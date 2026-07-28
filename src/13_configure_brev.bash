# ---------------------------------------------------------------------------
# Configure Brev API-key auth and skip interactive onboarding.
#
# `brev login --api-key ... --org-id ...` writes Brev's credentials cache,
# which makes future Brev commands non-interactive. The API key and org ID
# are a pair: if the caller provides one without the other, fail immediately
# instead of leaving Brev on an interactive auth path.
# ---------------------------------------------------------------------------
_configure_brev_auth() {
    local api_key="${AAB_BREV_API_KEY:-}"
    local org_id="${AAB_BREV_ORG_ID:-}"

    if [ -z "$api_key" ] && [ -z "$org_id" ]; then
        return
    fi
    if [ -z "$api_key" ] || [ -z "$org_id" ]; then
        warn "AAB_BREV_API_KEY and AAB_BREV_ORG_ID must both be set to configure Brev API-key auth."
        exit 1
    fi

    local brev_bin=""
    if command -v brev >/dev/null 2>&1; then
        brev_bin=$(command -v brev)
    elif [ -x "${HOME}/.local/bin/brev" ]; then
        brev_bin="${HOME}/.local/bin/brev"
    else
        warn "brev binary not on PATH; cannot configure AAB_BREV_API_KEY auth."
        exit 1
    fi

    if ! "$brev_bin" login --api-key "$api_key" --org-id "$org_id" >/dev/null 2>&1; then
        warn "brev login --api-key failed; cannot configure Brev API-key auth."
        exit 1
    fi

    log "Configured Brev API-key auth from AAB_BREV_API_KEY and AAB_BREV_ORG_ID."
}

_write_brev_onboarding() {
    mkdir -p "${BREV_DIR}"
    if [[ -f "${BREV_ONBOARDING}" ]]; then
        local backup
        backup="${BREV_ONBOARDING}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "${BREV_ONBOARDING}" "${backup}"
        log "Backed up existing onboarding.json -> ${backup}."
    fi
    cat > "${BREV_ONBOARDING}" <<'JSON'
{"step": 1, "hasRunBrevShell": true, "hasRunBrevOpen": true}
JSON
    log "Wrote ${BREV_ONBOARDING}."
}

configure_brev() {
    _configure_brev_auth
    _write_brev_onboarding
}
