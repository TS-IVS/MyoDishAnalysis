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
                                                                             "2000-01-01 11:02:00", 61, 61, 1)
    a0 = np.r_[np.full(60, 100.0), 40.0]  # baseline ch1: 60 beats of 100 uN and the extra beat of 40 uN (included)
    assert r["amplitude"] == pytest.approx(a0.mean()) and r["amplitude_median"] == 100 and \
        r["recording"] == "rigT_S_0" and r["note"] == ""  # parallel recording not used
    assert r["amplitude_SD"] == pytest.approx(a0.std(ddof=1)) and \
        r["amplitude_SEM"] == pytest.approx(a0.std(ddof=1) / math.sqrt(61))
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
    assert all(g(c, 120)["note"] == "protocol P1 13:59:00-14:03:00" for c in (1, 2))
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
    a0 = np.r_[np.full(60, 100.0), 40.0]
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
    assert PT["folder"] == d and sorted(os.listdir(d)) == ["CTRL", "OME0.5uM", "test.xlsx"] + [
        f"treatments_{m}{e}" for m in ("abs", "norm", "vsControl") for e in (".png", ".svg")]
    assert sorted(os.listdir(os.path.join(d, "CTRL"))) == sorted(
        f"CTRL_{g}_{m}{e}" for g in ("timepoints", "course") for m in ("abs", "norm") for e in (".png", ".svg"))
    x = pd.ExcelFile(os.path.join(d, "test.xlsx"))
    assert x.sheet_names == ["slices", "samples", "treatments", "course", "averageBeatsMean", "analyses", "info"]
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
    assert os.listdir(os.path.join(os.path.realpath(res), "timepoints_pooled", "cli")) == ["cli.xlsx"]
