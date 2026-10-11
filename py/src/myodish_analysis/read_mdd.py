# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Read a MyoDish .mdd file (force data, stimulus pulses, rocker state). Port of mda_readMdd.m.

    H = read_mdd(mdd_file)                          file facts only (no data)
    S = read_mdd(H, from_s, to_s, opts)             data, with the file facts H of an earlier call (faster: the log
                                                    file is not read again; same opts as for H)
    S = read_mdd(mdd_file, from_s, to_s[, opts])    data between from_s and to_s (time in the file)
    O = read_mdd(mdd_file, 'overview', bin_s[, opts, progress])    min/max of every channel per bin of the file
    O = read_mdd(mdd_file, 'overview', [bin_s, from_s, to_s], ...)  only this part of the file

FILE FORMAT (MyoDish software; facts from the Seidel lab's importMyoDishData)
  - int16, little endian, channels interleaved. Standard: 8 force channels + 1 stimulus/status channel at 400 Hz
    (7200 bytes per second). Since MyoDish software 2.0.9708 (07/2026) a file may contain only the recorded
    channel(s) + the status channel (single channel mode: 2 x int16 per sample).
    Old files (2020/21, software 1.0.x): 8 force channels at 500 Hz, no status channel.
  - sampling rate, recording duration (--> number of channels) and extended sensor mode are read from the log file
    <name>_log.log (UTF-16) next to the .mdd file.
  - the values in the file are arbitrary units (AU), converted to uN with the 'Calibration' entry of each channel in
    the log file (see calibration_factor). Option calibration='none' keeps the values as stored in the file.
  - status channel, bits (1-based): 1-8 stimulus current [mA], 9 current not reached, 10-13 stimulated channel,
    14 external trigger, 15 rocker moving (set in every sample while the rocker moves), 16 extra pulse. A stimulus
    pulse is a sample with any bit other than bit 15 set.
  - some setups do not transmit the rocker bit (firmware error). If bit 15 is never set while the log file has rocker
    speeds > 0 (tested in up to 5 such periods), or if there is no status channel, the rocker state is taken from the
    'rockerSpeed' entries of the log file (moving while rpm > 0, from rockerLogDelay = 0.27 s after the entry: median
    delay of the rocker bit in 154 transitions of 7 recordings, 0.26-0.31 s; moving before the first entry, as in
    all 7 recordings). Options rockerSource ('auto' |
    'status' | 'log') and rockerLogDelay, see options.

OUTPUT (S, a Struct with the field names of the MATLAB version)
  file facts: file, logFile, samplingRate, nChannelsInFile, dataChannels (physical channel numbers, 1-based),
              hasStimChannel, totalSeconds, recordingStart (MATLAB datenum of file time 0, NaN if unknown; 12-hour
              time stamps of software 2.0.7717-2.0.7769 corrected, see clock_time),
              extendedSensorIntervals, notes, offsetLog / calibrationLog ([time channel value] rows; time -Inf =
              logged before the recording start), rockerSpeedLog ([time rpm]), pulseSettingsLog ([time logChannel
              code value]: chargeDuration (code 1), pauseDuration (2), dechargeDuration (3) entries, us; log channel
              10k + c = extra pulse #k of channel c), extraPulseLog ([time channel k offset_ms line]: programmed time
              of the extra pulses relative to the regular pulse of the channel, see extra_pulse_offsets),
              calibrationApplied,
              extendedSensorFactor, rockerSource ('status channel' or 'log'), rockerLogIntervals ([from to] in s
              with rocker speed > 0 according to the log file)
  data:       t (s; centre of the averaged raw samples, first raw sample = 0 s), dt, force (nData x n, uN),
              rockerOn (bool, n), stim (Struct of arrays: time, channel, current, currentReached, external,
              isExtraPulse, rockerOn; one entry per stimulus pulse of any channel)
  Single channel files: force has one row = channel 1, stim.channel keeps the physical channel number.
  External trigger pulses (status bit 14 without channel / current bits, e.g. an external stimulator at the external
  controller unit): stim.channel = 0 (before 2026-10-08 channel 8); consecutive samples of such a pulse = one pulse;
  used as stimuli according to the option externalTrigger (analyze_channel).

TS 2026-10-06 (port of mda_readMdd.m, TS 2026-10-05; rocker state from the log 2026-10-07)
"""
from __future__ import annotations

import math
import os

import numpy as np

import datetime as _dt

from ._matlab import Struct, datetime_to_datenum, mround
from .clock_time import clock_time
from .calibration_factor import calibration_factor
from .log_entries import parse_clock_numbers, read_log_text, split_lines, sscanf_floats, str2double
from .options import options as _options
from .spikes import remove_spikes

import re as _re


def read_mdd(mdd_file, from_s=None, to_s=None, opts=None, progress=None):
    if opts is None:
        opts = _options()
    if isinstance(mdd_file, dict):  # file facts of an earlier call (same options): the log file is not read again
        S = Struct(mdd_file)
    else:
        S = read_header(str(mdd_file), opts)
    if from_s is None or (not isinstance(from_s, str) and np.size(from_s) == 0):
        return S
    if isinstance(from_s, str) and from_s.lower() == "overview":
        b = to_s
        t_range = None
        if b is not None and np.size(b) == 3:
            b = list(np.ravel(b))
            t_range = b[1:3]
            b = b[0]
        if b is None or (not np.isscalar(b) and np.size(b) == 0):
            b = max(1.0, S.totalSeconds / 20000.0)
        return read_overview(S, float(b), progress, t_range)
    if to_s is None:
        to_s = math.inf
    return read_data(S, float(from_s), float(to_s), opts.downsampling,
                     spike_removal=bool(opts.get("spikeRemoval", True)), opts=opts)


# =====================================================================================================
def read_header(mdd_file, opts=None):
    if opts is None:
        opts = _options()
    if not os.path.isfile(mdd_file):
        raise FileNotFoundError(f"read_mdd: file not found: {mdd_file}")
    H = Struct()
    H.file = os.path.abspath(mdd_file)
    H.bytes = os.path.getsize(H.file)
    p, nm = os.path.split(H.file)
    n = os.path.splitext(nm)[0]
    H.logFile = os.path.join(p, n + "_log.log")
    H.notes = []

    L = read_log(H.logFile, _dt.datetime.fromtimestamp(os.path.getmtime(H.file)))
    H.recordingStart = L.startDatenum
    if L.clockNote:
        H.notes.append(L.clockNote)  # 12-hour time stamps (2026-10-08)
    H.programVersion = L.programVersion
    H.recordingStopped = L.recordingStopped  # True / False / None (2026-10-08)
    H.offsetLog = L.offsetEvents
    H.calibrationLog = L.calibrationEvents
    H.rockerSpeedLog = L.rockerSpeedEvents
    # [time logChannel code value]: pulse durations (us; code 1 charge, 2 pause, 3 decharge; log channel 10k + c =
    # extra pulse #k of channel c); [time channel k offset_ms line]: programmed extra pulse times (2026-10-10)
    H.pulseSettingsLog = L.pulseSettingsEvents
    H.extraPulseLog = L.extraPulseOffsets

    # sampling rate: option > log file > 500 Hz for old 8-channel files (software 1.0.x) > 400 Hz
    if opts.samplingRate is not None:
        fs = float(opts.samplingRate); src = "option"
    elif not math.isnan(L.samplingRate):
        fs = L.samplingRate; src = "log file"
    elif (opts.nChannels is not None and opts.nChannels == 8) or L.nChannelsController == 8:
        fs = 500.0; src = "assumed (old 8-channel file)"
    else:
        fs = 400.0; src = "assumed"
    H.samplingRate = fs
    H.samplingRateSource = src
    if src not in ("log file", "option"):
        H.notes.append(f"No sampling rate in the log file: {_g(fs)} Hz assumed.")

    # number of int16 channels in the file: option > file size / recording duration > single channel mode > 9
    if opts.nChannels is not None:
        nCh = int(opts.nChannels)
    else:
        nCh = None
        if not math.isnan(L.recordingDuration) and L.recordingDuration > 5:
            nEst = H.bytes / (2 * fs * L.recordingDuration)
            if abs(nEst - mround(nEst)) < 0.1 and 2 <= mround(nEst) <= 9:
                nCh = int(mround(nEst))
            else:
                H.notes.append(f"File size does not fit the recording duration in the log file ({nEst:.2f} channels).")
        elif L.singleChannelMode is True:
            nCh = 2
        if nCh is None and math.isnan(L.samplingRate) and L.nChannelsController == 8:
            nCh = 8  # old 8-channel file (500 Hz, no status channel)
        if nCh is None:
            # no usable log information: the status channel (last channel) contains almost only 0 or the rocker
            # bit (16384); test 9 channels first, then single channel mode (2), then the others
            nCh = 9
            for cand in (9, 2, 3, 4, 5, 6, 7, 8):
                if _status_fraction(H.file, cand) > 0.95:
                    nCh = cand
                    break
            H.notes.append(f"{nCh} channels in the file (from the content of the status channel).")
    H.nChannelsInFile = nCh

    # status (stimulus) channel = last channel, except in legacy 8-channel files (500 Hz / nChannels;8 in the log)
    isLegacy = math.isnan(L.samplingRate) or L.samplingRate == 500 or L.nChannelsController == 8
    if nCh == 8 and isLegacy:
        H.hasStimChannel = False
        H.dataChannels = np.arange(1, 9)
    elif nCh >= 9:
        H.hasStimChannel = True
        H.dataChannels = np.arange(1, 9)
    else:
        H.hasStimChannel = True
        H.dataChannels = np.arange(1, nCh)
    H.stimRow = nCh - 1  # 0-based row of the status channel (MATLAB: nCh)
    H.totalSamples = H.bytes // (2 * nCh)
    H.totalSeconds = H.totalSamples / fs

    # rocker state: bit 15 of the status channel or, if this bit is missing although the log file has rocker speeds
    # > 0 (firmware error in some setups) or there is no status channel, the 'rockerSpeed' entries of the log file
    # (rocker moving while rpm > 0, from 'rockerLogDelay' s after the entry)
    H.rockerLogIntervals = rocker_intervals_from_log(H.rockerSpeedLog, float(opts.rockerLogDelay), H.totalSeconds)
    src = str(opts.rockerSource).lower()
    if src == "log":
        H.rockerSource = "log"
    elif src == "status":
        H.rockerSource = "status channel"
    else:
        H.rockerSource = "status channel"
        if H.rockerLogIntervals.shape[0]:
            if not H.hasStimChannel:
                H.rockerSource = "log"
                H.notes.append("No status channel: rocker state from the rockerSpeed entries of the log file (+%s s)."
                               % _g(float(opts.rockerLogDelay)))
            elif not _rocker_bit_in_intervals(H):
                H.rockerSource = "log"
                H.notes.append("Rocker bit missing in the status channel although the rocker speed was > 0: rocker "
                               "state from the rockerSpeed entries of the log file (+%s s)." % _g(float(opts.rockerLogDelay)))

    # extended sensor mode: intervals [from to] (s) in which the calibration value is divided by 3.3
    ext = []
    esm = opts.extendedSensorMode
    if isinstance(esm, str):
        for tt, on in L.extendedSensorModeEvents:
            if on == 1 and (not ext or not math.isinf(ext[-1][1])):
                ext.append([tt, math.inf])
            elif on == 0 and ext and math.isinf(ext[-1][1]):
                ext[-1][1] = tt
    elif esm:
        ext = [[-math.inf, math.inf]]
    ext = np.array(ext, dtype=float).reshape(-1, 2)
    H.extendedSensorIntervals = ext[ext[:, 1] > ext[:, 0]]
    H.extendedSensorFactor = float(opts.extendedSensorFactor)

    # calibration (AU per mN) --> factor 1000 / calibration per data channel (calibration_factor)
    H.calibrationApplied = opts.calibration == "auto"
    if H.calibrationApplied:
        C = np.asarray(H.calibrationLog).reshape(-1, 3)
        C = C[np.isin(C[:, 1], H.dataChannels) & (C[:, 2] > 0)]
        oddC = C[C[:, 2] != 1000]
        if oddC.shape[0]:
            H.notes.append("Calibration %s AU/mN in channel(s) %s: data converted to uN (AU x 1000 / calibration)."
                           % (_mat2str(np.unique(oddC[:, 2])), _mat2str(np.unique(oddC[:, 1]))))
        if H.extendedSensorIntervals.shape[0]:
            H.notes.append("Extended sensor mode on (%s s): calibration / %s."
                           % (_mat2str(H.extendedSensorIntervals, 6), _g(H.extendedSensorFactor)))
    else:
        H.notes.append("Calibration not applied: force values in arbitrary units (AU) as stored in the file.")
    return H


def _g(x):
    return f"{x:g}"


def _mat2str(a, prec=15):
    a = np.asarray(a, dtype=float)

    def f(v):
        if math.isinf(v):
            return "Inf" if v > 0 else "-Inf"
        return f"{v:.{prec}g}"
    if a.ndim <= 1:
        if a.size == 1:
            return f(float(a.ravel()[0]))
        return "[" + " ".join(f(v) for v in a.ravel()) + "]"
    if a.shape[0] == 1 and a.shape[1] == 1:
        return f(float(a[0, 0]))
    return "[" + ";".join(" ".join(f(v) for v in row) for row in a) + "]"


# =====================================================================================================
def read_data(H, from_s, to_s, nDS=2, stim_only=False, spike_removal=False, opts=None):
    """data between from_s and to_s (see read_mdd); stim_only: stimulus pulses and rocker state only (force not
    converted, S.force has no columns); spike_removal: spike artifacts of the force channels removed (remove_spikes;
    S.spikes: channel, from, to [s], size [AU]); opts: options of the spike removal (advanced settings)."""
    S = Struct(H)
    S.notes = list(H.notes)
    fs = S.samplingRate
    nCh = S.nChannelsInFile
    nDS = int(nDS)
    if from_s < 0:
        from_s = S.totalSeconds + from_s
    if to_s < 0:
        to_s = S.totalSeconds + to_s
    i0 = max(0, math.floor(from_s * fs / nDS) * nDS)  # first raw sample (0-based), on the nDS grid
    i1 = S.totalSamples if not math.isfinite(to_s) else min(S.totalSamples, math.ceil(to_s * fs))
    nRaw = (max(0, i1 - i0) // nDS) * nDS
    raw = np.fromfile(S.file, dtype="<i2", count=nCh * nRaw, offset=i0 * nCh * 2) if nRaw > 0 \
        else np.zeros(0, dtype="<i2")
    raw = raw[: (raw.size // nCh) * nCh].reshape(-1, nCh).T  # nCh x nRaw
    nRaw = (raw.shape[1] // nDS) * nDS
    raw = raw[:, :nRaw]
    n = nRaw // nDS
    S.fromSeconds = i0 / fs
    S.toSeconds = (i0 + nRaw) / fs
    S.dt = nDS / fs
    S.downsampling = nDS
    S.t = ((i0 + np.arange(n) * nDS) + (nDS - 1) / 2) / fs

    # force channels: spike artifacts removed (option spikeRemoval, see spikes.py), mean of nDS samples (nDS = 2:
    # identical to the median used by importMyoDishData)
    nData = len(S.dataChannels)
    S.force = np.zeros((nData, 0 if stim_only else n))
    S.spikes = np.zeros((0, 4))  # channel, from, to (s, time in the file), size (AU)
    Xr = None
    if spike_removal and not stim_only and nRaw > 0:
        Xr, sp = remove_spikes(raw[:nData], fs, opts)
        if sp.size:
            S.spikes = np.c_[np.asarray(S.dataChannels, float).ravel()[sp[:, 0].astype(int)], (i0 + sp[:, 1]) / fs,
                             (i0 + sp[:, 2]) / fs, sp[:, 3]]
    for c in range(0 if stim_only else nData):
        x = raw[c].astype(float) if Xr is None else Xr[c]
        if nDS == 2:
            x = (x[0::2] + x[1::2]) / 2
        elif nDS > 2:
            x = np.median(x.reshape(n, nDS), axis=1)
        S.force[c] = x
    for c in range(0 if stim_only else nData):  # AU --> uN (calibration, extended sensor mode)
        S.force[c] = S.force[c] * calibration_factor(S, S.dataChannels[c], S.t)

    # status channel: stimulus pulses and rocker state
    S.stim = Struct(time=np.zeros(0), channel=np.zeros(0, dtype=int), current=np.zeros(0),
                    currentReached=np.zeros(0, bool), external=np.zeros(0, bool), isExtraPulse=np.zeros(0, bool),
                    rockerOn=np.zeros(0, bool))
    S.rockerOn = np.zeros(n, bool)
    isLog = S.get("rockerSource") == "log"
    if S.hasStimChannel and nRaw > 0:
        code = raw[S.stimRow].view(np.uint16)
        rockerBit = (code & 16384) != 0  # bit 15
        idx = np.flatnonzero((code & 49151) != 0)  # any bit except bit 15 = stimulus pulse
        pc = code[idx]
        ch = ((pc >> 9) & 15).astype(int)  # bits 10-13
        isTrig = (pc & 16383) == 8192  # bit 14 without channel / current (bits 1-13): external trigger pulse
        ch[ch > 8] -= 8
        ch[ch == 0] = 8
        ch[isTrig] = 0  # no MyoDish channel
        if idx.size > 1:  # next sample of the same trigger pulse: one pulse
            dup = isTrig & np.r_[False, isTrig[:-1]] & np.r_[False, np.diff(idx) == 1]
            idx, pc, ch = idx[~dup], pc[~dup], ch[~dup]
        S.stim.time = (i0 + idx) / fs
        S.stim.channel = ch
        S.stim.current = (pc & 255).astype(float)  # bits 1-8 [mA]
        S.stim.currentReached = (pc & 256) == 0  # bit 9
        S.stim.external = (pc & 8192) != 0  # bit 14
        S.stim.isExtraPulse = (pc & 32768) != 0  # bit 16
        S.stim.rockerOn = rockerBit[idx].copy()
        # rocker state of every (downsampled) sample. In older firmware the rocker bit may only be set in the
        # stimulus pulses: then the state of the last pulse (any channel) is held until the next pulse.
        if isLog:
            pass  # rocker state from the log file (below)
        elif np.count_nonzero(rockerBit) > 2 * np.count_nonzero(S.stim.rockerOn):
            S.rockerOn = rockerBit.reshape(n, nDS).any(axis=1)
        elif S.stim.rockerOn.any():
            isPulse = np.zeros(nRaw, bool)
            isPulse[idx] = True
            lastPulse = np.cumsum(isPulse)
            pulseState = np.r_[False, S.stim.rockerOn]
            state = pulseState[lastPulse]
            S.rockerOn = state.reshape(n, nDS).any(axis=1)
            S.notes.append("Rocker state taken from the stimulus pulses (rocker bit not set continuously).")
    if isLog and nRaw > 0:  # rocker state from the 'rockerSpeed' entries of the log file
        state = rocker_state_from_log(S.rockerLogIntervals, (i0 + np.arange(nRaw)) / fs)
        S.rockerOn = state.reshape(n, nDS).any(axis=1)
        S.stim.rockerOn = state[np.round(S.stim.time * fs).astype(int) - i0]
    return S


def rocker_intervals_from_log(R, delay, T):
    """[from to] (s, time in the file) in which the rocker moves according to the 'rockerSpeed' entries (rpm > 0).
    An entry takes effect 'delay' s after its time; entries before the recording start (time -Inf) at time 0.
    Before the first entry the rocker moves (default state; in 7 of 7 recordings with rocker bit it moved at the start,
    also when the first entry was a speed > 0)."""
    R = np.asarray(R, dtype=float).reshape(-1, 2)
    I = []
    if R.shape[0] == 0:
        return np.zeros((0, 2))
    R = R[np.argsort(R[:, 0], kind="stable")]
    t = np.maximum(R[:, 0] + delay, 0.0)
    a = 0.0
    for k in range(R.shape[0]):
        if R[k, 1] > 0 and math.isnan(a):
            a = t[k]
        elif R[k, 1] <= 0 and not math.isnan(a):
            I.append([a, t[k]])
            a = math.nan
    if not math.isnan(a):
        I.append([a, T])
    I = np.array(I, dtype=float).reshape(-1, 2)
    I[:, 1] = np.minimum(I[:, 1], T)
    return I[I[:, 1] > I[:, 0]]


def rocker_state_from_log(I, t):
    """True where t lies in one of the intervals I = [from to] (sorted, disjoint): from <= t < to."""
    t = np.asarray(t, dtype=float)
    I = np.asarray(I, dtype=float).reshape(-1, 2)
    if I.shape[0] == 0 or t.size == 0:
        return np.zeros(t.shape, bool)
    k = np.searchsorted(I[:, 0], t, side="right") - 1
    v = k >= 0
    on = np.zeros(t.shape, bool)
    on[v] = t[v] < I[k[v], 1]
    return on


def _rocker_bit_in_intervals(H):
    """True if bit 15 of the status channel is set in (one of) the first 5 intervals with rocker movement according
    to the log file (0.25 s after the start, at most 4 s each); True also if no interval can be tested."""
    I = np.asarray(H.rockerLogIntervals, dtype=float).reshape(-1, 2)
    I = np.c_[I[:, 0] + 0.25, np.minimum(I[:, 1] - 0.25, I[:, 0] + 4.25)]
    I = I[I[:, 1] - I[:, 0] >= 0.5]
    if I.shape[0] == 0:
        return True
    fs = H.samplingRate
    nCh = H.nChannelsInFile
    for k in range(min(5, I.shape[0])):
        s0 = math.floor(I[k, 0] * fs)
        m = min(H.totalSamples, math.ceil(I[k, 1] * fs)) - s0
        if m <= 0:
            continue
        raw = np.fromfile(H.file, dtype="<i2", count=nCh * m, offset=s0 * nCh * 2)
        raw = raw[: (raw.size // nCh) * nCh].reshape(-1, nCh).T
        if np.any((raw[H.stimRow].view(np.uint16) & 16384) != 0):
            return True
    return False


# =====================================================================================================
def read_overview(H, bin_s, progress=None, t_range=None):
    """min/max of every data channel per bin over the whole file or the part t_range = [from to] (s), chunk-wise."""
    fs = H.samplingRate
    nCh = H.nChannelsInFile
    binSamples = max(1, mround(bin_s * fs))
    chunkBins = max(1, math.floor(600 * fs / binSamples))  # about 10 min per read
    chunkSamples = chunkBins * binSamples
    if t_range is None:
        s0, s1 = 0, H.totalSamples
    else:
        s0 = min(H.totalSamples, max(0, math.floor(t_range[0] * fs)))
        s1 = min(H.totalSamples, math.ceil(t_range[1] * fs))
    nSamples = max(0, s1 - s0)
    nBins = math.ceil(nSamples / binSamples)
    nData = len(H.dataChannels)
    O = Struct(H)
    O.binSeconds = binSamples / fs
    O.tBin = (s0 + (np.arange(nBins) + 0.5) * binSamples) / fs
    O.minForce = np.full((nData, nBins), np.nan)
    O.maxForce = np.full((nData, nBins), np.nan)
    O.rockerFraction = np.zeros(nBins)
    b0 = 0
    with open(H.file, "rb") as fh:
        fh.seek(s0 * nCh * 2)
        while b0 < nBins:
            m = min(chunkSamples, nSamples - b0 * binSamples)
            raw = np.fromfile(fh, dtype="<i2", count=m * nCh)
            m = raw.size // nCh
            if m == 0:
                break
            raw = raw[: m * nCh].reshape(m, nCh).T
            nb = math.ceil(m / binSamples)
            pad = nb * binSamples - m
            for c in range(nData):
                x = np.r_[raw[c].astype(float), np.full(pad, np.nan)]
                X = x.reshape(nb, binSamples)
                with np.errstate(all="ignore"):
                    O.minForce[c, b0:b0 + nb] = np.nanmin(X, axis=1)
                    O.maxForce[c, b0:b0 + nb] = np.nanmax(X, axis=1)
            if H.get("rockerSource") == "log":
                r = rocker_state_from_log(H.rockerLogIntervals, (s0 + b0 * binSamples + np.arange(m)) / fs).astype(float)
                r = np.r_[r, np.full(pad, np.nan)]
                O.rockerFraction[b0:b0 + nb] = np.nanmean(r.reshape(nb, binSamples), axis=1)
            elif H.hasStimChannel:
                r = ((raw[H.stimRow].view(np.uint16) & 16384) != 0).astype(float)
                r = np.r_[r, np.full(pad, np.nan)]
                O.rockerFraction[b0:b0 + nb] = np.nanmean(r.reshape(nb, binSamples), axis=1)
            b0 += nb
            if progress is not None:
                progress(min(1.0, b0 / nBins))
    for c in range(nData):  # AU --> uN
        kc = calibration_factor(H, H.dataChannels[c], O.tBin)
        O.minForce[c] *= kc
        O.maxForce[c] *= kc
    return O


# =====================================================================================================
def _status_fraction(file, nCh):
    """fraction of the values of the last channel (status channel if nCh is correct) that are 0 or 16384."""
    raw = np.fromfile(file, dtype="<i2", count=nCh * 20000)
    ncol = math.ceil(raw.size / nCh)
    raw = np.r_[raw, np.zeros(ncol * nCh - raw.size, dtype=raw.dtype)].reshape(ncol, nCh).T
    if raw.shape[1] < 100:
        return 0.0
    v = raw[nCh - 1]
    q = float(np.mean((v == 0) | (v == 16384)))
    if np.all(raw == 0):
        q = 0.0
    return q


# =====================================================================================================


def read_log(log_file, file_time=None):
    """the facts needed from the MyoDish log file (lines: systemTime;dataLogTime_ms;channel;code;value).
    file_time: last change of the .mdd file (decides AM/PM of 12-hour time stamps if the log cannot)."""
    L = Struct(samplingRate=math.nan, recordingDuration=math.nan, nChannelsController=math.nan,
               singleChannelMode=None, extendedSensorModeEvents=np.zeros((0, 2)), startDatenum=math.nan,
               programVersion="", clockNote="", offsetEvents=np.zeros((0, 3)), calibrationEvents=np.zeros((0, 3)),
               rockerSpeedEvents=np.zeros((0, 2)), recordingStopped=None, pulseSettingsEvents=np.zeros((0, 4)),
               extraPulseOffsets=np.zeros((0, 5)))
    txt = read_log_text(log_file)
    if txt is None:
        return L
    lines = split_lines(txt)
    nValid = 0
    tStart = tStop = tStartPar = tStopPar = math.nan
    kStart = kStartPar = None
    sysAll, tAll, textAll, versions = [], [], [], []  # all valid entries (clock time)
    # 2026-10-08: state of the last 'Recording' entry (1 started, 0 stopped) for this file (name in the entry), for
    # the main recording and for parallel recordings
    own = os.path.splitext(os.path.basename(log_file))[0]
    own = (own[:-4] if own.endswith("_log") else own).lower() + ".mdd"
    lastOwn = lastMain = lastPar = None
    tFirst = math.nan
    ext, offs, cal, rck = [], [], [], []  # last column: line number
    pst = []  # pulse durations: time, log channel, code (1-3), value (us), line
    seqEv = []  # 'Sequence' entries: (time, log channel, line, text)
    pstCodes = ("chargeduration", "pauseduration", "dechargeduration")
    lineStart = lineStartPar = math.nan
    tMax = tMaxPar = -math.inf  # latest dataLogTime since the chosen start line
    for i, line in enumerate(lines, start=1):
        f = _re.split(";+", line)  # strsplit: consecutive delimiters are collapsed
        if len(f) < 5:
            continue
        tsec = str2double(f[1]) / 1000.0
        if math.isnan(tsec):
            continue
        nValid += 1
        sysAll.append(f[0].strip()); tAll.append(tsec)
        if nValid == 1:
            tFirst = tsec
        code = f[3].strip()
        value = ";".join(f[4:]).strip()
        textAll.append(value)
        lc = code.lower(); lv = value.lower()
        if lc == "samplingrate recording":
            v = str2double(value)
            if not math.isnan(v):
                L.samplingRate = v
        elif lc == "recording":
            par = "parallel" in lv
            if "started" in lv:
                # the first start line; a later one only if the dataLogTime starts again (new recording). A
                # recording that was stopped and started again is appended to the same .mdd file.
                if par:
                    if math.isnan(lineStartPar) or tsec < tMaxPar - 1:
                        tStartPar = tsec; kStartPar = nValid - 1; lineStartPar = i; tMaxPar = tsec
                else:
                    if math.isnan(lineStart) or tsec < tMax - 1:
                        tStart = tsec; kStart = nValid - 1; lineStart = i; tMax = tsec
            elif "stopped" in lv:
                if par:
                    tStopPar = tsec
                else:
                    tStop = tsec
            st = 1 if "started" in lv else (0 if "stopped" in lv else None)
            if st is not None:
                if own in lv:
                    lastOwn = st
                if par:
                    lastPar = st
                else:
                    lastMain = st
        elif lc == "event" and "extended sensor mode" in lv:
            ext.append([tsec, float("off" not in lv), i])
        elif lc in ("offset", "calibration"):
            # one entry per channel ('<ch>;Calibration;1000'), or (software 2.0.80xx, 2022) all channels in one
            # line with channel 0 ('0;Calibration; 1000 1000 ... 1000')
            ch = str2double(f[2]); v = sscanf_floats(value)
            if not math.isnan(ch) and v:
                if ch == 0 and len(v) > 1:
                    E = [[tsec, k + 1, vk, i] for k, vk in enumerate(v)]
                else:
                    E = [[tsec, ch, v[0], i]]
                (offs if lc == "offset" else cal).extend(E)
        elif lc == "rockerspeed":
            v = str2double(value)
            if not math.isnan(v):
                rck.append([tsec, v, i])
        elif lc in pstCodes:  # pulse durations (us) of a channel; channel 10k+c = extra pulse #k
            ch = str2double(f[2]); v = str2double(value)
            if not math.isnan(ch) and not math.isnan(v):
                pst.append([tsec, ch, pstCodes.index(lc) + 1, v, i])
        elif lc == "sequence":  # stimulus times of the sequence (regular and extra pulses #k)
            seqEv.append((tsec, str2double(f[2]), i, value))
        elif lc == "nchannels":
            v = str2double(value)
            if not math.isnan(v):
                L.nChannelsController = v
        elif lc == "programinfo" and "version" in lv:
            L.programVersion = value
            versions.append(value)
        elif lc == "programversion":  # 2021-2022: 'ProgramVersion;2.0.7769.26061'
            versions.append(value)
        elif "singlechannelmode" in lc or (lc == "event" and "singlechannelmode" in lv):
            L.singleChannelMode = not ("off" in lv or "false" in lv or lv == "0")
        if not math.isnan(lineStart):
            tMax = max(tMax, tsec)
        if not math.isnan(lineStartPar):
            tMaxPar = max(tMaxPar, tsec)
    if nValid == 0:
        return L
    for last in (lastOwn, lastMain, lastPar):
        if last is not None:
            L.recordingStopped = last == 0
            break
    # entries of the main recording have priority over 'parallel recording' entries (schedule files)
    if math.isnan(tStart) and math.isnan(tStop):
        tStart = tStartPar; tStop = tStopPar; kStart = kStartPar
    if not math.isnan(tStart) and not math.isnan(tStop) and tStop > tStart:
        L.recordingDuration = tStop - tStart
    elif not math.isnan(tStop):
        L.recordingDuration = tStop
    # entries logged before the 'Recording started' line hold from the start of the file (time -Inf)
    if math.isnan(lineStart):
        lineStart = lineStartPar
    ext = np.array(ext, dtype=float).reshape(-1, 3)
    offs = np.array(offs, dtype=float).reshape(-1, 4)
    cal = np.array(cal, dtype=float).reshape(-1, 4)
    rck = np.array(rck, dtype=float).reshape(-1, 3)
    if not math.isnan(lineStart):
        ext[ext[:, 2] < lineStart, 0] = -math.inf
        offs[offs[:, 3] < lineStart, 0] = -math.inf
        cal[cal[:, 3] < lineStart, 0] = -math.inf
        rck[rck[:, 2] < lineStart, 0] = -math.inf
    pst = np.array(pst, dtype=float).reshape(-1, 5)
    X = extra_pulse_offsets(seqEv)
    if not math.isnan(lineStart):
        pst[pst[:, 4] < lineStart, 0] = -math.inf
        X[X[:, 4] < lineStart, 0] = -math.inf
    L.pulseSettingsEvents = pst[:, :4].copy()
    L.extraPulseOffsets = X
    L.rockerSpeedEvents = rck[:, :2].copy()
    L.extendedSensorModeEvents = ext[:, :2].copy()
    L.offsetEvents = offs[:, :3].copy()
    L.calibrationEvents = cal[:, :3].copy()
    # clock time of all entries, 12-hour time stamps (software 2.0.7717-2.0.7769) corrected (2026-10-08); file time 0
    # = clock time of the 'Recording started' entry - its dataLogTime
    clk, info = clock_time([parse_clock_numbers(x) for x in sysAll], tAll, versions, file_time, textAll)
    L.clockNote = info["note"]
    tSys = tStart
    if kStart is None:
        kStart = 0; tSys = tFirst
    if clk[kStart] is not None:
        if math.isnan(tSys):
            tSys = 0.0
        L.startDatenum = datetime_to_datenum(clk[kStart]) - tSys / 86400.0
    return L


_RE_ADDED = _re.compile(r"^Added stimTime(?:\(s\))?\s*(.*)$", _re.IGNORECASE)
_RE_TOKEN = _re.compile(r"^(-?\d+(?:\.\d+)?)(?:#(\d))?$")
_RE_NUM = _re.compile(r"-?\d+(\.\d+)?")


def extra_pulse_offsets(ev):
    """Programmed time of the extra pulses relative to the regular pulse of the same channel, from the 'Sequence'
    entries of the log file: 'Sent stimPeriod P' starts a new sequence (all extra pulses cleared); 'Added stimTime(s)
    a b#k ...' of channel c sets its regular times (numbers) and extra pulse times (#k = extra pulse k, software 2022
    and 2026); an entry of log channel 10k + c ('Added stimTime e') sets the times of extra pulse k of channel c.
    Returns rows [time, channel c, k, offset (ms; extra time - nearest regular time of the channel, within the
    period), line]. Every entry that changes channel c gives the complete set of its extra pulses (rows with the same
    line); k = 0 / offset NaN: no extra pulses. TS 2026-10-10 (port of mda_readMdd.m)"""
    rows = []
    R = [[] for _ in range(8)]  # regular times per channel (ms within the period)
    E = [[[] for _ in range(9)] for _ in range(8)]  # extra pulse times per channel and k
    P = math.nan  # period (ms)
    for t, chn, ln, txt in ev:
        txt = txt.strip()
        if txt[:15].lower() == "sent stimperiod":
            m = _RE_NUM.search(txt)
            p = float(m.group(0)) if m else math.nan
            if not math.isnan(p) and p > 0:
                P = p
            R = [[] for _ in range(8)]
            E = [[[] for _ in range(9)] for _ in range(8)]
            rows.extend([[t, c, 0, math.nan, ln] for c in range(1, 9)])
            continue
        m = _RE_ADDED.match(txt)
        if m is None or math.isnan(chn):
            continue
        k0 = int(math.floor(chn / 10)); c = int(chn - 10 * k0)
        if c < 1 or c > 8 or k0 > 9:
            continue
        reg = []; ext = [[] for _ in range(9)]
        for p in _re.split(r"\s+", m.group(1).strip()):
            mm = _RE_TOKEN.match(p)
            if mm is None:
                continue
            v = float(mm.group(1))
            if mm.group(2) is not None and int(mm.group(2)) >= 1:
                ext[int(mm.group(2)) - 1].append(v)
            elif k0 > 0:
                ext[k0 - 1].append(v)
            else:
                reg.append(v)
        if k0 == 0:  # an entry of channel c replaces its sequence
            R[c - 1] = reg
            for k in range(9):
                E[c - 1][k] = ext[k]
        else:
            E[c - 1][k0 - 1] = ext[k0 - 1]
        r = []
        for k in range(9):
            for e in E[c - 1][k]:
                if not R[c - 1]:
                    continue
                d = e - np.asarray(R[c - 1], float)
                if not math.isnan(P):
                    d = np.mod(d + P / 2, P) - P / 2
                j = int(np.argmin(np.abs(d)))
                r.append([t, c, k + 1, float(d[j]), ln])
        if not r:
            r = [[t, c, 0, math.nan, ln]]
        rows.extend(r)
    return np.array(rows, dtype=float).reshape(-1, 5)
