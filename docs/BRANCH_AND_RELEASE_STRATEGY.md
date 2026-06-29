# Branch & Release Strategy — aws-msp-mb

> Audit deliverable for the **Release Management** control (GAP remediation list).
> Defines how changes flow from a developer's commit to production, the gates
> along the way, and how each step maps to the MSP requirement it satisfies.
> Companion to [RELEASE_MANAGEMENT_DESIGN.md](RELEASE_MANAGEMENT_DESIGN.md).

Repo: **https://github.com/scriptbuzz/aws-msp-mb** (monorepo).

---

## 1. Branching model — trunk-based with short-lived branches

Deliberately simple (per the "simplest solution" rule). **No GitFlow, no release
branches, no long-lived `dev` branch.**

| Branch | Role | Protected? |
|---|---|---|
| `main` | The single source of truth. Every merge is a release candidate. The pipeline triggers from here. | ✅ yes |
| `feature/*`, `fix/*` | Short-lived working branches. One change, opened as a PR into `main`, deleted after merge. | no |

- All work happens on a short-lived branch and lands via **pull request**.
- `main` is always deployable.
- No direct commits to `main` — enforced by branch protection (§3).

---

## 2. Monorepo paths & what triggers the pipeline

The pipeline is **path-filtered** (CodePipeline V2) so only relevant changes deploy:

| Path | What it is | Triggers app pipeline? |
|---|---|---|
| `app/**` | the static website (application code) | ✅ yes |
| `infra/**` | Terraform (modules + environments) | separate infra trigger / plan-apply |
| `pipeline/**` | buildspec, appspec, taskdef | infra trigger (changes the pipeline itself) |
| `docs/**`, `web/**` | documentation, the draft diagram | ❌ no deploy |

```
Source trigger (CodePipeline V2):
  branch:    main
  filePaths: app/**
```

---

## 3. Pull-request approval gates (branch protection on `main`)

Configured on `main` in GitHub (free, native):

- ✅ Require a pull request before merging
- ✅ Require **at least 1 approving review**
- ✅ Require status checks to pass (build + tests) before merge
- ✅ Dismiss stale approvals on new commits
- ✅ No direct pushes / no force-push to `main`

> Satisfies: **PR approval gates** (GAP) and contributes to **"approval of changes"** (mandatory #3).

---

## 4. The release flow (end to end)

```
feature branch  ──PR──▶  review + status checks  ──merge to main──▶  pipeline fires (app/** changed)
                                                                          │
   Build  ──▶  Deploy dev  ──▶  Deploy test  ──▶  Deploy stage  ──▶  MANUAL APPROVAL  ──▶  Deploy prod
  (image,      (scale 0→1,      (scale 0→1,       (scale 0→1,        (human approves     (CodeDeploy
   tests,       validate,        validate,         validate,          + change record)    blue/green +
   push ECR)    scale→0)         scale→0)          scale→0)                                auto-rollback)
```

1. **Build** — build the container image once, tag by **immutable digest**, run unit + integration tests, push to ECR. *(Security-scan hook reserved but deferred — see design §8a.)*
2. **Deploy dev / test / stage** — promote the **same digest**; each lower env scales `0→1`, deploys (rolling update, no ALB), validates, scales back to `0`. Real deploys, ~$0 idle.
3. **Manual approval** — pipeline pauses; a human approves before production. The approval is recorded as audit evidence.
4. **Deploy prod** — **CodeDeploy blue/green**: green task set launched, traffic shifts blue→green, health checks + alarms watch green, **automatic rollback** on failure. Prod is always-on behind the only ALB.

---

## 5. Versioning & "simulate a release"

The app version is the release marker:

- **`app/VERSION`** holds the semantic version (e.g. `1.0.4`).
- To cut a release: bump `app/VERSION` (and/or a visible banner in `app/index.html`) on a feature branch → PR → approve → merge.
- The merge matches `app/**` → pipeline fires.
- Each merge = **one pipeline execution** = **one evidence artifact** in `docs/evidence/`.

SemVer:
- **patch** — content/copy fix, no structural change
- **minor** — new page/section
- **major** — reserved for significant redesign

---

## 6. Change records (ITSM) — GitHub-issue model (decision #19)

For each production deployment, the pipeline creates/links a **GitHub issue** as the change record:

- Title: `Change: deploy <app VERSION> to prod`
- Body links: the **commit**, the **artifact image digest**, the **pipeline execution id**, and the **approver**.
- Labeled `change-record`; closed when the deploy succeeds (or annotated on rollback).

> Satisfies: **change-record creation linked to artifact** (GAP). Lightweight by
> design; can be upgraded to SSM Change Manager or an external ITSM later without
> changing the pipeline topology.

---

## 7. Rollback

| Type | Mechanism |
|---|---|
| **Automatic** | CodeDeploy blue/green auto-rollback — failed health check or CloudWatch alarm on the green task set returns 100% traffic to blue; green is torn down. No human action. |
| **Manual** | Re-run the pipeline pinned to the previous image digest, **or** trigger a CodeDeploy rollback to the last successful deployment. |

The auto-rollback firing is captured (one deliberate failed-health-check run) as the **automated-rollback evidence**.

---

## 8. Requirement → step mapping (audit traceability)

| MSP requirement | Where it's satisfied |
|---|---|
| Version control (mandatory #1) | `main` + PRs; app code in `app/`, IaC in `infra/` |
| Test in non-prod before prod (mandatory #2) | dev / test / stage stages (scale-to-zero, real deploys) |
| Approval before prod (mandatory #3) | PR review (§3) + manual approval stage (§4) |
| Declarative IaC (mandatory #4) | Terraform under `infra/` |
| PR approval gates (GAP) | branch protection on `main` |
| CI quality gates (GAP) | Build stage: tests now; scanners via deferred hook |
| Staged promotion (GAP) | dev → test → stage → prod with prod approval |
| Change record linked to artifact (GAP) | GitHub-issue change record (§6) |
| Automated rollback (GAP) | CodeDeploy blue/green auto-rollback (§7) |

---

*Aligned with locked decisions #1–#20 in RELEASE_MANAGEMENT_DESIGN.md. Design-only — nothing provisioned.*
