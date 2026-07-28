# ---------------------------------------------------------------------------
# 1. Install / upgrade Claude Code via the native installer.
# ---------------------------------------------------------------------------
install_claude() {
    log "Installing Claude Code ${CLAUDE_CODE_VERSION} via native installer..."
    curl -fsSL https://claude.ai/install.sh | bash -s -- "$CLAUDE_CODE_VERSION"
}
