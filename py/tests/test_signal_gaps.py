# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Periods without signal (signal_gaps) and the watcher outputs _gaps.csv / _channels.csv with a synthetic recording
(9 channels, 400 Hz, 600 s). Pendant of mda_testSignalGaps.m (same recording and checks).

TS 2026-10-08
"""
import os

import numpy as np
import pandas as pd

from myodish_analysis.signal_gaps import signal_gaps
from myodish_analysis.watch import watch

FS = 400
T = 600


def write_recording(f):
    n = T * FS
    k = np.arange(n)
    x = np.zeros((9, n))
    for c in range(1, 9):
        x[c - 1] = np.round(-10000 + 500 * c + 20 * np.sin(0.7 * k + c) + 13 * np.sin(1.3 * k + 0.5 * c))
    x[0, 39920:39960] += 2000  # spike 99.8-99.9 s
    x[0, 64000:] += 300  # other level after putting the chamber back

    def hold(c, a, b, v):
        x[c - 1, int(round(a * FS)):int(round(b * FS))] = v

    hold(1, 100, 160, -10000)
    hold(1, 200, 210, -10001)
    hold(3, 200.05, 210, -10002)
    for c, a in ((5, 300), (6, 300.1), (7, 300.25), (8, 300.4)):
        hold(c, a, 360, -383)
    hold(4, 0, 50, -9000)
    hold(4, 400, 410, 32767)
    hold(7, 450, 460, -5000)
    hold(1, 450.05, 460, -5001)
    hold(3, 500, 600, -8000)
    hold(6, 520, 540, -7000)
    hold(8, 570, 580, -6000)
    hold(4, 570.4, 585, -6001)
    x[5, 530 * FS] = -6999
    x[1] = -383
    x[8] = 0
    x.T.astype("<i2").tofile(f)
    lines = ["systemTime;dataLogTime;channel;code;value",
             "2000 01 01 10:00:00:000;0;0;samplingRate Recording;400",
             "2000 01 01 10:00:00:000;0;0;Recording;started: gaps_ABC000101.mdd",
             "2000 01 01 10:01:41:000;101000;1;comment;chamber 1 out",
             "2000 01 01 10:08:20:000;500000;3;comment;discarded",
             "2000 01 01 10:10:00:000;600000;0;Recording;stopped: gaps_ABC000101.mdd"]
    with open(f[:-4] + "_log.log", "w") as fh:
        fh.write("\n".join(lines) + "\n")


def test_signal_gaps_and_watcher(tmp_path):
    raw = tmp_path / "raw"
    raw.mkdir()
    f = str(raw / "gaps_ABC000101.mdd")
    write_recording(f)
    G = signal_gaps(f)

    def row(c, a):
        return G[(G["channel"] == c) & (np.abs(G["from"] - a) < 1e-9)]

    r = row(1, 100)
    assert len(r) == 1 and r["type"].iat[0] == "chamber out" and abs(r["to"].iat[0] - 160) < 1e-9
    assert r["value"].iat[0] == -10000 and r["nSimultaneous"].iat[0] == 1
    assert not r["fromStart"].iat[0] and not r["untilEnd"].iat[0]
    assert abs(r["levelChange"].iat[0] - 300) < 5 and r["spikeBefore"].iat[0] > 1900 and abs(r["spikeAfter"].iat[0]) < 100
    assert row(1, 200)["type"].iat[0] == "board group" and row(3, 200.05)["type"].iat[0] == "board group"
    assert row(3, 200.05)["nSimultaneous"].iat[0] == 2 and abs(row(3, 200.05)["spread"].iat[0] - 0.05) < 1e-9
    g4 = G[(G["channel"] >= 5) & (G["from"] >= 299) & (G["from"] <= 301)]
    assert len(g4) == 4 and (g4["type"] == "board group").all() and (g4["nSimultaneous"] == 4).all()
    assert (np.abs(g4["to"] - 360) < 1e-9).all() and (np.abs(g4["spread"] - 0.4) < 1e-9).all()
    r = row(4, 0)
    assert len(r) == 1 and r["fromStart"].iat[0] and abs(r["to"].iat[0] - 50) < 1e-9
    assert r["type"].iat[0] == "chamber out" and np.isnan(r["levelBefore"].iat[0]) and not np.isnan(r["levelAfter"].iat[0])
    assert row(4, 400)["type"].iat[0] == "saturated" and row(4, 400)["valueAU"].iat[0] == 32767
    assert row(7, 450)["type"].iat[0] == "controller" and row(1, 450.05)["type"].iat[0] == "controller"
    # two chambers taken out with both hands 0.4 s apart (2 channels, > simultaneous_pair): not technical
    assert row(8, 570)["type"].iat[0] == "chamber out" and row(4, 570.4)["type"].iat[0] == "chamber out"
    assert row(8, 570)["nSimultaneous"].iat[0] == 1 and row(4, 570.4)["spread"].iat[0] == 0
    r = row(3, 500)
    assert len(r) == 1 and r["untilEnd"].iat[0] and r["type"].iat[0] == "chamber out" and np.isnan(r["levelAfter"].iat[0])
    r = row(6, 520)
    assert len(r) == 1 and abs(r["to"].iat[0] - 540) < 1e-9
    assert not ((G["channel"] == 6) & (G["from"] > 521) & (G["from"] < 541)).any()
    r = G[G["channel"] == 2]
    assert len(r) == 1 and r["type"].iat[0] == "no signal" and r["fromStart"].iat[0] and r["untilEnd"].iat[0]
    assert len(G) == 16

    # watcher: _gaps.csv, _channels.csv, summary columns
    res = str(tmp_path / "res")
    X, report = watch(str(raw), res, quiet=True, min_file_age_minutes=0, protocols=False)
    Gw = pd.read_csv(os.path.join(res, "gaps_ABC000101_gaps.csv"), keep_default_na=False)
    CH = pd.read_csv(os.path.join(res, "gaps_ABC000101_channels.csv"), keep_default_na=False)
    S = pd.read_csv(os.path.join(res, "gaps_ABC000101_summary.csv"))
    assert X["status"].iat[0] == "ok" and len(Gw) == 16
    assert {"clockFrom", "clockTo", "comments"} <= set(Gw.columns) and Gw["comments"].str.contains("chamber 1 out").any()
    st = dict(zip(CH["channel"], CH["status"]))
    n1 = float(CH.loc[CH["channel"] == 1, "nContractions"].iat[0])
    assert st[2] == "no slice" and st[3] == "removed" and (st[1] == "beating") == (n1 > 0)
    assert abs(float(CH.loc[CH["channel"] == 3, "lastSignal_s"].iat[0]) - 500) < 1e-6
    assert CH["idDate"].iat[0] == "2000-01-01" and "discarded" in CH.loc[CH["channel"] == 3, "endComments"].iat[0]
    s1 = S[S["channel"] == 1]
    assert abs(s1["noSignal_s"].sum() - 79.95) < 1e-6 and s1["nChamberOut"].sum() == 1
    assert "signal gaps: 6 chamber out, 6 board group, 2 controller, 1 saturated" in report
    # slice register: one slice per channel with signal; short chamber-out periods and technical periods belong to it
    R = pd.read_csv(os.path.join(res, "mda_slices.csv"), keep_default_na=False)
    assert len(R) == 7 and 2 not in set(R["channel"]) and "slice register: 7 slices in 1 experiment(s)" in report
    r1 = R[R["channel"] == 1].iloc[0]
    assert r1["nChamberOut"] == 1 and abs(r1["outHours"] - 60 / 3600) < 1e-9 and r1["startReason"] == "first signal"
    assert abs(r1["dayStart"] - 10 / 24) < 1e-9 and r1["daySource"] == "idDate"
    r3 = R[R["channel"] == 3].iloc[0]
    assert r3["endStatus"] == "removed" and r3["endTime"] == "2000-01-01 10:08:20" and "discarded" in r3["endComments"]
    r4 = R[R["channel"] == 4].iloc[0]
    assert r4["startTime"] == "2000-01-01 10:00:50" and r4["nChamberOut"] == 1
