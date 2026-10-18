# Private material correction, 2026-10-15

The Quest native material parser reports `KeyValues Error: LoadFromBuffer:
missing {` for `materials/models/weapons/arcticvr/p38/v_p38.vmt` in
`work/gquest-weapons-current.log` at line2019. The pinned upstream file ends with
two closing braces for one opening brace. The private copy now removes only the
final `}\n`, preserving all shader parameters and texture paths.

* Original:238 bytes, SHA256
  `ea89a384fe7dd01e058e3fb9f939b3c75eebd385edbd66c9238232d7efc105b3`.
* Adapted:236 bytes, SHA256
  `71d9fe3e06743f100372f4aca9760335ead0227ea16f090e2321dc64bae10e20`.

Upstream checkout and `glock_manifest.json` retain the original provenance;
`material_patch.json` records the deliberate private adaptation. The17 source
assets include one VMT and two VTF textures; this is not17 different VMT files.
All other16 source assets still match the pinned source manifest exactly.
`runtime_manifest.json` now hashes the actual adapted bytes.

Run `python3 work/gquest-arcvr/audit_materials.py` from the workspace for the
reproducible audit. It parses KeyValues grammar, resolves material/texture paths
against the private slice and user-owned VPK directories, validates referenced
VPK payload CRCs and VTF headers, and checks MDL skin tables/mesh material indices.
It produces `material_audit.json` outside the packaged content directory.

All5 private MDLs (four upstream and the derived native Glock) have valid texture
indices. Both Glock models have skin row[0,1]: mesh0 uses Glock18(1591 vertices),
mesh1 uses v_p38(692 vertices). The magazine also uses both; loose bullet/case
use v_p38. Thus the broken material concerns the cartridge/brass material and
cannot explain every weapon model being misaligned or the entire Glock shell.

Glock18 resolves to the stock `models/weapons/v_models/pist_glock18/glock18.vmt`.
The available CSS, GMod and fallback variants all have valid syntax, referencing
the real glock18 base texture and glock18_ref reflection mask. These dependencies
exist in the user's installed VPKs. The private v_p38 base texture and
bullet_normal_flat bump map are both present with valid VTF headers. No missing
material/texture dependencies were found within this slice.

Upstream MDL search directories contain a malformed third entry `/"/`; material
lookup resolves through preceding valid directories, so no MDL change is needed.
No textures were substituted, no weapon/pose code was edited, and no stock game
files were modified.

This verifies the packaged static correction. The root agent must hot-load the
VMT and request a material reload/restart before claiming the Quest parser error
is resolved. Actual Quest content mount precedence and visual appearance remain
runtime checks. Rerunning `prepare_glock.py` recopies pristine upstream files;
the documented two-byte material adaptation must be reapplied afterwards.
