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
