# module: ecs-service

*Last updated: 2026-07-02 13:23*

A reusable ECS **Fargate** service. One instance of this module per environment.

**Inputs control the per-env behavior:**
- `deployment_mode` — `rolling` (lower envs) or `blue_green` (prod)
- `desired_count` — `0` when idle for scale-to-zero lower envs; `>=1` for prod
- `attach_alb` — `false` for lower envs (no ALB), `true` for prod
- `cpu` / `memory` — smallest viable (0.25 vCPU / 0.5 GB) per cost rule

**Provisions:**
- ECS service + task definition + CloudWatch log group
  (the shared **cluster** lives in the `shared` environment root)
- For `blue_green`: `deploymentController = CODE_DEPLOY`, attached to the blue
  target group (pass `target_group_arn`)
- For `rolling`: native ECS deployment controller, no target groups
- Tasks get a public IP (public-subnet/no-NAT topology — see `network/`)

**Terraform vs. pipeline ownership:** after creation the pipeline registers
task-definition revisions and flips `desired_count`, and CodeDeploy retargets
the load balancer — so the service has `ignore_changes` on all three.

**Scale-to-zero (lower envs):** the pipeline scales `0 → 1`, deploys, validates,
then scales back to `0`. Real deploys, ~$0 idle (decision #20).

`msp-control`: OPS06 (staged promotion / non-prod validation).
