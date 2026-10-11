# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Write contraction table, summary and analysis info to Excel (.xlsx) or text (.csv). Port of mda_writeResults.m.

    write_results('results.xlsx', contractions, summary, info)
        sheets: contractions, summary, parameters (definitions), info (file facts, version and all options),
        thresholds (analysis windows: data window read, analysed range and detection threshold per channel and
        chunk; used to open the results in the GUI), labels, rockerFilter (option rockerFilter: result per channel and
        time range), protocols (option protocol), protocolResults (characteristic values per protocol and channel)
    write_results('results.csv', ...)
        results_contractions.csv, results_summary.csv, results_parameters.csv, results_info.csv, ...
    info_table(info)
        only the info table (key, value): file, ..., software, version, implementation, notes, info['extra'] (rows
        (key, value), e.g. createdBy, channels, loadedWindow_s), option_<name> for every option, log file entries

Existing sheets of the same name are overwritten.

TS 2026-10-06 (port of mda_writeResults.m, TS 2026-10-05; version, implementation, extra rows, thresholds
sheet 2026-10-09)
"""
from __future__ import annotations

import datetime as _dt
import math
import os
import re

import numpy as np
import pandas as pd

from . import __version__
from ._matlab import datenum_to_datetime
from .parameters import PARAMETERS


def num2str(v):
    """MATLAB num2str of a scalar."""
    if isinstance(v, (bool, np.bool_)):
        return "1" if v else "0"
    v = float(v)
    if math.isnan(v):
        return "NaN"
    if math.isinf(v):
        return "Inf" if v > 0 else "-Inf"
    if v == int(v) and abs(v) < 1e15:
        return str(int(v))
    d = max(1, int(math.floor(math.log10(abs(v)))) + 5)
    return f"{v:.{d}g}"


def mat2str(v):
    a = np.asarray(v, dtype=float)
    if a.ndim == 0 or a.size == 1:
        return num2str(float(a.ravel()[0]))
    if a.ndim == 1:
        return "[" + " ".join(num2str(x) for x in a) + "]"
    return "[" + ";".join(" ".join(num2str(x) for x in row) for row in a) + "]"


def mda_version():
    """version of MyoDishAnalysis as in MATLAB ('1.0.0b1' --> '1.0.0-beta.1')."""
    m = re.fullmatch(r"(\d+\.\d+\.\d+)(?:(a|b|rc)(\d+))?", __version__)
    if not m:
        return __version__
    if not m.group(2):
        return m.group(1)
    return "%s-%s.%s" % (m.group(1), {"a": "alpha", "b": "beta", "rc": "rc"}[m.group(2)], m.group(3))


def _num15(v):
    """sprintf('%.15g', v) of MATLAB (options in the info table: full precision, read back by read_results)."""
    v = float(v)
    if math.isnan(v):
        return "NaN"
    if math.isinf(v):
        return "Inf" if v > 0 else "-Inf"
    return f"{v:.15g}"


def _mat2str15(a):
    """mat2str of MATLAB (15 significant digits)."""
    a = np.asarray(a, dtype=float)
    if a.size == 1:
        return _num15(a.ravel()[0])
    if a.ndim <= 1:
        return "[" + " ".join(_num15(x) for x in a.ravel()) + "]"
    return "[" + ";".join(" ".join(_num15(x) for x in row) for row in a) + "]"


def _align_of(r):
    return "stimulus" if r.get("align") == "stimulus" else "50 % upstroke"


def _option_text(v):
    if isinstance(v, str):
        return v
    if v is None:
        return ""
    if isinstance(v, (list, tuple)) and v and isinstance(v[0], dict):  # reference beat(s)
        return "reference beat: " + "; ".join(
            f"channel {int(r['channel'])} ({r.get('source', '')}; aligned at the {_align_of(r)})" for r in v)
    if isinstance(v, dict):
        return _option_text([v])
    if isinstance(v, (bool, np.bool_)):
        return num2str(v)
    a = np.asarray(v)
    if a.size == 0:
        return ""
    if a.size == 1:
        return _num15(a.ravel()[0])
    return _mat2str15(a)


def parameter_table(contractions=None):
    from .analyze_ap import AP_PARAMETERS
    rows = [list(p) for p in PARAMETERS]
    if isinstance(contractions, pd.DataFrame):
        for c in contractions.columns:
            if c.endswith("_dRef"):
                rows.append([c, "uN", f"{c[:-5]} - mean of the reference contractions (reference beat of the channel)"])
            elif c.endswith("_pctRef"):
                rows.append([c, "%", f"100 * {c[:-7]} / mean of the reference contractions (reference beat of the "
                                     "channel)"])
        for p in AP_PARAMETERS:
            if p[0] in contractions.columns:
                rows.append(list(p))
    return pd.DataFrame(rows, columns=["parameter", "unit", "definition"])


def info_table(info):
    o = info["options"]
    # 2026-10-09: version and implementation as own rows; info['extra'] (rows (key, value)) after the notes
    extra = [(str(k), str(v)) for k, v in (info.get("extra") or [])]
    keys = ["file", "samplingRate_Hz", "samplingRateSource", "nChannelsInFile", "fileLength_s", "recordingStart",
            "analysisDate", "software", "version", "implementation", "notes"] + [k for k, _ in extra]
    startStr = ""
    rs = info.get("recordingStart", math.nan)
    if rs is not None and not (isinstance(rs, float) and math.isnan(rs)):
        startStr = datenum_to_datetime(rs).strftime("%Y-%m-%d %H:%M:%S")
    analysisDate = info.get("analysisDate", _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    vals = [info["file"], num2str(info["samplingRate"]), info["samplingRateSource"], num2str(info["nChannelsInFile"]),
            f"{info['totalSeconds']:.3f}", startStr, analysisDate,
            f"MyoDishAnalysis (Python) {__version__} (T. Seidel, FAU Erlangen-Nuernberg)", mda_version(), "Python",
            " | ".join(info.get("notes", []))] + [v for _, v in extra]
    for k, v in o.items():
        keys.append("option_" + k)
        vals.append(_option_text(v))
    # zero force (Offset) and Calibration entries of the log file, per channel (unique values)
    if "offsetLog" in info:
        for field, prefix in (("offsetLog", "logOffset_ch"), ("calibrationLog", "logCalibration_ch")):
            E = np.asarray(info[field], dtype=float).reshape(-1, 3)
            for ch in np.unique(E[:, 1]):
                v = E[E[:, 1] == ch, 2]
                u = []
                for x in v:
                    if x not in u:
                        u.append(x)
                keys.append(f"{prefix}{num2str(ch)}")
                vals.append(", ".join(num2str(x) for x in u))
    return pd.DataFrame({"key": keys, "value": vals})


def _for_file(T, csv):
    """table as written by MATLAB writetable: logical --> 1/0, datetime --> text (csv)."""
    T = T.copy()
    for c in T.columns:
        if T[c].dtype == bool:
            T[c] = T[c].astype(int)
        elif csv and pd.api.types.is_datetime64_any_dtype(T[c].dtype):
            T[c] = T[c].dt.strftime("%Y-%m-%d %H:%M:%S.%f").str[:-3]
    return T


def write_results(output_file, contractions, summary, info):
    p, nm = os.path.split(output_file)
    n, e = os.path.splitext(nm)
    if not e:
        e = ".xlsx"
        output_file = os.path.join(p, n + e)
    paramTable = parameter_table(contractions)
    infoTable = info_table(info)
    tabs = [("contractions", contractions), ("summary", summary), ("parameters", paramTable), ("info", infoTable)]
    th = info.get("thresholds")  # analysis windows (myodish_analysis, GUI export)
    if isinstance(th, pd.DataFrame) and len(th) > 0:
        tabs.append(("thresholds", th))
    if isinstance(info.get("labels"), pd.DataFrame):
        tabs.append(("labels", info["labels"]))
    rf = info.get("rockerFilter")
    if isinstance(rf, pd.DataFrame) and len(rf) > 0:
        tabs.append(("rockerFilter", rf))
    pr = info.get("protocols")
    if isinstance(pr, pd.DataFrame) and len(pr) > 0:
        tabs.append(("protocols", pr))
    rr = info.get("protocolResults")
    if isinstance(rr, pd.DataFrame) and len(rr) > 0:
        tabs.append(("protocolResults", rr))
    pu = info.get("pulses")  # all stimulus pulses of the analysed channels and ranges (option pulseTable, 2026-10-10)
    if isinstance(pu, pd.DataFrame) and len(pu) > 0:
        tabs.append(("pulses", pu))
    if e.lower() == ".csv":
        out = []
        for name, T in tabs:
            f = os.path.join(p, f"{n}_{name}.csv")
            _for_file(T, True).to_csv(f, index=False)
            out.append(f)
        return out
    out = [output_file]
    if isinstance(pu, pd.DataFrame) and len(pu) >= 1048576:  # Excel row limit: <name>_pulses.csv
        tabs = [x for x in tabs if x[0] != "pulses"]
        f = os.path.join(p, f"{n}_pulses.csv")
        _for_file(pu, True).to_csv(f, index=False)
        out.append(f)
    mode = "a" if os.path.isfile(output_file) else "w"
    kw = dict(if_sheet_exists="replace") if mode == "a" else {}
    with pd.ExcelWriter(output_file, engine="openpyxl", mode=mode, **kw) as xw:
        for name, T in tabs:
            _for_file(T, False).to_excel(xw, sheet_name=name, index=False)
    return out
