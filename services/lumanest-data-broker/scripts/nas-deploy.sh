#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RELEASE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
LUMANEST_ROOT=${LUMANEST_ROOT:-/vol2/docker/lumanest}
LIVE_DIR=${LIVE_DIR:-$LUMANEST_ROOT/qweather-token-broker}
PROJECT_NAME=${PROJECT_NAME:-qweather-token-broker}
ENV_FILE=$RELEASE_DIR/qweather-token-broker.env
COMPOSE_FILE=$RELEASE_DIR/compose.yaml
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR=$LUMANEST_ROOT/backups/$TIMESTAMP
BACKUP_HELPER_IMAGE=${BACKUP_HELPER_IMAGE:-redis:7.4-alpine}
PREVIOUS_RELEASE=$(cat "$LUMANEST_ROOT/current-release" 2>/dev/null || true)
if [ -z "$PREVIOUS_RELEASE" ]; then
  PREVIOUS_RELEASE=$LIVE_DIR
fi

require_file() {
  if [ ! -f "$1" ]; then
    echo "Required file is missing: $1" >&2
    exit 1
  fi
}

compose_release() {
  docker compose -p "$PROJECT_NAME" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

valid_volume_name() {
  case "$1" in
    ''|*[!a-zA-Z0-9_.-]*) return 1 ;;
    *) return 0 ;;
  esac
}

backup_volume() {
  volume=$1
  archive=$volume.tar.gz
  owner=$(id -u):$(id -g)
  docker run --rm --network none --read-only --cap-drop ALL \
    --security-opt no-new-privileges \
    -e ARCHIVE="$archive" -e OWNER="$owner" \
    -v "$volume:/source:ro" -v "$BACKUP_DIR/volumes:/backup" \
    "$BACKUP_HELPER_IMAGE" sh -ec \
    'tar -C /source -czf "/backup/$ARCHIVE" . && chown "$OWNER" "/backup/$ARCHIVE" && chmod 600 "/backup/$ARCHIVE"'
}

restore_old_stack() {
  if [ -f "$PREVIOUS_RELEASE/compose.yaml" ] && [ -f "$PREVIOUS_RELEASE/qweather-token-broker.env" ]; then
    docker compose \
      -p "$PROJECT_NAME" \
      --env-file "$PREVIOUS_RELEASE/qweather-token-broker.env" \
      -f "$PREVIOUS_RELEASE/compose.yaml" \
      up -d --build || true
  fi
}

deployment_failed() {
  status=$?
  trap - EXIT INT TERM
  echo "Deployment failed; restoring the previous stack." >&2
  compose_release down --remove-orphans >/dev/null 2>&1 || true
  restore_old_stack
  echo "Backup retained at $BACKUP_DIR" >&2
  exit "$status"
}

require_file "$COMPOSE_FILE"
require_file "$ENV_FILE"
require_file "$RELEASE_DIR/../lumanest-context-service/Dockerfile"
require_file "$PREVIOUS_RELEASE/compose.yaml"
require_file "$PREVIOUS_RELEASE/qweather-token-broker.env"
command -v docker >/dev/null
command -v curl >/dev/null
command -v tar >/dev/null
if ! docker info >/dev/null 2>&1; then
  echo "The current user cannot access Docker. Add it to the docker group and start a new session." >&2
  exit 1
fi
case "$PREVIOUS_RELEASE" in
  "$LUMANEST_ROOT"/*) ;;
  *) echo "Previous release must be under $LUMANEST_ROOT." >&2; exit 1 ;;
esac

# Validate interpolation and build contexts before stopping the running stack.
compose_release config --quiet
docker image inspect "$BACKUP_HELPER_IMAGE" >/dev/null 2>&1 || docker pull "$BACKUP_HELPER_IMAGE"

umask 077
mkdir -p "$BACKUP_DIR/volumes"
cat > "$BACKUP_DIR/manifest.env" <<EOF
PROJECT_NAME=$PROJECT_NAME
LIVE_DIR=$PREVIOUS_RELEASE
RELEASE_DIR=$RELEASE_DIR
CREATED_AT=$TIMESTAMP
EOF
previous_relative=${PREVIOUS_RELEASE#"$LUMANEST_ROOT"/}
tar -C "$LUMANEST_ROOT" -czf "$BACKUP_DIR/live-source.tar.gz" "$previous_relative"

trap deployment_failed EXIT INT TERM
docker compose \
  -p "$PROJECT_NAME" \
  --env-file "$PREVIOUS_RELEASE/qweather-token-broker.env" \
  -f "$PREVIOUS_RELEASE/compose.yaml" \
  stop

docker volume ls \
  --filter "label=com.docker.compose.project=$PROJECT_NAME" \
  --format '{{.Name}}' > "$BACKUP_DIR/volumes.txt"

while IFS= read -r volume; do
  [ -n "$volume" ] || continue
  if ! valid_volume_name "$volume"; then
    echo "Unsafe Docker volume name: $volume" >&2
    exit 1
  fi
  backup_volume "$volume"
done < "$BACKUP_DIR/volumes.txt"

compose_release up -d --build --remove-orphans

attempt=0
until curl --fail --silent --show-error http://127.0.0.1:8787/healthz >/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 60 ]; then
    echo "Broker health check timed out." >&2
    exit 1
  fi
  sleep 3
done

admin_status=$(curl --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:8788/admin)
public_admin_status=$(curl --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:8787/admin)
if [ "$admin_status" != "200" ] || [ "$public_admin_status" != "404" ]; then
  echo "Admin boundary check failed: 8788=$admin_status 8787=$public_admin_status" >&2
  exit 1
fi

compose_release exec -T context-service python -c \
  "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3)" >/dev/null

printf '%s\n' "$RELEASE_DIR" > "$LUMANEST_ROOT/current-release"
printf '%s\n' "$BACKUP_DIR" > "$LUMANEST_ROOT/last-backup"
trap - EXIT INT TERM

compose_release ps
echo "Deployment completed."
echo "Backup: $BACKUP_DIR"
