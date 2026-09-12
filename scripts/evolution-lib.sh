#!/usr/bin/env bash
# evolution-lib.sh — pure helpers for the self-evolution pipeline.
#
# This file is sourced by scripts/evolve.sh and by shell tests. It must not
# have side effects at source time.

# Pick the highest semver tag from stdin-or-args. Accepts vX.Y.Z only and
# treats leading zeros as decimal. Prints nothing when no valid version.
evo_max_version() {
  if [[ "$#" -gt 0 ]]; then
    printf '%s\n' "$@"
  else
    cat
  fi | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | awk -F'[v.]' '
    {
      major = $2 + 0; minor = $3 + 0; patch = $4 + 0
      if (NR == 1 || major > best_major ||
          (major == best_major && minor > best_minor) ||
          (major == best_major && minor == best_minor && patch > best_patch)) {
        best_major = major; best_minor = minor; best_patch = patch; best = $0
      }
    }
    END { if (best != "") print best }' || true
}

# evo_next_version <current (vX.Y.Z or X.Y.Z)> <patch|minor|major>
evo_next_version() {
  local current="${1#v}" bump="${2:-patch}"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$current"
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$patch" =~ ^[0-9]+$ ]] || return 2
  # Normalize leading zeros without relying on shell base# syntax.
  major="$(printf '%s' "$major" | sed 's/^0*//')"; major="${major:-0}"
  minor="$(printf '%s' "$minor" | sed 's/^0*//')"; minor="${minor:-0}"
  patch="$(printf '%s' "$patch" | sed 's/^0*//')"; patch="${patch:-0}"
  case "$bump" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
    *) return 3 ;;
  esac
  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

# evo_insert_evolution_entry <EVOLUTION.md> <new-entry-file>
# EVOLUTION.md is newest-first. Insert the new section immediately after the
# leading title line (or at the top when no title exists).
evo_insert_evolution_entry() {
  local target="$1" entry_file="$2"
  [[ -f "$target" && -f "$entry_file" ]] || return 2
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/tapgo-evolution.XXXXXX")"
  if head -1 "$target" | grep -q '^# '; then
    head -1 "$target" > "$tmp"
    printf '\n' >> "$tmp"
    cat "$entry_file" >> "$tmp"
    printf '\n' >> "$tmp"
    tail -n +2 "$target" >> "$tmp"
  else
    cat "$entry_file" >> "$tmp"
    printf '\n' >> "$tmp"
    cat "$target" >> "$tmp"
  fi
  mv "$tmp" "$target"
}

# evo_lock_acquire <lock-dir> — portable mkdir lock with stale-PID recovery.
evo_lock_acquire() {
  local lock_dir="$1"
  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" > "$lock_dir/pid"
    return 0
  fi
  local owner=""
  [[ -f "$lock_dir/pid" ]] && owner="$(cat "$lock_dir/pid" 2>/dev/null || true)"
  if [[ -n "$owner" ]] && kill -0 "$owner" 2>/dev/null; then
    return 1
  fi
  rm -rf "$lock_dir"
  mkdir "$lock_dir" 2>/dev/null || return 1
  printf '%s\n' "$$" > "$lock_dir/pid"
}

evo_lock_release() {
  local lock_dir="$1"
  local owner=""
  [[ -f "$lock_dir/pid" ]] && owner="$(cat "$lock_dir/pid" 2>/dev/null || true)"
  if [[ -z "$owner" || "$owner" == "$$" ]]; then
    rm -rf "$lock_dir"
  fi
}

# evo_path_covered <repo-relative-path> <allowed-path>...
# A path is covered when it equals an allowed path or lives under an allowed
# directory prefix. Returns 0/1 without printing.
evo_path_covered() {
  local candidate="$1"; shift
  local allowed
  for allowed in "$@"; do
    [[ -n "$allowed" ]] || continue
    if [[ "$candidate" == "$allowed" || "$candidate" == "$allowed"/* ]]; then
      return 0
    fi
  done
  return 1
}
