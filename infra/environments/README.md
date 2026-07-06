# environments/

*Last updated: 2026-07-05 12:12*

The **only** place deployment-specific values live. Each root calls the shared
modules with env-specific inputs + its own `backend.hcl` (S3 state key).
Porting to a new account/org = swap these values, nothing in `modules/` changes.

| Root | What it holds | desired_count (idle) | deployment_mode | ALB |
|---|---|---|---|---|
| **shared** | once-per-account layer: VPC, ECR, IAM, ECS cluster, the pipeline | — | — | — |
| dev | the dev service | 0 (scale-to-zero) | rolling | no |
| test | the test service | 0 (scale-to-zero) | rolling | no |
| stage | the stage service | 0 (scale-to-zero) | rolling | no |
| **prod** | the prod service + blue/green rig (ALB, TGs, CodeDeploy) | 1 (always-on) | **blue/green** | **yes** |

The env roots read the shared root's outputs via `terraform_remote_state`
(same state bucket). Prod↔pipeline wiring is by naming convention
(`mb-prod-use1-cd-app` etc.), so the roots stay independent.

Each root contains `main.tf`, `variables.tf`, `versions.tf`, `providers.tf`,
`outputs.tf`, plus **gitignored** local copies of `backend.hcl` and
`terraform.tfvars` (commit-safe `.example` files are provided for both).
The Release Management control is gated by `enable_release_management`
(default `true`) per [CONTROLS.md](../../docs/CONTROLS.md).

## Provisioning

Provisioning is driven stage-by-stage (bootstrap buckets → shared → dev/test/stage →
prod), each with verify + undo, by **[`scripts/rollout.sh`](../../scripts/rollout.sh)**.
The single source of truth for the stage table, apply order, and per-stage cost is
**[docs/ROLLOUT.md](../../docs/ROLLOUT.md)**. Human-required steps (GitHub connection
authorization, prod approval, attaching the deny-direct-prod-deploy policy) are catalogued
in [docs/MANUAL_OPERATIONS.md](../../docs/MANUAL_OPERATIONS.md).

Once provisioned, merges touching `app/**` drive deploys through the pipeline (design §3);
Terraform only changes when the infrastructure itself does.
