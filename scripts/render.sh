#!/usr/bin/env bash
# Renders every Helm-based Application exactly as ArgoCD would (chart + version +
# values file) and validates the output and the plain manifests with kubeconform.
# Used by CI on every pull request; run it locally before you push.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$(mktemp -d)}
mkdir -p "$OUT"
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

for app in "$ROOT"/gitops/apps/*.yaml; do
  chart=$(yq '.spec.sources[0].chart // ""' "$app")
  [ -n "$chart" ] || continue
  repo=$(yq '.spec.sources[0].repoURL' "$app")
  version=$(yq '.spec.sources[0].targetRevision' "$app")
  release=$(yq '.spec.sources[0].helm.releaseName' "$app")
  ns=$(yq '.spec.destination.namespace' "$app")
  values=$(yq '.spec.sources[0].helm.valueFiles[0]' "$app" | sed "s#^\$values/#$ROOT/#")

  echo "==> $chart $version (release $release, ns $ns)"
  helm template "$release" "$chart" --repo "$repo" --version "$version" \
    --namespace "$ns" --values "$values" --kube-version 1.37.0 \
    > "$OUT/$release.yaml"
done

echo "==> kubeconform"
kubeconform -strict -summary -ignore-missing-schemas \
  -schema-location default -schema-location "$CRD_SCHEMAS" \
  "$OUT"/*.yaml "$ROOT"/gitops/manifests "$ROOT"/gitops/apps "$ROOT"/gitops/bootstrap

echo "Rendered manifests: $OUT"
