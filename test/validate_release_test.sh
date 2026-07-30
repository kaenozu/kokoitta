# test/validate_release_test.sh
# リリースバージョン検証ロジックの単体テスト
# 関連: scripts/validate-release.sh, .github/workflows/release.yml

set -euo pipefail

SEMVER_TAG='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
SEMVER='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

PASS=0
FAIL=0

assert_tag() {
  local tag="$1"
  if [[ "$tag" =~ $SEMVER_TAG ]]; then
    echo "  ✅ PASS: tag='$tag'"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: tag='$tag' should be valid"
    FAIL=$((FAIL + 1))
  fi
}

refute_tag() {
  local tag="$1"
  if [[ "$tag" =~ $SEMVER_TAG ]]; then
    echo "  ❌ FAIL: tag='$tag' should be invalid"
    FAIL=$((FAIL + 1))
  else
    echo "  ✅ PASS: tag='$tag'"
    PASS=$((PASS + 1))
  fi
}

assert_version() {
  local ver="$1"
  if [[ "$ver" =~ $SEMVER ]]; then
    echo "  ✅ PASS: version='$ver'"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: version='$ver' should be valid"
    FAIL=$((FAIL + 1))
  fi
}

refute_version() {
  local ver="$1"
  if [[ "$ver" =~ $SEMVER ]]; then
    echo "  ❌ FAIL: version='$ver' should be invalid"
    FAIL=$((FAIL + 1))
  else
    echo "  ✅ PASS: version='$ver'"
    PASS=$((PASS + 1))
  fi
}

# === TAG tests ===

echo "[Tag validation]"

assert_tag "v0.0.0"
assert_tag "v1.2.3"
assert_tag "v10.200.3000"
assert_tag "v0.0.1"
assert_tag "v1.0.0"

refute_tag "1.2.3"
refute_tag "v1.2"
refute_tag "v1.2.3.4"
refute_tag "v1.2.3-beta"
refute_tag "v1.2.3+build"
refute_tag "v1.02.3"
refute_tag "v.1.2.3"
refute_tag "vv1.2.3"
refute_tag "v1.2.3-"
refute_tag ""
refute_tag "v"
refute_tag "v1.2.3."

# === Version tests ===

echo "[Version validation]"

assert_version "0.0.0"
assert_version "1.2.3"
assert_version "10.200.3000"
assert_version "0.0.1"
assert_version "1.0.0"

refute_version "v1.2.3"
refute_version "1.2"
refute_version "1.2.3.4"
refute_version "1.2.3-beta"
refute_version "1.2.3+build"
refute_version "1.02.3"
refute_version ".1.2.3"
refute_version ""
refute_version "1"
refute_version "1.2.3."

# === Version extraction ===

echo "[Version extraction]"

extract() {
  local tag="$1"
  echo "${tag#v}"
}

assert_extract() {
  local tag="$1"
  local expected="$2"
  local actual
  actual=$(extract "$tag")
  if [[ "$actual" == "$expected" ]]; then
    echo "  ✅ PASS: '$tag' -> '$actual'"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: '$tag' -> '$actual' (expected '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_extract "v1.2.3" "1.2.3"
assert_extract "v0.0.1" "0.0.1"
assert_extract "v10.200.3000" "10.200.3000"

# === Summary ===

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
