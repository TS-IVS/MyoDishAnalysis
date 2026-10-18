# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Slice register: one row per slice (channel of a setup from putting the slice in until it was taken out, the signal
was lost or the data end), built from the results of the watcher. Port of mda_sliceRegister.m.

    R = slice_register(results_folder)                       all experiments; writes the register files
    R = slice_register(results_folder, experiments=["expA"]) only these experiments (folders of the recordings in the
                                                             raw folder, relative to it)
    R = slice_register(..., new_slice_hours=2.0, write=True)
    R = slice_register(..., trends=True, trend_parameters=("amplitude", "diastolicForce", "TTP90", "TTR90"))
        images of the series and the experiment (2026-10-15; the watcher with trends=True), see below
    series_of(name)               (series, number) of a recording (name of the file)
    result_folder(rel, folders)   folder of the results of the recording rel (path relative to the raw folder)
                                  relative to the results folder of the watcher: folders 'series' (default) or 'flat'

Result folders of the watcher (folders=..., 2026-10-15):
  'series' (default)  <experiment>/<series>/<nn>/ for recordings with a number (Setup1_ABC000101_3.mdd ->
                      ABC000101/Setup1_ABC000101/03/; also its parallel recordings, e.g. ..._3_scheduleFile_...),
                      <experiment>/<name>/ for recordings without a number
  'flat'              <experiment>/ (all result files of the experiment in one folder, as before)
  Both layouts are read (also mixed; a recording with results in both: the series layout).

Images (trends=True; results with overview), per experiment:
  <series>/<series>_ch<c>.png  (flat layout: trends/<series>_ch<c>.png) per numbered series and channel with at least
      20 included contractions: per parameter of trend_parameters the whole time course of the series (left; all
      slices of the channel, slice changes dashed, the last 24 h yellow, recordings with red flags of the analysis
      report (mda_flags.csv) as red bars) and the last 24 h of the data (right; numbered comments with a list below);
      report.course_image
  <series>/<series>_trends.xlsx  (flat: trends/) the data of these images: sheets course (channel, slice, bin = clock
      time of the start of the bin, dayInCulture, nBeats = included contractions, the parameters = median of the 1-min
      values of the bin, binMinutes), last24h (channel, slice, window, nBeats, parameters per minute), comments
      (channel, number as in the image, clockTime, text) and slices (rows of the register of the series)
  <experiment>_overview.png  (mda_overview_root.png for recordings directly in the raw folder) all numbered series x
      channels: amplitude over the whole time course, status at the end of the data of the last slice, last amplitude,
      change in the last 24 h, % of the maximum, red frame = recordings with red flags (number); report.experiment_image

Experiment = folder of the recordings in the raw folder (relative to it). Series = recordings of one setup: the file
name up to its number (rigA_X_0, rigA_X_1, ... --> series rigA_X); channels are followed through the recordings of a
series in the order of their start.
Inputs per recording (watcher, gaps=True): channels (required) and gaps (sheets of <name>.xlsx or <name>_channels.csv,
<name>_gaps.csv), <name>_overview.csv(.gz); with trends=True also events (sheet / <name>_events.csv) and the protocols
(<name>_protocols.xlsx, sheet protocols, or <name>_protocols_protocols.csv).
Parallel recordings of a main file are ignored (mda_index.csv: status 'parallel', or analysed while their main file
has results; 2026-10-13/14): no contraction or stimulus is counted twice.

A new slice begins in a channel
  - with its first signal ('first signal'),
  - after a chamber-out period with a comment such as 'new slice', 'replaced', 'exchanged', 'getauscht' within 5 min
    of its start or end ('comment: <the comment>'), if the comment names the slice (slice, Schnitt, tissue, S<n>C<n>) or
    nothing else that can be exchanged (not: medium exchange, setup / sensor board / electrode exchanged, chamber
    replaced = the same slice in a new chamber; 2026-10-11),
  - when the label sliceID (<name>_labels.csv next to the recording) changes ('other sliceID'),
  - with the signal after a recording without signal in this channel ('after a recording without signal') or after
    >= new_slice_hours (default 2 h) without signal ('after # h without signal'), unless a comment within 5 min of the
    start or end of the period says the slice was put back ('moved back', 'put back', 'reinserted', 'wieder
    eingesetzt': same slice, nPutBack).
Shorter chamber-out periods (medium change, looking at the slice) belong to the slice (nChamberOut, outHours). Which
slice was put back is not in the signal: a slice exchanged within new_slice_hours without a comment or label stays
one row. Technical periods (board group, controller, saturated) do not end a slice.

R  DataFrame (and files <experiment>/<name of the experiment folder>_slices.csv, mda_slices_root.csv for recordings
   directly in the results folder, mda_slices.csv with all experiments), one row per slice:
     experiment, series, channel, slice (1, 2, ... per series and channel), setupID, sampleID, species, sliceID,
     idDate (labels of the first recording of the slice; idDate = yymmdd of the file name, see the watcher)
     startTime, endTime  clock time of the first and the last signal of the slice
     daysInSetup     (endTime - startTime) in days
     startReason     see above; insertedLater = not with the first signal of the series (or > new_slice_hours later)
     endStatus       'removed' (chamber out and not put back, or another slice afterwards), 'beating at end of data',
                     'not beating at end of data' (no contraction in the last 30 min with signal), 'signal lost'
                     (technical, until the end of the data), 'replaced (other sliceID)'
     beatingAtEnd    a contraction within the last 30 min with signal
     lastBeat        clock time of the end of the last 1-min window with contractions (overview)
     lastAmplitude   amplitude (median, included contractions) of the last 1-min window with contractions
     maxAmplitude    95th percentile of the 1-min amplitudes of the slice; lastAmplitude_pctMax = 100 * last / max
     nBeats          contractions of the slice (all, from the overview)
     dayStart, dayEnd  days since cultureStart (label) or since 00:00 of idDate (daySource); NaN for slices inserted
                     later without cultureStart (they may come from another preparation)
     nRecordings, firstRecording, lastRecording, nChamberOut, outHours, longestOut_min, nPutBack (long periods
     without signal bridged by a put-back comment), nTechnical (periods),
     calibration     'Calibration' values (AU per mN) of the channel in the recordings of the slice (';' separated)
     calibrationChanged  1 if the calibration changed during the slice or differs from another row with the same
                     sliceID (slice moved to another setup): force values / fold changes over time are only comparable
                     after conversion to uN (2026-10-10)
     endComments     comments of the log file about the end (removed, discarded, fixed, frozen, imaging, ...)
   Without <name>_overview.csv (overview_seconds=0) lastBeat, lastAmplitude, maxAmplitude and nBeats come from
   <name>_channels.csv (whole recording: for a slice replaced within a recording only the later slice gets them).

TS 2026-10-08 (calibration 2026-10-10; parallel recordings ignored 2026-10-13; result folders of the series, course
and overview images 2026-10-15)
"""
from __future__ import annotations

import datetime as _dt
import math
import os
import re

import numpy as np
import pandas as pd

from .signal_gaps import _prctile

RX_NEW_SLICE = re.compile(r"new slice|neues slice|replac|exchang|getauscht|ausgetauscht|ersetzt|swap", re.I)
# 2026-10-11: a comment with RX_NEW_SLICE counts only if it names the slice (RX_SLICE_WORD) or names nothing else that
# can be exchanged (RX_NOT_SLICE: medium exchange, setup / sensor board / electrode exchanged, chamber replaced = same
# slice in a new chamber)
RX_SLICE_WORD = re.compile(r"slice|schnitt|tissue|gewebe|\bLMS\b|\bS\d+C\d+\b", re.I)
RX_NOT_SLICE = re.compile(r"medi(um|a|en)|buffer|solution|l(oe|.)sung|setup|sensor|board|platine|electrode|elektrode|"
                          r"magnet|offset|calibr|kalibr|chamber|kammer|software|controller|cable|kabel|lid\b|deckel|"
                          r"computer|\bpc\b|pump|lamp|rocker", re.I)
RX_PUT_BACK = re.compile(r"moved back|put back|placed back|reinsert|re-insert|wieder eingesetzt|zur.{1,2}ckgesetzt",
                         re.I)
COLUMNS = ["experiment", "series", "channel", "slice", "setupID", "sampleID", "species", "sliceID", "idDate",
           "startTime", "endTime", "daysInSetup", "startReason", "insertedLater", "endStatus", "beatingAtEnd",
           "lastBeat", "lastAmplitude", "maxAmplitude", "lastAmplitude_pctMax", "nBeats", "dayStart", "dayEnd",
           "daySource", "nRecordings", "firstRecording", "lastRecording", "nChamberOut", "outHours", "longestOut_min", "nPutBack",
           "nTechnical", "calibration", "calibrationChanged", "endComments"]
ALL_NAME = "mda_slices.csv"
ROOT_NAME = "mda_slices_root.csv"
_FMT = "%Y-%m-%d %H:%M:%S"
_EPOCH = _dt.datetime(1970, 1, 1)


def slice_register(results_folder, experiments=None, new_slice_hours=2.0, write=True, trends=False,
                   trend_parameters=("amplitude", "diastolicForce", "TTP90", "TTR90")):
    res = os.path.abspath(results_folder)
    found = _experiments(res)
    todo = sorted(found) if experiments is None else [e for e in sorted(found) if e in set(experiments)]
    tp = [trend_parameters] if isinstance(trend_parameters, str) else list(trend_parameters)
    red = _red_flags(res) if trends else []
    out = {}
    for e in todo:
        R = _experiment(res, e, found[e], float(new_slice_hours), bool(trends), tp, bool(write), red)
        out[e] = R
        if write:
            R.to_csv(_file(res, e), index=False)
    if write:  # all experiments: the computed ones and the files of the others
        parts = []
        for e in sorted(found):
            if e in out:
                parts.append(out[e])
            elif os.path.isfile(_file(res, e)):
                parts.append(_read(_file(res, e)))
        A = pd.concat(parts, ignore_index=True) if parts else pd.DataFrame(columns=COLUMNS)
        A = A[[c for c in COLUMNS if c in A.columns]]
        A.to_csv(os.path.join(res, ALL_NAME), index=False)
    parts = [out[e] for e in todo]
    return pd.concat(parts, ignore_index=True) if parts else pd.DataFrame(columns=COLUMNS)


# ------------------------------------------------------------------------------------------------ helpers
def series_of(name):
    """(series, number) of a recording: file name up to its number (first part of digits only after the first part),
    number (NaN if none)"""
    return _series(name)


def result_folder(rel, folders="series"):
    """folder of the results of the recording rel (path relative to the raw folder, with or without .mdd) relative to
    the results folder ('/' separated, '' = the results folder): 'series' <folder>/<series>/<nn> (number with at least
    2 digits) or <folder>/<name> (no number); 'flat' <folder>"""
    rel = str(rel).replace("\\", "/")
    dr, _, n = rel.rpartition("/")
    n = re.sub(r"\.mdd$", "", n, flags=re.I)
    if str(folders).lower() == "flat":
        return dr
    s, num = _series(n)
    sub = n if math.isnan(num) else f"{s}/{int(num):02d}"
    return f"{dr}/{sub}" if dr else sub


def _experiment_of(rel, name):
    """experiment of the results of recording name in the folder rel (relative to the results folder) without an
    index: <e>/<series>/<nn> or <e>/<name> (series layout), otherwise rel (flat layout)"""
    p = rel.split("/") if rel else []
    s, num = _series(name)
    if not math.isnan(num) and len(p) >= 2 and re.fullmatch(r"\d+", p[-1]) and float(p[-1]) == num and p[-2] == s:
        return "/".join(p[:-2])
    if math.isnan(num) and p and p[-1] == name:
        return "/".join(p[:-1])
    return rel


def _full(e, n):
    return f"{e}/{n}" if e else n


def _experiments(res):
    """experiment ('/' separated folder of the recordings in the raw folder, '' = recordings directly in it) --> list of
    (folder of the results relative to res, name), from the result files (<name>_channels.csv or <name>.xlsx) in both
    layouts of the watcher (2026-10-15), without the parallel recordings of mda_index.csv (2026-10-13); a recording with
    results in both layouts: the series layout"""
    L = []
    for p, dirs, files in os.walk(res):
        dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d not in ("reports", "trends"))
        rel = os.path.relpath(p, res).replace(os.sep, "/")
        rel = "" if rel == "." else rel
        here = rel.rsplit("/", 1)[-1]
        names = set()
        for fn in files:
            if fn.startswith(".") or fn.startswith("~$"):
                continue
            if fn.endswith("_channels.csv"):
                names.add(fn[:-len("_channels.csv")])
            elif fn.endswith(".xlsx") and not fn.endswith("_protocols.xlsx") and fn != here + "_trends.xlsx":
                names.add(fn[:-5])  # results as .xlsx (2026-10-14)
        L += [(rel, n) for n in sorted(names)]
    if not L:
        return {}
    skip, files = _index_files(res)
    known = {}  # (folder, name) -> experiment, from the files of the index
    for f in files:
        r = re.sub(r"\.mdd$", "", f, flags=re.I)
        e, _, n = r.rpartition("/")
        for fo in (e, result_folder(r, "series")):
            known.setdefault((fo, n), e)
    best = {}
    for fo, n in L:
        e = known.get((fo, n))
        e = _experiment_of(fo, n) if e is None else e
        if _full(e, n) + ".mdd" in skip:
            continue
        ser = fo == result_folder(_full(e, n), "series")
        if (e, n) not in best or (ser and not best[(e, n)][1]):
            best[(e, n)] = (fo, ser)
    found = {}
    for (e, n), (fo, _) in sorted(best.items()):
        found.setdefault(e, []).append((fo, n))
    return found


def _index_files(res):
    """(files of parallel recordings, all files) of mda_index.csv (relative paths; '.mdd' lower case for the first):
    status 'parallel', or analysed ('parallel recording of <main> (...' in the message) while their main file has
    results (status ok): their data are in the results of the main file (2026-10-14)"""
    f = os.path.join(res, "mda_index.csv")
    if not os.path.isfile(f):
        return set(), []
    try:
        X = pd.read_csv(f, usecols=["file", "status", "message"], dtype=str, keep_default_na=False)
    except (ValueError, OSError, pd.errors.ParserError):
        return set(), []
    files = [str(x).replace("\\", "/") for x in X["file"]]
    ok = set(X.loc[X["status"] == "ok", "file"])
    out = set()
    for fl, st, msg in zip(files, X["status"], X["message"]):
        m = re.match(r"parallel recording of (.+?\.mdd) \(", msg, re.I)
        if st == "parallel" or (m and m.group(1) in ok):
            out.add(re.sub(r"\.mdd$", ".mdd", fl, flags=re.I))
    return out, files


def _red_flags(res):
    """(recording without .mdd, channel) with red flags of the analysis report (mda_flags.csv, level 'check')"""
    f = os.path.join(res, "mda_flags.csv")
    if not os.path.isfile(f):
        return []
    try:
        X = pd.read_csv(f, usecols=["file", "channel", "level"], dtype={"file": str, "level": str},
                        keep_default_na=False)
    except (ValueError, OSError, pd.errors.ParserError):
        return []
    X = X[X["level"] == "check"]
    return [(re.sub(r"\.mdd$", "", str(a).replace("\\", "/"), flags=re.I), float(c))
            for a, c in zip(X["file"], pd.to_numeric(X["channel"], errors="coerce"))]


def _file(res, e):
    if not e:
        return os.path.join(res, ROOT_NAME)
    return os.path.join(res, *e.split("/"), e.split("/")[-1] + "_slices.csv")


def _read(f):
    """all columns as text ('' for empty); numbers converted by the callers."""
    return pd.read_csv(f, dtype=str, keep_default_na=False)


def _read_tab(folder, n, tab, cols=None):
    """table tab of recording n as text: sheet of <n>.xlsx (2026-10-14) or <n>_<tab>.csv(.gz); None if missing"""
    x = os.path.join(folder, n + ".xlsx")
    if os.path.isfile(x):
        try:
            with pd.ExcelFile(x) as xl:
                if tab in xl.sheet_names:
                    T = xl.parse(tab, dtype=str, keep_default_na=False)
                    return T if cols is None else T[[c for c in T.columns if c in cols]]
        except Exception:  # noqa: BLE001 - not readable: the csv files
            pass
    f = os.path.join(folder, f"{n}_{tab}.csv")
    for g in (f, f + ".gz"):
        if os.path.isfile(g):
            return pd.read_csv(g, dtype=str, keep_default_na=False,
                               usecols=(lambda c: c in cols) if cols is not None else None)
    return None


def _num(T, c):
    if c not in T.columns:
        return np.full(len(T), np.nan)
    return pd.to_numeric(T[c].replace({"": "NaN"}), errors="coerce").to_numpy(float)


def _txt(T, c):
    return T[c].astype(str).tolist() if c in T.columns else [""] * len(T)


def _bool(T, c):
    return np.array([str(v).strip().lower() in ("1", "true") for v in _txt(T, c)], dtype=bool)


def _series(name):
    """file name up to its number (first part of digits only after the first part), number"""
    parts = name.split("_")
    for i in range(1, len(parts)):
        if re.fullmatch(r"\d+", parts[i]):
            return "_".join(parts[:i]), float(parts[i])
    return name, math.nan


def _seconds(s):
    """clock text --> s since 1970 (NaN if empty / not readable): 'yyyy-mm-dd[ HH:MM[:SS]]' or
    'dd.mm.yyyy[ HH:MM[:SS]]'"""
    p = str(s).strip().split(" ")
    if not p[0] or len(p) > 2:
        return math.nan
    m = re.fullmatch(r"(\d{4})-(\d{1,2})-(\d{1,2})", p[0])
    if m:
        x = [int(m.group(1)), int(m.group(2)), int(m.group(3)), 0, 0, 0]
    else:
        m = re.fullmatch(r"(\d{1,2})\.(\d{1,2})\.(\d{4})", p[0])
        if not m:
            return math.nan
        x = [int(m.group(3)), int(m.group(2)), int(m.group(1)), 0, 0, 0]
    if len(p) == 2:
        h = p[1].split(":")
        if len(h) < 2 or len(h) > 3 or not all(re.fullmatch(r"\d{1,2}", v) for v in h):
            return math.nan
        x[3:3 + len(h)] = [int(v) for v in h]
    try:
        d = _dt.datetime(x[0], x[1], x[2])
    except ValueError:
        return math.nan
    if x[3] > 23 or x[4] > 59 or x[5] > 59:
        return math.nan
    return (d - _EPOCH).total_seconds() + x[3] * 3600 + x[4] * 60 + x[5]


def _clock(t):
    if t is None or math.isnan(t):
        return ""
    return (_EPOCH + _dt.timedelta(seconds=int(math.floor(t + 0.5)))).strftime(_FMT)


def _experiment(res, e, items, hours, trends=False, tp=(), write=True, red=()):
    folder = os.path.join(res, *e.split("/")) if e else res
    recs = []
    oc = ["channel", "t_from", "t_to", "nBeats", "amplitude", "included"]
    if trends:
        oc += [x for x in tp if x not in oc]
    for fo, n in items:
        d = os.path.join(res, *fo.split("/")) if fo else res
        CH = _read_tab(d, n, "channels")
        if CH is None or not len(CH):
            continue
        G = _read_tab(d, n, "gaps")
        Ov = _read_tab(d, n, "overview", oc)
        E = PR = None
        if trends:
            E = _read_tab(d, n, "events", ["t_file", "channel", "category", "text"])
            PR = _read_tab(d, n + "_protocols", "protocols", ["name", "from", "to"])
        name = _txt(CH, "recording")[0] or n
        series, num = _series(name)
        recs.append(dict(name=name, series=series, num=num, start=_seconds(_txt(CH, "recordingStart")[0]),
                         L=float(_num(CH, "fileLength_s")[0]), CH=CH, G=G, O=Ov, E=E, PR=PR, folder=fo))
    # order: series, start (unknown start: after the known ones), number, name
    recs.sort(key=lambda r: (r["series"], math.isnan(r["start"]), 0 if math.isnan(r["start"]) else r["start"],
                             math.inf if math.isnan(r["num"]) else r["num"], r["name"]))
    rows = []
    slices = []  # slices (trend images)
    for series in sorted(set(r["series"] for r in recs)):
        S = [r for r in recs if r["series"] == series]
        prevEnd = math.nan
        for r in S:  # unknown start: end of the previous recording of the series
            if math.isnan(r["start"]):
                r["start"] = prevEnd if not math.isnan(prevEnd) else 0.0
            prevEnd = r["start"] + (r["L"] if not math.isnan(r["L"]) else 0.0)
        chans = sorted(set(float(c) for r in S for c in _num(r["CH"], "channel")))
        for c in chans:
            rr, cc = _channel(e, series, c, S, hours, trends, tp)
            rows += rr
            slices += cc
    R = pd.DataFrame(rows, columns=COLUMNS)
    # calibration (2026-10-10): rows of the same sliceID (slice moved to another setup) with other calibration values
    if len(R):
        sid = R["sliceID"].astype(str).to_numpy()
        cal = R["calibration"].astype(str).to_numpy()
        chg = R["calibrationChanged"].to_numpy(float).copy()
        for i in range(len(R)):
            if not sid[i] or not cal[i]:
                continue
            j = (sid == sid[i]) & (cal != "")
            if len(set(cal[j])) > 1:
                chg[i] = 1
        R["calibrationChanged"] = chg
    if trends and write:
        _series_images(folder, e, recs, slices, R, tp, red)
    return R


def _new(e, series, c, k, t, reason, row, seriesStart, hours):
    lab = {nm: row[nm] for nm in ("setupID", "sampleID", "species", "sliceID", "idDate", "cultureStart")}
    inserted = reason != "first signal" or t - seriesStart > hours * 3600
    return dict(e=e, series=series, c=c, k=k, start=t, reason=reason, inserted=inserted, lab=lab, last=t,
                recs=[], nOut=0, outSec=0.0, longest=0.0, nTech=0.0, nPutBack=0, W=[], fb=[], endCand="",
                endComments="", closed="", cal=[], TV=[], com=[], bands=[], band_labels=[])


def _channel(e, series, c, S, hours, trends=False, tp=()):
    rows = []
    slices = []
    cur = None
    k = 0
    outSince = None
    outText = ""
    emptyBetween = False
    seriesStart = S[0]["start"]
    for r in S:
        CH = r["CH"]
        i = np.flatnonzero(_num(CH, "channel") == c)
        if not i.size:
            continue
        i = int(i[0])
        row = {nm: _txt(CH, nm)[i] for nm in ("status", "setupID", "sampleID", "species", "sliceID", "idDate",
                                                "cultureStart", "endComments", "calibration")}
        St, L = r["start"], r["L"]
        if row["status"] == "no slice":
            if cur is not None:
                if outSince is None:
                    outSince = cur["last"]
                emptyBetween = True
            continue
        outs = []  # chamber-out periods of this channel (file time)
        G = r["G"]
        if G is not None and len(G):
            gc, typ = _num(G, "channel"), _txt(G, "type")
            ga, gb, gt = _num(G, "from"), _num(G, "to"), _txt(G, "comments")
            for j in np.flatnonzero((gc == c) & (np.array(typ) == "chamber out")):
                outs.append((ga[j], gb[j], gt[j]))
            outs.sort()
        segs, t = [], 0.0
        for a, b, _ in outs:
            if a > t:
                segs.append((t, a))
            t = max(t, b)
        if t < L:
            segs.append((t, L))
        for a, b in segs:
            tOn = St + a
            cmOn = " ".join(x[2] for x in outs if abs(x[1] - a) < 1e-6)
            sid = row["sliceID"]
            if cur is None:
                k += 1
                cur = _new(e, series, c, k, tOn, "first signal" if k == 1 else "signal after no slice", row,
                           seriesStart, hours)
            else:
                reason = ""
                if outSince is None:
                    if a == 0 and sid and cur["lab"]["sliceID"] and sid != cur["lab"]["sliceID"]:
                        reason = "other sliceID"
                else:
                    dur = tOn - outSince
                    txt = outText + " " + cmOn
                    nc = _new_slice_comment(outText, cmOn)
                    long_ = emptyBetween or dur >= hours * 3600
                    if nc:
                        reason = "comment: " + nc
                    elif sid and cur["lab"]["sliceID"] and sid != cur["lab"]["sliceID"]:
                        reason = "other sliceID"
                    elif long_ and RX_PUT_BACK.search(txt):
                        cur["nPutBack"] += 1  # same slice put back (comment), however long it was out
                    elif emptyBetween:
                        reason = "after a recording without signal"
                    elif dur >= hours * 3600:
                        reason = "after %.1f h without signal" % (dur / 3600)
                if reason:
                    cur["closed"] = "removed" if outSince is not None else "replaced (other sliceID)"
                    rows.append(_row(cur, hours))
                    slices.append(cur)
                    k += 1
                    cur = _new(e, series, c, k, tOn, reason, row, seriesStart, hours)
                elif outSince is not None:
                    cur["nOut"] += 1
                    cur["outSec"] += tOn - outSince
                    cur["longest"] = max(cur["longest"], tOn - outSince)
            outSince, outText, emptyBetween = None, "", False
            cur["last"] = St + b
            if r["name"] not in cur["recs"]:
                cur["recs"].append(r["name"])
            if row["calibration"]:
                cur["cal"] += row["calibration"].split(";")
            O = r["O"]
            if O is not None and len(O):
                oc, tf, tt = _num(O, "channel"), _num(O, "t_from"), _num(O, "t_to")
                sel = np.flatnonzero((oc == c) & (tf >= a - 1e-6) & (tf < b))
                amp, nb, inc = _num(O, "amplitude"), _num(O, "nBeats"), _bool(O, "included")
                for j in sel:  # end of the window at most the end of the signal
                    cur["W"].append((St + tf[j], St + min(tt[j], b), amp[j], nb[j], bool(inc[j])))
                if trends:  # values of the trend parameters (2026-10-14)
                    V = np.column_stack([_num(O, x)[sel] for x in tp]) if len(tp) else np.zeros((len(sel), 0))
                    for q, j in enumerate(sel):
                        cur["TV"].append([St + tf[j], nb[j], float(inc[j])] + list(V[q]))
            if trends:
                _trend_events(cur, r, c, St, a, b)
            if b < L - 1e-6:
                outSince = St + b
                outText = " ".join(x[2] for x in outs if abs(x[0] - b) < 1e-6)
        if cur is not None and segs and r["name"] in cur["recs"]:
            cur["nTech"] += _num(CH, "nTechnical")[i] if not math.isnan(_num(CH, "nTechnical")[i]) else 0.0
            if segs[-1][1] >= L - 1e-6:
                cur["endCand"] = row["status"]
            cur["endComments"] = row["endComments"]
            if r["O"] is None:  # no overview: values of the whole recording
                lc = _num(CH, "lastContraction_s")[i]
                cur["fb"].append((St + lc if not math.isnan(lc) else math.nan, _num(CH, "lastAmplitude")[i],
                                  _num(CH, "maxAmplitude")[i], _num(CH, "nContractions")[i]))
    if cur is not None:
        if outSince is not None:
            cur["closed"] = "removed"
        rows.append(_row(cur, hours))
        slices.append(cur)
    return rows, slices


def _trend_events(cur, rec, c, St, a, b):
    """comments, protocols and periods without signal of channel c in the segment [a b] (file time) of a recording"""
    E = rec.get("E")
    if E is not None and len(E):
        t, ch, cat, tx = _num(E, "t_file"), _num(E, "channel"), _txt(E, "category"), _txt(E, "text")
        for j in np.flatnonzero((t >= a) & (t <= b) & ((ch == 0) | (ch == c))):
            if cat[j] in ("comment", "protocol"):
                cur["com"].append(dict(t=St + t[j], text=tx[j], category=cat[j]))
    PR = rec.get("PR")
    if PR is not None and len(PR):
        pa, pb, pn = _num(PR, "from"), _num(PR, "to"), _txt(PR, "name")
        for j in np.flatnonzero((pb > a) & (pa < b)):
            cur["bands"].append([St + max(pa[j], a), St + min(pb[j], b), 1])
            cur["band_labels"].append(pn[j])
    G = rec.get("G")
    if G is not None and len(G):
        ga, gb = _num(G, "from"), _num(G, "to")
        for j in np.flatnonzero((_num(G, "channel") == c) & (gb > a - 1) & (ga < b + 1)):
            cur["bands"].append([St + ga[j], St + gb[j], 2])
            cur["band_labels"].append("")


def _series_images(folder, e, recs, slices, R, tp, red):
    """images of the numbered series (2026-10-15): course image per channel and <series>_trends.xlsx in
    <experiment>/<series>/ (results in the series layout) or <experiment>/trends/ (flat layout), overview image of the
    experiment"""
    from .parameters import PARAMETERS
    from .report import course_data, course_image
    td = os.path.join(folder, "trends")
    _delete_matching(td, r"_ch\d+_slice\d+\.png$")  # slice images of 2026-10-14 (replaced by the course images)
    if e:
        en = os.path.basename(folder)
        ov = os.path.join(folder, en + "_overview.png")
    else:
        en, ov = "(results folder)", os.path.join(folder, "mda_overview_root.png")
    if os.path.isfile(ov):
        os.remove(ov)
    if not recs or not slices:
        _remove_empty(td)
        return
    units = {p[0]: p[1] for p in PARAMETERS}
    un = [units.get(x, "1/min" if x == "beatsPerMinute" else "") for x in tp]
    red = set(red)
    OV = []  # cells of the overview image: (series, channel, indices of the slices, recordings with red flags)
    for ser in sorted({r["series"] for r in recs if not math.isnan(r["num"])}):
        S = [r for r in recs if r["series"] == ser]
        is_ser = any(r["folder"] != e for r in S)  # results in <experiment>/<series>/<nn>/
        out, old = (os.path.join(folder, ser), td) if is_ser else (td, os.path.join(folder, ser))
        _delete_series_outputs(old, ser)
        _delete_series_outputs(out, ser)
        if not is_ser:
            _remove_empty(old)  # series folder of the other layout without results
        J = [j for j, c in enumerate(slices) if c["series"] == ser]
        if not J:
            continue
        t0s, t1s = min(slices[j]["start"] for j in J), max(slices[j]["last"] for j in J)
        a0 = math.floor(t0s / 86400) * 86400  # time 0 of the images: midnight (bins of the clock)
        base = math.nan  # day 0 of the series: first slice with cultureStart / idDate
        for j in sorted(J, key=lambda j: slices[j]["start"]):
            base = _slice_base(slices[j])
            if not math.isnan(base):
                break
        Tc, Tl, Tm = [], [], []
        for c in sorted({slices[j]["c"] for j in J}):
            Jc = [j for j in J if slices[j]["c"] == c]
            Rd = [(r["start"] - a0, r["start"] + max(r["L"], 0.0) - a0) for r in S if (_full(e, r["name"]), c) in red]
            OV.append((ser, c, Jc, len(Rd)))
            D = _course_of([slices[j] for j in Jc], a0, t0s, t1s, base, tp, un, Rd)
            if D is None:
                continue
            cur = slices[Jc[-1]]
            v = [str(cur["lab"].get(nm, "")).strip() for nm in ("setupID", "sliceID", "species", "sampleID")]
            v = [x for x in v if x]
            lt = ("  ·  " + "  ·  ".join(v)) if v else ""
            D["title"] = f"{en}  ·  {ser}  ·  channel {int(c)}{lt}"
            D["subtitle"] = (_status_line(R.iloc[Jc[-1]], cur, len(Jc), base) + "\n" + _COURSE_LEGEND)
            course_image(os.path.join(out, f"{ser}_ch{int(c)}.png"), D)
            a1, a2, a3 = course_data(D)
            Tc.append(_course_rows(a1, c, "bin_from", "bin", D["t0"], base))
            Tl.append(_course_rows(a2, c, "t_from", "window", D["t0"], math.nan))
            a3 = a3.copy()
            a3.insert(0, "channel", float(c))
            a3["clockTime"] = _clock_of(D["t0"], a3["t"])
            Tm.append(a3[["channel", "number", "clockTime", "text"]])
        if Tc:
            os.makedirs(out, exist_ok=True)
            with pd.ExcelWriter(os.path.join(out, ser + "_trends.xlsx"), engine="openpyxl") as xw:
                pd.concat(Tc, ignore_index=True).to_excel(xw, sheet_name="course", index=False)
                pd.concat(Tl, ignore_index=True).to_excel(xw, sheet_name="last24h", index=False)
                pd.concat(Tm, ignore_index=True).to_excel(xw, sheet_name="comments", index=False)
                R[R["series"] == ser].to_excel(xw, sheet_name="slices", index=False)
    _remove_empty(td)
    if OV:
        _experiment_image(ov, en, OV, slices, R)


_COURSE_LEGEND = ("Left: dots = median per minute, line = median per bin; yellow = last 24 h; dashed = new slice; red "
                  "bar = red flags; light blue = protocol; grey = no signal. Right: the last 24 h, purple = comments")


def _course_of(sl, a0, t0s, t1s, base, tp, un, Rd):
    """data of the course image of one channel (slices sl of the channel; times in s since 1970: a0 time 0 of the image,
    t0s, t1s start and end of the series); None if fewer than 20 included contractions"""
    TV, com, B, bl, S = [], [], [], [], []
    for cur in sl:
        TV += cur["TV"]
        com += cur["com"]
        B += cur["bands"]
        bl += cur["band_labels"]
        S.append([cur["start"] - a0, cur["last"] - a0, cur["k"]])
    if not TV:
        return None
    TV = np.array(TV, float).reshape(len(TV), -1)
    if float(np.nansum(TV[TV[:, 2] > 0, 1])) < 20:
        return None
    B = np.array(B, float).reshape(-1, 3)
    if len(B):
        B[:, :2] -= a0
    return dict(title="", subtitle="", t=TV[:, 0] - a0, w=60.0, nb=TV[:, 1], inc=TV[:, 2] > 0, V=TV[:, 3:],
                names=list(tp), units=un, t0=_EPOCH + _dt.timedelta(seconds=a0), xlim=[t0s - a0, t1s - a0], bands=B,
                band_labels=bl, com=[dict(x, t=x["t"] - a0) for x in com], slices=np.array(S, float),
                last24=[max(t0s, t1s - 86400) - a0, t1s - a0],
                day_base=None if math.isnan(base) else _EPOCH + _dt.timedelta(seconds=base),
                red=np.array(Rd, float).reshape(-1, 2))


def _clock_of(t0, t):
    """clock times 'yyyy-mm-dd HH:MM:SS' of t (s after the datetime t0), rounded to seconds"""
    half = _dt.timedelta(microseconds=500000)
    return [(t0 + _dt.timedelta(seconds=float(x)) + half).replace(microsecond=0).strftime(_FMT) for x in t]


def _course_rows(T, c, tcol, name, t0, base):
    """rows of a sheet of <series>_trends.xlsx: channel, slice, clock time of tcol (s after t0) as name, dayInCulture
    (base: s since 1970; NaN: not added except for the course), the other columns"""
    T = T.copy()
    t = T.pop(tcol).to_numpy(float)
    T.insert(0, "channel", float(c))
    T.insert(2, name, _clock_of(t0, t))
    if not math.isnan(base) or name == "bin":
        d = (t0 - _EPOCH).total_seconds() + t
        T.insert(3, "dayInCulture", np.round((d - base) / 86400 * 1000) / 1000)
    return T


def _status_line(r, cur, nSl, base):
    """status of the last slice of a channel (first line of the subtitle of the course image)"""
    def dn(t):
        return (_EPOCH + _dt.timedelta(seconds=int(math.floor(t + 0.5)))).strftime("%d %b %H:%M")
    s = f"slice {cur['k']} since {dn(cur['start'])}"
    if not math.isnan(base):
        s += f" (day {int(math.floor(cur['start'] / 86400) - math.floor(base / 86400))})"
    s += f": {r['endStatus']}"
    if r["lastBeat"]:
        s += f"; last contraction {_dt.datetime.strptime(r['lastBeat'], _FMT):%d %b %H:%M}"
    la, lp = float(r["lastAmplitude"]), float(r["lastAmplitude_pctMax"])
    if np.isfinite(la):
        s += f", amplitude {la:.0f} µN"
        if np.isfinite(lp):
            s += f" ({lp:.0f} % of the maximum of the slice)"
    return s + f"; {nSl} slice(s), {len(cur['recs'])} recording(s) of the last slice"


def _window_amplitudes(W):
    """amplitude per 1-min window (W: tuples t_from, t_to, amplitude, nBeats, included; several rows of a window
    weighted by their number of contractions; included contractions, otherwise all)"""
    if not W:
        return np.array([]), np.array([])
    A = np.array([(w[0], w[2], w[3], float(w[4])) for w in W], float)
    tf, amp, nb, inc = A[:, 0], A[:, 1], A[:, 2], A[:, 3] > 0
    use = inc & (nb > 0) & ~np.isnan(amp)
    if not use.any():
        use = (nb > 0) & ~np.isnan(amp)
    if not use.any():
        return np.array([]), np.array([])
    w, g = np.unique(tf[use], return_inverse=True)
    a = np.bincount(g, weights=amp[use] * nb[use]) / np.bincount(g, weights=nb[use])
    return w, a


def _experiment_image(ov, en, OV, slices, R):
    """overview image of the experiment: series x channels (cells OV: series, channel, slices, recordings with red
    flags)"""
    from .report import experiment_image
    from .write_results import mda_version
    ser = sorted({x[0] for x in OV})
    chans = sorted({x[1] for x in OV})
    J = [j for x in OV for j in x[2]]
    t0, t1 = min(slices[j]["start"] for j in J), max(slices[j]["last"] for j in J)
    span = (t1 - t0) / 3600
    bm = 30 if span <= 30 else (60 if span <= 24 * 7 else 120)
    cells, nBeat = [], 0
    for sr, c, Jq, nRed in OV:
        t, y, sb, tw, aw = [], [], [], [], []
        for k, j in enumerate(Jq):
            cur = slices[j]
            if k > 0:
                sb.append((cur["start"] - t0) / 3600)
            w, a = _window_amplitudes(cur["W"])
            tw.append(w)
            aw.append(a)
            if not len(w):
                continue
            ub, g = np.unique(np.floor((w - t0) / 60 / bm), return_inverse=True)
            m = [float(np.median(a[g == q])) for q in range(len(ub))]
            if t:
                t.append(math.nan)
                y.append(math.nan)
            t += list((ub + 0.5) * bm / 60)
            y += m
        tw, aw = np.concatenate(tw) if tw else np.array([]), np.concatenate(aw) if aw else np.array([])
        r = R.iloc[Jq[-1]]
        d24 = math.nan
        u = tw >= t1 - 86400
        if u.any():
            ta, va = tw[u], aw[u]
            if ta.max() - ta.min() >= 4 * 3600:
                a = float(np.median(va[ta <= ta.min() + 7200]))
                b = float(np.median(va[ta >= ta.max() - 7200]))
                if a > 0:
                    d24 = 100 * (b - a) / a
        cells.append(dict(r=ser.index(sr), c=chans.index(c), t=np.array(t, float), y=np.array(y, float), sb=sb,
                          status=str(r["endStatus"]), k=int(slices[Jq[-1]]["k"]), amp=float(r["lastAmplitude"]),
                          pct=float(r["lastAmplitude_pctMax"]), d24=d24, nRed=nRed))
        nBeat += r["endStatus"] == "beating at end of data"

    def dn(x):
        return (_EPOCH + _dt.timedelta(seconds=int(math.floor(x + 0.5)))).strftime("%Y-%m-%d %H:%M")
    rep = os.path.basename(ov).replace("_overview.png", "_report.pdf")
    rep = rep.replace("mda_overview_root.png", "mda_report_root.pdf")
    D = dict(title=f"{en}  ·  {len(ser)} setup(s), {len(cells)} channel(s) with a slice: {nBeat} beating at the end of "
                   f"their data",
             subtitle=f"{dn(t0)} to {dn(t1)} ({span / 24:.1f} days); status of the last slice of each channel at the "
                      f"end of its data; made {_dt.datetime.now():%Y-%m-%d %H:%M} (MyoDishAnalysis {mda_version()})",
             rows=ser, cols=[int(c) for c in chans], t0=_EPOCH + _dt.timedelta(seconds=t0), xl=[0.0, max(span, 1.0)],
             last24=[max(0.0, span - 24), span], report=rep, cells=cells)
    experiment_image(ov, D)


def _delete_series_outputs(d, series):
    """images and workbook of a series in folder d (before they are written again, or in the other layout)"""
    if not os.path.isdir(d):
        return
    _delete_matching(d, "^" + re.escape(series) + r"_ch\d+\.png$")
    f = os.path.join(d, series + "_trends.xlsx")
    if os.path.isfile(f):
        os.remove(f)


def _delete_matching(d, rx):
    if not os.path.isdir(d):
        return
    for x in os.listdir(d):
        if x.endswith(".png") and re.search(rx, x):
            os.remove(os.path.join(d, x))


def _remove_empty(d):
    """folder d deleted if it is empty"""
    if os.path.isdir(d) and not os.listdir(d):
        os.rmdir(d)


def _slice_base(cur):
    """day 0 of the culture of a slice (s since 1970): cultureStart (label), otherwise 00:00 of idDate (not for slices
    inserted later); NaN if unknown"""
    lab = cur["lab"]
    if lab["cultureStart"] and not math.isnan(_seconds(lab["cultureStart"])):
        return _seconds(lab["cultureStart"])
    if lab["idDate"] and not cur["inserted"] and not math.isnan(_seconds(lab["idDate"])):
        return _seconds(lab["idDate"])
    return math.nan


def _new_slice_comment(*texts):
    """the first comment (gap comments, separated by ' | ') that says a new slice was mounted (RX_NEW_SLICE, and the
    slice named or nothing else that can be exchanged, see RX_NOT_SLICE); '' if none. Each comment once."""
    seen = []
    for t in texts:
        for c in re.split(r"\s*\|\s*", str(t)):
            c = c.strip()
            if c and c not in seen:
                seen.append(c)
    for c in seen:
        if RX_NEW_SLICE.search(c) and (RX_SLICE_WORD.search(c) or not RX_NOT_SLICE.search(c)):
            return c[:100]
    return ""


def _row(cur, hours):
    W = cur["W"]
    lastBeat = lastAmp = maxAmp = math.nan
    nBeats = 0.0
    if W:
        tf = np.array([w[0] for w in W])
        tt = np.array([w[1] for w in W])
        amp = np.array([w[2] for w in W])
        nb = np.array([w[3] for w in W])
        inc = np.array([w[4] for w in W])
        nBeats = float(np.nansum(nb))
        has = nb > 0
        if has.any():
            lastBeat = float(tt[has].max())
        use = inc & has & ~np.isnan(amp)
        if not use.any():
            use = has & ~np.isnan(amp)
        if use.any():
            wins = np.unique(tf[use])  # amplitude per window: mean of the rows (beat types) weighted by nBeats
            aw = np.array([np.sum(amp[use & (tf == x)] * nb[use & (tf == x)]) / np.sum(nb[use & (tf == x)])
                           for x in wins])
            lastAmp = float(aw[-1])
            maxAmp = _prctile(aw, 95)
    elif cur["fb"]:
        F = np.array(cur["fb"], dtype=float)
        if np.any(~np.isnan(F[:, 0])):
            j = int(np.nanargmax(F[:, 0]))
            lastBeat, lastAmp = float(F[j, 0]), float(F[j, 1])
        if np.any(~np.isnan(F[:, 2])):
            maxAmp = float(np.nanmax(F[:, 2]))
        nBeats = float(np.nansum(F[:, 3]))
    beating = (not math.isnan(lastBeat)) and cur["last"] - lastBeat <= 1800
    if cur["closed"]:
        status = cur["closed"]
    else:
        status = {"beating": "beating at end of data", "not beating": "not beating at end of data",
                  "signal lost": "signal lost", "removed": "removed"}.get(cur["endCand"], cur["endCand"])
    lab = cur["lab"]
    base, src = math.nan, ""
    if lab["cultureStart"] and not math.isnan(_seconds(lab["cultureStart"])):
        base, src = _seconds(lab["cultureStart"]), "cultureStart"
    elif lab["idDate"] and not cur["inserted"] and not math.isnan(_seconds(lab["idDate"])):
        base, src = _seconds(lab["idDate"]), "idDate"
    elif lab["idDate"]:
        src = "unknown (inserted later)"
    pct = 100 * lastAmp / maxAmp if maxAmp > 0 else math.nan
    cv = cur["cal"]  # calibration values of the slice in the order of time (2026-10-10)
    cal = ";".join(x for i, x in enumerate(cv) if i == 0 or x != cv[i - 1])
    calChanged = int(len(set(cv)) > 1)
    return [cur["e"], cur["series"], cur["c"], cur["k"], lab["setupID"], lab["sampleID"], lab["species"],
            lab["sliceID"], lab["idDate"], _clock(cur["start"]), _clock(cur["last"]),
            (cur["last"] - cur["start"]) / 86400, cur["reason"], int(cur["inserted"]), status, int(beating),
            _clock(lastBeat), lastAmp, maxAmp, pct, nBeats,
            (cur["start"] - base) / 86400 if src in ("cultureStart", "idDate") else math.nan,
            (cur["last"] - base) / 86400 if src in ("cultureStart", "idDate") else math.nan, src,
            len(cur["recs"]), cur["recs"][0] if cur["recs"] else "", cur["recs"][-1] if cur["recs"] else "",
            cur["nOut"], cur["outSec"] / 3600, cur["longest"] / 60, cur["nPutBack"], cur["nTech"], cal, calChanged,
            cur["endComments"]]
