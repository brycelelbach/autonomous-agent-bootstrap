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
