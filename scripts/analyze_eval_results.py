#!/usr/bin/env python3
import argparse
import csv
import statistics
from collections import Counter, defaultdict
from pathlib import Path


def as_bool(value):
    return str(value).strip().lower() == "true"


def as_float(row, key):
    value = row.get(key, "").strip()
    if not value:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def summarize_number(rows, key):
    values = [as_float(row, key) for row in rows]
    values = [value for value in values if value is not None]
    if not values:
        return None
    return {
        "count": len(values),
        "avg": statistics.mean(values),
        "median": statistics.median(values),
        "min": min(values),
        "max": max(values),
    }


def violation_counts(rows):
    counts = Counter()
    for row in rows:
        raw = row.get("violations", "")
        for part in raw.replace("|", ";").split(";"):
            part = part.strip()
            if not part:
                continue
            kind = part.split(":", 1)[0]
            counts[kind] += 1
    return counts


def print_number_summary(label, summary):
    if summary is None:
        print(f"- {label}: n/a")
        return
    print(
        f"- {label}: avg {summary['avg']:.1f}, median {summary['median']:.1f}, "
        f"min {summary['min']:.1f}, max {summary['max']:.1f} (n={summary['count']})"
    )


def analyze(paths):
    rows = []
    for path in paths:
        with path.open(newline="", encoding="utf-8") as handle:
            for row in csv.DictReader(handle):
                row["_source_file"] = path.name
                rows.append(row)

    if not rows:
        raise SystemExit("No rows found.")

    passed = [row for row in rows if as_bool(row.get("passed"))]
    failed = [row for row in rows if not as_bool(row.get("passed"))]
    pass_rate = len(passed) / len(rows)
    run_ids = sorted(set(row.get("run_id", "") for row in rows))

    print("# Eval Analysis")
    print()
    print(f"Files: {', '.join(path.name for path in paths)}")
    print(f"Runs: {len(run_ids)}")
    print(f"Rows: {len(rows)}")
    print(f"Pass rate: {len(passed)}/{len(rows)} ({pass_rate:.1%})")
    print()

    print("## Pass Rate By Task")
    by_task = defaultdict(list)
    for row in rows:
        by_task[row.get("task", "unknown")].append(row)
    for task, task_rows in sorted(by_task.items()):
        task_passed = sum(1 for row in task_rows if as_bool(row.get("passed")))
        print(f"- {task}: {task_passed}/{len(task_rows)} ({task_passed / len(task_rows):.1%})")
    print()

    print("## Failure Reasons")
    counts = violation_counts(failed)
    if counts:
        for violation, count in counts.most_common():
            print(f"- {violation}: {count}")
    else:
        print("- none")
    print()

    print("## Worst Cases")
    by_case = defaultdict(list)
    for row in rows:
        by_case[row.get("id", "unknown")].append(row)
    case_summaries = []
    for case_id, case_rows in by_case.items():
        case_passed = sum(1 for row in case_rows if as_bool(row.get("passed")))
        case_summaries.append((case_passed / len(case_rows), case_id, case_rows))
    for rate, case_id, case_rows in sorted(case_summaries)[:10]:
        if rate >= 1:
            continue
        reasons = violation_counts([row for row in case_rows if not as_bool(row.get("passed"))])
        reason_text = ", ".join(f"{name} x{count}" for name, count in reasons.most_common()) or "error"
        print(f"- {case_id}: {rate:.1%} pass, {reason_text}")
    print()

    print("## Latency")
    print_number_summary("time_to_first_token_ms", summarize_number(rows, "time_to_first_token_ms"))
    print_number_summary("total_latency_ms", summarize_number(rows, "total_latency_ms"))
    print_number_summary("estimated_tokens_per_second", summarize_number(rows, "estimated_tokens_per_second"))
    print_number_summary("estimated_output_tokens", summarize_number(rows, "estimated_output_tokens"))
    print()

    print("## Failed Outputs")
    for row in failed:
        input_text = row.get("input", "").replace("\n", " ")
        expected = row.get("expected_behavior", "").replace("\n", " ")
        output = row.get("output", "").replace("\n", " ")
        if len(input_text) > 180:
            input_text = input_text[:177] + "..."
        if len(expected) > 180:
            expected = expected[:177] + "..."
        if len(output) > 220:
            output = output[:217] + "..."
        print(f"- {row.get('id')}: {row.get('violations') or row.get('error')}")
        if input_text:
            print(f"  Input: {input_text}")
        if expected:
            print(f"  Expected: {expected}")
        print(f"  {output}")


def main():
    parser = argparse.ArgumentParser(description="Analyze exported Model Lab eval CSV files.")
    parser.add_argument("csv", nargs="+", type=Path, help="One or more results.csv exports")
    args = parser.parse_args()
    analyze(args.csv)


if __name__ == "__main__":
    main()
