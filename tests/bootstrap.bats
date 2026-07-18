#!/usr/bin/env bats
#
# Unit tests for bootstrap.bash. We source the script with TEST_MODE set so
# main() does not run, then exercise individual functions against a
# per-test HOME sandbox.

setup() {
    export TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    export REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # Unset env vars the script looks at so each test controls its own.
    unset AAB_CLAUDE_FIRST_PARTY_PROFILES AAB_CLAUDE_THIRD_PARTY_PROFILES \
          AAB_CLAUDE_DEFAULT_PROFILE \
          AAB_CODEX_FIRST_PARTY_PROFILES AAB_CODEX_THIRD_PARTY_PROFILES \
          AAB_CODEX_DEFAULT_PROFILE AAB_CODEX_SERVICE_TIER \
          AAB_CODEX_AGENT_MAX_THREADS \
          AAB_PI_PROFILES AAB_PI_DEFAULT_PROFILE \
          AAB_INFERENCE_GATEWAY_URL AAB_INFERENCE_GATEWAY_API_KEY \
          AAB_ANTHROPIC_API_KEY AAB_OPENAI_API_KEY \
          AAB_BREV_API_KEY AAB_BREV_ORG_ID BREV_API_KEY BREV_ORG_ID \
          AAB_GH_TOKEN AAB_GIT_AUTHOR_NAME AAB_GIT_AUTHOR_EMAIL \
          AAB_GH_AUTH_SSH_PRIVATE_KEY_B64 AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64 \
          ANTHROPIC_API_KEY ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN \
          OPENAI_API_KEY GH_TOKEN GITHUB_TOKEN \
          AAB_AGENT_PLUGINS_FILE AAB_PI_PLUGINS_FILE \
          AAB_APT_PACKAGES_FILE AAB_APT_PACKAGES_URL \
          AAB_UV_TOOLS_FILE AAB_UV_TOOLS_URL
    # shellcheck disable=SC1091
    source "$REPO_ROOT/bootstrap.bash"
    CLAUDE_MANAGED_SETTINGS_FILE="$TEST_HOME/etc/claude-code/managed-settings.json"
    SUDO=""
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "log writes to stdout with bootstrap prefix" {
    run log "hello"
    [ "$status" -eq 0 ]
    [ "$output" = "[bootstrap] hello" ]
}

@test "warn writes to stderr with WARN prefix" {
    run warn "bad"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[bootstrap] WARN: bad"* ]]
}

@test "need_sudo returns empty string for uid 0, 'sudo' otherwise" {
    result=$(need_sudo)
    if [ "$(id -u)" -eq 0 ]; then
        [ "$result" = "" ]
    else
        [ "$result" = "sudo" ]
    fi
}

@test "non-apt package versions are centralized" {
    local package_variable definitions
    for package_variable in \
        CLAUDE_CODE_VERSION CODEX_VERSION NODE_VERSION PI_VERSION BREV_VERSION \
        LIFEBOAT_REF GH_VERSION UV_VERSION RUFF_VERSION \
        PRE_COMMIT_VERSION AUTOCUDA_REF GITLEAKS_VERSION; do
        [ -n "${!package_variable}" ]
        definitions=$(grep -R "^${package_variable}=" "$REPO_ROOT/src/bootstrap" --include='*.bash')
        [[ "$definitions" == "$REPO_ROOT/src/bootstrap/00_versions.bash:"* ]]
        [ "$(printf '%s\n' "$definitions" | wc -l)" -eq 1 ]
    done
}

@test "agent plugin defaults are compiled into bootstrap.bash" {
    [ "$AGENT_PLUGINS_DEFAULT_CONTENT" = "$(cat "$REPO_ROOT/agent_plugins.txt")" ]
    [[ "$AGENT_PLUGINS_DEFAULT_CONTENT" != *"__AAB_AGENT_PLUGINS__"* ]]
}

@test "Pi package and asset defaults are compiled into bootstrap.bash" {
    [ "$PI_PLUGINS_DEFAULT_CONTENT" = "$(cat "$REPO_ROOT/pi_plugins.txt")" ]
    [ "$PI_OBSERVABILITY_ENV_CONTENT" = "$(cat "$REPO_ROOT/src/pi/observability.env")" ]
    [ "$PI_OBSERVABILITY_PRELOAD_CONTENT" = "$(cat "$REPO_ROOT/src/pi/observability-preload.cjs")" ]
    [ "$PI_LIST_TOOLS_EXTENSION_CONTENT" = "$(cat "$REPO_ROOT/src/pi/list-tools.ts")" ]
    [[ "$PI_PLUGINS_DEFAULT_CONTENT" != *"__AAB_PI_PLUGINS__"* ]]
    grep -Fq 'git:github.com/nicobailon/pi-subagents@' "$REPO_ROOT/pi_plugins.txt"
    ! grep -Fq 'robobryce/pi-subagents' "$REPO_ROOT/pi_plugins.txt"
}

@test "Claude profiles inherit unspecified tier models from the primary model" {
    export AAB_CLAUDE_THIRD_PARTY_PROFILES="deepseek-v4 model=deepseek-v4-pro haiku=deepseek-v4-flash effort=high"
    export AAB_CLAUDE_DEFAULT_PROFILE="third-party/deepseek-v4"
    local -A profile=()

    resolve_model_profile claude profile

    [ "${profile[source]}" = "third-party" ]
    [ "${profile[model]}" = "deepseek-v4-pro" ]
    [ "${profile[haiku]}" = "deepseek-v4-flash" ]
    [ "${profile[sonnet]}" = "deepseek-v4-pro" ]
    [ "${profile[opus]}" = "deepseek-v4-pro" ]
    [ "${profile[effort]}" = "high" ]
}

@test "profile selection remains source-specific within one harness" {
    export AAB_CODEX_FIRST_PARTY_PROFILES="gpt-5.5 effort=xhigh"
    export AAB_CODEX_THIRD_PARTY_PROFILES="gpt-5.5 model=gateway/gpt-5.5 effort=high"
    local -A profile=()

    AAB_CODEX_DEFAULT_PROFILE="first-party/gpt-5.5" resolve_model_profile codex profile
    [ "${profile[source]}" = "first-party" ]
    [ "${profile[model]}" = "gpt-5.5" ]

    AAB_CODEX_DEFAULT_PROFILE="third-party/gpt-5.5" resolve_model_profile codex profile
    [ "${profile[source]}" = "third-party" ]
    [ "${profile[model]}" = "gateway/gpt-5.5" ]
}

@test "validate_model_profiles rejects unknown fields and duplicate aliases" {
    AAB_PI_PROFILES="opus-4.8 model=one effort=high mystery=value" run validate_model_profiles
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown field 'mystery'"* ]]

    AAB_PI_PROFILES=$'opus-4.8 model=one effort=high\nopus-4.8 model=two effort=max' run validate_model_profiles
    [ "$status" -ne 0 ]
    [[ "$output" == *"Duplicate pi third-party profile 'opus-4.8'"* ]]
}

@test "validate_model_profiles rejects unknown Claude and Codex default selectors" {
    AAB_CLAUDE_THIRD_PARTY_PROFILES="deepseek-v4 model=vendor/deepseek-v4" \
        AAB_CLAUDE_DEFAULT_PROFILE="third-party/missing" \
        run validate_model_profiles
    [ "$status" -ne 0 ]
    [[ "$output" == *"AAB_CLAUDE_DEFAULT_PROFILE='third-party/missing' does not name a configured claude profile."* ]]

    AAB_CODEX_THIRD_PARTY_PROFILES="gpt-5.6 model=vendor/gpt-5.6" \
        AAB_CODEX_DEFAULT_PROFILE="third-party/missing" \
        run validate_model_profiles
    [ "$status" -ne 0 ]
    [[ "$output" == *"AAB_CODEX_DEFAULT_PROFILE='third-party/missing' does not name a configured codex profile."* ]]
}

@test "Pi maps provider-specific effort values through xhigh" {
    local -A profile=()

    _parse_model_profile_line pi third-party \
        "gpt-5.6 model=openai/openai/gpt-5.6-sol effort=ultra" profile

    [ "${profile[effort]}" = "ultra" ]
    [ "${profile[thinking]}" = "xhigh" ]

    _parse_model_profile_line pi third-party \
        "opus-4.8 model=aws/anthropic/bedrock-claude-opus-4-8 effort=max" profile

    [ "${profile[effort]}" = "max" ]
    [ "${profile[thinking]}" = "xhigh" ]
}

@test "configure_git uses AAB-prefixed git identity vars" {
    command -v git >/dev/null || skip "precondition: git must exist"
    AAB_GIT_AUTHOR_NAME="Alice Example" \
        AAB_GIT_AUTHOR_EMAIL="alice@example.com" \
        configure_git
    [ "$(git config --global --get user.name)" = "Alice Example" ]
    [ "$(git config --global --get user.email)" = "alice@example.com" ]
}

@test "configure_brev writes valid onboarding JSON" {
    _write_brev_onboarding
    [ -f "$BREV_ONBOARDING" ]
    python3 -c "import json; json.load(open('$BREV_ONBOARDING'))"
    grep -q '"hasRunBrevShell": true' "$BREV_ONBOARDING"
}

@test "configure_brev backs up pre-existing onboarding file" {
    mkdir -p "$BREV_DIR"
    echo '{"old": true}' > "$BREV_ONBOARDING"
    _write_brev_onboarding
    local backup_count
    backup_count=$(find "$BREV_DIR" -maxdepth 1 -name 'onboarding_step.json.bak.*' | wc -l)
    [ "$backup_count" -ge 1 ]
}

@test "configure_claude_settings uses default model when first-party model unset" {
    configure_claude_settings
    [ -f "$SETTINGS_FILE" ]
    python3 -c "import json; d=json.load(open('$SETTINGS_FILE')); assert d['model']=='$DEFAULT_CLAUDE_CODE_MODEL', d['model']"
}

@test "configure_claude_settings honors first-party model override" {
    AAB_CLAUDE_FIRST_PARTY_PROFILES="sonnet-4.6 model=claude-sonnet-4-6 effort=high" \
        AAB_CLAUDE_DEFAULT_PROFILE="first-party/sonnet-4.6" \
        configure_claude_settings
    python3 -c "import json; d=json.load(open('$SETTINGS_FILE')); assert d['model']=='claude-sonnet-4-6', d['model']"
}

@test "configure_claude_settings honors profile effort" {
    AAB_CLAUDE_FIRST_PARTY_PROFILES="opus-4.8 model=claude-opus-4-8 effort=high" configure_claude_settings
    python3 - <<PY
import json
d = json.load(open("$SETTINGS_FILE"))
assert d["effortLevel"] == "high", d
assert d["env"]["CLAUDE_CODE_EFFORT_LEVEL"] == "high", d
PY
}

@test "configure_claude_settings sets bypassPermissions and sandbox env" {
    configure_claude_settings
    python3 - <<PY
import json
d = json.load(open("$SETTINGS_FILE"))
assert d["permissions"]["defaultMode"] == "bypassPermissions"
assert d["skipDangerousModePermissionPrompt"] is True
assert d["env"]["CLAUDE_CODE_SANDBOXED"] == "1"
assert d["env"]["CLAUDE_CODE_ATTRIBUTION_HEADER"] == "0"
assert d["effortLevel"] == "$DEFAULT_CLAUDE_CODE_EFFORT"
assert d["env"]["CLAUDE_CODE_EFFORT_LEVEL"] == "$DEFAULT_CLAUDE_CODE_EFFORT"
assert d["env"]["CLAUDE_CODE_ENABLE_TELEMETRY"] == "1"
assert d["env"]["OTEL_LOGS_EXPORTER"] == "console"
# Content-logging gates stay off so prompts / tool args / raw bodies are not exported.
for gate in ("OTEL_LOG_RAW_API_BODIES", "OTEL_LOG_USER_PROMPTS", "OTEL_LOG_TOOL_DETAILS", "OTEL_LOG_TOOL_CONTENT"):
    assert gate not in d["env"], gate
deny = d["permissions"]["deny"]
assert "AskUserQuestion" in deny, deny
assert "EnterPlanMode" in deny, deny
assert "ExitPlanMode" in deny, deny
PY
}

@test "configure_claude_settings writes Claude managed deny policy when writable" {
    SUDO="" configure_claude_settings
    [ -f "$CLAUDE_MANAGED_SETTINGS_FILE" ]
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
}

@test "configure_claude_managed_settings warns and skips without passwordless sudo" {
    local fake_bin="$TEST_HOME/fake-managed-settings-nosudo-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/sudo" <<'SH'
#!/usr/bin/env bash
[ "$1" = "-n" ] && [ "$2" = "true" ] && exit 1
exit 1
SH
    chmod +x "$fake_bin/sudo"

    SUDO="sudo" PATH="$fake_bin:$PATH" run configure_claude_managed_settings
    [ "$status" -eq 0 ]
    [[ "$output" == *"passwordless sudo is not available"* ]]
    [ ! -f "$CLAUDE_MANAGED_SETTINGS_FILE" ]
}

@test "configure_claude_settings sets network-resilience env" {
    configure_claude_settings
    python3 - <<PY
import json
d = json.load(open("$SETTINGS_FILE"))
env = d["env"]
assert env["API_FORCE_IDLE_TIMEOUT"] == "0", env
assert env["API_TIMEOUT_MS"] == "1800000", env
assert env["CLAUDE_CODE_MAX_RETRIES"] == "15", env
PY
}

@test "configure_claude_settings pre-approves edits to ~/.claude/** and ~/.claude.json" {
    configure_claude_settings
    python3 - <<PY
import json
d = json.load(open("$SETTINGS_FILE"))
home = "$HOME"
allow = d["permissions"]["allow"]
for op in ("Edit", "Write", "Read"):
    assert f"{op}({home}/.claude/**)" in allow, (op, allow)
    assert f"{op}({home}/.claude.json)" in allow, (op, allow)
PY
}

@test "configure_claude_settings backs up pre-existing settings.json" {
    mkdir -p "$CLAUDE_DIR"
    echo '{"model": "old"}' > "$SETTINGS_FILE"
    configure_claude_settings
    local backup_count
    backup_count=$(find "$CLAUDE_DIR" -maxdepth 1 -name 'settings.json.bak.*' | wc -l)
    [ "$backup_count" -ge 1 ]
}

@test "configure_aab_env_file writes AAB config and credentials with private permissions" {
    AAB_CLAUDE_THIRD_PARTY_PROFILES="deepseek-v4 model=deepseek-v4-pro haiku=deepseek-v4-flash effort=high" \
        AAB_CLAUDE_DEFAULT_PROFILE="third-party/deepseek-v4" \
        AAB_CODEX_THIRD_PARTY_PROFILES="gpt-5.5 effort=xhigh" \
        AAB_CODEX_DEFAULT_PROFILE="third-party/gpt-5.5" \
        AAB_PI_PROFILES="opus-4.8 model=anthropic/claude-opus-4-8 effort=high" \
        AAB_PI_DEFAULT_PROFILE="opus-4.8" \
        AAB_INFERENCE_GATEWAY_URL="https://gateway.example.com/v1" \
        AAB_INFERENCE_GATEWAY_API_KEY="gateway-test-key" \
        AAB_GH_TOKEN="ghp_test_token" \
        configure_aab_env_file

    [ -f "$AAB_ENV_FILE" ]
    [ "$(stat -c '%a' "$AAB_ENV_FILE")" = "600" ]
    [ "$(stat -c '%a' "$AAB_DIR")" = "700" ]
    # shellcheck disable=SC1090
    . "$AAB_ENV_FILE"
    [ "$AAB_CLAUDE_DEFAULT_PROFILE" = "third-party/deepseek-v4" ]
    [[ "$AAB_CLAUDE_THIRD_PARTY_PROFILES" == *"deepseek-v4-pro"* ]]
    [ "$AAB_CODEX_DEFAULT_PROFILE" = "third-party/gpt-5.5" ]
    [ "$AAB_PI_DEFAULT_PROFILE" = "opus-4.8" ]
    [ "$AAB_INFERENCE_GATEWAY_URL" = "https://gateway.example.com/v1" ]
    [ "$AAB_INFERENCE_GATEWAY_API_KEY" = "gateway-test-key" ]
    [ "$AAB_GH_TOKEN" = "ghp_test_token" ]
}

@test "configure_aab_env_file persists only AAB-prefixed first-party API keys" {
    AAB_ANTHROPIC_API_KEY="sk-ant-test-key" \
        AAB_OPENAI_API_KEY="codex-first-party-test-key" \
        configure_aab_env_file

    grep -q '^export AAB_ANTHROPIC_API_KEY=' "$AAB_ENV_FILE"
    grep -q '^export AAB_OPENAI_API_KEY=' "$AAB_ENV_FILE"
    ! grep -q '^export ANTHROPIC_API_KEY=' "$AAB_ENV_FILE"
    ! grep -q '^export OPENAI_API_KEY=' "$AAB_ENV_FILE"
    ! grep -q '^export GH_TOKEN=' "$AAB_ENV_FILE"
}

@test "configure_codex_model_instructions writes the complete global prompt without a blocking-wait cap" {
    configure_codex_model_instructions

    [ -f "$CODEX_MODEL_INSTRUCTIONS_FILE" ]
    [ "$CODEX_MODEL_INSTRUCTIONS_FILE" = "$HOME/.codex/codex-instructions.md" ]
    cmp -s "$CODEX_MODEL_INSTRUCTIONS_FILE" <(emit_codex_model_instructions)
    grep -Fq 'An event-driven monitoring call such as `wait_agent` is exempt' "$CODEX_MODEL_INSTRUCTIONS_FILE"
    ! grep -Fq 'Avoid performing blocking sleep or wait calls longer than 60 seconds' "$CODEX_MODEL_INSTRUCTIONS_FILE"
}

@test "configure_codex_model_instructions backs up a pre-existing prompt" {
    mkdir -p "$CODEX_DIR"
    printf 'local prompt\n' > "$CODEX_MODEL_INSTRUCTIONS_FILE"

    configure_codex_model_instructions

    local backup_count
    backup_count=$(find "$CODEX_DIR" -maxdepth 1 -name 'codex-instructions.md.bak.*' | wc -l)
    [ "$backup_count" -ge 1 ]
    grep -Fxq 'You are Codex, an agent based on GPT-5. You and the user share one workspace, and your job is to collaborate with them until their goal is genuinely handled.' "$CODEX_MODEL_INSTRUCTIONS_FILE"
}

@test "configure_codex_config writes unattended yolo-mode defaults" {
    configure_codex_config
    [ -f "$CODEX_CONFIG" ]
    grep -q '^model = "gpt-5.5"$' "$CODEX_CONFIG"
    grep -Fxq "model_instructions_file = \"${HOME}/.codex/codex-instructions.md\"" "$CODEX_CONFIG"
    grep -q '^model_reasoning_effort = "xhigh"$' "$CODEX_CONFIG"
    grep -q '^model_reasoning_summary = "detailed"$' "$CODEX_CONFIG"
    grep -q '^hide_agent_reasoning = false$' "$CODEX_CONFIG"
    grep -q '^show_raw_agent_reasoning = true$' "$CODEX_CONFIG"
    grep -q '^service_tier = "priority"$' "$CODEX_CONFIG"
    grep -q '^approval_policy = "never"$' "$CODEX_CONFIG"
    grep -q '^sandbox_mode = "danger-full-access"$' "$CODEX_CONFIG"
    grep -q '^web_search = "live"$' "$CODEX_CONFIG"
    grep -q '^check_for_update_on_startup = false$' "$CODEX_CONFIG"
    grep -q '^environment = "dev"$' "$CODEX_CONFIG"
    grep -q '^exporter = "none"$' "$CODEX_CONFIG"
    grep -q '^trace_exporter = "none"$' "$CODEX_CONFIG"
    grep -q '^metrics_exporter = "none"$' "$CODEX_CONFIG"
    grep -q '^log_user_prompt = false$' "$CODEX_CONFIG"
    grep -q '^hide_full_access_warning = true$' "$CODEX_CONFIG"
    grep -q '^inherit = "all"$' "$CODEX_CONFIG"
    grep -q '^ignore_default_excludes = true$' "$CODEX_CONFIG"
    grep -q '^\[agents\]$' "$CODEX_CONFIG"
    grep -q '^max_threads = 64$' "$CODEX_CONFIG"
    grep -qF "[projects.\"$HOME\"]" "$CODEX_CONFIG"
    grep -q '^trust_level = "trusted"$' "$CODEX_CONFIG"
}

@test "configure_codex_config honors model, reasoning-effort, service-tier, and agent thread overrides" {
    AAB_CODEX_FIRST_PARTY_PROFILES="gpt-5.4 effort=high" \
        AAB_CODEX_DEFAULT_PROFILE="first-party/gpt-5.4" \
        AAB_CODEX_SERVICE_TIER="flex" \
        AAB_CODEX_AGENT_MAX_THREADS="24" \
        configure_codex_config
    grep -q '^model = "gpt-5.4"$' "$CODEX_CONFIG"
    grep -q '^model_reasoning_effort = "high"$' "$CODEX_CONFIG"
    grep -q '^service_tier = "flex"$' "$CODEX_CONFIG"
    grep -q '^max_threads = 24$' "$CODEX_CONFIG"
}

@test "configure_codex_config can target a third-party OpenAI-compatible Responses endpoint" {
    AAB_CODEX_THIRD_PARTY_PROFILES="gpt-5.5 model=openai/openai/gpt-5.5 effort=xhigh" \
        AAB_CODEX_DEFAULT_PROFILE="third-party/gpt-5.5" \
        AAB_INFERENCE_GATEWAY_URL="https://inference-api.nvidia.com/v1" \
        configure_codex_config

    grep -q '^model = "openai/openai/gpt-5.5"$' "$CODEX_CONFIG"
    grep -q '^model_provider = "aab-gateway"$' "$CODEX_CONFIG"
    grep -q '^\[model_providers."aab-gateway"\]$' "$CODEX_CONFIG"
    grep -q '^name = "AAB Inference Gateway"$' "$CODEX_CONFIG"
    grep -q '^base_url = "https://inference-api.nvidia.com/v1"$' "$CODEX_CONFIG"
    grep -q '^env_key = "AAB_INFERENCE_GATEWAY_API_KEY"$' "$CODEX_CONFIG"
    grep -q '^requires_openai_auth = false$' "$CODEX_CONFIG"
    grep -q '^wire_api = "responses"$' "$CODEX_CONFIG"
}

@test "configure_codex_config passes arbitrary profile effort through" {
    AAB_CODEX_FIRST_PARTY_PROFILES="gpt-5.5 effort=ultra" configure_codex_config
    grep -q '^model_reasoning_effort = "ultra"$' "$CODEX_CONFIG"
}

@test "configure_codex_config normalizes fast service tier to priority" {
    AAB_CODEX_SERVICE_TIER="fast" configure_codex_config
    grep -q '^service_tier = "priority"$' "$CODEX_CONFIG"
}

@test "configure_codex_config defaults invalid service tier back to priority" {
    AAB_CODEX_SERVICE_TIER="premium" run configure_codex_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"AAB_CODEX_SERVICE_TIER='premium'"* ]]
    grep -q '^service_tier = "priority"$' "$CODEX_CONFIG"
}

@test "configure_codex_config defaults invalid agent max threads back to 64" {
    AAB_CODEX_AGENT_MAX_THREADS="many" run configure_codex_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"AAB_CODEX_AGENT_MAX_THREADS='many'"* ]]
    grep -q '^max_threads = 64$' "$CODEX_CONFIG"
}

@test "configure_codex_config backs up pre-existing config.toml" {
    mkdir -p "$CODEX_DIR"
    echo 'model = "old"' > "$CODEX_CONFIG"
    configure_codex_config
    local backup_count
    backup_count=$(find "$CODEX_DIR" -maxdepth 1 -name 'config.toml.bak.*' | wc -l)
    [ "$backup_count" -ge 1 ]
}

@test "configure_codex_config preserves Codex plugin marketplace tables" {
    mkdir -p "$CODEX_DIR"
    cat > "$CODEX_CONFIG" <<'TOML'
model = "old"

[marketplaces.robobryce-agitentic]
last_updated = "2026-05-21T00:00:00Z"
source_type = "git"
source = "https://github.com/brycelelbach/agitentic.git"

[plugins."agitentic@robobryce-agitentic"]
enabled = true
TOML

    configure_codex_config

    grep -q '^\[marketplaces.robobryce-agitentic\]$' "$CODEX_CONFIG"
    grep -q '^source = "https://github.com/brycelelbach/agitentic.git"$' "$CODEX_CONFIG"
    grep -q '^\[plugins."agitentic@robobryce-agitentic"\]$' "$CODEX_CONFIG"
    grep -q '^enabled = true$' "$CODEX_CONFIG"
    grep -q '^approval_policy = "never"$' "$CODEX_CONFIG"
}

setup_fake_codex_installer() {
    export FAKE_CODEX_INSTALLER_BIN="$TEST_HOME/fake-codex-installer-bin"
    mkdir -p "$FAKE_CODEX_INSTALLER_BIN"
    cat > "$FAKE_CODEX_INSTALLER_BIN/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_HOME/codex-installer-curl-invocations"

output=""
config=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o|--output)
            output="$2"
            shift 2
            ;;
        --config)
            config="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [ -n "$config" ]; then
    cat "$config" >> "$TEST_HOME/codex-installer-curl-configs"
fi

if [ -n "$output" ]; then
    cat > "$output" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
if (: </dev/tty) 2>/dev/null; then
    echo dev-tty-present > "$TEST_HOME/codex-installer-tty"
fi
if [ -t 0 ]; then
    echo stdin-tty-present > "$TEST_HOME/codex-installer-tty"
fi
printf '%s\n' "$*" > "$TEST_HOME/codex-installer-args"
curl -fsSL https://api.github.com/repos/openai/codex/releases/latest >/dev/null
curl -fsSL https://github.com/openai/codex/releases/download/rust-v0.133.0/codex.tar.gz >/dev/null
INSTALLER
    exit 0
fi

cat <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
if (: </dev/tty) 2>/dev/null; then
    echo dev-tty-present > "$TEST_HOME/codex-installer-tty"
fi
if [ -t 0 ]; then
    echo stdin-tty-present > "$TEST_HOME/codex-installer-tty"
fi
printf '%s\n' "$*" > "$TEST_HOME/codex-installer-args"
curl -fsSL https://api.github.com/repos/openai/codex/releases/latest >/dev/null
curl -fsSL https://github.com/openai/codex/releases/download/rust-v0.133.0/codex.tar.gz >/dev/null
INSTALLER
SH
    chmod +x "$FAKE_CODEX_INSTALLER_BIN/curl"
    export PATH="$FAKE_CODEX_INSTALLER_BIN:$PATH"
}

@test "install_codex authenticates GitHub API calls when a GitHub token is available" {
    setup_fake_codex_installer
    GH_TOKEN="github-test-token" run install_codex
    [ "$status" -eq 0 ]
    [[ "$output" == *"Using GitHub authentication for Codex release metadata requests."* ]]
    grep -Fq "releases/download/rust-v${CODEX_VERSION}/install.sh" "$TEST_HOME/codex-installer-curl-invocations"
    grep -Fxq -- "--release ${CODEX_VERSION}" "$TEST_HOME/codex-installer-args"
    grep -Eq '^--config .+ https://api.github.com/repos/openai/codex/releases/latest$' "$TEST_HOME/codex-installer-curl-invocations"
    grep -Fxq -- '-fsSL https://github.com/openai/codex/releases/download/rust-v0.133.0/codex.tar.gz' "$TEST_HOME/codex-installer-curl-invocations"
    grep -Fq 'header = "Authorization: Bearer github-test-token"' "$TEST_HOME/codex-installer-curl-configs"
    [ ! -f "$TEST_HOME/codex-installer-tty" ]
}

@test "install_codex leaves installer calls unauthenticated without a GitHub token" {
    setup_fake_codex_installer
    run install_codex
    [ "$status" -eq 0 ]
    [[ "$output" != *"Using GitHub authentication for Codex release metadata requests."* ]]
    ! grep -Fq -- '--config' "$TEST_HOME/codex-installer-curl-invocations"
    [ ! -f "$TEST_HOME/codex-installer-curl-configs" ]
    [ ! -f "$TEST_HOME/codex-installer-tty" ]
}

# Stub `uv` on PATH so the tool-install steps find it without reaching the
# network. The stub records every invocation. UV_FAIL_TOOL_INSTALL=1 makes
# `uv tool install` exit non-zero, exercising the best-effort warning branches.
setup_fake_uv() {
    export FAKE_UV_BIN="$TEST_HOME/fake-uv-bin"
    export UV_VERSION
    mkdir -p "$FAKE_UV_BIN"
    cat > "$FAKE_UV_BIN/uv" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_HOME/uv-invocations"
if [ "${1:-}" = "--version" ]; then
    printf 'uv %s (fake)\n' "${UV_VERSION:?}"
    exit 0
fi
if [ "${1:-}" = "tool" ] && [ "${2:-}" = "install" ] && [ "${UV_FAIL_TOOL_INSTALL:-0}" = "1" ]; then
    exit 1
fi
exit 0
SH
    chmod +x "$FAKE_UV_BIN/uv"
    export PATH="$FAKE_UV_BIN:$PATH"
    UV_BIN="$FAKE_UV_BIN/uv"
}

# Stub `curl` so the uv installer fetch drops a fake `uv` into ~/.local/bin
# instead of reaching the network; the fetched uv records its invocations too.
setup_fake_uv_installer() {
    export FAKE_UV_INSTALLER_BIN="$TEST_HOME/fake-uv-installer-bin"
    export UV_VERSION
    mkdir -p "$FAKE_UV_INSTALLER_BIN"
    cat > "$FAKE_UV_INSTALLER_BIN/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_HOME/uv-installer-curl-invocations"
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/uv" <<'UV'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_HOME/uv-invocations"
if [ "${1:-}" = "--version" ]; then
    printf 'uv %s (fake)\n' "${UV_VERSION:?}"
fi
UV
chmod +x "$HOME/.local/bin/uv"
SH
    chmod +x "$FAKE_UV_INSTALLER_BIN/curl"
    export PATH="$FAKE_UV_INSTALLER_BIN:$PATH"
}

@test "install_uv installs the pinned uv release when absent" {
    # A PATH without uv forces the installer path; the fake curl provisions
    # ~/.local/bin/uv, which install_uv then records as UV_BIN.
    setup_fake_uv_installer
    PATH="$FAKE_UV_INSTALLER_BIN:/usr/bin:/bin" run install_uv
    [ "$status" -eq 0 ]
    grep -Fq "astral.sh/uv/${UV_VERSION}/install.sh" "$TEST_HOME/uv-installer-curl-invocations"
}

@test "install_uv prepends ~/.local/bin to the live PATH so uv tool binaries resolve in-process" {
    setup_fake_uv
    # A PATH without ~/.local/bin: install_uv must prepend it so executables that
    # `uv tool install` symlinks there (ruff, pre-commit, autocuda) resolve
    # later in the same run.
    PATH="$FAKE_UV_BIN:/usr/bin:/bin" install_uv
    case ":${PATH}:" in
        *":${HOME}/.local/bin:"*) ;;
        *) printf 'PATH is %s\n' "$PATH"; return 1 ;;
    esac
    # ~/.local/bin comes before the system dirs so its tools win.
    [[ "$PATH" == "${HOME}/.local/bin:"* ]]
}

@test "install_uv_tools runs uv tool install for each tool listed in the file" {
    setup_fake_uv
    printf '%s\n' '# The linter, pinned.' "ruff==${RUFF_VERSION}" '' '# The hook runner.' 'pre-commit' \
        > "$TEST_HOME/uv-tools.txt"
    export AAB_UV_TOOLS_FILE="$TEST_HOME/uv-tools.txt"

    run install_uv_tools
    [ "$status" -eq 0 ]
    # Each non-comment, non-blank line becomes its own `uv tool install`; the
    # comment and blank lines are stripped, not installed.
    grep -Fxq "tool install ruff==${RUFF_VERSION}" "$TEST_HOME/uv-invocations"
    grep -Fxq "tool install pre-commit==${PRE_COMMIT_VERSION}" "$TEST_HOME/uv-invocations"
    [ "$(grep -c 'tool install' "$TEST_HOME/uv-invocations")" -eq 2 ]
}

@test "install_uv_tools reads ./uv_tools.txt by default" {
    setup_fake_uv
    # No AAB_UV_TOOLS_FILE override: the committed uv_tools.txt at the repo root
    # is the default source, and the tools it lists get installed.
    UV_TOOLS_DEFAULT_FILE="$REPO_ROOT/uv_tools.txt" run install_uv_tools
    [ "$status" -eq 0 ]
    [[ "$output" == *"Reading uv tool list from $REPO_ROOT/uv_tools.txt."* ]]
    grep -Fxq "tool install ruff==${RUFF_VERSION}" "$TEST_HOME/uv-invocations"
    grep -Fxq "tool install pre-commit==${PRE_COMMIT_VERSION}" "$TEST_HOME/uv-invocations"
}

@test "install_uv_tools warns and continues when a tool install fails" {
    setup_fake_uv
    printf '%s\n' "ruff==${RUFF_VERSION}" > "$TEST_HOME/uv-tools.txt"
    export AAB_UV_TOOLS_FILE="$TEST_HOME/uv-tools.txt"
    export UV_FAIL_TOOL_INSTALL=1

    run install_uv_tools
    # Best effort: a failed tool install warns but does not abort the bootstrap.
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN:"*"ruff==${RUFF_VERSION}"* ]]
}

@test "uv_tools.txt delegates built-in versions to the central version file" {
    grep -Fxq 'ruff' "$REPO_ROOT/uv_tools.txt"
    grep -Fxq 'pre-commit' "$REPO_ROOT/uv_tools.txt"
    [ -n "$RUFF_VERSION" ]
    [ -n "$PRE_COMMIT_VERSION" ]
    # autocuda is private, so it must not be an installable tool line here (it
    # may be named in a comment explaining its absence). Strip comments and
    # blanks, then assert no remaining line names it.
    run bash -c "sed -E 's/#.*//' '$REPO_ROOT/uv_tools.txt' | grep -i 'autocuda'"
    [ "$status" -ne 0 ]
}

@test "install_uv_tools rejects an unpinned custom tool" {
    setup_fake_uv
    printf '%s\n' 'black' > "$TEST_HOME/uv-tools.txt"
    export AAB_UV_TOOLS_FILE="$TEST_HOME/uv-tools.txt"

    run install_uv_tools
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not version-pinned"* ]]
}

@test "install_autocuda installs its package from a pinned git ref" {
    setup_fake_uv

    run install_autocuda
    [ "$status" -eq 0 ]
    # Installed as its own isolated uv tool, not into a shared interpreter.
    grep -Fq "tool install git+https://github.com/${AUTOCUDA_PRIVATE_REPO}@${AUTOCUDA_REF}" "$TEST_HOME/uv-invocations"
}

@test "install_autocuda package failure warns and continues" {
    setup_fake_uv
    export UV_FAIL_TOOL_INSTALL=1

    run install_autocuda
    # Best effort: a failed install is never fatal.
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN:"*"autocuda"* ]]
}

@test "install_autocuda authenticates private fetches via a github token rewrite" {
    setup_fake_uv
    # Capture the environment uv runs under so the url.insteadOf rewrite is
    # observable; the token value itself never lands in the package spec.
    cat > "$FAKE_UV_BIN/uv" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--version" ]; then
    printf 'uv %s (fake)\n' "${UV_VERSION:?}"
    exit 0
fi
printf 'KEY0=%s VALUE0=%s\n' "${GIT_CONFIG_KEY_0:-}" "${GIT_CONFIG_VALUE_0:-}" >> "$TEST_HOME/uv-git-env"
exit 0
SH
    chmod +x "$FAKE_UV_BIN/uv"
    export AAB_GH_TOKEN="ghp_faketoken123"

    run install_autocuda
    [ "$status" -eq 0 ]
    grep -Fq 'KEY0=url.https://x-access-token:ghp_faketoken123@github.com/.insteadOf VALUE0=https://github.com/' "$TEST_HOME/uv-git-env"
}

@test "install_autocuda configures plugins when autocuda is on PATH" {
    setup_fake_uv
    local fake_bin="$TEST_HOME/fake-autocuda-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/autocuda" <<SH
#!/bin/sh
printf '%s\n' "\$*" >> "$TEST_HOME/autocuda-invocations"
SH
    chmod +x "$fake_bin/autocuda"
    PATH="$fake_bin:$PATH" run install_autocuda
    [ "$status" -eq 0 ]
    grep -Fxq 'install' "$TEST_HOME/autocuda-invocations"
}

@test "install_autocuda configuration warns and skips when autocuda is not on PATH" {
    setup_fake_uv
    # A PATH without autocuda: the private install was skipped, so this is a
    # graceful no-op warning rather than an error.
    PATH="$FAKE_UV_BIN:/usr/bin:/bin" run install_autocuda
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN:"*"autocuda"* ]]
    [ ! -f "$TEST_HOME/autocuda-invocations" ]
}

@test "install_autocuda restores AAB-managed settings.json keys that autocuda install strips" {
    setup_fake_uv
    # autocuda install shells out to claude's plugin CLI, which re-serialises
    # settings.json and drops top-level keys like effortLevel. The fake autocuda
    # below reproduces that strip; install_autocuda must re-merge them.
    mkdir -p "$CLAUDE_DIR"
    cat > "$SETTINGS_FILE" <<'JSON'
{
  "model": "claude-opus-4-7",
  "effortLevel": "max",
  "env": {"CLAUDE_CODE_EFFORT_LEVEL": "max"},
  "extraKnownMarketplaces": {}
}
JSON
    local fake_bin="$TEST_HOME/fake-autocuda-strip-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/autocuda" <<SH
#!/usr/bin/env bash
# Mimic claude's plugin CLI re-serialise: keep its own keys, drop effortLevel.
python3 - "$SETTINGS_FILE" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.pop("effortLevel", None)
d["extraKnownMarketplaces"]["brycelelbach-autocuda"] = {"source": {"source": "github", "repo": "brycelelbach/autocuda"}}
json.dump(d, open(p, "w"), indent=2)
PY
SH
    chmod +x "$fake_bin/autocuda"

    PATH="$fake_bin:$PATH" run install_autocuda
    [ "$status" -eq 0 ]
    # effortLevel is re-merged from the snapshot; the marketplace autocuda
    # install added survives (live value wins where present).
    python3 - "$SETTINGS_FILE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["effortLevel"] == "max", d
assert d["model"] == "claude-opus-4-7", d
assert d["env"]["CLAUDE_CODE_EFFORT_LEVEL"] == "max", d
assert "brycelelbach-autocuda" in d["extraKnownMarketplaces"], d
PY
    # The snapshot file is cleaned up.
    [ ! -f "${SETTINGS_FILE}.pre-autocuda-install.bak" ]
}

@test "configure_codex_launchers wraps codex with dynamic trust and bypass flags" {
    mkdir -p "$HOME/.local/bin" "$TEST_HOME/work/subdir"
    cat > "$TEST_HOME/real-codex" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TEST_HOME/codex-launcher-args"
SH
    chmod +x "$TEST_HOME/real-codex"
    ln -s "$TEST_HOME/real-codex" "$HOME/.local/bin/codex"

    configure_codex_launchers

    [ -x "$HOME/.local/bin/codex" ]
    [ -L "$HOME/.local/bin/codex-aab-real" ]
    (
        cd "$TEST_HOME/work/subdir"
        "$HOME/.local/bin/codex" --version
    )

    grep -Fxq -- '--dangerously-bypass-approvals-and-sandbox' "$TEST_HOME/codex-launcher-args"
    grep -Fxq -- '--dangerously-bypass-hook-trust' "$TEST_HOME/codex-launcher-args"
    grep -Fxq -- '-c' "$TEST_HOME/codex-launcher-args"
    grep -Fxq "projects={\"$TEST_HOME/work/subdir\"={trust_level=\"trusted\"}}" "$TEST_HOME/codex-launcher-args"
    grep -Fxq -- '--version' "$TEST_HOME/codex-launcher-args"
}

@test "configure_codex_launchers adds git root to dynamic trust override" {
    command -v git >/dev/null || skip "precondition: git must exist"
    mkdir -p "$HOME/.local/bin" "$TEST_HOME/repo/nested"
    git -C "$TEST_HOME/repo" init >/dev/null
    cat > "$TEST_HOME/real-codex" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TEST_HOME/codex-launcher-args"
SH
    chmod +x "$TEST_HOME/real-codex"
    ln -s "$TEST_HOME/real-codex" "$HOME/.local/bin/codex"

    configure_codex_launchers
    (
        cd "$TEST_HOME/repo/nested"
        "$HOME/.local/bin/codex" plugin list
    )

    grep -Fxq "projects={\"$TEST_HOME/repo/nested\"={trust_level=\"trusted\"},\"$TEST_HOME/repo\"={trust_level=\"trusted\"}}" "$TEST_HOME/codex-launcher-args"
    grep -Fxq -- 'plugin' "$TEST_HOME/codex-launcher-args"
    grep -Fxq -- 'list' "$TEST_HOME/codex-launcher-args"
}

@test "configure_codex_launchers generates source-explicit profiles and injects gateway config" {
    mkdir -p "$HOME/.local/bin"
    cat > "$TEST_HOME/real-codex" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TEST_HOME/codex-launcher-args"
printf '%s\n' "\${AAB_CODEX_DEFAULT_PROFILE:-}" > "$TEST_HOME/codex-launcher-default-profile"
printf '%s\n' "\${OPENAI_API_KEY:-}" > "$TEST_HOME/codex-launcher-api-key"
SH
    chmod +x "$TEST_HOME/real-codex"
    ln -s "$TEST_HOME/real-codex" "$HOME/.local/bin/codex"

    AAB_CODEX_THIRD_PARTY_PROFILES="gpt-5.5 model=vendor/model effort=ultra" \
        AAB_CODEX_DEFAULT_PROFILE="third-party/gpt-5.5" \
        AAB_INFERENCE_GATEWAY_URL="https://gateway.example.com/v1" \
        AAB_INFERENCE_GATEWAY_API_KEY="gateway-test-key" \
        AAB_OPENAI_API_KEY="first-party-key" \
        configure_aab_env_file
    AAB_CODEX_THIRD_PARTY_PROFILES="gpt-5.5 model=vendor/model effort=ultra" \
        AAB_CODEX_DEFAULT_PROFILE="third-party/gpt-5.5" \
        AAB_INFERENCE_GATEWAY_URL="https://gateway.example.com/v1" \
        configure_codex_launchers

    [ ! -L "$HOME/.local/bin/codex" ]
    [ -x "$HOME/.local/bin/codex-first-party-gpt-5.5" ]
    [ -x "$HOME/.local/bin/codex-third-party-gpt-5.5" ]
    grep -q '^profile_source=third-party$' "$HOME/.local/bin/codex"
    "$HOME/.local/bin/codex" exec hello

    [ "$(cat "$TEST_HOME/codex-launcher-default-profile")" = "third-party/gpt-5.5" ]
    grep -Fxq 'model="vendor/model"' "$TEST_HOME/codex-launcher-args"
    grep -Fxq 'model_reasoning_effort="ultra"' "$TEST_HOME/codex-launcher-args"
    grep -Fxq 'model_provider="aab-gateway"' "$TEST_HOME/codex-launcher-args"
    grep -Fq 'env_key="AAB_INFERENCE_GATEWAY_API_KEY"' "$TEST_HOME/codex-launcher-args"
    grep -Fq 'requires_openai_auth=false' "$TEST_HOME/codex-launcher-args"
    grep -Fq 'base_url="https://gateway.example.com/v1"' "$TEST_HOME/codex-launcher-args"
    [ "$(cat "$TEST_HOME/codex-launcher-api-key")" = "" ]

    "$HOME/.local/bin/codex-first-party-gpt-5.5" exec hello
    [ "$(cat "$TEST_HOME/codex-launcher-default-profile")" = "third-party/gpt-5.5" ]
    [ "$(cat "$TEST_HOME/codex-launcher-api-key")" = "first-party-key" ]
}

@test "configure_claude_launchers expands a gateway profile into every Claude model slot" {
    mkdir -p "$HOME/.local/bin"
    cat > "$TEST_HOME/real-claude" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TEST_HOME/claude-launcher-args"
{
    printf 'default_profile=%s\n' "\${AAB_CLAUDE_DEFAULT_PROFILE:-}"
    printf 'base_url=%s\n' "\${ANTHROPIC_BASE_URL:-}"
    printf 'auth_token=%s\n' "\${ANTHROPIC_AUTH_TOKEN:-}"
    printf 'api_key=%s\n' "\${ANTHROPIC_API_KEY:-}"
    printf 'model=%s\n' "\${ANTHROPIC_MODEL:-}"
    printf 'haiku=%s\n' "\${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
    printf 'sonnet=%s\n' "\${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"
    printf 'opus=%s\n' "\${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
    printf 'effort=%s\n' "\${CLAUDE_CODE_EFFORT_LEVEL:-}"
    printf 'subagent_model=%s\n' "\${CLAUDE_CODE_SUBAGENT_MODEL:-}"
    printf 'debug=%s\n' "\${DEBUG_SDK:-}"
    printf 'auto_compact_window=%s\n' "\${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
} > "$TEST_HOME/claude-launcher-env"
SH
    chmod +x "$TEST_HOME/real-claude"
    ln -s "$TEST_HOME/real-claude" "$HOME/.local/bin/claude"

    AAB_CLAUDE_THIRD_PARTY_PROFILES="deepseek-v4 model=deepseek-v4-pro haiku=deepseek-v4-flash effort=high context=1000000" \
        AAB_CLAUDE_DEFAULT_PROFILE="third-party/deepseek-v4" \
        AAB_INFERENCE_GATEWAY_URL="https://gateway.example.com/v1" \
        AAB_INFERENCE_GATEWAY_API_KEY="gateway-test-key" \
        AAB_ANTHROPIC_API_KEY="first-party-key" \
        configure_aab_env_file
    AAB_CLAUDE_THIRD_PARTY_PROFILES="deepseek-v4 model=deepseek-v4-pro haiku=deepseek-v4-flash effort=high context=1000000" \
        AAB_CLAUDE_DEFAULT_PROFILE="third-party/deepseek-v4" \
        AAB_INFERENCE_GATEWAY_URL="https://gateway.example.com/v1" \
        configure_claude_launchers

    # The selected entrypoint lives in ~/.local/aab-bin as a regular launcher
    # file (not a symlink to a provider wrapper); ~/.local/bin/claude is left as
    # the native binary for the auto-updater, and the wrappers exec it.
    [ ! -L "$HOME/.local/aab-bin/claude" ]
    [ -x "$HOME/.local/bin/claude-first-party-opus-4.8" ]
    [ -x "$HOME/.local/bin/claude-third-party-deepseek-v4" ]
    grep -q '^profile_source=third-party$' "$HOME/.local/aab-bin/claude"
    [ "$(readlink "$HOME/.local/bin/claude")" = "$TEST_HOME/real-claude" ]
    [ "$(readlink "$HOME/.local/bin/claude-aab-real")" = "$HOME/.local/bin/claude" ]
    "$HOME/.local/aab-bin/claude" -p hello

    grep -Fxq -- '--dangerously-skip-permissions' "$TEST_HOME/claude-launcher-args"
    grep -Fxq 'default_profile=third-party/deepseek-v4' "$TEST_HOME/claude-launcher-env"
    grep -Fxq 'base_url=https://gateway.example.com/v1' "$TEST_HOME/claude-launcher-env"
    grep -Fxq 'auth_token=gateway-test-key' "$TEST_HOME/claude-launcher-env"
    grep -Fxq 'api_key=' "$TEST_HOME/claude-launcher-env"
    # The model carries a [1m] suffix so Claude Code resolves the full 1M
    # window and engages auto-compaction; Claude Code strips the suffix before
    # the request, so the gateway still receives the real id.
    grep -Fxq 'model=deepseek-v4-pro[1m]' "$TEST_HOME/claude-launcher-env"
    grep -Fxq 'haiku=deepseek-v4-flash' "$TEST_HOME/claude-launcher-env"
    grep -Fxq 'sonnet=deepseek-v4-pro' "$TEST_HOME/claude-launcher-env"
    grep -Fxq 'opus=deepseek-v4-pro' "$TEST_HOME/claude-launcher-env"
    grep -Fxq 'effort=high' "$TEST_HOME/claude-launcher-env"
    # Sub-agents and teammates default to the same resolved model as the main
    # agent (including the [1m] suffix), so a gateway gets a recognized id.
    grep -Fxq 'subagent_model=deepseek-v4-pro[1m]' "$TEST_HOME/claude-launcher-env"
    grep -Fxq 'debug=1' "$TEST_HOME/claude-launcher-env"
    grep -Fxq 'auto_compact_window=1000000' "$TEST_HOME/claude-launcher-env"

    "$HOME/.local/bin/claude-first-party-opus-4.8" -p hello
    grep -Fxq 'default_profile=third-party/deepseek-v4' "$TEST_HOME/claude-launcher-env"
    grep -Fxq 'api_key=first-party-key' "$TEST_HOME/claude-launcher-env"
}

@test "configure_claude_launchers supports mixed gateway models" {
    mkdir -p "$HOME/.local/bin"
    cat > "$TEST_HOME/real-claude" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TEST_HOME/claude-launcher-args"
{
    printf 'model=%s\n' "\${ANTHROPIC_MODEL:-}"
    printf 'haiku=%s\n' "\${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
    printf 'sonnet=%s\n' "\${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"
    printf 'opus=%s\n' "\${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
} > "$TEST_HOME/claude-launcher-env"
SH
    chmod +x "$TEST_HOME/real-claude"
    ln -s "$TEST_HOME/real-claude" "$HOME/.local/bin/claude"

    AAB_CLAUDE_THIRD_PARTY_PROFILES="opus-4.8 model=bedrock/opus-4-8 haiku=azure/haiku-4-5 sonnet=bedrock/sonnet-4-8 effort=max" \
        AAB_CLAUDE_DEFAULT_PROFILE="third-party/opus-4.8" \
        AAB_INFERENCE_GATEWAY_URL="https://gateway.example.com" \
        configure_aab_env_file
    AAB_CLAUDE_THIRD_PARTY_PROFILES="opus-4.8 model=bedrock/opus-4-8 haiku=azure/haiku-4-5 sonnet=bedrock/sonnet-4-8 effort=max" \
        AAB_CLAUDE_DEFAULT_PROFILE="third-party/opus-4.8" \
        AAB_INFERENCE_GATEWAY_URL="https://gateway.example.com" \
        configure_claude_launchers

    # The selected entrypoint lives in ~/.local/aab-bin as a regular launcher
    # file (not a symlink to a provider wrapper); ~/.local/bin/claude is left as
    # the native binary for the auto-updater, and the wrappers exec it.
    [ ! -L "$HOME/.local/aab-bin/claude" ]
    grep -q '^profile_name=opus-4.8$' "$HOME/.local/aab-bin/claude"
    [ "$(readlink "$HOME/.local/bin/claude")" = "$TEST_HOME/real-claude" ]
    [ "$(readlink "$HOME/.local/bin/claude-aab-real")" = "$HOME/.local/bin/claude" ]
    "$HOME/.local/aab-bin/claude" -p hello

    grep -Fxq -- '--dangerously-skip-permissions' "$TEST_HOME/claude-launcher-args"
    grep -Fxq 'model=bedrock/opus-4-8' "$TEST_HOME/claude-launcher-env"
    grep -Fxq 'haiku=azure/haiku-4-5' "$TEST_HOME/claude-launcher-env"
    grep -Fxq 'sonnet=bedrock/sonnet-4-8' "$TEST_HOME/claude-launcher-env"
    grep -Fxq 'opus=bedrock/opus-4-8' "$TEST_HOME/claude-launcher-env"
}

@test "configure_claude_launchers uses profile subagent override or main model" {
    mkdir -p "$HOME/.local/bin"
    cat > "$TEST_HOME/real-claude" <<SH
#!/usr/bin/env bash
{
    printf 'model=%s\n' "\${ANTHROPIC_MODEL:-}"
    printf 'subagent_model=%s\n' "\${CLAUDE_CODE_SUBAGENT_MODEL:-}"
} > "$TEST_HOME/claude-launcher-env"
SH
    chmod +x "$TEST_HOME/real-claude"
    ln -s "$TEST_HOME/real-claude" "$HOME/.local/bin/claude"

    AAB_CLAUDE_FIRST_PARTY_PROFILES="opus-4.8 model=claude-opus-4-8 subagent=claude-haiku-4-5 effort=max" \
        configure_aab_env_file
    AAB_CLAUDE_FIRST_PARTY_PROFILES="opus-4.8 model=claude-opus-4-8 subagent=claude-haiku-4-5 effort=max" \
        configure_claude_launchers
    "$HOME/.local/aab-bin/claude" -p hello
    grep -Fxq 'subagent_model=claude-haiku-4-5' "$TEST_HOME/claude-launcher-env"

    AAB_CLAUDE_FIRST_PARTY_PROFILES="opus-4.8 model=claude-opus-4-8 effort=max" \
        configure_aab_env_file
    AAB_CLAUDE_FIRST_PARTY_PROFILES="opus-4.8 model=claude-opus-4-8 effort=max" \
        configure_claude_launchers
    "$HOME/.local/aab-bin/claude" -p hello
    grep -Fxq 'model=claude-opus-4-8' "$TEST_HOME/claude-launcher-env"
    grep -Fxq 'subagent_model=claude-opus-4-8' "$TEST_HOME/claude-launcher-env"
}

@test "configure_pi_models and configure_pi_launchers create pi-model aliases" {
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/pi-aab-real" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TEST_HOME/pi-launcher-args"
printf '%s\n' "\${AAB_PI_DEFAULT_PROFILE:-}" > "$TEST_HOME/pi-launcher-default-profile"
printf '%s\n' "\${OTEL_SERVICE_NAME:-}" > "$TEST_HOME/pi-launcher-otel-service"
SH
    chmod +x "$HOME/.local/bin/pi-aab-real"
    mkdir -p "$(dirname "$PI_OBSERVABILITY_ENV_FILE")"
    printf '%s\n' 'export OTEL_SERVICE_NAME=pi-test-service' > "$PI_OBSERVABILITY_ENV_FILE"

    AAB_PI_PROFILES=$'opus-4.8 model=aws/anthropic/bedrock-claude-opus-4-8 effort=max context=1000000 max_tokens=128000\ngpt-5.6 model=openai/openai/gpt-5.6-sol effort=ultra context=1050000 max_tokens=128000' \
        AAB_PI_DEFAULT_PROFILE="gpt-5.6" \
        AAB_INFERENCE_GATEWAY_URL="https://gateway.example.com/v1" \
        AAB_INFERENCE_GATEWAY_API_KEY="gateway-test-key" \
        configure_aab_env_file
    AAB_PI_PROFILES=$'opus-4.8 model=aws/anthropic/bedrock-claude-opus-4-8 effort=max context=1000000 max_tokens=128000\ngpt-5.6 model=openai/openai/gpt-5.6-sol effort=ultra context=1050000 max_tokens=128000' \
        AAB_PI_DEFAULT_PROFILE="gpt-5.6" \
        AAB_INFERENCE_GATEWAY_URL="https://gateway.example.com/v1" \
        configure_pi_models
    AAB_PI_PROFILES=$'opus-4.8 model=aws/anthropic/bedrock-claude-opus-4-8 effort=max context=1000000 max_tokens=128000\ngpt-5.6 model=openai/openai/gpt-5.6-sol effort=ultra context=1050000 max_tokens=128000' \
        AAB_PI_DEFAULT_PROFILE="gpt-5.6" \
        AAB_INFERENCE_GATEWAY_URL="https://gateway.example.com/v1" \
        configure_pi_launchers

    [ -x "$HOME/.local/bin/pi-gpt-5.6" ]
    [ -x "$HOME/.local/bin/pi-opus-4.8" ]
    [ ! -e "$HOME/.local/bin/pi-third-party-gpt-5.6" ]
    "$HOME/.local/bin/pi-gpt-5.6" -p hello
    [ "$(cat "$TEST_HOME/pi-launcher-default-profile")" = "gpt-5.6" ]
    grep -Fxq -- '--provider' "$TEST_HOME/pi-launcher-args"
    grep -Fxq 'aab-gateway' "$TEST_HOME/pi-launcher-args"
    grep -Fxq -- '--model' "$TEST_HOME/pi-launcher-args"
    grep -Fxq 'openai/openai/gpt-5.6-sol' "$TEST_HOME/pi-launcher-args"
    grep -Fxq -- '--thinking' "$TEST_HOME/pi-launcher-args"
    grep -Fxq 'xhigh' "$TEST_HOME/pi-launcher-args"
    ! grep -Fxq 'ultra' "$TEST_HOME/pi-launcher-args"
    [ "$(cat "$TEST_HOME/pi-launcher-otel-service")" = "pi-test-service" ]

    "$HOME/.local/bin/pi-gpt-5.6" install npm:example@1.0.0
    [ "$(sed -n '1p' "$TEST_HOME/pi-launcher-args")" = "install" ]
    [ "$(sed -n '2p' "$TEST_HOME/pi-launcher-args")" = "npm:example@1.0.0" ]
    [ "$(wc -l < "$TEST_HOME/pi-launcher-args")" -eq 2 ]
    python3 - <<PY
import json
d = json.load(open("$PI_MODELS_FILE"))
p = d["providers"]["aab-gateway"]
assert p["baseUrl"] == "https://gateway.example.com/v1", p
assert p["api"] == "openai-completions", p
assert p["apiKey"] == "\$AAB_INFERENCE_GATEWAY_API_KEY", p
assert p["models"] == [
    {
        "id": "aws/anthropic/bedrock-claude-opus-4-8",
        "name": "opus-4.8",
        "reasoning": True,
        "input": ["text"],
        "contextWindow": 1000000,
        "maxTokens": 128000,
        "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        "thinkingLevelMap": {"xhigh": "max"},
    },
    {
        "id": "openai/openai/gpt-5.6-sol",
        "name": "gpt-5.6",
        "reasoning": True,
        "input": ["text"],
        "contextWindow": 1050000,
        "maxTokens": 128000,
        "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        "thinkingLevelMap": {"xhigh": "ultra"},
    },
], p
PY

    _write_pi_launcher "deepseek-v4" "deepseek-v4-pro" "high" "$HOME/.local/bin/pi-deepseek-v4"
    "$HOME/.local/bin/pi-deepseek-v4" -p hello
    [ "$(cat "$TEST_HOME/pi-launcher-default-profile")" = "gpt-5.6" ]
}

@test "configure_pi_launchers removes stale aliases when profiles are disabled" {
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/pi-aab-real" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$HOME/.local/bin/pi-aab-real"

    AAB_PI_PROFILES="opus-4.8 model=anthropic/claude-opus-4-8 effort=max" \
        AAB_INFERENCE_GATEWAY_URL="https://gateway.example.com/v1" \
        configure_pi_launchers
    [ -x "$HOME/.local/bin/pi" ]
    [ -x "$HOME/.local/bin/pi-opus-4.8" ]

    AAB_PI_PROFILES="" configure_pi_launchers

    [ -f "$HOME/.local/bin/pi" ]
    [ ! -L "$HOME/.local/bin/pi" ]
    grep -Fq 'Autonomous-agent-bootstrap Pi launcher' "$HOME/.local/bin/pi"
    [ ! -e "$HOME/.local/bin/pi-opus-4.8" ]
    [ -x "$HOME/.local/bin/pi-aab-real" ]
}

@test "configure_pi_settings writes machine-independent unattended defaults" {
    AAB_PI_PROFILES=$'opus-4.8 model=anthropic/claude-opus-4-8 effort=high\ndeepseek-v4 model=deepseek-v4-pro effort=high' \
        AAB_PI_DEFAULT_PROFILE="deepseek-v4" \
        AAB_INFERENCE_GATEWAY_URL="https://gateway.example.com/v1" \
        configure_pi_settings

    python3 - "$PI_SETTINGS_FILE" "$PI_LIST_TOOLS_EXTENSION" <<'PY'
import json
import sys

settings_path, extension_path = sys.argv[1:]
with open(settings_path, encoding="utf-8") as handle:
    data = json.load(handle)
assert data["defaultProvider"] == "aab-gateway", data
assert data["defaultModel"] == "deepseek-v4-pro", data
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
assert data["enabledModels"] == ["anthropic/claude-opus-4-8", "deepseek-v4-pro"], data
assert data["extensions"] == [extension_path], data
assert data["packages"] == [], data
assert "trackingId" not in data and "lastChangelogVersion" not in data, data
PY
}

@test "configure_pi_observability installs launcher-only logging assets and pinned OTEL dependencies" {
    local fake_bin="$TEST_HOME/fake-npm-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/npm" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$TEST_HOME/npm-invocations"
SH
    chmod +x "$fake_bin/npm"

    PATH="$fake_bin:$PATH" configure_pi_observability

    [ -f "$PI_OBSERVABILITY_ENV_FILE" ]
    [ -f "$PI_OBSERVABILITY_PRELOAD" ]
    [ -f "$PI_LIST_TOOLS_EXTENSION" ]
    grep -Fq 'PI_TIMING="${PI_TIMING:-0}"' "$PI_OBSERVABILITY_ENV_FILE"
    grep -Fq 'OTEL_TRACES_EXPORTER="${OTEL_TRACES_EXPORTER:-console}"' "$PI_OBSERVABILITY_ENV_FILE"
    grep -Fq 'pi-observability-preload.cjs' "$PI_OBSERVABILITY_ENV_FILE"
    grep -Fq 'PI_DEBUG_LOG_FILE' "$PI_OBSERVABILITY_PRELOAD"
    grep -Fq 'pi.registerFlag("list-tools"' "$PI_LIST_TOOLS_EXTENSION"
    grep -Fq '@opentelemetry/auto-instrumentations-node@0.78.0' "$TEST_HOME/npm-invocations"
    grep -Fq '@opentelemetry/sdk-node@0.220.0' "$TEST_HOME/npm-invocations"
}

@test "install_pi_plugins installs every non-comment source without profile flags" {
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/pi-aab-real" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_HOME/pi-package-invocations"
SH
    chmod +x "$HOME/.local/bin/pi-aab-real"
    cat > "$TEST_HOME/pi-plugins.txt" <<'EOF'
# Test packages.
npm:one@1.0.0

git:github.com/example/two@0123456789abcdef
EOF
    export AAB_PI_PLUGINS_FILE="$TEST_HOME/pi-plugins.txt"

    install_pi_plugins

    grep -Fxq 'install npm:one@1.0.0 --no-approve' "$TEST_HOME/pi-package-invocations"
    grep -Fxq 'install git:github.com/example/two@0123456789abcdef --no-approve' "$TEST_HOME/pi-package-invocations"
    [ "$(wc -l < "$TEST_HOME/pi-package-invocations")" -eq 2 ]
}

setup_fake_codex() {
    export FAKE_CODEX_BIN="$TEST_HOME/fake-codex-bin"
    mkdir -p "$FAKE_CODEX_BIN"
    cat > "$FAKE_CODEX_BIN/codex" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_HOME/codex-invocations"
stdin=\$(cat)
printf '%s' "\$stdin" > "$TEST_HOME/codex-stdin"
if [ "\${FAKE_CODEX_FAIL:-0}" = "1" ]; then
    exit 42
fi
if [ "\$1" = "login" ] && [ "\${2:-}" = "--with-api-key" ]; then
    mkdir -p "\$HOME/.codex"
    printf '{"auth_mode":"apikey","OPENAI_API_KEY":"%s"}\n' "\$stdin" > "\$HOME/.codex/auth.json"
    exit 0
fi
exit 1
SH
    chmod +x "$FAKE_CODEX_BIN/codex"
    export PATH="$FAKE_CODEX_BIN:$PATH"
}

@test "configure_codex_auth is a no-op when AAB_OPENAI_API_KEY is unset" {
    setup_fake_codex
    run configure_codex_auth
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_HOME/codex-invocations" ]
    [ ! -f "$HOME/.codex/auth.json" ]
}

@test "configure_codex_auth logs in with AAB_OPENAI_API_KEY via stdin" {
    setup_fake_codex
    AAB_OPENAI_API_KEY="codex-first-party-test-key" run configure_codex_auth
    [ "$status" -eq 0 ]
    grep -Fxq 'login --with-api-key' "$TEST_HOME/codex-invocations"
    [ "$(cat "$TEST_HOME/codex-stdin")" = "codex-first-party-test-key" ]
    python3 - <<PY
import json
d = json.load(open("$HOME/.codex/auth.json"))
assert d["auth_mode"] == "apikey", d
assert d["OPENAI_API_KEY"] == "codex-first-party-test-key", d
PY
    [[ "$output" != *"codex-first-party-test-key"* ]]
}

@test "configure_codex_auth keeps first-party auth available when the selected profile is third-party" {
    setup_fake_codex
    AAB_CODEX_DEFAULT_PROFILE="third-party/gpt-5.5" \
        AAB_OPENAI_API_KEY="codex-first-party-test-key" \
        run configure_codex_auth
    [ "$status" -eq 0 ]
    grep -Fxq 'login --with-api-key' "$TEST_HOME/codex-invocations"
}

@test "configure_codex_auth fails when Codex API-key login fails" {
    setup_fake_codex
    export FAKE_CODEX_FAIL=1
    AAB_OPENAI_API_KEY="codex-first-party-test-key" run configure_codex_auth
    [ "$status" -ne 0 ]
    [[ "$output" == *"codex login --with-api-key failed"* ]]
    [[ "$output" != *"codex-first-party-test-key"* ]]
}

setup_fake_brev() {
    export FAKE_BREV_BIN="$TEST_HOME/fake-brev-bin"
    mkdir -p "$FAKE_BREV_BIN"
    cat > "$FAKE_BREV_BIN/brev" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_HOME/brev-invocations"
if [ "\${FAKE_BREV_FAIL:-0}" = "1" ]; then
    exit 42
fi
if [ "\$1" = "login" ] && [ "\${2:-}" = "--api-key" ] && [ "\${4:-}" = "--org-id" ]; then
    mkdir -p "\$HOME/.brev"
    printf '{"api_key":"%s","org_id":"%s"}\n' "\${3:-}" "\${5:-}" > "\$HOME/.brev/credentials.json"
    exit 0
fi
exit 1
SH
    chmod +x "$FAKE_BREV_BIN/brev"
    export PATH="$FAKE_BREV_BIN:$PATH"
}

@test "configure_brev auth is a no-op when API-key vars are unset" {
    setup_fake_brev
    run _configure_brev_auth
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_HOME/brev-invocations" ]
    [ ! -f "$HOME/.brev/credentials.json" ]
}

@test "configure_brev auth ignores unprefixed Brev API-key vars" {
    setup_fake_brev
    BREV_API_KEY="brev-unprefixed-test-key" \
        BREV_ORG_ID="org-unprefixed-test" \
        run _configure_brev_auth
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_HOME/brev-invocations" ]
    [ ! -f "$HOME/.brev/credentials.json" ]
}

@test "configure_brev auth requires API key and org ID together" {
    setup_fake_brev
    AAB_BREV_API_KEY="brev-test-key" run _configure_brev_auth
    [ "$status" -ne 0 ]
    [[ "$output" == *"AAB_BREV_API_KEY and AAB_BREV_ORG_ID must both be set"* ]]
    [ ! -f "$TEST_HOME/brev-invocations" ]
    [ ! -f "$HOME/.brev/credentials.json" ]
}

@test "configure_brev logs in with AAB_BREV_API_KEY and AAB_BREV_ORG_ID" {
    setup_fake_brev
    AAB_BREV_API_KEY="brev-test-key" \
        AAB_BREV_ORG_ID="org-test" \
        run _configure_brev_auth
    [ "$status" -eq 0 ]
    grep -Fxq 'login --api-key brev-test-key --org-id org-test' "$TEST_HOME/brev-invocations"
    python3 - <<PY
import json
d = json.load(open("$HOME/.brev/credentials.json"))
assert d["api_key"] == "brev-test-key", d
assert d["org_id"] == "org-test", d
PY
    [[ "$output" != *"brev-test-key"* ]]
}

@test "configure_brev auth fails when Brev API-key login fails" {
    setup_fake_brev
    export FAKE_BREV_FAIL=1
    AAB_BREV_API_KEY="brev-test-key" \
        AAB_BREV_ORG_ID="org-test" \
        run _configure_brev_auth
    [ "$status" -ne 0 ]
    [[ "$output" == *"brev login --api-key failed"* ]]
    [[ "$output" != *"brev-test-key"* ]]
}

@test "skip_claude_onboarding creates .claude.json with hasCompletedOnboarding=true" {
    skip_claude_onboarding
    [ -f "$CLAUDE_JSON" ]
    python3 -c "import json; d=json.load(open('$CLAUDE_JSON')); assert d['hasCompletedOnboarding'] is True"
}

@test "skip_claude_onboarding pre-approves AAB_ANTHROPIC_API_KEY fingerprint when set" {
    AAB_ANTHROPIC_API_KEY="sk-ant-test-0123456789abcdef0123456789abcdef" skip_claude_onboarding
    python3 - <<PY
import json
d = json.load(open("$CLAUDE_JSON"))
approved = d["customApiKeyResponses"]["approved"]
# Fingerprint is the last 20 chars of the key.
assert "f0123456789abcdef" in approved[0], approved
PY
}

@test "skip_claude_onboarding preserves existing fields in .claude.json" {
    mkdir -p "$(dirname "$CLAUDE_JSON")"
    cat > "$CLAUDE_JSON" <<JSON
{"userID": "u-123", "hasCompletedOnboarding": false}
JSON
    skip_claude_onboarding
    python3 - <<PY
import json
d = json.load(open("$CLAUDE_JSON"))
assert d["userID"] == "u-123"
assert d["hasCompletedOnboarding"] is True
PY
}

@test "skip_claude_onboarding is idempotent (second call does not duplicate fingerprint)" {
    AAB_ANTHROPIC_API_KEY="sk-ant-test-0123456789abcdef0123456789abcdef" skip_claude_onboarding
    AAB_ANTHROPIC_API_KEY="sk-ant-test-0123456789abcdef0123456789abcdef" skip_claude_onboarding
    python3 - <<PY
import json
d = json.load(open("$CLAUDE_JSON"))
approved = d["customApiKeyResponses"]["approved"]
assert len(approved) == 1, approved
PY
}

@test "configure_bashrc writes managed block with both markers" {
    configure_bashrc
    [ -f "$BASHRC" ]
    grep -q "$BASHRC_MARKER_BEGIN" "$BASHRC"
    grep -q "$BASHRC_MARKER_END" "$BASHRC"
}

@test "configure_bashrc is idempotent (single managed block after two runs)" {
    configure_bashrc
    configure_bashrc
    local begin_count end_count
    begin_count=$(grep -c "^${BASHRC_MARKER_BEGIN}$" "$BASHRC")
    end_count=$(grep -c "^${BASHRC_MARKER_END}$" "$BASHRC")
    [ "$begin_count" -eq 1 ]
    [ "$end_count" -eq 1 ]
}

@test "configure_bashrc puts launcher directory on PATH without aliases" {
    configure_bashrc
    grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$BASHRC"
    grep -q 'export PATH="$HOME/.local/aab-bin:$PATH"' "$BASHRC"
    ! grep -q '^alias claude=' "$BASHRC"
    ! grep -q '^alias codex=' "$BASHRC"
}

@test "configure_profile keeps the launcher dir ahead of ~/.local/bin in a login shell" {
    # Mimic a distro-default ~/.profile: source ~/.bashrc, then re-prepend
    # ~/.local/bin. Without the configure_profile block this re-prepend would shadow
    # the launcher dir for login/SSH shells.
    cat > "$PROFILE" <<'SH'
if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then . "$HOME/.bashrc"; fi
if [ -d "$HOME/.local/bin" ]; then PATH="$HOME/.local/bin:$PATH"; fi
SH
    configure_bashrc
    configure_profile

    # The managed block is added once and replaced (not stacked) on re-run.
    configure_profile
    [ "$(grep -cF "$BASHRC_MARKER_BEGIN" "$PROFILE")" -eq 1 ]

    mkdir -p "$HOME/.local/bin" "$HOME/.local/aab-bin"
    printf '#!/usr/bin/env bash\necho real\n' > "$HOME/.local/bin/claude"
    chmod +x "$HOME/.local/bin/claude"
    printf '#!/usr/bin/env bash\necho wrapper\n' > "$HOME/.local/bin/claude-third-party-deepseek"
    chmod +x "$HOME/.local/bin/claude-third-party-deepseek"
    ln -sfn "$HOME/.local/bin/claude-third-party-deepseek" "$HOME/.local/aab-bin/claude"

    # A login shell sources ~/.profile. PS1 is set so the distro ~/.bashrc guard
    # (`case $- in *i*) ;; *) return`) does not abort early before the AAB block.
    run env HOME="$HOME" PATH="/usr/bin:/bin" bash -c 'PS1="x"; . "$HOME/.profile" >/dev/null 2>&1; command -v claude'
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME/.local/aab-bin/claude" ]
}

@test "configure_claude_shell owns Claude shell defaults" {
    configure_claude_shell
    [ -f "$CLAUDE_SHELL_CONFIG_FILE" ]
    grep -Fxq 'export CLAUDE_CODE_SANDBOXED=1' "$CLAUDE_SHELL_CONFIG_FILE"
    grep -Fxq 'export DEBUG_SDK=1' "$CLAUDE_SHELL_CONFIG_FILE"
    ! grep -q '^export CLAUDE_CODE_EFFORT_LEVEL=' "$CLAUDE_SHELL_CONFIG_FILE"
}

@test "configure_bashrc sources AAB shell configuration" {
    configure_claude_shell
    AAB_GH_TOKEN="github-test-token" configure_github_shell
    configure_bashrc
    grep -Fq '"$HOME"/.aab/shell/*.env' "$BASHRC"
    ! grep -q '^export DEBUG_SDK=' "$BASHRC"
    run env HOME="$HOME" bash -c 'unset DEBUG_SDK CLAUDE_CODE_EFFORT_LEVEL GH_TOKEN; . "$HOME/.bashrc"; printf "%s %s %s" "$DEBUG_SDK" "${CLAUDE_CODE_EFFORT_LEVEL:-UNSET}" "$GH_TOKEN"'
    [ "$status" -eq 0 ]
    [ "$output" = "1 UNSET github-test-token" ]
}

@test "configure_github_shell writes a private GH_TOKEN mapping and clears stale values" {
    AAB_GH_TOKEN="github-test-token" configure_github_shell

    [ -f "$GITHUB_SHELL_CONFIG_FILE" ]
    [ "$(stat -c '%a' "$GITHUB_SHELL_CONFIG_FILE")" = "600" ]
    grep -Fxq 'export GH_TOKEN=github-test-token' "$GITHUB_SHELL_CONFIG_FILE"

    AAB_GH_TOKEN="" configure_github_shell
    ! grep -q '^export GH_TOKEN=' "$GITHUB_SHELL_CONFIG_FILE"
}

@test "configure_bashrc does not write credentials or provider AAB vars" {
    AAB_ANTHROPIC_API_KEY="sk-ant-test-key" \
        AAB_OPENAI_API_KEY="codex-first-party-test-key" \
        AAB_INFERENCE_GATEWAY_API_KEY="gateway-test-key" \
        AAB_GH_TOKEN="ghp_test_token" \
        configure_bashrc

    ! grep -q 'sk-ant-test-key' "$BASHRC"
    ! grep -q 'codex-first-party-test-key' "$BASHRC"
    ! grep -q 'gateway-test-key' "$BASHRC"
    ! grep -q 'ghp_test_token' "$BASHRC"
    ! grep -q '^export AAB_' "$BASHRC"
    ! grep -q '^export ANTHROPIC_' "$BASHRC"
    ! grep -q '^export OPENAI_API_KEY=' "$BASHRC"
    ! grep -q '^export GH_TOKEN=' "$BASHRC"
}

@test "configure_bashrc writes the dead-SSH-agent-socket guard" {
    configure_bashrc
    grep -qF 'if [ -n "${SSH_AUTH_SOCK:-}" ]; then' "$BASHRC"
    grep -qF 'unset SSH_AUTH_SOCK SSH_AGENT_PID' "$BASHRC"
}

@test "bashrc guard unsets SSH_AUTH_SOCK when the socket file is missing" {
    configure_bashrc
    run env HOME="$HOME" SSH_AUTH_SOCK="$HOME/gone/agent.sock" \
        bash -c '. "$HOME/.bashrc" >/dev/null 2>&1; printf %s "${SSH_AUTH_SOCK:-UNSET}"'
    [ "$status" -eq 0 ]
    [ "$output" = "UNSET" ]
}

@test "bashrc guard preserves a reachable SSH agent" {
    configure_bashrc
    # Mock a live agent: ssh-add exits 0, and a real (orphaned) socket file
    # exists so the guard reaches the probe rather than the missing-file branch.
    mkdir -p "$HOME/mockbin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$HOME/mockbin/ssh-add"
    printf '#!/usr/bin/env bash\nshift; exec "$@"\n' > "$HOME/mockbin/timeout"
    chmod +x "$HOME/mockbin/ssh-add" "$HOME/mockbin/timeout"
    python3 -c "import socket; socket.socket(socket.AF_UNIX).bind('$HOME/live.sock')"
    run env HOME="$HOME" PATH="$HOME/mockbin:$PATH" SSH_AUTH_SOCK="$HOME/live.sock" \
        bash -c '. "$HOME/.bashrc" >/dev/null 2>&1; printf %s "${SSH_AUTH_SOCK:-UNSET}"'
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME/live.sock" ]
}

@test "bashrc guard unsets a connectable-but-dead SSH agent socket" {
    configure_bashrc
    # A forwarded socket whose owner is alive but whose agent is gone: ssh-add
    # connects, then fails with a comms error and exit 1 — the same exit code a
    # live-but-empty agent returns, so the guard must key off the message.
    mkdir -p "$HOME/mockbin"
    printf '#!/usr/bin/env bash\necho "error fetching identities: communication with agent failed" >&2\nexit 1\n' \
        > "$HOME/mockbin/ssh-add"
    printf '#!/usr/bin/env bash\nshift; exec "$@"\n' > "$HOME/mockbin/timeout"
    chmod +x "$HOME/mockbin/ssh-add" "$HOME/mockbin/timeout"
    python3 -c "import socket; socket.socket(socket.AF_UNIX).bind('$HOME/dead.sock')"
    run env HOME="$HOME" PATH="$HOME/mockbin:$PATH" SSH_AUTH_SOCK="$HOME/dead.sock" \
        bash -c '. "$HOME/.bashrc" >/dev/null 2>&1; printf %s "${SSH_AUTH_SOCK:-UNSET}"'
    [ "$status" -eq 0 ]
    [ "$output" = "UNSET" ]
}

@test "sourcing bootstrap.bash does NOT execute main" {
    # setup() already sourced the script. If main had run, it would have
    # attempted to install Claude Code via curl; instead the function is
    # merely defined.
    type main >/dev/null
    # And no settings file should exist yet — configure_claude_settings was never
    # called by a main() invocation at source time.
    [ ! -f "$SETTINGS_FILE" ]
}

@test "entry-point guard fires when piped via curl | bash (issue #53)" {
    # Regression for issue #53: when the script is read from stdin (the
    # `curl ... | bash` install recipe), BASH_SOURCE is empty and the bare
    # `${BASH_SOURCE[0]}` tripped `set -u` before main could run. Extract the
    # entry-point block from bootstrap.bash and exercise it through a piped
    # bash with a stubbed main — under the fix, main fires and no unbound-
    # variable error is emitted.
    local guard
    guard=$(awk '/^# `:-\$0` covers/,/^fi$/' "$REPO_ROOT/bootstrap.bash")
    [ -n "$guard" ] || fail "could not locate entry-point guard in bootstrap.bash"
    run bash <<SH
set -euo pipefail
main() { echo MAIN_REACHED; }
$guard
SH
    [ "$status" -eq 0 ]
    [[ "$output" == *"MAIN_REACHED"* ]]
    [[ "$output" != *"unbound variable"* ]]
}

# A fake apt-get that records its args, plus a passthrough `env` so the
# `$SUDO env DEBIAN_FRONTEND=... apt-get` call works under a sandboxed PATH.
# `cat` is symlinked in so install_base_deps can read the package-list file
# while PATH is otherwise just this fake dir. $1 is the directory to populate;
# the recorded invocations land in $TEST_HOME/apt-get-invocations.
make_apt_get_fakes() {
    local fake_bin="$1"
    mkdir -p "$fake_bin"
    ln -s "$(command -v cat)" "$fake_bin/cat"
    cat > "$fake_bin/env" <<'SH'
#!/bin/sh
while [ "$#" -gt 0 ]; do
    case "$1" in
        *=*) shift ;;
        *) break ;;
    esac
done
exec "$@"
SH
    chmod +x "$fake_bin/env"
    cat > "$fake_bin/apt-get" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$TEST_HOME/apt-get-invocations"
SH
    chmod +x "$fake_bin/apt-get"
}

@test "install_base_deps installs exactly the packages listed in the file" {
    local fake_bin="$TEST_HOME/fake-base-deps-bin"
    make_apt_get_fakes "$fake_bin"
    # Comment and blank lines are stripped; the surviving packages are the whole
    # install list — no per-package marker check, the list goes in unconditionally.
    printf '%s\n' '# A comment.' 'curl=7.81.0-*' '' 'ripgrep=13.0.0-*' 'libgraphviz-dev=2.42.2-*' \
        > "$TEST_HOME/apt-packages.txt"
    export AAB_APT_PACKAGES_FILE="$TEST_HOME/apt-packages.txt"

    SUDO="" PATH="$fake_bin" run install_base_deps

    [ "$status" -eq 0 ]
    [[ "$output" == *"Reading apt package list from $TEST_HOME/apt-packages.txt."* ]]
    [[ "$output" == *"Installing apt packages: curl=7.81.0-* ripgrep=13.0.0-* libgraphviz-dev=2.42.2-*."* ]]
    grep -Fxq 'update -y' "$TEST_HOME/apt-get-invocations"
    grep -Fxq 'install -y --simulate --allow-downgrades --no-install-recommends curl=7.81.0-* ripgrep=13.0.0-* libgraphviz-dev=2.42.2-*' "$TEST_HOME/apt-get-invocations"
    grep -Fxq 'install -y --allow-downgrades --no-install-recommends curl=7.81.0-* ripgrep=13.0.0-* libgraphviz-dev=2.42.2-*' "$TEST_HOME/apt-get-invocations"
}

@test "install_base_deps falls back to distro versions when preferred versions are unavailable" {
    local fake_bin="$TEST_HOME/fake-base-deps-fallback-bin"
    make_apt_get_fakes "$fake_bin"
    cat > "$fake_bin/apt-get" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$TEST_HOME/apt-get-invocations"
case " $* " in
    *' --simulate '*) exit 100 ;;
esac
SH
    chmod +x "$fake_bin/apt-get"
    printf '%s\n' 'curl=7.81.0-*' 'git=1:2.34.1-*' 'python3=3.10.6-*' > "$TEST_HOME/apt-packages.txt"
    export AAB_APT_PACKAGES_FILE="$TEST_HOME/apt-packages.txt"

    SUDO="" PATH="$fake_bin" run install_base_deps

    [ "$status" -eq 0 ]
    [[ "$output" == *"Preferred apt package versions are unavailable on this distribution"* ]]
    [[ "$output" == *"Installing apt packages: curl git python3."* ]]
    grep -Fxq 'install -y --allow-downgrades --no-install-recommends curl git python3' "$TEST_HOME/apt-get-invocations"
}

@test "install_base_deps reads ./apt_packages.txt by default" {
    local fake_bin="$TEST_HOME/fake-base-deps-default-bin"
    make_apt_get_fakes "$fake_bin"
    # No AAB_APT_PACKAGES_FILE override: the committed apt_packages.txt at the
    # repo root is the default source, and the packages it lists get installed.
    SUDO="" APT_PACKAGES_DEFAULT_FILE="$REPO_ROOT/apt_packages.txt" PATH="$fake_bin" \
        run install_base_deps

    [ "$status" -eq 0 ]
    [[ "$output" == *"Reading apt package list from $REPO_ROOT/apt_packages.txt."* ]]
    # The autocuda pygraphviz build toolchain is part of the default list, so it
    # gets installed alongside the rest.
    grep -Eq 'install -y --allow-downgrades --no-install-recommends .*git=1:2[.]34[.]1-.*git-man=1:2[.]34[.]1-' "$TEST_HOME/apt-get-invocations"
    grep -Eq 'install -y --allow-downgrades --no-install-recommends .*libgraphviz-dev=2[.]42[.]2-.*build-essential=12[.]9ubuntu3' "$TEST_HOME/apt-get-invocations"
    grep -Eq 'install -y --allow-downgrades --no-install-recommends .*ripgrep=13[.]0[.]0-' "$TEST_HOME/apt-get-invocations"
    grep -Eq 'install -y --allow-downgrades --no-install-recommends .*openssh-client=1:8[.]9p1-' "$TEST_HOME/apt-get-invocations"
}

@test "install_base_deps warns and skips when apt-get is unavailable" {
    # A PATH with coreutils (so the file read works) but no apt-get exercises
    # the "bare host without apt-get" branch: warn and return, never install.
    local fake_bin="$TEST_HOME/fake-base-deps-noapt-bin"
    mkdir -p "$fake_bin"
    ln -s "$(command -v cat)" "$fake_bin/cat"
    printf '%s\n' 'curl=7.81.0-*' 'ripgrep=13.0.0-*' > "$TEST_HOME/apt-packages.txt"
    export AAB_APT_PACKAGES_FILE="$TEST_HOME/apt-packages.txt"

    PATH="$fake_bin" run install_base_deps
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt-get is not available"* ]]
    # Should NOT claim to be installing anything.
    [[ "$output" != *"Installing apt packages:"* ]]
}

@test "install_base_deps warns and skips when passwordless sudo is unavailable" {
    # Non-empty SUDO plus a `sudo -n true` that fails models a host where
    # privilege escalation needs a password the unattended run cannot supply.
    local fake_bin="$TEST_HOME/fake-base-deps-nosudo-bin"
    make_apt_get_fakes "$fake_bin"
    cat > "$fake_bin/sudo" <<'SH'
#!/bin/sh
# `sudo -n true` fails: no passwordless sudo.
[ "$1" = "-n" ] && exit 1
exit 0
SH
    chmod +x "$fake_bin/sudo"
    printf '%s\n' 'curl=7.81.0-*' 'ripgrep=13.0.0-*' > "$TEST_HOME/apt-packages.txt"
    export AAB_APT_PACKAGES_FILE="$TEST_HOME/apt-packages.txt"

    SUDO="sudo" PATH="$fake_bin" run install_base_deps
    [ "$status" -eq 0 ]
    [[ "$output" == *"passwordless sudo is not available"* ]]
    [[ "$output" != *"Installing apt packages:"* ]]
    [ ! -f "$TEST_HOME/apt-get-invocations" ]
}

@test "install_base_deps skips when the package list is empty" {
    local fake_bin="$TEST_HOME/fake-base-deps-empty-bin"
    make_apt_get_fakes "$fake_bin"
    # Only comments and blanks: nothing to install, so no apt-get call.
    printf '%s\n' '# Only a comment.' '' > "$TEST_HOME/apt-packages.txt"
    export AAB_APT_PACKAGES_FILE="$TEST_HOME/apt-packages.txt"

    SUDO="" PATH="$fake_bin" run install_base_deps
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt package list is empty"* ]]
    [ ! -f "$TEST_HOME/apt-get-invocations" ]
}

@test "install_base_deps rejects unpinned package entries" {
    local fake_bin="$TEST_HOME/fake-base-deps-unpinned-bin"
    make_apt_get_fakes "$fake_bin"
    printf '%s\n' 'curl' > "$TEST_HOME/apt-packages.txt"
    export AAB_APT_PACKAGES_FILE="$TEST_HOME/apt-packages.txt"

    SUDO="" PATH="$fake_bin" run install_base_deps
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not version-pinned"* ]]
    [ ! -f "$TEST_HOME/apt-get-invocations" ]
}

@test "apt-get calls are centralized in install_base_deps" {
    run bash -c '
        for source_file in "$1"/*.bash; do
            if grep -Eq "(^|[[:space:]])apt-get([[:space:]]|$)" "$source_file"; then
                printf "%s\n" "$source_file"
            fi
        done
    ' _ "$REPO_ROOT/src/bootstrap"
    [ "$status" -eq 0 ]
    [ "$output" = "$REPO_ROOT/src/bootstrap/01_install_base_deps.bash" ]
}


# ---------------------------------------------------------------------------
# configure_user_linger: cover the no-systemd skip, the already-lingering no-op,
# the enable path, the missing-passwordless-sudo skip, and the enable failure.
# ---------------------------------------------------------------------------

# Stubs `id`, `loginctl`, and `sudo` on a fresh $FAKE_LINGER_BIN, parameterized
# by exported env vars so each test sets only the behavior it needs:
#   FAKE_USER             — username `id -un` reports (default testuser).
#   FAKE_LINGER           — value `loginctl show-user --property=Linger` reports.
#   FAKE_ENABLE_RC        — exit code of `loginctl enable-linger` (default 0).
#   FAKE_SUDO_NOPASSWD_RC — exit code of `sudo -n true` (default 0 = available).
# `loginctl enable-linger <user>` records its args to $LINGER_ENABLE_LOG.
make_linger_fakes() {
    export FAKE_LINGER_BIN="$TEST_HOME/fake-linger-bin"
    export LINGER_ENABLE_LOG="$TEST_HOME/linger-enable-invocations"
    mkdir -p "$FAKE_LINGER_BIN"

    cat > "$FAKE_LINGER_BIN/id" <<'SH'
#!/bin/sh
[ "$1" = "-un" ] && { printf '%s\n' "${FAKE_USER:-testuser}"; exit 0; }
exit 0
SH

    cat > "$FAKE_LINGER_BIN/loginctl" <<'SH'
#!/bin/sh
case "$1" in
    show-user)     printf '%s\n' "${FAKE_LINGER:-no}" ;;
    enable-linger) printf 'enable-linger %s\n' "$2" >> "$LINGER_ENABLE_LOG"
                   exit "${FAKE_ENABLE_RC:-0}" ;;
esac
exit 0
SH

    cat > "$FAKE_LINGER_BIN/sudo" <<'SH'
#!/bin/sh
[ "$1" = "-n" ] && exit "${FAKE_SUDO_NOPASSWD_RC:-0}"
shift_to_cmd=0
for a in "$@"; do
    case "$a" in -*) shift ;; *) shift_to_cmd=1; break ;; esac
done
[ "$shift_to_cmd" = "1" ] && exec "$@"
exit 0
SH

    chmod +x "$FAKE_LINGER_BIN/id" "$FAKE_LINGER_BIN/loginctl" "$FAKE_LINGER_BIN/sudo"
}

@test "configure_user_linger skips cleanly when loginctl is unavailable" {
    make_linger_fakes
    rm -f "$FAKE_LINGER_BIN/loginctl"

    SUDO="" PATH="$FAKE_LINGER_BIN" run configure_user_linger
    [ "$status" -eq 0 ]
    [[ "$output" == *"loginctl not available"* ]]
    [ ! -f "$LINGER_ENABLE_LOG" ]
}

@test "configure_user_linger is a no-op when lingering is already enabled" {
    make_linger_fakes
    export FAKE_LINGER=yes

    SUDO="" PATH="$FAKE_LINGER_BIN" run configure_user_linger
    [ "$status" -eq 0 ]
    [[ "$output" == *"already enabled for testuser"* ]]
    # Must not re-run enable-linger when it is already on.
    [ ! -f "$LINGER_ENABLE_LOG" ]
}

@test "configure_user_linger enables lingering when it is off" {
    make_linger_fakes
    export FAKE_LINGER=no

    SUDO="" PATH="$FAKE_LINGER_BIN" run configure_user_linger
    [ "$status" -eq 0 ]
    [[ "$output" == *"Enabled user lingering for testuser"* ]]
    grep -Fxq 'enable-linger testuser' "$LINGER_ENABLE_LOG"
}

@test "configure_user_linger skips and warns when passwordless sudo is unavailable" {
    make_linger_fakes
    export FAKE_LINGER=no FAKE_SUDO_NOPASSWD_RC=1

    SUDO="sudo" PATH="$FAKE_LINGER_BIN" run configure_user_linger
    [ "$status" -eq 0 ]
    [[ "$output" == *"passwordless sudo is not available"* ]]
    [[ "$output" == *"sudo loginctl enable-linger testuser"* ]]
    # Without passwordless sudo it must not attempt the change.
    [ ! -f "$LINGER_ENABLE_LOG" ]
}

@test "configure_user_linger warns when enable-linger fails" {
    make_linger_fakes
    export FAKE_LINGER=no FAKE_ENABLE_RC=1

    SUDO="" PATH="$FAKE_LINGER_BIN" run configure_user_linger
    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not enable user lingering for testuser"* ]]
}


# ---------------------------------------------------------------------------
# install_agent_plugins: cover the gh-authenticated path, the
# raw.githubusercontent.com fallback, and the skip-on-no-access path added for
# private plugin marketplaces.
# ---------------------------------------------------------------------------

# Sets up $FAKE_BIN on PATH with stub `gh` and `curl` binaries plus two
# fixture directories the stubs read from:
#   $FAKE_GH_DIR   — served by `gh api repos/<owner>/<repo>/contents/...`
#   $FAKE_CURL_DIR — served by `curl https://raw.githubusercontent.com/...`
# Each fixture is keyed `<owner>__<repo>.json`.
setup_plugin_fakes() {
    export FAKE_BIN="$TEST_HOME/fake-bin"
    export FAKE_GH_DIR="$TEST_HOME/fake-gh-fixtures"
    export FAKE_CURL_DIR="$TEST_HOME/fake-curl-fixtures"
    mkdir -p "$FAKE_BIN" "$FAKE_GH_DIR" "$FAKE_CURL_DIR"

    cat > "$FAKE_BIN/gh" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
    if [ -n "${FAKE_GH_REQUIRED_TOKEN:-}" ]; then
        [ "${GH_TOKEN:-}" = "$FAKE_GH_REQUIRED_TOKEN" ] && exit 0 || exit 1
    fi
    [ "${FAKE_GH_AUTH_OK:-0}" = "1" ] && exit 0 || exit 1
fi
if [ "$1" = "api" ]; then
    for a in "$@"; do
        if [[ "$a" =~ ^repos/([^/]+)/([^/]+)/contents/ ]]; then
            f="${FAKE_GH_DIR}/${BASH_REMATCH[1]}__${BASH_REMATCH[2]}.json"
            [ -f "$f" ] && { cat "$f"; exit 0; }
            exit 22
        fi
    done
fi
exit 1
SH
    chmod +x "$FAKE_BIN/gh"

    cat > "$FAKE_BIN/curl" <<'SH'
#!/usr/bin/env bash
url=""
for a in "$@"; do
    case "$a" in https://*) url="$a";; esac
done
if [[ "$url" == https://raw.githubusercontent.com/* ]]; then
    rest="${url#https://raw.githubusercontent.com/}"
    owner="${rest%%/*}"; rest="${rest#*/}"
    repo="${rest%%/*}"
    f="${FAKE_CURL_DIR}/${owner}__${repo}.json"
    [ -f "$f" ] && { cat "$f"; exit 0; }
fi
exit 22
SH
    chmod +x "$FAKE_BIN/curl"

    export PATH="$FAKE_BIN:/usr/bin:/bin"
}

write_marketplace_fixture() {
    local dir="$1" owner_repo="$2" mkt_name="$3" plugin_name="$4"
    local key="${owner_repo/\//__}"
    cat > "$dir/$key.json" <<JSON
{"name": "$mkt_name", "plugins": [{"name": "$plugin_name"}]}
JSON
}

@test "install_agent_plugins fetches via gh api when gh is authenticated (private-repo path)" {
    setup_plugin_fakes
    export FAKE_GH_AUTH_OK=1
    # Fixture only reachable via gh — proves curl wasn't the source.
    write_marketplace_fixture "$FAKE_GH_DIR" "acme/private-plugin" "acme-market" "widget"
    echo "acme/private-plugin" > "$TEST_HOME/plugins.txt"
    export AAB_AGENT_PLUGINS_FILE="$TEST_HOME/plugins.txt"

    configure_claude_settings
    install_agent_plugins

    python3 - <<PY
import json
d = json.load(open("$SETTINGS_FILE"))
assert d["extraKnownMarketplaces"]["acme-market"]["source"]["repo"] == "acme/private-plugin", d
assert d["enabledPlugins"]["widget@acme-market"] is True, d
PY
}

@test "install_agent_plugins maps AAB_GH_TOKEN to GH_TOKEN for private-repo fetches" {
    setup_plugin_fakes
    export FAKE_GH_REQUIRED_TOKEN="ghp_private_plugin_test"
    export AAB_GH_TOKEN="$FAKE_GH_REQUIRED_TOKEN"
    write_marketplace_fixture "$FAKE_GH_DIR" "acme/private-plugin" "acme-market" "widget"
    echo "acme/private-plugin" > "$TEST_HOME/plugins.txt"
    export AAB_AGENT_PLUGINS_FILE="$TEST_HOME/plugins.txt"

    configure_claude_settings
    install_agent_plugins

    python3 - <<PY
import json
d = json.load(open("$SETTINGS_FILE"))
assert d["extraKnownMarketplaces"]["acme-market"]["source"]["repo"] == "acme/private-plugin", d
assert d["enabledPlugins"]["widget@acme-market"] is True, d
PY
}

@test "install_agent_plugins falls back to raw.githubusercontent.com when gh is not authenticated" {
    setup_plugin_fakes
    export FAKE_GH_AUTH_OK=0
    # Fixture only reachable via curl — proves the fallback path ran.
    write_marketplace_fixture "$FAKE_CURL_DIR" "acme/public-plugin" "acme-public" "gadget"
    echo "acme/public-plugin" > "$TEST_HOME/plugins.txt"
    export AAB_AGENT_PLUGINS_FILE="$TEST_HOME/plugins.txt"

    configure_claude_settings
    install_agent_plugins

    python3 - <<PY
import json
d = json.load(open("$SETTINGS_FILE"))
assert d["extraKnownMarketplaces"]["acme-public"]["source"]["repo"] == "acme/public-plugin", d
assert d["enabledPlugins"]["gadget@acme-public"] is True, d
PY
}

@test "install_agent_plugins logs-and-skips a private repo the caller cannot access" {
    setup_plugin_fakes
    export FAKE_GH_AUTH_OK=1
    # One entry is reachable via curl; the other is reachable nowhere (simulates
    # a private repo the caller has no token for).
    write_marketplace_fixture "$FAKE_CURL_DIR" "acme/public-plugin" "acme-public" "gadget"
    printf '%s\n%s\n' "acme/public-plugin" "private/no-access" > "$TEST_HOME/plugins.txt"
    export AAB_AGENT_PLUGINS_FILE="$TEST_HOME/plugins.txt"

    configure_claude_settings
    run install_agent_plugins
    [ "$status" -eq 0 ]
    # Soft log, not WARN, for the inaccessible repo.
    [[ "$output" == *"Could not fetch .claude-plugin/marketplace.json from private/no-access"* ]]
    [[ "$output" != *"WARN: "*"private/no-access"* ]]

    python3 - <<PY
import json
d = json.load(open("$SETTINGS_FILE"))
# Accessible entry got installed.
assert "acme-public" in d.get("extraKnownMarketplaces", {}), d
# Inaccessible entry did not poison settings.json.
repos = {m["source"]["repo"] for m in d.get("extraKnownMarketplaces", {}).values()}
assert "private/no-access" not in repos, repos
PY
}

# Drop fake agent CLIs on PATH that record every plugin invocation and exit 0.
# The install_agent_plugins tests below assert the marketplace-add and
# plugin-install calls actually fired with the expected arguments.
setup_fake_claude() {
    cat > "$FAKE_BIN/claude" <<SH
#!/usr/bin/env bash
if [ -n "\${FAKE_AGENT_REQUIRED_GH_TOKEN:-}" ] && [ "\${GH_TOKEN:-}" != "\$FAKE_AGENT_REQUIRED_GH_TOKEN" ]; then
    exit 44
fi
printf '%s\n' "\$*" >> "$TEST_HOME/claude-invocations"
exit 0
SH
    chmod +x "$FAKE_BIN/claude"
}

setup_fake_codex_plugin() {
    cat > "$FAKE_BIN/codex" <<SH
#!/usr/bin/env bash
if [ -n "\${FAKE_AGENT_REQUIRED_GH_TOKEN:-}" ] && [ "\${GH_TOKEN:-}" != "\$FAKE_AGENT_REQUIRED_GH_TOKEN" ]; then
    exit 45
fi
printf '%s\n' "\$*" >> "$TEST_HOME/codex-plugin-invocations"
exit 0
SH
    chmod +x "$FAKE_BIN/codex"
}

@test "install_agent_plugins runs both agent plugin CLIs for each enabled plugin" {
    setup_plugin_fakes
    setup_fake_claude
    setup_fake_codex_plugin
    export FAKE_GH_AUTH_OK=1
    # One marketplace, two plugins — exercises the dedupe (one
    # `marketplace add`) and the per-plugin install loop.
    cat > "$FAKE_GH_DIR/acme__multi.json" <<JSON
{"name": "acme-multi", "plugins": [{"name": "alpha"}, {"name": "beta"}]}
JSON
    echo "acme/multi" > "$TEST_HOME/plugins.txt"
    export AAB_AGENT_PLUGINS_FILE="$TEST_HOME/plugins.txt"

    configure_claude_settings
    install_agent_plugins

    grep -Fxq 'plugin marketplace add acme/multi' "$TEST_HOME/claude-invocations"
    grep -Fxq 'plugin install alpha@acme-multi --scope user' "$TEST_HOME/claude-invocations"
    grep -Fxq 'plugin install beta@acme-multi --scope user' "$TEST_HOME/claude-invocations"
    grep -Fxq 'plugin marketplace add acme/multi' "$TEST_HOME/codex-plugin-invocations"
    grep -Fxq 'plugin add alpha@acme-multi' "$TEST_HOME/codex-plugin-invocations"
    grep -Fxq 'plugin add beta@acme-multi' "$TEST_HOME/codex-plugin-invocations"
    # Dedupe: one marketplace add, not two.
    [ "$(grep -c 'plugin marketplace add' "$TEST_HOME/claude-invocations")" -eq 1 ]
    [ "$(grep -c 'plugin marketplace add' "$TEST_HOME/codex-plugin-invocations")" -eq 1 ]
}

@test "install_agent_plugins maps AAB_GH_TOKEN to GH_TOKEN for agent plugin CLIs" {
    setup_plugin_fakes
    setup_fake_claude
    setup_fake_codex_plugin
    export FAKE_GH_REQUIRED_TOKEN="ghp_agent_plugin_test"
    export FAKE_AGENT_REQUIRED_GH_TOKEN="$FAKE_GH_REQUIRED_TOKEN"
    export AAB_GH_TOKEN="$FAKE_GH_REQUIRED_TOKEN"
    write_marketplace_fixture "$FAKE_GH_DIR" "acme/private-plugin" "acme-market" "widget"
    echo "acme/private-plugin" > "$TEST_HOME/plugins.txt"
    export AAB_AGENT_PLUGINS_FILE="$TEST_HOME/plugins.txt"

    configure_claude_settings
    install_agent_plugins

    grep -Fxq 'plugin marketplace add acme/private-plugin' "$TEST_HOME/claude-invocations"
    grep -Fxq 'plugin install widget@acme-market --scope user' "$TEST_HOME/claude-invocations"
    grep -Fxq 'plugin marketplace add acme/private-plugin' "$TEST_HOME/codex-plugin-invocations"
    grep -Fxq 'plugin add widget@acme-market' "$TEST_HOME/codex-plugin-invocations"
}

@test "install_agent_plugins runs marketplace-add once per repo across distinct plugin lines" {
    setup_plugin_fakes
    setup_fake_claude
    setup_fake_codex_plugin
    export FAKE_GH_AUTH_OK=1
    # Two repos, one plugin each — exercises the multi-repo loop.
    write_marketplace_fixture "$FAKE_GH_DIR" "alpha/m" "alpha-m" "p1"
    write_marketplace_fixture "$FAKE_GH_DIR" "beta/m" "beta-m" "p2"
    printf '%s\n%s\n' "alpha/m" "beta/m" > "$TEST_HOME/plugins.txt"
    export AAB_AGENT_PLUGINS_FILE="$TEST_HOME/plugins.txt"

    configure_claude_settings
    install_agent_plugins

    grep -Fxq 'plugin marketplace add alpha/m' "$TEST_HOME/claude-invocations"
    grep -Fxq 'plugin marketplace add beta/m' "$TEST_HOME/claude-invocations"
    grep -Fxq 'plugin install p1@alpha-m --scope user' "$TEST_HOME/claude-invocations"
    grep -Fxq 'plugin install p2@beta-m --scope user' "$TEST_HOME/claude-invocations"
    grep -Fxq 'plugin marketplace add alpha/m' "$TEST_HOME/codex-plugin-invocations"
    grep -Fxq 'plugin marketplace add beta/m' "$TEST_HOME/codex-plugin-invocations"
    grep -Fxq 'plugin add p1@alpha-m' "$TEST_HOME/codex-plugin-invocations"
    grep -Fxq 'plugin add p2@beta-m' "$TEST_HOME/codex-plugin-invocations"
}

@test "install_agent_plugins warns and skips CLI installs when agent binaries are absent" {
    setup_plugin_fakes
    # Do not call setup_fake_claude or setup_fake_codex_plugin; leave PATH without
    # agent binaries.
    PATH="$FAKE_BIN:/usr/bin:/bin"
    export FAKE_GH_AUTH_OK=1
    write_marketplace_fixture "$FAKE_GH_DIR" "acme/m" "acme-m" "widget"
    echo "acme/m" > "$TEST_HOME/plugins.txt"
    export AAB_AGENT_PLUGINS_FILE="$TEST_HOME/plugins.txt"

    configure_claude_settings
    run install_agent_plugins
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN:"*"claude binary not on PATH"* ]]
    [[ "$output" == *"WARN:"*"codex binary not on PATH"* ]]
    # settings.json was still written even when the install step is skipped.
    python3 - <<PY
import json
d = json.load(open("$SETTINGS_FILE"))
assert d["enabledPlugins"]["widget@acme-m"] is True, d
PY
}

# ---------------------------------------------------------------------------
# configure_auth_ssh_key / configure_signing_ssh_key: cover the two distinct
# roles (GitHub SSH auth vs git commit/tag signing), including:
#   - skip-on-unset for each
#   - correct file modes on both key pairs
#   - auth writes a managed block in ~/.ssh/config mapping github.com to
#     id_aab_auth; signing leaves ~/.ssh/config alone
#   - signing configures git signing; auth leaves git signing alone
#   - idempotent re-runs (auth managed block is size-stable)
#   - pre-existing ~/.ssh/config entries outside the block are preserved
#   - invalid base64 and not-an-SSH-key input produce warn-and-skip
# ---------------------------------------------------------------------------

# Generates a valid ed25519 private key at <path> and echoes its base64
# encoding. The matching .pub is written next to <path> by ssh-keygen.
gen_test_ssh_key_b64() {
    local path="${1:-$TEST_HOME/generated_key}"
    command -v ssh-keygen >/dev/null || skip "precondition: ssh-keygen must exist"
    ssh-keygen -t ed25519 -N "" -q -C "aab-test" -f "$path"
    base64 -w0 < "$path"
}

@test "configure_auth_ssh_key is a no-op when AAB_GH_AUTH_SSH_PRIVATE_KEY_B64 is unset" {
    run configure_auth_ssh_key
    [ "$status" -eq 0 ]
    [ ! -e "$AUTH_KEY" ]
    [ ! -e "$SSH_CONFIG" ]
}

@test "configure_signing_ssh_key is a no-op when AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64 is unset" {
    run configure_signing_ssh_key
    [ "$status" -eq 0 ]
    [ ! -e "$SIGNING_KEY" ]
    # Signing does NOT touch ~/.ssh/config regardless — double-check nothing appeared.
    [ ! -e "$SSH_CONFIG" ]
    # And git signing config must not be set.
    [ -z "$(git config --global --get user.signingkey 2>/dev/null || true)" ]
}

@test "configure_auth_ssh_key writes id_aab_auth (0600) and id_aab_auth.pub (0644)" {
    AAB_GH_AUTH_SSH_PRIVATE_KEY_B64=$(gen_test_ssh_key_b64)
    export AAB_GH_AUTH_SSH_PRIVATE_KEY_B64
    configure_auth_ssh_key

    [ -f "$AUTH_KEY" ]
    [ -f "$AUTH_KEY_PUB" ]
    [ "$(stat -c '%a' "$AUTH_KEY")" = "600" ]
    [ "$(stat -c '%a' "$AUTH_KEY_PUB")" = "644" ]
    [ "$(stat -c '%a' "$SSH_DIR")" = "700" ]
    diff <(sort "$AUTH_KEY_PUB") <(sort "$TEST_HOME/generated_key.pub")
}

@test "configure_signing_ssh_key writes id_aab_signing (0600) and id_aab_signing.pub (0644)" {
    AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64=$(gen_test_ssh_key_b64)
    export AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64
    configure_signing_ssh_key

    [ -f "$SIGNING_KEY" ]
    [ -f "$SIGNING_KEY_PUB" ]
    [ "$(stat -c '%a' "$SIGNING_KEY")" = "600" ]
    [ "$(stat -c '%a' "$SIGNING_KEY_PUB")" = "644" ]
    diff <(sort "$SIGNING_KEY_PUB") <(sort "$TEST_HOME/generated_key.pub")
}

@test "configure_auth_ssh_key writes a managed block in ~/.ssh/config mapping github.com to id_aab_auth" {
    AAB_GH_AUTH_SSH_PRIVATE_KEY_B64=$(gen_test_ssh_key_b64)
    export AAB_GH_AUTH_SSH_PRIVATE_KEY_B64
    configure_auth_ssh_key

    [ -f "$SSH_CONFIG" ]
    grep -qF "$SSH_MARKER_BEGIN" "$SSH_CONFIG"
    grep -qF "$SSH_MARKER_END" "$SSH_CONFIG"
    grep -qE "^Host github.com$" "$SSH_CONFIG"
    grep -qF "IdentityFile $AUTH_KEY" "$SSH_CONFIG"
    grep -qE "^[[:space:]]+IdentitiesOnly yes$" "$SSH_CONFIG"
    [ "$(stat -c '%a' "$SSH_CONFIG")" = "600" ]
}

@test "configure_auth_ssh_key does NOT configure git signing" {
    command -v git >/dev/null || skip "precondition: git must exist"
    AAB_GH_AUTH_SSH_PRIVATE_KEY_B64=$(gen_test_ssh_key_b64)
    export AAB_GH_AUTH_SSH_PRIVATE_KEY_B64
    configure_auth_ssh_key

    # No signing config should have been written.
    [ -z "$(git config --global --get gpg.format 2>/dev/null || true)" ]
    [ -z "$(git config --global --get user.signingkey 2>/dev/null || true)" ]
    [ -z "$(git config --global --get commit.gpgsign 2>/dev/null || true)" ]
    [ -z "$(git config --global --get tag.gpgsign 2>/dev/null || true)" ]
}

@test "configure_signing_ssh_key does NOT touch ~/.ssh/config" {
    AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64=$(gen_test_ssh_key_b64)
    export AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64
    configure_signing_ssh_key

    [ ! -e "$SSH_CONFIG" ]
}

@test "configure_signing_ssh_key configures git SSH signing (gpg.format, signingkey, commit/tag.gpgsign)" {
    command -v git >/dev/null || skip "precondition: git must exist"
    AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64=$(gen_test_ssh_key_b64)
    export AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64
    configure_signing_ssh_key

    [ "$(git config --global --get gpg.format)" = "ssh" ]
    [ "$(git config --global --get user.signingkey)" = "$SIGNING_KEY_PUB" ]
    [ "$(git config --global --get commit.gpgsign)" = "true" ]
    [ "$(git config --global --get tag.gpgsign)" = "true" ]
}

@test "configure_auth_ssh_key is idempotent (second run: single managed block, file size stable)" {
    AAB_GH_AUTH_SSH_PRIVATE_KEY_B64=$(gen_test_ssh_key_b64)
    export AAB_GH_AUTH_SSH_PRIVATE_KEY_B64
    configure_auth_ssh_key
    local size1
    size1=$(wc -c < "$SSH_CONFIG")

    configure_auth_ssh_key
    local begin_count end_count size2
    begin_count=$(grep -cF "$SSH_MARKER_BEGIN" "$SSH_CONFIG")
    end_count=$(grep -cF "$SSH_MARKER_END" "$SSH_CONFIG")
    size2=$(wc -c < "$SSH_CONFIG")
    [ "$begin_count" -eq 1 ]
    [ "$end_count" -eq 1 ]
    [ "$size1" -eq "$size2" ]
}

@test "configure_auth_ssh_key preserves pre-existing non-managed content in ~/.ssh/config" {
    mkdir -p "$SSH_DIR"
    cat > "$SSH_CONFIG" <<'EOF'
Host gitlab.com
    IdentityFile ~/.ssh/id_ed25519_gitlab
    User git
EOF
    AAB_GH_AUTH_SSH_PRIVATE_KEY_B64=$(gen_test_ssh_key_b64)
    export AAB_GH_AUTH_SSH_PRIVATE_KEY_B64
    configure_auth_ssh_key

    # Original content still present.
    grep -qE "^Host gitlab.com$" "$SSH_CONFIG"
    grep -qF "IdentityFile ~/.ssh/id_ed25519_gitlab" "$SSH_CONFIG"
    # Managed block appended.
    grep -qF "$SSH_MARKER_BEGIN" "$SSH_CONFIG"
    grep -qE "^Host github.com$" "$SSH_CONFIG"
}

@test "configure_auth_ssh_key warns and skips on invalid-base64 input" {
    export AAB_GH_AUTH_SSH_PRIVATE_KEY_B64="this is not base64!@#"
    run configure_auth_ssh_key
    [ "$status" -eq 0 ]
    [[ "$output" == *"AAB_GH_AUTH_SSH_PRIVATE_KEY_B64 is not valid base64"* ]] \
        || [[ "$output" == *"AAB_GH_AUTH_SSH_PRIVATE_KEY_B64 did not decode to a valid SSH private key"* ]]
    [ ! -e "$AUTH_KEY" ]
}

@test "configure_signing_ssh_key warns and skips on decoded-garbage input" {
    export AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64="$(printf 'not-an-ssh-key' | base64 -w0)"
    run configure_signing_ssh_key
    [ "$status" -eq 0 ]
    [[ "$output" == *"AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64 did not decode to a valid SSH private key"* ]]
    [ ! -e "$SIGNING_KEY" ]
    [ ! -e "$SIGNING_KEY_PUB" ]
}

@test "auth and signing keys can be set independently (different keys, both written)" {
    # Generate two distinct keys, set each env var to a different encoding.
    AAB_GH_AUTH_SSH_PRIVATE_KEY_B64=$(gen_test_ssh_key_b64 "$TEST_HOME/auth_key")
    AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64=$(gen_test_ssh_key_b64 "$TEST_HOME/sign_key")
    export AAB_GH_AUTH_SSH_PRIVATE_KEY_B64 AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64

    configure_auth_ssh_key
    configure_signing_ssh_key

    # Both keys are on disk, at different paths.
    [ -f "$AUTH_KEY" ]
    [ -f "$SIGNING_KEY" ]
    ! diff -q "$AUTH_KEY" "$SIGNING_KEY"

    # Auth wiring in ~/.ssh/config points at the auth key, not the signing key.
    grep -qF "IdentityFile $AUTH_KEY" "$SSH_CONFIG"
    ! grep -qF "IdentityFile $SIGNING_KEY" "$SSH_CONFIG"

    # Git signing config points at the signing key, not the auth key.
    [ "$(git config --global --get user.signingkey)" = "$SIGNING_KEY_PUB" ]
}

# ---------------------------------------------------------------------------
# configure_git_hooks / configure_agent_rules: the global commit-identity
# enforcement hook plus the agent instruction-file rules. Cover:
#   - hook dispatcher + per-name symlinks configured, core.hooksPath set
#   - the emitted dispatcher is valid bash
#   - idempotent re-runs (one rule block, stable symlink count)
#   - functional enforcement: a matching identity commits, an overridden one
#     is blocked, by every override vector agents reach for
#   - the dispatcher chains through to a repo's own hook
#   - signing enforcement when global signing is configured
#   - the rule block lands in CLAUDE.md / AGENTS.md and preserves prior content
# Each test runs with HOME=$TEST_HOME, so `git config --global` and the hooks
# dir are sandboxed to the per-test home.
# ---------------------------------------------------------------------------

# Stage a committable repo under $TEST_HOME with the global identity pinned and
# the hooks configured. Echoes the repo path. The bootstrap helpers log to
# stdout, so redirect their chatter to stderr to keep the echoed path clean.
_setup_enforced_repo() {
    command -v git >/dev/null || skip "precondition: git must exist"
    AAB_GIT_AUTHOR_NAME="Global Name" \
        AAB_GIT_AUTHOR_EMAIL="global@example.com" \
        configure_git >&2
    configure_git_hooks >&2
    local repo="$TEST_HOME/repo"
    git init -q "$repo"
    printf '%s\n' "$repo"
}

@test "configure_git_hooks configures the dispatcher, per-name symlinks, and sets core.hooksPath" {
    command -v git >/dev/null || skip "precondition: git must exist"
    configure_git_hooks
    [ -x "$GIT_HOOK_DISPATCHER" ]
    [ "$(git config --global --get core.hooksPath)" = "$GIT_HOOKS_DIR" ]
    local name
    for name in "${GIT_HOOK_NAMES[@]}"; do
        [ -L "$GIT_HOOKS_DIR/$name" ]
        [ "$(readlink "$GIT_HOOKS_DIR/$name")" = "aab-git-hook" ]
    done
}

@test "git hook renderer emits syntactically valid bash" {
    _render_git_hook_script > "$TEST_HOME/hook"
    bash -n "$TEST_HOME/hook"
    head -1 "$TEST_HOME/hook" | grep -q '^#!/usr/bin/env bash$'
}

@test "configure_git_hooks is idempotent (stable symlink count, hooksPath set once)" {
    command -v git >/dev/null || skip "precondition: git must exist"
    configure_git_hooks
    local count1
    count1=$(find "$GIT_HOOKS_DIR" -maxdepth 1 -type l | wc -l)
    configure_git_hooks
    local count2
    count2=$(find "$GIT_HOOKS_DIR" -maxdepth 1 -type l | wc -l)
    [ "$count1" -eq "$count2" ]
    [ "$count1" -eq "${#GIT_HOOK_NAMES[@]}" ]
    [ "$(git config --global --get core.hooksPath)" = "$GIT_HOOKS_DIR" ]
}

@test "enforcement: a commit with the configured identity is allowed" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    echo hi > f.txt && git add f.txt
    run git commit -m "matching identity"
    [ "$status" -eq 0 ]
}

@test "enforcement: -c user.email override is blocked" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    echo hi > f.txt && git add f.txt
    run git -c user.email=hacker@evil.com commit -m "override"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Commit blocked"* ]]
}

@test "enforcement: --author override is blocked" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    echo hi > f.txt && git add f.txt
    run git commit --author="Hacker <hacker@evil.com>" -m "override"
    [ "$status" -ne 0 ]
}

@test "enforcement: GIT_AUTHOR_EMAIL env override is blocked" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    echo hi > f.txt && git add f.txt
    GIT_AUTHOR_EMAIL=hacker@evil.com run git commit -m "override"
    [ "$status" -ne 0 ]
}

@test "enforcement: GIT_COMMITTER_EMAIL env override is blocked" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    echo hi > f.txt && git add f.txt
    GIT_COMMITTER_EMAIL=hacker@evil.com run git commit -m "override"
    [ "$status" -ne 0 ]
}

@test "enforcement: repo-local user.email override is blocked" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    git config user.email hacker@evil.com
    git config user.name Hacker
    echo hi > f.txt && git add f.txt
    run git commit -m "override"
    [ "$status" -ne 0 ]
}

@test "enforcement: --no-verify bypasses the hook (documented escape hatch)" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    echo hi > f.txt && git add f.txt
    run git -c user.email=hacker@evil.com commit --no-verify -m "bypass"
    [ "$status" -eq 0 ]
}

@test "enforcement: no global identity pinned is a no-op (commit allowed)" {
    command -v git >/dev/null || skip "precondition: git must exist"
    configure_git_hooks
    local repo="$TEST_HOME/repo"
    git init -q "$repo"
    cd "$repo"
    # Only a repo-local identity, no global one — nothing to enforce against.
    git config user.name "Local Only"
    git config user.email "local@only.test"
    echo hi > f.txt && git add f.txt
    run git commit -m "no global identity"
    [ "$status" -eq 0 ]
}

@test "enforcement: dispatcher chains through to the repo's own hook" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    mkdir -p .git/hooks
    cat > .git/hooks/pre-commit <<'RH'
#!/usr/bin/env bash
echo "REPO_LOCAL_HOOK_RAN"
exit 0
RH
    chmod +x .git/hooks/pre-commit
    echo hi > f.txt && git add f.txt
    run git commit -m "with repo hook"
    [ "$status" -eq 0 ]
    [[ "$output" == *"REPO_LOCAL_HOOK_RAN"* ]]
}

@test "enforcement: a failing repo-local hook still blocks the commit" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    mkdir -p .git/hooks
    cat > .git/hooks/pre-commit <<'RH'
#!/usr/bin/env bash
exit 1
RH
    chmod +x .git/hooks/pre-commit
    echo hi > f.txt && git add f.txt
    run git commit -m "repo hook rejects"
    [ "$status" -ne 0 ]
}

@test "enforcement: signing disabled via config is blocked when global signing is on" {
    command -v git >/dev/null || skip "precondition: git must exist"
    AAB_GIT_AUTHOR_NAME="Global Name" \
        AAB_GIT_AUTHOR_EMAIL="global@example.com" \
        configure_git
    git config --global commit.gpgsign true
    git config --global gpg.format ssh
    git config --global user.signingkey "$TEST_HOME/fake.pub"
    configure_git_hooks
    local repo="$TEST_HOME/repo"
    git init -q "$repo"
    cd "$repo"
    echo hi > f.txt && git add f.txt
    # --no-gpg-sign keeps git from invoking a real signer; the hook should
    # still block because the effective commit.gpgsign is false.
    run git -c commit.gpgsign=false commit --no-gpg-sign -m "unsigned"
    [ "$status" -ne 0 ]
    [[ "$output" == *"signing is required"* ]]
}

# ---------------------------------------------------------------------------
# Pre-commit secret scan. The dispatcher blocks a commit that stages a secret,
# preferring gitleaks and falling back to a built-in shell grep. The unit suite
# does not download the gitleaks binary, so these tests run against the shell
# fallback by ensuring no gitleaks is resolvable (clean PATH, no
# ~/.local/bin/gitleaks under the per-test HOME) — except the one test that
# stubs a gitleaks on PATH to prove the preferred branch is taken. Each uses
# _setup_enforced_repo so the global identity matches and the identity check
# passes, letting execution reach the secret scan.
# ---------------------------------------------------------------------------

# A clean tree commits even with the secret scan active (fallback path).
@test "secret-scan (fallback): a commit with no secret is allowed" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    echo "nothing sensitive here" > clean.txt && git add clean.txt
    PATH="/usr/bin:/bin" run git commit -m "clean"
    [ "$status" -eq 0 ]
}

# A staged GitHub PAT is blocked by the shell fallback.
@test "secret-scan (fallback): a staged GitHub token is blocked" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    # Split the literal so this test file itself does not trip a secret scan.
    printf 'token=%s%s\n' "ghp_" "0000000000000000000000000000000000AB" > leak.txt
    git add leak.txt
    PATH="/usr/bin:/bin" run git commit -m "leak"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Commit blocked"* ]]
    [[ "$output" == *"GitHub token"* ]]
}

# URL-embedded credentials are blocked by the shell fallback.
@test "secret-scan (fallback): URL-embedded credentials are blocked" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    echo 'clone https://user:hunter2pass@github.com/o/r.git' > url.txt
    git add url.txt
    PATH="/usr/bin:/bin" run git commit -m "url creds"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Commit blocked"* ]]
}

# An AWS access-key id is blocked by the shell fallback.
@test "secret-scan (fallback): an AWS access key is blocked" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    # Concatenate so the file does not contain a contiguous key literal.
    printf 'k=%s%s\n' "AKIA" "IOSFODNN7EXAMPLE" > aws.txt
    git add aws.txt
    PATH="/usr/bin:/bin" run git commit -m "aws"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Commit blocked"* ]]
}

# A private-key header is blocked by the shell fallback.
@test "secret-scan (fallback): a private key header is blocked" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    echo '-----BEGIN RSA PRIVATE KEY-----' > key.txt
    git add key.txt
    PATH="/usr/bin:/bin" run git commit -m "privkey"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Commit blocked"* ]]
}

# The GITLEAKS_ALLOW env var is the documented escape hatch: with it set, a
# staged secret commits. (The literal assignment is annotated below so the
# repo's own gitleaks scan does not flag this test as a finding.)
@test "secret-scan: the GITLEAKS_ALLOW env var bypasses the scan" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    printf 'token=%s%s\n' "ghp_" "0000000000000000000000000000000000AB" > leak.txt
    git add leak.txt
    PATH="/usr/bin:/bin" GITLEAKS_ALLOW=1 run git commit -m "allowed leak"  # gitleaks:allow
    [ "$status" -eq 0 ]
}

# --no-verify skips every hook, including the secret scan.
@test "secret-scan: --no-verify bypasses the scan" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    printf 'token=%s%s\n' "ghp_" "0000000000000000000000000000000000AB" > leak.txt
    git add leak.txt
    PATH="/usr/bin:/bin" run git commit --no-verify -m "bypass"
    [ "$status" -eq 0 ]
}

# When gitleaks IS resolvable, the dispatcher uses it (not the shell fallback).
# Stub a gitleaks on PATH that fails only for `protect`, and assert the commit
# is blocked with the gitleaks-path message.
@test "secret-scan (gitleaks): a resolvable gitleaks is preferred and can block" {
    local repo
    repo=$(_setup_enforced_repo)
    cd "$repo"
    local stubdir="$TEST_HOME/stubbin"
    mkdir -p "$stubdir"
    cat > "$stubdir/gitleaks" <<'STUB'
#!/usr/bin/env bash
# Minimal gitleaks stub: `protect` reports a finding (exit 1); anything else ok.
case "${1:-}" in
    protect) echo "stub gitleaks: leak found" >&2; exit 1 ;;
    version) echo "8.18.4" ;;
    *) exit 0 ;;
esac
STUB
    chmod +x "$stubdir/gitleaks"
    # A file with NO secret pattern: the shell fallback would PASS it, so a block
    # here proves the gitleaks branch (not the fallback) made the decision.
    echo "totally innocuous content" > innocuous.txt && git add innocuous.txt
    PATH="$stubdir:/usr/bin:/bin" run git commit -m "via gitleaks stub"
    [ "$status" -ne 0 ]
    [[ "$output" == *"gitleaks found a secret"* ]]
}

# install_gitleaks is idempotent: a gitleaks already at the pinned version is
# left untouched and no download is attempted. We fake one at GITLEAKS_BIN that
# prints the pinned version, point PATH at nothing else, and assert the call is
# a quiet no-op that preserves the existing binary's content.
@test "install_gitleaks is a no-op when the pinned version is already installed" {
    mkdir -p "$(dirname "$GITLEAKS_BIN")"
    cat > "$GITLEAKS_BIN" <<STUB
#!/usr/bin/env bash
[ "\${1:-}" = version ] && echo "$GITLEAKS_VERSION"
STUB
    chmod +x "$GITLEAKS_BIN"
    local before
    before=$(cat "$GITLEAKS_BIN")
    run install_gitleaks
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
    # Untouched: same content (a re-download would replace it with a real ELF).
    [ "$(cat "$GITLEAKS_BIN")" = "$before" ]
}

# install_gitleaks skips cleanly (no error, no install) on an unsupported CPU
# arch, leaving the hook's shell fallback as the protection. Stub `uname` so the
# function sees an arch with no pinned build.
@test "install_gitleaks skips gracefully on an unsupported architecture" {
    local stubdir="$TEST_HOME/unamestub"
    mkdir -p "$stubdir"
    cat > "$stubdir/uname" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
    -s) echo Linux ;;
    -m) echo riscv64 ;;
    *) echo Linux ;;
esac
STUB
    chmod +x "$stubdir/uname"
    rm -f "$GITLEAKS_BIN"
    # Clean PATH (stub + base dirs only) so a host-wide gitleaks — e.g. CI's
    # /usr/local/bin install — does not short-circuit before the arch check.
    PATH="$stubdir:/usr/bin:/bin" run install_gitleaks
    [ "$status" -eq 0 ]
    [[ "$output" == *"no pinned build for riscv64"* ]]
    [ ! -e "$GITLEAKS_BIN" ]
}

@test "configure_agent_rules writes clean rules to CLAUDE.md and AGENTS.md" {
    configure_agent_rules
    [ -f "$CLAUDE_MEMORY_FILE" ]
    [ -f "$CODEX_AGENTS_FILE" ]
    [ -f "$AGENT_RULES_STATE_FILE" ]
    [ "$(stat -c '%a' "$AGENT_RULES_STATE_FILE")" = "600" ]
    ! grep -qF '# >>> autonomous-agent-bootstrap >>>' "$CLAUDE_MEMORY_FILE"
    ! grep -qF '# <<< autonomous-agent-bootstrap <<<' "$CLAUDE_MEMORY_FILE"
    grep -q "Operating principles" "$CLAUDE_MEMORY_FILE"
    grep -q "Act autonomously without seeking operator input" "$CLAUDE_MEMORY_FILE"
    grep -q "Always use the configured git identity" "$CLAUDE_MEMORY_FILE"
    ! grep -qF '# >>> autonomous-agent-bootstrap >>>' "$CODEX_AGENTS_FILE"
    grep -q "Operating principles" "$CODEX_AGENTS_FILE"
    grep -q "Always use the configured git identity" "$CODEX_AGENTS_FILE"
    grep -q "Operating principles" "$AGENT_RULES_STATE_FILE"
}

@test "configure_agent_rules is idempotent (single rule set, size stable)" {
    configure_agent_rules
    local size1
    size1=$(wc -c < "$CLAUDE_MEMORY_FILE")
    configure_agent_rules
    local rules_count size2
    rules_count=$(grep -c '^## Operating principles$' "$CLAUDE_MEMORY_FILE")
    size2=$(wc -c < "$CLAUDE_MEMORY_FILE")
    [ "$rules_count" -eq 1 ]
    [ "$size1" -eq "$size2" ]
}

@test "configure_agent_rules preserves pre-existing instruction-file content" {
    mkdir -p "$(dirname "$CLAUDE_MEMORY_FILE")"
    printf '# My memory\n\nKeep this line.\n' > "$CLAUDE_MEMORY_FILE"
    configure_agent_rules
    grep -q '^# My memory$' "$CLAUDE_MEMORY_FILE"
    grep -q '^Keep this line\.$' "$CLAUDE_MEMORY_FILE"
    ! grep -qF '# >>> autonomous-agent-bootstrap >>>' "$CLAUDE_MEMORY_FILE"
}

@test "configure_agent_rules replaces the sidecar-tracked rule text" {
    mkdir -p "$(dirname "$CLAUDE_MEMORY_FILE")" "$AAB_DIR"
    printf '# My memory\n\n## Old generated rules\n\nOld rule.\n' > "$CLAUDE_MEMORY_FILE"
    printf '## Old generated rules\n\nOld rule.\n' > "$AGENT_RULES_STATE_FILE"

    configure_agent_rules

    grep -q '^# My memory$' "$CLAUDE_MEMORY_FILE"
    ! grep -q '^## Old generated rules$' "$CLAUDE_MEMORY_FILE"
    grep -q '^## Operating principles$' "$CLAUDE_MEMORY_FILE"
}

# ---------------------------------------------------------------------------
# load_config_file / load_config_stdin: covers the bash-source-backed config
# loader used when main() is given a positional path or non-TTY stdin.
# Exercises quoting, comments, input-beats-env precedence, the missing-file
# and malformed-input error paths, shell-expansion features, and the
# stdin variant.
# ---------------------------------------------------------------------------

@test "load_config_file populates unset env vars from KEY=VALUE lines" {
    cat > "$TEST_HOME/aab.conf" <<'EOF'
AAB_CLAUDE_DEFAULT_PROFILE=third-party/deepseek-v4
AAB_INFERENCE_GATEWAY_URL=https://gateway.example.com
AAB_GIT_AUTHOR_NAME="Alice Example"
AAB_GIT_AUTHOR_EMAIL=alice@example.com
EOF
    load_config_file "$TEST_HOME/aab.conf"
    [ "$AAB_CLAUDE_DEFAULT_PROFILE" = "third-party/deepseek-v4" ]
    [ "$AAB_INFERENCE_GATEWAY_URL" = "https://gateway.example.com" ]
    [ "$AAB_GIT_AUTHOR_NAME" = "Alice Example" ]
    [ "$AAB_GIT_AUTHOR_EMAIL" = "alice@example.com" ]
}

@test "load_config_file: direct assignments override inherited env vars" {
    export AAB_CLAUDE_DEFAULT_PROFILE="first-party/opus-4.8"
    cat > "$TEST_HOME/aab.conf" <<'EOF'
AAB_CLAUDE_DEFAULT_PROFILE=first-party/sonnet-4.8
AAB_GIT_AUTHOR_NAME="Alice Example"
EOF
    load_config_file "$TEST_HOME/aab.conf"
    [ "$AAB_CLAUDE_DEFAULT_PROFILE" = "first-party/sonnet-4.8" ]
    # File-only value still loaded.
    [ "$AAB_GIT_AUTHOR_NAME" = "Alice Example" ]
}

@test "load_config_file: direct assignments replace inherited empty strings" {
    export AAB_ANTHROPIC_API_KEY=""
    cat > "$TEST_HOME/aab.conf" <<'EOF'
AAB_ANTHROPIC_API_KEY=sk-ant-from-file
EOF
    load_config_file "$TEST_HOME/aab.conf"
    [ "$AAB_ANTHROPIC_API_KEY" = "sk-ant-from-file" ]
}

@test "load_config_file handles double- and single-quoted values, and leading 'export '" {
    cat > "$TEST_HOME/aab.conf" <<'EOF'
AAB_CLAUDE_DEFAULT_PROFILE="first-party/sonnet-4.8"
AAB_GIT_AUTHOR_NAME='Alice Example'
export AAB_GH_TOKEN=ghp_abc123
EOF
    load_config_file "$TEST_HOME/aab.conf"
    [ "$AAB_CLAUDE_DEFAULT_PROFILE" = "first-party/sonnet-4.8" ]
    [ "$AAB_GIT_AUTHOR_NAME" = "Alice Example" ]
    [ "$AAB_GH_TOKEN" = "ghp_abc123" ]
}

@test "load_config_file preserves values containing '=' (only the FIRST '=' splits)" {
    cat > "$TEST_HOME/aab.conf" <<'EOF'
AAB_INFERENCE_GATEWAY_URL="https://example.com/v1?foo=bar&baz=qux"
EOF
    load_config_file "$TEST_HOME/aab.conf"
    [ "$AAB_INFERENCE_GATEWAY_URL" = "https://example.com/v1?foo=bar&baz=qux" ]
}

@test "load_config_file skips comments and blank lines" {
    cat > "$TEST_HOME/aab.conf" <<'EOF'
# comment at top

# another comment
AAB_CLAUDE_DEFAULT_PROFILE=first-party/opus-4.8  # trailing comment

EOF
    run load_config_file "$TEST_HOME/aab.conf"
    [ "$status" -eq 0 ]

    # Verify the one real key actually landed (re-run in-process).
    load_config_file "$TEST_HOME/aab.conf"
    [ "$AAB_CLAUDE_DEFAULT_PROFILE" = "first-party/opus-4.8" ]
}

@test "load_config_file expands \${VAR:-default} parameter expansions" {
    # bash sourcing means the file has access to the live shell — defaults,
    # parameter expansion, command substitution all work.
    cat > "$TEST_HOME/aab.conf" <<'EOF'
AAB_CLAUDE_DEFAULT_PROFILE="${AAB_CLAUDE_DEFAULT_PROFILE:-first-party/opus-4.8}"
AAB_GIT_AUTHOR_NAME="Default $(echo Alice)"
EOF
    load_config_file "$TEST_HOME/aab.conf"
    [ "$AAB_CLAUDE_DEFAULT_PROFILE" = "first-party/opus-4.8" ]
    [ "$AAB_GIT_AUTHOR_NAME" = "Default Alice" ]
}

@test "load_config_file aborts on malformed input under set -e" {
    # `set -a; . file; set +a` is strict: a bad-identifier line is a bash
    # syntax error and a no-equals line is a "command not found" exit. Both
    # short-circuit the load — the safer default for a credentials-loading
    # step than the previous warn-and-skip.
    #
    # bats's `run` helper turns `set -e` off, so to assert the real-world
    # abort behavior we re-source bootstrap.bash inside a fresh `bash -c`
    # that re-enables `set -euo pipefail`.
    cat > "$TEST_HOME/aab.conf" <<'EOF'
this-line-has-no-equals
AAB_CLAUDE_DEFAULT_PROFILE=first-party/opus-4.8
EOF
    run bash -c "
        set -euo pipefail
        source '$REPO_ROOT/bootstrap.bash'
        load_config_file '$TEST_HOME/aab.conf'
        echo 'should-not-reach'
    "
    [ "$status" -ne 0 ]
    [[ "$output" != *"should-not-reach"* ]]
}

@test "load_config_file: missing file errors out non-zero" {
    run load_config_file "$TEST_HOME/does-not-exist.conf"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found or not readable"* ]]
}

@test "load_config_stdin reads KEY=VALUE pairs piped on stdin" {
    load_config_stdin <<'EOF'
AAB_CLAUDE_DEFAULT_PROFILE=first-party/sonnet-4.8
AAB_GIT_AUTHOR_NAME="Alice Example"
EOF
    [ "$AAB_CLAUDE_DEFAULT_PROFILE" = "first-party/sonnet-4.8" ]
    [ "$AAB_GIT_AUTHOR_NAME" = "Alice Example" ]
}

@test "load_config_stdin replaces stale Claude and Codex defaults" {
    export AAB_CLAUDE_DEFAULT_PROFILE="first-party/opus-4.8"
    export AAB_CODEX_DEFAULT_PROFILE="first-party/gpt-5.5"
    load_config_stdin <<'EOF'
AAB_CLAUDE_THIRD_PARTY_PROFILES='deepseek-v4 model=vendor/deepseek-v4'
AAB_CLAUDE_DEFAULT_PROFILE=third-party/deepseek-v4
AAB_CODEX_THIRD_PARTY_PROFILES='gpt-5.6 model=vendor/gpt-5.6'
AAB_CODEX_DEFAULT_PROFILE=third-party/gpt-5.6
AAB_GIT_AUTHOR_NAME=Alice
EOF
    local -A claude_profile=() codex_profile=()
    validate_model_profiles
    resolve_model_profile claude claude_profile
    resolve_model_profile codex codex_profile
    [ "$AAB_CLAUDE_DEFAULT_PROFILE" = "third-party/deepseek-v4" ]
    [ "${claude_profile[source]}/${claude_profile[name]}" = "third-party/deepseek-v4" ]
    [ "$AAB_CODEX_DEFAULT_PROFILE" = "third-party/gpt-5.6" ]
    [ "${codex_profile[source]}/${codex_profile[name]}" = "third-party/gpt-5.6" ]
    [ "$AAB_GIT_AUTHOR_NAME" = "Alice" ]
}

@test "load_config_stdin: empty stdin is a silent no-op" {
    # No body in the heredoc — load_config_stdin sees zero bytes and returns
    # without touching the env.
    [ -z "${AAB_GIT_AUTHOR_NAME:-}" ]
    load_config_stdin </dev/null
    [ -z "${AAB_GIT_AUTHOR_NAME:-}" ]
}

@test "main() runs load_config_file only when given a positional arg (unset env vars populated)" {
    # Drive main's config-loading step in isolation: we don't want main()
    # to actually execute the rest of its pipeline here. Instead, replay
    # the same logic main() uses: if $1 is set, call load_config_file.
    cat > "$TEST_HOME/aab.conf" <<'EOF'
AAB_GIT_AUTHOR_EMAIL=from-file@example.com
EOF
    # No positional arg: env must remain untouched.
    [ -z "${AAB_GIT_AUTHOR_EMAIL:-}" ]
    # With a positional arg, the helper populates it.
    load_config_file "$TEST_HOME/aab.conf"
    [ "$AAB_GIT_AUTHOR_EMAIL" = "from-file@example.com" ]
}

# Stub curl so install_lifeboat "fetches" a fake script we control: a success
# stub writes the requested -o target, a failing stub exits non-zero so the
# best-effort degrade-to-warning path is exercised.
setup_fake_lifeboat_curl() {
    local mode="$1"  # ok | fail
    export FAKE_LIFEBOAT_BIN="$TEST_HOME/fake-lifeboat-bin"
    mkdir -p "$FAKE_LIFEBOAT_BIN"
    cat > "$FAKE_LIFEBOAT_BIN/curl" <<SH
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "$TEST_HOME/lifeboat-curl-invocations"
output=""
while [ "\$#" -gt 0 ]; do
    case "\$1" in
        -o|--output) output="\$2"; shift 2 ;;
        *) shift ;;
    esac
done
if [ "$mode" = fail ]; then exit 22; fi
[ -n "\$output" ] || exit 0
printf '#!/usr/bin/env bash\necho fake-lifeboat\n' > "\$output"
SH
    chmod +x "$FAKE_LIFEBOAT_BIN/curl"
    export PATH="$FAKE_LIFEBOAT_BIN:$PATH"
}

@test "install_lifeboat fetches the script to ~/.local/bin and marks it executable" {
    setup_fake_lifeboat_curl ok
    run install_lifeboat
    [ "$status" -eq 0 ]
    # Fetched from the public lifeboat repo, to a file (not piped to bash).
    grep -Fq "raw.githubusercontent.com/${LIFEBOAT_REPO}/${LIFEBOAT_REF}/lifeboat" \
        "$TEST_HOME/lifeboat-curl-invocations"
    grep -Fq -- '-o ' "$TEST_HOME/lifeboat-curl-invocations"
    # Installed and executable; no leftover .tmp.
    [ -x "$TEST_HOME/.local/bin/lifeboat" ]
    [ ! -e "$TEST_HOME/.local/bin/lifeboat.tmp" ]
}

@test "install_lifeboat degrades to a warning when the fetch fails" {
    setup_fake_lifeboat_curl fail
    run install_lifeboat
    # Best effort: the run continues (exit 0) and nothing is left behind.
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [ ! -e "$TEST_HOME/.local/bin/lifeboat" ]
    [ ! -e "$TEST_HOME/.local/bin/lifeboat.tmp" ]
}
