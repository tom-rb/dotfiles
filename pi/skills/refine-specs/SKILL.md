---
name: refine-specs
description: Refine the latest written specifications to maximize information density and eliminate redundancy
disable-model-invocation: true
---

## Goal
Your goal is to maximize information density and eliminate redundancy.

## Task
Analyze the provided technical specification(s). Revise and condense the documentation to remove verbosity, duplicate information, and fluff without losing a single technical requirement, constraint, edge case, or architectural decision.

### Strict Editing Rules

 - Remove decision reminders: A specification is a clean target state, not a decision log. Remove any reminders of decisions made in previous specs or during the refinement process (e.g. "as agreed", "not marked as an issue", "by your decision"). The later specs assume all background from previous specs is true. Don't restate them.

 - Apply the DRY Principle: If a concept, flow, or requirement is mentioned more than once, merge the information into a single "Single Source of Truth" and remove all other rephrased instances. Keep a reference only if it's **directly relevant** to the concept being specified, assume the reader already have read the previous specs.

 - Strip conversational fillers & meta-commentary: Remove introductory/concluding filler (e.g., "This section outlines...", "In conclusion...", "It is important to note that..."). Maintain it directly to the facts.

 - Use Active, Imperative Voice: Change passive or verbose phrasing (e.g., "The system should have the capability to allow the user to...") to direct commands (e.g., "The system must allow users to...").

 - Convert Prose to Structured Data: Where possible, replace dense paragraphs with bulleted lists, numbered execution flows, or Markdown tables.

 - Zero Technical Loss: Do not simplify or abstract away actual technical depth. Keep all API endpoints, data schemas, specific variable names, error codes, and business logic intact.

## Output Format

The Revised Specification(s): The clean, condensed, and deduplicated documents rewritten in place.

Editorial Summary: At the very end of the conversation, provide a brief summary of the documents changed, along with an estimated percentage reduction in word count.
