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
unset ANTHROPIC_API_KEY

case "$profile_source" in
    first-party)
        [ -n "${AAB_ANTHROPIC_API_KEY:-}" ] && export ANTHROPIC_API_KEY="$AAB_ANTHROPIC_API_KEY"
        ;;
    third-party)
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
    launcher="${HOME}/.local/bin/claude-${selected[source]}-${selected[name]}"
    ln -sfn "$launcher" "${launcher_dir}/claude"
    log "Wrote Claude profile launchers (selected=${selected[source]}/${selected[name]})."
}

_write_codex_gateway_model_catalog() {
    local profiles line records tmp
    local -A profile=()
    profiles=$(_profile_list_for codex third-party)
    if [ -z "$(_model_profile_lines "$profiles")" ]; then
        rm -f "$CODEX_GATEWAY_MODEL_CATALOG"
        return
    fi

    mkdir -p "$AAB_DIR"
    records=$(mktemp)
    tmp=$(mktemp "${CODEX_GATEWAY_MODEL_CATALOG}.tmp.XXXXXX")
    while IFS= read -r line; do
        _parse_model_profile_line codex third-party "$line" profile
        printf '%s\t%s\t%s\n' \
            "${profile[name]}" \
            "${profile[model]}" \
            "$(_codex_profile_service_tier "${profile[fast]}")" >> "$records"
    done < <(_model_profile_lines "$profiles")

    python3 - "$records" "$tmp" <<'PY'
import csv
import json
import sys

records_path, output_path = sys.argv[1:]
models = {}
with open(records_path, encoding="utf-8", newline="") as handle:
    for name, model_id, service_tier in csv.reader(handle, delimiter="\t"):
        model = models.setdefault(
            model_id,
            {
                "name": name,
                "service_tiers": [],
            },
        )
        if service_tier != "default" and service_tier not in model["service_tiers"]:
            model["service_tiers"].append(service_tier)

tier_details = {
    "priority": {
        "id": "priority",
        "name": "Fast",
        "description": "Priority processing",
    },
    "flex": {
        "id": "flex",
        "name": "Flex",
        "description": "Flexible processing",
    },
}
payload = {"models": []}
for model_id, model in models.items():
    service_tiers = [tier_details[tier] for tier in model["service_tiers"]]
    payload["models"].append(
        {
            "slug": model_id,
            "display_name": model["name"],
            "description": None,
            "default_reasoning_level": None,
            "supported_reasoning_levels": [],
            "shell_type": "default",
            "visibility": "none",
            "supported_in_api": True,
            "priority": 99,
            "additional_speed_tiers": ["fast"] if "priority" in model["service_tiers"] else [],
            "service_tiers": service_tiers,
            "default_service_tier": None,
            "availability_nux": None,
            "upgrade": None,
            "base_instructions": "",
            "model_messages": None,
            "include_skills_usage_instructions": False,
            "supports_reasoning_summaries": False,
            "default_reasoning_summary": "auto",
            "support_verbosity": False,
            "default_verbosity": None,
            "apply_patch_tool_type": None,
            "web_search_tool_type": "text",
            "truncation_policy": {"mode": "bytes", "limit": 10000},
            "supports_parallel_tool_calls": False,
            "supports_image_detail_original": False,
            "context_window": 272000,
            "max_context_window": 272000,
            "experimental_supported_tools": [],
            "input_modalities": ["text", "image"],
            "supports_search_tool": False,
            "use_responses_lite": False,
        }
    )

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
PY
    rm -f "$records"
    chmod 600 "$tmp"
    mv -f "$tmp" "$CODEX_GATEWAY_MODEL_CATALOG"
}

CODEX_SESSION_HOOK_TRUST_CONTENT=$(cat <<'AAB_CODEX_SESSION_HOOK_TRUST_EOF'
__AAB_CODEX_SESSION_HOOK_TRUST__
AAB_CODEX_SESSION_HOOK_TRUST_EOF
)

_write_codex_session_hook_trust() {
    local tmp
    mkdir -p "$(dirname "$CODEX_SESSION_HOOK_TRUST")"
    tmp=$(mktemp "${CODEX_SESSION_HOOK_TRUST}.tmp.XXXXXX")
    printf '%s\n' "$CODEX_SESSION_HOOK_TRUST_CONTENT" > "$tmp"
    chmod 700 "$tmp"
    mv -f "$tmp" "$CODEX_SESSION_HOOK_TRUST"
}

_write_codex_launcher() {
    local source="$1" name="$2" model="$3" effort="$4" service_tier="$5"
    local fast_mode="$6" model_catalog="$7" launcher="$8" tmp
    tmp=$(mktemp "${launcher}.tmp.XXXXXX")
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' '# Autonomous-agent-bootstrap Codex launcher.'
        printf 'profile_source=%q\n' "$source"
        printf 'profile_name=%q\n' "$name"
        printf 'profile_model=%q\n' "$model"
        printf 'profile_effort=%q\n' "$effort"
        printf 'profile_service_tier=%q\n' "$service_tier"
        printf 'profile_fast_mode=%q\n' "$fast_mode"
        printf 'profile_model_catalog=%q\n' "$model_catalog"
        cat <<'BASH'
set -euo pipefail

real_bin="${AAB_CODEX_REAL_BIN:-$HOME/.local/bin/codex-aab-real}"
hook_trust_helper="${AAB_CODEX_HOOK_TRUST_HELPER:-$HOME/.aab/codex-session-hook-trust.py}"
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

[ -n "${AAB_GH_TOKEN:-}" ] && export GH_TOKEN="$AAB_GH_TOKEN"
[ -n "${AAB_BREV_API_KEY:-}" ] && export BREV_API_KEY="$AAB_BREV_API_KEY"
[ -n "${AAB_BREV_ORG_ID:-}" ] && export BREV_ORG_ID="$AAB_BREV_ORG_ID"

model_escaped=$(toml_escape "$profile_model")
effort_escaped=$(toml_escape "$profile_effort")
service_tier_escaped=$(toml_escape "$profile_service_tier")
config_args=(
    -c "model=\"${model_escaped}\""
    -c "model_reasoning_effort=\"${effort_escaped}\""
    -c "service_tier=\"${service_tier_escaped}\""
    -c "features.fast_mode=${profile_fast_mode}"
)
if [ -n "$profile_model_catalog" ]; then
    model_catalog_escaped=$(toml_escape "$profile_model_catalog")
    config_args+=(-c "model_catalog_json=\"${model_catalog_escaped}\"")
fi
unset OPENAI_API_KEY
case "$profile_source" in
    first-party)
        [ -n "${AAB_OPENAI_API_KEY:-}" ] && export OPENAI_API_KEY="$AAB_OPENAI_API_KEY"
        config_args+=(-c 'model_provider="openai"')
        ;;
    third-party)
        if [ -z "${AAB_INFERENCE_GATEWAY_URL:-}" ]; then
            printf '[bootstrap] WARN: Codex profile %s requires AAB_INFERENCE_GATEWAY_URL.\n' "$profile_name" >&2
            exit 1
        fi
        base_url_escaped=$(toml_escape "$AAB_INFERENCE_GATEWAY_URL")
        provider_override="model_providers={\"aab-gateway\"={name=\"AAB Inference Gateway\",base_url=\"${base_url_escaped}\",env_key=\"AAB_INFERENCE_GATEWAY_API_KEY\",requires_openai_auth=false,wire_api=\"responses\",request_max_retries=4,stream_max_retries=5,stream_idle_timeout_ms=300000}}"
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
    hook_state=""
    if [ -x "$hook_trust_helper" ]; then
        hook_state=$("$hook_trust_helper" \
            "$real_bin" "$cwd" "${config_args[@]}" -c "$trust_override" 2>/dev/null) || hook_state=""
    fi
    case "$hook_state" in
        \{*\}) extra_args=(-c "hooks.state=${hook_state}" "${extra_args[@]}") ;;
        *) extra_args=(--dangerously-bypass-hook-trust "${extra_args[@]}") ;;
    esac
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
    local source profiles line launcher service_tier fast_mode model_catalog
    local -A profile=() selected=()

    _prepare_launcher_real_binary "codex" "$codex_bin" "$real_bin" "Autonomous-agent-bootstrap Codex launcher"
    _write_codex_session_hook_trust
    _remove_aab_profile_launchers \
        'Autonomous-agent-bootstrap Codex launcher' \
        "${HOME}/.local/bin/codex-first-party*" \
        "${HOME}/.local/bin/codex-third-party-*"
    _write_codex_gateway_model_catalog

    for source in first-party third-party; do
        profiles=$(_profile_list_for codex "$source")
        while IFS= read -r line; do
            _parse_model_profile_line codex "$source" "$line" profile
            if [ "$source" = "third-party" ]; then
                require_inference_gateway "Codex profile '${profile[name]}'"
            fi
            service_tier=$(_codex_profile_service_tier "${profile[fast]}")
            fast_mode=false
            [ "$service_tier" != priority ] || fast_mode=true
            model_catalog=""
            if [ "$source" = "third-party" ] && [ "$service_tier" != default ]; then
                model_catalog="$CODEX_GATEWAY_MODEL_CATALOG"
            fi
            launcher="${HOME}/.local/bin/codex-${source}-${profile[name]}"
            _write_codex_launcher \
                "$source" "${profile[name]}" "${profile[model]}" "${profile[effort]}" \
                "$service_tier" "$fast_mode" "$model_catalog" "$launcher"
        done < <(_model_profile_lines "$profiles")
    done

    resolve_model_profile codex selected
    launcher="${HOME}/.local/bin/codex-${selected[source]}-${selected[name]}"
    ln -sfn "$launcher" "$codex_bin"
    log "Wrote Codex profile launchers (selected=${selected[source]}/${selected[name]})."
}

_write_pi_launcher() {
    local name="$1" provider="$2" model="$3" thinking="$4" launcher="$5" tmp
    tmp=$(mktemp "${launcher}.tmp.XXXXXX")
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' '# Autonomous-agent-bootstrap Pi launcher.'
        printf 'profile_name=%q\n' "$name"
        printf 'profile_provider=%q\n' "$provider"
        printf 'profile_model=%q\n' "$model"
        printf 'profile_thinking=%q\n' "$thinking"
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
    [ "$has_provider" -eq 1 ] || extra_args+=(--provider "$profile_provider")
    [ "$has_model" -eq 1 ] || extra_args+=(--model "$profile_model")
    [ "$has_thinking" -eq 1 ] || extra_args+=(--thinking "$profile_thinking")
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
    local profiles line launcher provider
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
        _write_pi_launcher "" "" "" "" "$pi_bin"
        log "Wrote unconfigured Pi launcher with observability at ${pi_bin}."
        return
    fi

    require_inference_gateway "Pi profiles"
    while IFS= read -r line; do
        _parse_model_profile_line pi third-party "$line" profile
        if [ "${profile[fast]}" = true ]; then
            provider="aab-gateway-fast"
        else
            provider="aab-gateway"
        fi
        launcher="${HOME}/.local/bin/pi-${profile[name]}"
        _write_pi_launcher "${profile[name]}" "$provider" "${profile[model]}" "${profile[thinking]}" "$launcher"
    done < <(_model_profile_lines "$profiles")

    resolve_model_profile pi selected
    if [ "${selected[fast]}" = true ]; then
        provider="aab-gateway-fast"
    else
        provider="aab-gateway"
    fi
    _write_pi_launcher "${selected[name]}" "$provider" "${selected[model]}" "${selected[thinking]}" "$pi_bin"
    log "Wrote Pi profile launchers (selected=${selected[name]})."
}
