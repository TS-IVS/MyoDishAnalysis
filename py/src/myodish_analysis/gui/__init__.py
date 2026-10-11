# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""GUI of the MyoDishAnalysis (PySide6 + pyqtgraph). Port of MyoDishAnalysisGUI.m.

    mda-gui [file.mdd] [--labels labels.csv]
    mda-gui results.xlsx             (or <name>_info.csv: results of mda / mda-watch / a GUI export, see read_results)
    python -m myodish_analysis.gui [file.mdd]

    from myodish_analysis.gui import run
    win = run('file.mdd')            # inside a running Qt application: returns the window

TS 2026-10-06 (results files 2026-10-09; light colors also with Qt < 6.8, 2026-10-10)
"""
from __future__ import annotations

import argparse
import sys


def light(app):
    """light colors also in the dark mode of macOS / Windows (the plots are white, as in MATLAB). Qt >= 6.8: light color
    scheme; older Qt: Fusion style with a light palette."""
    from PySide6 import QtCore, QtGui
    try:
        app.styleHints().setColorScheme(QtCore.Qt.ColorScheme.Light)
        return
    except AttributeError:  # older Qt
        pass
    app.setStyle("Fusion")
    pal = QtGui.QPalette()
    R = QtGui.QPalette.ColorRole
    for role, c in ((R.Window, "#efefef"), (R.WindowText, "#000000"), (R.Base, "#ffffff"), (R.AlternateBase, "#f5f5f5"),
                    (R.Text, "#000000"), (R.Button, "#efefef"), (R.ButtonText, "#000000"), (R.ToolTipBase, "#ffffdc"),
                    (R.ToolTipText, "#000000"), (R.Highlight, "#3874d8"), (R.HighlightedText, "#ffffff"),
                    (R.PlaceholderText, "#808080"), (R.BrightText, "#ff0000"), (R.Link, "#0b57d0")):
        pal.setColor(role, QtGui.QColor(c))
    app.setPalette(pal)


def run(mdd_file=None, metadata=None, block=True):
    try:
        from PySide6 import QtWidgets
        import pyqtgraph  # noqa: F401
    except ImportError as e:
        raise ImportError("The GUI needs PySide6 and pyqtgraph: pip install 'myodish-analysis[gui]'") from e
    from .main_window import MainWindow
    app = QtWidgets.QApplication.instance()
    own = app is None
    if own:
        app = QtWidgets.QApplication(sys.argv[:1])
        app.setApplicationName("MyoDishAnalysis")
        light(app)
    win = MainWindow(mdd_file, metadata)
    win.show()
    if own and block:
        app.exec()
    return win


def main(argv=None):
    ap = argparse.ArgumentParser(prog="mda-gui", description="MyoDishAnalysis (interactive)")
    ap.add_argument("mdd", nargs="?", help=".mdd file, or a results file (.xlsx, <name>_info.csv) to open again")
    ap.add_argument("--labels", help="labels per channel (.csv / .xlsx, see labels)")
    a = ap.parse_args(argv)
    run(a.mdd, a.labels)


__all__ = ["run", "main", "light"]
