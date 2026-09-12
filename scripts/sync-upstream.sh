#!/usr/bin/env bash
# sync-upstream.sh — 跟上上游,同时**保留**你的本地自进化改动。
#
# 用法:
#   ./scripts/sync-upstream.sh            # 预检:只报告差异,不动任何东西
#   ./scripts/sync-upstream.sh --apply    # 以 rebase 方式把本地演进叠到上游之上
#
# 解决什么问题:
#   你可能已经在本副本里自进化了好几轮,而上游也发布了新版本。
#   直接 `git pull` 要么冲突、要么覆盖你的改动。这个脚本先让你**看清**
#   双方各有多少 commit、分别是什么,再决定是否 rebase。
#
# 安全约定:
#   - 工作树不干净时直接拒绝(rebase 会丢改动)。
#   - 默认只预检;必须显式 --apply 才动历史。
#   - rebase 冲突时停下并给出 continue/abort 指引,不做任何自动 force。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/tapgo-repo-slug.sh
source "$ROOT/scripts/tapgo-repo-slug.sh"

APPLY=""
for arg in "$@"; do
  case "$arg" in
    --apply)   APPLY="1" ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "ERROR: 未知参数 $arg(可用: --apply / --help)" >&2; exit 2 ;;
  esac
done

UPSTREAM_REMOTE="$(tapgo_upstream_remote)"
UPSTREAM_REF="${UPSTREAM_REMOTE}/main"

echo "==> 1/4 工作树检查"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: 工作树有未提交改动,rebase 会丢失它们。请先 commit 或 stash:" >&2
  git status --short | sed 's/^/    /' >&2
  exit 3
fi
echo "    干净"

echo "==> 2/4 拉取上游 (${UPSTREAM_REMOTE})"
if ! git fetch "$UPSTREAM_REMOTE" --tags; then
  echo "ERROR: 无法从 ${UPSTREAM_REMOTE} 拉取。检查网络 / remote 配置:" >&2
  git remote -v | sed 's/^/    /' >&2
  exit 4
fi

LOCAL_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
AHEAD="$(git rev-list --count "${UPSTREAM_REF}..HEAD")"
BEHIND="$(git rev-list --count "HEAD..${UPSTREAM_REF}")"

echo "==> 3/4 差异"
echo "    当前分支:  ${LOCAL_BRANCH}"
echo "    本地领先:  ${AHEAD} 个 commit(你的自进化)"
echo "    上游领先:  ${BEHIND} 个 commit(别人的演进)"
if [[ "$AHEAD" -gt 0 ]]; then
  echo "    你的本地 commit:"
  git log --oneline "${UPSTREAM_REF}..HEAD" | sed 's/^/      /'
fi
if [[ "$BEHIND" -gt 0 ]]; then
  echo "    上游新 commit:"
  git log --oneline "HEAD..${UPSTREAM_REF}" | sed 's/^/      /'
fi

if [[ "$BEHIND" -eq 0 ]]; then
  echo "==> 已是最新,无需同步。"
  exit 0
fi

if [[ -z "$APPLY" ]]; then
  echo
  echo "==> 预检结束(未改动任何东西)。"
  if [[ "$AHEAD" -gt 0 ]]; then
    echo "    确认后执行:  ./scripts/sync-upstream.sh --apply"
    echo "    将把你的 ${AHEAD} 个本地 commit rebase 到 ${UPSTREAM_REF} 之上。"
  else
    echo "    本地没有独有 commit,可直接执行:  ./scripts/sync-upstream.sh --apply"
  fi
  exit 0
fi

echo "==> 4/4 rebase 到 ${UPSTREAM_REF}"
if git rebase "${UPSTREAM_REF}"; then
  echo "==> 同步完成:本地 ${AHEAD} 个 commit 已重放到上游之上。"
  echo "    建议:./scripts/build-app.sh 重建并安装你的定制版。"
else
  echo "ERROR: rebase 遇到冲突(未做任何自动处理)。" >&2
  echo "  逐文件解决:  编辑冲突文件 → git add <file> → git rebase --continue" >&2
  echo "  放弃本次同步: git rebase --abort" >&2
  exit 5
fi
