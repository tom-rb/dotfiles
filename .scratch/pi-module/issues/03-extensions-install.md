# Extensions install

Status: ready-for-agent

## What to build

Materialize pi extensions from a repo-owned manifest. `pi install <source>` records each extension into pi's settings.json itself, so this path stays out of the [[Settings overlay]] (issue #2) entirely — pi owns the extensions array.

Scope:

- `pi/install_pi_extensions.sh` — a standalone, directly-runnable script (sources `utils/utils.sh` for `$DOTFILES`/`die`) that runs a list of pinned `pi install` lines. First example: `pi install npm:pi-disable-model-skill-invocation@0.1.1`. Sources may be `npm:<pkg>@<version>`, `git:<host/repo>@<ref>`, or a repo-shipped local package referenced as `"$DOTFILES/pi/packages/<name>"`.
- A `pi/packages/` directory housing repo-shipped local extensions (the local-package convention).
- `install_pi_extensions` step in `pi/install_pi.sh`, last in the wizard chain, that always shells out to the standalone script (`_sh -- "$DOTFILES/pi/install_pi_extensions.sh"`). Running the script by hand re-syncs extensions independently of the wizard.

## Acceptance criteria

- [ ] `sh pi/install_pi_extensions.sh` installs each listed extension via `pi install`, including `npm:pi-disable-model-skill-invocation@0.1.1`
- [ ] Local packages are referenced by absolute `$DOTFILES`-anchored path, not cwd-relative
- [ ] The script is runnable standalone and is also invoked unconditionally as the final wizard step
- [ ] Unit tests (shunit2 + shpy) mock `pi` and assert it is called once per source with the expected pinned argument
- [ ] A system test exercises the real `pi install` flow against an installed pi (with an `# @image:` annotation)

## Blocked by

- `.scratch/pi-module/issues/01-module-skeleton-pi-program-install.md`
