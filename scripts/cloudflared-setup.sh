#!/usr/bin/env bash
set -euo pipefail

TUNNEL_NAME="microservice-infra"
NAMESPACE="cloudflare"
SECRET_NAME="tunnel-credentials"
DOMAINS=("grafana.thirdlf03.com" "hubble.thirdlf03.com" "argocd.thirdlf03.com")

echo "=== Cloudflare Tunnel Setup ==="
echo ""

# Step 1: Login
echo "--- Step 1: Logging in to Cloudflare ---"
if [ ! -f "$HOME/.cloudflared/cert.pem" ]; then
  cloudflared tunnel login
else
  echo "Already logged in (cert.pem exists). Skipping."
fi

# Step 2: Create tunnel
echo ""
echo "--- Step 2: Creating tunnel '${TUNNEL_NAME}' ---"
if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
  echo "Tunnel '${TUNNEL_NAME}' already exists. Skipping creation."
else
  cloudflared tunnel create "$TUNNEL_NAME"
fi

# Step 3: Get tunnel ID and credentials
TUNNEL_ID=$(cloudflared tunnel list -o json | jq -r ".[] | select(.name==\"${TUNNEL_NAME}\") | .id")
CREDS_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"

if [ ! -f "$CREDS_FILE" ]; then
  echo "ERROR: Credentials file not found at ${CREDS_FILE}"
  echo "Try deleting and re-creating the tunnel."
  exit 1
fi

echo "Tunnel ID: ${TUNNEL_ID}"

# Step 4: Inject credentials as Kubernetes Secret
echo ""
echo "--- Step 3: Creating Kubernetes Secret ---"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic "$SECRET_NAME" \
  --namespace="$NAMESPACE" \
  --from-file=credentials.json="$CREDS_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret '${SECRET_NAME}' created in namespace '${NAMESPACE}'."

# Step 5: Create DNS CNAME records
echo ""
echo "--- Step 4: Creating DNS records ---"
for domain in "${DOMAINS[@]}"; do
  echo "  Creating CNAME for ${domain} → ${TUNNEL_ID}.cfargotunnel.com"
  cloudflared tunnel route dns "$TUNNEL_NAME" "$domain" || true
done

# Step 6: Print Cloudflare Access instructions
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next: Configure Cloudflare Access (Zero Trust) in the dashboard:"
echo ""
echo "  1. Go to https://one.dash.cloudflare.com/"
echo "  2. Zero Trust → Integrations → Identity providers"
echo "     → Add new → GitHub"
echo "     → Set App ID (Client ID) / Client Secret from GitHub OAuth App"
echo ""
echo "  3. Zero Trust → Access → Applications"
echo "     → Create an application for each subdomain:"
for domain in "${DOMAINS[@]}"; do
  echo "       - ${domain}"
done
echo ""
echo "  4. Add a Policy:"
echo "     → Action: Allow"
echo "     → Include: GitHub Organization = <your-org>"
echo ""
echo "Now run 'gen-manifests' and apply the cloudflared manifests."
