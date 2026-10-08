# Changelog

All notable changes. Versions: `MAJOR.MINOR.PATCH` (pre-releases `-beta.N`; Python package: `1.0.0bN`).
MATLAB and Python versions have the same version number and give the same results.

## [Unreleased]
### Added
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

### Changed
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
