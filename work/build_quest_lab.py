"""Create a private experimental APK copy; never overwrite the original APK."""
import struct as S
import zipfile
import hashlib
import zlib
from pathlib import Path

U32 = lambda b, o: S.unpack_from('<I', b, o)[0]
NS = 'http://schemas.android.com/apk/res/android'
source = Path('outputs/GDroid-0.1.29.apk')
out = Path('work/GMod-Quest-Lab-unsigned.apk')
with zipfile.ZipFile(source) as z:
    xml = z.read('AndroidManifest.xml')
    pool_at = 8
    kind, header, poolsize = S.unpack_from('<HHI', xml, pool_at)
    assert kind == 1 and header == 28
    count, styles, flags, stringstart, stylestart = S.unpack_from('<IIIII', xml, pool_at + 8)
    assert styles == 0 and not flags & 0x100, 'Expected unstyled UTF-16 pool'
    strings = []
    for i in range(count):
        p = pool_at + stringstart + U32(xml, pool_at + header + 4*i)
        length = S.unpack_from('<H', xml, p)[0]
        assert length < 0x8000
        strings.append(xml[p+2:p+2+length*2].decode('utf-16le'))
    def idx(s):
        if s not in strings: strings.append(s)
        return strings.index(s)
    def attr(name, value, namespace=NS):
        return S.pack('<IIIHBBI', idx(namespace), idx(name), idx(value), 8, 0, 3, idx(value))
    def boolattr(name, value):
        return S.pack('<IIIHBBI', idx(NS), idx(name), 0xffffffff, 8, 0, 0x12, int(value))
    def start(name, attributes=()):
        return S.pack('<HHIII', 0x102, 16, 36+20*len(attributes), 0, 0xffffffff) + S.pack('<IIHHHHHH', 0xffffffff, idx(name), 20, 20, len(attributes), 0, 0, 0) + b''.join(attributes)
    def end(name):
        return S.pack('<HHIIIII', 0x103, 16, 24, 0, 0xffffffff, 0xffffffff, idx(name))
    def leaf(name, attributes): return start(name, attributes) + end(name)
    vrfilter = start('intent-filter') + leaf('action', [attr('name', 'android.intent.action.MAIN')])
    for category in ['android.intent.category.LAUNCHER', 'com.oculus.intent.category.VR', 'org.khronos.openxr.intent.category.IMMERSIVE_HMD']:
        vrfilter += leaf('category', [attr('name', category)])
    vrfilter += end('intent-filter')
    metadata = leaf('meta-data', [attr('name', 'com.oculus.supportedDevices'), attr('value', 'quest3|questpro|quest2')])
    chunks, stack = [], []
    pos = pool_at + poolsize
    while pos < len(xml):
        typ, hs, size = S.unpack_from('<HHI', xml, pos)
        b = bytearray(xml[pos:pos+size])
        if typ == 0x102:
            name = strings[U32(b, 20)]
            attrsstart, attrsize, n = S.unpack_from('<HHH', b, 24)
            identity = None
            for i in range(n):
                p = 16 + attrsstart + i*attrsize
                aname = strings[U32(b, p+4)]
                dtype, value = b[p+15], U32(b, p+16)
                if aname == 'name' and dtype == 3: identity = strings[value]
                replacement = None
                if name == 'manifest' and aname == 'package': replacement = 'com.gmodvr.qvrx'
                if aname == 'authorities' and dtype == 3:
                    replacement = strings[value].replace('com.gmodvr.flat', 'com.gmodvr.qvrx')
                if name == 'application' and aname == 'label': replacement = 'Gquest'
                if replacement:
                    v = idx(replacement)
                    S.pack_into('<I', b, p+8, v)
                    b[p+15] = 3
                    S.pack_into('<I', b, p+16, v)
            if name == 'activity' and identity == 'com.gmodvr.flat.GameActivity':
                for i in range(n):
                    p = 16 + attrsstart + i*attrsize
                    if strings[U32(b,p+4)] == 'exported':
                        b[p+15] = 0x12
                        S.pack_into('<I', b, p+16, 0xffffffff)
            additions = []
            if name == 'application':
                # Debug only this isolated lab package so native stacks can be
                # inspected without root or changing the original GDroid app.
                additions.append(boolattr('debuggable', True))
            if name == 'activity' and identity in ['com.gmodvr.flat.GameActivity', 'com.gmodvr.flat.LauncherActivity']:
                label = 'Gquest' if identity.endswith('GameActivity') else 'Gquest Setup'
                if not any(strings[U32(b,16+attrsstart+i*attrsize+4)] == 'label' for i in range(n)):
                    additions.append(attr('label', label))
            if additions:
                b.extend(b''.join(additions))
                S.pack_into('<I', b, 4, len(b))
                S.pack_into('<H', b, 28, n + len(additions))
            stack.append((name, identity))
        elif typ == 0x103:
            name, identity = stack.pop()
            if name == 'activity' and identity == 'com.gmodvr.flat.GameActivity': chunks.append(vrfilter)
            if name == 'application': chunks.append(metadata)
        chunks.append(bytes(b))
        pos += size
    data, offsets = bytearray(), []
    for s in strings:
        encoded = s.encode('utf-16le')
        offsets.append(len(data))
        data += S.pack('<H',len(encoded)//2) + encoded + b'\0\0'
    data += bytes((-len(data)) % 4)
    startpos = 28 + 4*len(strings)
    pool = S.pack('<HHIIIIII',1,28,startpos+len(data),len(strings),0,flags,startpos,0) + b''.join(S.pack('<I',o) for o in offsets) + data
    # Resource-map indices correspond to string-pool indices, including newly
    # introduced attribute names. Preserve original mappings and add debuggable.
    mapped = []
    for b in chunks:
        if S.unpack_from('<H', b)[0] == 0x180:
            resourceids = [U32(b,p) for p in range(8,len(b),4)]
            debugidx = idx('debuggable')
            resourceids += [0] * max(0, debugidx + 1 - len(resourceids))
            resourceids[debugidx] = 0x0101000f
            b = S.pack('<HHI',0x180,8,8+4*len(resourceids)) + b''.join(S.pack('<I',v) for v in resourceids)
        mapped.append(b)
    # Android's resource lookup requires attributes ordered by their resource
    # IDs. Appending debuggable without this order parses in inspection tools
    # but is ignored by PackageManager's styled-attribute lookup.
    ordered = []
    for chunk in mapped:
        b = bytearray(chunk)
        if S.unpack_from('<H', b)[0] == 0x102:
            offset, width, n = S.unpack_from('<HHH', b, 24)
            assert width == 20
            assert S.unpack_from('<HHH', b, 30) == (0, 0, 0)
            p = 16 + offset
            attributes = [bytes(b[p+i*width:p+(i+1)*width]) for i in range(n)]
            def resource_key(a):
                nameid = U32(a,4)
                return resourceids[nameid] if nameid < len(resourceids) else 0
            attributes.sort(key=resource_key)
            b[p:p+n*width] = b''.join(attributes)
        ordered.append(bytes(b))
    payload = pool + b''.join(ordered)
    manifest = S.pack('<HHI',3,8,8+len(payload)) + payload
    dex = bytearray(z.read('classes.dex'))
    # Preserve DEX string_ids lexical ordering without changing any indices.
    # The original neighbours are launch_args < launcher < launcher saved session.
    needle, replacement = b'\x08launcher\0', b'\x08launcheq\0'
    assert dex.count(needle) == 1, 'Expected one exact launcher string literal'
    dex = dex.replace(needle,replacement)
    dex[12:32] = hashlib.sha1(dex[32:]).digest()
    S.pack_into('<I',dex,8,zlib.adler32(dex[12:]) & 0xffffffff)
    with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as w:
        for item in z.infolist():
            if item.filename.startswith('META-INF/'): continue
            content = z.read(item.filename)
            if item.filename == 'AndroidManifest.xml': content = manifest
            if item.filename == 'classes.dex': content = bytes(dex)
            if item.filename == 'lib/arm64-v8a/libclient.so':
                # GDroid Flat unconditionally clears the USERINFO VR-player
                # cvar in its once-only client initialization (VA 0x4857b0).
                # Keep this isolated copy in VR mode before server signon.
                assert hashlib.sha256(content).hexdigest() == '00c32647cdeca5726a14236ce7d23a5d6c493703df518f773a25baf70d06eea9'
                offset = 0x4817b0
                assert content[offset:offset+4] == bytes.fromhex('e1031f2a')  # mov w1,wzr
                content = content[:offset] + bytes.fromhex('21008052') + content[offset+4:]  # mov w1,#1

            w.writestr(item, content)
        w.write('work/liblauncheq.so','lib/arm64-v8a/liblauncheq.so')
        import json
        content_manifest = json.loads(Path('work/quest-vr-content-manifest.json').read_text())
        manifest_lines = []
        for entry in content_manifest['files']:
            relative = entry['path']
            assert not relative.startswith('/') and '..' not in relative.split('/') and '\t' not in relative and '\n' not in relative
            content_path = Path('work/quest-vr-content') / relative
            content = content_path.read_bytes()
            assert len(content) == entry['bytes'] and hashlib.sha256(content).hexdigest() == entry['sha256']
            w.writestr('assets/quest_lab_vr_content/' + relative, content)
            manifest_lines.append(str(entry['bytes']) + '\t' + relative)
        own_root = Path('work/gquest-ui')
        for own_path in sorted(own_root.rglob('*.lua')):
            relative = own_path.relative_to(own_root).as_posix()
            w.writestr('assets/quest_lab_vr_content/' + relative, own_path.read_bytes())
            manifest_lines.append(str(own_path.stat().st_size) + '\t' + relative)
        # Private ArcVR anniversary slice; provenance/checksums in its manifest.
        arc_root = Path('work/gquest-arcvr/content')
        if arc_root.exists():
            for asset in sorted(arc_root.rglob('*')):
                if not asset.is_file(): continue
                relative = asset.relative_to(arc_root).as_posix()
                assert not any(line.endswith('\t' + relative) for line in manifest_lines)
                w.writestr('assets/quest_lab_vr_content/' + relative, asset.read_bytes())
                manifest_lines.append(str(asset.stat().st_size) + '\t' + relative)
        model_root = Path('work/gquest-weapon-models/content')
        if model_root.exists():
            model_manifest=json.loads(Path('work/gquest-weapon-models/manifest.json').read_text())
            for entry in model_manifest['files']:
                relative=entry['path']
                content=(model_root/relative).read_bytes()
                assert len(content)==entry['bytes'] and hashlib.sha256(content).hexdigest()==entry['sha256']
                assert not any(line.endswith('\t'+relative) for line in manifest_lines)
                w.writestr('assets/quest_lab_vr_content/'+relative,content)
                manifest_lines.append(str(len(content))+'\t'+relative)
        w.writestr('assets/quest_lab_vr_content.tsv', '\n'.join(manifest_lines) + '\n')

print(out)
