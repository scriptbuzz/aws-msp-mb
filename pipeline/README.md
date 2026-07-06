# pipeline/ — build & deploy specs

*Last updated: 2026-07-02 13:23*

The specs CodeBuild/CodeDeploy consume. Referenced by the `pipeline` Terraform module.

- `buildspec.yml` — build image, container smoke test, (reserved security-scan
  hook — a labeled block in the `build` phase, since CodeBuild phase names are
  fixed), push to ECR by immutable digest, render `taskdef.json`/`appspec.yaml`
- `deploy_env.buildspec.yml` — lower-env rolling deploy: scale 0→1 on the new
  task-definition revision, wait steady, curl-validate the task's public IP,
  scale back to 0 (in a `finally` block, so idle cost ≈ $0 even on failure)
- `change_record.buildspec.yml` — ITSM change record (decision #19): GitHub
  issue tagged with the artifact digest when a token is configured; always
  emitted as a pipeline artifact (`change-record.json`)
- `appspec.yaml` — CodeDeploy ECS blue/green spec for prod (`<TASK_DEFINITION>`
  substituted by the CodeDeployToECS action)
- `taskdef.json` — task-definition template; `<FAMILY>`/roles/log settings are
  rendered by the build, `<IMAGE1_NAME>` by the CodeDeployToECS action
