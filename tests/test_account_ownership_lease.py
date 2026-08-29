#!/usr/bin/env python3
"""Deterministic contract tests for the FP 7404213 single-writer lease."""

import unittest
from dataclasses import dataclass


@dataclass(frozen=True)
class Claim:
    account: int
    instance_id: str
    host: str
    runtime_id: str
    secret: str
    heartbeat: int


class LeaseAuthority:
    def __init__(self, *, secret="v" * 48, ttl=15):
        self.secret = secret
        self.ttl = ttl
        self.lease = None
        self.audit = []

    def authorized(self, claim, now):
        return (
            claim.account == 7404213
            and claim.instance_id == "vps-fp-prod"
            and claim.host == "fxut9756438"
            and claim.secret == self.secret
            and -5 <= now - claim.heartbeat <= self.ttl
        )

    def cycle(self, claims, now):
        valid = sorted(
            (claim for claim in claims if self.authorized(claim, now)),
            key=lambda claim: (claim.heartbeat, claim.runtime_id),
        )
        owner_claim = next(
            (claim for claim in valid if self.lease and claim.runtime_id == self.lease["runtime_id"]),
            None,
        )
        if self.lease and self.lease["expires"] <= now:
            self.audit.append(("STALE_LEASE_EXPIRED", self.lease["runtime_id"], now))
            self.lease = None
        if self.lease and owner_claim:
            self.lease["renewed"] = now
            self.lease["expires"] = now + self.ttl
        if not self.lease and valid:
            winner = valid[0]
            self.lease = {
                "runtime_id": winner.runtime_id,
                "acquired": now,
                "renewed": now,
                "expires": now + self.ttl,
            }
            self.audit.append(("ACQUIRED", winner.runtime_id, now))
        return {
            claim.runtime_id: (
                "GRANTED" if self.lease and claim.runtime_id == self.lease["runtime_id"] else "DENIED"
            )
            for claim in claims
        }

    def release(self, runtime_id, now):
        if self.lease and self.lease["runtime_id"] == runtime_id:
            self.audit.append(("RELEASED", runtime_id, now))
            self.lease = None


class AccountOwnershipLeaseTests(unittest.TestCase):
    def setUp(self):
        self.authority = LeaseAuthority()
        self.vps = Claim(7404213, "vps-fp-prod", "fxut9756438", "vps-a", "v" * 48, 100)
        self.laptop = Claim(7404213, "laptop-development-blocked", "LAPTOP-DEVELOPMENT", "laptop-a", "", 100)

    def test_vps_owner_blocks_laptop_and_watchdog_restart(self):
        permits = self.authority.cycle([self.vps, self.laptop], 100)
        self.assertEqual("GRANTED", permits["vps-a"])
        self.assertEqual("DENIED", permits["laptop-a"])
        laptop_restart = Claim(**{**self.laptop.__dict__, "runtime_id": "laptop-watchdog-b", "heartbeat": 101})
        permits = self.authority.cycle([self.vps, laptop_restart], 101)
        self.assertEqual("GRANTED", permits["vps-a"])
        self.assertEqual("DENIED", permits["laptop-watchdog-b"])

    def test_vps_clean_restart_releases_and_reacquires(self):
        self.authority.cycle([self.vps], 100)
        self.authority.release("vps-a", 101)
        restarted = Claim(**{**self.vps.__dict__, "runtime_id": "vps-b", "heartbeat": 102})
        permits = self.authority.cycle([restarted], 102)
        self.assertEqual("GRANTED", permits["vps-b"])

    def test_crash_fails_closed_then_recovers_at_bounded_expiry(self):
        self.authority.cycle([self.vps], 100)
        contender = Claim(**{**self.vps.__dict__, "runtime_id": "vps-b", "heartbeat": 101})
        self.assertEqual("DENIED", self.authority.cycle([contender], 101)["vps-b"])
        contender = Claim(**{**contender.__dict__, "heartbeat": 115})
        self.assertEqual("GRANTED", self.authority.cycle([contender], 115)["vps-b"])
        self.assertIn(("STALE_LEASE_EXPIRED", "vps-a", 115), self.authority.audit)

    def test_stale_claim_and_wrong_secret_are_denied(self):
        stale = Claim(**{**self.vps.__dict__, "runtime_id": "stale", "heartbeat": 80})
        wrong = Claim(**{**self.vps.__dict__, "runtime_id": "wrong", "secret": "x" * 48})
        permits = self.authority.cycle([stale, wrong], 100)
        self.assertEqual({"stale": "DENIED", "wrong": "DENIED"}, permits)
        self.assertIsNone(self.authority.lease)

    def test_simultaneous_startup_has_exactly_one_winner(self):
        first = Claim(**{**self.vps.__dict__, "runtime_id": "vps-b"})
        second = Claim(**{**self.vps.__dict__, "runtime_id": "vps-a"})
        permits = self.authority.cycle([first, second], 100)
        self.assertEqual(1, list(permits.values()).count("GRANTED"))
        self.assertEqual("vps-a", self.authority.lease["runtime_id"])


if __name__ == "__main__":
    unittest.main()
