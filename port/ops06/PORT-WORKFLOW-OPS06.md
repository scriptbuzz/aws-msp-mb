# Port workflow — OPS06 (Release Management control) through the platform pipeline

*Last updated: 2026-07-15 17:43*

Deploys the **aws-msp-ops06** workload (an ECS Fargate release-management stack:
its own app pipeline, four environments, prod blue/green behind an ALB) into the
demo account via the tooling→demo Terraform pipeline. Mirrors the aws-msp-plat03
port pattern: flat additive files, one push, one approval.

---

## 1. What's in the zip

```
terraform/            (10 additive files — the scaffold's 7 files are NOT included)
├── variables-app.tf  all workload variables (every one defaulted) + naming locals
├── data.tf           aws_region / aws_partition / aws_availability_zones lookups
├── network.tf        VPC, 2 public subnets, IGW, route table, ALB + task SGs (no NAT)
├── ecr.tf            image repo (immutable tags, scan-on-push, keep-last-10)
├── cluster.tf        one ECS cluster for all four environments
├── artifacts.tf      S3 artifact bucket for the app pipeline (force_destroy)
├── iam-cicd.tf       5 service roles + policies + deny-direct-prod-deploy guardrail
├── ecs-services.tf   dev/test/stage (scale-to-zero) + prod (always-on, CODE_DEPLOY)
├── alb-bluegreen.tf  ALB, blue/green target groups, listeners, 5xx alarm, CodeDeploy
└── pipeline.tf       GitHub connection + 3 CodeBuild projects + CodePipeline V2
PORT-WORKFLOW-OPS06.md   (this file)
COMMANDS-OPS06.txt       (copy-paste command sheet)
```

No providers beyond `hashicorp/aws` are used, so there is **no
versions_override.tf**. Nothing in the zip touches the 7 protected scaffold files.

What makes this port unusual: the workload **is itself a CI/CD pipeline**. The
platform pipeline (tooling account) deploys the infrastructure; the deployed
**app pipeline** (demo account) then builds the container image from GitHub
(`scriptbuzz/aws-msp-mb`) and promotes it dev → test → stage → approval → prod
blue/green.

## 2. Precondition — clean scaffold (STOP if not)

Before unzipping, `terraform/` in the work repo must contain **only the 7
protected scaffold files** (`backend.tf`, `providers.tf`, `versions.tf`,
`variables.tf`, `terraform.tfvars`, `locals.tf`, `main.tf`), and the state must
hold no workload resources (a quick `terraform plan` shows no changes and no
existing workload resources).

If a previous project (e.g. aws-msp-plat03) is still present or deployed:
**STOP.** Remove it first — delete its files, push, approve the pure-destroy
plan — as a separate push, per the standard serial-projects process. Never mix a
removal and this deployment in one plan.

## 3. Work-laptop steps (Windows 11)

### Part 0 — every session starts here (PowerShell)

```powershell
$env:AWS_PROFILE = "<TOOLING_PROFILE>"        # terraform's credentials — FIRST, always
aws sso login --profile <TOOLING_PROFILE>
aws sts get-caller-identity                    # MUST show the tooling account id
```

### Unzip (additive) and safety-gate

```powershell
cd <WORK_REPO>
Expand-Archive -Path ..\aws-msp-ops06-port.zip -DestinationPath . -Force
git status        # SAFETY GATE: must list ONLY new files (10 .tf + 2 docs).
                  # Any "modified:" line means a protected file was touched — stop, investigate.
```

### Pre-flight (the same gates the pipeline enforces)

```powershell
cd terraform
terraform fmt -check -recursive    # must output nothing
terraform init                     # real init (backend + provider resolve)
terraform validate                 # must print Success!
terraform plan                     # optional dress rehearsal — expect:
                                   #   Plan: 52 to add, 0 to change, 0 to destroy.
cd ..
```

Any `change`/`destroy` count other than 0 means the scaffold isn't clean — back
to §2.

### Ship

```powershell
git add -A
git commit -m "Deploy aws-msp-ops06 release-management stack"
git push
```

## 4. What happens next (pipeline narrative)

| Stage | Account | What happens |
|---|---|---|
| Source | tooling | CodeCommit push event hands the repo to the pipeline |
| Plan | tooling | CodeBuild: `terraform fmt -check` → `init` → `validate` → `plan` saved as the `tfplan` artifact. Review it: **52 to add, 0 to change, 0 to destroy** |
| Manual approval | tooling | Admin approves the reviewed plan |
| Apply | tooling→demo | CodeBuild applies the **saved tfplan** via `assume_role` (TerraformDeploymentRole) into the demo account |

**Realistic apply duration: 4–6 minutes.** Long pole is the ALB (~2–3 min);
everything else (IAM, ECS, CodePipeline, CodeBuild, ECR, S3) is seconds each.

Immediately after apply, expect in the demo account:
- All 52 resources tagged with the platform's common tags.
- dev/test/stage ECS services: ACTIVE, desired 0, running 0 — **correct**.
- prod ECS service: desired 1, running 0 (the `:bootstrap` image tag doesn't
  exist yet) and the ALB URL serves **HTTP 503 — correct** until the first app
  release.
- The app pipeline's first execution (triggered on creation) **fails at Source**
  — the GitHub connection is still PENDING. Also correct; fixed next.

## 5. One-time, post-apply: authorize the GitHub connection (demo account)

The app pipeline sources from GitHub `scriptbuzz/aws-msp-mb` through a
CodeConnections connection that is born PENDING. Authorize it once, in the
**demo** account console:

1. Sign in to the demo account console (us-east-1).
2. Developer Tools → **Settings → Connections** → `aws-msp-ops06-use1-github`
   → **Update pending connection**.
3. Complete the GitHub OAuth ("AWS Connector for GitHub" app), granting access
   to `scriptbuzz/aws-msp-mb`.
4. Status flips to **AVAILABLE**.

This cannot be scripted (OAuth handshake by design). GitHub credentials with
access to that repo are required.

## 6. First app release + verification (demo account)

Start the app pipeline manually (push-triggering also works once the GitHub app
has repo access):

```powershell
aws codepipeline start-pipeline-execution --name aws-msp-ops06-use1-pipeline-app --profile <DEMO_PROFILE> --region us-east-1
```

Flow: Source → Build (docker image → ECR by digest, ~3–5 min) → Deploy-dev →
Deploy-test → Deploy-stage (each spins a task 0→1, validates over its public
IP, scales back to 0 — ~2–3 min apiece) → ChangeRecord + **ManualApproval**
(approve it in the demo console: CodePipeline → the pipeline → Review) →
Deploy-prod (blue/green, ~2–3 min). **End to end ~12–18 min** including your
approval latency.

Verify:

```powershell
# connection is AVAILABLE
aws codestar-connections list-connections --profile <DEMO_PROFILE> --region us-east-1 --query "Connections[?ConnectionName=='aws-msp-ops06-use1-github'].ConnectionStatus"

# pipeline execution Succeeded
aws codepipeline list-pipeline-executions --pipeline-name aws-msp-ops06-use1-pipeline-app --profile <DEMO_PROFILE> --region us-east-1 --max-items 1

# the live site answers 200 with a version stamp (health endpoint = "/")
$ALB = aws elbv2 describe-load-balancers --names aws-msp-ops06-prod-use1-alb --profile <DEMO_PROFILE> --region us-east-1 --query "LoadBalancers[0].DNSName" --output text
curl.exe -s -o NUL -w "%{http_code}" http://$ALB/       # expect 200
start http://$ALB/                                       # page shows build version + deploy time

# prod service healthy
aws ecs describe-services --cluster aws-msp-ops06-use1-cluster --services aws-msp-ops06-prod-use1-app-svc --profile <DEMO_PROFILE> --region us-east-1 --query "services[0].{desired:desiredCount,running:runningCount}"
```

## 7. Operations

- **Release**: bump `app/VERSION` in the GitHub repo, commit to `main`, push.
  The V2 trigger fires on `app/*` changes (requires the GitHub app's repo
  access); otherwise `start-pipeline-execution` as above. Every release MUST be
  a new commit — ECR tags are immutable (`<version>-<commit>`), re-running the
  same commit fails the Build stage by design.
- **Pause (cut the ~$9/mo task)**: scale prod to 0 —
  `aws ecs update-service --cluster aws-msp-ops06-use1-cluster --service aws-msp-ops06-prod-use1-app-svc --desired-count 0`.
  The ALB (~$16/mo) keeps billing while it exists; full stop = remove the
  project (§9). **Resume**: same command with `--desired-count 1`, then wait
  ~2 min.
- **Rollback demo**: CodeDeploy auto-rolls-back on deployment failure or a 5xx
  alarm; a deliberately bad image never receives traffic (green fails health
  checks, blue keeps serving).

## 8. Failure table

| Symptom | Cause | Fix |
|---|---|---|
| Plan stage fails instantly on fmt | file edited on the laptop without re-formatting | `terraform fmt -recursive`, commit, push |
| `Error: ... no version is selected` for a provider | stale init in the build | re-run the stage (init runs fresh); locally: `terraform init` |
| Plan shows changes/destroys ≠ 0 | scaffold not clean — previous project still in state | back to §2: remove old project first (separate push) |
| Apply: `AccessDenied` | wrong account/role (deployment role has admin) | `aws sts get-caller-identity`; confirm tooling profile + demo assume_role |
| App pipeline Source fails: connection not available | GitHub connection still PENDING | §5 authorization |
| App pipeline Build fails: `AccountLimitExceededException ... 0 builds in queue` | new-account CodeBuild concurrency hold in the demo account | AWS Support case to lift the account hold (quota requests don't apply) |
| App pipeline Build fails: image tag already exists | re-ran the same commit against immutable ECR tags | new commit (bump `app/VERSION`), push |
| Prod URL serves 503 | no release has reached prod yet (bootstrap tag) | run the first release (§6) |
| Push didn't trigger the app pipeline | GitHub app lacks repo access | GitHub → Settings → Applications → AWS Connector for GitHub → grant repo; or start manually |

## 9. Removing this project later

Delete the 10 workload `.tf` files (and the two docs) from the work repo, push;
the plan shows **only destroys (52)**; same approval flow. Teardown is designed
clean: ECR `force_delete`, artifact bucket `force_destroy`, no snapshots, no
secret recovery windows.

Post-destroy verification (tag sweep — `<PROJECT_TAG>` = the `project` value in
`terraform/terraform.tfvars`):

```powershell
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=<PROJECT_TAG> --profile <DEMO_PROFILE> --region us-east-1 --query "ResourceTagMappingList[].ResourceARN"
```

Expect `[]` (CodeConnections and just-deleted ECS services may echo for a few
minutes).

## 10. Windows 11 notes

- PowerShell has no `VAR=$(...)`: use `$V = aws ...` (as in §6).
- `unzip` → `Expand-Archive`; `open` → `start`; `curl` is aliased in PowerShell —
  use `curl.exe` for the real binary.
- Git Bash runs every command in this document as written for bash, if preferred.
