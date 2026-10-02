#!/usr/bin/env python3
"""
analyze_trace.py — Parse an xctrace Time Profiler trace and produce a
Markdown profiling report on stdout.

Usage:
    python3 analyze_trace.py <path-to.trace>

Requires: xcrun xctrace (ships with Xcode).
Standard library only — no third-party packages.
"""

import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from pathlib import Path


# ── xctrace helpers ────────────────────────────────────────────────────────────


def xctrace_export(trace_path: str, xpath: str, tmp_dir: str) -> str:
    """Export a table from the trace to a temp XML file and return its path."""
    out_path = Path(tmp_dir) / (xpath.replace("/", "_").replace(" ", "_") + ".xml")
    with open(out_path, "w") as fh:
        subprocess.run(
            [
                "xcrun",
                "xctrace",
                "export",
                "--input",
                trace_path,
                "--xpath",
                xpath,
            ],
            stdout=fh,
            stderr=subprocess.PIPE,
            check=True,
            text=True,
        )
    return str(out_path)


def xctrace_toc(trace_path: str) -> str:
    """Export the table of contents XML."""
    result = subprocess.run(
        ["xcrun", "xctrace", "export", "--input", trace_path, "--toc"],
        capture_output=True,
        check=True,
        text=True,
    )
    return result.stdout


# ── XML id/ref resolution ─────────────────────────────────────────────────────


def resolve_refs(root: ET.Element) -> None:
    """Resolve id/ref attributes in xctrace XML.

    Elements with an ``id`` attribute are stored. Later elements with a
    ``ref`` attribute pointing to that id are replaced with a copy of
    the original element (children and attributes).
    """
    registry: dict[str, ET.Element] = {}
    _collect_ids(root, registry)
    _resolve(root, registry)


def _collect_ids(elem: ET.Element, registry: dict[str, ET.Element]) -> None:
    eid = elem.get("id")
    if eid is not None:
        registry[eid] = elem
    for child in elem:
        _collect_ids(child, registry)


def _resolve(elem: ET.Element, registry: dict[str, ET.Element]) -> None:
    for i, child in enumerate(list(elem)):
        ref = child.get("ref")
        if ref is not None and ref in registry:
            original = registry[ref]
            # Replace the ref element with a shallow copy of the original
            clone = ET.Element(original.tag, original.attrib)
            clone.text = original.text
            clone.tail = child.tail
            for sub in original:
                clone.append(sub)
            elem[i] = clone
            child = clone
        _resolve(child, registry)


# ── Time profile parsing ──────────────────────────────────────────────────────


def frame_label(frame_elem: ET.Element) -> str:
    """Return a human-readable label for a stack frame."""
    name = frame_elem.get("name")
    if name:
        return name
    addr = frame_elem.get("addr") or "?"
    # Find the containing binary
    binary = ""
    for child in frame_elem:
        if child.tag == "binary":
            binary = child.get("name", "")
            break
    if binary:
        return f"{binary}+{addr}"
    return f"unknown+{addr}"


def binary_name(frame_elem: ET.Element) -> str:
    """Return the binary name for a stack frame."""
    for child in frame_elem:
        if child.tag == "binary":
            return child.get("name", "unknown")
    return "unknown"


def parse_time_profile(xml_path: str):
    """Parse the time-profile table XML.

    Returns (total_samples, total_weight_ms, binary_samples, top_self,
    top_inclusive_squeegee, recording_length_ms).
    """
    tree = ET.parse(xml_path)
    root = tree.getroot()
    resolve_refs(root)

    total_samples = 0
    total_weight_ms = 0.0
    binary_samples: Counter = Counter()
    self_samples: Counter = Counter()
    inclusive_squeegee: Counter = Counter()

    # Each <row> in the time-profile table has a weight (CPU time per sample)
    # and a backtrace (stack of <frame> elements).
    for row in root.iter("row"):
        weight_elem = row.find(".//weight")
        count = 1
        weight_ms = 0.0
        if weight_elem is not None:
            # The element text is the raw value in nanoseconds; the fmt
            # attribute is a human-readable string like "1.00 ms".
            raw = weight_elem.text
            fmt = weight_elem.get("fmt")
            if raw and raw.strip().isdigit():
                weight_ms = int(raw.strip()) / 1_000_000  # ns → ms
            elif fmt:
                weight_ms = _parse_fmt_ms(fmt)

        total_samples += count
        total_weight_ms += weight_ms

        # Walk backtrace
        frames = list(row.iter("frame"))
        if not frames:
            continue

        # Self (leaf) frame
        leaf = frames[-1] if frames else None
        if leaf is not None:
            lbl = frame_label(leaf)
            self_samples[lbl] += 1

        # Inclusive: count each unique (binary, function) once per sample
        seen_binaries: set[str] = set()
        seen_squeegee: set[str] = set()
        for f in frames:
            bn = binary_name(f)
            if bn not in seen_binaries:
                seen_binaries.add(bn)
                binary_samples[bn] += 1
            if bn == "Squeegee" and frame_label(f) not in seen_squeegee:
                seen_squeegee.add(frame_label(f))
                inclusive_squeegee[frame_label(f)] += 1

    return (
        total_samples,
        total_weight_ms,
        binary_samples,
        self_samples,
        inclusive_squeegee,
    )


def _parse_fmt_ms(fmt: str) -> float:
    """Parse a formatted duration string like '1.23 ms' or '456 µs'."""
    fmt = fmt.strip()
    if fmt.endswith("ms"):
        try:
            return float(fmt[:-2].strip())
        except ValueError:
            return 0.0
    if fmt.endswith("µs") or fmt.endswith("us"):
        try:
            return float(fmt[:-2].strip()) / 1000
        except ValueError:
            return 0.0
    if fmt.endswith("s"):
        try:
            return float(fmt[:-1].strip()) * 1000
        except ValueError:
            return 0.0
    return 0.0


# ── Signpost parsing ──────────────────────────────────────────────────────────

SQUEEGEE_SUBSYSTEM = "net.scosman.squeegee"


def _elem_text(elem: ET.Element | None) -> str:
    """Return the fmt attribute or text content of an element, or ""."""
    if elem is None:
        return ""
    return elem.get("fmt") or elem.text or ""


def parse_signposts(xml_path: str):
    """Parse the os-signpost table XML.

    xctrace exports Begin/End/Event as separate rows. Intervals are
    paired by (signpost-identifier, signpost-name) and their duration
    is computed from timestamps.

    Returns (interval_stats, event_counts) where:
      interval_stats[name] = {"count": int, "total_ms": float}
      event_counts[name][message_label] = int
    """
    tree = ET.parse(xml_path)
    root = tree.getroot()
    resolve_refs(root)

    interval_stats: dict[str, dict] = defaultdict(
        lambda: {"count": 0, "total_ms": 0.0, "labels": Counter()}
    )
    event_counts: dict[str, Counter] = defaultdict(Counter)

    # Track open intervals: (identifier, name) -> begin_time_ns
    open_intervals: dict[tuple[str, str], int] = {}
    # Track begin messages for intervals: (identifier, name) -> message
    begin_messages: dict[tuple[str, str], str] = {}

    for row in root.iter("row"):
        # Filter to our subsystem
        subsystem = _elem_text(row.find(".//subsystem"))
        if subsystem != SQUEEGEE_SUBSYSTEM:
            continue

        # Signpost name (engineering-type: signpost-name)
        name = _elem_text(row.find(".//signpost-name"))
        if not name:
            continue

        # Event type (engineering-type: event-type): "Begin", "End", "Event"
        event_type = _elem_text(row.find(".//event-type"))

        # Timestamp (engineering-type: event-time), text is nanoseconds
        time_elem = row.find(".//event-time")
        time_ns = 0
        if time_elem is not None and time_elem.text:
            try:
                time_ns = int(time_elem.text)
            except ValueError:
                pass

        # Signpost identifier (engineering-type: os-signpost-identifier)
        ident = _elem_text(row.find(".//os-signpost-identifier"))

        # Message (engineering-type: os-log-metadata)
        msg = _elem_text(row.find(".//os-log-metadata"))

        pair_key = (ident, name)

        if event_type == "Begin":
            open_intervals[pair_key] = time_ns
            if msg:
                begin_messages[pair_key] = msg

        elif event_type == "End":
            begin_ns = open_intervals.pop(pair_key, None)
            begin_msg = begin_messages.pop(pair_key, "")
            if begin_ns is not None:
                duration_ms = (time_ns - begin_ns) / 1_000_000
                interval_stats[name]["count"] += 1
                interval_stats[name]["total_ms"] += duration_ms
                if begin_msg:
                    interval_stats[name]["labels"][begin_msg] += 1

        elif event_type == "Event":
            label = msg.strip() if msg else "(none)"
            event_counts[name][label] += 1

    return interval_stats, event_counts


# ── Report generation ─────────────────────────────────────────────────────────

# Binaries to highlight in the share-by-binary table
HIGHLIGHT_BINARIES = [
    "SwiftData",
    "CoreData",
    "libsqlite3.dylib",
    "HIServices",
    "CoreGraphics",
    "SkyLight",
    "SwiftUI",
    "AttributeGraph",
    "Squeegee",
]


def generate_report(
    total_samples,
    total_weight_ms,
    binary_samples,
    self_samples,
    inclusive_squeegee,
    interval_stats,
    event_counts,
    recording_length_s=None,
):
    """Generate a Markdown report and print to stdout."""
    lines = []

    def out(s=""):
        lines.append(s)

    out("# Profiling Report")
    out()
    if recording_length_s is not None:
        out(f"- **Recording length:** {recording_length_s:,.1f} s")
    out(f"- **Total samples:** {total_samples:,}")
    out(f"- **Total CPU:** {total_weight_ms:,.1f} ms")
    out()

    # Share by binary (inclusive)
    out("## Share by Binary (inclusive)")
    out()
    out("| Binary | Samples | Share |")
    out("|---|---:|---:|")
    for bn in HIGHLIGHT_BINARIES:
        count = binary_samples.get(bn, 0)
        share = (count / total_samples * 100) if total_samples > 0 else 0
        if count > 0:
            out(f"| {bn} | {count:,} | {share:.1f}% |")
    # Any other binaries with > 1% share
    for bn, count in binary_samples.most_common():
        if bn in HIGHLIGHT_BINARIES:
            continue
        share = (count / total_samples * 100) if total_samples > 0 else 0
        if share >= 1.0:
            out(f"| {bn} | {count:,} | {share:.1f}% |")
    out()

    # Top 25 inclusive functions in Squeegee binary
    out("## Top 25 Inclusive Functions (Squeegee binary)")
    out()
    out("| Function | Samples | Share |")
    out("|---|---:|---:|")
    for func_name, count in inclusive_squeegee.most_common(25):
        share = (count / total_samples * 100) if total_samples > 0 else 0
        # Truncate long function names
        display = func_name[:100] + "…" if len(func_name) > 100 else func_name
        out(f"| `{display}` | {count:,} | {share:.1f}% |")
    out()

    # Top 25 self (leaf) functions
    out("## Top 25 Self (Leaf) Functions")
    out()
    out("| Function | Samples | Share |")
    out("|---|---:|---:|")
    for func_name, count in self_samples.most_common(25):
        share = (count / total_samples * 100) if total_samples > 0 else 0
        display = func_name[:100] + "…" if len(func_name) > 100 else func_name
        out(f"| `{display}` | {count:,} | {share:.1f}% |")
    out()

    # Signposts
    out("## Signposts")
    out()

    # Intervals
    if interval_stats:
        out("### Intervals")
        out()
        out("| Name | Count | Total (ms) | Mean (ms) |")
        out("|---|---:|---:|---:|")
        for name in sorted(interval_stats.keys()):
            stats = interval_stats[name]
            count = stats["count"]
            total = stats["total_ms"]
            mean = total / count if count > 0 else 0
            out(f"| {name} | {count:,} | {total:,.1f} | {mean:.2f} |")
        out()

        # Per-label breakdown for intervals that carry begin messages
        for name in sorted(interval_stats.keys()):
            labels = interval_stats[name]["labels"]
            if labels:
                out(f"**{name}** by label:")
                out()
                out("| Label | Count |")
                out("|---|---:|")
                for label, lcount in labels.most_common():
                    out(f"| {label} | {lcount:,} |")
                out()

    # Events
    if event_counts:
        out("### Events")
        out()
        for name in sorted(event_counts.keys()):
            labels = event_counts[name]
            total_for_name = sum(labels.values())
            out(f"**{name}** — {total_for_name:,} total")
            out()
            if len(labels) > 1 or (len(labels) == 1 and "(none)" not in labels):
                out("| Label | Count |")
                out("|---|---:|")
                for label, count in labels.most_common():
                    out(f"| {label} | {count:,} |")
                out()

    # CPU per event
    total_events = sum(
        sum(labels.values())
        for name, labels in event_counts.items()
        if name in ("workspaceEvent", "focusSignal", "scanTick")
    )
    if total_events > 0:
        cpu_per_event = total_weight_ms / total_events
        out(f"**CPU per event:** {cpu_per_event:.2f} ms "
            f"({total_weight_ms:,.1f} ms / {total_events:,} events)")
        out()

    # Warning: no inspect signposts
    if "inspect" not in interval_stats:
        out("> **Warning:** No `inspect` signposts found — "
            "the app may not have Accessibility permission.")
        out()

    print("\n".join(lines))


# ── Table discovery ────────────────────────────────────────────────────────────


def parse_recording_length(toc_xml: str) -> float | None:
    """Extract the recording length in seconds from the TOC XML."""
    root = ET.fromstring(toc_xml)
    for elem in root.iter("duration"):
        if elem.text:
            try:
                return float(elem.text)
            except ValueError:
                pass
    return None


def find_table_xpath(toc_xml: str, schema_keyword: str) -> str | None:
    """Find the xpath for a table whose schema name contains the keyword."""
    root = ET.fromstring(toc_xml)
    for table in root.iter("table"):
        schema = table.get("schema", "")
        if schema_keyword in schema.lower():
            # Build the xpath
            run = table.find("..")
            if run is None:
                # table is directly under run
                for run_elem in root.iter("run"):
                    for t in run_elem:
                        if t is table:
                            run = run_elem
                            break
            run_number = "1"
            if run is not None:
                run_number = run.get("number", "1")
            return (
                f'/trace-toc/run[@number="{run_number}"]'
                f'/data/table[@schema="{schema}"]'
            )
    return None


# ── Main ───────────────────────────────────────────────────────────────────────


def main():
    if len(sys.argv) < 2:
        print("Usage: analyze_trace.py <path-to.trace>", file=sys.stderr)
        sys.exit(1)

    trace_path = sys.argv[1]
    if not Path(trace_path).exists():
        print(f"Error: trace not found at {trace_path}", file=sys.stderr)
        sys.exit(1)

    # Get table of contents
    toc_xml = xctrace_toc(trace_path)
    recording_length_s = parse_recording_length(toc_xml)

    with tempfile.TemporaryDirectory() as tmp_dir:
        # Export time-profile table
        tp_xpath = find_table_xpath(toc_xml, "time-profile")
        if tp_xpath is None:
            print("Error: no time-profile table found in trace", file=sys.stderr)
            sys.exit(1)

        tp_xml_path = xctrace_export(trace_path, tp_xpath, tmp_dir)

        total_samples, total_weight_ms, binary_samples, self_samples, inclusive_squeegee = (
            parse_time_profile(tp_xml_path)
        )

        # Export signpost table
        interval_stats = {}
        event_counts = {}
        sp_xpath = find_table_xpath(toc_xml, "signpost")
        if sp_xpath is not None:
            sp_xml_path = xctrace_export(trace_path, sp_xpath, tmp_dir)
            interval_stats, event_counts = parse_signposts(sp_xml_path)
        else:
            print("Warning: no signpost table found in trace", file=sys.stderr)

        generate_report(
            total_samples,
            total_weight_ms,
            binary_samples,
            self_samples,
            inclusive_squeegee,
            interval_stats,
            event_counts,
            recording_length_s=recording_length_s,
        )


if __name__ == "__main__":
    main()
