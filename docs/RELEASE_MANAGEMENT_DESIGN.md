# AWS MSP — Release Management Design & Decisions

> Working design notes for the Release Management control of the AWS MSP audit.
> Captures the decisions, architecture, and open items from the design discussion.
> Status: **design only — nothing provisioned yet.**

---

## 1. Project context

- **Goal:** Provision the AWS solution(s) needed to pass the AWS MSP audit, one control at a time.
- **First control in scope:** **Release Management** (the user has referred to this as "OPS06" — see caveat below).
- **Repo:** `/Users/user/Documents/Development/aws-msp-claude`
- **Decision style:** review-before-build. No resources created without explicit approval.

> ⚠️ **Control-ID caveat:** "OPS06" was used as shorthand in discussion. The authoritative text the user supplied is titled **"Release Management."** Whether the current MSP workbook numbers it OPS06 should be confirmed against the official workbook before quoting the ID in audit evidence.

---

## 2. Standing rules (apply to every decision)

1. **Cheapest resource that does the job.**
2. **Simplest, least-complicated solution that passes the *minimum* MSP validation requirement.**
3. **Fully portable** — must be deployable to different AWS account(s) and Orgs. No hardcoded account IDs, org IDs, regions, or emails. Everything parameterized.
4. **Every recommendation is reviewed** for accuracy, cost, and simplicity before being presented.
5. Flag any paid (or could-become-paid) third-party/AWS service before adopting it.

---

## 3. Locked decisions

| # | Decision | Choice |
|---|---|---|
| 1 | Language / runtime | Python |
| 2 | IaC tool | Terraform (1.10+, S3-native state locking — no DynamoDB) |
| 3 | Multi-account strategy | AWS Organizations |
| 4 | MSP tier | AWS MSP Validated |
| 5 | Deployment account model | Own account(s) |
| 6 | Infrastructure | Greenfield |
| 7 | CI/CD | AWS CodePipeline |
| 8 | Source control | GitHub (owner: `scriptbuzz`) |
| 9 | Org/resource prefix | `mb` |
| 10 | Region | `us-east-1` |
| 11 | Manual approval before prod | Yes |
| 12 | Deny-direct-deploy guardrail | IAM policy (account-level, not SCP) |
| 13 | Sample app | Simple **static website** |
| 14 | Deployment target | **ECS Fargate + CodeDeploy blue/green** (see §6) |
| 15 | Security scanners | **Deferred (2026-06-29)** — ignore external scanners for now; reserve a pluggable hook (see §8a) |
| 16 | Repo structure | **Monorepo** — `github.com/scriptbuzz/aws-msp-mb` (supersedes 3-repo plan) |
| 17 | Pipeline version | **CodePipeline V2** — needed for monorepo path-filter triggers |
| 18 | Governing bar | **GAP remediation list** (heavier bar — blue/green, staged promotion, ITSM, etc.) |
| 19 | ITSM change-record | **GitHub-issue change record** (pipeline opens/links an issue tagged with the artifact digest) |
| 20 | Environment model | **Prod always-on + dev/test/stage scale-to-zero** · ALB on **prod only** · ~$25/mo |

### Repo structure — MONOREPO (decided 2026-06-29, supersedes the earlier 3-repo plan)

Single repo: **https://github.com/scriptbuzz/aws-msp-mb** (`origin`).
Local working copy: `/Users/user/Documents/Development/aws-msp-claude`.

```
aws-msp-mb/
├── app/                 # the static website (sample APPLICATION code)
├── infra/
│   ├── modules/         # reusable Terraform modules
│   └── environments/    # dev / test / stage / prod configs
├── pipeline/            # buildspec(s), appspec.yaml, taskdef.json
├── docs/                # design doc, evidence/, branch + release strategy
│   └── evidence/OPS06/
└── web/                 # the interactive diagram (draft)
```

**Why monorepo (not 3 repos):** single-operator greenfield under the
"simplest" rule. One repo = one set of branch-protection rules, one
CodeConnection, trivial to clone/port. `app/` vs `infra/` subdirs cleanly
separate application code from IaC (the audit evidence the control wants) —
clearer than two opaque repos. The 3-repo split solved problems we don't have
(multi-team module versioning, independent dev-workstation tear-down).

**Split later only if:** multiple customers with separate pipelines, a team
forms needing independent module release cycles, or the dev workstation
returns and must be independently destroyable.

> EC2 dev workstation stays **deferred**. Local dev: tfenv + pyenv + venv +
> one setup script + per-deployment `backend.hcl`. Portable, self-contained,
> no Docker.

### Pipeline trigger — monorepo path filter (CodePipeline V2)

The app-deploy pipeline triggers **only on `app/**` changes** via a
CodePipeline **V2 source trigger** (branch + file-path filter), so doc/web/
infra edits don't fire a deploy:

```
Source trigger (V2):
  branch:    main (or a dedicated release branch)
  filePaths: app/**
```

**"Simulate a release" convention:** bump `app/VERSION` (or a visible banner in
`app/index.html`) → open PR → reviewer approves → merge. The merge matches
`app/**` and fires the pipeline. Each merge = one execution = one evidence
artifact. Trigger a deliberate health-check failure on one run to capture the
auto-rollback evidence. (Requires CodePipeline **V2** — V1 has no path filters.)

---

## 4. The Release Management control

### 4a. Official mandatory text (authoritative — 4 components)

1. AWS Partner uses **version control** to manage code and deployment assets.
2. AWS Partner has **standard procedures for testing and validating changes in non-production** environments before deploying to production.
3. AWS Partner has a **system for managing approvals** of changes before being deployed to production.
4. For AWS resources owned/deployed by the Partner, the Partner uses **declarative (CloudFormation/Terraform) or imperative (CDK) automated IaC** tools.

### 4b. The "GAP" remediation list (heavier / stringent bar)

The auditor-style gap text asks for more than the 4 mandatory components:
- Git version control (app code **and** IaC)
- Pull-request approval gates
- CI quality gates: build, unit + integration tests, **IaC scan, SAST, SCA**
- Staged promotion across **dev → test → stage → prod** with manual approval at production
- **Change-record creation in ITSM linked to artifact**
- **Automated rollback** via AWS CodeDeploy blue/green or traffic shifting
- Pipeline architecture diagram
- Branch & release strategy doc
- One or two sample customer pipelines

> **Key finding:** the official mandatory text is *far lighter* than the GAP list. Items like SAST/SCA/IaC-scan, ITSM linkage, blue/green rollback, and 4 environments are **not** in the mandatory 4 components. Which bar governs depends on whether the GAP text is the auditor's actual remediation finding or an aspirational checklist — **open question for the user.**

---

## 5. Deployment target — how we landed on Fargate

The static site could be hosted many ways. The decision journey:

| Target | Cost | 4 envs | CodeDeploy blue/green | Notes |
|---|---|---|---|---|
| S3 + CloudFront | pennies | cheap (1 bucket/env) | ❌ | Cheapest; passes *mandatory* control. **Removed from consideration by user.** |
| Lambda (container) | low (scale-to-zero) | cheap | ✅ (alias shift, no ALB) | Poor fit for static (hand-rolled file serving) |
| App Runner | ~$3–5/env | cheap (pausable) | ❌ (own deploy + auto-rollback) | **Simplest** container option; cheaper than Fargate; but no CodeDeploy |
| **ECS Fargate + ALB** | ~$25/env | ~$100 if all live | ✅ | **Chosen.** No servers to patch; does CodeDeploy blue/green by name |
| EC2 + ALB | ~$20/env | ~$80 if all live | ✅ | You patch the OS — no advantage over Fargate |

**Why Fargate won:** user wants to demonstrate **CodeDeploy blue/green by name**; Fargate is the **simplest target that supports it** (App Runner/Lightsail are simpler but don't integrate with CodeDeploy), and it removes OS-patching from MSP vulnerability-management scope.

> **Cost note:** S3 + CloudFront remains the cheapest option that satisfies the *mandatory* control. Fargate is a deliberate over-spec to match the GAP text's named "CodeDeploy blue/green." Trade accepted by user.

---

## 6. Chosen architecture (Fargate)

### Multiple environments (decision #20)
- One container **image built once** in CI, pushed to **ECR**, promoted by **immutable digest** through environments (never rebuilt per env).
- One **ECS Service per environment**: dev → test → stage → prod.
- **Lower envs (dev/test/stage)** use cheap **ECS rolling updates**, run **0 tasks when idle** (scale-to-zero), and have **no ALB** — they're reachable for validation via the running task's IP (or ECS Service Connect). The pipeline scales the service to 1 → deploys → validates → scales back to 0, so idle compute cost ≈ $0 while the deploys remain real.
- **Prod** is **always-on** (it's the live site) and uses the full **CodeDeploy blue/green** rig. **Prod is the only environment with an ALB.**

**Cost:** prod ~$25/mo (ALB ~$16 + 1 Fargate task ~$9) is the irreducible floor; lower envs ~$0 idle. Total ≈ **~$25/mo**.

### Blue/green to prod (CodeDeploy ECS)
```
              ALB
        ┌──────┴───────┐
  prod listener   test listener (optional pre-shift validation)
        │
   ┌────┴─────┐
 BLUE TG    GREEN TG
   │            │
 BLUE        GREEN
 task set    task set (new version)
 (live)      (spun up on deploy)
```
1. Blue serves 100% live traffic.
2. CodeDeploy launches green with the new task definition → green target group.
3. (Optional) validate green via the test listener.
4. Traffic shifts blue → green (all-at-once / linear / canary).
5. Health checks + CloudWatch alarms watch green → **automatic rollback** to blue on failure.
6. On success + bake window, blue is terminated.

**Prod-only constructs:** ECS Service (`deploymentController: CODE_DEPLOY`), ALB + 2 target groups + prod listener (+ optional test listener), CodeDeploy application + deployment group, `appspec.yaml` + `taskdef.json`, IAM roles (CodeDeploy, task execution, task).

### Pipeline
```
Source (GitHub)
  → Build (build image → ECR; run tests + scans)
  → Deploy dev    (ECS rolling)
  → Deploy test   (ECS rolling)
  → Deploy stage  (ECS rolling)
  → MANUAL APPROVAL
  → Deploy prod   (CodeDeploy blue/green + auto-rollback)
```

### Cost-smart pattern (recommended)
Only **prod** needs the ALB + two target groups + CodeDeploy. Lower envs run as cheap single-task rolling services (or are simulated as pipeline stages). **One ALB, not four** → ~$25/mo instead of ~$100, while still demonstrating 4-stage promotion, prod approval, and blue/green rollback.

---

## 7. Compliance scorecards

### A. Against the official mandatory control
| Component | Status |
|---|---|
| 1. Version control (code + assets) | ✅ GitHub (app + IaC) |
| 2. Test/validate in non-prod before prod | ✅ dev/test/stage |
| 3. Approval before prod | ✅ manual approval gate |
| 4. Declarative/imperative IaC | ✅ Terraform |

**Verdict: 4/4 — fully meets the mandatory control.**

### B. Against the stringent GAP list
| Requirement | Status |
|---|---|
| Git version control (app + IaC) | ✅ |
| PR approval gates | ⚠️ add GitHub branch protection (trivial) |
| CI: build | ✅ |
| CI: unit + integration tests | ⚠️ author + wire real tests |
| CI: IaC scan / SAST / SCA | ⏸️ deferred — pluggable hook reserved (see §8a) |
| Staged promotion dev→test→stage→prod | ✅ |
| Manual approval at prod | ✅ |
| Change-record in ITSM linked to artifact | 🟡 decided → GitHub-issue change record (decision #19); to build |
| Automated rollback (CodeDeploy blue/green) | ✅ core of Fargate design |
| Pipeline architecture diagram | ⚠️ to author |
| Branch & release strategy doc | ⚠️ to author |
| 1–2 sample customer pipelines | ✅ this is the sample pipeline |

> **"Meets" requires evidence, not just build.** Auditors read artifacts: pipeline execution history, approval records, scan reports, the rollback actually firing. Clearing the bar = run the pipeline + capture evidence into `docs/evidence/`.

---

## 8. Tooling coverage — what the chosen services already cover

| Gap | Covered by | Native? | Cost flag |
|---|---|---|---|
| PR approval gates | GitHub branch protection | ✅ | Free |
| SCA (dependencies) | GitHub Dependabot | ✅ | Free (incl. private repos) |
| SAST | GitHub CodeQL (GHAS) | ✅ | ⚠️ **paid** on private repos |
| Image vulnerability scan | ECR basic scan / Amazon Inspector | ✅ | basic = free; Inspector = paid |
| Unit/integration tests | CodeBuild (host) | ⚙️ | Free (author the tests) |
| Build / staged deploy / approval / blue-green | CodePipeline + CodeBuild + CodeDeploy + Fargate | ✅ | the pipeline itself |
| **IaC scan (Terraform)** | none native → OSS in CodeBuild (Checkov / tfsec / Trivy) | ❌ | Free |
| **ITSM change record** | none of the chosen services → see §9 | ❌ | varies |
| Pipeline diagram + strategy doc | human-authored | ❌ | — |

### Cheapest free-leaning closure (when scanning is later enabled)
- **SAST:** Semgrep OSS in CodeBuild (avoids paid CodeQL on private repos)
- **SCA:** Dependabot (free) + Trivy in CodeBuild
- **IaC scan:** Checkov in CodeBuild
- **Image scan:** ECR basic scanning (free)
- **PR gates:** GitHub branch protection (free)

### 8a. Security scanning — DEFERRED but pluggable (decision 2026-06-29)

**External security tools are intentionally ignored for now.** No scanner
(Checkov, Semgrep, Trivy, CodeQL, Dependabot, Inspector) is wired or
provisioned. To avoid a rearchitect when they are added later, the design
**reserves a security-scan extension point**:

- **Where:** a dedicated `security-scan` phase in the CodeBuild buildspec
  (or a standalone CodePipeline stage between Build and Deploy dev).
- **Now:** the phase is a **no-op stub** that always passes — the pipeline
  runs end-to-end without any scanner present.
- **Contract for plugging in later:** a tool is added by (1) installing it in
  the buildspec `install`/`pre_build` step, (2) invoking it in the
  `security-scan` phase, and (3) letting its non-zero exit fail the stage —
  no pipeline/topology change required.
- **Gating policy (TBD when enabled):** which findings block the pipeline vs.
  warn. Left open until a scanner is chosen.

This keeps the current build the simplest thing that passes the *mandatory*
control (which does not require scanning) while staying one step away from the
GAP-list scanners.

---

## 9. Open decisions — ALL RESOLVED (2026-06-29)

1. ✅ **Which bar governs** → **GAP remediation list** (decision #18).
2. ✅ **ITSM** → **GitHub-issue change record** (decision #19) — pipeline opens/links an issue tagged with artifact digest + commit. Free.
3. ✅ **Environment model** → **prod always-on + dev/test/stage scale-to-zero, ALB on prod only** (decision #20), ~$25/mo.

No open decisions remain. Next is the branch & release strategy doc + scaffolding.

---

## 10. Deliverables still to produce

- Reserve the **no-op `security-scan` extension point** in CodeBuild (see §8a); wire unit/integration tests. External scanners stay **deferred** until a tool is chosen.
- ITSM change-record step — GitHub-issue change record (decision #19); to build into the pipeline
- GitHub branch protection (to configure on `main`)
- ✅ **Pipeline architecture diagram** — done ([web/index.html](../web/index.html), Architecture tab)
- ✅ **Branch & release strategy doc** — done ([BRANCH_AND_RELEASE_STRATEGY.md](BRANCH_AND_RELEASE_STRATEGY.md))
- Evidence capture into `docs/evidence/` (run the pipeline, collect execution history + rollback proof)

---

## 11. Manual / apply-time tasks (cannot be automated)

1. Create S3 state bucket + artifact bucket (Terraform state chicken-and-egg).
2. Authorize the GitHub connection OAuth handshake in the AWS console (comes up `PENDING`).
3. First `terraform apply` runs **locally** to create the pipeline; afterward the pipeline self-manages.
4. Provide AWS credentials via the project `.env` (per credential rules).

---

*Last updated: 2026-06-29. Design baseline + repo scaffold complete (READMEs, placeholders, pipeline stubs). No `.tf` files written and no AWS resources provisioned yet — that's the next phase.*
