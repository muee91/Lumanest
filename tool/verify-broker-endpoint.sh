#!/usr/bin/env bash
# Prove a broker base URL is really the LumaNest broker before trusting it.
#
# A tunnel that silently retargets to another service still answers 200, so
# status codes alone are not enough. These four checks only pass together for
# our broker, and each one names a different failure mode:
#   healthz      -> wrong application entirely
#   auth boundary -> credential-less exposure of business routes
#   /admin       -> admin console published to the internet
#   /metrics     -> the token this script and the app carry is not our token
#
# Usage: tool/verify-broker-endpoint.sh <base-url> [service-token-file]
set -euo pipefail

base_url="${1:-}"
token_file="${2:-}"

if [[ -z "$base_url" ]]; then
  echo "usage: $0 <base-url> [service-token-file]" >&2
  exit 2
fi
base_url="${base_url%/}"

# No token file argument means fall back to the client env the app itself uses.
if [[ -z "$token_file" ]]; then
  workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  token_file="$workspace_root/.secrets/nas/lumanest-token-broker-service-token"
fi

failures=0
check() {
  local name="$1" expected="$2" actual="$3" detail="${4:-}"
  if [[ "$actual" == "$expected" ]]; then
    printf 'ok    %-26s %s\n' "$name" "${detail:-$expected}"
  else
    printf 'FAIL  %-26s expected %s, got %s\n' "$name" "$expected" "${actual:-none}"
    failures=$((failures + 1))
  fi
}

request() {
  # method url [curl-args...]
  local method="$1" url="$2"
  shift 2
  curl -sS -m 20 -o /dev/null -w '%{http_code}' -X "$method" "$@" "$url" \
    2>/dev/null || echo "000"
}

host="$(printf '%s' "$base_url" | sed -E 's#^[a-z]+://##; s#[:/].*##')"
if [[ "$base_url" == http://* && ! "$host" =~ ^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|localhost) ]]; then
  echo "note: plaintext http to a non-private host: $base_url" >&2
fi

# 1. /healthz must be our exact JSON body, not another app's "OK".
health_body="$(curl -sS -m 20 "$base_url/healthz" 2>/dev/null || true)"
check healthz-shape '{"status":"ok"}' "$health_body"

# 2. An unauthenticated business route must be refused, never served.
auth_status="$(request GET "$base_url/v1/environment/sky-windows")"
check auth-enforced 401 "$auth_status"

# 3. The admin console lives on its own listener; the app port must 404 it.
admin_status="$(request GET "$base_url/admin")"
check admin-not-public 404 "$admin_status"

# 4. Our token must be accepted, and must return our own metric namespace.
metrics_status="skipped"
if [[ -r "$token_file" ]]; then
  token="$(tr -d '\n' < "$token_file")"
  metrics_status="$(request GET "$base_url/metrics" -H "Authorization: Bearer $token")"
  check metrics-auth 200 "$metrics_status"
  # A foreign app can serve /metrics without caring about tokens at all, which
  # would pass the line above. Requiring a bad token to be refused is what
  # actually proves we reached a broker that authenticates.
  bogus_status="$(request GET "$base_url/metrics" -H "Authorization: Bearer not-the-service-token")"
  check metrics-rejects-bad-token 401 "$bogus_status"
  series="$(curl -sS -m 20 -H "Authorization: Bearer $token" "$base_url/metrics" 2>/dev/null \
    | grep -c '^lumanest_' || true)"
  if [[ "$series" -gt 0 ]]; then
    printf 'ok    %-26s %s series\n' metrics-namespace "$series"
  else
    printf 'FAIL  %-26s no lumanest_* series served\n' metrics-namespace
    failures=$((failures + 1))
  fi
  if [[ "$series" -gt 0 ]] && ! curl -sS -m 20 -H "Authorization: Bearer $token" \
      "$base_url/metrics" 2>/dev/null | awk '/^lumanest/ && $NF != "0" {found=1} END{exit !found}'; then
    echo "note: broker is reachable and authenticated but every counter is 0." >&2
    echo "      Nothing instrumented has reached it since it started. If a client" >&2
    echo "      is expected to be talking to it, suspect the client's base URL or" >&2
    echo "      the tunnel, not the backend's content supply." >&2
  fi
else
  printf 'skip  %-26s no readable token file\n' "metrics-auth"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "not our broker, or misconfigured: $base_url" >&2
  exit 1
fi
echo "verified: $base_url"
