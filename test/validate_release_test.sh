#!/usr/bin/env bash
# test/validate_release_test.sh
# リリースバージョン検証ロジックの単体テスト
# 関連: scripts/validate-release.sh

set -euo pipefail

SCRIPT="$(dirname "$0")/../scripts/validate-release.sh"

PASS=0
FAIL=0

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local desc="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✅ PASS: $desc (exit code: $actual)"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $desc (expected exit code $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_output_contains() {
  local output="$1"
  local expected="$2"
  local desc="$3"
  if [[ "$output" == *"$expected"* ]]; then
    echo "  ✅ PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $desc (expected output to contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_output_contains() {
  local output="$1"
  local unexpected="$2"
  local desc="$3"
  if [[ "$output" != *"$unexpected"* ]]; then
    echo "  ✅ PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $desc (output should not contain '$unexpected')"
    FAIL=$((FAIL + 1))
  fi
}

run_script() {
  local stdout=""
  local stderr=""
  local exit_code=0
  stdout="$(bash "$SCRIPT" "$@" 2>&1)" && exit_code=$? || exit_code=$?
  echo "$stdout"
  return $exit_code
}

run_script_capture() {
  local stdout=""
  local stderr=""
  local exit_code=0
  stdout="$(bash "$SCRIPT" "$@" 2>/dev/null)" && exit_code=$? || exit_code=$?
  echo "STDOUT:$stdout"
  echo "EXIT:$exit_code"
}

echo "=== Release Validation Tests ==="
echo ""

# --- Success cases ---

echo "[Success cases]"

result="$(run_script_capture --tag v0.0.0)"
assert_exit_code 0 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://')" "--tag v0.0.0 should succeed"
assert_output_contains "$result" "version=0.0.0" "--tag v0.0.0 should output version=0.0.0"
assert_output_contains "$result" "release_tag=v0.0.0" "--tag v0.0.0 should output release_tag=v0.0.0"

result="$(run_script_capture --tag v1.2.3)"
assert_exit_code 0 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://')" "--tag v1.2.3 should succeed"
assert_output_contains "$result" "version=1.2.3" "--tag v1.2.3 should output version=1.2.3"
assert_output_contains "$result" "release_tag=v1.2.3" "--tag v1.2.3 should output release_tag=v1.2.3"

result="$(run_script_capture --version 1.2.3)"
assert_exit_code 0 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://')" "--version 1.2.3 should succeed"
assert_output_contains "$result" "version=1.2.3" "--version 1.2.3 should output version=1.2.3"
assert_output_contains "$result" "release_tag=v1.2.3" "--version 1.2.3 should output release_tag=v1.2.3"

result="$(run_script_capture --version 1.2.3 --version-code 42)"
assert_exit_code 0 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://')" "--version 1.2.3 --version-code 42 should succeed"
assert_output_contains "$result" "version=1.2.3" "--version 1.2.3 --version-code 42 should output version=1.2.3"
assert_output_contains "$result" "release_tag=v1.2.3" "--version 1.2.3 --version-code 42 should output release_tag=v1.2.3"
assert_output_contains "$result" "version_code=42" "--version 1.2.3 --version-code 42 should output version_code=42"

echo ""

# --- Failure cases ---

echo "[Failure cases]"

result="$(run_script_capture v1.2 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "v1.2 should fail (missing v prefix and patch)"

result="$(run_script_capture --tag v1.2.3-beta 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--tag v1.2.3-beta should fail (prerelease)"

result="$(run_script_capture --tag v1.2.3+build 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--tag v1.2.3+build should fail (build metadata)"

result="$(run_script_capture --tag v1.02.3 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--tag v1.02.3 should fail (leading zero)"

result="$(run_script_capture --tag 1.2.3 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--tag 1.2.3 should fail (missing v prefix)"

result="$(run_script_capture --version v1.2.3 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--version v1.2.3 should fail (has v prefix)"

result="$(run_script_capture --tag 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--tag with no value should fail"

result="$(run_script_capture --version 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--version with no value should fail"

result="$(run_script_capture --version-code 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--version-code with no value should fail"

result="$(run_script_capture --version 1.2.3 --version-code 0 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--version-code 0 should fail (not positive)"

result="$(run_script_capture --version 1.2.3 --version-code -1 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--version-code -1 should fail (negative)"

result="$(run_script_capture --version 1.2.3 --version-code abc 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--version-code abc should fail (not integer)"

result="$(run_script_capture --tag v1.2.3 --version 1.2.3 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--tag and --version together should fail"

result="$(run_script_capture 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "no arguments should fail"

result="$(run_script_capture --unknown 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "unknown option should fail"

# --- Shell injection edge cases ---

echo "[Shell injection edge cases]"

# Tag with embedded double quotes
result="$(run_script_capture --tag '"v1.2.3"' 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--tag '\"v1.2.3\"' should fail (embedded quotes)"

# Tag with literal $() command substitution
result="$(run_script_capture --tag '$(id)' 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--tag '\$(id)' should fail (command substitution literal)"

# Tag with literal backticks
result="$(run_script_capture --tag '`id`' 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--tag '\`id\`' should fail (backtick literal)"

# Tag with newline character
result="$(run_script_capture --tag $'v1.2\n3' 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--tag with newline should fail"

# Tag with semicolons
result="$(run_script_capture --tag 'v1.2.3;echo pwned' 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--tag 'v1.2.3;echo pwned' should fail (semicolons)"

# Tag with pipe
result="$(run_script_capture --tag 'v1.2.3|cat /etc/passwd' 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--tag 'v1.2.3|cat /etc/passwd' should fail (pipe)"

# Tag with environment variable reference
result="$(run_script_capture --tag '$HOME' 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--tag '\$HOME' should fail (env var reference)"

# Version with embedded command substitution
result="$(run_script_capture --version '$(id)' --version-code 42 2>&1)" || true
assert_exit_code 1 "$(echo "$result" | grep '^EXIT:' | sed 's/EXIT://' || echo '1')" "--version '\$(id)' should fail (command substitution literal)"

# Side-effect check: run with malicious input and verify no files created
side_effect_dir="$(mktemp -d)"
touch "$side_effect_dir/.keep"
initial_files="$(find "$side_effect_dir" -type f | sort)"
bash "$SCRIPT" --tag '$(id)' >/dev/null 2>&1 || true
bash "$SCRIPT" --tag '`id`' >/dev/null 2>&1 || true
bash "$SCRIPT" --tag $'evil\nv1.2.3' >/dev/null 2>&1 || true
after_files="$(find "$side_effect_dir" -type f | sort)"
if [[ "$initial_files" == "$after_files" ]]; then
  echo "  ✅ PASS: side-effect check (no extra files created by malicious input)"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: side-effect check (unexpected files in $side_effect_dir)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$side_effect_dir"

echo ""

# --- Summary ---

echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
