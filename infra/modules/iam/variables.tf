variable "name_prefix" {
  description = "Resource name prefix, e.g. mb-use1"
  type        = string
}

variable "env_prefix" {
  description = "Prefix env-scoped resources share with the env inserted, e.g. mb (yields mb-<env>-use1-*)"
  type        = string
}

variable "region_code" {
  description = "Short region code used in names, e.g. use1"
  type        = string
}

variable "cluster_name" {
  description = "Shared ECS cluster name (for scoping service ARNs)"
  type        = string
}

variable "artifact_bucket_name" {
  description = "Pre-created S3 bucket for pipeline artifacts (bootstrap step)"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN of the app ECR repository"
  type        = string
}

variable "connection_arn" {
  description = "CodeConnections connection ARN (GitHub)"
  type        = string
}

variable "github_token_ssm_param" {
  description = "Optional SSM SecureString parameter name holding a GitHub token for the change-record step; empty disables the permission"
  type        = string
  default     = ""
}
