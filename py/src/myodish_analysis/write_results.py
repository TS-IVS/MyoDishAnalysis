"""Write contraction table, summary and analysis info to Excel (.xlsx) or text (.csv). Port of mda_writeResults.m.

    write_results('results.xlsx', contractions, summary, info)
        sheets: contractions, summary, parameters (definitions), info (file facts and options), labels,
        rockerFilter (option rockerFilter: result per channel and time range), protocols (option protocol),
        protocolResults (characteristic values per protocol and channel)
    write_results('results.csv', ...)
        results_contractions.csv, results_summary.csv, results_parameters.csv, results_info.csv (+ labels,
        rockerFilter)

Existing sheets of the same name are overwritten.

TS 2026-10-06 (port of mda_writeResults.m, TS 2026-10-05)
"""
from __future__ import annotations

import datetime as _dt
import math
import os

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
    a = np.asarray(v)
    if a.size == 0:
        return ""
    if a.size == 1:
        return num2str(a.ravel()[0])
    return mat2str(a)


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
    keys = ["file", "samplingRate_Hz", "samplingRateSource", "nChannelsInFile", "fileLength_s", "recordingStart",
            "analysisDate", "software", "notes"]
    startStr = ""
    rs = info.get("recordingStart", math.nan)
    if rs is not None and not (isinstance(rs, float) and math.isnan(rs)):
        startStr = datenum_to_datetime(rs).strftime("%Y-%m-%d %H:%M:%S")
    analysisDate = info.get("analysisDate", _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    vals = [info["file"], num2str(info["samplingRate"]), info["samplingRateSource"], num2str(info["nChannelsInFile"]),
            f"{info['totalSeconds']:.3f}", startStr, analysisDate,
            f"MyoDishAnalysis (Python) {__version__} (T. Seidel, FAU Erlangen-Nuernberg)",
            " | ".join(info.get("notes", []))]
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
    if e.lower() == ".csv":
        out = []
        for name, T in tabs:
            f = os.path.join(p, f"{n}_{name}.csv")
            _for_file(T, True).to_csv(f, index=False)
            out.append(f)
        return out
    mode = "a" if os.path.isfile(output_file) else "w"
    kw = dict(if_sheet_exists="replace") if mode == "a" else {}
    with pd.ExcelWriter(output_file, engine="openpyxl", mode=mode, **kw) as xw:
        for name, T in tabs:
            _for_file(T, False).to_excel(xw, sheet_name=name, index=False)
    return [output_file]
