#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

cd "${REPO_ROOT}"

echo "checking for secrets with gitleaks..."

if ! command -v gitleaks > /dev/null 2>&1; then
    echo "ERROR: gitleaks is not installed" >&2
    echo "" >&2
    echo "Run 'go install github.com/zricethezav/gitleaks/v8@latest' to install it." >&2
    exit 1
fi

gitleaks git --log-opts="--all" --no-banner --redact
gitleaks dir . --no-banner --redact

echo "gitleaks check passed!"
