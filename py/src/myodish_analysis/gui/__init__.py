"""GUI of the MyoDishAnalysis (PySide6 + pyqtgraph). Port of MyoDishAnalysisGUI.m.

    mda-gui [file.mdd] [--labels labels.csv]
    mda-gui results.xlsx             (or <name>_info.csv: results of mda / mda-watch / a GUI export, see read_results)
    python -m myodish_analysis.gui [file.mdd]

    from myodish_analysis.gui import run
    win = run('file.mdd')            # inside a running Qt application: returns the window

TS 2026-10-06 (results files 2026-10-09)
"""
from __future__ import annotations

import argparse
import sys


def light(app):
    """light colors also in the dark mode of macOS / Windows (the plots are white, as in MATLAB); Qt >= 6.8."""
    from PySide6 import QtCore
    try:
        app.styleHints().setColorScheme(QtCore.Qt.ColorScheme.Light)
    except AttributeError:  # older Qt: system colors
        pass


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
