---
name: wayfinder
description: Plan a huge chunk of work — more than one agent session can hold — as a shared map of decision tasks, and resolve them one at a time until the way to the destination is clear.
disable-model-invocation: true
---

A loose idea has arrived — too big for one agent session, and wrapped in fog: the way from here to the **destination** isn't visible yet. Wayfinding is about finding that way, not charging at the destination. This skill charts the way as a **shared map** on the project's work tracker, then works its **decision tasks** — questions whose resolution is a decision, not slices of a build to execute — one at a time until the route is clear.

The destination varies per effort, and naming it is the first act of charting — it shapes every task. It might be a spec to hand off and iterate on, a decision to lock before planning starts, or a change made in place like a data-structure migration. The map is domain-agnostic — engineering work, course content, whatever fits the shape.

## The tracker

Everything this skill creates is a work item. A **map** is an `effort`; a **task** is a `task` under it. Both take a type name of their own, so that listing maps never returns another skill's efforts — the tracker file's type table names the skill that asks for each type, and the rows naming **wayfinder** are the ones to filter on. How this project's tracker names those, what its states are, how to claim an item, and how to invoke each verb are described in `docs/agents/work-tracker.md` — read it before the first operation. If that file is missing, this project has no tracker yet: stop and ask the user to run `/setup-my-skills`.

## Plan, don't do

Wayfinder is **planning** by default: each task resolves a decision, and the map is done when the way is clear — nothing left to decide before someone goes and does the thing. The pull to just do the work is usually the signal you've reached the edge of the map and it's time to hand off. An effort can override this in its **Annotations** — carrying execution into the map itself — but absent that, produce decisions, not built things.

## Refer by name

Every map and task is a work item, so it has a **name** — its title. In everything the human reads — narration, the map's Decisions-so-far — refer to it by that name, never by a bare id, number, or slug. A wall of `t042, t043, t044` is illegible; names read at a glance. The ref doesn't vanish — it rides alongside the name, so the tracker can link it — but it never stands in for it.

## The Map

The map is the effort's **body** — the canonical artifact, loaded once per session. Its tasks hold the detail.

The map is an **index**, not a store. It gists the decisions made and points at the tasks that hold them; a decision lives in exactly one place — its task — so the map never restates it.

The map holds **no state**. Which tasks are open, claimed, resolved, or blocked lives on the tasks themselves and is read with `list` — never mirrored onto the map, so parallel sessions never fight over it.

### The map body

```markdown
## Destination

<what reaching the end of this map looks like — the spec, decision, or change this effort is finding its way to. One or two lines; every session orients to it before choosing a task.>

## Annotations

<domain; skills every session should consult; standing preferences for this effort>

## Decisions so far

<!-- the decision index, append-only: one line per resolved task, written as it resolves and never edited afterwards. Open tasks are absent — they come from `list`. -->

 - [<ref>] <task name> — one-line gist of the answer.
 - [<ref>] <task name> — one-line gist of the answer.

## Not yet specified

<!-- see "Fog of war": in-scope fog you can't task yet; graduates as the frontier advances -->

## Out of scope

<!-- see "Out of scope": work ruled beyond the destination, that never became a task -->
```

Write each ref verbatim, exactly as the tracker gave it, so the tracker links it itself.

The map body is written whole, so `get` it immediately before appending a line and write it straight back. Two sessions that append at once still lose a line — but only the gist, never the decision, which lives on its own task and is found by `list`. The index is a convenience; treat it as one.

The index carries resolved tasks only, so **reopening a task removes its line**. That is the one edit the index allows; a line is never reworded once written, because rewording is where two sessions actually corrupt each other.

### Tasks

A task is a `task` under the map, sized to one 100K token agent session. Its body is the question:

```markdown
## Question

<the decision or investigation this task resolves>
```

Each task carries a `wayfinder:` label naming its method — one of `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, `wayfinder:task` (see [Task methods](#task-methods)).

Blocking is recorded on the task itself, in `blocked_by`: a task is **unblocked** when every task blocking it is resolved. The **frontier** is the map's tasks that are unresolved, unclaimed, and unblocked — the edge of the known. Compute it with `list`; nothing caches it.

**Claim** a task **first**, before dispatching or doing any work on it, so concurrent sessions skip it. The tracker file says how. A claim is advisory — it will not stop a second session that claims the same task — so where the user is running sessions in parallel, say plainly that two sessions can land on one task.

The answer isn't part of the body — it's recorded on resolution (see [Work through the map](#work-through-the-map)). Artifacts made while resolving a task are `attach`ed to it and referenced from it, never pasted into it.

## Task methods

Every task takes one of four methods, and each is either **HITL** — human in the loop, worked *with* a human who speaks for themselves — or **AFK**, driven by the agent alone. A HITL task only resolves through that live exchange; the agent never stands in for the human's side of it (a grilling agent that answers its own questions has broken this).

 - **Research** (AFK): Reading documentation, third-party APIs, or local resources like knowledge bases to surface a fact a decision waits on. Resolved by a `/research` **subagent**. Use when knowledge outside the current working directory is required.
 - **Prototype** (HITL): Raise the fidelity of the discussion by making a cheap, rough, concrete artifact to react to — an outline, a rough take, a stub, or UI/logic code via the `/prototype` skill. Attaches the prototype to the task. Use when "how should it look" or "how should it behave" is the key question.
 - **Grilling** (HITL): Conversation via the `/grilling` and `/domain-modeling` skills. The default case.
 - **Task** (HITL or AFK): Manual work that must happen before a *decision* can be made — nothing to decide, prototype, or research, but the discussion is blocked until it's done. Signing up for a service so its API can be judged, provisioning access, moving data so its shape can be seen. This is the one method that *does* rather than decides — and it earns its place by unblocking a decision, not by delivering the destination. The agent drives it alone where it can (AFK); otherwise it hands the human a precise checklist (HITL). Resolved when the work is done; the answer records what was done and any resulting facts (credentials location, new URLs, row counts) later tasks depend on.

## Fog of war

The map is _deliberately_ incomplete: don't chart what you can't yet see. Beyond the live tasks lies the **fog of war** — the dim view of decisions and investigations you can tell are coming but can't yet pin down, because they hang on questions still open. Resolving a task clears the fog ahead of it, graduating whatever's now specifiable into fresh tasks — one at a time, until the way to the destination is clear and no tasks remain.

The map's **Not yet specified** section is where that dim view is written down: the suspected question, the area to revisit later. It's the undiscovered frontier _toward_ the destination — everything here is in scope, just not sharp enough to task. Write as loosely or as fully as the view allows; it doubles as a signpost for collaborators reading where the effort is headed.

**Fog or task?** The test is whether you can state the question precisely now — _not_ whether you can answer it now.

 - **Task when** the question is already sharp — even if it's blocked and you can't act on it yet.
 - **Not yet specified when** you can't yet phrase it that sharply. Don't pre-slice the fog into task-sized pieces: it's coarser than a task, and one patch may graduate into several tasks, or none, once the frontier reaches it.

**Not yet specified** excludes what's already decided (Decisions so far), what's already a live task, and what's out of scope (the next section).

## Out of scope

Fog only ever gathers _toward_ the destination. The destination fixes the scope, so work beyond it is **out of scope** — it isn't fog, and it doesn't belong in **Not yet specified**. It gets its own **Out of scope** section on the map: work you've consciously ruled out of _this_ effort, and that never became a task. Scope, not sharpness, lands it here.

Out-of-scope work never graduates — the frontier stops at the destination — so it returns only if the destination is redrawn, and then as a fresh effort, not a resumption.

Ruling something out of scope is a scoping act, not a step on the route. When a task that already exists turns out to sit past the destination — mis-scoped in while charting, or exposed by a resolution — **resolve it as dropped**, with a note saying it sits beyond the destination. Nothing about it goes on the map: not in **Out of scope**, which is for what never became a task, and not in **Decisions so far**, which records the route actually walked — a scope boundary isn't a step on it.

## Invocation

Two modes. Either way, **never resolve more than one task per session** — with the exception of research tasks.

### Chart the map

User invokes with a loose idea.

1. **Name the destination.** Run a `/grilling` session with `/domain-modeling` in context to pin down what this map is finding its way to — the spec, decision, or change. The destination fixes the scope, so it's settled first.
2. **Map the frontier.** Grill again, **breadth-first** this time: fan out across the whole space rather than deep on any one thread, surfacing the open decisions and the first steps takeable now. **If this surfaces no fog** — the way to the destination is already clear, the whole journey small enough for one session — you don't need a map. Stop and ask the user how they'd like to proceed.
3. **`create` the map**: Destination and Annotations filled in, Decisions-so-far empty, the fog sketched into **Not yet specified**.
4. **`create` the tasks you can specify now** — then `update` their `blocked_by` in a **second pass** (items need refs before they can reference each other). Wiring sorts them into the frontier and the blocked; everything you can't yet specify stays in the fog — the **Not yet specified** section.
5. **Fire the research subagents.** For each `research` task you just created, confirm with the user and spin up a `/research` subagent to resolve it in parallel — since research can be of high token consumption the user might postpone the parallelism, so confirm each research dispatch before doing it. **Claim the task before dispatching**, never after. When a subagent reports, you — not it — close the loop: `attach` its findings to the task, then resolve the task exactly as [Work through the map](#work-through-the-map) step 5 describes, gist line and all. A research answer that never reaches the index is invisible to the next session.
6. Stop. Charting decides nothing by hand — research is the exception, because it answers without a human in the loop, and every other method needs a session of its own.

### Work through the map

User invokes with a map (URL, path or ref). A task is **optional** — without one, you pick the next decision, not the user.

1. `get` the **map** — the low-res view, not every task body.
2. Choose the task. If the user named one, or stated a preference, honour it. Otherwise `list` the map's tasks, compute the frontier, and take the task that advances the frontier most smartly — the one whose answer clears the most fog, unblocks the most work, or is likeliest to redraw the rest. The tracker imposes no order; the judgement is yours.

   An **empty frontier with unresolved tasks left** means they are all claimed or all blocked. Claimed by a session that died leaves a task claimed forever, so name the stranded tasks to the user and break the claim with their agreement rather than reporting the map as stuck.
3. **Claim it** — before any work.
4. Resolve it — **zoom as needed**: `get` the full body of any related or resolved task on demand; invoke the skills the `## Annotations` block names. If in doubt, use `/grilling` and `/domain-modeling`.
5. Record the resolution: `add_note` the answer to the task, `update` it to a resolved state, and **append one gist line** to the map's Decisions-so-far.
6. Add newly-surfaced tasks (create-then-wire); graduate any fog the answer has made specifiable, clearing each graduated patch from **Not yet specified** so it lives only as its new task. If the answer reveals a task — this one or another — sits beyond the destination, **rule it out of scope** rather than resolving it on the route. If the decision invalidates other parts of the map, `update` those tasks, or resolve them as dropped.
7. **Close the map if it's done.** The map is done when no task is unresolved and **Not yet specified** is empty — the way to the destination is clear. Say so, confirm with the user that it reads that way to them too, then `add_note` the route in a line or two and `update` the map to a resolved state. Nothing else resolves it: an effort outlives its last task unless someone ends it, and an open map that is actually finished pollutes every search for live work.

The user may run unblocked tasks in parallel, so expect other sessions to be editing the tracker concurrently.
