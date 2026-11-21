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
token=$(sed -n 's/^CLOUDFLARE_TUNNEL_TOKEN=//p' "$KEY_FILE")
hostname=$(sed -n 's/^CLOUDFLARE_TUNNEL_HOSTNAME=//p' "$KEY_FILE")

# docker-compose.yml reads these to pick Named vs Quick Tunnel (the image has no shell).
if [ -n "$token" ]; then
  export CLOUDFLARE_TUNNEL_TOKEN="$token" CLOUDFLARED_TUNNEL_ARGS=run
else
  unset CLOUDFLARE_TUNNEL_TOKEN CLOUDFLARED_TUNNEL_ARGS
fi

# Recreate cloudflared so its log holds only this run's URL.
docker compose --profile tunnel up -d --force-recreate gateway cloudflared

if [ -n "$token" ]; then
  url="${hostname:-https://<your-named-tunnel-hostname>}"
  case "$url" in http://*|https://*) ;; *) url="https://$url" ;; esac
else
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
fi

if [ -n "$token" ]; then
  url_note="Named tunnel active: this URL stays fixed across restarts."
else
  url_note="The URL changes every time a Quick Tunnel restarts."
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

Keep the key private. $url_note
Stop:  docker compose --profile tunnel stop gateway cloudflared
MSG
