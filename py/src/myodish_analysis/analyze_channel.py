"""Detect the contractions of one channel and calculate their parameters. Port of mda_analyzeChannel.m.

    B, C = analyze_channel(S, channel, range_=None, opts=None)

S        data from read_mdd (should start/end a few seconds before/after the range, so that the first and last
         contraction of the range are complete)
channel  data channel (1-8; single channel files: 1)
range_   [from, to] in s (time in the file); contractions whose peak lies in the range are returned.
         None = all contractions in S
opts     options from options()

B  pandas DataFrame, one row per contraction (columns as in the MATLAB version)
C  Struct: filtered signal (t, f), detection threshold, stimulus times of the channel (stimTimes) and whether each
   stimulus was followed by a contraction (stimCaptured), all peaks in S (iPeaks, 0-based; peakTimes); with the
   option rockerFilter: result of rocker_filter (rockerFilter) and the subtracted artifact (rockerArtifact);
   referenceBeat: the reference used for the columns refCorrelation, ... (None = none)
With the option referenceBeat, B also contains every parameter relative to the reference: <parameter>_pctRef
(% of the mean of the reference contractions), diastolicForce_dRef / diastolicSignal_dRef (difference, uN).

PROCESSING (see the MATLAB help and README)
  0. option rockerFilter: the periodic rocker artifact is subtracted first (rocker_filter)
  1. filter: moving median (50 ms) + moving mean (25 ms) on the 200 Hz signal (as GetContractionParameters)
  2. contractions = local maxima with a prominence >= threshold that are >= minBeatInterval apart; automatic
     threshold: relThreshold x typical amplitude, at least minThreshold
  3. stimulus assignment: 'stimulated' if the peak follows a stimulus of the channel by minStimToPeak ...
     maxStimToPeak (and is the most prominent peak after this stimulus), otherwise 'extra'; 'unpaced' without stimuli
  4. parameters between the previous and the next peak (at most maxBeatWindow s), see parameters.py

TS 2026-10-06 (port of mda_analyzeChannel.m, TS 2026-10-05)
"""
from __future__ import annotations

import math

import numpy as np
import pandas as pd

from ._matlab import Struct, gradient, islocalmax, mode, movmean, movmedian, mround
from .options import options as _options
from .parameters import PARAMETERS
from .zero_force import zero_force, zero_at

UNITS_FIRST = {"channel": "", "contraction": "", "t_peak": "s", "beatType": "", "t_stim": "s", "stimToPeak": "s",
               "rockerMoving": "", "included": ""}


def analyze_channel(S, channel, range_=None, opts=None):
    if opts is None:
        opts = _options()
    elif "rockerFilter" not in opts or "referenceBeat" not in opts:
        opts = _options(opts)
    dataChannels = list(np.asarray(S.dataChannels).ravel())
    if channel not in dataChannels:
        raise ValueError(f"analyze_channel: channel {channel} is not in the file (data channels: {dataChannels}).")
    row = dataChannels.index(channel)
    if range_ is None or np.size(range_) == 0:
        range_ = [S.fromSeconds, S.toSeconds]
    range_ = [float(range_[0]), float(range_[1])]

    # rocker artifact (option rockerFilter): subtracted here, unless S was filtered before (with more context)
    RF = None
    if opts.rockerFilter:
        if "rockerFiltered" in S and len(S.rockerFiltered) > row and S.rockerFiltered[row]:
            RF = S.rockerFilterInfo[row]
        else:
            from .rocker_filter import rocker_filter
            S, RF = rocker_filter(S, channel, opts)
            RF = RF[0]

    dt = S.dt
    f, t = filter_signal(S.force[row], S.t, dt, opts)
    N = f.size
    g = gradient(f) / dt

    # ------------------------------------------------------------------ stimuli
    stimCh = opts.stimChannel
    stim_ch_all = np.asarray(S.stim.channel)
    if stimCh is None:
        stimCh = channel
        # files with fewer than 8 data channels (single channel mode): the data rows are numbered 1..n, the stimulus
        # pulses keep the physical channel number. If there are no pulses for this number: the stimulated channel.
        if len(dataChannels) < 8 and stim_ch_all.size and not np.any(stim_ch_all == channel):
            stimCh = int(mode(stim_ch_all))
    ST = np.sort(np.asarray(S.stim.time, dtype=float)[stim_ch_all == stimCh])
    CL = float(np.median(np.diff(ST))) if ST.size > 1 else math.nan
    if not isinstance(opts.maxStimToPeak, str):
        maxLat = float(opts.maxStimToPeak)
    elif math.isnan(CL):
        maxLat = 0.9
    else:
        maxLat = min(CL, 1.0)

    # ------------------------------------------------------------------ detection
    isMax, P = islocalmax(f)
    cand = np.flatnonzero(isMax)
    prom = P[cand]
    if not isinstance(opts.threshold, str):
        thr = float(opts.threshold)
        thrMode = "manual"
        typAmp = math.nan
    else:
        thr, typAmp = auto_threshold(prom, ST.size, opts)
        thrMode = "auto"
    keep = prom >= thr
    cand = cand[keep]
    prom = prom[keep]
    # minimum interval: the more prominent of two close maxima wins
    order = np.argsort(-prom, kind="stable")
    w = max(1, mround(opts.minBeatInterval / dt))
    blocked = np.zeros(N, bool)
    accepted = np.zeros(cand.size, bool)
    for q in order:
        i = cand[q]
        if not blocked[i]:
            accepted[q] = True
            blocked[max(0, i - w + 1):min(N, i + w)] = True
    iPk = cand[accepted]
    promPk = prom[accepted]
    nPk = iPk.size
    tPk = t[iPk]

    # ------------------------------------------------------------------ stimulus assignment
    beatType = np.array(["unpaced"] * nPk, dtype=object)
    tStimOfBeat = np.full(nPk, np.nan)
    stimCaptured = np.zeros(ST.size, bool)
    if ST.size:
        beatType[:] = "extra"
        j = np.full(nPk, -1)
        for k in range(nPk):
            jj = np.searchsorted(ST, tPk[k] - opts.minStimToPeak, side="right") - 1  # last ST <= tPk - minStimToPeak
            if jj >= 0 and tPk[k] - ST[jj] <= maxLat:
                j[k] = jj
        for jj in np.unique(j[j >= 0]):
            ks = np.flatnonzero(j == jj)
            k = ks[np.argmax(promPk[ks])]  # several peaks after one stimulus: the most prominent one
            beatType[k] = "stimulated"
            tStimOfBeat[k] = ST[jj]
            stimCaptured[jj] = True

    # ------------------------------------------------------------------ zero force
    _, zeroSource, zeroT, zeroV = zero_force(S, channel, opts.zeroForce)

    # ------------------------------------------------------------------ parameters
    sel = np.flatnonzero((tPk >= range_[0]) & (tPk <= range_[1]))
    n = sel.size
    names = [p[0] for p in PARAMETERS]
    ix = {nm: k for k, nm in enumerate(names)}
    V = np.full((n, len(names)), np.nan)
    rockerMoving = np.zeros(n, bool)
    rockerOn = np.asarray(S.rockerOn, bool)
    maxW = mround(opts.maxBeatWindow / dt)
    for q in range(n):
        k = sel[q]
        i = iPk[k]
        a = iPk[k - 1] if k > 0 else 0
        b = iPk[k + 1] if k < nPk - 1 else N - 1
        a = max(a, i - maxW, 0)
        b = min(b, i + maxW, N - 1)
        seg = f[a:i + 1][::-1]  # f(i:-1:a): last minimum before the peak (flat diastole: the one next to the upstroke)
        ia = i - int(np.argmin(seg))
        Fdia = f[ia]
        ib = i + int(np.argmin(f[i:b + 1]))
        Fpost = f[ib]
        Fpk = f[i]
        A = Fpk - Fdia
        if k > 0:
            V[q, ix["peakToPeakInterval"]] = tPk[k] - tPk[k - 1]
        rockerMoving[q] = rockerOn[ia:ib + 1].any()  # replaced below by F_dia ... 90 % relaxation, if available
        if A <= 0 or ia == 0:  # no upstroke within the data (contraction starts before the loaded data)
            continue
        up10 = _cross_up(f, t, dt, ia, i, Fdia + 0.1 * A)
        up50 = _cross_up(f, t, dt, ia, i, Fdia + 0.5 * A)
        up90 = _cross_up(f, t, dt, ia, i, Fdia + 0.9 * A)
        V[q, ix["amplitude"]] = A
        V[q, ix["diastolicSignal"]] = Fdia
        V[q, ix["diastolicForce"]] = Fdia - zero_at(zeroT, zeroV, t[ia])
        V[q, ix["dFdtMax"]] = np.max(g[ia:i + 1])
        V[q, ix["riseTime10_90"]] = up90 - up10
        V[q, ix["TTP90"]] = t[i] - up10
        if ib < N - 1 and Fpk > Fpost:  # relaxation within the data
            R = Fpk - Fpost
            rel50, _ = _cross_down(f, t, dt, i, ib, Fpost + 0.5 * R)
            rel90, j90 = _cross_down(f, t, dt, i, ib, Fpost + 0.1 * R)
            V[q, ix["dFdtMin"]] = np.min(g[i:ib + 1])
            rockerMoving[q] = rockerOn[ia:j90 + 1].any()  # rocker state from F_dia to 90 % relaxation
            V[q, ix["TTR50"]] = rel50 - t[i]
            V[q, ix["TTR90"]] = rel90 - t[i]
            V[q, ix["CD50"]] = rel50 - up50
            V[q, ix["CD90"]] = rel90 - up10
            # AUC: trapezoid of (F - F_dia) from the 10 % crossing (upstroke) to the 90 % relaxation crossing
            below = np.flatnonzero(f[ia:i] < Fdia + 0.1 * A)
            i10 = below[-1] + ia + 1  # first sample above the 10 % level
            tt = np.r_[up10, t[i10:j90], rel90]
            yy = np.r_[0.1 * A, f[i10:j90] - Fdia, Fpost + 0.1 * R - Fdia]
            V[q, ix["AUC"]] = _trapz(tt, yy)
    with np.errstate(divide="ignore"):
        V[:, ix["peakToPeakFrequency"]] = 1.0 / V[:, ix["peakToPeakInterval"]]
    # set stimulation interval: stimulus of the contraction (extra contraction: last stimulus before the peak) minus the
    # previous stimulus pulse of the channel
    for q in range(n):
        tRef = tStimOfBeat[sel[q]]
        if math.isnan(tRef):
            tRef = tPk[sel[q]]
        j = np.searchsorted(ST, tRef + 1e-9, side="right") - 1
        if j >= 1:
            V[q, ix["stimInterval"]] = ST[j] - ST[j - 1]
    with np.errstate(divide="ignore"):
        V[:, ix["stimFrequency"]] = 1.0 / V[:, ix["stimInterval"]]

    # ------------------------------------------------------------------ table
    beatSel = beatType[sel]
    tStim = tStimOfBeat[sel]
    tPeakSel = tPk[sel]
    promSel = promPk[sel]
    included = ~np.isnan(V[:, 0])
    if opts.beats == "stimulated":
        included &= beatSel == "stimulated"
    if opts.rocker == "stopped":
        included &= ~rockerMoving
    if opts.rocker == "moving":
        included &= rockerMoving
    B = pd.DataFrame({"channel": np.full(n, channel, dtype=float), "contraction": np.arange(1, n + 1, dtype=float),
                      "t_peak": tPeakSel, "beatType": pd.Series(list(beatSel), dtype=object), "t_stim": tStim,
                      "stimToPeak": tPeakSel - tStim, "rockerMoving": rockerMoving, "included": included})
    for k, nm in enumerate(names):
        B[nm] = V[:, k]
    B["prominence"] = promSel
    units = dict(UNITS_FIRST)
    units.update({p[0]: p[1] for p in PARAMETERS})
    units["prominence"] = "uN"
    if opts.rockerFilter:  # contraction during a rocker movement whose artifact was subtracted
        art = S.rockerArtifact[row]
        B["rockerCorrected"] = rockerMoving & (art[iPk[sel]] != 0)
        units["rockerCorrected"] = ""
    B.attrs["units"] = units

    C = Struct()
    C.channel = channel
    C.stimChannel = stimCh
    C.t = t
    C.f = f
    C.iPeaks = iPk
    C.peakTimes = tPk
    C.threshold = thr
    C.thresholdMode = thrMode
    C.typicalAmplitude = typAmp
    C.stimTimes = ST
    C.stimCaptured = stimCaptured
    C.stimInterval = CL
    C.maxStimToPeak = maxLat
    C.range = range_
    C.zeroForce = zero_at(zeroT, zeroV, float(np.mean(range_)))
    C.zeroSource = zeroSource
    C.rockerFilter = RF  # None = not applied; otherwise result of rocker_filter
    C.rockerArtifact = None
    if opts.rockerFilter:
        C.rockerArtifact = S.rockerArtifact[row].copy()  # subtracted artifact (uN, at C.t)
    # comparison with a reference beat of this channel (option referenceBeat; otherwise the columns stay NaN)
    C.referenceBeat = None
    refs = opts.referenceBeat
    from . import reference_beat as rb
    if refs and n > 0:
        refs = [r for r in refs if "channel" in r and r["channel"] == channel]
        if refs:
            Vr = rb.compare(C, B, refs[0])
            for nm in Vr.columns:
                B[nm] = Vr[nm].to_numpy()
            C.referenceBeat = rb.align(refs[0], "")  # standard fields (also older references)
    # every parameter relative to the reference (<parameter>_pctRef, diastolic: _dRef). Added whenever the option
    # referenceBeat is set (NaN for channels without own reference), so that tables of all channels match
    if opts.referenceBeat:
        Vrel = rb.relative(B, C.referenceBeat)
        for nm in Vrel.columns:
            B[nm] = Vrel[nm].to_numpy()
        units.update(Vrel.attrs.get("units", {}))
    B.attrs["units"] = units
    return B, C


# =====================================================================================================
def filter_signal(x, t, dt, opts):
    """moving median + moving mean (windows in ms). An even window is centred half a sample before the current
    sample, i.e. delays the signal by dt/2: the time axis is corrected accordingly."""
    f = np.asarray(x, dtype=float)
    nMed = mround(opts.medianFilterMs / 1000 / dt)
    nMean = mround(opts.meanFilterMs / 1000 / dt)
    delay = 0.0
    if nMed > 1:
        f = movmedian(f, nMed)
        if nMed % 2 == 0:
            delay += dt / 2
    if nMean > 1:
        f = movmean(f, nMean)
        if nMean % 2 == 0:
            delay += dt / 2
    return f, np.asarray(t, dtype=float) - delay


def auto_threshold(prom, nStim, opts):
    """threshold = relThreshold x typical contraction amplitude, at least minThreshold (see the MATLAB help)."""
    typical = math.nan
    p = np.sort(prom[prom > 0])[::-1]
    if nStim >= 3:
        if p.size:
            typical = float(np.median(p[:min(p.size, nStim)]))
    else:
        p = p[p >= opts.minThreshold]
        if p.size >= 3:
            ratio = p[:-1] / p[1:]
            ratio[0] = 0  # at least 2 contractions above the gap (a single artifact is no cluster)
            k = int(np.argmax(ratio))
            typical = float(np.median(p[:k + 1]))
        elif p.size:
            typical = float(np.median(p))
    thr = opts.minThreshold if math.isnan(typical) else max(opts.minThreshold, opts.relThreshold * typical)
    return float(thr), typical


def _cross_up(f, t, dt, ia, i, level):
    """last crossing of level from below between the minimum (ia) and the peak (i), linear interpolation."""
    below = np.flatnonzero(f[ia:i] < level)
    if below.size == 0:
        return math.nan
    j = below[-1] + ia
    if f[j + 1] == f[j]:
        return math.nan
    return t[j] + (level - f[j]) / (f[j + 1] - f[j]) * dt


def _cross_down(f, t, dt, i, ib, level):
    """first crossing of level from above between the peak (i) and the minimum after the peak (ib)."""
    below = np.flatnonzero(f[i + 1:ib + 1] < level)
    if below.size == 0:
        return math.nan, ib
    j = below[0] + i + 1
    return t[j - 1] + (f[j - 1] - level) / (f[j - 1] - f[j]) * dt, j


def _trapz(x, y):
    x = np.asarray(x, float); y = np.asarray(y, float)
    if x.size < 2:
        return 0.0
    return float(np.sum(np.diff(x) * (y[:-1] + y[1:]) / 2))
