"""Action potential parameters of an EP recording (membrane potential) for every contraction. Port of mda_analyzeAP.m.

    A, M = analyze_ap(EP, B, **options)     EP from read_ep_recording, B from analyze_channel (same .mdd)
    AP_PARAMETERS                           (name, unit, definition) of the numeric AP columns

A  DataFrame with one row per row of B (append with pd.concat([B, A], axis=1)):
     AP_dVdtMax (V/s), AP_RMP (mV), AP_Vmax (mV), APD25/50/90 (ms), t_AP (s), AP_reference ('upstroke' |
     'stimulus' | ''), AP_note
M  list of Struct (one per row of B) for plots: tOn, tArtEnd, tAct, tPeak, vPeak, tAPD (3), vAPD (3), rmp

Definitions, stimulus artefact handling, fusion: see the MATLAB help / README "AP parameters per contraction".

OPTIONS: artefactSlope (V/s, 20), upstrokeMin (V/s, 20), minAmplitude (mV, 40), maxFoot (0.3), maxLatency (s, 0.1),
maxAPD (s, 2), apdFrom ('auto' | 'stimulus' | 'upstroke'), tolerance (s, 0.015)

TS 2026-10-06 (port of mda_analyzeAP.m, TS 2026-10-06)
"""
from __future__ import annotations

import math

import numpy as np
import pandas as pd

from ._matlab import Struct, gradient, movmean, mround

AP_PARAMETERS = [
    ("AP_dVdtMax", "V/s", "AP: maximum upstroke velocity; NaN if the upstroke lies within the stimulus artefact"),
    ("AP_RMP", "mV", "AP: resting (diastolic) membrane potential, median over 10 ms before the stimulus artefact"),
    ("AP_Vmax", "mV", "AP: maximum voltage (peak); NaN if the peak may lie within the stimulus artefact"),
    ("APD25", "ms", "AP duration: activation (upstroke dV/dt max) --> 25 % repolarization; NaN if the upstroke lies "
     "within the stimulus artefact"),
    ("APD50", "ms", "AP duration: activation --> 50 % repolarization; NaN if the upstroke lies within the stimulus "
     "artefact"),
    ("APD90", "ms", "AP duration: activation --> 90 % repolarization; upstroke within the artefact: from the stimulus "
     "onset, approximate (AP_note)"),
]
AP_COLUMNS = ["AP_dVdtMax", "AP_RMP", "AP_Vmax", "APD25", "APD50", "APD90", "t_AP", "AP_reference", "AP_note"]
_DEFAULTS = dict(artefactSlope=20, upstrokeMin=20, minAmplitude=40, maxFoot=0.3, maxLatency=0.1, maxAPD=2,
                 apdFrom="auto", tolerance=0.015)


def _empty_m():
    return Struct(tOn=math.nan, tArtEnd=math.nan, tAct=math.nan, tPeak=math.nan, vPeak=math.nan,
                  tAPD=np.full(3, np.nan), vAPD=np.full(3, np.nan), rmp=math.nan)


def analyze_ap(EP, B, **kw):
    P = dict(_DEFAULTS)
    for k, v in kw.items():
        m = [n for n in P if n.lower() == k.lower()]
        if not m:
            raise ValueError(f"analyze_ap: unknown option '{k}'.")
        P[m[0]] = v
    P = Struct(P)
    n = len(B)
    num = {c: np.full(n, np.nan) for c in AP_COLUMNS[:7]}
    ref_ = [""] * n
    notes = [""] * n
    M = [_empty_m() for _ in range(n)]

    def table():
        T = pd.DataFrame(num, index=B.index)
        T["AP_reference"] = ref_
        T["AP_note"] = notes
        T.attrs["units"] = {"AP_dVdtMax": "V/s", "AP_RMP": "mV", "AP_Vmax": "mV", "APD25": "ms", "APD50": "ms",
                            "APD90": "ms", "t_AP": "s", "AP_reference": "", "AP_note": ""}
        return T

    if n == 0 or EP is None or EP.get("V") is None or np.size(EP.V) == 0:
        return table(), M

    V = np.asarray(EP.V)
    nV = V.size
    dt = float(EP.dt)
    t0 = float(EP.t0)
    tEP = (t0, t0 + (nV - 1) * dt)

    def idx(t):  # 0-based sample index (MATLAB: 1-based)
        return int(min(nV - 1, max(0, mround((t - t0) / dt))))

    def tOf(k):
        return t0 + k * dt

    sAP = np.asarray(EP.get("stimTimes", np.zeros(0)), dtype=float).ravel()
    sEnd = sAP
    se = EP.get("stimEnds")
    if se is not None and np.size(se) == sAP.size:
        sEnd = np.asarray(se, dtype=float).ravel()
    fsHz = 1 / dt
    w05 = max(1, mround(0.0005 / dt))  # 0.5 ms
    mx = V.max(); mn = V.min()  # amplifier limits: many samples at exactly the extreme
    satHi = math.inf; satLo = -math.inf
    if np.count_nonzero(V == mx) >= 10:
        satHi = float(mx) - 0.5
    if np.count_nonzero(V == mn) >= 10:
        satLo = float(mn) + 0.5
    lev = np.array([0.25, 0.5, 0.9])
    artEndPrev = -math.inf
    tpk_all = B["t_peak"].to_numpy(dtype=float)
    tstim_all = B["t_stim"].to_numpy(dtype=float) if "t_stim" in B.columns else np.full(n, np.nan)
    Rmax = mround(P.maxAPD / dt)
    R02 = mround(0.02 / dt)

    for r in range(n):
        note = []
        tPk = tpk_all[r]
        if tPk < tEP[0] or tPk > tEP[1] + 0.5:
            notes[r] = "outside the EP recording"
            continue
        ts = tstim_all[r]
        j = None
        if not math.isnan(ts) and sAP.size:
            dd = np.abs(sAP - ts)
            j = int(np.argmin(dd))
            if dd[j] > P.tolerance:
                j = None
        if j is None and sAP.size:  # unassigned contraction: EP stimulus before the peak?
            c = np.flatnonzero((sAP < tPk - 0.03) & (sAP > tPk - 0.6))
            if c.size and (r == 0 or sAP[c[-1]] > tpk_all[max(0, r - 1)]):
                j = int(c[-1])

        st = Struct()  # state for the repolarization
        if j is not None:  # ---------------------------------------------------- stimulated AP
            tOn = sAP[j]
            tPe = max(sEnd[j], tOn)
            kOn = idx(tOn)
            tNext = tEP[1] + dt
            if j < sAP.size - 1:
                tNext = sAP[j + 1]
            kEnd = min(nV - 1, idx(tNext) - 1, kOn + Rmax)
            kr = np.arange(max(kOn - mround(0.0105 / dt), 0), kOn - w05 + 1)
            kr = kr[t0 + kr * dt > artEndPrev]
            rmp = math.nan
            if kr.size:
                rmp = float(np.median(V[kr].astype(float)))
            seg = V[kOn:kEnd + 1].astype(float)
            ns = seg.size
            if ns < 3 or math.isnan(rmp):
                notes[r] = "too little EP data"
                continue
            sm = movmean(seg, w05)
            dsm = gradient(sm) / dt / 1000  # V/s (mV/ms)
            sat = (seg >= satHi) | (seg <= satLo)
            iPe = max(0, min(ns - 1, idx(tPe) - kOn))
            cand = np.flatnonzero((np.arange(ns) > iPe) & ~sat & (np.abs(dsm) < P.artefactSlope))
            if cand.size:
                iAe = int(cand[0])
            else:
                iAe = min(ns - 1, iPe + mround(0.03 / dt))
                note.append("artefact not settled")
            tAe = tOf(kOn + iAe)
            artEndPrev = tAe
            M[r].tOn = tOn; M[r].tArtEnd = tAe; M[r].rmp = rmp
            # upstroke after the artefact
            dV = gradient(seg) / dt / 1000
            iw = np.arange(iAe, min(ns, mround(P.maxLatency / dt) + 1))
            clean = False
            iAct = iPk = None
            dmax = math.nan
            if iw.size > 2:
                im = int(iw[np.argmax(dV[iw])])
                dmax = float(dV[im])
                w = seg[im:min(ns - 1, im + R02) + 1]
                ip = im + int(np.argmax(w))
                amp = seg[ip] - rmp
                foot = float(np.min(seg[iAe:im + 1]))
                clean = (dmax >= P.upstrokeMin and im > iAe + 1 and amp >= P.minAmplitude
                         and foot <= rmp + P.maxFoot * amp and not sat[ip])
                if clean:
                    iAct = im; iPk = ip
            if clean:
                num["AP_dVdtMax"][r] = dmax
                num["AP_Vmax"][r] = seg[iPk]
                if fsHz < 5000:
                    num["AP_dVdtMax"][r] = math.nan
                    note.append("dV/dt max needs >= 5 kHz")
                tAct = tOf(kOn + iAct); rf = "upstroke"; vRef = seg[iPk]; iFrom = iPk; pkKnown = True
                if str(P.apdFrom).lower() == "stimulus":
                    tAct = tOn; rf = "stimulus"
            else:
                note.append("upstroke in artefact: APD90 from stimulus, approx.")
                i50 = np.arange(iAe, min(ns - 1, iAe + mround(0.05 / dt)) + 1)
                i50 = i50[~sat[i50]]
                noAP = i50.size == 0
                if not noAP:
                    k = int(np.argmax(seg[i50]))
                    vRef = seg[i50[k]]; iFrom = int(i50[k])
                    v20 = sm[min(ns - 1, iAe + R02)]
                    noAP = vRef - rmp < P.minAmplitude or v20 - rmp < P.minAmplitude / 2
                if noAP:
                    num["AP_RMP"][r] = rmp
                    notes[r] = "no AP"
                    continue
                tAct = tOn; rf = "stimulus"; pkKnown = False
                if str(P.apdFrom).lower() == "upstroke":
                    tAct = math.nan; rf = ""
        else:  # ----------------------------------------------------------------- unstimulated AP (no EP stimulus)
            k1 = idx(max(tPk - 0.6, tEP[0]))
            k2 = idx(tPk - 0.02)
            if r > 0:
                k1 = max(k1, idx(tpk_all[r - 1] + 0.05))
            if k2 - k1 < 10:
                notes[r] = "no AP found"
                continue
            seg0 = V[k1:k2 + 1].astype(float)
            dV0 = gradient(seg0) / dt / 1000
            inArt = np.zeros(seg0.size, bool)  # exclude stimulus artefacts (+30 ms)
            for q in np.flatnonzero((sAP >= tOf(k1) - 0.04) & (sAP <= tOf(k2))):
                a_ = max(0, idx(sAP[q]) - k1)
                b_ = min(seg0.size - 1, idx(sEnd[q] + 0.03) - k1)
                if b_ >= a_:
                    inArt[a_:b_ + 1] = True
            dV0[inArt] = -math.inf
            im = int(np.argmax(dV0))
            dmax = float(dV0[im])
            if dmax < P.upstrokeMin:
                notes[r] = "no AP found"
                continue
            kAct = k1 + im
            iFc = np.flatnonzero(dV0[:im + 1] < 0.1 * dmax)
            iF = int(iFc[-1]) if iFc.size else 0
            kF = k1 + iF
            kr = np.arange(max(0, kF - mround(0.0105 / dt)), kF - w05 + 1)
            if kr.size == 0:
                notes[r] = "no AP found"
                continue
            rmp = float(np.median(V[kr].astype(float)))
            kEnd = min(nV - 1, kAct + Rmax)
            nx = np.flatnonzero(sAP > tOf(kAct))
            if nx.size:
                kEnd = min(kEnd, idx(sAP[nx[0]]) - 1)
            seg = V[kF:kEnd + 1].astype(float)
            ns = seg.size
            sm = movmean(seg, w05)
            sat = (seg >= satHi) | (seg <= satLo)
            iAct = kAct - kF
            w = seg[iAct:min(ns - 1, iAct + R02) + 1]
            iPk = iAct + int(np.argmax(w))
            if seg[iPk] - rmp < P.minAmplitude or sat[iPk]:
                num["AP_RMP"][r] = rmp
                notes[r] = "no AP found"
                continue
            kOn = kF
            num["AP_dVdtMax"][r] = dmax
            num["AP_Vmax"][r] = seg[iPk]
            if fsHz < 5000:
                num["AP_dVdtMax"][r] = math.nan
                note.append("dV/dt max needs >= 5 kHz")
            tAct = tOf(kAct); rf = "upstroke"; vRef = seg[iPk]; iFrom = iPk; pkKnown = True
            M[r].rmp = rmp

        # ------------------------------------------------------------------ repolarization
        num["AP_RMP"][r] = rmp
        num["t_AP"][r] = tAct
        ref_[r] = rf
        M[r].tAct = tAct
        M[r].tPeak = tOf(kOn + iFrom)
        M[r].vPeak = float(vRef)
        if not math.isnan(num["AP_Vmax"][r]):
            M[r].vPeak = float(num["AP_Vmax"][r])
        Lv = vRef - lev * (vRef - rmp)
        qq = [0, 1, 2] if pkKnown else [2]  # peak unknown: APD25 / APD50 not evaluable
        for qn in qq:
            hit = np.flatnonzero(sm[iFrom:ns] <= Lv[qn])
            i = iFrom + int(hit[0]) if hit.size else None
            if i is None or i <= 0:
                pct = int(mround(100 * lev[qn]))
                if kOn + ns < nV and ns - 1 < Rmax:
                    note.append(f"next stimulus before APD{pct}")
                else:
                    note.append(f"no APD{pct}")
                continue
            fr = (sm[i - 1] - Lv[qn]) / (sm[i - 1] - sm[i])  # linear interpolation
            tx = tOf(kOn + i - 1) + fr * dt
            M[r].tAPD[qn] = tx
            M[r].vAPD[qn] = Lv[qn]
            num[f"APD{int(mround(100 * lev[qn]))}"][r] = 1000 * (tx - tAct)
        uniq = []
        for x in note:
            if x not in uniq:
                uniq.append(x)
        nxt = [x for x in uniq if x.startswith("next stimulus before APD")]
        if nxt:  # one note: the first level not reached
            uniq = [x for x in uniq if not x.startswith("next stimulus before APD")] + nxt[:1]
        notes[r] = "; ".join(uniq)

    # RMP not diastolic (stimulated before repolarization of the previous AP)
    rm = num["AP_RMP"]
    if np.any(~np.isnan(rm)):
        med = float(np.nanmedian(rm))
        with np.errstate(invalid="ignore"):
            hi = np.flatnonzero(rm > med + 10)
        for r in hi:
            s = "; ".join(["RMP not diastolic", notes[r]])
            if s.endswith("; "):
                s = s[:-2]
            notes[r] = s
    return table(), M
