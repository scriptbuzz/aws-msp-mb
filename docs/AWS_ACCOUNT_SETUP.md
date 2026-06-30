# AWS Account Setup (via Control Tower)

How to stand up the dedicated AWS account this project deploys into, using your
existing **AWS Control Tower** landing zone, and wire it to the repo. Access is via
**IAM Identity Center (SSO)** — **no long-lived access keys** (matches the secrets rule
and the MSP security narrative).

> All steps that touch the AWS console are **yours to do** (interactive). The agent
> cannot create accounts or authorize SSO. Once `.env` points at an SSO profile,
> the agent can run Terraform.

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
6. Assign **your user** the **`AWSAdministratorAccess`** permission set for this account
   (needed for the greenfield bootstrap — VPC/ECS/ECR/ALB/IAM/CodePipeline/etc.).
7. Copy the **AWS access portal URL** (the Identity Center start URL).

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
12. The agent/you run Terraform with the env loaded so the CLI inherits the profile:
    ```
    set -a && source .env && set +a && terraform <cmd>
    ```

That's the only credential the agent needs — and it's a short-lived SSO session, not a key.

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

---

## F. Then continue the rollout

With `.env` set and `aws sso login` done, proceed to the rollout phases in
[RELEASE_MANAGEMENT_DESIGN.md](RELEASE_MANAGEMENT_DESIGN.md) §11 / the rollout sequence:
bootstrap state buckets → GitHub OAuth connection → first local `terraform apply` →
hand off to the pipeline.

---

## Portability note

Because everything is variable-driven, porting to a **different** Control Tower account
or org later is just: Account Factory → new account, new SSO profile, new `backend.hcl`.
**No module code changes.**
