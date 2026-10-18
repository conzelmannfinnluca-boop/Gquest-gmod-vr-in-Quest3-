import socket, time
commands = [
    "echo GQUEST_LIVE_DIAGNOSTICS_BEGIN",
    "vr_hud_layer_status",
    "vr_hud_paint_probe 1",
    "vr_hud_quad_subrects_report 1",
    "vr_rt_readback 3",
    "vr_debug_hand_aim_delta 1",
    "vr_weapon_census",
    "vr_controller_offset_x",
    "vr_controller_offset_y",
    "vr_controller_offset_z",
    "vr_controller_offset_pitch",
    "vr_controller_offset_yaw",
    "vr_controller_offset_roll",
    "vr_first_person_uses_world_model",
    "vr_custom_mod_force_world_model_in_hand",
    "echo GQUEST_LIVE_DIAGNOSTICS_END",
]
with socket.create_connection(("127.0.0.1",27100),3) as connection:
    connection.settimeout(3)
    banner=connection.recv(4096)
    if not banner:
        raise RuntimeError("Engine socket closed: launch Gquest first")
    print(banner.decode().strip())
    connection.sendall(("\n".join(commands)+"\n").encode())
    time.sleep(2)
    print("Diagnostic commands sent; inspect device SRCENG logs for results")
