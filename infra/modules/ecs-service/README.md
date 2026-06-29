# module: ecs-service

A reusable ECS **Fargate** service. One instance of this module per environment.

**Inputs control the per-env behavior:**
- `deployment_mode` — `rolling` (lower envs) or `blue_green` (prod)
- `desired_count` — `0` when idle for scale-to-zero lower envs; `>=1` for prod
- `attach_alb` — `false` for lower envs (no ALB), `true` for prod
- `cpu` / `memory` — smallest viable (0.25 vCPU / 0.5 GB) per cost rule

**Provisions (planned):**
- ECS cluster (shared) + ECS service + task definition
- For `blue_green`: `deploymentController = CODE_DEPLOY`
- For `rolling`: native ECS deployment controller, no target groups
- Optional public IP + restricted SG for lower-env validation (no ALB)

**Scale-to-zero (lower envs):** the pipeline scales `0 → 1`, deploys, validates,
then scales back to `0`. Real deploys, ~$0 idle (decision #20).

`msp-control`: OPS06 (staged promotion / non-prod validation).

*Placeholder — `.tf` to be added.*
