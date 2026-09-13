#!/usr/bin/env python3
"""Build account-bound FXIFY ports of the deployed FP Bank1R giveback manager."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "research/adaptive-payoff-v1-bank1r-giveback-20260912/SolTradeFastMultiMarketV2.mq5"
PRESET = ROOT / "ops/forexvps/payload/fp-demo/SolTradeFastMultiMarketV2-FPMarkets-demo.set"
OUT = Path(__file__).resolve().parent / "release"
SOURCE_SHA = "4d1980812f3312728d8c8258c6b8b59d4c29013f3f3832128866fbcfcab3c63e"
PRESET_SHA = "ca4a715a61245ec4ef794f96f80c2a5ecf941b1411587f86af94f21902ac3643"
ACCOUNTS = {
    "fxify-10k": dict(account=7196820, suffix="F10", magic=2108202610, instance="vps-fxify-10k-prod"),
    "fxify-100k": dict(account=7198096, suffix="F100", magic=2108202620, instance="vps-fxify-100k-prod"),
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def once(text: str, old: str, new: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"expected one occurrence of {old!r}, found {count}")
    return text.replace(old, new, 1)


def build_one(name: str, spec: dict) -> dict:
    suffix, account, magic = spec["suffix"], spec["account"], spec["magic"]
    expert = f"SolTradeFastMultiMarketV202{suffix}"
    folder = f"SolTradeFastMultiMarketV2{suffix}"
    state = f"SFM2{suffix}"
    legacy = f"SFM1{suffix}"
    text = SOURCE.read_text(encoding="utf-8")
    text = once(text,
        '#property description "Demo-only active intraday multi-market context, execution, and management engine"',
        f'#property description "FXIFY {account} adaptive payoff Bank1R giveback manager"')
    text = once(text, "input long   ApprovedDemoAccount=0;", f"input long   ApprovedDemoAccount={account};")
    text = once(text, 'input string ApprovedDemoServer="FPMarketsSC-Demo";', 'input string ApprovedDemoServer="FXIFY-Server";')
    text = once(text, "input long   FastMagic=2108202601;", f"input long   FastMagic={magic};")
    text = text.replace("7404213", str(account))
    text = once(text, "#define FORBIDDEN_LIVE_LOGIN 7196820", "#define FORBIDDEN_LIVE_LOGIN 0")
    text = once(text, "#define V1_MAGIC 2108202601", f"#define V1_MAGIC {magic}")
    text = text.replace("SolTradeFastMultiMarketV2\\\\", folder + "\\\\")
    text = text.replace('"SFM2', f'"{state}')
    text = text.replace('"SFM1', f'"{legacy}')
    text = text.replace("ADAPTIVE_PAYOFF_V1_BANK1R_GIVEBACK: FP", "ADAPTIVE_PAYOFF_V1_BANK1R_GIVEBACK: FXIFY")

    directory = OUT / name
    directory.mkdir(parents=True, exist_ok=True)
    src = directory / f"{expert}.mq5"
    src.write_text(text, encoding="utf-8")

    preset = PRESET.read_text(encoding="utf-8")
    changes = {
        "ApprovedDemoAccount=7404213": f"ApprovedDemoAccount={account}",
        "ApprovedDemoServer=FPMarketsSC-Demo": "ApprovedDemoServer=FXIFY-Server",
        "FastMagic=2108202601": f"FastMagic={magic}",
        "RiskPerTradePercent=0.25": "RiskPerTradePercent=1.00",
        "OwnershipInstanceId=vps-fp-prod": f"OwnershipInstanceId={spec['instance']}",
        "OwnershipHost=fxut9756438": "OwnershipHost=__PRESERVE_INSTALLED_HOST__",
    }
    for old, new in changes.items():
        preset = once(preset, old, new)
    setfile = directory / f"{expert}-FINAL-ACTIVE.set"
    setfile.write_text(preset, encoding="utf-8")
    return {
        "target": name, "account": account, "server": "FXIFY-Server", "magic": magic,
        "expert": expert, "runtime_folder": folder, "state_prefix": state,
        "ownership_instance": spec["instance"], "source_sha256": sha(src),
        "preset_sha256": sha(setfile), "source": str(src.relative_to(ROOT)),
        "preset": str(setfile.relative_to(ROOT)),
    }


def main() -> None:
    if sha(SOURCE) != SOURCE_SHA or sha(PRESET) != PRESET_SHA:
        raise SystemExit("approved FP source or preset hash mismatch")
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema": "SOLTRADE_FXIFY_BANK1R_GIVEBACK_PORT_V1",
        "manager": "ADAPTIVE_PAYOFF_V1_BANK1R_GIVEBACK",
        "base_source_sha256": SOURCE_SHA,
        "base_preset_sha256": PRESET_SHA,
        "risk_percent": 1.0, "aggregate_risk_percent": 1.5,
        "bank_at_r": 1.0, "bank_fraction": 0.5,
        "entry_logic_changed": False, "management_logic_changed": False,
        "sizing_logic_changed": False, "thresholds_changed": False,
        "ports": [build_one(name, spec) for name, spec in ACCOUNTS.items()],
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
