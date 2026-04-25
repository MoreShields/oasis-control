# control/system

Foundational platform addons that ArgoCD manages on the control cluster: cert-manager, external-secrets, monitoring agents, and similar cluster-critical services that other workloads depend on. Sync wave 0 — these come up before anything in `control/capi/` or workload manifests.

## Currently empty — RKE2 ships these out of the box

The control cluster runs RKE2, which bundles several components as helm releases under `kube-system`, managed by RKE2's own helm-controller (not ArgoCD):

| Component | Helm release | Purpose |
|---|---|---|
| `rke2-canal` | kube-system | Default CNI (Calico + Flannel) — replaced at runtime by Cilium per cluster spec |
| `rke2-coredns` | kube-system | Cluster DNS |
| `rke2-ingress-nginx` | kube-system | Ingress controller (NGINX) |
| `rke2-metrics-server` | kube-system | metrics.k8s.io API |
| `rke2-snapshot-controller` | kube-system | Volume snapshot CRDs + controller |
| `rke2-runtimeclasses` | kube-system | RuntimeClass definitions |

Don't add Argo Applications for these — they'd fight RKE2's helm-controller. To customize (e.g. nginx-ingress values), use the [HelmChartConfig CRD](https://docs.rke2.io/helm) in a manifest under `control/capi/clusters/<cluster>/`.

## What lives here

- `cert-manager/` (future, when migrated from raw kubectl)
- `external-secrets/`, `sealed-secrets/`, etc. as needed

cert-manager is currently **bootstrap-installed via raw kubectl** (see `bootstrap/install.sh` Phase 3) and intentionally not Argo-managed — adopting its raw install via a helm Application would churn webhook certs that 5 CAPI controllers depend on. See `docs/known-issues.md` if/when that migration happens.
