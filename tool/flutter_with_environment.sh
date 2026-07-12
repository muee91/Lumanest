#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="$workspace_root/.secrets/environment.debug.json"

if [[ ! -f "$source_file" ]]; then
  echo "Missing $source_file" >&2
  exit 1
fi

safe_file="$(mktemp "${TMPDIR:-/tmp}/lumanest-client-env.XXXXXX.json")"
trap 'rm -f "$safe_file"' EXIT

# The central JSON also contains server-only values. Only these client-safe
# fields may be passed to Flutter and therefore considered for APK embedding.
jq '{
  AMAP_ANDROID_KEY,
  QWEATHER_API_HOST,
  QWEATHER_TOKEN_ENDPOINT,
  LUMANEST_SERVICE_TOKEN
}' "$source_file" > "$safe_file"

cd "$workspace_root"
flutter "$@" --dart-define-from-file="$safe_file"
