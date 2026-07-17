# ---------------------------------------------------------------------------
# 10b. Install Claude and Codex launcher wrapper families.
# ---------------------------------------------------------------------------
_is_aab_launcher_symlink_target() {
    case "$(basename "$1")" in
        claude-first-party|claude-third-party-anthropic|claude-third-party-deepseek|claude-third-party-nemotron|codex-first-party|codex-third-party-openai|codex-third-party-nemotron|codex-third-party-deepseek)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

_prepare_launcher_real_binary() {
    local agent_name="$1" agent_bin="$2" real_bin="$3" marker="$4"

    if [ ! -e "$agent_bin" ]; then
        warn "${agent_name} binary not found at ${agent_bin}; cannot install launcher wrappers."
        exit 1
    fi

    if [ -L "$agent_bin" ]; then
        local target
        target=$(readlink "$agent_bin")
        if _is_aab_launcher_symlink_target "$target"; then
            if [ ! -e "$real_bin" ]; then
                warn "${agent_name} launcher is installed but ${real_bin} is missing."
                exit 1
            fi
            return
        fi
        ln -sfn "$target" "$real_bin"
    elif ! grep -q "$marker" "$agent_bin" 2>/dev/null; then
        mv "$agent_bin" "$real_bin"
    elif [ ! -e "$real_bin" ]; then
        warn "${agent_name} launcher is installed but ${real_bin} is missing."
        exit 1
    fi
}

_write_claude_launcher() {
    local provider="$1" launcher="$2" tmp
    tmp=$(mktemp "${launcher}.tmp.XXXXXX")
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' '# Autonomous-agent-bootstrap Claude launcher.'
        printf 'provider=%q\n' "$provider"
        printf 'default_model=%q\n' "$DEFAULT_CLAUDE_CODE_MODEL"
        printf 'default_haiku_model=%q\n' "$DEFAULT_CLAUDE_CODE_HAIKU_MODEL"
        printf 'default_sonnet_model=%q\n' "$DEFAULT_CLAUDE_CODE_SONNET_MODEL"
        printf 'default_opus_model=%q\n' "$DEFAULT_CLAUDE_CODE_OPUS_MODEL"
        printf 'default_effort=%q\n' "$DEFAULT_CLAUDE_CODE_EFFORT"
        cat <<'BASH'
set -euo pipefail

real_bin="${AAB_CLAUDE_REAL_BIN:-$HOME/.local/bin/claude-aab-real}"
env_file="${AAB_ENV_FILE:-$HOME/.aab/.env}"
if [ -f "$env_file" ]; then
    set -a
    . "$env_file"
    set +a
fi

if [ ! -x "$real_bin" ]; then
    printf '[bootstrap] WARN: Claude real binary not executable: %s\n' "$real_bin" >&2
    exit 127
fi

export AAB_CLAUDE_CODE_INFERENCE_PROVIDER="$provider"
export CLAUDE_CODE_SANDBOXED=1
export DEBUG_SDK=1
export CLAUDE_CODE_EFFORT_LEVEL="${AAB_CLAUDE_CODE_EFFORT:-$default_effort}"
[ -n "${AAB_GH_TOKEN:-}" ] && export GH_TOKEN="$AAB_GH_TOKEN"
[ -n "${AAB_BREV_API_KEY:-}" ] && export BREV_API_KEY="$AAB_BREV_API_KEY"
[ -n "${AAB_BREV_ORG_ID:-}" ] && export BREV_ORG_ID="$AAB_BREV_ORG_ID"

unset ANTHROPIC_API_KEY
unset ANTHROPIC_BASE_URL
unset ANTHROPIC_AUTH_TOKEN
unset ANTHROPIC_MODEL
unset ANTHROPIC_DEFAULT_HAIKU_MODEL
unset ANTHROPIC_DEFAULT_SONNET_MODEL
unset ANTHROPIC_DEFAULT_OPUS_MODEL
unset CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS

case "$provider" in
    first-party)
        [ -n "${AAB_CLAUDE_CODE_FIRST_PARTY_API_KEY:-}" ] && export ANTHROPIC_API_KEY="$AAB_CLAUDE_CODE_FIRST_PARTY_API_KEY"
        export ANTHROPIC_MODEL="${AAB_CLAUDE_CODE_FIRST_PARTY_MODEL:-$default_model}"
        export ANTHROPIC_DEFAULT_HAIKU_MODEL="${AAB_CLAUDE_CODE_FIRST_PARTY_HAIKU_MODEL:-$default_haiku_model}"
        export ANTHROPIC_DEFAULT_SONNET_MODEL="${AAB_CLAUDE_CODE_FIRST_PARTY_SONNET_MODEL:-$default_sonnet_model}"
        export ANTHROPIC_DEFAULT_OPUS_MODEL="${AAB_CLAUDE_CODE_FIRST_PARTY_OPUS_MODEL:-$default_opus_model}"
        ;;
    third-party-anthropic)
        [ -n "${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_BASE_URL:-}" ] && export ANTHROPIC_BASE_URL="$AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_BASE_URL"
        [ -n "${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_API_KEY:-}" ] && export ANTHROPIC_AUTH_TOKEN="$AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_API_KEY"
        export ANTHROPIC_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_MODEL:-$default_model}"
        export ANTHROPIC_DEFAULT_HAIKU_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_HAIKU_MODEL:-$default_haiku_model}"
        export ANTHROPIC_DEFAULT_SONNET_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_SONNET_MODEL:-$default_sonnet_model}"
        export ANTHROPIC_DEFAULT_OPUS_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_OPUS_MODEL:-$default_opus_model}"
        ;;
    third-party-deepseek)
        [ -n "${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_BASE_URL:-}" ] && export ANTHROPIC_BASE_URL="$AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_BASE_URL"
        [ -n "${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_API_KEY:-}" ] && export ANTHROPIC_AUTH_TOKEN="$AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_API_KEY"
        # Claude Code resolves a model's context window to 200K unless the model
        # name carries a "[1m]" suffix (or is a known first-party id). Without a
        # known window, auto-compaction is also skipped in a local session, so
        # the conversation grows until the provider's hard limit. Tag the model
        # with "[1m]" so Claude Code resolves the full window and engages
        # compaction; the suffix is stripped from the model name before the
        # request, so the gateway still receives the real id (DeepSeek V4 Pro:
        # 1M context window).
        deepseek_model="${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_MODEL:-$default_model}"
        export ANTHROPIC_MODEL="${deepseek_model}[1m]"
        export ANTHROPIC_DEFAULT_HAIKU_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_HAIKU_MODEL:-$default_haiku_model}"
        export ANTHROPIC_DEFAULT_SONNET_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_SONNET_MODEL:-$default_sonnet_model}"
        export ANTHROPIC_DEFAULT_OPUS_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_OPUS_MODEL:-$default_opus_model}"
        # Pin the auto-compact window to DeepSeek's full 1M context. Compaction
        # then fires ~33K below it (~967K), the same window-minus-reserve margin
        # a first-party 1M model uses.
        export CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000
        ;;
    third-party-nemotron)
        [ -n "${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_BASE_URL:-}" ] && export ANTHROPIC_BASE_URL="$AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_BASE_URL"
        [ -n "${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_API_KEY:-}" ] && export ANTHROPIC_AUTH_TOKEN="$AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_API_KEY"
        # Tag the model with "[1m]" so Claude Code resolves the full configured
        # window and engages auto-compaction (see the deepseek arm above); the
        # suffix is stripped before the request, so the gateway receives the
        # real id. Nemotron 3 Ultra's window is 262,144, below the 1M the tag
        # unlocks, so the auto-compact window below is what actually applies.
        nemotron_model="${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_MODEL:-$default_model}"
        export ANTHROPIC_MODEL="${nemotron_model}[1m]"
        export ANTHROPIC_DEFAULT_HAIKU_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_HAIKU_MODEL:-$default_haiku_model}"
        export ANTHROPIC_DEFAULT_SONNET_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_SONNET_MODEL:-$default_sonnet_model}"
        export ANTHROPIC_DEFAULT_OPUS_MODEL="${AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_OPUS_MODEL:-$default_opus_model}"
        # Pin the auto-compact window to Nemotron's full 262,144 context.
        # Compaction fires ~33K below it (~229K), the same window-minus-reserve
        # margin a first-party model uses, leaving headroom under the hard limit
        # (the failure this prevents hit ~268K with no compaction at all).
        export CLAUDE_CODE_AUTO_COMPACT_WINDOW=262144
        ;;
esac

# CLAUDE_CODE_SUBAGENT_MODEL pins the model for sub-agents and team teammates,
# which spawn as separate Claude Code processes and otherwise resolve a
# canonical first-party model id that a third-party gateway rejects. Default it
# to the same resolved ANTHROPIC_MODEL the main agent uses (provider-correct,
# carrying any "[1m]" suffix); AAB_CLAUDE_CODE_SUBAGENT_MODEL overrides.
export CLAUDE_CODE_SUBAGENT_MODEL="${AAB_CLAUDE_CODE_SUBAGENT_MODEL:-$ANTHROPIC_MODEL}"

has_skip=0
for arg in "$@"; do
    case "$arg" in
        --dangerously-skip-permissions)
            has_skip=1
            ;;
    esac
done

extra_args=()
if [ "$has_skip" -eq 0 ]; then
    extra_args=(--dangerously-skip-permissions)
fi

exec "$real_bin" "${extra_args[@]}" "$@"
BASH
    } > "$tmp"
    chmod 755 "$tmp"
    mv -f "$tmp" "$launcher"
}

install_claude_launcher() {
    local launcher_dir="${HOME}/.local/aab-bin"
    local claude_bin="${HOME}/.local/bin/claude"
    local real_bin="${HOME}/.local/bin/claude-aab-real"
    local selected_provider
    selected_provider=$(normalize_claude_code_inference_provider "${AAB_CLAUDE_CODE_INFERENCE_PROVIDER:-$DEFAULT_CLAUDE_CODE_INFERENCE_PROVIDER}")

    if [ ! -e "$claude_bin" ]; then
        warn "claude binary not found at ${claude_bin}; cannot install launcher wrappers."
        exit 1
    fi

    # The native installer owns ~/.local/bin/claude and repoints it to each new
    # version. Point the wrappers' exec target at that symlink (rather than a
    # pinned version) so every wrapper runs whatever the updater currently
    # installs. install_claude runs first in main(), so ~/.local/bin/claude is
    # the native binary here, never one of our wrapper symlinks.
    ln -sfn "$claude_bin" "$real_bin"
    _write_claude_launcher "first-party" "${HOME}/.local/bin/claude-first-party"
    _write_claude_launcher "third-party-anthropic" "${HOME}/.local/bin/claude-third-party-anthropic"
    _write_claude_launcher "third-party-deepseek" "${HOME}/.local/bin/claude-third-party-deepseek"
    _write_claude_launcher "third-party-nemotron" "${HOME}/.local/bin/claude-third-party-nemotron"

    # Put the selected `claude` entrypoint in a dedicated directory kept ahead of
    # ~/.local/bin on PATH (see update_bashrc / update_profile), so the native
    # auto-updater's ~/.local/bin/claude can't shadow the wrapper. The entrypoint
    # is a regular launcher file rather than a symlink to a provider wrapper.
    mkdir -p "$launcher_dir"
    _write_claude_launcher "$selected_provider" "${launcher_dir}/claude"
    log "Installed Claude launcher wrappers (selected=${selected_provider}); entrypoint at ${launcher_dir}/claude."
}

_write_codex_launcher() {
    local provider="$1" launcher="$2" tmp
    tmp=$(mktemp "${launcher}.tmp.XXXXXX")
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' '# Autonomous-agent-bootstrap Codex launcher.'
        printf 'provider=%q\n' "$provider"
        printf 'default_model=%q\n' "$DEFAULT_CODEX_MODEL"
        printf 'default_third_party_openai_model=%q\n' "$DEFAULT_CODEX_THIRD_PARTY_OPENAI_MODEL"
        printf 'default_third_party_openai_base_url=%q\n' "$DEFAULT_CODEX_THIRD_PARTY_OPENAI_BASE_URL"
        printf 'default_third_party_nemotron_model=%q\n' "$DEFAULT_CODEX_THIRD_PARTY_NEMOTRON_MODEL"
        printf 'default_third_party_nemotron_base_url=%q\n' "$DEFAULT_CODEX_THIRD_PARTY_NEMOTRON_BASE_URL"
        printf 'default_third_party_deepseek_model=%q\n' "$DEFAULT_CODEX_THIRD_PARTY_DEEPSEEK_MODEL"
        printf 'default_third_party_deepseek_base_url=%q\n' "$DEFAULT_CODEX_THIRD_PARTY_DEEPSEEK_BASE_URL"
        cat <<'BASH'
set -euo pipefail

real_bin="${AAB_CODEX_REAL_BIN:-$HOME/.local/bin/codex-aab-real}"
env_file="${AAB_ENV_FILE:-$HOME/.aab/.env}"
if [ -f "$env_file" ]; then
    set -a
    . "$env_file"
    set +a
fi

if [ ! -x "$real_bin" ]; then
    printf '[bootstrap] WARN: Codex real binary not executable: %s\n' "$real_bin" >&2
    exit 127
fi

toml_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    printf '%s' "$s"
}

canonical_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        (cd "$dir" 2>/dev/null && pwd -P) || printf '%s' "$dir"
    else
        printf '%s' "$dir"
    fi
}

export AAB_CODEX_INFERENCE_PROVIDER="$provider"
[ -n "${AAB_GH_TOKEN:-}" ] && export GH_TOKEN="$AAB_GH_TOKEN"
[ -n "${AAB_BREV_API_KEY:-}" ] && export BREV_API_KEY="$AAB_BREV_API_KEY"
[ -n "${AAB_BREV_ORG_ID:-}" ] && export BREV_ORG_ID="$AAB_BREV_ORG_ID"

model="${AAB_CODEX_FIRST_PARTY_MODEL:-$default_model}"
config_args=()
case "$provider" in
    first-party)
        [ -n "${AAB_CODEX_FIRST_PARTY_API_KEY:-}" ] && export OPENAI_API_KEY="$AAB_CODEX_FIRST_PARTY_API_KEY"
        model="${AAB_CODEX_FIRST_PARTY_MODEL:-$default_model}"
        model_escaped=$(toml_escape "$model")
        config_args=(-c "model=\"${model_escaped}\"" -c 'model_provider="openai"')
        ;;
    third-party-openai)
        unset OPENAI_API_KEY
        model="${AAB_CODEX_THIRD_PARTY_OPENAI_MODEL:-$default_third_party_openai_model}"
        base_url="${AAB_CODEX_THIRD_PARTY_OPENAI_BASE_URL:-$default_third_party_openai_base_url}"
        model_escaped=$(toml_escape "$model")
        base_url_escaped=$(toml_escape "$base_url")
        provider_override="model_providers={\"third-party-openai\"={name=\"Third Party OpenAI\",base_url=\"${base_url_escaped}\",env_key=\"AAB_CODEX_THIRD_PARTY_OPENAI_API_KEY\",wire_api=\"responses\",request_max_retries=4,stream_max_retries=5,stream_idle_timeout_ms=300000}}"
        config_args=(-c "model=\"${model_escaped}\"" -c 'model_provider="third-party-openai"' -c "$provider_override")
        ;;
    third-party-nemotron)
        unset OPENAI_API_KEY
        model="${AAB_CODEX_THIRD_PARTY_NEMOTRON_MODEL:-$default_third_party_nemotron_model}"
        base_url="${AAB_CODEX_THIRD_PARTY_NEMOTRON_BASE_URL:-$default_third_party_nemotron_base_url}"
        model_escaped=$(toml_escape "$model")
        base_url_escaped=$(toml_escape "$base_url")
        provider_override="model_providers={\"third-party-nemotron\"={name=\"Third Party Nemotron\",base_url=\"${base_url_escaped}\",env_key=\"AAB_CODEX_THIRD_PARTY_NEMOTRON_API_KEY\",wire_api=\"responses\",request_max_retries=4,stream_max_retries=5,stream_idle_timeout_ms=300000}}"
        config_args=(-c "model=\"${model_escaped}\"" -c 'model_provider="third-party-nemotron"' -c "$provider_override")
        ;;
    third-party-deepseek)
        unset OPENAI_API_KEY
        model="${AAB_CODEX_THIRD_PARTY_DEEPSEEK_MODEL:-$default_third_party_deepseek_model}"
        base_url="${AAB_CODEX_THIRD_PARTY_DEEPSEEK_BASE_URL:-$default_third_party_deepseek_base_url}"
        model_escaped=$(toml_escape "$model")
        base_url_escaped=$(toml_escape "$base_url")
        provider_override="model_providers={\"third-party-deepseek\"={name=\"Third Party DeepSeek\",base_url=\"${base_url_escaped}\",env_key=\"AAB_CODEX_THIRD_PARTY_DEEPSEEK_API_KEY\",wire_api=\"responses\",request_max_retries=4,stream_max_retries=5,stream_idle_timeout_ms=300000}}"
        config_args=(-c "model=\"${model_escaped}\"" -c 'model_provider="third-party-deepseek"' -c "$provider_override")
        ;;
esac

cwd=$(canonical_dir "${PWD:-.}")
git_root=""
if command -v git >/dev/null 2>&1; then
    git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)
    if [ -n "$git_root" ]; then
        git_root=$(canonical_dir "$git_root")
    fi
fi

cwd_escaped=$(toml_escape "$cwd")
trust_override="projects={\"${cwd_escaped}\"={trust_level=\"trusted\"}"
if [ -n "$git_root" ] && [ "$git_root" != "$cwd" ]; then
    git_root_escaped=$(toml_escape "$git_root")
    trust_override="${trust_override},\"${git_root_escaped}\"={trust_level=\"trusted\"}"
fi
trust_override="${trust_override}}"

has_yolo=0
has_hook_bypass=0
for arg in "$@"; do
    case "$arg" in
        --dangerously-bypass-approvals-and-sandbox|--yolo)
            has_yolo=1
            ;;
        --dangerously-bypass-hook-trust)
            has_hook_bypass=1
            ;;
    esac
done

extra_args=("${config_args[@]}" -c "$trust_override")
if [ "$has_hook_bypass" -eq 0 ]; then
    extra_args=(--dangerously-bypass-hook-trust "${extra_args[@]}")
fi
if [ "$has_yolo" -eq 0 ]; then
    extra_args=(--dangerously-bypass-approvals-and-sandbox "${extra_args[@]}")
fi

exec "$real_bin" "${extra_args[@]}" "$@"
BASH
    } > "$tmp"
    chmod 755 "$tmp"
    mv -f "$tmp" "$launcher"
}

install_codex_launcher() {
    local codex_bin="${HOME}/.local/bin/codex"
    local real_bin="${HOME}/.local/bin/codex-aab-real"
    local selected_provider
    selected_provider=$(normalize_codex_inference_provider "${AAB_CODEX_INFERENCE_PROVIDER:-$DEFAULT_CODEX_INFERENCE_PROVIDER}")

    _prepare_launcher_real_binary "codex" "$codex_bin" "$real_bin" "Autonomous-agent-bootstrap Codex launcher"
    _write_codex_launcher "first-party" "${HOME}/.local/bin/codex-first-party"
    _write_codex_launcher "third-party-openai" "${HOME}/.local/bin/codex-third-party-openai"
    _write_codex_launcher "third-party-nemotron" "${HOME}/.local/bin/codex-third-party-nemotron"
    _write_codex_launcher "third-party-deepseek" "${HOME}/.local/bin/codex-third-party-deepseek"
    _write_codex_launcher "$selected_provider" "$codex_bin"
    log "Installed Codex launcher wrappers at ${HOME}/.local/bin (selected=${selected_provider})."
}

