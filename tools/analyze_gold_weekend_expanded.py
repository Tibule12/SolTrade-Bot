#!/usr/bin/env python3
"""Frozen, bar-estimate-only FP gold weekend experiment. Never connects to MT5."""

import argparse
import csv
import gzip
import json
import math
import random
from collections import defaultdict
from datetime import datetime, timedelta, timezone, time
from pathlib import Path
from statistics import mean, median
from zoneinfo import ZoneInfo

UTC = timezone.utc
FRAMES = {"M1": 1, "M15": 15, "H1": 60, "H4": 240}
METHODS = ("REOPEN", "AFTER_15M", "AFTER_30M", "DIRECTIONAL_H1", "PULLBACK_CONTINUATION", "FIRST_RANGE_BREAKOUT")
HORIZONS = (15, 30, 60, 240)
BARRIERS = (5, 10, 20)


def direction(a, b):
    return "BUY" if b > a else "SELL" if b < a else None


def load(path):
    # Tuesday's first broker hours can be the end of Monday's New York session.
    days = defaultdict(list)
    daily = {}
    count = 0
    first = last = None
    prior = None
    with (gzip.open(path,"rt",newline="") if path.suffix==".gz" else path.open(newline="")) as file:
        for raw in csv.DictReader(file):
            dt = datetime.fromtimestamp(int(raw["server_epoch"]), UTC).replace(tzinfo=None)
            if prior is not None and dt <= prior:
                raise ValueError("Non-increasing or duplicate broker M1 timestamp")
            prior = dt
            row = (dt, float(raw["bid_open"]), float(raw["bid_high"]), float(raw["bid_low"]),
                   float(raw["bid_close"]), int(raw["spread_points"]) * float(raw["point"]))
            if dt.weekday() in (0, 1, 4):
                days[dt.date()].append(row)
            d = daily.get(dt.date())
            if d is None:
                daily[dt.date()] = [row[1], row[2], row[3], row[4], 1]
            else:
                d[1] = max(d[1], row[2]); d[2] = min(d[2], row[3]); d[3] = row[4]; d[4] += 1
            first = first or dt
            last = dt
            count += 1
    return days, daily, {"rows": count, "first_server": str(first), "last_server": str(last), "daily_days": len(daily)}


def completed_frame(friday, minutes):
    if minutes == 1:
        return direction(friday[-1][1], friday[-1][4])
    for tail in reversed(friday):
        minute = tail[0].hour * 60 + tail[0].minute
        start_minute = minute // minutes * minutes
        block = [b for b in friday if start_minute <= b[0].hour * 60 + b[0].minute < start_minute + minutes]
        if (len(block) >= math.ceil(minutes * .75)
                and block[0][0].hour * 60 + block[0][0].minute <= start_minute + 1
                and block[-1][0].hour * 60 + block[-1][0].minute >= start_minute + minutes - 2):
            return direction(block[0][1], block[-1][4])
        # Jump to preceding block rather than rescanning every bar in the same block.
        friday = [b for b in friday if b[0].hour * 60 + b[0].minute < start_minute]
        if not friday:
            break
    return None


def atr_before(date, daily):
    dates = sorted(d for d in daily if d < date and daily[d][4] >= 120)
    if len(dates) < 15:
        return None
    values = []
    for d0, d1 in zip(dates[-15:-1], dates[-14:]):
        h, l, previous_close = daily[d1][1], daily[d1][2], daily[d0][3]
        values.append(max(h-l, abs(h-previous_close), abs(l-previous_close)))
    return mean(values)


def signals(friday, atr):
    opening, closing = friday[0][1], friday[-1][4]
    high, low = max(b[2] for b in friday), min(b[3] for b in friday)
    location = (closing-low)/(high-low) if high > low else .5
    ret = (closing-opening)/atr
    result = {name: completed_frame(friday, minutes) for name, minutes in FRAMES.items()}
    result["FRIDAY"] = direction(opening, closing)
    result["CLOSE_LOCATION"] = "BUY" if location >= .8 else "SELL" if location <= .2 else None
    result["ATR_RETURN"] = "BUY" if ret >= .75 else "SELL" if ret <= -.75 else None
    result["STRONG"] = "BUY" if ret >= .75 and location >= .8 else "SELL" if ret <= -.75 and location <= .2 else None
    for name, members in {"M1_H1": ("M1", "H1"), "H1_H4": ("H1", "H4"),
                          "H4_FRIDAY": ("H4", "FRIDAY"),
                          "ALL_AGREE": ("M1", "M15", "H1", "H4", "FRIDAY")}.items():
        values = [result[m] for m in members]
        result[name] = values[0] if values[0] and all(v == values[0] for v in values) else None
    for t in (.5, .75, 1.0):
        for q in (.1, .2, .3):
            result[f"STRONG_ATR_{t}_EDGE_{q}"] = (
                "BUY" if ret >= t and location >= 1-q else
                "SELL" if ret <= -t and location <= q else None)
    for q in (.1, .2, .3):
        result[f"LOCATION_EDGE_{q}"] = "BUY" if location >= 1-q else "SELL" if location <= q else None
    return result, {"friday_return_atr": ret, "friday_close_location": location, "friday_range_usd": high-low}


def entry_indices(monday, side):
    start = monday[0][0]
    out = {"REOPEN": 0}
    for name, minutes in (("AFTER_15M", 15), ("AFTER_30M", 30)):
        out[name] = next((i for i, b in enumerate(monday) if timedelta(minutes=minutes) <= b[0]-start <= timedelta(minutes=minutes+2)), None)
    out["DIRECTIONAL_H1"] = None
    for block in range(4):
        begin, end = start+timedelta(hours=block), start+timedelta(hours=block+1)
        segment = [b for b in monday if begin <= b[0] < end]
        if len(segment) >= 45 and segment[0][0] <= begin+timedelta(minutes=1) and segment[-1][0] >= end-timedelta(minutes=2):
            if direction(segment[0][1], segment[-1][4]) == side:
                out["DIRECTIONAL_H1"] = next((i for i, b in enumerate(monday) if end <= b[0] <= end+timedelta(minutes=2)), None)
                break
    out["PULLBACK_CONTINUATION"] = None
    peak = monday[0][1]
    phase = 0
    signed = 1 if side == "BUY" else -1
    for i, b in enumerate(monday):
        if b[0] >= start+timedelta(hours=4):
            break
        favorable = signed*(b[2] if side == "BUY" else b[3])
        close = signed*b[4]
        if phase == 0:
            peak = max(peak*signed, favorable)/signed
            if signed*(peak-monday[0][1]) >= 5:
                phase = 1
        elif phase == 1:
            if signed*(peak-b[4]) >= 2:
                phase = 2
            else:
                peak = max(signed*peak, favorable)/signed
        elif close >= signed*peak+1 and i+1 < len(monday) and monday[i+1][0]-b[0] <= timedelta(minutes=2):
            out["PULLBACK_CONTINUATION"] = i+1
            break
    out["FIRST_RANGE_BREAKOUT"] = None
    first = [b for b in monday if b[0] < start+timedelta(minutes=30)]
    if len(first) >= 23 and first[-1][0] >= start+timedelta(minutes=28):
        high, low = max(b[2] for b in first), min(b[3] for b in first)
        for i, b in enumerate(monday):
            if b[0] < start+timedelta(minutes=30):
                continue
            if b[0] >= start+timedelta(hours=4):
                break
            crossed = b[4] >= high+1 if side == "BUY" else b[4] <= low-1
            if crossed and i+1 < len(monday) and monday[i+1][0]-b[0] <= timedelta(minutes=2):
                out["FIRST_RANGE_BREAKOUT"] = i+1
                break
    return out


def quote_return(side, entry, bar):
    return bar[4]-entry if side == "BUY" else entry-(bar[4]+bar[5])


def extremes(side, entry, bar):
    return (bar[2]-entry, bar[3]-entry) if side == "BUY" else (entry-(bar[3]+bar[5]), entry-(bar[2]+bar[5]))


def endpoint(monday, start_index, target):
    return next((i for i in range(start_index, len(monday)) if target <= monday[i][0] <= target+timedelta(minutes=2)), None)


def session_endpoint(bars, start_index, target):
    # The broker may close its daily gold session immediately before this clock
    # time. Use a fresh completed quote at or before the boundary, never a quote
    # after the requested session has ended.
    return next((i for i in range(len(bars)-1, start_index-1, -1)
                 if target-timedelta(minutes=5) <= bars[i][0] <= target), None)


def evaluate(monday, side, index, monday_close_index=None):
    if index is None:
        return None
    start = monday[index][0]
    entry = monday[index][1] + (monday[index][5] if side == "BUY" else 0)
    result = {"entry_server": str(start), "entry_price_estimate": entry, "entry_spread_usd": monday[index][5]}
    for minutes in HORIZONS:
        j = endpoint(monday, index, start+timedelta(minutes=minutes))
        result[f"return_{minutes}m"] = None if j is None else quote_return(side, entry, monday[j])
    # Session conversion is a disclosed proxy, not a broker-certified historical offset.
    for label, zone, close_hour in (("LONDON", "Europe/London", 16), ("NY", "America/New_York", 17)):
        close = datetime.combine(start.date(), time(close_hour), ZoneInfo(zone)).astimezone(ZoneInfo("Europe/Athens")).replace(tzinfo=None)
        j = session_endpoint(monday, index, close) if close > start else None
        result[f"return_{label}"] = None if j is None else quote_return(side, entry, monday[j])
    monday_last = monday[-1] if monday_close_index is None else monday[monday_close_index]
    result["return_FULL_MONDAY"] = quote_return(side, entry, monday_last) if (monday_last[0]-monday[0][0]).total_seconds() >= 20*3600 else None
    end = min(start+timedelta(hours=4), monday[-1][0])
    window = [b for b in monday[index:] if b[0] <= end]
    gap = any(b[0]-a[0] > timedelta(minutes=5) for a, b in zip(window, window[1:]))
    result["barrier_4h_censored"] = bool(gap or not window or window[-1][0] < start+timedelta(hours=4)-timedelta(minutes=2))
    result["mfe_4h"] = max((extremes(side, entry, b)[0] for b in window), default=None)
    result["mae_4h"] = min((extremes(side, entry, b)[1] for b in window), default=None)
    for dollars in BARRIERS:
        first_fav = first_adv = None
        state = "CENSORED" if result["barrier_4h_censored"] else "NEITHER"
        if not result["barrier_4h_censored"]:
            for b in window:
                hi, lo = extremes(side, entry, b)
                fav, adv = hi >= dollars, lo <= -dollars
                if fav and first_fav is None:
                    first_fav = (b[0]-start).total_seconds()/60
                if adv and first_adv is None:
                    first_adv = (b[0]-start).total_seconds()/60
                if (fav or adv) and state == "NEITHER":
                    state = "AMBIGUOUS_SAME_BAR" if fav and adv else "FAVORABLE_FIRST" if fav else "ADVERSE_FIRST"
        result[f"barrier_{dollars}"] = state
        result[f"time_favorable_{dollars}m"] = first_fav
        result[f"time_adverse_{dollars}m"] = first_adv
    return result


def wilson(k, n):
    if not n: return None
    z = 1.96; p = k/n; den = 1+z*z/n
    center = (p+z*z/(2*n))/den
    half = z*math.sqrt(p*(1-p)/n+z*z/(4*n*n))/den
    return [round(center-half, 4), round(center+half, 4)]


def boot(values):
    if len(values) < 8: return None
    rng = random.Random(20261003+len(values))
    means = sorted(sum(rng.choices(values, k=len(values)))/len(values) for _ in range(1000))
    return [round(means[24], 4), round(means[974], 4)]


def summarize(rows, signal, side, method, split):
    eligible = [r for r in rows if r["split"] == split and r["signals"].get(signal) == side]
    selected = [r["paths"][side][method] for r in eligible if r["paths"][side][method] is not None]
    at4 = [p["return_240m"] for p in selected if p["return_240m"] is not None]
    gap_count = sum((r["gap_bid"] > 0) if side == "BUY" else (r["gap_bid"] < 0) for r in eligible)
    result = {"signal":signal,"side":side,"method":method,"split":split,"eligible_weekends":len(eligible),
              "entries":len(selected),"same_side_gap":gap_count,"same_side_gap_ci95":wilson(gap_count,len(eligible)),
              "continuation_4h":sum(x>0 for x in at4),"reversal_4h":sum(x<0 for x in at4),
              "continuation_4h_ci95":wilson(sum(x>0 for x in at4),len(at4)),
              "mean_4h":round(mean(at4),4) if at4 else None,"median_4h":round(median(at4),4) if at4 else None,
              "mean_4h_bootstrap_ci95":boot(at4),
              "median_mfe_4h":round(median(p["mfe_4h"] for p in selected if p["mfe_4h"] is not None),4) if selected else None,
              "median_mae_4h":round(median(p["mae_4h"] for p in selected if p["mae_4h"] is not None),4) if selected else None}
    for h in HORIZONS:
        vals=[p[f"return_{h}m"] for p in selected if p[f"return_{h}m"] is not None]
        result[f"n_{h}m"]=len(vals);result[f"mean_{h}m"]=round(mean(vals),4) if vals else None
        result[f"median_{h}m"]=round(median(vals),4) if vals else None
    for h in ("LONDON","NY","FULL_MONDAY"):
        vals=[p[f"return_{h}"] for p in selected if p[f"return_{h}"] is not None]
        result[f"n_{h}"]=len(vals);result[f"mean_{h}"]=round(mean(vals),4) if vals else None
        result[f"median_{h}"]=round(median(vals),4) if vals else None
    for d in BARRIERS:
        for outcome in ("FAVORABLE_FIRST","ADVERSE_FIRST","AMBIGUOUS_SAME_BAR","NEITHER","CENSORED"):
            result[f"barrier_{d}_{outcome.lower()}"]=sum(p[f"barrier_{d}"]==outcome for p in selected)
        for kind in ("favorable","adverse"):
            vals=[p[f"time_{kind}_{d}m"] for p in selected if p[f"time_{kind}_{d}m"] is not None]
            result[f"median_time_{kind}_{d}m"]=round(median(vals),2) if vals else None
    return result


def main(input_path, output):
    output.mkdir(parents=True, exist_ok=True)
    days,daily,coverage=load(input_path)
    rows=[]; missing=defaultdict(int)
    for friday_date in sorted(days):
        if friday_date.weekday()!=4: continue
        monday_date=friday_date+timedelta(days=3)
        friday,monday=days[friday_date],days.get(monday_date)
        if not monday: missing["no_monday"]+=1; continue
        hours=(monday[0][0]-friday[-1][0]).total_seconds()/3600
        if not 40<=hours<=80: missing["gap_outside_40_80h"]+=1; continue
        if len(friday)<40 or len(monday)<300: missing["partial_session"]+=1; continue
        atr=atr_before(friday_date,daily)
        if not atr: missing["missing_14_prior_days"]+=1; continue
        sig,meta=signals(friday,atr)
        tuesday = days.get(monday_date+timedelta(days=1), [])
        monday_path = monday + [b for b in tuesday if b[0].hour < 4]
        paths={}
        for side in ("BUY","SELL"):
            entries=entry_indices(monday,side)
            paths[side]={name:evaluate(monday_path,side,entries[name],len(monday)-1) for name in METHODS}
        rows.append({"friday":str(friday_date),"monday":str(monday_date),"signals":sig,"meta":meta,
                     "gap_bid":monday[0][1]-friday[-1][4],"paths":paths})
    if len(rows)<20: raise RuntimeError(f"Insufficient complete broker weekends: {len(rows)}")
    cut=max(1,int(len(rows)*.7))
    for i,r in enumerate(rows):r["split"]="IN_SAMPLE" if i<cut else "OUT_OF_SAMPLE"
    names=list(rows[0]["signals"])
    summaries=[summarize(rows,name,side,method,split) for name in names for side in ("BUY","SELL")
               for method in METHODS for split in ("IN_SAMPLE","OUT_OF_SAMPLE")]
    for r in rows:r["split_original"]=r["split"]
    all_summaries=[]
    for r in rows:r["split"]="ALL"
    all_summaries=[summarize(rows,name,side,method,"ALL") for name in names for side in ("BUY","SELL") for method in METHODS]
    for r in rows:r["split"]=r.pop("split_original")
    summaries+=all_summaries
    with (output/"results.csv").open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(summaries[0]));w.writeheader();w.writerows(summaries)
    with (output/"weekends.jsonl").open("w") as f:
        for r in rows:f.write(json.dumps(r,separators=(",",":"))+"\n")
    baseline=[]; random_returns=[]; long_returns=[]; short_returns=[]; strong=[]; ordinary=[]
    for r in rows:
        side=r["signals"]["FRIDAY"]
        buy=r["paths"]["BUY"]["REOPEN"]["return_240m"]
        sell=r["paths"]["SELL"]["REOPEN"]["return_240m"]
        if buy is not None and sell is not None:
            random_returns.append((buy+sell)/2);long_returns.append(buy);short_returns.append(sell)
        if side and r["paths"][side]["REOPEN"]["return_240m"] is not None:
            value=r["paths"][side]["REOPEN"]["return_240m"];baseline.append(value)
            (strong if r["signals"]["STRONG"]==side else ordinary).append(value)
    def stats(v):return {"n":len(v),"mean_4h":round(mean(v),4) if v else None,"median_4h":round(median(v),4) if v else None,"mean_ci95":boot(v)}
    positive=[r["paths"][r["signals"]["FRIDAY"]]["REOPEN"]["mae_4h"] for r in rows
              if r["signals"]["FRIDAY"] and r["paths"][r["signals"]["FRIDAY"]]["REOPEN"]["return_240m"] is not None
              and r["paths"][r["signals"]["FRIDAY"]]["REOPEN"]["return_240m"]>0]
    adverse=sorted(-x for x in positive if x is not None)
    summary={"coverage":coverage,"complete_weekends":len(rows),"missing_weekend_reasons":dict(missing),
             "split":{"in_sample":cut,"out_of_sample":len(rows)-cut,"cut_after_friday":rows[cut-1]["friday"]},
             "benchmarks":{"all_friday_direction":stats(baseline),"random_50_50_direction":stats(random_returns),
                           "unconditional_monday_buy":stats(long_returns),"unconditional_monday_sell":stats(short_returns),
                           "strong_friday_direction":stats(strong),"ordinary_friday_direction":stats(ordinary)},
             "adverse_4h_of_positive_friday_reopen":{"n":len(adverse),"median_usd":median(adverse) if adverse else None,
                  "p90_usd":adverse[min(len(adverse)-1,math.ceil(.9*len(adverse))-1)] if adverse else None}}
    (output/"summary.json").write_text(json.dumps(summary,indent=2)+"\n")
    return summary


if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("input",type=Path);p.add_argument("output",type=Path)
    a=p.parse_args();print(json.dumps(main(a.input,a.output),indent=2))
