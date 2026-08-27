# V2.200 structure probe status

Date: 2026-08-27

- Source: `MQL5/Experts/SolTradeFastMultiMarketV220StructureProbe.mq5`
- Compile result: `0 errors, 0 warnings`, X64 Regular
- Order capability: none in source; the intended shadow terminal configuration also sets `AllowLiveTrading=0`
- Account guard: `7404213 / FPMarketsSC-Demo`, demo mode only
- Runtime result: not activated

The probe was compiled in an isolated Wine prefix. MT5 deleted the copied account
cache `due security reason`, so the isolated terminal could not authenticate.
No credentials were requested, copied, logged, or exposed. The temporary prefix
was stopped and removed, and the production terminal was never restarted.

Consequently, selected-swing direction and reward/cost arithmetic are reviewed
from the production source, but exact selected timeframe, swing creation time,
and broker-dollar values remain explicitly unobserved in the V5 feed. The
continuous CSV shadow collector does not fabricate those fields.
