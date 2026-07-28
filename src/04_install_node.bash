# ---------------------------------------------------------------------------
# Install the pinned Node.js runtime that backs Pi and its npm/git packages.
# ---------------------------------------------------------------------------
install_node() {
    local machine asset sha256
    machine=$(uname -m)
    case "$machine" in
        x86_64|amd64)
            asset="node-v${NODE_VERSION}-linux-x64.tar.gz"
            sha256="$NODE_SHA256_LINUX_X64"
            ;;
        aarch64|arm64)
            asset="node-v${NODE_VERSION}-linux-arm64.tar.gz"
            sha256="$NODE_SHA256_LINUX_ARM64"
            ;;
        *)
            warn "Node.js has no configured AAB release for ${machine}; skipping installation."
            return
            ;;
    esac

    local node_bin="${NODE_INSTALL_DIR}/bin/node"
    if [ -x "$node_bin" ] && [ "$("$node_bin" --version 2>/dev/null)" = "v${NODE_VERSION}" ]; then
        log "Node.js ${NODE_VERSION} is already installed at ${NODE_INSTALL_DIR}."
    else
        log "Installing Node.js ${NODE_VERSION} from the official release."
        local tmpdir archive extracted actual
        tmpdir=$(mktemp -d)
        archive="${tmpdir}/${asset}"
        extracted="${tmpdir}/${asset%.tar.gz}"
        curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/${asset}" -o "$archive"
        actual=$(sha256sum "$archive" | awk '{ print $1 }')
        if [ "$actual" != "$sha256" ]; then
            rm -rf "$tmpdir"
            warn "Node.js ${NODE_VERSION} checksum verification failed for ${asset}."
            exit 1
        fi
        tar -xzf "$archive" -C "$tmpdir"
        if [ ! -x "${extracted}/bin/node" ] || [ ! -x "${extracted}/bin/npm" ]; then
            rm -rf "$tmpdir"
            warn "Node.js release archive did not contain node and npm executables."
            exit 1
        fi
        mkdir -p "$(dirname "$NODE_INSTALL_DIR")" "${HOME}/.local/bin"
        rm -rf "$NODE_INSTALL_DIR"
        mv "$extracted" "$NODE_INSTALL_DIR"
        rm -rf "$tmpdir"
    fi

    local executable
    for executable in node npm npx corepack; do
        if [ -e "${NODE_INSTALL_DIR}/bin/${executable}" ]; then
            ln -sfn "${NODE_INSTALL_DIR}/bin/${executable}" "${HOME}/.local/bin/${executable}"
        fi
    done
    case ":${PATH}:" in
        *":${HOME}/.local/bin:"*) ;;
        *) export PATH="${HOME}/.local/bin:${PATH}" ;;
    esac
}
