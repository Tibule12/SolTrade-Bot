#!/usr/bin/env python3
"""Read-only reconciliation of September 30 VPS state against frozen receipts."""
import csv
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


ROOT=Path(__file__).resolve().parents[1]
CAP=ROOT/'ops/forexvps/remote-output/full-readonly-audit-20260930'
OUT=ROOT/'reports/fast-multi-market-v2/full-live-audit-20260930'


def j(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def r(path):
    with path.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def stamp(value):return datetime.fromisoformat(value.replace('Z','+00:00'))


def main():
    first=j(CAP/'snapshot-before.json')
    final=j(CAP/'final-quick-state.json')
    expected=j(CAP/'expected-identities.json')
    prior=j(ROOT/'reports/fast-multi-market-v2/evaluator-repair-20260924/deployment.json')['after']
    pause=j(ROOT/'reports/fast-multi-market-v2/fxify-pause-20260916/verification.json')
    fxhash=j(CAP/'fxify-fresh-code-hashes.json')
    protect={}
    for name in ('fp','collector','tracker'):
        protect[name]={k:{'expected':v,'actual':first['identities'][name].get(k),'match':v==first['identities'][name].get(k)}
                       for k,v in prior['identities'][name].items() if k!='pids'}
        protect[name]['pid_unchanged']=first['identities'][name]['pids']==prior['identities'][name]['pids']
    config={p:{'expected':v,'actual':first['configuration_hashes'].get(p),'match':v==first['configuration_hashes'].get(p)}
            for p,v in prior['configuration_hashes'].items()}
    fxcodes={}
    for n,prefix in [('10k','fxify_10k'),('100k','fxify_100k')]:
        fxcodes[n]={k:{'expected':pause['hashes'][f'{prefix}_{k}'],'actual':fxhash[n][f'{k}_sha256'],
                       'match':pause['hashes'][f'{prefix}_{k}']==fxhash[n][f'{k}_sha256']} for k in ('source','binary')}
    lifecycle=[]
    for path in sorted(CAP.glob('lifecycle-202609*.csv')):lifecycle.extend(r(path))
    ownership=[x for x in lifecycle if x['event'].startswith('ACCOUNT_OWNERSHIP')]
    owner_counts=Counter(x['event'] for x in ownership)
    blocked_actions=Counter()
    blocked_reasons=Counter()
    for x in ownership:
        if x['event']=='ACCOUNT_OWNERSHIP_BLOCKED':
            detail=x['detail']
            a=re.search(r'detail=([^;]+)',detail)
            reason=re.search(r'reason=([^;]+)',detail)
            blocked_actions[a[1] if a else 'unknown']+=1
            blocked_reasons[reason[1] if reason else 'unknown']+=1
    authority=[]
    for line in (CAP/'fp-ownership-audit-tail.jsonl').read_text(encoding='utf-8-sig').splitlines():
        try:authority.append(json.loads(line))
        except json.JSONDecodeError:pass
    expires=[x for x in authority if x.get('event')=='STALE_LEASE_EXPIRED']
    expires_overdue=sorted(x['timestamp_epoch']-x['expires_epoch'] for x in expires)
    hb=first['evaluator_heartbeat'];run_ended=stamp(hb['run_finished_utc']);capture=stamp(first['captured_utc'])
    source_api={}
    for name,path in [('collector',ROOT/'tools/mql/brain-collector-v1/SolTradeBrainCollectorV1.mq5'),
                      ('tracker',ROOT/'tools/mql/full-lifetime-tracker-v1/SolTradeFullLifetimeTrackerV1.mq5')]:
        code=path.read_text()
        source_api[name]=re.findall(r'\b(?:OrderSend|CTrade|MqlTradeRequest|PositionClose|PositionModify|OrderDelete|MqlTradeTransaction)\b',code)
    output={'schema':'SOLTRADE_FULL_READONLY_AUDIT_20260930','read_only':True,'audit_orders_sent':0,'audit_positions_modified':0,
      'capture_utc':first['captured_utc'],'final_utc':final['utc'],
      'protected_hashes':protect,'configuration_hashes':config,'fxify_code_hashes':fxcodes,
      'all_protected_hashes_match':all(vv['match'] for group in protect.values() for vv in group.values() if isinstance(vv,dict)) and all(x['match'] for x in config.values()) and all(x['match'] for group in fxcodes.values() for x in group.values()),
      'fp':{'runtime_at_first':first['fp_runtime'],'runtime_at_final':final['fp_runtime'],
            'visual_broker_balance_at_1759_utc':94456.60,'visual_broker_equity_at_1759_utc':94847.27,
            'visual_broker_floating_profit_at_1759_utc':390.67,
            'visual_broker_position':{'ticket':'408708254','symbol':'ger40','direction':'SELL','volume':18.63,'entry':25209.75,'stop':25254.40,'current_price':25191.25},
            'ownership_state_at_final':final['ownership_state'],
            'ownership_lifecycle_counts_since_september24':dict(owner_counts),
            'ownership_blocked_actions':dict(blocked_actions),'ownership_blocked_reasons':dict(blocked_reasons),
            'ownership_authority_tail_window_utc':[authority[0]['timestamp_utc'],authority[-1]['timestamp_utc']] if authority else [],
            'ownership_authority_expirations_in_tail':len(expires),
            'ownership_authority_median_seconds_past_expiry':expires_overdue[len(expires_overdue)//2] if expires_overdue else None,
            'ownership_authority_max_seconds_past_expiry':max(expires_overdue,default=None)},
      'fxify':{'startup_blocks_at_first':first['fxify'],'startup_blocks_at_final':final['fxify'],
               'current_broker_exposure_verifiable':False,
               'reason':'Disabled EAs last published position/order status on September 16; no fresh independent broker exposure was captured.'},
      'collector':{'first':first['collector_heartbeat'],'final':final['collector']},
      'tracker':{'first':first['tracker_heartbeat'],'final':final['tracker']},
      'evaluator':{'last_published_heartbeat':hb,'published_age_hours_at_first':round((capture-run_ended).total_seconds()/3600,4),
                   'latest_progress_at_first':first['evaluator_progress'],
                   'latest_progress_at_final':final['evaluator_progress'],
                   'sequence':j(CAP/'sequence.json'),
                   'integrity_receipt':{'status':j(CAP/'integrity-receipt.json')['status'],
                                        'run_utc':j(CAP/'integrity-receipt.json')['run_utc'],
                                        'passed_checks':sum(x['passed'] for x in j(CAP/'integrity-receipt.json')['checks']),
                                        'total_checks':len(j(CAP/'integrity-receipt.json')['checks'])}},
      'tasks_at_first':first['tasks'],'tasks_at_final':final['tasks'],
      'research_program_trade_api_tokens':source_api,
      'cost_evidence_limit':'Repo/VPS capture lacks FXIFY purchase invoices and VPS billing; actual out-of-pocket fees cannot be calculated.',
      'limitations':['FP GUI balance/equity is a visual observation at 17:59 UTC and changes with the open position.',
                     'Snapshots are not atomic; hashes, runtimes, task status and GUI values have their own capture times.',
                     'FXIFY EA runtime position/order rows are stale from September 16; entry block is freshly verified but current exposure is not.']}
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'operations.json').write_text(json.dumps(output,indent=2)+'\n')
    print(json.dumps({'all_protected_hashes_match':output['all_protected_hashes_match'],
      'fp_final':{k:final['fp_runtime'][k] for k in ('timestamp_utc','entry_permission','autonomous_entry','positions','orders','equity')},
      'owner_counts':dict(owner_counts),'blocked_actions':dict(blocked_actions),
      'authority_expirations':len(expires),'evaluator_age_hours':output['evaluator']['published_age_hours_at_first']},indent=2))


if __name__=='__main__':main()
