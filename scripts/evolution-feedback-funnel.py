#!/usr/bin/env python3
"""Quantify the user-feedback loop: drafts → registered checks → shipped releases.

三个阶段（EVO-038）：
  * draft      — `evolution/feedback/drafts.json` 里的一条候选（带 discoveredAt）
  * registered — `evolution/feedback/registry.json` 里带可复现 check 的条目
                 （registeredAt 记录入库日期；sourceDraft 回指草稿）
  * shipped    — 条目带 fixedIn（真正修掉该问题的发布版本）

只在两侧时间都可信时统计等待时长：`fixedIn` 早于 `registeredAt` 的条目属于
“回填”（注册表建立前就修好了），只计入 shipped 计数，不编造等待时长。
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import statistics
import sys
from pathlib import Path

DEFAULT_STALE_DAYS = 30
VERSION_RE = re.compile(r"^v?\d+\.\d+")


def repo_root(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).resolve()
    return Path(__file__).resolve().parent.parent


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def parse_day(value: object) -> dt.date | None:
    """只接受日期/ISO 时间戳；版本号（v0.5.72）不是日期。"""
    if value is None:
        return None
    text = str(value).strip()
    if not text or VERSION_RE.match(text):
        return None
    try:
        return dt.datetime.fromisoformat(text.replace("Z", "+00:00")).date()
    except ValueError:
        return None


def release_dates(root: Path) -> dict[str, dt.date]:
    """evolution/versions/vX.Y.Z.json → {tag: 发布日}。"""
    out: dict[str, dt.date] = {}
    for path in sorted((root / "evolution" / "versions").glob("v*.json")):
        data = load_json(path)
        tag = str(data.get("tag") or ("v" + str(data.get("version", ""))))
        day = parse_day(data.get("date"))
        if tag != "v" and day:
            out[tag] = day
    return out


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    xs = sorted(values)
    if len(xs) == 1:
        return xs[0]
    position = (len(xs) - 1) * fraction
    low = int(position)
    high = min(low + 1, len(xs) - 1)
    return xs[low] + (xs[high] - xs[low]) * (position - low)


def days_between(later: dt.date | None, earlier: dt.date | None) -> int | None:
    if later is None or earlier is None:
        return None
    return (later - earlier).days


def compute(root: Path, stale_days: int, today: dt.date | None = None) -> dict:
    drafts = load_json(root / "evolution" / "feedback" / "drafts.json").get("drafts", [])
    registry = load_json(root / "evolution" / "feedback" / "registry.json").get("entries", [])
    releases = release_dates(root)
    now = today or dt.datetime.now(dt.timezone.utc).date()

    promoted_ids = {str(e.get("sourceDraft")) for e in registry if e.get("sourceDraft")}
    draft_promoted = sum(1 for d in drafts if str(d.get("id")) in promoted_ids)
    draft_total = len(drafts)
    draft_open = draft_total - draft_promoted

    stale_drafts = 0
    for draft in drafts:
        if str(draft.get("id")) in promoted_ids:
            continue
        age = days_between(now, parse_day(draft.get("discoveredAt")))
        if age is not None and age > stale_days:
            stale_drafts += 1

    registered = len(registry)
    shipped_entries = [e for e in registry if e.get("fixedIn")]
    shipped = len(shipped_entries)
    stale_registered = 0
    for entry in registry:
        if entry.get("fixedIn"):
            continue
        age = days_between(now, parse_day(entry.get("registeredAt")))
        if age is not None and age > stale_days:
            stale_registered += 1

    draft_to_registered: list[int] = []
    end_to_end_shipped = 0
    for entry in registry:
        reg_day = parse_day(entry.get("registeredAt"))
        source_id = str(entry.get("sourceDraft") or "")
        source = next((d for d in drafts if str(d.get("id")) == source_id), None)
        disc_day = parse_day(source.get("discoveredAt")) if source else None
        wait = days_between(reg_day, disc_day)
        if wait is not None and wait >= 0:
            draft_to_registered.append(wait)
        if source is not None and entry.get("fixedIn"):
            end_to_end_shipped += 1

    registered_to_shipped: list[int] = []
    backfilled = 0
    unknown_timing = 0
    for entry in shipped_entries:
        reg_day = parse_day(entry.get("registeredAt"))
        ship_day = releases.get(str(entry.get("fixedIn")))
        wait = days_between(ship_day, reg_day)
        if wait is None:
            unknown_timing += 1
        elif wait < 0:
            backfilled += 1
        else:
            registered_to_shipped.append(wait)

    def rate(numerator: int, denominator: int) -> float | None:
        return round(numerator / denominator, 4) if denominator else None

    return {
        "drafts": {
            "total": draft_total,
            "open": draft_open,
            "promoted": draft_promoted,
            "staleOverDays": stale_drafts,
        },
        "registered": {
            "total": registered,
            "shipped": shipped,
            "unshipped": registered - shipped,
            "staleOverDays": stale_registered,
        },
        "conversion": {
            "draftToRegistered": rate(draft_promoted, draft_total),
            "registeredToShipped": rate(shipped, registered),
            "draftToShipped": rate(end_to_end_shipped, draft_total),
        },
        "waitsDays": {
            "draftToRegisteredMedian": statistics.median(draft_to_registered) if draft_to_registered else None,
            "draftToRegisteredP95": percentile([float(v) for v in draft_to_registered], 0.95),
            "draftToRegisteredSamples": len(draft_to_registered),
            "registeredToShippedMedian": statistics.median(registered_to_shipped) if registered_to_shipped else None,
            "registeredToShippedP95": percentile([float(v) for v in registered_to_shipped], 0.95),
            "registeredToShippedSamples": len(registered_to_shipped),
        },
        "backfilledShipped": backfilled,
        "unknownTimingShipped": unknown_timing,
        "staleDays": stale_days,
    }


def format_wait(value: float | None) -> str:
    return "n/a" if value is None else f"{value:.1f}d"


def format_rate(value: float | None) -> str:
    return "n/a" if value is None else f"{value * 100:.1f}%"


def cmd_report(args: argparse.Namespace) -> int:
    root = repo_root(args.root)
    result = compute(root, args.stale_days)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        drafts = result["drafts"]
        registered = result["registered"]
        conversion = result["conversion"]
        waits = result["waitsDays"]
        print(f"feedback drafts:    total={drafts['total']} open={drafts['open']} "
              f"promoted={drafts['promoted']} stale(>{result['staleDays']}d)={drafts['staleOverDays']}")
        print(f"registered checks:  total={registered['total']} shipped={registered['shipped']} "
              f"unshipped={registered['unshipped']} stale(>{result['staleDays']}d)={registered['staleOverDays']}")
        print(f"conversion:         draft→registered={format_rate(conversion['draftToRegistered'])} "
              f"registered→shipped={format_rate(conversion['registeredToShipped'])} "
              f"draft→shipped={format_rate(conversion['draftToShipped'])}")
        print(f"wait draft→reg:     median={format_wait(waits['draftToRegisteredMedian'])} "
              f"p95={format_wait(waits['draftToRegisteredP95'])} n={waits['draftToRegisteredSamples']}")
        print(f"wait reg→shipped:   median={format_wait(waits['registeredToShippedMedian'])} "
              f"p95={format_wait(waits['registeredToShippedP95'])} n={waits['registeredToShippedSamples']} "
              f"(backfilled={result['backfilledShipped']} "
              f"unknownReleaseDate={result['unknownTimingShipped']})")
    if args.fail_on_stale and (result["drafts"]["staleOverDays"] or result["registered"]["staleOverDays"]):
        print("FEEDBACK FUNNEL STALE: 存在超过阈值的草稿或未发布条目", file=sys.stderr)
        return 1
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("report")
    p.add_argument("--root", default=None)
    p.add_argument("--stale-days", type=int, default=DEFAULT_STALE_DAYS)
    p.add_argument("--json", action="store_true")
    p.add_argument("--fail-on-stale", action="store_true")
    p.set_defaults(func=cmd_report)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
