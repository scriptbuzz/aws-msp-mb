variable "name_prefix" {
  description = "Resource name prefix, e.g. mb-use1"
  type        = string
}

variable "full_repository_id" {
  description = "GitHub owner/repo, e.g. scriptbuzz/aws-msp-mb"
  type        = string
}

variable "branch" {
  description = "Branch whose app/** pushes trigger the pipeline"
  type        = string
  default     = "main"
}

variable "artifact_bucket_name" {
  description = "Pre-created S3 bucket for pipeline artifacts (bootstrap step)"
  type        = string
}

variable "codepipeline_role_arn" {
  type = string
}

variable "codebuild_role_arn" {
  type = string
}

variable "ecr_repository_url" {
  type = string
}

variable "ecr_repository_name" {
  type = string
}

variable "cluster_name" {
  description = "Shared ECS cluster the lower-env deploys target"
  type        = string
}

variable "lower_envs" {
  description = "Lower environments in promotion order; names must match the env roots"
  type        = list(string)
  default     = ["dev", "test", "stage"]
}

variable "env_prefix" {
  description = "Org prefix for env-scoped names, e.g. mb (service = <env_prefix>-<env>-<region_code>-app-svc)"
  type        = string
}

variable "region_code" {
  description = "Short region code used in names, e.g. use1"
  type        = string
}

variable "container_name" {
  type    = string
  default = "app"
}

variable "task_execution_role_arn" {
  description = "Rendered into taskdef.json at build time"
  type        = string
}

variable "task_role_arn" {
  description = "Rendered into taskdef.json at build time"
  type        = string
}

variable "codedeploy_app_name" {
  description = "Prod CodeDeploy application name (by convention — created by the prod root)"
  type        = string
}

variable "codedeploy_deployment_group_name" {
  description = "Prod CodeDeploy deployment group name (by convention — created by the prod root)"
  type        = string
}

variable "github_token_ssm_param" {
  description = "Optional SSM SecureString parameter holding a GitHub token (repo scope) for the change-record issue; empty = change record is stored as an S3 artifact only"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  type    = number
  default = 30
}
