# ---------------------------------------------------------------------------
# Enable user lingering so the per-user systemd instance — and its bus at
# $XDG_RUNTIME_DIR/bus — stays up across SSH sessions instead of dying with the
# login session. Unattended agent workloads that wrap commands in
# `systemd-run --user --scope` (e.g. autocuda's `run slice`, which caps build
# CPU/memory) need the user bus available even when no interactive session is
# open. `loginctl enable-linger` is the one-time setup for that. Skip cleanly on
# hosts without a systemd user manager (bare containers) or without sudo.
# ---------------------------------------------------------------------------
enable_user_linger() {
    local user
    user=$(id -un)

    if ! command -v loginctl >/dev/null 2>&1; then
        log "loginctl not available (no systemd); skipping user-linger setup."
        return
    fi

    # Already lingering: keep re-runs quiet and avoid a needless sudo call.
    if [ "$(loginctl show-user "$user" --property=Linger --value 2>/dev/null)" = "yes" ]; then
        log "User lingering already enabled for ${user}."
        return
    fi

    if [ -n "$SUDO" ] && ! sudo -n true 2>/dev/null; then
        warn "Enabling user lingering for ${user} needs sudo and passwordless sudo is not available; run 'sudo loginctl enable-linger ${user}' so the user systemd bus stays up across sessions."
        return
    fi

    if $SUDO loginctl enable-linger "$user" 2>/dev/null; then
        log "Enabled user lingering for ${user} (user systemd bus stays up across sessions)."
    else
        warn "Could not enable user lingering for ${user}; run 'sudo loginctl enable-linger ${user}' so the user systemd bus stays up across sessions."
    fi
}
