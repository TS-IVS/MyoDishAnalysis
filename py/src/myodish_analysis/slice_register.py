# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Slice register: one row per slice (channel of a setup from putting the slice in until it was taken out, the signal
was lost or the data end), built from the results of the watcher. Port of mda_sliceRegister.m.

    R = slice_register(results_folder)                       all experiments; writes the register files
    R = slice_register(results_folder, experiments=["expA"]) only these experiments (subfolders of results_folder)
    R = slice_register(..., new_slice_hours=2.0, write=True)

Experiment = subfolder of the results folder (= subfolder of the raw folder). Series = recordings of one setup: the
file name up to its number (rigA_X_0, rigA_X_1, ... --> series rigA_X); channels are followed through the
recordings of a series in the order of their start.
Inputs per recording (watcher, gaps=True): <name>_channels.csv (required), <name>_gaps.csv, <name>_overview.csv.

A new slice begins in a channel
  - with its first signal ('first signal'),
  - after a chamber-out period with a comment such as 'new slice', 'replaced', 'exchanged', 'getauscht' within 5 min
    of its start or end ('comment: ...'),
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

TS 2026-10-08 (calibration 2026-10-10)
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


def slice_register(results_folder, experiments=None, new_slice_hours=2.0, write=True):
    res = os.path.abspath(results_folder)
    found = _experiments(res)
    todo = sorted(found) if experiments is None else [e for e in sorted(found) if e in set(experiments)]
    out = {}
    for e in todo:
        R = _experiment(res, e, found[e], float(new_slice_hours))
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
def _experiments(res):
    """experiment (subfolder, '/' separated, '' = results folder) --> names of the <name>_channels.csv files."""
    found = {}
    for p, dirs, files in os.walk(res):
        dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d != "reports")
        for fn in sorted(files):
            if fn.endswith("_channels.csv") and not fn.startswith("."):
                rel = os.path.relpath(p, res).replace(os.sep, "/")
                found.setdefault("" if rel == "." else rel, []).append(fn[:-len("_channels.csv")])
    return found


def _file(res, e):
    if not e:
        return os.path.join(res, ROOT_NAME)
    return os.path.join(res, *e.split("/"), e.split("/")[-1] + "_slices.csv")


def _read(f):
    """all columns as text ('' for empty); numbers converted by the callers."""
    return pd.read_csv(f, dtype=str, keep_default_na=False)


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


def _experiment(res, e, names, hours):
    folder = os.path.join(res, *e.split("/")) if e else res
    recs = []
    for n in names:
        CH = _read(os.path.join(folder, n + "_channels.csv"))
        if not len(CH):
            continue
        G = _read(os.path.join(folder, n + "_gaps.csv")) if os.path.isfile(os.path.join(folder, n + "_gaps.csv")) \
            else None
        fo = os.path.join(folder, n + "_overview.csv")
        O = _read(fo) if os.path.isfile(fo) else None
        name = _txt(CH, "recording")[0] or n
        series, num = _series(name)
        recs.append(dict(name=name, series=series, num=num, start=_seconds(_txt(CH, "recordingStart")[0]),
                         L=float(_num(CH, "fileLength_s")[0]), CH=CH, G=G, O=O))
    # order: series, start (unknown start: after the known ones), number, name
    recs.sort(key=lambda r: (r["series"], math.isnan(r["start"]), 0 if math.isnan(r["start"]) else r["start"],
                             math.inf if math.isnan(r["num"]) else r["num"], r["name"]))
    rows = []
    for series in sorted(set(r["series"] for r in recs)):
        S = [r for r in recs if r["series"] == series]
        prevEnd = math.nan
        for r in S:  # unknown start: end of the previous recording of the series
            if math.isnan(r["start"]):
                r["start"] = prevEnd if not math.isnan(prevEnd) else 0.0
            prevEnd = r["start"] + (r["L"] if not math.isnan(r["L"]) else 0.0)
        chans = sorted(set(float(c) for r in S for c in _num(r["CH"], "channel")))
        for c in chans:
            rows += _channel(e, series, c, S, hours)
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
    return R


def _new(e, series, c, k, t, reason, row, seriesStart, hours):
    lab = {nm: row[nm] for nm in ("setupID", "sampleID", "species", "sliceID", "idDate", "cultureStart")}
    inserted = reason != "first signal" or t - seriesStart > hours * 3600
    return dict(e=e, series=series, c=c, k=k, start=t, reason=reason, inserted=inserted, lab=lab, last=t,
                recs=[], nOut=0, outSec=0.0, longest=0.0, nTech=0.0, nPutBack=0, W=[], fb=[], endCand="",
                endComments="", closed="", cal=[])


def _channel(e, series, c, S, hours):
    rows = []
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
                    m = RX_NEW_SLICE.search(txt)
                    long_ = emptyBetween or dur >= hours * 3600
                    if m:
                        reason = "comment: " + _snippet(txt, m)
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
    return rows


def _snippet(txt, m):
    a = max(0, m.start() - 40)
    return txt[a:m.end() + 40].strip()


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
