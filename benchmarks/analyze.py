#!/usr/bin/env python3
"""
benchmarks/analyze.py — Statistical analysis of weblens vs chrome benchmark results

Usage:
    python3 benchmarks/analyze.py benchmarks/results/latest.csv
    python3 benchmarks/analyze.py benchmarks/results/20260411_1430.csv [--json]

Output: formatted report to stdout (pipe to a .md file to save)
"""

import csv
import sys
import math
import json
import argparse
from collections import defaultdict
from datetime import datetime
from pathlib import Path


# ─── Stats helpers ──────────────────────────────────────────────────────────

def mean(vals):
    return sum(vals) / len(vals) if vals else 0.0

def stddev(vals):
    if len(vals) < 2:
        return 0.0
    m = mean(vals)
    return math.sqrt(sum((v - m) ** 2 for v in vals) / (len(vals) - 1))

def median(vals):
    if not vals:
        return 0.0
    s = sorted(vals)
    n = len(s)
    return (s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2)

def percentile(vals, p):
    if not vals:
        return 0.0
    s = sorted(vals)
    idx = (p / 100) * (len(s) - 1)
    lo, hi = int(idx), min(int(idx) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (idx - lo)

def fmt(v, decimals=1):
    """Format a float, suppressing trailing zeros."""
    return f"{v:.{decimals}f}"

def winner(wl_val, cr_val, lower_is_better=True):
    """Return colored winner label."""
    if wl_val == cr_val == 0:
        return "  tie  "
    if lower_is_better:
        if wl_val < cr_val:
            return "weblens"
        elif cr_val < wl_val:
            return "chrome "
        else:
            return "  tie  "
    else:
        if wl_val > cr_val:
            return "weblens"
        elif cr_val > wl_val:
            return "chrome "
        else:
            return "  tie  "

def ratio_str(wl_val, cr_val, lower_is_better=True):
    """Return a human-readable ratio like '2.3x faster'."""
    if wl_val == 0 or cr_val == 0:
        return "N/A"
    if lower_is_better:
        if cr_val > wl_val:
            return f"{cr_val / wl_val:.1f}x lower"
        elif wl_val > cr_val:
            return f"{wl_val / cr_val:.1f}x higher"
        else:
            return "equal"
    else:
        if wl_val > cr_val:
            return f"{wl_val / cr_val:.1f}x higher"
        elif cr_val > wl_val:
            return f"{cr_val / wl_val:.1f}x lower"
        else:
            return "equal"


# ─── Data loading ────────────────────────────────────────────────────────────

def load_csv(path):
    """Load CSV and return list of row dicts with numeric fields cast."""
    numeric = {"time_s", "total_tok", "fresh_tok", "output_tok", "cost_usd", "turns", "accuracy", "error"}
    rows = []
    with open(path) as f:
        for row in csv.DictReader(f):
            for k in numeric:
                if k in row:
                    try:
                        row[k] = float(row[k])
                    except (ValueError, TypeError):
                        row[k] = 0.0
            rows.append(row)
    return rows

def group_rows(rows):
    """
    Returns nested dict: data[task_id][tool] = list of row dicts
    """
    data = defaultdict(lambda: defaultdict(list))
    for row in rows:
        data[row["task"]][row["tool"]].append(row)
    return data

def get_categories(rows):
    cats = {}
    for row in rows:
        cats[row["task"]] = row["category"]
    return cats


# ─── Per-task stats ──────────────────────────────────────────────────────────

def task_stats(runs):
    """Compute mean/min/max/stddev for a list of run dicts."""
    if not runs:
        return {}
    metrics = ["time_s", "total_tok", "fresh_tok", "output_tok", "cost_usd", "turns", "accuracy", "error"]
    result = {}
    for m in metrics:
        vals = [r[m] for r in runs if r[m] is not None]
        result[m] = {
            "mean": mean(vals),
            "min": min(vals) if vals else 0.0,
            "max": max(vals) if vals else 0.0,
            "std": stddev(vals),
            "n": len(vals),
        }
    # Reliability = % of runs without error
    result["reliability"] = mean([1 - r["error"] for r in runs])
    return result


# ─── Report generation ───────────────────────────────────────────────────────

def print_report(csv_path, output_json=False):
    rows = load_csv(csv_path)
    if not rows:
        print("No data found in CSV.")
        sys.exit(1)

    data = group_rows(rows)
    cats = get_categories(rows)
    task_ids = list(data.keys())
    tools = ["weblens", "chrome"]

    # Compute per-task stats
    stats = {}
    for tid in task_ids:
        stats[tid] = {t: task_stats(data[tid].get(t, [])) for t in tools}

    # ── Aggregate across all tasks ──────────────────────────────────────────
    def agg(metric, tool):
        vals = []
        for tid in task_ids:
            s = stats[tid].get(tool, {})
            if s and metric in s:
                vals.append(s[metric]["mean"])
        return vals

    all_metrics = {}
    for t in tools:
        all_metrics[t] = {
            "time_s": mean(agg("time_s", t)),
            "total_tok": mean(agg("total_tok", t)),
            "fresh_tok": mean(agg("fresh_tok", t)),
            "output_tok": mean(agg("output_tok", t)),
            "cost_usd": mean(agg("cost_usd", t)),
            "turns": mean(agg("turns", t)),
            "accuracy": mean(agg("accuracy", t)),
            "reliability": mean([
                stats[tid].get(t, {}).get("reliability", 0.0)
                for tid in task_ids
            ]),
            "all_times": [
                r["time_s"] for tid in task_ids for r in data[tid].get(t, [])
            ],
            "all_fresh_tok": [
                r["fresh_tok"] for tid in task_ids for r in data[tid].get(t, [])
            ],
        }

    wl = all_metrics["weblens"]
    cr = all_metrics["chrome"]

    # Key ratios
    fresh_ratio = (cr["fresh_tok"] / wl["fresh_tok"]) if wl["fresh_tok"] > 0 else 0.0
    cost_ratio  = (cr["cost_usd"] / wl["cost_usd"])   if wl["cost_usd"]  > 0 else 0.0
    time_ratio  = (cr["time_s"]   / wl["time_s"])      if wl["time_s"]    > 0 else 0.0

    # Per-category aggregates
    cat_names = sorted(set(cats.values()))
    cat_stats = {}
    for cat in cat_names:
        cat_task_ids = [tid for tid in task_ids if cats.get(tid) == cat]
        cat_stats[cat] = {}
        for t in tools:
            cat_stats[cat][t] = {
                "accuracy": mean([
                    stats[tid].get(t, {}).get("accuracy", {}).get("mean", 0.0)
                    for tid in cat_task_ids if stats[tid].get(t)
                ]),
                "time_s": mean([
                    stats[tid].get(t, {}).get("time_s", {}).get("mean", 0.0)
                    for tid in cat_task_ids if stats[tid].get(t)
                ]),
                "fresh_tok": mean([
                    stats[tid].get(t, {}).get("fresh_tok", {}).get("mean", 0.0)
                    for tid in cat_task_ids if stats[tid].get(t)
                ]),
            }

    n_tasks = len(task_ids)
    n_runs = len(rows) // (n_tasks * len(tools)) if n_tasks else 0

    # ── JSON output ────────────────────────────────────────────────────────
    if output_json:
        out = {
            "summary": {t: all_metrics[t] for t in tools},
            "per_task": {
                tid: {t: stats[tid].get(t, {}) for t in tools}
                for tid in task_ids
            },
            "by_category": cat_stats,
        }
        # Remove non-serializable keys
        for t in tools:
            out["summary"][t].pop("all_times", None)
            out["summary"][t].pop("all_input_tok", None)
        print(json.dumps(out, indent=2))
        return

    # ── Text report ────────────────────────────────────────────────────────
    sep = "═" * 70

    print(sep)
    print(" WEBLENS vs CHROME — BENCHMARK RESULTS")
    print(sep)
    print(f"  File:    {csv_path}")
    print(f"  Tasks:   {n_tasks}   |   Runs/task/tool: {n_runs}")
    print(f"  Date:    {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print()

    # ── Summary table ──────────────────────────────────────────────────────
    print("  WINNER BY METRIC (mean across all tasks):")
    print(f"  {'Metric':<22} {'weblens':>10} {'chrome':>10}  {'winner':<8}  ratio")
    print("  " + "─" * 64)

    rows_summary = [
        ("Time (s)",         "time_s",      wl["time_s"],      cr["time_s"],      True,  "faster"),
        ("Fresh tokens/task","fresh_tok",   wl["fresh_tok"],   cr["fresh_tok"],   True,  "efficient"),
        ("Total tokens/task","total_tok",   wl["total_tok"],   cr["total_tok"],   True,  ""),
        ("Output tokens",    "output_tok",  wl["output_tok"],  cr["output_tok"],  True,  ""),
        ("Cost (USD)",       "cost_usd",    wl["cost_usd"],    cr["cost_usd"],    True,  "cheaper"),
        ("Turns",            "turns",       wl["turns"],       cr["turns"],       True,  "fewer"),
        ("Accuracy",         "accuracy",    wl["accuracy"],    cr["accuracy"],    False, "accurate"),
        ("Reliability",      "reliability", wl["reliability"], cr["reliability"], False, "reliable"),
    ]
    for label, key, wval, cval, lib, suffix in rows_summary:
        w = winner(wval, cval, lib)
        if key == "accuracy" or key == "reliability":
            fmt_w = f"{wval*100:.0f}%"
            fmt_c = f"{cval*100:.0f}%"
            r = ratio_str(wval, cval, lib)
        elif key == "cost_usd":
            fmt_w = f"${wval:.4f}"
            fmt_c = f"${cval:.4f}"
            r = ratio_str(wval, cval, lib)
        elif key in ("total_tok", "fresh_tok", "output_tok", "turns"):
            fmt_w = f"{int(wval):,}"
            fmt_c = f"{int(cval):,}"
            r = ratio_str(wval, cval, lib)
        else:
            fmt_w = f"{wval:.1f}s"
            fmt_c = f"{cval:.1f}s"
            r = ratio_str(wval, cval, lib)
        print(f"  {label:<22} {fmt_w:>10} {fmt_c:>10}  {w:<8}  {r}")

    print()

    # Latency percentiles
    wl_times = wl.get("all_times", [])
    cr_times = cr.get("all_times", [])
    if wl_times and cr_times:
        print(f"  Latency percentiles:      {'weblens':>8}  {'chrome':>8}")
        for p in [50, 75, 95]:
            wl_p = percentile(wl_times, p)
            cr_p = percentile(cr_times, p)
            print(f"    P{p:<2}                      {wl_p:>7.1f}s  {cr_p:>7.1f}s")
    print()

    # ── By category ────────────────────────────────────────────────────────
    print("  BY CATEGORY:")
    print(f"  {'Category':<20} {'wl_acc':>7} {'cr_acc':>7} {'wl_time':>8} {'cr_time':>8} {'wl_fresh':>9} {'cr_fresh':>9}")
    print("  " + "─" * 72)
    for cat in cat_names:
        wl_c = cat_stats[cat]["weblens"]
        cr_c = cat_stats[cat]["chrome"]
        note = " ← visual" if cat == "visual" else ""
        print(f"  {cat:<20} {wl_c['accuracy']*100:>6.0f}% {cr_c['accuracy']*100:>6.0f}% "
              f"{wl_c['time_s']:>7.1f}s {cr_c['time_s']:>7.1f}s "
              f"{int(wl_c['fresh_tok']):>9,} {int(cr_c['fresh_tok']):>9,}{note}")
    print()

    # ── Per-task detail table ───────────────────────────────────────────────
    print("  PER-TASK DETAIL (mean of runs):")
    hdr = f"  {'Task':<22} {'Cat':<16} {'wl_t':>6} {'cr_t':>6} {'wl_tok':>7} {'cr_tok':>7} {'wl_acc':>7} {'cr_acc':>7} {'wl_err':>6} {'cr_err':>6}"
    print(hdr)
    print("  " + "─" * (len(hdr) - 2))

    for tid in task_ids:
        cat = cats.get(tid, "?")
        wl_s = stats[tid].get("weblens", {})
        cr_s = stats[tid].get("chrome", {})

        def g(s, m, sub="mean"):
            v = s.get(m, {})
            return v.get(sub, 0.0) if isinstance(v, dict) else 0.0

        wl_t = g(wl_s, "time_s")
        cr_t = g(cr_s, "time_s")
        wl_tok = int(g(wl_s, "fresh_tok"))
        cr_tok = int(g(cr_s, "fresh_tok"))
        wl_acc = g(wl_s, "accuracy")
        cr_acc = g(cr_s, "accuracy")
        wl_err = g(wl_s, "error")
        cr_err = g(cr_s, "error")

        # Mark visual tasks and weblens-specific tasks
        marker = ""
        if cat == "visual":
            marker = " [V]"
        elif cat == "weblens_specific":
            marker = " [W]"

        print(f"  {tid:<22} {cat:<16} {wl_t:>5.1f}s {cr_t:>5.1f}s "
              f"{wl_tok:>7,} {cr_tok:>7,} "
              f"{wl_acc*100:>6.0f}% {cr_acc*100:>6.0f}% "
              f"{wl_err:>5.0f}   {cr_err:>5.0f}{marker}")

    print()
    print("  [V] = visual task (Chrome expected to win)  [W] = weblens-specific feature")
    print()

    # ── ASCII bar chart: input tokens ──────────────────────────────────────
    print("  FRESH TOKENS BY TASK (weblens ░ vs chrome █):")
    print("  (Fresh = non-cached tokens per task — shows per-page context overhead)")
    max_tok = max(
        max((stats[tid].get("weblens", {}).get("fresh_tok", {}).get("mean", 0) for tid in task_ids), default=1),
        max((stats[tid].get("chrome",  {}).get("fresh_tok", {}).get("mean", 0) for tid in task_ids), default=1),
    )
    max_tok = max(max_tok, 1)
    bar_width = 30
    for tid in task_ids:
        wl_tok = stats[tid].get("weblens", {}).get("fresh_tok", {}).get("mean", 0)
        cr_tok = stats[tid].get("chrome",  {}).get("fresh_tok", {}).get("mean", 0)
        wl_bar = int((wl_tok / max_tok) * bar_width) if max_tok else 0
        cr_bar = int((cr_tok / max_tok) * bar_width) if max_tok else 0
        print(f"  {tid:<22} wl: {'░' * wl_bar:<{bar_width}} {int(wl_tok):>7,}")
        print(f"  {'':<22} cr: {'█' * cr_bar:<{bar_width}} {int(cr_tok):>7,}")
    print()

    # ── Key findings ───────────────────────────────────────────────────────
    print(sep)
    print(" KEY FINDINGS")
    print(sep)

    # Tasks where weblens wins on accuracy
    wl_wins = [tid for tid in task_ids
               if stats[tid].get("weblens", {}).get("accuracy", {}).get("mean", 0)
               > stats[tid].get("chrome", {}).get("accuracy", {}).get("mean", 0)]
    cr_wins = [tid for tid in task_ids
               if stats[tid].get("chrome", {}).get("accuracy", {}).get("mean", 0)
               > stats[tid].get("weblens", {}).get("accuracy", {}).get("mean", 0)]
    ties = [tid for tid in task_ids if tid not in wl_wins and tid not in cr_wins]

    print(f"  Accuracy wins — weblens: {len(wl_wins)}, chrome: {len(cr_wins)}, tied: {len(ties)}")
    if fresh_ratio > 0:
        print(f"  Fresh token efficiency — weblens uses {fresh_ratio:.1f}x fewer fresh tokens on average")
    if time_ratio > 0:
        print(f"  Speed — weblens is {time_ratio:.1f}x faster on average")
    if cost_ratio > 0:
        print(f"  Cost — weblens is {cost_ratio:.1f}x cheaper on average")

    visual_tasks = [tid for tid in task_ids if cats.get(tid) == "visual"]
    if visual_tasks:
        wl_vis_acc = mean([
            stats[tid].get("weblens", {}).get("accuracy", {}).get("mean", 0)
            for tid in visual_tasks
        ])
        cr_vis_acc = mean([
            stats[tid].get("chrome", {}).get("accuracy", {}).get("mean", 0)
            for tid in visual_tasks
        ])
        print(f"  Visual tasks ({len(visual_tasks)}) — weblens: {wl_vis_acc*100:.0f}%, chrome: {cr_vis_acc*100:.0f}%")

    non_visual = [tid for tid in task_ids if cats.get(tid) != "visual"]
    if non_visual:
        wl_nv_acc = mean([
            stats[tid].get("weblens", {}).get("accuracy", {}).get("mean", 0)
            for tid in non_visual
        ])
        cr_nv_acc = mean([
            stats[tid].get("chrome", {}).get("accuracy", {}).get("mean", 0)
            for tid in non_visual
        ])
        print(f"  Non-visual tasks ({len(non_visual)}) — weblens: {wl_nv_acc*100:.0f}%, chrome: {cr_nv_acc*100:.0f}%")

    print()


# ─── Entry point ────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Analyze weblens vs chrome benchmark CSV")
    parser.add_argument("csv_file", help="Path to benchmark CSV file")
    parser.add_argument("--json", action="store_true", help="Output as JSON instead of text")
    args = parser.parse_args()

    csv_path = Path(args.csv_file)
    if not csv_path.exists():
        print(f"Error: {csv_path} not found", file=sys.stderr)
        sys.exit(1)

    print_report(str(csv_path), output_json=args.json)
