# pipeline/ — build & deploy specs

The specs CodeBuild/CodeDeploy consume. Referenced by the `pipeline` Terraform module.

- `buildspec.yml` — CodeBuild phases: build image, tests, (reserved security-scan hook), push ECR
- `appspec.yaml` — CodeDeploy ECS blue/green hook spec for prod
- `taskdef.json` — ECS task definition template (image filled in at deploy time)

*Files below are placeholder stubs — real commands added in the next pass.*
