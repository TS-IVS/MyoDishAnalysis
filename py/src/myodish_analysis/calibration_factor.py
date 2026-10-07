"""Factor AU --> uN of a data channel at the times t (step function of time). Port of mda_calibrationFactor.m.

    k = calibration_factor(H, channel, t)     H = file facts from read_mdd, t = times in the file (s)

The values in an .mdd file are arbitrary units (AU):  uN = AU * k,  k = 1000 / calibrationEff(t).
calibrationEff = 'Calibration' entry of the channel in the log file (AU per mN, a kind of spring constant; 1000 if
there is none), divided by H.extendedSensorFactor (3.3) while the extended sensor mode is on.
Examples: 1000 --> k = 1; 3000 --> k = 1/3; 1000 in extended sensor mode --> k = 3.3.
k = 1 everywhere if the calibration is not applied (option calibration='none': values as stored in the file).

TS 2026-10-06 (port of mda_calibrationFactor.m, TS 2026-10-04)
"""
from __future__ import annotations

import numpy as np


def calibration_factor(H, channel, t):
    t = np.asarray(t, dtype=float)
    k = np.ones(t.shape)
    if not H.calibrationApplied:
        return k
    cal = 1000.0 * np.ones(t.shape)
    L = np.asarray(H.calibrationLog, dtype=float).reshape(-1, 3)
    E = L[(L[:, 1] == channel) & (L[:, 2] > 0)]
    if E.shape[0] > 0:
        E = E[np.argsort(E[:, 0], kind="stable")]  # entries before the recording start (-Inf) keep the log order
        cal[...] = E[0, 2]  # the first entry also holds before its time
        for j in range(1, E.shape[0]):
            cal[t >= E[j, 0]] = E[j, 2]
    X = np.asarray(H.extendedSensorIntervals, dtype=float).reshape(-1, 2)
    for q in range(X.shape[0]):
        I = (t >= X[q, 0]) & (t < X[q, 1])
        cal[I] = cal[I] / H.extendedSensorFactor
    return 1000.0 / cal
