# stage — scale-to-zero, rolling, no ALB. The pipeline scales 0->1, deploys,
# validates, and scales back to 0 (decision #20).

locals {
  env = "stage"
}

data "terraform_remote_state" "shared" {
  backend = "s3"

  config = {
    bucket = var.state_bucket_name
    key    = var.shared_state_key
    region = var.region
  }
}

module "app" {
  count  = var.enable_release_management ? 1 : 0
  source = "../../modules/ecs-service"

  name            = "${var.org}-${local.env}-${var.region_code}-app"
  cluster_arn     = data.terraform_remote_state.shared.outputs.cluster_arn
  deployment_mode = "rolling"
  desired_count   = 0 # scale-to-zero; the pipeline flips this during deploys

  subnet_ids         = data.terraform_remote_state.shared.outputs.public_subnet_ids
  security_group_ids = [data.terraform_remote_state.shared.outputs.task_security_group_id]

  # Never pulled while desired_count = 0; the pipeline registers revisions
  # with real digests from the first run on.
  image = "${data.terraform_remote_state.shared.outputs.ecr_repository_url}:bootstrap"

  execution_role_arn = data.terraform_remote_state.shared.outputs.task_execution_role_arn
  task_role_arn      = data.terraform_remote_state.shared.outputs.task_role_arn
}
