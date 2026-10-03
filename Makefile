.DEFAULT_GOAL := help
SHELL := /bin/bash

PACKAGE := Packages/SqueegeeKit
LINT_PATHS := $(wildcard Packages App ManualTestApp)

# SwiftLint is pinned to an exact version. Homebrew cannot pin a formula version
# in a Brewfile, so a brew-installed SwiftLint drifts between machines and CI —
# and different versions disagree about which rules fire (e.g. force_unwrapping).
# We vendor the pinned portable binary under .tools/ and every target invokes
# $(SWIFTLINT) instead of whatever happens to be on PATH. Bump the version here
# (and the SHA below) to upgrade; the version is in the path so it re-downloads.
SWIFTLINT_VERSION := 0.63.3
SWIFTLINT_SHA256  := fb045e85e7cb3374f42a4840b6b85a0106302afa69035c0c6f29af4a44c810b6
TOOLS_DIR := .tools
SWIFTLINT_DIR := $(TOOLS_DIR)/swiftlint-$(SWIFTLINT_VERSION)
SWIFTLINT := $(SWIFTLINT_DIR)/swiftlint

# SwiftFormat is pinned for the same reason as SwiftLint above: an unpinned brew
# install drifts between machines and CI, and newer versions turn on new default
# rules that would silently reformat the whole codebase. We vendor the pinned
# binary under .tools/ and invoke $(SWIFTFORMAT) everywhere.
SWIFTFORMAT_VERSION := 0.61.1
SWIFTFORMAT_SHA256  := b990400779aceb7d7020796eb9ba814d4480543f671d38fc0ff48cb72f04c584
SWIFTFORMAT_DIR := $(TOOLS_DIR)/swiftformat-$(SWIFTFORMAT_VERSION)
SWIFTFORMAT := $(SWIFTFORMAT_DIR)/swiftformat

.PHONY: help bootstrap generate build test lint format precommit-checks build-app profile-app bench bench-profile run-app run-manual-tests hooks ci manual-tests-check release clean

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-22s\033[0m %s\n",$$1,$$2}'

bootstrap: $(SWIFTLINT) $(SWIFTFORMAT) ## Install dev tools via Homebrew + pinned SwiftLint/SwiftFormat
	@command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
	brew bundle --file=Brewfile

$(SWIFTLINT):
	@echo "==> Fetching pinned SwiftLint $(SWIFTLINT_VERSION)"
	@mkdir -p "$(SWIFTLINT_DIR)"
	@curl -fL --retry 3 -o "$(SWIFTLINT_DIR)/portable_swiftlint.zip" \
	  "https://github.com/realm/SwiftLint/releases/download/$(SWIFTLINT_VERSION)/portable_swiftlint.zip"
	@if [ -n "$(SWIFTLINT_SHA256)" ]; then \
	  echo "$(SWIFTLINT_SHA256)  $(SWIFTLINT_DIR)/portable_swiftlint.zip" | shasum -a 256 -c - ; \
	else \
	  echo "WARNING: SWIFTLINT_SHA256 is unset — skipping integrity check"; \
	fi
	@cd "$(SWIFTLINT_DIR)" && unzip -o -q portable_swiftlint.zip
	@chmod +x "$(SWIFTLINT)"
	@touch "$(SWIFTLINT)"

$(SWIFTFORMAT):
	@echo "==> Fetching pinned SwiftFormat $(SWIFTFORMAT_VERSION)"
	@mkdir -p "$(SWIFTFORMAT_DIR)"
	@curl -fL --retry 3 -o "$(SWIFTFORMAT_DIR)/swiftformat.zip" \
	  "https://github.com/nicklockwood/SwiftFormat/releases/download/$(SWIFTFORMAT_VERSION)/swiftformat.zip"
	@if [ -n "$(SWIFTFORMAT_SHA256)" ]; then \
	  echo "$(SWIFTFORMAT_SHA256)  $(SWIFTFORMAT_DIR)/swiftformat.zip" | shasum -a 256 -c - ; \
	else \
	  echo "WARNING: SWIFTFORMAT_SHA256 is unset — skipping integrity check"; \
	fi
	@cd "$(SWIFTFORMAT_DIR)" && unzip -o -q swiftformat.zip
	@chmod +x "$(SWIFTFORMAT)"
	@touch "$(SWIFTFORMAT)"

generate: ## Generate Xcode projects from project.yml files
	cd App && xcodegen generate
	cd ManualTestApp && xcodegen generate

SWIFT_STRICT := -Xswiftc -warnings-as-errors

build: ## Build the SPM package
	swift build --package-path $(PACKAGE) $(SWIFT_STRICT)

test: ## GATING: run package tests
	@echo "==> Testing $(PACKAGE)"; \
	swift test --no-parallel --package-path $(PACKAGE) 2>&1 \
	  | grep -E 'recorded an issue|with [0-9]+ issue|Test run with [0-9]|Executed [0-9]+ test|: error:|error generated|no such module|cannot find|Build complete!' ; \
	rc=$${PIPESTATUS[0]}; [ $$rc -eq 0 ] || exit $$rc

lint: $(SWIFTLINT) $(SWIFTFORMAT) ## Check formatting + lint (non-mutating)
	$(SWIFTFORMAT) $(LINT_PATHS) --lint --quiet --cache ignore
	$(SWIFTLINT) lint --strict --quiet --no-cache $(LINT_PATHS)

format: $(SWIFTLINT) $(SWIFTFORMAT) ## Auto-format then autofix lint
	$(SWIFTFORMAT) $(LINT_PATHS) --quiet --cache ignore
	$(SWIFTLINT) lint --fix --quiet --no-cache $(LINT_PATHS)

precommit-checks: ## The pre-commit checks (format + lint + test); the hook and hooks-mcp both call this
	$(MAKE) format
	$(MAKE) lint
	$(MAKE) test

build-app: generate ## NON-GATING: build both apps via xcodebuild (ad-hoc)
	cd App && xcodebuild -quiet -project Squeegee.xcodeproj -scheme Squeegee \
	  -destination 'platform=macOS,arch=arm64' \
	  -configuration Debug CODE_SIGNING_ALLOWED=YES \
	  CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" build
	cd ManualTestApp && xcodebuild -quiet -project ManualTestApp.xcodeproj -scheme ManualTestApp \
	  -destination 'platform=macOS,arch=arm64' \
	  -configuration Debug CODE_SIGNING_ALLOWED=YES \
	  CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" build

PROFILE_DIR := build/profile

profile-app: generate ## Build a symbolicated Release app (Developer ID) for profiling
	cd App && xcodebuild -quiet -project Squeegee.xcodeproj -scheme Squeegee \
	  -destination 'platform=macOS,arch=arm64' \
	  -configuration Release \
	  -derivedDataPath ../$(PROFILE_DIR)/DerivedData build

bench: ## Run the deterministic perf-bench benchmark (release)
	swift run -c release --package-path $(PACKAGE) perf-bench

bench-profile: ## Build + profile perf-bench; requires LABEL=<name>
	scripts/profile/bench_profile.sh $(LABEL)

run-app: generate ## Build + run the app with Apple Development signing
	cd App && xcodebuild -quiet -project Squeegee.xcodeproj -scheme Squeegee \
	  -destination 'platform=macOS,arch=arm64' \
	  -configuration Debug \
	  -derivedDataPath build/DerivedData build
	open App/build/DerivedData/Build/Products/Debug/Squeegee.app

run-manual-tests: generate ## Build + run ManualTestApp with Apple Development signing
	cd ManualTestApp && xcodebuild -quiet -project ManualTestApp.xcodeproj -scheme ManualTestApp \
	  -destination 'platform=macOS,arch=arm64' \
	  -configuration Debug \
	  -derivedDataPath build/DerivedData build
	open ManualTestApp/build/DerivedData/Build/Products/Debug/ManualTestApp.app

hooks: ## Enable the opt-in pre-commit hook
	git config core.hooksPath .githooks
	@echo "Pre-commit hook enabled (.githooks)."

ci: lint test build ## What the gating CI job runs

manual-tests-check: ## Check that all manual test step IDs have been run
	swift run --package-path $(PACKAGE) manual-tests-check ManualTestApp/Results/manual_test_results.json

release: generate ## Archive, notarize, staple, and package a release DMG
	scripts/release.sh

clean: ## Remove build artifacts + generated projects
	rm -rf .build $(PACKAGE)/.build build App/build ManualTestApp/build
	rm -rf App/Squeegee.xcodeproj ManualTestApp/ManualTestApp.xcodeproj
	rm -rf ~/Library/Developer/Xcode/DerivedData/Squeegee-*
	rm -rf ~/Library/Developer/Xcode/DerivedData/ManualTestApp-*
