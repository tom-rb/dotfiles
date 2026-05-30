# Settings overlay merge

Status: ready-for-agent

## What to build

The [[Settings overlay]] step: deep-merge a repo-owned partial `settings.json` into pi's live config, which pi rewrites at runtime. See `docs/adr/0004-pi-settings-overlay.md` and the CONTEXT.md "Settings overlay" term.

Scope:

- `pi/merge_settings.mjs` — a committed Node deep-merge engine (not an inline `node -e`, so it's unit-testable). Semantics: on every object, repo-shipped scalar keys win; scalar arrays merge by union (repo elements ensured present, live-only elements kept); nothing is ever deleted.
- `pi/settings.json` — the partial overlay, shipping ONLY these four scalar keys for now: `hideThinkingBlock`, `enableSkillCommands`, `showHardwareCursor`, `doubleEscapeAction`. It deliberately omits volatile keys (`lastChangelogVersion`) and the extensions array (pi-owned, materialized by issue #3).
- `install_pi_settings` step in `pi/install_pi.sh`, inserted into the wizard chain after `install_pi_program`: target is `$(get_pi_config_dir)/settings.json`; first install (target absent) writes the overlay verbatim; otherwise merge via the engine. Write atomically (temp file then `mv`) so a concurrent pi read never sees half-written JSON. No backup — the never-delete property keeps the blast radius small.

## Acceptance criteria

- [ ] First install (no existing settings.json) creates the file with exactly the four overlay keys
- [ ] Re-merge over a live file overwrites the overlay's keys, leaves unrelated keys (e.g. `lastChangelogVersion`, user additions) untouched, and deletes nothing
- [ ] A scalar array present in both repo and live merges by union with no duplicates (engine capability, even if no overlay key exercises it yet)
- [ ] The merged file is written atomically (temp-then-`mv`); a failed merge leaves the original intact
- [ ] `merge_settings.mjs` has standalone Node unit tests covering repo-wins, union, and never-delete
- [ ] Shell-level tests cover the first-install vs merge branches of `install_pi_settings`

## Blocked by

- `.scratch/pi-module/issues/01-module-skeleton-pi-program-install.md`
