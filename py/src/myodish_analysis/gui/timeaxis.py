# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Time axis labels (h:mm:ss / m:ss) and number formats of the GUI (fmtClock, timeTicks, fmtNum, fmtDuration of
MyoDishAnalysisGUI.m) and a pyqtgraph axis that uses them.

TS 2026-10-06 (days 'd h:mm' from 2 days and labels of a condensed axis: rocker stops side by side, 2026-10-14)
"""
from __future__ import annotations

import math

import numpy as np
import pyqtgraph as pg

from .._matlab import mround

STEPS = [0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 10800, 21600, 43200,
         86400, 172800, 432000, 864000]
DAY = 86400.0


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


def fmt_days(t, st, with_sec=False, dec=0):
    """seconds --> 'n d' (whole days, steps of days) or 'n d h:mm(:ss)' (time axes from 2 days, 2026-10-14)"""
    if t is None or not math.isfinite(t):
        return ""
    neg = t < 0
    t = abs(t)
    d = math.floor(t / DAY + 1e-9)
    r = max(0.0, t - DAY * d)
    s = f"{d} d" if st >= DAY and r < 0.5 else f"{d} d {fmt_clock(r, True, with_sec, dec)}"
    return "-" + s if neg else s


def _step(span):
    st = STEPS[-1]
    for s_ in STEPS:
        if span / s_ <= 10:
            st = s_
            break
    return st


def tick_format(st, tmax, xl):
    """(hrs, days, with_sec, dec, unit) of a time axis with tick step st"""
    m = max(abs(tmax), abs(xl[0]), abs(xl[1]))
    hrs = m >= 3600
    days = m >= 2 * DAY
    with_sec = st < 60 or not hrs
    dec = 2 if st < 0.1 else (1 if st < 1 else 0)
    if days:
        unit = "days" if st >= DAY else ("d h:mm:ss" if with_sec else "d h:mm")
    else:
        unit = "m:ss" if not hrs else ("h:mm:ss" if with_sec else "h:mm")
    return hrs, days, with_sec, dec, unit


def fmt_tick(t, fmt, st):
    hrs, days, with_sec, dec, _ = fmt
    if t is None or not math.isfinite(t):
        return ""
    return fmt_days(t, st, with_sec, dec) if days else fmt_clock(t, hrs, with_sec, dec)


def time_ticks(xl, tmax):
    """tick positions (s), labels and unit for a time axis in seconds (about 4-10 ticks; 'd h:mm' from 2 days)."""
    st = _step(xl[1] - xl[0])
    ticks = np.arange(math.ceil(xl[0] / st), math.floor(xl[1] / st) + 1) * st
    fmt = tick_format(st, tmax, xl)
    labels = [fmt_tick(t, fmt, st) for t in ticks]
    return ticks, labels, fmt[4]


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
    """bottom axis in h:mm:ss / m:ss ('d h:mm' from 2 days). t0: subtracted for the labels (time relative to the window
    start); tmax: decides between h:mm and m:ss (as in the MATLAB GUI); clock: datetime of t = 0 for clock-time labels
    (dd.mm. HH:MM); map: function axis time -> time of the labels (rocker stops side by side: condensed axis, labels =
    time in the file; NaN = no label)."""

    def __init__(self, *a, **k):
        super().__init__(*a, orientation="bottom", **k)
        self.t0 = 0.0
        self.tmax = 0.0
        self.clock = None
        self.map = None
        self.unit = "m:ss"
        self.show_labels = True
        self._fmt = (False, False, True, 0, "m:ss")
        self._st = 1.0

    def tickValues(self, minVal, maxVal, size):
        if not math.isfinite(minVal) or not math.isfinite(maxVal) or maxVal <= minVal:
            return []
        xl = (minVal - self.t0, maxVal - self.t0)
        st = _step(xl[1] - xl[0])
        ticks = np.arange(math.ceil(xl[0] / st), math.floor(xl[1] / st) + 1) * st
        xr = xl
        if self.map is not None:  # format from the times of the labels
            v = np.asarray(self.map(ticks + self.t0), float) - self.t0
            v = v[np.isfinite(v)]
            if v.size:
                xr = (float(v.min()), float(v.max()))
        self._fmt = tick_format(st, self.tmax, xr)
        self._st = st
        self.unit = self._fmt[4]
        return [(st, list(ticks + self.t0))]

    def tickStrings(self, values, scale, spacing):
        if not self.show_labels:
            return [""] * len(values)
        if self.clock is not None:
            import datetime as _dt
            return [(self.clock + _dt.timedelta(seconds=float(v))).strftime("%d.%m. %H:%M") for v in values]
        if self.map is not None:
            values = list(np.asarray(self.map(np.asarray(values, float)), float))
        return [fmt_tick(v - self.t0, self._fmt, self._st) for v in values]
