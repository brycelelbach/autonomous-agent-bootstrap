# ---------------------------------------------------------------------------
# 0. Install the pinned Ubuntu base dependencies listed in apt_packages.txt via
# apt-get. Bare container images (e.g. ubuntu:22.04) ship with apt-get but
# nothing else, so we can't assume curl or python3 exist. apt no-ops packages
# that are already installed, so the whole list is installed unconditionally.
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

    log "Installing pinned apt packages: ${packages[*]}."
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -y
    # Hosted Ubuntu images can carry newer packages from PPAs. The explicit
    # pins are authoritative, so permit apt to restore the configured versions.
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades --no-install-recommends "${packages[@]}"
}
