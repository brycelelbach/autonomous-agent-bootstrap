# ---------------------------------------------------------------------------
# Configure Pi's generated inference-gateway model catalog and unattended
# defaults.
# ---------------------------------------------------------------------------

configure_pi_models() {
    local profiles line
    profiles=$(_profile_list_for pi third-party)
    if [ -z "$(_model_profile_lines "$profiles")" ]; then
        if [ -f "$PI_MODELS_MARKER" ]; then
            rm -f "$PI_MODELS_FILE" "$PI_MODELS_MARKER"
        fi
        return
    fi

    require_inference_gateway "Pi profiles"
    mkdir -p "$PI_DIR" "$AAB_DIR"
    if [ -f "$PI_MODELS_FILE" ] && [ ! -f "$PI_MODELS_MARKER" ]; then
        local backup
        backup="${PI_MODELS_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$PI_MODELS_FILE" "$backup"
        log "Backed up existing Pi models.json -> ${backup}."
    fi

    local records tmp
    records=$(mktemp)
    tmp=$(mktemp "${PI_MODELS_FILE}.tmp.XXXXXX")
    local -A profile=()
    while IFS= read -r line; do
        _parse_model_profile_line pi third-party "$line" profile
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${profile[name]}" \
            "${profile[model]}" \
            "${profile[effort]}" \
            "${profile[thinking]}" \
            "${profile[context]}" \
            "${profile["max_tokens"]}" \
            "${profile[fast]:-false}" >> "$records"
    done < <(_model_profile_lines "$profiles")

    python3 - "$records" "$AAB_INFERENCE_GATEWAY_URL" "$tmp" <<'PY'
import csv
from copy import deepcopy
import json
import sys

records_path, base_url, output_path = sys.argv[1:]
models = {}
fast_models = {}


def merge_model(catalog, candidate):
    model_id = candidate["id"]
    existing = catalog.get(model_id)
    if existing is None:
        catalog[model_id] = candidate
        return
    existing_map = existing.setdefault("thinkingLevelMap", {})
    for level, provider_effort in candidate.get("thinkingLevelMap", {}).items():
        previous = existing_map.get(level)
        if previous is not None and previous != provider_effort:
            raise SystemExit(
                f"Conflicting Pi effort mappings for model {model_id!r}: "
                f"{level} maps to both {previous!r} and {provider_effort!r}"
            )
        existing_map[level] = provider_effort
    if not existing_map:
        existing.pop("thinkingLevelMap", None)
    existing["reasoning"] = existing["reasoning"] or candidate["reasoning"]
    existing["contextWindow"] = max(existing["contextWindow"], candidate["contextWindow"])
    existing["maxTokens"] = max(existing["maxTokens"], candidate["maxTokens"])


with open(records_path, encoding="utf-8", newline="") as handle:
    for name, model_id, effort, thinking, context, max_tokens, fast in csv.reader(handle, delimiter="\t"):
        candidate = {
            "id": model_id,
            "name": name,
            "reasoning": thinking != "off",
            "input": ["text"],
            "contextWindow": int(context or "128000"),
            "maxTokens": int(max_tokens or "16384"),
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        }
        if effort != thinking or thinking in {"xhigh", "max"}:
            candidate["thinkingLevelMap"] = {thinking: effort}
        merge_model(models, deepcopy(candidate))
        if fast == "true":
            merge_model(fast_models, deepcopy(candidate))

payload = {
    "providers": {
        "aab-gateway": {
            "name": "AAB Inference Gateway",
            "baseUrl": base_url,
            "api": "openai-completions",
            "apiKey": "$AAB_INFERENCE_GATEWAY_API_KEY",
            "models": list(models.values()),
        }
    }
}
if fast_models:
    payload["providers"]["aab-gateway-fast"] = {
        "name": "AAB Inference Gateway Fast",
        "baseUrl": base_url,
        "api": "aab-openai-responses-fast",
        "apiKey": "$AAB_INFERENCE_GATEWAY_API_KEY",
        "models": list(fast_models.values()),
    }
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
PY

    rm -f "$records"
    chmod 600 "$tmp"
    mv -f "$tmp" "$PI_MODELS_FILE"
    : > "$PI_MODELS_MARKER"
    chmod 600 "$PI_MODELS_MARKER"
    log "Wrote ${PI_MODELS_FILE} from AAB_PI_PROFILES."
}

configure_pi_settings() {
    local profiles records line selected_provider="" selected_model=""
    local -A profile=() selected=()
    _remember_pi_fast_mode_package_registration
    profiles=$(_profile_list_for pi third-party)
    records=$(mktemp)
    while IFS= read -r line; do
        _parse_model_profile_line pi third-party "$line" profile
        printf '%s\t%s\n' "${profile[model]}" "${profile[fast]:-false}" >> "$records"
    done < <(_model_profile_lines "$profiles")

    if [ -s "$records" ]; then
        resolve_model_profile pi selected
        if [ "${selected[fast]}" = true ]; then
            selected_provider="aab-gateway-fast"
        else
            selected_provider="aab-gateway"
        fi
        selected_model="${selected[model]}"
    fi

    mkdir -p "$PI_DIR"
    if [ -f "$PI_SETTINGS_FILE" ]; then
        local backup
        backup="${PI_SETTINGS_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$PI_SETTINGS_FILE" "$backup"
        log "Backed up existing Pi settings.json -> ${backup}."
    fi

    local tmp
    tmp=$(mktemp "${PI_SETTINGS_FILE}.tmp.XXXXXX")
    python3 - "$PI_SETTINGS_FILE" "$records" \
        "$selected_provider" "$selected_model" "$tmp" <<'PY'
import json
from pathlib import Path
import sys

settings_path, models_path, provider, model, output_path = sys.argv[1:]
data = {}
try:
    with open(settings_path, encoding="utf-8") as handle:
        loaded = json.load(handle)
        if isinstance(loaded, dict):
            data = loaded
except (FileNotFoundError, json.JSONDecodeError):
    pass

data.update(
    {
        "defaultThinkingLevel": "high",
        "defaultProjectTrust": "always",
        "quietStartup": True,
        "enableInstallTelemetry": True,
        "enableAnalytics": True,
        "warnings": {"anthropicExtraUsage": False},
        "retry": {
            "enabled": True,
            "maxRetries": 15,
            "provider": {"timeoutMs": 240000, "maxRetries": 0},
        },
        "extensions": [],
        "packages": [],
    }
)

if provider:
    models = list(
        dict.fromkeys(
            line.split("\t", 1)[0]
            for line in Path(models_path).read_text().splitlines()
        )
    )
    data["defaultProvider"] = provider
    data["defaultModel"] = model
    data["enabledModels"] = models

for machine_key in ("trackingId", "lastChangelogVersion"):
    data.pop(machine_key, None)

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
    rm -f "$records"
    chmod 600 "$tmp"
    mv -f "$tmp" "$PI_SETTINGS_FILE"
    rm -f "${AAB_SHELL_CONFIG_DIR}/pi-observability.env"
    log "Wrote ${PI_SETTINGS_FILE} with unattended Pi defaults."
}
