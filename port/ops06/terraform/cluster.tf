# One ECS cluster shared by all four environments (Fargate — no compute cost
# while services are scaled to zero).

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled" # cost rule — enable only if debugging is ever needed
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-cluster" })
}
