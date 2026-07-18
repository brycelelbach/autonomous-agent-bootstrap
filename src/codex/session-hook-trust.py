#!/usr/bin/env python3
"""Emit a session override that trusts every enabled Codex hook."""

from __future__ import annotations

import json
import os
import select
import subprocess
import sys
import time
from typing import Any

RESPONSE_TIMEOUT_SECONDS = 10


class AppServerError(RuntimeError):
    """Report a failed Codex app-server exchange."""


def send_message(process: subprocess.Popen[str], message: dict[str, Any]) -> None:
    if process.stdin is None:
        raise AppServerError("Codex app-server stdin is unavailable.")
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    process.stdin.flush()


def read_response(process: subprocess.Popen[str], request_id: int) -> dict[str, Any]:
    if process.stdout is None:
        raise AppServerError("Codex app-server stdout is unavailable.")

    deadline = time.monotonic() + RESPONSE_TIMEOUT_SECONDS
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise AppServerError(f"Codex app-server request {request_id} timed out.")
        ready, _, _ = select.select([process.stdout], [], [], remaining)
        if not ready:
            raise AppServerError(f"Codex app-server request {request_id} timed out.")
        line = process.stdout.readline()
        if not line:
            raise AppServerError("Codex app-server closed before responding.")
        message = json.loads(line)
        if message.get("id") != request_id:
            continue
        if "error" in message:
            raise AppServerError(str(message["error"]))
        result = message.get("result")
        if not isinstance(result, dict):
            raise AppServerError("Codex app-server returned an invalid response.")
        return result


def toml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def hook_state_override(response: dict[str, Any]) -> str:
    states: dict[str, str] = {}
    entries = response.get("data")
    if not isinstance(entries, list):
        raise AppServerError("Codex hooks/list returned invalid data.")

    for entry in entries:
        if not isinstance(entry, dict):
            continue
        hooks = entry.get("hooks")
        if not isinstance(hooks, list):
            continue
        for hook in hooks:
            if not isinstance(hook, dict):
                continue
            if hook.get("enabled") is not True or hook.get("isManaged") is True:
                continue
            key = hook.get("key")
            current_hash = hook.get("currentHash")
            if not isinstance(key, str) or not isinstance(current_hash, str):
                raise AppServerError("Codex hooks/list returned invalid hook metadata.")
            states[key] = current_hash

    values = [
        f"{toml_string(key)}={{trusted_hash={toml_string(states[key])}}}"
        for key in sorted(states)
    ]
    return "{" + ",".join(values) + "}"


def main() -> int:
    if len(sys.argv) < 3:
        raise SystemExit("Usage: session-hook-trust.py CODEX_BIN CWD [CODEX_CONFIG_ARGS...]")

    codex_bin, cwd, *config_args = sys.argv[1:]
    process = subprocess.Popen(
        [codex_bin, *config_args, "app-server", "--stdio"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        env=os.environ,
    )
    try:
        send_message(
            process,
            {
                "method": "initialize",
                "id": 1,
                "params": {
                    "clientInfo": {
                        "name": "autonomous-agent-bootstrap",
                        "title": None,
                        "version": "1",
                    },
                    "capabilities": None,
                },
            },
        )
        read_response(process, 1)
        send_message(process, {"method": "initialized"})
        send_message(
            process,
            {"method": "hooks/list", "id": 2, "params": {"cwds": [cwd]}},
        )
        print(hook_state_override(read_response(process, 2)))
        return 0
    finally:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
