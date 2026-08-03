#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
MODE=${1:-write}
EXCLUDE_NEWER=2026-07-30T00:00:00Z

case "$MODE" in
  write) ;;
  --check) ;;
  *) echo "Usage: $0 [--check]" >&2; exit 2 ;;
esac

command -v uv >/dev/null 2>&1 || {
  echo "uv is required to compile Python runtime locks." >&2
  exit 1
}

TEMP_DIR=
if [ "$MODE" = "--check" ]; then
  TEMP_DIR=$(mktemp -d)
  trap 'rm -rf -- "$TEMP_DIR"' EXIT INT TERM
fi

status=0
for service in \
  lumanest-context-service \
  lumanest-discovery-service \
  lumanest-raster-service \
  lumanest-terrain-service
do
  service_dir=$ROOT_DIR/services/$service
  output=$service_dir/requirements.prod.txt
  if [ "$MODE" = "--check" ]; then
    generated=$TEMP_DIR/$service.txt
  else
    generated=$output
  fi

  (
    cd "$service_dir"
    uv pip compile \
      pyproject.toml \
      requirements.prod.in \
      --python-version 3.12 \
      --python-platform x86_64-manylinux_2_28 \
      --only-binary :all: \
      --generate-hashes \
      --exclude-newer "$EXCLUDE_NEWER" \
      --output-file "$generated" \
      --custom-compile-command '../../../tool/compile_python_runtime_locks.sh' \
      --quiet
  )

  if [ "$MODE" = "--check" ] && ! cmp -s "$generated" "$output"; then
    echo "Python runtime lock is stale: $output" >&2
    status=1
  fi
done

if [ "$status" -ne 0 ]; then
  echo "Run ./tool/compile_python_runtime_locks.sh and review the lock changes." >&2
  exit "$status"
fi
