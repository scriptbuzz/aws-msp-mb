# module: pipeline

*Last updated: 2026-07-02 13:23*

The CI/CD orchestrator — **CodePipeline V2** + CodeBuild + the GitHub connection.

**Provisions:**
- **CodeConnections** connection to GitHub (`scriptbuzz/aws-msp-mb`) — comes up `PENDING`, authorized manually once
- **CodePipeline V2** with a **path-filtered trigger** (`branch: main`, `filePaths: app/**`)
- Stages: Source → Build → Deploy-dev → Deploy-test → Deploy-stage →
  **Approve-prod** (change record, then manual approval) → Deploy-prod
  (`CodeDeployToECS` blue/green)
- Three **CodeBuild** projects (smallest compute, `BUILD_GENERAL1_SMALL`):
  - `cb-build` — `pipeline/buildspec.yml`: image + smoke test + reserved no-op
    **security-scan** block (scanners deferred — design §8a) + push by digest
  - `cb-deploy-env` — `pipeline/deploy_env.buildspec.yml`: one project reused
    for dev/test/stage (`ENV_NAME` injected per stage); scale-to-zero up/down
  - `cb-change-record` — `pipeline/change_record.buildspec.yml`: GitHub-issue
    **change record** before the approval gate (decision #19)
- CloudWatch Logs for build/deploy execution trail (evidence)

The prod CodeDeploy app/deployment-group names are passed in **by convention**
(they're created later by the prod root) so the two roots stay independent.

`msp-control`: OPS06 + GAP (staged promotion, approval gate, change record).
