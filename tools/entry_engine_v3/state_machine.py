"""Orderless ENTRY_ENGINE_V3_TRANSITION_EXPECTANCY decision state machine."""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class State(str, Enum):
    NO_TRADE="NO_TRADE"
    OPPORTUNITY_DETECTED="OPPORTUNITY_DETECTED"
    WAIT_FOR_TRANSITION="WAIT_FOR_TRANSITION"
    ENTRY_TRIGGERED="ENTRY_TRIGGERED"
    OPPORTUNITY_ABANDONED="OPPORTUNITY_ABANDONED"


@dataclass(frozen=True)
class Estimate:
    direction: str
    expected_net_r: float
    full_loss_probability: float
    bank1_probability: float
    opposite_expected_net_r: float


@dataclass
class TransitionMachine:
    detected_utc: int
    expiry_utc: int
    min_expected_net_r: float
    max_full_loss_probability: float
    min_bank1_probability: float
    min_direction_margin: float
    state: State=State.NO_TRADE
    decision_utc: int|None=None
    direction: str|None=None
    reason: str=""

    def detect(self, now:int)->State:
        if self.state is not State.NO_TRADE: raise ValueError("opportunity already initialized")
        self.state=State.OPPORTUNITY_DETECTED
        self.state=State.WAIT_FOR_TRANSITION
        return self.state

    def observe(self,now:int,estimate:Estimate)->State:
        if self.state is not State.WAIT_FOR_TRANSITION:return self.state
        if now>self.expiry_utc:
            self.state=State.OPPORTUNITY_ABANDONED;self.decision_utc=now;self.reason="TRANSITION_EXPIRED";return self.state
        checks=(estimate.expected_net_r>=self.min_expected_net_r,
                estimate.full_loss_probability<=self.max_full_loss_probability,
                estimate.bank1_probability>=self.min_bank1_probability,
                estimate.expected_net_r-estimate.opposite_expected_net_r>=self.min_direction_margin)
        if all(checks):
            self.state=State.ENTRY_TRIGGERED;self.decision_utc=now;self.direction=estimate.direction;self.reason="POSITIVE_TRANSITION_EXPECTANCY"
        return self.state

    def expire(self,now:int)->State:
        if self.state is State.WAIT_FOR_TRANSITION and now>=self.expiry_utc:
            self.state=State.OPPORTUNITY_ABANDONED;self.decision_utc=now;self.reason="TRANSITION_EXPIRED"
        return self.state


ORDER_CAPABILITY=False
