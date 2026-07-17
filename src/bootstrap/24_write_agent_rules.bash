# ---------------------------------------------------------------------------
# 9d. Write the global agent rules to every harness's instruction file. Claude
# Code reads ~/.claude/CLAUDE.md and Codex reads ~/.codex/AGENTS.md for every
# session in every repository, so the rules land regardless of what a project's
# own CLAUDE.md / AGENTS.md says. The block carries the operating principles for
# an unattended agent in this sandbox, followed by the git-identity rule (also
# enforced by the hook installed above). The rules are wrapped in a managed
# block so re-runs replace them in place rather than stacking, and pre-existing
# user content in either file is preserved.
# ---------------------------------------------------------------------------
_render_agent_rules() {
    cat <<'RULES'
## Operating principles

- Be consistent.
- Be concise in replies.
- Act autonomously without seeking operator input.
- You are in a safe sandbox without credentials that could cause serious harm.

## Always use the configured git identity

Always commit and tag with the git identity this machine is configured with, and don't override it with `git -c`, `--author=`, `GIT_AUTHOR_*` / `GIT_COMMITTER_*` env vars, or a repo-local `git config`.
RULES
}

write_agent_rules() {
    _write_agent_rules_block() {
        local file="$1" dir
        dir=$(dirname -- "$file")
        mkdir -p "$dir"
        touch "$file"
        if grep -qF "${AGENT_RULES_MARKER_BEGIN}" "$file"; then
            local tmp
            tmp=$(mktemp)
            awk -v begin="${AGENT_RULES_MARKER_BEGIN}" -v end="${AGENT_RULES_MARKER_END}" '
                $0 == begin { skip=1; next }
                $0 == end   { skip=0; next }
                !skip { print }
            ' "$file" > "$tmp"
            # Drop trailing blank lines left behind so the file size stays
            # stable across re-runs.
            while [ -s "$tmp" ] && [ -z "$(tail -n 1 "$tmp")" ]; do
                sed -i '$ d' "$tmp"
            done
            mv "$tmp" "$file"
        fi
        {
            [ -s "$file" ] && printf '\n'
            printf '%s\n' "${AGENT_RULES_MARKER_BEGIN}"
            _render_agent_rules
            printf '%s\n' "${AGENT_RULES_MARKER_END}"
        } >> "$file"
    }

    _write_agent_rules_block "${CLAUDE_MEMORY_FILE}"
    log "Wrote agent rules to ${CLAUDE_MEMORY_FILE}."
    _write_agent_rules_block "${CODEX_AGENTS_FILE}"
    log "Wrote agent rules to ${CODEX_AGENTS_FILE}."
}
