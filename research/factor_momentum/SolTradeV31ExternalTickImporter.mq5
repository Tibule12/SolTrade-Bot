#property strict
#property version "1.000"
#property description "V31 trade-disabled importer and exact timestamp/bid/ask parity audit"

string CONTROL="SolTrade\\Phase6\\V31ExternalImport\\control.csv";
string CANONICAL[7]={"EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY"};

string ResearchSymbol(const string canonical_symbol)
  {
   if(canonical_symbol=="EURUSD")return "EURUSD.V31";
   if(canonical_symbol=="GBPUSD")return "GBPUSD.V31";
   if(canonical_symbol=="AUDUSD")return "AUDUSD.V31";
   if(canonical_symbol=="NZDUSD")return "NZDUSD.V31";
   if(canonical_symbol=="USDCAD")return "USDCAD.V31";
   if(canonical_symbol=="USDCHF")return "USDCHF.V31";
   if(canonical_symbol=="USDJPY")return "USDJPY.V31";
   return "";
  }
string TSms(long value){return value>0?TimeToString((datetime)(value/1000),TIME_DATE|TIME_SECONDS)+StringFormat(".%03d",(int)(value%1000)):"NONE";}
bool KnownCanonical(const string symbol){for(int i=0;i<7;i++)if(CANONICAL[i]==symbol)return true;return false;}

bool LoadControl(string &canonical,string &import_root,string &output_root,long &expected)
  {
   int h=FileOpen(CONTROL,FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return false;
   string schema=FileReadString(h);canonical=FileReadString(h);import_root=FileReadString(h);output_root=FileReadString(h);expected=(long)StringToInteger(FileReadString(h));FileClose(h);
   return schema=="SOLTRADE_PHASE6_V31_IMPORT_CONTROL_V1"&&KnownCanonical(canonical)&&ResearchSymbol(canonical)!=""&&expected>0;
  }

int SessionMismatches(const string canonical,const string research)
  {
   int bad=0;
   for(int day=0;day<7;day++)
     {
      for(uint index=0;index<32;index++){datetime cf=0,ct=0,rf=0,rt=0;bool ca=SymbolInfoSessionQuote(canonical,(ENUM_DAY_OF_WEEK)day,index,cf,ct);bool ra=SymbolInfoSessionQuote(research,(ENUM_DAY_OF_WEEK)day,index,rf,rt);if(ca!=ra||(ca&&(cf!=rf||ct!=rt)))bad++;if(!ca&&!ra)break;}
      for(uint index=0;index<32;index++){datetime cf=0,ct=0,rf=0,rt=0;bool ca=SymbolInfoSessionTrade(canonical,(ENUM_DAY_OF_WEEK)day,index,cf,ct);bool ra=SymbolInfoSessionTrade(research,(ENUM_DAY_OF_WEEK)day,index,rf,rt);if(ca!=ra||(ca&&(cf!=rf||ct!=rt)))bad++;if(!ca&&!ra)break;}
     }
   return bad;
  }
int PropertyMismatches(const string canonical,const string research)
  {
   int bad=0;
   ENUM_SYMBOL_INFO_INTEGER ints[]={SYMBOL_DIGITS,SYMBOL_SPREAD_FLOAT,SYMBOL_TRADE_CALC_MODE,SYMBOL_TRADE_MODE,SYMBOL_TRADE_STOPS_LEVEL,SYMBOL_TRADE_FREEZE_LEVEL,SYMBOL_TRADE_EXEMODE,SYMBOL_SWAP_MODE,SYMBOL_SWAP_ROLLOVER3DAYS,SYMBOL_ORDER_MODE,SYMBOL_FILLING_MODE,SYMBOL_EXPIRATION_MODE};
   for(int i=0;i<ArraySize(ints);i++)if(SymbolInfoInteger(canonical,ints[i])!=SymbolInfoInteger(research,ints[i]))bad++;
   ENUM_SYMBOL_INFO_DOUBLE doubles[]={SYMBOL_POINT,SYMBOL_TRADE_TICK_SIZE,SYMBOL_TRADE_CONTRACT_SIZE,SYMBOL_VOLUME_MIN,SYMBOL_VOLUME_MAX,SYMBOL_VOLUME_STEP,SYMBOL_VOLUME_LIMIT,SYMBOL_SWAP_LONG,SYMBOL_SWAP_SHORT};
   for(int i=0;i<ArraySize(doubles);i++)if(SymbolInfoDouble(canonical,doubles[i])!=SymbolInfoDouble(research,doubles[i]))bad++;
   ENUM_SYMBOL_INFO_STRING strings[]={SYMBOL_CURRENCY_BASE,SYMBOL_CURRENCY_PROFIT,SYMBOL_CURRENCY_MARGIN,SYMBOL_BASIS};
   for(int i=0;i<ArraySize(strings);i++)if(SymbolInfoString(canonical,strings[i])!=SymbolInfoString(research,strings[i]))bad++;
   return bad+SessionMismatches(canonical,research);
  }
bool SameRequiredTick(const MqlTick &a,const MqlTick &b){return a.time==b.time&&a.time_msc==b.time_msc&&a.bid==b.bid&&a.ask==b.ask;}

int OnInit()
  {
   bool safe=!(bool)MQLInfoInteger(MQL_TESTER)&&AccountInfoString(ACCOUNT_SERVER)=="FPMarketsSC-Demo"&&(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO&&!(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)&&!(bool)MQLInfoInteger(MQL_TRADE_ALLOWED)&&OrdersTotal()==0&&PositionsTotal()==0;
   if(!safe){Print("SOLTRADE_V31_EXTERNAL_IMPORT_REJECTED | reason=CONNECTED_SAFETY_PREFLIGHT");return INIT_FAILED;}
   string canonical="",import_root="",output_root="";long expected=0;if(!LoadControl(canonical,import_root,output_root,expected)){Print("SOLTRADE_V31_EXTERNAL_IMPORT_CONTROL_FAILED | error=",GetLastError());return INIT_FAILED;}
   string research=ResearchSymbol(canonical);bool custom=false;
   if(SymbolExist(research,custom))
     {
      if(!custom){Print("SOLTRADE_V31_EXTERNAL_IMPORT_REFUSE_NONCUSTOM | ",research);return INIT_FAILED;}
      SymbolSelect(research,false);CustomTicksDelete(research,0,LONG_MAX);CustomRatesDelete(research,0,LONG_MAX);
      if(!CustomSymbolDelete(research)){Print("SOLTRADE_V31_EXTERNAL_IMPORT_CLEANUP_FAILED | ",research," | error=",GetLastError());return INIT_FAILED;}
     }
   if(!SymbolSelect(canonical,true)||!CustomSymbolCreate(research,"V31_EXTERNAL",canonical)){Print("SOLTRADE_V31_EXTERNAL_IMPORT_CREATE_FAILED | ",research," | error=",GetLastError());return INIT_FAILED;}
   if(!CustomSymbolSetDouble(research,SYMBOL_TRADE_TICK_SIZE,SymbolInfoDouble(canonical,SYMBOL_TRADE_TICK_SIZE))){Print("SOLTRADE_V31_EXTERNAL_PROPERTY_CONFIGURATION_FAILED | ",research," | error=",GetLastError());return INIT_FAILED;}
   int initial_property_mismatches=PropertyMismatches(canonical,research);if(initial_property_mismatches!=0){Print("SOLTRADE_V31_EXTERNAL_INITIAL_PROPERTY_MISMATCH | ",research," | count=",initial_property_mismatches);return INIT_FAILED;}
   int daily=FileOpen(output_root+"\\daily-import-parity.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   int summary=FileOpen(output_root+"\\import-summary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   int properties=FileOpen(output_root+"\\symbol-properties.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(daily==INVALID_HANDLE||summary==INVALID_HANDLE||properties==INVALID_HANDLE)return INIT_FAILED;
   FileWrite(daily,"schema","canonical_symbol","research_symbol","server_civil_date","source_records","imported_ticks","reloaded_ticks","exact_timestamp_bid_ask_mismatches","first_tick","last_tick","replace_error","reload_error");
   FileWrite(summary,"field","value");
   FileWrite(properties,"schema","canonical_symbol","research_symbol","digits","point","tick_size","contract_size","volume_min","volume_max","volume_step","calc_mode","base_currency","profit_currency","margin_currency","swap_mode","swap_rollover3day","swap_long","swap_short","property_or_session_mismatches","configured_before_import");
   double point=SymbolInfoDouble(research,SYMBOL_POINT);long total_source=0,total_imported=0,total_reloaded=0,total_mismatches=0;int day_files=0;long global_first=0,global_last=0;
   for(datetime day=D'2018.01.01 00:00:00';day<D'2025.01.01 00:00:00';day+=24*3600)
     {
      string date=TimeToString(day,TIME_DATE);StringReplace(date,".","-");string file=import_root+"\\"+date+".bin";
      int h=FileOpen(file,FILE_READ|FILE_BIN|FILE_COMMON);if(h==INVALID_HANDLE){Print("SOLTRADE_V31_EXTERNAL_DAY_FILE_MISSING | ",canonical," | ",date," | error=",GetLastError());FileClose(daily);FileClose(summary);FileClose(properties);return INIT_FAILED;}
      long bytes=(long)FileSize(h);if(bytes<0||bytes%16!=0){Print("SOLTRADE_V31_EXTERNAL_DAY_FILE_SIZE_INVALID | ",canonical," | ",date," | bytes=",bytes);FileClose(h);FileClose(daily);FileClose(summary);FileClose(properties);return INIT_FAILED;}
      int count=(int)(bytes/16);MqlTick source[];ArrayResize(source,count);
      for(int j=0;j<count;j++)
        {
         long time_msc=FileReadLong(h);int bid_points=FileReadInteger(h,INT_VALUE);int ask_points=FileReadInteger(h,INT_VALUE);
         source[j].time=(datetime)(time_msc/1000);source[j].time_msc=time_msc;source[j].bid=NormalizeDouble(bid_points*point,(int)SymbolInfoInteger(research,SYMBOL_DIGITS));source[j].ask=NormalizeDouble(ask_points*point,(int)SymbolInfoInteger(research,SYMBOL_DIGITS));source[j].last=0;source[j].volume=0;source[j].volume_real=0;source[j].flags=TICK_FLAG_BID|TICK_FLAG_ASK;
        }
      FileClose(h);long from=(long)day*1000,to=(long)(day+24*3600)*1000-1;ResetLastError();int imported=CustomTicksReplace(research,from,to,source,count);int replace_error=GetLastError();
      if(imported!=count){Print("SOLTRADE_V31_EXTERNAL_IMPORT_FAILED | ",research," | ",date," | source=",count," | imported=",imported," | error=",replace_error);FileClose(daily);FileClose(summary);FileClose(properties);return INIT_FAILED;}
      MqlTick reloaded[];ResetLastError();int got=CopyTicksRange(research,reloaded,COPY_TICKS_ALL,(ulong)from,(ulong)to);int reload_error=GetLastError();long mismatches=MathAbs(got-count);int compare=MathMin(got,count);for(int j=0;j<compare;j++)if(!SameRequiredTick(source[j],reloaded[j]))mismatches++;
      if(count>0){if(global_first==0)global_first=source[0].time_msc;global_last=source[count-1].time_msc;}
      total_source+=count;total_imported+=imported;total_reloaded+=got;total_mismatches+=mismatches;day_files++;
      FileWrite(daily,"SOLTRADE_PHASE6_V31_DAILY_IMPORT_PARITY_V1",canonical,research,date,count,imported,got,mismatches,count>0?TSms(source[0].time_msc):"NONE",count>0?TSms(source[count-1].time_msc):"NONE",replace_error,reload_error);FileFlush(daily);
      ArrayFree(source);ArrayFree(reloaded);
      if(mismatches!=0){Print("SOLTRADE_V31_EXTERNAL_TICK_PARITY_FAILED | ",research," | ",date," | mismatches=",mismatches);FileClose(daily);FileClose(summary);FileClose(properties);return INIT_FAILED;}
      if(day_files%365==0)Print("SOLTRADE_V31_EXTERNAL_IMPORT_PROGRESS | ",canonical," | days=",day_files," | ticks=",total_source);
     }
   int final_property_mismatches=PropertyMismatches(canonical,research);
   FileWrite(properties,"SOLTRADE_PHASE6_V31_PROPERTY_V1",canonical,research,(int)SymbolInfoInteger(research,SYMBOL_DIGITS),DoubleToString(SymbolInfoDouble(research,SYMBOL_POINT),10),DoubleToString(SymbolInfoDouble(research,SYMBOL_TRADE_TICK_SIZE),10),DoubleToString(SymbolInfoDouble(research,SYMBOL_TRADE_CONTRACT_SIZE),2),DoubleToString(SymbolInfoDouble(research,SYMBOL_VOLUME_MIN),8),DoubleToString(SymbolInfoDouble(research,SYMBOL_VOLUME_MAX),8),DoubleToString(SymbolInfoDouble(research,SYMBOL_VOLUME_STEP),8),(int)SymbolInfoInteger(research,SYMBOL_TRADE_CALC_MODE),SymbolInfoString(research,SYMBOL_CURRENCY_BASE),SymbolInfoString(research,SYMBOL_CURRENCY_PROFIT),SymbolInfoString(research,SYMBOL_CURRENCY_MARGIN),(int)SymbolInfoInteger(research,SYMBOL_SWAP_MODE),(int)SymbolInfoInteger(research,SYMBOL_SWAP_ROLLOVER3DAYS),DoubleToString(SymbolInfoDouble(research,SYMBOL_SWAP_LONG),8),DoubleToString(SymbolInfoDouble(research,SYMBOL_SWAP_SHORT),8),final_property_mismatches,"YES");
   bool pass=day_files==2557&&total_source==expected&&total_source==total_imported&&total_source==total_reloaded&&total_mismatches==0&&final_property_mismatches==0&&OrdersTotal()==0&&PositionsTotal()==0;
   FileWrite(summary,"schema","SOLTRADE_PHASE6_V31_IMPORT_SUMMARY_V1");FileWrite(summary,"status",pass?"PASS":"FAIL");FileWrite(summary,"canonical_symbol",canonical);FileWrite(summary,"research_symbol",research);FileWrite(summary,"day_files",day_files);FileWrite(summary,"expected_ticks",expected);FileWrite(summary,"source_records",total_source);FileWrite(summary,"imported_ticks",total_imported);FileWrite(summary,"reloaded_ticks",total_reloaded);FileWrite(summary,"exact_timestamp_bid_ask_mismatches",total_mismatches);FileWrite(summary,"first_tick",TSms(global_first));FileWrite(summary,"last_tick",TSms(global_last));FileWrite(summary,"property_or_session_mismatches",final_property_mismatches);FileWrite(summary,"orders",OrdersTotal());FileWrite(summary,"positions",PositionsTotal());FileWrite(summary,"trade_api_calls","NONE");FileWrite(summary,"pnl_calculated","NO");
   FileClose(daily);FileClose(summary);FileClose(properties);
   Print("SOLTRADE_V31_EXTERNAL_IMPORT_COMPLETE | status=",pass?"PASS":"FAIL"," | ",canonical," -> ",research," | ticks=",total_source," | mismatches=",total_mismatches," | orders=",OrdersTotal()," | positions=",PositionsTotal()," | pnl=NO");TerminalClose(pass?0:1);return pass?INIT_SUCCEEDED:INIT_FAILED;
  }
void OnTick(){}
