"""Read an EP recording (LabChart .mat export) and align it to a MyoDish .mdd file. Port of mda_readEPRecording.m.

    EP = read_ep_recording(ep_file, H)              H = read_mdd(mdd_file) (file facts) or the .mdd file name
    EP = read_ep_recording(ep_file, H, opts)        opts from options() (used to read the .mdd stimuli)
    EP = read_ep_recording(ep_file, H, opts, signalChannel=..., stimChannel=..., block=..., mddChannel=...,
                           stimThreshold='auto', timeOffset=None, tolerance=0.01, fitDrift=True)

The recording is placed on the time axis of the .mdd file by matching the stimulus pulses of the LabChart
stimulation channel with the stimulus pulses in the status channel of the .mdd file:
    t_mdd = t0 + slope * t_LabChart   (t_LabChart = 0 at the first sample of the block)
ALIGNMENT, OPTIONS and OUTPUT: see the MATLAB help / README "EP recordings". Block and channel numbers are 1-based as
in LabChart and MATLAB (EP.block, EP.signalChannel, EP.stimChannel).

OUTPUT (EP, a Struct): file, titles, signalChannel, stimChannel, block, nBlocks, fs, duration, t0, dt, V (float32,
unitV; V and uV are converted to mV), labelV, stim, unitStim, labelStim, stimTimes, stimEnds, stimAmplitude,
comments (DataFrame time, text), align (offset, slope, method, nMatched, nSE, nMdd, mddChannel, rms, clockOffset,
ambiguous, check, pairs, candidates), info (list of text lines), message.

TS 2026-10-06 (port of mda_readEPRecording.m, TS 2026-10-06)
"""
from __future__ import annotations

import math
import os

import numpy as np
import pandas as pd

from ._matlab import Struct, colon, mround
from .options import options as _options
from .read_mdd import read_mdd, read_data

_DEFAULTS = dict(signalChannel=None, stimChannel=None, block=None, mddChannel=None, stimThreshold="auto",
                 timeOffset=None, tolerance=0.01, fitDrift=True)


# ----------------------------------------------------------------------------------------------- LabChart .mat
def load_labchart_mat(file):
    """the variables of a LabChart MATLAB export as a dict of numpy arrays (MAT v5/v7 with scipy, v7.3 with h5py).
    Character matrices (titles, unittext, comtext) are returned as lists of strings (one per row)."""
    try:
        from scipy.io import loadmat
        D = loadmat(file, squeeze_me=False, chars_as_strings=True)
        out = {k: v for k, v in D.items() if not k.startswith("__")}
        for k in ("titles", "unittext", "comtext"):
            if k in out:
                out[k] = _char_rows(out[k])
        return out
    except NotImplementedError:  # v7.3 (HDF5)
        import h5py
        out = {}
        with h5py.File(file, "r") as F:
            for k in F.keys():
                ds = F[k]
                if not isinstance(ds, h5py.Dataset):
                    continue
                a = np.array(ds).T  # MATLAB column-major
                if ds.attrs.get("MATLAB_class", b"") in (b"char",):
                    a = ["".join(chr(c) for c in row) for row in np.atleast_2d(a)]
                out[k] = a
        return out


def _char_rows(a):
    a = np.asarray(a)
    if a.dtype.kind == "U":
        return [str(s) for s in a.ravel()]
    if a.dtype == object:
        return [str(np.asarray(s).ravel()[0]) if np.size(s) else "" for s in a.ravel()]
    return [str(s) for s in a.ravel()]


# =====================================================================================================
def read_ep_recording(ep_file, H, opts=None, **kw):
    if opts is None:
        opts = _options()
    P = dict(_DEFAULTS)
    for k, v in kw.items():
        if k.lower() == "vmchannel":
            k = "signalChannel"
        m = [n for n in P if n.lower() == k.lower()]
        if not m:
            raise ValueError(f"read_ep_recording: unknown option '{k}'.")
        P[m[0]] = v
    P = Struct(P)
    if isinstance(H, (str, os.PathLike)):
        H = read_mdd(str(H), None, None, opts)
    ep_file = str(ep_file)
    nm = os.path.basename(ep_file)
    if os.path.splitext(nm)[1].lower() != ".mat":
        raise ValueError(f"{nm}: a LabChart export (.mat) is expected.")
    L = load_labchart_mat(ep_file)
    need = ["data", "datastart", "dataend", "titles", "samplerate"]
    if not all(k in L for k in need):
        raise ValueError(f"{nm} is not a LabChart .mat export (variables data, datastart, dataend, titles, "
                         "samplerate).")
    titles = [s.strip() for s in L["titles"]]
    datastart = np.atleast_2d(np.asarray(L["datastart"], dtype=float))
    dataend = np.atleast_2d(np.asarray(L["dataend"], dtype=float))
    samplerate = np.atleast_2d(np.asarray(L["samplerate"], dtype=float))
    data = np.asarray(L["data"]).ravel()
    nCh, nBl = datastart.shape
    vm = _pick_channel(P.signalChannel, titles, ["potential", "membran", "vm", "voltage"], 1)
    sc = _pick_channel(P.stimChannel, titles, ["stim"], nCh)
    if sc == vm and nCh > 1:
        raise ValueError(f"Signal and stimulation are the same LabChart channel ({vm}).")
    blockTimes = np.full(nBl, np.nan)
    if "blocktimes" in L:
        bt = np.asarray(L["blocktimes"], dtype=float).ravel()
        blockTimes[:bt.size] = bt
    has = (datastart[vm - 1] > 0) & (dataend[vm - 1] >= datastart[vm - 1])
    if not has.any():
        raise ValueError(f"{nm}: no data in channel {vm} ({titles[vm - 1]}).")
    rs = H.recordingStart if H.recordingStart is not None else math.nan
    clockStart = (blockTimes - rs) * 86400  # s, .mdd time of the block start by the clocks
    dur = (dataend[vm - 1] - datastart[vm - 1] + 1) / samplerate[vm - 1]
    if P.block is None:
        with np.errstate(invalid="ignore"):
            ov = np.minimum(clockStart + dur, H.totalSeconds) - np.maximum(clockStart, 0)
        ov[~has | np.isnan(ov)] = -np.inf
        b = int(np.argmax(ov))
        if not ov[b] > 0:
            b = int(np.flatnonzero(has)[0])
        b += 1
    else:
        b = int(P.block)
        if b < 1 or b > nBl or not has[b - 1]:
            raise ValueError(f"{nm}: block {b} has no data.")
    bi = b - 1
    fs = float(samplerate[vm - 1, bi])
    V = data[int(datastart[vm - 1, bi]) - 1:int(dataend[vm - 1, bi])]
    V, unitV = _to_milli(V, _unit_of(L, vm, b))
    if datastart[sc - 1, bi] > 0 and samplerate[sc - 1, bi] == fs:
        X = data[int(datastart[sc - 1, bi]) - 1:int(dataend[sc - 1, bi])]
        unitStim = _unit_of(L, sc, b)
    else:
        X = np.zeros(0, np.float32)
        unitStim = ""
    V = np.asarray(V).astype(np.float32).ravel()
    X = np.asarray(X).astype(np.float32).ravel()
    prior = clockStart[bi]
    if "firstsampleoffset" in L and "tickrate" in L:
        tick = np.asarray(L["tickrate"], dtype=float).ravel()
        if tick.size >= b and tick[bi] > 0:
            fso = np.atleast_2d(np.asarray(L["firstsampleoffset"], dtype=float))
            prior = prior + fso[vm - 1, bi] / tick[bi]

    # ---------------------------------------------------------------- stimuli
    tA, ampA, tEndA = _detect_stim(X, fs, P.stimThreshold)
    A = Struct(offset=0.0, slope=1.0, method="", nMatched=0, nSE=tA.size, nMdd=0, mddChannel=math.nan, rms=math.nan,
               clockOffset=math.nan, ambiguous=False, pairs=np.zeros((0, 2)), candidates=np.zeros((0, 4)))
    if P.timeOffset is not None:
        to = np.atleast_1d(np.asarray(P.timeOffset, dtype=float)).ravel()
        A.offset = float(to[0])
        A.method = "fixed offset (option timeOffset)"
        if to.size > 1:
            A.slope = float(to[1])
        st = _mdd_stimuli(H, opts, [max(0.0, A.offset - 10), min(H.totalSeconds, A.offset + dur[bi] + 10)])
        k = np.ones(st.time.size, bool)
        if P.mddChannel is not None and np.any(st.channel == P.mddChannel):
            k = st.channel == P.mddChannel
            A.mddChannel = P.mddChannel
        tB = np.unique(st.time[k])
        A.nMdd = tB.size
        if tB.size and tA.size:
            edges = np.r_[-np.inf, (tB[:-1] + tB[1:]) / 2, np.inf]
            ia, _, d = _match_at(tA, tB, edges, A.offset, A.slope, P.tolerance)
            A.nMatched = ia.size
            A.rms = math.sqrt(np.mean(d ** 2)) if d.size else math.nan
    else:
        rg = [0.0, H.totalSeconds]
        if math.isfinite(prior):
            rg = [max(0.0, prior - 1800), min(H.totalSeconds, prior + dur[bi] + 1800)]
        st = _mdd_stimuli(H, opts, rg)
        A = _match_channels(A, tA, ampA, st, prior, P)
        if A.nMatched < _min_matches(tA.size, A.nMdd) and math.isfinite(prior) and (rg[0] != 0 or
                                                                                   rg[1] != H.totalSeconds):
            st = _mdd_stimuli(H, opts, [0.0, H.totalSeconds])  # clock times wrong? whole file
            A = _match_channels(A, tA, ampA, st, prior, P)
        if A.nMatched < _min_matches(tA.size, A.nMdd):
            A.ambiguous = True
            if math.isfinite(prior):
                A.offset = prior; A.slope = 1.0
                A.method = f"clock times (only {A.nMatched} of {tA.size} stimuli matched)"
            else:
                A.offset = 0.0; A.slope = 1.0
                A.method = f"NOT ALIGNED: offset 0 ({A.nMatched} of {tA.size} stimuli matched, no clock times)"
    if math.isfinite(prior):
        A.clockOffset = prior - A.offset
    A.check = []
    if P.timeOffset is None and A.ambiguous and A.nMatched >= _min_matches(tA.size, A.nMdd):
        A.check.append("shifts by a stimulus interval match as well")
    tm = A.offset + A.slope * tA
    nIn = int(np.count_nonzero((tm >= 0) & (tm <= H.totalSeconds)))
    if A.nMdd > 0 and nIn > 0 and A.nMatched < 0.8 * nIn:
        A.check.append(f"only {A.nMatched} of {nIn} LabChart stimuli within the .mdd recording matched")
    if P.timeOffset is None and abs(A.clockOffset) > 60:
        A.check.append(f"clock times differ by {A.clockOffset:.0f} s (wrong file?)")

    # ---------------------------------------------------------------- output
    EP = Struct()
    EP.file = ep_file; EP.titles = titles; EP.signalChannel = vm; EP.stimChannel = sc
    EP.block = b; EP.nBlocks = nBl; EP.fs = fs; EP.duration = V.size / fs
    EP.t0 = A.offset; EP.dt = A.slope / fs
    EP.V = V; EP.unitV = unitV; EP.labelV = _axis_label(titles[vm - 1]); EP.stim = X; EP.unitStim = unitStim
    EP.labelStim = _axis_label(titles[sc - 1])
    EP.stimTimes = A.offset + A.slope * tA
    EP.stimAmplitude = ampA
    EP.stimEnds = A.offset + A.slope * tEndA
    EP.comments = _read_comments(L, b, A)
    EP.align = A
    tEnd = EP.t0 + (V.size - 1) * EP.dt
    info = [nm, f"{titles[vm - 1]} ({unitV}) | {titles[sc - 1]} ({unitStim})",
            f"{fs / 1000:g} kHz, {EP.duration:.1f} s, block {b} of {nBl}", f".mdd time {EP.t0:.2f} - {tEnd:.2f} s",
            "", "Alignment to the .mdd stimuli:"]
    if A.nMdd == 0:
        info.append(f"{tA.size} LabChart stimuli, no .mdd stimuli")
    elif isinstance(A.mddChannel, float) and math.isnan(A.mddChannel):
        info.append(f"{A.nMatched} of {tA.size} stimuli matched (.mdd: {A.nMdd})")
    else:
        info.append(f"{A.nMatched} of {tA.size} stimuli matched (ch {int(A.mddChannel)}: {A.nMdd})")
    info.append(f"offset {A.offset:.4f} s, drift {(A.slope - 1) * 1e6:+.0f} ppm, rms {A.rms * 1000:.1f} ms")
    info.append(A.method)
    if math.isfinite(A.clockOffset):
        info.append(f"clock times differ by {A.clockOffset:+.2f} s")
    for c in A.check:
        info.append("CHECK: " + c)
    if len(EP.comments):
        info.append(f"{len(EP.comments)} LabChart comments")
    if nBl > 1:
        info.append(f"({nBl} blocks in the file)")
    EP.info = info
    EP.message = (f"EP recording {nm}: {A.nMatched}/{tA.size} stimuli matched, offset {A.offset:.3f} s "
                  f"({A.method}).")
    if A.check:
        EP.message = "CHECK (" + "; ".join(A.check) + ") " + EP.message
        print(EP.message)
        if A.candidates.shape[0]:
            print("Candidate offsets [offset (s), matched stimuli, R2 amplitude~current, drift (ppm)]:")
            print(A.candidates[:10])
    return EP


# =====================================================================================================
def _pick_channel(v, titles, keys, dflt):
    if v is not None and not isinstance(v, str):
        return int(v)
    if isinstance(v, str):
        keys = [v]
    for k in keys:
        for j, t in enumerate(titles):
            if k.lower() in t.lower():
                return j + 1
    if isinstance(v, str):
        raise ValueError(f"No LabChart channel title contains '{v}'.")
    return dflt


def _axis_label(t):
    lt = t.lower()
    if "membran" in lt or lt == "vm":
        return "V_m"
    if "stim" in lt:
        return "stim."
    if len(t) > 14:
        return t[:13] + "."
    return t


def _unit_of(L, ch, b):
    if "unittext" in L and "unittextmap" in L:
        m = np.atleast_2d(np.asarray(L["unittextmap"], dtype=float))
        k = int(m[ch - 1, b - 1])
        if k > 0:
            return L["unittext"][k - 1].strip()
    return ""


def _to_milli(x, u):
    x = np.asarray(x)
    if u == "V":
        return x * x.dtype.type(1000) if x.dtype.kind == "f" else x * 1000.0, "mV"
    if u in ("µV", "uV"):
        return x / x.dtype.type(1000) if x.dtype.kind == "f" else x / 1000.0, "mV"
    return x, u


def _detect_stim(x, fs, thr):
    """onsets and ends (s) and amplitudes of the pulses of the stimulation channel (biphasic pulse = one pulse)."""
    t = np.zeros(0); amp = np.zeros(0); tEnd = np.zeros(0)
    if x.size == 0:
        return t, amp, tEnd
    x = np.asarray(x, dtype=np.float32)
    x = np.abs(x - np.median(x).astype(np.float32))
    if isinstance(thr, str):
        thr = np.float32(max(np.float32(20 * 1.4826) * np.median(x).astype(np.float32),
                             np.float32(0.05) * np.max(x)))
        if thr == 0:
            return t, amp, tEnd
    a = x > thr
    if fs >= 4000:  # >= 2 samples: no single-sample spikes
        a = a & (np.r_[a[1:], False] | np.r_[False, a[:-1]])
    idx = np.flatnonzero(a)
    if idx.size == 0:
        return t, amp, tEnd
    first = np.r_[True, np.diff(idx) > mround(0.01 * fs)]  # pulses closer than 10 ms are one pulse
    g = np.cumsum(first) - 1
    t = idx[first] / fs
    tEnd = idx[np.r_[first[1:], True]] / fs
    amp = np.full(int(g[-1]) + 1, -np.inf)
    np.maximum.at(amp, g, x[idx].astype(float))
    return t, amp, tEnd


def _mdd_stimuli(H, opts, rg):
    """stimulus pulses of the .mdd file in the time range rg (s), read in parts of one hour."""
    st = Struct(time=np.zeros(0), channel=np.zeros(0), current=np.zeros(0))
    if not H.hasStimChannel:
        return st
    T, Ch, Cu = [], [], []
    for a in colon(rg[0], 3600, rg[1]):
        S = read_data(H, a, min(rg[1], a + 3600), opts.downsampling, stim_only=True)
        T.append(S.stim.time); Ch.append(S.stim.channel); Cu.append(S.stim.current)
    time = np.concatenate(T) if T else np.zeros(0)
    ch = np.concatenate(Ch).astype(float) if Ch else np.zeros(0)
    cu = np.concatenate(Cu) if Cu else np.zeros(0)
    key = time + 1e-6 * ch  # parts may overlap by one sample
    u, k = np.unique(key, return_index=True)
    st.time = u - 1e-6 * ch[k]
    st.channel = ch[k]
    st.current = cu[k]
    return st


def _min_matches(nA, nB):
    return max(3, math.ceil(0.3 * min(nA, nB)))


def _match_channels(A, tA, ampA, st, prior, P):
    """best alignment over the MyoDish channels with stimuli (P.mddChannel first: preferred on ties)."""
    chs = list(np.unique(st.channel))
    if P.mddChannel is not None and P.mddChannel in chs:
        chs = [P.mddChannel] + [c for c in chs if c != P.mddChannel]
    best = None
    for c in chs:
        k = st.channel == c
        tB = st.time[k]; cB = st.current[k]
        keep = np.r_[True, np.diff(tB) > 0.005]  # one pulse = one stimulus
        R = _align_stim(tA, ampA, tB[keep], cB[keep], prior, P.tolerance, P.fitDrift)
        R.mddChannel = c
        if best is None or R.nMatched > best.nMatched:
            best = R
    A = Struct(A)
    if best is None:
        A.nMdd = 0
        return A
    for k, v in best.items():
        A[k] = v
    return A


def _align_stim(tA, ampA, tB, cB, prior, tol, fitDrift):
    tA = np.asarray(tA, float).ravel(); tB = np.asarray(tB, float).ravel()
    ampA = np.asarray(ampA, float).ravel(); cB = np.asarray(cB, float).ravel()
    nA, nB = tA.size, tB.size
    R = Struct(offset=math.nan, slope=1.0, method="", nMatched=0, nMdd=nB, rms=math.nan, ambiguous=False,
               pairs=np.zeros((0, 2)), candidates=np.zeros((0, 3)))
    if nA == 0 or nB == 0:
        return R
    # histogram of all differences tB - tA (bins of width tol), in parts of <= 2e6 differences
    dmin = tB.min() - tA.max() - tol
    dmax = tB.max() - tA.min() + tol
    nb = math.ceil((dmax - dmin) / tol) + 1
    h = np.zeros(nb)
    step = max(1, math.floor(2e6 / nB))
    for i in range(0, nA, step):
        D = tB[:, None] - tA[None, i:min(nA, i + step)]
        bins = np.floor((D.ravel(order="F") - dmin) / tol).astype(np.int64)
        h += np.bincount(bins, minlength=nb)[:nb]
    h2 = h + np.r_[h[1:], 0]  # a matching difference may fall on either side of a bin edge
    isMax = (h2 >= np.r_[0, h2[:-1]]) & (h2 >= np.r_[h2[1:], 0]) & (h2 >= max(2, 0.5 * h2.max()))
    cand = np.flatnonzero(isMax)
    if cand.size == 0:
        return R
    o = np.argsort(-h2[cand], kind="stable")
    cand = cand[o[:min(o.size, 300)]]
    off0 = dmin + (cand + 1) * tol  # centre of the two bins (MATLAB: 1-based bin index)
    nc = off0.size
    C = np.zeros((nc, 4))
    keepR = []
    for i in range(nc):
        n, off, sl, rms, pr, ia, ib = _eval_offset(tA, tB, off0[i], tol, fitDrift)
        C[i] = [off, n, _r2_current(ampA[ia], cB[ib]), (sl - 1) * 1e6]
        keepR.append((sl, rms, pr))
    o = np.lexsort((np.abs(C[:, 0] - prior), -C[:, 1]))  # sortrows([-n, |offset - prior|]), stable
    C = C[o]; keepR = [keepR[i] for i in o]
    _, u = np.unique(mround(C[:, 0] / tol), return_index=True)  # refined candidates may coincide
    u = np.sort(u)
    C = C[u]; keepR = [keepR[i] for i in u]
    R.candidates = C
    nBest = C[0, 1]
    comp = np.flatnonzero(C[:, 1] >= nBest - max(2, math.ceil(0.05 * nBest)))
    how = "stimulus pattern"
    if comp.size > 1:
        r2 = C[comp, 2]
        if np.any(~np.isnan(r2)):
            with np.errstate(invalid="ignore"):
                good = comp[r2 >= np.nanmax(r2) - 0.01]
            if good.size < comp.size:
                how = "stimulus pattern + current"
            comp = good
    if comp.size > 1 and math.isfinite(prior):
        d = np.abs(C[comp, 0] - prior)
        o = np.argsort(d, kind="stable")
        ds = d[o]
        if ds[0] < 0.5 * ds[1]:
            comp = comp[o[:1]]
            how += " + clock times"
    if comp.size > 1:
        R.ambiguous = True
    pick = comp[0]
    R.offset = float(C[pick, 0]); R.nMatched = int(C[pick, 1])
    R.slope, R.rms, R.pairs = keepR[pick]
    R.method = how
    return R


def _eval_offset(tA, tB, off, tol, fitDrift):
    """matched stimuli, starting at offset off: the matched region grows with every refinement (median of the
    differences, with fitDrift a straight line through the matched stimuli, so that clock drift is followed)."""
    sl = 1.0
    nPrev = -1
    edges = np.r_[-np.inf, (tB[:-1] + tB[1:]) / 2, np.inf]
    for it in range(1, 16):
        ia, ib, d = _match_at(tA, tB, edges, off, sl, tol)
        n = ia.size
        if n == 0 or (n == nPrev and it > 2):
            break
        nPrev = n
        if fitDrift and n >= 10 and tA[ia].max() - tA[ia].min() >= 30:
            p = np.polyfit(tA[ia], tB[ib], 1)
            if abs(p[0] - 1) < 0.002:
                sl = float(p[0]); off = float(p[1])
                continue
        off = off + float(np.median(d))
    ia, ib, d = _match_at(tA, tB, edges, off, sl, tol)
    n = ia.size
    rms = math.sqrt(np.mean(d ** 2)) if n else math.nan
    pairs = np.c_[tA[ia], tB[ib]]
    return n, off, sl, rms, pairs, ia, ib


def _match_at(tA, tB, edges, off, sl, tol):
    """nearest .mdd stimulus of every LabChart stimulus (one .mdd stimulus per LabChart stimulus), |diff| <= tol."""
    x = off + sl * tA
    ib = np.searchsorted(edges, x, side="right") - 1
    ib = np.clip(ib, 0, tB.size - 1)
    d = tB[ib] - x
    ia = np.flatnonzero(np.abs(d) <= tol)
    ib = ib[ia]; d = d[ia]
    o = np.argsort(np.abs(d), kind="stable")
    _, u = np.unique(ib[o], return_index=True)
    k = np.sort(o[u])
    return ia[k], ib[k], d[k]


def _r2_current(amp, cur):
    """fraction of the variance of the LabChart pulse amplitude explained by the stimulus current level."""
    if amp.size < 6 or np.unique(cur).size < 2:
        return math.nan
    _, g = np.unique(cur, return_inverse=True)
    g = g.ravel()
    mu = np.bincount(g, weights=amp) / np.bincount(g)
    sst = np.sum((amp - np.mean(amp)) ** 2)
    if sst > 0:
        return float(1 - np.sum((amp - mu[g]) ** 2) / sst)
    return math.nan


def _read_comments(L, b, A):
    T = pd.DataFrame({"time": pd.Series([], dtype=float), "text": pd.Series([], dtype=object)})
    if "com" not in L or np.size(L["com"]) == 0 or "comtext" not in L or "tickrate" not in L:
        return T
    try:
        com = np.atleast_2d(np.asarray(L["com"], dtype=float))
        c = com[com[:, 1] == b]
        if c.shape[0] == 0:
            return T
        tick = np.asarray(L["tickrate"], dtype=float).ravel()
        t = A.offset + A.slope * c[:, 2] / tick[b - 1]
        txt = [L["comtext"][int(k) - 1].strip() for k in c[:, 4]]
        return pd.DataFrame({"time": t, "text": txt})
    except Exception:
        return T
