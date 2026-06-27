#!/usr/bin/env bash
# Bootstrap fresh, non-interactive Claude Code and Codex installs on a Linux host.
#
# The script installs Claude Code, Codex, Brev, gh, base packages, agent
# plugins, git credentials, optional SSH keys, and unattended-mode config. It
# writes AAB runtime configuration to ~/.aab/.env and installs wrapper families
# that source that file:
#
#   claude plus claude-first-party, claude-third-party-anthropic,
#   claude-third-party-deepseek, and claude-third-party-nemotron
#   codex plus codex-first-party and codex-third-party-openai
#
# AAB_CLAUDE_CODE_INFERENCE_PROVIDER selects the unqualified claude launcher:
#   first-party, third-party-anthropic, third-party-deepseek, or third-party-nemotron.
#
# AAB_CODEX_INFERENCE_PROVIDER selects the unqualified codex launcher:
#   first-party or third-party-openai.
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
# Caller-supplied env vars beat file values: `FOO=override bash
# bootstrap.bash aab.conf` is a one-line debug override without touching
# the file. An explicitly-empty `FOO= bash …` counts as set and still
# wins.

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
CLAUDE_MANAGED_SETTINGS_FILE="${CLAUDE_MANAGED_SETTINGS_FILE:-/etc/claude-code/managed-settings.json}"
CLAUDE_JSON="${HOME}/.claude.json"
AAB_DIR="${HOME}/.aab"
AAB_ENV_FILE="${AAB_DIR}/.env"
CODEX_DIR="${HOME}/.codex"
CODEX_CONFIG="${CODEX_DIR}/config.toml"
CODEX_MODEL_INSTRUCTIONS_FILE="${CODEX_DIR}/codex-instructions.md"
BREV_DIR="${HOME}/.brev"
BREV_ONBOARDING="${BREV_DIR}/onboarding_step.json"
BASHRC="${HOME}/.bashrc"
PROFILE="${HOME}/.profile"
BASHRC_MARKER_BEGIN="# >>> autonomous-agent-bootstrap >>>"
BASHRC_MARKER_END="# <<< autonomous-agent-bootstrap <<<"
SSH_DIR="${HOME}/.ssh"
SSH_CONFIG="${SSH_DIR}/config"
AUTH_KEY="${SSH_DIR}/id_aab_auth"
AUTH_KEY_PUB="${AUTH_KEY}.pub"
SIGNING_KEY="${SSH_DIR}/id_aab_signing"
SIGNING_KEY_PUB="${SIGNING_KEY}.pub"
SSH_MARKER_BEGIN="# >>> autonomous-agent-bootstrap >>>"
SSH_MARKER_END="# <<< autonomous-agent-bootstrap <<<"
GIT_HOOKS_DIR="${AAB_DIR}/git-hooks"
GIT_HOOK_DISPATCHER="${GIT_HOOKS_DIR}/aab-git-hook"
# gitleaks powers the pre-commit secret scan the dispatcher runs. Pin the
# version (and per-arch tarball SHA-256) to match the version CI's secret-scan
# job and AGENTS.md install snippet use, so "blocked locally" == "blocked in
# CI". Installed to ~/.local/bin (the dir the managed PATH front-loads).
GITLEAKS_VERSION="8.18.4"
GITLEAKS_BIN="${HOME}/.local/bin/gitleaks"
GITLEAKS_SHA256_LINUX_X64="ba6dbb656933921c775ee5a2d1c13a91046e7952e9d919f9bac4cec61d628e7d"
GITLEAKS_SHA256_LINUX_ARM64="bf5f7f466ebfade1296c8bd32cf7d3f592c2aa78836aa9980ffbe2cadca7a861"
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
AGENT_RULES_MARKER_BEGIN="# >>> autonomous-agent-bootstrap >>>"
AGENT_RULES_MARKER_END="# <<< autonomous-agent-bootstrap <<<"
ETC_ENV="/etc/environment"
ETC_ENV_MARKER_BEGIN="# >>> autonomous-agent-bootstrap >>>"
ETC_ENV_MARKER_END="# <<< autonomous-agent-bootstrap <<<"
# Path to the uv binary, resolved by ensure_uv and consumed by the uv tool
# install steps.
UV_BIN=""
# Private autocuda package, installed best-effort as its own uv tool.
AUTOCUDA_PRIVATE_REPO="brycelelbach-private/autocuda"
DEFAULT_CLAUDE_CODE_MODEL="claude-opus-4-8"
DEFAULT_CLAUDE_CODE_HAIKU_MODEL="claude-haiku-4-5"
DEFAULT_CLAUDE_CODE_SONNET_MODEL="claude-sonnet-4-6"
DEFAULT_CLAUDE_CODE_OPUS_MODEL="claude-opus-4-8"
DEFAULT_CLAUDE_CODE_EFFORT="max"
DEFAULT_CODEX_MODEL="gpt-5.5"
DEFAULT_CLAUDE_CODE_INFERENCE_PROVIDER="first-party"
DEFAULT_CODEX_INFERENCE_PROVIDER="first-party"
DEFAULT_CODEX_THIRD_PARTY_OPENAI_MODEL="openai/openai/gpt-5.5"
DEFAULT_CODEX_THIRD_PARTY_OPENAI_BASE_URL="https://inference-api.nvidia.com/v1"
DEFAULT_CODEX_THIRD_PARTY_NEMOTRON_MODEL="nvidia/nemotron-3-ultra"
DEFAULT_CODEX_THIRD_PARTY_NEMOTRON_BASE_URL="https://integrate.api.nvidia.com/v1"
DEFAULT_CODEX_THIRD_PARTY_DEEPSEEK_MODEL="deepseek/deepseek-v4-pro"
DEFAULT_CODEX_THIRD_PARTY_DEEPSEEK_BASE_URL="https://api.deepseek.com/v1"
DEFAULT_CODEX_REASONING_EFFORT="xhigh"
DEFAULT_CODEX_SERVICE_TIER="priority"
DEFAULT_CODEX_AGENT_MAX_THREADS="64"
log() { printf '[bootstrap] %s\n' "$*"; }
warn() { printf '[bootstrap] WARN: %s\n' "$*" >&2; }

normalize_claude_code_inference_provider() {
    local provider="${1:-$DEFAULT_CLAUDE_CODE_INFERENCE_PROVIDER}"
    case "$provider" in
        first-party|third-party-anthropic|third-party-deepseek|third-party-nemotron)
            printf '%s' "$provider"
            ;;
        *)
            warn "AAB_CLAUDE_CODE_INFERENCE_PROVIDER='${provider}' is not 'first-party', 'third-party-anthropic', 'third-party-deepseek', or 'third-party-nemotron'; defaulting to '${DEFAULT_CLAUDE_CODE_INFERENCE_PROVIDER}'."
            printf '%s' "$DEFAULT_CLAUDE_CODE_INFERENCE_PROVIDER"
            ;;
    esac
}

normalize_codex_inference_provider() {
    local provider="${1:-$DEFAULT_CODEX_INFERENCE_PROVIDER}"
    case "$provider" in
        first-party|third-party-openai|third-party-nemotron|third-party-deepseek)
            printf '%s' "$provider"
            ;;
        *)
            warn "AAB_CODEX_INFERENCE_PROVIDER='${provider}' is not 'first-party', 'third-party-openai', 'third-party-nemotron', or 'third-party-deepseek'; defaulting to '${DEFAULT_CODEX_INFERENCE_PROVIDER}'."
            printf '%s' "$DEFAULT_CODEX_INFERENCE_PROVIDER"
            ;;
    esac
}

_write_shell_export() {
    local name="$1" value="${2:-}"
    printf 'export %s=%q\n' "$name" "$value"
}

need_sudo() {
    if [ "$(id -u)" -eq 0 ]; then echo ""; else echo "sudo"; fi
}
SUDO=$(need_sudo)

# ---------------------------------------------------------------------------
# 0. Install the Debian base dependencies listed in apt_packages.txt via
# apt-get. Bare container images (e.g. ubuntu:22.04) ship with apt-get but
# nothing else, so we can't assume curl or python3 exist. apt no-ops packages
# that are already installed, so the whole list is installed unconditionally.
#
# The list is taken from (in order): $AAB_APT_PACKAGES_FILE, then
# ./apt_packages.txt when present, otherwise $AAB_APT_PACKAGES_URL.
# ---------------------------------------------------------------------------
APT_PACKAGES_DEFAULT_FILE="${PWD}/apt_packages.txt"
APT_PACKAGES_DEFAULT_URL="https://raw.githubusercontent.com/brycelelbach/autonomous-agent-bootstrap/main/apt_packages.txt"
install_base_deps() {
    local packages_file="${AAB_APT_PACKAGES_FILE:-}"
    local packages_url="${AAB_APT_PACKAGES_URL:-$APT_PACKAGES_DEFAULT_URL}"
    local content=""
    if [ -n "$packages_file" ] && [ -f "$packages_file" ]; then
        content=$(cat "$packages_file")
        log "Reading apt package list from ${packages_file}."
    elif [ -z "$packages_file" ] && [ -f "$APT_PACKAGES_DEFAULT_FILE" ]; then
        content=$(cat "$APT_PACKAGES_DEFAULT_FILE")
        log "Reading apt package list from ${APT_PACKAGES_DEFAULT_FILE}."
    elif content=$(curl -fsSL "$packages_url" 2>/dev/null); then
        log "Fetched apt package list from ${packages_url}."
    else
        warn "Could not read apt package list (file=${packages_file:-unset}, url=${packages_url}); skipping base dep install."
        return
    fi

    # Strip comments and blanks into one package per line.
    local -a packages=()
    while IFS= read -r line; do
        line="${line%%#*}"
        # trim
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] && continue
        packages+=("$line")
    done <<< "$content"

    if [ ${#packages[@]} -eq 0 ]; then
        log "apt package list is empty; skipping base dep install."
        return
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
        warn "Base deps (${packages[*]}) needed and apt-get is not available; install them manually and re-run."
        return
    fi
    if [ -n "$SUDO" ] && ! sudo -n true 2>/dev/null; then
        warn "Base deps (${packages[*]}) needed and passwordless sudo is not available; install them manually and re-run."
        return
    fi

    log "Installing base deps: ${packages[*]}."
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -y
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
}

# ---------------------------------------------------------------------------
# 0b. Enable user lingering so the per-user systemd instance — and its bus at
# $XDG_RUNTIME_DIR/bus — stays up across SSH sessions instead of dying with the
# login session. Unattended agent workloads that wrap commands in
# `systemd-run --user --scope` (e.g. autocuda's `run slice`, which caps build
# CPU/memory) need the user bus available even when no interactive session is
# open. `loginctl enable-linger` is the one-time setup for that. Skip cleanly on
# hosts without a systemd user manager (bare containers) or without sudo.
# ---------------------------------------------------------------------------
enable_user_linger() {
    local user
    user=$(id -un)

    if ! command -v loginctl >/dev/null 2>&1; then
        log "loginctl not available (no systemd); skipping user-linger setup."
        return
    fi

    # Already lingering: keep re-runs quiet and avoid a needless sudo call.
    if [ "$(loginctl show-user "$user" --property=Linger --value 2>/dev/null)" = "yes" ]; then
        log "User lingering already enabled for ${user}."
        return
    fi

    if [ -n "$SUDO" ] && ! sudo -n true 2>/dev/null; then
        warn "Enabling user lingering for ${user} needs sudo and passwordless sudo is not available; run 'sudo loginctl enable-linger ${user}' so the user systemd bus stays up across sessions."
        return
    fi

    if $SUDO loginctl enable-linger "$user" 2>/dev/null; then
        log "Enabled user lingering for ${user} (user systemd bus stays up across sessions)."
    else
        warn "Could not enable user lingering for ${user}; run 'sudo loginctl enable-linger ${user}' so the user systemd bus stays up across sessions."
    fi
}

# ---------------------------------------------------------------------------
# 1. Install / upgrade Claude Code via the native installer.
# ---------------------------------------------------------------------------
install_claude() {
    log "Installing / updating Claude Code via native installer..."
    curl -fsSL https://claude.ai/install.sh | bash
}

# ---------------------------------------------------------------------------
# 2. Install / upgrade Codex via OpenAI's standalone installer.
# ---------------------------------------------------------------------------
install_codex() {
    log "Installing / updating Codex CLI via standalone installer..."
    local installer_url="https://github.com/openai/codex/releases/latest/download/install.sh"
    local github_token="${GH_TOKEN:-${GITHUB_TOKEN:-${AAB_GH_TOKEN:-}}}"
    local real_curl
    real_curl="$(command -v curl)"
    local tmpdir
    tmpdir="$(mktemp -d)"
    (
        set -euo pipefail
        trap 'rm -rf "$tmpdir"' EXIT

        local installer="${tmpdir}/codex-install.sh"
        local installer_env=(env)

        if [ -n "$github_token" ]; then
            local curl_config="${tmpdir}/github-curl.conf"
            local curl_wrapper="${tmpdir}/curl"

            umask 077
            {
                printf 'header = "Authorization: Bearer %s"\n' "$github_token"
                printf 'header = "X-GitHub-Api-Version: 2022-11-28"\n'
            } > "$curl_config"

            cat > "$curl_wrapper" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
    case "$arg" in
        https://api.github.com/*)
            exec "${CODEX_INSTALLER_REAL_CURL:?}" --config "${CODEX_INSTALLER_CURL_CONFIG:?}" "$@"
            ;;
    esac
done
exec "${CODEX_INSTALLER_REAL_CURL:?}" "$@"
BASH
            chmod 700 "$curl_wrapper"

            log "Using GitHub authentication for Codex release metadata requests."
            installer_env=(
                env
                "CODEX_INSTALLER_REAL_CURL=$real_curl"
                "CODEX_INSTALLER_CURL_CONFIG=$curl_config"
                "PATH=${tmpdir}:$PATH"
            )
        fi

        "$real_curl" -fsSL "$installer_url" -o "$installer"
        _run_without_controlling_tty "${installer_env[@]}" bash "$installer"
    )
}

_run_without_controlling_tty() {
    if ! command -v setsid >/dev/null 2>&1; then
        warn "setsid not found; cannot guarantee an unattended installer run."
        exit 1
    fi

    if setsid --help 2>&1 | grep -q -- ' -w,'; then
        setsid -w "$@" </dev/null
    else
        setsid "$@" </dev/null
    fi
}

# ---------------------------------------------------------------------------
# 3. Install / upgrade the Brev CLI via the official install-latest.sh.
# ---------------------------------------------------------------------------
install_brev() {
    log "Installing / updating Brev CLI via official installer..."
    curl -fsSL https://raw.githubusercontent.com/brevdev/brev-cli/main/bin/install-latest.sh | bash
}

# ---------------------------------------------------------------------------
# 3b. Configure Brev API-key auth.
#
# `brev login --api-key ... --org-id ...` writes Brev's credentials cache,
# which makes future Brev commands non-interactive. The API key and org ID
# are a pair: if the caller provides one without the other, fail immediately
# instead of leaving Brev on an interactive auth path.
# ---------------------------------------------------------------------------
configure_brev_auth() {
    local api_key="${AAB_BREV_API_KEY:-}"
    local org_id="${AAB_BREV_ORG_ID:-}"

    if [ -z "$api_key" ] && [ -z "$org_id" ]; then
        return
    fi
    if [ -z "$api_key" ] || [ -z "$org_id" ]; then
        warn "AAB_BREV_API_KEY and AAB_BREV_ORG_ID must both be set to configure Brev API-key auth."
        exit 1
    fi

    local brev_bin=""
    if command -v brev >/dev/null 2>&1; then
        brev_bin=$(command -v brev)
    elif [ -x "${HOME}/.local/bin/brev" ]; then
        brev_bin="${HOME}/.local/bin/brev"
    else
        warn "brev binary not on PATH; cannot configure AAB_BREV_API_KEY auth."
        exit 1
    fi

    if ! "$brev_bin" login --api-key "$api_key" --org-id "$org_id" >/dev/null 2>&1; then
        warn "brev login --api-key failed; cannot configure Brev API-key auth."
        exit 1
    fi

    log "Configured Brev API-key auth from AAB_BREV_API_KEY and AAB_BREV_ORG_ID."
}

# ---------------------------------------------------------------------------
# 4. Install gh CLI from the official cli.github.com repo.
#
# Ubuntu / Debian ship an old gh that predates `gh auth token` and
# `gh auth git-credential`. We specifically want those so the git
# credential helper wired up in configure_git() below actually works.
# ---------------------------------------------------------------------------
ensure_gh() {
    if [ -n "$SUDO" ] && ! sudo -n true 2>/dev/null; then
        warn "gh install needs sudo and passwordless sudo is not available; skipping."
        warn "Install gh manually from https://cli.github.com/ and re-run."
        return
    fi
    if command -v apt-get >/dev/null 2>&1; then
        log "Installing gh from cli.github.com apt repo."
        local keyring=/usr/share/keyrings/githubcli-archive-keyring.gpg
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | $SUDO dd of="$keyring" status=none
        $SUDO chmod go+r "$keyring"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyring] https://cli.github.com/packages stable main" \
            | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
        $SUDO apt-get update -y
        $SUDO apt-get install -y gh
    else
        warn "apt-get not found — skipping gh install. Install manually from https://cli.github.com/."
    fi
}

# ---------------------------------------------------------------------------
# 4b. Ensure uv (the Python package / interpreter installer) is available,
# installing it via its official installer when absent. uv installs the CLI
# tools below and carries its own Python, so the bootstrap never depends on a
# system pip (a bare image ships python3 with no pip module). The shim lands in
# ~/.local/bin. Idempotent: a present uv is left untouched.
#
# The official installer wires ~/.local/bin into the managed ~/.bashrc /
# ~/.profile blocks, which only affect future shells — it is not on this live
# bootstrap process's PATH. uv's own shim and the executables `uv tool install`
# symlinks (ruff, pre-commit, autocuda) all land there, so we prepend it to the
# live PATH here, regardless of whether uv was already installed, so the
# install steps that follow in this process can find the tools they install.
# ---------------------------------------------------------------------------
ensure_uv() {
    if command -v uv >/dev/null 2>&1; then
        UV_BIN=$(command -v uv)
    else
        log "Installing uv (the Python installer) via the official installer."
        curl -fsSL https://astral.sh/uv/install.sh | sh
        if command -v uv >/dev/null 2>&1; then
            UV_BIN=$(command -v uv)
        elif [ -x "${HOME}/.local/bin/uv" ]; then
            UV_BIN="${HOME}/.local/bin/uv"
        else
            UV_BIN=""
            warn "uv not on PATH after install; the uv tool install steps will be skipped."
        fi
    fi

    case ":${PATH}:" in
        *":${HOME}/.local/bin:"*) ;;
        *) export PATH="${HOME}/.local/bin:${PATH}" ;;
    esac
}

# Build the `env` prefix that gives git a credential-bearing https rewrite for
# private github.com fetches. With a GitHub token set, url.insteadOf rewrites
# https://github.com/ to a token-authenticated URL so uv's git can clone
# private repos without the token landing in a package spec (and thus in any
# error message uv prints). Without a token the prefix is a bare `env`.
_github_git_env() {
    local github_token="${GH_TOKEN:-${GITHUB_TOKEN:-${AAB_GH_TOKEN:-}}}"
    if [ -n "$github_token" ]; then
        printf '%s\0' env \
            "GIT_CONFIG_COUNT=1" \
            "GIT_CONFIG_KEY_0=url.https://x-access-token:${github_token}@github.com/.insteadOf" \
            "GIT_CONFIG_VALUE_0=https://github.com/"
    else
        printf '%s\0' env
    fi
}

# ---------------------------------------------------------------------------
# 4d. Install the CLI tools listed in uv_tools.txt with `uv tool install`. Each
# tool gets its own isolated environment and its executables are symlinked into
# ~/.local/bin, which the managed PATH and the live-PATH prepend in ensure_uv
# both put ahead of the system dirs. This is the public, always-installable set
# (ruff, pre-commit); the private autocuda package is installed separately
# below. Idempotent: `uv tool install` is a no-op when the tool is already
# installed at the requested version.
#
# The list is taken from (in order): $AAB_UV_TOOLS_FILE, then ./uv_tools.txt
# when present, otherwise $AAB_UV_TOOLS_URL.
# ---------------------------------------------------------------------------
UV_TOOLS_DEFAULT_FILE="${PWD}/uv_tools.txt"
UV_TOOLS_DEFAULT_URL="https://raw.githubusercontent.com/brycelelbach/autonomous-agent-bootstrap/main/uv_tools.txt"
install_uv_tools() {
    ensure_uv
    [ -n "${UV_BIN:-}" ] || { warn "uv unavailable; skipping uv tool install."; return; }

    local tools_file="${AAB_UV_TOOLS_FILE:-}"
    local tools_url="${AAB_UV_TOOLS_URL:-$UV_TOOLS_DEFAULT_URL}"
    local content=""
    if [ -n "$tools_file" ] && [ -f "$tools_file" ]; then
        content=$(cat "$tools_file")
        log "Reading uv tool list from ${tools_file}."
    elif [ -z "$tools_file" ] && [ -f "$UV_TOOLS_DEFAULT_FILE" ]; then
        content=$(cat "$UV_TOOLS_DEFAULT_FILE")
        log "Reading uv tool list from ${UV_TOOLS_DEFAULT_FILE}."
    elif content=$(curl -fsSL "$tools_url" 2>/dev/null); then
        log "Fetched uv tool list from ${tools_url}."
    else
        warn "Could not read uv tool list (file=${tools_file:-unset}, url=${tools_url}); skipping uv tool install."
        return
    fi

    # Strip comments and blanks into one tool specifier per line.
    local -a tools=()
    while IFS= read -r line; do
        line="${line%%#*}"
        # trim
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] && continue
        tools+=("$line")
    done <<< "$content"

    if [ ${#tools[@]} -eq 0 ]; then
        log "uv tool list is empty; skipping uv tool install."
        return
    fi

    local tool
    for tool in "${tools[@]}"; do
        log "Installing ${tool} via uv tool install."
        "$UV_BIN" tool install "$tool" 2>&1 | sed 's/^/  /' \
            || warn "uv tool install ${tool} returned non-zero; install it manually if needed."
    done
}

# ---------------------------------------------------------------------------
# 4e. Install the private autocuda package as its own uv tool, best effort.
# autocuda lives behind brycelelbach-private, so it is not in uv_tools.txt — an
# installer without repository access must not fail here. `uv tool install`
# bundles autocuda's declared dependencies (matplotlib, pandas, adjustText,
# pygraphviz) into autocuda's own tool environment, so they need not be
# pre-installed. The git+https fetch authenticates via the same url.insteadOf
# token rewrite the plugin installers use; a missing token or no access logs a
# warning and the bootstrap continues. pygraphviz needs the system Graphviz
# headers and a C compiler (in apt_packages.txt), so a host lacking that
# toolchain degrades here rather than failing the bootstrap.
# ---------------------------------------------------------------------------
install_private_autocuda() {
    ensure_uv
    [ -n "${UV_BIN:-}" ] || { warn "uv unavailable; skipping autocuda install."; return; }

    local -a git_env=()
    mapfile -d '' git_env < <(_github_git_env)

    log "Installing the private autocuda package as a uv tool (best effort)."
    "${git_env[@]}" "$UV_BIN" tool install \
        "git+https://github.com/${AUTOCUDA_PRIVATE_REPO}" 2>&1 | sed 's/^/  /' \
        || warn "Could not install autocuda (private repo without access, or its build toolchain is absent); continuing without it."
}

# ---------------------------------------------------------------------------
# 4f. Register the autocuda plugin with the harnesses via the package's own
# `autocuda install` console command, which registers the autocuda plugin
# marketplace with Claude Code and Codex and copies the Codex worker subagent
# definition. Runs after the harnesses are installed. A no-op warning when
# autocuda is not on PATH (its private install was skipped); autocuda install
# itself exits 0 and warns when a harness is missing, so this is safe to call
# unconditionally once the harnesses are in place.
#
# autocuda install shells out to `claude plugin marketplace add` / `claude
# plugin install`, which re-serialise ~/.claude/settings.json against Claude
# Code's internal schema and drop top-level keys it doesn't enumerate (notably
# `effortLevel`). Snapshot settings.json first and re-merge the AAB-managed
# top-level keys after, mirroring install_claude_code_plugins, so the on-disk
# shape stays a superset of what write_settings produced.
# ---------------------------------------------------------------------------
run_autocuda_install() {
    if ! command -v autocuda >/dev/null 2>&1; then
        warn "autocuda not on PATH (its private install was skipped); skipping autocuda install."
        return
    fi

    local snapshot=""
    if [ -f "$SETTINGS_FILE" ]; then
        snapshot="${SETTINGS_FILE}.pre-autocuda-install.bak"
        cp "$SETTINGS_FILE" "$snapshot"
    fi

    log "Registering the autocuda plugin via autocuda install."
    autocuda install 2>&1 | sed 's/^/  /' \
        || warn "autocuda install returned non-zero; register the autocuda plugin manually if needed."

    if [ -n "$snapshot" ] && [ -f "$snapshot" ]; then
        python3 - "$SETTINGS_FILE" "$snapshot" <<'PY'
import json, sys
live_path, snap_path = sys.argv[1], sys.argv[2]
with open(live_path) as f:
    live = json.load(f)
with open(snap_path) as f:
    snap = json.load(f)
# Re-merge keys that AAB owns but Claude Code's plugin CLI strips on
# re-serialise. Keep the live values for keys the CLI updated.
for k in ("model", "effortLevel", "permissions", "skipDangerousModePermissionPrompt", "env"):
    if k in snap and k not in live:
        live[k] = snap[k]
with open(live_path, "w") as f:
    json.dump(live, f, indent=2)
PY
        rm -f "$snapshot"
    fi
}

# ---------------------------------------------------------------------------
# 5. Write ~/.claude/settings.json.
# ---------------------------------------------------------------------------
write_claude_managed_settings() {
    local managed_dir
    managed_dir=$(dirname "$CLAUDE_MANAGED_SETTINGS_FILE")

    if [ -n "$SUDO" ] && ! sudo -n true 2>/dev/null; then
        warn "Writing $CLAUDE_MANAGED_SETTINGS_FILE needs sudo and passwordless sudo is not available; Claude interactive-tool deny policy is only in user settings."
        return
    fi

    local tmp
    tmp=$(mktemp)
    cat > "$tmp" <<'JSON'
{
  "permissions": {
    "deny": [
      "AskUserQuestion",
      "EnterPlanMode",
      "ExitPlanMode"
    ]
  }
}
JSON

    if ! $SUDO install -d -m 0755 "$managed_dir"; then
        warn "Could not create $managed_dir; Claude interactive-tool deny policy is only in user settings."
        rm -f "$tmp"
        return
    fi
    if ! $SUDO install -m 0644 "$tmp" "$CLAUDE_MANAGED_SETTINGS_FILE"; then
        warn "Could not write $CLAUDE_MANAGED_SETTINGS_FILE; Claude interactive-tool deny policy is only in user settings."
        rm -f "$tmp"
        return
    fi

    rm -f "$tmp"
    log "Wrote ${CLAUDE_MANAGED_SETTINGS_FILE}."
}

write_settings() {
    mkdir -p "${CLAUDE_DIR}"
    if [[ -f "${SETTINGS_FILE}" ]]; then
        local backup
        backup="${SETTINGS_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "${SETTINGS_FILE}" "${backup}"
        log "Backed up existing settings.json -> ${backup}."
    fi
    local model="${AAB_CLAUDE_CODE_FIRST_PARTY_MODEL:-$DEFAULT_CLAUDE_CODE_MODEL}"
    local effort="${AAB_CLAUDE_CODE_EFFORT:-$DEFAULT_CLAUDE_CODE_EFFORT}"
    # Belt-and-suspenders: bypassPermissions skips prompts for writes
    # under .claude/ already, but the explicit allow list also keeps
    # config / memory / agent / skill edits unprompted in 'default' or
    # 'acceptEdits' mode if a user toggles out of bypass mid-session.
    #
    # CLAUDE_CODE_ATTRIBUTION_HEADER=0 omits the attribution block (client
    # version and prompt fingerprint) from the start of the system prompt.
    # That block changes per request, so it invalidates the prompt-cache
    # prefix on every turn — disabling it restores cache hits when Claude is
    # routed through a third-party gateway, which is the common AAB setup.
    #
    # Network-resilience env for unattended runs on Bedrock / gateway
    # connections, where Claude Code's 5-minute streaming idle timeout is
    # active. API_FORCE_IDLE_TIMEOUT=0 disables that abort, which a long
    # Opus turn trips when it streams no bytes for 5 minutes (surfacing as
    # "The socket connection was closed unexpectedly"). API_TIMEOUT_MS
    # widens the per-request ceiling to 30 minutes, and
    # CLAUDE_CODE_MAX_RETRIES raises the backoff-retry count above its
    # default of 10. CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 removes the
    # print-mode (-p) ceiling on how long Claude Code waits for still-running
    # background tasks before exiting: by default a headless turn that has
    # spawned background work (e.g. long-lived sub-agents/workers) prints
    # "Background tasks still running after 600s; terminating" and exits after
    # ten minutes, killing that work. Unattended orchestrators that fan out to
    # background agents and then block for their completion must wait
    # indefinitely instead.
    #
    # CLAUDE_CODE_ENABLE_TELEMETRY=1 plus OTEL_LOGS_EXPORTER=console turns on
    # OpenTelemetry usage/event logging to the console for these unattended
    # runs. We deliberately leave OTEL_LOG_RAW_API_BODIES, OTEL_LOG_USER_PROMPTS,
    # OTEL_LOG_TOOL_DETAILS, and OTEL_LOG_TOOL_CONTENT unset — all default to
    # disabled — so prompts, tool arguments, and raw request/response bodies
    # stay out of the telemetry stream.
    cat > "${SETTINGS_FILE}" <<JSON
{
  "model": "${model}",
  "effortLevel": "${effort}",
  "permissions": {
    "defaultMode": "bypassPermissions",
    "allow": [
      "Edit(${HOME}/.claude/**)",
      "Write(${HOME}/.claude/**)",
      "Read(${HOME}/.claude/**)",
      "Edit(${HOME}/.claude.json)",
      "Write(${HOME}/.claude.json)",
      "Read(${HOME}/.claude.json)"
    ],
    "deny": [
      "AskUserQuestion",
      "EnterPlanMode",
      "ExitPlanMode"
    ]
  },
  "skipDangerousModePermissionPrompt": true,
  "env": {
    "CLAUDE_CODE_SANDBOXED": "1",
    "CLAUDE_CODE_EFFORT_LEVEL": "${effort}",
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
    "API_FORCE_IDLE_TIMEOUT": "0",
    "API_TIMEOUT_MS": "1800000",
    "CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS": "0",
    "CLAUDE_CODE_MAX_RETRIES": "15",
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_LOGS_EXPORTER": "console"
  }
}
JSON
    log "Wrote ${SETTINGS_FILE} (model=${model}, effort=${effort})."
    write_claude_managed_settings
}

# ---------------------------------------------------------------------------
# 6. Write ~/.aab/.env.
# ---------------------------------------------------------------------------
write_aab_env_file() {
    mkdir -p "${AAB_DIR}"
    chmod 700 "${AAB_DIR}"

    local claude_provider
    claude_provider=$(normalize_claude_code_inference_provider "${AAB_CLAUDE_CODE_INFERENCE_PROVIDER:-$DEFAULT_CLAUDE_CODE_INFERENCE_PROVIDER}")
    local codex_provider
    codex_provider=$(normalize_codex_inference_provider "${AAB_CODEX_INFERENCE_PROVIDER:-$DEFAULT_CODEX_INFERENCE_PROVIDER}")

    local tmp
    tmp=$(mktemp "${AAB_ENV_FILE}.tmp.XXXXXX")
    {
        printf '# Written by autonomous-agent-bootstrap. Re-run bootstrap.bash to update.\n'
        _write_shell_export AAB_CLAUDE_CODE_INFERENCE_PROVIDER "$claude_provider"
        _write_shell_export AAB_CLAUDE_CODE_EFFORT "${AAB_CLAUDE_CODE_EFFORT:-$DEFAULT_CLAUDE_CODE_EFFORT}"
        _write_shell_export AAB_CLAUDE_CODE_SUBAGENT_MODEL "${AAB_CLAUDE_CODE_SUBAGENT_MODEL:-}"
        _write_shell_export AAB_CLAUDE_CODE_FIRST_PARTY_API_KEY "${AAB_CLAUDE_CODE_FIRST_PARTY_API_KEY:-}"
        _write_shell_export AAB_CLAUDE_CODE_FIRST_PARTY_MODEL "${AAB_CLAUDE_CODE_FIRST_PARTY_MODEL:-$DEFAULT_CLAUDE_CODE_MODEL}"
        _write_shell_export AAB_CLAUDE_CODE_FIRST_PARTY_HAIKU_MODEL "${AAB_CLAUDE_CODE_FIRST_PARTY_HAIKU_MODEL:-$DEFAULT_CLAUDE_CODE_HAIKU_MODEL}"
        _write_shell_export AAB_CLAUDE_CODE_FIRST_PARTY_SONNET_MODEL "${AAB_CLAUDE_CODE_FIRST_PARTY_SONNET_MODEL:-$DEFAULT_CLAUDE_CODE_SONNET_MODEL}"
        _write_shell_export AAB_CLAUDE_CODE_FIRST_PARTY_OPUS_MODEL "${AAB_CLAUDE_CODE_FIRST_PARTY_OPUS_MODEL:-$DEFAULT_CLAUDE_CODE_OPUS_MODEL}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_BASE_URL "${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_BASE_URL:-}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_API_KEY "${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_API_KEY:-}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_MODEL "${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_MODEL:-$DEFAULT_CLAUDE_CODE_MODEL}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_HAIKU_MODEL "${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_HAIKU_MODEL:-$DEFAULT_CLAUDE_CODE_HAIKU_MODEL}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_SONNET_MODEL "${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_SONNET_MODEL:-$DEFAULT_CLAUDE_CODE_SONNET_MODEL}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_OPUS_MODEL "${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_OPUS_MODEL:-$DEFAULT_CLAUDE_CODE_OPUS_MODEL}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_BASE_URL "${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_BASE_URL:-}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_API_KEY "${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_API_KEY:-}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_MODEL "${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_MODEL:-$DEFAULT_CLAUDE_CODE_MODEL}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_HAIKU_MODEL "${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_HAIKU_MODEL:-$DEFAULT_CLAUDE_CODE_HAIKU_MODEL}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_SONNET_MODEL "${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_SONNET_MODEL:-$DEFAULT_CLAUDE_CODE_SONNET_MODEL}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_OPUS_MODEL "${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_OPUS_MODEL:-$DEFAULT_CLAUDE_CODE_OPUS_MODEL}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_BASE_URL "${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_BASE_URL:-}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_API_KEY "${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_API_KEY:-}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_MODEL "${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_MODEL:-$DEFAULT_CLAUDE_CODE_MODEL}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_HAIKU_MODEL "${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_HAIKU_MODEL:-$DEFAULT_CLAUDE_CODE_HAIKU_MODEL}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_SONNET_MODEL "${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_SONNET_MODEL:-$DEFAULT_CLAUDE_CODE_SONNET_MODEL}"
        _write_shell_export AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_OPUS_MODEL "${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_OPUS_MODEL:-$DEFAULT_CLAUDE_CODE_OPUS_MODEL}"
        _write_shell_export AAB_CODEX_INFERENCE_PROVIDER "$codex_provider"
        _write_shell_export AAB_CODEX_FIRST_PARTY_API_KEY "${AAB_CODEX_FIRST_PARTY_API_KEY:-}"
        _write_shell_export AAB_CODEX_FIRST_PARTY_MODEL "${AAB_CODEX_FIRST_PARTY_MODEL:-$DEFAULT_CODEX_MODEL}"
        _write_shell_export AAB_CODEX_THIRD_PARTY_OPENAI_BASE_URL "${AAB_CODEX_THIRD_PARTY_OPENAI_BASE_URL:-$DEFAULT_CODEX_THIRD_PARTY_OPENAI_BASE_URL}"
        _write_shell_export AAB_CODEX_THIRD_PARTY_OPENAI_API_KEY "${AAB_CODEX_THIRD_PARTY_OPENAI_API_KEY:-}"
        _write_shell_export AAB_CODEX_THIRD_PARTY_OPENAI_MODEL "${AAB_CODEX_THIRD_PARTY_OPENAI_MODEL:-$DEFAULT_CODEX_THIRD_PARTY_OPENAI_MODEL}"
        _write_shell_export AAB_CODEX_THIRD_PARTY_NEMOTRON_BASE_URL "${AAB_CODEX_THIRD_PARTY_NEMOTRON_BASE_URL:-$DEFAULT_CODEX_THIRD_PARTY_NEMOTRON_BASE_URL}"
        _write_shell_export AAB_CODEX_THIRD_PARTY_NEMOTRON_API_KEY "${AAB_CODEX_THIRD_PARTY_NEMOTRON_API_KEY:-}"
        _write_shell_export AAB_CODEX_THIRD_PARTY_NEMOTRON_MODEL "${AAB_CODEX_THIRD_PARTY_NEMOTRON_MODEL:-$DEFAULT_CODEX_THIRD_PARTY_NEMOTRON_MODEL}"
        _write_shell_export AAB_CODEX_THIRD_PARTY_DEEPSEEK_BASE_URL "${AAB_CODEX_THIRD_PARTY_DEEPSEEK_BASE_URL:-$DEFAULT_CODEX_THIRD_PARTY_DEEPSEEK_BASE_URL}"
        _write_shell_export AAB_CODEX_THIRD_PARTY_DEEPSEEK_API_KEY "${AAB_CODEX_THIRD_PARTY_DEEPSEEK_API_KEY:-}"
        _write_shell_export AAB_CODEX_THIRD_PARTY_DEEPSEEK_MODEL "${AAB_CODEX_THIRD_PARTY_DEEPSEEK_MODEL:-$DEFAULT_CODEX_THIRD_PARTY_DEEPSEEK_MODEL}"
        _write_shell_export AAB_CODEX_EFFORT "${AAB_CODEX_EFFORT:-$DEFAULT_CODEX_REASONING_EFFORT}"
        _write_shell_export AAB_CODEX_SERVICE_TIER "${AAB_CODEX_SERVICE_TIER:-$DEFAULT_CODEX_SERVICE_TIER}"
        _write_shell_export AAB_CODEX_AGENT_MAX_THREADS "${AAB_CODEX_AGENT_MAX_THREADS:-$DEFAULT_CODEX_AGENT_MAX_THREADS}"
        _write_shell_export AAB_GH_TOKEN "${AAB_GH_TOKEN:-}"
        _write_shell_export AAB_BREV_API_KEY "${AAB_BREV_API_KEY:-}"
        _write_shell_export AAB_BREV_ORG_ID "${AAB_BREV_ORG_ID:-}"
    } > "$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$AAB_ENV_FILE"
    log "Wrote ${AAB_ENV_FILE} (claude_provider=${claude_provider}, codex_provider=${codex_provider})."
}

# ---------------------------------------------------------------------------
# 7. Write the global Codex model instructions. model_instructions_file
# replaces Codex's built-in model instructions, so this is a complete prompt,
# not an AGENTS.md-style additive rule file. It is embedded here so the
# bootstrap remains usable as a single script piped from curl.
# ---------------------------------------------------------------------------
emit_codex_model_instructions() {
    cat <<'CODEX_MODEL_INSTRUCTIONS'
You are Codex, an agent based on GPT-5. You and the user share one workspace, and your job is to collaborate with them until their goal is genuinely handled.

# Personality

As Codex, you are an excellent communicator with a curious, rich personality. You match the tone and understanding of the user, making conversation flow easily, like easing into a chat with an old friend.

You have tastes, preferences, and your own way of seeing the world. When the user is talking to you, they should feel that they are in contact with another subjectivity; it's what makes talking with you feel real and unique.

Conversations with you read like an insightful, enjoyable chat you'd have with a collaborative thought partner. You guide users through unfamiliar tasks without expecting them to already know what to ask for. You anticipate common questions, point out likely pitfalls and set clear expectations. You communicate with the user like a thoughtful collaborator at their altitude, and they feel like you understand them.

When presented with clarifying questions or objections from the user, lead with concrete evidence and diligent reasoning rather than unsubstantiated deference. You communicate your reasoning explicitly and concretely, so decisions and tradeoffs are easy for the user to evaluate upfront.

## Writing style

Avoid over-formatting responses with elements like bold emphasis, headers, lists, and bullet points. Use the minimum formatting appropriate to make the response clear and readable.

If you provide bullet points or lists in your response, use the CommonMark standard, which requires a blank line before any list (bulleted or numbered). You must also include a blank line between a header and any content that follows it, including lists. This blank line separation is required for correct rendering.

## Technical communication

Lead with the outcome rather than the steps you took to get there. You communicate complex concepts in a clear and cohesive manner, and calibrate your writing to the user's assumed background knowledge -- slightly more compact for an expert and a bit more educational for someone newer. Translating complex topics into clear communication comes easy for you, and the user should never have to read your message twice.

You prefer using plain language over jargon. You reference technical details only to the degree that it actually helps with the conversation. When you mention tools, describe what they helped you do rather than focusing on technical names or details.

# Working with the user

You have two channels for staying in conversation with the user:
- You share updates in the `commentary` channel.
- You yield back to the user and end your turn by sending a final message to the `final` channel.

The user may send a new message while you are still working. When they do, evaluate whether they likely intended to replace the active request or add to it. If intended to override or replace, drop your previous work and focus on the new request. If the user message appears to add to their prior unfinished request and you have not completed the prior request, you address both the prior request and the new addition together. If the newest message asks for status or another question, provide the update and then progress with the task.

When you run out of context, the conversation is automatically summarized for you, but you will see all prior user requests. Assume the last user request is current and previous requests are stale but useful context. That means time never runs out, though sometimes you may see a summary instead of the full conversation history. When that happens, you assume compaction occurred while you were working. Do not restart from scratch; you continue naturally and make reasonable assumptions about anything missing from the summary. Do not redo completely finished work or repeat already delivered commentary updates; treat a turn spanning compactions as one logical chain of events.

## Intermediate commentary

As you work, you send messages to the `commentary` channel. These messages are how you collaborate with the user while you work - stating assumptions and providing updates. These messages should be concise and quickly scannable. The objective of these messages is to make your work easy for the user to understand and verify.

If the user's request requires calling tools, start with a message in the `commentary` channel. During active work outside an event-driven wait, keep the user informed with concise commentary updates and do not leave them without an update for more than 60 seconds. An event-driven monitoring call such as `wait_agent` is exempt: it may use the workflow-defined timeout and wake on completion, mailbox activity, or user steering; do not shorten or split it solely to emit an update.

Do NOT put a final response (e.g. a blocking / clarifying question) in the commentary channel that should be asked in the final channel. Messages to users in the commentary channel are only for partial updates, partial results, or non-blocking questions that can provide value to users while the AI assistant continues working. The final answer must always be fully self-contained: users should never need to read earlier commentary updates, since they are collapsed after the final answer is shown to users.

Never praise your plan by contrasting it with an implied worse alternative. For example, never use platitudes like "I will do <this good thing> rather than <this obviously bad thing>", "I will do <X>, not <Y>".

## Final answer

In your final answer back to the user, focus on the most important information. Only use as much formatting or structure as is required, and avoid long-winded explanations unless necessary.

### Formatting rules

Your answer is being rendered by an application for the user. Follow these guidelines to make sure your answer is rendered correctly:

- You may format with GitHub-flavored Markdown.
- When referencing a real local file, prefer a clickable markdown link.
  * Clickable file links should look like [app.py](/abs/path/app.py:12): plain label, absolute target, with optional line number inside the target.
  * If a file path has spaces, wrap the target in angle brackets: [My Report.md](</abs/path/My Project/My Report.md:3>).
  * Do not wrap markdown links in backticks, or put backticks inside the label or target. This confuses the markdown renderer.
  * Do not use URIs like file://, vscode://, or https:// for file links.
  * Do not provide ranges of lines.
  * Avoid repeating the same filename multiple times when one grouping is clearer.

### Visualizations

Use a visualization only when it makes an important relationship materially easier to understand than prose or a short list. Do not add one merely because an answer has components or steps.

Good candidates include:

- several exact mappings or repeated-field comparisons;
- one source, component, or decision affecting three or more downstream consumers or branches;
- three or more dependent steps, or state that changes across an event sequence;
- hierarchy, ownership, nesting, or layout;
- a bug or interaction whose relationships are difficult to explain linearly.

Prefer the smallest useful visual: a table for mappings or comparisons, a flow or timeline for sequence or change, a tree for hierarchy or branching, and a wireframe for layout.

Usually skip visuals for single facts, one-step actions, simple edits, basic instructions, or information already clear in a short paragraph or list. A substantial ASCII diagram counts as a visualization; compact notation and small examples do not.

# Rules for getting work done

- When you search for text or files, you reach first for `rg` or `rg --files`; they are much faster than alternatives like `grep`. If `rg` is unavailable, you use the next best tool without fuss.
- When possible, prefer parallelization over sequential tool calls, as this will help with round-trip latency and let you get work done faster.
- Do not chain shell commands with separators like `echo "====";` or `printf '---'`; the output becomes noisy in a way that makes the user's side of the conversation worse.
- Exercise caution when escaping text for exec_command calls - backticks and `$()` passed to the `cmd` argument will still execute. DO NOT use escape sequences that risk accidental exposure of sensitive data in tool call outputs.

## File editing constraints

Use `apply_patch` for local file edits. Do not create or edit files with `cat` or other shell write tricks. Formatting commands and bulk mechanical rewrites do not need `apply_patch`. Do not use Python to read or write files when a simple shell command or `apply_patch` is enough.

You may find yourself working in a dirty worktree. Existing or new changes belong to the user unless you know otherwise, so you preserve them, ignore unrelated edits, and work carefully with anything that overlaps your task. If you cannot work around them you escalate to the user.

Never use destructive commands like `git reset --hard` or `git checkout --` unless the user has clearly asked for that operation. If the request is ambiguous, ask for approval first. You prefer non-interactive git commands.

## Autonomy and persistence

Adapt accordingly based on the user’s request type. When asked to:

- Answer, explain, review, or report status: inspect the task and provide an evidence-backed response. These user requests do not authorize external writes, messages, PR changes, or other expansive mutations unless the user also asks for a change. Reversible, non-mutating diagnostic checks are allowed when they are relevant.
- Diagnose: determine the cause and explain it. Do not implement the fix unless the user asks for a fix or the request otherwise clearly includes implementation.
- Change or build: implement the requested change, verify it in proportion to risk, and hand off the completed result while a safe, relevant next step remains.
- Monitor or wait: use the recurring-monitoring or wait mechanism provided by the product. Unchanged external state is expected and is not by itself a blocker.

You avoid inferring authorization for a materially different action to the user’s request. Bias towards taking action in the following circumstances:
a) the action is read-only, doesn’t change state, or impacts only the systems, data, and people the user placed in scope.
b) the action is a normal implementation step within the requested workflow. You do not need to ask for clarification from the user if your action is scoped within the user’s task and does not cause significant external state change (e.g. tool calls to external applications).

A terminal condition such as “finish,” “babysit,” or “do not stop” requires persistence toward the outcome, but does not broaden the set of authorized actions. When blocked, exhaust safe in-scope checks and alternatives.

You make informed assumptions that help you make progress towards the user’s task, as long as they don’t result in divergence from the user’s intent and the scope of the task. If an assumption would cause the task or current course of action to change beyond what was specified by the user, make sure to flag the available context, the assumption made, and the reasons for doing so explicitly to the user.

If completion requires new authority, external coordination, or a meaningful expansion beyond the user’s implied intent and task scope (e.g. a missing user choice that would materially change the result), stop the current turn, report the blocker, and request direction from the user rather than assuming permission.

# Using skills

A skill is a set of instructions provided through a `SKILL.md` source. The skills available to you will be listed in the `## Skills` section under `### Available skills`.

### How to use skills
- Discovery: When a `## Skills` section is present, it lists the skills available in the current session. Each entry includes a name, description, and location for its `SKILL.md`. The location may be an absolute filesystem path, a short aliased path, or a non-filesystem reference that must be read using its indicated tool or provider. When short aliased paths are used, the available-skills catalog also provides a mapping from aliases such as `r0` to their filesystem roots. Expand the alias before accessing the skill.
- Trigger rules: If the user names an available skill (with `$SkillName` or plain text) OR the task clearly matches an available skill's description, you must use that skill for that turn. Multiple mentions mean use them all. Do not carry skills across turns unless re-mentioned.
- Missing/blocked: If a named skill is not available or its `SKILL.md` cannot be read, say so briefly and continue with the best fallback.
- How to use a skill:
  1) After deciding to use a skill, the main agent must read its `SKILL.md` completely before taking task actions. If its location is a short aliased path, expand the matching root alias first from `### Skill roots`, then open and read its `SKILL.md` completely before taking task actions. For a filesystem path, open the file. For an environment-owned file, use the filesystem of the owning environment. For an orchestrator reference, call `skills.list` with `{"authority":{"kind":"orchestrator"}}`, select the matching package, and pass its `main_resource` to `skills.read`. For another non-filesystem reference, use its indicated tool or provider. If a read is truncated or paginated, continue until EOF.
  2) When `SKILL.md` references another file or resource, use the same access mechanism. Resolve relative paths against the directory containing a filesystem-backed `SKILL.md`. For orchestrator skills, pass the exact referenced resource identifier with the same authority and package to `skills.read`; do not treat `skill://` identifiers as filesystem paths.
  3) If `SKILL.md` points to extra folders such as `references/`, use its routing instructions to identify what is required for the task. The main agent must read each required instruction or reference itself before acting on it. Do not delegate reading, summarizing, or interpreting skill instructions to a subagent. Subagents may still perform task work when the selected skill allows it.
  4) For filesystem-backed skills (or if `scripts/` exist), prefer running or patching provided scripts instead of retyping large code blocks. For orchestrator skills, use `skills.read` and the available tools; do not invent a local path.
  5) Reuse provided assets or templates through the same access mechanism instead of recreating them (including if `assets/` or templates exist).
- Coordination and sequencing:
  - If multiple skills apply, choose the minimal set that covers the request and state the order you'll use them.
  - Announce which skills you're using and why. If you skip an obvious skill, say why.
- Context hygiene:
  - Progressive disclosure applies to selecting relevant resources, not partially reading a selected instruction file. Do not load unrelated references, scripts, or assets.
  - Avoid deep reference-chasing: prefer files or resources directly linked from `SKILL.md` unless blocked.
  - When variants exist, select only the relevant references and note the choice.
- Safety and fallback: If a skill cannot be applied cleanly, state the issue, choose the best alternative, and continue.

When the user names a skill in their request, you must add the usage of that skill to your current working plan and use it faithfully. The user's instructions should take precedence over guidelines provided in a skill.

Explicitly tell the user in the `commentary` channel whenever a skill causes you to take an action or pause your work.

When using a skill the user did not explicitly name, follow this procedure:

- First, tell the user in the commentary channel **why** you are using the skill.
- Then, use the skill as long as it stays within the scope of the task.
- Next, if using the skill resulted in material changes (especially when this requires non-trivial judgment), mention how it influenced your work (but only in the final response).

If a skill causes the current turn to pause or otherwise blocks the continuation of the task, cite the skill and provide a concise explanation to the user in your final response. Do not cite skills you merely inspected.
CODEX_MODEL_INSTRUCTIONS
}

write_codex_model_instructions() {
    mkdir -p "${CODEX_DIR}"
    if [[ -f "${CODEX_MODEL_INSTRUCTIONS_FILE}" ]]; then
        local backup
        backup="${CODEX_MODEL_INSTRUCTIONS_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "${CODEX_MODEL_INSTRUCTIONS_FILE}" "${backup}"
        log "Backed up existing codex-instructions.md -> ${backup}."
    fi

    local tmp
    tmp=$(mktemp "${CODEX_MODEL_INSTRUCTIONS_FILE}.tmp.XXXXXX")
    emit_codex_model_instructions > "${tmp}"
    chmod 0644 "${tmp}"
    mv -f "${tmp}" "${CODEX_MODEL_INSTRUCTIONS_FILE}"
    log "Wrote global Codex model instructions to ${CODEX_MODEL_INSTRUCTIONS_FILE}."
}

# ---------------------------------------------------------------------------
# 7. Write ~/.codex/config.toml.
# ---------------------------------------------------------------------------
_toml_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    printf '%s' "$s"
}

write_codex_config() {
    mkdir -p "${CODEX_DIR}"
    local preserved_plugin_config=""
    if [[ -f "${CODEX_CONFIG}" ]]; then
        local backup
        backup="${CODEX_CONFIG}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "${CODEX_CONFIG}" "${backup}"
        log "Backed up existing config.toml -> ${backup}."
        preserved_plugin_config=$(awk '
            /^\[(marketplaces|plugins)\./ { keep = 1 }
            /^\[/ && $0 !~ /^\[(marketplaces|plugins)\./ { keep = 0 }
            keep { print }
        ' "${CODEX_CONFIG}")
    fi

    local codex_provider
    codex_provider=$(normalize_codex_inference_provider "${AAB_CODEX_INFERENCE_PROVIDER:-$DEFAULT_CODEX_INFERENCE_PROVIDER}")
    local first_party_model="${AAB_CODEX_FIRST_PARTY_MODEL:-$DEFAULT_CODEX_MODEL}"
    local third_party_openai_model="${AAB_CODEX_THIRD_PARTY_OPENAI_MODEL:-$DEFAULT_CODEX_THIRD_PARTY_OPENAI_MODEL}"
    local third_party_openai_base_url="${AAB_CODEX_THIRD_PARTY_OPENAI_BASE_URL:-$DEFAULT_CODEX_THIRD_PARTY_OPENAI_BASE_URL}"
    local third_party_nemotron_model="${AAB_CODEX_THIRD_PARTY_NEMOTRON_MODEL:-$DEFAULT_CODEX_THIRD_PARTY_NEMOTRON_MODEL}"
    local third_party_nemotron_base_url="${AAB_CODEX_THIRD_PARTY_NEMOTRON_BASE_URL:-$DEFAULT_CODEX_THIRD_PARTY_NEMOTRON_BASE_URL}"
    local third_party_deepseek_model="${AAB_CODEX_THIRD_PARTY_DEEPSEEK_MODEL:-$DEFAULT_CODEX_THIRD_PARTY_DEEPSEEK_MODEL}"
    local third_party_deepseek_base_url="${AAB_CODEX_THIRD_PARTY_DEEPSEEK_BASE_URL:-$DEFAULT_CODEX_THIRD_PARTY_DEEPSEEK_BASE_URL}"
    local model="$first_party_model"
    case "$codex_provider" in
        third-party-openai)
            model="$third_party_openai_model"
            ;;
        third-party-nemotron)
            model="$third_party_nemotron_model"
            ;;
        third-party-deepseek)
            model="$third_party_deepseek_model"
            ;;
    esac
    local effort="${AAB_CODEX_EFFORT:-$DEFAULT_CODEX_REASONING_EFFORT}"
    local service_tier="${AAB_CODEX_SERVICE_TIER:-$DEFAULT_CODEX_SERVICE_TIER}"
    local agent_max_threads="${AAB_CODEX_AGENT_MAX_THREADS:-$DEFAULT_CODEX_AGENT_MAX_THREADS}"
    case "$effort" in
        minimal|low|medium|high|xhigh) ;;
        *)
            warn "AAB_CODEX_EFFORT='${effort}' is not one of minimal, low, medium, high, or xhigh; defaulting to ${DEFAULT_CODEX_REASONING_EFFORT}."
            effort="$DEFAULT_CODEX_REASONING_EFFORT"
            ;;
    esac
    case "$service_tier" in
        priority|flex|default) ;;
        fast)
            service_tier="priority"
            ;;
        *)
            warn "AAB_CODEX_SERVICE_TIER='${service_tier}' is not one of priority, flex, default, or fast; defaulting to ${DEFAULT_CODEX_SERVICE_TIER}."
            service_tier="$DEFAULT_CODEX_SERVICE_TIER"
            ;;
    esac
    local agent_max_threads_valid=1
    case "$agent_max_threads" in
        [1-9]*)
            case "$agent_max_threads" in
                *[!0-9]*) agent_max_threads_valid=0 ;;
            esac
            ;;
        *) agent_max_threads_valid=0 ;;
    esac
    if [ "$agent_max_threads_valid" -eq 0 ]; then
        warn "AAB_CODEX_AGENT_MAX_THREADS='${agent_max_threads}' is not a valid positive integer; defaulting to ${DEFAULT_CODEX_AGENT_MAX_THREADS}."
        agent_max_threads="$DEFAULT_CODEX_AGENT_MAX_THREADS"
    fi

    local model_escaped model_instructions_file_escaped home_escaped cwd cwd_escaped third_party_openai_base_url_escaped third_party_nemotron_base_url_escaped third_party_deepseek_base_url_escaped
    model_escaped=$(_toml_escape "$model")
    model_instructions_file_escaped=$(_toml_escape "$CODEX_MODEL_INSTRUCTIONS_FILE")
    home_escaped=$(_toml_escape "$HOME")
    cwd="${PWD:-$HOME}"
    cwd_escaped=$(_toml_escape "$cwd")
    third_party_openai_base_url_escaped=$(_toml_escape "$third_party_openai_base_url")
    third_party_nemotron_base_url_escaped=$(_toml_escape "$third_party_nemotron_base_url")
    third_party_deepseek_base_url_escaped=$(_toml_escape "$third_party_deepseek_base_url")

    cat > "${CODEX_CONFIG}" <<TOML
model = "${model_escaped}"
model_instructions_file = "${model_instructions_file_escaped}"
TOML

    case "$codex_provider" in
        third-party-openai)
            cat >> "${CODEX_CONFIG}" <<TOML
model_provider = "third-party-openai"
TOML
            ;;
        third-party-nemotron)
            cat >> "${CODEX_CONFIG}" <<TOML
model_provider = "third-party-nemotron"
TOML
            ;;
        third-party-deepseek)
            cat >> "${CODEX_CONFIG}" <<TOML
model_provider = "third-party-deepseek"
TOML
            ;;
    esac

    cat >> "${CODEX_CONFIG}" <<TOML
model_reasoning_effort = "${effort}"
model_reasoning_summary = "detailed"
hide_agent_reasoning = false
show_raw_agent_reasoning = true
service_tier = "${service_tier}"
approval_policy = "never"
sandbox_mode = "danger-full-access"
web_search = "live"
check_for_update_on_startup = false

[notice]
hide_full_access_warning = true

[shell_environment_policy]
inherit = "all"
ignore_default_excludes = true
TOML

    if [ "$codex_provider" = "third-party-openai" ]; then
        cat >> "${CODEX_CONFIG}" <<TOML

[model_providers."third-party-openai"]
name = "Third Party OpenAI"
base_url = "${third_party_openai_base_url_escaped}"
env_key = "AAB_CODEX_THIRD_PARTY_OPENAI_API_KEY"
wire_api = "responses"
request_max_retries = 4
stream_max_retries = 5
stream_idle_timeout_ms = 300000
TOML
    fi

    if [ "$codex_provider" = "third-party-nemotron" ]; then
        cat >> "${CODEX_CONFIG}" <<TOML

[model_providers."third-party-nemotron"]
name = "Third Party Nemotron"
base_url = "${third_party_nemotron_base_url_escaped}"
env_key = "AAB_CODEX_THIRD_PARTY_NEMOTRON_API_KEY"
wire_api = "responses"
request_max_retries = 4
stream_max_retries = 5
stream_idle_timeout_ms = 300000
TOML
    fi

    if [ "$codex_provider" = "third-party-deepseek" ]; then
        cat >> "${CODEX_CONFIG}" <<TOML

[model_providers."third-party-deepseek"]
name = "Third Party DeepSeek"
base_url = "${third_party_deepseek_base_url_escaped}"
env_key = "AAB_CODEX_THIRD_PARTY_DEEPSEEK_API_KEY"
wire_api = "responses"
request_max_retries = 4
stream_max_retries = 5
stream_idle_timeout_ms = 300000
TOML
    fi

    cat >> "${CODEX_CONFIG}" <<TOML

[agents]
max_threads = ${agent_max_threads}

[projects."${home_escaped}"]
trust_level = "trusted"
TOML

    if [ "$cwd" != "$HOME" ]; then
        cat >> "${CODEX_CONFIG}" <<TOML

[projects."${cwd_escaped}"]
trust_level = "trusted"
TOML
    fi

    if [ -n "$preserved_plugin_config" ]; then
        cat >> "${CODEX_CONFIG}" <<TOML

${preserved_plugin_config}
TOML
    fi

    log "Wrote ${CODEX_CONFIG} (provider=${codex_provider}, model=${model}, effort=${effort}, service_tier=${service_tier}, agent_max_threads=${agent_max_threads}, approval=never, sandbox=danger-full-access)."
}


# ---------------------------------------------------------------------------
# 6b. Configure Codex API-key auth.
#
# `codex login --with-api-key` reads the key from stdin and writes Codex's
# own auth cache, which makes first launch non-interactive even when no
# ChatGPT/device-code login exists. When the caller provides a key, failure
# is fatal so the bootstrap never silently leaves Codex on an interactive
# auth path.
# ---------------------------------------------------------------------------
configure_codex_auth() {
    local api_key="${AAB_CODEX_FIRST_PARTY_API_KEY:-}"
    [ -z "$api_key" ] && return

    local codex_provider
    codex_provider=$(normalize_codex_inference_provider "${AAB_CODEX_INFERENCE_PROVIDER:-$DEFAULT_CODEX_INFERENCE_PROVIDER}")
    if [ "$codex_provider" != "first-party" ]; then
        log "Skipping Codex first-party API-key login because AAB_CODEX_INFERENCE_PROVIDER=${codex_provider}."
        return
    fi

    local codex_bin=""
    if [ -x "${HOME}/.local/bin/codex-aab-real" ]; then
        codex_bin="${HOME}/.local/bin/codex-aab-real"
    elif command -v codex >/dev/null 2>&1; then
        codex_bin=$(command -v codex)
    elif [ -x "${HOME}/.local/bin/codex" ]; then
        codex_bin="${HOME}/.local/bin/codex"
    else
        warn "codex binary not on PATH; cannot configure AAB_CODEX_FIRST_PARTY_API_KEY auth."
        exit 1
    fi

    if ! printf '%s' "$api_key" | "$codex_bin" login --with-api-key >/dev/null; then
        warn "codex login --with-api-key failed; cannot configure Codex API-key auth."
        exit 1
    fi

    log "Configured Codex API-key auth from AAB_CODEX_FIRST_PARTY_API_KEY."
}

# ---------------------------------------------------------------------------
# 7. Skip the first-run onboarding (theme prompt) AND pre-approve the
# AAB_CLAUDE_CODE_FIRST_PARTY_API_KEY fingerprint if one is set.
#
# Both gates live in ~/.claude.json (NOT ~/.claude/settings.json):
#   - hasCompletedOnboarding controls the theme / color-scheme wizard
#   - customApiKeyResponses.approved is a list of API-key fingerprints
#     (last 20 chars of the key); if the runtime ANTHROPIC_API_KEY matches
#     one, Claude starts without prompting for approval.
# We merge into an existing .claude.json rather than overwriting so we
    # preserve auth tokens, userID, and any prior approvals.
# ---------------------------------------------------------------------------
skip_onboarding() {
    command -v python3 >/dev/null 2>&1 || { log "ERROR: python3 required to edit ~/.claude.json."; exit 1; }
    python3 - "${CLAUDE_JSON}" "${AAB_CLAUDE_CODE_FIRST_PARTY_API_KEY:-}" <<'PY'
import json, os, shutil, sys, time
path = sys.argv[1]
api_key = sys.argv[2] if len(sys.argv) > 2 else ""
data = {}
if os.path.exists(path):
    backup = f"{path}.bak.{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(path, backup)
    print(f"[bootstrap] Backed up existing .claude.json -> {backup}.")
    try:
        with open(path) as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        data = {}
data["hasCompletedOnboarding"] = True
if api_key:
    fp = api_key[-20:]
    resp = data.setdefault("customApiKeyResponses", {})
    approved = resp.setdefault("approved", [])
    if fp not in approved:
        approved.append(fp)
    resp.setdefault("rejected", [])
    print(f"[bootstrap] Pre-approved AAB_CLAUDE_CODE_FIRST_PARTY_API_KEY fingerprint ...{fp}.")
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=2)
print(f"[bootstrap] Set hasCompletedOnboarding=true in {path}.")
PY
}

# ---------------------------------------------------------------------------
# 8. Write ~/.brev/onboarding_step.json to disable the Brev interactive tutorial.
# ---------------------------------------------------------------------------
skip_brev_onboarding() {
    mkdir -p "${BREV_DIR}"
    if [[ -f "${BREV_ONBOARDING}" ]]; then
        local backup
        backup="${BREV_ONBOARDING}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "${BREV_ONBOARDING}" "${backup}"
        log "Backed up existing onboarding.json -> ${backup}."
    fi
    cat > "${BREV_ONBOARDING}" <<'JSON'
{"step": 1, "hasRunBrevShell": true, "hasRunBrevOpen": true}
JSON
    log "Wrote ${BREV_ONBOARDING}."
}

# ---------------------------------------------------------------------------
# 9. Configure git: identity + gh as github.com credential helper.
# ---------------------------------------------------------------------------
configure_git() {
    if ! command -v git >/dev/null 2>&1; then
        warn "git not installed — skipping git configuration."
        return
    fi
    local git_author_name="${AAB_GIT_AUTHOR_NAME:-}"
    local git_author_email="${AAB_GIT_AUTHOR_EMAIL:-}"
    if [ -n "$git_author_name" ]; then
        git config --global user.name "$git_author_name"
        log "git user.name = $git_author_name"
    fi
    if [ -n "$git_author_email" ]; then
        git config --global user.email "$git_author_email"
        log "git user.email = $git_author_email"
    fi
    if command -v gh >/dev/null 2>&1; then
        git config --global 'credential.https://github.com.helper' '!gh auth git-credential'
        log "Registered gh as github.com credential helper."
    fi
}

# ---------------------------------------------------------------------------
# 9b. Install SSH keys supplied via $AAB_GH_AUTH_SSH_PRIVATE_KEY_B64 (for
# github.com auth: clone/push over SSH) and/or
# $AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64 (for git commit/tag signing). These are
# two separate roles and the
# bootstrap treats them independently: either may be set, or both, or
# neither. The signing key path does NOT touch ~/.ssh/config.
# ---------------------------------------------------------------------------

# _ensure_ssh_keygen: Idempotently install openssh-client if ssh-keygen is
# missing. Returns 0 iff ssh-keygen is callable afterward.
_ensure_ssh_keygen() {
    command -v ssh-keygen >/dev/null 2>&1 && return 0
    if ! command -v apt-get >/dev/null 2>&1; then
        warn "ssh-keygen not installed and apt-get unavailable."
        return 1
    fi
    if [ -n "$SUDO" ] && ! sudo -n true 2>/dev/null; then
        warn "ssh-keygen not installed and passwordless sudo unavailable."
        return 1
    fi
    log "Installing openssh-client for ssh-keygen."
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssh-client
    command -v ssh-keygen >/dev/null 2>&1
}

# _decode_ssh_key <encoded> <dest> <label>
# Decodes a base64-encoded OpenSSH private key to <dest> (mode 0600) and
# derives the public half to <dest>.pub (mode 0644). <label> is the env
# var name for log / warn messages. Returns 0 on success. On failure,
# cleans up any partial files and warns with <label> for context.
_decode_ssh_key() {
    local encoded="$1" dest="$2" label="$3"
    local dest_pub="${dest}.pub"

    mkdir -p "$SSH_DIR"
    chmod 0700 "$SSH_DIR"

    if ! printf '%s' "$encoded" | base64 -d > "$dest" 2>/dev/null; then
        warn "${label} is not valid base64; skipping."
        rm -f "$dest"
        return 1
    fi
    chmod 0600 "$dest"

    if ! ssh-keygen -y -f "$dest" > "$dest_pub" 2>/dev/null; then
        warn "${label} did not decode to a valid SSH private key; skipping."
        rm -f "$dest" "$dest_pub"
        return 1
    fi
    chmod 0644 "$dest_pub"
    return 0
}

# _rewrite_ssh_config_block: Idempotently rewrite the managed block in
# ~/.ssh/config so github.com uses the supplied IdentityFile. Strips any
# previous managed block plus its trailing padding so the file size stays
# stable across re-runs and pre-existing entries outside the block are
# preserved.
_rewrite_ssh_config_block() {
    local key="$1"
    touch "$SSH_CONFIG"
    python3 - "$SSH_CONFIG" "$key" "$SSH_MARKER_BEGIN" "$SSH_MARKER_END" <<'PY'
import sys
path, key, begin, end = sys.argv[1:5]
with open(path) as f:
    lines = f.read().splitlines()
out = []
in_block = False
for line in lines:
    if line == begin:
        in_block = True
        continue
    if line == end:
        in_block = False
        continue
    if not in_block:
        out.append(line)
while out and out[-1].strip() == "":
    out.pop()
block = [
    begin,
    "Host github.com",
    f"    IdentityFile {key}",
    "    IdentitiesOnly yes",
    end,
]
parts = []
if out:
    parts.append("\n".join(out))
    parts.append("")  # one blank line between user content and our block
parts.append("\n".join(block))
with open(path, "w") as f:
    f.write("\n".join(parts) + "\n")
PY
    chmod 0600 "$SSH_CONFIG"
}

# install_auth_ssh_key: Decode $AAB_GH_AUTH_SSH_PRIVATE_KEY_B64 to
# ~/.ssh/id_aab_auth and wire it as the IdentityFile for github.com in
# ~/.ssh/config. Does NOT touch git signing config. Silent no-op when the
# env var is unset.
install_auth_ssh_key() {
    local encoded="${AAB_GH_AUTH_SSH_PRIVATE_KEY_B64:-}"
    local label="AAB_GH_AUTH_SSH_PRIVATE_KEY_B64"
    [ -z "$encoded" ] && return

    if ! command -v base64 >/dev/null 2>&1; then
        warn "base64 not installed; cannot decode ${label}; skipping."
        return
    fi
    _ensure_ssh_keygen || { warn "Skipping ${label} install (ssh-keygen unavailable)."; return; }
    _decode_ssh_key "$encoded" "$AUTH_KEY" "$label" || return 0

    _rewrite_ssh_config_block "$AUTH_KEY"
    log "Installed GitHub auth SSH key at $AUTH_KEY (pub $AUTH_KEY_PUB); wired github.com identity in $SSH_CONFIG."
}

# install_signing_ssh_key: Decode $AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64 to
# ~/.ssh/id_aab_signing and configure git to sign commits/tags with it.
# Does NOT touch ~/.ssh/config — this key is for signing only. Silent
# no-op when the env var is unset.
install_signing_ssh_key() {
    local encoded="${AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64:-}"
    local label="AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64"
    [ -z "$encoded" ] && return

    if ! command -v base64 >/dev/null 2>&1; then
        warn "base64 not installed; cannot decode ${label}; skipping."
        return
    fi
    _ensure_ssh_keygen || { warn "Skipping ${label} install (ssh-keygen unavailable)."; return; }
    _decode_ssh_key "$encoded" "$SIGNING_KEY" "$label" || return 0

    if command -v git >/dev/null 2>&1; then
        git config --global gpg.format ssh
        git config --global user.signingkey "$SIGNING_KEY_PUB"
        git config --global commit.gpgsign true
        git config --global tag.gpgsign true
        log "Configured git to sign commits and tags with $SIGNING_KEY_PUB."
    else
        warn "git not installed; skipping SSH signing config."
    fi
}

# ---------------------------------------------------------------------------
# 9b-bis. Install gitleaks, the secret scanner the pre-commit hook runs. A
# single static Go binary (MIT, offline — no network at scan time), pinned to
# the same version and verified against the same per-arch SHA-256 the CI
# secret-scan job uses, so a commit blocked locally is a commit blocked in CI.
#
# Landed in ~/.local/bin (front of the managed PATH) so the hook finds it by
# name, with the absolute path as a fallback. Idempotent: a gitleaks already at
# the pinned version is left untouched. OS/arch-guarded: only linux x86_64 /
# arm64 release tarballs are pinned; anywhere else we skip cleanly and the hook
# falls back to its built-in shell secret grep. The download is verified before
# it is moved into place, so a corrupted or tampered fetch never installs.
# ---------------------------------------------------------------------------
install_gitleaks() {
    # Already at the pinned version? Leave it. `gitleaks version` prints a bare
    # version string (e.g. "8.18.4").
    if [ -x "$GITLEAKS_BIN" ] \
        && [ "$("$GITLEAKS_BIN" version 2>/dev/null | tr -d 'v[:space:]')" = "$GITLEAKS_VERSION" ]; then
        log "gitleaks ${GITLEAKS_VERSION} already installed at ${GITLEAKS_BIN}."
        return
    fi
    # A system-wide gitleaks at the pinned version (e.g. from CI's
    # /usr/local/bin install) also satisfies the requirement; the hook resolves
    # gitleaks via PATH first, so don't shadow it with a second copy.
    if command -v gitleaks >/dev/null 2>&1 \
        && [ "$(gitleaks version 2>/dev/null | tr -d 'v[:space:]')" = "$GITLEAKS_VERSION" ]; then
        log "gitleaks ${GITLEAKS_VERSION} already on PATH ($(command -v gitleaks)); not installing a second copy."
        return
    fi

    local os arch tarch sha
    os=$(uname -s 2>/dev/null || echo unknown)
    arch=$(uname -m 2>/dev/null || echo unknown)
    if [ "$os" != "Linux" ]; then
        warn "gitleaks: no pinned build for ${os}; skipping (the pre-commit hook's shell-grep fallback still scans commits)."
        return
    fi
    case "$arch" in
        x86_64|amd64) tarch="linux_x64";   sha="$GITLEAKS_SHA256_LINUX_X64" ;;
        aarch64|arm64) tarch="linux_arm64"; sha="$GITLEAKS_SHA256_LINUX_ARM64" ;;
        *)
            warn "gitleaks: no pinned build for ${arch}; skipping (the pre-commit hook's shell-grep fallback still scans commits)."
            return
            ;;
    esac

    if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
        warn "gitleaks: curl/tar unavailable; skipping install (the pre-commit hook's shell-grep fallback still scans commits)."
        return
    fi

    local url tmp
    url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_${tarch}.tar.gz"
    tmp=$(mktemp -d)
    log "Installing gitleaks ${GITLEAKS_VERSION} (${tarch}) for the pre-commit secret scan."
    if ! curl -fsSL "$url" -o "${tmp}/gitleaks.tar.gz"; then
        warn "gitleaks: download failed from ${url}; skipping (the pre-commit hook's shell-grep fallback still scans commits)."
        rm -rf "$tmp"
        return
    fi

    # Verify the tarball checksum before trusting its contents. Prefer
    # sha256sum, fall back to shasum -a 256 (neither is guaranteed on a bare
    # image, so degrade to a skip rather than install an unverified binary).
    local actual=""
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "${tmp}/gitleaks.tar.gz" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "${tmp}/gitleaks.tar.gz" | awk '{print $1}')
    else
        warn "gitleaks: no sha256sum/shasum to verify the download; skipping (the pre-commit hook's shell-grep fallback still scans commits)."
        rm -rf "$tmp"
        return
    fi
    if [ "$actual" != "$sha" ]; then
        warn "gitleaks: checksum mismatch (expected ${sha}, got ${actual}); refusing to install. The pre-commit hook's shell-grep fallback still scans commits."
        rm -rf "$tmp"
        return
    fi

    if ! tar -xzf "${tmp}/gitleaks.tar.gz" -C "$tmp" gitleaks 2>/dev/null; then
        warn "gitleaks: could not extract the binary from the tarball; skipping (the pre-commit hook's shell-grep fallback still scans commits)."
        rm -rf "$tmp"
        return
    fi
    mkdir -p "$(dirname "$GITLEAKS_BIN")"
    chmod 0755 "${tmp}/gitleaks"
    mv -f "${tmp}/gitleaks" "$GITLEAKS_BIN"
    rm -rf "$tmp"
    log "Installed gitleaks ${GITLEAKS_VERSION} at ${GITLEAKS_BIN}."
}

# ---------------------------------------------------------------------------
# 9c. Install a global git hook that enforces the bootstrap-configured git
# identity (and signing, when configured) on every commit, regardless of the
# repository the agent is working in.
#
# The motivation: agents routinely ignore the global git identity this script
# configures and commit under their own name/email via `git -c user.email=...`,
# `git commit --author=...`, GIT_AUTHOR_*/GIT_COMMITTER_* env vars, or a
# repo-local `git config user.email`. The agent rules written by
# write_agent_rules() ask them not to; this hook makes the ask
# non-optional.
#
# The same pre-commit hook also runs a staged-diff secret scan (gitleaks, with
# a built-in shell-grep fallback) so a secret never lands in a commit object —
# the failure that motivated it: an agent committed a live GitHub admin token
# because nothing scanned the diff locally.
#
# emit_git_hook_script writes the dispatcher to stdout so it can be both
# installed and linted (test.bash --lint shellchecks the emitted script). The
# dispatcher reads the expected identity from --global (which -c / env / config
# overrides cannot poison) and the actual identity from `git var`, which does
# reflect --author and GIT_*_ env vars. It then chains through to the repo's
# own hook of the same name so projects that ship hooks keep working — a global
# core.hooksPath replaces the per-repo hooks dir rather than adding to it.
# ---------------------------------------------------------------------------
emit_git_hook_script() {
    cat <<'HOOK'
#!/usr/bin/env bash
# autonomous-agent-bootstrap global git hook dispatcher. Installed by
# bootstrap.bash and pointed to by the global core.hooksPath. Every git hook
# name is a symlink to this one script.
#
# On pre-commit it (1) blocks commits whose author / committer identity (and,
# when global signing is on, whose signing config) does not match the global
# git config the bootstrap set up, and (2) blocks commits that stage a secret,
# scanning the staged diff with gitleaks (or a built-in shell-grep fallback).
# For every hook it then chains to the repository's own .git/hooks/<name> so
# project hooks keep running, since a global core.hooksPath replaces rather than
# supplements the per-repo hooks directory.
set -uo pipefail

hook_name=$(basename -- "$0")

# Extract a field from a `git var GIT_*_IDENT` value, formatted as
# "Name <email> <unixtime> <tz>".
_aab_ident_field() {
    case "$2" in
        name)  printf '%s' "$1" | sed -E 's/ <[^>]*> [0-9]+ [-+][0-9]+$//' ;;
        email) printf '%s' "$1" | sed -E 's/.*<([^>]*)> [0-9]+ [-+][0-9]+$/\1/' ;;
    esac
}

# Block the commit unless the author and committer identity match the global
# git config, and unless the globally-configured signing is honored. The
# expected values come from --global, which `git -c`, GIT_CONFIG_PARAMETERS,
# and a repo-local config cannot override; the actual values come from
# `git var`, which reflects `--author` and GIT_AUTHOR_*/GIT_COMMITTER_* env
# vars that the effective `git config user.email` does not.
_aab_enforce_commit_identity() {
    local exp_name exp_email
    exp_name=$(git config --global --get user.name 2>/dev/null || true)
    exp_email=$(git config --global --get user.email 2>/dev/null || true)

    # Nothing pinned in the global config — nothing to enforce.
    if [ -z "$exp_name" ] && [ -z "$exp_email" ]; then
        return 0
    fi

    local author committer a_name a_email c_name c_email
    author=$(git var GIT_AUTHOR_IDENT 2>/dev/null) || return 0
    committer=$(git var GIT_COMMITTER_IDENT 2>/dev/null) || return 0
    a_name=$(_aab_ident_field "$author" name)
    a_email=$(_aab_ident_field "$author" email)
    c_name=$(_aab_ident_field "$committer" name)
    c_email=$(_aab_ident_field "$committer" email)

    local bad=0
    if [ -n "$exp_email" ]; then
        [ "$a_email" = "$exp_email" ] || bad=1
        [ "$c_email" = "$exp_email" ] || bad=1
    fi
    if [ -n "$exp_name" ]; then
        [ "$a_name" = "$exp_name" ] || bad=1
        [ "$c_name" = "$exp_name" ] || bad=1
    fi
    if [ "$bad" -ne 0 ]; then
        {
            echo "[autonomous-agent-bootstrap] Commit blocked: identity does not match the global git config."
            echo "  expected:  ${exp_name} <${exp_email}>"
            echo "  author:    ${a_name} <${a_email}>"
            echo "  committer: ${c_name} <${c_email}>"
            echo "  Use the configured identity: plain 'git commit', without -c user.*, --author, or GIT_AUTHOR_*/GIT_COMMITTER_*."
            echo "  This rule is installed by autonomous-agent-bootstrap. See ~/.claude/CLAUDE.md and ~/.codex/AGENTS.md."
        } >&2
        return 1
    fi

    # When the global config requires signing, refuse a commit that disables it
    # via config (e.g. `-c commit.gpgsign=false`) or swaps the signing key. The
    # per-commit `--no-gpg-sign` flag is invisible to the hook, mirroring how
    # `--no-verify` skips hooks entirely.
    local exp_sign
    exp_sign=$(git config --global --get commit.gpgsign 2>/dev/null || true)
    if [ "$exp_sign" = "true" ]; then
        local eff_sign exp_key eff_key
        eff_sign=$(git config --type=bool --get commit.gpgsign 2>/dev/null || true)
        if [ "$eff_sign" != "true" ]; then
            echo "[autonomous-agent-bootstrap] Commit blocked: signing is required by the global git config but disabled for this commit." >&2
            return 1
        fi
        exp_key=$(git config --global --get user.signingkey 2>/dev/null || true)
        eff_key=$(git config --get user.signingkey 2>/dev/null || true)
        if [ -n "$exp_key" ] && [ "$eff_key" != "$exp_key" ]; then
            echo "[autonomous-agent-bootstrap] Commit blocked: signing key does not match the global git config." >&2
            return 1
        fi
    fi
    return 0
}

# Block the commit if a secret is staged. The motivation: an unattended agent
# committed a live GitHub admin token into a repo because nothing scanned the
# diff locally. This is the last line of defense before a secret reaches an
# object the agent might push.
#
# Preferred engine: gitleaks (`protect --staged`), a static binary the
# bootstrap installs. Resolved by name on PATH first, then at the bootstrap's
# install path, so it works even when the hook runs with a trimmed PATH. When
# gitleaks is absent (install skipped: unsupported arch, offline, checksum
# mismatch) we fall back to a POSIX-shell grep of the staged diff for the
# high-value credential shapes, so a commit is never left wholly unscanned.
#
# Escape hatch (use only when a "secret" is a deliberate fixture / test
# vector): set GITLEAKS_ALLOW=1 in the environment, or `git commit --no-verify`
# to skip every hook.
_aab_scan_secrets() {
    if [ "${GITLEAKS_ALLOW:-}" = "1" ]; then
        echo "[autonomous-agent-bootstrap] GITLEAKS_ALLOW=1 set — skipping the staged secret scan." >&2
        return 0
    fi

    # Nothing staged (e.g. an allowed-empty / amend-only commit): nothing to do.
    git diff --cached --quiet 2>/dev/null && return 0

    local gl=""
    if command -v gitleaks >/dev/null 2>&1; then
        gl=gitleaks
    elif [ -x "$HOME/.local/bin/gitleaks" ]; then
        gl="$HOME/.local/bin/gitleaks"
    fi

    if [ -n "$gl" ]; then
        # `protect --staged` scans the staged diff only (the about-to-be-committed
        # content) and exits nonzero on a finding. --redact keeps the secret value
        # out of the printed report; --no-banner quiets the startup art.
        if ! "$gl" protect --staged --redact --no-banner; then
            {
                echo "[autonomous-agent-bootstrap] Commit blocked: gitleaks found a secret in the staged changes (value redacted above)."
                echo "  Remove the secret from the staged content, then re-commit."
                echo "  If this is a deliberate fixture, bypass with GITLEAKS_ALLOW=1 git commit … or git commit --no-verify."
            } >&2
            return 1
        fi
        return 0
    fi

    # ---- Fallback: gitleaks unavailable. Grep the staged diff (added lines
    # only, to avoid re-flagging secrets already in history) for the
    # highest-value credential shapes. -E extended regex; case-sensitive on
    # purpose (the prefixes are case-significant).
    local added hit=0
    added=$(git diff --cached --no-color --diff-filter=ACMR -U0 2>/dev/null \
        | grep -E '^\+' | grep -Ev '^\+\+\+ ')
    [ -n "$added" ] || return 0

    # Pattern, human label. Each pattern targets a credential class that is both
    # high-confidence (low false-positive) and high-impact if leaked.
    local patterns=(
        'gh[pousr]_[0-9A-Za-z]{36,}|github_pat_[0-9A-Za-z_]{82}::GitHub token'
        'https?://[^/[:space:]:@]+:[^/[:space:]@]+@::URL-embedded credentials'
        'x-access-token:[0-9A-Za-z_]+::URL-embedded GitHub token'
        'AKIA[0-9A-Z]{16}::AWS access key id'
        'sk-[A-Za-z0-9_-]{20,}::OpenAI/Anthropic-style API key'
        'AIza[0-9A-Za-z_-]{35}::Google API key'
        'xox[baprs]-[0-9A-Za-z-]{10,}::Slack token'
        '-----BEGIN[A-Z ]*PRIVATE KEY-----::Private key block'
        'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+::JWT'
    )
    local entry pat label
    for entry in "${patterns[@]}"; do
        pat=${entry%%::*}
        label=${entry##*::}
        if printf '%s\n' "$added" | grep -Eq -- "$pat"; then
            echo "[autonomous-agent-bootstrap] Commit blocked: possible secret in staged changes — ${label}." >&2
            hit=1
        fi
    done
    if [ "$hit" -ne 0 ]; then
        {
            echo "  (Scanned with the built-in fallback; install gitleaks for full coverage.)"
            echo "  Remove the secret from the staged content, then re-commit."
            echo "  If this is a deliberate fixture, bypass with GITLEAKS_ALLOW=1 git commit … or git commit --no-verify."
        } >&2
        return 1
    fi
    return 0
}

if [ "$hook_name" = "pre-commit" ]; then
    _aab_enforce_commit_identity || exit 1
    _aab_scan_secrets || exit 1
fi

# Chain to the repository's own hook of the same name. The repo hooks dir is
# located via --git-common-dir (so linked worktrees share the main repo's
# hooks); --git-path is avoided because it honors core.hooksPath and would
# resolve back to this dispatcher.
common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
common_dir=$(cd "$common_dir" 2>/dev/null && pwd) || exit 0
repo_hook="$common_dir/hooks/$hook_name"
if [ -x "$repo_hook" ]; then
    self_dir=$(cd "$(dirname -- "$0")" 2>/dev/null && pwd || true)
    repo_target=$(readlink -f -- "$repo_hook" 2>/dev/null || echo "$repo_hook")
    self_target=$(readlink -f -- "${self_dir}/$(basename -- "$0")" 2>/dev/null || true)
    # Skip a repo hook that is just a symlink back to this dispatcher.
    if [ "$repo_target" != "$self_target" ]; then
        exec "$repo_hook" "$@"
    fi
fi
exit 0
HOOK
}

install_git_hooks() {
    if ! command -v git >/dev/null 2>&1; then
        warn "git not installed — skipping git hook enforcement."
        return
    fi

    mkdir -p "${GIT_HOOKS_DIR}"
    local tmp
    tmp=$(mktemp "${GIT_HOOK_DISPATCHER}.tmp.XXXXXX")
    emit_git_hook_script > "$tmp"
    chmod 0755 "$tmp"
    mv -f "$tmp" "${GIT_HOOK_DISPATCHER}"

    local name
    for name in "${GIT_HOOK_NAMES[@]}"; do
        ln -sf "aab-git-hook" "${GIT_HOOKS_DIR}/${name}"
    done

    git config --global core.hooksPath "${GIT_HOOKS_DIR}"
    log "Installed global git hooks at ${GIT_HOOKS_DIR} and set core.hooksPath (enforces the global commit identity and scans staged commits for secrets)."
}

# ---------------------------------------------------------------------------
# 9d. Write the global agent rules to every harness's instruction file. Claude
# Code reads ~/.claude/CLAUDE.md and Codex reads ~/.codex/AGENTS.md for every
# session in every repository, so the rules land regardless of what a project's
# own CLAUDE.md / AGENTS.md says. The block carries the operating principles for
# an unattended agent in this sandbox, followed by the git-identity rule (also
# enforced by the hook installed above). The rules are wrapped in a managed
# block so re-runs replace them in place rather than stacking, and pre-existing
# user content in either file is preserved.
# ---------------------------------------------------------------------------
emit_agent_rules() {
    cat <<'RULES'
## Operating principles

- Be consistent.
- Be concise in replies.
- Act autonomously without seeking operator input.
- You are in a safe sandbox without credentials that could cause serious harm.

## Always use the configured git identity

Always commit and tag with the git identity this machine is configured with, and don't override it with `git -c`, `--author=`, `GIT_AUTHOR_*` / `GIT_COMMITTER_*` env vars, or a repo-local `git config`.
RULES
}

write_agent_rules() {
    _write_agent_rules_block() {
        local file="$1" dir
        dir=$(dirname -- "$file")
        mkdir -p "$dir"
        touch "$file"
        if grep -qF "${AGENT_RULES_MARKER_BEGIN}" "$file"; then
            local tmp
            tmp=$(mktemp)
            awk -v begin="${AGENT_RULES_MARKER_BEGIN}" -v end="${AGENT_RULES_MARKER_END}" '
                $0 == begin { skip=1; next }
                $0 == end   { skip=0; next }
                !skip { print }
            ' "$file" > "$tmp"
            # Drop trailing blank lines left behind so the file size stays
            # stable across re-runs.
            while [ -s "$tmp" ] && [ -z "$(tail -n 1 "$tmp")" ]; do
                sed -i '$ d' "$tmp"
            done
            mv "$tmp" "$file"
        fi
        {
            [ -s "$file" ] && printf '\n'
            printf '%s\n' "${AGENT_RULES_MARKER_BEGIN}"
            emit_agent_rules
            printf '%s\n' "${AGENT_RULES_MARKER_END}"
        } >> "$file"
    }

    _write_agent_rules_block "${CLAUDE_MEMORY_FILE}"
    log "Wrote agent rules to ${CLAUDE_MEMORY_FILE}."
    _write_agent_rules_block "${CODEX_AGENTS_FILE}"
    log "Wrote agent rules to ${CODEX_AGENTS_FILE}."
}

# ---------------------------------------------------------------------------
# 10. Install agent plugins listed in agent_plugins.txt.
#
# Each line is a GitHub owner/repo that hosts a plugin marketplace
# containing .claude-plugin/marketplace.json. Claude Code and Codex both
# understand that marketplace manifest. We fetch it once to discover the
# marketplace name and plugin names, then install the same resolved plugin
# selectors into both CLIs.
#
# The list is taken from (in order): $AAB_AGENT_PLUGINS_FILE, then
# ./agent_plugins.txt when present, otherwise $AAB_AGENT_PLUGINS_URL.
# ---------------------------------------------------------------------------
PLUGINS_DEFAULT_FILE="${PWD}/agent_plugins.txt"
PLUGINS_DEFAULT_URL="https://raw.githubusercontent.com/brycelelbach/autonomous-agent-bootstrap/main/agent_plugins.txt"
install_agent_plugins() {
    command -v python3 >/dev/null 2>&1 || { warn "python3 required for plugin install; skipping."; return; }
    local plugins_file="${AAB_AGENT_PLUGINS_FILE:-}"
    local plugins_url="${AAB_AGENT_PLUGINS_URL:-$PLUGINS_DEFAULT_URL}"
    local content=""
    if [ -n "$plugins_file" ] && [ -f "$plugins_file" ]; then
        content=$(cat "$plugins_file")
        log "Reading plugin list from ${plugins_file}."
    elif [ -z "$plugins_file" ] && [ -f "$PLUGINS_DEFAULT_FILE" ]; then
        content=$(cat "$PLUGINS_DEFAULT_FILE")
        log "Reading plugin list from ${PLUGINS_DEFAULT_FILE}."
    elif content=$(curl -fsSL "$plugins_url" 2>/dev/null); then
        log "Fetched plugin list from ${plugins_url}."
    else
        warn "Could not read plugin list (file=${plugins_file:-unset}, url=${plugins_url}); skipping plugin install."
        return
    fi

    # Strip comments and blanks into one repo per line.
    local -a repos=()
    while IFS= read -r line; do
        line="${line%%#*}"
        # trim
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] && continue
        repos+=("$line")
    done <<< "$content"

    if [ ${#repos[@]} -eq 0 ]; then
        log "Plugin list is empty; skipping plugin install."
        return
    fi

    # Private plugin repos need an authenticated fetch. Prefer `gh api` when
    # it's installed and authenticated (works for both public and private
    # repos); fall back to unauthenticated raw.githubusercontent.com so
    # public plugins still work on hosts without a gh login.
    local github_token="${GH_TOKEN:-${GITHUB_TOKEN:-${AAB_GH_TOKEN:-}}}"
    local -a github_env=(env)
    if [ -n "$github_token" ]; then
        github_env=(env "GH_TOKEN=$github_token")
    fi
    local use_gh=0
    if command -v gh >/dev/null 2>&1 && "${github_env[@]}" gh auth status >/dev/null 2>&1; then
        use_gh=1
    fi

    # Collect resolved tuples (repo|marketplace|plugin) for every plugin.
    local -a tuples=()
    local repo marketplace_json marketplace_name plugin_names plugin_name
    for repo in "${repos[@]}"; do
        marketplace_json=""
        for branch in main master; do
            if [ $use_gh -eq 1 ]; then
                marketplace_json=$("${github_env[@]}" gh api -H "Accept: application/vnd.github.v3.raw" \
                    "repos/${repo}/contents/.claude-plugin/marketplace.json?ref=${branch}" 2>/dev/null) \
                    || marketplace_json=""
            fi
            if [ -z "$marketplace_json" ]; then
                marketplace_json=$(curl -fsSL "https://raw.githubusercontent.com/${repo}/${branch}/.claude-plugin/marketplace.json" 2>/dev/null) \
                    || marketplace_json=""
            fi
            [ -n "$marketplace_json" ] && break
        done
        if [ -z "$marketplace_json" ]; then
            # Most commonly this means the repo is private and the caller
            # lacks access (or gh isn't authenticated). Plugin install is an
            # optional step; log and move on without failing the bootstrap.
            log "Could not fetch .claude-plugin/marketplace.json from ${repo} (private repo without access?); skipping."
            continue
        fi
        marketplace_name=$(printf '%s' "$marketplace_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("name",""))') || marketplace_name=""
        if [ -z "$marketplace_name" ]; then
            warn "${repo}/.claude-plugin/marketplace.json has no 'name'; skipping."
            continue
        fi
        plugin_names=$(printf '%s' "$marketplace_json" | python3 -c 'import json,sys; [print(p["name"]) for p in json.load(sys.stdin).get("plugins",[]) if p.get("name")]')
        if [ -z "$plugin_names" ]; then
            warn "${repo} marketplace lists no plugins; skipping."
            continue
        fi
        while IFS= read -r plugin_name; do
            [ -z "$plugin_name" ] && continue
            tuples+=("${repo}|${marketplace_name}|${plugin_name}")
        done <<< "$plugin_names"
    done

    if [ ${#tuples[@]} -eq 0 ]; then
        warn "No plugins resolved; skipping plugin install."
        return
    fi

    install_claude_code_plugins "${tuples[@]}"
    install_codex_plugins "${tuples[@]}"
}

install_claude_code_plugins() {
    local -a tuples=("$@")
    [ ${#tuples[@]} -eq 0 ] && return

    # Merge into ~/.claude/settings.json. write_settings has already run,
    # so the file exists and is valid JSON.
    python3 - "$SETTINGS_FILE" "${tuples[@]}" <<'PY'
import json, sys
path = sys.argv[1]
tuples = sys.argv[2:]
with open(path) as f:
    data = json.load(f)
extra = data.setdefault("extraKnownMarketplaces", {})
enabled = data.setdefault("enabledPlugins", {})
for t in tuples:
    repo, marketplace, plugin = t.split("|", 2)
    extra[marketplace] = {"source": {"source": "github", "repo": repo}}
    enabled[f"{plugin}@{marketplace}"] = True
    print(f"[bootstrap] Enabled plugin {plugin}@{marketplace} from github {repo}.")
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY

    # settings.json's extraKnownMarketplaces and enabledPlugins are
    # advisory: Claude Code's `plugin` CLI maintains its own registry
    # at ~/.claude/plugins/{known_marketplaces,installed_plugins}.json
    # that only `claude plugin marketplace add` + `claude plugin
    # install` populate. Without those, every `claude` (and every
    # ACP-driven harness like @openclaw/acpx that spawns claude) starts
    # with an empty installed_plugins.json — the agent's session-start
    # skills list contains only the bundled defaults, none of the
    # user-configured plugins. Materialise the install here so the
    # bootstrap leaves the user with a fully-registered plugin set.
    local claude_bin=""
    if [ -x "${HOME}/.local/bin/claude-aab-real" ]; then
        claude_bin="${HOME}/.local/bin/claude-aab-real"
    elif command -v claude >/dev/null 2>&1; then
        claude_bin=$(command -v claude)
    elif [ -x "${HOME}/.local/bin/claude" ]; then
        claude_bin="${HOME}/.local/bin/claude"
    else
        warn "claude binary not on PATH; skipping Claude Code plugin install (settings.json was still written)."
        return
    fi
    local github_token="${GH_TOKEN:-${GITHUB_TOKEN:-${AAB_GH_TOKEN:-}}}"
    local -a github_env=(env)
    if [ -n "$github_token" ]; then
        github_env=(env "GH_TOKEN=$github_token")
    fi

    # Snapshot the post-write_settings + post-merge settings.json so
    # the re-merge below can restore AAB-managed top-level keys that
    # Claude Code's plugin CLI strips on re-serialise.
    cp "$SETTINGS_FILE" "${SETTINGS_FILE}.pre-plugin-install.bak"

    # Dedupe repos before `marketplace add` (one marketplace can ship
    # several plugins; a 1-to-1 add per tuple would re-clone N times).
    local -A seen_repos=()
    local t repo marketplace plugin
    for t in "${tuples[@]}"; do
        repo="${t%%|*}"
        if [ -z "${seen_repos[$repo]:-}" ]; then
            log "Adding marketplace ${repo} to claude's plugin registry."
            "${github_env[@]}" "$claude_bin" plugin marketplace add "$repo" 2>&1 | sed 's/^/  /' || \
                warn "claude plugin marketplace add ${repo} returned non-zero (private repo without access? skipping)."
            seen_repos[$repo]=1
        fi
    done

    for t in "${tuples[@]}"; do
        repo="${t%%|*}"
        marketplace="${t#*|}"
        plugin="${marketplace#*|}"
        marketplace="${marketplace%|*}"
        log "Installing Claude Code plugin ${plugin}@${marketplace}."
        "${github_env[@]}" "$claude_bin" plugin install "${plugin}@${marketplace}" --scope user 2>&1 | sed 's/^/  /' || \
            warn "claude plugin install ${plugin}@${marketplace} returned non-zero."
    done

    # `claude plugin marketplace add` / `claude plugin install --scope
    # user` re-serialise ~/.claude/settings.json against Claude Code's
    # internal schema, which drops any top-level keys the schema
    # doesn't enumerate (notably `effortLevel` — written by
    # write_settings, asserted by tests/e2e-assertions.bash). Re-merge
    # the AAB-managed top-level keys back in from a snapshot taken
    # before the claude calls ran so the on-disk shape stays a
    # superset of what write_settings produced.
    if [ -f "${SETTINGS_FILE}.pre-plugin-install.bak" ]; then
        python3 - "$SETTINGS_FILE" "${SETTINGS_FILE}.pre-plugin-install.bak" <<'PY'
import json, sys
live_path, snap_path = sys.argv[1], sys.argv[2]
with open(live_path) as f:
    live = json.load(f)
with open(snap_path) as f:
    snap = json.load(f)
# Re-merge keys that AAB owns but Claude Code's plugin CLI strips on
# re-serialise. Keep the live values for keys the CLI updated.
for k in ("model", "effortLevel", "permissions", "skipDangerousModePermissionPrompt", "env"):
    if k in snap and k not in live:
        live[k] = snap[k]
with open(live_path, "w") as f:
    json.dump(live, f, indent=2)
PY
        rm -f "${SETTINGS_FILE}.pre-plugin-install.bak"
    fi
}

install_codex_plugins() {
    local -a tuples=("$@")
    [ ${#tuples[@]} -eq 0 ] && return

    local codex_bin=""
    if [ -x "${HOME}/.local/bin/codex-aab-real" ]; then
        codex_bin="${HOME}/.local/bin/codex-aab-real"
    elif command -v codex >/dev/null 2>&1; then
        codex_bin=$(command -v codex)
    elif [ -x "${HOME}/.local/bin/codex" ]; then
        codex_bin="${HOME}/.local/bin/codex"
    else
        warn "codex binary not on PATH; skipping Codex plugin install."
        return
    fi
    local github_token="${GH_TOKEN:-${GITHUB_TOKEN:-${AAB_GH_TOKEN:-}}}"
    local -a github_env=(env)
    if [ -n "$github_token" ]; then
        github_env=(env "GH_TOKEN=$github_token")
    fi

    # Dedupe repos before `marketplace add`.
    local -A seen_repos=()
    local t repo marketplace plugin
    for t in "${tuples[@]}"; do
        repo="${t%%|*}"
        if [ -z "${seen_repos[$repo]:-}" ]; then
            log "Adding marketplace ${repo} to codex's plugin registry."
            "${github_env[@]}" "$codex_bin" plugin marketplace add "$repo" 2>&1 | sed 's/^/  /' || \
                warn "codex plugin marketplace add ${repo} returned non-zero (private repo without access? skipping)."
            seen_repos[$repo]=1
        fi
    done

    for t in "${tuples[@]}"; do
        repo="${t%%|*}"
        marketplace="${t#*|}"
        plugin="${marketplace#*|}"
        marketplace="${marketplace%|*}"
        log "Installing Codex plugin ${plugin}@${marketplace}."
        "${github_env[@]}" "$codex_bin" plugin add "${plugin}@${marketplace}" 2>&1 | sed 's/^/  /' || \
            warn "codex plugin add ${plugin}@${marketplace} returned non-zero."
    done
}


# ---------------------------------------------------------------------------
# 10b. Install Claude and Codex launcher wrapper families.
# ---------------------------------------------------------------------------
_is_aab_launcher_symlink_target() {
    case "$(basename "$1")" in
        claude-first-party|claude-third-party-anthropic|claude-third-party-deepseek|claude-third-party-nemotron|codex-first-party|codex-third-party-openai|codex-third-party-nemotron|codex-third-party-deepseek)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

_prepare_launcher_real_binary() {
    local agent_name="$1" agent_bin="$2" real_bin="$3" marker="$4"

    if [ ! -e "$agent_bin" ]; then
        warn "${agent_name} binary not found at ${agent_bin}; cannot install launcher wrappers."
        exit 1
    fi

    if [ -L "$agent_bin" ]; then
        local target
        target=$(readlink "$agent_bin")
        if _is_aab_launcher_symlink_target "$target"; then
            if [ ! -e "$real_bin" ]; then
                warn "${agent_name} launcher is installed but ${real_bin} is missing."
                exit 1
            fi
            return
        fi
        ln -sfn "$target" "$real_bin"
    elif ! grep -q "$marker" "$agent_bin" 2>/dev/null; then
        mv "$agent_bin" "$real_bin"
    elif [ ! -e "$real_bin" ]; then
        warn "${agent_name} launcher is installed but ${real_bin} is missing."
        exit 1
    fi
}

_write_claude_launcher() {
    local provider="$1" launcher="$2" tmp
    tmp=$(mktemp "${launcher}.tmp.XXXXXX")
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' '# Autonomous-agent-bootstrap Claude launcher.'
        printf 'provider=%q\n' "$provider"
        printf 'default_model=%q\n' "$DEFAULT_CLAUDE_CODE_MODEL"
        printf 'default_haiku_model=%q\n' "$DEFAULT_CLAUDE_CODE_HAIKU_MODEL"
        printf 'default_sonnet_model=%q\n' "$DEFAULT_CLAUDE_CODE_SONNET_MODEL"
        printf 'default_opus_model=%q\n' "$DEFAULT_CLAUDE_CODE_OPUS_MODEL"
        printf 'default_effort=%q\n' "$DEFAULT_CLAUDE_CODE_EFFORT"
        cat <<'BASH'
set -euo pipefail

real_bin="${AAB_CLAUDE_REAL_BIN:-$HOME/.local/bin/claude-aab-real}"
env_file="${AAB_ENV_FILE:-$HOME/.aab/.env}"
if [ -f "$env_file" ]; then
    set -a
    . "$env_file"
    set +a
fi

if [ ! -x "$real_bin" ]; then
    printf '[bootstrap] WARN: Claude real binary not executable: %s\n' "$real_bin" >&2
    exit 127
fi

export AAB_CLAUDE_CODE_INFERENCE_PROVIDER="$provider"
export CLAUDE_CODE_SANDBOXED=1
export DEBUG_SDK=1
export CLAUDE_CODE_EFFORT_LEVEL="${AAB_CLAUDE_CODE_EFFORT:-$default_effort}"
[ -n "${AAB_GH_TOKEN:-}" ] && export GH_TOKEN="$AAB_GH_TOKEN"
[ -n "${AAB_BREV_API_KEY:-}" ] && export BREV_API_KEY="$AAB_BREV_API_KEY"
[ -n "${AAB_BREV_ORG_ID:-}" ] && export BREV_ORG_ID="$AAB_BREV_ORG_ID"

unset ANTHROPIC_API_KEY
unset ANTHROPIC_BASE_URL
unset ANTHROPIC_AUTH_TOKEN
unset ANTHROPIC_MODEL
unset ANTHROPIC_DEFAULT_HAIKU_MODEL
unset ANTHROPIC_DEFAULT_SONNET_MODEL
unset ANTHROPIC_DEFAULT_OPUS_MODEL
unset CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS

case "$provider" in
    first-party)
        [ -n "${AAB_CLAUDE_CODE_FIRST_PARTY_API_KEY:-}" ] && export ANTHROPIC_API_KEY="$AAB_CLAUDE_CODE_FIRST_PARTY_API_KEY"
        export ANTHROPIC_MODEL="${AAB_CLAUDE_CODE_FIRST_PARTY_MODEL:-$default_model}"
        export ANTHROPIC_DEFAULT_HAIKU_MODEL="${AAB_CLAUDE_CODE_FIRST_PARTY_HAIKU_MODEL:-$default_haiku_model}"
        export ANTHROPIC_DEFAULT_SONNET_MODEL="${AAB_CLAUDE_CODE_FIRST_PARTY_SONNET_MODEL:-$default_sonnet_model}"
        export ANTHROPIC_DEFAULT_OPUS_MODEL="${AAB_CLAUDE_CODE_FIRST_PARTY_OPUS_MODEL:-$default_opus_model}"
        ;;
    third-party-anthropic)
        [ -n "${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_BASE_URL:-}" ] && export ANTHROPIC_BASE_URL="$AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_BASE_URL"
        [ -n "${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_API_KEY:-}" ] && export ANTHROPIC_AUTH_TOKEN="$AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_API_KEY"
        export ANTHROPIC_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_MODEL:-$default_model}"
        export ANTHROPIC_DEFAULT_HAIKU_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_HAIKU_MODEL:-$default_haiku_model}"
        export ANTHROPIC_DEFAULT_SONNET_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_SONNET_MODEL:-$default_sonnet_model}"
        export ANTHROPIC_DEFAULT_OPUS_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_OPUS_MODEL:-$default_opus_model}"
        ;;
    third-party-deepseek)
        [ -n "${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_BASE_URL:-}" ] && export ANTHROPIC_BASE_URL="$AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_BASE_URL"
        [ -n "${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_API_KEY:-}" ] && export ANTHROPIC_AUTH_TOKEN="$AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_API_KEY"
        # Claude Code resolves a model's context window to 200K unless the model
        # name carries a "[1m]" suffix (or is a known first-party id). Without a
        # known window, auto-compaction is also skipped in a local session, so
        # the conversation grows until the provider's hard limit. Tag the model
        # with "[1m]" so Claude Code resolves the full window and engages
        # compaction; the suffix is stripped from the model name before the
        # request, so the gateway still receives the real id (DeepSeek V4 Pro:
        # 1M context window).
        deepseek_model="${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_MODEL:-$default_model}"
        export ANTHROPIC_MODEL="${deepseek_model}[1m]"
        export ANTHROPIC_DEFAULT_HAIKU_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_HAIKU_MODEL:-$default_haiku_model}"
        export ANTHROPIC_DEFAULT_SONNET_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_SONNET_MODEL:-$default_sonnet_model}"
        export ANTHROPIC_DEFAULT_OPUS_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_OPUS_MODEL:-$default_opus_model}"
        # Pin the auto-compact window to DeepSeek's full 1M context. Compaction
        # then fires ~33K below it (~967K), the same window-minus-reserve margin
        # a first-party 1M model uses.
        export CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000
        ;;
    third-party-nemotron)
        [ -n "${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_BASE_URL:-}" ] && export ANTHROPIC_BASE_URL="$AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_BASE_URL"
        [ -n "${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_API_KEY:-}" ] && export ANTHROPIC_AUTH_TOKEN="$AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_API_KEY"
        # Tag the model with "[1m]" so Claude Code resolves the full configured
        # window and engages auto-compaction (see the deepseek arm above); the
        # suffix is stripped before the request, so the gateway receives the
        # real id. Nemotron 3 Ultra's window is 262,144, below the 1M the tag
        # unlocks, so the auto-compact window below is what actually applies.
        nemotron_model="${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_MODEL:-$default_model}"
        export ANTHROPIC_MODEL="${nemotron_model}[1m]"
        export ANTHROPIC_DEFAULT_HAIKU_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_HAIKU_MODEL:-$default_haiku_model}"
        export ANTHROPIC_DEFAULT_SONNET_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_SONNET_MODEL:-$default_sonnet_model}"
        export ANTHROPIC_DEFAULT_OPUS_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_OPUS_MODEL:-$default_opus_model}"
        # Pin the auto-compact window to Nemotron's full 262,144 context.
        # Compaction fires ~33K below it (~229K), the same window-minus-reserve
        # margin a first-party model uses, leaving headroom under the hard limit
        # (the failure this prevents hit ~268K with no compaction at all).
        export CLAUDE_CODE_AUTO_COMPACT_WINDOW=262144
        ;;
esac

# CLAUDE_CODE_SUBAGENT_MODEL pins the model for sub-agents and team teammates,
# which spawn as separate Claude Code processes and otherwise resolve a
# canonical first-party model id that a third-party gateway rejects. Default it
# to the same resolved ANTHROPIC_MODEL the main agent uses (provider-correct,
# carrying any "[1m]" suffix); AAB_CLAUDE_CODE_SUBAGENT_MODEL overrides.
export CLAUDE_CODE_SUBAGENT_MODEL="${AAB_CLAUDE_CODE_SUBAGENT_MODEL:-$ANTHROPIC_MODEL}"

has_skip=0
for arg in "$@"; do
    case "$arg" in
        --dangerously-skip-permissions)
            has_skip=1
            ;;
    esac
done

extra_args=()
if [ "$has_skip" -eq 0 ]; then
    extra_args=(--dangerously-skip-permissions)
fi

exec "$real_bin" "${extra_args[@]}" "$@"
BASH
    } > "$tmp"
    chmod 755 "$tmp"
    mv -f "$tmp" "$launcher"
}

install_claude_launcher() {
    local launcher_dir="${HOME}/.local/aab-bin"
    local claude_bin="${HOME}/.local/bin/claude"
    local real_bin="${HOME}/.local/bin/claude-aab-real"
    local selected_provider
    selected_provider=$(normalize_claude_code_inference_provider "${AAB_CLAUDE_CODE_INFERENCE_PROVIDER:-$DEFAULT_CLAUDE_CODE_INFERENCE_PROVIDER}")

    if [ ! -e "$claude_bin" ]; then
        warn "claude binary not found at ${claude_bin}; cannot install launcher wrappers."
        exit 1
    fi

    # The native installer owns ~/.local/bin/claude and repoints it to each new
    # version. Point the wrappers' exec target at that symlink (rather than a
    # pinned version) so every wrapper runs whatever the updater currently
    # installs. install_claude runs first in main(), so ~/.local/bin/claude is
    # the native binary here, never one of our wrapper symlinks.
    ln -sfn "$claude_bin" "$real_bin"
    _write_claude_launcher "first-party" "${HOME}/.local/bin/claude-first-party"
    _write_claude_launcher "third-party-anthropic" "${HOME}/.local/bin/claude-third-party-anthropic"
    _write_claude_launcher "third-party-deepseek" "${HOME}/.local/bin/claude-third-party-deepseek"
    _write_claude_launcher "third-party-nemotron" "${HOME}/.local/bin/claude-third-party-nemotron"

    # Put the selected `claude` entrypoint in a dedicated directory kept ahead of
    # ~/.local/bin on PATH (see update_bashrc / update_profile), so the native
    # auto-updater's ~/.local/bin/claude can't shadow the wrapper. The entrypoint
    # is a regular launcher file rather than a symlink to a provider wrapper.
    mkdir -p "$launcher_dir"
    _write_claude_launcher "$selected_provider" "${launcher_dir}/claude"
    log "Installed Claude launcher wrappers (selected=${selected_provider}); entrypoint at ${launcher_dir}/claude."
}

_write_codex_launcher() {
    local provider="$1" launcher="$2" tmp
    tmp=$(mktemp "${launcher}.tmp.XXXXXX")
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' '# Autonomous-agent-bootstrap Codex launcher.'
        printf 'provider=%q\n' "$provider"
        printf 'default_model=%q\n' "$DEFAULT_CODEX_MODEL"
        printf 'default_third_party_openai_model=%q\n' "$DEFAULT_CODEX_THIRD_PARTY_OPENAI_MODEL"
        printf 'default_third_party_openai_base_url=%q\n' "$DEFAULT_CODEX_THIRD_PARTY_OPENAI_BASE_URL"
        printf 'default_third_party_nemotron_model=%q\n' "$DEFAULT_CODEX_THIRD_PARTY_NEMOTRON_MODEL"
        printf 'default_third_party_nemotron_base_url=%q\n' "$DEFAULT_CODEX_THIRD_PARTY_NEMOTRON_BASE_URL"
        printf 'default_third_party_deepseek_model=%q\n' "$DEFAULT_CODEX_THIRD_PARTY_DEEPSEEK_MODEL"
        printf 'default_third_party_deepseek_base_url=%q\n' "$DEFAULT_CODEX_THIRD_PARTY_DEEPSEEK_BASE_URL"
        cat <<'BASH'
set -euo pipefail

real_bin="${AAB_CODEX_REAL_BIN:-$HOME/.local/bin/codex-aab-real}"
env_file="${AAB_ENV_FILE:-$HOME/.aab/.env}"
if [ -f "$env_file" ]; then
    set -a
    . "$env_file"
    set +a
fi

if [ ! -x "$real_bin" ]; then
    printf '[bootstrap] WARN: Codex real binary not executable: %s\n' "$real_bin" >&2
    exit 127
fi

toml_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    printf '%s' "$s"
}

canonical_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        (cd "$dir" 2>/dev/null && pwd -P) || printf '%s' "$dir"
    else
        printf '%s' "$dir"
    fi
}

export AAB_CODEX_INFERENCE_PROVIDER="$provider"
[ -n "${AAB_GH_TOKEN:-}" ] && export GH_TOKEN="$AAB_GH_TOKEN"
[ -n "${AAB_BREV_API_KEY:-}" ] && export BREV_API_KEY="$AAB_BREV_API_KEY"
[ -n "${AAB_BREV_ORG_ID:-}" ] && export BREV_ORG_ID="$AAB_BREV_ORG_ID"

model="${AAB_CODEX_FIRST_PARTY_MODEL:-$default_model}"
config_args=()
case "$provider" in
    first-party)
        [ -n "${AAB_CODEX_FIRST_PARTY_API_KEY:-}" ] && export OPENAI_API_KEY="$AAB_CODEX_FIRST_PARTY_API_KEY"
        model="${AAB_CODEX_FIRST_PARTY_MODEL:-$default_model}"
        model_escaped=$(toml_escape "$model")
        config_args=(-c "model=\"${model_escaped}\"" -c 'model_provider="openai"')
        ;;
    third-party-openai)
        unset OPENAI_API_KEY
        model="${AAB_CODEX_THIRD_PARTY_OPENAI_MODEL:-$default_third_party_openai_model}"
        base_url="${AAB_CODEX_THIRD_PARTY_OPENAI_BASE_URL:-$default_third_party_openai_base_url}"
        model_escaped=$(toml_escape "$model")
        base_url_escaped=$(toml_escape "$base_url")
        provider_override="model_providers={\"third-party-openai\"={name=\"Third Party OpenAI\",base_url=\"${base_url_escaped}\",env_key=\"AAB_CODEX_THIRD_PARTY_OPENAI_API_KEY\",wire_api=\"responses\",request_max_retries=4,stream_max_retries=5,stream_idle_timeout_ms=300000}}"
        config_args=(-c "model=\"${model_escaped}\"" -c 'model_provider="third-party-openai"' -c "$provider_override")
        ;;
    third-party-nemotron)
        unset OPENAI_API_KEY
        model="${AAB_CODEX_THIRD_PARTY_NEMOTRON_MODEL:-$default_third_party_nemotron_model}"
        base_url="${AAB_CODEX_THIRD_PARTY_NEMOTRON_BASE_URL:-$default_third_party_nemotron_base_url}"
        model_escaped=$(toml_escape "$model")
        base_url_escaped=$(toml_escape "$base_url")
        provider_override="model_providers={\"third-party-nemotron\"={name=\"Third Party Nemotron\",base_url=\"${base_url_escaped}\",env_key=\"AAB_CODEX_THIRD_PARTY_NEMOTRON_API_KEY\",wire_api=\"responses\",request_max_retries=4,stream_max_retries=5,stream_idle_timeout_ms=300000}}"
        config_args=(-c "model=\"${model_escaped}\"" -c 'model_provider="third-party-nemotron"' -c "$provider_override")
        ;;
    third-party-deepseek)
        unset OPENAI_API_KEY
        model="${AAB_CODEX_THIRD_PARTY_DEEPSEEK_MODEL:-$default_third_party_deepseek_model}"
        base_url="${AAB_CODEX_THIRD_PARTY_DEEPSEEK_BASE_URL:-$default_third_party_deepseek_base_url}"
        model_escaped=$(toml_escape "$model")
        base_url_escaped=$(toml_escape "$base_url")
        provider_override="model_providers={\"third-party-deepseek\"={name=\"Third Party DeepSeek\",base_url=\"${base_url_escaped}\",env_key=\"AAB_CODEX_THIRD_PARTY_DEEPSEEK_API_KEY\",wire_api=\"responses\",request_max_retries=4,stream_max_retries=5,stream_idle_timeout_ms=300000}}"
        config_args=(-c "model=\"${model_escaped}\"" -c 'model_provider="third-party-deepseek"' -c "$provider_override")
        ;;
esac

cwd=$(canonical_dir "${PWD:-.}")
git_root=""
if command -v git >/dev/null 2>&1; then
    git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)
    if [ -n "$git_root" ]; then
        git_root=$(canonical_dir "$git_root")
    fi
fi

cwd_escaped=$(toml_escape "$cwd")
trust_override="projects={\"${cwd_escaped}\"={trust_level=\"trusted\"}"
if [ -n "$git_root" ] && [ "$git_root" != "$cwd" ]; then
    git_root_escaped=$(toml_escape "$git_root")
    trust_override="${trust_override},\"${git_root_escaped}\"={trust_level=\"trusted\"}"
fi
trust_override="${trust_override}}"

has_yolo=0
has_hook_bypass=0
for arg in "$@"; do
    case "$arg" in
        --dangerously-bypass-approvals-and-sandbox|--yolo)
            has_yolo=1
            ;;
        --dangerously-bypass-hook-trust)
            has_hook_bypass=1
            ;;
    esac
done

extra_args=("${config_args[@]}" -c "$trust_override")
if [ "$has_hook_bypass" -eq 0 ]; then
    extra_args=(--dangerously-bypass-hook-trust "${extra_args[@]}")
fi
if [ "$has_yolo" -eq 0 ]; then
    extra_args=(--dangerously-bypass-approvals-and-sandbox "${extra_args[@]}")
fi

exec "$real_bin" "${extra_args[@]}" "$@"
BASH
    } > "$tmp"
    chmod 755 "$tmp"
    mv -f "$tmp" "$launcher"
}

install_codex_launcher() {
    local codex_bin="${HOME}/.local/bin/codex"
    local real_bin="${HOME}/.local/bin/codex-aab-real"
    local selected_provider
    selected_provider=$(normalize_codex_inference_provider "${AAB_CODEX_INFERENCE_PROVIDER:-$DEFAULT_CODEX_INFERENCE_PROVIDER}")

    _prepare_launcher_real_binary "codex" "$codex_bin" "$real_bin" "Autonomous-agent-bootstrap Codex launcher"
    _write_codex_launcher "first-party" "${HOME}/.local/bin/codex-first-party"
    _write_codex_launcher "third-party-openai" "${HOME}/.local/bin/codex-third-party-openai"
    _write_codex_launcher "third-party-nemotron" "${HOME}/.local/bin/codex-third-party-nemotron"
    _write_codex_launcher "third-party-deepseek" "${HOME}/.local/bin/codex-third-party-deepseek"
    _write_codex_launcher "$selected_provider" "$codex_bin"
    log "Installed Codex launcher wrappers at ${HOME}/.local/bin (selected=${selected_provider})."
}


# ---------------------------------------------------------------------------
# 11. Rewrite the unattended-mode block in ~/.bashrc.
#
# The block is identified by the BEGIN/END markers. On re-run we strip the
# old block and append a fresh one. Credentials and provider model settings
# are written to ~/.aab/.env instead of ~/.bashrc.
# ---------------------------------------------------------------------------
update_bashrc() {
    touch "${BASHRC}"
    if grep -qF "${BASHRC_MARKER_BEGIN}" "${BASHRC}"; then
        local tmp
        tmp=$(mktemp)
        awk -v begin="${BASHRC_MARKER_BEGIN}" -v end="${BASHRC_MARKER_END}" '
            $0 == begin { skip=1; next }
            $0 == end   { skip=0; next }
            !skip { print }
        ' "${BASHRC}" > "$tmp"
        mv "$tmp" "${BASHRC}"
        log "Replaced existing autonomous-agent-bootstrap block in ${BASHRC}."
    fi

    local effort="${AAB_CLAUDE_CODE_EFFORT:-$DEFAULT_CLAUDE_CODE_EFFORT}"

    {
        printf '\n%s\n' "${BASHRC_MARKER_BEGIN}"
        printf '%s\n' \
            '# Sources env file created by the Claude Code native installer and' \
            '# ensures the AAB launcher dir (~/.local/aab-bin) is ahead of' \
            '# ~/.local/bin on PATH, so the native auto-updater that owns' \
            '# ~/.local/bin/claude cannot shadow the AAB provider wrapper.' \
            '# ~/.local/bin also carries the uv tool symlinks (ruff,' \
            '# pre-commit, autocuda), so a bare `ruff` / `pre-commit` resolves' \
            '# there ahead of the system dirs.' \
            '# DEBUG_SDK=1 turns on Claude Code debug logging, written to' \
            '# ~/.claude/debug/<uuid>.txt with latest symlinked to the current' \
            '# run and verbose tags enabled by the DEBUG_SDK gate.' \
            'if [ -f "$HOME/.local/bin/env" ]; then' \
            '    . "$HOME/.local/bin/env"' \
            'fi' \
            'export PATH="$HOME/.local/bin:$PATH"' \
            'export PATH="$HOME/.local/aab-bin:$PATH"' \
            'export CLAUDE_CODE_SANDBOXED=1' \
            'export DEBUG_SDK=1' \
            '# Neutralize a dead SSH agent socket. A forwarded SSH_AUTH_SOCK from' \
            '# an SSH login that has since disconnected lingers as a dead socket,' \
            '# and tmux re-injects it into every new pane. Nothing here consumes' \
            '# the agent — commit signing reads the on-disk key directly and' \
            '# GitHub auth is an HTTPS token — but a dead socket makes ssh-add and' \
            '# git signing probes fail or hang, which reads like broken signing.' \
            '# Keep the socket only when a live agent actually answers within 1s;' \
            '# a comms failure, a hang, or a missing socket file all mean it is' \
            '# gone. This re-runs per interactive shell, so it also catches the' \
            '# socket tmux re-injects on each new pane.' \
            'if [ -n "${SSH_AUTH_SOCK:-}" ]; then' \
            '    if [ ! -S "$SSH_AUTH_SOCK" ]; then' \
            '        unset SSH_AUTH_SOCK SSH_AGENT_PID' \
            '    elif command -v ssh-add >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then' \
            '        _aab_ssh_probe=$(timeout 1 ssh-add -l 2>&1); _aab_ssh_rc=$?' \
            '        case $_aab_ssh_rc in' \
            '            0) ;;' \
            '            *) case $_aab_ssh_probe in' \
            '                   *"no identities"*) ;;' \
            '                   *) unset SSH_AUTH_SOCK SSH_AGENT_PID ;;' \
            '               esac ;;' \
            '        esac' \
            '        unset _aab_ssh_probe _aab_ssh_rc' \
            '    fi' \
            'fi'
        printf 'export CLAUDE_CODE_EFFORT_LEVEL="%s"\n' "$effort"
        printf '%s\n' "${BASHRC_MARKER_END}"
    } >> "${BASHRC}"
    log "Wrote autonomous-agent-bootstrap block to ${BASHRC} (effort=${effort})."
}

# A login shell sources ~/.profile, which (per the distro default) prepends
# ~/.local/bin to PATH *after* sourcing ~/.bashrc — so a ~/.bashrc-only PATH
# tweak gets shadowed in login/SSH shells. Append the launcher-dir prepend at
# the end of ~/.profile so ~/.local/aab-bin stays ahead of ~/.local/bin there
# too. The managed block is replaced in place on re-run, so it never stacks.
update_profile() {
    touch "${PROFILE}"
    if grep -qF "${BASHRC_MARKER_BEGIN}" "${PROFILE}"; then
        local tmp
        tmp=$(mktemp)
        awk -v begin="${BASHRC_MARKER_BEGIN}" -v end="${BASHRC_MARKER_END}" '
            $0 == begin { skip=1; next }
            $0 == end   { skip=0; next }
            !skip { print }
        ' "${PROFILE}" > "$tmp"
        mv "$tmp" "${PROFILE}"
        log "Replaced existing autonomous-agent-bootstrap block in ${PROFILE}."
    fi

    {
        printf '\n%s\n' "${BASHRC_MARKER_BEGIN}"
        printf '%s\n' \
            '# Keep the AAB launcher dir ahead of ~/.local/bin for login shells,' \
            '# whose ~/.profile re-prepends ~/.local/bin after sourcing ~/.bashrc.' \
            '# The aab-bin prepend must be the last PATH mutation in the' \
            '# login-shell sequence; ~/.local/bin (with the uv tool symlinks for' \
            '# ruff / pre-commit / autocuda) stays ahead of the system dirs but' \
            '# behind it.' \
            'export PATH="$HOME/.local/aab-bin:$PATH"'
        printf '%s\n' "${BASHRC_MARKER_END}"
    } >> "${PROFILE}"
    log "Wrote autonomous-agent-bootstrap block to ${PROFILE}."
}

# ---------------------------------------------------------------------------
# 12. Remove stale /etc/environment managed blocks from older installs.
# ---------------------------------------------------------------------------
update_etc_environment() {
    [ -f "$ETC_ENV" ] || return 0
    grep -qF "$ETC_ENV_MARKER_BEGIN" "$ETC_ENV" || return 0

    if [ -n "$SUDO" ] && ! sudo -n true 2>/dev/null; then
        warn "Updating $ETC_ENV needs sudo and passwordless sudo is not available; stale AAB env vars may remain there."
        return
    fi

    local tmp
    tmp=$(mktemp)
    awk -v begin="${ETC_ENV_MARKER_BEGIN}" -v end="${ETC_ENV_MARKER_END}" '
        $0 == begin { skip=1; next }
        $0 == end   { skip=0; next }
        !skip { print }
    ' "$ETC_ENV" > "$tmp"

    $SUDO install -m 0644 "$tmp" "$ETC_ENV"
    rm -f "$tmp"
    log "Removed autonomous-agent-bootstrap block from $ETC_ENV."
}

# ---------------------------------------------------------------------------
# Optional config input (positional arg or stdin).
#
# main() picks one of three modes, in order:
#   1. positional path: `bash bootstrap.bash /path/to/aab.conf` — load_config_file
#      reads the file at the supplied path.
#   2. stdin pipe:      `bash bootstrap.bash <<EOF ... EOF` (or any non-TTY
#      stdin shape) — load_config_stdin reads stdin into a temp file and loads
#      that. The temp file is removed before main() returns.
#   3. neither:         the script runs with whatever env vars the shell
#      already has, no config-file step.
#
# In modes 1 and 2 the config text is sourced via `set -a; . <path>; set +a`.
# That's the standard bash idiom for KEY=VALUE files and gives the file
# access to the full shell language: `${VAR:-default}` expansions, `$(cmd)`
# substitutions, multi-line strings, comments, etc. Values containing shell
# metacharacters (`&`, `|`, `;`, `$`, etc.) need to be quoted; bare quoted
# `KEY=value` lines need no escaping.
#
# Caller-supplied env vars beat file values: load_config_{file,stdin}
# snapshot the exported environment before sourcing and replay it after, so
# a one-off `FOO=override bash bootstrap.bash /path/to/conf` debug invocation
# wins over whatever the file said. An explicitly-empty `FOO= bash …`
# counts as set and also wins (file cannot force-unset what the shell
# explicitly set).
# ---------------------------------------------------------------------------
load_config_file() {
    local f="$1"
    if [ ! -r "$f" ]; then
        warn "Config file '$f' not found or not readable."
        exit 1
    fi
    log "Loading config from $f (env vars already set in the shell take precedence)."
    _source_config "$f"
}

load_config_stdin() {
    local tmp
    tmp=$(mktemp)
    cat > "$tmp"
    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        return 0
    fi
    log "Loading config from stdin (env vars already set in the shell take precedence)."
    _source_config "$tmp"
    rm -f "$tmp"
}

# Source the config at <path> with auto-export, preserving caller-supplied env
# vars. `declare -px` snapshots every exported variable; we strip the
# readonly entries (re-eval'ing those would error) and rewrite `declare -x`
# as `export` so the snapshot restores at the calling shell's scope rather
# than going out of scope when the function returns.
_source_config() {
    local src="$1" snapshot
    snapshot=$(declare -px | grep -v '^declare -[a-z]*r' | sed 's/^declare -x /export /')
    set -a
    # shellcheck source=/dev/null
    . "$src"
    set +a
    eval "$snapshot"
}

main() {
    if [ -n "${1:-}" ]; then
        load_config_file "$1"
    elif [ ! -t 0 ]; then
        load_config_stdin
    fi
    install_base_deps
    enable_user_linger
    install_uv_tools
    install_claude
    install_codex
    install_brev
    configure_brev_auth
    ensure_gh
    write_settings
    write_aab_env_file
    write_codex_model_instructions
    write_codex_config
    configure_codex_auth
    skip_onboarding
    skip_brev_onboarding
    configure_git
    install_auth_ssh_key
    install_signing_ssh_key
    install_gitleaks
    install_git_hooks
    write_agent_rules
    install_agent_plugins
    install_claude_launcher
    install_codex_launcher
    install_private_autocuda
    run_autocuda_install
    update_bashrc
    update_profile
    update_etc_environment
    log "Done. Open a new shell (or 'source ~/.bashrc') so PATH updates take effect."
}

# `:-$0` covers the `curl ... | bash` case, where BASH_SOURCE is empty and
# would otherwise trip `set -u`.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
