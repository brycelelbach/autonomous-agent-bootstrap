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
