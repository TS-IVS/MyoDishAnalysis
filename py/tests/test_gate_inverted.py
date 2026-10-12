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

TS 2026-10-11
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
    st = np.zeros(n)
    for c in (1, 2, 3):  # pulse of channel c one sample after the one of channel c-1
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
    assert report_path("a/res.xlsx") == os.path.join("a", "res_report.pdf") and report_path("res.csv", False) is None
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
    L = legend_lines(FLAG_DEFAULTS)
    assert len(L) == 5 and all(len(t) <= 170 for _, t in L) and "T amplitude changes by > 30 %" in L[2][1]


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
