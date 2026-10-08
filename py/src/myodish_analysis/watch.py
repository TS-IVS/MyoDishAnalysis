"""Automatic analysis of new MyoDish recordings in a folder (watcher): MyoDishAnalysisWatch.m in Python.

    index, report = watch(raw_folder, results_folder, interval=0, reanalyze="outdated", ...)
    mda-watch RAW_FOLDER RESULTS_FOLDER [--interval 24] [--rocker-filter] ...      (command line)

Every pass searches raw_folder (with subfolders) for .mdd files and analyses those that are new, have changed, or were
analysed with another version, other options or (same implementation) other core code. The watcher only calls the
functions of MyoDishAnalysis (myodish_analysis, read_header, find_protocols, log_entries, write_results): improvements
of the analysis apply to the watcher results as well; with reanalyze="outdated" (default) the affected recordings are
analysed again.

Per recording (results_folder/<subfolder of raw_folder>/):
  <name>_summary.csv, _contractions.csv(.gz), _parameters.csv, _info.csv, _labels.csv (_rockerFilter.csv)
      summary = one row per channel and time range: time bins of bin_minutes (default 60 min) without the periods of
      the stimulation protocols (include_protocols=False, default; a bin with a protocol gives several ranges).
      range = clock time of the start of the range, bin = clock time of the start of the bin, nComments / comments =
      comments of the log file in the range (this channel or all channels). Contractions: contractions='all' (every
      contraction), 'thinned' (every thin_factor-th contraction per channel, thin_mode='nth', or the median of blocks
      of thin_factor contractions, thin_mode='median'; extra beats and, with include_protocols=True, the contractions in
      the protocols are always kept) or 'none'; columns bin, sampledEvery (number of contractions per row) and
      sampleMode ('singleBeat' / 'median'). compress=True: <name>_contractions.csv.gz.
  <name>_protocols_*.csv (if the log file contains stimulation protocols, protocols=True)
      myodish_analysis(file, protocol='all', ...): every contraction in the protocols, summary per protocol, channel
      and group, protocolResults (FFR, ST thresholds, refractory periods, PRP).
  <name>_events.csv (events=True): all entries of the log file (comments, stimulation and rocker settings, recording,
      calibration, schedule, warnings) with category, clock time and time in the file.
  <name>_gaps.csv (gaps=True): periods without force signal (signal_gaps): chamber taken out ('chamber out'), sensor
      board group or controller failures (>= 2 channels within 1 s), saturation, channels without a chamber ('no
      signal'); with clock times and the comments of the log file within 5 min of the start or end. The summary gets
      the columns noSignal_s (s without signal in the range) and nChamberOut (chambers taken out in the range).
  <name>_channels.csv (gaps=True): one row per channel: status at the end of the recording ('beating', 'not beating' =
      no contraction in the last 30 min with signal, 'removed' = chamber taken out and not put back, 'signal lost' =
      technical, 'no slice'), beatingAtEnd, s with and without signal, chambers taken out, technical failures,
      contractions, last contraction (time, clock time, median amplitude of the last 10 included contractions, in % of
      the 95th percentile of the recording), date of the experiment ID in the file name (6 digits yymmdd, e.g.
      ABC000101) and days since this date at the last contraction (or the end of the signal), daysInCulture (labels),
      comments about the slice's end (discarded, removed, not beating, fixed, frozen, ...).
  Labels per channel (metadata): <name>_labels.csv next to the .mdd file (saved by the GUI), if present.
results_folder/mda_index.csv
  one row per recording: file (path relative to raw_folder), bytes, modified (time of the .mdd file, UTC), logBytes,
  status (ok / error / running / noLog), version, implementation (MATLAB / Python), code (fingerprint of the core
  functions), options, analyzed, seconds, nContractions, outputs, message. The same file is used by the MATLAB and the
  Python watcher.
results_folder/reports/mda_report_<date>_<time>.txt
  report of a pass with analysed recordings: per channel contractions, capture (% of the stimuli followed by a
  contraction), extra beats (% of the detected contractions), mean amplitude in the first and last range (>= 10
  included contractions) and flags (no contractions, capture < flag_capture %, extra beats > flag_extra_beats %,
  amplitude change > flag_amplitude_change %).

Recordings are skipped while they are written: files modified less than min_file_age_minutes ago (default 10),
names starting with '.' (rsync temporary files), and recordings whose log file has no 'Recording stopped' entry
yet (status 'running') unless unchanged for incomplete_after_hours (default 30 h, e.g. aborted recordings).
Recordings without log file get the status 'noLog'; they are checked again in every pass. Errors are retried when the
file, the version, the options or the code change, or with retry_errors=True.

Options (keywords): interval (hours between passes, 0 = one pass, default), reanalyze ('outdated' | 'new' | 'all'),
retry_errors, from_date (only files modified on/after this date: 'yyyy-mm-dd', 'dd.mm.yyyy' or 'yymmdd'), filter
(regular expression on the relative path), max_files (per pass), dry_run (list only), min_file_age_minutes,
incomplete_after_hours, bin_minutes (60), include_protocols (False), protocol_margin_seconds (0: excluded after the end
of a protocol as well), protocols (True), contractions ('all'), thin_factor (10), thin_mode ('nth'), compress (False),
events (True), gaps (True: <name>_gaps.csv, <name>_channels.csv, summary columns noSignal_s, nChamberOut), workers
(1; > 1: recordings analysed in parallel processes), flag_capture (90), flag_extra_beats (10), flag_amplitude_change
(30), quiet. All other keywords are analysis options of myodish_analysis (e.g.
rockerFilter=True, rocker='stopped', threshold=300), applied to all recordings.

Run it once a day by the scheduler of the operating system (cron / launchd / Windows task scheduler), e.g.
    0 7 * * *  /path/to/venv/bin/mda-watch /data/myodish/raw /data/myodish/results --quiet
or keep it running with interval=24.

TS 2026-10-08
"""
from __future__ import annotations

import datetime as _dt
import gzip
import math
import os
import re
import shutil
import time
import warnings
import zlib

import numpy as np
import pandas as pd

from . import __version__
from ._matlab import mround
from .analysis import myodish_analysis
from .log_entries import log_entries
from .options import options as make_options
from .protocols import find_protocols
from .read_mdd import read_header
from .signal_gaps import signal_gaps
from .write_results import write_results

INDEX_NAME = "mda_index.csv"
INDEX_COLUMNS = ["file", "bytes", "modified", "logBytes", "status", "version", "implementation", "code", "options",
                 "analyzed", "seconds", "nContractions", "outputs", "message"]
LOCK_NAME = "mda_watch.lock"
LOCK_HOURS = 12.0  # an older lock file is ignored (watcher crashed)
WATCH_DEFAULTS = dict(interval=0.0, reanalyze="outdated", retry_errors=False, from_date=None, filter=None,
                      max_files=None, dry_run=False, min_file_age_minutes=10.0, incomplete_after_hours=30.0,
                      bin_minutes=60.0, include_protocols=False, protocol_margin_seconds=0.0, protocols=True,
                      contractions="all", thin_factor=10, thin_mode="nth", compress=False, events=True, gaps=True,
                      workers=1,
                      flag_capture=90.0, flag_extra_beats=10.0, flag_amplitude_change=30.0, quiet=False)
_TIME_FMT = "%Y-%m-%d %H:%M:%S"
_SET_BY_WATCHER = ("output", "labels", "metadata", "protocol", "groupby")  # not allowed as analysis options
_NOT_IN_OPTIONS = ("showfigures", "quiet", "chunkseconds")  # keywords of myodish_analysis, not of options()
_STIM_CODES = ("stimfrequency", "stimcurrent", "chargeduration", "dechargeduration", "chargecurrent",
               "dechargecurrent", "stimpulse", "stimpulses", "stimpolarisation", "stimpolarity", "polarity",
               "pauseduration", "sequence", "stimsequence", "spikethresh")


# ------------------------------------------------------------------------------------------------ public
def watch(raw_folder, results_folder, **kw):
    """One pass (interval=0) or repeated passes (interval in hours) over raw_folder; returns (index, report)."""
    wopts = {k: kw.pop(k) for k in list(kw) if k in WATCH_DEFAULTS}
    o = dict(WATCH_DEFAULTS, **wopts)
    if str(o["reanalyze"]).lower() not in ("outdated", "new", "all"):
        raise ValueError("reanalyze: 'outdated', 'new' or 'all' expected")
    o["contractions"] = str(o["contractions"]).lower()
    o["thin_mode"] = str(o["thin_mode"]).lower()
    if o["contractions"] not in ("all", "thinned", "none"):
        raise ValueError("contractions: 'all', 'thinned' or 'none' expected")
    if o["thin_mode"] not in ("nth", "median"):
        raise ValueError("thin_mode: 'nth' or 'median' expected")
    if int(o["thin_factor"]) < 1:
        raise ValueError("thin_factor: integer >= 1 expected")
    if not os.path.isdir(raw_folder):
        raise FileNotFoundError(f"watch: folder not found: {raw_folder}")
    bad = [k for k in kw if k.lower() in _SET_BY_WATCHER]
    if bad:
        raise ValueError(f"watch: {', '.join(bad)} is set by the watcher (labels per channel: <name>_labels.csv)")
    make_options(**{k: v for k, v in kw.items() if k.lower() not in _NOT_IN_OPTIONS})  # unknown options: error now
    while True:
        index, report = _one_pass(os.path.abspath(raw_folder), os.path.abspath(results_folder), o, kw)
        if not o["interval"] or o["interval"] <= 0:
            return index, report
        if not o["quiet"]:
            nxt = _dt.datetime.now() + _dt.timedelta(hours=float(o["interval"]))
            print(f"next pass {nxt:%Y-%m-%d %H:%M} (Ctrl+C stops)")
        time.sleep(float(o["interval"]) * 3600)


def mda_version():
    """version of MyoDishAnalysis as in MATLAB ('1.0.0b1' --> '1.0.0-beta.1')."""
    m = re.fullmatch(r"(\d+\.\d+\.\d+)(?:(a|b|rc)(\d+))?", __version__)
    if not m:
        return __version__
    if not m.group(2):
        return m.group(1)
    return "%s-%s.%s" % (m.group(1), {"a": "alpha", "b": "beta", "rc": "rc"}[m.group(2)], m.group(3))


def code_fingerprint():
    """adler32 (hex) of the core modules (all modules of the package except command line, self test, watcher, GUI)."""
    p = os.path.dirname(os.path.abspath(__file__))
    files = sorted(f for f in os.listdir(p) if f.endswith(".py") and f not in ("cli.py", "selftest.py", "watch.py"))
    a = 1
    for f in files:
        with open(os.path.join(p, f), "rb") as fh:
            a = zlib.adler32(f.encode() + fh.read(), a)
    return "%08x" % (a & 0xFFFFFFFF)


def options_text(analysis_options, o=None):
    """canonical text of the options that change the results (index column 'options'; same text as in MATLAB)."""
    o = dict(WATCH_DEFAULTS, **(o or {}))
    d = {"binminutes": o["bin_minutes"], "protocols": bool(o["protocols"]), "contractions": str(o["contractions"]),
         "compress": bool(o["compress"]), "events": bool(o["events"]),
         "includeprotocols": bool(o["include_protocols"]), "gaps": bool(o["gaps"])}
    if not o["include_protocols"]:
        d["protocolmarginseconds"] = o["protocol_margin_seconds"]
    if str(o["contractions"]) == "thinned":
        d["thinfactor"] = o["thin_factor"]
        d["thinmode"] = str(o["thin_mode"])
    for k, v in analysis_options.items():
        d[str(k).lower()] = v
    return "; ".join(f"{k}={_value_text(d[k])}" for k in sorted(d))


def parse_date(s):
    """'yyyy-mm-dd', 'dd.mm.yyyy' or 'yymmdd' --> datetime (start of the day)."""
    if s is None or isinstance(s, _dt.datetime):
        return s
    if isinstance(s, _dt.date):
        return _dt.datetime(s.year, s.month, s.day)
    s = str(s).strip()
    for fmt in ("%Y-%m-%d", "%d.%m.%Y", "%y%m%d"):
        try:
            return _dt.datetime.strptime(s, fmt)
        except ValueError:
            pass
    raise ValueError(f"from_date: 'yyyy-mm-dd', 'dd.mm.yyyy' or 'yymmdd' expected, not '{s}'")


def read_index(results_folder):
    f = os.path.join(results_folder, INDEX_NAME)
    if not os.path.isfile(f):
        return pd.DataFrame(columns=INDEX_COLUMNS)
    X = pd.read_csv(f, dtype=str, keep_default_na=False)
    for c in INDEX_COLUMNS:
        if c not in X.columns:
            X[c] = ""
    for c in ("bytes", "logBytes", "seconds", "nContractions"):
        X[c] = pd.to_numeric(X[c], errors="coerce")
    return X[INDEX_COLUMNS].reset_index(drop=True)


def event_category(code, text):
    """category of a log entry: comment, protocol, recording, schedule, stimulation, rocker, calibration, warning,
    other (same rules as in MATLAB)."""
    c = str(code).strip().lower()
    t = str(text).strip().lower()
    if c == "comment":
        if re.match(r"^(started|stopped) (parallel )?recording", t) or t.startswith("approaching 2 gb limit"):
            return "recording"
        if re.match(r'^(jump to \d+\s*bpm|s\d+ beat|\d+([.,]\d+)?\s*(hz|ma|bpm|ms)$|pause\s*\d+\s*sec|restored stimulation|'
                    r'keeping pulse settings|stimfrequency\s*\d+|"?rocker stop time)', t):
            return "protocol"  # steps written by the schedule files
        if "schedule" in t or t.startswith("saved settings"):
            return "schedule"
        if re.match(r"^(start|end|stop)\b", t) or re.search(r"\b(started|ended)$", t):
            return "protocol"
        return "comment"
    if c in _STIM_CODES:
        return "stimulation"
    if c in ("rockerspeed", "rocker"):
        return "rocker"
    if c in ("offset", "calibration") or (c == "event" and "extended sensor mode" in t):
        return "calibration"
    if c == "schedule":
        return "schedule"
    if c in ("warning", "error"):
        return "warning"
    if c in ("recording", "programinfo", "nchannels", "channel number", "channel order", "event") or \
            c.startswith("samplingrate"):
        return "recording"
    return "other"


# ------------------------------------------------------------------------------------------------ one pass
def _one_pass(raw, res, o, aopts):
    os.makedirs(res, exist_ok=True)
    lock = os.path.join(res, LOCK_NAME)
    if os.path.isfile(lock) and time.time() - os.path.getmtime(lock) < LOCK_HOURS * 3600:
        msg = f"another watcher is running (lock file {lock}, younger than {LOCK_HOURS:g} h): pass skipped"
        if not o["quiet"]:
            print(msg)
        return read_index(res), msg
    if not o["dry_run"]:
        with open(lock, "w") as fh:
            fh.write(f"{os.getpid()} {_dt.datetime.now():{_TIME_FMT}}\n")
    try:
        return _scan_and_analyse(raw, res, o, aopts)
    finally:
        if not o["dry_run"] and os.path.isfile(lock):
            try:
                os.remove(lock)
            except OSError as ex:
                print(f"warning: lock file {lock} could not be deleted ({ex}); delete it, otherwise the next "
                      f"passes are skipped for {LOCK_HOURS:g} h")


def _scan_and_analyse(raw, res, o, aopts):
    X = read_index(res)
    pos = {f: i for i, f in enumerate(X["file"])}
    version, code = mda_version(), code_fingerprint()
    otext = options_text(aopts, o)
    from_date = parse_date(o["from_date"])
    rx = re.compile(o["filter"], re.I) if o["filter"] else None
    now = time.time()
    todo = []
    for rel, f in _find_recordings(raw):
        if rx and not rx.search(rel):
            continue
        st = os.stat(f)
        logf = f[:-4] + "_log.log"
        logBytes = os.path.getsize(logf) if os.path.isfile(logf) else -1
        lastChange = max(st.st_mtime, os.path.getmtime(logf) if logBytes >= 0 else 0)
        if from_date is not None and st.st_mtime < from_date.timestamp():
            continue
        if now - lastChange < 60 * float(o["min_file_age_minutes"]):
            continue  # still written / copied
        modified = _dt.datetime.fromtimestamp(st.st_mtime, _dt.timezone.utc).strftime(_TIME_FMT) + " UTC"
        why = _why(X.iloc[pos[rel]] if rel in pos else None, st.st_size, modified, logBytes, version, code, otext, o)
        if why:
            todo.append(dict(rel=rel, f=f, bytes=st.st_size, modified=modified, logBytes=logBytes,
                             lastChange=lastChange, why=why))
    if o["max_files"] is not None:
        todo = todo[:int(o["max_files"])]
    if not o["quiet"]:
        print(f"{_dt.datetime.now():{_TIME_FMT}}  {raw}: {len(todo)} recording(s) to analyse")
    if o["dry_run"]:
        for t in todo:
            print(f"  {t['rel']}  ({t['why']})")
        return X, ""
    jobs = [(t, res, o, aopts, version, code, otext, now) for t in todo]
    blocks = []

    def store(row, block):
        nonlocal X
        if row["status"] in ("ok", "error"):
            blocks.append(block or f"{row['file']}\n  {row['status']}: {row['message']}\n")
        if not o["quiet"]:
            msg = f": {row['message']}" if row["status"] != "ok" else ""
            print(f"  {row['file']}: {row['status']} ({row['seconds']:g} s){msg}")
        rel = row["file"]
        if rel in pos:
            for k, v in row.items():
                X.at[pos[rel], k] = v
        else:
            pos[rel] = len(X)
            X = pd.DataFrame(X.to_dict("records") + [row], columns=INDEX_COLUMNS)
        _write_index(res, X)

    workers = int(o["workers"] or 1)
    if workers > 1 and len(jobs) > 1:
        import multiprocessing
        from concurrent.futures import ProcessPoolExecutor, as_completed
        # 'spawn' on all systems (default on macOS and Windows; fork in a multi-threaded process can deadlock)
        with ProcessPoolExecutor(max_workers=workers, mp_context=multiprocessing.get_context("spawn")) as ex:
            futs = [ex.submit(_process, j) for j in jobs]
            for fu in as_completed(futs):
                store(*fu.result())
    else:
        for j in jobs:
            store(*_process(j))
    if jobs:  # index in the order of the files (parallel processing finishes in any order)
        X = X.sort_values("file", kind="stable").reset_index(drop=True)
        _write_index(res, X)
    report = ""
    if blocks:
        blocks.sort()  # order of the files (parallel processing finishes in any order)
        head = (f"MyoDishAnalysis {version} (Python) watcher report {_dt.datetime.now():{_TIME_FMT}}\n"
                f"raw folder: {raw}\nresults:    {res}\noptions:    {otext}\n\n")
        report = head + "\n".join(blocks)
        d = os.path.join(res, "reports")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, f"mda_report_{_dt.datetime.now():%Y-%m-%d_%H%M%S}.txt"), "w",
                  encoding="utf-8") as fh:
            fh.write(report)
        if not o["quiet"]:
            print("\n" + report)
    return X, report


def _process(job):
    """header check and analysis of one recording; returns (index row, report block). Runs in a worker process too."""
    t, res, o, aopts, version, code, otext, now = job
    row = dict(file=t["rel"], bytes=t["bytes"], modified=t["modified"], logBytes=t["logBytes"], status="",
               version=version, implementation="Python", code=code, options=otext,
               analyzed=_dt.datetime.now().strftime(_TIME_FMT), seconds=math.nan, nContractions=math.nan, outputs="",
               message="")
    t0 = time.time()
    block = ""
    if t["logBytes"] < 0:
        row.update(status="noLog", message="no log file <name>_log.log")
    else:
        try:
            hopts = make_options(**{k: v for k, v in aopts.items() if k.lower() not in _NOT_IN_OPTIONS})
            H = read_header(t["f"], hopts)
            if H.recordingStopped is False and now - t["lastChange"] < 3600 * float(o["incomplete_after_hours"]):
                row.update(status="running", message="no 'Recording stopped' in the log file yet")
            else:
                row, block = _analyse(t["f"], t["rel"], H, res, row, o, aopts)
        except Exception as ex:  # noqa: BLE001 - one bad recording must not stop the pass
            row.update(status="error", message=_clean(f"{type(ex).__name__}: {ex}"))
    row["seconds"] = round(time.time() - t0, 1)
    return row, block


def _why(r, nbytes, modified, logBytes, version, code, otext, o):
    """reason to analyse the recording ('' = nothing to do)."""
    if r is None:
        return "new"
    old = _parse_time(r["modified"])
    if (r["bytes"] != nbytes or r["logBytes"] != logBytes or old is None
            or abs((old - _parse_time(modified)).total_seconds()) > 2):
        return "changed"
    status = r["status"]
    if status in ("running", "noLog"):
        return "check " + status
    outdated = ""
    if r["version"] != version:
        outdated = "other version"
    elif r["options"] != otext:
        outdated = "other options"
    elif r["implementation"] == "Python" and r["code"] != code:
        outdated = "core code changed"
    mode = str(o["reanalyze"]).lower()
    if status == "error":
        if o["retry_errors"]:
            return "retry error"
        return ("retry error, " + outdated) if outdated and mode != "new" else ""
    if mode == "all":
        return "reanalyze all"
    if mode == "outdated" and outdated:
        return outdated
    return ""


# ------------------------------------------------------------------------------------------------ one recording
def _analyse(f, rel, H, res, row, o, aopts):
    """the analyses of one recording (only calls of the MyoDishAnalysis functions)."""
    n = os.path.splitext(os.path.basename(f))[0]
    outDir = os.path.join(res, os.path.dirname(rel))
    os.makedirs(outDir, exist_ok=True)
    meta = f[:-4] + "_labels.csv"
    meta = meta if os.path.isfile(meta) else None
    msgs, outputs = [], []
    P = None
    if o["protocols"] or not o["include_protocols"]:
        try:
            P = find_protocols(H)
        except Exception as ex:  # noqa: BLE001
            msgs.append(f"protocols: {type(ex).__name__}: {ex}")
    W = _protocol_windows(P, float(o["protocol_margin_seconds"]))
    fr, to, labels, bins = _ranges(H, float(o["bin_minutes"]) * 60, None if o["include_protocols"] else W)
    for suffix in ("_contractions.csv", "_contractions.csv.gz"):  # results of earlier options
        if os.path.isfile(os.path.join(outDir, n + suffix)):
            os.remove(os.path.join(outDir, n + suffix))
    E = None
    if o["events"]:
        E = log_entries(H.logFile)
        E.insert(4, "category", [event_category(c, t) for c, t in zip(E["code"], E["text"])])
        _for_csv(E).to_csv(os.path.join(outDir, n + "_events.csv"), index=False)
        outputs.append(n + "_events.csv")
    G = None
    if o["gaps"]:
        try:
            G = signal_gaps(H)
            _for_csv(_gaps_out(G, H, E)).to_csv(os.path.join(outDir, n + "_gaps.csv"), index=False)
            outputs.append(n + "_gaps.csv")
        except Exception as ex:  # noqa: BLE001
            G = None
            msgs.append(f"gaps: {type(ex).__name__}: {ex}")
    S = None
    Call = None
    nC = 0
    if len(fr):
        C, S, info = myodish_analysis(f, None, fr, to, labels=labels, metadata=meta, quiet=True, **aopts)
        nC = len(C)
        binOf = dict(zip(labels, bins))
        S.insert(int(S.columns.get_loc("range")) + 1, "bin", [binOf[r] for r in S["range"]])
        C.insert(int(C.columns.get_loc("range")) + 1, "bin", [binOf[r] for r in C["range"]])
        _add_comments(S, E)
        if o["gaps"]:
            _add_gaps(S, G)
        Call = C
        C = _sample(C, labels, W if o["include_protocols"] else None, o)
        write_results(os.path.join(outDir, n + ".csv"), C, S, info)
        cf = os.path.join(outDir, n + "_contractions.csv")
        if o["contractions"] == "none":
            os.remove(cf)
        elif o["compress"]:
            with open(cf, "rb") as src, gzip.GzipFile(cf + ".gz", "wb", mtime=0) as dst:
                shutil.copyfileobj(src, dst)
            os.remove(cf)
        outputs.insert(0, n + ".csv")
        msgs = list(info.get("notes", [])) + msgs
    else:
        msgs.append("no time outside the stimulation protocols")
    CH = None
    if o["gaps"] and G is not None:
        CH = _channel_status(H, Call, G, E, n)
        _for_csv(CH).to_csv(os.path.join(outDir, n + "_channels.csv"), index=False)
        outputs.append(n + "_channels.csv")
    if o["protocols"] and P is not None and len(P):
        try:
            myodish_analysis(f, None, protocol="all", metadata=meta, quiet=True,
                             output=os.path.join(outDir, n + "_protocols.csv"), **aopts)
            outputs.append(n + "_protocols.csv")
        except Exception as ex:  # noqa: BLE001
            msgs.append(f"protocols: {type(ex).__name__}: {ex}")
    row.update(status="ok", nContractions=nC, outputs="; ".join(outputs), message=_clean(" | ".join(msgs)))
    return row, _report_block(rel, H, S, o, CH, G)


def _gaps_out(G, H, E):
    """periods without signal with clock times and the comments of the log file within 5 min of their start or end
    (this channel or all channels)."""
    Gw = G.copy()
    if E is not None and len(E):
        cm = E[E["category"] == "comment"]
        t, ch, tx = cm["t_file"].to_numpy(float), cm["channel"].to_numpy(float), cm["text"].astype(str).tolist()
    else:
        t, ch, tx = np.zeros(0), np.zeros(0), []
    cf, ct, txt = [], [], []
    for a, b, c, ue in zip(G["from"].to_numpy(float), G["to"].to_numpy(float), G["channel"].to_numpy(float),
                           G["untilEnd"].to_numpy(bool)):
        cf.append(_time_label(H, a, a))
        ct.append(_time_label(H, b, b))
        near = np.abs(t - a) <= 300
        if not ue:
            near = near | (np.abs(t - b) <= 300)
        k = np.flatnonzero(near & ((ch == c) | (ch == 0)))
        txt.append(" | ".join(_clean(tx[i]) for i in k))
    pos = int(Gw.columns.get_loc("duration")) + 1
    Gw.insert(pos, "clockFrom", cf)
    Gw.insert(pos + 1, "clockTo", ct)
    Gw["comments"] = txt
    return Gw


def _add_gaps(S, G):
    """columns noSignal_s (s without signal of the channel in the range) and nChamberOut (chambers taken out)."""
    noSig, nOut = [], []
    for a, b, c in zip(S["from"].to_numpy(float), S["to"].to_numpy(float), S["channel"].to_numpy(float)):
        if G is None or not len(G):
            noSig.append(0.0)
            nOut.append(0.0)
            continue
        g = G[G["channel"].to_numpy(float) == c]
        gf, gt = g["from"].to_numpy(float), g["to"].to_numpy(float)
        noSig.append(float(np.sum(np.maximum(0.0, np.minimum(gt, b) - np.maximum(gf, a)))))
        nOut.append(float(np.sum((g["type"].to_numpy() == "chamber out") & ~g["fromStart"].to_numpy(bool)
                                 & (gf >= a) & (gf <= b))))
    S["noSignal_s"] = noSig
    S["nChamberOut"] = nOut


_RX_END = re.compile(r"discard|remov|not beating|no beat|stopped beating|dead|died|infect|contamin|fix|froz|moved|"
                     r"taken out|replac|end of exp|sharp|imaging|histo|rna|pcr", re.IGNORECASE)


def _channel_status(H, C, G, E, name):
    """one row per channel: status at the end of the recording, signal, gaps, last contraction, comments about the
    end."""
    TT = float(H.totalSeconds)
    idTxt = _id_date(name)
    if E is not None and len(E):
        cm = E[E["category"] == "comment"]
        cch, ctx = cm["channel"].to_numpy(float), cm["text"].astype(str).tolist()
    else:
        cch, ctx = np.zeros(0), []
    rows = []
    for c in [int(x) for x in np.ravel(H.dataChannels)]:
        g = G[G["channel"].to_numpy(float) == c]
        typ = g["type"].to_numpy()
        fs_, ue = g["fromStart"].to_numpy(bool), g["untilEnd"].to_numpy(bool)
        noSig = float(np.sum(g["duration"].to_numpy(float)))
        r = dict(channel=c, status="", beatingAtEnd=False, signal_s=max(0.0, TT - noSig), noSignal_s=noSig,
                 nChamberOut=float(np.sum((typ == "chamber out") & ~fs_)),
                 nTechnical=float(np.sum(np.isin(typ, ["board group", "controller", "saturated"]))),
                 firstSignal_s=math.nan, lastSignal_s=math.nan, nContractions=0.0, lastContraction_s=math.nan,
                 lastContractionClock="", lastAmplitude=math.nan, maxAmplitude=math.nan,
                 lastAmplitude_pctMax=math.nan, idDate=idTxt, daysSinceIdDate=math.nan, daysInCulture=math.nan,
                 endComments="")
        cc = C[C["channel"].to_numpy(float) == c] if C is not None and len(C) else None
        r["nContractions"] = float(len(cc)) if cc is not None else 0.0
        if np.any(typ == "no signal"):
            r["status"] = "no slice"
        else:
            r["firstSignal_s"], r["lastSignal_s"] = 0.0, TT
            k = np.flatnonzero(fs_ & ~ue)
            if k.size:
                r["firstSignal_s"] = float(g["to"].iat[k[0]])
            k = np.flatnonzero(ue & ~fs_)
            if cc is not None and len(cc):
                r["lastContraction_s"] = float(cc["t_peak"].max())
            if k.size:
                r["lastSignal_s"] = float(g["from"].iat[k[0]])
            r["beatingAtEnd"] = (not math.isnan(r["lastContraction_s"])) and \
                r["lastSignal_s"] - r["lastContraction_s"] <= 1800
            if k.size and typ[k[0]] == "chamber out":
                r["status"] = "removed"
            elif k.size:
                r["status"] = "signal lost"
            elif r["beatingAtEnd"]:
                r["status"] = "beating"
            else:
                r["status"] = "not beating"
        if cc is not None and len(cc):
            inc = cc[cc["included"].to_numpy(bool)]
            if not len(inc):
                inc = cc
            inc = inc.sort_values("t_peak", kind="stable")
            amp = inc["amplitude"].to_numpy(float)
            r["lastAmplitude"] = float(np.nanmedian(amp[-10:])) if np.any(~np.isnan(amp[-10:])) else math.nan
            r["maxAmplitude"] = _prctile(amp, 95)
            if r["maxAmplitude"] > 0:
                r["lastAmplitude_pctMax"] = 100 * r["lastAmplitude"] / r["maxAmplitude"]
            j = int(np.argmax(cc["t_peak"].to_numpy(float)))
            r["lastContractionClock"] = _time_label(H, r["lastContraction_s"], r["lastContraction_s"])
            if "daysInCulture" in cc.columns:
                r["daysInCulture"] = float(cc["daysInCulture"].iat[j])
        tRef = r["lastContraction_s"] if not math.isnan(r["lastContraction_s"]) else r["lastSignal_s"]
        if idTxt and not math.isnan(H.recordingStart) and not math.isnan(tRef):
            d = _dt.date.fromisoformat(idTxt)
            r["daysSinceIdDate"] = H.recordingStart + tRef / 86400 - (d.toordinal() + 366)
        k = [i for i in range(len(ctx)) if (cch[i] == c or cch[i] == 0) and _RX_END.search(ctx[i])]
        r["endComments"] = " | ".join(_clean(ctx[i]) for i in k)
        rows.append(r)
    return pd.DataFrame(rows)


def _id_date(name):
    """date of the experiment ID in the file name: first part (between '_') of letters + 6 digits yymmdd ('' if
    none)."""
    for part in name.split("_"):
        m = re.fullmatch(r"[A-Za-z]*(\d{6})", part)
        if not m:
            continue
        y, mo, d = int(m.group(1)[:2]), int(m.group(1)[2:4]), int(m.group(1)[4:])
        try:
            return _dt.date(2000 + y, mo, d).isoformat()
        except ValueError:
            continue
    return ""


def _prctile(x, p):
    """MATLAB prctile of a vector (NaN ignored)"""
    x = np.sort(np.asarray(x, float)[~np.isnan(np.asarray(x, float))])
    n = x.size
    if n == 0:
        return math.nan
    if n == 1:
        return float(x[0])
    q = 100 * (np.arange(1, n + 1) - 0.5) / n
    return float(np.interp(min(max(p, q[0]), q[-1]), q, x))


def _gap_lines(CH, G):
    """report: periods without signal by type, channels that do not end beating."""
    lines = []
    if CH is None or G is None:
        return lines
    parts = []
    for t in ("chamber out", "board group", "controller", "saturated"):
        n = int(np.sum(G["type"].to_numpy() == t)) if len(G) else 0
        if n:
            parts.append(f"{n} {t}")
    if parts:
        lines.append("  signal gaps: " + ", ".join(parts))
    parts = [f"ch{int(c)} {st}" for c, st in zip(CH["channel"], CH["status"]) if st != "beating"]
    if parts:
        lines.append("  end of recording: " + ", ".join(parts))
    return lines


def _protocol_windows(P, margin):
    """[from to] of the protocols (to + margin), merged where they overlap."""
    if P is None or not len(P):
        return np.zeros((0, 2))
    W = np.c_[P["from"].to_numpy(float), P["to"].to_numpy(float) + margin]
    W = W[np.argsort(W[:, 0], kind="stable")]
    out = [list(W[0])]
    for a, b in W[1:]:
        if a <= out[-1][1]:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return np.array(out, dtype=float)


def _ranges(H, binS, W):
    """time bins of binS s (half-open), without the windows W (None: bins only); returns from, to, range labels, bin
    labels (range label = clock time of the start of the range)."""
    T = float(H.totalSeconds)
    edges = list(np.arange(0.0, T, binS)) if binS > 0 else [0.0]
    if len(edges) > 1 and T - edges[-1] <= 1:
        edges = edges[:-1]  # no bin shorter than 1 s at the end
    bfr = np.array(edges, dtype=float)
    bto = np.append(bfr[1:], T)
    fr, to, labels, bins = [], [], [], []
    for a, b in zip(bfr, bto):
        last = b == T
        pieces = [[a, b]]
        if W is not None:
            for wa, wb in W:
                nxt = []
                for pa, pb in pieces:
                    if wb <= pa or wa >= pb:
                        nxt.append([pa, pb])
                        continue
                    if wa > pa:
                        nxt.append([pa, wa])
                    if wb < pb:
                        nxt.append([wb, pb])
                pieces = nxt
        for pa, pb in pieces:
            if pb - pa < 1:
                continue  # no range shorter than 1 s
            fr.append(pa)
            to.append(pb if (last and pb == T) else pb - 1e-9)  # half-open: no contraction twice
            labels.append(_time_label(H, pa, pb))
            bins.append(_time_label(H, a, b))
    return np.array(fr, dtype=float), np.array(to, dtype=float), labels, bins


def _time_label(H, a, b):
    if not math.isnan(H.recordingStart):
        sec = int(mround((H.recordingStart - 719529.0) * 86400 + a))
        return (_dt.datetime(1970, 1, 1) + _dt.timedelta(seconds=sec)).strftime(_TIME_FMT)
    return "%s-%s min" % (_g(a / 60), _g(mround(b) / 60))


def _add_comments(S, E):
    """columns nComments and comments: comments of the log file in the range (channel of the row or channel 0)."""
    nC, txt = [], []
    if E is not None and len(E):
        cm = E[E["category"] == "comment"]
        t, ch, tx = cm["t_file"].to_numpy(float), cm["channel"].to_numpy(float), cm["text"].astype(str).tolist()
    else:
        t, ch, tx = np.zeros(0), np.zeros(0), []
    for a, b, c in zip(S["from"].to_numpy(float), S["to"].to_numpy(float), S["channel"].to_numpy(float)):
        k = np.flatnonzero((t >= a) & (t <= b) & ((ch == c) | (ch == 0)))
        nC.append(float(k.size))
        txt.append(" | ".join(_clean(tx[i]) for i in k))
    S["nComments"] = nC
    S["comments"] = txt


def _sample(C, labels, W, o):
    """contractions to save: all, every thin_factor-th, or medians of blocks of thin_factor (extra beats and the
    contractions in the windows W always complete); columns sampledEvery and sampleMode."""
    C = C.reset_index(drop=True)
    pos = C.columns.get_loc("bin") + 1
    if o["contractions"] != "thinned" or len(C) == 0:
        C.insert(pos, "sampledEvery", 1.0)
        C.insert(pos + 1, "sampleMode", "singleBeat")
        return C
    N = int(o["thin_factor"])
    tp = C["t_peak"].to_numpy(float)
    keep = np.array(C["beatType"] == "extra", dtype=bool)  # writable copy
    if W is not None:
        for a, b in W:
            keep |= (tp >= a) & (tp <= b)
    rmap = {r: i for i, r in enumerate(labels)}
    rIdx = C["range"].map(rmap).to_numpy(float)
    ch = C["channel"].to_numpy(float)
    order = np.lexsort((tp, ch))  # per channel in time order
    single, blocks = [], []  # single rows: (index, sampledEvery); blocks: lists of indices (median)
    if o["thin_mode"] == "nth":
        k = {}
        for i in order:
            if keep[i]:
                single.append((i, 1.0))
                continue
            k[ch[i]] = k.get(ch[i], -1) + 1
            if k[ch[i]] % N == 0:
                single.append((i, float(N)))
    else:
        inc, rock, bt = C["included"].to_numpy(), C["rockerMoving"].to_numpy(), C["beatType"].astype(str).to_numpy()
        cur, prev = [], None
        for i in order:
            if keep[i]:  # kept complete; does not interrupt the blocks of the other contractions
                single.append((i, 1.0))
                continue
            key = (ch[i], rIdx[i], bt[i], bool(inc[i]), bool(rock[i]))
            if cur and (key != prev or len(cur) == N):
                blocks.append(cur)
                cur = []
            cur.append(i)
            prev = key
        if cur:
            blocks.append(cur)
    idx = [i for i, _ in single]
    out = C.iloc[idx].copy()
    every = [e for _, e in single]
    mode = ["singleBeat"] * len(idx)
    if blocks:
        first = [b[0] for b in blocks]
        M = C.iloc[first].copy()
        num = [c for c in C.columns if c not in ("contraction", "channel") and pd.api.types.is_numeric_dtype(C[c].dtype)
               and not pd.api.types.is_bool_dtype(C[c].dtype)]
        A = C[num].to_numpy(float)
        with warnings.catch_warnings():  # all-NaN columns of a block: NaN
            warnings.simplefilter("ignore", RuntimeWarning)
            med = np.vstack([np.nanmedian(A[b], axis=0) for b in blocks])
        M[num] = med
        if "clockTime" in C.columns:
            M["clockTime"] = C["clockTime"].iloc[first].to_numpy() + pd.to_timedelta(M["t_peak"].to_numpy(float)
                                                                                      - tp[first], unit="s")
        out = pd.concat([out, M], ignore_index=True)
        every += [float(len(b)) for b in blocks]
        mode += ["median"] * len(blocks)
    out = out.reset_index(drop=True)
    out.insert(pos, "sampledEvery", every)
    out.insert(pos + 1, "sampleMode", mode)
    rI = out["range"].map(rmap).to_numpy(float)
    o2 = np.lexsort((out["t_peak"].to_numpy(float), out["channel"].to_numpy(float), rI))  # range, channel, time
    return out.iloc[o2].reset_index(drop=True)


def _report_block(rel, H, S, o, CH=None, G=None):
    start = ""
    if not math.isnan(H.recordingStart):
        sec = int(mround((H.recordingStart - 719529.0) * 86400))
        start = ", start " + (_dt.datetime(1970, 1, 1) + _dt.timedelta(seconds=sec)).strftime(_TIME_FMT)
    lines = [f"{rel}  ({H.totalSeconds / 3600:.2f} h, {len(H.dataChannels)} channels{start})",
             "  channel  contractions  capture%  extra%  amplitude first/last range (uN)  change%  flags"]
    if S is None or not len(S):
        return "\n".join([lines[0], "  no time outside the stimulation protocols"] + _gap_lines(CH, G)) + "\n"
    for ch in sorted(S["channel"].unique()):
        s = S[S["channel"] == ch]
        nDet, nInc = s["nDetected"].sum(), s["nContractions"].sum()
        nStim, nMiss, nExtra = s["nStimuli"].sum(), s["nMissedBeats"].sum(), s["nExtraBeats"].sum()
        cap = 100 * (1 - nMiss / nStim) if nStim > 0 else math.nan
        extra = 100 * nExtra / nDet if nDet > 0 else math.nan
        good = s[s["nContractions"] >= 10]
        a1 = good["amplitude_mean"].iloc[0] if len(good) else math.nan
        a2 = good["amplitude_mean"].iloc[-1] if len(good) else math.nan
        chg = 100 * (a2 - a1) / a1 if len(good) > 1 and a1 > 0 else math.nan
        flags = []
        if nDet == 0:
            flags.append("no contractions")
        elif cap < o["flag_capture"]:
            flags.append("capture < %s %%" % _g(o["flag_capture"]))
        if extra > o["flag_extra_beats"]:
            flags.append("extra beats > %s %%" % _g(o["flag_extra_beats"]))
        if abs(chg) > o["flag_amplitude_change"]:
            flags.append("amplitude change > %s %%" % _g(o["flag_amplitude_change"]))
        lines.append("  %7d  %12d  %8s  %6s  %15s / %-15s  %7s  %s" % (
            ch, nInc, _f1(cap), _f1(extra), _f1(a1), _f1(a2), _f1(chg), ", ".join(flags)))
    return "\n".join(lines + _gap_lines(CH, G)) + "\n"


# ------------------------------------------------------------------------------------------------ helpers
def _find_recordings(raw):
    out = []
    for p, dirs, files in os.walk(raw):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for fn in sorted(files):
            if fn.lower().endswith(".mdd") and not fn.startswith("."):
                f = os.path.join(p, fn)
                out.append((os.path.relpath(f, raw).replace(os.sep, "/"), f))
    return out


def _write_index(res, X):
    f = os.path.join(res, INDEX_NAME)
    tmp = f + ".tmp"
    X[INDEX_COLUMNS].to_csv(tmp, index=False)
    os.replace(tmp, f)


def _for_csv(T):
    """as MATLAB writetable: logical --> 1/0, datetime --> 'yyyy-mm-dd HH:MM:SS.fff'."""
    T = T.copy()
    for c in T.columns:
        if T[c].dtype == bool:
            T[c] = T[c].astype(int)
        elif pd.api.types.is_datetime64_any_dtype(T[c].dtype):
            T[c] = T[c].dt.strftime("%Y-%m-%d %H:%M:%S.%f").str[:-3]
    return T


def _parse_time(s):
    """'yyyy-mm-dd HH:MM:SS UTC' (index column 'modified') --> datetime; None if not readable."""
    s = str(s)
    if not s.endswith(" UTC"):
        return None
    try:
        return _dt.datetime.strptime(s[:-4], _TIME_FMT)
    except ValueError:
        return None


def _value_text(v):
    if v is None:
        return ""
    if isinstance(v, (bool, np.bool_)):
        return "1" if v else "0"
    if isinstance(v, (int, float, np.integer, np.floating)):
        return _num(v)
    if isinstance(v, str):
        return v
    a = np.asarray(v).ravel()
    if a.dtype.kind in "biuf":
        return "[" + " ".join(_num(x) for x in a) + "]"
    return "{" + " ".join(str(x) for x in a) + "}"


def _num(x):
    x = float(x)
    if math.isnan(x):
        return "NaN"
    if math.isinf(x):
        return "Inf" if x > 0 else "-Inf"
    return "%.10g" % x


def _g(x):
    return "%g" % x


def _f1(x):
    return "" if x is None or (isinstance(x, float) and math.isnan(x)) else "%.1f" % x


def _clean(s):
    return re.sub(r"[\r\n,]+", " ", str(s)).strip()
