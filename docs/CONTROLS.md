# MSP Controls Registry

*Last updated: 2026-07-04 14:31*

This repo is **multi-control**: it provisions the AWS solutions for one or more
AWS MSP audit controls. Controls are **opt-in** — you pick which to provision via
feature flags (`enable_<control>`), per the cheapest/simplest rules. This file is
the single index of what's covered.

## Registry

| Control | Domain | Status | Modules used | Composition root | Evidence | Design doc |
|---|---|---|---|---|---|---|
| **Release Management** (OPS06) | Cloud Ops | 🟢 deployed & operational (first release live) | network, ecr, iam, ecs-service, codedeploy-bluegreen, pipeline | `infra/environments/*` | [`docs/evidence/release-management/`](evidence/release-management/EVIDENCE.md) (captured; rollback demo pending) | [RELEASE_MANAGEMENT_DESIGN.md](RELEASE_MANAGEMENT_DESIGN.md) · [BRANCH_AND_RELEASE_STRATEGY.md](BRANCH_AND_RELEASE_STRATEGY.md) |
| _(future)_ Security logging | Security | ⬜ not started | _(cloudtrail, config…)_ | `infra/platform/` | — | — |
| _(future)_ Threat detection | Security | ⬜ not started | _(guardduty, security-hub…)_ | `infra/platform/` | — | — |
| _(future)_ Backup / DR | Resilience | ⬜ not started | _(backup…)_ | `infra/platform/` | — | — |

> Add rows as controls are scoped. The "future" rows are placeholders showing the
> intended shape — not commitments.

## Two composition paths

| Path | For | Lifecycle |
|---|---|---|
| `infra/environments/{dev,test,stage,prod}` | **app-centric** controls (e.g. Release Management deploys an app through environments) | per-environment |
| `infra/platform/` *(added when first needed)* | **account/org-level** controls (CloudTrail, Config, GuardDuty, Backup…) | provisioned once per account |

Both draw from the same shared `infra/modules/` library.

## How to add a new control

1. **Modules** — add reusable building block(s) under `infra/modules/<name>/`.
2. **Composition** — wire them into the right root (`environments/` or `platform/`),
   gated by a feature flag: `enable_<control>` in that root's tfvars; module blocks
   use `count = var.enable_<control> ? 1 : 0`.
3. **Docs + evidence** — add a design note and a `docs/evidence/<control>/` folder.
4. **Tag** — every resource gets `msp-control = <ID>` so all resources for a control
   are filterable in one Console/CLI query.
5. **Register** — add a row to the table above.

## Feature-flag conventions

- One boolean per control: `enable_release_management`, `enable_security_logging`, …
- Dependencies validated in Terraform (e.g. a control that needs CloudTrail asserts it).
- A control turned **off** provisions nothing and costs nothing.

*Release Management is deployed & operational (first release ran end-to-end). Other controls not started.*
