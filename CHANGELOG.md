# Changelog

All notable changes. Versions: `MAJOR.MINOR.PATCH` (pre-releases `-beta.N`; Python package: `1.0.0bN`).
MATLAB and Python versions have the same version number and give the same results.

## [Unreleased]
### Added
- Rocker state from the log file where the status channel does not contain it: if bit 15 (rocker moving) is never
  set while the log file has rocker speeds > 0 (firmware error in some setups), or if there is no status channel, the
  state is reconstructed from the `rockerSpeed` entries (moving while rpm > 0, 0.27 s after the entry). The status
  channel bit has priority whenever it is present. Options `rockerSource` (`auto` | `status` | `log`) and
  `rockerLogDelay`. Checked on the 7 example recordings with rocker bit: the reconstructed state agrees with the bit in
  ≥ 99.96 % of the samples. Example 8 (sharp electrode) has the missing bit.

### Changed
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
