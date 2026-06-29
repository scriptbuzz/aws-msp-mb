# module: iam

All least-privilege roles + the deny-direct-deploy guardrail.

**Provisions (planned):**
- **CodePipeline service role** — invoke CodeBuild, read/write artifact bucket, use the CodeConnection
- **CodeBuild service role** — read/write state bucket, push to ECR, run Terraform, deploy ECS
- **CodeDeploy service role** — manage ECS blue/green deployments
- **ECS task execution role** — pull from ECR, write logs
- **ECS task role** — app runtime perms (minimal for a static site)
- **Deny-direct-deploy IAM policy** (decision #12) — account-level policy ensuring
  production deploys only happen via the pipeline, not manual `terraform apply` / console

`msp-control`: OPS06 + the GAP guardrail ("deploys only via pipeline").

*Placeholder — `.tf` to be added.*
