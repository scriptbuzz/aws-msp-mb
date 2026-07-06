# Changelog

*Last updated: 2026-07-06 11:09*

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/), and the
project uses [semantic versioning](https://semver.org/).

## [1.0.5] - 2026-07-06

### Added
- First tagged GitHub Release of the AWS MSP Release Management control.

### Summary of what ships
- Terraform IaC — `network`, `ecr`, `iam`, `ecs-service`, `codedeploy-bluegreen`,
  and `pipeline` modules, with `dev` / `test` / `stage` / `prod` environment roots.
- CI/CD — CodePipeline V2 → CodeBuild → CodeDeploy blue/green on prod
  (dev/test/stage scale-to-zero, no ALB).
- Application — sample static site (`app/`) with version and build-time stamping
  injected at build.
- Documentation and MSP audit evidence for the Release Management (OPS06) control.

### Operational status
- Pipeline runs end-to-end: Source → Build → dev → test → stage → change-record →
  manual approval → prod blue/green.
- Prod is live; audit evidence captured; automated rollback demonstrated with zero
  downtime.

[1.0.5]: https://github.com/scriptbuzz/aws-msp-mb/releases/tag/v1.0.5
