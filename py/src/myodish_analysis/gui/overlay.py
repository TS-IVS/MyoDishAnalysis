"""Overlay of contractions: one group per added selection (channel, range, filters, exclusions) or per channel of the
analysed range (checkboxes), mean beat aligned at the stimulus (t = 0) or at the peak, or the time course of the range
(t = 0 at the first stimulus of each group); colour, line width, line style and band (SD / SEM / range) per group;
editable title, axis labels and legend; editable copy of the figure (matplotlib); export. Port of the overlay part of
MyoDishAnalysisGUI.m.

TS 2026-10-06 (channels, time course, styles, bands, texts, editable copy 2026-10-07)
"""
from __future__ import annotations

import math
import warnings

import numpy as np
import pandas as pd
import pyqtgraph as pg
from PySide6 import QtCore, QtGui, QtWidgets

from .._matlab import mround, nanmean, nanmedian, nanstd
from .timeaxis import fmt_clock
from .widgets import BLUE

MU = "µ"
COLORS = [(0, 114, 189), (217, 83, 25), (237, 177, 32), (126, 47, 142), (119, 172, 48), (77, 190, 238), (162, 20, 47)]
LINE_STYLES = ["-", "--", ":", "-."]
LINE_NAMES = ["solid", "dashed", "dotted", "dash-dot"]
QT_STYLES = {"-": QtCore.Qt.PenStyle.SolidLine, "--": QtCore.Qt.PenStyle.DashLine, ":": QtCore.Qt.PenStyle.DotLine,
             "-.": QtCore.Qt.PenStyle.DashDotLine}
BANDS = ["none", "SD", "SEM", "range"]
BAND_NAMES = ["no band", "band: mean +- SD", "band: mean +- SEM", "band: range (min - max)"]
LEGEND_NAMES = ["top right", "top left", "bottom right", "bottom left", "off"]
LEGEND_ANCHOR = {"top right": ((1, 0), (1, 0), (-10, 10)), "top left": ((0, 0), (0, 0), (10, 10)),
                 "bottom right": ((1, 1), (1, 1), (-10, -10)), "bottom left": ((0, 1), (0, 1), (10, -10))}
MPL_LEGEND = {"top right": "upper right", "top left": "upper left", "bottom right": "lower right",
              "bottom left": "lower left"}
ALIGN = ["mean beat: align at the stimulus (t = 0)", "mean beat: align at the peak (t = 0)",
         "time course of the range: t = 0 at the first stimulus"]


def band_of(band, M, SD, nn, Yall):
    """band around the mean: 'SD', 'SEM' (SD / sqrt(n)), 'range' (min - max of the traces); None for 'none' or fewer
    than 2 traces (overlayBand of MyoDishAnalysisGUI.m)."""
    if Yall.shape[0] < 2:
        return None
    if band == "SD":
        return M - SD, M + SD
    if band == "SEM":
        se = SD / np.sqrt(np.maximum(nn, 1))
        return M - se, M + se
    if band == "range":
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", RuntimeWarning)  # all-NaN columns
            lo = np.nanmin(Yall, axis=0)
            hi = np.nanmax(Yall, axis=0)
        lo = np.where(np.isnan(M), np.nan, lo)
        hi = np.where(np.isnan(M), np.nan, hi)
        return lo, hi
    return None


def finite_runs(lo, hi):
    """index ranges (a, b inclusive) of the runs of finite values of lo and hi (bandPatch)."""
    ok = np.isfinite(lo) & np.isfinite(hi)
    d = np.diff(np.r_[0, ok.astype(int), 0])
    return list(zip(np.flatnonzero(d == 1), np.flatnonzero(d == -1) - 1))


class OverlayWindow(QtWidgets.QWidget):
    def __init__(self, win):
        super().__init__()
        self.win = win
        self.groups = []
        self.next_color = 0
        self._mpl = []
        self.setWindowFlag(QtCore.Qt.WindowType.Window)
        self.setWindowTitle("MyoDishAnalysis: overlay")
        self.resize(1200, 720)
        h = QtWidgets.QHBoxLayout(self)
        left = QtWidgets.QVBoxLayout()
        h.addLayout(left, 3)
        self.pw = pg.PlotWidget()
        self.p = self.pw.getPlotItem()
        self.p.showGrid(x=True, y=True, alpha=0.25)
        self.p.getAxis("left").setWidth(72)
        for a in ("left", "bottom"):
            self.p.getAxis(a).enableAutoSIPrefix(False)  # no '(x0.001)' with typed axis labels
        self.p.addLegend(offset=(-10, 10), labelTextSize="8pt")
        left.addWidget(self.pw, 1)
        # texts of the figure (empty = automatic)
        g = QtWidgets.QGridLayout()
        left.addLayout(g)
        self.eTitle = QtWidgets.QLineEdit()
        self.eTitle.setToolTip("title of the plot (empty = automatic)")
        self.eX = QtWidgets.QLineEdit()
        self.eX.setToolTip("label of the x axis (empty = automatic)")
        self.eY = QtWidgets.QLineEdit()
        self.eY.setToolTip("label of the y axis (empty = automatic)")
        self.cLegend = QtWidgets.QComboBox()
        self.cLegend.addItems(LEGEND_NAMES)
        self.cLegend.setToolTip("position of the legend")
        g.addWidget(QtWidgets.QLabel("title"), 0, 0)
        g.addWidget(self.eTitle, 0, 1, 1, 3)
        g.addWidget(QtWidgets.QLabel("legend"), 0, 4)
        g.addWidget(self.cLegend, 0, 5)
        g.addWidget(QtWidgets.QLabel("x axis"), 1, 0)
        g.addWidget(self.eX, 1, 1)
        g.addWidget(QtWidgets.QLabel("y axis"), 1, 2)
        g.addWidget(self.eY, 1, 3, 1, 3)
        for e in (self.eTitle, self.eX, self.eY):
            e.editingFinished.connect(self.draw)
        self.cLegend.currentIndexChanged.connect(lambda *_: self.draw())
        # right: groups and settings
        v = QtWidgets.QVBoxLayout()
        h.addLayout(v, 1)
        v.addWidget(QtWidgets.QLabel("Groups (one per added selection or channel):"))
        self.lb = QtWidgets.QListWidget()
        self.lb.currentRowChanged.connect(lambda *_: self.show_group_style())
        v.addWidget(self.lb, 1)
        hh = QtWidgets.QHBoxLayout()
        b = QtWidgets.QPushButton("Add current selection")
        b.setToolTip("contractions selected in the main window (channel, range, filters, exclusions)")
        b.clicked.connect(self._add_draw)
        hh.addWidget(b)
        b = QtWidgets.QPushButton("Channels (same range) ...")
        b.setToolTip("channels for the analysed range of the main window (checkboxes): same settings and filters, "
                     "threshold and zero force of each channel; manual exclusions only in the channel of the main "
                     "window")
        b.clicked.connect(self.choose_channels)
        hh.addWidget(b)
        v.addLayout(hh)
        hh = QtWidgets.QHBoxLayout()
        b = QtWidgets.QPushButton("Remove group")
        b.clicked.connect(self.remove_group)
        hh.addWidget(b)
        b = QtWidgets.QPushButton("Clear all")
        b.clicked.connect(self.clear_groups)
        hh.addWidget(b)
        v.addLayout(hh)
        self.al = QtWidgets.QComboBox()
        self.al.addItems(ALIGN)
        self.al.setToolTip("time course: force of the whole range of each group, t = 0 at its first stimulus (the "
                           "channels are not stimulated at the same time)")
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
        box = QtWidgets.QGroupBox("Selected group: legend, line, band")
        gg = QtWidgets.QGridLayout(box)
        gg.addWidget(QtWidgets.QLabel("legend"), 0, 0)
        self.gName = QtWidgets.QLineEdit()
        self.gName.setToolTip("legend text of the group (empty = automatic)")
        self.gName.editingFinished.connect(lambda: self.set_group_style("name", self.gName.text()))
        gg.addWidget(self.gName, 0, 1, 1, 3)
        b = QtWidgets.QPushButton("colour ...")
        b.clicked.connect(self.pick_color)
        gg.addWidget(b, 1, 0)
        gg.addWidget(QtWidgets.QLabel("width"), 1, 1)
        self.gWidth = QtWidgets.QLineEdit("2")
        self.gWidth.setMaximumWidth(50)
        self.gWidth.setToolTip("line width of the mean (points)")
        self.gWidth.editingFinished.connect(self._width_edited)
        gg.addWidget(self.gWidth, 1, 2)
        self.gLine = QtWidgets.QComboBox()
        self.gLine.addItems(LINE_NAMES)
        self.gLine.activated.connect(lambda i: self.set_group_style("style", LINE_STYLES[i]))
        gg.addWidget(self.gLine, 1, 3)
        self.gBand = QtWidgets.QComboBox()
        self.gBand.addItems(BAND_NAMES)
        self.gBand.setToolTip("transparent band around the mean (mean beat)")
        self.gBand.activated.connect(lambda i: self.set_group_style("band", BANDS[i]))
        gg.addWidget(self.gBand, 2, 0, 1, 4)
        b = QtWidgets.QPushButton("line and band for all groups")
        b.setToolTip("width, line style and band of the selected group for all groups (colours and legends stay)")
        b.clicked.connect(self.style_to_all)
        gg.addWidget(b, 3, 0, 1, 4)
        v.addWidget(box)
        hh = QtWidgets.QHBoxLayout()
        b = QtWidgets.QPushButton("Save figure ...")
        b.clicked.connect(self.save_figure)
        hh.addWidget(b)
        b = QtWidgets.QPushButton("Export data ...")
        b.setToolTip("mean, SD, SEM, min, max, n and all single traces of every group (time course: the traces): "
                     ".xlsx / .csv / .txt")
        b.clicked.connect(self.export)
        hh.addWidget(b)
        b = QtWidgets.QPushButton("Edit figure ...")
        b.setToolTip("copy of the plot as a matplotlib figure: edit titles, axes, lines and legend (toolbar: figure "
                     "options), save as .png / .pdf / .svg ...")
        b.clicked.connect(self.edit_figure)
        hh.addWidget(b)
        v.addLayout(hh)
        self.tx = QtWidgets.QLabel("")
        self.tx.setWordWrap(True)
        v.addWidget(self.tx)

    # ------------------------------------------------------------------------------------------------ groups
    def _add_draw(self):
        if self.add_group():
            self.draw()

    def add_group(self):
        """current selection of the main window --> new overlay group."""
        w = self.win
        if w.B is None or w.C is None:
            w.status("Load a time window first.")
            return False
        sel = np.flatnonzero(w.selected())
        if sel.size == 0:
            w.status("No contraction selected.")
            return False
        return self.add_group_of(w.B, w.C, w.ch, sel)

    def add_group_of(self, B, C, ch, sel):
        """new overlay group of channel ch: segments of the filtered signal around the selected contractions (peak - 1 s
        ... peak + 1.6 s) and the force of the analysed range (time course, t = 0 at its first stimulus)."""
        w = self.win
        S = w.S
        rng = (float(w.range[0]), float(w.range[1]))
        tp = B["t_peak"].to_numpy()
        key = f"{ch}|{rng[0]:.4f}|{rng[1]:.4f}|{sel.size}|{np.sum(tp[sel]):.6f}"
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
        hrs = w.H.totalSeconds >= 3600
        lab = f"Ch {ch}, {fmt_clock(rng[0], hrs, True)} - {fmt_clock(rng[1], hrs, True)}, n = {sel.size}"
        L = w.Lbl
        r = np.flatnonzero(L["channel"].to_numpy(float) == ch)
        if r.size:
            for nm in ("treatment", "sliceID"):
                if nm in L.columns and isinstance(L[nm].iloc[r[0]], str) and L[nm].iloc[r[0]]:
                    lab += ", " + L[nm].iloc[r[0]]
        st = np.asarray(C.stimTimes, float)
        st = st[(st >= rng[0]) & (st <= rng[1])]
        t0 = float(st[0]) if st.size else rng[0]
        t = np.asarray(C.t, float)
        inR = (t >= rng[0]) & (t <= rng[1])
        self.next_color += 1  # default colours in the order of adding (stay when groups are removed)
        G = dict(key=key, seg=seg, dt=S.dt, pre=pre,
                 stimRel=B["t_stim"].to_numpy(float)[sel] - np.asarray(C.peakTimes)[loc],
                 dia=B["diastolicSignal"].to_numpy(float)[sel], amp=B["amplitude"].to_numpy(float)[sel],
                 zero=C.zeroForce, pp=nanmedian(B["peakToPeakInterval"].to_numpy(float)[sel]),
                 ch=int(ch), range=rng, noStim=st.size == 0, t0=t0, trT=t[inR] - t0,
                 trY=np.asarray(C.f, float)[inR], label=lab,
                 color=COLORS[(self.next_color - 1) % len(COLORS)], width=2.0, style="-", band="none", name="")
        self.groups.append(G)
        w.status(f"Overlay: group {len(self.groups)} added ({lab}).")
        return True

    def groups_of(self, ch):
        """overlay groups of channel ch for the analysed range of the main window."""
        rng = self.win.range
        return [k for k, G in enumerate(self.groups)
                if G["ch"] == ch and abs(G["range"][0] - rng[0]) < 1e-6 and abs(G["range"][1] - rng[1]) < 1e-6]

    def choose_channels(self):
        """checkboxes: channels with a group for the analysed range of the main window (ticked = added, unticked =
        removed)."""
        w = self.win
        if w.S is None or w.H is None:
            w.status("Load a time window first.")
            return
        chs = [int(c) for c in w.S.dataChannels]
        hrs = w.H.totalSeconds >= 3600
        d = QtWidgets.QDialog(self)
        d.setWindowTitle("Overlay: channels")
        lay = QtWidgets.QVBoxLayout(d)
        lab = QtWidgets.QLabel(f"Channels for the analysed range {fmt_clock(w.range[0], hrs, True)} - "
                               f"{fmt_clock(w.range[1], hrs, True)} (same settings; manual exclusions only in channel "
                               f"{w.ch}):")
        lab.setWordWrap(True)
        lay.addWidget(lab)
        cbs = []
        for c in chs:
            cb = QtWidgets.QCheckBox(f"Channel {c}")
            cb.setChecked(bool(self.groups_of(c)))
            lay.addWidget(cb)
            cbs.append(cb)
        bb = QtWidgets.QDialogButtonBox(QtWidgets.QDialogButtonBox.StandardButton.Ok |
                                        QtWidgets.QDialogButtonBox.StandardButton.Cancel)
        bb.accepted.connect(d.accept)
        bb.rejected.connect(d.reject)
        lay.addWidget(bb)
        if d.exec() != QtWidgets.QDialog.DialogCode.Accepted:
            return
        self.set_channels([c for c, cb in zip(chs, cbs) if cb.isChecked()])

    def set_channels(self, want):
        """groups of the analysed range of the main window: exactly the channels want (groups of other channels of this
        range removed); the channel of the main window with its selection, the others analysed with the same
        settings."""
        w = self.win
        if w.S is None or w.B is None:
            w.status("Load a time window first.")
            return
        chs = [int(c) for c in w.S.dataChannels]
        want = [c for c in chs if c in {int(x) for x in want}]
        for c in chs:
            if c not in want:
                for k in sorted(self.groups_of(c), reverse=True):
                    del self.groups[k]
        notes = []
        for c in want:
            if self.groups_of(c):
                continue
            if c == w.ch:
                Bx, Cx = w.B, w.C
                sel = np.flatnonzero(w.selected())
            else:
                w.status(f"Overlay: analysing channel {c} ...")
                try:
                    Bx, Cx = w.analyze_other(c)
                except Exception as e:  # noqa: BLE001
                    notes.append(f"channel {c}: {e}")
                    continue
                tp = Bx["t_peak"].to_numpy()
                s = Bx["included"].to_numpy(bool) & (tp >= w.range[0]) & (tp <= w.range[1])
                if w.ref_exclude:
                    s &= ~w.deviating_of(Bx, Cx)
                sel = np.flatnonzero(s)
            if sel.size == 0:
                notes.append(f"channel {c}: no contraction selected")
                continue
            self.add_group_of(Bx, Cx, c, sel)
        self.draw()
        if notes:
            w.status("Overlay: " + "; ".join(notes))

    def remove_group(self):
        k = self.lb.currentRow()
        if 0 <= k < len(self.groups):
            del self.groups[k]
        self.draw()

    def clear_groups(self):
        self.groups = []
        self.next_color = 0
        self.draw()

    # ------------------------------------------------------------------------------------------------ styles
    def selected_group(self):
        return min(max(0, self.lb.currentRow()), len(self.groups) - 1)

    def legend_name(self, g):
        G = self.groups[g]
        return G["name"] if G["name"] else f"{g + 1}: {G['label']}"

    def show_group_style(self):
        """controls of the selected group (legend text, line width, line style, band)."""
        ctl = (self.gName, self.gWidth, self.gLine, self.gBand)
        for c in ctl:
            c.setEnabled(bool(self.groups))
        if not self.groups:
            self.gName.setText("")
            return
        g = self.selected_group()
        G = self.groups[g]
        self.gName.setText(self.legend_name(g))
        self.gWidth.setText(f"{G['width']:g}")
        self.gLine.setCurrentIndex(LINE_STYLES.index(G["style"]))
        self.gBand.setCurrentIndex(BANDS.index(G["band"]))

    def _width_edited(self):
        try:
            v = float(self.gWidth.text())
        except ValueError:
            v = math.nan
        self.set_group_style("width", v)

    def set_group_style(self, field, value):
        if not self.groups:
            return
        g = self.selected_group()
        G = self.groups[g]
        if field == "width":
            if not math.isfinite(value) or value <= 0:
                self.show_group_style()
                self.win.status("Line width: enter a positive number.")
                return
        elif field == "name":
            value = str(value).strip()
            if value == f"{g + 1}: {G['label']}":
                value = ""  # automatic text
        if G[field] == value:
            return
        G[field] = value
        self.draw()

    def pick_color(self):
        if not self.groups:
            return
        G = self.groups[self.selected_group()]
        c = QtWidgets.QColorDialog.getColor(QtGui.QColor(*G["color"]), self, "Colour of the group")
        if c.isValid():
            self.set_group_style("color", (c.red(), c.green(), c.blue()))

    def style_to_all(self):
        if not self.groups:
            return
        G = self.groups[self.selected_group()]
        for H in self.groups:
            H["width"], H["style"], H["band"] = G["width"], G["style"], G["band"]
        self.draw()

    # ------------------------------------------------------------------------------------------------ curves
    def curves(self, G):
        """traces of one group on a common time grid (alignment, baseline, normalization as chosen)."""
        align_stim = self.al.currentIndex() != 1
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

    def trace(self, G):
        """time course of the range of one group (t = 0 at its first stimulus; baseline and normalization as chosen:
        median diastolic force / amplitude of its contractions)."""
        x, y = G["trT"], G["trY"].copy()
        if x.size == 0:
            return x, y
        if self.cBase.isChecked():
            y = y - nanmedian(G["dia"])
        elif not math.isnan(G["zero"]):
            y = y - G["zero"]
        if self.cNorm.isChecked():
            y = y / nanmedian(G["amp"])
        return x, y

    def texts(self, mode):
        """axis labels and title: the texts typed in the window, otherwise automatic."""
        xl = ["time from the stimulus (s)", "time from the peak (s)",
              "time from the first stimulus of the range (s)"][mode]
        if self.cNorm.isChecked():
            yl = "force / amplitude"
        elif self.cBase.isChecked():
            yl = f"force - diastolic force ({MU}N)"
        else:
            yl = f"force - zero force ({MU}N)"
        if mode == 2:
            tt = "force of the analysed range of each group"
        elif self.cSingle.isChecked():
            tt = "thick: mean of each group; thin: single contractions"
        else:
            tt = "mean of each group"
        user = self.eTitle.text().strip() != ""
        xl = self.eX.text() if self.eX.text().strip() else xl
        yl = self.eY.text() if self.eY.text().strip() else yl
        tt = self.eTitle.text() if user else tt
        return xl, yl, tt, user

    def content(self):
        """what is drawn (also for the editable copy): items (kind 'single' / 'band' / 'line'), x range, y range, texts,
        legend position, info lines."""
        mode = self.al.currentIndex()
        items, info = [], []
        xr = [math.inf, -math.inf]
        for g, G in enumerate(self.groups):
            col = tuple(G["color"])
            if mode == 2:
                x, y = self.trace(G)
                if x.size == 0:
                    continue
                items.append(dict(kind="line", x=x, y=y, color=col, width=G["width"], style=G["style"],
                                  name=self.legend_name(g)))
                xr = [min(xr[0], x[0]), max(xr[1], x[-1])]
                if G["noStim"]:
                    info.append(f"group {g + 1}: no stimulus in the range, t = 0 at its start")
                continue
            xg, M, SD, nn, Yall = self.curves(G)
            if self.cSingle.isChecked() and Yall.size:
                items.append(dict(kind="single", x=xg, Y=Yall, color=tuple(int(0.35 * c + 0.65 * 255) for c in col)))
            if Yall.shape[0]:
                bd = band_of(G["band"], M, SD, nn, Yall)
                if bd is not None:
                    items.append(dict(kind="band", x=xg, lo=bd[0], hi=bd[1], color=col))
                items.append(dict(kind="line", x=xg, y=M, color=col, width=G["width"], style=G["style"],
                                  name=self.legend_name(g)))
            nNo = G["seg"].shape[0] - Yall.shape[0]
            if nNo > 0:
                info.append(f"group {g + 1}: {nNo} contraction(s) without stimulus not shown")
        if mode == 2:
            xl = tuple(xr) if all(map(math.isfinite, xr)) and xr[1] > xr[0] else None
            info.insert(0, "time course: one trace per group (bands and single contractions: mean beat only)")
        else:
            L = nanmedian(np.array([G["pp"] for G in self.groups])) if self.groups else math.nan
            if math.isnan(L):
                L = 1.0
            xl = (-0.1, min(1.5, max(0.3, 0.95 * L))) if mode == 0 else (-min(0.4, 0.45 * L), min(1.5, 0.9 * L))
        # y range from the data in the visible time range (lines and bands)
        lo, hi = math.inf, -math.inf
        for it in items:
            x = it["x"]
            inx = np.ones(x.size, bool) if xl is None else (x >= xl[0]) & (x <= xl[1])
            ys = [it["Y"][:, inx]] if it["kind"] == "single" else (
                [it["lo"][inx], it["hi"][inx]] if it["kind"] == "band" else [it["y"][inx]])
            for y in ys:
                if np.any(np.isfinite(y)):
                    lo = min(lo, float(np.nanmin(y)))
                    hi = max(hi, float(np.nanmax(y)))
        yl = (lo - 0.05 * (hi - lo), hi + 0.08 * (hi - lo)) if math.isfinite(lo) and math.isfinite(hi) and hi > lo \
            else None
        xs, ys_, tt, user = self.texts(mode)
        return dict(items=items, xl=xl, yl=yl, xlabel=xs, ylabel=ys_, title=tt, user_title=user,
                    legend=LEGEND_NAMES[self.cLegend.currentIndex()], vline=mode != 1, info=info)

    def draw(self):
        p = self.p
        p.clear()
        if p.legend is not None:
            p.legend.clear()
        self.lb.blockSignals(True)
        row = self.lb.currentRow()
        self.lb.clear()
        if not self.groups:
            self.lb.blockSignals(False)
            p.setTitle('no group: select contractions in the main window and press "Add current selection"', size="9pt")
            self.tx.setText("")
            self.show_group_style()
            return
        for g, G in enumerate(self.groups):
            self.lb.addItem(f"{g + 1}: {G['label']}")
        self.lb.setCurrentRow(min(max(0, row), len(self.groups) - 1))
        self.lb.blockSignals(False)
        K = self.content()
        for it in K["items"]:
            if it["kind"] == "single":
                Y = it["Y"]
                X = np.tile(np.r_[it["x"], np.nan], Y.shape[0])
                Yv = np.c_[Y, np.full(Y.shape[0], np.nan)].ravel()
                p.plot(X, Yv, pen=pg.mkPen(it["color"], width=1), connect="finite")
            elif it["kind"] == "band":
                for a, b in finite_runs(it["lo"], it["hi"]):
                    if b - a < 1:
                        continue
                    c1 = pg.PlotCurveItem(it["x"][a:b + 1], it["lo"][a:b + 1], pen=pg.mkPen(None))
                    c2 = pg.PlotCurveItem(it["x"][a:b + 1], it["hi"][a:b + 1], pen=pg.mkPen(None))
                    p.addItem(c1)
                    p.addItem(c2)
                    p.addItem(pg.FillBetweenItem(c1, c2, brush=pg.mkBrush(*it["color"], 51)))
            else:
                pen = pg.mkPen(it["color"], width=it["width"], style=QT_STYLES[it["style"]])
                p.plot(it["x"], it["y"], pen=pen, name=it["name"] if K["legend"] != "off" else None)
        if K["vline"]:
            p.addItem(pg.InfiniteLine(0, angle=90, pen=pg.mkPen(BLUE, style=QtCore.Qt.PenStyle.DashLine)))
        if p.legend is not None:
            p.legend.setVisible(K["legend"] != "off")
            if K["legend"] != "off":
                ip, pp, off = LEGEND_ANCHOR[K["legend"]]
                p.legend.anchor(ip, pp, offset=off)
        p.setLabel("bottom", K["xlabel"])
        p.setLabel("left", K["ylabel"])
        if K["xl"] is not None and K["yl"] is not None:
            p.vb.setRange(xRange=K["xl"], yRange=K["yl"], padding=0)
        elif K["xl"] is not None:
            p.vb.setXRange(*K["xl"], padding=0)
        if K["user_title"]:
            p.setTitle(f"<b>{K['title']}</b>", size="12pt")
        else:
            p.setTitle(K["title"], size="9pt")
        self.tx.setText("\n".join(K["info"]) if K["info"] else "all contractions shown")
        self.show_group_style()

    # ------------------------------------------------------------------------------------------------ output
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

    def mpl_figure(self):
        """the overlay as a matplotlib figure (editable copy)."""
        from matplotlib.figure import Figure
        K = self.content()
        fig = Figure(figsize=(9, 6.2))
        ax = fig.add_subplot(111)
        rgb = lambda c: tuple(x / 255 for x in c)  # noqa: E731
        for it in K["items"]:
            if it["kind"] == "single":
                ax.plot(it["x"], it["Y"].T, color=rgb(it["color"]), linewidth=0.5, label="_nolegend_")
            elif it["kind"] == "band":
                ax.fill_between(it["x"], it["lo"], it["hi"], color=rgb(it["color"]), alpha=0.2, linewidth=0,
                                label="_nolegend_")
            else:
                ax.plot(it["x"], it["y"], color=rgb(it["color"]), linewidth=it["width"], linestyle=it["style"],
                        label=it["name"])
        if K["vline"]:
            ax.axvline(0, color=rgb(BLUE), linestyle="--", linewidth=0.8, label="_nolegend_")
        if K["xl"] is not None:
            ax.set_xlim(K["xl"])
        if K["yl"] is not None:
            ax.set_ylim(K["yl"])
        ax.set_xlabel(K["xlabel"])
        ax.set_ylabel(K["ylabel"])
        if K["user_title"]:
            ax.set_title(K["title"], fontsize=12, fontweight="bold")
        else:
            ax.set_title(K["title"], fontsize=9)
        ax.grid(True, alpha=0.3)
        if K["legend"] != "off" and any(it["kind"] == "line" for it in K["items"]):
            ax.legend(loc=MPL_LEGEND[K["legend"]], fontsize=8)
        fig.tight_layout()
        return fig

    def edit_figure(self):
        """copy of the plot as a matplotlib figure: titles, axes, lines and legend editable (toolbar: figure options),
        saved from its toolbar (.png / .pdf / .svg ...)."""
        if not self.groups:
            return
        from matplotlib.backends.backend_qtagg import FigureCanvasQTAgg, NavigationToolbar2QT
        fig = self.mpl_figure()
        w = QtWidgets.QWidget()
        w.setWindowFlag(QtCore.Qt.WindowType.Window)
        w.setWindowTitle("MyoDishAnalysis: overlay (editable copy)")
        lay = QtWidgets.QVBoxLayout(w)
        canvas = FigureCanvasQTAgg(fig)
        lay.addWidget(NavigationToolbar2QT(canvas, w))
        lay.addWidget(canvas, 1)
        w.resize(900, 650)
        w.show()
        self._mpl = [x for x in self._mpl if x.isVisible()] + [w]
        self.win.status("Editable copy of the overlay: toolbar button 'Edit axis, curve and image parameters' for "
                        "titles, axes, lines and legend; save from the toolbar.")

    def closeEvent(self, ev):
        for x in self._mpl:
            try:
                x.close()
            except RuntimeError:
                pass
        super().closeEvent(ev)

    def export(self):
        from .dialogs import ask_file, write_tables
        if not self.groups:
            return
        file = ask_file(self.win, "data", "overlay")
        if not file:
            return
        write_tables(self.win, file, *self.export_tables())

    def export_tables(self):
        """mean beat: mean, SD, n, SEM, min, max of every group on a common time grid + all single traces (one table per
        group); time course: the traces of all groups on a common grid; table 'groups' with labels and settings."""
        mode = self.al.currentIndex()
        dt = min(g["dt"] for g in self.groups)
        nG = len(self.groups)
        names, tabs = ["means"], [None]
        nTr = []
        if mode == 2:
            cur = [self.trace(G) for G in self.groups]
            xmin = min((c[0][0] for c in cur if c[0].size), default=0.0)
            xmax = max((c[0][-1] for c in cur if c[0].size), default=0.0)
            tt = np.arange(mround(xmin / dt), mround(xmax / dt) + 1) * dt
            Tm = pd.DataFrame({"t_from_first_stimulus_s": tt})
            for g, (x, y) in enumerate(cur):
                Tm[f"g{g + 1}"] = np.interp(tt, x, y, left=np.nan, right=np.nan) if x.size >= 2 else np.nan
                nTr.append(1 if x.size else 0)
            names[0] = "traces"
        else:
            cur = [self.curves(G) for G in self.groups]
            xmin = min((c[0][0] for c in cur if c[0].size), default=0.0)
            xmax = max((c[0][-1] for c in cur if c[0].size), default=0.0)
            tt = np.arange(mround(xmin / dt), mround(xmax / dt) + 1) * dt
            tn = "t_from_stimulus_s" if mode == 0 else "t_from_peak_s"
            Tm = pd.DataFrame({tn: tt})
            for g, c in enumerate(cur):
                xg, M, SD, nn, Yall = c
                if xg.size == 0:
                    m = sd = nk = se = mn = mx = np.full(tt.size, np.nan)
                else:
                    bd = band_of("range", M, SD, nn, Yall)
                    mn0, mx0 = bd if bd is not None else (np.full(xg.size, np.nan), np.full(xg.size, np.nan))
                    m = np.interp(tt, xg, M, left=np.nan, right=np.nan)
                    sd = np.interp(tt, xg, SD, left=np.nan, right=np.nan)
                    ii = np.clip(np.searchsorted(xg, tt), 1, max(1, xg.size - 1))
                    prev = np.clip(ii - 1, 0, xg.size - 1)
                    ii = np.clip(ii, 0, xg.size - 1)
                    ii = np.where(np.abs(xg[prev] - tt) <= np.abs(xg[ii] - tt), prev, ii)  # interp1 'nearest'
                    nk = np.where((tt >= xg[0]) & (tt <= xg[-1]), nn[ii], np.nan)
                    se = sd / np.sqrt(np.maximum(nk, 1))
                    mn = np.interp(tt, xg, mn0, left=np.nan, right=np.nan)
                    mx = np.interp(tt, xg, mx0, left=np.nan, right=np.nan)
                    Tg = pd.DataFrame(np.c_[xg, Yall.T], columns=[tn] + [f"c{k + 1}" for k in range(Yall.shape[0])])
                    names.append(f"g{g + 1}_traces")
                    tabs.append(Tg)
                Tm[f"g{g + 1}_mean"] = m
                Tm[f"g{g + 1}_SD"] = sd
                Tm[f"g{g + 1}_n"] = nk
                Tm[f"g{g + 1}_SEM"] = se
                Tm[f"g{g + 1}_min"] = mn
                Tm[f"g{g + 1}_max"] = mx
                nTr.append(Yall.shape[0])
        tabs[0] = Tm
        a = ["aligned at the stimulus (t = 0)", "aligned at the peak (t = 0)",
             "time course of the range, t = 0 at the first stimulus"][mode]
        b = "diastolic force subtracted" if self.cBase.isChecked() else "zero force subtracted (if known)"
        u = "normalized to the amplitude" if self.cNorm.isChecked() else "uN"
        names.append("groups")
        tabs.append(pd.DataFrame({
            "group": np.arange(1, nG + 1), "label": [G["label"] for G in self.groups],
            "legend": [self.legend_name(g) for g in range(nG)], "channel": [G["ch"] for G in self.groups],
            "from_s": [G["range"][0] for G in self.groups], "to_s": [G["range"][1] for G in self.groups],
            "firstStimulus_s": [G["t0"] for G in self.groups], "nTraces": nTr, "alignment": [a] * nG,
            "baseline": [b] * nG, "unit": [u] * nG, "band": [G["band"] for G in self.groups]}))
        return names, tabs
