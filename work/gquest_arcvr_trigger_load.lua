local previous=SWEP
SWEP={Primary={},Secondary={}}
include("gquest_arcvr_trigger_patch.lua")
weapons.Register(SWEP,"gquest_arcvr_aniv_glock")
SWEP=previous
print("GQUEST_ARCVR weapon registered",SERVER and "server" or "client")
