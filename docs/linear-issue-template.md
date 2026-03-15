# Linear Issue Template

Copy this into new SwiftOOT Linear issues.

## Title

Use `<verb> <single outcome>` and keep it branch-sized.

## Why This Exists

One or two sentences on the user, engine, extractor, or workflow problem this
issue solves.

## Scope

- In scope change 1
- In scope change 2
- In scope change 3

## Out Of Scope

- Adjacent work that should not be pulled into this issue

## Prerequisites / Dependencies

- Required repo state, generated inputs, tools, or upstream issues

## Acceptance Criteria

- Concrete outcome 1
- Concrete outcome 2
- Concrete outcome 3

## Validation

- `exact command here`
- `exact command here`

Add real-source commands and expected output files for parser/extractor issues.

## Docs Impact

- Docs update required because `<reason>`
  or
- No docs update expected because `<reason>`

## Split Before `agent-ready` If

- the issue would require more than one focused branch/PR
- the work crosses unrelated modules or review surfaces
- validation cannot be written as one coherent command set
- major open decisions are still unresolved

## `agent-ready` Checklist

- [ ] Problem, scope, and non-goals are explicit
- [ ] Validation commands are exact and reproducible
- [ ] Required inputs, tools, and fixtures are available
- [ ] Real-source acceptance path is included when fixture tests are not enough
- [ ] Issue is small enough for one focused branch/PR

## Definition Of Done Checklist

- [ ] Scope implemented without expanding into adjacent tickets
- [ ] Relevant tests or fixtures added or updated
- [ ] Validation commands run on the final branch state
- [ ] Docs updated when behavior/setup/architecture/workflow/validation changed
- [ ] Follow-up work captured in separate issues instead of silently skipped
- [ ] Verification notes include exact commands, results, docs decision, and
      follow-ups

## Verification Notes Format

```md
Validation
- `<command>` -> pass/fail, with one-line proof

Docs
- updated: `<path>` because `<reason>`
  or
- not needed: `<reason>`

Follow-ups
- none
  or
- `<issue id>`: `<gap or deferred work>`
```
