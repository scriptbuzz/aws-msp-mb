# module: ecr

*Last updated: 2026-07-02 13:23*

Container image registry for the sample app.

**Provisions:**
- ECR repository (`mb-use1-ecr-app`) with **immutable tags** (promotion is by digest)
- Lifecycle policy (keep last N images — cost control)
- ECR **basic** image scanning on push (free; enhanced/Inspector deferred with other scanners)

Access is granted on the IAM side (build + task-execution role policies), not
via a repository policy — same-account, so a repo policy would be redundant.

`msp-control`: OPS06 (artifact registry; image-by-digest promotion).
