# ---------------------------------------------------------------------------
# Install agent plugins listed in agent_plugins.txt.
#
# Each line is a GitHub owner/repo that hosts a plugin marketplace
# containing .claude-plugin/marketplace.json. Claude Code and Codex both
# understand that marketplace manifest. We fetch it once to discover the
# marketplace name and plugin names, then install the same resolved plugin
# selectors into both CLIs.
#
# The compiler embeds agent_plugins.txt below. AAB_AGENT_PLUGINS_FILE can
# replace the compiled list for a one-off local build.
# ---------------------------------------------------------------------------
AGENT_PLUGINS_DEFAULT_CONTENT=$(cat <<'AAB_AGENT_PLUGINS_EOF'
__AAB_AGENT_PLUGINS__
AAB_AGENT_PLUGINS_EOF
)
install_agent_plugins() {
    command -v python3 >/dev/null 2>&1 || { warn "python3 required for plugin install; skipping."; return; }
    local plugins_file="${AAB_AGENT_PLUGINS_FILE:-}"
    local content="$AGENT_PLUGINS_DEFAULT_CONTENT"
    if [ -n "$plugins_file" ]; then
        if [ ! -f "$plugins_file" ]; then
            warn "Plugin list file ${plugins_file} does not exist; skipping plugin install."
            return
        fi
        content=$(cat "$plugins_file")
        log "Reading plugin list override from ${plugins_file}."
    else
        log "Reading plugin list compiled into bootstrap.bash."
    fi

    # Strip comments and blanks into one repo per line.
    local -a repos=()
    while IFS= read -r line; do
        line="${line%%#*}"
        # trim
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] && continue
        repos+=("$line")
    done <<< "$content"

    if [ ${#repos[@]} -eq 0 ]; then
        log "Plugin list is empty; skipping plugin install."
        return
    fi

    # Private plugin repos need an authenticated fetch. Prefer `gh api` when
    # it's installed and authenticated (works for both public and private
    # repos); fall back to unauthenticated raw.githubusercontent.com so
    # public plugins still work on hosts without a gh login.
    local github_token="${GH_TOKEN:-${GITHUB_TOKEN:-${AAB_GH_TOKEN:-}}}"
    local -a github_env=(env)
    if [ -n "$github_token" ]; then
        github_env=(env "GH_TOKEN=$github_token")
    fi
    local use_gh=0
    if command -v gh >/dev/null 2>&1 && "${github_env[@]}" gh auth status >/dev/null 2>&1; then
        use_gh=1
    fi

    # Collect resolved tuples (repo|marketplace|plugin) for every plugin.
    local -a tuples=()
    local repo marketplace_json marketplace_name plugin_names plugin_name
    for repo in "${repos[@]}"; do
        marketplace_json=""
        for branch in main master; do
            if [ $use_gh -eq 1 ]; then
                marketplace_json=$("${github_env[@]}" gh api -H "Accept: application/vnd.github.v3.raw" \
                    "repos/${repo}/contents/.claude-plugin/marketplace.json?ref=${branch}" 2>/dev/null) \
                    || marketplace_json=""
            fi
            if [ -z "$marketplace_json" ]; then
                marketplace_json=$(curl -fsSL "https://raw.githubusercontent.com/${repo}/${branch}/.claude-plugin/marketplace.json" 2>/dev/null) \
                    || marketplace_json=""
            fi
            [ -n "$marketplace_json" ] && break
        done
        if [ -z "$marketplace_json" ]; then
            # Most commonly this means the repo is private and the caller
            # lacks access (or gh isn't authenticated). Plugin install is an
            # optional step; log and move on without failing the bootstrap.
            log "Could not fetch .claude-plugin/marketplace.json from ${repo} (private repo without access?); skipping."
            continue
        fi
        marketplace_name=$(printf '%s' "$marketplace_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("name",""))') || marketplace_name=""
        if [ -z "$marketplace_name" ]; then
            warn "${repo}/.claude-plugin/marketplace.json has no 'name'; skipping."
            continue
        fi
        plugin_names=$(printf '%s' "$marketplace_json" | python3 -c 'import json,sys; [print(p["name"]) for p in json.load(sys.stdin).get("plugins",[]) if p.get("name")]')
        if [ -z "$plugin_names" ]; then
            warn "${repo} marketplace lists no plugins; skipping."
            continue
        fi
        while IFS= read -r plugin_name; do
            [ -z "$plugin_name" ] && continue
            tuples+=("${repo}|${marketplace_name}|${plugin_name}")
        done <<< "$plugin_names"
    done

    if [ ${#tuples[@]} -eq 0 ]; then
        warn "No plugins resolved; skipping plugin install."
        return
    fi

    install_claude_code_plugins "${tuples[@]}"
    install_codex_plugins "${tuples[@]}"
}

install_claude_code_plugins() {
    local -a tuples=("$@")
    [ ${#tuples[@]} -eq 0 ] && return

    # Merge into ~/.claude/settings.json. configure_claude_settings has already run,
    # so the file exists and is valid JSON.
    python3 - "$SETTINGS_FILE" "${tuples[@]}" <<'PY'
import json, sys
path = sys.argv[1]
tuples = sys.argv[2:]
with open(path) as f:
    data = json.load(f)
extra = data.setdefault("extraKnownMarketplaces", {})
enabled = data.setdefault("enabledPlugins", {})
for t in tuples:
    repo, marketplace, plugin = t.split("|", 2)
    extra[marketplace] = {"source": {"source": "github", "repo": repo}}
    enabled[f"{plugin}@{marketplace}"] = True
    print(f"[bootstrap] Enabled plugin {plugin}@{marketplace} from github {repo}.")
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY

    # settings.json's extraKnownMarketplaces and enabledPlugins are
    # advisory: Claude Code's `plugin` CLI maintains its own registry
    # at ~/.claude/plugins/{known_marketplaces,installed_plugins}.json
    # that only `claude plugin marketplace add` + `claude plugin
    # install` populate. Without those, every `claude` (and every
    # ACP-driven harness like @openclaw/acpx that spawns claude) starts
    # with an empty installed_plugins.json — the agent's session-start
    # skills list contains only the bundled defaults, none of the
    # user-configured plugins. Materialise the install here so the
    # bootstrap leaves the user with a fully-registered plugin set.
    local claude_bin=""
    if [ -x "${HOME}/.local/bin/claude-aab-real" ]; then
        claude_bin="${HOME}/.local/bin/claude-aab-real"
    elif command -v claude >/dev/null 2>&1; then
        claude_bin=$(command -v claude)
    elif [ -x "${HOME}/.local/bin/claude" ]; then
        claude_bin="${HOME}/.local/bin/claude"
    else
        warn "claude binary not on PATH; skipping Claude Code plugin install (settings.json was still written)."
        return
    fi
    local github_token="${GH_TOKEN:-${GITHUB_TOKEN:-${AAB_GH_TOKEN:-}}}"
    local -a github_env=(env)
    if [ -n "$github_token" ]; then
        github_env=(env "GH_TOKEN=$github_token")
    fi

    # Snapshot the post-configure_claude_settings + post-merge settings.json so
    # the re-merge below can restore AAB-managed top-level keys that
    # Claude Code's plugin CLI strips on re-serialise.
    cp "$SETTINGS_FILE" "${SETTINGS_FILE}.pre-plugin-install.bak"

    # Dedupe repos before `marketplace add` (one marketplace can ship
    # several plugins; a 1-to-1 add per tuple would re-clone N times).
    local -A seen_repos=()
    local t repo marketplace plugin
    for t in "${tuples[@]}"; do
        repo="${t%%|*}"
        if [ -z "${seen_repos[$repo]:-}" ]; then
            log "Adding marketplace ${repo} to claude's plugin registry."
            "${github_env[@]}" "$claude_bin" plugin marketplace add "$repo" 2>&1 | sed 's/^/  /' || \
                warn "claude plugin marketplace add ${repo} returned non-zero (private repo without access? skipping)."
            seen_repos[$repo]=1
        fi
    done

    for t in "${tuples[@]}"; do
        repo="${t%%|*}"
        marketplace="${t#*|}"
        plugin="${marketplace#*|}"
        marketplace="${marketplace%|*}"
        log "Installing Claude Code plugin ${plugin}@${marketplace}."
        "${github_env[@]}" "$claude_bin" plugin install "${plugin}@${marketplace}" --scope user 2>&1 | sed 's/^/  /' || \
            warn "claude plugin install ${plugin}@${marketplace} returned non-zero."
    done

    # `claude plugin marketplace add` / `claude plugin install --scope
    # user` re-serialise ~/.claude/settings.json against Claude Code's
    # internal schema, which drops any top-level keys the schema
    # doesn't enumerate (notably `effortLevel` — written by
    # configure_claude_settings, asserted by tests/e2e-assertions.bash). Re-merge
    # the AAB-managed top-level keys back in from a snapshot taken
    # before the claude calls ran so the on-disk shape stays a
    # superset of what configure_claude_settings produced.
    if [ -f "${SETTINGS_FILE}.pre-plugin-install.bak" ]; then
        python3 - "$SETTINGS_FILE" "${SETTINGS_FILE}.pre-plugin-install.bak" <<'PY'
import json, sys
live_path, snap_path = sys.argv[1], sys.argv[2]
with open(live_path) as f:
    live = json.load(f)
with open(snap_path) as f:
    snap = json.load(f)
# Re-merge keys that AAB owns but Claude Code's plugin CLI strips on
# re-serialise. Keep the live values for keys the CLI updated.
for k in ("model", "effortLevel", "permissions", "skipDangerousModePermissionPrompt", "env"):
    if k in snap and k not in live:
        live[k] = snap[k]
with open(live_path, "w") as f:
    json.dump(live, f, indent=2)
PY
        rm -f "${SETTINGS_FILE}.pre-plugin-install.bak"
    fi
}

install_codex_plugins() {
    local -a tuples=("$@")
    [ ${#tuples[@]} -eq 0 ] && return

    local codex_bin=""
    if [ -x "${HOME}/.local/bin/codex-aab-real" ]; then
        codex_bin="${HOME}/.local/bin/codex-aab-real"
    elif command -v codex >/dev/null 2>&1; then
        codex_bin=$(command -v codex)
    elif [ -x "${HOME}/.local/bin/codex" ]; then
        codex_bin="${HOME}/.local/bin/codex"
    else
        warn "codex binary not on PATH; skipping Codex plugin install."
        return
    fi
    local github_token="${GH_TOKEN:-${GITHUB_TOKEN:-${AAB_GH_TOKEN:-}}}"
    local -a github_env=(env)
    if [ -n "$github_token" ]; then
        github_env=(env "GH_TOKEN=$github_token")
    fi

    # Dedupe repos before `marketplace add`.
    local -A seen_repos=()
    local t repo marketplace plugin
    for t in "${tuples[@]}"; do
        repo="${t%%|*}"
        if [ -z "${seen_repos[$repo]:-}" ]; then
            log "Adding marketplace ${repo} to codex's plugin registry."
            "${github_env[@]}" "$codex_bin" plugin marketplace add "$repo" 2>&1 | sed 's/^/  /' || \
                warn "codex plugin marketplace add ${repo} returned non-zero (private repo without access? skipping)."
            seen_repos[$repo]=1
        fi
    done

    for t in "${tuples[@]}"; do
        repo="${t%%|*}"
        marketplace="${t#*|}"
        plugin="${marketplace#*|}"
        marketplace="${marketplace%|*}"
        log "Installing Codex plugin ${plugin}@${marketplace}."
        "${github_env[@]}" "$codex_bin" plugin add "${plugin}@${marketplace}" 2>&1 | sed 's/^/  /' || \
            warn "codex plugin add ${plugin}@${marketplace} returned non-zero."
    done
}
