# Configurable Model Profiles Plan

## Goal

Replace model-specific AAB variables and hardcoded provider launchers with a small environment-variable contract that can define arbitrary, versioned model profiles without changing AAB.

## Configuration Contract

AAB accepts newline-delimited profiles through these variables:

- `AAB_CLAUDE_FIRST_PARTY_PROFILES`
- `AAB_CLAUDE_THIRD_PARTY_PROFILES`
- `AAB_CODEX_FIRST_PARTY_PROFILES`
- `AAB_CODEX_THIRD_PARTY_PROFILES`
- `AAB_PI_PROFILES`

Each non-empty line starts with the versioned alias suffix, followed by whitespace-separated `key=value` fields. Blank lines and lines beginning with `#` are ignored.

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
opus-4.8 model=anthropic/claude-opus-4-8 effort=high
'
```

The selected unqualified launchers are controlled independently:

```bash
export AAB_CLAUDE_PROFILE=first-party/opus-4.8
export AAB_CODEX_PROFILE=first-party/gpt-5.5
export AAB_PI_PROFILE=opus-4.8
```

Selection only chooses what `claude`, `codex`, or `pi` runs. It does not make backend selection harness-wide; every explicit profile retains its own first-party or third-party route.

Third-party profiles share one gateway:

```bash
export AAB_INFERENCE_GATEWAY_URL=https://gateway.example.com
export AAB_INFERENCE_GATEWAY_API_KEY=...
```

First-party Claude and Codex use `ANTHROPIC_API_KEY` and `OPENAI_API_KEY` when provided. When either is absent, AAB leaves that harness's interactive login state in control.

## Profile Semantics

- `model` defaults to the profile alias when omitted.
- `effort` is profile-specific and maps to the harness's native effort setting.
- Claude always receives `ANTHROPIC_MODEL` plus all three tier variables. `haiku`, `sonnet`, and `opus` each inherit `model` unless explicitly overridden.
- Claude `subagent` optionally overrides `CLAUDE_CODE_SUBAGENT_MODEL`; otherwise it inherits the resolved primary model.
- Claude `context` optionally enables the explicit auto-compaction window required by unknown third-party model identifiers.
- Pi `context` and `max_tokens` optionally populate its generated custom-model metadata.
- Unknown fields, malformed aliases, duplicate aliases, and invalid numeric fields fail bootstrap with an actionable error.

## Generated Commands

Claude and Codex aliases retain routing in their names:

- `claude-first-party-opus-4.8`
- `claude-third-party-deepseek-v4`
- `codex-first-party-gpt-5.5`
- `codex-third-party-gpt-5.5`

Pi is always gateway-backed, so its aliases omit `third-party`:

- `pi-opus-4.8`

## Implementation

1. Add reusable Bash parsing and profile-resolution helpers.
2. Persist the profile variables, selectors, standard first-party keys, and shared gateway settings in `~/.aab/.env`.
3. Resolve the selected Claude and Codex profiles when writing their base configuration.
4. Generate one launcher per configured profile and make the unqualified command use its selected profile.
5. Replace model-name-specific Claude context handling with the optional `context` field.
6. Install Pi from its official standalone Linux release, generate its gateway provider catalog from `AAB_PI_PROFILES`, and generate `pi-${profile}` launchers.
7. Remove stale AAB-owned launchers when profiles are deleted or renamed.
8. Update README examples and the environment-variable reference.
9. Add parser, inheritance, routing, effort, alias, persistence, and Pi configuration tests.
10. Regenerate `bootstrap.bash`, then run lint, unit, Docker end-to-end, and secret-scan validation.

## Compatibility Boundary

The generated profile aliases replace the fixed provider/model launcher matrix. The unqualified `claude` and `codex` commands keep first-party defaults when no profile variables are supplied. Existing interactive authentication remains valid because first-party launchers do not invent or require API keys.
