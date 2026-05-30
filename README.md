# autonomous-agent-bootstrap

A single idempotent bash script that turns a fresh Linux host into a ready-to-use Claude Code and Codex agent environment. Built for Brev VMs but works on any Ubuntu/Debian host.

## What It Sets Up

1. **Claude Code** via the official native installer, configured for unattended use with `bypassPermissions`, sandbox mode, debug logging, skipped onboarding, and pre-approved first-party API-key fingerprints when provided.
2. **Codex CLI** via OpenAI's standalone installer, configured with `approval_policy = "never"`, `sandbox_mode = "danger-full-access"`, trusted project roots, live web search, shell env inheritance, service tier, reasoning effort, and `[agents].max_threads`.
3. **AAB env file** at `~/.aab/.env` for provider selection, model names, and credentials. The bootstrap keeps these out of `~/.bashrc` and `/etc/environment`.
4. **Wrapper families** in `~/.local/bin`, with the selected `claude` entrypoint installed as a regular launcher file in `~/.local/aab-bin` (kept ahead of `~/.local/bin` on PATH so the native auto-updater, which owns `~/.local/bin/claude`, cannot shadow the wrapper):
   - `~/.local/aab-bin/claude` plus explicit `claude-first-party`, `claude-third-party-anthropic`, `claude-third-party-deepseek`, and `claude-third-party-nemotron` launchers
   - `codex` plus explicit `codex-first-party` and `codex-third-party-openai` launchers
5. **Brev CLI**, with optional `brev login --api-key ... --org-id ...` when `AAB_BREV_API_KEY` and `AAB_BREV_ORG_ID` are set.
6. **gh CLI**, installed from the official `cli.github.com` apt repo.
7. **git**, with optional author identity, GitHub credential helper, SSH auth key, and SSH signing key.
8. **Global git-identity enforcement** — an agent rule in every harness's global instruction file plus a global git hook that rejects commits whose identity does not match the configured git config. See [Git Identity Enforcement](#git-identity-enforcement).
9. **Agent plugins** listed in [`agent_plugins.txt`](./agent_plugins.txt), installed into both Claude Code and Codex.

## Requirements

- Ubuntu/Debian host with `bash` and `apt-get`
- Passwordless `sudo`, or run as root
- A bare `ubuntu:22.04` image is valid; the bootstrap installs `curl`, `python3`, `git`, `tar`, `gawk`, `ripgrep`, `sudo`, `ca-certificates`, and `gh`

## Quick Start

Create a config file with the settings you want, then run the bootstrap:

```bash
cat > /tmp/aab.conf <<'CONF'
AAB_CLAUDE_CODE_INFERENCE_PROVIDER=first-party
AAB_CLAUDE_CODE_FIRST_PARTY_MODEL=claude-opus-4-7
AAB_CLAUDE_CODE_EFFORT=max
AAB_CLAUDE_CODE_FIRST_PARTY_API_KEY=...

AAB_CODEX_INFERENCE_PROVIDER=first-party
AAB_CODEX_FIRST_PARTY_MODEL=gpt-5.5
AAB_CODEX_FIRST_PARTY_API_KEY=...
AAB_CODEX_EFFORT=xhigh
AAB_CODEX_SERVICE_TIER=priority
AAB_CODEX_AGENT_MAX_THREADS=16

AAB_BREV_API_KEY=...
AAB_BREV_ORG_ID=...
AAB_GH_TOKEN=...
AAB_GIT_AUTHOR_NAME=Your Name
AAB_GIT_AUTHOR_EMAIL=you@example.com
CONF

curl -fsSL https://raw.githubusercontent.com/brycelelbach/autonomous-agent-bootstrap/main/bootstrap.bash | bash -s -- /tmp/aab.conf
source ~/.bashrc
claude -p "Say hello from Claude Code"
codex exec "Say hello from Codex"
```

You can also pass the same keys as exported environment variables or pipe config on stdin. The file is sourced as bash, so quote values containing shell metacharacters.

## Provider Selection

`AAB_CLAUDE_CODE_INFERENCE_PROVIDER` controls which wrapper behavior the unqualified `claude` launcher uses:

- `first-party`
- `third-party-anthropic`
- `third-party-deepseek`
- `third-party-nemotron`

`AAB_CODEX_INFERENCE_PROVIDER` controls which wrapper behavior the unqualified `codex` launcher uses:

- `first-party`
- `third-party-openai`

The explicit wrappers are always installed, so you can run `claude-third-party-deepseek` or `codex-third-party-openai` directly regardless of the default launcher. To change the unqualified `claude` or `codex` command, update your config and re-run the bootstrap. AAB writes the unqualified commands as regular executable wrapper files, not shell aliases, so `type claude` should resolve to `~/.local/aab-bin/claude` and `type codex` to `~/.local/bin/codex`.

### Third-Party Claude Examples

```bash
AAB_CLAUDE_CODE_INFERENCE_PROVIDER=third-party-anthropic
AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_BASE_URL=https://gateway.example.com
AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_API_KEY=...
AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_MODEL=aws/anthropic/bedrock-claude-opus-4-7
AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_HAIKU_MODEL=aws/anthropic/claude-haiku-4-5-v1
AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_SONNET_MODEL=aws/anthropic/bedrock-claude-sonnet-4-6
AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_OPUS_MODEL=aws/anthropic/bedrock-claude-opus-4-7
```

```bash
AAB_CLAUDE_CODE_INFERENCE_PROVIDER=third-party-deepseek
AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_BASE_URL=https://deepseek-gateway.example.com
AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_API_KEY=...
AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_MODEL=deepseek-reasoner
AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_HAIKU_MODEL=deepseek-chat
AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_SONNET_MODEL=deepseek-chat
AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_OPUS_MODEL=deepseek-reasoner
```

```bash
AAB_CLAUDE_CODE_INFERENCE_PROVIDER=third-party-nemotron
AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_BASE_URL=https://inference-api.nvidia.com
AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_API_KEY=...
AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_MODEL=nvidia/nvidia/nemotron-3-ultra
AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_HAIKU_MODEL=nvidia/nvidia/nemotron-3-ultra
AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_SONNET_MODEL=nvidia/nvidia/nemotron-3-ultra
AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_OPUS_MODEL=nvidia/nvidia/nemotron-3-ultra
```

### Third-Party Codex Example

```bash
AAB_CODEX_INFERENCE_PROVIDER=third-party-openai
AAB_CODEX_THIRD_PARTY_OPENAI_BASE_URL=https://inference-api.nvidia.com/v1
AAB_CODEX_THIRD_PARTY_OPENAI_API_KEY=...
AAB_CODEX_THIRD_PARTY_OPENAI_MODEL=openai/openai/gpt-5.5
```

## Environment Variables

All variables are optional unless you select a provider that needs its credential.

| Variable | Effect |
| --- | --- |
| `AAB_CLAUDE_CODE_INFERENCE_PROVIDER` | `first-party`, `third-party-anthropic`, `third-party-deepseek`, or `third-party-nemotron`. Selects the unqualified `claude` launcher behavior. Defaults to `first-party`. |
| `AAB_CLAUDE_CODE_FIRST_PARTY_API_KEY` | Anthropic first-party API key. Stored in `~/.aab/.env`; mapped to `ANTHROPIC_API_KEY` by `claude-first-party`. |
| `AAB_CLAUDE_CODE_FIRST_PARTY_MODEL` | Claude first-party model. Defaults to `claude-opus-4-7`. |
| `AAB_CLAUDE_CODE_FIRST_PARTY_HAIKU_MODEL` | First-party haiku-tier model. Defaults to `claude-haiku-4-5`. |
| `AAB_CLAUDE_CODE_FIRST_PARTY_SONNET_MODEL` | First-party sonnet-tier model. Defaults to `claude-sonnet-4-6`. |
| `AAB_CLAUDE_CODE_FIRST_PARTY_OPUS_MODEL` | First-party opus-tier model. Defaults to `claude-opus-4-7`. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_BASE_URL` | Anthropic-compatible third-party base URL for Claude. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_API_KEY` | Third-party Anthropic-compatible API key. Mapped to `ANTHROPIC_AUTH_TOKEN`. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_MODEL` | Third-party Anthropic-compatible default model. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_HAIKU_MODEL` | Third-party Anthropic-compatible haiku-tier model. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_SONNET_MODEL` | Third-party Anthropic-compatible sonnet-tier model. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_ANTHROPIC_OPUS_MODEL` | Third-party Anthropic-compatible opus-tier model. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_BASE_URL` | DeepSeek gateway base URL for Claude. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_API_KEY` | DeepSeek gateway API key. Mapped to `ANTHROPIC_AUTH_TOKEN`. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_MODEL` | DeepSeek default model. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_HAIKU_MODEL` | DeepSeek haiku-tier model. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_SONNET_MODEL` | DeepSeek sonnet-tier model. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_DEEPSEEK_OPUS_MODEL` | DeepSeek opus-tier model. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_BASE_URL` | Nemotron gateway base URL for Claude. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_API_KEY` | Nemotron gateway API key. Mapped to `ANTHROPIC_AUTH_TOKEN`. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_MODEL` | Nemotron default model. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_HAIKU_MODEL` | Nemotron haiku-tier model. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_SONNET_MODEL` | Nemotron sonnet-tier model. |
| `AAB_CLAUDE_CODE_THIRD_PARTY_NEMOTRON_OPUS_MODEL` | Nemotron opus-tier model. |
| `AAB_CLAUDE_CODE_EFFORT` | Claude Code effort level. Defaults to `max`. |
| `AAB_CODEX_INFERENCE_PROVIDER` | `first-party` or `third-party-openai`. Selects the unqualified `codex` launcher behavior. Defaults to `first-party`. |
| `AAB_CODEX_FIRST_PARTY_API_KEY` | OpenAI API key for first-party Codex. Stored in `~/.aab/.env`, mapped to `OPENAI_API_KEY` by `codex-first-party`, and used for `codex login --with-api-key`. |
| `AAB_CODEX_FIRST_PARTY_MODEL` | Codex first-party model. Defaults to `gpt-5.5`. |
| `AAB_CODEX_THIRD_PARTY_OPENAI_BASE_URL` | OpenAI-compatible third-party base URL for Codex. Defaults to `https://inference-api.nvidia.com/v1`. |
| `AAB_CODEX_THIRD_PARTY_OPENAI_API_KEY` | OpenAI-compatible third-party API key for Codex. |
| `AAB_CODEX_THIRD_PARTY_OPENAI_MODEL` | Codex third-party OpenAI-compatible model. Defaults to `openai/openai/gpt-5.5`. |
| `AAB_CODEX_EFFORT` | Codex reasoning effort: `minimal`, `low`, `medium`, `high`, or `xhigh`. Defaults to `xhigh`. |
| `AAB_CODEX_SERVICE_TIER` | Codex service tier: `priority`, `flex`, `default`, or `fast` as an alias for `priority`. Defaults to `priority`. |
| `AAB_CODEX_AGENT_MAX_THREADS` | Maximum number of concurrently open Codex subagent threads. Defaults to `16`. |
| `AAB_BREV_API_KEY` | Brev organization-scoped API key. Used with `AAB_BREV_ORG_ID`. |
| `AAB_BREV_ORG_ID` | Brev organization ID paired with `AAB_BREV_API_KEY`. |
| `AAB_GH_TOKEN` | GitHub token. Stored in `~/.aab/.env`; wrappers map it to `GH_TOKEN` for agent subprocesses. |
| `AAB_GIT_AUTHOR_NAME` | `git config --global user.name`. |
| `AAB_GIT_AUTHOR_EMAIL` | `git config --global user.email`. |
| `AAB_GH_AUTH_SSH_PRIVATE_KEY_B64` | Base64-encoded OpenSSH private key for GitHub SSH auth. |
| `AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64` | Base64-encoded OpenSSH private key for git commit/tag signing. |
| `AAB_AGENT_PLUGINS_FILE` | Path to a local plugin marketplace list. |
| `AAB_AGENT_PLUGINS_URL` | URL for the plugin marketplace list when no local file is used. |

## What the Script Touches

| Path | How |
| --- | --- |
| `~/.aab/.env` | Rewritten with provider config, model names, and credentials. Mode `0600`; parent directory mode `0700`. |
| `~/.local/aab-bin/claude` | Claude launcher file for the selected provider; on PATH ahead of `~/.local/bin`. |
| `~/.local/bin/claude` | Left as the native installer's binary so the auto-updater can repoint it. |
| `~/.local/bin/claude-first-party` | Claude wrapper for first-party Anthropic. |
| `~/.local/bin/claude-third-party-anthropic` | Claude wrapper for Anthropic-compatible third-party gateways. |
| `~/.local/bin/claude-third-party-deepseek` | Claude wrapper for DeepSeek gateways. |
| `~/.local/bin/claude-third-party-nemotron` | Claude wrapper for Nemotron gateways. |
| `~/.local/bin/claude-aab-real` | Symlink to `~/.local/bin/claude`, so wrappers exec whatever the updater installs. |
| `~/.local/bin/codex` | Codex launcher file with the selected provider behavior. |
| `~/.local/bin/codex-first-party` | Codex wrapper for first-party OpenAI. |
| `~/.local/bin/codex-third-party-openai` | Codex wrapper for OpenAI-compatible third-party gateways. |
| `~/.local/bin/codex-aab-real` | Link or moved copy of the real Codex binary. |
| `~/.claude/settings.json` | Rewritten with unattended Claude defaults and plugin entries; existing file is backed up. |
| `~/.claude.json` | Merged with onboarding and optional API-key approval state; existing file is backed up. |
| `~/.codex/config.toml` | Rewritten with unattended Codex defaults and selected provider config while preserving Codex plugin tables; existing file is backed up. |
| `~/.codex/auth.json` | Written by `codex login --with-api-key` when first-party Codex API-key auth is configured. |
| `~/.bashrc` | Managed block for PATH and non-secret unattended-mode exports only. |
| `~/.profile` | Managed block that keeps `~/.local/aab-bin` ahead of `~/.local/bin` for login shells. |
| `/etc/environment` | Existing AAB managed blocks are removed so credentials do not remain there. |
| `~/.brev/credentials.json` | Written by `brev login --api-key ... --org-id ...` when Brev credentials are configured. |
| `~/.brev/onboarding_step.json` | Written to skip the Brev tutorial. |
| `~/.gitconfig` | git identity, GitHub credential helper, `core.hooksPath` for identity enforcement, and optional SSH signing config. |
| `~/.ssh/id_aab_auth`, `~/.ssh/config` | Written only when `AAB_GH_AUTH_SSH_PRIVATE_KEY_B64` is set. |
| `~/.ssh/id_aab_signing` | Written only when `AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64` is set. |
| `~/.aab/git-hooks/` | Global git hook dispatcher and per-hook-name symlinks that enforce the configured commit identity. `core.hooksPath` points here. See [Git Identity Enforcement](#git-identity-enforcement). |
| `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` | Managed block carrying the git-identity agent rule; other content is preserved. |

## SSH Keys

The bootstrap handles two independent optional SSH-key variables:

| Env var | Role |
| --- | --- |
| `AAB_GH_AUTH_SSH_PRIVATE_KEY_B64` | GitHub authentication for clone/push/pull over SSH. |
| `AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64` | git commit and tag signing only. |

Generate and encode a key:

```bash
ssh-keygen -t ed25519 -C "you@example.com" -f ~/.ssh/new_key -N ""
base64 -w0 < ~/.ssh/new_key
```

Set the encoded private key on the relevant AAB variable, and upload the public key to GitHub as either an authentication key, a signing key, or both.

## Git Identity Enforcement

The bootstrap configures a global git author, email, and (optionally) a commit-signing key, but unattended agents routinely commit under their own identity anyway — via `git -c user.email=...`, `git commit --author=...`, `GIT_AUTHOR_*` / `GIT_COMMITTER_*` environment variables, or a repo-local `git config user.email`. Two layers keep commits on the configured identity:

1. **An agent rule** is written to each harness's global instruction file — `~/.claude/CLAUDE.md` for Claude Code and `~/.codex/AGENTS.md` for Codex — both of which are loaded in every repository. The rule tells the agent to always commit with the configured identity and to leave the global git config alone. The rule lives inside a managed block (`# >>> autonomous-agent-bootstrap >>>` … `# <<< autonomous-agent-bootstrap <<<`), so re-running the bootstrap replaces it in place and any other content in those files is preserved.
2. **A global git hook** makes the rule non-optional. The bootstrap installs a dispatcher at `~/.aab/git-hooks/aab-git-hook`, symlinks it under each managed hook name, and points `core.hooksPath` at that directory. On `pre-commit` the dispatcher compares the commit's resolved author and committer identity (`git var GIT_AUTHOR_IDENT` / `GIT_COMMITTER_IDENT`) against the global `user.name` / `user.email`, and rejects the commit on a mismatch. When the global config requires signing (`commit.gpgsign=true`), it also rejects commits that disable signing via config or swap the signing key. The expected values are read from `--global`, which a per-invocation `-c`, an environment variable, or a repo-local config cannot override.

Because a global `core.hooksPath` replaces — rather than supplements — a repository's own `.git/hooks`, the dispatcher chains through to the repo's hook of the same name after its own checks pass, so projects that ship their own hooks (Husky, `pre-commit`, lint-staged, …) keep working.

The enforcement is intentionally scoped to identity and signing. It does not try to defeat the deliberate per-commit escape hatches git provides — `git commit --no-verify` skips all hooks, and `--no-gpg-sign` skips signing — which remain available for the rare legitimate case.

If no global `user.name` / `user.email` is configured, the hook is a no-op: there is nothing to enforce against, so all commits pass.

## Running the Tests

All tests are driven by [`./test.bash`](./test.bash).

```bash
./test.bash              # lint + unit
./test.bash --lint       # bash -n + shellcheck
./test.bash --unit       # bats suite
./test.bash --e2e        # destructive host e2e
./test.bash --docker     # e2e in a fresh ubuntu:22.04 container
./test.bash --smoke      # live Claude + Codex inference smoke
./test.bash --secrets    # gitleaks scan
./test.bash --all        # lint + unit + e2e + secrets
```

`--e2e` modifies the current `$HOME` and should only be run on a disposable machine. `--docker` is the safe bare-image check. `--smoke` spends real inference using the credentials in the current environment or the AAB wrapper configuration.
