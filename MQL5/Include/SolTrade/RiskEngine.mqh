#ifndef SOLTRADE_RISK_ENGINE_MQH
#define SOLTRADE_RISK_ENGINE_MQH

#include <SolTrade/Config.mqh>

#define SOLTRADE_RISK_STATE_SCHEMA "SOLTRADE_RISK_STATE_V1"
#define SOLTRADE_MONEY_TOLERANCE   0.01
#define SOLTRADE_MAX_OPEN_POSITIONS 1

struct SolTradeRiskCalculation
  {
   bool   valid;
   string reason;
   double equity;
   double risk_percent;
   double risk_money;
   double stop_distance;
   double tick_size;
   double tick_value_loss;
   double loss_per_lot;
   double raw_volume;
   double normalised_volume;
   double expected_loss;
   double volume_min;
   double volume_max;
   double volume_step;
  };

struct SolTradeStopValidation
  {
   bool   valid;
   string reason;
   double requested_distance;
   double minimum_distance;
  };

struct SolTradeSpreadValidation
  {
   bool   valid;
   string reason;
   int    spread_points;
   double spread_price;
   double atr;
   double atr_spread_limit;
  };

struct SolTradeRiskStatus
  {
   bool   initialised;
   bool   state_valid;
   bool   emergency_armed;
   bool   daily_locked;
   bool   weekly_locked;
   bool   emergency_locked;
   bool   consecutive_locked;
   long   day_key;
   long   week_key;
   long   consecutive_lock_day_key;
   int    consecutive_losses;
   double current_equity;
   double risk_budget;
   double daily_start_equity;
   double weekly_start_equity;
   double daily_profit_loss;
   double weekly_profit_loss;
   double daily_drawdown_percent;
   double weekly_drawdown_percent;
   double emergency_drawdown_percent;
   string lock_reason;
   string state_error;
   string last_event;
  };

enum ENUM_SOLTRADE_OUTCOME_RESULT
  {
   SOLTRADE_OUTCOME_ERROR     = -1,
   SOLTRADE_OUTCOME_DUPLICATE = 0,
   SOLTRADE_OUTCOME_RECORDED  = 1
  };

void ResetSolTradeRiskCalculation(SolTradeRiskCalculation &calculation)
  {
   calculation.valid             = false;
   calculation.reason            = "Risk calculation has not been evaluated";
   calculation.equity            = 0.0;
   calculation.risk_percent      = 0.0;
   calculation.risk_money        = 0.0;
   calculation.stop_distance     = 0.0;
   calculation.tick_size         = 0.0;
   calculation.tick_value_loss   = 0.0;
   calculation.loss_per_lot      = 0.0;
   calculation.raw_volume        = 0.0;
   calculation.normalised_volume = 0.0;
   calculation.expected_loss     = 0.0;
   calculation.volume_min        = 0.0;
   calculation.volume_max        = 0.0;
   calculation.volume_step       = 0.0;
  }

void ResetSolTradeRiskStatus(SolTradeRiskStatus &status)
  {
   status.initialised                  = false;
   status.state_valid                 = false;
   status.emergency_armed             = false;
   status.daily_locked                = false;
   status.weekly_locked               = false;
   status.emergency_locked            = false;
   status.consecutive_locked          = false;
   status.day_key                     = 0;
   status.week_key                    = 0;
   status.consecutive_lock_day_key    = 0;
   status.consecutive_losses          = 0;
   status.current_equity              = 0.0;
   status.risk_budget                 = 0.0;
   status.daily_start_equity          = 0.0;
   status.weekly_start_equity         = 0.0;
   status.daily_profit_loss           = 0.0;
   status.weekly_profit_loss          = 0.0;
   status.daily_drawdown_percent      = 0.0;
   status.weekly_drawdown_percent     = 0.0;
   status.emergency_drawdown_percent  = 0.0;
   status.lock_reason                 = "Risk engine is not initialised";
   status.state_error                 = "";
   status.last_event                  = "";
  }

bool SolTradeCalculateRiskBudget(const double equity,
                                 const double risk_percent,
                                 double &risk_money,
                                 string &reason)
  {
   risk_money = 0.0;
   reason     = "";

   if(!MathIsValidNumber(equity) || equity <= 0.0)
     {
      reason = "Equity must be a positive finite number";
      return false;
     }

   if(!MathIsValidNumber(risk_percent) ||
      risk_percent <= 0.0 ||
      risk_percent > 100.0)
     {
      reason = "Risk percent must be greater than 0 and no more than 100";
      return false;
     }

   risk_money = equity * (risk_percent / 100.0);
   if(!MathIsValidNumber(risk_money) || risk_money <= 0.0)
     {
      reason = "Calculated risk budget is invalid";
      risk_money = 0.0;
      return false;
     }

   return true;
  }

int SolTradeVolumeDigits(const double volume_step)
  {
   for(int digits = 0; digits <= 8; digits++)
     {
      if(MathAbs(NormalizeDouble(volume_step, digits) - volume_step) <= 1e-10)
         return digits;
     }

   return 8;
  }

bool SolTradeCalculatePositionSize(const double equity,
                                   const double risk_percent,
                                   const double stop_distance,
                                   const double tick_size,
                                   const double tick_value_loss,
                                   const double volume_min,
                                   const double volume_max,
                                   const double volume_step,
                                   SolTradeRiskCalculation &calculation)
  {
   ResetSolTradeRiskCalculation(calculation);
   calculation.equity          = equity;
   calculation.risk_percent    = risk_percent;
   calculation.stop_distance   = stop_distance;
   calculation.tick_size       = tick_size;
   calculation.tick_value_loss = tick_value_loss;
   calculation.volume_min      = volume_min;
   calculation.volume_max      = volume_max;
   calculation.volume_step     = volume_step;

   string reason = "";
   if(!SolTradeCalculateRiskBudget(equity,
                                   risk_percent,
                                   calculation.risk_money,
                                   reason))
     {
      calculation.reason = reason;
      return false;
     }

   if(!MathIsValidNumber(stop_distance) || stop_distance <= 0.0)
     {
      calculation.reason = "Stop distance must be a positive finite number";
      return false;
     }

   if(!MathIsValidNumber(tick_size) || tick_size <= 0.0)
     {
      calculation.reason = "Tick size must be a positive finite number";
      return false;
     }

   if(!MathIsValidNumber(tick_value_loss) || tick_value_loss <= 0.0)
     {
      calculation.reason =
         "Loss-side tick value must be a positive finite number";
      return false;
     }

   if(!MathIsValidNumber(volume_min) || volume_min <= 0.0 ||
      !MathIsValidNumber(volume_max) || volume_max < volume_min ||
      !MathIsValidNumber(volume_step) || volume_step <= 0.0)
     {
      calculation.reason = "Broker volume metadata is invalid";
      return false;
     }

   const double tick_count = stop_distance / tick_size;
   if(!MathIsValidNumber(tick_count) || tick_count <= 0.0)
     {
      calculation.reason = "Stop distance cannot be converted to ticks";
      return false;
     }

   calculation.loss_per_lot = tick_count * tick_value_loss;
   if(!MathIsValidNumber(calculation.loss_per_lot) ||
      calculation.loss_per_lot <= 0.0)
     {
      calculation.reason = "Expected one-lot stop loss is invalid";
      return false;
     }

   calculation.raw_volume =
      calculation.risk_money / calculation.loss_per_lot;
   if(!MathIsValidNumber(calculation.raw_volume) ||
      calculation.raw_volume <= 0.0)
     {
      calculation.reason = "Raw risk-based volume is invalid";
      return false;
     }

   const double grid_tolerance = 1e-12;
   const int volume_digits =
      MathMax(SolTradeVolumeDigits(volume_min),
              SolTradeVolumeDigits(volume_step));
   double broker_max_on_grid =
      volume_min +
      MathFloor(((volume_max - volume_min) + grid_tolerance) / volume_step) *
      volume_step;
   broker_max_on_grid = NormalizeDouble(broker_max_on_grid, volume_digits);

   if(calculation.raw_volume + grid_tolerance < volume_min)
     {
      calculation.reason =
         "Risk-based volume is below the broker minimum; rounding up is prohibited";
      return false;
     }

   double normalised =
      volume_min +
      MathFloor(((calculation.raw_volume - volume_min) + grid_tolerance) /
                volume_step) *
      volume_step;
   normalised = NormalizeDouble(normalised, volume_digits);

   if(normalised > broker_max_on_grid)
      normalised = broker_max_on_grid;

   if(normalised + grid_tolerance < volume_min)
     {
      calculation.reason =
         "Risk-based volume is below the broker minimum; rounding up is prohibited";
      return false;
     }

   calculation.expected_loss = normalised * calculation.loss_per_lot;

   // Rounding down should already keep risk within budget. This additional
   // guard steps down again if broker precision or floating-point effects cause
   // the recomputed monetary loss to exceed the approved budget by more than
   // one account-currency cent.
   while(normalised + grid_tolerance >= volume_min &&
         calculation.expected_loss >
            calculation.risk_money + SOLTRADE_MONEY_TOLERANCE)
     {
      normalised = NormalizeDouble(normalised - volume_step, volume_digits);
      calculation.expected_loss = normalised * calculation.loss_per_lot;
     }

   if(normalised + grid_tolerance < volume_min)
     {
      calculation.reason =
         "No broker-valid volume fits within the monetary risk budget";
      calculation.expected_loss = 0.0;
      return false;
     }

   if(!MathIsValidNumber(calculation.expected_loss) ||
      calculation.expected_loss <= 0.0 ||
      calculation.expected_loss >
         calculation.risk_money + SOLTRADE_MONEY_TOLERANCE)
     {
      calculation.reason =
         "Normalised volume exceeds the approved monetary risk budget";
      calculation.expected_loss = 0.0;
      return false;
     }

   calculation.normalised_volume = normalised;
   calculation.valid             = true;
   calculation.reason            = "Risk calculation valid";
   return true;
  }

bool SolTradeCalculatePositionSizeFromPrices(
   const double equity,
   const double risk_percent,
   const double entry_price,
   const double stop_price,
   const double tick_size,
   const double tick_value_loss,
   const double volume_min,
   const double volume_max,
   const double volume_step,
   SolTradeRiskCalculation &calculation)
  {
   if(!MathIsValidNumber(entry_price) ||
      !MathIsValidNumber(stop_price) ||
      entry_price <= 0.0 ||
      stop_price <= 0.0 ||
      entry_price == stop_price)
     {
      ResetSolTradeRiskCalculation(calculation);
      calculation.reason =
         "Entry and stop prices must be positive, finite, and different";
      return false;
     }

   return SolTradeCalculatePositionSize(equity,
                                        risk_percent,
                                        MathAbs(entry_price - stop_price),
                                        tick_size,
                                        tick_value_loss,
                                        volume_min,
                                        volume_max,
                                        volume_step,
                                        calculation);
  }

bool SolTradeValidateStopDistance(const double stop_distance,
                                  const double tick_size,
                                  const double point,
                                  const int stops_level_points,
                                  SolTradeStopValidation &validation)
  {
   validation.valid              = false;
   validation.reason             = "";
   validation.requested_distance = stop_distance;
   validation.minimum_distance   = 0.0;

   if(!MathIsValidNumber(stop_distance) || stop_distance <= 0.0)
     {
      validation.reason = "Stop distance must be positive";
      return false;
     }

   if(!MathIsValidNumber(tick_size) || tick_size <= 0.0 ||
      !MathIsValidNumber(point) || point <= 0.0 ||
      stops_level_points < 0)
     {
      validation.reason = "Stop-distance broker metadata is invalid";
      return false;
     }

   validation.minimum_distance =
      MathMax(tick_size, (double)stops_level_points * point);

   if(stop_distance + 1e-12 < validation.minimum_distance)
     {
      validation.reason = "Stop distance is below the broker minimum";
      return false;
     }

   validation.valid  = true;
   validation.reason = "Stop distance valid";
   return true;
  }

bool SolTradeValidatePositionCapacity(const int open_soltrade_positions,
                                      string &reason)
  {
   reason = "";

   if(open_soltrade_positions < 0)
     {
      reason = "Open SolTrade position count is invalid";
      return false;
     }

   if(open_soltrade_positions >= SOLTRADE_MAX_OPEN_POSITIONS)
     {
      reason = "Maximum of one open SolTrade position has been reached";
      return false;
     }

   return true;
  }

bool SolTradeValidateSpread(const int spread_points,
                            const double point,
                            const double atr,
                            const int max_spread_points,
                            const double max_spread_atr_percent,
                            SolTradeSpreadValidation &validation)
  {
   validation.valid             = false;
   validation.reason            = "";
   validation.spread_points     = spread_points;
   validation.spread_price      = 0.0;
   validation.atr               = atr;
   validation.atr_spread_limit  = 0.0;

   if(spread_points < 0 ||
      !MathIsValidNumber(point) || point <= 0.0 ||
      !MathIsValidNumber(atr) || atr <= 0.0 ||
      max_spread_points <= 0 ||
      !MathIsValidNumber(max_spread_atr_percent) ||
      max_spread_atr_percent <= 0.0 ||
      max_spread_atr_percent >= 100.0)
     {
      validation.reason = "Spread or ATR metadata is invalid";
      return false;
     }

   validation.spread_price =
      (double)spread_points * point;
   validation.atr_spread_limit =
      atr * (max_spread_atr_percent / 100.0);

   if(spread_points > max_spread_points)
     {
      validation.reason = "Spread exceeds the absolute point limit";
      return false;
     }

   if(validation.spread_price >
      validation.atr_spread_limit + 1e-12)
     {
      validation.reason = "Spread exceeds the ATR-relative limit";
      return false;
     }

   validation.valid  = true;
   validation.reason = "Spread valid";
   return true;
  }

long SolTradeBrokerDayKey(const datetime server_time)
  {
   if(server_time <= 0)
      return 0;

   MqlDateTime parts = {};
   if(!TimeToStruct(server_time, parts))
      return 0;

   parts.hour = 0;
   parts.min  = 0;
   parts.sec  = 0;
   return (long)StructToTime(parts);
  }

long SolTradeBrokerWeekKey(const datetime server_time)
  {
   if(server_time <= 0)
      return 0;

   MqlDateTime parts = {};
   if(!TimeToStruct(server_time, parts))
      return 0;

   const int days_since_monday = (parts.day_of_week + 6) % 7;
   parts.hour = 0;
   parts.min  = 0;
   parts.sec  = 0;
   const datetime day_start = StructToTime(parts);
   return (long)(day_start - (datetime)(days_since_monday * 86400));
  }

string SolTradeRiskStateChecksum(const string payload)
  {
   uint hash = 2166136261;
   for(int index = 0; index < StringLen(payload); index++)
     {
      hash ^= (uint)StringGetCharacter(payload, index);
      hash = (uint)(hash * (uint)16777619);
     }

   return StringFormat("%08lX", hash);
  }

class CSolTradeRiskEngine
  {
private:
   SolTradeConfig      m_config;
   SolTradeRiskStatus  m_status;
   bool                m_persistence_enabled;
   string              m_state_path;
   string              m_last_outcome_id;
   long                m_revision;
   bool                m_persistence_fault;

   void AppendEvent(string &event_text, const string addition)
     {
      if(StringLen(addition) == 0)
         return;

      if(StringLen(event_text) > 0)
         event_text += "; ";
      event_text += addition;
     }

   void UpdateLockReason()
     {
      if(!m_status.state_valid)
        {
         m_status.lock_reason =
            "Risk state invalid: " + m_status.state_error;
         return;
        }

      if(m_config.emergency_stop)
        {
         m_status.lock_reason = "EmergencyStop is enabled";
         return;
        }

      if(m_status.emergency_locked)
        {
         m_status.lock_reason =
            "Emergency drawdown lock requires explicit reset";
         return;
        }

      if(m_status.weekly_locked)
        {
         m_status.lock_reason = "Weekly loss limit reached";
         return;
        }

      if(m_status.daily_locked)
        {
         m_status.lock_reason = "Daily loss limit reached";
         return;
        }

      if(m_status.consecutive_locked)
        {
         m_status.lock_reason =
            "Consecutive-loss pause active until next broker day";
         return;
        }

      m_status.lock_reason = "Risk checks permit evaluation";
     }

   bool SaveState(string &reason)
     {
      reason = "";
      if(!m_persistence_enabled)
        {
         m_persistence_fault = false;
         return true;
        }

      const string temporary_path = m_state_path + ".tmp";
      FileDelete(temporary_path);

      ResetLastError();
      const int handle =
         FileOpen(temporary_path, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(handle == INVALID_HANDLE)
        {
         reason = "Cannot open temporary risk-state file; error " +
                  IntegerToString(GetLastError());
         m_persistence_fault = true;
         return false;
        }

      const string day_key_text =
         IntegerToString(m_status.day_key);
      const string daily_start_text =
         DoubleToString(m_status.daily_start_equity, 8);
      const string daily_locked_text =
         m_status.daily_locked ? "1" : "0";
      const string week_key_text =
         IntegerToString(m_status.week_key);
      const string weekly_start_text =
         DoubleToString(m_status.weekly_start_equity, 8);
      const string weekly_locked_text =
         m_status.weekly_locked ? "1" : "0";
      const string emergency_locked_text =
         m_status.emergency_locked ? "1" : "0";
      const string consecutive_losses_text =
         IntegerToString(m_status.consecutive_losses);
      const string consecutive_locked_text =
         m_status.consecutive_locked ? "1" : "0";
      const string consecutive_day_text =
         IntegerToString(m_status.consecutive_lock_day_key);
      const string payload =
         SOLTRADE_RISK_STATE_SCHEMA + "|" +
         day_key_text + "|" +
         daily_start_text + "|" +
         daily_locked_text + "|" +
         week_key_text + "|" +
         weekly_start_text + "|" +
         weekly_locked_text + "|" +
         emergency_locked_text + "|" +
         consecutive_losses_text + "|" +
         consecutive_locked_text + "|" +
         consecutive_day_text + "|" +
         m_last_outcome_id;
      const string checksum = SolTradeRiskStateChecksum(payload);

      const uint written =
         FileWrite(handle,
                   SOLTRADE_RISK_STATE_SCHEMA,
                   day_key_text,
                   daily_start_text,
                   daily_locked_text,
                   week_key_text,
                   weekly_start_text,
                   weekly_locked_text,
                   emergency_locked_text,
                   consecutive_losses_text,
                   consecutive_locked_text,
                   consecutive_day_text,
                   m_last_outcome_id,
                   checksum);
      FileFlush(handle);
      FileClose(handle);

      if(written == 0)
        {
         reason = "Risk-state write returned zero bytes";
         FileDelete(temporary_path);
         m_persistence_fault = true;
         return false;
        }

      ResetLastError();
      if(!FileMove(temporary_path, 0, m_state_path, FILE_REWRITE))
        {
         reason = "Cannot replace persistent risk-state file; error " +
                  IntegerToString(GetLastError());
         FileDelete(temporary_path);
         m_persistence_fault = true;
         return false;
        }

      m_persistence_fault = false;
      return true;
     }

   bool LoadState(bool &found, string &reason)
     {
      found  = false;
      reason = "";

      if(!m_persistence_enabled || !FileIsExist(m_state_path))
         return true;

      found = true;
      ResetLastError();
      const int handle =
         FileOpen(m_state_path, FILE_READ | FILE_CSV | FILE_ANSI, ',');
      if(handle == INVALID_HANDLE)
        {
         reason = "Cannot open persistent risk-state file; error " +
                  IntegerToString(GetLastError());
         return false;
        }

      const string schema                    = FileReadString(handle);
      const string day_key_text              = FileReadString(handle);
      const string daily_start_text          = FileReadString(handle);
      const string daily_locked_text         = FileReadString(handle);
      const string week_key_text             = FileReadString(handle);
      const string weekly_start_text         = FileReadString(handle);
      const string weekly_locked_text        = FileReadString(handle);
      const string emergency_locked_text     = FileReadString(handle);
      const string consecutive_losses_text   = FileReadString(handle);
      const string consecutive_locked_text   = FileReadString(handle);
      const string consecutive_day_text      = FileReadString(handle);
      const string last_outcome_id            = FileReadString(handle);
      const string stored_checksum            = FileReadString(handle);
      FileClose(handle);

      if(schema != SOLTRADE_RISK_STATE_SCHEMA)
        {
         reason = "Risk-state schema is missing or unsupported";
         return false;
        }

      const string payload =
         schema + "|" +
         day_key_text + "|" +
         daily_start_text + "|" +
         daily_locked_text + "|" +
         week_key_text + "|" +
         weekly_start_text + "|" +
         weekly_locked_text + "|" +
         emergency_locked_text + "|" +
         consecutive_losses_text + "|" +
         consecutive_locked_text + "|" +
         consecutive_day_text + "|" +
         last_outcome_id;
      if(stored_checksum != SolTradeRiskStateChecksum(payload))
        {
         reason = "Persistent risk-state checksum does not match";
         return false;
        }

      if((daily_locked_text != "0" && daily_locked_text != "1") ||
         (weekly_locked_text != "0" && weekly_locked_text != "1") ||
         (emergency_locked_text != "0" && emergency_locked_text != "1") ||
         (consecutive_locked_text != "0" && consecutive_locked_text != "1"))
        {
         reason = "Persistent risk-state lock flags are invalid";
         return false;
        }

      m_status.day_key                    = StringToInteger(day_key_text);
      m_status.daily_start_equity         = StringToDouble(daily_start_text);
      m_status.daily_locked               =
         (StringToInteger(daily_locked_text) == 1);
      m_status.week_key                   = StringToInteger(week_key_text);
      m_status.weekly_start_equity        = StringToDouble(weekly_start_text);
      m_status.weekly_locked              =
         (StringToInteger(weekly_locked_text) == 1);
      m_status.emergency_locked           =
         (StringToInteger(emergency_locked_text) == 1);
      m_status.consecutive_losses         =
         (int)StringToInteger(consecutive_losses_text);
      m_status.consecutive_locked         =
         (StringToInteger(consecutive_locked_text) == 1);
      m_status.consecutive_lock_day_key   =
         StringToInteger(consecutive_day_text);
      m_last_outcome_id                   = last_outcome_id;

      if(m_status.day_key <= 0 ||
         m_status.week_key <= 0 ||
         !MathIsValidNumber(m_status.daily_start_equity) ||
         m_status.daily_start_equity <= 0.0 ||
         !MathIsValidNumber(m_status.weekly_start_equity) ||
         m_status.weekly_start_equity <= 0.0 ||
         m_status.consecutive_losses < 0 ||
         m_status.consecutive_losses > 100000 ||
         (m_status.consecutive_locked &&
          m_status.consecutive_lock_day_key <= 0))
        {
         reason = "Persistent risk-state values are invalid";
         return false;
        }

      return true;
     }

   bool Evaluate(const datetime server_time,
                 const double equity,
                 bool &state_changed,
                 string &event_text,
                 string &reason)
     {
      state_changed = false;
      event_text    = "";
      reason        = "";

      if(server_time <= 0)
        {
         reason = "Broker server time is invalid";
         return false;
        }

      if(!MathIsValidNumber(equity) || equity <= 0.0)
        {
         reason = "Current account equity is invalid";
         return false;
        }

      const long current_day_key  = SolTradeBrokerDayKey(server_time);
      const long current_week_key = SolTradeBrokerWeekKey(server_time);
      if(current_day_key <= 0 || current_week_key <= 0)
        {
         reason = "Broker day or week key cannot be calculated";
         return false;
        }

      if(m_status.day_key > current_day_key ||
         m_status.week_key > current_week_key)
        {
         reason = "Persistent risk state is dated in the future";
         return false;
        }

      if(m_status.day_key != current_day_key)
        {
         m_status.day_key            = current_day_key;
         m_status.daily_start_equity  = equity;
         m_status.daily_locked        = false;
         state_changed                = true;
         AppendEvent(event_text, "NEW_BROKER_DAY");

         if(m_status.consecutive_locked)
           {
            m_status.consecutive_locked       = false;
            m_status.consecutive_losses       = 0;
            m_status.consecutive_lock_day_key = 0;
            AppendEvent(event_text, "CONSECUTIVE_LOSS_PAUSE_CLEARED");
           }
        }

      if(m_status.week_key != current_week_key)
        {
         m_status.week_key            = current_week_key;
         m_status.weekly_start_equity  = equity;
         m_status.weekly_locked        = false;
         state_changed                 = true;
         AppendEvent(event_text, "NEW_BROKER_WEEK");
        }

      m_status.current_equity = equity;
      if(!SolTradeCalculateRiskBudget(equity,
                                      m_config.risk_per_trade_percent,
                                      m_status.risk_budget,
                                      reason))
         return false;

      m_status.daily_profit_loss =
         equity - m_status.daily_start_equity;
      m_status.weekly_profit_loss =
         equity - m_status.weekly_start_equity;
      m_status.daily_drawdown_percent =
         MathMax(0.0,
                 ((m_status.daily_start_equity - equity) /
                  m_status.daily_start_equity) * 100.0);
      m_status.weekly_drawdown_percent =
         MathMax(0.0,
                 ((m_status.weekly_start_equity - equity) /
                  m_status.weekly_start_equity) * 100.0);

      m_status.emergency_armed =
         (m_config.production_baseline_equity > 0.0);
      if(m_status.emergency_armed)
        {
         m_status.emergency_drawdown_percent =
            MathMax(0.0,
                    ((m_config.production_baseline_equity - equity) /
                     m_config.production_baseline_equity) * 100.0);
        }
      else
         m_status.emergency_drawdown_percent = 0.0;

      if(!m_status.daily_locked &&
         m_status.daily_drawdown_percent + 1e-10 >=
            m_config.daily_loss_limit_percent)
        {
         m_status.daily_locked = true;
         state_changed         = true;
         AppendEvent(event_text, "DAILY_LOSS_LOCKED");
        }

      if(!m_status.weekly_locked &&
         m_status.weekly_drawdown_percent + 1e-10 >=
            m_config.weekly_loss_limit_percent)
        {
         m_status.weekly_locked = true;
         state_changed          = true;
         AppendEvent(event_text, "WEEKLY_LOSS_LOCKED");
        }

      if(m_status.emergency_armed &&
         !m_status.emergency_locked &&
         m_status.emergency_drawdown_percent + 1e-10 >=
            m_config.emergency_drawdown_percent)
        {
         m_status.emergency_locked = true;
         state_changed             = true;
         AppendEvent(event_text, "EMERGENCY_DRAWDOWN_LOCKED");
        }

      m_status.state_valid = true;
      m_status.state_error = "";
      UpdateLockReason();
      return true;
     }

   bool InitialiseFresh(const datetime server_time,
                        const double equity,
                        string &reason)
     {
      const long day_key  = SolTradeBrokerDayKey(server_time);
      const long week_key = SolTradeBrokerWeekKey(server_time);
      if(day_key <= 0 || week_key <= 0 ||
         !MathIsValidNumber(equity) || equity <= 0.0)
        {
         reason = "Cannot initialise risk baselines from time/equity";
         return false;
        }

      m_status.day_key                    = day_key;
      m_status.week_key                   = week_key;
      m_status.daily_start_equity         = equity;
      m_status.weekly_start_equity        = equity;
      m_status.daily_locked               = false;
      m_status.weekly_locked              = false;
      m_status.emergency_locked           = false;
      m_status.consecutive_locked         = false;
      m_status.consecutive_losses         = 0;
      m_status.consecutive_lock_day_key   = 0;
      m_last_outcome_id                   = "";
      return true;
     }

public:
   CSolTradeRiskEngine()
     {
      ResetSolTradeRiskStatus(m_status);
      m_persistence_enabled = true;
      m_state_path          = "";
      m_last_outcome_id     = "";
      m_revision            = 0;
      m_persistence_fault   = false;
     }

   bool Initialise(const SolTradeConfig &config,
                   const string account_identifier_hash,
                   const datetime server_time,
                   const double equity,
                   string &reason)
     {
      m_config              = config;
      m_persistence_enabled = true;
      m_revision            = 0;
      m_persistence_fault   = false;
      ResetSolTradeRiskStatus(m_status);

      string state_directory = config.risk_state_directory;
      StringReplace(state_directory, "/", "\\");
      m_state_path =
         state_directory + "\\risk_" + account_identifier_hash + "_" +
         StringFormat("%I64u", config.magic_number) + ".csv";

      bool found = false;
      if(!LoadState(found, reason))
        {
         m_status.initialised = true;
         m_status.state_valid = false;
         m_status.state_error = reason;
         UpdateLockReason();
         return false;
        }

      string event_text = "";
      if(!found)
        {
         if(!InitialiseFresh(server_time, equity, reason))
           {
            m_status.initialised = true;
            m_status.state_valid = false;
            m_status.state_error = reason;
            UpdateLockReason();
            return false;
           }
         AppendEvent(event_text, "RISK_STATE_INITIALISED");
        }
      else
         AppendEvent(event_text, "RISK_STATE_RESTORED");

      if(config.reset_emergency_lock && m_status.emergency_locked)
        {
         m_status.emergency_locked = false;
         AppendEvent(event_text, "EMERGENCY_LOCK_RESET_REQUESTED");
        }

      m_status.initialised = true;
      bool state_changed = !found || config.reset_emergency_lock;
      bool evaluated_change = false;
      string evaluated_event = "";
      if(!Evaluate(server_time,
                   equity,
                   evaluated_change,
                   evaluated_event,
                   reason))
        {
         m_status.state_valid = false;
         m_status.state_error = reason;
         UpdateLockReason();
         return false;
        }

      state_changed = state_changed || evaluated_change;
      AppendEvent(event_text, evaluated_event);
      m_status.last_event = event_text;

      if(state_changed && !SaveState(reason))
        {
         m_status.state_valid = false;
         m_status.state_error = reason;
         UpdateLockReason();
         return false;
        }

      m_revision++;
      return true;
     }

   bool InitialiseForTesting(const SolTradeConfig &config,
                             const datetime server_time,
                             const double equity,
                             string &reason)
     {
      m_config              = config;
      m_persistence_enabled = false;
      m_state_path          = "";
      m_last_outcome_id     = "";
      m_revision            = 0;
      m_persistence_fault   = false;
      ResetSolTradeRiskStatus(m_status);

      if(!InitialiseFresh(server_time, equity, reason))
         return false;

      m_status.initialised = true;
      bool changed = false;
      string event_text = "";
      if(!Evaluate(server_time,
                   equity,
                   changed,
                   event_text,
                   reason))
         return false;

      m_status.last_event = "TEST_RISK_STATE_INITIALISED";
      m_revision++;
      return true;
     }

   bool Refresh(const datetime server_time,
                const double equity,
                string &reason)
     {
      if(!m_status.initialised)
        {
         reason = "Risk engine is not initialised";
         return false;
        }

      bool state_changed = false;
      string event_text  = "";
      if(!Evaluate(server_time,
                   equity,
                   state_changed,
                   event_text,
                   reason))
        {
         m_status.state_valid = false;
         m_status.state_error = reason;
         UpdateLockReason();
         return false;
        }

      const bool recovering_persistence = m_persistence_fault;
      if(state_changed || recovering_persistence)
        {
         if(recovering_persistence)
            AppendEvent(event_text, "RISK_STATE_PERSISTENCE_RECOVERED");
         m_status.last_event = event_text;
         if(!SaveState(reason))
           {
            m_status.state_valid = false;
            m_status.state_error = reason;
            UpdateLockReason();
            return false;
           }
         m_revision++;
        }

      return true;
     }

   ENUM_SOLTRADE_OUTCOME_RESULT RecordClosedOutcome(
      const string outcome_id,
      const double net_profit,
      const datetime server_time,
      const double current_equity,
      string &reason)
     {
      reason = "";
      if(!m_status.initialised)
        {
         reason = "Risk engine is not initialised";
         return SOLTRADE_OUTCOME_ERROR;
        }

      if(StringLen(outcome_id) == 0 ||
         StringFind(outcome_id, ",") >= 0 ||
         StringFind(outcome_id, "\n") >= 0 ||
         !MathIsValidNumber(net_profit) ||
         !MathIsValidNumber(current_equity) ||
         current_equity <= 0.0)
        {
         reason = "Closed-outcome identifier, net result, or equity is invalid";
         return SOLTRADE_OUTCOME_ERROR;
        }

      if(!Refresh(server_time, current_equity, reason))
         return SOLTRADE_OUTCOME_ERROR;

      if(outcome_id == m_last_outcome_id)
        {
         reason = "Duplicate closed outcome ignored";
         return SOLTRADE_OUTCOME_DUPLICATE;
        }

      const int previous_losses = m_status.consecutive_losses;
      if(net_profit < 0.0)
         m_status.consecutive_losses++;
      else if(net_profit > 0.0)
         m_status.consecutive_losses = 0;
      // A true breakeven leaves the existing streak unchanged.

      string event_text = "CLOSED_OUTCOME_RECORDED";
      if(!m_status.consecutive_locked &&
         m_status.consecutive_losses >= m_config.consecutive_loss_limit)
        {
         m_status.consecutive_locked       = true;
         m_status.consecutive_lock_day_key = m_status.day_key;
         event_text = "CONSECUTIVE_LOSS_LOCKED";
        }
      else if(previous_losses > 0 &&
              m_status.consecutive_losses == 0)
         event_text = "CONSECUTIVE_LOSS_STREAK_RESET";

      m_last_outcome_id  = outcome_id;
      m_status.last_event = event_text;
      UpdateLockReason();

      if(!SaveState(reason))
        {
         m_status.state_valid = false;
         m_status.state_error = reason;
         UpdateLockReason();
         return SOLTRADE_OUTCOME_ERROR;
        }

      m_revision++;
      reason = event_text;
      return SOLTRADE_OUTCOME_RECORDED;
     }

   bool IsEntryLocked(string &reason)
     {
      UpdateLockReason();
      reason = m_status.lock_reason;
      return (!m_status.state_valid ||
              m_config.emergency_stop ||
              m_status.emergency_locked ||
              m_status.weekly_locked ||
              m_status.daily_locked ||
              m_status.consecutive_locked);
     }

   bool CalculateCurrentSymbolVolume(
      const double stop_distance,
      SolTradeRiskCalculation &calculation)
     {
      return SolTradeCalculatePositionSize(
         AccountInfoDouble(ACCOUNT_EQUITY),
         m_config.risk_per_trade_percent,
         stop_distance,
         SymbolInfoDouble(m_config.symbol, SYMBOL_TRADE_TICK_SIZE),
         SymbolInfoDouble(m_config.symbol, SYMBOL_TRADE_TICK_VALUE_LOSS),
         SymbolInfoDouble(m_config.symbol, SYMBOL_VOLUME_MIN),
         SymbolInfoDouble(m_config.symbol, SYMBOL_VOLUME_MAX),
         SymbolInfoDouble(m_config.symbol, SYMBOL_VOLUME_STEP),
         calculation);
     }

   void GetStatus(SolTradeRiskStatus &status)
     {
      status = m_status;
     }

   string LastOutcomeId()
     {
      return m_last_outcome_id;
     }

   long Revision()
     {
      return m_revision;
     }
  };

#endif // SOLTRADE_RISK_ENGINE_MQH
