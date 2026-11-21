#!/usr/bin/env bash
# Share this POS with a CPMS on another computer through Cloudflare Tunnel
# (Named Tunnel with a permanent domain, or free Quick Tunnel).
# Only the tunnel gateway is exposed: CPMS sign-in plus the
# /api/v1/integration/cpms/ routes, and only with the secret gateway key.
#
# Usage (from anywhere):
#   ./scripts/start-tunnel.sh
#   ./scripts/start-tunnel.sh --token "<cloudflare-token>" --hostname "pos-api.yourdomain.com"
# Stop:
#   docker compose --profile tunnel stop gateway cloudflared

set -euo pipefail
cd "$(dirname "$0")/.."

arg_token=""
arg_hostname=""
arg_key=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --token) arg_token="${2:?Missing value for --token}"; shift 2 ;;
    --hostname) arg_hostname="${2:?Missing value for --hostname}"; shift 2 ;;
    --gateway-key) arg_key="${2:?Missing value for --gateway-key}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

KEY_FILE=tunnel/gateway.env
existing_key=""
existing_token=""
existing_hostname=""
if [ -f "$KEY_FILE" ]; then
  existing_key=$(sed -n 's/^QB_GATEWAY_KEY=//p' "$KEY_FILE")
  existing_token=$(sed -n 's/^CLOUDFLARE_TUNNEL_TOKEN=//p' "$KEY_FILE")
  existing_hostname=$(sed -n 's/^CLOUDFLARE_TUNNEL_HOSTNAME=//p' "$KEY_FILE")
fi

key="${arg_key:-$existing_key}"
if [ -z "$key" ]; then
  key=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
fi
token="${arg_token:-$existing_token}"
hostname="${arg_hostname:-$existing_hostname}"

if [ ! -f "$KEY_FILE" ] || [ -n "$arg_token" ] || [ -n "$arg_hostname" ] || [ -n "$arg_key" ]; then
  {
    printf 'QB_GATEWAY_KEY=%s\n' "$key"
    [ -n "$token" ] && printf 'CLOUDFLARE_TUNNEL_TOKEN=%s\n' "$token"
    [ -n "$hostname" ] && printf 'CLOUDFLARE_TUNNEL_HOSTNAME=%s\n' "$hostname"
  } > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  echo "Saved $KEY_FILE."
fi

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
