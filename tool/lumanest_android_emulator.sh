#!/usr/bin/env bash

set -euo pipefail

SDK_ROOT=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-"$HOME/Library/Android/sdk"}}
AVD_NAME=${LUMANEST_AVD_NAME:-LumaNest_API35}
SYSTEM_IMAGE=${LUMANEST_AVD_IMAGE:-system-images;android-35;google_apis;arm64-v8a}
DEVICE_PROFILE=${LUMANEST_AVD_DEVICE:-pixel_6}
TEST_LATITUDE=${LUMANEST_TEST_LATITUDE:-30.525}
TEST_LONGITUDE=${LUMANEST_TEST_LONGITUDE:-120.681}
PACKAGE_NAME=com.muee.lumanest

EMULATOR="$SDK_ROOT/emulator/emulator"
ADB="$SDK_ROOT/platform-tools/adb"
AVDMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/avdmanager"
AVD_ROOT=${ANDROID_AVD_HOME:-"$HOME/.android/avd"}
AVD_CONFIG="$AVD_ROOT/$AVD_NAME.avd/config.ini"
EMULATOR_LOG="$AVD_ROOT/$AVD_NAME.emulator.log"
LAUNCH_LABEL=com.muee.lumanest.emulator.api35
PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_executable() {
  [[ -x "$1" ]] || fail "required Android SDK tool is missing: $1"
}

set_ini_value() {
  local key=$1
  local value=$2
  local temporary

  temporary=$(mktemp "$AVD_CONFIG.XXXXXX")
  awk -v key="$key" -v value="$value" '
    BEGIN { found = 0 }
    {
      current = $0
      sub(/[[:space:]]*=.*/, "", current)
      gsub(/[[:space:]]/, "", current)
      if (current == key) {
        print key " = " value
        found = 1
      } else {
        print $0
      }
    }
    END {
      if (!found) {
        print key " = " value
      }
    }
  ' "$AVD_CONFIG" > "$temporary"
  mv "$temporary" "$AVD_CONFIG"
}

configure_avd() {
  [[ -f "$AVD_CONFIG" ]] || fail "AVD config is missing: $AVD_CONFIG"

  # AMap uses a native GLTextureView. On Apple Silicon the emulator host GLES
  # backend can fail EGL context creation (12288), so pin ANGLE + SwiftShader.
  # Extra memory avoids System UI ANRs during Flutter startup.
  set_ini_value hw.gpu.enabled yes
  set_ini_value hw.gpu.mode swangle
  set_ini_value hw.ramSize 4096M
  set_ini_value vm.heapSize 512M
  set_ini_value hw.cpu.ncore 4
  set_ini_value disk.dataPartition.size 12G
  set_ini_value hw.audioInput no
  set_ini_value hw.audioOutput no
  set_ini_value hw.camera.back none
  set_ini_value hw.camera.front none
  set_ini_value hw.keyboard yes
  set_ini_value showDeviceFrame no
  set_ini_value fastboot.forceColdBoot yes
  set_ini_value fastboot.forceFastBoot no
  set_ini_value firstboot.bootFromDownloadableSnapshot no
  set_ini_value firstboot.bootFromLocalSnapshot no
  set_ini_value firstboot.saveToLocalSnapshot no
}

create_avd() {
  require_executable "$AVDMANAGER"
  require_executable "$EMULATOR"

  if [[ ! -d "$AVD_ROOT/$AVD_NAME.avd" ]]; then
    printf 'no\n' | "$AVDMANAGER" create avd \
      --force \
      --name "$AVD_NAME" \
      --package "$SYSTEM_IMAGE" \
      --device "$DEVICE_PROFILE"
  fi

  configure_avd
  printf 'configured %s (%s)\n' "$AVD_NAME" "$SYSTEM_IMAGE"
}

running_serial() {
  local serial
  local running_name

  while read -r serial _; do
    [[ "$serial" == emulator-* ]] || continue
    running_name=$("$ADB" -s "$serial" emu avd name 2>/dev/null | head -n 1 | tr -d '\r')
    if [[ "$running_name" == "$AVD_NAME" ]]; then
      printf '%s\n' "$serial"
      return 0
    fi
  done < <("$ADB" devices)
  return 1
}

wait_for_boot() {
  local deadline=$((SECONDS + 180))
  local serial

  while ((SECONDS < deadline)); do
    serial=$(running_serial || true)
    if [[ -n "$serial" ]] && \
      [[ $("$ADB" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') == 1 ]]; then
      printf '%s\n' "$serial"
      return 0
    fi
    sleep 2
  done
  fail "$AVD_NAME did not finish booting within 180 seconds; inspect $EMULATOR_LOG"
}

prepare_device() {
  local serial=$1

  "$ADB" -s "$serial" shell settings put global window_animation_scale 0
  "$ADB" -s "$serial" shell settings put global transition_animation_scale 0
  "$ADB" -s "$serial" shell settings put global animator_duration_scale 0
  "$ADB" -s "$serial" shell settings put system font_scale 1.0
  "$ADB" -s "$serial" shell settings put system system_locales zh-CN
  "$ADB" -s "$serial" shell settings put global time_zone Asia/Shanghai
  "$ADB" -s "$serial" shell cmd location set-location-enabled true
  "$ADB" -s "$serial" emu geo fix "$TEST_LONGITUDE" "$TEST_LATITUDE" >/dev/null
}

start_avd() {
  local serial
  local -a emulator_arguments=(
    -avd "$AVD_NAME"
    -gpu swangle
    -memory 4096
    -no-audio
    -no-boot-anim
    -no-snapshot
  )

  require_executable "$ADB"
  require_executable "$EMULATOR"
  create_avd

  serial=$(running_serial || true)
  if [[ -z "$serial" ]]; then
    if [[ $(uname -s) == Darwin ]]; then
      launchctl remove "$LAUNCH_LABEL" >/dev/null 2>&1 || true
      launchctl submit \
        -l "$LAUNCH_LABEL" \
        -o "$EMULATOR_LOG" \
        -e "$EMULATOR_LOG" \
        -- "$EMULATOR" "${emulator_arguments[@]}"
    else
      nohup "$EMULATOR" "${emulator_arguments[@]}" >"$EMULATOR_LOG" 2>&1 &
    fi
    serial=$(wait_for_boot)
  fi

  prepare_device "$serial"
  printf 'ready %s serial=%s location=%s,%s\n' \
    "$AVD_NAME" "$serial" "$TEST_LATITUDE" "$TEST_LONGITUDE"
}

install_app() {
  local serial
  local apk="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-debug.apk"

  serial=$(running_serial || true)
  [[ -n "$serial" ]] || fail "$AVD_NAME is not running; run '$0 start' first"

  (
    cd "$PROJECT_ROOT"
    ./tool/flutter_with_environment.sh build apk --debug
  )
  "$ADB" -s "$serial" install -r -t "$apk"
  "$ADB" -s "$serial" shell pm grant "$PACKAGE_NAME" android.permission.ACCESS_FINE_LOCATION || true
  "$ADB" -s "$serial" shell pm grant "$PACKAGE_NAME" android.permission.ACCESS_COARSE_LOCATION || true
  "$ADB" -s "$serial" shell pm grant "$PACKAGE_NAME" android.permission.POST_NOTIFICATIONS || true
  "$ADB" -s "$serial" emu geo fix "$TEST_LONGITUDE" "$TEST_LATITUDE" >/dev/null
  printf 'installed %s on %s\n' "$PACKAGE_NAME" "$serial"
}

smoke_test() {
  local serial
  local pid=''
  local deadline=$((SECONDS + 60))
  local crash_log

  serial=$(running_serial || true)
  [[ -n "$serial" ]] || fail "$AVD_NAME is not running; run '$0 start' first"
  "$ADB" -s "$serial" shell pm path "$PACKAGE_NAME" >/dev/null \
    || fail "$PACKAGE_NAME is not installed; run '$0 install' first"

  "$ADB" -s "$serial" shell am force-stop "$PACKAGE_NAME"
  "$ADB" -s "$serial" logcat -c
  "$ADB" -s "$serial" shell am start -W -n "$PACKAGE_NAME/.MainActivity" >/dev/null

  while ((SECONDS < deadline)); do
    pid=$("$ADB" -s "$serial" shell pidof "$PACKAGE_NAME" 2>/dev/null | tr -d '\r')
    [[ -n "$pid" ]] && break
    sleep 1
  done
  [[ -n "$pid" ]] || fail "$PACKAGE_NAME did not start within 60 seconds"

  sleep 12
  crash_log=$("$ADB" -s "$serial" logcat -d -v brief | \
    grep -E 'FATAL EXCEPTION|createContext failed|ANR in com\.muee\.lumanest|E/flutter' || true)
  [[ -z "$crash_log" ]] || fail "runtime crash detected:\n$crash_log"

  printf 'smoke test passed serial=%s pid=%s\n' "$serial" "$pid"
}

show_status() {
  local serial

  serial=$(running_serial || true)
  if [[ -z "$serial" ]]; then
    printf '%s is stopped\n' "$AVD_NAME"
    return 0
  fi

  printf 'avd=%s serial=%s api=%s boot=%s appPid=%s\n' \
    "$AVD_NAME" \
    "$serial" \
    "$("$ADB" -s "$serial" shell getprop ro.build.version.sdk | tr -d '\r')" \
    "$("$ADB" -s "$serial" shell getprop sys.boot_completed | tr -d '\r')" \
    "$("$ADB" -s "$serial" shell pidof "$PACKAGE_NAME" 2>/dev/null | tr -d '\r')"
}

stop_avd() {
  local serial

  serial=$(running_serial || true)
  if [[ -n "$serial" ]]; then
    "$ADB" -s "$serial" emu kill >/dev/null
  fi
  if [[ $(uname -s) == Darwin ]]; then
    launchctl remove "$LAUNCH_LABEL" >/dev/null 2>&1 || true
  fi
  printf 'stopped %s\n' "$AVD_NAME"
}

usage() {
  printf 'Usage: %s {create|start|install|smoke|status|stop}\n' "$0"
}

case ${1:-} in
  create) create_avd ;;
  start) start_avd ;;
  install) install_app ;;
  smoke) smoke_test ;;
  status) show_status ;;
  stop) stop_avd ;;
  *) usage; exit 2 ;;
esac
