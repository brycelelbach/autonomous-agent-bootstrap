# ---------------------------------------------------------------------------
# Configure Pi's generated inference-gateway model catalog.
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
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "${profile[name]}" \
            "${profile[model]}" \
            "${profile[effort]}" \
            "${profile[context]}" \
            "${profile["max_tokens"]}" >> "$records"
    done < <(_model_profile_lines "$profiles")

    python3 - "$records" "$AAB_INFERENCE_GATEWAY_URL" "$tmp" <<'PY'
import csv
import json
import sys

records_path, base_url, output_path = sys.argv[1:]
models = {}
with open(records_path, encoding="utf-8", newline="") as handle:
    for name, model_id, effort, context, max_tokens in csv.reader(handle, delimiter="\t"):
        candidate = {
            "id": model_id,
            "name": name,
            "reasoning": effort != "off",
            "input": ["text"],
            "contextWindow": int(context or "128000"),
            "maxTokens": int(max_tokens or "16384"),
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        }
        existing = models.get(model_id)
        if existing is None:
            models[model_id] = candidate
            continue
        existing["reasoning"] = existing["reasoning"] or candidate["reasoning"]
        existing["contextWindow"] = max(existing["contextWindow"], candidate["contextWindow"])
        existing["maxTokens"] = max(existing["maxTokens"], candidate["maxTokens"])

payload = {
    "providers": {
        "aab-gateway": {
            "name": "AAB Inference Gateway",
            "baseUrl": base_url,
            "api": "openai-responses",
            "apiKey": "$AAB_INFERENCE_GATEWAY_API_KEY",
            "models": list(models.values()),
        }
    }
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
