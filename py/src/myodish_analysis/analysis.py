"""Contraction parameters of every single contraction in a MyoDish recording (.mdd). Port of MyoDishAnalysis.m.

    contractions, summary, info = myodish_analysis(mdd_file, channels, from_s, to_s, **options)

mdd_file   .mdd file. The log file <name>_log.log must be in the same folder.
channels   data channels, e.g. 3 or [1, 2, 5] (None = all channels in the file)
from_s     start of the analysed time range in s (time in the file; negative = seconds before the end)
to_s       end of the time range. Lists define several ranges, e.g. from_s=[600, 3000], to_s=[660, 3060]

contractions  DataFrame, one row per detected contraction (also the excluded ones, see column 'included'); column
              'uncertain': contraction found with high sensitivity only (option detection, see options.py)
summary       DataFrame, one row per channel and range: numbers of contractions/stimuli, mean and SD of all
              parameters of the included contractions
info          dict: file facts, options, detection threshold per channel and range, notes; info['pulses'] (option
              pulseTable, default True; sheet / file 'pulses'): one row per stimulus pulse of the analysed channels and
              ranges (pulse ID, time, extra pulse, current, durations, outcome, role, contraction, coupling interval,
              time since the last onset, phase; see analyze_channel.pulse_table); with grouped protocols
              (FFR, ST, RP, PRP) info['protocolResults']: characteristic values per protocol and channel (see
              protocol_results.py), also sheet 'protocolResults' of the results file

OPTIONS (keywords)
  output='results.xlsx'   write the results (.xlsx: sheets contractions, summary, parameters, info; or .csv)
  labels=['baseline', 'drug']   names of the time ranges
  metadata=m              labels per channel (dict, DataFrame or .csv/.xlsx file), see labels.py
  showFigures=True        plot the signal with the detected contractions (matplotlib; ranges <= 30 min, <= 16)
  quiet=True              no messages
  settings='my.csv'       all options from a settings file (settings.py; GUI: Advanced ... -> Save settings ...) or from
                          the results of an earlier analysis; the other keywords override them
  rocker='stopped', beats='stimulated', threshold=300 (or [t1, t2, ...] per channel, NaN = auto),
  zeroForce=[z1, z2, ...], rockerFilter=True, referenceBeat=R and all other options of options()
  protocol='FFR'          analyse stimulation protocols found in the log file (find_protocols) instead of from_s / to_s:
                          a type ('FFR', 'RP', 'ST', 'PRP', 'PD', 'rockerSpeed'), 'all', row numbers (0-based) of
                          find_protocols(file), or a DataFrame like its output (e.g. corrected from / to). Range labels
                          'FFR 1', ... With a protocol, only contractions with the rocker at rest are included unless
                          rocker is given (grouping by rocker speed: all contractions).
  groupBy='pacingFrequency'  group the contractions by a stimulation quantity and summarize per group (group_beats):
                          pacingFrequency, S2interval, stimCurrent, pauseLength, rockerSpeed, pulseDuration,
                          'log:<code>', 'none'. Default with protocol: the quantity of the protocol type.

EXAMPLES
  T, S, info = myodish_analysis('examples/example3_humanVentricle.mdd', 6, 0, 120)
  T, S, info = myodish_analysis(f, [1, 2, 3], [600, 3000], [660, 3060], labels=['baseline', 'drug'],
                                    rocker='stopped', output='results.xlsx')
  T, S, info = myodish_analysis(f, None, protocol='FFR')                   # force-frequency protocol(s), per rate
  T, S, info = myodish_analysis(f, 1, protocol='RP', rocker='any')         # S2 intervals, all beats

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
from .protocol_results import RESULT_COLUMNS, protocol_results
from .protocols import add_empty_group_columns, find_protocols, group_beats
from .read_mdd import read_mdd
from .rocker_filter import rocker_filter
from .summarize import summarize
from .write_results import _mat2str15, _num15, write_results

DATENUM_1970 = 719529.0


def datenum_to_timestamps(dn):
    """MATLAB datenum(s) --> pandas datetime64 (NaN --> NaT)."""
    dn = np.asarray(dn, dtype=float)
    return pd.to_datetime((dn - DATENUM_1970) * 86400.0, unit="s")


def myodish_analysis(mdd_file, channels=None, from_s=0, to_s=math.inf, *, output=None, labels=None,
                         metadata=None, showFigures=False, quiet=False, chunkSeconds=1800, protocol=None, groupBy=None,
                         **opt_kw):
    rockerGiven = any(k.lower() == "rocker" for k in opt_kw)
    beatsGiven = any(k.lower() == "beats" for k in opt_kw)
    opts = make_options(**opt_kw)
    H = read_mdd(mdd_file, None, None, opts)
    protocols = None
    if protocol is not None:  # ranges = stimulation protocols of the log file
        if isinstance(protocol, pd.DataFrame):
            protocols = protocol.reset_index(drop=True)
        else:
            P = find_protocols(H)
            if isinstance(protocol, str):
                if protocol.lower() == "all":
                    protocols = P
                else:
                    sel = (P["type"].str.lower() == protocol.lower()) | (P["name"].str.lower() == protocol.lower())
                    protocols = P[sel.to_numpy(bool)].reset_index(drop=True)
            else:
                protocols = P.iloc[list(np.atleast_1d(protocol))].reset_index(drop=True)
            if len(protocols) == 0:
                found = ", ".join(f"{a} ({b})" for a, b in zip(P["type"], P["name"]))
                raise ValueError(f"No protocol '{protocol}' in the log file of {H.file}. Protocols found: {found}")
        from_s = protocols["from"].to_numpy(float)
        to_s = protocols["to"].to_numpy(float)
        if not labels:
            labels = [f"{t} {int(n)}" for t, n in zip(protocols["type"], protocols["number"])]
    nRanges = np.size(from_s)
    if groupBy is None and protocols is not None:
        groupByR = [str(g) for g in protocols["groupBy"]]
    elif groupBy is None:
        groupByR = ["none"] * nRanges
    else:
        groupByR = [str(groupBy)] * nRanges
    grouping = any(g.lower() != "none" for g in groupByR)
    if protocols is not None and not any(g.lower() == "rockerspeed" for g in groupByR):
        if not rockerGiven:
            opts.rocker = "stopped"  # protocols: contractions with the rocker at rest ...
        if not beatsGiven:
            opts.beats = "stimulated"  # ... that follow a stimulus
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
    # detection threshold per channel ('auto', one value, or one value per channel; NaN = auto)
    th = opts.threshold
    if isinstance(th, str) or np.size(th) == 1:
        thr_of = lambda c: th  # noqa: E731
    elif np.size(th) == len(channels):
        tarr = np.ravel(np.asarray(th, dtype=float))
        thr_of = lambda c: float(tarr[c])  # noqa: E731
    else:
        raise ValueError(f"threshold: 'auto', one value for all channels or one value per channel ({len(channels)}) "
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
    parts, sumParts, thrInfo, rfRows, resRows, pulseParts = [], [], [], [], [], []
    spikes = []  # spike artifacts removed (option spikeRemoval) in the analysed chunks: channel, from, to, size
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
        Sres = None  # S2interval results: data of the whole range (traces)
        for q in range(nQ):
            S = read_mdd(H, max(0.0, edges[q] - pad), edges[q + 1] + pad, opts)
            sp = np.asarray(S.get("spikes", np.zeros((0, 4))), float).reshape(-1, 4)
            if sp.shape[0]:  # within the chunk (the padding belongs to the neighbours), analysed channels
                ok = (sp[:, 1] >= edges[q]) & ((sp[:, 1] < edges[q + 1]) | (q == nQ - 1) & (sp[:, 1] <= edges[q + 1]))
                ok &= np.isin(sp[:, 0], np.asarray(channels, float))
                spikes.append(sp[ok])
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
                optsC.threshold = thr_of(c)
                Bq, Cq = analyze_channel(S, ch, sub, optsC)
                Bc[c][q] = Bq
                lastB[c] = Bq
                lastC[c] = Cq
                Cs[c][q] = Struct({k: v for k, v in Cq.items() if k not in ("t", "f", "rockerArtifact")})
                thrInfo.append([r + 1, ch, edges[q], edges[q + 1], Cq.threshold, Cq.maxStimToPeak,
                                max(0.0, edges[q] - pad), edges[q + 1] + pad])  # data window read (GUI: open results)
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
            Cm.stimTimes = _in_range_of(CsC, "stimTimes", "stimTimes")
            Cm.stimCaptured = _in_range_of(CsC, "stimCaptured", "stimTimes", bool)
            Cm.stimCapturedCertain = _in_range_of(CsC, "stimCapturedCertain", "stimTimes", bool)
            Cm.stimDuringContraction = _in_range_of(CsC, "stimDuringContraction", "stimTimes", bool)
            Cm.extraTimes = _in_range_of(CsC, "extraTimes", "extraTimes")
            Cm.extraElicited = _in_range_of(CsC, "extraElicited", "extraTimes", bool)
            Cm.threshold = float(np.median([x.threshold for x in CsC]))
            if opts.pulseTable:  # pulses of the range: contraction numbers of the whole range
                Pc = [x.get("pulses") for x in CsC]
                Pc = [x for x in Pc if x is not None and len(x) > 0]
                if Pc:
                    Pc = pd.concat(Pc, ignore_index=True)
                    pos = pd.Series(B["contraction"].to_numpy(float), index=B["t_peak"].to_numpy(float))
                    pos = pos[~pos.index.duplicated()]
                    Pc["contraction"] = Pc["t_peak"].map(pos).to_numpy(float)
                    Pc.insert(0, "range", labels[r])
                    pulseParts.append(Pc)
            if grouping and groupByR[r].lower() != "none":
                steadyN = 0  # FFR protocols: steady state per frequency (2026-10-10)
                if protocols is not None and str(protocols["type"].iloc[r]).upper() == "FFR":
                    steadyN = int(opts.steadyStateBeats)
                B, T, Z, gNotes = group_beats(H, B, Cm, ranges[r], groupByR[r], opts, return_stimuli=True,
                                              steady_n=steadyN, return_notes=True)
                for nt in gNotes:
                    H.notes.append("%s, channel %d: %s" % (labels[r], ch, nt))
                gb = groupByR[r].lower()
                if gb in ("pacingfrequency", "stimcurrent", "s2interval", "pauselength"):
                    trace = None
                    if gb == "s2interval":  # S2 response: traces of the whole range
                        if Sres is None:
                            Sres = read_mdd(H, max(0.0, ranges[r, 0] - 2), ranges[r, 1] + 2, opts)
                        optsC = Struct(opts)
                        optsC.zeroForce = zero_of(c)
                        optsC.threshold = thr_of(c)
                        _, Cx = analyze_channel(Sres, ch, ranges[r], optsC)
                        trace = dict(t=Cx.t, f=Cx.f, tR=Sres.t, rockerOn=Sres.rockerOn)
                    Rr = protocol_results(groupByR[r], T, Z, trace, opts)
                    pNote = str(protocols["note"].iloc[r]) if protocols is not None and "note" in protocols else ""
                    resRows.append(dict({"range": labels[r], "channel": ch, "from": float(ranges[r, 0]),
                                         "to": float(ranges[r, 1]), "groupBy": groupByR[r]}, **Rr,
                                        protocolNote=pNote))
            else:
                T = summarize(B, Cm, ranges[r])
                if grouping:  # same columns as the grouped ranges
                    B, T = add_empty_group_columns(B, T)
            T.insert(0, "range", labels[r])
            sumParts.append(T)
            B.insert(0, "range", labels[r])
            parts.append(B)
            if not quiet:
                print(f"  {labels[r]}, channel {ch}: {len(B)} contractions detected ({int(B['uncertain'].sum())} "
                      f"uncertain), {int(B['included'].sum())} included (threshold {Cm.threshold:.0f} uN, "
                      f"{Cm.thresholdMode})")
                if (opts.rocker == "stopped" and len(B) > 0 and not B["included"].any()
                        and B["rockerMoving"].astype(bool).all()):
                    print("    the rocker moved during every contraction: rocker='any' includes them")
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
    info["notes"] = list(H.notes)
    spikes = np.concatenate(spikes) if spikes else np.zeros((0, 4))
    if spikes.shape[0]:
        spikes = np.unique(spikes, axis=0)  # ranges that overlap: once
        cs, ns = np.unique(spikes[:, 0], return_counts=True)
        info["notes"].append("Spike artifacts removed (option spikeRemoval): %d (%s), largest %g AU." % (
            spikes.shape[0], ", ".join("channel %d: %d" % (c, k) for c, k in zip(cs, ns)), np.max(spikes[:, 3])))
    info["spikes"] = spikes
    if opts.pulseTable:  # all stimulus pulses of the analysed channels and ranges (2026-10-10)
        if pulseParts:
            info["pulses"] = pd.concat(pulseParts, ignore_index=True)
            from .analyze_channel import PULSE_UNITS
            info["pulses"].attrs["units"] = dict({"range": ""}, **PULSE_UNITS)
        else:
            info["pulses"] = pd.DataFrame()
    info["channels"] = channels
    info["ranges"] = ranges
    info["rangeLabels"] = labels
    info["protocols"] = protocols
    info["groupBy"] = groupByR
    info["labels"] = Lbl
    info["options"] = opts
    if resRows:
        PR = pd.DataFrame(resRows, columns=["range", "channel", "from", "to", "groupBy"] + RESULT_COLUMNS +
                          ["protocolNote"])
        PR.insert(0, "file", os.path.basename(H.file))
        if hasStart:
            PR = add_labels(PR, Lbl, list(datenum_to_timestamps(rs + (PR["from"].to_numpy() + PR["to"].to_numpy())
                                                                 / 2 / 86400.0)))
        else:
            PR = add_labels(PR, Lbl)
        info["protocolResults"] = PR
    info["thresholds"] = pd.DataFrame(thrInfo, columns=["range", "channel", "from", "to", "threshold_uN",
                                                        "maxStimToPeak_s", "windowFrom", "windowTo"])
    # 2026-10-09: rows of the info table (write_results) to reproduce the analysis (GUI: open results)
    info["extra"] = [("createdBy", "MyoDishAnalysis"), ("channels", _mat2str15(channels)),
                     ("chunkSeconds", _num15(chunkSeconds))]
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


def _in_range_of(CsC, field, time_field, dtype=float):
    """values of the field of all chunks (channel info of analyze_channel) whose times lie in the chunk's range"""
    parts = []
    for x in CsC:
        if field not in x or time_field not in x or x[field] is None:
            continue
        tt = np.asarray(x[time_field], float).ravel()
        y = np.asarray(x[field]).ravel()
        parts.append(y[(tt >= x.range[0]) & (tt <= x.range[1])])
    return np.concatenate(parts).astype(dtype) if parts else np.zeros(0, dtype)


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
