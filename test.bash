#!/usr/bin/env bash
# Run the project's tests. Mirrors the jobs in .github/workflows/ci.yml so
# "works locally" == "will pass CI".
#
# Usage:
#   ./test.bash              lint + unit (default; fast, no side effects)
#   ./test.bash --lint       bash -n + shellcheck
#   ./test.bash --unit       bats suite (tests/bootstrap.bats)
#   ./test.bash --e2e        runs bootstrap.bash on THIS host + assertions.
#                            Destructive: overwrites ~/.claude/settings.json,
#                            overwrites ~/.codex/config.toml, rewrites the
#                            ~/.bashrc managed block, modifies global git
#                            config, writes a synthetic Codex API-key login,
#                            writes a Brev API-key login when AAB_BREV_*
#                            vars are set, and installs claude / codex / pi /
#                            brev / gh.
#                            Only run on a disposable machine.
#   ./test.bash --docker     same as --e2e, but inside a fresh ubuntu:22.04
#                            docker container — safe to run anywhere with
#                            docker available, and the stronger check that
#                            bootstrap works on a bare image.
#   ./test.bash --smoke      live Claude + Codex inference smoke test using
#                            real credentials from the current environment.
#   ./test.bash --secrets    gitleaks scan of full history + working tree
#   ./test.bash --all        lint + unit + e2e + secrets, in order
#   ./test.bash -h|--help    print this usage

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

need() {
    command -v "$1" >/dev/null 2>&1 \
        || { echo "test.bash: Missing dependency: $1." >&2; return 1; }
}

run_lint() {
    echo "=== lint ==="
    need bash
    need python3
    need shellcheck
    python3 tools/compile_bootstrap.py --check
    bash -n bootstrap.bash
    shellcheck -S warning bootstrap.bash test.bash tests/e2e-assertions.bash
    # The global git hook is emitted from bootstrap.bash via a quoted heredoc,
    # so shellcheck does not see it above. Extract and lint it on its own.
    local hook
    hook=$(mktemp)
    # shellcheck disable=SC1090
    ( set -euo pipefail; source ./bootstrap.bash; _render_git_hook_script ) > "$hook"
    bash -n "$hook"
    shellcheck -S warning "$hook"
    rm -f "$hook"
}

run_unit() {
    echo "=== unit (bats) ==="
    need bats
    need python3
    bats tests/bootstrap.bats
}

run_e2e() {
    echo "=== e2e (runs bootstrap.bash on this host — DESTRUCTIVE) ==="
    # bootstrap.bash's install_base_deps step installs curl / python3 /
    # git / sudo / ripgrep / pandoc / ca-certificates itself, so we only need bash here.
    need bash
    : "${AAB_GIT_AUTHOR_NAME:=CI Bot}"
    : "${AAB_GIT_AUTHOR_EMAIL:=ci@example.com}"
    : "${AAB_CLAUDE_FIRST_PARTY_PROFILES:=opus-4.8 model=claude-opus-4-8 haiku=claude-haiku-4-5 sonnet=claude-sonnet-4-6 opus=claude-opus-4-8 effort=max}"
    : "${AAB_CLAUDE_PROFILE:=first-party/opus-4.8}"
    : "${AAB_CODEX_FIRST_PARTY_PROFILES:=gpt-5.5 effort=xhigh}"
    : "${AAB_CODEX_PROFILE:=first-party/gpt-5.5}"
    : "${AAB_PI_PROFILES:=opus-4.8 model=anthropic/claude-opus-4-8 effort=max context=200000 max_tokens=32000}"
    : "${AAB_PI_PROFILE:=opus-4.8}"
    : "${AAB_INFERENCE_GATEWAY_URL:=https://gateway.example.com/v1}"
    : "${AAB_INFERENCE_GATEWAY_API_KEY:=gateway-e2e-test-key}"
    : "${OPENAI_API_KEY:=codex-e2e-test-key}"
    export AAB_GIT_AUTHOR_NAME AAB_GIT_AUTHOR_EMAIL \
           AAB_CLAUDE_FIRST_PARTY_PROFILES AAB_CLAUDE_PROFILE \
           AAB_CODEX_FIRST_PARTY_PROFILES AAB_CODEX_PROFILE \
           AAB_PI_PROFILES AAB_PI_PROFILE \
           AAB_INFERENCE_GATEWAY_URL AAB_INFERENCE_GATEWAY_API_KEY \
           OPENAI_API_KEY

    bash bootstrap.bash
    bash tests/e2e-assertions.bash

    # Re-run and re-assert to verify idempotency.
    bash bootstrap.bash
    bash tests/e2e-assertions.bash

    echo "=== e2e passed ==="
}

run_docker_e2e() {
    echo "=== docker e2e (bootstrap in fresh ubuntu:22.04 container) ==="
    need docker
    # Mount the repo read-only and copy it inside the container so the
    # bootstrap works against a pristine tree it can write into.
    # Forward GITHUB_TOKEN (if set) so the Brev installer's release-info
    # call to api.github.com isn't rate-limited in CI; -e X without a value
    # is a no-op when the caller doesn't export it.
    docker run --rm \
        -e GITHUB_TOKEN \
        -e AAB_BREV_API_KEY \
        -e AAB_BREV_ORG_ID \
        -v "$HERE:/src:ro" \
        ubuntu:22.04 \
        bash -c 'set -euo pipefail
            cp -r /src /work
            cd /work
            ./test.bash --e2e'
    echo "=== docker e2e passed ==="
}

redact_secrets() {
    sed -E \
        -e 's/sk-[A-Za-z0-9_-]+/sk-REDACTED/g' \
        -e 's/nvapi-[A-Za-z0-9_-]+/nvapi-REDACTED/g' \
        -e 's/(ghp_|github_pat_)[A-Za-z0-9_]+/GITHUB_TOKEN_REDACTED/g'
}

run_smoke() {
    echo "=== live inference smoke (claude + codex exec) ==="
    need timeout
    need claude
    need codex

    local expected="${AAB_SMOKE_EXPECTED:-AAB_SMOKE_OK}"
    local prompt="${AAB_SMOKE_PROMPT:-Reply with exactly ${expected}.}"
    local claude_output codex_output

    if ! claude_output=$(timeout 180s claude --dangerously-skip-permissions -p "$prompt" 2>&1); then
        printf '%s\n' "$claude_output" | redact_secrets >&2
        echo "test.bash: Claude smoke test failed." >&2
        return 1
    fi
    if ! grep -Fq "$expected" <<<"$claude_output"; then
        printf '%s\n' "$claude_output" | redact_secrets >&2
        echo "test.bash: Claude smoke test did not return ${expected}." >&2
        return 1
    fi
    echo "Claude smoke passed."

    if [ "${OPENAI_API_KEY:-}" = "codex-e2e-test-key" ]; then
        echo "test.bash: --smoke requires real Codex authentication, not the synthetic e2e key." >&2
        return 1
    fi

    if ! codex_output=$(timeout 180s codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust "$prompt" 2>&1); then
        printf '%s\n' "$codex_output" | redact_secrets >&2
        echo "test.bash: Codex smoke test failed." >&2
        return 1
    fi
    if ! grep -Fq "$expected" <<<"$codex_output"; then
        printf '%s\n' "$codex_output" | redact_secrets >&2
        echo "test.bash: Codex smoke test did not return ${expected}." >&2
        return 1
    fi
    echo "Codex smoke passed."

    echo "=== live inference smoke passed ==="
}

run_secrets() {
    echo "=== secret scan (gitleaks) ==="
    need gitleaks
    gitleaks detect --source . --redact --verbose --exit-code 1
    gitleaks detect --source . --no-git --redact --verbose --exit-code 1
}

usage() {
    sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
}

if [ $# -eq 0 ]; then
    run_lint
    run_unit
    exit 0
fi

for arg in "$@"; do
    case "$arg" in
        --lint)    run_lint ;;
        --unit)    run_unit ;;
        --e2e)     run_e2e ;;
        --docker)  run_docker_e2e ;;
        --smoke)   run_smoke ;;
        --secrets) run_secrets ;;
        --all)
            run_lint
            run_unit
            run_e2e
            run_secrets
            ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "test.bash: Unknown arg: $arg." >&2
            usage >&2
            exit 2
            ;;
    esac
done
