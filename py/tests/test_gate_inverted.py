# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Longer onset gate of certain contractions and inverted signals (2026-10-11) with a synthetic recording (9 channels,
400 Hz, 320 s; pacing 0.5 Hz in channels 1-3). Pendant of mda_testGateInverted.m (same recording and checks).

    ch1  twitch 30 ms after every pulse                     stimulated, amplitude 1000 (filtered ~930)
    ch2  twitch 300 ms after every pulse (long delay)       stimulated (gateMaxCertain 0.5 s); all extra with 0.15 s
    ch3  inverted twitch 30 ms after every pulse            invertedSignal, force parameters NaN, rate and capture
    ch4  noise only; analysis report (report.py): ch2 delay and ch3 inverted to check
    ch5  rocker waves downwards (400 uN, 3 per stimulus interval) partly in phase with the pulses (phase at the pulse
         0 +- 2.5 rad): the median falls after the pulses (suspicion), but the detection in the negated signal finds
         no certain stimulated contraction: not inverted (invertedMinCapture; 2026-10-12)

Arrhythmic pacing (2026-10-13; second recording, 3 channels, 600 s, noise only): ch1 paced arrhythmically (mean 4 Hz,
interval CV ~29 %), ch2 1 Hz with variable pacing during an FFR protocol of the log file (100-500 s), ch3 1 Hz.

TS 2026-10-11 (arrhythmic pacing 2026-10-13)
"""
import math

import numpy as np

import myodish_analysis as mda

FS = 400
T = 320
PULSES = np.arange(10.0, 310.0, 2.0)


def twitch(tau):
    """twitch of amplitude 1: raised cosine rise in 0.1 s, exponential relaxation (0.12 s)"""
    y = np.zeros_like(tau)
    r = (tau >= 0) & (tau < 0.1)
    y[r] = (1 - np.cos(np.pi * tau[r] / 0.1)) / 2
    d = tau >= 0.1
    y[d] = np.exp(-(tau[d] - 0.1) / 0.12)
    return y


def rocker_partly_locked(t):
    """rocker waves with sharp troughs (400 uN), 3 cycles per stimulus interval; phase at pulse i: 2 pi 3 i + 2.5 u_i
    (u_i in [-1, 1], plastic number sequence), linear in between"""
    i = np.arange(PULSES.size)
    u = 2 * np.mod((i + 1) * 0.7548776662466927, 1.0) - 1
    th = 2 * np.pi * 3 * i + 2.5 * u
    w = 2 * np.pi * 3 / 2.0  # rad/s
    th = np.interp(t, np.r_[0.0, PULSES, T], np.r_[th[0] - w * PULSES[0], th, th[-1] + w * (T - PULSES[-1])])
    return -400 * np.maximum(0, np.sin(th)) ** 3


def write_recording(f):
    n = T * FS
    t = np.arange(n) / FS
    x = np.zeros((9, n))
    noise = np.round(3 * np.sin(2 * np.pi * 37.3 * t) + 2 * np.sin(2 * np.pi * 91.7 * t))
    for c, (delay, sign) in enumerate([(0.03, 1), (0.30, 1), (0.03, -1)]):
        y = np.zeros(n)
        for p in PULSES:
            k0 = int(round((p + delay) * FS))
            k1 = min(n, k0 + int(1.2 * FS))
            y[k0:k1] += twitch(t[k0:k1] - t[k0])
        x[c] = -383 + sign * 1000 * y + noise
    x[3:8] = -383 + noise
    x[4] = -383 + rocker_partly_locked(t) + noise
    st = np.zeros(n)
    for c in (1, 2, 3, 5):  # pulse of channel c one sample after the one of channel c-1
        idx = np.round(PULSES * FS).astype(int) + (c - 1)
        st[idx] = 50 | (c << 9)
    x[8] = st
    np.round(x).astype("<i2").T.tofile(f)
    name = f.replace("\\", "/").rsplit("/", 1)[-1]
    lines = ["systemTime;dataLogTime;channel;code;value",
             "2000 01 01 10:00:00:000;0;0;samplingRate Recording;400",
             f"2000 01 01 10:00:00:000;0;0;Recording;started: {name}",
             f"2000 01 01 10:05:20:000;{T * 1000};0;Recording;stopped: {name}"]
    with open(f[:-4] + "_log.log", "w") as fh:
        fh.write("\n".join(lines) + "\n")


def test_long_delay_and_inverted(tmp_path):
    f = str(tmp_path / "gate_rigA_0.mdd")
    write_recording(f)
    C, S, info = mda.myodish_analysis(f, [1, 2, 3], 0, T, quiet=True)
    nP = PULSES.size
    for ch in (1, 2, 3):
        c = C[C["channel"] == ch]
        assert (c["beatType"] == "stimulated").sum() >= nP - 1, ch
        assert (c["beatType"] == "extra").sum() == 0, ch
    c1, c2, c3 = (C[C["channel"] == ch] for ch in (1, 2, 3))
    # the filter flattens the sharp peak (amplitude ~930); the delayed twitch must give the same amplitude
    a1, a2 = c1["amplitude"].median(), c2["amplitude"].median()
    assert a1 > 900 and abs(a2 / a1 - 1) < 0.01 and not (c1["invertedSignal"].any() or c2["invertedSignal"].any())
    assert abs(c2["stimToOnset"].median() - c1["stimToOnset"].median() - 0.27) < 0.01
    assert abs(c2["stimToRise50"].median() - 0.35) < 0.01 and abs(c1["stimToRise50"].median() - 0.08) < 0.01
    assert c3["invertedSignal"].all() and c3["amplitude"].isna().all() and c3["TTP90"].isna().all()
    assert c3["stimToRise50"].isna().all() and abs(c3["peakToPeakFrequency"].median() - 0.5) < 0.01
    s3 = S[S["channel"] == 3]
    assert s3["invertedSignal"].all() and s3["nMissedBeats"].sum() <= 1 and math.isnan(s3["amplitude_mean"].iloc[0])
    assert not S.loc[S["channel"] != 3, "invertedSignal"].any()
    # gate of certain contractions as for uncertain ones (0.15 s): the delayed twitches are extra beats
    C15, _, _ = mda.myodish_analysis(f, [2], 0, T, quiet=True, gateMaxCertain=0.15)
    assert (C15["beatType"] == "stimulated").sum() == 0
    # no inversion check: channel 3 is analysed as it is (no contractions above the noise)
    C0, _, _ = mda.myodish_analysis(f, [3], 0, T, quiet=True, invertedCheck=False)
    assert not C0["invertedSignal"].any() if len(C0) else True


def test_inverted_confirmed_by_detection(tmp_path):
    """rocker waves partly in phase with the pulses (ch5): suspected (median falls after the pulses), but the normal
    detection in the negated signal finds no certain stimulated contraction: analysed as it is; option
    invertedMinCapture (2026-10-12)"""
    f = str(tmp_path / "gate_rigA_0.mdd")
    write_recording(f)
    C, S, _ = mda.myodish_analysis(f, [3, 5], 0, T, quiet=True)
    assert S.loc[S["channel"] == 3, "invertedSignal"].all() and not S.loc[S["channel"] == 5, "invertedSignal"].any()
    C0, S0, _ = mda.myodish_analysis(f, [5], 0, T, quiet=True, invertedCheck=False)
    c5 = C[C["channel"] == 5]
    assert len(c5) == len(C0) and np.allclose(c5["amplitude"].to_numpy(float), C0["amplitude"].to_numpy(float),
                                              equal_nan=True)  # the same as without the inversion check
    _, S1, _ = mda.myodish_analysis(f, [5], 0, T, quiet=True, invertedMinCapture=0)
    assert S1["invertedSignal"].all()  # suspicion alone
    _, S2, _ = mda.myodish_analysis(f, [3], 0, T, quiet=True, invertedMinCapture=1.01)
    assert not S2["invertedSignal"].any()


def test_analysis_report(tmp_path):
    """analysis report (report.py, 2026-10-11): ch2 delay (red D), ch3 inverted (red I), ch4 without contractions"""
    import os
    import re
    from myodish_analysis.report import analysis_report, report_flags, report_path
    f = str(tmp_path / "gate_rigA_0.mdd")
    write_recording(f)
    out = str(tmp_path / "res.csv")
    C, S, info = mda.myodish_analysis(f, [1, 2, 3, 4], 0, T, output=out, quiet=True)
    rep = str(tmp_path / "res_report.pdf")
    assert os.path.isfile(rep)  # default with output
    assert len(re.findall(rb"/Type\s*/Page[^s]", open(rep, "rb").read())) == 3  # overview, list, ch2 + ch3 traces
    R = report_flags(S, C)
    assert list(R["flags"]) == ["", "D", "I", ""] and list(R["level"]) == ["", "check", "check", "few beats"]
    assert R.loc[1, "red"] == "delay 315 ms" and R.loc[2, "red"] == "inverted signal"
    R2 = analysis_report(str(tmp_path / "x.pdf"), f, C, S, info, results=out)
    assert R2.loc[1, "matlab"] == f"MyoDishAnalysisGUI('{out}', 'channel', 2, 'window', [149 169])"
    assert R2.loc[2, "python"] == f'mda-gui "{out}" --channel 3 --window 149 169'
    # stricter flags: amplitude below 1000 uN is a slice-quality flag; no inversion check: ch3 not flagged red
    assert report_flags(S, C, amplitude=1000)["flags"].tolist()[:2] == ["A", "DA"]
    assert report_path(os.path.join("a", "res.xlsx")) == os.path.join("a", "res_report.pdf")
    assert report_path("res.csv", False) is None
    assert report_path(None) is None and report_path(None, "r.pdf") == "r.pdf" and report_path("r.txt", "on") == \
        "r.txt_report.pdf"
    mda.myodish_analysis(f, [1], 0, 60, output=str(tmp_path / "n.csv"), report=False, quiet=True)
    assert not os.path.isfile(str(tmp_path / "n_report.pdf"))


def test_report_label_and_amplitude_change():
    """channel label in the lists and amplitude change with its time span (report.py, 2026-10-12)"""
    import pandas as pd
    from myodish_analysis.report import duration_text, legend_lines, report_flags, FLAG_DEFAULTS
    rows = []
    for c, a1, tr, conc, grp in ((1, 100.0, "PMA", 100.0, ""), (2, 300.0, "", math.nan, "control"),
                                 (3, 300.0, "", math.nan, "")):
        for k in range(24):
            rows.append({"channel": c, "from": 3600.0 * k, "to": 3600.0 * (k + 1), "nDetected": 100, "nStimuli": 100,
                         "nMissedBeats": 0, "nExtraBeats": 30 if c == 2 else 0, "nUncertain": 0,
                         "nContractions": 100, "amplitude_mean": a1 + (660.0 if c == 1 else 0.0) * k / 23,
                         "amplitude_CV": 0.1, "treatment": tr, "concentration": conc, "concentrationUnit": "nM",
                         "sliceGroup": grp, "sampleGroup": ""})
    R = report_flags(pd.DataFrame(rows))
    assert list(R["label"]) == ["PMA 100 nM", "control", ""]
    assert R.loc[0, "yellow"] == "amplitude change +660 % over 24 h" and R.loc[0, "amplitudeChange_hours"] == 24
    assert R.loc[1, "yellow"] == "extra beats 30 %" and list(R["flags"]) == ["T", "X", ""]  # X: slice quality
    assert [duration_text(h) for h in (0.75, 5.5, 24, 84, math.nan)] == ["45 min", "5.5 h", "24 h", "3.5 d", ""]
    inv = [{"channel": 1, "from": 3600.0 * k, "to": 3600.0 * (k + 1), "nDetected": n, "nStimuli": n, "nMissedBeats": 0,
            "nExtraBeats": 0, "nUncertain": 0, "nContractions": n, "amplitude_mean": a, "amplitude_CV": 0.1,
            "invertedSignal": k == 0} for k, n, a in ((0, 60, math.nan), (1, 9940, 300.0))]
    assert report_flags(pd.DataFrame(inv)).loc[0, "red"] == "inverted signal (< 1 % of the contractions)"
    # red flag R: 'Controller restart suspected' warning of the control software 2.2 in the events table (2026-10-21)
    E = pd.DataFrame({"code": ["comment", "warning", "Warning", "warning"],
                      "text": ["start FFR protocol", "Controller restart suspected: no data for 6.2 s, frame counter 1 after it",
                               "controller restart suspected: no data for 5.0 s, 20 ms blocks although 2.5 ms was set",
                               "something else"], "t_file": [10.0, 1234.5, 2000.0, 3000.0]})
    RR = report_flags(pd.DataFrame(rows), events=E)
    assert list(RR["flags"]) == ["RT", "RX", "R"] and list(RR["level"]) == ["check"] * 3
    assert RR.loc[2, "red"] == "controller restart suspected (2, first at 1234 s)"
    assert report_flags(pd.DataFrame(rows), events=E.iloc[[0, 3]])["flags"].tolist() == ["T", "X", ""]
    L = legend_lines(FLAG_DEFAULTS)
    assert len(L) == 6 and all(len(t) <= 170 for _, t in L) and "T amplitude changes by > 30 %" in L[3][1]
    assert L[2][0] == "check" and L[2][1].startswith("R controller restart suspected")


def test_report_noise_index_and_large_extra_beats():
    """red N (uncertain with extra + missed beats), S (large extra beats), X as slice quality (2026-10-12)"""
    import pandas as pd
    from myodish_analysis.report import report_flags, report_window

    def S_of(ch, stimuli, miss, extra, unc):
        return {"channel": ch, "from": 0.0, "to": 3600.0, "nDetected": 1000, "nStimuli": stimuli, "nMissedBeats": miss,
                "nExtraBeats": extra, "nUncertain": unc, "nContractions": 1000, "amplitude_mean": 300.0,
                "amplitude_CV": 0.1}
    S = pd.DataFrame([S_of(1, 1000, 450, 0, 980),   # rocker waves after the pulses: uncertain, 45 % missed -> N
                      S_of(2, 1000, 10, 20, 900),   # uncertain but regular capture: real contractions near threshold
                      S_of(3, 0, 0, 0, 400),        # unpaced, 40 % uncertain -> N
                      S_of(4, 1000, 500, 300, 50),  # spontaneous activity: capture and extra beats (yellow)
                      S_of(5, 1000, 0, 100, 0),     # large extra beats (contractions below) -> S
                      S_of(6, 1000, 50, 150, 240)])  # 24 % uncertain: below 25 %, extra beats yellow
    C = pd.DataFrame({"channel": 5, "t_peak": np.arange(1000.0), "beatType": ["extra" if k % 10 == 0 else "stimulated"
                                                                               for k in range(1000)],
                      "uncertain": False, "included": True, "stimToOnset": 0.03,
                      "amplitude": [5000.0 if k % 10 == 0 else 400.0 for k in range(1000)]})
    R = report_flags(S, C)
    assert list(R["flags"]) == ["NC", "", "N", "CX", "S", "X"]
    assert R.loc[0, "red"] == "noise index 44 (uncertain 98 %, extra 0 %, missed 45 %)"
    assert R.loc[2, "red"] == "noise index 40 (uncertain 40 %, unpaced)" and R.loc[3, "yellow"] == \
        "capture 50 %, extra beats 30 %"
    assert R.loc[4, "red"] == "large extra beats 10 % (12.5 x the paced amplitude)"
    assert abs(R.loc[1, "noiseIndex"] - 2.7) < 1e-9 and list(R["level"]) == ["check", "", "check", "quality", "check",
                                                                             "quality"]
    assert report_window(C, 5, "S") == (0.0, 20.0)
    assert list(report_flags(S, C, uncertain=10)["flags"])[5] == "N"  # threshold as option


T2 = 600


def arrhythmic_pulses():
    """pulse times of ch1 (arrhythmic: intervals 0.25 s x (1 + 0.5 u_i), u_i in [-1, 1] plastic number sequence),
    ch2 (1 Hz; 100-500 s steps of 20 s at 1, 2, 3 Hz), ch3 (1 Hz); samples 4k, 4k + 1, 4k + 2 (one pulse per sample of
    the status channel)"""
    i = np.arange(1, 2400)
    iv = 0.25 * (1 + 0.5 * (2 * np.mod(i * 0.7548776662466927, 1.0) - 1))
    p1 = 5 + np.cumsum(iv)
    p1 = 4 * np.round(p1[p1 < T2 - 5] * FS / 4) / FS
    p2 = [np.arange(5.0, 100.0)]
    for j in range(20):
        r = 1 + j % 3
        p2.append(100 + 20 * j + np.arange(20 * r) / r)
    p2.append(np.arange(500.0, T2 - 5))
    p2 = 4 * np.round(np.concatenate(p2) * FS / 4) / FS + 1 / FS
    p3 = np.arange(5.0, T2 - 5) + 2 / FS
    return p1, p2, p3


def write_arrhythmic(f, protocol=True):
    n = T2 * FS
    t = np.arange(n) / FS
    x = np.zeros((4, n))
    x[:3] = -383 + np.round(3 * np.sin(2 * np.pi * 37.3 * t) + 2 * np.sin(2 * np.pi * 91.7 * t))
    for c, p in enumerate(arrhythmic_pulses(), start=1):
        x[3, np.round(p * FS).astype(int)] = 50 | (c << 9)
    np.round(x).astype("<i2").T.tofile(f)
    name = f.replace("\\", "/").rsplit("/", 1)[-1]
    lines = ["systemTime;dataLogTime;channel;code;value",
             "2000 01 01 10:00:00:000;0;0;samplingRate Recording;400",
             f"2000 01 01 10:00:00:000;0;0;Recording;started: {name}"]
    if protocol:
        lines += ["2000 01 01 10:01:40:000;100000;0;comment;FFR protocol started",
                  "2000 01 01 10:08:20:000;500000;0;comment;FFR protocol ended"]
    lines.append(f"2000 01 01 10:10:00:000;{T2 * 1000};0;Recording;stopped: {name}")
    with open(f[:-4] + "_log.log", "w") as fh:
        fh.write("\n".join(lines) + "\n")


def test_arrhythmic_pacing(tmp_path):
    """arrhythmic pacing (2026-10-13): detected from the stim-to-stim variability outside the stimulation protocols
    (> arrhythmicMinFraction of the paced time with CV > arrhythmicMinVariability), or set by arrhythmicChannels"""
    from myodish_analysis.summarize import stim_variability
    p1, p2, p3 = arrhythmic_pulses()
    cv, fr, d = stim_variability(p1, [0, T2])
    assert 25 < cv < 33 and fr == 1 and d == T2
    cv, fr, d = stim_variability(p2, [0, T2], exclude=[[100, 500]])
    assert cv < 1 and fr == 0 and d == 120  # windows 0-60 and 540-600
    f = str(tmp_path / "arr_rigA_0.mdd")
    write_arrhythmic(f)
    _, S, _ = mda.myodish_analysis(f, [1, 2, 3], 0, T2, quiet=True)
    cols = list(S.columns)
    assert cols[cols.index("stimFrequency"):cols.index("stimFrequency") + 6] == [
        "stimFrequency", "stimVariability_percent", "arrhythmicFraction", "pacedSeconds", "arrhythmicPacing",
        "detectionThreshold"]
    assert S["arrhythmicPacing"].tolist() == [True, False, False] and S["pacedSeconds"].tolist() == [120] * 3
    assert S["arrhythmicFraction"].tolist() == [1, 0, 0]
    _, S, _ = mda.myodish_analysis(f, [1, 2, 3], 0, T2, quiet=True, arrhythmicDetection=False,
                                   arrhythmicChannels="3")
    assert S["arrhythmicPacing"].tolist() == [False, False, True]
    _, S, _ = mda.myodish_analysis(f, [1, 2, 3], 0, T2, quiet=True, arrhythmicMinFraction=1)
    assert not S["arrhythmicPacing"].any()  # more than 100 %: never
    f2 = str(tmp_path / "arr_rigB_0.mdd")
    write_arrhythmic(f2, protocol=False)  # without the protocol in the log: ch2 variable during 400 of 600 s
    _, S, _ = mda.myodish_analysis(f2, [1, 2, 3], 0, T2, quiet=True)
    assert S["arrhythmicPacing"].tolist() == [True, True, False] and S["pacedSeconds"].tolist() == [T2] * 3
    _, S, _ = mda.myodish_analysis(f, [2], quiet=True, protocol="FFR", arrhythmicChannels=[2])
    assert S["arrhythmicPacing"].all()  # analysis of the protocol: only arrhythmicChannels


def test_report_arrhythmic_pacing_and_stimulus_frequency():
    """arrhythmic pacing: no C, V, missed beats not in the noise index; red F above stim_frequency (2026-10-13)"""
    import pandas as pd
    from myodish_analysis.report import report_flags

    def row(ch, arr, f):
        return {"channel": ch, "from": 0.0, "to": 3600.0, "nDetected": 1000, "nStimuli": 2000, "nMissedBeats": 1200,
                "nExtraBeats": 20, "nUncertain": 300, "nContractions": 1000, "amplitude_mean": 300.0,
                "amplitude_CV": 0.5, "stimFrequency": f, "arrhythmicPacing": arr}
    S = pd.DataFrame([row(1, False, 5.0), row(2, True, 5.0), row(3, False, 50.0), row(4, "True", 50.0)])
    R = report_flags(S)
    assert list(R["flags"]) == ["NCV", "", "NFCV", "F"] and list(R["level"]) == ["check", "", "check", "check"]
    assert R.loc[1, "extraMissed_percent"] == 2 and R.loc[1, "capture_percent"] == 40 and R.loc[1, "arrhythmicPacing"]
    assert R.loc[3, "red"] == "stimulus frequency 50 Hz" and R.loc[0, "stimFrequency_Hz"] == 5
    R = report_flags(S, uncertain=20, irregular=1)
    assert R.loc[1, "red"] == "noise index 1 (uncertain 30 %, extra 2 %, arrhythmic pacing)"
    assert list(report_flags(S, stim_frequency=60)["flags"]) == ["NCV", "", "NCV", ""]


def write_fast_stimulation(f):
    """2 channels, 60 s, 400 Hz: twitches (1000 uN, 30 ms after the pulse) at 1 Hz in both channels; ch1 pulses at 1 Hz,
    ch2 pulses at 20 Hz"""
    Tf, n = 60, 60 * FS
    t = np.arange(n) / FS
    x = np.zeros((3, n))
    x[:2] = -383 + np.round(3 * np.sin(2 * np.pi * 37.3 * t) + 2 * np.sin(2 * np.pi * 91.7 * t))
    beats = np.arange(2.0, Tf - 2)
    for c in (0, 1):
        for p in beats:
            x[c] += 1000 * twitch(t - p - 0.03)
    p1 = 4 * np.round(beats * FS / 4) / FS
    p2 = np.arange(2.0, Tf - 2, 0.05) + 1 / FS
    for c, p in ((1, p1), (2, p2)):
        x[2, np.round(p * FS).astype(int)] = 50 | (c << 9)
    np.round(x).astype("<i2").T.tofile(f)
    name = f.replace("\\", "/").rsplit("/", 1)[-1]
    with open(f[:-4] + "_log.log", "w") as fh:
        fh.write("\n".join(["systemTime;dataLogTime;channel;code;value",
                            "2000 01 01 10:00:00:000;0;0;samplingRate Recording;400",
                            f"2000 01 01 10:00:00:000;0;0;Recording;started: {name}",
                            f"2000 01 01 10:01:00:000;{Tf * 1000};0;Recording;stopped: {name}"]) + "\n")


def test_stimulation_above_10_hz(tmp_path):
    """stimulation > 10 Hz (real stimulation such as CCM pulse pairs, bursts or pulses over consecutive samples): the
    contractions are analysed as at 1 Hz, report flag F (2026-10-18: the exclusion of the contractions was removed
    again)"""
    from myodish_analysis.report import report_flags
    f = str(tmp_path / "fast_rigA_0.mdd")
    write_fast_stimulation(f)
    C, S, info = mda.myodish_analysis(f, [1, 2], 0, 60, quiet=True)
    s1, s2 = S.iloc[0], S.iloc[1]
    assert s1["nContractions"] == 56 and abs(s1["stimFrequency"] - 1) < 1e-9 and s1["amplitude_mean"] > 800
    assert s2["nContractions"] == 56 and abs(s2["stimFrequency"] - 20) < 1e-6
    assert abs(s2["amplitude_mean"] - s1["amplitude_mean"]) < 1e-6 and s2["nStimuli"] == 1120
    assert C.loc[C["channel"] == 2, "included"].all() and (C["channel"] == 2).sum() == 56
    assert not any("stimulation > 10 Hz" in n for n in info["notes"])
    R = report_flags(S)
    assert R.loc[1, "flags"] == "FC" and R.loc[1, "red"] == "stimulus frequency 20 Hz" and R.loc[0, "flags"] == ""
