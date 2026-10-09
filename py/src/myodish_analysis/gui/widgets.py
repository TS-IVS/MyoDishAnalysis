"""pyqtgraph building blocks of the GUI: a view box with the mouse behaviour of the MATLAB GUI (wheel = zoom the time
axis, shift + wheel = move, drag, click, double-click, right click = context menu), plot items with a time axis, a plot
with a second y axis, and drawing helpers (vertical ticks, rectangles, rotated labels).

TS 2026-10-06
"""
from __future__ import annotations

import numpy as np
import pyqtgraph as pg
from PySide6 import QtCore, QtGui, QtWidgets

from .timeaxis import TimeAxisItem

pg.setConfigOptions(antialias=False, background="w", foreground="k")

PURPLE = (140, 0, 191)
RED = (217, 0, 0)
BLUE = (0, 77, 255)
GREEN = (0, 153, 0)
GREY = (128, 128, 128)
MAGENTA = (230, 0, 230)
ORANGE = (255, 140, 0)  # uncertain contractions (high sensitivity)


class MouseViewBox(pg.ViewBox):
    """ViewBox whose mouse events are passed to callbacks (no built-in pan / zoom / menu)."""

    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.setMouseEnabled(x=False, y=False)
        self.setMenuEnabled(False)
        self.on_wheel = None      # f(x, steps, modifiers)
        self.on_drag = None       # f(phase 'start'|'move'|'finish', x0, x, button)
        self.on_click = None      # f(x, y, button, double, screen_pos)

    def wheelEvent(self, ev, axis=None):
        if self.on_wheel is None:
            ev.ignore()
            return
        p = self.mapToView(ev.pos())
        d = ev.delta() if hasattr(ev, "delta") else ev.angleDelta().y()
        steps = -d / 120.0  # wheel up (d > 0) = zoom in (MATLAB: VerticalScrollCount < 0)
        self.on_wheel(p.x(), steps, ev.modifiers())
        ev.accept()

    def mouseDragEvent(self, ev, axis=None):
        if self.on_drag is None or ev.button() != QtCore.Qt.MouseButton.LeftButton:
            ev.ignore()
            return
        ev.accept()
        x0 = self.mapToView(ev.buttonDownPos()).x()
        x = self.mapToView(ev.pos()).x()
        if ev.isStart():
            self.on_drag("start", x0, x, ev.button())
        elif ev.isFinish():
            self.on_drag("finish", x0, x, ev.button())
        else:
            self.on_drag("move", x0, x, ev.button())

    def mouseClickEvent(self, ev):
        if self.on_click is None:
            ev.ignore()
            return
        ev.accept()
        p = self.mapToView(ev.pos())
        self.on_click(p.x(), p.y(), ev.button(), ev.double(), ev.screenPos())


class ElidedLabel(QtWidgets.QLabel):
    """one-line label that shortens its text in the middle ("...") to the available width (tool tip: full text)."""

    def __init__(self, text=""):
        super().__init__()
        self._full = text
        self.setSizePolicy(QtWidgets.QSizePolicy.Policy.Ignored, QtWidgets.QSizePolicy.Policy.Preferred)
        self.setText(text)

    def setText(self, text):
        self._full = text
        self._elide()

    def full_text(self):
        return self._full

    def resizeEvent(self, ev):
        super().resizeEvent(ev)
        self._elide()

    def _elide(self):
        fm = self.fontMetrics()
        super().setText(fm.elidedText(self._full, QtCore.Qt.TextElideMode.ElideMiddle, max(10, self.width())))


class PlotArea(pg.GraphicsLayoutWidget):
    """GraphicsLayoutWidget whose size hint is its minimum size: QGraphicsView suggests the size of its scene, so plot
    areas stacked in a layout would not share the space by their stretch factors."""

    def sizeHint(self):
        return QtCore.QSize(max(200, self.minimumWidth()), max(80, self.minimumHeight()))


def time_plot(title="", show_x_labels=True, left_label="", right_width=10):
    """PlotItem with a MouseViewBox and a TimeAxisItem. right_width: width of the (empty) right axis; 50 for plots stacked
    with a TwinPlot, so that the time axes of all plots have the same length on the screen."""
    vb = MouseViewBox()
    ax = TimeAxisItem()
    ax.show_labels = show_x_labels
    p = pg.PlotItem(viewBox=vb, axisItems={"bottom": ax})
    p.hideButtons()
    p.showAxis("top", False)
    p.getAxis("left").setWidth(62)
    if left_label:
        p.setLabel("left", left_label)
    if title:
        set_title(p, title)
    f = QtGui.QFont()
    f.setPointSize(9)
    p._tick_font = f  # keep a reference (pyqtgraph stores the font object)
    for a in ("left", "bottom"):
        p.getAxis(a).setTickFont(f)
    p.showAxis("right")
    p.getAxis("right").setStyle(showValues=False)
    p.getAxis("right").setWidth(right_width)
    p.showAxis("top")
    p.getAxis("top").setStyle(showValues=False)
    p.getAxis("top").setHeight(1)
    return p


def set_title(p, text, size=8):
    p.setTitle(text, size=f"{size}pt", color="#333")


class TwinPlot:
    """time plot with a second y axis on the right (stimulus plot: current in mA left, interval in ms right)."""

    def __init__(self, show_x_labels=False):
        self.p = time_plot(show_x_labels=show_x_labels)
        self.p.showAxis("right")
        self.p.getAxis("right").setStyle(showValues=True)
        self.p.getAxis("right").setWidth(50)
        self.vb2 = pg.ViewBox()
        self.vb2.setMouseEnabled(x=False, y=False)
        self.vb2.setMenuEnabled(False)
        self.p.scene_added = False
        self.p.getAxis("right").linkToView(self.vb2)
        self.vb2.setXLink(self.p.vb)
        self.p.vb.sigResized.connect(self._sync)

    def attach(self):
        """call after the plot is in a scene."""
        if not self.p.scene_added and self.p.scene() is not None:
            self.p.scene().addItem(self.vb2)
            self.p.scene_added = True
            self._sync()

    def _sync(self):
        self.vb2.setGeometry(self.p.vb.sceneBoundingRect())
        self.vb2.linkedViewChanged(self.p.vb, self.vb2.XAxis)

    def clear(self):
        self.p.clear()
        self.vb2.clear()


def nan_segments(x, y0, y1):
    """x, y arrays of vertical segments (x, y0) - (x, y1), separated by NaN (connect='finite')."""
    x = np.asarray(x, float).ravel()
    n = x.size
    xs = np.c_[x, x, np.full(n, np.nan)].ravel()
    y0 = np.broadcast_to(np.asarray(y0, float), (n,))
    y1 = np.broadcast_to(np.asarray(y1, float), (n,))
    ys = np.c_[y0, y1, np.full(n, np.nan)].ravel()
    return xs, ys


def vlines(plot, x, y0, y1, color, width=1, style=QtCore.Qt.PenStyle.SolidLine, z=None):
    if np.size(x) == 0:
        return None
    xs, ys = nan_segments(x, y0, y1)
    it = pg.PlotDataItem(xs, ys, connect="finite", pen=pg.mkPen(color, width=width, style=style))
    if z is not None:
        it.setZValue(z)
    plot.addItem(it)
    return it


def rects(plot, x0, x1, y0, y1, brush, pen=None, z=-10):
    """rectangles [x0 x1] x [y0 y1] (one item)."""
    x0 = np.atleast_1d(np.asarray(x0, float))
    x1 = np.atleast_1d(np.asarray(x1, float))
    if x0.size == 0:
        return None
    it = pg.BarGraphItem(x0=x0, x1=x1, y0=np.full(x0.size, y0), height=np.full(x0.size, y1 - y0),
                         brush=pg.mkBrush(brush), pen=pg.mkPen(pen) if pen is not None else pg.mkPen(None))
    it.setZValue(z)
    plot.addItem(it)
    return it


def rot_labels(plot, x, y, labels, color, size=7, max_n=60):
    """labels rotated by 90 degrees, right aligned at (x, y) (comments)."""
    items = []
    if len(labels) > max_n:
        return items
    f = QtGui.QFont()
    f.setPointSize(size)
    for xi, lab in zip(x, labels):
        t = pg.TextItem(lab, color=color, angle=90, anchor=(1, 1))
        t.setFont(f)
        t.setPos(xi, y)
        plot.addItem(t)
        items.append(t)
    return items


def runs(mask):
    """start and end indices of runs of True."""
    m = np.asarray(mask, bool).astype(int)
    d = np.diff(np.r_[0, m, 0])
    return np.flatnonzero(d == 1), np.flatnonzero(d == -1) - 1


def message(parent, text, title="MyoDishAnalysis"):
    QtWidgets.QMessageBox.information(parent, title, text)
