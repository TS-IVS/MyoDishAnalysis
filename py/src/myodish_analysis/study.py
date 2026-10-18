# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Study of time points from a design table (port of mda_study.m; same arguments, files and values).

    R = study("design.xlsx")
    R = study("design.xlsx", resultsFolder="/data/results", name="PKC_rabbit")
    study_template("design.xlsx")

The design table has one row per slice (sheet slices of an .xlsx file, or a .csv file):
  series         recordings of one setup: the file name up to its number (Setup1_ABC000101 for Setup1_ABC000101_3.mdd)
  channel        channel of the slice
  treatment      name of the treatment (label of timepoints: letters, digits, '.', '-', '_'), e.g. CTRL, PMA50nM
  time           clock time of the treatment ('yyyy-mm-dd HH:MM[:SS]'; with t0 = chamberIn the documented time)
  sampleID       sample (heart, tissue) of the slice (default: slice register or series name)
  group          group of the sample (optional)
  exclude        empty, 'all' (whole slice) or the offset (min) from which the windows are left out
  excludeReason  reason of the exclusion (listed in the sheet excluded and the methods text)
and optional settings (sheet settings of the .xlsx file: key, value; or keyword arguments, which have priority):
  resultsFolder (results folder of the watcher; required), name (default 'study'), outputFolder (default
  <resultsFolder>/studies/<name>), offsets (minutes, e.g. '-30 10 60 180 360 720 1380'; required), seconds (default
  120), baseline (default: the last negative offset), t0 ('given' or 'chamberIn', default 'given'), t0Window (default
  90), control and order (treatments, separated by spaces), parameters (default those of timepoints), rawFolder,
  averageBeats (default true), figures (default true).

The study runs timepoints once per treatment (all its slices; files in <study>/analyses/<experiment>/<label>_<time>/)
and pool_timepoints with all analyses and the exclusions, into the study folder: <name>.xlsx (slices, samples,
treatments, statistics, qc, excluded, course, averageBeatsMean, analyses, info), images, <name>_figure_norm (.pdf,
.svg, .png), <name>_prism.xlsx, a copy of the design (design_<name>.xlsx or .csv) and <name>_methods.txt (methods text
for a manuscript, generated from the settings, the groups and the exclusions; check it before use).

Returns a dict: name, folder, design (DataFrame), settings, analyses (folders), pool (dict of pool_timepoints), methods
(text), files.

TS 2026-10-18
"""
from __future__ import annotations

import math
import os
import re
import shutil

import numpy as np
import pandas as pd

from .timepoints import pool_timepoints, timepoints
from .write_results import mda_version

DESIGN_COLUMNS = ["series", "channel", "treatment", "time", "sampleID", "group", "exclude", "excludeReason"]
SETTINGS = [("resultsFolder", "", "results folder of the watcher (folder with mda_index.csv); required"),
            ("name", "study", "name of the study: folder and workbook"),
            ("outputFolder", "", "folder of the study (default <resultsFolder>/studies/<name>)"),
            ("offsets", "", "start of the windows in minutes after the treatment, e.g. -30 10 60 180; required"),
            ("seconds", "120", "duration of every window (s)"),
            ("baseline", "", "offset of the reference window (default: the last negative offset; none: no baseline)"),
            ("t0", "given", "time 0: given (the time of the design) or chamberIn (end of the chamber-out period of "
                            "the channel nearest to it)"),
            ("t0Window", "90", "chamberIn: periods ending within +- this many minutes of the given time"),
            ("control", "", "treatments that are controls, separated by spaces (default: labels starting with CTRL, "
                            "control, vehicle or DMSO)"),
            ("order", "", "order of the treatments in the images, separated by spaces"),
            ("parameters", "", "parameters, separated by spaces (default those of timepoints)"),
            ("rawFolder", "", "raw folder of the watcher (average beats; default: the path of the analysis)"),
            ("averageBeats", "true", "average beats from the raw data (true / false)"),
            ("figures", "true", "images (true / false)")]


def study_template(file):
    """design table to fill in: sheet slices (one example row) and sheet settings (keys, defaults, descriptions)"""
    D = pd.DataFrame([["Setup1_ABC000101", 1, "CTRL", "2000-01-01 12:00", "ABC000101", "", "", ""],
                      ["Setup1_ABC000101", 2, "PMA50nM", "2000-01-01 12:00", "ABC000101", "", 720,
                       "arrhythmic from +12 h"]], columns=DESIGN_COLUMNS)
    St = pd.DataFrame([(k, v if k != "offsets" else "-30 10 60 180 360 720 1380", d) for k, v, d in SETTINGS],
                      columns=["key", "value", "description"])
    with pd.ExcelWriter(file, engine="openpyxl") as w:
        D.to_excel(w, sheet_name="slices", index=False)
        St.to_excel(w, sheet_name="settings", index=False)
    return file


def _text(v):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return ""
    if isinstance(v, pd.Timestamp):
        return v.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(v, float) and v == int(v):
        return str(int(v))
    return str(v).strip()


def _read_design(design):
    """design table (DataFrame) and the settings of the file"""
    settings = {}
    if isinstance(design, pd.DataFrame):
        D = design.copy()
    else:
        f = str(design)
        if f.lower().endswith((".xlsx", ".xls")):
            x = pd.ExcelFile(f)
            D = x.parse("slices" if "slices" in x.sheet_names else x.sheet_names[0], dtype=object)
            if "settings" in x.sheet_names:
                S = x.parse("settings", dtype=object)
                for k, v in zip(S.iloc[:, 0], S.iloc[:, 1]):
                    if _text(k):
                        settings[_text(k)] = _text(v)
        else:
            D = pd.read_csv(f, dtype=object, keep_default_na=False)
    D.columns = [str(c).strip() for c in D.columns]
    miss = [c for c in ("series", "channel", "treatment", "time") if c not in D.columns]
    if miss:
        raise ValueError("study: design: columns missing: " + ", ".join(miss))
    for c in DESIGN_COLUMNS:
        if c not in D.columns:
            D[c] = ""
    D = D[[_text(s) != "" for s in D["series"]]].reset_index(drop=True)
    if D.empty:
        raise ValueError("study: design: no slices.")
    out = pd.DataFrame({c: [_text(v) for v in D[c]] for c in DESIGN_COLUMNS})
    out["channel"] = [int(float(c)) for c in out["channel"]]
    for t in out["treatment"]:
        if not re.fullmatch(r"[A-Za-z0-9._-]+", t):
            raise ValueError(f"study: design: treatment '{t}': letters, digits, '.', '-' and '_' expected.")
    for e in out["exclude"]:
        if e and e.lower() != "all":
            float(e)
    return out, settings


def _bool(v):
    return str(v).strip().lower() not in ("false", "0", "no", "")


def _list(v):
    return [x for x in re.split(r"[\s,;]+", str(v).strip()) if x] if str(v).strip() else []


def study(design, **overrides):
    """study from a design table: see the module documentation"""
    D, settings = _read_design(design)
    P = {k: v for k, v, _ in SETTINGS}
    P.update(settings)
    P.update({k: _text(v) if not isinstance(v, (list, tuple)) else " ".join(map(str, v))
              for k, v in overrides.items() if k in P})
    unknown = [k for k in overrides if k not in P]
    if unknown:
        raise ValueError("study: unknown settings: " + ", ".join(unknown))
    if not P["resultsFolder"]:
        raise ValueError("study: resultsFolder: the results folder of the watcher expected.")
    off = [float(x) for x in _list(P["offsets"])]
    if not off:
        raise ValueError("study: offsets: minutes after the treatment expected, e.g. -30 10 60.")
    name = P["name"] or "study"
    if not re.fullmatch(r"[A-Za-z0-9._-]+", name):
        raise ValueError("study: name: letters, digits, '.', '-' and '_' expected.")
    folder = P["outputFolder"] or os.path.join(P["resultsFolder"], "studies", name)
    os.makedirs(folder, exist_ok=True)
    b = P["baseline"].strip().lower()
    baseline = None if b == "" else (math.nan if b == "none" else float(b))
    figures, avg = _bool(P["figures"]), _bool(P["averageBeats"])
    pars = _list(P["parameters"])
    kw = dict(seconds=float(P["seconds"]), baseline=baseline, write=True, figures=figures, average_beats=avg,
              raw_folder=P["rawFolder"], t0=P["t0"], t0_window=float(P["t0Window"]),
              output_folder=os.path.join(folder, "analyses"))
    if pars:
        kw["parameters"] = pars
    folders, TPs = [], []
    for t in list(dict.fromkeys(D["treatment"])):  # one call of timepoints per treatment, all its slices
        Dt = D[D["treatment"] == t]
        S = list(dict.fromkeys(Dt["series"]))
        ch = [list(Dt.loc[Dt["series"] == s, "channel"]) for s in S]
        tm = [x for s in S for x in Dt.loc[Dt["series"] == s, "time"]]
        smp, grp = [], []
        for s in S:
            for col, out in (("sampleID", smp), ("group", grp)):
                u = list(dict.fromkeys(Dt.loc[Dt["series"] == s, col]))
                if len(u) > 1:
                    raise ValueError(f"study: design: treatment {t}, series {s}: one {col} expected.")
                out.append(u[0])
        TP = timepoints(P["resultsFolder"], t, S, ch, tm, off, sampleID=smp if any(smp) else "",
                        group=grp if any(grp) else "", **kw)
        TPs.append(TP)
        folders += [TP["folder"]] if isinstance(TP["folder"], str) else list(TP["folder"])
    ex = [(r.series, r.channel, None if r.exclude.lower() == "all" else float(r.exclude), r.excludeReason)
          for r in D.itertuples() if r.exclude]
    PT = pool_timepoints(folders, order=_list(P["order"]) or None, name=name, output_folder=folder, figures=figures,
                         control=_list(P["control"]) or None, exclude=ex or None)
    if isinstance(design, pd.DataFrame):
        dc = os.path.join(folder, f"design_{name}.xlsx")
        with pd.ExcelWriter(dc, engine="openpyxl") as w:
            D.to_excel(w, sheet_name="slices", index=False)
            pd.DataFrame([(k, P[k]) for k, _, _ in SETTINGS], columns=["key", "value"]).to_excel(
                w, sheet_name="settings", index=False)
    else:
        dc = os.path.join(folder, f"design_{name}" + os.path.splitext(str(design))[1].lower())
        if os.path.realpath(str(design)) != os.path.realpath(dc):
            shutil.copyfile(str(design), dc)
    M = methods_text(PT, P, off, TPs)
    mf = os.path.join(folder, f"{name}_methods.txt")
    with open(mf, "w", encoding="utf-8") as fh:
        fh.write(M + "\n")
    return {"name": name, "folder": folder, "design": D, "settings": P, "analyses": folders, "pool": PT,
            "methods": M, "files": PT["files"] + [dc, mf]}


def _minutes_text(off):
    def one(o):
        if o == 0:
            return "0 min"
        if o % 60 == 0:
            return f"{o / 60:+g} h"
        return f"{o:+g} min"
    return ", ".join(one(o) for o in off)


def methods_text(PT, P, off, TPs=()):
    """methods paragraph for a manuscript (English; check before use)"""
    Sl, Ex = PT["slices"], PT["excluded"]
    b = [o for o in off if o < 0]
    base = P["baseline"].strip().lower()
    bo = None if base == "none" else (float(base) if base else (max(b) if b else None))
    t0 = ("the documented time of the addition" if str(P["t0"]).lower() in ("", "given") else
          "the reinsertion of the chamber after the addition (end of the chamber-out period of the channel nearest to "
          f"the documented time, within ±{_text(P['t0Window'])} min)")
    s = (f"Contraction parameters were analysed with MyoDishAnalysis {mda_version()} from the results of its "
         f"automatic batch analysis (watcher). For every slice, the parameters of the contractions were averaged in "
         f"windows of {_text(P['seconds'])} s starting {_minutes_text(off)} relative to the treatment (time 0 = "
         f"{t0}). In paced slices, only stimulated contractions were averaged; windows with ≥ 5 % extra beats "
         f"were marked as arrhythmic.")
    if bo is not None:
        s += (f" Values were normalized to the window {abs(bo):g} min before the treatment of the same slice "
              "(% of baseline); the diastolic force is given as change from this window (µN).")
    g = []
    for t in list(dict.fromkeys(PT["treatments"]["treatment"])):
        St = Sl[Sl["treatment"] == t]
        nS, nP = St.drop_duplicates(['sampleID', 'sliceID']).shape[0], St['sampleID'].nunique()
        g.append(f"{t} {nS} slice{'s' * (nS != 1)} from {nP} sample{'s' * (nP != 1)}")
    s += " Groups: " + "; ".join(g) + "."
    if len(Ex):
        x = []
        for (smp, sl, why), E in Ex.groupby(["sampleID", "sliceID", "excludeReason"], sort=False):
            o = E["offset_min"].to_numpy(float)
            w = "all windows" if o.min() <= min(off) else f"windows from {_minutes_text([o.min()])}"
            x.append(f"{smp} {sl} ({w}; {why})" if why else f"{smp} {sl} ({w})")
        s += " Excluded: " + "; ".join(x) + "."
    St = PT["statistics"]
    if len(St) and St["lme_p"].notna().any():
        s += (" Treatments were compared with the controls of the same time point by a linear mixed model with the "
              "sample as random intercept (REML; t test with n − 2 degrees of freedom); data are mean ± SEM "
              "of the slices.")
    else:
        s += (" Data are mean ± SEM of the slices; with fewer than 3 samples per group the data are shown "
              "descriptively.")
    return s
