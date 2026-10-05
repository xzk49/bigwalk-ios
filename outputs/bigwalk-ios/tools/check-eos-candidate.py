#!/usr/bin/env python3
"""Check a signed EOS candidate against its prepared image and range audit."""
import argparse
import hashlib
import json
import plistlib
import struct
from pathlib import Path


def sections(data):
    cursor = 32
    result = {}
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, length = struct.unpack_from('<II', data, cursor)
        if command == 0x19:
            for index in range(struct.unpack_from('<I', data, cursor + 64)[0]):
                section = cursor + 72 + index * 80
                name = data[section:section + 32]
                size, offset = struct.unpack_from('<QI', data, section + 40)
                kind = struct.unpack_from('<I', data, section + 64)[0] & 255
                if kind not in (1, 12, 18):  # zero-fill sections have no file data
                    result[name] = data[offset:offset + size]
        cursor += length
    return result


def branch_target(word, address):
    if word >> 26 not in (5, 37):
        raise ValueError('Expected immediate ARM64 B/BL')
    delta = word & 0x3ffffff
    if delta & (1 << 25):
        delta -= 1 << 26
    return address + delta * 4


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--prepared', required=True, type=Path)
    parser.add_argument('--audit', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    candidate = (args.app / 'Frameworks/GameAssembly.framework/GameAssembly.dylib').read_bytes()
    baseline = args.prepared.read_bytes()
    audit = json.loads(args.audit.read_text())
    assert hashlib.sha256(baseline).hexdigest() == audit['complete_baseline_image_sha256']
    restored = bytearray(candidate)
    targets = []
    for patch in audit['patches']:
        offset = patch['offset']
        original = bytes.fromhex(patch['original'])
        replacement = bytes.fromhex(patch['replacement'])
        assert candidate[offset:offset + len(original)] == replacement
        assert baseline[offset:offset + len(original)] == original
        restored[offset:offset + len(original)] = original
        address = int(patch['rva'], 16)
        branch_offset = 4 if len(replacement) == 8 else 0
        word = struct.unpack_from('<I', replacement, branch_offset)[0]
        target = branch_target(word, address + branch_offset)
        expected = int(patch.get('provider_rva', audit['target_rva']), 16)
        assert target == expected
        if 'ValidateRequiresAuth' in patch['purpose']:
            assert baseline[offset - 4:offset] == bytes.fromhex('000080d2')
        targets.append({'rva': hex(address), 'target': hex(target), 'purpose': patch['purpose']})
    # Signing replaces the code signature blob/header size; every file-backed
    # section must still match once the explicitly audited ranges are restored.
    assert sections(bytes(restored)) == sections(baseline)
    profile = plistlib.loads((args.app / 'Info.plist').read_bytes())
    assert profile['BigWalkIOSAudioOutput'] and profile['BigWalkEOSDeviceAuth']
    assert profile.get('BigWalkEOSNetworkMonitor', False) == audit['network_monitor_uses_real_eos_state']
    assert profile.get('BigWalkEOSMenuAuth', False) == audit.get('menu_auth_uses_real_eos_state', False)
    args.output.write_text(json.dumps(dict(passed=True, device_verified=False,
        restored_file_backed_sections_match=True, targets=targets,
        candidate_sha256=hashlib.sha256(candidate).hexdigest()), indent=2) + '\n')
    print(f'Passed: {len(targets)} guarded ranges, all restored sections and profile flags match.')


if __name__ == '__main__':
    main()
