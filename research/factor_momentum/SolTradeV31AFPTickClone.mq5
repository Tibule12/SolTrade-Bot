#property strict
#property version "1.000"
#property description "V31A connected trade-disabled FP Markets tick clone and exact parity audit"

string CANONICAL[7]={"EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY"};
string RESEARCH[7]={"EURUSD.V31","GBPUSD.V31","AUDUSD.V31","NZDUSD.V31","USDCAD.V31","USDCHF.V31","USDJPY.V31"};
datetime WARMUP_FROM=D'2024.12.01 00:00:00';
datetime TICK_FROM=D'2025.01.02 00:00:00';
datetime END_EXCLUSIVE=D'2026.08.01 00:00:00';
string ROOT="SolTrade\\Phase6\\V31AClone";
string WARMUP_ROOT="SolTrade\\Phase6\\V31AWarmup";

string TSms(long value){return value>0?TimeToString((datetime)(value/1000),TIME_DATE|TIME_SECONDS)+StringFormat(".%03d",(int)(value%1000)):"NONE";}

int LoadWarmupRates(const string symbol,MqlRates &rates[])
  {
   int h=FileOpen(WARMUP_ROOT+"\\"+symbol+".csv",FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE)return -1;
   for(int i=0;i<9;i++)FileReadString(h);
   while(!FileIsEnding(h))
     {
      string schema=FileReadString(h);if(schema=="")break;
      int n=ArraySize(rates);ArrayResize(rates,n+1,2048);
      rates[n].time=StringToTime(FileReadString(h));
      rates[n].open=StringToDouble(FileReadString(h));rates[n].high=StringToDouble(FileReadString(h));rates[n].low=StringToDouble(FileReadString(h));rates[n].close=StringToDouble(FileReadString(h));
      rates[n].tick_volume=(long)StringToInteger(FileReadString(h));rates[n].spread=(int)StringToInteger(FileReadString(h));rates[n].real_volume=(long)StringToInteger(FileReadString(h));
     }
   FileClose(h);return ArraySize(rates);
  }

int CopyTicksWait(const string symbol,MqlTick &ticks[],const ulong from,const ulong to)
  {
   for(int attempt=0;attempt<180;attempt++)
     {
      ResetLastError();int count=CopyTicksRange(symbol,ticks,COPY_TICKS_ALL,from,to);
      if(count>=0)return count;
      Sleep(1000);
     }
   return -1;
  }

bool SameTick(const MqlTick &a,const MqlTick &b)
  {
   return a.time==b.time&&a.time_msc==b.time_msc&&a.bid==b.bid&&a.ask==b.ask&&a.last==b.last&&a.volume==b.volume&&a.volume_real==b.volume_real&&a.flags==b.flags;
  }

int SessionMismatches(const string canonical,const string research)
  {
   int bad=0;
   for(int day=0;day<7;day++)
     {
      for(uint index=0;index<32;index++)
        {
         datetime cf=0,ct=0,rf=0,rt=0;
         bool ca=SymbolInfoSessionQuote(canonical,(ENUM_DAY_OF_WEEK)day,index,cf,ct);
         bool ra=SymbolInfoSessionQuote(research,(ENUM_DAY_OF_WEEK)day,index,rf,rt);
         if(ca!=ra||(ca&&(cf!=rf||ct!=rt)))bad++;
         if(!ca&&!ra)break;
        }
      for(uint index=0;index<32;index++)
        {
         datetime cf=0,ct=0,rf=0,rt=0;
         bool ca=SymbolInfoSessionTrade(canonical,(ENUM_DAY_OF_WEEK)day,index,cf,ct);
         bool ra=SymbolInfoSessionTrade(research,(ENUM_DAY_OF_WEEK)day,index,rf,rt);
         if(ca!=ra||(ca&&(cf!=rf||ct!=rt)))bad++;
         if(!ca&&!ra)break;
        }
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

int OnInit()
  {
   bool safe=!(bool)MQLInfoInteger(MQL_TESTER)&&AccountInfoString(ACCOUNT_SERVER)=="FPMarketsSC-Demo"&&(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO&&!(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)&&!(bool)MQLInfoInteger(MQL_TRADE_ALLOWED)&&OrdersTotal()==0&&PositionsTotal()==0;
   if(!safe){Print("SOLTRADE_V31A_CLONE_REJECTED | reason=CONNECTED_SAFETY_PREFLIGHT");return INIT_FAILED;}
   int properties=FileOpen(ROOT+"\\symbol-properties.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   int days=FileOpen(ROOT+"\\daily-tick-parity.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   int summary=FileOpen(ROOT+"\\clone-summary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(properties==INVALID_HANDLE||days==INVALID_HANDLE||summary==INVALID_HANDLE)return INIT_FAILED;
   FileWrite(properties,"schema","canonical_symbol","research_symbol","digits","point","tick_size","contract_size","volume_min","volume_max","volume_step","calc_mode","base_currency","profit_currency","margin_currency","swap_mode","swap_rollover3day","swap_long","swap_short","canonical_tick_value","research_tick_value","canonical_tick_value_profit","research_tick_value_profit","canonical_tick_value_loss","research_tick_value_loss","writable_property_or_session_mismatches","checked_after_import","calculated_tick_values_checked_in_tester_parity");
   FileWrite(days,"schema","canonical_symbol","research_symbol","date","source_ticks","imported_ticks","reloaded_ticks","exact_tick_mismatches","first_tick","last_tick","copy_error","replace_error","reload_error");
   FileWrite(summary,"schema","canonical_symbol","research_symbol","warmup_m1_rates","source_ticks","imported_ticks","reloaded_ticks","exact_tick_mismatches","property_or_session_mismatches","first_tick","last_tick","status","orders","positions","trade_api_calls","pnl_calculated");
   int property_mismatches[7];ArrayInitialize(property_mismatches,0);
   for(int i=0;i<7;i++)
     {
      bool custom=false;if(SymbolExist(RESEARCH[i],custom))
        {
         if(!custom){Print("SOLTRADE_V31A_CLONE_REFUSE_NONCUSTOM | ",RESEARCH[i]);FileClose(properties);FileClose(days);FileClose(summary);return INIT_FAILED;}
         SymbolSelect(RESEARCH[i],false);CustomTicksDelete(RESEARCH[i],0,LONG_MAX);CustomRatesDelete(RESEARCH[i],0,LONG_MAX);
         if(!CustomSymbolDelete(RESEARCH[i])){Print("SOLTRADE_V31A_EMPTY_CLEANUP_FAILED | ",RESEARCH[i]," | error=",GetLastError());FileClose(properties);FileClose(days);FileClose(summary);return INIT_FAILED;}
        }
      if(!SymbolSelect(CANONICAL[i],true)||!CustomSymbolCreate(RESEARCH[i],"V31A",CANONICAL[i])){Print("SOLTRADE_V31A_CLONE_CREATE_FAILED | ",RESEARCH[i]," | error=",GetLastError());FileClose(properties);FileClose(days);FileClose(summary);return INIT_FAILED;}
      bool configured=CustomSymbolSetDouble(RESEARCH[i],SYMBOL_TRADE_TICK_SIZE,SymbolInfoDouble(CANONICAL[i],SYMBOL_TRADE_TICK_SIZE));
      if(!configured){Print("SOLTRADE_V31A_PROPERTY_CONFIGURATION_FAILED | ",RESEARCH[i]," | error=",GetLastError());FileClose(properties);FileClose(days);FileClose(summary);return INIT_FAILED;}
      int mismatch=PropertyMismatches(CANONICAL[i],RESEARCH[i]);property_mismatches[i]=mismatch;
      if(mismatch!=0){Print("SOLTRADE_V31A_CLONE_PROPERTY_MISMATCH | ",RESEARCH[i]," | count=",mismatch);FileClose(properties);FileClose(days);FileClose(summary);return INIT_FAILED;}
     }
   FileFlush(properties);
   for(int i=0;i<7;i++)
     {
      MqlRates rates[];int warmup=LoadWarmupRates(CANONICAL[i],rates);int warmup_error=GetLastError();
      if(warmup<=0||CustomRatesReplace(RESEARCH[i],WARMUP_FROM,TICK_FROM-1,rates,warmup)!=warmup){Print("SOLTRADE_V31A_WARMUP_COPY_FAILED | ",CANONICAL[i]," | rates=",warmup," | error=",warmup_error,"/",GetLastError());FileClose(properties);FileClose(days);FileClose(summary);return INIT_FAILED;}
      ArrayFree(rates);long total_source=0,total_imported=0,total_reloaded=0,total_mismatch=0,first=0,last=0;
      for(datetime day=TICK_FROM;day<END_EXCLUSIVE;day+=24*3600)
        {
         ulong from=(ulong)day*1000,to=(ulong)MathMin((long)(day+24*3600),(long)END_EXCLUSIVE)*1000-1;
         MqlTick source[];ResetLastError();int count=CopyTicksWait(CANONICAL[i],source,from,to);int copy_error=GetLastError();
         if(count<0){Print("SOLTRADE_V31A_SOURCE_COPY_FAILED | ",CANONICAL[i]," | ",TimeToString(day,TIME_DATE)," | error=",copy_error);FileClose(properties);FileClose(days);FileClose(summary);return INIT_FAILED;}
         int imported=0,replace_error=0;if(count>0){ResetLastError();imported=CustomTicksReplace(RESEARCH[i],(long)from,(long)to,source,count);replace_error=GetLastError();if(imported!=count){Print("SOLTRADE_V31A_IMPORT_FAILED | ",RESEARCH[i]," | ",TimeToString(day,TIME_DATE)," | source=",count," | imported=",imported," | error=",replace_error);FileClose(properties);FileClose(days);FileClose(summary);return INIT_FAILED;}}
         MqlTick reloaded[];ResetLastError();int got=CopyTicksRange(RESEARCH[i],reloaded,COPY_TICKS_ALL,from,to);int reload_error=GetLastError();long mismatches=0;if(got!=count)mismatches+=MathAbs(got-count);int compare=MathMin(got,count);for(int j=0;j<compare;j++)if(!SameTick(source[j],reloaded[j]))mismatches++;
         if(count>0){if(first==0)first=source[0].time_msc;last=source[count-1].time_msc;}
         total_source+=count;total_imported+=imported;total_reloaded+=got;total_mismatch+=mismatches;
         FileWrite(days,"SOLTRADE_PHASE6_V31A_DAILY_TICK_PARITY_V1",CANONICAL[i],RESEARCH[i],TimeToString(day,TIME_DATE),count,imported,got,mismatches,count>0?TSms(source[0].time_msc):"NONE",count>0?TSms(source[count-1].time_msc):"NONE",copy_error,replace_error,reload_error);
         ArrayFree(source);ArrayFree(reloaded);
         if(mismatches!=0){Print("SOLTRADE_V31A_TICK_PARITY_FAILED | ",RESEARCH[i]," | ",TimeToString(day,TIME_DATE)," | mismatches=",mismatches);FileClose(properties);FileClose(days);FileClose(summary);return INIT_FAILED;}
        }
      property_mismatches[i]=PropertyMismatches(CANONICAL[i],RESEARCH[i]);
      FileWrite(properties,"SOLTRADE_PHASE6_V31A_PROPERTY_V1",CANONICAL[i],RESEARCH[i],(int)SymbolInfoInteger(RESEARCH[i],SYMBOL_DIGITS),DoubleToString(SymbolInfoDouble(RESEARCH[i],SYMBOL_POINT),10),DoubleToString(SymbolInfoDouble(RESEARCH[i],SYMBOL_TRADE_TICK_SIZE),10),DoubleToString(SymbolInfoDouble(RESEARCH[i],SYMBOL_TRADE_CONTRACT_SIZE),2),DoubleToString(SymbolInfoDouble(RESEARCH[i],SYMBOL_VOLUME_MIN),8),DoubleToString(SymbolInfoDouble(RESEARCH[i],SYMBOL_VOLUME_MAX),8),DoubleToString(SymbolInfoDouble(RESEARCH[i],SYMBOL_VOLUME_STEP),8),(int)SymbolInfoInteger(RESEARCH[i],SYMBOL_TRADE_CALC_MODE),SymbolInfoString(RESEARCH[i],SYMBOL_CURRENCY_BASE),SymbolInfoString(RESEARCH[i],SYMBOL_CURRENCY_PROFIT),SymbolInfoString(RESEARCH[i],SYMBOL_CURRENCY_MARGIN),(int)SymbolInfoInteger(RESEARCH[i],SYMBOL_SWAP_MODE),(int)SymbolInfoInteger(RESEARCH[i],SYMBOL_SWAP_ROLLOVER3DAYS),DoubleToString(SymbolInfoDouble(RESEARCH[i],SYMBOL_SWAP_LONG),8),DoubleToString(SymbolInfoDouble(RESEARCH[i],SYMBOL_SWAP_SHORT),8),DoubleToString(SymbolInfoDouble(CANONICAL[i],SYMBOL_TRADE_TICK_VALUE),12),DoubleToString(SymbolInfoDouble(RESEARCH[i],SYMBOL_TRADE_TICK_VALUE),12),DoubleToString(SymbolInfoDouble(CANONICAL[i],SYMBOL_TRADE_TICK_VALUE_PROFIT),12),DoubleToString(SymbolInfoDouble(RESEARCH[i],SYMBOL_TRADE_TICK_VALUE_PROFIT),12),DoubleToString(SymbolInfoDouble(CANONICAL[i],SYMBOL_TRADE_TICK_VALUE_LOSS),12),DoubleToString(SymbolInfoDouble(RESEARCH[i],SYMBOL_TRADE_TICK_VALUE_LOSS),12),property_mismatches[i],"YES","YES");FileFlush(properties);
      if(property_mismatches[i]!=0){Print("SOLTRADE_V31A_CLONE_FINAL_PROPERTY_MISMATCH | ",RESEARCH[i]," | count=",property_mismatches[i]);FileClose(properties);FileClose(days);FileClose(summary);return INIT_FAILED;}
      FileWrite(summary,"SOLTRADE_PHASE6_V31A_CLONE_SUMMARY_V1",CANONICAL[i],RESEARCH[i],warmup,total_source,total_imported,total_reloaded,total_mismatch,property_mismatches[i],TSms(first),TSms(last),(total_source>0&&total_source==total_imported&&total_source==total_reloaded&&total_mismatch==0)?"PASS":"FAIL",OrdersTotal(),PositionsTotal(),"NONE","NO");FileFlush(summary);FileFlush(days);
      Print("SOLTRADE_V31A_CLONE_SYMBOL_COMPLETE | ",CANONICAL[i]," -> ",RESEARCH[i]," | ticks=",total_source," | mismatches=",total_mismatch);
     }
   FileClose(properties);FileClose(days);FileClose(summary);
   Print("SOLTRADE_V31A_CLONE_COMPLETE | symbols=7 | trade_api_calls=NONE | orders=0 | positions=0 | pnl=NO");TerminalClose(0);return INIT_SUCCEEDED;
  }
void OnTick(){}
