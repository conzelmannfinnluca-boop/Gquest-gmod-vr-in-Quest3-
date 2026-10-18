"""Compare live pose samples with authored local binds; differences include animation."""
import json, math, struct
from pathlib import Path
root=Path(__file__).parent
live=json.loads((root/'gquest-left-hand-live.json').read_text())
audit=json.loads((root/'gquest-hand-bind-audit.json').read_text())
reference={b['name']:b for b in audit['gordonf_cit.mdl']['hand_bones']}
b=(root/'quest-vr-content/models/weapons/vr_superphyscannon.mdl').read_bytes()
def i(o): return struct.unpack_from('<i',b,o)[0]
weapon={}
for n in range(i(156)):
    o=i(160)+n*216;s=o+i(o);name=b[s:b.index(0,s)].decode()
    weapon[name]={'bind_pos':struct.unpack_from('<3f',b,o+32),'bind_quaternion':struct.unpack_from('<4f',b,o+44)}
def qang(a):
    p,y,r=(math.radians(a[k])/2 for k in ['p','y','r'])
    sp,cp,sy,cy,sr,cr=math.sin(p),math.cos(p),math.sin(y),math.cos(y),math.sin(r),math.cos(r)
    return sr*cp*cy-cr*sp*sy, cr*sp*cy+sr*cp*sy, cr*cp*sy-sr*sp*cy, cr*cp*cy+sr*sp*sy
def rotation(q,r):
    d=abs(sum(x*y for x,y in zip(q,r))/math.sqrt(sum(x*x for x in q)*sum(x*x for x in r)))
    return math.degrees(2*math.acos(min(1,d)))
summary=[]
for ent in live['entities']:
    exact=ent['model']=='models/weapons/vr_superphyscannon.mdl'
    binds=weapon if exact else reference
    rows=[]
    for bone in ent['bones']:
        bind=binds.get(bone['name'])
        if not bind or 'parent_local_angles' not in bone: continue
        pos=bone['parent_local_position'];angles=bone['parent_local_angles']
        rows.append({'name':bone['name'],'rotation_from_bind_degrees':rotation(qang(angles),bind['bind_quaternion']),
                     'position_from_bind_inches':math.dist([pos[k] for k in ['x','y','z']],bind['bind_pos']),
                     'parent_local_angles':angles})
    hand=next(x for x in ent['bones'] if x['name'].endswith('L_Hand'))
    tracked=live['tracked_left']['position']
    summary.append({'entity':ent['entity'],'class':ent['class'],'model':ent['model'],
                    'bind_reference':'exact weapon MDL' if exact else 'gordonf_cit reference ONLY; not actual entity MDL',
                    'hand_to_tracked_grip_inches':None if ent['class']=='gmod_hands' else math.dist([hand['position'][k] for k in ['x','y','z']],[tracked[k] for k in ['x','y','z']]),
                    'coordinate_caveat':'gmod_hands matrices appear in viewmodel space near origin; world grip distance is inapplicable' if ent['class']=='gmod_hands' else 'World bone origin differs from authored controller grip; distance alone is not an alignment error',
                    'bones':rows})
out={'caveat':'Observed differences include animation and authored grip offsets, not demonstrated corruption. Two entities use approximate different-model references.',
     'entities':summary}
(root/'gquest-left-hand-live-comparison.json').write_text(json.dumps(out,indent=2)+'\n')
for e in summary:
    print(e['entity'],e['model'],e['bind_reference'],'hand-grip distance',round(e['hand_to_tracked_grip_inches'],4) if e['hand_to_tracked_grip_inches'] is not None else 'inapplicable: viewmodel coordinates')
    print('\n'.join('%s %.4fdeg %.7fin'%(b['name'].split('_L_')[-1],b['rotation_from_bind_degrees'],b['position_from_bind_inches']) for b in e['bones']))
