# ---------------------------------------------------------------------------
# Install the pinned Pi packages listed in pi_plugins.txt.
#
# The compiler embeds pi_plugins.txt below. AAB_PI_PLUGINS_FILE can replace
# the compiled list for a one-off local build.
# ---------------------------------------------------------------------------
PI_PLUGINS_DEFAULT_CONTENT=$(cat <<'AAB_PI_PLUGINS_EOF'
__AAB_PI_PLUGINS__
AAB_PI_PLUGINS_EOF
)

install_pi_plugins() {
    local pi_bin="${HOME}/.local/bin/pi-aab-real"
    if [ ! -x "$pi_bin" ]; then
        warn "Pi real binary not executable at ${pi_bin}; skipping Pi package installation."
        return
    fi

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
    local source
    for source in "${sources[@]}"; do
        log "Installing Pi package ${source}."
        "${git_env[@]}" "$pi_bin" install "$source" --no-approve 2>&1 | sed 's/^/  /' \
            || warn "Pi package install returned non-zero for ${source}."
    done
}
