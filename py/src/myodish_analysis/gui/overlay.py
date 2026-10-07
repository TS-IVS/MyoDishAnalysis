"""Overlay of contractions: one group per added selection (channel, range, filters, exclusions), aligned at the
stimulus (t = 0) or at the peak; mean of every group, single traces, export. Port of the overlay part of
MyoDishAnalysisGUI.m.

TS 2026-10-06
"""
from __future__ import annotations

import math

import numpy as np
import pandas as pd
import pyqtgraph as pg
from PySide6 import QtCore, QtWidgets

from .._matlab import mround, nanmean, nanmedian, nanstd
from .timeaxis import fmt_clock
from .widgets import BLUE

MU = "µ"
COLORS = [(0, 114, 189), (217, 83, 25), (237, 177, 32), (126, 47, 142), (119, 172, 48), (77, 190, 238), (162, 20, 47)]


class OverlayWindow(QtWidgets.QWidget):
    def __init__(self, win):
        super().__init__()
        self.win = win
        self.groups = []
        self.setWindowFlag(QtCore.Qt.WindowType.Window)
        self.setWindowTitle("MyoDishAnalysis: overlay")
        self.resize(1100, 620)
        h = QtWidgets.QHBoxLayout(self)
        self.pw = pg.PlotWidget()
        self.p = self.pw.getPlotItem()
        self.p.showGrid(x=True, y=True, alpha=0.25)
        self.p.getAxis("left").setWidth(72)
        self.p.addLegend(offset=(-10, 10), labelTextSize="8pt")
        h.addWidget(self.pw, 3)
        v = QtWidgets.QVBoxLayout()
        h.addLayout(v, 1)
        v.addWidget(QtWidgets.QLabel("Groups (one per added selection):"))
        self.lb = QtWidgets.QListWidget()
        v.addWidget(self.lb, 1)
        b = QtWidgets.QPushButton("Add current selection")
        b.setToolTip("contractions selected in the main window (channel, range, filters, exclusions)")
        b.clicked.connect(self._add_draw)
        v.addWidget(b)
        hh = QtWidgets.QHBoxLayout()
        b = QtWidgets.QPushButton("Remove group")
        b.clicked.connect(self.remove_group)
        hh.addWidget(b)
        b = QtWidgets.QPushButton("Clear all")
        b.clicked.connect(self.clear_groups)
        hh.addWidget(b)
        v.addLayout(hh)
        self.al = QtWidgets.QComboBox()
        self.al.addItems(["align at the stimulus (t = 0)", "align at the peak (t = 0)"])
        self.al.currentIndexChanged.connect(lambda *_: self.draw())
        v.addWidget(self.al)
        self.cSingle = QtWidgets.QCheckBox("single contractions")
        self.cSingle.setChecked(True)
        self.cBase = QtWidgets.QCheckBox("subtract diastolic force (developed force)")
        self.cBase.setChecked(True)
        self.cNorm = QtWidgets.QCheckBox("normalize (amplitude = 1)")
        for c in (self.cSingle, self.cBase, self.cNorm):
            c.toggled.connect(lambda *_: self.draw())
            v.addWidget(c)
        hh = QtWidgets.QHBoxLayout()
        b = QtWidgets.QPushButton("Save figure ...")
        b.clicked.connect(self.save_figure)
        hh.addWidget(b)
        b = QtWidgets.QPushButton("Export data ...")
        b.setToolTip("mean, SD, n and all single traces of every group: .xlsx / .csv / .txt")
        b.clicked.connect(self.export)
        hh.addWidget(b)
        v.addLayout(hh)
        self.tx = QtWidgets.QLabel("")
        self.tx.setWordWrap(True)
        v.addWidget(self.tx)

    def _add_draw(self):
        if self.add_group():
            self.draw()

    def add_group(self):
        """current selection of the main window --> new overlay group (segments of the filtered signal)."""
        w = self.win
        if w.B is None or w.C is None:
            w.status("Load a time window first.")
            return False
        sel = np.flatnonzero(w.selected())
        if sel.size == 0:
            w.status("No contraction selected.")
            return False
        B, C, S = w.B, w.C, w.S
        tp = B["t_peak"].to_numpy()
        key = f"{w.ch}|{w.range[0]:.4f}|{w.range[1]:.4f}|{sel.size}|{np.sum(tp[sel]):.6f}"
        if any(g["key"] == key for g in self.groups):
            w.status("This selection is already in the overlay.")
            return True
        pre = mround(1.0 / S.dt)
        post = mround(1.6 / S.dt)
        pk = {v: i for i, v in enumerate(C.peakTimes)}
        loc = np.array([pk[x] for x in tp[sel]])
        idx = np.asarray(C.iPeaks)[loc]
        N = C.f.size
        seg = np.full((sel.size, pre + post + 1), np.nan)
        for k, i in enumerate(idx):
            a, b = i - pre, i + post
            ia, ib = max(0, a), min(N - 1, b)
            seg[k, ia - a:ib - a + 1] = C.f[ia:ib + 1]
        lab = (f"Ch {w.ch}, {fmt_clock(w.range[0], w.H.totalSeconds >= 3600, True)} - "
               f"{fmt_clock(w.range[1], w.H.totalSeconds >= 3600, True)}, n = {sel.size}")
        L = w.Lbl
        r = np.flatnonzero(L["channel"].to_numpy(float) == w.ch)
        if r.size:
            for nm in ("treatment", "sliceID"):
                if nm in L.columns and isinstance(L[nm].iloc[r[0]], str) and L[nm].iloc[r[0]]:
                    lab += ", " + L[nm].iloc[r[0]]
        G = dict(key=key, seg=seg, dt=S.dt, pre=pre,
                 stimRel=B["t_stim"].to_numpy(float)[sel] - np.asarray(C.peakTimes)[loc],
                 dia=B["diastolicSignal"].to_numpy(float)[sel], amp=B["amplitude"].to_numpy(float)[sel],
                 zero=C.zeroForce, pp=nanmedian(B["peakToPeakInterval"].to_numpy(float)[sel]), label=lab)
        self.groups.append(G)
        w.status(f"Overlay: group {len(self.groups)} added ({lab}).")
        return True

    def remove_group(self):
        k = self.lb.currentRow()
        if 0 <= k < len(self.groups):
            del self.groups[k]
        self.draw()

    def clear_groups(self):
        self.groups = []
        self.draw()

    def curves(self, G):
        """traces of one group on a common time grid (alignment, baseline, normalization as chosen)."""
        align_stim = self.al.currentIndex() == 0
        x0 = (np.arange(G["seg"].shape[1]) - G["pre"]) * G["dt"]
        Y = G["seg"].copy()
        if self.cBase.isChecked():
            Y = Y - G["dia"][:, None]
        elif not math.isnan(G["zero"]):
            Y = Y - G["zero"]
        if self.cNorm.isChecked():
            Y = Y / G["amp"][:, None]
        sh = -G["stimRel"] if align_stim else np.zeros(G["stimRel"].size)
        v = np.flatnonzero(~np.isnan(sh))
        lo = min(np.min(sh[v]) if v.size else 0.0, 0.0)
        hi = max(np.max(sh[v]) if v.size else 0.0, 0.0)
        xg = np.arange(mround((x0[0] + lo) / G["dt"]), mround((x0[-1] + hi) / G["dt"]) + 1) * G["dt"]
        Yall = np.full((v.size, xg.size), np.nan)
        for k, q in enumerate(v):
            xs = x0 + sh[q]
            Yall[k] = np.interp(xg, xs, Y[q], left=np.nan, right=np.nan)
        nn = np.sum(~np.isnan(Yall), axis=0)
        M = nanmean(Yall, axis=0) if v.size else np.full(xg.size, np.nan)
        SD = nanstd(Yall, axis=0) if v.size else np.full(xg.size, np.nan)
        bad = nn < 0.5 * v.size
        M = np.where(bad, np.nan, M)
        SD = np.where(bad, np.nan, SD)
        return xg, M, SD, nn, Yall

    def draw(self):
        p = self.p
        p.clear()
        if p.legend is not None:
            p.legend.clear()
        self.lb.clear()
        if not self.groups:
            p.setTitle('no group: select contractions in the main window and press "Add current selection"', size="9pt")
            self.tx.setText("")
            return
        info = []
        lo, hi = math.inf, -math.inf
        align_stim = self.al.currentIndex() == 0
        L = nanmedian(np.array([g["pp"] for g in self.groups]))
        if math.isnan(L):
            L = 1.0
        xl = (-0.1, min(1.5, max(0.3, 0.95 * L))) if align_stim else (-min(0.4, 0.45 * L), min(1.5, 0.9 * L))
        for g, G in enumerate(self.groups):
            xg, M, _, _, Yall = self.curves(G)
            col = COLORS[g % len(COLORS)]
            light = tuple(int(0.35 * c + 0.65 * 255) for c in col)
            inx = (xg >= xl[0]) & (xg <= xl[1])
            if self.cSingle.isChecked() and Yall.size:
                X = np.tile(np.r_[xg, np.nan], Yall.shape[0])
                Yv = np.c_[Yall, np.full(Yall.shape[0], np.nan)].ravel()
                p.plot(X, Yv, pen=pg.mkPen(light, width=1), connect="finite")
                lo = min(lo, np.nanmin(Yall[:, inx])) if np.any(~np.isnan(Yall[:, inx])) else lo
                hi = max(hi, np.nanmax(Yall[:, inx])) if np.any(~np.isnan(Yall[:, inx])) else hi
            if Yall.size:
                p.plot(xg, M, pen=pg.mkPen(col, width=2), name=f"{g + 1}: {G['label']}")
                if np.any(~np.isnan(M[inx])):
                    lo = min(lo, np.nanmin(M[inx]))
                    hi = max(hi, np.nanmax(M[inx]))
            nNo = G["seg"].shape[0] - Yall.shape[0]
            if nNo > 0:
                info.append(f"group {g + 1}: {nNo} contraction(s) without stimulus not shown")
            self.lb.addItem(f"{g + 1}: {G['label']}")
        if align_stim:
            p.addItem(pg.InfiniteLine(0, angle=90, pen=pg.mkPen(BLUE, style=QtCore.Qt.PenStyle.DashLine)))
            p.setLabel("bottom", "time from the stimulus (s)")
        else:
            p.setLabel("bottom", "time from the peak (s)")
        if self.cNorm.isChecked():
            p.setLabel("left", "force / amplitude")
        elif self.cBase.isChecked():
            p.setLabel("left", f"force - diastolic force ({MU}N)")
        else:
            p.setLabel("left", f"force - zero force ({MU}N)")
        if math.isfinite(lo) and math.isfinite(hi) and hi > lo:
            p.vb.setRange(xRange=xl, yRange=(lo - 0.05 * (hi - lo), hi + 0.08 * (hi - lo)), padding=0)
        else:
            p.vb.setXRange(*xl, padding=0)
        p.setTitle("thick: mean of each group; thin: single contractions", size="9pt")
        self.tx.setText("\n".join(info) if info else "all contractions shown")

    def save_figure(self):
        from .dialogs import ask_file, save_items
        if not self.groups:
            return
        file = ask_file(self.win, "image", "overlay")
        if not file:
            return
        try:
            save_items([self.p], file, 2700)
            self.win.status("Saved: " + file)
        except Exception as e:  # noqa: BLE001
            self.win.status(f"Save: {e}")

    def export(self):
        from .dialogs import ask_file, write_tables
        if not self.groups:
            return
        file = ask_file(self.win, "data", "overlay")
        if not file:
            return
        dt = min(g["dt"] for g in self.groups)
        cur = [self.curves(G) for G in self.groups]
        xmin = min((c[0][0] for c in cur if c[0].size), default=0.0)
        xmax = max((c[0][-1] for c in cur if c[0].size), default=0.0)
        tt = np.arange(mround(xmin / dt), mround(xmax / dt) + 1) * dt
        tn = "t_from_stimulus_s" if self.al.currentIndex() == 0 else "t_from_peak_s"
        Tm = pd.DataFrame({tn: tt})
        names, tabs = ["means"], [None]
        grp, nG = [], []
        for g, (G, c) in enumerate(zip(self.groups, cur)):
            xg, M, SD, nn, Yall = c
            if xg.size == 0:
                m = sd = nk = np.full(tt.size, np.nan)
            else:
                m = np.interp(tt, xg, M, left=np.nan, right=np.nan)
                sd = np.interp(tt, xg, SD, left=np.nan, right=np.nan)
                ii = np.clip(np.searchsorted(xg, tt), 1, max(1, xg.size - 1))
                prev = np.clip(ii - 1, 0, xg.size - 1)
                ii = np.clip(ii, 0, xg.size - 1)
                ii = np.where(np.abs(xg[prev] - tt) <= np.abs(xg[ii] - tt), prev, ii)  # interp1 'nearest'
                nk = np.where((tt >= xg[0]) & (tt <= xg[-1]), nn[ii], np.nan)
                Tg = pd.DataFrame(np.c_[xg, Yall.T], columns=[tn] + [f"c{k + 1}" for k in range(Yall.shape[0])])
                names.append(f"g{g + 1}_traces")
                tabs.append(Tg)
            Tm[f"g{g + 1}_mean"] = m
            Tm[f"g{g + 1}_SD"] = sd
            Tm[f"g{g + 1}_n"] = nk
            grp.append(G["label"])
            nG.append(Yall.shape[0])
        tabs[0] = Tm
        a = "aligned at the stimulus (t = 0)" if self.al.currentIndex() == 0 else "aligned at the peak (t = 0)"
        b = "diastolic force subtracted" if self.cBase.isChecked() else "zero force subtracted (if known)"
        u = "normalized to the amplitude" if self.cNorm.isChecked() else "uN"
        n = len(self.groups)
        names.append("groups")
        tabs.append(pd.DataFrame({"group": np.arange(1, n + 1), "label": grp, "nTraces": nG, "alignment": [a] * n,
                                  "baseline": [b] * n, "unit": [u] * n}))
        write_tables(self.win, file, names, tabs)
