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

2. Install the macOS build prerequisites described in
   [`Vendor/oot/docs/BUILDING_MACOS.md`](Vendor/oot/docs/BUILDING_MACOS.md).

3. Run the upstream asset setup flow:

```bash
cd Vendor/oot && gmake setup   # extracts assets via ZAPD
cd ../..
```

4. Generate the Xcode workspace:

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
and handoff format.
