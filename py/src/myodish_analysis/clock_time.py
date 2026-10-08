"""Clock time of MyoDish log entries; corrects the 12-hour time stamps of software 2.0.7717-2.0.7769. Port of
mda_clockTime.m.

    clk, info = clock_time(N, t, program_version=None, file_time=None, text=None)

N                n x 7: system time of each log entry as numbers: year month day hour minute second millisecond
                 (e.g. from '2021 03 01 03:11:50:000'); rows with NaN in columns 1-6: not readable (clk None)
t                n: dataLogTime of the entries (s; NaN if not readable)
program_version  'programInfo' entry (entries) of the log, e.g. 'Version 2.0.7769.26061' (str or list; optional)
file_time        time of the last change of the .mdd file (datetime or MATLAB datenum, local time; optional)
text             n values of the entries (optional; 'Started parallel recording: 01.Mar.2021 16:50:17' gives the
                 24-hour time of its entry)

clk              list of datetime (None if not readable): real-world clock time of the entries
info             dict: format ('24h' or '12h'), nCorrected (entries shifted by 12 h), ambiguous (True: 12-hour time
                 stamps whose AM/PM could not be determined; clk as written), source ('log', 'file time' or '' =
                 nothing corrected), note (text for the notes of the file; '' if nothing to report)

MyoDish software 2.0.7717 to 2.0.7769 (builds of 16.02.-09.04.2021; one setup used 2.0.7769 until 2024) wrote the
system time with a 12-hour clock and without AM/PM ('hh' instead of 'HH': 17:04 is written as 05:04, 00:30 as 12:30).
2.0.7712 and earlier and 2.0.7971 and later write 24-hour time stamps. A log can contain both (program restarted with
another version). The dataLogTime of the entries (ms since the start of the recording) is continuous, so AM/PM of the
entries follows from it:
  - an entry with hour 1-12 has two candidate times (as written, hour mod 12, and 12 h later); hours 0 and 13-23 are
    24-hour time stamps and stay as written.
  - entries 'Started / Stopped parallel recording: dd.MMM.yyyy HH:mm:ss' carry the 24-hour time in their text (also
    in the affected versions): their candidate is known.
  - the offset clock time - dataLogTime that most entries share (+-5 min) belongs to the recording; every entry takes
    the candidate with this offset (or with the offset +-1 h: change of daylight saving time). Entries with the same
    dataLogTime count once together (the software may log thousands of entries with a frozen dataLogTime).
  - entries without this offset (logged before 'Recording started' with the dataLogTime of a previous recording, or
    with a frozen dataLogTime after the recording) take the candidate that keeps the log in chronological order.
  - a log counts as 12-hour if a 'programInfo' / 'ProgramVersion' entry names a version between 2.0.7713 and 2.0.7970
    (the last unaffected and the first unaffected build seen in 16,203 logs of 2020-2026: 2.0.7712 and 2.0.7971), if a
    'parallel recording' entry shows it, or if entries of the recording need the correction and the corrected log is
    not less chronological than as written (rejects e.g. 24-hour logs with entries whose stale dataLogTime belongs to
    a recording that started 12 h earlier). 24-hour logs are not changed.
  - if all entries of the recording lie on the same side of noon / midnight, the log cannot tell AM from PM. Then the
    time of the last change of the .mdd file decides if it agrees with one of the two possible ends of the recording
    within 15 min (in 908 of 974 recordings checked, the file time was within 2 min of 'Recording stopped');
    otherwise the times stay as written and info['ambiguous'] is True (possibly 12 h too early).

TS 2026-10-08 (port of mda_clockTime.m)
"""
from __future__ import annotations

import datetime as _dt
import math
import re

import numpy as np

_DATENUM_OFFSET = 366
_VER = re.compile(r"(\d+)\.(\d+)\.(\d+)(\.\d+)?")
_PAR = re.compile(r"(Started|Stopped) parallel recording: *\d{1,2}\.\S+\.\d{4} (\d{1,2}):(\d{2}):\d{2}", re.IGNORECASE)
H12 = 43200000
TOL = 600000


def _finite(x):
    return x is not None and not (isinstance(x, float) and math.isnan(x))


def clock_time(N, t, program_version=None, file_time=None, text=None):
    n = len(N)
    info = {"format": "24h", "nCorrected": 0, "ambiguous": False, "source": "", "note": ""}
    clk = [None] * n
    if n == 0:
        return clk, info
    ok = np.zeros(n, dtype=bool)
    P = np.full(n, np.nan)
    h = np.full(n, np.nan)
    for i, row in enumerate(N):
        row = list(row) + [0] * (7 - len(row))
        if not all(_finite(x) for x in row[:6]):
            continue
        y, mo, d, hh, mi, s = (int(x) for x in row[:6])
        ms = int(row[6]) if _finite(row[6]) else 0
        try:
            c = _dt.datetime(y, mo, d, hh, mi, s) + _dt.timedelta(milliseconds=ms)
        except ValueError:
            continue
        clk[i] = c
        ok[i] = True
        day = _dt.date(y, mo, d).toordinal() + _DATENUM_OFFSET
        P[i] = day * 86400000.0 + ((hh * 60 + mi) * 60 + s) * 1000.0 + ms
        h[i] = hh

    # affected software version?
    if program_version is None:
        program_version = []
    elif isinstance(program_version, str):
        program_version = [program_version]
    ver = ""
    affected = False
    for pv in program_version:
        m = _VER.search(str(pv))
        if not m:
            continue
        b = int(m.group(3))
        vtxt = f"{m.group(1)}.{m.group(2)}.{m.group(3)}{m.group(4) or ''}"
        if int(m.group(1)) == 2 and 7713 <= b <= 7970:
            affected = True
            ver = vtxt
        elif not ver:
            ver = vtxt

    two = ok & (h >= 1) & (h <= 12)
    base = P.copy()
    m12 = two & (h == 12)
    base[m12] = P[m12] - H12
    kWritten = m12.astype(float)
    # 24-hour time in the text of the entry ('Started parallel recording: 01.Mar.2021 16:50:17')
    kText = np.full(n, np.nan)
    if text is not None and len(text) == n:
        for i in np.flatnonzero(two):
            q = _PAR.search(str(text[i]))
            if not q:
                continue
            hT = int(q.group(2)); mT = int(q.group(3))
            if 0 <= hT <= 23 and mT == int(N[i][4]) and hT % 12 == int(h[i]) % 12:
                kText[i] = float(hT >= 12)
    known = ~np.isnan(kText)
    fixedVal = P.copy()
    fixedVal[known] = base[known] + kText[known] * H12
    needText = bool(np.any(known & (kText != kWritten)))
    two = two & ~known
    tt = np.asarray(t, dtype=float).ravel()
    tm = np.round(tt * 1000.0)
    v = ok & np.isfinite(tm)

    # offset shared by most entries (60 s bins, window +-5 bins); ties: more entries as written, then the earlier
    # offset. Weight of an entry: 1 / number of entries with the same dataLogTime (entries logged while the
    # dataLogTime is frozen, e.g. after the end of a recording, count once together).
    w = np.zeros(n)
    if np.any(v):
        _, jt, ct = np.unique(tm[v], return_inverse=True, return_counts=True)
        w[v] = 1.0 / ct[jt]
    i2 = np.flatnonzero(v & two)
    i1 = np.flatnonzero(v & ~two)
    cand = np.concatenate([base[i2] - tm[i2], base[i2] + H12 - tm[i2], fixedVal[i1] - tm[i1]])
    wc = np.concatenate([w[i2], w[i2], w[i1]])
    asw = np.concatenate([kWritten[i2] == 0, kWritten[i2] == 1, fixedVal[i1] == P[i1]])

    def rnd(x):  # sums of weights: identical in MATLAB and Python
        return np.floor(np.asarray(x) * 1e6 + 0.5) / 1e6

    if cand.size == 0:
        Ob = math.nan
        tie = False
        altBin = math.nan
    else:
        binv = np.floor(cand / 60000.0)
        ub, j = np.unique(binv, return_inverse=True)
        cs = np.concatenate([[0.0], np.cumsum(np.bincount(j, weights=wc, minlength=len(ub)))])
        csW = np.concatenate([[0.0], np.cumsum(np.bincount(j, weights=wc * asw, minlength=len(ub)))])
        m = len(ub)
        lo = np.searchsorted(ub, ub - 5, side="left")
        hi = np.searchsorted(ub, ub + 5, side="right")
        sc = rnd(cs[hi] - cs[lo])
        scW = rnd(csW[hi] - csW[lo])
        o = np.lexsort((ub, -scW, -sc))
        Ob = ub[o[0]]
        best = sc[o[0]]

        def score_at(b0):
            a0 = np.searchsorted(ub, b0 - 5, side="left")
            z0 = np.searchsorted(ub, b0 + 5, side="right")
            return 0.0 if a0 >= z0 else float(rnd(cs[z0] - cs[a0]))

        sPlus = score_at(Ob + 720)
        sMinus = score_at(Ob - 720)
        tie = max(sPlus, sMinus) >= best
        altBin = Ob + 720 if sPlus >= sMinus else Ob - 720

    def assign(Ob0):
        sh = np.zeros(n)
        need = False
        lastM = math.nan
        k = np.full(n, np.nan)
        anchor = ok & ~two
        if not math.isnan(Ob0):
            for kk in (0, 1):
                with np.errstate(invalid="ignore"):
                    off = np.floor((base + kk * H12 - tm) / 60000.0)
                    und = np.isnan(k)
                    inMain = v & two & und & (np.abs(off - Ob0) <= 5)
                    inDst = v & two & und & ~inMain & ((np.abs(off - Ob0 - 60) <= 5) | (np.abs(off - Ob0 + 60) <= 5))
                k[inMain] = kk
                k[inDst] = kk
                anchor = anchor | inMain | inDst
                need = need or bool(np.any(inMain & (kk != kWritten)))
                vals = base[inMain] + kk * H12
                if vals.size:
                    lastM = float(np.max(vals)) if math.isnan(lastM) else max(lastM, float(np.max(vals)))
            with np.errstate(invalid="ignore"):
                offS = np.floor((fixedVal - tm) / 60000.0)
                inMainS = v & ~two & (np.abs(offS - Ob0) <= 5)
            vals = fixedVal[inMainS]
            if vals.size:
                lastM = float(np.max(vals)) if math.isnan(lastM) else max(lastM, float(np.max(vals)))
        cur = fixedVal.copy()
        dec = two & ~np.isnan(k)
        cur[dec] = base[dec] + k[dec] * H12
        idx = np.flatnonzero(anchor)
        if idx.size == 0:
            return sh, need, lastM
        first = int(idx[0])
        last = cur[first]
        for ii in range(first + 1, n):
            if not ok[ii]:
                continue
            if two[ii] and np.isnan(k[ii]):
                k[ii] = float(base[ii] < last - TOL)
                cur[ii] = base[ii] + k[ii] * H12
            last = cur[ii]
        nxt = cur[first]
        for ii in range(first - 1, -1, -1):
            if not ok[ii]:
                continue
            if two[ii] and np.isnan(k[ii]):
                k[ii] = float(base[ii] + H12 <= nxt + TOL)
                cur[ii] = base[ii] + k[ii] * H12
            nxt = cur[ii]
        sh[ok] = cur[ok] - P[ok]
        return sh, need, lastM

    shift, needCorr, lastMain = assign(Ob)
    if needCorr and not affected and not needText:
        # correction found in the data only: reject it if it makes the log less chronological (more steps back by
        # > 65 min), e.g. for entries with the stale dataLogTime of a recording that started 12 h earlier
        io = np.flatnonzero(ok)
        if np.sum(np.diff(P[io] + shift[io]) < -3900000) > np.sum(np.diff(P[io]) < -3900000):
            needCorr = False
    is12 = needCorr or needText or affected
    if not is12:
        return clk, info
    info["format"] = "12h"
    src = "log"
    if tie:
        decided = False
        if file_time is not None and not math.isnan(lastMain):
            if isinstance(file_time, _dt.datetime):
                F = (file_time.toordinal() + _DATENUM_OFFSET) * 86400000.0 + (
                    file_time.hour * 3600 + file_time.minute * 60 + file_time.second) * 1000.0 + file_time.microsecond / 1000.0
            else:
                F = float(file_time) * 86400000.0
            shiftAlt, _, lastAlt = assign(altBin)
            if abs(F - lastMain) <= 900000 and abs(F - lastAlt) > 900000:
                decided = True
                src = "file time"
            elif abs(F - lastAlt) <= 900000 and abs(F - lastMain) > 900000:
                decided = True
                src = "file time"
                shift = shiftAlt
        info["ambiguous"] = not decided
    info["nCorrected"] = int(np.count_nonzero(shift != 0))
    if info["nCorrected"] > 0:
        for i in np.flatnonzero(ok & (shift != 0)):
            clk[i] = clk[i] + _dt.timedelta(milliseconds=float(shift[i]))
    vt = f", software {ver}" if ver else ""
    if info["ambiguous"]:
        info["note"] = (f"12-hour time stamps in the log file (no AM/PM{vt}): AM/PM of the recording unknown, "
                        "clock times as written (possibly 12 h too early).")
    elif info["nCorrected"] > 0:
        info["source"] = src
        info["note"] = (f"12-hour time stamps in the log file (no AM/PM{vt}): clock time of {info['nCorrected']} "
                        f"entries corrected by 12 h (AM/PM from the {'dataLogTime' if src == 'log' else src}).")
    return clk, info
