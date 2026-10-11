# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Spike removal (spikes.remove_spikes, option spikeRemoval of read_mdd) with synthetic signals. Pendant of
mda_testSpikes.m (same signals and checks; sample indices here 0-based).

    ch1  rabbit-like contractions every 1 s (rise 60 ms), noise +-8 AU (raw sample pairs as in MyoDish files)
         spikes: 2.3 s one sample +2000; 4.6 s five samples -3000; 16.0 s five samples +3000
    ch2  fast rat-like contractions every 0.5 s (rise 20 ms), noise +-50 AU
         spikes: 1 sample -1500 in the upstroke of the contraction at 3.3 s; 16.0025 s five samples +120 (smaller than
         the jump threshold of ch2: found because of the spike of ch1 at the same time)
    ch3  chamber put in at 10 s: -5000 --> 30 ms at +20000, 10 ms at -15000 --> new level -2000 (spike + step);
         chamber taken out at 14 s: step to -8000 (no spike: stays)

TS 2026-10-10
"""
import math
import os

import numpy as np

import myodish_analysis as mda
from myodish_analysis.spikes import remove_spikes

FS = 400.0
N = 20 * 400


def _noise(k, a, b):
    kk = 2 * np.floor(k / 2)  # pairs of identical raw samples
    return np.floor(a * np.sin(0.7 * kk) + b * np.sin(1.9 * kk + 0.3) + 0.5)


def _beats(t, first, period, amp, rise, tau):
    y = np.zeros_like(t)
    for t0 in np.arange(first, t[-1], period):
        u = t - t0
        r = (u >= 0) & (u < rise)
        y[r] += amp * (1 - np.cos(math.pi * u[r] / rise)) / 2
        d = (u >= rise) & (u < rise + 8 * tau)
        y[d] += amp * np.exp(-(u[d] - rise) / tau)
    return y


def signals():
    k = np.arange(N, dtype=float)
    t = k / FS
    X0 = np.zeros((3, N))
    X0[0] = np.floor(-8000 + _beats(t, 0.5, 1.0, 1000, 0.06, 0.12) + 0.5) + _noise(k, 5, 3)
    X0[1] = np.floor(-5000 + _beats(t, 0.3, 0.5, 800, 0.02, 0.04) + 0.5) + _noise(k, 30, 20)
    X0[2] = np.where(k < 4000, -5000, np.where(k < 5600, -2000, -8000)) + _noise(k, 5, 3)
    X = X0.copy()
    X[0, 920] += 2000
    X[0, 1840:1845] -= 3000
    X[0, 6400:6405] += 3000
    X[1, 1324] -= 1500
    X[1, 6401:6406] += 120
    X[2, 4000:4012] = 20000
    X[2, 4012:4016] = -15000
    return X0, X


def test_remove_spikes_synthetic():
    X0, X = signals()
    _, none = remove_spikes(X0, FS)
    assert none.shape[0] == 0  # contractions (also fast ones), noise and steps are no spikes
    Y, sp = remove_spikes(X, FS)
    assert sp.shape == (6, 4)
    np.testing.assert_array_equal(sp[:, 0], [0, 1, 0, 2, 0, 1])
    np.testing.assert_array_equal(sp[:, 1], [920, 1324, 1840, 4000, 6400, 6401])
    np.testing.assert_array_equal(sp[:, 2], [920, 1324, 1844, 4015, 6404, 6405])
    rep = np.zeros(X.shape, bool)
    for c, a, b, _ in sp:
        rep[int(c), int(a):int(b) + 1] = True
    assert np.array_equal(Y[~rep], X[~rep])  # nothing else changed
    assert np.max(np.abs(Y[0, [920, 1840, 1842, 1844, 6402]] - X0[0, [920, 1840, 1842, 1844, 6402]])) <= 20
    assert abs(Y[1, 1324] - X0[1, 1324]) <= 0.1 * 800  # on the upstroke: close to the true value
    assert np.max(np.abs(Y[1, 6401:6406] - X0[1, 6401:6406])) <= 120
    seg = Y[2, 3995:4025]
    assert seg.max() <= -1900 and seg.min() >= -5100  # ramp from the old to the new level
    assert np.array_equal(Y[2, 5590:5700], X0[2, 5590:5700])  # step when the chamber is taken out: kept


def test_read_mdd_spike_removal(tmp_path):
    X0, X = signals()
    raw = np.zeros((9, N))
    raw[:3] = X
    raw[3:8] = -383
    f = str(tmp_path / "spikes_rigA_0.mdd")
    raw.T.astype("<i2").tofile(f)
    lines = ["systemTime;dataLogTime;channel;code;value",
             "2000 01 01 10:00:00:000;0;0;samplingRate Recording;400",
             "2000 01 01 10:00:00:000;0;0;Recording;started: spikes_rigA_0.mdd",
             "2000 01 01 10:00:20:000;20000;0;Recording;stopped: spikes_rigA_0.mdd"]
    with open(f[:-4] + "_log.log", "w") as fh:
        fh.write("\n".join(lines) + "\n")
    H = mda.read_mdd(f)
    S = mda.read_mdd(H, 0, 20)
    assert S.spikes.shape == (6, 4)
    np.testing.assert_array_equal(S.spikes[:, 0], [1, 2, 1, 3, 1, 2])
    np.testing.assert_allclose(S.spikes[:, 1], np.array([920, 1324, 1840, 4000, 6400, 6401]) / FS)
    S0 = mda.read_mdd(H, 0, 20, mda.options(spikeRemoval=False))
    assert S0.spikes.shape[0] == 0
    np.testing.assert_allclose(S0.force[0], (X[0, 0::2] + X[0, 1::2]) / 2)  # raw: unchanged
    C, _, info = mda.myodish_analysis(f, [1, 2, 3], 0, 20, quiet=True)
    assert "Spike artifacts removed (option spikeRemoval): 6 (channel 1: 3, channel 2: 2, channel 3: 1), largest " \
        "24997 AU." in info["notes"]
    C0, _, _ = mda.myodish_analysis(f, [1, 2, 3], 0, 20, quiet=True, spikeRemoval=False)
    a3, a03 = C.loc[C["channel"] == 3, "amplitude"], C0.loc[C0["channel"] == 3, "amplitude"]
    assert a03.max() > 20000 and a3.max() < 5000  # the spike of the chamber put in is no 'contraction' any more
    assert (C["channel"] == 1).sum() == (C0["channel"] == 1).sum() == 20  # short spikes: median filter anyway
