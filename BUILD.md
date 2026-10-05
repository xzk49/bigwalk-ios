# Build and install

[简体中文](BUILD.zh-CN.md)

Use macOS with Xcode and the iPhoneOS SDK, Python 3.9 or newer, your purchased fixed macOS Steam game build, and your own Apple development signing identity/provisioning. This source uses modern Python path methods; Python 3.9+ is required. Input hashes are pinned in `outputs/bigwalk-ios/source-audit.json`; a different game version must be audited separately rather than disabling guards.

The generated keyboard table contains local macOS keyboard-layout data. It is deliberately excluded from Git; build the supplied generator on your own Mac before preparing the bridges. `BIGWALK_MAC_APP` overrides the standard Steam installation path. The original bundle is read-only; generated frameworks, manifests and staged resources live under `work/`.

```sh
# Run from the repository root. Replace signing placeholders before staging.
python3 -m venv work/unity-tools
work/unity-tools/bin/python -m pip install UnityPy==1.25.4
export BIGWALK_MAC_APP="$HOME/Library/Application Support/Steam/steamapps/common/Big Walk/Big Walk.app"
export BIGWALK_TEAM_ID="YOUR_TEAM_ID"
export BIGWALK_SIGN_ID="YOUR_CODESIGN_IDENTITY"
cd outputs/bigwalk-ios
mkdir -p ../../work/bigwalk-probe
xcrun clang -fobjc-arc -framework Carbon -framework Foundation \
  compat/snapshot-keyboard.m -o ../../work/bigwalk-probe/snapshot-keyboard
../../work/bigwalk-probe/snapshot-keyboard compat/StrayUSKeyboard.inc \
  ../../work/bigwalk-probe/keyboard-reference.json
python3 prepare-unity.py
python3 tools/check-imports.py
xcodebuild -project BigWalkProbe.xcodeproj -scheme BigWalkProbe \
  -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath ../../work/bigwalk-probe/DerivedData \
  DEVELOPMENT_TEAM="$BIGWALK_TEAM_ID" -allowProvisioningUpdates build
python3 stage.py --identity "$BIGWALK_SIGN_ID" --steam-appid \
  --apple-controller --ios-audio-output --eos-device-auth \
  --eos-network-monitor --eos-menu-auth --mobile-texture-budget
codesign --verify --deep --strict ../../work/bigwalk-probe/package/BigWalkProbe.app
python3 tools/check-eos-candidate.py ../../work/bigwalk-probe/package/BigWalkProbe.app \
  --prepared ../../work/bigwalk-probe/Frameworks/GameAssembly.framework/GameAssembly.dylib \
  --audit ../../work/bigwalk-probe/eos-device-auth-audit.json \
  --output ../../work/bigwalk-probe/release-range-verification.json
```

## Signing and installation

Choose your own team in Xcode. The host entitlement requests `com.apple.developer.kernel.increased-memory-limit`; acceptance and effective memory limits depend on the actual provisioned device/profile. Keep signing entitlements consistent when re-signing. The source retains the stable bundle identifier `dev.xzk.bigwalkprobe`; use the same identifier to preserve existing app data, and do not uninstall merely to update.

From the repository root, replace `DEVICE_ID` with the connected device's CoreDevice identifier:

```sh
xcrun devicectl device install app --device DEVICE_ID work/bigwalk-probe/package/BigWalkProbe.app
xcrun devicectl device process launch --device DEVICE_ID dev.xzk.bigwalkprobe
```

The complete verified feature profile requires all staging flags shown above. Default staging leaves EOS experiments disabled and does not apply the quality resource budget. The system-root certificate experiment is intentionally omitted from this release profile.

## Optional diagnostic launches

Run at the main menu and let each test finish before entering a world:

- `--probe-touch-keyboard`: actual Unity held/released state for W, Shift, Ctrl, left/right mouse (approximately 25 seconds).
- `--probe-quality-presets`: six original desktop quality presets with expensive changes, restores previous level at 43 seconds, samples for 90 seconds.
- `--probe-mobile-resolutions`: four adaptive resolutions, then restores the previous short-edge preset.

Ordinary icon launches do not automatically run these tests. Logs and JSON reports are written to the app Documents directory; treat them as private because the original game can log platform identifiers. Public verification is a sanitized summary, not a dump of Documents.

## IPA export

After signature verification, archive the staged app under `Payload/BigWalkProbe.app`. Preserve executable permissions and framework structure. The export is for your own registered devices and remains subject to the signing profile's expiration; packaging cannot extend the profile or add devices. Do not publish the commercial resource bundle or signed IPA in this source repository.
