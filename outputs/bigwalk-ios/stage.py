#!/usr/bin/env python3
"""Stage and sign a diagnostic app. Keeps the Steam installation read-only."""
import os
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WORK = ROOT.parent.parent / "work/bigwalk-probe"
GAME = Path(os.environ.get("BIGWALK_MAC_APP", str(Path.home() / "Library/Application Support/Steam/steamapps/common/Big Walk/Big Walk.app")))

def run(*args):
    subprocess.run([str(a) for a in args], check=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--steam-appid", action="store_true",
                        help="Add Valve's development App ID file; Steam client authentication still applies")
    parser.add_argument("--apple-controller", action="store_true", help="Enable the audited Rewired Apple backend before initialization")
    parser.add_argument("--eos-device-login", action="store_true", help="Persist the original Device ID login path for icon launches")
    parser.add_argument("--eos-device-auth", action="store_true", help="Experimental: route original auth task to Device ID; audited staged binary change")
    parser.add_argument("--eos-network-monitor", action="store_true", help="Experimental: use real EOS state in the existing network monitor")
    parser.add_argument("--eos-menu-auth", action="store_true", help="Experimental: use real EOS login in host/join menu platform checks")
    parser.add_argument("--ios-system-roots", type=Path, help="Experimental: bundle read-only system root candidates; native iOS SecTrust must accept each")
    parser.add_argument("--ios-audio-output", action="store_true", help="Persist the native iOS output adapter after audible sound and map verification")
    parser.add_argument("--mobile-texture-budget", action="store_true", help="Preserve mip limit 2 across all original quality presets")
    args = parser.parse_args()
    if args.eos_network_monitor and not args.eos_device_auth:
        parser.error("--eos-network-monitor requires --eos-device-auth")
    if args.eos_menu_auth and not args.eos_device_auth:
        parser.error("--eos-menu-auth requires --eos-device-auth")
    ready = json.loads((WORK / "unity-ready.json").read_text())
    for name, expected in ready.items():
        if hashlib.sha256(Path(name).read_bytes()).hexdigest() != expected:
            raise RuntimeError("Input changed since preparation: " + name)
    product = WORK / "DerivedData/Build/Products/Debug-iphoneos/BigWalkProbe.app"
    stage = WORK / "package/BigWalkProbe.app"
    if stage.exists():
        shutil.rmtree(stage)
    stage.parent.mkdir(parents=True, exist_ok=True)
    run("cp", "-cR", product, stage)
    run("cp", "-cR", WORK / "Frameworks", stage / "Frameworks")
    if args.ios_system_roots:
        roots_data = args.ios_system_roots.read_bytes()
        roots = plistlib.loads(roots_data)
        if roots.get("domain") != "macOS read-only SystemRootCertificates.keychain" or not roots.get("records"):
            raise ValueError("Only an audited read-only system certificate export is accepted")
        (stage / "SystemRootCandidates.plist").write_bytes(roots_data)
        info_path = stage / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["BigWalkIOSSystemRoots"] = True
        info_path.write_bytes(plistlib.dumps(info))
    contents = stage / "GuestGame/Contents"
    contents.mkdir(parents=True)
    run("cp", "-cR", GAME / "Contents/Resources", contents / "Resources")
    shutil.copy2(GAME / "Contents/Info.plist", contents / "Info.plist")
    (contents / "MacOS").mkdir()
    (contents / "MacOS/Big Walk").write_text("Path marker only; host calls UnityPlayer's exported PlayerMain.\n")
    if args.steam_appid:
        # Documented Steamworks development startup mechanism. It suppresses
        # relaunch, while SteamAPI_Init still requires the real Steam client.
        for directory in (stage, contents / "MacOS", contents / "Resources"):
            (directory / "steam_appid.txt").write_text("1478500\n", encoding="ascii")
    if args.apple_controller:
        python = WORK.parent / "unity-tools/bin/python"
        if not python.exists():
            raise RuntimeError("Install UnityPy 1.25.4 in work/unity-tools first")
        run(python, ROOT / "enable-apple-controller.py", contents / "Resources/Data/data.unity3d",
            "--audit", WORK / "apple-controller-audit.json")
    if args.mobile_texture_budget:
        run(WORK.parent / "unity-tools/bin/python", ROOT / "enable-mobile-texture-budget.py",
            contents / "Resources/Data/data.unity3d", "--audit", WORK / "mobile-texture-budget-audit.json")
    if args.ios_audio_output:
        info_path = stage / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["BigWalkIOSAudioOutput"] = True
        info_path.write_bytes(plistlib.dumps(info))
    if args.eos_device_auth:
        network_args = ["--network-monitor"] if args.eos_network_monitor else []
        if args.eos_menu_auth:
            network_args.append("--menu-auth")
        run("python3", ROOT / "enable-eos-device-auth.py", stage / "Frameworks/GameAssembly.framework/GameAssembly.dylib",
            "--metadata", contents / "Resources/Data/il2cpp_data/Metadata/global-metadata.dat",
            "--prepared-binary", WORK / "Frameworks/GameAssembly.framework/GameAssembly.dylib",
            "--baseline", WORK / "unity-inputs.json", "--audit", WORK / "eos-device-auth-audit.json", *network_args)
    if args.eos_device_login or args.eos_device_auth:
        info_path = stage / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["BigWalkEOSDeviceLogin"] = True
        info["BigWalkEOSDeviceAuth"] = args.eos_device_auth
        info["BigWalkEOSNetworkMonitor"] = args.eos_network_monitor
        info["BigWalkEOSMenuAuth"] = args.eos_menu_auth
        info_path.write_bytes(plistlib.dumps(info))
    for framework in (stage / "Frameworks").glob("*.framework"):
        run("codesign", "--force", "--sign", args.identity, "--timestamp=none", framework)
    entitlements = WORK / "DerivedData/Build/Intermediates.noindex/BigWalkProbe.build/Debug-iphoneos/BigWalkProbe.build/BigWalkProbe.app.xcent"
    run("codesign", "--force", "--sign", args.identity, "--timestamp=none",
        "--entitlements", entitlements, "--generate-entitlement-der", stage)
    run("codesign", "--verify", "--deep", "--strict", stage)
    print(stage)

if __name__ == "__main__":
    main()
