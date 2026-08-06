#ifndef SOLTRADE_MARKET_DATA_MQH
#define SOLTRADE_MARKET_DATA_MQH

#include <SolTrade/Config.mqh>

struct SolTradeMarketSnapshot
  {
   datetime observed_at;
   datetime tick_time;
   datetime current_bar_time;
   datetime last_completed_bar_time;
   double   bid;
   double   ask;
   double   point;
   double   tick_size;
   double   volume_min;
   double   volume_max;
   double   volume_step;
   int      digits;
   int      spread_points;
   int      bars_available;
   bool     terminal_connected;
   bool     series_synchronised;
   bool     valid;
   string   reason;
  };

void ResetSolTradeMarketSnapshot(SolTradeMarketSnapshot &snapshot)
  {
   snapshot.observed_at             = TimeCurrent();
   snapshot.tick_time               = 0;
   snapshot.current_bar_time        = 0;
   snapshot.last_completed_bar_time = 0;
   snapshot.bid                     = 0.0;
   snapshot.ask                     = 0.0;
   snapshot.point                   = 0.0;
   snapshot.tick_size               = 0.0;
   snapshot.volume_min              = 0.0;
   snapshot.volume_max              = 0.0;
   snapshot.volume_step             = 0.0;
   snapshot.digits                  = 0;
   snapshot.spread_points           = 0;
   snapshot.bars_available          = 0;
   snapshot.terminal_connected      = false;
   snapshot.series_synchronised     = false;
   snapshot.valid                   = false;
   snapshot.reason                  = "Market data has not been evaluated";
  }

bool InitialiseSolTradeMarketData(const SolTradeConfig &config,
                                  datetime &last_seen_current_bar,
                                  string &reason)
  {
   reason = "";
   last_seen_current_bar = 0;

   ResetLastError();
   if(!SymbolSelect(config.symbol, true))
     {
      reason = "Cannot select configured symbol; error " +
               IntegerToString(GetLastError());
      return false;
     }

   const double point = SymbolInfoDouble(config.symbol, SYMBOL_POINT);
   const double tick_size =
      SymbolInfoDouble(config.symbol, SYMBOL_TRADE_TICK_SIZE);
   const double volume_min =
      SymbolInfoDouble(config.symbol, SYMBOL_VOLUME_MIN);
   const double volume_max =
      SymbolInfoDouble(config.symbol, SYMBOL_VOLUME_MAX);
   const double volume_step =
      SymbolInfoDouble(config.symbol, SYMBOL_VOLUME_STEP);

   if(!MathIsValidNumber(point) || point <= 0.0 ||
      !MathIsValidNumber(tick_size) || tick_size <= 0.0 ||
      !MathIsValidNumber(volume_min) || volume_min <= 0.0 ||
      !MathIsValidNumber(volume_max) || volume_max < volume_min ||
      !MathIsValidNumber(volume_step) || volume_step <= 0.0)
     {
      reason = "Configured symbol has invalid point, tick, or volume metadata";
      return false;
     }

   // Seed from the current forming bar. This prevents attachment/restart from
   // treating an old completed candle as a newly completed strategy event.
   last_seen_current_bar = iTime(config.symbol, config.timeframe, 0);
   return true;
  }

bool RefreshSolTradeMarketData(const SolTradeConfig &config,
                               SolTradeMarketSnapshot &snapshot)
  {
   ResetSolTradeMarketSnapshot(snapshot);
   snapshot.observed_at        = TimeCurrent();
   snapshot.terminal_connected =
      (bool)TerminalInfoInteger(TERMINAL_CONNECTED);

   if(!snapshot.terminal_connected && !(bool)MQLInfoInteger(MQL_TESTER))
     {
      snapshot.reason = "Terminal is disconnected";
      return false;
     }

   MqlTick tick;
   ResetLastError();
   if(!SymbolInfoTick(config.symbol, tick))
     {
      snapshot.reason = "No tick is available; error " +
                        IntegerToString(GetLastError());
      return false;
     }

   snapshot.tick_time   = tick.time;
   snapshot.bid         = tick.bid;
   snapshot.ask         = tick.ask;
   snapshot.point       = SymbolInfoDouble(config.symbol, SYMBOL_POINT);
   snapshot.tick_size   =
      SymbolInfoDouble(config.symbol, SYMBOL_TRADE_TICK_SIZE);
   snapshot.volume_min  =
      SymbolInfoDouble(config.symbol, SYMBOL_VOLUME_MIN);
   snapshot.volume_max  =
      SymbolInfoDouble(config.symbol, SYMBOL_VOLUME_MAX);
   snapshot.volume_step =
      SymbolInfoDouble(config.symbol, SYMBOL_VOLUME_STEP);
   snapshot.digits      =
      (int)SymbolInfoInteger(config.symbol, SYMBOL_DIGITS);

   if(!MathIsValidNumber(snapshot.bid) ||
      !MathIsValidNumber(snapshot.ask) ||
      snapshot.bid <= 0.0 ||
      snapshot.ask < snapshot.bid ||
      !MathIsValidNumber(snapshot.point) ||
      snapshot.point <= 0.0 ||
      !MathIsValidNumber(snapshot.tick_size) ||
      snapshot.tick_size <= 0.0)
     {
      snapshot.reason = "Quote or price increment metadata is invalid";
      return false;
     }

   snapshot.spread_points =
      (int)MathRound((snapshot.ask - snapshot.bid) / snapshot.point);

   const long tick_age_seconds = (long)(snapshot.observed_at - tick.time);
   if(tick_age_seconds > config.max_tick_age_seconds)
     {
      snapshot.reason = "Latest tick is stale by " +
                        IntegerToString(tick_age_seconds) + " seconds";
      return false;
     }

   snapshot.bars_available =
      Bars(config.symbol, config.timeframe);
   snapshot.series_synchronised =
      (bool)SeriesInfoInteger(config.symbol,
                              config.timeframe,
                              SERIES_SYNCHRONIZED);

   if(!snapshot.series_synchronised)
     {
      snapshot.reason = "Price history is not synchronised";
      return false;
     }

   if(snapshot.bars_available < config.minimum_history_bars)
     {
      snapshot.reason = "Insufficient history: " +
                        IntegerToString(snapshot.bars_available) +
                        " of " +
                        IntegerToString(config.minimum_history_bars) +
                        " bars";
      return false;
     }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   ResetLastError();
   const int copied =
      CopyRates(config.symbol, config.timeframe, 0, 2, rates);

   if(copied != 2)
     {
      snapshot.reason = "Cannot read current and completed candles; copied " +
                        IntegerToString(copied) + ", error " +
                        IntegerToString(GetLastError());
      return false;
     }

   snapshot.current_bar_time        = rates[0].time;
   snapshot.last_completed_bar_time = rates[1].time;

   if(snapshot.current_bar_time <= 0 ||
      snapshot.last_completed_bar_time <= 0 ||
      !MathIsValidNumber(rates[1].open) ||
      !MathIsValidNumber(rates[1].high) ||
      !MathIsValidNumber(rates[1].low) ||
      !MathIsValidNumber(rates[1].close) ||
      rates[1].open <= 0.0 ||
      rates[1].low <= 0.0 ||
      rates[1].high < rates[1].low ||
      rates[1].high < rates[1].open ||
      rates[1].high < rates[1].close ||
      rates[1].low > rates[1].open ||
      rates[1].low > rates[1].close ||
      rates[1].close <= 0.0)
     {
      snapshot.reason = "Completed candle data is invalid";
      return false;
     }

   snapshot.valid  = true;
   snapshot.reason = "Market data valid";
   return true;
  }

bool DetectSolTradeNewBar(const SolTradeMarketSnapshot &snapshot,
                          datetime &last_seen_current_bar,
                          datetime &completed_bar_time)
  {
   completed_bar_time = 0;

   if(!snapshot.valid || snapshot.current_bar_time <= 0)
      return false;

   if(last_seen_current_bar <= 0)
     {
      last_seen_current_bar = snapshot.current_bar_time;
      return false;
     }

   if(snapshot.current_bar_time < last_seen_current_bar)
     {
      // History/time changes can move the series backwards. Re-seed rather than
      // presenting an uncertain candle as a new strategy event.
      last_seen_current_bar = snapshot.current_bar_time;
      return false;
     }

   if(snapshot.current_bar_time == last_seen_current_bar)
      return false;

   last_seen_current_bar = snapshot.current_bar_time;
   completed_bar_time    = snapshot.last_completed_bar_time;
   return (completed_bar_time > 0);
  }

#endif // SOLTRADE_MARKET_DATA_MQH
