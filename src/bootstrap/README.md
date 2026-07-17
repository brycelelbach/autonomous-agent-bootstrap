# Bootstrap source modules

`bootstrap.bash` is compiled from these ordered `*.bash` modules by `tools/compile_bootstrap.py`.

Edit the module that owns the behavior you are changing, then run:

```bash
python3 tools/compile_bootstrap.py
```

High-traffic audit targets:

- `00_versions.bash` owns non-apt package versions, immutable refs, and release checksums.
- `13_configure_claude.bash` owns Claude settings, onboarding, and shell defaults.
- `13_configure_brev.bash` owns Brev authentication and onboarding.
- `13_configure_codex.bash` owns Codex instructions, config, and authentication.
- `23_install_git_hooks.bash` renders and installs the global git hook.
- `24_write_agent_rules.bash` renders and writes global harness instructions.
- `26_install_launchers.bash` owns launcher installation.
- `27_update_bashrc.bash` sources per-harness shell defaults and owns PATH integration.
