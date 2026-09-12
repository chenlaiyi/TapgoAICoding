#!/usr/bin/env bash
# tapgo-repo-slug.sh — 共享的「仓库归属」解析(供 evolve.sh / release 脚本 source)。
#
# 背景:自进化原先硬编码了维护者仓库(chenlaiyi/TapgoAICoding),
# 其他用户 clone 后跑到发布步骤必然失败。这里把它变成可配置:
#
#   1. 显式覆盖:TAPGO_REPO_SLUG=owner/repo
#   2. 其次:UPSTREAM remote(适合 fork 工作流,upstream 指向上游)
#   3. 再次:origin remote
#
# 只定义函数,不产生副作用(source 安全)。

# 把各种 git remote URL 归一化成 owner/repo
_tapgo_slug_from_url() {
  local url="$1"
  [[ -z "$url" ]] && return 1
  url="${url%.git}"
  case "$url" in
    *github.com[:/]*)
      # git@github.com:owner/repo  或  https://github.com/owner/repo
      url="${url#*github.com}"
      url="${url#:}"
      url="${url#/}"
      ;;
  esac
  # 只保留 owner/repo 两段
  local owner repo
  owner="${url%%/*}"
  repo="${url#*/}"
  repo="${repo%%/*}"
  [[ -n "$owner" && -n "$repo" ]] || return 1
  printf '%s/%s\n' "$owner" "$repo"
}

# 解析当前仓库归属;失败返回非零(调用方决定是否降级)
tapgo_repo_slug() {
  if [[ -n "${TAPGO_REPO_SLUG:-}" ]]; then
    printf '%s\n' "$TAPGO_REPO_SLUG"
    return 0
  fi
  local remote url
  for remote in upstream origin; do
    url="$(git remote get-url "$remote" 2>/dev/null || true)"
    if _tapgo_slug_from_url "$url"; then
      return 0
    fi
  done
  return 1
}

# 上游 remote 名(有 upstream 用 upstream,否则 origin)
tapgo_upstream_remote() {
  if git remote get-url upstream >/dev/null 2>&1; then
    printf 'upstream\n'
  else
    printf 'origin\n'
  fi
}
