#ifndef SOLTRADE_STRATEGY_BREAKOUT_MQH
#define SOLTRADE_STRATEGY_BREAKOUT_MQH

#include <SolTrade/Config.mqh>

#define SOLTRADE_EMA_PERIOD             200
#define SOLTRADE_ENTRY_CHANNEL_PERIOD    20
#define SOLTRADE_EXIT_CHANNEL_PERIOD     10
#define SOLTRADE_ATR_PERIOD              14
#define SOLTRADE_STRATEGY_HISTORY_BARS  221

enum ENUM_SOLTRADE_ENTRY_SIGNAL
  {
   SOLTRADE_SIGNAL_NONE = 0,
   SOLTRADE_SIGNAL_BUY  = 1,
   SOLTRADE_SIGNAL_SELL = 2
  };

enum ENUM_SOLTRADE_EXIT_SIGNAL
  {
   SOLTRADE_EXIT_NONE  = 0,
   SOLTRADE_EXIT_LONG  = 1,
   SOLTRADE_EXIT_SHORT = 2
  };

struct SolTradeStrategySignal
  {
   bool                         evaluated;
   bool                         valid;
   ENUM_SOLTRADE_ENTRY_SIGNAL   entry_signal;
   ENUM_SOLTRADE_EXIT_SIGNAL    exit_signal;
   datetime                     signal_bar_time;
   double                       signal_open;
   double                       signal_high;
   double                       signal_low;
   double                       signal_close;
   double                       ema_200;
   double                       entry_channel_high;
   double                       entry_channel_low;
   double                       exit_channel_high;
   double                       exit_channel_low;
   double                       atr_14;
   double                       initial_stop_distance;
   bool                         bullish_entry_breakout;
   bool                         bearish_entry_breakout;
   bool                         bullish_trend;
   bool                         bearish_trend;
   string                       entry_reason_code;
   string                       entry_reason;
   string                       exit_reason_code;
   string                       exit_reason;
   string                       calculation_error;
  };

void ResetSolTradeStrategySignal(SolTradeStrategySignal &signal)
  {
   signal.evaluated               = false;
   signal.valid                   = false;
   signal.entry_signal            = SOLTRADE_SIGNAL_NONE;
   signal.exit_signal             = SOLTRADE_EXIT_NONE;
   signal.signal_bar_time         = 0;
   signal.signal_open             = 0.0;
   signal.signal_high             = 0.0;
   signal.signal_low              = 0.0;
   signal.signal_close            = 0.0;
   signal.ema_200                 = 0.0;
   signal.entry_channel_high      = 0.0;
   signal.entry_channel_low       = 0.0;
   signal.exit_channel_high       = 0.0;
   signal.exit_channel_low        = 0.0;
   signal.atr_14                  = 0.0;
   signal.initial_stop_distance   = 0.0;
   signal.bullish_entry_breakout  = false;
   signal.bearish_entry_breakout  = false;
   signal.bullish_trend           = false;
   signal.bearish_trend           = false;
   signal.entry_reason_code       = "NOT_EVALUATED";
   signal.entry_reason            =
      "Waiting for a newly completed H1 candle";
   signal.exit_reason_code        = "NOT_EVALUATED";
   signal.exit_reason             =
      "Waiting for a newly completed H1 candle";
   signal.calculation_error       = "";
  }

string SolTradeEntrySignalName(const ENUM_SOLTRADE_ENTRY_SIGNAL signal)
  {
   switch(signal)
     {
      case SOLTRADE_SIGNAL_BUY:  return "BUY";
      case SOLTRADE_SIGNAL_SELL: return "SELL";
      default:                   return "NONE";
     }
  }

string SolTradeExitSignalName(const ENUM_SOLTRADE_EXIT_SIGNAL signal)
  {
   switch(signal)
     {
      case SOLTRADE_EXIT_LONG:  return "EXIT_LONG";
      case SOLTRADE_EXIT_SHORT: return "EXIT_SHORT";
      default:                  return "NONE";
     }
  }

bool SolTradeValidCompletedRate(const MqlRates &rate)
  {
   return (rate.time > 0 &&
           MathIsValidNumber(rate.open) &&
           MathIsValidNumber(rate.high) &&
           MathIsValidNumber(rate.low) &&
           MathIsValidNumber(rate.close) &&
           rate.open > 0.0 &&
           rate.low > 0.0 &&
           rate.close > 0.0 &&
           rate.high >= rate.low &&
           rate.high >= rate.open &&
           rate.high >= rate.close &&
           rate.low <= rate.open &&
           rate.low <= rate.close);
  }

double SolTradeTrueRange(const MqlRates &rate,
                         const double previous_close,
                         const bool has_previous_close)
  {
   double true_range = rate.high - rate.low;
   if(has_previous_close)
     {
      true_range =
         MathMax(true_range, MathAbs(rate.high - previous_close));
      true_range =
         MathMax(true_range, MathAbs(rate.low - previous_close));
     }

   return true_range;
  }

bool SolTradeStrictlyBelow(const double value,
                           const double boundary)
  {
   // Decimal prices that are mathematically equal can differ by a few binary
   // floating-point units after arithmetic (for example, 1.1000 - 0.0005
   // versus the literal 1.0995). Treat only that representation noise as
   // equality; any broker-valid price step remains many orders of magnitude
   // larger than this guard.
   const double scale =
      MathMax(1.0, MathMax(MathAbs(value), MathAbs(boundary)));
   const double equality_tolerance =
      8.0 * 2.2204460492503131e-16 * scale;

   return (value < boundary &&
           (boundary - value) > equality_tolerance);
  }

bool SolTradeEvaluateCompletedBars(
   const MqlRates &completed_bars[],
   SolTradeStrategySignal &signal)
  {
   ResetSolTradeStrategySignal(signal);
   signal.evaluated = true;

   const int total = ArraySize(completed_bars);
   if(total < SOLTRADE_STRATEGY_HISTORY_BARS)
     {
      signal.calculation_error =
         "Insufficient completed strategy history: " +
         IntegerToString(total) + " of " +
         IntegerToString(SOLTRADE_STRATEGY_HISTORY_BARS) + " bars";
      signal.entry_reason_code = "INVALID_HISTORY";
      signal.entry_reason      = signal.calculation_error;
      signal.exit_reason_code  = "INVALID_HISTORY";
      signal.exit_reason       = signal.calculation_error;
      return false;
     }

   const int first =
      total - SOLTRADE_STRATEGY_HISTORY_BARS;
   const int signal_index = total - 1;

   for(int index = first; index <= signal_index; index++)
     {
      if(!SolTradeValidCompletedRate(completed_bars[index]))
        {
         signal.calculation_error =
            "Invalid completed candle at chronological index " +
            IntegerToString(index - first);
         signal.entry_reason_code = "INVALID_CANDLE";
         signal.entry_reason      = signal.calculation_error;
         signal.exit_reason_code  = "INVALID_CANDLE";
         signal.exit_reason       = signal.calculation_error;
         return false;
        }

      if(index > first &&
         completed_bars[index].time <= completed_bars[index - 1].time)
        {
         signal.calculation_error =
            "Completed candles are not strictly chronological";
         signal.entry_reason_code = "INVALID_BAR_ORDER";
         signal.entry_reason      = signal.calculation_error;
         signal.exit_reason_code  = "INVALID_BAR_ORDER";
         signal.exit_reason       = signal.calculation_error;
         return false;
        }
     }

   double ema = 0.0;
   for(int index = first;
       index < first + SOLTRADE_EMA_PERIOD;
       index++)
      ema += completed_bars[index].close;
   ema /= (double)SOLTRADE_EMA_PERIOD;

   const double ema_alpha =
      2.0 / ((double)SOLTRADE_EMA_PERIOD + 1.0);
   for(int index = first + SOLTRADE_EMA_PERIOD;
       index <= signal_index;
       index++)
     {
      ema =
         ema_alpha * completed_bars[index].close +
         (1.0 - ema_alpha) * ema;
     }

   double atr = 0.0;
   for(int index = first;
       index < first + SOLTRADE_ATR_PERIOD;
       index++)
     {
      const bool has_previous = (index > first);
      const double previous_close =
         has_previous ? completed_bars[index - 1].close : 0.0;
      atr += SolTradeTrueRange(completed_bars[index],
                               previous_close,
                               has_previous);
     }
   atr /= (double)SOLTRADE_ATR_PERIOD;

   for(int index = first + SOLTRADE_ATR_PERIOD;
       index <= signal_index;
       index++)
     {
      const double true_range =
         SolTradeTrueRange(completed_bars[index],
                           completed_bars[index - 1].close,
                           true);
      atr =
         ((atr * (SOLTRADE_ATR_PERIOD - 1)) + true_range) /
         (double)SOLTRADE_ATR_PERIOD;
     }

   double entry_high =
      completed_bars[signal_index - SOLTRADE_ENTRY_CHANNEL_PERIOD].high;
   double entry_low =
      completed_bars[signal_index - SOLTRADE_ENTRY_CHANNEL_PERIOD].low;
   for(int index =
          signal_index - SOLTRADE_ENTRY_CHANNEL_PERIOD + 1;
       index < signal_index;
       index++)
     {
      entry_high = MathMax(entry_high, completed_bars[index].high);
      entry_low  = MathMin(entry_low, completed_bars[index].low);
     }

   double exit_high =
      completed_bars[signal_index - SOLTRADE_EXIT_CHANNEL_PERIOD].high;
   double exit_low =
      completed_bars[signal_index - SOLTRADE_EXIT_CHANNEL_PERIOD].low;
   for(int index =
          signal_index - SOLTRADE_EXIT_CHANNEL_PERIOD + 1;
       index < signal_index;
       index++)
     {
      exit_high = MathMax(exit_high, completed_bars[index].high);
      exit_low  = MathMin(exit_low, completed_bars[index].low);
     }

   const MqlRates signal_bar = completed_bars[signal_index];
   signal.signal_bar_time       = signal_bar.time;
   signal.signal_open           = signal_bar.open;
   signal.signal_high           = signal_bar.high;
   signal.signal_low            = signal_bar.low;
   signal.signal_close          = signal_bar.close;
   signal.ema_200               = ema;
   signal.entry_channel_high    = entry_high;
   signal.entry_channel_low     = entry_low;
   signal.exit_channel_high     = exit_high;
   signal.exit_channel_low      = exit_low;
   signal.atr_14                = atr;
   signal.initial_stop_distance = 2.0 * atr;

   if(!MathIsValidNumber(ema) || ema <= 0.0 ||
      !MathIsValidNumber(atr) || atr <= 0.0 ||
      !MathIsValidNumber(entry_high) ||
      !MathIsValidNumber(entry_low) ||
      !MathIsValidNumber(exit_high) ||
      !MathIsValidNumber(exit_low) ||
      entry_high < entry_low ||
      exit_high < exit_low)
     {
      signal.calculation_error =
         "EMA, ATR, or Donchian calculation is invalid";
      signal.entry_reason_code = "INVALID_INDICATOR";
      signal.entry_reason      = signal.calculation_error;
      signal.exit_reason_code  = "INVALID_INDICATOR";
      signal.exit_reason       = signal.calculation_error;
      return false;
     }

   signal.bullish_entry_breakout =
      (signal.signal_close > signal.entry_channel_high);
   signal.bearish_entry_breakout =
      SolTradeStrictlyBelow(signal.signal_close,
                            signal.entry_channel_low);
   signal.bullish_trend =
      (signal.signal_close > signal.ema_200);
   signal.bearish_trend =
      (signal.signal_close < signal.ema_200);

   if(signal.bullish_entry_breakout && signal.bullish_trend)
     {
      signal.entry_signal      = SOLTRADE_SIGNAL_BUY;
      signal.entry_reason_code = "BUY_BREAKOUT_ABOVE_EMA200";
      signal.entry_reason =
         "Close is strictly above the preceding 20-bar high and EMA 200";
     }
   else if(signal.bearish_entry_breakout && signal.bearish_trend)
     {
      signal.entry_signal      = SOLTRADE_SIGNAL_SELL;
      signal.entry_reason_code = "SELL_BREAKOUT_BELOW_EMA200";
      signal.entry_reason =
         "Close is strictly below the preceding 20-bar low and EMA 200";
     }
   else if(signal.bullish_entry_breakout)
     {
      signal.entry_reason_code = "BUY_TREND_FILTER_FAILED";
      signal.entry_reason =
         "Upward 20-bar breakout is not strictly above EMA 200";
     }
   else if(signal.bearish_entry_breakout)
     {
      signal.entry_reason_code = "SELL_TREND_FILTER_FAILED";
      signal.entry_reason =
         "Downward 20-bar breakout is not strictly below EMA 200";
     }
   else
     {
      signal.entry_reason_code = "NO_ENTRY_BREAKOUT";
      signal.entry_reason =
         "Close did not break the preceding 20-bar channel";
     }

   if(SolTradeStrictlyBelow(signal.signal_close,
                            signal.exit_channel_low))
     {
      signal.exit_signal      = SOLTRADE_EXIT_LONG;
      signal.exit_reason_code = "LONG_EXIT_BREAKOUT";
      signal.exit_reason =
         "Close is strictly below the preceding 10-bar low";
     }
   else if(signal.signal_close > signal.exit_channel_high)
     {
      signal.exit_signal      = SOLTRADE_EXIT_SHORT;
      signal.exit_reason_code = "SHORT_EXIT_BREAKOUT";
      signal.exit_reason =
         "Close is strictly above the preceding 10-bar high";
     }
   else
     {
      signal.exit_reason_code = "NO_EXIT_BREAKOUT";
      signal.exit_reason =
         "Close remains inside the preceding 10-bar exit channel";
     }

   signal.valid = true;
   return true;
  }

bool SolTradeEvaluateCurrentCompletedHistory(
   const SolTradeConfig &config,
   SolTradeStrategySignal &signal)
  {
   MqlRates completed_bars[];
   ArraySetAsSeries(completed_bars, false);

   ResetLastError();
   const int copied =
      CopyRates(config.symbol,
                config.timeframe,
                1,
                SOLTRADE_STRATEGY_HISTORY_BARS,
                completed_bars);
   if(copied != SOLTRADE_STRATEGY_HISTORY_BARS)
     {
      ResetSolTradeStrategySignal(signal);
      signal.evaluated = true;
      signal.entry_reason_code = "HISTORY_COPY_FAILED";
      signal.exit_reason_code  = "HISTORY_COPY_FAILED";
      signal.calculation_error =
         "Cannot copy completed strategy history: copied " +
         IntegerToString(copied) + " of " +
         IntegerToString(SOLTRADE_STRATEGY_HISTORY_BARS) +
         " bars; error " + IntegerToString(GetLastError());
      signal.entry_reason = signal.calculation_error;
      signal.exit_reason  = signal.calculation_error;
      return false;
     }

   return SolTradeEvaluateCompletedBars(completed_bars, signal);
  }

string SolTradeStrategyLogDetails(const SolTradeStrategySignal &signal,
                                  const int digits)
  {
   if(!signal.valid)
     {
      return "entry_reason_code=" + signal.entry_reason_code +
             "; exit_reason_code=" + signal.exit_reason_code +
             "; calculation_error=" + signal.calculation_error;
     }

   return
      "signal_bar_time=" +
         TimeToString(signal.signal_bar_time,
                      TIME_DATE | TIME_MINUTES) +
      "; entry_signal=" +
         SolTradeEntrySignalName(signal.entry_signal) +
      "; exit_signal=" +
         SolTradeExitSignalName(signal.exit_signal) +
      "; close=" + DoubleToString(signal.signal_close, digits) +
      "; ema_200=" + DoubleToString(signal.ema_200, digits) +
      "; entry_channel_high=" +
         DoubleToString(signal.entry_channel_high, digits) +
      "; entry_channel_low=" +
         DoubleToString(signal.entry_channel_low, digits) +
      "; exit_channel_high=" +
         DoubleToString(signal.exit_channel_high, digits) +
      "; exit_channel_low=" +
         DoubleToString(signal.exit_channel_low, digits) +
      "; atr_14=" + DoubleToString(signal.atr_14, digits) +
      "; initial_stop_distance=" +
         DoubleToString(signal.initial_stop_distance, digits) +
      "; entry_reason_code=" + signal.entry_reason_code +
      "; entry_reason=" + signal.entry_reason +
      "; exit_reason_code=" + signal.exit_reason_code +
      "; exit_reason=" + signal.exit_reason;
  }

#endif // SOLTRADE_STRATEGY_BREAKOUT_MQH
