# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""End of protocols without end comment (find_protocols, regular_pacing_start) with a synthetic recording (9 channels,
400 Hz, 2400 s; stimuli of channels 1 and 2 in the status channel). Pendant of mda_testProtocolEnd.m.

       0- 300 s  0.5 Hz, 60 mA (regular)
     300 s       'start stimCurrent threshold protocol': current steps 20, 30, 40, 50, 70, 80 mA every 40 s
     540- 1000   0.5 Hz, 60 mA                    --> ST ends at 540 s (regular pacing)
    1000 s       'start post rest potentiation protocol': 3 trains of 10 stimuli (0.5 Hz), 30 s pauses
    1150 s       'start FFR protocol': 1 Hz, 2 Hz (100 s each)   --> PRP ends at 1150 s (next protocol)
    1350- 2400   0.5 Hz, 60 mA                    --> FFR ends at 1350 s (regular pacing)
    1800 s       'start pulse duration protocol': pulse duration (log chargeDuration) 1000, 500, 250, 2000 us
                 every 30 s, interval and current unchanged   --> PD ends at 1890 s (pulse duration unchanged)

TS 2026-10-10
"""
import math

import numpy as np

import myodish_analysis as mda

FS = 400
T = 2400


def stimuli():
    """times (s) and currents (mA) of the stimuli"""
    t, cur = [], []
    steps = [20, 30, 40, 50, 70, 80]
    for x in np.arange(0, 1000, 2.0):  # 0.5 Hz, ST current steps
        t.append(x)
        cur.append(steps[int((x - 300) // 40)] if 300 <= x < 540 else 60)
    for a in (1000, 1050, 1100):  # PRP trains
        for i in range(10):
            t.append(a + 2.0 * i); cur.append(60)
    for x in np.arange(1150, 1250, 1.0):
        t.append(x); cur.append(60)
    for x in np.arange(1250, 1350, 0.5):
        t.append(x); cur.append(60)
    for x in np.arange(1350, T - 1, 2.0):
        t.append(x); cur.append(60)
    return np.array(t), np.array(cur)


def write_recording(f):
    n = T * FS
    x = np.zeros((9, n), dtype="<i2")
    x[:8] = -383
    t, cur = stimuli()
    for c in (1, 2):  # pulse of channel c one sample after the one of channel c-1
        idx = np.round(t * FS).astype(int) + (c - 1)
        x[8, idx] = (cur.astype(int) | (c << 9)).astype("<i2")
    x.T.tofile(f)
    name = f.replace("\\", "/").rsplit("/", 1)[-1]
    rows = [(0, 0, "samplingRate Recording", "400"), (0, 0, "Recording", "started: " + name),
            (0, 0, "chargeDuration", "2000"),
            (300, 0, "comment", "start stimCurrent threshold protocol"),
            (1000, 0, "comment", "start post rest potentiation protocol"),
            (1150, 0, "comment", "start FFR protocol"),
            (1800, 0, "comment", "start pulse duration protocol"),
            (1800, 0, "chargeDuration", "1000"), (1830, 0, "chargeDuration", "500"),
            (1860, 0, "chargeDuration", "250"), (1890, 0, "chargeDuration", "2000"),
            (T, 0, "Recording", "stopped: " + name)]
    lines = ["systemTime;dataLogTime;channel;code;value"]
    for s, ch, code, val in rows:
        hh, mm, ss = 10 + s // 3600, (s % 3600) // 60, s % 60
        lines.append(f"2000 01 01 {hh:02d}:{mm:02d}:{ss:02d}:000;{s * 1000};{ch};{code};{val}")
    with open(f[:-4] + "_log.log", "w") as fh:
        fh.write("\n".join(lines) + "\n")


def test_protocol_end_estimated(tmp_path):
    f = str(tmp_path / "pend_rigA_0.mdd")
    write_recording(f)
    P = mda.find_protocols(f)
    assert P["type"].tolist() == ["ST", "PRP", "FFR", "PD"]
    np.testing.assert_allclose(P["from"], [300, 1000, 1150, 1800])
    np.testing.assert_allclose(P["to"], [540, 1150, 1350, 1890])
    assert P["note"][0] == "no end comment: end estimated at 540 s (start of regular pacing: 0.5 Hz, 60 mA, > 5 min)"
    assert P["note"][1] == ("no end comment: end estimated at 1150 s (start of the next protocol 'FFR protocol')")
    assert P["note"][2] == "no end comment: end estimated at 1350 s (start of regular pacing: 0.5 Hz, 60 mA, > 5 min)"
    assert P["note"][3] == "no end comment: end estimated at 1890 s (start of regular pacing: 0.5 Hz, 60 mA, > 5 min)"
    # log file only (no stimuli): next protocol or end of the file
    L = mda.find_protocols(f[:-4] + "_log.log")
    np.testing.assert_allclose(L["to"][:3], [1000, 1150, 1800])
    assert math.isinf(L["to"][3]) and L["note"][3] == "no end comment: end estimated at Inf s (end of the file)"
    # without the end estimation from the stimuli
    P0 = mda.find_protocols(f, regular_minutes=0)
    np.testing.assert_allclose(P0["to"], [1000, 1150, 1800, T])
    assert P0["note"][3] == f"no end comment: end estimated at {T} s (end of the file)"
