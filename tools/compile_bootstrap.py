#!/usr/bin/env python3
"""Compile the modular bootstrap source tree into one curlable bash script."""

from __future__ import annotations

import argparse
import difflib
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "src" / "bootstrap"
OUTPUT = ROOT / "bootstrap.bash"
AGENT_PLUGINS = ROOT / "agent_plugins.txt"
PI_PLUGINS = ROOT / "pi_plugins.txt"
PI_ASSET_DIR = ROOT / "src" / "pi"
PI_OBSERVABILITY_ENV = PI_ASSET_DIR / "observability.env"
PI_OBSERVABILITY_PRELOAD = PI_ASSET_DIR / "observability-preload.cjs"
PI_LIST_TOOLS_EXTENSION = PI_ASSET_DIR / "list-tools.ts"
PI_FAST_MODE_EXTENSION = PI_ASSET_DIR / "fast-mode.ts"
CODEX_ASSET_DIR = ROOT / "src" / "codex"
CODEX_SESSION_HOOK_TRUST = CODEX_ASSET_DIR / "session-hook-trust.py"

GENERATED_HEADER = """# -----------------------------------------------------------------------------
# GENERATED FILE: do not edit directly.
#
# Source lives in src/bootstrap/*.bash. Rebuild with:
#   python3 tools/compile_bootstrap.py
# -----------------------------------------------------------------------------

"""


def compile_bootstrap(
    source_dir: Path = SOURCE_DIR,
    *,
    bootstrap_repo: str = "brycelelbach/autonomous-agent-bootstrap",
    bootstrap_ref: str = "generated",
) -> str:
    parts: list[str] = []
    for path in sorted(source_dir.glob("*.bash")):
        text = path.read_text()
        if not text.endswith("\n"):
            text += "\n"
        if path.name == "00_prelude.bash" and text.startswith("#!/usr/bin/env bash\n"):
            shebang, rest = text.split("\n", 1)
            parts.append(f"{shebang}\n{GENERATED_HEADER}{rest}")
        else:
            parts.append(f"\n# >>> src/bootstrap/{path.name} >>>\n{text}# <<< src/bootstrap/{path.name} <<<\n")
    compiled = "".join(parts)
    agent_plugins = AGENT_PLUGINS.read_text().rstrip("\n")
    pi_plugins = PI_PLUGINS.read_text().rstrip("\n")
    pi_observability_env = PI_OBSERVABILITY_ENV.read_text().rstrip("\n")
    pi_observability_preload = PI_OBSERVABILITY_PRELOAD.read_text().rstrip("\n")
    pi_list_tools_extension = PI_LIST_TOOLS_EXTENSION.read_text().rstrip("\n")
    pi_fast_mode_extension = PI_FAST_MODE_EXTENSION.read_text().rstrip("\n")
    codex_session_hook_trust = CODEX_SESSION_HOOK_TRUST.read_text().rstrip("\n")
    return (
        compiled.replace("__AAB_BOOTSTRAP_REPO__", bootstrap_repo)
        .replace("__AAB_BOOTSTRAP_REF__", bootstrap_ref)
        .replace("__AAB_AGENT_PLUGINS__", agent_plugins)
        .replace("__AAB_PI_PLUGINS__", pi_plugins)
        .replace("__AAB_PI_OBSERVABILITY_ENV__", pi_observability_env)
        .replace("__AAB_PI_OBSERVABILITY_PRELOAD__", pi_observability_preload)
        .replace("__AAB_PI_LIST_TOOLS_EXTENSION__", pi_list_tools_extension)
        .replace("__AAB_PI_FAST_MODE_EXTENSION__", pi_fast_mode_extension)
        .replace("__AAB_CODEX_SESSION_HOOK_TRUST__", codex_session_hook_trust)
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if bootstrap.bash is stale")
    parser.add_argument("--output", type=Path, default=OUTPUT, help="output path")
    parser.add_argument(
        "--bootstrap-repo",
        default=os.environ.get("GITHUB_REPOSITORY", "brycelelbach/autonomous-agent-bootstrap"),
        help="repo used by generated curl artifacts for side-file fetches",
    )
    parser.add_argument(
        "--bootstrap-ref",
        default=os.environ.get("AAB_BOOTSTRAP_REF", "generated"),
        help="ref used by generated curl artifacts for side-file fetches",
    )
    args = parser.parse_args()

    compiled = compile_bootstrap(
        bootstrap_repo=args.bootstrap_repo,
        bootstrap_ref=args.bootstrap_ref,
    )
    if args.check:
        existing = args.output.read_text() if args.output.exists() else ""
        if existing != compiled:
            diff = difflib.unified_diff(
                existing.splitlines(keepends=True),
                compiled.splitlines(keepends=True),
                fromfile=str(args.output),
                tofile="compiled bootstrap.bash",
            )
            sys.stderr.writelines(diff)
            return 1
        return 0

    args.output.write_text(compiled)
    os.chmod(args.output, 0o755)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
