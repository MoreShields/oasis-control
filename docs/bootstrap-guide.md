# Bootstrap Guide

Bootstraps a local Kind cluster ("bootstrap cluster"), uses it to provision the oasis-dev control cluster on AWS, then installs CAPI + ArgoCD on the control cluster for managing downstream workload clusters via GitOps.

## Architecture

```
Bootstrap (Kind, local, ephemeral)
  └─ creates → Control Cluster (oasis-dev, AWS, permanent)
                  ├─ ArgoCD (GitOps)
                  ├─ CAPI Operator + providers
                  ├─ manages → future workload clusters
```

## Prerequisites

**Local tools:** `kind`, `kubectl`, `helm`, `aws` (profile `nate-bnsf`, us-west-1), `curl`

**AWS resources (must exist):**
- SSH key pair `nate-bnsf` in us-west-1
- AMI `ami-0ce04faeae10d6e44` (Debian Trixie + RKE2 v1.32.4+rke2r1 airgap)
- IAM instance profile `k8s-converged-node` (see [iam-instance-roles.md](iam-instance-roles.md))

**Credentials:** `.env` in project root with `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`

## Quick Start

```bash
./bootstrap/install.sh
```

This runs the full flow: Kind cluster → control cluster → CAPI + ArgoCD. Takes ~15 minutes.

## What the Script Does

**Phase 1: Bootstrap Kind cluster**
- Creates `oasis-bootstrap` Kind cluster
- Installs cert-manager, CAPI Operator, providers
- Creates AWS credentials secret

**Phase 2: Create control cluster on AWS**
- Applies cluster manifest (VPC, NLB, 3 converged nodes)
- Waits for all 3 machines to be Running
- Extracts kubeconfig to `~/.kube/oasis-dev.kubeconfig`

**Phase 3: Install CAPI on control cluster**
- Installs cert-manager, CAPI Operator, providers on oasis-dev
- The control cluster can now manage downstream workload clusters

**Phase 4: Install ArgoCD on control cluster**
- Helm installs ArgoCD
- Applies app-of-apps pointing at this git repo
- ArgoCD manages CAPI providers via GitOps going forward

**Phase 5: Cleanup**
- Prompts to delete the bootstrap Kind cluster

## Post-Bootstrap

```bash
# Access the control cluster
export KUBECONFIG=~/.kube/oasis-dev.kubeconfig
kubectl get nodes

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# Check ArgoCD applications
kubectl get applications -n argocd
```

## Adding a Downstream Cluster

1. Create `clusters/<name>/cluster.yml` with the CAPI manifest
2. Create an ArgoCD Application in `control/argocd/applications/`
3. Commit and push — ArgoCD syncs automatically

## Teardown

```bash
# Delete a downstream workload cluster
kubectl delete cluster <name> -n <namespace>

# Delete the control cluster (from bootstrap Kind, if still running)
kubectl --context kind-oasis-bootstrap delete cluster oasis-dev -n oasis-dev
```

## Architecture Notes

**providerID:** Set via kubelet `--provider-id` at boot using IMDS, bypassing the CCM for node identity.

**Node join:** Uses `registrationMethod: internal-first` so joining nodes connect via private IP on port 9345, avoiding NLB hairpin issues.

**CCM:** Deployed for `uninitialized` taint removal, Service LoadBalancer support, and node lifecycle.

**Air-gap:** RKE2 and images baked into AMI. Nodes only need internet for cloud-init and registration.
