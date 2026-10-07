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

TS 2026-10-06 (port of mda_test.m, TS 2026-10-05)
"""
from __future__ import annotations

import sys

import numpy as np

from ._matlab import Struct, colon
from .analyze_channel import analyze_channel
from .options import options
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
    o = options(noFiltering=True, zeroForce=40)
    B, _ = analyze_channel(S, 1, [0.5, 29.5], o)
    B0, _ = analyze_channel(S, 1, [0.5, 29.5], options(o, pauseDiastoleWindow=np.inf))
    p = np.abs(B["t_stim"].to_numpy() - 18.9) < 1e-9
    a, a0 = B["amplitude"].to_numpy(), B0["amplitude"].to_numpy()
    rm, rm0 = B["rockerMoving"].to_numpy(bool), B0["rockerMoving"].to_numpy(bool)
    okS = bool(len(B) == 20 and len(B0) == 20 and p.sum() == 1 and abs(a[p][0] - 1000) < 1e-6
               and abs(B["diastolicSignal"].to_numpy()[p][0] - 100) < 1e-6 and not rm[p][0] and a0[p][0] > 1050
               and rm0[p][0] and np.max(np.abs(a[~p] - a0[~p])) < 1e-9 and not rm.any())
    out(f"stimulation pause 9 s, rocker moving until 1.2 s before the stimulus: amplitude {a[p][0]:.1f} uN (expected "
        f"1000; whole window {a0[p][0]:.1f}), rocker moving {int(rm[p][0])} (whole window {int(rm0[p][0])}), other "
        f"contractions unchanged   {_pass(okS)}")
    ok = ok and okS
    out("selftest: all tests passed." if ok else "selftest: TEST FAILED.")
    return bool(ok)


def main():
    sys.exit(0 if selftest() else 1)


if __name__ == "__main__":
    main()
