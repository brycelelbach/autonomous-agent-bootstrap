# autonomous-agent-bootstrap

A single idempotent bash script that turns a fresh Linux host into a ready-to-use Claude Code, Codex, and Pi agent environment. Built for Brev VMs but works on any Ubuntu/Debian host.

## What It Sets Up

1. **Claude Code** via the official native installer, configured for unattended use with `bypassPermissions`, a deny-only managed-settings policy for interactive human-in-the-loop tools, sandbox mode, debug logging, skipped onboarding, pre-approved first-party API-key fingerprints when provided, `CLAUDE_CODE_ATTRIBUTION_HEADER=0` so the per-request attribution block does not invalidate the prompt cache on third-party gateways, and OpenTelemetry usage logging to the console (`CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_LOGS_EXPORTER=console`) with prompt, tool, and raw-body content logging left disabled.
2. **Codex CLI** via OpenAI's standalone installer, configured with `approval_policy = "never"`, `sandbox_mode = "danger-full-access"`, trusted project roots, live web search, shell env inheritance, service tier, reasoning effort, detailed and raw reasoning traces, OpenTelemetry event recording with external exporters disabled and prompt logging off, and `[agents].max_threads`. A complete AAB-managed model-instructions prompt is installed at `~/.codex/codex-instructions.md` and selected globally with the absolute `model_instructions_file` path in `~/.codex/config.toml`.
3. **Pi** from its pinned official npm package on a pinned Node.js runtime, configured with an AAB-generated OpenAI Responses gateway provider, unattended retry/trust defaults, the packages in [`pi_plugins.txt`](./pi_plugins.txt), a tool-registry audit extension, per-process JSONL debug logs, and OpenTelemetry traces, metrics, and logs exported to the console by default.
4. **AAB env file** at `~/.aab/.env` for model profiles, selectors, and credentials. The bootstrap keeps these out of `~/.bashrc` and `/etc/environment`.
5. **Profile launcher families** in `~/.local/bin`, with source-explicit Claude and Codex aliases such as `claude-third-party-deepseek-v4` and `codex-first-party-gpt-5.5`, plus Pi aliases such as `pi-opus-4.8`. Pi omits `third-party` because every Pi profile uses the inference gateway.
6. **Brev CLI**, with optional `brev login --api-key ... --org-id ...` when `AAB_BREV_API_KEY` and `AAB_BREV_ORG_ID` are set.
7. **gh CLI**, installed as a pinned, checksum-verified standalone release.
8. **CLI tools as uv tools** — `uv` plus the tools listed in [`uv_tools.txt`](./uv_tools.txt), each installed with `uv tool install` into its own isolated environment with its executables symlinked into `~/.local/bin`, which the managed PATH blocks put ahead of the system dirs so a bare `ruff` / `pre-commit` resolves there. Built-in tool names resolve to the versions in [`src/bootstrap/00_versions.bash`](./src/bootstrap/00_versions.bash). The private `autocuda` package is installed best-effort from the immutable ref in the same version file (it is omitted from `uv_tools.txt` because it lives behind a private repo; a host without access — or without the Graphviz headers and compiler its `pygraphviz` dependency builds against — logs a warning and continues), and after the harnesses are in place `autocuda install` registers the autocuda plugin and worker with Claude Code, Codex, and Pi. Ubuntu package versions remain in [`apt_packages.txt`](./apt_packages.txt), agent plugins remain in [`agent_plugins.txt`](./agent_plugins.txt), and Pi packages remain in [`pi_plugins.txt`](./pi_plugins.txt).
9. **lifeboat** — a single-script home-directory backup tool fetched to `~/.local/bin/lifeboat`. It tars `$HOME`, keeping git history, source, and docs while dropping regenerable bulk (build artifacts, profiler dumps, caches, virtualenvs), to snapshot an agent's work before an ephemeral box is torn down. Compresses with `pigz` when present, falling back to `gzip`. Source: [`brycelelbach/lifeboat`](https://github.com/brycelelbach/lifeboat).
10. **git**, with optional author identity, GitHub credential helper, SSH auth key, and SSH signing key.
11. **Global agent rules** — clean rule text in every harness's global instruction file (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`) carrying the operating principles for an unattended agent in this sandbox (be concise, act autonomously, no harmful credentials) plus the git-identity rule. AAB tracks the generated text in a sidecar instead of adding management comments to agent prompts.
12. **Global git-identity enforcement** — the git-identity agent rule above, backed by a global git hook that rejects commits whose identity does not match the configured git config. See [Git Identity Enforcement](#git-identity-enforcement).
13. **Agent plugins** listed in [`agent_plugins.txt`](./agent_plugins.txt), installed into Claude Code and Codex, plus exact-version Pi packages listed in [`pi_plugins.txt`](./pi_plugins.txt). Pi uses upstream `nicobailon/pi-subagents`; Autocuda contributes its Pi-native worker through its own package manifest.
14. **User lingering** via `loginctl enable-linger`, so the per-user systemd instance and its bus stay up across SSH sessions. Unattended workloads that wrap commands in `systemd-run --user --scope` need the user bus available even when no interactive session is open. Skipped cleanly on hosts without a systemd user manager (e.g. a bare container).

## Requirements

- Ubuntu 22.04 host with `bash` and `apt-get`
- Passwordless `sudo`, or run as root
- A bare `ubuntu:22.04` image is valid; the bootstrap installs the version-pinned [`apt_packages.txt`](./apt_packages.txt) dependencies in one centralized step, then installs pinned Node.js and checksum-verified standalone `gh` releases.

## Quick Start

Export the profiles and credentials you want, then run the bootstrap:

```bash
export AAB_CLAUDE_FIRST_PARTY_PROFILES='opus-4.8 model=claude-opus-4-8 haiku=claude-haiku-4-5 sonnet=claude-sonnet-4-8 effort=high'
export AAB_CLAUDE_DEFAULT_PROFILE=first-party/opus-4.8

export AAB_CODEX_FIRST_PARTY_PROFILES='gpt-5.5 effort=xhigh'
export AAB_CODEX_DEFAULT_PROFILE=first-party/gpt-5.5

# Optional. If omitted, first-party launchers use existing interactive login.
export AAB_ANTHROPIC_API_KEY=...
export AAB_OPENAI_API_KEY=...

export AAB_GIT_AUTHOR_NAME='Your Name'
export AAB_GIT_AUTHOR_EMAIL=you@example.com

curl -fsSL https://raw.githubusercontent.com/brycelelbach/autonomous-agent-bootstrap/generated/bootstrap.bash | bash
source ~/.bashrc
claude -p "Say hello from Claude Code"
codex exec "Say hello from Codex"
```

The bootstrap also accepts the same exported variables through its optional sourced config-file or stdin mechanisms.

## Generated Bootstrap

`bootstrap.bash` is a generated, curlable artifact compiled from ordered source modules in `src/bootstrap/`. All non-apt, non-plugin package versions and immutable refs live in `src/bootstrap/00_versions.bash`; update that file when upgrading an installer. Claude, Codex, and Pi configuration live in `src/bootstrap/13_configure_claude.bash`, `src/bootstrap/13_configure_codex.bash`, and `src/bootstrap/13_configure_pi.bash`; Pi's non-shell assets live together in `src/pi/`. After editing a module, run:

```bash
python3 tools/compile_bootstrap.py
```

`./test.bash --lint` runs `python3 tools/compile_bootstrap.py --check`, so CI fails if `bootstrap.bash` is stale. The `Publish generated bootstrap` workflow compiles every pushed branch and publishes a curlable artifact branch in the same repository: `main` publishes to `generated`, and any other branch publishes to `generated/<branch-name>`. Forks publish to their own generated branches with the same workflow because the compiled script stamps the fork repository and generated ref into its side-file URLs.

## Model Profiles

Each profile variable contains one profile per line. A line starts with the versioned alias suffix followed by whitespace-separated `key=value` fields. Blank lines and lines beginning with `#` are ignored.

```bash
export AAB_CLAUDE_FIRST_PARTY_PROFILES='
opus-4.8 model=claude-opus-4-8 haiku=claude-haiku-4-5 sonnet=claude-sonnet-4-8 effort=high
'

export AAB_CLAUDE_THIRD_PARTY_PROFILES='
deepseek-v4 model=deepseek-v4-pro haiku=deepseek-v4-flash effort=high context=1000000
opus-4.8 model=bedrock/claude-opus-4-8 haiku=azure/claude-haiku-4-5 sonnet=bedrock/claude-sonnet-4-8 effort=high
'

export AAB_CODEX_FIRST_PARTY_PROFILES='
gpt-5.5 effort=xhigh
'

export AAB_CODEX_THIRD_PARTY_PROFILES='
gpt-5.5 effort=xhigh
'

export AAB_PI_PROFILES='
opus-4.8 model=aws/anthropic/bedrock-claude-opus-4-8 effort=max context=1000000 max_tokens=128000
gpt-5.6 model=openai/openai/gpt-5.6-sol effort=ultra context=1050000 max_tokens=128000
'
```

`model` defaults to the profile name. `effort` is passed through to the harness. Pi accepts its native `off`, `minimal`, `low`, `medium`, `high`, and `xhigh` levels directly; other values such as `ultra` are automatically mapped from Pi's `xhigh` level to the provider's value. Claude's `haiku`, `sonnet`, and `opus` slots each inherit `model`, so the DeepSeek profile above expands to `deepseek-v4-flash`, `deepseek-v4-pro`, and `deepseek-v4-pro` without repeating the Pro model. Optional Claude fields are `subagent` and `context`; optional Pi metadata fields are `context` and `max_tokens`.

First-party and third-party profiles coexist for Claude and Codex. The `*_DEFAULT_PROFILE` selectors only control the unqualified commands:

```bash
export AAB_CLAUDE_DEFAULT_PROFILE=third-party/deepseek-v4
export AAB_CODEX_DEFAULT_PROFILE=first-party/gpt-5.5
export AAB_PI_DEFAULT_PROFILE=opus-4.8
```

Every configured profile gets an explicit launcher:

- `claude-first-party-opus-4.8`
- `claude-third-party-deepseek-v4`
- `codex-first-party-gpt-5.5`
- `codex-third-party-gpt-5.5`
- `pi-opus-4.8`

Pi profiles are always third-party, so Pi aliases never include `third-party`.

All third-party profiles share one inference gateway:

```bash
export AAB_INFERENCE_GATEWAY_URL=https://gateway.example.com/v1
export AAB_INFERENCE_GATEWAY_API_KEY=...
```

First-party profiles map `AAB_ANTHROPIC_API_KEY` and `AAB_OPENAI_API_KEY` to the harness-native variables when present. If a key is absent, the launcher leaves the harness's interactive device/login state untouched.

## Environment Variables

All variables are optional unless a configured third-party profile needs the inference gateway.

| Variable | Effect |
| --- | --- |
| `AAB_CLAUDE_FIRST_PARTY_PROFILES` | Newline-delimited first-party Claude profiles. Defaults to the built-in versioned Opus profile. |
| `AAB_CLAUDE_THIRD_PARTY_PROFILES` | Newline-delimited gateway-backed Claude profiles. |
| `AAB_CLAUDE_DEFAULT_PROFILE` | Default `first-party/<name>` or `third-party/<name>` profile used by the unqualified `claude` command. |
| `AAB_CODEX_FIRST_PARTY_PROFILES` | Newline-delimited first-party Codex profiles. Defaults to the built-in versioned GPT profile. |
| `AAB_CODEX_THIRD_PARTY_PROFILES` | Newline-delimited gateway-backed Codex profiles. |
| `AAB_CODEX_DEFAULT_PROFILE` | Default `first-party/<name>` or `third-party/<name>` profile used by the unqualified `codex` command. |
| `AAB_PI_PROFILES` | Newline-delimited gateway-backed Pi profiles. |
| `AAB_PI_DEFAULT_PROFILE` | Default profile used by the unqualified `pi` command. Defaults to the first configured Pi profile. |
| `AAB_INFERENCE_GATEWAY_URL` | Shared base URL used by every third-party Claude/Codex profile and every Pi profile. |
| `AAB_INFERENCE_GATEWAY_API_KEY` | Shared inference-gateway key. It is mapped to each harness without placing the key on a command line. |
| `AAB_ANTHROPIC_API_KEY` | Optional first-party Anthropic key. Mapped to `ANTHROPIC_API_KEY` only for first-party Claude launchers. If absent, Claude's existing interactive login is used. |
| `AAB_OPENAI_API_KEY` | Optional first-party OpenAI key. Used to configure Codex API-key auth and mapped to `OPENAI_API_KEY` only for first-party Codex launchers. If absent, Codex's existing interactive login is used. |
| `AAB_CODEX_SERVICE_TIER` | Codex service tier: `priority`, `flex`, `default`, or `fast` as an alias for `priority`. Defaults to `priority`. |
| `AAB_CODEX_AGENT_MAX_THREADS` | Maximum number of concurrently open Codex subagent threads. Defaults to `64`. |
| `AAB_BREV_API_KEY` | Brev organization-scoped API key. Used with `AAB_BREV_ORG_ID`. |
| `AAB_BREV_ORG_ID` | Brev organization ID paired with `AAB_BREV_API_KEY`. |
| `AAB_GH_TOKEN` | GitHub token. Stored in `~/.aab/.env` and exported as `GH_TOKEN` from the private `~/.aab/shell/github.env` shell fragment. |
| `AAB_GIT_AUTHOR_NAME` | `git config --global user.name`. |
| `AAB_GIT_AUTHOR_EMAIL` | `git config --global user.email`. |
| `AAB_GH_AUTH_SSH_PRIVATE_KEY_B64` | Base64-encoded OpenSSH private key for GitHub SSH auth. |
| `AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64` | Base64-encoded OpenSSH private key for git commit/tag signing. |
| `AAB_AGENT_PLUGINS_FILE` | Optional local replacement for the plugin marketplace list compiled into `bootstrap.bash`. |
| `AAB_PI_PLUGINS_FILE` | Optional local replacement for the Pi package list compiled into `bootstrap.bash`. |
| `AAB_APT_PACKAGES_FILE` | Path to a local list of version-pinned Ubuntu package specifications to install with `apt-get`. |
| `AAB_APT_PACKAGES_URL` | URL for the Debian-package list when no local file is used. |
| `AAB_UV_TOOLS_FILE` | Path to a local list of CLI tools to install with `uv tool install`. |
| `AAB_UV_TOOLS_URL` | URL for the uv-tool list when no local file is used. |

## What the Script Touches

| Path | How |
| --- | --- |
| `~/.aab/.env` | Rewritten with profile definitions, selectors, and credentials. Mode `0600`; parent directory mode `0700`. |
| `~/.local/aab-bin/claude` | Claude launcher file for the selected profile; on PATH ahead of `~/.local/bin`. |
| `~/.local/bin/claude` | Left as the native installer's binary so the auto-updater can repoint it. |
| `~/.local/bin/claude-first-party-*` | One first-party Claude launcher per configured versioned profile. |
| `~/.local/bin/claude-third-party-*` | One inference-gateway Claude launcher per configured versioned profile. |
| `~/.local/bin/claude-aab-real` | Symlink to `~/.local/bin/claude`, so wrappers exec whatever the updater installs. |
| `~/.local/bin/codex` | Codex launcher file with the selected profile behavior. |
| `~/.local/bin/codex-first-party-*` | One first-party Codex launcher per configured versioned profile. |
| `~/.local/bin/codex-third-party-*` | One inference-gateway Codex launcher per configured versioned profile. |
| `~/.local/bin/codex-aab-real` | Link or moved copy of the real Codex binary. |
| `~/.local/bin/pi` | Pi launcher file for the selected profile, or an unconfigured launcher when no profiles are configured. Every launcher scopes Pi logging and OpenTelemetry variables to the Pi process. |
| `~/.local/bin/pi-*` | One gateway-backed Pi launcher per configured versioned profile; aliases omit `third-party`. |
| `~/.local/bin/pi-aab-real`, `~/.local/lib/node_modules/@earendil-works/pi-coding-agent/` | Pinned official npm Pi CLI and its runtime assets. |
| `~/.local/share/aab/node/`, `~/.local/bin/{node,npm,npx,corepack}` | Pinned official Node.js runtime used by Pi and Pi package installation. |
| `~/.pi/agent/settings.json` | Pi unattended defaults, selected gateway model, audit extension, and installed package registry. Machine identifiers and changelog state are not copied. |
| `~/.pi/agent/models.json` | Generated AAB inference-gateway provider and model catalog when Pi profiles are configured. |
| `~/.pi/agent/extensions/list-tools.ts` | Pi extension that prints the exact configured tool registry in table, verbose, or JSON form. |
| `~/.pi/agent/npm/pi-observability-preload.cjs`, `~/.pi/agent/debug/` | Launcher-only console capture that writes one structured JSONL debug file per Pi process. |
| `~/.aab/shell/github.env` | Private `GH_TOKEN` export generated from `AAB_GH_TOKEN`. Mode `0600`; sourced by the managed shell block. |
| `~/.aab/shell/pi-observability.env` | Pi-only telemetry defaults and `NODE_OPTIONS` preloads. Standard `OTEL_*` variables can override the console exporters. |
| `~/.claude/settings.json` | Rewritten with unattended Claude defaults and plugin entries; existing file is backed up. |
| `~/.claude.json` | Merged with onboarding and optional API-key approval state; existing file is backed up. |
| `~/.codex/config.toml` | Rewritten with unattended Codex defaults, the absolute global `model_instructions_file` path, and selected profile config while preserving Codex plugin tables; existing file is backed up. |
| `~/.codex/codex-instructions.md` | Complete AAB-managed Codex model-instructions prompt; existing file is backed up. |
| `~/.codex/auth.json` | Written by `codex login --with-api-key` when first-party Codex API-key auth is configured. |
| `~/.bashrc` | Managed block for PATH and AAB shell-fragment loading. Credential values remain in mode-`0600` files rather than appearing in the block. |
| `~/.profile` | Managed block that keeps `~/.local/aab-bin` ahead of `~/.local/bin` for login shells. |
| `/etc/environment` | Existing AAB managed blocks are removed so credentials do not remain there. |
| `/var/lib/systemd/linger/<user>` | Created by `loginctl enable-linger <user>` so the per-user systemd bus stays up across sessions. Skipped on hosts without a systemd user manager. |
| `~/.brev/credentials.json` | Written by `brev login --api-key ... --org-id ...` when Brev credentials are configured. |
| `~/.brev/onboarding_step.json` | Written to skip the Brev tutorial. |
| `~/.gitconfig` | git identity, GitHub credential helper, `core.hooksPath` for identity enforcement and the pre-commit secret scan, and optional SSH signing config. |
| `~/.local/bin/gitleaks` | The pinned gitleaks binary the pre-commit secret scan runs. Installed on linux x86_64 / arm64; skipped elsewhere (the hook falls back to a built-in shell scan). See [Secret Scanning](#secret-scanning). |
| `~/.ssh/id_aab_auth`, `~/.ssh/config` | Written only when `AAB_GH_AUTH_SSH_PRIVATE_KEY_B64` is set. |
| `~/.ssh/id_aab_signing` | Written only when `AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64` is set. |
| `~/.aab/git-hooks/` | Global git hook dispatcher and per-hook-name symlinks that enforce the configured commit identity and scan staged commits for secrets. `core.hooksPath` points here. See [Git Identity Enforcement](#git-identity-enforcement) and [Secret Scanning](#secret-scanning). |
| `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` | Clean global agent rules (operating principles + git-identity rule) without AAB management comments; other content is preserved. |
| `~/.aab/agent-rules.snapshot` | Exact generated rule text used to replace AAB's prior rules on subsequent runs without visible markers. |

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

1. **An agent rule** is written to each harness's global instruction file — `~/.claude/CLAUDE.md` for Claude Code and `~/.codex/AGENTS.md` for Codex — both of which are loaded in every repository. The rule tells the agent to always commit with the configured identity and to leave the global git config alone. AAB stores the exact generated text in `~/.aab/agent-rules.snapshot`, so re-running the bootstrap replaces its prior rules without putting management comments in agent prompts; any other content in those files is preserved.
2. **A global git hook** makes the rule non-optional. The bootstrap installs a dispatcher at `~/.aab/git-hooks/aab-git-hook`, symlinks it under each managed hook name, and points `core.hooksPath` at that directory. On `pre-commit` the dispatcher compares the commit's resolved author and committer identity (`git var GIT_AUTHOR_IDENT` / `GIT_COMMITTER_IDENT`) against the global `user.name` / `user.email`, and rejects the commit on a mismatch. When the global config requires signing (`commit.gpgsign=true`), it also rejects commits that disable signing via config or swap the signing key. The expected values are read from `--global`, which a per-invocation `-c`, an environment variable, or a repo-local config cannot override. The same `pre-commit` hook also runs a [secret scan](#secret-scanning) over the staged changes.

Because a global `core.hooksPath` replaces — rather than supplements — a repository's own `.git/hooks`, the dispatcher chains through to the repo's hook of the same name after its own checks pass, so projects that ship their own hooks (Husky, `pre-commit`, lint-staged, …) keep working.

The enforcement is intentionally scoped to identity and signing. It does not try to defeat the deliberate per-commit escape hatches git provides — `git commit --no-verify` skips all hooks, and `--no-gpg-sign` skips signing — which remain available for the rare legitimate case.

If no global `user.name` / `user.email` is configured, the hook is a no-op: there is nothing to enforce against, so all commits pass.

## Secret Scanning

The same global `pre-commit` hook scans every commit's staged changes for secrets **before** the commit lands, so a credential never reaches a git object an agent might push. (This exists because an unattended agent once committed a live GitHub admin token into a repo — nothing scanned the diff locally.) Because it rides the global `core.hooksPath` dispatcher, it covers **every** repository the agent clones or creates, including ones cloned after the bootstrap ran.

The scan runs after the identity check passes. It has two engines:

1. **gitleaks (preferred).** The bootstrap installs the [gitleaks](https://github.com/gitleaks/gitleaks) binary (a single static MIT-licensed executable that scans entirely offline) at `~/.local/bin/gitleaks`, pinned by [`src/bootstrap/00_versions.bash`](./src/bootstrap/00_versions.bash) to the same version and SHA-256 that CI uses. The hook resolves gitleaks by name on `PATH` (falling back to the absolute install path) and runs `gitleaks protect --staged --redact --no-banner`; a finding fails the commit, with the secret value redacted from the output. The binary is only installed on linux x86_64 / arm64; on any other OS or architecture the install step is skipped cleanly.

2. **Built-in shell fallback.** If gitleaks is not available (install skipped on an unsupported platform, offline, or a checksum mismatch), the hook greps the staged diff's added lines for the highest-value credential shapes so a commit is never left wholly unscanned: GitHub tokens (`ghp_` / `gho_` / `ghs_` / `ghr_…`, `github_pat_…`), URL-embedded credentials (`https://user:pass@…`, `x-access-token:…`), AWS access-key ids (`AKIA…`), OpenAI / Anthropic-style `sk-…` keys, Google `AIza…` keys, Slack `xox…` tokens, PEM `-----BEGIN … PRIVATE KEY-----` blocks, and JWTs.

**Bypass.** When a flagged "secret" is a deliberate fixture or test vector, set `GITLEAKS_ALLOW=1` in the environment for that commit (`GITLEAKS_ALLOW=1 git commit …`), or use `git commit --no-verify` to skip every hook. Both are documented escape hatches; prefer `GITLEAKS_ALLOW=1`, which skips only the secret scan and keeps identity enforcement in force.

`./test.bash --secrets` remains the separate, full-history gitleaks scan run in CI; the pre-commit hook is the faster, staged-only gate that runs on every commit.

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
