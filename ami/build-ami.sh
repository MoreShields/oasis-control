#!/bin/bash
set -euo pipefail

# Build the mkosi image and import it as an AWS AMI.
# Usage: ./build-ami.sh [--name <ami-name>]
#
# Prerequisites:
#   - mkosi installed (https://github.com/systemd/mkosi)
#   - AWS CLI configured (profile: nate-bnsf, region: us-west-1)
#   - S3 bucket: k8s-mkosi-images
#   - IAM role: vmimport (required by ec2 import-snapshot)

REGION="us-west-1"
PROFILE="nate-bnsf"
S3_BUCKET="k8s-mkosi-images"
S3_KEY="k8s-node.raw"
IMAGE_FILE="k8s-node.raw"
AMI_NAME="${1:-k8s-node-rke2-$(date +%Y%m%d-%H%M%S)}"
VOLUME_SIZE=50

cd "$(dirname "$0")"

# --- Preflight checks ---
for cmd in mkosi aws; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is not installed" >&2
        exit 1
    fi
done

# --- Step 1: Build the image ---
echo "==> Building mkosi image..."
mkosi --force build
echo "    Image built: ${IMAGE_FILE} ($(du -h "${IMAGE_FILE}" | cut -f1))"

# --- Step 2: Upload to S3 ---
echo "==> Uploading to s3://${S3_BUCKET}/${S3_KEY}..."
aws s3 cp "${IMAGE_FILE}" "s3://${S3_BUCKET}/${S3_KEY}" \
    --region "${REGION}" --profile "${PROFILE}"

# --- Step 3: Import as EBS snapshot ---
echo "==> Importing snapshot..."
IMPORT_TASK=$(aws ec2 import-snapshot \
    --region "${REGION}" --profile "${PROFILE}" \
    --disk-container "Format=raw,UserBucket={S3Bucket=${S3_BUCKET},S3Key=${S3_KEY}}" \
    --query 'ImportTaskId' --output text)
echo "    Import task: ${IMPORT_TASK}"

# --- Step 4: Poll until complete ---
echo "==> Waiting for snapshot import (this takes ~8 minutes)..."
while true; do
    STATUS=$(aws ec2 describe-import-snapshot-tasks \
        --region "${REGION}" --profile "${PROFILE}" \
        --import-task-ids "${IMPORT_TASK}" \
        --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Status' --output text)
    PROGRESS=$(aws ec2 describe-import-snapshot-tasks \
        --region "${REGION}" --profile "${PROFILE}" \
        --import-task-ids "${IMPORT_TASK}" \
        --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Progress' --output text 2>/dev/null || echo "?")

    if [ "${STATUS}" = "completed" ]; then
        SNAPSHOT_ID=$(aws ec2 describe-import-snapshot-tasks \
            --region "${REGION}" --profile "${PROFILE}" \
            --import-task-ids "${IMPORT_TASK}" \
            --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' --output text)
        echo "    Snapshot ready: ${SNAPSHOT_ID}"
        break
    elif [ "${STATUS}" = "deleted" ] || [ "${STATUS}" = "error" ]; then
        echo "ERROR: Snapshot import failed (status: ${STATUS})" >&2
        aws ec2 describe-import-snapshot-tasks \
            --region "${REGION}" --profile "${PROFILE}" \
            --import-task-ids "${IMPORT_TASK}" >&2
        exit 1
    fi

    echo "    Status: ${STATUS} (${PROGRESS}%)"
    sleep 30
done

# --- Step 5: Register AMI ---
echo "==> Registering AMI: ${AMI_NAME}..."
AMI_ID=$(aws ec2 register-image \
    --region "${REGION}" --profile "${PROFILE}" \
    --name "${AMI_NAME}" \
    --architecture x86_64 \
    --root-device-name /dev/xvda \
    --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"SnapshotId\":\"${SNAPSHOT_ID}\",\"VolumeSize\":${VOLUME_SIZE},\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
    --virtualization-type hvm \
    --ena-support \
    --boot-mode uefi \
    --query 'ImageId' --output text)

echo ""
echo "==> AMI registered successfully"
echo "    AMI ID:   ${AMI_ID}"
echo "    Name:     ${AMI_NAME}"
echo "    Region:   ${REGION}"
echo "    Snapshot: ${SNAPSHOT_ID}"
echo ""
echo "Update clusters/oasis-control/cluster.yml with:"
echo "    id: ${AMI_ID}"
