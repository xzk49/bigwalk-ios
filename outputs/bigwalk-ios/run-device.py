#!/usr/bin/env python3
"""Install and run only the dedicated BIG WALK test app; preserve its data."""
import argparse
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WORK = ROOT.parent.parent / "work/bigwalk-probe"
BUNDLE = "dev.xzk.bigwalkprobe"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--round", required=True)
    parser.add_argument("--load-only", action="store_true")
    parser.add_argument("--texture-mip-limit", type=int, choices=range(4))
    parser.add_argument("--capture-frame", action="store_true")
    parser.add_argument("--probe-continue", action="store_true")
    parser.add_argument("--probe-keyboard", action="store_true")
    parser.add_argument("--eos-device-login", action="store_true")
    parser.add_argument("--inspect-input", action="store_true")
    parser.add_argument("--audio-output-bridge", action="store_true", help="Opt-in audio experiment for this process only; icon launches retain the local-map baseline")
    args = parser.parse_args()
    if not args.round.replace("-", "").isalnum():
        parser.error("round must contain letters, digits or hyphens")
    output = WORK / "device-results" / args.round
    output.mkdir(parents=True, exist_ok=True)
    def run(arguments, name):
        with (output / (name + ".log")).open("w") as log:
            subprocess.run(["xcrun", "devicectl", *map(str, arguments)], check=True, stdout=log, stderr=subprocess.STDOUT)
    run(["device", "install", "app", "--device", args.device,
         WORK / "package/BigWalkProbe.app", "--json-output", output / "install.json"], "install")
    command = ["device", "process", "launch", "--device", args.device, "--terminate-existing",
               "--json-output", output / "launch.json", BUNDLE]
    if args.load_only:
        command.append("--load-only")
    if args.texture_mip_limit is not None:
        command.extend(["--texture-mip-limit", str(args.texture_mip_limit)])
    if args.capture_frame:
        command.append("--capture-frame")
    if args.probe_continue:
        command.append("--probe-continue")
    if args.probe_keyboard:
        command.append("--probe-keyboard")
    if args.eos_device_login:
        command.append("--eos-device-login")
    if args.audio_output_bridge:
        command.append("--audio-output-bridge")
    if args.inspect_input:
        command.append("--inspect-input")
    run(command, "launch")
    time.sleep(8)
    run(["device", "copy", "from", "--device", args.device, "--domain-type", "appDataContainer",
         "--domain-identifier", BUNDLE, "--source", "Documents", "--destination", output / "Documents"], "fetch")
    print(output)
    for name in ("runtime-console.log", "Player.log"):
        path = output / "Documents" / name
        if path.exists():
            print("\n" + name + "\n" + "\n".join(path.read_text(errors="replace").splitlines()[-16:]))

if __name__ == "__main__":
    main()
