# ---------------------------------------------------------------------------
# Optional config input (positional arg or stdin).
#
# main() picks one of three modes, in order:
#   1. positional path: `bash bootstrap.bash /path/to/aab.conf` — load_config_file
#      reads the file at the supplied path.
#   2. stdin pipe:      `bash bootstrap.bash <<EOF ... EOF` (or any non-TTY
#      stdin shape) — load_config_stdin reads stdin into a temp file and loads
#      that. The temp file is removed before main() returns.
#   3. neither:         the script runs with whatever env vars the shell
#      already has, no config-file step.
#
# In modes 1 and 2 the config text is sourced via `set -a; . <path>; set +a`.
# That's the standard bash idiom for KEY=VALUE files and gives the file
# access to the full shell language: `${VAR:-default}` expansions, `$(cmd)`
# substitutions, multi-line strings, comments, etc. Values containing shell
# metacharacters (`&`, `|`, `;`, `$`, etc.) need to be quoted; bare quoted
# `KEY=value` lines need no escaping.
#
# Caller-supplied env vars beat file values: load_config_{file,stdin}
# snapshot the exported environment before sourcing and replay it after, so
# a one-off `FOO=override bash bootstrap.bash /path/to/conf` debug invocation
# wins over whatever the file said. An explicitly-empty `FOO= bash …`
# counts as set and also wins (file cannot force-unset what the shell
# explicitly set).
# ---------------------------------------------------------------------------
load_config_file() {
    local f="$1"
    if [ ! -r "$f" ]; then
        warn "Config file '$f' not found or not readable."
        exit 1
    fi
    log "Loading config from $f (env vars already set in the shell take precedence)."
    _source_config "$f"
}

load_config_stdin() {
    local tmp
    tmp=$(mktemp)
    cat > "$tmp"
    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        return 0
    fi
    log "Loading config from stdin (env vars already set in the shell take precedence)."
    _source_config "$tmp"
    rm -f "$tmp"
}

# Source the config at <path> with auto-export, preserving caller-supplied env
# vars. `declare -px` snapshots every exported variable; we strip the
# readonly entries (re-eval'ing those would error) and rewrite `declare -x`
# as `export` so the snapshot restores at the calling shell's scope rather
# than going out of scope when the function returns.
_source_config() {
    local src="$1" snapshot
    snapshot=$(declare -px | grep -v '^declare -[a-z]*r' | sed 's/^declare -x /export /')
    set -a
    # shellcheck source=/dev/null
    . "$src"
    set +a
    eval "$snapshot"
}

main() {
    if [ -n "${1:-}" ]; then
        load_config_file "$1"
    elif [ ! -t 0 ]; then
        load_config_stdin
    fi
    validate_model_profiles
    install_base_deps
    install_uv_tools
    install_claude
    install_codex
    install_node
    install_pi
    install_brev
    install_lifeboat
    install_gh
    install_gitleaks
    configure_aab_env_file
    configure_github_shell
    configure_brev
    configure_claude
    configure_codex
    configure_pi_models
    configure_pi_settings
    configure_pi_observability
    configure_git
    configure_auth_ssh_key
    configure_signing_ssh_key
    configure_git_hooks
    configure_agent_rules
    install_agent_plugins
    install_pi_plugins
    configure_claude_launchers
    configure_codex_launchers
    configure_pi_launchers
    install_autocuda
    configure_user_linger
    configure_bashrc
    configure_profile
    log "Done. Open a new shell (or 'source ~/.bashrc') so PATH updates take effect."
}

# `:-$0` covers the `curl ... | bash` case, where BASH_SOURCE is empty and
# would otherwise trip `set -u`.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
