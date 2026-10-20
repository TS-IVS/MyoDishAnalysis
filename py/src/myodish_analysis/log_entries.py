# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""All entries of a MyoDish log file (comments, events, settings) as a table, in log order. Port of mda_logEntries.m.

    E = log_entries(log_file)          log_file = <name>_log.log next to the .mdd file

E.clockTime   datetime: system time of the entry (real-world date and time; NaT if not readable; 12-hour time
              stamps of MyoDish software 2.0.7717-2.0.7769 corrected, see clock_time)
E.t_file      s: dataLogTime of the entry = time in the .mdd file (as used by all MyoDish analysis scripts)
E.channel     channel number of the entry (0 = not channel-specific)
E.code        e.g. 'comment', 'Event', 'rockerSpeed', 'Calibration'
E.text        value / comment text
E.isComment   True for comments (code 'comment')
E.attrs['clock']   info of clock_time (format '24h' / '12h', nCorrected, ambiguous, source, note)

Lines (UTF-16 or UTF-8): systemTime;dataLogTime_ms;channel;code;value, e.g.
  2000 01 01 09:44:35:717;1025;0;comment;start rockerSpeedTest

TS 2026-10-06 (port of mda_logEntries.m, TS 2026-10-05; 12-hour time stamps 2026-10-08; structured events 2026-10-18;
waiting lines, codes chamber, rigor and backup 2026-10-20)
"""
from __future__ import annotations

import datetime as _dt
import math
import os
import re

import numpy as np
import pandas as pd

from .clock_time import clock_time

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


def parse_clock_numbers(s):
    """'yyyy mm dd HH:MM:SS:fff' --> [y, mo, d, h, mi, s, ms] (NaN for all if not readable; ms NaN if missing)."""
    m = _CLOCK.match(s.strip())
    if not m:
        return [math.nan] * 7
    return [float(x) for x in m.groups()[:6]] + [float(m.group(7)) if m.group(7) else math.nan]


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
    nums = []
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
        rows.append([None, t / 1000.0, ch, code, tok[4].strip(), code.lower() == "comment"])
        nums.append(parse_clock_numbers(tok[0]))
    if not rows:
        return empty
    # 12-hour time stamps (software 2.0.7717-2.0.7769) corrected, see clock_time (2026-10-08)
    ver = [r[4] for r in rows if (r[3].lower() == "programinfo" and "version" in r[4].lower())
           or r[3].lower() == "programversion"]
    file_time = None
    mdd = re.sub(r"_log\.log$", ".mdd", log_file, flags=re.IGNORECASE)
    if mdd != log_file and os.path.isfile(mdd):
        file_time = _dt.datetime.fromtimestamp(os.path.getmtime(mdd))
    clk, info = clock_time(nums, [r[1] for r in rows], ver, file_time, [r[4] for r in rows])
    for r, c in zip(rows, clk):
        r[0] = c
    E = pd.DataFrame(rows, columns=cols)
    E["clockTime"] = pd.to_datetime(E["clockTime"])
    E.attrs["clock"] = info
    return E


STRUCTURED_CODES = ("system", "slice", "protocolrun", "schedulerun", "doc", "chamber", "rigor", "backup")
_LOGFILE = re.compile(r"^logfile[23]?\s+(opened|created|closed)\s*:\s*(.*)$", re.I)
_NEW_RUN = re.compile(r"^myodishcontrolsoftware opened", re.I)


def waiting_lines(code, text, t):
    """waiting lines of a log (2026-10-20, see log_events): w (bool array) and t_next = dataLogTime (s) of the
    'LogFile created/opened' of this log that follows each waiting line (NaN otherwise)"""
    low = [str(c).strip().lower() for c in code]
    txt = [str(x).strip() for x in text]
    n = len(low)
    w = np.zeros(n, bool)
    t_next = np.full(n, np.nan)
    kind, name = [""] * n, [""] * n
    for i in range(n):
        if low[i] == "event":
            m = _LOGFILE.match(txt[i])
            if m:
                kind[i] = m.group(1).lower()
                name[i] = re.split(r"[\\/]", m.group(2).strip())[-1].strip().lower()
    first = next((i for i in range(n) if kind[i] in ("opened", "created")), None)
    if first is None:
        return w, t_next
    own = [x == name[first] for x in name]
    is_open = [own[i] and kind[i] in ("opened", "created") for i in range(n)]
    is_close = [own[i] and kind[i] == "closed" for i in range(n)]
    inside = False
    for i in range(n):
        if is_open[i]:
            inside = True
        elif is_close[i]:
            inside = False  # the closing line still belongs to its session
        elif low[i] == "event" and _NEW_RUN.match(txt[i]):
            inside = False  # a new run of the program (e.g. after a crash)
            w[i] = True
        else:
            w[i] = not inside
    nxt = math.nan  # only lines followed by an opening of this log are waiting
    tt = np.asarray(t, float)
    for i in range(n - 1, -1, -1):
        if is_open[i]:
            nxt = float(tt[i])
        if w[i]:
            if math.isnan(nxt):
                w[i] = False
            else:
                t_next[i] = nxt
    return w, t_next


def log_events(src):
    """Structured events of a MyoDish log file (2026-10-18): lines of the control software (builds from 2026-10, release
    2.2) whose value is one JSON object, code system, slice, protocolRun, scheduleRun, doc, chamber, rigor or backup.
    MATLAB: mda_logEntries(logFile, 'events').

        V = log_events(log_file)      or  V = log_events(E)  (E = log_entries(log_file), in log order)

    V: DataFrame, one row per structured line, in log order: row (row of E, from 0; MATLAB from 1), clockTime, t_file
    (s), t_logged (s), channel, code, event, actionId, by ('' if null), waiting, data (dict of all fields of the JSON
    object, read by name; absent fields are absent).
    t_logged: the dataLogTime of the line. t_file: the same, except for a waiting line.
    waiting (2026-10-20): the event happened while no main recording ran; the control software keeps such lines in
    memory and writes them into the next main log right before its 'LogFile created/opened'. Their dataLogTime is the
    frozen counter of the last main recording of that program run (another file, or 0), not a time in this file, so
    their t_file is the dataLogTime of that 'LogFile created/opened' (where this file was when the recording began).
    Rule: waiting are the lines after the last 'LogFile closed' of this log (or after the start of the log, or from a
    line 'MyodishControlSoftware opened' = a new run of the program, e.g. after a crash) up to the next 'LogFile
    created/opened' of this log; LogFile2 (second recording) and LogFile3 (rocker stop recording) count as well, and
    only lines about this log (the file name after the colon = the name in its first 'LogFile created/opened' line; a
    main log also holds lines about the other logs). Logs of a second or rocker stop recording have no waiting lines.
    Known limit: when the software lost the 'LogFile2/3 closed' line of the previous session (it does when all files are
    closed at once), the waiting lines before the next opening are not recognized. The old text lines stay as they are
    and are not in V. A line is structured if its code is one of these and its value starts with '{' (old
    lines never do; comments are checked by the code); lines that cannot be read (e.g. cut off by a crash) are counted
    in V.attrs['nUnreadable'] (rows of E in V.attrs['unreadable']) and left out. Unknown events and fields are kept."""
    import json
    E = src if isinstance(src, pd.DataFrame) else log_entries(src)
    cols = ["row", "clockTime", "t_file", "t_logged", "channel", "code", "event", "actionId", "by", "waiting", "data"]
    if len(E) == 0:
        V = pd.DataFrame({c: [] for c in cols})
        V.attrs.update(nUnreadable=0, unreadable=[])
        return V
    code = E["code"].astype(str).str.strip()
    txt = E["text"].astype(str).str.strip()
    low = code.str.lower()
    isS = (low.isin(STRUCTURED_CODES) & txt.str.startswith("{")).to_numpy(bool)
    wait, t_open = waiting_lines(code.tolist(), txt.tolist(), E["t_file"].to_numpy(float))
    rows, bad = [], []
    for i in np.flatnonzero(isS):
        try:
            d = json.loads(txt.iloc[i])
        except ValueError:
            d = None
        if not isinstance(d, dict):
            bad.append(int(i))
            continue
        t = float(E["t_file"].iloc[i])
        rows.append([int(i), E["clockTime"].iloc[i], float(t_open[i]) if wait[i] else t, t, float(E["channel"].iloc[i]),
                     code.iloc[i], str(d.get("event") or ""), str(d.get("actionId") or ""), str(d.get("by") or ""),
                     bool(wait[i]), d])
    V = pd.DataFrame(rows, columns=cols)
    if len(V):
        V["clockTime"] = pd.to_datetime(V["clockTime"])
    V.attrs.update(nUnreadable=len(bad), unreadable=bad)
    return V
