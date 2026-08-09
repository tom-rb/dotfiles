---
name: prune-code-comments
description: Modify comments in changed code files by deleting only redundant, historical, justificatory, caller-reference, and empty-scaffolding comments that clearly match the specified removal categories. Not intended for modifying code or documentation files.
disable-model-invocation: true
---

Review code comments in changed files. Prioritize uncommitted files. If the working tree is clean, review changes in the last commit. If the user specifies a branch, review all changes on that branch relative to the default merge target.

Delete only comments matching the categories below. Do not modify code. If only part of a comment is redundant, remove that part and rephrase the remainder for coherence.

REMOVE:

1. Code restatements — Comments that merely describe code visible on the following line. Remove test comments that only restate the test name or implementation.

2. Regression narrative — Comments describing past bugs rather than current behavior. Markers: "used to", "previously", "before this fix", "this is why X broke". Remove these especially when the test name already states the intent.

3. Reasoning traces — Comments documenting the author's discarded approaches or decision-making history. Keep comments that explain why the current implementation is necessary.

4. Caller cross-references — Comments that only identify callers or where a function fits in a flow. Markers: "Used by <fn>...", "Called from...", "Wired in by...". Keep comments that describe the caller-facing contract.

5. Empty scaffolding — Remove section dividers with no code beneath them and comment blocks orphaned by earlier deletions.

KEEP unchanged:
- Comments documenting invariants, ordering constraints, workarounds, or hidden preconditions whose violation would cause a bug, including deadlock risks, buffering behavior, and portability constraints.
- Prose in documentation files. Review code comments only; do not modify documents, specifications, or reports.

RULES:
- Delete a comment only when it clearly matches a removal category.
- Leave uncertain comments unchanged and report them as uncertain.
- After editing all comments in scope, run the linter.
- If the linter reports an error caused by your changes, undo those changes.
