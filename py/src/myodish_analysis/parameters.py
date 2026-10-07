"""Names, units and definitions of the contraction parameters. Port of mda_parameters.m.

    P = parameters()                 list of (name, unit, definition)
    P, label_names = parameters(with_labels=True)   also the names of the standard per-channel labels

Levels: upstroke = F_dia + x % of the amplitude (last crossing before the peak); relaxation = F_min,post +
(100 - x) % of (F_peak - F_min,post) (first crossing after the peak). F_dia = minimum between the previous and this
peak, F_min,post = minimum between this and the next peak. Crossing times are interpolated linearly between samples.
dF/dt = central difference of the filtered signal.

TS 2026-10-06 (port of mda_parameters.m, TS 2026-10-05)
"""
from __future__ import annotations

PARAMETERS = [
    ("amplitude", "uN", "F_peak - F_dia (force amplitude)"),
    ("diastolicForce", "uN", "diastolic force: F_dia - zero force of the channel (zero = sensor signal without load: "
     "Offset entry of the log file, or option zeroForce); NaN if unknown"),
    ("diastolicSignal", "uN", "F_dia: sensor signal at the minimum before the contraction (zero point = sensor "
     "offset; changes over time are meaningful)"),
    ("dFdtMax", "uN/s", "maximum rate of force rise (+dF/dt max), between F_dia and the peak"),
    ("dFdtMin", "uN/s", "maximum rate of relaxation (-dF/dt min, negative), between the peak and F_min,post"),
    ("riseTime10_90", "s", "rise time from 10 % to 90 % of the amplitude"),
    ("TTP90", "s", "rise time 90 % / time to peak: 10 % of the amplitude --> peak (as GetContractionParameters "
     "ttp90)"),
    ("TTR50", "s", "time from the peak to 50 % relaxation"),
    ("TTR90", "s", "time from the peak to 90 % relaxation"),
    ("CD50", "s", "contraction duration at 50 %: 50 % upstroke to 50 % relaxation (full width at half maximum)"),
    ("CD90", "s", "contraction duration at 90 %: 10 % upstroke to 90 % relaxation"),
    ("AUC", "uN*s", "area under the curve: integral of (F - F_dia) from 10 % upstroke to 90 % relaxation"),
    ("peakToPeakInterval", "s", "time from the previous contraction peak (any detected contraction) to this peak"),
    ("peakToPeakFrequency", "Hz", "1 / peakToPeakInterval"),
    ("stimInterval", "s", "set stimulation interval: stimulus of this contraction - previous stimulus pulse of the "
     "channel (extra contractions: interval of the last two stimuli before the peak); NaN without stimuli"),
    ("stimFrequency", "Hz", "1 / stimInterval (set stimulation frequency)"),
    ("refCorrelation", "", "reference beat (option referenceBeat, GUI: right click; aligned at the stimulus or the "
     "50 % upstroke, see reference_beat): Pearson correlation of the contraction with the mean reference shape; "
     "1 = same shape; NaN without reference"),
    ("refRMSDeviation_SD", "SD", "reference beat: root mean square deviation from the reference mean in units of "
     "the reference SD (overall deviation; includes amplitude differences); NaN without reference"),
    ("refRMSDeviationNorm_SD", "SD", "reference beat: as refRMSDeviation_SD, contraction and reference normalized "
     "to amplitude 1 (shape only); NaN without reference"),
    ("refMaxDeviation_SD", "SD", "reference beat: maximum deviation from the reference mean in units of the "
     "reference SD (30-ms mean; local deviations, e.g. shoulders, partial responses, delayed responses); NaN "
     "without reference"),
    ("refMaxDeviationNorm_SD", "SD", "reference beat: as refMaxDeviation_SD, contraction and reference normalized "
     "to amplitude 1 (shape only, e.g. shoulders, slow relaxation); NaN without reference"),
]

LABEL_NAMES = ["setupID", "sliceID", "species", "sampleID", "sampleGroup", "sliceGroup", "tissue", "treatment",
               "concentration", "concentrationUnit", "daysInCulture", "cultureStart", "comment", "analyst"]


def parameters(with_labels=False):
    P = [tuple(p) for p in PARAMETERS]
    if with_labels:
        return P, list(LABEL_NAMES)
    return P


def parameter_names():
    return [p[0] for p in PARAMETERS]
