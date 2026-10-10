"""Spike artifacts of the force channels: detection and removal. Port of mda_removeSpikes.m.

    X, spikes = remove_spikes(X, fs)        X: channels x samples (raw samples of the force channels, AU)
    X, spikes = remove_spikes(X, fs, opts)  options spikeJumpMin, spikeJumpFactor, spikeGroupGap, spikeMaxDuration,
                                            spikeLevelWindow, spikeJumpFraction, spikeCoincidence,
                                            spikeCoincidenceFactor (advanced settings; the numbers below are their
                                            defaults)

Spikes appear e.g. when a chamber is taken out or put in, often in several channels at once: the value jumps within
1-2 samples and comes back within a few ms (or goes on to a new level). A spike is a group of jumps (|difference
between two samples| >= J; jumps < 40 ms apart form one group) that lasts <= 100 ms, goes beyond the level before
and the level after it (median of the 20 ms before / after) by >= J, and whose largest jump is >= 50 % of its
largest deviation from the level before (abrupt; a contraction rises over many samples: at most ~30 % of its
amplitude per sample at 400 Hz). J = max(50 AU, 8 x median of the non-zero |differences| of the channel) (noise
level: independent of contractions and spikes). Where a spike of another channel lies within +-10 ms, J = max(50 AU,
J / 2) (spikes in several channels). A level change (step when a chamber is put in or taken out: one jump or a monotonic
transition) is no spike and stays. Replaced: the samples between the first and the last jump of the group, by a line
from the sample before to the sample after (a step with a spike becomes a short ramp).

spikes: array, one row per spike: channel index (0-based), first and last replaced sample (0-based), size (largest
deviation from the sample before the spike, AU).

TS 2026-10-10 (advanced settings 2026-10-10)
"""
from __future__ import annotations

import numpy as np

_DEFAULTS = dict(spikeJumpMin=50.0,  # AU
                 spikeJumpFactor=8.0,  # x median of the non-zero |differences|
                 spikeGroupGap=0.04, spikeMaxDuration=0.1, spikeLevelWindow=0.02,  # s
                 spikeJumpFraction=0.5, spikeCoincidence=0.01, spikeCoincidenceFactor=0.5)


def remove_spikes(X, fs, opts=None):
    D = {k: float(opts.get(k, v)) if opts is not None else v for k, v in _DEFAULTS.items()}
    JUMP_MIN, JUMP_FACTOR = D["spikeJumpMin"], D["spikeJumpFactor"]
    GROUP_GAP_MS, MAX_MS = 1000 * D["spikeGroupGap"], 1000 * D["spikeMaxDuration"]
    LEVEL_MS, COINCIDENCE_MS = 1000 * D["spikeLevelWindow"], 1000 * D["spikeCoincidence"]
    X = np.array(X, dtype=float, copy=True)
    if X.ndim == 1:
        X = X[None, :]
    nCh, n = X.shape
    G = max(1, int(round(GROUP_GAP_MS * fs / 1000)))
    Lmax = max(1, int(round(MAX_MS * fs / 1000)))
    W = max(2, int(round(LEVEL_MS * fs / 1000)))
    Cw = max(1, int(round(COINCIDENCE_MS * fs / 1000)))
    found = []
    J1 = np.zeros(nCh)  # jump threshold of every channel (pass 1)
    replaced = np.zeros((nCh, n), bool)
    if n < 2 * W + 2:
        return X, np.zeros((0, 4))
    for pas in (1, 2):
        near = np.zeros(n, bool)  # pass 2: within +-10 ms of a spike of another channel
        if pas == 2:
            if not found:
                break
        for c in range(nCh):
            x = X[c]
            ad = np.abs(np.diff(x))
            if pas == 1:
                nz = ad[ad > 0]
                J1[c] = max(JUMP_MIN, JUMP_FACTOR * (float(np.median(nz)) if nz.size else 0.0))
                J = J1[c]
                big = np.flatnonzero(ad >= J)
            else:
                near[:] = False
                for f in found:
                    if f[0] != c:
                        near[max(0, f[1] - Cw):min(n, f[2] + Cw + 1)] = True
                J = max(JUMP_MIN, D["spikeCoincidenceFactor"] * J1[c])
                big = np.flatnonzero((ad >= J) & near[:-1] & ~replaced[c, :-1] & ~replaced[c, 1:])
            if big.size == 0:
                continue
            br = np.flatnonzero(np.diff(big) > G)
            for k1, k2 in zip(big[np.r_[0, br + 1]], big[np.r_[br, big.size - 1]]):
                k1, k2 = int(k1), int(k2)
                if replaced[c, k1 + 1:k2 + 1].any() or not _is_spike(x, k1, k2, J, W, Lmax, D["spikeJumpFraction"]):
                    continue
                size = float(np.max(np.abs(x[k1 + 1:k2 + 1] - x[k1])))
                q = np.arange(k1 + 1, k2 + 1)
                x[k1 + 1:k2 + 1] = x[k1] + (x[k2 + 1] - x[k1]) * (q - k1) / (k2 + 1 - k1)
                replaced[c, k1 + 1:k2 + 1] = True
                found.append((c, k1 + 1, k2, size))
    found.sort(key=lambda f: (f[1], f[0]))
    return X, np.array(found, dtype=float).reshape(-1, 4)


def _is_spike(x, k1, k2, J, W, Lmax, frac=0.5):
    """jumps k1..k2 (jump k: x[k] -> x[k+1]): x[k1+1..k2] is a spike"""
    if k2 <= k1 or k2 - k1 > Lmax or k1 - W + 1 < 0 or k2 + 1 + W > x.size:
        return False
    seg = x[k1 + 1:k2 + 1]
    before = float(np.median(x[k1 - W + 1:k1 + 1]))
    after = float(np.median(x[k2 + 1:k2 + 1 + W]))
    beyond = max(float(seg.max()) - max(before, after), min(before, after) - float(seg.min()))
    if beyond < J:
        return False  # a step / monotonic transition
    largestJump = float(np.max(np.abs(np.diff(x[k1:k2 + 2]))))
    return largestJump >= frac * float(np.max(np.abs(seg - before)))
