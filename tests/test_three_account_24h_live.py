import csv
import gzip
import hashlib
import json
import unittest
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "reports/fast-multi-market-v2/three-account-replay-completion-20261001"
PRIOR = ROOT / "reports/fast-multi-market-v2/three-account-replay-20261001"


class TwentyFourHourLiveEvidenceTests(unittest.TestCase):
    def test_all_24h_tick_files_match_original_export_and_extend_after_actual_exit(self):
        manifest = json.loads((BASE / "fp-24h-tick-manifest.json").read_text())
        self.assertEqual(len(manifest["files"]), 29)
        self.assertEqual(manifest["total_ticks"], 2903063)
        with (PRIOR / "fp-broker-position-ledger.csv").open(newline="") as stream:
            positions = {r["position_id"]: r for r in csv.DictReader(stream)}
        for record in manifest["files"]:
            path = ROOT / record["path"]
            sha = hashlib.sha256()
            last_msc = None
            with gzip.open(path, "rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    sha.update(block)
            self.assertEqual(sha.hexdigest(), record["source_sha256"])
            with gzip.open(path, "rt") as stream:
                for row in csv.DictReader(stream):
                    last_msc = int(row["time_msc"])
            position = record["case_id"].removeprefix("fp24-")
            actual_exit_msc = int(datetime.fromisoformat(positions[position]["exit_utc"]).timestamp() * 1000) + 10800000
            self.assertGreater(last_msc, actual_exit_msc, position)

    def test_loss_table_keeps_opposite_final_cash_unknown(self):
        with (BASE / "fp-24h-opposite-paths.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        losses = [r for r in rows if r["actual_exit_class"] == "INITIAL_STRUCTURAL_STOP_EXIT"]
        self.assertEqual(len(rows), 29)
        self.assertEqual(len(losses), 14)
        self.assertEqual(sum(r["opposite_mirrored_status"] == "PLUS_1R_QUOTE_BOUNDARY" for r in losses), 13)
        self.assertTrue(all(r["opposite_final_cash"] == "" and r["opposite_final_r"] == "" for r in rows))


if __name__ == "__main__":
    unittest.main()
