#!/usr/bin/env python3
"""Build account-bound FXIFY ports from the verified corrected V2.202 source."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


APPROVED_SOURCE_SHA256 = "155cb0b9dcea6192c82584404eb36759e9baf0afbc71b699071d8bb387eee011"
APPROVED_PRESET_SHA256 = "ca4a715a61245ec4ef794f96f80c2a5ecf941b1411587f86af94f21902ac3643"
ALLOWED = {
    "fxify-10k": {
        "account": 7196820,
        "magic": 2108202610,
        "suffix": "F10",
        "instance": "vps-fxify-10k-prod",
    },
    "fxify-100k": {
        "account": 7198096,
        "magic": 2108202620,
        "suffix": "F100",
        "instance": "vps-fxify-100k-prod",
    },
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def replace_once(text: str, old: str, new: str) -> str:
    count = text.count(old)
    if count != 1:
        raise ValueError(f"expected one occurrence, found {count}: {old!r}")
    return text.replace(old, new, 1)


def build(source: Path, preset: Path, target: str, output: Path) -> dict[str, object]:
    if target not in ALLOWED:
        raise ValueError(f"unsupported target {target!r}")
    if sha256(source) != APPROVED_SOURCE_SHA256:
        raise ValueError("corrected V2.202 source hash does not match the verified release")
    if sha256(preset) != APPROVED_PRESET_SHA256:
        raise ValueError("V2.202 preset hash does not match the approved FP release")

    spec = ALLOWED[target]
    account = spec["account"]
    magic = spec["magic"]
    suffix = spec["suffix"]
    instance = spec["instance"]
    expert_name = f"SolTradeFastMultiMarketV202{suffix}"
    runtime_folder = f"SolTradeFastMultiMarketV2{suffix}"
    state_prefix = f"SFM2{suffix}"

    text = source.read_text(encoding="utf-8")
    text = replace_once(
        text,
        '#property description "Demo-only active intraday multi-market context, execution, and management engine"',
        f'#property description "FXIFY {account} corrected V2.202 isolated runtime port"',
    )
    text = replace_once(text, "input long   ApprovedDemoAccount=0;", f"input long   ApprovedDemoAccount={account};")
    text = replace_once(text, 'input string ApprovedDemoServer="FPMarketsSC-Demo";', 'input string ApprovedDemoServer="FXIFY-Server";')
    text = replace_once(text, "input long   FastMagic=2108202601;", f"input long   FastMagic={magic};")
    text = replace_once(text, "#define REQUIRED_DEMO_LOGIN 7404213", f"#define REQUIRED_DEMO_LOGIN {account}")
    text = replace_once(text, "#define FORBIDDEN_LIVE_LOGIN 7196820", "#define FORBIDDEN_LIVE_LOGIN 0")
    text = replace_once(text, "#define V1_MAGIC 2108202601", f"#define V1_MAGIC {magic}")
    text = text.replace("SolTradeFastMultiMarketV2\\", runtime_folder + "\\")
    for old in (
        "SFM2C_P", "SFM2_X", "SFM2_R_", "SFM2_MFE_", "SFM2_MAE_",
        "SFM2_EPOCH_", "SFM2_EXITPX_", "SFM2_SCRATCH_TRY_", "SFM2_SCRATCH_",
        "SFM2_INV_", "SFM2_HOLD_",
    ):
        text = text.replace(f'"{old}', f'"{state_prefix}{old[4:]}')
    text = text.replace('"SFM1_R_', f'"SFM1{suffix}_R_')

    # Global Algo Trading is the sole user activation switch.  Identity and
    # scanner checks may run while it is OFF, but entry fails closed immediately
    # before portfolio/order ownership and broker submission.
    text = replace_once(
        text,
        "if(!(bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||\n"
        "      !(bool)MQLInfoInteger(MQL_TRADE_ALLOWED)) { reason=\"TRADING_PERMISSION_OFF\"; return false; }",
        "if(!(bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) { reason=\"ACCOUNT_TRADING_PERMISSION_OFF\"; return false; }",
    )
    text = replace_once(
        text,
        "if(!candidate.eligible) { reason=\"NOT_ELIGIBLE\"; return false; }",
        "if(!candidate.eligible) { reason=\"NOT_ELIGIBLE\"; return false; }\n"
        "   if(!(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !(bool)MQLInfoInteger(MQL_TRADE_ALLOWED))\n"
        "     { reason=\"FINAL_MANUAL_ALGO_SWITCH_OFF\"; return false; }",
    )
    text = replace_once(text, "if(!CloseLegacySlowDemoPositions(reason))", "if(!DryRunOnly && !CloseLegacySlowDemoPositions(reason))")
    text = text.replace("version=2.202;isolated_fast_multi_expected=true", "version=2.202;fxify_isolated_port=true;final_manual_algo_gate=true")

    output.mkdir(parents=True, exist_ok=True)
    source_out = output / f"{expert_name}.mq5"
    source_out.write_text(text, encoding="utf-8")

    preset_text = preset.read_text(encoding="utf-8")
    replacements = {
        "ApprovedDemoAccount=7404213": f"ApprovedDemoAccount={account}",
        "ApprovedDemoServer=FPMarketsSC-Demo": "ApprovedDemoServer=FXIFY-Server",
        "FastMagic=2108202601": f"FastMagic={magic}",
        "OwnershipInstanceId=vps-fp-prod": f"OwnershipInstanceId={instance}",
        "OwnershipHost=fxut9756438": "OwnershipHost=__INJECTED_VPS_HOST__",
    }
    for old, new in replacements.items():
        preset_text = replace_once(preset_text, old, new)
    preset_text = replace_once(preset_text, "OwnershipClaimSecret=__INJECTED_ON_VPS__", "OwnershipClaimSecret=__INJECTED_ON_VPS__")
    preset_out = output / f"{expert_name}-FINAL-ALGO-OFF.set"
    preset_out.write_text(preset_text, encoding="utf-8")

    provenance = {
        "schema": "SOLTRADE_FXIFY_V202_CORRECTED_RUNTIME_PORT_V1",
        "target": target,
        "account": account,
        "server": "FXIFY-Server",
        "magic": magic,
        "runtime_folder": runtime_folder,
        "ownership_instance": instance,
        "strategy_version": "2.202",
        "min_reward_r": 1.15,
        "final_activation_gate": "GLOBAL_MT5_ALGO_TRADING_OFF",
        "approved_source_sha256": APPROVED_SOURCE_SHA256,
        "approved_preset_sha256": APPROVED_PRESET_SHA256,
        "generated_source_sha256": sha256(source_out),
        "generated_preset_sha256": sha256(preset_out),
        "strategy_changes": [
            "complete_admission_persistence", "first_adverse_tick_scratch_retired",
            "confirmed_profit_net_floor_positive", "bounded_opposite_thesis_lifetime",
        ],
        "portability_changes": [
            "account_and_server_guard", "account_unique_magic", "account_unique_file_common_namespace",
            "account_unique_terminal_global_prefix", "account_unique_ownership_lease",
            "scanner_allowed_while_global_algo_off", "entry_fails_closed_when_global_algo_off",
        ],
    }
    (output / f"{expert_name}-provenance.json").write_text(
        json.dumps(provenance, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return provenance


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--preset", type=Path, required=True)
    parser.add_argument("--target", choices=sorted(ALLOWED), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.preset, args.target, args.output), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
