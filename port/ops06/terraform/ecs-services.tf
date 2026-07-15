# Four environments on one cluster. dev/test/stage are scale-to-zero rolling
# services (the app pipeline flips desired_count 0->1, validates, then back to
# 0). prod is always-on under the CODE_DEPLOY controller (blue/green).
#
# Every task definition starts on the ":bootstrap" image tag, which does not
# exist until the app pipeline's first release pushes real images — so lower
# envs sit at 0 tasks and prod serves 503 through the ALB until that release.
# Terraform ignores task_definition/desired_count/load_balancer afterward: the
# pipeline and CodeDeploy own them at runtime.

locals {
  lower_family = { for env in var.lower_envs : env => local.env_family[env] }
}

# --- Lower environments (dev / test / stage) --------------------------------------

resource "aws_cloudwatch_log_group" "env" {
  for_each = local.lower_family

  name              = "/ecs/${each.value}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, { Name = "/ecs/${each.value}" })
}

resource "aws_ecs_task_definition" "env" {
  for_each = local.lower_family

  family                   = each.value
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = var.container_name
    image     = "${aws_ecr_repository.app.repository_url}:bootstrap"
    essential = true
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.env[each.key].name
        awslogs-region        = local.region
        awslogs-stream-prefix = var.container_name
      }
    }
  }])

  tags = merge(local.common_tags, { Name = each.value })
}

resource "aws_ecs_service" "env" {
  for_each = local.lower_family

  name            = "${each.value}-svc"
  cluster         = aws_ecs_cluster.main.arn
  task_definition = aws_ecs_task_definition.env[each.key].arn
  desired_count   = 0 # scale-to-zero; the app pipeline flips this during deploys
  launch_type     = "FARGATE"

  deployment_controller {
    type = "ECS"
  }

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true # public-subnet/no-NAT topology: needed to pull from ECR
  }

  # The app pipeline owns deploys after creation.
  lifecycle {
    ignore_changes = [task_definition, desired_count, load_balancer]
  }

  tags = merge(local.common_tags, { Name = "${each.value}-svc" })
}

# --- prod (always-on, blue/green) --------------------------------------------------

resource "aws_cloudwatch_log_group" "prod" {
  name              = "/ecs/${local.env_family["prod"]}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, { Name = "/ecs/${local.env_family["prod"]}" })
}

resource "aws_ecs_task_definition" "prod" {
  family                   = local.env_family["prod"]
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = var.container_name
    image     = "${aws_ecr_repository.app.repository_url}:bootstrap"
    essential = true
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.prod.name
        awslogs-region        = local.region
        awslogs-stream-prefix = var.container_name
      }
    }
  }])

  tags = merge(local.common_tags, { Name = local.env_family["prod"] })
}

resource "aws_ecs_service" "prod" {
  name            = local.env_service["prod"]
  cluster         = aws_ecs_cluster.main.arn
  task_definition = aws_ecs_task_definition.prod.arn
  desired_count   = 1 # always-on
  launch_type     = "FARGATE"

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = 30

  # CodeDeploy retargets the load balancer during blue/green; the pipeline
  # registers task-definition revisions. Terraform must not fight either.
  lifecycle {
    ignore_changes = [task_definition, desired_count, load_balancer]
  }

  tags = merge(local.common_tags, { Name = local.env_service["prod"] })
}
