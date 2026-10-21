# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Automatic analysis of new MyoDish recordings in a folder (watcher): MyoDishAnalysisWatch.m in Python.

    index, report = watch(raw_folder, results_folder, reanalyze="new", ...)              one pass
    watch(raw_folder, results_folder, schedule="daily 10:00", ...)                         passes on a schedule
    mda-watch RAW_FOLDER RESULTS_FOLDER [--schedule "daily 10:00"] [--rocker-filter] ...   (command line)

Every pass searches raw_folder (with subfolders) for .mdd files and analyses those that are new or have changed. The
watcher only calls the functions of MyoDishAnalysis (myodish_analysis, read_header, find_protocols, log_entries,
write_results). Recordings analysed earlier with another version of MyoDishAnalysis, other options or (same
implementation) other core code are not analysed again by default (reanalyze="new", 2026-10-12); every pass then shows
a notice (command line, top of the txt and PDF reports) with their number and the command that analyses them again
(reanalyze="outdated"). Earlier results are kept until then.

reanalyze:  'new' (default)  new and changed recordings; recordings with an analysis error are retried when the
                             version, the options or the core code change
            'outdated'       in addition the recordings analysed with another version, other options or other core
                             code (e.g. after an update: all of them, can take hours)
            'all'            every recording again

Result folders (folders=..., 2026-10-15): a quick overview instead of hundreds of files in one folder
  'series' (default)   results_folder/<experiment>/<series>/<nn>/ for recordings with a number in the name
                       (ABC000101/Setup1_ABC000101_3.mdd -> ABC000101/Setup1_ABC000101/03/; also its parallel recordings,
                       e.g. Setup1_ABC000101_3_scheduleFile_..._daily6am.mdd), results_folder/<experiment>/<name>/ for
                       recordings without a number (experiment = folder of the recording in raw_folder, series = name
                       up to its number, see slice_register)
  'flat'               results_folder/<experiment>/ (all files of an experiment in one folder, as before)
  Per experiment (with trends, register, report; see Slice register, Trend images, Reports):
    <experiment>/<experiment>_overview.png     all setups x channels at a glance (amplitude since the start, status,
                                               last 24 h, red flags)
    <experiment>/<experiment>_report.pdf       analysis report of all recordings of the experiment
    <experiment>/<experiment>_slices.csv       slice register
    <experiment>/<series>/<series>_ch<c>.png   course of each channel: since the start and the last 24 h
    <experiment>/<series>/<series>_trends.xlsx the data of these images
    <experiment>/<series>/<nn>/                the results of each recording (below) and its trend images
  The readers (GUI, results browser, flags, slice register, trends_again) take both layouts. Results of earlier passes
  in the other layout are moved when a recording is analysed again; reorganize(results_folder) (mda-watch RESULTS
  --reorganize) moves all of them at once (folders='flat' back).
Per recording (result_format='xlsx', default since 2026-10-14):
  <name>.xlsx               sheets summary, trends, trendComments, channels, gaps, events, parameters, info (version,
                            all options, watcher settings), thresholds (analysis windows), labels (rockerFilter): the
                            tables described below; mda-gui <name>.xlsx opens the analysis
  <name>_contractions.csv.gz, <name>_pulses.csv.gz (all stimulus pulses, option pulseTable), <name>_overview.csv.gz:
                            the large tables (gzip; much faster to write and read than sheets, no row limit)
  <name>_protocols.xlsx, <name>_protocols_contractions.csv.gz, _protocols_pulses.csv.gz   stimulation protocols
  <name>_ch<c>.png          trend image per channel (trends=True; see Trend images; flat layout: in trends/)
  result_format='csv': one file per table as before: <name>_summary.csv, _contractions.csv(.gz), _pulses.csv(.gz),
  _parameters.csv, _info.csv, _thresholds.csv, _labels.csv (_rockerFilter.csv), _overview.csv, _events.csv, _gaps.csv,
  _channels.csv, _trends.csv, _trendComments.csv, _protocols_*.csv (compress=True: contractions and pulses as
  .csv.gz). The readers (GUI, results
  browser, flags, slice register) take both formats; recordings are not analysed again because of the format
  (reanalyze='all' converts the results). Tables (sheets or files):
      contractions: not written with contractions='none'
      summary = one row per channel and time range: time bins of bin_minutes (default 60 min) without the periods of
      the stimulation protocols (include_protocols=False, default; a bin with a protocol gives several ranges).
      range = clock time of the start of the range, bin = clock time of the start of the bin, nComments / comments =
      comments of the log file in the range (this channel or all channels). Contractions: contractions='all' (every
      contraction), 'thinned' (every thin_factor-th contraction per channel, thin_mode='nth', or the median of blocks
      of thin_factor contractions, thin_mode='median'; extra beats and, with include_protocols=True, the contractions in
      the protocols are always kept) or 'none'; columns bin, sampledEvery (number of contractions per row) and
      sampleMode ('singleBeat' / 'median'). compress=True: <name>_contractions.csv.gz (gzip level 6).
  overview (overview_seconds=60, default; 0 = none): medians of all contractions per window of 1 min (file
      time, split at the ranges), channel, beat type, rocker state and inclusion: window (clock time of its start),
      t_from, t_to, nBeats, beatsPerMinute and the median of every parameter. About 1/30 (0.5 Hz) to 1/60 (1 Hz) of the
      rows of all contractions.
  protocols (if the log file contains stimulation protocols, protocols=True)
      myodish_analysis(file, protocol='all', ...): every contraction in the protocols, summary per protocol, channel
      and group, protocolResults (FFR, ST thresholds, refractory periods, PRP).
  events (events=True): all entries of the log file (comments, stimulation and rocker settings, recording,
      calibration, schedule, warnings) with category, clock time and time in the file.
  gaps (gaps=True): periods without force signal (signal_gaps): chamber taken out ('chamber out'), sensor
      board group or controller failures (>= 2 channels within 1 s), saturation, channels without a chamber ('no
      signal'); with clock times and the comments of the log file within 5 min of the start or end. The summary gets
      the columns noSignal_s (s without signal in the range) and nChamberOut (chambers taken out in the range).
  channels (gaps=True): one row per channel: recording, recordingStart, fileLength_s, calibration ('Calibration'
      entries of the log file, AU per mN; several values separated by ';'), status at the end of
      the recording ('beating', 'not beating' = no contraction in the last 30 min with signal outside the stimulation
      protocols, 'protocols only' = no time outside the protocols (not analysed), 'removed' = chamber taken out and
      not put back, 'signal lost' = technical, 'no slice'), beatingAtEnd, s with and without signal, chambers taken out, technical failures,
      contractions, last contraction (time, clock time, median amplitude of the last 10 included contractions, in % of
      the 95th percentile of the recording), date of the experiment ID in the file name (6 digits yymmdd, e.g.
      ABC000101) and days since this date at the last contraction (or the end of the signal), daysInCulture, labels
      setupID, sliceID, species, sampleID, cultureStart, comments about the slice's end (discarded, removed, not
      beating, fixed, frozen, ...).
  Labels per channel (metadata): <name>_labels.csv next to the .mdd file (saved by the GUI), if present.
Slice register (register=True, gaps=True; after each pass with analysed recordings, see slice_register):
  <experiment>/<experiment>_slices.csv and results_folder/mda_slices.csv (all experiments): one row per
  slice (channel of a setup from putting the slice in until it was taken out, the signal was lost or the data end)
  with start, end, reason of the start, end status, last contraction and amplitude, days in culture, chamber-out
  periods.
  A chamber-out period >= new_slice_hours (default 2 h), a recording without signal, a comment such as 'new slice' or
  another sliceID label start a new slice.
results_folder/mda_flags.csv (report=True, 2026-10-14)
  flags of the analysis report per recording and channel (file, analyzed, channel, label, status, nDetected,
  capture_percent, flags, level, red, yellow, from, to = window to open for the channels to check) of all analysed
  recordings (also of earlier passes); read by the results browser of the GUI (flags_table), the experiment reports
  and the overview images.
results_folder/mda_index.csv
  one row per recording: file (path relative to raw_folder), bytes, modified (time of the .mdd file, UTC), logBytes,
  status (ok / error / running / incomplete / parallel / noLog), version, implementation (MATLAB / Python), code
  (fingerprint of the core functions), options, analyzed, seconds, nContractions, outputs, message. The same file is
  used by the MATLAB and the Python watcher.
results_folder/reports/mda_report_<date>_<time>.txt
  report of a pass with analysed recordings: per channel contractions, capture (% of the stimuli followed by a
  contraction), extra beats (% of the detected contractions), mean amplitude in the first and last range (>= 10
  included contractions) and flags (no contractions, capture < flag_capture % (not with arrhythmic pacing, summary
  column arrhythmicPacing: 'arrhythmic pacing'), extra beats > flag_extra_beats %, amplitude change >
  flag_amplitude_change %). It lists the PDF reports of the experiments with analysed recordings.
results_folder/<experiment>/<experiment>_report.pdf (report=True, 2026-10-11; one report per experiment instead of one
  per pass since 2026-10-15; mda_report_root.pdf for recordings directly in raw_folder)
  analysis report of all analysed recordings of the experiment (report.py), made again after every pass with analysed
  recordings of the experiment: first page the overview image of the experiment, then the recordings x channels with
  flags (recordings of the last pass bold, earlier ones with the flags of mda_flags.csv: flags of earlier days stay
  visible), the list of the channels to check and those with slice-quality flags, and pages with traces of the red
  channels of the last pass. Flags: the channels whose analysis should be checked (red: inverted signal; noise
  suspected = uncertain >= flag_uncertain % and extra + missed beats >= flag_irregular %; large extra beats; delay
  pulse -> onset > flag_delay s; stimulus frequency > flag_stim_frequency Hz) and those with slice-quality flags
  (yellow: capture < flag_capture %, extra beats > flag_extra_beats %, amplitude < flag_amplitude uN, amplitude change
  > flag_amplitude_change %, amplitude CV > flag_amplitude_cv %; arrhythmic pacing: no capture and amplitude CV flags);
  channels with fewer than flag_min_beats detected contractions are not flagged. The commands that open the red
  channels in the GUI (MyoDishAnalysisGUI(<name>.xlsx, 'channel', c, 'window', [a b]) / mda-gui <name>.xlsx --channel
  c --window a b).

Trend images (trends=True, default; needs the overview; 2026-10-14), a quick look every morning:
  <experiment>/<experiment>_overview.png   (2026-10-15) one row per setup (numbered series), one column per channel:
      amplitude over the whole time course, background = status at the end of the data of the last slice (green
      beating, red not beating, grey removed, orange signal lost), last 24 h yellow, new slices dashed, texts: last
      amplitude, change in the last 24 h, % of the maximum of the slice; red frame = recordings with red flags of the
      analysis report (number; also flags of earlier passes: mda_flags.csv)
  <series>/<series>_ch<c>.png   (2026-10-15; flat layout: trends/) per setup and channel: left the whole time course
      since the start of the series (all slices, slice changes dashed, the last 24 h yellow, recordings with red flags
      as red bars), right the last 24 h (10-min line, protocols, comments numbered with a list); data in
      <series>/<series>_trends.xlsx (sheets course, last24h, comments, slices; see slice_register)
  <nn>/<name>_ch<c>.png      per recording and channel (with at least 20 included contractions): one panel per
      parameter of trend_parameters (default amplitude, diastolicForce, TTP90, TTR90; any parameter or
      beatsPerMinute), dots = values of the overview (median per minute of the included contractions), line = their
      median per 10 min (5 min up to 3 h, 30 min beyond 30 h), clock time; stimulation protocols as light blue bands
      with their name, periods without signal grey, comments of the log file as numbered purple lines with a list
      below (comments during a protocol only at its start or end); title with the labels of the channel; first / last
      2 h and change in %.
  PNG, 150 dpi, 11 inch wide. The data of the images per recording: sheet trends (channel, window = clock time of
  its start, t_from (s), nBeats = included contractions, the trend parameters (median per window; units as in the
  sheet parameters), bin_from (s): line = median of the rows with the same bin_from; up to 8 x 1440 rows per day) and
  sheet trendComments (channel, number as in the image, t_file, clockTime, text).
  trends_again(results_folder, include=..., trend_parameters=[...]) (mda-watch RESULTS --trends-only) makes the
  images and these sheets again from the result files, and the images of the series and experiments of these
  recordings.
Recordings are skipped while they are written or copied (2026-10-13): files modified less than min_file_age_minutes
ago (default 10), names starting with '.' (rsync temporary files),
  - status 'running': no 'Recording stopped' entry in the log file yet; analysed when the end of the data (start of
    the recording in the log file + duration of the file from its size) is incomplete_after_hours (default 30 h) ago,
    e.g. aborted recordings (without clock time in the log file, or with the clock of the recording computer more
    than 1 h ahead: incomplete_after_hours after the last change of the files),
  - status 'incomplete': the file is shorter than the recording in the log file ('Recording started' -> 'stopped')
    by more than 10 s and more than incomplete_tolerance % (default 2 %; relative because the sample clock of the
    controllers deviates from the clock of the computer by up to about 0.6 %, in one setup by 2 %; 24-h recordings:
    99 % within 90 s; the 10 s protect short recordings, whose start and stop entries can be 1-2 s off). Checked
    again in every pass; analysed (with a note in the message) when unchanged for incomplete_after_hours (copies that
    are never completed). Also 'incomplete', until the file changes: empty files (no data) and files dated before 1990
    (robocopy dates files to 1980 until their copy is finished),
  - status 'parallel' (parallel='skip', default): parallel recordings (e.g. schedule files, snapshots) whose main
    recording is in the same folder of raw_folder (its log file lists the file as 'started parallel recording', with
    the same duration) and selected in the same pass (include / exclude / from_date): the data are in the
    main file and its stimulation protocols in the main file's _protocols_* results. The message names the main file
    and the time window in it. Parallel recordings whose main file is not selected (e.g. include='*schedule*': the
    schedule files only) or missing, and all of them with parallel='analyse', are analysed; the message starts with
    'parallel recording of <main file> (...)'. The slice register ignores parallel recordings whose main file has
    results: no contraction or stimulus is counted twice (2026-10-14),
  - status 'noLog': no log file, or an empty one; analysed when the log file appears or changes.
Errors are retried when the file, the version, the options or the code change, or with retry_errors=True. The index
is written after every analysed recording and once at the end of the pass.
Lock file (2026-10-14): results_folder/mda_watch.lock exists while a pass runs; a second watcher on the same results
folder (Python, MATLAB, another computer) skips its pass. It is refreshed after every recording and during long steps;
a lock file that was not refreshed for 1 h (watcher crashed) is ignored.

Schedule (schedule='...', 2026-10-12; runs until Ctrl+C, in a terminal or as a background process):
    'daily 10:00'           every day at 10:00 (first pass at the next 10:00)
    'weekly Sun 05:00'      every Sunday at 05:00; several days: 'Mon,Thu 06:30'; 'weekdays 07:00' (Mon-Fri)
    'every 2 days 10:00'    every 2nd day at 10:00 (first pass at the next 10:00)
    'every 120 min'         first pass now, then every 120 min (also 'every 6 h')
Passes that are missed (computer asleep, a pass longer than the interval) are not repeated: the next one follows at
the next scheduled time.

Options (keywords): schedule (see above), reanalyze ('new' | 'outdated' | 'all'), retry_errors, from_date (only files
modified on/after this date: 'yyyy-mm-dd', 'dd.mm.yyyy' or 'yymmdd'), include / exclude (wildcard patterns, a string
or a list: * any characters, ? one character; a pattern without '/' is matched against every folder name and the file
name of the path relative to raw_folder, with '/' against the whole path; e.g. include='ABC00*' = all folders starting
with ABC00, include='*schedule*' = schedule files; 2026-10-13), case_sensitive (False: include and exclude ignore
case), parallel ('skip' | 'analyse'), max_files (per pass), dry_run (list only), min_file_age_minutes,
incomplete_after_hours (30), incomplete_tolerance (2 %), bin_minutes (60), include_protocols (False),
protocol_margin_seconds (0: excluded after the end of a protocol as well), protocols (True), contractions ('all'),
thin_factor (10), thin_mode ('nth'), result_format ('xlsx' | 'csv'), folders ('series' | 'flat'), compress (False;
format 'csv'), overview_seconds (60), trends (True), trend_parameters, events (True), gaps (True: gaps and channels
tables, summary columns noSignal_s, nChamberOut), register (True: slice register), new_slice_hours (2), workers (1;
> 1: recordings analysed in parallel processes), flag_capture (90), flag_extra_beats (10), flag_amplitude_change (30),
report (True: PDF report per experiment and mda_flags.csv), flag_uncertain (25), flag_irregular (15), flag_amplitude
(75 uN), flag_amplitude_cv (30), flag_delay (0.15 s), flag_min_beats (50), flag_stim_frequency (10 Hz), quiet. All
other keywords are analysis options of myodish_analysis (e.g. rockerFilter=True, rocker='stopped', threshold=300),
applied to all recordings; settings=file: analysis options from a settings file (settings.py) or earlier results (the
index records their values: after a change of the file the earlier recordings count as analysed with other options).
Advanced: filter (regular expression on the path relative to raw_folder, as re.search; include / exclude are simpler;
case_sensitive applies to it as well).

Keep it running with schedule='daily 07:00' (mda-watch ... --schedule "daily 07:00"), or start one pass a day by the
scheduler of the operating system (cron / launchd / Windows task scheduler), e.g.
    0 7 * * *  /path/to/venv/bin/mda-watch /data/myodish/raw /data/myodish/results --quiet

TS 2026-10-08 (watcher settings in the info table 2026-10-09; pulse table 2026-10-10; schedule and reanalyze 'new'
2026-10-12; arrhythmic pacing, flag_stim_frequency, include / exclude, completeness check, parallel recordings
2026-10-13; results as .xlsx, trend images 2026-10-14; result folders per series, course and overview images, PDF report
per experiment 2026-10-15)
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

from ._matlab import datenum_to_datetime, datetime_to_datenum, mround
from .analysis import myodish_analysis
from .log_entries import log_entries, read_log_text, split_lines, str2double
from .options import options as make_options
from .labels import labels as make_labels
from .parameters import LABEL_NAMES
from .protocols import find_protocols
from .read_mdd import read_header
from .signal_gaps import signal_gaps
from .slice_register import ALL_NAME as SLICES_NAME, result_folder, series_of, slice_register
from .write_results import mda_version, write_results

INDEX_NAME = "mda_index.csv"
INDEX_COLUMNS = ["file", "bytes", "modified", "logBytes", "status", "version", "implementation", "code", "options",
                 "analyzed", "seconds", "nContractions", "outputs", "message"]
LOCK_NAME = "mda_watch.lock"
LOCK_HOURS = 1.0  # a lock file not refreshed for this time is ignored (watcher crashed; refreshed after every
#                  recording, 2026-10-14; before: 12 h after its creation)
_LOCK_TOUCHED = [0.0]  # time of the last heartbeat of the lock file (_touch_lock)
ROBOCOPY_TIME = _dt.datetime(1990, 1, 1).timestamp()  # earlier file times: copy not finished (robocopy: 1980)
WATCH_DEFAULTS = dict(interval=0.0, schedule=None, reanalyze="new", retry_errors=False, from_date=None, filter=None,
                      include=None, exclude=None, case_sensitive=False, parallel="skip",
                      max_files=None, dry_run=False, min_file_age_minutes=10.0, incomplete_after_hours=30.0,
                      incomplete_tolerance=2.0,
                      bin_minutes=60.0, include_protocols=False, protocol_margin_seconds=0.0, protocols=True,
                      contractions="all", thin_factor=10, thin_mode="nth", compress=False, overview_seconds=60.0,
                      events=True, gaps=True, register=True, new_slice_hours=2.0, workers=1,
                      result_format="xlsx", folders="series", trends=True,
                      trend_parameters=("amplitude", "diastolicForce", "TTP90", "TTR90"),
                      flag_capture=90.0, flag_extra_beats=10.0, flag_amplitude_change=30.0, report=True,
                      flag_uncertain=25.0, flag_irregular=15.0, flag_amplitude=75.0, flag_amplitude_cv=30.0,
                      flag_delay=0.15, flag_min_beats=50, flag_stim_frequency=10.0, quiet=False)
_TIME_FMT = "%Y-%m-%d %H:%M:%S"
_SET_BY_WATCHER = ("output", "labels", "metadata", "protocol", "groupby")  # not allowed as analysis options
_NOT_IN_OPTIONS = ("showfigures", "quiet", "chunkseconds")  # keywords of myodish_analysis, not of options()
_STIM_CODES = ("stimfrequency", "stimcurrent", "chargeduration", "dechargeduration", "chargecurrent",
               "dechargecurrent", "stimpulse", "stimpulses", "stimpolarisation", "stimpolarity", "polarity",
               "pauseduration", "sequence", "stimsequence", "spikethresh")


# ------------------------------------------------------------------------------------------------ public
def watch(raw_folder, results_folder, **kw):
    """One pass, repeated passes on a schedule (schedule='daily 10:00', 'weekly Sun 05:00', 'every 120 min', ...; until
    Ctrl+C) or every interval hours; returns (index, report) of the (last) pass."""
    wopts = {k: kw.pop(k) for k in list(kw) if k in WATCH_DEFAULTS}
    o = dict(WATCH_DEFAULTS, **wopts)
    if str(o["reanalyze"]).lower() not in ("outdated", "new", "all"):
        raise ValueError("reanalyze: 'new', 'outdated' or 'all' expected")
    o["parallel"] = str(o["parallel"]).lower().replace("analyze", "analyse")
    if o["parallel"] not in ("skip", "analyse"):
        raise ValueError("parallel: 'skip' or 'analyse' expected")
    spec = parse_schedule(o["schedule"]) if o["schedule"] else None
    if spec is not None and o["interval"] and o["interval"] > 0:
        raise ValueError("watch: schedule and interval cannot be combined (interval=h is schedule='every <h> h')")
    o["contractions"] = str(o["contractions"]).lower()
    o["thin_mode"] = str(o["thin_mode"]).lower()
    if o["contractions"] not in ("all", "thinned", "none"):
        raise ValueError("contractions: 'all', 'thinned' or 'none' expected")
    if o["thin_mode"] not in ("nth", "median"):
        raise ValueError("thin_mode: 'nth' or 'median' expected")
    if int(o["thin_factor"]) < 1:
        raise ValueError("thin_factor: integer >= 1 expected")
    if float(o["overview_seconds"]) < 0:
        raise ValueError("overview_seconds: number >= 0 expected (0 = no overview)")
    _check_result_options(o)
    if not os.path.isdir(raw_folder):
        raise FileNotFoundError(f"watch: folder not found: {raw_folder}")
    bad = [k for k in kw if k.lower() in _SET_BY_WATCHER]
    if bad:
        raise ValueError(f"watch: {', '.join(bad)} is set by the watcher (labels per channel: <name>_labels.csv)")
    kw = _expand_settings(kw)  # settings file: its values (2026-10-10)
    make_options(**{k: v for k, v in kw.items() if k.lower() not in _NOT_IN_OPTIONS})  # unknown options: error now
    if spec is not None:
        return _scheduled(os.path.abspath(raw_folder), os.path.abspath(results_folder), o, kw, spec)
    while True:
        index, report = _one_pass(os.path.abspath(raw_folder), os.path.abspath(results_folder), o, kw)
        if not o["interval"] or o["interval"] <= 0:
            return index, report
        if not o["quiet"]:
            nxt = _dt.datetime.now() + _dt.timedelta(hours=float(o["interval"]))
            print(f"next pass {nxt:%Y-%m-%d %H:%M} (Ctrl+C stops)")
        time.sleep(float(o["interval"]) * 3600)


def _scheduled(raw, res, o, kw, spec):
    """passes on the schedule until Ctrl+C; returns (index, report) of the last pass."""
    index, report = read_index(res), ""
    nxt = next_pass(spec, None, _dt.datetime.now())
    try:
        while True:
            if nxt > _dt.datetime.now() and not o["quiet"]:
                print(f"next pass {nxt:%Y-%m-%d %H:%M} (schedule '{o['schedule']}'; Ctrl+C stops)")
            while True:  # short sleeps: the computer may sleep in between
                rest = (nxt - _dt.datetime.now()).total_seconds()
                if rest <= 0:
                    break
                time.sleep(min(rest, 60.0))
            index, report = _one_pass(raw, res, o, kw)
            nxt = next_pass(spec, nxt, _dt.datetime.now())
    except KeyboardInterrupt:
        if not o["quiet"]:
            print("watcher stopped")
    return index, report


_DAY_NAMES = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
SCHEDULE_HELP = ("'daily 10:00', 'weekly Sun 05:00', 'Mon,Thu 06:30', 'weekdays 07:00', 'every 2 days 10:00', "
                 "'every 120 min' or 'every 6 h'")


def parse_schedule(text):
    """schedule text -> dict: kind 'interval' (seconds; first pass now), 'days' (every n days at hour:minute) or
    'weekly' (days 0 = Monday ... 6 = Sunday at hour:minute). Same rules as MyoDishAnalysisWatch.m."""
    s = " ".join(str(text).strip().lower().replace(",", ", ").split()).replace(" ,", ",")
    bad = ValueError(f"schedule: {SCHEDULE_HELP} expected, not '{text}'")
    m = re.fullmatch(r"every (\d+(?:\.\d+)?) ?(min|mins|minute|minutes|m|h|hr|hrs|hour|hours)", s)
    if m:
        sec = float(m.group(1)) * (60.0 if m.group(2).startswith("m") else 3600.0)
        if sec < 60:
            raise ValueError("schedule: interval of at least 1 min expected")
        return dict(kind="interval", seconds=sec)
    m = re.fullmatch(r"(?:daily|every day|every (\d+) days?)(?: at)? (\d{1,2}):(\d{2})", s)
    if m:
        n, h, mi = int(m.group(1) or 1), int(m.group(2)), int(m.group(3))
        if n < 1 or h > 23 or mi > 59:
            raise bad
        return dict(kind="days", every=n, hour=h, minute=mi)
    m = re.fullmatch(r"(?:weekly |every )?([a-z][a-z, ]*?)(?: at)? (\d{1,2}):(\d{2})", s)
    if m:
        days = set()
        for tok in re.split(r"[ ,]+", m.group(1).strip()):
            if tok in ("weekdays", "workdays"):
                days |= {0, 1, 2, 3, 4}
            elif tok in ("weekend", "weekends"):
                days |= {5, 6}
            else:
                k = [i for i, d in enumerate(_DAY_NAMES) if len(tok) >= 2 and d.startswith(tok)]
                if len(k) != 1:
                    raise bad
                days.add(k[0])
        h, mi = int(m.group(2)), int(m.group(3))
        if not days or h > 23 or mi > 59:
            raise bad
        return dict(kind="weekly", days=sorted(days), hour=h, minute=mi)
    raise bad


def next_pass(spec, prev=None, now=None):
    """time of the next pass (datetime, local time) after the pass planned for prev (None: first pass)."""
    now = now or _dt.datetime.now()
    if spec["kind"] == "interval":
        if prev is None:
            return now
        step = _dt.timedelta(seconds=spec["seconds"])
        t = prev + step
        while t <= now:  # missed passes are not repeated
            t += step
        return t
    at = now.replace(hour=spec["hour"], minute=spec["minute"], second=0, microsecond=0)
    if spec["kind"] == "days":
        step = _dt.timedelta(days=spec["every"])
        if prev is None:
            return at if at > now else at + _dt.timedelta(days=1)
        t = prev + step
        while t <= now:
            t += step
        return t
    for k in range(8):
        t = at + _dt.timedelta(days=k)
        if t > now and t.weekday() in spec["days"]:
            return t
    raise ValueError("schedule: no day")  # not reached


def update_notice(stale, version, raw, res):
    """lines of the notice about recordings that were analysed with another version, other options or other core code
    and kept (reanalyze 'new'); stale = list of (reason, version of the index)."""
    if not stale:
        return []
    nv, nOpt = {}, 0
    for why, v in stale:
        if why == "other options":
            nOpt += 1
        else:
            k = str(v) + (" with other core code" if why == "core code changed" else "")
            nv[k] = nv.get(k, 0) + 1
    out = []
    if nv:
        out.append(f"MyoDishAnalysis has been updated (now {version}): {sum(nv.values())} recording(s) were analysed "
                   f"with another version ({', '.join(f'{k}: {n}' for k, n in sorted(nv.items()))}). This may change "
                   "the results or lead to inconsistencies with new data (see the release notes, CHANGELOG.md).")
    if nOpt:
        out.append(f"The analysis options have changed: {nOpt} recording(s) were analysed with other options (index "
                   "column 'options'); their results may not be comparable with those of new recordings.")
    out.append(f'The earlier results were kept. To analyse these recordings again: mda-watch "{raw}" "{res}" '
               "--reanalyze outdated (with your other options)")
    return out


def _expand_settings(kw):
    """keyword settings (settings file, settings.py): the options of the file that differ from the defaults, the other
    keywords override them. The index records the values, not the file name: after a change of the settings file the
    earlier recordings count as analysed with other options (reanalyze 'outdated' analyses them again)."""
    keys = [k for k in kw if k.lower() == "settings"]
    if not keys:
        return kw
    f = kw[keys[-1]]
    rest = {k: v for k, v in kw.items() if k.lower() != "settings"}
    if not f:
        return rest
    from .settings import load_settings
    St = load_settings(f)
    D = make_options()
    given = {k.lower() for k in rest}
    out = {k: v for k, v in St.items() if k != "referenceBeat" and k.lower() not in given
           and _value_text(v) != _value_text(D[k])}
    out.update(rest)
    return out


def code_fingerprint():
    """adler32 (hex) of the core modules (all modules of the package except command line, self test, watcher, slice
    register, GUI)."""
    p = os.path.dirname(os.path.abspath(__file__))
    files = sorted(f for f in os.listdir(p) if f.endswith(".py")
                   and f not in ("cli.py", "selftest.py", "watch.py", "slice_register.py"))
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
         "includeprotocols": bool(o["include_protocols"]), "gaps": bool(o["gaps"]),
         "overviewseconds": o["overview_seconds"]}
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
def _touch_lock(lock, force=False):
    """heartbeat of the lock file of a pass (2026-10-14): rewritten (time) at most once a minute (force: now) during the
    scan, after every recording and before long steps; a lock file not refreshed for LOCK_HOURS is ignored by the next
    watcher (crashed). None = no lock (dry run)"""
    if not lock or (not force and time.time() - _LOCK_TOUCHED[0] < 60):
        return
    _LOCK_TOUCHED[0] = time.time()
    try:
        with open(lock, "w") as fh:
            fh.write(f"{os.getpid()} {_dt.datetime.now():{_TIME_FMT}}\n")
    except OSError:
        pass


def _one_pass(raw, res, o, aopts):
    os.makedirs(res, exist_ok=True)
    lock = os.path.join(res, LOCK_NAME)
    if os.path.isfile(lock) and time.time() - os.path.getmtime(lock) < LOCK_HOURS * 3600:
        msg = f"another watcher is running (lock file {lock}, refreshed within the last hour): pass skipped"
        if not o["quiet"]:
            print(msg)
        return read_index(res), msg
    if not o["dry_run"]:
        _touch_lock(lock, force=True)
    try:
        return _scan_and_analyse(raw, res, o, aopts, None if o["dry_run"] else lock)
    finally:
        if not o["dry_run"] and os.path.isfile(lock):
            try:
                os.remove(lock)
            except OSError as ex:
                print(f"warning: lock file {lock} could not be deleted ({ex}); delete it, otherwise the next "
                      f"passes are skipped for {LOCK_HOURS:g} h")


def _scan_and_analyse(raw, res, o, aopts, lock=None):
    X = read_index(res)
    pos = {f: i for i, f in enumerate(X["file"])}
    version, code = mda_version(), code_fingerprint()
    otext = options_text(aopts, o)
    from_date = parse_date(o["from_date"])
    cs = bool(o["case_sensitive"])
    rx = re.compile(o["filter"], 0 if cs else re.I) if o["filter"] else None
    inc, exc = patterns(o["include"]), patterns(o["exclude"])

    def selected(rel):
        if rx and not rx.search(rel):
            return False
        return not ((inc and not wildcard_match(rel, inc, cs)) or (exc and wildcard_match(rel, exc, cs)))

    now = time.time()
    found = _find_recordings(raw)
    chosen = set()  # recordings selected in this pass (filter, include / exclude, from_date)
    for rel, f in found:
        if selected(rel) and (from_date is None or os.path.getmtime(f) >= from_date.timestamp()):
            chosen.add(rel)
    todo, stale = [], []
    for rel, f in found:
        if rel not in chosen:
            continue
        _touch_lock(lock)  # heartbeat (at most once a minute)
        st = os.stat(f)
        logf = f[:-4] + "_log.log"
        logBytes = os.path.getsize(logf) if os.path.isfile(logf) else -1
        lastChange = max(st.st_mtime, os.path.getmtime(logf) if logBytes >= 0 else 0)
        if now - lastChange < 60 * float(o["min_file_age_minutes"]):
            continue  # still written / copied
        modified = _dt.datetime.fromtimestamp(st.st_mtime, _dt.timezone.utc).strftime(_TIME_FMT) + " UTC"
        r = X.iloc[pos[rel]] if rel in pos else None
        why = _why(r, st.st_size, modified, logBytes, version, code, otext, o, chosen)
        if why:
            todo.append(dict(rel=rel, f=f, bytes=st.st_size, modified=modified, logBytes=logBytes,
                             lastChange=lastChange, mtime=st.st_mtime, why=why))
        elif r is not None and r["status"] == "ok" and _outdated(r, version, code, otext):
            stale.append((_outdated(r, version, code, otext), r["version"]))  # kept (reanalyze 'new')
    # parallel recordings (2026-10-14): skipped (parallel='skip') if their main file is selected in this pass, too
    # (its results contain the data); otherwise analysed and marked in the message (slice register: not counted twice)
    parallel, keep, cache = [], [], {}
    for t in todo:
        _touch_lock(lock)
        M = None
        if t["logBytes"] > 0 and t["bytes"] > 0:
            try:
                D = log_recordings(t["f"][:-4] + "_log.log", t["f"])
                M = main_recording(t["f"], D, cache) if D["parallel"] else None
            except Exception:  # noqa: BLE001 - analysed as usual
                M = None
        if M is not None:
            t["main"] = (os.path.relpath(M[0], raw).replace(os.sep, "/"), M[1], M[2])
            if o["parallel"] == "skip" and t["main"][0] in chosen:
                parallel.append(t)
                continue
        keep.append(t)
    todo = keep
    if o["max_files"] is not None:
        todo = todo[:int(o["max_files"])]
    notice = update_notice(stale, version, raw, res)
    if not o["quiet"]:
        nchk = sum(1 for t in todo if t["why"].startswith("check"))
        print(f"{_dt.datetime.now():{_TIME_FMT}}  {raw}: {len(todo) - nchk} recording(s) to analyse"
              + (f", {nchk} to check again (running / incomplete)" if nchk else "")
              + (f", {len(parallel)} parallel recording(s) skipped (main file selected)" if parallel else ""))
        for ln in notice:
            print("NOTE: " + ln)
    if o["dry_run"]:
        for t in todo:
            print(f"  {t['rel']}  ({t['why']})")
        for t in parallel:
            print(f"  {t['rel']}  (parallel recording of {t['main'][0]}: skipped)")
        return X, "\n".join(notice)
    jobs = [(t, res, o, aopts, version, code, otext, now) for t in todo]
    blocks = []
    done = []  # rows of the analysed recordings (PDF report)

    def store(row, block):
        nonlocal X
        if row["status"] in ("ok", "error"):
            blocks.append(block or f"{row['file']}\n  {row['status']}: {row['message']}\n")
            done.append(dict(row))
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
        if row["status"] in ("ok", "error"):  # the other states are written once at the end of the pass
            _write_index(res, X)
        _touch_lock(lock)  # heartbeat after every recording (2026-10-14)

    for t in parallel:  # index rows without analysis
        m, a, b = t["main"]
        row = _new_row(t, version, code, otext)
        row.update(status="parallel", seconds=0.0,
                   message=f"parallel recording of {m} ({_window_text(a, b)} of the main file): not analysed "
                           f"(parallel='skip'), its data and stimulation protocols are in the results of the main file")
        store(row, "")
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
    if jobs or parallel:  # index in the order of the files (parallel processing finishes in any order)
        X = X.sort_values("file", kind="stable").reset_index(drop=True)
        _write_index(res, X)
    fl = _report_flag_options(o)
    recs, flag_msg = [], ""
    if done and o["report"]:  # flags of the analysis report -> mda_flags.csv (2026-10-14), before the register (red
        _touch_lock(lock)     # flags in its images; 2026-10-15)
        try:
            recs = _report_records(raw, res, sorted(done, key=lambda r: r["file"]), fl)
            _update_flags(res, _record_flags(recs), done)
        except Exception as ex:  # noqa: BLE001 - the report must not stop the watcher
            recs, flag_msg = [], _clean(f"flags: {type(ex).__name__}: {ex}") + "\n"
    exps = sorted({t["rel"].rsplit("/", 1)[0] if "/" in t["rel"] else "" for t in todo})
    reg = ""
    if jobs and o["register"] and o["gaps"]:  # slice register and images of the series of these experiments
        _touch_lock(lock)
        try:
            R = slice_register(res, experiments=exps, new_slice_hours=float(o["new_slice_hours"]),
                               trends=bool(o["trends"]) and float(o["overview_seconds"]) > 0,
                               trend_parameters=o["trend_parameters"])
            reg = f"slice register: {len(R)} slices in {len(exps)} experiment(s), {SLICES_NAME}\n"
        except Exception as ex:  # noqa: BLE001
            reg = _clean(f"slice register: {type(ex).__name__}: {ex}") + "\n"
    report = ""
    if blocks:
        blocks.sort()  # order of the files (parallel processing finishes in any order)
        now_ = _dt.datetime.now()
        head = (f"MyoDishAnalysis {version} (Python) watcher report {now_:{_TIME_FMT}}\n"
                f"raw folder: {raw}\nresults:    {res}\noptions:    {otext}\n\n"
                + "".join(f"NOTE: {ln}\n" for ln in notice) + ("\n" if notice else ""))
        d = os.path.join(res, "reports")
        os.makedirs(d, exist_ok=True)
        pdf = ""
        if o["report"] and recs:  # PDF report per experiment (2026-10-15)
            lines = []
            for e in exps:
                new = [r for r in recs if r["name"].rpartition("/")[0] == e]
                if not new:
                    continue
                _touch_lock(lock)
                try:
                    f, n = _experiment_report(raw, res, e, new, fl, version, otext, now_, notice)
                    if f:
                        lines.append(f"PDF report: {f}" + (f" ({n} channel(s) to check)" if n else ""))
                except Exception as ex:  # noqa: BLE001 - the report must not stop the watcher
                    lines.append(_clean(f"PDF report {e}: {type(ex).__name__}: {ex}"))
            pdf = "".join(ln + "\n" for ln in lines)
        report = (head + "\n".join(blocks) + ("\n" + reg if reg else "") + ("\n" + flag_msg if flag_msg else "")
                  + ("\n" + pdf if pdf else ""))
        with open(os.path.join(d, f"mda_report_{now_:%Y-%m-%d_%H%M%S}.txt"), "w", encoding="utf-8") as fh:
            fh.write(report)
        if not o["quiet"]:
            print("\n" + report)
    elif notice:
        report = "\n".join(notice)
    return X, report


def _report_flag_options(o):
    return dict(uncertain=float(o["flag_uncertain"]), irregular=float(o["flag_irregular"]),
                extra=float(o["flag_extra_beats"]), capture=float(o["flag_capture"]),
                amplitude_change=float(o["flag_amplitude_change"]), amplitude=float(o["flag_amplitude"]),
                amplitude_cv=float(o["flag_amplitude_cv"]), delay=float(o["flag_delay"]),
                min_beats=float(o["flag_min_beats"]), stim_frequency=float(o["flag_stim_frequency"]))


def _report_records(raw, res, rows, fl):
    """recordings of this pass for the reports (2026-10-15): flags R per channel (report_flags, with the window of the
    channels to check), contractions C only for recordings with channels to check (detail pages; memory of passes
    with thousands of recordings), pulses read later (P_file)"""
    from .report import report_flags, report_window
    ccols = {"channel", "t_peak", "beatType", "uncertain", "included", "amplitude", "stimToOnset"}
    recs = []
    for row in rows:
        rel = str(row["file"]).replace("\\", "/")
        n = os.path.splitext(os.path.basename(rel))[0]
        d, _ = results_of(res, rel)
        rec = dict(name=rel, file=os.path.join(raw, rel), open=os.path.join(d, n + "_info.csv"), S=None, C=None,
                   P=None, status=None, notes=[], new=True, analyzed=row["analyzed"])
        if row["status"] != "ok":
            rec["notes"] = [_clean(f"error: {row['message']}")]
            recs.append(rec)
            continue
        rec["S"] = result_table(d, n, "summary")
        C = _read_result(os.path.join(d, n + "_contractions.csv"), usecols=lambda c: c in ccols)
        CH = result_table(d, n, "channels", usecols=lambda c: c in ("channel", "status"))
        if os.path.isfile(os.path.join(d, n + ".xlsx")):  # results as .xlsx (2026-10-14)
            rec["open"] = os.path.join(d, n + ".xlsx")
        if CH is not None:
            rec["status"] = {int(c): str(st) for c, st in zip(CH["channel"], CH["status"])}
        rec["notes"] = [m for m in str(row["message"]).split(" | ") if m.startswith("protocols:")]
        R = report_flags(rec["S"], C, rec["status"], events=result_table(d, n, "events", usecols=lambda c: c in (
            "code", "text", "t_file")), **fl)  # events: red flag R (controller restart suspected, 2026-10-21)
        R["window_from"], R["window_to"] = math.nan, math.nan
        for i in np.flatnonzero((R["level"] == "check").to_numpy()):
            R.at[i, "window_from"], R.at[i, "window_to"] = report_window(C, int(R.at[i, "channel"]), R.at[i, "flags"])
        rec["R"] = R
        rec["C"] = C if (R["level"] == "check").any() else None
        rec["P_file"] = os.path.join(d, n + "_pulses.csv")
        recs.append(rec)
    return recs


def _flags_frame(Fr):
    """flags of one recording for write_report from rows of mda_flags.csv (windows of the channels to check)"""
    D = pd.DataFrame({c: pd.to_numeric(Fr[c], errors="coerce").to_numpy(float)
                      for c in ("channel", "nDetected", "capture_percent")})
    for c in ("label", "status", "flags", "level", "red", "yellow"):
        D[c] = Fr[c].fillna("").astype(str).to_numpy()
    D["window_from"] = pd.to_numeric(Fr["from"], errors="coerce").to_numpy(float)
    D["window_to"] = pd.to_numeric(Fr["to"], errors="coerce").to_numpy(float)
    return D


def _record_flags(recs):
    """flags of the recordings (column recording) for mda_flags.csv"""
    parts = []
    for r in recs:
        if r.get("R") is not None and len(r["R"]):
            R = r["R"].copy()
            R.insert(0, "recording", r["name"])
            parts.append(R)
    return pd.concat(parts, ignore_index=True) if parts else None


def _experiment_report(raw, res, e, new, fl, version, otext, now_, notice=()):
    """PDF report of an experiment (2026-10-15): <experiment>/<name>_report.pdf (mda_report_root.pdf for recordings
    directly in the raw folder) with all analysed recordings of the experiment (index), the recordings of this pass
    (new) marked new (bold) with detail pages; the others with the flags of mda_flags.csv (computed from their result
    files where missing); first page: the overview image of the experiment (slice register). Returns (file, channels
    to check in the recordings of this pass); file '' if the experiment has no analysed recordings."""
    from .report import write_report
    if e:
        folder = _abs_folder(res, e)
        pdf = os.path.join(folder, e.rsplit("/", 1)[-1] + "_report.pdf")
        png = os.path.join(folder, e.rsplit("/", 1)[-1] + "_overview.png")
        en = e
    else:
        pdf, png = os.path.join(res, "mda_report_root.pdf"), os.path.join(res, "mda_overview_root.png")
        en = "recordings in the raw folder"
    X = read_index(res)
    files = [str(f).replace("\\", "/") for f in X["file"]]
    sel = [i for i, f in enumerate(files) if f.rpartition("/")[0] == e and X["status"].iloc[i] in ("ok", "error")]
    F = read_flags(res)
    by_name = {r["name"]: r for r in new}
    recs, add = [], []
    for i in sel:
        rel = files[i]
        if rel in by_name:
            recs.append(by_name[rel])
            continue
        x = X.iloc[i]
        rec = dict(name=rel, file=os.path.join(raw, rel), open="", S=None, C=None, P=None, status=None, notes=[],
                   new=False, analyzed=str(x["analyzed"]))
        if x["status"] != "ok":
            rec["notes"] = [_clean(f"error: {x['message']}")]
            recs.append(rec)
            continue
        d, _ = results_of(res, rel)
        n = os.path.splitext(os.path.basename(rel))[0]
        rec["open"] = os.path.join(d, n + (".xlsx" if os.path.isfile(os.path.join(d, n + ".xlsx")) else "_info.csv"))
        Fr = F[(F["file"] == x["file"]) & (F["analyzed"].astype(str) == str(x["analyzed"]))]
        if not len(Fr):  # flags missing (older watcher versions): from the result files
            try:
                Fr = flags_of(res, x["file"], str(x["analyzed"]))
                add.append(Fr)
            except Exception:  # noqa: BLE001 - shown without flags
                Fr = F.iloc[0:0]
        rec["R"] = _flags_frame(Fr)
        rec["notes"] = [m for m in str(x["message"]).split(" | ") if m.startswith("protocols:")]
        recs.append(rec)
    add = [a for a in add if len(a)]
    if add:
        A = pd.concat(add, ignore_index=True)
        _write_flags(res, pd.concat([F[~F["file"].isin(set(A["file"]))], A], ignore_index=True))
    if not recs:
        return "", 0

    def key(r):  # order: series, number, name
        n = os.path.splitext(os.path.basename(r["name"]))[0]
        sr, num = series_of(n)
        return sr, math.inf if math.isnan(num) else num, n
    recs.sort(key=key)
    sub = [f"raw folder: {raw}", f"results: {res}",
           f"MyoDishAnalysis {version} (Python) watcher, {now_:{_TIME_FMT}}: {len(recs)} recording(s) of {en}, "
           f"{sum(1 for r in recs if r['new'])} analysed in this pass (bold); options: {otext}"]
    R = write_report(recs, pdf, title=f"MyoDishAnalysis report: {en}", subtitle=sub, notice=notice,
                     image=png if os.path.isfile(png) else None, **fl)
    n = int(((R["level"] == "check") & R["recording"].isin(set(by_name))).sum()) if len(R) else 0
    return pdf, n


# ------------------------------------------------------------------------------------------------ flags table
FLAGS_NAME = "mda_flags.csv"
FLAG_COLUMNS = ["file", "analyzed", "channel", "label", "status", "nDetected", "capture_percent", "flags", "level",
                "red", "yellow", "from", "to"]
_FLAG_TEXT = ("file", "analyzed", "label", "status", "flags", "level", "red", "yellow")


def read_flags(results_folder):
    """results_folder/mda_flags.csv (flags of the analysis report per recording and channel, written by the watcher;
    2026-10-14); empty table with FLAG_COLUMNS if missing."""
    f = os.path.join(results_folder, FLAGS_NAME)
    if not os.path.isfile(f):
        return pd.DataFrame(columns=FLAG_COLUMNS)
    T = pd.read_csv(f, dtype={c: str for c in _FLAG_TEXT}, keep_default_na=False, na_values={"channel": [""],
                    "nDetected": [""], "capture_percent": [""], "from": [""], "to": [""]})
    for c in FLAG_COLUMNS:
        if c not in T.columns:
            T[c] = "" if c in _FLAG_TEXT else math.nan
    return T[FLAG_COLUMNS]


def _flag_rows(R, analyzed):
    """rows of mda_flags.csv from flags of write_report (column recording = file); analyzed: {file: time}"""
    if R is None or not len(R):
        return pd.DataFrame(columns=FLAG_COLUMNS)
    T = pd.DataFrame({"file": R["recording"].astype(str), "channel": R["channel"].astype(int)})
    T["analyzed"] = T["file"].map(lambda f: str(analyzed.get(f, "")))
    for c in ("label", "status", "flags", "level", "red", "yellow"):
        T[c] = R[c].fillna("").astype(str).to_numpy()
    T["nDetected"] = R["nDetected"].to_numpy()
    T["capture_percent"] = np.round(R["capture_percent"].to_numpy(float), 1)
    T["from"] = R["window_from"].to_numpy(float) if "window_from" in R.columns else math.nan
    T["to"] = R["window_to"].to_numpy(float) if "window_to" in R.columns else math.nan
    return T[FLAG_COLUMNS]


def _write_flags(results_folder, T):
    f = os.path.join(results_folder, FLAGS_NAME)
    tmp = f + ".tmp"
    T = T.sort_values(["file", "channel"], kind="stable")
    T[FLAG_COLUMNS].to_csv(tmp, index=False)
    os.replace(tmp, f)


def _update_flags(res, R, rows):
    """mda_flags.csv: rows of the recordings of this pass replaced (also removed: error now)"""
    files = {r["file"] for r in rows}
    old = read_flags(res)
    old = old[~old["file"].isin(files)]
    new = _flag_rows(R[R["recording"].isin(files)] if R is not None and len(R) else None,
                     {r["file"]: r["analyzed"] for r in rows})
    _write_flags(res, pd.concat([old, new], ignore_index=True) if len(old) else new)


def flags_of(results_folder, rel, analyzed="", **flags):
    """flags of one analysed recording (path relative to the raw folder) from its result files (summary, contractions,
    channels): rows of mda_flags.csv, window (from, to) for the channels to check (report_window, 20 s)"""
    from .report import report_flags, report_window
    n = os.path.splitext(os.path.basename(rel))[0]
    d, _ = results_of(results_folder, rel)
    S = result_table(d, n, "summary")
    if S is None:
        return pd.DataFrame(columns=FLAG_COLUMNS)
    C = _read_result(os.path.join(d, n + "_contractions.csv"), usecols=lambda c: c in {
        "channel", "t_peak", "beatType", "uncertain", "included", "amplitude", "stimToOnset"})
    CH = result_table(d, n, "channels", usecols=lambda c: c in ("channel", "status"))
    st = {int(c): str(s) for c, s in zip(CH["channel"], CH["status"])} if CH is not None else None
    E = result_table(d, n, "events", usecols=lambda c: c in ("code", "text", "t_file"))
    R = report_flags(S, C, st, events=E, **flags)
    R.insert(0, "recording", rel)
    R["window_from"], R["window_to"] = math.nan, math.nan
    for i in np.flatnonzero((R["level"] == "check").to_numpy()):
        R.at[i, "window_from"], R.at[i, "window_to"] = report_window(C, int(R.at[i, "channel"]), R.at[i, "flags"])
    return _flag_rows(R, {rel: analyzed})


def flags_table(results_folder, compute=False, progress=None, **flags):
    """flags of the analysis report per recording and channel for the results browser (2026-10-14): mda_flags.csv
    (written by the watcher) and the index; recordings with the status ok whose flags are missing or older than their
    analysis are computed from their result files if compute=True (and written to mda_flags.csv unless a watcher is
    running). Returns (index, flags of the current analyses, missing = files without current flags). progress:
    f(k, n)."""
    X = read_index(results_folder)
    T = read_flags(results_folder)
    have = {(f, a) for f, a in zip(T["file"], T["analyzed"])}
    ok = X[X["status"] == "ok"]
    missing = [f for f, a in zip(ok["file"], ok["analyzed"]) if (f, str(a)) not in have]
    if compute and missing:
        parts = [T[~T["file"].isin(set(missing))]]
        ana = dict(zip(ok["file"], ok["analyzed"]))
        for k, f in enumerate(missing):
            if progress is not None:
                progress(k, len(missing))
            try:
                parts.append(flags_of(results_folder, f, str(ana[f]), **flags))
            except Exception:  # noqa: BLE001 - shown without flags
                pass
        T = pd.concat([p for p in parts if len(p)], ignore_index=True) if any(len(p) for p in parts) else T.iloc[0:0]
        lock = os.path.join(results_folder, LOCK_NAME)
        if not (os.path.isfile(lock) and time.time() - os.path.getmtime(lock) < LOCK_HOURS * 3600):
            _write_flags(results_folder, T)
        have = {(f, a) for f, a in zip(T["file"], T["analyzed"])}
        missing = [f for f, a in zip(ok["file"], ok["analyzed"]) if (f, str(a)) not in have]
    cur = {(f, str(a)) for f, a in zip(ok["file"], ok["analyzed"])}  # only the flags of the current analyses
    keep = np.array([(f, str(a)) in cur for f, a in zip(T["file"], T["analyzed"])], dtype=bool)
    T = T[keep].reset_index(drop=True)  # (a list would select columns if empty)
    return X, T, missing


def _read_result(f, **kw):
    """result table <f> or <f>.gz (None if neither exists)"""
    for g in (f, f + ".gz"):
        if os.path.isfile(g):
            return pd.read_csv(g, low_memory=False, **kw)
    return None


def result_table(folder, name, table, usecols=None):
    """table of the results of recording name in folder: sheet of <name>.xlsx (result_format 'xlsx', 2026-10-14) or
    <name>_<table>.csv(.gz) (None if neither exists); usecols: as pandas (callable or list)"""
    x = os.path.join(folder, name + ".xlsx")
    if os.path.isfile(x):
        try:
            with pd.ExcelFile(x) as xl:
                if table in xl.sheet_names:
                    T = xl.parse(table)
                    if usecols is not None:
                        T = T[[c for c in T.columns if (usecols(c) if callable(usecols) else c in usecols)]]
                    return T
        except Exception:  # noqa: BLE001 - not readable: the csv files
            pass
    return _read_result(os.path.join(folder, f"{name}_{table}.csv"), usecols=usecols)


def _new_row(t, version, code, otext):
    return dict(file=t["rel"], bytes=t["bytes"], modified=t["modified"], logBytes=t["logBytes"], status="",
                version=version, implementation="Python", code=code, options=otext,
                analyzed=_dt.datetime.now().strftime(_TIME_FMT), seconds=math.nan, nContractions=math.nan, outputs="",
                message="")


def _process(job):
    """header check and analysis of one recording; returns (index row, report block). Runs in a worker process too."""
    t, res, o, aopts, version, code, otext, now = job
    row = _new_row(t, version, code, otext)
    t0 = time.time()
    block = ""
    status, note = precheck(t)
    if status:
        row.update(status=status, message=note)
    else:
        try:
            hopts = make_options(**{k: v for k, v in aopts.items() if k.lower() not in _NOT_IN_OPTIONS})
            H = read_header(t["f"], hopts)
            status, note = completeness(t, H, o, now)
            if status:
                row.update(status=status, message=note)
            else:
                row, block = _analyse(t["f"], t["rel"], H, res, row, o, aopts)
                if note:
                    row["message"] = note + (" | " + row["message"] if row["message"] else "")
        except Exception as ex:  # noqa: BLE001 - one bad recording must not stop the pass
            row.update(status="error", message=_clean(f"{type(ex).__name__}: {ex}"))
    if t.get("main") and row["status"] in ("ok", "error"):  # analysed parallel recording: marked (2026-10-14)
        m, a, b = t["main"]
        why = "parallel='analyse'" if o["parallel"] != "skip" else "main file not selected"
        mark = f"parallel recording of {m} ({_window_text(a, b)} of the main file): analysed ({why})"
        row["message"] = mark + (" | " + row["message"] if row["message"] else "")
    row["seconds"] = round(time.time() - t0, 1)
    return row, block


def parallel_of(message):
    """main file (path relative to the raw folder) of a parallel recording, from the message of its index row
    ('parallel recording of <main> (...'), or None"""
    m = re.match(r"parallel recording of (.+?\.mdd) \(", str(message), re.I)
    return m.group(1) if m else None


def precheck(t):
    """checks without reading the file (2026-10-13): ('incomplete', message) for an empty file or a file dated before
    1990 (robocopy marks unfinished copies with 1980), ('noLog', message) without log file or with an empty one;
    ('', '') otherwise. These states end when the file or the log file changes (no time limit)."""
    if t["bytes"] == 0:
        return "incomplete", "empty file (0 bytes): copy not finished"
    if t["mtime"] < ROBOCOPY_TIME:  # until the copy is finished (robocopy then sets the time of the source file)
        return "incomplete", "file time before 1990: copy not finished (robocopy dates unfinished copies to 1980)"
    if t["logBytes"] < 0:
        return "noLog", "no log file <name>_log.log"
    if t["logBytes"] == 0:
        return "noLog", "log file <name>_log.log empty: copy not finished"
    return "", ""


def completeness(t, H, o, now):
    """('running' | 'incomplete', message) while a recording is written or copied; ('', note) if it is analysed (note:
    analysed although incomplete). t: rel, f, lastChange (s since 1970); H: read_header (2026-10-13).
      no data (< 1 s):            'incomplete' until the file changes
      no 'Recording stopped':     'running' until the end of the data (start in the log file + duration of the file)
                                  is incomplete_after_hours ago (clock time unknown or > 1 h in the future: the last
                                  change of the files instead)
      file shorter than the log:  'incomplete' if more than max(10 s, incomplete_tolerance %) is missing; analysed
                                  (with a note) when unchanged for incomplete_after_hours"""
    hours = float(o["incomplete_after_hours"])
    if H.totalSeconds < 1:
        return "incomplete", "no data in the file (< 1 s): copy not finished"
    if H.recordingStopped is False:
        start = getattr(H, "recordingStart", math.nan)
        nowDn = datetime_to_datenum(_dt.datetime.fromtimestamp(now))
        end = start + H.totalSeconds / 86400.0 if isinstance(start, (int, float)) and math.isfinite(start) else math.nan
        if math.isfinite(end) and end <= nowDn + 1 / 24.0:
            age = (nowDn - end) * 24.0
            msg = f"no 'Recording stopped' in the log file yet (data until {datenum_to_datetime(end):%Y-%m-%d %H:%M})"
        else:  # no clock time, or the clock of the recording computer is ahead
            age = (now - t["lastChange"]) / 3600.0
            msg = "no 'Recording stopped' in the log file yet"
        return ("running", msg) if age < hours else ("", "")
    if H.recordingStopped is True:
        d = log_recordings(t["f"][:-4] + "_log.log", t["f"])["seconds"]
        if math.isfinite(d) and d > 0:
            miss = d - H.totalSeconds
            if miss > max(10.0, float(o["incomplete_tolerance"]) / 100.0 * d):
                msg = (f"file {H.totalSeconds:.0f} s, recording in the log file {d:.0f} s ({100.0 * miss / d:.1f} % "
                       f"missing): copy incomplete")
                if now - t["lastChange"] >= 3600 * hours:
                    return "", f"{msg}; analysed after {hours:g} h without change"
                return "incomplete", msg
    return "", ""


def _outdated(r, version, code, otext):
    """'other version' / 'other options' / 'core code changed' (same implementation) / ''"""
    if r["version"] != version:
        return "other version"
    if r["options"] != otext:
        return "other options"
    if r["implementation"] == "Python" and r["code"] != code:
        return "core code changed"
    return ""


def _why(r, nbytes, modified, logBytes, version, code, otext, o, present=None):
    """reason to analyse the recording ('' = nothing to do). present: recordings selected in this pass."""
    if r is None:
        return "new"
    old = _parse_time(r["modified"])
    if (r["bytes"] != nbytes or r["logBytes"] != logBytes or old is None
            or abs((old - _parse_time(modified)).total_seconds()) > 2):
        return "changed"
    status = r["status"]
    if status in ("running", "incomplete"):  # time limits; 'noLog': analysed when the log file appears (changed)
        return "check " + status
    if status == "parallel":  # main file named in the message (2026-10-13)
        if o["parallel"] != "skip":
            return "parallel='analyse'"
        m = parallel_of(r["message"])
        return "" if (m and (present is None or m in present)) else "check parallel (main file not selected)"
    outdated = _outdated(r, version, code, otext)
    mode = str(o["reanalyze"]).lower()
    if status == "error":  # no results to keep: retried when the version, the options or the core code change
        if o["retry_errors"]:
            return "retry error"
        return ("retry error, " + outdated) if outdated else ""
    if mode == "all":
        return "reanalyze all"
    if mode == "outdated" and outdated:
        return outdated
    return ""


# ------------------------------------------------------------------------------------------------ one recording
def _analyse(f, rel, H, res, row, o, aopts):
    """the analyses of one recording (only calls of the MyoDishAnalysis functions)."""
    n = os.path.splitext(os.path.basename(f))[0]
    outDir = _abs_folder(res, result_folder(rel, o["folders"]))  # series layout (2026-10-15) or flat
    oldDir = _abs_folder(res, result_folder(rel, "flat" if o["folders"] == "series" else "series"))
    if os.path.normpath(oldDir) != os.path.normpath(outDir) and os.path.isdir(oldDir):  # the other layout
        # empty folders removed only if results of this recording were there: with several workers another worker
        # may just have created the folder (fresh results folder; 2026-10-18)
        if _delete_results(oldDir, n, os.path.normpath(oldDir) == os.path.normpath(os.path.dirname(f))):
            _remove_empty_folders(oldDir, res)
    _makedirs(outDir)
    meta = f[:-4] + "_labels.csv"
    meta = meta if os.path.isfile(meta) else None
    xls = o["result_format"] == "xlsx"
    msgs, outputs = [], []
    P = None
    if o["protocols"] or not o["include_protocols"] or o["trends"]:
        try:
            P = find_protocols(H)
        except Exception as ex:  # noqa: BLE001
            msgs.append(f"protocols: {type(ex).__name__}: {ex}")
    W = _protocol_windows(P, float(o["protocol_margin_seconds"]))
    fr, to, labels, bins = _ranges(H, float(o["bin_minutes"]) * 60, None if o["include_protocols"] else W)
    _delete_results(outDir, n, os.path.normpath(outDir) == os.path.normpath(os.path.dirname(f)))
    E = None  # entries of the log file (also for the trend images)
    if o["events"] or o["trends"]:
        E = log_entries(H.logFile)
        E.insert(4, "category", [event_category(c, t) for c, t in zip(E["code"], E["text"])])
    Ev = E if o["events"] else None  # events table and comments in the results (events=True)
    G = Gw = None
    if o["gaps"]:
        try:
            G = signal_gaps(H)
            Gw = _gaps_out(G, H, Ev)
        except Exception as ex:  # noqa: BLE001
            G = Gw = None
            msgs.append(f"gaps: {type(ex).__name__}: {ex}")
    S = C = info = Ov = None
    Call = None
    nC = 0
    if len(fr):
        C, S, info = myodish_analysis(f, None, fr, to, labels=labels, metadata=meta, quiet=True, **aopts)
        info["extra"] = [(k, "MyoDishAnalysisWatch" if k == "createdBy" else v) for k, v in info["extra"]] + \
            [("watcherOptions", row["options"]), ("watcherCode", row["code"])]  # info table: watcher settings
        nC = len(C)
        binOf = dict(zip(labels, bins))
        S.insert(int(S.columns.get_loc("range")) + 1, "bin", [binOf[r] for r in S["range"]])
        C.insert(int(C.columns.get_loc("range")) + 1, "bin", [binOf[r] for r in C["range"]])
        _add_comments(S, Ev)
        if o["gaps"]:
            _add_gaps(S, G)
        Call = C
        if float(o["overview_seconds"]) > 0 and nC:
            Ov = _overview(C, labels, fr, to, H, float(o["overview_seconds"]))
        C = _sample(C, labels, W if o["include_protocols"] else None, o)
        msgs = list(info.get("notes", [])) + msgs
    else:
        msgs.append("no time outside the stimulation protocols")
    CH = None
    if o["gaps"] and G is not None:
        CH = _channel_status(H, Call, G, Ev, n, make_labels(meta, H.dataChannels),
                             float(np.max(to)) if len(to) else math.nan)
    TR, Ttr, Tcm = [], None, None  # trend data per channel (2026-10-14)
    if o["trends"] and Ov is not None:
        try:
            TR = _recording_trends(n, H.recordingStart, H.totalSeconds, Ov, E, P, G, make_labels(meta, H.dataChannels),
                                   o)
            Ttr, Tcm = _trend_tables(TR, _clock(H.recordingStart))
        except Exception as ex:  # noqa: BLE001
            TR, Ttr, Tcm = [], None, None
            msgs.append(f"trends: {type(ex).__name__}: {ex}")
    # result files: 'xlsx' (2026-10-14): <name>.xlsx (summary, trends, channels, gaps, events, parameters, info, ...;
    # sheets) and the large tables as <name>_contractions.csv.gz, _pulses.csv.gz, _overview.csv.gz; 'csv': one file
    # per table
    if xls:
        sheets = [(k, _for_csv(T) if k == "events" else T) for k, T in (
            ("trends", Ttr), ("trendComments", Tcm), ("channels", CH), ("gaps", Gw), ("events", Ev)) if T is not None]
        if S is not None:
            Cw = None if o["contractions"] == "none" else C
            if o["contractions"] == "none":
                info.pop("pulses", None)
            out = write_results(os.path.join(outDir, n + ".xlsx"), Cw, S, info, csv_tables=("contractions", "pulses"),
                                compress=True, sheets=sheets)
            outputs += [os.path.basename(x) for x in out]
        elif sheets:
            with pd.ExcelWriter(os.path.join(outDir, n + ".xlsx"), engine="openpyxl") as xw:
                for k, T in sheets:
                    _for_csv(T).to_excel(xw, sheet_name=k, index=False)
            outputs.append(n + ".xlsx")
        if Ov is not None:
            _for_csv(Ov).to_csv(os.path.join(outDir, n + "_overview.csv"), index=False)
            _gzip(os.path.join(outDir, n + "_overview.csv"))
            outputs.append(n + "_overview.csv.gz")
    else:
        if Ev is not None:
            _for_csv(Ev).to_csv(os.path.join(outDir, n + "_events.csv"), index=False)
            outputs.append(n + "_events.csv")
        if Gw is not None:
            _for_csv(Gw).to_csv(os.path.join(outDir, n + "_gaps.csv"), index=False)
            outputs.append(n + "_gaps.csv")
        if S is not None:
            Cw = None if o["contractions"] == "none" else C
            if o["contractions"] == "none":
                info.pop("pulses", None)
            write_results(os.path.join(outDir, n + ".csv"), Cw, S, info, csv_tables=("contractions", "pulses"),
                          compress=bool(o["compress"]))
            outputs.insert(0, n + ".csv")
        if Ov is not None:
            _for_csv(Ov).to_csv(os.path.join(outDir, n + "_overview.csv"), index=False)
            outputs.append(n + "_overview.csv")
        if CH is not None:
            _for_csv(CH).to_csv(os.path.join(outDir, n + "_channels.csv"), index=False)
            outputs.append(n + "_channels.csv")
        if Ttr is not None:
            Ttr.to_csv(os.path.join(outDir, n + "_trends.csv"), index=False)
            Tcm.to_csv(os.path.join(outDir, n + "_trendComments.csv"), index=False)
            outputs += [n + "_trends.csv", n + "_trendComments.csv"]
    if o["protocols"] and P is not None and len(P):
        try:
            if xls:  # <name>_protocols.xlsx, contractions and pulses as .csv.gz
                Cp, Sp, pinfo = myodish_analysis(f, None, protocol="all", metadata=meta, quiet=True, report=False,
                                                 **aopts)
                out = write_results(os.path.join(outDir, n + "_protocols.xlsx"), Cp, Sp, pinfo,
                                    csv_tables=("contractions", "pulses"), compress=True)
                outputs += [os.path.basename(x) for x in out]
            else:
                _, _, pinfo = myodish_analysis(f, None, protocol="all", metadata=meta, quiet=True,
                                               output=os.path.join(outDir, n + "_protocols.csv"), report=False, **aopts)
                outputs.append(n + "_protocols.csv")
                if o["compress"]:  # protocol contractions and pulses as well (2026-10-11)
                    for cf in (os.path.join(outDir, n + "_protocols_contractions.csv"),
                               os.path.join(outDir, n + "_protocols_pulses.csv")):
                        if os.path.isfile(cf):
                            _gzip(cf)
            msgs += ["protocols: " + x for x in pinfo.get("notes", []) if "not analysed" in x]  # single protocols
        except Exception as ex:  # noqa: BLE001
            msgs.append(f"protocols: {type(ex).__name__}: {ex}")
    if TR:  # trend images per channel (2026-10-14)
        try:
            tf = _trend_images(_image_folder(outDir, o["folders"]), n, TR)
            if tf:
                outputs.append((f"trends/{n}" if o["folders"] == "flat" else n) + f"_ch*.png ({len(tf)})")
        except Exception as ex:  # noqa: BLE001
            msgs.append(f"trends: {type(ex).__name__}: {ex}")
    row.update(status="ok", nContractions=nC, outputs="; ".join(outputs), message=_clean(" | ".join(msgs)))
    return row, _report_block(rel, H, S, o, CH, G)


def _check_result_options(o):
    """result_format, trends, trend_parameters (2026-10-14), folders (2026-10-15)"""
    from .parameters import PARAMETERS
    o["result_format"] = str(o["result_format"]).lower()
    if o["result_format"] not in ("xlsx", "csv"):
        raise ValueError("result_format: 'xlsx' or 'csv' expected")
    if "folders" in o:  # 2026-10-15
        o["folders"] = str(o["folders"]).lower()
        if o["folders"] not in ("series", "flat"):
            raise ValueError("folders: 'series' or 'flat' expected")
    o["trends"] = bool(o["trends"])
    tp = o["trend_parameters"]
    tp = [tp] if isinstance(tp, str) else list(tp)
    known = {p[0] for p in PARAMETERS} | {"beatsPerMinute"}
    bad = [x for x in tp if x not in known]
    if bad or not tp:
        raise ValueError(f"trend_parameters: parameters of parameters() or beatsPerMinute expected ({', '.join(bad)})")
    o["trend_parameters"] = tuple(tp)
    return o


def _makedirs(d, tries=3):
    """os.makedirs(d, exist_ok=True), again after a short pause if a parent folder disappeared meanwhile (an empty
    folder removed by another process)"""
    for k in range(tries):
        try:
            os.makedirs(d, exist_ok=True)
            return
        except FileNotFoundError:
            if k == tries - 1:
                raise
            time.sleep(0.2)


def _delete_results(outDir, n, beside_recording):
    """result files of a recording written by earlier passes (other options, the other format); not the labels file
    <name>_labels.csv if the results are written next to the recording. Returns the number of deleted files."""
    names = [n + ".xlsx", n + "_protocols.xlsx"]
    for t in ("summary", "contractions", "pulses", "parameters", "info", "thresholds", "labels", "rockerFilter",
              "overview", "events", "gaps", "channels", "protocols", "protocolResults", "trends", "trendComments"):
        for pre in ("", "protocols_"):
            if t == "labels" and not pre and beside_recording:
                continue
            names += [f"{n}_{pre}{t}.csv", f"{n}_{pre}{t}.csv.gz"]
    k = 0
    for x in names:
        if os.path.isfile(os.path.join(outDir, x)):
            os.remove(os.path.join(outDir, x))
            k += 1
    return k + _delete_trends(outDir, n)


def _delete_trends(outDir, n):
    """trend images of recording n (<outDir>/<n>_ch<c>.png in the series layout, <outDir>/trends/<n>_ch<c>.png in the
    flat layout). Returns the number of deleted files."""
    rx = re.compile("^" + re.escape(n) + r"_ch\d+\.png$")
    k = 0
    for td in (outDir, os.path.join(outDir, "trends")):
        if os.path.isdir(td):
            for x in os.listdir(td):
                if rx.match(x):
                    os.remove(os.path.join(td, x))
                    k += 1
    td = os.path.join(outDir, "trends")
    if os.path.isdir(td) and not os.listdir(td):
        os.rmdir(td)
    return k


def _image_folder(outDir, folders):
    """folder of the trend images of a recording: its results folder (series layout) or <folder>/trends (flat)"""
    return os.path.join(outDir, "trends") if folders == "flat" else outDir


def _abs_folder(res, rel):
    """absolute folder of a folder relative to the results folder ('/' separated, '' = res)"""
    return os.path.join(res, *rel.split("/")) if rel else res


def _remove_empty_folders(d, res):
    """d and its parents up to res (exclusive) deleted while they are empty (results moved to the other layout)"""
    d, res = os.path.normpath(d), os.path.normpath(res)
    while len(d) > len(res) and os.path.isdir(d) and not os.listdir(d):
        os.rmdir(d)
        d = os.path.dirname(d)


def results_of(results_folder, rel):
    """folder with the results of the recording rel (path relative to the raw folder): series layout (2026-10-15) or
    flat layout (earlier results); the series layout if neither has results. Returns (folder, layout)."""
    rel = str(rel).replace("\\", "/")
    n = re.sub(r"\.mdd$", "", rel.rsplit("/", 1)[-1], flags=re.I)
    d = _abs_folder(results_folder, result_folder(rel, "series"))
    if _has_results(d, n):
        return d, "series"
    f = _abs_folder(results_folder, result_folder(rel, "flat"))
    if _has_results(f, n):
        return f, "flat"
    return d, "series"


def _has_results(d, n):
    return any(os.path.isfile(os.path.join(d, n + x)) for x in (
        ".xlsx", "_info.csv", "_summary.csv", "_channels.csv", "_overview.csv", "_overview.csv.gz", "_protocols.xlsx",
        "_protocols_info.csv"))


# ------------------------------------------------------------------------------------------------ trend images
def _trend_values(Ov, names):
    """columns names of the overview (missing: NaN) and their units (parameters; beatsPerMinute: 1/min)"""
    from .parameters import PARAMETERS
    units = {p[0]: p[1] for p in PARAMETERS}
    V = np.full((len(Ov), len(names)), np.nan)
    un = []
    for k, nm in enumerate(names):
        if nm in Ov.columns:
            V[:, k] = pd.to_numeric(Ov[nm], errors="coerce").to_numpy(float)
        un.append(units.get(nm, "1/min" if nm == "beatsPerMinute" else ""))
    return V, un


def _trend_comments(E):
    """comments of the log file (categories comment and protocol) for the trend images"""
    if E is None or not len(E) or "category" not in E.columns:
        return []
    k = E["category"].astype(str).isin(("comment", "protocol")).to_numpy()
    return [dict(t=float(t), text=str(x), category=str(c), channel=float(ch))
            for t, x, c, ch in zip(E["t_file"][k], E["text"][k], E["category"][k], E["channel"][k])]


def _label_text(L, c):
    """labels of channel c for the title: setupID, sliceID, species, tissue, sampleID, treatment (concentration unit)"""
    if L is None or not len(L) or "channel" not in L.columns:
        return ""
    r = np.flatnonzero(pd.to_numeric(L["channel"], errors="coerce").to_numpy(float) == c)
    if not len(r):
        return ""
    r = int(r[0])

    def val(nm):
        if nm not in L.columns:
            return ""
        x = L[nm].iloc[r]
        if isinstance(x, (float, np.floating)) and math.isfinite(x) and float(x).is_integer():
            x = int(x)  # 100, not 100.0 (as MATLAB)
        x = "" if x is None or (isinstance(x, (float, np.floating)) and math.isnan(x)) else str(x).strip()
        return "" if x.lower() in ("nan", "<missing>") else x
    v = []
    for nm in ("setupID", "sliceID", "species", "tissue", "sampleID", "treatment"):
        x = val(nm)
        if not x:
            continue
        if nm == "treatment" and val("concentration"):
            x = f"{x} {val('concentration')} {val('concentrationUnit')}".strip()
        v.append(x)
    return ("  ·  " + "  ·  ".join(v)) if v else ""


def _fmt_g(x):
    return f"{x:g}"


def _trend_subtitle(t0, a, b, nIn, w):
    """start, duration, contractions and the legend of the trend image (t0: datetime of time 0 or None)"""
    if t0 is not None:
        st = (f"{t0 + _dt.timedelta(seconds=a):%Y-%m-%d %H:%M} to "
              f"{t0 + _dt.timedelta(seconds=b):%Y-%m-%d %H:%M}")
    else:
        st = "clock time unknown"
    return (f"{st} ({(b - a) / 3600:.1f} h), {int(round(nIn))} included contractions\nDots: median per "
            f"{_fmt_g(w)} s; line: median of the dots per bin; light blue: stimulation protocol; grey: no signal; "
            f"purple: comments (in protocols only at start / end)")


def _clock(recordingStart):
    """datenum --> datetime (None if unknown)"""
    try:
        return None if recordingStart is None or not math.isfinite(float(recordingStart)) else \
            datenum_to_datetime(float(recordingStart))
    except (TypeError, ValueError):
        return None


def _recording_trends(n, recordingStart, totalSeconds, Ov, E, P, G, L, o):
    """trend data of the channels of one recording: list of (channel, D) for report.trend_image / trend_data; every
    channel with at least 20 included contractions; values of the overview (overview_seconds)"""
    TR = []
    if Ov is None or not len(Ov):
        return TR
    names = list(o["trend_parameters"])
    V, un = _trend_values(Ov, names)
    com = _trend_comments(E)
    t0 = _clock(recordingStart)
    ch = pd.to_numeric(Ov["channel"], errors="coerce").to_numpy(float)
    inc = pd.to_numeric(Ov["included"], errors="coerce").fillna(0).to_numpy(float) > 0
    nb = pd.to_numeric(Ov["nBeats"], errors="coerce").fillna(0).to_numpy(float)
    tf = pd.to_numeric(Ov["t_from"], errors="coerce").to_numpy(float)
    for c in np.unique(ch[~np.isnan(ch)]):
        r = ch == c
        nIn = float(nb[r & inc].sum())
        if nIn < 20:
            continue
        B, bl = [], []
        if P is not None and len(P):
            for a, b, nm in zip(P["from"], P["to"], P["name"]):
                B.append([float(a), float(b), 1])
                bl.append(str(nm))
        if G is not None and len(G):
            g = pd.to_numeric(G["channel"], errors="coerce").to_numpy(float) == c
            for a, b in zip(np.asarray(G["from"], float)[g], np.asarray(G["to"], float)[g]):
                B.append([a, b, 2])
                bl.append("")
        cc = [x for x in com if x["channel"] == 0 or x["channel"] == c]
        D = dict(title=f"{n}  ·  channel {int(c)}{_label_text(L, int(c))}",
                 subtitle=_trend_subtitle(t0, 0, float(totalSeconds), nIn, float(o["overview_seconds"])),
                 t=tf[r], w=float(o["overview_seconds"]), nb=nb[r], inc=inc[r], V=V[r], names=names, units=un, t0=t0,
                 xlim=[0, float(totalSeconds)], bands=np.array(B, float).reshape(-1, 3), band_labels=bl, com=cc)
        TR.append((int(c), D))
    return TR


def _trend_images(d, n, TR):
    """trend images <d>/<name>_ch<c>.png of the channels of TR (_recording_trends); d = _image_folder(...)"""
    from .report import trend_image
    files = []
    for c, D in TR:
        f = trend_image(os.path.join(d, f"{n}_ch{c}.png"), D)
        if f:
            files.append(f)
    return files


def _clock_labels(t0, t):
    """clock times 'yyyy-mm-dd HH:MM:SS' of the times t (s in the file); '' if the clock time is unknown"""
    if t0 is None:
        return [""] * len(t)
    half = _dt.timedelta(microseconds=500000)  # rounded to whole seconds (as MATLAB)
    return [(t0 + _dt.timedelta(seconds=float(x)) + half).replace(microsecond=0).strftime(_TIME_FMT) for x in t]


def _trend_tables(TR, t0):
    """sheets trends and trendComments (2026-10-14): the data of the trend images of all channels. trends: channel,
    window (clock time of its start), t_from (s in the file), nBeats (included contractions), the trend parameters
    (median per window; units as in the sheet parameters), bin_from (s; line of the image = median of the rows with the
    same bin_from); trendComments: channel, number (as in the image), t_file, clockTime, text. (None, None) without
    channels."""
    from .report import trend_data
    T, C = [], []
    for c, D in TR:
        Tk, Ck = trend_data(D)
        Tk.insert(0, "channel", float(c))
        Tk.insert(1, "window", _clock_labels(t0, Tk["t_from"]))
        Ck = Ck.rename(columns={"t": "t_file"})
        Ck.insert(0, "channel", float(c))
        Ck.insert(3, "clockTime", _clock_labels(t0, Ck["t_file"]))
        T.append(Tk)
        C.append(Ck)
    if not T:
        return None, None
    return pd.concat(T, ignore_index=True), pd.concat(C, ignore_index=True)


def _write_trend_tables(d, n, Ttr, Tcm):
    """sheets trends / trendComments of <n>.xlsx (or <n>_trends.csv, _trendComments.csv for csv results) replaced"""
    if Ttr is None:
        return
    x = os.path.join(d, n + ".xlsx")
    if os.path.isfile(x):
        with pd.ExcelWriter(x, engine="openpyxl", mode="a", if_sheet_exists="replace") as xw:
            Ttr.to_excel(xw, sheet_name="trends", index=False)
            Tcm.to_excel(xw, sheet_name="trendComments", index=False)
    else:
        Ttr.to_csv(os.path.join(d, n + "_trends.csv"), index=False)
        Tcm.to_csv(os.path.join(d, n + "_trendComments.csv"), index=False)


def trends_again(results_folder, include=None, exclude=None, case_sensitive=False,
                 trend_parameters=("amplitude", "diastolicForce", "TTP90", "TTR90"), new_slice_hours=2.0,
                 quiet=False):
    """trend images of analysed recordings again from their result files (overview, events, protocols, gaps, labels,
    channels) and of the slices of their experiments (include / exclude / case_sensitive select the recordings of the
    index). Returns (files, report). MyoDishAnalysisWatch('trends', results, ...) in MATLAB."""
    o = _check_result_options(dict(result_format="xlsx", trends=True, trend_parameters=trend_parameters,
                                   overview_seconds=60.0))
    X = read_index(results_folder)
    X = X[X["status"] == "ok"]
    inc, exc = patterns(include), patterns(exclude)
    files, exps, n_rec = [], set(), 0
    for rel in X["file"]:
        rel = str(rel).replace("\\", "/")
        if (inc and not wildcard_match(rel, inc, case_sensitive)) or (exc and wildcard_match(rel, exc, case_sensitive)):
            continue
        n_rec += 1
        dr = os.path.dirname(rel)
        n = os.path.splitext(os.path.basename(rel))[0]
        d, layout = results_of(results_folder, rel)
        exps.add(dr)
        Ov = _read_result(os.path.join(d, n + "_overview.csv"))
        if Ov is None or not len(Ov):
            continue
        E = result_table(d, n, "events")
        P = result_table(d, n + "_protocols", "protocols")
        G = result_table(d, n, "gaps")
        L = result_table(d, n, "labels")
        CH = result_table(d, n, "channels", usecols=["recordingStart", "fileLength_s"])
        start, total = math.nan, float(pd.to_numeric(Ov["t_to"], errors="coerce").max())
        if CH is not None and len(CH):
            try:
                st = str(CH["recordingStart"].iloc[0]).strip()
                if st and st.lower() not in ("nan", "nat", "<missing>"):
                    start = datetime_to_datenum(pd.Timestamp(st).to_pydatetime())
            except (ValueError, TypeError, KeyError):
                pass
            L_ = pd.to_numeric(CH["fileLength_s"], errors="coerce").iloc[0]
            if np.isfinite(L_):
                total = float(L_)
        _delete_trends(d, n)
        f = []
        try:
            TR = _recording_trends(n, start, total, Ov, E, P, G, L, o)
            Ttr, Tcm = _trend_tables(TR, _clock(start))
            _write_trend_tables(d, n, Ttr, Tcm)
            f = _trend_images(_image_folder(d, layout), n, TR)
            files += f
        except Exception as ex:  # noqa: BLE001
            if not quiet:
                print(f"  {rel}: trends: {type(ex).__name__}: {ex}")
        if not quiet:
            print(f"  {rel}: {len(f)} trend image(s)")
    report = f"{len(files)} trend image(s) of {n_rec} recording(s)"
    if exps:
        R = slice_register(results_folder, experiments=sorted(exps), new_slice_hours=float(new_slice_hours),
                           trends=True, trend_parameters=o["trend_parameters"])
        report += (f"; slice register: {len(R)} slices in {len(exps)} experiment(s), images of the series and "
                   "experiments")
    if not quiet:
        print(report)
    return files, report


def reorganize(results_folder, folders="series", new_slice_hours=2.0,
               trend_parameters=("amplitude", "diastolicForce", "TTP90", "TTR90"), register=True, report=True,
               quiet=False):
    """result files of the analysed recordings (mda_index.csv) moved into the layout folders ('series', default, or
    'flat'; 2026-10-15), then the slice register, the images of the series and experiments and the experiment reports
    (PDF, flags of mda_flags.csv) made again for the experiments with moved results. Returns (number of recordings
    moved, report). MyoDishAnalysisWatch('reorganize', results, ...) in MATLAB; mda-watch RESULTS --reorganize."""
    from .report import FLAG_DEFAULTS
    o = _check_result_options(dict(result_format="xlsx", folders=folders, trends=True,
                                   trend_parameters=trend_parameters))
    res = os.path.abspath(results_folder)
    lock = os.path.join(res, LOCK_NAME)
    if os.path.isfile(lock) and time.time() - os.path.getmtime(lock) < LOCK_HOURS * 3600:
        raise RuntimeError(f"reorganize: a watcher is running on {res} (lock file)")
    other = "flat" if o["folders"] == "series" else "series"
    X = read_index(res)
    moved, exps = 0, set()
    for rel in X["file"]:
        rel = str(rel).replace("\\", "/")
        n = os.path.splitext(os.path.basename(rel))[0]
        to = _abs_folder(res, result_folder(rel, o["folders"]))
        frm = _abs_folder(res, result_folder(rel, other))
        if os.path.normpath(frm) == os.path.normpath(to) or not os.path.isdir(frm):
            continue
        src, dst = _result_files(frm, n, other == "flat", o["folders"] == "flat")
        if not src:
            continue
        for a, b in zip(src, dst):
            t = os.path.join(to, *b.split("/"))
            os.makedirs(os.path.dirname(t), exist_ok=True)
            os.replace(os.path.join(frm, *a.split("/")), t)
        _remove_empty_folders(os.path.join(frm, "trends"), res)
        _remove_empty_folders(frm, res)
        moved += 1
        exps.add(rel.rpartition("/")[0])
        if not quiet:
            print(f"  {rel}: {len(src)} file(s) -> {to}")
    rep = f"results of {moved} recording(s) moved to the layout '{o['folders']}'"
    if exps and register:
        R = slice_register(res, experiments=sorted(exps), new_slice_hours=float(new_slice_hours), trends=True,
                           trend_parameters=o["trend_parameters"])
        rep += f"; slice register: {len(R)} slices in {len(exps)} experiment(s), images of the series and experiments"
    if exps and report:
        fl = dict(FLAG_DEFAULTS)
        for e in sorted(exps):
            try:
                _experiment_report("", res, e, [], fl, mda_version(), "", _dt.datetime.now())
            except Exception as ex:  # noqa: BLE001
                rep += f"; PDF report {e}: {type(ex).__name__}: {ex}"
        rep += f"; PDF reports of {len(exps)} experiment(s)"
    if not quiet:
        print(rep)
    return moved, rep


def _result_files(d, n, from_flat, to_flat):
    """result files of recording n in folder d (names relative to d, '/' separated) and their names in the other
    layout (trend images: trends/<n>_ch<c>.png in the flat layout, <n>_ch<c>.png in the series layout); not
    <n>_labels.csv next to the recording (results folder = raw folder)"""
    names = [n + ".xlsx", n + "_protocols.xlsx"]
    beside = os.path.isfile(os.path.join(d, n + ".mdd"))
    for t in ("summary", "contractions", "pulses", "parameters", "info", "thresholds", "labels", "rockerFilter",
              "overview", "events", "gaps", "channels", "protocols", "protocolResults", "trends", "trendComments"):
        for pre in ("", "protocols_"):
            if t == "labels" and not pre and beside:
                continue
            names += [f"{n}_{pre}{t}.csv", f"{n}_{pre}{t}.csv.gz"]
    src = [x for x in names if os.path.isfile(os.path.join(d, x))]
    dst = list(src)
    img = os.path.join(d, "trends") if from_flat else d
    rx = re.compile("^" + re.escape(n) + r"_ch\d+\.png$")
    if os.path.isdir(img):
        for x in sorted(os.listdir(img)):
            if rx.match(x):
                src.append(("trends/" if from_flat else "") + x)
                dst.append(("trends/" if to_flat else "") + x)
    return src, dst


def _gzip(cf):
    """<cf>.gz (compression level 6 as MATLAB gzip: 1/4 of the time of level 9, files ~2-4 % larger; mtime 0:
    identical bytes for identical content), <cf> deleted"""
    with open(cf, "rb") as src, gzip.GzipFile(cf + ".gz", "wb", compresslevel=6, mtime=0) as dst:
        shutil.copyfileobj(src, dst)
    os.remove(cf)

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


_CH_LABELS = ("setupID", "sliceID", "species", "sampleID", "cultureStart")


def _channel_status(H, C, G, E, name, L=None, tEnd=math.inf):
    """one row per channel: recording, its start and length, status at the end of the recording, signal, gaps, last
    contraction, labels (setupID, sliceID, species, sampleID, cultureStart), comments about the end. tEnd = end of the
    analysed ranges (stimulation protocols at the end are not analysed; NaN: protocols only)."""
    TT = float(H.totalSeconds)
    idTxt = _id_date(name)
    start = _time_label(H, 0.0, 0.0) if not math.isnan(H.recordingStart) else ""
    if E is not None and len(E):
        cm = E[E["category"] == "comment"]
        cch, ctx = cm["channel"].to_numpy(float), cm["text"].astype(str).tolist()
    else:
        cch, ctx = np.zeros(0), []
    # 'Calibration' entries of the log file per channel (AU per mN; channel 0 = all channels), in the order of time,
    # several values separated by ';' (2026-10-10: changes are flagged in the slice register)
    CLg = getattr(H, "calibrationLog", None)
    if CLg is None and isinstance(H, dict):
        CLg = H.get("calibrationLog")
    CLg = np.asarray(CLg if CLg is not None else np.zeros((0, 3)), float).reshape(-1, 3)
    CLg = CLg[np.argsort(CLg[:, 0], kind="stable")]
    rows = []
    for c in [int(x) for x in np.ravel(H.dataChannels)]:
        cv = CLg[(CLg[:, 1] == c) | (CLg[:, 1] == 0), 2]
        if cv.size:
            cv = cv[np.r_[True, np.diff(cv) != 0]]
        cal = ";".join("%.15g" % x for x in cv)
        g = G[G["channel"].to_numpy(float) == c]
        typ = g["type"].to_numpy()
        fs_, ue = g["fromStart"].to_numpy(bool), g["untilEnd"].to_numpy(bool)
        noSig = float(np.sum(g["duration"].to_numpy(float)))
        r = dict(recording=name, recordingStart=start, fileLength_s=TT,
                 channel=c, calibration=cal, status="", beatingAtEnd=False, signal_s=max(0.0, TT - noSig), noSignal_s=noSig,
                 nChamberOut=float(np.sum((typ == "chamber out") & ~fs_)),
                 nTechnical=float(np.sum(np.isin(typ, ["board group", "controller", "saturated"]))),
                 firstSignal_s=math.nan, lastSignal_s=math.nan, nContractions=0.0, lastContraction_s=math.nan,
                 lastContractionClock="", lastAmplitude=math.nan, maxAmplitude=math.nan,
                 lastAmplitude_pctMax=math.nan, idDate=idTxt, daysSinceIdDate=math.nan, daysInCulture=math.nan)
        for nm in _CH_LABELS:
            v = ""
            if L is not None and nm in L.columns and np.any(L["channel"].to_numpy(float) == c):
                v = L.loc[L["channel"].to_numpy(float) == c, nm].iat[0]
                v = "" if v is None or (isinstance(v, float) and math.isnan(v)) else str(v)
            r[nm] = v
        r["endComments"] = ""
        cc = C[C["channel"].to_numpy(float) == c] if C is not None and len(C) else None
        r["nContractions"] = float(len(cc)) if cc is not None else 0.0
        if cc is not None and len(cc):  # also in a channel without signal (artifacts, e.g. when chambers are put back)
            r["lastContraction_s"] = float(cc["t_peak"].max())
        if np.any(typ == "no signal"):
            r["status"] = "no slice"
        else:
            r["firstSignal_s"], r["lastSignal_s"] = 0.0, TT
            k = np.flatnonzero(fs_ & ~ue)
            if k.size:
                r["firstSignal_s"] = float(g["to"].iat[k[0]])
            k = np.flatnonzero(ue & ~fs_)
            if k.size:
                r["lastSignal_s"] = float(g["from"].iat[k[0]])
            lastEff = min(r["lastSignal_s"], tEnd)  # end of the analysed signal
            r["beatingAtEnd"] = (not math.isnan(r["lastContraction_s"])) and not math.isnan(lastEff) and \
                lastEff - r["lastContraction_s"] <= 1800
            if k.size and typ[k[0]] == "chamber out":
                r["status"] = "removed"
            elif k.size:
                r["status"] = "signal lost"
            elif math.isnan(tEnd):
                r["status"] = "protocols only"
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


_OVERVIEW_KEYS = ("contraction", "channel", "t_peak", "t_stim", "clockTime", "sampledEvery", "beatType",
                  "rockerMoving", "included", "range", "bin", "sampleMode")


def _overview(C, labels, fr, to, H, w):
    """medians of all contractions per window of w s (file time; split at the ranges), channel, beat type, rocker
    state and inclusion: one row per group with window (clock time of its start), t_from, t_to, nBeats,
    beatsPerMinute (per s of the window in the range) and the median of every numeric parameter."""
    C = C.reset_index(drop=True)
    if not len(C):
        return pd.DataFrame()
    rmap = {r: i for i, r in enumerate(labels)}
    rI = C["range"].map(rmap).to_numpy(float)
    tp = C["t_peak"].to_numpy(float)
    win = np.floor(tp / w)
    ch = C["channel"].to_numpy(float)
    bt = C["beatType"].astype(str).to_numpy()
    rock = C["rockerMoving"].to_numpy(bool)
    inc = C["included"].to_numpy(bool)
    btU = sorted(set(bt))
    btI = np.array([btU.index(b) for b in bt], dtype=float)
    order = np.lexsort((~inc, rock, btI, win, rI, ch))  # channel, range, window, beat type, rocker, included first
    key = np.column_stack([ch, rI, win, btI, rock, inc])[order]
    new = np.ones(len(order), dtype=bool)
    if len(order) > 1:
        new[1:] = np.any(key[1:] != key[:-1], axis=1)
    start = np.flatnonzero(new)
    groups = np.split(order, start[1:])
    lab = [c for c in LABEL_NAMES if c in C.columns]
    num = [c for c in C.columns if c not in _OVERVIEW_KEYS and c not in lab
           and pd.api.types.is_numeric_dtype(C[c].dtype) and not pd.api.types.is_bool_dtype(C[c].dtype)]
    A = C[num].to_numpy(float)
    first = [g[0] for g in groups]
    O = C.iloc[first][["range", "bin", "channel"] + lab].reset_index(drop=True)
    a = np.maximum(win[first] * w, fr[rI[first].astype(int)])
    b = np.minimum((win[first] + 1) * w, np.round(to[rI[first].astype(int)], 6))
    O["window"] = [_time_label(H, x, x) for x in a]
    O["t_from"] = a
    O["t_to"] = b
    O["beatType"] = bt[first]
    O["rockerMoving"] = rock[first].astype(int)
    O["included"] = inc[first].astype(int)
    nB = np.array([len(g) for g in groups], dtype=float)
    O["nBeats"] = nB
    O["beatsPerMinute"] = np.where(b > a, 60 * nB / np.where(b > a, b - a, 1), np.nan)
    with warnings.catch_warnings():  # all-NaN columns of a group: NaN
        warnings.simplefilter("ignore", RuntimeWarning)
        med = np.vstack([np.nanmedian(A[g], axis=0) for g in groups]) if groups else np.zeros((0, len(num)))
    for j, c in enumerate(num):
        O[c] = med[:, j]
    return O


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
        arr = "arrhythmicPacing" in s.columns and bool(
            s["arrhythmicPacing"].astype(str).str.strip().str.lower().isin(["true", "1", "1.0"]).any())
        flags = []
        if nDet == 0:
            flags.append("no contractions")
        elif arr:  # capture < 100 % expected (2026-10-13)
            flags.append("arrhythmic pacing")
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
def patterns(x):
    """wildcard patterns of the options include / exclude: None, a string (several separated by ',' or ';') or a list"""
    if x is None:
        return []
    if isinstance(x, str):
        x = re.split(r"[,;]", x)
    return [str(p).strip().replace("\\", "/") for p in x if str(p).strip()]


def wildcard_match(rel, pats, case_sensitive=False):
    """True if the relative path rel ('folder/name.mdd') matches one of the wildcard patterns (* any characters, ? one
    character): a pattern without '/' is matched against the whole path, every folder name and the file name, a
    pattern with '/' against the whole path (2026-10-13; as MyoDishAnalysisWatch.m)"""
    rel = rel.replace("\\", "/")
    for p in pats:
        rx = re.escape(p).replace("\\*", ".*").replace("\\?", ".")
        parts = [rel] if "/" in p else [rel] + rel.split("/")
        if any(re.fullmatch(rx, q, 0 if case_sensitive else re.I) for q in parts):
            return True
    return False


def log_recordings(log_file, mdd_file):
    """'Recording' entries of the log file of mdd_file (completeness check and parallel recordings, 2026-10-13):
    seconds   recorded time of this file: sum of its intervals started -> stopped, at most last stop - first start
              (s, dataLogTime of the log file; NaN without complete interval)
    stopped   True if its last entry is 'stopped', False if 'started', None without entries
    parallel  True if the file was recorded as a parallel recording (its entries are 'parallel recording' entries;
              the software of 2020 wrote them for main recordings as well)
    started   {file name (lower case): [(start, stop), ...]} of the parallel recordings started from this log
              (s, dataLogTime of this log = time in this file; stop NaN if missing)
    Entries of the recording of the file: 'started: <file>' / 'stopped: <file>' (any file name: renamed files), else
    'started / stopped parallel recording: <this file>'."""
    D = dict(seconds=math.nan, stopped=None, parallel=False, started={})
    txt = read_log_text(log_file)
    if txt is None:
        return D
    own = os.path.basename(mdd_file).lower()
    ev = []  # (time, 1 started / 0 stopped, parallel, file name or None)
    for line in split_lines(txt):
        f = re.split(";+", line)
        if len(f) < 5 or f[3].strip().lower() != "recording":
            continue
        t = str2double(f[1]) / 1000.0
        v = ";".join(f[4:]).strip()
        lv = v.lower()
        k = 1 if "started" in lv else (0 if "stopped" in lv else None)
        if math.isnan(t) or k is None:
            continue
        nm = re.split(r"[\\/]", v.split(":", 1)[1].strip())[-1].strip().lower() if ":" in v else ""
        ev.append((t, k, "parallel" in lv, nm or None))
    mine = [e for e in ev if not e[2]]
    if not mine:
        mine = [e for e in ev if e[2] and e[3] in (None, own)]
        D["parallel"] = bool(mine)
    for t, k, par, nm in ev:
        if par and nm is not None and nm != own:
            W = D["started"].setdefault(nm, [])
            if k == 1:
                W.append([t, math.nan])
            elif W and math.isnan(W[-1][1]):
                W[-1][1] = t
    if mine:
        D["stopped"] = mine[-1][1] == 0
        tot, t0, n = 0.0, None, 0
        for t, k, _, _ in mine:
            if k == 1 and t0 is None:
                t0 = t
            elif k == 0 and t0 is not None:
                tot += t - t0
                t0 = None
                n += 1
        starts = [e[0] for e in mine if e[1] == 1]
        stops = [e[0] for e in mine if e[1] == 0]
        if n:
            D["seconds"] = min(tot, stops[-1] - starts[0]) if stops[-1] > starts[0] else tot
    D["started"] = {k: [tuple(w) for w in v] for k, v in D["started"].items()}
    return D


def main_recording(f, D, cache, prefix_only=False):
    """main recording of the parallel recording f (D = log_recordings of f): a recording of the same folder whose log
    lists f as parallel recording ('started parallel recording: <name of f>') with the same duration (+-max(5 s,
    1 %), if both are known). Returns (path of the main file, start, stop in s of the main file) or None. cache: logs
    of the folder read once per pass. prefix_only (GUI): only the recordings whose name is the beginning of the name
    of f (fast; about 90 % of the parallel recordings)."""
    folder = os.path.dirname(f)
    if folder not in cache:
        refs = {}
        try:
            names = sorted(os.listdir(folder))
        except OSError:
            names = []
        mdd = {os.path.splitext(n)[0].lower(): n for n in names if n.lower().endswith(".mdd") and not n.startswith(".")}
        own = os.path.splitext(os.path.basename(f))[0].lower()
        for n in names:
            if prefix_only and not (len(n) - 8 < len(own) and own.startswith(n[:-8].lower())):
                continue
            if n.lower().endswith("_log.log") and not n.startswith(".") and n[:-8].lower() in mdd:
                m = os.path.join(folder, mdd[n[:-8].lower()])
                for nm, W in log_recordings(os.path.join(folder, n), m)["started"].items():
                    refs.setdefault(nm, []).extend((m, a, b) for a, b in W)
        cache[folder] = refs
    d = D["seconds"]
    for m, a, b in cache[folder].get(os.path.basename(f).lower(), []):
        if os.path.normcase(m) == os.path.normcase(f):
            continue
        if math.isfinite(b) and math.isfinite(d) and abs((b - a) - d) > max(5.0, 0.01 * d):
            continue  # another recording of the same name
        return m, a, b
    return None


def parallel_main(mdd_file):
    """main recording of a parallel recording (GUI: button Main file; 2026-10-14): (path of the main file, start, stop
    in s of the main file) or None (not a parallel recording, or its main file not found). Only the recordings whose
    name is the beginning of the name of mdd_file are searched (fast). As MyoDishAnalysisWatch('mainRecording', f)."""
    f = str(mdd_file)
    D = log_recordings(os.path.splitext(f)[0] + "_log.log", f)
    return main_recording(f, D, {}, prefix_only=True) if D["parallel"] else None


def _window_text(a, b):
    return f"{a:.1f}-{b:.1f} s" if math.isfinite(b) else f"from {a:.1f} s"


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
