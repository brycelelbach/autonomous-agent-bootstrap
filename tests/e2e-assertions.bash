#!/usr/bin/env bash
#
# Post-bootstrap assertions. Assumes bootstrap.bash has just run under the
# current HOME. Exits non-zero on the first failure.

set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
CLAUDE_JSON="${HOME}/.claude.json"
CODEX_CONFIG="${HOME}/.codex/config.toml"
CODEX_AUTH="${HOME}/.codex/auth.json"
HERMES_CONFIG="${HOME}/.hermes/config.yaml"
BREV_ONBOARDING="${HOME}/.brev/onboarding_step.json"
BASHRC="${HOME}/.bashrc"
PROFILE="${HOME}/.profile"
AAB_ENV_FILE="${HOME}/.aab/.env"

# 1. settings.json is well-formed and has the expected shape.
[ -f "$SETTINGS_FILE" ] || fail "settings.json not written."
python3 - "$SETTINGS_FILE" "$HOME" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
home = sys.argv[2]
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
assert d["effortLevel"] == "max", d
assert d["env"]["CLAUDE_CODE_EFFORT_LEVEL"] == "max", d
assert d["model"].startswith("claude-"), d
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

# 2. config.toml is present and puts Codex in unattended yolo mode.
[ -f "$CODEX_CONFIG" ] || fail "Codex config.toml not written."
expected_codex_effort="${AAB_CODEX_EFFORT:-xhigh}"
expected_codex_service_tier="${AAB_CODEX_SERVICE_TIER:-priority}"
expected_codex_provider="${AAB_CODEX_INFERENCE_PROVIDER:-first-party}"
case "$expected_codex_provider" in
    first-party|third-party-openai) ;;
    *) expected_codex_provider="first-party" ;;
esac
if [ "$expected_codex_provider" = "third-party-openai" ]; then
    expected_codex_model="${AAB_CODEX_THIRD_PARTY_OPENAI_MODEL:-openai/openai/gpt-5.5}"
    expected_codex_base_url="${AAB_CODEX_THIRD_PARTY_OPENAI_BASE_URL:-https://inference-api.nvidia.com/v1}"
else
    expected_codex_model="${AAB_CODEX_FIRST_PARTY_MODEL:-gpt-5.5}"
fi
expected_codex_agent_max_threads="${AAB_CODEX_AGENT_MAX_THREADS:-16}"
expected_codex_agent_max_threads_valid=1
case "$expected_codex_service_tier" in
    priority|flex|default) ;;
    fast) expected_codex_service_tier="priority" ;;
    *) expected_codex_service_tier="priority" ;;
esac
grep -Fxq "model = \"${expected_codex_model}\"" "$CODEX_CONFIG" \
    || fail "Codex model is not ${expected_codex_model}."
if [ "$expected_codex_provider" = "third-party-openai" ]; then
    grep -q '^model_provider = "third-party-openai"$' "$CODEX_CONFIG" \
        || fail "Codex model_provider is not third-party-openai."
    grep -q '^\[model_providers."third-party-openai"\]$' "$CODEX_CONFIG" \
        || fail "Codex third-party-openai provider table missing."
    grep -Fxq "base_url = \"${expected_codex_base_url}\"" "$CODEX_CONFIG" \
        || fail "Codex third-party-openai provider base URL is not ${expected_codex_base_url}."
    grep -q '^env_key = "AAB_CODEX_THIRD_PARTY_OPENAI_API_KEY"$' "$CODEX_CONFIG" \
        || fail "Codex third-party-openai provider env key is not AAB_CODEX_THIRD_PARTY_OPENAI_API_KEY."
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
    expected_codex_agent_max_threads="16"
fi
grep -q '^approval_policy = "never"$' "$CODEX_CONFIG" \
    || fail "Codex approval_policy is not never."
grep -q '^sandbox_mode = "danger-full-access"$' "$CODEX_CONFIG" \
    || fail "Codex sandbox_mode is not danger-full-access."
grep -Fxq "model_reasoning_effort = \"${expected_codex_effort}\"" "$CODEX_CONFIG" \
    || fail "Codex reasoning effort is not ${expected_codex_effort}."
grep -Fxq "service_tier = \"${expected_codex_service_tier}\"" "$CODEX_CONFIG" \
    || fail "Codex service tier is not ${expected_codex_service_tier}."
grep -q '^check_for_update_on_startup = false$' "$CODEX_CONFIG" \
    || fail "Codex startup update check is not disabled."
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

# 2b. Hermes config.yaml routes at the gateway and is permission-free.
# Parse the YAML rather than grep for literal lines: enabling plugins runs the
# Hermes CLI, which normalizes/migrates config.yaml (re-emitting keys unquoted
# and reordered), so only the parsed VALUES are stable. Use Hermes's own venv
# interpreter (it ships PyYAML); it lives under the FHS or the ~/.local layout.
[ -f "$HERMES_CONFIG" ] || fail "Hermes config.yaml not written."
[ "$(stat -c '%a' "$HERMES_CONFIG")" = "600" ] || fail "Hermes config.yaml mode is not 600."
hermes_py=""
for cand in \
    /usr/local/lib/hermes-agent/venv/bin/python \
    "$HOME/.hermes/hermes-agent/venv/bin/python" \
    /usr/local/lib/hermes-agent/venv/bin/python3 \
    "$HOME/.hermes/hermes-agent/venv/bin/python3"; do
    [ -x "$cand" ] && { hermes_py="$cand"; break; }
done
[ -n "$hermes_py" ] || hermes_py="$(command -v python3 || true)"
[ -n "$hermes_py" ] || fail "no python interpreter available to parse Hermes config.yaml."
# Mirror write_hermes_config's /v1 normalization on the configured base URL
# (no built-in default — the operator supplies the gateway).
expected_hermes_base_url="${AAB_HERMES_BASE_URL%/}"
case "$expected_hermes_base_url" in
    ''|*/v1) ;;
    *) expected_hermes_base_url="${expected_hermes_base_url}/v1" ;;
esac
AAB_EXPECTED_HERMES_BASE_URL="$expected_hermes_base_url" \
AAB_EXPECTED_HERMES_MODEL="${AAB_HERMES_MODEL:-}" \
    "$hermes_py" - "$HERMES_CONFIG" <<'PY' || fail "Hermes config.yaml does not have the expected gateway / permission-free / no-limit values."
import os, sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
def g(*ks):
    x = d
    for k in ks:
        if not isinstance(x, dict):
            return None
        x = x.get(k)
    return x
base = os.environ["AAB_EXPECTED_HERMES_BASE_URL"]
model = os.environ["AAB_EXPECTED_HERMES_MODEL"]
cps = d.get("custom_providers") or []
gw = next((p for p in cps if isinstance(p, dict) and p.get("name") == "aab-gateway"), None)
assert g("model", "provider") == "aab-gateway", g("model", "provider")
assert g("model", "default") == model, g("model", "default")
assert g("model", "base_url") == base, g("model", "base_url")
assert gw is not None, "aab-gateway custom_providers entry missing"
assert gw.get("base_url") == base and gw.get("key_env") == "AAB_HERMES_API_KEY", gw
# permission-free
assert str(g("approvals", "mode")).lower() == "off", g("approvals", "mode")
assert g("hooks_auto_accept") is True, g("hooks_auto_accept")
assert g("delegation", "subagent_auto_approve") is True, g("delegation", "subagent_auto_approve")
# reasoning
assert g("agent", "reasoning_effort") == "xhigh", g("agent", "reasoning_effort")
assert g("display", "show_reasoning") is True, g("display", "show_reasoning")
# run-duration limits removed
assert int(g("agent", "max_turns")) >= 999999, g("agent", "max_turns")
assert int(g("goals", "max_turns")) >= 999999, g("goals", "max_turns")
assert int(g("delegation", "max_iterations")) >= 999999, g("delegation", "max_iterations")
assert int(g("agent", "gateway_timeout")) == 0, g("agent", "gateway_timeout")
assert int(g("agent", "gateway_auto_continue_freshness")) == 0, g("agent", "gateway_auto_continue_freshness")
assert g("tool_loop_guardrails", "hard_stop_enabled") is False, g("tool_loop_guardrails", "hard_stop_enabled")
assert g("tool_loop_guardrails", "warnings_enabled") is False, g("tool_loop_guardrails", "warnings_enabled")
# per-op timeouts raised; concurrency matches Codex's cap (16)
assert int(g("delegation", "max_concurrent_children")) == 16, g("delegation", "max_concurrent_children")
assert int(g("terminal", "timeout")) == 600, g("terminal", "timeout")
assert int(g("delegation", "child_timeout_seconds")) >= 86400, g("delegation", "child_timeout_seconds")
# self-improvement (curator) disabled
assert g("curator", "enabled") is False, g("curator", "enabled")
# the gateway secret is referenced by env, never inlined
assert not gw.get("api_key"), "gateway entry must not inline an api_key"
PY
pass "Hermes config.yaml written with gateway routing + permission-free, no-limit defaults."

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

# 6. AAB env file contains provider config and is private.
[ -f "$AAB_ENV_FILE" ] || fail "$AAB_ENV_FILE not written."
[ "$(stat -c '%a' "$AAB_ENV_FILE")" = "600" ] || fail "$AAB_ENV_FILE mode is not 600."
expected_claude_provider="${AAB_CLAUDE_CODE_INFERENCE_PROVIDER:-first-party}"
case "$expected_claude_provider" in
    first-party|third-party-anthropic|third-party-deepseek|third-party-nemotron) ;;
    *) expected_claude_provider="first-party" ;;
esac
grep -q "^export AAB_CLAUDE_CODE_INFERENCE_PROVIDER=${expected_claude_provider}$" "$AAB_ENV_FILE" \
    || fail "Claude provider not written to $AAB_ENV_FILE."
grep -q "^export AAB_CODEX_INFERENCE_PROVIDER=${expected_codex_provider}$" "$AAB_ENV_FILE" \
    || fail "Codex provider not written to $AAB_ENV_FILE."
if [ -n "${AAB_CODEX_FIRST_PARTY_API_KEY:-}" ]; then
    grep -q '^export AAB_CODEX_FIRST_PARTY_API_KEY=' "$AAB_ENV_FILE" \
        || fail "AAB_CODEX_FIRST_PARTY_API_KEY not written to $AAB_ENV_FILE."
fi
! grep -q '^export OPENAI_API_KEY=' "$AAB_ENV_FILE" \
    || fail "OPENAI_API_KEY should be mapped by wrappers, not stored in $AAB_ENV_FILE."
! grep -q '^export ANTHROPIC_API_KEY=' "$AAB_ENV_FILE" \
    || fail "ANTHROPIC_API_KEY should be mapped by wrappers, not stored in $AAB_ENV_FILE."
pass "AAB env file written with private provider config."

# 7. bashrc exposes only PATH and non-secret unattended-mode defaults.
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

# 8. DEBUG_SDK=1 is exported (provider-agnostic) so Claude Code writes
# its debug logs to ~/.claude/debug/<uuid>.txt for every invocation.
grep -q 'export DEBUG_SDK=1' "$BASHRC" \
    || fail "DEBUG_SDK=1 export missing from bashrc managed block."
pass "DEBUG_SDK=1 exported (claude debug logging on)."

# 8b. CLAUDE_CODE_EFFORT_LEVEL mirrors AAB_CLAUDE_CODE_EFFORT, defaulting
# to max so non-interactive launches keep the same effort setting.
grep -q 'export CLAUDE_CODE_EFFORT_LEVEL="max"' "$BASHRC" \
    || fail "CLAUDE_CODE_EFFORT_LEVEL=max export missing from bashrc managed block."
pass "CLAUDE_CODE_EFFORT_LEVEL=max exported."

# 9. The bashrc block sources cleanly.
bash -n "$BASHRC" || fail "bashrc has syntax errors."
pass "bashrc parses cleanly."

# 9b. ~/.profile carries the launcher-dir prepend once and parses cleanly.
grep -q 'export PATH="$HOME/.local/aab-bin:$PATH"' "$PROFILE" \
    || fail "launcher-dir PATH export missing from ~/.profile."
profile_begin=$(grep -c '^# >>> autonomous-agent-bootstrap >>>$' "$PROFILE")
[ "$profile_begin" -eq 1 ] || fail "Expected 1 ~/.profile managed block, got $profile_begin."
bash -n "$PROFILE" || fail "Login profile ~/.profile has syntax errors."
pass "Login profile keeps the launcher dir ahead of ~/.local/bin."

# 10. The launcher dir wins on PATH and selects the provider wrapper, while
#     ~/.local/bin/claude stays the native binary for the auto-updater.
export PATH="$HOME/.local/aab-bin:$HOME/.local/bin:$PATH"
command -v claude >/dev/null 2>&1 || fail "claude not on PATH after bootstrap."
# The launcher entrypoint is a regular AAB launcher file, not a symlink to a
# provider wrapper.
[ ! -L "$HOME/.local/aab-bin/claude" ] || fail "Launcher entrypoint ~/.local/aab-bin/claude should be an AAB launcher file, not a symlink."
grep -q '^# Autonomous-agent-bootstrap Claude launcher\.$' "$HOME/.local/aab-bin/claude" \
    || fail "Launcher entrypoint ~/.local/aab-bin/claude is not an AAB launcher."
grep -q "^provider=${expected_claude_provider}$" "$HOME/.local/aab-bin/claude" \
    || fail "Launcher entrypoint does not select ${expected_claude_provider}."
# ~/.local/bin/claude is the native binary, not one of our wrappers, so the
# updater can repoint it freely; the wrappers exec it via claude-aab-real.
[ -x "$HOME/.local/bin/claude" ] || fail "Native claude binary missing from ~/.local/bin."
case "$(basename "$(readlink -f "$HOME/.local/bin/claude")")" in
    claude-first-party|claude-third-party-*)
        fail "Native ~/.local/bin/claude resolves to an AAB wrapper; the updater would self-exec." ;;
esac
[ "$(readlink "$HOME/.local/bin/claude-aab-real")" = "$HOME/.local/bin/claude" ] \
    || fail "claude-aab-real does not track ~/.local/bin/claude."
[ -x "$HOME/.local/bin/claude-aab-real" ] || fail "Claude real binary link not installed."
[ -x "$HOME/.local/bin/claude-first-party" ] || fail "claude-first-party wrapper missing."
[ -x "$HOME/.local/bin/claude-third-party-anthropic" ] || fail "claude-third-party-anthropic wrapper missing."
[ -x "$HOME/.local/bin/claude-third-party-deepseek" ] || fail "claude-third-party-deepseek wrapper missing."
[ -x "$HOME/.local/bin/claude-third-party-nemotron" ] || fail "claude-third-party-nemotron wrapper missing."
# A login shell (sources ~/.profile, which re-prepends ~/.local/bin after
# ~/.bashrc) must still resolve `claude` to the launcher-dir wrapper.
login_claude=$(bash -lc 'command -v claude' 2>/dev/null) \
    || fail "claude not resolvable in a login shell."
[ "$login_claude" = "$HOME/.local/aab-bin/claude" ] \
    || fail "login shell resolves claude to ${login_claude}, not the launcher dir."
pass "claude wrapper family installed and selected (launcher dir wins on PATH)."
claude_plugins=$(claude plugin list 2>&1) || fail "claude plugin list failed."
case "$claude_plugins" in
    *"agitentic@robobryce-agitentic"*) ;;
    *) fail "Claude Code agitentic plugin not installed." ;;
esac
pass "Claude Code agent plugins installed."
command -v codex  >/dev/null 2>&1 || fail "codex not on PATH after bootstrap."
[ ! -L "$HOME/.local/bin/codex" ] || fail "codex should be an AAB launcher file, not a symlink."
grep -q '^# Autonomous-agent-bootstrap Codex launcher\.$' "$HOME/.local/bin/codex" \
    || fail "codex is not an AAB launcher."
grep -q "^provider=${expected_codex_provider}$" "$HOME/.local/bin/codex" \
    || fail "codex launcher does not select ${expected_codex_provider}."
[ -x "$HOME/.local/bin/codex-first-party" ] || fail "codex-first-party wrapper missing."
[ -x "$HOME/.local/bin/codex-third-party-openai" ] || fail "codex-third-party-openai wrapper missing."
[ -x "$HOME/.local/bin/codex-aab-real" ] \
    || fail "Codex real binary link not installed."
codex --version >/dev/null 2>&1 || fail "codex binary does not run."
pass "codex wrapper family installed and runnable."
codex_plugins=$(codex plugin list 2>&1) || fail "codex plugin list failed."
case "$codex_plugins" in
    *"agitentic@robobryce-agitentic"*) ;;
    *) fail "Codex agitentic plugin not installed." ;;
esac
pass "Codex agent plugins installed."
command -v hermes >/dev/null 2>&1 || fail "hermes not on PATH after bootstrap."
[ -L "$HOME/.local/bin/hermes" ] || fail "hermes is not an AAB provider symlink."
[ "$(readlink "$HOME/.local/bin/hermes")" = "hermes-gateway" ] \
    || fail "hermes symlink does not target hermes-gateway."
[ -x "$HOME/.local/bin/hermes-gateway" ] || fail "hermes-gateway wrapper missing."
[ -x "$HOME/.local/bin/hermes-aab-real" ] || fail "Hermes real binary link not installed."
pass "hermes wrapper installed and selected."
# The agitentic marketplace plugin is materialized into Hermes's plugin dir
# (its source tree carries no root plugin.yaml, so the bootstrap synthesizes
# one) and enabled.
[ -f "$HOME/.hermes/plugins/agitentic/plugin.yaml" ] \
    || fail "Hermes agitentic plugin.yaml not synthesized."
hermes_plugins=$(hermes plugins list --plain 2>&1) || fail "hermes plugins list failed."
case "$hermes_plugins" in
    *"agitentic"*) ;;
    *) fail "Hermes agitentic plugin not installed." ;;
esac
pass "Hermes agent plugins installed."
if [ "$expected_codex_provider" = "first-party" ] && [ -n "${AAB_CODEX_FIRST_PARTY_API_KEY:-}" ]; then
    [ -f "$CODEX_AUTH" ] || fail "Codex auth.json not written."
    AAB_EXPECTED_CODEX_API_KEY="$AAB_CODEX_FIRST_PARTY_API_KEY" \
        python3 - "$CODEX_AUTH" <<'PY'
import json
import os
import sys
with open(sys.argv[1]) as f:
    data = json.load(f)
if data.get("auth_mode") != "apikey":
    raise AssertionError("Codex auth_mode is not apikey.")
if data.get("OPENAI_API_KEY") != os.environ["AAB_EXPECTED_CODEX_API_KEY"]:
    raise AssertionError("Codex auth API key does not match AAB_CODEX_FIRST_PARTY_API_KEY.")
PY
    codex_login_status=$(codex login status 2>&1)
    case "$codex_login_status" in
        *"Logged in using an API key"*) ;;
        *) fail "Codex login status does not report API-key auth." ;;
    esac
    pass "Codex first-party API-key auth configured."
fi
command -v brev   >/dev/null 2>&1 || fail "brev not on PATH after bootstrap."
pass "brev binary installed and on PATH."
if [ -n "${AAB_BREV_API_KEY:-}" ] || [ -n "${AAB_BREV_ORG_ID:-}" ]; then
    [ -n "${AAB_BREV_API_KEY:-}" ] || fail "AAB_BREV_API_KEY missing while AAB_BREV_ORG_ID is set."
    [ -n "${AAB_BREV_ORG_ID:-}" ] || fail "AAB_BREV_ORG_ID missing while AAB_BREV_API_KEY is set."
    [ -f "$HOME/.brev/credentials.json" ] || fail "Brev credentials.json not written."
    brev ls >/dev/null 2>&1 || fail "brev ls failed with API-key auth."
    pass "Brev API-key auth configured."
fi
command -v gh     >/dev/null 2>&1 || fail "gh not on PATH after bootstrap."
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

# 12d. The agent instruction files carry the git-identity rule in a managed
# block, so Claude Code (~/.claude/CLAUDE.md) and Codex (~/.codex/AGENTS.md)
# both see it in every repository.
CLAUDE_MEMORY_FILE="${HOME}/.claude/CLAUDE.md"
CODEX_AGENTS_FILE="${HOME}/.codex/AGENTS.md"
for rule_file in "$CLAUDE_MEMORY_FILE" "$CODEX_AGENTS_FILE"; do
    [ -f "$rule_file" ] || fail "agent rule file $rule_file not written."
    grep -q '# >>> autonomous-agent-bootstrap >>>' "$rule_file" \
        || fail "agent rule file $rule_file missing managed-block begin marker."
    begin_count=$(grep -c '^# >>> autonomous-agent-bootstrap >>>$' "$rule_file")
    [ "$begin_count" -eq 1 ] \
        || fail "agent rule file $rule_file has $begin_count managed blocks, expected 1."
    grep -q 'Always use the configured git identity' "$rule_file" \
        || fail "agent rule file $rule_file missing the git-identity rule heading."
done
pass "agent instruction files carry the git-identity rule exactly once."

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
# sessions. The conditions here mirror enable_user_linger's own skip branches:
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

echo "All e2e assertions passed."
