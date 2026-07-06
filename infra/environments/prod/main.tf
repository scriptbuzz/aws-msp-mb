# prod — always-on (the live site), CodeDeploy blue/green, the only env with
# an ALB (decision #20). ~$25/mo: ALB ~$16 + one 0.25vCPU Fargate task ~$9.
#
# NOTE (first apply): push a bootstrap image first so the always-on task has
# something to run —
#   docker build -t <ecr_repository_url>:bootstrap app/ && docker push <ecr_repository_url>:bootstrap
# (ecr_repository_url is a shared-root output; see environments/README.md.)

locals {
  env    = "prod"
  prefix = "${var.org}-${local.env}-${var.region_code}"
}

data "terraform_remote_state" "shared" {
  backend = "s3"

  config = {
    bucket = var.state_bucket_name
    key    = var.shared_state_key
    region = var.region
  }
}

# ALB + blue/green target groups + CodeDeploy app/deployment group.
# Names derived from local.prefix match what the shared root's pipeline expects.
module "bluegreen" {
  count  = var.enable_release_management ? 1 : 0
  source = "../../modules/codedeploy-bluegreen"

  name_prefix           = local.prefix
  vpc_id                = data.terraform_remote_state.shared.outputs.vpc_id
  public_subnet_ids     = data.terraform_remote_state.shared.outputs.public_subnet_ids
  alb_security_group_id = data.terraform_remote_state.shared.outputs.alb_security_group_id
  cluster_name          = data.terraform_remote_state.shared.outputs.cluster_name
  ecs_service_name      = module.app[0].service_name
  codedeploy_role_arn   = data.terraform_remote_state.shared.outputs.codedeploy_role_arn

  deployment_config_name = var.deployment_config_name
}

module "app" {
  count  = var.enable_release_management ? 1 : 0
  source = "../../modules/ecs-service"

  name            = "${local.prefix}-app"
  cluster_arn     = data.terraform_remote_state.shared.outputs.cluster_arn
  deployment_mode = "blue_green"
  desired_count   = 1 # always-on

  subnet_ids         = data.terraform_remote_state.shared.outputs.public_subnet_ids
  security_group_ids = [data.terraform_remote_state.shared.outputs.task_security_group_id]
  target_group_arn   = module.bluegreen[0].blue_target_group_arn

  image = "${data.terraform_remote_state.shared.outputs.ecr_repository_url}:bootstrap"

  execution_role_arn = data.terraform_remote_state.shared.outputs.task_execution_role_arn
  task_role_arn      = data.terraform_remote_state.shared.outputs.task_role_arn
}
