# Live left-hand observation, 2026-10-15

Extracted one `GQUEST_LEFT_AUDIT` JSON record from
`work/gquest-current-20261015.log` to `work/gquest-left-hand-live.json`.
`work/analyze_left_hand_live.py` produces
`work/gquest-left-hand-live-comparison.json`. This is a single snapshot at
RealTime 4.6985, not a full motion or visual test.

## What was observed

All four actual console values are zero:
`hlvr_grip_yaw_correction`, `hlvr_legacy_aiming`,
`vr_player_body_vr_hands`, `hlvr_test_hand_pose`.

Three GLua-visible entities have all 16 sampled left matrices (hand + 15 finger
bones), parent matrices and normal parent-local segment lengths:

| Entity | Class | Model |
| --- | --- | --- |
| 1 | player | models/player/kleiner.mdl |
| 220 | gmod_hands | models/weapons/c_arms_citizen.mdl |
| 218 | weapon_physgun | models/weapons/vr_superphyscannon.mdl |

Every sampled manipulator position/angle is zero; every scale is (1,1,1). This
rules out a persistent GLua bone-manipulator offset on these sampled entities;
it does not rule out native SetBoneMatrix/animation changes or other entities.
No native `gordonf` body renderable was exposed by this enumeration.

Player Kleiner hand origin is 3.0734 inches from GquestXR's reconstructed left
grip. Physgun's left hand origin is 4.4148 inches from it. Neither number alone
is a bug: hand bone origin, controller grip anchor and weapon support hand
origins have different authored offsets. The independent GquestXR reconstruction
is itself awaiting visual alignment confirmation.

`gmod_hands` matrices are around world origin (hand -2.35,22.68,40.79), whereas
the tracked hand is (821.50,563.79,-112.40). These appear to be **viewmodel-space
matrices**. A direct world distance or angle comparison would be invalid.

## Bind comparison and its limits

For Kleiner and citizen arms, only the different `gordonf_cit` MDL reference has
been parsed locally, not their actual MDLs. These rows are explicitly labelled
approximate. Player finger rotation differences are structured: fingers 1..4
have approximately 30-degree base, 10-degree middle and zero tip changes;
thumb has approximately 40 degrees at its middle joint and zero at others.
Local positions match that reference to <0.000103 inches. This looks like a
coherent generic curled pose, not arbitrary finger transforms. It does not prove
that this is the desired displayed hand pose.

The Physgun comparison uses its **exact shipped MDL**. Finger rotation changes
from bind range approximately 3..66 degrees; local segment-position differences
stay below 0.000065 inches. These are plausibly authored grip animation changes.
A bind pose is not the intended runtime grip pose, so large curl changes are not
in themselves proof of twisting. Hand-to-forearm rotation also changes under IK
and cannot be diagnosed from its bind difference alone.

## Next diagnostic

First identify which visible mesh is faulty: player/body glove, weapon's authored
supporting left hand, or both. Capture the read-only report in two controlled
states with left wrist position held steady: left grip/trigger released, then
left grip/trigger pressed, without right-hand input. Record native action active
flags/values and repeat both hand bone matrices at the render stage if possible.
This distinguishes a static authored grip from wrongly mapped input or a palm
frame error; it does not require changing grip yaw or applying guessed rotations.

The existing left-only snapshot cannot establish left/right input independence
or render-stage timing, and it does not show skinning/mesh appearance. A screenshot
or wearer confirmation remains necessary to label any visible twist corrected.
