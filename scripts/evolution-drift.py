#!/usr/bin/env python3
"""EVO-055: 本机 App 版本漂移的单一真源。

背景：按约定发布流程不重启本机 App（重启会终止当前会话），于是 /Applications
已是新版、用户实际看到的界面可能仍是旧版。EVO-043 只记了一个 stale 布尔并打
WARN——它不会老化、不能随时查询、下一轮就没人记得。这里把漂移变成一个**有年龄、
可查询、可测试**的对象：

  * releasesBehind — 结构化记录里 (running, installed] 之间的版本数（不在记录
    覆盖范围内时给 null，不给错数）；
  * firstSeenAt / seenRuns — 同一个 running 版本被连续观察到多久、跨了几轮发布
    （seenRuns 按 run-id 去重，一轮内多次写 state 只算一次）；
  * remediation — 唯一的收敛动作；
  * line — 直接可读的一行。

子命令：
  compute --running <v> --installed <v> [--root DIR] [--state FILE] [--run-id ID] [--now ISO]
  check   [--state FILE]            # 有漂移则打印一行并退出 1，否则 0

本脚本是纯函数式/只读的（只读 state 与版本记录），不重启任何进程。
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import sys

VERSION_RE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")
RECORD_RE = re.compile(r"^v(.+)\.json$")
REMEDIATION = "./scripts/restart-and-resume.sh"
UNKNOWN_RUNNING = {"", "none", "unknown", "-"}


def parse_version(text: str):
    match = VERSION_RE.match((text or "").strip())
    if not match:
        return None
    return tuple(int(part) for part in match.groups())


def now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def repo_root_default() -> str:
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_previous_drift(state_path: str):
    if not state_path or not os.path.exists(state_path):
        return None
    try:
        with open(state_path, encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, ValueError):
        return None
    drift = (state.get("localApp") or {}).get("drift")
    return drift if isinstance(drift, dict) else None


def count_releases_between(root: str, running: str, installed: str):
    """结构化记录中 running < v <= installed 的条数。

    running 早于最早一条记录时返回 None：记录只覆盖 v0.5.258+ 之后，宁可说
    「未知」也不给一个偏小的数字。
    """
    versions_dir = os.path.join(root, "evolution", "versions")
    try:
        names = os.listdir(versions_dir)
    except OSError:
        return None
    recorded = []
    for name in names:
        match = RECORD_RE.match(name)
        if not match:
            continue
        parsed = parse_version(match.group(1))
        if parsed:
            recorded.append(parsed)
    low = parse_version(running)
    high = parse_version(installed)
    if not recorded or low is None or high is None:
        return None
    if low < min(recorded):
        return None
    return sum(1 for item in recorded if low < item <= high)


def short_date(iso_text: str) -> str:
    return iso_text[:10] if iso_text else "?"


def compute(args) -> dict:
    running = (args.running or "").strip()
    installed = (args.installed or "").strip()
    now = args.now or now_iso()
    previous = load_previous_drift(args.state)
    running_known = running.lower() not in UNKNOWN_RUNNING
    same_as_installed = running_known and running.lstrip("v") == installed.lstrip("v")

    if same_as_installed:
        return {
            "installed": installed,
            "running": running,
            "stale": False,
            "releasesBehind": 0,
            "firstSeenAt": None,
            "lastSeenAt": now,
            "seenRuns": 0,
            "seenRunId": None,
            "remediation": None,
            "line": "本机 App 与已安装版本一致（%s）" % installed,
        }

    releases_behind = count_releases_between(args.root, running, installed) if running_known else None

    if previous and previous.get("running") == running and previous.get("firstSeenAt"):
        first_seen = previous["firstSeenAt"]
        seen_runs = int(previous.get("seenRuns") or 0)
        if previous.get("seenRunId") != (args.run_id or None):
            seen_runs += 1
    else:
        first_seen = now
        seen_runs = 1

    behind_text = "落后 %d 个版本" % releases_behind if releases_behind is not None else "落后版本数未知"
    if running_known:
        line = "本机 App 落后：运行 %s / 已安装 %s（%s，自 %s 起，已累计 %d 轮）：%s" % (
            running, installed, behind_text, short_date(first_seen), seen_runs, REMEDIATION)
    else:
        line = "本机 App 最近版本未知（未检测到运行中进程）；已安装 %s：%s" % (installed, REMEDIATION)

    return {
        "installed": installed,
        "running": running or "none",
        "stale": True,
        "releasesBehind": releases_behind,
        "firstSeenAt": first_seen,
        "lastSeenAt": now,
        "seenRuns": seen_runs,
        "seenRunId": args.run_id or None,
        "remediation": REMEDIATION,
        "line": line,
    }


def check(args) -> int:
    state_path = args.state
    try:
        with open(state_path, encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, ValueError) as error:
        print("本机 App 漂移状态不可读：%s（%s）" % (state_path, error), file=sys.stderr)
        return 2
    local_app = state.get("localApp") or {}
    drift = local_app.get("drift") or {}
    if local_app.get("stale") is True:
        line = drift.get("line") or "本机 App 落后：运行 %s / 已安装 %s：%s" % (
            local_app.get("running"), local_app.get("installed"), REMEDIATION)
        print(line)
        return 1
    print("本机 App 版本一致：%s" % (local_app.get("installed") or "unknown"))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="本机 App 版本漂移真源（EVO-055）")
    sub = parser.add_subparsers(dest="command", required=True)

    compute_parser = sub.add_parser("compute", help="计算漂移元数据并输出 JSON")
    compute_parser.add_argument("--running", required=True)
    compute_parser.add_argument("--installed", required=True)
    compute_parser.add_argument("--root", default=repo_root_default())
    compute_parser.add_argument("--state", default="")
    compute_parser.add_argument("--run-id", default="")
    compute_parser.add_argument("--now", default="")

    check_parser = sub.add_parser("check", help="读 state 判断是否仍有漂移（有则退出 1）")
    check_parser.add_argument(
        "--state",
        default=os.path.join(os.path.expanduser("~"), "Library", "Application Support",
                             "Tapgo AICoding", "state", "evolution_state.json"),
    )
    return parser


def main(argv) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "compute":
        json.dump(compute(args), sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0
    return check(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
