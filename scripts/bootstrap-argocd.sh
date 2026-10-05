#!/usr/bin/env bash
# Installs ArgoCD once with Helm, then hands control to Git via the root app.
# After this, every change goes through Git; ArgoCD even upgrades itself.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)

if grep -q REPO_URL "$ROOT/gitops/bootstrap/root-app.yaml"; then
  echo "Run scripts/configure-gitops.sh first (placeholders still present)." >&2
  exit 1
fi

echo "==> Context: $(kubectl config current-context)"
kubectl get nodes

ARGOCD_CHART_VERSION=$(yq '.spec.sources[0].targetRevision' "$ROOT/gitops/apps/argocd.yaml")

echo "==> Grafana admin secret (kept out of Git)"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
if ! kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  kubectl -n monitoring create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$(openssl rand -base64 18)"
fi

echo "==> ArgoCD $ARGOCD_CHART_VERSION"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version "$ARGOCD_CHART_VERSION" \
  --values "$ROOT/gitops/values/argocd.yaml" \
  --wait --timeout 10m

echo "==> Root application"
kubectl apply -f "$ROOT/gitops/bootstrap/root-app.yaml"

cat <<EOF

Done. Watch the platform build itself:
  kubectl -n argocd get applications -w

ArgoCD UI:   kubectl -n argocd port-forward svc/argocd-server 8443:443   -> https://localhost:8443
  user admin, password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
Grafana:     kubectl -n monitoring port-forward svc/kps-grafana 3000:80  -> http://localhost:3000
  user admin, password: kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
EOF
