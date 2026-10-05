#!/usr/bin/env python3
"""Prepare the current game's engine and audited Stray bridge sources on copies."""
import importlib.util
import json
import hashlib
import re
import shutil
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("probe_inputs", ROOT / "prepare-ios.py")
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
WORK, GAME = p.WORK, p.GAME
SDK = Path(subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip())
BRIDGES = WORK / "bridges"
BRIDGES.mkdir(parents=True, exist_ok=True)
PROVENANCE = {}
for source in (ROOT / "compat").iterdir():
    if source.suffix in (".m", ".h", ".inc", ".s"):
        shutil.copy2(source, BRIDGES / source.name)
        PROVENANCE[source.name] = hashlib.sha256(source.read_bytes()).hexdigest()
keyboard = ROOT / "compat/StrayUSKeyboard.inc"
shutil.copy2(keyboard, BRIDGES / keyboard.name)
PROVENANCE["generated-US-keyboard"] = hashlib.sha256(keyboard.read_bytes()).hexdigest()

def flags(name):
    return ["xcrun", "clang", "-target", "arm64-apple-ios17.0", "-isysroot", SDK, "-dynamiclib", "-fobjc-arc",
            "-Wno-deprecated-declarations", "-g", "-O0", "-I", BRIDGES, "-framework", "Foundation",
            "-framework", "UIKit", "-framework", "QuartzCore", "-install_name", f"@rpath/{name}.framework/{name}"]

def reexport_native(name):
    return ["-Wl,-reexport_framework," + name]

def reexport_guest(name):
    return ["-Wl,-reexport_library," + str(WORK / f"Frameworks/{name}.framework/{name}")]

def exports(path):
    output = subprocess.check_output(["nm", "-gU", str(path)], text=True)
    return {line.split()[-1] for line in output.splitlines() if line.strip()}

def sdk_exports(name):
    path = SDK / f"System/Library/Frameworks/{name}.framework/{name}.tbd"
    if name == "libSystem":
        path = SDK / "usr/lib/libSystem.B.tbd"
    if not path.exists():
        return set()
    text = path.read_text()
    result = set(re.findall(r"_[A-Za-z0-9_$]+", text))
    for imports in IMPORTS.values():
        for symbol in imports:
            if symbol.startswith(("_OBJC_CLASS_$_", "_OBJC_METACLASS_$_")):
                classname = symbol.split("$_")[1]
                if re.search(r"\b" + re.escape(classname) + r"\b", text):
                    result.add(symbol)
    return result

def original_imports():
    raw = subprocess.check_output(["nm", "-arch", "arm64", "-m", str(GAME / "Contents/Frameworks/UnityPlayer.dylib")], text=True)
    result = {}
    for line in raw.splitlines():
        match = re.search(r"\(undefined\) external (\S+) \(from (\S+)\)", line)
        if match:
            result.setdefault(match[2], set()).add(match[1])
    return result

IMPORTS = original_imports()
TRAPS = {}

def build(name, category, sources, extra, native=(), also=()):
    target = p.framework(name)
    if not sources:
        empty = WORK / (name + "-facade.c")
        empty.write_text("void ProbeFacadeMarker_" + name + "(void) {}\n")
        sources = [empty]
    command = flags(name) + sources + extra
    p.run(command + ["-o", target])
    supported = exports(target)
    for n in native:
        supported |= sdk_exports(n)
    for n in also:
        supported |= exports(WORK / f"Frameworks/{n}.framework/{n}")
    missing = sorted(IMPORTS.get(category, set()) - supported)
    if missing:
        generated = WORK / (name + "-unimplemented.m")
        lines = ['#import <Foundation/Foundation.h>', '#include <stdio.h>', '#include <stdlib.h>']
        for i, symbol in enumerate(missing):
            if symbol.startswith("_OBJC_"):
                raise RuntimeError("Missing Objective-C ABI class: " + symbol)
            if symbol.startswith(("_k", "_NS")) and symbol != "_NSApplicationMain":
                lines.append(f'const CFStringRef TrapConstant{i} __asm__("{symbol}") = CFSTR("{symbol[1:]}");')
            else:
                lines.append(f'void Trap{i}(void) __asm__("{symbol}");')
                lines.append(f'void Trap{i}(void) {{ fprintf(stderr,"UNITYPROBE NEEDS_IMPLEMENTATION {category} {symbol}\\n"); abort(); }}')
        generated.write_text("\n".join(lines) + "\n")
        p.run(command + [generated, "-o", target])
        TRAPS[category] = missing
    return target

def retarget(source, name, routes):
    target = p.framework(name)
    executable = target.name
    p.run(["xcrun", "lipo", source, "-thin", "arm64", "-output", target])
    p.run(["codesign", "--remove-signature", target])
    data = bytearray(target.read_bytes())
    before = p.text_hash(data)
    updated = []
    changes = []
    for kind, _, cmd in p.commands(data):
        if kind == 0x32:
            assert struct.unpack_from("<I", cmd, 8)[0] == 1
            struct.pack_into("<III", cmd, 8, 2, 17 << 16, 26 << 16)
        elif kind == 0x24:
            struct.pack_into("<III", cmd, 0, 0x25, len(cmd), 17 << 16)
            struct.pack_into("<I", cmd, 12, 26 << 16)
        elif kind == 0xD:
            cmd = p.string_command(kind, cmd[8:24], f"@rpath/{name}.framework/{executable}")
        elif kind in (0xC, 0x80000018, 0x8000001F):
            offset = struct.unpack_from("<I", cmd, 8)[0]
            old = cmd[offset:].split(b"\0")[0].decode()
            match = re.search(r"/(\w+)\.framework/", old)
            replacement = routes.get(match[1]) if match else None
            new = (f"@rpath/{replacement}.framework/{replacement}" if replacement
                   else re.sub(r"/Versions/[^/]+/", "/", old))
            cmd = p.string_command(kind, cmd[8:24], new)
            changes.append([old, new])
        updated.append(cmd)
    if name == "Burst":
        # Import-free Mac Burst image is valid on macOS; iOS dyld requires a load dependency.
        assert not any(kind in (0xC, 0x80000018) for kind, _, _ in p.commands(data))
        updated.append(p.string_command(0xC, struct.pack("<IIII", 24, 0, 0x10000, 0x10000), "/usr/lib/libSystem.B.dylib"))
    table = b"".join(updated)
    old_size = struct.unpack_from("<I", data, 20)[0]
    first = min(struct.unpack_from("<I", cmd, 72 + 80*i + 48)[0]
                for kind, _, cmd in p.commands(data) if kind == 0x19
                for i in range(struct.unpack_from("<I", cmd, 64)[0])
                if struct.unpack_from("<I", cmd, 72 + 80*i + 48)[0])
    assert 32 + len(table) <= first
    length = max(old_size, len(table))
    data[32:32+length] = table.ljust(length, b"\0")
    struct.pack_into("<II", data, 16, len(updated), len(table))
    assert p.text_hash(data) == before
    target.write_bytes(data)
    p.run(["xcrun", "install_name_tool", "-change", "/usr/lib/libSystem.B.dylib",
           "@rpath/CompatSystem.framework/CompatSystem", target])
    assert p.text_hash(target.read_bytes()) == before
    p.run(["xcrun", "dyld_info", "-validate_only", target])
    return dict(source=str(source), original_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                unchanged_text_sha256=before, dependency_changes=changes)

def main():
    audit = json.loads((ROOT / "source-audit.json").read_text())
    if __import__("plistlib").loads((GAME / "Contents/Info.plist").read_bytes()).get("CFBundleVersion") != audit["build"]:
        raise RuntimeError("Game build differs from the fixed source audit")
    for binary in audit["binaries"]:
        source = GAME / binary["path"]
        if any(binary.get("encryption_ids", [])) or "arm64" not in binary["architectures"]:
            raise RuntimeError("Only audited, unencrypted ARM64 inputs are accepted")
        if hashlib.sha256(source.read_bytes()).hexdigest() != binary["sha256"]:
            raise RuntimeError("Game binary changed after audit: " + str(source))
    ready = WORK / "unity-ready.json"
    ready.unlink(missing_ok=True)
    src = lambda n: BRIDGES / n
    build("CompatAppKit", "AppKit", [src("AppKitBridge.m"), src("AppKitServices.m"), src("TouchGamepad.m"), src("TouchKeyboard.m"), src("MobileResolution.m"), ROOT / "UnityExtras.m", ROOT / "RunningApplicationBridge.m", ROOT / "UnityQualityProfile.m", ROOT / "BigWalkFrameCapture.m", ROOT / "BigWalkTextEntry.m", ROOT / "BigWalkProfilerGuard.m", ROOT / "BigWalkEOSLogin.m", ROOT / "BigWalkInputInspection.m", ROOT / "BigWalkAudioDiagnostics.m"],
          ["-framework", "Metal", "-framework", "ImageIO", "-framework", "CoreGraphics", "-framework", "GameController",
           "-Wl,-alias,_OBJC_CLASS_$_StrayFont,_OBJC_CLASS_$_NSFont", "-Wl,-alias,_OBJC_METACLASS_$_StrayFont,_OBJC_METACLASS_$_NSFont",
           "-Wl,-alias,_OBJC_CLASS_$_StrayColor,_OBJC_CLASS_$_NSColor", "-Wl,-alias,_OBJC_METACLASS_$_StrayColor,_OBJC_METACLASS_$_NSColor"])
    build("CompatFoundation", "Foundation", [ROOT / "UnityAppleEvent.m", src("GameBundleBridge.m")],
          ["-Wl,-alias,_OBJC_CLASS_$_StrayGameBundle,_OBJC_CLASS_$_NSBundle"] + reexport_native("Foundation"), native=("Foundation",))
    build("CompatCocoa", "Cocoa", [], reexport_guest("CompatFoundation") + reexport_guest("CompatAppKit"), also=("CompatFoundation", "CompatAppKit"), native=("Foundation",))
    build("CompatCarbon", "Carbon", [ROOT / "KeyboardBridge.m", ROOT / "DesktopExtras.m"], ["-DBUILD_CARBON=1"])
    build("CompatCoreServices", "CoreServices", [ROOT / "CoreServicesExtras.c"],
          reexport_guest("CompatCarbon") + ["-Wl,-reexport_library," + str(SDK / "usr/lib/libSystem.tbd")], also=("CompatCarbon",), native=("libSystem",))
    build("CompatCoreGraphics", "CoreGraphics", [src("DisplayBridge.m"), src("MetalBufferStorage.m"), ROOT / "CoreGraphicsExtras.m", ROOT / "UnityMetalStorage.m"],
          ["-framework", "Metal"] + reexport_native("CoreGraphics"), native=("CoreGraphics",))
    build("CompatCoreVideo", "CoreVideo", [src("DisplayLinkBridge.m"), ROOT / "DesktopExtras.m"],
          ["-DBUILD_COREVIDEO=1"] + reexport_native("CoreVideo"), native=("CoreVideo",))
    build("CompatIOKit", "IOKit", [src("RegistryBridge.m"), ROOT / "IOKitExtras.c"], reexport_native("IOKit"), native=("IOKit",))
    build("CompatCoreAudio", "CoreAudio", [ROOT / "BigWalkAudioHAL.m"], ["-framework", "AVFAudio", "-framework", "AudioToolbox"] + reexport_native("CoreAudio"), native=("CoreAudio",))
    build("CompatAudioUnit", "AudioUnit", [ROOT / "BigWalkAudioUnit.m"], ["-framework", "AVFAudio"] + reexport_native("AudioToolbox"), native=("AudioToolbox",))
    build("CompatSecurity", "Security", [ROOT / "BigWalkTrustSettings.m"], reexport_native("Security"), native=("Security",))
    build("CompatAVF", "AVFoundation", [], reexport_native("AVFoundation") + reexport_native("AVFAudio"), native=("AVFoundation", "AVFAudio"))
    build("CompatOpenGL", "OpenGL", [], [])
    build("CompatQuartz", "Quartz", [], reexport_native("Foundation"), native=("Foundation",))
    build("CompatSecurityFoundation", "SecurityFoundation", [], reexport_native("Foundation"), native=("Foundation",))
    build("CompatSystem", "libSystem", [ROOT / "GuestSystem.m"],
          ["-Wl,-reexport_library," + str(SDK / "usr/lib/libSystem.tbd")], native=("libSystem",))
    build("CompatSystemConfiguration", "SystemConfiguration", [ROOT / "SystemConfigurationBridge.m"],
          reexport_native("SystemConfiguration"), native=("SystemConfiguration",))
    routes = {n: "Compat" + n for n in ("AppKit", "Foundation", "Cocoa", "Carbon", "CoreServices", "CoreGraphics", "CoreVideo", "IOKit", "CoreAudio", "AudioUnit", "Security", "OpenGL", "Quartz", "SecurityFoundation")}
    routes["AVFoundation"] = "CompatAVF"
    routes["SystemConfiguration"] = "CompatSystemConfiguration"
    inputs = {"UnityPlayer": retarget(GAME / "Contents/Frameworks/UnityPlayer.dylib", "UnityPlayer", routes)}
    # Route only Unity's libSystem ordinal to the scoped bundle/library facade.
    target = WORK / "Frameworks/UnityPlayer.framework/UnityPlayer"
    p.run(["xcrun", "install_name_tool", "-change", "/usr/lib/libSystem.B.dylib",
           "@rpath/CompatSystem.framework/CompatSystem", target])
    assert p.text_hash(target.read_bytes()) == inputs["UnityPlayer"]["unchanged_text_sha256"]
    for name, relative in (("GameAssembly", "Contents/Frameworks/GameAssembly.dylib"),
                           ("SteamAPI", "Contents/PlugIns/steam_api.bundle/Contents/MacOS/libsteam_api.dylib"),
                           ("Burst", "Contents/PlugIns/lib_burst_generated.bundle"),
                           ("EOSSDK", "Contents/PlugIns/libEOSSDK-Mac-Shipping.dylib"),
                           ("Dissonance", "Contents/PlugIns/AudioPluginDissonance.bundle"),
                           ("Microphone", "Contents/PlugIns/MicrophoneUtility_macos.dylib"),
                           ("Rewired", "Contents/PlugIns/Rewired_MacOS.bundle"),
                           ("Opus", "Contents/PlugIns/opus.bundle")):
        source = GAME / relative
        inputs[name] = retarget(source, name, routes)
    manifest = dict(game_info=__import__("plistlib").loads((GAME / "Contents/Info.plist").read_bytes()),
                    inputs=inputs, bridge_source_sha256=PROVENANCE, unimplemented_symbols=TRAPS)
    (WORK / "unity-inputs.json").write_text(json.dumps(manifest, indent=2, default=str) + "\n")
    outputs = list((WORK / "Frameworks").glob("*.framework/*"))
    sources = list(ROOT.glob("*.m")) + list(ROOT.glob("*.c")) + [Path(__file__), ROOT / "prepare-ios.py", ROOT / "enable-apple-controller.py", ROOT / "stage.py"]
    sources += [path for path in (ROOT / "compat").iterdir() if path.suffix in (".m", ".h", ".inc", ".s")]
    sources += [ROOT / "Info.plist", ROOT / "BigWalkProbe.entitlements", ROOT / "BigWalkProbe.xcodeproj/project.pbxproj", ROOT / "enable-eos-device-auth.py"]
    ready.write_text(json.dumps({str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                                for path in outputs + sources if path.is_file()}, indent=2) + "\n")

if __name__ == "__main__":
    main()
