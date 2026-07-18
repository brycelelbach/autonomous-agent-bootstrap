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
            '# ~/.local/bin also carries the uv tool symlinks (ruff,' \
            '# pre-commit, autocuda), so a bare `ruff` / `pre-commit` resolves' \
            '# there ahead of the system dirs.' \
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
            '# login-shell sequence; ~/.local/bin (with the uv tool symlinks for' \
            '# ruff / pre-commit / autocuda) stays ahead of the system dirs but' \
            '# behind it.' \
            'export PATH="$HOME/.local/aab-bin:$PATH"'
        printf '%s\n' "${BASHRC_MARKER_END}"
    } >> "${PROFILE}"
    log "Wrote autonomous-agent-bootstrap block to ${PROFILE}."
}
