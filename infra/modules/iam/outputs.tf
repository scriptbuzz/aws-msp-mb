output "codepipeline_role_arn" {
  value = aws_iam_role.codepipeline.arn
}

output "codebuild_role_arn" {
  value = aws_iam_role.codebuild.arn
}

output "codedeploy_role_arn" {
  value = aws_iam_role.codedeploy.arn
}

output "task_execution_role_arn" {
  value = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "deny_direct_prod_deploy_policy_arn" {
  description = "Attach to human roles / SSO permission sets (manual step)"
  value       = aws_iam_policy.deny_direct_prod_deploy.arn
}
