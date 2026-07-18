#!/usr/bin/env bash
#
# Post-bootstrap assertions. Assumes bootstrap.bash has just run under the
# current HOME. Exits non-zero on the first failure.

set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
CLAUDE_MANAGED_SETTINGS_FILE="/etc/claude-code/managed-settings.json"
CLAUDE_JSON="${HOME}/.claude.json"
CODEX_CONFIG="${HOME}/.codex/config.toml"
CODEX_MODEL_INSTRUCTIONS_FILE="${HOME}/.codex/codex-instructions.md"
CODEX_GATEWAY_MODEL_CATALOG="${HOME}/.aab/codex-gateway-model-catalog.json"
CODEX_AUTH="${HOME}/.codex/auth.json"
BREV_ONBOARDING="${HOME}/.brev/onboarding_step.json"
BASHRC="${HOME}/.bashrc"
PROFILE="${HOME}/.profile"
AAB_ENV_FILE="${HOME}/.aab/.env"
CLAUDE_SHELL_CONFIG_FILE="${HOME}/.aab/shell/claude.env"
GITHUB_SHELL_CONFIG_FILE="${HOME}/.aab/shell/github.env"
PI_MODELS_FILE="${HOME}/.pi/agent/models.json"
PI_SETTINGS_FILE="${HOME}/.pi/agent/settings.json"
PI_OBSERVABILITY_ENV_FILE="${HOME}/.aab/shell/pi-observability.env"
PI_OBSERVABILITY_PRELOAD="${HOME}/.pi/agent/npm/pi-observability-preload.cjs"
PI_LIST_TOOLS_EXTENSION="${HOME}/.pi/agent/extensions/list-tools.ts"
PI_FAST_MODE_EXTENSION="${HOME}/.pi/agent/extensions/fast-mode.ts"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${REPO_ROOT}/bootstrap.bash"
declare -A expected_claude_profile=() expected_codex_profile=() expected_pi_profile=()
resolve_model_profile claude expected_claude_profile
resolve_model_profile codex expected_codex_profile
resolve_model_profile pi expected_pi_profile

# 1. settings.json is well-formed and has the expected shape.
[ -f "$SETTINGS_FILE" ] || fail "settings.json not written."
python3 - "$SETTINGS_FILE" "$HOME" "${expected_claude_profile[model]}" "${expected_claude_profile[effort]}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
home = sys.argv[2]
expected_model = sys.argv[3]
expected_effort = sys.argv[4]
assert d["permissions"]["defaultMode"] == "bypassPermissions", d
assert d["skipDangerousModePermissionPrompt"] is True, d
assert d["env"]["CLAUDE_CODE_SANDBOXED"] == "1", d
assert d["env"]["CLAUDE_CODE_ATTRIBUTION_HEADER"] == "0", d
assert d["env"]["API_FORCE_IDLE_TIMEOUT"] == "0", d
assert d["env"]["API_TIMEOUT_MS"] == "1800000", d
assert d["env"]["CLAUDE_CODE_MAX_RETRIES"] == "15", d
assert d["env"]["CLAUDE_CODE_ENABLE_TELEMETRY"] == "1", d
assert d["env"]["OTEL_LOGS_EXPORTER"] == "console", d
for gate in ("OTEL_LOG_RAW_API_BODIES", "OTEL_LOG_USER_PROMPTS", "OTEL_LOG_TOOL_DETAILS", "OTEL_LOG_TOOL_CONTENT"):
    assert gate not in d["env"], gate
assert d["effortLevel"] == expected_effort, d
assert d["env"]["CLAUDE_CODE_EFFORT_LEVEL"] == expected_effort, d
assert d["model"] == expected_model, d
assert d["extraKnownMarketplaces"]["robobryce-agitentic"]["source"]["repo"] == "brycelelbach/agitentic", d
assert d["enabledPlugins"]["agitentic@robobryce-agitentic"] is True, d
allow = d["permissions"]["allow"]
for op in ("Edit", "Write", "Read"):
    assert f"{op}({home}/.claude/**)" in allow, (op, allow)
    assert f"{op}({home}/.claude.json)" in allow, (op, allow)
deny = d["permissions"]["deny"]
assert "AskUserQuestion" in deny, deny
assert "EnterPlanMode" in deny, deny
assert "ExitPlanMode" in deny, deny
PY
pass "settings.json written with unattended-mode defaults."

if [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
    [ -f "$CLAUDE_MANAGED_SETTINGS_FILE" ] || fail "Claude managed settings policy not written."
    python3 - "$CLAUDE_MANAGED_SETTINGS_FILE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
deny = d["permissions"]["deny"]
assert "AskUserQuestion" in deny, deny
assert "EnterPlanMode" in deny, deny
assert "ExitPlanMode" in deny, deny
assert "defaultMode" not in d["permissions"], d
assert "disableBypassPermissionsMode" not in d, d
PY
    pass "Claude managed settings deny policy written."
else
    pass "No passwordless sudo for managed settings; Claude policy write correctly skipped."
fi

# 2b. Codex model instructions are written and selected.
[ -f "$CODEX_MODEL_INSTRUCTIONS_FILE" ] || fail "Global Codex model instructions not written."
grep -Fq 'You are Codex, an agent based on GPT-5.' "$CODEX_MODEL_INSTRUCTIONS_FILE"     || fail "Global Codex model instructions are incomplete."
grep -Fq 'An event-driven monitoring call such as `wait_agent` is exempt' "$CODEX_MODEL_INSTRUCTIONS_FILE"     || fail "Global Codex model instructions do not exempt event-driven waits."
! grep -Fq 'Avoid performing blocking sleep or wait calls longer than 60 seconds' "$CODEX_MODEL_INSTRUCTIONS_FILE"     || fail "Global Codex model instructions still cap blocking waits at 60 seconds."
pass "Global Codex model instructions written without a blocking-wait cap."

# 2. config.toml is present and puts Codex in unattended yolo mode.
[ -f "$CODEX_CONFIG" ] || fail "Codex config.toml not written."
expected_codex_effort="${expected_codex_profile[effort]}"
expected_codex_service_tier="${AAB_CODEX_SERVICE_TIER:-priority}"
expected_codex_source="${expected_codex_profile[source]}"
expected_codex_name="${expected_codex_profile[name]}"
expected_codex_model="${expected_codex_profile[model]}"
expected_codex_base_url="${AAB_INFERENCE_GATEWAY_URL:-}"
expected_codex_agent_max_threads="${AAB_CODEX_AGENT_MAX_THREADS:-64}"
expected_codex_agent_max_threads_valid=1
case "${expected_codex_profile[fast]}" in
    true) expected_codex_service_tier="priority" ;;
    false) expected_codex_service_tier="default" ;;
    "")
        case "$expected_codex_service_tier" in
            priority|flex|default) ;;
            fast) expected_codex_service_tier="priority" ;;
            *) expected_codex_service_tier="priority" ;;
        esac
        ;;
esac
expected_codex_fast_mode=false
[ "$expected_codex_service_tier" != priority ] || expected_codex_fast_mode=true
grep -Fxq "model = \"${expected_codex_model}\"" "$CODEX_CONFIG" \
    || fail "Codex model is not ${expected_codex_model}."
grep -Fxq "model_instructions_file = \"${CODEX_MODEL_INSTRUCTIONS_FILE}\"" "$CODEX_CONFIG" \
    || fail "Codex model_instructions_file does not use the global prompt."
if [ "$expected_codex_source" = "third-party" ]; then
    grep -q '^model_provider = "aab-gateway"$' "$CODEX_CONFIG" \
        || fail "Codex model_provider is not aab-gateway."
    grep -q '^\[model_providers."aab-gateway"\]$' "$CODEX_CONFIG" \
        || fail "Codex inference-gateway provider table missing."
    grep -Fxq "base_url = \"${expected_codex_base_url}\"" "$CODEX_CONFIG" \
        || fail "Codex inference-gateway base URL is not ${expected_codex_base_url}."
    grep -q '^env_key = "AAB_INFERENCE_GATEWAY_API_KEY"$' "$CODEX_CONFIG" \
        || fail "Codex inference-gateway env key is not AAB_INFERENCE_GATEWAY_API_KEY."
    grep -q '^requires_openai_auth = false$' "$CODEX_CONFIG" \
        || fail "Codex inference-gateway provider unexpectedly requires OpenAI login."
    if [ "$expected_codex_service_tier" != default ]; then
        [ -f "$CODEX_GATEWAY_MODEL_CATALOG" ] \
            || fail "Codex gateway model catalog not written."
        python3 - "$CODEX_GATEWAY_MODEL_CATALOG" "$expected_codex_model" \
            "$expected_codex_service_tier" <<'PY'
import json
import sys

catalog_path, expected_model, expected_tier = sys.argv[1:]
with open(catalog_path, encoding="utf-8") as handle:
    models = json.load(handle)["models"]
model = next(candidate for candidate in models if candidate["slug"] == expected_model)
assert expected_tier in [tier["id"] for tier in model["service_tiers"]], model
if expected_tier == "priority":
    assert model["additional_speed_tiers"] == ["fast"], model
PY
    fi
fi
case "$expected_codex_agent_max_threads" in
    [1-9]*)
        case "$expected_codex_agent_max_threads" in
            *[!0-9]*) expected_codex_agent_max_threads_valid=0 ;;
        esac
        ;;
    *) expected_codex_agent_max_threads_valid=0 ;;
esac
if [ "$expected_codex_agent_max_threads_valid" -eq 0 ]; then
    expected_codex_agent_max_threads="64"
fi
grep -q '^approval_policy = "never"$' "$CODEX_CONFIG" \
    || fail "Codex approval_policy is not never."
grep -q '^sandbox_mode = "danger-full-access"$' "$CODEX_CONFIG" \
    || fail "Codex sandbox_mode is not danger-full-access."
grep -Fxq "model_reasoning_effort = \"${expected_codex_effort}\"" "$CODEX_CONFIG" \
    || fail "Codex reasoning effort is not ${expected_codex_effort}."
grep -Fxq 'model_reasoning_summary = "detailed"' "$CODEX_CONFIG" \
    || fail "Codex detailed reasoning summary is not enabled."
grep -Fxq 'hide_agent_reasoning = false' "$CODEX_CONFIG" \
    || fail "Codex agent reasoning is hidden."
grep -Fxq 'show_raw_agent_reasoning = true' "$CODEX_CONFIG" \
    || fail "Codex raw agent reasoning is not enabled."
grep -Fxq "service_tier = \"${expected_codex_service_tier}\"" "$CODEX_CONFIG" \
    || fail "Codex service tier is not ${expected_codex_service_tier}."
grep -Fxq "fast_mode = ${expected_codex_fast_mode}" "$CODEX_CONFIG" \
    || fail "Codex fast-mode feature is not ${expected_codex_fast_mode}."
grep -q '^check_for_update_on_startup = false$' "$CODEX_CONFIG" \
    || fail "Codex startup update check is not disabled."
grep -q '^\[otel\]$' "$CODEX_CONFIG" \
    || fail "Codex OpenTelemetry config section is missing."
grep -Fxq 'environment = "dev"' "$CODEX_CONFIG" \
    || fail "Codex OpenTelemetry environment is not dev."
grep -Fxq 'exporter = "none"' "$CODEX_CONFIG" \
    || fail "Codex OpenTelemetry log exporter is not disabled."
grep -Fxq 'trace_exporter = "none"' "$CODEX_CONFIG" \
    || fail "Codex OpenTelemetry trace exporter is not disabled."
grep -Fxq 'metrics_exporter = "none"' "$CODEX_CONFIG" \
    || fail "Codex OpenTelemetry metrics exporter is not disabled."
grep -Fxq 'log_user_prompt = false' "$CODEX_CONFIG" \
    || fail "Codex OpenTelemetry prompt logging is not disabled."
grep -q '^hide_full_access_warning = true$' "$CODEX_CONFIG" \
    || fail "Codex full-access warning acknowledgement not written."
grep -q '^inherit = "all"$' "$CODEX_CONFIG" \
    || fail "Codex shell env inheritance is not all."
grep -q '^ignore_default_excludes = true$' "$CODEX_CONFIG" \
    || fail "Codex shell env token inheritance is not enabled."
grep -Fxq "max_threads = ${expected_codex_agent_max_threads}" "$CODEX_CONFIG" \
    || fail "Codex agent max_threads is not ${expected_codex_agent_max_threads}."
grep -qF "[projects.\"$HOME\"]" "$CODEX_CONFIG" \
    || fail "Codex HOME project trust entry missing."
pass "Codex config.toml written with unattended yolo-mode defaults."

# 3. .claude.json has onboarding flag set.
[ -f "$CLAUDE_JSON" ] || fail ".claude.json not written."
python3 - "$CLAUDE_JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["hasCompletedOnboarding"] is True, d
PY
pass ".claude.json has hasCompletedOnboarding=true."

# 4. Brev onboarding file is valid JSON.
[ -f "$BREV_ONBOARDING" ] || fail "brev onboarding_step.json not written."
python3 -c "import json; json.load(open('$BREV_ONBOARDING'))"
pass "brev onboarding_step.json is valid JSON."

# 5. Managed bashrc block is present exactly once.
grep -q '# >>> autonomous-agent-bootstrap >>>' "$BASHRC" \
    || fail "bashrc begin marker missing."
grep -q '# <<< autonomous-agent-bootstrap <<<' "$BASHRC" \
    || fail "bashrc end marker missing."
begin_count=$(grep -c '^# >>> autonomous-agent-bootstrap >>>$' "$BASHRC")
end_count=$(grep -c '^# <<< autonomous-agent-bootstrap <<<$' "$BASHRC")
[ "$begin_count" -eq 1 ] || fail "Expected 1 bashrc begin marker, got $begin_count."
[ "$end_count" -eq 1 ]   || fail "Expected 1 bashrc end marker, got $end_count."
pass "bashrc managed block present exactly once."

# 6. AAB env file contains profile config and is private.
[ -f "$AAB_ENV_FILE" ] || fail "$AAB_ENV_FILE not written."
[ "$(stat -c '%a' "$AAB_ENV_FILE")" = "600" ] || fail "$AAB_ENV_FILE mode is not 600."
expected_claude_selector="${expected_claude_profile[source]}/${expected_claude_profile[name]}"
expected_codex_selector="${expected_codex_profile[source]}/${expected_codex_profile[name]}"
grep -Fq "export AAB_CLAUDE_DEFAULT_PROFILE=${expected_claude_selector}" "$AAB_ENV_FILE" \
    || fail "Claude default profile selector not written to $AAB_ENV_FILE."
grep -Fq "export AAB_CODEX_DEFAULT_PROFILE=${expected_codex_selector}" "$AAB_ENV_FILE" \
    || fail "Codex default profile selector not written to $AAB_ENV_FILE."
grep -Fq "export AAB_PI_DEFAULT_PROFILE=${expected_pi_profile[name]}" "$AAB_ENV_FILE" \
    || fail "Pi default profile selector not written to $AAB_ENV_FILE."
grep -q '^export AAB_ANTHROPIC_API_KEY=' "$AAB_ENV_FILE" \
    || fail "AAB_ANTHROPIC_API_KEY not written to $AAB_ENV_FILE."
grep -q '^export AAB_OPENAI_API_KEY=' "$AAB_ENV_FILE" \
    || fail "AAB_OPENAI_API_KEY not written to $AAB_ENV_FILE."
! grep -q '^export ANTHROPIC_API_KEY=' "$AAB_ENV_FILE" \
    || fail "Native ANTHROPIC_API_KEY should not be persisted in $AAB_ENV_FILE."
! grep -q '^export OPENAI_API_KEY=' "$AAB_ENV_FILE" \
    || fail "Native OPENAI_API_KEY should not be persisted in $AAB_ENV_FILE."
pass "AAB env file written with private profile config."

[ -f "$GITHUB_SHELL_CONFIG_FILE" ] || fail "GitHub shell config not written."
[ "$(stat -c '%a' "$GITHUB_SHELL_CONFIG_FILE")" = "600" ] \
    || fail "$GITHUB_SHELL_CONFIG_FILE mode is not 600."
if [ -n "${AAB_GH_TOKEN:-}" ]; then
    shell_gh_token=$(env HOME="$HOME" GH_TOKEN= bash --noprofile -ic 'printf %s "$GH_TOKEN"' 2>/dev/null)
    [ "$shell_gh_token" = "$AAB_GH_TOKEN" ] \
        || fail "GH_TOKEN does not match AAB_GH_TOKEN after sourcing ~/.bashrc."
fi
pass "Private GitHub shell config maps AAB_GH_TOKEN to GH_TOKEN."

# 7. bashrc contains no credential literals.
grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$BASHRC" \
    || fail "PATH export missing from bashrc managed block."
grep -q 'export PATH="$HOME/.local/aab-bin:$PATH"' "$BASHRC" \
    || fail "launcher-dir PATH export missing from bashrc managed block."
# aab-bin must be prepended after ~/.local/bin so it lands ahead of it.
bin_line=$(grep -n 'export PATH="$HOME/.local/bin:$PATH"' "$BASHRC" | head -1 | cut -d: -f1)
aab_line=$(grep -n 'export PATH="$HOME/.local/aab-bin:$PATH"' "$BASHRC" | head -1 | cut -d: -f1)
[ "$aab_line" -gt "$bin_line" ] \
    || fail "aab-bin PATH export must come after the ~/.local/bin export in bashrc."
! grep -q '^alias claude=' "$BASHRC" || fail "claude alias should not be written."
! grep -q '^alias codex=' "$BASHRC" || fail "codex alias should not be written."
! grep -q 'claude_code_switch_inference_provider' "$BASHRC" \
    || fail "provider switch function should not be written."
! grep -q '^export AAB_' "$BASHRC" || fail "AAB vars should not be exported from bashrc."
! grep -q '^export ANTHROPIC_' "$BASHRC" || fail "Anthropic runtime vars should not be exported from bashrc."
! grep -q '^export OPENAI_API_KEY=' "$BASHRC" || fail "OpenAI API key should not be exported from bashrc."
! grep -q '^export GH_TOKEN=' "$BASHRC" || fail "GitHub token should not be exported from bashrc."
pass "bashrc managed block keeps credentials out."

# 8. Claude owns its shell defaults; the generic bashrc block only sources
# AAB-managed shell fragments.
[ -f "$CLAUDE_SHELL_CONFIG_FILE" ] || fail "Claude shell config not written."
grep -q '^export DEBUG_SDK=1$' "$CLAUDE_SHELL_CONFIG_FILE" \
    || fail "DEBUG_SDK=1 missing from Claude shell config."
! grep -q '^export CLAUDE_CODE_EFFORT_LEVEL=' "$CLAUDE_SHELL_CONFIG_FILE" \
    || fail "Claude effort should remain profile-specific."
grep -Fq '"$HOME"/.aab/shell/*.env' "$BASHRC" \
    || fail "bashrc does not source AAB shell configuration."
pass "Claude shell defaults are encapsulated and sourced generically."

# 9. The bashrc block sources cleanly.
bash -n "$BASHRC" || fail "bashrc has syntax errors."
pass "bashrc parses cleanly."

# 9a. The dead-SSH-agent-socket guard clears a stale SSH_AUTH_SOCK. A forwarded
# socket left by a disconnected login (and re-injected by tmux into new panes)
# would otherwise make ssh-add and git signing probes fail or hang. The distro
# ~/.bashrc returns early for a non-interactive shell before it reaches the
# appended managed block, so extract the block between its markers and source
# that directly — the guard runs unconditionally once reached.
managed_block=$(mktemp)
awk '/^# >>> autonomous-agent-bootstrap >>>$/{f=1} f{print} /^# <<< autonomous-agent-bootstrap <<<$/{f=0}' \
    "$BASHRC" > "$managed_block"
guard_out=$(env HOME="$HOME" SSH_AUTH_SOCK="$HOME/nonexistent-agent.sock" \
    bash -c ". '$managed_block' >/dev/null 2>&1; printf %s \"\${SSH_AUTH_SOCK:-UNSET}\"")
rm -f "$managed_block"
[ "$guard_out" = "UNSET" ] \
    || fail "bashrc did not unset a dead SSH_AUTH_SOCK (got '$guard_out')."
pass "bashrc clears a dead SSH agent socket."

# 9b. ~/.profile carries the launcher-dir prepend once and parses cleanly.
grep -q 'export PATH="$HOME/.local/aab-bin:$PATH"' "$PROFILE" \
    || fail "launcher-dir PATH export missing from ~/.profile."
profile_begin=$(grep -c '^# >>> autonomous-agent-bootstrap >>>$' "$PROFILE")
[ "$profile_begin" -eq 1 ] || fail "Expected 1 ~/.profile managed block, got $profile_begin."
bash -n "$PROFILE" || fail "Login profile ~/.profile has syntax errors."
pass "Login profile keeps the launcher dir ahead of ~/.local/bin."

# 10. The launcher dir wins on PATH and selects the profile wrapper, while
#     ~/.local/bin/claude stays the native binary for the auto-updater.
export PATH="$HOME/.local/aab-bin:$HOME/.local/bin:$PATH"
command -v claude >/dev/null 2>&1 || fail "claude not on PATH after bootstrap."
claude_profile_launcher="$HOME/.local/bin/claude-${expected_claude_profile[source]}-${expected_claude_profile[name]}"
[ -L "$HOME/.local/aab-bin/claude" ] \
    || fail "Launcher entrypoint ~/.local/aab-bin/claude is not a symlink."
[ "$(readlink "$HOME/.local/aab-bin/claude")" = "$claude_profile_launcher" ] \
    || fail "Claude launcher entrypoint does not select ${expected_claude_profile[source]}/${expected_claude_profile[name]}."
# ~/.local/bin/claude is the native binary, not one of our wrappers, so the
# updater can repoint it freely; the wrappers exec it via claude-aab-real.
[ -x "$HOME/.local/bin/claude" ] || fail "Native claude binary missing from ~/.local/bin."
case "$(basename "$(readlink -f "$HOME/.local/bin/claude")")" in
    claude-first-party-*|claude-third-party-*)
        fail "Native ~/.local/bin/claude resolves to an AAB wrapper; the updater would self-exec." ;;
esac
[ "$(readlink "$HOME/.local/bin/claude-aab-real")" = "$HOME/.local/bin/claude" ] \
    || fail "claude-aab-real does not track ~/.local/bin/claude."
[ -x "$HOME/.local/bin/claude-aab-real" ] || fail "Claude real binary link not installed."
[ -x "$claude_profile_launcher" ] || fail "Claude selected profile launcher missing at ${claude_profile_launcher}."
# A login shell (sources ~/.profile, which re-prepends ~/.local/bin after
# ~/.bashrc) must still resolve `claude` to the launcher-dir wrapper.
login_claude=$(bash -lc 'command -v claude' 2>/dev/null) \
    || fail "claude not resolvable in a login shell."
[ "$login_claude" = "$HOME/.local/aab-bin/claude" ] \
    || fail "login shell resolves claude to ${login_claude}, not the launcher dir."
"$HOME/.local/bin/claude" --version 2>&1 | grep -Fq "$CLAUDE_CODE_VERSION" \
    || fail "Claude Code is not the pinned version $CLAUDE_CODE_VERSION."
pass "claude wrapper family installed and selected (launcher dir wins on PATH)."
claude_plugins=$(claude plugin list 2>&1) || fail "claude plugin list failed."
case "$claude_plugins" in
    *"agitentic@robobryce-agitentic"*) ;;
    *) fail "Claude Code agitentic plugin not installed." ;;
esac
pass "Claude Code agent plugins installed."
command -v codex  >/dev/null 2>&1 || fail "codex not on PATH after bootstrap."
codex_profile_launcher="$HOME/.local/bin/codex-${expected_codex_source}-${expected_codex_name}"
[ -L "$HOME/.local/bin/codex" ] || fail "codex is not a symlink."
[ "$(readlink "$HOME/.local/bin/codex")" = "$codex_profile_launcher" ] \
    || fail "Codex launcher entrypoint does not select ${expected_codex_source}/${expected_codex_name}."
[ -x "$codex_profile_launcher" ] || fail "Codex selected profile launcher missing at ${codex_profile_launcher}."
[ -x "$HOME/.local/bin/codex-aab-real" ] \
    || fail "Codex real binary link not installed."
"$HOME/.local/bin/codex-aab-real" --version 2>&1 | grep -Fq "$CODEX_VERSION" \
    || fail "Codex is not the pinned version $CODEX_VERSION."
pass "codex wrapper family installed and runnable."
codex_plugins=$(codex plugin list 2>&1) || fail "codex plugin list failed."
case "$codex_plugins" in
    *"agitentic@robobryce-agitentic"*) ;;
    *) fail "Codex agitentic plugin not installed." ;;
esac
pass "Codex agent plugins installed."
command -v pi >/dev/null 2>&1 || fail "pi not on PATH after bootstrap."
command -v node >/dev/null 2>&1 || fail "node not on PATH after bootstrap."
command -v npm >/dev/null 2>&1 || fail "npm not on PATH after bootstrap."
node --version 2>&1 | grep -Fxq "v${NODE_VERSION}" \
    || fail "Node.js is not the pinned version ${NODE_VERSION}."
[ -x "$HOME/.local/bin/pi-${expected_pi_profile[name]}" ] \
    || fail "Pi selected profile launcher missing."
[ ! -e "$HOME/.local/bin/pi-third-party-${expected_pi_profile[name]}" ] \
    || fail "Pi aliases must not include third-party."
[ -f "$PI_MODELS_FILE" ] || fail "Pi models.json not written."
python3 - "$PI_MODELS_FILE" "${expected_pi_profile[model]}" "${expected_pi_profile[fast]}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    providers = json.load(handle)["providers"]
provider = providers["aab-gateway"]
assert provider["api"] == "openai-completions", provider
expected_model, fast = sys.argv[2:]
if fast == "true":
    fast_provider = providers["aab-gateway-fast"]
    assert fast_provider["api"] == "aab-openai-responses-fast", fast_provider
    assert expected_model in [model["id"] for model in fast_provider["models"]], fast_provider
PY
"$HOME/.local/bin/pi-aab-real" --version 2>&1 | grep -Fq "$PI_VERSION" \
    || fail "Pi is not the pinned version $PI_VERSION."
[ -f "$PI_SETTINGS_FILE" ] || fail "Pi settings.json not written."
[ -f "$PI_OBSERVABILITY_ENV_FILE" ] || fail "Pi observability environment file not written."
[ -f "$PI_OBSERVABILITY_PRELOAD" ] || fail "Pi observability preload not written."
[ -f "$PI_LIST_TOOLS_EXTENSION" ] || fail "Pi list-tools extension not written."
[ -f "$PI_FAST_MODE_EXTENSION" ] || fail "Pi fast-mode extension not written."
[ -f "$HOME/.pi/agent/npm/node_modules/@opentelemetry/auto-instrumentations-node/build/src/register.js" ] \
    || fail "Pi OpenTelemetry auto-instrumentation is not installed."
python3 - "$PI_SETTINGS_FILE" "$PI_LIST_TOOLS_EXTENSION" "$PI_FAST_MODE_EXTENSION" \
    "$REPO_ROOT/pi_plugins.txt" "${expected_pi_profile[model]}" "${expected_pi_profile[fast]}" <<'PY'
import json
import sys

settings_path, list_tools_extension, fast_mode_extension, plugins_path, expected_model, fast = sys.argv[1:]
with open(settings_path, encoding="utf-8") as handle:
    data = json.load(handle)
expected_provider = "aab-gateway-fast" if fast == "true" else "aab-gateway"
assert data["defaultProvider"] == expected_provider, data
assert data["defaultModel"] == expected_model, data
assert data["defaultThinkingLevel"] == "high", data
assert data["defaultProjectTrust"] == "always", data
assert data["quietStartup"] is True, data
assert data["enableInstallTelemetry"] is True, data
assert data["enableAnalytics"] is True, data
assert data["warnings"] == {"anthropicExtraUsage": False}, data
assert data["retry"] == {
    "enabled": True,
    "maxRetries": 15,
    "provider": {"timeoutMs": 240000, "maxRetries": 0},
}, data
assert data["extensions"] == [list_tools_extension, fast_mode_extension], data
assert "trackingId" not in data and "lastChangelogVersion" not in data, data
expected_packages = []
with open(plugins_path, encoding="utf-8") as handle:
    for raw_line in handle:
        line = raw_line.split("#", 1)[0].strip()
        if line:
            expected_packages.append(line)
missing = [source for source in expected_packages if source not in data["packages"]]
assert not missing, (missing, data["packages"])
PY
grep -Fq 'export OTEL_TRACES_EXPORTER="${OTEL_TRACES_EXPORTER:-console}"' "$PI_OBSERVABILITY_ENV_FILE" \
    || fail "Pi trace exporter does not default to console."
grep -Fq 'export OTEL_METRICS_EXPORTER="${OTEL_METRICS_EXPORTER:-console}"' "$PI_OBSERVABILITY_ENV_FILE" \
    || fail "Pi metrics exporter does not default to console."
grep -Fq 'export OTEL_LOGS_EXPORTER="${OTEL_LOGS_EXPORTER:-console}"' "$PI_OBSERVABILITY_ENV_FILE" \
    || fail "Pi log exporter does not default to console."
grep -Fq 'export PI_TIMING="${PI_TIMING:-0}"' "$PI_OBSERVABILITY_ENV_FILE" \
    || fail "Pi startup timing diagnostics are not disabled by default."
grep -Fq 'PI_DEBUG_LOG_FILE' "$PI_OBSERVABILITY_PRELOAD" \
    || fail "Pi JSONL debug preload is incomplete."
grep -Fq 'pi.registerFlag("list-tools"' "$PI_LIST_TOOLS_EXTENSION" \
    || fail "Pi list-tools extension is incomplete."
grep -Fq 'serviceTier: "priority"' "$PI_FAST_MODE_EXTENSION" \
    || fail "Pi fast-mode extension is incomplete."
pi_models_output=$(pi --list-models "${expected_pi_profile[model]}" 2>&1) \
    || fail "Pi model listing failed with the configured extensions."
case "$pi_models_output" in
    *"${expected_pi_profile[model]}"*) ;;
    *) fail "Pi selected model is missing from the model listing." ;;
esac
mkdir -p "$HOME/.pi/agent/debug"
debug_logs_before=$(find "$HOME/.pi/agent/debug" -maxdepth 1 -type f -name 'pi-*.jsonl' 2>/dev/null | wc -l)
pi list >/dev/null 2>&1 || fail "Pi package list failed through the profile launcher."
debug_logs_after=$(find "$HOME/.pi/agent/debug" -maxdepth 1 -type f -name 'pi-*.jsonl' 2>/dev/null | wc -l)
[ "$debug_logs_after" -gt "$debug_logs_before" ] \
    || fail "Pi launcher did not create a JSONL debug log."
pass "Pi profile, fast mode, packages, audit extension, JSONL logging, and OpenTelemetry are configured."
if [ "$expected_codex_source" = "first-party" ] && [ -n "${AAB_OPENAI_API_KEY:-}" ]; then
    [ -f "$CODEX_AUTH" ] || fail "Codex auth.json not written."
    AAB_EXPECTED_CODEX_API_KEY="$AAB_OPENAI_API_KEY" \
        python3 - "$CODEX_AUTH" <<'PY'
import json
import os
import sys
with open(sys.argv[1]) as f:
    data = json.load(f)
if data.get("auth_mode") != "apikey":
    raise AssertionError("Codex auth_mode is not apikey.")
if data.get("OPENAI_API_KEY") != os.environ["AAB_EXPECTED_CODEX_API_KEY"]:
    raise AssertionError("Codex auth API key does not match AAB_OPENAI_API_KEY.")
PY
    codex_login_status=$(codex login status 2>&1)
    case "$codex_login_status" in
        *"Logged in using an API key"*) ;;
        *) fail "Codex login status does not report API-key auth." ;;
    esac
    pass "Codex first-party API-key auth configured."
fi
command -v brev   >/dev/null 2>&1 || fail "brev not on PATH after bootstrap."
brev --version 2>&1 | grep -Fq "Current Version: v${BREV_VERSION}" \
    || fail "Brev is not the pinned version $BREV_VERSION."
pass "brev binary installed and on PATH."
if [ -n "${AAB_BREV_API_KEY:-}" ] || [ -n "${AAB_BREV_ORG_ID:-}" ]; then
    [ -n "${AAB_BREV_API_KEY:-}" ] || fail "AAB_BREV_API_KEY missing while AAB_BREV_ORG_ID is set."
    [ -n "${AAB_BREV_ORG_ID:-}" ] || fail "AAB_BREV_ORG_ID missing while AAB_BREV_API_KEY is set."
    [ -f "$HOME/.brev/credentials.json" ] || fail "Brev credentials.json not written."
    brev ls >/dev/null 2>&1 || fail "brev ls failed with API-key auth."
    pass "Brev API-key auth configured."
fi
command -v gh     >/dev/null 2>&1 || fail "gh not on PATH after bootstrap."
gh --version 2>&1 | grep -Fq "gh version ${GH_VERSION} " \
    || fail "gh is not the pinned version $GH_VERSION."
pass "gh binary installed."

# 11. git identity was configured.
expected_git_author_name="${AAB_GIT_AUTHOR_NAME:-CI Bot}"
expected_git_author_email="${AAB_GIT_AUTHOR_EMAIL:-ci@example.com}"
[ "$(git config --global user.name)"  = "$expected_git_author_name" ] \
    || fail "git user.name not set."
[ "$(git config --global user.email)" = "$expected_git_author_email" ] \
    || fail "git user.email not set."
pass "git identity configured."

# 12. gh credential helper is registered for github.com.
gh_helper=$(git config --global --get 'credential.https://github.com.helper' || true)
[ "$gh_helper" = '!gh auth git-credential' ] \
    || fail "gh credential helper not registered (got: '$gh_helper')."
pass "gh registered as github.com credential helper."

# 12b. The global git-identity enforcement hook is installed and wired via
# core.hooksPath, with a symlink for each managed hook name.
GIT_HOOKS_DIR="${HOME}/.aab/git-hooks"
GIT_HOOK_DISPATCHER="${GIT_HOOKS_DIR}/aab-git-hook"
[ -x "$GIT_HOOK_DISPATCHER" ] || fail "git hook dispatcher not installed at $GIT_HOOK_DISPATCHER."
hooks_path=$(git config --global --get core.hooksPath || true)
[ "$hooks_path" = "$GIT_HOOKS_DIR" ] \
    || fail "core.hooksPath not set to $GIT_HOOKS_DIR (got: '$hooks_path')."
for hook in pre-commit commit-msg pre-push; do
    [ -L "$GIT_HOOKS_DIR/$hook" ] \
        || fail "git hook symlink $GIT_HOOKS_DIR/$hook missing."
    [ "$(readlink "$GIT_HOOKS_DIR/$hook")" = "aab-git-hook" ] \
        || fail "git hook $hook does not point at the dispatcher."
done
pass "git identity enforcement hook installed and wired via core.hooksPath."

# 12c. Functional check: a commit with the configured identity is allowed, and
# a commit that overrides the identity is rejected. Runs in a throwaway repo so
# the assertions exercise the real hook end-to-end.
hook_repo=$(mktemp -d)
git init -q "$hook_repo"
(
    cd "$hook_repo"
    echo enforce > f.txt
    git add f.txt
    git commit -q -m "matching identity" \
        || { echo "FAIL: commit with the configured identity was rejected." >&2; exit 1; }
    echo enforce-more > f.txt
    git add f.txt
    if git -c user.email="hacker@example.com" -c user.name="Hacker" \
        commit -q -m "overridden identity" 2>/dev/null; then
        echo "FAIL: commit overriding the global identity was NOT blocked." >&2
        exit 1
    fi
) || { rm -rf "$hook_repo"; exit 1; }
rm -rf "$hook_repo"
pass "git hook allows the configured identity and blocks overrides."

# 12c-secrets. gitleaks is installed at the pinned version and the pre-commit
# hook blocks a commit that stages a secret while allowing a clean one. Runs in
# a throwaway repo so the scan is exercised end-to-end through the real hook.
GITLEAKS_BIN="${HOME}/.local/bin/gitleaks"
[ -x "$GITLEAKS_BIN" ] || fail "gitleaks not installed at $GITLEAKS_BIN."
gl_ver=$("$GITLEAKS_BIN" version 2>/dev/null | tr -d 'v[:space:]')
[ "$gl_ver" = "$GITLEAKS_VERSION" ] \
    || fail "gitleaks at $GITLEAKS_BIN is version '$gl_ver', expected $GITLEAKS_VERSION."
secret_repo=$(mktemp -d)
git init -q "$secret_repo"
(
    cd "$secret_repo"
    # Clean content commits.
    echo "no secrets here" > ok.txt
    git add ok.txt
    git commit -q -m "clean" \
        || { echo "FAIL: clean commit was rejected by the secret scan." >&2; exit 1; }
    # A staged GitHub token is blocked. Build the literal at runtime so this
    # assertions file does not itself contain a scannable token.
    printf 'token=%s%s\n' "ghp_" "0000000000000000000000000000000000AB" > leak.txt
    git add leak.txt
    if git commit -q -m "leak" 2>/dev/null; then
        echo "FAIL: commit staging a GitHub token was NOT blocked." >&2
        exit 1
    fi
    # The documented escape hatch lets the same commit through.
    GITLEAKS_ALLOW=1 git commit -q -m "allowed leak" \
        || { echo "FAIL: GITLEAKS_ALLOW=1 did not bypass the secret scan." >&2; exit 1; }
) || { rm -rf "$secret_repo"; exit 1; }
rm -rf "$secret_repo"
pass "gitleaks installed; pre-commit secret scan blocks a staged token and honors GITLEAKS_ALLOW."

# 12d. The agent instruction files carry the clean agent rules, so Claude Code
# (~/.claude/CLAUDE.md) and Codex (~/.codex/AGENTS.md) both see them in every
# repository without AAB management comments in their prompts.
CLAUDE_MEMORY_FILE="${HOME}/.claude/CLAUDE.md"
CODEX_AGENTS_FILE="${HOME}/.codex/AGENTS.md"
for rule_file in "$CLAUDE_MEMORY_FILE" "$CODEX_AGENTS_FILE"; do
    [ -f "$rule_file" ] || fail "agent rule file $rule_file not written."
    ! grep -q '^# >>> autonomous-agent-bootstrap >>>$' "$rule_file" \
        || fail "agent rule file $rule_file contains an AAB begin marker."
    ! grep -q '^# <<< autonomous-agent-bootstrap <<<$' "$rule_file" \
        || fail "agent rule file $rule_file contains an AAB end marker."
    rules_count=$(grep -c '^## Operating principles$' "$rule_file")
    [ "$rules_count" -eq 1 ] \
        || fail "agent rule file $rule_file has $rules_count rule sets, expected 1."
    grep -q 'Operating principles' "$rule_file" \
        || fail "agent rule file $rule_file missing the operating-principles heading."
    grep -q 'Always use the configured git identity' "$rule_file" \
        || fail "agent rule file $rule_file missing the git-identity rule heading."
done
[ -f "$HOME/.aab/agent-rules.snapshot" ] \
    || fail "agent-rule ownership sidecar not written."
pass "agent instruction files carry clean agent rules exactly once."

# 13. /etc/environment does not carry AAB secrets or provider config.
ETC_ENV=/etc/environment
if [ ! -r "$ETC_ENV" ]; then
    fail "$ETC_ENV not readable."
fi
! grep -q '^# >>> autonomous-agent-bootstrap >>>$' "$ETC_ENV" \
    || fail "$ETC_ENV still contains an AAB managed block."
! grep -q '^AAB_' "$ETC_ENV" || fail "$ETC_ENV should not contain AAB vars."
! grep -q '^ANTHROPIC_' "$ETC_ENV" || fail "$ETC_ENV should not contain Anthropic runtime vars."
! grep -q '^OPENAI_API_KEY=' "$ETC_ENV" || fail "$ETC_ENV should not contain OpenAI API keys."
! grep -q '^GH_TOKEN=' "$ETC_ENV" || fail "$ETC_ENV should not contain GitHub tokens."
pass "$ETC_ENV has no AAB provider or credential state."

# 14. User lingering is enabled so the per-user systemd bus survives across
# sessions. The conditions here mirror configure_user_linger's own skip branches:
# a host with no systemd user manager (bare container) or a non-root user
# without passwordless sudo is a correct skip, not a failure.
linger_user="$(id -un)"
if ! command -v loginctl >/dev/null 2>&1 || ! loginctl show-user "$linger_user" >/dev/null 2>&1; then
    pass "No systemd user manager; user-linger setup correctly skipped."
elif [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
    pass "No passwordless sudo for non-root user; user-linger setup correctly skipped."
else
    linger="$(loginctl show-user "$linger_user" --property=Linger --value 2>/dev/null || true)"
    [ "$linger" = "yes" ] || fail "User lingering not enabled for $linger_user (Linger=$linger)."
    pass "User lingering enabled for $linger_user."
fi

# 15. The uv_tools.txt CLI tools are installed as isolated uv tools: each tool's
# executables are symlinked from ~/.local/bin into its environment under
# ~/.local/share/uv/tools/, and the managed PATH puts ~/.local/bin ahead of the
# system dirs. Asserted directly so the suite cannot pass while the uv tool
# install silently no-ops.
UV_TOOLS_DIR="${HOME}/.local/share/uv/tools"
LOCAL_BIN="${HOME}/.local/bin"

for tool in ruff pre-commit; do
    [ -x "$LOCAL_BIN/$tool" ] || fail "$tool not on ~/.local/bin after bootstrap ($LOCAL_BIN/$tool missing)."
    command -v "$tool" >/dev/null 2>&1 || fail "$tool not on PATH after bootstrap."
    # The ~/.local/bin entry is a uv tool symlink into the tool's own env.
    tool_real="$(readlink -f "$LOCAL_BIN/$tool")"
    case "$tool_real" in
        "$UV_TOOLS_DIR"/*) ;;
        *) fail "$tool at $LOCAL_BIN/$tool resolves to $tool_real, not a uv tool env under $UV_TOOLS_DIR." ;;
    esac
done
uv --version 2>&1 | grep -Fq "uv ${UV_VERSION} " \
    || fail "uv is not the pinned version $UV_VERSION."
ruff --version 2>&1 | grep -Fq "$RUFF_VERSION" \
    || fail "ruff is not the pinned version $RUFF_VERSION."
pre-commit --version 2>&1 | grep -Fq "$PRE_COMMIT_VERSION" \
    || fail "pre-commit is not the pinned version $PRE_COMMIT_VERSION."
pass "uv, ruff, and pre-commit installed at their pinned versions."

# The managed ~/.bashrc block puts ~/.local/bin (with the uv tool symlinks)
# ahead of the system dirs. The block sits after ~/.bashrc's interactive-only
# guard, so an interactive login shell — how a user's shell actually resolves
# commands — is what picks it up; assert with `bash -lic`.
grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$BASHRC" \
    || fail "$BASHRC managed block does not put ~/.local/bin on PATH."
resolved_ruff="$(bash -lic 'command -v ruff' 2>/dev/null || true)"
[ "$resolved_ruff" = "$LOCAL_BIN/ruff" ] \
    || fail "an interactive login shell resolves ruff to '${resolved_ruff:-nothing}', not $LOCAL_BIN/ruff."
pass "managed PATH resolves a bare ruff to the uv tool in ~/.local/bin."

# 16. The private autocuda package is installed as its own uv tool: the apt
# package list provides the Graphviz headers and compiler its pygraphviz
# dependency builds against, so the install succeeds and `autocuda install`
# runs after the harnesses are in place. The token-bearing fetch needs repo
# access, so a host without it degrades to a warning instead — guard the
# assertion on the binary being present rather than forcing a failure offline.
if [ -x "$LOCAL_BIN/autocuda" ]; then
    autocuda_real="$(readlink -f "$LOCAL_BIN/autocuda")"
    case "$autocuda_real" in
        "$UV_TOOLS_DIR"/*) ;;
        *) fail "autocuda at $LOCAL_BIN/autocuda resolves to $autocuda_real, not a uv tool env under $UV_TOOLS_DIR." ;;
    esac
    command -v autocuda >/dev/null 2>&1 || fail "autocuda on ~/.local/bin but not resolvable on PATH."
    autocuda --help >/dev/null 2>&1 || fail "autocuda is present but does not run."
    [ -L "$HOME/.local/share/autocuda/pi-package" ] \
        || fail "autocuda did not expose its bundled Pi package."
    autocuda_pi_packages=$(pi list 2>&1) || fail "Pi package list failed after autocuda installation."
    case "$autocuda_pi_packages" in
        *autocuda/pi-package*) ;;
        *) fail "autocuda Pi package is not registered." ;;
    esac
    pass "autocuda installed as a uv tool and registered with Pi."
else
    pass "autocuda not installed (private repo without access); best-effort install correctly degraded."
fi

# 17. lifeboat (the home-directory backup tool) is fetched straight to
# ~/.local/bin and marked executable. The fetch needs network access to the
# public lifeboat repo, so a host without it degrades to a warning — guard the
# assertion on the script being present rather than forcing a failure offline.
# When present, it must be on PATH, run, and actually produce a backup.
if [ -x "$LOCAL_BIN/lifeboat" ]; then
    command -v lifeboat >/dev/null 2>&1 || fail "lifeboat on ~/.local/bin but not resolvable on PATH."
    lifeboat --help >/dev/null 2>&1 || fail "lifeboat is present but does not run."
    lb_src="$(mktemp -d)"; lb_out="$(mktemp -d)"
    echo keep >"$lb_src/keep.cpp"
    mkdir -p "$lb_src/build"; echo drop >"$lb_src/build/x.o"
    SRC="$lb_src" OUT_DIR="$lb_out" lifeboat e2e host >/dev/null 2>&1 \
        || fail "lifeboat did not complete a backup run."
    lb_tgz="$(find "$lb_out" -maxdepth 1 -name 'e2e-host-*.tar.gz' | head -1)"
    [ -n "$lb_tgz" ] || fail "lifeboat did not produce an e2e-host-*.tar.gz archive."
    # Capture the listing once (no tar|grep pipe: grep -q can SIGPIPE tar, which
    # pipefail would surface as a spurious failure), then match it offline.
    lb_list="$(tar -tzf "$lb_tgz")"
    grep -q 'keep\.cpp' <<<"$lb_list" || fail "lifeboat archive is missing kept source."
    if grep -q '\.o$' <<<"$lb_list"; then
        fail "lifeboat archive wrongly included a build artifact."
    fi
    rm -rf "$lb_src" "$lb_out"
    pass "lifeboat installed at ~/.local/bin, on PATH, runnable, and backs up correctly."
else
    pass "lifeboat not installed (fetch unavailable offline); best-effort install correctly degraded."
fi

echo "All e2e assertions passed."
