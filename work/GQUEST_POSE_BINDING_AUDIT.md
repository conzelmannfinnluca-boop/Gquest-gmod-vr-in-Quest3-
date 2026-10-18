# Pose binding static audit, 2026-10-16

Scope: read-only LLVM disassembly of the shipped ARM64 libraries. No REA provider execution or runtime observation; addresses below are ELF virtual addresses, not process absolute pointers.

## Artifact identity

- `work/gdroid-native/liblua_shared.so` SHA256 `4a081ad32ec2b571599f4a41452da3b35b7e73bc1569887dd66a25f3f12f6483`
- `work/gdroid-native/libvrxr.so` SHA256 `76867b5a2c925b1940f01fa964e9d3e17352975afef75cd4e36ab4c2bb7e2bb1`
- Saved disassembly: `work/lua_shared-pose-audit.asm` and `work/vrxr-pose-producer-audit.asm`.

## Binding registration and entry points

`lua_shared` registration at 0x118540..0x1185b4 registers:

| Lua name | Function VA | String address |
|---|---|---|
| GetHeadPose | 0x118760 | 0x1820c |
| GetHandPose | 0x1188e4 | 0x21d8a |
| GetAimPose | 0x1189f4 | 0x199e6 |

All call `VRXR_LocateInput(0, &snapshot)` (4288 bytes). Hand argument defaults 1, and zero selects left while any nonzero selects right. Hand record offset=64+56*hand for position and 76+56*hand for quaternion; aim record offset=176+56*hand and 188+56*hand. A valid return requires successful snapshot plus record flags bit 0x4. Head valid uses successful snapshot.

Positions are explicitly transformed from incoming XR meters `(x,y,z)` to `(x,-z,y)*39.37009811401367`. They are pushed into a field table by 0x11aa98.

## Exact quaternion to angle math

GetHandPose and GetAimPose call 0x11b0ac on unchanged incoming quaternion floats `(x,y,z,w)`. GetHeadPose performs the same math inline. Let D=57.2957763671875 and s=2*(w*y-z*x):

```
p = (abs(s)>=1 ? copysign(90,s) : asin(s)*D)
y = atan2(2*(w*z+x*y), 1-2*(y*y+z*z))*D
r = atan2(2*(w*x+y*z), 1-2*(x*x+y*y))*D
```

Helper writes roll through x3, pitch through x1, yaw through x2. Bindings then push in `(p,y,r)` order via 0x11ab84. This creates tagged field tables with both p/y/r and pitch/yaw/roll names. There is no orientation basis conversion in this binding. ARM64 FNMSUB/FMSUB semantics were crosschecked by compiling builtin_fmaf expressions using the same NDK compiler, avoiding a sign inference from mnemonic names.

## Producer corroboration: genuinely raw XR orientation

`libvrxr` `VRXR_LocateInput` begins 0x4ce84. Its space query helper at 0x4e3ac calls `xrLocateSpace` at 0x4e420. At 0x4e470..0x4e47c it copies the 16-byte `XrSpaceLocation.pose.orientation` directly from stack+24 into its record+12. Positions copy separately from stack+40/+48 into record+0/+8. No quaternion remapping occurs on this path. LocateInput copies this record into the grip output at 0x4d270..0x4d288 (record+64) and aim at 0x4d33c..0x4d380 (record+176). Cached time-zero path returns these snapshot fields. Alternate invalid/fallback record choice exists but uses the same helper/record layout. This establishes the normal tracked path retains the XR quaternion axes through Lua Euler conversion.

## Comparison to sourcePoseAngle

`work/gquest-ui/lua/autorun/client/gquest_wrist_hud.lua:4` reconstructs an Angle with these raw Euler components, rotates XR forward `(0,0,-1)` and up `(0,1,0)`, maps each vector `(x,y,z)->(x,-z,y)`, then derives Source forward/up orientation. That basis mapping is NOT duplicated by the native binding and is mathematically appropriate for raw XR axes (assuming native Angle/Vector operations implement normal Source conventions). Neutral XR orientation yields converted Source yaw 90 degrees; GetWorldTracking subtracts the head yaw difference when aligning with player EyeAngles, so neutral yaw alone is not evidence of an erroneous 90 degree weapon correction.

This audit does not establish the final weapon model bone/grip origin, attachment math, animation state, eye anchoring, or physical model alignment. Do not modify the confirmed wrist HUD or global grip correction on this evidence alone. A paired native entity / Lua model runtime comparison is still needed to locate that mismatch.

## Separate Glock idle animation root finding

The original MDL has one local `@idle` animation at file offset 0xd18, two frames. Its root animation record at 0xd80 has flags0x21 (RAWPOS|RAWROT2), nextoffset18, hence constant Quaternion64 + Vector48. Raw quaternion64 is 0x5ffffefffff80000. Using Valve's official packing formula (21bit signed-biased components divided by1048576.5), q≈(.499999762,.499998808,.499998808,.500002623). Euler≈(pitch0.000164,yaw89.999727,roll89.999836). Position=(-1.724609375,5.18359375,1.4765625). This matches the live root relative entity supplied by parent and differs from bind root by about Rz90. `derive_grip.py` currently uses inverse poseToBone (bind) rather than this animated idle root, so its synthetic roundtrip does not prove runtime attachment alignment. A correction against the actual idle root is supported if the native model carry path evaluates animated attachment transform. Runtime image validation remains necessary.

Exact decoded matrix: `work/gquest-glock-idle-root-audit.json`. Format references (read, no repository mutation): [Valve studio.h](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/public/studio.h), [Valve compressed_vector.h](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/public/mathlib/compressed_vector.h).

### Reproducible decoder

`work/gquest_decode_idle_root.py` exposes `decode_idle_root(path=DEFAULT_MODEL) -> dict` with a `matrix` field. It reads the pinned original Glock, validates SHA256, MDL header/root/animation identity, internal record offsets and RAWPOS|RAWROT2 flags, decodes Quaternion64 and Vector48 directly, and returns the constant authored root idle matrix. It writes no files. Invoking it prints JSON. It reproduced every matrix component in `gquest-glock-idle-root-audit.json` exactly; a one-byte-modified source was rejected by hash validation. No production, binary, or device edits were made for the helper.

Original GetHandPose quaternion math remains documented above at native VA0x11b0ac, called by binding VA0x1188e4. This independent pose binding finding remains valid and does not justify changing HUD conversions.
