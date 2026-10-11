# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Save and load the settings of an analysis (all options, including the advanced settings). Port of mda_settings.m.

    save_settings('mySettings.csv', opts)   write a settings file: table key, value (as the info table of the
                                            results): createdBy (MyoDishAnalysisSettings), version, implementation,
                                            savedDate, option_<name> for every option except the reference beat
    opts, notes = load_settings(file, notes=True)
    opts = load_settings(file)              complete options (options()) from a settings file or from results of
                                            the analysis, the watcher or the GUI (.xlsx, <name>_info.csv: the options
                                            of that analysis); options missing in the file have their default,
                                            options unknown in this version are ignored (notes)

The same file format is read and written by the MATLAB version (mda_settings.m). Every analysis stores its options in
the info table of the results, so the results of an analysis can be loaded as settings, too.
Use: options(settings=file), myodish_analysis(..., settings=file), mda-analyze --settings file, mda-watch --settings
file, GUI: Advanced ... -> Save settings ... / Load settings ...

TS 2026-10-10
"""
from __future__ import annotations

import datetime as _dt
import os

import pandas as pd


def save_settings(file, opts=None):
    from .options import options as make_options
    from .write_results import _option_text, mda_version
    if opts is None:
        opts = make_options()
    file = str(file)
    if not os.path.splitext(file)[1]:
        file += ".csv"
    keys = ["createdBy", "version", "implementation", "savedDate"]
    vals = ["MyoDishAnalysisSettings", mda_version(), "Python", _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")]
    for k, v in opts.items():
        if k == "referenceBeat":
            continue
        keys.append("option_" + k)
        vals.append(_option_text(v))
    pd.DataFrame({"key": keys, "value": vals}).to_csv(file, index=False)
    return file


def load_settings(file, notes=False):
    from .read_results import read_results
    R = read_results(str(file))
    opts = R["options"]
    if "referenceBeat" in opts:
        opts["referenceBeat"] = None
    return (opts, R["notes"]) if notes else opts
