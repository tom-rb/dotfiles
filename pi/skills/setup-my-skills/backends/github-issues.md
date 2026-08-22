# Backend — GitHub Issues

The **bindings** for GitHub Issues on a repository under a personal account: the state list, the claim recipes, the label set, and the six verbs.

Four things in here fail by returning a confidently wrong answer rather than an error. They are bolded where they arise.

## The verbs

They map onto `gh`. Sub-issues and blocking edges are first-class flags as of `gh` 2.98; issue types are not available, see below.

 - `create` → `gh issue create --title "<t>" --body "" --label <type-label> --parent <n>`. Pass `--body` even when empty; without it `gh` prompts, and a non-interactive session hangs.
 - `get` → `gh issue view <n> --json ...`
 - `list` → `gh issue list --search "sort:created-asc" --state all --limit <n> --json number,title,state,stateReason,parent,blockedBy,labels`. Direct filters: `--label`, `--state`, both of which compose with `--search`. Ask for **every** field a caller filters on in one call and filter the result, rather than making a call per predicate.

   **Always pass `--limit`, and always sort ascending.** `gh issue list` returns 30 by default, newest first. There is no `--parent` filter, so an effort's tasks are drawn from a list of the whole repository filtered client-side: a truncated list makes the frontier, the "no unresolved tasks" check, and every status read wrong without saying so, and the default order silently reverses anything that reads work in creation order — a caller taking "the first unresolved item" gets the newest instead of the oldest. `--search "sort:created-asc"` fixes the order and makes truncation drop the newest rather than the oldest. Set a limit above the repository's issue count and write that number down.

   That whole-repository list filtered on `parent` is the only recipe for an effort's tasks worth writing down. `--json subIssues` looks like the cheaper read, but it is a projection over child issues rather than a way to request arbitrary fields on them: it carries no `blockedBy` or `labels`, so it cannot answer a frontier query.

   **Three of those fields come back as structures, not scalars**: `.parent.number` (or `null`), `.blockedBy.nodes[].number`, `.labels[].name`. Read one as a scalar and the result is empty rather than an error.
 - `update` → `gh issue edit` for fields, including `--parent`, `--add-label`, `--remove-label`, `--add-blocked-by`; `gh issue close --reason completed` or `--reason "not planned"` to resolve; `gh issue reopen` to return a resolved item to an open state, which clears the resolution by itself — there is no second command to run.

   **`--add-blocked-by` is the only flag that writes a blocking edge anything reads back.** `--add-blocking` records the same edge from the other end, and nothing reads it back, so anything written that way lands in the tracker where no `list` will find it.
 - `add_note` → `gh issue comment`
 - `attach` → commits the file to a branch; see below.

`gh` changes between versions. Check the exact flags with `--help` while the user is present and write down what actually worked, not what should work.

## Types are labels here

Issue types are an organization feature, and a repository under a personal account has none. Declare one label per type name, prefixed by its role — `effort-type:<name>`, `task-type:<name>` — and create those labels during provisioning below. `create` passes the type's label, `list` filters on it, and the role prefix means "every effort" is also askable without knowing a single type name. Nothing about this reaches a skill: the rendered file simply answers `type` with a label.

So the label set is the one in `types-and-labels-registry.md`, plus one label per type, plus `claimed`.

## States

**The states are `open` and `closed`**, which is what GitHub enforces and all it enforces. `closed` is the resolved one, and its `resolution` is `stateReason`. **What you write and what you read back are not the same strings**, and every mismatch here yields an empty result rather than an error:

| Read (`--json state,stateReason`) | Write                    | Means        |
|-----------------------------------|--------------------------|--------------|
| `OPEN`, `stateReason: ""`         | `gh issue reopen`        | not resolved |
| `CLOSED`, `COMPLETED`             | `--reason completed`     | `done`       |
| `CLOSED`, `NOT_PLANNED`           | `--reason "not planned"` | `dropped`    |

`--state` takes `open`, while `--json state` returns `OPEN`. An open issue's `stateReason` is the **empty string, not `null`**, so `.stateReason // "x"` never fires and the resolved test is `.state == "CLOSED"` — never an emptiness test on `stateReason`.

## Claiming

**The claim is the label `claimed`.** GitHub has `open` and `closed` and nothing between, so there is no in-progress state to claim with. Claim with `gh issue edit --add-label claimed`, release with `--remove-label claimed`, and list unclaimed work by filtering the label set already returned by the whole-repository call — or with a direct query where one is wanted — `--search` takes a single string, so it folds into the sort: `--search "-label:claimed sort:created-asc"`. The claiming session also `add_note`s who it is, which is what lets the user decide whether a stale claim is safe to break.

## Provision the repository, with the user's agreement

This backend needs two things to exist before any skill can use it. Both are writes to the user's repository, so list exactly what you are about to create and get their agreement before creating any of it:

 - **Every label.** A label must exist before it can be applied, and a skill cannot provision its own — which is why the label set is closed. That means one label per type name, the `claimed` label, and every label declared in `types-and-labels-registry.md`.
 - **The `work-assets` branch**, which is where `attach` puts files. GitHub uploads attachments only through the web UI, so `attach` commits instead.

Create the branch from an empty tree, which touches neither the index nor the working tree and so is safe on a dirty repo:

```sh
git branch work-assets "$(git commit-tree "$(git hash-object -t tree /dev/null)" -m 'work assets')"
git push -u origin work-assets
```

`git switch --orphan` is the obvious alternative and the wrong one: it clears the tracked working tree.

## `attach` writes through a worktree

Once the branch exists, `attach` writes to it through a worktree, so the user's working tree is never disturbed:

```sh
git worktree add /tmp/work-assets work-assets
mkdir -p /tmp/work-assets/<n> && cp <file> /tmp/work-assets/<n>/<name>
git -C /tmp/work-assets add -A
git -C /tmp/work-assets commit -m "attach <name> to #<n>"
git -C /tmp/work-assets push
git worktree remove /tmp/work-assets
```

The body then links `https://github.com/<owner>/<repo>/blob/work-assets/<n>/<name>`. Images render inline from that URL; an HTML mockup does not, so say in the body that it has to be downloaded and opened locally.

## Verify

Run `list` and confirm the result looks right. Do not create a throwaway issue: an issue is visible to anyone watching the repository, and there is no delete.

Verifying is read-only; provisioning was not — it created labels and a branch, both of which the user agreed to beforehand and can remove by hand.

## What the rendered file has to carry

Beyond the generic list at the end of `work-tracker-vocabulary.md`, the rendered `docs/agents/work-tracker.md` needs the four bolded above, verbatim enough that a working agent never has to re-derive them:

 - the `--limit` number you settled on, written into the `list` command itself rather than left as a placeholder, together with `--search "sort:created-asc"`;
 - the read/write state mapping, including the empty-string `stateReason` and the `.state == "CLOSED"` test;
 - the nested field shapes, and the whole-repository-list-filtered-on-`parent` recipe that reads them;
 - `--add-blocked-by`, named as the only flag that writes a blocking edge anything reads back.

Leave out why `type` is a label at all. The rendered file answers `type` with a label and says nothing about issue types being unavailable — a working agent has no use for the distinction.
