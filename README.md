# MyoDishAnalysis

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23287809.svg)](https://doi.org/10.5281/zenodo.23287809)

Analysis of MyoDish recordings (`.mdd`) in MATLAB and Python: parameters of **every single contraction**,
reference beat, removal of the rocker artifact, alignment of a parallel EP recording (LabChart) and AP parameters.
Each has a command-line function (time range "from – to") and a GUI to view the recording and select the time
range or single contractions interactively. This file documents the MATLAB version (the reference);
the Python version (`py/`) gives the same results.

Version 1.0.0-beta.5 (2026-10-13) · Thomas Seidel, Friedrich-Alexander-Universität Erlangen-Nürnberg (FAU) / InVitroSys GmbH.
Public beta version (feedback welcome: GitHub issues or e-mail). Until 2026-10-06 named MyoDishContractionTool (functions MyoDishContractions,
MyoDishContractionsGUI, mdct_*); now MyoDishAnalysis, MyoDishAnalysisGUI, mda_*.
Python version with the same results: folder `py/` (see `py/README.md`).

## Citation and acknowledgement
MyoDishAnalysis was developed by Thomas Seidel, Institute of Cellular and Molecular
Physiology, Friedrich-Alexander-Universität Erlangen-Nürnberg / InVitroSys. If you publish results obtained with this
software, please cite the version you used with its DOI and mention it in the Methods, e.g. *Seidel T. MyoDishAnalysis,
version 1.0.0-beta.4. Zenodo; 2026. doi:10.5281/zenodo.23287810*. The DOI of every version is on its Zenodo record;
10.5281/zenodo.23287809 stands for all versions and resolves to the latest one (GitHub: *Cite this repository*).
Copyright (c) 2026 Thomas Seidel. License: GNU General Public License, version 3 or (at your option) any later version
(GPL-3.0-or-later, file `LICENSE`). Free to use, also commercially (companies, InVitroSys customers). Copies, original
or modified, may only be passed on under the same license and together with their source code. The software comes
without any warranty. Questions and bug reports: thomas.seidel@fau.de
Additional terms (GPL-3.0 section 7 b–e, file `NOTICE`): keep the copyright and author notices; a modified version
must have a name of its own (e.g. `MyoDishAnalysis-<suffix>`) and its own version number and must say that it
is a modified version, not an official release; the names of the author, FAU and InVitroSys may not be used
to promote it; no trademark rights to the names MyoDish and InVitroSys are granted. These terms do not
restrict the use of the software or of the results obtained with it.

## Requirements
MATLAB R2019b or newer. **No toolboxes.** Tested with MATLAB R2026a (macOS).
The log file `<name>_log.log` written by the MyoDish software must be in the same folder as the `.mdd` file.
Without it, 400 Hz is assumed and the number of channels is derived from the content of the status channel.
Files of the first MyoDish version (software 1.0.x, 2020/21: 8 force channels at 500 Hz, no status channel) are
recognized by the file size and the recording duration in the log file or, if they do not fit, by `nChannels` 8 /
500 Hz in the log file and no channel with the content of a status channel (2026-10-13). They are analysed as unpaced
channels: contractions only, no stimuli, extra or missed beats; all parameters that need the stimulus are NaN. Older
log files of this version (`_commands.log`, `_events.log`, `_time.mddt` instead of `<name>_log.log`) are not read.

**Force units**: the `.mdd` file contains arbitrary units (AU). They are converted to µN with the `Calibration`
entry of each channel in the log file (AU per mN; 1000 → AU = µN, 3000 → AU / 3). While the extended sensor mode
is on (log event `extended sensor mode on`, also when logged before the recording, until `extended sensor mode off`),
the calibration value is divided by 3.3 (1000 → AU × 3.3). `'calibration','none'` keeps the values of the file (AU).

## Quick start examples:
```matlab
addpath('/path/to/MyoDishAnalysis')
MyoDishAnalysisGUI('examples/example3_humanVentricle.mdd')                   % interactive
[c, s] = MyoDishAnalysis('examples/example3_humanVentricle.mdd', 6, 0, 120);  % channel 6, 0–120 s
mda_test                                                                       % self test
MyoDishAnalysisWatch('raw', 'results')                                         % new recordings of a folder
```
More examples: `example_MyoDishAnalysis.m`. Help: `help MyoDishAnalysis`, `help mda_options`.
**Quick-start guides** (2 + 1 pages): [`docs/MyoDishAnalysis_quickstart_GUI.pdf`](docs/MyoDishAnalysis_quickstart_GUI.pdf)
(first analysis in the GUI, export, reading the results) and
[`docs/MyoDishAnalysis_quickstart_watcher.pdf`](docs/MyoDishAnalysis_quickstart_watcher.pdf) (automatic analysis of a
folder, daily run, report).
**Example recordings** (folder `examples`, see `examples/README.md`): anonymized MyoDish recordings of human ventricle
and atrium, rabbit, pig and rat ventricle (force-frequency, post-rest potentiation, isoprenaline, stimulation threshold
and rocker speed protocols) and a sharp-electrode recording with its LabChart export.

## GUI (`MyoDishAnalysisGUI`)
0. **Open ...**: a recording (`.mdd`) or a results file (see **Open ...** with results files below); the folder is
   remembered. A recording opens with its first window (From / To: 0–120 s) loaded and analysed (2026-10-14).
   **Results ...**: results browser of a results folder of the watcher (`mda_index.csv`, `mda_flags.csv`; the last
   folder opens again directly, **Folder ...** chooses another one): one row per recording and channel with label,
   flags of the analysis report (red background = check the analysis, yellow = slice quality, see "Analysis
   report"), capture, contractions, channel status and the flag texts; recordings that were not analysed (status and
   message of the index) in grey. List *all recordings / with flags / red flags / not analysed* and a search field
   (all typed words must occur). **Double-click** a row (or **Open**): the channel with the settings of its analysis,
   at the window of the red flags, otherwise the first 120 s of its analysis (results file `<name>.xlsx` or
   `<name>_info.csv`, see below); a parallel recording that was not analysed: its main file at its time. **Compute flags (n)**: flags of
   recordings analysed by an older watcher (computed from their result files, saved in `mda_flags.csv`).
   **Main file** (button next to the file name, shown for a parallel recording such as a schedule file or snapshot
   started from the main recording; see "Watcher"): opens the main recording at the window shown, same channel.
   **Flags** (grey line above the table): the flags of the analysis report for the analysed range of the channel
   (red = check the analysis, orange = slice quality; the pointer shows the codes).
   **Comments ...**: searchable list of the comments in the log file (# = number in the force plot, date and time,
   time in the file, text; option "all log entries" adds events and settings). Search: all typed words must occur.
   Select a row: the comment is highlighted in the force plot; double-click a row (or select it and press **Go to**)
   to load the data around the comment (window length = currently loaded window, ≥ 30 s). Comments are marked purple
   in the overview and, numbered as in the list, in the force plot (pointer on a mark: its text; click: highlighted
   and selected in the list).
1. **Overview**: min/max envelope of the selected channel over the complete recording
   (green = rocker at rest; time axis h:mm, or h:mm:ss / m:ss when zoomed in or for short files, from 2 days
   *d h:mm* or whole days *n d*; the unit is shown bottom left, e.g. *(h:mm)*). Drag in the overview, or type From/To
   (seconds) and press **Load**, to load a time window. **Right click → Select all**: loads the range shown in the
   overview (at most 4 h).
   **Mouse wheel** over the overview: zoom the time axis (shift + wheel: move; double-click: whole file); the zoomed
   part is re-read in more detail (useful for 24-h recordings).
   **Arrow keys** (click into a plot first; MATLAB: not while the toolbar zoom / pan is active) and the **buttons under
   the force plot** change the loaded window, i.e. the blue selection in the overview and the analysed range (read
   again): ← / → (◀ / ▶ bottom left / right) move it by half its length, shift + ← / → (shift + click) extend it by half
   its length on that side, ↑ / ↓ (→← / ←→ in the middle) zoom in / out (half / twice its length, around the centre).
   With the mouse pointer over the overview the keys move its zoomed time axis instead; a zoomed overview moves along
   when the window leaves its visible part. The mouse wheel zooms only the display.
2. **Force plot**: force − zero force (if the zero force is known, see "Zero force"; otherwise the sensor signal).
   Red = selected contractions, orange = uncertain contractions (see *high sensitivity* below), grey = excluded by
   the filters, x = excluded by you, blue ticks = stimuli, green ticks = extra pulses (status channel bit 16:
   pre-pulses, CCM pulses, ...), green rings = contractions elicited by an extra pulse, black diamonds = ambiguous
   stimulus assignment (see "Stimulus assignment"), thin bar at the top = rocker state (green = at rest, grey =
   moving), yellow = analysed range(s).
   **Legend** of these markers in the force plot (menu *View → Legend of the force plot* or right click in the force
   plot; draggable; entries that do not occur in the window are left out).
   Panel *Cursor in the force plot*: *drag = select time range* or *click = exclude / include contraction*.
   **Several ranges** (2026-10-14): **shift + drag** adds a range to the selection (overlapping ranges are merged).
   The contractions and stimuli of all ranges are pooled (table, parameter plot with the mean per range, overlay,
   All channels; *Protocols → add selected range* and *Trend → selected range* use the span from the first to the
   last range); the exports add one summary row per range (*all ranges*, *range1*, ...; column `range` of the contractions and
   pulses), and **Open ...** restores the ranges. **Right click** in the force plot: **Zoom to the selection**
   (time axis = analysed ranges), **Select all rocker stops of the overview range** (with *only contractions with
   rocker at rest*): every rocker stop (≥ 1 s) within the range shown in the overview is read and shown side by
   side (dashed lines = time gaps; the time axis keeps the time in the file; at most 4 h of data and 2000 stops);
   all of them are selected and analysed together, exports keep the time in the file. Loading a window (Load, drag in
   the overview, arrow keys) returns to the normal view. In this view the rocker filter is off and intervals across
   the gaps (peak-to-peak, stimulus intervals) are not computed.
   **Advanced ...** (next to *only stimulated contractions*): all parameters of the method that are based on
   assumptions or experience (see "Advanced settings"), one tab per part of the analysis: *Assignment* (onset gate,
   rise phases, pre- / post-pulses, **stimuli**: *auto* / *MyoDish pulses* / *external trigger pulses*), *Detection*,
   *Noise / artifacts*, *Rocker rules*, *Signal* (averaging, filters, spike removal), *Rocker filter*, *Protocols*
   (tolerances of the grouping), *Export*. Hover over a name for its meaning; the default is shown next to every
   field (* = the window is read again). **Guide** opens the settings guide (`docs/MyoDishAnalysis_settings_guide.pdf`:
   figures for every parameter and the legend), **Defaults** shows the defaults, **Save settings ...** /
   **Load settings ...** write / read a settings file (a results file can be loaded as well; all settings except the
   threshold and zero force of the channels), **Apply** / **OK** analyse the window again (status line: the settings
   that differ from the defaults). The settings apply to All channels, Protocols, Trend and the exports and are
   written to the info table of every export. Changed settings (2026-10-14): the button shows their number in red,
   e.g. *Advanced (3 changed)*, shortened if the text does not fit (*Advanced (3 chgd)*, *Adv. (3 chgd)*); its
   tooltip lists them with their defaults.
   Mouse wheel: zoom the time axis (shift + wheel: move; double-click: whole loaded window). The figure toolbar
   zoom/pan also works (switch the tool off again to use the mouse modes). Time axis in h:mm:ss or m:ss (decimals
   when zoomed in below ~10 s); checkbox *time 0 = window start* shows the time relative to the
   window start (display only: From/To, tables and exports keep the time in the file, in s).
   **Mouse pointer** over the force, stimulus, parameter or EP plots (not the overview): a dashed line and a marker on
   the curve in every plot; the value at that time is written small in the top left corner of each plot — force,
   stimulus pulse nearest to it (current, interval), parameter of the lower plot of the nearest contraction, EP signal
   and stimulation; the plot under the pointer also shows the time and the time since the last stimulus (EP plots:
   stimuli of the EP recording). The windows always use light colors (also with a dark theme).
   **Threshold, this ch.**: detection threshold of the selected channel, *auto* or a manual value (µN); kept per
   channel when you switch channels and used for All channels, Protocols and Trend (command line: one value per
   channel, `'threshold',[NaN 300 NaN ...]`, NaN = auto).
   **Right click → Set as zero force**: the y value of the mouse pointer becomes the zero force of the channel
   (e.g. right-click on the baseline of an empty chamber); "Zero force from the log file" restores the Offset.
   Checkbox **remove rocker artifact**: see "Rocker artifact" below; light grey = signal before the
   correction; the result (artifact size, rocker frequency, or why it was not possible) is shown below the
   checkboxes and in the status line. The setting also applies to All channels, Trend and the exports.
   List **high sensitivity / high specificity** (next to it; auto threshold): *high sensitivity* (default) counts all
   contractions and marks the uncertain ones orange (status line: number of uncertain contractions); *high
   specificity* does not count them. Switching shows the result at once (see "Signal processing and detection").
   **Rocker artifact ...** (button next to *time 0 = window start*; also menu *Save / Export* and right click in the
   force plot): extra window with the signal of the loaded window before (grey) and after (black) the rocker filter
   and the removed periodic artifact (blue; grey background = rocker moving), estimated for the selected channel as
   for *remove rocker artifact*, also when that is off. Menu of the window: **Save figure** (.png / .jpg / .tif /
   .fig; Python: .pdf instead of .fig) and **Export data** of the visible time range (signal before / after, artifact,
   rocker state; table *rockerFilter*: rocker frequency, artifact size, fit; table *info*).
3. **Stimulus plot** (below the force plot): current of every stimulus pulse of the channel (red bars, mA;
   green = extra pulse; x = current not reached) and the interval to the previous pulse (blue, ms). With 40 pulses
   or fewer in view, the values are written next to the pulses (as `drawStimPulses` 'displayCurrents' /
   'displayIntervals'; "?!" = current not reached).
4. **Table**: mean, median, SD and n (contractions with a value) of the selected contractions (the median is
   less affected by post-rest or partly refractory contractions; the results files keep mean, SD and n); at the end **extra beats**
   (contractions without an adequate stimulus, count and % of the detected contractions) and **missed beats**
   (stimuli without a contraction above the detection threshold, count and % of the stimuli), both over the whole
   range, independent of the rocker / stimulated filters; **uncertain** contractions (all, stimulated, extra) and
   uncertain missed beats (stimuli followed only by an uncertain contraction, i.e. missed with *high specificity*);
   **missed in a contraction** (regular pulses that fell into a contraction elicited by another pulse), **extra
   pulses** and the contractions **elicited by an extra pulse** (if the range has extra pulses), **ambiguous
   stimulus** assignments. **Lower plot**: one parameter per contraction over time, chosen
   with the list *Lower plot* above it (all parameters, plus stimToPeak and prominence; red = selected, dashed = mean
   of the selected contractions).
   **Trend ...** (next to the list): rolling mean or median (window in min) of a parameter over long periods and
   over several files in a row, e.g. the daily files `_0`, `_1`, `_2` ... of a culture (**Add series** finds all
   `<name>_<number>.mdd` of the open file; **Add files** any others). Time 0 = start of the first file; the files are
   placed by the recording start in their log files (system time), gaps without data are shown grey ("no data");
   time axis as time since start (h:mm) or clock time. **Comments** of the log files (2026-10-13): purple dotted lines
   with numbered markers in a strip above the plot (they stay visible when you zoom; numbers that would overlap are
   hidden) and a list below the plot (number, time, full text); click a marker or a line of the list, or point at a
   marker, to highlight the comment (a line of the list outside the view moves the view to it). Saved figures
   contain the numbered markers (MATLAB: and the list of the comments in the view). **Sampling**: *short windows*
   (default: W = 30 s every T = 10 min; only these windows are read and analysed), *all contractions*, or *rocker
   stops only* (stop periods from the `rockerSpeed` entries of the log files; contractions with the rocker at rest).
   Use a rolling window ≥ 2 T. Reading the file dominates the time, not the analysis (24-h file via VPN: ~70 s to
   read, ~5 s to analyse one channel). Every window is a separate read (~0.25 s via VPN, a few ms in the lab
   network), so via VPN windows pay off from T ≈ 10 min on (24 h: ~35 s instead of ~75 s), in the lab network already
   at a few minutes. Analysing only every n-th contraction would not save time (the whole signal must be read and
   filtered anyway).
   *All channels in one pass*: the file is read once for all channels (~1.5 × the time of one channel); afterwards
   switching the channel shows its trend without recalculation.
   **Several channels**: *several channels ...* in the channel list (checkboxes) overlays their trends (one colour per
   channel, legend Ch n; the file is read once for all of them); the set stays in the list (e.g. *Ch 1+3+5*), single
   channels shown from the cache. Export: column `channel` in both sheets.
   **Calculate** detects the contractions in all listed files (threshold, filters, zero force and rocker filter of the
   main window); afterwards parameter, window and display change without recalculation. Save figure / Export data (all
   contractions with file, time since start and clock time; rolling curve; file list with gaps).
5. **Save / Export** (menu of the window, or right click on a plot): save all plots or a single plot (overview,
   force, stimulus, parameter plot) as `.png`, `.jpg`, `.tif` (300 dpi) or `.fig`, or the window as shown
   (screenshot); export the data of the force, stimulus or parameter plot (visible time range) to `.xlsx`
   (one sheet per table), `.csv` or `.txt` (one file per table): force signal (force − zero force), contractions
   with their status, stimuli, comments; stimulus pulses (current, interval); the plotted parameter. The overview
   (whole file) can only be saved as a picture. The overlay window has its own **Save figure** / **Export data**
   (mean, SD, SEM, min, max, n and all single traces of every group; time course: the traces) and **Edit figure ...**.
6. **Export this channel**: all contractions of the range (column `included`, `manuallyExcluded`) + summary →
   `.xlsx` / `.csv`. **All channels → file**: the same range and settings in all channels (without manual exclusions;
   computed with the command-line function, i.e. the automatic threshold may differ slightly from the GUI,
   which uses the loaded window). **Every export** (also the data of a plot, the overlay, the trend, the rocker
   artifact) contains the table **info**: version and implementation, recording, analysis date, all settings (with
   the threshold and zero force of the channel), loaded window and analysed range, EP recording (see "Results files").
   **Open ...** with a results file (or `MyoDishAnalysisGUI(resultsFile)`, Python `mda-gui results.xlsx`):
   opens a results file of the command line, the watcher or the GUI (`.xlsx`, `<name>_info.csv`, `_summary.csv`,
   `_contractions.csv`; watcher: `<name>.xlsx` with the contractions in `<name>_contractions.csv.gz`): the recording (path in the file; if moved: the same name next to the results file, otherwise
   a file dialog), all settings (threshold and zero force of the channel, detection mode, rocker filter, filters,
   stimuli) and the analysis window (several: list of channel, range and time) are restored; contractions excluded by
   you in an export are excluded again. The contractions are detected again and compared with the file (status line:
   *the same as here* or the differences; black o = contraction of the file not found again, e.g. results of another
   version). A reference beat is not stored in the results (create it again).
   `MyoDishAnalysisGUI(file, 'channel', c, 'window', [from to])` (Python `mda-gui file --channel c --window from to`)
   opens a recording or results file at channel `c` and loads the window from … to s (results file: its settings and
   the analysis window of this channel); the analysis report lists these commands for the channels to check.
   Menu **Save / Export → Analysis report (PDF) with 'All channels → file'** (off by default): the export also writes
   `<file>_report.pdf` (see "Analysis report").
   **Overlay contractions**: the selected contractions and their mean in an overlay window, aligned at the stimulus
   (default; stimulus = time 0) or at the peak, or the **time course** of the analysed range (t = 0 at the first
   stimulus of each group, since the channels are not stimulated at the same time); baseline = diastolic force
   (developed force) or zero force; optional normalization to the amplitude. Several selections can be compared:
   press the button again (or **Add current selection** in the overlay window) after selecting another range /
   channel / filter → one colour per group. **Channels (same range) ...**: checkboxes of all channels; ticked
   channels are added for the analysed range of the main window (same settings and filters, threshold and zero force
   of each channel; manual exclusions only in the channel of the main window), unticked ones removed.
   Per group (select it in the list): **legend** text, **colour**, line **width**, line style (solid / dashed /
   dotted / dash-dot) and a transparent **band** (mean ± SD, ± SEM or range min–max); *line and band for all groups*
   copies the settings. Below the plot: **title**, **x axis**, **y axis** (empty = automatic) and the **legend**
   position (or off). **Edit figure ...** opens a copy of the plot for free editing (MATLAB: normal figure with the
   plot tools, e.g. double-click a text or line; Python: matplotlib window, toolbar button *Edit axis, curve and image
   parameters*) and saving in other formats.
7. **+ EP recording ...**: an electrophysiological recording made in parallel with LabChart (`.mat` export; e.g.
   sharp electrode: voltage channel + stimulation channel; default file: same name as the `.mdd` file) is aligned to
   the stimuli of the `.mdd` file and shown below the plots with the same time axis (the window grows downwards;
   on small screens the plots above are compressed). The text right of the traces gives the matched stimuli,
   offset, clock drift and residual; **CHECK** marks an uncertain alignment. **Remove EP recording** hides it.
   With an EP recording, every contraction also gets its AP parameters (see below; table, lower plot, exports).
   **y limits** of the EP plots: drag up / down in a plot (band = new limits), double-click = automatic; right click
   → *Set y limits ...* / *y limits: automatic (restore view)*. The limits stay when the time axis changes.
   **remove stimulus artefact** (checkbox right of the traces, also in the right-click menu): the stimulus pulses and
   the artefact after them are replaced by straight lines (grey) in the signal plot — display only, the AP parameters
   are measured on the recorded signal (see "Removing the artefacts for the display").
   Script access: `api = fig.UserData; api.epRecording(matFile); EP = api.epRecordingData();`
   `api.epYLim(1, [-100 40])` (1 = signal, 2 = stimulation, `[]` = automatic), `api.epRemoveArtefacts(true)`,
   `Hv = api.hover(t, 'signal')` (mouse pointer at time t over a plot: markers and values).
8. **Protocols ...**: stimulation protocols found in the log file (see "Stimulation protocols"), editable
   (From / To, grouping; **+ selected range** adds the range of the main window). Tick protocols and channels,
   choose the contractions (rocker at rest / all / rocker moving) and press **Analyse**: summary per group (table) and
   a parameter against the quantity (mean ± SD / SEM; S1 / steady state as dashed line, post-S2 dotted). Threshold,
   filters, zero force, rocker filter and labels are taken from the main window. **Save figure** / **Export**.
9. **If the window stays empty or a button does nothing** (MATLAB GUI, 2026-10-21): every callback and the plotting
   run guarded. An error is shown in the status line in red (`Error in …: …`) and appended with the version, file,
   window, channel and stack to the error log `MyoDishAnalysisGUI_errors.log` in the temporary folder (`tempdir`
   in MATLAB: on Windows `%TEMP%`, on macOS `/var/folders/…/T/`); send that file with a bug report. With the
   environment variable `MDA_DEBUG` set (`setenv('MDA_DEBUG', '1')`) the report is also printed in the command
   window. A frequent cause of errors inside MATLAB's own GUI code is a user function on the MATLAB path that
   shadows a MATLAB function (e.g. a `split.m`, `contains.m` or `range.m` in a toolbox folder added with
   `addpath(genpath(...))`): `which split -all` lists all of them; remove that folder from the path.

## EP recordings (`mda_readEPRecording`)
`EP = mda_readEPRecording(matFile, mda_readMdd(mddFile))` places a LabChart recording on the time axis of the
`.mdd` file: `t_mdd = t0 + slope · t_LabChart`.
* **Stimuli**: LabChart: |stimulation − median| > max(20 × noise SD, 5 % of the largest pulse), onset of each pulse
  (pulses < 10 ms apart = one). The fixed 2 V threshold of `importSharpElectrodeData` missed the pulses ≤ 14 mA
  (amplitude ≈ 0.125 V/mA, saturated ≥ 40 mA in our recordings) and counts biphasic pulses twice.
  `.mdd`: stimulus pulses of the status channel; every channel with stimuli is tried (GUI: the shown channel first),
  also the external trigger pulses (external stimulator, "ext. trigger").
* **Offset**: all differences `.mdd` stimulus − LabChart stimulus are counted (bins of 10 ms); every frequent
  difference is refined by iterative matching (tolerance 10 ms) with a straight line (**clock drift**), and the
  one with the most matched stimuli wins. With (nearly) constant pacing, shifts by one stimulus interval match
  almost as many stimuli; then (1) the stimulus current decides (the LabChart pulse amplitude must be the same for
  the same current; threshold protocols), else (2) the clock times (LabChart block time vs. recording start in the
  log file; they differed by 0.15–0.29 s), else the result is marked CHECK.
* **Clock drift**: LabChart and MyoDish clocks differed by −78 to −97 ppm (4 recordings): 46 ms after
  8.5 min, ~0.35 s after 1 h. With a constant offset only 103 of 253 stimuli matched within 10 ms (8.5 min);
  with the fitted slope 252/253, residual 1.1–1.2 ms rms (= time resolution of the `.mdd` stimuli, 2.5 ms).
* Options: `'signalChannel'`, `'stimChannel'` (number or part of the title), `'block'`, `'mddChannel'`,
  `'stimThreshold'`, `'timeOffset'` (`t0` or `[t0 slope]`, no matching), `'tolerance'`, `'fitDrift'`.
  V and µV are converted to mV. LabChart comments are returned in `.mdd` time (`EP.comments`).
* Checked with 4 sharp-electrode recordings: all aligned unambiguously; `alignStimTimes_new` (constant offset, 2 V
  threshold) returned shifts of 21.5, 27.7 and −35.6 s instead of −0.42, −0.34 and −0.61 s for 3 of them.

### AP parameters per contraction (`mda_analyzeAP`; GUI: automatically with an EP recording)
`[A, M] = mda_analyzeAP(EP, B)` returns one row per contraction of `B` (append with `[B, A]`):
| column | unit | definition |
|---|---|---|
| `AP_dVdtMax` | V/s | maximum upstroke velocity (central difference of the raw signal); NaN if the upstroke lies within the stimulus artefact or the sampling rate is < 5 kHz |
| `AP_RMP` | mV | resting (diastolic) potential: median over 10 ms before the stimulus artefact (unstimulated beats: before the foot of the upstroke) |
| `AP_Vmax` | mV | peak voltage; NaN if the peak may lie within the artefact |
| `APD25`, `APD50`, `APD90` | ms | activation (time of dV/dt max) → 25 / 50 / 90 % repolarization (V_max − x % of (V_max − RMP); first crossing after the peak, 0.5 ms moving mean, interpolated) |
| `t_AP`, `AP_reference`, `AP_note` | s / text | activation time (`.mdd` time), `upstroke` or `stimulus`, reasons for missing values |

* **Stimulus artefact**: from the pulse onset in the stimulation channel (biphasic pulse incl. pause = one pulse;
  the onset is the stimulus time) until V_m is no longer saturated (amplifier limit, e.g. ±102.4 mV) and
  |dV/dt| (0.5 ms mean) < 20 V/s.
* **Upstroke within the artefact** (foot of the upstroke above RMP + 30 % of the amplitude, or the maximum dV/dt at
  the artefact end): `AP_dVdtMax`, `AP_Vmax`, `APD25`, `APD50` = NaN; `APD90` from the stimulus onset with the highest
  value within 50 ms after the artefact as reference (approximate; sensitive to that reference if the final
  repolarization is slow). No AP: < RMP + 20 mV 20 ms after the artefact, or never ≥ RMP + 40 mV.
* **Fusion**: every AP is evaluated up to the next stimulus; repolarization not reached → APD NaN
  (`next stimulus before APD90`). RMP > median RMP + 10 mV → `RMP not diastolic`.
* Options: `'artefactSlope'` (20 V/s), `'upstrokeMin'` (20 V/s), `'minAmplitude'` (40 mV), `'maxLatency'` (0.1 s),
  `'maxAPD'` (2 s), `'apdFrom'` (`'auto'` | `'stimulus'` | `'upstroke'`).
* Artefacts checked in 12 recordings: biphasic pulses of 6–9 ms in 9 of them (V_m saturated until
  ~8 ms → upstroke and peak hidden, APD90 only), 2–3 ms in 3. Short pulses (`examples/example8_rabbitVentricle_EP`): clean upstrokes 10–30 ms after the
  stimulus (dV/dt max 107 ± 7 V/s, RMP −85.7 mV, V_max +25 mV, APD90 228 ± 8 ms, n = 192).
* GUI markers (≤ 60 contractions visible): grey = artefact, green line = RMP, ▲ upstroke, ▼ V_max, ○ APD25/50/90.

### Removing the artefacts for the display (`mda_analyzeAP('removeArtefacts', EP)`; GUI: *remove stimulus artefact*)
`[Vc, R] = mda_analyzeAP('removeArtefacts', EP)` (Python `remove_artefacts(EP)`) replaces, for every pulse of the
stimulation channel, the samples from the pulse onset to the end of the artefact by a straight line from the last
sample before the pulse to the first sample after the artefact. End of the artefact: as for the AP parameters
(first sample after the pulse end that is not saturated and where |dV/dt| < 20 V/s; within 30 ms and before the next
pulse), then the decay of the artefact is followed towards the RMP (median over 10 ms before the pulse) for at most
10 ms until the RMP is reached, the decay is slower than 2 V/s or the signal turns back by > 3 mV (upstroke).
`R` = `[tFrom tTo]` of every replaced segment. Options `'artefactSlope'` (20 V/s), `'tailSlope'` (2 V/s),
`'maxTail'` (0.01 s). An upstroke within the artefact cannot be recovered (the line runs to the first sample after
it). `examples/example8_rabbitVentricle_EP`: 200 pulses (biphasic, 3 ms), 7.5–10.5 ms replaced each (pulse,
saturation at ±102.4 mV and the decay to about −77 mV); all 192 upstrokes (dV/dt max 11.5–36 ms after the pulse
onset) lie ≥ 2.5 ms after the replaced part.

## Labels per channel (metadata)
For documentation and later pooled analyses, every channel can carry labels that become columns of the
contraction and summary tables (and a sheet `labels` in the Excel output):

| label | type | example |
|---|---|---|
| setupID | text | `Setup3` |
| sliceID | text | `S12` |
| species | text | `human`, `rabbit`, `pig` |
| sampleID | text | heart / donor / animal, e.g. `H01` |
| sampleGroup | text | group of the sample, e.g. `DCM`, `donor`, `sham` |
| sliceGroup | text | experimental group of the slice, e.g. `control`, `drug` |
| tissue | text | region, e.g. `LV`, `RV`, `LA`, `RA` |
| treatment | text | e.g. `isoprenaline` |
| concentration | number | e.g. `100` (for dose–response analyses) |
| concentrationUnit | text | e.g. `nM` |
| daysInCulture | number | days in culture |
| cultureStart | text | `1999-12-24 14:30` – if given, `daysInCulture` is calculated for every contraction from its clock time |
| comment | text | free text |
| analyst | text | initials of the person who does the analysis |

Own additional fields are kept as extra columns.
* **Command line**: `'metadata', m` with a struct (one value for all channels, or one value per channel in the order
  of `channels`), a table (column `channel`) or a `.csv`/`.xlsx` file:
  ```matlab
  m.species = 'human'; m.sampleID = 'H01'; m.sliceID = {'S1','S6','S8'};
  m.sliceGroup = {'control','drug','drug'}; m.treatment = {'','isoprenaline','isoprenaline'};
  m.concentration = [0 10 100]; m.concentrationUnit = 'nM'; m.cultureStart = '1999-12-24 16:00'; m.analyst = 'TS';
  [c, s] = MyoDishAnalysis(mdd, [1 6 8], 1200, 1260, 'metadata', m);
  ```
* **GUI**: button **Labels ...** (editable table; "Fill empty cells from first row"; Load/Save). Saved as
  `<name>_labels.csv` next to the `.mdd` file, this file is loaded automatically the next time the file is opened.
  `MyoDishAnalysisGUI(mdd, m)` starts the GUI with the labels of `m` (the GUI shows all channels: with
  `m.channel = [1 6 8]` the per-channel values refer to these channels).

## Command line (`MyoDishAnalysis`)
```matlab
[contractions, summary, info] = MyoDishAnalysis(mddFile, channels, fromSeconds, toSeconds, options...)
```
* `channels`: e.g. `6` or `[1 6 8]`; `[]` = all channels in the file (single channel files: `1`).
* `fromSeconds`, `toSeconds`: time in the file (s); negative = seconds before the end. Vectors define
  several ranges, e.g. `[600 3000]`, `[660 3060]` with `'labels', {'baseline','drug'}`.
* Options: `'output','results.xlsx'` (or `.csv`), `'metadata',m` (labels per channel, see above),
  `'rocker','stopped'`, `'beats','stimulated'`, `'threshold',300` (µN), `'zeroForce',[z1 z2 ...]`,
  `'rockerFilter',true` (see "Rocker artifact"; result per channel in `info.rockerFilter` and the sheet
  `rockerFilter`), `'externalTrigger','auto'|'on'|'off'` (see "External trigger"), `'stimAssignment','onset'|'peak'`
  and the gate parameters (see "Stimulus assignment"), `'pulseTable',false` (no pulse table), `'showFigures',true`,
  `'quiet',true`; all others see `help mda_options`.
* `'pooled',true` (Python `pooled=True`, `--pooled`; 2026-10-14): with several ranges also one summary row per
  channel over all ranges together (`range` = *all ranges*; contractions and stimuli of the ranges pooled).
* **Analysis report** (`'report'`; 2026-10-11): with `'output'` also `<output>_report.pdf` (`'report',false`: none;
  `'report','file.pdf'`: this file, also without `'output'`). See "Analysis report".
* Results files (`'output'`; the watcher; GUI exports): sheet / file **info** (key, value) with the version
  (`version`, `implementation` MATLAB / Python, `software`), the recording (`file`, sampling rate, recording start),
  `analysisDate`, `createdBy` (MyoDishAnalysis, MyoDishAnalysisWatch, MyoDishAnalysisGUI), the analysed `channels`,
  `chunkSeconds`, the watcher settings (`watcherOptions`, `watcherCode`) or the GUI window (`loadedWindow_s`,
  `analysedRange_s`, `epRecording`), every option (`option_<name>`, full precision) and the Offset / Calibration
  entries of the log file; sheet **thresholds** = analysis windows (per range, channel and chunk of `chunkSeconds`:
  analysed range `from`–`to`, data read `windowFrom`–`windowTo`, detection threshold). With these the GUI shows
  exactly the same contractions again (**Open ...**). `mda_readResults` / `read_results` read them.
* `contractions`: one row per detected contraction; `summary`: one row per channel and range
  (counts incl. nExtraBeats, nMissedBeats, extraBeats_percent, missedBeats_percent, nUncertain,
  nStimulatedUncertain, nExtraBeatsUncertain, nMissedBeatsUncertain, nMissedDuringContraction, nExtraPulses,
  nElicitedByExtraPulse, nAmbiguous; stimFrequency, stimVariability_percent, arrhythmicFraction, pacedSeconds,
  arrhythmicPacing (see "Arrhythmic pacing"); sensorRate_inferred, repeatedSamples_percent (see "Sensor rate"); mean,
  SD and n of all parameters of the included contractions). Column
  `uncertain` of `contractions`: contraction found with high sensitivity only (option `'detection'`, see "Signal
  processing and detection"). `info.pulses` (sheet / file **pulses**, option `'pulseTable'`, default on): one row per
  stimulus pulse (see "Stimulus assignment").

## Automatic analysis of new recordings (`MyoDishAnalysisWatch`; Python `mda-watch`)
```matlab
MyoDishAnalysisWatch('/data/myodish/raw', '/data/myodish/results', 'rockerFilter', true)
MyoDishAnalysisWatch(raw, results, 'fromDate', '2026-10-01', 'dryRun', true)   % only list what would be analysed
MyoDishAnalysisWatch(raw, results, 'schedule', 'daily 10:00')    % in the background: every day at 10:00
MyoDishAnalysisWatch('status')                                   % scheduled watchers; MyoDishAnalysisWatch('stop')
MyoDishAnalysisWatch('trends', results, 'include', 'ABC00*')      % trend images again from the results
MyoDishAnalysisWatch('reorganize', results)                      % earlier results into the folders of the setups
```
```bash
mda-watch /data/myodish/raw /data/myodish/results --rocker-filter --quiet
mda-watch /data/myodish/raw /data/myodish/results --schedule "weekly Sun 05:00"    # until Ctrl+C
mda-watch /data/myodish/results --trends-only --include "ABC00*"                      # trend images again
mda-watch /data/myodish/results --reorganize                                         # earlier results into the folders
```
Each pass searches the raw folder (with subfolders) for `.mdd` files and analyses the new and changed ones. The
watcher only calls `MyoDishAnalysis`, `mda_readMdd` and `mda_protocols`.
* **After an update of MyoDishAnalysis** (or with other analysis options; 2026-10-12): the recordings analysed earlier
  keep their results, they are **not** analysed again by default (`'reanalyze','new'`). Every pass shows a notice in
  the command window and at the top of the txt and PDF reports: *"MyoDishAnalysis has been updated (now …):
  n recording(s) were analysed with another version (…). This may change the results or lead to inconsistencies
  with new data (see the release notes, CHANGELOG.md)."* with the command that analyses them again:
  `'reanalyze','outdated'` (`--reanalyze outdated`; all recordings of another version, other options or other core
  code; after an update this can take hours). `'reanalyze','all'`: every recording again.
* **Schedule** (`'schedule'`, `--schedule`; 2026-10-12): `'daily 10:00'`, `'weekly Sun 05:00'` (several days:
  `'Mon,Thu 06:30'`; `'weekdays 07:00'` = Mon–Fri), `'every 2 days 10:00'`, `'every 120 min'` / `'every 6 h'` (first
  pass now). MATLAB: a timer in the background of the session, MATLAB stays free between the passes (busy during a
  pass); `MyoDishAnalysisWatch('status')` lists the scheduled watchers with the next and last pass,
  `MyoDishAnalysisWatch('stop')` stops them (`'stop', resultsFolder`: one); it ends with the MATLAB session. Python:
  `mda-watch ... --schedule "..."` runs until Ctrl+C (terminal or background process). Missed passes (computer asleep,
  a pass longer than the interval) are not repeated.
* **Result folders** (`'folders'`, `--folders`; 2026-10-15), so that a daily look does not start with hundreds of
  files:
  ```
  results/ABC000101/                         experiment = folder of the recordings in the raw folder
      ABC000101_overview.png                 all setups x channels at a glance (see "Trend images")
      ABC000101_report.pdf                   analysis report of all recordings of the experiment
      ABC000101_slices.csv                   slice register
      Setup1_ABC000101/                      one folder per setup (series: file name up to its number)
          Setup1_ABC000101_ch1.png ... ch8   course of each channel: since the start and the last 24 h
          Setup1_ABC000101_trends.xlsx       the data of these images
          00/  01/  02/ ...                  one folder per recording (Setup1_ABC000101_2.mdd -> 02/; also its
                                             parallel recordings, e.g. Setup1_ABC000101_2_scheduleFile_...)
  results/mda_index.csv, mda_flags.csv, mda_slices.csv, reports/
  ```
  `'series'` (default): `<experiment>/<series>/<nn>/` for recordings with a number in the name,
  `<experiment>/<name>/` for recordings without a number. `'flat'`: all files of an experiment in `<experiment>/` (as
  before 2026-10-15; trend images in `<experiment>/trends/`). The GUI, the results browser, the flags, the slice
  register and `'trends'` read both layouts. Results of the other layout are moved when a recording is analysed
  again; `MyoDishAnalysisWatch('reorganize', results)` (`mda-watch RESULTS --reorganize`) moves all of them at once and
  makes the images and reports again (`'folders','flat'` / `--folders flat` back). `d =
  MyoDishAnalysisWatch('resultFolder', results, 'ABC000101/Setup1_ABC000101_2.mdd')` (Python `results_of`) returns the
  folder of a recording's results.
* **Result files per recording** (2026-10-14):
  * `<name>.xlsx`: the tables as sheets `summary`, `trends`, `trendComments`, `channels`, `gaps`, `events`,
    `parameters`, `info`, `thresholds`, `labels` (`rockerFilter`); **Open ...** in the GUI (or `MyoDishAnalysisGUI('<name>.xlsx')`) shows the analysis.
  * `<name>_contractions.csv.gz`, `<name>_pulses.csv.gz`, `<name>_overview.csv.gz`: the large tables, compressed
    text (sheets of this size are much slower: 1-min overview of 20,000 rows read in 1.4 s instead of 0.07 s in
    Python, 0.9 s instead of 0.2 s in MATLAB; and Excel has a limit of 1,048,575 rows, exceeded by the contractions of
    24 recordings of 2020–2026). pandas reads them directly; MATLAB: `gunzip` first, or
    `mda_readResults('<name>.xlsx')` (contractions included).
  * `<name>_protocols.xlsx`, `<name>_protocols_contractions.csv.gz`, `_protocols_pulses.csv.gz`: stimulation protocols.
  * `<name>_ch<c>.png`: trend images (see below; flat layout: `trends/<name>_ch<c>.png`).
  * `'resultFormat','csv'` (`--result-format csv`): one csv file per table as before 2026-10-14
    (`<name>_summary.csv`, `_contractions.csv`, `_pulses.csv`, `_parameters.csv`, `_info.csv`, `_thresholds.csv`,
    `_labels.csv`, `_overview.csv`, `_events.csv`, `_gaps.csv`, `_channels.csv`, `_trends.csv`, `_trendComments.csv`,
    `_protocols_*.csv`; `'compress',true`:
    contractions and pulses as `.csv.gz`). The GUI, the results browser, the flags and the slice register read both
    formats; results are not analysed again because of the format (`'reanalyze','all'` converts them; the files of
    the other format are removed).
* **Tables** (sheets or files):
  * `summary`: one row per channel and time range. The ranges are time bins (`'binMinutes'`, default 60)
    **without the stimulation protocols** (default; `'includeProtocols',true` keeps them, `'protocolMarginSeconds'`
    also excludes some time after each protocol); a bin with a protocol gives several ranges. Columns `range` (clock
    time of the start of the range), `bin` (clock time of the start of the bin), `nComments` / `comments` (comments of
    the log file in the range, this channel or all channels).
  * `contractions`: `'contractions','all'` (default: every contraction), `'thinned'` (every
    `'thinFactor'`-th contraction per channel, default 10, `'thinMode','nth'`; or the median of blocks of
    `'thinFactor'` successive contractions of the same type and rocker state, `'thinMode','median'`; extra beats and,
    with `'includeProtocols'`, the contractions in the protocols are always complete) or `'none'`. Columns
    `sampledEvery` (number of contractions represented by the row) and `sampleMode` (`singleBeat` / `median`).
    `.csv.gz`: a double click unpacks it on macOS and Windows. Trends from the summary or the overview (all
    contractions): every n-th contraction can alias the rocker modulation of the amplitude.
  * `overview` (`'overviewSeconds'`, default 60; 0 = none): medians of **all** contractions per 1-min
    window (file time, split at the ranges), channel, beat type, rocker state and inclusion, with `window` (clock time
    of its start), `t_from`, `t_to`, `nBeats`, `beatsPerMinute` and the median of every parameter. About 1/30 (0.5 Hz)
    to 1/60 (1 Hz) of the rows of all contractions (8-h recording, 7 channels: 242,270 contractions, 99 MB →
    6,949 rows, 2.8 MB). Medians of fixed windows instead of blocks of n successive contractions:
    where stimulated and extra beats alternate (spontaneous rate above the pacing rate), blocks of one beat type stay
    short. Basis of the trend images and of the slice register.
  * `protocols`: every contraction in the protocols, summary per protocol, channel and group, `protocolResults` (if
    the log file contains protocols).
  * `events` (`'events',true`): all entries of the log file with clock time, time in the file, channel,
    code, category (comment, protocol, recording, schedule, stimulation, rocker, calibration, warning, other) and text.
  * `gaps` (`'gaps',true`, default): periods without force signal (`mda_signalGaps` / `signal_gaps`, see
    below) with clock times and the comments of the log file within 5 min of their start or end. The summary gets
    the columns `noSignal_s` (s without signal in the range) and `nChamberOut` (chambers taken out in the range).
  * `channels` (`'gaps',true`): one row per channel with recording, `recordingStart`, `fileLength_s`,
    `calibration` (`Calibration` entries of the log file for the channel, AU per mN, several values in the order of
    time separated by `;`; 2026-10-10) and the status at the end of the recording (`beating`, `not beating` = no contraction in the last 30 min with signal
    outside the stimulation protocols, `protocols only` = no time outside the protocols, not analysed, `removed` =
    chamber taken out and not put back, `signal lost` = technical, `no slice`), `beatingAtEnd`, s with and without
    signal, chambers taken out,
    technical failures, number of contractions, last contraction (time in the file, clock time, median amplitude of
    the last 10 included contractions and in % of the 95th percentile of the recording), `idDate` (date of the
    experiment ID in the file name: a part of letters + 6 digits yymmdd, e.g. `ABC000101`) and `daysSinceIdDate` at
    the last contraction (or the end of the signal), `daysInCulture`, the labels `setupID`, `sliceID`, `species`,
    `sampleID`, `cultureStart` and `endComments` (comments of the channel about discarded, removed, not beating,
    fixed, frozen, … slices).
  * `parameters`, `info`, `labels` (`rockerFilter`: rocker artifact per channel and 30-min chunk). Labels per
    channel: `<name>_labels.csv` next to the `.mdd` file (saved by the GUI).
* **Trend images** (`'trends'`, default true; `--no-trends`; 2026-10-14), a quick look every morning (PNG, 150 dpi):
  * `<experiment>_overview.png` (2026-10-15): one row per setup (numbered series), one column per channel. Each cell:
    the amplitude over the whole time course of the experiment, the last 24 h yellow, new slices dashed; background =
    status of the last slice at the end of its data (green beating, red not beating, grey removed / replaced, orange
    signal lost, white no slice); texts: last amplitude, change in the last 24 h (first vs. last 2 h), number of the
    slice, last amplitude in % of the maximum of the slice. A **red frame** with a number marks channels with red flags
    (check the analysis) in any of their recordings, also of earlier passes (`mda_flags.csv`).
  * `<series>/<series>_ch<c>.png` (2026-10-15; flat: `trends/`) per setup and channel: per parameter, left the whole
    time course since the start of the series (all slices of the channel, line = median per bin of each slice, 30 min
    up to 7 days, 2 h beyond; slice changes dashed; the last 24 h yellow; recordings with red flags as red bars at the
    bottom; dates with the day in culture), right the last 24 h of the data (10-min line, protocols, comments numbered
    with a list below). The first line under the title gives the status of the last slice (since, end status, last
    contraction, amplitude in % of its maximum). Data in `<series>/<series>_trends.xlsx`: sheets `course` (channel,
    slice, bin = clock time of its start, dayInCulture, nBeats, the parameters = median of the 1-min values of the bin,
    binMinutes), `last24h` (the 1-min values), `comments` and `slices` (the rows of the register of the setup).
    Replaces the images per slice of 2026-10-14.
  * `<name>_ch<c>.png` per recording and channel with at least 20 included contractions: one panel per
    parameter of `'trendParameters'` (default amplitude, diastolicForce, TTP90, TTR90; any parameter or
    `beatsPerMinute`; `--trend-parameters`). Dots = overview (median per minute of the included contractions), line =
    their median per 10 min (5 min up to 3 h, 30 min beyond 30 h), clock time; stimulation protocols as light blue
    bands with their name, periods without signal grey, comments of the log file as numbered purple lines with a
    list below; during a protocol only the comments at its start and end are shown. Title with the labels of the
    channel (setupID, sliceID, species, tissue, sampleID, treatment); in each panel the median and the change from
    the first to the last 2 h.
  * The data of the images (to plot them again in another program): sheet `trends` of `<name>.xlsx` with one row
    per channel and 1-min window with included contractions (`channel`, `window` = clock time of its start, `t_from`,
    `nBeats`, the trend parameters in the units of the sheet `parameters`, `bin_from`: the line is the median of the
    rows with the same `bin_from`; at most 8 × 1,440 rows per day, far below the Excel limit) and sheet
    `trendComments` (`channel`, `number` as in the image, `t_file`, `clockTime`, `text`).
  * `MyoDishAnalysisWatch('trends', resultsFolder, 'include', ..., 'trendParameters', {...})` (`mda-watch RESULTS
    --trends-only ...`): the images and these sheets again from the result files, e.g. with other parameters or for
    results of earlier versions (also csv results), and the images of the setups and experiments.
* **Slice register** (`'register',true`, default; `mda_sliceRegister` / `slice_register`, see below):
  `<experiment>/<experiment>_slices.csv` and `mda_slices.csv` (all experiments), updated after every pass.
* **Index** `mda_index.csv` (one row per recording; the same file for MATLAB and Python): size and time (UTC) of the
  `.mdd` file, size of the log file, status (`ok`, `error`, `running`, `incomplete`, `parallel`, `noLog`), version,
  implementation, fingerprint
  of the core functions, options, analysis time, number of contractions, message. `'reanalyze'`: `'new'` (default)
  = new and changed recordings; `'outdated'` = also those analysed with another version, other options or (same
  implementation) other core functions; `'all'`. Recordings with an analysis error are retried when the file, the
  version, the options or the core functions change, or with `'retryErrors',true`.
* **Report** `reports/mda_report_<date>_<time>.txt` per pass: for every analysed recording and channel the number of
  contractions, capture (% of the stimuli followed by a contraction), extra beats (% of the detected contractions),
  mean amplitude in the first and last bin with ≥ 10 contractions and flags (no contractions, capture < 90 %, extra
  beats > 10 %, amplitude change > 30 %; `'flagCapture'`, `'flagExtraBeats'`, `'flagAmplitudeChange'`); periods
  without signal by type and the channels that do not end beating.
  The txt report lists the PDF reports of the experiments.
* **PDF report per experiment** `<experiment>/<experiment>_report.pdf` (`'report'`, default true; Python
  `--no-report`; one report per experiment instead of one per pass since 2026-10-15; `mda_report_root.pdf` for
  recordings directly in the raw folder), made again after every pass with analysed recordings of the experiment:
  first page the overview image, then **all** analysed recordings of the experiment x channels with their flags (the
  recordings of the last pass in bold, the earlier ones with the flags of `mda_flags.csv`: red flags of earlier days
  stay visible, also in the list of the channels to check), and pages with traces of the red channels of the last
  pass. See "Analysis report"; the GUI commands open the `<name>.xlsx` (csv results: `<name>_info.csv`) of the
  recording (settings of the watcher). MATLAB also prints the channels to check as links in the command window.
* **Flags** `mda_flags.csv` (2026-10-14; with the PDF report): the flags of the analysis report per recording and
  channel (file, analyzed, channel, label, status, nDetected, capture_percent, flags, level, red, yellow, from / to =
  window of the red flags) of all analysed recordings, updated after every pass; read by the results browser of the
  GUI (**Results ...**), the experiment reports and the overview images.
  `[T, missing] = MyoDishAnalysisWatch('flags', resultsFolder, compute)` (Python `X, T, missing =
  flags_table(results_folder, compute)`) returns the flags of the current analyses; `compute = true` computes the
  missing ones (results of older versions) from the result files and saves them (not while a watcher is running).
* **Skipped** while written or copied (2026-10-13): files changed in the last 10 min (`'minFileAgeMinutes'`), names
  starting with `.` (rsync temporary files, hidden folders), and:
  * `running`: no `Recording stopped` in the log file yet; analysed when the end of the data (start of the recording
    in the log file + duration from the file size) is 30 h ago (`'incompleteAfterHours'`, `--incomplete-after`),
    e.g. aborted recordings (without clock time, or with the clock of the recording computer more than 1 h ahead:
    30 h after the last change of the files);
  * `incomplete`: the file is shorter than the recording in the log file (`Recording started` → `stopped`) by more
    than 10 s **and** more than 2 % (`'incompleteTolerance'`, `--incomplete-tolerance`; 1 % before 2026-10-14), e.g.
    a copy to a network drive that was interrupted; checked again in every pass, analysed with a note in the message
    when unchanged for 30 h, and again when the copy is completed (the file changes). The tolerance is relative
    because the sample
    clock of the controllers deviates from the clock of the computer: in 15,748 stopped recordings of 2020–2026 the
    file was shorter than the log duration by at most 0.13 % in 99 % of them (99th percentile 2020: 0.35 %, 2021:
    0.58 %, from 2022 on: 0.05 %; 24-h recordings: up to 90 s), in one setup of 2021 by 1.1–2.1 %. The 10 s protect
    short recordings, whose start and stop entries can be 1–2 s off (99th percentile of recordings < 15 min: 2.4 s).
    9 recordings exceed both limits: 6 empty files, one with 1 % of its data, one 2.8 % short and one of that setup
    (2.05 %); with 1 % they were 22 (14 of that setup), with 10 s alone 1,364.
    Also `incomplete`, until the file changes (no time limit): empty files (no data; 258 of 17,237 recordings of
    2020–2026, analysed as `ok` without data before) and files dated before 1990 (robocopy dates files to 1980 until
    their copy is finished);
  * `parallel` (`'parallel','skip'`, default; `--parallel skip`): parallel recordings (schedule files, snapshots,
    FFR or Iso recordings started from the MyoDish software) whose main recording is in the same folder and selected
    in the same pass (not left out by `'include'`, `'exclude'`, `'filter'` or `'fromDate'`); main recording = a
    recording whose log file lists the file as `started parallel recording` with the same duration (± max(5 s,
    1 %)). Their data are in the main file and their stimulation protocols in the main file's `_protocols_*` results;
    the message names the main file and the time window in it (e.g. `parallel recording of expA/rigA_X_1.mdd
    (54.6-7554.6 s of the main file)`). Parallel recordings whose main file is not selected (e.g.
    `'include','*schedule*'`: the schedule files only) or missing (only the parallel file copied), and all of them
    with `'parallel','analyse'`, are analysed; their message starts with `parallel recording of <main file> (...):
    analysed (...)`. The slice register ignores parallel recordings whose main file has results in the same results
    folder, so that no contraction or stimulus of a slice is counted twice in its time course. 6,674 of the 16,463
    recordings with log file of 2020–2026 are such parallel recordings (5,063 schedule files, 687 snapshots);
  * `noLog`: no log file, or an empty one; analysed when the log file appears or changes.

  A lock file (`mda_watch.lock`) prevents two watchers on the same results folder (MATLAB, Python, another
  computer): a second watcher skips its pass. The running watcher refreshes it after every recording and during long
  steps (2026-10-14); a lock file not refreshed for 1 h (watcher crashed) is ignored (before: 12 h after its
  creation). The index is written after every analysed recording and once at the end of the pass.
* **Daily without an open MATLAB / terminal**: the scheduler of the operating system (cron / launchd / Windows task
  scheduler) with `mda-watch ...` or `matlab -batch "MyoDishAnalysisWatch(...)"`.
* **Selecting recordings** (2026-10-13): `'include'` / `'exclude'` (Python `--include` / `--exclude`) take wildcard
  patterns (`*` any characters, `?` one character; several as a cell array, separated by `,` or `;`, or after
  `--include`): a pattern without `/` is matched against every folder name and the file name of the path relative to
  the raw folder, a pattern with `/` against the whole path, e.g. `'include','ABC00*'` (all folders starting with ABC00),
  `'include','*schedule*'` (schedule files), `'exclude','*test*'`. Upper / lower case is ignored unless
  `'caseSensitive',true` (`--case-sensitive`). Advanced: `'filter'` (`--filter`), a regular expression on the
  relative path (`help MyoDishAnalysisWatch`, section ADVANCED OPTIONS; `mda-watch --help`, advanced options).
* Further options: `'resultFormat'`, `'folders'`, `'trends'`, `'trendParameters'` (see above), `'newSliceHours'` (slice
  register, default 2), `'maxFiles'`, `'protocols',false`, `'quiet',true`; all other name/value pairs are analysis options of `MyoDishAnalysis` for all recordings (e.g.
  `'rockerFilter',true`: rocker artifact removed in chunks of 30 min with 60 s context, result per chunk in the
  sheet / file `rockerFilter`). Python only: `--workers n` analyses n recordings in parallel (archives).
* Tested on 31 recordings (729 MB, rat, rabbit, pig, human, schedule files up to 2 h, single channel, sharp
  electrode) on one Mac: MATLAB 149 s, Python 69 s; results of MATLAB and Python identical (116 result files, max. relative
  difference 3e-10).

## Periods without signal: chamber taken out, sensor board failures (`mda_signalGaps`; Python `signal_gaps`)
```matlab
G = mda_signalGaps('recording.mdd')          % one row per period and channel
```
Without a sensor board the controller repeats the last value of the channel: the signal stays at exactly the same
number, while a connected sensor never gives identical values for seconds (noise of the AD converter). A period without
signal = at least 2 s (`'minSeconds'`) of identical consecutive raw samples; periods of a channel less than 0.5 s apart
are one (`'mergeSeconds'`). Types:
* `chamber out`: one channel, the chamber was taken out (and put back at `to`, unless `untilEnd`). Why is not in the
  signal: see the comments of the log file (the gaps table lists those within 5 min).
* `board group`: ≥ 3 channels of the same group (1–4 or 5–8) lose the signal within 1 s (`'simultaneous'`), or 2
  channels within 0.1 s (`'simultaneousPair'`) – faster than a person can take chambers out (with two hands, two
  chambers at once). A defective sensor board can disturb all boards of its group, so the chambers were probably not
  taken out at all.
* `controller`: the same with channels of both groups (controller, connection). `saturated`: the value held is the
  limit of the AD converter. `no signal`: the whole recording (no chamber in this channel).

Periods that begin with the file (`fromStart`, chamber put in later) are grouped by their end (signal back). Further
columns: `duration`, `nSimultaneous`, `spread` (s between the first and the last channel of the event), `value`
(value held), `levelBefore` / `levelAfter` (10th percentile of the 5 s before / after the period: diastolic level;
`levelChange` shows another preload or another slice after putting the chamber back) and `spikeBefore` / `spikeAfter`
(spike when the chamber is taken out / put back). In a sample of 88 daily recordings with periods without signal, 19
of 21 technical events (2–4 channels) had a spread ≤ 0.01 s (max. 0.42 s, 3 channels); of 606 chambers taken out one
after the other, 2 followed within 1 s (0.36 and 0.6 s: both hands, end of the experiment), none within 1–2.3 s
(median 5.3 s).

## Slice register (`mda_sliceRegister`; Python `slice_register`)
```matlab
R = mda_sliceRegister('/data/myodish/results')     % all experiments; also written by the watcher after each pass
```
One row per **slice**: a channel of a setup from putting the slice in until it was taken out, the signal was lost or
the data end. Built from the watcher results (tables channels, gaps: sheets of `<name>.xlsx` or `_channels.csv`,
`_gaps.csv`; `<name>_overview.csv(.gz)`; both layouts of the watcher, see "Result folders"), written to
`<experiment>/<experiment>_slices.csv` (experiment = folder of the recordings in the raw folder) and `mda_slices.csv`
(all experiments). The recordings of one setup (series: file name up to its number, e.g. `rigA_sampleX_0`,
`rigA_sampleX_1`, …) are followed channel by channel in the order of their start. A **new slice** begins with the first
signal of a channel, after a chamber-out period with a comment such as *new slice*, *replaced*, *exchanged*,
*getauscht*, when the label `sliceID` changes, and after a recording without signal in this channel or ≥ 2 h without
signal (`'newSliceHours'`) – unless a comment within 5 min of the start or end of that period says the slice was put
back (*moved back*, *put back*, *reinserted*, *wieder eingesetzt*; counted in `nPutBack`). Shorter chamber-out periods (medium change, looking at the slice) belong to the slice; technical
periods (board group, controller, saturated) do not end it. Which slice was put back is not in the signal: a slice
exchanged within 2 h without comment or label stays one row (documentation by the control software will close this
gap).

Columns: `experiment`, `series`, `channel`, `slice`, labels (`setupID`, `sampleID`, `species`, `sliceID`), `idDate`,
`startTime`, `endTime`, `daysInSetup`, `startReason`, `insertedLater` (not with the first signal of the series: possibly
another preparation, another species), `endStatus` (`removed`, `beating at end of data`, `not beating at end of data`,
`signal lost`, `protocols only`, `replaced (other sliceID)`), `beatingAtEnd`, `lastBeat`, `lastAmplitude` (last 1-min
window with contractions), `maxAmplitude` (95th percentile of the 1-min amplitudes), `lastAmplitude_pctMax`,
`nBeats`, `dayStart` / `dayEnd` (days since the label `cultureStart` or since 00:00 of `idDate`; not for slices
inserted later without `cultureStart`), `daySource`, `nRecordings`, `firstRecording`, `lastRecording`, `nChamberOut`,
`outHours`, `longestOut_min`, `nPutBack`, `nTechnical`, `calibration` (calibration values of the channel in the
recordings of the slice, `;` separated), `calibrationChanged` (1 if the calibration changed during the slice or differs
from another row with the same `sliceID`, e.g. a slice moved to another setup: force values and fold changes over time
are only comparable in µN; 2026-10-10), `endComments`. With `endStatus`, `lastAmplitude_pctMax` and `dayEnd` the
slices that died or were taken out can be counted and classified (e.g. dead vs. weak) with a criterion chosen later.
`'trends',true` (`trends=True`; the watcher with its default `'trends',true`; 2026-10-15): the course image per setup
and channel `<series>/<series>_ch<c>.png`, its data `<series>/<series>_trends.xlsx` and the overview image
`<experiment>_overview.png` (see "Trend images" of the watcher; `'trendParameters'`). `[s, n] =
mda_sliceRegister('series', name)` gives the series and number of a file name, `mda_sliceRegister('resultFolder', rel,
folders)` the folder of its results.

## Windows before and after a treatment (`mda_timepoints`; Python `mda-timepoints`; 2026-10-15)
```matlab
res = '/data/myodish/results';                       % results folder of the watcher
TP = mda_timepoints(res, 'Mava100', 'Setup1_ABC000101', [1 3 5], '2000-01-01 15:20', [-10 10 60 240 1440])
TP = mda_timepoints(res, 'Ome2uM', {'Setup1_ABC000101', 'Setup2_ABC000101'}, {[1 2], [4 5 6]}, ...
                    {'2000-01-01 13:20:00', '2000-01-01 13:30:00'}, [-60 120], 300)   % one time per setup, 300 s
```
```
mda-timepoints results Mava100 --series Setup1_ABC000101 --channels 1 3 5 --time "2000-01-01 15:20" --offsets -10 10 60 240 1440
```
Contraction parameters of channels of one or more setups (series: file name up to its number) in windows that start
exactly at the treatment time + `offsets` (minutes, required; negative = before) and last `seconds` (default 120 s);
windows are never shifted. Inputs: `channels` `[]` (all channels with contractions), a vector (every series), a matrix
with one row per series (0/NaN = none) or a cell array with one vector per series; `time` one clock time, one per
series or one per channel (the size of the channel matrix, or in the order of the channels). Parameters (default,
`'parameters'`): `amplitude`, `diastolicForce`, `TTP90`, `TTR90`, `CD50`, `CD90` (10 % upstroke to 90 % relaxation =
TTP90 + TTR90 of the beat), `dFdtMax`, `dFdtMin` (in **mN/s**; the analysis: µN/s), `AUC`, `beatsPerMinute` (all
contractions). Per window (sheet `summary`; 2026-10-16): counts (`nBeats`, `nIncluded`, `nExtra`), a **note**, per
parameter the **mean** of the included contractions (column `<parameter>`) and its normalized value, then per parameter
`_SD` and `_SEM` (SD / √n), then `_median`, `_q25`, `_q75`, then the average beat (`nAvgBeats`, `avgBeat_diastolic`,
`avgBeat_amplitude`). Normalized to the baseline window (the last negative offset, `'baseline'`):
`<parameter>_pctBaseline` = 100 × mean / mean of the baseline window; for the diastolic force, which can be near 0 or
negative, the absolute change `diastolicForce_delta` = mean − baseline mean (µN). **Windows without contractions**
although recorded (no chamber out / no signal in the window): the slice does not contract – `amplitude`, `AUC`,
`dFdtMax`, `dFdtMin` and `beatsPerMinute` are 0 (0 % of baseline), `TTP90`, `TTR90`, `CD50`, `CD90` NaN, and the
diastolic force (e.g. a contracture without beats) is taken from the signal: median of the force in the window,
filtered as in the analysis, minus the zero force (needs the recording; note `diastolic force from the signal`).
Notes: stimulation protocols, chamber out / no signal, user comments in the window, fewer than 80 % of the expected
contractions, another slice than in the baseline window (slice register; then no normalized values), `no recording`,
`pending: no data yet` (call again after the next pass of the watcher). `'sampleID'` and `'group'` (one text or one
per series) name the sample (default: slice register, else the series name after the setup: `Setup1_ABC000101` →
`ABC000101`) and its group (e.g. `'HTX'`) for pooling (below). Files in
`<experiment>/timepoints/<label>_<yyyy-mm-dd-HH-MM>/` (never changed by the watcher): `<label>_<time>.xlsx` (sheets
`summary`, `matrix` = channels × offsets per parameter (mean and normalized), `course` = 1-min values (medians of the
overview) from 30 min before the first to 30 min after the last window, `beats`, `averageBeats`, `averageBeatsMean`,
`info`) and the images, each **absolute (`_abs`) and normalized (`_norm`)**: `_timepoints_abs/_norm.png/.fig`
(mean ± SEM of the beats or % of baseline over the windows, one line per channel, black = mean ± SEM of the channels),
`_course_abs/_norm` (1-min course, black = mean ± SEM of the channels), `_averageBeats_abs/_norm` and
`_averageBeatsMean_abs/_norm` (Python: `.png` and `.svg`; without baseline window only `_abs`). `TP` is a struct
(Python: dict) with the same data (`TP.summary`, `TP.matrix.amplitude` (means), `TP.pctBaseline.amplitude`, ...).
Times of a substance added during a recording: the comment in the MyoDish log file (shown in the course images of the
watcher); a comment is often typed a few minutes before or up to an hour after the addition. **`'t0','chamberIn'`**
(Python `t0="chamberIn"`, `--t0 chamberIn`; 2026-10-18): per channel the end of the chamber-out period nearest to the
given time (periods ending within ± `'t0Window'` minutes, default 90) = the chamber with the substance put back; without
such a period the given time (note per window; columns `timeGiven`, `t0`). **Paced windows** (stimulated or extra
beats in the window; 2026-10-18): only the stimulated contractions are averaged; from 5 % extra beats the note
*arrhythmic: n extra beats (x % of the contractions)*. In the course images the mean of the channels is drawn twice:
solid where all channels have values, dashed with gaps of up to 3 h interpolated per channel. `'outputFolder'`: files in
`<outputFolder>/<experiment>/<label>_<time>/` (used by `mda_study`).

**Average beats** (`'averageBeats'`, default true; reads the recordings, read only; `'rawFolder'` if the raw folder is
mounted elsewhere than during the analysis): per window the mean of the included beats (no extra beats, no other
contraction in the segment), aligned at the stimulus (unpaced: onset), from 0.1 s before to the next beat, filtered as
in the analysis, minus the zero force of the channel. Three versions: `force_uN` (absolute: diastolic force kept, e.g.
the rise under omecamtiv mecarbil), `norm_baselineAmplitude` (baseline beat from 0 to 1, all windows on this scale:
change of amplitude and diastole relative to the baseline, comparable between slices) and `norm_ownAmplitude` (each beat
with amplitude 1, its diastole keeps the change against the baseline in baseline amplitudes: kinetics without losing the
diastolic effect), each with its standard error (`_SE`, SD of the beats / √n). Sheets `averageBeats` and
`averageBeatsMean` (mean, SD and SE of the channels), images `_averageBeats` (one row per channel) and
`_averageBeatsMean` (± SE shaded), and **one 16:9 slide per channel** `averageBeats/<series>_ch<c>.png/.fig` (Python
`.png/.svg`): average beats ± SE in µN and with the own amplitude = 1, below a table of the windows (n, amplitude,
diastolic force, TTP90, TTR90 and their change against the baseline, note) – ready for a slide deck. **Alternans**: two amplitude groups of the included beats
(1-D 2-means; each ≥ 20 % of the beats, means ≥ 20 % and ≥ 3 SD apart) give a note, e.g. *alternans: 2 amplitude groups
1693 / 3727 uN (42 % small beats, 83 % of successive beats switch)* (≥ 80 % switch; otherwise *irregular amplitudes: 2
groups ...*), and average beats of the small and the large beats; mean and median then describe neither group – see
the average beats.

## Pooling analyses by treatment (`mda_poolTimepoints`; Python `mda-pool-timepoints`; 2026-10-16)
```matlab
PT = mda_poolTimepoints(res)                                   % all analyses below the results folder
PT = mda_poolTimepoints(res, 'labels', {'CTRL', 'OME3uM', 'MAVA1uM'}, 'name', 'myosinModulators')
PT = mda_poolTimepoints(R(:, 2))                               % TP structs of mda_timepoints calls of a script
S = PT.slices; s = S.offset_min == 120;                        % statistics, sample as random effect
BarsWithErrorsFromList(S.amplitude_pctBaseline(s), S.treatment(s), 'lme', 'IDs', S.sampleID(s))
```
```
mda-pool-timepoints results --labels CTRL OME3uM MAVA1uM --name myosinModulators
```
The analyses of `mda_timepoints` (`<experiment>/timepoints/<label>_<time>/`, any experiment, sample or day) are pooled
by their label (treatment). Files in `<results>/timepoints_pooled/<name>/` (`'outputFolder'`): `<name>.xlsx` with the
sheet **`slices`** (one row per slice and time point: `treatment`, `substance`, `concentration`, `concentrationUnit`
(from the label: `OME0.5uM` → OME, 0.5, uM), `group`, `sampleID`, `sliceID` (`<series>_ch<c>`), `timePoint`
(`-1 h`, `+2 h`), `offset_min`, `isBaseline` and all columns of the summary of `mda_timepoints`) – one long table for
statistics, e.g. with `BarsWithErrorsFromList` – and the sheets `samples` (mean of the slices per sample),
`treatments` (per treatment and time point: n slices, n samples, mean, SD and SEM of the slices, mean and SEM of the
samples), `course`, `averageBeatsMean`, `analyses`, `info`; per treatment `<treatment>/<treatment>_timepoints`,
`_course` and `_averageBeatsMean` (`_abs` and `_norm`, all slices, black = mean ± SEM of the slices), and
`treatments_abs/_norm/_vsControl` (all treatments side by side: slices as dots, mean ± SEM per time point).
**Against the controls** (`'control'`, default: labels starting with CTRL, control, vehicle or DMSO; the control
slices of the same sample at the same time point, otherwise all control slices; columns `controlReference`,
`nControlSlices`): `<parameter>_pctBaseline_vsControl` = 100 × pctBaseline / mean pctBaseline of the controls
(corrects the drift of the controls) and `diastolicForce_delta_vsControl` = Δ − mean Δ of the controls (µN). Slices of one sample
are not independent: use the sheet `samples`, or the slices with the sample as random effect. The sample ID comes
from `mda_timepoints` (`'sampleID'`); analyses of earlier versions (without sample ID and SEM) are skipped and listed
in the sheet `analyses` – call `mda_timepoints` again.

**Exclusions, QC and statistics** (2026-10-18): column `qc` per window (codes from the notes: arrhythmic, capture,
noContractions, alternans, irregular, protocol, signal, otherSlice, comment, pending). `'exclude'` (Python `exclude=`,
`--exclude ID[:CH[:FROM[:REASON]]]`) leaves out a slice or its windows from a time point on, e.g.
`'exclude', {'ABC000101', 6, [], 'arrhythmic'}` (id = sampleID, series or sliceID; channel empty = all; from empty = the
whole slice); listed in the sheet `excluded` and in `info`. Sheet **`statistics`** per treatment, time point and
parameter (normalized values): mean and SEM of the slices and of the controls, difference, paired difference of the
samples with both, and a linear mixed model y ~ treatment + (1 | sample) (REML; degrees of freedom n − 2 as `fitlme`
'Residual') only if both groups have ≥ 3 samples, otherwise descriptive only. Exploratory: not corrected for multiple
comparisons; confirm results for a publication with a dedicated tool. Also written: `<name>_figure_norm.pdf/.svg/.png`
and `<name>_prism.xlsx` (below).

## Figures for a manuscript and GraphPad Prism (`mda_plotTimepoints`; Python `plot_timepoints`; 2026-10-18)
```matlab
[h, files] = mda_plotTimepoints(PT, 'parameters', {'amplitude', 'diastolicForce'}, 'output', 'fig2')
[h, files] = mda_plotTimepoints('pool.xlsx', 'mode', 'abs', 'panelSize', [50 40], 'timeUnit', 'min')
T = mda_plotTimepoints('prism', PT)            % T.amplitude_pctBaseline: one row per time point, one column per slice
```
One panel per parameter (default amplitude, diastolicForce, TTP90, TTR90), x = time after the treatment (h or min), per
treatment the mean ± SEM of the slices (markers, error bars) and the single slices (thin lines), legend *treatment (n =
slices/samples)*, controls black, other treatments in the colour-blind safe Okabe-Ito colours, Arial 7 pt, panel size in
mm; files `.pdf` and `.svg` (vector) and `.png` (300 dpi). Modes `'norm'` (% of baseline, diastolic force as change in
µN), `'abs'`, `'vsControl'`. The Prism tables: one sheet per value column in `<name>_prism.xlsx`, columns
`treatment|sample slice` (grouped table: paste per treatment).

## A study from one design table (`mda_study`; Python `mda-study`; 2026-10-18)
```matlab
mda_study('template', 'design.xlsx')           % empty design table with an example row
S = mda_study('design.xlsx', 'resultsFolder', res, 'name', 'OME_2026', 'offsets', [-30 10 60 240], 't0', 'chamberIn')
```
```
mda-study design.xlsx --results results --name OME_2026
```
One row per slice (sheet `slices`; settings in the sheet `settings` or as name, value pairs): `series`, `channel`,
`treatment`, `time`, `sampleID`, `group`, `exclude`
(empty, `all` or minutes from which on), `excludeReason`. Settings: `offsets`, `seconds`, `baseline`, `t0`, `t0Window`,
`control`, `order`, `parameters`, `rawFolder`, `averageBeats`, `figures`, `outputFolder`. Runs `mda_timepoints` once per
treatment (`<study>/analyses/`), pools them with the exclusions into the study folder (default
`<results>/studies/<name>/`) and writes a copy of the design and `<name>_methods.txt` (English methods text: version,
windows, t0, paced beats, normalization, groups with slices and samples, exclusions, statistics) – the design table is
the record of what was analysed and why slices were left out.

## Stimulation protocols (`'protocol'`, `'groupBy'`; GUI: **Protocols ...**)
Protocols such as force-frequency (FFR), refractory period (RP, S1-S2), stimulation threshold (ST), post-rest
potentiation (PRP) or pulse duration (PD) are found from the comments and schedule-file events of the log file and
analysed per value of their stimulation quantity.
```matlab
P = mda_protocols(file)                                              % protocols in the log file
[c, s] = MyoDishAnalysis(file, [3 6], [], [], 'protocol', 'FFR');   % per pacing frequency, rocker at rest
[c, s] = MyoDishAnalysis(file, 1, [], [], 'protocol', 'RP', 'rocker', 'any');   % per S2 interval, all beats
[c, s] = MyoDishAnalysis(file, 5, 60, 330, 'groupBy', 'log:chargeDuration');   % any range and log quantity
```
* **Finding the protocols** (`mda_protocols`): pairs of comments `start … protocol` / `end … protocol` (also
  `start of …`, `… protocol started` / `… ended`). A start is paired with the next end of the same name, otherwise of
  the same type; several protocols of the same type are numbered (`FFR 1`, `FFR 2`). **Start without end comment**
  (2026-10-10): the end is estimated – the start of regular pacing after the protocol start (per stimulated channel
  the first run of stimuli that lasts > 5 min + one interval with the same interval ± max(5 ms, 2 %), current and
  pulse duration (log `chargeDuration`); lower median over the channels; pulses < 50 ms after the previous one are
  no pacing (status channel errors); `mda_protocols(file, minutes)`, 0 = off), otherwise the start of the next
  protocol (any type) or the end of the file. Note `no end comment: end estimated at 540 s (start of regular pacing:
  0.5 Hz, 50 mA, > 5 min)` (or `(start of the next protocol '…')`, `(end of the file)`) in the protocol table and in
  the column `protocolNote` of `protocolResults`. Checked with 125 protocols that have an end comment (end estimated
  as if it were missing): FFR, ST, RP, PRP mostly within 10 s of the comment (the regular pacing starts a few s before
  it); PD protocols followed by another protocol within < 5 min end at that protocol. Type from keywords:
  FFR / frequency → `FFR`, refractory / S1S2 → `RP`, threshold / stimCurrent → `ST`, post rest / post pause / PRP → `PRP`,
  pulse duration → `PD`, rocker speed → `rockerSpeed`, others `other` (FFR, RP, ST, PRP, PD also as words of a
  name such as `PD_Test_12Steps`). Schedule files loaded by a schedule (log events `Loaded schedule file …` /
  `Jumped back from loaded schedule file …`) are protocols, too, if their file name contains such a keyword
  (e.g. `FFR_60beats_0.2-4Hz…`, `RP_1000-240ms_FJump…`, `StimThreshold_2-90mA`, `PostRestPotentiation`); name = file
  name. Comments and file names about the schedule itself (`start scheduleFile_humanVentricle`) are ignored; of two
  protocols of the same type within each other (comment and schedule file) the outer one is listed. The table can be edited (`from`, `to`,
  `groupBy`) and passed as `'protocol', P`; the GUI shows it editable (`+ selected range` adds the range of the main
  window).
* **Structured events of the control software** (builds from 2026-10, release 2.2; 2026-10-18): besides the old text
  lines, the log file gets lines whose value is one JSON object (codes `system`, `slice`, `protocolRun`,
  `scheduleRun`, `doc`, `chamber`, `rigor`, `backup`). `mda_logEntries(logFile, 'events')` (Python `log_events`)
  returns them as a table: time in the file, dataLogTime as written (`t_logged`), channel, code, event, actionId, by,
  `waiting` and all fields (`data`, read by name). Lines cut off by a crash are counted and left out. **Waiting
  lines** (2026-10-20): the software keeps what happens while no main recording runs and writes it into the next main
  log right before its `LogFile created/opened`; these lines (after the last `LogFile closed` of the log, or from
  `MyodishControlSoftware opened`, up to its next opening; `LogFile2`/`LogFile3` of the second and rocker stop
  recording included) get the time of that opening, since their dataLogTime is the frozen counter of the last main
  recording (often of another file).
  **Protocols from `protocolRun`**: where the log has these events, `mda_protocols` takes the protocols from them (start
  paired with end or abort by `run`; exact times; type and name of the start, also for protocols started by hand;
  notes `aborted: <reason>`, `started before this recording`, `started before this file`, `no end in the log: …`);
  the automatic comments `start <TYPE> protocol` / `end <TYPE> protocol` written right before them are not read again
  (each paired with the next `protocolRun` line of its kind and type), and a comment protocol of the same type that
  overlaps one is dropped. New types of the software: `doseResponse`,
  `substance`, `stretch`, `other` (groupBy `none`); names with dose response (any spelling) or the word `DRC` are
  `doseResponse` (tested first, as the software). Older recordings are read as before. The watcher leaves all protocols
  out of the regular summary (`'includeProtocols'`, default false), also those of the new types.
* **Grouping** (`mda_groupBeats`): every stimulus of the channel gets a value; a stimulated contraction belongs to the
  group of its stimulus, an extra contraction to the group of the last stimulus before it.

  | `groupBy` | value | default for |
  |---|---|---|
  | `pacingFrequency` | 1 / interval from the previous stimulus (Hz); intervals within 2 % form a cluster, its frequency (1 / median interval) is rounded to `frequencyResolution` (0.1 Hz) at ≥ 1 Hz and to `frequencyResolutionLow` (0.05 Hz) below 1 Hz: clusters with the same rounded frequency are one group (0.99, 1.0, 1.001 Hz = `1 Hz`; 0.74, 0.75 Hz = `0.75 Hz`; before 2026-10-10: label rounded to 0.05 Hz at all rates, `groupValue` unrounded); `groupValue` = the rounded frequency, `stimFrequency` = 1 / median interval. **FFR protocols** (2026-10-10, option `steadyStateBeats`, default 10): each frequency is summarized from its steady state, the last 10 contractions of the longest run of consecutive stimuli at this frequency (other runs, e.g. the basic pacing before and after the protocol, are not used; `groupStep` = number of the run), of its longest sequence of captured stimuli whose previous and next stimuli are captured, too (partial capture, e.g. 2:1: no steady state, note); 0 = all contractions of the frequency (versions ≤ 1.0.0-beta.3) | FFR |
  | `S2interval` | S2 = premature stimulus (interval < 95 % of the previous one, next interval longer or unknown, previous stimulus not premature; the last stimulus of the channel at the basic interval is an S1); groups `S2 <ms>` and `post-S2 <ms>` (the next stimulus; post-extrasystolic potentiation; S2 intervals within 5 ms are one group: the 400-Hz status channel records a pulse on a 2.5-ms grid, so the same interval can appear ±2.5 ms apart, while 10-ms steps of a schedule stay apart), `S1` (other stimuli at the basic interval, median ± 5 %, not followed by an S2), `pre-S2` (S1 followed by an S2: relaxation cut off) and `other` (other intervals, e.g. trains at a higher rate between the S1-S2 steps; analyse them with `pacingFrequency`). **With the programmed sequences of the log file** (`Sequence` entries, 2026-10-23: `StimPeriod` / `StimTimes` per channel of the software of 2022–2023, `Sent stimPeriod` / `Added stimTime(s)` of 2026) the pulses of a sequence with two regular times per period (S1 at t1, S2 at t2) are classified by that sequence: S1 = pulse followed by a pulse t2 − t1 later, S2 = the pulse t2 − t1 after an S1, `groupValue` = the programmed interval (`S2 130 ms` for 127.5 ms on the 2.5-ms grid). The log says what was sent, the status channel what the controller did: a sequence is used only where ≥ 90 % of its recorded pulses fit it as S1 or S2 (otherwise, e.g. after a dropped command, the interval rule applies). This is needed for schedules with an S1-S2 pair in every period (the lab's human standard schedule: S1 at 0, S2 at 960 → 80 ms, period 2 s; the S1 of the next pair is the `post-S2` stimulus): an S2 later than half the period (640 ms of 1200 ms) would otherwise be read as the next S1 with 560 ms, and an S2 at half the period (equal intervals) as no S2. Pulses that fit both roles are placed on the S1 grid of the sequence (the controller keeps the period when it switches sequences) | RP |
  | `stimCurrent` | current of the pulse (mA, status channel); `currentReached_percent` per group (pulses whose current was reached; pulses with an unknown result left out, see *Current reached* below) | ST |
  | `pauseLength` | first stimulus after a pause (interval ≥ 1.5 s, ≥ 1.5 × the median interval and ≥ 1.5 × the interval before; the median interval returns within the next 3 stimuli): `rest <s>`, one group per pause with `groupStep` = number of the pause (pooling over channels whose effective pauses differ); stimuli within 10 s after a pause `after rest` (decaying potentiation, not part of the reference); other stimuli at the median interval (± 5 %) `steady` (reference); all others `other`. Pauses (interval − steady interval) within `pauseTolerance` (10 %) of the shortest pause of a set have the same pause length (`groupValue` = their median interval, equal labels numbered `#n`) | PRP |
  | `pulseDuration` | `chargeDuration` entry of the log file for the stimulated channel (ms) | PD |
  | `rockerSpeed` | rocker speed at the peak (rpm, `rockerSpeed` entries of the log file); all contractions by default | rockerSpeed |
  | `log:<code>` | any numeric entry of the log file for the stimulated channel (or channel 0), e.g. `log:pauseDuration` | – |
* **Summary**: one row per protocol, channel and group with `group`, `groupValue`, `groupRole`, `groupStep`, `groupBy`, `nStimuli`,
  `nContractions`, `capture_percent` (stimuli followed by a contraction, independent of the rocker filter),
  `S2response_pct` and `separatePeak_percent` (S2 groups: median S2 response in % of the S1 amplitude and % of the
  S2 with a separate peak, from the template subtraction of the RP results below; an S2 response too small for the
  detection threshold still shows here), `amplitude_pctOfRef` (mean amplitude in % of the group `S1` / `steady`; post-rest groups: see PRP reference below),
  `amplitude_CV` (coefficient of variation of the amplitudes, population SD / mean), `irregular` (1 if
  `amplitude_CV` > `irregularCV`, 0.15: conduction block, alternans or extra beats) and mean, SD and n of all
  parameters. FFR frequencies summarized from fewer than `minGroupBeats` (5) included contractions are listed in the
  notes (`info.notes`). The
  contraction table gets the columns `group`, `groupValue`, `groupRole`, `groupStep`; the Excel output a sheet
  `protocols`.
* **Protocol results** (`mda_protocolResults`; `info.protocolResults`, sheet `protocolResults`, GUI table "protocol
  results"): one row per protocol and channel. A group counts as *captured* if at most max(1, 10 % of its stimuli)
  are not followed by a contraction and ≥ 2 are (as in GetFFRdata / GetStimThreshold).

  | protocol | columns | definition |
  |---|---|---|
  | FFR | `maxCapturedFrequency_Hz` | highest captured pacing frequency |
  | | `FFR_1Hz_pct`, `FFR_2Hz_pct`, `FFR_3Hz_pct`, `amplitude_0p5Hz_uN` | mean amplitude at 1 / 2 / 3 Hz in % of 0.5 Hz (captured groups; group frequencies rounded to 0.1 Hz, before 2026-10-10 ± 5 %) |
  | ST | `stimThreshold10_mA`, `…50`, `…95`, `…99` | lowest captured current whose mean amplitude is ≥ 10 / 50 / 95 / 99 % of the largest one (thresh10 … thresh99 of GetStimThreshold); `captureThreshold_mA` = lowest captured current, `maxAmplitude_uN` |
  | RP | `refPeriodNoPeak_ms` | S2 interval below which there is no separate contraction peak (< 50 % of the S2 with a peak) |
  | | `refPeriodNoResponse_ms` | S2 interval below which there is no response at all (median S2 response < noise level) |
  | | `refPeriodAllCaptured_ms` | shortest S2 interval above which every S2 interval gives a separate contraction peak at every S2 (from long to short: the S2 interval before the first one with a missing peak; all with a peak: the shortest analysed interval, note; 2026-10-10). Definition as the refractory period of the MyoDish export, but more sensitive to a single S2 without a separate peak: in 323 recordings of human slices `refPeriodNoPeak_ms` agreed better with the export (within 10 %: 95 vs 85 %, bias −1 vs +13 ms) |
  | | `…Step_ms`, `S2noiseLevel_pct`, `amplitudeS1_uN`, `nS2`, `nTemplateBeats` | distance of the two S2 intervals around the transition (uncertainty ≈ ± step/2), noise level, ... |
  | | `S2shortest_ms`, `S2longest_ms` | shortest / longest analysed S2 interval: a transition that is *not reached* (NaN, note) lies below `S2shortest_ms` (e.g. a slice that still gives a separate S2 contraction at the shortest S2 interval of the protocol), one *already at the longest interval* above `S2longest_ms` |
  | all | `variant` | the protocol as recorded, from the pulse pattern (2026-10-23): FFR `0.2-4 Hz (12 steps)`, ST `8-95 mA (30 steps)`, PRP `pauses 3/12/50/120 s`, RP `S1 train + S2 pairs, S2 800-320 ms (16 steps)` or `S1-S2 pairs in every period, …` (fewer than 3 S1 stimuli with the S1 interval before and after). Tells apart schedules with other pauses, steps or structure, e.g. when pooling |
  | PRP | `PRP1_pct` … `PRP6_pct` (+ `_pause_s`) | amplitude in % of the reference after the pauses of the protocol in ascending order (2026-10-23; pauses within `pauseTolerance` are one length, several pauses of one length: their mean); the `_pause_s` column shows the pause, so that recordings with different schedules are not pooled unnoticed |
  | PRP | `PRP15_pct`, `PRP30_pct`, `PRP60_pct` (+ `_pause_s`) | the lab's standard pauses: amplitude in % of the reference after a pause of 15 / 30 / 60 s ± `pauseTolerance` (10 %; several pauses: their mean, note; before 2026-10-10 the nearest pause within ± 50 %) (pause = stimulus interval − steady interval). Reference (option `prpReference`, 2026-10-10): `'preceding'` (default) = median of the last `prpReferenceBeats` (6) contractions of the pacing before each pause (this pacing loads the SR; slow changes of the amplitude during the protocol do not enter the ratio), `'firstTrain'` = mean of the contractions of the pacing before the first pause, `'steady'` = mean of the group `steady` (versions ≤ 1.0.0-beta.3) |

  S2 response (as in GetRefractoryPeriod): the mean S1 contraction (S1 interval before and after, rocker at rest) is
  scaled to the S1 contraction of each S1-S2 pair (S1 … S2 + 20 ms) and subtracted; response = maximum of the
  residual (30-ms mean) S2 + 30 … 600 ms in % of S1; separate peak = local maximum of the force after the S2 (not
  before the peak of the S1 template + 10 ms: at intervals shorter than the time to peak the S1 peak itself is no
  separate peak, 2026-10-23) with a prominence ≥ max(noise level, 2 %); noise level = 99th percentile of the
  response at pseudo-S2 on the S1 beats. **Without steady-state S1 beats** (fewer than 3: an S1-S2 pair in every
  period, e.g. the human standard schedule; 2026-10-23) the template is the mean S1 of the pairs with the longest S2
  interval (rocker at rest), cut 20 ms before their S2 and held at the mean of the 50 ms before the cut, which must be
  ≤ 10 % of the peak (relaxed S1; otherwise no estimates, note); the noise level then uses pseudo-S2 intervals that
  end ≥ 100 ms before the cut; note *template: S1 of the N pairs at … ms*. With a period of 2 s and S2 ≤ 960 ms the
  S1 is preceded by ≥ 1.04 s; with the stem-cell schedule (period 1.2 s, S2 up to 640 ms) the template S1 is itself
  premature, and channels with a noise level ≥ 50 % get no estimates. A
  transition is the first S2 interval (from long to short) below the level that stays below it (at the next shorter
  interval, or in the median of this and all shorter intervals: a single value just above the level among the
  shortest intervals does not undo a transition), interpolated linearly; tested intervals in 0.5-ms steps (the 400-Hz status channel records a pulse on a
  2.5-ms grid; with `Sequence` entries the programmed intervals). Example 8 (rabbit, ERP 460 ms in the lab table): no
  peak 475 ms, no response 461 ms (step 30 ms; programmed intervals 460 / 490 ms).
  The three values do not depend on the contraction detection: an S2 response too small for the detection
  threshold (e.g. 9 % of S1 at 150 ms in a rat slice, threshold 30 % of the typical amplitude) still counts as a
  separate peak, and a response without a peak of its own (a broadened relaxation) still counts as a response.
* **Rocker, stimulated beats**: with `'protocol'` only stimulated contractions (`'beats','stimulated'`) with the
  rocker at rest are included unless `'rocker'` / `'beats'` is given (grouping by rocker speed: all). Sharp-electrode recordings (no rocker) and protocols without rocker stops need
  `'rocker','any'` (GUI: "all contractions"). Schedules do not always stop the rocker: with option `rockerFallback`
  (default on; 2026-10-23, before `ffrRockerFallback` for FFR only, still accepted) a group (FFR frequency, current
  step, pause, S2 interval …) without contractions with the rocker at rest is summarized from its contractions with
  the rocker moving (note *no contraction with the rocker at rest at …: contractions with the rocker moving used*;
  the human standard schedule keeps the rocker running during PRP and ST), and the S2 response of an RP protocol
  without S1-S2 pairs at rest uses all pairs (note). A contraction counts as "rocker moving" if the rocker moved anywhere
  between its diastolic minimum and 90 % relaxation. After a stimulation pause the diastolic minimum is searched only
  in the last 0.5 s before the stimulus (option `pauseDiastoleWindow`), so that rocker movement or drift during the
  rest does not count (PRP: the rocker typically stops ~1.2 s before the post-rest stimulus).
* Examples: `examples/example3_humanVentricle` (FFR), `example8_rabbitVentricle_EP` (RP: no response ≤ 460 ms,
  response at 490 ms), `example2_rabbitVentricle` (PD, ST), `example7_pigVentricle` (PRP), `example1_rabbitVentricle`
  (rocker speed).

## Parameters (per contraction)
Within the cycle between the previous and the next peak (at most 3 s on each side):
F_dia = median of the unfiltered signal 60 … 5 ms before the eliciting pulse (option `diastolicLevel`,
`'preStimulusMedian'`, default since 2026-10-10; window `diastoleWindowStart` … `diastoleWindowEnd`, ends before the
stimulus artifact). Contractions without a pulse (extra, unpaced) and contractions whose median is at or above the peak
use the minimum before the peak, the level of all contractions with `'diastolicLevel','minimum'` (versions ≤
1.0.0-beta.3; a short dip before the pulse, e.g. noise or rocker movement, lowered it and enlarged the amplitude).
F_min,post = minimum after the peak. After a stimulation pause (stimulus interval ≥ 2.5 s and ≥ 1.5 × the interval
before) the minimum before the peak is searched only from 0.5 s before the stimulus (`pauseDiastoleWindow`; `Inf` =
as for all other contractions).
Upstroke levels = F_dia + x % of the amplitude (last crossing before the peak); relaxation levels =
F_min,post + (100 − x) % of (F_peak − F_min,post) (first crossing after the peak). Crossing times are
interpolated linearly between samples; dF/dt = central difference of the filtered signal.

| column | unit | definition |
|---|---|---|
| amplitude | µN | F_peak − F_dia |
| diastolicForce | µN | F_dia − zero force (zero = sensor signal without load: `Offset` of the channel in the log file, or option `zeroForce`) |
| diastolicSignal | µN | F_dia (sensor signal; its changes over time are meaningful even without zero) |
| dFdtMax | µN/s | maximum rate of force rise (+dF/dt max) |
| dFdtMin | µN/s | maximum rate of relaxation (−dF/dt min, negative) |
| riseTime10_90 | s | 10 % → 90 % of the amplitude |
| TTP90 | s | **rise time 90 %**: 10 % of the amplitude → peak (time to peak) |
| TTR50, TTR90 | s | peak → 50 % / 90 % relaxation |
| CD50 | s | 50 % upstroke → 50 % relaxation (full width at half maximum) |
| CD90 | s | 10 % upstroke → 90 % relaxation |
| AUC | µN·s | ∫ (F − F_dia) dt from 10 % upstroke to 90 % relaxation |
| peakToPeakInterval, peakToPeakFrequency | s, Hz | to the previous detected contraction |
| stimInterval, stimFrequency | s, Hz | set stimulation: stimulus of this contraction − previous stimulus pulse of the channel (extra contractions: last two stimuli before the peak) |

Further columns: `t_peak` (s in the file), `clockTime`, `beatType` (`stimulated` = elicited by a pulse of the
channel, see "Stimulus assignment"; `extra` = no eliciting pulse; `unpaced` = no stimuli in this channel), `t_stim`
(eliciting pulse), `stimToPeak`, `rockerMoving` (rocker moved at any time between F_dia and 90 % relaxation),
`included`, `uncertain`, `t_onset` (onset of the contraction), `stimToOnset`, `t_rise50`, `stimToRise50` (time at which
the upstroke crosses 50 % of the amplitude and its delay to the pulse; less dependent on the shape of the foot of the
upstroke than the onset), `invertedSignal` (see "Inverted signal"), `stimPulse` (pulse ID = raw sample
number of the eliciting pulse in the file, from 0; the key of the pulse table), `stimCurrent` (mA),
`stimChargeDuration`, `stimPauseDuration`, `stimDechargeDuration` (µs, from the log file), `elicitedByExtraPulse`,
`stimAmbiguous`, `prePulses`, `postPulses`, `prominence` (detection criterion); with `'rockerFilter',true` also
`rockerCorrected` (rocker moved and the artifact was subtracted).

## Signal processing and detection
* Data: 400 Hz, 2 samples averaged (200 Hz), moving median 50 ms + moving mean 25 ms (same processing
  as the lab's `GetContractionParameters`). The half-sample delay of the even filter windows is corrected.
* **Spike artifacts** (option `'spikeRemoval'`, default on; `mda_removeSpikes`, 2026-10-10): when a chamber is taken
  out or put in, and with electrical interference, the force value can jump within 1–2 raw samples and come back
  within a few ms (or go on to a new level), often in several channels at once. A spike is a group of jumps
  (|difference between two raw samples| ≥ J; jumps < 40 ms apart form one group) that lasts ≤ 100 ms, goes beyond the
  level before *and* after it (median of 20 ms) by ≥ J, and whose largest jump is ≥ 50 % of its largest deviation
  from the level before (a contraction rises over many samples: at most ~30 % of its amplitude per sample).
  J = max(50 AU, 8 × median of the non-zero |differences| of the channel), within ± 10 ms of a spike of another
  channel max(50 AU, J/2). Level changes (steps when a chamber is put in or taken out) are no spikes and stay. The
  spike samples are replaced by a line from the sample before to the sample after (raw samples, before the
  averaging); the notes of the analysis list the number per channel (`info.notes`, `info.spikes`), `S.spikes` of
  `mda_readMdd` the single spikes. `mda_signalGaps` measures the spikes at the periods without signal on the raw
  data. Checked on 42 recordings of 2020–2026 (no contraction changed in the most suspicious detections) and with
  spikes added to real recordings.
* Contractions = local maxima with a prominence ≥ threshold, ≥ 0.15 s apart. Automatic threshold:
  0.3 × typical amplitude (≥ 30 µN); typical amplitude = median of the n largest prominences
  (n = number of stimuli) or, without stimuli, of the prominences above the largest gap between the sorted
  prominences. Peaks of the rocker movement (paced channels, auto threshold; option `'rockerArtifacts'`, default
  on): (a) small peaks between the contractions (≤ 0.5 × typical, not locked to the stimuli) that form a cluster
  separated from the contractions by a clear gap (prominence ratio ≥ 1.6, ≥ 3 such peaks) raise the threshold into
  the gap; (b) with the rocker moving, the rocker / noise level N is taken from the rise of the signal in the 0.5 s
  before the stimuli (90th percentile). If the largest peaks are not locked to the stimuli and their typical
  amplitude is ≤ 50 µN, or ≤ 2 × N at the rhythm of the rocker, the peaks at that level are removed – *no
  contractions* if nothing is left (slice not beating); peaks locked to the stimuli well above N stay (slices that
  answer only some stimuli); (c) otherwise peaks not locked to the stimuli below min(1.5 × N, 0.5 × typical) are
  removed. Small peaks locked to a stimulus (alternans, partial capture) stay. The GUI status line shows the number
  of removed peaks. The threshold is computed per channel from the analysed window; check it in the GUI or with
  `'showFigures',true`, and set it manually if necessary (`'threshold',µN`; a manual threshold switches the rocker
  rules off).
* Small stimulus-locked contractions (option `'lockedThreshold'`, default 0 = off; 2026-10-21): with a value such as
  0.05, a peak below the automatic threshold is also a contraction if it is locked to a stimulus (latency within the
  lock window of the typical latency of the largest peaks), the rocker is at rest and its prominence is ≥ that
  fraction of the typical amplitude and ≥ `'lockedNoiseRel'` (3) × the median rise before the stimuli. Meant for
  responses the 30 % threshold cuts off: the small response to a premature S2 near the refractory period (9 % of S1
  in a rat slice), 2:1 alternans at high rates (human atrium, example 4: 96 small beats of 8–28 % of the typical
  amplitude). It changes the group statistics of such ranges, so it is off by default; the GUI has it under Advanced
  settings. `C.lockedLowPeaks` = number of peaks kept this way.
* Uncertain contractions (auto threshold; option `'detection'`): near the noise level, more real contractions mean
  more false positives and vice versa. A contraction is *certain* if it is locked to the stimuli (latency within
  ±min(0.1 s, 0.2 × stimulus interval) of the typical latency) and ≥ 2 × the median rise of the signal in the 0.5 s
  before the stimuli, or if it is large (≥ 0.7 × typical amplitude and ≥ 3 × that rise); unpaced channels: ≥ 0.5 ×
  typical amplitude. `'detection','sensitive'` (default, *high sensitivity*) counts the other contractions too and
  flags them (column `uncertain`; summary counts `nUncertain`, `nStimulatedUncertain`, `nExtraBeatsUncertain`,
  `nMissedBeatsUncertain`), so one run gives both results: *high specificity* = without the uncertain ones.
  `'detection','specific'` (*high specificity*) does not count them. The typical amplitude and the noise level are
  taken from the analysed window: in long windows with very different phases (e.g. a whole force-frequency protocol)
  small but regular contractions of the weak phase can be flagged; look at the orange markers in the GUI.

## Advanced settings and settings files (2026-10-10)

All constants of the method that are based on assumptions or experience are options (114 in total, 78 of them
constants in the code before 2026-10-10; defaults = the values used before, so the results do not change, except for
the new tolerances of the protocol grouping, see "Stimulation protocols"): stimulus
assignment, detection and certainty, noise level and artifact gap rule, rocker rules, spike removal, rocker filter,
tolerances of the protocol grouping, pulse text. List with defaults and meaning: `help mda_options` (section ADVANCED
SETTINGS) or the help of `options.py`; with figures: [`docs/MyoDishAnalysis_settings_guide.pdf`](docs/MyoDishAnalysis_settings_guide.pdf)
(GUI: **Advanced ...** → **Guide**). Purely numerical details (e.g. number of phase bins of the rocker cycle) and the
criteria of the protocol results (captured group, ST threshold levels, S2 response) are fixed.

Every analysis stores all options in its info table (rows `option_<name>`). A **settings file** is the same key /
value table as `.csv` (`createdBy` = MyoDishAnalysisSettings):

```matlab
mda_settings('save', 'mySettings.csv', mda_options('gateMax', 0.2, 'rockerFilter', true));
o = mda_settings('load', 'mySettings.csv');          % or a results file (.xlsx, _info.csv): its options
MyoDishAnalysis(file, 1:8, 0, 600, 'settings', 'mySettings.csv', 'threshold', 300);   % later names override it
MyoDishAnalysisWatch(raw, results, 'settings', 'mySettings.csv');   % index: the values (a changed file -> outdated)
```

Python: `settings.save_settings(file, opts)`, `settings.load_settings(file)`, `options(settings=file)`,
`mda-analyze ... --settings file`, `mda-watch ... --settings file`. Options unknown in the version that reads the
file are ignored (note); options missing in it have their default.

## Stimulus assignment (onset gate) and extra pulses (option `'stimAssignment'`, default `'onset'`; 2026-10-10)
Which pulse elicited a contraction? Every stimulus pulse of the channel is a candidate: the **regular pulses** and
the **extra pulses** (status channel bit 16, e.g. pre-pulses before the regular pulse or CCM pulses after it; log
channel 10k + c = extra pulse #k of channel c).
* **Onset** of a contraction = the tangent at the maximum dF/dt between the diastolic minimum and the peak crosses the
  diastolic level. The delay from the eliciting pulse to the onset is short (median per channel 6–75 ms in the
  example recordings, up to ~80 ms near threshold), much shorter and more stable than the delay to the peak.
* **Gate**: a pulse can only have elicited a contraction if it lies from onset − `gateMax` (0.15 s) to onset +
  `gateTolerance` (0.015 s, tolerance of the onset estimate). Contractions are assigned in the order of their
  prominence; every pulse elicits at most one contraction.
* **Longer gate of certain contractions** (`'gateMaxCertain'` 0.5 s, `'gateMaxCertainRel'` 0.5; 1.0.0-beta.5): a
  certain contraction (auto threshold, paced channel) still without a pulse after the first pass may be elicited by a
  regular pulse up to min(0.5 s, 0.5 × the interval of the regular pulses before the onset) before the onset (at
  least `gateMax`), e.g. a slice with a long electromechanical delay. This second pass never takes a pulse from a
  contraction within `gateMax` of it; uncertain contractions (e.g. rocker artifacts) keep `gateMax`. The diastolic
  level of such a contraction is the median 60 … 5 ms before its onset (instead of before the pulse).
  `'gateMaxCertain',0.15` gives the assignment of 1.0.0-beta.4.
* Several candidates: pulses before the onset before pulses after it; regular pulses before extra pulses (an extra
  pulse after the regular pulse falls into its refractory period, e.g. CCM; a sub-threshold pre-pulse lies further
  before the onset than the regular pulse); of one kind the earliest up to `gateCore` (0.06 s) before the onset,
  otherwise the latest one. An eliciting pre-pulse is found because the regular pulse then lies after the onset.
* No pulse in the gate: the upstroke can rise in phases (rocker movement, a spontaneous event fused with the
  contraction just before the stimulus). The onsets of the other rise phases (local maxima of dF/dt ≥ 25 % of the
  maximum) are tried, the earliest first; then a pulse up to 5 ms before the maximum dF/dt. Still none: `extra`.
* **stimAmbiguous** = true: a pulse of the other kind (regular / extra) within `ambiguityWindow` (0.01 s) of the
  chosen one, or one that would be chosen with the onset `gateTolerance` earlier or later, a later rise phase (the
  upstroke started more than `gateTolerance` before it) or the pulse after the gate. Ambiguities are accepted and counted
  (`nAmbiguous`), not hidden.
* **Missed beats** = regular pulses that elicited no contraction; `nMissedDuringContraction` = those that fell into a
  contraction elicited by another pulse (from its eliciting pulse to 90 % relaxation; refractory), the others were
  diastolic. Extra pulses never count as stimuli of the pacing (counts, intervals, protocols, groups).
* **prePulses / postPulses**: pulses without own contraction, written to the contraction they belong to: during the
  contraction (eliciting pulse … 90 % relaxation) as post-pulses, before it (at most `prePulseWindow`, 1 s, before
  the eliciting pulse) as pre-pulses. Format `t<ms>|<mA>|<charge µs>|<pause µs>|<decharge µs>`, several joined by
  `&` (sorted by time; at most 10, then `&+<number of the others>`); t relative to the eliciting pulse (extra beat:
  the onset), the programmed offset of the log file (`Sequence` entries) if the measured one is within 5 ms of it.
  The leading `t` keeps spreadsheet programs from reading a cell such as `-150|15|...` as a formula; `&` instead of
  `;` because `;` is the column separator of German CSV files. Example: `t-150|15|3000|1000|3000`.
  Durations: the last `chargeDuration` / `pauseDuration` / `dechargeDuration` entry of the log file before the pulse
  (extra pulse #k: log channel 10k + c if present, otherwise the values of the channel; software 2026).
  Time resolution of the pulses: 2.5 ms (400 Hz).
* **Pulse table** (`info.pulses`, sheet / file `pulses`; `'pulseTable',false` = none; xlsx with ≥ 1,048,576 rows:
  `<name>_pulses.csv`; watcher: like the contractions, `_pulses.csv(.gz)`): one row per pulse of the analysed
  channels and ranges: `pulse` (ID = raw sample number), `channel`, `t`, `extra`, `current_mA`, `currentReached`
  (1 / 0 / NaN = unknown),
  durations, `outcome` (`elicited` / `duringContraction` / `noResponse`), `role` (`eliciting` / `pre` / `post`),
  `contraction` (number in the contraction table), `t_peak`, `tRel_ms`, `couplingInterval_s` (to the previous
  eliciting pulse), `sinceOnset_s` (to the onset of the latest contraction) and `phase` (sinceOnset / onset … 90 %
  relaxation). Threshold, refractory period and pre-pulse effects can be evaluated from it as special cases.
* **Current reached** (2026-10-20): the controller writes the report of a pulse into the status channel when the
  pulse starts; whether its current was reached is known only at its end. Status bit 9 ("current not reached") of a
  pulse is therefore the result of the **previous base pulse of the same channel** (firmware V18G–V19C; confirmed
  from the firmware source and 3,285 of 3,285 pulse pairs in recordings of test controllers; a failure of an extra
  pulse of that channel in between counts as well). `mda_readMdd` / `read_mdd` assign it accordingly:
  `stim.currentReached` = 1 (reached), 0 (not reached) or NaN (unknown: the last base pulse of a channel when no
  later pulse of that channel follows within 600 s or the file ends; a base pulse followed by an extra pulse of its
  channel when the next base pulse has bit 9, because the failure may be the extra pulse's; extra pulses and external
  trigger pulses, which have no result of their own). The bit 9 of the first pulse of a file belongs to the time before the file and is not
  used. Before 2026-10-20 every pulse got its own bit 9, i.e. the result of the pulse before it. In single channel
  mode the firmware reports failures of channel 1 only in some configurations, so `currentReached` = 1 is not
  certain there.
* **Sensor rate** (2026-10-21): the new sensor boards (MMC5983) measure at 200 Hz, and the controller (firmware V19C)
  sends their value in every 2.5-ms row of a 400-Hz recording, so each value appears twice; the old boards (FXOS8700)
  deliver a new value in every row. The log does not say which board a channel has. `mda_readMdd` / `read_mdd`
  therefore infer it from the raw data of the window read: `repeatedSamples_percent` = share of samples equal to the
  sample before (runs of more than 4 identical values, i.e. chamber out, sensor gone or saturation, left out; about
  50 % for new boards, 1–8 % for old boards in lab recordings of 2026-10), `sensorRate` = sampling rate (< 20 %), half
  the sampling rate (> 35 %) or NaN (in between, or less than 1 s of samples). Both are columns of the summary
  (`sensorRate_inferred`, `repeatedSamples_percent`). On a channel at 200 Hz the timing parameters (stimToOnset,
  TTP, TTR50/90, CD50 …) have a resolution of 5 ms; compare such values only between channels and windows of the
  same rate. Where the rate is unambiguously half the sampling rate, the repeated values are replaced by a linear
  interpolation between the first samples of each pair (the measurement times) before the averaging of the raw
  samples (option `'halfRateInterpolation'`, default on; `S.halfRateInterpolated`), so that the timing does not
  depend on the phase of the pairs (before: a sample could be up to 2.5 ms older than its row); runs of more than 4
  identical values (held values, chamber out) stay. Later software versions log the rate of every port; MDA will then
  read it from the log.
* `'stimAssignment','peak'`: as in versions ≤ 1.0.0-beta.3 (peak `minStimToPeak` … min(stimulus interval, 1 s) after
  a pulse, the most prominent peak after it; extra pulses count as regular pulses). Results files of these versions
  are opened with `'peak'` (`mda_readResults`).
* Validation (2026-10-10): 9 example recordings (50 channels, 33,633 contractions; rabbit, human ventricle and atrium,
  pig, rat): `beatType` identical to `'peak'` in 41 channels. Differences: the peak gate counted spontaneous beats
  0.2–0.45 s after a pulse as stimulated where the delay to the onset is 6–16 ms (rat, 2 Hz, faster spontaneous
  rhythm; 193 contractions), assigned the pulse to the second peak of a double contraction (rabbit) or to a later
  peak 1.5 s after the pulse (human, slow contractions; 23), counted artifact steps of a chamber with saturated signal
  (rabbit, 74), and single contractions in 4 further channels. 8 recordings of 2022–2026 (prepulse threshold
  protocols, CCM, rat, pig, human): see `CHANGELOG.md`.

## Inverted signal (option `'invertedCheck'`, default on; 1.0.0-beta.5)
In a paced channel whose force **falls** after the stimuli (e.g. the magnet of the MyoDish out of position), the force
measurement is not valid. Test: the stimulus-triggered median of the filtered signal (`'invertedSkip'` 0.02 s …
min(1 s, median stimulus interval) after the pulses, baseline 60 … 5 ms before each pulse, at most 300 pulses) falls at
least `'invertedRatio'` (2) times as much as it rises, by at least `'invertedMinAmplitude'` (50 µN), and stays below
half the fall for at least `'invertedMinWidth'` (0.05 s); and the signal itself deflects downwards (50th − 10th
percentile ≥ 2 × (90th − 50th percentile)). The median and the percentiles keep steps (chamber taken out),
contractions that are not locked to the pulses and upright contractions just before the pulses from being taken for an
inverted signal (in a sample of 121 recordings, a first version of the test with the mean flagged 38 channels, mostly
for such reasons; the final test flags the channel whose magnet was out of position and one 30-min period without
contractions; the analysis report flags a channel only with ≥ 50 contractions in inverted ranges). This is the
suspicion. The inversion must be **confirmed by the detection** (2026-10-12): the normal detection in the negated signal finds certain stimulated
contractions for at least `'invertedMinCapture'` (20 %) of the pulses; otherwise (e.g. waves of the rocker partly in
phase with the pulses, no contractions) the section is analysed as it is. The detection alone cannot tell the
direction: in a clean signal both directions give regular, locked "contractions" (the plateau between the deflections);
the suspicion decides the direction, the detection confirms it. Check on all 1581 ranges (301 channels) that the
test alone flagged in the recordings of 2023, 2024 and 2026: 1069 ranges stay inverted; channels with ≥ 50
contractions in inverted ranges 103 → 90; all 10 channels checked visually as rocker waves or upright contractions
lose the flag, 14 of 15 channels checked visually as inverted keep it (the one lost has 60 µN deflections and < 20 %
certain capture in the suspected section). The second detection runs only for suspected sections. Then
the contractions are detected in the negated signal:
rate and capture (beat types, missed beats, `peakToPeakFrequency`, `stimFrequency`) are analysed, all force and time
parameters are NaN, and the column `invertedSignal` (contractions and summary) is true. Use: whether the slice beats
and follows the pacing, e.g. while it is kept in culture for a later analysis.

## Arrhythmic pacing (options `'arrhythmicChannels'`, `'arrhythmicDetection'`; 2026-10-13)
Some slices are paced continuously at a high or irregular rate, e.g. right atrium at up to 5–6 Hz with a
stimulus-to-stimulus SD of 30 %. Many pulses then elicit no contraction (often they fall into the previous one) and the
amplitude varies with the preceding interval; this is expected and no fault of the analysis. Such channels are marked
in the summary column `arrhythmicPacing`:
* `'arrhythmicChannels'` (e.g. `[3 5]`; GUI *Advanced ...* → *Protocols*): channels paced arrhythmically;
* `'arrhythmicDetection'` (default on): in addition, a channel is detected as arrhythmically paced if the coefficient
  of variation (population SD / mean) of its stimulus intervals exceeds `'arrhythmicMinVariability'` (10 %) in windows
  that make up more than `'arrhythmicMinFraction'` (50 %) of the paced time of the analysed ranges. Windows:
  `'arrhythmicWindow'` (60 s) from the start of each range, with ≥ 6 regular pulses (extra pulses do not count) and no
  overlap with a stimulation protocol of the log file, so FFR, PRP or threshold protocols do not make a channel
  arrhythmic (in analyses of the protocols, `'protocol'`, only `'arrhythmicChannels'` applies). Check on the human
  right-atrium recordings of 2022–2026: 712 of 714 channels paced at 5 Hz with an interval CV of 35–60 % detected (the
  2 others: misread status channel); no channel in 396 recordings of other tissues (details: `CHANGELOG.md`).

Summary columns: `stimVariability_percent` (median CV of the windows), `arrhythmicFraction` (variable fraction of the
paced time), `pacedSeconds` (time of the windows that count), `arrhythmicPacing`. The capture is analysed as usual;
the analysis report shows it with `~` and does not flag the capture (C) and the amplitude CV (V) of these channels, and
their missed beats do not count in the noise index (N: uncertain contractions with extra beats only). The text report
of the watcher writes `arrhythmic pacing` instead of `capture < 90 %`.

## Analysis report (`mda_report`; Python `report.py`; 1.0.0-beta.5)
A short PDF that says which analyses should be checked, written by the watcher per experiment after every pass with
analysed recordings (all recordings of the experiment, the new ones in bold; 2026-10-15), by `MyoDishAnalysis`
with `'output'` and by the GUI on request. Flags per channel (channels with a slice and ≥ 50 detected contractions;
thresholds: watcher options `'flag...'`, `mda_report('defaults')`):
* **check the analysis** (red: the analysis may not work, or technical faults put wrong values into the data):
  **I** inverted signal (the sensor does not work properly; only beating, capture and rate are analysed); **N** noise
  suspected: uncertain contractions ≥ 25 % **and** extra + missed beats ≥ 15 % (contractions near the detection
  threshold that do not follow the pacing are mostly noise or artifacts, e.g. rocker waves; uncertain contractions
  with regular capture are real contractions near the threshold and are not flagged; unpaced channel: uncertain ≥
  25 %); **S** large extra beats (certain extra beats ≥ 5 % with > 3 × the amplitude of the paced ones: spikes,
  saturation); **D** median delay pulse → onset > 150 ms; **F** stimulus frequency > 10 Hz in a range (1 / median
  stimulus interval; 2026-10-13): pulse pairs or groups (e.g. CCM pulses without the extra-pulse bit), bursts, pulses
  over consecutive samples or a misread status channel; the contractions are analysed as usual; **R** controller
  restart suspected (2026-10-21; the warning `Controller restart suspected: no data for … s, …` of the control
  software 2.2 in the log, read from the events table: after it the controller may have run with its power-on
  settings instead of those in the log; all channels of the recording). Noise index =
  uncertain % × (extra % + missed %) / 100; it is listed (e.g. `noise index 54 (uncertain 98 %, extra 0 %, missed
  55 %)`) and orders the trace pages. Arrhythmically paced channels (see "Arrhythmic pacing"): missed beats not counted,
  no C and V flags, capture shown with `~`.
* **slice quality** (yellow: possibly poor biological quality, also e.g. an effect of a treatment; the user
  decides): **C** capture < 90 %, **X** extra beats > 10 % (spontaneous activity; not shown with N), **A** amplitude
  < 75 µN, **T** amplitude change > 30 % (first → last range with ≥ 10 contractions; listed with the time span, e.g.
  "amplitude change +660 % over 24 h"), **V** amplitude CV > 30 %.
* Rules (2026-10-12) from the overnight runs of 2024 and 2026 (4923 recordings) and visual checks: with the former
  rules (U > 10 % or X > 10 % red) 14–19 % of the channels with a slice were red, half of them only for uncertain
  contractions. In a sample of 400 recordings of 2026 (2143 channels), 228 channels (11 %) have N (former rules: 367,
  17 %); in 12 of 12 inspected channels the N decision agreed with the traces (rocker waves detected as contractions
  vs. real small contractions near the threshold with regular capture).

Page 1: recordings × channels (capture % and the codes; grey: < 50 contractions; red letter P: a stimulation protocol
was not analysed, E: analysis error; legend below the table); page 2: the channels to check and those with
slice-quality flags, with the channel label in parentheses if given (treatment with concentration, otherwise
sliceGroup or sampleGroup, e.g. `ch 7 (PMA 100 nM): extra beats 30 %`); then one page per recording with red
flags (at most 8, the most flags and the highest noise index first) with traces of up to 4 channels (20 s at the most
uncertain / extra beats or large extra beats, markers of the analysis) and the commands that open exactly this place in the GUI:
`MyoDishAnalysisGUI(file, 'channel', c, 'window', [from to])` / `mda-gui file --channel c --window from to`.
`R = mda_report('flags', S, C)` returns the flags of an analysis as a table.

## External trigger (external stimulator; option `'externalTrigger'`, GUI *Advanced ...* → *Stimuli*)
With the external controller unit (one chamber) the slice can be paced by an external stimulator whose TTL pulses
are fed into the MyoDish: the status channel then has bit 14 (external trigger) set without channel and current bits
(e.g. a sharp-electrode setup with its own stimulator: 1 Hz, 4 Hz and S1-S2 intervals). These pulses are read as
`stim.channel = 0` (before 2026-10-08 they were read as channel 8, so the contractions of the slice in channel 1 were
all `unpaced`); a pulse of 2 samples (at USB reconnects) is one pulse. `'externalTrigger'`: `'auto'` (default) = the
external trigger pulses are the stimuli of the analysed channel if the window has no MyoDish stimulus pulses;
`'on'` = always (any data channel; MyoDish pulses ignored); `'off'` = never. GUI: **Advanced ...** → *Stimuli*
(*auto* / *MyoDish pulses* / *external trigger pulses*); the stimulus plot then shows the trigger pulses ("ext") and
their intervals, and the EP alignment also tries the trigger pulses (`mddChannel` 0). Since the external controller
unit carries one chamber, any channel with a signal belongs to it: analyse the channel with the slice.
Test recording (rabbit LV, 2.6 h, 8,691 trigger pulses): with the trigger pulses 30 / 30 contractions stimulated
at 0.5 Hz (stimulus → peak 99 ms) and 196 / 196 at 4 Hz (91 ms); before, all `unpaced`.

## Rocker artifact (`'rockerFilter',true`, GUI checkbox; `mda_rockerFilter`)
While the rocker moves, the dish tilts periodically and each sensor shows an additive periodic signal at the rocker
frequency (60 rpm setting = 1.212–1.215 Hz, i.e. 0.0202 Hz per rpm; 75 rpm = 1.516 Hz). Its shape and size differ
between channels (tens to several hundred µN, larger at higher speed) and are stable over time. It biases the
parameters (the peak and the diastolic minimum pick up the artifact) and adds beat-to-beat scatter; if it is larger
than the contraction, rocker cycles are detected as extra contractions.
* **Method**: the artifact is fitted per channel and rocker period in blocks of 30 s as 6 harmonics of the rocker
  frequency to the signal **between the contractions** (contractions masked by stimulus and detection; baseline
  fitted separately for each stretch between two contractions) and subtracted. Rocker frequency: rocker speed in the
  log file × 0.0202 Hz/rpm, refined with all channels. Blocks are used only if the stretches between the
  contractions cover the whole rocker cycle and the fit is consistent with the other blocks of the channel; uncertain
  blocks take the artifact of the nearest good block of the same rocker period. Rocker stops are not needed.
* **Validation** (2026-10-05): (1) synthetic periodic artifact (60 and 200 µN peak-to-peak, random shape) added to
  cleaned human ventricle recordings (4 channels, 0.2–0.75 Hz): median absolute amplitude error 14–172 µN without →
  0.2–25 µN with the filter (mostly ≤ 7 µN), TTR90 0.01–0.58 s → 0–0.2 s (mostly ≤ 0.01 s); at ≥ 1 Hz (human) no
  correction (too little time between the contractions). `mda_test`: 30 % artifact → amplitude ±0.06 %,
  TTP90/TTR90 ±0.2 ms. (2) Rocker-moving vs. rocker-stopped contractions: rabbit (rocker speed test 30–90 rpm,
  0.2 and 1 Hz), human (FFR protocol with rocker stops, 0.2–0.5 Hz) and pig (75 rpm, 0.2–0.5 Hz): after the
  correction the parameters approach those during the rocker stops and their beat-to-beat SD falls by up to ~80 %,
  e.g. rabbit 90 rpm TTP90 0.251 ± 0.082 → 0.162 ± 0.022 s (stopped 0.159 s); pig channels with an artifact larger
  than the contraction: 272–286 false extra beats → 3–7 per 260 s.
* **Not possible** (message, nothing subtracted): rocker does not move; rocker frequency not found; no periodic
  artifact detectable (small artifact relative to the noise); **too little time between the contractions**
  (e.g. human tissue paced ≥ 1 Hz: contraction ≈ cycle length). Partial correction is reported in %.
* **Limits**: only the additive periodic part is removed. An effect of the rocker movement on the contraction itself
  (e.g. medium flow, oxygen) is not removed — compare with rocker-stop periods (`'rocker','stopped'`) when it matters.
  Report whether the filter was used.

## Reference beat (GUI: right click in the force plot; option `'referenceBeat'`; `mda_referenceBeat`)
**Set mean beat shape of the selected contractions as reference**: mean ± SD of the selected contractions
(developed force, F − F_dia) becomes the reference of the channel. Every contraction is then compared with it (only
after the peak of the previous and up to the upstroke of the next contraction).
* **Alignment** (reference window, *aligned at*; both variants are stored in the reference):
  * *stimulus* (default): t = 0 at the stimulus. A changed stimulus-to-contraction latency counts as a deviation
    (e.g. delayed responses). The reference is built from the stimulated contractions of the selection;
    contractions without a stimulus (unpaced, extra) are aligned at their 50 % upstroke, placed at the 50 % upstroke
    of the reference.
  * *50 % upstroke*: shape only, independent of the latency (used automatically when the selection contains fewer
    than 3 stimulated contractions, e.g. unpaced recordings).
* **Parameters** (z = (F − mean) / SD of the reference at each time point; SD at least the median SD of the reference
  and 2 % of its amplitude):
  * `refCorrelation`: Pearson correlation with the mean reference shape (1 = same shape; independent of amplitude
    and baseline, therefore no normalized variant),
  * `refRMSDeviation_SD`: root mean square of z over the compared window (overall deviation),
  * `refMaxDeviation_SD`: maximum |z| (30-ms mean): local deviations such as shoulders, partial responses after a
    premature stimulus, delayed responses,
  * `refRMSDeviationNorm_SD`, `refMaxDeviationNorm_SD`: the same with contraction and reference normalized to
    amplitude 1 (shape only: shoulders, slowed relaxation; a partial response with normal shape is not detected).
* **Parameters relative to the reference** (2026-10-06): the reference also stores mean, SD and n of every parameter
  over its contractions. Every contraction gets `<parameter>_pctRef` = 100 × value / reference mean (% of the
  reference; e.g. `amplitude_pctRef`, `CD90_pctRef`, `AUC_pctRef`), for `diastolicForce` and `diastolicSignal`
  `<parameter>_dRef` = value − reference mean (µN; their zero point is arbitrary or close to the values). GUI: column
  *%ref* in the table (Δ = difference for the diastolic values), lower plot and trend (entries `..._pctRef`, dotted
  line = reference), *Copy summary*. Summary exports: `<parameter>_pctRef_mean` / `_SD`. The columns are added whenever
  a reference is set (NaN for channels without one). References saved before 2026-10-06 have no parameter values
  (columns NaN) – create them again.
Without reference these columns are NaN. **Show reference beat ...**: mean ± 1 SD and ± x SD (absolute and
normalized), the deviating contractions of the loaded range (magenta), threshold x for the maximum deviation (default
3 SD), measure (absolute / normalized / either) and alignment, option *exclude from the selection*; deviating
contractions are circled magenta in the force plot and counted in the table. **Save / Load reference** (.mat) applies a
reference to other files or time points (e.g. baseline of the same slice). Command line:
`R = mda_referenceBeat('create', C, B, rows)` (optionally `..., 'upstroke')`; switch later with
`R = mda_referenceBeat('align', R, 'upstroke')`), then `MyoDishAnalysis(..., 'referenceBeat', R)` (a reference
applies to the channel in `R.channel`; several references as struct array). The parameters are also available in the
lower plot, the trend and all exports.
* **Validation** (mda_test, synthetic, 1 Hz, noise 10 µN, amplitude ± 3 %; maximum deviation absolute / normalized):
  normal contractions ≤ 1.0 SD (normalized), shoulder 11.7 / 11.9 SD, partial response (half amplitude, same shape)
  22.3 / 1.3 SD (r = 0.9997), slowed relaxation 15.9 / 16.5 SD, 40 ms longer latency 10.4 / 10.5 SD
  (stimulus-aligned) vs 0.6 SD (aligned at the 50 % upstroke); normalized RMS deviation of normal contractions
  ≤ 0.49 SD, of the deviating ones ≥ 3.7 SD.
* **The shape depends on the stimulation rate.** Human ventricle (`examples/example3_humanVentricle`, force-frequency protocol, channel 6; reference from
  0.5 Hz contractions; median normalized maximum deviation, stimulus- / upstroke-aligned): 0.5 Hz 1.2 / 1.0 SD,
  0.2 Hz 2.2 / 1.2, 0.75 Hz 3.7 / 2.2, 1 Hz 7.7 / 4.4, 1.5 Hz 14 / 9 SD (faster contraction and relaxation at
  higher rates; stimulus to peak 216 ms at 0.5 Hz, 196 ms at 1 Hz). Build the reference at the rate of the
  contractions that are tested. The absolute measure also reacts to the normal scatter and drift of the amplitude.

## Notes and limitations
* **Diastolic force**: `diastolicSignal` is the sensor signal at the diastolic minimum; its zero point is the sensor
  offset, so only its changes over time are interpretable. `diastolicForce` subtracts the zero force of the channel:
  by default the `Offset` entry that the MyoDish software writes into the log file at the start of a recording
  (sensor signal without load); `'zeroForce',[z1 z2 ...]` (or the GUI field "Zero force") overrides it. An offset
  of 0 in the log means "not calibrated" → `diastolicForce` = NaN. Zero values are converted like the data
  (calibration, extended sensor mode).
* **dF/dt depends on the filtering.** Example (human ventricle, 3 chambers; fast SE recording):
  dFdtMax at 400 Hz with 20/10 ms filters is 13–19 % (human) and 16 % (fast) higher than with the default;
  without filtering 37–67 % higher (noise). Times (TTP90, TTR90, CD50) change by ≤ 3 ms. Amplitude: −1 %
  (human), −7 % for very fast contractions (CD50 ≈ 70 ms). Report the filter settings, and do not
  compare dF/dt values obtained with different filters.
* Very fast contractions (CD50 < 100 ms, high rates): consider `'downsampling',1,'medianFilterMs',20,'meanFilterMs',10`.
* Rocker movement causes a periodic artifact (see "Rocker artifact"): remove it with `'rockerFilter',true`, or use
  `'rocker','stopped'` (GUI: "only contractions with rocker at rest") for analyses during rocker stops.
* "Rise time 90 %" = `TTP90` (10 % of the amplitude → peak). `riseTime10_90` (10 % → 90 %) is reported in addition.
* **Longer gate**: a stimulus-locked technical artifact 0.15–0.5 s after the pulses (e.g. a periodic disturbance at
  the pacing rate) counts as a stimulated contraction if it is detected as a certain contraction; with only a pulse and
  a following contraction, a spontaneous beat cannot be told from an elicited one. Check channels with a long delay
  (report flag D, `stimToOnset`, `stimToRise50`) in the GUI.
* **Clock time of old recordings**: MyoDish software 2.0.7717–2.0.7769 (Feb–Apr 2021 builds; on one setup until 2024)
  wrote the clock time of the log file with a 12-hour clock without AM/PM. `mda_clockTime` / `clock_time` correct it
  (AM/PM from the dataLogTime, from `parallel recording` entries or from the time of the .mdd file); if a recording
  lies entirely before or after noon and nothing else decides, the times stay as written and the file notes say
  "AM/PM of the recording unknown". Keep the file times of the .mdd files when copying (e.g. `rsync -t`).

## Files
| file | purpose |
|---|---|
| `MyoDishAnalysis.m` | command-line analysis (from–to, several channels/ranges, export) |
| `MyoDishAnalysisGUI.m` | interactive analysis |
| `MyoDishAnalysisWatch.m` | automatic analysis of new recordings of a folder (index, results, report) |
| `mda_readMdd.m` | file reader (data, stimuli, rocker state, log file, overview) |
| `mda_logEntries.m` | entries of the log file (comments, events, settings) |
| `mda_clockTime.m` | clock time of the log entries (12-hour time stamps of software 2.0.7717–2.0.7769 corrected) |
| `mda_signalGaps.m` | periods without signal (chamber taken out, sensor board group / controller failures, empty channels) |
| `mda_removeSpikes.m` | spike artifacts of the force channels (chamber taken out / put in, interference; option `spikeRemoval`) |
| `mda_sliceRegister.m` | slice register from the watcher results (one row per slice: start, end, end status, last amplitude, days) |
| `mda_calibrationFactor.m`, `mda_zeroForce.m` | AU → µN (calibration, extended sensor mode); zero force of a channel |
| `mda_analyzeChannel.m` | filtering, detection, stimulus assignment, parameters |
| `mda_rockerFilter.m` | removal of the periodic rocker artifact (option `rockerFilter`) |
| `mda_referenceBeat.m` | reference beat (mean ± SD) and comparison of every contraction with it |
| `mda_readEPRecording.m` | EP recording (LabChart `.mat`) aligned to the stimuli of the `.mdd` file |
| `mda_analyzeAP.m` | AP parameters (dV/dt max, RMP, V_max, APD25/50/90) per contraction, stimulus artefact handling |
| `mda_protocols.m` | stimulation protocols found from the comments of the log file |
| `mda_groupBeats.m` | contractions grouped by a stimulation quantity (pacing frequency, S2 interval, current, rest, ...), summary per group |
| `mda_protocolResults.m` | characteristic values per protocol and channel (max. captured frequency, FFR ratios, current thresholds, refractory periods, PRP at 15 / 30 / 60 s) |
| `mda_parameters.m` | names, units and definitions of the parameters |
| `mda_options.m` | options and defaults (incl. the advanced settings) |
| `mda_settings.m` | settings files: save / load all options (also from results files) |
| `docs/MyoDishAnalysis_settings_guide.pdf` | settings guide: legend of the force plot, pulse assignment, every advanced setting with figures |
| `docs/MyoDishAnalysis_quickstart_GUI.pdf`, `docs/MyoDishAnalysis_quickstart_watcher.pdf` | quick-start guides: first analysis in the GUI and reading the results (2 pages); the watcher (1 page) |
| `mda_report.m` | analysis report (PDF): channels to check, traces, commands that open the GUI there |
| `mda_summarize.m`, `mda_writeResults.m` | summary table, Excel/CSV export (info table: version and all settings) |
| `mda_readResults.m` | read a results file again (settings, analysis windows, contractions; GUI: Open ...) |
| `mda_labels.m`, `mda_addLabels.m` | labels per channel (metadata) |
| `mda_test.m` | self test (parameters, rocker filter) |
| `mda_testWatch.m` | test of the watcher with example recordings |
| `mda_testClockTime.m`, `mda_testSignalGaps.m`, `mda_testSliceRegister.m` | tests of the clock-time correction, the periods without signal and the slice register |
| `mda_timepoints.m`, `mda_testTimepoints.m` | windows before and after a treatment (from the watcher results) and its test |
| `mda_poolTimepoints.m` | analyses of `mda_timepoints` pooled by treatment (one table of all slices, images; test in `mda_testTimepoints.m`) |
| `mda_plotTimepoints.m` | figure for a manuscript and GraphPad Prism tables from a pool (test in `mda_testTimepoints.m`) |
| `mda_study.m` | time points of a study from a design table: analyses, pool with exclusions, methods text (test in `mda_testTimepoints.m`) |
| `mda_testGateInverted.m` | test of the longer gate of certain contractions, inverted signals and the analysis report |
| `mda_version.m` | version number |
| `example_MyoDishAnalysis.m` | examples |
| `examples/` | anonymized example recordings (`.mdd`, `_log.log`, `_labels.csv`, LabChart `.mat`), see `examples/README.md` |
| `py/` | Python version (same results), see `py/README.md` |
| `py/tools/anonymize_recording.py` | anonymize a recording before sharing it (dates, paths, file names, initials, structured log lines of software 2.1 and 2.2: persons, samples, slices, chambers, folders, times, free texts; `_labels.csv`; final check; tests in `py/tests/test_mda.py`) |
| `py/tests/event_logs_2_2/` | anonymized example event logs of the control software (release 2.2 preview, simulated device), test data of `test_protocol_end.py` and `mda_testProtocolEnd.m` |
