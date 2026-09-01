#!/usr/bin/env bash
set -euo pipefail

source_file='MQL5/Experts/SolTradeFastMultiMarketV2.mq5'
authority='ops/forexvps/Run-AccountOwnershipAuthority.ps1'
laptop_set='config/mt5/SolTradeFastMultiMarketV2-FPMarkets-demo.set'
vps_set='ops/forexvps/payload/fp-demo/SolTradeFastMultiMarketV2-FPMarkets-demo.set'

for pattern in \
  'OwnershipLeaseRequired=true' \
  'OwnershipEligible=false' \
  'VerifyOrderOwnership' \
  'PERMIT_RUNTIME_MISMATCH' \
  'PERMIT_EXPIRED' \
  'PERMIT_RENEWAL_STALE' \
  'ACCOUNT_OWNERSHIP_' \
  'OwnershipLeaseTtlSeconds<10' \
  'OwnershipLeaseTtlSeconds>60'; do
  rg -q "$pattern" "$source_file"
done

[[ $(rg -c 'g_trade\.(Buy|Sell|PositionModify|PositionClose)' "$source_file") -eq 8 ]]
[[ $(rg -c 'VerifyOrderOwnership\(' "$source_file") -eq 8 ]]

rg -q '^OwnershipEligible=false$' "$laptop_set"
rg -q '^OwnershipClaimSecret=$' "$laptop_set"
rg -q '^OwnershipEligible=true$' "$vps_set"
rg -q '^OwnershipInstanceId=vps-fp-prod$' "$vps_set"
rg -q '^OwnershipClaimSecret=__INJECTED_ON_VPS__$' "$vps_set"

for pattern in \
  'Global\\SolTradeOwnership-\$Account' \
  "'STALE_LEASE_EXPIRED'" \
  "'ACQUIRED'" \
  "'RENEWED'" \
  "'RELEASED'" \
  "'DENIED'" \
  'race_candidates' \
  'claim_secret -cne \$expectedSecret'; do
  rg -q "$pattern" "$authority"
done

rg -q 'for \(\$attempt = 0; \$attempt -lt 12; \$attempt\+\+\)' "$authority"
rg -q 'catch \[IO.IOException\]' "$authority"
rg -q 'for\(int attempt=0;attempt<8;attempt\+\+\)' "$source_file"
rg -q 'FILE_SHARE_READ|FILE_SHARE_WRITE' "$source_file"

if rg -q 'OwnershipEligible=true|OwnershipClaimSecret=[^[:space:]]' "$laptop_set"; then
  echo 'laptop preset can obtain production ownership' >&2
  exit 1
fi

echo 'account ownership static safety checks passed'
