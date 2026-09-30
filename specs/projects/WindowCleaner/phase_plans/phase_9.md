---
status: complete
---

# Phase 9: Release

## Overview

Add the release script, a proper README, and update CLAUDE.md to reflect the completed state of the project (Phases 1-9 built). The release script automates the Developer ID archive, notarization, stapling, and DMG creation pipeline. It is not run in this phase -- it is validated syntactically and designed to fail clearly when credentials are missing.

## Steps

1. Create `scripts/release.sh`:
   - Read version from `App/project.yml` (`MARKETING_VERSION`).
   - `xcodebuild archive` with Release config, Developer ID Application signing, hardened runtime.
   - `xcodebuild -exportArchive` with `method: developer-id`.
   - `xcrun notarytool submit --keychain-profile <profile> --wait` then `xcrun stapler staple` on the `.app`.
   - `hdiutil create` a DMG with the app and `/Applications` symlink.
   - Sign the DMG, then notarize and staple the DMG.
   - Output to `build/release/WindowCleaner-<version>.dmg`.
   - Fail early with clear messages when required env vars / tools are missing.
   - Validate with `bash -n`.

2. Add `make release` target to the Makefile:
   - Depends on `generate`.
   - Runs `scripts/release.sh`.

3. Write `README.md`:
   - Product description, features, requirements (macOS 15+).
   - Build instructions (bootstrap, build, test, run).
   - Release process overview with required env vars.
   - Development section (module map, conventions).
   - No license section.

4. Update `CLAUDE.md`:
   - Update "Current stage" to reflect Phases 1-9 built.
   - Add `make release` to the Makefile table.

## Tests

- No automated tests for this phase (release script, README, and CLAUDE.md updates are not testable by the test suite).
- Validate `release.sh` with `bash -n` (syntax check).
