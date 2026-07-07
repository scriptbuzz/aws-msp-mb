#!/usr/bin/env bash
# Manage the `cicd-demo` IAM user — a demo operator that can create, manage,
# and delete this solution. Permissions = AWS-managed PowerUserAccess (all
# non-IAM services) + the scoped IAM add-on in infra/deploy-permissions.json
# (create/manage the mb-* roles/policies + iam:PassRole to the pipeline services).
#
# Usage: scripts/demo-user.sh [create|delete|status]
#
# NOTE: `create` prints a console password + access keys ONCE. They are shown in
# the terminal only, never written to disk or committed. Store them securely and
# rotate after the demo. This is a demo/sandbox convenience — an IAM user is a
# long-lived credential, unlike the project's default SSO access.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/.env" ] && { set -a; . "$ROOT/.env"; set +a; }
AWS="${AWS_BIN:-$HOME/bin/aws}"; command -v aws >/dev/null 2>&1 && AWS=aws
# MANUAL FALLBACK — no .env? Uncomment and edit these instead (they take
# precedence over anything .env loaded above):
# AWS_PROFILE=sandbox01
# AWS_REGION=us-east-1
: "${AWS_PROFILE:?set AWS_PROFILE in .env (or uncomment the manual fallback above)}"
PROFILE="$AWS_PROFILE"; REGION="${AWS_REGION:-us-east-1}"
Q="--profile $PROFILE --region $REGION"

USER=cicd-demo
INLINE_POLICY=cicd-demo-deploy-iam
POWERUSER=arn:aws:iam::aws:policy/PowerUserAccess
PERMS_FILE="$ROOT/infra/deploy-permissions.json"

acct=$($AWS sts get-caller-identity $Q --query Account --output text)

case "${1:-create}" in
  create)
    # 1. user (idempotent)
    if $AWS iam get-user --user-name "$USER" $Q >/dev/null 2>&1; then
      echo "user $USER already exists — updating policies/login"
    else
      $AWS iam create-user --user-name "$USER" \
        --tags Key=purpose,Value=cicd-demo Key=managed-by,Value=demo-user.sh $Q >/dev/null
      echo "created user $USER"
    fi

    # 2. permissions: PowerUserAccess (managed) + scoped IAM add-on (inline)
    $AWS iam attach-user-policy --user-name "$USER" --policy-arn "$POWERUSER" $Q
    $AWS iam put-user-policy --user-name "$USER" --policy-name "$INLINE_POLICY" \
      --policy-document "file://$PERMS_FILE" $Q
    echo "attached: PowerUserAccess + inline $INLINE_POLICY (scoped IAM for mb-*)"

    # 3. console login profile (force reset on first sign-in)
    PW=$(python3 -c "import secrets,string; a=string.ascii_letters+string.digits+'!@#%^_=+'; print(''.join(secrets.choice(a) for _ in range(20)))")
    if $AWS iam get-login-profile --user-name "$USER" $Q >/dev/null 2>&1; then
      $AWS iam update-login-profile --user-name "$USER" --password "$PW" --password-reset-required $Q
    else
      $AWS iam create-login-profile --user-name "$USER" --password "$PW" --password-reset-required $Q >/dev/null
    fi

    # 4. access keys for CLI/Terraform (only if none exist — max 2/user)
    existing=$($AWS iam list-access-keys --user-name "$USER" $Q --query 'length(AccessKeyMetadata)' --output text)
    if [ "$existing" = "0" ]; then
      KEY=$($AWS iam create-access-key --user-name "$USER" $Q --query 'AccessKey.{id:AccessKeyId,secret:SecretAccessKey}' --output json)
      AKID=$(echo "$KEY" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
      SECRET=$(echo "$KEY" | python3 -c "import sys,json;print(json.load(sys.stdin)['secret'])")
    else
      AKID="(existing key present — run 'delete' then 'create' to rotate)"; SECRET="(not shown)"
    fi

    cat <<EOF

==== SAVE NOW — shown once, not stored on disk ====
Console sign-in  : https://${acct}.signin.aws.amazon.com/console
  username       : ${USER}
  password       : ${PW}      (reset required on first sign-in)
Access key ID    : ${AKID}
Secret access key: ${SECRET}
===================================================
Recommended: add MFA (IAM > Users > ${USER} > Security credentials).
For CLI/Terraform: 'aws configure --profile ${USER}' with the keys above,
then AWS_PROFILE=${USER} for scripts/rollout.sh, or run in AWS CloudShell.
EOF
    ;;

  delete)
    $AWS iam delete-login-profile --user-name "$USER" $Q 2>/dev/null || true
    for k in $($AWS iam list-access-keys --user-name "$USER" $Q --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null); do
      $AWS iam delete-access-key --user-name "$USER" --access-key-id "$k" $Q || true
    done
    $AWS iam delete-user-policy --user-name "$USER" --policy-name "$INLINE_POLICY" $Q 2>/dev/null || true
    $AWS iam detach-user-policy --user-name "$USER" --policy-arn "$POWERUSER" $Q 2>/dev/null || true
    $AWS iam delete-user --user-name "$USER" $Q 2>/dev/null || true
    echo "deleted user $USER (login profile, access keys, policies, user)"
    ;;

  status)
    $AWS iam get-user --user-name "$USER" $Q --query 'User.{user:UserName,created:CreateDate,arn:Arn}' --output json 2>&1 || { echo "$USER not found"; exit 0; }
    echo "attached managed policies:"; $AWS iam list-attached-user-policies --user-name "$USER" $Q --query 'AttachedPolicies[].PolicyName' --output json
    echo "inline policies:"; $AWS iam list-user-policies --user-name "$USER" $Q --query 'PolicyNames' --output json
    echo "access keys:"; $AWS iam list-access-keys --user-name "$USER" $Q --query 'AccessKeyMetadata[].{id:AccessKeyId,status:Status}' --output json
    ;;

  *) echo "usage: $0 [create|delete|status]"; exit 2 ;;
esac
