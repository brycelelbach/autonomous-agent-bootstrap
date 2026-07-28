# ---------------------------------------------------------------------------
# 0. Install the Ubuntu base dependencies listed in apt_packages.txt via
# apt-get. Bare container images ship with apt-get but nothing else, so we
# can't assume curl or python3 exist. The preferred versions are used when the
# current distribution provides them; otherwise its available versions are
# installed. apt no-ops packages that are already installed, so the whole list
# is installed unconditionally.
#
# The list is taken from (in order): $AAB_APT_PACKAGES_FILE, then
# ./apt_packages.txt when present, otherwise $AAB_APT_PACKAGES_URL.
# ---------------------------------------------------------------------------
APT_PACKAGES_DEFAULT_FILE="${PWD}/apt_packages.txt"
APT_PACKAGES_DEFAULT_URL="https://raw.githubusercontent.com/${AAB_BOOTSTRAP_REPO}/${AAB_BOOTSTRAP_REF}/apt_packages.txt"
install_base_deps() {
    local packages_file="${AAB_APT_PACKAGES_FILE:-}"
    local packages_url="${AAB_APT_PACKAGES_URL:-$APT_PACKAGES_DEFAULT_URL}"
    local content=""
    if [ -n "$packages_file" ] && [ -f "$packages_file" ]; then
        content=$(cat "$packages_file")
        log "Reading apt package list from ${packages_file}."
    elif [ -z "$packages_file" ] && [ -f "$APT_PACKAGES_DEFAULT_FILE" ]; then
        content=$(cat "$APT_PACKAGES_DEFAULT_FILE")
        log "Reading apt package list from ${APT_PACKAGES_DEFAULT_FILE}."
    elif content=$(curl -fsSL "$packages_url" 2>/dev/null); then
        log "Fetched apt package list from ${packages_url}."
    else
        warn "Could not read apt package list (file=${packages_file:-unset}, url=${packages_url}); skipping base dep install."
        return
    fi

    # Strip comments and blanks into one package per line.
    local -a packages=()
    while IFS= read -r line; do
        line="${line%%#*}"
        # trim
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] && continue
        case "$line" in
            *=?*) ;;
            *)
                warn "apt package entry '${line}' is not version-pinned (expected package=version)."
                return 1
                ;;
        esac
        packages+=("$line")
    done <<< "$content"

    if [ ${#packages[@]} -eq 0 ]; then
        log "apt package list is empty; skipping base dep install."
        return
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
        warn "Base deps (${packages[*]}) needed and apt-get is not available; install them manually and re-run."
        return
    fi
    if [ -n "$SUDO" ] && ! sudo -n true 2>/dev/null; then
        warn "Base deps (${packages[*]}) needed and passwordless sudo is not available; install them manually and re-run."
        return
    fi

    log "Updating apt package metadata."
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -y

    local -a install_packages=("${packages[@]}")
    if ! $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --simulate --allow-downgrades --no-install-recommends "${install_packages[@]}" >/dev/null 2>&1; then
        install_packages=()
        local package
        for package in "${packages[@]}"; do
            install_packages+=("${package%%=*}")
        done
        warn "Preferred apt package versions are unavailable on this distribution; using its available versions."
    fi

    log "Installing apt packages: ${install_packages[*]}."
    # Hosted Ubuntu images can carry newer packages from PPAs. When the
    # preferred versions are available, permit apt to restore them.
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades --no-install-recommends "${install_packages[@]}"
}
