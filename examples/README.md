# Example recordings

Anonymized MyoDish recordings of living myocardial slices for trying out MyoDishAnalysis, for the documentation and for
the automatic tests (comparison of the Python and the MATLAB version, `py/tests/`). Every recording consists of the data
file (`.mdd`) and the log file of the MyoDish software (`_log.log`), plus a file with labels per channel
(`_labels.csv`, loaded automatically by the GUI). Example 8 also contains the LabChart export (`.mat`) of a sharp-electrode
recording made in parallel.

| file | species, tissue | day in culture | duration | channels | protocol | shows |
|---|---|---|---|---|---|---|
| `example1_rabbitVentricle` | rabbit, ventricle | 8 | 14 min | 8 | rocker speed test (rocker 0 and 30–90 rpm, with stops), 1 Hz | rocker artifact and `rockerFilter`; 2022 log format |
| `example2_rabbitVentricle` | rabbit, ventricle | 8 | 12 min | 8 (contractions in 3, 5, 7) | pulse duration test (12 steps), stimulation threshold 50 → 10 mA | stimulus currents, channels without contractions |
| `example3_humanVentricle` | human, ventricle | 11 | 15 min | 8 | force-frequency relation 0.2–4 Hz, 60 beats per rate, rocker stopped | parameters vs. rate, reference beat |
| `example4_humanAtrium` | human, right atrium | 8 | 18 min | 8 | 100 nM isoprenaline in channels 3, 4, 6, 8 (62–154 s); rate protocol 30–300 bpm from 872 s | drug response with control channels, ranges with labels, extra beats |
| `example5_pigVentricle` | pig, ventricle | 2 | 18 min | 8 | force-frequency relation 0.2–4 Hz | 2022 log format |
| `example6_ratVentricle` | rat, ventricle | 2 | 30 min | 8 | rocker speed test at 30 and 60 bpm (0–745 s); force-frequency relation 0.2–4 Hz (1025–1794 s) | rat contractions; rocker filter |
| `example7_pigVentricle` | pig, ventricle | 2 | 5 min | 8 | post-rest potentiation | rest pauses |
| `example8_rabbitVentricle_EP` | rabbit, ventricle | 0 (fresh) | 3.4 min | 1 | refractory period protocol (20 steps, 800 → 250 ms), 300 µM lidocaine, 37 °C; sharp-electrode recording (LabChart, 10 kHz) | EP alignment, AP parameters per contraction (`mda_readEPRecording`, `mda_analyzeAP`) |
| `example9_ratVentricle` | rat, ventricle | 5 | 11 min | 1 | 0.5 Hz, lidocaine 0 → 100 µM | single-channel file, sensor calibration 3000 |

Example 1: channels 1–4 in medium without BSA (column `treatment` of the labels).

## Use
MATLAB (in the folder `MyoDishAnalysis`):
```matlab
MyoDishAnalysisGUI('examples/example3_humanVentricle.mdd')
[c, s] = MyoDishAnalysis('examples/example4_humanAtrium.mdd', [2 3 6 8], [0 780], [60 870], 'labels', {'baseline','iso'});
[c, s, info] = MyoDishAnalysis('examples/example1_rabbitVentricle.mdd', 5, 0, inf, 'rockerFilter', true);
```
Python:
```bash
mda-gui examples/example3_humanVentricle.mdd
mda examples/example4_humanAtrium.mdd -c 2 3 6 8 --from 0 780 --to 60 870 --labels baseline iso
```
More: `example_MyoDishAnalysis.m` (MATLAB).

## Anonymization
The data files (`.mdd`) are unchanged. In the log files, all dates were shifted by a whole number of days so that each
recording starts on 1 January 2000 (time of day and all time differences are kept; the LabChart block time of example 8
was shifted by the same number of days). File names, folder paths, the software build number and date, and initials in
comments and protocol names were removed. MATLAB and Python give the same results for the anonymized and the original
files (all parameters identical; clock times shifted). To anonymize your own recordings before sharing them, e.g. with a
bug report: `python py/tools/anonymize_recording.py <file.mdd> <new_name> --initials AB,CD --show`.

## License
The example recordings may be used, shared and adapted under the terms of the
[Creative Commons Attribution 4.0 International license (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/);
please cite MyoDishAnalysis (see `CITATION.cff`).
