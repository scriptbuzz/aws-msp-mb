# Module-needed lookups. The caller identity is the scaffold's
# (data.aws_caller_identity.current in main.tf) — referenced, never redeclared.

data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition
}
