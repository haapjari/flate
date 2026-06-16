#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

readonly COMPLEXITY_THRESHOLD="${COMPLEXITY_THRESHOLD:-10}"
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly COMPLEXITY_BASE_REF="${COMPLEXITY_BASE_REF:-origin/main}"
readonly GOCYCLO="${GOCYCLO:-${REPO_ROOT}/_output/tools/gocyclo}"
readonly GO_CMD="${GO:-go}"

TMP_DIR=""

main() {
	cd "${REPO_ROOT}"

	require_go
	require_gocyclo
	TMP_DIR="$(mktemp -d)"
	trap cleanup EXIT

	local -a changed_files
	mapfile -t changed_files < <(changed_production_go_files)

	if [[ ${#changed_files[@]} -eq 0 ]]; then
		echo "no changed production Go files for complexity check"
		return 0
	fi

	local base
	base="$(base_commit || true)"

	local changed_ranges_file="${TMP_DIR}/changed-ranges.tsv"
	local function_ranges_file="${TMP_DIR}/function-ranges.tsv"
	local changed_functions_file="${TMP_DIR}/changed-functions.tsv"
	local failures_file="${TMP_DIR}/complexity-failures.txt"

	write_changed_ranges "${base}" "${changed_ranges_file}" "${changed_files[@]}"
	write_function_ranges "${function_ranges_file}" "${changed_files[@]}"
	write_changed_functions \
		"${changed_ranges_file}" \
		"${function_ranges_file}" \
		"${changed_functions_file}"

	if [[ ! -s "${changed_functions_file}" ]]; then
		echo "no changed Go functions for complexity check"
		return 0
	fi

	echo "checking changed Go function complexity..."
	write_complexity_failures \
		"${changed_functions_file}" \
		"${failures_file}" \
		"${changed_files[@]}"

	if [[ -s "${failures_file}" ]]; then
		echo "error: changed Go functions exceed complexity threshold ${COMPLEXITY_THRESHOLD}" >&2
		cat "${failures_file}" >&2
		return 1
	fi

	echo "changed Go function complexity is within threshold ${COMPLEXITY_THRESHOLD}"
}

cleanup() {
	if [[ -n "${TMP_DIR}" ]]; then
		rm -rf "${TMP_DIR}"
	fi
}

require_go() {
	if [[ -x "${GO_CMD}" ]]; then
		return 0
	fi

	if ! command -v "${GO_CMD}" >/dev/null 2>&1; then
		echo "error: Go toolchain not found: ${GO_CMD}" >&2
		return 1
	fi
}

require_gocyclo() {
	if [[ ! -x "${GOCYCLO}" ]]; then
		echo "error: gocyclo not found: ${GOCYCLO}" >&2
		return 1
	fi
}

write_changed_ranges() {
	local base="$1"
	local output_file="$2"
	shift 2

	: >"${output_file}"

	local file
	for file in "$@"; do
		changed_line_ranges "${base}" "${file}" |
			awk -v file="${file}" '{ print file "\t" $1 "\t" $2 }' >>"${output_file}"
	done
}

changed_line_ranges() {
	local base="$1"
	local file="$2"

	if is_untracked_file "${file}"; then
		printf '1 2147483647\n'
		return 0
	fi

	if [[ -n "${base}" ]]; then
		git diff --unified=0 --diff-filter=ACMR "${base}" -- "${file}" |
			diff_hunk_line_ranges
		return 0
	fi

	{
		git diff --unified=0 --diff-filter=ACMR -- "${file}"
		git diff --cached --unified=0 --diff-filter=ACMR -- "${file}"
	} | diff_hunk_line_ranges
}

is_untracked_file() {
	local file="$1"

	git ls-files --others --exclude-standard -- "${file}" |
		awk -v file="${file}" '
			$0 == file { found = 1 }
			END { exit found ? 0 : 1 }
		'
}

diff_hunk_line_ranges() {
	awk '
		/^@@ / {
			if (match($0, /\+[0-9]+(,[0-9]+)?/)) {
				range = substr($0, RSTART + 1, RLENGTH - 1)
				split(range, parts, ",")
				start = parts[1] + 0
				count = parts[2] == "" ? 1 : parts[2] + 0
				if (start == 0) {
					start = 1
				}
				end = count == 0 ? start : start + count - 1
				print start, end
			}
		}
	'
}

write_function_ranges() {
	local output_file="$1"
	shift

	local parser_bin
	parser_bin="$(build_function_ranges_tool)"
	"${parser_bin}" "$@" >"${output_file}"
}

build_function_ranges_tool() {
	local parser_file="${TMP_DIR}/go-function-ranges.go"
	local parser_bin="${TMP_DIR}/go-function-ranges"

	write_function_ranges_source "${parser_file}"
	"${GO_CMD}" build -o "${parser_bin}" "${parser_file}"
	printf '%s\n' "${parser_bin}"
}

write_function_ranges_source() {
	local parser_file="$1"

	cat >"${parser_file}" <<'EOF'
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/printer"
	"go/token"
	"os"
	"strings"
)

func main() {
	for _, path := range os.Args[1:] {
		if err := printFunctionRanges(path); err != nil {
			fmt.Fprintf(os.Stderr, "%v\n", err)
			os.Exit(1)
		}
	}
}

func printFunctionRanges(path string) error {
	fileSet := token.NewFileSet()
	file, err := parser.ParseFile(fileSet, path, nil, 0)
	if err != nil {
		return fmt.Errorf("parse %s: %w", path, err)
	}

	for _, declaration := range file.Decls {
		function, ok := declaration.(*ast.FuncDecl)
		if !ok {
			continue
		}

		fmt.Printf(
			"%s\t%s\t%d\t%d\n",
			path,
			functionName(function),
			fileSet.Position(function.Pos()).Line,
			fileSet.Position(function.End()).Line,
		)
	}

	return nil
}

func functionName(function *ast.FuncDecl) string {
	if function.Recv == nil || len(function.Recv.List) == 0 {
		return function.Name.Name
	}

	return "(" + receiverType(function.Recv.List[0].Type) + ")." + function.Name.Name
}

func receiverType(expression ast.Expr) string {
	var builder strings.Builder
	if err := printer.Fprint(&builder, token.NewFileSet(), expression); err != nil {
		return ""
	}
	return builder.String()
}
EOF
}

write_changed_functions() {
	local changed_ranges_file="$1"
	local function_ranges_file="$2"
	local output_file="$3"

	awk -F '\t' '
		NR == FNR {
			file = $1
			range_count[file]++
			range_start[file, range_count[file]] = $2
			range_end[file, range_count[file]] = $3
			next
		}
		{
			file = $1
			name = $2
			function_start = $3 + 0
			function_end = $4 + 0
			for (i = 1; i <= range_count[file]; i++) {
				start = range_start[file, i] + 0
				end = range_end[file, i] + 0
				if (start <= function_end && function_start <= end) {
					print file "\t" name
					next
				}
			}
		}
	' "${changed_ranges_file}" "${function_ranges_file}" |
		sort -u >"${output_file}"
}

write_complexity_failures() {
	local changed_functions_file="$1"
	local output_file="$2"
	shift 2

	local complexity_output
	local gocyclo_status=0
	complexity_output="$("${GOCYCLO}" -over "${COMPLEXITY_THRESHOLD}" "$@" 2>&1)" || gocyclo_status=$?
	if ((gocyclo_status > 1)); then
		printf '%s\n' "${complexity_output}" >&2
		return "${gocyclo_status}"
	fi

	printf '%s\n' "${complexity_output}" |
		awk '
			BEGIN { FS = "[[:space:]]+" }
			NR == FNR {
				changed[$1 "\t" $2] = 1
				next
			}
			NF == 0 { next }
			{
				function_name = $3
				location = $4
				file = location
				sub(/:[^:]*$/, "", file)
				sub(/:[^:]*$/, "", file)
				if ((file "\t" function_name) in changed) {
					print $0
				}
			}
		' "${changed_functions_file}" - >"${output_file}"
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
	if ! git rev-parse --verify "${COMPLEXITY_BASE_REF}^{commit}" >/dev/null 2>&1; then
		return 1
	fi

	git merge-base "${COMPLEXITY_BASE_REF}" HEAD 2>/dev/null ||
		git rev-parse "${COMPLEXITY_BASE_REF}^{commit}"
}

main "$@"
