# Agent Guidelines for SwiftOOT

## Project Context

SwiftOOT reimplements Zelda: Ocarina of Time as a native macOS SwiftUI/Metal app. Game data is extracted from the [zeldaret/oot](https://github.com/zeldaret/oot) C decompilation at build time. The runtime is pure Swift.

## Module Map

| Module | Purpose | Dependencies |
|---|---|---|
| `OOTDataModel` | Pure `Codable & Sendable` value types | none |
| `OOTExtractCLI` | Build-time extraction: C/XML → JSON + binary | OOTDataModel |
| `OOTContent` | Runtime content loading + caching | OOTDataModel |
| `OOTCore` | Headless game engine (`GameRuntime`) | OOTContent, OOTDataModel, OOTTelemetry |
| `OOTRender` | Metal 3D renderer, F3DEX2 interpreter | OOTDataModel |
| `OOTUI` | SwiftUI views, sidebars, HUD | OOTRender, OOTContent, OOTDataModel, OOTTelemetry |
| `OOTTelemetry` | Debug/diagnostics | OOTDataModel |
| `OOTMac` | macOS app host | all |

## Conventions

- **Swift 6.0**, strict concurrency, macOS 26.0 deployment target
- All data model types must be `Codable & Sendable`
- `GameRuntime` is `@MainActor @Observable` — the single source of truth
- Extraction output goes to `Content/OOT/` — never commit extracted content
- Actor behavior is reimplemented in Swift (not transpiled from C). Use the zeldaret/oot C source as reference.
- JSON for display list commands, binary for vertex/texture data

## Key Technical Concepts

### F3DEX2 Display Lists
N64 GPU command format. Parsed from `.inc.c` files at extraction time → JSON. Interpreted at runtime by `F3DEX2Interpreter` which translates to Metal draw calls. The interpreter maintains RSP state (vertex buffer, matrix stack) and RDP state (combiner, tile descriptors, color registers).

### N64 Texture Formats
RGBA16, CI4, CI8, I4, I8, IA4, IA8, IA16, RGBA32. Extracted to raw binary. Converted to `MTLTexture` at runtime by `TextureLoader`.

### Color Combiner
N64's fragment pipeline: `(A - B) * C + D` per cycle, 2 cycles. Emulated in a single parameterized Metal fragment shader with uniform-driven input selection.

### Extraction Pipeline
`OOTExtractCLI` reads from a cloned zeldaret/oot repo (after `gmake setup` has been run). It parses:
- C header table macros → game tables JSON
- Scene/object XMLs + `.inc.c` files → geometry, textures, skeletons, animations, collision
- Actor `.c` files → actor profiles

Current validated local bootstrap:

- `git submodule update --init`
- install Homebrew `make` and `mipsel-linux-gnu-binutils`
- place a supported ROM in `Vendor/oot/baseroms/<version>/baserom.{z64,n64,v64}`
- run `cd Vendor/oot && MIPS_BINUTILS_PREFIX=mipsel-linux-gnu- gmake setup VERSION=ntsc-1.2`
- run `tuist install && tuist generate --no-open`

If current macOS clang fails in `tools/assets/build_from_png`, the temporary
local workaround is:

- `cd Vendor/oot && MIPS_BINUTILS_PREFIX=mipsel-linux-gnu- gmake setup VERSION=ntsc-1.2 CFLAGS='-Wno-error=gnu-folding-constant'`

Track the permanent fix in `TAN-79`.

## Working with the Decompilation

The zeldaret/oot repo lives at `Vendor/oot/`. Key locations:
- `include/tables/scene_table.h` — scene definitions (101 scenes)
- `include/tables/actor_table.h` — actor definitions (512 actors)
- `assets/xml/scenes/` — scene asset XMLs
- `assets/xml/objects/` — object asset XMLs (3D models, skeletons)
- `src/overlays/actors/` — actor C source (behavior reference)
- `src/code/` — core engine C source (systems reference)

## What NOT to Do

- Don't commit extracted `Content/OOT/` assets or the `Vendor/oot/` submodule contents
- Don't try to compile or link OoT's C code into the Swift app
- Don't add dependencies without discussing first
- Don't implement actor behavior by transpiling C — rewrite idiomatically in Swift
- Don't over-abstract. Three similar lines > premature abstraction.

## Symphony Orchestration

Symphony is the execution layer for issue work. Linear is the queue.

### State Machine

- `Backlog`: not ready
- `Todo`: ready for Symphony pickup
- `In Progress`: worker is active
- `Human Review`: branch/PR is ready for review
- `Rework`: reviewer found issues; Symphony should continue on the existing branch, workspace, and PR by default
- `Done`: human merged the PR and moved the issue here

### Agent Issue Checklist

Apply this short checklist to every issue before adding `agent-ready` and again
before moving the work to review:

- [ ] The problem, in-scope change, and out-of-scope boundary are explicit.
- [ ] The issue is small enough for one focused branch/PR; if not, split it
  first.
- [ ] Validation is explicit: exact commands, expected proof, and any required
  real-source acceptance path are written in the issue.
- [ ] Required inputs are available now: repo files, fixtures, generated
  content, tools, and permissions.
- [ ] The implemented change stays within scope and updates tests or fixtures
  when behavior changed.
- [ ] Docs are updated when behavior, setup, architecture, workflows, or
  reproducible validation changed.
- [ ] Verification notes record what ran, what passed, and any follow-up work is
  filed as a separate issue instead of being silently skipped.

### `agent-ready` Definition

An issue may carry `agent-ready` only when all of these are true:

- the title names one concrete outcome
- scope and non-goals are explicit enough to reject adjacent work
- dependencies and prerequisites are already available in the repo or issue text
- exact validation commands are written, not implied
- parser/extractor tickets include the real-source command and expected output
  files when fixture coverage is not enough
- the issue is still single-branch sized; if it naturally becomes multiple
  independently reviewable changes, split it first

Remove `agent-ready` or keep the issue in `Backlog` when any of those conditions
is false.

### Definition Of Done

An issue is done for agent handoff only when all of these are true:

- the scoped change is implemented without expanding into neighboring tickets
- relevant tests, fixtures, or regression coverage were added or updated
- required validation commands were run on the final branch state
- docs were updated when the change altered behavior, setup, architecture,
  workflows, or the reproducible validation path
- any discovered out-of-scope work was captured as follow-up issues
- handoff notes include the required verification record below

### Verification Notes Format

Use this format in the workpad or final handoff notes:

```md
Validation
- `<command>` -> pass/fail, with one-line proof
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

Keep the notes brief, but always include the exact commands that were actually
run.

### When Docs Updates Are Required

Update docs when a change modifies any of these:

- user-visible behavior or developer workflow
- setup, bootstrap, build, test, or release steps
- architecture or module responsibilities
- required validation commands, fixtures, or expected output files
- issue execution rules that future workers or reviewers rely on

### When To Split An Issue

Split the issue before `agent-ready` when any of these are true:

- the work spans multiple modules with different validation strategies
- the issue bundles unrelated outcomes that could be reviewed independently
- the acceptance criteria require "and also" work better expressed as separate
  tickets
- there is no single validation command set that proves the whole change
- the worker would need to make major product or architecture decisions that are
  not already captured in the issue

When splitting, keep the current issue as the smallest independently shippable
slice and create follow-up issues for the rest.

### Worker Contract

For a normal implementation pass, Symphony should:

1. pick one issue from `Todo`
2. create a fresh branch from current `master`
3. implement only that issue
4. run the issue's verification commands
5. update docs if behavior or setup changed
6. open or update the PR
7. move the issue to `Human Review`
8. stop

Workers should not continue directly into the next issue from the same branch.

For extractor and parser issues, fixture tests are necessary but not sufficient.
If the issue touches `Vendor/oot` parsing, the worker must also run the exact
real-source acceptance command from the issue against the local `Vendor/oot`
tree before moving to `Human Review`.

For example, a scene-scoped extractor issue should not move to review unless the
worker has verified the real command succeeds and the expected output files
exist on disk.

### Reviewer Contract

Review the actual branch, not just the issue text or agent handoff.

At minimum:

- inspect the PR diff
- verify the branch still matches the issue scope
- run relevant local verification commands when practical
- look for packaging, scheme, entrypoint, or merge-order problems that CI may miss

If the branch is acceptable:

- approve and merge the PR on GitHub
- move the issue to `Done` in Linear

If the branch is not acceptable:

- move the issue to `Rework`
- leave concrete feedback in Linear or on the PR
- include the exact command to rerun
- include the exact expected output files to check
- include the exact failure string if one was observed

### Rework Rules

When an issue moves to `Rework`, the next Symphony worker should:

- preserve the existing workspace, branch, and PR by default
- address only the review findings
- push a focused follow-up commit on the same branch when possible

Create a fresh branch only when:

- the existing PR was closed or merged
- the branch cannot be pushed or recovered cleanly
- the workspace is corrupted
- the reviewer explicitly requests a reset

If the same issue returns to `Rework` more than twice for the same underlying
failure mode, stop treating it as a normal review loop. Tighten the issue's
verification contract, add a regression test for the real failing input shape,
and either:

- have the next worker prove the real acceptance command locally before review, or
- take over the branch directly and fix it.

### Lessons Learned

`TAN-30` exposed a repeatable failure pattern:

- fixture-only tests gave false confidence
- the real `Vendor/oot` source used macro-heavy forms the fixtures did not cover
- reviewers were correctly catching the failure, but the branch kept returning
  with narrow fixes that still did not satisfy the real command

To avoid repeating that pattern:

- write at least one regression test from a real upstream source shape, not only
  a simplified fixture invented for the test
- put the exact real-source acceptance command in the issue body
- require the worker handoff to include the command output and the concrete
  generated files
- reject parser/extractor issues that only prove synthetic fixtures
