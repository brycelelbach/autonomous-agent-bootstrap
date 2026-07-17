# ---------------------------------------------------------------------------
# Install / upgrade Pi from its official standalone Linux release.
# ---------------------------------------------------------------------------
install_pi() {
    local machine asset sha256
    machine=$(uname -m)
    case "$machine" in
        x86_64|amd64)
            asset="pi-linux-x64.tar.gz"
            sha256="$PI_SHA256_LINUX_X64"
            ;;
        aarch64|arm64)
            asset="pi-linux-arm64.tar.gz"
            sha256="$PI_SHA256_LINUX_ARM64"
            ;;
        *)
            warn "Pi has no supported standalone Linux release for ${machine}; skipping installation."
            return
            ;;
    esac

    log "Installing Pi ${PI_VERSION} via official standalone release..."
    local release_base="https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}"
    local tmpdir archive actual
    tmpdir=$(mktemp -d)
    archive="${tmpdir}/${asset}"

    if ! curl -fsSL "${release_base}/${asset}" -o "$archive"; then
        rm -rf "$tmpdir"
        warn "Could not download Pi ${PI_VERSION} standalone release."
        exit 1
    fi

    actual=$(sha256sum "$archive" | awk '{ print $1 }')
    if [ "$actual" != "$sha256" ]; then
        rm -rf "$tmpdir"
        warn "Pi ${PI_VERSION} checksum verification failed for ${asset}."
        exit 1
    fi

    tar -xzf "$archive" -C "$tmpdir"
    if [ ! -x "${tmpdir}/pi/pi" ]; then
        rm -rf "$tmpdir"
        warn "Pi release archive did not contain an executable pi binary."
        exit 1
    fi

    mkdir -p "$(dirname "$PI_INSTALL_DIR")" "${HOME}/.local/bin"
    rm -rf "$PI_INSTALL_DIR"
    mv "${tmpdir}/pi" "$PI_INSTALL_DIR"
    rm -rf "$tmpdir"
    ln -sfn "${PI_INSTALL_DIR}/pi" "${HOME}/.local/bin/pi-aab-real"
    log "Installed Pi ${PI_VERSION} at ${PI_INSTALL_DIR}."
}
