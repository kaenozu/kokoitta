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

echo "=== Workflow Security Tests ==="
echo ""

# 1. workflow_dispatch に ref 入力がない
#    workflow_dispatch セクション内に "ref:" があるか確認
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
if ! echo "$validate_section" | grep -q "ANDROID_KEYSTORE_BASE64"; then
  echo "  ✅ PASS: validate job has no ANDROID_KEYSTORE_BASE64"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: validate job should not have ANDROID_KEYSTORE_BASE64"
  FAIL=$((FAIL + 1))
fi
if ! echo "$validate_section" | grep -q "ANDROID_STORE_PASSWORD"; then
  echo "  ✅ PASS: validate job has no ANDROID_STORE_PASSWORD"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: validate job should not have ANDROID_STORE_PASSWORD"
  FAIL=$((FAIL + 1))
fi
if ! echo "$validate_section" | grep -q "ANDROID_KEY_ALIAS"; then
  echo "  ✅ PASS: validate job has no ANDROID_KEY_ALIAS"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: validate job should not have ANDROID_KEY_ALIAS"
  FAIL=$((FAIL + 1))
fi
if ! echo "$validate_section" | grep -q "ANDROID_KEY_PASSWORD"; then
  echo "  ✅ PASS: validate job has no ANDROID_KEY_PASSWORD"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: validate job should not have ANDROID_KEY_PASSWORD"
  FAIL=$((FAIL + 1))
fi

# 3. ワークフームレベルで contents: read（validate ジョブは明示的に write を持たない）
if grep -q "^permissions:" "$RELEASE_YML" && awk '/^permissions:/{flag=1; next} /^jobs:/{flag=0} flag' "$RELEASE_YML" | grep -q "contents: read"; then
  echo "  ✅ PASS: workflow has contents: read at top level"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: workflow should have contents: read at top level"
  FAIL=$((FAIL + 1))
fi

# 4. release ジョブの permissions が contents: write
release_section=$(awk '/^  release:/{flag=1; next} /^[a-z]/{flag=0} flag' "$RELEASE_YML")
if echo "$release_section" | grep -q "contents: write"; then
  echo "  ✅ PASS: release job has contents: write"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: release job should have contents: write"
  FAIL=$((FAIL + 1))
fi

# validate ジョブに contents: write がない
if ! echo "$validate_section" | grep -q "contents: write"; then
  echo "  ✅ PASS: validate job has no contents: write"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: validate job should not have contents: write"
  FAIL=$((FAIL + 1))
fi

# 5. shell injection 対策: run: ブロック内で github.ref_name / github.event.inputs.version を直接展開していない
#    validate ジョブの run: ブロックを抽出
validate_runs=$(echo "$validate_section" | awk '/^      run: \|/{flag=1; next} /^      - name:/{flag=0} flag')
if ! echo "$validate_runs" | grep -q 'github.ref_name'; then
  echo "  ✅ PASS: validate job run blocks have no direct github.ref_name"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: validate job run blocks should not directly expand github.ref_name"
  FAIL=$((FAIL + 1))
fi
if ! echo "$validate_runs" | grep -q 'github.event.inputs.version'; then
  echo "  ✅ PASS: validate job run blocks have no direct github.event.inputs.version"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: validate job run blocks should not directly expand github.event.inputs.version"
  FAIL=$((FAIL + 1))
fi

# env: 経由で受け渡していることを確認
if echo "$validate_section" | grep -q "INPUT_VERSION: \${{ github.event.inputs.version }}"; then
  echo "  ✅ PASS: version passed via env"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: version should be passed via env"
  FAIL=$((FAIL + 1))
fi
if echo "$validate_section" | grep -q "INPUT_TAG_NAME: \${{ github.ref_name }}"; then
  echo "  ✅ PASS: tag passed via env"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: tag should be passed via env"
  FAIL=$((FAIL + 1))
fi

# 6. cleanup ステップが存在し、if: always() を持つ
assert_contains "$RELEASE_YML" "Cleanup signing secrets" "cleanup step exists"
assert_contains "$RELEASE_YML" "if: always()" "cleanup step has if: always()"

# 7. validate ジョブが main から checkout している
assert_contains "$RELEASE_YML" "ref: main" "validate job checkouts trusted main ref"

# 8. target_commitish が validate ジョブの出力を使用
assert_contains "$RELEASE_YML" "target_commitish: \${{ needs.validate.outputs.commit_sha }}" "release uses validated commit SHA"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
