"""Command line: contraction parameters of every single contraction in a MyoDish recording (.mdd).

    mda FILE.mdd [-c 1 6 8] [--from 600 3000] [--to 660 3060] [--labels baseline drug] [-o results.xlsx]
                  [--rocker stopped] [--beats stimulated] [--threshold 300 ...] [--zero-force z1 z2 ...]
                  [--rocker-filter] [--external-trigger auto|on|off] [--metadata labels.csv] [--reference ref.mat]
                  [--set name=value ...]
                  [--protocol FFR | RP | ST | PRP | PD | rockerSpeed | all | n ...] [--group-by QUANTITY]
                  [--list-protocols] [--show-figures] [--quiet]

Same analysis as MyoDishAnalysis.m (see myodish_analysis). Without --output the summary is printed.
Examples:
    mda examples/example3_humanVentricle.mdd -c 6 --from 0 --to 120
    mda file.mdd -c 1 2 3 --from 600 3000 --to 660 3060 --labels baseline drug --rocker stopped -o results.xlsx
    mda file.mdd -c 3 --from 300 --to 500 --rocker-filter --set medianFilterMs=20 meanFilterMs=10 downsampling=1
    mda examples/example3_humanVentricle.mdd --list-protocols
    mda examples/example3_humanVentricle.mdd -c 6 --protocol FFR                  # per pacing frequency
    mda examples/example8_rabbitVentricle_EP.mdd --protocol RP --rocker any       # per S2 interval

TS 2026-10-06 (protocols 2026-10-07)
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
    ap.add_argument("--set", nargs="+", default=[], metavar="NAME=VALUE", help="further options (see options)")
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
    T, S, info = myodish_analysis(a.mdd, a.channels, a.from_s, a.to_s, output=a.output, labels=a.labels,
                                      metadata=a.metadata, showFigures=a.show_figures, quiet=a.quiet, protocol=prot,
                                      groupBy=a.group_by, **kw)
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
                    "folder. Recordings analysed with another version, other options or changed core code are "
                    "analysed again (--reanalyze outdated). Same as MyoDishAnalysisWatch.m.",
        epilog="Examples:\n  mda-watch /data/myodish/raw /data/myodish/results --rocker-filter\n"
               "  mda-watch raw results --from-date 2026-10-01 --dry-run\n"
               "  mda-watch raw results --interval 24          (one pass every 24 h, Ctrl+C stops)\n"
               "  mda-watch raw results --contractions thinned --thin-mode median --compress --workers 6\n"
               "Daily by the operating system: cron (Linux/macOS), launchd (macOS) or the Windows task scheduler.")
    ap.add_argument("--version", action="version", version=f"MyoDishAnalysis (Python) {__version__}")
    ap.add_argument("raw", help="folder with the recordings (subfolders are searched)")
    ap.add_argument("results", help="results folder (index mda_index.csv, results per recording, reports/)")
    ap.add_argument("--interval", type=float, default=0, help="hours between passes (default 0 = one pass)")
    ap.add_argument("--reanalyze", choices=["outdated", "new", "all"], default="outdated",
                    help="outdated (default): new, changed and outdated recordings; new: only new and changed; all")
    ap.add_argument("--retry-errors", action="store_true", help="analyse recordings with errors again")
    ap.add_argument("--from-date", help="only recordings modified on/after this date (yyyy-mm-dd, dd.mm.yyyy, yymmdd)")
    ap.add_argument("--filter", help="regular expression on the path relative to the raw folder")
    ap.add_argument("--max-files", type=int, help="at most this number of recordings per pass")
    ap.add_argument("--dry-run", action="store_true", help="only list what would be analysed")
    ap.add_argument("--min-age", type=float, default=10, help="minutes since the last change (default 10)")
    ap.add_argument("--incomplete-after", type=float, default=30,
                    help="hours after which a recording without 'Recording stopped' is analysed (default 30)")
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
    ap.add_argument("--compress", action="store_true", help="contractions as <name>_contractions.csv.gz")
    ap.add_argument("--no-events", action="store_true", help="no <name>_events.csv (entries of the log file)")
    ap.add_argument("--workers", type=int, default=1, help="recordings analysed in parallel (processes, default 1)")
    ap.add_argument("--rocker", choices=["any", "stopped", "moving"])
    ap.add_argument("--beats", choices=["all", "stimulated"])
    ap.add_argument("--threshold", type=float, nargs="+", help="detection threshold (uN), one value or one per channel")
    ap.add_argument("--rocker-filter", action="store_true", help="remove the periodic rocker artifact")
    ap.add_argument("--set", nargs="+", default=[], metavar="NAME=VALUE", help="further analysis options")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args(argv)
    kw = {}
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
    watch(a.raw, a.results, interval=a.interval, reanalyze=a.reanalyze, retry_errors=a.retry_errors,
          from_date=a.from_date, filter=a.filter, max_files=a.max_files, dry_run=a.dry_run,
          min_file_age_minutes=a.min_age, incomplete_after_hours=a.incomplete_after, bin_minutes=a.bin_minutes,
          protocols=not a.no_protocols, include_protocols=a.include_protocols,
          protocol_margin_seconds=a.protocol_margin, contractions=a.contractions, thin_factor=a.thin_factor,
          thin_mode=a.thin_mode, compress=a.compress, events=not a.no_events, workers=a.workers, quiet=a.quiet, **kw)
    return 0


def selftest_main():
    from .selftest import main as m
    m()


if __name__ == "__main__":
    sys.exit(main())
