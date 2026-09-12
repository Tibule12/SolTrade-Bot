#!/usr/bin/env python3
"""Build the FP-only Bank1R pre-bank giveback repair."""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from build_v202_validation import function_span

HERE = Path(__file__).resolve().parent
BASE = ROOT / "ops/forexvps/releases/fp-adaptive-payoff-v1-bank1r-20260911/SolTradeFastMultiMarketV2.mq5"
BASE_SHA = "ffb9494014430db58d0c99c3857b54b432c237bb9795d2422cf33b93eeeb4ce4"
OUT = HERE / "SolTradeFastMultiMarketV2.mq5"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def replace_once(source: str, old: str, new: str) -> str:
    assert source.count(old) == 1, (old[:80], source.count(old))
    return source.replace(old, new, 1)


def build() -> None:
    assert sha(BASE.read_bytes()) == BASE_SHA
    original = BASE.read_text()
    source = original

    source = replace_once(
        source,
        "#define AP_STATE_STRUCTURAL_RUNNER 3\n#define AP_EXIT_ENTRY_PROBATION_FAILED 1",
        "#define AP_STATE_STRUCTURAL_RUNNER 3\n#define AP_STATE_PRE_BANK_GIVEBACK 4\n#define AP_EXIT_ENTRY_PROBATION_FAILED 1",
    )
    source = replace_once(
        source,
        "#define AP_EXIT_ACCOUNT_RISK 5",
        "#define AP_EXIT_ACCOUNT_RISK 5\n#define AP_EXIT_PRE_BANK_GIVEBACK_FAILED 6",
    )
    source = replace_once(
        source,
        '   if(state==AP_STATE_PRE_BANK_PROFIT) return "PRE_BANK_PROFIT";\n   if(state==AP_STATE_STRUCTURAL_RUNNER) return "STRUCTURAL_RUNNER";',
        '   if(state==AP_STATE_PRE_BANK_PROFIT) return "PRE_BANK_PROFIT";\n   if(state==AP_STATE_PRE_BANK_GIVEBACK) return "PRE_BANK_GIVEBACK";\n   if(state==AP_STATE_STRUCTURAL_RUNNER) return "STRUCTURAL_RUNNER";',
    )
    source = replace_once(
        source,
        '   if(reason==AP_EXIT_ACCOUNT_RISK) return "ACCOUNT_RISK_EXIT";',
        '   if(reason==AP_EXIT_ACCOUNT_RISK) return "ACCOUNT_RISK_EXIT";\n   if(reason==AP_EXIT_PRE_BANK_GIVEBACK_FAILED) return "PRE_BANK_GIVEBACK_FAILED";',
    )

    start, end = function_span(source, "ManageFastPositions")
    manager = source[start:end]
    old_evidence = '''      bool structural_deterioration=scored && score.fresh && !structure_broken && !normal_pullback &&
         ((score.direction==-direction && direction*score.trend_m5<-0.20 && direction*score.trend_m15<=0.05 && opposite_score>=held_score+MinDirectionalDominance) ||
          (opposite_structure && direction*score.trend_m15<=0.05 && opposite_score>held_score));'''
    new_evidence = old_evidence + '''
      // A pre-bank giveback may fail on the already-computed opposing setup:
      // fresh opposite direction, opposite structure and existing dominance.
      // R alone never supplies the causal half of this decision.
      bool pre_bank_opposing_failure=scored && score.fresh && !structure_broken &&
         score.direction==-direction && opposite_structure &&
         opposite_score>=held_score+MinDirectionalDominance;
      bool pre_bank_causal_failure=structural_deterioration || pre_bank_opposing_failure;'''
    manager = replace_once(manager, old_evidence, new_evidence)

    old_transition = '''      if(state==AP_STATE_HEALTHY_POSITION && runner.peak_r>=0.50)
        { APTransition(identifier,AP_STATE_PRE_BANK_PROFIT,score,ticket,StringFormat("peak_r=%.5f;monetary_trailing_enabled=false",runner.peak_r)); state=AP_STATE_PRE_BANK_PROFIT; }

      bool banked=FPTryBank(ticket,identifier,symbol,bank_trigger_r,bank_trigger_cash,initial_risk_budget,score);'''
    new_transition = '''      if(state==AP_STATE_HEALTHY_POSITION && runner.peak_r>=0.50)
        { APTransition(identifier,AP_STATE_PRE_BANK_PROFIT,score,ticket,StringFormat("peak_r=%.5f;monetary_trailing_enabled=false",runner.peak_r)); state=AP_STATE_PRE_BANK_PROFIT; }
      if(state==AP_STATE_PRE_BANK_PROFIT && current_r<0.0)
        { APTransition(identifier,AP_STATE_PRE_BANK_GIVEBACK,score,ticket,StringFormat(
             "current_r=%.5f;peak_r=%.5f;banked=false;original_structural_sl_retained=true",current_r,runner.peak_r));
          state=AP_STATE_PRE_BANK_GIVEBACK; }
      if(state==AP_STATE_PRE_BANK_GIVEBACK && current_r>=0.0)
        { APTransition(identifier,AP_STATE_PRE_BANK_PROFIT,score,ticket,StringFormat(
             "current_r=%.5f;peak_r=%.5f;recovered_profitable_state=true",current_r,runner.peak_r));
          state=AP_STATE_PRE_BANK_PROFIT; }

      bool banked=FPTryBank(ticket,identifier,symbol,bank_trigger_r,bank_trigger_cash,initial_risk_budget,score);'''
    manager = replace_once(manager, old_transition, new_transition)

    old_damage = '''      if(GlobalVariableCheck(FPBankIntentKey(identifier))) continue;

      if(state==AP_STATE_ENTRY_PROBATION && current_r<=-0.50 && runner.peak_r<0.15 && soft_bad_bars>=2)'''
    new_damage = '''      if(GlobalVariableCheck(FPBankIntentKey(identifier))) continue;

      if(state==AP_STATE_PRE_BANK_GIVEBACK && current_r<=-0.50 && pre_bank_causal_failure)
        {
         APCloseOwned(ticket,identifier,AP_EXIT_PRE_BANK_GIVEBACK_FAILED,"POSITION_CLOSE_PRE_BANK_GIVEBACK_FAILED",score,StringFormat(
            "classification=PRE_BANK_GIVEBACK_FAILED;current_r=%.5f;peak_r=%.5f;causal=opposing_structural_or_persisted_thesis_deterioration;structural_deterioration=%s;opposite_direction=%s;opposite_structure=%s;held=%.2f;opposite=%.2f;original_structural_sl_retained=true",
            current_r,runner.peak_r,BoolText(structural_deterioration),BoolText(scored && score.fresh && score.direction==-direction),
            BoolText(opposite_structure),held_score,opposite_score));
         continue;
        }
      if(state==AP_STATE_ENTRY_PROBATION && current_r<=-0.50 && runner.peak_r<0.15 && soft_bad_bars>=2)'''
    manager = replace_once(manager, old_damage, new_damage)
    manager = replace_once(manager, "      if(soft_bad_bars>=2)\n        {", "      if(soft_bad_bars>=2 && state!=AP_STATE_PRE_BANK_GIVEBACK)\n        {")
    source = source[:start] + manager + source[end:]

    source = source.replace("ADAPTIVE_PAYOFF_V1_BANK1R", "ADAPTIVE_PAYOFF_V1_BANK1R_GIVEBACK")
    OUT.write_text(source)

    changed = {"APStateName", "APExitName", "ManageFastPositions", "WriteRuntimeStatus", "OnInit", "OnTradeTransaction"}
    preserved = {}
    for name in re.findall(r"^(?:void|bool|int|long|ulong|double|string|datetime)\s+(\w+)\s*\(", original, re.M):
        if name in changed:
            continue
        try:
            a, b = function_span(original, name)
            c, d = function_span(source, name)
        except Exception:
            continue
        if original[a:b] != source[c:d]:
            raise AssertionError(f"unexpected changed function: {name}")
        preserved[name] = sha(source[c:d].encode())

    assert re.findall(r"^input .*?;", original, re.M) == re.findall(r"^input .*?;", source, re.M)
    manifest = {
        "schema": "FP_ADAPTIVE_PAYOFF_V1_BANK1R_GIVEBACK_RELEASE",
        "base_sha256": BASE_SHA,
        "source_sha256": sha(OUT.read_bytes()),
        "manager": "ADAPTIVE_PAYOFF_V1_BANK1R_GIVEBACK",
        "account": 7404213,
        "server": "FPMarketsSC-Demo",
        "risk_percent": 1.0,
        "aggregate_risk_percent": 1.5,
        "bank_at_r": 1.0,
        "bank_original_fraction": 0.5,
        "fxify_forbidden": [7196820, 7198096],
        "entry_policy_changed": False,
        "sizing_changed": False,
        "structural_stop_changed": False,
        "runner_structure_changed": False,
        "changed_existing_functions": sorted(changed),
        "preserved_functions": preserved,
    }
    (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({k: v for k, v in manifest.items() if k != "preserved_functions"}, indent=2))


if __name__ == "__main__":
    build()
