# module: network

*Last updated: 2026-07-02 13:23*

VPC, public subnets across 2 AZs, and the two security groups.

**Provisions:**
- VPC + 2 public subnets (ALB requires 2 AZs), internet gateway, route table
- Security groups: ALB (prod; 80 + 8080 test listener), ECS tasks

**Decision (recorded):** no NAT gateway (~$32/mo) and **no private subnets**.
Fargate tasks run in public subnets with a public IP and a restricted SG —
the cheapest topology that lets tasks pull from ECR (standing rule #1).
The task SG allows the container port from the ALB SG and from
`task_ingress_cidrs` (default world — the app is a public static site, and
lower-env validation curls the task's public IP from CodeBuild, which has no
fixed egress IP without a NAT). Tighten `task_ingress_cidrs` if the app ever
serves non-public content.

`msp-control`: supports Release Management (deploy infra).
