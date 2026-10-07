"""Helpers to compare Python results with MATLAB results saved by the scripts in tests/matlab (TS 2026-10-06)."""
from __future__ import annotations

import math

import numpy as np
import pandas as pd


def loadmat(file):
    from scipy.io import loadmat as _lm
    return _lm(file, squeeze_me=True, struct_as_record=False, chars_as_strings=True)


def table_from_struct(st):
    """MATLAB table2struct(T, 'ToScalar', true) --> DataFrame."""
    d = {}
    for k in st._fieldnames:
        v = getattr(st, k)
        if isinstance(v, np.ndarray) and v.size == 0 and v.dtype.kind in "UOS":  # {''} of a one-row table
            v = [""]
        elif isinstance(v, np.ndarray) and v.dtype == object:
            v = [str(x) if not isinstance(x, np.ndarray) else "" for x in v.ravel()]
        elif isinstance(v, str):
            v = [v]
        elif np.ndim(v) == 0:
            v = [v]
        d[k] = list(np.ravel(v)) if not isinstance(v, list) else v
    n = max(len(v) for v in d.values()) if d else 0
    for k, v in d.items():
        if len(v) != n:
            d[k] = v + [np.nan] * (n - len(v))
    return pd.DataFrame(d)


def compare_tables(M, P, name="", rtol=1e-9, atol=1e-9, cols=None, quiet=False, skip=()):
    """compare two contraction tables (rows must correspond). Returns (ok, report lines)."""
    lines = []
    ok = True
    if len(M) != len(P):
        lines.append(f"{name}: number of rows differs: MATLAB {len(M)}, Python {len(P)}")
        return False, lines
    cols = cols or [c for c in M.columns if c in P.columns and c not in skip]
    missing = [c for c in M.columns if c not in P.columns and c not in skip]
    extra = [c for c in P.columns if c not in M.columns and c not in skip]
    if missing:
        lines.append(f"{name}: columns only in MATLAB: {missing}")
        ok = False
    if extra:
        lines.append(f"{name}: columns only in Python: {extra}")
    worst = []
    for c in cols:
        a = M[c].to_numpy()
        b = P[c].to_numpy()
        if a.dtype == object or b.dtype == object:
            eq = np.array([str(x) == str(y) for x, y in zip(a, b)])
            if not eq.all():
                ok = False
                i = int(np.flatnonzero(~eq)[0])
                lines.append(f"{name}: {c}: {int((~eq).sum())} differences, e.g. row {i}: '{a[i]}' vs '{b[i]}'")
            continue
        a = a.astype(float)
        b = b.astype(float)
        nanA, nanB = np.isnan(a), np.isnan(b)
        if np.any(nanA != nanB):
            ok = False
            i = int(np.flatnonzero(nanA != nanB)[0])
            lines.append(f"{name}: {c}: NaN pattern differs in {int(np.sum(nanA != nanB))} rows, e.g. row {i}: "
                         f"{a[i]} vs {b[i]}")
        v = ~nanA & ~nanB
        if v.any():
            d = np.abs(a[v] - b[v])
            tol = atol + rtol * np.abs(a[v])
            rel = np.max(d / np.maximum(np.abs(a[v]), 1e-300))
            worst.append((c, float(np.max(d)), float(rel)))
            if np.any(d > tol):
                ok = False
                i = int(np.flatnonzero(v)[np.argmax(d - tol)])
                lines.append(f"{name}: {c}: max abs diff {np.max(d):.3g} (rel {rel:.3g}), row {i}: {a[i]!r} vs {b[i]!r}")
    if worst and not quiet:
        w = max(worst, key=lambda x: x[2])
        lines.append(f"{name}: {len(M)} rows, {len(cols)} columns compared; largest relative difference {w[2]:.2e} "
                     f"({w[0]}) -> {'IDENTICAL within tolerance' if ok else 'DIFFERENCES'}")
    return ok, lines
