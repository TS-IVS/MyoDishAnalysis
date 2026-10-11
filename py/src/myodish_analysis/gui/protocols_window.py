# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Protocol window: stimulation protocols of the log file (force-frequency, refractory period, stimulation threshold,
post-rest potentiation, pulse duration, rocker speed ...), contractions grouped by the protocol quantity, summary per
group and plot of a parameter against the quantity. Port of the protocol part of MyoDishAnalysisGUI.m.

TS 2026-10-07
"""
from __future__ import annotations

import math
import os

import numpy as np
import pandas as pd
import pyqtgraph as pg
from PySide6 import QtCore, QtWidgets

from ..analysis import myodish_analysis
from ..parameters import PARAMETERS
from ..protocols import GROUP_BY, find_protocols
from ..write_results import write_results

MU = "µ"
X_LABEL = {"pacingFrequency": ("pacing frequency (Hz)", 1.0), "S2interval": ("S2 interval (ms)", 1000.0),
           "stimCurrent": ("stimulus current (mA)", 1.0), "pauseLength": ("rest interval (s)", 1.0),
           "rockerSpeed": ("rocker speed (rpm)", 1.0), "pulseDuration": ("pulse duration (ms)", 1.0)}
CONTRACTIONS = [("rocker at rest only", "stopped"), ("all contractions", "any"), ("rocker moving only", "moving")]
COLORS = [(0, 114, 189), (217, 83, 25), (237, 177, 32), (126, 47, 142), (119, 172, 48), (77, 190, 238),
          (162, 20, 47), (0, 0, 0)]


def plot_parameters():
    """parameters that can be plotted against the group quantity: (column base name, unit)."""
    lst = [(p[0], p[1]) for p in PARAMETERS if not p[0].startswith("ref")]
    return lst + [("amplitude_pctOfRef", "% of S1 / steady"), ("capture_percent", "%"), ("nContractions", "")]


class ProtocolWindow(QtWidgets.QWidget):
    def __init__(self, win):
        super().__init__()
        self.win = win
        self.T = self.S = self.info = None
        self.setWindowFlag(QtCore.Qt.WindowType.Window)
        self.setWindowTitle("MyoDishAnalysis: protocols - " + os.path.basename(win.H.file))
        self.resize(1400, 760)
        h = QtWidgets.QHBoxLayout(self)
        # left: plot and result table
        left = QtWidgets.QVBoxLayout()
        h.addLayout(left, 3)
        self.gl = pg.GraphicsLayoutWidget()
        self.gl.setBackground("w")
        self.p = self.gl.addPlot()
        self.p.showGrid(x=True, y=True, alpha=0.15)
        for ax in ("left", "bottom"):
            self.p.getAxis(ax).setPen("k")
            self.p.getAxis(ax).setTextPen("k")
        self.legend = self.p.addLegend(offset=(-10, 10), labelTextSize="8pt")
        left.addWidget(self.gl, 3)
        self.tbl = QtWidgets.QTableWidget(0, 0)
        self.tbl.setEditTriggers(QtWidgets.QAbstractItemView.EditTrigger.NoEditTriggers)
        left.addWidget(self.tbl, 2)
        # right: protocols and settings
        v = QtWidgets.QVBoxLayout()
        h.addLayout(v, 2)
        lab = QtWidgets.QLabel("Protocols (comments 'start ... protocol' / 'end ... protocol' or schedule files in the "
                               "log file). Tick the protocols to analyse; From / To and the grouping can be changed.")
        lab.setWordWrap(True)
        v.addWidget(lab)
        self.tp = QtWidgets.QTableWidget(0, 7)
        self.tp.setHorizontalHeaderLabels(["use", "type", "name", "from (s)", "to (s)", "group by", "note"])
        self.tp.verticalHeader().setVisible(False)
        hh = self.tp.horizontalHeader()
        for c in range(7):
            hh.setSectionResizeMode(c, QtWidgets.QHeaderView.ResizeMode.ResizeToContents)
        hh.setSectionResizeMode(2, QtWidgets.QHeaderView.ResizeMode.Stretch)
        v.addWidget(self.tp, 2)
        row = QtWidgets.QHBoxLayout()
        for text, cb, tip in (("Find in log file", self.find, "search the comments of the log file again"),
                              ("+ selected range", self.add_range, "add the range selected in the main window as a "
                               "protocol (choose the grouping)"),
                              ("Remove", self.remove, "remove the selected row")):
            b = QtWidgets.QPushButton(text)
            b.setToolTip(tip)
            b.clicked.connect(cb)
            row.addWidget(b)
        v.addLayout(row)
        g = QtWidgets.QGridLayout()
        g.addWidget(QtWidgets.QLabel("Channels"), 0, 0, QtCore.Qt.AlignmentFlag.AlignTop)
        self.lc = QtWidgets.QListWidget()
        for c in win.H.dataChannels:
            it = QtWidgets.QListWidgetItem(f"Ch {int(c)}")
            it.setFlags(it.flags() | QtCore.Qt.ItemFlag.ItemIsUserCheckable)
            it.setCheckState(QtCore.Qt.CheckState.Checked if int(c) == win.ch else QtCore.Qt.CheckState.Unchecked)
            self.lc.addItem(it)
        self.lc.setMaximumHeight(110)
        g.addWidget(self.lc, 0, 1)
        g.addWidget(QtWidgets.QLabel("Contractions"), 1, 0)
        self.cR = QtWidgets.QComboBox()
        self.cR.addItems([c[0] for c in CONTRACTIONS])
        self.cR.setToolTip("default: only contractions with the rocker at rest. Sharp-electrode recordings (no rocker) "
                           "or protocols without rocker stops: all contractions")
        g.addWidget(self.cR, 1, 1)
        self.cStim = QtWidgets.QCheckBox("only stimulated contractions")
        self.cStim.setChecked(True)  # protocols: stimulated contractions (as MyoDishAnalysis)
        g.addWidget(self.cStim, 2, 1)
        g.addWidget(QtWidgets.QLabel("Parameter"), 3, 0)
        self.cP = QtWidgets.QComboBox()
        self.params = plot_parameters()
        for nm, u in self.params:
            uu = u.replace("u", MU) if u.startswith("u") else u
            self.cP.addItem(f"{nm} ({uu})" if uu else nm)
        self.cP.currentIndexChanged.connect(lambda *_: self.draw())
        g.addWidget(self.cP, 3, 1)
        g.addWidget(QtWidgets.QLabel("Show"), 4, 0)
        self.cShow = QtWidgets.QComboBox()
        self.cShow.setToolTip("protocols grouped by the same quantity are shown together")
        self.cShow.currentIndexChanged.connect(lambda *_: self.draw())
        g.addWidget(self.cShow, 4, 1)
        self.cSD = QtWidgets.QComboBox()
        self.cSD.addItems(["mean ± SD", "mean ± SEM", "mean"])
        self.cSD.currentIndexChanged.connect(lambda *_: self.draw())
        g.addWidget(self.cSD, 5, 1)
        g.addWidget(QtWidgets.QLabel("Table"), 6, 0)
        self.cTab = QtWidgets.QComboBox()
        self.cTab.addItems(["groups", "protocol results"])
        self.cTab.setToolTip("protocol results: max. captured frequency, FFR ratios, current thresholds, refractory "
                             "periods (no peak / no response), PRP at 15 / 30 / 60 s, per protocol and channel")
        self.cTab.currentIndexChanged.connect(lambda *_: self.fill_table())
        g.addWidget(self.cTab, 6, 1)
        v.addLayout(g)
        b = QtWidgets.QPushButton("Analyse")
        f = b.font()
        f.setBold(True)
        b.setFont(f)
        b.setToolTip("contractions of the ticked protocols and channels, grouped (threshold, filters, zero force, rocker "
                     "filter and labels as in the main window)")
        b.clicked.connect(self.analyse)
        v.addWidget(b)
        row = QtWidgets.QHBoxLayout()
        for text, cb in (("Save figure ...", self.save_figure), ("Export ...", self.export)):
            b = QtWidgets.QPushButton(text)
            b.clicked.connect(cb)
            row.addWidget(b)
        v.addLayout(row)
        self.tx = QtWidgets.QLabel("")
        self.tx.setWordWrap(True)
        v.addWidget(self.tx)
        v.addStretch(1)
        self.find()

    # ---------------------------------------------------------------- protocol table
    def find(self):
        try:
            P = find_protocols(self.win.H)
        except Exception as e:  # noqa: BLE001
            self.tx.setText(f"Protocols: {e}")
            P = pd.DataFrame(columns=["type", "name", "number", "from", "to", "groupBy", "note"])
        self.tp.setRowCount(0)
        for _, r in P.iterrows():
            self._add_row(r["type"], r["name"], r["from"], r["to"], r["groupBy"], r["note"], r["type"] != "other")
        n = len(P)
        self.tx.setText(f"{n} protocol(s) found in the log file." if n else
                        "No protocol found (comments 'start ... protocol' / 'end ... protocol'). Add a range with "
                        "'+ selected range'.")

    def _add_row(self, typ, name, a, b, by, note, use):
        r = self.tp.rowCount()
        self.tp.insertRow(r)
        it = QtWidgets.QTableWidgetItem("")
        it.setFlags(QtCore.Qt.ItemFlag.ItemIsUserCheckable | QtCore.Qt.ItemFlag.ItemIsEnabled)
        it.setCheckState(QtCore.Qt.CheckState.Checked if use else QtCore.Qt.CheckState.Unchecked)
        self.tp.setItem(r, 0, it)
        for c, val in ((1, typ), (2, name), (6, note)):
            itc = QtWidgets.QTableWidgetItem(str(val))
            if c == 6:
                itc.setFlags(itc.flags() & ~QtCore.Qt.ItemFlag.ItemIsEditable)
            self.tp.setItem(r, c, itc)
        self.tp.setItem(r, 3, QtWidgets.QTableWidgetItem(f"{a:.2f}"))
        self.tp.setItem(r, 4, QtWidgets.QTableWidgetItem(f"{b:.2f}"))
        cb = QtWidgets.QComboBox()
        cb.setEditable(True)  # also 'log:<code>'
        cb.addItems(GROUP_BY + ["none"])
        cb.setCurrentText(str(by))
        cb.setToolTip("quantity: pacingFrequency, S2interval, stimCurrent, pauseLength, rockerSpeed, pulseDuration, "
                      "log:<code> (any numeric entry of the log file, e.g. log:pauseDuration), none")
        self.tp.setCellWidget(r, 5, cb)

    def add_range(self):
        rg = self.win.range
        if rg is None or any(math.isnan(x) for x in rg):
            self.tx.setText("Select a range in the main window first.")
            return
        self._add_row("manual", "selected range", rg[0], rg[1], "pacingFrequency", "", True)

    def remove(self):
        r = self.tp.currentRow()
        if r >= 0:
            self.tp.removeRow(r)

    def selected_protocols(self):
        rows = []
        n = {}
        for r in range(self.tp.rowCount()):
            if self.tp.item(r, 0).checkState() != QtCore.Qt.CheckState.Checked:
                continue
            typ = self.tp.item(r, 1).text().strip() or "manual"
            try:
                a = float(self.tp.item(r, 3).text())
                b = float(self.tp.item(r, 4).text())
            except ValueError:
                raise ValueError(f"row {r + 1}: From / To must be numbers (s).")
            if b <= a:
                raise ValueError(f"row {r + 1}: To must be larger than From.")
            n[typ] = n.get(typ, 0) + 1
            rows.append([typ, self.tp.item(r, 2).text(), float(n[typ]), a, b,
                         self.tp.cellWidget(r, 5).currentText().strip() or "none", "", "", ""])
        return pd.DataFrame(rows, columns=["type", "name", "number", "from", "to", "groupBy", "startComment",
                                           "endComment", "note"])

    def channels(self):
        return [int(self.win.H.dataChannels[k]) for k in range(self.lc.count())
                if self.lc.item(k).checkState() == QtCore.Qt.CheckState.Checked]

    # ---------------------------------------------------------------- analysis
    def analyse(self):
        win = self.win
        try:
            P = self.selected_protocols()
        except ValueError as e:
            self.tx.setText(str(e))
            return
        chs = self.channels()
        if len(P) == 0 or not chs:
            self.tx.setText("Tick at least one protocol and one channel.")
            return
        self.tx.setText("Analysing ...")
        QtWidgets.QApplication.processEvents()
        o = dict(win.opts)
        for k in ("rocker", "beats", "zeroForce", "threshold"):
            o.pop(k, None)
        try:
            T, S, info = myodish_analysis(win.H.file, chs, protocol=P, quiet=True, metadata=win.Lbl,
                                          rocker=CONTRACTIONS[self.cR.currentIndex()][1],
                                          beats="stimulated" if self.cStim.isChecked() else "all",
                                          zeroForce=[win.zero_of(c) for c in chs], threshold=win.thr_of(list(chs)),
                                          **o)
        except Exception as e:  # noqa: BLE001
            self.tx.setText(f"Error: {e}")
            return
        self.T, self.S, self.info = T, S, info
        qs = []
        for q in S["groupBy"]:
            if q != "none" and q not in qs:
                qs.append(q)
        self.cShow.blockSignals(True)
        self.cShow.clear()
        for q in qs:
            rgs = list(dict.fromkeys(S.loc[S["groupBy"] == q, "range"]))
            self.cShow.addItem(f"{q}: {', '.join(rgs)}", q)
        self.cShow.blockSignals(False)
        notes = " ".join(info.get("notes", [])[:2])
        self.tx.setText(f"{len(T)} contractions, {len(S)} groups ({', '.join(P['type'] + ' ' + P['number'].astype(int).astype(str))}; "
                        f"channels {', '.join(map(str, chs))}). {notes}")
        self.draw()

    def draw(self):
        self.p.clear()
        self.legend.clear()
        S = self.S
        if S is None or self.cShow.count() == 0:
            self.fill_table()
            return
        q = self.cShow.currentData()
        nm, unit = self.params[max(0, self.cP.currentIndex())]
        mcol = nm if nm in ("amplitude_pctOfRef", "capture_percent", "nContractions") else nm + "_mean"
        scol = None if mcol != nm + "_mean" else nm + "_SD"
        D = S[S["groupBy"] == q]
        xl, xf = X_LABEL.get(q, (q.replace("log:", "") if q.startswith("log:") else q, 1.0))
        k = 0
        for (rg, ch), G in D.groupby(["range", "channel"], sort=False):
            col = COLORS[k % len(COLORS)]
            k += 1
            for role, Gr in G.groupby("groupRole", sort=False):
                if role in ("other", "preS2", "afterRest"):  # no value: table only
                    continue
                y = Gr[mcol].to_numpy(float)
                x = Gr["groupValue"].to_numpy(float) * xf
                if role in ("S1", "steady"):  # reference: horizontal line
                    if y.size and not math.isnan(y[0]):
                        ln = pg.InfiniteLine(pos=y[0], angle=0, pen=pg.mkPen(col, width=1.5, style=QtCore.Qt.PenStyle.DashLine))
                        self.p.addItem(ln)
                        self.legend.addItem(pg.PlotDataItem(pen=pg.mkPen(col, width=1.5, style=QtCore.Qt.PenStyle.DashLine)),
                                            f"Ch {ch} {rg} {role}")
                    continue
                ok = ~np.isnan(x)
                x, y = x[ok], y[ok]
                o = np.argsort(x, kind="stable")
                x, y = x[o], y[o]
                sym = "o" if role != "postS2" else "s"
                it = pg.PlotDataItem(x, y, pen=pg.mkPen(col, width=1.5,
                                                        style=QtCore.Qt.PenStyle.DotLine if role == "postS2"
                                                        else QtCore.Qt.PenStyle.SolidLine),
                                     symbol=sym, symbolSize=7, symbolBrush=pg.mkBrush(col), symbolPen=pg.mkPen(col))
                self.p.addItem(it)
                lab = f"Ch {ch} {rg}" + (f" {'post-S2' if role == 'postS2' else role}" if role else "")
                self.legend.addItem(it, lab)
                if scol and self.cSD.currentIndex() < 2:
                    e = Gr[scol].to_numpy(float)[ok][o]
                    if self.cSD.currentIndex() == 1:
                        n = Gr[nm + "_n"].to_numpy(float)[ok][o]
                        with np.errstate(invalid="ignore", divide="ignore"):
                            e = e / np.sqrt(n)
                    e = np.where(np.isnan(e), 0, e)
                    eb = pg.ErrorBarItem(x=x, y=y, top=e, bottom=e, beam=0, pen=pg.mkPen(col, width=1))
                    self.p.addItem(eb)
        uu = unit.replace("u", MU) if unit.startswith("u") else unit
        self.p.setLabel("bottom", xl, color="k")
        self.p.setLabel("left", f"{nm} ({uu})" if uu else nm, color="k")
        self.p.enableAutoRange()
        self.fill_table()

    def fill_table(self):
        S = self.S
        if S is None:
            self.tbl.setRowCount(0)
            return
        if self.cTab.currentIndex() == 1:  # protocol results: the columns with values
            S = self.info.get("protocolResults") if self.info else None
            if S is None or len(S) == 0:
                self.tbl.setRowCount(0)
                return
            vals = [c for c in S.columns[S.columns.get_loc("groupBy") + 1:] if c != "resultNote"
                    and S[c].notna().any()]
            cols = ["range", "channel"] + vals + ["resultNote"]
        else:
            nm, _ = self.params[max(0, self.cP.currentIndex())]
            cols = self._group_columns(S, ["range", "channel", "group", "nStimuli", "nContractions",
                                           "capture_percent"], nm)
        self._fill(S, cols)

    @staticmethod
    def _group_columns(S, cols, nm):
        if nm + "_mean" in S.columns:
            cols += [nm + "_mean", nm + "_SD", nm + "_n"]
        elif nm in S.columns and nm not in cols:
            cols += [nm]
        if "amplitude_pctOfRef" not in cols:
            cols += ["amplitude_pctOfRef"]
        return cols

    def _fill(self, S, cols):
        self.tbl.setColumnCount(len(cols))
        self.tbl.setHorizontalHeaderLabels(cols)
        self.tbl.setRowCount(len(S))
        for i, (_, r) in enumerate(S[cols].iterrows()):
            for j, c in enumerate(cols):
                v = r[c]
                if isinstance(v, (float, np.floating)):
                    s = "" if math.isnan(v) else (f"{v:.0f}" if c.startswith("n") else f"{v:.4g}")
                else:
                    s = str(v)
                self.tbl.setItem(i, j, QtWidgets.QTableWidgetItem(s))
        self.tbl.resizeColumnsToContents()

    # ---------------------------------------------------------------- output
    def save_figure(self):
        from .dialogs import ask_file, save_items
        if self.S is None:
            self.tx.setText("Press Analyse first.")
            return
        file = ask_file(self.win, "image", "protocols")
        if not file:
            return
        try:
            save_items([self.p], file, 2400)
            self.tx.setText("Saved: " + file)
        except Exception as e:  # noqa: BLE001
            self.tx.setText(f"Save: {e}")

    def export(self):
        from .dialogs import ask_file
        if self.S is None:
            self.tx.setText("Press Analyse first.")
            return
        file = ask_file(self.win, "data", "protocols")
        if not file:
            return
        try:
            files = write_results(file, self.T, self.S, self.info)
            self.tx.setText("Written: " + ", ".join(os.path.basename(f) for f in files))
        except Exception as e:  # noqa: BLE001
            self.tx.setText(f"Export: {e}")
