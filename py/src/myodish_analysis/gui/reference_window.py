# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Reference beat window: mean +- 1 SD and +- x SD of the reference (absolute and normalized), the deviating contractions
of the loaded range, threshold / measure / alignment, save / load (.mat, compatible with MATLAB). Port of the
reference part of MyoDishAnalysisGUI.m.

TS 2026-10-06
"""
from __future__ import annotations

import os

import numpy as np
import pyqtgraph as pg
from PySide6 import QtCore, QtWidgets

from .. import reference_beat as rb

MU = "µ"


def _align_text(a):
    return "stimulus" if a == "stimulus" else "50 % upstroke"


class ReferenceWindow(QtWidgets.QWidget):
    def __init__(self, win):
        super().__init__()
        self.win = win
        self.setWindowFlag(QtCore.Qt.WindowType.Window)
        self.setWindowTitle("MyoDishAnalysis: reference beat")
        self.resize(1150, 560)
        h = QtWidgets.QHBoxLayout(self)
        self.gl = pg.GraphicsLayoutWidget()
        self.a1 = self.gl.addPlot(row=0, col=0)
        self.a2 = self.gl.addPlot(row=0, col=1)
        for a in (self.a1, self.a2):
            a.showGrid(x=True, y=True, alpha=0.25)
            a.getAxis("left").setWidth(66)
        self.a1.addLegend(offset=(-10, 10), labelTextSize="8pt")
        h.addWidget(self.gl, 4)
        v = QtWidgets.QVBoxLayout()
        h.addLayout(v, 1)
        v.addWidget(QtWidgets.QLabel("deviating if more than"))
        hh = QtWidgets.QHBoxLayout()
        self.eX = QtWidgets.QLineEdit(f"{win.ref_thr:g}")
        self.eX.setMaximumWidth(60)
        self.eX.editingFinished.connect(self.settings)
        hh.addWidget(self.eX)
        hh.addWidget(QtWidgets.QLabel("SD of the reference"))
        v.addLayout(hh)
        self.pW = QtWidgets.QComboBox()
        self.pW.addItems(["absolute (incl. amplitude)", "normalized (shape)", "absolute or normalized"])
        self.pW.setCurrentIndex(win.ref_which - 1)
        self.pW.activated.connect(self.settings)
        v.addWidget(self.pW)
        self.cX = QtWidgets.QCheckBox("exclude from the selection")
        self.cX.setChecked(win.ref_exclude)
        self.cX.toggled.connect(self.settings)
        v.addWidget(self.cX)
        self.cD = QtWidgets.QCheckBox("show deviating contractions")
        self.cD.setChecked(True)
        self.cD.toggled.connect(lambda *_: self.draw())
        v.addWidget(self.cD)
        hh = QtWidgets.QHBoxLayout()
        hh.addWidget(QtWidgets.QLabel("aligned at"))
        self.pA = QtWidgets.QComboBox()
        self.pA.addItems(["stimulus", "50 % upstroke"])
        self.pA.setCurrentIndex(1 if win.ref_align == "upstroke" else 0)
        self.pA.setToolTip("stimulus: a changed stimulus-to-contraction latency counts as deviation (contractions without "
                           "stimulus: aligned at the 50 % upstroke). 50 % upstroke: shape only.")
        self.pA.activated.connect(self.settings)
        hh.addWidget(self.pA)
        v.addLayout(hh)
        for text, cb, tip in (("Save reference ...", self.save, None),
                              ("Load reference ...", self.load, "reference saved before (e.g. baseline of the same "
                               "slice); used for the current channel"),
                              ("Remove reference", win.clear_reference, None)):
            b = QtWidgets.QPushButton(text)
            b.clicked.connect(cb)
            if tip:
                b.setToolTip(tip)
            v.addWidget(b)
        self.tx = QtWidgets.QLabel("")
        self.tx.setWordWrap(True)
        self.tx.setAlignment(QtCore.Qt.AlignmentFlag.AlignTop)
        v.addWidget(self.tx, 1)

    def closeEvent(self, ev):
        self.win.win_ref = None
        super().closeEvent(ev)

    def settings(self, *_):
        w = self.win
        try:
            x = float(self.eX.text())
            if x <= 0:
                raise ValueError
            w.ref_thr = x
        except ValueError:
            self.eX.setText(f"{w.ref_thr:g}")
        w.ref_which = self.pW.currentIndex() + 1
        w.ref_exclude = self.cX.isChecked()
        al = "stimulus" if self.pA.currentIndex() == 0 else "upstroke"
        R = w.current_reference()
        if R is not None and R.align != al:
            try:
                R = rb.align(R, al)
            except Exception as e:  # noqa: BLE001
                w.status(str(e))
                self.pA.setCurrentIndex(1 if R.align == "upstroke" else 0)
                return
            w.ref_align = al
            w.set_channel_reference(R)
            if w.S is not None:
                w.analyze(False)
            w.status(f"Reference beat of channel {w.ch}: aligned at the {_align_text(al)}.")
        else:
            w.ref_align = al
            if w.B is not None:
                w.refresh(False)
        self.draw()

    def draw(self):
        w = self.win
        R = w.current_reference()
        for a in (self.a1, self.a2):
            a.clear()
        if self.a1.legend is not None:
            self.a1.legend.clear()
        if R is None:
            self.a1.setTitle(f"channel {w.ch}: no reference beat (select contractions, right click in the force plot)",
                             size="9pt")
            self.a2.setTitle("")
            self.tx.setText("")
            return
        R = rb.align(R, "")
        self.pA.setCurrentIndex(1 if R.align == "upstroke" else 0)
        tg = np.asarray(R.tGrid, float) * 1000
        M = (np.asarray(R.mean, float), np.asarray(R.meanNorm, float))
        SD = (np.asarray(R.sd, float), np.asarray(R.sdNorm, float))
        ttl = (f"reference, channel {w.ch}: mean ± SD ({MU}N)", "normalized to amplitude 1 (shape)")
        x = w.ref_thr
        for q, a in enumerate((self.a1, self.a2)):
            tp = pg.mkPen((0, 0, 0, 0))
            lo2 = pg.PlotDataItem(tg, M[q] - x * SD[q], pen=tp)
            hi2 = pg.PlotDataItem(tg, M[q] + x * SD[q], pen=tp)
            lo1 = pg.PlotDataItem(tg, M[q] - SD[q], pen=tp)
            hi1 = pg.PlotDataItem(tg, M[q] + SD[q], pen=tp)
            for it in (lo2, hi2, lo1, hi1):
                a.addItem(it)
            a.addItem(pg.FillBetweenItem(lo2, hi2, brush=pg.mkBrush(217, 217, 255)))
            f1 = pg.FillBetweenItem(lo1, hi1, brush=pg.mkBrush(153, 153, 242))
            a.addItem(f1)
            a.plot(tg, M[q], pen=pg.mkPen("b", width=2), name="mean" if q == 0 else None)
            a.setTitle(ttl[q], size="9pt")
            a.setLabel("bottom", f"time from the {_align_text(R.align)} (ms)")
        self.a1.setLabel("left", f"developed force ({MU}N)")
        self.a2.setLabel("left", "force / amplitude")
        if self.a1.legend is not None:  # legend entry of the band (a FillBetweenItem cannot be a legend sample)
            dummy = pg.PlotDataItem([np.nan], [np.nan], pen=pg.mkPen((153, 153, 242), width=8))
            self.a1.addItem(dummy)
            self.a1.legend.addItem(dummy, f"± 1 SD (light: ± {x:g} SD)")
        nDev = nCmp = 0
        B, C = w.B, w.C
        if B is not None and C is not None and C.get("referenceBeat") is not None:
            inR = w.in_range()
            dv = np.flatnonzero(w.deviating() & inR)
            nDev = dv.size
            nCmp = int(np.sum(inR & ~np.isnan(B["refMaxDeviation_SD"].to_numpy(float))))
            if self.cD.isChecked() and dv.size:
                dv = dv[:40]
                Y = rb.traces(C, B, R, dv)
                amp = B["amplitude"].to_numpy(float)
                for k, r in enumerate(dv):
                    self.a1.plot(tg, Y[:, k], pen=pg.mkPen((230, 0, 230, 153), width=1))
                    self.a2.plot(tg, Y[:, k] / amp[r], pen=pg.mkPen((230, 0, 230, 153), width=1))
        wtxt = {1: "absolute", 2: "normalized", 3: "absolute or normalized"}[w.ref_which]
        self.tx.setText("\n".join([
            str(R.source), f"created {R.created}; aligned at the {_align_text(R.align)} ({R.n} contractions)",
            f"amplitude of the mean {R.amp:.0f} {MU}N",
            f"loaded range: {nDev} of {nCmp} compared contractions deviate by > {x:g} SD ({wtxt}, maximum); magenta = "
            "deviating (at most 40 shown)",
            "Parameters (tables, lower plot, trend): refCorrelation (1 = same shape), refRMSDeviation_SD (overall), "
            "refMaxDeviation_SD (largest local deviation), ...Norm: amplitude 1."]))

    def save(self):
        w = self.win
        R = w.current_reference()
        if R is None:
            w.status("No reference beat for this channel.")
            return
        n = os.path.splitext(os.path.basename(w.H.file))[0]
        d = os.path.join(w.last_dir or os.path.dirname(w.H.file), f"{n}_ch{w.ch}_referenceBeat.mat")
        fn, _ = QtWidgets.QFileDialog.getSaveFileName(self, "Save reference beat", d, "MATLAB file (*.mat)")
        if not fn:
            return
        w.last_dir = os.path.dirname(fn)
        rb.save_reference(fn, R)
        w.status("Reference beat saved: " + fn)

    def load(self):
        w = self.win
        p = w.last_dir or os.path.dirname(w.H.file)
        fn, _ = QtWidgets.QFileDialog.getOpenFileName(self, "Load reference beat", p, "MATLAB file (*.mat)")
        if not fn:
            return
        try:
            R = rb.load_reference(fn)[0]
            if R.get("tGrid") is None or R.get("sdNorm") is None:
                raise ValueError("no reference beat in this file")
        except Exception as e:  # noqa: BLE001
            w.status(f"Load reference: {e}")
            return
        w.last_dir = os.path.dirname(fn)
        R.channel = w.ch  # used for the current channel
        w.set_channel_reference(R)
        if w.S is not None:
            w.analyze(False)
        self.draw()
        msg = f"Reference beat loaded for channel {w.ch} ({R.source})."
        if R.get("params") is None:
            msg += " Saved before 2026-10-06: no parameter values, columns ..._pctRef are NaN - create it again."
        w.status(msg)
