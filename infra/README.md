# infra/ — Terraform

*Last updated: 2026-07-05 12:12*

All infrastructure as code. **Modules are account-agnostic**; the only place
deployment-specific values (account, region, names) live is `environments/`.

> **`modules/` is a shared library for ALL controls**, not just Release Management.
> The modules below are what Release Management uses; future controls
> (CloudTrail, Config, GuardDuty, Backup…) add their own modules alongside and
> compose them in `infra/platform/` (an account/org-level root, added when the
> first such control is scoped). See [../docs/CONTROLS.md](../docs/CONTROLS.md).

```
infra/
├── modules/                  # reusable, account-agnostic building blocks
│   ├── network/              # VPC, subnets, security groups
│   ├── ecr/                  # container image registry
│   ├── iam/                  # pipeline / build / deploy / task roles + deny-direct-deploy
│   ├── ecs-service/          # reusable Fargate service (rolling OR blue/green, scale-to-zero capable)
│   ├── codedeploy-bluegreen/ # CodeDeploy app + deployment group + ALB + 2 target groups (prod only)
│   └── pipeline/             # CodePipeline V2 + CodeBuild + CodeConnections
└── environments/
    ├── shared/               # once-per-account: network, ECR, IAM, cluster, pipeline
    ├── dev/                  # scale-to-zero, rolling, no ALB
    ├── test/                 # scale-to-zero, rolling, no ALB
    ├── stage/                # scale-to-zero, rolling, no ALB
    └── prod/                 # always-on, blue/green, ALB
```

## Conventions

- **Naming:** `mb-<env>-use1-<service>-<resource>-<suffix>`
- **Tags** (via provider `default_tags`): `org=mb`, `env`, `project=aws-msp`,
  `msp-control`, `managed-by=terraform`, `repo=aws-msp-mb`, `region=us-east-1`
- **State:** S3 backend with native locking (no DynamoDB). Backend values come
  from a per-deployment `backend.hcl` (never hardcoded in modules).
- **Portability:** no account IDs / org IDs / emails in modules — all variables.
  Account ID and partition are discovered via data sources where ARNs need them.
- **Network decision (recorded):** no NAT gateway, no private subnets — tasks
  run in public subnets with public IPs and restricted SGs (cheapest topology;
  see `modules/network/`).

## Deploy permissions (least-privilege)

**No AWS-managed policy is required.** The fully granular option is to attach the two
project policy files — nothing else:

- [`deploy-permissions-services.json`](deploy-permissions-services.json) — every
  service action the rollout performs (explicit action list; `mb-*`-scoped resources
  where the service supports it; region-pinned to `us-east-1`).
- [`deploy-permissions.json`](deploy-permissions.json) — the IAM subset: manage the
  `mb-*` roles/policies + conditional `iam:PassRole` to
  ECS/CodePipeline/CodeBuild/CodeDeploy.

If AWS-managed policies *are* available, `PowerUserAccess` + `deploy-permissions.json`
also works (PowerUser alone is insufficient — it excludes `iam:*`). Details, checklist
and rationale: [../docs/AWS_ACCOUNT_SETUP.md](../docs/AWS_ACCOUNT_SETUP.md) §B/§B2/§B3;
verify with `scripts/check-deploy-permissions.sh` (read-only).
