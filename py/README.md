# MyoDishAnalysis (Python)

Python port of the MATLAB **MyoDishAnalysis** (folder above this one): contraction parameters of **every
single contraction** in MyoDish recordings (`.mdd`), reference beat, rocker filter, alignment of a parallel EP
recording (LabChart) and AP parameters. It includes a command line (`mda`) and an interactive GUI (`mda-gui`, PySide6 + pyqtgraph).

Version 1.0.0b1 (2026-10-07; = MATLAB version 1.0.0-beta.1, public beta) · Thomas Seidel, Friedrich-Alexander-Universität
Erlangen-Nürnberg (FAU) / InVitroSys GmbH. Until 2026-10-06 named MyoDishContractionTool (Python package
`myodish_contractions`, commands `mdct`, `mdct-gui`, `mdct-test`); now `myodish_analysis`, `mda`, `mda-gui`, `mda-test`.

**The MATLAB version is the reference.** Option names, column names, units, definitions of the parameters and the
GUI follow it. Their documentation (`../README.md`) applies to the Python version. This file describes only
installation, usage and the differences.

## Citation and license
If you publish results obtained with this software, please cite the version you used (Seidel T. MyoDishAnalysis,
version 1.0.0-beta.1, 2026; DOI: see `CITATION.cff` or the Zenodo record of the release) and mention it in the Methods.

Copyright (c) 2026 Thomas Seidel. License: GNU General Public License, version 3 or (at your option) any later version
(GPL-3.0-or-later, file `LICENSE`). You may use it free of charge, also commercially (companies, InVitroSys customers).
Copies, original or modified, may only be passed on under the same license and together with their source code. The
software comes without any warranty. Questions and bug reports: thomas.seidel@fau.de
Additional terms (GPL-3.0 section 7 b, c, e): modified versions must be marked as modified and must not be presented
as the original MyoDishAnalysis (use a different name or a clear suffix); the copyright and author notice (Thomas Seidel)
must be kept; no rights to the names MyoDish and InVitroSys are granted.

## Installation
Python ≥ 3.10 (tested with 3.12 on macOS arm64 and with 3.10 and 3.13 on Linux). Use a separate environment, outside of synchronized folders
(e.g. Dropbox, OneDrive), for example with [uv](https://docs.astral.sh/uv/):

```bash
uv venv ~/.venvs/mda --python 3.12
source ~/.venvs/mda/bin/activate
uv pip install -e "/path/to/MyoDishAnalysis/py[all]"   # [gui]: GUI only, [test]: pytest only, nothing: core
```

With `-e` (editable), changes to the code in this folder are active without reinstalling. `pip install -e ".[all]"` works
too.

## Quick start
```bash
mda-gui examples/example3_humanVentricle.mdd                 # interactive
mda examples/example3_humanVentricle.mdd -c 6 --from 0 --to 120   # summary of channel 6, 0-120 s
mda file.mdd -c 1 2 3 --from 600 3000 --to 660 3060 --labels baseline drug --rocker stopped -o results.xlsx
mda file.mdd -c 3 --from 300 --to 500 --rocker-filter --set medianFilterMs=20 meanFilterMs=10
mda-test                                                     # self test (= mda_test.m)
mda-watch raw_folder results_folder --rocker-filter          # new recordings of a folder (= MyoDishAnalysisWatch.m)
mda --help
```

```python
from myodish_analysis import myodish_analysis, read_mdd, analyze_channel, options, reference_beat
contractions, summary, info = myodish_analysis("examples/example3_humanVentricle.mdd", 6, 0, 120)
contractions, summary, info = myodish_analysis(f, [1, 2, 3], [600, 3000], [660, 3060],
                                                   labels=["baseline", "drug"], rocker="stopped", output="res.xlsx")
H = read_mdd(f)                                  # header (log file)
S = read_mdd(H, 1200, 1260)                      # data of a time window
B, C = analyze_channel(S, 6, [1200, 1260], options(rockerFilter=True))

from myodish_analysis.gui import run
win = run("file.mdd", block=False)               # inside a running Qt application (e.g. IPython %gui qt)
win.open_ep("file.mat"); win.api_set_range([10, 100]); T, Sm = win.api_results()
```

`contractions` and `summary` are pandas DataFrames with the columns of the MATLAB tables (units in
`contractions.attrs["units"]`). `info` is a dict, and `info["rockerFilter"]` and `info["thresholds"]` are DataFrames.
Indices returned by the functions (e.g. `C.iPeaks`) are 0-based. Channel numbers are the physical channel numbers (1 … 8), as
in MATLAB.

## MATLAB → Python
| MATLAB | Python (`myodish_analysis.`) |
|---|---|
| `MyoDishAnalysis` | `myodish_analysis()`, command line `mda` |
| `MyoDishAnalysisGUI` | `gui.run()`, `mda-gui` |
| `mda_readMdd` | `read_mdd()` (`read_header`, `read_data`, `read_overview`) |
| `mda_logEntries` | `log_entries()` |
| `mda_clockTime` | `clock_time()` |
| `mda_signalGaps` | `signal_gaps()` |
| `mda_calibrationFactor`, `mda_zeroForce` | `calibration_factor()`, `zero_force()` |
| `mda_options`, `mda_parameters` | `options()`, `parameters()` |
| `mda_analyzeChannel` | `analyze_channel()` |
| `mda_rockerFilter` | `rocker_filter()` |
| `mda_referenceBeat('create' / 'align' / 'compare' / 'relative' / 'traces', …)` | `reference_beat.create()`, `.align()`, `.compare()`, `.relative()`, `.traces()`; `.save_reference()` / `.load_reference()` (`.mat`, interchangeable with MATLAB) |
| `mda_readEPRecording` | `read_ep_recording()` |
| `mda_analyzeAP` | `analyze_ap()` |
| `mda_protocols`, `mda_groupBeats`, `mda_protocolResults` | `find_protocols()`, `group_beats()`, `protocol_results()`; `myodish_analysis(..., protocol=, groupBy=)` (`info['protocolResults']`); `mda FILE --protocol FFR`, `--group-by`, `--list-protocols`; GUI **Protocols ...** |
| `mda_summarize`, `mda_writeResults` | `summarize()`, `write_results()` |
| `mda_labels`, `mda_addLabels` | `labels()`, `add_labels()` |
| `MyoDishAnalysisWatch` | `watch()`, `mda-watch` (same index `mda_index.csv` and results; see the main README) |
| `mda_test`, `mda_testWatch`, `mda_testClockTime`, `mda_testSignalGaps` | `selftest()`, `mda-test`, `tests/test_mda.py`, `tests/test_watch.py`, `tests/test_clock_time.py`, `tests/test_signal_gaps.py` |

## Agreement with MATLAB (R2026a), checked 2026-10-07
`tests/compare_matlab.py` compares the Python results with MATLAB results of the same calls
(`tests/matlab/mda_py_reference_*.m`, results in `tests/reference/`) on the example recordings in `examples/` (see
`examples/README.md`) and on synthetic signals. There are 32 comparisons, and all agree within the tolerance:
* **MATLAB helper functions** (`movmean`, `movmedian`, `islocalmax` incl. flat peaks and prominence, `round`, `a:d:b`,
  `linspace`, `gradient`, `median`) are bit-identical. MATLAB's chunked algorithm for `movmean` and its rounding of the median of
  an even number of values are reproduced, because differences in the last bit shifted peaks on flat maxima.
* **Contractions and summaries** of the 9 example recordings (human ventricle and atrium, rabbit, pig and rat ventricle;
  2022 and 2026 log formats; a single-channel file with calibration 3000; 192 to 12475 contractions per file): same rows,
  NaN pattern and text. All numbers agree within a relative difference ≤ 1e-9 (in practice ≤ 1e-14). Reader, overview and
  log entries are identical.
* **Synthetic signals of `mda_test`** (exact parameters, rocker filter, reference beat with the same noise) are
  identical.
* **Reference beat**: create and align (stimulus / upstroke) give identical results. A reference saved by MATLAB and loaded in
  Python gives identical deviations and relative parameters.
* **EP alignment** (example 8, sharp electrode): the same method and the same matched stimuli (199 of 200); offset and
  drift differ by < 1e-14 s. **AP parameters** agree within a relative difference ≤ 4e-13 (192 contractions, median APD90
  230.3 ms, dV/dt max 106.9 V/s).
* **Rocker filter** (examples 1, 3 and 6): the subtracted artifact agrees to ~1e-11 (least-squares solutions of
  LAPACK / Accelerate vs. MATLAB). Where the artifact subtraction leaves a flat peak, this tiny difference can move the peak
  of 0.06–0.4 % of the contractions by one sample of the analysed signal (5 ms at 400 Hz with the default downsampling 2;
  macOS: rarely two samples). Which peaks move depends on the linear-algebra library (it differs between computers). The
  parameters of these contractions then differ accordingly; summary SDs agree within 0.6 % and means more closely
  (test tolerance: means 0.5 %, SDs 2 %).

Run it yourself (in the repository; the example recordings and MATLAB results are not part of the installed package):
```bash
pytest py/tests                                    # self test, helpers, round trips, GUI start, comparison with MATLAB
python py/tests/compare_matlab.py                  # details per comparison (default: examples/ and py/tests/reference/)
python py/tests/compare_matlab.py --data DIR ex3   # other folder / single cases
```
The MATLAB side is in `tests/matlab/`: `mda_py_reference_files(dataDir, outDir, cases)`, `mda_py_reference_synthetic`
and `mda_py_reference_helpers` (write the `.mat` files in `tests/reference/`).

## Differences from the MATLAB version
* GUI: plots are saved as `.png` / `.jpg` / `.tif` (3000 px wide, 300 dpi) or `.pdf` (vector graphic, editable in Inkscape /
  Illustrator) instead of `.fig`. SVG is not offered because Qt writes the plot lines as non-scaling strokes, which Inkscape,
  Illustrator and cairo draw incorrectly. Zoom and pan use the mouse (wheel: zoom the time axis, shift + wheel: move,
  double-click: whole window; arrow keys as in MATLAB). There is no figure toolbar. Closing the main window closes its
  other windows. **Edit figure ...** of the overlay window opens a matplotlib window (toolbar: *Edit axis, curve and
  image parameters*; save as .png / .pdf / .svg) instead of a MATLAB figure with the plot tools.
* GUI script access: `win.open_ep(file)`, `win.EP`, `win.api_set_range()`, `win.api_results()`, `win.api_zero_at()`,
  `win.on_key('right', shift)`, `win.overlay_channels([1, 3])`, `win.win_overlay` replace `fig.UserData`.
* The `showFigures` figures of the command line are drawn with matplotlib.
* Text columns and messages of the result tables are identical (compared). Where MATLAB rounds with `round(x, n)`, Python
  reproduces its rounding: MATLAB rounds a value one ulp below a half away from zero, e.g. `round(1.005, 2)` = 1.01.

## Known limitations (MATLAB and Python)
* Rocker filter on a channel without a signal (constant sensor value): the artifact is ~1e-11 µN, and `artifactR2` is
  rounding noise. A clearer status would be "no periodic artifact detectable" (to be changed in both versions).

TS 2026-10-06
