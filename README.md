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
