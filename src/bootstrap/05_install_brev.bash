# ---------------------------------------------------------------------------
# 3. Install the pinned Brev CLI release.
# ---------------------------------------------------------------------------
install_brev() {
    local arch sha256
    case "$(uname -m)" in
        x86_64|amd64)
            arch="amd64"
            sha256="$BREV_SHA256_LINUX_AMD64"
            ;;
        aarch64|arm64)
            arch="arm64"
            sha256="$BREV_SHA256_LINUX_ARM64"
            ;;
        *)
            warn "Unsupported architecture for Brev ${BREV_VERSION}: $(uname -m)."
            return
            ;;
    esac

    local asset tmp_dir archive
    asset="brev-cli_${BREV_VERSION}_linux_${arch}.tar.gz"
    tmp_dir=$(mktemp -d)
    archive="${tmp_dir}/${asset}"
    log "Installing Brev CLI ${BREV_VERSION} from its official release..."
    if ! curl -fsSL \
        "https://github.com/brevdev/brev-cli/releases/download/v${BREV_VERSION}/${asset}" \
        -o "$archive"; then
        rm -rf "$tmp_dir"
        warn "Could not download Brev CLI ${BREV_VERSION}."
        exit 1
    fi
    if ! printf '%s  %s\n' "$sha256" "$archive" | sha256sum -c - >/dev/null; then
        rm -rf "$tmp_dir"
        warn "Brev CLI ${BREV_VERSION} checksum verification failed."
        exit 1
    fi
    tar -xzf "$archive" -C "$tmp_dir"
    if [ ! -x "${tmp_dir}/brev" ]; then
        rm -rf "$tmp_dir"
        warn "Brev CLI ${BREV_VERSION} archive did not contain an executable brev binary."
        exit 1
    fi
    mkdir -p "${HOME}/.local/bin"
    install -m 0755 "${tmp_dir}/brev" "${HOME}/.local/bin/brev"
    rm -rf "$tmp_dir"
    log "Installed Brev CLI ${BREV_VERSION} to ${HOME}/.local/bin/brev."
}
