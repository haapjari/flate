#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

readonly COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-80.0}"
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly GO_CMD="${GO:-go}"
readonly COVERAGE_BASE_REF="${COVERAGE_BASE_REF:-origin/main}"

TMP_DIR=""

main() {
	cd "${REPO_ROOT}"

	require_go

	local -a changed_files
	mapfile -t changed_files < <(changed_production_go_files)

	if [[ ${#changed_files[@]} -eq 0 ]]; then
		echo "no changed production Go files for coverage check"
		return 0
	fi

	local module
	module="$("${GO_CMD}" list -m)"

	TMP_DIR="$(mktemp -d)"
	trap cleanup EXIT

	local cover_profile="${TMP_DIR}/coverage.out"

	echo "running race-enabled coverage for changed production Go files..."
	"${GO_CMD}" test \
		--race \
		-count=1 \
		-covermode=atomic \
		-coverpkg=./pkg/flate \
		-coverprofile="${cover_profile}" \
		./pkg/flate

	check_coverage "${module}" "${cover_profile}" "${changed_files[@]}"
}

cleanup() {
	if [[ -n "${TMP_DIR}" ]]; then
		rm -rf "${TMP_DIR}"
	fi
}

require_go() {
	if [[ ! -x "${GO_CMD}" ]] && ! command -v "${GO_CMD}" >/dev/null 2>&1; then
		echo "error: Go toolchain not found: ${GO_CMD}" >&2
		return 1
	fi
}

changed_production_go_files() {
	{
		changed_since_base
		git diff --name-only --diff-filter=ACMR -- '*.go' ':!**/*_test.go'
		git diff --cached --name-only --diff-filter=ACMR -- '*.go' ':!**/*_test.go'
		git ls-files --others --exclude-standard -- '*.go' |
			grep -Ev '(^|/)[^/]+_test\.go$' || true
	} | sort -u
}

changed_since_base() {
	local base_commit
	if ! base_commit="$(base_commit)"; then
		return 0
	fi

	git diff --name-only --diff-filter=ACMR "${base_commit}" -- '*.go' ':!**/*_test.go'
}

base_commit() {
	if ! git rev-parse --verify "${COVERAGE_BASE_REF}^{commit}" >/dev/null 2>&1; then
		return 1
	fi

	git merge-base "${COVERAGE_BASE_REF}" HEAD 2>/dev/null ||
		git rev-parse "${COVERAGE_BASE_REF}^{commit}"
}

check_coverage() {
	local module="$1"
	local cover_profile="$2"
	shift 2

	local covered
	local total

	read -r covered total < <(
		awk -v module="${module}" '
			BEGIN {
				for (i = 1; i < ARGC - 1; i++) {
					files[ARGV[i]] = 1
					ARGV[i] = ""
				}
			}
			FNR == 1 {
				next
			}
			{
				split($1, pos, ":")
				file = pos[1]
				prefix = module "/"
				if (index(file, prefix) == 1) {
					file = substr(file, length(prefix) + 1)
				}
				if (!(file in files)) {
					next
				}
				statements += $2
				if ($3 > 0) {
					covered += $2
				}
			}
			END {
				printf "%d %d\n", covered, statements
			}
		' "$@" "${cover_profile}"
	)

	if [[ "${total}" == "0" ]]; then
		echo "changed production Go files contain no coverable statements"
		return 0
	fi

	local percent
	percent="$(awk -v covered="${covered}" -v total="${total}" 'BEGIN { printf "%.1f", (covered / total) * 100 }')"

	echo "changed production Go coverage: ${percent}% (${covered}/${total} statements)"

	awk -v percent="${percent}" -v threshold="${COVERAGE_THRESHOLD}" 'BEGIN { exit(percent + 0 < threshold + 0) }' || {
		echo "error: changed production Go coverage ${percent}% is below ${COVERAGE_THRESHOLD}%" >&2
		return 1
	}
}

main "$@"
