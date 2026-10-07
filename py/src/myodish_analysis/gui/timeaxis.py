"""Time axis labels (h:mm:ss / m:ss) and number formats of the GUI (fmtClock, timeTicks, fmtNum, fmtDuration of
MyoDishAnalysisGUI.m) and a pyqtgraph axis that uses them.

TS 2026-10-06
"""
from __future__ import annotations

import math

import numpy as np
import pyqtgraph as pg

from .._matlab import mround

STEPS = [0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 10800, 21600, 43200]


def fmt_clock(t, hrs, with_sec=True, dec=0):
    """seconds --> 'h:mm:ss' / 'h:mm' (hrs) or 'm:ss'; dec = decimals of the seconds."""
    neg = t < 0
    t = mround(abs(t) * 10 ** dec) / 10 ** dec
    h = math.floor(t / 3600)
    m = math.floor((t - 3600 * h) / 60)
    sec = t - 3600 * h - 60 * m
    if dec > 0:
        ss = f"{sec:0{3 + dec}.{dec}f}"
    else:
        ss = f"{int(mround(sec)):02d}"
    if hrs:
        s = f"{h}:{m:02d}:{ss}" if with_sec else f"{h}:{m:02d}"
    else:
        s = f"{math.floor(t / 60)}:{ss}"
    return "-" + s if neg else s


def time_ticks(xl, tmax):
    """tick positions (s), labels and unit for a time axis in seconds (about 4-10 ticks)."""
    span = xl[1] - xl[0]
    st = STEPS[-1]
    for s in STEPS:
        if span / s <= 10:
            st = s
            break
    ticks = np.arange(math.ceil(xl[0] / st), math.floor(xl[1] / st) + 1) * st
    hrs = max(abs(tmax), max(abs(xl[0]), abs(xl[1]))) >= 3600
    with_sec = st < 60 or not hrs
    dec = 2 if st < 0.1 else (1 if st < 1 else 0)
    labels = [fmt_clock(t, hrs, with_sec, dec) for t in ticks]
    unit = "m:ss" if not hrs else ("h:mm:ss" if with_sec else "h:mm")
    return ticks, labels, unit


def nav_step(xl, key, ext, lim, min_span):
    """time axis after an arrow key ('left', 'right', 'up', 'down'): left / right = move by half the span, with ext
    (shift) = extend by half the span on that side; up / down = zoom in / out around the centre (span / 2, x 2);
    limited to lim and >= min_span (navStep of MyoDishAnalysisGUI.m)."""
    a, b = float(xl[0]), float(xl[1])
    w = b - a
    c = (a + b) / 2
    if key == "left":
        xn = [a - 0.5 * w, b] if ext else [a - 0.5 * w, b - 0.5 * w]
    elif key == "right":
        xn = [a, b + 0.5 * w] if ext else [a + 0.5 * w, b + 0.5 * w]
    elif key == "up":
        xn = [c - 0.25 * w, c + 0.25 * w]
    else:
        xn = [c - w, c + w]
    span = min(max(xn[1] - xn[0], min_span), lim[1] - lim[0])
    if ext:
        return [max(xn[0], lim[0]), min(xn[1], lim[1])]
    a = min(max((xn[0] + xn[1]) / 2 - span / 2, lim[0]), lim[1] - span)
    return [a, a + span]


def fmt_num(x, digits):
    """compact number for the summary table: integers above 1000, otherwise significant digits."""
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return "NaN"
    if abs(x) >= 1000:
        return f"{x:.0f}"
    return f"{x:.{digits}g}"


def fmt_duration(sec):
    if sec < 120:
        return f"{sec:.1f} s"
    if sec < 7200:
        return f"{sec / 60:.1f} min"
    return f"{sec / 3600:.2f} h"


class TimeAxisItem(pg.AxisItem):
    """bottom axis in h:mm:ss / m:ss. t0: subtracted for the labels (time relative to the window start); tmax: decides
    between h:mm and m:ss (as in the MATLAB GUI); clock: datetime of t = 0 for clock-time labels (dd.mm. HH:MM)."""

    def __init__(self, *a, **k):
        super().__init__(*a, orientation="bottom", **k)
        self.t0 = 0.0
        self.tmax = 0.0
        self.clock = None
        self.unit = "m:ss"
        self.show_labels = True
        self._fmt = (False, True, 0)

    def tickValues(self, minVal, maxVal, size):
        if not math.isfinite(minVal) or not math.isfinite(maxVal) or maxVal <= minVal:
            return []
        xl = (minVal - self.t0, maxVal - self.t0)
        span = xl[1] - xl[0]
        st = STEPS[-1]
        for s_ in STEPS:
            if span / s_ <= 10:
                st = s_
                break
        ticks = np.arange(math.ceil(xl[0] / st), math.floor(xl[1] / st) + 1) * st
        hrs = max(abs(self.tmax), max(abs(xl[0]), abs(xl[1]))) >= 3600
        with_sec = st < 60 or not hrs
        dec = 2 if st < 0.1 else (1 if st < 1 else 0)
        self._fmt = (hrs, with_sec, dec)
        self.unit = "m:ss" if not hrs else ("h:mm:ss" if with_sec else "h:mm")
        return [(st, list(ticks + self.t0))]

    def tickStrings(self, values, scale, spacing):
        if not self.show_labels:
            return [""] * len(values)
        if self.clock is not None:
            import datetime as _dt
            return [(self.clock + _dt.timedelta(seconds=float(v))).strftime("%d.%m. %H:%M") for v in values]
        hrs, with_sec, dec = self._fmt
        return [fmt_clock(v - self.t0, hrs, with_sec, dec) for v in values]
