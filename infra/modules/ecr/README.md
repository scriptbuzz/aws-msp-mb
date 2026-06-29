# module: ecr

Container image registry for the sample app.

**Provisions (planned):**
- ECR repository (`mb-use1-ecr-app`)
- Lifecycle policy (keep last N images — cost control)
- ECR **basic** image scanning on push (free; enhanced/Inspector deferred with other scanners)
- Repository policy scoped to the build + task roles

`msp-control`: OPS06 (artifact registry; image-by-digest promotion).

*Placeholder — `.tf` to be added.*
