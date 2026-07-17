# ---------------------------------------------------------------------------
# Configure a global git hook that enforces the bootstrap-configured git
# identity (and signing, when configured) on every commit, regardless of the
# repository the agent is working in.
#
# The motivation: agents routinely ignore the global git identity this script
# configures and commit under their own name/email via `git -c user.email=...`,
# `git commit --author=...`, GIT_AUTHOR_*/GIT_COMMITTER_* env vars, or a
# repo-local `git config user.email`. The agent rules written by
# write_agent_rules() ask them not to; this hook makes the ask
# non-optional.
#
# The same pre-commit hook also runs a staged-diff secret scan (gitleaks, with
# a built-in shell-grep fallback) so a secret never lands in a commit object —
# the failure that motivated it: an agent committed a live GitHub admin token
# because nothing scanned the diff locally.
#
# _render_git_hook_script writes the dispatcher to stdout so it can be both
# written and linted (test.bash --lint shellchecks the emitted script). The
# dispatcher reads the expected identity from --global (which -c / env / config
# overrides cannot poison) and the actual identity from `git var`, which does
# reflect --author and GIT_*_ env vars. It then chains through to the repo's
# own hook of the same name so projects that ship hooks keep working — a global
# core.hooksPath replaces the per-repo hooks dir rather than adding to it.
# ---------------------------------------------------------------------------
_render_git_hook_script() {
    cat <<'HOOK'
#!/usr/bin/env bash
# autonomous-agent-bootstrap global git hook dispatcher. Configured by
# bootstrap.bash and pointed to by the global core.hooksPath. Every git hook
# name is a symlink to this one script.
#
# On pre-commit it (1) blocks commits whose author / committer identity (and,
# when global signing is on, whose signing config) does not match the global
# git config the bootstrap set up, and (2) blocks commits that stage a secret,
# scanning the staged diff with gitleaks (or a built-in shell-grep fallback).
# For every hook it then chains to the repository's own .git/hooks/<name> so
# project hooks keep running, since a global core.hooksPath replaces rather than
# supplements the per-repo hooks directory.
set -uo pipefail

hook_name=$(basename -- "$0")

# Extract a field from a `git var GIT_*_IDENT` value, formatted as
# "Name <email> <unixtime> <tz>".
_aab_ident_field() {
    case "$2" in
        name)  printf '%s' "$1" | sed -E 's/ <[^>]*> [0-9]+ [-+][0-9]+$//' ;;
        email) printf '%s' "$1" | sed -E 's/.*<([^>]*)> [0-9]+ [-+][0-9]+$/\1/' ;;
    esac
}

# Block the commit unless the author and committer identity match the global
# git config, and unless the globally-configured signing is honored. The
# expected values come from --global, which `git -c`, GIT_CONFIG_PARAMETERS,
# and a repo-local config cannot override; the actual values come from
# `git var`, which reflects `--author` and GIT_AUTHOR_*/GIT_COMMITTER_* env
# vars that the effective `git config user.email` does not.
_aab_enforce_commit_identity() {
    local exp_name exp_email
    exp_name=$(git config --global --get user.name 2>/dev/null || true)
    exp_email=$(git config --global --get user.email 2>/dev/null || true)

    # Nothing pinned in the global config — nothing to enforce.
    if [ -z "$exp_name" ] && [ -z "$exp_email" ]; then
        return 0
    fi

    local author committer a_name a_email c_name c_email
    author=$(git var GIT_AUTHOR_IDENT 2>/dev/null) || return 0
    committer=$(git var GIT_COMMITTER_IDENT 2>/dev/null) || return 0
    a_name=$(_aab_ident_field "$author" name)
    a_email=$(_aab_ident_field "$author" email)
    c_name=$(_aab_ident_field "$committer" name)
    c_email=$(_aab_ident_field "$committer" email)

    local bad=0
    if [ -n "$exp_email" ]; then
        [ "$a_email" = "$exp_email" ] || bad=1
        [ "$c_email" = "$exp_email" ] || bad=1
    fi
    if [ -n "$exp_name" ]; then
        [ "$a_name" = "$exp_name" ] || bad=1
        [ "$c_name" = "$exp_name" ] || bad=1
    fi
    if [ "$bad" -ne 0 ]; then
        {
            echo "[autonomous-agent-bootstrap] Commit blocked: identity does not match the global git config."
            echo "  expected:  ${exp_name} <${exp_email}>"
            echo "  author:    ${a_name} <${a_email}>"
            echo "  committer: ${c_name} <${c_email}>"
            echo "  Use the configured identity: plain 'git commit', without -c user.*, --author, or GIT_AUTHOR_*/GIT_COMMITTER_*."
            echo "  This rule is configured by autonomous-agent-bootstrap. See ~/.claude/CLAUDE.md and ~/.codex/AGENTS.md."
        } >&2
        return 1
    fi

    # When the global config requires signing, refuse a commit that disables it
    # via config (e.g. `-c commit.gpgsign=false`) or swaps the signing key. The
    # per-commit `--no-gpg-sign` flag is invisible to the hook, mirroring how
    # `--no-verify` skips hooks entirely.
    local exp_sign
    exp_sign=$(git config --global --get commit.gpgsign 2>/dev/null || true)
    if [ "$exp_sign" = "true" ]; then
        local eff_sign exp_key eff_key
        eff_sign=$(git config --type=bool --get commit.gpgsign 2>/dev/null || true)
        if [ "$eff_sign" != "true" ]; then
            echo "[autonomous-agent-bootstrap] Commit blocked: signing is required by the global git config but disabled for this commit." >&2
            return 1
        fi
        exp_key=$(git config --global --get user.signingkey 2>/dev/null || true)
        eff_key=$(git config --get user.signingkey 2>/dev/null || true)
        if [ -n "$exp_key" ] && [ "$eff_key" != "$exp_key" ]; then
            echo "[autonomous-agent-bootstrap] Commit blocked: signing key does not match the global git config." >&2
            return 1
        fi
    fi
    return 0
}

# Block the commit if a secret is staged. The motivation: an unattended agent
# committed a live GitHub admin token into a repo because nothing scanned the
# diff locally. This is the last line of defense before a secret reaches an
# object the agent might push.
#
# Preferred engine: gitleaks (`protect --staged`), a static binary the
# bootstrap installs. Resolved by name on PATH first, then at the bootstrap's
# install path, so it works even when the hook runs with a trimmed PATH. When
# gitleaks is absent (install skipped: unsupported arch, offline, checksum
# mismatch) we fall back to a POSIX-shell grep of the staged diff for the
# high-value credential shapes, so a commit is never left wholly unscanned.
#
# Escape hatch (use only when a "secret" is a deliberate fixture / test
# vector): set GITLEAKS_ALLOW=1 in the environment, or `git commit --no-verify`
# to skip every hook.
_aab_scan_secrets() {
    if [ "${GITLEAKS_ALLOW:-}" = "1" ]; then
        echo "[autonomous-agent-bootstrap] GITLEAKS_ALLOW=1 set — skipping the staged secret scan." >&2
        return 0
    fi

    # Nothing staged (e.g. an allowed-empty / amend-only commit): nothing to do.
    git diff --cached --quiet 2>/dev/null && return 0

    local gl=""
    if command -v gitleaks >/dev/null 2>&1; then
        gl=gitleaks
    elif [ -x "$HOME/.local/bin/gitleaks" ]; then
        gl="$HOME/.local/bin/gitleaks"
    fi

    if [ -n "$gl" ]; then
        # `protect --staged` scans the staged diff only (the about-to-be-committed
        # content) and exits nonzero on a finding. --redact keeps the secret value
        # out of the printed report; --no-banner quiets the startup art.
        if ! "$gl" protect --staged --redact --no-banner; then
            {
                echo "[autonomous-agent-bootstrap] Commit blocked: gitleaks found a secret in the staged changes (value redacted above)."
                echo "  Remove the secret from the staged content, then re-commit."
                echo "  If this is a deliberate fixture, bypass with GITLEAKS_ALLOW=1 git commit … or git commit --no-verify."
            } >&2
            return 1
        fi
        return 0
    fi

    # ---- Fallback: gitleaks unavailable. Grep the staged diff (added lines
    # only, to avoid re-flagging secrets already in history) for the
    # highest-value credential shapes. -E extended regex; case-sensitive on
    # purpose (the prefixes are case-significant).
    local added hit=0
    added=$(git diff --cached --no-color --diff-filter=ACMR -U0 2>/dev/null \
        | grep -E '^\+' | grep -Ev '^\+\+\+ ')
    [ -n "$added" ] || return 0

    # Pattern, human label. Each pattern targets a credential class that is both
    # high-confidence (low false-positive) and high-impact if leaked.
    local patterns=(
        'gh[pousr]_[0-9A-Za-z]{36,}|github_pat_[0-9A-Za-z_]{82}::GitHub token'
        'https?://[^/[:space:]:@]+:[^/[:space:]@]+@::URL-embedded credentials'
        'x-access-token:[0-9A-Za-z_]+::URL-embedded GitHub token'
        'AKIA[0-9A-Z]{16}::AWS access key id'
        'sk-[A-Za-z0-9_-]{20,}::OpenAI/Anthropic-style API key'
        'AIza[0-9A-Za-z_-]{35}::Google API key'
        'xox[baprs]-[0-9A-Za-z-]{10,}::Slack token'
        '-----BEGIN[A-Z ]*PRIVATE KEY-----::Private key block'
        'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+::JWT'
    )
    local entry pat label
    for entry in "${patterns[@]}"; do
        pat=${entry%%::*}
        label=${entry##*::}
        if printf '%s\n' "$added" | grep -Eq -- "$pat"; then
            echo "[autonomous-agent-bootstrap] Commit blocked: possible secret in staged changes — ${label}." >&2
            hit=1
        fi
    done
    if [ "$hit" -ne 0 ]; then
        {
            echo "  (Scanned with the built-in fallback; install gitleaks for full coverage.)"
            echo "  Remove the secret from the staged content, then re-commit."
            echo "  If this is a deliberate fixture, bypass with GITLEAKS_ALLOW=1 git commit … or git commit --no-verify."
        } >&2
        return 1
    fi
    return 0
}

if [ "$hook_name" = "pre-commit" ]; then
    _aab_enforce_commit_identity || exit 1
    _aab_scan_secrets || exit 1
fi

# Chain to the repository's own hook of the same name. The repo hooks dir is
# located via --git-common-dir (so linked worktrees share the main repo's
# hooks); --git-path is avoided because it honors core.hooksPath and would
# resolve back to this dispatcher.
common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
common_dir=$(cd "$common_dir" 2>/dev/null && pwd) || exit 0
repo_hook="$common_dir/hooks/$hook_name"
if [ -x "$repo_hook" ]; then
    self_dir=$(cd "$(dirname -- "$0")" 2>/dev/null && pwd || true)
    repo_target=$(readlink -f -- "$repo_hook" 2>/dev/null || echo "$repo_hook")
    self_target=$(readlink -f -- "${self_dir}/$(basename -- "$0")" 2>/dev/null || true)
    # Skip a repo hook that is just a symlink back to this dispatcher.
    if [ "$repo_target" != "$self_target" ]; then
        exec "$repo_hook" "$@"
    fi
fi
exit 0
HOOK
}

configure_git_hooks() {
    if ! command -v git >/dev/null 2>&1; then
        warn "git not installed — skipping git hook enforcement."
        return
    fi

    mkdir -p "${GIT_HOOKS_DIR}"
    local tmp
    tmp=$(mktemp "${GIT_HOOK_DISPATCHER}.tmp.XXXXXX")
    _render_git_hook_script > "$tmp"
    chmod 0755 "$tmp"
    mv -f "$tmp" "${GIT_HOOK_DISPATCHER}"

    local name
    for name in "${GIT_HOOK_NAMES[@]}"; do
        ln -sf "aab-git-hook" "${GIT_HOOKS_DIR}/${name}"
    done

    git config --global core.hooksPath "${GIT_HOOKS_DIR}"
    log "Configured global git hooks at ${GIT_HOOKS_DIR} and set core.hooksPath (enforces the global commit identity and scans staged commits for secrets)."
}
