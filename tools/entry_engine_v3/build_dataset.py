#!/usr/bin/env python3
"""Build independent transition episodes from SolTrade Brain Collector CSV/ZIP data.

The builder is intentionally independent of production BUY/SELL/admission scores.
It detects broad, symmetric market-activity episodes, records a WAIT trajectory,
and uses future executable bid/ask ticks only for outcome labels.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import zipfile
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator, TextIO

import numpy as np

from .common import EPISODE_COOLDOWN_SECONDS, HORIZON_SECONDS, WAIT_SECONDS, number, parse_state, utc_seconds


FEATURE_NAMES = [
    "wait_seconds", "rate_1s", "rate_5s", "rate_30s", "rate_burst_5v30",
    "quote_pressure_1s", "quote_pressure_5s", "quote_pressure_30s", "quote_pressure_share_5s",
    "trade_pressure_5s", "quote_acceleration_aligned", "mid_change_1s_aligned",
    "mid_change_5s_aligned", "mid_change_30s_aligned", "spread_points", "spread_5v30",
    "arrival_mean_ms_5s", "distance_day_open_aligned", "distance_session_open_aligned",
    "correlated_return_aligned", "correlated_alignment_fraction", "correlated_count",
    "scheduled_event_present", "minutes_to_event", "event_importance", "tick_size",
    "spread_cash_per_lot", "m1_trend_aligned", "m5_trend_aligned", "m15_trend_aligned",
    "h1_trend_aligned", "m1_structure_aligned", "m5_structure_aligned", "m15_structure_aligned",
    "h1_structure_aligned", "m1_return_aligned", "m5_return_aligned", "m15_return_aligned",
    "h1_return_aligned", "m1_vol_ratio", "m5_vol_ratio", "m15_vol_ratio",
    "m1_tick_volume", "m5_tick_volume", "m15_tick_volume", "m1_body_atr_aligned",
    "m5_body_atr_aligned", "stop_m1_atr", "stop_m5_atr", "cost_r",
    "d_quote_pressure_5s", "d_rate_5s", "d_spread_points", "d_mid_change_30s_aligned",
    "pullback_still_expanding", "resumption_evidence", "transition_pressure_score",
    "current_r_from_detection",
    "bid_change_from_detection_atr_aligned", "ask_change_from_detection_atr_aligned",
    "m1_trend_age_seconds", "m5_trend_age_seconds", "m15_trend_age_seconds", "h1_trend_age_seconds",
    "m1_impulse_displacement_atr_aligned", "m5_impulse_displacement_atr_aligned", "m15_impulse_displacement_atr_aligned",
    "pullback_depth_m1_atr", "remaining_room_m5_r", "remaining_room_m15_r",
    "adverse_structure_distance_m5_r", "adverse_structure_distance_m15_r",
]

OUTCOME_NAMES = [
    "mfe_r", "mae_r", "terminal_r", "seconds_to_plus_0_5", "seconds_to_plus_1",
    "seconds_to_plus_2", "seconds_to_plus_3", "seconds_to_plus_5", "seconds_to_minus_0_5",
    "seconds_to_minus_1", "maximum_continuation_r", "path_after_plus_1_r",
    "full_loss", "bank1", "plus_2", "plus_3", "plus_5", "expected_cost_r",
    "payoff_proxy_r", "structural_manager_r", "ratchet_loose_r", "ratchet_balanced_r",
    "ratchet_capture_r", "ratchet_loose_guaranteed_r", "ratchet_balanced_guaranteed_r",
    "ratchet_capture_guaranteed_r", "censored",
]

RATCHETS = {
    "loose": ((2.0, .25), (3.0, .75), (5.0, 1.50), (8.0, 3.0)),
    "balanced": ((1.5, .10), (2.5, .75), (4.0, 1.50), (6.0, 2.50), (10.0, 5.0)),
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


class Source:
    def __init__(self, path: Path):
        self.path = path
        self.archive = zipfile.ZipFile(path) if path.suffix.lower() == ".zip" else None

    def names(self, needle: str) -> list[str]:
        if self.archive:
            return sorted(n for n in self.archive.namelist() if needle in n and n.lower().endswith(".csv"))
        return sorted(str(p) for p in self.path.rglob("*.csv") if needle in str(p))

    def open(self, name: str) -> TextIO:
        if self.archive:
            return io.TextIOWrapper(self.archive.open(name), encoding="utf-8-sig", newline="")
        return open(name, encoding="utf-8-sig", newline="")

    def close(self) -> None:
        if self.archive:
            self.archive.close()


def feature_rows(source: Source) -> Iterator[dict[str, str]]:
    for name in source.names("features"):
        with source.open(name) as stream:
            yield from csv.DictReader(stream)


def raw_arrays(source: Source) -> dict[str, dict[str, np.ndarray]]:
    temporary: dict[str, dict[str, list[float]]] = defaultdict(lambda: {"time": [], "bid": [], "ask": []})
    for name in source.names("raw_ticks"):
        with source.open(name) as stream:
            for row in csv.DictReader(stream):
                symbol = row["symbol"]
                temporary[symbol]["time"].append(int(row["tick_time_utc_msc"]))
                temporary[symbol]["bid"].append(number(row["bid"]))
                temporary[symbol]["ask"].append(number(row["ask"]))
    result = {}
    for symbol, values in temporary.items():
        order = np.argsort(np.asarray(values["time"], dtype=np.int64), kind="stable")
        result[symbol] = {
            "time": np.asarray(values["time"], dtype=np.int64)[order],
            "bid": np.asarray(values["bid"], dtype=float)[order],
            "ask": np.asarray(values["ask"], dtype=float)[order],
        }
    return result


def aligned(value: float, direction: int) -> float:
    return value * direction


def normalized_pressure(row: dict[str, str], seconds: int) -> float:
    rate = number(row[f"rate_{seconds}s"])
    return number(row[f"quote_pressure_{seconds}s"]) / max(1.0, rate * seconds)


def detection(row: dict[str, str]) -> tuple[bool, int, str]:
    m1, m5, m15 = (parse_state(row[f"{tf}_completed_state"]) for tf in ("m1", "m5", "m15"))
    atr = max(m1.get("atr14", 0.0), 1e-12)
    move = number(row["mid_change_30s"]) / atr
    pressure = normalized_pressure(row, 5)
    burst = number(row["rate_5s"]) / max(number(row["rate_30s"]), 0.05)
    transition = int(np.sign(move + 0.35 * pressure + 0.20 * m1.get("trend", 0.0) + 0.10 * m5.get("trend", 0.0)))
    active = abs(move) >= 0.12 or abs(pressure) >= 0.30 or burst >= 1.8 or abs(m1.get("structure", 0.0)) > 0
    if not active or transition == 0:
        return False, 0, "NO_CAUSAL_ACTIVITY_TRANSITION"
    family = "PRESSURE_BURST" if abs(pressure) >= 0.30 else "RATE_BURST" if burst >= 1.8 else "STRUCTURE_TRANSITION"
    return True, transition, family


def base_values(row: dict[str, str], direction: int, first: dict[str, str], wait_seconds: int) -> dict[str, float]:
    bars = {tf: parse_state(row[f"{tf}_completed_state"]) for tf in ("m1", "m5", "m15", "h1")}
    first_pressure = normalized_pressure(first, 5)
    pressure = normalized_pressure(row, 5)
    spread30 = number(row["spread_mean_30s"])
    m1 = bars["m1"]
    def body_atr(bar: dict[str, float]) -> float:
        return (bar.get("close", 0.0) - bar.get("open", 0.0)) / max(bar.get("atr14", 0.0), 1e-12)
    values = {
        "wait_seconds": float(wait_seconds),
        "rate_1s": number(row["rate_1s"]), "rate_5s": number(row["rate_5s"]), "rate_30s": number(row["rate_30s"]),
        "rate_burst_5v30": number(row["rate_5s"]) / max(number(row["rate_30s"]), .05),
        "quote_pressure_1s": aligned(normalized_pressure(row, 1), direction),
        "quote_pressure_5s": aligned(pressure, direction), "quote_pressure_30s": aligned(normalized_pressure(row, 30), direction),
        "quote_pressure_share_5s": aligned(pressure, direction),
        "trade_pressure_5s": aligned(number(row["trade_pressure_5s"]) / max(1.0, number(row["rate_5s"])*5), direction),
        "quote_acceleration_aligned": aligned(number(row["quote_acceleration"]), direction),
        "mid_change_1s_aligned": aligned(number(row["mid_change_1s"]), direction),
        "mid_change_5s_aligned": aligned(number(row["mid_change_5s"]), direction),
        "mid_change_30s_aligned": aligned(number(row["mid_change_30s"]), direction),
        "spread_points": number(row["spread_points"]),
        "spread_5v30": number(row["spread_mean_5s"]) / max(spread30, 1e-12),
        "arrival_mean_ms_5s": number(row["arrival_mean_ms_5s"]),
        "distance_day_open_aligned": aligned(number(row["distance_from_day_open"]), direction),
        "distance_session_open_aligned": aligned(number(row["distance_from_session_open"]), direction),
        "correlated_return_aligned": aligned(number(row["correlated_return_mean"]), direction),
        "correlated_alignment_fraction": number(row["correlated_alignment_fraction"]),
        "correlated_count": number(row["correlated_count"]),
        "scheduled_event_present": 1.0 if row["scheduled_event_present"].lower()=="true" else 0.0,
        "minutes_to_event": number(row["minutes_to_event"], 1440.0), "event_importance": number(row["event_importance"]),
        "tick_size": number(row["tick_size"]), "spread_cash_per_lot": number(row["spread_cash_per_lot_estimate"]),
        "d_quote_pressure_5s": aligned(pressure-first_pressure, direction),
        "d_rate_5s": number(row["rate_5s"])-number(first["rate_5s"]),
        "d_spread_points": number(row["spread_points"])-number(first["spread_points"]),
        "d_mid_change_30s_aligned": aligned(number(row["mid_change_30s"])-number(first["mid_change_30s"]), direction),
    }
    for tf, bar in bars.items():
        values[f"{tf}_trend_aligned"] = aligned(bar.get("trend",0.0),direction)
        values[f"{tf}_structure_aligned"] = aligned(bar.get("structure",0.0),direction)
        values[f"{tf}_return_aligned"] = aligned(bar.get("return_3bar",0.0),direction)
        if tf in ("m1","m5","m15"):
            values[f"{tf}_vol_ratio"] = bar.get("vol_ratio",0.0)
            values[f"{tf}_tick_volume"] = bar.get("tick_volume",0.0)
    values["m1_body_atr_aligned"] = aligned(body_atr(bars["m1"]),direction)
    values["m5_body_atr_aligned"] = aligned(body_atr(bars["m5"]),direction)
    pullback = values["mid_change_30s_aligned"] < 0 and values["d_mid_change_30s_aligned"] < 0
    resume = values["quote_pressure_5s"] > .15 and values["mid_change_5s_aligned"] > 0 and values["m1_body_atr_aligned"] > 0
    values["pullback_still_expanding"] = float(pullback)
    values["resumption_evidence"] = float(resume)
    values["transition_pressure_score"] = values["quote_pressure_5s"] + .5*values["quote_acceleration_aligned"] + .5*float(resume) - .5*float(pullback)
    first_entry,_,first_risk,_,_=geometry(first,direction)
    current_exit=number(row["bid"] if direction>0 else row["ask"])
    values["current_r_from_detection"]=(current_exit-first_entry)*direction/max(first_risk,1e-12)
    atr1=max(bars["m1"].get("atr14",0.0),number(row["tick_size"]),1e-12)
    values["bid_change_from_detection_atr_aligned"]=aligned(number(row["bid"])-number(first["bid"]),direction)/atr1
    values["ask_change_from_detection_atr_aligned"]=aligned(number(row["ask"])-number(first["ask"]),direction)/atr1
    for tf in ("m1","m5","m15","h1"):
        values[f"{tf}_trend_age_seconds"]=number(row.get(f"_{tf}_trend_age_seconds"))
    for tf in ("m1","m5","m15"):
        bar=bars[tf];values[f"{tf}_impulse_displacement_atr_aligned"]=aligned(bar.get("return_3bar",0.0)*bar.get("close",0.0),direction)/max(bar.get("atr14",0.0),atr1)
    values["pullback_depth_m1_atr"]=max(0.0,-values["mid_change_30s_aligned"]/atr1)
    current_entry=number(row["ask"] if direction>0 else row["bid"])
    for tf in ("m5","m15"):
        bar=bars[tf]
        room=(bar.get("high",current_entry)-current_entry) if direction>0 else (current_entry-bar.get("low",current_entry))
        adverse=(current_entry-bar.get("low",current_entry)) if direction>0 else (bar.get("high",current_entry)-current_entry)
        values[f"remaining_room_{tf}_r"]=room/max(first_risk,1e-12)
        values[f"adverse_structure_distance_{tf}_r"]=adverse/max(first_risk,1e-12)
    return values


@dataclass
class Episode:
    episode_id: str
    symbol: str
    detected: int
    hypothesis: int
    family: str
    first: dict[str, str]
    observations: list[tuple[int, dict[str, str]]] = field(default_factory=list)


def build_episodes(source: Source) -> list[Episode]:
    active: dict[str, Episode] = {}
    blocked_until: dict[str, int] = defaultdict(int)
    episodes: list[Episode] = []
    counters: dict[str, int] = defaultdict(int)
    trend_value: dict[tuple[str,str],float] = {}
    trend_started: dict[tuple[str,str],int] = {}
    for row in feature_rows(source):
        if row.get("completed_bars_only","").lower() != "true" or row.get("order_capability","").lower() != "false":
            raise ValueError("collector causality/orderless invariant failed")
        now = utc_seconds(row["observation_utc"]); symbol=row["symbol"]
        for tf in ("m1","m5","m15","h1"):
            value=parse_state(row[f"{tf}_completed_state"]).get("trend",0.0);key=(symbol,tf)
            if key not in trend_value or value!=trend_value[key]:trend_value[key]=value;trend_started[key]=now
            row[f"_{tf}_trend_age_seconds"]=str(now-trend_started[key])
        episode=active.get(symbol)
        if episode:
            elapsed=now-episode.detected
            if elapsed <= WAIT_SECONDS:
                if not episode.observations or now-episode.observations[-1][0]>=15:
                    episode.observations.append((now,row))
            else:
                active.pop(symbol,None)
            continue
        if now < blocked_until[symbol]:
            continue
        ok,direction,family=detection(row)
        if not ok: continue
        counters[symbol]+=1
        eid=f"{symbol}-{now}-{counters[symbol]:04d}"
        episode=Episode(eid,symbol,now,direction,family,row,[(now,row)])
        episodes.append(episode);active[symbol]=episode;blocked_until[symbol]=now+EPISODE_COOLDOWN_SECONDS
    return episodes


def geometry(row: dict[str,str], direction: int) -> tuple[float,float,float,float,float]:
    m1=parse_state(row["m1_completed_state"]);m5=parse_state(row["m5_completed_state"]);m15=parse_state(row["m15_completed_state"])
    entry=number(row["ask"] if direction>0 else row["bid"])
    atr1=max(m1.get("atr14",0.0),number(row["tick_size"]),1e-12);atr5=max(m5.get("atr14",0.0),atr1)
    structural=(min(m5.get("low",entry),m15.get("low",entry)) if direction>0 else max(m5.get("high",entry),m15.get("high",entry)))
    floor=max(1.15*atr5,.55*max(m15.get("atr14",0.0),atr5))
    stop=(min(structural-.15*atr5,entry-floor) if direction>0 else max(structural+.15*atr5,entry+floor))
    risk=abs(entry-stop);spread=number(row["spread_price"]);cost=spread/risk if risk>0 else 99.0
    return entry,stop,risk,risk/atr1,risk/atr5


def whole_trade_ratchet(r: np.ndarray, tiers: tuple[tuple[float, float], ...] | None) -> tuple[float, float]:
    """Simulate Bank1R then a monotonic whole-trade guarantee on the half runner."""
    bank_hits=np.flatnonzero(r>=1.0)
    stop_hits=np.flatnonzero(r<=-1.0)
    if not len(bank_hits) or (len(stop_hits) and stop_hits[0]<bank_hits[0]):
        return (-1.0 if len(stop_hits) else float(np.clip(r[-1],-1.0,1.0))), -1.0
    start=int(bank_hits[0]); guaranteed=0.0; peak_whole=1.0
    for value in r[start:]:
        whole_peak=.5+.5*max(1.0,float(value));peak_whole=max(peak_whole,whole_peak)
        if tiers is None:
            # A deliberately loose convex capture schedule; no additional partial closes.
            candidate=max(0.0,.35*peak_whole-.25) if peak_whole>=2.0 else 0.0
        else:
            candidate=max((floor for trigger,floor in tiers if peak_whole>=trigger),default=0.0)
        guaranteed=max(guaranteed,candidate)
        runner_stop=2.0*guaranteed-1.0
        if value<=runner_stop:
            return guaranteed, guaranteed
    return .5+.5*float(r[-1]), guaranteed


def label(row: dict[str,str], direction:int, ticks:dict[str,np.ndarray]) -> dict[str,float|int|str]:
    at=int(row["observation_utc"])*1000; end=at+HORIZON_SECONDS*1000
    start_i=int(np.searchsorted(ticks["time"],at,"left"));end_i=int(np.searchsorted(ticks["time"],end,"right"))
    entry,stop,risk,stop1,stop5=geometry(row,direction)
    if end_i<=start_i or risk<=0:
        return {name:(1 if name=="censored" else "") for name in OUTCOME_NAMES}|{"stop_m1_atr":stop1,"stop_m5_atr":stop5,"cost_r":99.0}
    times=ticks["time"][start_i:end_i];exits=ticks["bid"][start_i:end_i] if direction>0 else ticks["ask"][start_i:end_i]
    r=(exits-entry)*direction/risk
    mfe=float(np.max(r));mae=float(np.min(r));terminal=float(r[-1])
    def hit(level:float,positive:bool)->float|str:
        idx=np.flatnonzero(r>=level) if positive else np.flatnonzero(r<=level)
        return (float(times[int(idx[0])]-at)/1000.0) if len(idx) else ""
    hits={"seconds_to_plus_0_5":hit(.5,True),"seconds_to_plus_1":hit(1,True),"seconds_to_plus_2":hit(2,True),
          "seconds_to_plus_3":hit(3,True),"seconds_to_plus_5":hit(5,True),"seconds_to_minus_0_5":hit(-.5,False),"seconds_to_minus_1":hit(-1,False)}
    plus1=hits["seconds_to_plus_1"];minus1=hits["seconds_to_minus_1"]
    bank=plus1!="" and (minus1=="" or float(plus1)<float(minus1));full=minus1!="" and not bank
    if bank:
        bank_i=int(np.flatnonzero(r>=1.0)[0]);later_stops=np.flatnonzero(r[bank_i:]<=-1.0)
        active_after1=r[bank_i:bank_i+int(later_stops[0])+1] if len(later_stops) else r[bank_i:]
    else: active_after1=np.asarray([])
    path_after=float(active_after1[-1]) if len(active_after1) else 0.0
    maximum_continuation=float(np.max(active_after1)) if len(active_after1) else 0.0
    stopped=minus1!=""
    cost_r=number(row["spread_price"])/risk
    structural,structural_floor=whole_trade_ratchet(r,())
    loose,loose_floor=whole_trade_ratchet(r,RATCHETS["loose"])
    balanced,balanced_floor=whole_trade_ratchet(r,RATCHETS["balanced"])
    capture,capture_floor=whole_trade_ratchet(r,None)
    payoff=structural
    return {"mfe_r":mfe,"mae_r":mae,"terminal_r":terminal,**hits,"maximum_continuation_r":maximum_continuation,
            "path_after_plus_1_r":path_after,"full_loss":int(full),"bank1":int(bank),"plus_2":int(bank and maximum_continuation>=2),
            "plus_3":int(bank and maximum_continuation>=3),"plus_5":int(bank and maximum_continuation>=5),"expected_cost_r":cost_r,
            "payoff_proxy_r":payoff,"structural_manager_r":structural,
            "ratchet_loose_r":loose,"ratchet_balanced_r":balanced,"ratchet_capture_r":capture,
            "ratchet_loose_guaranteed_r":loose_floor,"ratchet_balanced_guaranteed_r":balanced_floor,
            "ratchet_capture_guaranteed_r":capture_floor,
            "censored":int(times[-1]<end-1000 and not stopped),
            "stop_m1_atr":stop1,"stop_m5_atr":stop5,"cost_r":cost_r}


def main() -> int:
    parser=argparse.ArgumentParser();parser.add_argument("--source",type=Path,required=True);parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True);source=Source(args.source)
    try:
        episodes=build_episodes(source);ticks=raw_arrays(source)
        rows=[];episode_rows=[]
        for episode in episodes:
            episode_rows.append({"opportunity_id":episode.episode_id,"symbol":episode.symbol,"first_detection_utc":episode.detected,
                                 "direction_hypothesis":"LONG" if episode.hypothesis>0 else "SHORT","event_family":episode.family,
                                 "state":"WAIT_FOR_TRANSITION","wait_observations":len(episode.observations),
                                 "wait_expiry_utc":episode.detected+WAIT_SECONDS,"label_expiry_utc":episode.detected+HORIZON_SECONDS})
            if episode.symbol not in ticks: continue
            for observed,row in episode.observations:
                for direction in (1,-1):
                    values=base_values(row,direction,episode.first,observed-episode.detected)
                    outcome=label(row,direction,ticks[episode.symbol]);values.update({k:number(outcome.get(k)) for k in ("stop_m1_atr","stop_m5_atr","cost_r")})
                    rows.append({"opportunity_id":episode.episode_id,"symbol":episode.symbol,"event_family":episode.family,
                                 "first_detection_utc":episode.detected,"observation_utc":observed,"direction":"LONG" if direction>0 else "SHORT",
                                 "direction_hypothesis":"LONG" if episode.hypothesis>0 else "SHORT",**values,**outcome})
        with (args.output/"episodes.csv").open("w",newline="",encoding="utf-8") as f:
            w=csv.DictWriter(f,fieldnames=list(episode_rows[0]) if episode_rows else ["opportunity_id"]);w.writeheader();w.writerows(episode_rows)
        fields=["opportunity_id","symbol","event_family","first_detection_utc","observation_utc","direction","direction_hypothesis",*FEATURE_NAMES,*OUTCOME_NAMES]
        with (args.output/"observations.csv").open("w",newline="",encoding="utf-8") as f:
            w=csv.DictWriter(f,fieldnames=fields,extrasaction="ignore");w.writeheader();w.writerows(rows)
        manifest={"schema":"ENTRY_ENGINE_V3_DATASET_V1","source":str(args.source),"source_sha256":sha256(args.source) if args.source.is_file() else None,
                  "episodes":len(episode_rows),"observations":len(rows),"symbols":sorted({x["symbol"] for x in episode_rows}),
                  "first_detection_utc":min((x["first_detection_utc"] for x in episode_rows),default=None),
                  "last_detection_utc":max((x["first_detection_utc"] for x in episode_rows),default=None),
                  "independence_seconds":EPISODE_COOLDOWN_SECONDS,"wait_seconds":WAIT_SECONDS,"label_horizon_seconds":HORIZON_SECONDS,
                  "production_scores_used":False,"forming_bars_used":False,"future_used_as_features":False,"order_capability":False}
        (args.output/"dataset-manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
        (args.output/"feature-manifest.json").write_text(json.dumps({"schema":"ENTRY_ENGINE_V3_FEATURES_V1","features":FEATURE_NAMES,
             "causal_sources":["live executable quote","trailing tick windows ending at observation","completed M1/M5/M15/H1 bars","known event/calendar context","live cost properties"],
             "excluded":["production BUY/SELL/admission/no-trade scores as authority","future ticks","forming bars","outcomes","symbol identity as model input","raw LONG/SHORT identity (all directional features are mirrored)"],
             "unavailable_not_fabricated":["centralized order-book depth","true aggressor volume when broker flags are absent","commission when broker metadata is absent","pre-collector history for left-censored trend age"]},indent=2)+"\n")
        (args.output/"outcome-manifest.json").write_text(json.dumps({"schema":"ENTRY_ENGINE_V3_OUTCOMES_V1","outcomes":OUTCOME_NAMES,
             "entry_side":"ask for LONG, bid for SHORT","exit_side":"bid for LONG, ask for SHORT","horizon_seconds":HORIZON_SECONDS,
             "path_separation":"MFE/MAE and level-hit times retain the raw four-hour path. Continuation flags and maximum_continuation stop at the first executable structural stop after Bank1R.",
             "payoff_proxy":"Executable ask-to-bid or bid-to-ask path: -1R on pre-bank full loss; after Bank1R, 0.5R bank plus half-size terminal runner R. Spread is already embedded in the executable path and is not deducted twice.","future_only_for_labels":True},indent=2)+"\n")
        print(json.dumps(manifest,indent=2));return 0
    finally: source.close()


if __name__=="__main__":raise SystemExit(main())
