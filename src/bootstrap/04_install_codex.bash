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
