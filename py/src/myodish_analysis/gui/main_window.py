"""Interactive contraction analysis of a MyoDish recording (.mdd). Port of MyoDishAnalysisGUI.m (PySide6 + pyqtgraph).

    mda-gui [file.mdd]            (or: python -m myodish_analysis.gui [file.mdd])

0. Comments ...: searchable list of the comments of the log file; double-click (or Go to) loads the data around it.
1. Overview: min/max envelope of the selected channel (green = rocker at rest). Drag = load a time window; mouse wheel
   = zoom (shift + wheel: move), double-click = whole file; the zoomed part is re-read in more detail.
   Arrow keys: left / right = move the time axis by half its length, shift + left / right = extend it on that side,
   up / down = zoom in / out; mouse over the overview: its time axis, otherwise the force plot (beyond the loaded
   window the loaded window follows and is read again; the zoomed overview moves along).
2. Force plot: force - zero force; red = selected contractions, orange = uncertain (high sensitivity), grey = excluded
   by the filters, x = excluded by you, blue ticks = stimuli, grey background = rocker moving, yellow = analysed range,
   purple = comments.
   Cursor mode 'drag = select time range' or 'click = exclude / include contraction'. Wheel = zoom the time axis,
   shift + wheel = move, double-click = whole loaded window. Right click: zero force, reference beat, save / export.
3. Stimulus plot (current per pulse, interval to the previous pulse), table (mean, SD, n of the selected contractions,
   extra / missed / uncertain beats) and lower plot (one parameter per contraction). Detection threshold per channel
   (auto or manual); 'high sensitivity' (default) counts all contractions and marks the uncertain ones (orange), 'high
   specificity' does not count them (option detection). Stimuli: MyoDish pulses or external trigger pulses (external stimulator at the external controller unit;
   auto = trigger pulses if the window has no MyoDish pulses). Overlay contractions: mean beat (stimulus / peak) or
   time course of the range (t = 0 at the first stimulus), other channels of the same range by checkboxes, colour /
   width / line style / SD-SEM-range band per group, editable title, axis labels and legend, editable matplotlib copy
   (overlay.py).
4. + EP recording ...: LabChart .mat export aligned to the stimuli; AP parameters per contraction.
5. Protocols ...: stimulation protocols found in the log file ('start ... protocol' / 'end ... protocol'): contractions
   grouped by pacing frequency, S2 interval, stimulus current, rest interval, pulse duration or rocker speed; summary
   per group, plot of a parameter against the quantity, export (protocols_window.py).
See README.md of the MATLAB version for all details; results are the same as with MyoDishAnalysisGUI.

Thomas Seidel (FAU Erlangen-Nuernberg / InVitroSys GmbH), 2026-10-06 (port of MyoDishAnalysisGUI.m; detection mode
2026-10-09)
"""
from __future__ import annotations

import datetime as _dt
import json
import math
import os
import re
import traceback

import numpy as np
import pandas as pd
import pyqtgraph as pg
from PySide6 import QtCore, QtGui, QtWidgets

from .. import reference_beat as rb
from .._matlab import Struct, mround, nanmean
from ..add_labels import add_labels
from ..analyze_ap import AP_PARAMETERS, analyze_ap
from ..analyze_channel import analyze_channel
from ..analysis import datenum_to_timestamps, myodish_analysis
from ..labels import labels as make_labels
from ..log_entries import log_entries
from ..options import options as make_options
from ..parameters import PARAMETERS
from ..read_ep_recording import read_ep_recording
from ..read_mdd import read_mdd
from ..rocker_filter import rocker_filter
from ..summarize import summarize
from ..write_results import write_results
from ..zero_force import zero_force
from .timeaxis import fmt_clock, fmt_duration, fmt_num, nav_step
from .widgets import (BLUE, GREEN, GREY, MAGENTA, ORANGE, PURPLE, RED, ElidedLabel, PlotArea, TwinPlot, rects, rot_labels, runs, set_title, time_plot,
                      vlines)

MU = "µ"


def _plot_list():
    L = [(p[0], p[1]) for p in PARAMETERS] + [("stimToPeak", "s"), ("prominence", "uN")]
    for p in PARAMETERS:
        if p[0].startswith("ref"):
            continue
        if p[0] in ("diastolicForce", "diastolicSignal"):
            L.append((p[0] + "_dRef", "uN, diff. to ref"))
        else:
            L.append((p[0] + "_pctRef", "% of ref"))
    L += [(p[0], p[1]) for p in AP_PARAMETERS]
    return L



def _shift_held():
    """shift key held (shift + click on the arrow buttons under the force plot)"""
    return bool(QtWidgets.QApplication.keyboardModifiers() & QtCore.Qt.KeyboardModifier.ShiftModifier)

class MainWindow(QtWidgets.QMainWindow):
    def __init__(self, mdd_file=None, metadata=None):
        super().__init__()
        self.setWindowTitle("MyoDishAnalysis")
        self.resize(1450, 880)
        # ---------------------------------------------------------------- state
        self.H = self.S = self.O = self.B = self.C = None
        self.ch = 1
        self.range = [math.nan, math.nan]
        self.manual_off = []                # t_peak of the contractions excluded by the user
        self.zero_user = {}                 # zero force per channel entered by the user (missing / NaN = log file)
        self.thr_user = {}                  # detection threshold per channel entered by the user (missing = auto)
        self.Lbl = None                     # labels per channel (DataFrame)
        self.rel_time = False
        self.LE = None                      # log entries
        self.hiT = math.nan                 # comment last jumped to
        self.opts = make_options()
        self.ref_thr = 3.0
        self.ref_which = 2                  # 1 absolute, 2 normalized, 3 either
        self.ref_exclude = False
        self.ref_align = "stimulus"
        self.EP = None
        self.ep_marks = None
        self.rf_ctx = None
        self.rf_cache = {}
        self.rf_f0 = None
        self.Od = None                      # detailed overview of a zoomed part
        self.ovXL = None                    # time axis of the overview (None = whole file)
        self.last_dir = ""
        self.alt_pt = (math.nan, math.nan)  # last right click in the force plot
        self.tr_cache = {}
        self.tr_chans, self.tr_multi = [], []  # trend: channels shown (several = overlaid), last set
        self.plot_list = _plot_list()
        self.win_overlay = self.win_trend = self.win_ref = self.win_comments = self.win_labels = None
        self.win_protocols = None
        self._drag_item = None
        self._stim_txt = []
        self._ov_timer = QtCore.QTimer(self)
        self._ov_timer.setSingleShot(True)
        self._ov_timer.timeout.connect(self._load_detail)
        self._build_ui()
        QtWidgets.QApplication.instance().installEventFilter(self)  # arrow keys: navigation on the time axis
        self.empty_plots()
        if mdd_file:
            self.open_file(str(mdd_file))
            if metadata is not None and self.H is not None:
                try:
                    self.Lbl = make_labels(metadata, self.H.dataChannels)
                except Exception as e:  # noqa: BLE001
                    self.status(f"Labels: {e}")

    # =================================================================================================== UI
    def _build_ui(self):
        cw = QtWidgets.QWidget()
        self.setCentralWidget(cw)
        top = QtWidgets.QVBoxLayout(cw)
        top.setContentsMargins(6, 6, 6, 6)
        top.setSpacing(4)
        bar = QtWidgets.QHBoxLayout()
        top.addLayout(bar)

        def btn(text, cb, tip=None):
            b = QtWidgets.QPushButton(text)
            b.clicked.connect(cb)
            if tip:
                b.setToolTip(tip)
            return b
        bar.addWidget(btn("Open .mdd ...", self.on_open))
        bar.addWidget(btn("+ EP recording ...", self.on_open_ep, "add an electrophysiological recording (LabChart .mat "
                          "export, e.g. sharp electrode: voltage + stimulation) aligned to the stimuli of the open .mdd "
                          "file"))
        self.lFile = ElidedLabel("no file")
        self.lFile.setMinimumWidth(120)
        bar.addWidget(self.lFile, 1)
        bar.addWidget(QtWidgets.QLabel("Channel"))
        self.cCh = QtWidgets.QComboBox()
        self.cCh.setSizeAdjustPolicy(QtWidgets.QComboBox.SizeAdjustPolicy.AdjustToContents)
        self.cCh.setMinimumWidth(self.fontMetrics().horizontalAdvance(f"Ch 8  (99999 {MU}N)") + 40)
        self.cCh.addItem("-")
        self.cCh.activated.connect(self.on_channel)
        bar.addWidget(self.cCh)
        bar.addWidget(QtWidgets.QLabel("From (s)"))
        wE = max(60, self.fontMetrics().horizontalAdvance("000000.0") + 14)  # whole number visible (macOS fonts)
        self.eFrom = QtWidgets.QLineEdit("0")
        self.eFrom.setFixedWidth(wE)
        bar.addWidget(self.eFrom)
        bar.addWidget(QtWidgets.QLabel("To (s)"))
        self.eTo = QtWidgets.QLineEdit("60")
        self.eTo.setFixedWidth(wE)
        bar.addWidget(self.eTo)
        self.eFrom.returnPressed.connect(self.on_load)
        self.eTo.returnPressed.connect(self.on_load)
        bar.addWidget(btn("Load", self.on_load))
        bar.addWidget(btn("Overview", self.on_overview, "overview of the whole file (min/max envelope)"))
        bar.addWidget(btn("Comments ...", self.on_comments, "searchable list of the comments in the log file; "
                          "double-click = go to"))
        bar.addWidget(btn("Protocols ...", self.on_protocols, "stimulation protocols of the log file (FFR, refractory "
                          "period, threshold, post-rest potentiation ...): contractions grouped by pacing frequency, S2 "
                          "interval, current, rest interval ..."))
        self.lInfo = QtWidgets.QLabel("")
        self.lInfo.setMinimumWidth(200)
        f = self.lInfo.font()
        f.setPointSize(f.pointSize() - 1)
        self.lInfo.setFont(f)
        bar.addWidget(self.lInfo)

        body = QtWidgets.QHBoxLayout()
        top.addLayout(body, 1)
        left = QtWidgets.QVBoxLayout()
        left.setSpacing(2)
        body.addLayout(left, 1)
        # plots: overview, force, stimuli (one layout), lower plot (own layout below its parameter list)
        self.glTop = PlotArea()
        self.glTop.ci.setSpacing(2)
        self.pOv = time_plot(right_width=50)
        self.pMain = time_plot(show_x_labels=False, right_width=50)
        self.stim = TwinPlot()
        self.pStim = self.stim.p
        self.glTop.addItem(self.pOv, row=0, col=0)
        self.glTop.addItem(self.pMain, row=1, col=0)
        self.glTop.addItem(self._nav_buttons(), row=2, col=0)
        self.glTop.addItem(self.pStim, row=3, col=0)
        self.glTop.ci.layout.setRowStretchFactor(0, 9)
        self.glTop.ci.layout.setRowStretchFactor(1, 40)
        self.glTop.ci.layout.setRowStretchFactor(2, 0)
        self.glTop.ci.layout.setRowFixedHeight(2, 24)
        self.glTop.ci.layout.setRowStretchFactor(3, 13)
        self.stim.attach()
        self.glTop.setMinimumHeight(330)
        left.addWidget(self.glTop, 62)
        row = QtWidgets.QHBoxLayout()
        row.addWidget(QtWidgets.QLabel("Lower plot:"))
        self.cPar = QtWidgets.QComboBox()
        for nm, u in self.plot_list:
            self.cPar.addItem(f"{nm} ({u.replace('u', MU) if u.startswith('u') else u})")
        self.cPar.setToolTip("parameter of every contraction shown in the lower plot (red = selected contractions)")
        self.cPar.currentIndexChanged.connect(lambda *_: self.plot_param())
        row.addWidget(self.cPar)
        row.addWidget(btn("Trend ...", self.on_trend, "rolling average of a parameter over long periods, also over "
                          "several .mdd files (e.g. _0, _1, _2 ...) in a row"))
        row.addStretch(1)
        left.addLayout(row)
        self.glPar = PlotArea()
        self.pPar = time_plot(right_width=50)
        self.glPar.addItem(self.pPar)
        self.glPar.setMinimumHeight(130)
        left.addWidget(self.glPar, 24)
        # EP recording (hidden until loaded)
        self.epBox = QtWidgets.QWidget()
        eh = QtWidgets.QHBoxLayout(self.epBox)
        eh.setContentsMargins(0, 0, 0, 0)
        self.glEP = PlotArea()
        self.pEPv = time_plot(show_x_labels=False)
        self.pEPs = time_plot()
        self.glEP.addItem(self.pEPv, row=0, col=0)
        self.glEP.addItem(self.pEPs, row=1, col=0)
        self.glEP.ci.layout.setRowStretchFactor(0, 4)
        self.glEP.ci.layout.setRowStretchFactor(1, 1)
        eh.addWidget(self.glEP, 1)
        ev = QtWidgets.QVBoxLayout()
        self.lEP = QtWidgets.QLabel("")
        self.lEP.setWordWrap(True)
        self.lEP.setAlignment(QtCore.Qt.AlignmentFlag.AlignTop)
        self.lEP.setFixedWidth(330)
        ev.addWidget(self.lEP, 1)
        ev.addWidget(btn("Remove EP recording", self.on_close_ep))
        eh.addLayout(ev)
        self.epBox.setVisible(False)
        self.lEP.setSizePolicy(QtWidgets.QSizePolicy.Policy.Fixed, QtWidgets.QSizePolicy.Policy.Ignored)
        left.addWidget(self.epBox, 34)
        # x axes linked: force, stimuli, lower plot, EP
        for p in (self.pStim, self.pPar, self.pEPv, self.pEPs):
            p.setXLink(self.pMain)
        self.pMain.vb.sigXRangeChanged.connect(self._x_changed)
        self.pOv.vb.sigXRangeChanged.connect(lambda *_: self._ov_label())
        # mouse
        for p in (self.pMain, self.pStim, self.pPar, self.pEPv, self.pEPs):
            p.vb.on_wheel = self._wheel_main
        self.stim.vb2.wheelEvent = lambda ev, axis=None: self.pStim.vb.wheelEvent(ev, axis)
        self.pMain.vb.on_drag = self._drag_main
        self.pMain.vb.on_click = self._click_main
        for p, nm in ((self.pStim, "stimuli"), (self.pPar, "parameter"), (self.pEPv, "ep"), (self.pEPs, "ep")):
            p.vb.on_click = (lambda nm_: (lambda x, y, b, d, sp: self._click_other(nm_, x, y, b, d, sp)))(nm)
        self.pOv.vb.on_wheel = self._wheel_ov
        self.pOv.vb.on_drag = self._drag_ov
        self.pOv.vb.on_click = self._click_ov

        # ---------------------------------------------------------------- analysis panel
        pnl = QtWidgets.QGroupBox("Analysis")
        pnl.setFixedWidth(345)
        body.addWidget(pnl)
        pv = QtWidgets.QVBoxLayout(pnl)
        pv.setSpacing(4)
        gb = QtWidgets.QGroupBox("Cursor in the force plot")
        gv = QtWidgets.QVBoxLayout(gb)
        self.rbRange = QtWidgets.QRadioButton("drag = select time range")
        self.rbToggle = QtWidgets.QRadioButton("click = exclude / include contraction")
        self.rbRange.setChecked(True)
        gv.addWidget(self.rbRange)
        gv.addWidget(self.rbToggle)
        pv.addWidget(gb)
        h = QtWidgets.QHBoxLayout()
        h.addWidget(btn("Labels ...", self.on_labels, "labels per channel: setupID, sliceID, species, sampleID, groups, "
                        "treatment, days in culture, analyst ..."))
        h.addWidget(btn("Range = loaded window", self.on_whole_window))
        pv.addLayout(h)
        g = QtWidgets.QGridLayout()
        thr_tip = ("minimum prominence of a contraction peak, per channel: auto or a manual value for the selected "
                   "channel (kept when you switch channels; also used for All channels, Protocols and Trend)")
        lt = QtWidgets.QLabel(f"Threshold, this ch. ({MU}N)")
        lt.setToolTip(thr_tip)
        g.addWidget(lt, 0, 0)
        self.cThr = QtWidgets.QComboBox()
        self.cThr.setToolTip(thr_tip)
        self.cThr.addItems(["auto", "manual"])
        self.cThr.activated.connect(self.on_threshold)
        g.addWidget(self.cThr, 0, 1)
        self.eThr = QtWidgets.QLineEdit("")
        self.eThr.setToolTip(thr_tip)
        self.eThr.setMaximumWidth(70)
        self.eThr.editingFinished.connect(self.on_threshold_value)
        g.addWidget(self.eThr, 0, 2)
        lz = QtWidgets.QLabel(f"Zero force ({MU}N)")
        lz.setToolTip("sensor signal without load; diastolic force = diastolic signal - zero force. Empty = Offset entry "
                      "of the log file")
        g.addWidget(lz, 1, 0)
        self.eZero = QtWidgets.QLineEdit("")
        self.eZero.setToolTip("empty = Offset entry of the log file")
        self.eZero.editingFinished.connect(self.on_zero)
        g.addWidget(self.eZero, 1, 1)
        self.lZeroSrc = QtWidgets.QLabel("")
        f = self.lZeroSrc.font()
        f.setPointSize(f.pointSize() - 2)
        self.lZeroSrc.setFont(f)
        g.addWidget(self.lZeroSrc, 1, 2)
        pv.addLayout(g)
        self.cbRocker = QtWidgets.QCheckBox("only contractions with rocker at rest")
        self.cbStim = QtWidgets.QCheckBox("only stimulated contractions")
        self.cbRF = QtWidgets.QCheckBox("remove rocker artifact")
        self.cbRF.setToolTip("subtracts the periodic signal of the rocker movement (estimated per channel between the "
                             "contractions, +-60 s around the window); light grey in the force plot = signal before. See "
                             "rocker_filter")
        self.cbRel = QtWidgets.QCheckBox("time axis: 0 = start of the loaded window")
        self.cbRel.setToolTip("display only; From/To, tables and exports keep the time in the file (s)")
        self.cXT = QtWidgets.QComboBox()
        self.cXT.addItems(["stimuli: auto", "stimuli: MyoDish", "stimuli: ext. trigger"])
        self.cXT.setToolTip("stimulus times: MyoDish pulses of the channel, or the external trigger pulses of the "
                            "status channel (external stimulator at the external controller unit: one chamber, any "
                            "data channel). auto = external trigger pulses if the window has no MyoDish pulses")
        self.cXT.activated.connect(self.on_filter)
        self.cbRocker.toggled.connect(self.on_filter)
        pv.addWidget(self.cbRocker)
        self.cbStim.toggled.connect(self.on_filter)
        hs = QtWidgets.QHBoxLayout()
        hs.addWidget(self.cbStim)
        hs.addWidget(self.cXT)
        pv.addLayout(hs)
        self.cbRF.toggled.connect(self.on_rocker_filter)
        self.cDet = QtWidgets.QComboBox()
        self.cDet.addItems(["high sensitivity", "high specificity"])
        self.cDet.setToolTip("auto threshold: high sensitivity counts all contractions and marks the uncertain ones "
                             "(orange: neither locked to the stimuli nor large compared with the other contractions); "
                             "high specificity does not count them")
        self.cDet.activated.connect(self.on_detection)
        hr = QtWidgets.QHBoxLayout()
        hr.addWidget(self.cbRF)
        hr.addWidget(self.cDet)
        pv.addLayout(hr)
        self.cbRel.toggled.connect(self.on_rel_time)
        pv.addWidget(self.cbRel)
        self.lCounts = QtWidgets.QLabel("")
        self.lCounts.setWordWrap(True)
        self.lCounts.setAlignment(QtCore.Qt.AlignmentFlag.AlignTop)
        self.lCounts.setMinimumHeight(92)
        f = self.lCounts.font()
        f.setPointSize(f.pointSize() - 1)
        self.lCounts.setFont(f)
        pv.addWidget(self.lCounts)
        self.tbl = QtWidgets.QTableWidget(0, 5)
        self.tbl.setHorizontalHeaderLabels(["parameter", "mean", "SD", "n", "unit"])
        self.tbl.verticalHeader().setVisible(False)
        self.tbl.verticalHeader().setDefaultSectionSize(18)
        self.tbl.setEditTriggers(QtWidgets.QAbstractItemView.EditTrigger.NoEditTriggers)
        f = self.tbl.font()
        f.setPointSize(f.pointSize() - 1)
        self.tbl.setFont(f)
        pv.addWidget(self.tbl, 1)
        grid = QtWidgets.QGridLayout()
        grid.addWidget(btn("Overlay contractions", self.on_overlay, "overlay of the selected contractions (mean beat "
                           "or time course); press again (or Add in the overlay window) to add another selection as a "
                           "new group; other channels of the same range: Channels ... in the overlay window"), 0, 0)
        grid.addWidget(btn("Show table", self.on_show_table), 0, 1)
        grid.addWidget(btn("Export this channel ...", self.on_export), 1, 0)
        grid.addWidget(btn("All channels -> file ...", self.on_all_channels), 1, 1)
        grid.addWidget(btn("Copy summary", self.on_copy), 2, 0)
        grid.addWidget(btn("Help", self.on_help), 2, 1)
        pv.addLayout(grid)
        self.lStatus = QtWidgets.QLabel("Open an .mdd file.")
        self.lStatus.setWordWrap(True)
        self.lStatus.setMinimumHeight(54)
        self.lStatus.setAlignment(QtCore.Qt.AlignmentFlag.AlignTop)
        self.lStatus.setStyleSheet("color: #000099")
        f = self.lStatus.font()
        f.setPointSize(f.pointSize() - 1)
        self.lStatus.setFont(f)
        pv.addWidget(self.lStatus)

        # ---------------------------------------------------------------- menu: save / export
        m = self.menuBar().addMenu("Save / Export")
        m.addAction("Save all plots (.png / .jpg / .tif / .pdf) ...", lambda: self.save_plots("all"))
        m.addAction("Save window as shown (screenshot .png / .jpg / .tif) ...", lambda: self.save_plots("window"))
        m.addSeparator()
        for nm in ("overview", "force", "stimuli", "parameter"):
            m.addAction(f"Save {nm} plot ...", (lambda n_: (lambda: self.save_plots(n_)))(nm))
        m.addSeparator()
        m.addAction("Export data of the force plot (.xlsx / .csv / .txt) ...", lambda: self.export_plot_data("force"))
        m.addAction("Export data of the stimulus plot ...", lambda: self.export_plot_data("stimuli"))
        m.addAction("Export data of the parameter plot ...", lambda: self.export_plot_data("parameter"))
        hm = self.menuBar().addMenu("Help")
        hm.addAction("Help ...", self.on_help)

    # =================================================================================================== helpers
    def status(self, msg):
        self.lStatus.setText(msg)
        QtWidgets.QApplication.processEvents()

    def zero_of(self, ch=None):
        ch = self.ch if ch is None else ch
        return self.zero_user.get(ch, math.nan)

    def thr_of(self, chs=None):
        """thresholds of channels chs for the analysis functions: 'auto' or one value per channel (NaN = auto);
        a single channel (int / None = selected channel): 'auto' or the value"""
        if chs is None or isinstance(chs, (int, np.integer)):
            v = self.thr_user.get(self.ch if chs is None else int(chs), math.nan)
            return "auto" if math.isnan(v) else v
        th = [self.thr_user.get(int(c), math.nan) for c in chs]
        return "auto" if all(math.isnan(v) for v in th) else th

    def _err(self, prefix, e):
        self.status(f"{prefix}{e}")
        if os.environ.get("MDA_DEBUG"):
            traceback.print_exc()

    # =================================================================================================== file
    def on_open(self):
        fn, _ = QtWidgets.QFileDialog.getOpenFileName(self, "MyoDish data file", self.last_dir, "MyoDish (*.mdd)")
        if fn:
            self.open_file(fn)

    def open_file(self, file):
        try:
            H = read_mdd(file, None, None, self.opts)
        except Exception as e:  # noqa: BLE001
            self._err("Error: ", e)
            return
        self.H = H
        self.S = self.O = self.B = self.C = None
        self.manual_off = []
        self.zero_user = {}
        self.thr_user = {}
        self.cThr.setCurrentIndex(0)
        self.eThr.setText("")
        self.Od = None
        self.ovXL = None
        self.rf_ctx = None
        self.rf_cache = {}
        self.rf_f0 = None
        if self.EP is not None:
            self.EP = None
            self.show_ep(False)
        nm = os.path.basename(H.file)
        self.last_dir = os.path.dirname(H.file)
        self.lFile.setText(nm)
        self.lFile.setToolTip(H.file)
        self.cCh.clear()
        self.cCh.addItems([f"Ch {c}" for c in H.dataChannels])
        self.ch = int(H.dataChannels[0])
        info = f"{H.samplingRate:.0f} Hz, {len(H.dataChannels)} channel(s), {fmt_duration(H.totalSeconds)}"
        if not math.isnan(H.recordingStart):
            info += "\nstart " + datenum_to_timestamps(H.recordingStart).strftime("%Y-%m-%d %H:%M")
        self.lInfo.setText(info)
        self.eFrom.setText("0")
        self.eTo.setText(f"{min(120, math.floor(H.totalSeconds)):.0f}")
        self.empty_plots()
        msg = "File opened. Press Load (time window From/To) or Overview."
        self.LE = None
        self.hiT = math.nan
        try:
            self.LE = log_entries(H.logFile)
            if self.LE["isComment"].any():
                msg += f" {int(self.LE['isComment'].sum())} comments in the log file (button Comments ...)."
        except Exception as e:  # noqa: BLE001
            msg += f" Log entries not read: {e}"
        if self.win_comments is not None:
            self.win_comments.refresh_file()
        if H.notes:
            msg += " Note: " + " ".join(H.notes)
        self.Lbl = make_labels(None, H.dataChannels)
        if self.win_labels is not None:
            self.win_labels.close()
            self.win_labels = None
        lf = os.path.splitext(H.file)[0] + "_labels.csv"
        if os.path.isfile(lf):
            try:
                self.Lbl = make_labels(lf, H.dataChannels)
                msg += f" Labels loaded from {os.path.basename(lf)}."
            except Exception as e:  # noqa: BLE001
                msg += f" Labels file not read: {e}"
        self.status(msg)
        if H.bytes < 150e6:
            self.on_overview()  # small files: overview right away

    def on_load(self):
        H = self.H
        if H is None:
            self.status("Open a file first.")
            return
        try:
            fr = float(self.eFrom.text())
            to = float(self.eTo.text())
        except ValueError:
            self.status("From / To must be numbers (s).")
            return
        if fr < 0:
            fr = H.totalSeconds + fr
        if to < 0:
            to = H.totalSeconds + to
        fr = max(0.0, fr)
        to = min(H.totalSeconds, to)
        if to - fr < 1:
            self.status("Time window too short (< 1 s).")
            return
        if to - fr > 4 * 3600:
            self.status("Window longer than 4 h: use the command line version (mda) for long ranges.")
            return
        self.status("Loading ...")
        try:
            S = read_mdd(H, fr, to, self.opts)
        except Exception as e:  # noqa: BLE001
            self._err("Error: ", e)
            return
        self.S = S
        self.rf_ctx = None
        self.rf_cache = {}
        self.rf_f0 = None
        self.eFrom.setText(f"{S.fromSeconds:.1f}")
        self.eTo.setText(f"{S.toSeconds:.1f}")
        cur = self.cCh.currentIndex()
        self.cCh.clear()
        for k, c in enumerate(S.dataChannels):  # channel list with the signal range
            x = np.sort(S.force[k])
            r = (x[max(1, mround(0.995 * x.size)) - 1] - x[max(1, mround(0.005 * x.size)) - 1]) if x.size else 0
            self.cCh.addItem(f"Ch {c}  ({r:.0f} {MU}N)")
        self.cCh.setCurrentIndex(max(0, cur))
        self.range = [S.fromSeconds, S.toSeconds]
        self.manual_off = []
        self.analyze(True)
        self.plot_overview()

    def on_overview(self):
        if self.H is None:
            self.status("Open a file first.")
            return
        dlg = QtWidgets.QProgressDialog("Reading the whole file ...", None, 0, 100, self)
        dlg.setWindowTitle("Overview")
        dlg.setMinimumDuration(300)
        try:
            self.O = read_mdd(self.H, "overview", None, self.opts,
                              lambda p: (dlg.setValue(int(100 * p)), QtWidgets.QApplication.processEvents()))
        except Exception as e:  # noqa: BLE001
            self.O = None
            self._err("Error: ", e)
        dlg.close()
        self.plot_overview()
        if self.O is not None:
            self.status("Overview: drag = load a time window, wheel = zoom, shift + wheel = move, double-click = whole "
                        "file.")

    def on_channel(self, *_):
        if self.H is None:
            return
        self.ch = int(self.H.dataChannels[self.cCh.currentIndex()])
        self.manual_off = []
        self.show_threshold()
        self.plot_overview()
        if self.S is not None:
            self.analyze(False)

    # =================================================================================================== settings
    # detection threshold per channel (2026-10-07): auto or a manual value for each channel
    def on_threshold(self, *_):
        if self.cThr.currentIndex() == 0:
            self.thr_user.pop(self.ch, None)
            if self.S is not None:
                self.analyze(False)
        else:
            self.on_threshold_value()

    def show_threshold(self):
        """threshold controls of the selected channel (auto: value shown after the detection)"""
        v = self.thr_user.get(self.ch, math.nan)
        if math.isnan(v):
            self.cThr.setCurrentIndex(0)
            self.eThr.setText("")
        else:
            self.cThr.setCurrentIndex(1)
            self.eThr.setText(f"{v:g}")

    def on_threshold_value(self):
        try:
            v = float(self.eThr.text())
        except ValueError:
            v = math.nan
        cur = self.thr_user.get(self.ch, math.nan)
        if math.isnan(v) or v <= 0:
            if math.isnan(cur):
                self.cThr.setCurrentIndex(0)
            self.status("Threshold: enter a positive number (uN).")
            return
        if not math.isnan(cur) and abs(cur - v) < 1e-12 and self.cThr.currentIndex() == 1:
            return
        if math.isnan(cur) and self.C is not None and abs(self.C.threshold - v) < 0.5 and \
                self.cThr.currentIndex() == 0:
            return  # editing finished without a change (auto value shown)
        self.cThr.setCurrentIndex(1)
        self.thr_user[self.ch] = v
        if self.S is not None:
            self.analyze(False)

    def on_rocker_filter(self, *_):
        self.opts.rockerFilter = self.cbRF.isChecked()
        if self.S is not None:
            self.analyze(False)

    def on_detection(self, *_):
        self.opts.detection = ("sensitive", "specific")[self.cDet.currentIndex()]
        if self.S is not None:
            self.analyze(False)

    def on_filter(self, *_):
        self.opts.rocker = "stopped" if self.cbRocker.isChecked() else "any"
        self.opts.beats = "stimulated" if self.cbStim.isChecked() else "all"
        self.opts.externalTrigger = ("auto", "off", "on")[self.cXT.currentIndex()]
        if self.S is not None:
            self.analyze(False)

    def set_zero_at_click(self):
        if self.S is None or self.C is None or any(math.isnan(v) for v in self.alt_pt):
            self.status("Right-click into the force plot.")
            return
        z0 = zero_force(self.S, self.ch, self.zero_of(), [self.alt_pt[0]])[0][0]
        if math.isnan(z0):
            z0 = 0.0  # plot shows the sensor signal
        self.zero_user[self.ch] = self.alt_pt[1] + z0
        self.eZero.setText(f"{self.zero_user[self.ch]:.0f}")
        self.plot_overview()
        self.analyze(False)
        self.status(f"Zero force of channel {self.ch} set to {self.zero_user[self.ch]:.0f} {MU}N (sensor signal at the "
                    "mouse pointer).")

    def reset_zero(self):
        self.zero_user.pop(self.ch, None)
        self.eZero.setText("")
        self.plot_overview()
        if self.S is not None:
            self.analyze(False)

    def on_zero(self):
        s = self.eZero.text().strip()
        old = self.zero_of()
        if not s:
            if self.C is not None and not math.isnan(self.C.zeroForce) and math.isnan(old):
                return
            self.zero_user.pop(self.ch, None)
        else:
            try:
                v = float(s)
            except ValueError:
                self.status("Zero force: enter a number (uN) or leave empty (= log file).")
                return
            shown = self.C.zeroForce if self.C is not None else math.nan
            if math.isnan(old) and not math.isnan(shown) and f"{shown:.0f}" == s:
                return  # unchanged display of the log value
            if not math.isnan(old) and abs(old - v) < 1e-9:
                return
            self.zero_user[self.ch] = v
        self.plot_overview()
        if self.S is not None:
            self.analyze(False)

    def on_whole_window(self):
        if self.S is None:
            return
        self.range = [self.S.fromSeconds, self.S.toSeconds]
        self.refresh(False)

    def on_rel_time(self, *_):
        self.rel_time = self.cbRel.isChecked()
        self.main_ticks()

    # =================================================================================================== analysis
    def analyze(self, reset_x):
        self.status("Detecting contractions ...")
        rf_msg = ""
        try:
            optsC = Struct(self.opts)
            optsC.zeroForce = self.zero_of()
            optsC.threshold = self.thr_of()
            Sa = self.S
            if self.opts.rockerFilter:
                Sa, rf_msg = self.rocker_filtered(optsC)
            B, C = analyze_channel(Sa, self.ch, None, optsC)
            self.ep_marks = None
            if self.EP is not None and len(B) > 0:
                try:
                    A, self.ep_marks = analyze_ap(self.EP, B)
                    for c in A.columns:
                        B[c] = A[c].to_numpy()
                except Exception as e:  # noqa: BLE001
                    rf_msg = (rf_msg + f" AP analysis: {e}").strip()
            self.B, self.C = B, C
        except Exception as e:  # noqa: BLE001
            self.B = self.C = None
            self.pMain.clear()
            self.pPar.clear()
            self.plot_stim()
            self.update_summary()
            self._err("Error: ", e)
            return
        C = self.C
        if C.thresholdMode == "auto":
            self.eThr.setText(f"{C.threshold:.0f}")
        self.eZero.setText("" if math.isnan(C.zeroForce) else f"{C.zeroForce:.0f}")
        self.lZeroSrc.setText(C.zeroSource)
        self.refresh(reset_x)
        if self.win_ref is not None:
            self.win_ref.draw()
        msg = (f"Channel {self.ch}: {len(self.B)} contractions detected (threshold {C.threshold:.0f} {MU}N, "
               f"{C.thresholdMode}).")
        if self.B["uncertain"].any():
            msg += f" {int(self.B['uncertain'].sum())} uncertain (orange)."
        if C.get("noContractions", False):
            lvl = "" if math.isnan(C.noiseLevel) else f" (level before the stimuli {C.noiseLevel:.0f} {MU}N)"
            msg = (f"Channel {self.ch}: no contractions - only peaks of the rocker movement / noise{lvl}, not locked "
                   f"to the stimuli (slice not beating?).")
        elif C.get("thresholdArtifacts", 0) > 0:
            msg += f" {C.thresholdArtifacts} peaks of the rocker movement not counted (not locked to the stimuli)."
        if rf_msg:
            msg += " " + rf_msg
        self.status(msg)

    def rocker_filtered(self, optsC, ch=None):
        """S with the rocker artifact of channel ch (default: the current channel) subtracted; estimated with +-60 s
        context (windows < 10 min), cached per channel and detection options."""
        ch = self.ch if ch is None else int(ch)
        S = self.S
        if not np.any(S.rockerOn):
            return S, "Rocker filter: the rocker does not move in this window."
        dc = [int(c) for c in S.dataChannels]
        row = dc.index(ch)
        key = json.dumps({k: (v if not isinstance(v, np.ndarray) else v.tolist()) for k, v in optsC.items()
                          if k not in ("zeroForce", "rocker", "beats", "referenceBeat", "detection")}, default=str)
        E = self.rf_cache.get(ch)
        if E is None or E["key"] != key:
            self.status("Rocker filter: estimating the rocker artifact ...")
            if self.rf_ctx is None:
                if S.toSeconds - S.fromSeconds < 600:
                    self.rf_ctx = read_mdd(self.H, max(0.0, S.fromSeconds - 60),
                                           min(self.H.totalSeconds, S.toSeconds + 60), self.opts)
                else:
                    self.rf_ctx = S
            S1 = Struct(t=S.t, force=S.force[row:row + 1].copy(), dataChannels=np.array([ch]), rockerOn=S.rockerOn,
                        dt=S.dt)
            o = Struct(optsC)
            if o.rockerFrequency is None and self.rf_f0 is not None:
                o.rockerFrequency = self.rf_f0  # same for all channels
            S1, R = rocker_filter(S1, ch, o, self.rf_ctx)
            R = R[0]
            if self.rf_f0 is None and R.f0table.shape[0]:
                self.rf_f0 = R.f0table
            E = {"key": key, "art": S1.rockerArtifact[0].copy(), "R": R}
            self.rf_cache[ch] = E
        Sa = S.copy()
        Sa.force = S.force.copy()
        Sa.force[row] = S.force[row] - E["art"]
        Sa.rockerArtifact = np.zeros(S.force.shape)
        Sa.rockerArtifact[row] = E["art"]
        Sa.rockerFiltered = np.zeros(len(dc), bool)
        Sa.rockerFiltered[row] = True
        Sa.rockerFilterInfo = [None] * len(dc)
        Sa.rockerFilterInfo[row] = E["R"]
        return Sa, re.sub(r"^Rocker filter, channel \d+: ", "Rocker filter: ", E["R"].message)

    def in_range(self):
        tp = self.B["t_peak"].to_numpy()
        return (tp >= self.range[0]) & (tp <= self.range[1])

    def is_manual(self):
        tp = self.B["t_peak"].to_numpy()
        m = np.zeros(tp.size, bool)
        for t in self.manual_off:
            m |= np.abs(tp - t) < 1e-6
        return m

    def deviating(self):
        return self.deviating_of(self.B, self.C)

    def deviating_of(self, B, C):
        """contractions that deviate from the reference beat by more than ref_thr SD (False without reference)."""
        n = len(B)
        if C is None or C.get("referenceBeat") is None:
            return np.zeros(n, bool)
        with np.errstate(invalid="ignore"):
            a = B["refMaxDeviation_SD"].to_numpy(float) > self.ref_thr
            nrm = B["refMaxDeviationNorm_SD"].to_numpy(float) > self.ref_thr
        return a if self.ref_which == 1 else (nrm if self.ref_which == 2 else a | nrm)

    def selected(self):
        sel = self.B["included"].to_numpy(bool) & self.in_range() & ~self.is_manual()
        if self.ref_exclude:
            sel &= ~self.deviating()
        return sel

    def range_table(self):
        inR = self.in_range()
        man = self.is_manual()
        T = self.B[inR].copy().reset_index(drop=True)
        T["included"] = T["included"].to_numpy(bool) & ~man[inR]
        T["manuallyExcluded"] = man[inR]
        T["contraction"] = np.arange(1, len(T) + 1, dtype=float)
        H = self.H
        when = None
        if not math.isnan(H.recordingStart) and len(T):
            clock = datenum_to_timestamps(H.recordingStart + T["t_peak"].to_numpy() / 86400)
            T.insert(list(T.columns).index("t_peak") + 1, "clockTime", clock)
            when = list(clock)
        T.insert(0, "file", os.path.basename(H.file))
        return add_labels(T, self.Lbl, when)

    def summary_row(self):
        Bs = self.B.copy()
        Bs["included"] = self.selected()
        Sm = summarize(Bs, self.C, self.range)
        Sm.insert(0, "file", os.path.basename(self.H.file))
        when = None
        if not math.isnan(self.H.recordingStart):
            when = list(datenum_to_timestamps(np.array([self.H.recordingStart + np.mean(self.range) / 86400])))
        return add_labels(Sm, self.Lbl, when)

    # =================================================================================================== display
    def refresh(self, reset_x):
        self.plot_main(reset_x)
        self.plot_stim()
        self.plot_param()
        self.update_summary()
        self.draw_ep()

    def empty_plots(self):
        for p in (self.pMain, self.pPar):
            p.clear()
        self.plot_stim()
        if self.epBox.isVisible():
            self.pEPv.clear()
            self.pEPs.clear()
        self.tbl.setRowCount(0)
        self.lCounts.setText("")
        self.plot_overview()
        self.pMain.setLabel("left", f"force ({MU}N)")
        self.pPar.setLabel("bottom", "time in file (s)")

    def _axes_time(self):
        """time axes: tmax / t0 (relative time) of force, stimulus, parameter and EP plots."""
        if self.S is None:
            return
        t0 = self.S.fromSeconds if self.rel_time else 0.0
        tmax = self.S.toSeconds - t0 if self.rel_time else self.H.totalSeconds
        for p in (self.pMain, self.pStim, self.pPar, self.pEPv, self.pEPs):
            ax = p.getAxis("bottom")
            ax.t0 = t0
            ax.tmax = tmax
            ax.picture = None
            ax.update()

    def main_ticks(self):
        self._axes_time()
        self._x_label()

    def x_label_text(self):
        unit = self.pPar.getAxis("bottom").unit
        if self.rel_time:
            return f"time from the start of the loaded window ({unit}; window starts at {self.S.fromSeconds:.1f} s in the file)"
        return f"time in file ({unit})"

    def _x_label(self):
        if self.S is None:
            return
        xl = self.x_label_text()
        target = self.pEPs if self.epBox.isVisible() else self.pPar
        target.setLabel("bottom", xl)
        if target is self.pEPs:
            self.pPar.setLabel("bottom", "")

    def _x_changed(self, *_):
        QtCore.QTimer.singleShot(0, self._after_x_change)

    def _after_x_change(self):
        self._x_label()
        self.stim_labels()
        if self.epBox.isVisible():
            self.draw_ep()

    def _axis_time_of(self, p):
        """time axis of an export plot as on the screen (relative time)."""
        ax = p.getAxis("bottom")
        ax.t0 = self.S.fromSeconds if self.rel_time else 0.0
        ax.tmax = self.S.toSeconds - ax.t0 if self.rel_time else self.H.totalSeconds

    def plot_main(self, reset_x, target=None):
        p = self.pMain if target is None else target
        old = self.pMain.vb.viewRange()[0]
        p.clear()
        C, S, B = self.C, self.S, self.B
        if C is None:
            return
        if target is None:
            self._axes_time()
        else:
            self._axis_time_of(p)
        z0, _, _, _ = zero_force(S, self.ch, self.zero_of(), C.t)
        has_zero = not np.any(np.isnan(z0))
        fy = C.f - z0 if has_zero else C.f
        art = C.get("rockerArtifact")
        show_raw = art is not None and np.any(art != 0)
        f_raw = fy + art if show_raw else fy
        yl = [float(np.nanmin(np.r_[fy, f_raw])), float(np.nanmax(np.r_[fy, f_raw]))]
        d = max(1.0, yl[1] - yl[0])
        yl = [yl[0] - 0.08 * d, yl[1] + 0.08 * d]
        rects(p, [self.range[0]], [self.range[1]], yl[0], yl[1], (255, 245, 191), pen=(217, 179, 51), z=-20)
        s1, s2 = runs(S.rockerOn)
        if s1.size:
            rects(p, S.t[s1], S.t[s2], yl[0], yl[1], (140, 140, 140, 64), z=-15)
        if show_raw:
            c = p.plot(C.t, f_raw, pen=pg.mkPen((184, 184, 184), width=1))
            c.setDownsampling(auto=True, method="peak")
            c.setClipToView(True)
        c = p.plot(C.t, fy, pen=pg.mkPen("k", width=1))
        c.setDownsampling(auto=True, method="peak")
        c.setClipToView(True)
        st = C.stimTimes[(C.stimTimes >= S.fromSeconds) & (C.stimTimes <= S.toSeconds)]
        vlines(p, st, yl[0], yl[0] + 0.04 * (yl[1] - yl[0]), BLUE)
        if B is not None and len(B):
            pk = {v: i for i, v in enumerate(C.peakTimes)}
            tp = B["t_peak"].to_numpy()
            y = np.array([fy[C.iPeaks[pk[x]]] for x in tp])
            inR = self.in_range()
            man = self.is_manual()
            unc = B["included"].to_numpy(bool) & inR & ~man & B["uncertain"].to_numpy(bool)  # uncertain: orange
            sel = B["included"].to_numpy(bool) & inR & ~man & ~B["uncertain"].to_numpy(bool)
            filt = inR & ~B["included"].to_numpy(bool) & ~man
            p.addItem(pg.ScatterPlotItem(tp[~inR], y[~inR], symbol="o", size=3, pen=None, brush=(153, 153, 153)))
            p.addItem(pg.ScatterPlotItem(tp[filt], y[filt], symbol="t", size=8, pen=pg.mkPen((128, 128, 128)),
                                         brush=None))
            p.addItem(pg.ScatterPlotItem(tp[man & inR], y[man & inR], symbol="x", size=11, pen=pg.mkPen("k", width=1.5),
                                         brush="k"))
            p.addItem(pg.ScatterPlotItem(tp[sel], y[sel], symbol="t", size=8, pen=pg.mkPen(RED), brush=RED))
            p.addItem(pg.ScatterPlotItem(tp[unc], y[unc], symbol="t", size=8, pen=pg.mkPen(ORANGE), brush=ORANGE))
            dv = self.deviating() & inR
            if dv.any():
                p.addItem(pg.ScatterPlotItem(tp[dv], y[dv], symbol="o", size=14, pen=pg.mkPen(MAGENTA, width=1.5),
                                             brush=None))
        if self.LE is not None and len(self.LE):
            E = self.LE
            cm = E["isComment"].to_numpy() & (E["t_file"].to_numpy() >= S.fromSeconds) & \
                (E["t_file"].to_numpy() <= S.toSeconds)
            if cm.any():
                tc = E["t_file"].to_numpy()[cm]
                vlines(p, tc, yl[0], yl[1], PURPLE, style=QtCore.Qt.PenStyle.DotLine)
                lab = [(t[:45] + ("..." if len(t) > 45 else "")) + "  " for t in E["text"].to_numpy()[cm]]
                rot_labels(p, tc, yl[1], lab, PURPLE)
                hi = np.abs(tc - self.hiT) < 1e-6
                if hi.any():
                    vlines(p, tc[hi], yl[0], yl[1], PURPLE, width=2)
        p.vb.setYRange(yl[0], yl[1], padding=0)
        if target is not None:
            p.vb.setXRange(old[0], old[1], padding=0)
        elif reset_x or old[0] < S.fromSeconds - 1 or old[1] > S.toSeconds + 1 or old[1] - old[0] <= 0 or \
                (old[0] == 0 and old[1] == 1):
            p.vb.setXRange(S.fromSeconds, S.toSeconds, padding=0)
        else:
            p.vb.setXRange(old[0], old[1], padding=0)
        p.setLabel("left", f"force - zero force ({MU}N)" if has_zero else f"force ({MU}N, sensor signal; zero "
                   "unknown)")
        ttl = (f"Channel {self.ch}   (red = selected, orange = uncertain, grey = excluded by filter, x = excluded by you, blue = stimuli, "
               "grey background = rocker moving, purple = comments")
        ttl += ", light grey = before rocker filter)" if show_raw else ")"
        set_title(p, ttl)

    def plot_param(self, target=None):
        p = self.pPar if target is None else target
        p.clear()
        B = self.B
        if B is None:
            return
        if target is None:
            self._axes_time()
        else:
            self._axis_time_of(p)
        nm, unit = self.plot_list[max(0, self.cPar.currentIndex())]
        if nm not in B.columns:
            why = "no EP recording (+ EP recording ...)" if nm in [a[0] for a in AP_PARAMETERS] else \
                "no reference beat (right click in the force plot)"
            set_title(p, f"{nm}: {why}", 9)
            p.setLabel("left", "")
            return
        set_title(p, "")
        v = B[nm].to_numpy(float)
        tp = B["t_peak"].to_numpy()
        sel = self.selected()
        p.addItem(pg.ScatterPlotItem(tp[~sel], v[~sel], symbol="o", size=4, pen=None, brush=(179, 179, 179)))
        u = B["uncertain"].to_numpy(bool)
        p.addItem(pg.ScatterPlotItem(tp[sel & ~u], v[sel & ~u], symbol="o", size=6, pen=None, brush=RED))
        p.addItem(pg.ScatterPlotItem(tp[sel & u], v[sel & u], symbol="o", size=6, pen=None, brush=ORANGE))
        if sel.any():
            m = nanmean(v[sel])
            p.plot(self.range, [m, m], pen=pg.mkPen(RED, width=1, style=QtCore.Qt.PenStyle.DashLine))
        if nm.endswith("_pctRef"):
            p.addItem(pg.InfiniteLine(100, angle=0, pen=pg.mkPen("k", style=QtCore.Qt.PenStyle.DotLine)))
        if nm.endswith("_dRef"):
            p.addItem(pg.InfiniteLine(0, angle=0, pen=pg.mkPen("k", style=QtCore.Qt.PenStyle.DotLine)))
        u = unit.replace("u", MU) if unit.startswith("u") else unit
        p.setLabel("left", f"{nm} ({u})")
        p.showGrid(x=True, y=True, alpha=0.25)
        fin = v[np.isfinite(v)]
        if fin.size:
            lo, hi = float(fin.min()), float(fin.max())
            d = max(hi - lo, 1e-12 if hi == lo == 0 else abs(hi) * 0.05 + 1e-12)
            p.vb.setYRange(lo - 0.08 * d, hi + 0.08 * d, padding=0)
        if target is None:
            self._x_label()

    def update_summary(self):
        B = self.B
        if B is None:
            self.tbl.setRowCount(0)
            self.lCounts.setText("")
            return
        Sm = self.summary_row().iloc[0]
        rows = []
        for nm, u, _ in PARAMETERS:
            rows.append([nm, fmt_num(Sm[nm + "_mean"], 4), fmt_num(Sm[nm + "_SD"], 3), str(int(Sm[nm + "_n"])),
                         u.replace("u", MU) if u.startswith("u") else u])
        if "APD90" in B.columns:
            for nm, u, _ in AP_PARAMETERS:
                rows.append([nm, fmt_num(Sm[nm + "_mean"], 4), fmt_num(Sm[nm + "_SD"], 3), str(int(Sm[nm + "_n"])), u])
        rows.append(["extra beats", f"{int(Sm.nExtraBeats)}", "", str(int(Sm.nDetected)), "count"])
        rows.append(["extra beats", fmt_num(Sm.extraBeats_percent, 3), "", str(int(Sm.nDetected)), "%"])
        rows.append(["missed beats", f"{int(Sm.nMissedBeats)}", "", str(int(Sm.nStimuli)), "count"])
        rows.append(["missed beats", fmt_num(Sm.missedBeats_percent, 3), "", str(int(Sm.nStimuli)), "%"])
        rows.append(["uncertain (all)", f"{int(Sm.nUncertain)}", "", str(int(Sm.nDetected)), "count"])
        rows.append(["uncertain stimulated", f"{int(Sm.nStimulatedUncertain)}", "", str(int(Sm.nStimulated)), "count"])
        rows.append(["uncertain extra", f"{int(Sm.nExtraBeatsUncertain)}", "", str(int(Sm.nExtraBeats)), "count"])
        rows.append(["uncertain missed", f"{int(Sm.nMissedBeatsUncertain)}", "", str(int(Sm.nStimuli)), "count"])
        has_ref = self.C.get("referenceBeat") is not None
        if has_ref:
            inR = self.in_range()
            nCmp = int(np.sum(inR & ~np.isnan(B["refMaxDeviation_SD"].to_numpy(float))))
            nDev = int(np.sum(inR & self.deviating()))
            pDev = 100 * nDev / nCmp if nCmp > 0 else math.nan
            rows.append([f"deviating (> {self.ref_thr:g} SD)", f"{nDev}", "", str(nCmp), "count"])
            rows.append([f"deviating (> {self.ref_thr:g} SD)", fmt_num(pDev, 3), "", str(nCmp), "%"])
            for k, (nm, _, _) in enumerate(PARAMETERS):
                rows[k].insert(2, self.rel_cell(Sm, nm))
            for r in rows[len(PARAMETERS):]:
                r.insert(2, "")
            cols = ["parameter", "mean", "%ref", "SD", "n", "unit"]
        else:
            cols = ["parameter", "mean", "SD", "n", "unit"]
        self.tbl.clear()
        self.tbl.setColumnCount(len(cols))
        self.tbl.setHorizontalHeaderLabels(cols)
        self.tbl.setRowCount(len(rows))
        for i, r in enumerate(rows):
            for j, v in enumerate(r):
                it = QtWidgets.QTableWidgetItem(v)
                if j > 0 and cols[j] != "unit":
                    it.setTextAlignment(QtCore.Qt.AlignmentFlag.AlignRight | QtCore.Qt.AlignmentFlag.AlignVCenter)
                self.tbl.setItem(i, j, it)
        hh = self.tbl.horizontalHeader()  # numbers and units complete (font sizes differ between systems), names elided
        hh.setSectionResizeMode(0, QtWidgets.QHeaderView.ResizeMode.Stretch)
        for j in range(1, len(cols)):
            hh.setSectionResizeMode(j, QtWidgets.QHeaderView.ResizeMode.ResizeToContents)
        txt = (f"Range {self.range[0]:.2f} - {self.range[1]:.2f} s ({self.range[1] - self.range[0]:.1f} s)\n"
               f"{int(Sm.nContractions)} of {int(Sm.nDetected)} contractions selected ({int(Sm.nStimulated)} "
               f"stimulated, {int(Sm.nExtraBeats)} extra)\n{int(Sm.nStimuli)} stimuli"
               f"{' (ext. trigger)' if self.C.stimChannel == 0 else ''} ({Sm.stimFrequency:.2f} Hz), "
               f"{int(Sm.nMissedBeats)} without contraction\n{self.label_line(Sm)}")
        if self.C.rockerFilter is not None:
            txt += "\n" + self.rocker_line(self.C.rockerFilter)
        if has_ref:
            w = {1: "abs.", 2: "norm.", 3: "abs. or norm."}[self.ref_which]
            R = self.C.referenceBeat
            txt += (f"\nreference ({R.n}, {R.align}): deviating > {self.ref_thr:g} SD ({w})"
                    + (", excl." if self.ref_exclude else ""))
        self.lCounts.setText(txt)

    @staticmethod
    def rel_cell(Sm, p):
        if p + "_pctRef_mean" in Sm.index:
            v = Sm[p + "_pctRef_mean"]
            return "" if (v is None or math.isnan(v)) else f"{v:.1f}"
        if p + "_dRef_mean" in Sm.index:
            v = Sm[p + "_dRef_mean"]
            return "" if (v is None or math.isnan(v)) else f"Δ{v:+.0f}"
        return ""

    @staticmethod
    def rocker_line(R):
        if R.status == "corrected":
            return f"rocker filter: {R.artifactPP:.0f} {MU}N p-p removed ({R.f0:.3f} Hz)"
        if R.status == "partly corrected":
            return f"rocker filter: {R.artifactPP:.0f} {MU}N p-p removed in {100 * R.correctedFraction:.0f} % of rocker time"
        return "rocker filter: " + R.status

    def label_line(self, Sm):
        parts = []
        for nm in ("sampleID", "sliceID", "species", "tissue", "treatment"):
            v = Sm.get(nm, "")
            if isinstance(v, str) and v:
                parts.append(v)
        c = Sm.get("concentration", math.nan)
        if isinstance(c, (float, int)) and not math.isnan(c):
            parts.append(f"{c:g} {Sm.get('concentrationUnit', '')}".strip())
        d = Sm.get("daysInCulture", math.nan)
        if isinstance(d, (float, int)) and not math.isnan(d):
            parts.append(f"day {d:.2f}")
        return "labels: none (button Labels ...)" if not parts else "labels: " + " | ".join(parts)

    # ---------------------------------------------------------------- stimulus plot
    def stim_data(self):
        S, C = self.S, self.C
        J = np.flatnonzero(np.asarray(S.stim.channel) == C.stimChannel)
        o = np.argsort(np.asarray(S.stim.time)[J], kind="stable")
        J = J[o]
        tS = np.asarray(S.stim.time, float)[J]
        cur = np.asarray(S.stim.current, float)[J]
        if C.stimChannel == 0:  # external trigger pulses: no current
            cur = np.ones(cur.size)
        ok = np.asarray(S.stim.currentReached, bool)[J]
        ex = np.asarray(S.stim.isExtraPulse, bool)[J]
        iv = np.r_[np.nan, np.diff(tS)] * 1000
        return tS, cur, ok, ex, iv

    def plot_stim(self, target=None):
        tw = self.stim if target is None else target
        tw.clear()
        if target is None:
            self._stim_txt = []
        else:
            self._axis_time_of(tw.p)
        p = tw.p
        p.getAxis("left").setPen(pg.mkPen(RED))
        p.getAxis("left").setTextPen(pg.mkPen(RED))
        p.getAxis("right").setPen(pg.mkPen(BLUE))
        p.getAxis("right").setTextPen(pg.mkPen(BLUE))
        p.setLabel("left", "mA")
        p.setLabel("right", "ms")
        set_title(p, "")
        if self.C is None or self.S is None:
            return
        tS, cur, ok, ex, iv = self.stim_data()
        isExt = self.C.stimChannel == 0  # external trigger pulses: bars of height 1, no current
        if isExt:
            p.setLabel("left", "ext.")
        p.getAxis("left").setStyle(showValues=not isExt)
        if tS.size == 0:
            msg = "no external trigger pulses" if isExt else f"no stimulus pulses on channel {self.C.stimChannel}"
            set_title(p, msg, 8)
            return
        for m, col in ((~ex, RED), (ex, GREEN)):
            if m.any():
                vlines(p, tS[m], 0, cur[m], col)
        if (~ok).any():
            p.addItem(pg.ScatterPlotItem(tS[~ok], cur[~ok], symbol="x", size=7, pen=pg.mkPen((204, 0, 204)),
                                         brush=(204, 0, 204)))
        p.vb.setYRange(0, max(1.0, float(cur.max())) * 1.35, padding=0)
        tw.vb2.addItem(pg.ScatterPlotItem(tS, iv, symbol="o", size=5, pen=None, brush=BLUE))
        fin = iv[np.isfinite(iv)]
        if fin.size:
            r = (float(fin.min()), float(fin.max()))
            dd = max(r[1] - r[0], 0.2 * r[1] + 1)
            tw.vb2.setYRange(r[0] - 0.25 * dd, r[1] + 0.35 * dd, padding=0)
        if isExt:
            set_title(p, "external trigger pulses (external stimulator; red bars), interval to the previous pulse "
                      "(blue, ms)", 8)
        else:
            set_title(p, f"stimuli channel {self.C.stimChannel}: current (red bars, mA; green = extra pulse, x = "
                      "current not reached), interval to the previous pulse (blue, ms)", 8)
        if target is None:
            self.stim_labels()
        else:
            p.vb.setXRange(*self.pMain.vb.viewRange()[0], padding=0)
            self.stim_labels(tw)

    def stim_labels(self, target=None):
        tw = self.stim if target is None else target
        if target is None:
            for owner, t in self._stim_txt:
                try:
                    if t.scene() is not None:
                        owner.removeItem(t)
                except Exception:  # noqa: BLE001
                    pass
            self._stim_txt = []
        store = self._stim_txt if target is None else []
        if self.C is None or self.S is None:
            return
        tS, cur, ok, _, iv = self.stim_data()
        if tS.size == 0:
            return
        xl = self.pMain.vb.viewRange()[0]
        v = np.flatnonzero((tS >= xl[0]) & (tS <= xl[1]))
        if v.size == 0 or v.size > 40:
            return
        ylL = tw.p.vb.viewRange()[1]
        f = QtGui.QFont()
        f.setPointSize(7)
        for k in v:
            lab = "ext" if self.C.stimChannel == 0 else f"{cur[k]:g}" + (" ?!" if not ok[k] else "")
            t = pg.TextItem(lab, color=RED, anchor=(0.5, 1))
            t.setFont(f)
            t.setPos(tS[k], min(cur[k] + 0.04 * (ylL[1] - ylL[0]), ylL[1]))
            tw.p.addItem(t)
            store.append((tw.p, t))
            if not math.isnan(iv[k]):
                t2 = pg.TextItem(f"  {iv[k]:.0f}", color=BLUE, anchor=(0, 0.5))
                t2.setFont(f)
                t2.setPos(tS[k], iv[k])
                tw.vb2.addItem(t2)
                store.append((tw.vb2, t2))

    # ---------------------------------------------------------------- overview
    def plot_overview(self, target=None):
        p = self.pOv if target is None else target
        p.clear()
        O = self.O
        if O is None:
            t = pg.TextItem("Overview: press 'Overview'", color=(128, 128, 128), anchor=(0.5, 0.5))
            p.addItem(t)
            t.setPos(0.5, 0.5)
            p.vb.setRange(xRange=(0, 1), yRange=(0, 1), padding=0)
            set_title(p, "")
            return
        xlv = (0, O.totalSeconds) if self.ovXL is None else tuple(self.ovXL)
        P = O
        Od = self.Od
        if Od is not None and Od.range[0] <= xlv[0] + 1e-6 and Od.range[1] >= xlv[1] - 1e-6 and \
                Od.binSeconds < O.binSeconds:
            P = Od
        dc = [int(c) for c in P.dataChannels]
        row = dc.index(self.ch)
        x = P.tBin
        lo = P.minForce[row].copy()
        hi = P.maxForce[row].copy()
        zOv, _, _, _ = zero_force(self.H, self.ch, self.zero_of(), x)
        has_zero = not np.any(np.isnan(zOv))
        if has_zero:
            lo -= zOv
            hi -= zOv
        ok = ~np.isnan(lo) & ~np.isnan(hi)
        x, lo, hi, rf = x[ok], lo[ok], hi[ok], P.rockerFraction[ok]
        if x.size == 0:
            return
        vis = (x >= xlv[0] - P.binSeconds) & (x <= xlv[1] + P.binSeconds)
        if not vis.any():
            vis[:] = True
        yl = [float(lo[vis].min()), float(hi[vis].max())]
        d = max(1.0, yl[1] - yl[0])
        yl = [yl[0] - 0.05 * d, yl[1] + 0.05 * d]
        s1, s2 = runs(rf < 0.5)  # rocker at rest
        if s1.size:
            hb = P.binSeconds / 2
            rects(p, x[s1] - hb, x[s2] + hb, yl[0], yl[1], (191, 242, 191), z=-20)
        c1 = pg.PlotDataItem(x, hi, pen=pg.mkPen((51, 51, 51)))
        c2 = pg.PlotDataItem(x, lo, pen=pg.mkPen((51, 51, 51)))
        p.addItem(c1)
        p.addItem(c2)
        p.addItem(pg.FillBetweenItem(c1, c2, brush=pg.mkBrush(51, 51, 51)))
        if self.S is not None:
            rects(p, [self.S.fromSeconds], [self.S.toSeconds], yl[0], yl[1], (51, 128, 255, 77), pen=(0, 77, 255), z=5)
        if self.LE is not None and len(self.LE):
            E = self.LE
            tf = E["t_file"].to_numpy()
            tc = tf[E["isComment"].to_numpy() & (tf >= 0) & (tf <= O.totalSeconds)]
            vlines(p, tc, yl[1] - 0.3 * (yl[1] - yl[0]), yl[1], PURPLE, z=10)
        ax = p.getAxis("bottom")
        ax.tmax = O.totalSeconds
        ax.t0 = 0
        p.vb.setRange(xRange=xlv, yRange=yl, padding=0)
        self._ov_title = (has_zero, xlv)
        self._ov_label(p)

    def _ov_label(self, p=None):
        p = self.pOv if p is None else p
        if self.O is None or not hasattr(self, "_ov_title"):
            return
        has_zero, xlv = self._ov_title
        O = self.O
        hrs = O.totalSeconds >= 3600
        unit = p.getAxis("bottom").unit
        if self.ovXL is None:
            ws = f"whole file ({fmt_clock(O.totalSeconds, hrs, True)})"
        else:
            ws = f"{fmt_clock(xlv[0], hrs, True)} - {fmt_clock(xlv[1], hrs, True)} of {fmt_clock(O.totalSeconds, hrs, True)}"
        set_title(p, f"Channel {self.ch}, {ws}, time in {unit}, {'force - zero force' if has_zero else 'sensor signal'}"
                  "   (green = rocker at rest, blue = loaded window, purple = comments)")

    # =================================================================================================== keyboard
    _NAV_KEYS = {QtCore.Qt.Key.Key_Left: "left", QtCore.Qt.Key.Key_Right: "right", QtCore.Qt.Key.Key_Up: "up",
                 QtCore.Qt.Key.Key_Down: "down"}
    _KEEP_KEYS = (QtWidgets.QLineEdit, QtWidgets.QAbstractSpinBox, QtWidgets.QComboBox, QtWidgets.QAbstractItemView,
                  QtWidgets.QTextEdit, QtWidgets.QPlainTextEdit, QtWidgets.QAbstractSlider)

    def eventFilter(self, obj, ev):
        """arrow keys in this window (not in edit fields, lists and combo boxes): navigation on the time axis"""
        try:
            if ev.type() == QtCore.QEvent.Type.KeyPress and ev.key() in self._NAV_KEYS and \
                    isinstance(obj, QtWidgets.QWidget) and obj.window() is self and \
                    not isinstance(QtWidgets.QApplication.focusWidget(), self._KEEP_KEYS):
                ext = bool(ev.modifiers() & QtCore.Qt.KeyboardModifier.ShiftModifier)
                if self.on_key(self._NAV_KEYS[ev.key()], ext):
                    return True
        except RuntimeError:  # window being deleted
            return False
        return super().eventFilter(obj, ev)

    def _mouse_over(self, plot, view):
        pos = view.mapFromGlobal(QtGui.QCursor.pos())
        if not view.rect().contains(pos):
            return False
        return plot.vb.sceneBoundingRect().contains(view.mapToScene(pos))

    def _nav_buttons(self):
        """buttons under the force plot (as the arrow keys): loaded window (selection) left / right = move by half its
        length (shift + click: extend on that side), middle = zoom in / out. Returns the proxy item for the plot
        layout."""
        row = QtWidgets.QWidget()
        row.setStyleSheet("background: transparent")
        hl = QtWidgets.QHBoxLayout(row)
        hl.setContentsMargins(62, 1, 50, 1)  # aligned with the plot area (left axis 62 px, right axis 50 px)
        hl.setSpacing(4)
        self.bNav = {}
        for key, text, tip in (
                ("left", "\u25C0", "loaded window (selection): move it to the left by half its length (shift + "
                                    "click: extend it to the left; key: left arrow)"),
                (None, None, None),
                ("up", "\u2192\u2190", "loaded window (selection): zoom in to half its length around the centre "
                                         "(key: up arrow)"),
                ("down", "\u2190\u2192", "loaded window (selection): zoom out to twice its length (key: down arrow)"),
                (None, None, None),
                ("right", "\u25B6", "loaded window (selection): move it to the right by half its length (shift + "
                                     "click: extend it to the right; key: right arrow)")):
            if key is None:
                hl.addStretch(1)
                continue
            b = QtWidgets.QPushButton(text)
            b.setFixedSize(34, 22)
            b.setFocusPolicy(QtCore.Qt.FocusPolicy.NoFocus)  # the arrow keys stay with the plots
            b.setStyleSheet("QPushButton { background: white; border: 1px solid #aaa; border-radius: 3px; font-size: 9pt }"
                            " QPushButton:pressed { background: #ddd }")
            b.setToolTip(tip)
            b.clicked.connect((lambda k: (lambda *_: self.on_nav_button(k)))(key))
            hl.addWidget(b)
            self.bNav[key] = b
        proxy = QtWidgets.QGraphicsProxyWidget()
        proxy.setWidget(row)
        return proxy

    def on_nav_button(self, key, ext=None):
        """button under the force plot: as the arrow key in the force plot; shift + click on the left / right button
        extends the time axis instead of moving it (ext: given by tests)"""
        if ext is None:
            ext = key in ("left", "right") and _shift_held()
        self.nav_window(key, ext)

    def nav_window(self, key, ext):
        """arrow keys in the force plot and the buttons under it: change the loaded window (= selection in the overview
        and analysed range): left / right = move it by half its length (ext / shift: extend it on that side), up / down
        = zoom in / out (half / twice its length around the centre, at least 1 s); the window is read again"""
        if self.H is None or self.S is None:
            self.status("Load a time window first.")
            return
        self.load_window(nav_step((float(self.S.fromSeconds), float(self.S.toSeconds)), key, ext,
                                  (0.0, float(self.H.totalSeconds)), 1.0))

    def on_key(self, key, ext):
        """left / right arrow: move the loaded window by half its length; ext (shift): extend it by half its length
        on that side; up / down: zoom in / out (half / twice its length). Mouse over the overview: the time axis of the
        overview; otherwise the loaded window (= selection in the overview, analysed range), read again. Returns True
        if the key was used."""
        if self.H is None:
            return False
        if self.O is not None and self._mouse_over(self.pOv, self.glTop):
            lim = (0.0, float(self.O.totalSeconds))
            a, b = nav_step(self.pOv.vb.viewRange()[0], key, ext, lim, 5)
            self.ovXL = None if (b - a) >= 0.999 * (lim[1] - lim[0]) else (a, b)
            self.plot_overview()
            self._ov_timer.start(400)
            return True
        if self.S is None:
            return False
        self.nav_window(key, ext)  # force plot: the loaded window (selection in the overview)
        return True

    def load_window(self, w):
        """read the window w (s): From / To, a zoomed overview moves along; analysed range = the whole window"""
        w = [max(0.0, float(w[0])), min(float(self.H.totalSeconds), float(w[1]))]
        if w[1] - w[0] > 4 * 3600:
            self.status("Window longer than 4 h: use the command line version (mda) for long ranges.")
            return
        if abs(w[0] - self.S.fromSeconds) < 1e-6 and abs(w[1] - self.S.toSeconds) < 1e-6:
            return  # start / end of the file
        self._follow_overview(w)
        self.eFrom.setText(f"{w[0]:.3f}")
        self.eTo.setText(f"{w[1]:.3f}")
        self.on_load()

    def _follow_overview(self, w):
        """zoomed overview: move it along when the loaded window w leaves the visible part"""
        ov = self.ovXL
        if self.O is None or ov is None or (w[0] >= ov[0] and w[1] <= ov[1]):
            return
        T = float(self.O.totalSeconds)
        span = max(ov[1] - ov[0], 1.25 * (w[1] - w[0]))
        if w[1] > ov[0] + span:
            a = w[1] + 0.1 * span - span
        else:
            a = min(ov[0], w[0] - 0.1 * span)
        a = min(max(a, 0.0), T - span)
        self.ovXL = None if span >= 0.999 * T else (a, a + span)
        self._ov_timer.start(400)

    # =================================================================================================== mouse
    def _wheel_main(self, x0, n, mods):
        if self.S is None:
            return
        lim = (self.S.fromSeconds, self.S.toSeconds)
        self._zoom(self.pMain.vb, x0, n, mods, lim, 0.3)

    def _zoom(self, vb, x0, n, mods, lim, min_span):
        xl = vb.viewRange()[0]
        if mods & QtCore.Qt.KeyboardModifier.ShiftModifier:
            xl = [xl[0] + n * 0.15 * (xl[1] - xl[0]), xl[1] + n * 0.15 * (xl[1] - xl[0])]
        else:
            f = 1.25 ** n
            xl = [x0 + (xl[0] - x0) * f, x0 + (xl[1] - x0) * f]
        span = min(max(xl[1] - xl[0], min_span), lim[1] - lim[0])
        a = min(max(xl[0], lim[0]), lim[1] - span)
        vb.setXRange(a, a + span, padding=0)
        return a, a + span

    def _wheel_ov(self, x0, n, mods):
        if self.O is None:
            return
        lim = (0, self.O.totalSeconds)
        a, b = self._zoom(self.pOv.vb, x0, n, mods, lim, 5)
        self.ovXL = None if (b - a) >= 0.999 * (lim[1] - lim[0]) else (a, b)
        self.plot_overview()
        self._ov_timer.start(400)

    def _load_detail(self):
        if self.O is None or self.H is None:
            return
        if self.ovXL is None:
            self.Od = None
            return
        span = self.ovXL[1] - self.ovXL[0]
        if span / self.O.binSeconds > 1500:
            return
        Od = self.Od
        if Od is not None and Od.range[0] <= self.ovXL[0] and Od.range[1] >= self.ovXL[1] and Od.binSeconds <= span / 1500:
            return
        r = (max(0.0, self.ovXL[0] - 0.25 * span), min(self.H.totalSeconds, self.ovXL[1] + 0.25 * span))
        b = max(2 / self.H.samplingRate, span / 3000)
        old = self.lStatus.text()
        self.status("Reading the zoomed part of the overview ...")
        try:
            Od = read_mdd(self.H, "overview", [b, r[0], r[1]], self.opts)
            Od.range = r
            self.Od = Od
        except Exception as e:  # noqa: BLE001
            self.Od = None
            self._err("Overview: ", e)
            return
        self.status(old)
        self.plot_overview()

    def _drag_patch(self, plot, x0, x):
        yl = plot.vb.viewRange()[1]
        if self._drag_item is not None:
            try:
                self._drag_item.getViewBox().removeItem(self._drag_item)
            except Exception:  # noqa: BLE001
                pass
        self._drag_item = rects(plot, [min(x0, x)], [max(x0, x)], yl[0], yl[1], (51, 128, 255, 64), pen=(51, 128, 255),
                                z=50)

    def _end_drag(self):
        if self._drag_item is not None:
            try:
                vb = self._drag_item.getViewBox()
                if vb is not None:
                    vb.removeItem(self._drag_item)
            except Exception:  # noqa: BLE001
                pass
            self._drag_item = None

    def _clamp(self, vb, x):
        xl = vb.viewRange()[0]
        return min(max(x, xl[0]), xl[1])

    def _drag_main(self, phase, x0, x, button):
        if self.S is None or not self.rbRange.isChecked():
            return
        x0 = self._clamp(self.pMain.vb, x0)
        x = self._clamp(self.pMain.vb, x)
        if phase in ("start", "move"):
            self._drag_patch(self.pMain, x0, x)
            return
        self._end_drag()
        xl = self.pMain.vb.viewRange()[0]
        if abs(x - x0) < 0.003 * (xl[1] - xl[0]):
            return
        self.range = sorted([x0, x])
        self.refresh(False)

    def _drag_ov(self, phase, x0, x, button):
        if self.O is None:
            return
        x0 = self._clamp(self.pOv.vb, x0)
        x = self._clamp(self.pOv.vb, x)
        if phase in ("start", "move"):
            self._drag_patch(self.pOv, x0, x)
            return
        self._end_drag()
        xl = self.pOv.vb.viewRange()[0]
        if abs(x - x0) < 0.003 * (xl[1] - xl[0]):
            return
        a, b = sorted([x0, x])
        self.eFrom.setText(f"{a:.1f}")
        self.eTo.setText(f"{b:.1f}")
        self.on_load()

    def _click_main(self, x, y, button, double, screen_pos):
        if self.H is None:
            return
        if button == QtCore.Qt.MouseButton.RightButton:
            self.alt_pt = (x, y)
            self._context_menu("force", screen_pos)
            return
        if double:
            if self.S is not None:
                self.pMain.vb.setXRange(self.S.fromSeconds, self.S.toSeconds, padding=0)
            return
        if button == QtCore.Qt.MouseButton.LeftButton and self.rbToggle.isChecked() and self.S is not None:
            self.toggle_at(self._clamp(self.pMain.vb, x))

    def _click_other(self, name, x, y, button, double, screen_pos):
        if self.H is None:
            return
        if button == QtCore.Qt.MouseButton.RightButton:
            self._context_menu(name, screen_pos)
        elif double and self.S is not None:
            self.pMain.vb.setXRange(self.S.fromSeconds, self.S.toSeconds, padding=0)

    def _click_ov(self, x, y, button, double, screen_pos):
        if self.H is None:
            return
        if button == QtCore.Qt.MouseButton.RightButton:
            self._context_menu("overview", screen_pos)
        elif double and self.O is not None:
            self.ovXL = None
            self.plot_overview()

    def _context_menu(self, name, screen_pos):
        m = QtWidgets.QMenu(self)
        if name == "force":
            if any(math.isnan(v) for v in self.alt_pt):
                t = "Set as zero force (y at the mouse pointer)"
            else:
                t = f"Set as zero force here (y = {self.alt_pt[1]:.0f} {MU}N in the plot)"
            m.addAction(t, self.set_zero_at_click)
            m.addAction("Zero force from the log file (Offset)", self.reset_zero)
            m.addSeparator()
            m.addAction("Set mean beat shape of the selected contractions as reference", self.set_reference)
            m.addAction("Show reference beat / deviating contractions ...", self.show_reference)
            m.addAction("Remove reference beat of this channel", self.clear_reference)
            m.addSeparator()
        if name != "ep":
            m.addAction("Save this plot (.png / .jpg / .tif / .pdf) ...", lambda: self.save_plots(name))
            if name != "overview":
                m.addAction("Export data of this plot (.xlsx / .csv / .txt) ...", lambda: self.export_plot_data(name))
            m.addSeparator()
        m.addAction("Save all plots ...", lambda: self.save_plots("all"))
        m.exec(screen_pos.toPoint() if hasattr(screen_pos, "toPoint") else screen_pos)

    def toggle_at(self, x):
        """exclude / include the contraction next to x (click in the force plot)."""
        if self.B is None or len(self.B) == 0:
            return
        xl = self.pMain.vb.viewRange()[0]
        tp = self.B["t_peak"].to_numpy()
        k = int(np.argmin(np.abs(tp - x)))
        if abs(tp[k] - x) > max(0.15, 0.01 * (xl[1] - xl[0])):
            return
        hit = [t for t in self.manual_off if abs(t - tp[k]) < 1e-6]
        if hit:
            self.manual_off = [t for t in self.manual_off if abs(t - tp[k]) >= 1e-6]
        else:
            self.manual_off.append(float(tp[k]))
        self.refresh(False)

    # =================================================================================================== reference
    def set_reference(self):
        if self.B is None:
            self.status("Load a time window first.")
            return
        rows = np.flatnonzero(self.B["included"].to_numpy(bool) & self.in_range() & ~self.is_manual())
        try:
            R = rb.create(self.C, self.B, rows, self.ref_align)
        except Exception as e:  # noqa: BLE001
            self._err("Reference: ", e)
            return
        R.source = f"{os.path.basename(self.H.file)}, channel {self.ch}, {R.source}"
        refs = [r for r in (self.opts.referenceBeat or []) if r["channel"] != self.ch]
        self.opts.referenceBeat = refs + [R]
        self.analyze(False)
        self.status(f"Reference beat of channel {self.ch}: mean of {R.n} contractions, aligned at the "
                    f"{'stimulus' if R.align == 'stimulus' else '50 % upstroke'}. Deviations: table, lower plot "
                    "(ref...Deviation...), magenta circles.")
        self.show_reference()

    def clear_reference(self):
        refs = [r for r in (self.opts.referenceBeat or []) if r["channel"] != self.ch]
        self.opts.referenceBeat = refs or None
        if self.S is not None:
            self.analyze(False)
        if self.win_ref is not None:
            self.win_ref.draw()
        self.status(f"Reference beat of channel {self.ch} removed.")

    def current_reference(self):
        refs = [r for r in (self.opts.referenceBeat or []) if r["channel"] == self.ch]
        return refs[0] if refs else None

    def set_channel_reference(self, R):
        refs = [r for r in (self.opts.referenceBeat or []) if r["channel"] != self.ch]
        self.opts.referenceBeat = refs + [R] if R is not None else (refs or None)

    def show_reference(self):
        from .reference_window import ReferenceWindow
        if self.win_ref is None:
            self.win_ref = ReferenceWindow(self)
        self.win_ref.show()
        self.win_ref.raise_()
        self.win_ref.draw()

    # =================================================================================================== windows
    def on_overlay(self):
        from .overlay import OverlayWindow
        if self.win_overlay is not None and self.win_overlay.isVisible():
            if self.win_overlay.add_group():
                self.win_overlay.draw()
            self.win_overlay.raise_()
            return
        self.win_overlay = OverlayWindow(self)
        if not self.win_overlay.add_group():
            self.win_overlay = None
            return
        self.win_overlay.show()
        self.win_overlay.draw()

    def overlay_channels(self, chs):
        """overlay of the analysed range in channels chs (opens the overlay window; scripts / tests)"""
        from .overlay import OverlayWindow
        if self.win_overlay is None or not self.win_overlay.isVisible():
            self.win_overlay = OverlayWindow(self)
        self.win_overlay.set_channels(chs)
        self.win_overlay.show()
        self.win_overlay.raise_()

    def analyze_other(self, c):
        """channel c of the loaded window with the settings of the main window (threshold and zero force of channel
        c)"""
        optsC = Struct(self.opts)
        optsC.zeroForce = self.zero_of(c)
        optsC.threshold = self.thr_of(c)
        Sa = self.S
        if self.opts.rockerFilter:
            Sa, _ = self.rocker_filtered(optsC, c)
        return analyze_channel(Sa, c, None, optsC)

    def on_trend(self):
        if self.H is None:
            self.status("Open a file first.")
            return
        from .trend import TrendWindow
        if self.win_trend is not None and self.win_trend.isVisible():
            self.win_trend.raise_()
            return
        self.win_trend = TrendWindow(self)
        self.win_trend.show()

    def on_protocols(self):
        if self.H is None:
            self.status("Open a file first.")
            return
        from .protocols_window import ProtocolWindow
        if self.win_protocols is not None and self.win_protocols.isVisible() and \
                self.win_protocols.windowTitle().endswith(os.path.basename(self.H.file)):
            self.win_protocols.raise_()
            return
        if self.win_protocols is not None:
            self.win_protocols.close()
        self.win_protocols = ProtocolWindow(self)
        self.win_protocols.show()

    def on_comments(self):
        if self.H is None:
            self.status("Open a file first.")
            return
        from .dialogs import CommentsWindow
        if self.win_comments is None:
            self.win_comments = CommentsWindow(self)
        self.win_comments.refresh_file()
        self.win_comments.show()
        self.win_comments.raise_()

    def goto_time(self, t, text, clock):
        H = self.H
        if math.isnan(t) or t < 0 or t > H.totalSeconds:
            self.status(f'"{text}" ({t:.1f} s) is outside the recording (0 - {H.totalSeconds:.0f} s).')
            return
        ln = 60.0 if self.S is None else self.S.toSeconds - self.S.fromSeconds
        ln = min(max(ln, 30.0), 3600.0)
        fr = max(0.0, t - 0.2 * ln)
        to = min(H.totalSeconds, fr + ln)
        self.hiT = t
        self.eFrom.setText(f"{fr:.1f}")
        self.eTo.setText(f"{to:.1f}")
        self.on_load()
        self.raise_()
        self.status(f"Comment {clock} ({t:.1f} s in the file): {text}")

    def on_labels(self):
        if self.H is None:
            self.status("Open a file first.")
            return
        from .dialogs import LabelsDialog
        if self.win_labels is None:
            self.win_labels = LabelsDialog(self)
        self.win_labels.show()
        self.win_labels.raise_()

    def labels_applied(self, L):
        self.Lbl = L
        if self.B is not None:
            self.update_summary()
        self.status("Labels applied (columns of the exported tables).")

    def on_show_table(self):
        if self.B is None:
            return
        from .dialogs import TableWindow
        T = self.range_table()
        w = TableWindow(T, f"Channel {self.ch}: contractions {self.range[0]:.1f} - {self.range[1]:.1f} s", self)
        self._tables = [t for t in getattr(self, "_tables", []) if t.isVisible()] + [w]  # keep a reference
        w.show()

    def closeEvent(self, ev):
        """closing the main window closes its other windows (overlay, trend, reference, comments, labels, tables)."""
        for nm in ("win_overlay", "win_trend", "win_ref", "win_comments", "win_labels", "win_protocols"):
            x = getattr(self, nm, None)
            if x is not None:
                try:
                    x.close()
                except RuntimeError:  # already deleted
                    pass
        for t in getattr(self, "_tables", []):
            try:
                t.close()
            except RuntimeError:
                pass
        self._tables = []
        try:
            QtWidgets.QApplication.instance().removeEventFilter(self)
        except RuntimeError:
            pass
        super().closeEvent(ev)

    def on_help(self):
        from .dialogs import help_text
        d = QtWidgets.QDialog(self)
        d.setWindowTitle("MyoDishAnalysis - help")
        d.resize(820, 640)
        v = QtWidgets.QVBoxLayout(d)
        t = QtWidgets.QTextBrowser()
        t.setPlainText(help_text())
        v.addWidget(t)
        d.show()

    # =================================================================================================== export
    def ask_file(self, kind, what):
        from .dialogs import ask_file
        return ask_file(self, kind, what)

    def on_export(self):
        if self.B is None:
            self.status("Nothing to export.")
            return
        n = os.path.splitext(os.path.basename(self.H.file))[0]
        d = os.path.join(self.last_dir, f"{n}_ch{self.ch}_{self.range[0]:.0f}-{self.range[1]:.0f}s.xlsx")
        fn, _ = QtWidgets.QFileDialog.getSaveFileName(self, "Export contractions", d, "Excel (*.xlsx);;text (*.csv)")
        if not fn:
            return
        T = self.range_table()
        Sm = self.summary_row()
        info = dict(self.H)
        info["options"] = self.opts
        info["labels"] = self.Lbl
        try:
            files = write_results(fn, T, Sm, info)
            self.status("Written: " + ", ".join(files))
        except Exception as e:  # noqa: BLE001
            self._err("Error: ", e)

    def on_all_channels(self):
        if self.S is None:
            self.status("Load a time window first.")
            return
        n = os.path.splitext(os.path.basename(self.H.file))[0]
        d = os.path.join(self.last_dir, f"{n}_allChannels_{self.range[0]:.0f}-{self.range[1]:.0f}s.xlsx")
        fn, _ = QtWidgets.QFileDialog.getSaveFileName(self, "All channels", d, "Excel (*.xlsx);;text (*.csv)")
        if not fn:
            return
        self.status("Analysing all channels ...")
        try:
            o = dict(self.opts)
            o["zeroForce"] = [self.zero_of(int(c)) for c in self.H.dataChannels]  # NaN = Offset of the log file
            o["threshold"] = self.thr_of([int(c) for c in self.H.dataChannels])  # NaN = auto
            myodish_analysis(self.H.file, None, self.range[0], self.range[1], output=fn, quiet=True,
                                 metadata=self.Lbl, **o)
            self.status(f"All channels written to {os.path.basename(fn)} (same settings, manual exclusions not applied).")
        except Exception as e:  # noqa: BLE001
            self._err("Error: ", e)

    def on_copy(self):
        if self.B is None:
            return
        Sm = self.summary_row().iloc[0]
        lines = [f"file\t{os.path.basename(self.H.file)}", f"channel\t{self.ch}",
                 f"range (s)\t{self.range[0]:.2f}\t{self.range[1]:.2f}", f"n contractions\t{int(Sm.nContractions)}",
                 f"extra beats\t{int(Sm.nExtraBeats)}\tof {int(Sm.nDetected)} contractions\t{Sm.extraBeats_percent:.3g} %",
                 f"missed beats\t{int(Sm.nMissedBeats)}\tof {int(Sm.nStimuli)} stimuli\t{Sm.missedBeats_percent:.3g} %",
                 f"uncertain\t{int(Sm.nUncertain)}\tstimulated {int(Sm.nStimulatedUncertain)}\textra "
                 f"{int(Sm.nExtraBeatsUncertain)}\tmissed {int(Sm.nMissedBeatsUncertain)}"]
        for nm in [c for c in self.Lbl.columns if c != "channel"]:
            v = Sm.get(nm, "")
            if isinstance(v, float):
                v = "" if math.isnan(v) else f"{v:.3f}"
            if v:
                lines.append(f"{nm}\t{v}")
        has_ref = self.C.get("referenceBeat") is not None
        lines.append("parameter\tmean\tSD\tn\tunit" + ("\trelative to reference" if has_ref else ""))
        for nm, u, _ in PARAMETERS:
            ln = f"{nm}\t{Sm[nm + '_mean']:.6g}\t{Sm[nm + '_SD']:.6g}\t{int(Sm[nm + '_n'])}\t{u}"
            if has_ref:
                c = self.rel_cell(Sm, nm)
                c = c[1:] + " uN" if c.startswith("Δ") else (c + " %" if c else "")
                ln += "\t" + c
            lines.append(ln)
        QtWidgets.QApplication.clipboard().setText("\n".join(lines))
        self.status("Summary copied to the clipboard (tab separated).")

    def save_plots(self, which):
        from .dialogs import save_plot_images
        save_plot_images(self, which)

    def export_plot_data(self, which):
        from .dialogs import export_plot_data
        export_plot_data(self, which)

    # =================================================================================================== EP recording
    def on_open_ep(self):
        if self.H is None:
            self.status("Open the .mdd file first: the EP recording is aligned to its stimuli.")
            return
        d = os.path.splitext(self.H.file)[0] + ".mat"
        if not os.path.isfile(d):
            d = os.path.dirname(self.H.file)
        fn, _ = QtWidgets.QFileDialog.getOpenFileName(self, "EP recording (LabChart export)", d,
                                                      "LabChart export (*.mat);;all files (*)")
        if fn:
            self.open_ep(fn)

    def open_ep(self, ep_file):
        if not ep_file:
            self.on_close_ep()
            return
        if self.H is None:
            self.status("Open the .mdd file first: the EP recording is aligned to its stimuli.")
            return
        self.status("EP recording: reading and aligning the stimuli ...")
        try:
            EP = read_ep_recording(ep_file, self.H, self.opts, mddChannel=self.ch)
        except Exception as e:  # noqa: BLE001
            self._err("EP recording: ", e)
            return
        self.EP = EP
        self.show_ep(True)
        tEP = (EP.t0, EP.t0 + (EP.V.size - 1) * EP.dt)
        if self.S is None or self.S.t[-1] < tEP[0] or self.S.t[0] > tEP[1]:
            self.eFrom.setText(f"{max(0, math.floor(tEP[0])):.0f}")
            self.eTo.setText(f"{min(self.H.totalSeconds, math.ceil(tEP[1])):.0f}")
            self.on_load()
        else:
            self.analyze(False)
        msg = EP.message
        if self.B is not None and "AP_note" in self.B.columns:
            msg += f" APD90: {int(np.sum(~np.isnan(self.B['APD90'].to_numpy(float))))}/{len(self.B)} contractions."
        self.status(msg)

    def on_close_ep(self):
        if self.EP is None and not self.epBox.isVisible():
            return
        self.EP = None
        self.ep_marks = None
        self.show_ep(False)
        if self.S is not None:
            self.analyze(False)
        self.status("EP recording removed.")

    def show_ep(self, on):
        if on == self.epBox.isVisible():
            return
        g = self.geometry()
        dH = 330
        if on:
            scr = self.screen().availableGeometry() if self.screen() is not None else None
            newH = g.height() + dH
            if scr is not None:
                newH = min(newH, scr.height() - 40)
            self.epBox.setVisible(True)
            self.epBox.setMinimumHeight(220)
            self._h_before_ep = g.height()
            self.resize(g.width(), max(newH, self.minimumSizeHint().height()))
            self.pPar.getAxis("bottom").show_labels = False
            self.pPar.getAxis("bottom").picture = None
        else:
            self.epBox.setVisible(False)
            self.epBox.setMinimumHeight(0)
            h0 = getattr(self, "_h_before_ep", g.height() - dH)
            self.pPar.getAxis("bottom").show_labels = True
            self.pPar.getAxis("bottom").picture = None
            self.pPar.getAxis("bottom").update()
            self.resize(g.width(), max(500, h0))
        self._x_label()

    def draw_ep(self):
        if self.EP is None or not self.epBox.isVisible():
            return
        EP = self.EP
        self.pEPv.clear()
        self.pEPs.clear()
        xl = self.pMain.vb.viewRange()[0]
        if self.S is None:
            xl = (EP.t0, EP.t0 + (EP.V.size - 1) * EP.dt)
        tv, v = self._ep_segment(EP.V, xl)
        ts, sv = self._ep_segment(EP.stim, xl)
        if tv.size:
            self.pEPv.plot(tv, v, pen=pg.mkPen((0, 77, 191), width=1))
        if ts.size:
            self.pEPs.plot(ts, sv, pen=pg.mkPen((204, 0, 0), width=1))
        self.pEPv.setLabel("left", f"{EP.labelV} ({EP.unitV})")
        self.pEPs.setLabel("left", f"{EP.labelStim} ({EP.unitStim})")
        set_title(self.pEPv, "no EP data in this time range" if v.size == 0 else "", 9)
        if v.size:
            lo, hi = float(np.min(v)), float(np.max(v))
            d = max(hi - lo, 1)
            self.pEPv.vb.setYRange(lo - 0.05 * d, hi + 0.05 * d, padding=0)
        if sv.size:
            lo, hi = float(np.min(sv)), float(np.max(sv))
            d = max(hi - lo, 1e-6)
            self.pEPs.vb.setYRange(lo - 0.05 * d, hi + 0.05 * d, padding=0)
        info = list(EP.info)
        if self._draw_ap_marks(xl):
            info.append("AP: ▲ upstroke, ▼ V_max, o APD25/50/90")
        self.lEP.setText("\n".join(info))
        self._x_label()

    def _ep_segment(self, x, xl):
        EP = self.EP
        n = np.size(x)
        if n == 0:
            return np.zeros(0), np.zeros(0)
        k1 = max(0, math.floor((xl[0] - EP.t0) / EP.dt))
        k2 = min(n - 1, math.ceil((xl[1] - EP.t0) / EP.dt))
        if k2 < k1:
            return np.zeros(0), np.zeros(0)
        k = np.arange(k1, k2 + 1)
        nb = 4000
        if k.size <= 5 * nb:
            return EP.t0 + k * EP.dt, np.asarray(x, float)[k]
        m = (k.size // nb) * nb
        k = k[:m]
        X = np.asarray(x, float)[k].reshape(nb, -1)
        mn = X.min(axis=1)
        mx = X.max(axis=1)
        tb = EP.t0 + k[::X.shape[1]] * EP.dt
        t = np.c_[tb, tb + (X.shape[1] - 1) * EP.dt].ravel()
        return t, np.c_[mn, mx].ravel()

    def _draw_ap_marks(self, xl):
        M = self.ep_marks
        B = self.B
        if M is None or B is None or "t_AP" not in B.columns:
            return False
        tm = np.array([np.nanmax([m.tOn, m.tAct]) if not (math.isnan(m.tOn) and math.isnan(m.tAct)) else math.nan
                       for m in M])
        with np.errstate(invalid="ignore"):
            vis = np.flatnonzero((tm >= xl[0] - 0.5) & (tm <= xl[1]))
        if vis.size == 0 or vis.size > 60:
            return False
        yl = self.pEPv.vb.viewRange()[1]
        EP = self.EP
        ref = B["AP_reference"].to_numpy()
        vmax = B["AP_Vmax"].to_numpy(float)
        for q in vis:
            m = M[q]
            if not math.isnan(m.tOn) and not math.isnan(m.tArtEnd):
                rects(self.pEPv, [m.tOn], [m.tArtEnd], yl[0], yl[1], (153, 153, 153, 64), z=-5)
            if not math.isnan(m.rmp):
                tr = m.tOn if not math.isnan(m.tOn) else m.tAct
                self.pEPv.plot([tr - 0.0105, tr - 0.0005], [m.rmp, m.rmp], pen=pg.mkPen((0, 128, 0), width=2))
            if ref[q] == "upstroke" and not math.isnan(m.tAct):
                k = min(EP.V.size - 1, max(0, mround((m.tAct - EP.t0) / EP.dt)))
                self.pEPv.addItem(pg.ScatterPlotItem([m.tAct], [float(EP.V[k])], symbol="t1", size=9,
                                                     pen=pg.mkPen((0, 128, 0)), brush=(0, 179, 0)))
            if not math.isnan(vmax[q]):
                self.pEPv.addItem(pg.ScatterPlotItem([m.tPeak], [m.vPeak], symbol="t", size=9,
                                                     pen=pg.mkPen((204, 0, 0)), brush=(230, 0, 0)))
            ok = ~np.isnan(m.tAPD)
            if ok.any():
                self.pEPv.addItem(pg.ScatterPlotItem(m.tAPD[ok], m.vAPD[ok], symbol="o", size=7,
                                                     pen=pg.mkPen((26, 26, 26)), brush=None))
        self.pEPv.vb.setYRange(yl[0], yl[1], padding=0)
        return True

    # =================================================================================================== API (tests)
    def api_set_range(self, r):
        self.range = sorted([float(r[0]), float(r[1])])
        self.refresh(False)

    def api_results(self):
        if self.B is None:
            return None, None
        return self.range_table(), self.summary_row()

    def api_zero_at(self, xy):
        self.alt_pt = tuple(xy)
        self.set_zero_at_click()
