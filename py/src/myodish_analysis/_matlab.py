"""MATLAB-compatible numerical helpers.

The MATLAB version of the MyoDishAnalysis is the reference. These functions reproduce the semantics of the
MATLAB functions it uses (rounding, moving windows with 'Endpoints','shrink' and 'omitnan', islocalmax with
prominence, std of a single value, datenum), so that the Python port returns the same results.

TS 2026-10-06
"""
from __future__ import annotations

import datetime as _dt
import math

import numpy as np

__all__ = [
    "Struct", "mround", "round_digits", "movsum", "movmean", "movmedian", "islocalmax", "nanstd", "nanmean", "nanmedian", "gradient",
    "datenum", "datenum_to_datetime", "datetime_to_datenum", "mode", "linspace", "colon",
]


class Struct(dict):
    """dict with attribute access (stands in for a MATLAB struct). copy() is shallow, as dict.copy()."""

    def __getattr__(self, name):
        try:
            return self[name]
        except KeyError as e:
            raise AttributeError(name) from e

    def __setattr__(self, name, value):
        self[name] = value

    def __delattr__(self, name):
        try:
            del self[name]
        except KeyError as e:
            raise AttributeError(name) from e

    def copy(self):
        return Struct(self)

    def __repr__(self):
        items = []
        for k, v in self.items():
            if isinstance(v, np.ndarray):
                items.append(f"{k}=<{v.dtype} {v.shape}>")
            elif isinstance(v, (list, tuple)) and len(v) > 6:
                items.append(f"{k}=<{type(v).__name__} of {len(v)}>")
            else:
                r = repr(v)
                items.append(f"{k}={r if len(r) < 60 else r[:57] + '...'}")
        return "Struct(" + ", ".join(items) + ")"


def mround(x):
    """MATLAB round: halves away from zero (numpy rounds halves to even). Scalars return int."""
    if np.isscalar(x):
        if isinstance(x, (int, np.integer)):
            return int(x)
        x = float(x)
        if not math.isfinite(x):
            return x
        r = math.trunc(x)
        if abs(x - r) >= 0.5:
            r += 1 if x > 0 else -1
        return int(r)
    x = np.asarray(x, dtype=float)
    r = np.trunc(x)
    return r + np.sign(x) * (np.abs(x - r) >= 0.5)


def round_digits(x, n):
    """MATLAB round(x, n) (n digits after the decimal point, n < 0: before). MATLAB rounds y = x * 10^n (x / 10^-n)
    half away from zero, and also away from zero if y is exactly one ulp short of a half (determined with MATLAB
    R2026a: round(0.60449999999999993, 3) = 0.605, round(0.60449999999999982, 3) = 0.604, round(1.005, 2) = 1.01);
    n = 0: round(x)."""
    n = int(n)
    if n == 0:
        return mround(x)
    s = 10.0 ** abs(n)
    y = np.asarray(x, dtype=float) * s if n > 0 else np.asarray(x, dtype=float) / s
    a = np.abs(y)
    f = np.floor(a)
    a = np.where((a - f < 0.5) & (np.nextafter(a, np.inf) == f + 0.5), f + 0.5, a)
    r = np.copysign(f + (a - f >= 0.5), y)
    out = r / s if n > 0 else r * s
    return float(out) if np.ndim(out) == 0 else out


def _window_bounds(k):
    """backward and forward extent of a moving window of length k (MATLAB: even k is centred about the current and
    the previous element)."""
    k = int(k)
    if k % 2 == 1:
        return (k - 1) // 2, (k - 1) // 2
    return k // 2, k // 2 - 1


def movsum(x, k, chunk_outputs=None):
    """movsum(x, k) of MATLAB ('Endpoints','shrink'), bit-identical.

    MATLAB computes moving sums block-wise (van Herk / Gil-Werman): the outputs are processed in chunks of
    C = max(64, 2k) samples; within a chunk the data from the first window start are divided into blocks of k samples,
    with prefix sums (left to right) and suffix sums (right to left) per block; a window is the prefix sum up to its
    end if it starts at a block start, else suffix(start) + prefix(end). (Determined by comparison with MATLAB R2026a
    for k = 4 ... 200, NaN-free and with NaN, row and column vectors.) NaN propagates as in MATLAB.
    """
    x = np.asarray(x, dtype=float).ravel()
    n = x.size
    if n == 0:
        return x.copy()
    k = int(k)
    if k <= 1:
        return x.copy()
    kb, kf = _window_bounds(k)
    C = max(64, 2 * k)
    nC = -(-n // C)
    out = np.empty(n)
    step = max(1, (1 << 20) // C)  # chunks per batch (memory)
    for c0 in range(0, nC, step):
        c = np.arange(c0, min(nC, c0 + step))
        s0 = np.maximum(0, c * C - kb)
        e0 = np.minimum(n - 1, np.minimum(n - 1, c * C + C - 1) + kf)
        L = int(np.max(e0 - s0 + 1))
        nB = -(-L // k)
        Lp = nB * k
        idx = s0[:, None] + np.arange(Lp)[None, :]
        seg = np.where(idx <= e0[:, None], x[np.minimum(idx, n - 1)], 0.0)
        blocks = seg.reshape(c.size, nB, k)
        P = np.cumsum(blocks, axis=2).reshape(c.size, Lp)
        S = np.cumsum(blocks[:, :, ::-1], axis=2)[:, :, ::-1].reshape(c.size, Lp)
        i = np.arange(c[0] * C, min(n, (c[-1] + 1) * C))
        ci = i // C - c0
        a = np.maximum(0, i - kb) - s0[ci]
        b = np.minimum(n - 1, i + kf) - s0[ci]
        atStart = (a % k) == 0
        same = (a // k) == (b // k)
        out[i] = np.where(atStart, P[ci, b], np.where(same, S[ci, a], S[ci, a] + P[ci, b]))
    return out


def movmean(x, k, omitnan=True):
    """movmean(x, k[, 'omitnan']) with 'Endpoints','shrink' (default of MATLAB); bit-identical (see movsum):
    'omitnan': movsum of the values (NaN = 0) / movsum of the number of values."""
    x = np.asarray(x, dtype=float).ravel()
    if x.size == 0:
        return x.copy()
    nan = np.isnan(x)
    if omitnan:
        s = movsum(np.where(nan, 0.0, x), k)
        cnt = movsum((~nan).astype(float), k)
    else:
        s = movsum(x, k)
        cnt = movsum(np.ones(x.size), k)
    with np.errstate(invalid="ignore", divide="ignore"):
        return np.where(cnt > 0, s / cnt, np.nan)


def _midpoint(lo, hi):
    """midpoint of the two central values as computed by MATLAB movmedian (bit-identical): same sign: the value closer
    to zero + half the difference; different signs: (lo + hi) / 2. (MATLAB median() uses (lo + hi) / 2.)"""
    with np.errstate(invalid="ignore"):
        return np.where(lo >= 0, lo + (hi - lo) / 2, np.where(hi <= 0, hi + (lo - hi) / 2, (lo + hi) / 2))


def movmedian(x, k, omitnan=True, chunk=500_000):
    """movmedian(x, k, 'omitnan', 'Endpoints', 'shrink'), bit-identical to MATLAB (see _midpoint). Only 'omitnan'
    is implemented (the MyoDish tool uses nothing else)."""
    if not omitnan:
        raise NotImplementedError("movmedian: only 'omitnan' is implemented")
    x = np.asarray(x, dtype=float).ravel()
    n = x.size
    if n == 0:
        return x.copy()
    k = int(k)
    if k <= 1:
        return x.copy()
    kb, kf = _window_bounds(k)
    out = np.empty(n)
    for a in range(0, n, chunk):
        b = min(n, a + chunk)
        lo_i = max(0, a - kb)
        hi_i = min(n, b + kf)
        lead = kb - (a - lo_i)
        trail = kf - (hi_i - b)
        xp = np.concatenate([np.full(lead, np.nan), x[lo_i:hi_i], np.full(trail, np.nan)])
        W = np.sort(np.lib.stride_tricks.sliding_window_view(xp, kb + kf + 1), axis=1)  # NaN at the end
        m = np.sum(~np.isnan(W), axis=1)
        r = np.arange(W.shape[0])
        mi = np.maximum(m, 1)
        lo = W[r, (mi - 1) // 2]
        hi = W[r, mi // 2]
        res = np.where(mi % 2 == 1, hi, _midpoint(lo, hi))
        res[m == 0] = np.nan
        out[a:b] = res
    return out


def islocalmax(x, prominence=True):
    """[TF, P] = islocalmax(x) of MATLAB (default options: FlatSelection 'center').

    A local maximum is a sample (or a flat run of equal samples) that is larger than its neighbours; the first and
    the last sample are not local maxima. For flat runs the centre sample is returned (index s + floor((L-1)/2)).
    P: prominence of every local maximum (0 elsewhere; all samples of a flat maximum): the peak value minus the
    larger of the two minima between the peak and the nearest higher sample (or the end of the data) on either side.
    Returns (TF, P) as numpy arrays (bool, float).
    """
    x = np.asarray(x, dtype=float).ravel()
    n = x.size
    TF = np.zeros(n, bool)
    P = np.zeros(n)
    if n < 3:
        return TF, P
    # runs of equal values (NaN breaks runs and is never a maximum)
    neq = np.ones(n, bool)
    neq[1:] = ~(x[1:] == x[:-1])
    starts = np.flatnonzero(neq)
    ends = np.r_[starts[1:] - 1, n - 1]
    v = x[starts]
    nr = v.size
    if nr < 3:
        return TF, P
    left = np.r_[np.nan, v[:-1]]
    right = np.r_[v[1:], np.nan]
    ismax = (v > left) & (v > right)
    ismax[0] = False
    ismax[-1] = False
    ismax &= ~np.isnan(v)
    rk = np.flatnonzero(ismax)
    if rk.size == 0:
        return TF, P
    idx = starts[rk] + (ends[rk] - starts[rk]) // 2
    TF[idx] = True
    if prominence:  # MATLAB: every sample of a flat maximum carries its prominence
        pr = _prominence_runs(v, rk)
        L = ends[rk] - starts[rk] + 1
        P[np.repeat(starts[rk], L) + (np.arange(L.sum()) - np.repeat(np.cumsum(L) - L, L))] = np.repeat(pr, L)
    return TF, P


def _prominence_runs(v, rk):
    """prominence of the run maxima rk of the run-compressed signal v (no two neighbours are equal).

    Left base: minimum of v between the nearest run to the left with a value > peak (exclusive) and the peak; or the
    minimum from the start if there is none. Same on the right. prominence = peak - max(left base, right base).
    Computed with scipy.signal.peak_prominences when available (identical definition for a signal without plateaus:
    peaks of the same height are passed, as in MATLAB).
    """
    vv = np.where(np.isnan(v), -np.inf, v)
    try:
        from scipy.signal import peak_prominences
        prom, _, _ = peak_prominences(vv, rk)
        return prom
    except Exception:  # pragma: no cover - fallback without scipy
        out = np.empty(rk.size)
        for q, i in enumerate(rk):
            p = vv[i]
            j = i - 1
            lmin = p
            while j >= 0 and vv[j] <= p:
                lmin = min(lmin, vv[j])
                j -= 1
            j = i + 1
            rmin = p
            while j < vv.size and vv[j] <= p:
                rmin = min(rmin, vv[j])
                j += 1
            out[q] = p - max(lmin, rmin)
        return out


def nanmean(x, axis=None):
    """mean(x, 'omitnan') (no values: NaN)."""
    x = np.asarray(x, dtype=float)
    cnt = np.sum(~np.isnan(x), axis=axis)
    s = np.nansum(x, axis=axis)
    if np.ndim(cnt) == 0:
        return float(s / cnt) if cnt else np.nan
    with np.errstate(all="ignore"):
        return np.where(cnt > 0, s / np.maximum(cnt, 1), np.nan)


def nanmedian(x, axis=None):
    x = np.asarray(x, dtype=float)
    if x.size == 0:
        return np.nan
    import warnings
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)
        return np.nanmedian(x, axis=axis)


def nanstd(x, axis=None):
    """std(x, 'omitnan') (normalized by n - 1; one value: 0; none: NaN)."""
    x = np.asarray(x, dtype=float)
    if axis is None:
        v = x[~np.isnan(x)]
        if v.size == 0:
            return np.nan
        if v.size == 1:
            return 0.0
        return float(np.std(v, ddof=1))
    cnt = np.sum(~np.isnan(x), axis=axis)
    with np.errstate(all="ignore"):
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", RuntimeWarning)
            s = np.nanstd(x, axis=axis, ddof=1)
    s = np.where(cnt == 1, 0.0, s)
    s = np.where(cnt == 0, np.nan, s)
    return s


def gradient(f):
    """gradient(f) of a vector (spacing 1): central differences, one-sided at the ends; scalar: 0."""
    f = np.asarray(f, dtype=float).ravel()
    if f.size < 2:
        return np.zeros_like(f)
    return np.gradient(f)


def mode(x):
    """most frequent value (smallest of equally frequent ones), as MATLAB mode."""
    x = np.asarray(x).ravel()
    if x.size == 0:
        return np.nan
    u, c = np.unique(x, return_counts=True)
    return u[np.argmax(c)]


def linspace(a, b, n):
    """MATLAB linspace(a, b, n): a + (k * (b - a)) / (n - 1), first and last value exact."""
    n = int(n)
    if n <= 1:
        return np.array([float(b)])
    k = np.arange(n, dtype=float)
    y = a + (k * (b - a)) / (n - 1)
    y[0] = a
    y[-1] = b
    return y


def colon(a, d, b):
    """MATLAB a:d:b (bit-identical with MATLAB R2026a, checked e.g. for 0:0.1:0.3, 0.1:0.1:0.5, 0.6:0.002:0.62):
    n intervals as in MathWorks' colonop.m (round, minus 1 if a + n*d overshoots b by more than 2 eps); end point
    c = a + n*d, replaced by b if c is within that tolerance; first half (incl. the middle) a + k*d, second half
    c - (n-k)*d."""
    a = float(a); d = float(d); b = float(b)
    if not (math.isfinite(a) and math.isfinite(d) and math.isfinite(b)):
        return np.array([math.nan])
    if d == 0 or (a < b and d < 0) or (b < a and d > 0):
        return np.zeros(0)
    tol = 2.0 * np.finfo(float).eps * max(abs(a), abs(b))
    sig = 1.0 if d > 0 else -1.0
    if a == math.floor(a) and d == 1:
        n = int(math.floor(b) - a)
    elif a == math.floor(a) and d == math.floor(d):
        q = math.floor(a / d)
        n = int(math.floor((b - (a - q * d)) / d) - q)
    else:
        n = int(mround((b - a) / d))
        if sig * (a + n * d - b) > tol:
            n -= 1
    c = a + n * d
    if sig * (c - b) > -tol:
        c = b
    k = np.arange(n + 1, dtype=float)
    h = n // 2
    v = np.empty(n + 1)
    v[:h + 1] = a + k[:h + 1] * d
    v[h + 1:] = c - (n - k[h + 1:]) * d
    return v


# ----------------------------------------------------------------------------------------------- date numbers
_DATENUM_OFFSET = 366  # datenum(1,1,1) = 367; date.toordinal(1,1,1) = 1


def datenum(y, mo, d, h=0, mi=0, s=0.0):
    """MATLAB datenum(y, mo, d, h, mi, s) (days since year 0); s may contain fractions."""
    base = _dt.date(int(y), int(mo), int(d)).toordinal() + _DATENUM_OFFSET
    return base + (h * 3600.0 + mi * 60.0 + s) / 86400.0


def datetime_to_datenum(t):
    if t is None:
        return np.nan
    day = t.toordinal() + _DATENUM_OFFSET
    frac = (t.hour * 3600 + t.minute * 60 + t.second + t.microsecond / 1e6) / 86400.0
    return day + frac


def datenum_to_datetime(dn):
    """datenum --> datetime (millisecond resolution); NaN --> None."""
    if dn is None or (isinstance(dn, float) and math.isnan(dn)):
        return None
    dn = float(dn)
    day = int(math.floor(dn))
    frac = dn - day
    base = _dt.datetime.fromordinal(day - _DATENUM_OFFSET)
    us = round(frac * 86400e6 / 1000) * 1000  # ms
    return base + _dt.timedelta(microseconds=us)
