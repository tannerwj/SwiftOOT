# SwiftOOT

Native macOS app reimplementing Zelda: Ocarina of Time in Swift/Metal, using data extracted from the [zeldaret/oot](https://github.com/zeldaret/oot) decompilation.

Inspired by [Dimillian/PokeSwift](https://github.com/Dimillian/PokeSwift).

## Legal

SwiftOOT is an unofficial fan project. It is not affiliated with or endorsed by
Nintendo.

- This repository does not include any Nintendo ROMs, textures, audio, text, or
  other game assets.
- To use the extraction pipeline, you must supply your own legally obtained copy
  of Ocarina of Time.
- The `Vendor/oot` checkout is a separate upstream submodule. SwiftOOT's MIT
  license applies to the original code in this repository, not to third-party
  dependencies or to any content generated from a game ROM.

## Architecture

A build-time CLI extracts game data from the OoT decompilation (C source + XML assets) into JSON manifests and binary assets. The runtime app is pure Swift/Metal — it never touches C or assembly.

**Modules:** OOTDataModel · OOTExtractCLI · OOTContent · OOTCore · OOTRender · OOTUI · OOTTelemetry · OOTMac

## Prerequisites

- macOS 26.0+
- Xcode 26+
- [Tuist](https://tuist.io) 4.158.2 (pinned in [`.tool-versions`](.tool-versions))
- A base OoT ROM (not included)
- Homebrew `make` (`gmake`) and `mipsel-linux-gnu-binutils` for `Vendor/oot`

## Setup

SwiftOOT pins the upstream [zeldaret/oot](https://github.com/zeldaret/oot)
checkout as a git submodule in `Vendor/oot/`. `OOTExtractCLI` reads from that
checkout after the upstream `gmake setup` flow has completed.

1. Install the pinned Tuist version and the local `Vendor/oot` helpers:

```bash
mise install tuist
brew install make mipsel-linux-gnu-binutils
```

2. Initialize the pinned submodule checkout:

```bash
git submodule update --init
```

3. Apply the repo-local compatibility patches required by the pinned
   `Vendor/oot` checkout on current macOS clang:

```bash
./scripts/apply_vendor_oot_patches.sh
```

4. Install the remaining macOS build prerequisites described in
   [`Vendor/oot/docs/BUILDING_MACOS.md`](Vendor/oot/docs/BUILDING_MACOS.md).

5. Put your ROM in the matching upstream baserom folder.

This follows the same layout `zeldaret/oot` expects: choose a supported
version, place the ROM in `baseroms/<version>/`, and name it `baserom.z64`,
`baserom.n64`, or `baserom.v64`.

Supported upstream versions include:

- `ntsc-1.0`
- `ntsc-1.1`
- `ntsc-1.2`
- `pal-1.0`
- `pal-1.1`
- `gc-jp`
- `gc-jp-mq`
- `gc-us`
- `gc-us-mq`
- `gc-eu-mq-dbg`
- `gc-eu-dbg`
- `gc-eu`
- `gc-eu-mq`
- `gc-jp-ce`
- `ique-cn`

Validated local flow:

```bash
cp ~/Downloads/<your-rom>.n64 Vendor/oot/baseroms/ntsc-1.2/baserom.n64
```

More generally, upstream expects:

```bash
Vendor/oot/baseroms/<version>/baserom.z64
Vendor/oot/baseroms/<version>/baserom.n64
Vendor/oot/baseroms/<version>/baserom.v64
```

If you are unsure which version you have, compare it against the supported
version table in `Vendor/oot/README.md`.

6. Run the upstream asset setup flow.

```bash
cd Vendor/oot
MIPS_BINUTILS_PREFIX=mipsel-linux-gnu- gmake setup VERSION=ntsc-1.2
cd ../..
```

7. Resolve packages and generate the Xcode workspace:

```bash
tuist install
tuist generate --no-open
open SwiftOOT.xcworkspace
```

## Verification

CI now runs the following verification flow on every pull request.

```bash
tuist install
tuist generate --no-open
xcodebuild -workspace SwiftOOT.xcworkspace -scheme OOTMac -destination 'platform=macOS' build
xcodebuild -workspace SwiftOOT.xcworkspace -scheme SwiftOOT-Workspace -destination 'platform=macOS' test
```

`OOTMac` is the buildable app scheme, while `SwiftOOT-Workspace` is the scheme
that runs the current M0 unit test bundles. If you use `mise`, `mise install
tuist` reads the pinned version from `.tool-versions`; otherwise install Tuist
4.158.2 manually before running the commands above.

When validating extractor work against the real `Vendor/oot` tree, use the
exact issue command. For example, the current scoped extraction smoke test is:

```bash
swift run OOTExtractCLI extract --source Vendor/oot --output /tmp/swiftoot-spot04 --scene spot04
swift run OOTExtractCLI verify --content /tmp/swiftoot-spot04
```

## Generated vs Committed

Committed:

- Swift source, tests, project definitions, docs
- the `Vendor/oot` submodule pointer

Generated or supplied locally and not committed to this repository:

- `Vendor/oot/baseroms/`
- `Vendor/oot/extracted/`
- `Vendor/oot/build/`
- `Content/OOT/`
- Xcode/Tuist build artifacts like `Derived/`, `DerivedData/`, and `.build/`

## Agent Workflow

This project is intended for mostly serial, issue-by-issue agent execution:

- One agent takes one Linear issue
- The issue should be in `Todo` and labeled `agent-ready`
- The agent implements only that issue, runs verification, updates docs if needed, leaves a short handoff, and stops
- The next agent starts from the updated main branch after review or merge

See [AGENTS.md](AGENTS.md) for the issue readiness rules, definition of done,
handoff format, and the short checklist used to gate `agent-ready` and review.

## Symphony Workflow

Symphony is the worker orchestrator for this repo. Linear is the source of truth
for what Symphony should pick up next.

### Issue States

- `Backlog`: not ready for implementation
- `Todo`: ready for Symphony pickup
- `In Progress`: Symphony worker is actively implementing the issue
- `Human Review`: implementation is complete and ready for branch/PR review
- `Rework`: review found issues; Symphony should continue on the existing branch, workspace, and PR by default
- `Merging`: approved and ready for Symphony to land
- `Done`: merged and complete

### Expected Flow

1. Move a small, unblocked, well-scoped issue to `Todo`.
2. Symphony picks it up, creates a branch/PR, implements the change, verifies it, and moves the issue to `Human Review`.
3. Human review checks the actual PR branch, not just the Linear summary.
4. If changes are needed:
   - move the issue to `Rework`
   - leave concrete review feedback on the PR or Linear issue
   - keep the same branch and PR unless the reviewer explicitly requests a restart
5. If approved:
   - move the issue to `Merging`
   - Symphony lands the PR and moves the issue to `Done`

### Review Standard

Human review should verify branch-level reality:

- read the PR diff
- inspect the actual branch contents
- run the relevant local build/test commands when practical
- confirm the branch satisfies the Linear issue contract

Passing CI is necessary but not sufficient. If the branch introduces merge risk,
runner-only breakage, incorrect packaging, or misses issue acceptance criteria,
send it back to `Rework`.

## Lessons Learned

`TAN-30` showed that parser and extractor tickets need stronger acceptance
checks than normal app or module-skeleton work.

The main failure mode was:

- unit tests passed on simplified fixtures
- the real `Vendor/oot` source used additional macro forms
- the worker kept fixing only the last reported parse error instead of proving
  the full real command succeeded

For future extractor/parser issues:

- include the exact real-source command in the issue
- require the worker to run that command before review
- require the worker to confirm the expected output files exist
- add at least one regression test derived from the real upstream source shape

For reviewers:

- if the real-source command fails, send the issue back with the exact command,
  exact failure string, and exact expected output path
- if the same issue loops on the same failure mode, stop the loop and fix or
  restate the issue more concretely
