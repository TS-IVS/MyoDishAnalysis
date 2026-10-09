"""pytest tests of the watcher (watch.py / mda-watch, pendant of MyoDishAnalysisWatch.m) on example recordings.

TS 2026-10-08
"""
from __future__ import annotations

import os
import shutil
import sys
import time

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

import myodish_analysis as mda  # noqa: E402
import importlib  # noqa: E402

W = importlib.import_module("myodish_analysis.watch")  # the module (mda.watch is the function)
from myodish_analysis.cli import watch_main  # noqa: E402
from myodish_analysis.log_entries import read_log_text  # noqa: E402

EX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "examples")


def _copy(name, dest, age_s=3600, log=True):
    os.makedirs(dest, exist_ok=True)
    out = []
    for ext in [".mdd", "_labels.csv"] + (["_log.log"] if log else []):
        src = os.path.join(EX, name + ext)
        if os.path.isfile(src):
            shutil.copy(src, dest)
            out.append(os.path.join(dest, name + ext))
    _age(out, age_s)
    return os.path.join(dest, name + ".mdd")


def _age(files, age_s):
    t = time.time() - age_s
    for f in files:
        os.utime(f, (t, t))


@pytest.fixture()
def raw(tmp_path):
    r = tmp_path / "raw"
    _copy("example9_ratVentricle", str(r / "A"))
    _copy("example7_pigVentricle", str(r / "B"))
    return str(r)


def test_first_and_second_pass(raw, tmp_path):
    res = str(tmp_path / "results")
    X, report = W.watch(raw, res, quiet=True, bin_minutes=5)
    assert list(X["file"]) == ["A/example9_ratVentricle.mdd", "B/example7_pigVentricle.mdd"]
    assert (X["status"] == "ok").all() and (X["implementation"] == "Python").all()
    assert (X["version"] == W.mda_version()).all() and (X["code"] == W.code_fingerprint()).all()
    assert "A/example9_ratVentricle.mdd" in report and os.listdir(os.path.join(res, "reports"))
    S = pd.read_csv(os.path.join(res, "A", "example9_ratVentricle_summary.csv"))
    assert len(S) == 3 and list(S["range"]) == ["2000-01-01 15:48:46", "2000-01-01 15:53:46", "2000-01-01 15:58:46"]
    assert S["nContractions"].sum() == X.loc[0, "nContractions"]
    assert os.path.isfile(os.path.join(res, "B", "example7_pigVentricle_protocols_protocolResults.csv"))
    assert X.loc[1, "nContractions"] == 0 and "no time outside the stimulation protocols" in X.loc[1, "message"]
    assert not os.path.isfile(os.path.join(res, "B", "example7_pigVentricle_summary.csv"))
    assert {"bin", "nComments", "comments"} <= set(S.columns)
    assert os.path.isfile(os.path.join(res, "A", "example9_ratVentricle_events.csv"))
    assert not os.path.isfile(os.path.join(res, "A", "example9_ratVentricle_protocols_summary.csv"))  # no protocols
    assert not os.path.isfile(os.path.join(res, W.LOCK_NAME))
    # overview (1-min medians) and slice register
    O = pd.read_csv(os.path.join(res, "A", "example9_ratVentricle_overview.csv"))
    C = pd.read_csv(os.path.join(res, "A", "example9_ratVentricle_contractions.csv"))
    assert len(O) == 12 and O["nBeats"].sum() == len(C) == 333 and list(O["t_from"][:2]) == [0, 60]
    assert O["window"][0] == "2000-01-01 15:48:46" and abs(O["amplitude"][0] - 755.866666666667) < 1e-6
    R = pd.read_csv(os.path.join(res, "mda_slices.csv"), keep_default_na=False)
    a = R[R["experiment"] == "A"].iloc[0]
    assert len(R) == 9 and a["endStatus"] == "beating at end of data" and a["nBeats"] == 333 and a["species"] == "rat"
    assert (R.loc[R["experiment"] == "B", "endStatus"] == "protocols only").all() and "slice register: 9 slices" in report
    assert os.path.isfile(os.path.join(res, "A", "A_slices.csv")) and os.path.isfile(os.path.join(res, "B", "B_slices.csv"))
    X2, report2 = W.watch(raw, res, quiet=True, bin_minutes=5)
    assert report2 == "" and list(X2["analyzed"]) == list(X["analyzed"])


def test_one_bin_equals_direct_analysis(raw, tmp_path):
    res = str(tmp_path / "results")
    W.watch(raw, res, quiet=True, bin_minutes=60, protocols=False)
    f = os.path.join(raw, "A", "example9_ratVentricle.mdd")
    C, S, _ = mda.myodish_analysis(f, quiet=True, metadata=f[:-4] + "_labels.csv")
    Cw = pd.read_csv(os.path.join(res, "A", "example9_ratVentricle_contractions.csv"))
    assert len(Cw) == len(C)
    np.testing.assert_allclose(Cw["t_peak"], C["t_peak"], rtol=0, atol=1e-9)
    np.testing.assert_allclose(Cw["amplitude"], C["amplitude"], rtol=1e-12, equal_nan=True)
    R = mda.read_results(os.path.join(res, "A", "example9_ratVentricle_info.csv"))  # version, settings, windows
    assert R["version"] == W.mda_version() and R["implementation"] == "Python"
    assert R["createdBy"] == "MyoDishAnalysisWatch" and "binminutes=60" in R["extra"]["watcherOptions"]
    assert len(R["windows"]) >= 1 and (R["windows"]["windowFrom"] <= R["windows"]["from"]).all()
    assert R["options"].detection == "sensitive" and len(R["contractions"]) == len(Cw)


def test_reanalysis_when_options_or_files_change(raw, tmp_path):
    res = str(tmp_path / "results")
    W.watch(raw, res, quiet=True, protocols=False)
    base = W.options_text({}, dict(protocols=False))
    X, _ = W.watch(raw, res, quiet=True, protocols=False, reanalyze="new", rocker="stopped")
    assert (X["options"] == base).all()  # 'new': other options are ignored
    X, report = W.watch(raw, res, quiet=True, protocols=False, rocker="stopped")
    assert (X["options"] == base + "; rocker=stopped").all() and report
    log = os.path.join(raw, "A", "example9_ratVentricle_log.log")
    with open(log, "ab") as fh:
        fh.write(b"\x00")
    _age([log], 3600)
    X3, report = W.watch(raw, res, quiet=True, protocols=False, rocker="stopped")
    assert "A/example9_ratVentricle.mdd" in report and "B/example7_pigVentricle.mdd" not in report
    assert X3.loc[0, "logBytes"] == X.loc[0, "logBytes"] + 1
    X4, report = W.watch(raw, res, quiet=True, protocols=False, rocker="stopped", reanalyze="all", max_files=1)
    assert X4.loc[0, "analyzed"] >= X3.loc[0, "analyzed"] and X4.loc[1, "analyzed"] == X3.loc[1, "analyzed"]


def test_outdated_code_or_version(raw, tmp_path):
    res = str(tmp_path / "results")
    W.watch(raw, res, quiet=True, protocols=False)
    X = W.read_index(res)
    X.loc[0, "code"] = "00000000"  # core code changed (same implementation)
    X.loc[1, "version"] = "0.9"
    X.to_csv(os.path.join(res, W.INDEX_NAME), index=False)
    _, report = W.watch(raw, res, quiet=True, protocols=False)
    assert "A/example9" in report and "B/example7" in report
    X = W.read_index(res)
    X.loc[0, "code"] = "00000000"
    X["implementation"] = "MATLAB"  # code of another implementation: only version and options count
    X.to_csv(os.path.join(res, W.INDEX_NAME), index=False)
    _, report = W.watch(raw, res, quiet=True, protocols=False)
    assert report == ""


def test_skipped_recordings(tmp_path):
    raw = str(tmp_path / "raw")
    res = str(tmp_path / "results")
    _copy("example9_ratVentricle", os.path.join(raw, "young"), age_s=0)          # still written
    _copy("example9_ratVentricle", os.path.join(raw, "nolog"), log=False)         # no log file
    f = _copy("example9_ratVentricle", os.path.join(raw, ".hidden"))             # hidden folder
    shutil.copy(f, os.path.join(raw, "nolog", ".example9_ratVentricle.mdd.tmp1.mdd"))  # rsync temporary file
    run = _copy("example9_ratVentricle", os.path.join(raw, "running"))
    txt = read_log_text(run[:-4] + "_log.log")
    lines = [ln for ln in txt.splitlines() if "stopped:" not in ln]
    with open(run[:-4] + "_log.log", "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    _age([run[:-4] + "_log.log"], 3600)
    assert mda.read_header(run).recordingStopped is False
    X, report = W.watch(raw, res, quiet=True)
    st = dict(zip(X["file"], X["status"]))
    assert st == {"nolog/example9_ratVentricle.mdd": "noLog", "running/example9_ratVentricle.mdd": "running"}
    assert report == ""
    X, _ = W.watch(raw, res, quiet=True, incomplete_after_hours=0.5, min_file_age_minutes=0)
    st = dict(zip(X["file"], X["status"]))
    assert st["running/example9_ratVentricle.mdd"] == "ok" and st["young/example9_ratVentricle.mdd"] == "ok"
    assert st["nolog/example9_ratVentricle.mdd"] == "noLog" and len(X) == 3


def test_dry_run_filter_from_date_and_lock(raw, tmp_path, capsys):
    res = str(tmp_path / "results")
    X, _ = W.watch(raw, res, dry_run=True)
    assert len(X) == 0 and "A/example9_ratVentricle.mdd  (new)" in capsys.readouterr().out
    assert not os.path.isfile(os.path.join(res, W.INDEX_NAME))
    X, _ = W.watch(raw, res, quiet=True, filter="example7", protocols=False)
    assert list(X["file"]) == ["B/example7_pigVentricle.mdd"]
    X, _ = W.watch(raw, res, quiet=True, from_date="2099-01-01", protocols=False)
    assert len(X) == 1
    with open(os.path.join(res, W.LOCK_NAME), "w") as fh:
        fh.write("1\n")
    X, msg = W.watch(raw, res, quiet=True, protocols=False)
    assert "another watcher" in msg and len(X) == 1


def test_command_line(raw, tmp_path):
    res = str(tmp_path / "results")
    assert watch_main([raw, res, "--quiet", "--no-protocols", "--bin-minutes", "5", "--set", "rockerFilter=1",
                       "--contractions", "thinned", "--thin-mode", "median", "--thin-factor", "5", "--compress",
                       "--workers", "2"]) == 0
    X = W.read_index(res)
    assert (X["status"] == "ok").all()
    assert X.loc[0, "options"] == ("binminutes=5; compress=1; contractions=thinned; events=1; gaps=1; "
                                   "includeprotocols=0; overviewseconds=60; protocolmarginseconds=0; protocols=0; "
                                   "rockerfilter=1; thinfactor=5; thinmode=median")
    assert os.path.isfile(os.path.join(res, "A", "example9_ratVentricle_contractions.csv.gz"))
    O = pd.read_csv(os.path.join(res, "A", "example9_ratVentricle_overview.csv"))
    assert len(O) and {"window", "t_from", "t_to", "nBeats", "beatsPerMinute", "amplitude"} <= set(O.columns)
    assert os.path.isfile(os.path.join(res, "mda_slices.csv"))


def test_helpers():
    assert W.parse_date("2026-10-08") == W.parse_date("08.10.2026") == W.parse_date("261008")
    assert W.options_text({"Threshold": [300, float("nan")], "rocker": "stopped", "rockerFilter": True}) == \
        ("binminutes=60; compress=0; contractions=all; events=1; gaps=1; includeprotocols=0; overviewseconds=60; "
         "protocolmarginseconds=0; protocols=1; rocker=stopped; rockerfilter=1; threshold=[300 NaN]")
    assert W.event_category("comment", "Started parallel recording: x") == "recording"
    assert W.event_category("comment", "start FFR protocol") == "protocol"
    assert W.event_category("comment", "FFR protocol ended") == "protocol"
    assert W.event_category("comment", "addition of 100nM Iso") == "comment"
    assert W.event_category("stimFrequency", "1") == "stimulation"
    assert W.event_category("Event", "extended sensor mode off") == "calibration"
    for t in ("jump to 60 bpm", "S2 beat 300 ms", "50 mA", "0.5 Hz", "Pause 180seconds", "restored stimulation"):
        assert W.event_category("comment", t) == "protocol", t
    assert W.event_category("comment", "Approaching 2 GB limit. Changing datafile2.") == "recording"
    assert W.event_category("comment", "ZI: MX1.6-1.8 Dexa100nM") == "comment"
    assert W.mda_version() == "1.0.0-beta.3" or "-" not in mda.__version__
    assert len(W.code_fingerprint()) == 8
    for f in ("example1_rabbitVentricle", "example9_ratVentricle"):
        assert mda.read_header(os.path.join(EX, f + ".mdd")).recordingStopped is True


def test_protocols_excluded_or_included(tmp_path):
    raw = str(tmp_path / "raw")
    f = _copy("example2_rabbitVentricle", raw)  # PD 67-327 s, ST 512-658 s
    P = mda.find_protocols(f)
    res = str(tmp_path / "res")
    X, _ = W.watch(raw, res, quiet=True, bin_minutes=5)
    S = pd.read_csv(os.path.join(res, "example2_rabbitVentricle_summary.csv"))
    C = pd.read_csv(os.path.join(res, "example2_rabbitVentricle_contractions.csv"))
    for a, b in zip(P["from"], P["to"]):
        assert not ((C["t_peak"] > a) & (C["t_peak"] < b)).any()
        assert not ((S["from"] < b) & (S["to"] > a)).any()
    assert len(S["range"].unique()) == 3 and (S["bin"] <= S["range"]).all()
    res2 = str(tmp_path / "res2")
    W.watch(raw, res2, quiet=True, bin_minutes=5, include_protocols=True)
    C2 = pd.read_csv(os.path.join(res2, "example2_rabbitVentricle_contractions.csv"))
    inside = np.zeros(len(C2), bool)
    for a, b in zip(P["from"], P["to"]):
        inside |= (C2["t_peak"] >= a).to_numpy() & (C2["t_peak"] <= b).to_numpy()
    assert inside.any() and len(C2) > len(C)
    res3 = str(tmp_path / "res3")
    W.watch(raw, res3, quiet=True, bin_minutes=5, protocol_margin_seconds=30)
    S3 = pd.read_csv(os.path.join(res3, "example2_rabbitVentricle_summary.csv"))
    assert S3["from"].min() == 0 and (S3["from"] > 0).any() and abs(sorted(S3["from"].unique())[1] - (P["to"][0] + 30)) < 1e-6


def test_thinned_contractions(tmp_path):
    raw = str(tmp_path / "raw")
    _copy("example4_humanAtrium", raw)  # extra beats in channels 6-8
    _copy("example9_ratVentricle", raw)
    resA, resN, resM = (str(tmp_path / x) for x in ("all", "nth", "median"))
    W.watch(raw, resA, quiet=True, bin_minutes=5)
    W.watch(raw, resN, quiet=True, bin_minutes=5, contractions="thinned", thin_factor=10)
    W.watch(raw, resM, quiet=True, bin_minutes=5, contractions="thinned", thin_mode="median", thin_factor=10)
    for n in ("example4_humanAtrium", "example9_ratVentricle"):
        A = pd.read_csv(os.path.join(resA, n + "_contractions.csv"))
        Nn = pd.read_csv(os.path.join(resN, n + "_contractions.csv"))
        M = pd.read_csv(os.path.join(resM, n + "_contractions.csv"))
        assert (A["sampledEvery"] == 1).all() and (A["sampleMode"] == "singleBeat").all()
        for T in (Nn, M):  # extra beats complete, every other contraction represented once
            ex = T["beatType"] == "extra"
            assert ex.sum() == (A["beatType"] == "extra").sum() and (T.loc[ex, "sampledEvery"] == 1).all()
            assert T["sampledEvery"].sum() >= (A["beatType"] != "extra").sum() // 10
        assert set(Nn["sampleMode"]) == {"singleBeat"} and set(Nn.loc[Nn["beatType"] != "extra", "sampledEvery"]) <= {10.0}
        assert M.loc[M["sampleMode"] == "median", "sampledEvery"].sum() == (A["beatType"] != "extra").sum()
        for ch in A["channel"].unique():  # every 10th contraction of the channel (time order)
            a = A[(A["channel"] == ch) & (A["beatType"] != "extra")].sort_values("t_peak")
            nn = Nn[(Nn["channel"] == ch) & (Nn["beatType"] != "extra")].sort_values("t_peak")
            np.testing.assert_allclose(nn["t_peak"].to_numpy(), a["t_peak"].to_numpy()[::10])
    # first median block of example 9 = median of its first 10 contractions
    A = pd.read_csv(os.path.join(resA, "example9_ratVentricle_contractions.csv")).sort_values("t_peak")
    M = pd.read_csv(os.path.join(resM, "example9_ratVentricle_contractions.csv")).sort_values("t_peak")
    first = A.iloc[:int(M["sampledEvery"].iloc[0])]
    assert M["amplitude"].iloc[0] == pytest.approx(first["amplitude"].median())
    assert M["t_peak"].iloc[0] == pytest.approx(first["t_peak"].median())


def test_compress_none_and_stale_files(raw, tmp_path):
    res = str(tmp_path / "results")
    W.watch(raw, res, quiet=True, protocols=False)
    f = os.path.join(res, "A", "example9_ratVentricle_contractions.csv")
    assert os.path.isfile(f)
    W.watch(raw, res, quiet=True, protocols=False, compress=True)
    assert os.path.isfile(f + ".gz") and not os.path.isfile(f)
    assert len(pd.read_csv(f + ".gz")) == W.read_index(res).loc[0, "nContractions"]
    W.watch(raw, res, quiet=True, protocols=False, contractions="none")
    assert not os.path.isfile(f + ".gz") and not os.path.isfile(f)
    assert os.path.isfile(os.path.join(res, "A", "example9_ratVentricle_summary.csv"))


def test_events_and_comments(tmp_path):
    raw = str(tmp_path / "raw")
    _copy("example4_humanAtrium", raw)  # comments 'addition of 100nM Iso' in channels 3, 4, 6, 8
    res = str(tmp_path / "res")
    W.watch(raw, res, quiet=True, bin_minutes=5)
    E = pd.read_csv(os.path.join(res, "example4_humanAtrium_events.csv"))
    assert {"clockTime", "t_file", "channel", "code", "category", "text"} <= set(E.columns)
    assert (E.loc[E["text"] == "addition of 100nM Iso", "category"] == "comment").all()
    S = pd.read_csv(os.path.join(res, "example4_humanAtrium_summary.csv"))
    first = S[S["range"] == S["range"].iloc[0]].set_index("channel")
    assert first.loc[3, "comments"] == "addition of 100nM Iso" and first.loc[1, "nComments"] == 0


def test_parallel_workers(raw, tmp_path):
    X1, _ = W.watch(raw, str(tmp_path / "r1"), quiet=True, protocols=False)
    X2, _ = W.watch(raw, str(tmp_path / "r2"), quiet=True, protocols=False, workers=2)
    assert list(X1["file"]) == list(X2["file"]) and list(X1["nContractions"]) == list(X2["nContractions"])
    a = pd.read_csv(str(tmp_path / "r1" / "A" / "example9_ratVentricle_summary.csv"))
    b = pd.read_csv(str(tmp_path / "r2" / "A" / "example9_ratVentricle_summary.csv"))
    pd.testing.assert_frame_equal(a, b)


def test_channel_status_contraction_without_signal():
    """a contraction (artifact) in a channel without signal: status 'no slice', last contraction with clock time
    (crashed with NaN before, TS 2026-10-10)"""
    from types import SimpleNamespace
    H = SimpleNamespace(totalSeconds=600.0, recordingStart=730486.5, dataChannels=np.array([1, 2]))
    G = pd.DataFrame(dict(channel=[1.0], **{"from": [0.0], "to": [600.0]}, type=["no signal"], fromStart=[True],
                          untilEnd=[True], duration=[600.0]))
    C = pd.DataFrame(dict(channel=[1.0, 2.0, 2.0], t_peak=[550.0, 100.0, 590.0], included=[True, True, True],
                          amplitude=[5.0, 100.0, 120.0]))
    CH = W._channel_status(H, C, G, None, "rigA_X_0", None, 600.0)
    r1, r2 = CH.iloc[0], CH.iloc[1]
    assert r1["status"] == "no slice" and r1["nContractions"] == 1 and r1["lastContraction_s"] == 550
    assert r1["lastContractionClock"] == "2000-01-01 12:09:10" and not r1["beatingAtEnd"]
    assert r2["status"] == "beating" and r2["lastContraction_s"] == 590 and r2["lastContractionClock"] == "2000-01-01 12:09:50"
