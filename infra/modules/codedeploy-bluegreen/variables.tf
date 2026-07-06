variable "name_prefix" {
  description = "Resource name prefix, e.g. mb-prod-use1"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "Subnets for the ALB (needs 2 AZs)"
  type        = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "ecs_service_name" {
  description = "Prod ECS service (deployment_controller = CODE_DEPLOY)"
  type        = string
}

variable "codedeploy_role_arn" {
  type = string
}

variable "container_port" {
  type    = number
  default = 80
}

variable "health_check_path" {
  type    = string
  default = "/"
}

variable "deployment_config_name" {
  description = "Traffic-shift shape: all-at-once is the simplest that demonstrates rollback; switch to Canary10Percent5Minutes for a slower shift"
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
}

variable "enable_test_listener" {
  description = "Expose port 8080 for pre-shift validation of the green task set"
  type        = bool
  default     = true
}

variable "termination_wait_minutes" {
  description = "Bake window before the old (blue) task set is terminated"
  type        = number
  default     = 5
}

variable "alarm_5xx_threshold" {
  description = "Target 5xx count per minute that stops + rolls back a deployment"
  type        = number
  default     = 5
}
