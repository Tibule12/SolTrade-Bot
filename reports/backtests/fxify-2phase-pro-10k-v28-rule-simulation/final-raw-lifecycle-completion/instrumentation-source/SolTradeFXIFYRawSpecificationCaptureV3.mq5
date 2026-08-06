#property strict
#property version "3.100"
#property script_show_inputs
#property description "FXIFY RAW read-only symbol and account specification capture; no order functions"

string YesNo(const bool value)
  {
   return value ? "YES" : "NO";
  }

string Timestamp(const datetime value)
  {
   return TimeToString(value,TIME_DATE|TIME_SECONDS);
  }

string ResolveSymbol(const string canonical)
  {
   const string expected=canonical+".r";
   if(SymbolSelect(expected,true))
      return expected;
   return "";
  }

void OnStart()
  {
   Print("SOLTRADE_FXIFY_RAW_CAPTURE_PREFLIGHT | action=READ_ONLY_SPECIFICATION_CAPTURE");
   if((bool)MQLInfoInteger(MQL_TESTER) ||
      !(bool)TerminalInfoInteger(TERMINAL_CONNECTED) ||
      AccountInfoString(ACCOUNT_SERVER)!="FXIFY-Server" ||
      (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO ||
      OrdersTotal()!=0 || PositionsTotal()!=0)
     {
      PrintFormat("SOLTRADE_FXIFY_RAW_CAPTURE_REJECTED | connected=%s | server_match=%s | demo=%s | account_trade_allowed=%s | account_expert_allowed=%s | mql_trade_allowed=%s | orders=%d | positions=%d",
                  YesNo((bool)TerminalInfoInteger(TERMINAL_CONNECTED)),
                  YesNo(AccountInfoString(ACCOUNT_SERVER)=="FXIFY-Server"),
                  YesNo((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO),
                  YesNo((bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)),
                  YesNo((bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT)),
                  YesNo((bool)MQLInfoInteger(MQL_TRADE_ALLOWED)),
                  OrdersTotal(),PositionsTotal());
      return;
     }

   const int symbols=FileOpen("soltrade-fxify-raw-symbol-specifications.csv",
                              FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   const int account=FileOpen("soltrade-fxify-raw-account-and-server.csv",
                              FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(symbols==INVALID_HANDLE || account==INVALID_HANDLE)
     {
      if(symbols!=INVALID_HANDLE) FileClose(symbols);
      if(account!=INVALID_HANDLE) FileClose(account);
      PrintFormat("SOLTRADE_FXIFY_RAW_CAPTURE_FILE_FAILED | error=%d",GetLastError());
      return;
     }

   string canonical[7];
   canonical[0]="EURUSD";
   canonical[1]="GBPUSD";
   canonical[2]="AUDUSD";
   canonical[3]="NZDUSD";
   canonical[4]="USDCAD";
   canonical[5]="USDCHF";
   canonical[6]="USDJPY";

   const datetime server_time=TimeTradeServer();
   const datetime gmt_time=TimeGMT();
   FileWrite(account,"schema","field","value");
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","server",AccountInfoString(ACCOUNT_SERVER));
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","company",AccountInfoString(ACCOUNT_COMPANY));
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","account_mode",(int)AccountInfoInteger(ACCOUNT_TRADE_MODE));
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","account_currency",AccountInfoString(ACCOUNT_CURRENCY));
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","account_leverage",(int)AccountInfoInteger(ACCOUNT_LEVERAGE));
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","account_margin_mode",(int)AccountInfoInteger(ACCOUNT_MARGIN_MODE));
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","account_trade_allowed",YesNo((bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)));
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","account_expert_allowed",YesNo((bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT)));
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","terminal_trade_allowed",YesNo((bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)));
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","mql_trade_allowed",YesNo((bool)MQLInfoInteger(MQL_TRADE_ALLOWED)));
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","orders",OrdersTotal());
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","positions",PositionsTotal());
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","terminal_build",(int)TerminalInfoInteger(TERMINAL_BUILD));
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","server_time",Timestamp(server_time));
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","gmt_time",Timestamp(gmt_time));
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","observed_server_utc_offset_seconds",(long)server_time-(long)gmt_time);
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","capture_local_time",Timestamp(TimeLocal()));
   FileWrite(account,"SOLTRADE_FXIFY_RAW_ACCOUNT_V1","credentials_recorded","NO");

   FileWrite(symbols,"schema","canonical_symbol","exact_symbol","capture_server_time",
             "digits","point","tick_size","tick_value","tick_value_profit","tick_value_loss",
             "contract_size","volume_min","volume_step","volume_max","volume_limit",
             "stops_level_points","freeze_level_points","trade_calc_mode","trade_mode",
             "execution_mode","filling_mode","order_mode","margin_initial","margin_maintenance",
             "buy_margin_one_lot","sell_margin_one_lot","bid","ask","spread_price","spread_points",
             "swap_long","swap_short","swap_mode","triple_swap_day","currency_base",
             "currency_profit","currency_margin","select_ok","tick_ok","status");

   bool pass=true;
   for(int i=0;i<7;i++)
     {
      const string exact=ResolveSymbol(canonical[i]);
      MqlTick tick={};
      const bool select_ok=(exact!="");
      const bool tick_ok=select_ok && SymbolInfoTick(exact,tick);
      double buy_margin=0.0,sell_margin=0.0;
      const bool buy_margin_ok=tick_ok && OrderCalcMargin(ORDER_TYPE_BUY,exact,1.0,tick.ask,buy_margin);
      const bool sell_margin_ok=tick_ok && OrderCalcMargin(ORDER_TYPE_SELL,exact,1.0,tick.bid,sell_margin);
      const double point=select_ok ? SymbolInfoDouble(exact,SYMBOL_POINT) : 0.0;
      const double spread=tick_ok ? tick.ask-tick.bid : 0.0;
      const bool row_ok=select_ok && tick_ok && buy_margin_ok && sell_margin_ok && point>0.0;
      pass=pass && row_ok;
      FileWrite(symbols,"SOLTRADE_FXIFY_RAW_SYMBOL_V1",canonical[i],exact,Timestamp(server_time),
                select_ok ? (int)SymbolInfoInteger(exact,SYMBOL_DIGITS) : 0,
                DoubleToString(point,12),
                DoubleToString(select_ok ? SymbolInfoDouble(exact,SYMBOL_TRADE_TICK_SIZE) : 0.0,12),
                DoubleToString(select_ok ? SymbolInfoDouble(exact,SYMBOL_TRADE_TICK_VALUE) : 0.0,12),
                DoubleToString(select_ok ? SymbolInfoDouble(exact,SYMBOL_TRADE_TICK_VALUE_PROFIT) : 0.0,12),
                DoubleToString(select_ok ? SymbolInfoDouble(exact,SYMBOL_TRADE_TICK_VALUE_LOSS) : 0.0,12),
                DoubleToString(select_ok ? SymbolInfoDouble(exact,SYMBOL_TRADE_CONTRACT_SIZE) : 0.0,4),
                DoubleToString(select_ok ? SymbolInfoDouble(exact,SYMBOL_VOLUME_MIN) : 0.0,8),
                DoubleToString(select_ok ? SymbolInfoDouble(exact,SYMBOL_VOLUME_STEP) : 0.0,8),
                DoubleToString(select_ok ? SymbolInfoDouble(exact,SYMBOL_VOLUME_MAX) : 0.0,8),
                DoubleToString(select_ok ? SymbolInfoDouble(exact,SYMBOL_VOLUME_LIMIT) : 0.0,8),
                select_ok ? (int)SymbolInfoInteger(exact,SYMBOL_TRADE_STOPS_LEVEL) : 0,
                select_ok ? (int)SymbolInfoInteger(exact,SYMBOL_TRADE_FREEZE_LEVEL) : 0,
                select_ok ? (int)SymbolInfoInteger(exact,SYMBOL_TRADE_CALC_MODE) : -1,
                select_ok ? (int)SymbolInfoInteger(exact,SYMBOL_TRADE_MODE) : -1,
                select_ok ? (int)SymbolInfoInteger(exact,SYMBOL_TRADE_EXEMODE) : -1,
                select_ok ? (int)SymbolInfoInteger(exact,SYMBOL_FILLING_MODE) : 0,
                select_ok ? (int)SymbolInfoInteger(exact,SYMBOL_ORDER_MODE) : 0,
                DoubleToString(select_ok ? SymbolInfoDouble(exact,SYMBOL_MARGIN_INITIAL) : 0.0,8),
                DoubleToString(select_ok ? SymbolInfoDouble(exact,SYMBOL_MARGIN_MAINTENANCE) : 0.0,8),
                DoubleToString(buy_margin,8),DoubleToString(sell_margin,8),
                DoubleToString(tick_ok ? tick.bid : 0.0,12),
                DoubleToString(tick_ok ? tick.ask : 0.0,12),
                DoubleToString(spread,12),DoubleToString(point>0.0 ? spread/point : 0.0,4),
                DoubleToString(select_ok ? SymbolInfoDouble(exact,SYMBOL_SWAP_LONG) : 0.0,8),
                DoubleToString(select_ok ? SymbolInfoDouble(exact,SYMBOL_SWAP_SHORT) : 0.0,8),
                select_ok ? (int)SymbolInfoInteger(exact,SYMBOL_SWAP_MODE) : -1,
                select_ok ? (int)SymbolInfoInteger(exact,SYMBOL_SWAP_ROLLOVER3DAYS) : -1,
                select_ok ? SymbolInfoString(exact,SYMBOL_CURRENCY_BASE) : "",
                select_ok ? SymbolInfoString(exact,SYMBOL_CURRENCY_PROFIT) : "",
                select_ok ? SymbolInfoString(exact,SYMBOL_CURRENCY_MARGIN) : "",
                YesNo(select_ok),YesNo(tick_ok),row_ok ? "PASS" : "FAIL");
     }

   FileFlush(symbols);
   FileFlush(account);
   FileClose(symbols);
   FileClose(account);
   PrintFormat("SOLTRADE_FXIFY_RAW_CAPTURE_COMPLETE | status=%s | symbols=7 | orders=%d | positions=%d | credentials_recorded=NO",
               pass ? "PASS" : "FAIL",OrdersTotal(),PositionsTotal());
  }
