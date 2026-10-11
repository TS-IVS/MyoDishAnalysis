# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Slice register (slice_register) with synthetic watcher results: experiment expA, series rigA_sampleX (4 recordings,
channels 1-8) and rigB_sampleY (1 recording). Pendant of mda_testSliceRegister.m (same results and checks).

    ch1  medium changes (2 x 5 min)                               1 slice, beating at end of data
    ch2  taken out on day 2 (comment 'discarded'), then empty      1 slice, removed, last amplitude 50 of 200
    ch3  taken out on day 1, one recording empty, new slice day 3  2 slices (after a recording without signal)
    ch4  5 min out with the comment 'new slice'                    2 slices (comment)
    ch5  4 h out                                                   2 slices (after 4.0 h without signal)
    ch6  no slice                                                  no row
    ch7  label sliceID S7a --> S7b                                 2 slices (other sliceID)
    ch8  no contractions after day 2                               1 slice, not beating at end of data
    rigB ch1 with label cultureStart                               days since cultureStart
    rigB ch2 3 h out with the comment 'slice moved back'            1 slice (put back), nPutBack 1

TS 2026-10-08
"""
import math
import os

import numpy as np
import pandas as pd

from myodish_analysis.slice_register import slice_register

DAY = 86400.0
H = 3600.0
# recordings of rigA_sampleX: start (s after 2000-01-01 00:00), length (s)
REC = [("rigA_sampleX_0", 16 * H, 14 * H), ("rigA_sampleX_1", DAY + 6 * H, DAY),
       ("rigA_sampleX_2", 2 * DAY + 6 * H, DAY), ("rigA_sampleX_3", 3 * DAY + 6 * H, DAY)]


def clock(t):
    return (pd.Timestamp("2000-01-01") + pd.Timedelta(seconds=t)).strftime("%Y-%m-%d %H:%M:%S")


def scenario():
    """per recording: channels rows, gaps rows, overview rows (file times)"""
    out = {}
    for name, start, L in REC + [("rigB_sampleY_0", 16 * H, 14 * H)]:
        out[name] = dict(start=start, L=L, ch={}, gaps=[], ov=[])
    def chan(n, c, status="beating", sliceID="", cultureStart="", endComments="", lastAmp=math.nan):
        out[n]["ch"][c] = dict(status=status, sliceID=sliceID, cultureStart=cultureStart, endComments=endComments,
                               lastAmplitude=lastAmp)
    def gap(n, c, a, b, comments=""):
        L = out[n]["L"]
        out[n]["gaps"].append(dict(channel=c, start=a, end=b, fromStart=a == 0, untilEnd=b == L, comments=comments))
    for n, _, _ in REC:
        for c in range(1, 9):
            chan(n, c, sliceID=("S7a" if n[-1] in "01" else "S7b") if c == 7 else "")
        chan(n, 6, status="no slice")
        gap(n, 6, 0, out[n]["L"])
    gap("rigA_sampleX_1", 1, 4 * H, 4 * H + 300)
    gap("rigA_sampleX_2", 1, 4 * H, 4 * H + 300)
    gap("rigA_sampleX_2", 2, 6 * H, DAY, "discarded")
    chan("rigA_sampleX_2", 2, status="removed", endComments="discarded")
    chan("rigA_sampleX_3", 2, status="no slice")
    gap("rigA_sampleX_3", 2, 0, DAY)
    gap("rigA_sampleX_1", 3, 6 * H, DAY)
    chan("rigA_sampleX_1", 3, status="removed")
    chan("rigA_sampleX_2", 3, status="no slice")
    gap("rigA_sampleX_2", 3, 0, DAY)
    gap("rigA_sampleX_3", 3, 0, 2 * H)
    gap("rigA_sampleX_2", 4, 4 * H, 4 * H + 300, "new slice")
    gap("rigA_sampleX_1", 5, 3 * H, 7 * H)
    chan("rigA_sampleX_2", 8, status="not beating")
    chan("rigA_sampleX_3", 8, status="not beating")
    chan("rigB_sampleY_0", 1, cultureStart="1999-12-31 12:00")
    chan("rigB_sampleY_0", 2)
    gap("rigB_sampleY_0", 2, 2 * H, 5 * H, "slice moved back")
    # overview: one 60-s window every 20 min of signal, 60 beats; amplitude 100 (ch2: 200, last window before the
    # removal 50)
    for n, d in out.items():
        for c, row in d["ch"].items():
            if row["status"] == "no slice":
                continue
            outs = sorted((g["start"], g["end"]) for g in d["gaps"] if g["channel"] == c)
            segs, t = [], 0.0
            for a, b in outs:
                if a > t:
                    segs.append((t, a))
                t = max(t, b)
            if t < d["L"]:
                segs.append((t, d["L"]))
            for a, b in segs:
                for w in np.arange(a, b, 1200.0):
                    if c == 8 and n in ("rigA_sampleX_2", "rigA_sampleX_3"):
                        continue
                    amp = 200.0 if c == 2 else 100.0
                    if c == 2 and n == "rigA_sampleX_2" and w + 1200 >= b:
                        amp = 50.0
                    d["ov"].append(dict(channel=c, t_from=w, t_to=min(w + 60, b), beatType="stimulated",
                                        included=1, nBeats=60.0, amplitude=amp))
    return out


def write(res, out):
    folder = os.path.join(res, "expA")
    os.makedirs(folder, exist_ok=True)
    for n, d in out.items():
        rows = []
        for c, r in d["ch"].items():
            rows.append(dict(recording=n, recordingStart=clock(d["start"]), fileLength_s=d["L"], channel=c,
                             status=r["status"], nTechnical=0.0, lastContraction_s=math.nan,
                             lastAmplitude=r["lastAmplitude"], maxAmplitude=math.nan, nContractions=0.0,
                             idDate="2000-01-01", setupID="", sliceID=r["sliceID"], species="", sampleID="",
                             cultureStart=r["cultureStart"], endComments=r["endComments"]))
        pd.DataFrame(rows).to_csv(os.path.join(folder, n + "_channels.csv"), index=False)
        G = pd.DataFrame([dict(channel=g["channel"], **{"from": g["start"], "to": g["end"]}, type="chamber out",
                               fromStart=int(g["fromStart"]), untilEnd=int(g["untilEnd"]), comments=g["comments"])
                          for g in d["gaps"]], columns=["channel", "from", "to", "type", "fromStart", "untilEnd",
                                                         "comments"])
        G.loc[G["fromStart"].eq(1) & G["untilEnd"].eq(1), "type"] = "no signal"
        G.to_csv(os.path.join(folder, n + "_gaps.csv"), index=False)
        pd.DataFrame(d["ov"]).to_csv(os.path.join(folder, n + "_overview.csv"), index=False)


def test_slice_register(tmp_path):
    res = str(tmp_path)
    write(res, scenario())
    R = slice_register(res)
    A = pd.read_csv(os.path.join(res, "mda_slices.csv"), keep_default_na=False)
    E = pd.read_csv(os.path.join(res, "expA", "expA_slices.csv"), keep_default_na=False)
    assert len(R) == 13 and len(A) == 13 and len(E) == 13

    def get(series, c):
        return R[(R["series"] == series) & (R["channel"] == c)].reset_index(drop=True)

    r = get("rigA_sampleX", 1)
    assert len(r) == 1 and r["endStatus"][0] == "beating at end of data" and r["beatingAtEnd"][0] == 1
    assert r["nChamberOut"][0] == 2 and abs(r["outHours"][0] - 600 / H) < 1e-9 and r["nRecordings"][0] == 4
    assert r["startTime"][0] == "2000-01-01 16:00:00" and r["endTime"][0] == "2000-01-05 06:00:00"
    assert abs(r["dayStart"][0] - 16 / 24) < 1e-9 and abs(r["dayEnd"][0] - 4.25) < 1e-9
    assert r["daySource"][0] == "idDate"
    r = get("rigA_sampleX", 2)
    assert len(r) == 1 and r["endStatus"][0] == "removed" and r["endTime"][0] == "2000-01-03 12:00:00"
    assert r["lastAmplitude"][0] == 50 and r["maxAmplitude"][0] == 200 and abs(r["lastAmplitude_pctMax"][0] - 25) < 1e-9
    assert "discarded" in r["endComments"][0]
    r = get("rigA_sampleX", 3)
    assert len(r) == 2 and r["endStatus"][0] == "removed" and r["endTime"][0] == "2000-01-02 12:00:00"
    assert r["startReason"][1] == "after a recording without signal" and r["startTime"][1] == "2000-01-04 08:00:00"
    assert r["insertedLater"][1] == 1 and math.isnan(r["dayStart"][1])
    assert r["daySource"][1] == "unknown (inserted later)"
    r = get("rigA_sampleX", 4)
    assert len(r) == 2 and r["startReason"][1].startswith("comment:") and "new slice" in r["startReason"][1]
    assert r["endStatus"][0] == "removed" and r["startTime"][1] == "2000-01-03 10:05:00"
    r = get("rigA_sampleX", 5)
    assert len(r) == 2 and r["startReason"][1] == "after 4.0 h without signal"
    assert len(get("rigA_sampleX", 6)) == 0
    r = get("rigA_sampleX", 7)
    assert len(r) == 2 and r["endStatus"][0] == "replaced (other sliceID)" and r["startReason"][1] == "other sliceID"
    assert r["sliceID"][1] == "S7b" and r["startTime"][1] == "2000-01-03 06:00:00"
    r = get("rigA_sampleX", 8)
    assert len(r) == 1 and r["endStatus"][0] == "not beating at end of data" and r["beatingAtEnd"][0] == 0
    assert r["lastBeat"][0] == "2000-01-03 05:41:00"
    r = get("rigB_sampleY", 2)
    assert len(r) == 1 and r["nPutBack"][0] == 1 and r["nChamberOut"][0] == 1 and abs(r["outHours"][0] - 3) < 1e-9
    assert r["endStatus"][0] == "beating at end of data"
    r = get("rigB_sampleY", 1)
    assert len(r) == 1 and r["daySource"][0] == "cultureStart" and abs(r["dayStart"][0] - 28 / 24) < 1e-9
    assert list(A["slice"].astype(int)) == list(R["slice"].astype(int))
