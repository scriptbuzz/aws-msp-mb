# The production-only blue/green rig: ALB + two target groups + CodeDeploy
# application/deployment group with alarm-driven auto-rollback.

resource "aws_lb" "prod" {
  name               = "${local.prod_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = merge(local.common_tags, { Name = "${local.prod_prefix}-alb" })
}

resource "aws_lb_target_group" "blue" {
  name        = "${local.prod_prefix}-tg-blue"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200-299"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, { Name = "${local.prod_prefix}-tg-blue" })
}

resource "aws_lb_target_group" "green" {
  name        = "${local.prod_prefix}-tg-green" # 32 chars — at the ALB naming limit
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200-299"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, { Name = "${local.prod_prefix}-tg-green" })
}

resource "aws_lb_listener" "prod" {
  load_balancer_arn = aws_lb.prod.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  # CodeDeploy swaps the listener between blue and green on every deployment.
  lifecycle {
    ignore_changes = [default_action]
  }

  tags = merge(local.common_tags, { Name = "${local.prod_prefix}-listener" })
}

resource "aws_lb_listener" "test" {
  count = var.enable_test_listener ? 1 : 0

  load_balancer_arn = aws_lb.prod.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green.arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }

  tags = merge(local.common_tags, { Name = "${local.prod_prefix}-test-listener" })
}

# Rollback alarm: target 5xx spikes on the ALB stop the deployment and roll back.
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${local.prod_prefix}-alb-target-5xx"
  alarm_description   = "Target 5xx on the prod ALB — trips CodeDeploy auto-rollback"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = var.alarm_5xx_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.prod.arn_suffix
  }

  tags = merge(local.common_tags, { Name = "${local.prod_prefix}-alb-target-5xx" })
}

resource "aws_codedeploy_app" "prod" {
  name             = local.codedeploy_app_name
  compute_platform = "ECS"

  tags = merge(local.common_tags, { Name = local.codedeploy_app_name })
}

resource "aws_codedeploy_deployment_group" "prod" {
  app_name               = aws_codedeploy_app.prod.name
  deployment_group_name  = local.codedeploy_group_name
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = var.deployment_config_name

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.main.name
    service_name = aws_ecs_service.prod.name
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = var.termination_wait_minutes
    }
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.prod.arn]
      }

      dynamic "test_traffic_route" {
        for_each = var.enable_test_listener ? [1] : []
        content {
          listener_arns = [aws_lb_listener.test[0].arn]
        }
      }

      target_group {
        name = aws_lb_target_group.blue.name
      }
      target_group {
        name = aws_lb_target_group.green.name
      }
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  alarm_configuration {
    enabled = true
    alarms  = [aws_cloudwatch_metric_alarm.target_5xx.alarm_name]
  }

  tags = merge(local.common_tags, { Name = local.codedeploy_group_name })
}
