"""pytest tests of the Python port without recordings: the self test (pendant of mda_test.m), the MATLAB-compatible
helpers, options, reference beat (.mat round trip), result files, command line and GUI start.

    pytest tests            (in the folder py; recordings / MATLAB results: test_matlab_reference.py)

TS 2026-10-06
"""
from __future__ import annotations

import math
import os
import tempfile
import sys

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
    assert 463 < r["refPeriodNoPeak_ms"] < 492 and r["refPeriodNoPeakStep_ms"] == 29
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
        assert (w.S.fromSeconds, w.S.toSeconds) == (52.5, 97.5) and list(w.range) == [52.5, 97.5]
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
        adv = w.adv_win
        adv.ctl["gateCore"].setText("x")
        assert not adv.apply(False) and "enter a number" in adv.lMsg.text()
        adv.defaults()
        assert adv.apply(True) and w.opts.gateMax == 0.15 and not w.adv_win.isVisible()
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
        assert w.ch == 5 and w.thr_user == {5: 150.0} and w.cDet.currentIndex() == 1 and w.range == [60.0, 120.0]
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
