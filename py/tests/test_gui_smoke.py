# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Smoke test of the GUI (2026-11-12; counterpart of the GUI part of mda_testAll.m): every example recording opens,
every channel can be selected, the flag line shows flags and not an error, and the results browser explains every
flag letter. Runs without a display (Qt platform 'offscreen'); skipped without PySide6 / pyqtgraph."""
import os

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
QtWidgets = pytest.importorskip("PySide6.QtWidgets")
pytest.importorskip("pyqtgraph")

EX = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "examples"))
RECORDINGS = sorted(f for f in os.listdir(EX) if f.endswith(".mdd")) if os.path.isdir(EX) else []


@pytest.fixture(scope="module")
def app():
    from myodish_analysis.gui import light
    a = QtWidgets.QApplication.instance() or QtWidgets.QApplication(["mda-gui"])
    light(a)
    return a


def _events(app, n=20):
    for _ in range(n):
        app.processEvents()


@pytest.mark.parametrize("name", RECORDINGS)
def test_recording_opens_and_shows_flags(app, name):
    from myodish_analysis.gui.main_window import MainWindow
    win = MainWindow(os.path.join(EX, name))
    try:
        win.resize(1450, 800)
        win.show()
        _events(app)
        assert win.H is not None and win.cCh.count() == len(win.H.dataChannels)
        for k in list(range(win.cCh.count())) + [0]:        # every channel, then the first one again
            win.cCh.setCurrentIndex(k)
            _events(app, 5)
            txt = win.lFlags.text()
            assert txt.startswith("Flags") and "could not be computed" not in txt, (name, k, txt)
    finally:
        win.close()
        _events(app, 5)


def test_flag_line_shows_an_error(app, monkeypatch):
    # 2026-11-12: flags that could not be computed must not look like no flags
    if not RECORDINGS:
        pytest.skip("no example recordings")
    from myodish_analysis import report
    from myodish_analysis.gui.main_window import MainWindow
    win = MainWindow(os.path.join(EX, RECORDINGS[0]))
    try:
        _events(app)

        def broken(*a, **kw):
            raise RuntimeError("test error")
        monkeypatch.setattr(report, "report_flags", broken)
        win.show_flags()
        assert "could not be computed" in win.lFlags.text() and "test error" in win.lFlags.toolTip()
    finally:
        win.close()
        _events(app, 5)


def test_legends_explain_every_flag():
    from myodish_analysis import report
    from myodish_analysis.gui.dialogs import ResultsBrowser
    letters = set(dict(report.RED_CODES + report.SENSOR_CODES + report.YELLOW_CODES).values())
    for text in (" ".join(report.short_legend()), ResultsBrowser.HINT,
                 " ".join(t for _, t in report.legend_lines(report.FLAG_DEFAULTS))):
        missing = sorted(c for c in letters if f" {c} " not in text)
        assert not missing, (missing, text[:80])
    assert len(ResultsBrowser.VIEWS) == 5 and "orange" in ResultsBrowser.VIEWS[3]
