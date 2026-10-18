# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
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


def _wcsv(*a, **k):
    """the watcher with the results as one csv file per table (result_format='csv'; tests of the analysis itself) in
    the folder of the experiment (folders='flat') and without trend images"""
    k.setdefault("result_format", "csv")
    k.setdefault("trends", False)
    k.setdefault("folders", "flat")
    return W.watch(*a, **k)


def _age(files, age_s):
    t = time.time() - age_s
    for f in files:
        os.utime(f, (t, t))


def _edit_log(log, start_hours_ago=None, recording=None):
    """log file of a copied example: clock times shifted (the recording started start_hours_ago h ago) and / or the
    'Recording' entries replaced by recording = [(dataLogTime ms, text), ...]"""
    import datetime as dt
    lines = read_log_text(log).splitlines()
    if recording is not None:  # 'started' entries at the place of the first, 'stopped' at the last Recording entry
        k = [i for i, ln in enumerate(lines) if ";Recording;" in ln]
        clk = lines[k[0]].split(";")[0]
        new = {i: [] for i in k}
        for t, v in recording:
            new[k[-1] if "stopped" in v else k[0]].append(f"{clk};{t};0;Recording;{v}")
        lines = [x for i, ln in enumerate(lines) for x in (new[i] if i in new else [ln])]
    if start_hours_ago is not None:
        def clock(ln):
            return dt.datetime.strptime(ln.split(";")[0][:19], "%Y %m %d %H:%M:%S")
        t0 = clock(next(ln for ln in lines if ";Recording;started" in ln))
        d = dt.datetime.now() - dt.timedelta(hours=start_hours_ago) - t0
        lines = [lines[0]] + [(clock(ln) + d).strftime("%Y %m %d %H:%M:%S") + ln.split(";")[0][19:] + ln[ln.index(";"):]
                              for ln in lines[1:] if ln.strip()]
    with open(log, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


@pytest.fixture()
def raw(tmp_path):
    r = tmp_path / "raw"
    _copy("example9_ratVentricle", str(r / "A"))
    _copy("example7_pigVentricle", str(r / "B"))
    return str(r)


def test_first_and_second_pass(raw, tmp_path):
    """default results (2026-10-14/15): a folder per recording (names without a number: <experiment>/<name>/),
    <name>.xlsx with the tables as sheets, the large tables as .csv.gz, trend images, a PDF report per experiment"""
    res = str(tmp_path / "results")
    X, report = W.watch(raw, res, quiet=True, bin_minutes=5)
    assert list(X["file"]) == ["A/example9_ratVentricle.mdd", "B/example7_pigVentricle.mdd"]
    assert (X["status"] == "ok").all() and (X["implementation"] == "Python").all()
    assert (X["version"] == W.mda_version()).all() and (X["code"] == W.code_fingerprint()).all()
    assert "A/example9_ratVentricle.mdd" in report and os.listdir(os.path.join(res, "reports"))
    assert not [x for x in os.listdir(os.path.join(res, "reports")) if x.endswith(".pdf")]  # no report per pass
    n9, n7 = "example9_ratVentricle", "example7_pigVentricle"
    eA, eB = os.path.join(res, "A"), os.path.join(res, "B")
    A, B = os.path.join(eA, n9), os.path.join(eB, n7)
    assert sorted(os.listdir(eA)) == ["A_report.pdf", "A_slices.csv", n9]  # no numbered series: no overview image
    assert os.path.getsize(os.path.join(eA, "A_report.pdf")) > 1000
    assert f"PDF report: {os.path.join(eA, 'A_report.pdf')}" in report and os.path.isfile(os.path.join(eB, "B_report.pdf"))
    assert sorted(os.listdir(A)) == [n9 + ".xlsx", n9 + "_ch1.png", n9 + "_contractions.csv.gz",
                                     n9 + "_overview.csv.gz", n9 + "_pulses.csv.gz"]
    sheets = ["summary", "trends", "trendComments", "channels", "gaps", "events", "parameters", "info", "thresholds",
              "labels"]
    assert pd.ExcelFile(os.path.join(A, n9 + ".xlsx")).sheet_names == sheets
    assert os.path.getsize(os.path.join(A, n9 + "_ch1.png")) > 20000
    assert X.loc[0, "outputs"] == (f"{n9}.xlsx; {n9}_contractions.csv.gz; {n9}_pulses.csv.gz; {n9}_overview.csv.gz; "
                                   f"{n9}_ch*.png (1)")
    assert W.results_of(res, "A/" + n9 + ".mdd") == (A, "series")
    S = W.result_table(A, n9, "summary")
    assert len(S) == 3 and list(S["range"]) == ["2000-01-01 15:48:46", "2000-01-01 15:53:46", "2000-01-01 15:58:46"]
    assert S["nContractions"].sum() == X.loc[0, "nContractions"]
    assert {"bin", "nComments", "comments"} <= set(S.columns)
    # B: stimulation protocols only (no summary; channels, gaps, events) and the protocol analysis
    assert X.loc[1, "nContractions"] == 0 and "no time outside the stimulation protocols" in X.loc[1, "message"]
    assert pd.ExcelFile(os.path.join(B, n7 + ".xlsx")).sheet_names == ["channels", "gaps", "events"]
    assert "protocolResults" in pd.ExcelFile(os.path.join(B, n7 + "_protocols.xlsx")).sheet_names
    assert os.path.isfile(os.path.join(B, n7 + "_protocols_contractions.csv.gz"))
    assert W.result_table(B, n7, "summary") is None and not [x for x in os.listdir(B) if x.endswith(".png")]
    assert not os.path.isfile(os.path.join(res, W.LOCK_NAME))
    # overview (1-min medians), contractions, results opened again, slice register
    Ov = pd.read_csv(os.path.join(A, n9 + "_overview.csv.gz"))
    C = pd.read_csv(os.path.join(A, n9 + "_contractions.csv.gz"))
    assert len(Ov) == 12 and Ov["nBeats"].sum() == len(C) == 333 and list(Ov["t_from"][:2]) == [0, 60]
    assert Ov["window"][0] == "2000-01-01 15:48:46"
    assert abs(Ov["amplitude"][0] - 748.916666666667) < 1e-6  # 755.87 with diastolicLevel minimum
    # data of the trend image (sheet trends): one row per window with included contractions, overview values
    Tt = pd.read_excel(os.path.join(A, n9 + ".xlsx"), sheet_name="trends")
    assert list(Tt.columns) == ["channel", "window", "t_from", "nBeats", "amplitude", "diastolicForce", "TTP90",
                                "TTR90", "bin_from"]
    inc = Ov[Ov["included"] == 1]
    assert len(Tt) == inc["t_from"].nunique() and Tt["nBeats"].sum() == inc["nBeats"].sum()
    one = inc.groupby("t_from").filter(lambda g: len(g) == 1).set_index("t_from")
    m = Tt.set_index("t_from").loc[one.index]
    np.testing.assert_allclose(m["amplitude"], one["amplitude"], rtol=1e-12)
    assert Tt["window"][0] == Ov["window"][0] and set(Tt["bin_from"]) <= {0, 300, 600}
    Rr = mda.read_results(os.path.join(A, n9 + ".xlsx"))
    assert Rr["createdBy"] == "MyoDishAnalysisWatch" and len(Rr["contractions"]) == 333 and len(Rr["windows"]) >= 1
    R = pd.read_csv(os.path.join(res, "mda_slices.csv"), keep_default_na=False)
    a = R[R["experiment"] == "A"].iloc[0]
    assert len(R) == 9 and a["endStatus"] == "beating at end of data" and a["nBeats"] == 333 and a["species"] == "rat"
    assert (R.loc[R["experiment"] == "B", "endStatus"] == "protocols only").all() and "slice register: 9 slices" in report
    assert os.path.isfile(os.path.join(eA, "A_slices.csv")) and os.path.isfile(os.path.join(eB, "B_slices.csv"))
    F = W.read_flags(res)
    assert (F["file"] == "A/" + n9 + ".mdd").sum() == 1 and len(W.flags_of(res, "A/" + n9 + ".mdd")) == 1
    X2, report2 = W.watch(raw, res, quiet=True, bin_minutes=5)
    assert report2 == "" and list(X2["analyzed"]) == list(X["analyzed"])


def test_result_formats_and_trends_again(raw, tmp_path):
    """resultFormat csv <-> xlsx and folders flat <-> series: the files of the other format / layout are removed;
    slice register of mixed folders; trend images again from the results (other parameters, command line)
    (2026-10-14/15)"""
    res = str(tmp_path / "results")
    eA, n9 = os.path.join(res, "A"), "example9_ratVentricle"
    A = os.path.join(eA, n9)
    _wcsv(raw, res, quiet=True, protocols=False, trends=True)  # csv files in A/ (flat)
    assert os.path.isfile(os.path.join(eA, n9 + "_summary.csv")) and not os.path.isfile(os.path.join(eA, n9 + ".xlsx"))
    assert os.path.isfile(os.path.join(eA, n9 + "_trends.csv"))
    assert os.path.isfile(os.path.join(eA, n9 + "_trendComments.csv"))
    assert os.path.isfile(os.path.join(eA, "trends", n9 + "_ch1.png"))
    W.watch(raw, res, quiet=True, protocols=False, reanalyze="all", include="A")  # A: .xlsx in A/<name>/, B: flat csv
    files = [n9 + ".xlsx", n9 + "_ch1.png", n9 + "_contractions.csv.gz", n9 + "_overview.csv.gz", n9 + "_pulses.csv.gz"]
    assert sorted(os.listdir(A)) == files
    assert not [x for x in os.listdir(eA) if x.startswith(n9 + "_") or x == n9 + ".xlsx"]  # flat files removed
    assert not os.path.isdir(os.path.join(eA, "trends"))
    assert os.path.isfile(os.path.join(res, "B", "example7_pigVentricle_channels.csv"))
    R = W.slice_register(res)
    assert len(R) == 9 and R.loc[R["experiment"] == "A", "nBeats"].iloc[0] == 333
    files, rep = W.trends_again(res, include="A", trend_parameters=["amplitude", "beatsPerMinute"], quiet=True)
    assert files == [os.path.join(A, n9 + "_ch1.png")] and rep.startswith("1 trend image(s) of 1")
    Tt = pd.read_excel(os.path.join(A, n9 + ".xlsx"), sheet_name="trends")  # sheet replaced: the new parameters
    assert list(Tt.columns)[4:] == ["amplitude", "beatsPerMinute", "bin_from"] and len(Tt) > 5
    with pytest.raises(ValueError):
        W.trends_again(res, trend_parameters=["noSuchParameter"])
    os.remove(os.path.join(A, n9 + "_ch1.png"))
    assert watch_main([res, "--trends-only", "--quiet", "--include", "A"]) == 0
    assert os.path.isfile(os.path.join(A, n9 + "_ch1.png"))
    _wcsv(raw, res, quiet=True, protocols=False, reanalyze="all", include="A")  # back to csv in A/: A/<name>/ removed
    assert os.path.isfile(os.path.join(eA, n9 + "_channels.csv")) and not os.path.isfile(os.path.join(eA, n9 + ".xlsx"))
    assert not os.path.isdir(A) and not os.path.isdir(os.path.join(eA, "trends"))


def test_one_bin_equals_direct_analysis(raw, tmp_path):
    res = str(tmp_path / "results")
    _wcsv(raw, res, quiet=True, bin_minutes=60, protocols=False)
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
    _wcsv(raw, res, quiet=True, protocols=False)
    base = W.options_text({}, dict(protocols=False))
    X, report = _wcsv(raw, res, quiet=True, protocols=False, rocker="stopped")
    assert (X["options"] == base).all()  # default 'new': results of other options kept, notice (2026-10-12)
    assert "2 recording(s) were analysed with other options" in report and "--reanalyze outdated" in report
    X, report = _wcsv(raw, res, quiet=True, protocols=False, rocker="stopped", reanalyze="outdated")
    assert (X["options"] == base + "; rocker=stopped").all() and report and "NOTE" not in report
    log = os.path.join(raw, "A", "example9_ratVentricle_log.log")
    with open(log, "ab") as fh:
        fh.write(b"\x00")
    _age([log], 3600)
    X3, report = _wcsv(raw, res, quiet=True, protocols=False, rocker="stopped")
    assert "A/example9_ratVentricle.mdd" in report and "B/example7_pigVentricle.mdd" not in report
    assert X3.loc[0, "logBytes"] == X.loc[0, "logBytes"] + 1
    X4, report = _wcsv(raw, res, quiet=True, protocols=False, rocker="stopped", reanalyze="all", max_files=1)
    assert X4.loc[0, "analyzed"] >= X3.loc[0, "analyzed"] and X4.loc[1, "analyzed"] == X3.loc[1, "analyzed"]


def test_outdated_code_or_version(raw, tmp_path):
    res = str(tmp_path / "results")
    _wcsv(raw, res, quiet=True, protocols=False)
    X = W.read_index(res)
    X.loc[0, "code"] = "00000000"  # core code changed (same implementation)
    X.loc[1, "version"] = "0.9"
    X.to_csv(os.path.join(res, W.INDEX_NAME), index=False)
    X1, report = _wcsv(raw, res, quiet=True, protocols=False)  # default 'new': kept, notice
    assert report.startswith("MyoDishAnalysis has been updated") and "(0.9: 1, " in report
    assert "with other core code: 1)" in report and list(X1["version"]) == list(X["version"])
    _, report = _wcsv(raw, res, quiet=True, protocols=False, reanalyze="outdated")
    assert "A/example9" in report and "B/example7" in report and "NOTE" not in report
    X = W.read_index(res)
    X.loc[0, "code"] = "00000000"
    X["implementation"] = "MATLAB"  # code of another implementation: only version and options count
    X.to_csv(os.path.join(res, W.INDEX_NAME), index=False)
    _, report = _wcsv(raw, res, quiet=True, protocols=False)
    assert report == ""


def test_schedule(raw, tmp_path, monkeypatch, capsys):
    """schedule: parsing, next pass, passes until Ctrl+C (2026-10-12)"""
    import datetime as dt
    P = W.parse_schedule
    assert P("daily 10:00") == dict(kind="days", every=1, hour=10, minute=0) == P("every day at 10:00")
    assert P("weekly Sun 05:00") == dict(kind="weekly", days=[6], hour=5, minute=0) == P("Sunday 5:00")
    assert P("Mon,Thu 06:30")["days"] == [0, 3] and P("weekdays 07:00")["days"] == [0, 1, 2, 3, 4]
    assert P("every 120 min") == dict(kind="interval", seconds=7200.0) and P("every 6 h")["seconds"] == 21600
    assert P("every 2 days 10:00") == dict(kind="days", every=2, hour=10, minute=0)
    for bad in ("daily 25:00", "sometimes", "every 0 min", "every 30 s", "T 10:00"):
        with pytest.raises(ValueError):
            P(bad)
    now = dt.datetime(2026, 10, 12, 8, 30)  # Monday
    N = W.next_pass
    assert N(P("daily 10:00"), None, now) == dt.datetime(2026, 10, 12, 10, 0)
    assert N(P("daily 07:00"), None, now) == dt.datetime(2026, 10, 13, 7, 0)
    assert N(P("weekly Sun 05:00"), None, now) == dt.datetime(2026, 10, 18, 5, 0)
    a = N(P("Mon,Thu 06:30"), None, now)
    assert a == dt.datetime(2026, 10, 15, 6, 30) and N(P("Mon,Thu 06:30"), a, a) == dt.datetime(2026, 10, 19, 6, 30)
    e = P("every 120 min")
    assert N(e, None, now) == now and N(e, now, now) == dt.datetime(2026, 10, 12, 10, 30)
    assert N(e, now, now + dt.timedelta(hours=5)) == dt.datetime(2026, 10, 12, 14, 30)  # missed passes skipped
    d2 = P("every 2 days 07:00")
    assert N(d2, dt.datetime(2026, 10, 13, 7), dt.datetime(2026, 10, 13, 7, 5)) == dt.datetime(2026, 10, 15, 7)
    with pytest.raises(ValueError):
        _wcsv(raw, str(tmp_path / "r0"), schedule="every 1 h", interval=2)
    # first pass now, then sleeping until the next one: Ctrl+C stops the watcher
    def stop(_):
        raise KeyboardInterrupt
    monkeypatch.setattr(W.time, "sleep", stop)
    res = str(tmp_path / "results")
    X, report = _wcsv(raw, res, schedule="every 60 min", protocols=False, filter="example9")
    out = capsys.readouterr().out
    assert list(X["file"]) == ["A/example9_ratVentricle.mdd"] and "A/example9" in report
    assert "next pass" in out and "watcher stopped" in out


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
    # 2026-10-13: running while the end of the data (start in the log + file duration, 11 min) is < 30 h ago
    _edit_log(run[:-4] + "_log.log", start_hours_ago=1)
    _age([run[:-4] + "_log.log"], 3600)
    assert mda.read_header(run).recordingStopped is False
    X, report = _wcsv(raw, res, quiet=True)
    st = dict(zip(X["file"], X["status"]))
    assert st == {"nolog/example9_ratVentricle.mdd": "noLog", "running/example9_ratVentricle.mdd": "running"}
    assert report == ""
    t_nolog = X.loc[X["file"] == "nolog/example9_ratVentricle.mdd", "analyzed"].iloc[0]
    time.sleep(1.1)  # a check again would change the time of the row
    X, _ = _wcsv(raw, res, quiet=True, incomplete_after_hours=0.5, min_file_age_minutes=0)
    st = dict(zip(X["file"], X["status"]))
    assert st["running/example9_ratVentricle.mdd"] == "ok" and st["young/example9_ratVentricle.mdd"] == "ok"
    assert st["nolog/example9_ratVentricle.mdd"] == "noLog" and len(X) == 3
    # 2026-10-13: 'noLog' is not checked again in every pass, but analysed when the log file appears
    assert X.loc[X["file"] == "nolog/example9_ratVentricle.mdd", "analyzed"].iloc[0] == t_nolog
    shutil.copy(os.path.join(EX, "example9_ratVentricle_log.log"), os.path.join(raw, "nolog"))
    X, _ = _wcsv(raw, res, quiet=True, min_file_age_minutes=0, protocols=False)
    assert dict(zip(X["file"], X["status"]))["nolog/example9_ratVentricle.mdd"] == "ok"


def test_dry_run_filter_from_date_and_lock(raw, tmp_path, capsys):
    res = str(tmp_path / "results")
    X, _ = _wcsv(raw, res, dry_run=True)
    assert len(X) == 0 and "A/example9_ratVentricle.mdd  (new)" in capsys.readouterr().out
    assert not os.path.isfile(os.path.join(res, W.INDEX_NAME))
    X, _ = _wcsv(raw, res, quiet=True, filter="example7", protocols=False)
    assert list(X["file"]) == ["B/example7_pigVentricle.mdd"]
    X, _ = _wcsv(raw, res, quiet=True, from_date="2099-01-01", protocols=False)
    assert len(X) == 1
    # wildcard patterns (2026-10-13): folder or file name, case ignored unless case_sensitive; exclude
    capsys.readouterr()
    for kw, sel in ((dict(include="b"), ["B/example7"]), (dict(include="b", case_sensitive=True), []),
                    (dict(include="*VENTRICLE*", exclude="B/*"), ["A/example9"]),
                    (dict(include="example?_*", exclude=["*pig*"]), ["A/example9"]),
                    (dict(filter="EXAMPLE9", case_sensitive=True), [])):
        _wcsv(raw, str(tmp_path / "dry"), dry_run=True, **kw)
        out = capsys.readouterr().out
        assert sorted(x for x in ("A/example9", "B/example7") if x + "_" in out) == sel, kw
    m = W.wildcard_match
    rel = "ABC00ab/Setup10_ABC00ab_1_scheduleFile_X.mdd"
    assert m(rel, ["ABC00*"]) and m(rel, ["*schedule*"]) and m(rel, W.patterns("ABC01*; Setup10_*"))
    assert not m(rel, ["*Schedule*"], True) and not m(rel, ["ABC01*"]) and m(rel, ["abc00a*/setup1?_*"])
    lock = os.path.join(res, W.LOCK_NAME)
    with open(lock, "w") as fh:
        fh.write("1\n")
    X, msg = _wcsv(raw, res, quiet=True, protocols=False)
    assert "another watcher" in msg and len(X) == 1
    # heartbeat (2026-10-14): rewritten at most once a minute unless forced; a lock file not refreshed for 1 h is
    # ignored (watcher crashed) and removed at the end of the pass
    W._LOCK_TOUCHED[0] = 0.0
    W._touch_lock(lock)
    _age([lock], 30)
    W._touch_lock(lock)  # last heartbeat < 1 min ago: not rewritten
    assert time.time() - os.path.getmtime(lock) > 20
    W._touch_lock(lock, force=True)
    assert time.time() - os.path.getmtime(lock) < 10
    W._touch_lock(None, force=True)  # dry run: no lock file
    _age([lock], 2 * 3600)
    X, msg = _wcsv(raw, res, quiet=True, protocols=False, report=False)
    assert "another watcher" not in str(msg) and len(X) == 2 and not os.path.isfile(lock)


def test_command_line(raw, tmp_path):
    res = str(tmp_path / "results")
    assert watch_main([raw, res, "--quiet", "--no-protocols", "--bin-minutes", "5", "--set", "rockerFilter=1",
                       "--contractions", "thinned", "--thin-mode", "median", "--thin-factor", "5", "--compress",
                       "--workers", "2", "--result-format", "csv", "--no-trends", "--folders", "flat"]) == 0
    X = W.read_index(res)
    assert (X["status"] == "ok").all()
    assert X.loc[0, "options"] == ("binminutes=5; compress=1; contractions=thinned; events=1; gaps=1; "
                                   "includeprotocols=0; overviewseconds=60; protocolmarginseconds=0; protocols=0; "
                                   "rockerfilter=1; thinfactor=5; thinmode=median")
    assert os.path.isfile(os.path.join(res, "A", "example9_ratVentricle_contractions.csv.gz"))
    O = pd.read_csv(os.path.join(res, "A", "example9_ratVentricle_overview.csv"))
    assert len(O) and {"window", "t_from", "t_to", "nBeats", "beatsPerMinute", "amplitude"} <= set(O.columns)
    assert os.path.isfile(os.path.join(res, "mda_slices.csv"))
    # --filter (advanced options) and --interval (older form of --schedule, not in the help) are still accepted
    res2 = str(tmp_path / "res2")
    assert watch_main([raw, res2, "--quiet", "--no-protocols", "--filter", "example7", "--interval", "0"]) == 0
    assert list(W.read_index(res2)["file"]) == ["B/example7_pigVentricle.mdd"]
    assert os.path.isfile(os.path.join(res2, "B", "example7_pigVentricle", "example7_pigVentricle.xlsx"))  # series


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
    assert W.event_category("comment", "note: MX1.6-1.8 Dexa100nM") == "comment"
    assert W.mda_version() == "1.0.0-beta.5" or "-" not in mda.__version__
    assert len(W.code_fingerprint()) == 8
    for f in ("example1_rabbitVentricle", "example9_ratVentricle"):
        assert mda.read_header(os.path.join(EX, f + ".mdd")).recordingStopped is True


def test_protocols_excluded_or_included(tmp_path):
    raw = str(tmp_path / "raw")
    f = _copy("example2_rabbitVentricle", raw)  # PD 67-327 s, ST 512-658 s
    P = mda.find_protocols(f)
    res = str(tmp_path / "res")
    X, _ = _wcsv(raw, res, quiet=True, bin_minutes=5)
    S = pd.read_csv(os.path.join(res, "example2_rabbitVentricle_summary.csv"))
    C = pd.read_csv(os.path.join(res, "example2_rabbitVentricle_contractions.csv"))
    for a, b in zip(P["from"], P["to"]):
        assert not ((C["t_peak"] > a) & (C["t_peak"] < b)).any()
        assert not ((S["from"] < b) & (S["to"] > a)).any()
    assert len(S["range"].unique()) == 3 and (S["bin"] <= S["range"]).all()
    res2 = str(tmp_path / "res2")
    _wcsv(raw, res2, quiet=True, bin_minutes=5, include_protocols=True)
    C2 = pd.read_csv(os.path.join(res2, "example2_rabbitVentricle_contractions.csv"))
    inside = np.zeros(len(C2), bool)
    for a, b in zip(P["from"], P["to"]):
        inside |= (C2["t_peak"] >= a).to_numpy() & (C2["t_peak"] <= b).to_numpy()
    assert inside.any() and len(C2) > len(C)
    res3 = str(tmp_path / "res3")
    _wcsv(raw, res3, quiet=True, bin_minutes=5, protocol_margin_seconds=30)
    S3 = pd.read_csv(os.path.join(res3, "example2_rabbitVentricle_summary.csv"))
    assert S3["from"].min() == 0 and (S3["from"] > 0).any() and abs(sorted(S3["from"].unique())[1] - (P["to"][0] + 30)) < 1e-6


def test_thinned_contractions(tmp_path):
    raw = str(tmp_path / "raw")
    _copy("example4_humanAtrium", raw)  # extra beats in channels 6-8
    _copy("example9_ratVentricle", raw)
    resA, resN, resM = (str(tmp_path / x) for x in ("all", "nth", "median"))
    _wcsv(raw, resA, quiet=True, bin_minutes=5)
    _wcsv(raw, resN, quiet=True, bin_minutes=5, contractions="thinned", thin_factor=10)
    _wcsv(raw, resM, quiet=True, bin_minutes=5, contractions="thinned", thin_mode="median", thin_factor=10)
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
    _wcsv(raw, res, quiet=True, protocols=False)
    f = os.path.join(res, "A", "example9_ratVentricle_contractions.csv")
    assert os.path.isfile(f)
    _wcsv(raw, res, quiet=True, protocols=False, compress=True, reanalyze="outdated")
    assert os.path.isfile(f + ".gz") and not os.path.isfile(f)
    assert len(pd.read_csv(f + ".gz")) == W.read_index(res).loc[0, "nContractions"]
    _wcsv(raw, res, quiet=True, protocols=False, contractions="none", reanalyze="outdated")
    assert not os.path.isfile(f + ".gz") and not os.path.isfile(f)
    assert os.path.isfile(os.path.join(res, "A", "example9_ratVentricle_summary.csv"))


def test_compress_protocol_outputs(raw, tmp_path):
    """compress=True: protocol contractions and pulses as .csv.gz (gzip level 6) as well (2026-10-11)"""
    res = str(tmp_path / "results")
    _wcsv(raw, res, quiet=True, filter="example7")
    base = os.path.join(res, "B", "example7_pigVentricle_protocols_")
    assert os.path.isfile(base + "contractions.csv") and os.path.isfile(base + "pulses.csv")
    n = len(pd.read_csv(base + "contractions.csv"))
    _wcsv(raw, res, quiet=True, filter="example7", compress=True, reanalyze="outdated")
    for k in ("contractions", "pulses"):
        f = base + k + ".csv"
        assert os.path.isfile(f + ".gz") and not os.path.isfile(f)
        with open(f + ".gz", "rb") as fh:
            assert fh.read(9)[8] == 0  # gzip header XFL: 2 = level 9, 4 = level 1, 0 = other levels (6)
    assert n > 0 and len(pd.read_csv(base + "contractions.csv.gz")) == n


def test_events_and_comments(tmp_path):
    raw = str(tmp_path / "raw")
    _copy("example4_humanAtrium", raw)  # comments 'addition of 100nM Iso' in channels 3, 4, 6, 8
    res = str(tmp_path / "res")
    _wcsv(raw, res, quiet=True, bin_minutes=5)
    E = pd.read_csv(os.path.join(res, "example4_humanAtrium_events.csv"))
    assert {"clockTime", "t_file", "channel", "code", "category", "text"} <= set(E.columns)
    assert (E.loc[E["text"] == "addition of 100nM Iso", "category"] == "comment").all()
    S = pd.read_csv(os.path.join(res, "example4_humanAtrium_summary.csv"))
    first = S[S["range"] == S["range"].iloc[0]].set_index("channel")
    assert first.loc[3, "comments"] == "addition of 100nM Iso" and first.loc[1, "nComments"] == 0


def test_parallel_workers(raw, tmp_path):
    X1, _ = _wcsv(raw, str(tmp_path / "r1"), quiet=True, protocols=False)
    X2, _ = _wcsv(raw, str(tmp_path / "r2"), quiet=True, protocols=False, workers=2)
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


def _named_copy(dest, name, seconds=None, age_s=3600):
    """example9 (400 Hz, 2 channels, 666.68 s) as <dest>/<name>.mdd with log file, truncated to seconds"""
    os.makedirs(dest, exist_ok=True)
    f = os.path.join(dest, name + ".mdd")
    with open(os.path.join(EX, "example9_ratVentricle.mdd"), "rb") as fh:
        b = fh.read()
    with open(f, "wb") as fh:
        fh.write(b if seconds is None else b[:int(round(seconds * 400)) * 4])
    shutil.copy(os.path.join(EX, "example9_ratVentricle_log.log"), f[:-4] + "_log.log")
    _age([f, f[:-4] + "_log.log"], age_s)
    return f


def test_incomplete_copies(tmp_path):
    """file shorter than the recording in the log file (> max(10 s, 1 %)), robocopy file time 1980; analysed after
    incomplete_after_hours without change; complete copy analysed again (TS 2026-10-13)"""
    raw, res = str(tmp_path / "raw"), str(tmp_path / "results")
    _named_copy(os.path.join(raw, "I"), "half", 333)
    _named_copy(os.path.join(raw, "T"), "short5s", 666.68 - 5)
    r = _named_copy(os.path.join(raw, "R"), "robo")
    os.utime(r, (315532800, 315532800))  # 1980-01-01
    _named_copy(os.path.join(raw, "E"), "empty", 0)  # empty file (0 bytes) with log file
    e = _named_copy(os.path.join(raw, "L"), "emptylog")  # empty log file
    open(e[:-4] + "_log.log", "w").close()
    _age([e[:-4] + "_log.log"], 3600)
    X, report = _wcsv(raw, res, quiet=True, protocols=False, register=False, min_file_age_minutes=0)
    st, msg = dict(zip(X["file"], X["status"])), dict(zip(X["file"], X["message"]))
    assert st == {"E/empty.mdd": "incomplete", "I/half.mdd": "incomplete", "L/emptylog.mdd": "noLog",
                  "R/robo.mdd": "incomplete", "T/short5s.mdd": "ok"}
    assert msg["I/half.mdd"].startswith("file 333 s, recording in the log file 667 s (50.1 % missing)")
    assert "before 1990" in msg["R/robo.mdd"] and msg["E/empty.mdd"].startswith("empty file (0 bytes)")
    assert "empty" in msg["L/emptylog.mdd"]
    X, _ = _wcsv(raw, res, quiet=True, protocols=False, register=False, min_file_age_minutes=0,
                 incomplete_after_hours=0.5)
    st, msg = dict(zip(X["file"], X["status"])), dict(zip(X["file"], X["message"]))
    assert st["I/half.mdd"] == "ok" and "analysed after 0.5 h without change" in msg["I/half.mdd"]
    assert st["R/robo.mdd"] == "incomplete"  # until the copy is finished (file time of the source)
    assert st["E/empty.mdd"] == "incomplete" and st["L/emptylog.mdd"] == "noLog"  # no time limit
    _named_copy(os.path.join(raw, "I"), "half", age_s=60)  # copy completed
    X, _ = _wcsv(raw, res, quiet=True, protocols=False, register=False, min_file_age_minutes=0)
    st, msg = dict(zip(X["file"], X["status"])), dict(zip(X["file"], X["message"]))
    assert st["I/half.mdd"] == "ok" and "incomplete" not in str(msg["I/half.mdd"])
    # unit: completeness of a recording without 'Recording stopped' from the clock time of the data end
    from types import SimpleNamespace
    from myodish_analysis._matlab import datetime_to_datenum
    import datetime as dt
    now = time.time()
    t = dict(f=r, lastChange=now, mtime=now)
    H = SimpleNamespace(recordingStopped=False, totalSeconds=3600.0,
                        recordingStart=datetime_to_datenum(dt.datetime.now() - dt.timedelta(hours=32)))
    assert W.completeness(t, H, dict(W.WATCH_DEFAULTS), now) == ("", "")  # data end 31 h ago
    H.recordingStart += 2 / 24.0  # data end 29 h ago
    assert W.completeness(t, H, dict(W.WATCH_DEFAULTS), now)[0] == "running"
    H.recordingStart = float("nan")  # no clock time: last change of the files
    assert W.completeness(t, H, dict(W.WATCH_DEFAULTS), now)[0] == "running"
    t["lastChange"] = now - 31 * 3600
    assert W.completeness(t, H, dict(W.WATCH_DEFAULTS), now) == ("", "")
    H.recordingStart = datetime_to_datenum(dt.datetime.now() + dt.timedelta(hours=3))  # clock of the recording PC ahead
    assert W.completeness(t, H, dict(W.WATCH_DEFAULTS), now) == ("", "")  # last change 31 h ago
    t["lastChange"] = now
    assert W.completeness(t, H, dict(W.WATCH_DEFAULTS), now)[0] == "running"
    H.totalSeconds = 0.5  # no data
    assert W.completeness(t, H, dict(W.WATCH_DEFAULTS), now)[0] == "incomplete"


def _parallel_raw(tmp_path):
    """raw folder: P/S1_X_1.mdd (main recording, 666.68 s) with its parallel recording P/S1_X_1_scheduleFile.mdd
    (100-400 s of the main file), Q/S1_X_1_scheduleFile.mdd without main file. Returns raw, main file, parallel file"""
    raw = str(tmp_path / "raw")
    par = "C:\\data\\S1_X_1_scheduleFile.mdd"
    m = _named_copy(os.path.join(raw, "P"), "S1_X_1")
    _edit_log(m[:-4] + "_log.log", recording=[(0, "started: S1_X_1.mdd"),
                                              (100000, "started parallel recording: " + par),
                                              (400000, "stopped parallel recording: " + par),
                                              (666680, "stopped: S1_X_1.mdd")])
    for d in ("P", "Q"):  # Q: without main file
        p = _named_copy(os.path.join(raw, d), "S1_X_1_scheduleFile", 300)
        _edit_log(p[:-4] + "_log.log", recording=[(5, "started parallel recording: " + par),
                                                  (300005, "stopped parallel recording: " + par)])
    logs = (("P", "S1_X_1_log.log"), ("P", "S1_X_1_scheduleFile_log.log"), ("Q", "S1_X_1_scheduleFile_log.log"))
    _age([os.path.join(raw, d, n) for d, n in logs], 3600)
    return raw, m, os.path.join(raw, "P", "S1_X_1_scheduleFile.mdd")


def test_parallel_recordings(tmp_path):
    """parallel recording (schedule file) with its main file: status 'parallel' (default), parallel='analyse',
    without main file analysed, slice register without it, include of the parallel file only (main file not selected:
    analysed and marked), flags table (TS 2026-10-13/14)"""
    raw, m, _ = _parallel_raw(tmp_path)
    p = os.path.join(raw, "Q", "S1_X_1_scheduleFile.mdd")
    D = W.log_recordings(m[:-4] + "_log.log", m)
    assert D["seconds"] == 666.68 and D["stopped"] is True and not D["parallel"]
    assert D["started"] == {"s1_x_1_schedulefile.mdd": [(100.0, 400.0)]}
    D = W.log_recordings(p[:-4] + "_log.log", p)
    assert D["parallel"] and D["seconds"] == 300.0 and D["started"] == {}
    res = str(tmp_path / "results")
    X, report = _wcsv(raw, res, quiet=True, protocols=False)
    st, msg = dict(zip(X["file"], X["status"])), dict(zip(X["file"], X["message"]))
    assert st == {"P/S1_X_1.mdd": "ok", "P/S1_X_1_scheduleFile.mdd": "parallel", "Q/S1_X_1_scheduleFile.mdd": "ok"}
    assert msg["P/S1_X_1_scheduleFile.mdd"].startswith("parallel recording of P/S1_X_1.mdd (100.0-400.0 s of the main")
    assert not os.path.isfile(os.path.join(res, "P", "S1_X_1_scheduleFile_summary.csv"))
    X, report = _wcsv(raw, res, quiet=True, protocols=False)
    assert report == ""  # nothing to do
    X, _ = _wcsv(raw, res, quiet=True, protocols=False, parallel="analyse")
    st, msg = dict(zip(X["file"], X["status"])), dict(zip(X["file"], X["message"]))
    assert st["P/S1_X_1_scheduleFile.mdd"] == "ok" and msg["P/S1_X_1_scheduleFile.mdd"].startswith(
        "parallel recording of P/S1_X_1.mdd (100.0-400.0 s of the main file): analysed (parallel='analyse')")
    assert W.parallel_of(msg["P/S1_X_1_scheduleFile.mdd"]) == "P/S1_X_1.mdd"

    def register(r):
        R = pd.read_csv(os.path.join(r, "mda_slices.csv"))
        return " ".join(str(x) for x in R[R["experiment"] == "P"].to_numpy().ravel())
    # 2026-10-14: analysed parallel recordings are not counted in the slice register while the main file has results
    assert "S1_X_1_scheduleFile" not in register(res) and "S1_X_1" in register(res)
    X, _ = _wcsv(raw, res, quiet=True, protocols=False, reanalyze="all")  # parallel again: results ignored
    assert dict(zip(X["file"], X["status"]))["P/S1_X_1_scheduleFile.mdd"] == "parallel"
    assert "S1_X_1_scheduleFile" not in register(res)
    # only the schedule files (main file not selected, 2026-10-14): analysed and marked; counted in the register
    # until the main file has results in the same folder
    r2 = str(tmp_path / "r2")
    X, report = _wcsv(raw, r2, quiet=True, protocols=False, include="*schedule*")
    st, msg = dict(zip(X["file"], X["status"])), dict(zip(X["file"], X["message"]))
    assert st == {"P/S1_X_1_scheduleFile.mdd": "ok", "Q/S1_X_1_scheduleFile.mdd": "ok"}
    assert msg["P/S1_X_1_scheduleFile.mdd"].startswith(
        "parallel recording of P/S1_X_1.mdd (100.0-400.0 s of the main file): analysed (main file not selected)")
    assert "not analysed although" not in report and "S1_X_1_scheduleFile" in register(r2)
    X, _ = _wcsv(raw, r2, quiet=True, protocols=False)  # all: main file analysed, schedule file kept, not counted
    assert dict(zip(X["file"], X["status"]))["P/S1_X_1.mdd"] == "ok"
    assert "S1_X_1_scheduleFile" not in register(r2) and "S1_X_1" in register(r2)
    # status 'parallel' and the main file not selected: analysed
    X, _ = _wcsv(raw, res, quiet=True, protocols=False, include="*schedule*")
    assert dict(zip(X["file"], X["status"]))["P/S1_X_1_scheduleFile.mdd"] == "ok"
    # flags table of the report (mda_flags.csv, 2026-10-14): written by the watcher, computed again = same flags
    X, T, missing = W.flags_table(res)
    assert set(T["file"]) == {"P/S1_X_1.mdd", "P/S1_X_1_scheduleFile.mdd", "Q/S1_X_1_scheduleFile.mdd"}
    assert missing == [] and list(T.columns) == W.FLAG_COLUMNS and (T["channel"] == 1).any()
    os.remove(os.path.join(res, W.FLAGS_NAME))
    X, T2, missing = W.flags_table(res)
    assert len(T2) == 0 and len(missing) == 3
    X, T2, missing = W.flags_table(res, compute=True)
    assert missing == [] and os.path.isfile(os.path.join(res, W.FLAGS_NAME))
    a = T.sort_values(["file", "channel"]).reset_index(drop=True)[["file", "analyzed", "channel", "flags", "level"]]
    b = T2.sort_values(["file", "channel"]).reset_index(drop=True)[["file", "analyzed", "channel", "flags", "level"]]
    pd.testing.assert_frame_equal(a, b, check_dtype=False)
    with pytest.raises(ValueError):
        _wcsv(raw, str(tmp_path / "r3"), parallel="sometimes")
    assert watch_main([raw, str(tmp_path / "r4"), "--dry-run", "--quiet", "--parallel", "analyze",
                       "--incomplete-tolerance", "3"]) == 0
    # main file whose log lists a parallel recording of the same name but another duration: not the main file
    D = W.log_recordings(p[:-4] + "_log.log", p)
    D["seconds"] = 200.0
    assert W.main_recording(os.path.join(raw, "P", "S1_X_1_scheduleFile.mdd"), D, {}) is None
    D["seconds"] = 302.0
    assert W.main_recording(os.path.join(raw, "P", "S1_X_1_scheduleFile.mdd"), D, {})[1:] == (100.0, 400.0)


def test_log_recordings_2020():
    """software 2020: main recordings logged as 'parallel recording' of the file itself, dataLogTime restarted
    (appended to the same file); the shorter of sum and span counts"""
    import tempfile
    d = tempfile.mkdtemp()
    f = os.path.join(d, "rigA_X_0.mdd")
    p = "C:\\data\\rigA_X_0.mdd"
    with open(f[:-4] + "_log.log", "w", encoding="utf-8") as fh:
        fh.write("systemTime;dataLogTime;channel;code;value\n"
                 f"2000 01 01 12:00:00:000;0;0;Recording;started parallel recording: {p}\n"
                 f"2000 01 02 10:16:27:036;80187036;0;Recording;stopped parallel recording: {p}\n"
                 f"2000 01 02 10:16:27:046;10;0;Recording;started parallel recording: {p}\n"
                 f"2000 01 02 14:38:29:608;15722572;0;Recording;stopped parallel recording: {p}\n")
    D = W.log_recordings(f[:-4] + "_log.log", f)
    assert D["parallel"] and D["stopped"] is True and abs(D["seconds"] - 15722.572) < 1e-6 and D["started"] == {}
    assert W.main_recording(f, D, {}) is None  # no other recording lists it: analysed


def test_gui_results_browser_parallel(tmp_path):
    """results browser of the GUI (rows of the index and the flags table, parallel recordings, open a row, compute
    missing flags) and the button Main file of a parallel recording (TS 2026-10-14)"""
    pytest.importorskip("PySide6")
    pytest.importorskip("pyqtgraph")
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6 import QtCore, QtWidgets
    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
    from myodish_analysis.gui.main_window import MainWindow
    raw, m, par = _parallel_raw(tmp_path)
    res = str(tmp_path / "results")
    W.watch(raw, res, quiet=True, protocols=False)
    assert W.parallel_main(par) == (m, 100.0, 400.0) and W.parallel_main(m) is None
    ws = []
    try:
        w = MainWindow()
        ws.append(w)
        B = w.on_browse(os.path.join(res, "P"), remember=False)  # subfolder chosen: the results folder
        assert B.res == res and B.missing == []
        D = B.D
        assert set(D["file"]) == {"P/S1_X_1.mdd", "P/S1_X_1_scheduleFile.mdd", "Q/S1_X_1_scheduleFile.mdd"}
        r = D[D["file"] == "P/S1_X_1_scheduleFile.mdd"].iloc[0]
        assert r["indexStatus"] == "parallel" and r["main"] == "P/S1_X_1.mdd" and (r["a"], r["b"]) == (100, 400)
        assert D.loc[D["file"] == "P/S1_X_1.mdd", "channel"].tolist() == [1]  # one data channel
        B.dd.setCurrentIndex(3)  # not analysed: the parallel recording, opened in its main file at its time
        assert B.model.rowCount() == 1 and B.model.rows[0][0] == "P/S1_X_1_scheduleFile.mdd"
        assert B.open_row(0)
        assert w.H.file == m and (w.S.fromSeconds, w.S.toSeconds) == (100, 220) and w.ch == 1
        B.dd.setCurrentIndex(0)
        B.ef.setText("q/")
        B.filter()
        assert B.model.rowCount() == 1 and B.model.rows[0][:2] == ("Q/S1_X_1_scheduleFile.mdd", "1")
        assert B.open_row(0)  # the schedule file without main file: first 120 s of its analysis
        assert w.H.file.endswith(os.path.join("Q", "S1_X_1_scheduleFile.mdd")) and w.ch == 1
        assert (w.S.fromSeconds, w.S.toSeconds) == (0, 120) and "the same as here" in w.lStatus.text()
        # flags missing (results of an older watcher): '?', computed and written again
        os.remove(os.path.join(res, W.FLAGS_NAME))
        B.load()
        assert len(B.missing) == 2 and set(B.D["flags"]) == {"?", ""}
        B.compute()
        assert B.missing == [] and os.path.isfile(os.path.join(res, W.FLAGS_NAME)) and "?" not in set(B.D["flags"])
        # a parallel recording opened directly: button Main file opens the main file at the same time
        w2 = MainWindow(par)
        ws.append(w2)
        assert w2.main_rec == (m, 100.0, 400.0) and w2.bMain.isVisibleTo(w2)
        assert "parallel recording of S1_X_1.mdd (100.0-400.0 s of the main file)" in w2.lStatus.text()
        assert (w2.S.fromSeconds, w2.S.toSeconds) == (0, 120)
        w2.on_main_file()
        assert w2.H.file == m and (w2.S.fromSeconds, w2.S.toSeconds) == (100, 220) and w2.ch == 1
        assert not w2.bMain.isVisibleTo(w2)
    finally:
        for x in ws:
            x.close()
            x.deleteLater()
        app.processEvents()
        QtCore.QCoreApplication.sendPostedEvents(None, QtCore.QEvent.Type.DeferredDelete)


def _series_raw(tmp_path):
    """raw folder E with two recordings of a series (copies of example 9): rigX_sampleA_0 (recorded 30 h ago) and
    rigX_sampleA_1 (6 h ago)"""
    E = tmp_path / "raw" / "E"
    E.mkdir(parents=True)
    for k, hours in ((0, 30), (1, 6)):
        n = f"rigX_sampleA_{k}"
        files = []
        for ext in (".mdd", "_labels.csv", "_log.log"):
            shutil.copy(os.path.join(EX, "example9_ratVentricle" + ext), str(E / (n + ext)))
            files.append(str(E / (n + ext)))
        _edit_log(str(E / (n + "_log.log")), start_hours_ago=hours)
        _age(files, 3600)
    return str(tmp_path / "raw")


def test_series_folders_flags_and_reorganize(tmp_path, monkeypatch):
    """folders 'series' (default, 2026-10-15): numbered recordings of a setup in <experiment>/<series>/<nn>/, course
    image per channel and workbook in <experiment>/<series>/, overview image and PDF report per experiment with all
    its recordings (red flags of earlier passes stay visible); timepoints on these results; reorganize into the flat
    layout and back (timepoints/ kept)"""
    import pypdf
    import myodish_analysis.report as rp
    raw = _series_raw(tmp_path)
    res = str(tmp_path / "res")
    X, report = W.watch(raw, res, quiet=True, protocols=False)
    assert list(X["status"]) == ["ok", "ok"]
    e, s = os.path.join(res, "E"), os.path.join(res, "E", "rigX_sampleA")
    n0, n1 = "rigX_sampleA_0", "rigX_sampleA_1"
    assert sorted(os.listdir(e)) == ["E_overview.png", "E_report.pdf", "E_slices.csv", "rigX_sampleA"]
    assert sorted(os.listdir(s)) == ["00", "01", "rigX_sampleA_ch1.png", "rigX_sampleA_trends.xlsx"]
    assert sorted(os.listdir(os.path.join(s, "01"))) == [n1 + ".xlsx", n1 + "_ch1.png", n1 + "_contractions.csv.gz",
                                                         n1 + "_overview.csv.gz", n1 + "_pulses.csv.gz"]
    assert W.results_of(res, "E/" + n1 + ".mdd") == (os.path.join(s, "01"), "series")
    assert f"PDF report: {os.path.join(e, 'E_report.pdf')}" in report
    x = pd.ExcelFile(os.path.join(s, "rigX_sampleA_trends.xlsx"))
    assert x.sheet_names == ["course", "last24h", "comments", "slices"]
    Tc, Tl = x.parse("course"), x.parse("last24h")  # one slice (recordings of a series follow each other)
    assert set(Tc["slice"]) == {1} and (Tc["binMinutes"] == 10).all() and len(x.parse("slices")) == 1
    assert (Tc["bin"].str[14:16].astype(int) % 10 == 0).all() and Tc["bin"].str[17:].eq("00").all()  # bins of the clock
    Ov1 = pd.read_csv(os.path.join(s, "01", n1 + "_overview.csv.gz"))
    assert len(Tl) == Ov1.loc[Ov1["included"] == 1, "t_from"].nunique()  # last 24 h: recording 1 only
    # a red flag of an earlier pass (recording 0) stays in the report and the images when recording 1 is analysed again
    F = W.read_flags(res)
    assert set(F["file"]) == {"E/" + n0 + ".mdd", "E/" + n1 + ".mdd"}
    F.loc[F["file"] == "E/" + n0 + ".mdd", ["level", "red", "flags"]] = ["check", "test flag of yesterday", "N"]
    F.to_csv(os.path.join(res, W.FLAGS_NAME), index=False)
    seen = {}
    for fn in ("course_image", "experiment_image"):
        orig = getattr(rp, fn)
        monkeypatch.setattr(rp, fn, lambda out, D, _o=orig, _f=fn: (seen.__setitem__(_f, D), _o(out, D))[1])
    X2, report2 = W.watch(raw, res, quiet=True, protocols=False, reanalyze="all", include="*_1.mdd")
    assert n1 + ".mdd" in report2 and n0 + ".mdd" not in report2
    assert seen["experiment_image"]["cells"][0]["nRed"] == 1 and len(seen["course_image"]["red"]) == 1
    txt = " ".join(p.extract_text() for p in pypdf.PdfReader(os.path.join(e, "E_report.pdf")).pages)
    assert "test flag of yesterday" in txt and "2 recording(s) (1 new = bold)" in txt
    # timepoints (2026-10-15) on these results: means of the contractions of the windows, no recording between the
    # recordings, pending after the data; the watcher keeps <experiment>/timepoints/ (reorganize below)
    from myodish_analysis.timepoints import timepoints
    C1 = pd.read_csv(os.path.join(s, "01", n1 + "_contractions.csv.gz"))
    tc = pd.to_datetime(C1["clockTime"])
    t0 = tc.min().floor("min") + pd.Timedelta(minutes=5)
    TP = timepoints(res, "Tst", "rigX_sampleA", [], t0, [-600, -2, 2, 300], 60)
    S = TP["summary"]
    assert list(TP["rows"]["channel"]) == [1] and S["note"].iloc[0] == "no recording"
    assert S["note"].iloc[3] == "pending: no data yet"
    for k in (1, 2):
        a = t0 + pd.Timedelta(minutes=float(S["offset_min"].iloc[k]))
        m = (tc >= a) & (tc < a + pd.Timedelta(seconds=60)) & (C1["channel"] == 1) & (C1["included"] == 1)
        assert S["nIncluded"].iloc[k] == m.sum() and S["amplitude"].iloc[k] == pytest.approx(
            C1.loc[m, "amplitude"].mean(), rel=1e-9)
        assert S["amplitude_median"].iloc[k] == pytest.approx(C1.loc[m, "amplitude"].median(), rel=1e-9)
        assert S["dFdtMax"].iloc[k] == pytest.approx(C1.loc[m, "dFdtMax"].mean() / 1000, rel=1e-9)  # mN/s
    for k in (1, 2):  # average beats from the recording, filtered as in the analysis: amplitude as the contractions
        assert S["nAvgBeats"].iloc[k] > 0 and abs(S["avgBeat_amplitude"].iloc[k] / S["amplitude"].iloc[k] - 1) < 0.05
    b = TP["averageBeats"][(TP["averageBeats"]["offset_min"] == -2) & (TP["averageBeats"]["trace"] == "all")]
    assert abs(b["norm_baselineAmplitude"].max() - 1) < 1e-9
    assert abs(b.loc[b["t_s"] < 0, "norm_ownAmplitude"].mean()) < 1e-9 and (b["force_SE_uN"] > 0).all()
    b2 = TP["averageBeats"][(TP["averageBeats"]["offset_min"] == 2) & (TP["averageBeats"]["trace"] == "all")]
    np.testing.assert_allclose(b2["norm_ownAmplitude_SE"], b2["force_SE_uN"] / (b2["force_uN"].max() - b2.loc[
        b2["t_s"] < 0, "force_uN"].mean()), rtol=1e-9)  # own amplitude = 1: SE in the same scale
    # channel 2 without contractions (recorded, no gap): amplitude, dF/dt, beats 0, times NaN, diastole from the signal
    S2 = timepoints(res, "Tst2", "rigX_sampleA", [2], t0, [-2, 2], 60, average_beats=False, write=False)["summary"]
    assert (S2[["amplitude", "dFdtMax", "dFdtMin", "AUC", "beatsPerMinute"]] == 0).all().all()
    assert S2[["TTP90", "TTR90", "CD50", "CD90"]].isna().all().all() and np.isfinite(S2["diastolicForce"]).all()
    assert (S2["note"] == "no contractions; diastolic force from the signal").all()
    d2 = S2["diastolicForce"].to_numpy(float)
    assert S2["diastolicForce_delta"].iloc[1] == pytest.approx(d2[1] - d2[0])
    tpd = TP["folder"]
    files_tp = sorted(os.listdir(tpd))
    assert tpd.startswith(os.path.join(os.path.realpath(e), "timepoints", "Tst_")) and len(files_tp) == 18
    assert sorted(os.listdir(os.path.join(tpd, "averageBeats"))) == ["rigX_sampleA_ch1.png", "rigX_sampleA_ch1.svg"]
    # reorganize: flat layout (images in E/trends/) and back
    n, rep = W.reorganize(res, folders="flat", quiet=True)
    assert n == 2 and rep.startswith("results of 2 recording(s) moved to the layout 'flat'")
    assert sorted(os.listdir(e)) == sorted(["E_overview.png", "E_report.pdf", "E_slices.csv", "timepoints", "trends"] + [
        f"{m}{x}" for m in (n0, n1) for x in (".xlsx", "_contractions.csv.gz", "_overview.csv.gz", "_pulses.csv.gz")])
    assert sorted(os.listdir(os.path.join(e, "trends"))) == [n0 + "_ch1.png", n1 + "_ch1.png", "rigX_sampleA_ch1.png",
                                                             "rigX_sampleA_trends.xlsx"]
    assert W.results_of(res, "E/" + n1 + ".mdd") == (e, "flat")
    assert watch_main([res, "--reorganize", "--quiet"]) == 0
    assert sorted(os.listdir(e)) == ["E_overview.png", "E_report.pdf", "E_slices.csv", "rigX_sampleA", "timepoints"]
    assert sorted(os.listdir(tpd)) == files_tp  # the watcher keeps timepoints/
    assert sorted(os.listdir(os.path.join(s, "00"))) == [n0 + ".xlsx", n0 + "_ch1.png", n0 + "_contractions.csv.gz",
                                                         n0 + "_overview.csv.gz", n0 + "_pulses.csv.gz"]
    assert len(W.slice_register(res)) == 1


def test_empty_folder_of_another_worker_kept(tmp_path, monkeypatch):
    """several workers on a fresh results folder (2026-10-18): a recording without results in the other layout does
    not remove the (still empty) experiment folder that another worker has just created; the results folder of a
    recording is created again if a parent folder disappears meanwhile"""
    res = str(tmp_path / "res")
    e = os.path.join(res, "E")
    os.makedirs(e)  # created by another worker, its series folder not yet
    assert W._delete_results(e, "rigX_sampleA_1", False) == 0
    open(os.path.join(e, "rigX_sampleA_1.xlsx"), "w").close()
    os.makedirs(os.path.join(e, "trends"))
    open(os.path.join(e, "trends", "rigX_sampleA_1_ch3.png"), "w").close()
    assert W._delete_results(e, "rigX_sampleA_1", False) == 2 and os.listdir(e) == []  # empty trends/ removed
    calls = []
    real = os.makedirs

    def flaky(d, exist_ok=False):
        calls.append(d)
        if len(calls) == 1:
            raise FileNotFoundError(d)
        return real(d, exist_ok=exist_ok)
    monkeypatch.setattr(W.os, "makedirs", flaky)
    d = os.path.join(e, "rigX_sampleA", "01")
    W._makedirs(d)
    assert calls[0] == d and calls.count(d) == 2 and os.path.isdir(d)  # second try (os.makedirs also for parents)
