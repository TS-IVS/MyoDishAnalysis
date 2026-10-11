# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""pytest: Python port vs. MATLAB results (written by tests/matlab/mda_py_reference_*.m) on real recordings and
synthetic signals. The recordings are the anonymized examples in examples/ of the repository.

    MDA_TESTDATA=<folder with the .mdd/.log/.mat files> MDA_REFERENCE=<folder with the MATLAB .mat results> pytest tests

Defaults: examples/ and tests/reference. Details per comparison: python tests/compare_matlab.py.

TS 2026-10-06 (example recordings 2026-10-07)
"""
from __future__ import annotations

import os
import sys
import warnings

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import compare_matlab as cm  # noqa: E402

DATA = os.environ.get("MDA_TESTDATA", cm.EXAMPLES)
REF = os.environ.get("MDA_REFERENCE", os.path.join(HERE, "reference"))


def _run(fn, *args):
    cm.RESULTS.clear()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)
        fn(*args)
    bad = [n for n, k in cm.RESULTS if k is False]
    assert cm.RESULTS, "nothing compared"
    assert not bad, "differences: " + "; ".join(bad)


def test_helpers():
    if not os.path.isfile(os.path.join(REF, "helpers_reference.mat")):
        pytest.skip("no MATLAB results of mda_py_reference_helpers.m")
    _run(cm.case_helpers, REF)


def test_synthetic():
    if not os.path.isfile(os.path.join(REF, "synthetic_reference.mat")):
        pytest.skip("no MATLAB results of mda_py_reference_synthetic.m")
    _run(cm.case_synthetic, REF)


@pytest.mark.parametrize("case", list(cm.FILES))
def test_recording(case):
    if not os.path.isfile(os.path.join(REF, case + ".mat")):
        pytest.skip(f"no MATLAB results for {case}")
    if not os.path.isfile(os.path.join(DATA, cm.FILES[case])):
        pytest.skip(f"recording {cm.FILES[case]} not available")
    _run(cm.case_files, case, DATA, REF)
