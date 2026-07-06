output "service_name" {
  value = aws_ecs_service.app.name
}

output "service_arn" {
  value = aws_ecs_service.app.id
}

output "task_definition_family" {
  value = aws_ecs_task_definition.app.family
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.app.name
}
