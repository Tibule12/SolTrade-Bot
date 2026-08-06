# Production Approval Checklist

This checklist is a future gate, not evidence that Phase 4 is production-ready
or approved for real-account execution.

## Technical

- [ ] Zero compilation errors and warnings.
- [ ] All calculation, mode, restart, and signal fixtures pass.
- [ ] No unhandled broker result codes.
- [ ] Every position receives and retains its required stop.
- [ ] Daily, weekly, consecutive-loss, and emergency locks are verified.
- [ ] Restart recovery and duplicate prevention are verified.
- [ ] Manual/unrelated positions remain unmanaged.
- [ ] Default-deny live gating is independently verified.

## Research

- [ ] Positive untouched out-of-sample expectancy.
- [ ] Positive forward-demo expectancy.
- [ ] Profit factor above 1.15 after realistic costs.
- [ ] Maximum drawdown below 8%.
- [ ] Stress costs remain acceptable.
- [ ] Small sensible parameter changes do not destroy results.
- [ ] Results do not depend on one short period or a few trades.
- [ ] At least eight weeks and normally 50 forward-demo trades are complete.

The binding numeric Phase 6 rules, including High/Stress thresholds,
20%/40% concentration limits, cross-dataset variation, and the 50-closed-trade
OOS minimum, are defined in `docs/phase6-backtesting.md`. “Stress costs remain
acceptable” is not an independent subjective override.

## Deployment

- [ ] Exact source commit and compiled artifact are recorded.
- [ ] Broker/account type/base currency/leverage match the validated setup.
- [ ] Production baseline equity is explicitly configured and approved.
- [ ] Live account number, strategy version, and risk profile are approved.
- [ ] A future phase explicitly removes the Phase 4 real-account prohibition
      only after every approval gate passes.
- [ ] `AllowLiveTrading` is enabled only in that separately approved build and
      only for the approved micro account.
- [ ] VPS, terminal restart, connectivity, logging, and alert procedures pass.
- [ ] No borrowed or essential funds are used.
- [ ] A rollback/emergency response owner and review date are documented.

Any unchecked item is a no-go. A profitable backtest alone cannot approve live
trading.
