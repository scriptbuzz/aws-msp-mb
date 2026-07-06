data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  region       = data.aws_region.current.name
  partition    = data.aws_partition.current.partition
  artifact_arn = "arn:${local.partition}:s3:::${var.artifact_bucket_name}"

  # Env-scoped resource patterns (services/taskdefs are named mb-<env>-use1-app*)
  service_arn_pattern = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:service/${var.cluster_name}/${var.env_prefix}-*-${var.region_code}-app-svc"
  taskdef_arn_pattern = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:task-definition/${var.env_prefix}-*-${var.region_code}-app:*"
}

# --- ECS task execution role (pull image, write logs) -------------------------

resource "aws_iam_role" "task_execution" {
  name = "${var.name_prefix}-task-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- ECS task role (app runtime — static site needs nothing) ------------------

resource "aws_iam_role" "task" {
  name = "${var.name_prefix}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# --- CodeDeploy service role ---------------------------------------------------

resource "aws_iam_role" "codedeploy" {
  name = "${var.name_prefix}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_ecs" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AWSCodeDeployRoleForECS"
}

# --- CodeBuild service role ----------------------------------------------------

resource "aws_iam_role" "codebuild" {
  name = "${var.name_prefix}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.name_prefix}-codebuild-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/codebuild/${var.name_prefix}-*"
      },
      {
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = var.ecr_repository_arn
      },
      {
        Sid      = "ArtifactBucket"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = "${local.artifact_arn}/*"
      },
      {
        # Describe/List calls don't support resource-level scoping.
        Sid      = "EcsRead"
        Effect   = "Allow"
        Action   = ["ecs:DescribeTaskDefinition", "ecs:DescribeTasks", "ecs:ListTasks", "ecs:DescribeServices", "ecs:RegisterTaskDefinition", "ecs:TagResource"]
        Resource = "*"
      },
      {
        Sid      = "EcsDeploy"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService"]
        Resource = local.service_arn_pattern
      },
      {
        # Lower-env validation: resolve the task ENI to its public IP.
        Sid      = "EniRead"
        Effect   = "Allow"
        Action   = ["ec2:DescribeNetworkInterfaces"]
        Resource = "*"
      },
      {
        Sid      = "PassTaskRoles"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.task_execution.arn, aws_iam_role.task.arn]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      }
      ],
      var.github_token_ssm_param == "" ? [] : [{
        Sid      = "GithubTokenParam"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/${trimprefix(var.github_token_ssm_param, "/")}"
      }]
    )
  })
}

# --- CodePipeline service role -------------------------------------------------

resource "aws_iam_role" "codepipeline" {
  name = "${var.name_prefix}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "${var.name_prefix}-codepipeline-policy"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "UseGithubConnection"
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
        Resource = var.connection_arn
      },
      {
        Sid      = "ArtifactBucket"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketVersioning", "s3:ListBucket"]
        Resource = [local.artifact_arn, "${local.artifact_arn}/*"]
      },
      {
        Sid      = "RunBuilds"
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        Resource = "arn:${local.partition}:codebuild:${local.region}:${local.account_id}:project/${var.name_prefix}-*"
      },
      {
        Sid    = "ProdBlueGreen"
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:RegisterApplicationRevision"
        ]
        Resource = "arn:${local.partition}:codedeploy:${local.region}:${local.account_id}:*:${var.env_prefix}-prod-*"
      },
      {
        # Deployment configs are AWS-managed resources named CodeDeployDefault.*
        # (e.g. CodeDeployDefault.ECSAllAtOnce), so they fall outside the
        # mb-prod-* scope above and need their own read grant.
        Sid      = "DeploymentConfigRead"
        Effect   = "Allow"
        Action   = ["codedeploy:GetDeploymentConfig"]
        Resource = "arn:${local.partition}:codedeploy:${local.region}:${local.account_id}:deploymentconfig:*"
      },
      {
        # The CodeDeployToECS action registers the rendered task definition.
        Sid      = "RegisterTaskDef"
        Effect   = "Allow"
        Action   = ["ecs:RegisterTaskDefinition", "ecs:TagResource", "ecs:DescribeServices", "ecs:DescribeTaskDefinition"]
        Resource = "*"
      },
      {
        Sid      = "PassTaskRoles"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.task_execution.arn, aws_iam_role.task.arn]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      }
    ]
  })
}

# --- Deny-direct-deploy guardrail (decision #12) -------------------------------
# Account-level customer-managed policy: prod deploys happen ONLY via the
# pipeline. Attach to human roles / SSO permission sets (manual step — Identity
# Center permission sets live in the management account, out of this account's
# Terraform scope).

resource "aws_iam_policy" "deny_direct_prod_deploy" {
  name        = "${var.name_prefix}-deny-direct-prod-deploy"
  description = "Deny direct (non-pipeline) mutation of prod ECS service and prod CodeDeploy deployments"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyDirectProdEcs"
        Effect   = "Deny"
        Action   = ["ecs:UpdateService", "ecs:DeleteService", "ecs:UpdateServicePrimaryTaskSet", "ecs:StopTask"]
        Resource = "arn:${local.partition}:ecs:*:${local.account_id}:service/${var.cluster_name}/${var.env_prefix}-prod-*"
      },
      {
        Sid      = "DenyDirectProdCodeDeploy"
        Effect   = "Deny"
        Action   = ["codedeploy:CreateDeployment", "codedeploy:StopDeployment"]
        Resource = "arn:${local.partition}:codedeploy:*:${local.account_id}:deploymentgroup:${var.env_prefix}-prod-*/*"
      }
    ]
  })
}
