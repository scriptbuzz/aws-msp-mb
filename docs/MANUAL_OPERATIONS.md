# Manual Operations — what needs a human, and why

*Last updated: 2026-07-05 12:12*

This project automates as much of the rollout as possible (see
[ROLLOUT.md](ROLLOUT.md) / [`scripts/rollout.sh`](../scripts/rollout.sh)). A handful of
steps still require a human. This doc lists them, says whether each is automatable,
and explains why the manual ones can't be scripted from here.

The common thread for the non-automatable steps: they live **outside this deploy
account's control plane** (in the AWS management/Org account, in GitHub, or in AWS
Support), or they are **interactive by security design** — automating them would
require long-lived credentials or would defeat a control we deliberately want.

---

## A. Genuinely manual (cannot be automated from this repo)

| # | Operation | Why it can't be automated here |
|---|---|---|
| A1 | **Provision the AWS account** (Control Tower Account Factory) | Runs in the **management/Org account** under landing-zone governance; creating an account + applying baseline guardrails is an org-governance action, not something a workload account's automation can (or should) perform on itself. *Automatable in principle* via Service Catalog / Control Tower APIs **from the management account** — out of this repo's scope and privilege boundary. |
| A2 | **Assign SSO access** (IAM Identity Center user + permission set) | Identity Center lives in the **management account**; granting humans access is identity governance outside the deploy account. |
| A3 | **`aws configure sso` / `aws sso login`** | Interactive **browser OAuth (device flow)** — by design a human authenticates in a browser. No headless path exists without long-lived keys, which the security model forbids. Tokens are short-lived (~hourly), so re-login recurs. |
| A4 | **Authorize the GitHub connection** (CodeConnections `PENDING` → `AVAILABLE`) | AWS **deliberately** requires a human to complete the OAuth handshake in the console. There is **no API to approve a pending connection** — a guardrail so code cannot silently grant itself repository access. |
| A5 | **Grant the "AWS Connector for GitHub" app access to the repo** (enables push auto-trigger) | A **GitHub-side** app installation/permission, controlled by a repo/org admin in GitHub Settings. No AWS API reaches it. Without it the pipeline's push webhook never fires (see [ROLLOUT.md](ROLLOUT.md) / current status). |
| A6 | **Approve the production gate** (pipeline manual approval) | **Human-by-design** — the whole point of the control is that a person decides to promote to prod, and the approval is captured as audit evidence. It *can* be approved via CLI, but automating it would defeat the control. |
| A7 | **AWS Support case** (e.g. new-account CodeBuild concurrency = 0) | An **AWS-side account restriction** lifted only by AWS Support — external to our control plane. |
| A8 | **Attach the deny-direct-prod-deploy policy** to human SSO permission sets | Permission sets live in the **management account's** Identity Center; the deploy account's automation can't modify them. The policy itself is created by Terraform (output `deny_direct_prod_deploy_policy_arn`); only the *attachment to a permission set* is manual. |

> Full click-by-click for A1–A3 is in [AWS_ACCOUNT_SETUP.md](AWS_ACCOUNT_SETUP.md).

---

## B. Was manual → now automated in this repo

| Operation | How it's automated |
|---|---|
| **State + artifact S3 buckets** (the Terraform-state chicken-and-egg) | `scripts/rollout.sh apply bootstrap` creates them via the AWS CLI **before** Terraform initializes its S3 backend. |
| **All infrastructure provisioning** | `scripts/rollout.sh apply <stage>` (bootstrap → shared substages → dev/test/stage → prod substages), each with `verify` and `undo`. |
| **Deploying the app** | Fully automated by the pipeline once triggered: build → ECR → dev/test/stage → approval → prod blue/green. |
| **Rollback demonstration** | `scripts/demo-rollback.sh` (one command). |

---

## C. Partially automated / conditional

| Operation | Status |
|---|---|
| **Trigger a release** | *Currently manual* (`aws codepipeline start-pipeline-execution` or the console's "Release change"). Becomes **fully automatic on `git push`** once **A5** is done — the pipeline already has the V2 push trigger wired (branch `main`, paths `app/**`); only the GitHub App repo grant is missing. |

---

## Design note

The non-automatable items (A1–A8) are not gaps in the tooling — they are the
**trust boundaries** of the model: browser-based human auth instead of stored keys
(A3), explicit human authorization for repo access (A4/A5) and production promotion
(A6), and org-level governance kept in the management account (A1/A2/A8). Automating
them away would require weakening exactly the controls the MSP audit is checking for.
