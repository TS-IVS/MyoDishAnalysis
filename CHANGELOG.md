# Changelog

All notable changes. Versions: `MAJOR.MINOR.PATCH` (pre-releases `-beta.N`; Python package: `1.0.0bN`).
MATLAB and Python versions have the same version number and give the same results.

## [1.0.0-beta.4] – 2026-10-10
Fourth pre-release for testers (Git tag `v1.0.0-beta.4`). **Analysis results change**: diastolic level, FFR steady
state, PRP reference, stimulus assignment and protocol grouping (below); the former behaviour is available as an option
value.

### Changed
- **Diastolic level** (2026-10-10; option `'diastolicLevel'`, default `'preStimulusMedian'`): F_dia = median of the
  unfiltered signal `diastoleWindowStart` … `diastoleWindowEnd` (60 … 5 ms) before the eliciting pulse (ends before
  the stimulus artifact). Before (`'minimum'`, still available): the last minimum of the filtered signal before the
  peak, which a short dip before the pulse (noise, rocker movement) lowered, enlarging the amplitude. Amplitude,
  `diastolicForce`, `diastolicSignal`, the upstroke levels (TTP, rise time, CD start) and the AUC refer to F_dia;
  the relaxation levels still refer to the minimum after the peak. Contractions without a pulse (extra, unpaced)
  and contractions whose median is at or above the peak use the minimum. Tests in `mda_test.m` / `selftest`
  (dip before the pulse: median 100 µN, minimum 50 µN) and `protocolSelectionTest` / `test_protocol_selection`
  (FFR steady state, PRP reference).
- **FFR steady state** (2026-10-10; option `'steadyStateBeats'`, default 10): each pacing frequency of an FFR protocol
  is summarized from the last 10 contractions of the longest run of consecutive stimuli at this frequency
  (`groupStep` = number of the run), of its longest sequence of captured stimuli whose previous and next stimuli are
  captured, too (preceding and following interval of each contraction = 1 / rate): partial capture (e.g. 2:1) gives
  no steady state (note `no run of captured stimuli`). Before (`0`): all contractions of the frequency in the protocol range,
  also those of the basic pacing before and after the protocol (e.g. 0.5 Hz) and of the first beats after a change of
  the rate.
  With the rocker `'stopped'`, a frequency without contractions with the rocker at rest is summarized from its
  contractions with the rocker moving (option `'ffrRockerFallback'`, default on; note).
- **PRP reference** (2026-10-10; option `'prpReference'`, default `'preceding'`): each post-rest contraction is
  divided by the median of the last `prpReferenceBeats` (6) contractions of the pacing before its pause (this pacing
  loads the SR). `'firstTrain'`: mean of the contractions of the pacing before the first pause; `'steady'`: mean of
  the group `steady` over the whole protocol (versions ≤ 1.0.0-beta.3). `amplitude_pctOfRef` of the post-rest groups
  and `PRP15/30/60_pct`.
- **Grouping tolerances of the protocols** (2026-10-10; options `'frequencyResolution'`, `'frequencyResolutionLow'`,
  `'pauseTolerance'`):
  `pacingFrequency`: the frequency of a cluster of intervals (within 2 %) is rounded to 0.1 Hz at ≥ 1 Hz and to
  0.05 Hz below 1 Hz (`'frequencyResolutionLow'`); clusters with the same rounded frequency are one group and
  `groupValue` is the rounded frequency (0.99, 1.0, 1.001 and 1.03 Hz = `1 Hz`, 0.74 / 0.75 Hz = `0.75 Hz`; before:
  label rounded to 0.05 Hz, 1.03 Hz = `1.05 Hz`, `groupValue` = 1 / median interval). FFR results: the groups at
  0.5, 1, 2, 3 Hz (before: ± 5 %). `pauseLength`: pauses within 10 % of the shortest pause of a set have the same
  pause length (`groupValue` = their median interval, labels numbered `#n`); `PRP15/30/60_pct`: mean of the pauses within ± 10 % of 15 / 30 / 60 s (before: the nearest pause within
  ± 50 %). Tests `groupingTest` (`mda_test.m`), `test_grouping_tolerances`.
- **Stimulus assignment by the onset gate** (2026-10-10; option `'stimAssignment'`, default `'onset'`): a pulse can
  only have elicited a contraction if it lies from onset − `gateMax` (0.15 s) to onset + `gateTolerance` (0.015 s);
  onset = tangent at the maximum dF/dt crossing the diastolic level. Several candidates: before the onset before after
  it, regular before extra pulses, of one kind the earliest within `gateCore` (0.06 s) before the onset, otherwise the
  latest. No pulse in the gate: onsets of the other rise phases of the upstroke (rocker movement, fused spontaneous
  events), then a pulse up to 5 ms before the maximum dF/dt. New columns `t_onset`, `stimToOnset`, `stimAmbiguous`.
  Before (`'stimAssignment','peak'`, still available): a peak 25 ms … min(stimulus interval, 1 s) after a pulse was
  `stimulated`. Results of older versions are opened with `'peak'` (`mda_readResults` / `read_results`). Example
  recordings (50 channels, 33,633 contractions): `beatType` unchanged in 41 channels; spontaneous contractions
  0.2–0.45 s after a pulse (rat, delay to the onset 6–16 ms) are now `extra`, a pulse is assigned to the first of two
  fused peaks and to very slow contractions (human, peak 1.5 s after the pulse). MATLAB references of the examples
  renewed (with the pulse tables).
- Extra pulses (status channel bit 16: pre-pulses, CCM pulses) are no longer counted as stimuli (counts, missed beats,
  intervals, protocols, groups, start of regular pacing). Before, every CCM pulse counted as a missed beat. 8 recordings
  of 2022–2026 (`'peak'` → `'onset'`): CCM test protocol (human, 10–300 ms offsets): stimulated 404–1183 → 3521–3564
  per channel, missed 7388–8167 → 0–10; CCM 30 ms after the regular pulse (human): stimulated 899 → 3509, missed
  6119 → 91; pre-pulse threshold protocol (rabbit): missed 1132 / 1213 → 410 / 427, 6 contractions elicited by the
  pre-pulse; pre-pulse protocol (human), rat, pig, human atrium and ventricle without extra pulses: stimulated within
  0–6 per channel. `stimAmbiguous` mainly in channels with strong rocker artifacts (pig, atrium) and in slow human
  slices with CCM (the regular pulse just outside the gate).
### Added
- Protocol summary (2026-10-10): `amplitude_CV` (coefficient of variation of the amplitudes, population SD / mean) and
  `irregular` (`amplitude_CV` > `irregularCV`, 0.15: conduction block, alternans, extra beats) per group; note for
  FFR frequencies with fewer than `minGroupBeats` (5) included contractions.
- Protocol results, RP (2026-10-10): `refPeriodAllCaptured_ms`, the shortest S2 interval above which every S2 gives a
  separate contraction peak (from long to short: the interval before the first one with a missing peak), the
  definition of the refractory period of the MyoDish export. It is more sensitive to a single S2 without a separate
  peak: in 323 recordings of human slices (days 0–7) `refPeriodNoPeak_ms` (50 % criterion, unchanged) agreed better
  with the export (within 10 %: 95 vs 85 %; bias −1 vs +13 ms).
- Watcher and slice register (2026-10-10): column `calibration` (`Calibration` entries of the log file, AU per mN) in
  `<name>_channels.csv`; `calibration` and `calibrationChanged` in the slice register (calibration changed during the
  slice or differs between rows of the same `sliceID`, e.g. a slice moved to another setup).
- Settings guide 0.4: diastolic level, FFR steady state and PRP reference (figures 10 and 16).
- **Advanced settings** (2026-10-10): all constants of the method that are based on assumptions or experience are
  options (78 new ones; defaults = the former constants, results unchanged except the protocol grouping above):
  stimulus assignment (`risePhaseLevel`, `steepRiseMargin`, `contractionEnd`, `offsetSnap`), detection and certainty
  (`pacedMinStimuli`, `pauseMinInterval`, `pauseIntervalRatio`, `lockWindow`, `lockWindowRel`, `certain...`), noise level and artifact gap rule (`noise...`,
  `artifact...`, `chanceMargin`, `chanceMax`), rocker rules (`rockerRuleMinFraction`, `noise...Max`, `rhythm...`,
  `keep...`, `dropRel`, `small...`, `rockerOnly...`, `captureTolerance`), spike removal (`spike...`), rocker filter
  (`rockerHzPerRpm`, `rf...` incl. the contraction masks), protocol grouping (`frequencyResolution`,
  `frequencyResolutionLow`, `pauseTolerance`), `pulseTextMax`. GUI **Advanced ...** (MATLAB and Python): one tab per part (Assignment,
  Detection, Noise / artifacts, Rocker rules, Signal, Rocker filter, Protocols, Export), default and unit next to
  every field, * = the window is read again (downsampling, spike removal, rocker source); buttons Guide, Save
  settings ..., Load settings ... (settings file or results; with the rocker filter, detection and filters of the
  main window). Settings files: `mda_settings` / `settings.py` (key / value .csv as the info table),
  `mda_options('settings', file)`, `options(settings=file)`, `MyoDishAnalysis(..., 'settings', file)`, `--settings`
  (`mda-analyze`, `mda-watch`), watcher (index records the values); `mda_readResults` / `read_results` read a single
  key / value table. Settings guide `docs/MyoDishAnalysis_settings_guide.pdf` (legend, pulse assignment, a figure and a
  table for every tab). MATLAB references renewed (options in the reference files).
- **Legend of the force plot** (MATLAB and Python GUI, 2026-10-10): all markers (selected, uncertain, excluded by
  filter / by you, outside the range, deviating, elicited by an extra pulse, ambiguous, only in the results file,
  stimulus / extra pulses, rocker moving, analysed range, comments, signal before the rocker filter; only those that
  occur); menu *View*, right click in the force plot; also in the saved force plot (MATLAB). API `api.legend(tf)` /
  `win.on_legend(tf)`.
- Extra pulses and pulse table (2026-10-10): every contraction gets its eliciting pulse (`stimPulse` = pulse ID = raw
  sample number, `stimCurrent`, `stimChargeDuration`, `stimPauseDuration`, `stimDechargeDuration` from the log file),
  `elicitedByExtraPulse`, and the pulses without own contraction as `prePulses` (up to `prePulseWindow`, 1 s, before
  the eliciting pulse) and `postPulses` (eliciting pulse … 90 % relaxation): `t<ms>|<mA>|<charge>|<pause>|<decharge>`,
  several joined by `&` (time relative to the eliciting pulse; the programmed offset of the log `Sequence` entries if
  within 5 ms). Summary: `nMissedDuringContraction`, `nExtraPulses`, `nElicitedByExtraPulse`, `nAmbiguous`. Pulse table
  (option `'pulseTable'`, default on): `info.pulses`, sheet / file `pulses` (`<name>_pulses.csv` beyond the Excel row
  limit; watcher `_pulses.csv(.gz)`, like the contractions): pulse, channel, time, extra, current, durations, outcome,
  role, contraction, coupling interval, time since the last onset, phase. Log file: `chargeDuration` /
  `pauseDuration` / `dechargeDuration` of log channel c and 10k + c (extra pulse #k), `Sequence` entries (`S.pulseSettingsLog`,
  `S.extraPulseLog`). Tests `mda_testExtraPulses.m`, `selftest.extra_pulse_test` (temporary .mdd with CCM, sub- and
  supra-threshold pre-pulses, missed and ambiguous cases).
- GUI **Advanced ...** (MATLAB and Python, 2026-10-10): stimulus assignment and gate parameters, stimulus source (moved
  from the list *stimuli* next to *only stimulated contractions*), detection parameters (relThreshold, minThreshold,
  minBeatInterval, maxBeatWindow, pauseDiastoleWindow, rocker artifact rules), moving median / mean, spike removal,
  pulse table; Defaults, Apply, OK. Force plot: extra pulses (green ticks), contractions elicited by an extra pulse
  (green rings), ambiguous assignments (black diamonds); table and counts with the new numbers; exports with the
  sheet `pulses`. API `api.advanced(struct)` / `win.api_advanced(dict)`.
- Spike artifacts (2026-10-10): `mda_removeSpikes` / `spikes.remove_spikes`, option `'spikeRemoval'` (default on) of
  `mda_readMdd` / `read_mdd`. Short (<= 100 ms) excursions with abrupt edges (jumps between two raw samples >=
  max(50 AU, 8 x noise), largest jump >= 50 % of the excursion) beyond the level before and after them, e.g. when a
  chamber is taken out or put in or with electrical interference, often in several channels (within +-10 ms of a
  spike of another channel the threshold is halved), are replaced by a line before the averaging of the raw samples;
  level changes (steps) stay. `S.spikes` (channel, from, to, size), note of the analysis (number per channel),
  `info.spikes`. `mda_signalGaps` measures the spikes at the periods without signal on the raw data. Checked on 42
  recordings of 2020-2026 and with spikes added to real recordings (rat, rabbit, human: 85-97 % found, contraction
  counts as without the spikes in 17 of 19 channels, median amplitude and CD90 within 0.2 %; without the removal up to
  9 extra 'contractions' per channel). Tests `mda_testSpikes.m`, `py/tests/test_spikes.py`; MATLAB references of the
  example recordings with spikes (ex1, ex3, ex3ref, ex4, ex5, ex6) and of the protocols renewed.
- Protocols without end comment (2026-10-10): the end is estimated (`mda_protocols` / `find_protocols`): start of
  regular pacing after the protocol start (> 5 min + one interval with the same interval, current and pulse duration
  (log `chargeDuration`); lower median over the stimulated channels; pulses < 50 ms apart ignored), otherwise the
  start of the next protocol (any type) or the end of the file. Note `no end comment: end estimated at ... s (...)`;
  new column `protocolNote` of `protocolResults`; `mda_protocols(file, minutes)` (0 = only next protocol / end of
  the file). Before: until the next protocol of the same type or the end of the file (e.g. a threshold protocol
  without end comment excluded a whole day from the summary of the watcher). Checked with 125 protocols with end
  comment (end estimated as if it were missing): FFR, ST, RP within 10 s in 74 of 75, PRP 21 of 25 (all within 60 s);
  PD protocols followed by another protocol within < 5 min end at that protocol. Tests `mda_testProtocolEnd.m`,
  `py/tests/test_protocol_end.py`.
- Overview and slice register (2026-10-10): watcher file `<name>_overview.csv` (`'overviewSeconds'`, default 60;
  Python `overview_seconds`, `--overview-seconds`): medians of all contractions per 1-min window, channel, beat type,
  rocker state and inclusion with `nBeats` and `beatsPerMinute` (1/30 to 1/60 of the rows of all contractions, for
  Excel). `<name>_channels.csv`: columns recording, recordingStart, fileLength_s and the labels setupID, sliceID,
  species, sampleID, cultureStart; status `protocols only` (no time outside the stimulation protocols), `not beating`
  judged at the end of the analysed signal (stimulation protocols at the end excluded). Slice register
  `mda_sliceRegister` / `slice_register` (watcher `'register'`, `'newSliceHours'`; Python `--no-register`,
  `--new-slice-hours`): one row per slice over the recordings of a setup (new slice after a recording without
  signal or >= 2 h without signal unless a comment says 'moved back' / 'put back', after a comment such as 'new
  slice', or with another sliceID) with start and end time, start reason, end status, last amplitude, days in
  culture and chamber-out periods; files `<experiment>/<experiment>_slices.csv` and `mda_slices.csv`. The slice
  register does not change the code fingerprint (no reanalysis). Tests `mda_testSliceRegister.m`,
  `py/tests/test_slice_register.py`.
### Fixed
- Watcher, `<name>_channels.csv` (2026-10-10): a contraction in a channel without signal (artifact, e.g. when the
  chambers of other channels are put back) stopped the Python watcher with `ValueError: cannot convert float NaN to
  integer` (MATLAB: `lastContractionClock` NaT). `lastContraction_s` and `lastContractionClock` are now given for every
  channel with contractions; the status stays `no slice`. Test in `py/tests/test_watch.py`.
- `mda_analyzeChannel` / `analyze_channel` (2026-10-10): a held value above the diastolic level (e.g. chamber out)
  can contain a local maximum from rounding of the filter (amplitude ~1e-13 uN) whose prominence relative to the
  surrounding signal passes the threshold. Python stopped with `IndexError: index -1 is out of bounds` (AUC); MATLAB
  kept the peak with NaN timing parameters. An amplitude <= 1e-9 x max(1, |F_dia|) is now treated like no upstroke
  (parameters NaN, not included); the AUC is skipped if no sample lies below the 10 % level.
- Protocol analysis of long protocols (2026-10-10): a refractory-period protocol without end comment and with a gap
  of many hours in the log extends to the end of the recording (> 10^4 stimuli); `mda_protocolResults` /
  `protocol_results` (rocker at rest: a mask over all samples per stimulus; leave-one-out template: the sum of all
  template beats per beat) and `mda_groupBeats` / `group_beats` (stimulus of every contraction: a search over all
  stimuli per contraction) needed hours or did not finish (watcher hung). Binary search, cumulative sums, `ismember`
  / one-pass lookups instead; same results.

## [1.0.0-beta.3] – 2026-10-10
Third pre-release for testers (Git tag `v1.0.0-beta.3`): GUI changes only, analysis results identical to 1.0.0-beta.2.

### Changed
- GUI (MATLAB and Python): the values at the mouse pointer are written small in the top left corner of every plot
  (no boxes next to the pointer); the windows always use light colors, also with a dark theme of MATLAB (R2025a+) or
  of the operating system (Python: light color scheme, Qt < 6.8: Fusion style with a light palette).

## [1.0.0-beta.2] – 2026-10-09
Second pre-release for testers (Git tag `v1.0.0-beta.2`, no GitHub release / DOI yet).

### Added
- GUI, EP recordings (MATLAB and Python, 2026-10-09): **y limits** of the signal and stimulation plot — drag up / down
  in the plot (band = new limits), double-click = automatic, right click *Set y limits ...* / *y limits: automatic
  (restore view)*; kept when the time axis changes (before: automatic, after AP markers frozen). **remove stimulus
  artefact** (checkbox, right-click menu): pulses and artefact replaced by straight lines (grey) in the signal plot,
  display only (`mda_analyzeAP('removeArtefacts', EP)`, Python `remove_artefacts`; same end of the artefact as the AP
  analysis, then the decay towards the RMP for ≤ 10 ms). MATLAB reference ex8 regenerated (`epClean`), compared in
  `compare_matlab.py`.
- GUI (MATLAB and Python, 2026-10-09): **mouse pointer** over the force, stimulus, parameter or EP plots: dashed line,
  marker and value in every plot at that time (force, nearest stimulus pulse, parameter of the nearest contraction,
  EP signal and stimulation); time and time since the last stimulus in the plot under the pointer. API
  `epYLim`, `epRemoveArtefacts`, `hover` (MATLAB), `ep_set_ylim`, `ep_set_clean`, `hover` (Python).
- GUI (MATLAB and Python, 2026-10-09): buttons under the force plot – ◀ / ▶ move the loaded window (= selection in
  the overview, analysed range) by half its length (shift + click: extend it on that side), →← / ←→ zoom it in / out
  (half / twice its length); the arrow keys in the force plot do the same (before: only the display, the window
  followed when the view left it); the mouse wheel zooms only the display. Trend window: *several channels ...* in the
  channel list overlays the trends of several channels (one colour per channel, read once; export with column
  `channel`). API `navButton`, `trend` (MATLAB), `on_nav_button`, `nav_window`, `TrendWindow.set_channels`,
  `export_tables` (Python).
- Peaks of the rocker movement are no longer counted as contractions (paced channels, auto threshold; option
  `rockerArtifacts`, default on; 2026-10-09). a) Small peaks between the contractions while the rocker moves
  (≤ 0.5 × typical amplitude, not locked to the stimuli: latency not within ±0.1 s of the median latency of the
  contractions) that form a cluster separated from the contractions by a clear gap (ratio ≥ 1.6, ≥ 3 such peaks, at
  most chance level + 0.2 of the cluster locked, ≥ 75 % with the rocker moving): the threshold is raised into the
  gap; small peaks locked to a stimulus (alternans, partial capture) stay. b) Rocker moving in ≥ 50 % of the data:
  rocker / noise level N = 90th percentile of the rise of the signal in the 0.5 s before the stimuli (≥ 10 stimuli
  after intervals ≥ 0.9 s). If < 50 % of the largest peaks (as many as stimuli) are locked to the stimuli (±0.1 s
  around the densest 0.2-s window of their latencies) and their typical amplitude is ≤ 50 µN, or ≤ 2 × N with the
  peaks at the rhythm of the rocker (0.7–2.2 peaks per rocker cycle or a median interval of 1 or ½ rocker period;
  rocker speed of the log file × 0.0202 Hz/rpm): all peaks < 3 × max(typical, N) are removed, except locked peaks
  ≥ max(1.5 × N, N + 50 µN) if there are ≥ max(3, 5 % of the stimuli) of them and more than by chance (slices that
  answer only some stimuli); `C.noContractions` = no peak left (slice not beating). c) Otherwise peaks not locked to
  the stimuli below min(1.5 × N, 0.5 × typical) are removed (below min(1.5 × N, typical) if they are at the rhythm
  of the rocker). `C.thresholdArtifacts` = removed peaks, `C.noiseLevel` = N; GUI status line. Checked on 35 test
  recordings (820 windows of 10 min × channel) and visually on rocker-only, partially capturing and dying slices;
  known limit: an unlocked spontaneous rhythm at the rocker frequency with amplitudes ≤ 2 × N counts as rocker. The
  examples change accordingly (e.g. example 4: channels 6 and 7 without contractions, example 3: 642 peaks of
  channels 3 and 5 at the noise level); MATLAB references ex1, ex3, ex3ref, ex4, ex5, ex6 and protocols
  regenerated.
- Results show version and all settings and can be opened in the GUI again (2026-10-09): the info table of every
  results file (command line `'output'`, watcher, GUI exports) has the rows `version`, `implementation`, `createdBy`,
  `channels`, `chunkSeconds`, watcher settings (`watcherOptions`, `watcherCode`) or the GUI window
  (`loadedWindow_s`, `analysedRange_s`, `epRecording`) and every option in full precision (`%.15g`; before: 4–5
  significant digits); new sheet / file `thresholds` = analysis windows (range, channel, `from`, `to`, threshold,
  data window `windowFrom`, `windowTo`; also `info.thresholds` of `MyoDishAnalysis`). Every data export of the GUI
  (plots, overlay, trend, rocker artifact) contains the table `info`; *Export this channel* writes the effective
  threshold and zero force of the channel (before: the GUI defaults) and the analysis window. New `mda_readResults` /
  `read_results`; GUI **Open results ...** / `MyoDishAnalysisGUI(resultsFile)` / `mda-gui results.xlsx`: recording,
  settings, analysis window and manual exclusions restored, contractions detected again and compared with the file
  (black o = only in the file). Checked: MATLAB and Python open their own and each other's results (command line,
  GUI export) with identical contractions; watcher results via the tests. GUI API `openResults`, `rockerWindow`,
  `nextFile`, `exportChannel`, `exportPlotData` (MATLAB), `open_results`, `on_rocker_window`, `next_file` (Python).
- GUI **Rocker artifact ...** (2026-10-09): window with the signal before / after the rocker filter and the removed
  periodic artifact of the selected channel and loaded window (also when the filter is off); save as figure, export
  the data of the visible time range (with the result of the filter and the table `info`).
- Detection modes and uncertain contractions (option `detection`, 2026-10-09): `'sensitive'` (default, *high
  sensitivity*, results as before) counts all contractions and flags the uncertain ones (new column `uncertain` after
  `included`); `'specific'` (*high specificity*) does not count them. Paced channels: certain = locked to the stimuli
  (latency within ±min(0.1 s, 0.2 × stimulus interval before the largest contractions) of the typical latency) and
  ≥ 2 × the median rise before the stimuli (`C.noiseMedian`; unknown: locked suffices), or ≥ 0.7 × typical and
  ≥ 3 × that rise; unpaced: ≥ 0.5 × typical; manual threshold: not assessed. Summary columns `nUncertain`,
  `nStimulatedUncertain`, `nExtraBeatsUncertain`, `nMissedBeatsUncertain` (stimuli followed only by an uncertain
  contraction = missed with `'specific'`; `C.stimCapturedCertain`), also per protocol group; GUI list *high
  sensitivity / high specificity* next to *remove rocker artifact*, uncertain contractions orange, counts in the
  table, status line and copied summary. Check on 35 windows (266 channel windows): sensitive − uncertain = specific
  in every window; clean channels without uncertain contractions. The contraction masks of the rocker filter always
  use all contractions (independent of the mode). MATLAB reference ex3 case `spec` added; references regenerated.
- Rocker peaks at high pacing rates (2026-10-09): without a noise level before the stimuli (no intervals ≥ 0.9 s),
  peaks at the rhythm of the rocker (≥ 60 % of the intervals 1 or ½ rocker period, ≥ 10 intervals), not locked to the
  stimuli (±min(0.1 s, 0.2 × stimulus interval)) and no 1:1 / 2:1 capture at the rocker period are removed while the
  rocker moves (< 3 × the median of the largest peaks; locked peaks of partial capture stay). Known limit: pacing at
  the rocker frequency (60 rpm ≈ 1.2 Hz) cannot be told apart.
- Periods without signal (2026-10-08): `mda_signalGaps` / `signal_gaps` find periods of identical consecutive raw
  samples (≥ 2 s; the controller repeats the last value when a sensor board is missing): `chamber out` (one channel),
  `board group` (≥ 3 channels of group 1–4 or 5–8 within 1 s, or 2 within 0.1 s: technical, a defective board
  disturbs its group; two chambers taken out with both hands stay `chamber out`), `controller` (both groups),
  `saturated`, `no signal` (whole file); spread of the event, levels before / after (diastolic level, change after
  putting the chamber back) and spikes. Watcher (`'gaps',true`): `<name>_gaps.csv` with clock times and nearby
  comments, summary columns `noSignal_s` and `nChamberOut`, `<name>_channels.csv` with the status of every channel at
  the end of the recording (beating, not beating, removed, signal lost, no slice), last contraction and amplitude,
  days since the date of the experiment ID and comments about the end of the slice; report lines. Tests
  `mda_testSignalGaps.m`, `py/tests/test_signal_gaps.py`.
- Watcher (2026-10-08): `MyoDishAnalysisWatch` / `mda-watch` (`myodish_analysis.watch`) analyses the new and changed
  recordings of a folder and its subfolders: every contraction of the whole recording, summary per time bin (clock-time
  labels), stimulation protocols with protocol results; index `mda_index.csv` shared by MATLAB and Python (recordings
  are analysed again when their files, the version, the options or the core functions change); report per pass with
  capture, extra beats, amplitude change and flags; running recordings, missing log files and rsync temporary files
  are skipped. Only calls of the core functions. Tests `mda_testWatch.m`, `py/tests/test_watch.py`.
  Options: summary without the stimulation protocols (default; `includeProtocols`, `protocolMarginSeconds`),
  contractions `all` / `thinned` (every n-th or median of blocks of n, extra beats complete; columns `sampledEvery`,
  `sampleMode`) / `none`, `compress` (.csv.gz), events file and comments per range, Python `--workers`.
- Header field `recordingStopped` (`mda_readMdd` / `read_header`): 1 if the last `Recording` entry of the log file for
  this file is `stopped`, 0 if the recording is still running (or was aborted), NaN / None without such entries.
- `mda_version.m` (version number, also in the `info` sheet).

- Rocker state from the log file where the status channel does not contain it: if bit 15 (rocker moving) is never
  set while the log file has rocker speeds > 0 (firmware error in some setups), or if there is no status channel, the
  state is reconstructed from the `rockerSpeed` entries (moving while rpm > 0, 0.27 s after the entry). The status
  channel bit has priority whenever it is present. Options `rockerSource` (`auto` | `status` | `log`) and
  `rockerLogDelay`. Checked on the 7 example recordings with rocker bit: the reconstructed state agrees with the bit in
  ≥ 99.96 % of the samples. Example 8 (sharp electrode) has the missing bit.

- Stimulation protocols: `mda_protocols` / `find_protocols` find protocols from the comments of the log file
  (`start … protocol` / `end … protocol`; FFR, RP, ST, PRP, PD, rocker speed; several per file). `mda_groupBeats` /
  `group_beats` group the contractions and stimuli by pacing frequency, S2 interval (S1 / S2 / post-S2), stimulus
  current, rest interval, pulse duration, rocker speed or any numeric log entry; summary per group with capture and
  amplitude relative to S1 / steady state. `MyoDishAnalysis` options `'protocol'` and `'groupBy'` (Python `protocol=`,
  `groupBy=`; command line `--protocol`, `--group-by`, `--list-protocols`); sheet `protocols` in the results.
- Protocols also from schedule-file events of the log file (`Loaded schedule file <name>.txt` … `Jumped back from
  loaded schedule file`), if the file name contains a protocol keyword (e.g. `PD_Test_12Steps`, `StimThreshold_2-90mA`);
  keywords also as words of CamelCase / underscore names. Comments and file names about the schedule itself
  (`start scheduleFile_…`) are ignored (they were listed as a protocol spanning the whole file; with `FFR_and_PRP` in
  the name as a PRP protocol that hid the real PRP protocols).
- Protocol results (`mda_protocolResults` / `protocol_results`; `info.protocolResults`, sheet `protocolResults`, GUI
  table "protocol results"), one row per protocol and channel: maximum captured frequency and amplitude at 1 / 2 / 3 Hz
  in % of 0.5 Hz (FFR); current thresholds at 10 / 50 / 95 / 99 % of the maximum amplitude and the lowest captured
  current (ST); refractory periods "no separate peak" and "no response at all" from the S2 response (subtraction of
  the scaled S1 template, noise level from pseudo-S2 as in GetRefractoryPeriod) (RP); post-rest potentiation at the
  pauses nearest to 15 / 30 / 60 s (PRP). RP also gives the shortest and longest analysed S2 interval
  (`S2shortest_ms`, `S2longest_ms`), so that a refractory period below the tested range ("not reached", NaN) can be
  reported as < `S2shortest_ms`.
- GUI (MATLAB and Python): window **Protocols ...**: editable protocol list, channels, rocker selection, grouping,
  plot of a parameter against the quantity (mean ± SD / SEM), result table, figure and data export.

- GUI (MATLAB and Python, 2026-10-07):
  - Detection threshold per channel (*auto* or a manual value for each channel, kept when switching channels; used
    for All channels, Protocols and Trend). `MyoDishAnalysis` / `myodish_analysis` accept one threshold per channel
    (`'threshold',[NaN 300 ...]`, NaN = auto; command line `--threshold t1 t2 ...`).
  - Arrow keys: ← / → move the time axis by half its length, shift + ← / → extend it, ↑ / ↓ zoom; over the overview
    its time axis, otherwise the force plot (the loaded window follows and is read again; the zoomed overview moves
    along).
  - Overlay window: other channels for the same range by checkboxes; time course of the range (t = 0 at the first
    stimulus of each group); colour, line width, line style and band (SD / SEM / range) per group; editable legend
    texts, title, axis labels and legend position; **Edit figure ...** (MATLAB plot tools / matplotlib figure
    options); export with SEM, min and max.

- External trigger pulses as stimuli (2026-10-08, MATLAB and Python): pulses of the status channel with bit 14 and
  without channel / current bits (external stimulator at the external controller unit, one chamber) are read as
  `stim.channel = 0` (one pulse also if 2 samples long) and are the stimuli of the analysed channel with the new option
  `externalTrigger` (`'auto'` default: if the window has no MyoDish pulses; `'on'`, `'off'`; command line
  `--external-trigger`; GUI list *stimuli: auto / MyoDish / ext. trigger*). Stimulus plot, export and EP alignment
  (`mddChannel` 0) included. Before, these pulses were read as channel 8 and the contractions of the slice (in
  channel 1) were all `unpaced`. Self tests with a temporary .mdd file.

### Fixed
- 12-hour time stamps (2026-10-08): MyoDish software 2.0.7717–2.0.7769 (builds of 16.02.–09.04.2021; one setup used
  2.0.7769 until 2024) wrote the system time of the log file with a 12-hour clock and without AM/PM (17:04 as 05:04).
  New `mda_clockTime` / `clock_time` derive AM/PM from the continuous dataLogTime (offset clock time − dataLogTime
  shared by most entries; entries with stale or frozen dataLogTime in chronological order), from
  `Started/Stopped parallel recording: … HH:mm:ss` entries, or, if all entries of a recording lie on the same side of
  noon/midnight, from the time of the .mdd file (within 15 min of the end); otherwise the times stay as written and a
  note says so. Used by `mda_logEntries` (clock time of all entries; info in `E.Properties.UserData`, Python
  `E.attrs['clock']`) and `mda_readMdd` (`recordingStart`, note in `notes`). 24-hour logs are never changed.
  Archived logs 2020–2026 (16,205): 2,043 with 12-hour time stamps, 1,191 corrected; in 483 the recording
  start was 12 h off (clock time of the contractions, days in culture, watcher bins). MATLAB and Python identical on
  2,640 logs. Tests `mda_testClockTime.m`, `py/tests/test_clock_time.py`.
- Python GUI extra: PySide6 6.12.0 is excluded for Python 3.10 / 3.11 (crash at interpreter exit, `free(): invalid
  size`, after the plots were redrawn; 6.11.2 and Python 3.12 / 3.13 are fine). Found by the CI job ubuntu / 3.10.

### Changed
- `mda_logEntries`: clock time from the integer milliseconds of the log file (was seconds + ms / 1000 as a float, so
  that `.SSS` sometimes showed 1 ms less than Python and the log file).
- RP protocol results: a numerically zero S1 template (flat signal, mean of the baseline-corrected traces ±1e-12 µN)
  is "no S1 contraction" in both versions (MATLAB continued with +7e-12, Python stopped with 0 / −2e-13; found by
  comparing the watcher results of 31 recordings).
- Diastolic minimum (F_dia) after a stimulation pause (stimulus interval ≥ 2.5 s and ≥ 1.5 × the interval before):
  searched only from 0.5 s before the stimulus (new option `pauseDiastoleWindow`, `Inf` = previous behaviour), not
  during the pause. Post-rest contractions of PRP protocols were counted as "rocker moving" (and excluded with
  `'rocker','stopped'`) because the minimum lay in the rest while the rocker still moved. Example 7: all post-rest
  contractions (3–61 s) are now included, amplitudes ≤ 1.3 % lower. In the other examples only the first
  contraction after a longer interval changes (FFR step to 0.2 Hz, ST pause of 6 s; ≤ 0.6 %, with rocker filter
  ≤ 1.8 %); regular pacing is unchanged.
- `S2interval` grouping: `S1` = stimuli at the basic interval (median ± 5 %); stimuli at other intervals (e.g. the
  trains at increasing rates between the S1-S2 steps of the daily RP schedule) form the group `other` instead of
  being part of the S1 reference (`amplitude_pctOfRef`).
- Log file: the first `Recording started` entry is the start of the data. A recording that was stopped and started
  again is appended to the same `.mdd` file (dataLogTime continues); the last start was used before, which shifted
  `clockTime` by the length of the interruption, set all earlier rocker speed entries to the file start and broke
  grouping by log values (e.g. pulse duration). A later start counts only if the dataLogTime starts again. Known
  limitation: one start time per file, so `clockTime` of the data recorded after a restart is early by the length of
  the interruption.
- `pauseLength` grouping (PRP): a pause needs a known, ≥ 1.5 × shorter interval before it and the return of the steady
  interval within 3 stimuli, so the second (2 s) interval after each post-rest beat, a lower rate at the end of the
  protocol and the first intervals of the recording are no longer rests. One group per pause with the new column
  `groupStep` (number of the pause; the effective pause differs between channels in recent firmware). Stimuli within
  10 s after a pause form the group `after rest` and are no longer part of the `steady` reference (the reference is
  now the steady pacing before the first pause, as in GetPostRestPotentiation). Example 7: reference 4184 instead of
  4052 µN, post-rest 104–119 %.
- `S2interval`: S1 stimuli followed by an S2 form the group `pre-S2` (relaxation cut off; not in the S1 reference).
- Protocols: only stimulated contractions by default (`'beats','stimulated'`, as in the original protocol scripts);
  a protocol start comment repeated within 10 s counts once.
- Protocols: note `gap of … in the log` when the log has a gap of > 10 min within a protocol (the schedule stalled;
  found in 4 of 146 daily schedule files, e.g. 23.5 h, after which the remaining commands were sent within 1 s).
- Protocol summary of a channel without stimuli in the range: no error in Python (group `unknown`, as in MATLAB; also
  for `S2interval`).
- Command line: hint when no contraction is included because the rocker moved during all of them
  (`'rocker','any'`).
- Tests: tolerance of the rocker-filter comparison per statistic (summary means 0.5 %, SDs 2 %); which flat peaks move
  by one sample depends on the linear-algebra library.

## [1.0.0-beta.1] – 2026-10-07
First public pre-release (beta for testers and collaborators).

### Added
- MATLAB: `MyoDishAnalysis` (command line, ranges in s, labels, Excel/CSV export) and `MyoDishAnalysisGUI`
  (overview, force, stimulus and parameter plots, selection of ranges and single contractions, overlay, trend over
  several files, reference beat, EP recording, export of plots and data).
- Parameters of every single contraction (amplitude, diastolic force, dF/dt, rise time, TTP90, TTR50/90, CD50/90,
  AUC, intervals, stimulus assignment, extra and missed beats), automatic detection threshold.
- Rocker filter: removal of the periodic rocker artifact.
- Reference beat: comparison of every contraction with a reference (deviation, correlation, parameters relative to the
  reference).
- EP recordings (LabChart `.mat`): alignment to the `.mdd` stimuli incl. clock drift; AP parameters per contraction
  (dV/dt max, RMP, V_max, APD25/50/90).
- Python version (`py/`, package `myodish_analysis`, commands `mda`, `mda-gui`, `mda-test`): same functions and
  results (compared with MATLAB R2026a on the 9 example recordings and synthetic signals).
- Self tests: `mda_test` (MATLAB), `mda-test` and `pytest` (Python).
- Example recordings (`examples/`, anonymized): human ventricle and atrium, rabbit, pig and rat ventricle; force-frequency,
  post-rest potentiation, isoprenaline, stimulation threshold and rocker speed protocols; a sharp-electrode recording.
- `py/tools/anonymize_recording.py`: anonymize a recording (dates, paths, file names, initials) before sharing it.

### Changed
- Renamed from MyoDishContractionTool: `MyoDishContractions` → `MyoDishAnalysis`, `MyoDishContractionsGUI` →
  `MyoDishAnalysisGUI`, `mdct_*` → `mda_*`. Saved reference beats (`.mat`) and exported result files remain usable.
- License: GPL-3.0-or-later with additional terms (see `README.md`).
