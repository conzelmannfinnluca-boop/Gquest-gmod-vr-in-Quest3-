#include <cassert>
#include <cstdio>
#include <vector>
#define LOG(...) do {} while(0)
#include "gquest_vr_lua.h"
using namespace GquestVRLua;
static bool live=true,located=true;
static unsigned char packet[4288]={};
static std::vector<Triple> triples;
static std::vector<double> values;
static ptrdiff_t hand=1;
static int calls=0;
static double duration=0.1,frequency=160,amplitude=0.5;
static void reset() {triples.clear();values.clear();}
int main() {
 api.booted=[](){return live;};api.running=[](){return live;};
 api.locate=[](int64_t time,void* out){assert(time==0);memcpy(out,packet,4288);return located;};
 api.pushVector=[](lua_State*,const Triple& v){triples.push_back(v);};api.pushAngle=api.pushVector;
 api.pushBool=[](lua_State*,int n){values.push_back(n);};
 api.pushNumber=[](lua_State*,double n){values.push_back(n);};
 api.optInteger=[](lua_State*,int,ptrdiff_t){return hand;};
 api.optNumber=[](lua_State*,int index,double){return index==2?duration:index==3?frequency:amplitude;};
 api.checkString=[](lua_State*,int,size_t* n){*n=12;return "trigger_pull";};
 api.findSet=[](const char* set){assert(strcmp(set,"gameplay")==0);return 0;};
 api.findAction=[](int,const char*){return 2;};
 api.analog=[](int s,int a,int h,float* x,float* y,bool* valid){assert(s==0 && a==2 && h==1);*x=0.75;*y=0;*valid=true;return true;};
 api.digital=[](int,int,int,bool* down,bool* changed,bool* valid){*down=true;*changed=true;*valid=true;return true;};
 api.haptic=[](int h,float sec,float hz,float amp){assert(h==1 && sec<=1 && hz<=320 && amp<=1);++calls;};
 api.hapticStop=[](int){++calls;};
 const float pos[]={1,2,3},q[]={0,0,0,1};const uint32_t flags=4;
 for(int side=0;side<2;++side) {
  memcpy(packet+64+56*side,pos,12);memcpy(packet+76+56*side,q,16);memcpy(packet+116+56*side,&flags,4);
  memcpy(packet+176+56*side,pos,12);memcpy(packet+188+56*side,q,16);memcpy(packet+228+56*side,&flags,4);
 }
 memcpy(packet+8,pos,12);memcpy(packet+20,q,16);
 for(int side=0;side<2;++side) {hand=side;for(int kind=0;kind<3;++kind) {
  reset();assert(pose(nullptr,kind)==3 && values.back()==1 && triples.size()==2);
  assert(fabs(triples[0].x-39.370098)<0.001 && fabs(triples[0].y+118.110294)<0.001 && fabs(triples[0].z-78.740196)<0.001);
  assert(triples[1].x==0 && triples[1].y==0 && triples[1].z==0);
 }}
 const float yawQ[]={0,0,0.70710678f,0.70710678f};auto yaw=angles(yawQ);assert(fabs(yaw.y-90)<0.001);
 const float pitchQ[]={0,0.70710678f,0,0.70710678f};auto pitch=angles(pitchQ);assert(fabs(pitch.x-90)<0.03);
 uint32_t zero=0;memcpy(packet+172,&zero,4);reset();Hand(nullptr);assert(values.back()==0 && triples[0].x==0);
 live=false;reset();Head(nullptr);assert(values.back()==0 && triples[0].x==0);live=true;
 located=false;reset();Head(nullptr);assert(values.back()==0);located=true;
 float nan=__builtin_nanf("");memcpy(packet+8,&nan,4);reset();Head(nullptr);assert(values.back()==0);
 hand=1;reset();Analog(nullptr);assert(values[0]==0.75 && values[2]==1);
 reset();Digital(nullptr);assert(values[0]==1 && values[1]==1 && values[2]==1);
 hand=100;reset();Analog(nullptr);assert(values[0]==0 && values[2]==0);
 hand=1;live=false;reset();Digital(nullptr);assert(values[0]==0 && values[2]==0);
 Haptic(nullptr);assert(calls==0);live=true;amplitude=10;duration=5;frequency=500;Haptic(nullptr);assert(calls==1);
 amplitude=0;Haptic(nullptr);assert(calls==2);
 puts("PASS VR Lua bridge: both hands/head/aim, quaternion axes, real validity/finite gates, input routing, inactive/invalid input and bounded haptics");
}
