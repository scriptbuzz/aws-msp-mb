provider "aws" {
  region = var.region

  default_tags {
    tags = {
      org         = var.org
      env         = "shared"
      project     = "aws-msp"
      msp-control = "release-management"
      managed-by  = "terraform"
      repo        = var.repo_name
    }
  }
}
