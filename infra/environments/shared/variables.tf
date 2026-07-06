variable "region" {
  type    = string
  default = "us-east-1"
}

variable "region_code" {
  description = "Short region code used in resource names"
  type        = string
  default     = "use1"
}

variable "org" {
  description = "Org/resource prefix (decision #9)"
  type        = string
  default     = "mb"
}

variable "repo_name" {
  description = "Repo tag value"
  type        = string
  default     = "aws-msp-mb"
}

variable "enable_release_management" {
  description = "Feature flag (CONTROLS.md): provision the Release Management control"
  type        = bool
  default     = true
}

variable "full_repository_id" {
  description = "GitHub owner/repo the pipeline sources from"
  type        = string
  default     = "scriptbuzz/aws-msp-mb"
}

variable "branch" {
  type    = string
  default = "main"
}

variable "artifact_bucket_name" {
  description = "Pre-created pipeline artifact bucket (bootstrap step — see environments/README)"
  type        = string
}

variable "github_token_ssm_param" {
  description = "Optional SSM SecureString parameter with a GitHub token for the change-record issue; empty = artifact-only change record"
  type        = string
  default     = ""
}
