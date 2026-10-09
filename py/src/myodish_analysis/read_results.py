"""Read a results file of MyoDishAnalysis (settings, analysis windows, contractions) to show it again. Port of
mda_readResults.m.

    R = read_results('results.xlsx')
    R = read_results('results_info.csv')       (or _summary.csv, _contractions.csv(.gz), _thresholds.csv: the other
                                                files of the set are found by their names)

Results of myodish_analysis (output=...), the watcher, the GUI (Export this channel ..., All channels -> file ...,
protocols) and of the MATLAB version. Used by the GUI to open results: mda-gui results.xlsx.

R (dict): mddFile (recording, path at the time of the analysis), version, implementation, createdBy, analysisDate,
options (options() from the rows option_<name> of the info table; options unknown here and a reference beat are left
out, notes), channels (analysed channels: one threshold / zero force per channel in this order; [] if not recorded),
windows (DataFrame, one row per analysis window: channel, range, from, to (contractions reported), windowFrom, windowTo
(data read and analysed), threshold_uN; older results without the thresholds sheet: from the summary, window = range
+- maxBeatWindow + 2 s), summary, contractions, labels, rockerFilter (DataFrames or None), extra (dict of the other
rows of the info table, e.g. loadedWindow_s, epRecording, watcherOptions), info (the info table), notes (list).

TS 2026-10-09
"""
from __future__ import annotations

import math
import os
import re

import numpy as np
import pandas as pd

from .options import NAMES as OPTION_NAMES, _DEFAULTS as OPTION_DEFAULTS, options as make_options

_SUFFIX = re.compile(r"_(info|summary|contractions|thresholds|parameters|labels|rockerFilter|protocols|"
                     r"protocolResults)$")


def parse_numbers(s):
    """numbers of a scalar or of mat2str text ('[1 2;3 4]', 'NaN', 'Inf'); None if s is not numeric. No eval."""
    s = str(s).strip()
    if not s:
        return None
    t = re.sub(r"^\[|\]$", "", s)
    rows = []
    for r in t.split(";"):
        parts = [p for p in r.strip().split() if p]
        if not parts:
            return None
        vals = []
        for p in parts:
            try:
                vals.append(float(p))  # 'NaN', 'Inf', '-Inf' as well
            except ValueError:
                return None
        if rows and len(vals) != len(rows[0]):
            return None
        rows.append(vals)
    a = np.array(rows, dtype=float)
    if a.size == 1:
        return float(a.ravel()[0])
    return a.ravel() if a.shape[0] == 1 else a


def _parse_value(s, default, name):
    """option value from its text in the info table (as written by write_results / mda_writeResults)."""
    s = str(s).strip()
    if not s:
        return default if isinstance(default, str) else None
    x = parse_numbers(s)
    if x is not None:
        v = x
    elif s.lower() in ("true", "false"):
        v = s.lower() == "true"
    else:
        v = s
    if (isinstance(default, bool) or name == "extendedSensorMode") and isinstance(v, float):
        v = v != 0
    return v


def _read_sheet(xl, name):
    if name not in xl.sheet_names:
        return None
    dtype = str if name == "info" else None
    return pd.read_excel(xl, sheet_name=name, dtype=dtype, keep_default_na=name != "info")


def _read_csv(file, info=False):
    if not os.path.isfile(file):
        return None
    if info:
        return pd.read_csv(file, dtype=str, keep_default_na=False)
    return pd.read_csv(file)


def read_results(results_file):
    results_file = str(results_file)
    R = dict(resultsFile=results_file, mddFile="", version="", implementation="", createdBy="", analysisDate="",
             options=make_options(), channels=None, windows=None, summary=None, contractions=None, labels=None,
             rockerFilter=None, extra={}, info=None, notes=[])
    p, nm = os.path.split(results_file)
    n, e = os.path.splitext(nm)
    gz = e.lower() == ".gz"
    if gz:
        n, e = os.path.splitext(n)
    if e.lower() in (".xlsx", ".xls"):
        xl = pd.ExcelFile(results_file)

        def get(name):
            return _read_sheet(xl, name)
    else:
        base = _SUFFIX.sub("", n)

        def get(name):
            f = os.path.join(p, f"{base}_{name}.csv")
            if name == "contractions" and not os.path.isfile(f) and os.path.isfile(f + ".gz"):
                f = f + ".gz"
            return _read_csv(f, info=name == "info")
    I = get("info")
    if I is None or not {"key", "value"} <= set(I.columns):
        raise ValueError(f"read_results: no info table (key, value) found for {results_file}.")
    I = I[["key", "value"]].copy()
    I["key"] = I["key"].astype(str)
    I["value"] = I["value"].fillna("").astype(str).replace({"nan": ""})
    R["info"] = I

    def val(k):
        v = I.loc[I["key"] == k, "value"]
        return str(v.iloc[0]) if len(v) else ""
    R["mddFile"] = val("file")
    R["version"] = val("version")
    R["implementation"] = val("implementation")
    if not R["version"]:  # results written before 2026-10-09: version in 'software'
        sw = val("software")
        m = re.search(r"(\d+\.\d+\.\d+(-?[a-z]+\.?\d*)?)", sw)
        if m:
            R["version"] = m.group(1)
        R["implementation"] = "Python" if "Python" in sw else ("MATLAB" if "MATLAB" in sw else "")
    R["createdBy"] = val("createdBy")
    R["analysisDate"] = val("analysisDate")
    given = {}
    for k, v in zip(I["key"], I["value"]):
        if not k.startswith("option_"):
            continue
        name = k[7:]
        if name not in OPTION_NAMES:
            R["notes"].append(f"option {name} of the results is unknown in this version (ignored)")
            continue
        if name == "referenceBeat":
            if v:
                R["notes"].append(f"{v}: not restored (create it again in the GUI)")
            continue
        given[name] = _parse_value(v, OPTION_DEFAULTS[name], name)
    R["options"] = make_options(given)
    ch = val("channels")
    if ch:
        x = parse_numbers(ch)
        R["channels"] = None if x is None else [int(c) for c in np.atleast_1d(x).ravel()]
    R["summary"] = get("summary")
    R["labels"] = get("labels")
    R["rockerFilter"] = get("rockerFilter")
    R["contractions"] = get("contractions")
    W = get("thresholds")
    cols = ["channel", "range", "from", "to", "windowFrom", "windowTo", "threshold_uN"]
    Sm = R["summary"]
    if W is not None and {"channel", "from", "to", "windowFrom", "windowTo"} <= set(W.columns):
        lbl = [""] * len(W)
        if Sm is not None and {"range", "channel", "from", "to"} <= set(Sm.columns):
            for r in range(len(W)):
                j = np.flatnonzero((Sm["channel"].to_numpy() == W["channel"].iloc[r])
                                   & (Sm["from"].to_numpy(float) <= W["from"].iloc[r] + 1e-6)
                                   & (Sm["to"].to_numpy(float) >= W["to"].iloc[r] - 1e-6))
                if j.size:
                    lbl[r] = str(Sm["range"].iloc[j[0]])
        thr = W["threshold_uN"].to_numpy(float) if "threshold_uN" in W.columns else np.full(len(W), np.nan)
        R["windows"] = pd.DataFrame({"channel": W["channel"].astype(int).to_numpy(), "range": lbl,
                                     "from": W["from"].to_numpy(float), "to": W["to"].to_numpy(float),
                                     "windowFrom": W["windowFrom"].to_numpy(float),
                                     "windowTo": W["windowTo"].to_numpy(float), "threshold_uN": thr})
    elif Sm is not None and {"channel", "from", "to"} <= set(Sm.columns):
        o = R["options"]
        pad = o.maxBeatWindow + 2
        if o.rockerFilter:
            pad = max(pad, 60)
        lbl = [str(x) for x in Sm["range"]] if "range" in Sm.columns else [""] * len(Sm)
        thr = Sm["detectionThreshold"].to_numpy(float) if "detectionThreshold" in Sm.columns else \
            np.full(len(Sm), np.nan)
        f = Sm["from"].to_numpy(float)
        t = Sm["to"].to_numpy(float)
        R["windows"] = pd.DataFrame({"channel": Sm["channel"].astype(int).to_numpy(), "range": lbl, "from": f,
                                     "to": t, "windowFrom": np.maximum(0, f - pad), "windowTo": t + pad,
                                     "threshold_uN": thr})
        R["notes"].append("no analysis windows in the results (older version): data window = range +- maxBeatWindow "
                          "+ 2 s")
    else:
        R["windows"] = pd.DataFrame({c: [] for c in cols})
    skip = {"file", "version", "implementation", "createdBy", "analysisDate", "channels", "notes", "software",
            "samplingRate_Hz", "samplingRateSource", "nChannelsInFile", "fileLength_s", "recordingStart"}
    for k, v in zip(I["key"], I["value"]):
        if k.startswith(("option_", "logOffset_ch", "logCalibration_ch")) or k in skip:
            continue
        R["extra"][k] = v
    nt = val("notes")
    if nt:
        R["notes"].insert(0, "notes of the analysis: " + nt)
    return R


def value_of_channel(x, chans, c):
    """threshold / zero force of channel c from the option value: 'auto' / None = NaN, one value, one per channel."""
    if x is None or isinstance(x, str):
        return math.nan
    a = np.atleast_1d(np.asarray(x, dtype=float)).ravel()
    if a.size == 0:
        return math.nan
    if a.size == 1:
        return float(a[0])
    if chans and c in chans:
        j = chans.index(c)
        if j < a.size:
            return float(a[j])
    return math.nan
