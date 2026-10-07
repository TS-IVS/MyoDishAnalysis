"""Reference beat (mean shape +- SD of selected contractions) and the comparison of contractions with it.
Port of mda_referenceBeat.m.

    R = create(C, B, rows[, align])   reference from the contractions B.iloc[rows] (at least 3); align 'stimulus'
                                      (default) or 'upstroke'
    R = align(R, align)               switch the alignment of a reference (both variants are stored; '' = keep, only
                                      standardize the fields of older references)
    V = compare(C, B, R)              DataFrame, one row per contraction: refCorrelation, refRMSDeviation_SD,
                                      refRMSDeviationNorm_SD, refMaxDeviation_SD, refMaxDeviationNorm_SD
    Y = traces(C, B, R, rows)         developed force of the contractions on R.tGrid, aligned as R (one column per
                                      contraction, NaN where not comparable)
    V = relative(B, R)                every parameter relative to the reference (<p>_pctRef, diastolic: <p>_dRef)
    save_reference(file, R) / load_reference(file)   .mat file (variable referenceBeat), compatible with MATLAB
    mda_referenceBeat(action, ...)   dispatcher with the MATLAB call syntax

C, B   channel info and contraction table of analyze_channel. rows are 0-based row positions of B (or a boolean
       mask).

ALIGNMENT, COMPARISON and RELATIVE PARAMETERS: see the MATLAB help / README "Reference beat".

TS 2026-10-06 (port of mda_referenceBeat.m, TS 2026-10-05, relative parameters 2026-10-06)
"""
from __future__ import annotations

import datetime as _dt
import math

import numpy as np
import pandas as pd

from ._matlab import Struct, movmean, mround, nanmean, nanmedian, nanstd
from .parameters import PARAMETERS

COMPARE_NAMES = ["refCorrelation", "refRMSDeviation_SD", "refRMSDeviationNorm_SD", "refMaxDeviation_SD",
                 "refMaxDeviationNorm_SD"]
_VFIELDS = ["align", "tGrid", "mean", "sd", "meanNorm", "sdNorm", "nPerPoint", "t50", "tOnset", "tPeak", "amp", "n"]


def mda_referenceBeat(action, *args):
    a = action.lower()
    if a == "create":
        return create(*args)
    if a == "align":
        return align(*args)
    if a == "compare":
        return compare(*args)
    if a == "relative":
        return relative(*args)
    if a == "traces":
        return traces(*args)
    raise ValueError("reference_beat: action 'create', 'align', 'compare', 'relative' or 'traces' expected.")


def _check_align(a):
    a = str(a).lower()
    for v in ("stimulus", "upstroke"):
        if v.startswith(a) and a:
            return v
    raise ValueError(f"reference_beat: alignment must be 'stimulus' or 'upstroke' (not '{a}').")


def _rows(B, rows):
    rows = np.asarray(rows)
    if rows.dtype == bool:
        rows = np.flatnonzero(rows)
    return rows.astype(int).ravel()


# =====================================================================================================
def create(C, B, rows, align_="stimulus"):
    align_ = _check_align(align_) if align_ else "stimulus"
    rows = _rows(B, rows)
    amp = B["amplitude"].to_numpy()
    rows = rows[~np.isnan(amp[rows]) & (amp[rows] > 0)]
    info = _beat_info(C, B)
    rows = rows[~np.isnan(info.t50[rows])]
    if rows.size < 3:
        raise ValueError("reference_beat: at least 3 contractions with an amplitude are needed for a reference "
                         f"(selected: {rows.size}).")
    dt = float(np.median(np.diff(C.t)))
    V = Struct()
    V.upstroke = _variant(B, info, rows, info.t50[rows], 0.0, -0.15, 2.5, dt, "upstroke")
    V.stimulus = None
    tst = B["t_stim"].to_numpy()
    st = rows[~np.isnan(tst[rows])]
    if st.size >= 3:
        lat = float(np.median(info.t50[st] - tst[st]))  # stimulus -> 50 % upstroke
        V.stimulus = _variant(B, info, st, tst[st], lat, min(-0.05, lat - 0.15), lat + 2.5, dt, "stimulus")
    if V.stimulus is None:
        align_ = "upstroke"
    R = Struct()
    R.variants = V
    R.channel = C.channel
    tp = B["t_peak"].to_numpy()
    R.source = f"{rows.size} contractions ({st.size} stimulated), {np.min(tp[rows]):.1f}-{np.max(tp[rows]):.1f} s"
    R.created = _dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    R.params = _param_stats(B, rows)
    R.align = align_
    return align(R, align_)


def _param_stats(B, rows):
    base, _, _ = _relative_names()
    P = Struct(names=list(base), mean=np.full(len(base), np.nan), sd=np.full(len(base), np.nan),
               n=np.zeros(len(base)))
    for k, nm in enumerate(base):
        if nm not in B.columns:
            continue
        v = B[nm].to_numpy(dtype=float)[rows]
        P.mean[k] = nanmean(v)
        P.sd[k] = nanstd(v)
        P.n[k] = np.sum(~np.isnan(v))
    return P


def _relative_names():
    base = [p[0] for p in PARAMETERS if not p[0].startswith("ref")]
    isDiff = [b in ("diastolicForce", "diastolicSignal") for b in base]
    rel = [b + ("_dRef" if d else "_pctRef") for b, d in zip(base, isDiff)]
    return base, rel, isDiff


def relative(B, R):
    """every parameter relative to the reference (NaN without reference / parameter values)."""
    base, rel, isDiff = _relative_names()
    M = np.full((len(B), len(base)), np.nan)
    params = None if R is None else R.get("params")
    if params is not None and len(params) and "names" in params:
        names = list(params["names"])
        pm = np.asarray(params["mean"], dtype=float).ravel()
        for k, nm in enumerate(base):
            if nm not in names or nm not in B.columns:
                continue
            r = pm[names.index(nm)]
            v = B[nm].to_numpy(dtype=float)
            if isDiff[k]:
                M[:, k] = v - r
            elif not math.isnan(r) and r != 0:
                M[:, k] = 100 * v / r
    V = pd.DataFrame(M, columns=rel, index=B.index)
    V.attrs["units"] = {r: ("uN" if d else "%") for r, d in zip(rel, isDiff)}
    return V


def _variant(B, info, rows, anchor, t50, g0, g1, dt, align_):
    """mean +- SD of the contractions rows (time 0 = anchor) on a grid g0 ... g1."""
    tGrid = np.arange(mround(g0 / dt), mround(g1 / dt) + 1) * dt
    nG = tGrid.size
    Y = np.full((nG, rows.size), np.nan)
    YN = Y.copy()
    amp = B["amplitude"].to_numpy()
    for q in range(rows.size):
        y, valid = _beat_trace(B, info, rows[q], anchor[q], tGrid)
        y[~valid] = np.nan
        Y[:, q] = y
        YN[:, q] = y / amp[rows[q]]
    nValid = np.sum(~np.isnan(Y), axis=1)
    m = nanmean(Y, axis=1)
    mN = nanmean(YN, axis=1)
    # window: where at least half of the contractions are available, until 90 % relaxation of the mean + 0.15 s
    ok = nValid >= max(2, 0.5 * rows.size)
    prod = m * ok
    ip = int(np.nanargmax(prod))
    ampM = prod[ip]
    idx = np.arange(nG)
    with np.errstate(invalid="ignore"):
        cand = np.flatnonzero((idx > ip) & (m < 0.1 * ampM))
    iEnd = cand[0] if cand.size else nG - 1
    iEnd = min(nG - 1, iEnd + mround(0.15 / dt))
    bad = np.flatnonzero(~ok[:iEnd + 1] & (idx[:iEnd + 1] > ip))
    if bad.size:
        iEnd = bad[0] - 1
    bad = np.flatnonzero(~ok[:ip + 1])
    iBeg = 0 if bad.size == 0 else bad[-1] + 1
    J = np.arange(iBeg, iEnd + 1)
    W = Struct()
    W.align = align_
    W.tGrid = tGrid[J]
    W.mean = m[J]
    W.sd = nanstd(Y[J], axis=1)
    W.meanNorm = mN[J]
    W.sdNorm = nanstd(YN[J], axis=1)
    W.nPerPoint = nValid[J].astype(float)
    W.t50 = float(t50)
    with np.errstate(invalid="ignore"):
        below = np.flatnonzero(m[iBeg:ip + 1] < 0.1 * ampM)
    W.tOnset = float(tGrid[iBeg]) if below.size == 0 else float(tGrid[iBeg + below[-1]])
    W.tPeak = float(tGrid[ip])
    W.amp = float(ampM)
    W.n = int(rows.size)
    return W


def align(R, align_=""):
    """activate a variant ('' = keep R.align); also converts references of the first version (aligned at the
    upstroke)."""
    if R is None:
        return R
    R = Struct(R)
    if "variants" not in R or R.variants is None:
        W = Struct()
        for f in _VFIELDS:
            W[f] = R.get(f)
        W.align = "upstroke"
        W.t50 = 0.0
        if W.nPerPoint is None or np.size(W.nPerPoint) == 0:
            W.nPerPoint = np.full(np.shape(W.tGrid), np.nan)
        R.variants = Struct(upstroke=W, stimulus=None)
        R.align = "upstroke"
    if not align_:
        align_ = R.align
    align_ = _check_align(align_)
    var = R.variants
    if align_ == "stimulus" and var.get("stimulus") is None:
        raise ValueError("reference_beat: this reference has no stimulus-aligned variant (fewer than 3 stimulated "
                         "contractions); use the alignment 'upstroke'.")
    W = var[align_]
    out = Struct()
    for f in _VFIELDS:
        out[f] = W.get(f)
    out.align = align_
    out.channel = R.get("channel")
    out.source = R.get("source", "")
    out.created = R.get("created", "")
    out.params = R.get("params")  # None: reference before 2026-10-06
    out.variants = Struct(upstroke=var.get("upstroke"), stimulus=var.get("stimulus"))
    return out


def compare(C, B, R):
    n = len(B)
    M = np.full((n, len(COMPARE_NAMES)), np.nan)
    if R is not None and n > 0:
        R = align(R, "")
        info = _beat_info(C, B)
        a = _anchors(B, info, R)
        tG = np.asarray(R.tGrid, dtype=float).ravel()
        Rm = np.asarray(R.mean, dtype=float).ravel()
        Rsd = np.asarray(R.sd, dtype=float).ravel()
        RmN = np.asarray(R.meanNorm, dtype=float).ravel()
        RsdN = np.asarray(R.sdNorm, dtype=float).ravel()
        dtg = float(np.median(np.diff(tG)))
        w = max(1, mround(0.03 / dtg))  # moving mean of the deviation over 30 ms (maximum)
        sdA = np.fmax(Rsd, np.fmax(nanmedian(Rsd), 0.02 * R.amp))  # max ignores NaN, as in MATLAB
        sdN = np.fmax(RsdN, np.fmax(nanmedian(RsdN), 0.02))
        amp = B["amplitude"].to_numpy()
        for k in range(n):
            A = amp[k]
            if np.isnan(A) or A <= 0 or np.isnan(a[k]):
                continue
            y, valid = _beat_trace(B, info, k, a[k], tG)
            valid = valid & ~np.isnan(Rm) & ~np.isnan(Rsd)
            nv = int(np.sum(valid))
            if nv < 0.5 * tG.size or nv < 10:
                continue
            yv = y[valid]
            mv = Rm[valid]
            if _std(yv) > 0 and _std(mv) > 0:
                M[k, 0] = float(np.corrcoef(yv, mv)[0, 1])
            z = (y - Rm) / sdA
            z[~valid] = np.nan
            zN = (y / A - RmN) / sdN
            zN[~valid] = np.nan
            M[k, 1] = math.sqrt(np.mean(z[valid] ** 2))
            M[k, 2] = math.sqrt(np.mean(zN[valid] ** 2))
            M[k, 3] = np.nanmax(np.abs(movmean(z, w)))
            M[k, 4] = np.nanmax(np.abs(movmean(zN, w)))
    return pd.DataFrame(M, columns=COMPARE_NAMES, index=B.index)


def _std(v):
    return float(np.std(v, ddof=1)) if v.size > 1 else 0.0


def traces(C, B, R, rows):
    R = align(R, "")
    info = _beat_info(C, B)
    a = _anchors(B, info, R)
    rows = _rows(B, rows)
    tG = np.asarray(R.tGrid, dtype=float).ravel()
    out = np.full((tG.size, rows.size), np.nan)
    for q, r in enumerate(rows):
        if np.isnan(a[r]):
            continue
        y, valid = _beat_trace(B, info, r, a[r], tG)
        y[~valid] = np.nan
        out[:, q] = y
    return out


def _anchors(B, info, R):
    """time 0 of every contraction on R.tGrid (NaN: no 50 % upstroke found)."""
    a = info.t50 - R.t50  # 50 % upstroke at the 50 % upstroke of the reference
    if R.align == "stimulus":
        ts = B["t_stim"].to_numpy(dtype=float)
        s = ~np.isnan(ts) & ~np.isnan(info.t50)
        a[s] = ts[s]
    return a


def _beat_info(C, B):
    """50 % upstroke time of every contraction; peak times of the neighbouring contractions."""
    n = len(B)
    info = Struct()
    info.t50 = np.full(n, np.nan)
    pkT = np.asarray(C.peakTimes, dtype=float)
    tpk = B["t_peak"].to_numpy(dtype=float)
    loc = {}
    for i, v in enumerate(pkT):
        loc.setdefault(v, i)
    t = np.asarray(C.t, dtype=float)
    f = np.asarray(C.f, dtype=float)
    dts = float(np.median(np.diff(t))) if t.size > 1 else 1.0
    amp = B["amplitude"].to_numpy(dtype=float)
    dsig = B["diastolicSignal"].to_numpy(dtype=float)
    iPeaks = np.asarray(C.iPeaks)
    for k in range(n):
        if tpk[k] not in loc or np.isnan(amp[k]):
            continue
        i = int(iPeaks[loc[tpk[k]]])
        lev = dsig[k] + 0.5 * amp[k]
        lo = max(0, i - mround(3 / dts))
        below = np.flatnonzero(f[lo:i] < lev)
        if below.size == 0:
            continue
        j = below[-1] + lo
        if f[j + 1] == f[j]:
            continue
        info.t50[k] = t[j] + (lev - f[j]) / (f[j + 1] - f[j]) * (t[j + 1] - t[j])
    # all detected peaks (also outside B) as neighbours
    pk = np.sort(pkT)
    info.prevPeak = np.full(n, np.nan)
    info.nextPeak = np.full(n, np.nan)
    pos = {}
    for i, v in enumerate(pk):
        pos.setdefault(v, i)
    for k in range(n):
        p = pos.get(tpk[k])
        if p is None:
            continue
        if p > 0:
            info.prevPeak[k] = pk[p - 1]
        if p < pk.size - 1:
            info.nextPeak[k] = pk[p + 1]
    # time from the 50 % upstroke to the peak (median): the next contraction starts about this much before its peak
    dUp = tpk - info.t50
    dUp = dUp[~np.isnan(dUp)]
    info.riseHalf = float(np.median(dUp)) if dUp.size else 0.1
    if math.isnan(info.riseHalf):
        info.riseHalf = 0.1
    info.t = t
    info.f = f
    info.t0 = float(t[0])
    info.dt = (t[-1] - t[0]) / max(1, t.size - 1)  # uniform sampling (read_mdd)
    info.dsig = dsig
    return info


def _beat_trace(B, info, k, anchor, tGrid):
    """developed force of contraction k on tGrid (relative to its anchor time)."""
    tq = anchor + tGrid
    x = (tq - info.t0) / info.dt  # 0-based position (MATLAB: + 1)
    i0 = np.floor(x)
    fr = x - i0
    nf = info.f.size
    inside = (i0 >= 0) & (i0 < nf - 1)
    y = np.full(tq.shape, np.nan)
    ii = i0[inside].astype(int)
    y[inside] = info.f[ii] * (1 - fr[inside]) + info.f[ii + 1] * fr[inside] - info.dsig[k]
    valid = inside.copy()
    if not np.isnan(info.nextPeak[k]):  # before the upstroke of the next contraction (10 % ~ 2 x (50 % -> peak))
        valid &= tq < info.nextPeak[k] - 2 * info.riseHalf
    if not np.isnan(info.prevPeak[k]):
        valid &= tq > info.prevPeak[k]
    return y, valid


# =====================================================================================================
# .mat files (MATLAB compatible: variable 'referenceBeat', a struct or struct array)
def save_reference(file, R):
    from scipy.io import savemat
    refs = R if isinstance(R, (list, tuple)) else [R]
    recs = [_to_mat(align(r, "")) for r in refs]
    if len(recs) == 1:
        savemat(file, {"referenceBeat": recs[0]}, do_compression=True)
    else:
        arr = np.empty((1, len(recs)), dtype=object)
        for i, r in enumerate(recs):
            arr[0, i] = r
        savemat(file, {"referenceBeat": recs}, do_compression=True)


def _to_mat(x):
    if x is None:
        return np.zeros((0, 0))
    if isinstance(x, dict):
        return {k: _to_mat(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        if all(isinstance(v, str) for v in x):
            arr = np.empty((1, len(x)), dtype=object)
            for i, v in enumerate(x):
                arr[0, i] = v
            return arr
        return np.asarray(x, dtype=float)
    if isinstance(x, np.ndarray):
        if x.ndim == 1:
            return x.reshape(-1, 1).astype(float)
        return x
    return x


def load_reference(file):
    """references of a .mat file (variable referenceBeat; MATLAB or Python); list of Struct."""
    from scipy.io import loadmat
    D = loadmat(file, squeeze_me=True, struct_as_record=False, chars_as_strings=True)
    if "referenceBeat" not in D:
        raise ValueError(f"{file}: no variable 'referenceBeat'.")
    v = D["referenceBeat"]
    items = list(v.ravel()) if isinstance(v, np.ndarray) and v.dtype == object else [v]
    return [align(_from_mat(r), "") for r in items]


def _from_mat(x):
    from scipy.io.matlab import mat_struct
    if isinstance(x, mat_struct):
        return Struct({k: _from_mat(getattr(x, k)) for k in x._fieldnames})
    if isinstance(x, np.ndarray):
        if x.dtype == object:
            return [_from_mat(v) for v in x.ravel()]
        if x.size == 0:
            return None
        if x.dtype.kind in "U":
            return str(x)
        return np.atleast_1d(x.astype(float)).ravel() if x.ndim <= 2 else x
    if isinstance(x, str):
        return x
    if isinstance(x, (np.floating, float, np.integer, int)):
        return float(x)
    return x
