#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="$workspace_root/.secrets/environment.debug.json"
command_name="${1:-}"

cd "$workspace_root"
case "$command_name" in
  build|run|drive|test-configured)
    ;;
  *)
    # Unit/widget tests and commands such as analyze stay independent of the
    # machine's real service configuration.
    flutter "$@"
    exit
    ;;
esac

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

case "$command_name" in
  build|run|drive)
    flutter "$@" --dart-define-from-file="$safe_file"
    ;;
  test-configured)
    shift
    flutter test "$@" --dart-define-from-file="$safe_file"
    ;;
esac
