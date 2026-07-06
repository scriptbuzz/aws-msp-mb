variable "name" {
  description = "Base name, e.g. mb-dev-use1-app (service becomes <name>-svc, task family <name>)"
  type        = string
}

variable "cluster_arn" {
  description = "Shared ECS cluster ARN"
  type        = string
}

variable "deployment_mode" {
  description = "rolling (lower envs) or blue_green (prod, CodeDeploy-controlled)"
  type        = string
  default     = "rolling"

  validation {
    condition     = contains(["rolling", "blue_green"], var.deployment_mode)
    error_message = "deployment_mode must be \"rolling\" or \"blue_green\"."
  }
}

variable "desired_count" {
  description = "0 for scale-to-zero lower envs; >=1 for prod"
  type        = number
  default     = 0
}

variable "subnet_ids" {
  description = "Public subnets the tasks run in (no-NAT topology)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups for the tasks"
  type        = list(string)
}

variable "target_group_arn" {
  description = "Blue target group ARN — prod/blue_green only; null for lower envs (no ALB)"
  type        = string
  default     = null
}

variable "container_name" {
  type    = string
  default = "app"
}

variable "container_port" {
  type    = number
  default = 80
}

variable "cpu" {
  description = "Smallest viable per cost rule (0.25 vCPU)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Smallest viable per cost rule (0.5 GB)"
  type        = number
  default     = 512
}

variable "image" {
  description = "Initial container image; the pipeline registers new revisions with real digests after this"
  type        = string
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}
