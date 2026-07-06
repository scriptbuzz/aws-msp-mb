resource "aws_ecr_repository" "app" {
  name         = var.name
  force_delete = var.force_delete

  # Immutable tags — promotion is by digest, tags can never be repointed.
  image_tag_mutability = "IMMUTABLE"

  # ECR basic scanning (free). Enhanced/Inspector deferred with the other scanners (design §8a).
  image_scanning_configuration {
    scan_on_push = true
  }
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
