# SwiftOOT

Native macOS app reimplementing Zelda: Ocarina of Time in Swift/Metal, using data extracted from the [zeldaret/oot](https://github.com/zeldaret/oot) decompilation.

Inspired by [Dimillian/PokeSwift](https://github.com/Dimillian/PokeSwift).

## Architecture

A build-time CLI extracts game data from the OoT decompilation (C source + XML assets) into JSON manifests and binary assets. The runtime app is pure Swift/Metal — it never touches C or assembly.

**Modules:** OOTDataModel · OOTExtractCLI · OOTContent · OOTCore · OOTRender · OOTUI · OOTTelemetry · OOTMac

## Rendering Modes

The gameplay debugger sidebar now exposes a live render-mode toggle:

- `N64 Aesthetic` renders through a 320x240 offscreen target with retro post-processing.
- `Enhanced` renders at native window resolution with smoother filtering, post AA, and EDR output on supported displays.

Switching modes updates the current scene immediately without reloading gameplay state.

Enhanced mode only opts into the EDR presentation path when the active target
screen reports `maximumPotentialExtendedDynamicRangeColorComponentValue > 1`.
On those screens SwiftOOT switches the `MTKView` drawable to a floating-point
EDR output path; on unsupported screens it keeps the existing SDR presentation
configuration.

Validate the output-mode selection with:

```bash
swift test --filter OOTRenderTests
swift test --filter OOTUITests/testFixtureRuntimeCaptureSupportsBothPresentationModes
```

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

## Deterministic Developer Harness

`OOTMac` now supports a developer-only harness for deterministic scene launch,
scripted controller input, and capture export. The harness stays dormant unless
you set one or more of these environment variables before launching the app:

- `SWIFTOOT_SCENE`: scene name like `spot04` or scene id like `0x55`
- `SWIFTOOT_ENTRANCE`: optional entrance index override
- `SWIFTOOT_SPAWN`: optional spawn index override
- `SWIFTOOT_TIME_OF_DAY`: optional fixed hour value such as `18.5`
- `SWIFTOOT_DIRECTOR_COMMENTARY`: optional `1`/`true` flag to start gameplay with commentary mode enabled
- `SWIFTOOT_INPUT_SCRIPT`: optional JSON script path
- `SWIFTOOT_CAPTURE_FRAME`: optional PNG output path
- `SWIFTOOT_CAPTURE_STATE`: optional JSON output path
- `SWIFTOOT_CAPTURE_VIEWPORT`: optional capture size such as `960x540`

The script format is a top-level JSON array. Each step must define exactly one
of `duration` or `frameRange`, and may set `stick`, `lPressed`, `rPressed`,
`aPressed`, `bPressed`, `cLeftPressed`, `cDownPressed`, `cRightPressed`,
`zPressed`, and `startPressed`. See
[`docs/developer-harness-script.example.json`](docs/developer-harness-script.example.json)
for a checked-in example.

For a reproducible local capture, build the app into a known derived-data path
and launch the resulting binary with the harness variables:

```bash
xcodebuild -workspace SwiftOOT.xcworkspace -scheme OOTMac -destination 'platform=macOS' -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build
SWIFTOOT_CONTENT_ROOT=/absolute/path/to/Content/OOT \
SWIFTOOT_SCENE=spot04 \
SWIFTOOT_TIME_OF_DAY=18.5 \
SWIFTOOT_DIRECTOR_COMMENTARY=1 \
SWIFTOOT_INPUT_SCRIPT=$PWD/docs/developer-harness-script.example.json \
SWIFTOOT_CAPTURE_FRAME=$PWD/tmp/harness/frame.png \
SWIFTOOT_CAPTURE_STATE=$PWD/tmp/harness/state.json \
SWIFTOOT_CAPTURE_VIEWPORT=960x540 \
.build/xcode/Build/Products/Debug/OOTMac.app/Contents/MacOS/OOTMac
```

When `SWIFTOOT_CAPTURE_FRAME` or `SWIFTOOT_CAPTURE_STATE` is set, the harness
launches straight into gameplay, replays the scripted input, writes the
requested outputs, and terminates the app automatically.

When validating extractor work against the real `Vendor/oot` tree, use the
exact issue command. For example, the current scoped extraction smoke test is:

```bash
swift run OOTExtractCLI extract --source Vendor/oot --output /tmp/swiftoot-spot04 --scene spot04
swift run OOTExtractCLI verify --content /tmp/swiftoot-spot04
```

The extractor now also emits scoped music bundles under `Content/OOT/Audio/BGM`
with a catalog at `Content/OOT/Manifests/audio/bgm-tracks.json`, plus bounded
sound effect bundles under `Content/OOT/Audio/SFX` with a catalog at
`Content/OOT/Manifests/audio/sfx.json`.

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
