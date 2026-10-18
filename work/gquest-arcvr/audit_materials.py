"""Read-only private material/model audit; writes evidence outside content/."""
from pathlib import Path
import hashlib, json, math, re, struct, zlib
HERE=Path(__file__).resolve().parent
CONTENT=HERE/'content'
SOURCE=HERE.parent/'arcvr-anniversary'
REL='materials/models/weapons/arcticvr/p38/v_p38.vmt'
sha=lambda b:hashlib.sha256(b).hexdigest()
original=(SOURCE/REL).read_bytes(); adapted=(CONTENT/REL).read_bytes()
assert sha(original)=='ea89a384fe7dd01e058e3fb9f939b3c75eebd385edbd66c9238232d7efc105b3'
assert original.endswith(b'}\n}\n') and adapted==original[:-2]
patch={'path':REL,'source_commit':'0d8d5bed01c77ad1550097689dc0d1e6fc035385',
       'original_bytes':len(original),'original_sha256':sha(original),
       'adapted_bytes':len(adapted),'adapted_sha256':sha(adapted),
       'change':'Remove only final unmatched closing brace and its newline. Source checkout is unchanged.',
       'reason':'Native runtime KeyValues parser reported missing { for this exact VMT.',
       'runtime_fix_verified':False}
(HERE/'material_patch.json').write_text(json.dumps(patch,indent=2)+'\n')

class VPK:
    def __init__(self,path):
        self.path=Path(path);self.index={}
        with self.path.open('rb') as f:
            sig,version,size=struct.unpack('<III',f.read(12))
            assert sig==0x55aa1234 and version in (1,2)
            self.header=12 if version==1 else 28
            f.seek(self.header);tree=f.read(size)
        self.data_start=self.header+size
        off=0
        def string():
            nonlocal off
            end=tree.index(0,off);value=tree[off:end].decode();off=end+1;return value
        while (ext:=string()):
            while (directory:=string()):
                while (name:=string()):
                    crc,preload,archive,entry,length,term=struct.unpack_from('<IHHIIH',tree,off);off+=18
                    assert term==0xffff
                    prefix=tree[off:off+preload];off+=preload
                    rel=(('' if directory==' ' else directory+'/')+name+('.'+ext if ext!=' ' else '')).lower()
                    self.index[rel]=(crc,archive,entry,length,prefix)
    def read(self,rel):
        crc,archive,offset,length,prefix=self.index[rel.lower()]
        source=self.path if archive==0x7fff else self.path.with_name(self.path.name[:-8]+'_%03d.vpk'%archive)
        if length:
            with source.open('rb') as f:
                f.seek(offset+(self.data_start if archive==0x7fff else 0));data=prefix+f.read(length)
        else:data=prefix
        assert len(data)==len(prefix)+length and zlib.crc32(data)&0xffffffff==crc,(source,rel)
        return data
archives=[VPK(path) for path in dict.fromkeys(r['archive'] for r in json.loads((HERE.parent/'gquest-arcvr-stock-dependencies.json').read_text()))]
private={str(p.relative_to(CONTENT)).lower():p for p in CONTENT.rglob('*') if p.is_file()}
def locate(rel):
    rel=rel.replace('\\','/').lower()
    if rel in private:return {'location':'private content','path':rel,'bytes':private[rel].stat().st_size},private[rel].read_bytes()
    for archive in archives:
        if rel in archive.index:
            data=archive.read(rel)
            return {'location':str(archive.path),'path':rel,'bytes':len(data)},data
    return None,None

def parse_vmt(raw):
    text=raw.decode('utf-8-sig');text=re.sub(r'//[^\n]*','',text)
    tokens=[m[1] if m[1] is not None else m[2] or m[3] for m in re.finditer(r'"([^"\n]*)"|([{}])|([^\s{}"]+)',text)]
    i=0
    def value():
        nonlocal i
        assert i<len(tokens)
        token=tokens[i];i+=1
        assert token!='}'
        return block() if token=='{' else token
    def block():
        nonlocal i
        pairs=[]
        while i<len(tokens) and tokens[i]!='}':pairs.append((value(),value()))
        assert i<len(tokens) and tokens[i]=='}';i+=1;return pairs
    shader=value();body=value();assert isinstance(shader,str) and isinstance(body,list) and i==len(tokens)
    return shader,body
materials=[];visited=set();missing=[]
def audit_vmt(rel):
    rel=rel.replace('\\','/').lower()
    if rel in visited:return
    visited.add(rel)
    origin,data=locate(rel)
    if data is None:missing.append(rel);return
    shader,pairs=parse_vmt(data)
    row={**origin,'shader':shader,'syntax':'balanced key/value grammar','sha256':sha(data),'dependencies':[]}
    for key,val in pairs:
        if not isinstance(key,str) or not isinstance(val,str):continue
        key=key.lower()
        if key in ('$basetexture','$bumpmap','$detail','$envmapmask','$phongexponenttexture','$normalmapalphaenvmapmask'):
            if val in ('0','1'):continue
            dependency='materials/'+val.replace('\\','/').lower()+'.vtf'
            info,texture=locate(dependency)
            if texture is None:missing.append(dependency);row['dependencies'].append({'missing':dependency});continue
            assert texture[:4]==b'VTF\0'
            major,minor,hdr=struct.unpack_from('<III',texture,4);w,h=struct.unpack_from('<HH',texture,16)
            assert major==7 and 0<minor<=6 and hdr<=len(texture) and w>0 and h>0
            row['dependencies'].append({**info,'vtf_version':[major,minor],'width':w,'height':h,'sha256':sha(texture)})
        elif key=='include':audit_vmt(val.replace('\\','/').lower())
    materials.append(row)

models=[]
for path in sorted(CONTENT.rglob('*.mdl')):
    raw=path.read_bytes();u=lambda o:struct.unpack_from('<I',raw,o)[0]
    string=lambda o:raw[o:raw.index(0,o)].decode()
    assert raw[:4]==b'IDST' and u(4)==48 and u(76)==len(raw)
    textures=[string(u(208)+n*64+u(u(208)+n*64)) for n in range(u(204))]
    dirs=[string(u(u(216)+n*4)).replace('\\','/') for n in range(u(212))]
    refs,families,skin=u(220),u(224),u(228)
    skin_table=[list(struct.unpack_from('<'+'H'*refs,raw,skin+family*refs*2)) for family in range(families)]
    assert all(idx<len(textures) for family in skin_table for idx in family)
    meshes=[]
    for bp in range(u(232)):
        bo=u(236)+bp*16
        for model in range(u(bo+4)):
            mo=bo+u(bo+12)+model*148
            for mesh in range(u(mo+72)):
                me=mo+u(mo+76)+mesh*116;material=u(me)
                assert material<refs,(path,material,refs)
                meshes.append({'bodypart':bp,'model':model,'mesh':mesh,'skinref':material,'vertex_count':u(me+8)})
    resolved=[]
    for name in textures:
        candidates=['materials/'+d+name+'.vmt' for d in dirs]
        chosen=next((r for r in candidates if locate(r)[0]),None)
        assert chosen,(path,candidates)
        info,_=locate(chosen);resolved.append({'texture':name,**info});audit_vmt(chosen)
    models.append({'path':str(path.relative_to(CONTENT)),'checksum':u(8),'textures':textures,'texture_directories':dirs,
                   'skinref_count':refs,'skin_families':skin_table,'mesh_skinref_indices':meshes,'resolved_materials':resolved})

manifest=json.loads((HERE/'glock_manifest.json').read_text())
source_records=[]
for record in manifest['files']:
    data=(CONTENT/record['path']).read_bytes();changed=sha(data)!=record['sha256']
    assert not changed or record['path']==REL
    source_records.append({'path':record['path'],'upstream_bytes_match':not changed,'sha256':sha(data)})
assert not missing,missing
stock_variants=[]
glock_material='materials/models/weapons/v_models/pist_glock18/glock18.vmt'
for archive in archives:
    if glock_material not in archive.index:continue
    data=archive.read(glock_material);shader,pairs=parse_vmt(data);dependencies=[]
    for key,val in pairs:
        if key.lower() not in ('$basetexture','$envmapmask'):continue
        rel='materials/'+val.replace('\\','/').lower()+'.vtf';locations=[]
        for candidate in archives:
            if rel in candidate.index:
                texture=candidate.read(rel);assert texture[:4]==b'VTF\0'
                locations.append({'archive':str(candidate.path),'bytes':len(texture),'sha256':sha(texture)})
        assert locations,rel
        dependencies.append({'path':rel,'available_in':locations})
    stock_variants.append({'archive':str(archive.path),'path':glock_material,'syntax':'balanced key/value grammar',
                           'shader':shader,'sha256':sha(data),'dependencies':dependencies})
report={'private_lab_only':True,'source_file_count':len(source_records),'private_vmt_count':len(list(CONTENT.rglob('*.vmt'))),
        'patched_material':patch,'source_asset_checks':source_records,'models':models,'materials':materials,
        'stock_material_variants':stock_variants,'missing_dependencies':missing,
        'limitations':'Static syntax, VTF headers, CRCs, MDL skin references and local user VPK resolution verified. Actual Quest mount order/native rendering require device verification; no replacement textures or models supplied.'}
(HERE/'material_audit.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'source_assets':len(source_records),'private_vmts':report['private_vmt_count'],'model_count':len(models),
                  'resolved_materials':len(materials),'missing_dependencies':missing,'patch':patch}))
