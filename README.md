# GKE Platform: a production-style workflow for practice

Terraform builds a private GKE cluster on Google Cloud. ArgoCD then deploys everything else from this Git repo: a monitoring stack (Prometheus, Grafana, Alertmanager, Loki, Alloy) and a large microservices app, the **[OpenTelemetry Demo](https://opentelemetry.io/docs/demo/)** (~20 services in 10+ languages, plus Kafka, Postgres, Valkey and feature flags for failure injection).

```
 you ──PR──▶ GitHub ──CI (fmt, validate, tflint, trivy, helm render, kubeconform)──▶ main
                                                                                     │
 terraform/  ──apply──▶  GCP: VPC + Cloud NAT, private GKE, Artifact Registry,        │ watches
                         GCS (Loki), static IP, budget alerts                         ▼
                                                     ┌─────────── GKE cluster ─────────────┐
                                                     │ ArgoCD ──syncs──▶ gitops/apps/*      │
                                                     │  system pool (on-demand):            │
                                                     │    ArgoCD, Prometheus, Grafana,      │
                                                     │    Alertmanager, Loki, Alloy         │
 internet ──▶ Gateway (global LB, static IP) ──────▶ │  apps pool (Spot, 1–3 nodes):        │
                                                     │    OpenTelemetry Demo (otel-demo ns) │
                                                     └──────────────────────────────────────┘
 telemetry:  services ─OTLP─▶ collector ─▶ traces: Jaeger · metrics: Prometheus · logs: Loki
             all pod stdout ─▶ Alloy ─▶ Loki          Grafana reads all three
```

## Repository layout

| Path | What it is |
|---|---|
| `terraform/bootstrap/` | One-time setup with **local** state: APIs, the remote-state bucket, a billing budget |
| `terraform/modules/network` | VPC, subnet with pod/service ranges, Cloud Router + NAT |
| `terraform/modules/gke` | Cluster + node pools + least-privilege node service account |
| `terraform/envs/dev/` | The `dev` environment: wires the modules together, plus registry, Loki bucket, Gateway IP. State lives in GCS |
| `gitops/bootstrap/root-app.yaml` | The **only** manifest applied by hand (app of apps) |
| `gitops/apps/` | One ArgoCD Application per component, all pinned to exact chart versions |
| `gitops/values/` | Helm values for each chart |
| `gitops/manifests/` | Plain YAML: namespaces, Gateway + HTTPRoute, alert rules |
| `scripts/` | `check-quotas`, `configure-gitops`, `bootstrap-argocd`, `render` (CI), `teardown` |
| `.github/workflows/ci.yaml` | Pull-request checks |

## Cost: read this first

The free trial gives you **$300 for 90 days**, with **no quota increases**. The GKE management fee is free for one zonal cluster, but everything else is paid from your credits. Roughly, while it's running:

| Item | ≈ per hour |
|---|---|
| 1× e2-highmem-2 on-demand (system pool) | $0.09 |
| 1–3× e2-highmem-2 **Spot** (apps pool) | $0.03 each |
| Global load balancer forwarding rule | $0.025 |
| Cloud NAT, disks, GCS, egress | a few cents |
| **Total** | **≈ $0.15–0.25/h, or about $4–6/day if left running** |

These are estimates; check *Billing > Reports* for real numbers. **Work in sessions:** create the environment, practise, then run `scripts/teardown.sh`. Rebuilding takes ~25 minutes, and rebuilding often is itself good practice. The budget from `bootstrap` emails you at 25/50/90/100% of `monthly_budget`, measured **before** credits, so it actually fires during the trial.

---

## Phase 0: one-time setup on your laptop

All the CLIs come from `~/kubernetes/setup/install-cli-tools.sh` (terraform, tflint, gcloud, gke-gcloud-auth-plugin, kubectl, helm, argocd, yq, kubeconform, trivy).

```bash
gcloud auth login                         # your Google account, for gcloud commands
gcloud auth application-default login     # credentials Terraform uses (ADC)

# A dedicated project keeps this isolated and easy to delete.
export PROJECT_ID=gke-platform-$RANDOM
gcloud projects create $PROJECT_ID
gcloud billing accounts list               # copy the ACCOUNT_ID
gcloud billing projects link $PROJECT_ID --billing-account=<ACCOUNT_ID>
gcloud config set project $PROJECT_ID
gcloud auth application-default set-quota-project $PROJECT_ID
```

## Phase 1: bootstrap (APIs, state bucket, budget)

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars    # fill in project_id, billing_account_id, currency
terraform init
terraform plan          # READ the plan. Always.
terraform apply
cd ../..
./scripts/check-quotas.sh $PROJECT_ID europe-west1
```
If `CPUS` or `E2_CPUS` is below ~10, lower `apps_max_nodes` in the next step.

> Bootstrap state stays local (`terraform/bootstrap/terraform.tfstate`, ignored by Git). It's tiny and rarely changes. Back it up, or migrate it into the bucket it created (a good exercise: add a `backend "gcs"` block and run `terraform init -migrate-state`).

## Phase 2: infrastructure

```bash
cd terraform/envs/dev
cp terraform.tfvars.example terraform.tfvars    # project_id + admin_cidrs = ["$(curl -s https://ifconfig.me)/32"]
terraform init -backend-config="bucket=${PROJECT_ID}-tfstate"
terraform plan -out=tfplan
terraform apply tfplan                          # ~10–15 min, mostly the cluster
$(terraform output -raw get_credentials)        # writes the kubeconfig context
cd ../../..
kubectl get nodes -L cloud.google.com/gke-nodepool,cloud.google.com/gke-spot
```
Expect 2 nodes: one in `system`, one in `apps` (Spot).

**If kubectl times out later**, your public IP has probably changed: the API only accepts `admin_cidrs`. Update `terraform.tfvars` and `terraform apply` again.

## Phase 3: put this repo on GitHub

ArgoCD pulls from Git, so the repo must be reachable. A **public** repo is simplest, and safe, because nothing secret is committed: passwords are created in-cluster, and `.gitignore` blocks state and tfvars files.

```bash
# create an empty repo named gke-platform on github.com first, then:
./scripts/configure-gitops.sh https://github.com/<you>/gke-platform.git
git add -A && git commit -m "Initial platform"
git remote add origin git@github.com:<you>/gke-platform.git
git push -u origin main
```
`configure-gitops.sh` fills in the placeholders (`REPO_URL`, `LOKI_BUCKET`, `GATEWAY_IP_NAME`) from your Terraform outputs.

## Phase 4: hand the cluster to GitOps

```bash
./scripts/bootstrap-argocd.sh
kubectl -n argocd get applications -w
```
Within ~10 minutes, every application should be `Synced` / `Healthy`. Order matters, and sync waves handle it: ArgoCD → Prometheus (CRDs) → Loki → Alloy → Gateway + alert rules → the demo.

## Phase 5: look around

| What | How |
|---|---|
| **The shop** | `http://$(terraform -chdir=terraform/envs/dev output -raw gateway_ip)/`. The Google load balancer takes **5–10 min** to come up after the Gateway is created |
| Load generator UI | `http://<gateway_ip>/loadgen/` |
| Feature flags UI | `http://<gateway_ip>/feature/` |
| Jaeger (traces) | `http://<gateway_ip>/jaeger/ui/` |
| **Grafana** | `kubectl -n monitoring port-forward svc/kps-grafana 3000:80`. Password: see the end of `bootstrap-argocd.sh` |
| **ArgoCD** | `kubectl -n argocd port-forward svc/argocd-server 8443:443` |
| Prometheus | `kubectl -n monitoring port-forward svc/kps-prometheus 9090` |
| Alertmanager | `kubectl -n monitoring port-forward svc/kps-alertmanager 9093` |

Admin UIs stay private (port-forward only). Only the shop is public, which is deliberate.

In Grafana: *Dashboards* has ~30 built-in dashboards (cluster, nodes, pods, namespaces). *Explore → Loki*: `{namespace="otel-demo"}`. *Explore → Jaeger*: search the `frontend` service.

---

## Phase 6: the daily workflow (how real teams change things)

**Never `kubectl apply` or `helm upgrade` by hand.** ArgoCD's `selfHeal` reverts manual changes within minutes. Every change goes:

```
branch → edit → ./scripts/render.sh locally → PR → CI green → merge → ArgoCD syncs → verify in Grafana
```

Try it now:
1. `git switch -c more-load` and raise the load generator's users: add to `gitops/values/opentelemetry-demo.yaml`
   ```yaml
   components:
     load-generator:
       envOverrides:
         - name: LOCUST_USERS
           value: "20"
   ```
2. `./scripts/render.sh`, then commit, push, open a PR, and watch CI. Merge.
3. Watch ArgoCD pick it up, then watch request rates rise in Grafana.
4. Roll it back **the GitOps way**: `git revert` the merge commit and push.

Infrastructure changes follow the same path, with `terraform plan` in the PR description and `terraform apply` after merge. (Running plan/apply from CI is a later step; see "Next steps".)

## Phase 7: practice scenarios (production incidents you can cause on purpose)

1. **Find a failure from the symptoms.** In the feature-flags UI, turn on `paymentFailure`. Use only Grafana and Jaeger to find **which service** is failing and **why**: error spans in Jaeger, the payment pod's logs in Loki. Then turn on `productCatalogFailure`, `kafkaQueueProblems`, `recommendationCacheFailure` and `emailMemoryLeak` one at a time. For each one, write down which signal (metric, log or trace) revealed it first.
2. **Make the alert real.** `gitops/manifests/alerts/otel-demo-rules.yaml` contains `ShopHighErrorRate`. Check in *Explore → Prometheus* that `traces_span_metrics_calls_total` exists with a `status_code` label (fix the rule via a PR if it doesn't), trigger `paymentFailure`, and watch the alert go Pending → Firing at `:9093`.
3. **Send alerts somewhere.** Configure an Alertmanager receiver (email or Slack webhook) under `alertmanager.config` in the kps values. Keep the webhook URL in a Secret, not in Git (look up `alertmanagerSpec.secrets` / `alertmanagerConfigSecret`).
4. **Survive a Spot preemption.** `kubectl drain` the apps node, or simulate a reclaim: `gcloud compute instances simulate-maintenance-event <node> --zone europe-west1-b`. What broke, for how long, and what would have prevented it (replicas, PDBs, spreading)?
5. **Cluster autoscaling.** Set `LOCUST_USERS` very high via a PR and watch the apps pool grow (`kubectl get nodes -w`). Is CPU or memory the bottleneck? Look at requests vs usage in the Compute Resources dashboards.
6. **Upgrade a component.** Bump a chart's `targetRevision` (for example Loki) in a PR, read the chart's changelog first, merge, and watch the rollout.
7. **Drift.** `kubectl -n otel-demo scale deploy frontend --replicas=0`, then watch ArgoCD self-heal it.
8. **Lock down the network.** Write NetworkPolicies for `otel-demo` (Dataplane V2 enforces them): default-deny, then allow only what each service needs. Use Jaeger's service graph as your map.
9. **Break the platform.** Delete the `grafana-admin` Secret, or put a typo in Loki's values. How does each failure show up in ArgoCD, and how do you recover?
10. **Cost.** Find this cluster in *Billing > Reports*, grouped by SKU. What's the most expensive line item?

## Teardown (end of every session)

```bash
./scripts/teardown.sh
```
It removes the Gateway's load balancer and the PVC disks **through Kubernetes first**, because those are created by controllers and Terraform doesn't know about them. Then it runs `terraform destroy`. The bootstrap layer (state bucket, budget) stays; it costs almost nothing. Next session, start again from Phase 2.

---

## Design decisions (useful in interviews)

| Decision | Why |
|---|---|
| Zonal cluster | Covered by the GKE free tier; production would be **regional** (control plane survives a zone outage) |
| Private nodes + Cloud NAT | Nodes have no public IPs; outbound traffic goes through NAT |
| Control plane restricted to `admin_cidrs` | The API isn't open to the internet |
| Dataplane V2 | eBPF networking with NetworkPolicy built in; no kube-proxy |
| Workload Identity | Loki writes to GCS with **no key file anywhere**; the IAM binding names the Kubernetes ServiceAccount directly |
| Own node service account | The default compute SA has Editor on the whole project |
| Two node pools, Spot for apps | ~70% cheaper; forces you to design for nodes disappearing |
| `pd-standard` disks | The trial's SSD quota is small |
| Self-hosted observability, Google's only for system components | Free, portable skills; no per-sample Cloud Monitoring bill |
| ArgoCD manages itself | Upgrading ArgoCD is a pull request |
| Secrets never in Git | Grafana's password is generated in-cluster |
| Accepted risks | No versioning on the Loki bucket (disposable logs), no VPC flow logs (cost). Both flagged MEDIUM by trivy |

## Next steps

- **Terraform in CI** with Workload Identity Federation (GitHub → GCP without keys): `plan` on PR as a comment, `apply` on merge.
- **TLS:** cert-manager + Let's Encrypt on the Gateway, using a real domain or `<ip>.sslip.io`.
- **Secrets:** External Secrets Operator + Google Secret Manager.
- **A `prod` environment:** `terraform/envs/prod` with a regional cluster, plus an ApplicationSet that deploys the same apps to both.
- **Progressive delivery:** Argo Rollouts canary for the frontend, with Prometheus analysis.
- **Tracing backend:** replace the demo's in-memory Jaeger with Grafana Tempo on GCS.
