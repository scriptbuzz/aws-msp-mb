# aws-msp-mb

Monorepo supporting the provisioning of AWS solutions required to pass the
**AWS MSP audit**. It is **multi-control**: controls are opt-in (feature-flagged),
so you provision only what you choose. The first control in scope is
**Release Management** — but the structure is built to take more.
See the **[controls registry](docs/CONTROLS.md)** for what's covered and how to add a control.

> **Status: design + scaffold. No AWS resources provisioned yet.**

## Standing rules

1. Cheapest resource that does the job.
2. Simplest solution that passes the **minimum** MSP validation requirement.
3. Fully portable — no hardcoded account/org IDs, regions, or emails. Everything is a variable.
4. Every recommendation reviewed for accuracy, cost, simplicity before adopting.

## Layout

```
aws-msp-mb/
├── app/                 # the static website (sample APPLICATION code) — what the pipeline deploys
├── infra/
│   ├── modules/         # reusable Terraform modules (account-agnostic)
│   └── environments/    # dev / test / stage / prod — the only place deployment-specific values live
├── pipeline/            # buildspec(s), appspec.yaml, taskdef.json
├── docs/                # design doc, branch+release strategy, evidence/
└── web/                 # interactive walkthrough + architecture diagram (draft)
```

## Key decisions (full list in the design doc)

| | |
|---|---|
| IaC | Terraform 1.10+ (S3-native state locking) |
| Region / prefix | `us-east-1` / `mb-` |
| CI/CD | CodePipeline **V2** → CodeBuild → CodeDeploy |
| Deploy target | ECS **Fargate**; **blue/green on prod only** |
| Environments | prod always-on; dev/test/stage **scale-to-zero**, no ALB |
| ITSM | GitHub-issue change record |
| Security scanners | deferred — pluggable hook reserved |
| Est. cost | ~$25/mo |

## Docs

- [Controls registry](docs/CONTROLS.md) — what controls are covered + how to add one
- [Release Management design](docs/RELEASE_MANAGEMENT_DESIGN.md) — decisions, architecture, scorecards
- [Branch & release strategy](docs/BRANCH_AND_RELEASE_STRATEGY.md) — how changes flow to prod
- [AWS account setup](docs/AWS_ACCOUNT_SETUP.md) — provision the deploy account via Control Tower + SSO
- Interactive diagram — `web/index.html` (open in a browser)
