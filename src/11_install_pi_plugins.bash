# ---------------------------------------------------------------------------
# Reinstall the Pi packages listed in pi_plugins.txt.
#
# The compiler embeds pi_plugins.txt below. AAB_PI_PLUGINS_FILE can replace
# the optional package list for a one-off local build. Fast Pi profiles still
# require the fast-mode provider package.
# ---------------------------------------------------------------------------
PI_PLUGINS_DEFAULT_CONTENT=$(cat <<'AAB_PI_PLUGINS_EOF'
__AAB_PI_PLUGINS__
AAB_PI_PLUGINS_EOF
)
PI_FAST_MODE_SOURCE="git:github.com/robobryce/pi-fast-mode"
PI_FAST_MODE_CHECKOUT="${PI_DIR}/git/github.com/robobryce/pi-fast-mode"
PI_PREVIOUS_FAST_MODE_SOURCE=""

_pi_fast_mode_required() {
    local profiles line
    local -A profile=()
    profiles=$(_profile_list_for pi third-party)
    while IFS= read -r line; do
        _parse_model_profile_line pi third-party "$line" profile
        if [ "${profile[fast]:-false}" = true ]; then
            return 0
        fi
    done < <(_model_profile_lines "$profiles")
    return 1
}

_is_pi_fast_mode_source() {
    case "$1" in
        "$PI_FAST_MODE_SOURCE"|"${PI_FAST_MODE_SOURCE}"@*) return 0 ;;
        *) return 1 ;;
    esac
}

_remove_legacy_pi_fast_mode_extension() {
    rm -f "${PI_DIR}/extensions/fast-mode.ts"
}

_pi_fast_mode_install_is_valid() {
    [ -d "${PI_FAST_MODE_CHECKOUT}/.git" ] \
        && [ -f "${PI_FAST_MODE_CHECKOUT}/package.json" ] \
        && [ -f "${PI_FAST_MODE_CHECKOUT}/src/index.ts" ]
}

_pi_fast_mode_package_is_registered() {
    local source="$1"
    [ -f "$PI_SETTINGS_FILE" ] || return 1
    python3 - "$PI_SETTINGS_FILE" "$source" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
if sys.argv[2] not in data.get("packages", []):
    raise SystemExit(1)
PY
}

_remember_pi_fast_mode_package_registration() {
    PI_PREVIOUS_FAST_MODE_SOURCE=""
    [ -f "$PI_SETTINGS_FILE" ] || return 0
    PI_PREVIOUS_FAST_MODE_SOURCE=$(python3 - "$PI_SETTINGS_FILE" "$PI_FAST_MODE_SOURCE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
except (OSError, json.JSONDecodeError):
    raise SystemExit(0)
if not isinstance(data, dict):
    raise SystemExit(0)
base = sys.argv[2]
packages = data.get("packages", [])
if not isinstance(packages, list):
    raise SystemExit(0)
for source in packages:
    if isinstance(source, str) and (source == base or source.startswith(f"{base}@")):
        print(source)
        break
PY
)
}

_restore_pi_fast_mode_package_registration() {
    local source="$1" tmp
    [ -f "$PI_SETTINGS_FILE" ] || return 0
    if ! _pi_fast_mode_install_is_valid; then
        source=""
    fi

    if ! tmp=$(mktemp "${PI_SETTINGS_FILE}.tmp.XXXXXX"); then
        return 1
    fi
    if ! python3 - "$PI_SETTINGS_FILE" "$PI_FAST_MODE_SOURCE" "$source" "$tmp" <<'PY'
import json
import sys

settings_path, base, source, output_path = sys.argv[1:]
with open(settings_path, encoding="utf-8") as handle:
    data = json.load(handle)
packages = data.get("packages", [])
if not isinstance(packages, list):
    packages = []
packages = [
    package
    for package in packages
    if not (
        isinstance(package, str)
        and (package == base or package.startswith(f"{base}@"))
    )
]
if source:
    packages.append(source)
data["packages"] = packages
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
    then
        rm -f "$tmp"
        return 1
    fi
    if ! chmod 600 "$tmp" || ! mv -f "$tmp" "$PI_SETTINGS_FILE"; then
        rm -f "$tmp"
        return 1
    fi
}

_restore_pi_fast_mode_installation() {
    local source="$1" backup="$2" legacy="${PI_DIR}/extensions/fast-mode.ts"
    local restore_failed=0

    if ! rm -rf "$PI_FAST_MODE_CHECKOUT"; then
        restore_failed=1
    elif [ -n "$backup" ] \
        && { [ -e "${backup}/checkout" ] || [ -L "${backup}/checkout" ]; }; then
        if ! mkdir -p "$(dirname "$PI_FAST_MODE_CHECKOUT")" \
            || ! mv "${backup}/checkout" "$PI_FAST_MODE_CHECKOUT"; then
            restore_failed=1
        fi
    fi

    if [ -n "$backup" ] \
        && { [ -e "${backup}/legacy" ] || [ -L "${backup}/legacy" ]; }; then
        if ! rm -f "$legacy" \
            || ! mkdir -p "$(dirname "$legacy")" \
            || ! mv "${backup}/legacy" "$legacy"; then
            restore_failed=1
        fi
    fi
    if ! _restore_pi_fast_mode_package_registration "$source"; then
        restore_failed=1
    fi
    if [ "$restore_failed" -eq 0 ] && [ -n "$backup" ] \
        && ! rm -rf "$backup"; then
        restore_failed=1
    fi
    return "$restore_failed"
}

_remove_legacy_pi_npm_packages() {
    local npm_root="$PI_NPM_DIR"
    local package_json="${npm_root}/package.json"
    local package_lock="${npm_root}/package-lock.json"
    if [ ! -d "${npm_root}/node_modules/pi-list-tools" ] \
        && [ ! -d "${npm_root}/node_modules/pi-print-stream" ] \
        && [ ! -d "${npm_root}/node_modules/pi-otel" ] \
        && { [ ! -f "$package_json" ] \
            || ! grep -Eq '"(pi-list-tools|pi-print-stream|pi-otel)"' "$package_json"; } \
        && { [ ! -f "$package_lock" ] \
            || ! grep -Eq '"node_modules/(pi-list-tools|pi-print-stream|pi-otel)"' "$package_lock"; }; then
        return
    fi

    local npm_bin="${HOME}/.local/bin/npm"
    if [ ! -x "$npm_bin" ]; then
        npm_bin=$(command -v npm || true)
    fi
    if [ -z "$npm_bin" ]; then
        warn "npm unavailable; obsolete Pi npm packages were not removed."
        return
    fi

    log "Removing obsolete Pi npm packages."
    "$npm_bin" uninstall --prefix "$npm_root" --ignore-scripts --no-audit --no-fund \
        pi-list-tools pi-print-stream pi-otel 2>&1 | sed 's/^/  /' \
        || warn "Could not remove obsolete Pi npm packages."
}

_install_required_pi_fast_mode() {
    local pi_bin="$1" source="$2" git_env_name="$3"
    local -n git_env_ref="$git_env_name"
    (
        local backup="" remove_output="" transaction_active=0
        local previous_source="$PI_PREVIOUS_FAST_MODE_SOURCE"

        _rollback_pi_fast_mode_transaction() {
            if [ "$transaction_active" -eq 1 ]; then
                if ! _restore_pi_fast_mode_installation "$previous_source" "$backup"; then
                    warn "Could not fully restore the previous Pi fast-mode provider."
                fi
                transaction_active=0
            elif [ -n "$backup" ] && ! rm -rf "$backup"; then
                warn "Could not remove the temporary Pi fast-mode package backup."
            fi
        }

        trap '_rollback_pi_fast_mode_transaction' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM

        if ! backup=$(mktemp -d "${TMPDIR:-/tmp}/aab-pi-fast-mode.XXXXXX"); then
            warn "Could not create a backup for the existing Pi fast-mode package."
            exit 1
        fi
        if [ -e "$PI_FAST_MODE_CHECKOUT" ] || [ -L "$PI_FAST_MODE_CHECKOUT" ]; then
            if ! cp -a "$PI_FAST_MODE_CHECKOUT" "${backup}/checkout"; then
                warn "Could not back up the existing Pi fast-mode package."
                exit 1
            fi
        fi
        if [ -f "${PI_DIR}/extensions/fast-mode.ts" ] \
            || [ -L "${PI_DIR}/extensions/fast-mode.ts" ]; then
            if ! cp -a "${PI_DIR}/extensions/fast-mode.ts" "${backup}/legacy"; then
                warn "Could not back up the legacy Pi fast-mode extension."
                exit 1
            fi
        fi
        transaction_active=1

        if ! rm -rf "$PI_FAST_MODE_CHECKOUT"; then
            warn "Could not prepare the Pi fast-mode package path for replacement."
            exit 1
        fi

        if ! remove_output=$("${git_env_ref[@]}" "$pi_bin" remove "$source" --no-approve 2>&1); then
            if [[ "$remove_output" != *"No matching package found"* ]]; then
                if [ -n "$remove_output" ]; then
                    printf '%s\n' "$remove_output" | sed 's/^/  /'
                fi
                warn "Pi package removal returned non-zero for ${source}; installation will still be attempted."
            fi
        fi

        if ! "${git_env_ref[@]}" "$pi_bin" install "$source" --no-approve 2>&1 | sed 's/^/  /'; then
            warn "Required Pi fast-mode package installation failed; any previous provider will be restored."
            exit 1
        fi
        if ! _pi_fast_mode_install_is_valid \
            || ! _pi_fast_mode_package_is_registered "$source"; then
            warn "Required Pi fast-mode package installation did not produce a valid registered checkout."
            exit 1
        fi
        if ! _remove_legacy_pi_fast_mode_extension; then
            warn "Could not remove the legacy Pi fast-mode extension after installing its replacement."
            exit 1
        fi

        transaction_active=0
        if ! rm -rf "$backup"; then
            warn "Could not remove the temporary Pi fast-mode package backup."
            exit 1
        fi
        backup=""
        trap - EXIT INT TERM
    )
}

install_pi_plugins() {
    local fast_mode_required=0
    if _pi_fast_mode_required; then
        fast_mode_required=1
    fi

    local pi_bin="${HOME}/.local/bin/pi-aab-real"
    if [ ! -x "$pi_bin" ]; then
        if [ "$fast_mode_required" -eq 1 ]; then
            if ! _restore_pi_fast_mode_package_registration "$PI_PREVIOUS_FAST_MODE_SOURCE"; then
                warn "Could not restore the previous Pi fast-mode package registration."
            fi
            warn "Pi real binary not executable at ${pi_bin}; the required fast-mode package cannot be installed."
            return 1
        fi
        warn "Pi real binary not executable at ${pi_bin}; skipping Pi package installation."
        _remove_legacy_pi_fast_mode_extension
        return
    fi

    _remove_legacy_pi_npm_packages

    local plugins_file="${AAB_PI_PLUGINS_FILE:-}"
    local content="$PI_PLUGINS_DEFAULT_CONTENT"
    if [ -n "$plugins_file" ]; then
        if [ ! -f "$plugins_file" ]; then
            if [ "$fast_mode_required" -eq 1 ]; then
                warn "Pi package list file ${plugins_file} does not exist; only the required fast-mode package will be installed."
                content=""
            else
                warn "Pi package list file ${plugins_file} does not exist; skipping Pi package installation."
                _remove_legacy_pi_fast_mode_extension
                return
            fi
        else
            content=$(cat "$plugins_file")
            log "Reading Pi package list override from ${plugins_file}."
        fi
    else
        log "Reading Pi package list compiled into bootstrap.bash."
    fi

    local -a sources=()
    local line source
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] && continue
        sources+=("$line")
    done <<< "$content"

    if [ "$fast_mode_required" -eq 1 ]; then
        local fast_mode_source_present=0
        for source in "${sources[@]}"; do
            if _is_pi_fast_mode_source "$source"; then
                fast_mode_source_present=1
                break
            fi
        done
        if [ "$fast_mode_source_present" -eq 0 ]; then
            sources+=("$PI_FAST_MODE_SOURCE")
            log "Adding the required Pi fast-mode package omitted by the replacement package list."
        fi
    fi

    if [ ${#sources[@]} -eq 0 ]; then
        log "Pi package list is empty; skipping package installation."
        _remove_legacy_pi_fast_mode_extension
        return
    fi

    local -a git_env=()
    mapfile -d '' git_env < <(_github_git_env)
    local install_succeeded remove_output
    for source in "${sources[@]}"; do
        # Pi has no force-install option. Remove the managed package first so
        # an existing checkout or npm tree cannot make installation a no-op.
        # Missing settings entries are expected because configure_pi_settings
        # clears the package registry before this function runs.
        log "Reinstalling Pi package ${source}."
        if [ "$fast_mode_required" -eq 1 ] && _is_pi_fast_mode_source "$source"; then
            if ! _install_required_pi_fast_mode "$pi_bin" "$source" git_env; then
                return 1
            fi
            continue
        fi

        remove_output=""
        if ! remove_output=$("${git_env[@]}" "$pi_bin" remove "$source" --no-approve 2>&1); then
            if [[ "$remove_output" != *"No matching package found"* ]]; then
                if [ -n "$remove_output" ]; then
                    printf '%s\n' "$remove_output" | sed 's/^/  /'
                fi
                warn "Pi package removal returned non-zero for ${source}; installation will still be attempted."
            fi
        fi

        install_succeeded=0
        if "${git_env[@]}" "$pi_bin" install "$source" --no-approve 2>&1 | sed 's/^/  /'; then
            install_succeeded=1
        fi
        if [ "$install_succeeded" -eq 1 ]; then
            if _is_pi_fast_mode_source "$source"; then
                _remove_legacy_pi_fast_mode_extension
            fi
        else
            warn "Pi package install returned non-zero for ${source}."
        fi
    done

    if [ "$fast_mode_required" -eq 0 ]; then
        _remove_legacy_pi_fast_mode_extension
    fi
}
