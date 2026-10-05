#!/usr/bin/env python3
"""Build isolated iOS probe inputs. Never modifies the installed Mac game or Stray."""
import os
import hashlib
import json
import plistlib
import re
import shutil
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WORK = ROOT.parent.parent / "work/bigwalk-probe"
GAME = Path(os.environ.get("BIGWALK_MAC_APP", str(Path.home() / "Library/Application Support/Steam/steamapps/common/Big Walk/Big Walk.app")))

def run(args):
    subprocess.run([str(x) for x in args], check=True)

def framework(name):
    directory = WORK / "Frameworks" / (name + ".framework")
    directory.mkdir(parents=True, exist_ok=True)
    executable = name + ".dylib" if name == "GameAssembly" else name
    info = dict(CFBundleExecutable=executable, CFBundleName=name, CFBundleIdentifier="dev.xzk.bigwalkprobe." + name.lower(),
                CFBundlePackageType="FMWK", CFBundleVersion="1", CFBundleShortVersionString="0.1",
                MinimumOSVersion="17.0", CFBundleSupportedPlatforms=["iPhoneOS"])
    (directory / "Info.plist").write_bytes(plistlib.dumps(info))
    return directory / executable

def commands(data):
    offset = 32
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        kind, size = struct.unpack_from("<II", data, offset)
        yield kind, offset, bytearray(data[offset:offset + size])
        offset += size

def text_hash(data):
    for kind, _, cmd in commands(data):
        if kind != 0x19:
            continue
        for i in range(struct.unpack_from("<I", cmd, 64)[0]):
            start = 72 + 80 * i
            if cmd[start:start + 16].split(b"\0")[0] == b"__text":
                size, offset = struct.unpack_from("<QI", cmd, start + 40)
                return hashlib.sha256(data[offset:offset + size]).hexdigest()
    raise ValueError("Missing __text")

def string_command(kind, prefix, value):
    result = bytearray(struct.pack("<II", kind, 0) + prefix + value.encode() + b"\0")
    result.extend(b"\0" * (-len(result) % 8))
    struct.pack_into("<I", result, 4, len(result))
    return result

