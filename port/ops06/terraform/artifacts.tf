# Artifact store for the app pipeline (CodePipeline stage hand-offs).
# force_destroy: demo stack — teardown must not strand the bucket.

resource "aws_s3_bucket" "artifacts" {
  bucket        = local.artifact_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, { Name = local.artifact_bucket_name })
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
