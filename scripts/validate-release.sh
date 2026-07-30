# scripts/validate-release.sh
# リリースバージョン・タグの入力検証
# タグ起動: validate-release.sh --tag v1.2.3
# 手動起動: validate-release.sh --version 1.2.3 --version-code 42
# 関連: .github/workflows/release.yml, test/validate_release_test.sh

set -euo pipefail

SEMVER_TAG='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
SEMVER='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

usage() {
  echo "Usage: $0 --tag <vX.Y.Z> | --version <X.Y.Z> [--version-code <N>]" >&2
  exit 1
}

TAG=""
VERSION=""
VERSION_CODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --version-code)
      VERSION_CODE="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -n "$TAG" ]]; then
  if [[ ! "$TAG" =~ $SEMVER_TAG ]]; then
    echo "ERROR: Invalid tag format '$TAG' (expected vX.Y.Z, e.g. v1.2.3)" >&2
    exit 1
  fi
  VERSION="${TAG#v}"
  echo "version=$VERSION"
  echo "release_tag=$TAG"
elif [[ -n "$VERSION" ]]; then
  if [[ ! "$VERSION" =~ $SEMVER ]]; then
    echo "ERROR: Invalid version format '$VERSION' (expected X.Y.Z, e.g. 1.2.3)" >&2
    exit 1
  fi
  echo "version=$VERSION"
  echo "release_tag=v$VERSION"
else
  usage
fi

if [[ -n "$VERSION_CODE" ]]; then
  echo "version_code=$VERSION_CODE"
fi
