#!/usr/bin/env python3
"""Audit guest imports routed through desktop facades; never add stubs."""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT.parent.parent / "work/bigwalk-probe"
SDK = Path(subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip())
NATIVE = {
    "Foundation": ("Foundation",), "Cocoa": ("Foundation",),
    "CoreServices": ("libSystem",), "CoreGraphics": ("CoreGraphics",),
    "CoreVideo": ("CoreVideo",), "IOKit": ("IOKit",), "CoreAudio": ("CoreAudio",),
    "AudioUnit": ("AudioToolbox",), "Security": ("Security",),
    "AVFoundation": ("AVFoundation", "AVFAudio"), "Quartz": ("Foundation",),
    "SecurityFoundation": ("Foundation",), "libSystem": ("libSystem",),
    "SystemConfiguration": ("SystemConfiguration",),
}

def exported(name):
    path = WORK / f"Frameworks/{name}.framework/{name}"
    lines = subprocess.check_output(["nm", "-gU", str(path)], text=True).splitlines()
    return {line.split()[-1] for line in lines if line.strip()}

def main():
    inputs = json.loads((WORK / "unity-inputs.json").read_text())
    cache = {}
    def supports(category, symbol):
        if category not in cache:
            bridge = "CompatAVF" if category == "AVFoundation" else "CompatSystem" if category == "libSystem" else "Compat" + category
            available = exported(bridge)
            if category == "Cocoa": available |= exported("CompatAppKit") | exported("CompatFoundation")
            if category == "CoreServices": available |= exported("CompatCarbon")
            texts = []
            for name in NATIVE.get(category, ()):
                path = SDK / "usr/lib/libSystem.B.tbd" if name == "libSystem" else SDK / f"System/Library/Frameworks/{name}.framework/{name}.tbd"
                texts.append(path.read_text())
            combined = "\n".join(texts)
            available |= set(re.findall(r"_[A-Za-z0-9_$]+", combined))
            # Mach-O's lazy binder is exported without the usual leading '_'.
            if re.search(r"\bdyld_stub_binder\b", combined): available.add("dyld_stub_binder")
            cache[category] = available, combined
        available, combined = cache[category]
        if symbol in available: return True
        if symbol.startswith(("_OBJC_CLASS_$_", "_OBJC_METACLASS_$_")):
            return bool(re.search(r"\b" + re.escape(symbol.split("$_")[1]) + r"\b", combined))
        return False

    categories = set(NATIVE) | {"AppKit", "Carbon", "OpenGL"}
    report = {}
    for name, item in inputs["inputs"].items():
        raw = subprocess.check_output(["nm", "-arch", "arm64", "-m", item["source"]], text=True)
        missing, traps = {}, {}
        for line in raw.splitlines():
            match = re.search(r"\(undefined\).*?external (\S+) \(from (\S+)\)", line)
            if not match: continue
            symbol, category = match.groups()
            if category not in categories: continue
            if not supports(category, symbol): missing.setdefault(category, []).append(symbol)
            elif symbol in inputs["unimplemented_symbols"].get(category, ()):
                traps.setdefault(category, []).append(symbol)
        report[name] = {"unresolved_desktop_imports": missing, "diagnostic_only_imports": traps}
    output = ROOT / "desktop-import-audit.json"
    output.write_text(json.dumps({"scope": "Desktop facade imports only; SDK stub coverage is static and does not prove runtime behavior", "images": report}, indent=2) + "\n")
    for name, item in report.items():
        print(name, "unresolved:", sum(map(len, item["unresolved_desktop_imports"].values())),
              "diagnostic-only:", sum(map(len, item["diagnostic_only_imports"].values())))

if __name__ == "__main__": main()
