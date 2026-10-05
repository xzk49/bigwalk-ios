#!/usr/bin/env python3
"""Experimental iOS auth routing on a staged copy, with exact binary guards."""
import argparse
import hashlib
import json
import struct
from pathlib import Path


def text_section(binary):
    if struct.unpack_from('<II', binary) != (0xfeedfacf, 0x100000c):
        raise ValueError('Expected thin ARM64 Mach-O')
    cursor = 32
    for _ in range(struct.unpack_from('<I', binary, 16)[0]):
        command, length = struct.unpack_from('<II', binary, cursor)
        if command == 0x19:
            for index in range(struct.unpack_from('<I', binary, cursor+64)[0]):
                section = cursor+72+index*80
                if binary[section:section+16].split(b'\0')[0] == b'__text':
                    address, size, offset = struct.unpack_from('<QQI',binary,section+32)
                    return address, size, offset
        cursor += length
    raise ValueError('No __text section')


def section_at(binary, rva):
    cursor=32
    for _ in range(struct.unpack_from('<I',binary,16)[0]):
        command,length=struct.unpack_from('<II',binary,cursor)
        if command==0x19:
            for index in range(struct.unpack_from('<I',binary,cursor+64)[0]):
                s=cursor+72+index*80
                address,size,offset=struct.unpack_from('<QQI',binary,s+32)
                if address<=rva and rva+8<=address+size:
                    return binary[s:s+16].split(b'\0')[0].decode(),address,size,offset
        cursor+=length
    raise ValueError('Entry is not in a file-backed section')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary',type=Path)
    parser.add_argument('--metadata',required=True,type=Path)
    parser.add_argument('--baseline',required=True,type=Path)
    parser.add_argument('--prepared-binary',required=True,type=Path)
    parser.add_argument('--audit',required=True,type=Path)
    parser.add_argument('--network-monitor',action='store_true',help='Use real EOS state in the original network monitor')
    parser.add_argument('--menu-auth',action='store_true',help='Use real EOS login in the host/join menu platform checks')
    args = parser.parse_args()
    # Reject the actual Steam installation; mutate only the dedicated stage.
    if '/package/BigWalkProbe.app/Frameworks/' not in str(args.binary.resolve()):
        raise ValueError('Only the dedicated staged app is accepted')
    metadata = args.metadata.read_bytes()
    h = struct.unpack_from('<95I',metadata)
    if h[:2] != (0xfab11baf,39): raise ValueError('Unrecognized metadata version')
    strings = metadata[h[8]:h[8]+h[9]]
    def name(index): return strings[index:strings.find(b'\0',index)].decode()
    td = h[59]+5503*82
    if name(struct.unpack_from('<I',metadata,td)[0]) != 'EOSProjectManager':
        raise ValueError('Class layout changed')
    methods = {}
    for index in range(h[19]):
        offset = h[17]+index*32
        n,declaring,result_type = struct.unpack_from('<IHH',metadata,offset)
        if declaring == 5503 and name(n) in ('AuthenticateUser','DoDeviceTokenConnect'):
            methods[name(n)] = (result_type,struct.unpack_from('<H',metadata,offset+30)[0])
    if (set(methods) != {'AuthenticateUser','DoDeviceTokenConnect'} or
        methods['AuthenticateUser'][0] != methods['DoDeviceTokenConnect'][0] or
        methods['AuthenticateUser'][1] != 1 or methods['DoDeviceTokenConnect'][1] != 0):
        raise ValueError('Original UniTask signatures changed')
    binary = bytearray(args.binary.read_bytes())
    prepared=args.prepared_binary.read_bytes()
    if bytes(binary)!=prepared:
        raise ValueError('Staged image must exactly match the prepared baseline before routing')
    address,size,file_offset = text_section(binary)
    before_text = bytes(binary[file_offset:file_offset+size])
    expected = json.loads(args.baseline.read_text())['inputs']['GameAssembly']['unchanged_text_sha256']
    if hashlib.sha256(before_text).hexdigest() != expected:
        raise ValueError('GameAssembly text does not match audited original')
    entry,target = 0xa65dcc,0xa66370
    section,code_address,code_size,code_offset=section_at(binary,entry)
    if section!='il2cpp' or section_at(binary,target)[0]!='il2cpp':
        raise ValueError('Expected original generated-code section')
    offset=code_offset+entry-code_address
    before_code=bytes(binary[code_offset:code_offset+code_size])
    original = bytes(binary[offset:offset+8])
    if original != bytes.fromhex('ffc301d1f65704a9'):
        raise ValueError('AuthenticateUser prologue changed')
    # Both factories return the identical UniTask struct. Device ID's native
    # factory uses only the manager; pass null MethodInfo and tail-call it.
    # It creates/logs in via the real SDK and retains the original callback.
    branch = 0x14000000 | (((target-(entry+4))//4)&0x3ffffff)
    replacement = struct.pack('<II',0xaa1f03e1,branch) # mov x1,xzr; b original helper
    binary[offset:offset+8] = replacement
    patches=[dict(rva=hex(entry),offset=offset,original=original.hex(),replacement=replacement.hex(),purpose='Original Device ID auth factory')]
    if args.network_monitor:
        # Preserve the original monitor's polling, debounce and events. Its
        # Steam BLoggedOn query becomes the game's actual SDK login query;
        # there is no constant online result or fabricated Steam identity.
        monitor=0x421e220
        monitor_section,ma,ms,mo=section_at(binary,monitor)
        if monitor_section!='il2cpp':raise ValueError('Monitor code section changed')
        m_offset=mo+monitor-ma
        old=bytes(binary[m_offset:m_offset+8])
        if old!=bytes.fromhex('000080d2197f2d97'):raise ValueError('Original Steam monitor query changed')
        # IsUserAlreadyLogin is an instance method whose audited native body
        # ignores its receiver and queries the SDK singleton's real user.
        # The existing null x0 is retained. Do not call get_IsConnected with
        # a potentially-null manager during early startup.
        provider=0xa65290
        delta=provider-(monitor+4)
        if delta%4 or not -(1<<27)<=delta<(1<<27):raise ValueError('Monitor branch outside ARM64 range')
        new=struct.pack('<II',0xd2800000,0x94000000|((delta//4)&0x3ffffff))
        binary[m_offset:m_offset+8]=new
        patches.append(dict(rva=hex(monitor),offset=m_offset,original=old.hex(),replacement=new.hex(),purpose='Original real SDK login query; original network monitor retained',provider_rva=hex(provider),provider_code_sha256=hashlib.sha256(prepared[provider:0xa65458]).hexdigest()))
    if args.menu_auth:
        # These two menu methods otherwise return immediately when the Steam
        # client is absent, before GenerateGameCode is reached. Replace only
        # their platform-login calls, keeping their own requiresAuth flag and
        # original control flow. No global Steam validity getter is changed.
        for call,owner in ((0xb6e8a4,'HostMenuSelect'),(0xb6e904,'HostMenuSelect'),
                           (0xb70f5c,'JoinMenu'),(0xb70fbc,'JoinMenu')):
            sec,addr,sz,off=section_at(binary,call)
            if sec!='il2cpp':raise ValueError('Menu code section changed')
            at=off+call-addr
            old=bytes(binary[at:at+4])
            original_call=struct.pack('<I',0x94000000|(((0xb43a68-call)//4)&0x3ffffff))
            if old!=original_call:raise ValueError(f'{owner} original Steam validity call changed')
            provider=0xa65290
            delta=provider-call
            if delta%4 or not -(1<<27)<=delta<(1<<27):raise ValueError('Menu branch outside ARM64 range')
            new=struct.pack('<I',0x94000000|((delta//4)&0x3ffffff))
            binary[at:at+4]=new
            patches.append(dict(rva=hex(call),offset=at,original=old.hex(),replacement=new.hex(),
                                purpose=f'{owner}.ValidateRequiresAuth real SDK login query',provider_rva=hex(provider)))
    restored = bytearray(binary)
    for patch in patches:
        old=bytes.fromhex(patch['original'])
        restored[patch['offset']:patch['offset']+len(old)]=old
    if bytes(restored) != args.binary.read_bytes(): raise ValueError('Unexpected extra mutation')
    args.binary.write_bytes(binary)
    args.audit.parent.mkdir(parents=True,exist_ok=True)
    args.audit.write_text(json.dumps(dict(experimental=True,device_verified=False,
        original_source_modified=False,entry_rva=hex(entry),target_rva=hex(target),
        original_bytes=original.hex(),replacement_bytes=replacement.hex(),changed_range_bytes=sum(len(bytes.fromhex(p['original'])) for p in patches),patches=patches,
        network_monitor_uses_real_eos_state=args.network_monitor,
        menu_auth_uses_real_eos_state=args.menu_auth,
        baseline_text_sha256=expected,changed_section=section,
        baseline_generated_code_sha256=hashlib.sha256(before_code).hexdigest(),
        modified_generated_code_sha256=hashlib.sha256(binary[code_offset:code_offset+code_size]).hexdigest(),
        complete_baseline_image_sha256=hashlib.sha256(prepared).hexdigest(),
        metadata_return_type=methods['AuthenticateUser'][0],
        synthesized_credentials=False,synthesized_server_success=False),indent=2)+'\n')
    print(f'Experimental auth routing: {len(patches)} audited ranges; real EOS network monitor={args.network_monitor}; menu auth={args.menu_auth}')


if __name__ == '__main__': main()
