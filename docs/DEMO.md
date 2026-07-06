# Demo Script — Release Management pipeline

*Last updated: 2026-07-04 15:07*

A simple, followable walkthrough that shows the control working end-to-end: a change
flows from a Git commit → staged environments → human approval → production via
blue/green, and a bad release is automatically rolled back with zero downtime.

**Setup (once, before the demo):**
- `aws sso login --profile sandbox01`
- *(optional)* create a demo operator IAM user (console + CLI, full create/manage/delete
  rights via PowerUser + scoped IAM): `scripts/demo-user.sh create` — prints a one-time
  password + access keys and the console sign-in URL. Remove it after with
  `scripts/demo-user.sh delete`.
- Prod must be up: `scripts/rollout.sh apply prod` (skip if already running)
- Live URL: `PROD=http://$(aws elbv2 describe-load-balancers --names mb-prod-use1-alb --profile sandbox01 --region us-east-1 --query 'LoadBalancers[0].DNSName' --output text)`

---

## Part A — a normal release (happy path)  (~10 min)

1. **Show the starting point.** Open `$PROD/` in a browser — note the current `build: vX.Y.Z`.
   Say: "This is production, served by ECS Fargate behind an ALB."

2. **Show version control.** In GitHub (`scriptbuzz/aws-msp-mb`), show `app/` and `infra/`.
   Say: "App code and all infrastructure are in Git — nothing is hand-built in the console."

3. **Cut a release.** Bump the version and push:
   ```sh
   echo "1.0.4" > app/VERSION
   git commit -am "release: 1.0.4 demo"
   git push origin main
   aws codepipeline start-pipeline-execution --name mb-use1-pipeline-app --profile sandbox01 --region us-east-1
   ```
   Say: "One commit to `app/**` is a release. The image is built once and promoted by digest."

4. **Watch staged promotion.** In the CodePipeline console (pipeline `mb-use1-pipeline-app`),
   watch **Build → Deploy-dev → Deploy-test → Deploy-stage** go green.
   Say: "Every lower environment gets the *same* image, validated before moving on."

5. **Show the change record + approve.** At **Approve-prod**, point out the ChangeRecord ran
   first (digest-linked ITSM record), then click **Review → Approve** with a comment.
   Say: "Production needs an explicit human approval, recorded for audit."

6. **Watch prod blue/green.** **Deploy-prod** runs CodeDeploy blue/green. When it's green,
   refresh `$PROD/` — the version now shows the new build.
   Say: "New version launched alongside the old, traffic shifted, old one retired."

---

## Part B — automated rollback (the safety net)  (~5 min)

7. **Deploy a deliberately broken release to prod** (bad image that can't start):
   ```sh
   scripts/demo-rollback.sh        # (or the manual steps in docs/evidence/.../11-rollback-summary.txt)
   ```
   Keep `$PROD/` open and refresh throughout.

8. **Show what happens.** The new (green) task set never becomes healthy
   (`CannotPullContainerError`); **traffic is never shifted**; CodeDeploy tears the bad
   version down. **`$PROD/` stays HTTP 200 on the good version the whole time.**
   Say: "A broken release cannot take production down — it's caught and rolled back automatically."

---

## Part C — the evidence  (~2 min)

9. Open [`docs/evidence/release-management/EVIDENCE.md`](evidence/release-management/EVIDENCE.md).
   Walk the table mapping each MSP control component to a captured artifact — highlight that the
   **change record's `artifact_digest` matches the deployed image digest** (change linked to artifact),
   and the **rollback demonstration** files.

10. Open [`web/index.html`](../web/index.html) for the interactive architecture + pipeline diagram.

---

### Reset after the demo
- The broken deployment auto-cleans (green torn down). If a `demo` task-def revision remains:
  `aws ecs deregister-task-definition --task-definition mb-prod-use1-app:<n> --profile sandbox01 --region us-east-1`
- To stop cost when done: `scripts/rollout.sh undo prod` (removes the ~$25/mo prod stack).

> Note: this is a **sandbox** demo. The prod ALB DNS changes each time prod is recreated —
> re-fetch `$PROD` with the command in Setup.
