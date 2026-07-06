provider "aws" {
  region = var.region

  default_tags {
    tags = {
      org         = var.org
      env         = local.env
      project     = "aws-msp"
      msp-control = "release-management"
      managed-by  = "terraform"
      repo        = var.repo_name
    }
  }
}
