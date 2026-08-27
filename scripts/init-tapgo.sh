#!/usr/bin/env bash
# Initialize Tapgo AICoding's isolated Codex home.
#
# What this does:
#   1. Ensures the Codex CLI is installed (Homebrew cask, ≥ 0.149.1).
#   2. Sources the MiniMax-M3 bearer token from a single, explicit
#      source. We deliberately do NOT auto-migrate from old
#      ~/.codex/ backup files: those keys may be expired/revoked
#      (we have hit `1008 insufficient balance` / `1004 login fail`
#      on stale 8-month-old keys in this very repo). The user must
#      either:
#        - paste the key when prompted (input is hidden), or
#        - set MINIMAX_API_KEY / TAPGO_API_KEY in the environment, or
#      Optional safety net: an explicit `--from-file <path>` argument
#      reads from a file the user points us at (e.g. an internal vault
#      mount). We never probe ~/.codex/ on our own.
#   3. Writes the model catalog, config.toml, and auth.json under
#      ~/Library/Application Support/Tapgo AICoding/codex/ — the ONLY
#      directory Tapgo AICoding ever reads.
#   4. Verifies by spawning `codex app-server` against the isolated
#      home and checking the `initialize` response points at OUR
#      `codexHome` field (the harness echoes back the env we passed).
#
# This script never reads or writes anything under the official
# ~/.codex/ directory. It does not modify the user's environment
# beyond writing into the Tapgo AICoding Application Support subtree.

set -euo pipefail

APP_NAME="Tapgo AICoding"
CODEX_HOME="${HOME}/Library/Application Support/${APP_NAME}/codex"
CONFIG_FILE="${CODEX_HOME}/config.toml"
AUTH_FILE="${CODEX_HOME}/auth.json"
CATALOG_FILE="${CODEX_HOME}/model-catalogs/tapgo-catalog.json"
MIN_HARNESS_VERSION="0.149.1"
HARNESS_BIN_OVERRIDE="${HARNESS_BIN:-}"

resolve_harness_bin() {
  if [[ -n "${HARNESS_BIN_OVERRIDE}" ]]; then
    printf '%s\n' "${HARNESS_BIN_OVERRIDE}"
    return
  fi

  local path_codex=""
  path_codex="$(command -v codex 2>/dev/null || true)"

  local candidate
  for candidate in \
    /opt/homebrew/bin/codex \
    /usr/local/bin/codex \
    "${HOME}/.local/bin/codex" \
    "${path_codex}"; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return
    fi
  done

  return 1
}

version_at_least() {
  local actual="$1"
  local minimum="$2"
  local actual_major actual_minor actual_patch
  local minimum_major minimum_minor minimum_patch

  IFS=. read -r actual_major actual_minor actual_patch <<<"${actual}"
  IFS=. read -r minimum_major minimum_minor minimum_patch <<<"${minimum}"

  (( actual_major > minimum_major )) && return 0
  (( actual_major < minimum_major )) && return 1
  (( actual_minor > minimum_minor )) && return 0
  (( actual_minor < minimum_minor )) && return 1
  (( actual_patch >= minimum_patch ))
}

FROM_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-file) FROM_FILE="$2"; shift 2 ;;
    --region)    BASE_URL="$2"; shift 2 ;;
    -h|--help)
      cat <<USAGE
Usage: $0 [--from-file <path>]

Sources the MiniMax-M3 bearer key in this order (first hit wins):
  1. --from-file <path>        Read key from a specific file (single line).
  2. \$MINIMAX_API_KEY env var
  3. \$TAPGO_API_KEY env var
  4. Interactive prompt (input is hidden)

If none of those work, the script exits with a clear error and points
the user at the right env var.

Set HARNESS_BIN=/absolute/path/to/codex to use an explicit Codex CLI.
USAGE
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

echo "==> Initializing ${APP_NAME} isolated Codex home"
echo "    ${CODEX_HOME}"

# 1. Check for the codex harness.
echo
echo "==> Checking for Codex CLI"
if ! HARNESS_BIN="$(resolve_harness_bin)"; then
  echo "  ERROR: codex not found. Install with: brew install --cask codex" >&2
  exit 1
fi
if [[ ! -x "${HARNESS_BIN}" ]]; then
  echo "  ERROR: codex is not executable at ${HARNESS_BIN}" >&2
  exit 1
fi

HARNESS_VERSION_OUTPUT="$("${HARNESS_BIN}" --version 2>/dev/null || true)"
if [[ ! "${HARNESS_VERSION_OUTPUT}" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  echo "  ERROR: unable to determine Codex CLI version from: ${HARNESS_VERSION_OUTPUT:-<empty>}" >&2
  exit 1
fi
HARNESS_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
if ! version_at_least "${HARNESS_VERSION}" "${MIN_HARNESS_VERSION}"; then
  echo "  ERROR: Codex CLI ${HARNESS_VERSION} is too old; Tapgo AICoding requires >= ${MIN_HARNESS_VERSION}." >&2
  echo "         Upgrade with: brew upgrade --cask codex" >&2
  exit 1
fi
echo "  Found: ${HARNESS_VERSION_OUTPUT} (${HARNESS_BIN})"

mkdir -p "${CODEX_HOME}/model-catalogs"

# 2. Source the MiniMax-M3 bearer key. Explicit sources only — no
# auto-probing of ~/.codex/ to avoid ingesting stale/revoked keys.
echo
echo "==> Locating MiniMax-M3 bearer key (explicit sources only)"

KEY=""
KEY_SOURCE=""

if [[ -n "${FROM_FILE}" ]]; then
  if [[ ! -f "${FROM_FILE}" ]]; then
    echo "  ERROR: --from-file path does not exist: ${FROM_FILE}" >&2
    exit 1
  fi
  KEY="$(head -1 "${FROM_FILE}" | tr -d '\r\n')"
  KEY_SOURCE="file:${FROM_FILE}"
  echo "  ✓ Key loaded from ${FROM_FILE}."
fi

if [[ -z "${KEY}" && -n "${MINIMAX_API_KEY:-}" ]]; then
  KEY="${MINIMAX_API_KEY}"
  KEY_SOURCE="env(MINIMAX_API_KEY)"
  echo "  ✓ Key loaded from MINIMAX_API_KEY env var."
fi

if [[ -z "${KEY}" && -n "${TAPGO_API_KEY:-}" ]]; then
  KEY="${TAPGO_API_KEY}"
  KEY_SOURCE="env(TAPGO_API_KEY)"
  echo "  ✓ Key loaded from TAPGO_API_KEY env var."
fi

if [[ -z "${KEY}" ]]; then
  echo
  echo "  No key in env or --from-file. Paste the MiniMax-M3 bearer key below."
  echo "  (Input is hidden; key is stored 0600 in the isolated auth.json.)"
  read -r -s -p "  MiniMax API key: " KEY
  echo
  KEY_SOURCE="user-typed"
fi

if [[ -z "${KEY}" ]]; then
  echo "  ERROR: no API key provided" >&2
  exit 1
fi

# 3. Region. Default is the China endpoint, the only one we ship.
echo
echo "==> Region"
BASE_URL="${BASE_URL:-https://api.minimaxi.com/v1}"
echo "  Endpoint: ${BASE_URL}"
echo "  (override with --region <url>)"

# 4. Write isolated config files. These are the ONLY files Tapgo
# AICoding ever reads from this directory.
echo
echo "==> Writing isolated configuration"
echo "    auth.json     (0600)"
echo "    config.toml   (0600)"
echo "    tapgo-catalog.json"

# auth.json — the bearer lives here, never in config.toml.
umask 077
TMP_AUTH="$(mktemp "${AUTH_FILE}.XXXXXX")"
chmod 600 "${TMP_AUTH}"
python3 - "$TMP_AUTH" "$KEY" <<'PYEOF'
import json, sys
path, key = sys.argv[1], sys.argv[2]
with open(path, "w", encoding="utf-8") as f:
    json.dump({"OPENAI_API_KEY": key}, f, indent=2, sort_keys=True)
PYEOF
mv "${TMP_AUTH}" "${AUTH_FILE}"
chmod 600 "${AUTH_FILE}"

# config.toml — uses env_key so codex reads the bearer from auth.json
# at runtime via the OPENAI_API_KEY env var that Tapgo AICoding
# exports when spawning the harness. Nothing sensitive is hard-coded.
cat >"${CONFIG_FILE}" <<EOF
# Tapgo AICoding — isolated Codex home.
# Owned by ${APP_NAME}. Independent from ~/.codex/.

model = "MiniMax-M3"
model_provider = "minimax"
model_context_window = 1000000
model_catalog_json = "${CATALOG_FILE}"

[model_providers.minimax]
name = "MiniMax"
base_url = "${BASE_URL}"
wire_api = "responses"
env_key = "OPENAI_API_KEY"
EOF
chmod 600 "${CONFIG_FILE}"

# tapgo-catalog.json — MiniMax-M3 only.
cat >"${CATALOG_FILE}" <<'EOF'
{
  "models": [
    {
      "slug": "MiniMax-M3",
      "display_name": "MiniMax-M3",
      "description": "Tapgo AICoding 唯一可用模型。",
      "default_reasoning_level": "high",
      "supported_reasoning_levels": [
        { "effort": "none", "description": "Think-Off" },
        { "effort": "high", "description": "Deep" }
      ],
      "shell_type": "shell_command",
      "visibility": "list",
      "supported_in_api": true,
      "priority": 0,
      "base_instructions": "You are Tapgo AICoding, a coding agent powered by MiniMax-M3. You share the user's workspace and help achieve their coding goals. Be concise and direct.",
      "supports_reasoning_summaries": true,
      "default_reasoning_summary": "none",
      "support_verbosity": false,
      "truncation_policy": { "mode": "bytes", "limit": 10000 },
      "supports_parallel_tool_calls": true,
      "experimental_supported_tools": [],
      "input_modalities": ["text", "image"]
    }
  ]
}
EOF
chmod 644 "${CATALOG_FILE}"

# 5. Smoke-test: spawn the harness against the isolated home and
# confirm the initialize response points at OUR codexHome.
echo
echo "==> Verifying harness accepts the isolated config"
TMP_KEY_FILE="$(mktemp)"
chmod 600 "${TMP_KEY_FILE}"
cp "${AUTH_FILE}" "${TMP_KEY_FILE}"
# Drive the harness with one `initialize` request, then read stdout
# lines until we see the matching JSON-RPC response. We grab the
# first non-empty stdout line that starts with `{` (the harness
# may also write a banner to stderr — we ignore stderr entirely).
VERIFY_OUTPUT="$(
  CODEX_HOME="${CODEX_HOME}" \
  OPENAI_API_KEY="${KEY}" \
  "${HARNESS_BIN}" app-server --listen stdio:// 2>/dev/null \
    < <(sleep 0.3; printf '%s\n' '{"id":1,"method":"initialize","params":{"clientInfo":{"name":"tapgo-init","title":"init-tapgo","version":"0.0.1"}}}'; sleep 1) \
    | awk '/^\{/{print; exit}'
)"
rm -f "${TMP_KEY_FILE}"

if [[ -z "${VERIFY_OUTPUT}" ]]; then
  echo "  ERROR: harness produced no JSON response when launched against ${CODEX_HOME}" >&2
  exit 1
fi
if ! echo "${VERIFY_OUTPUT}" | grep -q "\"codexHome\":\"${CODEX_HOME}\""; then
  echo "  ERROR: harness did not pick up the isolated codexHome." >&2
  echo "    Expected: ${CODEX_HOME}" >&2
  echo "    Got:      ${VERIFY_OUTPUT}" >&2
  exit 1
fi
echo "  ✓ Harness reported codexHome=${CODEX_HOME}"

echo
echo "==> Done"
echo
echo "    Independent Codex home:  ${CODEX_HOME}"
echo "    Key source:              ${KEY_SOURCE}"
echo
echo "    Run:   ./scripts/build-app.sh && open 'Tapgo AICoding.app'"
echo "    Logs:  tail -f ~/Library/Logs/Tapgo\\ AICoding/harness.log"
