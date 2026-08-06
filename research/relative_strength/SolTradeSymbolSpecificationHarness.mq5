#property strict
#property version "1.000"
#property description "Tester-only broker symbol specification exporter; no prices or trading"

input string OutputRoot="SolTrade\\Phase6\\V26SymbolSpecs\\EURUSD";
bool g_ok=false;

int OnInit()
  {
   if(!MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION)||(int)TerminalInfoInteger(TERMINAL_BUILD)!=6090||AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo")
      return INIT_PARAMETERS_INCORRECT;
   int h=FileOpen(OutputRoot+"\\symbol-specification.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE)return INIT_FAILED;
   FileWrite(h,"field","value");
   FileWrite(h,"schema","SOLTRADE_PHASE6_V26_SYMBOL_SPECIFICATION_V1");
   FileWrite(h,"symbol",_Symbol);
   FileWrite(h,"digits",(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
   FileWrite(h,"point",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_POINT),12));
   FileWrite(h,"trade_tick_size",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),12));
   FileWrite(h,"trade_tick_value",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE),12));
   FileWrite(h,"contract_size",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),4));
   FileWrite(h,"volume_min",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),8));
   FileWrite(h,"volume_max",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),8));
   FileWrite(h,"volume_step",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),8));
   FileWrite(h,"stops_level_points",(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL));
   FileWrite(h,"freeze_level_points",(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL));
   FileWrite(h,"swap_mode",(int)SymbolInfoInteger(_Symbol,SYMBOL_SWAP_MODE));
   FileWrite(h,"swap_long",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_SWAP_LONG),8));
   FileWrite(h,"swap_short",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_SWAP_SHORT),8));
   FileWrite(h,"swap_rollover3_day",(int)SymbolInfoInteger(_Symbol,SYMBOL_SWAP_ROLLOVER3DAYS));
   FileWrite(h,"price_fields_written","NO");
   FileWrite(h,"orders_or_positions","ZERO");
   FileWrite(h,"status","PASS");
   FileClose(h);
   g_ok=true;
   return INIT_SUCCEEDED;
  }
void OnTick(){}
double OnTester(){return g_ok?1.0:0.0;}
