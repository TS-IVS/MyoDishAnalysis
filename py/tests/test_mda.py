# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""pytest tests of the Python port without recordings: the self test (pendant of mda_test.m), the MATLAB-compatible
helpers, options, reference beat (.mat round trip), result files, command line, GUI start and the anonymization of
recordings (py/tools/anonymize_recording.py).

    pytest tests            (in the folder py; recordings / MATLAB results: test_matlab_reference.py)

TS 2026-10-06
"""
from __future__ import annotations

import importlib.util
import json
import math
import os
import shutil
import tempfile
import sys
import warnings

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

import myodish_analysis as mda  # noqa: E402
from myodish_analysis import _matlab as M  # noqa: E402
from myodish_analysis import reference_beat as rb  # noqa: E402
from myodish_analysis.selftest import _S, synthetic_signal  # noqa: E402


# ------------------------------------------------------------------------------------------------ self test
def test_selftest():
    """mda_test.m: exact parameters of synthetic contractions, rocker filter, reference beat."""
    assert mda.selftest(verbose=False)


# ------------------------------------------------------------------------------------------------ helpers
def test_mround_half_away_from_zero():
    assert M.mround(0.5) == 1 and M.mround(-0.5) == -1 and M.mround(2.5) == 3
    assert M.mround(0.49999999999999994) == 0  # float rounding trap of floor(x + 0.5)
    np.testing.assert_array_equal(M.mround(np.array([-1.5, -0.4, 0.4, 1.5])), [-2, 0, 0, 2])


@pytest.mark.parametrize("x,n,expected", [  # results of MATLAB R2026a round(x, n)
    (0.6044999999999999, 3, 0.605), (0.6044999999999998, 3, 0.604), (0.12499999999999999, 2, 0.13),
    (0.12499999999999997, 2, 0.12), (0.7499999999999999, 1, 0.8), (0.7499999999999998, 1, 0.7),
    (3.1415499999999996, 4, 3.1416), (3.141549999999999, 4, 3.1415), (2.4999999999999996, 0, 2),
    (-0.12499999999999999, 2, -0.13), (1249.9999999999998, -2, 1300), (1234.5, -2, 1200), (1.005, 2, 1.01),
    (2.675, 2, 2.68), (0.0004999999999999999, 3, 0), (12345678.123455, 5, 12345678.12346)])
def test_round_digits_as_matlab(x, n, expected):
    assert M.round_digits(x, n) == expected


def _naive_window(x, k, f):
    kb, kf = M._window_bounds(k)
    n = x.size
    return np.array([f(x[max(0, i - kb):min(n, i + kf + 1)]) for i in range(n)])


@pytest.mark.parametrize("k", [1, 2, 3, 4, 7, 10, 25, 64, 129])
def test_movmean_movmedian_against_naive(k):
    rng = np.random.default_rng(k)
    x = rng.standard_normal(1000) * 100
    x[[5, 400, 401]] = np.nan
    np.testing.assert_allclose(M.movmean(x, k), _naive_window(x, k, np.nanmean), rtol=1e-12, atol=1e-10)
    np.testing.assert_allclose(M.movmedian(x, k), _naive_window(x, k, np.nanmedian), rtol=1e-12, atol=1e-10)


def test_window_bounds_as_matlab():
    assert M._window_bounds(5) == (2, 2)  # odd: centred
    assert M._window_bounds(4) == (2, 1)  # even: one more sample backwards (MATLAB movmean / movmedian)


def test_islocalmax_plateau_and_prominence():
    x = np.array([0, 1, 3, 3, 3, 1, 0, 2, 0, 5, 5, 4], float)
    tf, P = M.islocalmax(x)
    assert np.flatnonzero(tf).tolist() == [3, 7, 9]  # centre of a plateau (even length: the first of the two)
    assert P[3] == 3 and P[7] == 2 and P[9] == 1  # last peak: base = the lower end value 4
    assert np.all(P[2:5] == 3)  # prominence on the whole plateau (MATLAB)


def test_colon_linspace_std():
    # values printed by MATLAB R2026a with %.17g
    np.testing.assert_array_equal(M.colon(0, 0.1, 0.3), [0, 0.10000000000000001, 0.19999999999999998,
                                                          0.29999999999999999])
    np.testing.assert_array_equal(M.colon(0.1, 0.1, 0.5), [0.10000000000000001, 0.20000000000000001,
                                                            0.30000000000000004, 0.40000000000000002, 0.5])
    np.testing.assert_array_equal(M.colon(3, 2, 11), [3, 5, 7, 9, 11])
    np.testing.assert_array_equal(M.linspace(-0.3, 1.7, 6), [-0.29999999999999999, 0.10000000000000003, 0.5,
                                                              0.89999999999999991, 1.3, 1.7])
    c = M.colon(0, 0.005, 20)
    assert c.size == 4001 and c[0] == 0 and c[-1] == 20 and c[2000] == 10
    assert M.colon(1, 1, 0).size == 0
    np.testing.assert_allclose(M.linspace(0, 1, 5), [0, 0.25, 0.5, 0.75, 1], rtol=0, atol=0)
    assert M.nanstd(np.array([3.0])) == 0  # MATLAB std of one value
    assert math.isnan(M.nanstd(np.array([np.nan])))


def test_datenum():
    import datetime as dt
    assert M.datenum(1970, 1, 1) == 719529
    d = M.datetime_to_datenum(dt.datetime(2026, 10, 6, 12, 0, 0))
    assert d == M.datenum(2026, 10, 6, 12)
    assert M.datenum_to_datetime(d) == dt.datetime(2026, 10, 6, 12, 0, 0)


# ------------------------------------------------------------------------------------------------ options
def test_options_case_insensitive_and_checked():
    o = mda.options(threshold=300, MEDIANFILTERMS=20)
    assert o.threshold == 300 and o.medianFilterMs == 20
    o2 = mda.options(o, rockerFilter=True)
    assert o2.rockerFilter and not o.rockerFilter  # the base is not changed
    with pytest.raises(Exception):
        mda.options(noSuchOption=1)


def test_parameters_table():
    names = mda.parameters()["name"].tolist() if isinstance(mda.parameters(), pd.DataFrame) else \
        [p[0] for p in mda.PARAMETERS]
    for nm in ("amplitude", "TTP90", "TTR90", "CD90", "AUC", "dFdtMax"):
        assert nm in names


# ------------------------------------------------------------------------------------------------ analysis
@pytest.fixture(scope="module")
def synthetic_beats():
    rng = np.random.default_rng(7)
    dt = 0.005
    t = M.colon(0, dt, 30)
    onset = np.arange(1, 29, dtype=float)
    F = synthetic_signal(t, onset, amp=1000 * (1 + 0.02 * rng.standard_normal(onset.size)),
                         noise=5 * rng.standard_normal(t.size))
    S = _S(t, F, onset)
    B, C = mda.analyze_channel(S, 1, [0.5, 29.5], mda.options(zeroForce=40))
    return S, B, C


def test_analyze_channel_units_and_columns(synthetic_beats):
    _, B, _ = synthetic_beats
    assert len(B) == 28
    assert B.attrs["units"]["amplitude"] in ("uN", "µN")
    assert set(["t_peak", "amplitude", "TTP90", "beatType", "included"]).issubset(B.columns)
    assert np.all(np.abs(B["amplitude"] - 1000) < 100)


def test_reference_beat_mat_round_trip(tmp_path, synthetic_beats):
    S, B, C = synthetic_beats
    R = rb.create(C, B, np.arange(2, 20))
    f = tmp_path / "ref.mat"
    rb.save_reference(str(f), R)
    R2 = rb.load_reference(str(f))[0]
    for k in ("tGrid", "mean", "sd", "meanNorm", "sdNorm"):
        np.testing.assert_allclose(np.asarray(R2[k], float), np.asarray(R[k], float), rtol=0, atol=0)
    assert R2.align == R.align and int(R2.n) == int(R.n)
    B1, _ = mda.analyze_channel(S, 1, [0.5, 29.5], mda.options(zeroForce=40, referenceBeat=R))
    B2, _ = mda.analyze_channel(S, 1, [0.5, 29.5], mda.options(zeroForce=40, referenceBeat=R2))
    pd.testing.assert_series_equal(B1["refMaxDeviation_SD"], B2["refMaxDeviation_SD"])
    assert np.all(B1["refCorrelation"].iloc[2:20] > 0.99)


def test_write_results_xlsx_and_csv(tmp_path, synthetic_beats):
    _, B, _ = synthetic_beats
    _, B, C = synthetic_beats
    Sm = mda.summarize(B, C, [0.5, 29.5])
    info = {"file": "synthetic.mdd", "samplingRate": 200, "samplingRateSource": "test", "nChannelsInFile": 1,
            "totalSeconds": 30.0, "recordingStart": math.nan, "options": mda.options(zeroForce=40)}
    for name in ("res.xlsx", "res.csv"):
        mda.write_results(str(tmp_path / name), B, Sm, info)
    x = pd.read_excel(tmp_path / "res.xlsx", sheet_name=None)
    assert "contractions" in x and len(x["contractions"]) == len(B)
    np.testing.assert_allclose(x["contractions"]["amplitude"].to_numpy(), B["amplitude"].to_numpy(), rtol=1e-12)
    assert any(p.name.startswith("res") and p.suffix == ".csv" for p in tmp_path.iterdir())


def test_summarize_several_ranges(synthetic_beats):
    """summary of several analysed ranges (rows [from to]) = pooled contractions and stimuli of the ranges
    (2026-10-14)"""
    _, B, C = synthetic_beats
    R = np.array([[0.5, 10.5], [15.5, 29.5]])
    Sm = mda.summarize(B, C, R)
    t = B["t_peak"].to_numpy(float)
    inR = ((t >= R[0, 0]) & (t <= R[0, 1])) | ((t >= R[1, 0]) & (t <= R[1, 1]))
    assert Sm["from"].iloc[0] == 0.5 and Sm["to"].iloc[0] == 29.5
    assert Sm["nContractions"].iloc[0] == int(np.sum(inR & B["included"].to_numpy(bool)))
    assert Sm["nContractions"].iloc[0] < mda.summarize(B, C, [0.5, 29.5])["nContractions"].iloc[0]
    S1 = mda.summarize(B, C, [0.5, 10.5])
    S2 = mda.summarize(B, C, [15.5, 29.5])
    assert Sm["nContractions"].iloc[0] == S1["nContractions"].iloc[0] + S2["nContractions"].iloc[0]
    assert Sm["nStimuli"].iloc[0] == S1["nStimuli"].iloc[0] + S2["nStimuli"].iloc[0]


def test_rocker_rest_intervals_chunkwise():
    """rocker-at-rest intervals with sample resolution over chunk borders (O.rockerRest of the overview, 2026-10-14)"""
    from myodish_analysis.read_mdd import _rest_intervals
    ivs = []
    op = _rest_intervals(ivs, None, np.array([0, 1, 1, 0, 0, 1, 1], bool), 0.0, 1.0)
    assert ivs == [[1.0, 3.0]] and op == 5.0
    op = _rest_intervals(ivs, op, np.array([1, 1, 0, 1], bool), 7.0, 1.0)
    assert ivs == [[1.0, 3.0], [5.0, 9.0]] and op == 10.0
    op = _rest_intervals(ivs, op, np.array([0, 0], bool), 11.0, 1.0)
    assert ivs[-1] == [10.0, 11.0] and op is None


def test_time_axis_days():
    """time axis labels: m:ss, h:mm, from 2 days 'd h:mm' and whole days (2026-10-14)"""
    pytest.importorskip("pyqtgraph")
    from myodish_analysis.gui.timeaxis import time_ticks
    _, lab, unit = time_ticks([0, 300], 300)
    assert unit == "m:ss" and lab[1] == "0:30"
    _, lab, unit = time_ticks([0, 6 * 3600], 6 * 3600)
    assert unit == "h:mm" and "1:00" in lab
    tk, lab, unit = time_ticks([0, 3 * 86400], 3 * 86400)
    assert unit == "d h:mm" and lab[tk.tolist().index(86400.0)] == "1 d 0:00"
    tk, lab, unit = time_ticks([0, 20 * 86400], 20 * 86400)
    assert unit == "days" and lab[1] == f"{int(tk[1] / 86400)} d"


# ------------------------------------------------------------------------------------------------ rocker state from the log
def test_rocker_intervals_from_log():
    from myodish_analysis.read_mdd import rocker_intervals_from_log, rocker_state_from_log
    # moving before the first entry; entries before the recording (-Inf) count from 0; delay; end of file
    R = np.array([[-np.inf, 60], [10, 0], [20, 60], [25, 90], [30, 0], [50, 60]], float)
    I = rocker_intervals_from_log(R, 0.27, 40.0)
    np.testing.assert_allclose(I, [[0, 10.27], [20.27, 30.27]])
    assert rocker_intervals_from_log(np.array([[-np.inf, 0], [5, 60]], float), 0.0, 8.0).tolist() == [[5.0, 8.0]]
    assert rocker_intervals_from_log(np.zeros((0, 2)), 0.27, 8.0).shape == (0, 2)
    on = rocker_state_from_log(I, np.array([-1, 0, 10.26, 10.27, 20.27, 30.0, 35.0]))
    assert on.tolist() == [False, True, True, False, True, True, False]


EX = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "examples"))


@pytest.mark.skipif(not os.path.isdir(EX), reason="example recordings not available")
def test_rocker_source_examples():
    # example 8: rocker bit missing although the log has rocker speeds > 0 --> state from the log
    H = mda.read_mdd(os.path.join(EX, "example8_rabbitVentricle_EP.mdd"))
    assert H.rockerSource == "log" and H.rockerLogIntervals.shape[0] == 17
    S = mda.read_mdd(H, 0, H.totalSeconds)
    assert 0.5 < S.rockerOn.mean() < 0.55
    # example 3: rocker bit present; the state reconstructed from the log agrees with it
    f = os.path.join(EX, "example3_humanVentricle.mdd")
    H = mda.read_mdd(f)
    assert H.rockerSource == "status channel"
    S = mda.read_mdd(H, 0, H.totalSeconds)
    Hl = mda.read_mdd(f, opts=mda.options(rockerSource="log"))
    Sl = mda.read_mdd(Hl, 0, H.totalSeconds)
    assert np.mean(S.rockerOn == Sl.rockerOn) > 0.999
    assert np.mean(S.stim.rockerOn == Sl.stim.rockerOn) > 0.999
    with pytest.raises(ValueError):
        mda.options(rockerSource="x")


# ------------------------------------------------------------------------------------------------ protocols / log file
def _write_log(path, rows):
    # lines: systemTime;dataLogTime_ms;channel;code;value
    path.write_text("\n".join(f"{a};{int(round(b * 1000))};{c};{d};{e}" for a, b, c, d, e in rows) + "\n",
                    encoding="utf-8")
    return str(path)


def test_find_protocols_comments_and_schedule_files(tmp_path):
    S = "2026 01 01 06:00:00:000"
    log = _write_log(tmp_path / "x_log.log", [
        (S, 0, 0, "Recording", "started parallel recording: C:\\data\\x.mdd"),
        (S, 0, 0, "comment", "Started parallel recording: 01.Jan.2026 06:00:00"),
        (S, 1, 0, "comment", "start scheduleFile_humanVentricle_FFR_and_PRP"),       # schedule itself: ignored
        (S, 2, 0, "schedule", "Loaded schedule file C:\\p r\\FFR_60beats_0.2-4Hz.txt"),
        (S, 3, 0, "comment", "FFR protocol started"),
        (S, 100, 0, "comment", "FFR protocol ended"),
        (S, 101, 0, "schedule", "Jumped back from loaded schedule file."),          # older logs: no name
        (S, 110, 0, "schedule", "Loaded schedule file C:\\p\\PD_Test_12Steps.txt"),
        (S, 200, 0, "schedule", "Jumped back from loaded schedule file C:\\p\\PD_Test_12Steps.txt."),
        (S, 210, 0, "schedule", "Loaded schedule file C:\\p\\QC_large.txt"),           # no protocol keyword
        (S, 220, 0, "comment", "start post rest potentiation protocol"),
        (S, 300, 0, "comment", "end post rest potentiation protocol"),
        (S, 310, 0, "schedule", "Jumped back from loaded schedule file C:\\p\\QC_large.txt."),
        (S, 320, 0, "comment", "end scheduleFile_humanVentricle"),
    ])
    P = mda.find_protocols(log)
    assert P["type"].tolist() == ["FFR", "PD", "PRP"]
    assert P["name"].tolist() == ["FFR_60beats_0.2-4Hz", "PD_Test_12Steps", "post rest potentiation protocol"]
    np.testing.assert_allclose(P[["from", "to"]].to_numpy(), [[2, 101], [110, 200], [220, 300]])
    from myodish_analysis.protocols import protocol_type
    assert [protocol_type(n) for n in ("ST_50-8mA_stepSize2mA", "PulseDurationProtocol", "RP_1000-240ms_FJump",
                                       "isoprenalineFrequencyProtocol", "QC_large")] == \
        ["ST", "PD", "RP", "FFR", "other"]


def test_read_log_recording_restarted(tmp_path):
    from myodish_analysis.read_mdd import read_log
    rows = [("2026 01 01 06:00:00:000", 0, 0, "Recording", "started parallel recording: x.mdd"),
            ("2026 01 01 06:00:00:000", 0, 1, "Offset", "100"),
            ("2026 01 01 06:00:05:000", 5, 0, "rockerSpeed", "60"),
            ("2026 01 01 06:05:00:000", 300, 0, "Recording", "stopped parallel recording: x.mdd"),
            # recording started again 1 h later: appended to the .mdd file, dataLogTime continues
            ("2026 01 01 07:05:00:000", 300, 0, "Recording", "started parallel recording: x.mdd"),
            ("2026 01 01 07:05:00:000", 300, 1, "Offset", "120"),
            ("2026 01 01 07:06:00:000", 360, 0, "Recording", "stopped parallel recording: x.mdd")]
    L = read_log(_write_log(tmp_path / "a_log.log", rows))
    assert abs(L.startDatenum - M.datenum(2026, 1, 1, 6, 0, 0)) < 1e-9     # first start
    assert L.recordingDuration == 360
    np.testing.assert_allclose(L.rockerSpeedEvents, [[5, 60]])
    np.testing.assert_allclose(L.offsetEvents, [[0, 1, 100], [300, 1, 120]])
    # a new recording in the same log file (dataLogTime starts again): the later start counts
    rows2 = rows[:4] + [("2026 01 01 08:00:00:000", 0, 0, "Recording", "started parallel recording: x.mdd"),
                        ("2026 01 01 08:00:10:000", 10, 0, "rockerSpeed", "30")]
    L2 = read_log(_write_log(tmp_path / "b_log.log", rows2))
    assert abs(L2.startDatenum - M.datenum(2026, 1, 1, 8, 0, 0)) < 1e-9
    np.testing.assert_allclose(L2.rockerSpeedEvents, [[-np.inf, 60], [10, 30]])


@pytest.mark.skipif(not os.path.isdir(EX), reason="example recordings not available")
def test_prp_groups_example7():
    # one group per pause (steps 1-7), 2nd interval after a pause / lower rate at the end are no rests,
    # 'after rest' is not part of the steady reference
    _, S, _ = mda.myodish_analysis(os.path.join(EX, "example7_pigVentricle.mdd"), 1, protocol="PRP", quiet=True)
    R = S[S["groupRole"] == "postRest"]
    assert R["group"].tolist() == ["rest 2 s", "rest 3 s", "rest 5 s", "rest 9 s", "rest 16 s", "rest 31 s", "rest 61 s"]
    assert R["groupStep"].tolist() == [1, 2, 3, 4, 5, 6, 7]
    assert set(S["group"]) == set(R["group"]) | {"steady", "after rest", "other"}
    st = S[S["group"] == "steady"].iloc[0]
    assert st["nContractions"] == 8 and st["amplitude_pctOfRef"] == 100
    # reference 'preceding' (default): last 6 contractions before each pause; 'steady' (<= 1.0.0-beta.3): 115-125 %
    assert 120 < R["amplitude_pctOfRef"].max() < 130
    _, S0, _ = mda.myodish_analysis(os.path.join(EX, "example7_pigVentricle.mdd"), 1, protocol="PRP", quiet=True,
                                    prpReference="steady")
    assert 115 < S0.loc[S0["groupRole"] == "postRest", "amplitude_pctOfRef"].max() < 125


@pytest.mark.skipif(not os.path.isdir(EX), reason="example recordings not available")
def test_protocol_results_examples():
    def res(f, ch, **kw):
        return mda.myodish_analysis(os.path.join(EX, f), ch, quiet=True, **kw)[2]["protocolResults"].iloc[0]
    r = res("example8_rabbitVentricle_EP.mdd", 1, protocol="RP", rocker="any")  # S2 463 ms: none, 492 ms: full
    assert 463 < r["refPeriodNoPeak_ms"] < 492 and r["refPeriodNoPeakStep_ms"] == 30  # 492.5 - 462.5 (0.5-ms steps)
    assert 463 <= r["refPeriodNoResponse_ms"] < 492 and r["S2noiseLevel_pct"] < 10
    r = res("example3_humanVentricle.mdd", 6, protocol="FFR")
    assert r["maxCapturedFrequency_Hz"] == 4 and 90 < r["FFR_1Hz_pct"] < 115 and 60 < r["FFR_3Hz_pct"] < 90
    r = res("example2_rabbitVentricle.mdd", 5, protocol="ST", rocker="any")
    assert r["captureThreshold_mA"] <= r["stimThreshold10_mA"] <= r["stimThreshold50_mA"] <= r["stimThreshold95_mA"] \
        <= r["stimThreshold99_mA"]
    r = res("example7_pigVentricle.mdd", 1, protocol="PRP")
    assert (r["PRP15_pause_s"], r["PRP30_pause_s"], r["PRP60_pause_s"]) == (15, 30, 60)
    assert 120 < r["PRP15_pct"] < 130 and np.isnan(r["FFR_1Hz_pct"])  # reference 'steady' (<= 1.0.0-beta.3): 115-125
    r = res("example8_rabbitVentricle_EP.mdd", 1, protocol="RP", rocker="any")
    assert r["S2shortest_ms"] < r["refPeriodNoPeak_ms"] < r["S2longest_ms"]


def _s1s2_recording(tmp_path, name, s2_ms, fs=400):
    """synthetic S1-S2 protocol as a lab schedule (2026-10-21): 1-Hz S1 pacing, then per step one S1-S2 pair at a
    period of 2 s (S2 after s2_ms), the next S1 1.88 s after the S2 and 1-Hz pacing again; the file ends with two S1
    at 1 s after the last pair. Pulses on the 2.5-ms grid of the status channel."""
    ts = [1.0 + k for k in range(6)]
    for c in s2_ms:
        s1 = ts[-1] + 1.0
        ts += [s1, s1 + c / 1000, s1 + c / 1000 + 1.88]
        ts += [ts[-1] + 1.0 for _ in range(1)]
        ts += [ts[-1] + 1.0 for _ in range(2)]
    ts = np.round(np.array(ts) * fs) / fs
    T = int(np.ceil(ts[-1])) + 1
    n = T * fs
    tt = np.arange(n) / fs
    F = np.full(n, 2000.0)
    for t0 in ts:
        a = t0 + 0.03
        m = (tt >= a) & (tt < a + 0.05)
        F[m] = np.maximum(F[m], 2000 + 1000 * (tt[m] - a) / 0.05)
        m = (tt >= a + 0.05) & (tt < a + 0.15)
        F[m] = np.maximum(F[m], 3000 - 1000 * (tt[m] - a - 0.05) / 0.1)
    X = np.zeros((9, n), np.int16)
    X[0] = np.round(F).astype(np.int16)
    code = np.zeros(n, np.uint16)
    code[np.round(ts * fs).astype(int)] = 512 + 50
    X[8] = code.view(np.int16)
    mdd = str(tmp_path / f"{name}.mdd")
    X.T.astype("<i2").tofile(mdd)
    L = ["systemTime;dataLogTime;channel;code;value", "2026 01 01 06:00:00:000;0;0;nChannels;9",
         "2026 01 01 06:00:00:000;0;0;Recording;started: x.mdd", "2026 01 01 06:00:00:000;0;0;samplingRate Recording;400"]
    for c in range(1, 9):
        L += [f"2026 01 01 06:00:00:000;0;{c};Calibration;1000", f"2026 01 01 06:00:00:000;0;{c};Offset;0"]
    L.append(f"2026 01 01 06:{T // 60:02d}:{T % 60:02d}:000;{T * 1000};0;Recording;stopped: x.mdd")
    (tmp_path / f"{name}_log.log").write_text("\n".join(L) + "\n")
    return mdd, T


def test_s2_groups_last_pulse_and_grid(tmp_path):
    # 2026-10-21 (as s2GroupTest of mda_test.m; a lab recording of a rat slice, RP schedule 250 -> 120 ms in 10-ms
    # steps): 1) the last stimulus of the file, 1 s after a post-S2 stimulus (1-Hz pacing resumed), was an 'S2 1000
    # ms' (no next interval to show that it is not premature); 2) S2 steps of 10 ms recorded on the 2.5-ms grid
    # (127.5 and 120 ms) fell into one group 'S2 124 ms' (tolerance 7.5 ms, now 5 ms)
    s2 = [250, 230, 207.5, 197.5, 180, 167.5, 150, 140, 127.5, 120]
    mdd, T = _s1s2_recording(tmp_path, "s1s2", s2)
    _, S, _ = mda.myodish_analysis(mdd, 1, 0.5, T, groupBy="S2interval", quiet=True, noFiltering=True,
                                   spikeRemoval=False)
    g = S[S["groupRole"] == "S2"]
    assert g["group"].tolist() == [f"S2 {x:g} ms" for x in sorted(s2)]  # groups sorted by value, 127.5 and 120 apart
    assert "S2 1000 ms" not in S["group"].tolist()
    assert int(S.loc[S["group"] == "S1", "nStimuli"].iloc[0]) == 6 + 3 * 10 - 10  # the last S1 of every step is pre-S2
    assert all(int(x) == 1 for x in g["nStimuli"])
    assert S.loc[S["groupRole"] == "postS2", "nStimuli"].sum() == 10


def test_grouping_tolerances(tmp_path):
    # 2026-10-10 (as groupingTest of mda_test.m): pacing frequency rounded to 0.1 Hz, below 1 Hz to 0.05 Hz (0.49 /
    # 0.5, 0.74 / 0.75, 0.97 / 0.99 / 1.0, 1.96 / 2.0 Hz), pauses within 10 % = one pause length (PRP: their mean)
    fs = 400
    iv = [2.0] * 8 + [2.04] * 8 + [1.3325] * 6 + [1.35] * 6 + [1.0] * 12 + [1.01] * 12 + [0.97] * 12 + [0.5] * 12 + [0.51] * 12
    ffr_end = 1 + sum(iv) + 0.5
    for p_ in (16, 15.5, 31, 32.5):
        iv += [1.0] * 10 + [p_]
    iv += [1.0] * 10
    ts = np.round((1 + np.r_[0, np.cumsum(iv)]) * fs) / fs
    T = int(np.ceil(ts[-1])) + 2
    n = T * fs
    tt = np.arange(n) / fs
    F = np.full(n, 2000.0)
    for t0 in ts:
        a = t0 + 0.03
        m = (tt >= a) & (tt < a + 0.1)
        F[m] = 2000 + 1000 * (tt[m] - a) / 0.1
        m = (tt >= a + 0.1) & (tt < a + 0.3)
        F[m] = 3000 - 1000 * (tt[m] - a - 0.1) / 0.2
    X = np.zeros((9, n), np.int16)
    X[0] = np.round(F).astype(np.int16)
    code = np.zeros(n, np.uint16)
    code[np.round(ts * fs).astype(int)] = 512 + 50  # channel 1, 50 mA
    X[8] = code.view(np.int16)
    mdd = str(tmp_path / "grouping.mdd")
    X.T.astype("<i2").tofile(mdd)
    L = ["systemTime;dataLogTime;channel;code;value", "2026 01 01 06:00:00:000;0;0;nChannels;9",
         "2026 01 01 06:00:00:000;0;0;Recording;started: x.mdd", "2026 01 01 06:00:00:000;0;0;samplingRate Recording;400"]
    for c in range(1, 9):
        L += [f"2026 01 01 06:00:00:000;0;{c};Calibration;1000", f"2026 01 01 06:00:00:000;0;{c};Offset;0"]
    L.append(f"2026 01 01 06:{T // 60:02d}:{T % 60:02d}:000;{T * 1000};0;Recording;stopped: x.mdd")
    (tmp_path / "grouping_log.log").write_text("\n".join(L) + "\n")
    kw = dict(quiet=True, noFiltering=True, spikeRemoval=False)
    _, Sf, If = mda.myodish_analysis(mdd, 1, 0.5, ffr_end, groupBy="pacingFrequency", **kw)
    _, Sp, Ip = mda.myodish_analysis(mdd, 1, ffr_end, T, groupBy="pauseLength", **kw)
    Sf = Sf[Sf["group"] != "unknown"]
    assert sorted(Sf["group"]) == ["0.5 Hz", "0.75 Hz", "1 Hz", "2 Hz"]
    assert sorted(Sf["groupValue"]) == [0.5, 0.75, 1, 2]
    assert int(Sf.loc[Sf["group"] == "1 Hz", "nStimuli"].iloc[0]) == 36
    rf = If["protocolResults"].iloc[0]
    assert rf["maxCapturedFrequency_Hz"] == 2 and abs(rf["FFR_1Hz_pct"] - 100) < 2 and abs(rf["FFR_2Hz_pct"] - 100) < 2
    rest = Sp[Sp["groupRole"] == "postRest"]
    assert rest["group"].tolist() == ["rest 15.8 s #1", "rest 15.8 s #2", "rest 31.8 s #3", "rest 31.8 s #4"]
    rp = Ip["protocolResults"].iloc[0]
    assert abs(rp["PRP15_pause_s"] - 14.75) < 1e-6 and abs(rp["PRP30_pause_s"] - 30.75) < 1e-6
    assert np.isnan(rp["PRP60_pct"]) and "PRP15: mean of 2 pauses" in rp["resultNote"]
    _, Sf2, _ = mda.myodish_analysis(mdd, 1, 0.5, ffr_end, groupBy="pacingFrequency", frequencyResolution=0.01, **kw)
    assert "1.03 Hz" in set(Sf2["group"])  # 0.97 s: a group of its own at 0.01 Hz


def test_old_8_channel_file(tmp_path):
    """old MyoDish file (software 1.0.x, 2026-10-13): 8 force channels at 500 Hz without status channel; the recording
    duration in the log file does not fit the file size: recognized by nChannels 8 / 500 Hz in the log file and no
    channel with the content of a status channel; analysed as unpaced (contractions only, as mda_test.m)"""
    fs, T = 500, 60
    n = T * fs
    tt = np.arange(n) / fs
    F = 2000 + 3 * np.sin(2 * np.pi * 37.3 * tt)
    for a in np.arange(1.0, T - 1):
        m = (tt >= a) & (tt < a + 0.1)
        F[m] += 1000 * (tt[m] - a) / 0.1
        m = (tt >= a + 0.1) & (tt < a + 0.4)
        F[m] += 1000 - 1000 * (tt[m] - a - 0.1) / 0.3
    X = np.zeros((8, n))
    X[0] = F
    X[7] = 1500 + 2 * np.sin(2 * np.pi * 11.1 * tt)  # channel 8 with a sensor signal: no status channel
    mdd = str(tmp_path / "old8.mdd")
    np.round(X).astype("<i2").T.tofile(mdd)
    L = ["systemTime;dataLogTime;channel;code;value", "2020 01 01 06:00:00:000;0;0;nChannels;8",
         "2020 01 01 06:00:00:000;0;0;samplingRate Recording;500",
         "2020 01 01 06:00:00:000;0;0;Recording;started: old8.mdd"]
    for c in range(1, 9):
        L += [f"2020 01 01 06:00:00:000;0;{c};Calibration;1000", f"2020 01 01 06:00:00:000;0;{c};Offset;0"]
    L.append("2020 01 01 06:01:30:000;90000;0;Recording;stopped: old8.mdd")  # 90 s: does not fit the file
    (tmp_path / "old8_log.log").write_text("\n".join(L) + "\n")
    H = mda.read_mdd(mdd)
    assert H.nChannelsInFile == 8 and not H.hasStimChannel and H.samplingRate == 500
    assert any("old 8-channel file" in x for x in H.notes)
    C, S, _ = mda.myodish_analysis(mdd, [1, 8], 0, T, quiet=True)
    c1 = C[C["channel"] == 1]
    assert len(c1) == T - 2 and (c1["beatType"] == "unpaced").all() and c1["stimToPeak"].isna().all()
    assert 900 < c1["amplitude"].median() < 1000 and abs(c1["peakToPeakFrequency"].median() - 1) < 0.01  # filtered peak
    s1 = S[S["channel"] == 1].iloc[0]
    assert s1["nStimuli"] == 0 and s1["nExtraBeats"] == 0 and s1["nMissedBeats"] == 0 and np.isnan(s1["stimFrequency"])
    assert not S["arrhythmicPacing"].any()


def test_protocol_selection(tmp_path):
    # 2026-10-10 (as protocolSelectionTest of mda_test.m): FFR steady state (last 10 contractions of the longest run;
    # 2 Hz with 2:1 capture: none), PRP reference per pause ('preceding': median of the last 6; 'firstTrain': mean of
    # the train)
    fs = 400
    ivF = [2.0] * 15 + [1.0] * 20 + [0.5] * 20 + [2.0] * 3
    tsF = 2 + np.r_[0, np.cumsum(ivF)]
    ampF = 1000 + 10 * np.arange(1, tsF.size + 1)
    t0 = tsF[-1] + 2
    ivP = [1.0] * 11 + [10.0] + [1.0] * 11 + [20.0] + [1.0] * 12
    tsP = t0 + np.r_[0, np.cumsum(ivP)]
    ampP = np.r_[np.arange(920, 1141, 20), 2000, np.arange(940, 1141, 20), 2500, np.full(12, 1000)]
    ts = np.round(np.r_[tsF, tsP] * fs) / fs
    amp = np.r_[ampF, ampP].astype(float)
    hasC = np.ones(ts.size, bool)
    hasC[37:56:2] = False  # 2 Hz (pulses 36 ... 55): 2:1 capture
    T = int(np.ceil(ts[-1])) + 3
    n = T * fs
    tt = np.arange(n) / fs
    F = np.full(n, 2000.0)
    for t_, a_ in zip(ts[hasC], amp[hasC]):
        a = t_ + 0.03
        m = (tt >= a) & (tt < a + 0.1)
        F[m] = 2000 + a_ * (tt[m] - a) / 0.1
        m = (tt >= a + 0.1) & (tt < a + 0.3)
        F[m] = 2000 + a_ - a_ * (tt[m] - a - 0.1) / 0.2
    X = np.zeros((9, n), np.int16)
    X[0] = np.round(F).astype(np.int16)
    code = np.zeros(n, np.uint16)
    code[np.round(ts * fs).astype(int)] = 512 + 50
    X[8] = code.view(np.int16)
    mdd = str(tmp_path / "protsel.mdd")
    X.T.astype("<i2").tofile(mdd)

    def clk(x):
        return "2026 01 01 06:%02d:%02d:%03d" % (int(x // 60), int(x % 60), int(round(1000 * (x % 1))))
    L = ["systemTime;dataLogTime;channel;code;value", "2026 01 01 06:00:00:000;0;0;nChannels;9",
         "2026 01 01 06:00:00:000;0;0;Recording;started: x.mdd", "2026 01 01 06:00:00:000;0;0;samplingRate Recording;400"]
    for c in range(1, 9):
        L += [f"2026 01 01 06:00:00:000;0;{c};Calibration;1000", f"2026 01 01 06:00:00:000;0;{c};Offset;0"]
    for x, txt in ((1.5, "FFR protocol started"), (tsF[-1] + 1, "FFR protocol ended"), (t0 - 0.5, "PRP protocol started"),
                   (tsP[-1] + 1, "PRP protocol ended")):
        L.append("%s;%d;0;comment;%s" % (clk(x), int(round(1000 * x)), txt))
    L.append("%s;%d;0;Recording;stopped: x.mdd" % (clk(T), T * 1000))
    (tmp_path / "protsel_log.log").write_text("\n".join(L) + "\n")
    kw = dict(quiet=True, noFiltering=True, spikeRemoval=False, downsampling=1)
    _, S1, I1 = mda.myodish_analysis(mdd, 1, None, None, protocol="all", **kw)
    _, S0, _ = mda.myodish_analysis(mdd, 1, None, None, protocol="FFR", steadyStateBeats=0, **kw)
    _, S2, _ = mda.myodish_analysis(mdd, 1, None, None, protocol="PRP", prpReference="firstTrain", **kw)

    def g(S, r, nm):
        return S[(S["range"] == r) & (S["group"] == nm)].iloc[0]
    a, a0 = g(S1, "FFR 1", "0.5 Hz"), g(S0, "FFR 1", "0.5 Hz")
    assert a["nContractions"] == 10 and abs(a["amplitude_mean"] - 1115) < 1e-6 and a["groupStep"] == 1
    a2 = S1[(S1["range"] == "FFR 1") & (S1["group"] == "2 Hz")]
    assert g(S1, "FFR 1", "1 Hz")["nContractions"] == 10 and (a2.empty or a2["nContractions"].iloc[0] == 0)
    assert any("no run of captured stimuli at 2 Hz" in x for x in I1["notes"])
    assert a0["nContractions"] == 18 and np.isnan(a0["groupStep"]) and a["irregular"] == 0
    assert abs(g(S1, "PRP 1", "rest 10 s")["amplitude_pctOfRef"] - 100 * 2000 / 1090) < 1e-6
    assert abs(g(S1, "PRP 1", "rest 20 s")["amplitude_pctOfRef"] - 100 * 2500 / 1090) < 1e-6
    assert abs(g(S2, "PRP 1", "rest 10 s")["amplitude_pctOfRef"] - 100 * 2000 / 1040) < 1e-6
    assert abs(g(S2, "PRP 1", "rest 20 s")["amplitude_pctOfRef"] - 100 * 2500 / 1040) < 1e-6


@pytest.mark.skipif(not os.path.isdir(EX), reason="example recordings not available")
def test_threshold_per_channel():
    f = os.path.join(EX, "example3_humanVentricle.mdd")
    _, _, i1 = mda.myodish_analysis(f, [1, 2, 3], 0, 60, quiet=True)
    _, _, i2 = mda.myodish_analysis(f, [1, 2, 3], 0, 60, quiet=True, threshold=[np.nan, 500, np.nan])
    t1, t2 = i1["thresholds"]["threshold_uN"].to_numpy(), i2["thresholds"]["threshold_uN"].to_numpy()
    assert t2[1] == 500 and t2[0] == t1[0] and t2[2] == t1[2]  # NaN = auto
    with pytest.raises(ValueError):
        mda.myodish_analysis(f, [1, 2, 3], 0, 60, quiet=True, threshold=[300, 400])
    with pytest.raises(ValueError):
        mda.options(threshold=-1)
    assert mda.options(threshold="").threshold == "auto"


def test_nav_step():
    pytest.importorskip("pyqtgraph")
    from myodish_analysis.gui.timeaxis import nav_step
    assert nav_step([10, 20], "right", False, (0, 100), 0.3) == [15, 25]
    assert nav_step([10, 20], "left", True, (0, 100), 0.3) == [5, 20]
    assert nav_step([10, 20], "up", False, (0, 100), 0.3) == [12.5, 17.5]
    assert nav_step([10, 20], "down", False, (0, 100), 0.3) == [5, 25]
    assert nav_step([0, 10], "down", False, (0, 100), 0.3) == [0, 20]  # zoom out at the start of the file
    assert nav_step([90, 100], "right", False, (0, 100), 0.3) == [90, 100]
    assert nav_step([2, 4], "left", True, (0, 100), 0.3) == [1, 4]


# ------------------------------------------------------------------------------------------------ command line / GUI
def test_cli_help(capsys):
    from myodish_analysis.cli import main
    with pytest.raises(SystemExit) as e:
        main(["--help"])
    assert e.value.code == 0
    assert "mdd" in capsys.readouterr().out.lower()


def test_gui_starts_without_file():
    pytest.importorskip("PySide6")
    pytest.importorskip("pyqtgraph")
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6 import QtCore, QtWidgets
    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
    from myodish_analysis.gui.main_window import MainWindow
    w = MainWindow()
    w.show()
    app.processEvents()
    assert w.H is None
    w.close()
    w.deleteLater()  # delete the Qt objects now, not at interpreter exit (pyqtgraph items crash there on macOS)
    app.processEvents()
    QtCore.QCoreApplication.sendPostedEvents(None, QtCore.QEvent.Type.DeferredDelete)


@pytest.mark.skipif(not os.path.isdir(EX), reason="example recordings not available")
def test_gui_nav_buttons_trend_channels(monkeypatch):
    """buttons under the force plot (shift + click extends) and the trend of several channels (overlay)"""
    pytest.importorskip("PySide6")
    pytest.importorskip("pyqtgraph")
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6 import QtWidgets
    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])  # noqa: F841
    from myodish_analysis.gui import main_window as mw
    from myodish_analysis.gui.trend import TrendWindow
    w = mw.MainWindow(os.path.join(EX, "example3_humanVentricle.mdd"))
    tw = None
    try:
        w.eFrom.setText("0")
        w.eTo.setText("60")
        w.on_load()
        w.bNav["right"].click()
        assert (w.S.fromSeconds, w.S.toSeconds) == (30, 90)
        monkeypatch.setattr(mw, "_shift_held", lambda: True)
        w.bNav["right"].click()
        assert (w.S.fromSeconds, w.S.toSeconds) == (30, 120)
        w.bNav["up"].click()  # zoom the loaded window (selection in the overview); shift does not matter
        assert (w.S.fromSeconds, w.S.toSeconds) == (52.5, 97.5) and np.asarray(w.range).tolist() == [[52.5, 97.5]]
        monkeypatch.setattr(mw, "_shift_held", lambda: False)
        w.bNav["down"].click()
        assert (w.S.fromSeconds, w.S.toSeconds) == (30, 120) and list(w.pMain.vb.viewRange()[0]) == [30, 120]
        w.bNav["left"].click()
        assert (w.S.fromSeconds, w.S.toSeconds) == (0, 90)
        # trend: channels 1 and 3 overlaid (one calculation, file read once), then channel 3 alone from the cache
        tw = TrendWindow(w)
        tw.pM.setCurrentIndex(0)
        tw.set_channels([1, 3])
        assert tw.pC.currentText() == "Ch 1+3" and tw.pC.itemText(tw.pC.count() - 1) == "several channels ..."
        tw.calc(False)
        assert sorted(tw.data["channel"].unique().tolist()) == [1, 3]
        assert sorted(set(tw.roll[:, 0].tolist())) == [1, 3]
        assert [lbl.text for _, lbl in tw.p.legend.items] == ["Ch 1", "Ch 3"]
        names, tabs = tw.export_tables()
        assert names == ["contractions", "rolling", "files"]
        assert list(tabs[0].columns[:3]) == ["file", "channel", "t_since_start_s"]
        assert list(tabs[1].columns[:2]) == ["channel", "t_since_start_s"] and set(tabs[1]["channel"]) == {1, 3}
        n3 = int((tw.data["channel"] == 3).sum())
        tw.set_channels([3])
        tw.calc(True)
        assert tw.data["channel"].unique().tolist() == [3] and len(tw.data) == n3
        assert tw.pC.currentText() == "Ch 3" and tw.pC.findText("Ch 1+3") >= 0
        c, _, _ = mw.myodish_analysis(w.H.file, [3], [0.0], [float(w.H.totalSeconds)], quiet=True,
                                      **tw._opts(tw.files[0], [3], 0))  # same as channel 3 alone
        assert len(c) == n3
    finally:
        if tw is not None:
            tw.close()
        w.close()
        w.deleteLater()


def test_gui_threshold_keys_overlay():
    pytest.importorskip("PySide6")
    pytest.importorskip("pyqtgraph")
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6 import QtCore, QtWidgets
    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
    from myodish_analysis.gui.main_window import MainWindow
    w = MainWindow(os.path.join(EX, "example3_humanVentricle.mdd"))
    try:
        w.eFrom.setText("0")
        w.eTo.setText("60")
        w.on_load()
        # threshold per channel
        w.cThr.setCurrentIndex(1)
        w.eThr.setText("400")
        w.on_threshold_value()
        assert w.C.threshold == 400 and w.C.thresholdMode == "manual"
        w.cCh.setCurrentIndex(1)
        w.on_channel()
        assert w.C.thresholdMode == "auto" and w.cThr.currentIndex() == 0
        w.cCh.setCurrentIndex(0)
        w.on_channel()
        th = w.thr_of([1, 2])
        assert w.C.threshold == 400 and w.eThr.text() == "400" and th[0] == 400 and math.isnan(th[1])
        # advanced settings (2026-10-10): stimuli: external trigger pulses (none in this file) / auto; gate parameters
        w.api_advanced({"externalTrigger": "on"})
        assert w.opts.externalTrigger == "on" and w.C.stimChannel == 0 and w.C.stimTimes.size == 0
        w.api_advanced({"externalTrigger": "auto", "gateMax": 0.2})
        assert w.opts.externalTrigger == "auto" and w.C.stimChannel == 1 and w.C.stimTimes.size > 0
        assert w.opts.gateMax == 0.2 and "gateMax = 0.2" in w.lStatus.text()
        # 'Advanced' button (2026-10-14): number of changed settings (shortened to the width), red, tool tip lists them
        assert w.bAdv.text() in ("Advanced (1 changed)", "Advanced (1 chgd)", "Adv. (1 chgd)", "Adv. (1)")
        assert w.bAdv.property("changed") and "gateMax = 0.2 (default 0.15)" in w.bAdv.toolTip()
        fm = w.bAdv.fontMetrics()
        w.bAdv.resize(60, w.bAdv.height())
        w.adv_indicator()
        t = w.bAdv.text()
        assert t == "Adv. (1)" or fm.horizontalAdvance(t) <= 44
        assert t != "Advanced (1 changed)" or fm.horizontalAdvance(t) <= 44
        w.bAdv.resize(400, w.bAdv.height())
        w.adv_indicator()
        assert w.bAdv.text() == "Advanced (1 changed)"
        adv = w.adv_win
        adv.ctl["gateCore"].setText("x")
        assert not adv.apply(False) and "enter a number" in adv.lMsg.text()
        adv.defaults()
        assert adv.apply(True) and w.opts.gateMax == 0.15 and not w.adv_win.isVisible()
        assert w.bAdv.text() == "Advanced ..." and not w.bAdv.property("changed")
        assert "default values" in w.bAdv.toolTip()
        # all advanced settings in tabs, settings file save / load, legend of the force plot (2026-10-10)
        from myodish_analysis.advanced import ROWS
        assert adv.tabs.count() == 8 and set(adv.ctl) == {r[0] for r in ROWS}
        f = os.path.join(tempfile.mkdtemp(), "set.csv")
        w.next_file = f
        w.api_advanced({"rfHarmonics": 4, "noisePercentile": 80})
        w.api_advanced("save")
        assert os.path.isfile(f) and w.opts.rfHarmonics == 4
        w.api_advanced({"rfHarmonics": 6, "noisePercentile": 90})
        w.cbRF.setChecked(True)
        w.next_file = f
        w.api_advanced("load")
        assert w.adv_win.ctl["rfHarmonics"].text() == "4" and w.adv_win.pending["rockerFilter"] is False
        assert w.adv_win.apply(False) and w.opts.rfHarmonics == 4 and w.opts.noisePercentile == 80
        assert not w.cbRF.isChecked() and not w.opts.rockerFilter
        w.adv_win.defaults()
        w.adv_win.apply(True)
        leg = w.pMain._mda_legend
        assert leg is not None and "selected contraction" in [it[1].text for it in leg.items]
        w.on_legend(False)
        assert w.pMain._mda_legend is None and "red = selected" in w.pMain.titleLabel.text
        w.on_legend(True)
        assert w.pMain._mda_legend is not None
        # arrow keys: move (loaded window follows), extend, zoom
        w.on_key("right", False)
        assert (w.S.fromSeconds, w.S.toSeconds) == (30, 90)
        w.on_key("right", True)
        assert (w.S.fromSeconds, w.S.toSeconds) == (30, 120)
        w.on_key("up", False)  # zoom: the loaded window (selection), read again
        assert (w.S.fromSeconds, w.S.toSeconds) == (52.5, 97.5) and list(w.pMain.vb.viewRange()[0]) == [52.5, 97.5]
        # overlay: channels of the same range, styles, bands, time course, export tables
        w.overlay_channels([1, 3])
        ov = w.win_overlay
        assert [G["ch"] for G in ov.groups] == [1, 3]
        ov.lb.setCurrentRow(1)
        ov.set_group_style("band", "SEM")
        ov.set_group_style("style", "--")
        ov.set_group_style("name", "test")
        K = ov.content()
        assert [it["kind"] for it in K["items"]] == ["single", "line", "single", "band", "line"]
        assert K["items"][-1]["name"] == "test" and K["items"][-1]["style"] == "--"
        names, tabs = ov.export_tables()
        assert names[0] == "means" and "g2_SEM" in tabs[0].columns and tabs[-1]["legend"].tolist()[1] == "test"
        ov.al.setCurrentIndex(2)
        names, tabs = ov.export_tables()
        assert names[0] == "traces" and list(tabs[0].columns) == ["t_from_first_stimulus_s", "g1", "g2"]
        assert ov.mpl_figure().axes[0].get_xlabel() == "time from the first stimulus of the range (s)"
        w.overlay_channels([3])
        assert [G["ch"] for G in ov.groups] == [3]
        ov.close()
    finally:
        w.close()
        w.deleteLater()
        app.processEvents()
        QtCore.QCoreApplication.sendPostedEvents(None, QtCore.QEvent.Type.DeferredDelete)


@pytest.mark.skipif(not os.path.isdir(EX), reason="example recordings not available")
def test_results_reopened_in_gui_and_rocker_window(tmp_path):
    """results (version, all settings, analysis windows) of myodish_analysis and of a GUI export are opened in the GUI
    again: same contractions; rocker artifact window with export (table info) and figure (2026-10-09)"""
    pytest.importorskip("PySide6")
    pytest.importorskip("pyqtgraph")
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6 import QtCore, QtWidgets
    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
    from myodish_analysis.gui.main_window import MainWindow
    f = os.path.join(EX, "example3_humanVentricle.mdd")
    rx = str(tmp_path / "r.xlsx")
    T, _, _ = mda.myodish_analysis(f, [3, 5], [60, 300], [120, 400], quiet=True, output=rx,
                                   threshold=[np.nan, 150], detection="specific")
    R = mda.read_results(rx)
    assert R["version"] and R["implementation"] == "Python" and R["createdBy"] == "MyoDishAnalysis"
    assert R["channels"] == [3, 5] and R["options"].detection == "specific"
    assert np.isnan(R["options"].threshold[0]) and R["options"].threshold[1] == 150
    assert R["windows"][["windowFrom", "windowTo"]].to_numpy().tolist()[0] == [55, 125]
    ws = []
    try:
        w = MainWindow()
        ws.append(w)
        assert w.open_results(rx, pick=1)
        assert w.ch == 5 and w.thr_user == {5: 150.0} and w.cDet.currentIndex() == 1
        assert np.asarray(w.range).tolist() == [[60.0, 120.0]]
        assert "the same as here" in w.lStatus.text()
        # GUI export with a contraction excluded by the user and a zero force, opened again
        w2 = MainWindow(f)
        ws.append(w2)
        w2.on_load(window=[60, 120])
        w2.cCh.setCurrentIndex(4)
        w2.on_channel()
        t0 = float(w2.B["t_peak"].iloc[3])
        w2.manual_off.append(t0)
        w2.zero_user[5] = -4000.0
        w2.analyze(False)
        w2.next_file = str(tmp_path / "g.csv")
        w2.on_export()
        I = pd.read_csv(tmp_path / "g_info.csv", dtype=str, keep_default_na=False).set_index("key")["value"]
        assert I["createdBy"] == "MyoDishAnalysisGUI" and I["loadedWindow_s"] == "60 120"
        assert I["option_zeroForce"] == "-4000" and I["option_detection"] == "sensitive"
        w3 = MainWindow(str(tmp_path / "g_info.csv"))
        ws.append(w3)
        assert w3.ch == 5 and w3.zero_user == {5: -4000.0} and w3.manual_off == [t0]
        assert "the same as here" in w3.lStatus.text()
        # opened at a channel and window (commands of the analysis report, 2026-10-11)
        w4 = MainWindow(rx, channel=5, window=[70, 90])
        ws.append(w4)
        assert w4.ch == 5 and w4.thr_user == {5: 150.0} and np.asarray(w4.range).tolist() == [[70.0, 90.0]]
        w5 = MainWindow(f, channel=5, window=[70, 90])
        ws.append(w5)
        assert w5.ch == 5 and w5.cCh.currentIndex() == 4 and abs(w5.S.fromSeconds - 70) < 1 and w5.B is not None
        # rocker artifact window: data with the settings (table info), figure
        rw = w2.on_rocker_window()
        names, tabs = rw.export_tables()
        assert names == ["rockerArtifact", "rockerFilter"] and "rockerArtifact_uN" in tabs[0].columns
        np.testing.assert_allclose(tabs[0]["force_minus_zero_before_uN"] - tabs[0]["rockerArtifact_uN"],
                                   tabs[0]["force_minus_zero_after_uN"], atol=1e-9)
        w2.next_file = str(tmp_path / "ra.csv")
        rw.export_data()
        assert {"ra_rockerArtifact.csv", "ra_rockerFilter.csv", "ra_info.csv"} <= set(os.listdir(tmp_path))
        w2.next_file = str(tmp_path / "ra.png")
        rw.save_figure()
        assert os.path.getsize(tmp_path / "ra.png") > 10000
        rw.close()
    finally:
        for w in ws:
            w.close()
            w.deleteLater()
        app.processEvents()
        QtCore.QCoreApplication.sendPostedEvents(None, QtCore.QEvent.Type.DeferredDelete)


@pytest.mark.skipif(not os.path.isdir(EX), reason="example recordings not available")
def test_gui_ep_ylim_artefacts_mouse_pointer(tmp_path):
    """EP plots: y limits (fixed / automatic, drag), stimulus artefacts removed for the display, values at the mouse
    pointer in all plots (2026-10-09)"""
    pytest.importorskip("PySide6")
    pytest.importorskip("pyqtgraph")
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6 import QtCore, QtWidgets
    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
    from myodish_analysis.gui.main_window import MainWindow
    f = os.path.join(EX, "example8_rabbitVentricle_EP.mdd")
    w = MainWindow(f)
    try:
        w.show()
        w.open_ep(f.replace(".mdd", ".mat"))
        app.processEvents()
        EP = w.EP
        st = float(EP.stimTimes[19])
        w.pMain.vb.setXRange(st - 0.05, st + 0.35, padding=0)
        app.processEvents()
        w.draw_ep()
        # values at the mouse pointer: 5 ms after the stimulus (artefact)
        Hv, time = w.hover(st + 0.005, "signal")
        assert [h["name"] for h in Hv] == ["force", "stimuli", "parameter", "signal", "stimulation"]
        assert time.startswith("t = 0:21.77") and "stimulus +5.0 ms" in time
        k = int(round((st + 0.005 - EP.t0) / EP.dt))
        assert Hv[3]["y"] == pytest.approx(float(EP.V[k])) and Hv[3]["text"].endswith(" mV")
        assert Hv[1]["text"].startswith("50 mA, interval 1000 ms") and np.isfinite(Hv[0]["y"])
        assert all(w._hv[id(p)][0].isVisible() for p in w._hover_list())
        txt = w._hv[id(w.pEPv)][2]  # values: top left in the plot (child of the view box), time first under the pointer
        assert txt.parentItem() is w.pEPv.vb and txt.toPlainText().startswith("t = 0:21.77")
        assert w._hv[id(w.pMain)][2].toPlainText() == Hv[0]["text"]
        w.hover(0, "")
        assert not any(w._hv[id(p)][0].isVisible() for p in w._hover_list())
        # stimulus artefacts removed (display): grey straight lines, value marked as replaced
        Vc, RA = mda.remove_artefacts(EP)
        w.ep_set_clean(True)
        m = w.ep_art_mask
        assert w.cbEPclean.isChecked() and m.sum() == sum(round((b - a) / EP.dt) + 1 for a, b in RA)
        assert np.array_equal(Vc[~m], EP.V[~m]) and np.array_equal(w.ep_vc, Vc)
        Hv, _ = w.hover(st + 0.005, "signal")
        assert Hv[3]["text"].endswith("(artefact removed)") and Hv[3]["y"] == pytest.approx(float(Vc[k]))
        lo, hi = w.pEPv.vb.viewRange()[1]
        assert lo > -100 and hi < 40  # without the saturated artefact (+-102 mV)
        # y limits: fixed, kept when the time axis changes, automatic again (double-click / restore view)
        w.ep_set_ylim(1, [-100, 40])
        w.pMain.vb.setXRange(st, st + 0.5, padding=0)
        app.processEvents()
        w.draw_ep()
        assert w.pEPv.vb.viewRange()[1] == pytest.approx([-100, 40])
        assert "fixed y limits" in w.pEPv.titleLabel.text
        w._drag_ep(2, "start", (st, 0.5), (st, 0.5))
        w._drag_ep(2, "finish", (st, 0.5), (st, 2.5))
        assert w.ep_ylim[1] == pytest.approx([0.5, 2.5]) and w.pEPs.vb.viewRange()[1] == pytest.approx([0.5, 2.5])
        w._click_other("ep_v", st, 0, QtCore.Qt.MouseButton.LeftButton, True, None)
        w.ep_set_ylim(2, None)
        assert w.ep_ylim == [None, None] and "fixed" not in w.pEPv.titleLabel.text
        w.ep_set_clean(False)
        assert not w.cbEPclean.isChecked()
        Hv, _ = w.hover(st + 0.1, "force")
        assert Hv[3]["y"] == pytest.approx(float(EP.V[int(round((st + 0.1 - EP.t0) / EP.dt))]))
    finally:
        w.close()
        w.deleteLater()
        app.processEvents()
        QtCore.QCoreApplication.sendPostedEvents(None, QtCore.QEvent.Type.DeferredDelete)


@pytest.mark.skipif(not os.path.isdir(EX), reason="example recordings not available")
def test_gui_first_window_comments_flags():
    """a recording opens with its first 120 s analysed; comments as numbered marks (pointer: text, click: selected in
    the comment window, row selected there: highlighted in the force plot); flags line of the report (2026-10-14)"""
    pytest.importorskip("PySide6")
    pytest.importorskip("pyqtgraph")
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6 import QtCore, QtWidgets
    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
    from myodish_analysis.gui.main_window import MainWindow
    w = MainWindow(os.path.join(EX, "example4_humanAtrium.mdd"))
    try:
        assert (w.S.fromSeconds, w.S.toSeconds) == (0, 120) and w.B is not None and len(w.B)
        assert w.lFlags.full_text().startswith("Flags") and w.main_rec is None and not w.bMain.isVisibleTo(w)
        assert [int(k) for k in w._com["k"]] == [1, 2, 3] and len(w._com_nums) == 3
        t2 = float(w._com["t"][1])
        Hv, _ = w.hover(t2, "force")
        assert "comment 2: addition of 100nM Iso" in Hv[0]["text"]
        Hv, _ = w.hover(t2 + 10, "force")
        assert "comment" not in Hv[0]["text"]
        w.comment_click(2)
        cw = w.win_comments
        assert cw is not None and cw.ut.currentRow() == 1 and cw.ut.item(1, 0).text() == "2"
        assert w.hiT == t2 and w.lStatus.text().startswith("Comment 2 (")
        cw.ut.selectRow(2)  # row of the comment window: highlighted in the force plot
        assert w.hiT == float(w._com["t"][2])
        cw.ef.setText("nothing like this")
        w.comment_click(1)  # hidden by the search: the search is cleared
        assert cw.ef.text() == "" and cw.ut.currentRow() == 0
        cw.close()
    finally:
        w.close()
        w.deleteLater()
        app.processEvents()
        QtCore.QCoreApplication.sendPostedEvents(None, QtCore.QEvent.Type.DeferredDelete)


@pytest.mark.skipif(not os.path.isdir(EX), reason="example recordings not available")
def test_batch_pooled_ranges():
    """several ranges with pooled=True: one row per range and channel plus one 'all ranges' row (2026-10-14)"""
    _, S, _ = mda.myodish_analysis(os.path.join(EX, "example6_ratVentricle.mdd"), [1, 2], [10, 70], [40, 110],
                                   quiet=True, pooled=True)
    assert list(S["range"]) == ["range1", "range1", "range2", "range2", "all ranges", "all ranges"]
    P = S[S["range"] == "all ranges"].set_index("channel")
    for ch in (1, 2):
        Sc = S[(S["channel"] == ch) & (S["range"] != "all ranges")]
        assert P.loc[ch, "nContractions"] == Sc["nContractions"].sum()
        assert (P.loc[ch, "from"], P.loc[ch, "to"]) == (10, 110)


@pytest.mark.skipif(not os.path.isdir(EX), reason="example recordings not available")
def test_gui_several_ranges_rocker_stops(tmp_path):
    """several analysed ranges (shift + drag): pooled summary, export with one row per range, opened again; zoom to
    the selection; select all of the overview; every rocker stop of the overview side by side: exported in file time
    and opened again (2026-10-14)"""
    pytest.importorskip("PySide6")
    pytest.importorskip("pyqtgraph")
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6 import QtCore, QtWidgets
    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
    from myodish_analysis.gui.main_window import MainWindow
    f = os.path.join(EX, "example6_ratVentricle.mdd")
    ws = []
    try:
        w = MainWindow(f, channel=1, window=[0, 300])
        ws.append(w)
        w.api_set_range([10, 40])
        n1 = int(w.api_results()[1]["nContractions"].iloc[0])
        w.api_set_range([70, 110])
        n2 = int(w.api_results()[1]["nContractions"].iloc[0])
        w.api_set_range([10, 40])
        w.api_set_range([70, 110], True)
        assert int(w.api_results()[1]["nContractions"].iloc[0]) == n1 + n2
        w.api_set_range([30, 50], True)  # overlapping ranges are merged
        assert np.asarray(w.range).tolist() == [[10.0, 50.0], [70.0, 110.0]]
        w.zoom_to_selection()
        assert w.pMain.vb.viewRange()[0] == pytest.approx([8.0, 112.0])
        xf = str(tmp_path / "multi.xlsx")
        w.next_file = xf
        w.on_export()
        Ts = pd.read_excel(xf, sheet_name="summary")
        Tc = pd.read_excel(xf, sheet_name="contractions")
        assert list(Ts["range"]) == ["all ranges", "range1", "range2"] and "range" in Tc.columns
        assert Ts["nContractions"].iloc[0] == Ts["nContractions"].iloc[1] + Ts["nContractions"].iloc[2]
        w2 = MainWindow(xf)
        ws.append(w2)
        assert np.asarray(w2.range).tolist() == [[10.0, 50.0], [70.0, 110.0]]
        assert "the same as here" in w2.lStatus.text()
        w.select_all()
        assert w.S.fromSeconds == 0 and w.S.toSeconds == pytest.approx(w.H.totalSeconds, abs=0.1)
        w.cbRocker.setChecked(True)
        app.processEvents()
        w.select_rocker_stops()
        Ov = mda.read_mdd(f, "overview")
        stops = Ov.rockerRest[(Ov.rockerRest[:, 1] - Ov.rockerRest[:, 0]) >= 1]
        assert w.sbs is not None and len(w.sbs["seg"]) == len(stops) == len(w.range) > 10
        np.testing.assert_allclose(w.w2f(np.asarray(w.range)), stops, atol=1e-6)
        xf2 = str(tmp_path / "stops.xlsx")
        w.next_file = xf2
        w.on_export()
        Tc = pd.read_excel(xf2, sheet_name="contractions")
        ins = np.zeros(len(Tc), bool)
        for a, b in stops:
            ins |= (Tc["t_peak"] >= a - 1e-6) & (Tc["t_peak"] <= b + 1e-6)
        assert len(Tc) > 100 and ins.all()
        w3 = MainWindow(xf2)
        ws.append(w3)
        assert w3.sbs is not None and len(w3.sbs["seg"]) == len(stops) and "the same as here" in w3.lStatus.text()
    finally:
        for w in ws:
            w.close()
            w.deleteLater()
        app.processEvents()
        QtCore.QCoreApplication.sendPostedEvents(None, QtCore.QEvent.Type.DeferredDelete)


# ------------------------------------------------------------------------------------------------ status bit 9
def test_current_reached_previous_pulse(tmp_path):
    """bit 9 of the status channel = result of the previous base pulse of the channel (2026-10-20; pendant of
    bit9Checks in mda_testExtraPulses.m): synthetic file, 720 s, 400 Hz; an extra pulse between two base pulses makes a
    bit 9 of the next base pulse ambiguous (NaN)"""
    fs, T = 400, 720
    n = T * fs
    code = np.zeros(n, np.uint16)
    t3 = np.arange(0, 119, 2.0); b3 = np.zeros(t3.size, bool); b3[[0, 3, 10, 29]] = True
    t5 = np.r_[np.arange(0, 40.0), np.arange(100, 111.0)]; b5 = t5 == 100
    t6 = np.r_[np.arange(0, 11.0), 700.0]; b6 = t6 == 700
    for t, b, c, cur, off in ((t3, b3, 3, 40, 0), (t5, b5, 5, 50, 1), (t6, b6, 6, 30, 2)):
        code[np.round(t * fs).astype(int) + off] = c * 512 + cur + 256 * b
    code[np.round(np.r_[51.01, 56.01] * fs).astype(int)] = 32768 + 3 * 512 + 20  # extra pulses of channel 3
    X = np.full((9, n), -383, "<i2")
    X[8] = code.view("<i2")
    f = str(tmp_path / "bit9_rigA_0.mdd")
    X.T.tofile(f)
    lines = ["systemTime;dataLogTime;channel;code;value", "2026 01 01 06:00:00:000;0;0;nChannels;9",
             "2026 01 01 06:00:00:000;0;0;Recording;started: x.mdd", "2026 01 01 06:00:00:000;0;0;samplingRate Recording;400",
             "2026 01 01 06:12:00:000;%d;0;Recording;stopped: x.mdd" % (T * 1000)]
    with open(f[:-4] + "_log.log", "w") as fh:
        fh.write("\n".join(lines) + "\n")
    S, S1, S2 = mda.read_mdd(f, 0, T), mda.read_mdd(f, 0, 50), mda.read_mdd(f, 50, T)
    S3, S4 = mda.read_mdd(f, 0, 57), mda.read_mdd(f, 0, 56.005)  # extra pulse at 56.01 s in the window / after it

    def cr(S, c, x):
        k = (np.asarray(S.stim.channel) == c) & (np.asarray(S.stim.isExtraPulse, bool) == x)
        return np.asarray(S.stim.currentReached, float)[k]

    e3 = np.r_[(~b3[1:]).astype(float), np.nan]
    e3[t3 == 56] = np.nan  # extra pulse at 56.01 s, next base pulse (58 s) with bit 9: ambiguous
    e5 = np.r_[(~b5[1:]).astype(float), np.nan]
    np.testing.assert_array_equal(cr(S, 3, False), e3)
    assert np.isnan(cr(S, 3, True)).all() and cr(S, 3, True).size == 2
    assert e3[t3 == 50][0] == 1  # extra pulse at 51.01 s, next base pulse without bit 9: reached
    np.testing.assert_array_equal(cr(S3, 3, False), e3[:29])
    np.testing.assert_array_equal(cr(S4, 3, False), e3[:29])
    np.testing.assert_array_equal(cr(S, 5, False), e5)
    np.testing.assert_array_equal(np.r_[cr(S1, 3, False), cr(S2, 3, False)], e3)
    np.testing.assert_array_equal(np.r_[cr(S1, 5, False), cr(S2, 5, False)], e5)
    np.testing.assert_array_equal(cr(S, 6, False), np.r_[np.ones(10), 0, np.nan])
    np.testing.assert_array_equal(cr(S1, 6, False), np.r_[np.ones(10), np.nan])


# ------------------------------------------------------------------------------------------------ anonymization
# py/tools/anonymize_recording.py with a log file of the format of software 2.1 (structured JSON lines between the old
# text lines) and a _labels.csv: example recording 9 with a synthetic original name, date, version, PC, user, controller
# serial number, initials and sample ID (all values invented). TS 2026-10-17
AN_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AN_EX = os.path.join(AN_ROOT, "examples", "example9_ratVentricle")
_an_spec = importlib.util.spec_from_file_location("anonymize_recording",
                                                  os.path.join(AN_ROOT, "py", "tools", "anonymize_recording.py"))
an = importlib.util.module_from_spec(_an_spec)
_an_spec.loader.exec_module(an)

AN_NAME = "MD7_010203_01"   # original name of the synthetic recording (date 2001-02-03)
AN_DAYS = -399              # 2001-02-03 -> 2000-01-01
AN_J_OPEN = ('{"v":1,"event":"logOpen","actionId":"QWERTZUIOP-1","by":null,"format":2,"file":"' + AN_NAME + '.mdd",'
             '"role":"main","appended":false,"session":"QWERTZUIOP","software":"2.1.1234.5678","pc":"LAB-PC-07",'
             '"winUser":"jdoe","tz":"W. Europe Standard Time","utcOffset":"+01:00","controllerId":"FT0TEST1A",'
             '"myoDishId":"7"}')
AN_J_ID = ('{"v":1,"event":"identity","actionId":"QWERTZUIOP-2","by":"AB","controllerId":"FT0TEST1A",'
           '"ftdiSerial":"FT0TEST1","kind":"ftdi","myoDishId":"7","port":"COM3",'
           '"pnp":"FTDIBUS\\\\VID_0403+PID_6015+FT0TEST1A\\\\0000"}')
AN_J_DETACH = '{"v":1,"event":"detach","actionId":"QWERTZUIOP-3","by":null,"port":"COM3","reason":"close"}'
AN_J_EXIT = '{"v":1,"event":"exit","actionId":"QWERTZUIOP-4","by":null}'
AN_J_CUT = '{"v":1,"event":"exit","actionId":"QWERTZUIOP-5","by":nu'
AN_SECRETS = ("LAB-PC-07", "jdoe", "FT0TEST1", "FTDIBUS", "1234.5678", AN_NAME, "HX-0042", "2001 02 03", "AB:")
AN_LABELS = ("channel,setupID,sliceID,species,sampleID,sampleGroup,sliceGroup,tissue,treatment,concentration,"
             "concentrationUnit,daysInCulture,cultureStart,comment,analyst,owner,medium\n"
             "1,7,HX-0042_S7C1,rat,HX-0042,,,ventricle,lidocaine,100,uM,5,2001-01-29 09:30,"
             "AB: lidocaine 0 -> 100 uM,AB,CD,M199\n")


def _an_old_log():
    txt = an.read_text(AN_EX + "_log.log")[0]
    return (txt.replace("example9_ratVentricle", AN_NAME).replace("2000 01 01 ", "2001 02 03 ")
            .replace("Version 2.0", "Version 2.1.1234.5678"))


def _an_v2_log(cut=False):
    """the log of example 9 with the structured lines of software 2.1 (logOpen, identity, detach, exit)"""
    out = []
    for ln in _an_old_log().split("\r\n"):
        if ln.endswith("Recording;stopped: " + AN_NAME + ".mdd"):
            out.append("2001 02 03 15:59:52:470;666670;0;system;" + AN_J_DETACH)
        out.append(ln)
        if ln.endswith("LogFile opened: " + AN_NAME + "_log.log"):
            out.append("2001 02 03 15:48:45:732;0;0;system;" + AN_J_OPEN)
        elif ln.endswith("Recording;started: " + AN_NAME + ".mdd"):
            out.append("2001 02 03 15:48:47:733;2000;0;system;" + AN_J_ID)
            out.append("2001 02 03 15:50:00:000;74267;0;Comment;AB: lidocaine 100 uM added at 15:50, 03.02.2001")
        elif ln.endswith("LogFile closed: " + AN_NAME + "_log.log"):
            out.append("2001 02 03 15:59:52:490;666690;0;system;" + AN_J_EXIT)
    if cut:
        out.append("2001 02 03 15:59:52:495;666695;0;system;" + AN_J_CUT)
    return "\r\n".join(out)


@pytest.fixture
def an_rec(tmp_path):
    """the synthetic original recording (.mdd of example 9, v2 log, labels)"""
    d = tmp_path / "orig"
    d.mkdir()
    shutil.copyfile(AN_EX + ".mdd", d / (AN_NAME + ".mdd"))
    an.write_text(str(d / (AN_NAME + "_log.log")), _an_v2_log(cut=True), "utf-16-le", True)
    (d / (AN_NAME + "_labels.csv")).write_bytes(AN_LABELS.encode("utf-8"))
    return d


def _an_json_lines(txt):
    return [(ln.split(";", 4), json.loads(ln.split(";", 4)[4])) for ln in txt.split("\r\n")
            if ln.count(";") >= 4 and ln.split(";", 4)[4].startswith("{") and ln.endswith("}")]


def test_anonymize_v2_log_lines():
    src = _an_v2_log()
    names = an.Pseudonyms()
    txt, comments = an.anonymize_log_text(src, AN_NAME, "rec1", AN_DAYS, ["AB"], names)
    for s in AN_SECRETS:
        assert s not in txt, s
    assert txt.isascii()
    a, b = src.split("\r\n"), txt.split("\r\n")
    assert len(a) == len(b)
    for x, y in zip(a, b):   # codes, channels, dataLogTime unchanged; no ';' inside the value
        fx, fy = x.split(";", 4), y.split(";", 4)
        assert fx[1:4] == fy[1:4] and len(fy) == len(fx) and y.count(";") == x.count(";")
    J = _an_json_lines(txt)
    assert [j["event"] for _, j in J] == ["logOpen", "identity", "detach", "exit"]
    o, i = J[0][1], J[1][1]
    assert list(o) == list(json.loads(AN_J_OPEN))              # order of the fields kept
    assert (o["pc"], o["winUser"], o["software"], o["file"], o["controllerId"], o["by"]) == \
        ("PC", "user", "2.1", "rec1.mdd", "controller1", None)
    assert (i["controllerId"], i["ftdiSerial"], i["pnp"], i["by"]) == \
        ("controller1", "controller2", "USB serial device", "P1")
    assert (o["session"], o["actionId"], o["tz"], o["utcOffset"], o["myoDishId"], o["format"]) == \
        ("QWERTZUIOP", "QWERTZUIOP-1", "W. Europe Standard Time", "+01:00", "7", 2)
    assert J[2][1] == json.loads(AN_J_DETACH) and J[3][1] == json.loads(AN_J_EXIT)
    assert J[0][0][0] == "2000 01 01 15:48:45:732"
    assert comments == ["P1: lidocaine 100 uM added at 15:50, 01.01.2000"]
    assert names.unreadable == []
    # the old text lines exactly as without the structured lines
    old = an.anonymize_log_text(_an_old_log(), AN_NAME, "rec1", AN_DAYS, ["AB"])[0]
    kept = [ln for ln in b if ";system;" not in ln and "Comment;" not in ln]
    assert kept == old.split("\r\n")


def _an_win(*parts, unc=False):
    """a Windows path as written inside a JSON string (backslashes escaped); built here, not written out"""
    bs = "\\\\"
    return (bs + bs if unc else "C" + ":" + bs) + bs.join(parts)


AN_J_NEW = [  # events of the control software 2.2 (fields as in its notes of 2026-10-18 and 2026-10-20; values invented)
    (0, 0, "system", '{"v":1,"event":"user","actionId":"QWERTZUIOP-6","by":"AB","initials":"AB","name":"Anna Beispiel",'
                     '"previous":"CD"}'),
    (0, 3, "slice", '{"v":1,"event":"slice_mount","actionId":"QWERTZUIOP-7","by":"AB","mount":"QWERTZUIOP-7",'
                    '"sliceId":"HX-0042_S7C3","myoDishId":"7","controllerId":"FT0TEST1A","user":"AB","species":"rat",'
                    '"sampleId":"HX-0042","sampleGroup":"","sliceGroup":"DEX","tissue":"ventricle","treatment":"",'
                    '"concentration":100,"concentrationUnit":"nM","cultureStart":"2001-01-29T09:30:00+01:00",'
                    '"installTime":"2001-02-03T10:20:00+01:00","chamberId":"C-00417","owner":"CD","medium":"M199"}'),
    (5, 3, "slice", '{"v":1,"event":"slice_remove","actionId":"QWERTZUIOP-8","by":"AB","mount":"QWERTZUIOP-7",'
                    '"sliceId":"HX-0042_S7C3","sampleId":"HX-0042","chamberId":"C-00417","owner":"CD",'
                    '"removeTime":"2001-02-03T11:40:00+01:00","reason":"AB: end, see '
                    + _an_win("Data", "HX-0042", "notes.txt") + '",'
                    '"destination":"fixed 03.02.2001","removedBy":"AB"}'),
    (6, 0, "scheduleRun", '{"v":1,"event":"start","actionId":"QWERTZUIOP-9","by":"CD","run":"QWERTZUIOP-9",'
                          '"file":"FFR_AB.txt","path":"' + _an_win("Users", "jdoe", "schedules", "FFR_AB.txt")
                          + '","size":288,'
                          '"sha256":"16ab"}'),
    (7, 0, "scheduleRun", '{"v":1,"event":"load","actionId":"QWERTZUIOP-10","by":"auto","run":"QWERTZUIOP-10",'
                          '"file":"sub_AB.txt","path":"' + _an_win("Users", "jdoe", "sub_AB.txt")
                          + '","parentFile":"FFR_AB.txt",'
                          '"line":9}'),
    (8, 0, "protocolRun", '{"v":1,"event":"start","actionId":"QWERTZUIOP-11","by":"AB","run":"QWERTZUIOP-11",'
                          '"type":"FFR","name":"FFR_AB 03.02.2001","scheduleFile":"FFR_AB.txt","line":3}'),
    (9, 1, "doc", '{"v":1,"event":"action","actionId":"QWERTZUIOP-12","by":"AB","action":"Added substance",'
                  '"kind":"addition","channels":[1],"sliceId":"HX-0042_S7C1","mount":null,'
                  '"time":"2001-02-03T10:45:12+01:00","substance":"isoprenaline","concentration":0.1,"unit":"uM",'
                  '"comment":"AB: first dose","takesChamberOut":false,"run":null}'),
    (10, 0, "backup", '{"v":1,"event":"backup_setting","actionId":"QWERTZUIOP-13","by":"AB","copy":true,'
                      '"target":"' + _an_win("server", "lab", "jdoe", "backup", unc=True) + '","previousTarget":"",'
                      '"parallel":false}'),
    (11, 0, "backup", '{"v":1,"event":"backup_failed","actionId":"QWERTZUIOP-14","by":"auto","file":"'
                      + AN_NAME + '.mdd",'
                      '"to":"' + _an_win("server", "lab", "jdoe", "backup", unc=True) + '","reason":"access denied: '
                      + _an_win("server", "lab", "jdoe", "backup", AN_NAME + ".mdd", unc=True) + '","retryMinutes":10}'),
    (12, 0, "system", '{"v":1,"event":"dataFolder","actionId":"QWERTZUIOP-15","by":"auto","file":"'
                      + AN_NAME + '.mdd",'
                      '"role":"main","kind":"sync","client":"LabSyncBox","evidence":"'
                      + _an_win("Users", "jdoe", "LabSyncBox")
                      + '","folder":"' + _an_win("Users", "jdoe", "LabSyncBox", "HX-0042") + '","answer":null}'),
    (13, 2, "chamber", '{"v":1,"event":"chamber_in","actionId":"QWERTZUIOP-16","by":"auto","kind":"back",'
                       '"out":"QWERTZUIOP-5","ago":3.0,"duration":40.5,"check":"rigor"}'),
    (14, 2, "rigor", '{"v":1,"event":"check_answer","actionId":"QWERTZUIOP-17","by":"AB","rigor":true,'
                     '"answer":"unchanged","reason":"chamberBack","trigger":"QWERTZUIOP-16","slice":null,'
                     '"mount":"QWERTZUIOP-7","sliceId":"HX-0042_S7C2","cultureStartUnknown":false}')]
AN_NEW_SECRETS = ("Anna", "Beispiel", "HX-0042", "C-00417", "jdoe", "server", "LabSyncBox", "Data",
                  "2001-01-29", "2001-02-03", "03.02.2001", "_AB", "AB:", '"AB"', '"CD"', "FT0TEST1")


def test_anonymize_events_2_2():
    """fields of the slice, user, schedule, protocol, doc, backup, folder, chamber and rigor events (2026-10-20)"""
    rows = ["systemTime;dataLogTime;channel;code;value"]
    rows += ["2001 02 03 10:%02d:00:000;%d;%d;%s;%s" % (t, 1000 * t, ch, code, j) for t, ch, code, j in AN_J_NEW]
    names = an.Pseudonyms()
    txt = an.anonymize_log_text("\r\n".join(rows), AN_NAME, "rec1", AN_DAYS, ["AB"], names)[0]
    for x in AN_NEW_SECRETS:
        assert x not in txt, x
    assert txt.isascii() and len(txt.split("\r\n")) == len(rows)
    J = [j for _, j in _an_json_lines(txt)]
    u, m, r, s1, s2, p, d, b1, b2, f, c, g = J
    assert (u["by"], u["initials"], u["name"], u["previous"]) == ("P1", "P1", "P1", "P2")
    assert (m["sliceId"], m["sampleId"], m["user"], m["owner"], m["chamberId"]) == ("S1_S7C3", "S1", "P1", "P2",
                                                                                    "chamber1")
    assert (m["cultureStart"], m["installTime"]) == ("1999-12-27T09:30:00+01:00", "2000-01-01T10:20:00+01:00")
    assert (m["species"], m["tissue"], m["sliceGroup"], m["myoDishId"], m["controllerId"], m["concentration"]) == \
        ("rat", "ventricle", "DEX", "7", "controller1", 100)
    assert (r["removeTime"], r["reason"], r["destination"], r["removedBy"]) == \
        ("2000-01-01T11:40:00+01:00", "P1: end, see notes.txt", "fixed 01.01.2000", "P1")
    assert (s1["file"], s1["path"], s1["by"], s1["sha256"], s1["size"]) == ("FFR_P1.txt", "FFR_P1.txt", "P2", "16ab",
                                                                             288)
    assert (s2["file"], s2["path"], s2["parentFile"]) == ("sub_P1.txt", "sub_P1.txt", "FFR_P1.txt")
    assert (p["name"], p["scheduleFile"], p["type"]) == ("FFR_P1 01.01.2000", "FFR_P1.txt", "FFR")
    assert (d["sliceId"], d["time"], d["comment"], d["substance"]) == ("S1_S7C1", "2000-01-01T10:45:12+01:00",
                                                                      "P1: first dose", "isoprenaline")
    assert (b1["target"], b1["previousTarget"], b2["to"], b2["file"]) == ("folder1", "", "folder1", "rec1.mdd")
    assert b2["reason"] == "access denied: rec1.mdd" and b2["retryMinutes"] == 10
    assert (f["client"], f["evidence"], f["folder"], f["kind"]) == ("sync client", "removed", "folder2", "sync")
    assert (c["out"], c["duration"], c["check"]) == ("QWERTZUIOP-5", 40.5, "rigor")
    assert (g["sliceId"], g["by"], g["mount"], g["answer"]) == ("S1_S7C2", "P1", "QWERTZUIOP-7", "unchanged")
    assert names.dates == {an.dt.date(2001, 1, 29), an.dt.date(2001, 2, 3)}
    assert "slice_mount species: rat" in names.texts and any(t.startswith("slice_remove reason:") for t in names.texts)


def test_anonymize_initials_pseudonyms():
    """--initials: 'AB: comment' -> 'P1: comment', '_AB' in protocol names -> '_P1', the same pseudonyms as 'by'"""
    src = "\r\n".join(["systemTime;dataLogTime;channel;code;value",
                       "2001 02 03 10:00:00:000;0;0;Comment;AB: medium changed",
                       "2001 02 03 10:00:01:000;1;0;Sequence;Started: FFR_CD.xml",
                       '2001 02 03 10:00:02:000;2;0;system;{"v":1,"event":"x","actionId":"Q-1","by":"CD"}',
                       "2001 02 03 10:00:03:000;3;0;Comment;  CD : AB_test_AB.xml"])
    names = an.Pseudonyms()
    L = an.anonymize_log_text(src, AN_NAME, "rec1", AN_DAYS, ["AB", "CD"], names)[0].split("\r\n")
    assert L[1] == "2000 01 01 10:00:00:000;0;0;Comment;P1: medium changed"
    assert L[2].endswith(";Sequence;Started: FFR_P2.xml")
    assert json.loads(L[3].split(";", 4)[4])["by"] == "P2"
    assert L[4].endswith(";Comment;  P2 : AB_test_P1.xml")
    assert names.map["person"] == {"AB": "P1", "CD": "P2"}


def test_anonymize_umlaut_semicolon_numbers():
    v = ('{"v":1,"event":"note","actionId":"QWERTZUIOP-6","by":"M\\u00fcstermann","text":"M\\u00fcstermann\\u003b Probe 1",'
         '"x":1.50,"y":-0,"z":1e-05,"list":[{"by":"CD"},null,true]}')
    names = an.Pseudonyms()
    txt = an.anonymize_log_text("2001 02 03 10:00:00:000;5;0;doc;" + v, AN_NAME, "rec1", AN_DAYS, (), names)[0]
    f = txt.split(";")
    assert len(f) == 5 and txt.isascii() and "\\u003b" in f[4]
    j = json.loads(f[4])
    assert (j["by"], j["text"], j["list"][0]["by"]) == ("P1", "Müstermann; Probe 1", "P2")
    assert '"x":1.50,"y":-0,"z":1e-05' in f[4]           # numbers exactly as written
    assert names.originals == {"Müstermann": "person", "CD": "person"}


def test_anonymize_unreadable_line_kept():
    names = an.Pseudonyms()
    src = _an_v2_log(cut=True)
    txt = an.anonymize_log_text(src, AN_NAME, "rec1", AN_DAYS, (), names)[0]
    n = len(src.split("\r\n"))
    assert names.unreadable == [n]
    assert txt.split("\r\n")[-1] == "2000 01 01 15:59:52:495;666695;0;system;" + AN_J_CUT


def test_anonymize_labels_and_results(an_rec, tmp_path, capsys):
    out = tmp_path / "anon"
    days = an.anonymize(str(an_rec / (AN_NAME + ".mdd")), "rec1", str(out), initials=["AB"], show=True)
    assert days == AN_DAYS
    assert "1 structured log line(s) could not be read" in capsys.readouterr().out
    log = an.read_text(str(out / "rec1_log.log"))[0]
    lbl = (out / "rec1_labels.csv").read_text(encoding="utf-8")
    for s in AN_SECRETS:
        assert s not in log and s not in lbl, s
    by = [j["by"] for _, j in _an_json_lines(log) if j["by"]]
    L = pd.read_csv(out / "rec1_labels.csv", dtype=str, keep_default_na=False)
    assert list(L.columns) == AN_LABELS.split("\n")[0].split(",")
    r = L.iloc[0]
    assert (r.sampleID, r.sliceID, r.analyst, r.owner, r.cultureStart, r.comment, r.medium) == \
        ("S1", "S1_S7C1", by[0], "P2", "1999-12-27 09:30", "P1: lidocaine 0 -> 100 uM", "M199")
    # MyoDishAnalysis: the same results on the original and on the anonymized recording (clock times shifted)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        from myodish_analysis import myodish_analysis
        c0, s0, i0 = myodish_analysis(str(an_rec / (AN_NAME + ".mdd")), quiet=True)
        c1, s1, i1 = myodish_analysis(str(out / "rec1.mdd"), quiet=True)
    assert len(c0) > 300 and list(c0.columns) == list(c1.columns) and list(s0.columns) == list(s1.columns)
    shift = pd.Timedelta(days=AN_DAYS)
    assert (pd.to_datetime(c1["clockTime"]) - pd.to_datetime(c0["clockTime"]) == shift).all()
    for A, B in ((c0, c1), (s0, s1)):
        for col in A.columns:
            if col in ("clockTime", "file"):
                continue
            x, y = A[col].to_numpy(), B[col].to_numpy()
            if x.dtype.kind in "fiub":
                assert np.array_equal(x, y, equal_nan=True), col
            else:
                assert [str(v) for v in x] == [str(v) for v in y], col
    assert i1["recordingStart"] - i0["recordingStart"] == AN_DAYS
    # time of the last change of the copy: shifted by the same number of days (local time)
    t0, t1 = (an.dt.datetime.fromtimestamp(os.path.getmtime(x))
              for x in (an_rec / (AN_NAME + ".mdd"), out / "rec1.mdd"))
    assert abs((t1 - t0 - an.dt.timedelta(days=AN_DAYS)).total_seconds()) < 1e-3


def test_anonymize_map_file(an_rec, tmp_path):
    mp = str(tmp_path / "study_map.json")
    an.anonymize(str(an_rec / (AN_NAME + ".mdd")), "rec1", str(tmp_path / "a"), initials=["AB"], map_file=mp)
    M = json.load(open(mp, encoding="utf-8"))
    assert M["controller"] == {"FT0TEST1A": "controller1", "FT0TEST1": "controller2"}
    assert M["person"] == {"AB": "P1", "CD": "P2"} and M["sample"] == {"HX-0042": "S1"}
    # second recording of the study: the same pseudonyms, new values continue the numbering
    log = an_rec / (AN_NAME + "_log.log")
    an.write_text(str(log), _an_v2_log().replace('"by":"AB"', '"by":"EF"'), "utf-16-le", True)
    (an_rec / (AN_NAME + "_labels.csv")).write_bytes(AN_LABELS.replace("HX-0042", "HX-0043").encode("utf-8"))
    an.anonymize(str(an_rec / (AN_NAME + ".mdd")), "rec2", str(tmp_path / "b"), initials=["AB"], map_file=mp)
    M = json.load(open(mp, encoding="utf-8"))
    assert M["person"] == {"AB": "P1", "CD": "P2", "EF": "P3"} and M["sample"] == {"HX-0042": "S1", "HX-0043": "S2"}
    L = pd.read_csv(tmp_path / "b" / "rec2_labels.csv", dtype=str, keep_default_na=False)
    assert (L.sampleID[0], L.analyst[0], L.owner[0]) == ("S2", "P1", "P2")
    txt = an.read_text(str(tmp_path / "b" / "rec2_log.log"))[0]
    assert [j["controllerId"] for _, j in _an_json_lines(txt) if "controllerId" in j] == ["controller1"] * 2


def test_anonymize_final_check(an_rec, tmp_path):
    out = tmp_path / "anon"
    with pytest.raises(an.AnonymizationError, match="person 'AB'"):   # initials in a comment, --initials missing
        an.anonymize(str(an_rec / (AN_NAME + ".mdd")), "rec1", str(out))
    assert not os.listdir(out)
    # a structured line that cannot be read and still contains the PC name
    log = an_rec / (AN_NAME + "_log.log")
    an.write_text(str(log), _an_v2_log() + "\r\n2001 02 03 16:00:00:000;700000;0;system;" + AN_J_OPEN[:-40],
                  "utf-16-le", True)
    with pytest.raises(an.AnonymizationError, match="pc 'LAB-PC-07'"):
        an.anonymize(str(an_rec / (AN_NAME + ".mdd")), "rec1", str(out), initials=["AB"])
    # a date of the recording in a form that is not shifted (ISO in a comment)
    an.write_text(str(log), _an_v2_log() + "\r\n2001 02 03 16:00:00:000;700000;0;Comment;protocol of 2001-02-03",
                  "utf-16-le", True)
    with pytest.raises(an.AnonymizationError, match="line 37: date '2001-02-03'"):
        an.anonymize(str(an_rec / (AN_NAME + ".mdd")), "rec1", str(out), initials=["AB"])
    assert not os.listdir(out)
    with pytest.raises(ValueError, match="replace the recording"):
        an.anonymize(str(an_rec / (AN_NAME + ".mdd")), AN_NAME, str(an_rec), initials=["AB"])


def test_anonymize_old_time_stamps_and_versions():
    """time stamps without leading zeros (software before 2.0.7717) are shifted too; versions without build number,
    builds that wrote 12-hour time stamps -> 2.0.7717"""
    src = "\r\n".join(["systemTime;dataLogTime;channel;code;value",
                       "2001 2 3 9:05:00:000;0;0;programInfo;Version 2.0.7745.28699",
                       "2001 02 03 09:05:00:100;0;0;ProgramVersion;2.0.7769.26061",
                       "2001 2 4 0:00:01:000;0;0;programInfo;Version 2.0.9708.42745",
                       "2001 02 04 00:00:02:000;0;0;ProgramVersion;2.0.9708.42745"])
    assert an.first_date(src.splitlines()) == an.dt.date(2001, 2, 3)
    assert an.anonymize_log_text(src, AN_NAME, "rec1", AN_DAYS)[0].split("\r\n")[1:] == [
        "2000 1 1 9:05:00:000;0;0;programInfo;Version 2.0.7717",
        "2000 01 01 09:05:00:100;0;0;ProgramVersion;2.0.7717",
        "2000 1 2 0:00:01:000;0;0;programInfo;Version 2.0",
        "2000 01 02 00:00:02:000;0;0;ProgramVersion;2.0"]


def test_anonymize_broken_lines():
    """lines broken by an interrupted write: rests of paths, own file name, dates and glued time stamps are anonymized
    too; a rest before a glued time stamp becomes '(cut)' (MyoDishAnalysis does not read its time either way)"""
    src = "\r\n".join(["systemTime;dataLogTime;channel;code;value",
                       "2001 02 03 09:52:44:990;100;0;Event;Data log file selected: C:\\Users\\User\\My",
                       "Dish\\data\\XY010203\\" + AN_NAME + ".mdd",
                       "MyoD2001 02 03 09:52:44:998;108;3;chargeDuration;4000",
                       "t C:\\Users\\jdoe\\Box (Jane Doe)2001 02 03 10:20:08:329;200;3;pauseDuration;1000",
                       "2001 02 03 10:20:09:000;210;1;pauseDuration;1000\r"
                       "2001 02 03 10:20:09:001;211;1;chargeDuration;4000",
                       "heduled for 04/02/2001 05:59:57 by AB_AB.xml",
                       "Parametername: index"])
    L = an.anonymize_log_text(src, AN_NAME, "rec1", AN_DAYS, ["AB"])[0].split("\r\n")
    assert L[1:] == ["2000 01 01 09:52:44:990;100;0;Event;Data log file selected: My",
                     "rec1.mdd",
                     "(cut) 2000 01 01 09:52:44:998;108;3;chargeDuration;4000",
                     "(cut) 2000 01 01 10:20:08:329;200;3;pauseDuration;1000",
                     "2000 01 01 10:20:09:000;210;1;pauseDuration;1000\r"
                     "2000 01 01 10:20:09:001;211;1;chargeDuration;4000",
                     "heduled for 02/01/2000 05:59:57 by AB_P1.xml",
                     "Parametername: index"]


def test_anonymize_12_hour_log(tmp_path):
    """software 2.0.7745 (12-hour time stamps): a recording from 13:00 to 13:20 written as 01:00-01:20; the log cannot
    tell AM from PM, the time of the last change of the .mdd file decides. The same on the anonymized copy."""
    from myodish_analysis.read_mdd import read_log
    d = tmp_path / "orig"
    d.mkdir()
    shutil.copyfile(AN_EX + ".mdd", d / (AN_NAME + ".mdd"))
    t = an.dt.datetime(2001, 2, 3, 13, 20, 30).timestamp()
    os.utime(d / (AN_NAME + ".mdd"), (t, t))
    an.write_text(str(d / (AN_NAME + "_log.log")), "\r\n".join([
        "systemTime;dataLogTime;channel;code;value",
        "2001 02 03 01:00:00:000;0;0;programInfo;Version 2.0.7745.28699",
        "2001 02 03 01:00:00:000;0;0;Recording;started: " + AN_NAME + ".mdd",
        "2001 02 03 01:10:00:000;600000;0;Comment;x",
        "2001 02 03 01:20:00:000;1200000;0;Recording;stopped: " + AN_NAME + ".mdd"]), "utf-16-le", True)
    an.anonymize(str(d / (AN_NAME + ".mdd")), "rec1", str(tmp_path / "anon"))
    start = []
    for f in (d / AN_NAME, tmp_path / "anon" / "rec1"):
        L = read_log(str(f) + "_log.log", an.dt.datetime.fromtimestamp(os.path.getmtime(str(f) + ".mdd")))
        start.append(L.startDatenum)
    assert abs((start[0] % 1) * 24 - 13) < 1e-6 and abs(start[1] - start[0] - AN_DAYS) < 1e-9


def test_anonymize_cli(an_rec, tmp_path, capsys):
    mdd = str(an_rec / (AN_NAME + ".mdd"))
    assert an.main([mdd, "rec1", "--outdir", str(tmp_path / "x"), "--initials", "AB"]) is None
    assert "dates shifted by -399 days" in capsys.readouterr().out
    assert an.main([mdd, "rec1", "--outdir", str(tmp_path / "y")]) == 1
    assert "original values are still in the output" in capsys.readouterr().err
