# module: codedeploy-bluegreen

*Last updated: 2026-07-02 13:23*

The production-only blue/green rig. Instantiated for **prod only** (decision #20).

**Provisions:**
- Application Load Balancer (prod listener :80 + optional test listener :8080)
- **Two target groups** (blue + green) for traffic shifting
- CodeDeploy **application** + **deployment group** (ECS compute platform)
- Deployment config: `ECSAllAtOnce` by default (simplest that demonstrates
  rollback); switch `deployment_config_name` to a canary/linear config for a
  slower shift
- Auto-rollback on `DEPLOYMENT_FAILURE` (health checks) **and**
  `DEPLOYMENT_STOP_ON_ALARM` — a CloudWatch alarm on ALB target 5xx

**Pairs with:** `ecs-service` in `blue_green` mode and `appspec.yaml` / `taskdef.json` in `pipeline/`.
The service consumes this module's blue target group; this module's deployment
group consumes the service's name — Terraform resolves the mutual reference
(the resource graph is acyclic: TGs → service → deployment group).

`msp-control`: GAP — automated rollback (CodeDeploy blue/green + traffic shifting).
