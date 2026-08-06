# V3.1 no-retry decision

V3.1 retains entry at the first tradable real tick, exactly one eligibility check, and exactly one submission opportunity.

The V20 five-minute diagnostic is not an entry rule. A delayed attempt would change entry price and market state; 39 of 61 V20 spread blocks never resolved during the same H1 candle; and selecting a window after reviewing those counts would be retrospective rule selection.

If the first tick fails the V3.1 spread rule, the setup is cancelled. There is no waiting, delayed entry, or controlled/uncontrolled retry.
