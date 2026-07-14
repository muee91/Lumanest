#!/bin/sh
set -eu

if [ "${CONFIRM_ROLLBACK:-}" != "yes" ]; then
  echo "Set CONFIRM_ROLLBACK=yes to restore archived Docker volumes." >&2
  exit 1
fi

if [ "$#" -ne 1 ]; then
  echo "Usage: CONFIRM_ROLLBACK=yes $0 /vol2/docker/lumanest/backups/<timestamp>" >&2
  exit 1
fi

BACKUP_DIR=${1%/}
LUMANEST_ROOT=${LUMANEST_ROOT:-/vol2/docker/lumanest}
MANIFEST=$BACKUP_DIR/manifest.env
BACKUP_HELPER_IMAGE=${BACKUP_HELPER_IMAGE:-redis:7.4-alpine}

valid_volume_name() {
  case "$1" in
    ''|*[!a-zA-Z0-9_.-]*) return 1 ;;
    *) return 0 ;;
  esac
}

restore_volume() {
  volume=$1
  archive=$volume.tar.gz
  docker run --rm --network none --read-only --cap-drop ALL \
    --security-opt no-new-privileges \
    -e ARCHIVE="$archive" \
    -v "$volume:/target" -v "$BACKUP_DIR/volumes:/backup:ro" \
    "$BACKUP_HELPER_IMAGE" sh -ec \
    'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf "/backup/$ARCHIVE"'
}

case "$BACKUP_DIR" in
  "$LUMANEST_ROOT"/backups/*) ;;
  *) echo "Backup must be under $LUMANEST_ROOT/backups." >&2; exit 1 ;;
esac

if [ ! -f "$MANIFEST" ] || [ ! -f "$BACKUP_DIR/live-source.tar.gz" ] || [ ! -f "$BACKUP_DIR/volumes.txt" ]; then
  echo "Backup is incomplete: $BACKUP_DIR" >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "The current user cannot access Docker. Add it to the docker group and start a new session." >&2
  exit 1
fi
docker image inspect "$BACKUP_HELPER_IMAGE" >/dev/null 2>&1 || docker pull "$BACKUP_HELPER_IMAGE"

PROJECT_NAME=$(awk -F= '$1 == "PROJECT_NAME" {print substr($0, index($0, "=") + 1)}' "$MANIFEST")
LIVE_DIR=$(awk -F= '$1 == "LIVE_DIR" {print substr($0, index($0, "=") + 1)}' "$MANIFEST")
CURRENT_RELEASE=$(cat "$LUMANEST_ROOT/current-release" 2>/dev/null || true)

if [ -n "$CURRENT_RELEASE" ] && [ -f "$CURRENT_RELEASE/compose.yaml" ] && [ -f "$CURRENT_RELEASE/qweather-token-broker.env" ]; then
  docker compose \
    -p "$PROJECT_NAME" \
    --env-file "$CURRENT_RELEASE/qweather-token-broker.env" \
    -f "$CURRENT_RELEASE/compose.yaml" \
    down --remove-orphans
fi

while IFS= read -r volume; do
  [ -n "$volume" ] || continue
  if ! valid_volume_name "$volume"; then
    echo "Unsafe Docker volume name: $volume" >&2
    exit 1
  fi
  archive=$BACKUP_DIR/volumes/$volume.tar.gz
  if [ ! -f "$archive" ]; then
    echo "Volume archive is missing: $archive" >&2
    exit 1
  fi
  docker volume inspect "$volume" >/dev/null 2>&1 || docker volume create "$volume" >/dev/null
  restore_volume "$volume"
done < "$BACKUP_DIR/volumes.txt"

if [ ! -f "$LIVE_DIR/compose.yaml" ]; then
  tar -C "$LUMANEST_ROOT" -xzf "$BACKUP_DIR/live-source.tar.gz"
fi

docker compose \
  -p "$PROJECT_NAME" \
  --env-file "$LIVE_DIR/qweather-token-broker.env" \
  -f "$LIVE_DIR/compose.yaml" \
  up -d --build

printf '%s\n' "$LIVE_DIR" > "$LUMANEST_ROOT/current-release"
echo "Rollback completed from $BACKUP_DIR"
