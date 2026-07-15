# Workload variables — every one has a default; nothing here is required at plan
# time. The scaffold owns owner/project/environment/expiration_date; these are
# additive and app-scoped only.

variable "app_name" {
  description = "Resource name prefix for this workload (kebab-case, unique per demo)"
  type        = string
  default     = "aws-msp-ops06"
}

variable "region_code" {
  description = "Short naming token embedded in env-scoped resource names (kept as 'use1' because the app repo's buildspecs derive names as <app_name>-<env>-<region_code>-app)"
  type        = string
  default     = "use1"
}

variable "vpc_cidr" {
  description = "CIDR for the workload VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of AZs / public subnets"
  type        = number
  default     = 2
}

variable "container_name" {
  description = "Container name inside task definitions (the app repo's appspec/taskdef expect 'app')"
  type        = string
  default     = "app"
}

variable "container_port" {
  description = "Container/listener port"
  type        = number
  default     = 80
}

variable "cpu" {
  description = "Fargate task CPU units"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory (MiB)"
  type        = number
  default     = 512
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the prod ALB (80 + test listener 8080)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "task_ingress_cidrs" {
  description = "CIDRs allowed to reach task public IPs on the container port (lower-env validation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "lower_envs" {
  description = "Scale-to-zero promotion environments, in pipeline order"
  type        = list(string)
  default     = ["dev", "test", "stage"]
}

variable "log_retention_days" {
  description = "CloudWatch log retention for app + build logs"
  type        = number
  default     = 30
}

variable "keep_last_images" {
  description = "ECR lifecycle: number of images to retain"
  type        = number
  default     = 10
}

variable "health_check_path" {
  description = "ALB target group health check path"
  type        = string
  default     = "/"
}

variable "deployment_config_name" {
  description = "CodeDeploy ECS deployment config for prod blue/green"
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
}

variable "enable_test_listener" {
  description = "Create the :8080 test listener for pre-shift validation"
  type        = bool
  default     = true
}

variable "termination_wait_minutes" {
  description = "Minutes to keep the old (blue) task set after a successful shift (0 = terminate immediately)"
  type        = number
  default     = 0
}

variable "alarm_5xx_threshold" {
  description = "Target 5xx count per minute that stops + rolls back a prod deployment"
  type        = number
  default     = 5
}

variable "full_repository_id" {
  description = "GitHub owner/repo the app pipeline sources from"
  type        = string
  default     = "scriptbuzz/aws-msp-mb"
}

variable "branch" {
  description = "Release branch the app pipeline watches"
  type        = string
  default     = "main"
}

variable "github_token_ssm_param" {
  description = "Optional SSM SecureString parameter holding a GitHub token for change-record issues; empty = artifact-only change records"
  type        = string
  default     = ""
}

# --- Naming convention (single source for every resource name) -------------------

locals {
  # Shared-scope names: <app_name>-<region_code>-*
  name_prefix = "${var.app_name}-${var.region_code}"

  # Env-scoped names: <app_name>-<env>-<region_code>-app — the app repo's
  # buildspecs reconstruct these from ENV_PREFIX/ENV_NAME/REGION_CODE, so the
  # pattern is load-bearing.
  env_family  = { for env in concat(var.lower_envs, ["prod"]) : env => "${var.app_name}-${env}-${var.region_code}-app" }
  env_service = { for env, family in local.env_family : env => "${family}-svc" }

  prod_prefix           = "${var.app_name}-prod-${var.region_code}"
  codedeploy_app_name   = "${local.prod_prefix}-cd-app"
  codedeploy_group_name = "${local.prod_prefix}-cd-group"

  artifact_bucket_name = "${var.app_name}-artifacts-${data.aws_caller_identity.current.account_id}"
}
