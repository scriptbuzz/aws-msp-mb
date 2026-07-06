locals {
  # Env-scoped names by convention — must match what the env roots create.
  env_family  = { for env in concat(var.lower_envs, ["prod"]) : env => "${var.env_prefix}-${env}-${var.region_code}-app" }
  env_service = { for env, family in local.env_family : env => "${family}-svc" }
}

# --- GitHub connection ---------------------------------------------------------
# Comes up PENDING; authorize the OAuth handshake once in the console
# (Developer Tools -> Settings -> Connections). Manual task #2 in design §11.

resource "aws_codestarconnections_connection" "github" {
  name          = "${var.name_prefix}-github"
  provider_type = "GitHub"
}

# --- CodeBuild projects ----------------------------------------------------------

resource "aws_cloudwatch_log_group" "build" {
  name              = "/codebuild/${var.name_prefix}-cb-build"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "deploy_env" {
  name              = "/codebuild/${var.name_prefix}-cb-deploy-env"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "change_record" {
  name              = "/codebuild/${var.name_prefix}-cb-change-record"
  retention_in_days = var.log_retention_days
}

# Build: container image -> ECR by digest; tests; reserved no-op security-scan (design §8a).
resource "aws_codebuild_project" "build" {
  name         = "${var.name_prefix}-cb-build"
  description  = "Build app image, run tests, push to ECR by immutable digest"
  service_role = var.codebuild_role_arn

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
      value = var.ecr_repository_url
    }
    environment_variable {
      name  = "ECR_REPO_NAME"
      value = var.ecr_repository_name
    }
    environment_variable {
      name  = "CONTAINER_NAME"
      value = var.container_name
    }
    environment_variable {
      name  = "TASK_EXECUTION_ROLE_ARN"
      value = var.task_execution_role_arn
    }
    environment_variable {
      name  = "TASK_ROLE_ARN"
      value = var.task_role_arn
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
}

# Lower-env deploy: scale 0->1, register new task-def revision, validate, scale back to 0.
# One project reused for dev/test/stage; ENV_NAME is set per pipeline action.
resource "aws_codebuild_project" "deploy_env" {
  name         = "${var.name_prefix}-cb-deploy-env"
  description  = "Rolling deploy to a scale-to-zero lower env (ENV_NAME set per stage)"
  service_role = var.codebuild_role_arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "CLUSTER_NAME"
      value = var.cluster_name
    }
    environment_variable {
      name  = "ENV_PREFIX"
      value = var.env_prefix
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
}

# ITSM change record (decision #19): GitHub issue tagged with the artifact digest.
resource "aws_codebuild_project" "change_record" {
  name         = "${var.name_prefix}-cb-change-record"
  description  = "Open the GitHub-issue change record for the prod deploy"
  service_role = var.codebuild_role_arn

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
}

# --- The pipeline (V2 — path-filtered trigger) -----------------------------------

resource "aws_codepipeline" "app" {
  name          = "${var.name_prefix}-pipeline-app"
  role_arn      = var.codepipeline_role_arn
  pipeline_type = "V2"

  artifact_store {
    location = var.artifact_bucket_name
    type     = "S3"
  }

  # Fire only on app/** changes on the release branch (design: monorepo path filter).
  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      push {
        branches {
          includes = [var.branch]
        }
        # Both patterns: "app/*" matches direct children (e.g. app/VERSION,
        # app/index.html) and "app/**" matches nested paths. CodePipeline's
        # glob does not treat "app/**" as covering direct children.
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

    # Change record first, so the approver sees the linked issue/digest.
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
        CustomData = "Approve the prod blue/green deploy. The change record (GitHub issue / ChangeRecordArtifact) references the exact image digest."
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
        ApplicationName                = var.codedeploy_app_name
        DeploymentGroupName            = var.codedeploy_deployment_group_name
        TaskDefinitionTemplateArtifact = "BuildArtifact"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "BuildArtifact"
        AppSpecTemplatePath            = "appspec.yaml"
        Image1ArtifactName             = "BuildArtifact"
        Image1ContainerName            = "IMAGE1_NAME"
      }
    }
  }
}
