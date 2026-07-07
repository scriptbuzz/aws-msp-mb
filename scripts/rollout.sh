#!/usr/bin/env bash
# Stage-gated rollout driver for the AWS MSP Release Management stack.
# Every stage is separately applied, verified, and undoable (docs/ROLLOUT.md).
#
#   scripts/rollout.sh status                 # where am I?
#   scripts/rollout.sh apply  <stage>
#   scripts/rollout.sh verify <stage>
#   scripts/rollout.sh undo   <stage>
#   scripts/rollout.sh undo-all               # tear everything down (reverse order)
#
# Stages, in order: bootstrap shared dev test stage prod
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# --- env / tools ---------------------------------------------------------------
[ -f .env ] && { set -a; . ./.env; set +a; }
: "${AWS_PROFILE:?set AWS_PROFILE in .env}"
: "${AWS_REGION:=us-east-1}"
export AWS_PROFILE AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"

AWS="${AWS_BIN:-$HOME/bin/aws}";            command -v aws        >/dev/null 2>&1 && AWS=aws
TF="${TERRAFORM_BIN:-$HOME/bin/terraform}"; command -v terraform  >/dev/null 2>&1 && TF=terraform

ACCOUNT_ID="$($AWS sts get-caller-identity --query Account --output text)" ||
  { echo "ERROR: no AWS credentials — run: aws sso login --profile $AWS_PROFILE"; exit 1; }

# The project is pinned to us-east-1 (resource names embed the use1 code and
# bucket creation assumes it). Redeploys target a new ACCOUNT, same region.
[ "$AWS_REGION" = "us-east-1" ] || { echo "ERROR: this project is pinned to us-east-1 (AWS_REGION=$AWS_REGION)" >&2; exit 1; }
ORG=mb
REPO_NAME=aws-msp-mb
REGION_CODE=use1
STATE_BUCKET="${ORG}-msp-tfstate-${ACCOUNT_ID}"
ARTIFACT_BUCKET="${ORG}-msp-artifacts-${ACCOUNT_ID}"
ENVS_LOWER="dev test stage"
ALL_STAGES="bootstrap shared dev test stage prod"

say()  { printf '\n== %s\n' "$*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

tf_dir() { echo "infra/environments/$1"; }

tf_init() { ( cd "$(tf_dir "$1")" && $TF init -backend-config=backend.hcl -input=false -upgrade >/dev/null ); }

# --- bootstrap: buckets + per-root config files ---------------------------------

bucket_exists() { $AWS s3api head-bucket --bucket "$1" >/dev/null 2>&1; }

make_bucket() {
  bucket_exists "$1" && { echo "bucket $1 already exists"; return; }
  $AWS s3api create-bucket --bucket "$1" >/dev/null   # us-east-1: no LocationConstraint
  $AWS s3api put-bucket-versioning --bucket "$1" --versioning-configuration Status=Enabled
  $AWS s3api put-public-access-block --bucket "$1" --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  echo "created bucket $1 (versioned, public access blocked)"
}

purge_bucket() {
  bucket_exists "$1" || { echo "bucket $1 gone"; return; }
  echo "purging all object versions from $1 ..."
  $AWS s3api list-object-versions --bucket "$1" \
      --query '{Objects: [Versions[].{Key:Key,VersionId:VersionId}, DeleteMarkers[].{Key:Key,VersionId:VersionId}][] }' \
      --output json > /tmp/purge.$$.json
  if python3 -c "import json,sys; d=json.load(open('/tmp/purge.$$.json')); sys.exit(0 if d.get('Objects') else 1)"; then
    # chunked delete (max 1000 per call)
    python3 - "$1" /tmp/purge.$$.json <<'PYEOF'
import json, subprocess, sys
bucket, path = sys.argv[1], sys.argv[2]
objs = json.load(open(path)).get("Objects") or []
for i in range(0, len(objs), 1000):
    payload = json.dumps({"Objects": objs[i:i+1000], "Quiet": True})
    subprocess.run(["aws" , "s3api", "delete-objects", "--bucket", bucket, "--delete", payload],
                   check=True, capture_output=True)
print(f"deleted {len(objs)} versions/markers")
PYEOF
  fi
  rm -f /tmp/purge.$$.json
  $AWS s3api delete-bucket --bucket "$1"
  echo "deleted bucket $1"
}

write_root_config() { # $1 = root name
  local d; d="$(tf_dir "$1")"
  cat > "$d/backend.hcl" <<EOF
bucket       = "$STATE_BUCKET"
key          = "$REPO_NAME/$1/terraform.tfstate"
region       = "$AWS_REGION"
use_lockfile = true
EOF
  if [ "$1" = shared ]; then
    printf 'artifact_bucket_name = "%s"\n' "$ARTIFACT_BUCKET" > "$d/terraform.tfvars"
  else
    printf 'state_bucket_name = "%s"\n' "$STATE_BUCKET" > "$d/terraform.tfvars"
  fi
  echo "wrote $d/backend.hcl + terraform.tfvars"
}

apply_bootstrap() {
  say "bootstrap: state + artifact buckets in $ACCOUNT_ID ($AWS_REGION)"
  make_bucket "$STATE_BUCKET"
  make_bucket "$ARTIFACT_BUCKET"
  for r in shared $ENVS_LOWER prod; do write_root_config "$r"; done
}

verify_bootstrap() {
  local ok=0
  for b in "$STATE_BUCKET" "$ARTIFACT_BUCKET"; do
    if bucket_exists "$b"; then
      v="$($AWS s3api get-bucket-versioning --bucket "$b" --query Status --output text)"
      echo "OK  bucket $b (versioning: $v)"
    else echo "FAIL bucket $b missing"; ok=1; fi
  done
  for r in shared $ENVS_LOWER prod; do
    [ -f "$(tf_dir "$r")/backend.hcl" ] && echo "OK  $(tf_dir "$r")/backend.hcl" || { echo "FAIL $(tf_dir "$r")/backend.hcl missing"; ok=1; }
  done
  return $ok
}

undo_bootstrap() {
  say "undo bootstrap: deleting buckets (state is lost — envs must already be destroyed)"
  purge_bucket "$ARTIFACT_BUCKET"
  purge_bucket "$STATE_BUCKET"
}

# --- terraform stages ------------------------------------------------------------

apply_root()  { say "apply $1"; tf_init "$1"; ( cd "$(tf_dir "$1")" && $TF apply -input=false -auto-approve ); }
undo_root()   { say "destroy $1"; tf_init "$1"; ( cd "$(tf_dir "$1")" && $TF destroy -input=false -auto-approve ); }

# Stage-2 substages: targeted applies inside the shared root (dependency order).
# 2f (shared-pipeline) is a full untargeted apply that converges the root.
target_for() {
  case "$1" in
    shared-network)    echo 'module.network[0]' ;;
    shared-ecr)        echo 'module.ecr[0]' ;;
    shared-cluster)    echo 'aws_ecs_cluster.shared[0]' ;;
    shared-connection) echo 'module.pipeline[0].aws_codestarconnections_connection.github' ;;
    shared-iam)        echo 'module.iam[0]' ;;
    *) return 1 ;;
  esac
}

apply_shared_sub() {
  local tgt; tgt="$(target_for "$1")" || die "unknown substage $1"
  say "apply $1 (target: $tgt)"
  tf_init shared
  ( cd "$(tf_dir shared)" && $TF apply -input=false -auto-approve -target="$tgt" )
}

undo_shared_sub() {
  local tgt; tgt="$(target_for "$1")" || die "unknown substage $1"
  say "destroy $1 (target: $tgt — dependents included)"
  tf_init shared
  ( cd "$(tf_dir shared)" && $TF destroy -input=false -auto-approve -target="$tgt" )
}

verify_shared_network() {
  $AWS ec2 describe-vpcs --filters "Name=tag:Name,Values=${ORG}-${REGION_CODE}-vpc" \
    --query 'Vpcs[0].{vpc:VpcId,cidr:CidrBlock,state:State}' --output json
  $AWS ec2 describe-subnets --filters "Name=tag:Name,Values=${ORG}-${REGION_CODE}-public-*" \
    --query 'length(Subnets)' --output text | sed 's/^/public subnets: /'
  $AWS ec2 describe-security-groups --filters "Name=group-name,Values=${ORG}-${REGION_CODE}-alb-sg,${ORG}-${REGION_CODE}-task-sg" \
    --query 'SecurityGroups[].GroupName' --output text | sed 's/^/security groups: /'
}

verify_shared_ecr() {
  $AWS ecr describe-repositories --repository-names "${ORG}-${REGION_CODE}-ecr-app" \
    --query 'repositories[0].{name:repositoryName,uri:repositoryUri,tagMutability:imageTagMutability,scanOnPush:imageScanningConfiguration.scanOnPush}' --output json
}

verify_shared_cluster() {
  $AWS ecs describe-clusters --clusters "${ORG}-${REGION_CODE}-cluster" \
    --query 'clusters[0].{name:clusterName,status:status}' --output json
}

verify_shared_connection() {
  $AWS codestar-connections list-connections --provider-type-filter GitHub \
    --query "Connections[?ConnectionName=='${ORG}-${REGION_CODE}-github'].{name:ConnectionName,status:ConnectionStatus}" --output json
  echo "PENDING is expected until authorized in the console (CodePipeline > Settings > Connections)"
}

verify_shared_iam() {
  for r in codepipeline-role codebuild-role codedeploy-role task-exec-role task-role; do
    $AWS iam get-role --role-name "${ORG}-${REGION_CODE}-$r" --query 'Role.RoleName' --output text | sed 's/^/OK  role /'
  done
  $AWS iam list-policies --scope Local --query "Policies[?PolicyName=='${ORG}-${REGION_CODE}-deny-direct-prod-deploy'].PolicyName" --output text | sed 's/^/OK  policy /'
}

# --- Stage-6 (prod) substages: targeted applies in the prod root ----------------
# Dependency order: alb -> service -> codedeploy (the deployment group references
# the ECS service by name; the service attaches to the blue target group).
prod_targets_for() {
  case "$1" in
    prod-alb)
      echo "-target=module.bluegreen[0].aws_lb.prod -target=module.bluegreen[0].aws_lb_target_group.blue -target=module.bluegreen[0].aws_lb_target_group.green -target=module.bluegreen[0].aws_lb_listener.prod -target=module.bluegreen[0].aws_lb_listener.test" ;;
    prod-service)
      echo "-target=module.app[0]" ;;
    *) return 1 ;;
  esac
}

apply_prod_sub() {
  local flags; flags="$(prod_targets_for "$1")" || die "unknown substage $1"
  say "apply $1 ($flags)"
  tf_init prod
  ( cd "$(tf_dir prod)" && $TF apply -input=false -auto-approve $flags )
}

undo_prod_sub() {
  local flags; flags="$(prod_targets_for "$1")" || die "unknown substage $1"
  say "destroy $1 ($flags — dependents included)"
  tf_init prod
  ( cd "$(tf_dir prod)" && $TF destroy -input=false -auto-approve $flags )
}

verify_prod_alb() {
  $AWS elbv2 describe-load-balancers --names "${ORG}-prod-${REGION_CODE}-alb" \
    --query 'LoadBalancers[0].{name:LoadBalancerName,dns:DNSName,state:State.Code}' --output json
  $AWS elbv2 describe-target-groups \
    --names "${ORG}-prod-${REGION_CODE}-tg-blue" "${ORG}-prod-${REGION_CODE}-tg-green" \
    --query 'TargetGroups[].TargetGroupName' --output text | sed 's/^/target groups: /'
}

verify_prod_service() {
  $AWS ecs describe-services --cluster "${ORG}-${REGION_CODE}-cluster" --services "${ORG}-prod-${REGION_CODE}-app-svc" \
    --query 'services[0].{status:status,desired:desiredCount,running:runningCount}' --output json
  echo "NOTE: task pulls :bootstrap (absent until first pipeline release) — running may stay 0 and ALB serves 503 until Stage 7. Expected."
}

verify_shared() {
  tf_init shared
  ( cd "$(tf_dir shared)" && $TF output )
  local pipeline conn
  pipeline="$(cd "$(tf_dir shared)" && $TF output -raw pipeline_name)"
  conn="$(cd "$(tf_dir shared)" && $TF output -raw github_connection_status)"
  $AWS codepipeline get-pipeline --name "$pipeline" >/dev/null && echo "OK  pipeline $pipeline exists"
  $AWS ecr describe-repositories --repository-names "${ORG}-${REGION_CODE}-ecr-app" >/dev/null && echo "OK  ECR ${ORG}-${REGION_CODE}-ecr-app"
  echo "GitHub connection status: $conn"
  [ "$conn" = AVAILABLE ] || echo "ACTION NEEDED: authorize the connection in the console (Developer Tools > Settings > Connections), then re-verify"
}

verify_env() { # dev/test/stage
  local svc="${ORG}-$1-${REGION_CODE}-app-svc"
  $AWS ecs describe-services --cluster "${ORG}-${REGION_CODE}-cluster" --services "$svc" \
    --query 'services[0].{status:status,desired:desiredCount,running:runningCount}' --output json \
    && echo "OK  $svc (expect status ACTIVE, desired 0 while idle)"
}

verify_prod() {
  verify_env prod || true
  local dns
  dns="$(cd "$(tf_dir prod)" && $TF output -raw site_url)"
  echo "prod URL: $dns   (503 is EXPECTED until the first pipeline release deploys an image)"
  $AWS deploy get-deployment-group --application-name "${ORG}-prod-${REGION_CODE}-cd-app" \
      --deployment-group-name "${ORG}-prod-${REGION_CODE}-cd-group" \
      --query 'deploymentGroupInfo.deploymentGroupName' --output text \
    && echo "OK  CodeDeploy deployment group"
  curl -s -o /dev/null -w 'ALB HTTP status: %{http_code}\n' --max-time 10 "$dns" || echo "ALB not answering yet (DNS can take a minute)"
}

# --- driver ---------------------------------------------------------------------

status() {
  echo "account: $ACCOUNT_ID  profile: $AWS_PROFILE  region: $AWS_REGION"
  bucket_exists "$STATE_BUCKET"    && echo "bootstrap: state bucket present"    || echo "bootstrap: NOT done"
  bucket_exists "$ARTIFACT_BUCKET" && echo "bootstrap: artifact bucket present" || true
  for r in shared $ENVS_LOWER prod; do
    if $AWS s3api head-object --bucket "$STATE_BUCKET" --key "$REPO_NAME/$r/terraform.tfstate" >/dev/null 2>&1; then
      echo "$r: state exists (applied)"
    else
      echo "$r: not applied"
    fi
  done
}

cmd="${1:-status}"; stg="${2:-}"

case "$cmd" in
  status) status ;;
  apply|verify|undo)
    [ -n "$stg" ] || die "usage: $0 $cmd <bootstrap|shared|dev|test|stage|prod>"
    case "$cmd-$stg" in
      apply-bootstrap)  apply_bootstrap ;;
      verify-bootstrap) verify_bootstrap ;;
      undo-bootstrap)   undo_bootstrap ;;
      apply-shared-network|apply-shared-ecr|apply-shared-cluster|apply-shared-connection|apply-shared-iam) apply_shared_sub "$stg" ;;
      undo-shared-network|undo-shared-ecr|undo-shared-cluster|undo-shared-connection|undo-shared-iam)      undo_shared_sub "$stg" ;;
      verify-shared-network)    verify_shared_network ;;
      verify-shared-ecr)        verify_shared_ecr ;;
      verify-shared-cluster)    verify_shared_cluster ;;
      verify-shared-connection) verify_shared_connection ;;
      verify-shared-iam)        verify_shared_iam ;;
      apply-shared-pipeline)    apply_root shared ;;   # final converging apply
      verify-shared-pipeline)   verify_shared ;;
      apply-shared)     apply_root shared ;;
      verify-shared)    verify_shared ;;
      undo-shared)      undo_root shared ;;
      apply-dev|apply-test|apply-stage)   apply_root "$stg" ;;
      verify-dev|verify-test|verify-stage) verify_env "$stg" ;;
      undo-dev|undo-test|undo-stage)      undo_root "$stg" ;;
      apply-prod-alb|apply-prod-service)  apply_prod_sub "$stg" ;;
      undo-prod-alb|undo-prod-service)    undo_prod_sub "$stg" ;;
      verify-prod-alb)      verify_prod_alb ;;
      verify-prod-service)  verify_prod_service ;;
      apply-prod-codedeploy)  apply_root prod ;;   # final converging apply of the prod root
      verify-prod-codedeploy) verify_prod ;;
      apply-prod)       apply_root prod ;;
      verify-prod)      verify_prod ;;
      undo-prod)        undo_root prod ;;
      *) die "unknown stage '$stg' (stages: $ALL_STAGES)" ;;
    esac ;;
  undo-all)
    say "FULL TEARDOWN (reverse order)"
    for r in prod stage test dev shared; do
      if $AWS s3api head-object --bucket "$STATE_BUCKET" --key "$REPO_NAME/$r/terraform.tfstate" >/dev/null 2>&1; then
        undo_root "$r"
      else
        echo "skip $r (no state)"
      fi
    done
    undo_bootstrap ;;
  *) die "usage: $0 {status|apply|verify|undo} [stage] | undo-all" ;;
esac
