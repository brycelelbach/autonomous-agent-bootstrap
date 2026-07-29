# Bootstrap source modules

`bootstrap.bash` is compiled from these ordered `*.bash` modules by `tools/compile_bootstrap.py`. The compiler writes an ignored repository-root artifact for local use; the publish workflow writes the distributable copy to a generated branch.

Edit the module that owns the behavior you are changing, then run:

```bash
python3 tools/compile_bootstrap.py
```

High-traffic audit targets:

- `00_versions.bash` owns every non-apt, non-plugin package version, immutable ref, and release checksum.
- `04_install_node.bash` installs the pinned Node.js runtime used by Pi and its packages.
- `06_install_gitleaks.bash` installs the pinned, checksum-verified gitleaks release binary.
- `11_install_agent_plugins.bash` installs the plugin list embedded by the compiler from `agent_plugins.txt`.
- `11_install_pi_plugins.bash` reinstalls the Pi package list embedded from `pi_plugins.txt`; AAB-owned repositories, including the bounded local-only telemetry package, follow their default branches, while third-party sources remain pinned. Fast Pi profiles require `pi-fast-mode` even when a replacement package list omits it, and the legacy inline provider remains available until that package installs successfully. The module also removes obsolete npm-installed Pi packages during upgrades.
- `12_model_profiles.bash` parses and resolves environment-defined model profiles.
- `13_configure_claude.bash` owns Claude settings, onboarding, and shell defaults.
- `13_configure_codex.bash` owns Codex instructions, config, and authentication.
- `13_configure_pi.bash` owns Pi models and unattended settings.
- AAB-owned Pi provider extensions, including `pi-fast-mode`, are installed from their current default branches through `pi_plugins.txt`.
- `23_configure_git_hooks.bash` owns global git-hook configuration and rendering.
- `26_configure_launchers.bash` owns launcher generation.
- `27_configure_shell_startup.bash` sources per-harness shell defaults and owns PATH integration.
