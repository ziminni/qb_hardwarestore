#!/usr/bin/env bash
# Share this POS with a CPMS on another computer through a free Cloudflare Quick
# Tunnel. Only the tunnel gateway is exposed: CPMS sign-in plus the
# /api/v1/integration/cpms/ routes, and only with the secret gateway key.
#
# Usage (from anywhere):  ./scripts/start-tunnel.sh
# Stop:                    docker compose --profile tunnel stop gateway cloudflared

set -euo pipefail
cd "$(dirname "$0")/.."

KEY_FILE=tunnel/gateway.env
if [ ! -f "$KEY_FILE" ]; then
  key=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
  printf 'QB_GATEWAY_KEY=%s\n' "$key" > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  echo "Created $KEY_FILE with a new gateway key."
fi
key=$(sed -n 's/^QB_GATEWAY_KEY=//p' "$KEY_FILE")

# Recreate cloudflared so its log holds only this run's URL.
docker compose --profile tunnel up -d --force-recreate gateway cloudflared

echo "Waiting for the tunnel URL..."
url=""
for _ in $(seq 1 60); do
  url=$(docker compose logs cloudflared 2>/dev/null \
    | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1 || true)
  [ -n "$url" ] && break
  sleep 2
done
if [ -z "$url" ]; then
  echo "No tunnel URL after 2 minutes. Check: docker compose logs cloudflared" >&2
  exit 1
fi

cat <<MSG

POS is reachable at $url (gateway only).

On the CPMS computer, put these lines in
  qb_project_management_system/django-backend/.env
then run  docker compose up -d  there:

POS_API_BASE_URL=$url
POS_API_ALLOW_INSECURE_LOCAL=False
POS_API_GATEWAY_HEADER_NAME=X-QB-Gateway-Key
POS_API_GATEWAY_HEADER_VALUE=$key

Keep the key private. The URL changes every time the tunnel restarts.
Stop:  docker compose --profile tunnel stop gateway cloudflared
MSG
