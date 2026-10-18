"""Private VR model metadata overlay; preserve the user's original weapon data."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parent.parent
GAME=Path('/home/shift/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/GarrysMod')
OUT=ROOT/'work/gquest-weapon-models'
CONTENT=OUT/'content'
sha=lambda b:hashlib.sha256(b).hexdigest()
donor=json.loads((ROOT/'work/quest-vr-content-manifest.json').read_text())
assets={r['path'].lower():r for r in donor['files']}
records=[]
with ZipFile(ROOT/'work/sourcevr-core-reference.apk') as archive:
    assert sha((ROOT/'work/sourcevr-core-reference.apk').read_bytes())==donor['origin_apk_sha256']
    manifest=archive.read('assets/sourcevr/v1/vr/hl2vr.manifest').decode()
    for line in manifest.splitlines():
        digest,path=line.split('  ',1)
        if not path.startswith('scripts/weapon_') or not path.endswith('.txt') or path.endswith('weapon_cubemap.txt'):continue
        reference=archive.read('assets/sourcevr/v1/blobs/sha256/'+digest)
        assert sha(reference)==digest
        fields=re.findall(rb'"(vrmodel(?:_l)?)"\s*"([^"\r\n]+)"',reference)
        # Physgun is a GMod native special case already observed using this VR
        # model. Make that existing choice explicit; do not borrow HL2 stats.
        if path=='scripts/weapon_physgun.txt':
            fields=[(b'vrmodel',b'models/weapons/vr_superphyscannon.mdl'),
                    (b'vrmodel_l',b'models/weapons/left_handed/vr_superphyscannon_l.mdl')]
        if not fields:continue
        original_path=GAME/'sourceengine'/path
        original=original_path.read_bytes()
        assert not re.search(rb'"vrmodel(?:_l)?"\s*"',original),path
        for _,model in fields:
            rel=model.decode().lower()
            assert rel in assets,(path,rel)
            actual=ROOT/'work/quest-vr-content'/assets[rel]['path']
            assert sha(actual.read_bytes())==assets[rel]['sha256']
            for suffix in ('.vvd','.dx90.vtx'):
                assert rel[:-4]+suffix in assets,(path,rel,suffix)
        token=re.compile(rb'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[{}]',re.S)
        brace=next(m for m in token.finditer(original) if m.group()==b'{')
        newline=b'\r\n' if b'\r\n' in original else b'\n'
        injected=newline+b'\t// Gquest: explicit VR models; all original weapon data follows.'+newline
        injected+=b''.join(b'\t"'+key+b'"\t"'+value+b'"'+newline for key,value in fields)
        adapted=original[:brace.end()]+injected+original[brace.end():]
        assert adapted[:brace.end()]+adapted[brace.end()+len(injected):]==original
        target=CONTENT/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(adapted)
        view=re.search(rb'"viewmodel"\s*"([^"\r\n]+)"',original)
        view=view.group(1).decode() if view else None
        renamed=view.replace('/v_','/vr_').lower() if view else None
        records.append({'path':path,'bytes':len(adapted),'sha256':sha(adapted),
            'original_path':str(original_path),'original_sha256':sha(original),
            'donor_script_sha256':digest,'fields':{k.decode():v.decode() for k,v in fields},
            'original_bytes_preserved':True,'flat_viewmodel':view,
            'simple_vr_rename':renamed,'simple_vr_rename_present':renamed in assets if renamed else False})
assert len(records)==12,len(records)
report={'private_lab_only':True,'origin_apk_sha256':donor['origin_apk_sha256'],
        'files':records,'runtime_verified':False,
        'scope':'Only vrmodel/vrmodel_l keys added to exact original user-owned scripts. No ammo, damage, audio, buckets or animation fields changed.'}
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'files':len(records),'missing_simple_rename':[r['path'] for r in records if not r['simple_vr_rename_present']]}))
