#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
RELEASE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
LUMANEST_ROOT_INPUT=${LUMANEST_ROOT:-/vol2/docker/lumanest}
LIVE_DIR_INPUT=${LIVE_DIR:-$LUMANEST_ROOT_INPUT/qweather-token-broker}
PROJECT_NAME=${PROJECT_NAME:-qweather-token-broker}
BROKER_DOCKERFILE=${BROKER_DOCKERFILE:-Dockerfile}
CONTEXT_DOCKERFILE=${CONTEXT_DOCKERFILE:-Dockerfile}
DISCOVERY_DOCKERFILE=${DISCOVERY_DOCKERFILE:-Dockerfile}
RASTER_DOCKERFILE=${RASTER_DOCKERFILE:-Dockerfile}
TERRAIN_DOCKERFILE=${TERRAIN_DOCKERFILE:-Dockerfile}
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_HELPER_IMAGE=${BACKUP_HELPER_IMAGE:-redis:7.4-alpine}
HEALTHCHECK_ATTEMPTS=${HEALTHCHECK_ATTEMPTS:-60}
HEALTHCHECK_INTERVAL_SECONDS=${HEALTHCHECK_INTERVAL_SECONDS:-3}
SKIP_BUILD=${SKIP_BUILD:-0}
DATA_MAY_BE_CHANGED=0
BACKUP_COMPLETE=0

require_file() {
  if [ ! -f "$1" ]; then
    echo "Required file is missing: $1" >&2
    exit 1
  fi
}

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

environment_value() {
  name=$1
  awk -v name="$name" 'index($0, name "=") == 1 { value=substr($0, length(name) + 2) } END { print value }' "$ENV_FILE"
}

upsert_environment_value() {
  name=$1
  value=$2
  temporary=$ENV_FILE.tmp.$$
  awk -v name="$name" -v value="$value" '
    index($0, name "=") == 1 {
      if (!seen++) print name "=" value
      next
    }
    { print }
    END { if (!seen) print name "=" value }
  ' "$ENV_FILE" > "$temporary"
  chmod 600 "$temporary"
  mv -f "$temporary" "$ENV_FILE"
}

ensure_outbound_network_environment() {
  mode=$(environment_value LUMANEST_OUTBOUND_NETWORK_MODE)
  case "$mode" in
    direct|mihomo) ;;
    *)
      proxy=$(environment_value LUMANEST_OUTBOUND_PROXY_URL)
      if [ -n "$proxy" ]; then mode=mihomo; else mode=direct; fi
      upsert_environment_value LUMANEST_OUTBOUND_NETWORK_MODE "$mode"
      echo "Initialized outbound network mode: $mode"
      ;;
  esac

  controller_token=$(environment_value LUMANEST_NETWORK_CONTROLLER_TOKEN)
  if [ ${#controller_token} -lt 24 ]; then
    controller_token=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
    case "$controller_token" in
      *[!a-f0-9]*|'') echo "Unable to generate network controller token." >&2; exit 1 ;;
    esac
    upsert_environment_value LUMANEST_NETWORK_CONTROLLER_TOKEN "$controller_token"
    echo "Generated the protected network controller token."
  fi
}

compose_release() {
  docker compose -p "$PROJECT_NAME" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

compose_previous() {
  docker compose \
    -p "$PROJECT_NAME" \
    --env-file "$PREVIOUS_RELEASE/qweather-token-broker.env" \
    -f "$PREVIOUS_RELEASE/compose.yaml" \
    "$@"
}

backup_application_images() {
  services=$(compose_previous config --services) || return 1
  images_tmp=$BACKUP_DIR/application-images.txt.tmp.$$
  image_refs=
  broker_backed_up=0
  : > "$images_tmp"

  for service in qweather-token-broker context-service discovery-api discovery-worker lumanest-raster-service lumanest-terrain-service; do
    if ! printf '%s\n' "$services" | grep -qx "$service"; then
      continue
    fi
    container_id=$(compose_previous ps -q "$service") || return 1
    if [ -z "$container_id" ]; then
      echo "Cannot archive image because the previous $service container is missing." >&2
      return 1
    fi
    image_id=$(docker inspect --format '{{.Image}}' "$container_id") || return 1
    original_ref=$(docker inspect --format '{{.Config.Image}}' "$container_id") || return 1
    backup_ref=lumanest-rollback/$PROJECT_NAME-$service:$TIMESTAMP
    if ! valid_image_reference "$image_id" || \
        ! valid_image_reference "$original_ref" || \
        ! valid_image_reference "$backup_ref"; then
      echo "Unsafe Docker image reference for service $service." >&2
      return 1
    fi
    docker image tag "$image_id" "$backup_ref" || return 1
    printf '%s|%s|%s\n' "$service" "$original_ref" "$backup_ref" >> "$images_tmp"
    image_refs="$image_refs $backup_ref"
    if [ "$service" = "qweather-token-broker" ]; then
      broker_backed_up=1
    fi
  done

  if [ "$broker_backed_up" -ne 1 ]; then
    echo "The previous Broker image could not be archived." >&2
    return 1
  fi
  mv -f "$images_tmp" "$BACKUP_DIR/application-images.txt"
  # References are strictly validated above and therefore cannot contain spaces.
  # shellcheck disable=SC2086
  docker image save -o "$BACKUP_DIR/application-images.tar" $image_refs
  if [ ! -s "$BACKUP_DIR/application-images.tar" ]; then
    echo "Application image archive is empty." >&2
    return 1
  fi
}

validate_image_backup() {
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

restore_backup_images() {
  validate_image_backup || return 1
  docker image load -i "$BACKUP_DIR/application-images.tar" >/dev/null || return 1
  while IFS='|' read -r service original_ref backup_ref extra; do
    docker image tag "$backup_ref" "$original_ref" || return 1
  done < "$BACKUP_DIR/application-images.txt"
}

cleanup_backup_image_tags() {
  [ -f "$BACKUP_DIR/application-images.txt" ] || return 0
  while IFS='|' read -r service original_ref backup_ref extra; do
    [ -n "$backup_ref" ] || continue
    docker image rm "$backup_ref" >/dev/null 2>&1 || true
  done < "$BACKUP_DIR/application-images.txt"
}

backup_volume() {
  volume=$1
  archive=$volume.tar.gz
  owner=$(id -u):$(id -g)
  docker run --rm --network none --read-only --cap-drop ALL \
    --cap-add DAC_OVERRIDE --cap-add FOWNER --cap-add CHOWN \
    --security-opt no-new-privileges \
    -e ARCHIVE="$archive" -e OWNER="$owner" \
    -v "$volume:/source:ro" -v "$BACKUP_DIR/volumes:/backup" \
    "$BACKUP_HELPER_IMAGE" sh -ec \
    'tar -C /source -czf "/backup/$ARCHIVE" . && chown "$OWNER" "/backup/$ARCHIVE" && chmod 600 "/backup/$ARCHIVE"'
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

validate_volume_archives() {
  if [ ! -s "$BACKUP_DIR/volumes.txt" ]; then
    echo "No Docker volumes were discovered for project $PROJECT_NAME." >&2
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

restore_backup_volumes() {
  validate_volume_archives || return 1
  while IFS= read -r volume; do
    [ -n "$volume" ] || continue
    docker volume inspect "$volume" >/dev/null 2>&1 || docker volume create "$volume" >/dev/null
    restore_volume "$volume" || return 1
  done < "$BACKUP_DIR/volumes.txt"
}

verify_http_boundary() {
  expected_admin_marker=$1
  attempt=1
  while ! curl --max-time 5 --fail --silent http://127.0.0.1:8787/healthz >/dev/null; do
    if [ "$attempt" -ge "$HEALTHCHECK_ATTEMPTS" ]; then
      echo "Broker health check timed out." >&2
      return 1
    fi
    attempt=$((attempt + 1))
    sleep "$HEALTHCHECK_INTERVAL_SECONDS"
  done

  admin_status=$(curl --max-time 5 --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:8788/admin || true)
  public_admin_status=$(curl --max-time 5 --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:8787/admin || true)
  if [ "$admin_status" != "200" ] || [ "$public_admin_status" != "404" ]; then
    echo "Admin boundary check failed: 8788=$admin_status 8787=$public_admin_status" >&2
    return 1
  fi
  if [ -n "$expected_admin_marker" ] && \
      ! curl --max-time 5 --fail --silent http://127.0.0.1:8788/admin | grep -Fq "$expected_admin_marker"; then
    echo "Admin content check failed." >&2
    return 1
  fi
}

verify_previous_context() {
  services=$(compose_previous config --services) || return 1
  if printf '%s\n' "$services" | grep -qx 'context-service'; then
    compose_previous exec -T context-service python -c \
      "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3)" >/dev/null
  fi
}

verify_previous_discovery() {
  services=$(compose_previous config --services) || return 1
  if printf '%s\n' "$services" | grep -qx 'discovery-api'; then
    compose_previous exec -T discovery-api python -c \
      "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8001/readyz', timeout=3)" >/dev/null
  fi
}

verify_previous_discovery_worker() {
  services=$(compose_previous config --services) || return 1
  if printf '%s\n' "$services" | grep -qx 'discovery-worker'; then
    compose_previous exec -T discovery-worker python -c \
      "import os; from redis import Redis; assert Redis.from_url(os.environ['REDIS_URL'], decode_responses=True).get('discovery:worker:heartbeat') == 'ok'" >/dev/null
  fi
}

verify_release_discovery_worker() {
  attempt=1
  while ! compose_release exec -T discovery-worker python -c \
    "import os; from redis import Redis; assert Redis.from_url(os.environ['REDIS_URL'], decode_responses=True).get('discovery:worker:heartbeat') == 'ok'" >/dev/null 2>&1; do
    if [ "$attempt" -ge "$HEALTHCHECK_ATTEMPTS" ]; then
      echo "Discovery worker heartbeat check timed out." >&2
      return 1
    fi
    attempt=$((attempt + 1))
    sleep "$HEALTHCHECK_INTERVAL_SECONDS"
  done
}

verify_release_service_health() {
  service=$1
  attempt=1
  while :; do
    container_id=$(compose_release ps -q "$service" 2>/dev/null || true)
    health_status=
    if [ -n "$container_id" ]; then
      health_status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_id" 2>/dev/null || true)
    fi
    if [ "$health_status" = "healthy" ]; then
      return 0
    fi
    if [ "$attempt" -ge "$HEALTHCHECK_ATTEMPTS" ]; then
      echo "$service health check timed out (last status: ${health_status:-missing})." >&2
      return 1
    fi
    attempt=$((attempt + 1))
    sleep "$HEALTHCHECK_INTERVAL_SECONDS"
  done
}

restore_old_stack() {
  restore_backup_images || return 1
  compose_previous up -d --no-build --remove-orphans
}

deployment_failed() {
  original_status=$?
  trap - EXIT INT TERM
  set +e
  [ "$original_status" -ne 0 ] || original_status=1
  echo "Deployment failed; starting verified recovery from $BACKUP_DIR." >&2

  recovery_status=0
  if [ "$DATA_MAY_BE_CHANGED" -eq 1 ]; then
    if ! compose_release down --remove-orphans; then
      echo "Recovery stopped: the new stack could not be removed safely." >&2
      recovery_status=1
    elif ! restore_backup_volumes; then
      echo "Recovery stopped: archived Docker volumes could not be restored." >&2
      recovery_status=1
    fi
  fi

  if [ "$recovery_status" -eq 0 ]; then
    if ! restore_old_stack; then
      echo "Recovery failed: the previous stack could not be started." >&2
      recovery_status=1
    elif ! verify_http_boundary "" || ! verify_previous_context || ! verify_previous_discovery || ! verify_previous_discovery_worker; then
      echo "Recovery failed: the previous stack did not pass health checks." >&2
      recovery_status=1
    fi
  fi

  if [ "$recovery_status" -eq 0 ]; then
    if [ "$DATA_MAY_BE_CHANGED" -eq 1 ]; then
      echo "Previous stack, archived volumes, and application images restored successfully." >&2
    else
      echo "Previous stack restarted; persistent volumes were not modified." >&2
    fi
  else
    if [ "$BACKUP_COMPLETE" -eq 1 ]; then
      echo "AUTOMATIC RECOVERY FAILED. Keep all containers stopped and restore manually from $BACKUP_DIR." >&2
    else
      echo "AUTOMATIC RECOVERY FAILED before a complete volume backup existed. Do not restore from $BACKUP_DIR; inspect the unchanged volumes and Docker state." >&2
    fi
  fi
  echo "Backup retained at $BACKUP_DIR" >&2
  exit "$original_status"
}

if ! valid_identifier "$PROJECT_NAME"; then
  echo "Unsafe Compose project name: $PROJECT_NAME" >&2
  exit 1
fi
if ! valid_identifier "$BROKER_DOCKERFILE"; then
  echo "Unsafe Broker Dockerfile name: $BROKER_DOCKERFILE" >&2
  exit 1
fi
if ! valid_identifier "$CONTEXT_DOCKERFILE"; then
  echo "Unsafe Context Dockerfile name: $CONTEXT_DOCKERFILE" >&2
  exit 1
fi
if ! valid_identifier "$DISCOVERY_DOCKERFILE"; then
  echo "Unsafe Discovery Dockerfile name: $DISCOVERY_DOCKERFILE" >&2
  exit 1
fi
if ! valid_identifier "$RASTER_DOCKERFILE"; then
  echo "Unsafe Raster Dockerfile name: $RASTER_DOCKERFILE" >&2
  exit 1
fi
if ! valid_identifier "$TERRAIN_DOCKERFILE"; then
  echo "Unsafe Terrain Dockerfile name: $TERRAIN_DOCKERFILE" >&2
  exit 1
fi
export BROKER_DOCKERFILE CONTEXT_DOCKERFILE DISCOVERY_DOCKERFILE RASTER_DOCKERFILE TERRAIN_DOCKERFILE
case "$HEALTHCHECK_ATTEMPTS" in
  ''|0|*[!0-9]*) echo "HEALTHCHECK_ATTEMPTS must be a positive integer." >&2; exit 1 ;;
esac
case "$HEALTHCHECK_INTERVAL_SECONDS" in
  ''|0|*[!0-9]*) echo "HEALTHCHECK_INTERVAL_SECONDS must be a positive integer." >&2; exit 1 ;;
esac
case "$SKIP_BUILD" in
  0|1) ;;
  *) echo "SKIP_BUILD must be 0 or 1." >&2; exit 1 ;;
esac

LUMANEST_ROOT=$(canonical_dir "$LUMANEST_ROOT_INPUT") || {
  echo "LumaNest root does not exist: $LUMANEST_ROOT_INPUT" >&2
  exit 1
}
require_under_root "$RELEASE_DIR" "Release directory"

PREVIOUS_RELEASE_RAW=$(cat "$LUMANEST_ROOT/current-release" 2>/dev/null || true)
if [ -z "$PREVIOUS_RELEASE_RAW" ]; then
  PREVIOUS_RELEASE_RAW=$LIVE_DIR_INPUT
fi
if ! safe_single_line "$PREVIOUS_RELEASE_RAW"; then
  echo "Current release path must be a single line." >&2
  exit 1
fi
PREVIOUS_RELEASE=$(canonical_dir "$PREVIOUS_RELEASE_RAW") || {
  echo "Previous release does not exist: $PREVIOUS_RELEASE_RAW" >&2
  exit 1
}
require_under_root "$PREVIOUS_RELEASE" "Previous release"
if [ "$PREVIOUS_RELEASE" = "$RELEASE_DIR" ]; then
  echo "Deploy from a commit-isolated release directory, not the active release." >&2
  exit 1
fi

ENV_FILE=$RELEASE_DIR/qweather-token-broker.env
COMPOSE_FILE=$RELEASE_DIR/compose.yaml
BACKUP_DIR=$LUMANEST_ROOT/backups/$TIMESTAMP

require_file "$COMPOSE_FILE"
require_file "$RELEASE_DIR/$BROKER_DOCKERFILE"
require_file "$RELEASE_DIR/../lumanest-context-service/$CONTEXT_DOCKERFILE"
require_file "$RELEASE_DIR/../lumanest-raster-service/$RASTER_DOCKERFILE"
require_file "$RELEASE_DIR/../lumanest-terrain-service/$TERRAIN_DOCKERFILE"
# Older release fixtures have no Discovery service. A real release with the
# Discovery compose stanza is still validated by `compose config` below before
# the previous stack is stopped.
if [ -d "$RELEASE_DIR/../lumanest-discovery-service" ]; then
  require_file "$RELEASE_DIR/../lumanest-discovery-service/$DISCOVERY_DOCKERFILE"
fi
require_file "$PREVIOUS_RELEASE/compose.yaml"
require_file "$PREVIOUS_RELEASE/qweather-token-broker.env"

umask 077
if [ ! -f "$ENV_FILE" ]; then
  cp "$PREVIOUS_RELEASE/qweather-token-broker.env" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "Inherited the protected environment file from the previous release."
fi
require_file "$ENV_FILE"
ensure_outbound_network_environment

command -v docker >/dev/null
command -v curl >/dev/null
command -v grep >/dev/null
command -v tar >/dev/null
command -v awk >/dev/null
command -v od >/dev/null
command -v tr >/dev/null
if ! docker info >/dev/null 2>&1; then
  echo "The current user cannot access Docker. Add it to the docker group and start a new session." >&2
  exit 1
fi

# Validate interpolation and build contexts before stopping the running stack.
compose_release config --quiet
docker image inspect "$BACKUP_HELPER_IMAGE" >/dev/null 2>&1 || docker pull "$BACKUP_HELPER_IMAGE"

mkdir -p "$BACKUP_DIR/volumes"
BACKUP_DIR=$(canonical_dir "$BACKUP_DIR")
require_under_root "$BACKUP_DIR" "Backup directory"

# Archive the currently running application images before any service is stopped.
backup_application_images
validate_image_backup

manifest_tmp=$BACKUP_DIR/manifest.env.tmp.$$
{
  printf 'PROJECT_NAME=%s\n' "$PROJECT_NAME"
  printf 'LIVE_DIR=%s\n' "$PREVIOUS_RELEASE"
  printf 'RELEASE_DIR=%s\n' "$RELEASE_DIR"
  printf 'CREATED_AT=%s\n' "$TIMESTAMP"
} > "$manifest_tmp"
mv -f "$manifest_tmp" "$BACKUP_DIR/manifest.env"

previous_relative=${PREVIOUS_RELEASE#"$LUMANEST_ROOT"/}
tar -C "$LUMANEST_ROOT" -czf "$BACKUP_DIR/live-source.tar.gz" "$previous_relative"

trap deployment_failed EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

compose_previous stop

volumes_tmp=$BACKUP_DIR/volumes.txt.tmp.$$
docker volume ls \
  --filter "label=com.docker.compose.project=$PROJECT_NAME" \
  --format '{{.Name}}' > "$volumes_tmp"
mv -f "$volumes_tmp" "$BACKUP_DIR/volumes.txt"

while IFS= read -r volume; do
  [ -n "$volume" ] || continue
  if ! valid_identifier "$volume"; then
    echo "Unsafe Docker volume name: $volume" >&2
    exit 1
  fi
  backup_volume "$volume"
done < "$BACKUP_DIR/volumes.txt"
validate_volume_archives
BACKUP_COMPLETE=1

DATA_MAY_BE_CHANGED=1
if [ "$SKIP_BUILD" = 1 ]; then
  # Compose-only releases can reuse the already verified application images.
  # This is also the safe path when the NAS registry mirror is unavailable.
  compose_release up -d --no-build --remove-orphans
else
  compose_release up -d --build --remove-orphans
fi
verify_http_boundary '<title>栖光 · 管理台</title>'
compose_release exec -T context-service python -c \
  "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3)" >/dev/null
compose_release exec -T discovery-api python -c \
  "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8001/readyz', timeout=3)" >/dev/null
verify_release_discovery_worker
verify_release_service_health lumanest-raster-service
verify_release_service_health lumanest-terrain-service

# last-backup is written first; current-release is the final commit marker.
atomic_write "$LUMANEST_ROOT/last-backup" "$BACKUP_DIR"
atomic_write "$LUMANEST_ROOT/current-release" "$RELEASE_DIR"
trap - EXIT INT TERM

cleanup_backup_image_tags
compose_release ps
echo "Deployment completed."
echo "Backup: $BACKUP_DIR"
