#ifndef SOLTRADE_PHASE6_V9_HASHING_MQH
#define SOLTRADE_PHASE6_V9_HASHING_MQH

const int V9_HASH_CHUNK_TICKS = 256;
const ulong V9_RESEARCH_CUTOFF =
   (ulong)D'2025.12.24 00:00:00' * 1000;
const ulong V9_PRE_FINAL_H1 =
   (ulong)D'2025.12.23 23:00:00' * 1000;
const ulong V9_FINAL_DAY =
   (ulong)D'2025.12.23 00:00:00' * 1000;
const ulong V9_FINAL_MINUTE =
   (ulong)D'2025.12.23 23:59:00' * 1000;

struct V9HashState
  {
   string probe;
   string source;
   string scope;
   string key;
   string chain;
   string buffer;
   ulong count;
   ulong chunks;
   ulong first_msc;
   ulong last_msc;
   ulong buffer_count;
   ulong buffer_first_msc;
   ulong buffer_last_msc;
  };

struct V9StreamSet
  {
   string probe;
   string source;
   ulong start_msc;
   ulong end_msc;
   V9HashState complete;
   V9HashState months[13];
   int month_count;
   int active_month;
   V9HashState pre_final_h1;
   V9HashState final_day;
   V9HashState final_hour;
   V9HashState final_minute;
   V9HashState guard_tail;
  };

string V9Sha256(const string value)
  {
   uchar source[];
   uchar key[];
   uchar digest[];
   int size = StringToCharArray(value, source, 0, -1, CP_UTF8);
   if(size > 0)
      ArrayResize(source, size - 1);
   if(CryptEncode(CRYPT_HASH_SHA256, source, key, digest) <= 0)
      return "";
   string result = "";
   for(int index = 0; index < ArraySize(digest); index++)
      result += StringFormat("%02x", digest[index]);
   return result;
  }

string V9Timestamp(const ulong value)
  {
   if(value == 0)
      return "NONE";
   return TimeToString((datetime)(value / 1000),
                       TIME_DATE | TIME_SECONDS) +
          "." + StringFormat("%03u", (uint)(value % 1000));
  }

string V9TickRecord(const MqlTick &tick)
  {
   return StringFormat(
      "%I64u|%.10f|%.10f|%.10f|%I64u|%u|%.10f\n",
      (ulong)tick.time_msc,
      tick.bid,
      tick.ask,
      tick.last,
      tick.volume,
      tick.flags,
      tick.volume_real);
  }

void V9HashInit(V9HashState &state,
                const string probe,
                const string source,
                const string scope,
                const string key)
  {
   ZeroMemory(state);
   state.probe = probe;
   state.source = source;
   state.scope = scope;
   state.key = key;
   state.chain = V9Sha256("SOLTRADE_PHASE6_V9_STREAM_V1|" +
                          scope + "|" + key);
  }

bool V9HashFlush(V9HashState &state)
  {
   if(state.buffer_count == 0)
      return true;
   const string chunk_hash = V9Sha256(state.buffer);
   if(chunk_hash == "")
      return false;
   state.chunks++;
   state.chain = V9Sha256(
      state.chain + "|" + IntegerToString((long)state.chunks) +
      "|" + IntegerToString((long)state.buffer_count) +
      "|" + IntegerToString((long)state.buffer_first_msc) +
      "|" + IntegerToString((long)state.buffer_last_msc) +
      "|" + chunk_hash);
   state.buffer = "";
   state.buffer_count = 0;
   state.buffer_first_msc = 0;
   state.buffer_last_msc = 0;
   return state.chain != "";
  }

bool V9HashAdd(V9HashState &state,
               const string record,
               const ulong time_msc)
  {
   if(state.count == 0)
      state.first_msc = time_msc;
   if(state.buffer_count == 0)
      state.buffer_first_msc = time_msc;
   state.last_msc = time_msc;
   state.buffer_last_msc = time_msc;
   state.buffer += record;
   state.count++;
   state.buffer_count++;
   if(state.buffer_count >= (ulong)V9_HASH_CHUNK_TICKS)
      return V9HashFlush(state);
   return true;
  }

string V9MonthKey(const ulong time_msc)
  {
   MqlDateTime parts;
   TimeToStruct((datetime)(time_msc / 1000), parts);
   return StringFormat("%04d-%02d", parts.year, parts.mon);
  }

void V9StreamInit(V9StreamSet &stream,
                  const string probe,
                  const string source,
                  const datetime start_time,
                  const datetime end_time)
  {
   ZeroMemory(stream);
   stream.probe = probe;
   stream.source = source;
   stream.start_msc = (ulong)start_time * 1000;
   stream.end_msc = (ulong)end_time * 1000;
   stream.active_month = -1;
   V9HashInit(stream.complete, probe, source, "COMPLETE", "ALL");
   V9HashInit(stream.pre_final_h1, probe, source,
              "PRE_FINAL_H1", "BEFORE_2025-12-23T23:00:00");
   V9HashInit(stream.final_day, probe, source,
              "FINAL_RESEARCH_DAY", "2025-12-23");
   V9HashInit(stream.final_hour, probe, source,
              "FINAL_RESEARCH_H1", "2025-12-23T23");
   V9HashInit(stream.final_minute, probe, source,
              "FINAL_RESEARCH_M1", "2025-12-23T23:59");
   V9HashInit(stream.guard_tail, probe, source,
              "POST_RESEARCH_GUARD", "2025-12-24");
  }

int V9FindOrAddMonth(V9StreamSet &stream, const string key)
  {
   if(stream.active_month >= 0 &&
      stream.months[stream.active_month].key == key)
      return stream.active_month;
   for(int index = 0; index < stream.month_count; index++)
      if(stream.months[index].key == key)
        {
         stream.active_month = index;
         return index;
        }
   if(stream.month_count >= 13)
      return -1;
   const int result = stream.month_count++;
   V9HashInit(stream.months[result], stream.probe, stream.source,
              "CALENDAR_MONTH", key);
   stream.active_month = result;
   return result;
  }

bool V9StreamAdd(V9StreamSet &stream,
                 const MqlTick &tick,
                 const string record)
  {
   const ulong time_msc = (ulong)tick.time_msc;
   if(time_msc < stream.start_msc || time_msc >= stream.end_msc)
      return true;
   if(!V9HashAdd(stream.complete, record, time_msc))
      return false;
   const int month = V9FindOrAddMonth(stream, V9MonthKey(time_msc));
   if(month < 0 || !V9HashAdd(stream.months[month], record, time_msc))
      return false;
   if(time_msc < V9_PRE_FINAL_H1 &&
      !V9HashAdd(stream.pre_final_h1, record, time_msc))
      return false;
   if(time_msc >= V9_FINAL_DAY && time_msc < V9_RESEARCH_CUTOFF &&
      !V9HashAdd(stream.final_day, record, time_msc))
      return false;
   if(time_msc >= V9_PRE_FINAL_H1 && time_msc < V9_RESEARCH_CUTOFF &&
      !V9HashAdd(stream.final_hour, record, time_msc))
      return false;
   if(time_msc >= V9_FINAL_MINUTE && time_msc < V9_RESEARCH_CUTOFF &&
      !V9HashAdd(stream.final_minute, record, time_msc))
      return false;
   if(time_msc >= V9_RESEARCH_CUTOFF &&
      !V9HashAdd(stream.guard_tail, record, time_msc))
      return false;
   return true;
  }

void V9HashPrint(V9HashState &state)
  {
   const bool flushed = V9HashFlush(state);
   PrintFormat(
      "SOLTRADE_PHASE6_V9_STREAM | probe=%s | source=%s | scope=%s | key=%s | count=%I64u | first=%s | final=%s | chunks=%I64u | sha256=%s | valid=%s",
      state.probe, state.source, state.scope, state.key,
      state.count, V9Timestamp(state.first_msc),
      V9Timestamp(state.last_msc), state.chunks,
      state.chain, flushed ? "YES" : "NO");
  }

void V9StreamPrint(V9StreamSet &stream)
  {
   V9HashPrint(stream.complete);
   for(int index = 0; index < stream.month_count; index++)
      V9HashPrint(stream.months[index]);
   V9HashPrint(stream.pre_final_h1);
   V9HashPrint(stream.final_day);
   V9HashPrint(stream.final_hour);
   V9HashPrint(stream.final_minute);
   V9HashPrint(stream.guard_tail);
  }

#endif
