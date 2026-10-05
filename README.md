# BIG WALK iOS

[简体中文](README.zh-CN.md) · English

Native ARM64 compatibility port of the purchased macOS Steam build of **BIG WALK** to iOS. The repository contains the host app, compatibility bridges, audited preparation scripts, and documentation. Obtain the original game separately through your own purchase; commercial game binaries, assets, SDK binaries, signing profiles, saves, and runtime account data are excluded.

## Verified release — 2026-10-05

Fixed input: BIG WALK **1.5.1**, build **20260827105422**, Unity **6000.3.17f1**. Tested on **iPhone 17 / A19 / iOS 26.3**. The Xcode target has a minimum iOS version of 17.0; this is a build setting, not a claim that older phones were tested.

- Existing worlds load and are playable; game audio has received audible user confirmation.
- Real EOS Device ID authentication, connection health, lobby creation, join codes, and cross-device map synchronization were verified. Authentication and network status come from SDK results; no fabricated tickets, identities, or server success responses.
- Touch keyboard/mouse layout is visible and usable, confirmed by the user. W, Shift, Ctrl, and both mouse buttons also passed actual Unity hold/release probes.
- Adaptive 720p / 900p / 1080p / 1.5K presets use short edges of **720 / 900 / 1080 / 1440 pixels**. The long edge follows the device viewport. Both the original graphics menu and the touch settings expose the four sizes.
- Windowed/fullscreen-off startup and all four resolution transitions passed on the tested phone.
- Six desktop quality presets passed the original QualitySettings API test with expensive changes enabled, then restored the original quality level. All retained texture mip limit 2. The same process stayed alive for 90 seconds, with a measured peak footprint of **2,500,709,264 bytes**. The user also confirmed manual menu quality switching works.

See [verification-summary.json](verification-summary.json) for the compact status snapshot and [BUILD.md](BUILD.md) for reproduction.

## Touch controls and resolution

Open the top **⚙** button to select keyboard/mouse or Xbox layout, show/hide controls, set opacity, button size, camera sensitivity, and resolution. **⌨** opens text entry for room names and other text. WASD is a sliding movement pad; drag the camera area to look around. Shift runs, Ctrl crouches, Space jumps; Q/E and mouse buttons follow the original serialized keyboard/mouse bindings. See [CONTROLS.md](docs/CONTROLS.md).

| Short-edge preset | Tested iPhone viewport, 874:402 | iPad 4:3 geometry example |
| --- | --- | --- |
| 720p | 1566 × 720 | 960 × 720 |
| 900p | 1956 × 900 | 1200 × 900 |
| 1080p | 2348 × 1080 | 1440 × 1080 |
| 1.5K | 3130 × 1440 | 1920 × 1440 |

The UIKit canvas retains the native viewport. The render size is independent of touch layout. iPad ratios were checked locally; **no iPad hardware validation** has been performed.

## How the port works

Preparation operates on independent copies and preserves the original Steam installation. Ordinary ARM64 slices are retargeted, dependencies are routed into scoped compatibility frameworks, and the host calls the original Unity player entry point. AppKit window/input behavior is adapted to UIKit; Metal rendering remains native. The audio facade adapts the macOS HAL/AudioUnit calls to the real iOS audio session and output device.

The EOS adaptation changes six guarded call ranges in the fixed GameAssembly image to query genuine EOS login state in the original authentication, network-monitor, and host/join-menu paths. The resource scripts enable the Apple controller backend and preserve the tested mobile mip budget across all eight quality presets. The latter changes eight bytes in the decompressed QualitySettings object and retains every unrelated compressed block.

The 720p keyboard fix replaces a desktop logical-width threshold with detection of the actual Metal game canvas. The right-mouse fix supplies the missing superclass event handlers while retaining Unity's original input handling.

## Limits

Actual microphone send/receive has not been verified, although the Dissonance network handshake was observed. The optional system-root certificate experiment is not part of this verified build; complete HTTPS certificate adaptation is still pending. Steam friends integration and Game Center are not implemented. No LAN/offline multiplayer mode has been established.

Source is tied to the fixed game hashes. A different game build requires a new audit. No App Store distribution or universal unsigned IPA is provided by this repository. Use your own valid signing identity, provisioning, and supported entitlements; locally exported development IPAs retain the originating signing restrictions.

## Repository layout and attribution

- `outputs/bigwalk-ios/`: Xcode host, native bridges, preparation/resource scripts, and audits.
- `docs/`: English and Chinese operating notes.
- `verification-summary.json`: sanitized verification snapshot.

The compatibility layer builds on the preceding Stray iOS work. Touch controller layout/mapping includes adaptations from Geocld/XStreaming; attribution and its MIT license are retained in [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt). [LICENSE](LICENSE) covers the supplied compatibility source, not BIG WALK, Unity, EOS, or other third-party commercial software.
