# ---------------------------------------------------------------------------
# 5. Write ~/.claude/settings.json.
# ---------------------------------------------------------------------------
configure_claude_managed_settings() {
    local managed_dir
    managed_dir=$(dirname "$CLAUDE_MANAGED_SETTINGS_FILE")

    if [ -n "$SUDO" ] && ! sudo -n true 2>/dev/null; then
        warn "Writing $CLAUDE_MANAGED_SETTINGS_FILE needs sudo and passwordless sudo is not available; Claude interactive-tool deny policy is only in user settings."
        return
    fi

    local tmp
    tmp=$(mktemp)
    cat > "$tmp" <<'JSON'
{
  "permissions": {
    "deny": [
      "AskUserQuestion",
      "EnterPlanMode",
      "ExitPlanMode"
    ]
  }
}
JSON

    if ! $SUDO install -d -m 0755 "$managed_dir"; then
        warn "Could not create $managed_dir; Claude interactive-tool deny policy is only in user settings."
        rm -f "$tmp"
        return
    fi
    if ! $SUDO install -m 0644 "$tmp" "$CLAUDE_MANAGED_SETTINGS_FILE"; then
        warn "Could not write $CLAUDE_MANAGED_SETTINGS_FILE; Claude interactive-tool deny policy is only in user settings."
        rm -f "$tmp"
        return
    fi

    rm -f "$tmp"
    log "Wrote ${CLAUDE_MANAGED_SETTINGS_FILE}."
}

configure_claude_settings() {
    mkdir -p "${CLAUDE_DIR}"
    if [[ -f "${SETTINGS_FILE}" ]]; then
        local backup
        backup="${SETTINGS_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "${SETTINGS_FILE}" "${backup}"
        log "Backed up existing settings.json -> ${backup}."
    fi
    local model="${AAB_CLAUDE_CODE_FIRST_PARTY_MODEL:-$DEFAULT_CLAUDE_CODE_MODEL}"
    local effort="${AAB_CLAUDE_CODE_EFFORT:-$DEFAULT_CLAUDE_CODE_EFFORT}"
    # Belt-and-suspenders: bypassPermissions skips prompts for writes
    # under .claude/ already, but the explicit allow list also keeps
    # config / memory / agent / skill edits unprompted in 'default' or
    # 'acceptEdits' mode if a user toggles out of bypass mid-session.
    #
    # CLAUDE_CODE_ATTRIBUTION_HEADER=0 omits the attribution block (client
    # version and prompt fingerprint) from the start of the system prompt.
    # That block changes per request, so it invalidates the prompt-cache
    # prefix on every turn — disabling it restores cache hits when Claude is
    # routed through a third-party gateway, which is the common AAB setup.
    #
    # Network-resilience env for unattended runs on Bedrock / gateway
    # connections, where Claude Code's 5-minute streaming idle timeout is
    # active. API_FORCE_IDLE_TIMEOUT=0 disables that abort, which a long
    # Opus turn trips when it streams no bytes for 5 minutes (surfacing as
    # "The socket connection was closed unexpectedly"). API_TIMEOUT_MS
    # widens the per-request ceiling to 30 minutes, and
    # CLAUDE_CODE_MAX_RETRIES raises the backoff-retry count above its
    # default of 10. CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 removes the
    # print-mode (-p) ceiling on how long Claude Code waits for still-running
    # background tasks before exiting: by default a headless turn that has
    # spawned background work (e.g. long-lived sub-agents/workers) prints
    # "Background tasks still running after 600s; terminating" and exits after
    # ten minutes, killing that work. Unattended orchestrators that fan out to
    # background agents and then block for their completion must wait
    # indefinitely instead.
    #
    # CLAUDE_CODE_ENABLE_TELEMETRY=1 plus OTEL_LOGS_EXPORTER=console turns on
    # OpenTelemetry usage/event logging to the console for these unattended
    # runs. We deliberately leave OTEL_LOG_RAW_API_BODIES, OTEL_LOG_USER_PROMPTS,
    # OTEL_LOG_TOOL_DETAILS, and OTEL_LOG_TOOL_CONTENT unset — all default to
    # disabled — so prompts, tool arguments, and raw request/response bodies
    # stay out of the telemetry stream.
    cat > "${SETTINGS_FILE}" <<JSON
{
  "model": "${model}",
  "effortLevel": "${effort}",
  "permissions": {
    "defaultMode": "bypassPermissions",
    "allow": [
      "Edit(${HOME}/.claude/**)",
      "Write(${HOME}/.claude/**)",
      "Read(${HOME}/.claude/**)",
      "Edit(${HOME}/.claude.json)",
      "Write(${HOME}/.claude.json)",
      "Read(${HOME}/.claude.json)"
    ],
    "deny": [
      "AskUserQuestion",
      "EnterPlanMode",
      "ExitPlanMode"
    ]
  },
  "skipDangerousModePermissionPrompt": true,
  "env": {
    "CLAUDE_CODE_SANDBOXED": "1",
    "CLAUDE_CODE_EFFORT_LEVEL": "${effort}",
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
    "API_FORCE_IDLE_TIMEOUT": "0",
    "API_TIMEOUT_MS": "1800000",
    "CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS": "0",
    "CLAUDE_CODE_MAX_RETRIES": "15",
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_LOGS_EXPORTER": "console"
  }
}
JSON
    log "Wrote ${SETTINGS_FILE} (model=${model}, effort=${effort})."
    configure_claude_managed_settings
}

# Skip Claude Code's first-run theme prompt and pre-approve the
# first-party API-key fingerprint when one is set. Both gates live in
# ~/.claude.json, so preserve unrelated authentication and user fields.
skip_claude_onboarding() {
    command -v python3 >/dev/null 2>&1 || { log "ERROR: python3 required to edit ~/.claude.json."; exit 1; }
    python3 - "${CLAUDE_JSON}" "${AAB_CLAUDE_CODE_FIRST_PARTY_API_KEY:-}" <<'PY'
import json, os, shutil, sys, time
path = sys.argv[1]
api_key = sys.argv[2] if len(sys.argv) > 2 else ""
data = {}
if os.path.exists(path):
    backup = f"{path}.bak.{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(path, backup)
    print(f"[bootstrap] Backed up existing .claude.json -> {backup}.")
    try:
        with open(path) as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        data = {}
data["hasCompletedOnboarding"] = True
if api_key:
    fp = api_key[-20:]
    resp = data.setdefault("customApiKeyResponses", {})
    approved = resp.setdefault("approved", [])
    if fp not in approved:
        approved.append(fp)
    resp.setdefault("rejected", [])
    print(f"[bootstrap] Pre-approved AAB_CLAUDE_CODE_FIRST_PARTY_API_KEY fingerprint ...{fp}.")
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=2)
print(f"[bootstrap] Set hasCompletedOnboarding=true in {path}.")
PY
}

# Write Claude-specific shell defaults to a dedicated file. The generic
# ~/.bashrc integration sources every file in ~/.aab/shell instead of
# hard-coding harness settings in the shell integration module.
configure_claude_shell() {
    local effort="${AAB_CLAUDE_CODE_EFFORT:-$DEFAULT_CLAUDE_CODE_EFFORT}"
    mkdir -p "${AAB_SHELL_CONFIG_DIR}"
    {
        printf '%s\n' \
            '# Generated by autonomous-agent-bootstrap.' \
            'export CLAUDE_CODE_SANDBOXED=1' \
            'export DEBUG_SDK=1'
        printf 'export CLAUDE_CODE_EFFORT_LEVEL=%q\n' "$effort"
    } > "${CLAUDE_SHELL_CONFIG_FILE}"
    chmod 0644 "${CLAUDE_SHELL_CONFIG_FILE}"
    log "Wrote Claude shell configuration to ${CLAUDE_SHELL_CONFIG_FILE}."
}

configure_claude() {
    configure_claude_settings
    configure_claude_shell
    skip_claude_onboarding
}
