# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Stimulation protocols of a MyoDish recording and grouping of the contractions by a stimulation quantity.
Port of mda_protocols.m and mda_groupBeats.m.

    P = find_protocols(mdd_file)          protocols found from the comments of the log file (or H, or the log file)
    B, G = group_beats(H, B, C, range_, by, opts)    contractions of one channel and range grouped by 'by';
                                                      summary per group

find_protocols: protocols are marked by pairs of comments such as 'start FFR protocol' ... 'end FFR protocol',
'start of refractory period protocol' ... 'end of refractory period protocol' or 'FFR protocol started' ... 'FFR
protocol ended'. A start is paired with the next end of the same name (otherwise of the same type). A start without an
end lasts until the next protocol of the same type or the end of the file (note 'no end comment'). Protocols within a
protocol of the same type are not listed separately; a start comment repeated within 10 s counts once. A gap of > 10
min between the log entries within a protocol is noted ('gap of 23.5 h in the log': schedule stalled). Comments about
the recording itself and about schedule files ('start scheduleFile_humanVentricle') are ignored. Schedule files loaded by a schedule (log events 'Loaded schedule
file <path>' ... 'Jumped back from loaded schedule file <path>') are protocols, too, if their file name contains a
protocol keyword (e.g. PD_Test_12Steps.txt) and not 'schedule'; name = file name without extension.
P: DataFrame, one row per protocol: type, name, number (k-th protocol of this type), from, to (s), groupBy (default
quantity), startComment, endComment, note.
Types (keywords in the name) and default grouping: FFR (FFR, force-frequency, frequency): pacingFrequency;
RP (refractory, RP, S1S2, S2): S2interval; ST (threshold, stimCurrent, ST): stimCurrent; PRP (post rest, PRP, rest
potentiation): pauseLength; PD (pulse duration, PD): pulseDuration; rockerSpeed (rocker speed): rockerSpeed;
other: none. FFR, RP, ST, PRP, PD also as separate words or parts of a CamelCase / underscore name ('PD_Test').

group_beats: see the help of mda_groupBeats.m (same quantities, groups, columns; return_stimuli=True: also Z, the
stimuli of the channel with role, value and capture, input of protocol_results):
  pacingFrequency, S2interval, stimCurrent, pauseLength, rockerSpeed, pulseDuration, 'log:<code>'. Extra pulses (status
  channel bit 16) are no stimuli of the protocol; an extra pulse belongs to the group of the nearest regular pulse, a
  contraction elicited by it to the group of the last regular pulse at or before it, an extra beat to the group of
  the last regular pulse at or before its onset. pacingFrequency: groups = frequencies rounded to
  opts.frequencyResolution (0.1 Hz; below 1 Hz frequencyResolutionLow, 0.05 Hz); pauseLength: pauses within opts.pauseTolerance (10 %) of the
  shortest pause of a set have the same pause length.

steady_n (FFR protocols: opts.steadyStateBeats): steady state per frequency (the last steady_n contractions of the
longest run, within it of the longest sequence of consecutive captured stimuli with captured neighbours; rocker at rest
if any, see ffrRockerFallback); pauseLength: reference of each pause (prpReference); amplitude_CV, irregular;
return_notes=True: also the notes (2026-10-10).

TS 2026-10-07 (port of mda_protocols.m and mda_groupBeats.m; schedule files 2026-10-07; uncertain contractions
2026-10-09; extra pulses, frequency / pause tolerances, FFR steady state, PRP reference, irregular groups 2026-10-10)
"""
from __future__ import annotations

import math
import re

import numpy as np
import pandas as pd

from ._matlab import Struct, mround
from .log_entries import log_entries, sscanf_floats, str2double
from .summarize import summarize

_START1 = re.compile(r"^(?:start(?:ing)?|begin(?:ning)?)\s+(?:of\s+)?(?:the\s+)?(.+?)\s*$", re.I)
_START2 = re.compile(r"^(.+?)\s+(?:started|starts|begins)\s*$", re.I)
_END1 = re.compile(r"^(?:end(?:ed)?|stop(?:ped)?|finish(?:ed)?)\s+(?:of\s+)?(?:the\s+)?(.+?)\s*$", re.I)
_END2 = re.compile(r"^(.+?)\s+(?:ended|ends|end|stopped|finished|done)\s*$", re.I)
COLUMNS = ["type", "name", "number", "from", "to", "groupBy", "startComment", "endComment", "note"]
GROUP_BY = ["pacingFrequency", "S2interval", "stimCurrent", "pauseLength", "rockerSpeed", "pulseDuration"]


def _parse_comment(txt):
    if "recording" in txt.lower():  # 'Started parallel recording: ...'
        return "", ""
    for kind, rx in (("start", _START1), ("start", _START2), ("end", _END1), ("end", _END2)):
        m = rx.match(txt)
        if m:
            return kind, m.group(1)
    return "", ""


_LOADED = re.compile(r"^Loaded schedule file\s+(.+?)\s*$", re.I)
_JUMPED = re.compile(r"^Jumped back from loaded schedule file\s*(.*?)\s*$", re.I)
_WORDS = re.compile(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+")


def _parse_schedule_event(txt):
    """'Loaded schedule file C:\\...\\PD_Test.txt' / 'Jumped back from loaded schedule file C:\\...\\PD_Test.txt.'"""
    m = _LOADED.match(txt)
    kind = "start"
    if not m:
        m = _JUMPED.match(txt)
        kind = "end"
        if not m:
            return "", ""
    p = re.sub(r"\.+$", "", m.group(1).replace("\\", "/"))
    p = p.rsplit("/", 1)[-1]
    return kind, re.sub(r"\.[A-Za-z0-9]{1,4}$", "", p)


def _norm_name(name):
    key = name.lower().replace("protocol", "")
    return re.sub(r"[^a-z0-9]", "", key)


def protocol_type(name):
    """protocol type from the name (keywords; FFR, RP, ST, PRP, PD also as words: 'PD_Test' -> PD)"""
    key = _norm_name(name)
    tok = [w.lower() for w in _WORDS.findall(str(name))]
    if re.search(r"postrest|prp|restpotentiation", key):
        return "PRP"
    if re.search(r"refractory|^rp|s1s2|^s2", key) or "rp" in tok:
        return "RP"
    if re.search(r"threshold|stimcurrent|^st$|^st[^a-z]", key) or "st" in tok:
        return "ST"
    if re.search(r"pulseduration|^pd$|^pd[^a-z]", key) or "pd" in tok:
        return "PD"
    if re.search(r"rockerspeed", key):
        return "rockerSpeed"
    if re.search(r"ffr|forcefrequency|frequency", key) or "ffr" in tok:
        return "FFR"
    return "other"


def default_group_by(typ):
    return {"FFR": "pacingFrequency", "RP": "S2interval", "ST": "stimCurrent", "PRP": "pauseLength",
            "PD": "pulseDuration", "rockerSpeed": "rockerSpeed"}.get(typ, "none")


def find_protocols(src, regular_minutes=5.0):
    H = None
    if isinstance(src, dict):
        H = src
        logFile, T = src["logFile"], src["totalSeconds"]
    elif str(src).lower().endswith(".mdd"):
        from .read_mdd import read_mdd
        H = read_mdd(str(src))
        logFile, T = H.logFile, H.totalSeconds
    else:
        logFile, T = str(src), math.inf
    E = log_entries(logFile)
    tAll = np.sort(E["t_file"].to_numpy(float)) if len(E) else np.zeros(0)
    tAll = tAll[np.isfinite(tAll)]  # all log entries (gaps within a protocol)
    isSched = np.array([str(c).lower() == "schedule" for c in E["code"]], dtype=bool)
    E = E[(E["isComment"].to_numpy(bool) | isSched) & np.isfinite(E["t_file"].to_numpy(float))]
    E = E.sort_values("t_file", kind="stable")
    st = []
    open_ = []
    sched = []  # names of the loaded schedule files (nested)
    for txt, tf, isC in zip(E["text"], E["t_file"], E["isComment"]):
        txt = str(txt).strip()
        if isC:
            kind, name = _parse_comment(txt)
            if not kind:
                continue
        else:
            kind, name = _parse_schedule_event(txt)
            if not kind:
                continue
            if kind == "start":
                sched.append(name)
            else:  # 'Jumped back from loaded schedule file.' (older logs): the last one
                js = [j for j, x in enumerate(sched) if x == name]
                if not name or not js:
                    js = [len(sched) - 1]
                if js[-1] < 0:
                    continue
                name = sched.pop(js[-1])
            txt = ("Loaded schedule file " if kind == "start" else "Jumped back from loaded schedule file ") + name
        if "schedule" in name.lower():  # the schedule file itself
            continue
        key = _norm_name(name)
        typ = protocol_type(name)
        if not isC and typ == "other":  # schedule files without protocol keyword
            continue
        if kind == "start":
            st.append(dict(type=typ, name=name, key=key, start=float(tf), to=math.nan, startComment=txt,
                           endComment="", note=""))
            open_.append(len(st) - 1)
        else:
            js = [j for j, i in enumerate(open_) if st[i]["key"] == key]
            if not js and typ != "other":
                js = [j for j, i in enumerate(open_) if st[i]["type"] == typ]
            if not js:
                continue  # end without start: ignored
            j = js[-1]
            st[open_[j]]["to"] = float(tf)
            st[open_[j]]["endComment"] = txt
            del open_[j]
    # starts without end within a protocol of the same type: not listed separately
    drop = [math.isnan(s["to"]) and any(x["type"] == s["type"] and not math.isnan(x["to"]) and x["start"] <= s["start"]
                                        < x["to"] for x in st) for s in st]
    st = [s for s, d in zip(st, drop) if not d]
    # a start followed by another start of the same type within 10 s is a repeated comment and dropped
    drop = [False] * len(st)
    for i, s in enumerate(st):
        if math.isnan(s["to"]):
            nxt = [x["start"] for x in st[i + 1:] if x["type"] == s["type"]]
            drop[i] = bool(nxt) and nxt[0] - s["start"] < 10
    st = [s for s, d in zip(st, drop) if not d]
    # other starts without end: end estimated (2026-10-10) = start of regular pacing (> regular_minutes with the same
    # stimulus interval, current and pulse duration, after a change within the protocol), otherwise the start of the
    # next protocol (any type) or the end of the file; note 'no end comment: end estimated ...'
    for i, s in enumerate(st):
        if math.isnan(s["to"]):
            later = [x for x in st if x["start"] > s["start"]]
            nxt = min(later, key=lambda x: x["start"]) if later else None
            tLimit = nxt["start"] if nxt else T
            why = f"start of the next protocol '{nxt['name']}'" if nxt else "end of the file"
            tEnd = tLimit
            if H is not None and regular_minutes and regular_minutes > 0:
                r = regular_pacing_start(H, s["start"], tLimit, 60.0 * float(regular_minutes))
                if r is not None:
                    tEnd, why = r
            s["to"] = tEnd
            s["note"] = f"no end comment: end estimated at {_g(tEnd)} s ({why})"
    # protocols within a protocol of the same type are not listed separately
    keep = [True] * len(st)
    for i in range(len(st)):
        for j in range(len(st)):
            a, b = st[i], st[j]
            if i != j and keep[j] and a["type"] == b["type"] and a["start"] >= b["start"] and a["to"] <= b["to"] and \
                    (a["start"] > b["start"] or a["to"] < b["to"] or i > j):
                keep[i] = False
    st = [s for s, k in zip(st, keep) if k]
    # a gap of > 10 min between the log entries within a protocol (e.g. the schedule stalled and the remaining
    # commands were sent later at once): note
    for s in st:
        if not math.isfinite(s["to"]):
            continue
        g = float(np.max(np.diff(np.r_[s["start"], tAll[(tAll > s["start"]) & (tAll < s["to"])], s["to"]])))
        if g > 600:
            gs = "%.1f h" % (math.floor(g / 360) / 10) if g >= 3600 else "%d min" % math.floor(g / 60)
            s["note"] = "; ".join(x for x in (s["note"], f"gap of {gs} in the log") if x)
    rows = []
    for i, s in enumerate(st):
        number = sum(1 for x in st[:i + 1] if x["type"] == s["type"])
        rows.append([s["type"], s["name"], float(number), s["start"], s["to"], default_group_by(s["type"]),
                     s["startComment"], s["endComment"], s["note"]])
    P = pd.DataFrame(rows, columns=COLUMNS)
    if len(P) == 0:
        P = P.astype({"number": float, "from": float, "to": float})
    return P


def regular_pacing_start(H, t0, tLimit, minDur=300.0):
    """start of regular pacing after t0 (end of a protocol without end comment, see mda_protocols.m): per stimulated
    channel the first run of stimuli that starts after t0 and before tLimit and lasts > minDur + one interval with the
    same interval (+-max(5 ms, 2 %)), current and pulse duration (log 'chargeDuration'); a pulse < 50 ms after the
    previous pulse of the channel is no pacing stimulus (status channel errors). Returns (lower median of the run starts
    over the channels with such a run, reason text) or None. TS 2026-10-10"""
    from .read_mdd import read_data
    T = float(H.totalSeconds)
    b = min(T, float(tLimit) + minDur + 60.0)
    if not H.get("hasStimChannel", False) or b <= t0:
        return None
    tt, ch, cur = [], [], []
    a = max(0.0, float(t0) - 120.0)  # from before the start: pacing that continues into the protocol is no new run
    while a < b:
        e = min(b, a + 3600.0)
        S = read_data(H, a, e, 2, stim_only=True)
        k = (S.stim.time >= a) & (S.stim.time < e)  # chunk boundaries: no pulse twice
        if "isExtraPulse" in S.stim:
            k &= ~np.asarray(S.stim.isExtraPulse, bool)  # extra pulses: no pacing (2026-10-10)
        tt.append(S.stim.time[k]); ch.append(S.stim.channel[k]); cur.append(S.stim.current[k])
        a = e
    tt, ch, cur = np.concatenate(tt), np.concatenate(ch), np.concatenate(cur)
    E = log_entries(H.logFile)
    starts = []
    for c in np.unique(ch):
        k = np.flatnonzero(ch == c)
        t, I = tt[k], cur[k]
        keep = np.r_[True, np.diff(t) >= 0.05]
        t, I = t[keep], I[keep]
        ep = np.searchsorted(_pulse_duration_changes(E, c), t, side="right")  # pulse duration epoch of every pulse
        n = t.size
        i = 0
        while i < n - 1:
            isi0 = t[i + 1] - t[i]
            tol = max(0.005, 0.02 * isi0)
            j = i + 1
            while (j + 1 < n and abs(t[j + 1] - t[j] - isi0) <= tol and I[j + 1] == I[i] and I[j] == I[i]
                   and ep[j + 1] == ep[i] and ep[j] == ep[i]):
                j += 1
            if t[i] > t0 and t[i] < tLimit and I[j] == I[i] and ep[j] == ep[i] and t[j] - t[i] > minDur + isi0:
                starts.append((float(t[i]), float(isi0), float(I[i])))
                break
            if t[i] >= tLimit:
                break
            i = j
    if not starts:
        return None
    starts.sort()
    s, isi, I = starts[(len(starts) - 1) // 2]
    return s, "start of regular pacing: %.3g Hz, %g mA, > %g min" % (1.0 / isi, I, minDur / 60.0)


def _pulse_duration_changes(E, c):
    """times (s, time in the file) at which the pulse duration of channel c changes (log 'chargeDuration' of channel c or
    0 with another value than the entry before)"""
    if E is None or len(E) == 0:
        return np.zeros(0)
    codes = E["code"].astype(str).str.lower().to_numpy()
    chs = E["channel"].to_numpy(float)
    tf = E["t_file"].to_numpy(float)
    k = np.flatnonzero((codes == "chargeduration") & ((chs == c) | (chs == 0)) & np.isfinite(tf))
    if k.size < 2:
        return np.zeros(0)
    k = k[np.argsort(tf[k], kind="stable")]
    v = np.array([str2double(x) for x in E["text"].to_numpy()[k]])
    chg = np.flatnonzero(v[1:] != v[:-1]) + 1
    return np.sort(tf[k[chg]])


def _g(x):
    """MATLAB sprintf('%g', x) (Inf, NaN)"""
    if math.isnan(x):
        return "NaN"
    if math.isinf(x):
        return "Inf" if x > 0 else "-Inf"
    return "%g" % x


# =====================================================================================================
def group_beats(H, B, C, range_, by, opts=None, return_stimuli=False, steady_n=0, return_notes=False):
    from .options import options as make_options
    from .read_mdd import read_mdd
    if opts is None:
        opts = make_options()
    steadyN = int(steady_n or 0)
    notes = []
    ffrFallback = bool(opts.get("ffrRockerFallback", True))  # options of older versions: defaults
    prpRef = opts.get("prpReference", "steady")
    prpN = int(opts.get("prpReferenceBeats", 6))
    irrCV = float(opts.get("irregularCV", 0.15))
    minGB = int(opts.get("minGroupBeats", 5))
    rockerSel = opts.get("rocker", "any")
    beatsSel = opts.get("beats", "all")
    by = str(by)
    byl = by.lower()
    r0, r1 = float(range_[0]), float(range_[1])

    # stimuli of the channel (with the 300 s before)
    S = read_mdd(H, max(0.0, r0 - 300), min(H.totalSeconds, r1 + 1), opts)
    stimCh = C.stimChannel
    isX = np.zeros(np.size(S.stim.channel), bool)  # extra pulses (status channel bit 16) are no stimuli of the
    if "isExtraPulse" in S.stim and stimCh > 0 and opts.get("stimAssignment", "onset") != "peak":  # protocol
        isX = np.asarray(S.stim.isExtraPulse, bool)  # (option stimAssignment 'peak': as before)
    idx = np.flatnonzero((S.stim.channel == stimCh) & ~isX)
    o = np.argsort(S.stim.time[idx], kind="stable")
    idx = idx[o]
    tt = S.stim.time[idx]
    cur = S.stim.current[idx]
    reached = S.stim.currentReached[idx]
    nS = tt.size
    prevInt = np.r_[np.nan, np.diff(tt)][:nS]  # no stimuli (channel not paced): empty
    nextInt = np.r_[np.diff(tt), np.nan][:nS]

    # value and role of every stimulus
    val = np.full(nS, np.nan)
    step = np.full(nS, np.nan)  # pauseLength: number of the pause
    role = np.array([""] * nS, dtype=object)
    refRole = ""
    runId = np.zeros(nS, int)
    steadyCL = math.nan
    if byl == "pacingfrequency":  # one group per rounded frequency (frequencyResolution, 2026-10-10)
        val = _round_frequency(1.0 / _group_median(prevInt, _cluster_values(prevInt, 0.0, 0.02)),
                               float(opts.get("frequencyResolution", 0.1)),
                               float(opts.get("frequencyResolutionLow", 0.05)))
        # runs of consecutive stimuli at the same frequency; step = number of the run of this frequency (steady state)
        runId = np.cumsum(np.r_[True, ~(val[1:] == val[:-1])])[:nS]
        if steadyN > 0:
            for v in np.unique(val[~np.isnan(val)]):
                r = list(dict.fromkeys(runId[val == v].tolist()))
                for q, x in enumerate(r):
                    step[runId == x] = q + 1
    elif byl == "s2interval":
        with np.errstate(invalid="ignore"):
            premature = (prevInt < 0.95 * np.r_[np.nan, prevInt[:-1]]) & (np.isnan(nextInt) | (nextInt > 1.05 * prevInt))
        isS2 = premature & ~np.r_[False, premature[:-1]]
        role[:] = "S1"
        role[isS2] = "S2"
        post = np.r_[False, isS2[:-1]][:nS]
        role[post] = "postS2"
        cand = ~isS2 & ~post  # S1 = basic interval; other intervals: 'other'
        inR = (tt >= r0) & (tt <= r1)
        p = prevInt[cand & inR]
        base = float(np.median(p[~np.isnan(p)])) if np.any(~np.isnan(p)) else math.nan
        with np.errstate(invalid="ignore"):
            role[cand & (np.abs(prevInt - base) > 0.05 * base)] = "other"
        role[(role == "S1") & np.r_[isS2[1:], False][:nS]] = "preS2"  # relaxation cut off by the S2
        s2 = np.full(nS, np.nan)
        s2[isS2] = prevInt[isS2]
        v2 = _group_median(s2, _cluster_values(s2, 0.0075, 0.0))
        val[isS2] = v2[isS2]
        ip = np.flatnonzero(post)
        val[ip] = v2[ip - 1]
        refRole = "S1"
    elif byl == "stimcurrent":
        val = cur.astype(float)
    elif byl == "pauselength":
        inR = (tt >= r0) & (tt <= r1)
        p = prevInt[inR]
        steadyCL = float(np.median(p[~np.isnan(p)])) if np.any(~np.isnan(p)) else math.nan
        before = np.r_[np.nan, prevInt[:-1]][:nS]
        # pause: the interval before is known and >= 1.5 x shorter (not the 2nd interval after a pause), and the
        # steady interval returns within the next 3 stimuli (not a change to a lower rate, e.g. at the end)
        with np.errstate(invalid="ignore"):
            steady = np.abs(prevInt - steadyCL) <= 0.05 * steadyCL
            rest = (prevInt >= np.fmax(1.5, 1.5 * steadyCL)) & (prevInt >= 1.5 * before)
        for r in np.flatnonzero(rest):
            nx = steady[r + 1:min(r + 4, nS)]
            rest[r] = nx.size == 0 or bool(nx.any())
        after = np.zeros(nS, bool)  # potentiation decays: not part of the steady reference
        for r in np.flatnonzero(rest):
            after |= (tt > tt[r]) & (tt <= tt[r] + 10)
        role[:] = "other"
        role[steady] = "steady"
        role[after] = "afterRest"
        role[rest] = "postRest"
        val[rest] = prevInt[rest]
        pz = np.full(nS, np.nan)  # pauses within pauseTolerance: one pause length (2026-10-10)
        pz[rest] = prevInt[rest] - (steadyCL if not math.isnan(steadyCL) else 0.0)
        v2 = _group_median(prevInt, _cluster_anchored(pz, float(opts.get("pauseTolerance", 0.1))))
        val[rest] = np.array([mround(x * 1000) for x in v2[rest]]) / 1000  # (ms: labels without rounding noise)
        sr = rest & inR
        step[sr] = np.arange(1, int(sr.sum()) + 1)
        refRole = "steady"
    elif byl == "rockerspeed":
        val = _rocker_speed_at(H, tt, float(opts.rockerLogDelay))
    elif byl == "pulseduration":
        val = _log_value_at(H, "chargeDuration", stimCh, tt) / 1000.0
    elif byl.startswith("log:"):
        val = _log_value_at(H, by[4:].strip(), stimCh, tt)
    else:
        raise ValueError(f"group_beats: unknown quantity '{by}'.")
    lbl = _group_labels(byl, val, role, by)
    if byl == "pauselength":  # one group per pause: equal labels get the pause number
        ir = np.flatnonzero(~np.isnan(step))
        if ir.size:
            u, cnt = np.unique(lbl[ir], return_counts=True)
            dupl = set(u[cnt > 1])
            for i in ir:
                if lbl[i] in dupl:
                    lbl[i] = "%s #%d" % (lbl[i], int(step[i]))

    # group of every contraction
    B = B.copy()
    nB = len(B)
    tStim = B["t_stim"].to_numpy(float)
    tPeak = B["t_peak"].to_numpy(float)
    # stimulus of every contraction: first stimulus with t == t_stim, without t_stim the last stimulus <= t_peak -
    # minStimToPeak (lookups instead of a search over all stimuli per contraction: long protocols, 2026-10-10)
    # (2026-10-10: contraction elicited by an extra pulse: the last regular pulse at or before it; extra beat: the last
    # regular pulse at or before the onset, if known)
    k = _first_index(tt, tStim)
    noStim = np.isnan(tStim) | (k < 0)
    if noStim.any():
        hasOn = "t_onset" in B.columns and opts.get("stimAssignment", "onset") != "peak"
        tOn = B["t_onset"].to_numpy(float) if hasOn else np.full(nB, np.nan)
        x = np.where(~np.isnan(tStim), tStim, np.where(~np.isnan(tOn), tOn, tPeak - opts.minStimToPeak))[noStim]
        if np.all(np.diff(tt) >= 0):
            k[noStim] = np.searchsorted(tt, x, side="right") - 1  # -1: none
        else:
            k[noStim] = [int(np.flatnonzero(tt <= v)[-1]) if np.any(tt <= v) else -1 for v in x]
    has = k >= 0
    bVal = np.full(nB, np.nan)
    bRole = np.array([""] * nB, dtype=object)
    bLbl = np.array(["unknown"] * nB, dtype=object)
    bStep = np.full(nB, np.nan)
    bStep[has] = step[k[has]]
    bVal[has] = val[k[has]]
    bRole[has] = role[k[has]]
    bLbl[has] = lbl[k[has]]
    if byl == "rockerspeed":  # rocker speed at the peak
        bVal = _rocker_speed_at(H, tPeak, float(opts.rockerLogDelay))
        bLbl = _group_labels("rockerspeed", bVal, np.array([""] * nB, dtype=object), by)
    B["group"] = list(bLbl)
    B["groupValue"] = bVal
    B["groupRole"] = list(bRole)
    B["groupStep"] = bStep

    # FFR: steady state per frequency (2026-10-10)
    selStep = {}
    if byl == "pacingfrequency" and steadyN > 0 and nB > 0 and nS > 0:
        amp = B["amplitude"].to_numpy(float)
        eligible = ~np.isnan(amp)
        stim = B["beatType"].to_numpy() == "stimulated"
        if beatsSel == "stimulated":
            eligible &= stim
        moving = B["rockerMoving"].to_numpy(bool)
        inc = B["included"].to_numpy(bool).copy()
        inRs = (tt >= r0) & (tt <= r1)
        # captured stimuli: followed by their stimulated contraction (any rocker state). Within the longest run, only
        # captured stimuli whose previous and next stimulus are captured, too, count (preceding and following interval
        # of the contraction = stimulus intervals), and of these the longest sequence of consecutive stimuli: partial
        # capture (e.g. 2:1) is no steady state at this frequency (2026-10-10)
        capt = np.zeros(nS, bool)
        okC = has & stim & ~np.isnan(amp)
        capt[k[okC]] = True
        okS = capt & np.r_[False, capt[:-1]] & np.r_[capt[1:], True]
        fb = []
        nc = []
        for key in list(dict.fromkeys(bLbl[has].tolist())):
            rowsG = bLbl == key
            js = np.flatnonzero(inRs & (lbl == key))
            if js.size == 0 or math.isnan(val[js[0]]):
                continue
            ru = runId[js]
            u, cnt = np.unique(ru, return_counts=True)
            rSel = u[np.flatnonzero(cnt == cnt.max())[-1]]  # longest run (equal length: the later one)
            jRun = np.flatnonzero(runId == rSel)
            jOk = jRun[okS[jRun]]
            if jOk.size == 0:
                nc.append(key)
            else:
                sub = np.cumsum(np.r_[1, np.diff(jOk) != 1])
                cs = np.bincount(sub)
                jOk = jOk[sub == np.flatnonzero(cs == cs.max())[-1]]
            cand = rowsG & has & eligible & np.isin(k, jOk)
            if rockerSel == "stopped":
                use = cand & ~moving
                if not use.any() and cand.any() and ffrFallback:
                    use = cand
                    fb.append(key)
            elif rockerSel == "moving":
                use = cand & moving
            else:
                use = cand
            iu = np.flatnonzero(use)
            iu = iu[np.argsort(tPeak[iu], kind="stable")]
            iu = iu[max(0, iu.size - steadyN):]
            inc[rowsG] = False
            inc[iu] = True
            selStep[key] = float(step[np.flatnonzero(runId == rSel)[0]])
        B["included"] = inc
        if fb:
            notes.append("no contraction with the rocker at rest at %s: contractions with the rocker moving used"
                         % ", ".join(fb))
        if nc:
            notes.append("no run of captured stimuli at %s (missed beats): no steady-state contractions" % ", ".join(nc))

    # summary per group
    inR = (tt >= r0) & (tt <= r1)
    Cst = np.asarray(C.stimTimes, dtype=float)
    Ccap = np.asarray(C.stimCaptured, dtype=bool)
    Ccc = np.asarray(C.get("stimCapturedCertain", C.stimCaptured), dtype=bool)
    captured = np.zeros(nS, bool)
    capturedCertain = np.zeros(nS, bool)  # followed by a certain contraction (option detection)
    jC = _first_index(Cst, tt)  # first stimulus of the channel with the same time (ismember)
    hasC = jC >= 0
    captured[hasC] = Ccap[jC[hasC]]
    capturedCertain[hasC] = Ccc[jC[hasC]]
    duringC = np.zeros(nS, bool)  # within a contraction elicited by another pulse
    Cdc = C.get("stimDuringContraction")
    if Cdc is not None and np.size(Cdc) == Cst.size:
        duringC[hasC] = np.asarray(Cdc, bool)[jC[hasC]]
    # extra pulses of the range: group of the nearest regular pulse (pre-pulse: the next one, CCM pulse: the previous
    # one)
    xT = np.zeros(0)
    xE = np.zeros(0, bool)
    xLbl = np.array([], dtype=object)
    if C.get("extraTimes") is not None and np.size(C.extraTimes) and nS > 0:
        xT = np.asarray(C.extraTimes, float).ravel()
        xE = np.zeros(xT.size, bool)
        if C.get("extraElicited") is not None and np.size(C.extraElicited) == xT.size:
            xE = np.asarray(C.extraElicited, bool).ravel()
        keepX = (xT >= r0) & (xT <= r1)
        xT = xT[keepX]
        xE = xE[keepX]
        xLbl = np.array([lbl[int(np.argmin(np.abs(tt - x)))] for x in xT], dtype=object)
    inRb = (tPeak >= r0) & (tPeak <= r1)
    keys = []
    for x in list(lbl[inR]) + list(bLbl[inRb]):
        if x not in keys:
            keys.append(x)
    roleOrder = ["", "S1", "preS2", "S2", "postS2", "steady", "afterRest", "postRest", "other"]
    kr, kv, ks = [], [], []
    for key in keys:
        j = np.flatnonzero(lbl == key)
        if j.size:
            kr.append(roleOrder.index(role[j[0]]))
            kv.append(val[j[0]])
            ks.append(step[j[0]])
        else:
            j = np.flatnonzero(bLbl == key)
            kr.append(roleOrder.index(bRole[j[0]]))
            kv.append(bVal[j[0]])
            ks.append(bStep[j[0]])
    kv2 = [math.inf if math.isnan(v) else v for v in kv]
    ks2 = [math.inf if math.isnan(v) else v for v in ks]
    order = sorted(range(len(keys)), key=lambda q: (kr[q], kv2[q], ks2[q]))
    parts = []
    for q in order:
        js = inR & (lbl == keys[q])
        Cg = Struct(dict(C))
        Cg.stimTimes = tt[js]
        Cg.stimCaptured = captured[js]
        Cg.stimCapturedCertain = capturedCertain[js]
        Cg.stimDuringContraction = duringC[js]
        Cg.extraTimes = xT[xLbl == keys[q]] if xT.size else np.zeros(0)
        Cg.extraElicited = xE[xLbl == keys[q]] if xT.size else np.zeros(0, bool)
        Bg = B[B["group"].to_numpy() == keys[q]]
        T = summarize(Bg, Cg, [r0, r1])
        pj = prevInt[js]
        pj = pj[~np.isnan(pj)]
        T["stimFrequency"] = 1.0 / float(np.median(pj)) if js.any() and pj.size else math.nan
        capt = 100 * float(np.mean(captured[js])) if js.any() else math.nan
        reach = 100 * float(np.mean(reached[js])) if js.any() else math.nan
        pos = list(T.columns).index("missedBeats_percent") + 1
        T.insert(pos, "capture_percent", capt)
        T.insert(pos + 1, "currentReached_percent", reach)
        T.insert(0, "groupBy", by)
        T.insert(0, "groupStep", float(ks[q]))
        T.insert(0, "groupRole", roleOrder[kr[q]])
        T.insert(0, "groupValue", float(kv[q]))
        T.insert(0, "group", keys[q])
        parts.append(T)
    Z = pd.DataFrame(dict(t=tt, prevInt=prevInt, nextInt=nextInt, role=role, value=val, step=step, group=lbl,
                          captured=captured, inRange=inR))
    def _out(B, G):
        res = (B, G, Z) if return_stimuli else (B, G)
        return res + (notes,) if return_notes else res

    if not parts:
        return _out(B, pd.DataFrame())
    G = pd.concat(parts, ignore_index=True)
    ref = math.nan
    if refRole:
        r = np.flatnonzero(G["groupRole"].to_numpy() == refRole)
        if r.size:
            ref = float(G["amplitude_mean"].iloc[r[0]])
    G.insert(list(G.columns).index("amplitude_SD") + 1, "amplitude_pctOfRef", 100 * G["amplitude_mean"] / ref)
    cv = G["amplitude_CV"].to_numpy(float)
    with np.errstate(invalid="ignore"):
        irregular = np.where(np.isnan(cv), np.nan, (cv > irrCV).astype(float))
    G.insert(list(G.columns).index("amplitude_CV") + 1, "irregular", irregular)
    if selStep:  # FFR: number of the run summarized
        G["groupStep"] = [selStep.get(g, x) for g, x in zip(G["group"], G["groupStep"].to_numpy(float))]
    if byl == "pacingfrequency" and steadyN > 0 and minGB > 0:
        nc = G["nContractions"].to_numpy(float)
        few = np.flatnonzero((nc > 0) & (nc < minGB) & ~np.isnan(G["groupValue"].to_numpy(float)))
        if few.size:
            notes.append("fewer than %d included contractions at %s" % (minGB, ", ".join(
                "%s (%d)" % (G["group"].iloc[q], int(nc[q])) for q in few)))
    # post-rest potentiation: reference of each pause (2026-10-10)
    if byl == "pauselength" and prpRef != "steady" and nB > 0 and not math.isnan(steadyCL):
        with np.errstate(invalid="ignore"):
            regular = np.abs(prevInt - steadyCL) <= 0.05 * steadyCL  # stimuli at the steady interval
        amp = B["amplitude"].to_numpy(float)
        cOf = np.full(nS, -1)  # stimulated contraction of every stimulus
        okB = has & (B["beatType"].to_numpy() == "stimulated") & ~np.isnan(amp)
        for i in np.flatnonzero(okB):
            cOf[k[i]] = i
        post = np.flatnonzero((B["groupRole"].to_numpy() == "postRest") & has & B["included"].to_numpy(bool))
        refOf = np.full(nB, np.nan)
        if prpRef == "preceding":
            for i in post:
                lst = []
                j = k[i] - 1
                while j >= 0 and regular[j]:
                    if cOf[j] >= 0:
                        lst.append(cOf[j])
                        if len(lst) == prpN:
                            break
                    j -= 1
                if lst:
                    refOf[i] = float(np.median(amp[lst]))
        else:  # 'firstTrain'
            kp = np.flatnonzero((role == "postRest") & (tt >= r0) & (tt <= r1))
            lst = []
            if kp.size:
                j = kp[0] - 1
                while j >= 0 and regular[j]:
                    if cOf[j] >= 0:
                        lst.append(cOf[j])
                    j -= 1
            if lst:
                refOf[post] = float(np.mean(amp[lst]))
        grp = B["group"].to_numpy()
        pct = G["amplitude_pctOfRef"].to_numpy(float).copy()
        for q in np.flatnonzero(G["groupRole"].to_numpy() == "postRest"):
            rq = post[grp[post] == G["group"].iloc[q]]
            x = amp[rq] / refOf[rq]
            x = x[~np.isnan(x)]
            pct[q] = 100 * float(np.mean(x)) if x.size else math.nan
        G["amplitude_pctOfRef"] = pct
    return _out(B, G)


def add_empty_group_columns(B, T):
    """the group columns for a range without grouping (group 'all'), so that the tables can be concatenated."""
    B = B.copy()
    B["group"] = "all"
    B["groupValue"] = np.nan
    B["groupRole"] = ""
    B["groupStep"] = np.nan
    T = T.copy()
    pos = list(T.columns).index("missedBeats_percent") + 1
    T.insert(pos, "capture_percent", np.nan)
    T.insert(pos + 1, "currentReached_percent", np.nan)
    T.insert(list(T.columns).index("amplitude_SD") + 1, "amplitude_pctOfRef", np.nan)
    T.insert(list(T.columns).index("amplitude_CV") + 1, "irregular", np.nan)
    T.insert(0, "groupBy", "none")
    T.insert(0, "groupStep", np.nan)
    T.insert(0, "groupRole", "")
    T.insert(0, "groupValue", np.nan)
    T.insert(0, "group", "all")
    return B, T


# =====================================================================================================
def _cluster_values(v, absTol, relTol):
    """groups of similar values: sorted distinct values, a new group where the gap > absTol + relTol * lower value."""
    gid = np.full(v.shape, -1)
    u = np.unique(v[~np.isnan(v)])
    if u.size == 0:
        return gid
    br = np.r_[True, np.diff(u) > absTol + relTol * u[:-1]]
    starts = u[br]
    ok = ~np.isnan(v)
    gid[ok] = np.searchsorted(starts, v[ok], side="right") - 1
    return gid


def _cluster_anchored(v, relTol):
    """groups of similar values: sorted distinct values, a new group where the value > (1 + relTol) x the first value
    of the group (no chaining)"""
    gid = np.full(v.shape, -1)
    u = np.unique(v[~np.isnan(v)])
    if u.size == 0:
        return gid
    starts = [u[0]]
    for x in u[1:]:
        if x > (1 + relTol) * starts[-1] + 1e-12:
            starts.append(x)
    ok = ~np.isnan(v)
    gid[ok] = np.searchsorted(np.asarray(starts), v[ok], side="right") - 1
    return gid


def _round_frequency(f, res, res_low=0.05):
    """frequency rounded to res (Hz) at >= 1 Hz, to res_low below 1 Hz (as MATLAB round; division by the integer
    1 / res where possible: exact decimals)"""
    f = np.asarray(f, float)
    out = np.full(f.shape, np.nan)
    for sel, r in (((f >= 1), res), ((f < 1), res_low)):  # (NaN: neither)
        q = 1.0 / r
        if abs(q - round(q)) < 1e-9:
            q = float(round(q))
        out[sel] = np.array([mround(x * q) for x in f[sel]]) / q
    return out


def _group_median(v, gid):
    m = np.full(v.shape, np.nan)
    for g in np.unique(gid[gid >= 0]):
        k = gid == g
        m[k] = np.median(v[k])
    return m


def _first_index(a, v):
    """index of the first element of a equal to each value of v (-1: none; NaN never matches) - the lowest index of
    MATLAB ismember(v, a), without a search over a for every value. TS 2026-10-10"""
    a = np.asarray(a, float).ravel()
    v = np.asarray(v, float).ravel()
    out = np.full(v.size, -1, dtype=int)
    if a.size == 0 or v.size == 0:
        return out
    u, first = np.unique(a, return_index=True)  # sorted values (NaN last), index of their first occurrence
    p = np.clip(np.searchsorted(u, v), 0, u.size - 1)
    hit = u[p] == v
    out[hit] = first[p[hit]]
    return out


def _group_labels(byl, val, role, byName):
    out = []
    for v, r in zip(val, role):
        if byl == "pacingfrequency":  # the rounded frequency (_round_frequency)
            s = "%g Hz" % v if not math.isnan(v) else ""
        elif byl == "s2interval":
            if r == "S1":
                s = "S1"
            elif r == "preS2":
                s = "pre-S2"
            elif r == "other":
                s = "other"
            elif r == "S2":
                s = "S2 %d ms" % mround(1000 * v) if not math.isnan(v) else ""
            else:
                s = "post-S2 %d ms" % mround(1000 * v) if not math.isnan(v) else ""
        elif byl == "stimcurrent":
            s = "%g mA" % v
        elif byl == "pauselength":
            s = "rest %s s" % _g3(v) if r == "postRest" else ("after rest" if r == "afterRest" else r)
        elif byl == "rockerspeed":
            s = "%g rpm" % v
        elif byl == "pulseduration":
            s = "%g ms" % v
        else:
            s = "%s %g" % (byName[4:].strip(), v)
        if math.isnan(v) and r not in ("S1", "preS2", "other", "steady", "afterRest"):
            s = "unknown"
        out.append(s)
    return np.array(out, dtype=object)


def _g3(v):
    """v with 3 significant digits as MATLAB sprintf('%.3g') (halves away from zero)"""
    if math.isnan(v) or v == 0:
        return "%g" % v
    d = 2 - int(math.floor(math.log10(abs(v))))
    return "%g" % (mround(v * 10 ** d) / 10 ** d)


def _unique_last(te, x):
    """sorted distinct times; for several entries at the same time the last one (as MATLAB unique(..., 'last'))."""
    u, inv = np.unique(te, return_inverse=True)
    last = np.zeros(u.size, int)
    for i, g in enumerate(inv):
        last[g] = i
    return u, x[last]


def _rocker_speed_at(H, t, delay):
    R = np.asarray(H.rockerSpeedLog, dtype=float).reshape(-1, 2)
    t = np.asarray(t, dtype=float)
    v = np.full(t.shape, np.nan)
    if R.shape[0] == 0:
        return v
    R = R[np.argsort(R[:, 0], kind="stable")]
    te = np.maximum(R[:, 0] + delay, 0.0)
    te, rv = _unique_last(te, R[:, 1])
    k = np.searchsorted(te, t, side="right") - 1
    ok = (k >= 0) & ~np.isnan(t)
    v[ok] = rv[k[ok]]
    return v


def _log_value_at(H, code, ch, t):
    t = np.asarray(t, dtype=float)
    v = np.full(t.shape, np.nan)
    E = log_entries(H.logFile)
    if len(E) == 0:
        return v
    codes = E["code"].astype(str).str.lower().to_numpy()
    texts = E["text"].astype(str).str.lower().to_numpy()
    isRec = codes == "recording"
    started = np.array(["started" in x for x in texts])
    par = np.array(["parallel" in x for x in texts])
    c = np.flatnonzero(isRec & started & ~par)
    if c.size == 0:
        c = np.flatnonzero(isRec & started)
    tf = E["t_file"].to_numpy(float).copy()
    # the first start; a later one only if the dataLogTime starts again (new recording in the same log file; a
    # recording that was stopped and started again is appended to the .mdd file, its dataLogTime continues)
    if c.size:
        rec = int(c[0])
        for j in c[1:]:
            seg = tf[rec:j]
            if np.any(~np.isnan(seg)) and tf[j] < np.nanmax(seg) - 1:
                rec = int(j)
        tf[:rec] = -np.inf
    chs = E["channel"].to_numpy(float)
    k = np.flatnonzero((codes == code.lower()) & ((chs == ch) | (chs == 0)))
    if k.size == 0:
        return v
    x = np.full(k.size, np.nan)
    for i, kk in enumerate(k):
        num = sscanf_floats(str(E["text"].iloc[kk]))
        if num:
            x[i] = num[0]
    te = tf[k]
    o = np.argsort(te, kind="stable")
    te, x = _unique_last(te[o], x[o])
    kk = np.searchsorted(te, t, side="right") - 1
    ok = kk >= 0
    v[ok] = x[kk[ok]]
    return v
