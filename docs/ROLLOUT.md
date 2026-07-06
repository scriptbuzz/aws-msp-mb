# Rollout — stage-gated, verifiable, undoable

*Last updated: 2026-07-03 15:13*

> **Current position (2026-07-03): all stages applied; first release ran end-to-end
> to a live prod site.** The pipeline (Stage 7) is operational. See
> [STATUS.md](STATUS.md). Prod is up at ~$25/mo while running — `scripts/rollout.sh
> undo prod` stops that cost; `undo-all` tears everything down.

The AWS rollout happens **one stage at a time**. Each stage is applied only with
explicit approval, verified before moving on, and each has an undo. Driver:
[`scripts/rollout.sh`](../scripts/rollout.sh) (reads `.env`; needs `aws sso login`).

```sh
scripts/rollout.sh status            # where am I?
scripts/rollout.sh apply  <stage>
scripts/rollout.sh verify <stage>
scripts/rollout.sh undo   <stage>
scripts/rollout.sh undo-all          # full teardown, reverse order
```

## Stage table

| # | Stage | Creates | Monthly cost | Verify | Undo |
|---|---|---|---|---|---|
| 1 | `bootstrap` | 2 S3 buckets (`mb-msp-tfstate-<acct>`, `mb-msp-artifacts-<acct>`) + writes each root's `backend.hcl`/`terraform.tfvars` | ~$0 (pennies for storage) | buckets exist, versioned | delete buckets (purges all versions — state is lost) |
| 2a | `shared-network` | VPC, 2 public subnets, IGW, route table, ALB + task security groups | $0 | VPC/subnets/SGs exist | targeted destroy |
| 2b | `shared-ecr` | ECR repo (immutable tags, scan-on-push, keep-last-10) | ~$0 | repo exists | targeted destroy |
| 2c | `shared-cluster` | ECS cluster (no compute) | $0 | cluster ACTIVE | targeted destroy |
| 2d | `shared-connection` | GitHub CodeConnection (comes up PENDING) | $0 | status PENDING → authorize → AVAILABLE | targeted destroy |
| 2e | `shared-iam` | 5 roles + deny-direct-prod-deploy policy | $0 | roles + policy exist | targeted destroy |
| 2f | `shared-pipeline` | CodeBuild ×3, log groups, CodePipeline V2 (full converging apply of the shared root) | ~$0 idle | pipeline + ECR checks, outputs | `undo shared` (whole root) |
| 3 | `dev` | dev ECS service (desired 0) + task def + log group | $0 idle | service ACTIVE, desired 0 | destroy |
| 4 | `test` | same for test | $0 idle | same | destroy |
| 5 | `stage` | same for stage | $0 idle | same | destroy |
| 6a | `prod-alb` | ALB, 2 target groups (blue/green), prod + test listeners | **~$16** (ALB) — billing starts here | ALB active, target groups exist | targeted destroy |
| 6b | `prod-service` | prod ECS service (desired 1, attached to blue TG) + task def + log group | **+~$9** (1 always-on task) | service ACTIVE desired 1 (running may be 0 pre-release) | targeted destroy |
| 6c | `prod-codedeploy` | CodeDeploy app + deployment group + 5xx alarm (full converging apply of the prod root) | ~$0 | CodeDeploy group, ALB URL (503 expected pre-release) | `undo prod` (whole root) |
| 7 | first release | *(no new infra)* — authorize GitHub connection, push repo, bump `app/VERSION`, merge → pipeline runs end-to-end | build minutes (pennies) | pipeline execution green; site serves the version | roll back via CodeDeploy / redeploy previous digest |

## Manual steps (cannot be scripted)

- **Done:** sandbox01 account (561521479906), SSO profile `sandbox01`, `.env`.
- **After stage 2d:** authorize the GitHub connection in the console —
  CodePipeline → Settings → Connections → `mb-use1-github` → *Update pending connection*.
- **Before stage 7:** `git push` (pipeline sources from GitHub `main`, path `app/**`).
- **Optional hardening:** attach the deny-direct-prod-deploy policy (shared output)
  to human permission sets; GitHub branch protection on `main`.

## Notes

- **No local Docker:** the prod service starts with a nonexistent `:bootstrap`
  image tag, so the ALB serves 503 until the first pipeline release (stage 7)
  deploys a real image via CodeDeploy. Deliberate — avoids needing Docker on
  this machine; CodeBuild does all image building.
- **Full teardown after testing:** `scripts/rollout.sh undo-all`
  (prod → stage → test → dev → shared → buckets). The ECR repo has
  `force_delete = true`, so images don't block destroy.
- Costs assume `us-east-1`, one 0.25 vCPU/0.5 GB Fargate task.
