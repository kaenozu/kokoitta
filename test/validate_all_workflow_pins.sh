#!/usr/bin/env bash
# Fail closed when any third-party GitHub Action in any workflow uses a mutable ref.

set -euo pipefail

mapfile -t workflows < <(find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print | sort)
if [[ ${#workflows[@]} -eq 0 ]]; then
  echo 'No workflow files found.' >&2
  exit 1
fi

failures=0
for workflow in "${workflows[@]}"; do
  while IFS= read -r line; do
    # Local actions (./...) do not have remote mutable refs.
    if [[ "$line" =~ uses:[[:space:]]*\./ ]]; then
      continue
    fi
    if [[ ! "$line" =~ @[0-9a-f]{40}([[:space:]#]|$) ]]; then
      echo "unpinned action: $workflow: $line" >&2
      failures=$((failures + 1))
    fi
  done < <(grep -E '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*[^[:space:]]+' "$workflow" || true)
done

if [[ $failures -ne 0 ]]; then
  echo "$failures unpinned action reference(s) found." >&2
  exit 1
fi

echo "All GitHub Actions are pinned to full commit SHAs across ${#workflows[@]} workflow files."
