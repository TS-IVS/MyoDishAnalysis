"""Per-channel labels (metadata) as a table with one row per channel. Port of mda_labels.m.

    L = labels(None, channels)            empty labels for the channels
    L = labels(d, channels)               d = dict, e.g.
          d['species'] = 'human'                          same value for all channels
          d['sliceID'] = ['S1', 'S2', 'S3']               one value per channel (in the order of 'channels')
          d['channel'] = [1, 6, 8]: the per-channel values refer to these channels (other channels: empty labels)
        or a list of dicts with one element per channel
    L = labels(df, channels)              DataFrame (with a column 'channel', or one row per channel in order)
    L = labels('labels.csv', channels)    file written by the GUI (csv) or an Excel file (sheet 'labels' of a
                                          result file, otherwise the first sheet)

Standard labels (always present, in this order): setupID, sliceID, species, sampleID, sampleGroup, sliceGroup,
tissue, treatment (text), concentration (number), concentrationUnit (text), daysInCulture (number), cultureStart
(text, e.g. '1999-12-24 14:30' or '24.12.1999 14:30'), comment, analyst (text). Further fields are kept.

TS 2026-10-06 (port of mda_labels.m, TS 2026-10-04)
"""
from __future__ import annotations

import datetime as _dt
import math
import os
import warnings

import numpy as np
import pandas as pd

from .parameters import LABEL_NAMES

NUMERIC_LABELS = ("concentration", "daysInCulture")


def _is_num(x):
    return isinstance(x, (int, float, np.integer, np.floating, bool, np.bool_)) and not isinstance(x, str)


def labels(meta, channels):
    channels = [int(c) for c in np.atleast_1d(channels).ravel()]
    nCh = len(channels)
    L = pd.DataFrame({"channel": np.array(channels, dtype=float)})
    for nm in LABEL_NAMES:
        L[nm] = np.full(nCh, np.nan) if nm in NUMERIC_LABELS else [""] * nCh
    if meta is None or (isinstance(meta, (dict, list)) and len(meta) == 0):
        return L
    if isinstance(meta, (str, os.PathLike)):
        meta = _read_label_file(str(meta))
    if isinstance(meta, dict) and meta.get("channel") is not None and np.size(meta["channel"]) > 0:
        m2 = {k: v for k, v in meta.items() if k != "channel"}
        meta = labels(m2, meta["channel"])
    if isinstance(meta, pd.DataFrame):
        if "channel" in meta.columns:
            chm = list(meta["channel"].to_numpy(dtype=float))
            names = [c for c in meta.columns if c != "channel"]
            recs = []
            for c in channels:
                d = {}
                for nm in names:
                    if float(c) in chm:
                        v = meta[nm].iloc[chm.index(float(c))]
                        if isinstance(v, float) and math.isnan(v) and nm not in NUMERIC_LABELS \
                                and not pd.api.types.is_numeric_dtype(meta[nm]):
                            v = ""
                    else:
                        v = None
                    d[nm] = v
                recs.append(d)
            meta = recs
        elif len(meta) == nCh:
            meta = meta.to_dict("records")
        else:
            raise ValueError(f"labels: the table needs a column 'channel' or one row per channel ({nCh}).")
    if isinstance(meta, list):
        if len(meta) != nCh and len(meta) != 1:
            raise ValueError(f"labels: list with {len(meta)} elements, but {nCh} channels.")
        names = []
        for d in meta:
            for k in d:
                if k not in names:
                    names.append(k)
        per = [[d.get(nm) for d in meta] for nm in names] if len(meta) == nCh else None
        if per is None:
            meta = meta[0]
        else:
            for nm, vals in zip(names, per):
                if nm == "channel":
                    continue
                _set(L, nm, vals)
            return L
    if not isinstance(meta, dict):
        raise ValueError("labels: labels must be a dict, a DataFrame or a file name.")
    for nm, v in meta.items():
        if nm == "channel":
            continue
        if v is None or isinstance(v, (str, _dt.datetime)) or _is_num(v):
            vals = [v] * nCh
        elif isinstance(v, (list, tuple, np.ndarray, pd.Series)) and len(v) == nCh:
            vals = list(v)
        elif isinstance(v, (list, tuple)) and len(v) == 1:
            vals = [v[0]] * nCh
        elif isinstance(v, (list, tuple, np.ndarray)) and len(v) == 0:
            vals = [None] * nCh
        else:
            raise ValueError(f"labels: label '{nm}' needs one value for all channels or one value per channel "
                             f"({nCh}).")
        _set(L, nm, vals)
    return L


def _set(L, nm, vals):
    if nm in NUMERIC_LABELS or (nm not in LABEL_NAMES and all(_is_num(x) for x in vals)):
        num = np.full(len(vals), np.nan)
        for i, x in enumerate(vals):
            if isinstance(x, str):
                try:
                    x = float(x.replace(",", "."))
                except ValueError:
                    x = math.nan
            if x is not None and _is_num(x):
                num[i] = float(x)
        L[nm] = num
    else:
        L[nm] = [_to_text(x) for x in vals]


def _to_text(x):
    if x is None:
        return ""
    if isinstance(x, str):
        return x
    if isinstance(x, (_dt.datetime, pd.Timestamp)):
        return x.strftime("%Y-%m-%d %H:%M")
    if _is_num(x):
        if isinstance(x, float) and math.isnan(x):
            return ""
        return f"{x:g}" if isinstance(x, (float, np.floating)) else str(x)
    return ""


def _read_label_file(file):
    if not os.path.isfile(file):
        raise FileNotFoundError(f"labels: file not found: {file}")
    ext = os.path.splitext(file)[1].lower()
    conv = {"channel": float, "concentration": float, "daysInCulture": float}
    if ext in (".xlsx", ".xls"):
        xl = pd.ExcelFile(file)
        sheet = "labels" if "labels" in xl.sheet_names else xl.sheet_names[0]
        T = pd.read_excel(file, sheet_name=sheet, dtype=str)
    else:
        T = pd.read_csv(file, dtype=str, keep_default_na=False)
    for c in T.columns:
        if c in conv:
            T[c] = pd.to_numeric(T[c].replace("", np.nan), errors="coerce")
        else:
            T[c] = T[c].fillna("").astype(str)
    return T
