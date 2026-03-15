# SwiftOOT

Native macOS app reimplementing Zelda: Ocarina of Time in Swift/Metal, using data extracted from the [zeldaret/oot](https://github.com/zeldaret/oot) decompilation.

Inspired by [Dimillian/PokeSwift](https://github.com/Dimillian/PokeSwift).

## Architecture

A build-time CLI extracts game data from the OoT decompilation (C source + XML assets) into JSON manifests and binary assets. The runtime app is pure Swift/Metal — it never touches C or assembly.

**Modules:** OOTDataModel · OOTExtractCLI · OOTContent · OOTCore · OOTRender · OOTUI · OOTTelemetry · OOTMac

## Prerequisites

- macOS 26.0+
- Xcode 26+
- [Tuist](https://tuist.io) 4.158.2 (pinned in [`.tool-versions`](.tool-versions))
- A base OoT ROM (not included)

## Setup

SwiftOOT pins the upstream [zeldaret/oot](https://github.com/zeldaret/oot)
checkout as a git submodule in `Vendor/oot/`. `OOTExtractCLI` reads from that
checkout after the upstream `gmake setup` flow has completed.

1. Initialize the pinned submodule checkout:

```bash
git submodule update --init
```

2. Apply the repo-local compatibility patches required by the pinned
   `Vendor/oot` checkout on current macOS clang:

```bash
./scripts/apply_vendor_oot_patches.sh
```

3. Install the macOS build prerequisites described in
   [`Vendor/oot/docs/BUILDING_MACOS.md`](Vendor/oot/docs/BUILDING_MACOS.md).

4. Run the upstream asset setup flow:

```bash
cd Vendor/oot && gmake setup   # extracts assets via ZAPD
cd ../..
```

5. Generate the Xcode workspace:

```bash
mise install tuist             # optional, but matches CI's pinned Tuist setup
tuist generate --no-open
open SwiftOOT.xcworkspace
```

## Verification

CI now runs the following M0 verification flow on every pull request. No extra
environment variables are required for this path.

```bash
tuist generate --no-open
xcodebuild -workspace SwiftOOT.xcworkspace -scheme OOTMac -destination 'platform=macOS' build
xcodebuild -workspace SwiftOOT.xcworkspace -scheme SwiftOOT-Workspace -destination 'platform=macOS' test
```

`OOTMac` is the buildable app scheme, while `SwiftOOT-Workspace` is the scheme
that runs the current M0 unit test bundles. If you use `mise`, `mise install
tuist` reads the pinned version from `.tool-versions`; otherwise install Tuist
4.158.2 manually before running the commands above.

## Agent Workflow

This project is intended for mostly serial, issue-by-issue agent execution:

- One agent takes one Linear issue
- The issue should be in `Todo` and labeled `agent-ready`
- The agent implements only that issue, runs verification, updates docs if needed, leaves a short handoff, and stops
- The next agent starts from the updated main branch after review or merge

See [AGENTS.md](AGENTS.md) for the issue readiness rules, definition of done,
handoff format, and the short checklist used to gate `agent-ready` and review.
Use [docs/linear-issue-template.md](docs/linear-issue-template.md) when writing
new Linear issues.

## Symphony Workflow

Symphony is the worker orchestrator for this repo. Linear is the source of truth
for what Symphony should pick up next.

### Issue States

- `Backlog`: not ready for implementation
- `Todo`: ready for Symphony pickup
- `In Progress`: Symphony worker is actively implementing the issue
- `Human Review`: implementation is complete and ready for branch/PR review
- `Rework`: review found issues; Symphony should continue from the current
  branch/workspace by default and address the requested changes there
- `Merging`: approved and ready for Symphony to land
- `Done`: merged and complete

### Expected Flow

1. Move a small, unblocked, well-scoped issue to `Todo`.
2. Symphony picks it up, creates a branch/PR, implements the change, verifies it, and moves the issue to `Human Review`.
3. Human review checks the actual PR branch, not just the Linear summary.
4. If changes are needed:
   - move the issue to `Rework`
   - leave concrete review feedback on the PR or Linear issue
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
