#!/usr/bin/env python3
"""Build account-bound, state-isolated FXIFY runtime ports from frozen V2.201.

The generator refuses any source other than the historically approved V2.201
artifact.  Its substitutions are infrastructure-only: account/server guard,
magic namespace, durable-state namespace, filename/description, and the
migration dry-run safeguard around legacy-position cleanup.  Strategy inputs
and decision/management code remain unchanged.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


APPROVED_SOURCE_SHA256 = "c2530ad8e3429c05d4d03e5643f609786ada0bc4a8ecdd4f8216ab9cc00abc61"
APPROVED_PRESET_SHA256 = "b6411be64672842e6c126dd310c2fb3f4941067f39f5716b8a2dfdac8f918c45"
ALLOWED = {
    "fxify-10k": {"account": 7196820, "magic": 2108202610, "suffix": "F10"},
    "fxify-100k": {"account": 7198096, "magic": 2108202620, "suffix": "F100"},
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
        raise ValueError("V2.201 source hash does not match the approved release")
    if sha256(preset) != APPROVED_PRESET_SHA256:
        raise ValueError("V2.201 preset hash does not match the approved release")

    account = ALLOWED[target]["account"]
    magic = ALLOWED[target]["magic"]
    suffix = ALLOWED[target]["suffix"]
    runtime_folder = f"SolTradeFastMultiMarketV2{suffix}"
    expert_name = f"SolTradeFastMultiMarketV201{suffix}"
    state_prefix = f"SFM2{suffix}_"

    text = source.read_text(encoding="utf-8")
    text = replace_once(
        text,
        '#property description "Demo-only active intraday multi-market context, execution, and management engine"',
        f'#property description "FXIFY {account} V2.201 strategy-preserving isolated runtime port"',
    )
    text = replace_once(text, "input long   ApprovedDemoAccount=0;", f"input long   ApprovedDemoAccount={account};")
    text = replace_once(text, 'input string ApprovedDemoServer="FPMarketsSC-Demo";', 'input string ApprovedDemoServer="FXIFY-Server";')
    text = replace_once(text, "input long   FastMagic=2108202601;", f"input long   FastMagic={magic};")
    text = replace_once(text, "#define REQUIRED_DEMO_LOGIN 7404213", f"#define REQUIRED_DEMO_LOGIN {account}")
    text = replace_once(text, "#define FORBIDDEN_LIVE_LOGIN 7196820", "#define FORBIDDEN_LIVE_LOGIN 0")
    text = replace_once(text, "#define V1_MAGIC 2108202601", f"#define V1_MAGIC {magic}")
    text = text.replace("SolTradeFastMultiMarketV2\\\\", runtime_folder + "\\\\")
    text = text.replace('"SFM2_', f'"{state_prefix}')
    text = text.replace('"SFM1_R_', f'"SFM1{suffix}_R_')
    text = replace_once(
        text,
        "if(!CloseLegacySlowDemoPositions(reason))",
        "if(!DryRunOnly && !CloseLegacySlowDemoPositions(reason))",
    )

    forbidden_fragments = [
        "SolTradeFastMultiMarketV2\\\\",
        '"SFM2_',
        '"SFM1_R_',
        "#define REQUIRED_DEMO_LOGIN 7404213",
        "#define V1_MAGIC 2108202601",
    ]
    remaining = [fragment for fragment in forbidden_fragments if fragment in text]
    if remaining:
        raise ValueError(f"portability substitutions incomplete: {remaining}")

    output.mkdir(parents=True, exist_ok=True)
    source_out = output / f"{expert_name}.mq5"
    source_out.write_text(text, encoding="utf-8")

    preset_text = preset.read_text(encoding="utf-8")
    preset_text = replace_once(preset_text, "DryRunOnly=false", "DryRunOnly=true")
    preset_text = replace_once(preset_text, "ApprovedDemoAccount=7404213", f"ApprovedDemoAccount={account}")
    preset_text = replace_once(preset_text, "ApprovedDemoServer=FPMarketsSC-Demo", "ApprovedDemoServer=FXIFY-Server")
    preset_text = replace_once(preset_text, "FastMagic=2108202601", f"FastMagic={magic}")
    preset_out = output / f"{expert_name}-ORDER-DISABLED.set"
    preset_out.write_text(preset_text, encoding="utf-8")

    provenance = {
        "schema": "SOLTRADE_FXIFY_V201_RUNTIME_PORT_V1",
        "target": target,
        "account": account,
        "server": "FXIFY-Server",
        "magic": magic,
        "runtime_folder": runtime_folder,
        "order_permission": "DISABLED_DRY_RUN",
        "strategy_version": "2.201",
        "min_reward_r": 1.20,
        "approved_source_sha256": APPROVED_SOURCE_SHA256,
        "approved_preset_sha256": APPROVED_PRESET_SHA256,
        "generated_source_sha256": sha256(source_out),
        "generated_preset_sha256": sha256(preset_out),
        "portability_changes": [
            "account_and_server_guard",
            "account_unique_magic",
            "account_unique_file_common_namespace",
            "account_unique_terminal_global_prefix",
            "legacy_cleanup_suppressed_while_dry_run",
            "order_permission_forced_off_by_deployment_preset",
        ],
        "strategy_changes": [],
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
