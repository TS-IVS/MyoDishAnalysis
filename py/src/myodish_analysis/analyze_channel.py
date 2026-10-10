"""Detect the contractions of one channel and calculate their parameters. Port of mda_analyzeChannel.m.

    B, C = analyze_channel(S, channel, range_=None, opts=None)

S        data from read_mdd (should start/end a few seconds before/after the range, so that the first and last
         contraction of the range are complete)
channel  data channel (1-8; single channel files: 1)
range_   [from, to] in s (time in the file); contractions whose peak lies in the range are returned.
         None = all contractions in S
opts     options from options()

B  pandas DataFrame, one row per contraction (columns as in the MATLAB version); stimulus columns: t_stim,
   stimToPeak, t_onset, stimToOnset, stimPulse (ID = raw sample number of the eliciting pulse), stimCurrent (mA),
   stimChargeDuration, stimPauseDuration, stimDechargeDuration (us, log file), elicitedByExtraPulse, stimAmbiguous,
   prePulses, postPulses (see 3.)
C  Struct: filtered signal (t, f), detection threshold, regular stimulus pulses of the channel (stimTimes), whether
   each was followed by a contraction (stimCaptured) or fell into a contraction elicited by another pulse
   (stimDuringContraction), extra pulses (extraTimes, extraElicited), onsets of all peaks (onsetTimes), table of the
   pulses of the range (pulses; option pulseTable, see pulse_table), all peaks in S (iPeaks, 0-based; peakTimes);
   with the option rockerFilter: result of rocker_filter (rockerFilter) and the subtracted artifact (rockerArtifact);
   referenceBeat: the reference used for the columns refCorrelation, ... (None = none)
With the option referenceBeat, B also contains every parameter relative to the reference: <parameter>_pctRef
(% of the mean of the reference contractions), diastolicForce_dRef / diastolicSignal_dRef (difference, uN).

PROCESSING (see the MATLAB help and README)
  0. option rockerFilter: the periodic rocker artifact is subtracted first (rocker_filter)
  1. filter: moving median (50 ms) + moving mean (25 ms) on the 200 Hz signal (as GetContractionParameters)
  2. contractions = local maxima with a prominence >= threshold that are >= minBeatInterval apart; automatic
     threshold: relThreshold x typical amplitude, at least minThreshold. Paced channels, auto threshold (option
     rockerArtifacts): a) raised into a clear gap above small peaks not locked to the stimuli (rocker artifacts),
     small peaks locked to a stimulus stay (artifact_gap_threshold); b) rocker moving (>= 50 % of the data), rocker /
     noise level N before the stimuli (pre_stimulus_noise): largest peaks not locked to the stimuli and typical
     amplitude <= 50 uN or <= 2 x N at the rhythm of the rocker: rocker / noise peaks are removed
     (C.noContractions if none is left); c) otherwise peaks not locked to the stimuli below min(1.5 x N,
     0.5 x typical) (typical if at the rhythm of the rocker) are removed (rocker_noise_rule).
     C.thresholdArtifacts = removed peaks, C.noiseLevel = N. Without N (high rates, no intervals >= 0.9 s): peaks at
     the rhythm of the rocker (>= 60 % of the intervals 1 or 1/2 rocker period), not locked to the stimuli and no
     1:1 / 2:1 capture at the rocker period are removed while the rocker moves
  2b. certainty (auto threshold, option detection): paced channels: a contraction is certain if it is locked to the
     stimuli (latency within +-min(0.1 s, 0.2 x stimulus interval) of the typical latency) and >= 2 x the median rise
     before the stimuli (C.noiseMedian), or large (>= 0.7 x typical and >= 3 x that median); unpaced: >= 0.5 x
     typical. Otherwise column uncertain = True ('sensitive', default) or the contraction is not counted
     ('specific'). C.stimCapturedCertain: stimulus followed by a certain contraction
  3. stimulus assignment (option stimAssignment, default 'onset', 2026-10-10): every pulse of the channel, regular or
     extra pulse (status channel bit 16), is a candidate. Onset = the tangent at the maximum dF/dt crossing the
     diastolic level. A pulse can only have elicited a contraction if it lies in the gate onset - gateMax ... onset +
     gateTolerance (0.15 s / 0.015 s). Contractions in the order of their prominence, every pulse elicits at most one
     contraction; several candidates: pulses before the onset before pulses after it, regular pulses before extra
     pulses, of one kind the earliest within gateCore (0.06 s) before the onset, otherwise the latest. No pulse in
     the gate: the onsets of the other rise phases of the upstroke (local maxima of dF/dt >= 25 % of the maximum:
     rocker movement, a spontaneous event fused with the contraction) are tried, the earliest first, then a pulse up
     to 5 ms before the maximum dF/dt. Column stimAmbiguous: a pulse of the other kind within ambiguityWindow of the
     chosen one or chosen with the onset gateTolerance earlier or later, a later rise phase, or the pulse after the
     gate. 'stimulated' = a pulse in the gate, 'extra' = none, 'unpaced' = channel without pulses. Pulses that
     elicited no contraction: post-pulses (eliciting pulse ... 90 % relaxation) and pre-pulses (up to prePulseWindow
     before the eliciting pulse), columns prePulses / postPulses 't<ms>|<mA>|<charge us>|<pause us>|<decharge us>'
     joined by '&'. 'peak' (versions <= 1.0.0-beta.3): 'stimulated' if the peak follows a pulse by minStimToPeak ...
     maxStimToPeak (the most prominent peak after it); extra pulses count as regular pulses
  4. parameters between the previous and the next peak (at most maxBeatWindow s), see parameters.py. Diastolic level
     F_dia (option diastolicLevel, 2026-10-10): median of the unfiltered signal 60 ... 5 ms (diastoleWindowStart ...
     diastoleWindowEnd) before the eliciting pulse; contractions without pulse, or a median at or above the peak: the
     last minimum of the filtered signal before the peak ('minimum', versions <= 1.0.0-beta.3). Amplitude, upstroke
     levels, AUC and diastolic force refer to F_dia, relaxation levels to the minimum after the peak. After a
     stimulation pause (stimulus interval >= 2.5 s and >= 1.5 x the interval before) the minimum before the peak is
     searched only from pauseDiastoleWindow (0.5 s) before the stimulus (options.py)

TS 2026-10-06 (port of mda_analyzeChannel.m, TS 2026-10-05; rocker artifacts, certainty of contractions
2026-10-09; onset gate, extra pulses, pulse table, diastolic level before the pulse 2026-10-10)
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
               "rockerMoving": "", "included": "", "uncertain": ""}
UNITS_STIM = {"t_onset": "s", "stimToOnset": "s", "stimPulse": "", "stimCurrent": "mA", "stimChargeDuration": "us",
              "stimPauseDuration": "us", "stimDechargeDuration": "us", "elicitedByExtraPulse": "", "stimAmbiguous": "",
              "prePulses": "", "postPulses": ""}
PULSE_UNITS = {"pulse": "", "channel": "", "t": "s", "extra": "", "current_mA": "mA", "currentReached": "",
               "chargeDuration_us": "us", "pauseDuration_us": "us", "dechargeDuration_us": "us", "outcome": "",
               "role": "", "contraction": "", "t_peak": "s", "tRel_ms": "ms", "couplingInterval_s": "s",
               "sinceOnset_s": "s", "phase": ""}


def analyze_channel(S, channel, range_=None, opts=None):
    if opts is None:
        opts = _options()
    elif ("rockerFilter" not in opts or "referenceBeat" not in opts or "pauseDiastoleWindow" not in opts
          or "lockWindow" not in opts or "diastolicLevel" not in opts):
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
    isMD = stim_ch_all > 0  # MyoDish stimulus pulses (0 = external trigger pulse)
    if stimCh is None:
        stimCh = channel
        # files with fewer than 8 data channels (single channel mode): the data rows are numbered 1..n, the stimulus
        # pulses keep the physical channel number. If there are no pulses for this number: the stimulated channel.
        if len(dataChannels) < 8 and isMD.any() and not np.any(stim_ch_all == channel):
            stimCh = int(mode(stim_ch_all[isMD]))
    # external trigger pulses (external stimulator at the external controller unit: one chamber, no channel number)
    # as stimuli: 'on', or 'auto' if the window has trigger pulses but no MyoDish pulses (2026-10-08)
    xt = opts.get("externalTrigger", "auto")
    if xt == "on" or (xt == "auto" and not isMD.any() and np.any(stim_ch_all == 0)):
        stimCh = 0
    # pulses of the channel: regular pulses (ST) and extra pulses (status channel bit 16: pre-pulses, CCM pulses, ...;
    # 2026-10-10). Option stimAssignment 'peak' (versions <= 1.0.0-beta.3): extra pulses count as regular pulses.
    legacy = opts.get("stimAssignment", "onset") == "peak"
    selP = np.flatnonzero(stim_ch_all == stimCh)  # (indices: as MATLAB, other fields may be shorter after the last one)
    PT = np.asarray(S.stim.time, dtype=float)[selP]
    PX = np.zeros(PT.size, bool)
    if stimCh > 0 and "isExtraPulse" in S.stim and not legacy:
        PX = np.asarray(S.stim.isExtraPulse, bool).ravel()[selP]
    PC = np.full(PT.size, np.nan)  # current (mA) and current reached (status channel)
    PR = np.ones(PT.size, bool)
    if "current" in S.stim:
        PC = np.asarray(S.stim.current, float).ravel()[selP]
    if "currentReached" in S.stim:
        PR = np.asarray(S.stim.currentReached, bool).ravel()[selP]
    o = np.argsort(PT, kind="stable")
    PT, PX, PC, PR = PT[o], PX[o], PC[o], PR[o]
    STall = PT  # all pulses (latency of the peaks: locked to any pulse)
    ST = PT[~PX]  # regular pulses (counts, intervals, missed beats)
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
    if not isinstance(opts.threshold, str) and np.size(opts.threshold) > 1:
        raise ValueError("analyze_channel: one threshold per channel (several channels: myodish_analysis).")
    nArt = 0  # peaks removed as rocker artifacts
    keepLow = np.zeros(prom.size, bool)  # small peaks below a raised threshold that are kept (locked to a stimulus)
    drop = np.zeros(prom.size, bool)  # peaks removed by the rocker / noise level
    noBeats = False  # no contractions (peaks at the rocker / noise level)
    noiseLvl = math.nan  # rocker / noise level before the stimuli (uN, 90th percentile)
    noiseMed = math.nan  # median rise before the stimuli (uN; certainty of contractions)
    if not isinstance(opts.threshold, str) and not math.isnan(float(np.ravel(opts.threshold)[0])):
        thr = float(np.ravel(opts.threshold)[0])  # NaN = auto (per-channel thresholds of myodish_analysis)
        thrMode = "manual"
        typAmp = math.nan
    else:
        thr, typAmp = auto_threshold(prom, ST.size, opts)
        thrMode = "auto"
        if ST.size >= opts.pacedMinStimuli:  # paced: rocker / noise level before the stimuli
            noiseLvl, nNoise, noiseMed = pre_stimulus_noise(t, f, ST, opts)
            if nNoise < opts.noiseMinWindows:
                noiseLvl = math.nan
                noiseMed = math.nan
        if opts.get("rockerArtifacts", True) and ST.size >= opts.pacedMinStimuli:  # paced: rocker artifacts
            rockerOn = np.asarray(S.rockerOn, bool).ravel()
            thr, keepLow, nArt = artifact_gap_threshold(t[cand], prom, thr, typAmp, STall, rockerOn[cand], CL, opts)
            if rockerOn.mean() >= opts.rockerRuleMinFraction:
                fR = rocker_frequency(S, opts)
                drop, noBeats = rocker_noise_rule(t[cand], prom, thr, keepLow, typAmp, ST, noiseLvl, rockerOn[cand],
                                                  np.count_nonzero(rockerOn) * dt, fR, STall, opts)
                nArt += int(np.count_nonzero(drop))
    keep = ((prom >= thr) | keepLow) & ~drop
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
    # certainty (option detection, 2026-10-09). Paced: certain = locked to the stimuli (latency within +-hw of the
    # typical latency, hw = min(0.1 s, 0.2 x stimulus interval before the largest contractions)) and >= 2 x Nm, or
    # large (>= 0.7 x typical and >= 3 x Nm); Nm = median rise before the stimuli (unknown: locked suffices), typical =
    # median of the largest contractions (as many as stimuli). Unpaced: certain = >= 0.5 x typical (auto threshold).
    # 'sensitive': uncertain contractions are counted and flagged (column uncertain); 'specific': they are removed.
    # Manual threshold: not assessed.
    certain = np.ones(iPk.size, bool)
    if thrMode == "auto" and iPk.size:
        if ST.size >= opts.pacedMinStimuli:
            o = np.argsort(-promPk, kind="stable")
            top = o[:min(o.size, ST.size)]
            typC = float(np.median(promPk[top]))
            lat = _stim_latency(t[iPk], STall)
            ci = np.full(top.size, np.nan)  # stimulus interval before the largest contractions
            for q in range(top.size):
                j = int(np.searchsorted(ST, t[iPk[top[q]]], side="right")) - 1  # last ST <= t
                if j >= 1:
                    ci[q] = ST[j] - ST[j - 1]
            ci = ci[~np.isnan(ci)]
            hw = min(opts.lockWindow, opts.lockWindowRel * float(np.median(ci))) if ci.size else opts.lockWindow
            lk = latency_lock(lat, top, hw)
            with np.errstate(invalid="ignore"):
                certain = (lk & ~(promPk < opts.certainNoiseRel * noiseMed)) | \
                    ~(promPk < np.fmax(opts.certainLargeRel * typC, opts.certainLargeNoiseRel * noiseMed))
        elif not math.isnan(typAmp):
            certain = promPk >= opts.certainUnpacedRel * typAmp
    if opts.get("detection", "sensitive") == "specific":
        iPk = iPk[certain]
        promPk = promPk[certain]
        certain = certain[certain]
    nPk = iPk.size
    tPk = t[iPk]

    # ------------------------------------------------------------------ stimulus assignment
    # onset of every contraction: tangent at the maximum dF/dt between the diastolic minimum and the peak, crossing the
    # diastolic level (NaN without upstroke in the data); end of the contraction: 90 % relaxation (2026-10-10)
    maxW = mround(opts.maxBeatWindow / dt)
    tOn, tEnd, tMs, tSeg = onset_and_end(f, t, g, dt, iPk, maxW, opts)
    beatType = np.array(["unpaced"] * nPk, dtype=object)
    pOfBeat = np.full(nPk, -1)  # eliciting pulse (index into PT; -1 = none)
    jAll = np.full(nPk, -1)  # 'peak': pulse of every peak (also the less prominent ones)
    amb = np.zeros(nPk, bool)  # assignment ambiguous (option ambiguityWindow)
    if PT.size:
        beatType[:] = "extra"
        if legacy:  # peak: last pulse minStimToPeak ... maxLat before the peak
            j = np.full(nPk, -1)
            for k in range(nPk):
                jj = np.searchsorted(PT, tPk[k] - opts.minStimToPeak, side="right") - 1  # last PT <= tPk - minStimToPeak
                if jj >= 0 and tPk[k] - PT[jj] <= maxLat:
                    j[k] = jj
            for jj in np.unique(j[j >= 0]):
                ks = np.flatnonzero(j == jj)
                pOfBeat[ks[np.argmax(promPk[ks])]] = jj  # several peaks after one pulse: the most prominent one
            jAll = j
        else:
            pOfBeat, amb, tOn = gate_assign(tOn, tMs, tPk, promPk, PT, PX, opts, maxLat, tSeg)
            jAll = pOfBeat
        beatType[pOfBeat >= 0] = "stimulated"
    hasB = pOfBeat >= 0
    tStimOfBeat = np.full(nPk, np.nan)
    tStimOfBeat[hasB] = PT[pOfBeat[hasB]]
    elicitedX = np.zeros(nPk, bool)
    elicitedX[hasB] = PX[pOfBeat[hasB]]
    # regular pulses: followed by a contraction (captured), by a certain one, or within a contraction elicited by
    # another pulse (from its eliciting pulse to 90 % relaxation: refractory, not captured)
    regIdx = np.cumsum(~PX) - 1  # index into ST of every regular pulse (-1 for extra pulses)
    regIdx[PX] = -1
    pUsed = np.zeros(PT.size, bool)
    pUsedCertain = np.zeros(PT.size, bool)
    pUsed[pOfBeat[hasB]] = True
    for jj in np.unique(pOfBeat[hasB]):  # several peaks after one pulse ('peak'): any certain one
        pUsedCertain[jj] = bool(np.any(certain[jAll == jj]))  # captured in the 'specific' mode, too
    stimCaptured = pUsed[~PX]
    stimCapturedCertain = pUsedCertain[~PX]
    wStart = tStimOfBeat.copy()
    wStart[np.isnan(wStart)] = tOn[np.isnan(wStart)]
    owner, during = pulse_owners(PT, pOfBeat, wStart, tEnd, tStimOfBeat, tOn, opts)
    stimDuring = during[~PX]
    jStimOfBeat = np.full(nPk, -1)  # regular pulse of the contraction (index into ST)
    jStimOfBeat[hasB] = regIdx[pOfBeat[hasB]]
    # contractions after a stimulation pause (stimulus interval >= 2.5 s and >= 1.5 x the interval before; without a
    # previous stimulus in the data: time since the start of the data; without the interval before: median interval):
    # F_dia is searched only from opts.pauseDiastoleWindow before the stimulus, not during the pause (drift, rocker
    # movement until shortly before the stimulus, e.g. post-rest potentiation protocols)
    afterPause = np.zeros(nPk, bool)
    for k in np.flatnonzero(jStimOfBeat >= 0):
        jj = jStimOfBeat[k]
        prevInt = ST[jj] - ST[jj - 1] if jj >= 1 else ST[jj] - t[0]
        before = ST[jj - 1] - ST[jj - 2] if jj >= 2 else CL
        afterPause[k] = prevInt >= np.fmax(opts.pauseMinInterval, opts.pauseIntervalRatio * before)

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
    useMedian = opts.diastolicLevel != "minimum"  # diastolic level: median before the pulse (2026-10-10)
    xRaw = np.asarray(S.force[row], dtype=float)  # unfiltered signal (after spike removal / rocker filter)
    tRaw = np.asarray(S.t, dtype=float).ravel()
    for q in range(n):
        k = sel[q]
        i = iPk[k]
        a = iPk[k - 1] if k > 0 else 0
        b = iPk[k + 1] if k < nPk - 1 else N - 1
        a = max(a, i - maxW, 0)
        b = min(b, i + maxW, N - 1)
        if afterPause[k]:
            a = max(a, int(np.searchsorted(t, tStimOfBeat[k] - opts.pauseDiastoleWindow, side="left")))
        seg = f[a:i + 1][::-1]  # f(i:-1:a): last minimum before the peak (flat diastole: the one next to the upstroke)
        ia = i - int(np.argmin(seg))
        Fdia = f[ia]
        ib = i + int(np.argmin(f[i:b + 1]))
        Fpost = f[ib]
        Fpk = f[i]
        iu = ia  # start of the search for the upstroke crossings
        # diastolic level (2026-10-10): median of the unfiltered signal diastoleWindowStart ... diastoleWindowEnd before
        # the eliciting pulse (default); without pulse, or a median at or above the peak: the minimum before the peak
        if useMedian and not math.isnan(tStimOfBeat[k]):
            w0 = int(np.searchsorted(tRaw, tStimOfBeat[k] - opts.diastoleWindowStart - 1e-9, side="left"))
            w1 = int(np.searchsorted(tRaw, tStimOfBeat[k] - opts.diastoleWindowEnd + 1e-9, side="left")) - 1
            if 0 <= w0 <= w1 < xRaw.size:
                Fm = float(np.nanmedian(xRaw[w0:w1 + 1]))
                if Fm < Fpk:
                    Fdia = Fm
                    # upstroke crossings: from the window before the pulse on (a median below the filtered minimum)
                    iu = min(ia, max(a, int(np.searchsorted(t, tStimOfBeat[k] - opts.diastoleWindowStart,
                                                            side="left"))))
        A = Fpk - Fdia
        if k > 0:
            V[q, ix["peakToPeakInterval"]] = tPk[k] - tPk[k - 1]
        rockerMoving[q] = rockerOn[ia:ib + 1].any()  # replaced below by F_dia ... 90 % relaxation, if available
        # no upstroke within the data (contraction starts before the loaded data), or a rounding bump of a held value
        # (e.g. chamber out: plateau above the diastolic level, A ~ 1e-13 uN)
        if not A > 1e-9 * max(1.0, abs(Fdia)) or ia == 0:
            continue
        up10 = _cross_up(f, t, dt, iu, i, Fdia + 0.1 * A)
        up50 = _cross_up(f, t, dt, iu, i, Fdia + 0.5 * A)
        up90 = _cross_up(f, t, dt, iu, i, Fdia + 0.9 * A)
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
            below = np.flatnonzero(f[iu:i] < Fdia + 0.1 * A)
            if below.size:
                i10 = below[-1] + iu + 1  # first sample above the 10 % level
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
    uncertain = ~certain[sel]
    included = ~np.isnan(V[:, 0])
    if opts.beats == "stimulated":
        included &= beatSel == "stimulated"
    if opts.rocker == "stopped":
        included &= ~rockerMoving
    if opts.rocker == "moving":
        included &= rockerMoving
    B = pd.DataFrame({"channel": np.full(n, channel, dtype=float), "contraction": np.arange(1, n + 1, dtype=float),
                      "t_peak": tPeakSel, "beatType": pd.Series(list(beatSel), dtype=object), "t_stim": tStim,
                      "stimToPeak": tPeakSel - tStim, "rockerMoving": rockerMoving, "included": included,
                      "uncertain": uncertain})
    # eliciting pulse and the pulses that did not elicit a contraction (2026-10-10, see pulse_properties / pulse_text)
    fs = float(S.samplingRate) if "samplingRate" in S else 2.0 / dt  # pulse ID = raw sample number
    snapMs = float(opts.offsetSnap) * 1000  # programmed offsets (log file) used within this time (ms)
    pDur, _, pNom = pulse_properties(S, stimCh, PT, PX, snapMs)
    pSel = pOfBeat[sel]
    hasP = pSel >= 0
    sv = np.full((n, 5), np.nan)  # pulse ID, current, charge, pause, decharge
    if hasP.any():
        sv[hasP, 0] = mround(PT[pSel[hasP]] * fs)
        sv[hasP, 1] = PC[pSel[hasP]]
        sv[hasP, 2:5] = pDur[pSel[hasP], :]
    preTxt, postTxt = pulse_text(sel, owner, PT, PX, PC, pDur, pNom, pOfBeat, tOn, n, snapMs, int(opts.pulseTextMax))
    tOnSel = tOn[sel]
    B["t_onset"] = tOnSel
    B["stimToOnset"] = tOnSel - tStim
    B["stimPulse"] = sv[:, 0]
    B["stimCurrent"] = sv[:, 1]
    B["stimChargeDuration"] = sv[:, 2]
    B["stimPauseDuration"] = sv[:, 3]
    B["stimDechargeDuration"] = sv[:, 4]
    B["elicitedByExtraPulse"] = elicitedX[sel]
    B["stimAmbiguous"] = amb[sel]
    B["prePulses"] = pd.Series(preTxt, dtype=object)
    B["postPulses"] = pd.Series(postTxt, dtype=object)
    for k, nm in enumerate(names):
        B[nm] = V[:, k]
    B["prominence"] = promSel
    units = dict(UNITS_FIRST)
    units.update(UNITS_STIM)
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
    C.thresholdArtifacts = nArt
    C.noContractions = bool(noBeats)
    C.noiseLevel = noiseLvl
    C.noiseMedian = noiseMed
    C.stimCapturedCertain = stimCapturedCertain
    C.stimTimes = ST
    C.stimCaptured = stimCaptured
    C.stimDuringContraction = stimDuring  # regular pulse within a contraction elicited by another pulse (refractory)
    C.extraTimes = PT[PX]  # extra pulses (status channel bit 16)
    C.extraElicited = pUsed[PX]  # extra pulse elicited a contraction
    C.onsetTimes = tOn  # contraction onset of every peak (iPeaks)
    C.stimAssignment = "peak" if legacy else "onset"
    C.pulses = None  # pulse table of the range (option pulseTable; myodish_analysis: info["pulses"])
    if opts.get("pulseTable", True):
        C.pulses = pulse_table(channel, PT, PX, PC, PR, pDur, fs, range_, pOfBeat, owner, during, tStimOfBeat, tOn,
                               tEnd, tPk, sel, pNom, snapMs)
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
# stimulus assignment, pulses (2026-10-10)
def _lower_bound(x, v):
    """first index (0-based) of the sorted array x with x[i] >= v (x.size if none)"""
    return int(np.searchsorted(x, v, side="left"))


def onset_and_end(f, t, g, dt, iPk, maxW, opts=None):
    """onset of every contraction: the tangent at the maximum dF/dt between the diastolic minimum (last minimum before
    the peak, as for the parameters) and the peak crosses the diastolic level (limited to [t(minimum), t(max. dF/dt)]);
    NaN without upstroke in the data. tMs: time of the maximum dF/dt. End: opts.contractionEnd (90 %) relaxation
    (first crossing after the peak, as TTR90); without relaxation in the window: time of the minimum after the peak. tSeg: onsets of the other
    rise phases of the upstroke (list of arrays, see _phase_onsets): the upstroke can rise in phases (rocker movement,
    an undetected event fused with the contraction, e.g. a spontaneous beat just before the stimulus)"""
    if opts is None:
        opts = _options()
    endFrac = (100 - float(opts.contractionEnd)) / 100
    N = f.size
    nPk = iPk.size
    tOn = np.full(nPk, np.nan)
    tEnd = np.full(nPk, np.nan)
    tMs = np.full(nPk, np.nan)
    tSeg = [np.zeros(0)] * nPk
    for k in range(nPk):
        i = int(iPk[k])
        a = int(iPk[k - 1]) if k > 0 else 0
        b = int(iPk[k + 1]) if k < nPk - 1 else N - 1
        a = max(a, i - maxW, 0)
        b = min(b, i + maxW, N - 1)
        ia = i - int(np.argmin(f[a:i + 1][::-1]))
        Fdia = f[ia]
        if 0 < ia < i:
            im = ia + int(np.argmax(g[ia:i + 1]))
            gm = g[im]
            if gm > 0:
                tOn[k] = min(max(t[im] - (f[im] - Fdia) / gm, t[ia]), t[im])
                tMs[k] = t[im]
                tSeg[k] = _phase_onsets(f, t, g, ia, i, im, float(opts.risePhaseLevel))
        ib = i + int(np.argmin(f[i:b + 1]))
        Fpost = f[ib]
        if ib > i and f[i] > Fpost:
            lvl = Fpost + endFrac * (f[i] - Fpost)
            below = np.flatnonzero(f[i + 1:ib + 1] < lvl)
            if below.size == 0:
                tEnd[k] = t[ib]
            else:
                j = int(below[0]) + i + 1
                tEnd[k] = t[j - 1] + (f[j - 1] - lvl) / (f[j - 1] - f[j]) * dt
        else:
            tEnd[k] = t[i]
    return tOn, tEnd, tMs, tSeg


def _phase_onsets(f, t, g, ia, i, im, level=0.25):
    """onsets of the other rise phases of the upstroke between the diastolic minimum ia and the peak i (im = maximum
    dF/dt), in time order: every local maximum of dF/dt >= level (opts.risePhaseLevel, 25 %) x the maximum; foot of a phase = the bottom of the
    dip of F before it (dF/dt <= 0 in between) or the shoulder (minimum of dF/dt) after the previous phase, the
    diastolic minimum for the first phase; onset = the tangent at the local maximum of dF/dt crossing the level of
    the foot (limited to [t(foot), t(maximum)])"""
    y = g[ia:i + 1]
    x = f[ia:i + 1]
    if y.size < 3:
        return np.zeros(0)
    pk = np.flatnonzero((y[1:-1] > y[:-2]) & (y[1:-1] >= y[2:]) & (y[1:-1] >= level * g[im])) + 1
    allPk = np.union1d(pk, [im - ia])
    out = []
    for p in pk:
        if p == im - ia:
            continue
        prev = allPk[allPk < p]
        if prev.size == 0:
            foot = 0
        else:
            seg = y[prev[-1]:p + 1]
            if np.min(seg) <= 0:
                foot = prev[-1] + int(np.flatnonzero(seg <= 0)[-1])  # bottom of the dip of F
            else:
                foot = prev[-1] + int(np.argmin(seg))  # shoulder
        out.append(min(max(t[ia + p] - (x[p] - x[foot]) / y[p], t[ia + foot]), t[ia + p]))
    return np.array(out, float)


def gate_assign(tOn, tMs, tPk, promPk, PT, PX, opts, maxLat, tSeg=None):
    """Onset gate: a pulse (regular or extra) can only have elicited a contraction if it lies from onset - gateMax to
    onset + gateTolerance. Contractions in the order of their prominence (the most prominent one first), each pulse
    elicits at most one contraction. Several candidates: see _choose (before the onset before after it, regular before
    extra pulses, the earliest within gateCore before the onset, otherwise the latest). Ambiguous: a pulse of the other
    kind (regular / extra) within ambiguityWindow of the chosen one, or one of the other kind would be chosen if the
    onset were gateTolerance earlier or later.
    No pulse in the gate: 1. the gates of the other rise phases of the upstroke (tSeg, earliest first), the first one
    with a pulse; its onset becomes the onset of the contraction (ambiguous if the upstroke started more than
    gateTolerance before it); 2. the eliciting pulse
    must precede the steepest upstroke - a pulse after the gate up to 5 ms before the maximum dF/dt (onset estimated
    too early, e.g. rocker artifacts) is taken (regular first, the earliest), marked ambiguous. Contractions
    without onset (no upstroke in the data): the last unused pulse minStimToPeak ... maxLat before the peak.
    Returns p (index into PT, -1 = none), amb and the onsets (tOn, segment onset where used)."""
    nPk = tOn.size
    tOn = np.array(tOn, float)
    p = np.full(nPk, -1)
    amb = np.zeros(nPk, bool)
    used = np.zeros(PT.size, bool)
    gMax = float(opts.gateMax); gCore = float(opts.gateCore); gTol = float(opts.gateTolerance)
    aWin = float(opts.ambiguityWindow)

    def gate(t0):
        a = _lower_bound(PT, t0 - gMax - 1e-9)
        b = _lower_bound(PT, t0 + gTol + 1e-9) - 1
        c = np.arange(a, b + 1)
        return c[~used[c]], b

    for k in np.argsort(-np.asarray(promPk, float), kind="stable"):
        if math.isnan(tOn[k]):
            idx = np.flatnonzero((PT <= tPk[k] - opts.minStimToPeak) & ~used)
            if idx.size and tPk[k] - PT[idx[-1]] <= maxLat:
                p[k] = idx[-1]
                used[idx[-1]] = True
            continue
        cand, b = gate(tOn[k])
        forced = False
        if cand.size == 0 and tSeg is not None and np.size(tSeg[k]):
            first = min(tOn[k], float(np.min(tSeg[k])))  # start of the upstroke
            for ts in tSeg[k]:
                c2, _ = gate(ts)
                if c2.size:
                    cand = c2
                    tOn[k] = ts
                    forced = ts > first + gTol + 1e-9  # the upstroke started before (fused event): ambiguous
                    break
        if cand.size == 0:
            c2 = _lower_bound(PT, tMs[k] - float(opts.steepRiseMargin) + 1e-9) - 1
            cand = np.arange(b + 1, c2 + 1)
            cand = cand[~used[cand]]
            if cand.size == 0:
                continue
            r = cand[~PX[cand]]
            j = int(r[0]) if r.size else int(cand[0])
            p[k] = j
            used[j] = True
            amb[k] = True
            continue
        j = _choose(cand, PT, PX, tOn[k], gCore)
        o = cand[cand != j]
        oth = o[PX[o] != PX[j]]  # candidates of the other kind (regular / extra)
        # ambiguous: a pulse of the other kind (regular / extra) within ambiguityWindow, or chosen if the onset were
        # gateTolerance earlier or later (tolerance of the onset estimate: gate and choice)
        amb[k] = bool(forced or np.any(np.abs(PT[oth] - PT[j]) <= aWin + 1e-9))
        for t1 in (tOn[k] - gTol, tOn[k] + gTol):
            c1, _ = gate(t1)
            if not amb[k] and c1.size and PX[_choose(c1, PT, PX, t1, gCore)] != PX[j]:
                amb[k] = True
        p[k] = j
        used[j] = True
    return p, amb, tOn


def _choose(cand, PT, PX, t0, gCore):
    """eliciting pulse among the candidates of a gate (onset t0): pulses before the onset before pulses after it (onset
    tolerance); among them regular pulses before extra pulses (an extra pulse after a regular one falls into its
    refractory period, e.g. CCM; a sub-threshold pre-pulse lies further before the onset than the regular pulse); of
    one kind the earliest within gateCore before the onset, otherwise the latest one. After the onset: the earliest
    (regular first)."""
    B = cand[PT[cand] <= t0 + 1e-9]
    if B.size:
        for q in (B[~PX[B]], B[PX[B]]):
            if q.size:
                c = q[PT[q] >= t0 - gCore - 1e-9]
                return int(c[0]) if c.size else int(q[-1])
    r = cand[~PX[cand]]
    return int(r[0]) if r.size else int(cand[0])


def pulse_owners(PT, pOfBeat, wStart, tEnd, tStim, tOn, opts):
    """contraction of every pulse: owner[i] = [contraction index (0-based, -1 = none), role], role 3 = eliciting pulse,
    2 = post-pulse (within a contraction, from its eliciting pulse (extra beat: onset) to 90 % relaxation; the one that
    started last), 1 = pre-pulse (before the eliciting pulse (onset) of the next contraction, at most prePulseWindow),
    0 = none. during: within a contraction elicited by another pulse (not the eliciting pulse)"""
    nP = PT.size
    owner = np.zeros((nP, 2), dtype=int)
    owner[:, 0] = -1
    during = np.zeros(nP, bool)
    ok = np.flatnonzero(~np.isnan(wStart))
    o = np.argsort(wStart[ok], kind="stable")
    ws = wStart[ok][o]
    kk = ok[o]
    we = tEnd[kk].copy()
    we[np.isnan(we)] = ws[np.isnan(we)]
    isEl = np.zeros(nP, bool)
    for k in np.flatnonzero(pOfBeat >= 0):
        owner[pOfBeat[k]] = [k, 3]
        isEl[pOfBeat[k]] = True
    pre = float(opts.prePulseWindow)
    for i in np.flatnonzero(~isEl):
        tp = PT[i]
        j = _lower_bound(ws, tp + 1e-12) - 1  # last window that starts at or before the pulse
        post = -1
        for jj in (j, j - 1):
            if jj >= 0 and tp <= we[jj] + 1e-9:
                post = int(kk[jj])
                break
        if post >= 0:
            owner[i] = [post, 2]
            during[i] = True
            continue
        if j + 1 < kk.size:
            k = int(kk[j + 1])
            ref = tStim[k]
            if math.isnan(ref):
                ref = tOn[k]
            if ref > tp and ref - tp <= pre + 1e-9:
                owner[i] = [k, 1]
    return owner, during


def pulse_properties(S, c, PT, PX, snapMs=5.0):
    """pulse durations (us; charge, pause, decharge: last 'chargeDuration' / 'pauseDuration' / 'dechargeDuration' entry
    of the log file at or before the pulse; regular pulses: log channel c (and 0); extra pulse #k: log channel 10k + c
    if such entries exist (software 2022), otherwise the values of channel c (software 2026)), number k of every extra
    pulse and its programmed offset to the regular pulse (dNom, ms: the offset of the 'Sequence' entries nearest to the
    measured one, if within 5 ms; NaN otherwise). Measured offset: to the nearest regular pulse of the channel."""
    n = PT.size
    dur = np.full((n, 3), np.nan)
    kOf = np.zeros(n, dtype=int)
    dNom = np.full(n, np.nan)
    if n == 0:
        return dur, kOf, dNom
    iX = np.flatnonzero(PX)
    kOf[iX] = 1
    X = np.asarray(S.get("extraPulseLog", np.zeros((0, 5))), float).reshape(-1, 5)
    TR = PT[~PX]
    if iX.size and X.size and TR.size:
        Xc = X[X[:, 1] == c]
        if Xc.size:
            Xc = Xc[np.lexsort((Xc[:, 4], Xc[:, 0]))]
            for i in iX:
                jr = _lower_bound(TR, PT[i])
                cand = np.array([q for q in (jr - 1, jr) if 0 <= q < TR.size])
                q = int(np.argmin(np.abs(TR[cand] - PT[i])))
                dm = (PT[i] - TR[cand[q]]) * 1000
                L = _lower_bound(Xc[:, 0], PT[i] + 1e-9) - 1  # latest entry at or before the pulse: its line = the set
                if L < 0:
                    continue
                R = Xc[(Xc[:, 4] == Xc[L, 4]) & (Xc[:, 2] > 0)]
                if R.size == 0:
                    continue
                d = np.abs(R[:, 3] - dm)
                q = int(np.argmin(d))
                kOf[i] = int(R[q, 2])
                if d[q] <= snapMs:
                    dNom[i] = R[q, 3]
    P = np.asarray(S.get("pulseSettingsLog", np.zeros((0, 4))), float).reshape(-1, 4)
    if P.size == 0:
        return dur, kOf, dNom
    for code in (1, 2, 3):
        dur[:, code - 1] = _log_value(P[np.isin(P[:, 1], [0, c]) & (P[:, 2] == code)], PT)
        for k in np.unique(kOf[kOf > 0]):
            Pk = P[(P[:, 1] == 10 * k + c) & (P[:, 2] == code)]
            if Pk.size == 0:
                continue
            ii = np.flatnonzero(kOf == k)
            v = _log_value(Pk, PT[ii])
            keep = ~np.isnan(v)
            dur[ii[keep], code - 1] = v[keep]
    return dur, kOf, dNom


def _log_value(P, t):
    """value of the last entry (rows [time ch code value], log order) at or before the times t (NaN before the first)"""
    t = np.asarray(t, float)
    v = np.full(t.shape, np.nan)
    if P.size == 0:
        return v
    o = np.argsort(P[:, 0], kind="stable")  # entries at the same time in log order
    te = P[o, 0]
    x = P[o, 3]
    j = np.searchsorted(te, t + 1e-9, side="left") - 1
    v[j >= 0] = x[j[j >= 0]]
    return v


def _rel_pulse_time(i, k, PT, PX, pNom, pOfBeat, tOn, snapMs=5.0):
    """time of pulse i relative to the eliciting pulse of contraction k (extra beat: its onset), ms; the programmed
    offset (log file) if the measured one is within 5 ms of it (extra pulse relative to the regular pulse, or vice
    versa)"""
    e = pOfBeat[k]
    ref = PT[e] if e >= 0 else tOn[k]
    tms = mround((PT[i] - ref) * 10000) / 10
    if e >= 0 and not PX[e] and PX[i] and not math.isnan(pNom[i]) and abs(tms - pNom[i]) <= snapMs:
        tms = pNom[i]
    elif e >= 0 and PX[e] and not PX[i] and not math.isnan(pNom[e]) and abs(tms + pNom[e]) <= snapMs:
        tms = -pNom[e]
    return float(tms)


def _num_text(x):
    x = float(x)
    return "NaN" if math.isnan(x) else "%.10g" % (x + 0.0)


def pulse_text(sel, owner, PT, PX, PC, pDur, pNom, pOfBeat, tOn, n, snapMs=5.0, nMax=10):
    """pre- and post-pulses of the selected contractions: 't<ms>|<mA>|<charge us>|<pause us>|<decharge us>', several
    joined by '&' (sorted by time; at most 10, the ones nearest to the eliciting pulse, then '&+<number of the
    others>'). The text starts with 't' (a cell starting with '-' or '+' would be read as a formula by spreadsheet
    programs)"""
    preTxt = [""] * n
    postTxt = [""] * n
    if n == 0 or PT.size == 0:
        return preTxt, postTxt
    qOf = np.full(max(tOn.size, int(np.max(sel)) + 1), -1)
    qOf[sel] = np.arange(n)
    for role in (1, 2):
        ii = np.flatnonzero((owner[:, 1] == role) & (owner[:, 0] >= 0))
        if ii.size == 0:
            continue
        qq = qOf[owner[ii, 0]]
        keep = qq >= 0
        ii = ii[keep]
        qq = qq[keep]
        for q in np.unique(qq):
            lst = np.sort(ii[qq == q])
            k = sel[q]
            nMore = max(0, lst.size - nMax)
            lst = lst[lst.size - min(nMax, lst.size):] if role == 1 else lst[:nMax]
            tok = ["t" + _num_text(_rel_pulse_time(i, k, PT, PX, pNom, pOfBeat, tOn, snapMs)) + "|" + _num_text(PC[i]) + "|"
                   + _num_text(pDur[i, 0]) + "|" + _num_text(pDur[i, 1]) + "|" + _num_text(pDur[i, 2]) for i in lst]
            txt = "&".join(tok)
            if nMore > 0:
                txt = f"{txt}&+{nMore}"  # never at the start (spreadsheet formulas)
            if role == 1:
                preTxt[q] = txt
            else:
                postTxt[q] = txt
    return preTxt, postTxt


def pulse_table(channel, PT, PX, PC, PR, pDur, fs, range_, pOfBeat, owner, during, tStim, tOn, tEnd, tPk, sel, pNom,
                snapMs=5.0):
    """one row per pulse of the range: pulse (ID = raw sample number in the file, from 0), channel, t (s), extra
    (status channel bit 16), current_mA, currentReached, chargeDuration_us, pauseDuration_us, dechargeDuration_us,
    outcome ('elicited' / 'duringContraction' / 'noResponse'), role ('eliciting' / 'pre' / 'post' / ''), contraction
    (number of the contraction it belongs to, NaN if outside the range), t_peak of that contraction, tRel_ms (pre /
    post: time relative to its eliciting pulse, as in prePulses / postPulses), couplingInterval_s (to the previous
    eliciting pulse), sinceOnset_s (to the onset of the latest contraction), phase (sinceOnset / onset ... 90 %
    relaxation of that contraction)"""
    i = np.flatnonzero((PT >= range_[0]) & (PT <= range_[1]))
    n = i.size
    nPk = tOn.size
    qOf = np.full(max(nPk, 1), -1)
    qOf[sel] = np.arange(sel.size)
    roles = ["", "pre", "post", "eliciting"]
    outcome = ["noResponse"] * n
    role = [""] * n
    contraction = np.full(n, np.nan)
    tPeakOf = np.full(n, np.nan)
    tRel = np.full(n, np.nan)
    elT = np.sort(tStim[~np.isnan(tStim)])
    onV = np.flatnonzero(~np.isnan(tOn))
    o = np.argsort(tOn[onV], kind="stable")
    onT = tOn[onV][o]
    onK = onV[o]
    coupling = np.full(n, np.nan)
    since = np.full(n, np.nan)
    phase = np.full(n, np.nan)
    for m in range(n):
        ip = i[m]
        k, r = int(owner[ip, 0]), int(owner[ip, 1])
        role[m] = roles[r]
        if r == 3:
            outcome[m] = "elicited"
        elif during[ip]:
            outcome[m] = "duringContraction"
        if k >= 0:
            tPeakOf[m] = tPk[k]
            if qOf[k] >= 0:
                contraction[m] = qOf[k] + 1
            tRel[m] = 0.0 if r == 3 else _rel_pulse_time(ip, k, PT, PX, pNom, pOfBeat, tOn, snapMs)
        j = _lower_bound(elT, PT[ip] - 1e-9) - 1  # previous eliciting pulse (strictly before)
        if j >= 0:
            coupling[m] = PT[ip] - elT[j]
        j = _lower_bound(onT, PT[ip] + 1e-9) - 1  # latest onset at or before the pulse
        if j >= 0:
            since[m] = PT[ip] - onT[j]
            kk = onK[j]
            d = tEnd[kk] - tOn[kk]
            if d > 0:
                phase[m] = since[m] / d
    P = pd.DataFrame({"pulse": mround(PT[i] * fs) if n else np.zeros(0), "channel": np.full(n, channel, dtype=float),
                      "t": PT[i], "extra": PX[i], "current_mA": PC[i], "currentReached": PR[i],
                      "chargeDuration_us": pDur[i, 0], "pauseDuration_us": pDur[i, 1],
                      "dechargeDuration_us": pDur[i, 2], "outcome": pd.Series(outcome, dtype=object),
                      "role": pd.Series(role, dtype=object), "contraction": contraction, "t_peak": tPeakOf,
                      "tRel_ms": tRel, "couplingInterval_s": coupling, "sinceOnset_s": since, "phase": phase})
    P.attrs["units"] = dict(PULSE_UNITS)
    return P


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


def artifact_gap_threshold(tc, prom, thr, typical, ST, rocker, CL, opts=None):
    """paced channels: raise the auto threshold into a clear gap above a cluster of small peaks that are not locked
    to the stimuli and occur while the rocker moves (rocker artifacts); peaks of that cluster locked to a stimulus
    stay (see artifactGapThreshold in mda_analyzeChannel.m). Returns thr, keepLow (bool per candidate), nLow."""
    if opts is None:
        opts = _options()
    keepLow = np.zeros(prom.size, bool)
    k = np.flatnonzero(prom >= thr)
    if k.size < opts.artifactMinCandidates or math.isnan(typical) or ST.size == 0:
        return thr, keepLow, 0
    o = np.argsort(-prom[k], kind="stable")
    k = k[o]
    p = prom[k]
    r = p[:-1] / p[1:]
    r[(p[:-1] > typical) | (p[1:] > opts.artifactMaxRel * typical)] = 0  # gap below the bulk, small lower cluster
    g = int(np.argmax(r))
    if r[g] < opts.artifactGapRatio:
        return thr, keepLow, 0
    hi, lo = k[:g + 1], k[g + 1:]
    lat_hi = _stim_latency(tc[hi], ST)
    if np.all(np.isnan(lat_hi)):
        return thr, keepLow, 0
    lat_hi = float(np.nanmedian(lat_hi))
    with np.errstate(invalid="ignore"):
        locked = np.abs(_stim_latency(tc[lo], ST) - lat_hi) <= opts.lockWindow
    w2 = 2 * opts.lockWindow
    chance = w2 / max(CL, w2)  # fraction locked by chance (window 2 x lockWindow per cycle)
    if (np.count_nonzero(~locked) < opts.artifactMinPeaks or locked.mean() > min(opts.chanceMax, chance + opts.chanceMargin)
            or rocker[lo].mean() < opts.artifactRockerFraction):
        return thr, keepLow, 0
    thr = math.sqrt(p[g] * p[g + 1])
    keepLow[lo[locked]] = True
    return float(thr), keepLow, int(np.count_nonzero(~locked))


def pre_stimulus_noise(t, f, ST, opts=None):
    """rocker / noise level: rise (maximum minus the running minimum) of the filtered signal in the window before
    every stimulus that follows an interval >= 0.9 s (window min(0.5 s, 0.4 x interval), where no contraction is
    expected; a relaxation that is not finished only falls and does not count). N = 90th percentile, n = number of
    windows, Nm = median (robust against contractions that reach into some of the windows; see preStimulusNoise in
    mda_analyzeChannel.m). TS 2026-10-09"""
    if opts is None:
        opts = _options()
    t = np.asarray(t, float)
    f = np.asarray(f, float)
    r = np.full(ST.size, np.nan)
    for j in range(1, ST.size):
        ci = ST[j] - ST[j - 1]
        if ci < opts.noiseMinInterval:
            continue
        i1 = int(np.searchsorted(t, ST[j] - min(opts.noiseWindow, opts.noiseWindowRel * ci), side="left"))  # first t >= x
        i2 = int(np.searchsorted(t, ST[j], side="left")) - 1  # last sample before the stimulus
        if i2 - i1 < 2:
            continue
        s = f[i1:i2 + 1]
        r[j] = float(np.max(s - np.minimum.accumulate(s)))
    return _prctile(r, opts.noisePercentile), int(np.count_nonzero(~np.isnan(r))), _prctile(r, 50)


def rocker_noise_rule(tc, prom, thr, keepLow, typical, ST, N, rocker, tOn, fR, STall=None, opts=None):
    """peaks of the rocker movement / noise of paced channels while the rocker moves (see rockerNoiseRule in
    mda_analyzeChannel.m). Latency of the contractions: centre of the 0.2-s window with the most latencies of the
    largest peaks (as many as stimuli); peaks within +-0.1 s of it are locked. (< 50 % of the largest peaks locked
    and (typical <= 50 uN or (typical <= 2 x N and the peaks at the rhythm of the rocker))) or else rockerOnly (N
    unknown, high rates: >= 60 % of the peak intervals 1 or 1/2 rocker period +-10 %, the median no 1:1 or 2:1
    multiple of the stimulus interval +-5 %, < max(50 %, chance + 20 %) locked within +-min(0.1 s, 0.2 x stimulus
    interval)): all peaks < 3 x max(typical, N) (rockerOnly: median of the largest peaks, only while the rocker
    moves) are dropped, except locked peaks >= max(1.5 x N, N + 50) if there are >= max(3, 5 % of the stimuli) of
    them and more than by chance; none = no peak left. Otherwise peaks not locked
    with a prominence < min(1.5 x N, 0.5 x typical) are dropped (< min(1.5 x N, typical) if they are at the rhythm
    of the rocker). Returns drop (bool per candidate), none. TS 2026-10-09 (STall: all pulses incl. extra pulses for
    the latency, 2026-10-10)"""
    if STall is None:
        STall = ST
    if opts is None:
        opts = _options()
    tc = np.asarray(tc, float)
    above = (prom >= thr) | keepLow
    drop = np.zeros(prom.size, bool)
    k = np.flatnonzero(above)
    if k.size < 3:
        return drop, False
    o = np.argsort(-prom[k], kind="stable")
    top = k[o[:min(k.size, ST.size)]]
    lat = _stim_latency(tc, STall)
    if np.all(np.isnan(lat[top])):
        return drop, False
    locked = latency_lock(lat, top, opts.lockWindow)
    w2 = 2 * opts.lockWindow
    chance = w2 / max(float(np.median(np.diff(ST))), w2)  # fraction of the time within +-lockWindow of the latency
    noise = bool(locked[top].mean() < opts.noiseLockedMax and (typical <= opts.noiseAbsMax or (
        typical <= opts.noiseRelMax * N and _rocker_rhythm(tc, above & rocker, tOn, fR, opts.rhythmMinPerCycle, opts))))
    # N unknown (high rates, no intervals >= 0.9 s): peaks at the rhythm of the rocker, not of the stimuli. +-0.1 s
    # covers most of a short stimulus interval: locking here within +-hw, hw = min(0.1 s, 0.2 x median interval)
    rockerOnly = False
    if not noise and math.isnan(N) and not math.isnan(fR):
        d = np.diff(tc[above & rocker]) * fR  # peak intervals in rocker periods
        if d.size >= opts.rockerOnlyMinIntervals:
            atR = (np.abs(d - 1) <= opts.rockerOnlyTolerance) | (np.abs(d - 0.5) <= opts.rockerOnlyTolerance / 2)
            CLm = float(np.median(np.diff(ST)))
            ipi = float(np.median(d)) / fR
            k2 = mround(ipi / CLm)  # 1:1 or 2:1 capture at the rocker period: undecidable
            if atR.mean() >= opts.rockerOnlyFraction and not (
                    1 <= k2 <= 2 and abs(ipi - k2 * CLm) <= opts.captureTolerance * ipi):
                hw = min(opts.lockWindow, opts.lockWindowRel * CLm)
                lockedR = latency_lock(lat, top, hw)
                chanceR = 2 * hw / max(CLm, 2 * hw)
                if lockedR[top].mean() < max(opts.noiseLockedMax, chanceR + opts.chanceMargin):
                    rockerOnly = True
                    locked = lockedR
                    chance = chanceR
    if noise or rockerOnly:
        Nn = typical if math.isnan(N) else N
        big = above & (prom >= max(opts.keepNoiseRel * Nn, Nn + opts.keepNoiseAbs))  # clearly above the noise level
        lk = big & locked  # contractions of some stimuli (partial capture)
        nlk = int(np.count_nonzero(lk))
        if (nlk < max(opts.keepMinPeaks, opts.keepMinFraction * ST.size)
                or nlk <= min(opts.chanceMax, chance + opts.chanceMargin) * np.count_nonzero(big)):
            lk[:] = False  # not more than by chance
        L = typical if math.isnan(N) else (N if math.isnan(typical) else max(typical, N))
        if rockerOnly:
            L = float(np.median(prom[top]))  # size of the rocker peaks (typical: of more peaks than exist)
        drop = above & (prom < opts.dropRel * L) & ~lk
        if rockerOnly:
            drop &= rocker  # peaks while the rocker is at rest are no rocker peaks
        return drop, not bool(np.any(above & ~drop))
    if not math.isnan(N):
        lim = min(opts.smallNoiseRel * N, opts.smallTypicalRel * typical)
        if _rocker_rhythm(tc, above & ~locked & rocker, tOn, fR, opts.smallRhythmMinPerCycle, opts):
            lim = min(opts.smallNoiseRel * N, opts.smallRhythmTypicalRel * typical)
        drop = above & ~locked & (prom < lim)
    return drop, False


def latency_lock(lat, top, hw):
    """peaks locked to the stimuli: latency (time since the previous stimulus) within +-hw of the centre of the window
    of 2 x hw that contains the most latencies of the reference peaks top (indices, e.g. the largest peaks); see
    latencyLock in mda_analyzeChannel.m"""
    lat = np.asarray(lat, float)
    locked = np.zeros(lat.size, bool)
    lv = np.sort(lat[top])
    lv = lv[~np.isnan(lv)]
    if lv.size == 0:
        return locked
    best = 0
    latRef = math.nan
    for x in lv:
        c = int(np.count_nonzero((lv >= x) & (lv <= x + 2 * hw)))
        if c > best:
            best = c
            latRef = x + hw
    with np.errstate(invalid="ignore"):
        return np.abs(lat - latRef) <= hw


def _rocker_rhythm(tc, sel, tOn, fR, minPerCycle, opts=None):
    """peaks sel at the rhythm of the rocker: minPerCycle ... rhythmMaxPerCycle (2.2) peaks per rocker cycle or a
    median interval of 1 or 1/2 rocker period (+-rhythmTolerance, 15 %, or half of it); False if the rocker frequency
    fR is unknown"""
    if opts is None:
        opts = _options()
    perCycle = np.count_nonzero(sel) / max(tOn, np.finfo(float).eps) / fR
    d = np.diff(tc[sel])
    ipi = float(np.median(d)) * fR if d.size else math.nan
    tol = opts.rhythmTolerance
    return bool((0 if math.isnan(perCycle) else minPerCycle <= perCycle <= opts.rhythmMaxPerCycle)
                or abs(ipi - 1) <= tol or abs(ipi - 0.5) <= tol / 2)


def rocker_frequency(S, opts):
    """rocker frequency (Hz): opts.rockerFrequency (one value in Hz, or [rpm, f0] rows of rocker_filter: the row of
    the logged speed, a single row otherwise) or the last logged rocker speed > 0 before the middle of the data
    (otherwise the first one) x opts.rockerHzPerRpm (0.0202 Hz/rpm); NaN if unknown (see rockerFrequency in
    mda_analyzeChannel.m)"""
    g = opts.get("rockerFrequency", None)
    ga = None
    if g is not None and not isinstance(g, str):
        ga = np.asarray(g, float)
        if ga.size == 1:
            v = float(ga.ravel()[0])
            if v > 0:
                return v
            ga = None
    rpm = math.nan
    L = np.asarray(S.get("rockerSpeedLog", np.zeros((0, 2))), float).reshape(-1, 2)
    if L.shape[0]:
        mid = (float(S.fromSeconds) + float(S.toSeconds)) / 2
        j = np.flatnonzero((L[:, 0] <= mid) & (L[:, 1] > 0))
        if j.size:
            rpm = float(L[j[-1], 1])
        else:
            j = np.flatnonzero(L[:, 1] > 0)
            if j.size:
                rpm = float(L[j[0], 1])
    if ga is not None and ga.size and ((ga.ndim == 2 and ga.shape[1] == 2) or (ga.ndim == 1 and ga.size == 2)):
        rows = ga.reshape(-1, 2)
        j = np.flatnonzero(rows[:, 0] == rpm)
        jj = int(j[0]) if j.size else (0 if rows.shape[0] == 1 else -1)
        if jj >= 0 and rows[jj, 1] > 0:
            return float(rows[jj, 1])
    return float(opts.get("rockerHzPerRpm", 0.0202)) * rpm if not math.isnan(rpm) else math.nan


def _prctile(x, p):
    """MATLAB prctile of a vector (NaN ignored)"""
    x = np.asarray(x, float)
    x = np.sort(x[~np.isnan(x)])
    n = x.size
    if n == 0:
        return math.nan
    if n == 1:
        return float(x[0])
    q = 100 * (np.arange(1, n + 1) - 0.5) / n
    return float(np.interp(min(max(p, q[0]), q[-1]), q, x))


def _stim_latency(tt, ST):
    """time since the previous stimulus (NaN before the first one)"""
    tt = np.asarray(tt, float)
    j = np.searchsorted(ST, tt, side="right") - 1
    lat = np.full(tt.size, np.nan)
    ok = j >= 0
    lat[ok] = tt[ok] - ST[j[ok]]
    return lat


def auto_threshold(prom, nStim, opts):
    """threshold = relThreshold x typical contraction amplitude, at least minThreshold (see the MATLAB help)."""
    typical = math.nan
    p = np.sort(prom[prom > 0])[::-1]
    if nStim >= opts.get("pacedMinStimuli", 3):
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
