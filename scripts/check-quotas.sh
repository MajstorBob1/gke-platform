#!/usr/bin/env bash
# Shows the Compute Engine quotas that limit this platform. Free-trial projects
# cannot request increases, so size the node pools to fit what you see here.
#   ./scripts/check-quotas.sh <project_id> [region]
set -euo pipefail
PROJECT=${1:?usage: $0 <project_id> [region]}
REGION=${2:-europe-west1}

echo "== Project-wide"
gcloud compute project-info describe --project "$PROJECT" --format=json \
  | jq -r '.quotas[] | select(.metric | test("^(CPUS_ALL_REGIONS|GLOBAL_EXTERNAL_MANAGED_FORWARDING_RULES|STATIC_ADDRESSES|IN_USE_ADDRESSES)$")) | "\(.metric)\t\(.usage)/\(.limit)"' \
  | column -t

echo "== Region $REGION"
gcloud compute regions describe "$REGION" --project "$PROJECT" --format=json \
  | jq -r '.quotas[] | select(.metric | test("^(CPUS|E2_CPUS|DISKS_TOTAL_GB|SSD_TOTAL_GB|IN_USE_ADDRESSES|INSTANCES)$")) | "\(.metric)\t\(.usage)/\(.limit)"' \
  | column -t

cat <<'EOF'

This platform needs (default sizing, e2-highmem-2 = 2 vCPU each):
  CPUS / E2_CPUS : 2 (system) + 2..6 (apps, 1-3 Spot nodes) + 2 during surge upgrades  => up to 10
  DISKS_TOTAL_GB : 50 GB per node + 2x10 GB PVCs                                         => up to ~220
  SSD_TOTAL_GB   : ~0 (everything uses pd-standard)
If CPUS is lower than that, reduce apps_max_nodes in terraform.tfvars.
EOF
