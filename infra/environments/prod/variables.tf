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

variable "state_bucket_name" {
  description = "Terraform state bucket (same one backend.hcl points at) — used to read the shared root's outputs"
  type        = string
}

variable "shared_state_key" {
  description = "State key of the shared root"
  type        = string
  default     = "aws-msp-mb/shared/terraform.tfstate"
}

variable "deployment_config_name" {
  description = "CodeDeploy traffic-shift shape"
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
}
