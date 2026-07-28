# ---------------------------------------------------------------------------
# 9d. Write the global agent rules to every harness's instruction file. Claude
# Code reads ~/.claude/CLAUDE.md and Codex reads ~/.codex/AGENTS.md for every
# session in every repository, so the rules land regardless of what a project's
# own CLAUDE.md / AGENTS.md says. The rules carry the operating principles for
# an unattended agent in this sandbox, followed by the git-identity rule (also
# enforced by the hook installed above). A sidecar stores the exact generated
# text so re-runs can replace it without adding management comments to the
# instruction files. Pre-existing user content in either file is preserved.
# ---------------------------------------------------------------------------
_render_agent_rules() {
    cat <<'RULES'
## Operating principles

- Be consistent.
- Be concise in replies.
- Act autonomously without seeking operator input.
- You are in a safe sandbox without credentials that could cause serious harm.

 ## Write substantive PR descriptions
 
 Write substantive PR descriptions in plain language without jargon. Explain both the "why" and the "how". Provide concrete examples. Explain design decisions. Summarize all changes made, not just their effect.
 
## Always use the configured git identity

Always commit and tag with the git identity this machine is configured with, and don't override it with `git -c`, `--author=`, `GIT_AUTHOR_*` / `GIT_COMMITTER_*` env vars, or a repo-local `git config`.
RULES
}

configure_agent_rules() {
    local current_rules previous_rules
    current_rules=$(mktemp)
    previous_rules=$(mktemp)
    _render_agent_rules > "$current_rules"
    if [ -f "$AGENT_RULES_STATE_FILE" ]; then
        cp "$AGENT_RULES_STATE_FILE" "$previous_rules"
    else
        : > "$previous_rules"
    fi

    _configure_agent_rules_file() {
        local file="$1" dir tmp
        dir=$(dirname -- "$file")
        mkdir -p "$dir"
        touch "$file"
        tmp=$(mktemp)
        python3 - "$file" "$previous_rules" "$current_rules" "$tmp" <<'PY'
import sys
from pathlib import Path

target_path, previous_path, current_path, output_path = sys.argv[1:]
text = Path(target_path).read_text(encoding="utf-8")
previous = Path(previous_path).read_text(encoding="utf-8")
current = Path(current_path).read_text(encoding="utf-8")
for managed in dict.fromkeys((previous, current)):
    if not managed:
        continue
    index = text.rfind(managed)
    if index >= 0:
        text = text[:index] + text[index + len(managed):]
        break

text = text.rstrip("\r\n")
if text:
    text += "\n"
Path(output_path).write_text(text, encoding="utf-8")
PY
        mv "$tmp" "$file"
        {
            [ -s "$file" ] && printf '\n'
            cat "$current_rules"
        } >> "$file"
    }

    _configure_agent_rules_file "${CLAUDE_MEMORY_FILE}"
    log "Wrote agent rules to ${CLAUDE_MEMORY_FILE}."
    _configure_agent_rules_file "${CODEX_AGENTS_FILE}"
    log "Wrote agent rules to ${CODEX_AGENTS_FILE}."

    mkdir -p "$AAB_DIR"
    chmod 700 "$AAB_DIR"
    chmod 600 "$current_rules"
    mv "$current_rules" "$AGENT_RULES_STATE_FILE"
    rm -f "$previous_rules"
}
