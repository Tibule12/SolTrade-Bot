#!/usr/bin/env python3
"""Read-only reconstruction of frozen forward evidence; never trains or trades."""
import argparse
import csv
import io
import json
import math
import re
import sys
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.forward_evidence.evaluator import (CANDIDATE_IDS, candidate_summary,
    entry_quality, flag, number, payoff_metrics, quality_calibration, validate_right_censored)


def rows(path):
    with path.open(encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


def zip_rows(z, prefix):
    result=[]
    for name in sorted(n for n in z.namelist() if n.startswith(prefix+'/') and n.endswith('.csv')):
        with z.open(name) as f:
            result.extend(csv.DictReader(io.TextIOWrapper(f,encoding='utf-8-sig')))
    return result


def audit(source, destination):
    with zipfile.ZipFile(source/'tracker-all-quick.zip') as z:
        events=zip_rows(z,'events')
        raw=zip_rows(z,'outcomes')
    latest = {}
    for r in raw:
        key = (r['opportunity_id'], r['candidate_id'])
        if key not in latest or number(r['terminal_utc']) >= number(latest[key]['terminal_utc']):
            latest[key] = r
    censored_errors = validate_right_censored(raw)
    event_counts=Counter(e['event'] for e in events)
    detected=[e for e in events if e['event']=='OPPORTUNITY_DETECTED']
    per_symbol=defaultdict(list)
    for e in detected:per_symbol[e['symbol']].append(number(e['utc_msc'])/1000)
    episode_gaps=[b-a for times in per_symbol.values() for a,b in zip(sorted(times),sorted(times)[1:])]
    fire_times=defaultdict(list)
    for e in events:
        if e['event']=='CAUSAL_INVALIDATION':fire_times[e['opportunity_id']].append(number(e['utc_msc']))
    eligible = sorted((r.copy() for r in latest.values() if r['outcome_status'] == 'TERMINAL'
                       and flag(r['baseline_final_r_known']) and flag(r['aftermath_complete'])
                       and flag(r['causal_final_r_known'])), key=lambda r:(number(r['entry_utc']),r['opportunity_id'],r['candidate_id']))
    entries = {}
    for e in events:
        if e['event'] == 'ENTRY_TRIGGERED':
            entries.setdefault(e['opportunity_id'], e)
    for r in eligible:
        r['candidate_final_r'] = number(r['causal_final_r'])
        r['candidate_fired'] = flag(r['causal_exit_triggered'])
        r['reached_plus_1_after_exit'] = r['reached_bank1_after_exit']
        r['delta_r'] = r['candidate_final_r'] - number(r['baseline_final_r'])
        r['r_saved'] = max(0.0, r['delta_r'])
        r['r_lost'] = max(0.0, -r['delta_r'])
        detail = entries.get(r['opportunity_id'], {}).get('detail', '')
        m = re.search(r'expected_net_r=([-+.\deE]+)', detail)
        r['entry_expected_r'] = float(m[1]) if m else None
        r['entry_quality'] = entry_quality(r['entry_expected_r']) if m else -1
        for n in (2,3,5):
            r[f'baseline_plus_{n}'] = number(r['mfe_r']) >= n
    baseline = [r for r in eligible if r['candidate_id'] == CANDIDATE_IDS[0]]
    published = rows(source / 'per-trade-evidence.csv')
    pub_ids = {r['opportunity_id'] for r in published}
    old = Path('reports/fast-multi-market-v2/evaluator-repair-20260924/per-trade-evidence.csv')
    old_ids = {r['opportunity_id'] for r in rows(old)}
    parity = []
    lookup = {(r['opportunity_id'],r['candidate_id']):r for r in eligible}
    for p in published:
        k = (p['opportunity_id'],p['candidate_id'])
        if k not in lookup:
            parity.append({'key':k,'issue':'published outcome missing from raw'})
            continue
        r=lookup[k]
        for col, alt in [('baseline_final_r','baseline_final_r'),('candidate_final_r','candidate_final_r'),('r_saved_vs_baseline','r_saved'),('r_lost_vs_baseline_if_interrupted','r_lost')]:
            if col in p and abs(number(p[col])-number(r[alt])) > 2e-7:
                parity.append({'key':k,'field':col,'published':p[col],'reconstructed':r[alt]})
    def cohort(rs):
        return {'baseline':payoff_metrics(rs,'baseline_final_r'),
                'baseline_terminal_order':payoff_metrics(sorted(rs,key=lambda r:number(r['terminal_utc'])),'baseline_final_r'),
                'initial_stop_losses':sum(r['terminal_reason']=='INITIAL_STRUCTURAL_STOP' for r in rs),
                'bank1_paths':sum(flag(r['bank1_reached']) for r in rs),
                'plus_2_3_5_paths':{n:sum(number(r['mfe_r'])>=n for r in rs) for n in (2,3,5)},
                'long':sum(r['direction']=='LONG' for r in rs),'short':sum(r['direction']=='SHORT' for r in rs),
                'quality_calibration':quality_calibration(rs)}
    candidates={c:candidate_summary(eligible,c) for c in CANDIDATE_IDS}
    for c in CANDIDATE_IDS:
        rr=[r for r in eligible if r['candidate_id']==c]
        candidates[c]['gross_r_saved'] = sum(r['r_saved'] for r in rr)
        candidates[c]['gross_r_lost'] = sum(r['r_lost'] for r in rr)
        candidates[c]['profitable_trades_interrupted']=sum(r['candidate_fired'] and number(r['baseline_final_r'])>0 for r in rr)
        candidates[c]['post_september24_snapshot']=candidate_summary([r for r in eligible if r['opportunity_id'] not in old_ids],c)
    integrity={'right_censor_errors':censored_errors,'published_numeric_parity_errors':parity,
               'raw_terminal_rows':len(raw),'unique_outcome_keys':len(latest),'eligible_comparisons':len(eligible),
               'published_positions':len(pub_ids),'tracker_complete_positions':len(baseline),
               'unique_detected_opportunities':len({e['opportunity_id'] for e in detected}),
               'minimum_same_symbol_episode_gap_seconds':min(episode_gaps,default=None),
               'episode_gaps_under_four_hours':sum(g<14400 for g in episode_gaps),
               'duplicate_event_keys':len(events)-len({(e['opportunity_id'],e['utc_msc'],e['event'],e['candidate_id']) for e in events}),
               'four_outcome_candidates_per_position':all(sum(r['opportunity_id']==o for r in latest.values())==4 for o in {r['opportunity_id'] for r in latest.values()}),
               'detected_partition_matches':event_counts['OPPORTUNITY_DETECTED']==event_counts['OPPORTUNITY_ABANDONED']+event_counts['ENTRY_TRIGGERED'],
               'bank_once_matches_outcomes':event_counts['BANK1R']==sum(flag(r['bank1_reached']) for r in baseline),
               'missing_published_opportunities':sorted(set(r['opportunity_id'] for r in baseline)-pub_ids)}
    # Independently audit persisted observations, not just heartbeat assertions.
    lifetime={'rows':0,'opportunities':{},'violations':[],'limits':['Raw quote timestamp/age is not a persisted lifetime column; stale-quote rejection cannot be independently proved for every row.','Timing gaps can be intentional market closures, stale quote rejection, or load; five seconds is a target, not assumed proof.']}
    seen=set(); gaps=[]; by_id={r['opportunity_id']:r for r in baseline}
    with zipfile.ZipFile(source/'tracker-all-quick.zip') as z:
        for name in sorted(z.namelist()):
            if not name.startswith('lifetime_observations/') or not name.endswith('.csv'):
                continue
            with z.open(name) as f:
                for r in csv.DictReader(io.TextIOWrapper(f,encoding='utf-8-sig')):
                    lifetime['rows']+=1
                    oid=r['opportunity_id']; t=int(r['observation_utc_msc']); key=(oid,t)
                    if key in seen:lifetime['violations'].append({'type':'duplicate_observation','opportunity_id':oid,'utc_msc':t})
                    seen.add(key)
                    a=lifetime['opportunities'].setdefault(oid,{'rows':0,'first_utc_msc':t,'last_utc_msc':t,'banked_rows':0,'after_invalidation_rows':0,'beyond_four_hours_rows':0,'max_gap_seconds':0})
                    if a['rows']:
                        gap=(t-a['last_utc_msc'])/1000;gaps.append(gap);a['max_gap_seconds']=max(a['max_gap_seconds'],gap)
                    a['rows']+=1;a['last_utc_msc']=t
                    a['banked_rows']+=flag(r.get('bank1_reached'))
                    if fire_times.get(oid) and t>min(fire_times[oid]):a['after_invalidation_rows']+=1
                    b=by_id.get(oid)
                    if b and t>number(b['entry_utc'])*1000+14400000:a['beyond_four_hours_rows']+=1
                    if b and t>number(b['terminal_utc'])*1000:lifetime['violations'].append({'type':'observation_after_baseline_terminal','opportunity_id':oid,'utc_msc':t})
                    for k in ('completed_bars_only','feature_window_ready'):
                        if k in r and not flag(r[k]):lifetime['violations'].append({'type':k,'opportunity_id':oid,'utc_msc':t})
                    if flag(r.get('order_capability')):lifetime['violations'].append({'type':'order_capability','opportunity_id':oid,'utc_msc':t})
                    for k,v in r.items():
                        if k.endswith('_state') or k.endswith('_structure'):
                            m=re.search(r'(?:^|;)end_utc=(\d+)',v)
                            if m and int(m[1])*1000>t:lifetime['violations'].append({'type':'future_completed_bar','field':k,'opportunity_id':oid,'utc_msc':t})
    gaps.sort()
    lifetime['cadence']={'gaps':len(gaps),'median_seconds':gaps[len(gaps)//2] if gaps else None,
                         'p95_seconds':gaps[min(len(gaps)-1,int(len(gaps)*.95))] if gaps else None,
                         'gaps_over_10_seconds':sum(g>10 for g in gaps),'max_seconds':max(gaps,default=None)}
    result={'audit_only':True,'order_capability':False,'tuning_performed':False,
            'event_counts':dict(event_counts),
            'all_completed':cohort(baseline),'new_completed_since_september24_capture':cohort([r for r in baseline if r['opportunity_id'] not in old_ids]),
            'candidates':candidates,'integrity':integrity,'lifetime_audit':lifetime,
            'first_trigger':min(entries.values(),key=lambda e:number(e['utc_msc'])) if entries else None,
            'first_completed':min(baseline,key=lambda r:number(r['terminal_utc'])) if baseline else None,
            'method':'Entry-order R drawdown matches frozen evaluator convention; terminal-order drawdown also supplied. R is standardized hypothetical trade risk, not account cash. Invalidation interruption counts use AFTER-exit flags. No inference of model profitability from audit.'}
    destination.mkdir(parents=True,exist_ok=True)
    (destination/'forward-analysis.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    if eligible:
        with (destination/'forward-comparisons.csv').open('w',newline='') as f:
            w=csv.DictWriter(f,fieldnames=list(eligible[0]));w.writeheader();w.writerows(eligible)
    print(json.dumps({k:result[k] for k in ('event_counts','all_completed','new_completed_since_september24_capture','integrity')},indent=2))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();audit(a.source,a.output)
