# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""One summary row (mean and SD of the included contractions) for one channel and time range. Port of mda_summarize.m.

    T = summarize(B, C, range_, opts=None, exclude=None)

B       contraction table of one channel (analyze_channel); only rows with included = True and a peak within range
        are averaged
C       channel info from analyze_channel (stimulus times, threshold)
range_  [from, to] in s; several ranges (n x 2, 2026-10-14): one row over all of them (union; from / to = first start /
        last end, stimFrequency from the intervals within the ranges)
opts    options (arrhythmicWindow, arrhythmicMinVariability; None = defaults)
exclude [from to] rows of the stimulation protocols (stim-to-stim variability: windows overlapping them are skipped)

Columns: channel, from, to, nContractions (included), nDetected, nStimulated, nExtraBeats, nStimuli, nMissedBeats,
extraBeats_percent, missedBeats_percent, nUncertain, nStimulatedUncertain, nExtraBeatsUncertain,
nMissedBeatsUncertain (uncertain contractions, see analyze_channel, option detection; missed: stimuli followed only by
an uncertain contraction), nMissedDuringContraction (missed: the regular pulse fell into a contraction elicited by
another pulse), nExtraPulses (status channel bit 16), nElicitedByExtraPulse, nAmbiguous (stimAmbiguous), stimFrequency
(Hz, from the median stimulus interval in the range), stimVariability_percent (median CV of the stimulus intervals in
windows of arrhythmicWindow, %), arrhythmicFraction (fraction of the paced time in windows whose CV exceeds
arrhythmicMinVariability), pacedSeconds (paced time of these windows: >= 5 intervals, no overlap with exclude =
[from to] of the stimulation protocols; 2026-10-13; analysis adds arrhythmicPacing), detectionThreshold (uN), zeroForce
(uN), sensorRate_inferred (Hz) and repeatedSamples_percent (sensor rate of the channel inferred from repeated raw values
in the window read, see read_mdd; 2026-10-21), then <parameter>_mean,
<parameter>_SD and <parameter>_n for every parameter; amplitude_CV after amplitude_n (population SD / mean of the
included amplitudes, NaN with < 2; 2026-10-10);
with a reference beat <parameter>_pctRef / _dRef _mean / _SD; with AP columns (analyze_ap) _mean / _SD / _n.

TS 2026-10-06 (port of mda_summarize.m, TS 2026-10-04; uncertain contractions 2026-10-09; extra pulses 2026-10-10;
stimulus variability 2026-10-13; several ranges 2026-10-14)
"""
from __future__ import annotations

import math

import numpy as np
import pandas as pd

from ._matlab import nanmean, nanstd
from .parameters import PARAMETERS


def ranges_of(range_):
    """[from, to] or several ranges -> array n x 2 (2026-10-14)"""
    return np.asarray(range_, dtype=float).reshape(-1, 2)


def in_ranges(t, R):
    """t within one of the ranges R (rows [from, to], bounds included)"""
    t = np.asarray(t, dtype=float)
    out = np.zeros(t.shape, dtype=bool)
    for a, b in ranges_of(R):
        out |= (t >= a) & (t <= b)
    return out


def stim_variability(ST, range_, window=60.0, min_cv=0.1, exclude=None):
    """stim-to-stim variability of the regular pulses ST in range_ (one or several rows [from, to]; 2026-10-13):
    windows of window s from the start of each range (the last one shorter); paced windows: >= 6 pulses and no overlap
    with the [from to] rows of exclude (stimulation protocols); CV = population SD / mean of their intervals.
    Returns median CV (%), fraction of the paced time with CV > min_cv, paced time (s); NaN, NaN, 0 without paced
    windows."""
    ST = np.sort(np.asarray(ST, dtype=float))
    X = np.zeros((0, 2)) if exclude is None else np.asarray(exclude, dtype=float).reshape(-1, 2)
    cvs, dur, var = [], 0.0, 0.0
    for a, b in ranges_of(range_):
        w = float(a)
        while w < b:
            e = min(w + float(window), float(b))
            x = ST[(ST >= w) & (ST < e)]
            if x.size >= 6 and not np.any((X[:, 0] < e) & (X[:, 1] > w)):
                iv = np.diff(x)
                cv = float(np.std(iv) / np.mean(iv))
                cvs.append(cv)
                dur += e - w
                if cv > min_cv:
                    var += e - w
            w = e
    if not cvs:
        return math.nan, math.nan, 0.0
    return 100 * float(np.median(cvs)), var / dur, dur


def summarize(B, C, range_, opts=None, exclude=None):
    from .analyze_ap import AP_PARAMETERS
    if opts is None:
        from .options import options
        opts = options()
    params = [p[0] for p in PARAMETERS]
    R = ranges_of(range_)  # one or several ranges [from, to] (2026-10-14)
    tp = B["t_peak"].to_numpy(dtype=float)
    inRange = in_ranges(tp, R)
    I = inRange & B["included"].to_numpy(dtype=bool)
    ST = np.asarray(C.stimTimes, dtype=float)
    J = in_ranges(ST, R)
    fStim = math.nan
    iv = np.concatenate([np.diff(ST[(ST >= a) & (ST <= b)]) for a, b in R])  # intervals within the ranges
    if iv.size:
        fStim = 1 / float(np.median(iv))
    zeroF = C.get("zeroForce", math.nan)
    bt = B["beatType"].to_numpy()
    row = dict(channel=C.channel, **{"from": float(R[:, 0].min())}, to=float(R[:, 1].max()),
               nContractions=int(np.sum(I)),
               nDetected=int(np.sum(inRange)), nStimulated=int(np.sum(inRange & (bt == "stimulated"))),
               nExtraBeats=int(np.sum(inRange & (bt == "extra"))), nStimuli=int(np.sum(J)),
               nMissedBeats=int(np.sum(J & ~np.asarray(C.stimCaptured, bool))))
    row["extraBeats_percent"] = 100 * row["nExtraBeats"] / row["nDetected"] if row["nDetected"] > 0 else math.nan
    row["missedBeats_percent"] = 100 * row["nMissedBeats"] / row["nStimuli"] if row["nStimuli"] > 0 else math.nan
    # 2026-10-09: uncertain contractions (column uncertain, option detection): all, stimulated, extra beats, and missed
    # beats that are uncertain (stimuli followed only by an uncertain contraction: missed with detection='specific')
    u = inRange & B["uncertain"].to_numpy(dtype=bool)
    nMU = 0
    if C.get("stimCapturedCertain") is not None:
        nMU = int(np.sum(J & np.asarray(C.stimCaptured, bool) & ~np.asarray(C.stimCapturedCertain, bool)))
    row["nUncertain"] = int(np.sum(u))
    row["nStimulatedUncertain"] = int(np.sum(u & (bt == "stimulated")))
    row["nExtraBeatsUncertain"] = int(np.sum(u & (bt == "extra")))
    row["nMissedBeatsUncertain"] = nMU
    # 2026-10-10: extra pulses (status channel bit 16), contractions elicited by them, ambiguous assignments, missed
    # beats whose pulse fell into a contraction elicited by another pulse (refractory)
    nDur = nXP = nEl = nAmb = 0
    sd = C.get("stimDuringContraction")
    if sd is not None and np.size(sd) == ST.size:
        nDur = int(np.sum(J & np.asarray(sd, bool) & ~np.asarray(C.stimCaptured, bool)))
    xt = C.get("extraTimes")
    if xt is not None:
        xt = np.asarray(xt, float)
        nXP = int(np.sum(in_ranges(xt, R)))
    if "elicitedByExtraPulse" in B.columns:
        nEl = int(np.sum(inRange & B["elicitedByExtraPulse"].to_numpy(dtype=bool)))
    if "stimAmbiguous" in B.columns:
        nAmb = int(np.sum(inRange & B["stimAmbiguous"].to_numpy(dtype=bool)))
    row["nMissedDuringContraction"] = nDur
    row["nExtraPulses"] = nXP
    row["nElicitedByExtraPulse"] = nEl
    row["nAmbiguous"] = nAmb
    row["stimFrequency"] = fStim
    row["stimVariability_percent"], row["arrhythmicFraction"], row["pacedSeconds"] = stim_variability(
        ST[J], R, opts.get("arrhythmicWindow", 60.0), opts.get("arrhythmicMinVariability", 0.1), exclude)
    row["detectionThreshold"] = C.threshold
    row["zeroForce"] = zeroF
    # 2026-10-21: sensor rate of the channel inferred from repeated raw values (read_mdd)
    row["sensorRate_inferred"] = float(C.get("sensorRate", math.nan))
    row["repeatedSamples_percent"] = float(C.get("repeatedSamples_percent", math.nan))
    for p in params:
        v = B[p].to_numpy(dtype=float)[I]
        row[p + "_mean"] = nanmean(v)
        row[p + "_SD"] = nanstd(v)
        row[p + "_n"] = int(np.sum(~np.isnan(v)))
        if p == "amplitude":  # 2026-10-10: coefficient of variation (population SD / mean; irregular groups)
            w = v[~np.isnan(v)]
            row["amplitude_CV"] = float(np.std(w) / np.mean(w)) if w.size >= 2 else math.nan
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
