# Bootstrap source modules

`bootstrap.bash` is compiled from these ordered `*.bash` modules by `tools/compile_bootstrap.py`.

Edit the module that owns the behavior you are changing, then run:

```bash
python3 tools/compile_bootstrap.py
```

High-traffic audit targets:

- `00_versions.bash` owns non-apt package versions, immutable refs, and release checksums.
- `06_install_gitleaks.bash` installs the pinned, checksum-verified gitleaks release binary.
- `11_install_agent_plugins.bash` installs the plugin list embedded by the compiler from `agent_plugins.txt`.
- `13_configure_claude.bash` owns Claude settings, onboarding, and shell defaults.
- `13_configure_brev.bash` owns Brev authentication and onboarding.
- `13_configure_codex.bash` owns Codex instructions, config, and authentication.
- `23_configure_git_hooks.bash` renders and configures the global git hook.
- `24_write_agent_rules.bash` renders and writes global harness instructions.
- `26_write_launchers.bash` owns launcher generation.
- `27_update_bashrc.bash` sources per-harness shell defaults and owns PATH integration.
