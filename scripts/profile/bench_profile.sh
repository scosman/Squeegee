#!/usr/bin/env bash
# bench_profile.sh <label>
#
# Builds perf-bench in release mode, runs it once to capture a bench table,
# then records a Time Profiler trace of a churn run and analyzes it.
set -euo pipefail

LABEL="${1:?Usage: bench_profile.sh <label>}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTDIR="build/profile/bench-${LABEL}-${TIMESTAMP}"
PACKAGE="Packages/SqueegeeKit"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$OUTDIR"

echo "==> Building perf-bench (release)…"
swift build -c release --package-path "$PACKAGE" --product perf-bench 2>&1 | tail -n 20

BIN_DIR=$(swift build -c release --package-path "$PACKAGE" --show-bin-path)
BIN="$BIN_DIR/perf-bench"

if [ ! -x "$BIN" ]; then
    echo "Error: perf-bench binary not found at $BIN" >&2
    exit 1
fi

echo "==> Running perf-bench (all scenarios, 5 repeats)…"
"$BIN" | tee "$OUTDIR/bench.md"
echo ""

echo "==> Recording Time Profiler trace (churn, 10 repeats)…"
xcrun xctrace record \
    --template 'Time Profiler' \
    --output "$OUTDIR/trace.trace" \
    --launch -- "$BIN" --scenario churn --repeat 10

echo ""
echo "==> Analyzing trace…"
python3 "$SCRIPT_DIR/analyze_trace.py" --binary perf-bench "$OUTDIR/trace.trace" \
    | tee "$OUTDIR/report.md"

echo ""
echo "==> Done. Output in $OUTDIR/"
echo "    bench.md  — benchmark table"
echo "    trace.trace — Time Profiler trace"
echo "    report.md — trace analysis"
