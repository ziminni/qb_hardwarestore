#!/usr/bin/env bash
# Starts a free Cloudflare Quick Tunnel exposing the local POS backend (port 8000)
# over HTTPS so a remote CPMS machine can connect to it without port forwarding.
#
# Usage:
#   ./scripts/start-tunnel.sh [PORT]

set -euo pipefail

PORT="${1:-8000}"
TARGET_URL="http://localhost:${PORT}"

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "Error: 'cloudflared' is not installed or not in PATH." >&2
  echo "Install it from: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/" >&2
  exit 1
fi

echo "Starting Cloudflare Quick Tunnel for POS backend at ${TARGET_URL} ..."
echo "Copy the generated https://<name>.trycloudflare.com URL into CPMS:"
echo "  POS_API_BASE_URL=https://<name>.trycloudflare.com"
echo "  POS_API_SERVICE_USERNAME=cpms_service"
echo "  POS_API_SERVICE_PASSWORD=demo1234"
echo ""

exec cloudflared tunnel --url "${TARGET_URL}"
