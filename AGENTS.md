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

## Linear Workflow

SwiftOOT is intended to run with mostly serial, short-lived agents. One agent should handle one Linear issue, leave the repo in a verifiable state, then stop.

### Issue Readiness

An issue is agent-ready only when all of the following are true:

- The issue is in `Todo`
- The issue is labeled `agent-ready`
- There are no unresolved `blockedBy` issues in Linear
- Scope is narrow enough to finish in a single branch without pulling in adjacent work
- Acceptance criteria are observable and specific
- Verification expectations are stated or can be derived from existing project commands

Do not start issues labeled `blocked` or `needs-human`.

### Agent Loop

1. Read the Linear issue and only the relevant local code/docs.
2. Create or use the issue branch.
3. Implement only the scoped change.
4. Add or update tests for the change.
5. Run the relevant verification commands.
6. Update docs when behavior, setup, architecture, or workflow changed.
7. Leave a concise handoff summary, including what changed and what was verified.
8. Stop. Do not continue into the next ticket in the same session.

### Definition of Done

Before an issue is considered complete, all of the following must be true:

- The scoped implementation is complete
- Relevant tests were added or updated, or the issue explicitly documents why tests are not applicable
- Build/test/lint or equivalent verification commands were run
- Any changed setup, workflow, architecture, or user-facing behavior is documented
- Follow-up work is called out as separate Linear issues instead of being folded in silently
- The issue is ready for review without requiring hidden context from the previous agent

### Handoff Format

Every agent should leave a short summary in the issue, PR, or final report using this structure:

- Changed: the concrete code or files touched
- Verified: exact commands run and the result
- Docs: what was updated, or `none`
- Follow-ups: new issues created or `none`
- Risks: any known gaps, assumptions, or items requiring human review

### When to Split an Issue

Split the issue before implementation if any of these are true:

- The work spans multiple modules with no clear single acceptance test
- The issue mixes infrastructure, feature work, and refactors
- The issue requires multiple architectural decisions that are not already made
- The issue cannot be verified in one pass by a small set of commands or checks
- The issue description says "implement X system" but actually describes several independently shippable steps
