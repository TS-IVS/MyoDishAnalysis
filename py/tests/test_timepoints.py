# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Test of timepoints (mda_timepoints.m) with synthetic results of the watcher (csv files, folders of the series):
experiment expT, series rigT_S, recordings 0 (day 1) and 1 (day 2) and a parallel recording of recording 0 (not used),
treatment 2000-01-01 12:00:00, windows of 120 s at -60, 10, 120, 1440 and 2880 min.

  ch1  amplitude 100 before, 150 after the treatment (diastolic force 10 / 30 uN); one extra beat (amplitude 40) in the
       baseline window; another slice on day 2
  ch2  amplitude 200; chamber out 12:09:30-12:11:00 and a comment at 12:11:00 (window +10 min: 30 of ~60 contractions)
  ch3  amplitude 300; alternans 300 / 150 from 13:30 (window +120 min); no contractions on day 2
  protocol P1 13:59:00-14:03:00 (window +120 min), no data on day 3 (window +2880 min: pending)
  all channels: dFdtMax 5000 uN/s (timepoints: 5 mN/s); diastolic force of ch2 and ch3 50 uN
Pendant of mda_testTimepoints.m (same files and checks). TS 2026-10-15 (means, SD, SEM, dF/dt in mN/s, diastolic
force as change in uN, no contractions, images absolute and normalized 2026-10-16)"""
import math
import os

import numpy as np
import pandas as pd
import pytest

from myodish_analysis.timepoints import pool_timepoints, timepoints

T0 = pd.Timestamp("2000-01-01 12:00:00")
OFF = [-60, 10, 120, 1440, 2880]


def _clock(t):
    return t.strftime("%Y-%m-%d %H:%M:%S.") + f"{t.microsecond // 1000:03d}"


def _recording(d, n, start, day, parallel=False):
    os.makedirs(d, exist_ok=True)
    rs = pd.Timestamp(start)
    pd.DataFrame({"key": ["recordingStart", "fileLength_s"],
                  "value": [rs.strftime("%Y-%m-%d %H:%M:%S"), "86400" if not parallel else "3600"]}).to_csv(
        os.path.join(d, n + "_info.csv"), index=False)
    rows, ov = [], []
    base = rs.normalize() + pd.Timedelta(hours=10)
    beats = [base + pd.Timedelta(seconds=1 + 2 * k) for k in range(9000)]  # 10:00:01 .. 14:59:59, 0.5 Hz
    for c in (1, 2, 3):
        for t in beats:
            if parallel and (c != 1 or not (pd.Timestamp("2000-01-01 11:00") <= t < pd.Timestamp("2000-01-01 13:00"))):
                continue
            if c == 2 and day == 1 and pd.Timestamp("2000-01-01 12:09:30") <= t < pd.Timestamp("2000-01-01 12:11:00"):
                continue
            if c == 3 and day == 2:
                continue
            a = {1: 100.0 if (day == 1 and t < T0) else 150.0, 2: 200.0, 3: 300.0}[c]
            if c == 3 and day == 1 and t >= pd.Timestamp("2000-01-01 13:30") and \
                    int(((t - base).total_seconds() - 1) / 2) % 2 == 1:
                a = 150.0  # alternans 300 / 150 from 13:30
            if parallel:
                a = 999.0
            dia = (10.0 if (day == 1 and t < T0) else 30.0) if c == 1 else 50.0
            rows.append((c, _clock(t), "stimulated", 1, 0.5, 0.5, a, 0.1 if a == 100 else 0.12, dia, 5000.0))
        if c == 1 and day == 1 and not parallel:
            rows.append((1, _clock(pd.Timestamp("2000-01-01 11:00:30.5")), "extra", 1, math.nan, math.nan, 40.0, 0.1,
                         10.0, 5000.0))
        if c == 2 and day == 1 and not parallel:  # 4 extra beats in the window +120 min: arrhythmic (2026-10-18)
            for s_ in (10.5, 30.5, 50.5, 70.5):
                rows.append((2, _clock(pd.Timestamp("2000-01-01 14:00:00") + pd.Timedelta(seconds=s_)), "extra", 1,
                             math.nan, math.nan, 80.0, 0.1, 50.0, 5000.0))
    C = pd.DataFrame(rows, columns=["channel", "clockTime", "beatType", "included", "stimFrequency",
                                    "peakToPeakFrequency", "amplitude", "TTP90", "diastolicForce", "dFdtMax"]
                     ).sort_values(["channel", "clockTime"])
    C["t_peak"] = (pd.to_datetime(C["clockTime"]) - rs).dt.total_seconds()
    C["t_stim"] = np.where(C["beatType"] == "extra", np.nan, C["t_peak"] - 0.12)
    C.to_csv(os.path.join(d, n + "_contractions.csv"), index=False)
    for c in (1, 2, 3):
        Cc = C[C["channel"] == c]
        if Cc.empty:
            continue
        w = pd.to_datetime(Cc["clockTime"]).dt.floor("min")
        for m, g in Cc.groupby(w.to_numpy()):
            ov.append((pd.Timestamp(m).strftime("%Y-%m-%d %H:%M:%S"), c, "stimulated", 1, len(g),
                       float(g["amplitude"].median()), float(g["TTP90"].median()),
                       float(g["diastolicForce"].median()), float(g["dFdtMax"].median())))
    pd.DataFrame(ov, columns=["window", "channel", "beatType", "included", "nBeats", "amplitude", "TTP90",
                              "diastolicForce", "dFdtMax"]).to_csv(os.path.join(d, n + "_overview.csv"), index=False)
    if day == 1 and not parallel:
        pd.DataFrame({"channel": [2], "clockFrom": ["2000-01-01 12:09:30"], "clockTo": ["2000-01-01 12:11:00"],
                      "type": ["chamber out"]}).to_csv(os.path.join(d, n + "_gaps.csv"), index=False)
        pd.DataFrame({"clockTime": ["2000-01-01 12:11:00.000"], "channel": [2], "category": ["comment"],
                      "text": ["medium exchange"]}).to_csv(os.path.join(d, n + "_events.csv"), index=False)
        s0 = (pd.Timestamp("2000-01-01 13:59:00") - rs).total_seconds()
        pd.DataFrame({"type": ["PD"], "name": ["P1"], "number": [1], "from": [s0], "to": [s0 + 240]}).to_csv(
            os.path.join(d, n + "_protocols_protocols.csv"), index=False)


def _results(tmp_path):
    res = str(tmp_path / "res")
    s = os.path.join(res, "expT", "rigT_S")
    _recording(os.path.join(s, "00"), "rigT_S_0", "2000-01-01 06:00:00", 1)
    _recording(os.path.join(s, "01"), "rigT_S_1", "2000-01-02 06:00:00", 2)
    _recording(os.path.join(s, "00"), "rigT_S_0_par", "2000-01-01 11:00:00", 1, parallel=True)
    files = ["expT/rigT_S_0.mdd", "expT/rigT_S_1.mdd", "expT/rigT_S_0_par.mdd"]
    pd.DataFrame({"file": files, "bytes": 1, "modified": "", "logBytes": 1, "status": "ok", "version": "x",
                  "implementation": "Python", "code": "", "options": "contractions=all", "analyzed": "",
                  "seconds": 1, "nContractions": 1, "outputs": "", "message": ""}).to_csv(
        os.path.join(res, "mda_index.csv"), index=False)
    pd.DataFrame({"series": ["rigT_S"] * 4, "channel": [1, 1, 2, 3], "slice": [1, 2, 1, 1],
                  "sampleID": ["A1", "A1", "", ""],
                  "startTime": ["2000-01-01 10:00:01", "2000-01-02 08:00:00", "2000-01-01 10:00:01",
                                "2000-01-01 10:00:01"],
                  "endTime": ["2000-01-02 07:00:00", "2000-01-02 14:59:59", "2000-01-02 14:59:59",
                              "2000-01-01 14:59:59"]}).to_csv(os.path.join(res, "expT", "expT_slices.csv"), index=False)
    return res


def test_windows_notes_files(tmp_path):
    res = _results(tmp_path)
    TP = timepoints(os.path.join(res, "expT"), "T1", "rigT_S", [], "2000-01-01 12:00", OFF)
    S = TP["summary"]
    assert list(TP["rows"]["channel"]) == [1, 2, 3] and len(S) == 15 and TP["baseline"] == -60
    # sample ID: slice register (ch1), else the series name after the setup (rigT_S --> S); group ''
    assert list(TP["rows"]["sampleID"]) == ["A1", "S", "S"] and list(S["sampleID"][::5]) == ["A1", "S", "S"]
    assert (TP["rows"]["group"] == "").all()
    g = lambda c, o: S[(S["channel"] == c) & (S["offset_min"] == o)].iloc[0]  # noqa: E731
    r = g(1, -60)
    assert (r["from"], r["to"], r["nBeats"], r["nIncluded"], r["nExtra"]) == ("2000-01-01 11:00:00",
                                                                             "2000-01-01 11:02:00", 61, 60, 1)
    a0 = np.full(60, 100.0)  # baseline ch1: 60 stimulated beats of 100 uN; the extra beat (40 uN) not in the values
    assert r["amplitude"] == pytest.approx(a0.mean()) and r["amplitude_median"] == 100 and \
        r["recording"] == "rigT_S_0" and r["note"] == ""  # parallel recording not used
    assert r["amplitude_SD"] == pytest.approx(a0.std(ddof=1)) and \
        r["amplitude_SEM"] == pytest.approx(a0.std(ddof=1) / math.sqrt(60))
    assert (r["amplitude_q25"], r["amplitude_q75"], r["diastolicForce"], r["dFdtMax"]) == (100, 100, 10, 5)
    r = g(1, 10)
    assert r["amplitude"] == 150 and r["amplitude_pctBaseline"] == pytest.approx(15000 / a0.mean())
    assert r["TTP90_pctBaseline"] == pytest.approx(120) and r["dFdtMax_pctBaseline"] == pytest.approx(100)
    assert r["diastolicForce_delta"] == 20  # absolute change of the diastolic force (uN)
    pars = ["amplitude", "diastolicForce", "TTP90", "TTR90", "CD50", "CD90", "dFdtMax", "dFdtMin", "AUC",
            "beatsPerMinute"]
    nm = ["diastolicForce_delta" if p == "diastolicForce" else p + "_pctBaseline" for p in pars]
    assert TP["parameters"] == pars and TP["units"][6:8] == ["mN/s", "mN/s"] and list(S.columns) == (
        ["series", "channel", "sampleID", "group", "time", "offset_min", "from", "to", "recording", "slice", "nBeats",
         "nIncluded", "nExtra", "note"] + [x for p, q in zip(pars, nm) for x in (p, q)]
        + [p + e for p in pars for e in ("_SD", "_SEM")]
        + [p + e for p in pars for e in ("_median", "_q25", "_q75")] + ["nAvgBeats", "avgBeat_diastolic",
                                                                       "avgBeat_amplitude"])
    r = g(2, 10)
    assert r["nIncluded"] == 30 and r["note"] == ("chamber out 12:09:30-12:11:00; comment 12:11:00 medium exchange; "
                                                  "30 of ~60 expected contractions included")
    assert g(1, 120)["note"] == "protocol P1 13:59:00-14:03:00"
    r = g(2, 120)  # paced: values of the stimulated beats; >= 5 % extra beats: arrhythmic
    assert r["note"] == "protocol P1 13:59:00-14:03:00; arrhythmic: 4 extra beats (6 % of the contractions)"
    assert (r["nBeats"], r["nIncluded"], r["nExtra"], r["amplitude"], r["beatsPerMinute"]) == (64, 60, 4, 200, 32)
    r = g(3, 120)
    assert r["note"] == ("protocol P1 13:59:00-14:03:00; alternans: 2 amplitude groups 150 / 300 uN (50 % small beats, "
                         "100 % of successive beats switch)") and r["amplitude"] == 225 and r["amplitude_median"] == 225
    assert TP["averageBeats"].empty and (S["nAvgBeats"] == 0).all() and \
        any("rigT_S_0.mdd not found" in n for n in TP["notes"])  # no recordings: no average beats
    r = g(1, 1440)
    assert r["recording"] == "rigT_S_1" and r["slice"] == 2 and r["amplitude"] == 150 and \
        math.isnan(r["amplitude_pctBaseline"]) and r["note"] == "other slice than in the baseline window"
    r = g(3, 1440)  # no contractions (recorded, no gap): force values 0, times NaN, diastole from the signal (no mdd)
    assert r["note"] == "no contractions" and r["nBeats"] == 0 and r["amplitude"] == 0 and r["dFdtMax"] == 0
    assert r["AUC"] == 0 and r["beatsPerMinute"] == 0 and r["amplitude_pctBaseline"] == 0 and math.isnan(r["TTP90"])
    assert math.isnan(r["diastolicForce"]) and any("diastolic force without contractions: rigT_S_1.mdd not found" in n
                                                  for n in TP["notes"])
    assert all(g(c, 2880)["note"] == "pending: no data yet" for c in (1, 2, 3))
    assert np.isnan(TP["matrix"]["beatsPerMinute"][0, 4]) and TP["matrix"]["beatsPerMinute"][0, 0] == 30.5
    np.testing.assert_allclose(TP["matrix"]["amplitude"][:, 0], [a0.mean(), 200, 300])
    np.testing.assert_allclose(TP["pctBaseline"]["amplitude"][0, :3], [100, 15000 / a0.mean(), 15000 / a0.mean()])
    C = TP["course"]
    c1 = C[C["channel"] == 1]  # day 1 10:30-14:59 and day 2 10:00-14:59 (1-min values of the overview)
    assert c1["minutes"].iloc[0] == -90 and c1["minutes"].iloc[-1] == 1619 and len(c1) == 570
    assert ((c1["minutes"] >= -90) & (c1["minutes"] <= 179)).sum() == 270
    assert c1.loc[c1["minutes"] == -1, "amplitude_pctBaseline"].iloc[0] == 100
    assert c1.loc[c1["minutes"] == 0, "amplitude_pctBaseline"].iloc[0] == 150  # medians of the baseline window
    assert c1.loc[c1["minutes"] == 0, "diastolicForce_delta"].iloc[0] == 20 and (c1["dFdtMax"] == 5).all()
    assert len(TP["beats"]) == int(S["nBeats"].sum()) and TP["units"][0] == "uN"
    d = os.path.join(os.path.realpath(res), "expT", "timepoints", "T1_2000-01-01-12-00")
    assert TP["folder"] == d and sorted(os.listdir(d)) == sorted(
        ["T1_2000-01-01-12-00" + x for x in [".xlsx"] + [f"_{g_}_{m}{e}" for g_ in ("timepoints", "course")
                                                         for m in ("abs", "norm") for e in (".png", ".svg")]])
    x = pd.ExcelFile(os.path.join(d, "T1_2000-01-01-12-00.xlsx"))
    assert x.sheet_names == ["summary", "matrix", "course", "beats", "averageBeats", "averageBeatsMean", "info"]
    M = x.parse("matrix")
    assert list(M.columns[5:]) == ["-60 min", "+10 min", "+120 min", "+1440 min", "+2880 min"]
    v = lambda p, m: M.loc[(M["parameter"] == p) & (M["measure"] == m) & (M["channel"] == 1), "+10 min"].iloc[0]  # noqa
    assert v("amplitude", "mean") == 150 and v("amplitude", "pctBaseline") == pytest.approx(15000 / a0.mean())
    assert v("diastolicForce", "delta") == 20


def test_inputs(tmp_path):
    res = _results(tmp_path)
    # one time per channel; seconds; baseline none; nothing written
    TP = timepoints(res, "T2", "rigT_S", [1, 2], ["2000-01-01 12:00", "2000-01-01 12:01:00"], [-60, 10], 60,
                    baseline=math.nan, write=False, sampleID="X9", group="HTX")
    assert list(TP["rows"]["sampleID"]) == ["X9", "X9"] and (TP["summary"]["group"] == "HTX").all()
    assert TP["folder"] == "" and TP["files"] == [] and np.isnan(TP["pctBaseline"]["amplitude"]).all()
    assert list(TP["summary"]["from"]) == ["2000-01-01 11:00:00", "2000-01-01 12:10:00", "2000-01-01 11:01:00",
                                           "2000-01-01 12:11:00"]
    assert list(TP["summary"]["nBeats"]) == [31, 30, 30, 30]
    # no baseline: only absolute images
    TP = timepoints(res, "T6", "rigT_S", [1], "2000-01-01 12:00", [-60, 10], baseline=math.nan, average_beats=False)
    assert sorted(os.listdir(TP["folder"])) == sorted(["T6_2000-01-01-12-00" + x for x in (
        ".xlsx", "_timepoints_abs.png", "_timepoints_abs.svg", "_course_abs.png", "_course_abs.svg")])
    # matrix of channels (one row per series) with one time per element
    TP = timepoints(res, "T3", ["rigT_S"], [[3, 0, 1]], [["2000-01-01 12:00", None, "01.01.2000 12:00:30"]], [-60],
                    write=False)
    assert list(TP["rows"]["channel"]) == [3, 1] and list(TP["rows"]["time"]) == ["2000-01-01 12:00:00",
                                                                                   "2000-01-01 12:00:30"]
    for bad in (dict(label="a b"), dict(offsets=[]), dict(channels=[1, 1]), dict(series="rigX"),
                dict(time="tomorrow"), dict(offsets=[-60, -60])):
        a = dict(results_folder=res, label="T4", series="rigT_S", channels=[1], time="2000-01-01 12:00",
                 offsets=[-60, 10], write=False)
        a.update(bad)
        with pytest.raises(ValueError):
            timepoints(**a)


def test_command_line(tmp_path, capsys):
    from myodish_analysis.cli import timepoints_main
    res = _results(tmp_path)
    assert timepoints_main([res, "T5", "--series", "rigT_S", "--channels", "1", "--time", "2000-01-01 12:00",
                            "--offsets", "-60", "10", "--no-figures"]) == 0
    out = capsys.readouterr().out
    d = os.path.join(os.path.realpath(res), "expT", "timepoints", "T5_2000-01-01-12-00")
    assert os.listdir(d) == ["T5_2000-01-01-12-00.xlsx"] and "150" in out


def test_pool(tmp_path):
    """pool_timepoints (mda_poolTimepoints.m): three analyses (OME0.5uM: sample H1 ch1 + ch2 and sample H3 ch2 on day
    2; CTRL: sample H2 ch3), pooled by treatment from the results folder and from the dicts"""
    res = _results(tmp_path)
    kw = dict(average_beats=False)
    TPs = [timepoints(res, "OME0.5uM", "rigT_S", [1, 2], "2000-01-01 12:00", [-60, 10], sampleID="H1", group="HTX",
                      **kw),
           timepoints(res, "CTRL", "rigT_S", [3], "2000-01-01 12:00", [-60, 10], sampleID="H2", group="HTX", **kw),
           timepoints(res, "OME0.5uM", "rigT_S", [2], "2000-01-02 12:00", [-60, 10], sampleID="H3", **kw)]
    PT = pool_timepoints(res, name="test", labels=["CTRL", "OME0.5uM"])
    S = PT["slices"]
    assert list(S.columns[:10]) == ["treatment", "substance", "concentration", "concentrationUnit", "group",
                                    "sampleID", "sliceID", "timePoint", "offset_min", "isBaseline"]
    k = list(S.columns).index("analysis")
    assert len(S) == 8 and list(S.columns[k:k + 3]) == ["analysis", "controlReference", "nControlSlices"] and \
        S.columns[-1] == "beatsPerMinute_pctBaseline_vsControl" and "treatmentTime" in S.columns
    o = S[S["treatment"] == "OME0.5uM"]
    assert (o["substance"] == "OME").all() and (o["concentration"] == 0.5).all() and \
        (o["concentrationUnit"] == "uM").all()
    c = S[S["treatment"] == "CTRL"]
    assert (c["substance"] == "CTRL").all() and c["concentration"].isna().all() and (c["sliceID"] == "rigT_S_ch3").all()
    assert sorted(set(o["sliceID"])) == ["rigT_S_ch1", "rigT_S_ch2"] and list(o["timePoint"][:2]) == ["-1 h", "+10 min"]
    assert list(S["isBaseline"][:2]) == [1, 0] and set(o["group"]) == {"HTX", ""}
    a0 = np.full(60, 100.0)  # baseline ch1: stimulated beats only
    T = PT["treatments"]
    assert list(T["treatment"]) == ["CTRL", "CTRL", "OME0.5uM", "OME0.5uM"]  # controls first
    r = T[(T["treatment"] == "OME0.5uM") & (T["offset_min"] == 10)].iloc[0]
    v = np.array([15000 / a0.mean(), 100, 100])
    assert (r["nSlices"], r["nSamples"]) == (3, 2) and r["amplitude_pctBaseline"] == pytest.approx(v.mean())
    assert r["amplitude_pctBaseline_SEM"] == pytest.approx(v.std(ddof=1) / math.sqrt(3))
    assert r["amplitude_pctBaseline_samples"] == pytest.approx(((v[0] + v[1]) / 2 + v[2]) / 2)
    Sm = PT["samples"]
    assert len(Sm) == 6 and list(Sm.loc[(Sm["sampleID"] == "H1"), "nSlices"]) == [2, 2]
    C = PT["course"]
    assert set(C["treatment"]) == {"CTRL", "OME0.5uM"} and \
        C.loc[(C["treatment"] == "OME0.5uM") & (C["minutes"] == -1), "amplitude_pctBaseline"].iloc[0] == 100
    assert list(PT["analyses"]["status"]) == ["pooled"] * 3 and PT["controls"] == ["CTRL"]
    # against the controls: OME (samples H1, H3 without own control) -> all controls (H2 ch3: 100 %, delta 0)
    assert list(o["controlReference"].unique()) == ["all controls"] and (c["controlReference"] == "sample").all()
    r1 = o[(o["sliceID"] == "rigT_S_ch1") & (o["offset_min"] == 10)].iloc[0]
    assert r1["nControlSlices"] == 1 and r1["amplitude_pctBaseline_vsControl"] == pytest.approx(15000 / a0.mean())
    assert r1["diastolicForce_delta_vsControl"] == 20 and (c["amplitude_pctBaseline_vsControl"] == 100).all()
    d = os.path.join(os.path.realpath(res), "timepoints_pooled", "test")
    assert PT["folder"] == d and sorted(os.listdir(d)) == sorted(["CTRL", "OME0.5uM", "test.xlsx",
                                                                 "test_prism.xlsx"] + [
        f"treatments_{m}{e}" for m in ("abs", "norm", "vsControl") for e in (".png", ".svg")] + [
        f"test_figure_norm.{e}" for e in ("pdf", "svg", "png")])
    assert sorted(os.listdir(os.path.join(d, "CTRL"))) == sorted(
        f"CTRL_{g}_{m}{e}" for g in ("timepoints", "course") for m in ("abs", "norm") for e in (".png", ".svg"))
    x = pd.ExcelFile(os.path.join(d, "test.xlsx"))
    assert x.sheet_names == ["slices", "samples", "treatments", "statistics", "qc", "excluded", "course",
                             "averageBeatsMean", "analyses", "info"]
    # the dicts of timepoints: the same values without reading the files
    P2 = pool_timepoints(TPs, write=False)
    k = ["treatment", "sampleID", "sliceID", "offset_min"]
    A_, B_ = S.sort_values(k).reset_index(drop=True), P2["slices"].sort_values(k).reset_index(drop=True)
    for col in ("amplitude", "amplitude_pctBaseline", "diastolicForce_delta", "amplitude_SEM",
                "amplitude_pctBaseline_vsControl", "diastolicForce_delta_vsControl"):
        np.testing.assert_allclose(A_[col].to_numpy(float), B_[col].to_numpy(float), rtol=1e-12, equal_nan=True)
    with pytest.raises(ValueError):
        pool_timepoints(res, labels=["nothing"], write=False)
    from myodish_analysis.cli import pool_timepoints_main
    assert pool_timepoints_main([res, "--labels", "OME0.5uM", "--name", "cli", "--no-figures"]) == 0
    assert sorted(os.listdir(os.path.join(os.path.realpath(res), "timepoints_pooled", "cli"))) == ["cli.xlsx",
                                                                                                   "cli_prism.xlsx"]


def test_pool_exclude_qc_statistics(tmp_path):
    """pool_timepoints (2026-10-18): option exclude (a window from an offset on; a whole slice), column qc and sheet qc
    (codes of the notes), sheet statistics against the controls (descriptive with < 3 samples), course and average
    beats of excluded windows left out"""
    res = _results(tmp_path)
    timepoints(res, "OME0.5uM", "rigT_S", [1, 2], "2000-01-01 12:00", [-60, 10], sampleID="H1", average_beats=False)
    timepoints(res, "CTRL", "rigT_S", [3], "2000-01-01 12:00", [-60, 10], sampleID="H2", average_beats=False)
    PT = pool_timepoints(res, name="ex", exclude=[("H1", 2, 10, "test reason"), ("nothing", None, None, "")],
                         figures=False)
    S, E = PT["slices"], PT["excluded"]
    assert len(S) == 5 and len(E) == 1 and E["excludeReason"].iloc[0] == "test reason"
    assert (E["sliceID"].iloc[0], E["offset_min"].iloc[0]) == ("rigT_S_ch2", 10)
    assert "exclude nothing: no slice found" in PT["notes"]
    i = PT["info"]
    assert i.loc[i["key"] == "exclude", "value"].iloc[0] == "H1 ch2 from 10 min: test reason; nothing"
    C = PT["course"]  # OME: from minute 10 on only ch1
    o = C[C["treatment"] == "OME0.5uM"]
    assert (o.loc[o["minutes"] >= 10, "nSlices"] == 1).all() and (o.loc[o["minutes"] < 10, "nSlices"] == 2).all()
    q = S.set_index(["sliceID", "offset_min"])["qc"]
    assert q[("rigT_S_ch1", -60)] == "" and PT["qc"].empty  # ch2 +10 (chamber out, comment) excluded
    PT2 = pool_timepoints(res, name="ex2", figures=False)
    Q = PT2["qc"]
    assert list(Q["qc"]) == ["capture signal comment"] and Q["sliceID"].iloc[0] == "rigT_S_ch2"
    St = PT2["statistics"]
    r = St[(St["treatment"] == "OME0.5uM") & (St["parameter"] == "amplitude_pctBaseline")].iloc[0]
    assert (r["offset_min"], r["nSlices"], r["nSamples"], r["nControlSlices"], r["nPairedSamples"]) == (10, 2, 1, 1, 0)
    assert r["mean"] == pytest.approx(125) and r["controlMean"] == 100 and r["difference"] == pytest.approx(25)
    assert math.isnan(r["lme_p"]) and r["lme_note"] == "fewer than 3 samples in a group: descriptive only"
    assert len(St) == len(PT2["parameters"])  # one time point after the baseline
    PT3 = pool_timepoints(res, name="ex3", exclude=pd.DataFrame({"id": ["rigT_S_ch1"], "reason": ["whole slice"]}),
                          write=False)
    assert set(PT3["slices"]["sliceID"]) == {"rigT_S_ch2", "rigT_S_ch3"} and len(PT3["excluded"]) == 2
    from myodish_analysis.cli import pool_timepoints_main
    assert pool_timepoints_main([res, "--name", "cli2", "--no-figures", "--exclude", "H1:2:10:test"]) == 0
    x = pd.read_excel(os.path.join(os.path.realpath(res), "timepoints_pooled", "cli2", "cli2.xlsx"), "excluded")
    assert list(x["excludeReason"]) == ["test"]


def test_lme_random_intercept():
    """linear mixed model of the statistics sheet (REML, random intercept per sample) against statsmodels MixedLM
    (estimate 18.2215, SE 3.8915, variance ratio 4.2369 for these data)"""
    from myodish_analysis.timepoints import _lme_ri
    y = [96, 104, 120, 126, 81, 85, 99, 92, 110, 131, 112, 118, 140]
    x = [0, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 1, 1]
    g = ["A", "A", "A", "A", "B", "B", "B", "B", "C", "C", "D", "D", "D"]
    e, se, df, p, th = _lme_ri(y, x, g)
    assert e == pytest.approx(18.2215, rel=1e-4) and se == pytest.approx(3.8915, rel=2e-3)
    assert th == pytest.approx(4.2369, rel=2e-3) and df == 11 and 0.0006 < p < 0.0008
    assert all(math.isnan(v) for v in _lme_ri([1, 2], [0, 1], ["a", "b"]))  # too few values


def test_t0_chamber_in(tmp_path):
    """t0='chamberIn' (2026-10-18): time 0 = end of the chamber-out period of the channel nearest to the given time
    (ch2: chamber out 12:09:30-12:11:00); channels without such a period keep the given time"""
    res = _results(tmp_path)
    TP = timepoints(res, "T7", "rigT_S", [1, 2], "2000-01-01 12:00", [-60, 10], t0="chamberIn", average_beats=False,
                    write=False)
    R = TP["rows"]
    assert list(R["time"]) == ["2000-01-01 12:00:00", "2000-01-01 12:11:00"]
    assert list(R["timeGiven"]) == ["2000-01-01 12:00:00"] * 2 and TP["t0"] == "chamberIn"
    assert R["t0"].iloc[0] == "no chamber-out period within +-90 min: given time 12:00:00"
    assert R["t0"].iloc[1] == "chamber in 12:11:00 (given 12:00:00, +11.0 min; 1 chamber-out period(s) within +-90 min)"
    S = TP["summary"]
    assert S[(S["channel"] == 2) & (S["offset_min"] == 10)]["from"].iloc[0] == "2000-01-01 12:21:00"
    i = TP["info"]
    assert i.loc[i["key"] == "t0", "value"].iloc[0] == (
        "end of the chamber-out period of the channel nearest to the given time (chamber in; periods ending within "
        "+-90 min): rigT_S ch1: no chamber-out period within +-90 min: given time 12:00:00; rigT_S ch2: chamber in "
        "12:11:00 (given 12:00:00, +11.0 min; 1 chamber-out period(s) within +-90 min)")
    TP2 = timepoints(res, "T8", "rigT_S", [2], "2000-01-01 12:00", [10], t0="chamberIn", t0_window=5,
                     average_beats=False, write=False)
    assert TP2["rows"]["time"].iloc[0] == "2000-01-01 12:00:00"  # period ends 11 min later: outside +-5 min
    with pytest.raises(ValueError):
        timepoints(res, "T9", "rigT_S", [2], "2000-01-01 12:00", [10], t0="chamberOut", write=False)


def test_figure_and_prism(tmp_path):
    """plot_timepoints (figure for a manuscript) and prism_tables (2026-10-18): from the dict and from the workbook"""
    from myodish_analysis.timepoints import plot_timepoints, prism_tables
    res = _results(tmp_path)
    timepoints(res, "OME0.5uM", "rigT_S", [1, 2], "2000-01-01 12:00", [-60, 10], sampleID="H1", average_beats=False)
    timepoints(res, "CTRL", "rigT_S", [3], "2000-01-01 12:00", [-60, 10], sampleID="H2", average_beats=False)
    PT = pool_timepoints(res, name="fig", figures=False)
    x = os.path.join(PT["folder"], "fig_prism.xlsx")
    P = prism_tables(PT)
    assert list(P) == ["amplitude_pctBaseline", "diastolicForce_delta", "TTP90_pctBaseline", "TTR90_pctBaseline"]
    A = P["amplitude_pctBaseline"]
    assert list(A.columns) == ["time_h", "CTRL|H2 rigT_S_ch3", "OME0.5uM|H1 rigT_S_ch1", "OME0.5uM|H1 rigT_S_ch2"]
    np.testing.assert_allclose(A["time_h"], [-1, 1 / 6])
    np.testing.assert_allclose(A["OME0.5uM|H1 rigT_S_ch1"], [100, 150])
    B = pd.read_excel(x, sheet_name="amplitude_pctBaseline")
    np.testing.assert_allclose(B.to_numpy(float), A.to_numpy(float))
    out = str(tmp_path / "f1")
    fig, files = plot_timepoints(PT, output=out, parameters=["amplitude", "diastolicForce"], mode="norm")
    assert files == [out + ".pdf", out + ".svg", out + ".png"] and all(os.path.getsize(f) > 1000 for f in files)
    ax = fig.axes[0]
    assert ax.get_ylabel() == "amplitude (% of baseline)" and fig.axes[1].get_ylabel() == "diastolic force, change (uN)"
    labels = [t.get_text() for t in fig.legends[0].get_texts()]
    assert labels == ["CTRL (n = 1/1)", "OME0.5uM (n = 2/1)"]
    fig2, f2 = plot_timepoints(os.path.join(PT["folder"], "fig.xlsx"), mode="abs", slices=False)
    assert f2 == [] and len([a for a in fig2.axes if a.get_visible()]) == 4


def test_study(tmp_path):
    """study (2026-10-18): design table (one row per slice, exclusions) -> timepoints per treatment and pool_timepoints
    in one study folder, with the design, a methods text and the Prism tables; template; t0 = chamberIn"""
    from myodish_analysis.study import study, study_template
    res = _results(tmp_path)
    tpl = study_template(str(tmp_path / "design.xlsx"))
    x = pd.ExcelFile(tpl)
    assert x.sheet_names == ["slices", "settings"] and list(x.parse("slices").columns) == [
        "series", "channel", "treatment", "time", "sampleID", "group", "exclude", "excludeReason"]
    D = pd.DataFrame({"series": ["rigT_S"] * 3, "channel": [1, 2, 3], "treatment": ["OME0.5uM", "OME0.5uM", "CTRL"],
                      "time": ["2000-01-01 12:00"] * 3, "sampleID": ["H1", "H1", "H2"], "group": "",
                      "exclude": ["", "10", ""], "excludeReason": ["", "test reason", ""]})
    f = str(tmp_path / "d.csv")
    D.to_csv(f, index=False)
    R = study(f, resultsFolder=res, offsets="-60 10", name="s1", averageBeats="false", figures="false")
    d = os.path.join(res, "studies", "s1")
    assert R["folder"] == d and sorted(os.listdir(d)) == ["analyses", "design_s1.csv", "s1.xlsx", "s1_methods.txt",
                                                          "s1_prism.xlsx"]
    assert sorted(os.listdir(os.path.join(d, "analyses", "expT"))) == ["CTRL_2000-01-01-12-00",
                                                                      "OME0.5uM_2000-01-01-12-00"]
    PT = R["pool"]
    assert len(PT["slices"]) == 5 and list(PT["excluded"]["excludeReason"]) == ["test reason"]
    assert R["methods"].startswith("Contraction parameters were analysed with MyoDishAnalysis ")
    assert "windows of 120 s starting -1 h, +10 min relative to the treatment (time 0 = the documented time of " \
        "the addition)" in R["methods"]
    assert "Groups: CTRL 1 slice from 1 sample; OME0.5uM 2 slices from 1 sample." in R["methods"]
    assert "Excluded: H1 rigT_S_ch2 (windows from +10 min; test reason)." in R["methods"]
    assert open(os.path.join(d, "s1_methods.txt"), encoding="utf-8").read().strip() == R["methods"]
    R2 = study(D, resultsFolder=res, offsets=[-60, 10], name="s2", t0="chamberIn", averageBeats="false",
               figures="false")
    S = R2["pool"]["slices"]
    assert S.loc[(S["sliceID"] == "rigT_S_ch2") & (S["offset_min"] == -60), "treatmentTime"].iloc[0] == \
        "2000-01-01 12:11:00"
    assert "design_s2.xlsx" in os.listdir(R2["folder"]) and "reinsertion of the chamber" in R2["methods"]
    with pytest.raises(ValueError):
        study(D.drop(columns="time"), resultsFolder=res, offsets="-60 10")
    with pytest.raises(ValueError):
        study(f, offsets="-60 10")  # no results folder
    from myodish_analysis.cli import study_main
    assert study_main(["--template", str(tmp_path / "t2.xlsx")]) == 0 and os.path.isfile(str(tmp_path / "t2.xlsx"))
