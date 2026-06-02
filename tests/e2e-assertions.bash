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
BREV_ONBOARDING="${HOME}/.brev/onboarding_step.json"
BASHRC="${HOME}/.bashrc"
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
assert d["effortLevel"] == "max", d
assert d["env"]["CLAUDE_CODE_EFFORT_LEVEL"] == "max", d
assert d["model"].startswith("claude-"), d
assert d["extraKnownMarketplaces"]["robobryce-agitentic"]["source"]["repo"] == "brycelelbach/agitentic", d
assert d["enabledPlugins"]["agitentic@robobryce-agitentic"] is True, d
allow = d["permissions"]["allow"]
for op in ("Edit", "Write", "Read"):
    assert f"{op}({home}/.claude/**)" in allow, (op, allow)
    assert f"{op}({home}/.claude.json)" in allow, (op, allow)
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

# 10. The binaries the bootstrap installed are on PATH (via ~/.local/bin).
export PATH="$HOME/.local/bin:$PATH"
command -v claude >/dev/null 2>&1 || fail "claude not on PATH after bootstrap."
[ -L "$HOME/.local/bin/claude" ] || fail "claude is not an AAB provider symlink."
[ "$(readlink "$HOME/.local/bin/claude")" = "claude-${expected_claude_provider}" ] \
    || fail "claude symlink does not target claude-${expected_claude_provider}."
[ -x "$HOME/.local/bin/claude-aab-real" ] || fail "Claude real binary link not installed."
[ -x "$HOME/.local/bin/claude-first-party" ] || fail "claude-first-party wrapper missing."
[ -x "$HOME/.local/bin/claude-third-party-anthropic" ] || fail "claude-third-party-anthropic wrapper missing."
[ -x "$HOME/.local/bin/claude-third-party-deepseek" ] || fail "claude-third-party-deepseek wrapper missing."
[ -x "$HOME/.local/bin/claude-third-party-nemotron" ] || fail "claude-third-party-nemotron wrapper missing."
pass "claude wrapper family installed and selected."
claude_plugins=$(claude plugin list 2>&1) || fail "claude plugin list failed."
case "$claude_plugins" in
    *"agitentic@robobryce-agitentic"*) ;;
    *) fail "Claude Code agitentic plugin not installed." ;;
esac
pass "Claude Code agent plugins installed."
command -v codex  >/dev/null 2>&1 || fail "codex not on PATH after bootstrap."
[ -L "$HOME/.local/bin/codex" ] || fail "codex is not an AAB provider symlink."
[ "$(readlink "$HOME/.local/bin/codex")" = "codex-${expected_codex_provider}" ] \
    || fail "codex symlink does not target codex-${expected_codex_provider}."
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

echo "All e2e assertions passed."
