# Container registry. Immutable tags: promotion through the app pipeline is by
# digest, tags can never be repointed. force_delete keeps teardown clean.

resource "aws_ecr_repository" "app" {
  name         = "${local.name_prefix}-ecr-app"
  force_delete = true

  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ecr-app" })
}

resource "aws_ecr_lifecycle_policy" "keep_last" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${var.keep_last_images} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.keep_last_images
      }
      action = { type = "expire" }
    }]
  })
}
