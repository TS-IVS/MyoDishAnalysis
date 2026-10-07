"""Trend window: rolling mean / median of a parameter over long periods and over several .mdd files in a row (e.g. the
daily files _0, _1, _2 ... of a culture). Sampling: all contractions, short windows (W s every T min) or rocker stops
only. Port of the trend part of MyoDishAnalysisGUI.m.

TS 2026-10-06
"""
from __future__ import annotations

import datetime as _dt
import glob
import json
import math
import os
import re

import numpy as np
import pandas as pd
import pyqtgraph as pg
from PySide6 import QtCore, QtWidgets

from .._matlab import Struct, colon, mround
from ..analysis import datenum_to_timestamps, myodish_analysis
from ..log_entries import log_entries
from ..read_mdd import read_mdd
from .timeaxis import fmt_clock
from .widgets import PURPLE, rects, rot_labels, time_plot, vlines

MU = "µ"


def rolling(t, v, w_s, use_median):
    """rolling mean / median over a time window of w_s seconds centred at every point ([t - w/2, t + w/2), as MATLAB
    movmean / movmedian with 'SamplePoints'); NaN values omitted."""
    o = np.argsort(t, kind="stable")
    t = np.asarray(t, float)[o]
    v = np.asarray(v, float)[o]
    lo = np.searchsorted(t, t - w_s / 2, side="left")
    hi = np.searchsorted(t, t + w_s / 2, side="left")
    hi = np.maximum(hi, np.arange(t.size) + 1)
    if not use_median:
        ok = ~np.isnan(v)
        c = np.r_[0, np.cumsum(np.where(ok, v, 0.0))]
        n = np.r_[0, np.cumsum(ok)]
        with np.errstate(invalid="ignore", divide="ignore"):
            r = (c[hi] - c[lo]) / (n[hi] - n[lo])
    else:
        r = np.array([np.nanmedian(v[a:b]) if np.any(~np.isnan(v[a:b])) else np.nan for a, b in zip(lo, hi)])
    return t, r


class TrendWindow(QtWidgets.QWidget):
    def __init__(self, win):
        super().__init__()
        self.win = win
        self.files = []
        self.data = None
        self.sampling = ""
        self.roll = np.zeros((0, 2))
        self._yl0 = [0.0, 1.0]
        self._cmt = []
        self._cmt_items = []
        self.setWindowFlag(QtCore.Qt.WindowType.Window)
        self.setWindowTitle("MyoDishAnalysis: trend")
        self.resize(1300, 660)
        h = QtWidgets.QHBoxLayout(self)
        self.gl = pg.GraphicsLayoutWidget()
        self.p = time_plot()
        self.gl.addItem(self.p)
        self.p.addLegend(offset=(-10, 10), labelTextSize="8pt")
        self.p.vb.on_wheel = self._wheel
        self.p.vb.on_click = self._click
        self.p.vb.sigXRangeChanged.connect(lambda *_: self._ticks())
        h.addWidget(self.gl, 2)
        v = QtWidgets.QVBoxLayout()
        h.addLayout(v, 1)
        v.addWidget(QtWidgets.QLabel("Files in a row (time 0 = start of the first file; order: start time in the log):"))
        self.lbF = QtWidgets.QListWidget()
        v.addWidget(self.lbF, 1)
        hh = QtWidgets.QHBoxLayout()
        for text, cb, tip in (("Add files ...", self.add_files, None),
                              ("Add series (_0, _1, ...)", self.add_series,
                               "all files <name>_<number>.mdd in the folder of the open file"),
                              ("Remove", self.remove, None)):
            b = QtWidgets.QPushButton(text)
            b.clicked.connect(cb)
            if tip:
                b.setToolTip(tip)
            hh.addWidget(b)
        v.addLayout(hh)
        g = QtWidgets.QGridLayout()
        g.addWidget(QtWidgets.QLabel("Channel"), 0, 0)
        self.pC = QtWidgets.QComboBox()
        self.pC.addItems([f"Ch {c}" for c in win.H.dataChannels])
        self.pC.setCurrentIndex(max(0, [int(c) for c in win.H.dataChannels].index(win.ch)))
        self.pC.activated.connect(lambda *_: self.calc(True))
        g.addWidget(self.pC, 0, 1)
        self.pR = QtWidgets.QComboBox()
        self.pR.addItems(["whole files", "selected range (open file only)"])
        g.addWidget(self.pR, 0, 2)
        g.addWidget(QtWidgets.QLabel("Sampling"), 1, 0)
        self.pM = QtWidgets.QComboBox()
        self.pM.addItems(["all contractions", "short windows (W s every T min)", "rocker stops only (log file)"])
        self.pM.setCurrentIndex(1)
        self.pM.setToolTip("short windows: only W s every T min are read and analysed (much faster for 24-h files, the "
                           "reading dominates); rocker stops: only the rocker stops of the log files (contractions with "
                           "the rocker at rest)")
        self.pM.currentIndexChanged.connect(self._sampling_controls)
        g.addWidget(self.pM, 1, 1, 1, 2)
        g.addWidget(QtWidgets.QLabel("window W (s)"), 2, 0)
        self.eWs = QtWidgets.QLineEdit("30")
        g.addWidget(self.eWs, 2, 1)
        hT = QtWidgets.QHBoxLayout()
        hT.addWidget(QtWidgets.QLabel("every T (min)"))
        self.eTm = QtWidgets.QLineEdit("10")
        self.eTm.setToolTip("interval between the windows (min). Every window costs a separate read: from a network "
                            "drive via VPN (~0.25 s per window) windows pay off from ~10 min on")
        hT.addWidget(self.eTm)
        g.addLayout(hT, 2, 2)
        g.addWidget(QtWidgets.QLabel("Parameter"), 3, 0)
        self.pP = QtWidgets.QComboBox()
        for k in range(win.cPar.count()):
            self.pP.addItem(win.cPar.itemText(k))
        self.pP.setCurrentIndex(win.cPar.currentIndex())
        self.pP.currentIndexChanged.connect(lambda *_: self.draw())
        g.addWidget(self.pP, 3, 1, 1, 2)
        g.addWidget(QtWidgets.QLabel("Rolling window (min)"), 4, 0)
        self.eW = QtWidgets.QLineEdit("60")
        self.eW.editingFinished.connect(self.draw)
        g.addWidget(self.eW, 4, 1)
        self.pS = QtWidgets.QComboBox()
        self.pS.addItems(["mean", "median"])
        self.pS.currentIndexChanged.connect(lambda *_: self.draw())
        g.addWidget(self.pS, 4, 2)
        v.addLayout(g)
        self.cS = QtWidgets.QCheckBox("single contractions")
        self.cS.setChecked(True)
        self.cI = QtWidgets.QCheckBox("only included contractions (filters of the main window)")
        self.cI.setChecked(True)
        self.cK = QtWidgets.QCheckBox("comments of the log files")
        self.cK.setChecked(True)
        self.cT = QtWidgets.QCheckBox("clock time (date) instead of time since start")
        self.cA = QtWidgets.QCheckBox("all channels in one pass (switch channel without recalculation)")
        self.cA.setToolTip("the file is read once for all channels (reading dominates the time); about 1.5 x the time of "
                           "one channel, afterwards every channel is shown at once")
        for c in (self.cS, self.cI, self.cK):
            c.toggled.connect(lambda *_: self.draw())
            v.addWidget(c)
        self.cT.toggled.connect(lambda *_: self.draw())
        v.addWidget(self.cT)
        v.addWidget(self.cA)
        b = QtWidgets.QPushButton("Calculate")
        f = b.font()
        f.setBold(True)
        b.setFont(f)
        b.setToolTip("detects the contractions in the files (threshold, filters, zero force and rocker filter as in the "
                     "main window); results are kept, so changing parameter / window only redraws")
        b.clicked.connect(lambda: self.calc(False))
        v.addWidget(b)
        hh = QtWidgets.QHBoxLayout()
        b = QtWidgets.QPushButton("Save figure ...")
        b.clicked.connect(self.save_figure)
        hh.addWidget(b)
        b = QtWidgets.QPushButton("Export data ...")
        b.clicked.connect(self.export)
        hh.addWidget(b)
        v.addLayout(hh)
        self.tx = QtWidgets.QLabel("")
        self.tx.setWordWrap(True)
        fo = self.tx.font()
        fo.setPointSize(fo.pointSize() - 2)
        self.tx.setFont(fo)
        v.addWidget(self.tx)
        self._sampling_controls()
        self.files = self.file_info([win.H.file])
        self.list_files()
        self.draw()

    # ---------------------------------------------------------------- files
    def _sampling_controls(self, *_):
        en = self.pM.currentIndex() == 1
        self.eWs.setEnabled(en)
        self.eTm.setEnabled(en)

    def file_info(self, files):
        F = []
        for f in files:
            try:
                Hk = read_mdd(f, None, None, self.win.opts)
            except Exception as e:  # noqa: BLE001
                self.win.status(f"Trend: {e}")
                continue
            cmt = pd.DataFrame({"t_file": pd.Series([], dtype=float), "text": pd.Series([], dtype=object)})
            try:
                E = log_entries(Hk.logFile)
                cmt = pd.DataFrame({"t_file": E["t_file"][E["isComment"]].to_numpy(),
                                    "text": E["text"][E["isComment"]].to_numpy()})
            except Exception:  # noqa: BLE001
                pass
            F.append(Struct(file=Hk.file, name=os.path.basename(Hk.file), start=Hk.recordingStart, dur=Hk.totalSeconds,
                            offset=0.0, gap=0.0, startKnown=not math.isnan(Hk.recordingStart),
                            channels=[int(c) for c in Hk.dataChannels], comments=cmt, rockerLog=Hk.rockerSpeedLog))
        if not F:
            return F
        st = np.array([f.start if f.startKnown else np.inf for f in F])
        o = np.lexsort((np.arange(len(F)), st))
        F = [F[i] for i in o]
        for k, Fk in enumerate(F):
            if k == 0:
                Fk.offset = 0.0
                Fk.gap = 0.0
            elif Fk.startKnown and F[0].startKnown:
                Fk.offset = (Fk.start - F[0].start) * 86400
                Fk.gap = Fk.offset - (F[k - 1].offset + F[k - 1].dur)
            else:
                Fk.offset = F[k - 1].offset + F[k - 1].dur  # start unknown: directly after the previous file
                Fk.gap = math.nan
        return F

    def list_files(self):
        self.lbF.clear()
        for k, Fk in enumerate(self.files):
            st = datenum_to_timestamps(Fk.start).strftime("%d.%m.%y %H:%M") if Fk.startKnown else "start unknown"
            if k == 0:
                g = "time 0"
            elif math.isnan(Fk.gap):
                g = "appended (no start time)"
            elif Fk.gap < -1:
                g = f"OVERLAP {fmt_clock(-Fk.gap, True, True)}"
            elif Fk.gap > 60:
                g = f"gap {fmt_clock(Fk.gap, True, True)}"
            else:
                g = "no gap"
            self.lbF.addItem(f"{Fk.name} | {st} | {fmt_clock(Fk.dur, True, True)} | {g}")
        if not self.files:
            self.lbF.addItem("(no file)")

    def set_files(self, f):
        seen = []
        for x in f:
            if x not in seen:
                seen.append(x)
        self.win.status("Trend: reading the log files ...")
        self.files = self.file_info(seen)
        self.data = None
        self.list_files()
        self.draw()

    def add_files(self):
        p = os.path.dirname(self.win.H.file)
        fn, _ = QtWidgets.QFileDialog.getOpenFileNames(self, "Add .mdd files", p, "MyoDish (*.mdd)")
        if fn:
            self.set_files([F.file for F in self.files] + list(fn))

    def add_series(self):
        p, n = os.path.split(os.path.splitext(self.win.H.file)[0])
        m = re.match(r"^(.*)_(\d+)$", n)
        if not m:
            self.win.status("The file name does not end with _<number> (e.g. Setup3_sample01_1.mdd).")
            return
        stem = m.group(1)
        nm = sorted(os.path.basename(x) for x in glob.glob(os.path.join(p, glob.escape(stem) + "_*.mdd")))
        nm = [x for x in nm if re.match("^" + re.escape(stem) + r"_\d+\.mdd$", x)]
        self.set_files([F.file for F in self.files] + [os.path.join(p, x) for x in nm])
        self.win.status(f"Trend: {len(nm)} files of the series {stem}_*.")

    def remove(self):
        k = self.lbF.currentRow()
        if 0 <= k < len(self.files):
            self.set_files([F.file for i, F in enumerate(self.files) if i != k])

    # ---------------------------------------------------------------- calculation
    def windows(self, Fk, a, b, mode, Ws, Tm):
        if mode == 1:
            s0 = colon(a, Tm * 60, b)
            W = np.c_[s0, np.minimum(s0 + Ws, b)]
        elif mode == 2:
            L = np.asarray(Fk.rockerLog, float).reshape(-1, 2).copy()
            W = np.zeros((0, 2))
            if L.shape[0]:
                L[np.isinf(L[:, 0]), 0] = 0
                rows = []
                for q in np.flatnonzero(L[:, 1] == 0):
                    nx = np.flatnonzero((L[:, 0] > L[q, 0]) & (L[:, 1] > 0))
                    e = Fk.dur if nx.size == 0 else L[nx[0], 0]
                    rows.append([L[q, 0], e])
                W = np.array(rows, float).reshape(-1, 2)
            W = np.c_[np.maximum(W[:, 0], a), np.minimum(W[:, 1], b)]
            W = W[W[:, 1] - W[:, 0] >= 3]
        else:
            W = np.array([[a, b]], float)
        if mode != 2:
            W = W[W[:, 1] - W[:, 0] >= 1]
        return W

    def _opts(self, Fk, chans, mode):
        w = self.win
        o = dict(w.opts)
        if Fk.file == w.H.file:
            o["zeroForce"] = [w.zero_of(c) for c in chans]
        else:
            o["zeroForce"] = math.nan
        o["threshold"] = w.thr_of([int(c) for c in chans])  # threshold per channel: also for the other files
        if mode == 2:
            o["rocker"] = "stopped"
        return o

    def _key(self, Fk, ch, a, b, mode):
        o = self._opts(Fk, [ch], mode)
        rf = o.get("referenceBeat")
        if rf:
            o["referenceBeat"] = [(r.get("channel"), r.get("source"), r.get("align"), r.get("created")) for r in rf]
        return f"{Fk.file}|{ch}|{a:.3f}|{b:.3f}|{json.dumps(o, default=str, sort_keys=True)}|{self.sampling}"

    def calc(self, only_cached=False):
        w = self.win
        if not self.files:
            return
        chT = int(w.H.dataChannels[self.pC.currentIndex()])
        jobs = []
        for k, Fk in enumerate(self.files):
            if self.pR.currentIndex() == 1:
                if Fk.file == w.H.file and not any(math.isnan(x) for x in w.range):
                    jobs.append((k, w.range[0], w.range[1]))
            else:
                jobs.append((k, 0.0, Fk.dur))
        if not jobs:
            w.status("Trend: no data (selected range: load a window of the open file first).")
            return
        mode = self.pM.currentIndex()
        try:
            Ws = float(self.eWs.text())
        except ValueError:
            Ws = math.nan
        try:
            Tm = float(self.eTm.text())
        except ValueError:
            Tm = math.nan
        if mode == 1:
            if math.isnan(Ws) or Ws < 5:
                Ws = 30.0
                self.eWs.setText("30")
            if math.isnan(Tm) or Tm <= 0:
                Tm = 10.0
                self.eTm.setText("10")
            if Ws >= Tm * 60:
                mode = 0  # windows cover everything
        self.sampling = {1: f"{Ws:g} s every {Tm:g} min", 2: "rocker stops only"}.get(mode, "all contractions")
        cache = w.tr_cache
        if only_cached:
            for k, a, b in jobs:
                Fk = self.files[k]
                if chT in Fk.channels and self._key(Fk, chT, a, b, mode) not in cache:
                    self.data = None
                    self.draw()
                    w.status(f"Trend: channel {chT} not calculated yet - press Calculate.")
                    return
        total = sum(b - a for _, a, b in jobs)
        dlg = QtWidgets.QProgressDialog("Detecting contractions ...", "Cancel", 0, 1000, self)
        dlg.setWindowTitle("Trend")
        dlg.setMinimumDuration(200)
        done = 0.0
        parts = []
        block = 7200.0  # s per call (myodish_analysis chunks internally)
        try:
            for k, a0, b0 in jobs:
                Fk = self.files[k]
                if chT not in Fk.channels:
                    w.status(f"Trend: channel {chT} not in {Fk.name}.")
                    done += b0 - a0
                    continue
                key = self._key(Fk, chT, a0, b0, mode)
                chans = [chT]
                if self.cA.isChecked() and not only_cached:
                    chans = list(Fk.channels)
                missing = any(self._key(Fk, c2, a0, b0, mode) not in cache for c2 in chans)
                if not missing:
                    Tk = cache[key]
                    done += b0 - a0
                else:
                    o = self._opts(Fk, chans, mode)
                    Wj = self.windows(Fk, a0, b0, mode, Ws, Tm)
                    if Wj.shape[0] == 0:
                        w.status(f"Trend: no {self.sampling} in {Fk.name}.")
                    Tks = []
                    for a in colon(a0, block, b0):
                        b = min(a + block, b0)
                        if dlg.wasCanceled():
                            raise KeyboardInterrupt
                        dlg.setLabelText(f"{Fk.name}: {fmt_clock(a, True, True)} - {fmt_clock(b, True, True)}")
                        dlg.setValue(int(1000 * done / max(total, 1e-9)))
                        QtWidgets.QApplication.processEvents()
                        if mode == 0:
                            Wb = np.array([[a, b]]) if b - a >= 1 else np.zeros((0, 2))
                        else:
                            sel = (Wj[:, 0] >= a) & ((Wj[:, 0] < b) | ((b == b0) & (Wj[:, 0] <= b)))
                            Wb = Wj[sel]
                        if Wb.shape[0]:
                            c, _, _ = myodish_analysis(Fk.file, chans, Wb[:, 0], Wb[:, 1], quiet=True, **o)
                            if len(c):
                                Tks.append(c)
                        done += b - a
                    Tk = pd.concat(Tks, ignore_index=True) if Tks else None
                    for c2 in chans:
                        T2 = None if Tk is None else Tk[Tk["channel"] == c2]
                        if T2 is not None and len(T2):
                            _, iu = np.unique(mround(T2["t_peak"].to_numpy() * 1e4), return_index=True)
                            T2 = T2.iloc[np.sort(iu)].reset_index(drop=True)  # peaks exactly at a block border
                        cache[self._key(Fk, c2, a0, b0, mode)] = T2
                    Tk = cache[key]
                if Tk is not None and len(Tk):
                    keep = [c for c in ("t_peak", "beatType", "included", "rockerMoving") if c in Tk.columns]
                    pn = [nm for nm, _ in w.plot_list if nm in Tk.columns]
                    Tk = Tk[keep + pn].copy()
                    Tk["t_since_start"] = Tk["t_peak"].to_numpy() + Fk.offset
                    Tk["fileIndex"] = k
                    parts.append(Tk)
        except KeyboardInterrupt:
            dlg.close()
            w.status("Trend: cancelled.")
            return
        except Exception as e:  # noqa: BLE001
            dlg.close()
            w.status(f"Trend: {e}")
            return
        dlg.close()
        self.data = pd.concat(parts, ignore_index=True).sort_values("t_since_start", kind="stable") \
            .reset_index(drop=True) if parts else None
        self.draw()
        n = 0 if self.data is None else len(self.data)
        nf = 0 if self.data is None else self.data["fileIndex"].nunique()
        w.status(f"Trend: {n} contractions in {nf} file(s).")

    # ---------------------------------------------------------------- drawing
    def draw(self, *_):
        p = self.p
        p.clear()
        if p.legend is not None:
            p.legend.clear()
        self._cmt = []
        if not self.files:
            p.setTitle("no file", size="9pt")
            return
        w = self.win
        nm, unit = w.plot_list[self.pP.currentIndex()]
        unit = unit.replace("u", MU) if unit.startswith("u") else unit
        yl0 = [0.0, 1.0]
        D = self.data
        have = D is not None and len(D) > 0 and nm in D.columns
        I = None
        if have:
            v = D[nm].to_numpy(float)
            t = D["t_since_start"].to_numpy(float)
            I = ~np.isnan(v)
            if self.cI.isChecked():
                I &= D["included"].to_numpy(bool)
            if I.any():
                q = np.sort(v[I])
                lo = q[max(1, mround(0.002 * q.size)) - 1]
                hi = q[max(1, mround(0.998 * q.size)) - 1]
                if hi <= lo:
                    hi = lo + 1
                yl0 = [lo - 0.08 * (hi - lo), hi + 0.12 * (hi - lo)]
        for f, Fk in enumerate(self.files):
            shade = 0.03 * (f % 2)
            col = tuple(int(255 * (c - shade)) for c in (0.93, 0.95, 1.0))
            rects(p, [Fk.offset], [Fk.offset + Fk.dur], yl0[0], yl0[1], col, z=-20)
            suf = re.search(r"_\d+$", os.path.splitext(Fk.name)[0])
            suf = suf.group(0) if suf else os.path.splitext(Fk.name)[0][-25:]
            tt = pg.TextItem(" " + suf, color=(77, 77, 153), anchor=(0, 0))
            p.addItem(tt)
            tt.setPos(Fk.offset, yl0[1])
            if f > 0 and not math.isnan(Fk.gap) and Fk.gap > 60:
                g0 = self.files[f - 1].offset + self.files[f - 1].dur
                rects(p, [g0], [Fk.offset], yl0[0], yl0[1], (209, 209, 209), z=-19)
                tg = pg.TextItem(f"no data\n{fmt_clock(Fk.gap, True, False)}", color=(89, 89, 89), anchor=(0.5, 0.5))
                p.addItem(tg)
                tg.setPos((g0 + Fk.offset) / 2, sum(yl0) / 2)
        if have and I.any():
            if self.cS.isChecked():
                p.addItem(pg.ScatterPlotItem(t[I], v[I], symbol="o", size=3, pen=None, brush=(242, 153, 153)))
            try:
                wMin = float(self.eW.text())
                if wMin <= 0:
                    raise ValueError
            except ValueError:
                wMin = 10.0
                self.eW.setText("10")
            T2, R2 = [], []
            fi = D["fileIndex"].to_numpy()
            for f in np.unique(fi[I]):
                J = I & (fi == f)
                tt_, rr = rolling(t[J], v[J], wMin * 60, self.pS.currentIndex() == 1)
                T2 += list(tt_) + [np.nan]
                R2 += list(rr) + [np.nan]
            p.plot(np.array(T2), np.array(R2), pen=pg.mkPen((191, 0, 0), width=2), connect="finite",
                   name=f"rolling {self.pS.currentText()} ({wMin:g} min)")
            self.roll = np.c_[T2, R2]
        else:
            self.roll = np.zeros((0, 2))
        if self.cK.isChecked():
            for Fk in self.files:
                cm = Fk.comments
                if cm is None or len(cm) == 0:
                    continue
                tf = cm["t_file"].to_numpy(float)
                ok = (tf >= 0) & (tf <= Fk.dur)
                tc = tf[ok] + Fk.offset
                if tc.size == 0:
                    continue
                vlines(p, tc, yl0[0], yl0[1], PURPLE, style=QtCore.Qt.PenStyle.DotLine)
                lab = [s[:35] + "  " for s in cm["text"].to_numpy()[ok]]
                self._cmt += [(x, lb) for x, lb in zip(tc, lab)]
        last = self.files[-1]
        self._yl0 = yl0
        self._cmt_items = []
        p.vb.setRange(xRange=(0, max(1, last.offset + last.dur)), yRange=yl0, padding=0)
        p.setLabel("left", f"{nm} ({unit})")
        if have:
            p.setTitle(f"Channel {int(w.H.dataChannels[self.pC.currentIndex()])}, {len(D)} contractions "
                       f"({int(I.sum())} shown), {len(self.files)} file(s), sampling: {self.sampling}", size="9pt")
        else:
            p.setTitle("press Calculate (detects the contractions in the listed files)", size="9pt")
        p.showGrid(x=True, y=True, alpha=0.25)
        self._ticks()
        info = [f"{len(self.files)} file(s), total {fmt_clock(last.offset + last.dur, True, True)}"]
        g = [F.gap for F in self.files[1:] if not math.isnan(F.gap) and F.gap > 60]
        if g:
            info.append(f"{len(g)} gap(s) between the files: " + ", ".join(fmt_clock(x, True, False) for x in g))
        if any(not F.startKnown for F in self.files):
            info.append("start time unknown for some files: appended directly")
        if have and self.pM.currentIndex() == 1:
            try:
                Tm = float(self.eTm.text())
                if float(self.eW.text()) < 2 * Tm:
                    info.append(f"short windows every {Tm:g} min: use a rolling window >= {2 * Tm:g} min")
            except ValueError:
                pass
        info.append("zero force: open file = value of the main window, other files = Offset of their log")
        info.append("manual exclusions of the main window are not applied")
        self.tx.setText("\n".join(info))

    def _ticks(self):
        ax = self.p.getAxis("bottom")
        xl = self.p.vb.viewRange()[0]
        ax.tmax = max(3600, xl[1])
        if self.cT.isChecked() and self.files and self.files[0].startKnown:
            ax.clock = datenum_to_timestamps(self.files[0].start).to_pydatetime()
            self.p.setLabel("bottom", "clock time (dd.mm. HH:MM)")
        else:
            ax.clock = None
            self.p.setLabel("bottom", f"time since the start of the first file ({ax.unit})")
        ax.picture = None
        ax.update()
        # comment labels: only labels that do not overlap (about one text line apart)
        for it in self._cmt_items:
            if it.scene() is not None:
                self.p.removeItem(it)
        self._cmt_items = []
        if not getattr(self, "_cmt", None):
            return
        wpx = max(1.0, self.p.vb.width())
        min_dx = 11 * (xl[1] - xl[0]) / wpx
        last = -math.inf
        xs, labs = [], []
        for x, lb in sorted(self._cmt):
            if xl[0] <= x <= xl[1] and x - last >= min_dx:
                xs.append(x)
                labs.append(lb)
                last = x
        self._cmt_items = rot_labels(self.p, xs, self._yl0[1], labs, PURPLE, max_n=200)

    def _wheel(self, x0, n, mods):
        if not self.files:
            return
        last = self.files[-1]
        lim = (0, max(1, last.offset + last.dur))
        xl = self.p.vb.viewRange()[0]
        if mods & QtCore.Qt.KeyboardModifier.ShiftModifier:
            xl = [xl[0] + n * 0.15 * (xl[1] - xl[0]), xl[1] + n * 0.15 * (xl[1] - xl[0])]
        else:
            f = 1.25 ** n
            xl = [x0 + (xl[0] - x0) * f, x0 + (xl[1] - x0) * f]
        span = min(max(xl[1] - xl[0], 10), lim[1] - lim[0])
        a = min(max(xl[0], lim[0]), lim[1] - span)
        self.p.vb.setXRange(a, a + span, padding=0)

    def _click(self, x, y, button, double, sp):
        if double and self.files:
            last = self.files[-1]
            self.p.vb.setXRange(0, max(1, last.offset + last.dur), padding=0)

    # ---------------------------------------------------------------- output
    def save_figure(self):
        from .dialogs import ask_file, save_items
        file = ask_file(self.win, "image", "trend")
        if not file:
            return
        try:
            save_items([self.p], file, 3600)
            self.win.status("Saved: " + file)
        except Exception as e:  # noqa: BLE001
            self.win.status(f"Save: {e}")

    def export(self):
        from .dialogs import ask_file, write_tables
        if self.data is None or len(self.data) == 0:
            self.win.status("Trend: press Calculate first.")
            return
        file = ask_file(self.win, "data", "trend")
        if not file:
            return
        D = self.data.copy()
        fi = D["fileIndex"].to_numpy()
        D.insert(0, "file", [self.files[i].name for i in fi])
        st = np.array([self.files[i].start for i in fi], float)
        D.insert(1, "t_since_start_s", D.pop("t_since_start"))
        D.insert(2, "clockTime", datenum_to_timestamps(st + D["t_peak"].to_numpy() / 86400))
        D = D.rename(columns={"t_peak": "t_file_s"}).drop(columns=["fileIndex"])
        nm = self.win.plot_list[self.pP.currentIndex()][0]
        R = pd.DataFrame(self.roll[~np.isnan(self.roll[:, 0])] if self.roll.size else np.zeros((0, 2)),
                         columns=["t_since_start_s", f"rolling_{nm}"])
        Fi = pd.DataFrame({"file": [F.name for F in self.files],
                           "recordingStart": [datenum_to_timestamps(F.start).strftime("%Y-%m-%d %H:%M:%S")
                                              if F.startKnown else "unknown" for F in self.files],
                           "duration_s": [F.dur for F in self.files], "offset_s": [F.offset for F in self.files],
                           "gapBefore_s": [F.gap for F in self.files], "sampling": [self.sampling] * len(self.files)})
        write_tables(self.win, file, ["contractions", "rolling", "files"], [D, R, Fi])
