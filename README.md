# aws-msp-mb

![Release](https://img.shields.io/github/v/release/scriptbuzz/aws-msp-mb?sort=semver&color=success)
![Terraform](https://img.shields.io/badge/Terraform-1.10%2B-7B42BC?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-ECS%20Fargate-FF9900?logo=amazonaws&logoColor=white)
![CI/CD](https://img.shields.io/badge/CI%2FCD-CodePipeline%20V2-527FFF?logo=awscodepipeline&logoColor=white)
![Deploy](https://img.shields.io/badge/deploy-blue%2Fgreen-2496ED)

*Last updated: 2026-07-06 11:09*

Monorepo supporting the provisioning of AWS solutions required to pass the
**AWS MSP audit**. It is **multi-control**: controls are opt-in (feature-flagged),
so you provision only what you choose. The first control in scope is
**Release Management** — but the structure is built to take more.
See the **[controls registry](docs/CONTROLS.md)** for what's covered and how to add a control.

> **Status: Release Management deployed & operational in AWS (sandbox account).** The
> pipeline runs end-to-end — Source → Build → dev → test → stage → change-record →
> manual approval → prod blue/green — and the prod site is live. Audit evidence is
> captured and automated rollback has been demonstrated (zero downtime).
> See [docs/STATUS.md](docs/STATUS.md) for the running status log and
> [docs/evidence/release-management/EVIDENCE.md](docs/evidence/release-management/EVIDENCE.md) for the proof.

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

**Design & reference**
- [Controls registry](docs/CONTROLS.md) — what controls are covered + how to add one
- [Release Management design](docs/RELEASE_MANAGEMENT_DESIGN.md) — decisions, architecture, scorecards
- [Branch & release strategy](docs/BRANCH_AND_RELEASE_STRATEGY.md) — how changes flow to prod

**Operate**
- [Rollout runbook](docs/ROLLOUT.md) — stage-by-stage provisioning (`scripts/rollout.sh`)
- [AWS account setup](docs/AWS_ACCOUNT_SETUP.md) — provision the deploy account via Control Tower + SSO
- [Manual operations](docs/MANUAL_OPERATIONS.md) — the human-required steps and why they can't be automated
- [Demo script](docs/DEMO.md) — followable end-to-end walkthrough incl. automated rollback
- [Security / secrets handling](SECURITY.md) — what's never committed + the pre-commit secret scanner (`git config core.hooksPath .githooks`)

**Status & evidence**
- [Changelog](CHANGELOG.md) — versioned release history
- [Status log](docs/STATUS.md) — running 3P status entries
- [Audit evidence](docs/evidence/release-management/EVIDENCE.md) — first-release proof mapped to the control
- Interactive diagram — `web/index.html` (open in a browser)
