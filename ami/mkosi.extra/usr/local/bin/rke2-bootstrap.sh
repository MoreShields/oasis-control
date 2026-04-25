#!/bin/bash
set -euo pipefail

# RKE2_ROLE, RKE2_TOKEN, RKE2_INIT_IP, RKE2_NODE_IP come from EnvironmentFile

mkdir -p /etc/rancher/rke2
cat > /etc/rancher/rke2/config.yaml <<CFG
token: ${RKE2_TOKEN}
cni: cilium
node-ip: ${RKE2_NODE_IP}
tls-san:
  - ${RKE2_INIT_IP}
  - ${RKE2_NODE_IP}
CFG

if [ "$RKE2_ROLE" = "join" ]; then
    echo "server: https://${RKE2_INIT_IP}:9345" >> /etc/rancher/rke2/config.yaml
    echo "Waiting for init node at ${RKE2_INIT_IP}:9345..."
    until curl -sk --max-time 2 "https://${RKE2_INIT_IP}:9345/ping" 2>/dev/null; do
        sleep 10
    done
fi

systemctl enable --now rke2-server.service

ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
mkdir -p /root/.kube
ln -sf /etc/rancher/rke2/rke2.yaml /root/.kube/config
