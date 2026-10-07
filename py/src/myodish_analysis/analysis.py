"""Contraction parameters of every single contraction in a MyoDish recording (.mdd). Port of MyoDishAnalysis.m.

    contractions, summary, info = myodish_analysis(mdd_file, channels, from_s, to_s, **options)

mdd_file   .mdd file. The log file <name>_log.log must be in the same folder.
channels   data channels, e.g. 3 or [1, 2, 5] (None = all channels in the file)
from_s     start of the analysed time range in s (time in the file; negative = seconds before the end)
to_s       end of the time range. Lists define several ranges, e.g. from_s=[600, 3000], to_s=[660, 3060]

contractions  DataFrame, one row per detected contraction (also the excluded ones, see column 'included')
summary       DataFrame, one row per channel and range: numbers of contractions/stimuli, mean and SD of all
              parameters of the included contractions
info          dict: file facts, options, detection threshold per channel and range, notes

OPTIONS (keywords)
  output='results.xlsx'   write the results (.xlsx: sheets contractions, summary, parameters, info; or .csv)
  labels=['baseline', 'drug']   names of the time ranges
  metadata=m              labels per channel (dict, DataFrame or .csv/.xlsx file), see labels.py
  showFigures=True        plot the signal with the detected contractions (matplotlib; ranges <= 30 min, <= 16)
  quiet=True              no messages
  rocker='stopped', beats='stimulated', threshold=300, zeroForce=[z1, z2, ...], rockerFilter=True,
  referenceBeat=R and all other options of options()

EXAMPLES
  T, S, info = myodish_analysis('examples/example3_humanVentricle.mdd', 6, 0, 120)
  T, S, info = myodish_analysis(f, [1, 2, 3], [600, 3000], [660, 3060], labels=['baseline', 'drug'],
                                    rocker='stopped', output='results.xlsx')

Thomas Seidel (FAU Erlangen-Nuernberg / InVitroSys GmbH), 2026-10-06 (port of MyoDishAnalysis.m, 2026-10-05)
"""
from __future__ import annotations

import datetime as _dt
import math
import os

import numpy as np
import pandas as pd

from ._matlab import Struct, colon
from .add_labels import add_labels
from .analyze_channel import analyze_channel
from .labels import labels as make_labels
from .options import options as make_options
from .read_mdd import read_mdd
from .rocker_filter import rocker_filter
from .summarize import summarize
from .write_results import write_results

DATENUM_1970 = 719529.0


def datenum_to_timestamps(dn):
    """MATLAB datenum(s) --> pandas datetime64 (NaN --> NaT)."""
    dn = np.asarray(dn, dtype=float)
    return pd.to_datetime((dn - DATENUM_1970) * 86400.0, unit="s")


def myodish_analysis(mdd_file, channels=None, from_s=0, to_s=math.inf, *, output=None, labels=None,
                         metadata=None, showFigures=False, quiet=False, chunkSeconds=1800, **opt_kw):
    opts = make_options(**opt_kw)
    H = read_mdd(mdd_file, None, None, opts)
    dc = [int(c) for c in np.asarray(H.dataChannels).ravel()]
    if channels is None or np.size(channels) == 0:
        channels = dc
    channels = [int(c) for c in np.atleast_1d(channels).ravel()]
    bad = [c for c in channels if c not in dc]
    if bad:
        raise ValueError(f"Channel(s) {bad} not in the file. Data channels in {H.file}: {dc}")
    fr = np.atleast_1d(np.asarray(from_s, dtype=float)).ravel()
    to = np.atleast_1d(np.asarray(to_s, dtype=float)).ravel()
    if fr.size != to.size:
        raise ValueError("from_s and to_s must have the same number of elements.")
    ranges = np.c_[fr, to]
    ranges[ranges < 0] = H.totalSeconds + ranges[ranges < 0]
    ranges = np.minimum(np.maximum(ranges, 0), H.totalSeconds)
    if np.any(ranges[:, 1] <= ranges[:, 0]):
        raise ValueError(f"Empty time range (file length {H.totalSeconds:.1f} s).")
    nR = ranges.shape[0]
    zf = opts.zeroForce
    if zf is None:
        zero_of = lambda c: None  # noqa: E731
    elif np.size(zf) == 1:
        zv = float(np.ravel(zf)[0])
        zero_of = lambda c: zv  # noqa: E731
    elif np.size(zf) == len(channels):
        zarr = np.ravel(np.asarray(zf, dtype=float))
        zero_of = lambda c: float(zarr[c])  # noqa: E731
    else:
        raise ValueError(f"zeroForce: one value for all channels or one value per channel ({len(channels)}) "
                         "expected.")
    if not labels:
        labels = [f"range{r + 1}" for r in range(nR)]
    labels = [labels] if isinstance(labels, str) else list(labels)
    if len(labels) != nR:
        raise ValueError(f"Number of labels ({len(labels)}) ~= number of ranges ({nR}).")
    if not quiet:
        print(f"{H.file}\n  {H.samplingRate:.0f} Hz ({H.samplingRateSource}), {len(dc)} channel(s) in file, "
              f"{H.totalSeconds:.1f} s")
        for note in H.notes:
            print(f"  note: {note}")

    # ------------------------------------------------------------------ analysis (chunks of <= chunkSeconds)
    pad = opts.maxBeatWindow + 2
    if opts.rockerFilter:
        pad = max(pad, 60)  # context for the estimate of the rocker artifact
    parts, sumParts, thrInfo, rfRows = [], [], [], []
    nFig = 0
    f0cache = np.zeros((0, 2))
    for r in range(nR):
        edges = np.unique(np.r_[colon(ranges[r, 0], chunkSeconds, ranges[r, 1]), ranges[r, 1]])
        nQ = edges.size - 1
        Bc = [[None] * nQ for _ in channels]
        Cs = [[None] * nQ for _ in channels]
        lastB = [None] * len(channels)
        lastC = [None] * len(channels)
        S = None
        for q in range(nQ):
            S = read_mdd(H, max(0.0, edges[q] - pad), edges[q + 1] + pad, opts)
            sub = [edges[q], edges[q + 1]]
            if q < nQ - 1:
                sub[1] -= 1e-9  # half-open chunks: no contraction twice
            if opts.rockerFilter:  # rocker artifact of all channels of this chunk at once
                oR = Struct(opts)
                if oR.rockerFrequency is None and f0cache.shape[0]:
                    oR.rockerFrequency = f0cache
                S, RFq = rocker_filter(S, channels, oR)
                if RFq and RFq[0].f0table.shape[0]:
                    ft = RFq[0].f0table[~np.isnan(RFq[0].f0table[:, 1])]
                    for row in ft:
                        same = (f0cache[:, 0] == row[0]) | (np.isnan(f0cache[:, 0]) & np.isnan(row[0]))
                        if f0cache.shape[0] == 0 or not same.any():
                            f0cache = np.r_[f0cache, row[None, :]]
            for c, ch in enumerate(channels):
                optsC = Struct(opts)
                optsC.zeroForce = zero_of(c)
                Bq, Cq = analyze_channel(S, ch, sub, optsC)
                Bc[c][q] = Bq
                lastB[c] = Bq
                lastC[c] = Cq
                Cs[c][q] = Struct({k: v for k, v in Cq.items() if k not in ("t", "f", "rockerArtifact")})
                thrInfo.append([r + 1, ch, edges[q], edges[q + 1], Cq.threshold, Cq.maxStimToPeak])
                if opts.rockerFilter and Cq.rockerFilter is not None:
                    RF = Cq.rockerFilter
                    rfRows.append([labels[r], ch, edges[q], edges[q + 1], RF.status, RF.f0, RF.artifactPP, RF.r2,
                                   100 * RF.correctedFraction, RF.message])
        for c, ch in enumerate(channels):
            B = pd.concat(Bc[c], ignore_index=True)
            B.attrs = dict(Bc[c][0].attrs)
            B["contraction"] = np.arange(1, len(B) + 1, dtype=float)
            CsC = Cs[c]
            Cm = Struct(CsC[0])
            st, sc = [], []
            for x in CsC:
                k = (x.stimTimes >= x.range[0]) & (x.stimTimes <= x.range[1])
                st.append(x.stimTimes[k]); sc.append(x.stimCaptured[k])
            Cm.stimTimes = np.concatenate(st)
            Cm.stimCaptured = np.concatenate(sc)
            Cm.threshold = float(np.median([x.threshold for x in CsC]))
            T = summarize(B, Cm, ranges[r])
            T.insert(0, "range", labels[r])
            sumParts.append(T)
            B.insert(0, "range", labels[r])
            parts.append(B)
            if not quiet:
                print(f"  {labels[r]}, channel {ch}: {len(B)} contractions detected, {int(B['included'].sum())} "
                      f"included (threshold {Cm.threshold:.0f} uN, {Cm.thresholdMode})")
                if opts.rockerFilter and rfRows:
                    msgs = []
                    for row in rfRows:
                        if row[0] == labels[r] and row[1] == ch:
                            import re
                            m = re.sub(r"^Rocker filter, channel \d+: ", "", row[9])
                            if m not in msgs:
                                msgs.append(m)
                    print("    rocker filter: " + " | ".join(msgs[:3]))
            if showFigures and nFig < 16 and nQ == 1:
                nFig += 1
                _plot_channel(lastC[c], lastB[c], S, ranges[r],
                              f"{os.path.basename(H.file)} - channel {ch} - {labels[r]}")
    thrInfo = sorted(thrInfo, key=lambda x: (x[0], x[1], x[2]))  # order: range, channel, time
    units = dict(parts[0].attrs.get("units", {})) if parts else {}
    contractions = pd.concat(parts, ignore_index=True)
    summary = pd.concat(sumParts, ignore_index=True)

    # absolute time of every contraction (if the log file contains the recording start)
    rs = H.recordingStart
    hasStart = rs is not None and not math.isnan(rs)
    clock = None
    if hasStart and len(contractions) > 0:
        clock = datenum_to_timestamps(rs + contractions["t_peak"].to_numpy() / 86400.0)
        contractions.insert(list(contractions.columns).index("t_peak") + 1, "clockTime", clock)
    summary.insert(0, "file", os.path.basename(H.file))

    # per-channel labels (metadata) as columns after 'channel'
    Lbl = make_labels(metadata, channels)
    contractions = add_labels(contractions, Lbl, list(clock) if clock is not None else None)
    if hasStart:
        mid = datenum_to_timestamps(rs + (summary["from"].to_numpy() + summary["to"].to_numpy()) / 2 / 86400.0)
        summary = add_labels(summary, Lbl, list(mid))
    else:
        summary = add_labels(summary, Lbl)
    contractions.attrs["units"] = units

    info = {k: v for k, v in H.items() if k not in ("totalSamples", "stimRow")}
    info["channels"] = channels
    info["ranges"] = ranges
    info["rangeLabels"] = labels
    info["labels"] = Lbl
    info["options"] = opts
    info["thresholds"] = pd.DataFrame(thrInfo, columns=["range", "channel", "from", "to", "threshold_uN",
                                                        "maxStimToPeak_s"])
    if opts.rockerFilter:
        RFT = pd.DataFrame(rfRows, columns=["range", "channel", "from_s", "to_s", "status", "rockerFrequency_Hz",
                                            "artifact_uN_peakToPeak", "artifactR2", "corrected_percentOfRockerOnTime",
                                            "message"])
        if len(RFT):
            gr = RFT["range"].map({lb: i for i, lb in enumerate(labels)})
            RFT = RFT.assign(_g=gr).sort_values(["_g", "channel", "from_s"], kind="stable").drop(columns="_g")
            RFT = RFT.reset_index(drop=True)
        info["rockerFilter"] = RFT
    info["analysisDate"] = _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    if output:
        write_results(output, contractions, summary, info)
        if not quiet:
            print(f"  results written to {output}")
    return contractions, summary, info


def _plot_channel(C, B, S, range_, ttl):
    try:
        import matplotlib.pyplot as plt
    except ImportError:  # pragma: no cover
        return
    fig, ax = plt.subplots(num=ttl, figsize=(12, 4))
    t = np.asarray(C.t)
    I = (t >= range_[0] - 2) & (t <= range_[1] + 2)
    f = np.asarray(C.f)
    yl = np.array([np.min(f[I]), np.max(f[I])])
    yl = yl + np.array([-0.05, 0.1]) * max(1, yl[1] - yl[0])
    rk = np.asarray(S.rockerOn)[I]
    tt = t[I]
    if rk.any():
        d = np.diff(np.r_[0, rk.astype(int), 0])
        for a, b in zip(np.flatnonzero(d == 1), np.flatnonzero(d == -1) - 1):
            ax.axvspan(tt[a], tt[b], color=(0.9, 0.9, 0.9), lw=0)
    ax.plot(t[I], f[I], "k", lw=0.8)
    st = C.stimTimes[(C.stimTimes >= range_[0] - 2) & (C.stimTimes <= range_[1] + 2)]
    ax.vlines(st, yl[0], yl[0] + 0.04 * (yl[1] - yl[0]), color="b")
    pk = {v: i for i, v in enumerate(C.peakTimes)}
    inc = B["included"].to_numpy()
    tp = B["t_peak"].to_numpy()
    yv = np.array([f[C.iPeaks[pk[x]]] for x in tp])
    ax.plot(tp[inc], yv[inc], "rv", mfc="r")
    ax.plot(tp[~inc], yv[~inc], "v", color=(0.5, 0.5, 0.5))
    ax.axvline(range_[0], color="g", ls="--")
    ax.axvline(range_[1], color="g", ls="--")
    ax.set_ylim(yl)
    ax.set_xlabel("time in file (s)")
    ax.set_ylabel("force (µN)")
    ax.set_title(f"{ttl}\n{int(inc.sum())} contractions included (red), grey = excluded, blue = stimuli, "
                 "shaded = rocker moving", fontsize=9)
    fig.tight_layout()
    plt.show(block=False)
