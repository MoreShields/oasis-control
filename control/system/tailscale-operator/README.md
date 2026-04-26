# Tailscale operator

Exposes individual Kubernetes Services to the tailnet by annotation. We use it to expose **exactly one Service per cluster**: the Cilium Gateway's auto-created Service. Every app behind the Gateway is reached via a single tailnet hostname; no per-Service operator interaction.

The helm install lives at `control/argocd/applications/tailscale-operator.yml`.

## Bootstrap-time secret (out-of-band)

The operator authenticates to your tailnet via OAuth. The chart reads OAuth creds from a Secret named `operator-oauth` in the `tailscale` namespace; that Secret is **not** in this repo and must be created before the helm release becomes Healthy.

1. In the [Tailscale admin console](https://login.tailscale.com/admin/settings/oauth), create an OAuth client with **Devices: write** and **Devices: core: write** scopes. Tag it `tag:k8s` (the same tag the operator gives to spawned proxy devices).
2. On the control cluster, create the Secret:
   ```bash
   KUBECONFIG=~/.kube/oasis-control.kubeconfig \
     kubectl create namespace tailscale --dry-run=client -o yaml | kubectl apply -f -
   KUBECONFIG=~/.kube/oasis-control.kubeconfig \
     kubectl create secret generic operator-oauth -n tailscale \
       --from-literal=client_id=$TS_OAUTH_CLIENT_ID \
       --from-literal=client_secret=$TS_OAUTH_CLIENT_SECRET
   ```

Argo will retry the helm install until the Secret exists, then settle Healthy.

## Future: bring the Secret into GitOps

Two options when ready: Sealed Secrets (encrypt the Secret in repo, controller decrypts in-cluster) or External Secrets Operator pulling from AWS Secrets Manager. Either way the operator-oauth Secret becomes Argo-managed and re-bootstraps don't require this manual step.
