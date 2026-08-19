---
name: review-specs
description: Review the latest written specifications for completeness and robustness.
disable-model-invocation: true
---

Focused specification review of the diff between `HEAD` and a fixed point the user supplies:

- **Completeness** — is the specified behavior complete or does it leave room for bugs and undetermined behavior?

Run as a **sub-agent** so it starts unbiased and with a fresh context.

## Hunt for

 - Correctness bugs
 - Race conditions / ordering hazards
 - Uncovered branches / unspecified behavior
 - Test quality

# Report format

Return a numbered list of findings, most severe first. For each: (severity: BUG / RACE / UNSPECIFIED-BEHAVIOR / TEST-QUALITY / NIT, file:line, one-paragraph explanation with the concrete failing interleaving or scenario, and — for uncovered branches — a sketch of the test that would cover it). If you verify something suspicious and conclude it is actually fine, list it under a separate "checked and fine" section with one line each. Be adversarial: prefer concrete interleavings over vague concerns.