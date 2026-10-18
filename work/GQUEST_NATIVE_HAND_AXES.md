# Native hand-axis trace, 2026-10-15

This is stripped shipped-binary LLVM analysis, not a source reconstruction or a
confirmed repair. No binary or bone matrices were changed.

## Verified side mapping and transforms

The call at `0x39fc90` passes `w2=(w23==1)` into pose construction `0x3a1428`.
The same side flag is passed as w3 to apply routine `0x3a1aac`. There, zero
selects the string `ValveBiped.Bip01_L_Hand` (VA0x59437), one selects
`ValveBiped.Bip01_R_Hand` (VA0x5d440). Therefore side 0 is left, side 1 right.

Construction reads a per-hand local transform through `0x34b0f8`. Its exact
branch order is: VR active byte4888 must be nonzero; skeletal presence byte
977+side nonzero returns the initialized identity matrix; otherwise valid-cache
byte5024+side selects `this + 4896 + 64*side` (4x4 matrix). Otherwise it uses
the fixed fallback described below. The skeletal-presence interpretation is
supported by `0x349d38`, returning active&&byte977, and its use in the constructor
before reading skeletal joint quaternions. That local offset cache is computed
at `0x345a98` (left) / `0x345afc` (right) through `0x3480f4` from the actual input
snapshot. The latter validates snapshot flags and two real pose quaternions;
it is not simply the raw world grip pose. This is a local offset/relative-pose
path, so globally correcting this matrix would be particularly risky.

If the cache is unavailable, `0x34b17c..0x34b1bc` constructs a fixed fallback:
position (-2,+2,-3) for left, (-2,-2,-3) for right; angles (-30,0,0) for both.
The angles are verified by decoding two float constants at VA0xcb1c8.

Pose construction extracts Euler angles from the returned matrix, then:

* right: keeps extracted pitch/yaw/roll;
* left: negates pitch and roll (`0x3a164c..0x3a165c`).

`0x3a1118` subsequently interpolates finger entries at offsets >=24. It does
not overwrite the hand position/angle fields at offsets 0..23.

The apply routine has a complementary **hand-authored basis choice**:
`0x3a1d88..0x3a1ddc` constructs quaternion (1,0,0,0) for right, (0,0,0,1) for
left, i.e. right gets a proper 180-degree X rotation, left identity. It combines
this matrix, the pose angle/offset matrix and the selected hand's controller/world
frame; original bone matrices/children are transformed too. This is not a
simple lone mirror instruction that can safely be removed.

In mathematical terms, negating pitch and roll with yaw retained is the proper
rotation `S_z R S_z`, where `S_z=diag(1,1,-1)`. It is not a reflected mesh
(determinant remains +1). The right-side X half-turn is also determinant +1.
These are different operations; there is no proven single-instruction
"double mirror cancellation". Exact resulting grip-to-palm matrix additionally
depends on original authored bone transforms and the local offset cache.

The only direct load found for `hlvr_grip_yaw_correction` is at
`0x3456c4..0x345738`; its ConVar object is VA0xe3fdf0. This shared setting must
stay at the user-confirmed zero.

## Paired live observations

Three `GQUEST_HAND_FRAME` samples in `gquest-current-20261015-trigger.log`
show stable left grip-to-palm angles around (-62,+27,-10.5); right around
(+62,-29,+168). The near-180 roll difference alone is not a defect: left/right
authored hand bases differ. The almost stable local frame is more consistent
with a fixed basis/calibration issue than stale tracking; it does not identify
the intended correction axis or show the visual skin.

Do not assume an OpenXR grip frame is a simple forward-pointing aim frame.
Khronos defines the grip's X axis normal to the palm with opposite inward/outward
semantics for right/left, and its -Z axis along the partly closed finger tube
from little finger toward thumb. This differs from aim-pose semantics:
https://registry.khronos.org/OpenXR/specs/1.1-khr/html/xrspec.html#semantic-paths-standard-pose-identifiers

## Exact next measurement

Capture these matrices in the **same frame** for side0 and side1:

1. Raw native cached world grip/hand matrices before authored model offsets.
2. The returned local matrix from `0x34b0f8`, including whether its cache/fallback
   branch is used (hand validity at offsets 977+side, 5024+side, VR active4888).
3. The six float handOffset/handAngles fields output by `0x3a1428`.
4. Body palm matrix at the final render stage (existing body dump supplies this).

The testable invariant is `K_s = inverse(G_s) * P_s` in a single consistent
native basis. Check K_s remains stable when rotating only that wrist. Also compare
the cache-derived versus fallback local offset with its handed authored basis.
The GLua GquestXR grip reconstruction is a useful independent sample, but cannot
replace native G_s because its Euler/XR conversion is not independently calibrated
against the native body transform.

`vr_debug_hand_pose` **injects raw tracking** and must not be used here.
`vr_hand_debug` draws hand boxes/deltas and `cl_hlvr_hands_debug` draws hand cubes;
neither is a left-only calibration interface. No verified per-left calibration
ConVar was found. Without the local offset/body matrix relationship, neither a
NOP of the left Euler negation nor a guessed global/bone rotation is supported.

## New measured cached-pose candidate

Subsequent native bridge capture `work/gquest-hand-native-20261015.log` supplies
six samples per hand, all VR=1, skeletal=0, cached=1. The matrices remain stable
to their printed precision. Exact sample1 cache Euler angles are:

* left: (+62.35598,+27.12356,+10.54028);
* right: (+62.08343,-28.92269,-11.63726).

The constructor changes left to (-62.35598,+27.12356,-10.54028), matching the
previous observed rendered left local rotation. Right apply adds its authored
X half-turn, giving (+62.08343,-28.92269,+168.36274), matching the previous
rendered right local rotation. The cached rotations are already almost a
Y-reflected pair, before the constructor's extra Z-conjugation on left.

`0x3480f4` computes this cache as inverse(Source-converted grip matrix) multiplied
by a second Source-converted snapshot pose. The second pose is at snapshot
384+56*side; the grip is at64+56*side; validity byte379+side must be set and
source-kind byte381+side must equal2. There is no side-specific angle negation
inside that computation; it preserves the handed snapshot pose. The exact
semantic name of the second pose remains unresolved. Its being a distinct real
pose, not a made-up fixed user correction, is established by the snapshot reads.

These measurements now support a **controlled visual A/B candidate**: skip
constructor pitch/roll negation only for the observed left cached controller
path, leaving right, raw tracking, local positions, HUD and network untouched.
This is a roughly126-degree orientation change derived from actual measured
cache transforms. It remains a candidate until wearer confirmation; proving
where a rotation is introduced does not by itself prove the intended mesh basis.

Exact instruction VA0x3a164c is word0x370000b3 (`tbnz w19,#0,+0x14`). The
controlled candidate word0x14000005 (`b +0x14`) jumps to the same0x3a1660 target.
For right (sidebit1), old and new instructions take exactly the same path. For
left, only the following two FNEG and two hand-angle stores are skipped.
Surrounding bytes must match; original and candidate words must be recognized
explicitly. Runtime root bridge gates this candidate on VR active, left
skeletal0/cache1 and an explicit opt-in file, restoring on disable or inactive
path. The branch patch itself is global code, so timely same-thread gate polling
is necessary to avoid applying it briefly to a changed fallback/skeletal path.

`work/gquest-hand-candidate-math.json` records the12 measured samples, original
constructor/apply angle outcomes, and candidate outcomes. No binary edit was
performed by this audit worker.
