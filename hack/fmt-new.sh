#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TOOLS_DIR="${REPO_ROOT}/_output/tools"

cd "${REPO_ROOT}"

mapfile -t changed_files < <(
	git diff --name-only --diff-filter=ACMR -- '*.go'
)
mapfile -t untracked_files < <(
	git ls-files --others --exclude-standard -- '*.go'
)

files=("${changed_files[@]}" "${untracked_files[@]}")

if [[ ${#files[@]} -eq 0 ]]; then
	echo "no changed Go files to format"
	exit 0
fi

echo "formatting changed Go files..."

gofmt -w -s "${files[@]}"

if [[ -x "${TOOLS_DIR}/goimports" ]]; then
	"${TOOLS_DIR}/goimports" -w -local github.com/haapjari/flate "${files[@]}"
fi

if [[ -x "${TOOLS_DIR}/gofumpt" ]]; then
	"${TOOLS_DIR}/gofumpt" -w -extra "${files[@]}"
fi

if [[ -x "${TOOLS_DIR}/golines" ]]; then
	"${TOOLS_DIR}/golines" -w --max-len=80 "${files[@]}"
fi

echo "formatting complete!"
