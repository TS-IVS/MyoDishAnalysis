# MyoDishAnalysis

Analysis of MyoDish recordings (`.mdd`) in MATLAB and Python: parameters of **every single contraction**,
reference beat, removal of the rocker artifact, alignment of a parallel EP recording (LabChart) and AP parameters.
Each has a command-line function (time range "from – to") and a GUI to view the recording and select the time
range or single contractions interactively. This file documents the MATLAB version (the reference);
the Python version (`py/`) gives the same results.

Version 1.0.0-beta.2 (2026-10-09) · Thomas Seidel, Friedrich-Alexander-Universität Erlangen-Nürnberg (FAU) / InVitroSys GmbH.
Public beta version (feedback welcome: GitHub issues or e-mail). Until 2026-10-06 named MyoDishContractionTool (functions MyoDishContractions,
MyoDishContractionsGUI, mdct_*); now MyoDishAnalysis, MyoDishAnalysisGUI, mda_*.
Python version with the same results: folder `py/` (see `py/README.md`).

## Citation and acknowledgement
MyoDishAnalysis was developed by Thomas Seidel, Institute of Cellular and Molecular
Physiology, Friedrich-Alexander-Universität Erlangen-Nürnberg / InVitroSys. If you publish results obtained with this
software, please cite the version you used (Seidel T. MyoDishAnalysis, version 1.0.0-beta.2, 2026; DOI: see
`CITATION.cff` or the Zenodo record of the release) and mention it in the Methods.
Copyright (c) 2026 Thomas Seidel. License: GNU General Public License, version 3 or (at your option) any later version
(GPL-3.0-or-later, file `LICENSE`). Free to use, also commercially (companies, InVitroSys customers). Copies, original
or modified, may only be passed on under the same license and together with their source code. The software comes
without any warranty. Questions and bug reports: thomas.seidel@fau.de
Additional terms (GPL-3.0 section 7 b, c, e): modified versions must be marked as modified and must not be
presented as the original MyoDishAnalysis (use a different name or a clear suffix); the copyright and author notice
(Thomas Seidel) must be kept; no rights to the names MyoDish and InVitroSys are granted.

## Requirements
MATLAB R2019b or newer. **No toolboxes.** Tested with MATLAB R2026a (macOS).
The log file `<name>_log.log` written by the MyoDish software must be in the same folder as the `.mdd` file.
Without it, 400 Hz is assumed and the number of channels is derived from the content of the status channel.

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
**Example recordings** (folder `examples`, see `examples/README.md`): anonymized MyoDish recordings of human ventricle
and atrium, rabbit, pig and rat ventricle (force-frequency, post-rest potentiation, isoprenaline, stimulation threshold
and rocker speed protocols) and a sharp-electrode recording with its LabChart export.

## GUI (`MyoDishAnalysisGUI`)
0. **Comments ...**: searchable list of the comments in the log file (date and time, time in the file, text; option
   "all log entries" adds events and settings). Search: all typed words must occur. Double-click a row (or select it
   and press **Go to**) to load the data around the comment (window length = currently loaded window, ≥ 30 s).
   Comments are marked purple in the overview and the force plot.
1. **Overview**: min/max envelope of the selected channel over the complete recording
   (green = rocker at rest; time axis h:mm, or h:mm:ss / m:ss when zoomed in or for short files). Drag in the
   overview, or type From/To (seconds) and press **Load**, to load a time window.
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
   the filters, x = excluded by you, blue ticks = stimuli, grey background = rocker moving, yellow = analysed range.
   Panel *Cursor in the force plot*: *drag = select time range* or *click = exclude / include contraction*.
   List *stimuli* (next to *only stimulated contractions*): *auto* / *MyoDish* / *ext. trigger* — stimulus times from
   the MyoDish pulses of the channel or from the external trigger pulses (external stimulator, see "External
   trigger").
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
4. **Table**: mean, SD and n (contractions with a value) of the selected contractions; at the end **extra beats**
   (contractions without an adequate stimulus, count and % of the detected contractions) and **missed beats**
   (stimuli without a contraction above the detection threshold, count and % of the stimuli), both over the whole
   range, independent of the rocker / stimulated filters; **uncertain** contractions (all, stimulated, extra) and
   uncertain missed beats (stimuli followed only by an uncertain contraction, i.e. missed with *high specificity*). **Lower plot**: one parameter per contraction over time, chosen
   with the list *Lower plot* above it (all parameters, plus stimToPeak and prominence; red = selected, dashed = mean
   of the selected contractions).
   **Trend ...** (next to the list): rolling mean or median (window in min) of a parameter over long periods and
   over several files in a row, e.g. the daily files `_0`, `_1`, `_2` ... of a culture (**Add series** finds all
   `<name>_<number>.mdd` of the open file; **Add files** any others). Time 0 = start of the first file; the files are
   placed by the recording start in their log files (system time), gaps without data are shown grey ("no data"),
   comments purple; time axis as time since start (h:mm) or clock time. **Sampling**: *short windows* (default:
   W = 30 s every T = 10 min; only these windows are read and analysed), *all contractions*, or *rocker stops only*
   (stop periods from the `rockerSpeed` entries of the log files; contractions with the rocker at rest). Use a rolling
   window ≥ 2 T. Reading the file dominates the time, not the analysis (24-h file via VPN: ~70 s to read, ~5 s to
   analyse one channel). Every window is a separate read (~0.25 s via VPN, a few ms in the lab network), so via VPN
   windows pay off from T ≈ 10 min on (24 h: ~35 s instead of ~75 s), in the lab network already at a few minutes.
   Analysing only every n-th contraction would not save time (the whole signal must be read and filtered anyway).
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
   **Open results ...** (button at the top; or `MyoDishAnalysisGUI(resultsFile)`, Python `mda-gui results.xlsx`):
   opens a results file of the command line, the watcher or the GUI (`.xlsx`, `<name>_info.csv`, `_summary.csv`,
   `_contractions.csv`): the recording (path in the file; if moved: the same name next to the results file, otherwise
   a file dialog), all settings (threshold and zero force of the channel, detection mode, rocker filter, filters,
   stimuli) and the analysis window (several: list of channel, range and time) are restored; contractions excluded by
   you in an export are excluded again. The contractions are detected again and compared with the file (status line:
   *the same as here* or the differences; black o = contraction of the file not found again, e.g. results of another
   version). A reference beat is not stored in the results (create it again).
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
  `rockerFilter`), `'externalTrigger','auto'|'on'|'off'` (see "External trigger"), `'showFigures',true`,
  `'quiet',true`; all others see `help mda_options`.
* Results files (`'output'`; the watcher; GUI exports): sheet / file **info** (key, value) with the version
  (`version`, `implementation` MATLAB / Python, `software`), the recording (`file`, sampling rate, recording start),
  `analysisDate`, `createdBy` (MyoDishAnalysis, MyoDishAnalysisWatch, MyoDishAnalysisGUI), the analysed `channels`,
  `chunkSeconds`, the watcher settings (`watcherOptions`, `watcherCode`) or the GUI window (`loadedWindow_s`,
  `analysedRange_s`, `epRecording`), every option (`option_<name>`, full precision) and the Offset / Calibration
  entries of the log file; sheet **thresholds** = analysis windows (per range, channel and chunk of `chunkSeconds`:
  analysed range `from`–`to`, data read `windowFrom`–`windowTo`, detection threshold). With these the GUI shows
  exactly the same contractions again (**Open results ...**). `mda_readResults` / `read_results` read them.
* `contractions`: one row per detected contraction; `summary`: one row per channel and range
  (counts incl. nExtraBeats, nMissedBeats, extraBeats_percent, missedBeats_percent, nUncertain,
  nStimulatedUncertain, nExtraBeatsUncertain, nMissedBeatsUncertain; mean, SD and n of all parameters of the included
  contractions). Column `uncertain` of `contractions`: contraction found with high sensitivity only (option
  `'detection'`, see "Signal processing and detection").

## Automatic analysis of new recordings (`MyoDishAnalysisWatch`; Python `mda-watch`)
```matlab
MyoDishAnalysisWatch('/data/myodish/raw', '/data/myodish/results', 'rockerFilter', true)
MyoDishAnalysisWatch(raw, results, 'fromDate', '2026-10-01', 'dryRun', true)   % only list what would be analysed
```
```bash
mda-watch /data/myodish/raw /data/myodish/results --rocker-filter --quiet
```
Each pass searches the raw folder (with subfolders) for `.mdd` files and analyses the new and changed ones. The
watcher only calls `MyoDishAnalysis`, `mda_readMdd` and `mda_protocols`: every improvement of the analysis applies to
its results as well.
* **Per recording** (results folder, same subfolders as in the raw folder):
  * `<name>_summary.csv`: one row per channel and time range. The ranges are time bins (`'binMinutes'`, default 60)
    **without the stimulation protocols** (default; `'includeProtocols',true` keeps them, `'protocolMarginSeconds'`
    also excludes some time after each protocol); a bin with a protocol gives several ranges. Columns `range` (clock
    time of the start of the range), `bin` (clock time of the start of the bin), `nComments` / `comments` (comments of
    the log file in the range, this channel or all channels).
  * `<name>_contractions.csv`: `'contractions','all'` (default: every contraction), `'thinned'` (every
    `'thinFactor'`-th contraction per channel, default 10, `'thinMode','nth'`; or the median of blocks of
    `'thinFactor'` successive contractions of the same type and rocker state, `'thinMode','median'`; extra beats and,
    with `'includeProtocols'`, the contractions in the protocols are always complete) or `'none'`. Columns
    `sampledEvery` (number of contractions represented by the row) and `sampleMode` (`singleBeat` / `median`).
    `'compress',true`: `<name>_contractions.csv.gz` (a double click unpacks it on macOS and Windows; pandas reads it
    directly; MATLAB: `gunzip` first; one file per recording). Trends from the summary (all contractions): every n-th
    contraction can alias the rocker modulation of the amplitude.
  * `<name>_overview.csv` (`'overviewSeconds'`, default 60; 0 = none): medians of **all** contractions per 1-min
    window (file time, split at the ranges), channel, beat type, rocker state and inclusion, with `window` (clock time
    of its start), `t_from`, `t_to`, `nBeats`, `beatsPerMinute` and the median of every parameter. About 1/30 (0.5 Hz)
    to 1/60 (1 Hz) of the rows of all contractions (8-h recording, 7 channels: 242,270 contractions, 99 MB →
    6,949 rows, 2.8 MB); opens in Excel. Medians of fixed windows instead of blocks of n successive contractions:
    where stimulated and extra beats alternate (spontaneous rate above the pacing rate), blocks of one beat type stay
    short. For an archive: all contractions compressed (`'compress',true`) and the overview uncompressed.
  * `<name>_protocols_*.csv`: every contraction in the protocols, summary per protocol, channel and group,
    `protocolResults` (if the log file contains protocols).
  * `<name>_events.csv` (`'events',true`): all entries of the log file with clock time, time in the file, channel,
    code, category (comment, protocol, recording, schedule, stimulation, rocker, calibration, warning, other) and text.
  * `<name>_gaps.csv` (`'gaps',true`, default): periods without force signal (`mda_signalGaps` / `signal_gaps`, see
    below) with clock times and the comments of the log file within 5 min of their start or end. The summary gets
    the columns `noSignal_s` (s without signal in the range) and `nChamberOut` (chambers taken out in the range).
  * `<name>_channels.csv` (`'gaps',true`): one row per channel with recording, `recordingStart`, `fileLength_s` and
    the status at the end of the recording (`beating`, `not beating` = no contraction in the last 30 min with signal
    outside the stimulation protocols, `protocols only` = no time outside the protocols, not analysed, `removed` =
    chamber taken out and not put back, `signal lost` = technical, `no slice`), `beatingAtEnd`, s with and without
    signal, chambers taken out,
    technical failures, number of contractions, last contraction (time in the file, clock time, median amplitude of
    the last 10 included contractions and in % of the 95th percentile of the recording), `idDate` (date of the
    experiment ID in the file name: a part of letters + 6 digits yymmdd, e.g. `ABC000101`) and `daysSinceIdDate` at
    the last contraction (or the end of the signal), `daysInCulture`, the labels `setupID`, `sliceID`, `species`,
    `sampleID`, `cultureStart` and `endComments` (comments of the channel about discarded, removed, not beating,
    fixed, frozen, … slices).
  * `_parameters`, `_info`, `_labels` (`_rockerFilter`: rocker artifact per channel and 30-min chunk). Labels per
    channel: `<name>_labels.csv` next to the `.mdd` file (saved by the GUI).
* **Slice register** (`'register',true`, default; `mda_sliceRegister` / `slice_register`, see below):
  `<experiment>/<experiment>_slices.csv` and `mda_slices.csv` (all experiments), updated after every pass.
* **Index** `mda_index.csv` (one row per recording; the same file for MATLAB and Python): size and time (UTC) of the
  `.mdd` file, size of the log file, status (`ok`, `error`, `running`, `noLog`), version, implementation, fingerprint
  of the core functions, options, analysis time, number of contractions, message. With `'reanalyze','outdated'`
  (default) a recording is analysed again when its files, the version, the options or (same implementation) the core
  functions change; `'new'`: only new and changed files; `'all'`. Errors are retried when something changed or with
  `'retryErrors',true`.
* **Report** `reports/mda_report_<date>_<time>.txt` per pass: for every analysed recording and channel the number of
  contractions, capture (% of the stimuli followed by a contraction), extra beats (% of the detected contractions),
  mean amplitude in the first and last bin with ≥ 10 contractions and flags (no contractions, capture < 90 %, extra
  beats > 10 %, amplitude change > 30 %; `'flagCapture'`, `'flagExtraBeats'`, `'flagAmplitudeChange'`); periods
  without signal by type and the channels that do not end beating.
* **Skipped**: files changed in the last 10 min (`'minFileAgeMinutes'`), names starting with `.` (rsync temporary
  files, hidden folders), recordings without `Recording stopped` in the log file (status `running`; analysed when
  unchanged for 30 h, `'incompleteAfterHours'`), recordings without log file (`noLog`). A lock file
  (`mda_watch.lock`) prevents two watchers on the same results folder; one left behind by a crashed run is ignored
  after 12 h (or delete it).
* **Daily**: the scheduler of the operating system (cron / launchd / Windows task scheduler) with `mda-watch ...` or
  `matlab -batch "MyoDishAnalysisWatch(...)"`; or `'interval', 24` (one pass every 24 h, MATLAB stays busy).
* Further options: `'newSliceHours'` (slice register, default 2), `'filter'` (regular expression on the relative
  path), `'maxFiles'`, `'protocols',false`,
  `'quiet',true`; all other name/value pairs are analysis options of `MyoDishAnalysis` for all recordings (e.g.
  `'rockerFilter',true`: rocker artifact removed in chunks of 30 min with 60 s context, result per chunk in
  `_rockerFilter.csv`). Python only: `--workers n` analyses n recordings in parallel (archives).
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
  signal: see the comments of the log file (`_gaps.csv` lists those within 5 min).
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
the data end. Built from the watcher results (`_channels.csv`, `_gaps.csv`, `_overview.csv`), written to
`<experiment>/<experiment>_slices.csv` (experiment = subfolder of the results and raw folder) and `mda_slices.csv`
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
`outHours`, `longestOut_min`, `nPutBack`, `nTechnical`, `endComments`. With `endStatus`, `lastAmplitude_pctMax` and `dayEnd` the
slices that died or were taken out can be counted and classified (e.g. dead vs. weak) with a criterion chosen later.

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
  the same type; several protocols of the same type are numbered (`FFR 1`, `FFR 2`). A start without an end lasts
  until the next protocol of the same type or the end of the file (note `no end comment`). Type from keywords:
  FFR / frequency → `FFR`, refractory / S1S2 → `RP`, threshold / stimCurrent → `ST`, post rest / PRP → `PRP`,
  pulse duration → `PD`, rocker speed → `rockerSpeed`, others `other` (FFR, RP, ST, PRP, PD also as words of a
  name such as `PD_Test_12Steps`). Schedule files loaded by a schedule (log events `Loaded schedule file …` /
  `Jumped back from loaded schedule file …`) are protocols, too, if their file name contains such a keyword
  (e.g. `FFR_60beats_0.2-4Hz…`, `RP_1000-240ms_FJump…`, `StimThreshold_2-90mA`, `PostRestPotentiation`); name = file
  name. Comments and file names about the schedule itself (`start scheduleFile_humanVentricle`) are ignored; of two
  protocols of the same type within each other (comment and schedule file) the outer one is listed. The table can be edited (`from`, `to`,
  `groupBy`) and passed as `'protocol', P`; the GUI shows it editable (`+ selected range` adds the range of the main
  window).
* **Grouping** (`mda_groupBeats`): every stimulus of the channel gets a value; a stimulated contraction belongs to the
  group of its stimulus, an extra contraction to the group of the last stimulus before it.

  | `groupBy` | value | default for |
  |---|---|---|
  | `pacingFrequency` | 1 / interval from the previous stimulus (Hz); intervals within 2 % are one group; label rounded to 0.05 Hz | FFR |
  | `S2interval` | S2 = premature stimulus (interval < 95 % of the previous one, next interval longer, previous stimulus not premature); groups `S2 <ms>` and `post-S2 <ms>` (the next stimulus; post-extrasystolic potentiation; S2 intervals within 7.5 ms are one group), `S1` (other stimuli at the basic interval, median ± 5 %, not followed by an S2), `pre-S2` (S1 followed by an S2: relaxation cut off) and `other` (other intervals, e.g. trains at a higher rate between the S1-S2 steps; analyse them with `pacingFrequency`) | RP |
  | `stimCurrent` | current of the pulse (mA, status channel); `currentReached_percent` per group | ST |
  | `pauseLength` | first stimulus after a pause (interval ≥ 1.5 s, ≥ 1.5 × the median interval and ≥ 1.5 × the interval before; the median interval returns within the next 3 stimuli): `rest <s>`, one group per pause with `groupStep` = number of the pause (pooling over channels whose effective pauses differ); stimuli within 10 s after a pause `after rest` (decaying potentiation, not part of the reference); other stimuli at the median interval (± 5 %) `steady` (reference); all others `other` | PRP |
  | `pulseDuration` | `chargeDuration` entry of the log file for the stimulated channel (ms) | PD |
  | `rockerSpeed` | rocker speed at the peak (rpm, `rockerSpeed` entries of the log file); all contractions by default | rockerSpeed |
  | `log:<code>` | any numeric entry of the log file for the stimulated channel (or channel 0), e.g. `log:pauseDuration` | – |
* **Summary**: one row per protocol, channel and group with `group`, `groupValue`, `groupRole`, `groupStep`, `groupBy`, `nStimuli`,
  `nContractions`, `capture_percent` (stimuli followed by a contraction, independent of the rocker filter),
  `amplitude_pctOfRef` (mean amplitude in % of the group `S1` / `steady`) and mean, SD and n of all parameters. The
  contraction table gets the columns `group`, `groupValue`, `groupRole`, `groupStep`; the Excel output a sheet
  `protocols`.
* **Protocol results** (`mda_protocolResults`; `info.protocolResults`, sheet `protocolResults`, GUI table "protocol
  results"): one row per protocol and channel. A group counts as *captured* if at most max(1, 10 % of its stimuli)
  are not followed by a contraction and ≥ 2 are (as in GetFFRdata / GetStimThreshold).

  | protocol | columns | definition |
  |---|---|---|
  | FFR | `maxCapturedFrequency_Hz` | highest captured pacing frequency |
  | | `FFR_1Hz_pct`, `FFR_2Hz_pct`, `FFR_3Hz_pct`, `amplitude_0p5Hz_uN` | mean amplitude at 1 / 2 / 3 Hz in % of 0.5 Hz (captured groups, ± 5 %) |
  | ST | `stimThreshold10_mA`, `…50`, `…95`, `…99` | lowest captured current whose mean amplitude is ≥ 10 / 50 / 95 / 99 % of the largest one (thresh10 … thresh99 of GetStimThreshold); `captureThreshold_mA` = lowest captured current, `maxAmplitude_uN` |
  | RP | `refPeriodNoPeak_ms` | S2 interval below which there is no separate contraction peak (< 50 % of the S2 with a peak) |
  | | `refPeriodNoResponse_ms` | S2 interval below which there is no response at all (median S2 response < noise level) |
  | | `…Step_ms`, `S2noiseLevel_pct`, `amplitudeS1_uN`, `nS2`, `nTemplateBeats` | distance of the two S2 intervals around the transition (uncertainty ≈ ± step/2), noise level, ... |
  | | `S2shortest_ms`, `S2longest_ms` | shortest / longest analysed S2 interval: a transition that is *not reached* (NaN, note) lies below `S2shortest_ms` (e.g. a slice that still gives a separate S2 contraction at the shortest S2 interval of the protocol), one *already at the longest interval* above `S2longest_ms` |
  | PRP | `PRP15_pct`, `PRP30_pct`, `PRP60_pct` (+ `_pause_s`) | amplitude in % of the steady reference after the pause nearest to 15 / 30 / 60 s (pause = stimulus interval − steady interval) |

  S2 response (as in GetRefractoryPeriod): the mean S1 contraction (S1 interval before and after, rocker at rest) is
  scaled to the S1 contraction of each S1-S2 pair (S1 … S2 + 20 ms) and subtracted; response = maximum of the
  residual (30-ms mean) S2 + 30 … 600 ms in % of S1; separate peak = local maximum of the force after the S2 with a
  prominence ≥ max(noise level, 2 %); noise level = 99th percentile of the response at pseudo-S2 on the S1 beats. A
  transition is the first S2 interval (from long to short) below the level whose next shorter interval is also
  below it, interpolated linearly. Example 8 (rabbit, ERP 460 ms in the lab table): no peak 477.5 ms, no response
  464 ms (step 29 ms).
* **Rocker, stimulated beats**: with `'protocol'` only stimulated contractions (`'beats','stimulated'`) with the
  rocker at rest are included unless `'rocker'` / `'beats'` is given (grouping by rocker speed: all). Sharp-electrode recordings (no rocker) and protocols without rocker stops need
  `'rocker','any'` (GUI: "all contractions"). A contraction counts as "rocker moving" if the rocker moved anywhere
  between its diastolic minimum and 90 % relaxation. After a stimulation pause the diastolic minimum is searched only
  in the last 0.5 s before the stimulus (option `pauseDiastoleWindow`), so that rocker movement or drift during the
  rest does not count (PRP: the rocker typically stops ~1.2 s before the post-rest stimulus).
* Examples: `examples/example3_humanVentricle` (FFR), `example8_rabbitVentricle_EP` (RP: no response ≤ 463 ms,
  response at 492 ms), `example2_rabbitVentricle` (PD, ST), `example7_pigVentricle` (PRP), `example1_rabbitVentricle`
  (rocker speed).

## Parameters (per contraction)
Within the cycle between the previous and the next peak (at most 3 s on each side):
F_dia = minimum before the peak, F_min,post = minimum after the peak. After a stimulation pause (stimulus interval
≥ 2.5 s and ≥ 1.5 × the interval before) F_dia is searched only from 0.5 s before the stimulus
(`pauseDiastoleWindow`; `Inf` = as for all other contractions).
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

Further columns: `t_peak` (s in the file), `clockTime`, `beatType` (`stimulated` = peak 25 ms …
min(stimulus interval, 1 s) after a stimulus of the channel; `extra` = not stimulus-locked; `unpaced` = no
stimuli in this channel), `t_stim`, `stimToPeak`, `rockerMoving` (rocker moved at any time between F_dia and
90 % relaxation), `included`, `prominence` (detection criterion); with `'rockerFilter',true` also `rockerCorrected`
(rocker moved and the artifact was subtracted).

## Signal processing and detection
* Data: 400 Hz, 2 samples averaged (200 Hz), moving median 50 ms + moving mean 25 ms (same processing
  as the lab's `GetContractionParameters`). The half-sample delay of the even filter windows is corrected.
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

## External trigger (external stimulator; option `'externalTrigger'`, GUI list *stimuli*)
With the external controller unit (one chamber) the slice can be paced by an external stimulator whose TTL pulses
are fed into the MyoDish: the status channel then has bit 14 (external trigger) set without channel and current bits
(e.g. a sharp-electrode setup with its own stimulator: 1 Hz, 4 Hz and S1-S2 intervals). These pulses are read as
`stim.channel = 0` (before 2026-10-08 they were read as channel 8, so the contractions of the slice in channel 1 were
all `unpaced`); a pulse of 2 samples (at USB reconnects) is one pulse. `'externalTrigger'`: `'auto'` (default) = the
external trigger pulses are the stimuli of the analysed channel if the window has no MyoDish stimulus pulses;
`'on'` = always (any data channel; MyoDish pulses ignored); `'off'` = never. GUI: list next to *only stimulated
contractions* (*stimuli: auto / MyoDish / ext. trigger*); the stimulus plot then shows the trigger pulses ("ext") and
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
| `mda_options.m` | options and defaults |
| `mda_summarize.m`, `mda_writeResults.m` | summary table, Excel/CSV export (info table: version and all settings) |
| `mda_readResults.m` | read a results file again (settings, analysis windows, contractions; GUI: Open results) |
| `mda_labels.m`, `mda_addLabels.m` | labels per channel (metadata) |
| `mda_test.m` | self test (parameters, rocker filter) |
| `mda_testWatch.m` | test of the watcher with example recordings |
| `mda_testClockTime.m`, `mda_testSignalGaps.m`, `mda_testSliceRegister.m` | tests of the clock-time correction, the periods without signal and the slice register |
| `mda_version.m` | version number |
| `example_MyoDishAnalysis.m` | examples |
| `examples/` | anonymized example recordings (`.mdd`, `_log.log`, `_labels.csv`, LabChart `.mat`), see `examples/README.md` |
| `py/` | Python version (same results), see `py/README.md` |
| `py/tools/anonymize_recording.py` | anonymize a recording before sharing it (dates, paths, file names, initials) |
