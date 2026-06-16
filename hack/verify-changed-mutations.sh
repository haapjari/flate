#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly GO_CMD="${GO:-go}"
readonly MUTATION_BASE_REF="${MUTATION_BASE_REF:-origin/main}"
readonly MUTATION_TIMEOUT="${MUTATION_TIMEOUT:-30}"
readonly GO_MUTESTING="${GO_MUTESTING:-${REPO_ROOT}/_output/tools/go-mutesting}"
readonly REPORT_FILE="${REPO_ROOT}/report.json"

main() {
	cd "${REPO_ROOT}"

	require_go
	require_go_mutesting

	local -a changed_files
	mapfile -t changed_files < <(changed_production_go_files)

	if [[ ${#changed_files[@]} -eq 0 ]]; then
		echo "no changed production Go files for mutation check"
		return 0
	fi

	rm -f "${REPORT_FILE}" "${REPO_ROOT}/go-mutesting-report.html"
	trap 'rm -f "${REPORT_FILE}" "${REPO_ROOT}/go-mutesting-report.html"' EXIT

	echo "running mutation tests for changed production Go files..."
	GOFLAGS="${GOFLAGS:-} -count=1" \
		"${GO_MUTESTING}" \
		--exec-timeout="${MUTATION_TIMEOUT}" \
		"${changed_files[@]}"

	check_report
}

require_go() {
	if [[ -x "${GO_CMD}" ]]; then
		PATH="$(dirname "${GO_CMD}"):${PATH}"
		export PATH
		return 0
	fi

	if ! command -v "${GO_CMD}" >/dev/null 2>&1; then
		echo "error: Go toolchain not found: ${GO_CMD}" >&2
		return 1
	fi
}

require_go_mutesting() {
	if [[ ! -x "${GO_MUTESTING}" ]]; then
		echo "error: go-mutesting not found: ${GO_MUTESTING}" >&2
		return 1
	fi
}

changed_production_go_files() {
	{
		changed_since_base
		git diff --name-only --diff-filter=ACMR -- '*.go' ':!**/*_test.go'
		git diff --cached --name-only --diff-filter=ACMR -- '*.go' ':!**/*_test.go'
		git ls-files --others --exclude-standard -- '*.go' ':!**/*_test.go'
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
	if ! git rev-parse --verify "${MUTATION_BASE_REF}^{commit}" >/dev/null 2>&1; then
		return 1
	fi

	git merge-base "${MUTATION_BASE_REF}" HEAD 2>/dev/null ||
		git rev-parse "${MUTATION_BASE_REF}^{commit}"
}

check_report() {
	if [[ ! -f "${REPORT_FILE}" ]]; then
		echo "error: go-mutesting did not write ${REPORT_FILE}" >&2
		return 1
	fi

	local total_count
	local escaped_count
	local error_count
	local timeout_count
	total_count="$(json_count totalMutantsCount)"
	escaped_count="$(json_count escapedCount)"
	error_count="$(json_count errorCount)"
	timeout_count="$(json_count timeOutCount)"

	echo "changed production Go mutants: ${total_count} total, ${escaped_count} escaped"

	if ((escaped_count > 0)); then
		echo "error: ${escaped_count} viable mutants survived" >&2
		return 1
	fi

	if ((error_count > 0 || timeout_count > 0)); then
		echo "error: mutation run had ${error_count} errors and ${timeout_count} timeouts" >&2
		return 1
	fi
}

json_count() {
	local name="$1"
	local count
	count="$(
		awk -v name="\"${name}\"" '
			{
				pattern = name "[[:space:]]*:[[:space:]]*[0-9]+"
				if (match($0, pattern)) {
					value = substr($0, RSTART, RLENGTH)
					sub(/^.*:/, "", value)
					gsub(/[^0-9]/, "", value)
					print value
					found = 1
					exit
				}
				END {
					if (!found) {
						exit 1
					}
				}
			' "${REPORT_FILE}"
	)" || {
		echo "error: ${name} missing from ${REPORT_FILE}" >&2
		return 1
	}

	printf '%s\n' "${count}"
}

main "$@"
