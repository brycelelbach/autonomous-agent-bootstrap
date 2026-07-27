# ---------------------------------------------------------------------------
# 3. Install the latest Brev CLI release.
# ---------------------------------------------------------------------------
install_brev() {
    local arch
    case "$(uname -m)" in
        x86_64|amd64)
            arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        *)
            warn "Unsupported architecture for Brev: $(uname -m)."
            return
            ;;
    esac

    local github_token="${GH_TOKEN:-${GITHUB_TOKEN:-${AAB_GH_TOKEN:-}}}"
    local api_url="https://api.github.com/repos/brevdev/brev-cli/releases/latest"
    local curl_args=(-fsSL)
    if [ -n "$github_token" ]; then
        curl_args+=(
            -H "Authorization: Bearer ${github_token}"
            -H "X-GitHub-Api-Version: 2022-11-28"
        )
    fi

    local tmp_dir release_json tag version asset checksums archive
    tmp_dir=$(mktemp -d)
    release_json="${tmp_dir}/release.json"
    if ! curl "${curl_args[@]}" "$api_url" -o "$release_json"; then
        rm -rf "$tmp_dir"
        warn "Could not resolve the latest Brev CLI release."
        exit 1
    fi
    tag=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["tag_name"])' "$release_json")
    version="${tag#v}"
    asset="brev-cli_${version}_linux_${arch}.tar.gz"
    checksums="${tmp_dir}/brev-checksums.txt"
    archive="${tmp_dir}/${asset}"
    log "Installing latest Brev CLI release ${version}..."
    if ! curl -fsSL \
        "https://github.com/brevdev/brev-cli/releases/download/${tag}/brev-cli_${version}_checksums.txt" \
        -o "$checksums" \
        || ! curl -fsSL \
        "https://github.com/brevdev/brev-cli/releases/download/${tag}/${asset}" \
        -o "$archive"; then
        rm -rf "$tmp_dir"
        warn "Could not download Brev CLI ${version}."
        exit 1
    fi
    if ! (cd "$tmp_dir" && grep -F "  ${asset}" brev-checksums.txt | sha256sum -c - >/dev/null); then
        rm -rf "$tmp_dir"
        warn "Brev CLI ${version} checksum verification failed."
        exit 1
    fi
    tar -xzf "$archive" -C "$tmp_dir"
    if [ ! -x "${tmp_dir}/brev" ]; then
        rm -rf "$tmp_dir"
        warn "Brev CLI ${version} archive did not contain an executable brev binary."
        exit 1
    fi
    mkdir -p "${HOME}/.local/bin"
    install -m 0755 "${tmp_dir}/brev" "${HOME}/.local/bin/brev"
    rm -rf "$tmp_dir"
    log "Installed Brev CLI ${version} to ${HOME}/.local/bin/brev."
}
