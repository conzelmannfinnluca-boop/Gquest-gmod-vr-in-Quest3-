"""Send the known test commands once the actual engine socket is available."""
import socket
import time

deadline=time.monotonic()+45
commands=b"lua_openscript gquest_arcvr_equip_test.lua\nlua_openscript_cl gquest_close_menu_probe.lua\nlua_openscript_cl gquest_arcvr_runtime_probe.lua\n"
while time.monotonic()<deadline:
    try:
        with socket.create_connection(("127.0.0.1",27100),timeout=2) as connection:
            connection.settimeout(2)
            banner=connection.recv(2048)
            if b"Half-Life 2 VR dev command socket" in banner:
                connection.sendall(commands)
                time.sleep(1)
                print("Commands sent to the confirmed engine socket; inspect runtime logs.")
                raise SystemExit(0)
    except (OSError,TimeoutError):
        pass
    time.sleep(3)
raise SystemExit("No confirmed engine socket within 45 seconds; no execution claimed.")
