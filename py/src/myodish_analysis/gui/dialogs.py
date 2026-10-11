# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Dialogs of the GUI: comments of the log file, labels per channel, contraction table, help, file dialogs, saving plots
(images) and exporting the plotted data. Port of the corresponding parts of MyoDishAnalysisGUI.m.

TS 2026-10-06 (info table in every export, open results, rocker artifact window 2026-10-09; advanced settings
2026-10-10)
"""
from __future__ import annotations

import math
import os

import numpy as np
import pandas as pd
import pyqtgraph as pg
from PySide6 import QtCore, QtGui, QtWidgets

from ..advanced import ROWS as ADVANCED_ROWS, TABS as ADVANCED_TABS
from ..analyze_ap import AP_PARAMETERS
from ..analysis import datenum_to_timestamps
from ..labels import labels as make_labels
from ..parameters import PARAMETERS
from ..zero_force import zero_force
from .timeaxis import fmt_clock
from .widgets import TwinPlot, runs, time_plot

IMAGE_FILTER = "PNG image (*.png);;JPEG image (*.jpg);;TIFF image (*.tif);;PDF vector graphic (*.pdf)"
SHOT_FILTER = "PNG image (*.png);;JPEG image (*.jpg);;TIFF image (*.tif)"
DATA_FILTER = "Excel (*.xlsx);;comma separated (*.csv);;tab separated text (*.txt)"


def ask_file(win, kind, what):
    """file name dialog; kind 'image', 'screenshot' or 'data'. win.next_file (scripts / tests): this file, no dialog."""
    if getattr(win, "next_file", ""):
        fn, win.next_file = win.next_file, ""
        return fn
    H = win.H
    p = os.path.dirname(H.file)
    n = os.path.splitext(os.path.basename(H.file))[0]
    if not win.last_dir:
        win.last_dir = p
    flt = {"image": IMAGE_FILTER, "screenshot": SHOT_FILTER}.get(kind, DATA_FILTER)
    ext = ".png" if kind != "data" else ".xlsx"
    base = f"{n}_overlay" if what == "overlay" else f"{n}_ch{win.ch}_{what}"
    fn, sel = QtWidgets.QFileDialog.getSaveFileName(win, f"Save {what}", os.path.join(win.last_dir, base + ext), flt)
    if not fn:
        return ""
    if not os.path.splitext(fn)[1]:
        e = sel[sel.rfind("*.") + 1:-1] if "*." in sel else ext
        fn += e
    win.last_dir = os.path.dirname(fn)
    return fn


# ----------------------------------------------------------------------------------------------- images
EXPORT_HEIGHT = {"overview": 1, "force": 2.4, "stimuli": 1, "parameter": 1.5}  # relative heights as in the MATLAB GUI


def _scaled_pen(pen, s):
    q = QtGui.QPen(pg.mkPen(pen))
    if q.style() != QtCore.Qt.PenStyle.NoPen:
        w = q.widthF()
        q.setWidthF((w if w > 0 else 1.0) * s)
    return q


def _scale_pens(scene, s):
    """line widths x s for a raster image with s image pixels per screen pixel (pyqtgraph pens are cosmetic: 1 device
    pixel wide whatever the scale). Returns the list to undo it."""
    undo = []
    if s == 1:
        return undo
    for it in scene.items():
        try:
            if isinstance(it.parentItem(), pg.PlotDataItem):
                continue  # drawn by the PlotDataItem (curve / scatter of it)
            if isinstance(it, pg.PlotDataItem):
                o = (it.opts.get("pen"), it.opts.get("symbolPen"))
                it.setPen(_scaled_pen(o[0], s) if o[0] is not None else None)
                if o[1] is not None and it.opts.get("symbol") is not None:
                    it.setSymbolPen(_scaled_pen(o[1], s))
                undo.append((it, "pdi", o))
            elif isinstance(it, (pg.PlotCurveItem, pg.ScatterPlotItem)):
                o = it.opts.get("pen")
                if o is not None:
                    it.setPen(_scaled_pen(o, s))
                    undo.append((it, "pen", o))
            elif isinstance(it, pg.AxisItem):
                o = it.pen()
                it.setPen(_scaled_pen(o, s))
                undo.append((it, "pen", o))
            elif isinstance(it, pg.InfiniteLine):
                o = QtGui.QPen(it.pen)
                it.setPen(_scaled_pen(o, s))
                undo.append((it, "pen", o))
            elif isinstance(it, pg.BarGraphItem) and it.opts.get("pen") is not None:
                o = it.opts.get("pen")
                it.setOpts(pen=_scaled_pen(o, s))
                undo.append((it, "bar", o))
        except Exception:  # noqa: BLE001  (an item that cannot be changed is drawn with its own pen)
            pass
    return undo


def _undo_pens(undo):
    for it, kind, o in reversed(undo):
        try:
            if kind == "pdi":
                it.setPen(o[0])
                if o[1] is not None and it.opts.get("symbol") is not None:
                    it.setSymbolPen(o[1])
            elif kind == "bar":
                it.setOpts(pen=o)
            else:
                it.setPen(o)
        except Exception:  # noqa: BLE001
            pass


def _export_mode(scene, on, opts=None):
    for it in scene.items():
        if hasattr(it, "setExportMode"):
            try:
                it.setExportMode(on, opts or {})
            except Exception:  # noqa: BLE001
                pass


def render_scene(scene, src, file, width_px=3000, dpi=300):
    """draw the part src (scene coordinates) of a graphics scene into a file: .png / .jpg / .tif with width_px pixels
    (saved with dpi) or .pdf (vector graphic, size as on the screen; editable e.g. in Inkscape / Illustrator). No .svg:
    Qt writes the lines of the plots as non-scaling strokes, which Inkscape, Illustrator and cairo do not draw
    correctly."""
    ext = os.path.splitext(file)[1].lower()
    src = QtCore.QRectF(src)
    w, h = src.width(), src.height()
    sdpi = QtGui.QGuiApplication.primaryScreen().logicalDotsPerInch() if QtGui.QGuiApplication.primaryScreen() else 96
    hints = (QtGui.QPainter.RenderHint.Antialiasing | QtGui.QPainter.RenderHint.TextAntialiasing |
             QtGui.QPainter.RenderHint.SmoothPixmapTransform)
    if ext == ".pdf":  # vector graphic (lines as on the screen: cosmetic pens are converted by Qt's pdf engine)
        dev = QtGui.QPdfWriter(file)
        dev.setResolution(int(round(sdpi)))
        dev.setPageMargins(QtCore.QMarginsF(0, 0, 0, 0))
        dev.setPageSize(QtGui.QPageSize(QtCore.QSizeF(w / sdpi * 25.4, h / sdpi * 25.4),
                                        QtGui.QPageSize.Unit.Millimeter, "plot"))
        dev.setCreator("MyoDishAnalysis")
        dev.setTitle(os.path.splitext(os.path.basename(file))[0])
        _export_mode(scene, True, {"antialias": True, "background": pg.mkColor("w"), "resolutionScale": 1.0})
        pa = QtGui.QPainter()
        if not pa.begin(dev):
            _export_mode(scene, False)
            raise IOError(f"could not write {file}")
        try:
            pa.setRenderHints(hints)
            tgt = QtCore.QRectF(pa.viewport())
            pa.fillRect(tgt, QtGui.QColor("white"))
            scene.render(pa, tgt, src, QtCore.Qt.AspectRatioMode.IgnoreAspectRatio)
        finally:
            pa.end()
            _export_mode(scene, False)
        return
    s = float(width_px) / w
    img = QtGui.QImage(int(round(w * s)), int(round(h * s)), QtGui.QImage.Format.Format_ARGB32)
    dpm = int(round(sdpi / 0.0254))
    img.setDotsPerMeterX(dpm)  # text metrics as on the screen (the layout was made with them)
    img.setDotsPerMeterY(dpm)
    img.fill(QtGui.QColor("white"))
    undo = _scale_pens(scene, s)
    flag = QtWidgets.QGraphicsItem.GraphicsItemFlag.ItemIgnoresTransformations
    fixed = [it for it in scene.items() if isinstance(it, pg.LegendItem) and it.flags() & flag]
    for it in fixed:  # legends are drawn in screen pixels: scaled with the image like everything else
        it.setFlag(flag, False)
    _export_mode(scene, True, {"antialias": True, "background": pg.mkColor("w"), "resolutionScale": s})
    pa = QtGui.QPainter(img)
    try:
        pa.setRenderHints(hints)
        scene.render(pa, QtCore.QRectF(0, 0, img.width(), img.height()), src,
                     QtCore.Qt.AspectRatioMode.IgnoreAspectRatio)
    finally:
        pa.end()
        _export_mode(scene, False)
        _undo_pens(undo)
        for it in fixed:
            it.setFlag(flag, True)
    img.setDotsPerMeterX(int(round(dpi / 0.0254)))
    img.setDotsPerMeterY(int(round(dpi / 0.0254)))
    if ext in (".jpg", ".jpeg"):
        img = img.convertToFormat(QtGui.QImage.Format.Format_RGB32)
    wr = QtGui.QImageWriter(file)
    if ext in (".jpg", ".jpeg"):
        wr.setQuality(95)
    elif ext in (".tif", ".tiff"):
        wr.setCompression(1)  # LZW
    if not wr.write(img):
        raise IOError(f"could not write {file}: {wr.errorString()}")


def save_items(items, file, width_px=3000):
    """save plot items of a window (the rectangle around them, as on the screen)."""
    r = QtCore.QRectF()
    for it in items:
        r = r.united(it.sceneBoundingRect())
    render_scene(items[0].scene(), r, file, width_px)


def export_figure(win, lst, width=1300):
    """the plots of the main window without controls, stacked like the MATLAB GUI (makePlainFigure): overview, force,
    stimuli, parameter; hidden widget with new plot items drawn by the plot functions of the main window."""
    hgt = [EXPORT_HEIGHT[x] for x in lst]
    gw = pg.GraphicsLayoutWidget()
    gw.setAttribute(QtCore.Qt.WidgetAttribute.WA_DontShowOnScreen, True)
    gw.setBackground("w")
    gw.setFixedSize(width, int(120 + 190 * sum(hgt)))
    gw.ci.setContentsMargins(10, 10, 10, 10)
    gw.ci.setSpacing(14)
    timed = [x for x in lst if x != "overview"]
    plots = {}
    for k, nm in enumerate(lst):
        last = bool(timed) and nm == timed[-1]
        if nm == "stimuli":
            tw = TwinPlot(show_x_labels=last)
            gw.addItem(tw.p, row=k, col=0)
            tw.attach()
            plots[nm] = tw
        else:
            p = time_plot(show_x_labels=(nm == "overview" or last), right_width=50)
            gw.addItem(p, row=k, col=0)
            plots[nm] = p
        gw.ci.layout.setRowStretchFactor(k, int(round(10 * hgt[k])))
    gw.show()
    QtWidgets.QApplication.processEvents()
    xl = win.pMain.vb.viewRange()[0]
    for nm in lst:
        if nm == "overview":
            win.plot_overview(target=plots[nm])
        elif nm == "force":
            win.plot_main(False, target=plots[nm])
        elif nm == "stimuli":
            win.plot_stim(target=plots[nm])
        else:
            win.plot_param(target=plots[nm])
    for nm in timed:
        p = plots[nm].p if nm == "stimuli" else plots[nm]
        p.vb.setXRange(xl[0], xl[1], padding=0)
    if timed:
        p = plots[timed[-1]].p if timed[-1] == "stimuli" else plots[timed[-1]]
        p.setLabel("bottom", win.x_label_text())
    QtWidgets.QApplication.processEvents()
    if "stimuli" in plots:
        plots["stimuli"]._sync()
    gw._plots = plots  # keep the TwinPlot (its second view box is a separate scene item)
    return gw


def save_plot_images(win, which):
    if win.H is None:
        win.status("Open a file first.")
        return
    if which == "window":
        file = ask_file(win, "screenshot", "window")
        if not file:
            return
        pm = win.grab()
        pm.save(file, None, 95 if file.lower().endswith((".jpg", ".jpeg")) else -1)
        win.status("Saved: " + file)
        return
    lst = ["overview", "force", "stimuli", "parameter"] if which == "all" else [which]
    if win.O is None:
        lst = [x for x in lst if x != "overview"]
    if win.S is None or win.C is None:
        lst = [x for x in lst if x == "overview"]
    if not lst:
        win.status("Nothing to save (press Overview or load a time window first).")
        return
    file = ask_file(win, "image", which)
    if not file:
        return
    write_plot_images(win, lst, file)


def write_plot_images(win, lst, file, width_px=3000):
    gw = None
    try:
        gw = export_figure(win, lst)
        render_scene(gw.scene(), QtCore.QRectF(0, 0, gw.width(), gw.height()), file, width_px)
        win.status("Saved: " + file)
    except Exception as e:  # noqa: BLE001
        win.status(f"Save: {e}")
    finally:
        if gw is not None:
            gw.hide()
            gw.deleteLater()


# ----------------------------------------------------------------------------------------------- data
def write_tables(win, file, names, tabs):
    """.xlsx: one sheet per table; .csv / .txt: one file per table (<name>_<table>.csv if several). Always with the table
    'info' (version, file, all settings: info_table of write_results; 2026-10-09)."""
    from ..write_results import info_table
    p, nm = os.path.split(file)
    n, e = os.path.splitext(nm)
    nData = len(tabs)
    names = list(names) + ["info"]
    tabs = list(tabs) + [info_table(win.gui_info())]
    try:
        if e.lower() == ".xlsx":
            with pd.ExcelWriter(file, engine="openpyxl") as xw:
                for name, T in zip(names, tabs):
                    _plain(T).to_excel(xw, sheet_name=name[:31], index=False)
            files = [file]
        elif e.lower() in (".csv", ".txt"):
            sep = "," if e.lower() == ".csv" else "\t"
            files = [os.path.join(p, f"{n}_{name}{e}") for name in names]
            if nData == 1:
                files[0] = file  # one data table: the file name chosen
            for f, T in zip(files, tabs):
                _plain(T, text=True).to_csv(f, sep=sep, index=False)
        else:
            raise ValueError(f"unknown file type {e}")
        win.status(f"Written to {p}: " + ", ".join(os.path.basename(f) for f in files))
    except Exception as ex:  # noqa: BLE001
        win.status(f"Export: {ex}")


def _plain(T, text=False):
    T = T.copy()
    for c in T.columns:
        if T[c].dtype == bool:
            T[c] = T[c].astype(int)
        elif text and pd.api.types.is_datetime64_any_dtype(T[c].dtype):
            T[c] = T[c].dt.strftime("%Y-%m-%d %H:%M:%S.%f").str[:-3]
    return T


def export_plot_data(win, which):
    if which == "overview":
        win.status("The overview can only be saved as a picture.")
        return
    S, C, B, H = win.S, win.C, win.B, win.H
    if S is None or C is None:
        win.status("Load a time window first.")
        return
    xl = win.pMain.vb.viewRange()[0]
    file = ask_file(win, "data", which)
    if not file:
        return
    clk = (lambda t: datenum_to_timestamps(H.recordingStart + np.asarray(t, float) / 86400)) \
        if not math.isnan(H.recordingStart) else None
    names, tabs = [], []
    if which == "force":
        I = (C.t >= xl[0]) & (C.t <= xl[1])
        t = C.t[I]
        f = C.f[I]
        z, _, _, _ = zero_force(S, win.ch, win.zero_of(), t)
        T = pd.DataFrame({"t_file_s": t})
        if win.rel_time:
            T["t_window_s"] = t - S.fromSeconds
        if not np.any(np.isnan(z)):
            T["force_minus_zero_uN"] = f - z
        else:
            T["force_signal_uN"] = f
        if C.get("rockerArtifact") is not None:
            T["rockerArtifactSubtracted_uN"] = C.rockerArtifact[I]
        if len(T) > 1048000 and file.lower().endswith(".xlsx"):
            win.status(f"{len(T)} rows: too many for Excel. Zoom in or export as .csv / .txt.")
            return
        names.append("signal")
        tabs.append(T)
        if B is not None and len(B):
            tp = B["t_peak"].to_numpy()
            J = np.flatnonzero((tp >= xl[0]) & (tp <= xl[1]))
            pk = {v: i for i, v in enumerate(C.peakTimes)}
            y = np.array([C.f[C.iPeaks[pk[x]]] for x in tp[J]])
            zz, _, _, _ = zero_force(S, win.ch, win.zero_of(), tp[J])
            if not np.any(np.isnan(zz)):
                y = y - zz
            inR = win.in_range()
            man = win.is_manual()
            sel = win.selected()
            inc = B["included"].to_numpy(bool)
            st = np.array(["outside the analysed range"] * J.size, dtype=object)
            st[inR[J] & ~inc[J]] = "excluded by filter"
            st[inR[J] & man[J]] = "excluded by user"
            st[sel[J]] = "selected"
            Tc = pd.DataFrame({"t_peak_s": tp[J], "peak_force_uN": y, "beatType": B["beatType"].to_numpy()[J],
                               "status": st})
            if clk is not None:
                Tc["clockTime"] = clk(tp[J])
            names.append("contractions")
            tabs.append(Tc)
        ts = C.stimTimes[(C.stimTimes >= xl[0]) & (C.stimTimes <= xl[1])]
        names.append("stimuli")
        tabs.append(pd.DataFrame({"t_stim_s": ts}))
        if win.LE is not None and len(win.LE):
            E = win.LE
            cm = E["isComment"].to_numpy() & (E["t_file"].to_numpy() >= xl[0]) & (E["t_file"].to_numpy() <= xl[1])
            if cm.any():
                names.append("comments")
                tabs.append(pd.DataFrame({"t_file_s": E["t_file"].to_numpy()[cm], "clockTime": E["clockTime"][cm].to_numpy(),
                                          "comment": E["text"].to_numpy()[cm]}))
    elif which == "stimuli":
        tS, cur, ok, ex, iv = win.stim_data()
        I = (tS >= xl[0]) & (tS <= xl[1])
        if C.stimChannel == 0:  # external trigger pulses: no current
            cur = np.full(cur.size, np.nan)
        T = pd.DataFrame({"t_file_s": tS[I], "current_mA": cur[I], "currentReached": ok[I], "extraPulse": ex[I],
                          "intervalToPreviousPulse_ms": iv[I]})
        if win.rel_time:
            T["t_window_s"] = T["t_file_s"] - S.fromSeconds
        if clk is not None:
            T["clockTime"] = clk(T["t_file_s"].to_numpy())
        names.append("stimuli_extTrigger" if C.stimChannel == 0 else f"stimuli_ch{C.stimChannel}")
        tabs.append(T)
    elif which == "parameter":
        if B is None:
            win.status("No contractions.")
            return
        nm, unit = win.plot_list[win.cPar.currentIndex()]
        if nm not in B.columns:
            win.status("No values for this parameter (reference beat / EP recording).")
            return
        v = B[nm].to_numpy(float)
        sel = win.selected()
        tp = B["t_peak"].to_numpy()
        J = (tp >= xl[0]) & (tp <= xl[1])
        vn = f"{nm}_{unit.replace('/', '_per_').replace('*', 'x').replace('%', 'pct').replace(' ', '_').replace(',', '')}"
        T = pd.DataFrame({"t_peak_s": tp[J], vn: v[J], "selected": sel[J]})
        if win.rel_time:
            T["t_window_s"] = T["t_peak_s"] - S.fromSeconds
        if clk is not None:
            T["clockTime"] = clk(T["t_peak_s"].to_numpy())
        names.append(nm)
        tabs.append(T)
    write_tables(win, file, names, tabs)


# ----------------------------------------------------------------------------------------------- comments
class CommentsWindow(QtWidgets.QWidget):
    """searchable list of the comments (or all entries) of the log file; double-click / Go to loads the data."""

    def __init__(self, win):
        super().__init__()
        self.win = win
        self.setWindowFlag(QtCore.Qt.WindowType.Window)
        self.resize(950, 520)
        g = QtWidgets.QGridLayout(self)
        g.addWidget(QtWidgets.QLabel("Search:"), 0, 0)
        self.ef = QtWidgets.QLineEdit()
        self.ef.setPlaceholderText("text (several words: all must occur)")
        self.ef.textChanged.connect(self.filter)
        g.addWidget(self.ef, 0, 1)
        self.cb = QtWidgets.QCheckBox("all log entries (events, settings)")
        self.cb.toggled.connect(self.filter)
        g.addWidget(self.cb, 0, 2)
        self.lbl = QtWidgets.QLabel("")
        g.addWidget(self.lbl, 0, 3)
        b = QtWidgets.QPushButton("Go to")
        b.clicked.connect(lambda: self.goto())
        g.addWidget(b, 0, 4)
        self.ut = QtWidgets.QTableWidget(0, 6)
        self.ut.setHorizontalHeaderLabels(["date / time", "time in file", "t (s)", "ch", "code", "text"])
        self.ut.verticalHeader().setVisible(False)
        self.ut.setEditTriggers(QtWidgets.QAbstractItemView.EditTrigger.NoEditTriggers)
        self.ut.setSelectionBehavior(QtWidgets.QAbstractItemView.SelectionBehavior.SelectRows)
        self.ut.horizontalHeader().setStretchLastSection(True)
        for k, w in enumerate((140, 80, 80, 35, 110)):
            self.ut.setColumnWidth(k, w)
        self.ut.cellDoubleClicked.connect(lambda r, c: self.goto(r))
        g.addWidget(self.ut, 1, 0, 1, 5)
        hint = QtWidgets.QLabel("Double-click a row (or select it and press Go to): loads the data around it (window "
                                "length = loaded window, at least 30 s). Comments are marked purple in the plots.")
        hint.setStyleSheet("color: #4d4d4d")
        g.addWidget(hint, 2, 0, 1, 5)
        self.view = []

    def refresh_file(self):
        if self.win.H is not None:
            self.setWindowTitle("Comments - " + os.path.basename(self.win.H.file))
        self.filter()

    def filter(self, *_):
        E = self.win.LE
        self.view = []
        if E is None or len(E) == 0:
            self.ut.setRowCount(0)
            self.lbl.setText("no log file")
            return
        m = E["isComment"].to_numpy().copy()
        if self.cb.isChecked():
            m[:] = True
        words = [w for w in self.ef.text().lower().split() if w]
        if words:
            hay = (E["text"].astype(str) + " " + E["code"].astype(str)).str.lower().to_numpy()
            for w in words:
                m &= np.array([w in h for h in hay])
        self.view = list(np.flatnonzero(m))
        hrs = self.win.H.totalSeconds >= 3600
        self.ut.setRowCount(len(self.view))
        for r, j in enumerate(self.view):
            ct = E["clockTime"].iloc[j]
            vals = ["" if pd.isna(ct) else pd.Timestamp(ct).strftime("%Y-%m-%d %H:%M:%S"),
                    fmt_clock(E["t_file"].iloc[j], hrs, True), f"{round(E['t_file'].iloc[j] * 10) / 10:g}",
                    f"{E['channel'].iloc[j]:g}", str(E["code"].iloc[j]), str(E["text"].iloc[j])]
            for c, v in enumerate(vals):
                self.ut.setItem(r, c, QtWidgets.QTableWidgetItem(v))
        what = "entries" if self.cb.isChecked() else "comments"
        tot = len(E) if self.cb.isChecked() else int(E["isComment"].sum())
        self.lbl.setText(f"{len(self.view)} of {tot} {what}")

    def goto(self, r=None):
        if r is None:
            r = self.ut.currentRow()
        if r is None or r < 0 or r >= len(self.view):
            self.lbl.setText("select a row first")
            return
        E = self.win.LE
        j = self.view[r]
        ct = E["clockTime"].iloc[j]
        self.win.goto_time(float(E["t_file"].iloc[j]), str(E["text"].iloc[j]),
                           "" if pd.isna(ct) else pd.Timestamp(ct).strftime("%Y-%m-%d %H:%M:%S"))


# ----------------------------------------------------------------------------------------------- labels
class LabelsDialog(QtWidgets.QWidget):
    """editable table of the labels per channel (metadata); load / save as .csv (<name>_labels.csv)."""

    def __init__(self, win):
        super().__init__()
        self.win = win
        self.setWindowFlag(QtCore.Qt.WindowType.Window)
        self.setWindowTitle("Labels per channel (metadata)")
        self.resize(1300, 360)
        v = QtWidgets.QVBoxLayout(self)
        self.ut = QtWidgets.QTableWidget()
        self.ut.verticalHeader().setVisible(False)
        v.addWidget(self.ut, 1)
        h = QtWidgets.QHBoxLayout()
        for text, cb in (("Apply and close", lambda: self.apply(True)), ("Apply", lambda: self.apply(False)),
                         ("Fill empty cells from first row", self.fill_down), ("Load ...", self.load),
                         ("Save ...", self.save)):
            b = QtWidgets.QPushButton(text)
            b.clicked.connect(cb)
            h.addWidget(b)
        t = QtWidgets.QLabel("cultureStart, e.g. 1999-12-24 14:30: daysInCulture is then calculated for every "
                             "contraction. analyst: your initials. Saved as <name>_labels.csv next to the .mdd file, the "
                             "file is loaded automatically next time.")
        t.setWordWrap(True)
        h.addWidget(t, 1)
        v.addLayout(h)
        self.show_labels(win.Lbl)

    def show_labels(self, L):
        self.ut.clear()
        self.ut.setColumnCount(len(L.columns))
        self.ut.setRowCount(len(L))
        self.ut.setHorizontalHeaderLabels(list(L.columns))
        self.num = [pd.api.types.is_numeric_dtype(L[c]) for c in L.columns]
        for r in range(len(L)):
            for c, nm in enumerate(L.columns):
                v = L[nm].iloc[r]
                s = "" if (isinstance(v, float) and math.isnan(v)) else (f"{v:g}" if isinstance(v, (int, float)) else str(v))
                it = QtWidgets.QTableWidgetItem(s)
                if nm == "channel":
                    it.setFlags(it.flags() & ~QtCore.Qt.ItemFlag.ItemIsEditable)
                self.ut.setItem(r, c, it)
        self.ut.resizeColumnsToContents()
        for c in range(1, self.ut.columnCount()):
            self.ut.setColumnWidth(c, max(85, self.ut.columnWidth(c)))

    def table(self):
        names = [self.ut.horizontalHeaderItem(c).text() for c in range(self.ut.columnCount())]
        d = {}
        for c, nm in enumerate(names):
            vals = [self.ut.item(r, c).text() if self.ut.item(r, c) else "" for r in range(self.ut.rowCount())]
            if nm == "channel" or (c < len(self.num) and self.num[c]):
                d[nm] = pd.to_numeric(pd.Series(vals).str.replace(",", ".").replace("", np.nan), errors="coerce")
            else:
                d[nm] = vals
        T = pd.DataFrame(d)
        return make_labels(T, self.win.H.dataChannels)

    def apply(self, close):
        try:
            L = self.table()
        except Exception as e:  # noqa: BLE001
            self.win.status(f"Labels: {e}")
            return
        self.win.labels_applied(L)
        if close:
            self.close()
            self.win.win_labels = None
        else:
            self.show_labels(L)

    def fill_down(self):
        for c in range(1, self.ut.columnCount()):
            first = self.ut.item(0, c).text() if self.ut.item(0, c) else ""
            for r in range(1, self.ut.rowCount()):
                it = self.ut.item(r, c)
                if it is None or not it.text().strip():
                    self.ut.setItem(r, c, QtWidgets.QTableWidgetItem(first))

    def load(self):
        p = os.path.dirname(self.win.H.file)
        fn, _ = QtWidgets.QFileDialog.getOpenFileName(self, "Load labels", p, "labels (*.csv *.xlsx)")
        if not fn:
            return
        try:
            self.show_labels(make_labels(fn, self.win.H.dataChannels))
        except Exception as e:  # noqa: BLE001
            self.win.status(f"Labels: {e}")

    def save(self):
        try:
            L = self.table()
        except Exception as e:  # noqa: BLE001
            self.win.status(f"Labels: {e}")
            return
        d = os.path.splitext(self.win.H.file)[0] + "_labels.csv"
        fn, _ = QtWidgets.QFileDialog.getSaveFileName(self, "Save labels", d, "labels (*.csv)")
        if not fn:
            return
        try:
            L.to_csv(fn, index=False)
            self.win.labels_applied(L)
            self.win.status("Labels saved: " + fn)
        except Exception as e:  # noqa: BLE001
            self.win.status(f"Labels not saved: {e}")


# ----------------------------------------------------------------------------------------------- table
class TableWindow(QtWidgets.QWidget):
    def __init__(self, T, title, parent=None):
        super().__init__()
        self.setWindowFlag(QtCore.Qt.WindowType.Window)
        self.setWindowTitle(title)
        self.resize(1200, 600)
        v = QtWidgets.QVBoxLayout(self)
        tw = QtWidgets.QTableWidget(len(T), len(T.columns))
        tw.setHorizontalHeaderLabels([str(c) for c in T.columns])
        tw.setEditTriggers(QtWidgets.QAbstractItemView.EditTrigger.NoEditTriggers)
        for c, nm in enumerate(T.columns):
            col = T[nm]
            for r in range(len(T)):
                v_ = col.iloc[r]
                if isinstance(v_, (float, np.floating)):
                    s = "NaN" if math.isnan(v_) else f"{v_:.6g}"
                elif isinstance(v_, pd.Timestamp):
                    s = v_.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
                else:
                    s = str(v_)
                tw.setItem(r, c, QtWidgets.QTableWidgetItem(s))
        v.addWidget(tw)
        self._keep = parent
        if parent is not None:
            parent._tables = getattr(parent, "_tables", []) + [self]


# ----------------------------------------------------------------------------------------------- advanced settings
# rows (advanced.py, as advancedDefs in MyoDishAnalysisGUI.m): option name, label, kind ('popup', 'check', 'num',
# 'int', 'numauto', 'vec'), popup items [(label, value)], description, scale (shown value = option value x scale),
# unit, tab, reread (the window is read again)


def _adv_default_text(row, d0):
    name, _, kind, items, _, scale, unit, _, reread = row
    v = d0[name]
    unit = unit.replace("uN", "µN")
    if kind == "popup":
        t = "default: " + next(lb for lb, val in items if val == v)
    elif kind == "check":
        t = "default: on" if v else "default: off"
    elif kind == "numauto":
        t = "s (default: auto)" if isinstance(v, str) else f"s (default: {v:g})"
    elif kind == "vec":
        t = f"{unit} (default: {' '.join(f'{x * scale:g}' for x in v)})".strip()
    else:
        t = f"{unit} (default: {float(v) * scale:g})".strip()
    return t + (" *" if reread else "")


def settings_guide_file():
    """settings guide (PDF): docs/ of the repository (next to the MATLAB code) or of the package"""
    here = os.path.dirname(os.path.abspath(__file__))
    nm = "MyoDishAnalysis_settings_guide.pdf"
    for d in (os.path.join(here, "..", "docs"), os.path.join(here, "..", "..", "..", "..", "docs")):
        f = os.path.normpath(os.path.join(d, nm))
        if os.path.isfile(f):
            return f
    return ""


class AdvancedSettings(QtWidgets.QWidget):
    """advanced settings (2026-10-10): all parameters of the method that are based on assumptions or experience
    (options.py), one tab per part of the analysis; meaning: tooltips and the settings guide (button Guide).
    Defaults = options(); Apply / OK analyse the window again (* = the window is read again). Save settings ... /
    Load settings ...: settings file (settings.py; results of an analysis can be loaded as well)."""

    def __init__(self, win):
        from ..options import options as make_options
        super().__init__(win)  # owned by the main window (closed with it)
        self.win = win
        self.pending = {}  # settings of the main window loaded from a file (applied at Apply / OK)
        self.setWindowFlag(QtCore.Qt.WindowType.Window)
        self.setWindowTitle("MyoDishAnalysis - advanced settings")
        v = QtWidgets.QVBoxLayout(self)
        self.tabs = QtWidgets.QTabWidget()
        self.ctl = {}
        d0 = make_options()
        for tab in ADVANCED_TABS:
            page = QtWidgets.QWidget()
            g = QtWidgets.QGridLayout(page)
            g.setVerticalSpacing(3)
            r = 0
            for row in ADVANCED_ROWS:
                name, label, kind, items, tip, scale, unit, tb, reread = row
                if tb != tab:
                    continue
                if reread:
                    tip += " (the window is read again)"
                lb = QtWidgets.QLabel(label)
                lb.setToolTip(tip)
                g.addWidget(lb, r, 0)
                if kind == "popup":
                    w = QtWidgets.QComboBox()
                    w.addItems([it[0] for it in items])
                elif kind == "check":
                    w = QtWidgets.QCheckBox("")
                else:
                    w = QtWidgets.QLineEdit("")
                    w.setMaximumWidth(120 if kind == "vec" else 90)
                w.setToolTip(tip)
                g.addWidget(w, r, 1)
                d = QtWidgets.QLabel(_adv_default_text(row, d0))
                d.setStyleSheet("color: #666666")
                d.setToolTip(tip)
                g.addWidget(d, r, 2)
                self.ctl[name] = w
                r += 1
            g.setRowStretch(r, 1)
            g.setColumnStretch(2, 1)
            self.tabs.addTab(page, tab)
        v.addWidget(self.tabs)
        self.lMsg = QtWidgets.QLabel("Hover over a name for its meaning; Guide: settings guide with figures. Apply or OK "
                                     "analyses the loaded window again (* = the window is read again). Settings are "
                                     "saved with every export and can be loaded from a settings file or from results.")
        self.lMsg.setWordWrap(True)
        self.lMsg.setStyleSheet("color: #000099")
        v.addWidget(self.lMsg)
        h = QtWidgets.QHBoxLayout()
        for text, cb, tip in (
                ("Defaults", self.defaults, "show the default values (options()); Apply or OK uses them"),
                ("Load settings ...", self.load, "settings file (Save settings ...) or results of an analysis (.xlsx, "
                 "_info.csv): all settings except the threshold and zero force of the channels; Apply or OK uses them"),
                ("Save settings ...", self.save, "all settings as shown (with the rocker filter, detection and filters "
                 "of the main window) as a settings file (.csv): options(settings=file), mda-analyze --settings file"),
                ("Guide", self.guide, "settings guide (PDF): the parameters and the markers of the force plot with "
                 "figures")):
            b = QtWidgets.QPushButton(text)
            b.setToolTip(tip)
            b.clicked.connect(cb)
            h.addWidget(b)
        h.addStretch(1)
        for text, cb in (("Cancel", self.close), ("Apply", lambda: self.apply(False)), ("OK", lambda: self.apply(True))):
            b = QtWidgets.QPushButton(text)
            b.clicked.connect(cb)
            h.addWidget(b)
        v.addLayout(h)
        self.resize(820, 680)
        self.show_options(win.opts)

    def defaults(self):
        from ..options import options as make_options
        self.show_options(make_options())

    def show_options(self, o):
        for name, _, kind, items, _, scale, _, _, _ in ADVANCED_ROWS:
            w = self.ctl[name]
            v = o[name]
            if kind == "popup":
                vals = [it[1] for it in items]
                w.setCurrentIndex(vals.index(v) if v in vals else 0)
            elif kind == "check":
                w.setChecked(bool(v))
            elif kind == "numauto":
                w.setText("auto" if isinstance(v, str) or v is None else f"{v:g}")
            elif kind == "vec":
                w.setText(" ".join(f"{float(x) * scale:g}" for x in np.asarray(v, float).ravel()))
            else:
                w.setText(f"{float(v) * scale:g}")

    def read(self):
        """options from the controls (and the settings loaded for the main window), checked; (options, error)"""
        from ..options import options as make_options
        o = dict(self.win.opts)
        o.update(self.pending)
        for name, label, kind, items, _, scale, _, _, _ in ADVANCED_ROWS:
            w = self.ctl[name]
            if kind == "popup":
                o[name] = items[w.currentIndex()][1]
            elif kind == "check":
                o[name] = w.isChecked()
            elif kind == "numauto":
                t = w.text().strip()
                if not t or t.lower() == "auto":
                    o[name] = "auto"
                else:
                    try:
                        o[name] = float(t)
                    except ValueError:
                        return None, f"{label}: a number or auto."
            elif kind == "vec":
                try:
                    o[name] = tuple(float(x) / scale for x in w.text().replace(",", " ").split())
                except ValueError:
                    return None, f"{label}: numbers separated by spaces."
            else:
                try:
                    x = float(w.text().strip()) / scale
                except ValueError:
                    return None, f"{label}: enter a number."
                o[name] = int(x) if name in ("medianFilterMs", "meanFilterMs") and x == int(x) else x
        try:
            return make_options(o), ""
        except ValueError as e:
            return None, str(e)

    def apply(self, close_it):
        """options from the controls: checked (options()), then the window is analysed again"""
        o, err = self.read()
        if o is None:
            self.lMsg.setText(err)
            return False
        msg = self.win.apply_advanced(o)
        self.pending = {}
        if close_it:
            self.close()  # hidden, reused by the next Advanced ...
        else:
            self.show_options(self.win.opts)
            self.lMsg.setText(msg)
        return True

    def save(self):
        """all settings as shown -> settings file (settings.py)"""
        from ..settings import save_settings
        o, err = self.read()
        if o is None:
            self.lMsg.setText(err)
            return ""
        if self.win.next_file:
            fn, self.win.next_file = self.win.next_file, ""
        else:
            d = self.win.last_dir or (os.path.dirname(self.win.H.file) if self.win.H is not None else "")
            fn, _ = QtWidgets.QFileDialog.getSaveFileName(self, "Save settings",
                                                          os.path.join(d, "MyoDishAnalysis_settings.csv"),
                                                          "settings (*.csv)")
            if not fn:
                return ""
        try:
            fn = save_settings(fn, o)
            self.lMsg.setText(f"Settings saved: {fn} (all options as shown; Apply or OK uses them here).")
        except OSError as e:
            self.lMsg.setText(f"Settings not saved: {e}")
            return ""
        return fn

    def load(self):
        """settings file or results -> controls (and the settings of the main window at Apply / OK)"""
        from ..settings import load_settings
        if self.win.next_file:
            fn, self.win.next_file = self.win.next_file, ""
        else:
            d = self.win.last_dir or (os.path.dirname(self.win.H.file) if self.win.H is not None else "")
            fn, _ = QtWidgets.QFileDialog.getOpenFileName(self, "Load settings", d,
                                                          "settings or results (*.csv *.xlsx)")
            if not fn:
                return False
        try:
            o, notes = load_settings(fn, notes=True)
        except (OSError, ValueError, KeyError) as e:
            self.lMsg.setText(f"Settings not loaded: {e}")
            return False
        names = {r[0] for r in ADVANCED_ROWS} | {"threshold", "zeroForce", "referenceBeat"}
        self.pending = {k: v for k, v in o.items() if k not in names}
        self.show_options(o)
        msg = (f"Loaded {os.path.basename(fn)}: Apply or OK uses these settings (with rocker filter "
               f"{bool(o.rockerFilter)}, {o.detection}, rocker {o.rocker}, beats {o.beats}).")
        if notes:
            msg += " " + " ".join(notes)
        self.lMsg.setText(msg)
        return True

    def guide(self):
        f = settings_guide_file()
        if not f:
            self.lMsg.setText("Settings guide not found (docs/MyoDishAnalysis_settings_guide.pdf of the repository).")
            return
        QtGui.QDesktopServices.openUrl(QtCore.QUrl.fromLocalFile(f))


# ----------------------------------------------------------------------------------------------- help
class RockerArtifactWindow(QtWidgets.QMainWindow):
    """rocker artifact (2026-10-09): signal of the loaded window before and after the rocker filter and the subtracted
    periodic artifact of the selected channel; menu: save as figure, export the data of the visible time range with the
    result of the filter and the settings (table info)."""

    def __init__(self, win, msg):
        super().__init__(win)
        self.win = win
        S, ch = win.S, win.ch
        E = win.rf_cache[ch]
        self.R = E["R"]
        self.ch = ch
        row = [int(c) for c in S.dataChannels].index(ch)
        self.t = np.asarray(S.t, float)
        self.before = np.asarray(S.force[row], float).copy()
        self.art = np.asarray(E["art"], float).ravel()
        self.after = self.before - self.art
        z = zero_force(S, ch, win.zero_of(), self.t)[0]
        self.has_z = not np.any(np.isnan(z))
        if self.has_z:
            self.before -= z
            self.after -= z
        self.rocker = np.asarray(S.rockerOn, bool).ravel()
        self.tx = self.t - S.fromSeconds if win.rel_time else self.t
        self.setWindowTitle(f"Rocker artifact - channel {ch}")
        self.resize(1100, 560)
        self.gw = pg.GraphicsLayoutWidget()
        self.gw.setBackground("w")
        self.setCentralWidget(self.gw)
        mu = "\u00b5"
        self.p1 = self.gw.addPlot(row=0, col=0)
        self.p2 = self.gw.addPlot(row=1, col=0)
        self.p2.setXLink(self.p1)
        for p in (self.p1, self.p2):
            p.getAxis("left").setWidth(78)  # tick labels and axis label side by side
        name = os.path.basename(win.H.file)
        self.p1.setTitle(f"{name}, channel {ch} (200 Hz signal before the median / mean filters)", size="9pt")
        self.p2.setTitle(msg, size="9pt")
        yu = f"force - zero force ({mu}N)" if self.has_z else f"force ({mu}N, sensor signal)"
        self.p1.setLabel("left", yu)
        self.p2.setLabel("left", f"rocker artifact ({mu}N)")
        self.p2.setLabel("bottom", "time in the window (s)" if win.rel_time else "time in file (s)")
        a, b = runs(self.rocker)
        for p, y in ((self.p1, np.r_[self.before, self.after]), (self.p2, self.art)):
            yl = [float(np.nanmin(y)), float(np.nanmax(y))] if y.size else [0.0, 1.0]
            if yl[1] <= yl[0]:
                yl = [yl[0] - 1, yl[1] + 1]
            d = yl[1] - yl[0]
            yl = [yl[0] - 0.05 * d, yl[1] + 0.05 * d]
            if a.size:
                it = pg.BarGraphItem(x0=self.tx[a], x1=self.tx[b], y0=np.full(a.size, yl[0]),
                                     height=np.full(a.size, yl[1] - yl[0]), brush=pg.mkBrush(140, 140, 140, 50),
                                     pen=pg.mkPen(None))
                it.setZValue(-10)
                p.addItem(it)
            p.setYRange(yl[0], yl[1], padding=0)
            p.showGrid(x=False, y=False)
        self.p1.addLegend(offset=(-10, 10))
        c1 = self.p1.plot(self.tx, self.before, pen=pg.mkPen((179, 179, 179), width=1), name="before the rocker filter")
        c2 = self.p1.plot(self.tx, self.after, pen=pg.mkPen("k", width=1), name="after (analysed)")
        c3 = self.p2.plot(self.tx, self.art, pen=pg.mkPen((0, 77, 255), width=1))
        for c in (c1, c2, c3):
            c.setDownsampling(auto=True, method="peak")
            c.setClipToView(True)
        if self.tx.size:
            self.p1.setXRange(self.tx[0], self.tx[-1], padding=0)
        m = self.menuBar().addMenu("Save / Export")
        m.addAction("Save figure (.png / .jpg / .tif / .pdf) ...", self.save_figure)
        m.addAction("Export data of the visible time range (.xlsx / .csv / .txt) ...", self.export_data)

    def save_figure(self):
        file = ask_file(self.win, "image", "rockerArtifact")
        if not file:
            return
        try:
            render_scene(self.gw.scene(), QtCore.QRectF(0, 0, self.gw.width(), self.gw.height()), file)
            self.win.status("Saved: " + file)
        except Exception as e:  # noqa: BLE001
            self.win.status(f"Save: {e}")

    def export_tables(self):
        xl = self.p2.vb.viewRange()[0]
        I = (self.tx >= xl[0]) & (self.tx <= xl[1])
        T = pd.DataFrame({"t_file_s": self.t[I]})
        if self.win.rel_time:
            T["t_window_s"] = self.tx[I]
        H = self.win.H
        if not math.isnan(H.recordingStart):
            T["clockTime"] = datenum_to_timestamps(H.recordingStart + self.t[I] / 86400.0)
        nm = "force_minus_zero" if self.has_z else "force_signal"
        T[nm + "_before_uN"] = self.before[I]
        T["rockerArtifact_uN"] = self.art[I]
        T[nm + "_after_uN"] = self.after[I]
        T["rockerMoving"] = self.rocker[I]
        R = self.R
        Tr = pd.DataFrame([[self.ch, R.status, R.f0, R.artifactPP, R.r2, 100 * R.correctedFraction, R.message]],
                          columns=["channel", "status", "rockerFrequency_Hz", "artifact_uN_peakToPeak", "artifactR2",
                                   "corrected_percentOfRockerOnTime", "message"])
        return ["rockerArtifact", "rockerFilter"], [T, Tr]

    def export_data(self):
        file = ask_file(self.win, "data", "rockerArtifact")
        if not file:
            return
        names, tabs = self.export_tables()
        if len(tabs[0]) > 1048000 and file.lower().endswith(".xlsx"):
            self.win.status(f"{len(tabs[0])} rows: too many for Excel. Zoom in or export as .csv / .txt.")
            return
        write_tables(self.win, file, names, tabs)


def help_text():
    P = PARAMETERS
    lines = [
        "Comments ...: searchable list of the comments in the log file (date / time, time in the file, text; option: "
        "all log entries). Double-click a row (or Go to) to load the data around it. Comments are marked purple in the "
        "plots.", "",
        "Overview: min/max of the selected channel over the whole recording (green = rocker at rest). Drag in it to "
        "load a time window (or type From/To and press Load). Mouse wheel: zoom (shift + wheel: move), double-click: "
        "whole file; the zoomed part is re-read in more detail.", "",
        "Force plot: red = selected contractions, orange = uncertain contractions (high sensitivity: neither locked to "
        "the stimuli nor large compared with the other contractions; not counted with high specificity), grey = "
        "excluded by the filters (rocker / stimulated only), x = "
        "excluded by you, blue ticks = stimuli, green ticks = extra pulses (status channel bit 16: pre-pulses, CCM "
        "pulses, ...), green rings = contractions elicited by an extra pulse, black diamonds = ambiguous stimulus "
        "assignment, grey background = rocker moving, yellow = analysed range.",
        "Advanced ...: all parameters of the method that are based on assumptions or experience, one tab per part "
        "(stimulus assignment / onset gate, detection, noise and artifact rules, rocker rules, signal and spike removal, "
        "rocker filter, export). Hover over a name for its meaning; Guide = settings guide (PDF) with figures; Defaults "
        "= options(); Apply / OK analyse the window again (* = the window is read again). Save settings ... / Load "
        "settings ...: settings file (.csv; also results of an analysis); the settings are saved with every export "
        "(info table).",
        "Legend of the force plot: menu View or right click in the force plot (it can be dragged).",
        "Cursor in the force plot: \"drag = select time range\" or \"click = exclude / include contraction\". Mouse "
        "wheel: zoom the time axis (shift + wheel: move); double-click: whole loaded window. Right click: zero force, "
        "reference beat, save / export.",
        "Arrow keys and the buttons under the force plot change the loaded window (= blue selection in the overview and "
        "analysed range; read again): left / right = move it by half its length, shift + left / right (shift + click) "
        "= extend it by half its length on that side, up / down (middle buttons) = zoom in / out (half / twice its "
        "length). Mouse pointer over the overview: the keys move its time axis instead; a zoomed overview moves "
        "along. The mouse wheel zooms only the display.",
        "Mouse pointer over the force, stimulus, parameter or EP plots: a dashed line and a marker show the value at "
        "that time in every plot (force; stimulus pulse nearest to it: current and interval; lower plot: parameter of "
        "the nearest contraction; EP signal and stimulation). The plot under the pointer also shows the time and the "
        "time since the last stimulus.", "",
        "Overlay contractions: selected contractions + mean, aligned at the stimulus (t = 0, default) or the peak, or "
        "the time course of the analysed range (t = 0 at the first stimulus of each group). Press again (or Add "
        "current selection in the overlay window) to add another selection as a new group; Channels (same range) ...: "
        "tick "
        "channels to add them for the analysed range (same settings, threshold and zero force of each channel). Per "
        "group (list): legend text, colour, line width, line style and a transparent band (mean +- SD, +- SEM or "
        "range). Title, axis labels and legend position are editable below the plot (empty = automatic); Edit figure "
        "... opens a copy as a matplotlib figure (toolbar: edit axes, curves and legend; save as .png / .pdf / .svg).",
        "",
        "Trend ...: rolling mean / median of a parameter over long periods and several files in a row (_0, _1, ...); "
        "sampling: all contractions, short windows or rocker stops. Channel list: one channel, or several channels ... "
        "(checkboxes) = overlaid, one colour per channel (the file is read once for all of them).", "",
        "Save / Export (menu or right click on a plot): plots as .png / .jpg / .tif (300 dpi) / .pdf, plotted data "
        "(visible time range) as .xlsx / .csv / .txt; overview: picture only. Every data export contains the table info "
        "(version, recording, all settings, threshold and zero force of the channel, window and range).", "",
        "Open results ...: a results file of MyoDishAnalysis, the watcher or an export of the GUI (.xlsx, "
        "<name>_info.csv, _summary.csv, _contractions.csv): the recording (path in the file; otherwise next to the "
        "results file or asked for), the settings and the analysis window (channel, data window, analysed range; "
        "several: list) are restored, the contractions are detected again and compared with the file (status line; "
        "black o = contraction of the file not found again, e.g. other version). Contractions excluded by you in an "
        "export are excluded again.", "",
        "Labels ...: labels per channel (setupID, sliceID, species, sampleID, sampleGroup, sliceGroup, tissue, "
        "treatment, concentration, concentrationUnit, daysInCulture, cultureStart, comment, analyst) - columns of the "
        "exported tables; saved as <name>_labels.csv next to the .mdd file and loaded automatically.", "",
        "Detection: peaks with a prominence >= threshold (auto: 0.3 x typical amplitude, >= 30 uN; per channel: auto "
        "or a manual value, kept when you switch channels and used for All channels, Protocols and Trend). Stimuli "
        "(list next to \"only stimulated contractions\"): the MyoDish pulses of the channel, or the external trigger "
        "pulses of the status channel (external stimulator at the external controller unit, which carries one chamber: "
        "any data channel); auto = external trigger pulses if the loaded window has no MyoDish pulses. A "
        "contraction within 25 ms ... min(stimulus interval, 1 s) after a stimulus of the channel is \"stimulated\", "
        "otherwise \"extra\".", "",
        "Reference beat (right click in the force plot): the mean shape (+- SD) of the selected contractions becomes "
        "the reference of the channel. Every contraction is compared with it, aligned at the stimulus (default; a "
        "changed latency counts, contractions without stimulus at the 50 % upstroke) or at the 50 % upstroke (shape "
        "only): refCorrelation, refRMSDeviation_SD and refMaxDeviation_SD in SD of the reference, each also normalized "
        "(...Norm: both scaled to amplitude 1). Deviating contractions (> x SD) are circled magenta, counted in the "
        "table and can be excluded (reference window). Save/load a reference (.mat, compatible with MATLAB) to apply "
        "it to other files. Every parameter is also given relative to the mean of the reference contractions (column "
        "%ref; <parameter>_pctRef; diastolic force: difference in uN, _dRef).", "",
        "+ EP recording ...: LabChart export (.mat) of an electrophysiological recording made in parallel, e.g. sharp "
        "electrode (voltage + stimulation channel). It is aligned to the stimuli of the .mdd file (stimulus pattern; on "
        "constant pacing also stimulus current and clock times; clock drift corrected) and shown below the plots. Check "
        "the alignment if marked CHECK. With an EP recording every contraction gets AP parameters (AP_dVdtMax, AP_RMP, "
        "AP_Vmax, APD25/50/90, AP_note).",
        "EP plots: drag up / down = y limits of that plot, double-click = automatic; right click: Set y limits ... / y "
        "limits: automatic (restore view). remove stimulus artefact: the stimulus pulses and the artefact after them "
        "(saturation, decay towards the RMP) are replaced by straight lines (grey) - display only, the AP parameters "
        "are measured on the recorded signal.", "",
        "Remove rocker artifact: the periodic signal of the rocker (60 rpm = 1.21 Hz) is estimated per channel between "
        "the contractions (+-60 s around the window) and subtracted; light grey = signal before. Not possible "
        "(message): rocker frequency not found, no periodic artifact, too little time between the contractions. Rocker "
        "artifact ... (button, menu Save / Export, right click in the force plot): extra window with the signal before "
        "/ after the filter and the removed artifact (also if the filter is off); menu: save as figure, export the "
        "data of the visible time range.", "",
        "Parameters:"]
    lines += [f"{n} ({u}): {d}" for n, u, d in P]
    lines += [f"{n} ({u}): {d}" for n, u, d in AP_PARAMETERS]
    return "\n".join(lines)
