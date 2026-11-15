#!/bin/sh
# Refuse to start without a real gateway key: an empty key would match a request
# that sends no header at all.
if [ "${#QB_GATEWAY_KEY}" -lt 24 ]; then
  echo "QB_GATEWAY_KEY is missing or shorter than 24 characters; run scripts/start-tunnel first." >&2
  exit 1
fi
