# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Zero force of a channel (sensor signal without load, uN) at the times t. Port of mda_zeroForce.m.

    z, src, zeroT, zeroV = zero_force(S, channel, zero_user, t)

S          file facts / data from read_mdd (offsetLog, calibration, extended sensor mode)
zero_user  zero force entered by the user (uN); None or NaN = 'Offset' entry of the channel in the log file (written
           at the start of a recording, AU; 0 = not calibrated --> NaN). The log value is converted to uN with
           calibration_factor, and whether the factor of the extended sensor mode belongs to it depends on the
           version of the control software (offset_normalized): from lab version 10e on the line is normalized
           (raw x factor) and the calibration alone converts it, up to 10d it was the raw value of the mode that was
           active when the offset was detected, so there the factor at the time of the entry belongs to it. The
           control software writes no new Offset line when the mode is switched during a recording; the small step
           that the approximate factor leaves is noted in the report.
z          zero force at the times t (NaN = unknown), src text ('user', 'log', 'unknown', ...)
zeroT, zeroV  the step function (times, values)

TS 2026-10-06 (port of mda_zeroForce.m, TS 2026-10-04)
"""
from __future__ import annotations

import numpy as np

from .calibration_factor import calibration_factor, offset_normalized


def _first(v):
    if v is None:
        return None
    a = np.atleast_1d(np.asarray(v, dtype=float)).ravel()
    return None if a.size == 0 else float(a[0])


def zero_force(S, channel, zero_user=None, t=None):
    t = np.asarray([] if t is None else t, dtype=float)
    zeroT = np.array([0.0])
    zeroV = np.array([np.nan])
    src = "unknown"
    zu = _first(zero_user)
    if zu is not None and not np.isnan(zu):
        zeroV = np.array([zu])
        src = "user"
    elif "offsetLog" in S and S.offsetLog is not None and np.size(S.offsetLog) > 0:
        L = np.asarray(S.offsetLog, dtype=float).reshape(-1, 3)
        E = L[L[:, 1] == channel]
        if E.shape[0] > 0:
            E = E[np.argsort(E[:, 0], kind="stable")]
            v = E[:, 2].copy()
            v[v == 0] = np.nan  # 0 = offset not calibrated
            if np.all(np.isnan(v)):
                src = "log: not calibrated (0)"
            else:
                zeroT = E[:, 0].copy()
                with_mode = True                 # up to 10d: raw value of the mode of that moment
                if "programVersion" in S:
                    with_mode = not offset_normalized(S.programVersion)
                zeroV = v * calibration_factor(S, channel, zeroT, with_sensor_mode=with_mode)
                src = "log"
    idx = np.zeros(t.shape, dtype=int)  # before the first entry: the first entry
    for j in range(1, zeroT.size):
        idx[t >= zeroT[j]] = j
    z = zeroV[idx] if t.size else np.zeros(t.shape)
    return z, src, zeroT, zeroV


def zero_at(zeroT, zeroV, t):
    """value of the step function at time t (before the first entry: the first entry)."""
    k = np.flatnonzero(np.asarray(zeroT) <= t)
    k = k[-1] if k.size else 0
    return float(np.asarray(zeroV)[k])
