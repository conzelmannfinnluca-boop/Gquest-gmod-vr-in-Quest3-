// Own compatibility module for the VR Lua API missing from GDroid0.1.30.
// Uses exported Lua/GLua and VRXR APIs; never replaces the upstream Lua library.
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <dlfcn.h>
#include <algorithm>
namespace GquestVRLua {
struct lua_State;
using Function=int(*)(lua_State*);
struct Triple {float x,y,z;};
struct API {
 void(*create)(lua_State*,int,int)=nullptr;
 void(*pushClosure)(lua_State*,Function,int)=nullptr;
 void(*setField)(lua_State*,int,const char*)=nullptr;
 void(*pushValue)(lua_State*,int)=nullptr;
 void(*pushBool)(lua_State*,int)=nullptr;
 void(*pushNumber)(lua_State*,double)=nullptr;
 void(*pushInteger)(lua_State*,ptrdiff_t)=nullptr;
 ptrdiff_t(*optInteger)(lua_State*,int,ptrdiff_t)=nullptr;
 double(*optNumber)(lua_State*,int,double)=nullptr;
 const char*(*checkString)(lua_State*,int,size_t*)=nullptr;
 void(*pushVector)(lua_State*,const Triple&)=nullptr;
 void(*pushAngle)(lua_State*,const Triple&)=nullptr;
 bool(*locate)(int64_t,void*)=nullptr;
 bool(*booted)()=nullptr;
 bool(*running)()=nullptr;
 int(*primary)()=nullptr;
 void(*setPrimary)(int)=nullptr;
 int(*findSet)(const char*)=nullptr;
 int(*findAction)(int,const char*)=nullptr;
 bool(*analog)(int,int,int,float*,float*,bool*)=nullptr;
 bool(*digital)(int,int,int,bool*,bool*,bool*)=nullptr;
 void(*haptic)(int,float,float,float)=nullptr;
 void(*hapticStop)(int)=nullptr;
} api;
static bool active() {return api.booted() && api.running();}
static int IsActive(lua_State* L) {api.pushBool(L,active());return 1;}
static Triple angles(const float* q) {
 const float x=q[0],y=q[1],z=q[2],w=q[3],deg=57.2957795131f;
 return {std::asin(std::max(-1.f,std::min(1.f,2*(w*y-z*x))))*deg,
   std::atan2(2*(w*z+x*y),1-2*(y*y+z*z))*deg,
   std::atan2(2*(w*x+y*z),1-2*(x*x+y*y))*deg};
}
static bool decode(const unsigned char* data,size_t pos,size_t quat,Triple& position,Triple& angle) {
 float p[3],q[4];memcpy(p,data+pos,sizeof(p));memcpy(q,data+quat,sizeof(q));
 for(float v:p) if(!std::isfinite(v)) return false;
 float norm=0;for(float v:q) {if(!std::isfinite(v)) return false;norm+=v*v;}
 if(norm<0.5f || norm>1.5f) return false;
 // Preserve the established Gquest playspace convention. World conversion
 // remains in its existing Lua tracking provider.
 constexpr float units=39.370098f;
 position={p[0]*units,-p[2]*units,p[1]*units};angle=angles(q);return true;
}
static int pose(lua_State* L,int kind) {
 alignas(16) unsigned char snapshot[4288]={};
 const int side=kind==0?0:int(api.optInteger(L,1,1)!=0);
 const bool located=active() && api.locate(0,snapshot);
 Triple position{},angle{};
 const size_t pos=kind==0?8:kind==1?64+56*side:176+56*side;
 const size_t quat=kind==0?20:kind==1?76+56*side:188+56*side;
 bool valid=located && decode(snapshot,pos,quat,position,angle);
 if(kind) {
  uint32_t flags=0;memcpy(&flags,snapshot+(kind==1?116:228)+56*side,4);
  valid=valid && (flags&4)!=0;
 }
 if(!valid) {position={};angle={};}
 api.pushVector(L,position);api.pushAngle(L,angle);api.pushBool(L,valid);return 3;
}
static int Head(lua_State* L) {return pose(L,0);}
static int Hand(lua_State* L) {return pose(L,1);}
static int Aim(lua_State* L) {return pose(L,2);}
static int Primary(lua_State* L) {api.pushInteger(L,api.primary());return 1;}
static int SetPrimary(lua_State* L) {
 const int hand=int(api.optInteger(L,1,1));if(hand==0 || hand==1) api.setPrimary(hand);return 0;
}
static int action(lua_State* L,bool digital) {
 size_t length=0;const char* name=api.checkString(L,1,&length);
 const auto requested=api.optInteger(L,2,-1);
 const int hand=int(requested);const bool validHand=requested>=-1 && requested<=1;
 const int set=length>0 && length<128?api.findSet("gameplay"):-1;
 const int index=set>=0?api.findAction(set,name):-1;
 bool enabled=false,down=false,changed=false;float x=0,y=0;
 if(active() && validHand && index>=0) {
  if(digital) api.digital(set,index,hand,&down,&changed,&enabled);
  else api.analog(set,index,hand,&x,&y,&enabled);
 }
 if(!digital && (!std::isfinite(x) || !std::isfinite(y))) {x=0;y=0;enabled=false;}
 if(!enabled) {x=0;y=0;down=false;changed=false;}
 if(digital) {api.pushBool(L,down);api.pushBool(L,changed);}
 else {api.pushNumber(L,x);api.pushNumber(L,y);}
 api.pushBool(L,enabled);return 3;
}
static int Analog(lua_State* L) {return action(L,false);}
static int Digital(lua_State* L) {return action(L,true);}
static int Haptic(lua_State* L) {
 const auto hand=api.optInteger(L,1,1);
 const double seconds=api.optNumber(L,2,0.1),frequency=api.optNumber(L,3,160),amplitude=api.optNumber(L,4,0.5);
 if(!active() || hand<0 || hand>1 || !std::isfinite(seconds) || !std::isfinite(frequency) || !std::isfinite(amplitude)) return 0;
 if(amplitude<=0) api.hapticStop(int(hand));
 else api.haptic(int(hand),float(std::max(0.,std::min(1.,seconds))),float(std::max(0.,std::min(320.,frequency))),float(std::min(1.,amplitude)));
 return 0;
}
static int Open(lua_State* L) {
 api.create(L,0,9);
 struct Entry {const char* name;Function function;};
 const Entry entries[]={{"IsActive",IsActive},{"GetHeadPose",Head},{"GetHandPose",Hand},{"GetAimPose",Aim},
 {"GetPrimaryHand",Primary},{"SetPrimaryHand",SetPrimary},{"GetAnalog",Analog},{"GetDigital",Digital},{"TriggerHaptic",Haptic}};
 for(const auto& entry:entries) {api.pushClosure(L,entry.function,0);api.setField(L,-2,entry.name);}
 api.pushValue(L,-1);api.setField(L,-10002,"vr");
 LOG("VRLUA own compatibility module opened; live XR input and actual Vector/Angle userdata");
 return 1;
}
static bool Install(void* xr) {
 void* lua=dlopen("liblua_shared.so",RTLD_NOW|RTLD_LOCAL);
 if(!lua) {LOG("VRLUA missing upstream Lua library");return false;}
 bool ok=true;
 #define GQUEST_LUA_BIND(field,lib,symbol) api.field=reinterpret_cast<decltype(api.field)>(dlsym(lib,symbol));ok=ok && api.field
 GQUEST_LUA_BIND(create,lua,"lua_createtable");
 GQUEST_LUA_BIND(pushClosure,lua,"lua_pushcclosure");
 GQUEST_LUA_BIND(setField,lua,"lua_setfield");
 GQUEST_LUA_BIND(pushValue,lua,"lua_pushvalue");
 GQUEST_LUA_BIND(pushBool,lua,"lua_pushboolean");
 GQUEST_LUA_BIND(pushNumber,lua,"lua_pushnumber");
 GQUEST_LUA_BIND(pushInteger,lua,"lua_pushinteger");
 GQUEST_LUA_BIND(optInteger,lua,"luaL_optinteger");
 GQUEST_LUA_BIND(optNumber,lua,"luaL_optnumber");
 GQUEST_LUA_BIND(checkString,lua,"luaL_checklstring");
 GQUEST_LUA_BIND(pushVector,lua,"_ZN4glua10PushVectorEP9lua_StateRK6Vector");
 GQUEST_LUA_BIND(pushAngle,lua,"_ZN4glua9PushAngleEP9lua_StateRK6QAngle");
 GQUEST_LUA_BIND(locate,xr,"VRXR_LocateInput");
 GQUEST_LUA_BIND(booted,xr,"VRXR_IsBootstrapped");
 GQUEST_LUA_BIND(running,xr,"VRXR_IsSessionRunning");
 GQUEST_LUA_BIND(primary,xr,"VRXR_GetPrimaryHand");
 GQUEST_LUA_BIND(setPrimary,xr,"VRXR_SetPrimaryHand");
 GQUEST_LUA_BIND(findSet,xr,"VRXR_FindActionSet");
 GQUEST_LUA_BIND(findAction,xr,"VRXR_FindAction");
 GQUEST_LUA_BIND(analog,xr,"VRXR_GetAnalogAction");
 GQUEST_LUA_BIND(digital,xr,"VRXR_GetDigitalAction");
 GQUEST_LUA_BIND(haptic,xr,"VRXR_Haptic");
 GQUEST_LUA_BIND(hapticStop,xr,"VRXR_HapticStop");
 #undef GQUEST_LUA_BIND
 using Register=void(*)(const char*,Function);
 auto reg=reinterpret_cast<Register>(dlsym(lua,"_ZN4glua20RegisterNativeModuleEPKcPFiP9lua_StateE"));
 if(!ok || !reg) {LOG("VRLUA required compatibility symbol missing");return false;}
 reg("gquest_vr",Open);
 LOG("VRLUA registered own module against official0.1.30 Lua library");
 // Module/function pointers live until launcher teardown; keep library pinned.
 return true;
}
}
