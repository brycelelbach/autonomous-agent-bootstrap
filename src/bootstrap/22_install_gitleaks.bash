# ---------------------------------------------------------------------------
# 9b-bis. Install gitleaks, the secret scanner the pre-commit hook runs. A
# single static Go binary (MIT, offline — no network at scan time), pinned to
# the same version and verified against the same per-arch SHA-256 the CI
# secret-scan job uses, so a commit blocked locally is a commit blocked in CI.
#
# Landed in ~/.local/bin (front of the managed PATH) so the hook finds it by
# name, with the absolute path as a fallback. Idempotent: a gitleaks already at
# the pinned version is left untouched. OS/arch-guarded: only linux x86_64 /
# arm64 release tarballs are pinned; anywhere else we skip cleanly and the hook
# falls back to its built-in shell secret grep. The download is verified before
# it is moved into place, so a corrupted or tampered fetch never installs.
# ---------------------------------------------------------------------------
install_gitleaks() {
    # Already at the pinned version? Leave it. `gitleaks version` prints a bare
    # version string (e.g. "8.18.4").
    if [ -x "$GITLEAKS_BIN" ] \
        && [ "$("$GITLEAKS_BIN" version 2>/dev/null | tr -d 'v[:space:]')" = "$GITLEAKS_VERSION" ]; then
        log "gitleaks ${GITLEAKS_VERSION} already installed at ${GITLEAKS_BIN}."
        return
    fi
    # A system-wide gitleaks at the pinned version (e.g. from CI's
    # /usr/local/bin install) also satisfies the requirement; the hook resolves
    # gitleaks via PATH first, so don't shadow it with a second copy.
    if command -v gitleaks >/dev/null 2>&1 \
        && [ "$(gitleaks version 2>/dev/null | tr -d 'v[:space:]')" = "$GITLEAKS_VERSION" ]; then
        log "gitleaks ${GITLEAKS_VERSION} already on PATH ($(command -v gitleaks)); not installing a second copy."
        return
    fi

    local os arch tarch sha
    os=$(uname -s 2>/dev/null || echo unknown)
    arch=$(uname -m 2>/dev/null || echo unknown)
    if [ "$os" != "Linux" ]; then
        warn "gitleaks: no pinned build for ${os}; skipping (the pre-commit hook's shell-grep fallback still scans commits)."
        return
    fi
    case "$arch" in
        x86_64|amd64) tarch="linux_x64";   sha="$GITLEAKS_SHA256_LINUX_X64" ;;
        aarch64|arm64) tarch="linux_arm64"; sha="$GITLEAKS_SHA256_LINUX_ARM64" ;;
        *)
            warn "gitleaks: no pinned build for ${arch}; skipping (the pre-commit hook's shell-grep fallback still scans commits)."
            return
            ;;
    esac

    if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
        warn "gitleaks: curl/tar unavailable; skipping install (the pre-commit hook's shell-grep fallback still scans commits)."
        return
    fi

    local url tmp
    url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_${tarch}.tar.gz"
    tmp=$(mktemp -d)
    log "Installing gitleaks ${GITLEAKS_VERSION} (${tarch}) for the pre-commit secret scan."
    if ! curl -fsSL "$url" -o "${tmp}/gitleaks.tar.gz"; then
        warn "gitleaks: download failed from ${url}; skipping (the pre-commit hook's shell-grep fallback still scans commits)."
        rm -rf "$tmp"
        return
    fi

    # Verify the tarball checksum before trusting its contents. Prefer
    # sha256sum, fall back to shasum -a 256 (neither is guaranteed on a bare
    # image, so degrade to a skip rather than install an unverified binary).
    local actual=""
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "${tmp}/gitleaks.tar.gz" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "${tmp}/gitleaks.tar.gz" | awk '{print $1}')
    else
        warn "gitleaks: no sha256sum/shasum to verify the download; skipping (the pre-commit hook's shell-grep fallback still scans commits)."
        rm -rf "$tmp"
        return
    fi
    if [ "$actual" != "$sha" ]; then
        warn "gitleaks: checksum mismatch (expected ${sha}, got ${actual}); refusing to install. The pre-commit hook's shell-grep fallback still scans commits."
        rm -rf "$tmp"
        return
    fi

    if ! tar -xzf "${tmp}/gitleaks.tar.gz" -C "$tmp" gitleaks 2>/dev/null; then
        warn "gitleaks: could not extract the binary from the tarball; skipping (the pre-commit hook's shell-grep fallback still scans commits)."
        rm -rf "$tmp"
        return
    fi
    mkdir -p "$(dirname "$GITLEAKS_BIN")"
    chmod 0755 "${tmp}/gitleaks"
    mv -f "${tmp}/gitleaks" "$GITLEAKS_BIN"
    rm -rf "$tmp"
    log "Installed gitleaks ${GITLEAKS_VERSION} at ${GITLEAKS_BIN}."
}

