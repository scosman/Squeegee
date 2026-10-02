#!/usr/bin/env bash
#
# run.sh — Build a Release app, swap in for the installed copy, record a
# 5-minute Time Profiler trace, then analyze and report.
#
# Usage:
#   scripts/profile/run.sh <label>
#   # e.g. scripts/profile/run.sh baseline
#
# Must run outside the agent sandbox (xcodebuild, xctrace, osascript).
# The user must be at the Mac during the 5-minute recording.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BUNDLE_ID="net.scosman.squeegee"
INSTALLED_APP="/Applications/Squeegee.app"
PROFILE_DIR="$REPO_ROOT/build/profile"
APP_PATH="$PROFILE_DIR/DerivedData/Build/Products/Release/Squeegee.app"
BINARY_PATH="$APP_PATH/Contents/MacOS/Squeegee"

WARMUP_SECONDS=10
RECORD_SECONDS=300
QUIT_TIMEOUT=20

# ── Argument ───────────────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <label>" >&2
    exit 1
fi

LABEL="$1"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$PROFILE_DIR/$LABEL-$TIMESTAMP"
mkdir -p "$RUN_DIR"

log() { printf '==> %s\n' "$*"; }
error() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ── Trap: always restart the installed app ─────────────────────────────────────

restart_installed() {
    if [[ -d "$INSTALLED_APP" ]]; then
        log "Restarting installed app"
        open "$INSTALLED_APP" || true
    fi
}
trap restart_installed EXIT

# ── Step 1: Build ──────────────────────────────────────────────────────────────

log "Building Release app (make profile-app)"
(cd "$REPO_ROOT" && make profile-app)

if [[ ! -x "$BINARY_PATH" ]]; then
    error "Build output not found at $BINARY_PATH"
fi

# ── Step 2: Check for stray builds ────────────────────────────────────────────

# Match actual Squeegee binaries by executable path, not command-line args
STRAY_PIDS=$(pgrep -f '/Squeegee.app/Contents/MacOS/Squeegee' 2>/dev/null || true)
for stray_pid in $STRAY_PIDS; do
    stray_path=$(ps -o command= -p "$stray_pid" 2>/dev/null | awk '{print $1}' || true)
    case "$stray_path" in
        "$INSTALLED_APP"/Contents/MacOS/Squeegee) ;;
        "$BINARY_PATH") ;;
        */Squeegee.app/Contents/MacOS/Squeegee)
            error "A Squeegee process is running from $stray_path. Quit it first." ;;
    esac
done

# ── Step 3: Quit installed app ─────────────────────────────────────────────────

if pgrep -f "$INSTALLED_APP/Contents/MacOS/Squeegee" >/dev/null 2>&1; then
    log "Quitting installed Squeegee"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" || true

    elapsed=0
    while pgrep -f "$INSTALLED_APP/Contents/MacOS/Squeegee" >/dev/null 2>&1; do
        sleep 1
        elapsed=$((elapsed + 1))
        if [[ $elapsed -ge $QUIT_TIMEOUT ]]; then
            error "Installed app did not quit within $QUIT_TIMEOUT seconds"
        fi
    done
    log "Installed app quit after ${elapsed}s"
fi

# ── Step 4: Copy the store ────────────────────────────────────────────────────

STORE_SOURCE="$HOME/Library/Application Support/Squeegee"
STORE_DEST="$RUN_DIR/store"
mkdir -p "$STORE_DEST"

if ls "$STORE_SOURCE"/Squeegee.store* >/dev/null 2>&1; then
    cp "$STORE_SOURCE"/Squeegee.store* "$STORE_DEST/"
    log "Copied store to $STORE_DEST"
else
    log "No existing store found — profiling with a fresh store"
fi

# ── Step 5: Launch profiling build ─────────────────────────────────────────────

log "Launching profiling build"
open -n "$APP_PATH" --args --profiling-store "$STORE_DEST"

elapsed=0
PID=""
while [[ -z "$PID" ]]; do
    PID=$(pgrep -f "$BINARY_PATH" 2>/dev/null || true)
    sleep 1
    elapsed=$((elapsed + 1))
    if [[ $elapsed -ge $QUIT_TIMEOUT ]]; then
        error "Profiling build did not start within $QUIT_TIMEOUT seconds"
    fi
done
log "Profiling build running (pid=$PID)"

# ── Step 6: Record trace ──────────────────────────────────────────────────────

log "Warming up for ${WARMUP_SECONDS}s"
sleep "$WARMUP_SECONDS"

TRACE_PATH="$RUN_DIR/trace.trace"
log "Recording ${RECORD_SECONDS}s — use the Mac normally"
xcrun xctrace record \
    --template 'Time Profiler' \
    --attach "$PID" \
    --time-limit "${RECORD_SECONDS}s" \
    --output "$TRACE_PATH"

# ── Step 7: Quit profiling build ──────────────────────────────────────────────

log "Quitting profiling build"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true

elapsed=0
while pgrep -f "$BINARY_PATH" >/dev/null 2>&1; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [[ $elapsed -ge $QUIT_TIMEOUT ]]; then
        log "Force-killing profiling build"
        kill -9 "$PID" 2>/dev/null || true
        break
    fi
done

# ── Step 8: Analyze ───────────────────────────────────────────────────────────

REPORT_PATH="$RUN_DIR/report.md"
log "Analyzing trace"
python3 "$SCRIPT_DIR/analyze_trace.py" "$TRACE_PATH" > "$REPORT_PATH"

log "Report written to $REPORT_PATH"
echo ""
cat "$REPORT_PATH"
