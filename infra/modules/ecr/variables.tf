variable "name" {
  description = "Repository name, e.g. mb-use1-ecr-app"
  type        = string
}

variable "keep_last_images" {
  description = "Lifecycle policy: number of images to retain (cost control)"
  type        = number
  default     = 10
}

variable "force_delete" {
  description = "Allow deleting the repo even if it contains images (sample project: easy teardown)"
  type        = bool
  default     = true
}
