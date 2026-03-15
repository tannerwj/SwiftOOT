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

4. Install the remaining macOS build prerequisites described in the upstream
   [`zeldaret/oot` macOS build guide](https://github.com/zeldaret/oot/blob/main/docs/BUILDING_MACOS.md).

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

Run this local verification flow after setup:

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

For project-specific contributor workflow, review rules, and automation
guidance, see [AGENTS.md](AGENTS.md).

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
- ROMs, extracted content, and local build artifacts should remain local and not
  be committed to this repository.
