# Release Management — Audit Evidence

*Last updated: 2026-07-04 15:02*

Captured evidence that the **Release Management** control is implemented and operating.
All artifacts come from the first production release in the sandbox account
(`561521479906`, `us-east-1`).

## Release under evidence

| Field | Value |
|---|---|
| Pipeline | `mb-use1-pipeline-app` (CodePipeline V2) |
| Execution ID | `d1f7307a-9a89-46a6-aa43-73ab8de23747` |
| Source commit | `c35cb7f` (GitHub `scriptbuzz/aws-msp-mb`, branch `main`) |
| App version | `1.0.3` |
| Image digest deployed | `sha256:f5f484be8a89c22d8f52be40513924ad217ff6d40adfe7dacd9271114e0cf6f1` |
| Result | **Succeeded** — prod live, HTTP 200 |
| Date | 2026-07-03 |

## Mandatory control components → evidence

| # | Mandatory component | Evidence |
|---|---|---|
| 1 | Version control (code + deployment assets) | GitHub repo; commit `c35cb7f` drove the run — `08-version-control.txt`, `01-pipeline-execution.json` |
| 2 | Test/validate in non-prod before prod | Staged promotion dev → test → stage, each Succeeded — `02-stage-results.json` |
| 3 | System for managing approvals before prod | Manual approval action, human-approved ("Looks good.") — `03-approval-record.json` |
| 4 | Declarative/imperative IaC | Terraform (`infra/` modules + env roots) provisions the whole stack |

## GAP-list items → evidence

| Requirement | Evidence |
|---|---|
| Staged promotion dev→test→stage→prod | `02-stage-results.json` (all stages, timestamps) |
| Manual approval at prod | `03-approval-record.json` |
| Change record linked to artifact | `04-change-record.txt` — `artifact_digest` matches the deployed image digest exactly |
| Automated rollback (CodeDeploy blue/green) | `05-codedeploy-bluegreen.json` (rig) + **demonstrated live**: `10-rollback-deployment.json`, `11-rollback-summary.txt` — a bad release could not become healthy, traffic never shifted, green torn down, **zero downtime** |
| Deploy-only-via-pipeline guardrail | `09-deny-direct-policy.json` (`mb-use1-deny-direct-prod-deploy`) |
| Live result | `07-live-site.txt` (HTTP 200, version `1.0.3-c35cb7f`) |

## Files in this folder

- `01-pipeline-execution.json` — execution summary + source revision
- `02-stage-results.json` — every stage/action, status, start/end times
- `03-approval-record.json` — manual approval + comment + timestamp
- `04-change-record.txt` — the ITSM change record (digest-linked)
- `05-codedeploy-bluegreen.json` — the prod blue/green deployment
- `06-artifact-image.json` — ECR image tag + digest (promoted by digest)
- `07-live-site.txt` — live prod HTTP 200 + served version
- `08-version-control.txt` — commit history
- `09-deny-direct-policy.json` — the deny-direct-prod-deploy guardrail
- `10-rollback-deployment.json` — the failed prod deployment + auto-rollback config
- `11-rollback-summary.txt` — automated-rollback demonstration write-up

## Notes / caveats

- The change record shows `commit: unknown` because the ChangeRecord stage reads
  the Build artifact (not source); its `artifact_digest` is the authoritative link
  and it matches the deployed image. (Minor hardening: pass the commit through the
  build artifact.)
- Change record is stored as a pipeline artifact (no GitHub token configured, so no
  issue was opened) — `GITHUB_TOKEN_SSM_PARAM` is the switch to also open an issue.
- The Deploy-prod action shows one Failed attempt (an IAM scope gap, fixed in commit
  `7838f08`) followed by a Succeeded retry — retained as evidence of the fix.

## Coverage

All mandatory components and the GAP-list items are now evidenced, including the
**automated-rollback demonstration** (`10`/`11`). Operational follow-ups outside the
evidence set: attach the deny-direct-prod-deploy policy to SSO permission sets, and
confirm push-based auto-triggering of the pipeline.
