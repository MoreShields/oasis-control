# AMI Build (mkosi)

Builds a bootable Debian Trixie disk image with RKE2 and Cilium CNI images baked in for fully airgapped Kubernetes node operation. The image is imported to AWS as an AMI.

## What's in the image

- **OS:** Debian Trixie (13), UEFI boot via systemd-boot
- **Runtime:** RKE2 v1.32.4+rke2r1 (server mode)
- **CNI:** Cilium (airgap images at `/var/lib/rancher/rke2/agent/images/`)
- **Airgap artifacts:** `rke2-images-core` + `rke2-images-cilium` — zero network pulls at boot
- **Bootstrap:** systemd path unit watches for cloud-init env file, then configures and starts RKE2

## Prerequisites

- [mkosi](https://github.com/systemd/mkosi) installed on the build host
- AWS CLI configured with profile `nate-bnsf`
- S3 bucket `k8s-mkosi-images` in `us-west-1`
- IAM role `vmimport` (required by `ec2 import-snapshot`)

## Build and push

```bash
cd ami
./build-ami.sh
```

The script builds the image, uploads to S3, imports as an EBS snapshot, and registers an AMI. Takes ~10 minutes (mostly snapshot import). The new AMI ID is printed at the end — update `clusters/control-cluster/cluster-oasis-dev.yml` with it.

## Updating RKE2 version

Edit the `RKE2_VERSION` variable in `mkosi.prepare.chroot`, then rebuild:

```bash
# In mkosi.prepare.chroot, change:
RKE2_VERSION="v1.32.4+rke2r1"
# to the new version, then:
./build-ami.sh
```

## How it works

### Build pipeline (mkosi)

| Phase | Script | Network | What it does |
|-------|--------|---------|--------------|
| prepare | `mkosi.prepare.chroot` | Yes | Downloads RKE2 installer, tarball, and airgap image bundles |
| postinst | `mkosi.postinst.chroot` | No | Configures kernel modules, sysctls, enables systemd units |
| overlay | `mkosi.extra/` | N/A | Copies bootstrap script and systemd units into the image |

### Boot sequence

```
cloud-init writes /run/rke2-bootstrap/env (from IMDS userdata)
    -> rke2-bootstrap.path detects the file
    -> rke2-bootstrap.service runs rke2-bootstrap.sh
        -> writes /etc/rancher/rke2/config.yaml
        -> starts rke2-server.service
        -> RKE2 loads airgap images, starts etcd + k8s + Cilium
```

### CAPI vs standalone usage

**Under CAPI (oasis-dev cluster):** CAPRKE2 generates its own cloud-init userdata that configures and starts RKE2. The baked-in systemd path unit never triggers because CAPRKE2 doesn't write `/run/rke2-bootstrap/env`. The AMI just provides the OS + RKE2 binaries + airgap images.

**Standalone (deploy.sh on jump host):** The `deploy.sh` script (not included here — see `n-jump:~/k8s-mkosi/deploy.sh`) passes cloud-init userdata that writes the env file, triggering the full bootstrap sequence.

## File structure

```
ami/
├── mkosi.conf                  # Image definition (distro, packages, boot config)
├── mkosi.prepare.chroot        # Build-time: download RKE2 + airgap images (has network)
├── mkosi.postinst.chroot       # Build-time: kernel tunables, enable services (no network)
├── mkosi.extra/                # Files overlaid into the image filesystem
│   └── usr/
│       ├── local/bin/
│       │   └── rke2-bootstrap.sh       # Bootstrap logic for standalone use
│       └── lib/systemd/
│           ├── system/
│           │   ├── rke2-bootstrap.path     # Watches for env file
│           │   └── rke2-bootstrap.service  # One-shot bootstrap
│           └── system-preset/
│               └── 10-rke2.preset          # Prevents RKE2 auto-start
└── build-ami.sh                # Build image + import to AWS as AMI
```
