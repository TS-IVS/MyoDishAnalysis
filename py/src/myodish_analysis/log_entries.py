"""All entries of a MyoDish log file (comments, events, settings) as a table, in log order. Port of mda_logEntries.m.

    E = log_entries(log_file)          log_file = <name>_log.log next to the .mdd file

E.clockTime   datetime: system time of the entry (real-world date and time; NaT if not readable)
E.t_file      s: dataLogTime of the entry = time in the .mdd file (as used by all MyoDish analysis scripts)
E.channel     channel number of the entry (0 = not channel-specific)
E.code        e.g. 'comment', 'Event', 'rockerSpeed', 'Calibration'
E.text        value / comment text
E.isComment   True for comments (code 'comment')

Lines (UTF-16 or UTF-8): systemTime;dataLogTime_ms;channel;code;value, e.g.
  2022 03 07 09:44:35:717;1025;0;comment;start rockerSpeedTest

TS 2026-10-06 (port of mda_logEntries.m, TS 2026-10-05)
"""
from __future__ import annotations

import datetime as _dt
import math
import os
import re

import numpy as np
import pandas as pd

_NUM = re.compile(r"^[+-]?((\d+(\.\d*)?)|(\.\d+))([eEdD][+-]?\d+)?$")


def str2double(s):
    """MATLAB str2double of one text: the number, or NaN (commas are thousands separators, Inf/NaN accepted)."""
    if s is None:
        return math.nan
    s = str(s).strip()
    if not s:
        return math.nan
    low = s.lower()
    if low in ("inf", "+inf", "infinity", "+infinity"):
        return math.inf
    if low in ("-inf", "-infinity"):
        return -math.inf
    if low == "nan":
        return math.nan
    s2 = s.replace(",", "")
    if not _NUM.match(s2):
        return math.nan
    return float(s2.replace("d", "e").replace("D", "e"))


_FLOAT_AT = re.compile(r"\s*([+-]?((\d+(\.\d*)?)|(\.\d+))([eE][+-]?\d+)?|[+-]?[Ii]nf|[Nn]a[Nn])")


def sscanf_floats(s):
    """sscanf(s, '%f'): as many numbers as can be read from the start of s."""
    out = []
    pos = 0
    while True:
        m = _FLOAT_AT.match(s, pos)
        if not m:
            break
        out.append(float(m.group(1)))
        pos = m.end()
    return out


def read_log_text(log_file):
    """text of a MyoDish log file (UTF-16 little endian with or without byte order mark, or UTF-8); None if missing."""
    if not log_file or not os.path.isfile(log_file):
        return None
    with open(log_file, "rb") as fh:
        b = fh.read()
    if len(b) >= 4 and ((b[0] == 255 and b[1] == 254) or (b[1] == 0 and b[3] == 0)):
        if b[0] == 255:
            b = b[2:]
        b = b[: 2 * (len(b) // 2)]
        return b.decode("utf-16-le", errors="replace")
    return b.decode("utf-8", errors="replace")


def split_lines(txt):
    return re.split(r"\r?\n", txt)


_LINE = re.compile(r"^([^;]*);([^;]*);([^;]*);([^;]*);(.*)$")
_CLOCK = re.compile(r"^(\d+) (\d+) (\d+) (\d+):(\d+):(\d+):?(\d*)")


def parse_clock(s):
    """'yyyy mm dd HH:MM:SS:fff' --> datetime (None if not readable)."""
    m = _CLOCK.match(s.strip())
    if not m:
        return None
    N = [int(x) for x in m.groups()[:6]]
    ms = int(m.group(7)) if m.group(7) else 0
    try:
        return _dt.datetime(N[0], N[1], N[2], N[3], N[4], N[5]) + _dt.timedelta(milliseconds=ms)
    except ValueError:
        return None


def log_entries(log_file):
    cols = ["clockTime", "t_file", "channel", "code", "text", "isComment"]
    empty = pd.DataFrame({"clockTime": pd.Series([], dtype="datetime64[ns]"), "t_file": pd.Series([], dtype=float),
                          "channel": pd.Series([], dtype=float), "code": pd.Series([], dtype=object),
                          "text": pd.Series([], dtype=object), "isComment": pd.Series([], dtype=bool)})
    txt = read_log_text(log_file)
    if txt is None:
        return empty
    rows = []
    for line in split_lines(txt):
        m = _LINE.match(line)
        if not m:
            continue
        tok = m.groups()
        t = str2double(tok[1])
        if math.isnan(t):
            continue  # header line, broken lines
        ch = str2double(tok[2])
        if math.isnan(ch):
            ch = 0.0
        code = tok[3].strip()
        rows.append((parse_clock(tok[0]), t / 1000.0, ch, code, tok[4].strip(), code.lower() == "comment"))
    if not rows:
        return empty
    E = pd.DataFrame(rows, columns=cols)
    E["clockTime"] = pd.to_datetime(E["clockTime"])
    return E
