# Bootstrap source modules

`bootstrap.bash` is compiled from these ordered `*.bash` modules by `tools/compile_bootstrap.py`.

Edit the module that owns the behavior you are changing, then run:

```bash
python3 tools/compile_bootstrap.py
```

High-traffic audit targets:

- `00_versions.bash` owns every non-apt, non-plugin package version, immutable ref, and release checksum.
- `04_install_node.bash` installs the pinned Node.js runtime used by Pi and its packages.
- `06_install_gitleaks.bash` installs the pinned, checksum-verified gitleaks release binary.
- `11_install_agent_plugins.bash` installs the plugin list embedded by the compiler from `agent_plugins.txt`.
- `11_install_pi_plugins.bash` installs the exact Pi package list embedded from `pi_plugins.txt`.
- `12_model_profiles.bash` parses and resolves environment-defined model profiles.
- `13_configure_claude.bash` owns Claude settings, onboarding, and shell defaults.
- `13_configure_codex.bash` owns Codex instructions, config, and authentication.
- `13_configure_pi.bash` owns Pi models, unattended settings, and the inline fast-mode extension.
- `23_configure_git_hooks.bash` owns global git-hook configuration and rendering.
- `26_configure_launchers.bash` owns launcher generation.
- `27_configure_shell_startup.bash` sources per-harness shell defaults and owns PATH integration.
