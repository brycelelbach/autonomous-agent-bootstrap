#!/usr/bin/env bash
# Bootstrap fresh, non-interactive Claude Code, Codex, and Pi installs on Linux.
#
# The script installs Claude Code, Codex, Brev, gh, base packages, agent
# plugins, git credentials, optional SSH keys, and unattended-mode config. It
# writes AAB runtime configuration to ~/.aab/.env and installs wrapper families
# that source that file:
#
#   claude plus claude-first-party-<profile> and claude-third-party-<profile>
#   codex plus codex-first-party-<profile> and codex-third-party-<profile>
#   pi plus pi-<profile>
#
# AAB_CLAUDE_DEFAULT_PROFILE and AAB_CODEX_DEFAULT_PROFILE select the
# unqualified launchers.
# Source remains part of each profile rather than being selected harness-wide.
#
# AAB_PI_DEFAULT_PROFILE selects the unqualified Pi launcher. Pi is always
# routed through the shared inference gateway, so its aliases omit
# "third-party".
#
# Provider credentials and model names are kept out of ~/.bashrc and
# /etc/environment. The managed ~/.bashrc block only puts ~/.local/bin on PATH
# and exports non-secret unattended-mode defaults.
#
# Can be run from a local checkout or piped via `curl ... | bash`. Safe to
# re-run: existing settings.json, config.toml, and .claude.json are backed up
# before overwrite, and AAB-managed wrapper/config files are replaced wholesale.
#
# Optional config input — settings using the env-var contract above can
# come in via either of two channels (in order of preference):
#
#   1. Positional arg: a path to a config file
#      (`bash bootstrap.bash ./aab.conf` or `curl ... | bash -s -- ./aab.conf`).
#   2. Stdin pipe: heredoc, file redirect, or any non-TTY stdin
#      (`bash bootstrap.bash <<EOF ... EOF`,
#       `bash <(curl ...) <<EOF ... EOF`).
#
# The file (or piped content) is sourced via `set -a; . file; set +a`, so
# it has full access to bash syntax: `${VAR:-default}`, `$(cmd)`, multi-
# line strings, comments. Values containing shell metacharacters (`&`,
# `|`, `;`, `$`, …) need to be quoted; plain `KEY=value` lines do not.
#
# Config-file and stdin assignments are authoritative over inherited shell
# values. To make an individual setting environment-overridable, express that
# in the config itself with `FOO="${FOO:-default}"`.

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
CLAUDE_MANAGED_SETTINGS_FILE="${CLAUDE_MANAGED_SETTINGS_FILE:-/etc/claude-code/managed-settings.json}"
CLAUDE_JSON="${HOME}/.claude.json"
AAB_DIR="${HOME}/.aab"
AAB_ENV_FILE="${AAB_DIR}/.env"
AAB_SHELL_CONFIG_DIR="${AAB_DIR}/shell"
CLAUDE_SHELL_CONFIG_FILE="${AAB_SHELL_CONFIG_DIR}/claude.env"
GITHUB_SHELL_CONFIG_FILE="${AAB_SHELL_CONFIG_DIR}/github.env"
CODEX_DIR="${HOME}/.codex"
CODEX_CONFIG="${CODEX_DIR}/config.toml"
CODEX_MODEL_INSTRUCTIONS_FILE="${CODEX_DIR}/codex-instructions.md"
CODEX_GATEWAY_MODEL_CATALOG="${AAB_DIR}/codex-gateway-model-catalog.json"
PI_DIR="${HOME}/.pi/agent"
PI_SETTINGS_FILE="${PI_DIR}/settings.json"
PI_MODELS_FILE="${PI_DIR}/models.json"
PI_MODELS_MARKER="${AAB_DIR}/pi-models-generated"
PI_NPM_DIR="${PI_DIR}/npm"
NODE_INSTALL_DIR="${HOME}/.local/share/aab/node"
BREV_DIR="${HOME}/.brev"
BREV_ONBOARDING="${BREV_DIR}/onboarding_step.json"
BASHRC="${HOME}/.bashrc"
PROFILE="${HOME}/.profile"
AAB_BOOTSTRAP_REPO="${AAB_BOOTSTRAP_REPO:-__AAB_BOOTSTRAP_REPO__}"
AAB_BOOTSTRAP_REF="${AAB_BOOTSTRAP_REF:-__AAB_BOOTSTRAP_REF__}"
BASHRC_MARKER_BEGIN="# >>> autonomous-agent-bootstrap >>>"
BASHRC_MARKER_END="# <<< autonomous-agent-bootstrap <<<"
SSH_DIR="${HOME}/.ssh"
SSH_CONFIG="${SSH_DIR}/config"
AUTH_KEY="${SSH_DIR}/id_aab_auth"
AUTH_KEY_PUB="${AUTH_KEY}.pub"
SIGNING_KEY="${SSH_DIR}/id_aab_signing"
SIGNING_KEY_PUB="${SIGNING_KEY}.pub"
GIT_ALLOWED_SIGNERS_FILE="${AAB_DIR}/git-allowed-signers"
SSH_MARKER_BEGIN="# >>> autonomous-agent-bootstrap >>>"
SSH_MARKER_END="# <<< autonomous-agent-bootstrap <<<"
GIT_HOOKS_DIR="${AAB_DIR}/git-hooks"
GIT_HOOK_DISPATCHER="${GIT_HOOKS_DIR}/aab-git-hook"
GITLEAKS_BIN="${HOME}/.local/bin/gitleaks"
# git hook names the dispatcher is symlinked under. core.hooksPath replaces
# the per-repo hooks dir wholesale, so we cover the hooks git invokes around a
# commit / push and chain through to any repo-local hook of the same name.
GIT_HOOK_NAMES=(
    pre-commit
    prepare-commit-msg
    commit-msg
    post-commit
    pre-merge-commit
    pre-rebase
    post-checkout
    post-merge
    pre-push
    post-rewrite
    applypatch-msg
    pre-applypatch
    post-applypatch
    sendemail-validate
)
CLAUDE_MEMORY_FILE="${CLAUDE_DIR}/CLAUDE.md"
CODEX_AGENTS_FILE="${CODEX_DIR}/AGENTS.md"
AGENT_RULES_STATE_FILE="${AAB_DIR}/agent-rules.snapshot"
# Path to the uv binary, resolved by install_uv and consumed by the uv tool
# install steps.
UV_BIN=""
DEFAULT_CLAUDE_CODE_MODEL="claude-opus-4-8"
DEFAULT_CLAUDE_CODE_HAIKU_MODEL="claude-haiku-4-5"
DEFAULT_CLAUDE_CODE_SONNET_MODEL="claude-sonnet-4-6"
DEFAULT_CLAUDE_CODE_OPUS_MODEL="claude-opus-4-8"
DEFAULT_CLAUDE_CODE_EFFORT="max"
DEFAULT_CODEX_MODEL="gpt-5.6-sol"
DEFAULT_CODEX_REASONING_EFFORT="ultra"
DEFAULT_PI_EFFORT="xhigh"
DEFAULT_CODEX_SERVICE_TIER="priority"
DEFAULT_CODEX_AGENT_MAX_THREADS="8"
DEFAULT_CLAUDE_FIRST_PARTY_PROFILES="${DEFAULT_CLAUDE_CODE_MODEL} model=${DEFAULT_CLAUDE_CODE_MODEL} haiku=${DEFAULT_CLAUDE_CODE_HAIKU_MODEL} sonnet=${DEFAULT_CLAUDE_CODE_SONNET_MODEL} opus=${DEFAULT_CLAUDE_CODE_OPUS_MODEL} effort=${DEFAULT_CLAUDE_CODE_EFFORT}"
DEFAULT_CLAUDE_THIRD_PARTY_PROFILES=""
DEFAULT_CODEX_FIRST_PARTY_PROFILES="${DEFAULT_CODEX_MODEL} model=${DEFAULT_CODEX_MODEL} effort=${DEFAULT_CODEX_REASONING_EFFORT} fast=true"
DEFAULT_CODEX_THIRD_PARTY_PROFILES=""
DEFAULT_PI_PROFILES=""
DEFAULT_CLAUDE_PROFILE="first-party/opus-4.8"
DEFAULT_CODEX_PROFILE="first-party/gpt-5.5"
DEFAULT_PI_PROFILE=""
log() { printf '[bootstrap] %s\n' "$*"; }
warn() { printf '[bootstrap] WARN: %s\n' "$*" >&2; }

_write_shell_export() {
    local name="$1" value="${2:-}"
    printf 'export %s=%q\n' "$name" "$value"
}

# Parse newline-delimited Header=Value entries without exposing values in
# generated Codex configuration or launcher arguments. Header names use a
# conservative token subset suitable for custom HTTP headers.
_parse_codex_gateway_http_headers() {
    local names_name="$1" values_name="$2"
    local -n names_ref="$names_name" values_ref="$values_name"
    names_ref=()
    values_ref=()

    local raw="${AAB_CODEX_GATEWAY_HTTP_HEADERS:-}"
    local line name value normalized line_number=0
    local -A seen=()
    while IFS= read -r line || [ -n "$line" ]; do
        line_number=$((line_number + 1))
        [ -n "$line" ] || continue
        if [[ "$line" != *=* ]]; then
            warn "AAB_CODEX_GATEWAY_HTTP_HEADERS entry ${line_number} must use Header=Value syntax."
            return 1
        fi
        name=${line%%=*}
        value=${line#*=}
        if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
            warn "AAB_CODEX_GATEWAY_HTTP_HEADERS entry ${line_number} has an invalid header name."
            return 1
        fi
        if [ -z "$value" ] || [[ "$value" =~ [[:cntrl:]] ]]; then
            warn "AAB_CODEX_GATEWAY_HTTP_HEADERS entry ${line_number} must have a non-empty single-line value."
            return 1
        fi
        normalized=${name,,}
        if [[ -v "seen[$normalized]" ]]; then
            warn "AAB_CODEX_GATEWAY_HTTP_HEADERS contains duplicate header names."
            return 1
        fi
        seen[$normalized]=1
        names_ref+=("$name")
        values_ref+=("$value")
    done <<< "$raw"
}

_codex_gateway_header_env_name() {
    printf 'AAB_CODEX_GATEWAY_HTTP_HEADER_%s' "$1"
}

need_sudo() {
    if [ "$(id -u)" -eq 0 ]; then echo ""; else echo "sudo"; fi
}
SUDO=$(need_sudo)
