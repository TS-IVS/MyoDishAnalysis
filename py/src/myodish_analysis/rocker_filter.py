"""Remove the periodic rocker artifact from the force signal while the rocker moves. Port of mda_rockerFilter.m.

    S, R = rocker_filter(S, channels, opts)          estimate the artifact in S and subtract it
    S, R = rocker_filter(S, channels, opts, Sctx)    estimate it in Sctx (same file, a larger time window that
                                                     contains S) and subtract it in S

S         data from read_mdd. Returned (as a copy) with the artifact subtracted from the force rows of the channels;
          S.rockerArtifact (size of S.force, uN; 0 where nothing was subtracted), S.rockerFiltered (bool per force
          row) and S.rockerFilterInfo (list per force row: R of the channel)
channels  data channel(s) to filter
opts      options from options() (rockerFrequency: None = automatic, a number (Hz) or [rpm, f0] rows)
R         list of Struct, one per channel: status, message, f0 (Hz), rpm, artifactPP (uN, peak-to-peak), r2,
          correctedFraction (of the rocker-on time in S), f0table ([rpm f0] rows), pass, blocks
          (rows [from to coverage r2 pp ok run source]; run and source are 0-based indices, MATLAB: 1-based)

METHOD (see the MATLAB help and README "Rocker artifact"): rocker frequency from the log file (rpm x 0.0202 Hz/rpm),
refined with the data of all channels; per rocker-on period blocks of 30 s: least-squares fit of 6 harmonics + a
baseline per stretch between two contractions to the samples between the contractions; consistency checks;
cross-faded blocks; only the periodic part is subtracted.

TS 2026-10-06 (port of mda_rockerFilter.m, TS 2026-10-05)
"""
from __future__ import annotations

import math

import numpy as np

from ._matlab import Struct, colon, linspace, mround, nanmedian, round_digits


def _constants():
    return Struct(
        hzPerRpm=0.0202,     # rocker frequency per rpm setting (two setups: 0.02020 and 0.02025 Hz/rpm)
        bandRel=0.03,        # search band around the expected frequency
        bandNoLog=(0.4, 2.2),  # search band without rocker speed in the log file
        K=6,                 # harmonics
        block=30,            # block length (s), hop = block / 2
        minRun=3,            # shorter rocker-on periods are not corrected (s)
        knot=2,              # baseline knots (s)
        lamB=0.1,            # smoothness penalty baseline
        lamH=1e-3,           # ridge penalty harmonics
        minCover=0.9,        # fraction of the 20 phase bins of the rocker cycle with >= 5 samples
        minR2=0.2,
        maxPPrel=1.6,        # block size <= 1.6 x reference size
        minRefBlock=10,      # reference blocks >= 10 s
        maxBorrow=60,        # artifact of a neighbouring block of the same rocker period (s)
        f0Block=120,         # frequency estimate: blocks of <= 120 s, at most 6 per channel and speed
        f0Blocks=6,
        wideRel=0.10,        # frequency estimate: the peak must be clear within +-10 %
        extendBlock=90,      # blocks without full coverage of the rocker cycle: retried with 90 s
    )


def _empty_r(channel=math.nan):
    return Struct(channel=channel, status="", message="", f0=math.nan, rpm=math.nan, artifactPP=math.nan,
                  r2=math.nan, correctedFraction=0.0, f0table=np.zeros((0, 2)), blocks=np.zeros((0, 8)), **{"pass": 0})


def rocker_filter(S, channels, opts, Sctx=None):
    from .analyze_channel import analyze_channel

    if Sctx is None:
        Sctx = S
    channels = [int(c) for c in np.atleast_1d(channels).ravel()]
    nRow = len(S.dataChannels)
    S = S.copy()
    S.force = np.array(S.force, dtype=float, copy=True)
    if "rockerArtifact" not in S or S.rockerArtifact is None or np.shape(S.rockerArtifact) != S.force.shape:
        S.rockerArtifact = np.zeros(S.force.shape)
        S.rockerFiltered = np.zeros(nRow, bool)
        S.rockerFilterInfo = [None] * nRow
    else:
        S.rockerArtifact = S.rockerArtifact.copy()
        S.rockerFiltered = np.array(S.rockerFiltered, bool).copy()
        S.rockerFilterInfo = list(S.rockerFilterInfo)
    o0 = Struct(opts)
    o0.rockerFilter = False; o0.rocker = "any"; o0.beats = "all"; o0.zeroForce = math.nan
    thrV = None  # one threshold per channel (myodish_analysis; NaN = auto)
    if not isinstance(opts.threshold, str) and np.size(opts.threshold) > 1:
        if np.size(opts.threshold) != len(channels):
            raise ValueError("rocker_filter: one threshold per channel expected.")
        thrV = np.ravel(np.asarray(opts.threshold, float))
        o0.threshold = "auto"

    def o_of(chX):
        """options of the contraction masks of channel chX (its threshold with per-channel thresholds)"""
        if thrV is None or chX not in channels:
            return o0
        o = Struct(o0)
        o.threshold = float(thrV[channels.index(chX)])
        return o
    P = _constants()
    R = [_empty_r(c) for c in channels]

    # ------------------------------------------------------------------ rocker periods and their speed
    r0, r1 = _runs(Sctx.rockerOn, Sctx.dt, P.minRun)
    if r0.size == 0 or not np.any(S.rockerOn):
        for Rc in R:
            Rc.status = "rocker not moving"
            Rc.message = f"Rocker filter, channel {Rc.channel}: the rocker does not move in this time window."
        return _store(S, R), R
    tc = np.asarray(Sctx.t, dtype=float)
    runT = np.c_[tc[r0], tc[r1]]  # [start end] of the rocker-on periods (s)
    nRun = r0.size
    rpm = np.full(nRun, np.nan)
    Lg = np.asarray(Sctx.get("rockerSpeedLog", np.zeros((0, 2))), dtype=float).reshape(-1, 2)
    if Lg.shape[0]:
        for q in range(nRun):
            tq = runT[q, 0] + min(5.0, 0.5 * (runT[q, 1] - runT[q, 0]))  # the speed command may follow the start
            j = np.flatnonzero((Lg[:, 0] <= tq) & (Lg[:, 1] > 0))
            if j.size:
                rpm[q] = Lg[j[-1], 1]
        known = np.flatnonzero(~np.isnan(rpm))
        for q in np.flatnonzero(np.isnan(rpm)):
            if known.size == 0:
                break
            k = int(np.argmin(np.abs(runT[known, 0] - runT[q, 0])))
            rpm[q] = rpm[known[k]]
        if known.size == 0:  # only stop commands before: first speed logged after the periods
            j = np.flatnonzero(Lg[:, 1] > 0)
            if j.size:
                rpm[:] = Lg[j[0], 1]
    # ------------------------------------------------------------------ rocker frequency per speed
    key = rpm.copy(); key[np.isnan(key)] = -1  # periods without logged speed: one group
    grp, gi = np.unique(key, return_inverse=True)
    gi = gi.ravel()
    f0run = np.full(nRun, np.nan)
    given = opts.rockerFrequency
    if given is not None:
        given = np.asarray(given, dtype=float)
        if given.ndim == 2 and given.shape[1] == 2:
            given = given.copy()
            given[np.isnan(given[:, 0]), 0] = -1
    needEstimate = np.zeros(grp.size, bool)
    for g in range(grp.size):
        if given is not None and given.size == 1 and float(given.ravel()[0]) > 0:
            f0run[gi == g] = float(given.ravel()[0])
        elif given is not None and given.ndim == 2 and given.shape[1] == 2 and np.any(given[:, 0] == grp[g]):
            f0run[gi == g] = given[np.flatnonzero(given[:, 0] == grp[g])[0], 1]
        else:
            needEstimate[g] = True
    # masks of the contractions in the original signal (A: stimulus windows of paced channels; B: from the detected
    # contractions); all channels for the frequency estimate, otherwise only the filtered channels
    dcX = [int(c) for c in np.asarray(Sctx.dataChannels).ravel()]
    nX = len(dcX)
    need = np.isin(dcX, channels)
    if needEstimate.any():
        need[:] = True
    MA = [None] * nX
    MB = [None] * nX
    for k in np.flatnonzero(need):
        try:
            B0, C0 = analyze_channel(Sctx, dcX[k], None, o_of(dcX[k]))
            if C0.stimTimes.size >= 3:
                MA[k] = _first_mask(B0, C0)
            MB[k] = _second_mask(B0, C0)
        except Exception:
            MB[k] = np.zeros((0, 2))
    if needEstimate.any():
        MF = list(MB)  # frequency estimate: stimulus windows if they leave >= 25 % of the time
        for k in range(nX):
            if MA[k] is not None and MA[k].size and np.mean(_mask_of(tc, MA[k])) >= 0.25:
                MF[k] = MA[k]
        for g in np.flatnonzero(needEstimate):
            if grp[g] < 0:
                band = P.bandNoLog
            else:
                band = (grp[g] * P.hzPerRpm * (1 - P.bandRel), grp[g] * P.hzPerRpm * (1 + P.bandRel))
            f0run[gi == g] = _estimate_f0(Sctx, MF, runT[gi == g], band, grp[g] >= 0, P)
    f0table = np.zeros((grp.size, 2))
    for g in range(grp.size):
        f0table[g] = [grp[g], f0run[np.flatnonzero(gi == g)[0]]]
    f0table[f0table[:, 0] < 0, 0] = np.nan

    # ------------------------------------------------------------------ artifact per channel
    onS = np.asarray(S.rockerOn, bool)
    dcS = [int(c) for c in np.asarray(S.dataChannels).ravel()]
    tS = np.asarray(S.t, dtype=float)
    for c, ch in enumerate(channels):
        Rc = R[c]
        Rc.f0table = f0table
        Rc.f0 = nanmedian(f0run)
        Rc.rpm = nanmedian(rpm)
        if ch not in dcS or ch not in dcX:
            continue
        row = dcS.index(ch)
        rowX = dcX.index(ch)
        if np.all(np.isnan(f0run)):
            Rc.status = "rocker frequency not found"
            Rc.message = (f"Rocker filter, channel {ch}: rocker frequency not found (expected "
                          f"{_fmt_list(rpm * P.hzPerRpm)} Hz) - no correction.")
            continue
        x = np.asarray(Sctx.force[rowX], dtype=float)
        # pass 1: both masks, the better fit (accepted time x R2) is used
        I = _fit_artifact(tc, x, runT, gi, f0run, MB[rowX], P)
        if MA[rowX] is not None and MA[rowX].size:
            IA = _fit_artifact(tc, x, runT, gi, f0run, MA[rowX], P)
            if IA.score > I.score:
                I = IA
        Rc["pass"] = 1
        # pass 2: mask from the contractions detected in the cleaned signal; fit again on the original signal
        if I.score > 0:
            Sx = Sctx.copy()
            Sx.force = np.array(Sctx.force, dtype=float, copy=True)
            Sx.force[rowX] = x - _eval_artifact(I, tc, runT, f0run, P)
            B1, C1 = analyze_channel(Sx, ch, None, o_of(ch))
            I2 = _fit_artifact(tc, x, runT, gi, f0run, _second_mask(B1, C1), P)
            if I2.score >= I.score:
                I = I2
                Rc["pass"] = 2
        a = _eval_artifact(I, tS, runT, f0run, P)
        S.force[row] = S.force[row] - a
        S.rockerArtifact[row] = a
        # result
        Rc.artifactPP = I.refPP
        Rc.r2 = I.refR2
        Rc.blocks = I.blk
        Rc.correctedFraction = float(np.sum(onS & (a != 0)) / max(1, np.sum(onS)))
        pct = 100 * Rc.correctedFraction
        src = I.blk[~np.isnan(I.blk[:, 7]), 6].astype(int) if I.blk.shape[0] else np.zeros(0, int)
        fTxt = _fmt_list(f0run[np.unique(src)])
        if math.isnan(I.refPP) or pct == 0:
            if I.nCovered == 0:
                Rc.status = "too little time between contractions"
                Rc.message = (f"Rocker filter, channel {ch}: too little time between the contractions to estimate "
                              "the rocker artifact (pacing too fast for the duration of the contractions) - no "
                              "correction.")
            else:
                Rc.status = "no periodic artifact detectable"
                Rc.message = f"Rocker filter, channel {ch}: no periodic rocker artifact detectable - no correction."
        elif pct >= 99.5:
            Rc.status = "corrected"
            Rc.message = (f"Rocker filter, channel {ch}: artifact {I.refPP:.0f} µN peak-to-peak (f0 {fTxt} Hz) "
                          "removed.")
        else:
            Rc.status = "partly corrected"
            Rc.message = (f"Rocker filter, channel {ch}: artifact {I.refPP:.0f} µN peak-to-peak (f0 {fTxt} Hz) "
                          f"removed in {pct:.0f} % of the rocker-on time (rest: not estimable).")
    return _store(S, R), R


# =====================================================================================================
def _store(S, R):
    dc = [int(c) for c in np.asarray(S.dataChannels).ravel()]
    for Rc in R:
        if Rc.channel not in dc:
            continue
        row = dc.index(Rc.channel)
        S.rockerFiltered[row] = True
        S.rockerFilterInfo[row] = Rc
    return S


def _fmt_list(v):
    v = np.asarray(v, dtype=float).ravel()
    v = v[~np.isnan(v)]
    if v.size == 0:
        return "?"
    v = np.unique(round_digits(v, 3))  # MATLAB unique(round(v, 3))
    return ", ".join(f"{x:.3f}" for x in v)


def _runs(on, dt, minLen):
    on = np.asarray(on, bool).ravel().astype(int)
    d = np.diff(np.r_[0, on, 0])
    s0 = np.flatnonzero(d == 1)
    s1 = np.flatnonzero(d == -1) - 1
    keep = (s1 - s0) * dt >= minLen
    return s0[keep], s1[keep]


# ------------------------------------------------------------------ masks (time intervals with contractions)
def _first_mask(B, C):
    ST = np.asarray(C.stimTimes, dtype=float)
    if ST.size >= 3:
        CL = np.r_[np.diff(ST), np.median(np.diff(ST))]
        return np.c_[ST - 0.02, ST + np.minimum(CL - 0.05, 1.2)]
    ttp, ttr = _durations(B)
    pk = np.asarray(C.peakTimes, dtype=float)
    return np.c_[pk - ttp - 0.08, pk + 1.3 * ttr + 0.08]


def _second_mask(B, C):
    ST = np.asarray(C.stimTimes, dtype=float)
    if ST.size >= 3:
        st = (B["beatType"] == "stimulated").to_numpy()
        ttp, ttr = _durations(B[st])
        lat = nanmedian(B["stimToPeak"].to_numpy()[st])
        if np.isnan(lat):
            lat = 0.3
        CL = np.r_[np.diff(ST), np.median(np.diff(ST))]
        iv = np.c_[ST - 0.02, ST + np.minimum(CL - 0.05, max(0.3, lat + 1.3 * ttr + 0.08))]
        ampS = nanmedian(B["amplitude"].to_numpy()[st])
        with np.errstate(invalid="ignore"):
            ex = (B["beatType"] == "extra").to_numpy() & (B["prominence"].to_numpy() >= 0.5 * ampS)
        tp = B["t_peak"].to_numpy()[ex]
        return np.r_[iv, np.c_[tp - ttp - 0.08, tp + 1.3 * ttr + 0.08]]
    ttp, ttr = _durations(B)
    pk = np.asarray(C.peakTimes, dtype=float)
    return np.c_[pk - ttp - 0.08, pk + 1.3 * ttr + 0.08]


def _durations(B):
    ttp = nanmedian(B["TTP90"].to_numpy()) if len(B) else np.nan
    ttr = nanmedian(B["TTR90"].to_numpy()) if len(B) else np.nan
    if np.isnan(ttp):
        ttp = 0.3
    if np.isnan(ttr):
        ttr = 0.6
    return float(ttp), float(ttr)


def _mask_of(t, iv):
    """True = sample between contractions."""
    t = np.asarray(t, dtype=float).ravel()
    n = t.size
    m = np.ones(n, bool)
    if iv is None or np.size(iv) == 0 or n < 2:
        return m
    iv = np.asarray(iv, dtype=float).reshape(-1, 2)
    dt = (t[-1] - t[0]) / (n - 1)
    with np.errstate(invalid="ignore"):
        i0 = np.floor((iv[:, 0] - t[0]) / dt)
        i1 = np.ceil((iv[:, 1] - t[0]) / dt)
    i0 = np.fmax(0, i0)  # max/min ignore NaN, as in MATLAB
    i1 = np.fmin(n - 1, i1)
    ok = i1 >= i0
    if not ok.any():
        return m
    i0 = i0[ok].astype(np.int64); i1 = i1[ok].astype(np.int64)
    d = np.bincount(i0, minlength=n + 1)[: n + 1] - np.bincount(i1 + 1, minlength=n + 1)[: n + 1]
    return np.cumsum(d[:n]) == 0


# ------------------------------------------------------------------ rocker frequency (all channels)
def _estimate_f0(Sctx, M, runT, band, fromLog, P):
    """harmonic-sum periodogram (3 harmonics, baseline per block removed), mean over the channels; maximum within
    band, which must be a clear peak (>= 0.05 and >= 3 x the median within +-10 % around the expected frequency)."""
    t = np.asarray(Sctx.t, dtype=float)
    dec = max(1, mround(0.02 / Sctx.dt))  # about 50 Hz is enough for the frequency
    blocks = _blocks_of(runT, P.f0Block)
    if blocks.shape[0] > P.f0Blocks:
        sel = (mround(linspace(1, blocks.shape[0], P.f0Blocks)) - 1).astype(int)
        blocks = blocks[sel]
    D = []  # per channel and block: channel row, t, residual e0, basis Q
    for k in range(len(M)):
        m = _mask_of(t, M[k])
        for j in range(blocks.shape[0]):
            u = np.flatnonzero((t >= blocks[j, 0]) & (t <= blocks[j, 1]) & m)
            u = u[::dec]
            if u.size < 30:
                continue
            Hb, _, keep = _base_basis(t[u], 1.5 * dec * Sctx.dt, 3, P)
            u = u[keep]
            if u.size < 30:
                continue
            y = np.asarray(Sctx.force[k], dtype=float)[u]
            Q, _ = np.linalg.qr(Hb, mode="reduced")
            e0 = y - Q @ (Q.T @ y)
            D.append((k, t[u], e0, Q))
    f0 = math.nan
    if not D:
        return f0
    step = 0.002
    wide = band
    if fromLog:
        mb = (band[0] + band[1]) / 2
        wide = (mb * (1 - P.wideRel), mb * (1 + P.wideRel))
    fr = colon(wide[0], step, wide[1])
    nCh = len(M)

    def mean_r2(fx):
        res = np.zeros((nCh, fx.size))
        tot = np.zeros(nCh)
        for (k_, tt, e0_, Q_) in D:
            tot[k_] += np.sum(e0_ ** 2)
            for jj, fj in enumerate(fx):
                e1 = np.exp(2j * np.pi * fj * tt)
                e2 = e1 * e1
                e3 = e2 * e1
                X = np.c_[e1.real, e1.imag, e2.real, e2.imag, e3.real, e3.imag]
                X = X - Q_ @ (Q_.T @ X)
                cf = np.linalg.lstsq(X, e0_, rcond=None)[0]
                res[k_, jj] += np.sum((e0_ - X @ cf) ** 2)
        okC = tot > 0
        return np.mean(1 - res[okC] / tot[okC][:, None], axis=0)

    r2 = mean_r2(fr)
    inB = (fr >= band[0]) & (fr <= band[1])
    prod = r2 * inB
    j = int(np.nanargmax(prod)) if np.any(~np.isnan(prod)) else 0
    r2max = prod[j]
    if not (r2max >= 0.05 and r2max >= 3 * np.median(r2)):  # no clear peak: not found
        return f0
    ff = fr[j] + colon(-step, step / 20, step)
    r2f = mean_r2(ff)
    j = int(np.nanargmax(r2f))
    f0 = float(ff[j])
    if f0 <= band[0] + step or f0 >= band[1] - step:  # at the band edge: not found
        f0 = math.nan
    return f0


def _block_samples(t, m, a, b, f0):
    """samples between contractions in [a b] and the covered fraction of the rocker cycle (20 phase bins, >= 5)."""
    u = np.flatnonzero((t >= a) & (t <= b) & m)
    pb = np.floor(np.mod(t[u] * f0, 1) * 20).astype(int)
    cnt = np.bincount(pb, minlength=20)[:20]
    return u, float(np.mean(cnt >= 5))


def _blocks_of(runT, L):
    blocks = []  # [from to run]
    for q in range(runT.shape[0]):
        ts, te = runT[q]
        if te - ts <= L:
            blocks.append([ts, te, q])
        else:
            nb = math.ceil((te - ts - L) / (L / 2)) + 1
            for a in linspace(ts, te - L, nb):
                blocks.append([a, a + L, q])
    return np.array(blocks, dtype=float).reshape(-1, 3)


# ------------------------------------------------------------------ artifact of one channel
def _fit_artifact(t, x, runT, grpRun, f0run, iv, P):
    """t, x: signal (raw force), iv: contractions [from to]; I: blocks, harmonic coefficients, consistency."""
    m = _mask_of(t, iv)
    I = Struct()
    I.dt = float(np.median(np.diff(t)))
    blocks = _blocks_of(runT, P.block)
    nB = blocks.shape[0]
    blk = np.full((nB, 8), np.nan)  # [from to coverage r2 pp ok run source]
    coef = [None] * nB
    for j in range(nB):
        a, b, q = blocks[j, 0], blocks[j, 1], int(blocks[j, 2])
        f0 = f0run[q]
        blk[j, [0, 1, 6]] = [a, b, q]
        blk[j, 5] = 0
        if np.isnan(f0):
            continue
        u, cov = _block_samples(t, m, a, b, f0)
        if cov < P.minCover and b - a < P.extendBlock:  # e.g. pacing close to the rocker frequency: longer block
            mid = (a + b) / 2
            a2 = max(runT[q, 0], mid - P.extendBlock / 2)
            b2 = min(runT[q, 1], mid + P.extendBlock / 2)
            if b2 - a2 > b - a:
                u2, cov2 = _block_samples(t, m, a2, b2, f0)
                if cov2 > cov:
                    u, cov, a, b = u2, cov2, a2, b2
        blk[j, 2] = cov
        if u.size < 100 or cov < P.minCover:
            continue
        Hb, DtD, keep = _base_basis(t[u], 1.5 * I.dt, 10, P)
        u = u[keep]
        if u.size < 100:
            continue
        X = np.c_[Hb, _harm(t[u], f0, P.K)]
        nb = Hb.shape[1]
        n = u.size
        Pen = _blkdiag([P.lamB * n / nb * DtD, P.lamH * n * np.eye(2 * P.K)])
        cf = np.linalg.solve(X.T @ X + Pen, X.T @ x[u])
        e = x[u] - X @ cf
        base = x[u] - Hb @ cf[:nb]
        with np.errstate(divide="ignore", invalid="ignore"):  # constant signal (no sensor): -Inf / NaN as in MATLAB
            r2 = 1 - np.sum(e ** 2) / np.sum((base - np.mean(base)) ** 2)
        w = _harm(colon(0, 0.005, 1) / f0, f0, P.K) @ cf[nb:]
        pp = np.max(w) - np.min(w)
        sb = np.sort(base)
        rng = sb[max(1, mround(0.99 * n)) - 1] - sb[max(1, mround(0.01 * n)) - 1]
        blk[j, 3:6] = [r2, pp, float(pp <= 1.5 * rng)]
        coef[j] = cf[nb:]
    I.nCovered = int(np.sum(blk[:, 2] >= P.minCover)) if nB else 0
    # consistency of the blocks, per rocker speed (the size of the artifact depends on the speed)
    with np.errstate(invalid="ignore"):
        good = (blk[:, 5] == 1) & (blk[:, 3] >= P.minR2) & (blk[:, 1] - blk[:, 0] >= P.minRefBlock)
    acc = np.zeros(nB, bool)
    gB = np.asarray(grpRun)[blk[:, 6].astype(int)] if nB else np.zeros(0, int)
    for g in np.unique(gB):
        inn = gB == g
        if not np.any(good & inn):
            continue
        refPP = np.median(blk[good & inn, 4])
        refR2 = np.median(blk[good & inn, 3])
        with np.errstate(invalid="ignore"):
            acc |= inn & (blk[:, 5] == 1) & (blk[:, 3] >= max(P.minR2, 0.5 * refR2)) & (blk[:, 4] <= P.maxPPrel * refPP)
    blk[:, 5] = acc
    I.refPP = math.nan
    I.refR2 = math.nan
    if acc.any():
        I.refPP = float(np.median(blk[acc, 4]))
        I.refR2 = float(np.median(blk[acc, 3]))
    I.acceptedTime = float(np.sum(blk[acc, 1] - blk[acc, 0]))
    r2pos = 0.0 if math.isnan(I.refR2) else max(0.0, I.refR2)  # max ignores NaN, as in MATLAB
    I.score = I.acceptedTime * r2pos  # for the choice between masks
    if math.isnan(I.score):
        I.score = 0.0
    # coefficients per block: accepted blocks their own; others those of the nearest accepted block of the same
    # rocker period (<= maxBorrow s)
    ctr = np.mean(blk[:, 0:2], axis=1) if nB else np.zeros(0)
    for j in range(nB):
        if acc[j]:
            blk[j, 7] = j
        else:
            cand = np.flatnonzero(acc & (blk[:, 6] == blk[j, 6]) & (np.abs(ctr - ctr[j]) <= P.maxBorrow))
            if cand.size == 0:
                continue
            k = int(np.argmin(np.abs(ctr[cand] - ctr[j])))
            blk[j, 7] = cand[k]
    I.blk = blk
    I.coef = coef
    return I


def _eval_artifact(I, tEval, runT, f0run, P):
    """artifact at the times tEval (blocks cross-faded with triangular weights, flat towards the ends of a rocker
    period)."""
    tEval = np.asarray(tEval, dtype=float)
    art = np.zeros(tEval.shape)
    W = np.zeros(tEval.shape)
    dt = I.dt
    blk = I.blk
    for j in np.flatnonzero(~np.isnan(blk[:, 7])) if blk.shape[0] else []:
        a, b, q = blk[j, 0], blk[j, 1], int(blk[j, 6])
        ie = np.flatnonzero((tEval >= a - dt / 2) & (tEval <= b + dt / 2))
        if ie.size == 0:
            continue
        te_ = tEval[ie]
        mid = (a + b) / 2
        w = np.ones(ie.size)
        if a > runT[q, 0] + dt:
            w = np.minimum(w, (te_ - a) / (mid - a))
        if b < runT[q, 1] - dt:
            w = np.minimum(w, (b - te_) / (b - mid))
        w = np.maximum(w, 1e-6)
        art[ie] += w * (_harm(te_, f0run[q], P.K) @ I.coef[int(blk[j, 7])])
        W[ie] += w
    pos = W > 0
    art[pos] = art[pos] / W[pos]
    return art


def _blkdiag(mats):
    mats = [np.atleast_2d(np.asarray(M, dtype=float)) for M in mats]
    r = sum(M.shape[0] for M in mats)
    c = sum(M.shape[1] for M in mats)
    out = np.zeros((r, c))
    i = j = 0
    for M in mats:
        out[i:i + M.shape[0], j:j + M.shape[1]] = M
        i += M.shape[0]
        j += M.shape[1]
    return out


def _base_basis(tu, gapThr, minN, P):
    """baseline of the samples between contractions, separately per gap-free stretch: a constant for stretches < 2
    knot distances, a linear spline (smoothness penalty DtD) for longer ones."""
    tu = np.asarray(tu, dtype=float).ravel()
    n = tu.size
    brk = np.r_[0, np.flatnonzero(np.diff(tu) > gapThr) + 1, n]
    keep = np.zeros(n, bool)
    Hs, Ds = [], []
    for w in range(brk.size - 1):
        iw = np.arange(brk[w], brk[w + 1])
        if iw.size < minN:
            continue
        keep[iw] = True
        tw = tu[iw]
        if tw[-1] - tw[0] < 2 * P.knot:
            Hs.append(np.ones((iw.size, 1)))
            Ds.append(np.zeros((1, 1)))
        else:
            H = _hats(tw, P.knot)
            Dm = np.diff(np.eye(H.shape[1]), n=2, axis=0)
            Hs.append(H)
            Ds.append(Dm.T @ Dm)
    if not Hs:
        return np.zeros((0, 0)), np.zeros((0, 0)), keep
    return _blkdiag(Hs), _blkdiag(Ds), keep


def _harm(t, f0, K):
    t = np.asarray(t, dtype=float).ravel()
    X = np.zeros((t.size, 2 * K))
    for k in range(1, K + 1):
        X[:, 2 * k - 2] = np.cos(2 * np.pi * k * f0 * t)
        X[:, 2 * k - 1] = np.sin(2 * np.pi * k * f0 * t)
    return X


def _hats(t, step):
    """linear spline basis (hat functions), knots evenly over [t(1) t(end)] with a spacing <= step."""
    n = max(2, math.ceil((t[-1] - t[0]) / step) + 1)
    kn = linspace(t[0], t[-1], n)
    h = kn[1] - kn[0]
    return np.maximum(0, 1 - np.abs(t[:, None] - kn[None, :]) / h)
