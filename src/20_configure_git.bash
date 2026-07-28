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

