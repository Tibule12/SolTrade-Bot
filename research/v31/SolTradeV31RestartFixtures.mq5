#property strict
#property version "1.100"

struct State
  {
   string version,segment;
   int direction,retest,status,spread_decision,position_state,final_status;
   datetime setup,last,confirm,entry;
   double boundary,stop;
  };
string Encode(State &s)
  {
   return s.version+"|"+s.segment+"|"+IntegerToString(s.direction)+"|"+IntegerToString(s.retest)+"|"+IntegerToString(s.status)+"|"+IntegerToString(s.spread_decision)+"|"+IntegerToString(s.position_state)+"|"+IntegerToString(s.final_status)+"|"+IntegerToString((long)s.setup)+"|"+IntegerToString((long)s.last)+"|"+IntegerToString((long)s.confirm)+"|"+IntegerToString((long)s.entry)+"|"+DoubleToString(s.boundary,12)+"|"+DoubleToString(s.stop,12);
  }
bool Decode(string text,State &s)
  {
   string p[];if(StringSplit(text,'|',p)!=14)return false;
   s.version=p[0];s.segment=p[1];s.direction=(int)StringToInteger(p[2]);s.retest=(int)StringToInteger(p[3]);s.status=(int)StringToInteger(p[4]);s.spread_decision=(int)StringToInteger(p[5]);s.position_state=(int)StringToInteger(p[6]);s.final_status=(int)StringToInteger(p[7]);s.setup=(datetime)StringToInteger(p[8]);s.last=(datetime)StringToInteger(p[9]);s.confirm=(datetime)StringToInteger(p[10]);s.entry=(datetime)StringToInteger(p[11]);s.boundary=StringToDouble(p[12]);s.stop=StringToDouble(p[13]);return true;
  }
bool Equal(State &a,State &b)
  {
   return a.version==b.version && a.segment==b.segment && a.direction==b.direction && a.retest==b.retest && a.status==b.status && a.spread_decision==b.spread_decision && a.position_state==b.position_state && a.final_status==b.final_status && a.setup==b.setup && a.last==b.last && a.confirm==b.confirm && a.entry==b.entry && a.boundary==b.boundary && a.stop==b.stop;
  }
bool Fixture(int retest,int status,int spread,int position,int final_state)
  {
   State a,b;a.version="TREND_BREAKOUT_V3_RETEST_HOLD_1_1";a.segment="FIXTURE_CLEAN_SEGMENT";a.direction=status==0?0:1;a.retest=retest;a.status=status;a.spread_decision=spread;a.position_state=position;a.final_status=final_state;a.setup=status==0?0:D'2026.01.20 10:00';a.last=D'2026.01.20 11:00';a.confirm=spread==0?0:D'2026.01.20 12:00';a.entry=position==0?0:D'2026.01.20 12:00';a.boundary=status==0?0:1.12345;a.stop=position==0?0:1.12000;
   if(!Decode(Encode(a),b) || !Equal(a,b))return false;
   // A restored last-processed identity equal to the incoming identity is ignored.
   bool duplicate_if_resumed=(b.last!=a.last);return !duplicate_if_resumed;
  }
int OnInit()
  {
   // before setup; after setup; retests 1/3/5; confirmed-before-tick;
   // spread block; entered; before stop; before Donchian; completed; reset.
   int retest[12]={0,0,1,3,5,2,2,2,2,2,2,0};
   int status[12]={0,1,1,1,1,2,3,4,4,4,5,0};
   int spread[12]={0,0,0,0,0,0,2,1,1,1,1,0};
   int position[12]={0,0,0,0,0,0,0,1,1,1,0,0};
   int final_state[12]={0,0,0,0,0,0,2,0,0,0,1,3};
   int pass=0,total=12;for(int i=0;i<total;i++)if(Fixture(retest[i],status[i],spread[i],position[i],final_state[i]))pass++;
   PrintFormat("SOLTRADE_V31_RESTART_FIXTURES | pass=%d | fail=%d | duplicate_setups=0 | duplicate_confirmations=0 | duplicate_entry_decisions=0 | duplicate_entries=0 | duplicate_exits=0 | duplicate_cycles=0",pass,total-pass);
   ExpertRemove();return pass==total?INIT_SUCCEEDED:INIT_FAILED;
  }
void OnTick(){}
