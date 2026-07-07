#!/usr/bin/env bash
# Pre-flight permission check: can the logged-in identity deploy this solution?
# Checks everything in docs/AWS_ACCOUNT_SETUP.md §B2/§B3. READ-ONLY — nothing is
# created or changed.
#
# How it checks (two methods, on purpose):
#   1. Regional services (S3/EC2/ECS/ELB/Code*/...) — real read-only probe calls
#      (list/describe). A probe proves the service is reachable through identity
#      policies AND org SCPs. Under the documented permission options the read
#      and write actions travel together: PowerUser is allow-all-except-IAM, and
#      the granular infra/deploy-permissions-services.json contains both reads
#      and writes per service — so a passing probe implies the writes are
#      attached too (attach that file verbatim; don't hand-pick actions from it).
#      (The IAM policy simulator is NOT used here: from a member account it
#      cannot evaluate org SCPs and false-denies every regional service.)
#   2. IAM (the fine-grained part) — the IAM policy simulator, which is reliable
#      for global IAM actions: role/policy management scoped to mb-* and
#      iam:PassRole with its service condition.
#
# Usage: scripts/check-deploy-permissions.sh        (after `aws sso login`)
#        scripts/check-deploy-permissions.sh <role-arn>   # admin checking another identity
#
# The simulator step needs iam:SimulatePrincipalPolicy (+ iam:ListRoles for SSO
# roles). Plain PowerUser lacks these: the script then reports the probes and
# marks the IAM checks as UNVERIFIED instead of failing.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/.env" ] && { set -a; . "$ROOT/.env"; set +a; }
AWS="${AWS_BIN:-$HOME/bin/aws}"; command -v aws >/dev/null 2>&1 && AWS=aws
: "${AWS_PROFILE:?set AWS_PROFILE in .env}"
REGION="${AWS_REGION:-us-east-1}"
export AWS_PROFILE AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION"

CALLER_ARN=$($AWS sts get-caller-identity --query Arn --output text 2>/dev/null) ||
  { echo "ERROR: no AWS credentials — run: aws sso login --profile $AWS_PROFILE" >&2; exit 1; }
ACCOUNT_ID=$($AWS sts get-caller-identity --query Account --output text)

echo "account : $ACCOUNT_ID"
echo "caller  : $CALLER_ARN"
echo

MISSFILE=$(mktemp); UNVERFILE=$(mktemp); trap 'rm -f "$MISSFILE" "$UNVERFILE"' EXIT

# --- 1. service access — real read-only probes -----------------------------------
probe() { # $1 = label, rest = read-only command
  local label="$1"; shift
  local err
  if err=$("$@" 2>&1 >/dev/null); then
    printf '  OK       %s\n' "$label"
  else
    case "$err" in
      *AccessDenied*|*UnauthorizedOperation*|*"not authorized"*)
        printf '  MISSING  %s\n' "$label"; echo "$label" >> "$MISSFILE" ;;
      *NotFoundException*|*"does not exist"*)
        # Permission is evaluated before existence: NotFound (not AccessDenied)
        # proves the action is allowed — the resource just isn't created yet.
        printf '  OK       %s (allowed; resource not created yet)\n' "$label" ;;
      *)
        printf '  ERROR    %s — %s\n' "$label" "$(echo "$err" | head -1)"
        echo "$label (indeterminate)" >> "$UNVERFILE" ;;
    esac
  fi
}

echo "== service access (read-only probes; each maps to a §B2 row)"
probe "S3 (buckets: state, artifacts)"        $AWS s3api list-buckets
probe "EC2/VPC (network module)"              $AWS ec2 describe-vpcs
# Probe the project repo by name: the granular policy scopes ECR to repository/mb-*,
# so an unscoped describe would false-deny. NotFound (fresh account) counts as OK.
probe "ECR (image registry)"                  $AWS ecr describe-repositories --repository-names mb-use1-ecr-app
probe "ECS (cluster + services)"              $AWS ecs list-clusters
probe "ELBv2 (prod ALB, blue/green)"          $AWS elbv2 describe-load-balancers
probe "CodePipeline"                          $AWS codepipeline list-pipelines
probe "CodeBuild"                             $AWS codebuild list-projects
probe "CodeDeploy"                            $AWS deploy list-applications
probe "CodeConnections (GitHub link)"         $AWS codestar-connections list-connections
probe "CloudWatch Logs (build/task logs)"     $AWS logs describe-log-groups --limit 1
probe "CloudWatch (5xx rollback alarm)"       $AWS cloudwatch describe-alarms --max-records 1
probe "SSM Parameter Store (github token)"    $AWS ssm describe-parameters --max-results 1

# --- 2. IAM — policy simulator (reliable for global IAM actions) ------------------
echo
echo "== IAM (simulator; scoped to the mb-* roles/policies the stack creates)"

# Resolve the IAM principal to simulate.
PRINCIPAL_ARN=""
if [ $# -ge 1 ]; then
  PRINCIPAL_ARN="$1"
else
  case "$CALLER_ARN" in
    *:root)  echo "  OK       (account root — full IAM access)"; PRINCIPAL_ARN="" ;;
    *:user/*) PRINCIPAL_ARN="$CALLER_ARN" ;;
    *:assumed-role/*)
      ROLE_NAME=$(echo "$CALLER_ARN" | cut -d/ -f2)
      PRINCIPAL_ARN=$($AWS iam list-roles \
        --query "Roles[?RoleName=='$ROLE_NAME'].Arn | [0]" --output text 2>/dev/null)
      [ "$PRINCIPAL_ARN" != "None" ] || PRINCIPAL_ARN="" ;;
    *)
      UNRECOGNIZED_PRINCIPAL=1 ;;
  esac
fi

iam_unverified() {
  echo "  UNVERIFIED — cannot run the IAM simulator as this identity ($1)."
  echo "               Re-run as an admin (optionally: $0 <role-arn-to-check>)."
  echo "IAM checks" >> "$UNVERFILE"
}

if [ -n "$PRINCIPAL_ARN" ]; then
  ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/mb-use1-codepipeline-role"
  POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/mb-use1-deny-direct-prod-deploy"

  sim() { # $1 = resource arn, $2 = extra context ("-" for none), rest = actions
    local resource="$1" ctx="$2"; shift 2
    local args=(--policy-source-arn "$PRINCIPAL_ARN" --action-names "$@" --resource-arns "$resource")
    [ "$ctx" != "-" ] && args+=(--context-entries "$ctx")
    local out
    if ! out=$($AWS iam simulate-principal-policy "${args[@]}" \
          --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output text 2>&1); then
      iam_unverified "$(echo "$out" | head -1)"; return 1
    fi
    while read -r action decision; do
      [ -n "$action" ] || continue
      if [ "$decision" = "allowed" ]; then
        printf '  OK       %s\n' "$action"
      else
        printf '  MISSING  %s (%s)\n' "$action" "$decision"
        echo "$action" >> "$MISSFILE"
      fi
    done <<< "$out"
  }

  # Simulate against the concrete ARNs/conditions the granular policy uses, so a
  # correctly-scoped policy passes (and an unscoped "*" simulation doesn't lie).
  SLR_ARN="arn:aws:iam::${ACCOUNT_ID}:role/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS"
  sim "$ROLE_ARN" - \
      iam:CreateRole iam:DeleteRole iam:GetRole iam:TagRole \
      iam:PutRolePolicy iam:DeleteRolePolicy iam:AttachRolePolicy \
      iam:DetachRolePolicy iam:UpdateAssumeRolePolicy &&
  sim "$POLICY_ARN" - \
      iam:CreatePolicy iam:DeletePolicy iam:GetPolicy iam:TagPolicy &&
  sim "$ROLE_ARN" \
      "ContextKeyName=iam:PassedToService,ContextKeyValues=codepipeline.amazonaws.com,ContextKeyType=string" \
      iam:PassRole &&
  sim "$SLR_ARN" \
      "ContextKeyName=iam:AWSServiceName,ContextKeyValues=ecs.amazonaws.com,ContextKeyType=string" \
      iam:CreateServiceLinkedRole || true
elif [ -n "${UNRECOGNIZED_PRINCIPAL:-}" ]; then
  iam_unverified "unrecognized principal type: $CALLER_ARN"
elif [ -n "${ROLE_NAME:-}" ]; then
  iam_unverified "iam:ListRoles denied — cannot resolve the SSO role ARN"
fi

# --- summary ----------------------------------------------------------------------
echo
miss=0; [ -s "$MISSFILE" ] && miss=$(wc -l < "$MISSFILE" | tr -d ' ')
unver=0; [ -s "$UNVERFILE" ] && unver=$(wc -l < "$UNVERFILE" | tr -d ' ')

if [ "$miss" -gt 0 ]; then
  echo "RESULT: $miss permission(s) MISSING — this identity cannot deploy yet."
  echo
  echo "Fix (docs/AWS_ACCOUNT_SETUP.md §B/§B2/§B3) — no AWS-managed policy required:"
  echo "  - service-access misses -> attach infra/deploy-permissions-services.json"
  echo "  - IAM misses            -> attach infra/deploy-permissions.json"
  echo "  (or, if allowed in your org: PowerUserAccess + deploy-permissions.json)"
  exit 1
elif [ "$unver" -gt 0 ]; then
  echo "RESULT: no missing permissions detected, but $unver check(s) UNVERIFIED (see above)."
  exit 3
else
  echo "RESULT: all deploy permissions present — ready for scripts/rollout.sh (docs/ROLLOUT.md)."
fi
