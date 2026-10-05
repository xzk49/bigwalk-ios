#!/usr/bin/env python3
"""Preserve the verified mobile mip budget in every original quality preset."""
import argparse,bisect,copy,hashlib,importlib.util,json,os,struct
from pathlib import Path
import UnityPy
spec=importlib.util.spec_from_file_location('controller_bundle',Path(__file__).with_name('enable-apple-controller.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
EXPECTED='df6440d940f08d8a89284ae67b92319411adc9e5aa5413b08c1afd2cdf6bc306'

def enable(path,audit_path):
 b=m.Bundle(path);start,size,_=b.nodes['globalgamemanagers'];env=UnityPy.load(b.read(start,size));obj=env.assets[0].objects[12];raw=obj.get_raw_data()
 assert obj.class_id==47 and len(raw)==1640 and hashlib.sha256(raw).hexdigest()==EXPECTED
 old=obj.read_typetree();new=copy.deepcopy(old);presets=[]
 for v in new['m_QualitySettings']:
  before=v['globalTextureMipmapLimit'];v['globalTextureMipmapLimit']=max(before,2);presets.append(dict(name=v['name'],before=before,after=v['globalTextureMipmapLimit']))
 changed=obj.save_typetree(new);assert len(raw)==len(changed)
 diffs={i:c for i,(a,c) in enumerate(zip(raw,changed)) if a!=c}
 assert diffs=={72:2,272:2,476:2,676:2,884:2,1088:2,1292:2,1492:2}
 patches={}
 for offset,value in diffs.items():
  absolute=start+obj.byte_start+offset;assert b.read(absolute,1)==raw[offset:offset+1]
  index=bisect.bisect_right(b.starts,absolute)-1;patches.setdefault(index,{})[absolute-b.starts[index]]=value
 replacements={}
 for i,changes in patches.items():
  original=b.block(i);altered=bytearray(original)
  for offset,value in changes.items():altered[offset]=value
  assert {j:c for j,(a,c) in enumerate(zip(original,altered)) if a!=c}==changes
  encoded=m.COMPRESSION_MAP[b.blocks[i][4]&63](altered);assert m.DECOMPRESSION_MAP[b.blocks[i][4]&63](encoded,len(altered))==altered
  replacements[i]=encoded;struct.pack_into('>I',b.info,20+i*10+4,len(encoded))
 encoded_info=m.COMPRESSION_MAP[b.flags&63](b.info);prefix=bytearray(b.prefix);data_start=(len(prefix)+len(encoded_info)+15)//16*16
 output_size=data_start+sum(len(replacements[i]) if i in replacements else v[3] for i,v in enumerate(b.blocks));struct.pack_into('>QIII',prefix,b.header_fields,output_size,len(encoded_info),len(b.info),b.flags)
 before_sha=hashlib.sha256(b.data).hexdigest();temp=path.with_suffix('.mobile-mip.tmp')
 try:
  with temp.open('wb') as out:
   out.write(prefix);out.write(encoded_info);out.write(bytes(data_start-out.tell()))
   for i,(_,off,_,count,_) in enumerate(b.blocks):out.write(replacements[i] if i in replacements else b.data[off:off+count])
   assert out.tell()==output_size
  check=m.Bundle(temp)
  try:
   assert b.nodes==check.nodes
   for i,v in enumerate(b.blocks):
    cv=check.blocks[i];assert (v[0],v[2],v[4])==(cv[0],cv[2],cv[4])
    if i not in replacements:assert b.data[v[1]:v[1]+v[3]]==check.data[cv[1]:cv[1]+cv[3]]
    else:assert {j:c for j,(a,c) in enumerate(zip(b.block(i),check.block(i))) if a!=c}==patches[i]
   ce=UnityPy.load(check.read(start,size));result=ce.assets[0].objects[12].read_typetree();assert result==new
   after_sha=hashlib.sha256(check.data).hexdigest()
  finally:check.close()
  report=dict(passed=True,source_sha256=before_sha,modified_sha256=after_sha,object_original_sha256=EXPECTED,object_modified_sha256=hashlib.sha256(changed).hexdigest(),object_size=1640,class_id=47,path_id=12,node='globalgamemanagers',field='m_QualitySettings[].globalTextureMipmapLimit',modified_uncompressed_bytes=len(diffs),field_offsets=list(diffs),presets=presets,directory_unchanged=True,serialized_file_metadata_unchanged=True,unaffected_compressed_blocks_identical=True,affected_blocks=len(patches),unaffected_compressed_blocks=len(b.blocks)-len(patches))
  b.close();os.replace(temp,path);audit_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('Passed: eight preset mip fields; all unrelated serialized bytes and compressed blocks unchanged.')
 except BaseException:temp.unlink(missing_ok=True);raise

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('staged_bundle',type=Path);p.add_argument('--audit',required=True,type=Path);a=p.parse_args();work=Path(__file__).resolve().parents[2]/'work';path=a.staged_bundle.resolve()
 if not path.is_relative_to(work.resolve()):p.error('Only independent copies under workspace/work may be changed')
 enable(path,a.audit)
