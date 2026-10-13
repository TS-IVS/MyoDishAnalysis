# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Analysis report (PDF): which analyses should be checked, with traces and the commands to open them in the GUI.
Port of mda_report.m (same flags and pages).

    R = report_flags(S, C, status=None, **flags)         flags per channel (DataFrame)
    R = write_report(recordings, 'report.pdf', title=..., subtitle=[...], notice=[...], **flags)

Written by the watcher after every pass with analysed recordings (results_folder/reports/mda_report_<date>_<time>.pdf,
option report=True), by myodish_analysis with an output file (<output>_report.pdf, option report) and by the GUI on
request (menu File).

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
    F  stimulus frequency > stim_frequency (10 Hz) in a range (median stimulus interval; implausible: status channel
       probably misread; 2026-10-13)
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
2026-10-13)
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
RED_CODES = (("inverted", "I"), ("noise", "N"), ("large", "S"), ("delay", "D"), ("frequency", "F"))
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


def report_flags(S, C=None, status=None, **flags):
    """one row per channel: counts, values and flags (columns flags = codes, red / yellow = descriptions)."""
    fl = _flags(flags)
    status = dict(status or {})
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
                 **flags):
    """writes the PDF; returns the flags of all channels (DataFrame: recording, file, open, ..., window_from,
    window_to, matlab, python; window and commands for the channels with red flags). notice: lines shown in red at
    the top of the first page (watcher: recordings analysed with another version or other options)."""
    import matplotlib
    from matplotlib.backends.backend_pdf import PdfPages
    from .write_results import mda_version
    fl = _flags(flags)
    recs = []
    for rec in recordings:
        R = rec.get("R")  # flags computed by the caller (e.g. the watcher: C kept only for channels to check)
        R = report_flags(rec.get("S"), rec.get("C"), rec.get("status"), **fl) if R is None else R.copy()
        R.insert(0, "recording", rec["name"])
        R["window_from"], R["window_to"], R["matlab"], R["python"] = math.nan, math.nan, "", ""
        opn = rec.get("open") or rec.get("file") or ""
        for i in np.flatnonzero((R["level"] == "check").to_numpy()):
            a, b = report_window(rec.get("C"), int(R.at[i, "channel"]), R.at[i, "flags"], window_s)
            R.at[i, "window_from"], R.at[i, "window_to"] = a, b
            R.at[i, "matlab"], R.at[i, "python"] = gui_commands(opn, int(R.at[i, "channel"]), a, b)
        recs.append(dict(rec, R=R, notes=list(rec.get("notes") or []), open=opn))
    allR = pd.concat([r["R"] for r in recs], ignore_index=True) if recs else report_flags(None)
    check = [r for r in recs if (r["R"]["level"] == "check").any() or r["notes"]]
    def order(r):  # the most red flags, then the highest noise index first
        chk = r["R"][r["R"]["level"] == "check"]
        ni = chk["noiseIndex"].to_numpy(float) if "noiseIndex" in chk.columns else np.array([])
        return (-sum(sum(ch in RED_LETTERS for ch in str(f)) for f in chk["flags"]),
                -(float(np.nanmax(ni)) if ni.size and np.any(~np.isnan(ni)) else 0.0))
    detail = sorted([r for r in recs if (r["R"]["level"] == "check").any()], key=order)
    detail = detail[:max_pages]
    os.makedirs(os.path.dirname(os.path.abspath(out)) or ".", exist_ok=True)
    with matplotlib.rc_context({"font.size": 7}), \
            PdfPages(out, metadata={"Title": title, "Creator": f"MyoDishAnalysis {mda_version()}"}) as pdf:
        _overview_pages(pdf, recs, title, subtitle, fl, len(detail), notice)
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


def _overview_pages(pdf, recs, title, subtitle, fl, nDetail, notice=()):
    nRed = sum(int((r["R"]["level"] == "check").sum()) for r in recs)
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
        fig.text(0.05, y - 0.004, f"{len(recs)} recording(s), {nSl} channel(s) with a slice: {nRed} to check (red"
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
            ax.text(0, yk - rh * 0.2, _short(rec["name"], 62), fontsize=6, va="top")
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
        lines.append((_short(rec["name"], 110), "b"))
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
