#!/usr/bin/env python3
"""
scripts/lib/aggregate-stats.py — Statistical aggregation for benchmark runs.

Usage: aggregate-stats.py <log_dir> <num_runs> <mode> <output_file>

Reads run_1.json through run_N.json from log_dir, computes per-step and
total statistics, prints a formatted table, and writes a JSON summary.
"""

import json
import math
import os
import sys


def load_runs(log_dir: str, num_runs: int) -> list[dict]:
    """Load run_1.json through run_N.json from log_dir."""
    runs = []
    for i in range(1, num_runs + 1):
        path = os.path.join(log_dir, f"run_{i}.json")
        if not os.path.exists(path):
            print(f"Warning: {path} not found, skipping", file=sys.stderr)
            continue
        with open(path) as f:
            runs.append(json.load(f))
    return runs


def calc_stats(values: list[float]) -> dict:
    """Calculate avg, median, min, max, stddev for a list of values."""
    if not values:
        return {"avg": 0.0, "median": 0.0, "min": 0.0, "max": 0.0, "stddev": 0.0}

    n = len(values)
    avg = sum(values) / n
    sorted_vals = sorted(values)

    if n % 2 == 1:
        median = sorted_vals[n // 2]
    else:
        median = (sorted_vals[n // 2 - 1] + sorted_vals[n // 2]) / 2.0

    min_val = min(values)
    max_val = max(values)

    if n > 1:
        variance = sum((x - avg) ** 2 for x in values) / (n - 1)
        stddev = math.sqrt(variance)
    else:
        stddev = 0.0

    return {
        "avg": round(avg, 1),
        "median": round(median, 1),
        "min": round(min_val, 1),
        "max": round(max_val, 1),
        "stddev": round(stddev, 1),
    }


def extract_step_names(runs: list[dict]) -> list[str]:
    """Extract step names preserving order from the first run."""
    if not runs:
        return []
    seen = set()
    names = []
    for step in runs[0].get("steps", []):
        name = step["name"]
        if name not in seen:
            seen.add(name)
            names.append(name)
    # Also include any steps from later runs that weren't in the first
    for run in runs[1:]:
        for step in run.get("steps", []):
            name = step["name"]
            if name not in seen:
                seen.add(name)
                names.append(name)
    return names


def aggregate(runs: list[dict], mode: str) -> dict:
    """Compute per-step and total statistics across runs."""
    step_names = extract_step_names(runs)

    # Collect durations and resources per step
    per_step = {}
    for name in step_names:
        durations = []
        cpu_avgs = []
        mem_peaks = []

        for run in runs:
            for step in run.get("steps", []):
                if step["name"] == name:
                    durations.append(float(step["duration_sec"]))
                    resources = step.get("resources")
                    if resources:
                        if "cpu_avg_percent" in resources:
                            cpu_avgs.append(float(resources["cpu_avg_percent"]))
                        elif "cpu_avg" in resources:
                            cpu_avgs.append(float(resources["cpu_avg"]))
                        if "mem_peak_mb" in resources:
                            mem_peaks.append(float(resources["mem_peak_mb"]))
                    break

        stats = calc_stats(durations)

        # Average CPU and max mem peak
        cpu_avg = round(sum(cpu_avgs) / len(cpu_avgs), 1) if cpu_avgs else None
        mem_peak_mb = round(max(mem_peaks), 1) if mem_peaks else None

        stats["cpu_avg"] = cpu_avg
        stats["mem_peak_mb"] = mem_peak_mb
        per_step[name] = stats

    # Total duration stats
    total_durations = []
    for run in runs:
        if "total_duration_sec" in run:
            total_durations.append(float(run["total_duration_sec"]))
    total_stats = calc_stats(total_durations)

    # Host info from first run
    host = {}
    if runs:
        session = runs[0].get("session", {})
        host = session.get("host", {})

    return {
        "session": {
            "mode": mode,
            "runs": len(runs),
            "host": host,
        },
        "per_step": per_step,
        "total": total_stats,
    }


def format_duration(val: float) -> str:
    """Format a duration value as e.g. '45.2s'."""
    return f"{val:.1f}s"


def print_table(result: dict) -> None:
    """Print a formatted summary table to stdout."""
    num_runs = result["session"]["runs"]
    mode = result["session"]["mode"]
    host = result["session"].get("host", {})

    os_name = host.get("os", "unknown")
    cpu_model = host.get("cpu_model", "unknown")
    memory_gb = host.get("memory_gb", "?")

    col_step = 27
    col_val = 7
    col_cpu = 9
    col_mem = 9

    header_width = 100

    print("=" * header_width)
    title = f" {mode.replace('-', ' ').title()} Benchmark Summary ({num_runs} runs)"
    print(title)
    print(f" Host: {os_name} / {cpu_model} / {memory_gb}GB")
    print("=" * header_width)

    # Column headers
    print(
        f" {'Step':<{col_step}} | {'Avg':>{col_val}} | {'Median':>{col_val}} | "
        f"{'Min':>{col_val}} | {'Max':>{col_val}} | {'StdDev':>{col_val}} | "
        f"{'CPU Avg':>{col_cpu}} | {'Mem Peak':>{col_mem}}"
    )
    print("-" * header_width)

    # Per-step rows
    per_step = result.get("per_step", {})
    for step_name, stats in per_step.items():
        avg_s = format_duration(stats["avg"])
        med_s = format_duration(stats["median"])
        min_s = format_duration(stats["min"])
        max_s = format_duration(stats["max"])
        std_s = format_duration(stats["stddev"])

        cpu_avg = stats.get("cpu_avg")
        mem_peak = stats.get("mem_peak_mb")

        cpu_str = f"{cpu_avg:.1f}%" if cpu_avg is not None else "\u2014"
        if mem_peak is not None:
            if mem_peak >= 1024:
                mem_str = f"{mem_peak / 1024:.1f} GB"
            else:
                mem_str = f"{mem_peak:.0f} MB"
        else:
            mem_str = "\u2014"

        # Truncate step name if too long
        display_name = step_name if len(step_name) <= col_step else step_name[: col_step - 2] + ".."

        print(
            f" {display_name:<{col_step}} | {avg_s:>{col_val}} | {med_s:>{col_val}} | "
            f"{min_s:>{col_val}} | {max_s:>{col_val}} | {std_s:>{col_val}} | "
            f"{cpu_str:>{col_cpu}} | {mem_str:>{col_mem}}"
        )

    # Total row
    print("-" * header_width)
    total = result.get("total", {})
    avg_s = format_duration(total.get("avg", 0))
    med_s = format_duration(total.get("median", 0))
    min_s = format_duration(total.get("min", 0))
    max_s = format_duration(total.get("max", 0))
    std_s = format_duration(total.get("stddev", 0))

    print(
        f" {'TOTAL':<{col_step}} | {avg_s:>{col_val}} | {med_s:>{col_val}} | "
        f"{min_s:>{col_val}} | {max_s:>{col_val}} | {std_s:>{col_val}} | "
        f"{'\u2014':>{col_cpu}} | {'\u2014':>{col_mem}}"
    )
    print("=" * header_width)


def main() -> None:
    if len(sys.argv) != 5:
        print(
            f"Usage: {sys.argv[0]} <log_dir> <num_runs> <mode> <output_file>",
            file=sys.stderr,
        )
        sys.exit(1)

    log_dir = sys.argv[1]
    num_runs = int(sys.argv[2])
    mode = sys.argv[3]
    output_file = sys.argv[4]

    runs = load_runs(log_dir, num_runs)
    if not runs:
        print("Error: no benchmark run files found", file=sys.stderr)
        sys.exit(1)

    result = aggregate(runs, mode)

    # Print formatted table to stdout
    print_table(result)

    # Write JSON summary
    output_dir = os.path.dirname(output_file)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    with open(output_file, "w") as f:
        json.dump(result, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
