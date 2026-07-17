# ---------------------------------------------------------------------------
# 4e. Install the private autocuda package as its own uv tool and run its
# plugin registration, best effort.
# autocuda lives behind brycelelbach-private, so it is not in uv_tools.txt — an
# installer without repository access must not fail here. `uv tool install`
# bundles autocuda's declared dependencies (matplotlib, pandas, adjustText,
# pygraphviz) into autocuda's own tool environment, so they need not be
# pre-installed. The git+https fetch authenticates via the same url.insteadOf
# token rewrite the plugin installers use; a missing token or no access logs a
# warning and the bootstrap continues. pygraphviz needs the system Graphviz
# headers and a C compiler (in apt_packages.txt), so a host lacking that
# toolchain degrades here rather than failing the bootstrap.
# ---------------------------------------------------------------------------
install_autocuda() {
    install_uv
    [ -n "${UV_BIN:-}" ] || { warn "uv unavailable; skipping autocuda install."; return; }

    local -a git_env=()
    mapfile -d '' git_env < <(_github_git_env)

    log "Installing the private autocuda package as a uv tool (best effort)."
    "${git_env[@]}" "$UV_BIN" tool install \
        "git+https://github.com/${AUTOCUDA_PRIVATE_REPO}@${AUTOCUDA_REF}" 2>&1 | sed 's/^/  /' \
        || warn "Could not install autocuda (private repo without access, or its build toolchain is absent); continuing without it."

    if ! command -v autocuda >/dev/null 2>&1; then
        warn "autocuda not on PATH (its private install was skipped); skipping autocuda install."
        return
    fi

    local snapshot=""
    if [ -f "$SETTINGS_FILE" ]; then
        snapshot="${SETTINGS_FILE}.pre-autocuda-install.bak"
        cp "$SETTINGS_FILE" "$snapshot"
    fi

    log "Registering the autocuda plugin via autocuda install."
    autocuda install 2>&1 | sed 's/^/  /' \
        || warn "autocuda install returned non-zero; register the autocuda plugin manually if needed."

    if [ -n "$snapshot" ] && [ -f "$snapshot" ]; then
        python3 - "$SETTINGS_FILE" "$snapshot" <<'PY'
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
        rm -f "$snapshot"
    fi
}
