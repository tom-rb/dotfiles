# Types and labels registry

The types and labels the skills in this collection need. **This is the only file in the collection that names individual skills** — the vocabulary and the setup steps stay agnostic to which skills are installed, so a new skill is added by adding its rows here and nowhere else.

Read by the setup interview while it fills in the instance. Working agents never read this file; they read the rendered `docs/agents/work-tracker.md`.

## Types

| Type      | Role   | Prefix | Asked for by    |
|-----------|--------|--------|-----------------|
| `map`     | effort | `w`    | wayfinder       |
| `task`    | task   | `t`    | wayfinder       |
| `feature` | effort | `f`    | ways-of-working |
| `gate`    | task   | `g`    | ways-of-working |
| `slice`   | task   | `s`    | ways-of-working |

The prefix is a suggestion for the local markdown backend, which stores the type in it. The GitHub backend has no use for it.

## Labels

| Label                                                                               | On               | Asked for by    |
|-------------------------------------------------------------------------------------|------------------|-----------------|
| `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, `wayfinder:task` | a wayfinder task | wayfinder       |
| `gate:1` … `gate:4`                                                                 | a gate           | ways-of-working |

A backend may need labels of its own, to store a field it has no native home for. Those come from the backend section of the setup skill, not from here.
