"""Characteristic values of a stimulation protocol (one channel, one range) from the grouped summary. Port of
mda_protocolResults.m.

    R = protocol_results(by, G, Z=None, trace=None, opts=None)

by     grouping of the range ('pacingFrequency', 'stimCurrent', 'S2interval', 'pauseLength'; others: only the note)
G      group summary of the channel and range (group_beats)
Z      stimuli of the channel (group_beats(..., return_stimuli=True)); needed for S2interval
trace  S2interval: dict t, f (filtered force of the channel, analyze_channel C.t / C.f), tR, rockerOn (rocker state
       of the samples, read_mdd S.t / S.rockerOn)
opts   options (rocker: 'stopped' = template and S2 windows only while the rocker is at rest)

R      dict with all result columns (NaN where not applicable), see RESULT_COLUMNS and the help of mda_protocolResults.m

TS 2026-10-07 (port of mda_protocolResults.m)
"""
from __future__ import annotations

import math

import numpy as np

from ._matlab import islocalmax, movmean, mround

RESULT_COLUMNS = [
    "maxCapturedFrequency_Hz", "amplitude_0p5Hz_uN", "FFR_1Hz_pct", "FFR_2Hz_pct", "FFR_3Hz_pct",
    "captureThreshold_mA", "stimThreshold10_mA", "stimThreshold50_mA", "stimThreshold95_mA", "stimThreshold99_mA",
    "maxAmplitude_uN",
    "refPeriodNoPeak_ms", "refPeriodNoPeakStep_ms", "refPeriodNoResponse_ms", "refPeriodNoResponseStep_ms",
    "S2noiseLevel_pct", "amplitudeS1_uN", "nS2", "nTemplateBeats",
    "PRP15_pct", "PRP15_pause_s", "PRP30_pct", "PRP30_pause_s", "PRP60_pct", "PRP60_pause_s",
    "resultNote"]


def captured_groups(G):
    """a group is captured if at most max(1, 10 % of its stimuli) are not followed by a contraction and >= 2 are."""
    n = G["nStimuli"].to_numpy(float)
    nf = np.array([mround(x) for x in G["capture_percent"].to_numpy(float) / 100 * n]) if len(G) else np.zeros(0)
    nm = n - nf
    with np.errstate(invalid="ignore"):
        return (nm <= np.fmax(1, np.floor(0.1 * n))) & (nf >= 2)


def protocol_results(by, G, Z=None, trace=None, opts=None):
    R = {c: math.nan for c in RESULT_COLUMNS}
    R["resultNote"] = ""
    notes = []
    byl = str(by).lower()
    if G is None or len(G) == 0:
        R["resultNote"] = "no groups"
        return R
    val = G["groupValue"].to_numpy(float)
    amp = G["amplitude_mean"].to_numpy(float)
    role = G["groupRole"].astype(str).to_numpy()
    cap = captured_groups(G)

    if byl == "pacingfrequency":
        ok = cap & ~np.isnan(val)
        if ok.any():
            R["maxCapturedFrequency_Hz"] = float(np.max(val[ok]))
        a05 = _at(val, amp, cap, 0.5)
        R["amplitude_0p5Hz_uN"] = a05
        for f, c in ((1, "FFR_1Hz_pct"), (2, "FFR_2Hz_pct"), (3, "FFR_3Hz_pct")):
            R[c] = 100 * _at(val, amp, cap, f) / a05
        if math.isnan(a05):
            notes.append("no captured 0.5 Hz group")

    elif byl == "stimcurrent":
        ok = cap & ~np.isnan(val)
        if ok.any():
            R["captureThreshold_mA"] = float(np.min(val[ok]))
        oka = ok & ~np.isnan(amp)
        if oka.any():
            mx = float(np.max(amp[oka]))
            R["maxAmplitude_uN"] = mx
            for x in (10, 50, 95, 99):
                k = oka & (amp >= x / 100 * mx)
                R[f"stimThreshold{x}_mA"] = float(np.min(val[k]))
        else:
            notes.append("no captured current with included contractions")

    elif byl == "pauselength":
        st = np.flatnonzero(role == "steady")
        cl = 1 / float(G["stimFrequency"].to_numpy(float)[st[0]]) if st.size else math.nan
        pr = np.flatnonzero((role == "postRest") & ~np.isnan(val))
        pause = val[pr] - cl
        pct = G["amplitude_pctOfRef"].to_numpy(float)[pr]
        for x in (15, 30, 60):
            if pr.size and not math.isnan(cl):
                k = int(np.argmin(np.abs(pause - x)))
                if abs(pause[k] - x) <= 0.5 * x:
                    R[f"PRP{x}_pct"] = float(pct[k])
                    R[f"PRP{x}_pause_s"] = float(pause[k])
        if math.isnan(cl):
            notes.append("no steady group")

    elif byl == "s2interval":
        if Z is None or trace is None:
            notes.append("S2 response: no data")
        else:
            notes += _s2_results(R, Z, trace, opts)
    R["resultNote"] = "; ".join(notes)
    return R


def _at(val, amp, cap, f):
    """amplitude of the captured group at f (+-5 %, the nearest)"""
    with np.errstate(invalid="ignore"):
        k = np.flatnonzero(cap & (np.abs(val - f) <= 0.05 * f))
    if not k.size:
        return math.nan
    return float(amp[k[np.argmin(np.abs(val[k] - f))]])


# =====================================================================================================
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


def _transition(ci, v, level, name, notes):
    """first interval (from long to short) at which v falls below level and stays below at the next shorter interval;
    linear interpolation with the previous interval (GetRefractoryPeriod)"""
    keep = ~np.isnan(v)
    ci, v = ci[keep], v[keep]
    if not v.size or math.isnan(level):
        notes.append(f"{name}: not determined")
        return math.nan, math.nan
    below = v < level
    nxt = np.r_[below[1:], True]
    k = np.flatnonzero(below & nxt)
    if not k.size:
        notes.append(f"{name}: not reached (< {ci[-1]:g} ms)")
        return math.nan, math.nan
    k = int(k[0])
    if k == 0:
        notes.append(f"{name}: already at the longest interval (> {ci[0]:g} ms)")
        return math.nan, math.nan
    step = ci[k - 1] - ci[k]
    return float(ci[k] + (level - v[k]) / (v[k - 1] - v[k]) * step), float(step)


def _s2_results(R, Z, trace, opts):
    """S2 response by subtraction of the scaled mean steady-state S1 contraction (GetRefractoryPeriod, 2026-10-06):
    template = mean S1 contraction (S1 interval before and after, rocker at rest), scaled per S2 on S1 ... S2 + 20 ms;
    response = maximum of the residual (30-ms mean) S2 + 30 ms ... min(S2 + 600 ms, S1 interval - 100 ms) (% of S1);
    separate peak = local maximum of the S1+S2 trace S2 + 25 ms ... min(S2 + 600 ms, next stimulus + 20 ms) with
    prominence >= max(noise level, 2 %) (not limited by the template, so that the peak is found also when the S2
    interval is close to the S1 interval); noise level = 99th percentile of the response at pseudo-S2 on the template
    beats (leave-one-out)."""
    notes = []
    t = np.asarray(trace["t"], float).ravel()
    f = np.asarray(trace["f"], float).ravel()
    tR = np.asarray(trace["tR"], float).ravel()
    rock = np.asarray(trace["rockerOn"], bool).ravel()
    stopped = opts is not None and str(opts.rocker) == "stopped"
    st = Z["t"].to_numpy(float)
    role = Z["role"].astype(str).to_numpy()
    val = Z["value"].to_numpy(float)
    inR = Z["inRange"].to_numpy(bool)
    pi = Z["prevInt"].to_numpy(float)
    ni = Z["nextInt"].to_numpy(float)
    p = pi[(role == "S1") & inR]
    p = p[~np.isnan(p)]
    if t.size < 10 or not p.size:
        return ["S2 response: no S1 stimuli"]
    S1 = float(np.median(p))
    dt = float(np.median(np.diff(t)))
    tol = max(0.03, 0.02 * S1)

    def at_rest(a, b):
        if not stopped:
            return True
        k = (tR >= a) & (tR <= b)
        return bool(k.any()) and not bool(rock[k].any())

    def in_data(a, b):
        return t[0] <= a and t[-1] >= b

    tg = np.arange(mround(-0.05 / dt), mround((S1 - 0.1) / dt) + 1) * dt
    w = max(1, mround(0.03 / dt))

    def get_trace(s, grid=None):
        g = tg if grid is None else grid
        x = s + g
        y = np.interp(x, t, f)
        y[(x < t[0]) | (x > t[-1])] = np.nan
        return y - np.mean(y[g < 0])

    with np.errstate(invalid="ignore"):
        isSS = (role == "S1") & inR & (np.abs(pi - S1) < tol) & (np.abs(ni - S1) < tol)
    jSS = [j for j in np.flatnonzero(isSS) if in_data(st[j] - 0.05, st[j] + S1 - 0.1) and at_rest(st[j], st[j] + S1 - 0.1)]
    Y = np.column_stack([get_trace(st[j]) for j in jSS]) if jSS else np.zeros((tg.size, 0))
    ok = ~np.isnan(Y).any(axis=0) if Y.size else np.zeros(0, bool)
    Y = Y[:, ok]
    nT = Y.shape[1]
    R["nTemplateBeats"] = float(nT)
    jS2 = np.flatnonzero((role == "S2") & inR)
    R["nS2"] = float(jS2.size)
    if not jS2.size:
        return ["no S2 stimuli"]
    if nT < 3:
        return [f"only {nT} steady-state S1 beats with the rocker at rest (>= 3 needed)"]
    m = Y.mean(axis=1)
    A1 = float(np.max(m))
    R["amplitudeS1_uN"] = A1
    if A1 <= 0:
        return ["no S1 contraction"]

    nTg = tg.size

    def s2response(y, mt, c, winResp, gy=None, winPeak=None):
        """residual maximum (S2 response), scale of the S1 contraction and the largest prominence of a local maximum
        of the S1+S2 trace y (grid gy, starting like tg) S2 + 25 ms ... winPeak"""
        yt = y[:nTg]
        pre = (tg >= 0) & (tg <= c + 0.02)
        aq = float(yt[pre] @ mt[pre] / (mt[pre] @ mt[pre]))
        r = movmean(yt - aq * mt, w)
        Kw = np.flatnonzero((tg >= c + 0.03) & (tg <= winResp))
        rmax = float(np.max(r[Kw])) if Kw.size else math.nan
        pmax = 0.0
        if gy is not None:
            Kq = np.flatnonzero((gy >= c + 0.025) & (gy <= winPeak))
            if Kq.size >= 3:
                isMax, P = islocalmax(movmean(y[Kq], w))
                if isMax.any():
                    pmax = float(np.max(P[isMax]))
        return rmax, aq, pmax

    n = jS2.size
    CI = np.full(n, np.nan)
    resp = np.full(n, np.nan)
    prom = np.full(n, np.nan)
    for q, j in enumerate(jS2):
        if j < 1:
            continue
        s1 = st[j - 1]
        c = st[j] - s1
        CI[q] = c
        winPeak = min(c + 0.6, c + (ni[j] if not math.isnan(ni[j]) else math.inf) + 0.02)
        winResp = min(winPeak, S1 - 0.1)
        if not in_data(s1 - 0.05, s1 + max(winPeak, S1 - 0.1)) or not at_rest(s1, s1 + winPeak):
            continue
        gy = np.arange(mround(-0.05 / dt), mround(max(winPeak, S1 - 0.1) / dt) + 1) * dt
        rq, aq, pq = s2response(get_trace(s1, gy), m, c, winResp, gy, winPeak)
        if aq < 0.2 or math.isnan(rq):  # no S1 contraction
            continue
        resp[q] = 100 * rq / (aq * A1)
        prom[q] = 100 * pq / (aq * A1)

    # noise level: pseudo-S2 on the template beats (leave-one-out template) at every tested interval
    uCI = np.unique([mround(x * 1000) / 1000 for x in CI[~np.isnan(resp)]])
    nullV = []
    for k in range(nT):
        mk = (Y.sum(axis=1) - Y[:, k]) / (nT - 1)
        for c in uCI:
            rk, ak, _ = s2response(Y[:, k], mk, c, min(c + 0.6, S1 - 0.1))
            if ak >= 0.2 and not math.isnan(rk):
                nullV.append(100 * rk / (ak * float(np.max(mk))))
    noise = _prctile(np.array(nullV), 99)
    R["S2noiseLevel_pct"] = noise
    with np.errstate(invalid="ignore"):
        sep = (prom >= max(noise, 2)) & (resp >= noise)

    # transitions from long to short S2 intervals (groups of mda_groupBeats)
    v = ~np.isnan(resp)
    g = val[jS2][v]
    ciU = np.unique(g)[::-1]
    fracSep = np.array([np.mean(sep[v][g == x]) for x in ciU])
    medResp = np.array([np.median(resp[v][g == x]) for x in ciU])
    ciU = np.array([mround(1000 * x) for x in ciU], float)
    R["refPeriodNoPeak_ms"], R["refPeriodNoPeakStep_ms"] = _transition(ciU, 100 * fracSep, 50, "no peak", notes)
    R["refPeriodNoResponse_ms"], R["refPeriodNoResponseStep_ms"] = _transition(ciU, medResp, noise, "no response",
                                                                               notes)
    if not math.isnan(noise) and noise >= 50:
        for c in ("refPeriodNoPeak_ms", "refPeriodNoPeakStep_ms", "refPeriodNoResponse_ms",
                  "refPeriodNoResponseStep_ms"):
            R[c] = math.nan
        notes = [f"noise level {mround(noise)} %: no reliable stimulus-locked S1 contraction - no estimates"]
    return notes
