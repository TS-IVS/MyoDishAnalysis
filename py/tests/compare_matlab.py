"""Compare the Python port with the MATLAB MyoDishAnalysis on real recordings and synthetic signals.

    python tests/compare_matlab.py [--data DIR] [--ref DIR] [case ...]

DIR data: the recordings (default: examples/ of the repository); DIR ref: MATLAB results written by
tests/matlab/mda_py_reference_files.m, mda_py_reference_synthetic.m and mda_py_reference_helpers.m (default
tests/reference). Cases: helpers, synthetic, ex1 ... ex9, ex3ref (default: all available).

For every table: number of rows, NaN pattern, text columns identical; numbers within rel. 1e-9 (rocker filter 1e-6).
Prints one line per comparison and a summary; exit code 1 if anything differs.

TS 2026-10-06 (example recordings 2026-10-07)
"""
from __future__ import annotations

import argparse
import math
import os
import sys
import time

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
EXAMPLES = os.path.normpath(os.path.join(HERE, "..", "..", "examples"))
sys.path.insert(0, os.path.join(HERE, "..", "src"))
sys.path.insert(0, HERE)

from matlab_compare import compare_tables, loadmat, table_from_struct  # noqa: E402
import myodish_analysis as mda  # noqa: E402
from myodish_analysis._matlab import Struct  # noqa: E402

FILES = dict(
    ex1="example1_rabbitVentricle.mdd", ex2="example2_rabbitVentricle.mdd", ex3="example3_humanVentricle.mdd",
    ex3ref="example3_humanVentricle.mdd", ex4="example4_humanAtrium.mdd", ex5="example5_pigVentricle.mdd",
    ex6="example6_ratVentricle.mdd", ex7="example7_pigVentricle.mdd", ex8="example8_rabbitVentricle_EP.mdd",
    ex9="example9_ratVentricle.mdd", protocols="example3_humanVentricle.mdd",
)
PROT = {  # key: (example, channels, from, to, keyword options) as in case 'protocols' of mda_py_reference_files.m
    "ffr3": (3, [3, 6], None, None, dict(protocol="FFR")),
    "ffr4": (4, [3, 6], None, None, dict(protocol="FFR", rocker="any")),
    "rp8": (8, 1, None, None, dict(protocol="RP", rocker="any")),
    "st2": (2, [3, 5, 7], None, None, dict(protocol="ST", rocker="any")),
    "pd2": (2, 5, None, None, dict(protocol="PD", rocker="any")),
    "prp7": (7, [1, 3], None, None, dict(protocol="PRP")),
    "prp7any": (7, 3, None, None, dict(protocol="PRP", rocker="any")),
    "rocker1": (1, 5, None, None, dict(protocol="rockerSpeed")),
    "all6": (6, [1, 6], None, None, dict(protocol="all")),
    "log2": (2, 5, 60, 330, dict(groupBy="log:dechargeDuration", rocker="any")),
}
EP_CASES = ("ex8",)
CLI = {  # key: (channels, from, to, keyword options) as in mda_py_reference_files.m
    "ex1": {"all": (None, 0, math.inf, {}), "rocker": ([1, 2, 8], 0, math.inf, dict(rockerFilter=True))},
    "ex2": {"all": (None, 0, math.inf, {})},
    "ex3": {"all": (None, 0, math.inf, {}),
            "ranges": ([3, 6], [60, 400], [120, 460], dict(labels=["a", "b"], rocker="stopped", beats="stimulated")),
            "rocker": (None, 0, math.inf, dict(rockerFilter=True)),
            "thr": (6, 100, 300, dict(threshold=300, downsampling=1, medianFilterMs=20, meanFilterMs=10))},
    "ex4": {"all": (None, 0, math.inf, {}), "ranges": ([2, 3, 5, 6], [0, 780], [60, 870], dict(labels=["baseline", "iso"]))},
    "ex5": {"all": (None, 0, math.inf, {})},
    "ex6": {"all": (None, 0, math.inf, {}), "rocker": ([1, 4, 6], 0, 745, dict(rockerFilter=True))},
    "ex7": {"all": (None, 0, math.inf, {})},
    "ex8": {"all": (None, 0, math.inf, {})},
    "ex9": {"all": (None, 0, math.inf, {})},
}
READER = {"ex1": (300, 330), "ex2": (500, 560), "ex3": (100, 160), "ex4": (50, 110), "ex5": (200, 260),
          "ex6": (1030, 1090), "ex9": (10, 70)}

RESULTS = []


def report(ok, lines, name):
    RESULTS.append((name, ok))
    for ln in lines:
        print("   " + ln)
    print(("OK    " if ok else "DIFF  ") + name)


def to_datenum(ts):
    ts = pd.to_datetime(pd.Series(ts))
    return (ts - pd.Timestamp("1970-01-01")).dt.total_seconds().to_numpy() / 86400.0 + 719529.0


def cmp_cli(X, T, S, info, name, rtol, rocker=False):
    """compare the outputs of myodish_analysis with MATLAB. rocker=True (option rockerFilter): the artifact is a
    least-squares fit (identical to ~1e-12, not bit-identical); after its subtraction the filtered signal has exactly
    flat peaks (two or three equal samples) in a few contractions, whose peak can then be found one (rarely two) samples
    (5 ms) apart. Which peaks move depends on the BLAS library. Such rows (<= 1 %) are counted and excluded from the row-wise
    comparison; summary means within 0.5 %, SDs within 2 %."""
    M = table_from_struct(X.contractions)
    P = T.copy()
    if "clockTime" in P.columns:
        P["clockTime"] = to_datenum(P["clockTime"])
    lines = []
    okS = True
    if rocker and len(M) == len(P):
        d = np.abs(M["t_peak"].to_numpy(float) - P["t_peak"].to_numpy(float))
        shifted = d > 1e-9
        dt = 0.005
        # one sample (on macOS with Accelerate once two samples: three equal samples at the peak)
        okS = bool(np.all(d[shifted] < 2 * dt + 1e-6) and shifted.mean() <= 0.01)
        n2 = int(np.sum(d[shifted] > dt + 1e-6))
        lines.append(f"{name}: {int(shifted.sum())} of {len(M)} contractions ({100 * shifted.mean():.2f} %) with the peak "
                     f"one sample apart{f' ({n2} two samples)' if n2 else ''} (flat peak after the artifact subtraction); "
                     "compared without them")
        # the next contraction of the same channel and range: peakToPeakInterval refers to the shifted peak
        nxt = np.r_[False, shifted[:-1]] & (M["channel"].to_numpy() == np.r_[np.nan, M["channel"].to_numpy()[:-1]])
        for c in ("peakToPeakInterval", "peakToPeakFrequency"):
            M.loc[nxt, c] = np.nan
            P.loc[nxt, c] = np.nan
        M = M[~shifted].reset_index(drop=True)
        P = P[~shifted].reset_index(drop=True)
    ok1, l1 = compare_tables(M, P, name + " contractions", rtol=rtol, atol=rtol, skip=("clockTime",))
    if "clockTime" in M.columns and len(M) == len(P) and len(M):
        dct = np.nanmax(np.abs(M["clockTime"].to_numpy(float) - P["clockTime"].to_numpy(float))) * 86400
        l1.append(f"{name} contractions: clockTime max diff {dct * 1000:.3f} ms")
        ok1 = ok1 and dct < 1e-4
    Ms = table_from_struct(X.summary)
    if rocker:  # SDs react most to the few contractions whose peak moved by one sample (BLAS-dependent)
        sd = [c for c in Ms.columns if c.endswith("_SD") and c in S.columns]
        ok2a, l2a = compare_tables(Ms, S, name + " summary (means)", rtol=5e-3, atol=rtol, skip=sd)
        ok2b, l2b = compare_tables(Ms, S, name + " summary (SDs)", rtol=2e-2, atol=rtol, cols=sd)
        ok2, l2 = ok2a and ok2b, l2a + l2b
    else:
        ok2, l2 = compare_tables(Ms, S, name + " summary", rtol=rtol, atol=rtol)
    Mt = table_from_struct(X.thresholds)
    ok3, l3 = compare_tables(Mt, info["thresholds"], name + " thresholds", rtol=rtol, atol=rtol)
    ok4, l4 = True, []
    if hasattr(X, "rockerFilter"):
        Mr = table_from_struct(X.rockerFilter)
        Pr = info["rockerFilter"].reset_index(drop=True)
        flat = Mr["artifact_uN_peakToPeak"].to_numpy(float) < 1e-6  # constant signal (no sensor): artifact ~1e-11
        if flat.any():
            cc = ["channel", "status", "corrected_percentOfRockerOnTime"]
            okf, lf = compare_tables(Mr[flat].reset_index(drop=True)[cc], Pr[flat].reset_index(drop=True)[cc],
                                     name + " rockerFilter (constant channels)", rtol=1e-6, atol=1e-6)
            l4 += lf + [f"{name} rockerFilter: channel(s) {Mr['channel'][flat].astype(int).tolist()} constant (no sensor "
                        "signal): artifact < 1e-6 uN in both; R2 / size are rounding noise and not compared"]
            ok4 = okf
        okr, lr = compare_tables(Mr[~flat].reset_index(drop=True), Pr[~flat].reset_index(drop=True),
                                 name + " rockerFilter", rtol=1e-6, atol=1e-6)
        ok4 = ok4 and okr
        l4 += lr
    ok5, l5 = True, []
    if hasattr(X, "protocolResults"):
        Mp = table_from_struct(X.protocolResults)
        Pp = info.get("protocolResults")
        if Pp is None:
            ok5, l5 = False, [f"{name} protocolResults: missing in Python"]
        else:
            ok5, l5 = compare_tables(Mp, Pp.reset_index(drop=True), name + " protocolResults", rtol=max(rtol, 1e-9),
                                     atol=max(rtol, 1e-9), skip=("clockTime",))
    report(okS and ok1 and ok2 and ok3 and ok4 and ok5, lines + l1 + l2 + l3 + l4 + l5, name)


def cmp_reader(R, mdd, a, b, name):
    S = mda.read_mdd(mdd, a, b)
    r = R.reader
    lines = []
    ok = True
    for f, pv in (("t", S.t), ("force", S.force), ("rockerOn", S.rockerOn.astype(float)), ("stimTime", S.stim.time),
                  ("stimChannel", S.stim.channel.astype(float)), ("stimCurrent", S.stim.current),
                  ("currentReached", S.stim.currentReached.astype(float))):
        mv = np.atleast_1d(np.asarray(getattr(r, f), dtype=float))
        pv = np.asarray(pv, dtype=float)
        if mv.size != pv.size:
            ok = False
            lines.append(f"{name} reader {f}: size {mv.size} vs {pv.size}")
            continue
        d = np.max(np.abs(mv.ravel() - np.reshape(pv, mv.shape).ravel())) if mv.size else 0.0
        if d > 1e-9 * max(1, np.max(np.abs(mv))):
            ok = False
        lines.append(f"{name} reader {f}: {mv.size} values, max diff {d:.3g}")
    O = mda.read_mdd(mdd, "overview", 2)
    o = R.overview
    for f in ("tBin", "minForce", "maxForce", "rockerFraction"):
        mv = np.asarray(getattr(o, f), dtype=float)
        pv = np.asarray(O[f], dtype=float).reshape(mv.shape)
        d = np.nanmax(np.abs(mv - pv)) if mv.size else 0.0
        okf = d <= 1e-9 * max(1, np.nanmax(np.abs(mv))) and np.array_equal(np.isnan(mv), np.isnan(pv))
        ok = ok and okf
        lines.append(f"{name} overview {f}: {mv.size} values, max diff {d:.3g}")
    E = mda.log_entries(S.logFile)
    Mlog = table_from_struct(R.log)
    E2 = E.copy()
    E2["clockTime"] = to_datenum(E2["clockTime"])
    okl, ll = compare_tables(Mlog, E2, name + " log entries", rtol=1e-12, atol=1e-6)
    report(ok and okl, lines + ll, name + " reader/overview/log")


def _example(data, k):
    import glob
    return sorted(glob.glob(os.path.join(data, f"example{k}_*.mdd")))[0]


def case_protocols(data, ref):
    """protocols found in the log files (find_protocols) and analyses per protocol and group (group_beats)."""
    R = loadmat(os.path.join(ref, "protocols.mat"))["R"]
    print("--- protocols")
    for k in range(1, 10):
        M = table_from_struct(getattr(R, f"list{k}"))
        P = mda.find_protocols(_example(data, k))
        if len(P) == 0 and all(len(M[c]) == 0 or (len(M) == 1 and str(M[c].iloc[0]) in ("", "nan")) for c in M.columns):
            report(True, [f"example {k}: no protocols in both"], f"protocols example {k}")
            continue
        report(*compare_tables(M, P, f"protocols example {k}", rtol=1e-12, atol=1e-9), f"protocols example {k}")
    for key, (k, ch, a, b, kw) in PROT.items():
        t0 = time.time()
        kw2 = dict(kw)
        if a is None:
            T, S, info = mda.myodish_analysis(_example(data, k), ch, quiet=True, **kw2)
        else:
            T, S, info = mda.myodish_analysis(_example(data, k), ch, a, b, quiet=True, **kw2)
        cmp_cli(getattr(R, key), T, S, info, f"protocols/{key} ({time.time() - t0:.1f} s)", 1e-9)


def case_files(case, data, ref):
    if case == "protocols":
        return case_protocols(data, ref)
    R = loadmat(os.path.join(ref, case + ".mat"))["R"]
    mdd = os.path.join(data, FILES[case])
    print(f"--- {case}: {FILES[case]}")
    rtol = 1e-9
    for key, (ch, a, b, kw) in CLI.get(case, {}).items():
        if not hasattr(R, key):
            continue
        t0 = time.time()
        T, S, info = mda.myodish_analysis(mdd, ch, a, b, quiet=True, **kw)
        dt = time.time() - t0
        cmp_cli(getattr(R, key), T, S, info, f"{case}/{key} ({dt:.1f} s)", rtol, rocker=bool(kw.get("rockerFilter")))
    if case in READER:
        cmp_reader(R, mdd, *READER[case], case)
    if case == "ex3ref":
        Rm = R.ref
        S = mda.read_mdd(mdd, 0, 125)
        B, C = mda.analyze_channel(S, 6, [0, 120])
        Rp = mda.reference_beat.create(C, B, np.flatnonzero(B["included"].to_numpy()))
        lines, ok = [], True
        for f in ("tGrid", "mean", "sd", "meanNorm", "sdNorm", "nPerPoint"):
            a = np.asarray(getattr(Rm, f), float)
            b_ = np.asarray(Rp[f], float)
            d = np.nanmax(np.abs(a - b_)) if a.shape == b_.shape else np.inf
            ok = ok and d < 1e-9 * max(1, np.nanmax(np.abs(a)))
            lines.append(f"reference {f}: {a.size} points, max diff {d:.3g}")
        for f in ("t50", "tOnset", "tPeak", "amp", "n"):
            a, b_ = float(getattr(Rm, f)), float(Rp[f])
            ok = ok and abs(a - b_) <= 1e-9 * max(1, abs(a))
            lines.append(f"reference {f}: {a!r} vs {b_!r}")
        report(ok, lines, "ex3ref reference beat (create)")
        # the MATLAB reference (loaded from the .mat) applied by Python
        Rml = mda.reference_beat.align(mda.reference_beat._from_mat(Rm), "")
        for key, (ch, rr) in (("refStim", ([3, 6], Rml)), ("refUp", (6, mda.reference_beat.align(Rml, "upstroke")))):
            T, S2, info = mda.myodish_analysis(mdd, ch, 0, 900, quiet=True, referenceBeat=rr)
            cmp_cli(getattr(R, key), T, S2, info, f"ex3ref/{key} (MATLAB reference)", 1e-9)
    if case in EP_CASES:
        ep_file = os.path.join(data, FILES[case].replace(".mdd", ".mat"))
        H = mda.read_mdd(mdd)
        t0 = time.time()
        EP = mda.read_ep_recording(ep_file, H)
        dt = time.time() - t0
        e = R.ep
        A = EP.align
        lines, ok = [], True
        for f, pv in (("t0", EP.t0), ("dt", EP.dt), ("fs", EP.fs), ("block", EP.block),
                      ("signalChannel", EP.signalChannel), ("stimChannel", EP.stimChannel), ("nV", EP.V.size),
                      ("Vsum", float(np.sum(EP.V.astype(float)))), ("offset", A.offset), ("slope", A.slope),
                      ("nMatched", A.nMatched), ("nSE", A.nSE), ("nMdd", A.nMdd), ("mddChannel", A.mddChannel),
                      ("rms", A.rms), ("clockOffset", A.clockOffset), ("ambiguous", float(A.ambiguous))):
            mv = float(getattr(e, f))
            d = abs(mv - float(pv))
            okf = d <= 1e-9 * max(1, abs(mv)) or (math.isnan(mv) and math.isnan(float(pv)))
            ok = ok and okf
            if not okf or f in ("offset", "slope", "nMatched", "rms"):
                lines.append(f"EP {f}: MATLAB {mv!r}, Python {float(pv)!r}")
        for f, pv in (("stimTimes", EP.stimTimes), ("stimEnds", EP.stimEnds), ("stimAmplitude", EP.stimAmplitude),
                      ("pairs", A.pairs), ("candidates", A.candidates)):
            mv = np.atleast_1d(np.asarray(getattr(e, f), float))
            pv = np.asarray(pv, float)
            if mv.size != pv.size:
                ok = False
                lines.append(f"EP {f}: size {mv.shape} vs {pv.shape}")
                continue
            pv = pv.reshape(mv.shape)
            d = np.nanmax(np.abs(mv - pv)) if mv.size else 0.0
            okf = d <= 1e-7 * max(1, np.nanmax(np.abs(mv))) if mv.size else True
            ok = ok and okf
            lines.append(f"EP {f}: {mv.shape}, max diff {d:.3g}")
        ok = ok and str(e.method) == A.method
        lines.append(f"EP method: '{e.method}' vs '{A.method}'")
        report(ok, lines, f"{case} EP alignment ({dt:.1f} s)")
        ch = int(R.apChannel)
        B, _, _ = mda.myodish_analysis(mdd, ch, 0, math.inf, quiet=True)
        Ap, _ = mda.analyze_ap(EP, B)
        P = pd.concat([B[["t_peak", "t_stim", "beatType"]].reset_index(drop=True), Ap.reset_index(drop=True)], axis=1)
        M = table_from_struct(R.ap)
        okA, lA = compare_tables(M, P, f"{case} AP parameters", rtol=1e-9, atol=1e-9)
        n_ok = int(np.sum(~np.isnan(P["APD90"].to_numpy(float))))
        lA.append(f"{case} AP parameters: {len(P)} contractions, APD90 in {n_ok}, median APD90 "
                  f"{np.nanmedian(P['APD90']):.1f} ms, dV/dt max {np.nanmedian(P['AP_dVdtMax']):.1f} V/s")
        report(okA, lA, f"{case} AP parameters")


def case_helpers(ref):
    from myodish_analysis._matlab import gradient, islocalmax, movmean, movmedian, mround
    D = loadmat(os.path.join(ref, "helpers_reference.mat"))
    lines, ok = [], True
    for k in range(len(D["X"])):
        x = np.atleast_1d(D["X"][k]).astype(float)
        tf, p = islocalmax(x)
        e1 = int(np.sum(tf != np.atleast_1d(D["TF"][k]).astype(bool)))
        e2 = float(np.max(np.abs(p - np.atleast_1d(D["P"][k]))))
        ok = ok and e1 == 0 and e2 == 0
        lines.append(f"islocalmax signal {k + 1} ({x.size}): TF differences {e1}, prominence max diff {e2:.3g}")
    worst = 0.0
    for i, w in enumerate(np.atleast_1d(D["win"])):
        for a, b_ in ((movmedian(D["y"], w), D["MM"][i]), (movmean(D["y"], w), D["MA"][i]),
                      (movmedian(D["z"].astype(float), w), D["MZ"][i]),
                      (movmean(movmedian(D["z"].astype(float), w), 5), D["MZa"][i])):
            if np.any(np.isnan(a) != np.isnan(b_)):
                ok = False
            worst = max(worst, float(np.nanmax(np.abs(a - b_)) / np.nanmax(np.abs(b_))))
    ok = ok and worst < 1e-14
    lines.append(f"movmedian / movmean (windows {list(np.atleast_1d(D['win']))}, NaN, ends): max rel diff {worst:.2g}; "
                 "integer-valued data: identical" if worst < 1e-14 else f"moving windows: max rel diff {worst:.2g}")
    g = float(np.nanmax(np.abs(gradient(D["y"]) - D["G"])))
    r = mround(np.array([-2.5, -1.5, -0.5, 0.5, 1.5, 2.5, 0.49999999999999994]))
    ok = ok and g == 0 and np.array_equal(r, np.asarray(D["R"], float))
    lines.append(f"gradient max diff {g:.3g}; round {r.tolist()} vs {np.asarray(D['R']).tolist()}")
    report(ok, lines, "helpers (islocalmax, movmedian, movmean, gradient, round)")


def case_synthetic(ref):
    D = loadmat(os.path.join(ref, "synthetic_reference.mat"))

    def mkS(T, on=None):
        t = np.asarray(T.t, float)
        onset = np.asarray(T.onset, float)
        S = Struct(dataChannels=np.array([1]), dt=0.005, t=t, force=np.asarray(T.F, float)[None, :],
                   rockerOn=np.zeros(t.size, bool) if on is None else np.asarray(on, bool), fromSeconds=t[0],
                   toSeconds=t[-1])
        S.stim = Struct(time=onset - 0.1, channel=np.ones(onset.size, int))
        return S

    o = mda.options
    T1 = D["T1"]
    B, _ = mda.analyze_channel(mkS(T1), 1, [2, 17], o(noFiltering=True, zeroForce=40))
    report(*compare_tables(table_from_struct(T1.B), B, "exact parameters"), "synthetic: exact parameters (mda_test 1)")
    B, _ = mda.analyze_channel(mkS(T1), 1, [2, 17], o(zeroForce=40))
    report(*compare_tables(table_from_struct(T1.Bfilt), B, "default filters"), "synthetic: default filters")
    T2 = D["T2"]
    S = mkS(T2, T2.on)
    S.rockerSpeedLog = np.array([[-np.inf, 60.0]])
    B0, _ = mda.analyze_channel(S, 1, [5, 195], o(noFiltering=True, zeroForce=40))
    B1, C1 = mda.analyze_channel(S, 1, [5, 195], o(noFiltering=True, zeroForce=40, rockerFilter=True))
    ok1, l1 = compare_tables(table_from_struct(T2.B1), B1, "rocker filter", rtol=1e-9, atol=1e-9)
    d = float(np.max(np.abs(C1.rockerArtifact - T2.artifact)))
    bm = np.atleast_2d(T2.blocks)
    bp = C1.rockerFilter.blocks.copy()
    bp[:, 6:] += 1
    db = float(np.nanmax(np.abs(bm - bp)))
    ok1 = ok1 and d < 1e-9 and db < 1e-9 and C1.rockerFilter.status == T2.status
    l1.append(f"rocker filter: artifact max diff {d:.2g} uN, blocks max diff {db:.2g}, f0 {C1.rockerFilter.f0!r} vs "
              f"{float(T2.f0)!r}, status '{C1.rockerFilter.status}'")
    report(ok1, l1, "synthetic: rocker filter (mda_test 2)")
    T3 = D["T3"]
    S = mkS(T3)
    B, C = mda.analyze_channel(S, 1, [0.5, 59], o(zeroForce=40))
    R = mda.reference_beat.create(C, B, np.atleast_1d(T3.rows).astype(int) - 1)
    BR, _ = mda.analyze_channel(S, 1, [0.5, 59], o(zeroForce=40, referenceBeat=R))
    BU, _ = mda.analyze_channel(S, 1, [0.5, 59], o(zeroForce=40, referenceBeat=mda.reference_beat.align(R, "upstroke")))
    okR, lR = compare_tables(table_from_struct(T3.BR), BR, "reference beat (stimulus)", rtol=1e-9, atol=1e-9)
    okU, lU = compare_tables(table_from_struct(T3.BU), BU, "reference beat (upstroke)", rtol=1e-9, atol=1e-9)
    Y = mda.reference_beat.traces(C, B, R, np.arange(len(B)))
    dy = float(np.nanmax(np.abs(Y - T3.Y)))
    okY = dy < 1e-9 and np.array_equal(np.isnan(Y), np.isnan(T3.Y))
    report(okR and okU and okY, lR + lU + [f"reference traces: max diff {dy:.2g} uN"],
           "synthetic: reference beat (mda_test 3, same noise as MATLAB)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", default=EXAMPLES)
    ap.add_argument("--ref", default=os.path.join(HERE, "reference"))
    ap.add_argument("cases", nargs="*")
    a = ap.parse_args()
    import warnings
    warnings.simplefilter("ignore", RuntimeWarning)
    cases = a.cases or ["helpers", "synthetic"] + list(FILES)
    for c in cases:
        if c == "helpers":
            case_helpers(a.ref)
        elif c == "synthetic":
            case_synthetic(a.ref)
        elif os.path.isfile(os.path.join(a.ref, c + ".mat")) and os.path.isfile(os.path.join(a.data, FILES[c])):
            case_files(c, a.data, a.ref)
        else:
            print(f"--- {c}: skipped (no data or reference)")
    n_ok = sum(1 for _, k in RESULTS if k is True)
    n_bad = sum(1 for _, k in RESULTS if k is False)
    print(f"\n{n_ok} comparisons identical within tolerance, {n_bad} with differences, "
          f"{sum(1 for _, k in RESULTS if k is None)} notes")
    for n, k in RESULTS:
        if k is False:
            print("  DIFF: " + n)
    return 1 if n_bad else 0


if __name__ == "__main__":
    sys.exit(main())
