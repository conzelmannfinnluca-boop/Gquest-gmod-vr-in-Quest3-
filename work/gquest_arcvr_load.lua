local previous=SWEP
SWEP={Primary={},Secondary={}}
include("weapons/gquest_arcvr_aniv_glock/shared.lua")
weapons.Register(SWEP,"gquest_arcvr_aniv_glock")
SWEP=previous
print("GQUEST_ARCVR weapon registered",SERVER and "server" or "client")
