output "connection_arn" {
  description = "Authorize this connection once in the console (comes up PENDING)"
  value       = aws_codestarconnections_connection.github.arn
}

output "connection_status" {
  value = aws_codestarconnections_connection.github.connection_status
}

output "pipeline_name" {
  value = aws_codepipeline.app.name
}
