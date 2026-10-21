# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Analysis report (PDF): which analyses should be checked, with traces and the commands to open them in the GUI.
Port of mda_report.m (same flags and pages).

    R = report_flags(S, C, status=None, **flags)         flags per channel (DataFrame)
    R = write_report(recordings, 'report.pdf', title=..., subtitle=[...], notice=[...], image=png, **flags)
    f = trend_image('trend.png', D)                       trend image of one channel (watcher, slice register;
                                                          2026-10-14): one panel per parameter, see trend_image
    T, C = trend_data(D)                                  its data (rows per window, comments shown)
    f = course_image('course.png', D)                     course image of one channel of a series (slice register,
                                                          2026-10-15): whole time course and the last 24 h
    Tc, Tl, Tm = course_data(D)                           its data (bins per slice, windows of the last 24 h, comments)
    f = experiment_image('overview.png', D)               overview image of an experiment (2026-10-15): series x
                                                          channels with the amplitude, status and red flags

Written by the watcher per experiment after every pass with analysed recordings of the experiment
(<experiment>/<experiment>_report.pdf: all its recordings, the new ones (rec['new']) in bold with detail pages, first
page image = overview image; 2026-10-15; option report=True), by myodish_analysis with an output file
(<output>_report.pdf, option report) and by the GUI on request (menu File).

recordings: list of dicts, one per recording: name (shown), file (.mdd), open (file for the GUI commands: results file
of the analysis, otherwise the .mdd file), S (summary), C (contractions, optional: amplitude, delay and the markers of
the traces), P (pulse table, optional: pulses in the traces; or P_file: read only for the detail pages), R (optional:
flags of report_flags, computed by the caller), status (dict channel -> status of the watcher channel
table, e.g. 'no slice', optional), notes (list of texts, e.g. protocols not analysed; 'error: ...' = analysis
error).

Flags per channel (channels with a slice and at least min_beats (50) detected contractions):
  check the analysis (red: the analysis may not work, or technical faults put wrong values into the data; detail page
  with traces):
    I  inverted signal (column invertedSignal) in ranges with at least min_beats detected contractions (sensor not
       working properly; only beating, capture and rate are analysed)
    N  noise suspected: uncertain contractions >= uncertain (25) % of the detected ones and, in a paced channel, extra
       beats + missed beats (% of the detected contractions + % of the stimuli) >= irregular (15) %: contractions near
       the detection threshold that do not follow the pacing are mostly noise or artifacts (e.g. rocker waves).
       Uncertain contractions with regular capture (few extra and missed beats) are real contractions near the
       threshold and not flagged. Noise index = uncertain % x min(100, extra % + missed %) / 100 (unpaced channel:
       uncertain %); it orders the list.
    S  large extra beats: certain extra beats >= artifact_share (5) % of the contractions with a median amplitude >
       artifact_ratio (3) times that of the certain stimulated contractions (spikes, saturation; needs C)
    D  median delay pulse -> onset of the stimulated contractions > delay (0.15 s)
    F  stimulus frequency > stim_frequency (10 Hz) in a range (median stimulus interval; 2026-10-13): pulse pairs or
       groups (e.g. CCM pulses without the extra-pulse bit), bursts, pulses over consecutive samples or a misread
       status channel; the contractions are analysed as usual (check the stimulation)
  slice quality (yellow: possibly poor biological quality, e.g. also an effect of a treatment; the user decides):
    C  capture < capture (90) % of the stimuli
    X  extra beats > extra (10) % of the detected contractions (spontaneous activity; not shown with N)
    A  median amplitude of the included contractions < amplitude (75 uN)
    T  amplitude change > amplitude_change (30) % from the first to the last range with >= 10 included contractions
       (shown with the time between the start of the first and the end of the last of these ranges, e.g. 'amplitude
       change +660 % over 24 h')
    V  median amplitude CV of the ranges > amplitude_cv (30) %
Arrhythmic pacing (summary column arrhythmicPacing: option arrhythmicChannels or detected, see options; 2026-10-13):
capture and amplitude CV are not flagged (C, V) and the missed beats do not count in the noise index (N: extra beats
only); missed beats, uncertain contractions and a variable amplitude are expected. The capture is still shown
(overview: '~' after it).
Channel label (lists and trace pages, e.g. 'ch 7 (PMA)'): the values of the label treatment (with concentration and
unit), otherwise sliceGroup, otherwise sampleGroup of the summary, if given.
Pages: overview (recordings x channels: capture % and codes), list of the channels to check (red) and of those with
slice-quality flags (yellow), one page per recording with red flags (at most max_pages (8), the recordings with
the most red flags and the highest noise index first; up to 4 channels with a window of window_s (20 s) at the most
uncertain / extra beats (N) or large extra beats (S)) with the commands to open them:
    MATLAB  MyoDishAnalysisGUI(file, 'channel', c, 'window', [from to])
    Python  mda-gui file --channel c --window from to

TS 2026-10-11 (noise index N, large extra beats S, extra beats as slice quality 2026-10-12; arrhythmic pacing, F
2026-10-13; trend images 2026-10-14; course and experiment images, reports per experiment 2026-10-15)
"""
from __future__ import annotations

import math
import os
import textwrap

import numpy as np
import pandas as pd

FLAG_DEFAULTS = dict(uncertain=25.0, irregular=15.0, artifact_share=5.0, artifact_ratio=3.0, extra=10.0, capture=90.0,
                     amplitude_change=30.0, amplitude=75.0, amplitude_cv=30.0, delay=0.15, min_beats=50,
                     stim_frequency=10.0)
RED_CODES = (("inverted", "I"), ("noise", "N"), ("large", "S"), ("delay", "D"), ("frequency", "F"),
             ("restart", "R"))
YELLOW_CODES = (("capture", "C"), ("extra", "X"), ("amplitude", "A"), ("change", "T"), ("cv", "V"))
RED_LETTERS = "".join(c for _, c in RED_CODES)
_CELL_RED, _CELL_YELLOW, _CELL_GREY = "#f8c9c4", "#fbe8a6", "#eeeeee"
_GREEN, _ORANGE, _BLUE, _RED, _GREY = "#2e7d32", "#e65100", "#1565c0", "#c62828", "#555555"
_A4 = (8.27, 11.69)
_ROWS_PER_PAGE = 48
_LINES_PER_PAGE = 78


def _flags(kw):
    unknown = set(kw) - set(FLAG_DEFAULTS)
    if unknown:
        raise ValueError(f"report: unknown flag(s) {', '.join(sorted(unknown))} ({', '.join(FLAG_DEFAULTS)})")
    return dict(FLAG_DEFAULTS, **kw)


def _sum(s, col):
    return float(s[col].sum()) if col in s.columns and len(s) else 0.0


def _truthy(x):
    """boolean column (bool, 0/1 or text 'True' / 'False' of a csv file)"""
    if x.dtype == bool:
        return x.to_numpy()
    return x.astype(str).str.strip().str.lower().isin(["true", "1", "1.0"]).to_numpy()


def _texts(x):
    """non-empty texts of a column, unique in order (csv: empty = NaN)"""
    out = []
    for v in x:
        t = "" if v is None or (isinstance(v, float) and math.isnan(v)) else str(v).strip()
        if t and t.lower() != "nan" and t not in out:
            out.append(t)
    return out


def channel_label(s):
    """short label of a channel from the label columns of its summary rows: treatment (with concentration and unit),
    otherwise sliceGroup, otherwise sampleGroup; several values (e.g. a treatment started later) joined by ' / '; ''
    if none."""
    if s is None or not len(s):
        return ""
    vals = []
    if "treatment" in s.columns:
        for _, r in s.iterrows():
            t = _texts([r["treatment"]])
            if not t:
                continue
            c = r["concentration"] if "concentration" in s.columns else math.nan
            try:
                c = float(c)
            except (TypeError, ValueError):
                c = math.nan
            u = _texts([r["concentrationUnit"]]) if "concentrationUnit" in s.columns else []
            v = t[0] + (f" {c:g}" + (f" {u[0]}" if u else "") if not math.isnan(c) else "")
            if v not in vals:
                vals.append(v)
    for col in ("sliceGroup", "sampleGroup"):
        if not vals and col in s.columns:
            vals = _texts(s[col])
    txt = " / ".join(vals[:3]) + (" / …" if len(vals) > 3 else "")
    return txt if len(txt) <= 40 else txt[:39] + "…"


def duration_text(hours):
    """'45 min', '5.5 h', '24 h', '3.5 d'"""
    if hours is None or not hours == hours:
        return ""
    if hours < 1.5:
        return "%.0f min" % (60 * hours)
    if hours < 10:
        return "%.1f h" % hours
    if hours < 72:
        return "%.0f h" % hours
    return "%.1f d" % (hours / 24)


def _label(r):
    lb = r.get("label", "") if hasattr(r, "get") else ""
    return f" ({lb})" if isinstance(lb, str) and lb else ""


def restart_warnings(E):
    """'controller restart suspected ...' from the events table E of a recording (lines of code warning whose text
    starts with 'Controller restart suspected', control software 2.2, F-90): '' if none, otherwise the description of
    the red flag R (number and time of the first one, s in the file), 2026-10-21"""
    if E is None or not len(E) or not {"code", "text"}.issubset(E.columns):
        return ""
    k = np.flatnonzero((E["code"].astype(str).str.lower() == "warning").to_numpy()
                       & E["text"].astype(str).str.lower().str.startswith("controller restart suspected").to_numpy())
    if not k.size:
        return ""
    t = float(E["t_file"].iloc[k[0]]) if "t_file" in E.columns else math.nan
    if math.isnan(t):
        return f"controller restart suspected ({k.size})"
    return f"controller restart suspected ({k.size}, first at {t:.0f} s)"


def report_flags(S, C=None, status=None, events=None, **flags):
    """one row per channel: counts, values and flags (columns flags = codes, red / yellow = descriptions). events
    (2026-10-21): events table of the recording (log_entries / <name>_events.csv) for the red flag R (controller
    restart suspected)."""
    fl = _flags(flags)
    status = dict(status or {})
    restart = restart_warnings(events)
    chans = sorted(({int(c) for c in S["channel"]} if S is not None and len(S) else set())
                   | {int(c) for c in status})
    rows = []
    for c in chans:
        s = S[S["channel"] == c] if S is not None and len(S) else pd.DataFrame()
        nDet, nStim, nMiss = _sum(s, "nDetected"), _sum(s, "nStimuli"), _sum(s, "nMissedBeats")
        nX, nU = _sum(s, "nExtraBeats"), _sum(s, "nUncertain")
        good = s[s["nContractions"] >= 10] if "nContractions" in s.columns else s.iloc[0:0]
        a1 = float(good["amplitude_mean"].iloc[0]) if len(good) else math.nan
        a2 = float(good["amplitude_mean"].iloc[-1]) if len(good) else math.nan
        span = (float(good["to"].iloc[-1]) - float(good["from"].iloc[0])) / 3600 \
            if len(good) > 1 and {"from", "to"} <= set(good.columns) else math.nan
        cv = s["amplitude_CV"].to_numpy(float) if "amplitude_CV" in s.columns else np.array([])
        r = dict(channel=c, label=channel_label(s), status=str(status.get(c, "")), nDetected=int(nDet),
                 capture_percent=100 * (1 - nMiss / nStim) if nStim > 0 else math.nan,
                 extra_percent=100 * nX / nDet if nDet > 0 else math.nan,
                 uncertain_percent=100 * nU / nDet if nDet > 0 else math.nan,
                 extraMissed_percent=math.nan, noiseIndex=math.nan, largeExtra_percent=math.nan,
                 largeExtra_ratio=math.nan,
                 amplitude_uN=math.nan,
                 amplitudeChange_percent=100 * (a2 - a1) / a1 if len(good) > 1 and a1 > 0 else math.nan,
                 amplitudeChange_hours=span if len(good) > 1 and a1 > 0 else math.nan,
                 amplitudeCV_percent=100 * float(np.median(cv[~np.isnan(cv)])) if np.any(~np.isnan(cv)) else math.nan,
                 delay_ms=math.nan,
                 invertedSignal=False,
                 arrhythmicPacing=bool(_truthy(s["arrhythmicPacing"]).any()) if "arrhythmicPacing" in s.columns
                 and len(s) else False,
                 stimFrequency_Hz=float(np.nanmax(s["stimFrequency"].to_numpy(float)))
                 if "stimFrequency" in s.columns and s["stimFrequency"].notna().any() else math.nan)
        arr = r["arrhythmicPacing"]
        if nDet > 0:  # noise index: uncertain contractions in a channel that does not follow the pacing
            if nStim > 0:  # arrhythmic pacing: missed beats expected, not counted (2026-10-13)
                r["extraMissed_percent"] = r["extra_percent"] + (0.0 if arr else 100 - r["capture_percent"])
                r["noiseIndex"] = r["uncertain_percent"] * min(100.0, r["extraMissed_percent"]) / 100
            else:
                r["noiseIndex"] = r["uncertain_percent"]
        nInv = 0.0
        if "invertedSignal" in s.columns and len(s):
            iv = _truthy(s["invertedSignal"])
            r["invertedSignal"] = bool(iv.any())
            nInv = float(s.loc[iv, "nDetected"].sum()) if "nDetected" in s.columns else 0.0
        cc = C[C["channel"] == c] if C is not None and len(C) else None
        if cc is not None and len(cc):
            inc = cc[cc["included"].astype(bool)] if "included" in cc.columns else cc
            a = inc["amplitude"].to_numpy(float) if "amplitude" in inc.columns else np.array([])
            if np.any(~np.isnan(a)):
                r["amplitude_uN"] = float(np.median(a[~np.isnan(a)]))
            st = cc[cc["beatType"] == "stimulated"] if "beatType" in cc.columns else cc.iloc[0:0]
            d = st["stimToOnset"].to_numpy(float) if "stimToOnset" in st.columns else np.array([])
            if np.any(~np.isnan(d)):
                r["delay_ms"] = 1000 * float(np.median(d[~np.isnan(d)]))
            if {"beatType", "uncertain", "amplitude"} <= set(cc.columns):  # large certain extra beats
                cert = ~cc["uncertain"].astype(bool).to_numpy()
                bt = cc["beatType"].astype(str).to_numpy()
                ae, asx = cc["amplitude"].to_numpy(float)[cert & (bt == "extra")], \
                    cc["amplitude"].to_numpy(float)[cert & (bt == "stimulated")]
                ae, asx = ae[~np.isnan(ae)], asx[~np.isnan(asx)]
                r["largeExtra_percent"] = 100 * ae.size / len(cc)
                if ae.size and asx.size and np.median(asx) > 0:
                    r["largeExtra_ratio"] = float(np.median(ae) / np.median(asx))
        elif "amplitude_mean" in s.columns and s["amplitude_mean"].notna().any():
            r["amplitude_uN"] = float(np.nanmedian(s["amplitude_mean"].to_numpy(float)))
        red, yellow = [], []
        if r["status"] != "no slice" and nDet >= fl["min_beats"]:
            if nInv >= fl["min_beats"]:  # ranges with an inverted signal and enough contractions
                share = 100 * nInv / nDet
                part = "" if nInv >= nDet else " (< 1 % of the contractions)" if share < 1 else \
                    f" ({share:.0f} % of the contractions)"
                red.append(("inverted", "inverted signal" + part))
            noise = r["uncertain_percent"] >= fl["uncertain"] and (nStim <= 0 or
                                                                    r["extraMissed_percent"] >= fl["irregular"])
            if noise:
                red.append(("noise", "noise index %.0f (uncertain %.0f %%, " % (r["noiseIndex"], r["uncertain_percent"])
                            + ("extra %.0f %%, arrhythmic pacing)" % r["extra_percent"] if nStim > 0 and arr else
                               "extra %.0f %%, missed %.0f %%)" % (r["extra_percent"], 100 - r["capture_percent"])
                               if nStim > 0 else "unpaced)")))
            if r["largeExtra_percent"] >= fl["artifact_share"] and r["largeExtra_ratio"] > fl["artifact_ratio"]:
                red.append(("large", "large extra beats %.0f %% (%.1f x the paced amplitude)"
                            % (r["largeExtra_percent"], r["largeExtra_ratio"])))
            if r["delay_ms"] > 1000 * fl["delay"]:
                red.append(("delay", "delay %.0f ms" % r["delay_ms"]))
            if r["stimFrequency_Hz"] > fl["stim_frequency"]:
                red.append(("frequency", "stimulus frequency %.0f Hz" % r["stimFrequency_Hz"]))
            if restart:
                red.append(("restart", restart))
            if r["capture_percent"] < fl["capture"] and not arr:
                yellow.append(("capture", "capture %.0f %%" % r["capture_percent"]))
            if not noise and r["extra_percent"] > fl["extra"]:
                yellow.append(("extra", "extra beats %.0f %%" % r["extra_percent"]))
            if not r["invertedSignal"] and r["amplitude_uN"] < fl["amplitude"]:
                yellow.append(("amplitude", "amplitude %.0f uN" % r["amplitude_uN"]))
            if abs(r["amplitudeChange_percent"]) > fl["amplitude_change"]:
                d = duration_text(r["amplitudeChange_hours"])
                yellow.append(("change", "amplitude change %+.0f %% " % r["amplitudeChange_percent"]
                               + (f"over {d}" if d else "(first vs. last range)")))
            if r["amplitudeCV_percent"] > fl["amplitude_cv"] and not arr:
                yellow.append(("cv", "amplitude CV %.0f %%" % r["amplitudeCV_percent"]))
        code = dict(RED_CODES + YELLOW_CODES)
        r["flags"] = "".join(code[k] for k, _ in red + yellow)
        r["red"] = "; ".join(t for _, t in red)
        r["yellow"] = ", ".join(t for _, t in yellow)
        r["level"] = "check" if red else ("quality" if yellow else
                                          ("no slice" if r["status"] == "no slice" else
                                           ("few beats" if nDet < fl["min_beats"] else "")))
        rows.append(r)
    cols = ["channel", "label", "status", "nDetected", "capture_percent", "extra_percent", "uncertain_percent",
            "extraMissed_percent", "noiseIndex", "largeExtra_percent", "largeExtra_ratio", "amplitude_uN",
            "amplitudeChange_percent", "amplitudeChange_hours", "amplitudeCV_percent", "delay_ms", "invertedSignal",
            "arrhythmicPacing", "stimFrequency_Hz", "flags", "level", "red", "yellow"]
    return pd.DataFrame(rows, columns=cols)


def report_window(C, channel, flags="", width=20.0):
    """window [from, to] of width s at the most uncertain / extra contractions (flag N; X, U as well), at the most
    certain extra beats (S), otherwise around the median contraction."""
    c = C[C["channel"] == channel] if C is not None and len(C) and "t_peak" in C.columns else None
    if c is None or not len(c):
        return 0.0, float(width)
    t = c["t_peak"].to_numpy(float)
    bad = np.zeros(len(c), bool)
    ex = (c["beatType"] == "extra").to_numpy() if "beatType" in c.columns else np.zeros(len(c), bool)
    un = c["uncertain"].astype(bool).to_numpy() if "uncertain" in c.columns else np.zeros(len(c), bool)
    if "X" in flags or "N" in flags:
        bad |= ex
    if "U" in flags or "N" in flags:
        bad |= un
    if "S" in flags and not bad.any():
        bad |= ex & ~un
    if bad.any():
        e = np.arange(math.floor(np.nanmin(t)), np.nanmax(t) + width, width)
        h, _ = np.histogram(t[bad], e)
        a = float(e[int(np.argmax(h))])
    else:
        a = math.floor(float(np.nanmedian(t)) - width / 2)
    a = max(0.0, a)
    return a, a + float(width)


def gui_commands(file, channel, a, b):
    """(MATLAB, Python) commands that open the file at this channel and window."""
    m = "MyoDishAnalysisGUI('%s', 'channel', %d, 'window', [%g %g])" % (str(file).replace("'", "''"), channel, a, b)
    p = 'mda-gui "%s" --channel %d --window %g %g' % (file, channel, a, b)
    return m, p


def write_report(recordings, out, title="MyoDishAnalysis report", subtitle=(), max_pages=8, window_s=20.0, notice=(),
                 image=None, **flags):
    """writes the PDF; returns the flags of all channels (DataFrame: recording, file, open, ..., window_from,
    window_to, matlab, python; window and commands for the channels with red flags). notice: lines shown in red at
    the top of the first page (watcher: recordings analysed with another version or other options). rec['new']
    (optional, 2026-10-15; experiment reports of the watcher): recordings of the last pass, marked '(new)'; detail
    pages only for them (the others: flags R and windows of mda_flags.csv, no contractions). image: PNG shown on the
    first page (experiment overview)."""
    import matplotlib
    from matplotlib.backends.backend_pdf import PdfPages
    from .write_results import mda_version
    fl = _flags(flags)
    recs = []
    has_new = any("new" in r for r in recordings)
    for rec in recordings:
        R = rec.get("R")  # flags computed by the caller (e.g. the watcher: C kept only for channels to check)
        R = report_flags(rec.get("S"), rec.get("C"), rec.get("status"), **fl) if R is None else R.copy()
        R = R.reset_index(drop=True)
        for c, v in (("noiseIndex", math.nan), ("arrhythmicPacing", False)):
            if c not in R.columns:
                R[c] = v
        R.insert(0, "recording", rec["name"])
        if "window_from" not in R.columns:
            R["window_from"], R["window_to"] = math.nan, math.nan
        R["window_from"] = R["window_from"].astype(float)
        R["window_to"] = R["window_to"].astype(float)
        R["matlab"], R["python"] = "", ""
        opn = rec.get("open") or rec.get("file") or ""
        C = rec.get("C")
        for i in np.flatnonzero((R["level"] == "check").to_numpy()):
            if not np.isfinite(R.at[i, "window_from"]) or C is not None:  # windows of mda_flags.csv kept
                R.at[i, "window_from"], R.at[i, "window_to"] = report_window(C, int(R.at[i, "channel"]),
                                                                             R.at[i, "flags"], window_s)
            R.at[i, "matlab"], R.at[i, "python"] = gui_commands(opn, int(R.at[i, "channel"]), R.at[i, "window_from"],
                                                                R.at[i, "window_to"])
        recs.append(dict(rec, R=R, notes=list(rec.get("notes") or []), open=opn))
    allR = pd.concat([r["R"] for r in recs], ignore_index=True) if recs else report_flags(None)
    check = [r for r in recs if (r["R"]["level"] == "check").any() or r["notes"]]
    def order(r):  # the most red flags, then the highest noise index first
        chk = r["R"][r["R"]["level"] == "check"]
        ni = chk["noiseIndex"].to_numpy(float) if "noiseIndex" in chk.columns else np.array([])
        return (-sum(sum(ch in RED_LETTERS for ch in str(f)) for f in chk["flags"]),
                -(float(np.nanmax(ni)) if ni.size and np.any(~np.isnan(ni)) else 0.0))
    detail = sorted([r for r in recs if (r["R"]["level"] == "check").any() and (not has_new or r.get("new") is True)],
                    key=order)
    detail = detail[:max_pages]
    os.makedirs(os.path.dirname(os.path.abspath(out)) or ".", exist_ok=True)
    with matplotlib.rc_context({"font.size": 7}), \
            PdfPages(out, metadata={"Title": title, "Creator": f"MyoDishAnalysis {mda_version()}"}) as pdf:
        first = image is not None and os.path.isfile(str(image))
        if first:
            _image_page(pdf, image, title, subtitle, notice)
        _overview_pages(pdf, recs, title, subtitle, fl, len(detail), () if first else notice)
        _list_pages(pdf, recs, check, detail)
        for rec in detail:
            _detail_page(pdf, rec)
    return allR


def report_path(output, report=None):
    """file of the report of an analysis: report = None / True / 'on' -> <output without extension>_report.pdf (no
    output: none), False / 'off' -> none, a file name -> this file."""
    if report is False or report is None and not output:
        return None
    if isinstance(report, (str, os.PathLike)):
        r = str(report)
        if r.lower() in ("off", "false", "none", ""):
            return None
        if r.lower() not in ("on", "true", "auto"):
            return r
    if not output:
        return None
    o = str(output)
    stem, ext = os.path.splitext(o)
    return (stem if ext.lower() in (".xlsx", ".xls", ".csv") else o) + "_report.pdf"


def options_changed(opts):
    """'name=value; ...' of the options that differ from the defaults (subtitle of the report)."""
    from .options import options as make_options
    from .write_results import _option_text
    d0 = make_options()
    ch = [f"{k}={_option_text(v)}" for k, v in opts.items()
          if k != "referenceBeat" and k in d0 and _option_text(v) != _option_text(d0[k])]
    return "; ".join(ch) if ch else "defaults"


def analysis_report(out, file, C, S, info, results=None, **flags):
    """report of one analysis (myodish_analysis, GUI): one recording; the GUI commands open the results file (or the
    recording). Returns the flags (see write_report)."""
    from .write_results import mda_version
    notes = [str(n) for n in (info.get("notes") or []) if "not analysed" in str(n)]
    rec = dict(name=os.path.basename(str(file)), file=str(file), open=results or str(file), S=S, C=C,
               P=info.get("pulses"), notes=notes)
    opts = info.get("options") or {}
    sub = [f"recording: {file}", f"results: {results}" if results else "results: not written",
           f"MyoDishAnalysis {mda_version()} (Python), analysed {info.get('analysisDate', '')}; settings: "
           f"{options_changed(opts) if len(opts) else 'defaults'}"]
    return write_report([rec], out, subtitle=sub, **flags)


# ------------------------------------------------------------------------------------------------ pages
def _figure():
    from matplotlib.figure import Figure
    return Figure(figsize=_A4)


def _short(name, n):
    s = str(name)
    for a, b in ((".mdd", ""), ("_scheduleFile_", " sched "), ("_withParallelRecording", "")):
        s = s.replace(a, b)
    return s if len(s) <= n else s[:n - 1] + "…"


def _image_page(pdf, image, title, subtitle, notice=()):
    """first page of an experiment report (2026-10-15): title, subtitle, notice and the overview image of the
    experiment"""
    import matplotlib.image as mpimg
    from matplotlib.figure import Figure
    img = mpimg.imread(str(image))
    P = (_A4[1], _A4[0]) if img.shape[1] > 1.2 * img.shape[0] else _A4  # landscape for a wide image
    fig = Figure(figsize=P)
    dy = _A4[1] / P[1]  # line spacing as on a portrait page
    fig.text(0.05, 1 - 0.035 * dy, title, fontsize=14, weight="bold")
    y = 1 - 0.052 * dy
    for s in subtitle:
        for ln in textwrap.wrap(str(s), int(150 * P[0] / _A4[0]))[:2]:
            fig.text(0.05, y, ln, fontsize=6.5, color=_GREY)
            y -= 0.011 * dy
    for s in notice:
        for ln in textwrap.wrap(str(s), int(135 * P[0] / _A4[0]))[:3]:
            fig.text(0.05, y, ln, fontsize=7, color=_RED, weight="bold" if s == notice[0] else "normal")
            y -= 0.012 * dy
    ratio = img.shape[0] / img.shape[1] * P[0] / P[1]  # height per width (page units)
    h = min(ratio * 0.9, y - 0.05)
    wd = h / ratio
    ax = fig.add_axes([(1 - wd) / 2, y - 0.01 - h, wd, h])
    ax.imshow(img)
    ax.axis("off")
    pdf.savefig(fig)


def _overview_pages(pdf, recs, title, subtitle, fl, nDetail, notice=()):
    nRed = sum(int((r["R"]["level"] == "check").sum()) for r in recs)
    nNew = sum(1 for r in recs if r.get("new") is True)
    nYel = sum(int((r["R"]["level"] == "quality").sum()) for r in recs)
    nSl = sum(int((r["R"]["status"] != "no slice").sum()) for r in recs)
    chans = sorted({int(c) for r in recs for c in r["R"]["channel"]}) or list(range(1, 9))
    pages = [recs[i:i + _ROWS_PER_PAGE] for i in range(0, max(1, len(recs)), _ROWS_PER_PAGE)]
    for p, part in enumerate(pages):
        fig = _figure()
        fig.text(0.05, 0.965, title + (f" (overview {p + 1}/{len(pages)})" if len(pages) > 1 else ""),
                 fontsize=14, weight="bold")
        y = 0.948
        for s in subtitle:
            for ln in textwrap.wrap(str(s), 150)[:2]:
                fig.text(0.05, y, ln, fontsize=6.5, color=_GREY)
                y -= 0.011
        if p == 0 and notice:  # e.g. recordings analysed with another version (watcher)
            y -= 0.003
            for s in notice:
                for ln in textwrap.wrap(str(s), 135)[:3]:
                    fig.text(0.05, y, ln, fontsize=7, color=_RED, weight="bold" if s == notice[0] else "normal")
                    y -= 0.012
        fig.text(0.05, y - 0.004, f"{len(recs)} recording(s)" + (f" ({nNew} new = bold)" if nNew else "")
                 + f", {nSl} channel(s) with a slice: {nRed} to check (red"
                 + (f", traces on {nDetail} page(s)" if nDetail else "") + f"), {nYel} with slice-quality flags (yellow)",
                 fontsize=8)
        top = y - 0.02
        ax = fig.add_axes([0.05, 0.10, 0.92, top - 0.10])
        ax.axis("off")
        ax.set_xlim(0, 1)
        ax.set_ylim(0, 1)
        rh = 1.0 / (_ROWS_PER_PAGE + 1)
        x0 = 0.46
        cw = min(0.068, (1 - x0) / len(chans))
        ax.text(0, 1, "recording", fontsize=7, weight="bold", va="top")
        for j, c in enumerate(chans):
            ax.text(x0 + (j + 0.5) * cw, 1, f"ch {c}", fontsize=7, weight="bold", va="top", ha="center")
        for k, rec in enumerate(part):
            yk = 1 - (k + 1) * rh
            ax.text(0, yk - rh * 0.2, _short(rec["name"], 62), fontsize=6, va="top",
                    weight="bold" if rec.get("new") is True else "normal")
            if rec["notes"]:
                mk = "E" if any(str(m).startswith("error") for m in rec["notes"]) else "P"
                ax.text(x0 - 0.008, yk - rh * 0.2, mk, fontsize=6, va="top", ha="right", color=_RED, weight="bold")
            byc = {int(r["channel"]): r for _, r in rec["R"].iterrows()}
            for j, c in enumerate(chans):
                r = byc.get(c)
                if r is None:
                    continue
                if r["level"] == "no slice":
                    col, txt = "white", ""
                elif r["level"] == "few beats":
                    col = _CELL_GREY
                    txt = {"beating": "b", "not beating": "nb", "removed": "rm", "signal lost": "lost",
                           "protocols only": "prot"}.get(r["status"], str(r["nDetected"]))
                else:
                    col = _CELL_RED if r["level"] == "check" else (_CELL_YELLOW if r["level"] == "quality" else "white")
                    cap = "" if math.isnan(r["capture_percent"]) else "%.0f" % r["capture_percent"] \
                        + ("~" if r.get("arrhythmicPacing", False) else "")
                    txt = (cap + " " + r["flags"]).strip()
                ax.add_patch(matplotlib_rect(x0 + j * cw + 0.002, yk - rh + 0.001, cw - 0.004, rh - 0.002, col))
                ax.text(x0 + (j + 0.5) * cw, yk - rh / 2, txt, fontsize=5.5, ha="center", va="center")
        _legend(fig, fl)
        pdf.savefig(fig)


def legend_lines(fl):
    """(cell colour, text) of the legend below the overview table"""
    mu = "\u00b5"
    return [
        (None, "Each cell: capture (% of the stimuli followed by a contraction; ~ arrhythmic pacing, C and V not "
               "flagged) and the letters of the flags. White: no flag; empty: no slice."),
        ("check", f"Red = check the analysis:  I inverted signal,  N noise (uncertain \u2265 {fl['uncertain']:g} %, "
                  f"extra+missed \u2265 {fl['irregular']:g} %),  S large extra beats (> {fl['artifact_ratio']:g} x "
                  f"paced),  D delay > {1000 * fl['delay']:g} ms,  F pacing > {fl['stim_frequency']:g} Hz"),
        ("check", "R controller restart suspected (warning of the control software: after it the controller may have "
                  "run with its power-on settings instead of those in the log)"),
        ("quality", f"Yellow = slice quality:  C capture < {fl['capture']:g} %,  X extra beats > {fl['extra']:g} %,  "
                    f"A amplitude < {fl['amplitude']:g} {mu}N,  T amplitude changes by > {fl['amplitude_change']:g} % "
                    f"during the recording,  V amplitude CV > {fl['amplitude_cv']:g} %"),
        ("few beats", f"Grey = fewer than {fl['min_beats']:g} contractions:  b beating, nb not beating, rm removed, "
                      "otherwise the number of contractions"),
        (None, "Red letter left of the cells:  P a stimulation protocol was not analysed,  E analysis error  "
               "(details in the list on the next page)"),
    ]


def _legend(fig, fl):
    col = {"check": _CELL_RED, "quality": _CELL_YELLOW, "few beats": _CELL_GREY}
    y = 0.085
    for c, t in legend_lines(fl):
        x = 0.05
        if c is not None:
            fig.patches.append(matplotlib_rect(0.05, y - 0.0015, 0.012, 0.0085, col[c], transform=fig.transFigure,
                                               figure=fig))
            x = 0.066
        fig.text(x, y, t, fontsize=6.5)
        y -= 0.0125


def matplotlib_rect(x, y, w, h, color, **kw):
    from matplotlib.patches import Rectangle
    return Rectangle((x, y), w, h, color=color, lw=0, **kw)


def _list_pages(pdf, recs, check, detail):
    page0 = pdf.get_pagecount()
    lines = [("Check the analysis (red)", "h")]
    if not check:
        lines.append(("no channel to check", "n"))
    lines_detail = {}
    for rec in check:
        lines.append((_short(rec["name"], 110) + ("  (new)" if rec.get("new") is True else ""), "b"))
        lines_detail[len(lines) - 1] = rec
        for _, r in rec["R"][rec["R"]["level"] == "check"].iterrows():
            lines.append((f"ch {int(r['channel'])}{_label(r)}: {r['red']}" + (f"   ({r['yellow']})" if r["yellow"] else ""),
                          "n"))
        for m in rec["notes"]:
            for ln in textwrap.wrap(str(m), 140)[:3]:
                lines.append((ln, "o"))
    lines.append(("", "n"))
    lines.append(("Slice quality (yellow)", "h"))
    nQ = 0
    for rec in recs:
        q = rec["R"][rec["R"]["level"] == "quality"]
        if len(q):
            nQ += len(q)
            txt = _short(rec["name"], 80) + " - " + "; ".join(f"ch {int(r['channel'])}{_label(r)}: {r['yellow']}"
                                                              for _, r in q.iterrows())
            for ln in textwrap.wrap(txt, 150):
                lines.append((ln, "s"))
    if not nQ:
        lines.append(("none", "n"))
    # pages of the list, then the page numbers of the detail pages
    chunks = [lines[i:i + _LINES_PER_PAGE] for i in range(0, len(lines), _LINES_PER_PAGE)]
    first = page0 + len(chunks) + 1
    pageOf = {id(rec): first + k for k, rec in enumerate(detail)}
    for p, chunk in enumerate(chunks):
        fig = _figure()
        y = 0.965
        for k, (txt, sty) in enumerate(chunk):
            i = p * _LINES_PER_PAGE + k
            if sty == "h":
                fig.text(0.05, y, txt, fontsize=11, weight="bold")
                y -= 0.016
                continue
            x, size, color, weight = {"b": (0.05, 7.5, "black", "bold"), "n": (0.07, 6.8, "black", "normal"),
                                      "o": (0.07, 6.5, _ORANGE, "normal"), "s": (0.05, 6.3, "black", "normal")}[sty]
            fig.text(x, y, txt, fontsize=size, color=color, weight=weight)
            rec = lines_detail.get(i)
            if rec is not None and id(rec) in pageOf:
                fig.text(0.95, y, f"page {pageOf[id(rec)]}", fontsize=6.5, color=_GREY, ha="right")
            y -= 0.0118
        pdf.savefig(fig)


def _detail_page(pdf, rec):
    from .read_mdd import read_mdd
    R = rec["R"]
    rows = R[R["level"] == "check"].head(4)
    fig = _figure()
    fig.text(0.05, 0.965, _short(rec["name"], 100), fontsize=10, weight="bold")
    fig.text(0.05, 0.951, "o stimulated (green) / extra beat (orange), x uncertain; dashed: pulse (blue) / pulse without "
             "contraction (red); dotted: extra pulse", fontsize=6.5, color=_GREY)
    top, bottom = 0.935, 0.22
    h = (top - bottom) / 4
    H = None
    try:
        H = read_mdd(rec["file"])
    except Exception as ex:  # noqa: BLE001
        fig.text(0.05, 0.9, f"recording not read: {ex}", fontsize=8, color=_RED)
    C, P = rec.get("C"), rec.get("P")
    if P is None and rec.get("P_file"):  # pulse table read only for the detail pages
        for g in (rec["P_file"], rec["P_file"] + ".gz"):
            if os.path.isfile(g):
                P = pd.read_csv(g, usecols=lambda c: c in ("channel", "t", "extra", "outcome"), low_memory=False)
                break
    for k, (_, r) in enumerate(rows.iterrows()):
        a, b = float(r["window_from"]), float(r["window_to"])
        ax = fig.add_axes([0.09, top - (k + 1) * h + 0.045, 0.86, h - 0.075])
        ax.set_title(f"channel {int(r['channel'])}{_label(r)}: " + "; ".join(x for x in (r["red"], r["yellow"]) if x),
                     fontsize=8, loc="left")
        ax.tick_params(labelsize=6)
        ax.set_xlim(a, b)
        ax.set_xlabel("time in the recording (s)", fontsize=6)
        ax.set_ylabel("force (µN)", fontsize=6)
        if H is None:
            continue
        try:
            D = read_mdd(H, a, b)
            i = [int(c) for c in np.ravel(D.dataChannels)].index(int(r["channel"]))
        except Exception as ex:  # noqa: BLE001
            ax.text(0.5, 0.5, f"not read: {ex}", transform=ax.transAxes, ha="center", fontsize=7, color=_RED)
            continue
        t, y = np.asarray(D.t, float), np.asarray(D.force[i], float)
        ax.plot(t, y, color="#37474f", lw=0.6)
        if P is not None and len(P) and {"channel", "t"} <= set(P.columns):
            p = P[(P["channel"] == r["channel"]) & (P["t"] >= a) & (P["t"] <= b)]
            for _, q in p.iterrows():
                ax.axvline(float(q["t"]), color=_RED if q.get("outcome") == "noResponse" else _BLUE, lw=0.8,
                           ls=":" if bool(q.get("extra", False)) else "--")
        if C is not None and len(C) and "t_peak" in C.columns:
            c = C[(C["channel"] == r["channel"]) & (C["t_peak"] >= a) & (C["t_peak"] <= b)]
            for _, q in c.iterrows():
                tp = float(q["t_peak"])
                ax.plot(tp, np.interp(tp, t, y), "x" if bool(q.get("uncertain", False)) else "o", ms=4, mfc="none",
                        color=_GREEN if q.get("beatType") == "stimulated" else _ORANGE)
    yy = 0.19
    fig.text(0.05, yy, "Open in the GUI (MATLAB; Python: mda-gui \"<file>\" --channel <c> --window <from> <to>):",
             fontsize=7, weight="bold")
    yy -= 0.014
    for ln in textwrap.wrap("f = '%s';" % str(rec["open"]).replace("'", "''"), 130):
        fig.text(0.05, yy, ln, fontsize=6, family="monospace")
        yy -= 0.012
    for _, r in rows.iterrows():
        fig.text(0.05, yy, "MyoDishAnalysisGUI(f, 'channel', %d, 'window', [%g %g])"
                 % (int(r["channel"]), r["window_from"], r["window_to"]), fontsize=6, family="monospace")
        yy -= 0.012
    for m in rec["notes"]:
        yy -= 0.004
        fig.text(0.05, yy, textwrap.shorten(str(m), 150), fontsize=6.5, color=_ORANGE)
        yy -= 0.012
    pdf.savefig(fig)


# ------------------------------------------------------------------------------------------------ trend images
_BLUE, _DOT, _PURPLE, _INK = "#1D72B9", "#A3B8D6", "#8C3DA8", "#212121"
_PROT, _GAP = "#DEEDFF", "#E3E3E3"


def _trend_units(y, un):
    """display units: uN -> µN, s -> ms"""
    un = str(un) if un is not None else ""
    if un == "s":
        return 1000 * y, "ms"
    return y, {"uN": "µN", "uN/s": "µN/s", "uN*s": "µN·s", "": "-"}.get(un, un)


def _fmt_sig(v):
    if not np.isfinite(v):
        return "NaN"
    if abs(v) >= 100:
        return f"{v:.0f}"
    if abs(v) >= 10:
        return f"{v:.1f}"
    return f"{v:.3g}"


def _trend_note(th, y, un):
    ok = ~np.isnan(y)
    if not ok.any():
        return ""
    s = f"median {_fmt_sig(float(np.median(y[ok])))} {un}"
    t, v = th[ok], y[ok]
    if t.max() - t.min() >= 4:
        a = float(np.median(v[t <= t.min() + 2]))
        b = float(np.median(v[t >= t.max() - 2]))
        s += f"   first / last 2 h: {_fmt_sig(a)} → {_fmt_sig(b)}"
        if a != 0 and np.isfinite(a) and np.isfinite(b):
            s += f" ({100 * (b - a) / abs(a):+.0f} %)"
    return s


def _trend_ticks(xl, t0, n_max=9):
    """ticks (hours after t0) and labels: clock time 'HH:MM', midnight / steps of days 'dd Mon'; otherwise hours; at
    most about n_max intervals"""
    import datetime as _dt
    steps = [1 / 60, 2 / 60, 5 / 60, 10 / 60, 0.25, 0.5, 1, 2, 3, 6, 12, 24, 48, 96, 168, 336]
    span = xl[1] - xl[0]
    st = steps[-1]
    for s_ in steps:
        if span / s_ <= n_max:
            st = s_
            break
    if t0 is None:
        tk = np.arange(math.ceil(xl[0] / st - 1e-9), math.floor(xl[1] / st + 1e-9) + 1) * st
        return tk, [f"{h:g}" for h in tk]
    midnight = _dt.datetime(t0.year, t0.month, t0.day)
    off = (t0 - midnight).total_seconds() / 3600  # hours of t0 after its midnight
    a, b = xl[0] + off, xl[1] + off
    hrs = np.arange(math.ceil(a / st - 1e-9), math.floor(b / st + 1e-9) + 1) * st
    tk = hrs - off
    lbl = []
    for h in hrs:
        d = midnight + _dt.timedelta(hours=float(h))
        lbl.append(d.strftime("%d %b") if st >= 24 or abs(h / 24 - round(h / 24)) < 1e-9 else d.strftime("%H:%M"))
    return tk, lbl


def _trend_time(t, t0, span):
    import datetime as _dt
    if t0 is None:
        return f"{int(t // 3600)}:{int((t % 3600) // 60):02d} h"
    d = t0 + _dt.timedelta(seconds=float(t))
    return d.strftime("%d %b %H:%M") if span > 24 else d.strftime("%H:%M")


def _trend_prep(D):
    """values of a trend image (trend_image, trend_data): per window of the overview the included contractions (rows
    of a window weighted by their number of contractions), time axis, bin of the line, bands and the comments shown;
    None if nothing is shown"""
    names = list(D["names"])
    p = len(names)
    nb = np.asarray(D["nb"], float).ravel()
    use = np.asarray(D["inc"], bool).ravel() & (nb > 0)
    if not use.any() or p == 0:
        return None
    V = np.asarray(D["V"], float).reshape(len(nb), p)[use]
    t = np.asarray(D["t"], float).ravel()[use]
    nb = nb[use]
    wins, g = np.unique(t, return_inverse=True)
    Y = np.full((len(wins), p), np.nan)
    for j in range(p):
        x = V[:, j]
        ok = ~np.isnan(x)
        num = np.bincount(g[ok], weights=x[ok] * nb[ok], minlength=len(wins))
        den = np.bincount(g[ok], weights=nb[ok], minlength=len(wins))
        with np.errstate(invalid="ignore", divide="ignore"):
            Y[:, j] = np.where(den > 0, num / np.where(den > 0, den, 1), np.nan)
    w = float(D.get("w") or 60)
    th = (wins + w / 2) / 3600
    xl = D.get("xlim")
    if xl is not None and len(xl) == 2 and all(np.isfinite(xl)):
        xl = sorted(float(v) / 3600 for v in xl)
    else:
        xl = [float(th.min()), float(th.max())]
    if xl[1] - xl[0] <= 0:
        xl = [xl[0] - 0.5, xl[1] + 0.5]
    span = xl[1] - xl[0]
    bm = 5 if span <= 3 else (10 if span <= 30 else (30 if span <= 24 * 7 else 120))
    B = np.asarray(D.get("bands") if D.get("bands") is not None else np.zeros((0, 3)), float).reshape(-1, 3)
    bl = list(D.get("band_labels") or [])
    P = B[B[:, 2] == 1, :2]
    C0 = [c for c in (D.get("com") or []) if xl[0] * 3600 - 1 <= float(c["t"]) <= xl[1] * 3600 + 1]
    tcs = np.array([float(c["t"]) for c in C0])
    keep = np.zeros(len(C0), bool)
    for k, c in enumerate(C0):  # outside the protocols: the comments
        keep[k] = str(c.get("category", "comment")) == "comment" and not np.any((P[:, 0] <= tcs[k] + 5) &
                                                                                (P[:, 1] >= tcs[k] - 5))
    for a_, b_ in P:  # a protocol: only the comment nearest to its start and to its end (within 5 s)
        for edge in (a_, b_):
            if len(tcs) and np.min(np.abs(tcs - edge)) <= 5:
                keep[int(np.argmin(np.abs(tcs - edge)))] = True
    cm = sorted(((float(c["t"]), " ".join(str(c["text"]).split())) for k, c in enumerate(C0) if keep[k]),
                key=lambda x: x[0])
    nbw = np.bincount(g, weights=nb, minlength=len(wins))  # included contractions per window
    return dict(wins=wins, nb=nbw, Y=Y, th=th, xl=xl, span=span, bm=bm, t0=D.get("t0"), B=B, bl=bl, cm=cm)


def trend_data(D):
    """the data of a trend image (2026-10-14): (T, C). T one row per window with included contractions: t_from (s
    after t0, as D['t']), nBeats (included contractions), the parameters (units of D['units']), bin_from (start of
    the bin of the line, s; line = median of the rows of a bin); C the comments shown (number, t (s), text). Same as
    mda_report('trendData', D)."""
    names = list(D["names"])
    cols = ["t_from", "nBeats"] + names + ["bin_from"]
    R = _trend_prep(D)
    if R is None:
        return pd.DataFrame(columns=cols), pd.DataFrame(columns=["number", "t", "text"])
    T = pd.DataFrame({"t_from": R["wins"], "nBeats": R["nb"]})
    for j, nm in enumerate(names):
        T[nm] = R["Y"][:, j]
    T["bin_from"] = np.floor(R["th"] * 60 / R["bm"]) * R["bm"] * 60
    C = pd.DataFrame({"number": np.arange(1, len(R["cm"]) + 1, dtype=float), "t": [c[0] for c in R["cm"]],
                      "text": [c[1] for c in R["cm"]]})
    return T, C


def trend_image(out, D):
    """trend image (PNG, 150 dpi; 2026-10-14) of one channel: one panel per parameter with the values per window of
    the overview (dots: included contractions; several rows of a window, e.g. beat types or rocker states, weighted by
    their number of contractions) and their median per bin (line: 5 min up to 3 h shown, 10 min up to 30 h, 30 min up
    to 7 days, 2 h beyond), stimulation protocols (light blue, name), periods without signal (grey), comments (purple,
    numbered, list below; during a protocol only those at its start or end). Same figure as mda_report('trend').
    D (dict): title, subtitle, t (window start, s after t0), w (window length, s), nb (contractions), inc (included),
    V (values, one column per parameter), names, units, t0 (datetime of t = 0; None: time in hours), xlim ([from, to]
    s; optional), bands (rows from, to (s), kind: 1 = protocol, 2 = no signal), band_labels, com (list of dicts t (s),
    text, category; comments of this channel and of all channels). Returns out ('' if there is nothing to show)."""
    from matplotlib.figure import Figure
    names = list(D["names"])
    p = len(names)
    R = _trend_prep(D)
    if R is None:
        return ""
    Y, th, xl, span, bm, t0, B, bl, cm = (R[k] for k in ("Y", "th", "xl", "span", "bm", "t0", "B", "bl", "cm"))
    nCm = len(cm)
    nList = min(nCm, 60)
    listRows = math.ceil(nList / 3) + (1 if nCm > nList else 0)
    fw, hT, hS, hP, hG, hX = 11.0, 0.78, 0.26, 1.3, 0.1, 0.5
    hL = (0.12 + 0.15 * listRows) if listRows > 0 else 0.0
    fh = hT + hS + p * hP + (p - 1) * hG + hX + hL
    fig = Figure(figsize=(fw, fh), facecolor="w")
    L, Wd = 0.085, 0.885
    fig.text(0.01, 1 - 0.18 / fh, str(D.get("title", "")), fontsize=11, fontweight="bold", color=_INK, va="center")
    fig.text(0.01, 1 - 0.5 / fh, str(D.get("subtitle", "")), fontsize=7.5, color="#595959", va="center",
             linespacing=1.5)
    tk, tkl = _trend_ticks(xl, t0)
    yTop = fh - hT - hS
    axS = fig.add_axes([L, yTop / fh, Wd, hS / fh])
    axS.set_xlim(xl)
    axS.set_ylim(0, 1)
    axS.axis("off")
    ax = []
    for i in range(p):
        b = yTop - (i + 1) * hP - i * hG
        a = fig.add_axes([L, b / fh, Wd, hP / fh])
        ax.append(a)
        y, un = _trend_units(Y[:, i], D["units"][i])
        xb, yb = _bin_line(th, y, bm)  # line: median per bin of bm minutes
        yl = _trend_panel(a, th, y, xb, yb, B, bl, [c[0] for c in cm], xl, span, 0.0048 if i == 0 else 0, 2.5)
        a.set_xlim(xl)
        a.set_xticks(tk)
        a.set_xticklabels([] if i < p - 1 else tkl)
        a.tick_params(labelsize=8, direction="out", colors="#4D4D4D")
        a.grid(True, alpha=0.25, lw=0.5)
        a.set_axisbelow(False)
        a.set_ylabel(f"{names[i]}\n({un})", fontsize=8)
        a.text(xl[1] - 0.004 * span, yl[1] - 0.02 * (yl[1] - yl[0]), _trend_note(th, y, un), fontsize=7,
               color="#4D4D4D", ha="right", va="top", zorder=5,
               bbox=dict(facecolor="w", edgecolor="none", alpha=0.75, pad=1))
    ax[-1].set_xlabel("clock time" if t0 is not None else "time in the recording (h)", fontsize=8)
    last = [-math.inf, -math.inf]  # numbers in two rows; moved to the right where they would overlap
    for k, (tc, _) in enumerate(cm, start=1):
        x = tc / 3600
        dmin = 0.006 * span * (len(str(k)) + 1)
        r = next((j for j in range(2) if x - last[j] >= dmin), int(np.argmin(last)))
        x = max(x, last[r] + dmin)
        last[r] = x
        axS.text(x, 0.28 + 0.42 * r, str(k), fontsize=7, color=_PURPLE, fontweight="bold", ha="center",
                 va="baseline", clip_on=False)
    if listRows > 0:
        axL = fig.add_axes([0.02, 0, 0.96, hL / fh])
        axL.set_xlim(0, 3)
        axL.set_ylim(0, 1)
        axL.axis("off")
        nr = math.ceil(nList / 3)
        for k in range(nList):
            col, row = k // nr, k % nr
            yy = 1 - (0.08 + row * 0.15) / hL
            s_ = cm[k][1] if len(cm[k][1]) <= 52 else cm[k][1][:51] + "…"
            axL.text(col + 0.005, yy, str(k + 1), fontsize=7, color=_PURPLE, fontweight="bold", va="top")
            axL.text(col + 0.06, yy, f"{_trend_time(cm[k][0], t0, span)}  {s_}", fontsize=7, color=_INK, va="top")
        if nCm > nList:
            axL.text(0.005, 1 - (0.08 + nr * 0.15) / hL, f"… and {nCm - nList} more comments (events of the recording)",
                     fontsize=7, color="#595959", va="top")
    return _save_png(fig, out)


def _save_png(fig, out):
    d = os.path.dirname(out)
    if d:
        os.makedirs(d, exist_ok=True)
    fig.savefig(out, dpi=150, facecolor="w")
    return out


def _bin_line(th, y, bm, grp=None):
    """line of a trend panel: median of y per bin of bm minutes (th: hours), x = centre of the bin (h); NaN between bins
    that are not adjacent and between the groups grp (e.g. slices; None = one group)"""
    th, y = np.asarray(th, float).ravel(), np.asarray(y, float).ravel()
    grp = np.ones(len(th)) if grp is None else np.asarray(grp, float).ravel()
    ok = ~np.isnan(y)
    xs, ys = [], []
    for g in np.unique(grp[ok]):
        s_ = ok & (grp == g)
        ub, gb = np.unique(np.floor(th[s_] * 60 / bm), return_inverse=True)
        yv = y[s_]
        med = np.array([np.median(yv[gb == k]) for k in range(len(ub))])
        idx = np.arange(len(ub)) + np.r_[0, np.cumsum(np.diff(ub) > 1)]  # NaN between bins that are not adjacent
        x = np.full(idx[-1] + 1, np.nan)
        v = x.copy()
        x[idx] = (ub + 0.5) * bm / 60
        v[idx] = med
        if xs:
            xs.append(np.array([np.nan]))
            ys.append(np.array([np.nan]))
        xs.append(x)
        ys.append(v)
    return (np.concatenate(xs), np.concatenate(ys)) if xs else (np.array([]), np.array([]))


def _trend_panel(a, th, y, xb, yb, B, bl, tc, xl, span, name_width, ms):
    """one panel of a trend / course image: bands (B rows from, to (s), kind 1 = protocol (light blue; with its name bl
    if name_width > 0 = width of a character as part of the span), 2 = no signal (grey)), comment lines at tc (s), dots
    (median per window, size ms), line (xb, yb; a point for bins without neighbours); y limits from the 1st and 99th
    percentile of the values; returns the y limits"""
    v = np.r_[y, yb]
    v = np.sort(v[~np.isnan(v)])
    if len(v) == 0:
        yl = [0.0, 1.0]
    else:
        lo = v[max(0, int(round(0.01 * len(v))) - 1)]
        hi = v[max(0, int(round(0.99 * len(v))) - 1)]
        if hi <= lo:
            d = max(1.0, abs(lo)) * 0.1
            lo, hi = lo - d, hi + d
        yl = [lo - 0.08 * (hi - lo), hi + 0.12 * (hi - lo)]
    for k in range(len(B)):
        a.axvspan(B[k, 0] / 3600, B[k, 1] / 3600, color=_PROT if B[k, 2] == 1 else _GAP, lw=0, zorder=0)
        if name_width > 0 and B[k, 2] == 1 and k < len(bl):  # name, shortened to the width of the band
            nch = int((min(B[k, 1] / 3600, xl[1]) - max(B[k, 0] / 3600, xl[0])) / span / name_width)
            lb = str(bl[k]) if len(str(bl[k])) <= nch else str(bl[k])[:max(0, nch - 1)] + "…"
            if nch >= 4:
                a.text(max(B[k, 0] / 3600, xl[0]), yl[1], " " + lb, fontsize=6.5, color="#33619E", va="top",
                       clip_on=True)
    for tc_ in tc:
        a.axvline(tc_ / 3600, color=_PURPLE, ls=":", lw=0.7, zorder=1)
    a.plot(th, y, ".", color=_DOT, ms=ms, zorder=2)
    a.plot(xb, yb, "-", color=_BLUE, lw=1.3, zorder=3)
    if len(yb):  # bins without neighbours: a point
        pad = np.r_[np.nan, yb, np.nan]
        iso = ~np.isnan(yb) & np.isnan(pad[:-2]) & np.isnan(pad[2:])
        a.plot(xb[iso], yb[iso], "o", color=_BLUE, ms=2.5, zorder=3)
    a.set_ylim(yl)
    return yl


# ------------------------------------------------------------------------------------------------ course images
_LAST24, _SLICE, _RED_BAR = "#FFF5C7", "#4D4D4D", "#C62828"


def _slice_of_windows(t, S):
    """number of the slice (rows from, to, number of S, in the order of time) of the windows starting at t"""
    t = np.asarray(t, float).ravel()
    S = np.asarray(S if S is not None else np.zeros((0, 3)), float).reshape(-1, 3)
    if not len(S):
        return np.ones(len(t))
    i = np.sum(t[:, None] >= S[:, 0][None, :] - 1e-6, axis=1)
    i[i < 1] = 1
    return S[i - 1, 2]


def _course_prep(D):
    """values of a course image (course_image, course_data): R = the whole time course (_trend_prep of all windows,
    D['xlim']), R24 = the last 24 h (_trend_prep of the windows in D['last24'], None if none); both with the slice of
    every window (D['slices']: rows from, to (s), number)"""
    R = _trend_prep(D)
    if R is None:
        return None, None
    R["slice"] = _slice_of_windows(R["wins"], D.get("slices"))
    a, b = (float(v) for v in D["last24"])
    t = np.asarray(D["t"], float).ravel()
    c = t + float(D.get("w") or 60) / 2  # windows with their centre in the last 24 h
    k = (c >= a) & (c <= b)
    if not k.any():
        return R, None
    p = len(list(D["names"]))
    D24 = dict(D, t=t[k], nb=np.asarray(D["nb"], float).ravel()[k], inc=np.asarray(D["inc"], bool).ravel()[k],
               V=np.asarray(D["V"], float).reshape(len(t), p)[k], xlim=[a, b])
    R24 = _trend_prep(D24)
    if R24 is not None:
        R24["slice"] = _slice_of_windows(R24["wins"], D.get("slices"))
    return R, R24


def _unique_names(names):
    """as matlab.lang.makeUniqueStrings: later duplicates get _1, _2, ..."""
    out, seen = [], set()
    for n in names:
        m, k = n, 0
        while m in seen:
            k += 1
            m = f"{n}_{k}"
        seen.add(m)
        out.append(m)
    return out


def course_data(D):
    """the data of a course image (2026-10-15): (Tc, Tl, Tm). Tc one row per slice and bin of the whole course (slice,
    bin_from (s after t0), nBeats = included contractions, the parameters = median of the windows of the bin,
    binMinutes), Tl the windows of the last 24 h (slice, t_from, nBeats, the parameters: median per window), Tm the
    comments numbered in the image (number, t, text). Same as mda_report('courseData', D)."""
    names = list(D["names"])
    cc = _unique_names(["slice", "bin_from", "nBeats"] + names + ["binMinutes"])
    cl = _unique_names(["slice", "t_from", "nBeats"] + names)
    Tc, Tl = pd.DataFrame(columns=cc), pd.DataFrame(columns=cl)
    Tm = pd.DataFrame(columns=["number", "t", "text"])
    R, R24 = _course_prep(D)
    if R is None:
        return Tc, Tl, Tm
    bi = np.floor(R["th"] * 60 / R["bm"])
    keys = sorted(set(zip(R["slice"].tolist(), bi.tolist())))
    pos = {k: i for i, k in enumerate(keys)}
    g = np.array([pos[(a, b)] for a, b in zip(R["slice"].tolist(), bi.tolist())])
    n = len(keys)
    M = np.full((n, len(names)), np.nan)
    for j in range(len(names)):
        for q in range(n):
            v = R["Y"][g == q, j]
            v = v[~np.isnan(v)]
            if len(v):
                M[q, j] = np.median(v)
    data = np.column_stack([np.array([k[0] for k in keys]), np.array([k[1] for k in keys]) * R["bm"] * 60,
                            np.bincount(g, weights=R["nb"], minlength=n), M, np.full(n, float(R["bm"]))])
    Tc = pd.DataFrame(data, columns=cc)
    if R24 is None:
        return Tc, Tl, Tm
    Tl = pd.DataFrame(np.column_stack([R24["slice"], R24["wins"], R24["nb"], R24["Y"]]), columns=cl)
    Tm = pd.DataFrame({"number": np.arange(1, len(R24["cm"]) + 1, dtype=float), "t": [c[0] for c in R24["cm"]],
                       "text": [c[1] for c in R24["cm"]]})
    return Tc, Tl, Tm


def _course_ticks(xl, D):
    """ticks of the whole time course: clock time / dates; at midnight with the day in culture (D['day_base'],
    datetime of day 0) below"""
    import datetime as _dt
    tk, lbl = _trend_ticks(xl, D.get("t0"))
    base = D.get("day_base")
    if base is None or D.get("t0") is None:
        return tk, lbl
    base_day = _dt.datetime(base.year, base.month, base.day)
    for k, h in enumerate(tk):
        d = D["t0"] + _dt.timedelta(hours=float(h))
        dr = (d + _dt.timedelta(seconds=30)).replace(second=0, microsecond=0)
        if dr.hour == 0 and dr.minute == 0:
            lbl[k] = f"{dr:%d %b}\nday {(dr - base_day).days}"
    return tk, lbl


def _course_marks(a, S, Rd, yl, labels, xl):
    """slice changes (dashed line, 'slice k' if labels) and recordings with red flags (red bar at the bottom)"""
    for k in range(1, len(S)):
        x = S[k, 0] / 3600
        if x < xl[0] or x > xl[1]:
            continue
        a.plot([x, x], yl, "--", color=_SLICE, lw=1.0, zorder=4)
        if labels:
            a.text(x, yl[0] + 0.08 * (yl[1] - yl[0]), f" slice {int(S[k, 2])}", fontsize=7, color=_SLICE,
                   fontweight="bold", va="bottom", clip_on=True, zorder=5)
    for a_, b_ in Rd:
        lo, hi = max(a_ / 3600, xl[0]), min(b_ / 3600, xl[1])
        if hi > lo:
            a.axvspan(lo, hi, ymin=0, ymax=0.05 / 1.0, color=_RED_BAR, lw=0, zorder=4)


def course_image(out, D):
    """course image (PNG, 150 dpi; 2026-10-15) of one channel of a series of recordings (slice register): one row per
    parameter, left the whole time course of the series (dots = values per window of the overview, line = median per
    bin of each slice: 30 min up to 7 days, 2 h beyond; slice changes dashed with 'slice k'; the last 24 h shaded
    yellow; recordings with red flags as red bars at the bottom), right the last 24 h (as the trend image of a
    recording: 10-min bins, protocols, periods without signal, numbered comments with a list below). Same figure as
    mda_report('course').
    D (dict): as for trend_image (title, subtitle, t, w, nb, inc, V, names, units, t0, xlim = [0, end of the series]
    (s), bands, band_labels, com) and slices (rows from, to (s), number), last24 ([from, to] s), day_base (datetime of
    day 0 of the culture; None: no day numbers), red (rows from, to (s): recordings with red flags). Returns out ('' if
    there is nothing to show)."""
    import datetime as _dt
    from matplotlib.figure import Figure
    R, R24 = _course_prep(D)
    if R is None:
        return ""
    names = list(D["names"])
    p = len(names)
    cm = R24["cm"] if R24 is not None else []
    nCm = len(cm)
    nList = min(nCm, 60)
    listRows = math.ceil(nList / 3) + (1 if nCm > nList else 0)
    fw, hT, hS, hP, hG, hX = 11.0, 0.78, 0.42, 1.3, 0.1, 0.62
    hL = (0.12 + 0.15 * listRows) if listRows > 0 else 0.0
    fh = hT + hS + p * hP + (p - 1) * hG + hX + hL
    fig = Figure(figsize=(fw, fh), facecolor="w")
    L1, W1, L2, W2 = 0.075, 0.565, 0.70, 0.285
    fig.text(0.01, 1 - 0.18 / fh, str(D.get("title", "")), fontsize=11, fontweight="bold", color=_INK, va="center")
    fig.text(0.01, 1 - 0.5 / fh, str(D.get("subtitle", "")), fontsize=7.5, color="#595959", va="center",
             linespacing=1.5)
    xl, span, t0 = R["xl"], R["span"], D.get("t0")
    xl24 = [float(D["last24"][0]) / 3600, float(D["last24"][1]) / 3600]
    s24 = xl24[1] - xl24[0]
    yTop = fh - hT - hS
    when = (lambda h: (t0 + _dt.timedelta(hours=h) + _dt.timedelta(seconds=0.5)).strftime("%d %b %H:%M")) \
        if t0 is not None else (lambda h: f"{h:.1f} h")
    fig.text(L1, (yTop + 0.82 * hS) / fh, f"whole time course: {when(xl[0])} to {when(xl[1])} ({span / 24:.1f} days)",
             fontsize=8, fontweight="bold", color=_INK, va="center")
    fig.text(L2, (yTop + 0.82 * hS) / fh, f"last 24 h (to {when(xl24[1])})", fontsize=8, fontweight="bold",
             color=_INK, va="center")
    axS = fig.add_axes([L2, yTop / fh, W2, hS / fh])
    axS.set_xlim(xl24)
    axS.set_ylim(0, 1)
    axS.axis("off")
    tk, tkl = _course_ticks(xl, D)
    tk2, tkl2 = _trend_ticks(xl24, t0, 5)
    S = np.asarray(D.get("slices") if D.get("slices") is not None else np.zeros((0, 3)), float).reshape(-1, 3)
    Rd = np.asarray(D.get("red") if D.get("red") is not None else np.zeros((0, 2)), float).reshape(-1, 2)
    a1, a2 = [], []
    for i in range(p):
        b = yTop - (i + 1) * hP - i * hG
        y, un = _trend_units(R["Y"][:, i], D["units"][i])
        a = fig.add_axes([L1, b / fh, W1, hP / fh])
        a1.append(a)
        xb, yb = _bin_line(R["th"], y, R["bm"], R["slice"])
        yl = _trend_panel(a, R["th"], y, xb, yb, R["B"], R["bl"], [], xl, span, 0, 1.5)
        a.axvspan(xl24[0], xl24[1], color=_LAST24, lw=0, zorder=-1)
        _course_marks(a, S, Rd, yl, i == 0, xl)
        a.set_xlim(xl)
        a.set_xticks(tk)
        a.set_xticklabels([] if i < p - 1 else tkl)
        a.tick_params(labelsize=7.5 if i == p - 1 else 8, direction="out", colors="#4D4D4D")
        a.tick_params(axis="y", labelsize=8)
        a.grid(True, alpha=0.25, lw=0.5)
        a.set_axisbelow(False)
        a.set_ylabel(f"{names[i]}\n({un})", fontsize=8)
        a.text(xl[1] - 0.004 * span, yl[1] - 0.02 * (yl[1] - yl[0]), _trend_note(R["th"], y, un), fontsize=7,
               color="#4D4D4D", ha="right", va="top", zorder=6,
               bbox=dict(facecolor="w", edgecolor="none", alpha=0.75, pad=1))
        a = fig.add_axes([L2, b / fh, W2, hP / fh])
        a2.append(a)
        a.set_xlim(xl24)
        a.set_xticks(tk2)
        a.set_xticklabels([] if i < p - 1 else tkl2)
        a.tick_params(labelsize=8, direction="out", colors="#4D4D4D")
        a.grid(True, alpha=0.25, lw=0.5)
        if R24 is None:
            a.set_yticks([])
            a.text(0.5, 0.5, "no contractions in the last 24 h", transform=a.transAxes, fontsize=7.5,
                   color="#595959", ha="center")
            continue
        y2, _ = _trend_units(R24["Y"][:, i], D["units"][i])
        xb2, yb2 = _bin_line(R24["th"], y2, R24["bm"], R24["slice"])
        yl2 = _trend_panel(a, R24["th"], y2, xb2, yb2, R24["B"], R24["bl"], [c[0] for c in cm], xl24, s24,
                           0.0048 * W1 / W2 if i == 0 else 0, 2)
        _course_marks(a, S, Rd, yl2, False, xl24)
        a.set_xlim(xl24)
        a.set_axisbelow(False)
        a.text(xl24[1] - 0.006 * s24, yl2[1] - 0.02 * (yl2[1] - yl2[0]), _trend_note(R24["th"], y2, un), fontsize=6.5,
               color="#4D4D4D", ha="right", va="top", zorder=6,
               bbox=dict(facecolor="w", edgecolor="none", alpha=0.75, pad=1))
    a1[-1].set_xlabel("date (day in culture)" if D.get("day_base") is not None else "date", fontsize=8)
    a2[-1].set_xlabel("clock time", fontsize=8)
    last = [-math.inf] * 3  # comment numbers in three rows; moved to the right where they would overlap
    for k, (tc, _) in enumerate(cm, start=1):
        x = tc / 3600
        dmin = 0.006 * W1 / W2 * s24 * (len(str(k)) + 1)
        r = next((j for j in range(3) if x - last[j] >= dmin), int(np.argmin(last)))
        x = max(x, last[r] + dmin)
        last[r] = x
        axS.text(x, 0.04 + 0.22 * r, str(k), fontsize=7, color=_PURPLE, fontweight="bold", ha="center", va="baseline",
                 clip_on=False)
    if listRows > 0:  # list of the comments of the last 24 h
        axL = fig.add_axes([0.02, 0, 0.96, hL / fh])
        axL.set_xlim(0, 3)
        axL.set_ylim(0, 1)
        axL.axis("off")
        nr = math.ceil(nList / 3)
        for k in range(nList):
            col, row = k // nr, k % nr
            yy = 1 - (0.08 + row * 0.15) / hL
            s_ = cm[k][1] if len(cm[k][1]) <= 52 else cm[k][1][:51] + "…"
            axL.text(col + 0.005, yy, str(k + 1), fontsize=7, color=_PURPLE, fontweight="bold", va="top")
            axL.text(col + 0.06, yy, f"{_trend_time(cm[k][0], t0, 25)}  {s_}", fontsize=7, color=_INK, va="top")
        if nCm > nList:
            axL.text(0.005, 1 - (0.08 + nr * 0.15) / hL, f"… and {nCm - nList} more comments in the last 24 h",
                     fontsize=7, color="#595959", va="top")
    return _save_png(fig, out)


_STATUS_CELL = (("beating at end of data", "#E3F5E6", "beating"),
                ("not beating at end of data", "#FCE0DB", "not beating"),
                ("removed", "#EBEBEB", "removed"), ("replaced (other sliceID)", "#EBEBEB", "replaced"),
                ("signal lost", "#FFF0D6", "signal lost"))


def experiment_image(out, D):
    """overview image of an experiment (PNG, 150 dpi; 2026-10-15): one row per series (setup), one column per channel;
    per cell the amplitude (median per bin of the included contractions) over the whole time course of the experiment,
    slice changes (dashed), the last 24 h (yellow), background = status of the last slice at the end of its data (green
    beating, red not beating, grey removed / replaced, orange signal lost, white no slice), texts: last amplitude,
    change in the last 24 h, % of the maximum of the slice, number of the slice, recordings with red flags (red frame,
    number). Same figure as mda_report('experiment').
    D (dict): title, subtitle, rows (labels of the series), cols (channels), t0 (datetime of x = 0), xl ([0, end] h),
    last24 ([from, to] h), report (name of the PDF report, legend), cells (list of dicts r, c (0-based), t (h), y (uN),
    sb (slice changes, h), status, k, amp, pct, d24, nRed). Returns out ('' if there is nothing to show)."""
    import datetime as _dt
    from matplotlib.figure import Figure
    from matplotlib.patches import Rectangle
    rows, cols = list(D["rows"]), list(D["cols"])
    nr, nc = len(rows), len(cols)
    if not nr or not nc:
        return ""
    cwI, chI, lwI, hT, hH, hB = 1.3, 0.88, 1.45, 0.78, 0.25, 0.8
    fw, fh = max(9.0, lwI + nc * cwI + 0.15), hT + hH + nr * chI + hB
    fig = Figure(figsize=(fw, fh), facecolor="w")
    fig.text(0.01, 1 - 0.18 / fh, str(D.get("title", "")), fontsize=11, fontweight="bold", color=_INK, va="center")
    fig.text(0.01, 1 - 0.5 / fh, str(D.get("subtitle", "")), fontsize=7.5, color="#595959", va="center",
             linespacing=1.5)
    for j, c in enumerate(cols):
        fig.text((lwI + (j + 0.5) * cwI) / fw, (fh - hT - hH / 2) / fh, f"ch {c}", fontsize=8, fontweight="bold",
                 ha="center", va="center", color=_INK)
    for i, nm in enumerate(rows):
        fig.text(0.12 / fw, (fh - hT - hH - (i + 0.5) * chI) / fh, nm, fontsize=8, fontweight="bold", va="center",
                 color=_INK)
    xl = [float(v) for v in D["xl"]]
    t0 = D.get("t0")
    xm = []
    if t0 is not None:  # midnights
        d = _dt.datetime(t0.year, t0.month, t0.day) + _dt.timedelta(days=1)
        while (d - t0).total_seconds() / 3600 <= xl[1]:
            xm.append((d - t0).total_seconds() / 3600)
            d += _dt.timedelta(days=1)
    l24 = [float(v) for v in D["last24"]]
    st = {s_: (col, sh) for s_, col, sh in _STATUS_CELL}
    cells = {(int(x["r"]), int(x["c"])): x for x in D.get("cells") or []}
    for i in range(nr):
        for j in range(nc):
            ax = fig.add_axes([(lwI + j * cwI + 0.04) / fw, (fh - hT - hH - (i + 1) * chI + 0.08) / fh,
                               (cwI - 0.08) / fw, (chI - 0.16) / fh])
            ax.set_xlim(xl)
            ax.set_xticks([])
            ax.set_yticks([])
            for sp in ax.spines.values():
                sp.set_color("#BFBFBF")
            C = cells.get((i, j))
            if C is None:
                ax.set_ylim(0, 1)
                ax.text(0.5, 0.5, "no slice", transform=ax.transAxes, fontsize=6.5, color="#999999", ha="center",
                        va="center")
                continue
            col, sl = st.get(C["status"], ("white", C["status"]))
            ax.set_facecolor(col)
            y = np.asarray(C["y"], float)
            v = np.sort(y[~np.isnan(y)])
            top = float(v[max(0, int(round(0.99 * len(v))) - 1)]) if len(v) else 1.0
            top = top if top > 0 else 1.0
            ax.set_ylim(-0.4 * top, 1.6 * top)  # line between the texts at the top and at the bottom
            ax.axvspan(l24[0], l24[1], color=_LAST24, alpha=0.8, lw=0, zorder=0)
            for x in xm:
                ax.axvline(x, color="#D1D1D1", lw=0.4, zorder=1)
            for x in C["sb"]:
                ax.axvline(x, color=_SLICE, ls="--", lw=0.8, zorder=2)
            ax.plot(C["t"], y, "-", color=_BLUE, lw=1.0, zorder=3)
            pad = np.r_[np.nan, y, np.nan]  # bins without neighbours: a point
            iso = ~np.isnan(y) & np.isnan(pad[:-2]) & np.isnan(pad[2:])
            ax.plot(np.asarray(C["t"], float)[iso], y[iso], ".", color=_BLUE, ms=3, zorder=3)
            if np.isfinite(C["amp"]):
                ax.text(0.03, 0.95, f"{_fmt_sig(float(C['amp']))} µN", transform=ax.transAxes, fontsize=6.5, va="top",
                        color=_INK)
            if np.isfinite(C["d24"]):
                ax.text(0.97, 0.95, f"24 h {C['d24']:+.0f} %", transform=ax.transAxes, fontsize=6.5, va="top",
                        ha="right", color=_INK)
            ax.text(0.03, 0.05, sl, transform=ax.transAxes, fontsize=6.5, va="bottom", color=_INK)
            s_ = f"slice {int(C['k'])}" if C["k"] > 1 else ""
            if np.isfinite(C["pct"]):
                s_ = f"{s_}  {C['pct']:.0f} %".strip()
            ax.text(0.97, 0.05, s_, transform=ax.transAxes, fontsize=6, va="bottom", ha="right", color="#595959")
            if C["nRed"] > 0:  # red frame, number above it
                for sp in ax.spines.values():
                    sp.set_color(_RED_BAR)
                    sp.set_linewidth(1.6)
                ax.text(0.5, 1.03, f" {int(C['nRed'])} red ", transform=ax.transAxes, fontsize=6.5, fontweight="bold",
                        color=_RED_BAR, va="bottom", ha="center", zorder=6, clip_on=False,
                        bbox=dict(facecolor="w", edgecolor=_RED_BAR, lw=0.8, pad=0.8))
    y0 = (hB - 0.2) / fh
    x = 0.12
    for s_, col, sh in (_STATUS_CELL[0], _STATUS_CELL[1], _STATUS_CELL[2], _STATUS_CELL[4]):
        fig.patches.append(Rectangle((x / fw, y0 - 0.06 / fh), 0.16 / fw, 0.12 / fh, facecolor=col, edgecolor="#B3B3B3",
                                     transform=fig.transFigure, figure=fig))
        fig.text((x + 0.21) / fw, y0, sh, fontsize=7, color=_INK, va="center")
        x += 0.32 + 0.065 * len(sh)
    fig.patches.append(Rectangle((x / fw, y0 - 0.06 / fh), 0.16 / fw, 0.12 / fh, facecolor=_LAST24, edgecolor="none",
                                 transform=fig.transFigure, figure=fig))
    fig.text((x + 0.21) / fw, y0, "last 24 h", fontsize=7, color=_INK, va="center")
    rep = f", {D['report']}" if D.get("report") else ""
    fig.text(0.12 / fw, y0 - 0.2 / fh, f"blue: amplitude (median per bin);  dashed: new slice;  red frame: recordings "
             f"with red flags (check the analysis{rep})", fontsize=7, color=_INK, va="center")
    fig.text(0.12 / fw, y0 - 0.4 / fh, "status = end of the data of the last slice; texts: last amplitude, change in "
             "the last 24 h (first vs. last 2 h), number of the slice, last amplitude in % of the maximum of the slice",
             fontsize=7, color="#595959", va="center")
    return _save_png(fig, out)
