# The app release pipeline: GitHub -> Build -> dev -> test -> stage ->
# change-record + manual approval -> prod blue/green. This is the workload's
# own CI/CD chain (the Release Management control); it runs inside the demo
# account and is itself deployed by the platform pipeline.

# --- GitHub connection ---------------------------------------------------------
# Comes up PENDING; authorize the OAuth handshake once in the demo-account
# console (Developer Tools -> Settings -> Connections). Documented in the
# port workflow.

resource "aws_codestarconnections_connection" "github" {
  name          = "${local.name_prefix}-github"
  provider_type = "GitHub"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-github" })
}

# --- CodeBuild projects ----------------------------------------------------------

resource "aws_cloudwatch_log_group" "build" {
  name              = "/codebuild/${local.name_prefix}-cb-build"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, { Name = "/codebuild/${local.name_prefix}-cb-build" })
}

resource "aws_cloudwatch_log_group" "deploy_env" {
  name              = "/codebuild/${local.name_prefix}-cb-deploy-env"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, { Name = "/codebuild/${local.name_prefix}-cb-deploy-env" })
}

resource "aws_cloudwatch_log_group" "change_record" {
  name              = "/codebuild/${local.name_prefix}-cb-change-record"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, { Name = "/codebuild/${local.name_prefix}-cb-change-record" })
}

# Build: container image -> ECR by digest; smoke test; reserved no-op security-scan hook.
resource "aws_codebuild_project" "build" {
  name         = "${local.name_prefix}-cb-build"
  description  = "Build app image, run tests, push to ECR by immutable digest"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_MEDIUM"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true # docker build

    environment_variable {
      name  = "ECR_REPO_URL"
      value = aws_ecr_repository.app.repository_url
    }
    environment_variable {
      name  = "ECR_REPO_NAME"
      value = aws_ecr_repository.app.name
    }
    environment_variable {
      name  = "CONTAINER_NAME"
      value = var.container_name
    }
    environment_variable {
      name  = "TASK_EXECUTION_ROLE_ARN"
      value = aws_iam_role.task_execution.arn
    }
    environment_variable {
      name  = "TASK_ROLE_ARN"
      value = aws_iam_role.task.arn
    }
    environment_variable {
      name  = "PROD_FAMILY"
      value = local.env_family["prod"]
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "pipeline/buildspec.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-cb-build" })
}

# Lower-env deploy: scale 0->1, register new task-def revision, validate, scale
# back to 0. One project reused for dev/test/stage; ENV_NAME is set per stage.
resource "aws_codebuild_project" "deploy_env" {
  name         = "${local.name_prefix}-cb-deploy-env"
  description  = "Rolling deploy to a scale-to-zero lower env (ENV_NAME set per stage)"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "CLUSTER_NAME"
      value = aws_ecs_cluster.main.name
    }
    environment_variable {
      name  = "ENV_PREFIX"
      value = var.app_name
    }
    environment_variable {
      name  = "REGION_CODE"
      value = var.region_code
    }
    environment_variable {
      name  = "CONTAINER_NAME"
      value = var.container_name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "pipeline/deploy_env.buildspec.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.deploy_env.name
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-cb-deploy-env" })
}

# Change record: JSON artifact (always) + GitHub issue (when a token is configured).
resource "aws_codebuild_project" "change_record" {
  name         = "${local.name_prefix}-cb-change-record"
  description  = "Record the prod change (artifact digest, commit, execution) before approval"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "GITHUB_REPO"
      value = var.full_repository_id
    }
    environment_variable {
      name  = "GITHUB_TOKEN_SSM_PARAM"
      value = var.github_token_ssm_param
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "pipeline/change_record.buildspec.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.change_record.name
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-cb-change-record" })
}

# --- The pipeline (V2 — path-filtered trigger) -----------------------------------

resource "aws_codepipeline" "app" {
  name          = "${local.name_prefix}-pipeline-app"
  role_arn      = aws_iam_role.codepipeline.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  # Fire only on app/** changes on the release branch (monorepo path filter).
  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      push {
        branches {
          includes = [var.branch]
        }
        # Both patterns: "app/*" matches direct children (e.g. app/VERSION)
        # and "app/**" matches nested paths — CodePipeline's glob does not
        # treat "app/**" as covering direct children.
        file_paths {
          includes = ["app/*", "app/**"]
        }
      }
    }
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.github.arn
        FullRepositoryId     = var.full_repository_id
        BranchName           = var.branch
        OutputArtifactFormat = "CODE_ZIP"
        DetectChanges        = "false" # the V2 trigger above owns change detection
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]

      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }

  # Staged promotion: same digest through dev -> test -> stage (rolling, scale-to-zero).
  dynamic "stage" {
    for_each = var.lower_envs
    content {
      name = "Deploy-${stage.value}"
      action {
        name            = "Deploy"
        category        = "Build"
        owner           = "AWS"
        provider        = "CodeBuild"
        version         = "1"
        input_artifacts = ["BuildArtifact"]

        configuration = {
          ProjectName = aws_codebuild_project.deploy_env.name
          EnvironmentVariables = jsonencode([
            { name = "ENV_NAME", value = stage.value }
          ])
        }
      }
    }
  }

  stage {
    name = "Approve-prod"

    # Change record first, so the approver sees the recorded digest.
    action {
      name             = "ChangeRecord"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      run_order        = 1
      input_artifacts  = ["BuildArtifact"]
      output_artifacts = ["ChangeRecordArtifact"]

      configuration = {
        ProjectName = aws_codebuild_project.change_record.name
        EnvironmentVariables = jsonencode([
          { name = "PIPELINE_EXECUTION_ID", value = "#{codepipeline.PipelineExecutionId}" }
        ])
      }
    }

    action {
      name      = "ManualApproval"
      category  = "Approval"
      owner     = "AWS"
      provider  = "Manual"
      version   = "1"
      run_order = 2

      configuration = {
        CustomData = "Approve the prod blue/green deploy. The change record (ChangeRecordArtifact) references the exact image digest."
      }
    }
  }

  stage {
    name = "Deploy-prod"
    action {
      name            = "BlueGreen"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = "1"
      input_artifacts = ["BuildArtifact"]

      configuration = {
        ApplicationName                = aws_codedeploy_app.prod.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.prod.deployment_group_name
        TaskDefinitionTemplateArtifact = "BuildArtifact"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "BuildArtifact"
        AppSpecTemplatePath            = "appspec.yaml"
        Image1ArtifactName             = "BuildArtifact"
        Image1ContainerName            = "IMAGE1_NAME"
      }
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-pipeline-app" })
}
