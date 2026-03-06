#!/usr/bin/env bash
# Garage 初期セットアップ: レイアウト適用 → キー作成 → バケット作成 → Secret 配布
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SECRETS_FILE="${REPO_ROOT}/secrets/garage.yaml"

GARAGE_POD="garage-0"
GARAGE_NS="storage"
OBSERVABILITY_NS="observability"

garage_exec() {
  kubectl exec -n "$GARAGE_NS" "$GARAGE_POD" -- /garage "$@"
}

echo "=== Garage Setup ==="

# Step 1: Apply layout (single node)
echo "--- Applying cluster layout ---"
NODE_ID=$(garage_exec status 2>&1 | grep -oE '[a-f0-9]{16}' | head -1)
if [ -z "$NODE_ID" ]; then
  echo "ERROR: Could not determine Garage node ID"
  exit 1
fi
garage_exec layout assign "$NODE_ID" -z dc1 -c 4G 2>/dev/null || true
LAYOUT_VER=$(garage_exec layout show 2>&1 | grep -oE 'apply --version [0-9]+' | grep -oE '[0-9]+' || echo "")
if [ -n "$LAYOUT_VER" ]; then
  garage_exec layout apply --version "$LAYOUT_VER"
  echo "Layout applied (version $LAYOUT_VER)"
else
  echo "Layout already up to date"
fi

# Step 2: Create access key
echo "--- Creating access key ---"
# Check if key already exists by listing keys
EXISTING_KEY=$(garage_exec key list 2>&1 | grep "garage-o11y-key" || true)
if [ -n "$EXISTING_KEY" ]; then
  echo "Key 'garage-o11y-key' already exists, retrieving..."
  ACCESS_KEY=$(echo "$EXISTING_KEY" | grep -oE 'GK[a-zA-Z0-9]+' | head -1)
  KEY_OUTPUT=$(garage_exec key info "$ACCESS_KEY" --show-secret 2>&1)
else
  KEY_OUTPUT=$(garage_exec key create garage-o11y-key 2>&1)
fi

ACCESS_KEY=$(echo "$KEY_OUTPUT" | grep -oE 'GK[a-zA-Z0-9]+' | head -1)
SECRET_KEY=$(echo "$KEY_OUTPUT" | grep "Secret key" | awk '{print $NF}')

if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
  echo "ERROR: Could not extract access key / secret key"
  echo "Key output: $KEY_OUTPUT"
  exit 1
fi

echo "Access Key: $ACCESS_KEY"

# Step 3: Create buckets and grant permissions
echo "--- Creating buckets ---"
for BUCKET in loki-chunks tempo-traces; do
  garage_exec bucket create "$BUCKET" 2>/dev/null || echo "Bucket '$BUCKET' already exists"
  garage_exec bucket allow "$BUCKET" --read --write --key "$ACCESS_KEY"
  echo "Bucket '$BUCKET' ready"
done

# Step 4: Create Kubernetes Secrets
echo "--- Creating Kubernetes Secrets ---"
SECRET_NAME="garage-s3-credentials"

for NS in "$GARAGE_NS" "$OBSERVABILITY_NS"; do
  kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic "$SECRET_NAME" \
    --namespace="$NS" \
    --from-literal=AWS_ACCESS_KEY_ID="$ACCESS_KEY" \
    --from-literal=AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "Secret '$SECRET_NAME' created in namespace '$NS'"
done

# Step 5: Encrypt credentials with sops (for gitops reproducibility)
if command -v sops &>/dev/null; then
  echo "--- Saving credentials with sops ---"
  mkdir -p "$(dirname "$SECRETS_FILE")"
  # Write plaintext directly to target path, encrypt in-place
  cat > "$SECRETS_FILE" <<EOF
aws_access_key_id: ${ACCESS_KEY}
aws_secret_access_key: ${SECRET_KEY}
EOF
  # sops needs to find .sops.yaml from repo root; encrypt in-place
  (cd "$REPO_ROOT" && sops --encrypt --in-place "secrets/garage.yaml")
  echo "Encrypted credentials saved to $SECRETS_FILE"
else
  echo "WARN: sops not found, skipping credential encryption"
fi

echo ""
echo "=== Garage setup complete ==="
echo "S3 endpoint: http://garage.${GARAGE_NS}:3900"
echo "Access Key:  $ACCESS_KEY"
echo "Buckets:     loki-chunks, tempo-traces"
