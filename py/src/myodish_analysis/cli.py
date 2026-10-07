"""Command line: contraction parameters of every single contraction in a MyoDish recording (.mdd).

    mda FILE.mdd [-c 1 6 8] [--from 600 3000] [--to 660 3060] [--labels baseline drug] [-o results.xlsx]
                  [--rocker stopped] [--beats stimulated] [--threshold 300] [--zero-force z1 z2 ...]
                  [--rocker-filter] [--metadata labels.csv] [--reference ref.mat] [--set name=value ...]
                  [--show-figures] [--quiet]

Same analysis as MyoDishAnalysis.m (see myodish_analysis). Without --output the summary is printed.
Examples:
    mda examples/example3_humanVentricle.mdd -c 6 --from 0 --to 120
    mda file.mdd -c 1 2 3 --from 600 3000 --to 660 3060 --labels baseline drug --rocker stopped -o results.xlsx
    mda file.mdd -c 3 --from 300 --to 500 --rocker-filter --set medianFilterMs=20 meanFilterMs=10 downsampling=1

TS 2026-10-06
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
    ap.add_argument("--threshold", type=float, help="detection threshold (prominence, uN); default auto")
    ap.add_argument("--zero-force", type=float, nargs="+", help="zero force (uN), one value or one per channel")
    ap.add_argument("--rocker-filter", action="store_true", help="remove the periodic rocker artifact")
    ap.add_argument("--reference", help="reference beat(s) (.mat saved by the GUI or MATLAB) for the comparison")
    ap.add_argument("--set", nargs="+", default=[], metavar="NAME=VALUE", help="further options (see options)")
    ap.add_argument("--show-figures", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args(argv)
    from .analysis import myodish_analysis
    kw = {}
    if a.rocker:
        kw["rocker"] = a.rocker
    if a.beats:
        kw["beats"] = a.beats
    if a.threshold is not None:
        kw["threshold"] = a.threshold
    if a.zero_force is not None:
        kw["zeroForce"] = a.zero_force
    if a.rocker_filter:
        kw["rockerFilter"] = True
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
                                      metadata=a.metadata, showFigures=a.show_figures, quiet=a.quiet, **kw)
    if not a.output and not a.quiet:
        import pandas as pd
        cols = ["range", "channel", "nContractions", "amplitude_mean", "amplitude_SD", "dFdtMax_mean", "TTP90_mean",
                "TTR90_mean", "CD90_mean"]
        with pd.option_context("display.width", 200, "display.max_columns", 20):
            print(S[[c for c in cols if c in S.columns]].to_string(index=False))
    if a.show_figures:
        import matplotlib.pyplot as plt
        plt.show()
    return 0


def selftest_main():
    from .selftest import main as m
    m()


if __name__ == "__main__":
    sys.exit(main())
