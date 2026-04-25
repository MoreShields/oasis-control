#!/bin/bash
set -euo pipefail

# Creates the CAPA AWS credentials secret from .env
# Usage: ./scripts/create-aws-secret.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../../.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: .env file not found at $ENV_FILE"
  echo "Expected format:"
  echo "  AWS_ACCESS_KEY_ID=AKIA..."
  echo "  AWS_SECRET_ACCESS_KEY=..."
  exit 1
fi

source "$ENV_FILE"

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "Error: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set in .env"
  exit 1
fi

# CAPA expects credentials in AWS INI format, base64-encoded
CREDS_B64=$(printf "[default]\naws_access_key_id = %s\naws_secret_access_key = %s\n" \
  "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" | base64)

kubectl create secret generic bnsf-aws-creds \
  --from-literal=AWS_B64ENCODED_CREDENTIALS="$CREDS_B64" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret bnsf-aws-creds created/updated in default namespace"
