variable "name_prefix" {
  description = "Resource name prefix, e.g. mb-use1"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of AZs / public subnets (ALB requires 2)"
  type        = number
  default     = 2
}

variable "container_port" {
  description = "Port the app container listens on"
  type        = number
  default     = 80
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the (prod) ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "task_ingress_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach tasks directly on the container port. Needed for
    lower-env validation: CodeBuild curls the task's public IP (no ALB in lower
    envs, and CodeBuild has no fixed egress IP without a NAT). The app is a
    public static site, so world-open here matches the prod ALB posture; tighten
    if the app ever serves non-public content.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
