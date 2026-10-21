# Changelog

All notable changes. Versions: `MAJOR.MINOR.PATCH` (pre-releases `-beta.N`; Python package: `1.0.0bN`).
MATLAB and Python versions have the same version number and give the same results.

## [Unreleased]
### Fixed
- **Current reached (status bit 9) assigned to the right pulse.** The controller writes the report of a pulse when the
  pulse starts, and the result ("current not reached") only becomes known at its end; bit 9 of a pulse is therefore
  the result of the previous base pulse of the same channel (firmware V18G–V19C, confirmed by the firmware source and
  3,285 of 3,285 pulse pairs). `mda_readMdd` / `read_mdd` now give each base pulse the bit 9 of the next base pulse of
  its channel (searched up to 600 s beyond the window read); `stim.currentReached` and the column `currentReached`
  of the pulse table are 1 / 0 / NaN (unknown: the last pulse of a channel in the file; a base pulse followed by an
  extra pulse of its channel when the next base pulse has bit 9, since the firmware ORs the failure of an extra pulse
  into that bit; extra pulses, external trigger pulses) instead of true / false, and `currentReached_percent` leaves the unknown pulses out. This changes
  `currentReached_percent` of threshold protocols (before: the first pulse of every current step carried the result
  of the last pulse of the step before) and `currentReached` in all pulse tables; recordings analysed before need to
  be analysed again for these columns.
- **MATLAB `mda_timepoints`, `mda_poolTimepoints`: relative results folder** (e.g. `mda_timepoints('results', ...)`)
  was resolved against the folder MATLAB was started in (Java), not the current folder: *no mda_index.csv in ...* or
  no analyses found after `cd`. Relative paths now refer to the current folder (`pwd`), as in Python.
- **Python watcher with several workers, new results folder: a recording failed with `FileNotFoundError`** (1 of
  10,565 recordings in a complete run): when two recordings of the same experiment started at the same time, one
  worker removed the still empty experiment folder (clean-up of results in the other folder layout) while the other
  was creating its results folder in it. Empty folders are now removed only if results of the recording were deleted
  there, and the results folder is created again after a short pause if a parent folder disappeared. Rerun failed
  recordings with `--retry-errors`.
- **MATLAB: stimulation protocols of a recording not analysed** when one protocol had no contraction in a channel
  (its grouped summary was empty and had fewer columns: *All tables being vertically concatenated must have the same
  number of variables*; the watcher listed `protocols: MATLAB:table:vertcat:SizeMismatch` and wrote no
  `_protocols` results). Empty summaries are now left out, as in Python (found in a recording of 2026 with 4
  threshold protocols).
- **Watcher: empty files** (0 bytes, mostly failed copies: 258 of 17,237 recordings of 2020–2026) were analysed and
  listed as `ok` without data; empty log files (6 recordings with data) were read as if the log file had no entries
  (sampling rate, calibration and protocols assumed). Now: empty file → `incomplete`, empty log file → `noLog`, until
  the file changes.
- **Files of the first MyoDish version** (software 1.0.x, 8 force channels at 500 Hz, no status channel) whose
  recording duration in the log file does not fit the file size were read as 9-channel files (no channel passed the
  status-channel test, 9 was assumed): the 9th column of the misread data gave pseudo-pulses at 60–80 Hz (report flag
  F) and wrong force values. Now: no status channel found and `nChannels` 8 or 500 Hz in the log file → 8 channels
  without status channel, analysed as unpaced (contractions only; stimulus-related parameters NaN, no extra or missed
  beats). In the recordings of 2020 and 2021, 54 recordings (52 of setups 1 and 2) were affected; the other 456
  recordings of this kind were already read as 8-channel files.
- **`py/tools/anonymize_recording.py`: dates not shifted in logs of software before 2.0.7717** (2020/21). These
  logs write time stamps without leading zeros (`1999 12 24 8:48:22:399`), which the tool did not recognize. In 442 of
  16,205 lab logs no date was shifted at all, in 184 some lines kept the real date. Now these time stamps are shifted
  too and written in the same form. Also anonymized now:
  - lines broken by an interrupted write (rests of paths with folder names, the own file name, dates, time stamps of
    glued lines; 144 logs), with the rest of a line before a glued time stamp replaced by `(cut)`;
  - `ProgramVersion` lines (2021–2022), which kept the build number.
  The final check also stops if a date of the recording is left in the output (`1999 12 24`, `24.12.1999`,
  `24/Dec/1999`, `1999-12-24`).
- **`py/tools/anonymize_recording.py`: clock time of anonymized logs with 12-hour time stamps** (software
  2.0.7713–2.0.7970). With the build number removed, MyoDishAnalysis no longer recognized every such log (3 of 1,902
  lab logs: start 12 h off). The copy of the `.mdd` file also had the time of copying, which decides AM/PM in logs
  that cannot tell (64 of 1,880 such logs on the hard disk). Now these builds are written as `2.0.7717`, and the copy
  keeps the time of last change of the recording, shifted by the same number of days.
- **RP results `refPeriodNoResponse_ms` / `refPeriodNoPeak_ms`: transition rule relaxed.** The transition is the
  first interval (from long to short) below the level that stays below it at the next shorter interval *or* in the
  median of this and all shorter intervals; before, a single value just above the level at the shortest interval
  (5.3 % against a noise level of 4.6 %) made the result NaN ("not reached") although the two intervals before were
  below it (rat slice: now 132 ms; example 8 unchanged).
- **S2 groups of refractory-period protocols** (`mda_groupBeats` / `group_beats`, `S2interval`; found with a lab
  recording of a rat slice, RP schedule 250 → 120 ms in 10-ms steps): 1) the last stimulus of a channel at the basic
  S1 interval after a post-S2 stimulus (1-Hz pacing resumed after the last S1-S2 pair, file or range ending there)
  was an S2 of its own (`S2 1000 ms`; no next interval to show that it is not premature; 16 of 1,510 RP ranges of
  human recordings of 2024–2025): now an S1. 2) S2 intervals within 7.5 ms were one group, but the 400-Hz status
  channel records a pulse on a 2.5-ms grid, so 10-ms steps of a schedule could fall into one group (127.5 and
  120 ms → `S2 124 ms`, 2 stimuli): now 5 ms (the same interval ±2.5 ms stays one group). Group labels and the
  tested intervals of the RP results (`S2shortest_ms`, `refPeriod...`) in 0.5-ms steps (`S2 207.5 ms` instead of
  `S2 207 ms` / `S2 208 ms`, which depended on rounding). RP results change by at most 0.5 ms.

### Added
- **MATLAB GUI: guarded callbacks and an error log.** Every callback (buttons, lists, mouse, keys) and the plotting
  after the detection run guarded: an error is shown in the status line in red (`Error in …: …`) instead of only in
  the command window, and appended with version, file, window, channel and stack to
  `<tempdir>/MyoDishAnalysisGUI_errors.log` (an empty window after *Load* that needed a restart could not be
  reproduced; the log tells what went wrong next time). `MDA_DEBUG` also prints the report.
- **Channels at half the recording rate: half-rate interpolation** (option `halfRateInterpolation`, default on;
  `S.halfRateInterpolated`): where the inferred sensor rate is unambiguously samplingRate / 2 (new boards at 200 Hz in
  a 400-Hz recording, see "Sensor rate" below), the repeated raw values are replaced by a linear interpolation between
  the first samples of each pair (the measurement times) before the averaging of the raw samples, so that the timing of
  such channels no longer depends on the phase of the pairs (before: up to 2.5 ms). Runs of more than 4 identical
  values (held values, chamber out) stay. Other channels unchanged.
- **Red flag `R` (controller restart suspected)** in the analysis report, the GUI flag line and the watcher's flag
  tables: the warning `Controller restart suspected: no data for … s, …` of the control software 2.2 (F-90) in the
  events table of the recording (`mda_report('flags', ..., E)` / `report_flags(..., events=E)`); after it the
  controller may have run with its power-on settings instead of those in the log. All channels of the recording.
- **Option `lockedThreshold`** (default 0 = off; `lockedNoiseRel` 3): paced channels, auto threshold: a peak below
  the threshold is also a contraction if it is locked to a stimulus, the rocker is at rest and it is ≥ this fraction of
  the typical amplitude and ≥ 3 × the median rise before the stimuli. With 0.05 the small S2 response (29 µN, 9 % of
  S1) of a rat slice at 150 ms is counted and the 2:1 alternans of example 4 (human atrium, 4–5 Hz) becomes 1:1 (96
  small beats); the other examples change by 0–19 contractions. `C.lockedLowPeaks`; advanced settings of the GUI.
- **Group summary of RP protocols: `S2response_pct` and `separatePeak_percent`** for the S2 groups (median S2
  response in % of the S1 amplitude from the template subtraction, % of the S2 with a separate peak), so that an S2
  response too small for the detection threshold is visible in the group table (columns after
  `currentReached_percent`, NaN for the other groups and protocols; `mda_protocolResults` second output `G2`).
- **GUI: column `median`** in the parameter table (and in the copied summary) next to mean, SD and n: the median of
  the selected contractions is less affected by post-rest or partly refractory contractions (a user's request).
- **Sensor rate per channel, inferred** (summary columns `sensorRate_inferred`, `repeatedSamples_percent`;
  `S.sensorRate`, `S.repeatedSamples_percent` of `mda_readMdd` / `read_mdd`). The new sensor boards measure at 200 Hz
  in a 400-Hz recording, so every value appears twice; the log does not say which board a channel has. MDA infers
  the rate from the share of repeated raw values (about 50 % against 1–8 % for the old boards in lab recordings of
  2026-10). Timing parameters of such channels have a resolution of 5 ms. No other results change.
- **Protocol keywords `post pause` and `pause potentiation`** (type PRP, e.g. `Start post-pause-potentiation` of an
  older standard schedule that several labs use). Before, such a protocol was not recognized at all (no keyword).
  None of the 16,488 recordings of 2020–2026 on the lab disk has such a comment.
- **Structured events of the MyoDish control software** (builds from 2026-10, release 2.2): `mda_logEntries(logFile,
  'events')` (Python `log_events`) reads the log lines whose value is one JSON object (codes system, slice,
  protocolRun, scheduleRun, doc, chamber, rigor, backup): time in the file, dataLogTime as written (`t_logged`),
  channel, code, event, actionId, by, waiting and all fields by name; lines cut off by a crash are counted and left
  out. **Waiting lines** (logged while no main recording ran and written into the next main log right before its
  `LogFile created/opened`): the lines after the last `LogFile closed` of this log (or from `MyodishControlSoftware
  opened`, a new run of the program, e.g. after a crash) up to its next opening, `LogFile2`/`LogFile3` (second and
  rocker stop recording) included, only lines about this log; their time in the file is that of the opening (their
  dataLogTime is the frozen counter of the last main recording, often of another file). With the first rule, a file
  first written as second recording and then continued as main recording lost its first protocol (found by the
  developer of the control software in its example logs). **`mda_protocols` /
  `find_protocols` take the protocols from the `protocolRun` events** where a log has them (start paired with end or
  abort by run, exact times, type and name of the start, also for protocols started by hand; notes for aborted
  protocols, protocols started before the recording or the file, and protocols without end); the automatic comments
  `start/end <TYPE> protocol` written right before them are not read again (each paired with the next `protocolRun`
  line of its kind and type, also when the two lines got different times), and comment protocols of the same type
  that overlap one are dropped. New protocol types `doseResponse`, `substance`, `stretch`, `other` (groupBy none); names with dose
  response or the word DRC are `doseResponse` (tested first, as the control software; without end comment treated like
  `unknown`). Older recordings unchanged. Tested with a synthetic log in the format of the control software (dev build
  2.1.9787.20360) and with 26 example event logs of its replay test (simulated device; anonymized in
  `py/tests/event_logs_2_2`); no lab recording with these lines exists yet.
- **`py/tools/anonymize_recording.py`: the fields of the newer events of the control software** (slice, user,
  protocolRun, scheduleRun, doc, backup, dataFolder, chamber, rigor): persons (`initials`, `user`, `owner`,
  `removedBy`, `previous` and the full `name` of the event user) → `P1`, …; `sampleId` → `S1`, … and the sample inside
  `sliceId` (as in `_labels.csv`); `chamberId` → `chamber1`, …; folders (`folder`, `target`, `previousTarget`, `to`) →
  `folder1`, …; `scheduleFile`, `parentFile`, `preset` → file names, with the `--initials` rule `_AB` → `_P1` (also in
  `file` and `path`); times `cultureStart`, `installTime`, `removeTime`, `time` shifted by the same number of days;
  protocol names and free texts (`comment`, `text`, `destination`, `reason` of `slice_remove` and `backup_failed`) like
  comments; `client` (sync program) and `evidence` replaced. The final check also searches for the dates of the shifted
  times, `--show` lists the free texts and slice labels, and network paths are reduced to file names
  like drive paths.
- **`mda_timepoints`** (Python `timepoints`, `mda-timepoints`; new files `mda_timepoints.m`, `mda_testTimepoints.m`,
  `py/src/myodish_analysis/timepoints.py`, `py/tests/test_timepoints.py`): contraction parameters in windows before
  and after a treatment from the results of the watcher, e.g. `mda_timepoints(res, 'Mava100', 'Setup1_ABC000101',
  [1 3 5], '2000-01-01 15:20', [-10 10 60 240 1440])`. Windows start exactly at time + offset (minutes, required) and
  last `seconds` (default 120); channels and times as vectors or matrices (one row per setup, one time per setup or
  channel); median and quartiles of the included contractions, % of the baseline window, notes (protocols, chamber
  out, comments, missing contractions, other slice, pending). Output: struct and
  `<experiment>/timepoints/<label>_<time>/` (xlsx with summary, matrix, 1-min course, single contractions, info;
  images `.png` and `.fig` / `.svg`). MATLAB and Python identical (146 windows of 73 channels of 9 human
  experiments: max. relative difference 7e-16). **Average beats** per window from the recordings (absolute in µN with
  the diastolic force, normalized to the baseline amplitude, normalized to the own amplitude with the diastolic change
  against the baseline kept; each ± SE; mean ± SE of the channels; one 16:9 slide per channel with a table of the
  values; options `'averageBeats'`, `'rawFolder'`), mean values per parameter, and an **alternans** note (two
  amplitude groups; average beats of the small and the large beats): in a human slice under omecamtiv mecarbil 3 µM the
  median amplitude (+36 %) overestimated the mean (+8 %) because the beats alternated between ~1.7 and ~3.7 mN.
- **`mda_timepoints` (2026-10-16)**: main value per window and parameter is the **mean** of the included contractions
  (before: the median), followed by its normalized value; then `_SD`, `_SEM`, `_median`, `_q25`, `_q75` and the
  average-beat columns at the end of the summary; `pctBaseline` and the matrix from the means. New default parameters
  `CD90`, `dFdtMax`, `dFdtMin` (in mN/s) and `AUC`. Diastolic force normalized as absolute change against the
  baseline (`diastolicForce_delta`, µN; % of a baseline near 0 or negative was meaningless, e.g. −593 → +972 µN gave
  −164 %, and % of the amplitude explodes with small amplitudes). Windows without contractions although recorded:
  amplitude, AUC, dF/dt and beatsPerMinute 0, times NaN, diastolic force from the signal (median of the filtered force
  − zero force). All images absolute and normalized (`_timepoints_abs/_norm`, `_course_abs/_norm`, `_averageBeats_abs/_norm`,
  `_averageBeatsMean_abs/_norm`; earlier names are removed), black line = mean ± SEM of the channels (also in the
  course). Options `'sampleID'` and `'group'` (columns in `rows` and `summary`).
- **`mda_poolTimepoints`** (Python `pool_timepoints`, `mda-pool-timepoints`; new file `mda_poolTimepoints.m`): analyses
  of `mda_timepoints` of several experiments, samples and days pooled by treatment: workbook with one row per slice and
  time point (treatment, substance, concentration, group, sampleID, sliceID, timePoint and all summary columns; for
  statistics, e.g. `BarsWithErrorsFromList` with the sample as random effect), samples, treatments (slices and samples),
  course, average beats; values against the controls of the same time point (`_vsControl`: pctBaseline in % of the
  controls, diastolic Δ − Δ of the controls; controls of the same sample, otherwise all); images per treatment and all
  treatments side by side (`_abs`, `_norm`, `_vsControl`).
- **`mda_poolTimepoints` (2026-10-18)**: option **`'exclude'`** (Python `exclude=`, `mda-pool-timepoints --exclude
  ID[:CH[:FROM[:REASON]]]`): table or cell array with the columns id (sampleID, series or sliceID), channel (empty = all),
  from (minutes after the treatment; empty = the whole slice) and reason; excluded windows are left out of all sheets,
  images and statistics and listed in the sheet `excluded`, treatments without slices are dropped with a note. Column
  **`qc`** per window (codes from the notes: arrhythmic, capture, noContractions, alternans, irregular, protocol,
  signal, otherSlice, comment, pending) for the decision what to exclude. Sheet **`statistics`** per treatment, time
  point and parameter: mean and SEM of the slices, the same of the controls, difference, paired difference of the
  samples with treatment and control, and a linear mixed model y ~ treatment + (1 | sample) (REML, own implementation
  in MATLAB and Python without toolboxes; validated against statsmodels MixedLM: estimate 18.2215, SE 3.8915, variance
  ratio 4.2369) only if both groups have at least 3 samples, otherwise descriptive only. Degrees of freedom n − 2 (as
  `fitlme` 'Residual'): exploratory and not corrected for multiple comparisons; for a publication confirm with a
  dedicated tool (e.g. lme4/lmerTest with Satterthwaite degrees of freedom). Also written: `<name>_figure_norm` (pdf,
  svg, png) and `<name>_prism.xlsx`.
- **`mda_plotTimepoints`** (Python `plot_timepoints`, `prism_tables`; new file `mda_plotTimepoints.m`): figure for a
  manuscript from a pool (struct or workbook): one panel per parameter (default amplitude, diastolicForce, TTP90,
  TTR90), x = time after the treatment, per treatment mean ± SEM of the slices and thin lines of the single slices,
  legend *treatment (n = slices/samples)*, controls black, other treatments in the colour-blind safe Okabe-Ito colours,
  Arial 7 pt, panel size in mm, files `.pdf` / `.svg` / `.png` (300 dpi); modes `'norm'`, `'abs'`, `'vsControl'`.
  `mda_plotTimepoints('prism', PT)`: tables for GraphPad Prism (one row per time point, one column per slice, header
  `treatment|sample slice`).
- **`mda_study`** (Python `study`, `mda-study`; new files `mda_study.m`, `py/src/myodish_analysis/study.py`): time
  points of a whole study from one design table (xlsx with the sheets slices and settings, or csv; one row per slice:
  series, channel, treatment, time, sampleID, group, exclude, excludeReason) and a few settings (offsets, seconds,
  baseline, t0, control, order, parameters, ...): one `mda_timepoints` analysis per treatment in `<study>/analyses/`,
  the pool with the exclusions in the study folder (default `<results>/studies/<name>/`), a copy of the design and
  `<name>_methods.txt` (methods text: version, windows, t0, paced beats only, normalization, groups with slices and
  samples, exclusions, statistics). `mda_study('template', file)` / `study_template(file)` writes an empty design table
  with an example row.
- **`mda_timepoints`: option `'t0'`** (Python `t0=`, `--t0`): `'given'` (default) or `'chamberIn'`: per channel the end
  of the chamber-out period nearest to the given time (periods ending within ± `'t0Window'` minutes, default 90), i.e.
  the time the chamber with the treatment was put back; comments are often written minutes before or up to an hour
  after the treatment. Notes per window, columns `timeGiven` and `t0`. Option **`'outputFolder'`** (Python
  `output_folder=`): files in `<outputFolder>/<experiment>/<label>_<time>/` instead of the results folder (used by
  `mda_study`).
- **Watcher: wildcard patterns** (options `'include'`, `'exclude'`; Python `--include`, `--exclude`): e.g. `'ABC00*'`
  (all folders starting with ABC00) or `'*schedule*'` (schedule files); a pattern without `/` is matched against every
  folder name and the file name, with `/` against the relative path. `'caseSensitive'` (`--case-sensitive`, default
  false) applies to them and to `'filter'` (before: `'filter'` always ignored case).

- **Watcher: incomplete copies** (status `incomplete`): a recording whose file is shorter than its recording in the
  log file (`Recording started` → `stopped`) by more than 10 s and more than 2 % (`'incompleteTolerance'`,
  `--incomplete-tolerance`; relative because the sample clocks deviate from the computer clock by up to about 0.6 %,
  in one setup by 2 %, i.e. up to 90 s in 24 h; an absolute limit of 10 s alone would hold back 1,364 of 15,748
  recordings), or whose file time is before 1990 (robocopy marks unfinished copies with 1980), is not analysed and is
  checked again in the next pass; after `'incompleteAfterHours'` (30 h) without change it is analysed with a note in
  the message. Tested on the 16,463 recordings with log file of 2020–2026: 9 exceed both limits (6 empty files, 1
  with 1 % of its data, 1 short by 2.8 %, 1 of one setup of 2021 with a clock deviation of 1.1–2.1 %); with 1 %: 22
  (14 of that setup).
- **Watcher: parallel recordings** (option `'parallel'`, `--parallel`; default `'skip'`, status `parallel`): a
  recording that the log file of another recording in the same folder lists as `started parallel recording` (same
  duration) is not analysed if that main file is selected in the same pass: its data are in the main file and its
  protocols in the main file's `_protocols_*` results; the index names the main file and the time window. Parallel
  recordings whose main file is not selected (e.g. `'include','*schedule*'`) or missing, and all of them with
  `'analyse'`, are analysed and marked in the message (`parallel recording of <main file> (...): analysed (...)`).
  The slice register ignores parallel recordings whose main file has results in the same folder (no contraction or
  stimulus counted twice in the time course of a slice). In 2020–2026: 6,674 of 16,463 recordings (5,063 schedule
  files, 687 snapshots).
- **Watcher: flags table** `mda_flags.csv` (with the PDF report): flags of the analysis report per recording and
  channel, updated after every pass. `MyoDishAnalysisWatch('flags', res, compute)` / `flags_table(res, compute)`
  return the flags of the current analyses and compute missing ones from the result files.
- **GUI: results browser** (button **Results ...**, MATLAB and Python): recordings and channels of a results folder
  of the watcher with the flags of the analysis report (colours of the report), list all / with flags / red flags /
  not analysed, search; double-click opens the channel with the settings of its analysis (red flags: at the window of
  the flags, otherwise the first 120 s); **Compute flags** for results of older watcher versions. The last folder is
  remembered.
- **GUI: parallel recordings**: button **Main file** next to the file name opens the main recording at the window
  shown (same channel); the status line names the main file and the time window.
- **GUI: flags line** above the table: flags of the analysis report for the analysed range of the channel.
- **GUI: changed advanced settings at a glance** (MATLAB and Python): the button **Advanced ...** shows the number of
  advanced settings that differ from the defaults in red, e.g. *Advanced (3 changed)*, shortened to the width of the
  button (*Advanced (3 chgd)*, *Adv. (3 chgd)*, *Adv. (3)*); its tooltip lists them with their defaults.
- **GUI: several analysed ranges** (MATLAB and Python): shift + drag in the force plot adds a range (overlapping
  ranges are merged); contractions and stimuli of all ranges are pooled; exports with one summary row per range plus
  *all ranges* (column `range` in the contractions and pulses); Open ... restores the ranges.
- **GUI: rocker stops side by side** (MATLAB and Python; right click in the force plot, with *only contractions with
  rocker at rest*): every rocker stop (≥ 1 s) of the range shown in the overview is read and shown side by side
  (dashed lines = time gaps, time axis in file time), selected and analysed together; exports in file time, Open ...
  shows the same stops again. Limits: 4 h of data, 2000 stops.
- **GUI: Zoom to the selection** (right click in the force plot) and **Select all** (right click in the overview:
  loads the range shown, at most 4 h).
- **GUI: unit of the overview time axis** bottom left (e.g. *(h:mm)*); from 2 days *d h:mm*, whole days *n d*.
- **`'pooled'`** (`MyoDishAnalysis`, Python `pooled=True` / `--pooled`): with several ranges also one summary row per
  channel over all ranges (`range` = *all ranges*). `mda_summarize` / `summarize` accept several ranges (rows
  `[from to]`). `mda_readMdd(..., 'overview')` / `read_overview` return `rockerRest` (rocker-at-rest intervals in
  seconds, sample resolution).

- **Watcher: result folders per setup and recording** (`'folders'`, default `'series'`; Python `folders`,
  `--folders`): `<experiment>/<series>/<nn>/` per recording with a number in the name (Setup1_ABC000101_2.mdd →
  `ABC000101/Setup1_ABC000101/02/`, with its parallel recordings), `<experiment>/<name>/` otherwise; in the folder of
  the setup the course images and their data, in the folder of the experiment the overview image, the PDF report and
  the slice register. `'flat'`: all files of an experiment in one folder as before. All readers take both layouts;
  `MyoDishAnalysisWatch('reorganize', res)` / `mda-watch RESULTS --reorganize` moves earlier results (and back with
  `'folders','flat'`). `MyoDishAnalysisWatch('resultFolder', res, rel)` / `results_of(res, rel)`;
  `mda_sliceRegister('series', name)` / `series_of(name)`, `mda_sliceRegister('resultFolder', rel, folders)` /
  `result_folder(rel, folders)`.
- **Watcher: overview image per experiment** `<experiment>_overview.png`: setups x channels with the amplitude over
  the whole time course, the last 24 h, slice changes, the status of the last slice (colour), last amplitude, change
  in the last 24 h, % of the maximum and a red frame for channels with red flags in any recording (also of earlier
  passes). `mda_report('experiment', png, D)` / `report.experiment_image(png, D)`.
- **Watcher: course image per setup and channel** `<series>/<series>_ch<c>.png`: per parameter the whole time course
  since the start of the setup (all slices, slice changes, the last 24 h shaded, recordings with red flags as red
  bars, dates with the day in culture) and the last 24 h (10-min line, protocols, numbered comments); status of the
  last slice in the subtitle. Data in `<series>/<series>_trends.xlsx` (sheets course, last24h, comments, slices).
  `mda_report('course', png, D)`, `mda_report('courseData', D)` / `report.course_image`, `report.course_data`.
- **Watcher: trend images** (`'trends'`, default true; Python `trends`, `--no-trends`): `<name>_ch<c>.png` per
  recording and channel (flat layout: `trends/`; one panel per parameter of `'trendParameters'`, default amplitude, diastolicForce, TTP90,
  TTR90; dots = median per minute (overview), line = median per 10 min; stimulation protocols, periods without
  signal, comments of the log file with a list, in protocols only the comments at their start and end; labels of
  the channel in the title; change from the first to the last 2 h). PNG, 150 dpi. The data
  of the images in the sheets `trends` (one row per channel and 1-min window: the plotted values, `bin_from` of the
  line) and `trendComments` (the numbered comments) of `<name>.xlsx`; `mda_report('trendData', D)` /
  `report.trend_data(D)`.
  `MyoDishAnalysisWatch('trends', resultsFolder, ...)` / `mda-watch RESULTS --trends-only` makes them again from the
  result files. `mda_report('trend', png, D)` / `report.trend_image(png, D)`; `mda_sliceRegister(..., 'trends', true)`.
- **`mda_writeResults` / `write_results`**: `'csvTables'` (tables of an .xlsx written as `<name>_<table>.csv`),
  `'compress'` (as `.csv.gz`), `'sheets'` (further sheets); tables with more rows than Excel allows are always
  written as `.csv`. `mda_readResults` / `read_results` read the contractions of an `.xlsx` without the sheet from
  `<name>_contractions.csv(.gz)`.
- **`py/tools/anonymize_recording.py`: structured log lines of the MyoDish software 2.1** (one JSON object per line
  beside the old text lines; tests in `py/tests/test_mda.py`). They are anonymized by field name in every event:
  `pc` → `PC`, `winUser` → `user`, `pnp` → `USB serial device`, `software` → major.minor, `controllerId` and
  `ftdiSerial` → `controller1`, `controller2`, …, `by` (initials) → `P1`, `P2`, … (`auto` and null kept), `file`,
  `previousFile` and `path` → file name with the new name. All other fields, and numbers exactly as written, are kept.
  Each line is written back as one line of pure ASCII JSON (`;` as `\u003b`). Lines that cannot be read (cut off
  after a crash) are kept unchanged and reported. `<name>_labels.csv` → `<new_name>_labels.csv` with the same
  pseudonyms: sampleID → `S1`, …, the sample ID inside sliceID too, analyst and owner as persons, cultureStart shifted
  by the same number of days, comment as the comments of the log. `--map FILE.json` gives all recordings of a study
  the same pseudonyms (the map holds the original values: do not share it). **Final check:** the output files are
  searched for every original value that was replaced and for the `--initials`. If one is left, e.g. in a free-text
  comment, the output files are deleted and the tool stops with an error naming the line. Old text lines are treated
  as before, except for the `--initials`: they are now replaced by the same pseudonyms instead of removed
  (`AB: comment` → `P1: comment`, `_AB` in protocol names → `_P1`). MATLAB and Python give the same results for the
  original and the anonymized recording (all parameters identical; clock times shifted by the same number of days).
  Still to come: person, sample and free-text fields of
  later events (`slice`, `doc`, `protocolRun`, `scheduleRun`) and ISO times inside structured lines.

### Changed
- **GUI, Protocols ...**: protocols are preselected if they have a stimulation quantity (groupBy not `none`; before:
  type not `other` / `unknown`), so that the new types without grouping are not preselected.
- **`mda_timepoints`: paced windows use the stimulated contractions only** (2026-10-18): when a window contains
  stimulated or extra beats, spontaneous and extra beats are left out of the values; note **`arrhythmic: n extra beats
  (x % of the contractions)`** from 5 % extra beats (column `qc` of the pool: arrhythmic). Before, extra beats of an
  arrhythmic slice were averaged with the paced beats.
- **`mda_timepoints` / `mda_poolTimepoints`: mean of the channels in the course images** as two lines: solid = only
  where all channels have values, dashed = gaps of up to 3 h interpolated per channel; SEM bands lighter (alpha 0.12)
  and interrupted at gaps.
- **Report flag F** (stimulus frequency > 10 Hz, red): description only; the contractions of such ranges are analysed
  as usual. The pseudo-pulses at 30–100 Hz of 2022 came from old 8-channel files read as 9-channel files (see Fixed,
  files of the first MyoDish version); such rates otherwise come from real stimulation: pulse pairs or groups (CCM
  pulses as a second normal pulse 50 ms after the first, 2022, or without the extra-pulse bit), bursts (17 Hz) and
  pulse trains (13 Hz), or pulses over consecutive samples (400/500 Hz); in the complete analysis of 2020–2026: 137
  channels of 28 recordings with F.
- **Watcher: PDF report per experiment** `<experiment>/<experiment>_report.pdf` instead of one report per pass
  (`reports/mda_report_<date>_<time>.pdf`): all analysed recordings of the experiment with their flags (the
  recordings of the last pass in bold, the earlier ones from `mda_flags.csv`, so that red flags of earlier days stay
  visible), first page the overview image, trace pages for the red channels of the last pass. The txt report of the
  pass lists the PDF reports. `mda_report(..., 'image', png)`, `recs(i).new` / `write_report(..., image=png)`,
  `rec['new']`.
- **Watcher: result files** (`'resultFormat'`, default `'xlsx'`; Python `result_format`, `--result-format`): one
  `<name>.xlsx` per recording with the tables as sheets (summary, trends, trendComments, channels, gaps, events,
  parameters, info, thresholds, labels) and the large tables as `<name>_contractions.csv.gz`, `_pulses.csv.gz`, `_overview.csv.gz`;
  protocols as `<name>_protocols.xlsx` (+ `.csv.gz`). Before: one csv file per table (11–17 files per recording);
  `'resultFormat','csv'` keeps that. The GUI (Open, results browser), the flags, the PDF report and the slice
  register read both formats; recordings are not analysed again because of the format.
- **Watcher: recordings without `Recording stopped`** (status `running`) are analysed when the end of their data
  (start of the recording in the log file + duration from the file size) is `'incompleteAfterHours'` (30 h) ago
  (clock of the recording computer more than 1 h ahead or unknown: 30 h after the last change of the files); before:
  30 h after the last change of the file (a copy refreshed every hour was never analysed, an old aborted recording
  copied today waited 30 h).
- **Watcher: lock file with heartbeat**: the running watcher refreshes `mda_watch.lock` after every recording and
  during long steps (scan, slice register, report); a lock file not refreshed for 1 h (watcher crashed) is ignored by
  the next watcher. Before: ignored 12 h after its creation, so that a crashed run blocked the passes for up to 12 h.
- **Watcher options**: `'include'` / `'exclude'` are the standard way to select recordings; `'filter'` (regular
  expression, `--filter`) is listed as an advanced option (`help MyoDishAnalysisWatch`: ADVANCED OPTIONS; `mda-watch
  --help`: advanced options). `'interval'` (`--interval`; passes every h hours in a blocking loop) is no longer
  documented, but still accepted; `'schedule'` replaces it.
- **Watcher: `noLog` recordings** are no longer checked again in every pass, but analysed when the log file appears
  or changes; the index is written after every analysed recording and once at the end of the pass (before: after
  every row, also for recordings only checked); the command window counts the recordings to analyse and those to
  check again separately.
- **GUI: Open ...** (MATLAB and Python): one button for recordings and results files (before: *Open .mdd ...* /
  *Open results ...*); the folder is remembered between sessions. A recording opens with its first window (From /
  To: 0–120 s) loaded and analysed (before: only the file facts; Load had to be pressed).
- **GUI: comments in the force plot** (MATLAB and Python): numbered purple marks at the top (numbers as in the comment
  window, no overlapping numbers; pointer on a mark: its text; click: highlighted and selected in the comment window);
  selecting a row of the comment window highlights the comment in the force plot; comment window with the column #.
  Before: rotated labels, which overlapped when comments were close together.
- **GUI colors** (MATLAB and Python): accent blue `#1D72B9` for the buttons of the main action of each window (Load,
  Calculate, Analyse, OK, Apply and close), the titles and borders of the panels, the status texts (dark blue), table
  headers (Python: light blue), the stimulus pulses, the intervals and the loaded window (before: `(0, 77, 255)`);
  red, orange, green, grey and purple of the plots unchanged. Quick start GUI: new screenshot.
- **GUI: rocker state** in the force plot as a thin bar at the top (green = at rest, grey = moving) instead of a grey
  background, which overlapped with the yellow analysed range.
- **GUI: y-axis label** of the force plot no longer cut off with wide tick labels (left margin adapted to the labels).
- **GUI, Trend** (MATLAB and Python): comments of the log files as numbered markers in a strip above the plot (visible
  at any zoom, no overlapping numbers) and a list below the plot (number, time, full text); click a marker or a line
  of the list, or point at a marker, to highlight the comment. Before: rotated labels in small font at the top of the
  plot, which disappeared when zooming in y.

## [1.0.0-beta.5] – 2026-10-13
Fifth pre-release for testers (Git tag `v1.0.0-beta.5`). **Analysis results change** for contractions with a long
delay after the pulse (longer gate, diastolic window), inverted signals and protocols found in comments (below);
`gateMaxCertain = 0.15` and `invertedCheck = false` give the former stimulus assignment and force values. New summary
columns after `stimFrequency` (arrhythmic pacing).
**The watcher no longer analyses all recordings again after an update** (`'reanalyze','new'` is the default; a notice
names the recordings of another version and the command `'reanalyze','outdated'`).

### Added
- **License notices** (2026-10-11): `NOTICE` (also `py/NOTICE`, part of the Python package): copyright and the
  additional terms under GPL-3.0 section 7 (author attribution; a modified version needs a name and version number of
  its own and must say that it is modified; no promotion with the names of the author, FAU and InVitroSys; no
  trademark rights to MyoDish and InVitroSys). Every source file starts with a short notice (copyright, SPDX license
  identifier, reference to `NOTICE`), after the help text in the MATLAB files.
- **Zenodo DOI** (2026-10-11): 10.5281/zenodo.23287809 (all versions) in `CITATION.cff` and the README (badge,
  citation example with the DOI of 1.0.0-beta.4, 10.5281/zenodo.23287810).
- **Analysis report (PDF)** (2026-10-11/12; `mda_report.m`, `report.py`): which analyses should be checked, with
  traces and the commands to open them in the GUI. Flags per channel with at least 50 detected contractions:
  - check the analysis (red: the analysis may not work, or technical faults put wrong values into the data; a page
    with traces of up to 4 channels): **I** inverted signal (sensor not working properly; only beating, capture and
    rate analysed); **N** noise suspected = uncertain contractions ≥ 25 % and extra + missed beats ≥ 15 % (noise index
    = uncertain % × (extra % + missed %) / 100, listed and used for the order; unpaced channel: uncertain ≥ 25 %);
    **S** large extra beats (certain extra beats ≥ 5 % with > 3 × the paced amplitude); **D** delay pulse → onset >
    150 ms; **F** stimulus frequency > 10 Hz (see below). Uncertain contractions with regular capture (few extra and
    missed beats) are not flagged: in visual checks
    they were real contractions near the detection threshold, while uncertain contractions with many missed or extra
    beats were mostly rocker waves.
  - slice quality (yellow: possibly poor biological quality, also e.g. an effect of a treatment; the user decides):
    capture < 90 %, extra beats > 10 % (spontaneous activity), amplitude < 75 µN, amplitude change > 30 % (first →
    last range, listed with its time span, e.g. "amplitude change +660 % over 24 h"), amplitude CV > 30 %.
  - An inverted signal in less than 1 % of the contractions is given as "< 1 %".
  - Page 1: recordings × channels with capture and flag codes, legend below; page 2: list of the channels to check and
    of those with slice-quality flags, with the channel label in parentheses if given (treatment with concentration,
    otherwise sliceGroup / sampleGroup, e.g. `ch 7 (PMA 100 nM): extra beats 30 %`); then one page per recording with
    red flags (at most 8).
  - Written by the watcher after every pass (`reports/mda_report_<date>_<time>.pdf`; option `report`, flags
    `flagUncertain` (25), `flagIrregular` (15), `flagAmplitude`, `flagAmplitudeCV`, `flagDelay`, `flagMinBeats` /
    `flag_*`), by `MyoDishAnalysis` / `myodish_analysis` / `mda` with an output file (`<output>_report.pdf`; option
    `report`, `--report FILE`, `--no-report`) and by the GUI on request (menu Save / Export: report with 'All
    channels → file'). MATLAB prints the channels to check as links in the command window.
  - In the overnight runs with the first rules (extra > 10 % or uncertain > 10 % red), 14 % (2026) and 19 % (2024) of
    the channels with a slice were red, half of them for uncertain contractions only; with the final rules 11 % of
    the channels of a sample of 400 recordings of 2026 (former rules: 17 %).
- **Quick-start guides** (2026-10-11): `docs/MyoDishAnalysis_quickstart_GUI.pdf` (2 pages: first analysis in the
  GUI, export, reading the results) and `docs/MyoDishAnalysis_quickstart_watcher.pdf` (1 page). Settings guide 0.5
  (longer gate, stimToRise50, inverted signal; figure 11).
- **Watcher schedule** (2026-10-12; option `'schedule'`, `--schedule`): `'daily 10:00'`, `'weekly Sun 05:00'`
  (`'Mon,Thu 06:30'`, `'weekdays 07:00'`), `'every 2 days 10:00'`, `'every 120 min'` / `'every 6 h'` (first pass now).
  MATLAB: a timer in the background of the session (MATLAB stays free between the passes),
  `MyoDishAnalysisWatch('status')` / `MyoDishAnalysisWatch('stop')`. Python: runs until Ctrl+C. Missed passes are
  not repeated. `'interval'` (hours, blocking loop) remains.
- **GUI at a channel and time window** (2026-10-11): `MyoDishAnalysisGUI(file, 'channel', c, 'window', [from to])`,
  `mda-gui file --channel c --window from to` (recording or results file; with a results file its settings and the
  analysis window of this channel).
- **Onset gate of certain contractions** (2026-10-11; options `'gateMaxCertain'` 0.5 s, `'gateMaxCertainRel'` 0.5): a
  certain contraction (auto threshold, paced channel) without a pulse within `gateMax` (0.15 s) before its onset is
  assigned to a regular pulse up to min(0.5 s, 0.5 × the interval of the regular pulses before the onset) before the
  onset, at least `gateMax`. Two passes: all contractions with `gateMax` first, then the remaining certain ones with
  the longer gate, so that no contraction within 0.15 s of a pulse loses it. Uncertain contractions (e.g. rocker
  artifacts) keep 0.15 s. Before, a contraction with a long electromechanical delay was an extra beat and its pulse a
  missed beat (channels with a constant delay of about 0.3 s: 55–100 % extra beats, now 0–0.3 %); in 121 recordings
  of 2025/2026, about 0.08 % of the certain contractions changed from extra to stimulated. `gateMaxCertain = 0.15`
  gives the former assignment. Limitation: a stimulus-locked technical artifact 0.15–0.5 s after the pulses counts as
  stimulated if it is detected as a certain contraction.
- **Columns `t_rise50`, `stimToRise50`** (2026-10-11): time at which the upstroke crosses 50 % of the amplitude and
  its delay to the eliciting pulse. Less dependent on the shape of the foot of the upstroke than `stimToOnset`
  (interquartile range 25 / 39 ms vs 72 / 117 ms in two channels with slow or irregular upstrokes).
- **Inverted signal** (2026-10-11; options `'invertedCheck'` on, `'invertedRatio'` 2, `'invertedMinAmplitude'` 50 µN,
  `'invertedMinWidth'` 0.05 s, `'invertedSkip'` 0.02 s): in a paced channel whose stimulus-triggered median (filtered
  signal 0.02 s … min(1 s, median interval) after the pulses, baseline 60–5 ms before each pulse, at most 300 pulses)
  falls at least twice as much as it rises (fall ≥ 50 µN, ≥ 0.05 s below half the fall) and whose signal deflects
  downwards (50th − 10th percentile ≥ 2 × (90th − 50th percentile)), the force measurement is not valid (e.g. magnet of
  the MyoDish out of position). The contractions are detected in the negated signal, so that rate and capture
  (`beatType`, missed beats, `peakToPeakFrequency`, `stimFrequency`) are still analysed; all force and time parameters
  are NaN; column `invertedSignal` in the contractions and in the summary. Before, the force values of such a channel
  were meaningless (e.g. contractions detected at the relaxation).
- **Inverted signal confirmed by the detection** (2026-10-12; option `'invertedMinCapture'` 0.2): the test above is
  the suspicion; the inversion is kept only if the normal detection in the negated signal finds certain stimulated
  contractions for ≥ 20 % of the pulses of the section, otherwise the section is analysed again as it is. Rocker
  waves partly in phase with the pulses and upright contractions just before the pulses were taken for an inverted
  signal by the test alone; their contractions in the negated signal are uncertain. Check on all 1581 ranges (301
  channels) that the test alone flagged in the recordings of 2023, 2024 and 2026 (Python; MATLAB gives the same
  result in 18 of 18 ranges checked): 1069 ranges stay inverted (2023: 437 → 25); channels flagged I in the analysis
  report 103 → 90; all 10 channels checked visually as rocker waves or upright contractions lose the flag, 14 of 15
  checked visually as inverted keep it (the one lost: 60 µN deflections, < 20 % certain capture in the suspected
  section). The certain capture in the negated signal is bimodal (499 of 1581 ranges ≈ 0, 1024 ≥ 90 %, 55 in between).
  Rules tested before and not taken over: fall ≥ 0.25 × (90th − 10th percentile of the signal) removed 4 of the 15
  inverted channels and only 2 of 9 rocker channels; a lock test against sham triggers with a consistency test kept
  the upright contractions before the pulses. Sign changes within a recording occur, mostly with a large step of the
  baseline (chamber taken out and put back); the decision is made per section (chunk of ≤ 30 min).
- **Arrhythmic pacing** (2026-10-13; options `'arrhythmicChannels'`, `'arrhythmicDetection'` (on),
  `'arrhythmicMinVariability'` 0.1, `'arrhythmicMinFraction'` 0.5, `'arrhythmicWindow'` 60 s; GUI *Advanced ...* →
  *Protocols*): slices paced continuously at a high or irregular rate (e.g. right atrium at 5 Hz with a stimulus
  interval CV of 30–60 %) miss many pulses by design. A channel is marked (summary column `arrhythmicPacing`) if it is
  listed in `'arrhythmicChannels'` or if the CV of its stimulus intervals exceeds 10 % in windows that make up more
  than 50 % of the paced time (60-s windows with ≥ 6 regular pulses that do not overlap a stimulation protocol of the
  log file; analyses of the protocols: only `'arrhythmicChannels'`). New summary columns `stimVariability_percent`,
  `arrhythmicFraction`, `pacedSeconds`, `arrhythmicPacing`. The analysis report does not flag the capture (C) and the
  amplitude CV (V) of these channels and does not count their missed beats in the noise index (N); the capture is
  shown with `~`. The text report of the watcher writes `arrhythmic pacing` instead of the capture flag.
  Check on all human right-atrium recordings of 2022–2026 (1769 recordings): of 714 channels paced at 5 Hz with an
  interval CV of 35–60 %, 712 are detected (the 2 others: misread status channel, flag F; 5th percentile of the
  variable fraction 0.70); channels with regular pacing at 0.5 Hz (1813) or 1 Hz (1171): 20 detected, all paced
  arrhythmically during most of the recording or with intervals of 0.86–1.2 s (CV 10.5 %, one experiment, just above
  the threshold); daily protocol schedules of arrhythmically paced cultures (regular pacing between the protocols,
  arrhythmic pacing after them) have a variable fraction of about 0.4 and are not marked. 396 recordings of other
  tissues (2024, 2026; 3168 channels) and 41 atrial recordings of other species: no channel detected.
- **Analysis report: red flag F** (2026-10-13; watcher option `'flagStimFrequency'` / `flag_stim_frequency`, 10 Hz):
  stimulus frequency (1 / median stimulus interval of a range) above 10 Hz; such rates (30–100 Hz in 9 recordings of
  2022–2026 that are not paced arrhythmically) come from a misread status channel.

### Changed
- **Watcher: default `'reanalyze','new'`** (2026-10-12; before `'outdated'`): recordings analysed with another version
  of MyoDishAnalysis, other options or other core code keep their results; every pass shows a notice (command window /
  terminal, top of the txt and PDF reports) with their number and versions: "MyoDishAnalysis has been updated (now
  …): n recording(s) were analysed with another version (…). This may change the results or lead to
  inconsistencies with new data (see the release notes, CHANGELOG.md)." and the command that analyses them again
  (`'reanalyze','outdated'`, `--reanalyze outdated`). Before, the first pass after an update analysed every recording
  again (hours). Recordings with an analysis error are still retried after an update.
- Definition of `diastolicSignal` in the parameters table: the diastolic level of `diastolicLevel` (median before the
  pulse since 1.0.0-beta.4) instead of "the minimum before the contraction".
- **Diastolic window of delayed contractions** (2026-10-11): if the onset follows the eliciting pulse by more than
  `gateMax` (longer gate above), the median window ends 5 ms before the onset instead of before the pulse (the force
  at the pulse may still fall, e.g. incomplete relaxation, which lowered the amplitude).
- **Protocols from comments** (2026-10-11): a comment such as '... started' / 'start ...' marks a protocol only if it
  contains a protocol keyword. Known types as before (`ST` now also 'thresh', e.g. 'Start StimThresh'); without a type
  keyword but with a general one (protocol, Protokoll, programme, program, Test) the type is `unknown` (before:
  `other`); without any keyword it is no protocol. Before, e.g. a note that the software was started again, an
  experiment name or a drug application ('start Iso wash-in') were protocols, often up to the end of the file, and
  their time was missing in the watcher summaries (112 h in 11 recordings of 2025/2026). A protocol of type
  `unknown` without end comment needs regular pacing within 2 h after its start, otherwise it is dropped. A protocol
  without end comment ends at the latest when the software was restarted ('LogFile opened', programInfo 'Version',
  'Recording started:') or the connection was lost (without 'Connection re-established' within 60 s); before, e.g. a
  refractory period protocol aborted by a lost connection lasted until the next protocol or the end of the file.
- **Watcher, `compress`** (2026-10-11): gzip level 6 in Python (as MATLAB `gzip`; level 9 took 4 times longer for
  2–4 % smaller files), and the protocol contractions and pulses (`_protocols_contractions.csv`,
  `_protocols_pulses.csv`) are compressed as well (before: always .csv, 56 GB of the 195 GB of the 2025/2026 run).
- **Slice register** (2026-10-11): a comment with 'replaced' / 'exchanged' / 'getauscht' ... starts a new slice only if
  it names the slice (slice, Schnitt, tissue, S<n>C<n>) or nothing else that can be exchanged: 'medium exchange', 'setup /
  sensor board / electrode exchanged' and 'chamber replaced' (the same slice in a new chamber) do not (before: 47 of 86
  comment starts in 2025/2026 were such comments). `startReason` contains the comment once.

### Fixed
- **Protocol analysis** (2026-10-11): a protocol outside the recorded data (e.g. started after the connection was
  lost) or with an error stopped the analysis of all protocols of the file ('Empty time range'). Now every protocol is
  analysed on its own: such a protocol is not analysed (note in the info table, in the protocols table and in the
  watcher index), the others are.
- RuntimeWarning (0/0) in the S2 response of flat template beats (Python).

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
