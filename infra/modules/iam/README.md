# module: iam

*Last updated: 2026-07-02 13:23*

All least-privilege roles + the deny-direct-deploy guardrail.

**Provisions:**
- **CodePipeline service role** — invoke CodeBuild, read/write artifact bucket,
  use the CodeConnection, create prod CodeDeploy deployments, register task defs
- **CodeBuild service role** — push to ECR, register task defs, update env
  services (scale-to-zero deploys), read the optional GitHub-token SSM param
- **CodeDeploy service role** — AWS-managed `AWSCodeDeployRoleForECS`
- **ECS task execution role** — pull from ECR, write logs (AWS-managed policy)
- **ECS task role** — empty (a static site needs no runtime perms)
- **Deny-direct-deploy IAM policy** (decision #12) — denies non-pipeline mutation
  of the prod ECS service / prod CodeDeploy deployments

> **Manual step:** attach the deny policy (output
> `deny_direct_prod_deploy_policy_arn`) to human roles / SSO permission sets.
> Identity Center permission sets live in the management account, outside this
> account's Terraform scope.

`msp-control`: OPS06 + the GAP guardrail ("deploys only via pipeline").
