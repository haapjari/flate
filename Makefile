DBG_MAKEFILE ?=
ifeq ($(DBG_MAKEFILE),1)
    $(warning ***** starting Makefile for goal(s) "$(MAKECMDGOALS)")
else
    MAKEFLAGS += -s
endif

SHELL := /usr/bin/env bash -o errexit -o pipefail -o nounset

MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --warn-undefined-variables

.SUFFIXES:

GO ?= $(shell if command -v go >/dev/null 2>&1; then command -v go; elif [ -x /usr/local/go/bin/go ]; then printf '/usr/local/go/bin/go'; else printf 'go'; fi)
GOFLAGS ?=

OUT_DIR := _output
TOOLS_DIR := $(OUT_DIR)/tools
HACK_DIR := hack

GOLANGCI_LINT_VERSION := v2.12.2
GOTESTSUM_VERSION := v1.13.0
GOIMPORTS_VERSION := v0.45.0
GOFUMPT_VERSION := v0.10.0
GOLINES_VERSION := v0.13.0
GOVULNCHECK_VERSION := v1.3.0
GO_MUTESTING_COMMIT := c0dfdf7b2d644d6c526de0952da05f5a89bcc8d5
GOCYCLO_VERSION := v0.6.0

COVERAGE_DIR := $(OUT_DIR)/coverage
COVERAGE_FILE := $(COVERAGE_DIR)/coverage.out
COVERAGE_HTML := $(COVERAGE_DIR)/coverage.html

# ============================================================================
# HELP TARGETS
# ============================================================================

.PHONY: all
all: verify

.PHONY: help
help:
	@echo "Commands"
	@echo ""
	@echo "Primary:"
	@echo "  all              - run verify (default)"
	@echo "  help             - show this help"
	@echo "  clean            - remove build artifacts"
	@echo ""
	@echo "Tests:"
	@echo "  test             - run tests"
	@echo "  test-race        - run tests with race detector"
	@echo "  test-race-cover-changed - run race tests and enforce changed-code coverage"
	@echo "  test-mutate-changed - run mutation tests on changed production Go files"
	@echo "  test-cover       - run tests with coverage report"
	@echo ""
	@echo "Verification:"
	@echo "  fmt              - format code"
	@echo "  lint-new         - run golangci-lint on new code"
	@echo "  lint-complexity-changed - enforce changed-code cyclomatic complexity"
	@echo "  verify           - run all verification checks"
	@echo "  verify-go-version - check go version is in sync"
	@echo "  verify-gofmt     - check code formatting"
	@echo "  verify-gomod     - check go.mod is tidy"
	@echo "  verify-vet       - run go vet"
	@echo "  verify-lint      - skip golangci-lint placeholder"
	@echo "  verify-govulncheck - run govulncheck (optional)"
	@echo "  verify-gitleaks  - scan git history and working tree for secrets"
	@echo ""
	@echo "Update:"
	@echo "  update           - run update-gofmt and update-gomod"
	@echo "  update-gofmt     - format code with gofmt and goimports"
	@echo "  update-gomod     - run go mod tidy"
	@echo ""
	@echo "Development:"
	@echo "  tools            - install development tools"
	@echo "  setup-hooks      - enable versioned git hooks from .githooks"
	@echo ""
	@echo "Variables:"
	@echo "  DBG_MAKEFILE=1   - show make debugging output"
	@echo "  GOFLAGS=...      - extra flags for go commands"

# ============================================================================
# TOOLS TARGETS
# ============================================================================

.PHONY: tools
tools: $(TOOLS_DIR)/golangci-lint \
	$(TOOLS_DIR)/gotestsum \
	$(TOOLS_DIR)/goimports \
	$(TOOLS_DIR)/go-mutesting \
	$(TOOLS_DIR)/gocyclo

$(TOOLS_DIR):
	mkdir -p $(TOOLS_DIR)

$(TOOLS_DIR)/govulncheck: Makefile | $(TOOLS_DIR)
	@echo "installing govulncheck $(GOVULNCHECK_VERSION)..."
	GOBIN=$(abspath $(TOOLS_DIR)) $(GO) install golang.org/x/vuln/cmd/govulncheck@$(GOVULNCHECK_VERSION)

$(TOOLS_DIR)/golangci-lint: Makefile | $(TOOLS_DIR)
	@echo "installing golangci-lint $(GOLANGCI_LINT_VERSION)..."
	GOBIN=$(abspath $(TOOLS_DIR)) $(GO) install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION)

$(TOOLS_DIR)/gotestsum: Makefile | $(TOOLS_DIR)
	@echo "installing gotestsum $(GOTESTSUM_VERSION)..."
	GOBIN=$(abspath $(TOOLS_DIR)) $(GO) install gotest.tools/gotestsum@$(GOTESTSUM_VERSION)

$(TOOLS_DIR)/goimports: Makefile | $(TOOLS_DIR)
	@echo "installing goimports $(GOIMPORTS_VERSION)..."
	GOBIN=$(abspath $(TOOLS_DIR)) $(GO) install golang.org/x/tools/cmd/goimports@$(GOIMPORTS_VERSION)

$(TOOLS_DIR)/gofumpt: Makefile | $(TOOLS_DIR)
	@echo "installing gofumpt $(GOFUMPT_VERSION)..."
	GOBIN=$(abspath $(TOOLS_DIR)) $(GO) install mvdan.cc/gofumpt@$(GOFUMPT_VERSION)

$(TOOLS_DIR)/golines: Makefile | $(TOOLS_DIR)
	@echo "installing golines $(GOLINES_VERSION)..."
	GOBIN=$(abspath $(TOOLS_DIR)) $(GO) install github.com/segmentio/golines@$(GOLINES_VERSION)

$(TOOLS_DIR)/go-mutesting: Makefile | $(TOOLS_DIR)
	@echo "installing go-mutesting $(GO_MUTESTING_COMMIT)..."
	tmp_dir="$$(mktemp -d)"; \
	trap 'rm -rf "$${tmp_dir}"' EXIT; \
	git clone --quiet https://github.com/haapjari/go-mutesting.git "$${tmp_dir}/go-mutesting"; \
	git -C "$${tmp_dir}/go-mutesting" checkout --quiet $(GO_MUTESTING_COMMIT); \
	GOBIN=$(abspath $(TOOLS_DIR)) $(GO) -C "$${tmp_dir}/go-mutesting" install ./cmd/go-mutesting

$(TOOLS_DIR)/gocyclo: Makefile | $(TOOLS_DIR)
	@echo "installing gocyclo $(GOCYCLO_VERSION)..."
	GOBIN=$(abspath $(TOOLS_DIR)) $(GO) install github.com/fzipp/gocyclo/cmd/gocyclo@$(GOCYCLO_VERSION)

# ============================================================================
# VERIFY TARGETS
# ============================================================================

.PHONY: verify
verify: verify-go-version \
	verify-gofmt \
	verify-gomod \
	verify-vet \
	verify-lint \
	test \
	test-race \
	test-cover \
	test-race-cover-changed \
	verify-govulncheck \
	verify-gitleaks \
	lint-complexity-changed
	@echo "all verification checks passed!"

.PHONY: verify-go-version
verify-go-version:
	@$(HACK_DIR)/verify-go-version.sh

.PHONY: verify-gofmt
verify-gofmt:
	@$(HACK_DIR)/verify-gofmt.sh

.PHONY: verify-gomod
verify-gomod:
	@$(HACK_DIR)/verify-gomod.sh

.PHONY: verify-vet
verify-vet:
	$(GO) vet ./pkg/flate/...

.PHONY: verify-govulncheck
verify-govulncheck: $(TOOLS_DIR)/govulncheck
	$(TOOLS_DIR)/govulncheck ./...

.PHONY: verify-gitleaks
verify-gitleaks:
	@$(HACK_DIR)/verify-gitleaks.sh

.PHONY: verify-lint
verify-lint:
	@echo "skipping golangci-lint for now..."

.PHONY: fmt
fmt: $(TOOLS_DIR)/goimports $(TOOLS_DIR)/gofumpt $(TOOLS_DIR)/golines
	@$(HACK_DIR)/fmt-new.sh

.PHONY: lint-new
lint-new: $(TOOLS_DIR)/golangci-lint
	@$(HACK_DIR)/lint-new.sh

.PHONY: lint-complexity-changed
lint-complexity-changed: $(TOOLS_DIR)/gocyclo
	@GOCYCLO="$(abspath $(TOOLS_DIR)/gocyclo)" $(HACK_DIR)/verify-changed-complexity.sh

# ============================================================================
# UPDATE TARGETS
# ============================================================================

.PHONY: update
update: update-gofmt update-gomod
	@echo "all updates complete!"

.PHONY: update-gofmt
update-gofmt: $(TOOLS_DIR)/goimports $(TOOLS_DIR)/gofumpt $(TOOLS_DIR)/golines
	@$(HACK_DIR)/update-gofmt.sh

.PHONY: update-gomod
update-gomod:
	@echo "running go mod tidy..."
	$(GO) mod tidy

# ============================================================================
# TEST TARGETS
# ============================================================================

.PHONY: test
test: $(TOOLS_DIR)/gotestsum
	@echo "running tests..."
	$(TOOLS_DIR)/gotestsum --format pkgname -- -count=1 ./pkg/flate/...

.PHONY: test-race
test-race: $(TOOLS_DIR)/gotestsum
	@echo "running tests with race detector..."
	$(TOOLS_DIR)/gotestsum --format pkgname -- -race -count=1 ./pkg/flate/...

.PHONY: test-race-cover-changed
test-race-cover-changed:
	@GO="$(GO)" $(HACK_DIR)/verify-changed-coverage.sh

.PHONY: test-mutate-changed
test-mutate-changed: $(TOOLS_DIR)/go-mutesting
	@GO="$(GO)" GO_MUTESTING="$(abspath $(TOOLS_DIR)/go-mutesting)" $(HACK_DIR)/verify-changed-mutations.sh

.PHONY: test-cover
test-cover: $(TOOLS_DIR)/gotestsum | $(COVERAGE_DIR)
	@echo "running tests with coverage..."
	$(TOOLS_DIR)/gotestsum --format pkgname -- -race -count=1 -coverprofile=$(COVERAGE_FILE) -covermode=atomic ./pkg/flate/...
	$(GO) tool cover -func=$(COVERAGE_FILE)
	$(GO) tool cover -html=$(COVERAGE_FILE) -o $(COVERAGE_HTML)
	@echo ""
	@echo "html report: $(COVERAGE_DIR)/coverage.html"

$(COVERAGE_DIR):
	mkdir -p $(COVERAGE_DIR)

# ============================================================================
# CLEANING TARGETS
# ============================================================================

.PHONY: setup-hooks
setup-hooks:
	@$(HACK_DIR)/setup-hooks.sh

.PHONY: clean
clean:
	@echo "cleaning build artifacts..."
	rm -rf $(OUT_DIR)
	$(GO) clean
