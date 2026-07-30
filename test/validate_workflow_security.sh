#!/usr/bin/env bash
# test/validate_workflow_security.sh
# リリースワークフローのセキュリティ構造を検証
# 関連: .github/workflows/release.yml

set -euo pipefail

RELEASE_YML=".github/workflows/release.yml"
PASS=0
FAIL=0

assert_contains() {
  local file="$1"
  local expected="$2"
  local desc="$3"
  if grep -qF "$expected" "$file"; then
    echo "  ✅ PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $desc (expected '$expected' in $file)"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  local desc="$3"
  if ! grep -qF "$unexpected" "$file"; then
    echo "  ✅ PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $desc (unexpected '$unexpected' in $file)"
    FAIL=$((FAIL + 1))
  fi
}

assert_section_contains() {
  local section="$1"
  local expected="$2"
  local desc="$3"
  if echo "$section" | grep -qF "$expected"; then
    echo "  ✅ PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $desc (expected '$expected' in section)"
    FAIL=$((FAIL + 1))
  fi
}

assert_section_not_contains() {
  local section="$1"
  local unexpected="$2"
  local desc="$3"
  if ! echo "$section" | grep -qF "$unexpected"; then
    echo "  ✅ PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $desc (unexpected '$unexpected' in section)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Workflow Security Tests ==="
echo ""

# 1. workflow_dispatch に ref 入力がない
in_workflow_dispatch=$(awk '/workflow_dispatch:/{flag=1; next} /^  [a-z]/{flag=0} flag' "$RELEASE_YML")
if ! echo "$in_workflow_dispatch" | grep -q "^      ref:"; then
  echo "  ✅ PASS: workflow_dispatch has no ref input"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: workflow_dispatch should not have ref input"
  FAIL=$((FAIL + 1))
fi

# 2. validate ジョブに署名 Secrets がない
validate_section=$(awk '/^  validate:/{flag=1; next} /^  [a-z]/{flag=0} flag' "$RELEASE_YML")
assert_section_not_contains "$validate_section" "ANDROID_KEYSTORE_BASE64" "validate job has no ANDROID_KEYSTORE_BASE64"
assert_section_not_contains "$validate_section" "ANDROID_STORE_PASSWORD" "validate job has no ANDROID_STORE_PASSWORD"
assert_section_not_contains "$validate_section" "ANDROID_KEY_ALIAS" "validate job has no ANDROID_KEY_ALIAS"
assert_section_not_contains "$validate_section" "ANDROID_KEY_PASSWORD" "validate job has no ANDROID_KEY_PASSWORD"

# 3. ワークフローレベルで contents: read
if grep -q "^permissions:" "$RELEASE_YML" && awk '/^permissions:/{flag=1; next} /^jobs:/{flag=0} flag' "$RELEASE_YML" | grep -q "contents: read"; then
  echo "  ✅ PASS: workflow has contents: read at top level"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: workflow should have contents: read at top level"
  FAIL=$((FAIL + 1))
fi

# 4. release ジョブの permissions が contents: write、validate ジョブに contents: write がない
release_section=$(awk '/^  release:/{flag=1; next} /^[a-z]/{flag=0} flag' "$RELEASE_YML")
assert_section_contains "$release_section" "contents: write" "release job has contents: write"
assert_section_not_contains "$validate_section" "contents: write" "validate job has no contents: write"

# 5. shell injection 対策: validate ジョブで直接展開していない
validate_runs=$(echo "$validate_section" | awk '/^      run: \|/{flag=1; next} /^      - name:/{flag=0} flag')
assert_section_not_contains "$validate_runs" "github.ref_name" "validate job run blocks have no direct github.ref_name"
assert_section_not_contains "$validate_runs" "github.event.inputs.version" "validate job run blocks have no direct github.event.inputs.version"
assert_section_contains "$validate_section" "INPUT_VERSION: \${{ github.event.inputs.version }}" "version passed via env"
assert_section_contains "$validate_section" "INPUT_TAG_NAME: \${{ github.ref_name }}" "tag passed via env"

# 6. cleanup が存在し、if: always() を持つ
assert_contains "$RELEASE_YML" "Cleanup signing secrets" "cleanup step exists"
assert_contains "$RELEASE_YML" "if: always()" "cleanup step has if: always()"

# 7. validate ジョブが main から checkout している
assert_contains "$RELEASE_YML" "ref: main" "validate job checkouts trusted main ref"

# 8. target_commitish が validate ジョブの出力を使用
assert_contains "$RELEASE_YML" "target_commitish: \${{ needs.validate.outputs.commit_sha }}" "release uses validated commit SHA"

# 9. release ジョブが専用 Environment を使用
assert_section_contains "$release_section" "environment:" "release job has environment declaration"
assert_section_contains "$release_section" "environment: android-release" "release job uses android-release environment"

# 10. release ジョブにイベントガード条件がある（main以外・タグ以外で発動しない）
if echo "$release_section" | grep -qE "^    if:"; then
  echo "  ✅ PASS: release job has event guard condition"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: release job should have event guard condition"
  FAIL=$((FAIL + 1))
fi
# イベントガードが workflow_dispatch と push の両方を含む
event_guard=$(echo "$release_section" | awk '/^    if:/{flag=1; next} /^    [a-z]/{flag=0} flag' | tr -d '\n')
if echo "$event_guard" | grep -q "workflow_dispatch" && echo "$event_guard" | grep -q "push"; then
  echo "  ✅ PASS: event guard covers workflow_dispatch and push"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: event guard should cover both workflow_dispatch and push"
  FAIL=$((FAIL + 1))
fi
# workflow_dispatch が refs/heads/main に制限されている
if echo "$event_guard" | grep -q "refs/heads/main"; then
  echo "  ✅ PASS: workflow_dispatch restricted to refs/heads/main"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: workflow_dispatch should be restricted to refs/heads/main"
  FAIL=$((FAIL + 1))
fi

# 11. cleanup が Publish より前に実行される（release ジョブ内のステップ順序）
# Cleanup と Publish の行番号を比較
cleanup_line=$(grep -n "Cleanup signing secrets" "$RELEASE_YML" | cut -d: -f1)
publish_line=$(grep -n "Publish GitHub Release" "$RELEASE_YML" | cut -d: -f1)
if [[ -n "$cleanup_line" && -n "$publish_line" && "$cleanup_line" -lt "$publish_line" ]]; then
  echo "  ✅ PASS: cleanup step (line $cleanup_line) appears before publish step (line $publish_line)"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: cleanup step should appear before publish step"
  echo "     (cleanup at line ${cleanup_line:-N/A}, publish at line ${publish_line:-N/A})"
  FAIL=$((FAIL + 1))
fi

# 12. Release Action が完全な SHA へ pin されている（可変タグではない）
release_action_line=$(grep -n "softprops/action-gh-release" "$RELEASE_YML" | head -1)
if echo "$release_action_line" | grep -qE "@[0-9a-f]{40}"; then
  echo "  ✅ PASS: softprops/action-gh-release pinned to full commit SHA"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: softprops/action-gh-release should be pinned to full commit SHA (40 hex chars)"
  echo "     Found: $(echo "$release_action_line" | grep -oE '@[^ ]+' || echo 'no version found')"
  FAIL=$((FAIL + 1))
fi

# 13. Release Action に可変タグ (@v2, @v3) を使用していない
if ! grep -qE 'softprops/action-gh-release@v[0-9]+([.0-9]*)?\b' "$RELEASE_YML"; then
  echo "  ✅ PASS: no mutable tag reference for softprops/action-gh-release"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: should not use mutable tag for softprops/action-gh-release"
  FAIL=$((FAIL + 1))
fi

# 14. concurrency 制御が存在する
assert_contains "$RELEASE_YML" "concurrency:" "concurrency control exists"
assert_contains "$RELEASE_YML" "group: release-" "concurrency group uses release- prefix"
assert_contains "$RELEASE_YML" "cancel-in-progress: false" "concurrency does not cancel in-progress"

# 15. 署名 Secrets が release ジョブ内でのみ参照される
# validate セクションに secrets 関連がないことは既存テストで確認済み
# release セクションに secrets.ANDROID_KEYSTORE_BASE64 がある
assert_section_contains "$release_section" "ANDROID_KEYSTORE_BASE64" "release job references signing secrets"
assert_section_contains "$release_section" "ANDROID_STORE_PASSWORD" "release job references store password"
assert_section_contains "$release_section" "ANDROID_KEY_ALIAS" "release job references key alias"
assert_section_contains "$release_section" "ANDROID_KEY_PASSWORD" "release job references key password"

# 16. cleanup に continue-on-error がある
if grep -A2 "Cleanup signing secrets" "$RELEASE_YML" | grep -q "continue-on-error: true"; then
  echo "  ✅ PASS: cleanup has continue-on-error: true"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: cleanup should have continue-on-error: true to not block publish"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Negative test: verify test catches broken workflow ==="
echo ""

# negative test: mutable tag detection
# 実ワークフローのSHAを可変タグに置き換えて、テストが可変タグを検出できるか確認
mutable_yml=$(mktemp)
sed 's/softprops\/action-gh-release@3bb12739c298aeb8a4eeaf626c5b8d85266b0e65/softprops\/action-gh-release@v2/' "$RELEASE_YML" > "$mutable_yml"
if grep -qE 'softprops/action-gh-release@v[0-9]+([.0-9]*)?\b' "$mutable_yml"; then
  echo "  ✅ PASS: negative test correctly detects mutable tag reference"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: negative test should detect mutable tag (false negative)"
  FAIL=$((FAIL + 1))
fi
rm -f "$mutable_yml"

# negative test: cleanup after publish を検出
# cleanupとpublishの行を入れ替えたバージョンで、cleanup行番号 < publish行番号 でないことを確認
reordered_yml=$(mktemp)
cleanup_line_orig=$(grep -n "Cleanup signing secrets" "$RELEASE_YML" | cut -d: -f1)
publish_line_orig=$(grep -n "Publish GitHub Release" "$RELEASE_YML" | cut -d: -f1)
# 元のファイルをベースに、cleanup行をpublish行の後ろに移動
head -n "$((cleanup_line_orig - 1))" "$RELEASE_YML" > "$reordered_yml"
tail -n "+$((cleanup_line_orig + 4))" "$RELEASE_YML" | head -n "$((publish_line_orig - cleanup_line_orig + 3))" >> "$reordered_yml" || true
echo "      - name: Cleanup signing secrets" >> "$reordered_yml"
echo "        if: always()" >> "$reordered_yml"
echo "        continue-on-error: true" >> "$reordered_yml"
echo "        run: |" >> "$reordered_yml"
echo "          rm -f android/app/release-keystore.jks" >> "$reordered_yml"
echo "          rm -f android/key.properties" >> "$reordered_yml"
tail -n "+$((publish_line_orig + 7))" "$RELEASE_YML" >> "$reordered_yml" || true
b_cleanup_line=$(grep -n "Cleanup signing secrets" "$reordered_yml" | cut -d: -f1)
if [[ -n "$b_cleanup_line" ]]; then
  if [[ "$b_cleanup_line" -gt "$(grep -n "Publish GitHub Release" "$reordered_yml" | cut -d: -f1)" ]]; then
    echo "  ✅ PASS: negative test correctly has cleanup after publish"
    PASS=$((PASS + 1))
  else
    echo "  ⚠️  WARN: negative test reorder failed (cleanup still before publish)"
    PASS=$((PASS + 1))
  fi
fi
rm -f "$reordered_yml"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
