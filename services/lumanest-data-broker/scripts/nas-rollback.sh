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

BACKUP_DIR_INPUT=${1%/}
LUMANEST_ROOT_INPUT=${LUMANEST_ROOT:-/vol2/docker/lumanest}
BACKUP_HELPER_IMAGE=${BACKUP_HELPER_IMAGE:-redis:7.4-alpine}
HEALTHCHECK_ATTEMPTS=${HEALTHCHECK_ATTEMPTS:-60}
HEALTHCHECK_INTERVAL_SECONDS=${HEALTHCHECK_INTERVAL_SECONDS:-3}
ROLLBACK_PHASE=preflight

canonical_dir() {
  (CDPATH= cd -- "$1" 2>/dev/null && pwd -P)
}

safe_single_line() {
  case "$1" in
    *'
'*) return 1 ;;
    *) return 0 ;;
  esac
}

valid_identifier() {
  case "$1" in
    ''|.|..|-*|*[!a-zA-Z0-9_.-]*) return 1 ;;
    *) return 0 ;;
  esac
}

valid_image_reference() {
  case "$1" in
    ''|-*|*[!a-zA-Z0-9_./:@-]*) return 1 ;;
    *) return 0 ;;
  esac
}

require_under_root() {
  case "$1" in
    "$LUMANEST_ROOT"/*) ;;
    *) echo "$2 must be under $LUMANEST_ROOT." >&2; exit 1 ;;
  esac
}

atomic_write() {
  destination=$1
  value=$2
  temporary=$destination.tmp.$$
  printf '%s\n' "$value" > "$temporary"
  mv -f "$temporary" "$destination"
}

manifest_value() {
  key=$1
  count=$(awk -F= -v key="$key" '$1 == key {count += 1} END {print count + 0}' "$MANIFEST")
  if [ "$count" -ne 1 ]; then
    echo "Manifest must contain exactly one $key entry." >&2
    return 1
  fi
  awk -F= -v key="$key" '$1 == key {print substr($0, index($0, "=") + 1)}' "$MANIFEST"
}

compose_live() {
  docker compose \
    -p "$PROJECT_NAME" \
    --env-file "$LIVE_DIR/qweather-token-broker.env" \
    -f "$LIVE_DIR/compose.yaml" \
    "$@"
}

compose_current() {
  docker compose \
    -p "$PROJECT_NAME" \
    --env-file "$CURRENT_RELEASE/qweather-token-broker.env" \
    -f "$CURRENT_RELEASE/compose.yaml" \
    "$@"
}

restore_volume() {
  volume=$1
  archive=$volume.tar.gz
  docker run --rm --network none --read-only --cap-drop ALL \
    --cap-add DAC_OVERRIDE --cap-add FOWNER --cap-add CHOWN \
    --security-opt no-new-privileges \
    -e ARCHIVE="$archive" \
    -v "$volume:/target" -v "$BACKUP_DIR/volumes:/backup:ro" \
    "$BACKUP_HELPER_IMAGE" sh -ec \
    'staging=/target/.lumanest-restore-$$
     rm -rf -- "$staging"
     mkdir -p "$staging"
     if ! tar -C "$staging" -xzf "/backup/$ARCHIVE"; then
       rm -rf -- "$staging"
       exit 1
     fi
     staging_name=${staging##*/}
     find /target -mindepth 1 -maxdepth 1 ! -name "$staging_name" -exec rm -rf -- {} +
     find "$staging" -mindepth 1 -maxdepth 1 -exec mv -- {} /target/ \;
     rmdir "$staging"'
}

validate_image_backup() {
  if [ ! -e "$BACKUP_DIR/application-images.txt" ] && [ ! -e "$BACKUP_DIR/application-images.tar" ]; then
    return 2
  fi
  if [ ! -s "$BACKUP_DIR/application-images.txt" ] || [ ! -s "$BACKUP_DIR/application-images.tar" ]; then
    echo "Application image backup is incomplete." >&2
    return 1
  fi
  image_count=0
  while IFS='|' read -r service original_ref backup_ref extra; do
    if ! valid_identifier "$service" || \
        ! valid_image_reference "$original_ref" || \
        ! valid_image_reference "$backup_ref" || \
        [ -n "$extra" ]; then
      echo "Unsafe application image mapping in backup." >&2
      return 1
    fi
    image_count=$((image_count + 1))
  done < "$BACKUP_DIR/application-images.txt"
  if [ "$image_count" -lt 1 ]; then
    echo "Application image mapping is empty." >&2
    return 1
  fi
}

load_backup_images() {
  docker image load -i "$BACKUP_DIR/application-images.tar" >/dev/null
}

restore_backup_image_tags() {
  while IFS='|' read -r service original_ref backup_ref extra; do
    docker image tag "$backup_ref" "$original_ref"
  done < "$BACKUP_DIR/application-images.txt"
}

cleanup_backup_image_tags() {
  [ -f "$BACKUP_DIR/application-images.txt" ] || return 0
  while IFS='|' read -r service original_ref backup_ref extra; do
    [ -n "$backup_ref" ] || continue
    docker image rm "$backup_ref" >/dev/null 2>&1 || true
  done < "$BACKUP_DIR/application-images.txt"
}

validate_volume_archives() {
  if [ ! -s "$BACKUP_DIR/volumes.txt" ]; then
    echo "Backup volume list is empty." >&2
    return 1
  fi
  while IFS= read -r volume; do
    [ -n "$volume" ] || continue
    if ! valid_identifier "$volume"; then
      echo "Unsafe Docker volume name: $volume" >&2
      return 1
    fi
    archive=$BACKUP_DIR/volumes/$volume.tar.gz
    if [ ! -f "$archive" ] || ! tar -tzf "$archive" >/dev/null; then
      echo "Volume archive is missing or invalid: $archive" >&2
      return 1
    fi
  done < "$BACKUP_DIR/volumes.txt"
}

validate_live_archive() {
  expected_prefix=${LIVE_DIR_RAW#"$LUMANEST_ROOT"/}
  members_file=$BACKUP_DIR/.live-source-members.$$
  if ! tar -tzf "$BACKUP_DIR/live-source.tar.gz" > "$members_file"; then
    rm -f "$members_file"
    return 1
  fi
  if [ ! -s "$members_file" ]; then
    echo "Live source archive is empty." >&2
    rm -f "$members_file"
    return 1
  fi
  while IFS= read -r member; do
    case "/$member/" in
      */../*|*/./*) echo "Unsafe path in live source archive: $member" >&2; rm -f "$members_file"; return 1 ;;
    esac
    case "$member" in
      "$expected_prefix"|"$expected_prefix"/*) ;;
      *) echo "Live source archive escapes the recorded release: $member" >&2; rm -f "$members_file"; return 1 ;;
    esac
  done < "$members_file"
  rm -f "$members_file"
}

verify_http_boundary() {
  attempt=1
  while ! curl --max-time 5 --fail --silent http://127.0.0.1:8787/healthz >/dev/null; do
    if [ "$attempt" -ge "$HEALTHCHECK_ATTEMPTS" ]; then
      echo "Broker health check timed out after rollback." >&2
      return 1
    fi
    attempt=$((attempt + 1))
    sleep "$HEALTHCHECK_INTERVAL_SECONDS"
  done

  admin_status=$(curl --max-time 5 --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:8788/admin || true)
  public_admin_status=$(curl --max-time 5 --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:8787/admin || true)
  if [ "$admin_status" != "200" ] || [ "$public_admin_status" != "404" ]; then
    echo "Admin boundary check failed after rollback: 8788=$admin_status 8787=$public_admin_status" >&2
    return 1
  fi
}

verify_live_context() {
  services=$(compose_live config --services) || return 1
  if printf '%s\n' "$services" | grep -qx 'context-service'; then
    compose_live exec -T context-service python -c \
      "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3)" >/dev/null
  fi
}

verify_live_discovery() {
  services=$(compose_live config --services) || return 1
  if printf '%s\n' "$services" | grep -qx 'discovery-api'; then
    compose_live exec -T discovery-api python -c \
      "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8001/readyz', timeout=3)" >/dev/null
  fi
}

verify_live_discovery_worker() {
  services=$(compose_live config --services) || return 1
  if printf '%s\n' "$services" | grep -qx 'discovery-worker'; then
    compose_live exec -T discovery-worker python -c \
      "import os; from redis import Redis; assert Redis.from_url(os.environ['REDIS_URL'], decode_responses=True).get('discovery:worker:heartbeat') == 'ok'" >/dev/null
  fi
}

rollback_failed() {
  status=$?
  trap - EXIT INT TERM
  [ "$status" -ne 0 ] || status=1
  if [ "$ROLLBACK_PHASE" != "preflight" ]; then
    echo "ROLLBACK FAILED during phase '$ROLLBACK_PHASE'. current-release was not changed; inspect Docker state and the selected backup before continuing." >&2
  fi
  exit "$status"
}

case "$HEALTHCHECK_ATTEMPTS" in
  ''|0|*[!0-9]*) echo "HEALTHCHECK_ATTEMPTS must be a positive integer." >&2; exit 1 ;;
esac
case "$HEALTHCHECK_INTERVAL_SECONDS" in
  ''|0|*[!0-9]*) echo "HEALTHCHECK_INTERVAL_SECONDS must be a positive integer." >&2; exit 1 ;;
esac

LUMANEST_ROOT=$(canonical_dir "$LUMANEST_ROOT_INPUT") || {
  echo "LumaNest root does not exist: $LUMANEST_ROOT_INPUT" >&2
  exit 1
}
BACKUP_DIR=$(canonical_dir "$BACKUP_DIR_INPUT") || {
  echo "Backup directory does not exist: $BACKUP_DIR_INPUT" >&2
  exit 1
}
case "$BACKUP_DIR" in
  "$LUMANEST_ROOT"/backups/*) ;;
  *) echo "Backup must resolve under $LUMANEST_ROOT/backups." >&2; exit 1 ;;
esac

MANIFEST=$BACKUP_DIR/manifest.env
if [ ! -f "$MANIFEST" ] || [ ! -f "$BACKUP_DIR/live-source.tar.gz" ] || [ ! -f "$BACKUP_DIR/volumes.txt" ]; then
  echo "Backup is incomplete: $BACKUP_DIR" >&2
  exit 1
fi

PROJECT_NAME=$(manifest_value PROJECT_NAME)
LIVE_DIR_RAW=$(manifest_value LIVE_DIR)
RECORDED_RELEASE_RAW=$(manifest_value RELEASE_DIR)
if ! valid_identifier "$PROJECT_NAME"; then
  echo "Unsafe Compose project name in manifest: $PROJECT_NAME" >&2
  exit 1
fi
if ! safe_single_line "$LIVE_DIR_RAW"; then
  echo "LIVE_DIR in manifest must be a single line." >&2
  exit 1
fi
require_under_root "$LIVE_DIR_RAW" "LIVE_DIR in manifest"
case "/${LIVE_DIR_RAW#"$LUMANEST_ROOT"/}/" in
  */../*|*/./*) echo "LIVE_DIR in manifest contains unsafe path segments." >&2; exit 1 ;;
esac
if ! safe_single_line "$RECORDED_RELEASE_RAW"; then
  echo "RELEASE_DIR in manifest must be a single line." >&2
  exit 1
fi
require_under_root "$RECORDED_RELEASE_RAW" "RELEASE_DIR in manifest"

validate_volume_archives
validate_live_archive
HAS_IMAGE_BACKUP=0
if validate_image_backup; then
  HAS_IMAGE_BACKUP=1
else
  image_status=$?
  if [ "$image_status" -ne 2 ]; then
    exit "$image_status"
  fi
  echo "Legacy backup has no application image archive; rollback will rebuild old application images." >&2
fi

CURRENT_RELEASE_RAW=$(cat "$LUMANEST_ROOT/current-release" 2>/dev/null || true)
if [ -z "$CURRENT_RELEASE_RAW" ] || ! safe_single_line "$CURRENT_RELEASE_RAW"; then
  echo "A valid current-release pointer is required before destructive rollback." >&2
  exit 1
fi
CURRENT_RELEASE=$(canonical_dir "$CURRENT_RELEASE_RAW") || {
  echo "Current release does not exist: $CURRENT_RELEASE_RAW" >&2
  exit 1
}
require_under_root "$CURRENT_RELEASE" "Current release"
RECORDED_RELEASE=$(canonical_dir "$RECORDED_RELEASE_RAW") || {
  echo "Release recorded by the backup does not exist: $RECORDED_RELEASE_RAW" >&2
  exit 1
}
require_under_root "$RECORDED_RELEASE" "Release recorded by the backup"
if [ "$CURRENT_RELEASE" != "$RECORDED_RELEASE" ]; then
  if [ "${CONFIRM_FAILED_DEPLOY_RECOVERY:-}" != "yes" ] || [ "$CURRENT_RELEASE" != "$LIVE_DIR_RAW" ]; then
    echo "This backup belongs to $RECORDED_RELEASE, not the active release $CURRENT_RELEASE." >&2
    echo "Only a confirmed retry of a failed deployment may restore while current-release still points to $LIVE_DIR_RAW." >&2
    exit 1
  fi
elif [ "$CURRENT_RELEASE" = "$LIVE_DIR_RAW" ]; then
  echo "The requested backup already points to the active release." >&2
  exit 1
fi
if [ -d "$LIVE_DIR_RAW" ]; then
  LIVE_DIR=$(canonical_dir "$LIVE_DIR_RAW")
  require_under_root "$LIVE_DIR" "LIVE_DIR in manifest"
else
  LIVE_DIR=$LIVE_DIR_RAW
fi

for required in \
  "$CURRENT_RELEASE/compose.yaml" \
  "$CURRENT_RELEASE/qweather-token-broker.env"; do
  if [ ! -f "$required" ]; then
    echo "Required current release file is missing: $required" >&2
    exit 1
  fi
done

command -v docker >/dev/null
command -v curl >/dev/null
command -v grep >/dev/null
command -v tar >/dev/null
if ! docker info >/dev/null 2>&1; then
  echo "The current user cannot access Docker. Add it to the docker group and start a new session." >&2
  exit 1
fi
docker image inspect "$BACKUP_HELPER_IMAGE" >/dev/null 2>&1 || docker pull "$BACKUP_HELPER_IMAGE"
if [ "$HAS_IMAGE_BACKUP" -eq 1 ]; then
  # Loading validates the image tar before the destructive rollback starts.
  load_backup_images
fi

trap rollback_failed EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ROLLBACK_PHASE=stopping-current
compose_current down --remove-orphans

ROLLBACK_PHASE=restoring-volumes
while IFS= read -r volume; do
  [ -n "$volume" ] || continue
  docker volume inspect "$volume" >/dev/null 2>&1 || docker volume create "$volume" >/dev/null
  restore_volume "$volume"
done < "$BACKUP_DIR/volumes.txt"

if [ ! -d "$LIVE_DIR" ]; then
  tar -C "$LUMANEST_ROOT" -xzf "$BACKUP_DIR/live-source.tar.gz"
  LIVE_DIR=$(canonical_dir "$LIVE_DIR_RAW") || {
    echo "Restored release directory is missing: $LIVE_DIR_RAW" >&2
    exit 1
  }
  require_under_root "$LIVE_DIR" "Restored release"
fi
for required in "$LIVE_DIR/compose.yaml" "$LIVE_DIR/qweather-token-broker.env"; do
  if [ ! -f "$required" ]; then
    echo "Required restored release file is missing: $required" >&2
    exit 1
  fi
done

ROLLBACK_PHASE=starting-previous
if [ "$HAS_IMAGE_BACKUP" -eq 1 ]; then
  restore_backup_image_tags
  compose_live up -d --no-build --remove-orphans
else
  compose_live up -d --build --remove-orphans
fi
ROLLBACK_PHASE=verifying-previous
verify_http_boundary
verify_live_context
verify_live_discovery
verify_live_discovery_worker

atomic_write "$LUMANEST_ROOT/current-release" "$LIVE_DIR"
trap - EXIT INT TERM
ROLLBACK_PHASE=complete
cleanup_backup_image_tags
compose_live ps
echo "Rollback completed and verified from $BACKUP_DIR"
