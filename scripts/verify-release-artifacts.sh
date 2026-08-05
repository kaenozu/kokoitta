#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: verify-release-artifacts.sh --apk FILE --aab FILE --version X.Y.Z \
  --version-code N --application-id PACKAGE
EOF
  exit 2
}

APK=""
AAB=""
EXPECTED_VERSION=""
EXPECTED_VERSION_CODE=""
EXPECTED_APPLICATION_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apk) APK="${2:-}"; shift 2 ;;
    --aab) AAB="${2:-}"; shift 2 ;;
    --version) EXPECTED_VERSION="${2:-}"; shift 2 ;;
    --version-code) EXPECTED_VERSION_CODE="${2:-}"; shift 2 ;;
    --application-id) EXPECTED_APPLICATION_ID="${2:-}"; shift 2 ;;
    *) echo "ERROR: unknown argument '$1'" >&2; usage ;;
  esac
done

[[ -n "$APK" && -n "$AAB" && -n "$EXPECTED_VERSION" && -n "$EXPECTED_VERSION_CODE" && -n "$EXPECTED_APPLICATION_ID" ]] || usage
[[ -f "$APK" ]] || { echo "ERROR: APK not found: $APK" >&2; exit 1; }
[[ -f "$AAB" ]] || { echo "ERROR: AAB not found: $AAB" >&2; exit 1; }
[[ "$EXPECTED_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo "ERROR: invalid version" >&2; exit 1; }
[[ "$EXPECTED_VERSION_CODE" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: invalid version code" >&2; exit 1; }
[[ "$EXPECTED_APPLICATION_ID" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$ ]] || { echo "ERROR: invalid application ID" >&2; exit 1; }

find_apkanalyzer() {
  if [[ -n "${APKANALYZER_BIN:-}" ]]; then
    printf '%s\n' "$APKANALYZER_BIN"
    return
  fi
  if command -v apkanalyzer >/dev/null 2>&1; then
    command -v apkanalyzer
    return
  fi
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  [[ -n "$sdk" ]] || return 1
  find "$sdk/cmdline-tools" -type f -path '*/bin/apkanalyzer' -print 2>/dev/null | sort -V | tail -n 1
}

APKANALYZER="$(find_apkanalyzer)"
[[ -n "$APKANALYZER" && -x "$APKANALYZER" ]] || { echo "ERROR: apkanalyzer not found" >&2; exit 1; }

normalize() {
  tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' | tail -n 1
}

assert_equal() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: $label mismatch: expected '$expected', got '$actual'" >&2
    exit 1
  fi
  echo "PASS: $label = $actual"
}

apk_application_id="$($APKANALYZER manifest application-id "$APK" | normalize)"
apk_version_name="$($APKANALYZER manifest version-name "$APK" | normalize)"
apk_version_code="$($APKANALYZER manifest version-code "$APK" | normalize)"

assert_equal "APK applicationId" "$EXPECTED_APPLICATION_ID" "$apk_application_id"
assert_equal "APK versionName" "$EXPECTED_VERSION" "$apk_version_name"
assert_equal "APK versionCode" "$EXPECTED_VERSION_CODE" "$apk_version_code"

read_bundle_attribute() {
  local xpath="$1"
  if [[ -n "${BUNDLE_DUMP_RUNNER:-}" ]]; then
    "$BUNDLE_DUMP_RUNNER" "$AAB" "$xpath" | normalize
  else
    ./android/gradlew -p android -q dumpReleaseBundleManifestAttribute \
      --no-daemon \
      -PbundleFile="$(realpath "$AAB")" \
      -PmanifestXpath="$xpath" | normalize
  fi
}

aab_application_id="$(read_bundle_attribute '/manifest/@package')"
aab_version_name="$(read_bundle_attribute '/manifest/@android:versionName')"
aab_version_code="$(read_bundle_attribute '/manifest/@android:versionCode')"

assert_equal "AAB applicationId" "$EXPECTED_APPLICATION_ID" "$aab_application_id"
assert_equal "AAB versionName" "$EXPECTED_VERSION" "$aab_version_name"
assert_equal "AAB versionCode" "$EXPECTED_VERSION_CODE" "$aab_version_code"

apk_sha256="$(sha256sum "$APK" | awk '{print $1}')"
aab_sha256="$(sha256sum "$AAB" | awk '{print $1}')"
echo "APK SHA-256: $apk_sha256"
echo "AAB SHA-256: $aab_sha256"
