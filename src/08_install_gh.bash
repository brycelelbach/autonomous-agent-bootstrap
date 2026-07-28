# ---------------------------------------------------------------------------
# 4. Install a pinned gh CLI standalone release. gh intentionally does not use
# apt so every apt invocation remains centralized in install_base_deps().
# ---------------------------------------------------------------------------
install_gh() {
    if command -v gh >/dev/null 2>&1 \
        && gh --version 2>/dev/null | head -n 1 | grep -q "gh version ${GH_VERSION} "; then
        log "gh ${GH_VERSION} already installed."
        return
    fi

    local arch sha256
    case "$(uname -m)" in
        x86_64|amd64)
            arch="amd64"
            sha256="$GH_SHA256_LINUX_AMD64"
            ;;
        aarch64|arm64)
            arch="arm64"
            sha256="$GH_SHA256_LINUX_ARM64"
            ;;
        *)
            warn "Unsupported architecture for gh ${GH_VERSION}: $(uname -m)."
            return
            ;;
    esac

    local tmp_dir archive extracted
    tmp_dir=$(mktemp -d)
    archive="${tmp_dir}/gh.tar.gz"
    extracted="${tmp_dir}/gh_${GH_VERSION}_linux_${arch}/bin/gh"
    if ! curl -fsSL \
        "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${arch}.tar.gz" \
        -o "$archive"; then
        warn "Could not download gh ${GH_VERSION}."
        rm -rf "$tmp_dir"
        return
    fi
    if ! printf '%s  %s\n' "$sha256" "$archive" | sha256sum -c - >/dev/null; then
        warn "Checksum verification failed for gh ${GH_VERSION}."
        rm -rf "$tmp_dir"
        return
    fi
    tar -xzf "$archive" -C "$tmp_dir"
    mkdir -p "${HOME}/.local/bin"
    install -m 0755 "$extracted" "${HOME}/.local/bin/gh"
    rm -rf "$tmp_dir"
    log "Installed gh ${GH_VERSION} to ${HOME}/.local/bin/gh."
}
