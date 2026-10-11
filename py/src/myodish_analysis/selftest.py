# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Self test of the parameter calculation with synthetic contractions of known shape. Port of mda_test.m.

    ok = selftest()          prints expected and calculated values, returns True if all agree
    python -m myodish_analysis.selftest      (or: mda-test)

Synthetic signal (no filtering): diastolic signal 100 uN (zero force 40 uN --> diastolic force 60 uN), linear rise by
1000 uN within 200 ms, linear relaxation within 400 ms, one contraction per second, stimulus 100 ms before the onset.
For this shape all parameters can be calculated by hand (linear interpolation of the level crossings is exact):
  riseTime10_90 = 0.8*0.2, TTP90 = 0.9*0.2, TTR50 = 0.5*0.4, TTR90 = 0.9*0.4, CD50 = 0.1+0.2,
  CD90 = 0.18+0.36, dF/dt = 1000/0.2 and -1000/0.4, AUC = 0.5*0.6*1000 - 0.5*0.02*100 - 0.5*0.04*100 = 297
Rocker filter: the same contractions every 2 s with a periodic rocker artifact (30 % of the amplitude); with the
option rockerFilter amplitude, TTP90, TTR90 and diastolic force must be recovered (0.5 %, 2 ms, 2 uN).
Reference beat: shoulder, partial response, slow relaxation and (aligned at the stimulus) a 40 ms longer latency must
deviate by > 5 SD, normal beats < 3 SD (normalized); the partial response (half amplitude, same shape) only in the
absolute deviation, the longer latency not when aligned at the 50 % upstroke. The noise is drawn with numpy (the
MATLAB test uses rng(3)); the criteria are the same. tests/compare_matlab.py compares with MATLAB on identical signals.
Stimulation pause: after a 9 s pause with rocker movement until 1.2 s before the stimulus, F_dia (amplitude 1000 uN)
and the rocker state of the first contraction come from the 0.5 s before its stimulus (option pauseDiastoleWindow).
External trigger pulses: a temporary 9-channel .mdd file with external trigger pulses only (status bit 14 without
channel / current): read as channel 0, one entry per pulse, stimuli with option externalTrigger 'auto' / 'on'.
Rocker peaks (option rockerArtifacts): rocker movement only, every 4th stimulus answered, every stimulus answered.
Uncertain contractions (option detection): small peaks between the contractions, not locked to the stimuli.
Extra pulses (status channel bit 16): onset gate, pre- / post-pulses, pulse table (extra_pulse_test, port of
mda_testExtraPulses.m). Diastolic level (option diastolicLevel): median before the pulse vs minimum before the peak.

TS 2026-10-06 (port of mda_test.m, TS 2026-10-05; external trigger 2026-10-08, rocker peaks, uncertain
2026-10-09; extra pulses, diastolic level 2026-10-10)
"""
from __future__ import annotations

import sys

import numpy as np

from ._matlab import Struct, colon
from .analyze_channel import analyze_channel
from .options import options
from .summarize import summarize
from . import reference_beat as rb


def _pass(p):
    return "ok" if p else "FAILED"


def synthetic_signal(t, onset, amp=None, rel=None, t0=None, shoulder=None, noise=None):
    """the synthetic contractions of mda_test (linear rise 0.2 s, linear relaxation rel s)."""
    F = 100 * np.ones(t.size) if noise is None else 100 + noise
    for k, on in enumerate(onset):
        A = 1000.0 if amp is None else amp[k]
        r = 0.4 if rel is None else rel[k]
        s = on if t0 is None else t0[k]
        I = (t >= s) & (t < s + 0.2)
        F[I] = F[I] + A * (t[I] - s) / 0.2 if noise is not None else 100 + A * (t[I] - s) / 0.2
        I = (t >= s + 0.2) & (t < s + 0.2 + r)
        F[I] = F[I] + A - A * (t[I] - s - 0.2) / r if noise is not None else 100 + A - A * (t[I] - s - 0.2) / r
        if shoulder is not None and shoulder[k]:
            I = (t >= s + 0.35) & (t < s + 0.5)
            F[I] = F[I] + 250 * np.sin(np.pi * (t[I] - s - 0.35) / 0.15)
    return F


def _S(t, F, onset, on=None, rocker_log=None):
    S = Struct(dataChannels=np.array([1]), dt=0.005, t=t, force=F[None, :],
               rockerOn=np.zeros(t.size, bool) if on is None else on, fromSeconds=float(t[0]),
               toSeconds=float(t[-1]))
    if rocker_log is not None:
        S.rockerSpeedLog = rocker_log
    S.stim = Struct(time=np.asarray(onset, float) - 0.1, channel=np.ones(len(onset), dtype=int))
    return S


def selftest(verbose=True, seed=3):
    out = print if verbose else (lambda *a, **k: None)
    dt = 0.005
    t = colon(0, dt, 20)
    onset = np.arange(1, 19, dtype=float)
    F = synthetic_signal(t, onset)
    S = _S(t, F, onset)
    B, _ = analyze_channel(S, 1, [2, 17], options(noFiltering=True, zeroForce=40))
    expected = [("amplitude", 1000), ("diastolicSignal", 100), ("diastolicForce", 60), ("dFdtMax", 5000),
                ("dFdtMin", -2500), ("riseTime10_90", 0.16), ("TTP90", 0.18), ("TTR50", 0.2), ("TTR90", 0.36),
                ("CD50", 0.3), ("CD90", 0.54), ("AUC", 297), ("peakToPeakInterval", 1), ("peakToPeakFrequency", 1),
                ("stimToPeak", 0.3), ("stimInterval", 1), ("stimFrequency", 1)]
    allstim = bool(np.all(B["beatType"] == "stimulated"))
    ok = len(B) == 15 and allstim
    out(f"{len(B)} contractions detected (expected 15), all stimulated: {int(allstim)}")
    for nm, e in expected:
        v = B[nm].to_numpy(dtype=float)
        err = np.max(np.abs(v - e)) / abs(e)
        p = err < 1e-9
        ok = ok and p
        out(f"{nm:<20s} expected {e:9.4f}   calculated {np.mean(v):9.4f}   max. rel. error {err:.1e}   {_pass(p)}")

    # diastolic level (2026-10-10): a dip to 50 uN 0.3 ... 0.25 s before every pulse (outside the window 60 ... 5 ms
    # before it): median before the pulse (default) 100 uN, amplitude 1000 uN; 'minimum' 50 uN, amplitude 1050 uN
    F2 = F.copy()
    for on_ in onset:
        F2[(t >= on_ - 0.4) & (t < on_ - 0.35)] = 50
    S2 = _S(t, F2, onset)
    Bm, _ = analyze_channel(S2, 1, [2, 17], options(noFiltering=True, zeroForce=40))
    Bn, _ = analyze_channel(S2, 1, [2, 17], options(noFiltering=True, zeroForce=40, diastolicLevel="minimum"))
    okD = bool(np.all(np.abs(Bm["amplitude"] - 1000) < 1e-9) and np.all(np.abs(Bm["diastolicSignal"] - 100) < 1e-9)
               and np.all(np.abs(Bm["TTP90"] - 0.18) < 1e-9) and np.all(np.abs(Bn["amplitude"] - 1050) < 1e-9)
               and np.all(np.abs(Bn["diastolicSignal"] - 50) < 1e-9))
    out(f"diastolic level: median before the pulse {Bm['diastolicSignal'].mean():.1f} uN (amplitude "
        f"{Bm['amplitude'].mean():.1f}), minimum {Bn['diastolicSignal'].mean():.1f} uN (amplitude "
        f"{Bn['amplitude'].mean():.1f}); expected 100 / 1000, 50 / 1050   {_pass(okD)}")
    ok = ok and okD

    # rocker filter: the same contractions every 2 s plus a periodic artifact (60 rpm = 1.2117 Hz, 3 harmonics,
    # 300 uN peak-to-peak = 30 % of the amplitude) while the rocker moves (0-90 s and 100-200 s)
    t = colon(0, dt, 200)
    onset = np.arange(1, 198, 2, dtype=float)
    F = synthetic_signal(t, onset)
    on = (t < 90) | (t >= 100)
    art = np.zeros(t.size)
    for q in (1, 2):
        I = on & ((t < 90) == (q == 1))
        a = (np.cos(2 * np.pi * 1.2117 * t[I] + 0.3 + q) + 0.5 * np.cos(4 * np.pi * 1.2117 * t[I] + 2.1 + 2 * q)
             + 0.25 * np.cos(6 * np.pi * 1.2117 * t[I] + 4 + q))
        art[I] = 300 * a / (a.max() - a.min())
    S = _S(t, F + art, onset, on=on, rocker_log=np.array([[-np.inf, 60.0]]))
    o = options(noFiltering=True, zeroForce=40)
    B0, _ = analyze_channel(S, 1, [5, 195], o)
    B1, C1 = analyze_channel(S, 1, [5, 195], options(o, rockerFilter=True))
    chk = [("amplitude", 1000, 0.005), ("TTP90", 0.18, 0.002), ("TTR90", 0.36, 0.002), ("diastolicForce", 60, 2)]
    out(f"rocker filter ({C1.rockerFilter.status}, f0 {C1.rockerFilter.f0:.4f} Hz): {len(B1)} contractions "
        "(expected 95)")
    okR = len(B1) == 95 and C1.rockerFilter.status == "corrected"
    for nm, e, tol in chk:
        if nm == "amplitude":
            tol = tol * e
        e0 = np.max(np.abs(B0[nm].to_numpy() - e))
        e1 = np.max(np.abs(B1[nm].to_numpy() - e))
        p = e1 <= tol
        okR = okR and p
        out(f"{nm:<20s} expected {e:9.4f}   max. abs. error without filter {e0:8.4f}, with filter {e1:8.4f}   "
            f"{_pass(p)}")
    ok = ok and okR

    # reference beat: 1 Hz, noise 10 uN, amplitude 1000 uN +- 3 %; 2 beats each with a shoulder, half amplitude
    # (partial response), slower relaxation (0.6 instead of 0.4 s) and 40 ms longer latency after the stimulus;
    # reference = beats 2-15, aligned at the stimulus (default) and at the 50 % upstroke
    rng = np.random.default_rng(seed)
    t = colon(0, dt, 60)
    onset = np.arange(1, 59, dtype=float)
    typ = np.zeros(onset.size, int)
    typ[[19, 34]] = 1; typ[[24, 44]] = 2; typ[[29, 49]] = 3; typ[[39, 54]] = 4
    noise = 10 * rng.standard_normal(t.size)
    amp = 1000 * (1 + 0.03 * rng.standard_normal(onset.size))
    amp[typ == 2] = 500
    rel = np.where(typ == 3, 0.6, 0.4)
    t0 = onset + np.where(typ == 4, 0.04, 0.0)
    F = synthetic_signal(t, onset, amp=amp, rel=rel, t0=t0, shoulder=typ == 1, noise=noise)
    S = _S(t, F, onset)
    o = options(zeroForce=40)
    B, C = analyze_channel(S, 1, [0.5, 59], o)
    tpk = B["t_peak"].to_numpy()
    R = rb.create(C, B, np.flatnonzero((tpk > 2) & (tpk < 16)))
    B, _ = analyze_channel(S, 1, [0.5, 59], options(o, referenceBeat=R))
    BU, _ = analyze_channel(S, 1, [0.5, 59], options(o, referenceBeat=rb.align(R, "upstroke")))
    tp = typ[np.argmin(np.abs(B["t_peak"].to_numpy()[:, None] - (onset + 0.2)[None, :]), axis=1)]
    dn = B["refMaxDeviationNorm_SD"].to_numpy(); da = B["refMaxDeviation_SD"].to_numpy()
    dnU = BU["refMaxDeviationNorm_SD"].to_numpy(); rn = B["refRMSDeviationNorm_SD"].to_numpy()
    rc = B["refCorrelation"].to_numpy()
    okB = (len(B) == 58 and R.align == "stimulus" and np.all(dn[tp == 0] < 3) and np.all(dn[(tp == 1) | (tp == 3)] > 5)
           and np.all(da[(tp == 1) | (tp == 3)] > 5) and np.all(da[tp == 2] > 5) and np.all(dn[tp == 2] < 3)
           and np.all(rc[tp == 2] > 0.999) and np.all(dn[tp == 4] > 5) and np.all(dnU[tp == 4] < 3)
           and np.all(dnU[tp == 0] < 3) and rn[tp == 0].max() < rn[(tp == 1) | (tp == 3) | (tp == 4)].min())
    out("reference beat (stimulus-aligned; max. deviation absolute / normalized, SD): normal max "
        f"{dn[tp == 0].max():.1f} (normalized) | shoulder {da[tp == 1].min():.1f} / {dn[tp == 1].min():.1f} | partial "
        f"{da[tp == 2].min():.1f} / {dn[tp == 2].max():.1f} (corr {rc[tp == 2].min():.4f}) | slow relaxation "
        f"{da[tp == 3].min():.1f} / {dn[tp == 3].min():.1f} | latency +40 ms {da[tp == 4].min():.1f} / "
        f"{dn[tp == 4].min():.1f}, upstroke-aligned {dnU[tp == 4].max():.1f} | RMS normalized: normal max "
        f"{rn[tp == 0].max():.2f}, deviating min {rn[(tp == 1) | (tp == 3) | (tp == 4)].min():.2f}   {_pass(okB)}")
    ok = ok and okB
    # parameters relative to the reference: normal ~100 %, partial response ~50 % amplitude, slow relaxation TTR90 150 %
    pa = B["amplitude_pctRef"].to_numpy(); pr = B["TTR90_pctRef"].to_numpy()
    dd = B["diastolicForce_dRef"].to_numpy()
    okP = (np.all(np.abs(pa[tp == 0] - 100) < 10) and np.all(np.abs(pa[tp == 2] - 50) < 5)
           and np.all(np.abs(pr[tp == 3] - 150) < 10) and np.all(np.abs(pr[tp == 0] - 100) < 5)
           and np.all(np.abs(dd[tp == 0]) < 40))
    out(f"relative to the reference: amplitude normal {pa[tp == 0].min():.0f}-{pa[tp == 0].max():.0f} %, partial "
        f"{pa[tp == 2].min():.0f}-{pa[tp == 2].max():.0f} % (expected 50) | TTR90 slow relaxation "
        f"{pr[tp == 3].min():.0f}-{pr[tp == 3].max():.0f} % (expected 150) | diastolic force difference normal max "
        f"{np.abs(dd[tp == 0]).max():.0f} uN   {_pass(okP)}")
    ok = ok and okP

    # stimulation pause: 1 Hz, pause of 9 s, rocker moving (artifact +-120 uN) until 1.2 s before the next stimulus.
    # F_dia of the first contraction after the pause: only from pauseDiastoleWindow (0.5 s) before its stimulus
    # (amplitude 1000 uN, rocker stopped); with the whole window (inf) the artifact gives F_dia and the rocker state.
    t = colon(0, dt, 30)
    onset = np.r_[np.arange(1, 11), np.arange(19, 29)].astype(float)
    F = synthetic_signal(t, onset)
    on = (t >= 13.5) & (t < 17.7)
    F[on] = F[on] + 120 * np.sin(2 * np.pi * 1.2 * t[on])
    S = _S(t, F, onset, on=on)
    o = options(noFiltering=True, zeroForce=40, diastolicLevel="minimum")  # (median before the pulse: not affected)
    B, _ = analyze_channel(S, 1, [0.5, 29.5], o)
    B0, _ = analyze_channel(S, 1, [0.5, 29.5], options(o, pauseDiastoleWindow=np.inf))
    Bmed, _ = analyze_channel(S, 1, [0.5, 29.5], options(o, pauseDiastoleWindow=np.inf, diastolicLevel="preStimulusMedian"))
    p = np.abs(B["t_stim"].to_numpy() - 18.9) < 1e-9
    a, a0 = B["amplitude"].to_numpy(), B0["amplitude"].to_numpy()
    rm, rm0 = B["rockerMoving"].to_numpy(bool), B0["rockerMoving"].to_numpy(bool)
    okS = bool(len(B) == 20 and len(B0) == 20 and p.sum() == 1 and abs(a[p][0] - 1000) < 1e-6
               and abs(B["diastolicSignal"].to_numpy()[p][0] - 100) < 1e-6 and not rm[p][0] and a0[p][0] > 1050
               and rm0[p][0] and np.max(np.abs(a[~p] - a0[~p])) < 1e-9 and not rm.any()
               and abs(Bmed["amplitude"].to_numpy()[p][0] - 1000) < 1e-6)
    out(f"stimulation pause 9 s, rocker moving until 1.2 s before the stimulus: amplitude {a[p][0]:.1f} uN (expected "
        f"1000; whole window {a0[p][0]:.1f}), rocker moving {int(rm[p][0])} (whole window {int(rm0[p][0])}), other "
        f"contractions unchanged   {_pass(okS)}")
    ok = ok and okS

    # peaks of the rocker movement (option rockerArtifacts, 2026-10-09): 200 s, stimuli every 2 s, rocker 60 rpm moving
    # throughout (artifact 80 uN peak-to-peak, 2 harmonics). No contractions: none counted, C.noContractions; every 4th
    # stimulus answered (200 uN): only these 24 contractions; every stimulus answered (150 uN): 95 contractions, no
    # extra beats. Without the option the rocker peaks count (> 200 peaks each).
    t = colon(0, dt, 200)
    onset = np.arange(1, 198, 2, dtype=float)
    a = np.cos(2 * np.pi * 1.212 * t + 0.4) + 0.3 * np.cos(4 * np.pi * 1.212 * t + 1.3)
    art = 80 * a / (a.max() - a.min())
    o = options(zeroForce=40)
    nR = np.zeros((3, 4), int)
    noC = []
    for q, A in enumerate((0, 200, 150)):
        ons = onset[::4] if q == 1 else onset
        F = 100 * np.ones(t.size) if A == 0 else synthetic_signal(t, ons, amp=[A] * len(ons))
        S = _S(t, F + art, onset, on=np.ones(t.size, bool), rocker_log=np.array([[-np.inf, 60.0]]))
        B0, _ = analyze_channel(S, 1, [5, 195], options(o, rockerArtifacts=False))
        B1, C1 = analyze_channel(S, 1, [5, 195], o)
        bt = B1["beatType"].to_numpy()
        nR[q] = [len(B0), len(B1), np.sum(bt == "stimulated"), np.sum(bt == "extra")]
        noC.append(bool(C1.noContractions))
    okA = bool(np.array_equal(nR[:, 1:], [[0, 0, 0], [24, 24, 0], [95, 95, 0]]) and np.all(nR[:, 0] > 200)
               and noC == [True, False, False])
    out(f"rocker peaks (option rockerArtifacts): no contractions {nR[0, 1]} (without the option {nR[0, 0]}, no "
        f"contractions flag {int(noC[0])}) | every 4th stimulus {nR[1, 1]} (expected 24; without {nR[1, 0]}) | every "
        f"stimulus {nR[2, 2]} stimulated, {nR[2, 3]} extra (expected 95, 0; without {nR[2, 0]})   {_pass(okA)}")
    ok = ok and okA

    # uncertain contractions (option detection, 2026-10-09): 0.5 Hz, 300 uN, plus 32 small peaks (120 uN) between the
    # contractions, not locked to the stimuli: 'sensitive' counts them as uncertain extra beats, 'specific' does not
    t = colon(0, dt, 200)
    onset = np.arange(1, 198, 2, dtype=float)
    F = synthetic_signal(t, onset, amp=[300] * onset.size)
    ob = onset[::3]
    bump = ob + 1.1 + 0.3 * (np.arange(1, ob.size + 1) % 3) / 2
    for b in bump:
        I = np.abs(t - b) < 0.1
        F[I] = F[I] + 120 * (1 - np.abs(t[I] - b) / 0.1)
    S = _S(t, F, onset)
    o = options(zeroForce=40)
    B1, C1 = analyze_channel(S, 1, [5, 195], o)
    B2, _ = analyze_channel(S, 1, [5, 195], options(o, detection="specific"))
    T1 = summarize(B1, C1, [5, 195])
    u = B1["uncertain"].to_numpy(bool)
    okU = bool(len(B1) == 127 and u.sum() == 32 and np.all(B1["beatType"].to_numpy()[u] == "extra") and len(B2) == 95
               and T1["nUncertain"].iloc[0] == 32 and T1["nExtraBeatsUncertain"].iloc[0] == 32
               and T1["nStimulatedUncertain"].iloc[0] == 0)
    out(f"uncertain contractions (option detection): sensitive {len(B1)} (expected 127), uncertain {int(u.sum())} extra "
        f"beats (expected 32), specific {len(B2)} (expected 95), summary nUncertain {int(T1['nUncertain'].iloc[0])}   "
        f"{_pass(okU)}")
    ok = ok and okU

    # external trigger pulses (2026-10-08): status bit 14 without channel / current (external stimulator at the
    # external controller unit), temporary .mdd file, see mda_test.m
    okX = _external_trigger_test(out)
    ok = ok and okX
    # extra pulses (2026-10-10): onset gate, pre- / post-pulses, pulse table (mda_testExtraPulses.m)
    okE = extra_pulse_test(out)
    ok = ok and okE
    out("selftest: all tests passed." if ok else "selftest: TEST FAILED.")
    return bool(ok)


def _external_trigger_test(out):
    """temporary .mdd (9 channels, 400 Hz, 30 s; contractions in channel 1 150 ms after each external trigger pulse,
    one pulse 2 samples long, rocker bit set throughout): stim.channel 0, one entry per pulse; stimuli of the analysed
    channel with externalTrigger 'auto' / 'on', not with 'off'; with a MyoDish pulse in the window 'auto' keeps the
    MyoDish pulses (externalTriggerTest of mda_test.m)."""
    import os
    import tempfile

    from .read_mdd import read_mdd
    fs = 400
    n = 30 * fs
    tt = np.arange(n) / fs
    trig = np.arange(1, 29, dtype=float)
    X = np.zeros((9, n), np.int16)
    F = np.full(n, 2000.0)
    for a0 in trig:
        a = a0 + 0.05
        m = (tt >= a) & (tt < a + 0.1)
        F[m] = 2000 + 1000 * (tt[m] - a) / 0.1
        m = (tt >= a + 0.1) & (tt < a + 0.4)
        F[m] = 3000 - 1000 * (tt[m] - a - 0.1) / 0.3
    X[0] = np.round(F).astype(np.int16)
    code = np.full(n, 16384, np.uint16)  # rocker bit
    iT = np.round(trig * fs).astype(int)
    code[iT] = 24576  # bit 14 + 15
    code[iT[4] + 1] = 24576  # one pulse 2 samples long
    X[8] = code.view(np.int16)
    L = ["systemTime;dataLogTime;channel;code;value", "2026 01 01 06:00:00:000;0;0;nChannels;9",
         "2026 01 01 06:00:00:000;0;0;Recording;started: x.mdd",
         "2026 01 01 06:00:00:000;0;0;samplingRate Recording;400"]
    for c in range(1, 9):
        L += [f"2026 01 01 06:00:00:000;0;{c};Calibration;1000", f"2026 01 01 06:00:00:000;0;{c};Offset;0"]
    L.append("2026 01 01 06:00:30:000;30000;0;Recording;stopped: x.mdd")
    with tempfile.TemporaryDirectory() as d:
        mdd = os.path.join(d, "xtrig.mdd")
        X.T.astype("<i2").tofile(mdd)
        with open(os.path.join(d, "xtrig_log.log"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(L) + "\n")
        try:
            S = read_mdd(mdd, 0, 30)
            o = options(externalTrigger="auto")

            def nst(B):
                return int(np.sum(B["beatType"] == "stimulated"))
            Ba, Ca = analyze_channel(S, 1, [0.5, 29.5], o)
            Bf, _ = analyze_channel(S, 1, [0.5, 29.5], options(o, externalTrigger="off"))
            Sm = S.copy()
            Sm.stim = Struct(S.stim)
            Sm.stim.time = np.r_[S.stim.time, 0.2]
            Sm.stim.channel = np.r_[S.stim.channel, 3]  # one MyoDish pulse (channel 3)
            Bm, _ = analyze_channel(Sm, 1, [0.5, 29.5], o)
            Bo, _ = analyze_channel(Sm, 1, [0.5, 29.5], options(o, externalTrigger="on"))
            st = np.asarray(S.stim.time, float)
            okX = bool(st.size == 28 and np.all(np.asarray(S.stim.channel) == 0) and np.all(S.stim.external)
                       and np.max(np.abs(st - trig)) < 1e-9 and Ca.stimChannel == 0 and len(Ba) == 28 and nst(Ba) == 28
                       and abs(np.median(Ba["stimToPeak"]) - 0.15) < 0.02 and nst(Bf) == 0 and nst(Bm) == 0
                       and nst(Bo) == 28)
            out(f"external trigger pulses (bit 14 without channel): {st.size} pulses read (expected 28, channel 0), "
                f"stimulated contractions: auto {nst(Ba)}, off {nst(Bf)}, auto with a MyoDish pulse {nst(Bm)}, on "
                f"{nst(Bo)} (expected 28 / 0 / 0 / 28), stimToPeak {np.median(Ba['stimToPeak']):.3f} s   {_pass(okX)}")
        except Exception as e:  # noqa: BLE001
            okX = False
            out(f"external trigger pulses: {e}   FAILED")
    return okX


def extra_pulse_test(out=print):
    """stimulus assignment with extra pulses (port of mda_testExtraPulses.m): temporary 9-channel .mdd (400 Hz) with
    log file, one contraction per second in channel 1 (linear rise 100 ms, relaxation 300 ms, onset at k + 0.5 s),
    regular pulses (50 mA) and extra pulses (bit 16) of channel 1; log: pulse durations of channel 1 and of extra
    pulse #1 (log channel 11), 'Sequence' entries with the programmed extra pulse 30 ms after the regular pulse.
    k = 5 CCM (regular pulse, post-pulse t30), 6 sub-threshold pre-pulse (pre-pulse t-100), 7 eliciting pre-pulse
    (elicitedByExtraPulse, regular pulse missed within the contraction), 8 extra beat, 9 missed beat, 10 extra pulse
    5 ms before the regular pulse (ambiguous), 11 extra pulse only; stimAssignment 'peak' as before."""
    import os
    import tempfile

    from .read_mdd import read_mdd
    fs = 400
    T = 16
    n = T * fs
    tt = np.arange(n) / fs
    X = np.zeros((9, n), np.int16)
    F = np.full(n, 2000.0)
    beats = [k for k in range(1, 15) if k != 9]
    for k in beats:
        a = k + 0.5
        m = (tt >= a) & (tt < a + 0.1)
        F[m] = 2000 + 1000 * (tt[m] - a) / 0.1
        m = (tt >= a + 0.1) & (tt < a + 0.4)
        F[m] = 3000 - 1000 * (tt[m] - a - 0.1) / 0.3
    X[0] = np.round(F).astype(np.int16)
    P = [[k + 0.47, 50, 0] for k in (1, 2, 3, 4, 12, 13, 14)]
    P += [[5.43, 50, 0], [5.46, 60, 1], [6.37, 15, 1], [6.47, 50, 0], [7.47, 20, 1], [7.57, 50, 0], [9.47, 50, 0],
          [10.465, 25, 1], [10.47, 50, 0], [11.47, 30, 1]]
    code = np.zeros(n, np.uint16)
    for t0, cur, ex in P:
        code[int(round(t0 * fs))] = 512 + cur + (32768 if ex else 0)  # channel 1, current, bit 16
    X[8] = code.view(np.int16)
    L = ["systemTime;dataLogTime;channel;code;value", "2026 01 01 06:00:00:000;0;0;nChannels;9",
         "2026 01 01 06:00:00:000;0;1;chargeDuration;1000", "2026 01 01 06:00:00:000;0;1;pauseDuration;100",
         "2026 01 01 06:00:00:000;0;1;dechargeDuration;1000", "2026 01 01 06:00:00:000;0;11;chargeDuration;3000",
         "2026 01 01 06:00:00:000;0;11;pauseDuration;1000", "2026 01 01 06:00:00:000;0;11;dechargeDuration;3000",
         "2026 01 01 06:00:00:000;0;0;Sequence;Sent stimPeriod 1000",
         "2026 01 01 06:00:00:000;0;1;Sequence;Added stimTime(s) 470 500#1",
         "2026 01 01 06:00:00:000;0;0;Recording;started: x.mdd",
         "2026 01 01 06:00:00:000;0;0;samplingRate Recording;400"]
    for c in range(1, 9):
        L += [f"2026 01 01 06:00:00:000;0;{c};Calibration;1000", f"2026 01 01 06:00:00:000;0;{c};Offset;0"]
    L.append(f"2026 01 01 06:00:{T:02d}:000;{T * 1000};0;Recording;stopped: x.mdd")
    ok = True
    with tempfile.TemporaryDirectory() as d:
        mdd = os.path.join(d, "xpulse.mdd")
        X.T.astype("<i2").tofile(mdd)
        with open(os.path.join(d, "xpulse_log.log"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(L) + "\n")
        try:
            S = read_mdd(mdd, 0, T)
            o = options(noFiltering=True, spikeRemoval=False)
            B, C = analyze_channel(S, 1, [0.8, 15], o)
            Sm = summarize(B, C, [0.8, 15]).iloc[0]
            ton = B["t_onset"].to_numpy(float)

            def row(k):
                r = np.flatnonzero(np.abs(ton - (k + 0.5)) < 0.003)
                return int(r[0]) if r.size else None

            def v(col, k):
                return B[col].iloc[row(k)]
            X1 = np.asarray(S.extraPulseLog, float)
            chk = [("reader: 17 pulses, 5 extra pulses (bit 16)",
                    np.size(S.stim.time) == 17 and int(np.sum(S.stim.isExtraPulse)) == 5),
                   ("log: programmed extra pulse +30 ms (Sequence)",
                    bool(np.any((X1[:, 1] == 1) & (X1[:, 2] == 1) & (np.abs(X1[:, 3] - 30) < 1e-9)))),
                   ("log: pulse durations of channel 1 and 11", np.asarray(S.pulseSettingsLog).shape[0] == 6),
                   ("13 contractions, 12 stimulated, 1 extra beat",
                    len(B) == 13 and Sm.nStimulated == 12 and Sm.nExtraBeats == 1),
                   ("onsets exact (+-3 ms)", all(row(k) is not None for k in beats))]
            chk.append(("k=1: regular pulse, stimToOnset 30 ms, pulse ID, current, durations",
                        not v("elicitedByExtraPulse", 1) and abs(v("stimToOnset", 1) - 0.03) < 0.003
                        and v("stimPulse", 1) == round(1.47 * fs) and v("stimCurrent", 1) == 50
                        and [v("stimChargeDuration", 1), v("stimPauseDuration", 1), v("stimDechargeDuration", 1)]
                        == [1000, 100, 1000]))
            chk.append(("k=5 CCM: regular pulse, post-pulse t30|60|3000|1000|3000",
                        abs(v("t_stim", 5) - 5.43) < 1e-9 and not v("elicitedByExtraPulse", 5)
                        and not v("stimAmbiguous", 5) and v("postPulses", 5) == "t30|60|3000|1000|3000"
                        and v("prePulses", 5) == ""))
            chk.append(("k=6 sub-threshold pre-pulse: regular pulse, pre-pulse t-100|15|...",
                        abs(v("t_stim", 6) - 6.47) < 1e-9 and v("prePulses", 6) == "t-100|15|3000|1000|3000"
                        and not v("stimAmbiguous", 6)))
            chk.append(("k=7 eliciting pre-pulse: elicitedByExtraPulse, post-pulse t100|50|...",
                        v("elicitedByExtraPulse", 7) and abs(v("t_stim", 7) - 7.47) < 1e-9 and v("stimCurrent", 7) == 20
                        and v("stimChargeDuration", 7) == 3000 and v("postPulses", 7) == "t100|50|1000|100|1000"))
            chk.append(("k=8: extra beat", v("beatType", 8) == "extra" and np.isnan(v("t_stim", 8))))
            chk.append(("k=10: regular pulse, ambiguous, pre-pulses t-1000 (missed at k=9) & t-5",
                        abs(v("t_stim", 10) - 10.47) < 1e-9 and v("stimAmbiguous", 10)
                        and v("prePulses", 10) == "t-1000|50|1000|100|1000&t-5|25|3000|1000|3000"))
            chk.append(("k=11: extra pulse only -> elicitedByExtraPulse",
                        v("elicitedByExtraPulse", 11) and not v("stimAmbiguous", 11)))
            chk.append(("summary: 12 stimuli, 2 missed (1 in a contraction), 5 extra pulses, 2 elicited by them, 1 "
                        "ambiguous", Sm.nStimuli == 12 and Sm.nMissedBeats == 2 and Sm.nMissedDuringContraction == 1
                        and Sm.nExtraPulses == 5 and Sm.nElicitedByExtraPulse == 2 and Sm.nAmbiguous == 1))
            Pt = C.pulses
            tp = Pt["t"].to_numpy(float)
            q9 = int(np.flatnonzero(np.abs(tp - 9.47) < 1e-9)[0])
            q7 = int(np.flatnonzero(np.abs(tp - 7.57) < 1e-9)[0])
            q5 = int(np.flatnonzero(np.abs(tp - 5.46) < 1e-9)[0])
            chk.append(("pulse table: 17 rows, outcomes and roles",
                        len(Pt) == 17 and int(np.sum(Pt["outcome"] == "elicited")) == 12
                        and Pt["outcome"].iloc[q9] == "noResponse" and Pt["outcome"].iloc[q7] == "duringContraction"
                        and Pt["role"].iloc[q7] == "post" and Pt["tRel_ms"].iloc[q7] == 100
                        and abs(Pt["phase"].iloc[q7] - 0.07 / 0.37) < 0.02 and Pt["role"].iloc[q5] == "post"
                        and bool(Pt["extra"].iloc[q5]) and Pt["pulse"].iloc[q5] == round(5.46 * fs)
                        and Pt["tRel_ms"].iloc[q5] == 30))
            Bp, Cp = analyze_channel(S, 1, [0.8, 15], options(o, stimAssignment="peak"))
            chk.append(("peak assignment: 17 stimuli, no extra pulses",
                        np.size(Cp.stimTimes) == 17 and np.size(Cp.extraTimes) == 0
                        and not Bp["elicitedByExtraPulse"].any() and Cp.stimAssignment == "peak"))
            for name, passed in chk:
                out(f"{name:<100s} {_pass(bool(passed))}")
                ok = ok and bool(passed)
        except Exception as e:  # noqa: BLE001
            ok = False
            out(f"extra pulses: {type(e).__name__}: {e}   FAILED")
    out("extra pulses: all tests passed." if ok else "extra pulses: TEST FAILED.")
    return ok


def main():
    sys.exit(0 if selftest() else 1)


if __name__ == "__main__":
    main()
