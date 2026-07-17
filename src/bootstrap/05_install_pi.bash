# ---------------------------------------------------------------------------
# Install / upgrade Pi from its official npm package. The Node-backed CLI is
# required because launcher-only NODE_OPTIONS preloads provide Pi's local
# debug log and OpenTelemetry instrumentation, and Pi package installation
# shells out to npm for runtime dependencies.
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
