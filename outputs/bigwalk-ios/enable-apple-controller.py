#!/usr/bin/env python3
"""Enable Rewired's Apple backend in two audited objects in a staged copy.

Preserves directory and serialized-file metadata and copies every unaffected
compressed UnityFS block verbatim. Only two decompressed bytes change.
Requires UnityPy 1.25.4 (the isolated work/unity-tools environment).
"""
import argparse
import bisect
import hashlib
import json
import mmap
import os
import struct
from pathlib import Path
import UnityPy
from UnityPy.helpers.CompressionHelper import COMPRESSION_MAP, DECOMPRESSION_MAP
from UnityPy.streams import EndianBinaryReader

EXPECTED_OBJECT_SHA = {'sharedassets1.assets': '16915baffd9ae959974486caf593f77cf525e38da8ec3e8e1b39bf82e34cb0cc', 'level1': 'e94987c3263937f37780199f7b0575b6c78e0e7f36c2000809edf68da4eb3ff9'}
TARGETS = [('sharedassets1.assets', 11998), ('level1', 3867)]

class Bundle:
    def __init__(self, path):
        self.file = path.open('rb')
        self.data = mmap.mmap(self.file.fileno(), 0, access=mmap.ACCESS_READ)
        r = EndianBinaryReader(self.data)
        assert r.read_string_to_null() == 'UnityFS'
        assert r.read_u_int() == 8
        assert r.read_string_to_null() == '5.x.x'
        assert r.read_string_to_null() == '6000.3.17f1'
        self.header_fields = r.Position
        assert r.read_long() == len(self.data)
        compressed, uncompressed, flags = r.read_u_int(), r.read_u_int(), r.read_u_int()
        assert flags == 0x243, 'Unexpected bundle flags'
        self.flags = flags
        r.align_stream(16)
        self.prefix = self.data[:r.Position]
        self.info = bytearray(DECOMPRESSION_MAP[flags & 63](r.read_bytes(compressed), uncompressed))
        b = EndianBinaryReader(self.info)
        assert b.read_bytes(16) == bytes(16), 'Nonzero bundle data hash needs separate handling'
        count = b.read_int()
        self.blocks, self.starts = [], []
        r.align_stream(16)
        compressed_offset, data_offset = r.Position, 0
        for i in range(count):
            u, c, f = b.read_u_int(), b.read_u_int(), b.read_u_short()
            assert f & 63 in (0, 2, 3)
            self.starts.append(data_offset)
            self.blocks.append((data_offset, compressed_offset, u, c, f))
            data_offset += u
            compressed_offset += c
        assert compressed_offset == len(self.data)
        self.nodes = {}
        for i in range(b.read_int()):
            off, size, f, name = b.read_long(), b.read_long(), b.read_u_int(), b.read_string_to_null()
            self.nodes[name] = (off, size, f)
        assert b.Position == len(self.info)
        self.cache = {}

    def block(self, i):
        if i not in self.cache:
            off, start, u, c, f = self.blocks[i]
            raw = DECOMPRESSION_MAP[f & 63](self.data[start:start+c], u)
            assert len(raw) == u
            self.cache[i] = raw
        return self.cache[i]

    def read(self, start, size):
        result = bytearray()
        end = start + size
        i = bisect.bisect_right(self.starts, start)-1
        while start < end:
            off, _, u, _, _ = self.blocks[i]
            amount = min(end-start, off+u-start)
            result += self.block(i)[start-off:start-off+amount]
            start += amount
            i += 1
        return bytes(result)

    def close(self):
        self.data.close()
        self.file.close()


def enable(path, audit_path):
    bundle = Bundle(path)
    patches, objects = {}, []
    for name, path_id in TARGETS:
        node_start, node_size, _ = bundle.nodes[name]
        env = UnityPy.load(bundle.read(node_start, node_size))
        asset = env.assets[0]
        obj = asset.objects[path_id]
        raw = obj.get_raw_data()
        assert obj.class_id == 114 and len(raw) == 46776
        assert hashlib.sha256(raw).hexdigest() == EXPECTED_OBJECT_SHA[name]
        assert struct.unpack_from('<iq', raw, 16) == (1, 1595)
        assert struct.unpack_from('<18I', raw, 140) == (0,0,1,1,240,0,0,0,0,1,1,0,0,0,1,0,0,0)
        absolute = node_start + obj.byte_start + 200
        assert bundle.read(absolute, 4) == bytes(4)
        i = bisect.bisect_right(bundle.starts, absolute)-1
        patches.setdefault(i, {})[absolute-bundle.starts[i]] = 1
        modified = raw[:200]+b'\1'+raw[201:]
        objects.append(dict(file=name, path_id=path_id, object_size=len(raw), field='ConfigVars.platformVars_osxStandalone.useAppleGameController', field_offset=200,
                            before=0, after=1, uncompressed_offset=absolute, original_sha256=hashlib.sha256(raw).hexdigest(), modified_sha256=hashlib.sha256(modified).hexdigest()))
        del env, asset, obj, raw
        bundle.cache.clear()
    replacements = {}
    for i, changes in patches.items():
        original = bundle.block(i)
        changed = bytearray(original)
        for offset, value in changes.items():
            assert changed[offset] == 0
            changed[offset] = value
        assert sum(a!=b for a,b in zip(original, changed)) == len(changes)
        encoded = COMPRESSION_MAP[bundle.blocks[i][4] & 63](changed)
        assert DECOMPRESSION_MAP[bundle.blocks[i][4] & 63](encoded, len(changed)) == changed
        replacements[i] = encoded
        struct.pack_into('>I', bundle.info, 20 + i*10 + 4, len(encoded))
    encoded_info = COMPRESSION_MAP[bundle.flags & 63](bundle.info)
    prefix = bytearray(bundle.prefix)
    data_start = (len(prefix)+len(encoded_info)+15)//16*16
    output_size = data_start + sum(len(replacements[i]) if i in replacements else b[3] for i,b in enumerate(bundle.blocks))
    struct.pack_into('>QIII', prefix, bundle.header_fields, output_size, len(encoded_info), len(bundle.info), bundle.flags)
    before_sha = hashlib.sha256(bundle.data).hexdigest()
    temp = path.with_suffix('.apple-controller.tmp')
    try:
        with temp.open('wb') as out:
            out.write(prefix)
            out.write(encoded_info)
            out.write(bytes(data_start-out.tell()))
            for i, (_, start, _, c, _) in enumerate(bundle.blocks):
                out.write(replacements[i] if i in replacements else bundle.data[start:start+c])
            assert out.tell() == output_size
        check = Bundle(temp)
        try:
            for i,b in enumerate(bundle.blocks):
                cb = check.blocks[i]
                assert b[0] == cb[0] and b[2] == cb[2] and b[4] == cb[4]
                if i not in replacements:
                    assert bundle.data[b[1]:b[1]+b[3]] == check.data[cb[1]:cb[1]+cb[3]]
                else:
                    old, new = bundle.block(i), check.block(i)
                    diffs = {j: v for j,(a,v) in enumerate(zip(old,new)) if a!=v}
                    assert diffs == patches[i]
            assert bundle.nodes == check.nodes
            after_sha = hashlib.sha256(check.data).hexdigest()
        finally:
            check.close()
        bundle.close()
        os.replace(temp, path)
    except BaseException:
        temp.unlink(missing_ok=True)
        raise
    report = dict(source_sha256=before_sha, staged_sha256=after_sha, original_text_modified=False,
                  modified_uncompressed_bytes=2, affected_blocks=len(patches), unchanged_compressed_blocks=len(bundle.blocks)-len(patches), directory_unchanged=True, serialized_file_metadata_unchanged=True, objects=objects)
    audit_path.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))

if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('staged_bundle', type=Path)
    p.add_argument('--audit', required=True, type=Path)
    args=p.parse_args()
    # Never write to the user's Steam installation.
    work=(Path(__file__).resolve().parents[2]/'work').resolve()
    path=args.staged_bundle.resolve()
    if not path.is_relative_to(work):
        p.error('Only a staged copy under this workspace/work is accepted')
    enable(path,args.audit)
