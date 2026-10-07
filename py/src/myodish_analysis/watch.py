"""Automatic analysis of new MyoDish recordings in a folder (watcher): MyoDishAnalysisWatch.m in Python.

    index, report = watch(raw_folder, results_folder, interval=0, reanalyze="outdated", ...)
    mda-watch RAW_FOLDER RESULTS_FOLDER [--interval 24] [--rocker-filter] ...      (command line)

Every pass searches raw_folder (with subfolders) for .mdd files and analyses those that are new, have changed, or were
analysed with another version, other options or (same implementation) other core code. The watcher only calls the
functions of MyoDishAnalysis (myodish_analysis, read_header, find_protocols): improvements of the analysis apply to the
watcher results as well; with reanalyze="outdated" (default) the affected recordings are analysed again.

Per recording (results_folder/<subfolder of raw_folder>/):
  <name>_contractions.csv, _summary.csv, _parameters.csv, _info.csv, _labels.csv (_rockerFilter.csv)
      every single contraction of the whole recording; summary = one row per channel and time bin (bin_minutes,
      default 60 min; range label = clock time of the bin start). Same as
      myodish_analysis(file, None, bins_from, bins_to, labels=..., output='<name>.csv', **analysis_options).
  <name>_protocols_*.csv (if the log file contains stimulation protocols, protocols=True)
      myodish_analysis(file, protocol='all', output='<name>_protocols.csv', **analysis_options): summary per
      protocol, channel and group, protocolResults (FFR, ST thresholds, refractory periods, PRP).
  Labels per channel (metadata): <name>_labels.csv next to the .mdd file (saved by the GUI), if present.
results_folder/mda_index.csv
  one row per recording: file (path relative to raw_folder), bytes, modified (time of the .mdd file, UTC), logBytes, status (ok / error /
  running / noLog), version, implementation (MATLAB / Python), code (fingerprint of the core functions), options,
  analyzed, seconds, nContractions, outputs, message. The same file is used by the MATLAB and the Python watcher.
results_folder/reports/mda_report_<date>_<time>.txt
  report of a pass with analysed recordings: per channel contractions, capture (% of the stimuli followed by a
  contraction), extra beats (% of the detected contractions), mean amplitude in the first and last bin (bins with
  >= 10 included contractions) and flags (no contractions, capture < flag_capture %, extra beats > flag_extra_beats %,
  amplitude change > flag_amplitude_change %).

Recordings are skipped while they are written: files modified less than min_file_age_minutes ago (default 10),
names starting with '.' (rsync temporary files), and recordings whose log file has no 'Recording stopped' entry
yet (status 'running') unless unchanged for incomplete_after_hours (default 30 h, e.g. aborted recordings).
Recordings without log file get the status 'noLog'; they are checked again in every pass. Errors are retried when the
file, the version, the options or the code change, or with retry_errors=True.

Options (keywords): interval (hours between passes, 0 = one pass, default), reanalyze ('outdated' | 'new' | 'all'),
retry_errors, from_date (only files modified on/after this date: 'yyyy-mm-dd', 'dd.mm.yyyy' or 'yymmdd'), filter
(regular expression on the relative path), max_files (per pass), dry_run (list only), min_file_age_minutes,
incomplete_after_hours, bin_minutes, protocols (True), flag_capture (90), flag_extra_beats (10),
flag_amplitude_change (30), quiet. All other keywords are analysis options of myodish_analysis (e.g.
rockerFilter=True, rocker='stopped', threshold=300), applied to all recordings.

Run it once a day by the scheduler of the operating system (cron / launchd / Windows task scheduler), e.g.
    0 7 * * *  /path/to/venv/bin/mda-watch /data/myodish/raw /data/myodish/results --quiet
or keep it running with interval=24.

TS 2026-10-08
"""
from __future__ import annotations

import datetime as _dt
import math
import os
import re
import time
import zlib

import numpy as np
import pandas as pd

from . import __version__
from ._matlab import mround
from .analysis import myodish_analysis
from .options import options as make_options
from .protocols import find_protocols
from .read_mdd import read_header

INDEX_NAME = "mda_index.csv"
INDEX_COLUMNS = ["file", "bytes", "modified", "logBytes", "status", "version", "implementation", "code", "options",
                 "analyzed", "seconds", "nContractions", "outputs", "message"]
LOCK_NAME = "mda_watch.lock"
LOCK_HOURS = 12.0  # an older lock file is ignored (watcher crashed)
WATCH_DEFAULTS = dict(interval=0.0, reanalyze="outdated", retry_errors=False, from_date=None, filter=None,
                      max_files=None, dry_run=False, min_file_age_minutes=10.0, incomplete_after_hours=30.0,
                      bin_minutes=60.0, protocols=True, flag_capture=90.0, flag_extra_beats=10.0,
                      flag_amplitude_change=30.0, quiet=False)
_TIME_FMT = "%Y-%m-%d %H:%M:%S"
_SET_BY_WATCHER = ("output", "labels", "metadata", "protocol", "groupby")  # not allowed as analysis options
_NOT_IN_OPTIONS = ("showfigures", "quiet", "chunkseconds")  # keywords of myodish_analysis, not of options()


# ------------------------------------------------------------------------------------------------ public
def watch(raw_folder, results_folder, **kw):
    """One pass (interval=0) or repeated passes (interval in hours) over raw_folder; returns (index, report)."""
    wopts = {k: kw.pop(k) for k in list(kw) if k in WATCH_DEFAULTS}
    o = dict(WATCH_DEFAULTS, **wopts)
    if str(o["reanalyze"]).lower() not in ("outdated", "new", "all"):
        raise ValueError("reanalyze: 'outdated', 'new' or 'all' expected")
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


def options_text(analysis_options, bin_minutes=60.0, protocols=True):
    """canonical text of the options that change the results (index column 'options'; same text as in MATLAB)."""
    d = {"binminutes": bin_minutes, "protocols": bool(protocols)}
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
    otext = options_text(aopts, o["bin_minutes"], o["protocols"])
    from_date = parse_date(o["from_date"])
    rx = re.compile(o["filter"], re.I) if o["filter"] else None
    hopts = make_options(**{k: v for k, v in aopts.items() if k.lower() not in _NOT_IN_OPTIONS})
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
            todo.append((rel, f, logf, st.st_size, modified, logBytes, lastChange, why))
    if o["max_files"] is not None:
        todo = todo[:int(o["max_files"])]
    if not o["quiet"]:
        print(f"{_dt.datetime.now():{_TIME_FMT}}  {raw}: {len(todo)} recording(s) to analyse")
    if o["dry_run"]:
        for t in todo:
            print(f"  {t[0]}  ({t[7]})")
        return X, ""
    blocks = []
    for rel, f, logf, nbytes, modified, logBytes, lastChange, why in todo:
        row = dict(file=rel, bytes=nbytes, modified=modified, logBytes=logBytes, version=version,
                   implementation="Python", code=code, options=otext, analyzed=_dt.datetime.now().strftime(_TIME_FMT),
                   seconds=math.nan, nContractions=math.nan, outputs="", message="")
        t0 = time.time()
        block = ""
        if logBytes < 0:
            row.update(status="noLog", message="no log file <name>_log.log")
        else:
            try:
                H = read_header(f, hopts)
                if H.recordingStopped is False and now - lastChange < 3600 * float(o["incomplete_after_hours"]):
                    row.update(status="running", message="no 'Recording stopped' in the log file yet")
                else:
                    if not o["quiet"]:
                        print(f"  {rel} ({why}) ...")
                    row, block = _analyse(f, rel, H, res, row, o, aopts)
            except Exception as ex:  # noqa: BLE001 - one bad recording must not stop the pass
                row.update(status="error", message=_clean(f"{type(ex).__name__}: {ex}"))
        row["seconds"] = round(time.time() - t0, 1)
        if row["status"] in ("ok", "error"):
            blocks.append(block or f"{rel}\n  {row['status']}: {row['message']}\n")
        if not o["quiet"] and row["status"] != "ok":
            print(f"  {rel}: {row['status']}: {row['message']}")
        if rel in pos:
            for k, v in row.items():
                X.at[pos[rel], k] = v
        else:
            pos[rel] = len(X)
            X = pd.DataFrame(X.to_dict("records") + [row], columns=INDEX_COLUMNS)
        _write_index(res, X)
    report = ""
    if blocks:
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


def _analyse(f, rel, H, res, row, o, aopts):
    """the analyses of one recording (only calls of the MyoDishAnalysis functions)."""
    n = os.path.splitext(os.path.basename(f))[0]
    outDir = os.path.join(res, os.path.dirname(rel))
    os.makedirs(outDir, exist_ok=True)
    meta = f[:-4] + "_labels.csv"
    meta = meta if os.path.isfile(meta) else None
    fr, to, labels = _bins(H, float(o["bin_minutes"]) * 60)
    C, S, info = myodish_analysis(f, None, fr, to, labels=labels, metadata=meta, quiet=True,
                                  output=os.path.join(outDir, n + ".csv"), **aopts)
    outputs = [n + ".csv"]
    msgs = list(info.get("notes", []))
    if o["protocols"]:
        try:
            P = find_protocols(H)
            if len(P):
                myodish_analysis(f, None, protocol="all", metadata=meta, quiet=True,
                                 output=os.path.join(outDir, n + "_protocols.csv"), **aopts)
                outputs.append(n + "_protocols.csv")
        except Exception as ex:  # noqa: BLE001
            msgs.append(f"protocols: {type(ex).__name__}: {ex}")
    row.update(status="ok", nContractions=len(C), outputs="; ".join(outputs), message=_clean(" | ".join(msgs)))
    return row, _report_block(rel, H, C, S, o)


def _bins(H, binS):
    T = float(H.totalSeconds)
    edges = list(np.arange(0.0, T, binS)) if binS > 0 else [0.0]
    if len(edges) > 1 and T - edges[-1] <= 1:
        edges = edges[:-1]  # no bin shorter than 1 s at the end
    fr = np.array(edges, dtype=float)
    to = np.append(fr[1:] - 1e-9, T)  # half-open bins: no contraction twice
    labels = []
    for a, b in zip(fr, to):
        if not math.isnan(H.recordingStart):
            sec = int(mround((H.recordingStart - 719529.0) * 86400 + a))
            labels.append((_dt.datetime(1970, 1, 1) + _dt.timedelta(seconds=sec)).strftime(_TIME_FMT))
        else:
            labels.append("%s-%s min" % (_g(a / 60), _g(mround(b) / 60)))
    return fr, to, labels


def _report_block(rel, H, C, S, o):
    start = ""
    if not math.isnan(H.recordingStart):
        sec = int(mround((H.recordingStart - 719529.0) * 86400))
        start = ", start " + (_dt.datetime(1970, 1, 1) + _dt.timedelta(seconds=sec)).strftime(_TIME_FMT)
    lines = [f"{rel}  ({H.totalSeconds / 3600:.2f} h, {len(H.dataChannels)} channels{start})",
             "  channel  contractions  capture%  extra%  amplitude first/last bin (uN)  change%  flags"]
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
        lines.append("  %7d  %12d  %8s  %6s  %14s / %-14s  %7s  %s" % (
            ch, nInc, _f1(cap), _f1(extra), _f1(a1), _f1(a2), _f1(chg), ", ".join(flags)))
    return "\n".join(lines) + "\n"


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
