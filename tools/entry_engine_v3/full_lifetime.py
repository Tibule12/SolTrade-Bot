"""Reference semantics for the orderless full-lifetime tracker."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class InvalidationCandidate:
    candidate_id: str
    adverse_r_lte: float
    transition_score_lte: float
    require_no_resumption: bool = False
    require_structural_reversal: bool = False
    require_expanding_pullback: bool = False

    def triggers(
        self,
        current_r: float,
        transition_score: float,
        *,
        resumption: bool,
        structural_alignment: float,
        expanding_pullback: bool,
    ) -> bool:
        if current_r > self.adverse_r_lte or transition_score > self.transition_score_lte:
            return False
        if self.require_no_resumption and resumption:
            return False
        if self.require_structural_reversal and structural_alignment > -1.0:
            return False
        if self.require_expanding_pullback and not expanding_pullback:
            return False
        return True


FROZEN_CANDIDATES = (
    InvalidationCandidate("FROZEN_V3_DIAGNOSTIC", -0.40, -0.25),
    InvalidationCandidate("STRICT_PRESSURE_RESUMPTION", -0.50, -0.35, require_no_resumption=True),
    InvalidationCandidate("STRUCTURAL_REVERSAL_CONFIRMATION", -0.40, -0.25, require_structural_reversal=True),
    InvalidationCandidate(
        "EXPANDING_PULLBACK_FAILURE",
        -0.35,
        -0.30,
        require_no_resumption=True,
        require_expanding_pullback=True,
    ),
)


@dataclass
class CandidatePath:
    invalidated: bool = False
    exit_r: float | None = None
    banked_before_exit: bool = False
    continued_to_minus_1: bool = False
    recovered_to_breakeven: bool = False
    reached_bank1: bool = False
    reached_plus_2: bool = False
    reached_plus_3: bool = False
    reached_plus_5: bool = False


@dataclass
class LifetimePosition:
    candidates: tuple[InvalidationCandidate, ...] = FROZEN_CANDIDATES
    bank1_reached: bool = False
    bank_count: int = 0
    structural_stop_reached: bool = False
    active: bool = True
    entry_utc: int = 0
    terminal_utc: int | None = None
    terminal_reason: str | None = None
    outcome_status: str = "OPEN"
    runner_stop_r: float = -1.0
    runner_trail_updates: int = 0
    mfe_r: float = 0.0
    mae_r: float = 0.0
    paths: dict[str, CandidatePath] = field(default_factory=dict)

    def __post_init__(self) -> None:
        self.paths = {candidate.candidate_id: CandidatePath() for candidate in self.candidates}

    def observe(
        self,
        current_r: float,
        transition_score: float,
        *,
        now: int | None = None,
        fresh_quote: bool = True,
        resumption: bool = False,
        structural_alignment: float = 0.0,
        expanding_pullback: bool = False,
    ) -> None:
        if not self.active or not fresh_quote:
            return
        self.mfe_r = max(self.mfe_r, current_r)
        self.mae_r = min(self.mae_r, current_r)
        if not self.bank1_reached and current_r >= 1.0:
            self.bank1_reached = True
            self.bank_count += 1
        active_stop_r = self.runner_stop_r if self.bank1_reached else -1.0
        if current_r <= active_stop_r:
            self.structural_stop_reached = True
        for candidate in self.candidates:
            path = self.paths[candidate.candidate_id]
            if not path.invalidated and candidate.triggers(
                current_r,
                transition_score,
                resumption=resumption,
                structural_alignment=structural_alignment,
                expanding_pullback=expanding_pullback,
            ):
                path.invalidated = True
                path.exit_r = current_r
                path.banked_before_exit = self.bank1_reached
            if path.invalidated:
                path.continued_to_minus_1 |= current_r <= -1.0
                path.recovered_to_breakeven |= current_r >= 0.0
                path.reached_bank1 |= current_r >= 1.0
                path.reached_plus_2 |= current_r >= 2.0
                path.reached_plus_3 |= current_r >= 3.0
                path.reached_plus_5 |= current_r >= 5.0
        if self.structural_stop_reached:
            self.active = False
            self.terminal_utc = now
            self.terminal_reason = "RUNNER_STRUCTURAL_STOP" if self.bank1_reached else "INITIAL_STRUCTURAL_STOP"
            self.outcome_status = "TERMINAL"

    def advance_runner_stop(self, proposed_stop_r: float) -> None:
        """Mirror the frozen manager: only a banked runner gets a tighter profitable stop."""
        if self.active and self.bank1_reached and proposed_stop_r > 0.0 and proposed_stop_r > self.runner_stop_r:
            self.runner_stop_r = proposed_stop_r
            self.runner_trail_updates += 1

    def evaluate_research_cutoff(self, now: int, safety_horizon_seconds: int, *, fresh_quote: bool) -> None:
        """A disabled horizon is unlimited; an enabled horizon censors only on a fresh market."""
        if not self.active or safety_horizon_seconds <= 0 or not fresh_quote:
            return
        if now - self.entry_utc >= safety_horizon_seconds:
            self.active = False
            self.terminal_utc = now
            self.terminal_reason = "RESEARCH_SAFETY_HORIZON"
            self.outcome_status = "RIGHT_CENSORED"

    def baseline_final_r(self, terminal_r: float) -> float | None:
        if self.outcome_status == "RIGHT_CENSORED":
            return None
        if not self.structural_stop_reached:
            return None
        return 0.5 + 0.5 * terminal_r if self.bank1_reached else terminal_r

    def causal_final_r(self, candidate_id: str, terminal_r: float) -> float | None:
        path = self.paths[candidate_id]
        if not path.invalidated:
            return self.baseline_final_r(terminal_r)
        assert path.exit_r is not None
        return 0.5 + 0.5 * path.exit_r if path.banked_before_exit else path.exit_r

    def to_state(self) -> dict[str, Any]:
        return {
            "active": self.active,
            "entry_utc": self.entry_utc,
            "terminal_utc": self.terminal_utc,
            "terminal_reason": self.terminal_reason,
            "outcome_status": self.outcome_status,
            "bank1_reached": self.bank1_reached,
            "bank_count": self.bank_count,
            "structural_stop_reached": self.structural_stop_reached,
            "runner_stop_r": self.runner_stop_r,
            "runner_trail_updates": self.runner_trail_updates,
            "mfe_r": self.mfe_r,
            "mae_r": self.mae_r,
            "paths": {key: vars(value).copy() for key, value in self.paths.items()},
        }

    @classmethod
    def from_state(cls, state: dict[str, Any]) -> "LifetimePosition":
        position = cls(entry_utc=int(state["entry_utc"]))
        for key in (
            "active", "terminal_utc", "terminal_reason", "outcome_status", "bank1_reached",
            "bank_count", "structural_stop_reached", "runner_stop_r", "runner_trail_updates",
            "mfe_r", "mae_r",
        ):
            setattr(position, key, state[key])
        position.paths = {key: CandidatePath(**value) for key, value in state["paths"].items()}
        return position


ORDER_CAPABILITY = False
