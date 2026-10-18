# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Contraction parameters in time windows before and after a treatment (e.g. a substance added at a known clock time),
from the results of the watcher. Port of mda_timepoints.m (same arguments, files and values; images as .png and .svg
instead of .png and .fig).

    TP = timepoints(results_folder, label, series, channels, time, offsets)
    TP = timepoints(results_folder, label, series, channels, time, offsets, seconds=120,
                    parameters=(...), baseline=None, write=True, figures=True)

    TP = timepoints("/data/results", "Mava100", "Setup1_ABC000101", [1, 3, 5], "2000-01-01 15:20",
                    [-10, 10, 60, 240, 1440])
        channels 1, 3 and 5 of the setup 1 (recordings Setup1_ABC000101_<n>.mdd), substance added at 15:20: windows
        of 120 s starting 10 min before and 10 min, 1 h, 4 h and 24 h after
    TP = timepoints(res, "Ome2uM", ["Setup1_ABC000101", "Setup2_ABC000101"], [[1, 2, 0], [4, 5, 6]],
                    ["2000-01-01 13:20:00", "2000-01-01 13:30:00"], [-60, 120], 300)
        two setups (channels 1 and 2 of setup 1, 4 to 6 of setup 2), one time per setup, windows of 300 s

Inputs
  results_folder  results folder of the watcher (watch(raw_folder, results_folder): the folder with mda_index.csv) or
                  a folder in it (e.g. the folder of the experiment)
  label           name of the treatment, e.g. 'Mava100' (letters, digits, '.', '-', '_'): name of the output folder
  series          recordings of one setup: the file name up to its number ('Setup1_ABC000101' for
                  Setup1_ABC000101_3.mdd); several series as a list
  channels        None or [] = all channels with contractions in the windows; a list of channels (the same in every
                  series); a matrix with one row per series (0 or NaN = no channel), or a list with one list (or
                  number) per series, e.g. [[1, 2], 3] (a flat list such as [1, 3] means channels 1 and 3 of every
                  series)
  time            clock time of the treatment: datetime / Timestamp or text ('yyyy-mm-dd HH:MM[:SS]' or
                  'dd.mm.yyyy HH:MM[:SS]'); one time for all channels, one per series (list), or one per channel (a
                  matrix of the shape of the channel matrix, or one per channel in the order of the channels, series by
                  series)
  offsets         start of the windows in minutes after the treatment (required, negative = before), e.g. [-60, 120]
  seconds         duration of every window in s (default 120)
Options: parameters (default amplitude, diastolicForce, TTP90, TTR90, CD50, CD90, dFdtMax, dFdtMin, AUC,
beatsPerMinute, see PARAMETERS; CD90 = 10 % upstroke to 90 % relaxation = TTP90 + TTR90 of the beat; dFdtMax and dFdtMin
in mN/s (the analysis: uN/s), also in the sheets beats and course; beatsPerMinute = all contractions of the window per
minute), baseline (offset of the reference window of pctBaseline; default the last
negative offset; NaN: none), write (default True), figures (default True, with write), average_beats (default True;
needs the recordings, read only), raw_folder (raw folder of the watcher: recordings at <raw_folder>/<path in
mda_index.csv>; default: the path of the analysis, info sheet 'file'), sampleID (sample of the slices: one text or one
per series; default: the slice register, else the series name after the setup: Setup1_ABC000101 --> ABC000101; for
pool_timepoints), group (group of the sample, e.g. 'HTX': one text or one per series; default '').

Windows start exactly at time + offset and last `seconds` ([start, start + seconds), clock time of the peak of the
contraction); they are never shifted. Values per window of the included contractions (column included, all beat types):
mean (column <parameter>), SD, SEM (SD / sqrt(n)), median, quartiles (q25, q75); nBeats (all contractions), nIncluded,
nExtra (extra beats); normalized to the baseline window of the same channel: <parameter>_pctBaseline = 100 * mean / mean
of the baseline window, for the diastolic force the absolute change diastolicForce_delta = mean - mean of the baseline
window (uN; a diastolic force near 0 or negative has no meaningful % of baseline). Windows without contractions although
recorded (no gap of the signal): the slice does not contract: amplitude, AUC, dFdtMax, dFdtMin and beatsPerMinute 0,
TTP90, TTR90, CD50, CD90 NaN, the diastolic force from the signal (median of the force filtered as in the analysis -
zero force; needs the recording; note 'diastolic force from the signal'). Notes (column note): stimulation protocols,
periods without signal (gaps of the watcher), user comments in the window, fewer than 80 % of the expected contractions
included (expected = seconds x median stimulation or beat frequency of the window), another slice than in the baseline
window (slice register; then no pctBaseline), a baseline window that ends after the treatment, windows without
recording, and 'pending: no data yet' for windows after the end of the analysed recordings (call again after the next
pass of the watcher), and two amplitude groups of the included beats (1-D 2-means: each group >= 20 % of the beats,
means >= 20 % and >= 3 SD apart): 'alternans: 2 amplitude groups ...' if >= 80 % of successive beats switch the group,
otherwise 'irregular amplitudes: 2 groups ...'; mean and median then describe neither group, see the average beats.
Parallel recordings of a main file are not used twice.

Average beats (2026-10-15): the included beats of a window without extra beats and without another contraction in the
segment, aligned at the stimulus (unpaced: at the onset), from 0.1 s before to the next beat - 0.05 s (shortest beat
interval of the windows, at most 4 s), raw force of the recording (read_mdd) - zero force of the channel (summary),
filtered as in the analysis (moving median and mean, options of the analysis), on a 2-ms grid, averaged; with alternans
also the small and the large beats separately. Columns force_uN (absolute: the diastolic force is kept),
norm_baselineAmplitude ((F - diastole of the baseline average beat) / its amplitude: the baseline beat goes from 0 to 1,
the other windows show the change of amplitude and diastole on this scale; comparable between slices) and
norm_ownAmplitude ((F - own diastole) / own amplitude + (own diastole - baseline diastole) / baseline amplitude: every
beat has the amplitude 1 and keeps its diastolic change against the baseline, e.g. omecamtiv mecarbil; without baseline
window: own diastole = 0); diastole = mean of the 0.1 s before the stimulus. Every column with its standard error
(..._SE: SD of the beats / sqrt(n)). Summary: nAvgBeats, avgBeat_diastolic, avgBeat_amplitude (uN).

Output files (folder of the experiment in the results folder: <experiment>/timepoints/<label>_<yyyy-mm-dd-HH-MM>/,
time = the earliest treatment time; several experiments: one folder each; files of the same name are replaced, the
watcher never changes these folders):
  <label>_<time>.xlsx  sheets summary (one row per series, channel and window: counts, note, per parameter mean and
      pctBaseline (diastole: delta), then per parameter SD and SEM, median, q25, q75, then the average beat: nAvgBeats,
      avgBeat_diastolic, avgBeat_amplitude), matrix (per parameter the means and pctBaseline: one row per series and
      channel, one column per offset), course (1-min values of the overview of the watcher from 30 min before the first
      to 30 min after the last window; median per minute of the included contractions, extra beats excluded; normalized
      with the medians of the baseline window), beats (all contractions of the windows; more than 1 million rows:
      <label>_<time>_beats.csv), averageBeats (series, channel, offset_min, trace = all / small beats / large beats,
      nBeats, t_s, force_uN, norm_baselineAmplitude, norm_ownAmplitude, each with ..._SE), averageBeatsMean (mean, SD
      and SE of the channels per window: force, baseline amplitude = 1, own amplitude = 1) and info (call, version,
      recordings used, notes)
  images, each absolute (_abs) and normalized to the baseline window (_norm; not without baseline window):
  <label>_<time>_timepoints_abs / _norm.png / .svg  per parameter over the windows: mean +- SEM of the beats (abs) or
      pctBaseline (norm), one line per channel, black = mean +- SEM of the channels
  <label>_<time>_course_abs / _norm.png / .svg  per parameter the 1-min course relative to the treatment (values or
      pctBaseline), one line per channel, black = mean +- SEM of the channels, windows grey, treatment = dashed line
  <label>_<time>_averageBeats_abs / _norm.png / .svg  one panel per channel: force (uN; abs), or one row per channel:
      baseline amplitude = 1, own amplitude = 1 (norm; without baseline: own amplitude); +- SE shaded, one color per
      window (baseline black), alternans groups dashed
  <label>_<time>_averageBeatsMean_abs / _norm.png / .svg  mean +- SE of the channels (force; baseline amplitude = 1,
      own amplitude = 1)
  averageBeats/<series>_ch<c>.png / .svg  one 16:9 slide per channel (for presentations): average beats +- SE in uN
      and with the own amplitude = 1, table of the values per window (n, amplitude, diastolic force, TTP90, TTR90 and
      their change against the baseline, note)

Returns a dict with the same data: label, time (earliest treatment time), offsets, seconds, baseline (offset, NaN =
none), parameters, units, rows (DataFrame series, channel, sampleID, group, time, experiment: one row per channel = rows
of the matrices), summary, matrix[parameter] (means) and pctBaseline[parameter] (normalized; diastolicForce:
delta in uN) (channels x offsets, numpy arrays), course, beats, averageBeats, averageBeatsMean, notes, info, folder
(str; list for several experiments), files. Several analyses (experiments, samples) by treatment: pool_timepoints.

TS 2026-10-15 (average beats, alternans, standard errors, slides per channel 2026-10-15; means, SD, SEM, CD90, dF/dt,
AUC, diastolic force as change in uN, windows without contractions, images absolute and normalized 2026-10-16)
"""
from __future__ import annotations

import datetime as _dt
import math
import os
import re

import numpy as np
import pandas as pd

from .parameters import PARAMETERS
from .write_results import mda_version

DEFAULT_PARAMETERS = ("amplitude", "diastolicForce", "TTP90", "TTR90", "CD50", "CD90", "dFdtMax", "dFdtMin", "AUC",
                      "beatsPerMinute")


def timepoints(results_folder, label, series, channels, time, offsets, seconds=120.0, parameters=DEFAULT_PARAMETERS,
               baseline=None, write=True, figures=True, average_beats=True, raw_folder="", sampleID="", group=""):
    """Contraction parameters in time windows around a treatment; see the module documentation."""
    from .watch import read_index, results_of

    sec = seconds
    if not (_is_number(sec) and math.isfinite(float(sec)) and float(sec) > 0):
        raise ValueError("timepoints: seconds: a positive number expected.")
    sec = float(sec)
    label = str(label)
    if not re.fullmatch(r"[A-Za-z0-9._-]+", label):
        raise ValueError("timepoints: label: letters, digits, '.', '-' and '_' expected (name of the output folder).")
    off = np.atleast_1d(np.asarray(offsets, float)).ravel() if offsets is not None else np.zeros(0)
    if off.size == 0 or not np.all(np.isfinite(off)):
        raise ValueError("timepoints: offsets: minutes after the treatment expected, e.g. [-60, 120].")
    if np.unique(off).size < off.size:
        raise ValueError("timepoints: offsets: each offset only once.")
    pars = [parameters] if isinstance(parameters, str) else [str(p) for p in parameters]
    if not pars:
        raise ValueError("timepoints: parameters: at least one parameter expected.")
    base_off = _baseline_offset(baseline, off)
    S = [series] if isinstance(series, str) else [str(s).strip() for s in series]
    S = [s.strip() for s in S]
    if not S or any(not s for s in S):
        raise ValueError("timepoints: series: name(s) of the series expected.")
    pS, pC, pT, all_ch = _expand_pairs(S, channels, time)
    smp_s, grp_s = _label_per_series(sampleID, S, "sampleID"), _label_per_series(group, S, "group")

    res = _index_folder(results_folder)
    X = read_index(res)
    recs = {s: _series_recordings(res, X, s, results_of) for s in S}
    for s_ in S:
        recs[s_]["raw"] = str(raw_folder or "")
    cache, raw_cache, ab_notes = {}, {}, []
    if any(all_ch):
        pS, pC, pT = _all_channels(pS, pC, pT, all_ch, recs, off, sec, pars, cache)
    nP, nK = len(pS), off.size
    if nP == 0:
        raise ValueError("timepoints: no channel with contractions in the windows.")
    pSmp = [smp_s[S.index(s)] for s in pS]  # sample ID and group of the channels ('' = from the data)
    pGrp = [grp_s[S.index(s)] for s in pS]
    units = _units(pars)

    # windows
    kb = None if base_off is None else int(np.flatnonzero(off == base_off)[0])
    M = np.full((nP, nK, len(pars)), np.nan)  # means (main values)
    Med = M.copy()  # medians (normalization of the course)
    rows, bparts, abparts, used = [], [], [], []
    reg_cache = {}
    for p in range(nP):
        R = recs[pS[p]]
        slice_k = np.full(nK, np.nan)
        prow = []
        Wb = [None] * nK  # included beats of the windows (average beats)
        for k in range(nK):
            a0 = pT[p] + pd.Timedelta(minutes=float(off[k]))
            b0 = a0 + pd.Timedelta(seconds=sec)
            notes, parts, names = [], [], []
            inR = [j for j in range(len(R["rel"])) if R["start"][j] < b0 and R["stop"][j] > a0]
            for j in inR:
                D = _recording_data(cache, R, j, pars)
                names.append(R["name"][j])
                used.append(R["rel"][j])
                C = D["C"]
                parts.append(C[(C["channel"] == pC[p]) & (C["clock"] >= a0) & (C["clock"] < b0)].assign(rec_=j))
                notes += _window_notes(D, pC[p], a0, b0)
                if "contractions=thinned" in R["options"][j]:
                    notes.append("thinned contractions")
            if not inR:
                notes.append("pending: no data yet" if not R["stop"] or a0 >= max(R["stop"]) else "no recording")
            elif (a0 < min(R["start"][j] for j in inR) or b0 > max(R["stop"][j] for j in inR)
                  or _coverage_gap(R, inR, a0, b0)):
                notes.append("window partly without recording")
            C = pd.concat(parts, ignore_index=True) if parts else _empty_contractions(pars).assign(rec_=0)
            C = C.sort_values("clock", kind="mergesort").reset_index(drop=True)
            nB = len(C)
            inc = C["included"].to_numpy(float) == 1
            nI = int(inc.sum())
            nE = int((C["beatType"].astype(str) == "extra").sum())
            f = _nanmedian(C["stimFrequency"].to_numpy(float))
            if math.isnan(f):
                f = _nanmedian(C["peakToPeakFrequency"].to_numpy(float))
            if not math.isnan(f) and f > 0 and nI < 0.8 * sec * f:
                notes.append(f"{nI} of ~{_mround(sec * f)} expected contractions included")
            if nB == 0 and inR:
                notes.append("no contractions")
            if kb is not None and k == kb and b0 > pT[p]:
                notes.append("baseline window ends after the treatment")
            ib = inc & (C["beatType"].astype(str).to_numpy() != "extra")  # alternans: two amplitude groups
            grp, atxt = _alternans_groups(C["amplitude"].to_numpy(float)[ib])
            if atxt:
                notes.append(atxt)
            al = C["t_stim"].to_numpy(float)[ib]
            u = np.isnan(al)
            al[u] = C["t_onset"].to_numpy(float)[ib][u]  # unpaced: onset
            Wb[k] = pd.DataFrame({"j": C["rec_"].to_numpy()[ib].astype(int), "align": al,
                                  "tpeak": C["t_peak"].to_numpy(float)[ib], "grp": grp})
            slice_k[k], sid = _slice_at(res, R, pS[p], pC[p], a0, reg_cache)
            if not pSmp[p] and sid:
                pSmp[p] = sid  # sample ID of the slice register
            vals, sdv, sem, med, q25, q75 = (np.full(len(pars), np.nan) for _ in range(6))
            for i, par in enumerate(pars):
                if par == "beatsPerMinute":
                    if inR:
                        vals[i] = med[i] = nB / sec * 60
                else:
                    x = C[par].to_numpy(float)[inc]
                    x = x[~np.isnan(x)]
                    if x.size:
                        vals[i], med[i] = float(np.mean(x)), float(np.median(x))
                        q25[i], q75[i] = _prctile(x, 25), _prctile(x, 75)
                        if x.size > 1:
                            sdv[i] = float(np.std(x, ddof=1))
                            sem[i] = sdv[i] / math.sqrt(x.size)
            # no contractions although recorded (no gap of the signal in the window): the slice does not contract:
            # amplitude, AUC, dF/dt and beatsPerMinute 0, times NaN, diastolic force from the signal (median of the
            # filtered force - zero force; needs the recording)
            if nB == 0 and inR and "window partly without recording" not in notes and \
                    not _signal_gap(R, inR, cache, pC[p], a0, b0, pars):
                z = np.array([q in ("amplitude", "AUC", "dFdtMax", "dFdtMin") for q in pars])
                vals[z] = med[z] = q25[z] = q75[z] = 0.0
                if "diastolicForce" in pars:
                    i_ = pars.index("diastolicForce")
                    v, nt = _signal_force(R, inR, cache, raw_cache, int(pC[p]), a0, b0, pars)
                    ab_notes += nt
                    if not math.isnan(v):
                        vals[i_] = med[i_] = v
                        notes.append("diastolic force from the signal")
            M[p, k, :], Med[p, k, :] = vals, med
            row = {"series": pS[p], "channel": int(pC[p]), "sampleID": "", "group": pGrp[p],
                   "time": _clock_text(pT[p]), "offset_min": _num(off[k]),
                   "from": _clock_text(a0), "to": _clock_text(b0), "recording": ";".join(_unique(names)),
                   "slice": slice_k[k], "nBeats": nB, "nIncluded": nI, "nExtra": nE,
                   "note": "; ".join(_unique(notes)), "nAvgBeats": 0, "avgBeat_diastolic": np.nan,
                   "avgBeat_amplitude": np.nan}
            for i, par in enumerate(pars):
                row[par], row[_norm_name(par)] = vals[i], np.nan
                row[par + "_SD"], row[par + "_SEM"] = sdv[i], sem[i]
                row[par + "_median"], row[par + "_q25"], row[par + "_q75"] = med[i], q25[i], q75[i]
            prow.append(row)
            if nB > 0:
                B = C.drop(columns=["clock", "rec_"]).copy()
                B = B.drop(columns=["channel"])
                B.insert(0, "window_from", _clock_text(a0))
                B.insert(0, "offset_min", _num(off[k]))
                B.insert(0, "channel", int(pC[p]))
                B.insert(0, "series", pS[p])
                bparts.append(B)
        if not pSmp[p]:  # sample ID: option, slice register, or the series name after the setup
            pSmp[p] = _series_sample(pS[p])
        for k in range(nK):
            prow[k]["sampleID"] = pSmp[p]
            other = (kb is not None and not math.isnan(slice_k[k]) and not math.isnan(slice_k[kb])
                     and slice_k[k] != slice_k[kb])
            if other:
                prow[k]["note"] = _join_note(prow[k]["note"], "other slice than in the baseline window")
            if kb is None or other:
                continue
            for i, par in enumerate(pars):  # pctBaseline; diastolicForce: change in uN
                if par == "diastolicForce":
                    prow[k][_norm_name(par)] = M[p, k, i] - M[p, kb, i]
                else:
                    prow[k][_norm_name(par)] = _div(100 * M[p, k, i], M[p, kb, i])
        if average_beats:  # average beats (raw data of the recordings)
            T_, st, nt = _pair_average_beats(pS[p], int(pC[p]), Wb, off, kb, R, pars, cache, raw_cache)
            ab_notes += nt
            abparts.append(T_)
            for k in range(nK):
                prow[k]["nAvgBeats"], prow[k]["avgBeat_diastolic"], prow[k]["avgBeat_amplitude"] = (
                    int(st["n"][k]), st["dia"][k], st["amp"][k])
        rows += prow
    summary = pd.DataFrame(rows, columns=_summary_columns(pars))
    Pct = np.full((nP, nK, len(pars)), np.nan)
    for i, par in enumerate(pars):
        Pct[:, :, i] = summary[_norm_name(par)].to_numpy(float).reshape(nP, nK)
    beats = pd.concat(bparts, ignore_index=True) if bparts else pd.DataFrame()
    abparts = [x for x in abparts if len(x)]
    AB = pd.concat(abparts, ignore_index=True) if abparts else _ab_template()

    # course
    cparts = []
    for p in range(nP):
        R = recs[pS[p]]
        a0 = pT[p] + pd.Timedelta(minutes=float(off.min()) - 30)
        b0 = pT[p] + pd.Timedelta(minutes=float(off.max()) + 30) + pd.Timedelta(seconds=sec)
        parts = []
        for j in range(len(R["rel"])):
            if R["start"][j] < b0 and R["stop"][j] > a0:
                Ov = _recording_data(cache, R, j, pars)["Ov"]
                O = Ov[(Ov["channel"] == pC[p]) & (Ov["clock"] >= a0) & (Ov["clock"] < b0)]
                if len(O):
                    parts.append(O)
        if not parts:
            continue
        O = pd.concat(parts, ignore_index=True).sort_values("clock", kind="mergesort").reset_index(drop=True)
        n = len(O)
        mins = ((O["clock"] - pT[p]).dt.total_seconds().to_numpy(float) / 60)
        T = pd.DataFrame({"series": [pS[p]] * n, "channel": [int(pC[p])] * n, "time": [_clock_text(pT[p])] * n,
                          "window": O["clock"].dt.strftime("%Y-%m-%d %H:%M:%S").to_list(),
                          "minutes": np.round(mins * 1e6) / 1e6, "nBeats": O["nBeats"].to_numpy(float)})
        for i, par in enumerate(pars):  # normalized with the medians of the baseline window
            v = O[par].to_numpy(float)
            T[par] = v
            with np.errstate(divide="ignore", invalid="ignore"):
                if kb is None:
                    T[_norm_name(par)] = np.nan
                elif par == "diastolicForce":
                    T[_norm_name(par)] = v - Med[p, kb, i]
                else:
                    T[_norm_name(par)] = 100 * v / Med[p, kb, i]
        cparts.append(T)
    course = pd.concat(cparts, ignore_index=True) if cparts else _course_template(pars)

    exps = [recs[s]["experiment"] for s in pS]
    TP = {"label": label, "time": _clock_text(min(pT)), "offsets": off.copy(), "seconds": sec,
          "baseline": np.nan if kb is None else float(off[kb]), "parameters": pars, "units": units,
          "rows": pd.DataFrame({"series": pS, "channel": [int(c) for c in pC], "sampleID": pSmp, "group": pGrp,
                                "time": [_clock_text(t) for t in pT], "experiment": exps}),
          "summary": summary, "matrix": {par: M[:, :, i].copy() for i, par in enumerate(pars)},
          "pctBaseline": {par: Pct[:, :, i].copy() for i, par in enumerate(pars)}, "course": course,
          "beats": beats, "averageBeats": AB, "averageBeatsMean": _average_beats_mean(AB, off),
          "notes": _unique(ab_notes)}
    used = _unique(used)
    TP["info"] = _info_table(TP, res, used)
    TP["folder"], TP["files"] = "", []
    if not write:
        return TP

    folders = []
    for e in _unique(exps):
        sel = np.array([x == e for x in exps])
        t0 = min(t for t, s in zip(pT, sel) if s)
        base = f"{label}_{t0.strftime('%Y-%m-%d-%H-%M')}"
        d = os.path.join(res, *(e.split("/") if e else []), "timepoints", base)
        os.makedirs(d, exist_ok=True)
        folders.append(d)
        Te = _subset(TP, sel, nK)
        Te["info"] = _info_table(Te, res, _used_of(used, list(Te["rows"]["series"])))
        TP["files"] += _write_files(d, base, Te, bool(figures))
    TP["folder"] = folders[0] if len(folders) == 1 else folders
    return TP


# ------------------------------------------------------------------------------------------------------------ inputs
def _is_number(x):
    return isinstance(x, (int, float, np.integer, np.floating)) and not isinstance(x, bool)


def _num(x):
    x = float(x)
    return int(x) if x == int(x) else x


def _mround(x):
    """MATLAB round (half away from zero)"""
    return int(math.floor(abs(x) + 0.5) * (1 if x >= 0 else -1))


def _baseline_offset(b, off):
    if b is None:
        neg = off[off < 0]
        return float(neg.max()) if neg.size else None
    if _is_number(b) and math.isnan(float(b)):
        return None
    if _is_number(b) and np.any(off == float(b)):
        return float(b)
    raise ValueError("timepoints: baseline: one of the offsets expected.")


def _expand_pairs(S, channels, time):
    """one element per channel: series, channel (NaN = all channels of the series, filled later), time"""
    nS = len(S)
    T, Tshape = _to_time(time)
    M = None
    if channels is None or (not _is_number(channels) and len(np.atleast_1d(np.asarray(channels, dtype=object))) == 0):
        rows, empty = [None] * nS, True
    else:
        empty = False
        if _is_number(channels):
            rows = [[float(channels)]] * nS
            if nS == 1:
                M = np.array([[float(channels)]])
        elif isinstance(channels, (list, tuple)) and nS > 1 and len(channels) == nS and \
                any(isinstance(c, (list, tuple, np.ndarray)) for c in channels):
            rows = [[float(v) for v in np.atleast_1d(np.asarray(c, float))] for c in channels]
            lens = {len(r) for r in rows}
            if len(lens) == 1:
                M = np.array(rows, float)
        else:
            A = np.asarray(channels, float)
            if A.ndim == 2 and nS > 1 and A.shape[0] == nS:
                M = A
                rows = [list(A[i]) for i in range(nS)]
            elif A.ndim <= 1 or 1 in A.shape:
                v = list(A.ravel())
                rows = [v] * nS
                if nS == 1:
                    M = A.reshape(1, -1)
            else:
                raise ValueError("timepoints: channels: [], a list, a matrix with one row per series or a list of "
                                 "lists expected.")
    pS, pC, idx, all_ch = [], [], [], []
    for i in range(nS):
        if empty:
            pS.append(S[i]); pC.append(np.nan); all_ch.append(True); idx.append(None)
            continue
        for j, c in enumerate(rows[i]):
            if c is None or math.isnan(c) or c == 0:
                continue
            if c < 1 or c != round(c):
                raise ValueError("timepoints: channels: channel numbers 1, 2, ... expected.")
            if any(s == S[i] and x == int(c) for s, x in zip(pS, pC)):
                raise ValueError(f"timepoints: channels: channel {int(c)} of {S[i]} given twice (one channel per "
                                 "series: a list with one list per series, e.g. [[1], [1]]).")
            pS.append(S[i]); pC.append(int(c)); all_ch.append(False)
            idx.append((min(i, M.shape[0] - 1), j) if M is not None else None)
    if not pS:
        raise ValueError("timepoints: channels: no channel given.")
    sidx = [S.index(s) for s in pS]
    nT = len(T)
    if nT == 1:
        pT = [T[0]] * len(pS)
    elif M is not None and not any(all_ch) and Tshape == M.shape:
        Tm = np.empty(Tshape, dtype=object)
        Tm.ravel()[:] = T
        pT = [Tm[i] for i in idx]
    elif not any(all_ch) and nT == len(pS):
        pT = list(T)
    elif nT == nS:
        pT = [T[i] for i in sidx]
    else:
        raise ValueError("timepoints: time: one time, one per series or one per channel (the shape of the channel "
                         "matrix) expected.")
    if any(t is None or pd.isna(t) for t in pT):
        raise ValueError("timepoints: time: a clock time is missing.")
    return pS, pC, pT, all_ch


def _to_time(x):
    """list of Timestamps (row-major) and the shape of the input"""
    if isinstance(x, (str, _dt.datetime, pd.Timestamp, np.datetime64)):
        return [_one_time(x)], (1, 1)
    A = np.asarray(x, dtype=object)
    shape = A.shape if A.ndim == 2 else (1, A.size)
    return [_one_time(v) for v in A.ravel()], shape


def _one_time(v):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return pd.NaT  # no channel at this position of the matrix
    if isinstance(v, (pd.Timestamp, _dt.datetime, np.datetime64)):
        return pd.Timestamp(v)
    s = str(v).strip().replace("T", " ")
    if not s:
        return pd.NaT
    for fm in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%d.%m.%Y %H:%M:%S", "%d.%m.%Y %H:%M", "%Y-%m-%d %H:%M:%S.%f"):
        try:
            return pd.Timestamp(_dt.datetime.strptime(s, fm))
        except ValueError:
            pass
    raise ValueError(f"timepoints: time '{s}': 'yyyy-mm-dd HH:MM[:SS]' or 'dd.mm.yyyy HH:MM[:SS]' expected.")


def _index_folder(f):
    """the results folder of the watcher: f or the first parent folder with mda_index.csv"""
    d = os.path.realpath(str(f))
    start = d
    while True:
        if os.path.isfile(os.path.join(d, "mda_index.csv")):
            return d
        up = os.path.dirname(d)
        if not up or up == d:
            raise ValueError(f"timepoints: no mda_index.csv in {start} or its parent folders (results folder of the "
                             "watcher).")
        d = up


def _series_info(name):
    """series, number and main recording (nothing after the number) of a file name"""
    p = name.split("_")
    for i in range(1, len(p)):
        if re.fullmatch(r"\d+", p[i]):
            return "_".join(p[:i]), float(p[i]), i == len(p) - 1
    return name, math.nan, True


def _series_recordings(res, X, series, results_of):
    """analysed recordings of the series in the order of their start"""
    from .watch import result_table
    R = {"rel": [], "name": [], "dir": [], "num": [], "main": [], "options": [], "start": [], "stop": [],
         "experiment": ""}
    for _, r in X.iterrows():
        if not str(r["status"]).startswith("ok"):
            continue
        rel = str(r["file"]).replace("\\", "/")
        n = re.sub(r"\.mdd$", "", rel.rsplit("/", 1)[-1], flags=re.I)
        s, num, main = _series_info(n)
        if s != series:
            continue
        d, _ = results_of(res, rel)
        t1, t2 = _recording_span(result_table(d, n, "info"))
        if t1 is None:
            continue
        R["rel"].append(rel); R["name"].append(n); R["dir"].append(d); R["num"].append(num)
        R["main"].append(main); R["options"].append(str(r["options"])); R["start"].append(t1); R["stop"].append(t2)
        R["experiment"] = rel.rpartition("/")[0]
    if not R["rel"]:
        raise ValueError(f"timepoints: no analysed recording of the series {series} in {res}.")
    keep = [not (not R["main"][i] and any(R["main"][j] and R["num"][j] == R["num"][i] for j in range(len(R["rel"]))))
            for i in range(len(R["rel"]))]
    k = [i for i in range(len(R["rel"])) if keep[i]]
    k = sorted(k, key=lambda i: R["start"][i])
    for f in ("rel", "name", "dir", "num", "main", "options", "start", "stop"):
        R[f] = [R[f][i] for i in k]
    return R


def _info_value(I, key):
    if I is None or "key" not in I.columns or "value" not in I.columns:
        return None
    v = I.loc[I["key"].astype(str) == key, "value"]
    return None if v.empty else v.iloc[0]


def _recording_span(I):
    s, L = _info_value(I, "recordingStart"), _info_value(I, "fileLength_s")
    try:
        L = float(L)
    except (TypeError, ValueError):
        return None, None
    t1 = _parse_clock(pd.Series([s])).iloc[0] if s is not None else pd.NaT
    if pd.isna(t1) or math.isnan(L):
        return None, None
    return t1, t1 + pd.Timedelta(seconds=L)


def _recording_data(cache, R, j, pars):
    """contractions, protocols, gaps, comments and overview of recording j (read once)"""
    from .watch import result_table
    key = R["rel"][j]
    if key in cache:
        return cache[key]
    d, n = R["dir"][j], R["name"][j]
    pc = [p for p in pars if p != "beatsPerMinute"]
    cc = _unique(["channel", "clockTime", "beatType", "included", "stimFrequency", "peakToPeakFrequency", "t_stim",
                  "t_onset", "t_peak", "amplitude"] + pc)
    C = result_table(d, n, "contractions", usecols=lambda c: c in cc)
    C = _standard_contractions(C, pars)
    rs = R["start"][j]
    I = result_table(d, n, "info")
    s = _info_value(I, "recordingStart")
    if s is not None:
        t = _parse_clock(pd.Series([s])).iloc[0]
        if not pd.isna(t):
            rs = t
    Pr = result_table(d, n + "_protocols", "protocols")
    if Pr is None or not {"name", "from", "to"} <= set(Pr.columns):
        Pr = pd.DataFrame({"name": pd.Series([], dtype=object), "a": pd.Series([], dtype="datetime64[ns]"),
                           "b": pd.Series([], dtype="datetime64[ns]")})
    else:
        Pr = pd.DataFrame({"name": Pr["name"].astype(str),
                           "a": rs + pd.to_timedelta(pd.to_numeric(Pr["from"], errors="coerce"), unit="s"),
                           "b": rs + pd.to_timedelta(pd.to_numeric(Pr["to"], errors="coerce"), unit="s")})
    G = result_table(d, n, "gaps")
    if G is None or not {"channel", "clockFrom", "clockTo", "type"} <= set(G.columns):
        G = pd.DataFrame({"channel": pd.Series([], dtype=float), "a": pd.Series([], dtype="datetime64[ns]"),
                          "b": pd.Series([], dtype="datetime64[ns]"), "type": pd.Series([], dtype=object)})
    else:
        G = pd.DataFrame({"channel": pd.to_numeric(G["channel"], errors="coerce").to_numpy(float),
                          "a": _parse_clock(G["clockFrom"]).to_numpy(), "b": _parse_clock(G["clockTo"]).to_numpy(),
                          "type": G["type"].astype(str).to_numpy()})
    E = result_table(d, n, "events")
    if E is None or not {"clockTime", "channel", "category", "text"} <= set(E.columns):
        E = pd.DataFrame({"t": pd.Series([], dtype="datetime64[ns]"), "channel": pd.Series([], dtype=float),
                          "text": pd.Series([], dtype=object)})
    else:
        E = E[E["category"].astype(str) == "comment"]
        E = pd.DataFrame({"t": _parse_clock(E["clockTime"]).to_numpy(),
                          "channel": pd.to_numeric(E["channel"], errors="coerce").to_numpy(float),
                          "text": E["text"].astype(str).to_numpy()})
    oc = _unique(["window", "channel", "beatType", "included", "nBeats"] + list(pars))
    Ov = _standard_overview(result_table(d, n, "overview", usecols=lambda c: c in oc), pars)
    # zero force per channel (summary) and the recording (average beats): <raw_folder>/<relative path> or the path of
    # the analysis (info: file)
    zero = np.full(64, np.nan)
    Z = result_table(d, n, "summary", usecols=lambda c: c in ("channel", "zeroForce"))
    if Z is not None and {"channel", "zeroForce"} <= set(Z.columns):
        zc = pd.to_numeric(Z["channel"], errors="coerce").to_numpy(float)
        zf = pd.to_numeric(Z["zeroForce"], errors="coerce").to_numpy(float)
        for c in np.unique(zc[~np.isnan(zc) & (zc >= 1) & (zc <= 64) & ~np.isnan(zf)]):
            zero[int(c) - 1] = zf[np.flatnonzero((zc == c) & ~np.isnan(zf))[0]]
    cand = []
    if R.get("raw"):
        cand.append(os.path.join(R["raw"], *R["rel"][j].split("/")))
    f = _info_value(I, "file")
    if f is not None and str(f) not in ("", "nan"):
        cand.append(str(f))
    mdd = next((c for c in cand if os.path.isfile(c)), "")
    from .options import options as _options  # filter of the analysis (average beats)
    o = _options()
    filt = [float(o.medianFilterMs), float(o.meanFilterMs)]
    for i_, k_ in enumerate(("option_medianFilterMs", "option_meanFilterMs")):
        try:
            x_ = float(_info_value(I, k_))
            if not math.isnan(x_):
                filt[i_] = x_
        except (TypeError, ValueError):
            pass
    if str(_info_value(I, "option_noFiltering")).strip().lower() in ("1", "true"):
        filt = [0.0, 0.0]
    D = {"C": C, "Pr": Pr, "G": G, "E": E, "Ov": Ov, "zero": zero, "mdd": mdd, "filt": filt, "start": rs}
    cache[key] = D
    return D


def _standard_contractions(C, pars):
    if C is None or not {"channel", "clockTime"} <= set(C.columns):
        return _empty_contractions(pars)
    T = pd.DataFrame({"channel": pd.to_numeric(C["channel"], errors="coerce").to_numpy(float)})
    T["clock"] = _parse_clock(C["clockTime"]).to_numpy()
    T["clockTime"] = C["clockTime"].astype(str).to_numpy()
    T["beatType"] = C["beatType"].fillna("").astype(str).to_numpy() if "beatType" in C.columns else ""
    for f in _unique(["included", "stimFrequency", "peakToPeakFrequency", "t_stim", "t_onset", "t_peak", "amplitude"]
                     + [p for p in pars if p != "beatsPerMinute"]):
        T[f] = pd.to_numeric(C[f], errors="coerce").to_numpy(float) * _scale(f) if f in C.columns else np.nan
    return T


def _empty_contractions(pars):
    T = pd.DataFrame({"channel": pd.Series([], dtype=float), "clock": pd.Series([], dtype="datetime64[ns]"),
                      "clockTime": pd.Series([], dtype=object), "beatType": pd.Series([], dtype=object)})
    for f in _unique(["included", "stimFrequency", "peakToPeakFrequency", "t_stim", "t_onset", "t_peak", "amplitude"]
                     + [p for p in pars if p != "beatsPerMinute"]):
        T[f] = pd.Series([], dtype=float)
    return T


def _standard_overview(Ov, pars):
    """1-min values of the included contractions (extra beats excluded; several beat types: the one with most beats)"""
    O = pd.DataFrame({"channel": pd.Series([], dtype=float), "clock": pd.Series([], dtype="datetime64[ns]"),
                      "nBeats": pd.Series([], dtype=float)})
    for p in pars:
        O[p] = pd.Series([], dtype=float)
    if Ov is None or not {"window", "channel", "included", "nBeats"} <= set(Ov.columns):
        return O
    inc = pd.to_numeric(Ov["included"], errors="coerce").to_numpy(float) == 1
    if "beatType" in Ov.columns:
        inc &= Ov["beatType"].astype(str).to_numpy() != "extra"
    Ov = Ov[inc].reset_index(drop=True)
    if Ov.empty:
        return O
    t = _parse_clock(Ov["window"])
    ch = pd.to_numeric(Ov["channel"], errors="coerce").to_numpy(float)
    nb = pd.to_numeric(Ov["nBeats"], errors="coerce").to_numpy(float)
    o = np.lexsort((-nb, t.to_numpy(dtype="datetime64[ns]").astype("int64"), ch))
    ch, tt, nb = ch[o], t.to_numpy()[o], nb[o]
    first = np.r_[True, (ch[1:] != ch[:-1]) | (tt[1:] != tt[:-1])]
    O = pd.DataFrame({"channel": ch[first], "clock": tt[first], "nBeats": nb[first]})
    for p in pars:
        O[p] = (pd.to_numeric(Ov[p], errors="coerce").to_numpy(float)[o][first] * _scale(p) if p in Ov.columns
                else np.nan)
    return O


def _window_notes(D, c, a0, b0):
    notes = []
    Pr, G, E = D["Pr"], D["G"], D["E"]
    for i in np.flatnonzero((Pr["a"] < b0).to_numpy() & (Pr["b"] > a0).to_numpy()):
        notes.append(f"protocol {Pr['name'].iloc[i]} {_hms(Pr['a'].iloc[i])}-{_hms(Pr['b'].iloc[i])}")
    ch = G["channel"].to_numpy(float)
    for i in np.flatnonzero(((ch == c) | (ch == 0)) & (G["a"] < b0).to_numpy() & (G["b"] > a0).to_numpy()):
        notes.append(f"{G['type'].iloc[i]} {_hms(G['a'].iloc[i])}-{_hms(G['b'].iloc[i])}")
    ch = E["channel"].to_numpy(float)
    for i in np.flatnonzero(((ch == c) | (ch == 0)) & (E["t"] >= a0).to_numpy() & (E["t"] < b0).to_numpy()):
        notes.append(f"comment {_hms(E['t'].iloc[i])} {E['text'].iloc[i]}")
    return notes


def _coverage_gap(R, inR, a0, b0):
    s = sorted(R["start"][j] for j in inR)
    e = sorted(R["stop"][j] for j in inR)
    return any(s[i + 1] > e[i] and s[i + 1] > a0 and e[i] < b0 for i in range(len(s) - 1))


def _slice_at(res, R, series, c, t, reg_cache):
    """number of the slice of the channel at time t and its sample ID (slice register of the experiment; NaN / '' if
    unknown)"""
    e = R["experiment"]
    if e:
        q = e.split("/")
        f = os.path.join(res, *q, q[-1] + "_slices.csv")
    else:
        f = os.path.join(res, "mda_slices_root.csv")
    if f not in reg_cache:
        T = None
        if os.path.isfile(f):
            try:
                T = pd.read_csv(f, dtype=str, keep_default_na=False)
            except Exception:  # noqa: BLE001 - no register: no check
                T = None
        reg_cache[f] = T
    T = reg_cache[f]
    if T is None or not {"series", "channel", "slice", "startTime", "endTime"} <= set(T.columns):
        return math.nan, ""
    k = T[(T["series"] == series) & (pd.to_numeric(T["channel"], errors="coerce") == c)]
    for _, r in k.iterrows():
        a, b = _parse_clock(pd.Series([r["startTime"]])).iloc[0], _parse_clock(pd.Series([r["endTime"]])).iloc[0]
        if not pd.isna(a) and not pd.isna(b) and a - pd.Timedelta(seconds=60) <= t <= b + pd.Timedelta(seconds=60):
            sid = str(r["sampleID"]).strip() if "sampleID" in T.columns else ""
            return float(r["slice"]), "" if sid.lower() in ("nan", "<missing>", "none") else sid
    return math.nan, ""


def _label_per_series(x, S, name):
    """sample ID / group: one text for all series or one per series ('' = from the data)"""
    if x is None or (isinstance(x, str) and not x) or (not isinstance(x, str) and len(x) == 0):
        return [""] * len(S)
    if isinstance(x, str):
        return [x.strip()] * len(S)
    if len(x) == len(S):
        return [str(y).strip() for y in x]
    raise ValueError(f"timepoints: {name}: one text or one per series expected.")


def _series_sample(series):
    """sample ID from the name of the series: the part after the setup (Setup1_ABC000101 --> ABC000101)"""
    m = re.match(r"^[^_]+_(.+)$", series)
    return m.group(1) if m else series


def _all_channels(pS, pC, pT, all_ch, recs, off, sec, pars, cache):
    nS, nC, nT = [], [], []
    for p in range(len(pS)):
        if not all_ch[p]:
            nS.append(pS[p]); nC.append(pC[p]); nT.append(pT[p])
            continue
        R = recs[pS[p]]
        chs = set()
        for o in off:
            a0 = pT[p] + pd.Timedelta(minutes=float(o))
            b0 = a0 + pd.Timedelta(seconds=sec)
            for j in range(len(R["rel"])):
                if R["start"][j] < b0 and R["stop"][j] > a0:
                    C = _recording_data(cache, R, j, pars)["C"]
                    chs |= set(C.loc[(C["clock"] >= a0) & (C["clock"] < b0), "channel"].dropna().astype(int))
        for c in sorted(chs):
            nS.append(pS[p]); nC.append(int(c)); nT.append(pT[p])
    return nS, nC, nT


def _units(pars):
    U = {p[0]: p[1] for p in PARAMETERS}
    return ["1/min" if p == "beatsPerMinute" else "mN/s" if p in ("dFdtMax", "dFdtMin") else U.get(p, "")
            for p in pars]


def _scale(p):
    """factor from the unit of the analysis to the unit of timepoints (dF/dt: uN/s --> mN/s)"""
    return 1e-3 if p in ("dFdtMax", "dFdtMin") else 1.0


def _signal_gap(R, inR, cache, c, a0, b0, pars):
    """a period without signal of channel c (chamber out, no signal, technical; gaps of the watcher) in [a0, b0)"""
    for j in inR:
        G = _recording_data(cache, R, j, pars)["G"]
        ch = G["channel"].to_numpy(float)
        if np.any(((ch == c) | (ch == 0)) & (G["a"] < b0).to_numpy() & (G["b"] > a0).to_numpy()):
            return True
    return False


def _signal_force(R, inR, cache, raw_cache, ch, a0, b0, pars):
    """median of the force of channel ch in [a0, b0) (raw signal of the recordings, filtered as in the analysis, minus
    the zero force of the channel: of the analysis, else of the log file); NaN without recording or zero force"""
    from types import SimpleNamespace
    from .analyze_channel import filter_signal
    from .read_mdd import read_mdd
    from .zero_force import zero_force
    notes, F = [], []
    for j in inR:
        D = _recording_data(cache, R, j, pars)
        if not D["mdd"]:
            notes.append(f"diastolic force without contractions: {R['name'][j]}.mdd not found (option rawFolder)")
            continue
        if D["mdd"] not in raw_cache:
            raw_cache[D["mdd"]] = read_mdd(D["mdd"])
        s0, s1 = (a0 - D["start"]).total_seconds(), (b0 - D["start"]).total_seconds()
        z = D["zero"][ch - 1] if ch <= len(D["zero"]) else math.nan  # zero force of the analysis (summary)
        if math.isnan(z):  # channel without contractions: log file
            z = float(zero_force(raw_cache[D["mdd"]], ch, None, [(s0 + s1) / 2])[0][0])
        if math.isnan(z):
            notes.append(f"diastolic force without contractions: zero force of {R['name'][j]} ch{ch} unknown")
            continue
        S = read_mdd(raw_cache[D["mdd"]], max(0.0, s0 - 1), s1 + 1)
        dc = [int(c) for c in np.atleast_1d(S.dataChannels)]
        row = dc.index(ch) if ch in dc else (0 if len(dc) == 1 else None)
        t = np.asarray(S.t, float).ravel()
        if row is None or t.size < 2:
            continue
        f, t = filter_signal(np.asarray(S.force, float)[row], t, t[1] - t[0],
                             SimpleNamespace(medianFilterMs=D["filt"][0], meanFilterMs=D["filt"][1]))
        F.append(np.asarray(f, float)[(t >= s0) & (t < s1)] - z)
    F = np.concatenate(F) if F else np.zeros(0)
    F = F[~np.isnan(F)]
    return (float(np.median(F)) if F.size else math.nan), notes


def _norm_name(p):
    """column of the normalized value: <p>_pctBaseline; diastolicForce: change against the baseline (uN)"""
    return "diastolicForce_delta" if p == "diastolicForce" else p + "_pctBaseline"


def _norm_ref(p):
    """value of 'no change' of the normalized parameter"""
    return 0 if p == "diastolicForce" else 100


def _axis_label(p, u, norm):
    if not norm:
        return u
    return "change against the baseline (uN)" if p == "diastolicForce" else "% of baseline"


def _div(a, b):
    """a / b as in MATLAB (x / 0 = +-Inf, 0 / 0 = NaN)"""
    a, b = float(a), float(b)
    if math.isnan(a) or math.isnan(b):
        return np.nan
    if b == 0:
        return np.nan if a == 0 else math.copysign(math.inf, a)
    return a / b


def _summary_columns(pars):
    """counts, note, per parameter mean and normalized value; then SD and SEM, median and quartiles, average beat"""
    c = ["series", "channel", "sampleID", "group", "time", "offset_min", "from", "to", "recording", "slice", "nBeats",
         "nIncluded", "nExtra", "note"]
    c += [x for p in pars for x in (p, _norm_name(p))]
    c += [x for p in pars for x in (p + "_SD", p + "_SEM")]
    c += [x for p in pars for x in (p + "_median", p + "_q25", p + "_q75")]
    return c + ["nAvgBeats", "avgBeat_diastolic", "avgBeat_amplitude"]


def _course_template(pars):
    T = pd.DataFrame({"series": pd.Series([], dtype=object), "channel": pd.Series([], dtype=float),
                      "time": pd.Series([], dtype=object), "window": pd.Series([], dtype=object),
                      "minutes": pd.Series([], dtype=float), "nBeats": pd.Series([], dtype=float)})
    for p in pars:
        T[p] = pd.Series([], dtype=float)
        T[_norm_name(p)] = pd.Series([], dtype=float)
    return T


def _join_note(s, x):
    return x if not s else s + "; " + x


def _info_table(TP, res, used):
    b = "none" if math.isnan(TP["baseline"]) else _g(TP["baseline"])
    rows = [("function", "mda_timepoints"), ("version", mda_version()), ("implementation", "Python"),
            ("analysisDate", _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")), ("resultsFolder", res),
            ("label", TP["label"]), ("sampleID", " ".join(_unique(list(TP["rows"]["sampleID"])))),
            ("group", " ".join(_unique(list(TP["rows"]["group"])))), ("time", TP["time"]),
            ("offsets_min", " ".join(_g(o) for o in TP["offsets"])),
            ("seconds", _g(TP["seconds"])), ("baseline_min", b), ("parameters", " ".join(TP["parameters"])),
            ("units", " ".join(f"{p}={u}" for p, u in zip(TP["parameters"], TP["units"]))),
            ("windows", "[time + offset, time + offset + seconds), clock time of the peak"),
            ("values", "mean (column <parameter>), SD, SEM (SD / sqrt(n)), median, q25, q75 of the included "
             "contractions; beatsPerMinute = all contractions per minute; dFdtMax, dFdtMin in mN/s"),
            ("pctBaseline", "<parameter>_pctBaseline = 100 * mean / mean of the baseline window of the channel (same "
             "slice); diastolicForce_delta = mean - mean of the baseline window (uN); course: the same with the "
             "1-min medians and the medians of the baseline window; no contractions (recorded, no gap): amplitude, "
             "AUC, dFdtMax, dFdtMin 0, times NaN, diastolic force = median of the filtered signal - zero force"),
            ("averageBeats", "mean of the included beats (no extra beats, no other contraction in the segment), "
             "aligned at the stimulus (unpaced: onset), 0.1 s before to the next beat - 0.05 s, raw force of the "
             "recording - zero force (uN), filtered as in the analysis; norm_baselineAmplitude = (F - "
             "diastole of the baseline average beat) / its amplitude; norm_ownAmplitude = (F - own diastole) "
             "/ own amplitude + (own diastole - baseline diastole) / baseline amplitude; diastole = mean of the "
             "0.1 s before the stimulus; ..._SE = SD of the beats / sqrt(n)"),
            ("alternans", "two amplitude groups of the included beats (1-D 2-means: each >= 20 %, means >= 20 % and "
             ">= 3 SD apart; alternans if >= 80 % of successive beats switch, otherwise irregular amplitudes): note, "
             "average beats of the small and the large beats"),
            ("notes", "; ".join(TP.get("notes", []))),
            ("recordings", "; ".join(used))]
    return pd.DataFrame(rows, columns=["key", "value"])


def _g(x):
    """number as MATLAB num2str (up to 4 decimals for non-integers)"""
    x = float(x)
    if x == int(x):
        return str(int(x))
    return f"{x:.4f}".rstrip("0").rstrip(".")


def _used_of(used, series):
    return [u for u in used if _series_info(re.sub(r"\.mdd$", "", u.rsplit("/", 1)[-1], flags=re.I))[0] in series]


def _subset(TP, sel, nK):
    Te = dict(TP)
    Te["rows"] = TP["rows"][sel].reset_index(drop=True)
    Te["time"] = _clock_text(min(_parse_clock(Te["rows"]["time"])))
    Te["summary"] = TP["summary"][np.repeat(sel, nK)].reset_index(drop=True)
    Te["matrix"] = {p: v[sel] for p, v in TP["matrix"].items()}
    Te["pctBaseline"] = {p: v[sel] for p, v in TP["pctBaseline"].items()}
    keys = set(zip(Te["rows"]["series"], Te["rows"]["channel"]))
    for f in ("course", "beats", "averageBeats"):
        T = TP[f]
        if len(T):
            m = np.array([(s, int(c)) in keys for s, c in zip(T["series"], T["channel"])])
            Te[f] = T[m].reset_index(drop=True)
    Te["averageBeatsMean"] = _average_beats_mean(Te["averageBeats"], TP["offsets"])
    return Te


def _write_files(d, base, TP, figs):
    x = os.path.join(d, base + ".xlsx")
    for f in (x, os.path.join(d, base + "_beats.csv"), os.path.join(d, base + "_averageBeats.csv")):
        if os.path.isfile(f):
            os.remove(f)
    files = [x]
    with pd.ExcelWriter(x, engine="openpyxl") as w:
        TP["summary"].to_excel(w, sheet_name="summary", index=False)
        _matrix_sheet(TP).to_excel(w, sheet_name="matrix", index=False)
        TP["course"].to_excel(w, sheet_name="course", index=False)
        B = TP["beats"]
        if len(B) > 1e6:
            f = os.path.join(d, base + "_beats.csv")
            B.to_csv(f, index=False)
            pd.DataFrame({"note": [f"{len(B)} rows: {base}_beats.csv"]}).to_excel(w, sheet_name="beats", index=False)
            files.append(f)
        elif B.empty:
            pd.DataFrame({"series": pd.Series([], dtype=object)}).to_excel(w, sheet_name="beats", index=False)
        else:
            B.to_excel(w, sheet_name="beats", index=False)
        AB = TP["averageBeats"]
        if len(AB) > 1e6:
            f = os.path.join(d, base + "_averageBeats.csv")
            AB.to_csv(f, index=False)
            pd.DataFrame({"note": [f"{len(AB)} rows: {base}_averageBeats.csv"]}).to_excel(
                w, sheet_name="averageBeats", index=False)
            files.append(f)
        else:
            AB.to_excel(w, sheet_name="averageBeats", index=False)
        TP["averageBeatsMean"].to_excel(w, sheet_name="averageBeatsMean", index=False)
        TP["info"].to_excel(w, sheet_name="info", index=False)
    if not figs:
        return files
    return files + _write_figures(d, base, TP, ("timepoints", "course", "averageBeats", "averageBeatsMean", "slides"))


def _write_figures(d, base, TP, kinds):
    """images (kinds: timepoints, course, averageBeats, averageBeatsMean, slides), each absolute (_abs) and normalized
    to the baseline window (_norm; not without baseline); files of the names of earlier versions (<base>_timepoints,
    _course, _averageBeats, _averageBeatsMean) are removed"""
    import matplotlib
    matplotlib.use("Agg")
    files = []
    no_base = math.isnan(TP["baseline"])
    for g in ("timepoints", "course", "averageBeats", "averageBeatsMean"):
        for e in (".png", ".svg"):
            for f in [base + "_" + g + e] + ([base + "_" + g + "_norm" + e] if no_base else []):
                if os.path.isfile(os.path.join(d, f)):
                    os.remove(os.path.join(d, f))
    for m in (("abs",) if no_base else ("abs", "norm")):
        if "timepoints" in kinds:
            f1 = os.path.join(d, f"{base}_timepoints_{m}")
            _save(_timepoints_figure(TP, m), f1)
            files += [f1 + ".png", f1 + ".svg"]
        if "course" in kinds:
            f2 = os.path.join(d, f"{base}_course_{m}")
            _save(_course_figure(TP, m), f2)
            files += [f2 + ".png", f2 + ".svg"]
    if not len(TP["averageBeats"]):
        return files
    for m in ("abs", "norm"):  # norm without baseline: own amplitude = 1 only
        if "averageBeats" in kinds:
            f3 = os.path.join(d, f"{base}_averageBeats_{m}")
            _save(_average_beats_figure(TP, m), f3)
            files += [f3 + ".png", f3 + ".svg"]
        if "averageBeatsMean" in kinds:
            f4 = os.path.join(d, f"{base}_averageBeatsMean_{m}")
            _save(_average_beats_mean_figure(TP, m), f4)
            files += [f4 + ".png", f4 + ".svg"]
    if "slides" not in kinds:
        return files
    # one 16:9 slide per channel (average beats +- SE and the values): averageBeats/<series>_ch<c>
    ds = os.path.join(d, "averageBeats")
    os.makedirs(ds, exist_ok=True)
    R, AB = TP["rows"], TP["averageBeats"]
    have = set(zip(AB["series"], AB["channel"].astype(int)))
    for i in range(len(R)):
        if (R["series"].iloc[i], int(R["channel"].iloc[i])) not in have:
            continue
        f5 = os.path.join(ds, f"{R['series'].iloc[i]}_ch{int(R['channel'].iloc[i])}")
        _save(_channel_slide(TP, i), f5)
        files += [f5 + ".png", f5 + ".svg"]
    return files


def _matrix_sheet(TP):
    oc = [f"{o:+g} min" for o in TP["offsets"]]
    parts = []
    R = TP["rows"]
    for i, par in enumerate(TP["parameters"]):
        for m in ("mean", _norm_name(par)[len(par) + 1:]):
            V = TP["matrix"][par] if m == "mean" else TP["pctBaseline"][par]
            T = pd.DataFrame({"parameter": par, "measure": m, "series": R["series"], "channel": R["channel"],
                              "time": R["time"]})
            for k, c in enumerate(oc):
                T[c] = V[:, k]
            parts.append(T)
    return pd.concat(parts, ignore_index=True)


# ---------------------------------------------------------------------------------------------------------- figures
def _grid(n):
    nc = min(3, n)
    return int(math.ceil(n / nc)), nc


def _pair_labels(R):
    if "label" in R.columns:  # pool_timepoints
        return list(R["label"])
    if R["series"].nunique() == 1:
        return [f"ch{c}" for c in R["channel"]]
    return [f"{s} ch{c}" for s, c in zip(R["series"], R["channel"])]


def _unit_title(p, u):
    return p if not u else f"{p} ({u})"


def _figure_title(TP):
    if TP.get("title"):  # pool_timepoints
        return TP["title"]
    t = _parse_clock(TP["rows"]["time"])
    tt = _clock_text(t.min()) if t.min() == t.max() else f"{_clock_text(t.min())} to {_hms(t.max())}"
    s = f"{TP['label']}: treatment {tt}, {len(TP['rows'])} channel(s), windows of {_g(TP['seconds'])} s"
    if not math.isnan(TP["baseline"]):
        s += f", baseline {_offset_labels([TP['baseline']])[0]}"
    return s


def _offset_labels(off):
    L = []
    for o in off:
        o = float(o)
        if o == 0:
            L.append("0 min")
        elif o % 60 == 0:
            L.append(f"{o / 60:+g} h")
        else:
            L.append(f"{o:+g} min")
    return L


def _colors(n):
    import matplotlib.pyplot as plt
    base = plt.rcParams["axes.prop_cycle"].by_key().get("color", ["C0"])
    return [base[i % len(base)] for i in range(n)]


def _timepoints_figure(TP, mode):
    """per parameter over the windows, one line per channel (abs: mean +- SEM of the beats, units of the parameters;
    norm: pctBaseline, diastolicForce: change in uN), black = mean +- SEM of the channels"""
    import matplotlib.pyplot as plt
    import warnings
    pars, R = TP["parameters"], TP["rows"]
    nP, nK = len(R), len(TP["offsets"])
    nr, nc = _grid(len(pars))
    fig, axs = plt.subplots(nr, nc, figsize=(4.2 * nc, 3.1 * nr + 0.6), squeeze=False)
    col, lab = _colors(nP), _pair_labels(R)
    norm = mode == "norm"
    x = np.arange(1, nK + 1)
    for i, par in enumerate(pars):
        ax = axs[i // nc][i % nc]
        if norm:
            V, E = TP["pctBaseline"][par], None
        else:
            V = TP["matrix"][par]
            E = TP["summary"][par + "_SEM"].to_numpy(float).reshape(nP, nK)
        for p in range(nP):
            ax.errorbar(x, V[p], yerr=None if E is None else E[p], fmt="-o", color=col[p], markersize=4,
                        linewidth=0.8, capsize=2, label=lab[p])
        if nP > 1:  # mean +- SEM of the channels
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                nv = np.sum(~np.isnan(V), axis=0)
                sv = np.nanstd(V, axis=0, ddof=1) / np.sqrt(nv)
                sv[nv < 2] = np.nan
                ax.errorbar(x, np.nanmean(V, axis=0), yerr=sv, fmt="-", color="k", linewidth=2.2, elinewidth=1,
                            capsize=4, label="mean +- SEM")
        if norm:
            ax.axhline(_norm_ref(par), linestyle=":", color="0.5")
        ax.set_xticks(x)
        ax.set_xticklabels(_offset_labels(TP["offsets"]), fontsize=8)
        ax.set_xlim(0.6, nK + 0.4)
        ax.tick_params(labelsize=8)
        ax.set_ylabel(_axis_label(par, TP["units"][i], norm), fontsize=8)
        ax.set_title(_unit_title(par, TP["units"][i]), fontsize=9)
        if i == 0 and nP <= 16:
            ax.legend(fontsize=6, frameon=False)
    for i in range(len(pars), nr * nc):
        axs[i // nc][i % nc].set_visible(False)
    w = " - normalized to the baseline window" if norm else " - mean +- SEM of the beats"
    fig.suptitle(_figure_title(TP) + w, fontsize=10)
    fig.tight_layout()
    return fig


def _course_figure(TP, mode):
    """per parameter the 1-min values relative to the treatment: 'abs' (units) or 'norm' (pctBaseline;
    diastolicForce: change in uN), one line per channel, black = mean +- SEM of the channels
    (shaded); windows grey, treatment dashed"""
    import matplotlib.pyplot as plt
    pars, R, C = TP["parameters"], TP["rows"], TP["course"]
    nP = len(R)
    nr, nc = _grid(len(pars))
    fig, axs = plt.subplots(nr, nc, figsize=(4.2 * nc, 3.1 * nr + 0.6), squeeze=False)
    col, lab = _colors(nP), _pair_labels(R)
    norm = mode == "norm"
    off = np.asarray(TP["offsets"], float)
    span = off.max() + 30 + TP["seconds"] / 60 - (off.min() - 30)
    f, xl = (60, "hours after the treatment") if span > 360 else (1, "minutes after the treatment")
    for i, par in enumerate(pars):
        ax = axs[i // nc][i % nc]
        for o in off:
            x0, x1 = o / f, (o + TP["seconds"] / 60) / f
            ax.axvspan(x0, x0 + max(x1 - x0, span / f / 300), color="0.85", linewidth=0, zorder=0)
        v = _norm_name(par) if norm else par
        for p in range(nP):
            s = (C["series"] == R["series"].iloc[p]).to_numpy() & (C["channel"].to_numpy(float) == R["channel"].iloc[p])
            ax.plot(C["minutes"].to_numpy(float)[s] / f, C[v].to_numpy(float)[s], "-", color=col[p], linewidth=0.8,
                    label=lab[p])
        if nP > 1:  # mean +- SEM of the channels (minutes rounded)
            mx, my, ms = _course_mean(C, R, v)
            _shade(ax, mx / f, my, ms, "k")
            ax.plot(mx / f, my, "-", color="k", linewidth=1.6, label="mean +- SEM")
        ax.axvline(0, linestyle="--", color="0.3")
        ax.set_xlim((off.min() - 30) / f, (off.max() + 30 + TP["seconds"] / 60) / f)
        ax.tick_params(labelsize=8)
        ax.set_xlabel(xl, fontsize=8)
        ax.set_ylabel(_axis_label(par, TP["units"][i], norm), fontsize=8)
        ax.set_title(_unit_title(par, TP["units"][i]), fontsize=9)
        if i == 0 and nP <= 16:
            ax.legend(fontsize=6, frameon=False)
    for i in range(len(pars), nr * nc):
        axs[i // nc][i % nc].set_visible(False)
    w = ", normalized to the baseline window" if norm else ""
    fig.suptitle(_figure_title(TP) + " - 1-min values" + w + ", windows grey", fontsize=10)
    fig.tight_layout()
    return fig


def _course_mean(C, R, v):
    """mean and SEM of the channels R of the course column v per minute (minutes after the treatment rounded)"""
    keys = set(zip(R["series"], R["channel"].astype(int)))
    s = np.array([(a, int(b)) in keys for a, b in zip(C["series"], C["channel"])], bool)
    mm = C["minutes"].to_numpy(float)[s]
    m = np.sign(mm) * np.floor(np.abs(mm) + 0.5)  # MATLAB round
    val = C[v].to_numpy(float)[s]
    ok = np.isfinite(val)
    if not ok.any():
        return np.zeros(0), np.zeros(0), np.zeros(0)
    G = pd.DataFrame({"m": m[ok], "v": val[ok]}).groupby("m")["v"]
    x = np.asarray(G.mean().index, float)
    y, n, sd = G.mean().to_numpy(float), G.count().to_numpy(float), G.std(ddof=1).to_numpy(float)
    e = sd / np.sqrt(n)
    e[n < 2] = np.nan
    return x, y, e


def _save(fig, f):
    import matplotlib.pyplot as plt
    fig.savefig(f + ".png", dpi=150)
    fig.savefig(f + ".svg")
    plt.close(fig)


# ---------------------------------------------------------------------------------------------------- average beats
def _alternans_groups(x):
    """two amplitude groups of the beats x (in time order; alternans or irregular): grp 1 = small, 2 = large, 0 = none
    (1-D 2-means of the amplitudes: each group >= 20 % of the beats, means >= 20 % of the larger and >= 3 SD apart);
    'alternans' if >= 80 % of successive beats switch the group, otherwise 'irregular amplitudes'"""
    x = np.asarray(x, float).ravel()
    grp = np.zeros(x.size, int)
    ok = ~np.isnan(x)
    n = int(ok.sum())
    if n < 10:
        return grp, ""
    v = np.sort(x[ok])
    best, kb = math.inf, 0
    for k in range(1, n):
        a, b = v[:k], v[k:]
        ss = float(np.sum((a - a.mean()) ** 2) + np.sum((b - b.mean()) ** 2))
        if ss < best:
            best, kb = ss, k
    lo = ok & (x <= v[kb - 1])
    hi = ok & (x > v[kb - 1])
    if not hi.any():
        return grp, ""
    mlo, mhi = float(x[lo].mean()), float(x[hi].mean())
    sd = math.sqrt(best / max(n - 2, 1))
    fl = lo.sum() / n
    if min(fl, 1 - fl) < 0.2 or mhi - mlo < 0.2 * mhi or mhi - mlo < 3 * sd:
        return grp, ""
    grp[lo], grp[hi] = 1, 2
    g = grp[ok]
    sw = float(np.mean(g[1:] != g[:-1]))
    kind = "alternans: 2 amplitude groups" if sw >= 0.8 else "irregular amplitudes: 2 groups"
    return grp, (f"{kind} {mlo:.0f} / {mhi:.0f} uN ({_mround(100 * fl)} % small beats, {_mround(100 * sw)} % of "
                 "successive beats switch)")


AB_COLUMNS = ["series", "channel", "offset_min", "trace", "nBeats", "t_s", "force_uN", "force_SE_uN",
              "norm_baselineAmplitude", "norm_baselineAmplitude_SE", "norm_ownAmplitude", "norm_ownAmplitude_SE"]


def _ab_template():
    return pd.DataFrame({c: pd.Series([], dtype=object if c in ("series", "trace") else float) for c in AB_COLUMNS})


def _pair_average_beats(series, ch, Wb, off, kb, R, pars, cache, raw_cache):
    """average beats of one channel per window (Wb[k]: DataFrame j (recording), align (s in the file), tpeak, grp of
    the included beats): traces 'all', 'small beats', 'large beats' (alternans), force - zero force and normalized,
    each with its standard error (SD of the beats / sqrt(n))"""
    from .read_mdd import read_mdd
    nK = len(off)
    st = {"n": np.zeros(nK, int), "dia": np.full(nK, np.nan), "amp": np.full(nK, np.nan)}
    notes = []
    pre, step = 0.1, 0.002
    cyc = np.full(nK, np.nan)
    for k in range(nK):
        W = Wb[k]
        if W is None or len(W) < 2:
            continue
        dd = []
        for j in np.unique(W["j"].to_numpy()):
            a = np.sort(W["align"].to_numpy(float)[(W["j"].to_numpy() == j) & ~np.isnan(W["align"].to_numpy(float))])
            dd += list(np.diff(a))
        if dd:
            cyc[k] = float(np.median(dd))
    if np.all(np.isnan(cyc)):
        return _ab_template(), st, notes
    L = min(float(np.nanmin(cyc)) - pre - 0.05, 4.0)
    if L < 0.1:
        return _ab_template(), st, notes
    nPts = int(math.floor((L + pre) / step + 1e-9)) + 1
    tg = -pre + np.arange(nPts) * step
    avg = [[None] * 3 for _ in range(nK)]
    se = [[None] * 3 for _ in range(nK)]
    nb = np.zeros((nK, 3), int)
    for k in range(nK):
        W = Wb[k]
        if W is None or len(W) == 0:
            continue
        segs, g = [], []
        for j in np.unique(W["j"].to_numpy()):
            D = _recording_data(cache, R, int(j), pars)
            if not D["mdd"]:
                notes.append(f"average beats: {R['name'][int(j)]}.mdd not found (option rawFolder)")
                continue
            w = W[(W["j"].to_numpy() == j) & ~np.isnan(W["align"].to_numpy(float))]
            if len(w) == 0:
                continue
            z = D["zero"][ch - 1] if ch <= len(D["zero"]) else math.nan
            if math.isnan(z):
                z = 0.0
                notes.append(f"average beats: zero force of {R['name'][int(j)]} ch{ch} unknown (force = sensor signal)")
            if D["mdd"] not in raw_cache:
                raw_cache[D["mdd"]] = read_mdd(D["mdd"])
            al = w["align"].to_numpy(float)
            S = read_mdd(raw_cache[D["mdd"]], max(0.0, al.min() - pre - 1), al.max() + L + 1)
            dc = [int(c) for c in np.atleast_1d(S.dataChannels)]
            row = dc.index(ch) if ch in dc else (0 if len(dc) == 1 else None)
            t = np.asarray(S.t, float).ravel()
            if row is None or t.size == 0:
                continue
            from types import SimpleNamespace
            from .analyze_channel import filter_signal
            F, t = filter_signal(np.asarray(S.force, float)[row], t, t[1] - t[0],
                                 SimpleNamespace(medianFilterMs=D["filt"][0], meanFilterMs=D["filt"][1]))
            C = D["C"]
            pk = C["t_peak"].to_numpy(float)[C["channel"].to_numpy(float) == ch]
            for a, tp, gr in zip(al, w["tpeak"].to_numpy(float), w["grp"].to_numpy(int)):
                if a - pre < t[0] or a + L > t[-1]:
                    continue
                if np.any((np.abs(pk - tp) > 1e-6) & (pk > a - pre) & (pk < a + L)):
                    continue
                segs.append(np.interp(a + tg, t, F) - z)
                g.append(gr)
        if not segs:
            continue
        Y, g = np.column_stack(segs), np.asarray(g)
        for m, sel in enumerate((np.ones(g.size, bool), g == 1, g == 2)):
            if sel.any() and (m == 0 or (g > 0).any()):
                avg[k][m] = Y[:, sel].mean(axis=1)
                nb[k, m] = int(sel.sum())
                se[k][m] = (Y[:, sel].std(axis=1, ddof=1) / math.sqrt(nb[k, m]) if nb[k, m] > 1
                            else np.full(nPts, np.nan))
    neg = tg < 0
    ref = None
    if kb is not None and avg[kb][0] is not None:
        y = avg[kb][0]
        d0 = float(np.mean(y[neg]))
        ref = (d0, float(np.max(y)) - d0)
    labs = ("all", "small beats", "large beats")
    parts = []
    ts = np.round(tg * 1e6) / 1e6
    for k in range(nK):
        for m in range(3):
            y = avg[k][m]
            if y is None:
                continue
            d0 = float(np.mean(y[neg]))
            a0 = float(np.max(y)) - d0
            if m == 0:
                st["n"][k], st["dia"][k], st["amp"][k] = nb[k, 0], d0, a0
            e = se[k][m]
            # own amplitude = 1; the diastole keeps its change against the baseline (in baseline amplitudes)
            y1 = (y - d0) / a0 + (0.0 if ref is None else (d0 - ref[0]) / ref[1])
            y2, e2 = (np.full(nPts, np.nan),) * 2 if ref is None else ((y - ref[0]) / ref[1], e / ref[1])
            parts.append(pd.DataFrame({"series": series, "channel": ch, "offset_min": _num(off[k]), "trace": labs[m],
                                       "nBeats": int(nb[k, m]), "t_s": ts, "force_uN": y, "force_SE_uN": e,
                                       "norm_baselineAmplitude": y2, "norm_baselineAmplitude_SE": e2,
                                       "norm_ownAmplitude": y1, "norm_ownAmplitude_SE": e / a0}))
    T = pd.concat(parts, ignore_index=True) if parts else _ab_template()
    return T, st, notes


def _average_beats_mean(AB, off):
    """mean, SD and SE over the channels of the average beats (trace all) per window, common time axis (shortest
    beat): force (uN), baseline amplitude = 1, own amplitude = 1"""
    import warnings
    v = ("force_uN", "norm_baselineAmplitude", "norm_ownAmplitude")
    cols = ["offset_min", "t_s", "n"] + [x + e for x in v for e in ("_mean", "_sd", "_se")]
    if AB is None or len(AB) == 0:
        return pd.DataFrame({c: pd.Series([], dtype=float) for c in cols})
    A = AB[AB["trace"] == "all"]
    parts = []
    for o in off:
        Ak = A[A["offset_min"].to_numpy(float) == float(o)]
        keys = list(zip(Ak["series"], Ak["channel"].astype(int)))
        u = _unique(keys)
        if not u:
            continue
        kk = np.array([f"{a}|{b}" for a, b in keys])
        uu = [f"{a}|{b}" for a, b in u]
        ts = Ak["t_s"].to_numpy(float)
        tmax = min(ts[kk == x].max() for x in uu)
        t = ts[(kk == uu[0]) & (ts <= tmax + 1e-9)]
        keep = ts <= tmax + 1e-9
        n = len(uu)
        T = {"offset_min": _num(o), "t_s": t, "n": n}
        for c in v:
            Y = np.column_stack([Ak[c].to_numpy(float)[(kk == x) & keep] for x in uu])
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                m = np.nanmean(Y, axis=1)
                sd = np.nanstd(Y, axis=1, ddof=1) if n > 1 else np.full(t.size, np.nan)
            T[c + "_mean"], T[c + "_sd"], T[c + "_se"] = m, sd, sd / math.sqrt(n)
        parts.append(pd.DataFrame(T, columns=cols))
    return pd.concat(parts, ignore_index=True) if parts else pd.DataFrame({c: pd.Series([], dtype=float) for c in cols})


def _offset_colors(TP):
    """colors of the windows: baseline black, the others in the order of the offsets"""
    off = np.asarray(TP["offsets"], float)
    col = _colors(len(off) + 1)[1:]
    if not math.isnan(TP["baseline"]):
        col = ["k" if o == TP["baseline"] else c for o, c in zip(off, col)]
    return col


AB_TITLES = ("force (uN)", "baseline amplitude = 1, baseline diastole = 0",
             "own amplitude = 1, diastole: change in baseline amplitudes")


def _shade(ax, t, y, e, color):
    """standard error as a band around y"""
    e = np.asarray(e, float)
    if np.any(~np.isnan(e)):
        e = np.nan_to_num(e)
        ax.fill_between(t, y - e, y + e, color=color, alpha=0.2, linewidth=0)


def _beat_panel(ax, TP, AB, sel, ycol, ecol, col, legend, fs):
    """average beats of the rows sel of AB per window: trace all +- SE (shaded), alternans groups dashed"""
    L = _offset_labels(TP["offsets"])
    for k, o in enumerate(TP["offsets"]):
        for m in ("all", "small beats", "large beats"):
            s = sel & (AB["offset_min"].to_numpy(float) == float(o)) & (AB["trace"].to_numpy() == m)
            if not s.any():
                continue
            t, y = AB["t_s"].to_numpy(float)[s], AB[ycol].to_numpy(float)[s]
            if m == "all":
                _shade(ax, t, y, AB[ecol].to_numpy(float)[s], col[k])
                n = int(AB["nBeats"].to_numpy()[s][0])
                ax.plot(t, y, "-", color=col[k], linewidth=1.2, label=f"{L[k]} (n={n})")
            else:
                ax.plot(t, y, "--", color=col[k], linewidth=0.7)
    ax.tick_params(labelsize=fs)
    if legend:
        ax.legend(fontsize=6, frameon=False)


def _average_beats_figure(TP, mode):
    """average beats +- SE per channel, one color per window, alternans: small and large beats dashed; mode 'abs':
    force (uN), one panel per channel; 'norm': one row per channel, baseline amplitude = 1 and own amplitude = 1
    (diastole: change against the baseline; without baseline window: own amplitude only)"""
    import matplotlib.pyplot as plt
    AB, R = TP["averageBeats"], TP["rows"]
    keys = [f"{a}|{b}" for a, b in zip(AB["series"], AB["channel"].astype(int))]
    rk = [f"{a}|{b}" for a, b in zip(R["series"], R["channel"])]
    rows = [i for i, x in enumerate(rk) if x in set(keys)]
    n_row = len(rows)
    col, lab = _offset_colors(TP), _pair_labels(R)
    ycol = ("force_uN", "norm_baselineAmplitude", "norm_ownAmplitude")
    ecol = ("force_SE_uN", "norm_baselineAmplitude_SE", "norm_ownAmplitude_SE")
    kk = np.array(keys)
    if mode == "abs":
        nr, nc = _grid(n_row)
        fig, axs = plt.subplots(nr, nc, figsize=(4.2 * nc, 2.9 * nr + 0.7), squeeze=False)
        for r, i in enumerate(rows):
            ax = axs[r // nc][r % nc]
            _beat_panel(ax, TP, AB, kk == rk[i], ycol[0], ecol[0], col, r == 0, 7)
            ax.set_title(f"{lab[i]}: {AB_TITLES[0]}", fontsize=8)
            if r >= n_row - nc:
                ax.set_xlabel("s after stimulus", fontsize=7)
        for r in range(n_row, nr * nc):
            axs[r // nc][r % nc].set_visible(False)
    else:
        cs = (2,) if math.isnan(TP["baseline"]) else (1, 2)
        nc = len(cs)
        fig, axs = plt.subplots(n_row, nc, figsize=(4.2 * nc + 0.8, 2.4 * n_row + 0.7), squeeze=False)
        for r, i in enumerate(rows):
            for c, q in enumerate(cs):
                ax = axs[r][c]
                _beat_panel(ax, TP, AB, kk == rk[i], ycol[q], ecol[q], col, c == 0, 7)
                ax.set_title(f"{lab[i]}: {AB_TITLES[q]}" if c == 0 else AB_TITLES[q], fontsize=8)
                if r == n_row - 1:
                    ax.set_xlabel("s after stimulus", fontsize=7)
    fig.suptitle(_figure_title(TP) + " - average beats +- SE (dashed: small / large beats of alternans)", fontsize=9)
    fig.tight_layout()
    return fig


def _average_beats_mean_figure(TP, mode):
    """mean +- SE over the channels: 'abs' force (uN); 'norm' baseline amplitude = 1 and own amplitude = 1 (without
    baseline window: own amplitude only)"""
    import matplotlib.pyplot as plt
    M = TP["averageBeatsMean"]
    cs = (0,) if mode == "abs" else (2,) if math.isnan(TP["baseline"]) else (1, 2)
    fig, axs = plt.subplots(1, len(cs), figsize=(4.75 * len(cs), 3.8), squeeze=False)
    col, L = _offset_colors(TP), _offset_labels(TP["offsets"])
    ycol = ("force_uN", "norm_baselineAmplitude", "norm_ownAmplitude")
    for c, q in enumerate(cs):
        ax = axs[0][c]
        for k, o in enumerate(TP["offsets"]):
            s = M["offset_min"].to_numpy(float) == float(o)
            if not s.any():
                continue
            t = M["t_s"].to_numpy(float)[s]
            y = M[ycol[q] + "_mean"].to_numpy(float)[s]
            _shade(ax, t, y, M[ycol[q] + "_se"].to_numpy(float)[s], col[k])
            ax.plot(t, y, "-", color=col[k], linewidth=1.3, label=f"{L[k]} (n={int(M['n'].to_numpy()[s][0])})")
        ax.tick_params(labelsize=8)
        ax.set_xlabel("s after stimulus", fontsize=8)
        ax.set_title(AB_TITLES[q], fontsize=9)
        if c == 0:
            ax.legend(fontsize=7, frameon=False)
    fig.suptitle(_figure_title(TP) + " - mean +- SE of the " + TP.get("unitName", "channels"), fontsize=9)
    fig.tight_layout()
    return fig


def _slide_table(TP, i):
    """rows of the value table of a channel slide: window, n, mean amplitude (% of baseline), diastolic force
    (change), TTP90 / TTR90 (% of baseline), note"""
    R, S = TP["rows"], TP["summary"]
    s = S[(S["series"] == R["series"].iloc[i]) & (S["channel"] == R["channel"].iloc[i])].reset_index(drop=True)
    L = _offset_labels(TP["offsets"])
    pars = [p for p in ("amplitude", "diastolicForce", "TTP90", "TTR90") if p in TP["parameters"]]
    head = ["window", "n (avg. beat)"] + [{"amplitude": "amplitude (uN)", "diastolicForce": "diastolic force (uN)",
                                           "TTP90": "TTP90 (ms)", "TTR90": "TTR90 (ms)"}[p] for p in pars] + ["note"]
    rows = []
    base = None if math.isnan(TP["baseline"]) else int(np.flatnonzero(np.asarray(TP["offsets"]) == TP["baseline"])[0])
    for k in range(len(s)):
        r = [L[k], f"{int(s['nIncluded'].iloc[k])} ({int(s['nAvgBeats'].iloc[k])})"]
        for p in pars:
            v = float(s[p].iloc[k])
            f = 1000.0 if p in ("TTP90", "TTR90") else 1.0
            txt = "-" if math.isnan(v) else f"{v * f:.0f}"
            if not math.isnan(v) and base is not None and k != base:
                if p == "diastolicForce":
                    b = float(s[p].iloc[base])
                    if not math.isnan(b):
                        txt += f" ({v - b:+.0f})"
                else:
                    pc = float(s[p + "_pctBaseline"].iloc[k])
                    if not math.isnan(pc):
                        txt += f" ({pc:.0f} %)"
            r.append(txt)
        nt = str(s["note"].iloc[k]) if isinstance(s["note"].iloc[k], str) else ""
        r.append(nt if len(nt) <= 70 else nt[:67] + "...")
        rows.append(r)
    return head, rows


def _beat_end(AB, sel):
    """end of the slide time axis (s): last time with > 5 % of the amplitude in any window + 30 %"""
    x1, tmax = -math.inf, -math.inf
    for o in np.unique(AB["offset_min"].to_numpy(float)[sel]):
        s = sel & (AB["offset_min"].to_numpy(float) == o) & (AB["trace"].to_numpy() == "all")
        if not s.any():
            continue
        t, y = AB["t_s"].to_numpy(float)[s], AB["force_uN"].to_numpy(float)[s]
        tmax = max(tmax, float(t.max()))
        d0 = float(np.mean(y[t < 0]))
        a = float(np.max(y)) - d0
        j = np.flatnonzero((y - d0) / a > 0.05)
        if j.size:
            x1 = max(x1, float(t[j[-1]]))
    return tmax if math.isinf(x1) else min(tmax, 1.3 * x1 + 0.05)


def _channel_slide(TP, i):
    """16:9 slide of one channel: average beats +- SE absolute (uN) and with the own amplitude = 1 (diastole: change
    against the baseline in baseline amplitudes), table of the values"""
    import matplotlib.pyplot as plt
    AB, R = TP["averageBeats"], TP["rows"]
    sel = (AB["series"].to_numpy() == R["series"].iloc[i]) & (AB["channel"].to_numpy(float) == R["channel"].iloc[i])
    fig = plt.figure(figsize=(13.333, 7.5))
    gs = fig.add_gridspec(2, 2, height_ratios=[2.3, 1], hspace=0.28, wspace=0.18, left=0.06, right=0.98, top=0.88,
                          bottom=0.03)
    col, L = _offset_colors(TP), _offset_labels(TP["offsets"])
    x1 = 1000 * _beat_end(AB, sel)
    for c, (yc, ec, tt) in enumerate((("force_uN", "force_SE_uN", AB_TITLES[0]),
                                      ("norm_ownAmplitude", "norm_ownAmplitude_SE", AB_TITLES[2]))):
        ax = fig.add_subplot(gs[0, c])
        for k, o in enumerate(TP["offsets"]):
            for m in ("all", "small beats", "large beats"):
                s = sel & (AB["offset_min"].to_numpy(float) == float(o)) & (AB["trace"].to_numpy() == m)
                if not s.any():
                    continue
                t, y = 1000 * AB["t_s"].to_numpy(float)[s], AB[yc].to_numpy(float)[s]
                if m == "all":
                    _shade(ax, t, y, AB[ec].to_numpy(float)[s], col[k])
                    ax.plot(t, y, "-", color=col[k], linewidth=1.8,
                            label=f"{L[k]} (n = {int(AB['nBeats'].to_numpy()[s][0])})")
                else:
                    ax.plot(t, y, "--", color=col[k], linewidth=0.9)
        if math.isfinite(x1):
            ax.set_xlim(-100, x1)
        ax.set_xlabel("ms after stimulus", fontsize=11)
        ax.set_ylabel("uN" if c == 0 else "amplitude = 1", fontsize=11)
        ax.set_title(tt, fontsize=12)
        ax.tick_params(labelsize=10)
        ax.spines[["top", "right"]].set_visible(False)
        if c == 0:
            ax.legend(fontsize=10, frameon=False)
    head, rows = _slide_table(TP, i)
    ax = fig.add_subplot(gs[1, :])
    ax.axis("off")
    if rows:
        tb = ax.table(cellText=rows, colLabels=head, loc="upper center", cellLoc="center")
        tb.auto_set_font_size(False)
        tb.set_fontsize(10)
        tb.scale(1, 1.4)
        for k in range(len(rows)):
            tb[k + 1, 0].get_text().set_color(col[k])
            tb[k + 1, 0].get_text().set_fontweight("bold")
            tb[k + 1, len(head) - 1].get_text().set_fontsize(8)
        for j in range(len(head)):
            tb[0, j].get_text().set_fontweight("bold")
            tb[0, j].set_facecolor("0.92")
    t0 = R["time"].iloc[i]
    fig.suptitle(f"{R['series'].iloc[i]} ch{R['channel'].iloc[i]} - {TP['label']}, treatment {t0} - average beats "
                 f"+- SE (windows of {_g(TP['seconds'])} s; dashed: alternans groups)", fontsize=14)
    return fig


# ---------------------------------------------------------------------------------------------------------- helpers
def _parse_clock(x):
    """clock texts ('yyyy-mm-dd HH:MM:SS[.fff]', 'yyyy-mm-dd HH:MM', 'yyyy-mm-dd') or datetimes --> datetime Series"""
    s = pd.Series(x).reset_index(drop=True)
    if pd.api.types.is_datetime64_any_dtype(s):
        return s
    s = s.astype(object).where(s.notna(), "").astype(str).str.strip().str.replace("T", " ", regex=False)
    out = pd.Series(pd.NaT, index=s.index, dtype="datetime64[ns]")
    k = s.str.fullmatch(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(\.\d*)?")
    if k.any():
        frac = pd.to_numeric(s[k].str.slice(19), errors="coerce").fillna(0.0)
        out[k] = (pd.to_datetime(s[k].str.slice(0, 19), format="%Y-%m-%d %H:%M:%S", errors="coerce")
                  + pd.to_timedelta(frac, unit="s"))
    k = s.str.fullmatch(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}")
    if k.any():
        out[k] = pd.to_datetime(s[k], format="%Y-%m-%d %H:%M", errors="coerce")
    k = s.str.fullmatch(r"\d{4}-\d{2}-\d{2}")
    if k.any():
        out[k] = pd.to_datetime(s[k], format="%Y-%m-%d", errors="coerce")
    return out


def _clock_text(t):
    """'yyyy-mm-dd HH:MM:SS' (milliseconds when not zero)"""
    if t is None or pd.isna(t):
        return ""
    t = pd.Timestamp(t)
    ms = _mround(t.microsecond / 1000 + t.nanosecond / 1e6)
    if ms in (0, 1000):
        return t.round("s").strftime("%Y-%m-%d %H:%M:%S")
    return t.strftime("%Y-%m-%d %H:%M:%S.") + f"{ms:03d}"


def _hms(t):
    return pd.Timestamp(t).round("s").strftime("%H:%M:%S")


def _nanmedian(x):
    x = np.asarray(x, float)
    x = x[~np.isnan(x)]
    return float(np.median(x)) if x.size else math.nan


def _prctile(x, p):
    """MATLAB prctile of a vector (NaN ignored)"""
    x = np.sort(np.asarray(x, float)[~np.isnan(np.asarray(x, float))])
    n = x.size
    if n == 0:
        return math.nan
    if n == 1:
        return float(x[0])
    q = 100 * (np.arange(1, n + 1) - 0.5) / n
    return float(np.interp(min(max(p, q[0]), q[-1]), q, x))


def _unique(x):
    out = []
    for v in x:
        if v not in out:
            out.append(v)
    return out


# ------------------------------------------------------------------------------------------------------------- pool
def pool_timepoints(source, labels=None, order=None, name="pooled", output_folder="", write=True, figures=True,
                    control=None):
    """Analyses of timepoints (several experiments, samples, days) pooled by treatment: one table with all slices and
    time points (for statistics), tables per sample and per treatment, and the images of timepoints per treatment with
    all its slices. Port of mda_poolTimepoints.m (same arguments, files and values; images as .png and .svg).

        PT = pool_timepoints(results_folder)
        PT = pool_timepoints(source, labels=["OME3uM", "MAVA1uM"], name="myosinModulators")

    source: results folder of the watcher (all analyses <experiment>/timepoints/<label>_<time>/ below it), the folder of
    one analysis, a list of such folders, or the dicts returned by timepoints (nothing is read from the files).
    Options: labels (treatments to pool; default all), order (order of the treatments in the images; default: controls
    first, then by substance and concentration), control (treatments that are controls; default: the labels starting
    with CTRL, control, vehicle or DMSO), name (default 'pooled': name of the folder and of the workbook), output_folder
    (default <results folder>/timepoints_pooled/<name>), write, figures.

    Pooling: treatment = label of timepoints, with substance, concentration and unit taken from it (OME0.5uM --> OME,
    0.5, uM); sample = sampleID of timepoints (option sampleID, slice register or the series name after the setup);
    group = group of timepoints; slice = series and channel of an analysis (sliceID <series>_ch<c>, another slice of
    the slice register: _s<n>). Time points = offsets of the windows (all offsets of the analyses of a treatment). The
    values of a slice and window are those of timepoints (mean of the included beats, SD, SEM, median, quartiles,
    pctBaseline, diastolicForce_delta in uN). Against the controls of the same time point (the control slices of the
    same sample, otherwise all control slices; controlReference, nControlSlices): <parameter>_pctBaseline_vsControl =
    100 * pctBaseline / mean pctBaseline of the controls, diastolicForce_delta_vsControl = delta - mean delta of the
    controls (uN). Slices of one sample are not independent: the sheet samples has the
    means per sample; with slices as data points use the sample as random effect. Analyses of older versions (without
    sampleID and SEM) are skipped (sheet analyses).

    Output files (output_folder): <name>.xlsx with the sheets slices (one row per slice and time point: treatment,
    substance, concentration, concentrationUnit, group, sampleID, sliceID, timePoint, offset_min, isBaseline, the
    summary columns of timepoints, analysis, controlReference, nControlSlices, <...>_vsControl), samples, treatments
    (per treatment and time point: n slices, n samples; per parameter and normalized value mean, SD, SEM of the slices,
    mean and SEM of the samples: <parameter>_samples, <parameter>_samplesSEM), course (mean and SEM of the 1-min values
    of the slices per minute after the treatment), averageBeatsMean, analyses and info;
    <treatment>/<treatment>_timepoints_abs / _norm, _course_abs / _norm, _averageBeatsMean_abs / _norm (.png, .svg);
    treatments_abs / _norm / _vsControl (.png, .svg): per parameter and time point the slices (dots) and their mean +-
    SEM for every treatment.

    Returns a dict with the same data: name, parameters, units, slices, samples, treatments, course, averageBeatsMean,
    analyses, notes, controls, info, folder, files.

    TS 2026-10-16"""
    name = str(name)
    if not re.fullmatch(r"[A-Za-z0-9._-]+", name):
        raise ValueError("pool_timepoints: name: letters, digits, '.', '-' and '_' expected.")
    A, notes, res_folder = _collect_analyses(source)
    if labels:
        labels = [labels] if isinstance(labels, str) else list(labels)
        A = [a for a in A if a["label"] in labels]
    use = [not a["skip"] for a in A]
    notes += [f"{a['name']}: {a['skip']}" for a in A if a["skip"]]
    An = _analyses_table(A, use)
    A = [a for a, u in zip(A, use) if u]
    if not A:
        raise ValueError("pool_timepoints: no analysis of timepoints found (or none of the labels).")
    pars = [p for p in A[0]["parameters"] if all(p in a["parameters"] for a in A[1:])]
    if len(pars) < len(A[0]["parameters"]):
        notes.append("parameters: only those of all analyses")
    units = [u for p, u in zip(A[0]["parameters"], A[0]["units"]) if p in pars]
    treat = _treatment_order(_unique([a["label"] for a in A]), [order] if isinstance(order, str) else list(order or []))
    Sl = _slice_table(A, pars)
    ctrl = ([control] if isinstance(control, str) else list(control)) if control else [
        t for t in treat if re.match(r"(ctrl|control|vehicle|dmso)", t, re.I)]
    Sl, nt = _control_columns(Sl, pars, ctrl)
    notes += nt
    Sm = _sample_table(Sl, pars)
    Tr = _treatment_table(Sl, Sm, pars, treat)
    Co, Ab, TPs = _treatment_data(A, Sl, pars, units, treat)
    PT = {"name": name, "parameters": pars, "units": units, "slices": Sl, "samples": Sm, "treatments": Tr,
          "course": Co, "averageBeatsMean": Ab, "analyses": An, "notes": notes, "controls": ctrl}
    PT["info"] = _pool_info(PT, treat)
    PT["folder"], PT["files"] = "", []
    if not write:
        return PT
    d = str(output_folder or "")
    if not d:
        if not res_folder:
            raise ValueError("pool_timepoints: output_folder: needed (no results folder of the watcher known).")
        d = os.path.join(res_folder, "timepoints_pooled", name)
    os.makedirs(d, exist_ok=True)
    x = os.path.join(d, name + ".xlsx")
    if os.path.isfile(x):
        os.remove(x)
    with pd.ExcelWriter(x, engine="openpyxl") as w:
        for sh, T in (("slices", Sl), ("samples", Sm), ("treatments", Tr), ("course", Co), ("averageBeatsMean", Ab),
                      ("analyses", An), ("info", PT["info"])):
            T.to_excel(w, sheet_name=sh, index=False)
    files = [x]
    if figures:
        import matplotlib
        matplotlib.use("Agg")
        for t, TP in zip(treat, TPs):
            dt = os.path.join(d, t)
            os.makedirs(dt, exist_ok=True)
            files += _write_figures(dt, t, TP, ("timepoints", "course", "averageBeatsMean"))
        for m in ("abs", "norm", "vsControl") if ctrl else ("abs", "norm"):
            f = os.path.join(d, "treatments_" + m)
            _save(_treatments_figure(Sl, pars, units, treat, TPs, m, name), f)
            files += [f + ".png", f + ".svg"]
    PT["folder"], PT["files"] = d, files
    return PT


def _collect_analyses(source):
    """analyses of timepoints: dicts of timepoints or the workbooks <label>_<time>.xlsx of the folders"""
    notes, res_folder = [], ""
    if isinstance(source, dict):
        source = [source]
    if isinstance(source, (list, tuple)) and source and all(isinstance(s, dict) for s in source):
        A = []
        for TP in source:
            f = TP["folder"] if isinstance(TP["folder"], str) else "; ".join(TP["folder"])
            t = pd.Timestamp(TP["time"]).strftime("%Y-%m-%d-%H-%M")
            a = {"name": f"{TP['label']}_{t}", "folder": f, "label": TP["label"], "summary": TP["summary"],
                 "course": TP["course"], "averageBeats": TP["averageBeats"], "parameters": list(TP["parameters"]),
                 "units": list(TP["units"]), "offsets": np.asarray(TP["offsets"], float), "baseline": TP["baseline"],
                 "seconds": TP["seconds"], "version": _info_get(TP["info"], "version"), "skip": ""}
            a["skip"] = _check_summary(a)
            A.append(a)
            if not res_folder:
                res_folder = _info_get(TP["info"], "resultsFolder")
        return A, notes, res_folder
    F = [source] if isinstance(source, (str, os.PathLike)) else list(source)
    D = []
    for f in F:
        f = str(f)
        if not os.path.isdir(f):
            raise ValueError(f"pool_timepoints: {f}: no folder.")
        f = os.path.realpath(f)
        n = os.path.basename(f)
        if os.path.isfile(os.path.join(f, n + ".xlsx")):
            D.append(f)
        else:
            found = []
            for r, dirs, fs in os.walk(f):
                if os.path.basename(os.path.dirname(r)) == "timepoints" and os.path.basename(r) + ".xlsx" in fs:
                    found.append(r)
            D += sorted(found)
            if not res_folder and os.path.isfile(os.path.join(f, "mda_index.csv")):
                res_folder = f
    A = []
    for d in _unique(D):
        a = _read_analysis(d)
        if not res_folder and a["resultsFolder"]:
            res_folder = a["resultsFolder"]
        a.pop("resultsFolder")
        A.append(a)
    return A, notes, res_folder


def _read_analysis(d):
    """one analysis from its workbook <d>/<name>.xlsx (sheets summary, course, averageBeats, info)"""
    n = os.path.basename(d)
    x = os.path.join(d, n + ".xlsx")
    a = {"name": n, "folder": d, "label": "", "summary": pd.DataFrame(), "course": pd.DataFrame(),
         "averageBeats": pd.DataFrame(), "parameters": [], "units": [], "offsets": np.zeros(0), "baseline": math.nan,
         "seconds": math.nan, "version": "", "skip": "", "resultsFolder": ""}
    try:
        I = _sheet(x, "info", ("key", "value"))
    except Exception:  # noqa: BLE001 - not an analysis of timepoints
        a["skip"] = "no sheet info"
        return a
    a["label"], a["version"] = _info_get(I, "label"), _info_get(I, "version")
    a["resultsFolder"] = _info_get(I, "resultsFolder")
    a["parameters"] = _info_get(I, "parameters").split()
    U = dict(u.split("=", 1) for u in _info_get(I, "units").split() if "=" in u)
    a["units"] = [U.get(p, "") for p in a["parameters"]]
    a["offsets"] = np.array([float(v) for v in _info_get(I, "offsets_min").split()], float)
    b = _info_get(I, "baseline_min")
    a["baseline"] = math.nan if b in ("", "none") else float(b)
    a["seconds"] = float(_info_get(I, "seconds") or "nan")
    a["summary"] = _sheet(x, "summary", ("series", "sampleID", "group", "time", "from", "to", "recording", "note"))
    a["skip"] = _check_summary(a)
    if a["skip"]:
        return a
    a["course"] = _sheet(x, "course", ("series", "time", "window"))
    AB = _sheet(x, "averageBeats", ("series", "trace", "note"))
    if "note" in AB.columns and "t_s" not in AB.columns:  # more than 1 million rows
        f = os.path.join(d, n + "_averageBeats.csv")
        AB = pd.read_csv(f, dtype={"series": str, "trace": str}) if os.path.isfile(f) else pd.DataFrame()
    a["averageBeats"] = AB
    return a


def _sheet(x, s, text):
    """sheet s of the workbook x; the columns text as text, all others as numbers"""
    T = pd.read_excel(x, sheet_name=s, dtype={c: object for c in text})
    for c in T.columns:
        if c in text:
            T[c] = T[c].map(lambda v: "" if v is None or (isinstance(v, float) and math.isnan(v)) else str(v))
        else:
            T[c] = pd.to_numeric(T[c], errors="coerce").astype(float)
    return T


def _info_get(I, key):
    if I is None or not {"key", "value"} <= set(I.columns):
        return ""
    v = I.loc[I["key"].astype(str) == key, "value"]
    if v.empty or (isinstance(v.iloc[0], float) and math.isnan(v.iloc[0])):
        return ""
    return str(v.iloc[0])


def _check_summary(a):
    """'' or why the analysis cannot be pooled"""
    S = a["summary"]
    if S is None or S.empty:
        return "empty summary"
    if not {"sampleID", "group"} <= set(S.columns) or not a["parameters"] or a["parameters"][0] + "_SEM" not in S:
        return "older version of mda_timepoints (no sampleID, SEM): call mda_timepoints again"
    return ""


def _analyses_table(A, use):
    rows = []
    for a, u in zip(A, use):
        S = a["summary"]
        ns, sid = 0, ""
        if S is not None and len(S) and {"series", "channel"} <= set(S.columns):
            ns = len(S[["series", "channel"]].drop_duplicates())
            if "sampleID" in S.columns:
                sid = " ".join(_unique(list(S["sampleID"])))
        rows.append((a["name"], a["label"], sid, ns, "pooled" if u else "skipped: " + a["skip"], a["folder"]))
    return pd.DataFrame(rows, columns=["analysis", "treatment", "sampleID", "nSlices", "status", "folder"])


def _treatment_order(t, order):
    """controls first, then by substance and concentration (molar); 'order' first"""
    def key(x):
        s, c, u = _split_label(x)
        m = c * _unit_factor(u)
        return (not re.match(r"(ctrl|control|vehicle|dmso)", x, re.I), s.lower(), (1, 0.0) if math.isnan(m)
                else (0, m))
    t = sorted(t, key=key)
    first = [x for x in order if x in t]
    return first + [x for x in t if x not in first]


def _split_label(label):
    """substance, concentration and unit of a treatment label (OME0.5uM --> OME, 0.5, uM; OME0p5uM as well)"""
    m = re.match(r"^(.*?)[_-]?(\d+(?:[.,p]\d+)?)\s*(pM|nM|uM|µM|mM|M)$", label)
    if not m or not m.group(1):
        return label, math.nan, ""
    return m.group(1), float(re.sub(r"[,p]", ".", m.group(2))), m.group(3)


def _unit_factor(u):
    return {"pM": 1e-12, "nM": 1e-9, "uM": 1e-6, "µM": 1e-6, "mM": 1e-3, "M": 1.0}.get(u, 1.0)


def _pool_offset_labels(off):
    return ["" if math.isnan(float(o)) else lab for o, lab in zip(off, _offset_labels([0 if math.isnan(float(o))
                                                                                      else o for o in off]))]


def _slice_table(A, pars):
    """one row per slice and window: treatment, sample, slice, time point and the summary columns of timepoints"""
    parts = []
    for a in A:
        S = a["summary"].reset_index(drop=True)
        s, c, u = _split_label(a["label"])
        n = len(S)
        sid = [""] * n
        for (se, ch), g in S.groupby(["series", "channel"], sort=True):
            r = g.index.to_numpy()
            sl = S.loc[r[S["offset_min"].to_numpy(float)[r] == a["baseline"]], "slice"].to_numpy(float)
            if not sl.size or math.isnan(sl[0]):
                sl = S.loc[r, "slice"].to_numpy(float)
                sl = sl[~np.isnan(sl)]
            i_ = f"{se}_ch{int(ch)}"
            if sl.size and sl[0] > 1:
                i_ += f"_s{int(sl[0])}"
            for k in r:
                sid[k] = i_
        T = pd.DataFrame({"treatment": a["label"], "substance": s, "concentration": c, "concentrationUnit": u,
                          "group": S["group"].to_numpy(), "sampleID": S["sampleID"].to_numpy(), "sliceID": sid,
                          "timePoint": _pool_offset_labels(S["offset_min"].to_numpy(float)),
                          "offset_min": S["offset_min"].to_numpy(float),
                          "isBaseline": (S["offset_min"].to_numpy(float) == a["baseline"]).astype(float)})
        rest = S[[x for x in S.columns if x not in ("sampleID", "group", "offset_min")]].rename(
            columns={"time": "treatmentTime"})
        extra = [p for p in a["parameters"] if p not in pars]
        keep = [x for x in rest.columns if not any(x == p or x.startswith(p + "_") for p in extra)]
        T = pd.concat([T, rest[keep].reset_index(drop=True)], axis=1)
        T["analysis"] = a["name"]
        if parts:
            for x in parts[0].columns:
                if x not in T.columns:
                    T[x] = "" if parts[0][x].dtype == object else np.nan
            T = T[list(parts[0].columns)]
        parts.append(T)
    return pd.concat(parts, ignore_index=True)


def _pool_cols(pars):
    """value, normalized value and normalized value against the controls of every parameter"""
    return [x for p in pars for x in (p, _norm_name(p))] + [_norm_name(p) + "_vsControl" for p in pars]


def _control_columns(Sl, pars, ctrl):
    """normalized values against the controls of the same time point: the control slices of the same sample, otherwise
    all control slices; <parameter>_pctBaseline_vsControl = 100 * value / control mean, diastolicForce_delta_vsControl =
    value - control mean (uN)"""
    Sl = Sl.copy()
    n = len(Sl)
    isC = Sl["treatment"].isin(ctrl).to_numpy()
    off = Sl["offset_min"].to_numpy(float)
    smp = Sl["sampleID"].to_numpy()
    R, ref = [], []
    for i in range(n):
        s = isC & (off == off[i])
        same = s & (smp == smp[i])
        if same.any():
            R.append(same), ref.append("sample")
        elif s.any():
            R.append(s), ref.append("all controls")
        else:
            R.append(np.zeros(n, bool)), ref.append("")
    Sl["controlReference"] = ref
    Sl["nControlSlices"] = [int(r.sum()) for r in R]
    for p in pars:
        q = _norm_name(p)
        x = Sl[q].to_numpy(float)
        v = np.full(n, np.nan)
        for i in range(n):
            if R[i].any():
                m = _nanmean(x[R[i]])
                v[i] = x[i] - m if p == "diastolicForce" else _div(100 * x[i], m)
        Sl[q + "_vsControl"] = v
    return Sl, ([] if ctrl else ["no control treatment: no values against the controls"])


def _nanmean(x):
    x = np.asarray(x, float)
    x = x[~np.isnan(x)]
    return float(x.mean()) if x.size else math.nan


def _sd_of(x):
    x = np.asarray(x, float)
    x = x[~np.isnan(x)]
    return float(x.std(ddof=1)) if x.size > 1 else math.nan


def _sem_of(x):
    x = np.asarray(x, float)
    x = x[~np.isnan(x)]
    return float(x.std(ddof=1) / math.sqrt(x.size)) if x.size > 1 else math.nan


def _sample_table(Sl, pars):
    """per treatment, sample and window: number of slices and the mean of the slices of every parameter"""
    rows = []
    for (tr, smp, off), g in Sl.groupby(["treatment", "sampleID", "offset_min"], sort=True):
        r = {"treatment": tr, "group": g["group"].iloc[0], "sampleID": smp, "offset_min": _num(off),
             "timePoint": _pool_offset_labels([off])[0], "nSlices": len(g)}
        for c in _pool_cols(pars):
            r[c] = _nanmean(g[c])
        rows.append(r)
    return pd.DataFrame(rows, columns=["treatment", "group", "sampleID", "offset_min", "timePoint", "nSlices"]
                        + _pool_cols(pars))


def _treatment_table(Sl, Sm, pars, treat):
    """per treatment and window: n slices, n samples; per parameter mean, SD, SEM of the slices, mean and SEM of the
    samples"""
    rows = []
    for (tr, off), g in Sl.groupby(["treatment", "offset_min"], sort=True):
        r = {"treatment": tr, "offset_min": _num(off), "timePoint": _pool_offset_labels([off])[0], "nSlices": len(g),
             "nSamples": g["sampleID"].nunique()}
        gs = Sm[(Sm["treatment"] == tr) & (Sm["offset_min"].to_numpy(float) == off)]
        for c in _pool_cols(pars):
            r[c], r[c + "_SD"], r[c + "_SEM"] = _nanmean(g[c]), _sd_of(g[c]), _sem_of(g[c])
            r[c + "_samples"], r[c + "_samplesSEM"] = _nanmean(gs[c]), _sem_of(gs[c])
        rows.append(r)
    T = pd.DataFrame(rows)
    T["_o"] = [treat.index(x) for x in T["treatment"]]
    return T.sort_values(["_o", "offset_min"], kind="mergesort").drop(columns="_o").reset_index(drop=True)


def _treatment_data(A, Sl, pars, units, treat):
    """per treatment: course (mean and SEM of the slices per minute), mean of the average beats, TP dict for the
    images"""
    cols = [x for p in pars for x in (p, _norm_name(p))]
    cparts, aparts, TPs = [], [], []
    for t in treat:
        ia = [a for a in A if a["label"] == t]
        S = Sl[Sl["treatment"] == t].reset_index(drop=True)
        off = np.unique(np.concatenate([np.asarray(a["offsets"], float) for a in ia]))
        bl = [a["baseline"] for a in ia]
        bl = bl[0] if all(b == bl[0] for b in bl) and not math.isnan(bl[0]) else math.nan
        sec = ia[0]["seconds"]
        key = (S["analysis"] + "|" + S["series"]).to_list()
        kc = [f"{k}|{int(c)}" for k, c in zip(key, S["channel"])]
        u = _unique(kc)
        iu = [kc.index(x) for x in u]
        nP, nK = len(u), off.size
        R = pd.DataFrame({"series": [key[i] for i in iu], "channel": [int(S["channel"].iloc[i]) for i in iu],
                          "label": [f"{S['sampleID'].iloc[i]} {S['series'].iloc[i].split('_')[0]} "
                                    f"ch{int(S['channel'].iloc[i])}" for i in iu],
                          "sampleID": [S["sampleID"].iloc[i] for i in iu],
                          "time": [S["treatmentTime"].iloc[i] for i in iu]})
        Su = pd.DataFrame({"series": np.repeat(R["series"].to_numpy(), nK), "channel": np.repeat(R["channel"], nK),
                           "offset_min": np.tile(off, nP)})
        TP = {"label": t, "offsets": off, "seconds": sec, "baseline": bl, "parameters": pars, "units": units,
              "rows": R, "matrix": {}, "pctBaseline": {}}
        keyarr, ch = np.array(key, dtype=object), S["channel"].to_numpy(float)
        for par in pars:
            M, Q, E = (np.full((nP, nK), np.nan) for _ in range(3))
            for p in range(nP):
                s = (keyarr == R["series"].iloc[p]) & (ch == R["channel"].iloc[p])
                k = np.searchsorted(off, S["offset_min"].to_numpy(float)[s])
                M[p, k] = S[par].to_numpy(float)[s]
                Q[p, k] = S[_norm_name(par)].to_numpy(float)[s]
                E[p, k] = S[par + "_SEM"].to_numpy(float)[s]
            TP["matrix"][par], TP["pctBaseline"][par] = M, Q
            Su[par + "_SEM"] = E.ravel()
        TP["summary"] = Su
        cp = []  # course: 1-min values of the slices
        for a in ia:
            C = a["course"]
            if C is None or not len(C) or not set(["series", "channel", "minutes"] + cols) <= set(C.columns):
                continue
            C = C[["series", "channel", "minutes"] + cols].copy()
            C["series"] = a["name"] + "|" + C["series"].astype(str)
            cp.append(C)
        C = (pd.concat(cp, ignore_index=True) if cp
             else pd.DataFrame({c: pd.Series([], dtype=float) for c in ["series", "channel", "minutes"] + cols}))
        if len(C):
            C = C[np.isin([f"{s_}|{int(c_)}" for s_, c_ in zip(C["series"], C["channel"])], u)].reset_index(drop=True)
        TP["course"] = C
        if len(C):
            mm = C["minutes"].to_numpy(float)
            m = np.sign(mm) * np.floor(np.abs(mm) + 0.5)
            kk = np.array([f"{s_}|{int(c_)}" for s_, c_ in zip(C["series"], C["channel"])], dtype=object)
            rows = []
            for v in np.unique(m):
                s = m == v
                r = {"treatment": t, "minutes": _num(v), "nSlices": len(set(kk[s]))}
                for c in cols:
                    r[c], r[c + "_SEM"] = _nanmean(C[c].to_numpy(float)[s]), _sem_of(C[c].to_numpy(float)[s])
                rows.append(r)
            cparts.append(pd.DataFrame(rows))
        ap = []  # average beats of the slices (trace all)
        for a in ia:
            B = a["averageBeats"]
            if B is None or not len(B) or "t_s" not in B.columns:
                continue
            B = B[B["trace"] == "all"].copy()
            B["series"] = a["name"] + "|" + B["series"].astype(str)
            ap.append(B)
        AB = pd.concat(ap, ignore_index=True) if ap else pd.DataFrame()
        if len(AB):
            AB = AB[np.isin([f"{s_}|{int(c_)}" for s_, c_ in zip(AB["series"], AB["channel"])], u)].reset_index(
                drop=True)
        TP["averageBeats"] = AB
        TP["averageBeatsMean"] = _average_beats_mean(AB, off)
        if len(TP["averageBeatsMean"]):
            aparts.append(pd.concat([pd.DataFrame({"treatment": [t] * len(TP["averageBeatsMean"])}),
                                     TP["averageBeatsMean"]], axis=1))
        b = "" if math.isnan(bl) else f", baseline {_offset_labels([bl])[0]}"
        TP["unitName"] = "slices"
        TP["title"] = (f"{t} (pooled): {nP} slice(s) of {R['sampleID'].nunique()} sample(s), windows of "
                       f"{_g(sec)} s{b}")
        TPs.append(TP)
    Co = (pd.concat(cparts, ignore_index=True) if cparts else
          pd.DataFrame({c: pd.Series([], dtype=float) for c in ["treatment", "minutes", "nSlices"]}))
    Ab = (pd.concat(aparts, ignore_index=True) if aparts else
          pd.concat([pd.DataFrame({"treatment": pd.Series([], dtype=object)}), _average_beats_mean(None, [0])], axis=1))
    return Co, Ab, TPs


def _pool_info(PT, treat):
    rows = [("function", "mda_poolTimepoints"), ("version", mda_version()), ("implementation", "Python"),
            ("analysisDate", _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")), ("name", PT["name"]),
            ("treatments", " ".join(treat)), ("controls", " ".join(PT["controls"])),
            ("parameters", " ".join(PT["parameters"])),
            ("units", " ".join(f"{p}={u}" for p, u in zip(PT["parameters"], PT["units"]))),
            ("values", "per slice and window as mda_timepoints: mean (column <parameter>), SD, SEM, median, q25, q75 "
             "of the included beats; <parameter>_pctBaseline = 100 * mean / mean of the baseline window of the "
             "slice; diastolicForce_delta = mean - baseline mean (uN)"),
            ("vsControl", "against the controls of the same time point (the control slices of the same sample, "
             "otherwise all control slices: controlReference, nControlSlices): <parameter>_pctBaseline_vsControl = "
             "100 * pctBaseline / mean pctBaseline of the controls; diastolicForce_delta_vsControl = delta - mean "
             "delta of the controls (uN)"),
            ("samples", "mean of the slices of a sample per treatment and window (slices of a sample are not "
             "independent)"),
            ("treatmentsSheet", "per treatment and window: mean, SD and SEM of the slices; <parameter>_samples, "
             "<parameter>_samplesSEM: mean and SEM of the sample means"),
            ("course", "mean and SEM of the 1-min values of the slices per minute after the treatment (rounded)"),
            ("notes", "; ".join(PT["notes"]))]
    return pd.DataFrame(rows, columns=["key", "value"])


def _treatments_figure(Sl, pars, units, treat, TPs, mode, name):
    """per parameter: x = treatments; per window the slices (dots) and their mean +- SEM; norm and vsControl (against
    the controls): windows after the baseline"""
    import matplotlib.pyplot as plt
    norm, vs = mode != "abs", mode == "vsControl"
    offs = np.unique(Sl["offset_min"].to_numpy(float))
    bl = set(Sl.loc[Sl["isBaseline"] == 1, "offset_min"].to_numpy(float))
    if norm:
        offs = np.array([o for o in offs if o not in bl])
    nT, nK = len(treat), offs.size
    nr, nc = _grid(len(pars))
    fig, axs = plt.subplots(nr, nc, figsize=(max(4.2, 0.55 * nT + 1.5) * nc, 3.4 * nr + 0.6), squeeze=False)
    col = _colors(nK + 1)[1:]
    col = ["k" if o in bl else c for o, c in zip(offs, col)]
    L = _offset_labels(offs)
    w = 0.7 / max(nK, 1)
    tr = Sl["treatment"].to_numpy()
    of = Sl["offset_min"].to_numpy(float)
    for i, par in enumerate(pars):
        ax = axs[i // nc][i % nc]
        v = _norm_name(par) + "_vsControl" if vs else _norm_name(par) if norm else par
        val = Sl[v].to_numpy(float)
        for k in range(nK):
            x0 = np.arange(1, nT + 1) + (k + 1 - (nK + 1) / 2) * w
            mu, se = np.full(nT, np.nan), np.full(nT, np.nan)
            for j, t in enumerate(treat):
                y = val[(tr == t) & (of == offs[k])]
                y = y[~np.isnan(y)]
                if not y.size:
                    continue
                jx = x0[j] + ((np.arange(1, y.size + 1) * 0.618) % 1 - 0.5) * w * 0.6
                ax.plot(jx, y, ".", color=col[k], alpha=0.45, markersize=5)
                mu[j], se[j] = y.mean(), _sem_of(y)
            ax.errorbar(x0, mu, yerr=se, fmt="o", color=col[k], markersize=5, linewidth=1.2, capsize=3, label=L[k])
        if norm:
            ax.axhline(_norm_ref(par), linestyle=":", color="0.5")
        ax.set_xticks(np.arange(1, nT + 1))
        ax.set_xticklabels(treat, rotation=45, ha="right", fontsize=7)
        ax.set_xlim(0.4, nT + 0.6)
        ax.tick_params(labelsize=7)
        if vs:
            yl = ("change against the baseline - controls (uN)" if par == "diastolicForce"
                  else "% of baseline, % of the controls")
        else:
            yl = _axis_label(par, units[i], norm)
        ax.set_ylabel(yl, fontsize=8)
        ax.set_title(_unit_title(par, units[i]), fontsize=9)
        if i == 0:
            ax.legend(fontsize=6, frameon=False)
    for i in range(len(pars), nr * nc):
        axs[i // nc][i % nc].set_visible(False)
    n = sum(len(TP["rows"]) for TP in TPs)
    m = ("normalized to the baseline window and to the controls" if vs else
         "normalized to the baseline window of the slice" if norm else "absolute")
    fig.suptitle(f"{name}: {nT} treatment(s), {n} slice(s) - slices (dots) and mean +- SEM, {m}", fontsize=10)
    fig.tight_layout()
    return fig
