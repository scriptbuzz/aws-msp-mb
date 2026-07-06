output "alb_dns_name" {
  description = "Public URL of the prod site"
  value       = aws_lb.prod.dns_name
}

output "blue_target_group_arn" {
  description = "Attach the prod ECS service here at creation"
  value       = aws_lb_target_group.blue.arn
}

output "codedeploy_app_name" {
  value = aws_codedeploy_app.prod.name
}

output "codedeploy_deployment_group_name" {
  value = aws_codedeploy_deployment_group.prod.deployment_group_name
}
