# SwiftOOT

Native macOS app reimplementing Zelda: Ocarina of Time in Swift/Metal, using data extracted from the [zeldaret/oot](https://github.com/zeldaret/oot) decompilation.

Inspired by [Dimillian/PokeSwift](https://github.com/Dimillian/PokeSwift).

## Architecture

A build-time CLI extracts game data from the OoT decompilation (C source + XML assets) into JSON manifests and binary assets. The runtime app is pure Swift/Metal — it never touches C or assembly.

**Modules:** OOTDataModel · OOTExtractCLI · OOTContent · OOTCore · OOTRender · OOTUI · OOTTelemetry · OOTMac

## Prerequisites

- macOS 26.0+
- Xcode 26+
- [Tuist](https://tuist.io)
- A base OoT ROM (not included)

## Setup

```bash
git submodule update --init
cd Vendor/oot && gmake setup   # extracts assets via ZAPD
cd ../..
tuist generate
open SwiftOOT.xcworkspace
```

## Verification

Until CI is in place, every issue should record the exact commands used for verification.

Typical M0 verification flow:

```bash
tuist generate
xcodebuild -workspace SwiftOOT.xcworkspace -scheme OOTMac build
xcodebuild -workspace SwiftOOT.xcworkspace -scheme OOTMac test
```

If a task affects only a subset of targets, prefer the narrowest relevant build/test command and record it in the issue or PR notes.

## Agent Workflow

This project is intended for mostly serial, issue-by-issue agent execution:

- One agent takes one Linear issue
- The issue should be in `Todo` and labeled `agent-ready`
- The agent implements only that issue, runs verification, updates docs if needed, leaves a short handoff, and stops
- The next agent starts from the updated main branch after review or merge

See [AGENTS.md](/Users/tjohnson/repos/SwiftOOT/AGENTS.md) for the issue readiness rules, definition of done, and handoff format.
