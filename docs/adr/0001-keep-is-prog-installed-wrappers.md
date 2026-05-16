# Keep `is_<prog>_installed` wrappers despite their apparent shallowness

The per-program `is_zsh_installed`, `is_git_installed`, `is_tmux_installed` wrappers look like pass-throughs over `command_exists` and read as candidates for deletion (the inner body is a one-liner). Keep them: they exist as named seams so shpy tests can stub *one* program's presence check without disturbing other `command_exists` calls in the same code path (e.g. `get_supported_pm` calling `command_exists apt-get` further down). shpy's `createSpy` replaces a function globally and cannot match on arguments, so mocking `command_exists` directly is too coarse — the wrapper is what makes the test surface targetable.

Does not apply to `is_zimfw_installed` or `is_tpm_installed`: those encode a non-trivial file-path check, not a `command_exists` call, and are genuinely deep.
