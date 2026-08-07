---
name: clean-comments
description: Remove redundant, left-overs or useless comments.
disable-model-invocation: true
---

Review comments in the changed files. Delete only comments matching the four categories below. Do not reword comments, and do not touch code.

REMOVE:

1. Regression narrative — comments recounting a past bug rather than describing current behavior. Markers: "used to", "previously", "before this fix", "this is why X broke". Most common above test functions whose name already states the intent.

2. Caller cross-references — comments naming who calls this function or where it fits in a flow, adding nothing about what the code does. Markers: "Used by <fn>...", "Called from...", "Wired in by...", "for <other module>'s benefit".

3. Restatements of the code — comments whose content is readable from the line directly below.

4. Empty scaffolding — section dividers with no code under them, and comment blocks left orphaned by earlier deletions.

KEEP (do not touch, even if verbose):
- The one-line description above each function, and its argument/flag/return docs.
- Any comment stating an invariant, ordering constraint, workaround, or hidden precondition — anything whose violation would be a bug rather than a style difference (deadlock risks, buffering behavior, portability caveats).
- Comments explaining why an obvious-looking alternative was rejected.

Rules:
- Delete whole comments, never partial sentences. If removing part of a comment would leave a dangling or ungrammatical remainder, leave the comment alone and report it instead.
- If a deletion is not clearly in one of the four categories, leave it and report it as uncertain.
- After editing, run the linter.
