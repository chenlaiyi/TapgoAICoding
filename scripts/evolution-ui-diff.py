#!/usr/bin/env python3
"""Compare two evolution UI snapshots (baseline vs candidate).

EVO-044：`preview-evolution-ui.sh` 的离屏渲染在同一台机器上是**确定**的
（实测两次渲染逐字节一致），所以可以拿一张基线图做像素回归门禁。

比对策略（从强到弱）：
  1. 字节完全相同 → 直接通过（最常见，零成本）；
  2. 装了 Pillow → 逐像素比较，按“通道差 > --channel-threshold 的像素占比”
     与 --tolerance 判定，并给出差异 bbox / 最大通道差；
  3. 没装 Pillow 且字节不同 → 以 exit 3 明确报告“无法比对”，而不是假装通过。

退出码：0 通过 / 1 超容差 / 2 用法或读图错误 / 3 缺 Pillow 无法比对
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def load_pillow():
    try:
        from PIL import Image, ImageChops  # type: ignore

        return Image, ImageChops
    except Exception:
        return None, None


def compare(baseline: Path, candidate: Path, tolerance: float, channel_threshold: int) -> dict:
    baseline_bytes = baseline.read_bytes()
    candidate_bytes = candidate.read_bytes()
    result = {
        "baseline": str(baseline),
        "candidate": str(candidate),
        "tolerance": tolerance,
        "channelThreshold": channel_threshold,
        "byteIdentical": baseline_bytes == candidate_bytes,
    }
    if result["byteIdentical"]:
        result.update({"differingRatio": 0.0, "maxChannelDelta": 0, "sizeMatch": True, "method": "bytes"})
        return result

    Image, ImageChops = load_pillow()
    if Image is None:
        result.update({"method": "unavailable", "reason": "Pillow 未安装，且两份快照字节不同"})
        return result

    with Image.open(baseline) as base_img, Image.open(candidate) as cand_img:
        base = base_img.convert("RGB")
        cand = cand_img.convert("RGB")
        result["method"] = "pixels"
        result["sizeMatch"] = base.size == cand.size
        result["baselineSize"] = list(base.size)
        result["candidateSize"] = list(cand.size)
        if base.size != cand.size:
            result.update({"differingRatio": 1.0, "maxChannelDelta": 255})
            return result

        diff = ImageChops.difference(base, cand)
        bbox = diff.getbbox()
        max_delta = 0
        differing = 0
        total = base.size[0] * base.size[1]
        for pixel in diff.getdata():
            peak = max(pixel)
            if peak > max_delta:
                max_delta = peak
            if peak > channel_threshold:
                differing += 1
        result.update({
            "differingPixels": differing,
            "totalPixels": total,
            "differingRatio": differing / total if total else 0.0,
            "maxChannelDelta": max_delta,
            "diffBBox": list(bbox) if bbox else None,
        })
        return result


def write_diff_image(baseline: Path, candidate: Path, out: Path) -> bool:
    Image, ImageChops = load_pillow()
    if Image is None:
        return False
    with Image.open(baseline) as base_img, Image.open(candidate) as cand_img:
        diff = ImageChops.difference(base_img.convert("RGB"), cand_img.convert("RGB"))
        out.parent.mkdir(parents=True, exist_ok=True)
        diff.save(out)
    return True


def cmd_compare(args: argparse.Namespace) -> int:
    baseline, candidate = Path(args.baseline), Path(args.candidate)
    for path in (baseline, candidate):
        if not path.exists():
            print(f"ERROR: 找不到快照 {path}", file=sys.stderr)
            return 2
    try:
        result = compare(baseline, candidate, args.tolerance, args.channel_threshold)
    except Exception as exc:  # 读图/解码失败都算用法错误
        print(f"ERROR: 比对失败 {exc}", file=sys.stderr)
        return 2

    if result.get("method") == "unavailable":
        if args.json:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        print(f"UI DIFF UNAVAILABLE: {result['reason']}（baseline={baseline} candidate={candidate}）",
              file=sys.stderr)
        return 3

    passed = result.get("sizeMatch", True) and result.get("differingRatio", 1.0) <= args.tolerance
    result["passed"] = passed

    if args.diff_out and not passed:
        result["diffImage"] = str(args.diff_out) if write_diff_image(baseline, candidate, args.diff_out) else None

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        if result.get("byteIdentical"):
            print(f"UI DIFF OK (byte-identical) baseline={baseline.name}")
        else:
            print(f"UI DIFF ratio={result.get('differingRatio', 1.0):.6f} "
                  f"maxDelta={result.get('maxChannelDelta')} bbox={result.get('diffBBox')}")
    if not passed:
        print(f"UI DIFF FAILED: 与基线差异超过容差 {args.tolerance}（candidate={candidate}）", file=sys.stderr)
        return 1
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("compare")
    p.add_argument("baseline")
    p.add_argument("candidate")
    p.add_argument("--tolerance", type=float, default=0.001)  # 0.1% 像素
    p.add_argument("--channel-threshold", type=int, default=8)
    p.add_argument("--json", action="store_true")
    p.add_argument("--diff-out", default=None)
    p.set_defaults(func=cmd_compare)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
