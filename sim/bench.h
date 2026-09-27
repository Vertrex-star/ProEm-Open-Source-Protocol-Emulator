// =============================================================================
// Project: ProEm - Open Source Protocol Emulator
// File: sim/bench.h
// Type: Test bench (shared by every test)
// Device under test: protocol_emulator (src/top/protocol_emulator.sv)
// Author: Paul Vincent Bezzina
// Language: C++14
// Description:
// =============================================================================

#include "emu_sim.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
#include <deque>
#include <string>
#include <utility>
#include <functional>
using namespace cxxrtl_design;
typedef std::vector<std::pair<unsigned,unsigned>> V;
typedef std::vector<unsigned> B;
p_protocol__emulator t;
int INS_R=16, RET_R=0, CH=0; long cycles=0;
std::deque<int> serial;
std::function<void()> env=[](){};
unsigned pin_in=0;
V got[2]; std::vector<unsigned> status[2]; std::vector<unsigned> global_flags;
int ret_state=0, ret_count=0, ret_bit=0; unsigned ret_byte=0; std::vector<unsigned> ret_bytes;
void ret_decode(){ int r=RET_R?RET_R:INS_R; int lv=t.p_tx__serial.get<bool>();
  if(ret_state==0){ if(!lv){ ret_state=1; ret_count=r/2; } return; }
  if(--ret_count>0) return;
  if(ret_state==1){ if(lv){ ret_state=0; return; } ret_state=2; ret_bit=0; ret_byte=0; ret_count=r; return; }
  if(ret_state==2){ ret_byte|=(unsigned)lv<<ret_bit; ret_bit++; ret_count=r; if(ret_bit==8) ret_state=3; return; }
  if(ret_state==3){ ret_bytes.push_back(ret_byte); ret_state=0;
    if(ret_bytes.size()==2){ unsigned h=ret_bytes[0], v=ret_bytes[1]; ret_bytes.clear();
      if((h&0xC0)==0xC0) global_flags.push_back(v);
      else { int c=(h>>5)&1; unsigned len=h&15; if(len==15) status[c].push_back(v); else got[c].push_back({len,v}); } } } }
void clk(){ int lv=1; if(!serial.empty()){ lv=serial.front(); serial.pop_front(); } t.p_rx__serial.set<bool>(lv); t.p_pin__in.set<unsigned>(pin_in);
  t.p_clk.set<bool>(0); t.step(); t.p_clk.set<bool>(1); t.step(); cycles++; ret_decode(); env(); }
void idle(long n){ for(long i=0;i<n;i++) clk(); }
void put_level(int v){ for(int i=0;i<INS_R;i++) serial.push_back(v); }
void send_byte(unsigned b,int stop=1){ put_level(0); for(int i=0;i<8;i++) put_level((b>>i)&1); put_level(stop); put_level(1); }
void send(const B&bytes){ for(unsigned b:bytes) send_byte(b&0xFF); }
void settle(){ while(!serial.empty()) clk(); idle(8); }
void program(const B&bytes){ send(bytes); settle(); }
void wait_return(long limit=2000000){ long quiet=0; int r=RET_R?RET_R:INS_R; for(long i=0;i<limit;i++){ bool busy=ret_state!=0||!t.p_tx__serial.get<bool>(); clk(); if(busy) quiet=0; else if(++quiet>30*r) break; } }
unsigned op(unsigned o,unsigned n=0){ return (o<<4)|(CH<<3)|(n&7); }
B I_start(unsigned val,unsigned cyc,int cap,int wr,int pin=0){ return {op(1),(unsigned)((wr<<7)|(cap<<6)|(cyc&15)),(unsigned)(pin&7),val&0xFF}; }
B I_hdr(int n,unsigned val,unsigned cyc,int cap,int wr,int grp=0,int sr=0,int any=0){ return {op(2,n),(unsigned)((wr<<7)|(cap<<6)|(grp<<4)|(cyc&15)),(unsigned)((sr<<7)|(any<<6)),val&0xFF}; }
B I_main(unsigned bits,int dir,int we=0,int ack=0,int pin=0,int sr=0){ return {op(3),(unsigned)((dir<<6)|(we<<5)|(ack<<4)|(sr<<3)|(pin&7)),(bits>>8)&0xFF,bits&0xFF}; }
B I_end(unsigned len,int pina,unsigned pat,int pair=0,int inv=0,int err=0,int pinb=0){ return {op(4),(unsigned)((len<<3)|(pina&7)),(unsigned)((pair<<7)|(inv<<6)|(err<<5)|(pinb&7)),(pat>>8)&0xFF,pat&0xFF}; }
B I_wdog(unsigned l){ return {op(5),(l>>8)&0xFF,l&0xFF}; }
B I_order(int msb){ return {op(6,msb)}; }
B I_run(int mode=0){ return {op(7,mode)}; }
B I_halt(){ return {op(8)}; }
B I_clear(){ return {op(9)}; }
B I_line(unsigned code,int pina,int stuff=0,int pinb=0,int inv=0,int sany=0){ unsigned v=(code<<13)|(inv<<12)|((pina&7)<<8)|(sany<<7)|((stuff&15)<<3)|(pinb&7); return {op(0xA),(v>>8)&0xFF,v&0xFF}; }
B I_clock(unsigned src,unsigned div,int pin=0,int edge=0,int idle=0,int etk=0){ unsigned v=(src<<30)|(edge<<28)|(idle<<27)|((pin&7)<<24)|(etk<<22)|(div&0xFFFF); return {op(0xB),(v>>24)&0xFF,(v>>16)&0xFF,(v>>8)&0xFF,v&0xFF}; }
B I_out(int drive,int idle=0,int pair=0,int eop=0,int i2c=0,int cshigh=0){ return {op(0xD),(unsigned)((drive<<6)|(idle<<5)|(pair<<4)|(eop<<3)|(i2c<<2)|(cshigh<<1))}; }
B I_link(unsigned div){ return {op(0xE),(div>>8)&0xFF,div&0xFF}; }
B I_data(unsigned len,unsigned val){ return {op(0xC,len-1),val&0xFF}; }
B I_branch(int rule,int hit,int miss,int src,int block,unsigned mask,unsigned value){ return {op(0xF,rule),(unsigned)((hit<<6)|(miss<<4)|(src<<3)|(block&7)),mask&0xFF,value&0xFF}; }
enum { KEEP=0, GO_READ=1, GO_WRITE=2, ABORT=3 };
B cat(std::initializer_list<B> parts){ B o; for(auto&p:parts) o.insert(o.end(),p.begin(),p.end()); return o; }
enum { SYNC=0, ASYNC=1, GENERATE=2, RECOVER=3 };
void power_on(){ t.p_rx__serial.set<bool>(true); t.p_pin__in.set<unsigned>(pin_in); t.p_rst__n.set<bool>(0); t.step(); t.p_rst__n.set<bool>(1); t.step(); idle(20); send_byte(0x55); settle(); }
bool baud_ok(){ return t.p_baud__locked.get<bool>(); }
unsigned rev8(unsigned v){ unsigned o=0; for(int i=0;i<8;i++) if((v>>i)&1) o|=1u<<(7-i); return o; }
void clear_results(){ for(int c=0;c<2;c++){ got[c].clear(); status[c].clear(); } global_flags.clear(); }
std::string show(const V&v){ std::string s; char b[16]; int n=0; for(auto&e:v){ if(n++==12){ s+=" ..."; break; } snprintf(b,sizeof b," %u:%02X",e.first,e.second); s+=b; } return s; }
std::string showst(const std::vector<unsigned>&v){ std::string s; char b[8]; for(auto x:v){ snprintf(b,sizeof b," %02X",x); s+=b; } return s; }
bool report(const char*name,bool ok,const std::string&detail=""){ printf("  %-54s%s %s\n",name,detail.c_str(),ok?"PASS":"FAIL"); return ok; }
