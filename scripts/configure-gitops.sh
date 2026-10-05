#!/usr/bin/env bash
# Fills the placeholders in gitops/ with your repo URL and Terraform outputs.
# Run once after `terraform apply`, then commit and push.
#   ./scripts/configure-gitops.sh https://github.com/<you>/gke-platform.git
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO_URL=${1:?usage: $0 <https git URL of this repo>}
TF="terraform -chdir=$ROOT/terraform/envs/dev"

LOKI_BUCKET=$($TF output -raw loki_bucket)
GATEWAY_IP_NAME=$($TF output -raw gateway_ip_name)

echo "REPO_URL        = $REPO_URL"
echo "LOKI_BUCKET     = $LOKI_BUCKET"
echo "GATEWAY_IP_NAME = $GATEWAY_IP_NAME"

grep -rl --include='*.yaml' -e REPO_URL -e LOKI_BUCKET -e GATEWAY_IP_NAME "$ROOT/gitops" | while read -r f; do
  sed -i \
    -e "s#REPO_URL#$REPO_URL#g" \
    -e "s#LOKI_BUCKET#$LOKI_BUCKET#g" \
    -e "s#GATEWAY_IP_NAME#$GATEWAY_IP_NAME#g" \
    "$f"
  echo "updated ${f#"$ROOT"/}"
done

echo
echo "Now commit and push:  git add gitops && git commit -m 'Configure GitOps for dev' && git push"
