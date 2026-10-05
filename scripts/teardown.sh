#!/usr/bin/env bash
# Destroys everything that costs money, in the right order.
#
# Why not just `terraform destroy`? Kubernetes creates cloud resources that
# Terraform doesn't know about:
#   - the Gateway   -> load balancer, forwarding rule, backend services, NEGs
#   - each PVC      -> a Persistent Disk
# Deleting the cluster first ORPHANS them: they keep billing and can block the
# VPC deletion. So we delete them through Kubernetes first, then destroy.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)

echo "==> Context: $(kubectl config current-context)"
read -r -p "Destroy the platform in this context? Type 'destroy': " ok
[ "$ok" = destroy ] || exit 1

echo "==> Stop GitOps from recreating things"
kubectl -n argocd delete application root --wait=true --timeout=10m || true
kubectl -n argocd delete applications --all --wait=true --timeout=10m || true

echo "==> Delete the Gateway (cloud load balancer)"
kubectl delete gateway --all -A --wait=true --timeout=10m || true

echo "==> Delete PVCs (persistent disks)"
kubectl delete pvc --all -A --wait=true --timeout=10m || true

echo "==> Give GCP controllers time to remove the LB and disks"
sleep 90

echo "==> terraform destroy (env layer only; bootstrap + state bucket are kept)"
terraform -chdir="$ROOT/terraform/envs/dev" destroy

cat <<'EOF'

Check nothing is left billing:
  gcloud compute forwarding-rules list
  gcloud compute disks list
  gcloud compute network-endpoint-groups list
EOF
