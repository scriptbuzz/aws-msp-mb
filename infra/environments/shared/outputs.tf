# Consumed by the env roots via terraform_remote_state. All null when the
# control is disabled.

output "vpc_id" {
  value = one(module.network[*].vpc_id)
}

output "public_subnet_ids" {
  value = one(module.network[*].public_subnet_ids)
}

output "alb_security_group_id" {
  value = one(module.network[*].alb_security_group_id)
}

output "task_security_group_id" {
  value = one(module.network[*].task_security_group_id)
}

output "cluster_arn" {
  value = one(aws_ecs_cluster.shared[*].arn)
}

output "cluster_name" {
  value = one(aws_ecs_cluster.shared[*].name)
}

output "ecr_repository_url" {
  value = one(module.ecr[*].repository_url)
}

output "task_execution_role_arn" {
  value = one(module.iam[*].task_execution_role_arn)
}

output "task_role_arn" {
  value = one(module.iam[*].task_role_arn)
}

output "codedeploy_role_arn" {
  value = one(module.iam[*].codedeploy_role_arn)
}

output "deny_direct_prod_deploy_policy_arn" {
  description = "Attach to human roles / SSO permission sets (manual step)"
  value       = one(module.iam[*].deny_direct_prod_deploy_policy_arn)
}

output "github_connection_arn" {
  description = "Authorize once in the console (comes up PENDING)"
  value       = one(module.pipeline[*].connection_arn)
}

output "github_connection_status" {
  value = one(module.pipeline[*].connection_status)
}

output "pipeline_name" {
  value = one(module.pipeline[*].pipeline_name)
}
