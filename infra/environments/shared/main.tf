# Shared (once-per-account) layer of the Release Management control:
# network, ECR, IAM, ECS cluster, and the pipeline. The per-env service roots
# (dev/test/stage/prod) read this root's outputs via terraform_remote_state.

locals {
  count  = var.enable_release_management ? 1 : 0
  prefix = "${var.org}-${var.region_code}"

  # Prod blue/green names by convention — the prod root's codedeploy-bluegreen
  # module derives the same names from its prefix.
  codedeploy_app_name   = "${var.org}-prod-${var.region_code}-cd-app"
  codedeploy_group_name = "${var.org}-prod-${var.region_code}-cd-group"
}

module "network" {
  count  = local.count
  source = "../../modules/network"

  name_prefix = local.prefix
}

module "ecr" {
  count  = local.count
  source = "../../modules/ecr"

  name = "${local.prefix}-ecr-app"
}

resource "aws_ecs_cluster" "shared" {
  count = local.count
  name  = "${local.prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled" # cost rule — enable if debugging is ever needed
  }
}

module "iam" {
  count  = local.count
  source = "../../modules/iam"

  name_prefix            = local.prefix
  env_prefix             = var.org
  region_code            = var.region_code
  cluster_name           = aws_ecs_cluster.shared[0].name
  artifact_bucket_name   = var.artifact_bucket_name
  ecr_repository_arn     = module.ecr[0].repository_arn
  connection_arn         = module.pipeline[0].connection_arn
  github_token_ssm_param = var.github_token_ssm_param
}

module "pipeline" {
  count  = local.count
  source = "../../modules/pipeline"

  name_prefix          = local.prefix
  full_repository_id   = var.full_repository_id
  branch               = var.branch
  artifact_bucket_name = var.artifact_bucket_name

  codepipeline_role_arn   = module.iam[0].codepipeline_role_arn
  codebuild_role_arn      = module.iam[0].codebuild_role_arn
  task_execution_role_arn = module.iam[0].task_execution_role_arn
  task_role_arn           = module.iam[0].task_role_arn

  ecr_repository_url  = module.ecr[0].repository_url
  ecr_repository_name = module.ecr[0].repository_name
  cluster_name        = aws_ecs_cluster.shared[0].name
  env_prefix          = var.org
  region_code         = var.region_code

  codedeploy_app_name              = local.codedeploy_app_name
  codedeploy_deployment_group_name = local.codedeploy_group_name

  github_token_ssm_param = var.github_token_ssm_param
}
