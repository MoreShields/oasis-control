# Bootstrap Guide

Complete guide to bootstrapping the oasis-control management cluster and creating workload clusters on AWS.

## Prerequisites

**Local tools:**
- `kind` — local Kubernetes cluster
- `kubectl` — Kubernetes CLI
- `helm` — Kubernetes package manager
- `aws` CLI — configured with profile `nate-bnsf` (us-west-1)
- `curl`

**AWS resources (must exist before bootstrap):**
- SSH key pair `nate-bnsf` in us-west-1
- AMI `ami-0ce04faeae10d6e44` in us-west-1 (Debian Trixie + RKE2 v1.32.4+rke2r1 airgap, built via mkosi on n-jump:/home/admin/k8s-mkosi)
- IAM instance profile `k8s-converged-node` (see [docs/iam-instance-roles.md](iam-instance-roles.md) for creation steps)

**Credentials:**
- `.env` file in project root with `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`

## Step 1: Create the Kind management cluster

```bash
kind create cluster --name oasis-control
kubectl cluster-info --context kind-oasis-control
```

## Step 2: Install the CAPI Operator

```bash
helm repo add capi-operator https://kubernetes-sigs.github.io/cluster-api-operator
helm repo update

helm install capi-operator capi-operator/cluster-api-operator \
  --create-namespace -n capi-operator-system \
  --set infrastructure=aws \
  --wait
```

## Step 3: Create the AWS credentials secret

```bash
./scripts/create-aws-secret.sh
```

This reads `.env` and creates the `bnsf-aws-creds` secret in the `default` namespace, formatted for CAPA.

## Step 4: Apply CAPI providers

The providers configure CAPA (AWS infrastructure) and CAPRKE2 (RKE2 bootstrap + control plane).

```bash
kubectl apply -f clusters/control-cluster/infrastructureprovider-aws.yml
kubectl apply -f clusters/control-cluster/bootstrapprovider-rke2.yml
kubectl apply -f clusters/control-cluster/controlplaneprovider-rke2.yml
```

Wait for all providers to be ready:

```bash
kubectl get providers.operator.cluster.x-k8s.io -A
# All should show Ready=True
```

## Step 5: Create the workload cluster

```bash
kubectl apply -f clusters/control-cluster/cluster-oasis-dev.yml
kubectl apply -f clusters/control-cluster/aws-ccm-addon.yml
```

This creates:
- VPC with public/private subnets in us-west-1
- NLB for the API server (ports 6443 + 9345)
- 3 converged control plane + worker nodes (t3a.medium)
- AWS CCM deployed via ClusterResourceSet

## Step 6: Monitor progress

```bash
# Watch infrastructure provisioning (~3 min for VPC + NLB)
kubectl get awscluster -n oasis-dev -w

# Watch machine creation and node join (~5 min per node)
kubectl get machines -n oasis-dev -w

# Once machines are Running, get the workload kubeconfig
kubectl get secret oasis-dev-kubeconfig -n oasis-dev \
  -o jsonpath='{.data.value}' | base64 -d > ~/.kube/oasis-dev.kubeconfig

# Verify all 3 nodes
kubectl --kubeconfig ~/.kube/oasis-dev.kubeconfig get nodes
```

Expected result: 3 Ready nodes with `control-plane,etcd,master` roles and `aws:///` providerIDs.

## Teardown

```bash
# Delete the workload cluster (terminates all AWS resources)
kubectl delete cluster oasis-dev -n oasis-dev

# This cascades to AWSCluster, machines, VPC, NLB, etc.
# Takes ~5 min for AWS resource cleanup (NAT gateway deletion is slow)
```

## Architecture Notes

**providerID:** Set via kubelet `--provider-id` flag at boot using IMDS (in `preRKE2Commands`), bypassing the CCM for node identity. This avoids a circular dependency where CAPI waits for providerID → CCM sets providerID → CCM needs a running cluster → cluster needs CAPI to mark machines Ready.

**Node join:** Uses `registrationMethod: internal-first` so joining nodes connect directly to an existing node's private IP on port 9345, avoiding NLB hairpin issues with internet-facing load balancers.

**CCM:** Still deployed for removing the `node.cloudprovider.kubernetes.io/uninitialized` taint (required because `cloudProviderName: external` is set), Service type LoadBalancer support, and node lifecycle management.

**Air-gap:** RKE2 and container images are baked into the AMI. Nodes don't need internet access for Kubernetes components — only for initial cloud-init and NLB-based registration.
