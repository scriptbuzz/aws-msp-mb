# AWS Account Setup (via Control Tower)

*Last updated: 2026-07-07 11:53*

How to stand up the dedicated AWS account this project deploys into, using your
existing **AWS Control Tower** landing zone, and wire it to the repo. Access is via
**IAM Identity Center (SSO)** — **no long-lived access keys** (matches the secrets rule
and the MSP security narrative).

> All steps that touch the AWS console are **manual** (interactive) — account
> creation and SSO authorization cannot be automated. Once `.env` points at an SSO
> profile, Terraform can be run non-interactively.

---

## A. Provision the account — Control Tower Account Factory

1. Sign in to your **management account** → open the **AWS Control Tower** console.
2. Go to **Account Factory** → **Create account** (or via Service Catalog →
   "AWS Control Tower Account Factory" product).
3. Fill in:
   - **Account email** — a *unique* email not used by any existing AWS account
     (e.g. `aws+msp-mb@yourdomain`). Each AWS account needs its own.
   - **Display name** — e.g. `mb-msp`.
   - **IAM Identity Center user** — the email/name that will own/admin the account.
   - **Organizational Unit** — choose the target OU (e.g. a `Workloads` or `Sandbox`
     OU). Avoid the management account.
4. Submit. Control Tower provisions in ~15–30 min — it enrolls the account, applies
   the baseline (org **CloudTrail** + **Config**), and applies the OU's **guardrails**.

> Bonus: that baseline CloudTrail/Config is reusable evidence for *future* security
> controls in this repo (see [CONTROLS.md](CONTROLS.md)).

---

## B. Grant access — IAM Identity Center (SSO)

5. Open **IAM Identity Center** → **AWS accounts** → select the new `mb-msp` account.
6. Assign **your user** a permission set for this account. Two options:
   - **Simplest:** `AWSAdministratorAccess`.
   - **Least-privilege (recommended):** **`PowerUserAccess` + a small scoped IAM add-on.**
     PowerUser alone is **not** enough — it excludes `iam:*`, and this stack both
     **creates IAM roles/policies** (the `iam` module) and needs **`iam:PassRole`** to
     wire roles to ECS/CodePipeline/CodeBuild/CodeDeploy. Add an inline policy from
     [`infra/deploy-permissions.json`](../infra/deploy-permissions.json) (scoped to the
     `mb-*` names) to a custom permission set alongside `PowerUserAccess`. This avoids
     full admin while granting exactly what the deploy needs. Org/account APIs aren't
     used by the deploy, so PowerUser's other exclusions don't matter.
7. Copy the **AWS access portal URL** (the Identity Center start URL).

> Full rationale + the exact IAM gaps are in [MANUAL_OPERATIONS.md](MANUAL_OPERATIONS.md)
> and the "deploy permissions" note in [../infra/README.md](../infra/README.md).

### B2. Permissions checklist — everything a redeploy needs

Use this to confirm the deploying identity (and the people around it) can do
**all** of the following before starting the rollout in a new account.

> **Automated check:** after `aws sso login`, run
> **[`scripts/check-deploy-permissions.sh`](../scripts/check-deploy-permissions.sh)** —
> it verifies every in-account row below and prints OK / MISSING per permission.
> Read-only (probe calls + the IAM policy simulator); it creates and changes
> nothing. Regional services are verified with real read-only calls rather than
> the simulator, because from a member account the simulator cannot evaluate org
> SCPs and would false-deny them. Rows 11–13 (management account, GitHub, AWS
> Support) are people, not API calls — check those by hand.

**In the deploy account (the principal running `scripts/rollout.sh` / Terraform):**

| # | Capability | Used by | Covered by |
|---|---|---|---|
| 1 | S3 — create/manage buckets, read/write objects | bootstrap (state + artifact buckets), Terraform state | PowerUser or admin |
| 2 | EC2 — VPC, subnets, IGW, route tables, security groups | shared-network | PowerUser or admin |
| 3 | ECR — create repo, lifecycle policy | shared-ecr | PowerUser or admin |
| 4 | ECS — cluster, services, task definitions | shared-cluster, all envs | PowerUser or admin |
| 5 | ELBv2 — ALB, target groups, listeners | prod | PowerUser or admin |
| 6 | CodePipeline / CodeBuild / CodeDeploy / CodeConnections | shared-pipeline, prod | PowerUser or admin |
| 7 | CloudWatch — log groups, 5xx alarm | pipeline, prod | PowerUser or admin |
| 8 | SSM Parameter Store — read/write one parameter | optional GitHub token for change-record issues | PowerUser or admin |
| 9 | IAM — create/manage the `mb-*` roles & policies, `iam:PassRole` to ECS/CodePipeline/CodeBuild/CodeDeploy | shared-iam, service wiring | **NOT in PowerUser** → [`deploy-permissions.json`](../infra/deploy-permissions.json) add-on (or admin) |
| 10 | IAM service-linked roles (ELB/ECS auto-create them on first use in a new account) | first ALB / ECS service | PowerUser (explicitly includes `iam:CreateServiceLinkedRole`) or admin |

**Outside the deploy account (other people/roles needed once):**

| # | Who | For |
|---|---|---|
| 11 | **Management-account** Identity Center admin | assign the permission set (step 6) and attach the deny-direct-prod-deploy policy to human permission sets |
| 12 | **GitHub repo admin** | authorize the CodeConnection (console OAuth) and grant the "AWS Connector for GitHub" app access to the repo |
| 13 | **AWS Support** access on the new account | lift the new-account CodeBuild concurrency hold if present (pre-flight item 16) |

**Not covered by the least-privilege option:** `scripts/demo-user.sh` manages an IAM
*user* (`cicd-demo`), which is outside the `mb-*` role/policy scope — run it as admin,
or skip it (it's a demo convenience, not part of the rollout).

### B3. Why these permissions — the rationale

The principle: **the deployer needs exactly the ability to create what the stack
contains, nothing more.** Terraform has no special access of its own — every resource
in `infra/` maps to an AWS API family the deploying identity must be allowed to call.

- **S3 (row 1)** — the project *creates its own* state and artifact buckets
  (bootstrap stage), so it needs bucket-level permissions (create, versioning,
  public-access-block), not just object read/write. CodePipeline cannot run
  without an artifact bucket; Terraform cannot track anything without state.
- **EC2 (row 2)** — no servers are ever launched (it's Fargate), but VPCs, subnets,
  route tables and security groups live in the **EC2 API namespace**. This is why
  "EC2 permissions" are required for a stack with zero EC2 instances.
- **ECR / ECS / ELBv2 (rows 3–5)** — one API family per thing the stack is:
  a registry to hold images (created empty; *pushing* is done later by the
  CodeBuild **role**, not the deployer), a cluster + four services to run them,
  and the prod ALB with **two** target groups — blue/green needs both.
- **CodePipeline / CodeBuild / CodeDeploy / CodeConnections (row 6)** — the
  delivery machinery itself: the pipeline, three build projects, the blue/green
  deployment group, and the GitHub connection object.
- **CloudWatch (row 7)** — build/task log groups, plus the **5xx alarm that
  triggers automatic rollback** — it's part of the control, not observability
  sugar.
- **SSM (row 8)** — one optional SecureString parameter (GitHub token) so the
  change-record step can open issues without the token ever touching the repo.
- **IAM roles/policies (row 9) — the crux.** AWS services cannot act in your
  account until you *give them an identity*: the stack creates five roles
  (pipeline orchestration, build, deploy traffic-shifting, task execution
  [pull image + write logs], task runtime). Creating roles is **privilege
  escalation surface**, which is exactly why `PowerUserAccess` excludes `iam:*`
  — and why the add-on restores it **only for `role/mb-*` / `policy/mb-*`**:
  the deployer can manage this project's identities but cannot touch any other
  role in the account. Blast-radius containment via the naming convention.
- **`iam:PassRole` (row 9, least obvious)** — wiring a role *to* a service is
  "passing" it. Without this being a distinct permission, anyone who can create
  an ECS service could hand it an **existing high-privilege role** and escalate.
  The add-on therefore (a) limits passing to `mb-*` roles and (b) adds an
  `iam:PassedToService` condition so they can only be passed to the four
  services that legitimately consume them (ECS tasks, CodePipeline, CodeBuild,
  CodeDeploy) — not to, say, a Lambda the deployer controls.
- **Service-linked roles (row 10)** — on first use in a brand-new account,
  ELB and ECS auto-create their internal `AWSServiceRoleFor…` roles.
  `PowerUserAccess` explicitly allows `iam:CreateServiceLinkedRole`, so this
  works without the add-on — but it's why a *stricter* custom policy than
  PowerUser would break on the first ALB.

And the mirror image: the **deny-direct-prod-deploy policy** exists to *remove*
permissions from humans — prod may only change through the pipeline (build →
tests → change record → approval). The deployer permissions above are for
**standing the machine up**; day-to-day releases need none of them.

---

## C. Configure the CLI profile (your workstation)

8. Run `aws configure sso`:
   - **SSO start URL** — the access portal URL from step 7
   - **SSO region** — your Identity Center region (often the CT home region)
   - Pick the **`mb-msp` account** and the **AdministratorAccess** role
   - **Profile name** — `mb-msp`
9. Log in: `aws sso login --profile mb-msp`
10. Verify: `aws sts get-caller-identity --profile mb-msp` → shows the **new account ID**.

SSO tokens are short-lived; re-run `aws sso login` when they expire. No keys stored.

---

## D. Wire it into the repo

11. In the project **`.env`** (gitignored — see `.env.example`):
    ```
    AWS_PROFILE=mb-msp
    AWS_REGION=us-east-1
    ```
12. Run Terraform with the env loaded so the CLI inherits the profile:
    ```
    set -a && source .env && set +a && terraform <cmd>
    ```

That's the only credential needed — and it's a short-lived SSO session, not a key.

---

## E. Pre-flight checks (avoid surprises at apply time)

13. **Region:** confirm `us-east-1` is a **governed region** in Control Tower (it's the
    usual home region). If CT only governs another region, either change the project
    region or add `us-east-1` to governed regions.
14. **Guardrails:** Control Tower's mandatory guardrails (logging, region deny, root
    restrictions) don't block ECS/ECR/ALB/CodePipeline. If you've enabled **elective**
    guardrails that deny specific services/regions, confirm none block this stack.
15. **Terraform state:** simplest is to put the state + artifact S3 buckets **in this
    same `mb-msp` account** (Phase 2 of the rollout). `backend.hcl` points at them.
16. **CodeBuild concurrency hold (new accounts):** freshly created AWS accounts can
    ship with an enforced limit of **0 concurrent CodeBuild builds** — every build fails
    with `AccountLimitExceededException: Cannot have more than 0 builds in queue` even
    though Service Quotas shows a normal value. Only **AWS Support** can lift it (open a
    support case; quota-increase requests don't apply). Budget for this before the first
    pipeline run in any new account.

---

## F. Then continue the rollout

With `.env` set and `aws sso login` done, run the stage-by-stage rollout in
**[ROLLOUT.md](ROLLOUT.md)** (`scripts/rollout.sh apply bootstrap → shared → dev/test/stage
→ prod`; buckets are created automatically). Human-required steps along the way (authorize
the GitHub connection, approve prod, attach the deny-direct-prod-deploy policy) are in
[MANUAL_OPERATIONS.md](MANUAL_OPERATIONS.md).

---

## Portability note

Because everything is variable-driven, porting to a **different** Control Tower account
or org later is just: Account Factory → new account, new SSO profile, new `backend.hcl`.
**No module code changes.**
