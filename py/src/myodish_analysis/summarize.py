"""One summary row (mean and SD of the included contractions) for one channel and time range. Port of mda_summarize.m.

    T = summarize(B, C, range_)

B       contraction table of one channel (analyze_channel); only rows with included = True and a peak within range
        are averaged
C       channel info from analyze_channel (stimulus times, threshold)
range_  [from, to] in s

Columns: channel, from, to, nContractions (included), nDetected, nStimulated, nExtraBeats, nStimuli, nMissedBeats,
extraBeats_percent, missedBeats_percent, stimFrequency (Hz, from the median stimulus interval in the range),
detectionThreshold (uN), zeroForce (uN), then <parameter>_mean, <parameter>_SD and <parameter>_n for every parameter;
with a reference beat <parameter>_pctRef / _dRef _mean / _SD; with AP columns (analyze_ap) _mean / _SD / _n.

TS 2026-10-06 (port of mda_summarize.m, TS 2026-10-04)
"""
from __future__ import annotations

import math

import numpy as np
import pandas as pd

from ._matlab import nanmean, nanstd
from .parameters import PARAMETERS


def summarize(B, C, range_):
    from .analyze_ap import AP_PARAMETERS
    params = [p[0] for p in PARAMETERS]
    tp = B["t_peak"].to_numpy(dtype=float)
    inRange = (tp >= range_[0]) & (tp <= range_[1])
    I = inRange & B["included"].to_numpy(dtype=bool)
    ST = np.asarray(C.stimTimes, dtype=float)
    J = (ST >= range_[0]) & (ST <= range_[1])
    fStim = math.nan
    if np.sum(J) > 1:
        fStim = 1 / float(np.median(np.diff(ST[J])))
    zeroF = C.get("zeroForce", math.nan)
    bt = B["beatType"].to_numpy()
    row = dict(channel=C.channel, **{"from": range_[0]}, to=range_[1], nContractions=int(np.sum(I)),
               nDetected=int(np.sum(inRange)), nStimulated=int(np.sum(inRange & (bt == "stimulated"))),
               nExtraBeats=int(np.sum(inRange & (bt == "extra"))), nStimuli=int(np.sum(J)),
               nMissedBeats=int(np.sum(J & ~np.asarray(C.stimCaptured, bool))))
    row["extraBeats_percent"] = 100 * row["nExtraBeats"] / row["nDetected"] if row["nDetected"] > 0 else math.nan
    row["missedBeats_percent"] = 100 * row["nMissedBeats"] / row["nStimuli"] if row["nStimuli"] > 0 else math.nan
    row["stimFrequency"] = fStim
    row["detectionThreshold"] = C.threshold
    row["zeroForce"] = zeroF
    for p in params:
        v = B[p].to_numpy(dtype=float)[I]
        row[p + "_mean"] = nanmean(v)
        row[p + "_SD"] = nanstd(v)
        row[p + "_n"] = int(np.sum(~np.isnan(v)))
    rel = [c for c in B.columns if c.endswith("_pctRef") or c.endswith("_dRef")]
    for c in rel:
        v = B[c].to_numpy(dtype=float)[I]
        row[c + "_mean"] = nanmean(v)
        row[c + "_SD"] = nanstd(v)
    for p in AP_PARAMETERS:
        if p[0] not in B.columns:
            continue
        v = B[p[0]].to_numpy(dtype=float)[I]
        row[p[0] + "_mean"] = nanmean(v)
        row[p[0] + "_SD"] = nanstd(v)
        row[p[0] + "_n"] = int(np.sum(~np.isnan(v)))
    return pd.DataFrame([row])
