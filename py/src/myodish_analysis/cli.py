# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Command line: contraction parameters of every single contraction in a MyoDish recording (.mdd).
(mda-watch: watch_main, mda-timepoints: timepoints_main)

    mda FILE.mdd [-c 1 6 8] [--from 600 3000] [--to 660 3060] [--labels baseline drug] [-o results.xlsx]
                  [--rocker stopped] [--beats stimulated] [--threshold 300 ...] [--zero-force z1 z2 ...]
                  [--rocker-filter] [--external-trigger auto|on|off] [--metadata labels.csv] [--reference ref.mat]
                  [--set name=value ...]
                  [--protocol FFR | RP | ST | PRP | PD | rockerSpeed | all | n ...] [--group-by QUANTITY]
                  [--list-protocols] [--report FILE | --no-report] [--show-figures] [--quiet]

Same analysis as MyoDishAnalysis.m (see myodish_analysis). Without --output the summary is printed. With --output, the
analysis report <output>_report.pdf is written as well (report.py; --no-report: not, --report FILE: this file).
Examples:
    mda examples/example3_humanVentricle.mdd -c 6 --from 0 --to 120
    mda file.mdd -c 1 2 3 --from 600 3000 --to 660 3060 --labels baseline drug --rocker stopped -o results.xlsx
    mda file.mdd -c 3 --from 300 --to 500 --rocker-filter --set medianFilterMs=20 meanFilterMs=10 downsampling=1
    mda examples/example3_humanVentricle.mdd --list-protocols
    mda examples/example3_humanVentricle.mdd -c 6 --protocol FFR                  # per pacing frequency
    mda examples/example8_rabbitVentricle_EP.mdd --protocol RP --rocker any       # per S2 interval

TS 2026-10-06 (protocols 2026-10-07; report 2026-10-11)
"""
from __future__ import annotations

import argparse
import math
import sys


def _value(s):
    low = s.lower()
    if low in ("true", "on", "yes"):
        return True
    if low in ("false", "off", "no"):
        return False
    if low in ("none", "[]"):
        return None
    try:
        return int(s)
    except ValueError:
        pass
    try:
        return float(s)
    except ValueError:
        return s


def main(argv=None):
    from . import __version__
    ap = argparse.ArgumentParser(prog="mda", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", action="version", version=f"MyoDishAnalysis (Python) {__version__}")
    ap.add_argument("mdd", help=".mdd file (the log file <name>_log.log must be in the same folder)")
    ap.add_argument("-c", "--channels", type=int, nargs="+", help="data channels (default: all)")
    ap.add_argument("--from", dest="from_s", type=float, nargs="+", default=[0.0],
                    help="start(s) of the range(s) in s (negative = before the end)")
    ap.add_argument("--to", dest="to_s", type=float, nargs="+", default=[math.inf], help="end(s) of the range(s) in s")
    ap.add_argument("--labels", nargs="+", help="names of the ranges")
    ap.add_argument("--pooled", action="store_true",
                    help="several ranges: also one summary row per channel over all of them ('all ranges')")
    ap.add_argument("-o", "--output", help="output file .xlsx or .csv")
    ap.add_argument("--metadata", help="labels per channel (.csv / .xlsx)")
    ap.add_argument("--rocker", choices=["any", "stopped", "moving"])
    ap.add_argument("--beats", choices=["all", "stimulated"])
    ap.add_argument("--threshold", type=float, nargs="+",
                    help="detection threshold (prominence, uN), one value or one per channel (nan = auto); "
                         "default auto")
    ap.add_argument("--zero-force", type=float, nargs="+", help="zero force (uN), one value or one per channel")
    ap.add_argument("--rocker-filter", action="store_true", help="remove the periodic rocker artifact")
    ap.add_argument("--external-trigger", choices=["auto", "on", "off"],
                    help="external trigger pulses of the status channel as stimuli (external stimulator); default auto")
    ap.add_argument("--reference", help="reference beat(s) (.mat saved by the GUI or MATLAB) for the comparison")
    ap.add_argument("--protocol", nargs="+", help="stimulation protocol(s) of the log file instead of --from/--to: type "
                    "(FFR, RP, ST, PRP, PD, rockerSpeed), 'all', or numbers of --list-protocols (0-based)")
    ap.add_argument("--group-by", help="group the contractions: pacingFrequency, S2interval, stimCurrent, pauseLength, "
                    "rockerSpeed, pulseDuration, log:<code>, none (default with --protocol: by protocol type)")
    ap.add_argument("--list-protocols", action="store_true", help="list the protocols found in the log file and exit")
    ap.add_argument("--settings", help="settings file (saved by the GUI or settings.save_settings) or results of an "
                    "analysis: all options from it; the other arguments override them")
    ap.add_argument("--set", nargs="+", default=[], metavar="NAME=VALUE", help="further options (see options)")
    rp = ap.add_mutually_exclusive_group()
    rp.add_argument("--report", metavar="FILE", help="analysis report (PDF) to this file (default with --output: "
                    "<output>_report.pdf)")
    rp.add_argument("--no-report", action="store_true", help="no analysis report")
    ap.add_argument("--show-figures", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args(argv)
    from .analysis import myodish_analysis
    if a.list_protocols:
        import pandas as pd
        from .protocols import find_protocols
        P = find_protocols(a.mdd)
        with pd.option_context("display.width", 200, "display.max_columns", 20, "display.max_colwidth", 40):
            print(P[["type", "name", "number", "from", "to", "groupBy", "note"]].to_string() if len(P)
                  else "no protocols found (comments 'start ... protocol' / 'end ... protocol')")
        return 0
    prot = None
    if a.protocol:
        prot = a.protocol[0] if len(a.protocol) == 1 and not a.protocol[0].isdigit() else \
            [int(x) for x in a.protocol]
    kw = {}
    if a.settings:
        kw["settings"] = a.settings
    if a.rocker:
        kw["rocker"] = a.rocker
    if a.beats:
        kw["beats"] = a.beats
    if a.threshold is not None:
        kw["threshold"] = a.threshold[0] if len(a.threshold) == 1 else a.threshold
    if a.zero_force is not None:
        kw["zeroForce"] = a.zero_force
    if a.rocker_filter:
        kw["rockerFilter"] = True
    if a.external_trigger:
        kw["externalTrigger"] = a.external_trigger
    if a.reference:
        from .reference_beat import load_reference
        kw["referenceBeat"] = load_reference(a.reference)
    for s in a.set:
        if "=" not in s:
            ap.error(f"--set: NAME=VALUE expected, not '{s}'")
        k, v = s.split("=", 1)
        if "," in v:
            kw[k] = [_value(x) for x in v.split(",")]
        else:
            kw[k] = _value(v)
    if len(a.from_s) != len(a.to_s):
        if len(a.to_s) == 1 and math.isinf(a.to_s[0]):
            a.to_s = [math.inf] * len(a.from_s)
        else:
            ap.error("--from and --to need the same number of values")
    T, S, info = myodish_analysis(a.mdd, a.channels, a.from_s, a.to_s, output=a.output,
                                      report=False if a.no_report else a.report, labels=a.labels,
                                      metadata=a.metadata, showFigures=a.show_figures, quiet=a.quiet, protocol=prot,
                                      groupBy=a.group_by, pooled=a.pooled, **kw)
    if not a.output and not a.quiet:
        import pandas as pd
        cols = ["range", "channel", "group", "nStimuli", "nContractions", "capture_percent", "amplitude_mean",
                "amplitude_SD", "amplitude_pctOfRef", "dFdtMax_mean", "TTP90_mean", "TTR90_mean", "CD90_mean"]
        with pd.option_context("display.width", 200, "display.max_columns", 20):
            print(S[[c for c in cols if c in S.columns]].to_string(index=False))
    if a.show_figures:
        import matplotlib.pyplot as plt
        plt.show()
    return 0


def watch_main(argv=None):
    """mda-watch: analyse new recordings of a folder (see myodish_analysis.watch)."""
    from . import __version__
    from .watch import watch
    ap = argparse.ArgumentParser(
        prog="mda-watch", formatter_class=argparse.RawDescriptionHelpFormatter,
        description="Analyse new MyoDish recordings (.mdd) of a folder and its subfolders: every contraction of the "
                    "whole recording, summary per time bin, stimulation protocols; index and report in the results "
                    "folder. Recordings analysed earlier with another version, other options or changed core code "
                    "are kept and listed in a notice (--reanalyze outdated analyses them again). Same as "
                    "MyoDishAnalysisWatch.m.",
        epilog="Examples:\n  mda-watch /data/myodish/raw /data/myodish/results --rocker-filter\n"
               "  mda-watch raw results --from-date 2026-10-01 --dry-run\n"
               "  mda-watch raw results --schedule \"daily 10:00\"       (every day at 10:00, Ctrl+C stops)\n"
               "  mda-watch raw results --schedule \"weekly Sun 05:00\"  (also \"Mon,Thu 06:30\", \"weekdays 07:00\")\n"
               "  mda-watch raw results --schedule \"every 120 min\"     (first pass now; also \"every 6 h\")\n"
               "  mda-watch raw results --reanalyze outdated   (after an update: all recordings of another version)\n"
               "  mda-watch raw results --contractions thinned --thin-mode median --compress --workers 6\n"
               "  mda-watch raw results --include \"*schedule*\"   (only the schedule files)\n"
               "  mda-watch results --trends-only --include \"ABC00*\"   (trend images again from the results)\n"
               "  mda-watch results --reorganize   (results of earlier versions into the folders of the series)\n"
               "Daily by the operating system: cron (Linux/macOS), launchd (macOS) or the Windows task scheduler.")
    ap.add_argument("--version", action="version", version=f"MyoDishAnalysis (Python) {__version__}")
    ap.add_argument("raw", help="folder with the recordings (subfolders are searched)")
    ap.add_argument("results", nargs="?",
                    help="results folder (index mda_index.csv, results per recording, reports/)")
    ap.add_argument("--schedule", help="passes on a schedule until Ctrl+C: 'daily 10:00', 'weekly Sun 05:00', "
                    "'Mon,Thu 06:30', 'weekdays 07:00', 'every 2 days 10:00', 'every 120 min' (first pass now) or "
                    "'every 6 h'")
    ap.add_argument("--interval", type=float, default=0, help=argparse.SUPPRESS)  # older form of --schedule
    ap.add_argument("--reanalyze", choices=["new", "outdated", "all"], default="new",
                    help="new (default): new and changed recordings (recordings of another version or with other "
                    "options are kept, a notice lists them); outdated: these as well; all: every recording")
    ap.add_argument("--retry-errors", action="store_true", help="analyse recordings with errors again")
    ap.add_argument("--from-date", help="only recordings modified on/after this date (yyyy-mm-dd, dd.mm.yyyy, yymmdd)")
    ap.add_argument("--include", nargs="+", metavar="PATTERN",
                    help="only recordings matching one of these wildcard patterns (* any characters, ? one character; "
                    "without '/': matched against every folder name and the file name, e.g. 'ABC00*' or '*schedule*'; "
                    "with '/': against the path relative to the raw folder)")
    ap.add_argument("--exclude", nargs="+", metavar="PATTERN", help="not the recordings matching these patterns")
    ap.add_argument("--case-sensitive", action="store_true",
                    help="--include and --exclude (and --filter) distinguish upper and lower case (default: ignore "
                    "case)")
    ap.add_argument("--max-files", type=int, help="at most this number of recordings per pass")
    ap.add_argument("--dry-run", action="store_true", help="only list what would be analysed")
    ap.add_argument("--min-age", type=float, default=10, help="minutes since the last change (default 10)")
    ap.add_argument("--incomplete-after", type=float, default=30,
                    help="hours after which a recording without 'Recording stopped' (from the end of its data) or an "
                    "incomplete copy (from its last change) is analysed (default 30)")
    ap.add_argument("--incomplete-tolerance", type=float, default=2, metavar="PERCENT",
                    help="part of the recording in the log file that may be missing in the file (default 2 %%, at "
                    "least 10 s; more: status 'incomplete', checked again in the next pass)")
    ap.add_argument("--parallel", choices=["skip", "analyse", "analyze"], default="skip",
                    help="parallel recordings (schedule files, snapshots) whose main file is in the same folder and "
                    "selected, too: skip (default; index status 'parallel', data and protocols are in the main file) "
                    "or analyse; with --include \"*schedule*\" alone the schedule files are analysed")
    ap.add_argument("--bin-minutes", type=float, default=60, help="time bin of the summary in min (default 60)")
    ap.add_argument("--no-protocols", action="store_true", help="no analysis of the stimulation protocols")
    ap.add_argument("--include-protocols", action="store_true",
                    help="summary and contractions also during the stimulation protocols (default: without them)")
    ap.add_argument("--protocol-margin", type=float, default=0,
                    help="s after the end of a protocol that are excluded as well (default 0)")
    ap.add_argument("--contractions", choices=["all", "thinned", "none"], default="all",
                    help="single contractions to save (default all)")
    ap.add_argument("--thin-factor", type=int, default=10, help="--contractions thinned: every n-th / blocks of n (10)")
    ap.add_argument("--thin-mode", choices=["nth", "median"], default="nth",
                    help="--contractions thinned: every n-th contraction (default) or median of blocks of n")
    ap.add_argument("--result-format", choices=["xlsx", "csv"], default="xlsx",
                    help="xlsx (default): <name>.xlsx with the tables as sheets (summary, channels, gaps, events, "
                    "info, ...) and the large tables as <name>_contractions.csv.gz, _pulses.csv.gz, _overview.csv.gz; "
                    "csv: one file per table")
    ap.add_argument("--folders", choices=["series", "flat"], default="series",
                    help="series (default): <experiment>/<series>/<nn>/ per recording with a number in the name "
                    "(Setup1_ABC000101_3 -> ABC000101/Setup1_ABC000101/03/), <experiment>/<name>/ otherwise, images of "
                    "the series in <experiment>/<series>/; flat: all files of an experiment in <experiment>/")
    ap.add_argument("--reorganize", action="store_true",
                    help="only move the results of the results folder into the layout of --folders (mda-watch RESULTS "
                    "--reorganize) and make the register, the images and the experiment reports again")
    ap.add_argument("--compress", action="store_true",
                    help="--result-format csv: contractions and pulses as .csv.gz")
    ap.add_argument("--overview-seconds", type=float, default=60,
                    help="overview: medians per window of n s (default 60, 0 = none)")
    ap.add_argument("--no-trends", action="store_true",
                    help="no trend images (<name>_ch<c>.png per recording and channel, <series>_ch<c>.png per setup "
                    "and channel, <experiment>_overview.png)")
    ap.add_argument("--trend-parameters", nargs="+", metavar="NAME",
                    default=["amplitude", "diastolicForce", "TTP90", "TTR90"],
                    help="parameters of the trend images (default amplitude diastolicForce TTP90 TTR90; any "
                    "parameter or beatsPerMinute)")
    ap.add_argument("--trends-only", action="store_true",
                    help="only the trend images again from the result files of the results folder (one folder: "
                    "mda-watch RESULTS --trends-only; --include / --exclude select the recordings)")
    ap.add_argument("--no-events", action="store_true", help="no events table (entries of the log file)")
    ap.add_argument("--no-gaps", action="store_true",
                    help="no gaps / channels tables (periods without signal: chamber out, board failures)")
    ap.add_argument("--no-register", action="store_true", help="no slice register (mda_slices.csv)")
    ap.add_argument("--new-slice-hours", type=float, default=2,
                    help="slice register: a slice after >= n h without signal is a new slice (default 2)")
    ap.add_argument("--workers", type=int, default=1, help="recordings analysed in parallel (processes, default 1)")
    ap.add_argument("--no-report", action="store_true",
                    help="no PDF report (<experiment>/<experiment>_report.pdf: all recordings of the experiment, "
                    "channels to check with traces) and no mda_flags.csv")
    ap.add_argument("--rocker", choices=["any", "stopped", "moving"])
    ap.add_argument("--beats", choices=["all", "stimulated"])
    ap.add_argument("--threshold", type=float, nargs="+", help="detection threshold (uN), one value or one per channel")
    ap.add_argument("--rocker-filter", action="store_true", help="remove the periodic rocker artifact")
    ap.add_argument("--settings", help="settings file (saved by the GUI or settings.save_settings) or results of an "
                    "analysis: all analysis options from it; the other arguments override them")
    ap.add_argument("--set", nargs="+", default=[], metavar="NAME=VALUE", help="further analysis options")
    ap.add_argument("--quiet", action="store_true")
    adv = ap.add_argument_group("advanced options")
    adv.add_argument("--filter", metavar="REGEX",
                     help="regular expression on the path relative to the raw folder (--include / --exclude are "
                     "simpler)")
    a = ap.parse_args(argv)
    if a.reorganize:  # results into the other layout (2026-10-15)
        from .watch import reorganize
        try:
            reorganize(a.results or a.raw, folders=a.folders, new_slice_hours=a.new_slice_hours,
                       trend_parameters=a.trend_parameters, register=not a.no_register, report=not a.no_report,
                       quiet=a.quiet)
        except (ValueError, RuntimeError) as ex:
            ap.error(str(ex))
        return 0
    if a.trends_only:  # trend images again from the results (2026-10-14)
        from .watch import trends_again
        try:
            trends_again(a.results or a.raw, include=a.include, exclude=a.exclude, case_sensitive=a.case_sensitive,
                         trend_parameters=a.trend_parameters, new_slice_hours=a.new_slice_hours, quiet=a.quiet)
        except ValueError as ex:
            ap.error(str(ex))
        return 0
    if not a.results:
        ap.error("the results folder is missing (mda-watch RAW RESULTS)")
    kw = {}
    if a.settings:
        kw["settings"] = a.settings
    if a.rocker:
        kw["rocker"] = a.rocker
    if a.beats:
        kw["beats"] = a.beats
    if a.threshold is not None:
        kw["threshold"] = a.threshold[0] if len(a.threshold) == 1 else a.threshold
    if a.rocker_filter:
        kw["rockerFilter"] = True
    for s in a.set:
        if "=" not in s:
            ap.error(f"--set: NAME=VALUE expected, not '{s}'")
        k, v = s.split("=", 1)
        kw[k] = [_value(x) for x in v.split(",")] if "," in v else _value(v)
    if a.schedule:
        from .watch import parse_schedule
        try:
            parse_schedule(a.schedule)
        except ValueError as ex:
            ap.error(str(ex))
    watch(a.raw, a.results, interval=a.interval, schedule=a.schedule, reanalyze=a.reanalyze,
          retry_errors=a.retry_errors, from_date=a.from_date, filter=a.filter, include=a.include, exclude=a.exclude,
          case_sensitive=a.case_sensitive, max_files=a.max_files, dry_run=a.dry_run,
          min_file_age_minutes=a.min_age, incomplete_after_hours=a.incomplete_after,
          incomplete_tolerance=a.incomplete_tolerance, parallel=a.parallel, bin_minutes=a.bin_minutes,
          protocols=not a.no_protocols, include_protocols=a.include_protocols,
          protocol_margin_seconds=a.protocol_margin, contractions=a.contractions, thin_factor=a.thin_factor,
          thin_mode=a.thin_mode, compress=a.compress, overview_seconds=a.overview_seconds, events=not a.no_events,
          gaps=not a.no_gaps, register=not a.no_register, new_slice_hours=a.new_slice_hours, workers=a.workers,
          report=not a.no_report, result_format=a.result_format, folders=a.folders, trends=not a.no_trends,
          trend_parameters=a.trend_parameters, quiet=a.quiet, **kw)
    return 0


def timepoints_main(argv=None):
    """mda-timepoints RESULTS LABEL --series S [S ...] [--channels C ...] --time T [T ...] --offsets O [O ...]
    [--seconds 120] [--parameters P ...] [--baseline O | none] [--raw-folder RAW] [--sample-id ID ...] [--group G ...]
    [--no-average-beats] [--no-figures] [--no-write]: contraction parameters and average beats in windows before and
    after a treatment (timepoints.py, mda_timepoints.m)"""
    from .timepoints import timepoints, DEFAULT_PARAMETERS
    ap = argparse.ArgumentParser(
        prog="mda-timepoints",
        description="Contraction parameters in windows of SECONDS starting at TIME + OFFSET (min) for channels of "
                    "the series (results of mda-watch). Files: <experiment>/timepoints/<label>_<time>/ (xlsx with "
                    "summary, matrix, course, beats, info; images .png and .svg).",
        epilog="Examples:\n"
               "  mda-timepoints results Mava100 --series Setup1_ABC000101 --channels 1 3 5 "
               "--time \"2000-01-01 15:20\" --offsets -10 10 60 240 1440\n"
               "  mda-timepoints results Ome2uM --series Setup1_ABC000101 Setup2_ABC000101 --channels 1 2 "
               "--time \"2000-01-01 13:20:00\" \"2000-01-01 13:30:00\" --offsets -60 120 --seconds 300\n"
               "  (--channels: the same channels in every series; none: all channels with contractions; --time: one, "
               "one per series or one per channel)",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("results", help="results folder of mda-watch (with mda_index.csv) or a folder in it")
    ap.add_argument("label", help="name of the treatment (letters, digits, '.', '-', '_'): name of the output folder")
    ap.add_argument("--series", nargs="+", required=True, help="series: file name up to its number")
    ap.add_argument("--channels", nargs="*", type=int, default=[], help="channels (default: all with contractions)")
    ap.add_argument("--time", nargs="+", required=True, help="clock time of the treatment ('yyyy-mm-dd HH:MM[:SS]')")
    ap.add_argument("--offsets", nargs="+", type=float, required=True,
                    help="start of the windows in minutes after the treatment (negative = before)")
    ap.add_argument("--seconds", type=float, default=120.0, help="duration of every window (s, default 120)")
    ap.add_argument("--parameters", nargs="+", default=list(DEFAULT_PARAMETERS), help="parameters (default: "
                    + " ".join(DEFAULT_PARAMETERS) + ")")
    ap.add_argument("--baseline", default=None, help="offset of the reference window (default: the last negative "
                    "offset; none: no pctBaseline)")
    ap.add_argument("--raw-folder", default="", help="raw folder of mda-watch (average beats; default: the path of the "
                    "analysis)")
    ap.add_argument("--sample-id", nargs="+", default=[], help="sample of the slices: one or one per series (default: "
                    "slice register, else the series name after the setup)")
    ap.add_argument("--group", nargs="+", default=[], help="group of the sample: one or one per series (default none)")
    ap.add_argument("--no-average-beats", action="store_true", help="no average beats (the recordings are not read)")
    ap.add_argument("--no-figures", action="store_true", help="no images")
    ap.add_argument("--no-write", action="store_true", help="no files (the summary is printed)")
    a = ap.parse_args(argv)
    b = None if a.baseline is None else (math.nan if a.baseline.lower() == "none" else float(a.baseline))
    one = lambda x: x[0] if len(x) == 1 else x  # noqa: E731
    time_ = a.time[0] if len(a.time) == 1 else a.time
    try:
        TP = timepoints(a.results, a.label, a.series, a.channels, time_, a.offsets, a.seconds,
                        parameters=a.parameters, baseline=b, write=not a.no_write, figures=not a.no_figures,
                        average_beats=not a.no_average_beats, raw_folder=a.raw_folder, sampleID=one(a.sample_id),
                        group=one(a.group))
    except ValueError as ex:
        ap.error(str(ex))
    import pandas as pd
    with pd.option_context("display.width", 200, "display.max_columns", 12, "display.max_colwidth", 60):
        cols = ["series", "channel", "offset_min", "from", "nIncluded"] + [
            c for c in (a.parameters[0], a.parameters[0] + "_pctBaseline") if c in TP["summary"].columns] + ["note"]
        print(TP["summary"][cols].to_string(index=False))
    for f in TP["files"]:
        print(f)
    return 0


def pool_timepoints_main(argv=None):
    """mda-pool-timepoints SOURCE [SOURCE ...] [--labels L ...] [--order L ...] [--control L ...] [--name NAME]
    [--output-folder F] [--no-figures] [--no-write]: analyses of mda-timepoints pooled by treatment (timepoints.py pool_timepoints,
    mda_poolTimepoints.m)"""
    from .timepoints import pool_timepoints
    ap = argparse.ArgumentParser(
        prog="mda-pool-timepoints",
        description="Analyses of mda-timepoints (<experiment>/timepoints/<label>_<time>/) pooled by treatment (label): "
                    "workbook with all slices and time points (sampleID, group, treatment, timePoint, parameters), "
                    "samples, treatments, course, average beats; images per treatment. Files: <results>/"
                    "timepoints_pooled/<name>/.",
        epilog="Examples:\n"
               "  mda-pool-timepoints results\n"
               "  mda-pool-timepoints results --labels CTRL OME3uM MAVA1uM --name myosinModulators",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", nargs="+", help="results folder of mda-watch (all analyses below it) or analysis folders")
    ap.add_argument("--labels", nargs="+", default=None, help="treatments to pool (default: all)")
    ap.add_argument("--order", nargs="+", default=None, help="order of the treatments in the images")
    ap.add_argument("--control", nargs="+", default=None, help="treatments that are controls (default: labels "
                    "starting with CTRL, control, vehicle or DMSO)")
    ap.add_argument("--name", default="pooled", help="name of the pooled analysis (default pooled)")
    ap.add_argument("--output-folder", default="", help="folder of the files (default <results>/timepoints_pooled/"
                    "<name>)")
    ap.add_argument("--no-figures", action="store_true", help="no images")
    ap.add_argument("--no-write", action="store_true", help="no files (the treatments are printed)")
    a = ap.parse_args(argv)
    try:
        PT = pool_timepoints(a.source[0] if len(a.source) == 1 else a.source, labels=a.labels, order=a.order,
                             name=a.name, output_folder=a.output_folder, write=not a.no_write,
                             figures=not a.no_figures, control=a.control)
    except ValueError as ex:
        ap.error(str(ex))
    import pandas as pd
    p = PT["parameters"][0]
    with pd.option_context("display.width", 200, "display.max_columns", 12):
        cols = ["treatment", "timePoint", "nSlices", "nSamples", p, p + "_SEM"] + [
            c for c in (p + "_pctBaseline", p + "_pctBaseline_SEM") if c in PT["treatments"].columns]
        print(PT["treatments"][cols].to_string(index=False))
    for n in PT["notes"]:
        print("note: " + n)
    for f in PT["files"]:
        print(f)
    return 0


def selftest_main():
    from .selftest import main as m
    m()


if __name__ == "__main__":
    sys.exit(main())
