#!/usr/bin/env bash
# test/validate_release_ref_resolution.sh
# タグ push と手動実行でビルド対象 commit を正しく解決することを検証する。

set -euo pipefail

RELEASE_YML=".github/workflows/release.yml"
PASS=0
FAIL=0

assert_contains() {
  local expected="$1"
  local desc="$2"
  if grep -qF -- "$expected" "$RELEASE_YML"; then
    echo "  ✅ PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $desc (expected '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local unexpected="$1"
  local desc="$2"
  if ! grep -qF -- "$unexpected" "$RELEASE_YML"; then
    echo "  ✅ PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $desc (unexpected '$unexpected')"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Release Ref Resolution Tests ==="
echo ""

assert_contains "ref: \${{ github.sha }}" \
  "validate checks out the event commit"
assert_contains "EVENT_COMMIT_SHA: \${{ github.sha }}" \
  "tag event SHA is retained for release"
assert_contains "fetch-depth: 0" \
  "checkout fetches history required for ancestry verification"
assert_contains "- name: Verify event commit belongs to main" \
  "event commit ancestry verification step exists"
assert_contains 'git merge-base --is-ancestor "$EVENT_COMMIT_SHA" origin/main' \
  "event commit must be contained in trusted main"
assert_contains "ref: \${{ needs.validate.outputs.commit_sha }}" \
  "release job checks out the validated commit"
assert_contains "flutter-version: '3.47.1'" \
  "release jobs use the CI Flutter version"
assert_contains "java-version: '17'" \
  "release jobs use Java 17"

echo ""
echo "=== Release Action Pinning Tests ==="
echo ""

uses_count=0
while IFS= read -r line; do
  uses_count=$((uses_count + 1))
  if [[ "$line" =~ @[0-9a-f]{40}([[:space:]]|$) ]]; then
    echo "  ✅ PASS: action pinned: ${line#"${line%%[![:space:]]*}"}"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: action is not pinned to a full commit SHA: $line"
    FAIL=$((FAIL + 1))
  fi
done < <(grep -E '^[[:space:]]+uses:' "$RELEASE_YML")

if [[ $uses_count -gt 0 ]]; then
  echo "  ✅ PASS: inspected $uses_count action references"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: no action references found"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
