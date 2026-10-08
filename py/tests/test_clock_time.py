"""Clock time of log entries (clock_time): 12-hour time stamps of MyoDish software 2.0.7717-2.0.7769 corrected,
24-hour logs unchanged. Pendant of mda_testClockTime.m (same cases).

TS 2026-10-08
"""
import datetime as dt
import os

import numpy as np
import pytest

from myodish_analysis._matlab import datetime_to_datenum
from myodish_analysis.clock_time import clock_time
from myodish_analysis.log_entries import log_entries
from myodish_analysis.read_mdd import read_mdd

D0 = dt.datetime(2021, 3, 1)
V12 = "Version 2.0.7769.26061"
V24 = "Version 2.0.9756.15922"


def at(hrs):
    """clock times in whole seconds"""
    return [D0 + dt.timedelta(seconds=round(h * 3600)) for h in hrs]


def nums(T, fmt12):
    """numbers of the time stamps as the software writes them ('hh': hours 1-12, 'HH': 0-23)"""
    out = []
    for t in T:
        h = (t.hour - 1) % 12 + 1 if fmt12 else t.hour
        out.append([t.year, t.month, t.day, h, t.minute, t.second, round(t.microsecond / 1000)])
    return out


def run(T, fmt12, ver, file_time=None, text=None, tt=None):
    if tt is None:
        tt = [(t - T[0]).total_seconds() for t in T]
    return clock_time(nums(T, fmt12), tt, ver, file_time, text)


def shifted(T, h):
    return [t + dt.timedelta(hours=h) for t in T]


def test_24h_unchanged():
    T = at([6, 6.5, 11.9, 12.2, 17.1, 23.5, 24.2, 29.9])
    clk, info = run(T, False, V24)
    assert clk == T and info["format"] == "24h" and info["nCorrected"] == 0


@pytest.mark.parametrize("ver", [V12, ""])
def test_12h_corrected(ver):
    T = at([6, 7, 12.25, 17 + 4 / 60, 23.9, 24.5, 29.98])
    clk, info = run(T, True, ver)
    assert clk == T and info["format"] == "12h" and info["nCorrected"] == 3
    if ver:
        assert not info["ambiguous"] and info["source"] == "log"


def test_afternoon_only():
    T = at([13, 13.5, 14, 16, 17])
    clk, info = run(T, True, V12)
    assert clk == shifted(T, -12) and info["ambiguous"] and info["nCorrected"] == 0
    assert "AM/PM of the recording unknown" in info["note"]
    txt = ["x"] * len(T)
    txt[0] = "Started parallel recording: 01.Mrz.2021 13:00:00"
    clk, info = run(T, True, V12, text=txt)
    assert clk == T and not info["ambiguous"] and info["nCorrected"] == 5
    clk, info = run(T, True, V12, file_time=datetime_to_datenum(T[-1] + dt.timedelta(minutes=2)))
    assert clk == T and not info["ambiguous"] and info["source"] == "file time"
    clk, info = run(T, True, V12, file_time=T[-1] - dt.timedelta(hours=12) + dt.timedelta(minutes=1))
    assert clk == shifted(T, -12) and not info["ambiguous"] and info["nCorrected"] == 0


def test_24h_stale_datalogtime_unchanged():
    Told = at([10 + k / 3600 for k in range(5)])
    Tnew = at([18, 18.5, 19, 22, 25, 29])
    T = Told + Tnew
    tt = [4 * 3600.0] * len(Told) + [(t - Tnew[0]).total_seconds() for t in Tnew]
    clk, info = run(T, False, V24, tt=tt)
    assert clk == T and info["format"] == "24h"


def test_12h_stale_and_frozen():
    T = at([13.9, 13.95, 14, 15, 18, 22, 26, 30, 30.5, 31, 36])
    tt = [(t - T[2]).total_seconds() for t in T]
    tt[0] = tt[1] = 5000.0
    tt[-3:] = [tt[-4]] * 3
    clk, info = run(T, True, V12, tt=tt)
    assert clk == T and info["format"] == "12h"


def test_two_versions():
    T1 = at([15, 15.1, 15.2])
    T2 = at([15.5, 16, 20, 26])
    N = nums(T1, False) + nums(T2, True)
    tt = [(t - T1[0]).total_seconds() for t in T1] + [(t - T2[0]).total_seconds() for t in T2]
    clk, info = clock_time(N, tt, ["Version 2.0.7712.19726", V12])
    assert clk == T1 + T2 and info["format"] == "12h"


def test_log_file_and_mdd(tmp_path):
    mdd = tmp_path / "Setup2_test_0.mdd"
    np.zeros((400 * 60, 9), dtype="<i2").tofile(mdd)
    T = at([14 + 1 / 3, 14 + 1 / 3, 15, 20, 25])
    tt = [0.0] + [(t - T[0]).total_seconds() for t in T[1:]]
    txt = ["Recording;started: Setup2_test_0.mdd", "samplingRate Recording;400", "comment;Mx 1600",
           "comment;observation", "Recording;stopped: Setup2_test_0.mdd"]
    Nw = nums(T, True)
    lines = ["systemTime;dataLogTime;channel;code;value",
             "%04d %02d %02d %02d:%02d:%02d:%03d;0;0;programInfo;%s" % (*Nw[0], V12)]
    for k in range(len(T)):
        lines.append("%04d %02d %02d %02d:%02d:%02d:%03d;%d;0;%s" % (*Nw[k], round(tt[k] * 1000), txt[k]))
    lf = tmp_path / "Setup2_test_0_log.log"
    lf.write_text("\n".join(lines) + "\n", encoding="utf-8")
    E = log_entries(str(lf))
    assert [c.to_pydatetime() for c in E.clockTime] == [T[0]] + T
    assert E.attrs["clock"]["nCorrected"] == 5
    H = read_mdd(str(mdd))
    assert abs(H.recordingStart - datetime_to_datenum(T[0])) < 1e-8
    assert any("12-hour time stamps" in n for n in H.notes)
    os.remove(mdd)
