#!/usr/bin/env bash
# scripts/validate-release.sh
# リリースバージョン・タグの入力検証
# タグ起動: validate-release.sh --tag vX.Y.Z
# 手動起動: validate-release.sh --version X.Y.Z [--version-code N]
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
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --tag requires a value" >&2
        exit 1
      fi
      TAG="$2"
      shift 2
      ;;
    --version)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --version requires a value" >&2
        exit 1
      fi
      VERSION="$2"
      shift 2
      ;;
    --version-code)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --version-code requires a value" >&2
        exit 1
      fi
      VERSION_CODE="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown argument '$1'" >&2
      usage
      ;;
  esac
done

if [[ -n "$TAG" && -n "$VERSION" ]]; then
  echo "ERROR: --tag and --version are mutually exclusive" >&2
  exit 1
fi

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
  if [[ ! "$VERSION_CODE" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: Invalid version-code '$VERSION_CODE' (expected a positive integer)" >&2
    exit 1
  fi
  echo "version_code=$VERSION_CODE"
fi
