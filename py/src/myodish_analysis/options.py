"""Analysis options of the MyoDishAnalysis (defaults + changes). Port of mda_options.m.

    opts = options()                          default options
    opts = options(threshold=150, ...)        defaults, changed by keyword
    opts = options(opts, rocker='stopped')    update an existing options struct (a copy is returned)

Names are the same as in the MATLAB version and not case sensitive (relthreshold = relThreshold). Unknown names raise
an error (typos are not silently ignored).

DETECTION OF CONTRACTIONS
  threshold        'auto' (default) or a number [uN]: minimum prominence of a contraction peak; myodish_analysis
                   also takes one value per channel (NaN = auto for that channel)
  relThreshold     auto threshold: at most this fraction of the typical contraction amplitude (default 0.3)
  minThreshold     auto threshold: never lower than this [uN] (default 30)
  minBeatInterval  minimum time between two contraction peaks [s] (default 0.15, i.e. up to ~6.7 Hz)

SELECTION OF CONTRACTIONS (the excluded ones stay in the table with included = False)
  beats            'all' (default) | 'stimulated' (only contractions that follow a stimulus of the channel)
  rocker           'any' (default) | 'stopped' (rocker at rest from F_dia to 90 % relaxation) | 'moving'

SIGNAL PROCESSING (defaults = GetContractionParameters / analyzeMyoDish of the Seidel lab)
  downsampling     n raw samples are combined (default 2: mean, 400 Hz --> 200 Hz; n > 2: median)
  medianFilterMs   moving median [ms] (default 50; 0 = off)
  meanFilterMs     moving mean [ms] (default 25; 0 = off)
  noFiltering      flag (True), same as medianFilterMs=0, meanFilterMs=0
  maxBeatWindow    at most this time before and after a peak belongs to one contraction [s] (default 3)

ROCKER ARTIFACT (see rocker_filter)
  rockerFilter     False (default) | True: remove the periodic rocker artifact while the rocker moves
  rockerFrequency  None (default: rocker speed in the log file x 0.0202 Hz/rpm, refined with the data) or the
                   rocker frequency in Hz (or rows [rpm, Hz])

REFERENCE BEAT (see reference_beat)
  referenceBeat    None (default) or reference(s) from reference_beat.create (list, one per channel; a reference
                   is applied to the channel in its field 'channel')

STIMULUS ASSIGNMENT
  minStimToPeak    a peak earlier than this after a stimulus is not caused by it [s] (default 0.025)
  maxStimToPeak    'auto' (default: min(stimulus interval, 1 s); 0.9 s if unknown) or a number [s]
  stimChannel      stimulus channel of the analysed data channel (None = same number; single channel files: the
                   channel that was stimulated)

DIASTOLIC FORCE
  zeroForce        sensor signal without load [uN] for diastolicForce = F_dia - zeroForce (None = 'Offset' entry of
                   the channel in the log file; NaN = from the log file). myodish_analysis(): one value per
                   channel or one for all channels
  pauseDiastoleWindow  after a stimulation pause (stimulus interval >= 2.5 s and >= 1.5 x the interval before),
                   F_dia is searched only from this time before the stimulus to the peak [s] (default 0.5; inf = from
                   the previous peak or maxBeatWindow, as for all other contractions). F_dia and the rocker state then
                   do not depend on drift or rocker movement during the pause

FILE FORMAT (normally taken from the log file <name>_log.log next to the .mdd file; these options override it)
  samplingRate     [Hz] (None = from the log file; without log file 400 Hz)
  nChannels        number of int16 channels per sample in the file
  calibration      'auto' (default): AU --> uN with the 'Calibration' entry of each channel in the log file;
                   'none': values as stored in the file (AU; also no extended sensor mode factor)
  extendedSensorMode  'auto' (default: from the log file), True (on during the whole file) or False
  extendedSensorFactor  default 3.3
  rockerSource     'auto' (default): rocker state from bit 15 of the status channel; from the 'rockerSpeed' entries
                   of the log file if that bit is missing (some setups) or there is no status channel.
                   'status' or 'log' forces one source
  rockerLogDelay   delay of the rocker movement after a 'rockerSpeed' entry of the log file [s] (default 0.27)

TS 2026-10-06 (port of mda_options.m, TS 2026-10-05; rockerSource, pauseDiastoleWindow 2026-10-07)
"""
from __future__ import annotations

import numbers

import numpy as np

from ._matlab import Struct, mround

_DEFAULTS = dict(
    threshold="auto",
    relThreshold=0.3,
    minThreshold=30,
    minBeatInterval=0.15,
    beats="all",
    rocker="any",
    downsampling=2,
    medianFilterMs=50,
    meanFilterMs=25,
    maxBeatWindow=3,
    rockerFilter=False,
    rockerFrequency=None,
    referenceBeat=None,
    minStimToPeak=0.025,
    maxStimToPeak="auto",
    stimChannel=None,
    zeroForce=None,
    samplingRate=None,
    nChannels=None,
    extendedSensorMode="auto",
    extendedSensorFactor=3.3,
    calibration="auto",
    rockerSource="auto",
    rockerLogDelay=0.27,
    pauseDiastoleWindow=0.5,
)
NAMES = list(_DEFAULTS)


def _is_empty(v):
    if v is None:
        return True
    try:
        return len(v) == 0 and not isinstance(v, str)
    except TypeError:
        return False


def options(base=None, **changes):
    """Options struct (Struct with the MATLAB option names); see the module help."""
    opts = Struct(_DEFAULTS)
    if base is not None:
        for k, v in dict(base).items():
            opts[k] = v
    lower = {n.lower(): n for n in NAMES}
    for key, val in changes.items():
        if key.lower() in ("nofiltering",):
            if val:
                opts.medianFilterMs = 0
                opts.meanFilterMs = 0
            continue
        name = lower.get(key.lower())
        if name is None:
            raise ValueError(f"options: unknown option '{key}'. Valid options: {', '.join(NAMES)}, noFiltering.")
        opts[name] = val
    # checks
    if _is_empty(opts.threshold) or (isinstance(opts.threshold, str) and not opts.threshold.strip()):
        opts.threshold = "auto"
    elif isinstance(opts.threshold, str):
        if opts.threshold.lower() != "auto":
            raise ValueError("options: 'threshold' must be 'auto' or a number.")
        opts.threshold = "auto"
    else:
        th = np.asarray(opts.threshold, dtype=float)
        if np.any(th <= 0):
            raise ValueError("options: 'threshold' must be 'auto', a positive number or one number per channel "
                             "(NaN = auto).")
        opts.threshold = float(th.ravel()[0]) if th.size == 1 else th.ravel()
    opts.beats = str(opts.beats).lower()
    if opts.beats not in ("all", "stimulated"):
        raise ValueError("options: 'beats' must be 'all' or 'stimulated'.")
    opts.rocker = str(opts.rocker).lower()
    if opts.rocker not in ("any", "stopped", "moving"):
        raise ValueError("options: 'rocker' must be 'any', 'stopped' or 'moving'.")
    if isinstance(opts.maxStimToPeak, str):
        opts.maxStimToPeak = "auto"
    opts.downsampling = max(1, mround(float(opts.downsampling)))
    opts.rockerSource = str(opts.rockerSource).lower()
    if opts.rockerSource not in ("auto", "status", "log"):
        raise ValueError("options: 'rockerSource' must be 'auto', 'status' or 'log'.")
    rf = opts.rockerFilter
    opts.rockerFilter = (rf is True) or (not isinstance(rf, str) and rf is not None and not _is_empty(rf)
                                          and bool(rf == 1)) or (isinstance(rf, str) and rf.lower() in ("on", "true"))
    if _is_empty(opts.referenceBeat):
        opts.referenceBeat = None
    elif isinstance(opts.referenceBeat, dict):
        opts.referenceBeat = [opts.referenceBeat]
    elif not isinstance(opts.referenceBeat, (list, tuple)):
        raise ValueError("options: 'referenceBeat' must be None or a reference from reference_beat.create.")
    else:
        opts.referenceBeat = list(opts.referenceBeat)
    pw = opts.pauseDiastoleWindow
    if isinstance(pw, (bool, str)) or not isinstance(pw, numbers.Real) or not pw > 0:
        raise ValueError("options: 'pauseDiastoleWindow' must be a positive number of seconds (inf = off).")
    opts.pauseDiastoleWindow = float(pw)
    opts.calibration = str(opts.calibration).lower()
    if opts.calibration not in ("auto", "none"):
        raise ValueError("options: 'calibration' must be 'auto' or 'none'.")
    for k in ("rockerFrequency", "stimChannel", "zeroForce", "samplingRate", "nChannels"):
        if _is_empty(opts[k]):
            opts[k] = None
    return opts


def is_numeric_threshold(v):
    return not isinstance(v, str)
