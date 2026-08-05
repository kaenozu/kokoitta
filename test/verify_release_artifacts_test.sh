#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/verify-release-artifacts.sh"
RELEASE_YML="$ROOT/.github/workflows/release.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

touch "$TMP/app.apk" "$TMP/app.aab"

cat > "$TMP/apkanalyzer" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  application-id) echo "${FAKE_APK_APPLICATION_ID:-com.kaenozu.kokoitta_app}" ;;
  version-name) echo "${FAKE_APK_VERSION_NAME:-1.2.3}" ;;
  version-code) echo "${FAKE_APK_VERSION_CODE:-42}" ;;
  *) exit 3 ;;
esac
EOF
chmod +x "$TMP/apkanalyzer"

cat > "$TMP/bundle-dump" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  /manifest/@package) echo "${FAKE_AAB_APPLICATION_ID:-com.kaenozu.kokoitta_app}" ;;
  /manifest/@android:versionName) echo "${FAKE_AAB_VERSION_NAME:-1.2.3}" ;;
  /manifest/@android:versionCode) echo "${FAKE_AAB_VERSION_CODE:-42}" ;;
  *) exit 4 ;;
esac
EOF
chmod +x "$TMP/bundle-dump"

PASS=0
FAIL=0
pass() {
  echo "PASS: $1"
  PASS=$((PASS + 1))
}
fail() {
  echo "FAIL: $1"
  FAIL=$((FAIL + 1))
}
run_case() {
  local name="$1" expected="$2"
  shift 2
  set +e
  "$@" >/dev/null 2>&1
  local actual=$?
  set -e
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name expected $expected got $actual"
  fi
}

base=(env APKANALYZER_BIN="$TMP/apkanalyzer" BUNDLE_DUMP_RUNNER="$TMP/bundle-dump" bash "$SCRIPT" --apk "$TMP/app.apk" --aab "$TMP/app.aab" --version 1.2.3 --version-code 42 --application-id com.kaenozu.kokoitta_app)
run_case success 0 "${base[@]}"
run_case apk-version-mismatch 1 env FAKE_APK_VERSION_NAME=9.9.9 "${base[@]}"
run_case aab-package-mismatch 1 env FAKE_AAB_APPLICATION_ID=com.example.wrong "${base[@]}"
run_case invalid-version 1 env APKANALYZER_BIN="$TMP/apkanalyzer" BUNDLE_DUMP_RUNNER="$TMP/bundle-dump" bash "$SCRIPT" --apk "$TMP/app.apk" --aab "$TMP/app.aab" --version v1.2.3 --version-code 42 --application-id com.kaenozu.kokoitta_app
run_case missing-apk 1 env APKANALYZER_BIN="$TMP/apkanalyzer" BUNDLE_DUMP_RUNNER="$TMP/bundle-dump" bash "$SCRIPT" --apk "$TMP/missing.apk" --aab "$TMP/app.aab" --version 1.2.3 --version-code 42 --application-id com.kaenozu.kokoitta_app

verify_line="$(grep -nF 'Verify APK and AAB metadata' "$RELEASE_YML" | cut -d: -f1)"
cleanup_line="$(grep -nF 'Cleanup signing secrets' "$RELEASE_YML" | cut -d: -f1)"
publish_line="$(grep -nF 'Publish GitHub Release' "$RELEASE_YML" | cut -d: -f1)"
if [[ -n "$verify_line" && -n "$cleanup_line" && -n "$publish_line" && "$verify_line" -lt "$cleanup_line" && "$cleanup_line" -lt "$publish_line" ]]; then
  pass "artifact verification occurs before cleanup and publish"
else
  fail "artifact verification order is unsafe"
fi

grep -qF 'bash scripts/verify-release-artifacts.sh' "$RELEASE_YML" \
  && pass "release invokes artifact verifier" \
  || fail "release does not invoke artifact verifier"
grep -qF 'EXPECTED_APPLICATION_ID: com.kaenozu.kokoitta_app' "$RELEASE_YML" \
  && pass "release pins expected application ID" \
  || fail "release application ID contract missing"

printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
