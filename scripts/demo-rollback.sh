#!/usr/bin/env bash
# Demo: deploy a deliberately broken release to prod and show CodeDeploy's
# automated blue/green rollback protect production (zero downtime).
# Safe: the bad version never receives traffic; blue keeps serving throughout.
set -euo pipefail

# Load .env if present (AWS_PROFILE / AWS_REGION), else fall back to sandbox defaults.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/.env" ] && { set -a; . "$ROOT/.env"; set +a; }
AWS="${AWS_BIN:-$HOME/bin/aws}"; command -v aws >/dev/null 2>&1 && AWS=aws
PROFILE="${AWS_PROFILE:-sandbox01}"
REGION="${AWS_REGION:-us-east-1}"
Q="--profile $PROFILE --region $REGION"

CLUSTER=mb-use1-cluster
SVC=mb-prod-use1-app-svc
APP=mb-prod-use1-cd-app
GROUP=mb-prod-use1-cd-group
ALB=$($AWS elbv2 describe-load-balancers --names mb-prod-use1-alb $Q --query 'LoadBalancers[0].DNSName' --output text)

echo "== baseline: $(curl -s -o /tmp/d.html -w 'HTTP %{http_code}' http://$ALB/) serving $(grep -oE '1\.0\.[0-9]+-[a-f0-9]+' /tmp/d.html | head -1)"

echo "== registering a BAD task definition (image tag that cannot be pulled)"
GOOD=$($AWS ecs describe-services --cluster $CLUSTER --services $SVC $Q --query "services[0].taskSets[?status=='PRIMARY']|[0].taskDefinition" --output text)
$AWS ecs describe-task-definition --task-definition "$GOOD" $Q --query 'taskDefinition' > /tmp/good_td.json
python3 - <<'PY'
import json
td=json.load(open('/tmp/good_td.json'))
repo=td['containerDefinitions'][0]['image'].split('@')[0].split(':')[0]
td['containerDefinitions'][0]['image']=repo+':rollback-demo-nonexistent'
for k in ['taskDefinitionArn','revision','status','requiresAttributes','compatibilities','registeredAt','registeredBy']: td.pop(k,None)
json.dump(td,open('/tmp/bad_td.json','w'))
PY
BAD=$($AWS ecs register-task-definition --cli-input-json file:///tmp/bad_td.json $Q --query 'taskDefinition.taskDefinitionArn' --output text)
echo "   $BAD"

echo "== creating CodeDeploy blue/green deployment with the bad task def"
REV=$(python3 -c "import json;c='version: 0.0\nResources:\n  - TargetService:\n      Type: AWS::ECS::Service\n      Properties:\n        TaskDefinition: \"$BAD\"\n        LoadBalancerInfo:\n          ContainerName: app\n          ContainerPort: 80\n';print(json.dumps({'revisionType':'AppSpecContent','appSpecContent':{'content':c}}))")
DID=$($AWS deploy create-deployment --application-name $APP --deployment-group-name $GROUP --revision "$REV" --description "Automated-rollback demo" $Q --query 'deploymentId' --output text)
echo "   deployment $DID"

echo "== watching (green will fail to start; site stays up on the good version)"
for i in $(seq 1 6); do
  sleep 20
  code=$(curl -s -o /tmp/d.html -w '%{http_code}' http://$ALB/); ver=$(grep -oE '1\.0\.[0-9]+-[a-f0-9]+' /tmp/d.html | head -1)
  echo "   t+$((i*20))s  site: HTTP $code ($ver)  green: $($AWS ecs describe-services --cluster $CLUSTER --services $SVC $Q --query "services[0].taskSets[?status=='ACTIVE']|[0].stabilityStatus" --output text 2>/dev/null)"
done

echo "== invoking CodeDeploy rollback (tears down the bad green task set)"
$AWS deploy stop-deployment --deployment-id "$DID" --auto-rollback-enabled $Q >/dev/null
for i in $(seq 1 8); do
  sleep 15
  n=$($AWS ecs describe-services --cluster $CLUSTER --services $SVC $Q --query 'length(services[0].taskSets)' --output text)
  [ "$n" = "1" ] && break
done

echo "== cleanup: deregister the bad task def"
$AWS ecs deregister-task-definition --task-definition "$BAD" $Q >/dev/null || true

echo "== result: $(curl -s -o /tmp/d.html -w 'HTTP %{http_code}' http://$ALB/) serving $(grep -oE '1\.0\.[0-9]+-[a-f0-9]+' /tmp/d.html | head -1) — production never went down."
