#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

cd "${REPO_ROOT}"

echo "setting up git hooks..."

git config core.hooksPath .githooks

echo "git hooks installed successfully!"
echo ""
echo "installed hooks (core.hooksPath=.githooks):"
echo "  - pre-commit: scans staged changes for secrets with gitleaks"
echo "  - pre-push: refuses direct pushes to main"
