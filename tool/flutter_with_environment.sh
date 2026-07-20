#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="$workspace_root/.secrets/environment.debug.json"

if [[ ! -f "$source_file" ]]; then
  echo "Missing $source_file" >&2
  exit 1
fi

safe_file="$(mktemp "${TMPDIR:-/tmp}/lumanest-client-env.XXXXXX")"
trap 'rm -f "$safe_file"' EXIT

# The central JSON also contains server-only values. Only these client-safe
# fields may be passed to Flutter and therefore considered for APK embedding.
jq '{
  AMAP_ANDROID_KEY,
  LUMANEST_BROKER_BASE_URL,
  LUMANEST_SERVICE_TOKEN,
  SENTRY_DSN
}' "$source_file" > "$safe_file"

cd "$workspace_root"
command_name="${1:-}"
case "$command_name" in
  build|run|test|drive)
    flutter "$@" --dart-define-from-file="$safe_file"
    ;;
  *)
    flutter "$@"
    ;;
esac
