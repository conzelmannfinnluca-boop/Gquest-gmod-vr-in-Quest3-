# Private ArcVR foundation for Gquest

Source: https://github.com/Pescorr/arcvr_anniversary_bugfix_beta at
`0d8d5bed01c77ad1550097689dc0d1e6fc035385`.
This slice is **arcticvr_aniv_glock**, defined by
`lua/weapons/arcticvr_aniv_glock/shared.lua`; it is not the legacy
`arcticvr_glock` variant. No upstream files were modified, published, or pushed.
No license file is present in this checkout; prepared assets remain in the private lab.

`prepare_glock.py` creates `glock_manifest.json` and a 17-file asset slice
(1,551,740 bytes) in `content/`. Four MDL48 models have matching VVD, DX90 VTX,
and present PHY checksums. Glock's ten bone names match its source BoneIndices.
The preparation validates exact source damage 15/30, RPM 1200, magazine capacity
17, hand offset (-4.9,-4,1.3), angle (10,0,0), and source-file SHA256.

| Source dependency | Native Quest route | Current status |
| --- | --- | --- |
| World head/hand tracking in g_VR | Real `vr.GetHeadPose`, `vr.GetHandPose(0/1)`, validity flag | Own pose reader implemented; no fabricated values |
| Playspace-to-world transform | Shared own `GquestXR.GetWorldTracking()` | Optional preview consumes it; physical alignment still needs headset test |
| Viewmodel offsets | Source `LocalToWorld(offsetPos,offsetAng,handPos,handAng)` | Exact anniversary offsets preserved |
| g_VR.viewModel and native weapon rendering | Separate explicitly enabled diagnostic ClientsideModel | Preview only; no replacement weapon registered |
| Trigger, slide bone transforms | Source bones trigger2/slide3, roll15°, slide1.4 on -Z | Isolated visual part test; no weapon state changed |
| VRMod_Input and analog state | Genuine native input transitions, menu-focus exclusion | Not connected; native analog/digital signatures require runtime confirmation |
| VRMod_Tracking recoil/two-hand alterations | Apply ArcVR recoil and stabilization to its model, preserve raw native hand poses | Pending; no edits to native tracking |
| VRMod_PreRender/Right and eye poses | Native per-eye render hooks and validated eye positions | Ordinary model preview only; scope rendering pending |
| AVR shooting | Original `avr_shoot` packet and source `VR_Shoot`, chamber/cycle state | Not active; source PrimaryAttack is intentionally a no-op |
| Physical magazines, left-hand grab/drop | Real server shadow-physics updater and heldItems plus pickup networking | Blocking full reload port; native hand pose alone cannot replace this |
| Finger pose arrays | Native hand skeleton/finger control bridge | Pending; no fake g_VR arrays installed |
| Haptics | Real native `vr.TriggerHaptic` | Pending verified signature and amplitude conversion |

The Glock/magazine models require the external CSS material
`models/weapons/v_models/pist_glock18/Glock18.vmt`, absent from this repository.
The source worldmodel and most Glock sounds are also external CSS content.
Root's inspection found the Glock material/worldmodel in the user's existing
GMod and fallback VPKs, and three main Glock sounds in fallback/content_cstrike
VPKs. That evidence is included in the manifest; actual Quest resolution still
needs a runtime check. No duplicate user content was copied into this slice.
`CheckGlockAssets()` refuses the preview if the material is unresolved.
The bundled `v_p38.vmt` contains an extra closing brace in the upstream file;
it remains byte-identical here and should be checked by the actual material parser.
No unrelated textures or renamed stock models have been substituted.

The original ArcVR autoruns/server network receivers are deliberately absent
from this prepared content folder. Loading those now would reference an absent
VRMod pickup system. `sv_arcticvr.lua` expects `g_VR[SteamID].heldItems`, a live
physics updater, and `vrutil_net_pickup`; filling an empty table would not implement
pickup. Its shot receiver accepts client muzzle coordinates and calls server
`VR_Shoot`; a multiplayer adaptation will need authoritative ownership, reach,
fire-rate, and ammunition checks. Do not expose this experimental slice on a server.

## Test commands after mounting the content

The only autorun is own `lua/autorun/client/gquest_arcvr_pose.lua`.
With valid shared world tracking and mounted CSS material:

```
gquest_arcvr_glock_preview 1
gquest_arcvr_glock_parts 1 1
gquest_arcvr_glock_parts 0 0
gquest_arcvr_glock_preview 0
```

This tests the original Glock model and slide/trigger geometry against real
right-hand tracking. It does not shoot, replace the Physgun, consume ammunition,
or claim to be a usable ArcVR weapon. Existing Gquest weapons remain available.
The preview can overlap them during the explicit test; disable it afterwards.

Verified locally: source pin, numeric fidelity, model companion checksums,
bone-index contract, asset SHA256, and own adapter Lua syntax with system Lua5.4.
Not verified: GLua execution, mounted asset resolution, native render visibility,
actual controller alignment, any ArcVR shooting or physical reload operation.

## Subsequent prepared shooting slice

`NATIVE_INPUT_AUDIT.md` describes the newly prepared genuine trigger-to-server
shooting slice, distinct class `gquest_arcvr_aniv_glock`, and diagnostic magazine
commands. The earlier preview remains isolated. `derive_grip.py` adds a calibrated
grip attachment in a new model namespace while retaining original geometry files.
`grip_roundtrip.json` records matrix proof. `runtime_manifest.json` covers all
original assets, derived models, and own Lua to deploy together. Source manifest
`glock_manifest.json` covers only the original 17 assets and upstream source data.
