#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TOOLS_DIR="${REPO_ROOT}/_output/tools"

cd "${REPO_ROOT}"

patch_file="$(mktemp)"
trap 'rm -f "${patch_file}"' EXIT

git diff --no-ext-diff --relative --diff-filter=ACMR -- '*.go' >"${patch_file}"

while IFS= read -r file; do
	git diff --no-ext-diff --relative --no-index /dev/null "${file}" >>"${patch_file}" || true
done < <(git ls-files --others --exclude-standard -- '*.go')

if [[ ! -s "${patch_file}" ]]; then
	echo "no changed Go files to lint"
	exit 0
fi

"${TOOLS_DIR}/golangci-lint" run --new-from-patch="${patch_file}" --timeout 5m ./pkg/flate/...
