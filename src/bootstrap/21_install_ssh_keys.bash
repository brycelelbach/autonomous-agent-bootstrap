# ---------------------------------------------------------------------------
# 9b. Install SSH keys supplied via $AAB_GH_AUTH_SSH_PRIVATE_KEY_B64 (for
# github.com auth: clone/push over SSH) and/or
# $AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64 (for git commit/tag signing). These are
# two separate roles and the
# bootstrap treats them independently: either may be set, or both, or
# neither. The signing key path does NOT touch ~/.ssh/config.
# ---------------------------------------------------------------------------

# _require_ssh_keygen: Verify the pinned openssh-client package supplied
# ssh-keygen. Package installation is centralized in install_base_deps().
_require_ssh_keygen() {
    command -v ssh-keygen >/dev/null 2>&1 && return 0
    warn "ssh-keygen is unavailable after installing the pinned apt package list."
    return 1
}

# _decode_ssh_key <encoded> <dest> <label>
# Decodes a base64-encoded OpenSSH private key to <dest> (mode 0600) and
# derives the public half to <dest>.pub (mode 0644). <label> is the env
# var name for log / warn messages. Returns 0 on success. On failure,
# cleans up any partial files and warns with <label> for context.
_decode_ssh_key() {
    local encoded="$1" dest="$2" label="$3"
    local dest_pub="${dest}.pub"

    mkdir -p "$SSH_DIR"
    chmod 0700 "$SSH_DIR"

    if ! printf '%s' "$encoded" | base64 -d > "$dest" 2>/dev/null; then
        warn "${label} is not valid base64; skipping."
        rm -f "$dest"
        return 1
    fi
    chmod 0600 "$dest"

    if ! ssh-keygen -y -f "$dest" > "$dest_pub" 2>/dev/null; then
        warn "${label} did not decode to a valid SSH private key; skipping."
        rm -f "$dest" "$dest_pub"
        return 1
    fi
    chmod 0644 "$dest_pub"
    return 0
}

# _rewrite_ssh_config_block: Idempotently rewrite the managed block in
# ~/.ssh/config so github.com uses the supplied IdentityFile. Strips any
# previous managed block plus its trailing padding so the file size stays
# stable across re-runs and pre-existing entries outside the block are
# preserved.
_rewrite_ssh_config_block() {
    local key="$1"
    touch "$SSH_CONFIG"
    python3 - "$SSH_CONFIG" "$key" "$SSH_MARKER_BEGIN" "$SSH_MARKER_END" <<'PY'
import sys
path, key, begin, end = sys.argv[1:5]
with open(path) as f:
    lines = f.read().splitlines()
out = []
in_block = False
for line in lines:
    if line == begin:
        in_block = True
        continue
    if line == end:
        in_block = False
        continue
    if not in_block:
        out.append(line)
while out and out[-1].strip() == "":
    out.pop()
block = [
    begin,
    "Host github.com",
    f"    IdentityFile {key}",
    "    IdentitiesOnly yes",
    end,
]
parts = []
if out:
    parts.append("\n".join(out))
    parts.append("")  # one blank line between user content and our block
parts.append("\n".join(block))
with open(path, "w") as f:
    f.write("\n".join(parts) + "\n")
PY
    chmod 0600 "$SSH_CONFIG"
}

# install_auth_ssh_key: Decode $AAB_GH_AUTH_SSH_PRIVATE_KEY_B64 to
# ~/.ssh/id_aab_auth and wire it as the IdentityFile for github.com in
# ~/.ssh/config. Does NOT touch git signing config. Silent no-op when the
# env var is unset.
install_auth_ssh_key() {
    local encoded="${AAB_GH_AUTH_SSH_PRIVATE_KEY_B64:-}"
    local label="AAB_GH_AUTH_SSH_PRIVATE_KEY_B64"
    [ -z "$encoded" ] && return

    if ! command -v base64 >/dev/null 2>&1; then
        warn "base64 not installed; cannot decode ${label}; skipping."
        return
    fi
    _require_ssh_keygen || { warn "Skipping ${label} install (ssh-keygen unavailable)."; return; }
    _decode_ssh_key "$encoded" "$AUTH_KEY" "$label" || return 0

    _rewrite_ssh_config_block "$AUTH_KEY"
    log "Installed GitHub auth SSH key at $AUTH_KEY (pub $AUTH_KEY_PUB); wired github.com identity in $SSH_CONFIG."
}

# install_signing_ssh_key: Decode $AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64 to
# ~/.ssh/id_aab_signing and configure git to sign commits/tags with it.
# Does NOT touch ~/.ssh/config — this key is for signing only. Silent
# no-op when the env var is unset.
install_signing_ssh_key() {
    local encoded="${AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64:-}"
    local label="AAB_GIT_SSH_SIGNING_PRIVATE_KEY_B64"
    [ -z "$encoded" ] && return

    if ! command -v base64 >/dev/null 2>&1; then
        warn "base64 not installed; cannot decode ${label}; skipping."
        return
    fi
    _require_ssh_keygen || { warn "Skipping ${label} install (ssh-keygen unavailable)."; return; }
    _decode_ssh_key "$encoded" "$SIGNING_KEY" "$label" || return 0

    if command -v git >/dev/null 2>&1; then
        git config --global gpg.format ssh
        git config --global user.signingkey "$SIGNING_KEY_PUB"
        git config --global commit.gpgsign true
        git config --global tag.gpgsign true
        log "Configured git to sign commits and tags with $SIGNING_KEY_PUB."
    else
        warn "git not installed; skipping SSH signing config."
    fi
}
