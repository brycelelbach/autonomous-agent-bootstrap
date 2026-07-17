# ---------------------------------------------------------------------------
# Write profile-driven Claude, Codex, and Pi launcher families.
# ---------------------------------------------------------------------------
_is_aab_launcher_symlink_target() {
    case "$(basename "$1")" in
        claude-first-party-*|claude-third-party-*|claude-first-party|codex-first-party-*|codex-third-party-*|codex-first-party|pi-*)
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
        warn "${agent_name} binary not found at ${agent_bin}; cannot write launcher wrappers."
        exit 1
    fi

    if [ -L "$agent_bin" ]; then
        local target
        target=$(readlink "$agent_bin")
        if _is_aab_launcher_symlink_target "$target"; then
            if [ ! -e "$real_bin" ]; then
                warn "${agent_name} launcher exists but ${real_bin} is missing."
                exit 1
            fi
            return
        fi
        ln -sfn "$target" "$real_bin"
    elif ! grep -q "$marker" "$agent_bin" 2>/dev/null; then
        mv "$agent_bin" "$real_bin"
    elif [ ! -e "$real_bin" ]; then
        warn "${agent_name} launcher exists but ${real_bin} is missing."
        exit 1
    fi
}

_remove_aab_profile_launchers() {
    local marker="$1"
    shift
    local pattern launcher
    for pattern in "$@"; do
        for launcher in $pattern; do
            [ -f "$launcher" ] || continue
            [ -L "$launcher" ] && continue
            if grep -q "$marker" "$launcher" 2>/dev/null; then
                rm -f "$launcher"
            fi
        done
    done
}

_write_claude_launcher() {
    local source="$1" name="$2" model="$3" haiku="$4" sonnet="$5" opus="$6"
    local effort="$7" context="$8" subagent="$9" launcher="${10}" tmp
    local resolved_model="$model" resolved_subagent="$subagent"
    if [ -n "$context" ]; then
        case "$resolved_model" in
            *\[1m\]) ;;
            *) resolved_model="${resolved_model}[1m]" ;;
        esac
        if [ "$resolved_subagent" = "$model" ]; then
            resolved_subagent="$resolved_model"
        fi
    fi

    tmp=$(mktemp "${launcher}.tmp.XXXXXX")
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' '# Autonomous-agent-bootstrap Claude launcher.'
        printf 'profile_source=%q\n' "$source"
        printf 'profile_name=%q\n' "$name"
        printf 'profile_model=%q\n' "$resolved_model"
        printf 'profile_haiku=%q\n' "$haiku"
        printf 'profile_sonnet=%q\n' "$sonnet"
        printf 'profile_opus=%q\n' "$opus"
        printf 'profile_effort=%q\n' "$effort"
        printf 'profile_context=%q\n' "$context"
        printf 'profile_subagent=%q\n' "$resolved_subagent"
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

export AAB_CLAUDE_PROFILE="${profile_source}/${profile_name}"
export CLAUDE_CODE_SANDBOXED=1
export DEBUG_SDK=1
export CLAUDE_CODE_EFFORT_LEVEL="$profile_effort"
[ -n "${AAB_GH_TOKEN:-}" ] && export GH_TOKEN="$AAB_GH_TOKEN"
[ -n "${AAB_BREV_API_KEY:-}" ] && export BREV_API_KEY="$AAB_BREV_API_KEY"
[ -n "${AAB_BREV_ORG_ID:-}" ] && export BREV_ORG_ID="$AAB_BREV_ORG_ID"

unset ANTHROPIC_BASE_URL
unset ANTHROPIC_AUTH_TOKEN
unset ANTHROPIC_MODEL
unset ANTHROPIC_DEFAULT_HAIKU_MODEL
unset ANTHROPIC_DEFAULT_SONNET_MODEL
unset ANTHROPIC_DEFAULT_OPUS_MODEL
unset CLAUDE_CODE_AUTO_COMPACT_WINDOW
unset CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS

case "$profile_source" in
    first-party)
        ;;
    third-party)
        unset ANTHROPIC_API_KEY
        if [ -z "${AAB_INFERENCE_GATEWAY_URL:-}" ]; then
            printf '[bootstrap] WARN: Claude profile %s requires AAB_INFERENCE_GATEWAY_URL.\n' "$profile_name" >&2
            exit 1
        fi
        export ANTHROPIC_BASE_URL="$AAB_INFERENCE_GATEWAY_URL"
        [ -n "${AAB_INFERENCE_GATEWAY_API_KEY:-}" ] && export ANTHROPIC_AUTH_TOKEN="$AAB_INFERENCE_GATEWAY_API_KEY"
        ;;
esac

export ANTHROPIC_MODEL="$profile_model"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$profile_haiku"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$profile_sonnet"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$profile_opus"
export CLAUDE_CODE_SUBAGENT_MODEL="$profile_subagent"
if [ -n "$profile_context" ]; then
    export CLAUDE_CODE_AUTO_COMPACT_WINDOW="$profile_context"
fi

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

configure_claude_launchers() {
    local launcher_dir="${HOME}/.local/aab-bin"
    local claude_bin="${HOME}/.local/bin/claude"
    local real_bin="${HOME}/.local/bin/claude-aab-real"
    local source profiles line launcher
    local -A profile=() selected=()

    if [ ! -e "$claude_bin" ]; then
        warn "claude binary not found at ${claude_bin}; cannot write launcher wrappers."
        exit 1
    fi

    ln -sfn "$claude_bin" "$real_bin"
    mkdir -p "$launcher_dir" "${HOME}/.local/bin"
    _remove_aab_profile_launchers \
        'Autonomous-agent-bootstrap Claude launcher' \
        "${HOME}/.local/bin/claude-first-party*" \
        "${HOME}/.local/bin/claude-third-party-*"

    for source in first-party third-party; do
        profiles=$(_profile_list_for claude "$source")
        while IFS= read -r line; do
            _parse_model_profile_line claude "$source" "$line" profile
            if [ "$source" = "third-party" ]; then
                require_inference_gateway "Claude profile '${profile[name]}'"
            fi
            launcher="${HOME}/.local/bin/claude-${source}-${profile[name]}"
            _write_claude_launcher \
                "$source" "${profile[name]}" "${profile[model]}" \
                "${profile[haiku]}" "${profile[sonnet]}" "${profile[opus]}" \
                "${profile[effort]}" "${profile[context]}" "${profile[subagent]}" \
                "$launcher"
        done < <(_model_profile_lines "$profiles")
    done

    resolve_model_profile claude selected
    _write_claude_launcher \
        "${selected[source]}" "${selected[name]}" "${selected[model]}" \
        "${selected[haiku]}" "${selected[sonnet]}" "${selected[opus]}" \
        "${selected[effort]}" "${selected[context]}" "${selected[subagent]}" \
        "${launcher_dir}/claude"
    log "Wrote Claude profile launchers (selected=${selected[source]}/${selected[name]})."
}

_write_codex_launcher() {
    local source="$1" name="$2" model="$3" effort="$4" launcher="$5" tmp
    tmp=$(mktemp "${launcher}.tmp.XXXXXX")
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' '# Autonomous-agent-bootstrap Codex launcher.'
        printf 'profile_source=%q\n' "$source"
        printf 'profile_name=%q\n' "$name"
        printf 'profile_model=%q\n' "$model"
        printf 'profile_effort=%q\n' "$effort"
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
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '%s' "$value"
}

canonical_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        (cd "$dir" 2>/dev/null && pwd -P) || printf '%s' "$dir"
    else
        printf '%s' "$dir"
    fi
}

export AAB_CODEX_PROFILE="${profile_source}/${profile_name}"
[ -n "${AAB_GH_TOKEN:-}" ] && export GH_TOKEN="$AAB_GH_TOKEN"
[ -n "${AAB_BREV_API_KEY:-}" ] && export BREV_API_KEY="$AAB_BREV_API_KEY"
[ -n "${AAB_BREV_ORG_ID:-}" ] && export BREV_ORG_ID="$AAB_BREV_ORG_ID"

model_escaped=$(toml_escape "$profile_model")
effort_escaped=$(toml_escape "$profile_effort")
config_args=(-c "model=\"${model_escaped}\"" -c "model_reasoning_effort=\"${effort_escaped}\"")
case "$profile_source" in
    first-party)
        config_args+=(-c 'model_provider="openai"')
        ;;
    third-party)
        unset OPENAI_API_KEY
        if [ -z "${AAB_INFERENCE_GATEWAY_URL:-}" ]; then
            printf '[bootstrap] WARN: Codex profile %s requires AAB_INFERENCE_GATEWAY_URL.\n' "$profile_name" >&2
            exit 1
        fi
        base_url_escaped=$(toml_escape "$AAB_INFERENCE_GATEWAY_URL")
        provider_override="model_providers={\"aab-gateway\"={name=\"AAB Inference Gateway\",base_url=\"${base_url_escaped}\",env_key=\"AAB_INFERENCE_GATEWAY_API_KEY\",wire_api=\"responses\",request_max_retries=4,stream_max_retries=5,stream_idle_timeout_ms=300000}}"
        config_args+=(-c 'model_provider="aab-gateway"' -c "$provider_override")
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

configure_codex_launchers() {
    local codex_bin="${HOME}/.local/bin/codex"
    local real_bin="${HOME}/.local/bin/codex-aab-real"
    local source profiles line launcher
    local -A profile=() selected=()

    _prepare_launcher_real_binary "codex" "$codex_bin" "$real_bin" "Autonomous-agent-bootstrap Codex launcher"
    _remove_aab_profile_launchers \
        'Autonomous-agent-bootstrap Codex launcher' \
        "${HOME}/.local/bin/codex-first-party*" \
        "${HOME}/.local/bin/codex-third-party-*"

    for source in first-party third-party; do
        profiles=$(_profile_list_for codex "$source")
        while IFS= read -r line; do
            _parse_model_profile_line codex "$source" "$line" profile
            if [ "$source" = "third-party" ]; then
                require_inference_gateway "Codex profile '${profile[name]}'"
            fi
            launcher="${HOME}/.local/bin/codex-${source}-${profile[name]}"
            _write_codex_launcher "$source" "${profile[name]}" "${profile[model]}" "${profile[effort]}" "$launcher"
        done < <(_model_profile_lines "$profiles")
    done

    resolve_model_profile codex selected
    _write_codex_launcher "${selected[source]}" "${selected[name]}" "${selected[model]}" "${selected[effort]}" "$codex_bin"
    log "Wrote Codex profile launchers (selected=${selected[source]}/${selected[name]})."
}

_write_pi_launcher() {
    local name="$1" model="$2" effort="$3" launcher="$4" tmp
    tmp=$(mktemp "${launcher}.tmp.XXXXXX")
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' '# Autonomous-agent-bootstrap Pi launcher.'
        printf 'profile_name=%q\n' "$name"
        printf 'profile_model=%q\n' "$model"
        printf 'profile_effort=%q\n' "$effort"
        cat <<'BASH'
set -euo pipefail

real_bin="${AAB_PI_REAL_BIN:-$HOME/.local/bin/pi-aab-real}"
env_file="${AAB_ENV_FILE:-$HOME/.aab/.env}"
observability_env_file="${AAB_PI_OBSERVABILITY_ENV_FILE:-$HOME/.aab/shell/pi-observability.env}"
if [ -f "$env_file" ]; then
    set -a
    . "$env_file"
    set +a
fi
# shellcheck source=/dev/null
[ ! -f "$observability_env_file" ] || . "$observability_env_file"

if [ ! -x "$real_bin" ]; then
    printf '[bootstrap] WARN: Pi real binary not executable: %s\n' "$real_bin" >&2
    exit 127
fi

case "${1:-}" in
    install|remove|uninstall|update|list|config)
        exec "$real_bin" "$@"
        ;;
esac

if [ -n "$profile_name" ] && [ -z "${AAB_INFERENCE_GATEWAY_URL:-}" ]; then
    printf '[bootstrap] WARN: Pi profile %s requires AAB_INFERENCE_GATEWAY_URL.\n' "$profile_name" >&2
    exit 1
fi

[ -z "$profile_name" ] || export AAB_PI_PROFILE="$profile_name"
[ -n "${AAB_GH_TOKEN:-}" ] && export GH_TOKEN="$AAB_GH_TOKEN"
[ -n "${AAB_BREV_API_KEY:-}" ] && export BREV_API_KEY="$AAB_BREV_API_KEY"
[ -n "${AAB_BREV_ORG_ID:-}" ] && export BREV_ORG_ID="$AAB_BREV_ORG_ID"

has_provider=0
has_model=0
has_thinking=0
for arg in "$@"; do
    case "$arg" in
        --provider|--provider=*) has_provider=1 ;;
        --model|--model=*) has_model=1 ;;
        --thinking|--thinking=*) has_thinking=1 ;;
    esac
done

extra_args=()
if [ -n "$profile_name" ]; then
    [ "$has_provider" -eq 1 ] || extra_args+=(--provider aab-gateway)
    [ "$has_model" -eq 1 ] || extra_args+=(--model "$profile_model")
    [ "$has_thinking" -eq 1 ] || extra_args+=(--thinking "$profile_effort")
fi
exec "$real_bin" "${extra_args[@]}" "$@"
BASH
    } > "$tmp"
    chmod 755 "$tmp"
    mv -f "$tmp" "$launcher"
}

configure_pi_launchers() {
    local pi_bin="${HOME}/.local/bin/pi"
    local real_bin="${HOME}/.local/bin/pi-aab-real"
    local profiles line launcher
    local -A profile=() selected=()

    if [ ! -x "$real_bin" ]; then
        warn "Pi real binary not executable at ${real_bin}; skipping profile launchers."
        return
    fi
    profiles=$(_profile_list_for pi third-party)
    _remove_aab_profile_launchers \
        'Autonomous-agent-bootstrap Pi launcher' \
        "${HOME}/.local/bin/pi" \
        "${HOME}/.local/bin/pi-*"

    if [ -z "$(_model_profile_lines "$profiles")" ]; then
        _write_pi_launcher "" "" "" "$pi_bin"
        log "Wrote unconfigured Pi launcher with observability at ${pi_bin}."
        return
    fi

    require_inference_gateway "Pi profiles"
    while IFS= read -r line; do
        _parse_model_profile_line pi third-party "$line" profile
        launcher="${HOME}/.local/bin/pi-${profile[name]}"
        _write_pi_launcher "${profile[name]}" "${profile[model]}" "${profile[effort]}" "$launcher"
    done < <(_model_profile_lines "$profiles")

    resolve_model_profile pi selected
    _write_pi_launcher "${selected[name]}" "${selected[model]}" "${selected[effort]}" "$pi_bin"
    log "Wrote Pi profile launchers (selected=${selected[name]})."
}
