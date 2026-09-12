#!/usr/bin/env python3
"""Runtime state schema registry, migration and gate (EVO-035).

运行态文件由多个写入方产生（evolve.sh、test-failure-report.py、benchmark、
model-eval、rollback-drill.sh、maintenance.sh），字段演进时读者只能靠猜。
这里给每个 artifact 登记当前 schema 版本：

  * 新记录必须自带 schemaVersion（各写入方负责写入）；
  * v3 起 evolution_state*.json 额外记录 startedAt/durationSeconds/tokens/costUSD
    （token/成本可选，由 harness 通过 EVOLVE_RUN_TOKENS / EVOLVE_RUN_COST_USD 提供）；
  * `ensure` 给历史记录补写推断出的版本（原子、幂等、不新增/删除字段）；
  * `validate` 拒绝未知或未来版本（例如用旧代码解析新格式时应显式失败）；
  * 读者（Python/Swift/H5）保持宽容：缺字段不崩，门禁放在写入侧。

历史记录缺少 schemaVersion 时一律补成 LEGACY_VERSION(1)：低估版本是安全的，
高估会让旧代码误以为字段齐全。
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path

LEGACY_VERSION = 1


@dataclass(frozen=True)
class Artifact:
    """一个运行态 artifact 的 schema 契约。"""

    version: int          # 当前 schema 版本（写入方必须写这个值）
    kind: str             # "json"（单对象）或 "jsonl"（每行一条记录）
    latest_required: tuple[str, ...] = ()   # 最新一条记录至少包含的字段


ARTIFACTS: dict[str, Artifact] = {
    "evolution_state.json": Artifact(3, "json", ("status", "version")),
    "evolution_state_history.jsonl": Artifact(
        3, "jsonl", ("status", "version", "healthCheck", "worktreeVerified")),
    "evolution_progress.json": Artifact(1, "json", ("phase", "phaseIndex", "status")),
    "test_run_history.jsonl": Artifact(1, "jsonl", ("status", "ranAt")),
    "evolution_benchmark_history.jsonl": Artifact(1, "jsonl", ("score", "ranAt")),
    "model_eval_history.jsonl": Artifact(1, "jsonl", ("score",)),
    "rollback_drill_history.jsonl": Artifact(1, "jsonl", ("tag", "passed", "ranAt")),
    "maintenance_history.jsonl": Artifact(1, "jsonl", ("status", "ranAt")),
}


def default_state_dir() -> Path:
    explicit = os.environ.get("EVOLVE_STATE_DIR")
    if explicit:
        return Path(explicit).expanduser()
    return Path.home() / "Library" / "Application Support" / "Tapgo AICoding" / "state"


def read_jsonl(path: Path) -> list[tuple[int, str, dict | None]]:
    """返回 [(行号, 原始行, 解析结果或 None)]，空行已剔除。"""
    rows = []
    for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            obj = None
        rows.append((number, line, obj if isinstance(obj, dict) else None))
    return rows


def read_json_object(path: Path) -> tuple[dict | None, str]:
    try:
        data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except json.JSONDecodeError:
        return None, "invalid-json"
    if not isinstance(data, dict):
        return None, "not-an-object"
    return data, ""


def write_atomic(path: Path, text: str) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    try:
        mode = path.stat().st_mode & 0o777
    except OSError:
        mode = 0o600
    with tmp.open("w", encoding="utf-8") as fh:
        fh.write(text)
        fh.flush()
        os.fsync(fh.fileno())
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def scan(state_dir: Path) -> list[dict]:
    """检查所有已知 artifact；返回每个文件的报告。"""
    reports = []
    for name, artifact in ARTIFACTS.items():
        path = state_dir / name
        report = {
            "artifact": name, "path": str(path), "exists": path.exists(),
            "currentVersion": artifact.version, "kind": artifact.kind,
            "records": 0, "missing": 0, "legacy": 0, "future": 0,
            "invalid": [], "latestMissingKeys": [],
        }
        if not path.exists():
            reports.append(report)
            continue
        if artifact.kind == "json":
            obj, error = read_json_object(path)
            if obj is None:
                report["invalid"].append({"line": 1, "reason": error})
                reports.append(report)
                continue
            entries = [(1, json.dumps(obj, ensure_ascii=False), obj)]
        else:
            entries = read_jsonl(path)
        report["records"] = len(entries)
        for number, _raw, obj in entries:
            if obj is None:
                report["invalid"].append({"line": number, "reason": "invalid-json"})
                continue
            version = obj.get("schemaVersion")
            if version is None:
                report["missing"] += 1
            elif not isinstance(version, int):
                report["invalid"].append({"line": number, "reason": "schemaVersion-not-int"})
            elif version > artifact.version:
                report["future"] += 1
            elif version < LEGACY_VERSION:
                report["invalid"].append({"line": number, "reason": f"schemaVersion-{version}-too-old"})
            elif version < artifact.version:
                report["legacy"] += 1
        if entries and artifact.latest_required:
            last = entries[-1][2]
            if isinstance(last, dict):
                report["latestMissingKeys"] = [
                    key for key in artifact.latest_required if key not in last]
        reports.append(report)
    return reports


def problems(reports: list[dict]) -> list[str]:
    issues = []
    for report in reports:
        if not report["exists"]:
            continue
        name = report["artifact"]
        if report["invalid"]:
            first = report["invalid"][0]
            issues.append(f"{name}: 第 {first['line']} 行无法解析（{first['reason']}），共 {len(report['invalid'])} 处")
        if report["missing"]:
            issues.append(f"{name}: {report['missing']} 条记录缺 schemaVersion（跑 ensure 补齐）")
        if report["future"]:
            issues.append(
                f"{name}: {report['future']} 条记录 schemaVersion > {report['currentVersion']}"
                "，需要更新代码而不是降级解析")
        if report["latestMissingKeys"]:
            issues.append(f"{name}: 最新记录缺字段 {', '.join(report['latestMissingKeys'])}")
    return issues


def cmd_status(args: argparse.Namespace) -> int:
    state_dir = Path(args.state_dir).expanduser()
    reports = scan(state_dir)
    if args.json:
        print(json.dumps({"stateDir": str(state_dir), "artifacts": reports},
                         ensure_ascii=False, indent=2))
        return 0
    print(f"state dir: {state_dir}")
    for report in reports:
        if not report["exists"]:
            print(f"  -      {report['artifact']:38s} (absent)")
            continue
        versions = []
        if report["missing"]:
            versions.append(f"missing={report['missing']}")
        if report["legacy"]:
            versions.append(f"v<{report['currentVersion']}={report['legacy']}")
        if report["future"]:
            versions.append(f"future={report['future']}")
        detail = ", ".join(versions) if versions else f"v{report['currentVersion']}"
        print(f"  ok     {report['artifact']:38s} records={report['records']} {detail}")
    return 0


def cmd_ensure(args: argparse.Namespace) -> int:
    state_dir = Path(args.state_dir).expanduser()
    stamped_files = 0
    stamped_records = 0
    for name, artifact in ARTIFACTS.items():
        path = state_dir / name
        if not path.exists():
            continue
        changed = False
        if artifact.kind == "json":
            obj, error = read_json_object(path)
            if obj is None:
                print(f"WARN {name}: 无法解析（{error}），跳过", file=sys.stderr)
                continue
            if obj.get("schemaVersion") is None:
                obj["schemaVersion"] = LEGACY_VERSION
                write_atomic(path, json.dumps(obj, ensure_ascii=False, indent=2) + "\n")
                changed = True
                stamped_records += 1
        else:
            rows = read_jsonl(path)
            out_lines = []
            file_changed = False
            for _number, raw, obj in rows:
                if obj is None or obj.get("schemaVersion") is not None:
                    out_lines.append(raw)
                    continue
                obj = dict(obj)
                obj["schemaVersion"] = LEGACY_VERSION
                out_lines.append(json.dumps(obj, ensure_ascii=False))
                file_changed = True
                stamped_records += 1
            if file_changed:
                write_atomic(path, "\n".join(out_lines) + "\n")
                changed = True
        if changed:
            stamped_files += 1
            if not args.json:
                print(f"stamped {name}")
    reports = scan(state_dir)
    issues = problems(reports)
    if args.json:
        print(json.dumps({"stateDir": str(state_dir), "stampedFiles": stamped_files,
                          "stampedRecords": stamped_records, "issues": issues},
                         ensure_ascii=False, indent=2))
    elif not args.quiet:
        print(f"SCHEMA ENSURE: stamped {stamped_records} record(s) in {stamped_files} file(s)")
    if issues:
        for issue in issues:
            print(f"SCHEMA ERROR: {issue}", file=sys.stderr)
        return 13
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    state_dir = Path(args.state_dir).expanduser()
    reports = scan(state_dir)
    issues = problems(reports)
    if args.json:
        print(json.dumps({"stateDir": str(state_dir), "issues": issues, "artifacts": reports},
                         ensure_ascii=False, indent=2))
    if issues:
        for issue in issues:
            print(f"SCHEMA ERROR: {issue}", file=sys.stderr)
        return 13
    if not args.json and not args.quiet:
        known = [r for r in reports if r["exists"]]
        print(f"SCHEMA OK: {len(known)} artifact(s) 均在已知 schema 范围内")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--state-dir", default=str(default_state_dir()))
        p.add_argument("--json", action="store_true")

    p = sub.add_parser("status", help="列出已知 artifact 与版本分布")
    common(p)
    p.set_defaults(func=cmd_status)

    p = sub.add_parser("ensure", help="补齐历史记录缺失的 schemaVersion 并校验")
    common(p)
    p.add_argument("--quiet", action="store_true")
    p.set_defaults(func=cmd_ensure)

    p = sub.add_parser("validate", help="只校验，不写文件")
    common(p)
    p.add_argument("--quiet", action="store_true")
    p.set_defaults(func=cmd_validate)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
