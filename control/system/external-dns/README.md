# external-dns (Cloudflare) — STUB, not yet wired up

Plan: external-dns watches `Service.type=LoadBalancer` and `Ingress` resources in each cluster and writes DNS records to Cloudflare. One external-dns deployment per cluster, scoped to a per-cluster subdomain so records don't collide.

## Prerequisites (TODO before deploying)

1. **Cloudflare API token** with `Zone:Read` + `DNS:Edit` for the target zone(s). Create at https://dash.cloudflare.com/profile/api-tokens — use the "Edit zone DNS" template, restrict to specific zone.
2. **Domain decision** — which apex zone? (e.g. `example.com`)
3. **Per-cluster subdomain convention** — proposed:
   - `*.oasis-control.example.com` → control cluster (admin UIs only; ArgoCD, etc.)
   - `*.oasis.example.com` → oasis workload cluster
4. **Secret delivery** — Cloudflare token must reach each cluster. Two options:
   - **Sealed Secrets / SOPS** — commit encrypted secret to repo, decrypt at apply time. Standard GitOps pattern.
   - **External Secrets Operator + AWS SSM/Secrets Manager** — token lives in AWS, cluster pulls via IRSA. Heavier setup but better key rotation.

## Deployment shape (when wiring up)

Add an Argo Application per cluster (control, oasis, future):

```yaml
# control/argocd/applications/external-dns-<cluster>.yml
spec:
  source:
    repoURL: https://kubernetes-sigs.github.io/external-dns/
    chart: external-dns
    targetRevision: 1.16.0  # pin
    helm:
      releaseName: external-dns
      valuesObject:
        provider: cloudflare
        env:
          - name: CF_API_TOKEN
            valueFrom:
              secretKeyRef:
                name: cloudflare-api-token
                key: token
        domainFilters: ["oasis.example.com"]   # per-cluster subdomain
        policy: sync                            # full reconcile (delete stale records)
        registry: txt
        txtOwnerId: oasis                       # per-cluster, prevents cross-cluster overwrites
  destination:
    server: <cluster-API-server-URL>            # different for each cluster
    namespace: external-dns
```

Note: targeting downstream clusters from the control-cluster's ArgoCD requires registering the downstream cluster with ArgoCD (`argocd cluster add`), or running an ArgoCD instance per workload cluster. Decide pattern before wiring up.

## Pairs with cert-manager

Once external-dns is in, cert-manager DNS-01 (using the same Cloudflare token in a separate secret) can issue wildcard certs for `*.oasis.example.com`. Add cert-manager ClusterIssuer manifests under `control/system/cert-manager/issuers/` when ready.
