# module: network

VPC, public/private subnets across 2 AZs, security groups, and (if needed)
NAT-free egress for Fargate tasks.

**Provisions (planned):**
- VPC + 2 public subnets (ALB requires 2 AZs) + 2 private subnets
- Security groups: ALB (prod), ECS tasks
- Internet gateway; route tables

**Cheapest path:** avoid NAT gateway (~$32/mo). Fargate tasks pulling from ECR
+ reaching CodeDeploy can use public subnets with a restricted SG, or VPC
endpoints if private subnets are required. Decision recorded when `.tf` lands.

`msp-control`: supports OPS06 (deploy infra).

*Placeholder — inputs/outputs/main `.tf` to be added.*
