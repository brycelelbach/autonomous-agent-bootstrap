# ---------------------------------------------------------------------------
# Parse, validate, and resolve environment-defined model profiles.
# ---------------------------------------------------------------------------
_model_profile_lines() {
    local profiles="$1" line
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] && continue
        case "$line" in
            \#*) continue ;;
        esac
        printf '%s\n' "$line"
    done <<< "$profiles"
}

_profile_list_for() {
    local harness="$1" source="$2"
    case "${harness}/${source}" in
        claude/first-party)
            printf '%s' "${AAB_CLAUDE_FIRST_PARTY_PROFILES-$DEFAULT_CLAUDE_FIRST_PARTY_PROFILES}"
            ;;
        claude/third-party)
            printf '%s' "${AAB_CLAUDE_THIRD_PARTY_PROFILES-$DEFAULT_CLAUDE_THIRD_PARTY_PROFILES}"
            ;;
        codex/first-party)
            printf '%s' "${AAB_CODEX_FIRST_PARTY_PROFILES-$DEFAULT_CODEX_FIRST_PARTY_PROFILES}"
            ;;
        codex/third-party)
            printf '%s' "${AAB_CODEX_THIRD_PARTY_PROFILES-$DEFAULT_CODEX_THIRD_PARTY_PROFILES}"
            ;;
        pi/third-party)
            printf '%s' "${AAB_PI_PROFILES-$DEFAULT_PI_PROFILES}"
            ;;
        *)
            warn "Unknown model-profile group '${harness}/${source}'."
            return 1
            ;;
    esac
}

_parse_model_profile_line() {
    local harness="$1" source="$2" line="$3" result_name="$4"
    local -n result="$result_name"
    local -a fields
    local field key value
    local -A seen_fields=()

    read -r -a fields <<< "$line"
    if [ "${#fields[@]}" -eq 0 ]; then
        warn "Empty ${harness} ${source} model profile."
        return 1
    fi

    result=()
    result[harness]="$harness"
    result[source]="$source"
    result[name]="${fields[0]}"
    result[model]="${fields[0]}"
    result[context]=""
    result["max_tokens"]=""
    result[subagent]=""
    result[thinking]=""
    case "$harness" in
        claude)
            result[effort]="$DEFAULT_CLAUDE_CODE_EFFORT"
            ;;
        codex)
            result[effort]="$DEFAULT_CODEX_REASONING_EFFORT"
            ;;
        pi)
            result[effort]="$DEFAULT_PI_EFFORT"
            ;;
        *)
            warn "Unknown model-profile harness '${harness}'."
            return 1
            ;;
    esac

    if [[ ! "${result[name]}" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
        warn "Invalid ${harness} ${source} profile name '${result[name]}'; use lowercase letters, digits, dots, and hyphens."
        return 1
    fi

    for field in "${fields[@]:1}"; do
        case "$field" in
            \#*) break ;;
        esac
        if [[ "$field" != *=* ]]; then
            warn "Invalid field '${field}' in ${harness} ${source} profile '${result[name]}'; expected key=value."
            return 1
        fi
        key="${field%%=*}"
        value="${field#*=}"
        if [ -z "$value" ]; then
            warn "Empty field '${key}' in ${harness} ${source} profile '${result[name]}'."
            return 1
        fi
        if [ -n "${seen_fields[$key]:-}" ]; then
            warn "Duplicate field '${key}' in ${harness} ${source} profile '${result[name]}'."
            return 1
        fi
        seen_fields[$key]=1

        case "${harness}/${key}" in
            claude/model|claude/effort|claude/context|claude/subagent|claude/haiku|claude/sonnet|claude/opus|codex/model|codex/effort|pi/model|pi/effort|pi/context|pi/max_tokens)
                result[$key]="$value"
                ;;
            *)
                warn "Unknown field '${key}' in ${harness} ${source} profile '${result[name]}'."
                return 1
                ;;
        esac
    done

    case "${result[context]}" in
        "") ;;
        *[!0-9]*|0)
            warn "context='${result[context]}' in ${harness} ${source} profile '${result[name]}' is not a positive integer."
            return 1
            ;;
    esac
    case "${result["max_tokens"]}" in
        "") ;;
        *[!0-9]*|0)
            warn "max_tokens='${result["max_tokens"]}' in ${harness} ${source} profile '${result[name]}' is not a positive integer."
            return 1
            ;;
    esac

    if [ "$harness" = "claude" ]; then
        result[haiku]="${result[haiku]:-${result[model]}}"
        result[sonnet]="${result[sonnet]:-${result[model]}}"
        result[opus]="${result[opus]:-${result[model]}}"
        result[subagent]="${result[subagent]:-${result[model]}}"
    elif [ "$harness" = "pi" ]; then
        case "${result[effort]}" in
            off|minimal|low|medium|high|xhigh)
                result[thinking]="${result[effort]}"
                ;;
            *)
                result[thinking]="xhigh"
                ;;
        esac
    fi
}

_validate_model_profile_list() {
    local harness="$1" source="$2" profiles="$3" line
    local -A profile=() seen_names=()
    while IFS= read -r line; do
        _parse_model_profile_line "$harness" "$source" "$line" profile || return 1
        if [ -n "${seen_names[${profile[name]}]:-}" ]; then
            warn "Duplicate ${harness} ${source} profile '${profile[name]}'."
            return 1
        fi
        seen_names[${profile[name]}]=1
    done < <(_model_profile_lines "$profiles")
}

validate_model_profiles() {
    local harness source profiles
    for harness in claude codex; do
        for source in first-party third-party; do
            profiles=$(_profile_list_for "$harness" "$source")
            _validate_model_profile_list "$harness" "$source" "$profiles"
        done
    done
    profiles=$(_profile_list_for pi third-party)
    _validate_model_profile_list pi third-party "$profiles"
}

_find_model_profile() {
    local harness="$1" source="$2" name="$3" result_name="$4"
    local profiles line
    local -A candidate=()
    profiles=$(_profile_list_for "$harness" "$source")
    while IFS= read -r line; do
        _parse_model_profile_line "$harness" "$source" "$line" candidate || return 1
        if [ "${candidate[name]}" = "$name" ]; then
            _parse_model_profile_line "$harness" "$source" "$line" "$result_name"
            return
        fi
    done < <(_model_profile_lines "$profiles")
    return 1
}

_first_model_profile() {
    local harness="$1" source="$2" result_name="$3"
    local profiles line
    profiles=$(_profile_list_for "$harness" "$source")
    while IFS= read -r line; do
        _parse_model_profile_line "$harness" "$source" "$line" "$result_name"
        return
    done < <(_model_profile_lines "$profiles")
    return 1
}

resolve_model_profile() {
    local harness="$1" result_name="$2"
    local selection explicit_selection=0 source name

    case "$harness" in
        claude)
            if [ "${AAB_CLAUDE_DEFAULT_PROFILE+x}" = x ]; then
                selection="$AAB_CLAUDE_DEFAULT_PROFILE"
                explicit_selection=1
            else
                selection="$DEFAULT_CLAUDE_PROFILE"
            fi
            ;;
        codex)
            if [ "${AAB_CODEX_DEFAULT_PROFILE+x}" = x ]; then
                selection="$AAB_CODEX_DEFAULT_PROFILE"
                explicit_selection=1
            else
                selection="$DEFAULT_CODEX_PROFILE"
            fi
            ;;
        pi)
            if [ "${AAB_PI_DEFAULT_PROFILE+x}" = x ]; then
                selection="$AAB_PI_DEFAULT_PROFILE"
                explicit_selection=1
            else
                selection="$DEFAULT_PI_PROFILE"
            fi
            if [ -n "$selection" ] && _find_model_profile pi third-party "$selection" "$result_name"; then
                return 0
            fi
            if [ "$explicit_selection" -eq 1 ]; then
                warn "AAB_PI_DEFAULT_PROFILE='${selection}' does not name a configured Pi profile."
                return 1
            fi
            _first_model_profile pi third-party "$result_name"
            return
            ;;
        *)
            warn "Unknown model-profile harness '${harness}'."
            return 1
            ;;
    esac

    if [[ "$selection" == */* ]]; then
        source="${selection%%/*}"
        name="${selection#*/}"
    else
        source=""
        name="$selection"
    fi
    case "$source" in
        first-party|third-party) ;;
        *)
            warn "AAB_${harness^^}_DEFAULT_PROFILE='${selection}' must use first-party/<profile> or third-party/<profile>."
            return 1
            ;;
    esac

    if _find_model_profile "$harness" "$source" "$name" "$result_name"; then
        return 0
    fi
    if [ "$explicit_selection" -eq 1 ]; then
        warn "AAB_${harness^^}_DEFAULT_PROFILE='${selection}' does not name a configured ${harness} profile."
        return 1
    fi
    if _first_model_profile "$harness" first-party "$result_name"; then
        return 0
    fi
    _first_model_profile "$harness" third-party "$result_name"
}

require_inference_gateway() {
    local profile_label="$1"
    if [ -z "${AAB_INFERENCE_GATEWAY_URL:-}" ]; then
        warn "${profile_label} requires AAB_INFERENCE_GATEWAY_URL."
        return 1
    fi
}
