# Work tracker: Local Markdown

Items of planned work for this repo are registered in markdown files under the `docs/` directory. Other artifacts, like mockups, design reviews, research maps, postponed ideas, all have their precise placement according to the diagram below. The contents of each file are described by their respective documented guides in this repo. The focus below is on placement and file naming.

## Work items placement

```
docs/
  adr/
    adr001-<adr-slug>.md   → system-wide architectural decision records
  codebase_design_reviews/ → codebase review artefacts
    cdr01-<codebase-review-slug>.html
  features/
    f001-<feature-slug>/  → feature implementation with complete gated workflow
      f001-status.md      → gate approvals + slices/tasks checklist
      g1-product.md
      g2-architecture.md
      g3-program-design.md
      g4-slices.md
      mockups/m01-<mockup-slug>.html
  ideas/
    i01-<idea-slug>.md    → postponed ideas for later consideration
  wayfinder/
    w01-<wayfinder-slug>/ → systematic research with human feedback
      w01-map.md          → research directions, unknowns and tasks checklist
      t01-<task-slug>.md  → wayfinder tasks
      t01-findings/       → directory to store findings per wayfinder task
```

## Naming conventions

- Each type of numbered artefact starts with a common letter(s) identifying their type, then an increasing integer for their id starting from 1.
- Slugs are used for easier identification of the file contents and prevent problems with invalid characters in filenames.
- One feature per directory: `docs/features/fNNN-<feature-slug>/`. The `fNNN` is the feature tag.
- The status of all tasks and gates of a feature are tracked in a single place: their respective fNNN-status.md file.
- One wayfinder effort per directory: `docs/wayfinder/wNN-<wayfinder-slug>/`. The `wNN` is the wayfinder tag.
- Wayfinder tasks are placed under their respective folders, prefixed by the wayfinder tag, numbered from `01` for each folder. To reference a task, prefix it with the wayfinder tag, e.g. `f002/t03`.
- System-wide ADRs are captured in: `docs/adr/`, named `adrNNN-<adr-slug>.md`. Context specific ones are captured in a relative `docs/adr/` directory inside the context.
- Ideas are captured in: `docs/ideas/`, named `iNN-<idea-slug>.md`.
- Codebase design reviews are captured in: `docs/codebase_design_reviews/`, named `cdrNN-<codebase-review-slug>.html`.

## Status management

- The status is managed in determined files: `fNNN-status.md` for features slices and gates, and `wNN-map.md` for wayfinder tasks.
