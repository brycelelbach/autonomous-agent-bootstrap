# ---------------------------------------------------------------------------
# Reinstall the Pi packages listed in pi_plugins.txt.
#
# The compiler embeds pi_plugins.txt below. AAB_PI_PLUGINS_FILE can replace
# the compiled list for a one-off local build.
# ---------------------------------------------------------------------------
PI_PLUGINS_DEFAULT_CONTENT=$(cat <<'AAB_PI_PLUGINS_EOF'
__AAB_PI_PLUGINS__
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
