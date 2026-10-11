# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Add the per-channel labels as columns (after 'channel') to a contraction or summary table. Port of mda_addLabels.m.

    T = add_labels(T, L)          L = label table from labels(); rows are matched by T.channel
    T = add_labels(T, L, when)    when = datetime per row of T (clock time of the contraction, or of the middle of the
                                  range for summary rows): if cultureStart is given for a channel, daysInCulture =
                                  days since cultureStart (fractional), otherwise the label value

TS 2026-10-06 (port of mda_addLabels.m, TS 2026-10-04)
"""
from __future__ import annotations

import datetime as _dt
import math
import warnings

import numpy as np
import pandas as pd


def add_labels(T, L, when=None):
    T = T.copy()
    h = len(T)
    chT = T["channel"].to_numpy(dtype=float)
    chL = list(L["channel"].to_numpy(dtype=float))
    loc = np.array([chL.index(c) if c in chL else -1 for c in chT], dtype=int)
    found = loc >= 0
    names = [c for c in L.columns if c != "channel"]
    for nm in names:
        if nm in T.columns:
            del T[nm]  # labels added before: replace
    pos = list(T.columns).index("channel") + 1
    newcols = {}
    for nm in names:
        col = L[nm]
        if not (pd.api.types.is_numeric_dtype(col) or pd.api.types.is_bool_dtype(col)):
            v = np.array([""] * h, dtype=object)
            v[found] = col.to_numpy()[loc[found]]
        else:
            v = np.full(h, np.nan)
            v[found] = col.to_numpy(dtype=float)[loc[found]]
        if nm == "daysInCulture" and when is not None and "cultureStart" in names:
            startTxt = np.array([""] * h, dtype=object)
            startTxt[found] = L["cultureStart"].to_numpy()[loc[found]]
            d = _days_since(startTxt, when)
            v = v.astype(float)
            v[~np.isnan(d)] = d[~np.isnan(d)]
        newcols[nm] = v
    left = T.iloc[:, :pos]
    right = T.iloc[:, pos:]
    mid = pd.DataFrame(newcols, index=T.index)
    out = pd.concat([left, mid, right], axis=1)
    out.attrs = dict(T.attrs)
    return out


def _days_since(startTxt, when):
    when = list(when)
    d = np.full(len(startTxt), np.nan)
    cache = {}
    for i, s in enumerate(startTxt):
        if s not in cache:
            cache[s] = _parse_date(s)
        t0 = cache[s]
        w = when[i]
        if t0 is None or w is None or (isinstance(w, float) and math.isnan(w)) or pd.isna(w):
            continue
        d[i] = (pd.Timestamp(w) - pd.Timestamp(t0)).total_seconds() / 86400
    return d


_FMTS = ["%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d", "%d.%m.%Y %H:%M:%S", "%d.%m.%Y %H:%M", "%d.%m.%Y",
         "%Y/%m/%d %H:%M", "%Y/%m/%d"]


def _parse_date(s):
    s = (s or "").strip()
    if not s:
        return None
    for f in _FMTS:
        try:
            return _dt.datetime.strptime(s, f)
        except ValueError:
            pass
    warnings.warn(f"cultureStart '{s}' not understood (use e.g. 1999-12-24 14:30).")
    return None
