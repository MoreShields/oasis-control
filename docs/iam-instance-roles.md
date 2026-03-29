# IAM Instance Roles

## k8s-converged-node

**Instance Profile:** `k8s-converged-node`
**IAM Role:** `k8s-converged-node`
**Purpose:** Minimal permissions for converged Kubernetes nodes (combined control plane + worker) managed by CAPI/CAPA.

Used by converged Kubernetes nodes running CCM (for Service LoadBalancers and node lifecycle) and EBS CSI driver. Note: node providerID is set via kubelet `--provider-id` flag at boot (injected by `preRKE2Commands` from IMDS), not by the CCM.

### Permissions

| Statement | Actions | Purpose |
|-----------|---------|---------|
| NodeIdentity | `ec2:DescribeInstances`, `ec2:DescribeInstanceTypes`, `ec2:DescribeRegions`, `ec2:DescribeAvailabilityZones`, `ec2:DescribeNetworkInterfaces`, `ec2:DescribeVpcs`, `ec2:DescribeSubnets`, `ec2:DescribeTags`, `ec2:DescribeSecurityGroups` | CCM needs to look up instance metadata for node lifecycle management and removing the `uninitialized` taint |
| LoadBalancer | `elasticloadbalancing:Describe*`, `Create*`, `Delete*`, `Modify*`, `AttachLoadBalancerToSubnets`, `DetachLoadBalancerFromSubnets`, `ApplySecurityGroupsToLoadBalancer`, `AddTags`, `RemoveTags` | CCM creates ELBs for `Service type: LoadBalancer` |
| SecurityGroups | `ec2:CreateSecurityGroup`, `ec2:DeleteSecurityGroup`, `ec2:AuthorizeSecurityGroupIngress`, `ec2:RevokeSecurityGroupIngress`, `ec2:CreateTags` | CCM manages security groups for load balancers |
| EBSVolumes | `ec2:CreateVolume`, `ec2:DeleteVolume`, `ec2:AttachVolume`, `ec2:DetachVolume`, `ec2:DescribeVolumes`, `ec2:DescribeVolumesModifications`, `ec2:ModifyVolume` | EBS CSI driver provisions and manages persistent volumes |
| EBSSnapshots | `ec2:CreateSnapshot`, `ec2:DeleteSnapshot`, `ec2:DescribeSnapshots` | EBS CSI driver manages volume snapshots |
| KMS | `kms:DescribeKey`, `kms:CreateGrant` | EBS CSI driver supports encrypted volumes |

### What's excluded

- **Route management** (`ec2:CreateRoute`, etc.) — not needed with `--configure-cloud-routes=false` (Cilium handles pod networking)
- **Auto Scaling** — CAPI manages node scaling, not cluster-autoscaler
- **ECR** — not using ECR for container images

### Usage

Referenced in `AWSMachineTemplate` resources:

```yaml
spec:
  template:
    spec:
      iamInstanceProfile: k8s-converged-node
```

### Recreating

```bash
# Role with EC2 trust policy
aws iam create-role \
  --role-name k8s-converged-node \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{
      "Effect":"Allow",
      "Principal":{"Service":"ec2.amazonaws.com"},
      "Action":"sts:AssumeRole"
    }]
  }'

# Attach the policy (see policy JSON below)
aws iam put-role-policy \
  --role-name k8s-converged-node \
  --policy-name k8s-converged-node-policy \
  --policy-document file://docs/k8s-converged-node-policy.json

# Instance profile
aws iam create-instance-profile --instance-profile-name k8s-converged-node
aws iam add-role-to-instance-profile \
  --instance-profile-name k8s-converged-node \
  --role-name k8s-converged-node
```
