---
name: wayfinder
description: Plan a huge chunk of work — more than one agent session can hold — as a shared map of decision tasks, and resolve them one at a time until the way to the destination is clear.
disable-model-invocation: true
---

A loose idea has arrived — too big for one agent session, and wrapped in fog: the way from here to the **destination** isn't visible yet. Wayfinding is about finding that way, not charging at the destination. This skill charts the way as a **shared map** on the project's work tracker, then works its **decision tasks** — questions whose resolution is a decision, not slices of a build to execute — one at a time until the route is clear.

The destination varies per effort, and naming it is the first act of charting — it shapes every task. It might be a spec to hand off and iterate on, a decision to lock before planning starts, or a change made in place like a data-structure migration. The map is domain-agnostic — engineering work, course content, whatever fits the shape.

## Plan, don't do

Wayfinder is **planning** by default: each task resolves a decision, and the map is done when the way is clear — nothing left to decide before someone goes and does the thing. The pull to just do the work is usually the signal you've reached the edge of the map and it's time to hand off. An effort can override this in its **Notes** — carrying execution into the map itself — but absent that, produce decisions, not deliverables.

## Refer by name

Every map and task is a work item, so it has a **name** — its title. In everything the human reads — narration, the map's Decisions-so-far — refer to it by that name, never by a bare id, number, or slug. A wall of `t42, t43, t44` is illegible; names read at a glance. The id doesn't vanish — a name wraps its link — but it rides *inside* the name, never stand in for it.

## The Map

The map is a single docs/wayfinder/wNN-<wayfinder-slug>/wNN-map.md file — the canonical artifact. The map tasks are tracked in tNN-<task-slug>.md files under the same directory. Some can depend on others, and this is represented EXCLUSIVELY in the map itself.

The map is an **index**, not a store. It lists the decisions made and points at the tasks that hold their detail; a decision lives in exactly one place — its task — so the map never restates it, only gists it and links.

### The map body

The whole map at low resolution, loaded once per session. Open and closed tasks references are also listed in the map – their details live as task files, and their status and dependencies are stored in the wNN-map.md as shown below.

```markdown
## Destination

<what reaching the end of this map looks like — the spec, decision, or change this effort is finding its way to. One or two lines; every session orients to it before choosing a task.>

## Notes

<domain; skills every session should consult; standing preferences for this effort>

## Decisions so far

<!-- the decision index — one line per task: gist enough to judge relevance, then follow the link for the detail the task holds -->

- [x] [t01 <closed task title>](link) research
    - One-line gist of the answer
- [x] [t02 <closed task title>](link) grilling, blocked by: t01
    - One-line gist of the answer
- [!] [t03 <in progress task title>](link) prototype, blocked by: t02
- [ ] [t04 <open task title>](link) grilling, blocked by: t01, t03

## Not yet specified

<!-- see "Fog of war": in-scope fog you can't task yet; graduates as the frontier advances -->

## Out of scope

<!-- see "Out of scope": work ruled beyond the destination; closed, never graduates -->
```

### Tasks

Created as task files towards the destination. They stay in the same wNN-<wayfinder-slug>/ directory as the map. Its body is the question, sized to one 100K token agent session:

```markdown
## Question

<the decision or investigation this task resolves>
```

Each task carries a `task-type:` entry in their frontmatter — one of `research`, `prototype`, `grilling`, `task` (see [Task Types](#task-types)) — and mirrors the type in the map's task list.

The orchestrator agent **claims** a task by marking it in progress with [!], doing it **first**, before dispatching or doing any work on the task, so concurrent sessions skip it.

Blocking is written as dependencies in wNN-map.md task list — essential because it tracks the frontier, so anyone sees what's takeable at a glance on the map. A task is **unblocked** when every task blocking it is closed; the **frontier** is the open, unblocked, unclaimed children — the edge of the known.

The answer isn't part of the body — it's recorded on resolution (see [Work through the map](#work-through-the-map)). Assets created while resolving a task are linked from the work item, not pasted in.

## Task Types

Every task is either **HITL** — human in the loop, worked *with* a human who speaks for themselves — or **AFK**, driven by the agent alone. A HITL task only resolves through that live exchange; the agent never stands in for the human's side of it (a grilling agent that answers its own questions has broken this).

- **Research** (AFK): Reading documentation, third-party APIs, or local resources like knowledge bases to surface a fact a decision waits on. Resolved by a `/research` **subagent**. Use when knowledge outside the current working directory is required.
- **Prototype** (HITL): Raise the fidelity of the discussion by making a cheap, rough, concrete artifact to react to — an outline, a rough take, a stub, or UI/logic code via the `/prototype` skill. Links the prototype as an asset. Use when "how should it look" or "how should it behave" is the key question.
- **Grilling** (HITL): Conversation via the `/grilling` and `/domain-modeling` skills. The default case.
- **Task** (HITL or AFK): Manual work that must happen before a *decision* can be made — nothing to decide, prototype, or research, but the discussion is blocked until it's done. Signing up for a service so its API can be judged, provisioning access, moving data so its shape can be seen. This is the one type that *does* rather than decides — and it earns its place by unblocking a decision, not by delivering the destination. The agent drives it alone where it can (AFK); otherwise it hands the human a precise checklist (HITL). Resolved when the work is done; the answer records what was done and any resulting facts (credentials location, new URLs, row counts) later tasks depend on.

## Fog of war

The map is _deliberately_ incomplete: don't chart what you can't yet see. Beyond the live tasks lies the **fog of war** — the dim view of decisions and investigations you can tell are coming but can't yet pin down, because they hang on questions still open. Resolving a task clears the fog ahead of it, graduating whatever's now specifiable into fresh tasks — one at a time, until the way to the destination is clear and no tasks remain.

The map's **Not yet specified** section is where that dim view is written down: the suspected question, the area to revisit later. It's the undiscovered frontier _toward_ the destination — everything here is in scope, just not sharp enough to task. Write as loosely or as fully as the view allows; it doubles as a signpost for collaborators reading where the effort is headed.

**Fog or task?** The test is whether you can state the question precisely now — _not_ whether you can answer it now.

- **Task when** the question is already sharp — even if it's blocked and you can't act on it yet.
- **Not yet specified when** you can't yet phrase it that sharply. Don't pre-slice the fog into task-sized pieces: it's coarser than a task, and one patch may graduate into several tasks, or none, once the frontier reaches it.

**Not yet specified** excludes what's already decided (Decisions so far), what's already a live task, and what's out of scope (the next section).

## Out of scope

Fog only ever gathers _toward_ the destination. The destination fixes the scope, so work beyond it is **out of scope** — it isn't fog, and it doesn't belong in **Not yet specified**. It gets its own **Out of scope** section on the map: work you've consciously ruled out of _this_ effort. Scope, not sharpness, lands it here.

Out-of-scope work never graduates — the frontier stops at the destination — so it returns only if the destination is redrawn, and then as a fresh effort, not a resumption.

Ruling something out of scope is a scoping act, not a step on the route. When a task that already exists turns out to sit past the destination — mis-scoped in while charting, or exposed by a resolution — **close it** (a closed task is unambiguously off the frontier) and leave one line in the **Out of scope** section: the gist plus why it's out of scope, linking the closed task. It stays out of **Decisions so far**, which records the route actually walked — a scope boundary isn't a step on it.

## Invocation

Two modes. Either way, **never resolve more than one task per session** — with the exception of research tasks.

### Chart the map

User invokes with a loose idea.

1. **Name the destination.** Run a `/grilling` session with `/domain-modeling` in context to pin down what this map is finding its way to — the spec, decision, or change. The destination fixes the scope, so it's settled first.
2. **Map the frontier.** Grill again, **breadth-first** this time: fan out across the whole space rather than deep on any one thread, surfacing the open decisions and the first steps takeable now. **If this surfaces no fog** — the way to the destination is already clear, the whole journey small enough for one session — you don't need a map. Stop and ask the user how they'd like to proceed.
3. **Create the map**: Destination and Notes filled in, Decisions-so-far empty, the fog sketched into **Not yet specified**.
4. **Create the tasks you can specify now** — then wire blocking edges in a **second pass** (items need ids before they can reference each other). Wiring sorts them into the frontier and the blocked; everything you can't yet specify stays in the fog — the **Not yet specified** section.
5. **Fire the research subagents.** For each `research` task you just created, confirm with the user and spin up a `/research` subagent to resolve it in parallel — since research can be of high token consumption the user might postpone the parallelism, so confirm each research dispatch before doing it. The research subagents capture their findings in a tNN-findings/ directory under the wayfinder one.
6. Stop — charting is one session's work; it hand-resolves nothing.

### Work through the map

User invokes with a map (URL, path or tag/number). A task is **optional** — without one, you pick the next decision, not the user.

1. Load the **map** — the low-res view, not every task body.
2. Choose the task. If the user named one, use it. Otherwise take the first frontier task in order. **Claim it**: mark it in progress before any work.
3. Resolve it — **zoom as needed**: fetch the full body of any related or closed task on demand; invoke the skills the `## Notes` block names. If in doubt, use `/grilling` and `/domain-modeling`.
4. Record the resolution: write the answer as a resolution comment, mark the task done, and **append a context pointer** to the map's Decisions-so-far.
5. Add newly-surfaced tasks (create-then-wire); graduate any fog the answer has made specifiable, clearing each graduated patch from **Not yet specified** so it lives only as its new task. If the answer reveals a task — this one or another — sits beyond the destination, **rule it out of scope** rather than resolving it on the route. If the decision invalidates other parts of the map, update or delete those tasks.

The user may run unblocked tasks in parallel, so expect other sessions to be editing the tracker concurrently.
