"""Reference semantics for the orderless full-lifetime tracker."""
from __future__ import annotations

from dataclasses import dataclass, field


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
        resumption: bool = False,
        structural_alignment: float = 0.0,
        expanding_pullback: bool = False,
    ) -> None:
        self.mfe_r = max(self.mfe_r, current_r)
        self.mae_r = min(self.mae_r, current_r)
        if not self.bank1_reached and current_r >= 1.0:
            self.bank1_reached = True
            self.bank_count += 1
        if current_r <= -1.0:
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
            if path.invalidated:
                path.continued_to_minus_1 |= current_r <= -1.0
                path.recovered_to_breakeven |= current_r >= 0.0
                path.reached_bank1 |= current_r >= 1.0
                path.reached_plus_2 |= current_r >= 2.0
                path.reached_plus_3 |= current_r >= 3.0
                path.reached_plus_5 |= current_r >= 5.0

    def baseline_final_r(self, terminal_r: float) -> float:
        if self.structural_stop_reached:
            return 0.0 if self.bank1_reached else -1.0
        return 0.5 + 0.5 * terminal_r if self.bank1_reached else terminal_r

    def causal_final_r(self, candidate_id: str, terminal_r: float) -> float:
        path = self.paths[candidate_id]
        if not path.invalidated:
            return self.baseline_final_r(terminal_r)
        assert path.exit_r is not None
        return 0.5 + 0.5 * path.exit_r if self.bank1_reached else path.exit_r


ORDER_CAPABILITY = False
