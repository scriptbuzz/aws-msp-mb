# Status Log — AWS MSP Release Management

*Last updated: 2026-07-07 19:19*

Running status log for the Release Management control rollout. Newest entry on top.
Format: 3P (Progress / Plans / Problems).

---

## 🔐 Portability + deploy-permissions hardening (Jul 6–7, 2026)

**Progress:** Shipped release **v1.0.5** (tagged GitHub Release + `CHANGELOG.md`; prod
now serves `1.0.5-98c6a69`). Tuned the pipeline — Build on `MEDIUM` CodeBuild compute and
prod blue/green `termination_wait = 0` (both applied in-place, verified live). Ran a full
portability pass: scripts pinned to **us-east-1** with parameters + manual `.env`-free
fallbacks lifted to a labeled banner at the top of each script. Made the deploy grant
**fully granular** — new [`infra/deploy-permissions-services.json`](../infra/deploy-permissions-services.json)
(160 service actions, `mb-*`-scoped where supported, region-pinned) pairs with
[`infra/deploy-permissions.json`](../infra/deploy-permissions.json) so **no AWS-managed
policy is required**. Added a read-only pre-flight checker
[`scripts/check-deploy-permissions.sh`](../scripts/check-deploy-permissions.sh)
(service probes + IAM policy simulator; verified against admin and via custom-policy
simulation incl. negative controls). Documented the full permissions story
(AWS_ACCOUNT_SETUP §B/§B2/§B3) and the new-account CodeBuild hold as a pre-flight item.
Repo cosmetics: README badges, About/topics, and history squashed to a single commit.

**Plans:** Same outstanding manual items — grant the "AWS Connector for GitHub" app repo
access (enables push-to-deploy), attach the deny-direct-prod-deploy policy to human SSO
permission sets, and rotate/remove the exposed `cicd-demo` credentials before real use.

**Problems:** None open. Note the checker's own reliance on region-correct probes: the IAM
policy simulator can't evaluate org SCPs from a member account, so regional services are
verified with real read-only calls instead (documented in the script header).

---

## 🚀 AWS MSP — Release Management (Jul 2–3, 2026)

**Progress:** Provisioned the full Release Management control in the sandbox01 account
(6 Terraform modules, 5 environment roots, staged via a per-stage rollout script) and ran
the **first release end-to-end** — Source → Build → dev → test → stage → change-record →
manual approval → **prod blue/green**, all green; the prod site is live (HTTP 200) serving
the pipeline-stamped build `v1.0.3`. Fixed 4 pipeline defects surfaced during rollout
(invalid CodeBuild phase, immutable-tag collision, missing buildspec artifacts, and a
CodeDeploy IAM scope gap).

**Plans:** Capture MSP audit evidence (execution history, approval record, change record,
live-site proof) into `docs/evidence/`; demonstrate automated blue/green rollback via a
deliberate health-check failure; attach the deny-direct-prod-deploy guardrail to SSO
permission sets; and confirm push-based auto-triggering.

**Problems:** A new-account CodeBuild hold (0 builds allowed account-wide) blocked every
build for ~1 day — resolved via AWS Support; prod now runs at ~$25/mo while up; the
push→pipeline webhook is not yet confirmed (all runs triggered manually so far).
