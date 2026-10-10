"""Periods without force signal: chamber taken out, sensor board failures, channels without a chamber. Port of
mda_signalGaps.m.

    G = signal_gaps(mdd_file)            or  G = signal_gaps(H)   (H from read_mdd)
    G = signal_gaps(mdd_file, opts)      opts from options() (calibration of the values)
    G = signal_gaps(..., min_seconds=2, simultaneous=1, simultaneous_pair=0.1, merge_seconds=0.5)

Without a sensor board (chamber taken out of the setup, defective board) the controller repeats the last value of the
channel: the signal stays at exactly the same number. A connected sensor never gives identical values for seconds
(noise of the AD converter). A period without signal = at least min_seconds (default 2 s) of identical consecutive raw
samples of a data channel. Periods of a channel less than merge_seconds (default 0.5 s) apart are one period (the value
held may jump once, e.g. when another board of the controller is plugged in or the controller restarts).

G  DataFrame, one row per period and channel, sorted by the start (columns as in MATLAB):
     channel, from, to, duration (s in the file; to = first sample with signal again or the end of the file)
     type            'chamber out'  one channel: chamber taken out (and put back at 'to' unless untilEnd). The reason
                                    is not in the signal (log comments, documentation).
                     'board group'  >= 3 channels of the same group (1-4 or 5-8) within 'simultaneous' s (default 1),
                                    or 2 channels within 'simultaneous_pair' s (default 0.1): faster than a person can
                                    take chambers out (two hands: two chambers at once), i.e. a technical failure (a
                                    defective sensor board disturbs the other boards of its group)
                     'controller'   the same with channels of both groups (controller, connection)
                     'saturated'    the value held is the limit of the AD converter (-32768 or 32767: overload)
                     'no signal'    the whole recording (no chamber in this channel)
     nSimultaneous   channels in the same event (1 for 'chamber out')
     spread          s between the first and the last channel of the event (0 for 'chamber out')
     fromStart       the period begins with the file (simultaneity then judged from the ends: signal back)
     untilEnd        the period lasts until the end of the file
     valueAU, value  value held (raw value of the file; uN, or AU with calibration='none')
     levelBefore     10th percentile of the 5 s before the period (ending 0.5 s before it): diastolic level
     levelAfter      10th percentile of the 5 s after the period (from 2 s after it)
     levelChange     levelAfter - levelBefore (e.g. other preload or another slice after putting the chamber back)
     spikeBefore     largest deviation from the median of the 2 s before the period within its last 0.5 s
     spikeAfter      largest deviation from the median of the 2 s after the period (from 0.5 s) within its first 0.5 s
                     (levels and spikes NaN where there is no signal)

Reads the raw data of the whole file in 1-h blocks.

TS 2026-10-08 (port of mda_signalGaps.m)
"""
from __future__ import annotations

import math

import numpy as np
import pandas as pd

from .calibration_factor import calibration_factor
from .options import options as _options
from .read_mdd import read_mdd

COLUMNS = ["channel", "from", "to", "duration", "type", "nSimultaneous", "spread", "fromStart", "untilEnd", "valueAU",
           "value", "levelBefore", "levelAfter", "levelChange", "spikeBefore", "spikeAfter"]


def _prctile(x, p):
    """MATLAB prctile of a vector (NaN ignored)"""
    x = np.sort(np.asarray(x, float)[~np.isnan(np.asarray(x, float))])
    n = x.size
    if n == 0:
        return math.nan
    if n == 1:
        return float(x[0])
    q = 100 * (np.arange(1, n + 1) - 0.5) / n
    return float(np.interp(min(max(p, q[0]), q[-1]), q, x))


def _around(H, opts, c, t0, side):
    level = math.nan
    spike = math.nan
    if side < 0:
        w = [t0 - 5.5, t0 - 0.5]
        ws = [t0 - 2, t0]
    else:
        w = [t0 + 2, t0 + 7]
        ws = [t0, t0 + 2]
    T = H.totalSeconds
    w = [max(min(v, T), 0.0) for v in w]
    ws = [max(min(v, T), 0.0) for v in ws]
    iC = list(np.ravel(H.dataChannels)).index(c)
    if w[1] - w[0] >= 1:
        S = read_mdd(H, w[0], w[1], opts)
        level = _prctile(np.asarray(S.force)[iC], 10)
    if ws[1] - ws[0] >= 1:
        S = read_mdd(H, ws[0], ws[1], opts)
        x = np.asarray(S.force)[iC]
        t = np.asarray(S.t)
        near = t >= ws[1] - 0.5 if side < 0 else t < ws[0] + 0.5
        ref = ~near
        if near.any() and ref.any():
            spike = float(np.max(np.abs(x[near] - np.median(x[ref]))))
    return level, spike


def signal_gaps(src, opts=None, min_seconds=2.0, simultaneous=1.0, simultaneous_pair=0.1, merge_seconds=0.5):
    if opts is None:
        opts = _options()
    H = src if isinstance(src, dict) else read_mdd(str(src), opts=opts)
    opts_full = _options(opts, downsampling=1, spikeRemoval=False)  # levels and spikes at the periods: raw
    fs = H.samplingRate
    ch = [int(c) for c in np.ravel(H.dataChannels)]
    nCh = len(ch)
    minN = max(2, int(round(min_seconds * fs)))

    # runs of identical consecutive raw samples (indices of the samples, 1 = first sample of the file), 1-h blocks
    runs = []  # [channel index (1-based), first sample, last sample, raw value]
    cur = [None] * nCh
    lastVal = [None] * nCh
    nF = int(H.nChannelsInFile)
    N = int(H.totalSamples)
    block = int(round(3600 * fs))
    n0 = 0
    with open(H.file, "rb") as fh:
        while n0 < N:
            m = min(block, N - n0)
            raw = np.fromfile(fh, dtype="<i2", count=nF * m)
            m = raw.size // nF
            if m == 0:
                break
            raw = raw[: m * nF].reshape(m, nF).T
            for c in range(nCh):
                v = raw[c].astype(np.int64)
                first_new = (lastVal[c] is None) or (v[0] != lastVal[c])
                st = np.flatnonzero(np.concatenate([[first_new], v[1:] != v[:-1]])) + 1  # 1-based in block
                if st.size:
                    if cur[c] is not None and n0 + st[0] - cur[c][0] >= minN:
                        runs.append([c + 1, cur[c][0], n0 + st[0] - 1, cur[c][1]])
                    q = np.flatnonzero(np.diff(st) >= minN)
                    for i in q:
                        runs.append([c + 1, n0 + int(st[i]), n0 + int(st[i + 1]) - 1, int(v[st[i] - 1])])
                    cur[c] = (n0 + int(st[-1]), int(v[st[-1] - 1]))
                lastVal[c] = int(v[-1])
            n0 += m
    for c in range(nCh):
        if cur[c] is not None and n0 - cur[c][0] + 1 >= minN:
            runs.append([c + 1, cur[c][0], n0, cur[c][1]])

    # merge periods of a channel that are less than merge_seconds apart (glitch between two held values)
    runs.sort(key=lambda r: (r[0], r[1]))
    merged = []
    for r in runs:
        if merged and r[0] == merged[-1][0] and r[1] - merged[-1][2] - 1 < merge_seconds * fs:
            merged[-1][2] = max(merged[-1][2], r[2])
        else:
            merged.append(list(r))
    runs = merged
    nR = len(runs)
    if nR == 0:
        return pd.DataFrame({c: pd.Series([], dtype=object if c == "type" else float) for c in COLUMNS})
    R = np.array(runs, dtype=float)
    G = pd.DataFrame({
        "channel": [ch[int(i) - 1] for i in R[:, 0]],
        "from": (R[:, 1] - 1) / fs,
        "to": R[:, 2] / fs,
    })
    G["duration"] = G["to"] - G["from"]
    G["type"] = "chamber out"
    G["nSimultaneous"] = 1
    G["fromStart"] = R[:, 1] == 1
    G["untilEnd"] = R[:, 2] == n0
    G["valueAU"] = R[:, 3]
    G["value"] = [G["valueAU"].iat[r]
                  * float(calibration_factor(H, int(G["channel"].iat[r]), np.array([G["from"].iat[r]]))[0])
                  for r in range(nR)]
    for c in ["levelBefore", "levelAfter", "levelChange", "spikeBefore", "spikeAfter"]:
        G[c] = math.nan

    # type
    sat = ((G["valueAU"] <= -32768) | (G["valueAU"] >= 32767)).to_numpy()
    none = (G["fromStart"] & G["untilEnd"]).to_numpy()
    typ = np.array(["chamber out"] * nR, dtype=object)
    typ[sat] = "saturated"
    typ[none & ~sat] = "no signal"
    nSim = np.ones(nR, dtype=int)
    spr = np.zeros(nR)
    # simultaneous events: signal lost (from) of periods within the file, and signal back (to) of periods from the
    # file start, each kind separately. A person has two hands: >= 3 channels within 'simultaneous' s, or 2 channels
    # within 'simultaneous_pair' s are technical.
    grp = np.where(G["channel"].to_numpy() > 4, 2, 1)
    fromStart = G["fromStart"].to_numpy()
    for kind in (1, 2):
        if kind == 1:
            cand = np.flatnonzero(~sat & ~none & ~fromStart)
            ev = G["from"].to_numpy()
        else:
            cand = np.flatnonzero(~sat & ~none & fromStart)
            ev = G["to"].to_numpy()
        cand = cand[np.argsort(ev[cand], kind="stable")]
        k = 0
        while k < cand.size:
            j = k
            while j < cand.size - 1 and ev[cand[j + 1]] - ev[cand[k]] <= simultaneous:
                j += 1
            I = cand[k:j + 1]
            spread = ev[I[-1]] - ev[I[0]]
            if I.size >= 3 or (I.size == 2 and spread <= simultaneous_pair):
                typ[I] = "board group" if np.all(grp[I] == grp[I[0]]) else "controller"
                nSim[I] = I.size
                spr[I] = spread
            k = j + 1
    G["type"] = typ
    G["nSimultaneous"] = nSim
    G["spread"] = spr

    # levels and spikes around the period (signal of the channel)
    for r in np.flatnonzero(~none):
        c = int(G["channel"].iat[r])
        if not G["fromStart"].iat[r]:
            lv, sp = _around(H, opts_full, c, float(G["from"].iat[r]), -1)
            G.loc[G.index[r], "levelBefore"] = lv
            G.loc[G.index[r], "spikeBefore"] = sp
        if not G["untilEnd"].iat[r]:
            lv, sp = _around(H, opts_full, c, float(G["to"].iat[r]), 1)
            G.loc[G.index[r], "levelAfter"] = lv
            G.loc[G.index[r], "spikeAfter"] = sp
    G["levelChange"] = G["levelAfter"] - G["levelBefore"]
    G = G.sort_values(["from", "channel"], kind="stable").reset_index(drop=True)
    return G[COLUMNS]
