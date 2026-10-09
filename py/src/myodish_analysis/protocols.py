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
  pacingFrequency, S2interval, stimCurrent, pauseLength, rockerSpeed, pulseDuration, 'log:<code>'.

TS 2026-10-07 (port of mda_protocols.m and mda_groupBeats.m; schedule files 2026-10-07; uncertain contractions
2026-10-09)
"""
from __future__ import annotations

import math
import re

import numpy as np
import pandas as pd

from ._matlab import Struct, mround
from .log_entries import log_entries, sscanf_floats
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


def find_protocols(src):
    if isinstance(src, dict):
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
    # other starts without end: until the next start of the same type or the end of the file; a start followed by
    # another start of the same type within 10 s is a repeated comment and dropped
    drop = [False] * len(st)
    for i, s in enumerate(st):
        if math.isnan(s["to"]):
            nxt = [x["start"] for x in st[i + 1:] if x["type"] == s["type"]]
            s["to"] = nxt[0] if nxt else T
            s["note"] = "no end comment"
            drop[i] = bool(nxt) and nxt[0] - s["start"] < 10
    st = [s for s, d in zip(st, drop) if not d]
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


# =====================================================================================================
def group_beats(H, B, C, range_, by, opts=None, return_stimuli=False):
    from .options import options as make_options
    from .read_mdd import read_mdd
    if opts is None:
        opts = make_options()
    by = str(by)
    byl = by.lower()
    r0, r1 = float(range_[0]), float(range_[1])

    # stimuli of the channel (with the 300 s before)
    S = read_mdd(H, max(0.0, r0 - 300), min(H.totalSeconds, r1 + 1), opts)
    stimCh = C.stimChannel
    idx = np.flatnonzero(S.stim.channel == stimCh)
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
    if byl == "pacingfrequency":
        val = 1.0 / _group_median(prevInt, _cluster_values(prevInt, 0.0, 0.02))
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
    k = np.full(nB, -1)
    for i in range(nB):
        if not math.isnan(tStim[i]):
            j = np.flatnonzero(tt == tStim[i])
        else:
            j = np.flatnonzero(tt <= tPeak[i] - opts.minStimToPeak)
            j = j[-1:]
        if j.size:
            k[i] = j[0]
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

    # summary per group
    inR = (tt >= r0) & (tt <= r1)
    Cst = np.asarray(C.stimTimes, dtype=float)
    Ccap = np.asarray(C.stimCaptured, dtype=bool)
    Ccc = np.asarray(C.get("stimCapturedCertain", C.stimCaptured), dtype=bool)
    captured = np.zeros(nS, bool)
    capturedCertain = np.zeros(nS, bool)  # followed by a certain contraction (option detection)
    for i in range(nS):
        j = np.flatnonzero(Cst == tt[i])
        if j.size:
            captured[i] = Ccap[j[0]]
            capturedCertain[i] = Ccc[j[0]]
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
    if not parts:
        return (B, pd.DataFrame(), Z) if return_stimuli else (B, pd.DataFrame())
    G = pd.concat(parts, ignore_index=True)
    ref = math.nan
    if refRole:
        r = np.flatnonzero(G["groupRole"].to_numpy() == refRole)
        if r.size:
            ref = float(G["amplitude_mean"].iloc[r[0]])
    G.insert(list(G.columns).index("amplitude_SD") + 1, "amplitude_pctOfRef", 100 * G["amplitude_mean"] / ref)
    return (B, G, Z) if return_stimuli else (B, G)


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


def _group_median(v, gid):
    m = np.full(v.shape, np.nan)
    for g in np.unique(gid[gid >= 0]):
        k = gid == g
        m[k] = np.median(v[k])
    return m


def _group_labels(byl, val, role, byName):
    out = []
    for v, r in zip(val, role):
        if byl == "pacingfrequency":
            stp = 0.05 if v >= 0.5 else 0.01
            s = "%g Hz" % (mround(v / stp) * stp) if not math.isnan(v) else ""
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
            s = "rest %.3g s" % v if r == "postRest" else ("after rest" if r == "afterRest" else r)
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
