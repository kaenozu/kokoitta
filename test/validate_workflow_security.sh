#!/usr/bin/env bash
# test/validate_workflow_security.sh
# リリースワークフローの信頼境界と Secrets 取扱いを構造検証する。

set -euo pipefail

RELEASE_YML=".github/workflows/release.yml"
PASS=0
FAIL=0

pass() {
  echo "  ✅ PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ❌ FAIL: $1"
  FAIL=$((FAIL + 1))
}

assert_contains() {
  local file="$1"
  local expected="$2"
  local desc="$3"
  if grep -qF -- "$expected" "$file"; then
    pass "$desc"
  else
    fail "$desc (expected '$expected')"
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  local desc="$3"
  if ! grep -qF -- "$unexpected" "$file"; then
    pass "$desc"
  else
    fail "$desc (unexpected '$unexpected')"
  fi
}

assert_section_contains() {
  local section="$1"
  local expected="$2"
  local desc="$3"
  if grep -qF -- "$expected" <<<"$section"; then
    pass "$desc"
  else
    fail "$desc (expected '$expected')"
  fi
}

assert_section_not_contains() {
  local section="$1"
  local unexpected="$2"
  local desc="$3"
  if ! grep -qF -- "$unexpected" <<<"$section"; then
    pass "$desc"
  else
    fail "$desc (unexpected '$unexpected')"
  fi
}

workflow_dispatch_section=$(awk '/^  workflow_dispatch:/{flag=1; next} /^[a-z]/{flag=0} flag' "$RELEASE_YML")
validate_section=$(awk '/^  validate:/{flag=1; next} /^  release:/{flag=0} flag' "$RELEASE_YML")
release_section=$(awk '/^  release:/{flag=1; next} flag' "$RELEASE_YML")
validate_runs=$(awk '/^  validate:/{in_validate=1} /^  release:/{in_validate=0} in_validate && /^        run: \|/{in_run=1; next} in_validate && /^      - name:/{in_run=0} in_validate && in_run' "$RELEASE_YML")

echo "=== Workflow Security Tests ==="
echo ""

assert_section_not_contains "$workflow_dispatch_section" "      ref:" \
  "workflow_dispatch has no custom ref input"

for secret in \
  ANDROID_KEYSTORE_BASE64 \
  ANDROID_STORE_PASSWORD \
  ANDROID_KEY_ALIAS \
  ANDROID_KEY_PASSWORD; do
  assert_section_not_contains "$validate_section" "$secret" \
    "validate job has no $secret"
done

workflow_permissions=$(awk '/^permissions:/{flag=1; next} /^jobs:/{flag=0} flag' "$RELEASE_YML")
assert_section_contains "$workflow_permissions" "contents: read" \
  "workflow defaults to contents: read"
assert_section_contains "$release_section" "contents: write" \
  "release job alone receives contents: write"
assert_section_not_contains "$validate_section" "contents: write" \
  "validate job has no contents: write"

assert_section_contains "$validate_section" 'INPUT_VERSION: ${{ github.event.inputs.version }}' \
  "version input is passed through env"
assert_section_contains "$validate_section" 'INPUT_TAG_NAME: ${{ github.ref_name }}' \
  "tag name is passed through env"
assert_section_not_contains "$validate_runs" "github.ref_name" \
  "run blocks do not directly expand github.ref_name"
assert_section_not_contains "$validate_runs" "github.event.inputs.version" \
  "run blocks do not directly expand workflow input"
assert_section_contains "$validate_section" \
  "ref: \${{ github.event_name == 'push' && github.sha || 'main' }}" \
  "tag push uses github.sha and manual execution uses main"
assert_section_contains "$validate_section" "fetch-depth: 0" \
  "validate checkout includes history for ancestry check"
assert_section_contains "$validate_section" "Verify tagged commit belongs to main" \
  "tag ancestry check exists"
assert_section_contains "$validate_section" \
  'git merge-base --is-ancestor "$COMMIT_SHA" "origin/main"' \
  "tag commit must be contained in main"

assert_section_contains "$release_section" "environment: android-release" \
  "release job uses android-release Environment"
assert_section_contains "$release_section" "github.ref == 'refs/heads/main'" \
  "manual release is restricted to main"
assert_section_contains "$release_section" "startsWith(github.ref, 'refs/tags/v')" \
  "tag release is restricted to v* refs"
assert_section_contains "$release_section" \
  'ref: ${{ needs.validate.outputs.commit_sha }}' \
  "release checks out the validated commit"
assert_section_contains "$release_section" \
  'target_commitish: ${{ needs.validate.outputs.commit_sha }}' \
  "Release tag targets the validated commit"

assert_section_contains "$release_section" "Cleanup signing secrets" \
  "cleanup step exists"
assert_section_contains "$release_section" "if: always()" \
  "cleanup runs on failure paths"
assert_section_contains "$release_section" "continue-on-error: true" \
  "cleanup failure cannot block cleanup flow"
assert_section_contains "$release_section" "rm -f android/app/release-keystore.jks" \
  "cleanup removes keystore"
assert_section_contains "$release_section" "rm -f android/key.properties" \
  "cleanup removes key.properties"

cleanup_line=$(grep -nF "Cleanup signing secrets" "$RELEASE_YML" | cut -d: -f1)
publish_line=$(grep -nF "Publish GitHub Release" "$RELEASE_YML" | cut -d: -f1)
if [[ -n "$cleanup_line" && -n "$publish_line" && "$cleanup_line" -lt "$publish_line" ]]; then
  pass "cleanup occurs before third-party publish action"
else
  fail "cleanup must occur before publish"
fi

unpinned_actions=0
while IFS= read -r line; do
  if [[ ! "$line" =~ @[0-9a-f]{40}([[:space:]]|$) ]]; then
    echo "     unpinned: $line"
    unpinned_actions=$((unpinned_actions + 1))
  fi
done < <(grep -E '^[[:space:]]+uses:' "$RELEASE_YML")
if [[ $unpinned_actions -eq 0 ]]; then
  pass "all release workflow actions are pinned to full commit SHAs"
else
  fail "$unpinned_actions action reference(s) are not fully pinned"
fi

assert_contains "$RELEASE_YML" "concurrency:" \
  "workflow has concurrency control"
assert_contains "$RELEASE_YML" "group: release-" \
  "concurrency is scoped by release tag/version"
assert_contains "$RELEASE_YML" "cancel-in-progress: false" \
  "in-progress releases are not cancelled"

for secret in \
  ANDROID_KEYSTORE_BASE64 \
  ANDROID_STORE_PASSWORD \
  ANDROID_KEY_ALIAS \
  ANDROID_KEY_PASSWORD; do
  assert_section_contains "$release_section" "$secret" \
    "release job references $secret"
done

assert_section_contains "$validate_section" "scripts/validate-release.sh" \
  "workflow uses the production release validator"
assert_section_contains "$validate_section" "gh release view" \
  "existing Release is checked before build"
assert_section_contains "$validate_section" 'refs/tags/$TAG^{}' \
  "existing tag peeled commit is checked"
assert_section_contains "$release_section" "kokoitta_app-*.apk" \
  "APK is attached to GitHub Release"
assert_section_contains "$release_section" "kokoitta_app-*.aab" \
  "AAB is attached to GitHub Release"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
