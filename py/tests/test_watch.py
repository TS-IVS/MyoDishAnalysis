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
    assert not os.path.isfile(os.path.join(res, "A", "example9_ratVentricle_protocols_summary.csv"))  # no protocols
    assert not os.path.isfile(os.path.join(res, W.LOCK_NAME))
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


def test_reanalysis_when_options_or_files_change(raw, tmp_path):
    res = str(tmp_path / "results")
    W.watch(raw, res, quiet=True, protocols=False)
    X, _ = W.watch(raw, res, quiet=True, protocols=False, reanalyze="new", rocker="stopped")
    assert (X["options"] == "binminutes=60; protocols=0").all()  # 'new': other options are ignored
    X, report = W.watch(raw, res, quiet=True, protocols=False, rocker="stopped")
    assert (X["options"] == "binminutes=60; protocols=0; rocker=stopped").all() and report
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
    assert watch_main([raw, res, "--quiet", "--no-protocols", "--bin-minutes", "5", "--set", "rockerFilter=1"]) == 0
    X = W.read_index(res)
    assert (X["status"] == "ok").all() and (X["options"] == "binminutes=5; protocols=0; rockerfilter=1").all()


def test_helpers():
    assert W.parse_date("2026-10-08") == W.parse_date("08.10.2026") == W.parse_date("261008")
    assert W.options_text({"Threshold": [300, float("nan")], "rocker": "stopped", "rockerFilter": True}, 60, True) == \
        "binminutes=60; protocols=1; rocker=stopped; rockerfilter=1; threshold=[300 NaN]"
    assert W.mda_version() == "1.0.0-beta.1" or "-" not in mda.__version__
    assert len(W.code_fingerprint()) == 8
    for f in ("example1_rabbitVentricle", "example9_ratVentricle"):
        assert mda.read_header(os.path.join(EX, f + ".mdd")).recordingStopped is True
