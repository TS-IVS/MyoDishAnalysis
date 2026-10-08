"""pytest tests of the Python port without recordings: the self test (pendant of mda_test.m), the MATLAB-compatible
helpers, options, reference beat (.mat round trip), result files, command line and GUI start.

    pytest tests            (in the folder py; recordings / MATLAB results: test_matlab_reference.py)

TS 2026-10-06
"""
from __future__ import annotations

import math
import os
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
    assert 115 < R["amplitude_pctOfRef"].max() < 125


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
    assert 115 < r["PRP15_pct"] < 125 and np.isnan(r["FFR_1Hz_pct"])
    r = res("example8_rabbitVentricle_EP.mdd", 1, protocol="RP", rocker="any")
    assert r["S2shortest_ms"] < r["refPeriodNoPeak_ms"] < r["S2longest_ms"]


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
        # stimuli: external trigger pulses (none in this file) / MyoDish / auto
        w.cXT.setCurrentIndex(2)
        w.on_filter()
        assert w.opts.externalTrigger == "on" and w.C.stimChannel == 0 and w.C.stimTimes.size == 0
        w.cXT.setCurrentIndex(0)
        w.on_filter()
        assert w.opts.externalTrigger == "auto" and w.C.stimChannel == 1 and w.C.stimTimes.size > 0
        # arrow keys: move (loaded window follows), extend, zoom
        w.on_key("right", False)
        assert (w.S.fromSeconds, w.S.toSeconds) == (30, 90)
        w.on_key("right", True)
        assert (w.S.fromSeconds, w.S.toSeconds) == (30, 120)
        w.on_key("up", False)
        assert list(w.pMain.vb.viewRange()[0]) == [52.5, 97.5] and w.S.toSeconds == 120
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
