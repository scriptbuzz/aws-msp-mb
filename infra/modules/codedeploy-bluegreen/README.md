# module: codedeploy-bluegreen

The production-only blue/green rig. Instantiated for **prod only** (decision #20).

**Provisions (planned):**
- Application Load Balancer (prod listener + optional test listener)
- **Two target groups** (blue + green) for traffic shifting
- CodeDeploy **application** + **deployment group** (ECS compute platform)
- Deployment config (canary / linear / all-at-once — TBD)
- Auto-rollback: on failed health check **and** on CloudWatch alarm
- CloudWatch alarms watching the green target group

**Pairs with:** `ecs-service` in `blue_green` mode and `appspec.yaml` / `taskdef.json` in `pipeline/`.

`msp-control`: GAP — automated rollback (CodeDeploy blue/green + traffic shifting).

*Placeholder — `.tf` to be added.*
