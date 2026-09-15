import unittest

from tools.audit_fp_m1_forward_gate import decode_behaviour


class FPForwardGateAuditTests(unittest.TestCase):
    def test_setup_key_behaviour_decoding_preserves_int32_overflow(self):
        self.assertEqual(decode_behaviour(294_965_307, -1), "STRUCTURE_INSIDE")
        self.assertEqual(decode_behaviour(-1_200_003_421, -1), "BREAKOUT_DOWN")
        self.assertEqual(decode_behaviour(-294_962_964, 1), "STRUCTURE_INSIDE")


if __name__ == "__main__":
    unittest.main()
