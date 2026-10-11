# Contributing to MyoDishAnalysis

Thank you for testing and improving MyoDishAnalysis.

## Report a problem or suggest a feature
- **Problems:** open an issue ("Bug report"). Please give the version (`MyoDishAnalysis` / `mda --version`, or the
  `software` row of the info sheet of an exported file), MATLAB or Python, the operating system and what you did. If
  possible, attach a short recording (`.mdd` + `_log.log`) or say how to obtain it.
- **Ideas:** open an issue ("Feature request").
- **Questions and examples of use:** use the Discussions. Please tell us in "Show and tell" where and for what you use
  MyoDishAnalysis. This helps to keep the software maintained.
- No GitHub account: e-mail to thomas.seidel@fau.de.

## Code contributions (pull requests)
- MATLAB is the reference: a change of the analysis must be made in both versions and give the same results
  (`mda_test`, `pytest`, `py/tests/compare_matlab.py`).
- By submitting a pull request you agree that your contribution is licensed under GPL-3.0-or-later with the
  additional terms in `NOTICE` and that Thomas Seidel may also distribute it under other license terms (e.g. for use
  in other software). If you do not agree, please say so in the pull request.
