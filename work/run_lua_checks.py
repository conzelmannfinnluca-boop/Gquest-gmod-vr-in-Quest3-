"""Run standalone Lua boundary harnesses with system Lua 5.4 (not the game VM)."""
import ctypes, sys
from pathlib import Path
lib=ctypes.CDLL('liblua5.4.so.0')
lib.luaL_newstate.restype=ctypes.c_void_p
lib.luaL_openlibs.argtypes=[ctypes.c_void_p]
lib.luaL_loadfilex.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_char_p]
lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p]
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p]
lib.lua_tolstring.restype=ctypes.c_char_p
lib.lua_close.argtypes=[ctypes.c_void_p]
for arg in sys.argv[1:]:
    state=lib.luaL_newstate(); lib.luaL_openlibs(state)
    code=lib.luaL_loadfilex(state,arg.encode(),None)
    if not code and 'test_' in Path(arg).name: code=lib.lua_pcallk(state,0,0,0,0,None)
    if code: raise RuntimeError(arg+': '+lib.lua_tolstring(state,-1,None).decode())
    lib.lua_close(state)
    print('PASS',arg)
