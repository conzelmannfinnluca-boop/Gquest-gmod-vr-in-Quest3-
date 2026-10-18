# Left hand audit, 2026-10-15

## Established offline findings

`gquest-hand-bind-audit.json` contains MDL v48 parent-local bind position and
quaternion records. Raw float inequality is not a useful measure of anatomical
twisting. Comparing quaternion orientation with normalized absolute dot products:

| Pair | Maximum left rotation difference | Maximum right rotation difference | Maximum left position difference |
| --- | ---: | ---: | ---: |
| gordonf_cit / gordonf_cit_vrhands | 0.889974 degrees | 0.972171 degrees | 0.000038586 inches |
| gordonf / gordonf_vrhands | 0.889989 degrees | 0.972163 degrees | 0.000038379 inches |

The left and right Hand bone bind transforms are exactly unchanged in each pair.
These differences do not support correcting a large left-only rotation through
the model bind pose. They do not exclude skin-weight, animation or native runtime
pose differences; those have not been measured by this comparison.

## Native console commands, static evidence

The shipped `work/gdroid-native/libclient.so` is stripped AArch64. Addresses below
are ELF virtual addresses from LLVM disassembly (`work/client-full.asm`), not
runtime process addresses. This is static inspection, not REA provider evidence.

* `hlvr_set_hand_pose_offset`: registration at 0x3a31f0, callback 0x3a02f8.
  Parses three floats (`%f %f %f`) into the single debug pose position vector
  at VA 0xe46e30. No left/right selector.
* `hlvr_set_hand_pose_angles`: registration at 0x3a3230, callback 0x3a0360.
  Parses three floats into the next debug pose angle vector at VA 0xe46e3c.
  No left/right selector. This does not modify finger-angle entries.
* `hlvr_set_hand_pose_finger`: registration at 0x3a31a8, callback 0x3a0258.
  Parses `%d %d %f %f %f`; first index must be 0..4, second 0..2. Writes one
  3-float entry at debugPose + 24 + finger*36 + bone*12. No hand selector.
* `hlvr_print_hand_pose`: registration at 0x3a3270, callback 0x3a03c8.
  Logs the shared debug handOffset, handAngles and 15 finger entries. It does
  **not** query live tracked joints or the rendered hand's current bone matrices.
* `hlvr_test_hand_pose`: ConVar initialization at 0x3a3160; default `0`. Native
  pose construction at 0x3a1450 loads its integer value, branches at 0x3a146c,
  and copies the debug structure only on the nonzero path (0x3a1470..0x3a1560).
  Therefore editing debug offsets while this variable is zero is not a useful
  test of live tracking alignment.

The callbacks do not check sscanf's return count before storing. Do not send
partial/malformed argument lists. Do not turn on this shared debug pose to try
to repair only the left hand: it is a pose override, not a demonstrated left-only
calibration interface.

The recorded `vr_player_body_vr_hands` console help says `1` uses VR hand meshes
joined to the HL2 body; `0` uses original body hands. This is a global two-hand
model comparison and should not be represented as a left-only fix. User-confirmed
`hlvr_grip_yaw_correction 0` must remain unchanged.

## Prepared safe device diagnostic

`work/gquest_left_hand_audit.lua` registers `gquest_left_hand_audit`. It reads
existing left-hand/finger bone matrices, parent-local transforms and manipulator
values on nearby GLua-exposed entities, plus actual relevant convar values and
the current GquestXR tracked left pose. It changes no convars, poses, models,
bones, rendering hooks or right-hand state, and does not call SetupBones.

Run once with `lua_openscript_cl gquest_left_hand_audit.lua`, then run the command
while the affected hand is visible. Compare actual bone matrices with the tracked
left pose and repeat with open/closed fingers if available. Native render-only
hands may not be represented by GLua entities; no matching entity is an API
visibility limit, not proof the hand is absent. Read-only probe is prepared and
syntax checked locally; not run in the headset because USB access is blocked.

## Remaining hypotheses, not fixes

If the whole palm is rotated with otherwise coherent fingers, inspect the
native left grip-to-hand authored-axis conversion. If the palm follows correctly
but finger relative transforms distort, inspect native skeletal/animation pose
composition. Both require runtime pose/bone evidence before selecting a rotation
or editing authored assets. No arbitrary finger rotations were applied.
