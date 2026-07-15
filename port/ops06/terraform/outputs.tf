# Workload outputs (the scaffold owns output "account_id").

output "pipeline_name" {
  description = "App release pipeline (start manually until the GitHub connection is authorized)"
  value       = aws_codepipeline.app.name
}

output "github_connection_arn" {
  description = "CodeConnections ARN — authorize once in the console (comes up PENDING)"
  value       = aws_codestarconnections_connection.github.arn
}

output "github_connection_status" {
  description = "PENDING until authorized in the console"
  value       = aws_codestarconnections_connection.github.connection_status
}

output "prod_site_url" {
  description = "Prod site (serves 503 until the first app-pipeline release)"
  value       = "http://${aws_lb.prod.dns_name}/"
}

output "ecr_repository_url" {
  description = "App image repository"
  value       = aws_ecr_repository.app.repository_url
}

output "artifact_bucket_name" {
  description = "App pipeline artifact store"
  value       = aws_s3_bucket.artifacts.bucket
}

output "cluster_name" {
  description = "ECS cluster shared by all four environments"
  value       = aws_ecs_cluster.main.name
}

output "deny_direct_prod_deploy_policy_arn" {
  description = "Guardrail policy to attach to human roles (manual, optional for the demo)"
  value       = aws_iam_policy.deny_direct_prod_deploy.arn
}
