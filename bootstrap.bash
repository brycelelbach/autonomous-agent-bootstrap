#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# GENERATED FILE: do not edit directly.
#
# Source lives in src/bootstrap/*.bash. Rebuild with:
#   python3 tools/compile_bootstrap.py
# -----------------------------------------------------------------------------

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
PI_OBSERVABILITY_ENV_FILE="${AAB_SHELL_CONFIG_DIR}/pi-observability.env"
PI_FAST_MODE_EXTENSION="${PI_DIR}/extensions/fast-mode.ts"
NODE_INSTALL_DIR="${HOME}/.local/share/aab/node"
BREV_DIR="${HOME}/.brev"
BREV_ONBOARDING="${BREV_DIR}/onboarding_step.json"
BASHRC="${HOME}/.bashrc"
PROFILE="${HOME}/.profile"
AAB_BOOTSTRAP_REPO="${AAB_BOOTSTRAP_REPO:-brycelelbach/autonomous-agent-bootstrap}"
AAB_BOOTSTRAP_REF="${AAB_BOOTSTRAP_REF:-generated}"
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

need_sudo() {
    if [ "$(id -u)" -eq 0 ]; then echo ""; else echo "sudo"; fi
}
SUDO=$(need_sudo)

# >>> src/bootstrap/00_versions.bash >>>
# ---------------------------------------------------------------------------
# Versions, immutable git refs, and release-asset checksums used directly by
# bootstrap modules. Package-list pins remain in their sidecar files.
# ---------------------------------------------------------------------------
CLAUDE_CODE_VERSION="2.1.212"
CODEX_VERSION="0.144.5"

NODE_VERSION="24.18.0"
NODE_SHA256_LINUX_X64="783130984963db7ba9cbd01089eaf2c2efb055c7c1693c943174b967b3050cb8"
NODE_SHA256_LINUX_ARM64="6b4484c2190274175df9aa8f28e2d758a819cb1c1fe6ab481e2f95b463ab8508"

PI_VERSION="0.80.10"
PI_NPM_PACKAGE="@earendil-works/pi-coding-agent"

BREV_VERSION="0.6.330"
BREV_SHA256_LINUX_AMD64="5a6e70374db9be33f85f299161733b4a8409840d47638c781429b96e8d53704f"
BREV_SHA256_LINUX_ARM64="d7e0426df7714a6a6f14d9dfa46bf82fd5f38a31f968a912ac6dfaf51728122c"

LIFEBOAT_REPO="brycelelbach/lifeboat"
LIFEBOAT_REF="380cfd61de7e1d22ce6d32d27f8d92d4b8685edb"

GH_VERSION="2.96.0"
GH_SHA256_LINUX_AMD64="83d5c2ccad5498f58bf6368acb1ab32588cf43ab3a4b1c301bf36328b1c8bd60"
GH_SHA256_LINUX_ARM64="06f86ec7103d41993b76cd78072f43595c34aaa56506d971d9860e67140bf909"

UV_VERSION="0.11.29"

AUTOCUDA_PRIVATE_REPO="brycelelbach-private/autocuda"

GITLEAKS_VERSION="8.18.4"
GITLEAKS_SHA256_LINUX_X64="ba6dbb656933921c775ee5a2d1c13a91046e7952e9d919f9bac4cec61d628e7d"
GITLEAKS_SHA256_LINUX_ARM64="bf5f7f466ebfade1296c8bd32cf7d3f592c2aa78836aa9980ffbe2cadca7a861"
# <<< src/bootstrap/00_versions.bash <<<

# >>> src/bootstrap/01_install_base_deps.bash >>>
# ---------------------------------------------------------------------------
# 0. Install the Ubuntu base dependencies listed in apt_packages.txt via
# apt-get. Bare container images ship with apt-get but nothing else, so we
# can't assume curl or python3 exist. The preferred versions are used when the
# current distribution provides them; otherwise its available versions are
# installed. apt no-ops packages that are already installed, so the whole list
# is installed unconditionally.
#
# The list is taken from (in order): $AAB_APT_PACKAGES_FILE, then
# ./apt_packages.txt when present, otherwise $AAB_APT_PACKAGES_URL.
# ---------------------------------------------------------------------------
APT_PACKAGES_DEFAULT_FILE="${PWD}/apt_packages.txt"
APT_PACKAGES_DEFAULT_URL="https://raw.githubusercontent.com/${AAB_BOOTSTRAP_REPO}/${AAB_BOOTSTRAP_REF}/apt_packages.txt"
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
        case "$line" in
            *=?*) ;;
            *)
                warn "apt package entry '${line}' is not version-pinned (expected package=version)."
                return 1
                ;;
        esac
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

    log "Updating apt package metadata."
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -y

    local -a install_packages=("${packages[@]}")
    if ! $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --simulate --allow-downgrades --no-install-recommends "${install_packages[@]}" >/dev/null 2>&1; then
        install_packages=()
        local package
        for package in "${packages[@]}"; do
            install_packages+=("${package%%=*}")
        done
        warn "Preferred apt package versions are unavailable on this distribution; using its available versions."
    fi

    log "Installing apt packages: ${install_packages[*]}."
    # Hosted Ubuntu images can carry newer packages from PPAs. When the
    # preferred versions are available, permit apt to restore them.
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades --no-install-recommends "${install_packages[@]}"
}
# <<< src/bootstrap/01_install_base_deps.bash <<<

# >>> src/bootstrap/03_install_claude.bash >>>
# ---------------------------------------------------------------------------
# 1. Install / upgrade Claude Code via the native installer.
# ---------------------------------------------------------------------------
install_claude() {
    log "Installing Claude Code ${CLAUDE_CODE_VERSION} via native installer..."
    curl -fsSL https://claude.ai/install.sh | bash -s -- "$CLAUDE_CODE_VERSION"
}
# <<< src/bootstrap/03_install_claude.bash <<<

# >>> src/bootstrap/04_install_codex.bash >>>
# ---------------------------------------------------------------------------
# 2. Install / upgrade Codex via OpenAI's standalone installer.
# ---------------------------------------------------------------------------
install_codex() {
    log "Installing Codex CLI ${CODEX_VERSION} via standalone installer..."
    local installer_url="https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/install.sh"
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
        _run_without_controlling_tty "${installer_env[@]}" bash "$installer" --release "$CODEX_VERSION"
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
# <<< src/bootstrap/04_install_codex.bash <<<

# >>> src/bootstrap/04_install_node.bash >>>
# ---------------------------------------------------------------------------
# Install the pinned Node.js runtime that backs Pi and its npm/git packages.
# ---------------------------------------------------------------------------
install_node() {
    local machine asset sha256
    machine=$(uname -m)
    case "$machine" in
        x86_64|amd64)
            asset="node-v${NODE_VERSION}-linux-x64.tar.gz"
            sha256="$NODE_SHA256_LINUX_X64"
            ;;
        aarch64|arm64)
            asset="node-v${NODE_VERSION}-linux-arm64.tar.gz"
            sha256="$NODE_SHA256_LINUX_ARM64"
            ;;
        *)
            warn "Node.js has no configured AAB release for ${machine}; skipping installation."
            return
            ;;
    esac

    local node_bin="${NODE_INSTALL_DIR}/bin/node"
    if [ -x "$node_bin" ] && [ "$("$node_bin" --version 2>/dev/null)" = "v${NODE_VERSION}" ]; then
        log "Node.js ${NODE_VERSION} is already installed at ${NODE_INSTALL_DIR}."
    else
        log "Installing Node.js ${NODE_VERSION} from the official release."
        local tmpdir archive extracted actual
        tmpdir=$(mktemp -d)
        archive="${tmpdir}/${asset}"
        extracted="${tmpdir}/${asset%.tar.gz}"
        curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/${asset}" -o "$archive"
        actual=$(sha256sum "$archive" | awk '{ print $1 }')
        if [ "$actual" != "$sha256" ]; then
            rm -rf "$tmpdir"
            warn "Node.js ${NODE_VERSION} checksum verification failed for ${asset}."
            exit 1
        fi
        tar -xzf "$archive" -C "$tmpdir"
        if [ ! -x "${extracted}/bin/node" ] || [ ! -x "${extracted}/bin/npm" ]; then
            rm -rf "$tmpdir"
            warn "Node.js release archive did not contain node and npm executables."
            exit 1
        fi
        mkdir -p "$(dirname "$NODE_INSTALL_DIR")" "${HOME}/.local/bin"
        rm -rf "$NODE_INSTALL_DIR"
        mv "$extracted" "$NODE_INSTALL_DIR"
        rm -rf "$tmpdir"
    fi

    local executable
    for executable in node npm npx corepack; do
        if [ -e "${NODE_INSTALL_DIR}/bin/${executable}" ]; then
            ln -sfn "${NODE_INSTALL_DIR}/bin/${executable}" "${HOME}/.local/bin/${executable}"
        fi
    done
    case ":${PATH}:" in
        *":${HOME}/.local/bin:"*) ;;
        *) export PATH="${HOME}/.local/bin:${PATH}" ;;
    esac
}
# <<< src/bootstrap/04_install_node.bash <<<

# >>> src/bootstrap/05_install_brev.bash >>>
# ---------------------------------------------------------------------------
# 3. Install the pinned Brev CLI release.
# ---------------------------------------------------------------------------
install_brev() {
    local arch sha256
    case "$(uname -m)" in
        x86_64|amd64)
            arch="amd64"
            sha256="$BREV_SHA256_LINUX_AMD64"
            ;;
        aarch64|arm64)
            arch="arm64"
            sha256="$BREV_SHA256_LINUX_ARM64"
            ;;
        *)
            warn "Unsupported architecture for Brev ${BREV_VERSION}: $(uname -m)."
            return
            ;;
    esac

    local asset tmp_dir archive
    asset="brev-cli_${BREV_VERSION}_linux_${arch}.tar.gz"
    tmp_dir=$(mktemp -d)
    archive="${tmp_dir}/${asset}"
    log "Installing Brev CLI ${BREV_VERSION} from its official release..."
    if ! curl -fsSL \
        "https://github.com/brevdev/brev-cli/releases/download/v${BREV_VERSION}/${asset}" \
        -o "$archive"; then
        rm -rf "$tmp_dir"
        warn "Could not download Brev CLI ${BREV_VERSION}."
        exit 1
    fi
    if ! printf '%s  %s\n' "$sha256" "$archive" | sha256sum -c - >/dev/null; then
        rm -rf "$tmp_dir"
        warn "Brev CLI ${BREV_VERSION} checksum verification failed."
        exit 1
    fi
    tar -xzf "$archive" -C "$tmp_dir"
    if [ ! -x "${tmp_dir}/brev" ]; then
        rm -rf "$tmp_dir"
        warn "Brev CLI ${BREV_VERSION} archive did not contain an executable brev binary."
        exit 1
    fi
    mkdir -p "${HOME}/.local/bin"
    install -m 0755 "${tmp_dir}/brev" "${HOME}/.local/bin/brev"
    rm -rf "$tmp_dir"
    log "Installed Brev CLI ${BREV_VERSION} to ${HOME}/.local/bin/brev."
}
# <<< src/bootstrap/05_install_brev.bash <<<

# >>> src/bootstrap/05_install_pi.bash >>>
# ---------------------------------------------------------------------------
# Install / upgrade Pi from its official npm package. The Node-backed CLI is
# required because Pi package installation shells out to npm for runtime
# dependencies.
# ---------------------------------------------------------------------------
install_pi() {
    if ! command -v npm >/dev/null 2>&1; then
        warn "npm is unavailable; cannot install Pi ${PI_VERSION}."
        exit 1
    fi

    local launcher="${HOME}/.local/bin/pi"
    if [ -f "$launcher" ] && [ ! -L "$launcher" ] \
        && grep -q 'Autonomous-agent-bootstrap Pi launcher' "$launcher" 2>/dev/null; then
        rm -f "$launcher"
    fi

    log "Installing Pi ${PI_VERSION} from ${PI_NPM_PACKAGE}."
    npm install --global --prefix "${HOME}/.local" --ignore-scripts --no-audit --no-fund \
        "${PI_NPM_PACKAGE}@${PI_VERSION}"

    local installed_cli="${HOME}/.local/lib/node_modules/${PI_NPM_PACKAGE}/dist/cli.js"
    if [ ! -x "$installed_cli" ]; then
        warn "Pi npm package did not install an executable CLI at ${installed_cli}."
        exit 1
    fi
    ln -sfn "$installed_cli" "${HOME}/.local/bin/pi-aab-real"
    log "Installed Pi ${PI_VERSION} at ${installed_cli}."
}
# <<< src/bootstrap/05_install_pi.bash <<<

# >>> src/bootstrap/06_install_gitleaks.bash >>>
# ---------------------------------------------------------------------------
# Install gitleaks, the secret scanner the pre-commit hook runs. A
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
# <<< src/bootstrap/06_install_gitleaks.bash <<<

# >>> src/bootstrap/07_install_lifeboat.bash >>>
# ---------------------------------------------------------------------------
# 3c. Install the lifeboat home-directory backup tool.
#
# lifeboat is a single self-contained bash script that tars a home directory,
# keeping git history, source, and docs while dropping regenerable bulk (build
# artifacts, profiler dumps, caches, virtualenvs). It is the recommended way to
# snapshot an agent's work before an ephemeral box is torn down. We fetch the
# script straight to ~/.local/bin (already on the managed PATH) and mark it
# executable. Best effort: a fetch failure warns rather than aborting the run.
#
# lifeboat prefers pigz for parallel compression and falls back to gzip, so no
# extra package is strictly required; pigz in apt_packages.txt just makes it
# faster on multi-core hosts.
# ---------------------------------------------------------------------------
install_lifeboat() {
    log "Installing / updating lifeboat backup tool..."
    local url="https://raw.githubusercontent.com/${LIFEBOAT_REPO}/${LIFEBOAT_REF}/lifeboat"
    local dest="${HOME}/.local/bin/lifeboat"
    mkdir -p "${HOME}/.local/bin"
    if curl -fsSL "$url" -o "${dest}.tmp"; then
        chmod +x "${dest}.tmp"
        mv -f "${dest}.tmp" "$dest"
        log "Installed lifeboat at ${dest}."
    else
        rm -f "${dest}.tmp"
        warn "Could not fetch lifeboat from ${url}; continuing without it."
    fi
}
# <<< src/bootstrap/07_install_lifeboat.bash <<<

# >>> src/bootstrap/08_install_gh.bash >>>
# ---------------------------------------------------------------------------
# 4. Install a pinned gh CLI standalone release. gh intentionally does not use
# apt so every apt invocation remains centralized in install_base_deps().
# ---------------------------------------------------------------------------
install_gh() {
    if command -v gh >/dev/null 2>&1 \
        && gh --version 2>/dev/null | head -n 1 | grep -q "gh version ${GH_VERSION} "; then
        log "gh ${GH_VERSION} already installed."
        return
    fi

    local arch sha256
    case "$(uname -m)" in
        x86_64|amd64)
            arch="amd64"
            sha256="$GH_SHA256_LINUX_AMD64"
            ;;
        aarch64|arm64)
            arch="arm64"
            sha256="$GH_SHA256_LINUX_ARM64"
            ;;
        *)
            warn "Unsupported architecture for gh ${GH_VERSION}: $(uname -m)."
            return
            ;;
    esac

    local tmp_dir archive extracted
    tmp_dir=$(mktemp -d)
    archive="${tmp_dir}/gh.tar.gz"
    extracted="${tmp_dir}/gh_${GH_VERSION}_linux_${arch}/bin/gh"
    if ! curl -fsSL \
        "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${arch}.tar.gz" \
        -o "$archive"; then
        warn "Could not download gh ${GH_VERSION}."
        rm -rf "$tmp_dir"
        return
    fi
    if ! printf '%s  %s\n' "$sha256" "$archive" | sha256sum -c - >/dev/null; then
        warn "Checksum verification failed for gh ${GH_VERSION}."
        rm -rf "$tmp_dir"
        return
    fi
    tar -xzf "$archive" -C "$tmp_dir"
    mkdir -p "${HOME}/.local/bin"
    install -m 0755 "$extracted" "${HOME}/.local/bin/gh"
    rm -rf "$tmp_dir"
    log "Installed gh ${GH_VERSION} to ${HOME}/.local/bin/gh."
}
# <<< src/bootstrap/08_install_gh.bash <<<

# >>> src/bootstrap/09_install_uv.bash >>>
# ---------------------------------------------------------------------------
# 4b. Ensure uv (the Python package / interpreter installer) is available,
# installing it via its official installer when absent. uv installs the CLI
# tools below and carries its own Python, so the bootstrap never depends on a
# system pip (a bare image ships python3 with no pip module). The shim lands in
# ~/.local/bin. Idempotent: a present uv is left untouched.
#
# The official installer wires ~/.local/bin into the managed ~/.bashrc /
# ~/.profile blocks, which only affect future shells — it is not on this live
# bootstrap process's PATH. uv's own shim and installed tool executables all
# land there, so we prepend it to the live PATH here, regardless of whether uv
# was already installed, so later install steps can find those tools.
# ---------------------------------------------------------------------------
install_uv() {
    if command -v uv >/dev/null 2>&1 \
        && uv --version 2>/dev/null | grep -q "^uv ${UV_VERSION} "; then
        UV_BIN=$(command -v uv)
    else
        log "Installing uv ${UV_VERSION} via the official installer."
        curl -fsSL "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh
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
# <<< src/bootstrap/09_install_uv.bash <<<

# >>> src/bootstrap/10_install_uv_tools.bash >>>
# ---------------------------------------------------------------------------
# 4d. Install the CLI tools listed in uv_tools.txt with `uv tool install`. Each
# tool gets its own isolated environment and its executables are symlinked into
# ~/.local/bin, which the managed PATH and the live-PATH prepend in install_uv
# both put ahead of the system dirs. The private autocuda package is installed
# separately. Idempotent: `uv tool install` is a no-op when the tool is already
# installed at the requested version.
#
# The list is taken from (in order): $AAB_UV_TOOLS_FILE, then ./uv_tools.txt
# when present, otherwise $AAB_UV_TOOLS_URL.
# ---------------------------------------------------------------------------
UV_TOOLS_DEFAULT_FILE="${PWD}/uv_tools.txt"
UV_TOOLS_DEFAULT_URL="https://raw.githubusercontent.com/${AAB_BOOTSTRAP_REPO}/${AAB_BOOTSTRAP_REF}/uv_tools.txt"
install_uv_tools() {
    install_uv
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
        case "$line" in
            *==?*) ;;
            *)
                warn "uv tool entry '${line}' is not version-pinned (expected package==version)."
                return 1
                ;;
        esac
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
# <<< src/bootstrap/10_install_uv_tools.bash <<<

# >>> src/bootstrap/11_install_agent_plugins.bash >>>
# ---------------------------------------------------------------------------
# Install agent plugins listed in agent_plugins.txt.
#
# Each line is a GitHub owner/repo that hosts a plugin marketplace
# containing .claude-plugin/marketplace.json. Claude Code and Codex both
# understand that marketplace manifest. We fetch it once to discover the
# marketplace name and plugin names, then install the same resolved plugin
# selectors into both CLIs.
#
# The compiler embeds agent_plugins.txt below. AAB_AGENT_PLUGINS_FILE can
# replace the compiled list for a one-off local build.
# ---------------------------------------------------------------------------
AGENT_PLUGINS_DEFAULT_CONTENT=$(cat <<'AAB_AGENT_PLUGINS_EOF'
# Agent plugin marketplaces installed by bootstrap.bash.
#
# One GitHub "owner/repo" per line. The repo must contain
# .claude-plugin/marketplace.json at the repository root. Claude Code and
# Codex both read that marketplace manifest to discover the marketplace
# name and the plugin name(s) to install.
#
# Lines beginning with '#' and blank lines are ignored. To install
# additional plugins, add their marketplace repos below.

brycelelbach/agitentic
brycelelbach-private/autocuda
AAB_AGENT_PLUGINS_EOF
)
install_agent_plugins() {
    command -v python3 >/dev/null 2>&1 || { warn "python3 required for plugin install; skipping."; return; }
    local plugins_file="${AAB_AGENT_PLUGINS_FILE:-}"
    local content="$AGENT_PLUGINS_DEFAULT_CONTENT"
    if [ -n "$plugins_file" ]; then
        if [ ! -f "$plugins_file" ]; then
            warn "Plugin list file ${plugins_file} does not exist; skipping plugin install."
            return
        fi
        content=$(cat "$plugins_file")
        log "Reading plugin list override from ${plugins_file}."
    else
        log "Reading plugin list compiled into bootstrap.bash."
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

    # Merge into ~/.claude/settings.json. configure_claude_settings has already run,
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

    # Snapshot the post-configure_claude_settings + post-merge settings.json so
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
    # configure_claude_settings, asserted by tests/e2e-assertions.bash). Re-merge
    # the AAB-managed top-level keys back in from a snapshot taken
    # before the claude calls ran so the on-disk shape stays a
    # superset of what configure_claude_settings produced.
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
# <<< src/bootstrap/11_install_agent_plugins.bash <<<

# >>> src/bootstrap/11_install_autocuda.bash >>>
# ---------------------------------------------------------------------------
# 4e. Install the private autocuda package as its own uv tool and run its
# plugin registration, best effort.
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
install_autocuda() {
    install_uv
    [ -n "${UV_BIN:-}" ] || { warn "uv unavailable; skipping autocuda install."; return; }

    local -a git_env=()
    mapfile -d '' git_env < <(_github_git_env)

    log "Force-reinstalling the private autocuda package as a uv tool (best effort)."
    "${git_env[@]}" "$UV_BIN" tool install --force --refresh \
        "git+https://github.com/${AUTOCUDA_PRIVATE_REPO}" 2>&1 | sed 's/^/  /' \
        || warn "Could not install autocuda (private repo without access, or its build toolchain is absent); continuing without it."

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
# <<< src/bootstrap/11_install_autocuda.bash <<<

# >>> src/bootstrap/11_install_pi_plugins.bash >>>
# ---------------------------------------------------------------------------
# Reinstall the Pi packages listed in pi_plugins.txt.
#
# The compiler embeds pi_plugins.txt below. AAB_PI_PLUGINS_FILE can replace
# the compiled list for a one-off local build.
# ---------------------------------------------------------------------------
PI_PLUGINS_DEFAULT_CONTENT=$(cat <<'AAB_PI_PLUGINS_EOF'
# Pi packages installed by bootstrap.bash.
#
# One Pi package source per line, using the same syntax accepted by
# `pi install`. AAB-owned Git repositories follow their default branches;
# third-party npm and Git packages use exact versions and immutable commits.
#
# Lines beginning with '#' and blank lines are ignored.

npm:pi-codex-goal@0.1.37
git:github.com/robobryce/pi-list-tools
git:github.com/robobryce/pi-local-otel
git:github.com/robobryce/pi-schedule-prompt
git:github.com/nicobailon/pi-subagents@ea9b72f2e5bc0e0cbaacdab589576e858b12c03f
git:github.com/robobryce/pi-bash-background
git:github.com/robobryce/pi-web-access
git:github.com/robobryce/pi-retry-empty
git:github.com/robobryce/pi-print-stream
AAB_PI_PLUGINS_EOF
)

_remove_legacy_pi_npm_packages() {
    local npm_root="$PI_NPM_DIR"
    local package_json="${npm_root}/package.json"
    local package_lock="${npm_root}/package-lock.json"
    if [ ! -d "${npm_root}/node_modules/pi-list-tools" ] \
        && [ ! -d "${npm_root}/node_modules/pi-print-stream" ] \
        && [ ! -d "${npm_root}/node_modules/pi-otel" ] \
        && { [ ! -f "$package_json" ] \
            || ! grep -Eq '"(pi-list-tools|pi-print-stream|pi-otel)"' "$package_json"; } \
        && { [ ! -f "$package_lock" ] \
            || ! grep -Eq '"node_modules/(pi-list-tools|pi-print-stream|pi-otel)"' "$package_lock"; }; then
        return
    fi

    local npm_bin="${HOME}/.local/bin/npm"
    if [ ! -x "$npm_bin" ]; then
        npm_bin=$(command -v npm || true)
    fi
    if [ -z "$npm_bin" ]; then
        warn "npm unavailable; obsolete Pi npm packages were not removed."
        return
    fi

    log "Removing obsolete Pi npm packages."
    "$npm_bin" uninstall --prefix "$npm_root" --ignore-scripts --no-audit --no-fund \
        pi-list-tools pi-print-stream pi-otel 2>&1 | sed 's/^/  /' \
        || warn "Could not remove obsolete Pi npm packages."
}

install_pi_plugins() {
    local pi_bin="${HOME}/.local/bin/pi-aab-real"
    if [ ! -x "$pi_bin" ]; then
        warn "Pi real binary not executable at ${pi_bin}; skipping Pi package installation."
        return
    fi

    _remove_legacy_pi_npm_packages

    local plugins_file="${AAB_PI_PLUGINS_FILE:-}"
    local content="$PI_PLUGINS_DEFAULT_CONTENT"
    if [ -n "$plugins_file" ]; then
        if [ ! -f "$plugins_file" ]; then
            warn "Pi package list file ${plugins_file} does not exist; skipping Pi package installation."
            return
        fi
        content=$(cat "$plugins_file")
        log "Reading Pi package list override from ${plugins_file}."
    else
        log "Reading Pi package list compiled into bootstrap.bash."
    fi

    local -a sources=()
    local line
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] && continue
        sources+=("$line")
    done <<< "$content"

    if [ ${#sources[@]} -eq 0 ]; then
        log "Pi package list is empty; skipping package installation."
        return
    fi

    local -a git_env=()
    mapfile -d '' git_env < <(_github_git_env)
    local source remove_output
    for source in "${sources[@]}"; do
        # Pi has no force-install option. Remove the managed package first so
        # an existing checkout or npm tree cannot make installation a no-op.
        # Missing settings entries are expected because configure_pi_settings
        # clears the package registry before this function runs.
        log "Reinstalling Pi package ${source}."
        remove_output=""
        if ! remove_output=$("${git_env[@]}" "$pi_bin" remove "$source" --no-approve 2>&1); then
            if [[ "$remove_output" != *"No matching package found"* ]]; then
                if [ -n "$remove_output" ]; then
                    printf '%s\n' "$remove_output" | sed 's/^/  /'
                fi
                warn "Pi package removal returned non-zero for ${source}; installation will still be attempted."
            fi
        fi
        "${git_env[@]}" "$pi_bin" install "$source" --no-approve 2>&1 | sed 's/^/  /' \
            || warn "Pi package install returned non-zero for ${source}."
    done
}
# <<< src/bootstrap/11_install_pi_plugins.bash <<<

# >>> src/bootstrap/12_configure_aab_env_file.bash >>>
# ---------------------------------------------------------------------------
# Persist shared model-profile and credential configuration in ~/.aab/.env.
# ---------------------------------------------------------------------------
configure_aab_env_file() {
    mkdir -p "${AAB_DIR}"
    chmod 700 "${AAB_DIR}"

    local claude_first_party_profiles claude_third_party_profiles
    local codex_first_party_profiles codex_third_party_profiles pi_profiles
    claude_first_party_profiles=$(_profile_list_for claude first-party)
    claude_third_party_profiles=$(_profile_list_for claude third-party)
    codex_first_party_profiles=$(_profile_list_for codex first-party)
    codex_third_party_profiles=$(_profile_list_for codex third-party)
    pi_profiles=$(_profile_list_for pi third-party)

    local -A claude_profile=() codex_profile=() pi_profile=()
    resolve_model_profile claude claude_profile
    resolve_model_profile codex codex_profile
    local pi_profile_name=""
    if resolve_model_profile pi pi_profile; then
        pi_profile_name="${pi_profile[name]}"
    fi

    local tmp
    tmp=$(mktemp "${AAB_ENV_FILE}.tmp.XXXXXX")
    {
        printf '# Written by autonomous-agent-bootstrap. Re-run bootstrap.bash to update.\n'
        _write_shell_export AAB_CLAUDE_FIRST_PARTY_PROFILES "$claude_first_party_profiles"
        _write_shell_export AAB_CLAUDE_THIRD_PARTY_PROFILES "$claude_third_party_profiles"
        _write_shell_export AAB_CLAUDE_DEFAULT_PROFILE "${claude_profile[source]}/${claude_profile[name]}"
        _write_shell_export AAB_CODEX_FIRST_PARTY_PROFILES "$codex_first_party_profiles"
        _write_shell_export AAB_CODEX_THIRD_PARTY_PROFILES "$codex_third_party_profiles"
        _write_shell_export AAB_CODEX_DEFAULT_PROFILE "${codex_profile[source]}/${codex_profile[name]}"
        _write_shell_export AAB_PI_PROFILES "$pi_profiles"
        _write_shell_export AAB_PI_DEFAULT_PROFILE "$pi_profile_name"
        _write_shell_export AAB_INFERENCE_GATEWAY_URL "${AAB_INFERENCE_GATEWAY_URL:-}"
        _write_shell_export AAB_INFERENCE_GATEWAY_API_KEY "${AAB_INFERENCE_GATEWAY_API_KEY:-}"
        _write_shell_export AAB_ANTHROPIC_API_KEY "${AAB_ANTHROPIC_API_KEY:-}"
        _write_shell_export AAB_OPENAI_API_KEY "${AAB_OPENAI_API_KEY:-}"
        _write_shell_export AAB_CODEX_SERVICE_TIER "${AAB_CODEX_SERVICE_TIER:-$DEFAULT_CODEX_SERVICE_TIER}"
        _write_shell_export AAB_CODEX_AGENT_MAX_THREADS "${AAB_CODEX_AGENT_MAX_THREADS:-$DEFAULT_CODEX_AGENT_MAX_THREADS}"
        _write_shell_export AAB_GH_TOKEN "${AAB_GH_TOKEN:-}"
        _write_shell_export AAB_BREV_API_KEY "${AAB_BREV_API_KEY:-}"
        _write_shell_export AAB_BREV_ORG_ID "${AAB_BREV_ORG_ID:-}"
    } > "$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$AAB_ENV_FILE"
    log "Wrote ${AAB_ENV_FILE} (claude_profile=${claude_profile[source]}/${claude_profile[name]}, codex_profile=${codex_profile[source]}/${codex_profile[name]}, pi_profile=${pi_profile_name:-none})."
}

configure_github_shell() {
    mkdir -p "${AAB_SHELL_CONFIG_DIR}"
    local tmp
    tmp=$(mktemp "${GITHUB_SHELL_CONFIG_FILE}.tmp.XXXXXX")
    {
        printf '# Generated by autonomous-agent-bootstrap.\n'
        if [ -n "${AAB_GH_TOKEN:-}" ]; then
            _write_shell_export GH_TOKEN "$AAB_GH_TOKEN"
        fi
    } > "$tmp"
    chmod 0600 "$tmp"
    mv -f "$tmp" "${GITHUB_SHELL_CONFIG_FILE}"
    log "Wrote GitHub shell configuration to ${GITHUB_SHELL_CONFIG_FILE}."
}
# <<< src/bootstrap/12_configure_aab_env_file.bash <<<

# >>> src/bootstrap/12_model_profiles.bash >>>
# ---------------------------------------------------------------------------
# Parse, validate, and resolve environment-defined model profiles.
# ---------------------------------------------------------------------------
_model_profile_lines() {
    local profiles="$1" line
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] && continue
        case "$line" in
            \#*) continue ;;
        esac
        printf '%s\n' "$line"
    done <<< "$profiles"
}

_profile_list_for() {
    local harness="$1" source="$2"
    case "${harness}/${source}" in
        claude/first-party)
            printf '%s' "${AAB_CLAUDE_FIRST_PARTY_PROFILES-$DEFAULT_CLAUDE_FIRST_PARTY_PROFILES}"
            ;;
        claude/third-party)
            printf '%s' "${AAB_CLAUDE_THIRD_PARTY_PROFILES-$DEFAULT_CLAUDE_THIRD_PARTY_PROFILES}"
            ;;
        codex/first-party)
            printf '%s' "${AAB_CODEX_FIRST_PARTY_PROFILES-$DEFAULT_CODEX_FIRST_PARTY_PROFILES}"
            ;;
        codex/third-party)
            printf '%s' "${AAB_CODEX_THIRD_PARTY_PROFILES-$DEFAULT_CODEX_THIRD_PARTY_PROFILES}"
            ;;
        pi/third-party)
            printf '%s' "${AAB_PI_PROFILES-$DEFAULT_PI_PROFILES}"
            ;;
        *)
            warn "Unknown model-profile group '${harness}/${source}'."
            return 1
            ;;
    esac
}

_parse_model_profile_line() {
    local harness="$1" source="$2" line="$3" result_name="$4"
    local -n result="$result_name"
    local -a fields
    local field key value
    local -A seen_fields=()

    read -r -a fields <<< "$line"
    if [ "${#fields[@]}" -eq 0 ]; then
        warn "Empty ${harness} ${source} model profile."
        return 1
    fi

    result=()
    result[harness]="$harness"
    result[source]="$source"
    result[name]="${fields[0]}"
    result[model]="${fields[0]}"
    result[context]=""
    result["max_tokens"]=""
    result[subagent]=""
    result[thinking]=""
    result["fast"]=""
    case "$harness" in
        claude)
            result[effort]="$DEFAULT_CLAUDE_CODE_EFFORT"
            ;;
        codex)
            result[effort]="$DEFAULT_CODEX_REASONING_EFFORT"
            ;;
        pi)
            result[effort]="$DEFAULT_PI_EFFORT"
            ;;
        *)
            warn "Unknown model-profile harness '${harness}'."
            return 1
            ;;
    esac

    if [[ ! "${result[name]}" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
        warn "Invalid ${harness} ${source} profile name '${result[name]}'; use lowercase letters, digits, dots, and hyphens."
        return 1
    fi

    for field in "${fields[@]:1}"; do
        case "$field" in
            \#*) break ;;
        esac
        if [[ "$field" != *=* ]]; then
            warn "Invalid field '${field}' in ${harness} ${source} profile '${result[name]}'; expected key=value."
            return 1
        fi
        key="${field%%=*}"
        value="${field#*=}"
        if [ -z "$value" ]; then
            warn "Empty field '${key}' in ${harness} ${source} profile '${result[name]}'."
            return 1
        fi
        if [ -n "${seen_fields[$key]:-}" ]; then
            warn "Duplicate field '${key}' in ${harness} ${source} profile '${result[name]}'."
            return 1
        fi
        seen_fields[$key]=1

        case "${harness}/${key}" in
            claude/model|claude/effort|claude/context|claude/subagent|claude/haiku|claude/sonnet|claude/opus|codex/model|codex/effort|codex/fast|pi/model|pi/effort|pi/context|pi/max_tokens|pi/fast)
                result[$key]="$value"
                ;;
            *)
                warn "Unknown field '${key}' in ${harness} ${source} profile '${result[name]}'."
                return 1
                ;;
        esac
    done

    case "${result[context]}" in
        "") ;;
        *[!0-9]*|0)
            warn "context='${result[context]}' in ${harness} ${source} profile '${result[name]}' is not a positive integer."
            return 1
            ;;
    esac
    case "${result["max_tokens"]}" in
        "") ;;
        *[!0-9]*|0)
            warn "max_tokens='${result["max_tokens"]}' in ${harness} ${source} profile '${result[name]}' is not a positive integer."
            return 1
            ;;
    esac
    case "${result[fast]}" in
        ""|true|false) ;;
        *)
            warn "fast='${result[fast]}' in ${harness} ${source} profile '${result[name]}' must be true or false."
            return 1
            ;;
    esac

    if [ "$harness" = "claude" ]; then
        result[haiku]="${result[haiku]:-${result[model]}}"
        result[sonnet]="${result[sonnet]:-${result[model]}}"
        result[opus]="${result[opus]:-${result[model]}}"
        result[subagent]="${result[subagent]:-${result[model]}}"
    elif [ "$harness" = "pi" ]; then
        case "${result[effort]}" in
            off|minimal|low|medium|high|xhigh|max)
                result[thinking]="${result[effort]}"
                ;;
            *)
                result[thinking]="xhigh"
                ;;
        esac
    fi
}

_validate_model_profile_list() {
    local harness="$1" source="$2" profiles="$3" line
    local -A profile=() seen_names=()
    while IFS= read -r line; do
        _parse_model_profile_line "$harness" "$source" "$line" profile || return 1
        if [ -n "${seen_names[${profile[name]}]:-}" ]; then
            warn "Duplicate ${harness} ${source} profile '${profile[name]}'."
            return 1
        fi
        seen_names[${profile[name]}]=1
    done < <(_model_profile_lines "$profiles")
}

validate_model_profiles() {
    local harness source profiles
    local -A selected=()
    for harness in claude codex; do
        for source in first-party third-party; do
            profiles=$(_profile_list_for "$harness" "$source")
            _validate_model_profile_list "$harness" "$source" "$profiles" || return 1
        done
    done
    profiles=$(_profile_list_for pi third-party)
    _validate_model_profile_list pi third-party "$profiles" || return 1

    resolve_model_profile claude selected || return 1
    resolve_model_profile codex selected || return 1
    if [ "${AAB_PI_DEFAULT_PROFILE+x}" = x ] || [ -n "$(_model_profile_lines "$profiles")" ]; then
        resolve_model_profile pi selected || return 1
    fi
}

_find_model_profile() {
    local harness="$1" source="$2" name="$3" result_name="$4"
    local profiles line
    local -A candidate=()
    profiles=$(_profile_list_for "$harness" "$source")
    while IFS= read -r line; do
        _parse_model_profile_line "$harness" "$source" "$line" candidate || return 1
        if [ "${candidate[name]}" = "$name" ]; then
            _parse_model_profile_line "$harness" "$source" "$line" "$result_name"
            return
        fi
    done < <(_model_profile_lines "$profiles")
    return 1
}

_first_model_profile() {
    local harness="$1" source="$2" result_name="$3"
    local profiles line
    profiles=$(_profile_list_for "$harness" "$source")
    while IFS= read -r line; do
        _parse_model_profile_line "$harness" "$source" "$line" "$result_name"
        return
    done < <(_model_profile_lines "$profiles")
    return 1
}

resolve_model_profile() {
    local harness="$1" result_name="$2"
    local selection explicit_selection=0 source name

    case "$harness" in
        claude)
            if [ "${AAB_CLAUDE_DEFAULT_PROFILE+x}" = x ]; then
                selection="$AAB_CLAUDE_DEFAULT_PROFILE"
                explicit_selection=1
            else
                selection="$DEFAULT_CLAUDE_PROFILE"
            fi
            ;;
        codex)
            if [ "${AAB_CODEX_DEFAULT_PROFILE+x}" = x ]; then
                selection="$AAB_CODEX_DEFAULT_PROFILE"
                explicit_selection=1
            else
                selection="$DEFAULT_CODEX_PROFILE"
            fi
            ;;
        pi)
            if [ "${AAB_PI_DEFAULT_PROFILE+x}" = x ]; then
                selection="$AAB_PI_DEFAULT_PROFILE"
                explicit_selection=1
            else
                selection="$DEFAULT_PI_PROFILE"
            fi
            if [ -n "$selection" ] && _find_model_profile pi third-party "$selection" "$result_name"; then
                return 0
            fi
            if [ "$explicit_selection" -eq 1 ]; then
                warn "AAB_PI_DEFAULT_PROFILE='${selection}' does not name a configured Pi profile."
                return 1
            fi
            _first_model_profile pi third-party "$result_name"
            return
            ;;
        *)
            warn "Unknown model-profile harness '${harness}'."
            return 1
            ;;
    esac

    if [[ "$selection" == */* ]]; then
        source="${selection%%/*}"
        name="${selection#*/}"
    else
        source=""
        name="$selection"
    fi
    case "$source" in
        first-party|third-party) ;;
        *)
            warn "AAB_${harness^^}_DEFAULT_PROFILE='${selection}' must use first-party/<profile> or third-party/<profile>."
            return 1
            ;;
    esac

    if _find_model_profile "$harness" "$source" "$name" "$result_name"; then
        return 0
    fi
    if [ "$explicit_selection" -eq 1 ]; then
        warn "AAB_${harness^^}_DEFAULT_PROFILE='${selection}' does not name a configured ${harness} profile."
        return 1
    fi
    if _first_model_profile "$harness" first-party "$result_name"; then
        return 0
    fi
    _first_model_profile "$harness" third-party "$result_name"
}

require_inference_gateway() {
    local profile_label="$1"
    if [ -z "${AAB_INFERENCE_GATEWAY_URL:-}" ]; then
        warn "${profile_label} requires AAB_INFERENCE_GATEWAY_URL."
        return 1
    fi
}
# <<< src/bootstrap/12_model_profiles.bash <<<

# >>> src/bootstrap/13_configure_brev.bash >>>
# ---------------------------------------------------------------------------
# Configure Brev API-key auth and skip interactive onboarding.
#
# `brev login --api-key ... --org-id ...` writes Brev's credentials cache,
# which makes future Brev commands non-interactive. The API key and org ID
# are a pair: if the caller provides one without the other, fail immediately
# instead of leaving Brev on an interactive auth path.
# ---------------------------------------------------------------------------
_configure_brev_auth() {
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

_write_brev_onboarding() {
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

configure_brev() {
    _configure_brev_auth
    _write_brev_onboarding
}
# <<< src/bootstrap/13_configure_brev.bash <<<

# >>> src/bootstrap/13_configure_claude.bash >>>
# ---------------------------------------------------------------------------
# 5. Write ~/.claude/settings.json.
# ---------------------------------------------------------------------------
configure_claude_managed_settings() {
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

configure_claude_settings() {
    mkdir -p "${CLAUDE_DIR}"
    if [[ -f "${SETTINGS_FILE}" ]]; then
        local backup
        backup="${SETTINGS_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "${SETTINGS_FILE}" "${backup}"
        log "Backed up existing settings.json -> ${backup}."
    fi
    local -A profile=()
    resolve_model_profile claude profile
    if [ "${profile[source]}" = "third-party" ]; then
        require_inference_gateway "Claude profile '${profile[name]}'"
    fi
    local model="${profile[model]}"
    local effort="${profile[effort]}"
    local model_json effort_json
    model_json=$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$model")
    effort_json=$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$effort")
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
  "model": ${model_json},
  "effortLevel": ${effort_json},
  "permissions": {
    "defaultMode": "bypassPermissions",
    "allow": [
      "Edit(${HOME}/.claude/**)",
      "Read(${HOME}/.claude/**)",
      "Edit(${HOME}/.claude.json)",
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
    "CLAUDE_CODE_EFFORT_LEVEL": ${effort_json},
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
    log "Wrote ${SETTINGS_FILE} (profile=${profile[source]}/${profile[name]}, model=${model}, effort=${effort})."
    configure_claude_managed_settings
}
# Skip Claude Code's first-run theme prompt and pre-approve the
# first-party API-key fingerprint when one is set. Both gates live in
# ~/.claude.json, so preserve unrelated authentication and user fields.
skip_claude_onboarding() {
    command -v python3 >/dev/null 2>&1 || { log "ERROR: python3 required to edit ~/.claude.json."; exit 1; }
    python3 - "${CLAUDE_JSON}" "${AAB_ANTHROPIC_API_KEY:-}" <<'PY'
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
    print(f"[bootstrap] Pre-approved first-party Anthropic API-key fingerprint ...{fp}.")
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=2)
print(f"[bootstrap] Set hasCompletedOnboarding=true in {path}.")
PY
}

# Write Claude-specific shell defaults to a dedicated file. The generic
# ~/.bashrc integration sources every file in ~/.aab/shell instead of
# hard-coding harness settings in the shell integration module.
configure_claude_shell() {
    mkdir -p "${AAB_SHELL_CONFIG_DIR}"
    printf '%s\n' \
        '# Generated by autonomous-agent-bootstrap.' \
        'export CLAUDE_CODE_SANDBOXED=1' \
        'export DEBUG_SDK=1' > "${CLAUDE_SHELL_CONFIG_FILE}"
    chmod 0644 "${CLAUDE_SHELL_CONFIG_FILE}"
    log "Wrote Claude shell configuration to ${CLAUDE_SHELL_CONFIG_FILE}."
}

configure_claude() {
    configure_claude_settings
    configure_claude_shell
    skip_claude_onboarding
}
# <<< src/bootstrap/13_configure_claude.bash <<<

# >>> src/bootstrap/13_configure_codex.bash >>>
# ---------------------------------------------------------------------------
# Configure global Codex model instructions. model_instructions_file
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
- Whenever you spawn a subagent, set `fork_turns` to `"none"` so it starts without inherited conversation turns.
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

configure_codex_model_instructions() {
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
# Write ~/.codex/config.toml.
# ---------------------------------------------------------------------------
_toml_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    printf '%s' "$s"
}

_normalize_codex_service_tier() {
    local service_tier="${1:-$DEFAULT_CODEX_SERVICE_TIER}"
    case "$service_tier" in
        priority|flex|default)
            printf '%s' "$service_tier"
            ;;
        fast)
            printf '%s' priority
            ;;
        *)
            warn "AAB_CODEX_SERVICE_TIER='${service_tier}' is not one of priority, flex, default, or fast; defaulting to ${DEFAULT_CODEX_SERVICE_TIER}."
            printf '%s' "$DEFAULT_CODEX_SERVICE_TIER"
            ;;
    esac
}

_codex_profile_service_tier() {
    case "$1" in
        true) printf '%s' priority ;;
        false) printf '%s' default ;;
        "") _normalize_codex_service_tier "${AAB_CODEX_SERVICE_TIER:-$DEFAULT_CODEX_SERVICE_TIER}" ;;
    esac
}

configure_codex_config() {
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

    local -A profile=()
    resolve_model_profile codex profile
    if [ "${profile[source]}" = "third-party" ]; then
        require_inference_gateway "Codex profile '${profile[name]}'"
    fi

    local model="${profile[model]}"
    local effort="${profile[effort]}"
    local service_tier fast_mode=false
    service_tier=$(_codex_profile_service_tier "${profile[fast]}")
    [ "$service_tier" != priority ] || fast_mode=true
    local agent_max_threads="${AAB_CODEX_AGENT_MAX_THREADS:-$DEFAULT_CODEX_AGENT_MAX_THREADS}"
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
    # Multi-agent V2 counts the root thread; keep the configured child capacity consistent across runtimes.
    local multi_agent_v2_max_concurrent_threads_per_session
    multi_agent_v2_max_concurrent_threads_per_session=$((agent_max_threads + 1))

    local model_escaped effort_escaped model_instructions_file_escaped
    local home_escaped cwd cwd_escaped gateway_url_escaped
    model_escaped=$(_toml_escape "$model")
    effort_escaped=$(_toml_escape "$effort")
    model_instructions_file_escaped=$(_toml_escape "$CODEX_MODEL_INSTRUCTIONS_FILE")
    home_escaped=$(_toml_escape "$HOME")
    cwd="${PWD:-$HOME}"
    cwd_escaped=$(_toml_escape "$cwd")
    gateway_url_escaped=$(_toml_escape "${AAB_INFERENCE_GATEWAY_URL:-}")

    cat > "${CODEX_CONFIG}" <<TOML
model = "${model_escaped}"
model_instructions_file = "${model_instructions_file_escaped}"
TOML

    if [ "${profile[source]}" = "third-party" ]; then
        cat >> "${CODEX_CONFIG}" <<'TOML'
model_provider = "aab-gateway"
TOML
    fi

    cat >> "${CODEX_CONFIG}" <<TOML
model_reasoning_effort = "${effort_escaped}"
model_reasoning_summary = "detailed"
hide_agent_reasoning = false
show_raw_agent_reasoning = true
service_tier = "${service_tier}"
approval_policy = "never"
sandbox_mode = "danger-full-access"
web_search = "live"
check_for_update_on_startup = false

[features]
fast_mode = ${fast_mode}
default_mode_request_user_input = false

[otel]
environment = "dev"
exporter = "none"
trace_exporter = "none"
metrics_exporter = "none"
log_user_prompt = false

[notice]
hide_full_access_warning = true

[shell_environment_policy]
inherit = "all"
ignore_default_excludes = true
TOML

    if [ "${profile[source]}" = "third-party" ]; then
        cat >> "${CODEX_CONFIG}" <<TOML

[model_providers."aab-gateway"]
name = "AAB Inference Gateway"
base_url = "${gateway_url_escaped}"
env_key = "AAB_INFERENCE_GATEWAY_API_KEY"
requires_openai_auth = false
wire_api = "responses"
request_max_retries = 4
stream_max_retries = 5
stream_idle_timeout_ms = 300000
TOML
    fi

    cat >> "${CODEX_CONFIG}" <<TOML

[features.multi_agent_v2]
max_concurrent_threads_per_session = ${multi_agent_v2_max_concurrent_threads_per_session}

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

    log "Wrote ${CODEX_CONFIG} (profile=${profile[source]}/${profile[name]}, model=${model}, effort=${effort}, service_tier=${service_tier}, fast=${fast_mode}, agent_max_threads=${agent_max_threads}, approval=never, sandbox=danger-full-access)."
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
    local api_key="${AAB_OPENAI_API_KEY:-}"
    [ -z "$api_key" ] && return

    local codex_bin=""
    if [ -x "${HOME}/.local/bin/codex-aab-real" ]; then
        codex_bin="${HOME}/.local/bin/codex-aab-real"
    elif command -v codex >/dev/null 2>&1; then
        codex_bin=$(command -v codex)
    elif [ -x "${HOME}/.local/bin/codex" ]; then
        codex_bin="${HOME}/.local/bin/codex"
    else
        warn "codex binary not on PATH; cannot configure AAB_OPENAI_API_KEY auth."
        exit 1
    fi

    if ! printf '%s' "$api_key" | "$codex_bin" login --with-api-key >/dev/null; then
        warn "codex login --with-api-key failed; cannot configure Codex API-key auth."
        exit 1
    fi

    log "Configured Codex API-key auth from AAB_OPENAI_API_KEY."
}

configure_codex() {
    configure_codex_model_instructions
    configure_codex_config
    configure_codex_auth
}
# <<< src/bootstrap/13_configure_codex.bash <<<

# >>> src/bootstrap/13_configure_pi.bash >>>
# ---------------------------------------------------------------------------
# Configure Pi's generated inference-gateway model catalog, unattended
# defaults, local fast-mode extension, and local-only OpenTelemetry logging.
# ---------------------------------------------------------------------------
PI_OBSERVABILITY_ENV_CONTENT=$(cat <<'AAB_PI_OBSERVABILITY_ENV_EOF'
# Pi observability defaults. Pi launchers source this file so these variables
# stay scoped to Pi processes and never affect unrelated tools.

export PI_TIMING="${PI_TIMING:-0}"
export PI_PATTY_BG_TASKS_DISABLE_CTRL_B="${PI_PATTY_BG_TASKS_DISABLE_CTRL_B:-1}"

# Match AAB's Claude and Codex policy: enable metadata-only OpenTelemetry while
# preventing network exporters and GenAI message-content capture. The Pi
# extension stores console-exported records in private local JSONL files.
export OTEL_SDK_DISABLED="${OTEL_SDK_DISABLED:-false}"
export OTEL_SERVICE_NAME="${OTEL_SERVICE_NAME:-pi-coding-agent}"
export OTEL_TRACES_EXPORTER="${OTEL_TRACES_EXPORTER:-console}"
export OTEL_METRICS_EXPORTER=none
export OTEL_LOGS_EXPORTER=none
export OTEL_RESOURCE_ATTRIBUTES=service.namespace=aab,deployment.environment.name=local
export OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=false
export OTEL_INSTRUMENTATION_HTTP_CAPTURE_HEADERS_CLIENT_REQUEST=
export OTEL_INSTRUMENTATION_HTTP_CAPTURE_HEADERS_CLIENT_RESPONSE=
export OTEL_INSTRUMENTATION_HTTP_CAPTURE_HEADERS_SERVER_REQUEST=
export OTEL_INSTRUMENTATION_HTTP_CAPTURE_HEADERS_SERVER_RESPONSE=
export PI_OTEL_LOG_DIR="${PI_OTEL_LOG_DIR:-$HOME/.pi/agent/debug}"
AAB_PI_OBSERVABILITY_ENV_EOF
)
PI_FAST_MODE_EXTENSION_CONTENT=$(cat <<'AAB_PI_FAST_MODE_EXTENSION_EOF'
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { clampThinkingLevel, streamOpenAIResponses } from "@earendil-works/pi-ai/compat";

export default function fastMode(pi: ExtensionAPI) {
	pi.registerProvider("aab-gateway-fast", {
		api: "aab-openai-responses-fast",
		streamSimple(model, context, options) {
			const responseModel = { ...model, api: "openai-responses" as const };
			const clampedReasoning = options?.reasoning
				? clampThinkingLevel(responseModel, options.reasoning)
				: undefined;
			const reasoningEffort = clampedReasoning === "off" ? undefined : clampedReasoning;

			return streamOpenAIResponses(responseModel, context, {
				...options,
				maxTokens: options?.maxTokens ?? model.maxTokens,
				reasoningEffort,
				serviceTier: "priority",
			});
		},
	});
}
AAB_PI_FAST_MODE_EXTENSION_EOF
)

configure_pi_models() {
    local profiles line
    profiles=$(_profile_list_for pi third-party)
    if [ -z "$(_model_profile_lines "$profiles")" ]; then
        if [ -f "$PI_MODELS_MARKER" ]; then
            rm -f "$PI_MODELS_FILE" "$PI_MODELS_MARKER"
        fi
        return
    fi

    require_inference_gateway "Pi profiles"
    mkdir -p "$PI_DIR" "$AAB_DIR"
    if [ -f "$PI_MODELS_FILE" ] && [ ! -f "$PI_MODELS_MARKER" ]; then
        local backup
        backup="${PI_MODELS_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$PI_MODELS_FILE" "$backup"
        log "Backed up existing Pi models.json -> ${backup}."
    fi

    local records tmp
    records=$(mktemp)
    tmp=$(mktemp "${PI_MODELS_FILE}.tmp.XXXXXX")
    local -A profile=()
    while IFS= read -r line; do
        _parse_model_profile_line pi third-party "$line" profile
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${profile[name]}" \
            "${profile[model]}" \
            "${profile[effort]}" \
            "${profile[thinking]}" \
            "${profile[context]}" \
            "${profile["max_tokens"]}" \
            "${profile[fast]:-false}" >> "$records"
    done < <(_model_profile_lines "$profiles")

    python3 - "$records" "$AAB_INFERENCE_GATEWAY_URL" "$tmp" <<'PY'
import csv
from copy import deepcopy
import json
import sys

records_path, base_url, output_path = sys.argv[1:]
models = {}
fast_models = {}


def merge_model(catalog, candidate):
    model_id = candidate["id"]
    existing = catalog.get(model_id)
    if existing is None:
        catalog[model_id] = candidate
        return
    existing_map = existing.setdefault("thinkingLevelMap", {})
    for level, provider_effort in candidate.get("thinkingLevelMap", {}).items():
        previous = existing_map.get(level)
        if previous is not None and previous != provider_effort:
            raise SystemExit(
                f"Conflicting Pi effort mappings for model {model_id!r}: "
                f"{level} maps to both {previous!r} and {provider_effort!r}"
            )
        existing_map[level] = provider_effort
    if not existing_map:
        existing.pop("thinkingLevelMap", None)
    existing["reasoning"] = existing["reasoning"] or candidate["reasoning"]
    existing["contextWindow"] = max(existing["contextWindow"], candidate["contextWindow"])
    existing["maxTokens"] = max(existing["maxTokens"], candidate["maxTokens"])


with open(records_path, encoding="utf-8", newline="") as handle:
    for name, model_id, effort, thinking, context, max_tokens, fast in csv.reader(handle, delimiter="\t"):
        candidate = {
            "id": model_id,
            "name": name,
            "reasoning": thinking != "off",
            "input": ["text"],
            "contextWindow": int(context or "128000"),
            "maxTokens": int(max_tokens or "16384"),
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        }
        if effort != thinking or thinking in {"xhigh", "max"}:
            candidate["thinkingLevelMap"] = {thinking: effort}
        merge_model(models, deepcopy(candidate))
        if fast == "true":
            merge_model(fast_models, deepcopy(candidate))

payload = {
    "providers": {
        "aab-gateway": {
            "name": "AAB Inference Gateway",
            "baseUrl": base_url,
            "api": "openai-completions",
            "apiKey": "$AAB_INFERENCE_GATEWAY_API_KEY",
            "models": list(models.values()),
        }
    }
}
if fast_models:
    payload["providers"]["aab-gateway-fast"] = {
        "name": "AAB Inference Gateway Fast",
        "baseUrl": base_url,
        "api": "aab-openai-responses-fast",
        "apiKey": "$AAB_INFERENCE_GATEWAY_API_KEY",
        "models": list(fast_models.values()),
    }
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
PY

    rm -f "$records"
    chmod 600 "$tmp"
    mv -f "$tmp" "$PI_MODELS_FILE"
    : > "$PI_MODELS_MARKER"
    chmod 600 "$PI_MODELS_MARKER"
    log "Wrote ${PI_MODELS_FILE} from AAB_PI_PROFILES."
}

configure_pi_settings() {
    local profiles records line selected_provider="" selected_model=""
    local -A profile=() selected=()
    profiles=$(_profile_list_for pi third-party)
    records=$(mktemp)
    while IFS= read -r line; do
        _parse_model_profile_line pi third-party "$line" profile
        printf '%s\t%s\n' "${profile[model]}" "${profile[fast]:-false}" >> "$records"
    done < <(_model_profile_lines "$profiles")

    if [ -s "$records" ]; then
        resolve_model_profile pi selected
        if [ "${selected[fast]}" = true ]; then
            selected_provider="aab-gateway-fast"
        else
            selected_provider="aab-gateway"
        fi
        selected_model="${selected[model]}"
    fi

    mkdir -p "$PI_DIR" "$(dirname "$PI_FAST_MODE_EXTENSION")"
    if [ -f "$PI_SETTINGS_FILE" ]; then
        local backup
        backup="${PI_SETTINGS_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$PI_SETTINGS_FILE" "$backup"
        log "Backed up existing Pi settings.json -> ${backup}."
    fi

    local tmp
    tmp=$(mktemp "${PI_SETTINGS_FILE}.tmp.XXXXXX")
    python3 - "$PI_SETTINGS_FILE" "$records" "$PI_FAST_MODE_EXTENSION" \
        "$selected_provider" "$selected_model" "$tmp" <<'PY'
import json
from pathlib import Path
import sys

settings_path, models_path, fast_mode_extension, provider, model, output_path = sys.argv[1:]
data = {}
try:
    with open(settings_path, encoding="utf-8") as handle:
        loaded = json.load(handle)
        if isinstance(loaded, dict):
            data = loaded
except (FileNotFoundError, json.JSONDecodeError):
    pass

data.update(
    {
        "defaultThinkingLevel": "high",
        "defaultProjectTrust": "always",
        "quietStartup": True,
        "enableInstallTelemetry": True,
        "enableAnalytics": True,
        "warnings": {"anthropicExtraUsage": False},
        "retry": {
            "enabled": True,
            "maxRetries": 15,
            "provider": {"timeoutMs": 240000, "maxRetries": 0},
        },
        "extensions": [fast_mode_extension],
        "packages": [],
    }
)

if provider:
    models = list(
        dict.fromkeys(
            line.split("\t", 1)[0]
            for line in Path(models_path).read_text().splitlines()
        )
    )
    data["defaultProvider"] = provider
    data["defaultModel"] = model
    data["enabledModels"] = models

for machine_key in ("trackingId", "lastChangelogVersion"):
    data.pop(machine_key, None)

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
    rm -f "$records"
    chmod 600 "$tmp"
    mv -f "$tmp" "$PI_SETTINGS_FILE"
    log "Wrote ${PI_SETTINGS_FILE} with unattended Pi defaults."
}

_write_pi_embedded_asset() {
    local path="$1" content="$2" mode="$3" tmp
    mkdir -p "$(dirname "$path")"
    tmp=$(mktemp "${path}.tmp.XXXXXX")
    printf '%s\n' "$content" > "$tmp"
    chmod "$mode" "$tmp"
    mv -f "$tmp" "$path"
}

configure_pi_extensions() {
    _write_pi_embedded_asset "$PI_OBSERVABILITY_ENV_FILE" "$PI_OBSERVABILITY_ENV_CONTENT" 600
    _write_pi_embedded_asset "$PI_FAST_MODE_EXTENSION" "$PI_FAST_MODE_EXTENSION_CONTENT" 600
    log "Wrote Pi fast-mode and local OpenTelemetry configuration."
}
# <<< src/bootstrap/13_configure_pi.bash <<<

# >>> src/bootstrap/20_configure_git.bash >>>
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

# <<< src/bootstrap/20_configure_git.bash <<<

# >>> src/bootstrap/21_configure_ssh_keys.bash >>>
# ---------------------------------------------------------------------------
# Write SSH keys supplied via $AAB_GH_AUTH_SSH_PRIVATE_KEY_B64 (for
# github.com auth: clone/push over SSH) and/or
# $AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64 (for git commit/tag signing). These are
# two separate roles and the
# bootstrap treats them independently: either may be set, or both, or
# neither. The signing key path does NOT touch ~/.ssh/config.
# ---------------------------------------------------------------------------

# _require_ssh_keygen: Verify the pinned openssh-client package supplied
# ssh-keygen. Package installation is centralized in install_base_deps().
_require_ssh_keygen() {
    command -v ssh-keygen >/dev/null 2>&1 && return 0
    warn "ssh-keygen is unavailable after installing the pinned apt package list."
    return 1
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

# configure_auth_ssh_key: Decode $AAB_GH_AUTH_SSH_PRIVATE_KEY_B64 to
# ~/.ssh/id_aab_auth and wire it as the IdentityFile for github.com in
# ~/.ssh/config. Does NOT touch git signing config. Silent no-op when the
# env var is unset.
configure_auth_ssh_key() {
    local encoded="${AAB_GH_AUTH_SSH_PRIVATE_KEY_B64:-}"
    local label="AAB_GH_AUTH_SSH_PRIVATE_KEY_B64"
    [ -z "$encoded" ] && return

    if ! command -v base64 >/dev/null 2>&1; then
        warn "base64 not installed; cannot decode ${label}; skipping."
        return
    fi
    _require_ssh_keygen || { warn "Skipping ${label} write (ssh-keygen unavailable)."; return; }
    _decode_ssh_key "$encoded" "$AUTH_KEY" "$label" || return 0

    _rewrite_ssh_config_block "$AUTH_KEY"
    log "Wrote GitHub auth SSH key at $AUTH_KEY (pub $AUTH_KEY_PUB); wired github.com identity in $SSH_CONFIG."
}

_write_git_allowed_signers() {
    local principal="$1" key_type key_data tmp
    if [[ "$principal" == *[[:space:]]* ]]; then
        warn "git user.email contains whitespace; cannot write the SSH allowed signers file."
        return 1
    fi
    read -r key_type key_data _ < "$SIGNING_KEY_PUB"
    if [ -z "$key_type" ] || [ -z "$key_data" ]; then
        warn "Signing public key at ${SIGNING_KEY_PUB} is malformed; cannot write the SSH allowed signers file."
        return 1
    fi

    mkdir -p "$AAB_DIR"
    chmod 0700 "$AAB_DIR"
    tmp=$(mktemp "${GIT_ALLOWED_SIGNERS_FILE}.tmp.XXXXXX")
    printf '%s %s %s\n' "$principal" "$key_type" "$key_data" > "$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "$GIT_ALLOWED_SIGNERS_FILE"
}

# configure_signing_ssh_key: Decode $AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64 to
# ~/.ssh/id_aab_signing and configure git to sign and locally verify commits
# and tags with it.
# Does NOT touch ~/.ssh/config — this key is for signing only. Silent
# no-op when the env var is unset.
configure_signing_ssh_key() {
    local encoded="${AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64:-}"
    local label="AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64"
    local signing_principal
    [ -z "$encoded" ] && return

    if ! command -v base64 >/dev/null 2>&1; then
        warn "base64 not installed; cannot decode ${label}; skipping."
        return
    fi
    _require_ssh_keygen || { warn "Skipping ${label} write (ssh-keygen unavailable)."; return; }
    _decode_ssh_key "$encoded" "$SIGNING_KEY" "$label" || return 0

    if command -v git >/dev/null 2>&1; then
        git config --global gpg.format ssh
        git config --global user.signingkey "$SIGNING_KEY_PUB"
        git config --global commit.gpgsign true
        git config --global tag.gpgsign true
        signing_principal=$(git config --global --get user.email 2>/dev/null || true)
        if [ -z "$signing_principal" ]; then
            warn "git user.email is unset; cannot configure local SSH signature verification."
        elif _write_git_allowed_signers "$signing_principal"; then
            git config --global gpg.ssh.allowedSignersFile "$GIT_ALLOWED_SIGNERS_FILE"
            log "Configured local SSH signature verification with $GIT_ALLOWED_SIGNERS_FILE."
        fi
        log "Configured git to sign commits and tags with $SIGNING_KEY_PUB."
    else
        warn "git not installed; skipping SSH signing config."
    fi
}
# <<< src/bootstrap/21_configure_ssh_keys.bash <<<

# >>> src/bootstrap/23_configure_git_hooks.bash >>>
# ---------------------------------------------------------------------------
# Configure a global git hook that enforces the bootstrap-configured git
# identity (and signing, when configured) on every commit, regardless of the
# repository the agent is working in.
#
# The motivation: agents routinely ignore the global git identity this script
# configures and commit under their own name/email via `git -c user.email=...`,
# `git commit --author=...`, GIT_AUTHOR_*/GIT_COMMITTER_* env vars, or a
# repo-local `git config user.email`. The agent rules written by
# configure_agent_rules() ask them not to; this hook makes the ask
# non-optional.
#
# The same pre-commit hook also runs a staged-diff secret scan (gitleaks, with
# a built-in shell-grep fallback) so a secret never lands in a commit object —
# the failure that motivated it: an agent committed a live GitHub admin token
# because nothing scanned the diff locally.
#
# _render_git_hook_script writes the dispatcher to stdout so it can be both
# written and linted (test.bash --lint shellchecks the emitted script). The
# dispatcher reads the expected identity from --global (which -c / env / config
# overrides cannot poison) and the actual identity from `git var`, which does
# reflect --author and GIT_*_ env vars. It then chains through to the repo's
# own hook of the same name so projects that ship hooks keep working — a global
# core.hooksPath replaces the per-repo hooks dir rather than adding to it.
# ---------------------------------------------------------------------------
_render_git_hook_script() {
    cat <<'HOOK'
#!/usr/bin/env bash
# autonomous-agent-bootstrap global git hook dispatcher. Configured by
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
            echo "  This rule is configured by autonomous-agent-bootstrap. See ~/.claude/CLAUDE.md and ~/.codex/AGENTS.md."
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

configure_git_hooks() {
    if ! command -v git >/dev/null 2>&1; then
        warn "git not installed — skipping git hook enforcement."
        return
    fi

    mkdir -p "${GIT_HOOKS_DIR}"
    local tmp
    tmp=$(mktemp "${GIT_HOOK_DISPATCHER}.tmp.XXXXXX")
    _render_git_hook_script > "$tmp"
    chmod 0755 "$tmp"
    mv -f "$tmp" "${GIT_HOOK_DISPATCHER}"

    local name
    for name in "${GIT_HOOK_NAMES[@]}"; do
        ln -sf "aab-git-hook" "${GIT_HOOKS_DIR}/${name}"
    done

    git config --global core.hooksPath "${GIT_HOOKS_DIR}"
    log "Configured global git hooks at ${GIT_HOOKS_DIR} and set core.hooksPath (enforces the global commit identity and scans staged commits for secrets)."
}
# <<< src/bootstrap/23_configure_git_hooks.bash <<<

# >>> src/bootstrap/24_configure_agent_rules.bash >>>
# ---------------------------------------------------------------------------
# 9d. Write the global agent rules to every harness's instruction file. Claude
# Code reads ~/.claude/CLAUDE.md and Codex reads ~/.codex/AGENTS.md for every
# session in every repository, so the rules land regardless of what a project's
# own CLAUDE.md / AGENTS.md says. The rules carry the operating principles for
# an unattended agent in this sandbox, followed by the git-identity rule (also
# enforced by the hook installed above). A sidecar stores the exact generated
# text so re-runs can replace it without adding management comments to the
# instruction files. Pre-existing user content in either file is preserved.
# ---------------------------------------------------------------------------
_render_agent_rules() {
    cat <<'RULES'
## Operating principles

- Be consistent.
- Be concise in replies.
- Act autonomously without seeking operator input.
- You are in a safe sandbox without credentials that could cause serious harm.
- Write substantive PR descriptions in plain language. Explain the status quo and resulting behavior, name important architecture decisions, new components, and dependencies, and give concrete before/after examples when useful. Never omit a material artifact such as a new plugin or use only jargon-heavy bullets.

## Always use the configured git identity

Always commit and tag with the git identity this machine is configured with, and don't override it with `git -c`, `--author=`, `GIT_AUTHOR_*` / `GIT_COMMITTER_*` env vars, or a repo-local `git config`.
RULES
}

configure_agent_rules() {
    local current_rules previous_rules
    current_rules=$(mktemp)
    previous_rules=$(mktemp)
    _render_agent_rules > "$current_rules"
    if [ -f "$AGENT_RULES_STATE_FILE" ]; then
        cp "$AGENT_RULES_STATE_FILE" "$previous_rules"
    else
        : > "$previous_rules"
    fi

    _configure_agent_rules_file() {
        local file="$1" dir tmp
        dir=$(dirname -- "$file")
        mkdir -p "$dir"
        touch "$file"
        tmp=$(mktemp)
        python3 - "$file" "$previous_rules" "$current_rules" "$tmp" <<'PY'
import sys
from pathlib import Path

target_path, previous_path, current_path, output_path = sys.argv[1:]
text = Path(target_path).read_text(encoding="utf-8")
previous = Path(previous_path).read_text(encoding="utf-8")
current = Path(current_path).read_text(encoding="utf-8")
for managed in dict.fromkeys((previous, current)):
    if not managed:
        continue
    index = text.rfind(managed)
    if index >= 0:
        text = text[:index] + text[index + len(managed):]
        break

text = text.rstrip("\r\n")
if text:
    text += "\n"
Path(output_path).write_text(text, encoding="utf-8")
PY
        mv "$tmp" "$file"
        {
            [ -s "$file" ] && printf '\n'
            cat "$current_rules"
        } >> "$file"
    }

    _configure_agent_rules_file "${CLAUDE_MEMORY_FILE}"
    log "Wrote agent rules to ${CLAUDE_MEMORY_FILE}."
    _configure_agent_rules_file "${CODEX_AGENTS_FILE}"
    log "Wrote agent rules to ${CODEX_AGENTS_FILE}."

    mkdir -p "$AAB_DIR"
    chmod 700 "$AAB_DIR"
    chmod 600 "$current_rules"
    mv "$current_rules" "$AGENT_RULES_STATE_FILE"
    rm -f "$previous_rules"
}
# <<< src/bootstrap/24_configure_agent_rules.bash <<<

# >>> src/bootstrap/26_configure_launchers.bash >>>
# ---------------------------------------------------------------------------
# Write profile-driven Claude, Codex, and Pi launcher families.
# ---------------------------------------------------------------------------
_is_aab_launcher_symlink_target() {
    case "$(basename "$1")" in
        claude-first-party-*|claude-third-party-*|claude-first-party|codex-first-party-*|codex-third-party-*|codex-first-party|pi-*)
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
        warn "${agent_name} binary not found at ${agent_bin}; cannot write launcher wrappers."
        exit 1
    fi

    if [ -L "$agent_bin" ]; then
        local target
        target=$(readlink "$agent_bin")
        if _is_aab_launcher_symlink_target "$target"; then
            if [ ! -e "$real_bin" ]; then
                warn "${agent_name} launcher exists but ${real_bin} is missing."
                exit 1
            fi
            return
        fi
        ln -sfn "$target" "$real_bin"
    elif ! grep -q "$marker" "$agent_bin" 2>/dev/null; then
        mv "$agent_bin" "$real_bin"
    elif [ ! -e "$real_bin" ]; then
        warn "${agent_name} launcher exists but ${real_bin} is missing."
        exit 1
    fi
}

_remove_aab_profile_launchers() {
    local marker="$1"
    shift
    local pattern launcher target
    for pattern in "$@"; do
        for launcher in $pattern; do
            if [ -L "$launcher" ]; then
                target=$(readlink "$launcher")
                if _is_aab_launcher_symlink_target "$target"; then
                    rm -f "$launcher"
                fi
                continue
            fi
            [ -f "$launcher" ] || continue
            if grep -q "$marker" "$launcher" 2>/dev/null; then
                rm -f "$launcher"
            fi
        done
    done
}

_write_claude_launcher() {
    local source="$1" name="$2" model="$3" haiku="$4" sonnet="$5" opus="$6"
    local effort="$7" context="$8" subagent="$9" launcher="${10}" tmp
    local resolved_model="$model" resolved_subagent="$subagent"
    if [ -n "$context" ]; then
        case "$resolved_model" in
            *\[1m\]) ;;
            *) resolved_model="${resolved_model}[1m]" ;;
        esac
        if [ "$resolved_subagent" = "$model" ]; then
            resolved_subagent="$resolved_model"
        fi
    fi

    tmp=$(mktemp "${launcher}.tmp.XXXXXX")
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' '# Autonomous-agent-bootstrap Claude launcher.'
        printf 'profile_source=%q\n' "$source"
        printf 'profile_name=%q\n' "$name"
        printf 'profile_model=%q\n' "$resolved_model"
        printf 'profile_haiku=%q\n' "$haiku"
        printf 'profile_sonnet=%q\n' "$sonnet"
        printf 'profile_opus=%q\n' "$opus"
        printf 'profile_effort=%q\n' "$effort"
        printf 'profile_context=%q\n' "$context"
        printf 'profile_subagent=%q\n' "$resolved_subagent"
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

export CLAUDE_CODE_SANDBOXED=1
export DEBUG_SDK=1
export CLAUDE_CODE_EFFORT_LEVEL="$profile_effort"
[ -n "${AAB_GH_TOKEN:-}" ] && export GH_TOKEN="$AAB_GH_TOKEN"
[ -n "${AAB_BREV_API_KEY:-}" ] && export BREV_API_KEY="$AAB_BREV_API_KEY"
[ -n "${AAB_BREV_ORG_ID:-}" ] && export BREV_ORG_ID="$AAB_BREV_ORG_ID"

unset ANTHROPIC_BASE_URL
unset ANTHROPIC_AUTH_TOKEN
unset ANTHROPIC_MODEL
unset ANTHROPIC_DEFAULT_HAIKU_MODEL
unset ANTHROPIC_DEFAULT_SONNET_MODEL
unset ANTHROPIC_DEFAULT_OPUS_MODEL
unset CLAUDE_CODE_AUTO_COMPACT_WINDOW
unset CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS
unset ANTHROPIC_API_KEY

case "$profile_source" in
    first-party)
        [ -n "${AAB_ANTHROPIC_API_KEY:-}" ] && export ANTHROPIC_API_KEY="$AAB_ANTHROPIC_API_KEY"
        ;;
    third-party)
        if [ -z "${AAB_INFERENCE_GATEWAY_URL:-}" ]; then
            printf '[bootstrap] WARN: Claude profile %s requires AAB_INFERENCE_GATEWAY_URL.\n' "$profile_name" >&2
            exit 1
        fi
        export ANTHROPIC_BASE_URL="$AAB_INFERENCE_GATEWAY_URL"
        [ -n "${AAB_INFERENCE_GATEWAY_API_KEY:-}" ] && export ANTHROPIC_AUTH_TOKEN="$AAB_INFERENCE_GATEWAY_API_KEY"
        ;;
esac

export ANTHROPIC_MODEL="$profile_model"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$profile_haiku"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$profile_sonnet"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$profile_opus"
export CLAUDE_CODE_SUBAGENT_MODEL="$profile_subagent"
if [ -n "$profile_context" ]; then
    export CLAUDE_CODE_AUTO_COMPACT_WINDOW="$profile_context"
fi

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

configure_claude_launchers() {
    local launcher_dir="${HOME}/.local/aab-bin"
    local claude_bin="${HOME}/.local/bin/claude"
    local real_bin="${HOME}/.local/bin/claude-aab-real"
    local source profiles line launcher
    local -A profile=() selected=()

    if [ ! -e "$claude_bin" ]; then
        warn "claude binary not found at ${claude_bin}; cannot write launcher wrappers."
        exit 1
    fi

    ln -sfn "$claude_bin" "$real_bin"
    mkdir -p "$launcher_dir" "${HOME}/.local/bin"
    _remove_aab_profile_launchers \
        'Autonomous-agent-bootstrap Claude launcher' \
        "${HOME}/.local/bin/claude-first-party*" \
        "${HOME}/.local/bin/claude-third-party-*"

    for source in first-party third-party; do
        profiles=$(_profile_list_for claude "$source")
        while IFS= read -r line; do
            _parse_model_profile_line claude "$source" "$line" profile
            if [ "$source" = "third-party" ]; then
                require_inference_gateway "Claude profile '${profile[name]}'"
            fi
            launcher="${HOME}/.local/bin/claude-${source}-${profile[name]}"
            _write_claude_launcher \
                "$source" "${profile[name]}" "${profile[model]}" \
                "${profile[haiku]}" "${profile[sonnet]}" "${profile[opus]}" \
                "${profile[effort]}" "${profile[context]}" "${profile[subagent]}" \
                "$launcher"
        done < <(_model_profile_lines "$profiles")
    done

    resolve_model_profile claude selected
    launcher="${HOME}/.local/bin/claude-${selected[source]}-${selected[name]}"
    ln -sfn "$launcher" "${launcher_dir}/claude"
    log "Wrote Claude profile launchers (selected=${selected[source]}/${selected[name]})."
}

_write_codex_gateway_model_catalog() {
    local codex_bin="$1"
    local profiles line records bundled_catalog tmp_home tmp alias_count
    local -A profile=()
    profiles=$(_profile_list_for codex third-party)
    if [ -z "$(_model_profile_lines "$profiles")" ]; then
        rm -f "$CODEX_GATEWAY_MODEL_CATALOG"
        return
    fi

    mkdir -p "$AAB_DIR"
    records=$(mktemp)
    bundled_catalog=$(mktemp)
    tmp_home=$(mktemp -d)
    tmp=$(mktemp "${CODEX_GATEWAY_MODEL_CATALOG}.tmp.XXXXXX")
    while IFS= read -r line; do
        _parse_model_profile_line codex third-party "$line" profile
        printf '%s\n' "${profile[model]}" >> "$records"
    done < <(_model_profile_lines "$profiles")

    mkdir -p "${tmp_home}/.codex"
    if ! HOME="$tmp_home" CODEX_HOME="${tmp_home}/.codex" \
        "$codex_bin" debug models --bundled > "$bundled_catalog" 2>/dev/null; then
        rm -f "$records" "$bundled_catalog" "$tmp"
        rm -r "$tmp_home"
        warn "Could not read Codex's bundled model catalog; gateway model metadata was not refreshed."
        return
    fi

    if ! alias_count=$(python3 - "$records" "$bundled_catalog" "$tmp" <<'PY'
import copy
import json
import sys

records_path, source_path, output_path = sys.argv[1:]
with open(source_path, encoding="utf-8") as source:
    catalog = json.load(source)

models = catalog.get("models")
if not isinstance(models, list):
    raise ValueError("Codex model catalog does not contain a models list")

by_slug = {
    model["slug"]: model
    for model in models
    if isinstance(model, dict) and isinstance(model.get("slug"), str)
}
alias_count = 0
with open(records_path, encoding="utf-8") as records:
    for configured_model in dict.fromkeys(records.read().splitlines()):
        if configured_model in by_slug:
            continue
        bundled_slug = configured_model.rsplit("/", 1)[-1]
        template = by_slug.get(bundled_slug)
        if template is None:
            continue
        alias = copy.deepcopy(template)
        alias["slug"] = configured_model
        models.append(alias)
        by_slug[configured_model] = alias
        alias_count += 1

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(catalog, handle, indent=2)
    handle.write("\n")

print(alias_count)
PY
    ); then
        rm -f "$records" "$bundled_catalog" "$tmp"
        rm -r "$tmp_home"
        warn "Could not generate Codex gateway model metadata."
        return
    fi
    rm -f "$records"
    rm -f "$bundled_catalog"
    rm -r "$tmp_home"
    chmod 600 "$tmp"
    mv -f "$tmp" "$CODEX_GATEWAY_MODEL_CATALOG"
    log "Wrote ${CODEX_GATEWAY_MODEL_CATALOG} with ${alias_count} gateway model alias(es)."
}

_write_codex_launcher() {
    local source="$1" name="$2" model="$3" effort="$4" service_tier="$5"
    local fast_mode="$6" model_catalog="$7" launcher="$8" tmp
    tmp=$(mktemp "${launcher}.tmp.XXXXXX")
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' '# Autonomous-agent-bootstrap Codex launcher.'
        printf 'profile_source=%q\n' "$source"
        printf 'profile_name=%q\n' "$name"
        printf 'profile_model=%q\n' "$model"
        printf 'profile_effort=%q\n' "$effort"
        printf 'profile_service_tier=%q\n' "$service_tier"
        printf 'profile_fast_mode=%q\n' "$fast_mode"
        printf 'profile_model_catalog=%q\n' "$model_catalog"
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
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '%s' "$value"
}

canonical_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        (cd "$dir" 2>/dev/null && pwd -P) || printf '%s' "$dir"
    else
        printf '%s' "$dir"
    fi
}

[ -n "${AAB_GH_TOKEN:-}" ] && export GH_TOKEN="$AAB_GH_TOKEN"
[ -n "${AAB_BREV_API_KEY:-}" ] && export BREV_API_KEY="$AAB_BREV_API_KEY"
[ -n "${AAB_BREV_ORG_ID:-}" ] && export BREV_ORG_ID="$AAB_BREV_ORG_ID"

model_escaped=$(toml_escape "$profile_model")
effort_escaped=$(toml_escape "$profile_effort")
service_tier_escaped=$(toml_escape "$profile_service_tier")
config_args=(
    -c "model=\"${model_escaped}\""
    -c "model_reasoning_effort=\"${effort_escaped}\""
    -c "service_tier=\"${service_tier_escaped}\""
    -c "features.fast_mode=${profile_fast_mode}"
)
if [ -n "$profile_model_catalog" ]; then
    model_catalog_escaped=$(toml_escape "$profile_model_catalog")
    config_args+=(-c "model_catalog_json=\"${model_catalog_escaped}\"")
fi
unset OPENAI_API_KEY
case "$profile_source" in
    first-party)
        [ -n "${AAB_OPENAI_API_KEY:-}" ] && export OPENAI_API_KEY="$AAB_OPENAI_API_KEY"
        config_args+=(-c 'model_provider="openai"')
        ;;
    third-party)
        if [ -z "${AAB_INFERENCE_GATEWAY_URL:-}" ]; then
            printf '[bootstrap] WARN: Codex profile %s requires AAB_INFERENCE_GATEWAY_URL.\n' "$profile_name" >&2
            exit 1
        fi
        base_url_escaped=$(toml_escape "$AAB_INFERENCE_GATEWAY_URL")
        provider_override="model_providers={\"aab-gateway\"={name=\"AAB Inference Gateway\",base_url=\"${base_url_escaped}\",env_key=\"AAB_INFERENCE_GATEWAY_API_KEY\",requires_openai_auth=false,wire_api=\"responses\",request_max_retries=4,stream_max_retries=5,stream_idle_timeout_ms=300000}}"
        config_args+=(-c 'model_provider="aab-gateway"' -c "$provider_override")
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

configure_codex_launchers() {
    local codex_bin="${HOME}/.local/bin/codex"
    local real_bin="${HOME}/.local/bin/codex-aab-real"
    local source profiles line launcher service_tier fast_mode model_catalog
    local -A profile=() selected=()

    _prepare_launcher_real_binary "codex" "$codex_bin" "$real_bin" "Autonomous-agent-bootstrap Codex launcher"
    _remove_aab_profile_launchers \
        'Autonomous-agent-bootstrap Codex launcher' \
        "${HOME}/.local/bin/codex-first-party*" \
        "${HOME}/.local/bin/codex-third-party-*"
    _write_codex_gateway_model_catalog "$real_bin"

    for source in first-party third-party; do
        profiles=$(_profile_list_for codex "$source")
        while IFS= read -r line; do
            _parse_model_profile_line codex "$source" "$line" profile
            if [ "$source" = "third-party" ]; then
                require_inference_gateway "Codex profile '${profile[name]}'"
            fi
            service_tier=$(_codex_profile_service_tier "${profile[fast]}")
            fast_mode=false
            [ "$service_tier" != priority ] || fast_mode=true
            model_catalog=""
            if [ "$source" = "third-party" ]; then
                model_catalog="$CODEX_GATEWAY_MODEL_CATALOG"
            fi
            launcher="${HOME}/.local/bin/codex-${source}-${profile[name]}"
            _write_codex_launcher \
                "$source" "${profile[name]}" "${profile[model]}" "${profile[effort]}" \
                "$service_tier" "$fast_mode" "$model_catalog" "$launcher"
        done < <(_model_profile_lines "$profiles")
    done

    resolve_model_profile codex selected
    launcher="${HOME}/.local/bin/codex-${selected[source]}-${selected[name]}"
    ln -sfn "$launcher" "$codex_bin"
    log "Wrote Codex profile launchers (selected=${selected[source]}/${selected[name]})."
}

_write_pi_launcher() {
    local name="$1" provider="$2" model="$3" thinking="$4" launcher="$5" tmp
    tmp=$(mktemp "${launcher}.tmp.XXXXXX")
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' '# Autonomous-agent-bootstrap Pi launcher.'
        printf 'profile_name=%q\n' "$name"
        printf 'profile_provider=%q\n' "$provider"
        printf 'profile_model=%q\n' "$model"
        printf 'profile_thinking=%q\n' "$thinking"
        cat <<'BASH'
set -euo pipefail

real_bin="${AAB_PI_REAL_BIN:-$HOME/.local/bin/pi-aab-real}"
env_file="${AAB_ENV_FILE:-$HOME/.aab/.env}"
observability_env_file="${AAB_PI_OBSERVABILITY_ENV_FILE:-$HOME/.aab/shell/pi-observability.env}"
if [ -f "$env_file" ]; then
    set -a
    . "$env_file"
    set +a
fi

# Keep OpenTelemetry and its local JSONL capture scoped to Pi launchers.
# shellcheck source=/dev/null
[ ! -f "$observability_env_file" ] || . "$observability_env_file"

# Keep Pi's built-in Ctrl+B binding even if the observability file is absent.
export PI_PATTY_BG_TASKS_DISABLE_CTRL_B="${PI_PATTY_BG_TASKS_DISABLE_CTRL_B:-1}"

if [ ! -x "$real_bin" ]; then
    printf '[bootstrap] WARN: Pi real binary not executable: %s\n' "$real_bin" >&2
    exit 127
fi

case "${1:-}" in
    install|remove|uninstall|update|list|config)
        exec "$real_bin" "$@"
        ;;
esac

if [ -n "$profile_name" ] && [ -z "${AAB_INFERENCE_GATEWAY_URL:-}" ]; then
    printf '[bootstrap] WARN: Pi profile %s requires AAB_INFERENCE_GATEWAY_URL.\n' "$profile_name" >&2
    exit 1
fi

[ -n "${AAB_GH_TOKEN:-}" ] && export GH_TOKEN="$AAB_GH_TOKEN"
[ -n "${AAB_BREV_API_KEY:-}" ] && export BREV_API_KEY="$AAB_BREV_API_KEY"
[ -n "${AAB_BREV_ORG_ID:-}" ] && export BREV_ORG_ID="$AAB_BREV_ORG_ID"

has_provider=0
has_model=0
has_thinking=0
for arg in "$@"; do
    case "$arg" in
        --provider|--provider=*) has_provider=1 ;;
        --model|--model=*) has_model=1 ;;
        --thinking|--thinking=*) has_thinking=1 ;;
    esac
done

extra_args=()
if [ -n "$profile_name" ]; then
    [ "$has_provider" -eq 1 ] || extra_args+=(--provider "$profile_provider")
    [ "$has_model" -eq 1 ] || extra_args+=(--model "$profile_model")
    [ "$has_thinking" -eq 1 ] || extra_args+=(--thinking "$profile_thinking")
fi
exec "$real_bin" "${extra_args[@]}" "$@"
BASH
    } > "$tmp"
    chmod 755 "$tmp"
    mv -f "$tmp" "$launcher"
}

configure_pi_launchers() {
    local pi_bin="${HOME}/.local/bin/pi"
    local real_bin="${HOME}/.local/bin/pi-aab-real"
    local profiles line launcher provider
    local -A profile=() selected=()

    if [ ! -x "$real_bin" ]; then
        warn "Pi real binary not executable at ${real_bin}; skipping profile launchers."
        return
    fi
    profiles=$(_profile_list_for pi third-party)
    _remove_aab_profile_launchers \
        'Autonomous-agent-bootstrap Pi launcher' \
        "${HOME}/.local/bin/pi" \
        "${HOME}/.local/bin/pi-*"

    if [ -z "$(_model_profile_lines "$profiles")" ]; then
        _write_pi_launcher "" "" "" "" "$pi_bin"
        log "Wrote unconfigured Pi launcher at ${pi_bin}."
        return
    fi

    require_inference_gateway "Pi profiles"
    while IFS= read -r line; do
        _parse_model_profile_line pi third-party "$line" profile
        if [ "${profile[fast]}" = true ]; then
            provider="aab-gateway-fast"
        else
            provider="aab-gateway"
        fi
        launcher="${HOME}/.local/bin/pi-${profile[name]}"
        _write_pi_launcher "${profile[name]}" "$provider" "${profile[model]}" "${profile[thinking]}" "$launcher"
    done < <(_model_profile_lines "$profiles")

    resolve_model_profile pi selected
    if [ "${selected[fast]}" = true ]; then
        provider="aab-gateway-fast"
    else
        provider="aab-gateway"
    fi
    _write_pi_launcher "${selected[name]}" "$provider" "${selected[model]}" "${selected[thinking]}" "$pi_bin"
    log "Wrote Pi profile launchers (selected=${selected[name]})."
}
# <<< src/bootstrap/26_configure_launchers.bash <<<

# >>> src/bootstrap/27_configure_shell_startup.bash >>>
# ---------------------------------------------------------------------------
# 11. Rewrite the unattended-mode block in ~/.bashrc.
#
# The block is identified by the BEGIN/END markers. On re-run we strip the
# old block and append a fresh one. Credentials and provider model settings
# are written to ~/.aab/.env instead of ~/.bashrc.
# ---------------------------------------------------------------------------
configure_bashrc() {
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

    {
        printf '\n%s\n' "${BASHRC_MARKER_BEGIN}"
        printf '%s\n' \
            '# Sources env file created by the Claude Code native installer and' \
            '# ensures the AAB launcher dir (~/.local/aab-bin) is ahead of' \
            '# ~/.local/bin on PATH, so the native auto-updater that owns' \
            '# ~/.local/bin/claude cannot shadow the AAB provider wrapper.' \
            '# ~/.local/bin also carries uv tool symlinks, which resolve there' \
            '# ahead of the system dirs.' \
            'if [ -f "$HOME/.local/bin/env" ]; then' \
            '    . "$HOME/.local/bin/env"' \
            'fi' \
            'export PATH="$HOME/.local/bin:$PATH"' \
            'export PATH="$HOME/.local/aab-bin:$PATH"' \
            '# Export the GitHub credential used by gh and git.' \
            'if [ -f "$HOME/.aab/shell/github.env" ]; then' \
            '    . "$HOME/.aab/shell/github.env"' \
            'fi' \
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
        printf '%s\n' "${BASHRC_MARKER_END}"
    } >> "${BASHRC}"
    log "Wrote autonomous-agent-bootstrap block to ${BASHRC}."
}

# A login shell sources ~/.profile, which (per the distro default) prepends
# ~/.local/bin to PATH *after* sourcing ~/.bashrc — so a ~/.bashrc-only PATH
# tweak gets shadowed in login/SSH shells. Append the launcher-dir prepend at
# the end of ~/.profile so ~/.local/aab-bin stays ahead of ~/.local/bin there
# too. The managed block is replaced in place on re-run, so it never stacks.
configure_profile() {
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
            '# login-shell sequence; ~/.local/bin and its uv tool symlinks stay' \
            '# ahead of the system dirs but behind it.' \
            'export PATH="$HOME/.local/aab-bin:$PATH"'
        printf '%s\n' "${BASHRC_MARKER_END}"
    } >> "${PROFILE}"
    log "Wrote autonomous-agent-bootstrap block to ${PROFILE}."
}
# <<< src/bootstrap/27_configure_shell_startup.bash <<<

# >>> src/bootstrap/28_configure_user_linger.bash >>>
# ---------------------------------------------------------------------------
# Enable user lingering so the per-user systemd instance — and its bus at
# $XDG_RUNTIME_DIR/bus — stays up across SSH sessions instead of dying with the
# login session. Unattended agent workloads that wrap commands in
# `systemd-run --user --scope` (e.g. autocuda's `run slice`, which caps build
# CPU/memory) need the user bus available even when no interactive session is
# open. `loginctl enable-linger` is the one-time setup for that. Skip cleanly on
# hosts without a systemd user manager (bare containers) or without sudo.
# ---------------------------------------------------------------------------
configure_user_linger() {
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
# <<< src/bootstrap/28_configure_user_linger.bash <<<

# >>> src/bootstrap/30_load_config_file.bash >>>
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
# Config input is sourced after the inherited environment, so assignments in
# the file or stdin are authoritative. A config can opt into environment
# precedence for an individual value with `FOO="${FOO:-default}"`.
# ---------------------------------------------------------------------------
load_config_file() {
    local f="$1"
    if [ ! -r "$f" ]; then
        warn "Config file '$f' not found or not readable."
        exit 1
    fi
    log "Loading config from $f."
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
    log "Loading config from stdin."
    _source_config "$tmp"
    rm -f "$tmp"
}

# Source the config at <path> with auto-export. Existing environment values
# remain available to shell expansions in the config, while direct assignments
# replace them.
_source_config() {
    local src="$1"
    set -a
    # shellcheck source=/dev/null
    . "$src"
    set +a
}

main() {
    if [ -n "${1:-}" ]; then
        load_config_file "$1"
    elif [ ! -t 0 ]; then
        load_config_stdin
    fi
    validate_model_profiles
    install_base_deps
    install_uv_tools
    install_claude
    install_codex
    install_node
    install_pi
    install_brev
    install_lifeboat
    install_gh
    install_gitleaks
    configure_aab_env_file
    configure_github_shell
    configure_brev
    configure_claude
    configure_codex
    configure_pi_models
    configure_pi_settings
    configure_pi_extensions
    configure_git
    configure_auth_ssh_key
    configure_signing_ssh_key
    configure_git_hooks
    configure_agent_rules
    install_agent_plugins
    install_pi_plugins
    configure_claude_launchers
    configure_codex_launchers
    configure_pi_launchers
    install_autocuda
    configure_user_linger
    configure_bashrc
    configure_profile
    log "Done. Open a new shell (or 'source ~/.bashrc') so PATH updates take effect."
}

# `:-$0` covers the `curl ... | bash` case, where BASH_SOURCE is empty and
# would otherwise trip `set -u`.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
# <<< src/bootstrap/30_load_config_file.bash <<<
