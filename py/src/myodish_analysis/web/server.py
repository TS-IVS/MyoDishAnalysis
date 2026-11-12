# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""MyoDishAnalysis in the browser (2026-11-12, first step): the results of a results folder of the watcher and the
state of the watcher, served by a small local web server. Standard library only.

    mda-web RESULTS [--raw RAW] [--port 8765] [--host 127.0.0.1] [--no-browser]
    serve(results_folder, raw_folder=None, host="127.0.0.1", port=8765, open_browser=True)

The server runs on the computer that holds the data and answers on 127.0.0.1 only, unless another host is given: with
--host 0.0.0.0 every computer that reaches this one can read the results and start a pass, and there is no login. Use
that inside a trusted network only.

Pages (one file, static/index.html): the start page, the results browser (one row per recording and channel with its
flags in words, filters, search; a row shows the texts of the flags, the trend image of the channel, the report of the
experiment and the command that opens the place in the desktop GUI), the watcher (what is analysed, the reports of
the last passes, one pass now), the settings of the passes started from the page (Basics: the settings people change,
in plain words; Expert: every advanced setting, from the list of the desktop GUI) and the help.

Interface (JSON unless noted):
    GET  /api/state                 results and raw folder, version, names of the flags, legend
    GET  /api/results               rows of the results browser, files without current flags
    POST /api/flags/compute         computes the missing flags from the result files (flags_table(compute=True))
    GET  /api/watcher               counts of the index by status, reports of the passes, state of a pass started here
    GET  /api/report?name=...       text of one pass report (results/reports/<name>)
    POST /api/watcher/run           {"raw": folder, "dry_run": bool, "other_raw": bool, "options": {...}, "again":
                                    bool}: one pass in the background (watch) with the settings of the page; what it
                                    prints is in run.output of the state. options: which recordings (reanalyze,
                                    retry_errors, include, exclude, from_date, max_files, min_file_age_minutes,
                                    workers). Refused until confirmed, unless it only lists: a pass from another raw
                                    folder than the one of the last pass (code "otherRaw", other_raw) and a pass that
                                    analyzes recordings again (code "again", again)
    GET  /api/settings              the settings page: fields (value as shown, default), basics, what differs
    POST /api/settings              {"values": {option: value as shown}, "base": "standard" | ""}: saves them in
                                    <results>/mda_web_settings.csv (settings.save_settings); passes started from the
                                    page use this file
    POST /api/settings/last         the page filled with the settings of the newest analysis (not saved)
    POST /api/settings/file         {"text": content of a settings file .csv, "name"}: the page filled with them
    GET  /api/help                  flags with the thresholds in use, guides at hand
    GET  /api/studies               the studies of the results folder, its series, columns and settings of a design
    GET  /api/study?name=...        one study: design, images, methods text, files, tables
    GET  /api/analysis?id=...       one analysis of timepoints outside a study or one pool (ids in /api/studies)
    POST /api/study/run             {"name", "settings": {key: value}, "rows": [slice, ...]}: study.study in the
                                    background, into <results>/studies/<name>
    POST /api/study/design          {"data": base64 of a design table .xlsx / .csv, "name"}: rows and settings
    GET  /api/study/template        an empty design table (.xlsx)
    GET  /api/job                   state of the study started here (running, error, what it printed)
    GET  /docs/<name>.pdf           the guides of a source checkout (docs/)
    GET  /files/<path>              a file of the results folder (images, PDF reports, tables), nothing outside it

With the default host only requests addressed to this computer are answered (Host 127.0.0.1 or localhost).
"""
from __future__ import annotations

import argparse
import contextlib
import datetime as _dt
import io
import json
import math
import mimetypes
import os
import re
import sys
import threading
import traceback
import urllib.parse
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

_STATIC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
_REPORT_RX = re.compile(r"^mda_report_[0-9_\-]+\.txt$")
_SERVED = {".png", ".jpg", ".pdf", ".txt", ".csv", ".gz", ".xlsx", ".json"}
_LOCAL_HOSTS = ("127.0.0.1", "localhost", "::1")
_MAX_BODY = 2000000   # bytes of a request (a settings file is a few kB)
SETTINGS_NAME = "mda_web_settings.csv"   # settings of the passes started from the page (settings.save_settings)

# the settings page. Expert: the rows of the advanced settings window of the desktop GUI (advanced.ROWS) and the
# options of its main window (_EXTRA_ROWS, same columns); the options of one recording (threshold, zero force,
# reference beat, calibration, ...) are not settings of a folder and keep their values. Basics (_BASICS): the settings
# people change, in plain words: (title, what it does, option names).
_TAB_TITLES = {"Assignment": "Stimulus and contraction", "Detection": "Detection",
               "Noise / artifacts": "Noise and artifacts", "Rocker rules": "Rocker: which contractions to keep",
               "Rocker filter": "Rocker: removing the wave", "Signal": "Signal and spikes",
               "Protocols": "Stimulation protocols", "Export": "Export"}
_EXTRA_ROWS = (
    ("rockerFilter", "Remove the rocker artifact", "check", None,
     "the periodic wave that the rocker adds to the signal is removed while the rocker moves (the automatic analysis "
     "does this in chunks of 30 min; result per chunk in the table rockerFilter)", 1, "", "Rocker filter", False),
    ("detection", "Uncertain contractions", "popup",
     (("counted and marked (sensitive)", "sensitive"), ("not counted (specific)", "specific")),
     "a contraction is uncertain if it is neither locked to the stimuli nor large. sensitive: uncertain contractions "
     "are counted and marked (column uncertain); specific: they are not counted", 1, "", "Detection", False),
    ("beats", "Contractions included", "popup",
     (("all", "all"), ("only those that follow a stimulus", "stimulated")),
     "the others stay in the table with included = false", 1, "", "Detection", False),
    ("rocker", "Rocker during the included contractions", "popup",
     (("any", "any"), ("at rest", "stopped"), ("moving", "moving")),
     "at rest: rocker at rest from the diastolic level to 90 % relaxation; the others stay in the table with "
     "included = false", 1, "", "Rocker rules", False),
    ("halfRateInterpolation", "Sensors at half the recording rate", "check", None,
     "channels whose sensor measures at half the recording rate: the repeated values are replaced by a linear "
     "interpolation, so that the timing does not depend on the phase of the pairs", 1, "", "Signal", False),
)
_BASICS = (
    ("Remove the rocker artifact", "The periodic wave of the rocker is taken out of the signal while the rocker "
     "moves", ("rockerFilter",)),
    ("Where the stimuli come from", "MyoDish, an external stimulator, or decided from the recording",
     ("externalTrigger",)),
    ("Smallest contraction that counts", "Automatic threshold as a share of the typical contraction, and its lower "
     "end", ("relThreshold", "minThreshold")),
    ("Uncertain contractions", "Small contractions that do not follow the pacing: counted and marked, or left out",
     ("detection",)),
    ("Shortest time between two contractions", "Peaks closer than this are one contraction", ("minBeatInterval",)),
    ("Where the diastolic force is measured", "Just before the pulse, or at the lowest point before the contraction",
     ("diastolicLevel",)),
    ("How the program knows that the rocker moves", "From the recording, from the log, or whichever is there",
     ("rockerSource",)),
    ("Smoothing of the signal", "Moving median and moving mean. Zero means none",
     ("medianFilterMs", "meanFilterMs")),
    ("Remove spikes", "Jumps that no slice can produce, e.g. when a chamber is taken out or put in",
     ("spikeRemoval",)),
    ("Notice a signal that is upside down", "A sensor that does not work properly can turn the contractions over",
     ("invertedCheck",)),
    ("Channels paced with an irregular rhythm", "Missed beats and a variable amplitude are expected there (channel "
     "numbers, e.g. 1 3 5)", ("arrhythmicChannels",)),
    ("Protocols: beats per frequency step", "How many beats at the end of a step are the steady state",
     ("steadyStateBeats",)),
)
_DOCS = (("MyoDishAnalysis_quickstart_watcher.pdf", "Quick start: the automatic analysis (1 page)"),
         ("MyoDishAnalysis_quickstart_GUI.pdf", "Quick start: the desktop program (2 pages)"),
         ("MyoDishAnalysis_settings_guide.pdf", "Settings guide: every setting, with figures"))


class App:
    """state of one server: the folders and the pass started from the page (at most one at a time)"""

    def __init__(self, results_folder, raw_folder=None, host="127.0.0.1"):
        self.results = os.path.abspath(results_folder)
        self.raw = os.path.abspath(raw_folder) if raw_folder else ""
        self.local_only = host in _LOCAL_HOSTS   # then only requests addressed to this computer are answered
        self.lock = threading.Lock()
        self.run = dict(running=False, started="", finished="", raw="", dry_run=False, report="", error="")
        self.job = dict(running=False, kind="", name="", started="", finished="", error="", output="")   # a study

    # ------------------------------------------------------------------------------------------- data
    def state(self):
        from .. import report
        from ..write_results import mda_version
        return dict(results=self.results, raw=self.raw or self.raw_of_last_report(), version=mda_version(),
                    hasIndex=os.path.isfile(os.path.join(self.results, "mda_index.csv")),
                    studies=self._n_studies(),
                    names=[dict(letter=c, group=g, name=n) for c, g, n in report.FLAG_NAMES],
                    legend=report.short_legend(), minBeats=report.FLAG_DEFAULTS["min_beats"])

    def results_rows(self):
        """one row per analysed recording and channel (flags of the current analyses), one per recording without"""
        from .. import report
        from ..watch import flags_table, results_of
        X, T, missing = flags_table(self.results, compute=False)
        msg = dict(zip(X["file"], X["message"].fillna("").astype(str)))
        st = dict(zip(X["file"], X["status"].astype(str)))
        ana = dict(zip(X["file"], X["analyzed"].astype(str)))
        rows, have, folders = [], set(), {}
        for r in T.to_dict("records"):
            f = str(r["file"])
            have.add(f)
            if f not in folders:
                folders[f] = self._links(f, results_of(self.results, f)[0])
            ch = int(r["channel"])
            L = folders[f]
            img = L["images"].get(ch, "")
            rows.append(dict(file=f, channel=ch, label=_s(r["label"]), status=_s(r["status"]),
                             nDetected=_n(r["nDetected"]), capture=_n(r["capture_percent"]), flags=_s(r["flags"]),
                             words=report.flag_words(_s(r["flags"])), level=_s(r["level"]), red=_s(r["red"]),
                             sensor=_s(r.get("sensor", "")), yellow=_s(r["yellow"]), peakSignal=_n(r["peakSignal_AU"]),
                             offset=_n(r["offset_AU"]), window=[_n(r["from"]), _n(r["to"])], indexStatus="ok",
                             analyzed=ana.get(f, ""), image=img, report=L["report"], workbook=L["workbook"],
                             open=L["open"], experiment=L["experiment"], note=""))
        for f in X["file"]:
            if f in have:
                continue
            ok = st.get(f) == "ok"
            rows.append(dict(file=f, channel=None, label="", status="", nDetected=None, capture=None, flags="",
                             words="", level="", red="", sensor="", yellow="", peakSignal=None, offset=None,
                             window=[None, None], indexStatus=st.get(f, ""), analyzed=ana.get(f, ""), image="",
                             report="", workbook="", open="", experiment=f.replace("\\", "/").rpartition("/")[0],
                             note="flags not computed yet" if ok else msg.get(f, "")))
        rows.sort(key=lambda r: (r["file"], r["channel"] or 0))
        return dict(rows=rows, missing=list(missing), recordings=int(len(X)))

    def _links(self, rel, folder):
        """urls of the files that belong to a recording: trend image per channel, workbook, report of the experiment"""
        rel = rel.replace("\\", "/")
        name = re.sub(r"\.mdd$", "", rel.rsplit("/", 1)[-1], flags=re.I)
        exp = rel.rpartition("/")[0]
        images = {}
        for d in (folder, os.path.join(folder, "trends")):
            if not os.path.isdir(d):
                continue
            for fn in os.listdir(d):
                m = re.fullmatch(re.escape(name) + r"_ch(\d+)\.png", fn)
                if m and int(m.group(1)) not in images:
                    images[int(m.group(1))] = self._url(os.path.join(d, fn))
        wb = os.path.join(folder, name + ".xlsx")
        rep = os.path.join(self.results, *exp.split("/"), exp.rsplit("/", 1)[-1] + "_report.pdf") if exp else \
            os.path.join(self.results, "mda_report_root.pdf")
        info = os.path.join(folder, name + "_info.csv")
        return dict(images=images, workbook=self._url(wb) if os.path.isfile(wb) else "",
                    open=wb if os.path.isfile(wb) else info if os.path.isfile(info) else "",
                    report=self._url(rep) if os.path.isfile(rep) else "", experiment=exp)

    def _url(self, path):
        rel = os.path.relpath(path, self.results).replace(os.sep, "/")
        return "/files/" + urllib.parse.quote(rel)

    # ------------------------------------------------------------------------------------------- settings
    def settings_file(self):
        return os.path.join(self.results, SETTINGS_NAME)

    def _options_now(self):
        """the options a pass started from the page uses: those of the settings file of the page, else the defaults"""
        from ..options import options
        f = self.settings_file()
        if os.path.isfile(f):
            from ..settings import load_settings
            return options(load_settings(f))
        return options()

    def pass_keywords(self):
        """keywords of watch for a pass started from the page (the settings file of the page, if there is one)"""
        return dict(settings=self.settings_file()) if os.path.isfile(self.settings_file()) else {}

    def settings(self, opts=None, source=None):
        """the settings page: every field with its value as shown (option x scale) and its default, the basics, what
        differs from the defaults and from the newest analysis. opts: options to show instead of the saved ones
        (loaded from a file or from the newest analysis, not saved yet)"""
        from .. import advanced
        from ..options import options
        from ..watch import _expand_settings, _value_text, options_text
        D = options()
        saved = os.path.isfile(self.settings_file())
        if opts is None:
            opts, source = self._options_now(), "saved" if saved else "standard"
        fields, on_page = [], set()
        for name, label, kind, items, text, scale, unit, tab, _ in _EXTRA_ROWS + tuple(advanced.ROWS):
            on_page.add(name)
            fields.append(dict(name=name, label=label, kind=kind, items=[[str(a), b] for a, b in items or ()],
                               text=text, unit=unit, tab=tab, value=_shown(opts[name], kind, scale),
                               default=_shown(D[name], kind, scale)))
        changed = [n for n in D if n != "referenceBeat" and _value_text(opts[n]) != _value_text(D[n])]
        last = self.last_analysis()
        diff = []
        if last:
            mine = _text_dict(options_text(_expand_settings(self.pass_keywords())))
            theirs = _text_dict(last[1])
            low = {r[0].lower(): r for r in _EXTRA_ROWS + tuple(advanced.ROWS)}

            def show(k, d):   # the value as the page shows it; an option that is not named has its standard value
                row = low.get(k)
                if k in d:
                    return _canon_shown(row, d[k]) if row else d[k]
                return _canon_shown(row, _value_text(D[row[0]])) + " (standard)" if row else "standard"
            diff = [dict(name=low[k][0] if k in low else k, last=show(k, theirs), page=show(k, mine))
                    for k in sorted(set(mine) | set(theirs)) if mine.get(k) != theirs.get(k)]
        return dict(file=self.settings_file(), saved=saved, source=source, fields=fields, changed=changed,
                    notOnPage=[n for n in changed if n not in on_page],
                    tabs=[dict(name=t, title=_TAB_TITLES.get(t, t)) for t in advanced.TABS],
                    basics=[dict(title=a, text=b, names=list(c)) for a, b, c in _BASICS],
                    download=self._url(self.settings_file()) if saved else "",
                    last=dict(file=last[0], canLoad=bool(last[2]), differs=diff) if last else None)

    def save_settings(self, values, base=None):
        """saves the settings of the page: values = {option name: value as shown}; base = "standard": on top of the
        defaults, otherwise on top of what is saved (options that are not on the page keep their values)"""
        from .. import advanced
        from ..options import options
        from ..settings import save_settings
        cur = options() if base == "standard" else self._options_now()
        rows = {r[0]: r for r in _EXTRA_ROWS + tuple(advanced.ROWS)}
        changes = {}
        for name, v in dict(values or {}).items():
            if name not in rows:
                raise ValueError(f"unknown setting: {name}")
            _, label, kind, items, _, scale = rows[name][:6]
            if _same_shown(v, _shown(cur[name], kind, scale)):
                continue   # unchanged: the stored value stays as it is (no rounding by the way through the page)
            try:
                changes[name] = _parse(v, kind, scale, items)
            except ValueError as e:
                raise ValueError(f"{label}: {e}") from None
        opts = options(cur, **changes)
        os.makedirs(self.results, exist_ok=True)
        save_settings(self.settings_file(), opts)
        return self.settings()

    def last_analysis(self):
        """(recording, text of its options in the index, results file that holds its settings) of the newest
        analysis of the results folder; None without one"""
        from ..watch import read_index, results_of
        X = read_index(self.results)
        X = X[X["status"].astype(str) == "ok"]
        if not len(X):
            return None
        r = X.sort_values("analyzed", kind="stable").iloc[-1]
        f = str(r["file"])
        return f, str(r["options"] or ""), self._links(f, results_of(self.results, f)[0])["open"]

    def settings_of_last_analysis(self):
        """the settings page filled with the settings of the newest analysis (not saved)"""
        from ..options import options
        from ..settings import load_settings
        last = self.last_analysis()
        if not last or not last[2]:
            raise ValueError("no analyzed recording with its settings in this results folder")
        return self.settings(options(load_settings(last[2])), "the newest analysis (" + last[0] + ")")

    def settings_of_text(self, text, name=""):
        """the settings page filled with the settings of a settings file (.csv) given as text (not saved)"""
        import tempfile
        from ..options import options
        from ..settings import load_settings
        if "option_" not in str(text):
            raise ValueError("this is not a settings file (.csv saved by MyoDishAnalysis)")
        fd, tmp = tempfile.mkstemp(suffix=".csv")
        try:
            with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
                fh.write(str(text))
            opts = options(load_settings(tmp))
        finally:
            os.remove(tmp)
        return self.settings(opts, "the file " + os.path.basename(str(name) or "settings.csv"))

    def help(self):
        """what the help page needs from the program: the flags with the thresholds in use, the guides at hand"""
        from .. import report
        fl = dict(report.FLAG_DEFAULTS)
        d = _docs_folder()
        return dict(names=[dict(letter=c, group=g, name=n) for c, g, n in report.FLAG_NAMES],
                    legend=[dict(group=g or "", text=t) for g, t in report.legend_lines(fl)],
                    minBeats=fl["min_beats"],
                    docs=[dict(url="/docs/" + f, title=t) for f, t in _DOCS
                          if d and os.path.isfile(os.path.join(d, f))],
                    settingsFile=self.settings_file(), localOnly=self.local_only)

    def compute_flags(self):
        from ..watch import flags_table
        _, T, missing = flags_table(self.results, compute=True)
        return dict(rows=int(len(T)), missing=list(missing))

    def watcher(self):
        from ..watch import LOCK_HOURS, LOCK_NAME, read_index
        X = read_index(self.results)
        counts = {str(k): int(v) for k, v in X["status"].value_counts().items()}
        last = max((a for a in X["analyzed"].astype(str) if a), default="")
        lock = os.path.join(self.results, LOCK_NAME)
        busy = os.path.isfile(lock) and (_dt.datetime.now().timestamp() - os.path.getmtime(lock)) < LOCK_HOURS * 3600
        d = os.path.join(self.results, "reports")
        reports = sorted((f for f in os.listdir(d) if _REPORT_RX.match(f)), reverse=True)[:30] \
            if os.path.isdir(d) else []
        with self.lock:
            run = dict(self.run)
        from ..options import options
        from ..watch import _value_text
        D, O = options(), self._options_now()
        return dict(recordings=int(len(X)), counts=counts, lastAnalyzed=last, locked=bool(busy), reports=reports,
                    raw=self.raw or self.raw_of_last_report(), lastRaw=self.raw_of_last_report(), run=run,
                    settingsChanged=[n for n in D if n != "referenceBeat" and _value_text(O[n]) != _value_text(D[n])])

    def raw_of_last_report(self):
        """raw folder named in the newest pass report ('' if there is none)"""
        d = os.path.join(self.results, "reports")
        if not os.path.isdir(d):
            return ""
        for f in sorted((f for f in os.listdir(d) if _REPORT_RX.match(f)), reverse=True)[:1]:
            try:
                with open(os.path.join(d, f), encoding="utf-8", errors="replace") as fh:
                    for line in fh.read(4000).splitlines():
                        if line.startswith("raw folder:"):
                            return line.split(":", 1)[1].strip()
            except OSError:
                pass
        return ""

    def report_text(self, name):
        if not _REPORT_RX.match(name or ""):
            raise ValueError("not a pass report")
        with open(os.path.join(self.results, "reports", name), encoding="utf-8", errors="replace") as fh:
            return fh.read()

    def start_pass(self, raw, dry_run=False, other_raw=False, options=None, again=False):
        """one pass of the watcher in the background; refused while one runs (here or elsewhere: lock file). A pass
        that analyzes is also refused (OtherRaw) when the results folder was filled from another raw folder, unless
        other_raw is set: the recordings are known by their path below the raw folder, so from a folder one level
        up or down every recording counts as new and is analyzed a second time. options: which recordings the pass
        takes (_pass_options); a pass that analyzes recordings again (reanalyze 'outdated' or 'all') replaces their
        results and is refused (Again) unless again is set."""
        opts = _pass_options(options)
        last = self.raw_of_last_report()
        raw = os.path.abspath(raw or self.raw or last or "")
        if not raw or not os.path.isdir(raw):
            raise ValueError("raw folder not found: " + (raw or "(none given)"))
        if not dry_run and not again and opts.get("reanalyze", "new") != "new":
            raise Again("This analyzes recordings again and replaces their results"
                        + (": all recordings of the raw folder that match." if opts["reanalyze"] == "all" else
                           ": those analyzed with another version of the program or with other settings.")
                        + " Look at the list first ('Show what would be analyzed').")
        if last and not dry_run and not other_raw and not _same_folder(last, raw):
            raise OtherRaw(f"This results folder was filled from another raw folder ({last}). From {raw} the "
                           "recordings may count as new and be analyzed a second time. Look at the list first "
                           "('Show what would be analyzed').")
        with self.lock:
            if self.run["running"]:
                raise ValueError("a pass started here is still running")
            if self.job["running"]:
                raise ValueError("the study " + self.job["name"] + " started here is still running")
            self.run = dict(running=True, started=_now(), finished="", raw=raw, dry_run=bool(dry_run), report="",
                            error="", output="", options=dict(opts, from_date=str(opts.get("from_date", ""))[:10])
                            if "from_date" in opts else dict(opts))
        threading.Thread(target=self._pass, args=(raw, bool(dry_run), opts), daemon=True).start()
        return dict(started=True)

    def _pass(self, raw, dry_run, opts=None):
        report, error = "", ""
        try:
            from ..watch import watch
            with contextlib.redirect_stdout(_Tee(self, self.run, sys.stdout)):  # the lines of the pass, for the page
                _, report = watch(raw, self.results, quiet=False, dry_run=dry_run, **(opts or {}),
                                  **self.pass_keywords())
        except Exception as e:  # noqa: BLE001 - shown on the page
            error = f"{type(e).__name__}: {e}"
            if os.environ.get("MDA_DEBUG"):
                traceback.print_exc()
        with self.lock:
            self.run.update(running=False, finished=_now(), report=str(report or ""), error=error)

    # ------------------------------------------------------------------------------------------- studies
    def series_list(self):
        """the series of the results folder (recordings of one setup: the file name up to its number), each with its
        experiment, the number of analysed recordings and the channels with their labels (newest flags)"""
        from ..timepoints import _series_info
        from ..watch import flags_table
        X, T, _ = flags_table(self.results, compute=False)
        out = {}
        for f, st in zip(X["file"].astype(str), X["status"].astype(str)):
            if not st.startswith("ok"):
                continue
            rel = f.replace("\\", "/")
            s, _, main = _series_info(re.sub(r"\.mdd$", "", rel.rsplit("/", 1)[-1], flags=re.I))
            if not main:
                continue
            d = out.setdefault(s, dict(series=s, experiment=rel.rpartition("/")[0], recordings=0, channels={}))
            d["recordings"] += 1
        for r in T.to_dict("records"):
            rel = str(r["file"]).replace("\\", "/")
            s = _series_info(re.sub(r"\.mdd$", "", rel.rsplit("/", 1)[-1], flags=re.I))[0]
            if s in out and _s(r["status"]) != "no slice":
                out[s]["channels"][int(r["channel"])] = _s(r["label"])
        return [dict(d, channels=[dict(channel=c, label=d["channels"][c]) for c in sorted(d["channels"])])
                for d in sorted(out.values(), key=lambda d: d["series"])]

    def _n_studies(self):
        root = os.path.join(self.results, "studies")
        return sum(1 for x in os.listdir(root) if os.path.isdir(os.path.join(root, x))) if os.path.isdir(root) else 0

    def _study_folder(self, name):
        name = str(name or "")
        if not re.fullmatch(r"[A-Za-z0-9._-]+", name) or name.strip(".") == "":
            raise ValueError("name of the study: letters, digits, '.', '-' and '_' expected")
        return os.path.join(self.results, "studies", name)

    def _study_design(self, folder, name):
        """(rows, settings) of the design kept in the study folder; ([], {}) without one"""
        from ..study import _read_design
        for ext in (".xlsx", ".csv"):
            f = os.path.join(folder, "design_" + name + ext)
            if os.path.isfile(f):
                D, settings = _read_design(f)
                return D.to_dict("records"), settings
        return [], {}

    def studies(self):
        """the studies of the results folder (<results>/studies/<name>/), newest first, and what the editor needs"""
        from ..study import DESIGN_COLUMNS, SETTINGS
        root, out = os.path.join(self.results, "studies"), []
        for name in sorted(os.listdir(root)) if os.path.isdir(root) else []:
            d = os.path.join(root, name)
            wb = os.path.join(d, name + ".xlsx")
            if not os.path.isdir(d) or not re.fullmatch(r"[A-Za-z0-9._-]+", name):
                continue
            try:
                rows, _ = self._study_design(d, name)
            except Exception:  # noqa: BLE001 - a design that cannot be read: the study is listed without it
                rows = []
            out.append(dict(name=name, done=os.path.isfile(wb), slices=len(rows),
                            treatments=list(dict.fromkeys(r["treatment"] for r in rows)),
                            modified=_dt.datetime.fromtimestamp(os.path.getmtime(wb if os.path.isfile(wb) else d)
                                                                ).strftime("%Y-%m-%d %H:%M")))
        out.sort(key=lambda x: x["modified"], reverse=True)
        with self.lock:
            job = dict(self.job)
        hide = ("resultsFolder", "outputFolder", "name")
        single, pools = self.other_analyses()
        return dict(studies=out, single=single, pools=pools, series=self.series_list(),
                    columns=list(DESIGN_COLUMNS), job=job,
                    settings=[dict(key=k, default=v, text=t) for k, v, t in SETTINGS if k not in hide])

    def study_view(self, name):
        """one study: its design and settings, the images, the methods text, the files and three tables"""
        d = self._study_folder(name)
        if not os.path.isdir(d):
            raise FileNotFoundError(name)
        rows, settings = self._study_design(d, name)
        files = [("design_" + name + ".xlsx", "Design table (.xlsx)"),
                 ("design_" + name + ".csv", "Design table (.csv)")]
        V = self._folder_view(d, name, (("treatments", "Per treatment and time point"), ("statistics", "Statistics"),
                                        ("excluded", "Left out")), files)
        return dict(V, name=name, rows=rows, settings=settings)

    def _folder_view(self, d, name, sheets, more_files=(), root_title="All treatments"):
        """what a folder with the results of timepoints, pool_timepoints or study shows: its images (those of the
        folder and of its subfolders except analyses), files, methods text and the given sheets of its workbook"""
        import pandas as pd
        groups = []
        for sub in [""] + sorted(x for x in os.listdir(d) if os.path.isdir(os.path.join(d, x)) and x != "analyses"):
            imgs = sorted(f for f in os.listdir(os.path.join(d, sub)) if f.lower().endswith(".png"))
            if imgs:   # the summary images first: normalized before absolute
                imgs.sort(key=lambda f: (0 if "_figure_" in f else 1 if f.startswith("treatments") else 2,
                                         0 if "_norm" in f else 1 if "_vsControl" in f else 2, f))
                groups.append(dict(title=sub or root_title,
                                   images=[dict(name=f, url=self._url(os.path.join(d, sub, f))) for f in imgs]))
        files = []
        for f, title in ((name + ".xlsx", "Workbook with all tables (.xlsx)"),
                         (name + "_prism.xlsx", "Tables for GraphPad Prism (.xlsx)"),
                         (name + "_figure_norm.pdf", "Figure (PDF)"), (name + "_methods.txt", "Methods text (.txt)"),
                         *more_files):
            if os.path.isfile(os.path.join(d, f)):
                files.append(dict(title=title, url=self._url(os.path.join(d, f))))
        methods = ""
        mf = os.path.join(d, name + "_methods.txt")
        if os.path.isfile(mf):
            with open(mf, encoding="utf-8", errors="replace") as fh:
                methods = fh.read().strip()
        tables = []
        wb = os.path.join(d, name + ".xlsx")
        if os.path.isfile(wb):
            x = pd.ExcelFile(wb)
            for sheet, title in sheets:
                if sheet in x.sheet_names:
                    T = x.parse(sheet)
                    if len(T):
                        tables.append(dict(title=title, sheet=sheet, columns=[str(c) for c in T.columns],
                                           rows=[[_cell(v) for v in r] for r in T.head(400).itertuples(index=False)],
                                           more=max(0, len(T) - 400)))
        return dict(folder=d, done=os.path.isfile(wb), groups=groups, files=files, methods=methods, tables=tables)

    def other_analyses(self):
        """analyses of timepoints made outside a study (<experiment>/timepoints/<label>_<time>/, by mda-timepoints or
        mda_timepoints) and pools of them (<results>/timepoints_pooled/<name>/): id = path below the results folder"""
        from ..watch import read_index
        exps = {""} | {str(f).replace("\\", "/").rpartition("/")[0] for f in read_index(self.results)["file"]}
        single = []
        for e in sorted(exps):
            root = os.path.join(self.results, *[x for x in e.split("/") if x], "timepoints")
            for n in sorted(os.listdir(root)) if os.path.isdir(root) else []:
                wb = os.path.join(root, n, n + ".xlsx")
                m = re.fullmatch(r"(.+)_(\d{4}-\d{2}-\d{2})-(\d{2})-(\d{2})", n)
                if m and os.path.isfile(wb):
                    single.append(dict(id=(e + "/" if e else "") + "timepoints/" + n, label=m.group(1), experiment=e,
                                       time=f"{m.group(2)} {m.group(3)}:{m.group(4)}", modified=_mtime(wb)))
        pools, root = [], os.path.join(self.results, "timepoints_pooled")
        for n in sorted(os.listdir(root)) if os.path.isdir(root) else []:
            wb = os.path.join(root, n, n + ".xlsx")
            if os.path.isfile(wb):
                pools.append(dict(id="timepoints_pooled/" + n, name=n, modified=_mtime(wb)))
        return single, pools

    def analysis_view(self, rel):
        """one analysis of timepoints or one pool (id of other_analyses): images, files and tables"""
        parts = [x for x in str(rel or "").replace("\\", "/").split("/") if x]
        if len(parts) < 2 or parts[-2] not in ("timepoints", "timepoints_pooled") or ".." in parts:
            raise ValueError("not an analysis of this results folder")
        d = os.path.realpath(os.path.join(self.results, *parts))
        root = os.path.realpath(self.results)
        name = parts[-1]
        if os.path.commonpath([d, root]) != root or not os.path.isfile(os.path.join(d, name + ".xlsx")):
            raise FileNotFoundError(rel)
        if parts[-2] == "timepoints_pooled":
            V = self._folder_view(d, name, (("treatments", "Per treatment and time point"),
                                            ("statistics", "Statistics"), ("excluded", "Left out")))
            return dict(V, kind="pool", name=name, title="Pooled analyses " + name)
        m = re.fullmatch(r"(.+)_(\d{4}-\d{2}-\d{2})-(\d{2})-(\d{2})", name)
        V = self._folder_view(d, name, (("summary", "The windows"),), root_title="All channels")
        return dict(V, kind="timepoints", name=name,
                    title="Treatment " + (f"{m.group(1)}, {m.group(2)} {m.group(3)}:{m.group(4)}" if m else name))

    def study_design_of_file(self, data, name):
        """rows and settings of a design table (.xlsx or .csv, base64) for the editor; nothing is saved"""
        import base64
        import tempfile
        from ..study import _read_design
        ext = os.path.splitext(str(name or ""))[1].lower()
        if ext not in (".xlsx", ".csv"):
            raise ValueError("a design table is an .xlsx or a .csv file")
        try:
            raw = base64.b64decode(str(data or ""), validate=True)
        except ValueError:
            raise ValueError("the file did not arrive complete") from None
        fd, tmp = tempfile.mkstemp(suffix=ext)
        try:
            with os.fdopen(fd, "wb") as fh:
                fh.write(raw)
            D, settings = _read_design(tmp)
        except Exception as e:  # noqa: BLE001 - what the design lacks (study: design: ...), or not a table at all
            if isinstance(e, ValueError) and str(e).startswith("study: design: "):
                raise ValueError("Design table: " + str(e)[len("study: design: "):]) from None
            raise ValueError(f"this file cannot be read as a design table ({type(e).__name__})") from None
        finally:
            os.remove(tmp)
        return dict(rows=D.to_dict("records"), settings=settings)

    def study_template(self):
        """bytes of an empty design table (.xlsx) with an example row"""
        import tempfile
        from ..study import study_template
        fd, tmp = tempfile.mkstemp(suffix=".xlsx")
        os.close(fd)
        try:
            study_template(tmp)
            with open(tmp, "rb") as fh:
                return fh.read()
        finally:
            os.remove(tmp)

    def start_study(self, name, settings, rows):
        """runs a study in the background: design = rows (one per slice), settings = those of study.SETTINGS; the
        results folder is this one and the study folder <results>/studies/<name>. Refused while a pass or a study
        started here runs. The design is checked before the start, so that a mistake is shown at once."""
        import pandas as pd
        from ..study import DESIGN_COLUMNS, SETTINGS, _read_design
        self._study_folder(name)
        known = {k for k, _, _ in SETTINGS} - {"resultsFolder", "outputFolder", "name"}
        P = {}
        for k, v in dict(settings or {}).items():
            if k not in known:
                raise ValueError(f"unknown setting of a study: {k}")
            P[k] = ("true" if v else "false") if isinstance(v, bool) else str(v).strip()
        if not P.get("offsets", "").strip():
            raise ValueError("Windows: give the minutes after the treatment at which the windows start, e.g. -30 10 60")
        try:
            [float(x) for x in re.split(r"[\s,;]+", P["offsets"]) if x]
        except ValueError:
            raise ValueError("Windows: numbers (minutes) expected, e.g. -30 10 60") from None
        P["offsets"] = " ".join(x for x in re.split(r"[\s,;]+", P["offsets"]) if x)
        rows = [r for r in (rows or []) if str(r.get("series", "")).strip()]
        if not rows:
            raise ValueError("The table of slices is empty: every slice needs its series, channel, treatment and time")
        D = pd.DataFrame([{c: ("" if r.get(c) is None else str(r.get(c)).strip()) for c in DESIGN_COLUMNS}
                          for r in rows], columns=DESIGN_COLUMNS)
        for i, r in enumerate(D.to_dict("records"), 1):
            for c in ("channel", "treatment", "time"):
                if not r[c]:
                    raise ValueError(f"Slice {i} ({r['series']}): {c} is missing")
            try:
                int(float(r["channel"]))
            except ValueError:
                raise ValueError(f"Slice {i} ({r['series']}): channel '{r['channel']}' is not a number") from None
            if r["exclude"] and r["exclude"].lower() != "all":
                try:
                    float(r["exclude"])
                except ValueError:
                    raise ValueError(f"Slice {i} ({r['series']}): leave out from '{r['exclude']}': empty, all or "
                                     "the minutes from which on the windows are left out") from None
            try:
                pd.Timestamp(r["time"])
            except (ValueError, TypeError):
                raise ValueError(f"Slice {i} ({r['series']}): time '{r['time']}' is not a date and time "
                                 "(yyyy-mm-dd HH:MM)") from None
        known_series = {x["series"] for x in self.series_list()}
        miss = sorted(set(D["series"]) - known_series)
        if miss:
            raise ValueError("No analysed recording of the series " + ", ".join(miss) + " in this results folder")
        try:
            D, _ = _read_design(D)
        except ValueError as e:
            raise ValueError(str(e).replace("study: design: ", "")) from None
        with self.lock:
            if self.run["running"]:
                raise ValueError("a pass started here is still running")
            if self.job["running"]:
                raise ValueError("the study " + self.job["name"] + " started here is still running")
            self.job = dict(running=True, kind="study", name=name, started=_now(), finished="", error="", output="")
        threading.Thread(target=self._study, args=(name, D, P), daemon=True).start()
        return dict(started=True)

    def _study(self, name, D, P):
        error = ""
        try:
            from ..study import study
            with contextlib.redirect_stdout(_Tee(self, self.job, sys.stdout)):
                study(D, resultsFolder=self.results, name=name, **P)
        except Exception as e:  # noqa: BLE001 - shown on the page
            error = f"{type(e).__name__}: {e}" if not isinstance(e, ValueError) else str(e)
            if os.environ.get("MDA_DEBUG"):
                traceback.print_exc()
        with self.lock:
            self.job.update(running=False, finished=_now(), error=error)

    def file_path(self, rel):
        """absolute path of a file of the results folder; ValueError for anything outside it or of another kind"""
        p = os.path.realpath(os.path.join(self.results, *[s for s in rel.split("/") if s]))
        root = os.path.realpath(self.results)
        if os.path.commonpath([p, root]) != root or not os.path.isfile(p):
            raise ValueError("not a file of the results folder")
        if os.path.splitext(p)[1].lower() not in _SERVED:
            raise ValueError("this kind of file is not served")
        return p


class OtherRaw(ValueError):
    """a pass from another raw folder than the one of the last pass (the page asks before it goes on)"""


class Again(ValueError):
    """a pass that analyzes recordings again and replaces their results (the page asks before it goes on)"""


def _pass_options(options):
    """which recordings a pass started from the page takes: keywords of watch from what the page sends (reanalyze
    'new' | 'outdated' | 'all', retry_errors, include, exclude, from_date, max_files, min_file_age_minutes, workers);
    empty values are left out, so the defaults of the watcher hold. ValueError with what is expected."""
    from ..watch import parse_date
    out = {}
    for k, v in dict(options or {}).items():
        if v is None or (isinstance(v, str) and not v.strip()):
            continue
        if k == "reanalyze":
            if str(v) not in ("new", "outdated", "all"):
                raise ValueError("which recordings: new, outdated or all expected")
            out[k] = str(v)
        elif k == "retry_errors":
            if not isinstance(v, bool):
                raise ValueError("recordings with an error: on or off expected")
            if v:
                out[k] = True
        elif k in ("include", "exclude"):
            out[k] = str(v).strip()
        elif k == "from_date":
            try:
                out[k] = parse_date(str(v).strip())
            except ValueError:
                raise ValueError(f"changed since: a date is expected (yyyy-mm-dd), not '{v}'") from None
        elif k in ("max_files", "workers", "min_file_age_minutes"):
            name = {"max_files": "at most", "workers": "at the same time", "min_file_age_minutes": "wait"}[k]
            try:
                x = float(str(v).strip().replace(",", "."))
            except ValueError:
                raise ValueError(f"{name}: a number is expected, not '{v}'") from None
            if k == "min_file_age_minutes":
                if not (0 <= x <= 100000):
                    raise ValueError("wait: minutes from 0 on expected")
                out[k] = x
            else:
                if x != round(x) or not (1 <= x <= (100000 if k == "max_files" else 16)):
                    raise ValueError(f"{name}: a whole number from 1 on expected"
                                     + ("" if k == "max_files" else " (at most 16)"))
                out[k] = int(x)
        else:
            raise ValueError(f"unknown option of a pass: {k}")
    return out


def _same_folder(a, b):
    def norm(p):
        return os.path.normcase(os.path.realpath(os.path.abspath(p))).rstrip("\\/")
    return norm(a) == norm(b)


class _Tee(io.TextIOBase):
    """what a pass or a study prints goes to the terminal as before and, for the page, into its state (run or job;
    the last 20000 characters)"""

    def __init__(self, app, state, out):
        self.app, self.state, self.out = app, state, out

    def write(self, s):
        with self.app.lock:
            self.state["output"] = (self.state.get("output", "") + s)[-20000:]
        try:
            self.out.write(s)
        except (OSError, ValueError):
            pass
        return len(s)

    def flush(self):
        try:
            self.out.flush()
        except (OSError, ValueError):
            pass


def _docs_folder():
    """folder docs of a source checkout (the guides as PDF); '' in an installed package"""
    d = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "docs"))
    return d if os.path.isdir(d) else ""


def _text_dict(text):
    """'a=1; b=x' (options text of the index) --> {'a': '1', 'b': 'x'}"""
    out = {}
    for part in str(text or "").split("; "):
        k, eq, v = part.partition("=")
        if eq and k.strip():
            out[k.strip()] = v.strip()
    return out


def _shown(v, kind, scale):
    """value of an option as the settings page shows it (kind and scale of advanced.ROWS): number x scale, 'auto',
    'inf', numbers of a vector separated by blanks, true / false"""
    if kind == "check":
        return v.lower() in ("on", "true", "1") if isinstance(v, str) else bool(v)
    if kind == "popup":
        return v if isinstance(v, (str, bool, int, float)) else str(v)
    if kind == "vec":
        import numpy as np
        a = [] if v is None else np.asarray(v, dtype=float).ravel().tolist()
        return " ".join("%.12g" % (x * scale) for x in a)
    if v is None:
        return ""
    if isinstance(v, str):
        return v
    x = float(v) * scale
    if math.isnan(x):
        return ""
    if math.isinf(x):
        return "inf" if x > 0 else "-inf"
    return float("%.12g" % x)


def _canon_shown(row, text):
    """a value of the options text of the index (option units) as the settings page shows it (with its unit)"""
    _, _, kind, items, _, scale, unit = row[:7]
    text = str(text).strip()
    try:
        if kind == "check":
            return "on" if text.lower() in ("1", "true", "on") else "off"
        if kind == "popup":
            return next((str(a) for a, b in items or () if str(b) == text), text)
        if kind in ("num", "int", "numauto") and text.lower() != "auto":
            return ("%.12g" % (float(text) * scale)) + (" " + unit if unit else "")
    except ValueError:
        pass
    return text or "none"


def _same_shown(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return isinstance(a, bool) and isinstance(b, bool) and a == b
    try:
        return float(a) == float(b)
    except (TypeError, ValueError):
        return str(a).strip() == str(b).strip()


def _parse(v, kind, scale, items):
    """value of an option from what the settings page sends; ValueError with what is expected"""
    if kind == "check":
        if isinstance(v, bool):
            return v
        raise ValueError("on or off expected")
    if kind == "popup":
        for _, val in items or ():
            if str(val) == str(v):
                return val
        raise ValueError("one of these is expected: " + ", ".join(str(b) for _, b in items or ()))
    if kind == "vec":
        try:
            return tuple(float(x) / scale for x in re.split(r"[\s,;]+", str(v).strip()) if x)
        except ValueError:
            raise ValueError("numbers are expected, e.g. 1 3 5 (empty: none)") from None
    t = str(v).strip().lower()
    if kind == "numauto" and t == "auto":
        return "auto"
    try:
        x = float(t)
    except ValueError:
        raise ValueError("a number is expected" + (" (or auto)" if kind == "numauto" else "")) from None
    if math.isnan(x):
        raise ValueError("a number is expected")
    if kind == "int" and math.isfinite(x) and x != round(x):
        raise ValueError("a whole number is expected")
    return x / scale


def _now():
    return _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def _s(v):
    return "" if v is None or (isinstance(v, float) and math.isnan(v)) else str(v)


def _mtime(f):
    return _dt.datetime.fromtimestamp(os.path.getmtime(f)).strftime("%Y-%m-%d %H:%M")


def _cell(v):
    """a cell of a table for the page: text, or a number with 4 significant digits; '' for nothing"""
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return ""
    if isinstance(v, bool):
        return "yes" if v else "no"
    try:
        x = float(v)
    except (TypeError, ValueError):
        return str(v)
    if isinstance(v, str):
        return v
    if math.isnan(x) or math.isinf(x):
        return ""
    return int(x) if x == round(x) and abs(x) < 1e15 else float("%.4g" % x)


def _n(v):
    try:
        v = float(v)
    except (TypeError, ValueError):
        return None
    return None if math.isnan(v) or math.isinf(v) else v


def make_handler(app):
    class Handler(BaseHTTPRequestHandler):
        server_version = "MyoDishAnalysisWeb"

        def log_message(self, *a):  # quiet: no request log in the terminal
            return

        def _json(self, obj, code=200):
            body = json.dumps(obj, allow_nan=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _file(self, path, ctype=None):
            ctype = ctype or mimetypes.guess_type(path)[0] or "application/octet-stream"
            with open(path, "rb") as fh:
                body = fh.read()
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _refused(self):
            """True (and answered) for a request that is not addressed to this computer while the server is meant
            for this computer only: a page of another site that points its own name at 127.0.0.1 could otherwise
            read the results through the browser of the user"""
            if not app.local_only:
                return False
            host = (self.headers.get("Host") or "").strip().lower()
            name = host[1:host.index("]")] if host.startswith("[") and "]" in host else host.rsplit(":", 1)[0]
            if name in _LOCAL_HOSTS:
                return False
            self._json(dict(error="this server answers on this computer only (http://127.0.0.1)"), 403)
            return True

        def _bytes(self, body, filename):
            self.send_response(200)
            self.send_header("Content-Type", mimetypes.guess_type(filename)[0] or "application/octet-stream")
            self.send_header("Content-Disposition", 'attachment; filename="%s"' % filename)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _do(self, fn):
            try:
                fn()
            except OtherRaw as e:
                self._json(dict(error=str(e), code="otherRaw"), 400)
            except Again as e:
                self._json(dict(error=str(e), code="again"), 400)
            except ValueError as e:
                self._json(dict(error=str(e)), 400)
            except FileNotFoundError:
                self._json(dict(error="not found"), 404)
            except Exception as e:  # noqa: BLE001 - the page shows the message
                if os.environ.get("MDA_DEBUG"):
                    traceback.print_exc()
                self._json(dict(error=f"{type(e).__name__}: {e}"), 500)

        def do_GET(self):  # noqa: N802
            if self._refused():
                return None
            u = urllib.parse.urlsplit(self.path)
            q = urllib.parse.parse_qs(u.query)
            path = urllib.parse.unquote(u.path)
            if path in ("/", "/index.html"):
                return self._do(lambda: self._file(os.path.join(_STATIC, "index.html"), "text/html; charset=utf-8"))
            if path == "/api/state":
                return self._do(lambda: self._json(app.state()))
            if path == "/api/results":
                return self._do(lambda: self._json(app.results_rows()))
            if path == "/api/watcher":
                return self._do(lambda: self._json(app.watcher()))
            if path == "/api/report":
                return self._do(lambda: self._json(dict(text=app.report_text((q.get("name") or [""])[0]))))
            if path == "/api/settings":
                return self._do(lambda: self._json(app.settings()))
            if path == "/api/help":
                return self._do(lambda: self._json(app.help()))
            if path == "/api/studies":
                return self._do(lambda: self._json(app.studies()))
            if path == "/api/study":
                return self._do(lambda: self._json(app.study_view((q.get("name") or [""])[0])))
            if path == "/api/analysis":
                return self._do(lambda: self._json(app.analysis_view((q.get("id") or [""])[0])))
            if path == "/api/study/template":
                return self._do(lambda: self._bytes(app.study_template(), "design.xlsx"))
            if path == "/api/job":
                with app.lock:
                    job = dict(app.job)
                return self._json(job)
            if path.startswith("/docs/"):
                name = path[len("/docs/"):]
                if name in [f for f, _ in _DOCS] and _docs_folder():
                    return self._do(lambda: self._file(os.path.join(_docs_folder(), name)))
                return self._json(dict(error="not found"), 404)
            if path.startswith("/files/"):
                return self._do(lambda: self._file(app.file_path(path[len("/files/"):])))
            self._json(dict(error="not found"), 404)

        def do_POST(self):  # noqa: N802
            if self._refused():
                return None
            n = int(self.headers.get("Content-Length") or 0)
            if n > _MAX_BODY:
                return self._json(dict(error="request too large"), 413)
            try:
                data = json.loads(self.rfile.read(n).decode("utf-8") or "{}") if n else {}
            except ValueError:
                return self._json(dict(error="not JSON"), 400)
            # a page of another site must not start a pass in the name of the user: same-origin requests only
            origin = self.headers.get("Origin")
            if origin and urllib.parse.urlsplit(origin).netloc != self.headers.get("Host"):
                return self._json(dict(error="request from another site refused"), 403)
            path = urllib.parse.urlsplit(self.path).path
            if path == "/api/flags/compute":
                return self._do(lambda: self._json(app.compute_flags()))
            if path == "/api/watcher/run":
                return self._do(lambda: self._json(app.start_pass(
                    data.get("raw"), bool(data.get("dry_run", False)), bool(data.get("other_raw", False)),
                    data.get("options"), bool(data.get("again", False)))))
            if path == "/api/settings":
                return self._do(lambda: self._json(app.save_settings(data.get("values"), data.get("base"))))
            if path == "/api/settings/last":
                return self._do(lambda: self._json(app.settings_of_last_analysis()))
            if path == "/api/study/run":
                return self._do(lambda: self._json(app.start_study(data.get("name"), data.get("settings"),
                                                                    data.get("rows"))))
            if path == "/api/study/design":
                return self._do(lambda: self._json(app.study_design_of_file(data.get("data"), data.get("name"))))
            if path == "/api/settings/file":
                return self._do(lambda: self._json(app.settings_of_text(data.get("text", ""), data.get("name", ""))))
            self._json(dict(error="not found"), 404)

    return Handler


def make_server(results_folder, raw_folder=None, host="127.0.0.1", port=8765):
    """(server, app): the server is not started yet (serve_forever), port 0 = any free port"""
    app = App(results_folder, raw_folder, host)
    return ThreadingHTTPServer((host, int(port)), make_handler(app)), app


def serve(results_folder, raw_folder=None, host="127.0.0.1", port=8765, open_browser=True):
    srv, _ = make_server(results_folder, raw_folder, host, port)
    url = "http://%s:%d/" % ("127.0.0.1" if host in ("0.0.0.0", "") else host, srv.server_address[1])
    print(f"MyoDishAnalysis in the browser: {url}   (results: {os.path.abspath(results_folder)}; stop with Ctrl+C)")
    if host not in ("127.0.0.1", "localhost"):
        print("Note: other computers can reach this page. There is no login: use it in a trusted network only.")
    if open_browser:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()


def main(argv=None):
    ap = argparse.ArgumentParser(prog="mda-web", description="MyoDishAnalysis in the browser: results browser and "
                                 "watcher of a results folder (local web server, this computer only by default)")
    ap.add_argument("results", help="results folder of the watcher (with mda_index.csv)")
    ap.add_argument("--raw", help="raw folder with the recordings (for a pass started from the page; default: the "
                    "one named in the newest pass report)")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--host", default="127.0.0.1", help="127.0.0.1 (default): this computer only; 0.0.0.0: every "
                    "computer that reaches this one (no login, trusted networks only)")
    ap.add_argument("--no-browser", action="store_true", help="do not open the page in the browser")
    a = ap.parse_args(argv)
    serve(a.results, a.raw, a.host, a.port, not a.no_browser)
