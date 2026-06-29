# environments/

The **only** place deployment-specific values live. Each env is a thin Terraform
root that calls the shared modules with env-specific inputs + its own
`backend.hcl` (S3 state key). Porting to a new account/org = swap these values,
nothing in `modules/` changes.

| Env | desired_count (idle) | deployment_mode | ALB | always-on? |
|---|---|---|---|---|
| dev | 0 (scale-to-zero) | rolling | no | no |
| test | 0 (scale-to-zero) | rolling | no | no |
| stage | 0 (scale-to-zero) | rolling | no | no |
| **prod** | 1 | **blue/green** | **yes** | **yes** |

Each env folder will contain (next pass): `main.tf` (module calls),
`variables.tf`, `terraform.tfvars`, `backend.hcl`, `versions.tf`, `providers.tf`.
