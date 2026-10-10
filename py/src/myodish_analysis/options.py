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
  rockerArtifacts  True (default) | False: paced channels, auto threshold: peaks of the rocker movement are not
                   counted as contractions (see analyze_channel): a clear gap above small peaks not locked to the
                   stimuli raises the threshold; with the rocker moving, peaks at the rocker / noise level before
                   the stimuli that are not locked to the stimuli are dropped (no contractions at all if the largest
                   peaks are not locked and their typical amplitude is <= 50 uN, or <= 2 x that level at the
                   rhythm of the rocker)
  detection        'sensitive' (default, high sensitivity) | 'specific' (high specificity): auto threshold; a
                   contraction is uncertain if it is neither locked to the stimuli (and >= 2 x the median rise of
                   the signal before the stimuli) nor large (>= 0.7 x typical amplitude and >= 3 x that rise;
                   unpaced: >= 0.5 x typical amplitude). 'sensitive': uncertain contractions are counted and flagged
                   (column uncertain); 'specific': they are not counted

SELECTION OF CONTRACTIONS (the excluded ones stay in the table with included = False)
  beats            'all' (default) | 'stimulated' (only contractions that follow a stimulus of the channel)
  rocker           'any' (default) | 'stopped' (rocker at rest from F_dia to 90 % relaxation) | 'moving'

SIGNAL PROCESSING (defaults = GetContractionParameters / analyzeMyoDish of the Seidel lab)
  spikeRemoval     True (default) | False: spike artifacts of the force channels (e.g. when chambers are taken out
                   or put in, often in several channels) are replaced by a line before the averaging of the raw
                   samples; level changes (steps) stay (see spikes.remove_spikes)
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

STIMULUS ASSIGNMENT (which pulse elicited a contraction; see analyze_channel)
  stimAssignment   'onset' (default): a pulse can only have elicited a contraction if it lies in the gate of the
                   contraction onset, from onset - gateMax to onset + gateTolerance (onset = tangent at the maximum
                   dF/dt crossing the diastolic level). Regular pulses and extra pulses (status channel bit 16, e.g.
                   pre-pulses or CCM pulses) are both candidates. 'peak': as in versions <= 1.0.0-beta.3 (last pulse
                   minStimToPeak ... maxStimToPeak before the peak; extra pulses count as regular pulses)
  gateMax          longest delay from the eliciting pulse to the onset [s] (default 0.15; near threshold the onset
                   can be delayed by ~80 ms)
  gateCore         typical delay range [s] (default 0.06): several candidates: pulses before the onset before
                   pulses after it, regular before extra pulses; of one kind the earliest up to gateCore before the
                   onset, otherwise the latest one
  gateTolerance    tolerance of the onset estimate [s] (default 0.015): pulses up to this time after the onset are
                   still candidates
  ambiguityWindow  a pulse of the other kind (regular / extra) up to this time before or after the chosen pulse:
                   column stimAmbiguous = True [s] (default 0.01; also: a pulse of the other kind would be chosen with
                   the onset gateTolerance earlier or later; fused rise phases; pulse after the gate)
  prePulseWindow   pulses that elicit no contraction: before a contraction they are kept as pre-pulses if they lie
                   at most this time before its eliciting pulse [s] (default 1); during a contraction (from the
                   eliciting pulse to 90 % relaxation) as post-pulses
  minStimToPeak    'peak' assignment: a peak earlier than this after a stimulus is not caused by it [s] (default
                   0.025)
  maxStimToPeak    'peak' assignment: 'auto' (default: min(stimulus interval, 1 s); 0.9 s if unknown) or a number [s]
  stimChannel      stimulus channel of the analysed data channel (None = same number; single channel files: the
                   channel that was stimulated)
  externalTrigger  external trigger pulses of the status channel (bit 14 without channel / current, e.g. an external
                   stimulator at the external controller unit, which carries one chamber) as stimuli: 'auto' (default:
                   if the window has external trigger pulses but no MyoDish stimulus pulses), 'on' (always; for every
                   analysed channel, MyoDish pulses ignored), 'off' (never)
  pulseTable       True (default) | False: table of all stimulus pulses of the analysed channels and ranges
                   (info["pulses"], sheet / file 'pulses'; see analysis)

DIASTOLIC FORCE
  zeroForce        sensor signal without load [uN] for diastolicForce = F_dia - zeroForce (None = 'Offset' entry of
                   the channel in the log file; NaN = from the log file). myodish_analysis(): one value per
                   channel or one for all channels
  diastolicLevel   'preStimulusMedian' (default, 2026-10-10): F_dia = median of the unfiltered signal
                   diastoleWindowStart ... diastoleWindowEnd (60 ... 5 ms) before the eliciting pulse; contractions
                   without pulse (extra, unpaced) or with a median at or above the peak: 'minimum'. 'minimum'
                   (versions <= 1.0.0-beta.3): last minimum of the filtered signal before the peak. Amplitude, upstroke
                   levels, AUC and diastolicForce refer to F_dia; relaxation levels to the minimum after the peak (both)
  pauseDiastoleWindow  after a stimulation pause (stimulus interval >= 2.5 s and >= 1.5 x the interval before),
                   the diastolic minimum is searched only from this time before the stimulus to the peak [s] (default
                   0.5; inf = from the previous peak or maxBeatWindow, as for all other contractions). The minimum and
                   the rocker state then do not depend on drift or rocker movement during the pause

PROTOCOLS (see myodish_analysis(protocol=...) and protocols.group_beats)
  ffrRockerFallback  True (default) | False: FFR protocols with rocker 'stopped': a pacing frequency (step) without
                   contractions with the rocker at rest is summarized from its contractions with the rocker moving
  prpReference     post-rest potentiation, reference amplitude of each post-rest contraction: 'preceding' (default):
                   median of the last prpReferenceBeats (6) contractions of the pacing before the pause; 'firstTrain':
                   mean of the contractions of the pacing before the first pause of the protocol; 'steady': mean of the
                   steady group (versions <= 1.0.0-beta.3)

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

ADVANCED SETTINGS (2026-10-10; before: constants in the code, based on assumptions or experience; GUI
'Advanced ...'; saved with every analysis (info table) and as a settings file, see settings.py)
 ASSIGNMENT
 risePhaseLevel           no pulse in the gate of the onset: the onsets of the other rise phases of the upstroke are
                          tried (local maxima of dF/dt of at least this fraction of the maximum dF/dt; rocker movement,
                          fused spontaneous events) (default 0.25)
 steepRiseMargin          still no pulse: a pulse after the gate up to this time before the maximum dF/dt is taken
                          (onset estimated too early, e.g. rocker artifacts); marked ambiguous [s] (default 0.005)
 contractionEnd           end of a contraction for post-pulses, for regular pulses missed within a contraction and for
                          the phase of the pulse table: this relaxation (% of peak - minimum after the peak) [%
                          relaxation] (default 90)
 offsetSnap               time of pre- / post-pulses: the programmed offset of the log file ('Sequence' entries) is
                          used if the measured offset (resolution 2.5 ms) lies within this time of it [s] (default
                          0.005)
 DETECTION
 pacedMinStimuli          a channel counts as paced with at least this many regular pulses in the data window: typical
                          amplitude = median of the largest peaks (as many as pulses), noise level before the stimuli,
                          rocker rules, certainty by locking; otherwise: largest gap between the sorted prominences
                          [pulses] (default 3)
 pauseMinInterval         stimulation pause: stimulus interval at least this long ... [s] (default 2.5)
 pauseIntervalRatio       ... and at least this multiple of the interval before; then F_dia is searched only from
                          pauseDiastoleWindow before the stimulus [x interval before] (default 1.5)
 diastoleWindowStart      diastolic level 'median before the pulse': window from this time before the eliciting pulse
                          ... [s] (default 0.06)
 diastoleWindowEnd        ... to this time before the pulse (stimulus artifact excluded) [s] (default 0.005)
 lockWindow               a peak is locked to the stimuli if its latency (time since the previous pulse) lies within
                          +-lockWindow of the typical latency (centre of the densest window of 2 x lockWindow);
                          certainty and rocker / artifact rules [s] (default 0.1)
 lockWindowRel            at high rates the lock window is at most this fraction of the stimulus interval (certainty;
                          rocker-only rule) [x stimulus interval] (default 0.2)
 certainNoiseRel          certainty, paced: a locked contraction is certain if its prominence is >= this multiple of
                          the median rise of the signal before the stimuli [x median rise] (default 2)
 certainLargeRel          certainty, paced: a contraction that is not locked is certain if it is >= this fraction of
                          the typical amplitude ... [x typical] (default 0.7)
 certainLargeNoiseRel     ... and >= this multiple of the median rise before the stimuli [x median rise] (default 3)
 certainUnpacedRel        certainty, unpaced channels: certain if >= this fraction of the typical amplitude [x typical]
                          (default 0.5)
 NOISE / ARTIFACTS
 noiseMinInterval         noise level N: only windows before stimuli that follow an interval of at least this length
                          [s] (default 0.9)
 noiseWindow              noise level N: window before each such stimulus (at most noiseWindowRel x interval); rise =
                          maximum minus the running minimum of the signal [s] (default 0.5)
 noiseWindowRel           noise window at most this fraction of the stimulus interval [x interval] (default 0.4)
 noisePercentile          noise level N = this percentile of the rises (the median of the rises is used for the
                          certainty) [%] (default 90)
 noiseMinWindows          noise level only with at least this many windows (otherwise unknown) [windows] (default 10)
 artifactMinCandidates    artifact gap rule (raises the threshold): needs at least this many peaks above the auto
                          threshold [peaks] (default 6)
 artifactGapRatio         artifact gap rule: the largest ratio between two consecutive sorted prominences below the
                          typical amplitude must be >= this value (a clear gap between artifacts and contractions) [x]
                          (default 1.6)
 artifactMaxRel           artifact gap rule: all peaks of the lower cluster are <= this fraction of the typical
                          amplitude [x typical] (default 0.5)
 artifactMinPeaks         artifact gap rule: at least this many peaks of the lower cluster are not locked to the
                          stimuli [peaks] (default 3)
 artifactRockerFraction   artifact gap rule: at least this fraction of the lower cluster occurs while the rocker moves
                          (default 0.75)
 chanceMargin             locked 'more than by chance': fraction locked > chance level (2 x lockWindow / stimulus
                          interval) + this margin ... (default 0.2)
 chanceMax                ... the limit is at most this fraction (artifact gap rule, partial capture of the rocker
                          rules) (default 0.6)
 ROCKER RULES
 rockerRuleMinFraction    rocker rules (b, c): only if the rocker moves during at least this fraction of the data
                          window (default 0.5)
 noiseLockedMax           rule b (no contractions): fewer than this fraction of the largest peaks (as many as pulses)
                          locked ... (default 0.5)
 noiseAbsMax              ... and the typical amplitude <= this value ... [uN] (default 50)
 noiseRelMax              ... or <= this multiple of the noise level N with the peaks at the rhythm of the rocker:
                          rocker / noise peaks [x N] (default 2)
 rhythmMinPerCycle        rhythm of the rocker: at least this many peaks per rocker cycle (rule b) ... [peaks / cycle]
                          (default 0.7)
 rhythmMaxPerCycle        ... and at most this many, or a median peak interval of 1 or 1/2 rocker period ... [peaks /
                          cycle] (default 2.2)
 rhythmTolerance          ... within this tolerance (1/2 period: half of it) (default 0.15)
 keepNoiseRel             rule b: locked peaks >= max(keepNoiseRel x N, N + keepNoiseAbs) stay (slices that answer only
                          some stimuli) ... [x N] (default 1.5)
 keepNoiseAbs             ... (absolute distance from the noise level) ... [uN] (default 50)
 keepMinPeaks             ... if there are at least this many of them ... [peaks] (default 3)
 keepMinFraction          ... and at least this fraction of the pulses, and more of them are locked than by chance
                          (default 0.05)
 dropRel                  rule b: peaks below this multiple of max(typical amplitude, N) are removed (larger peaks are
                          no rocker artifacts) [x max(typical, N)] (default 3)
 smallNoiseRel            rule c: peaks not locked to the stimuli below min(smallNoiseRel x N, smallTypicalRel x
                          typical) are removed ... [x N] (default 1.5)
 smallTypicalRel          ... (peaks at the rhythm of the rocker: smallRhythmTypicalRel instead) ... [x typical]
                          (default 0.5)
 smallRhythmMinPerCycle   ... rhythm of the rocker for rule c: at least this many peaks per rocker cycle ... [peaks /
                          cycle] (default 0.5)
 smallRhythmTypicalRel    ... then the limit is min(smallNoiseRel x N, this fraction of the typical amplitude) [x
                          typical] (default 1)
 rockerOnlyMinIntervals   N unknown (high rates): peaks at the rhythm of the rocker need at least this many peak
                          intervals ... [intervals] (default 10)
 rockerOnlyFraction       ... of which at least this fraction are 1 or 1/2 rocker period ... (default 0.6)
 rockerOnlyTolerance      ... within this tolerance (1/2 period: half of it) ... (default 0.1)
 captureTolerance         ... and the median interval is no 1:1 or 2:1 multiple of the stimulus interval within this
                          tolerance (capture at the rocker period cannot be told apart) (default 0.05)
 SIGNAL
 spikeJumpMin             spike: a jump between two raw samples >= J = max(spikeJumpMin, spikeJumpFactor x median of
                          the non-zero differences of the channel) ... [AU] (default 50)
 spikeJumpFactor          ... (noise level of the channel) ... [x noise] (default 8)
 spikeGroupGap            jumps closer than this form one group ... [s] (default 0.04)
 spikeMaxDuration         ... that lasts at most this long ... [s] (default 0.1)
 spikeLevelWindow         ... and goes beyond the level before and after it (median of this time) by >= J ... [s]
                          (default 0.02)
 spikeJumpFraction        ... with the largest jump >= this fraction of its largest deviation (abrupt; a contraction
                          rises over many samples) (default 0.5)
 spikeCoincidence         within this time of a spike of another channel ... [s] (default 0.01)
 spikeCoincidenceFactor   ... the jump threshold is max(spikeJumpMin, this factor x J) (spikes in several channels) [x
                          J] (default 0.5)
 ROCKER FILTER
 rockerHzPerRpm           rocker frequency per rpm setting (two setups: 0.02020 and 0.02025 Hz/rpm); rocker rules and
                          rocker filter [Hz / rpm] (default 0.0202)
 rfBandRel                rocker filter: the rocker frequency is searched within +-this fraction of the expected
                          frequency (default 0.03)
 rfBandNoLog              rocker filter: search band without rocker speed in the log file [Hz (from to)] (default 0.4
                          2.2)
 rfHarmonics              rocker filter: number of harmonics of the periodic artifact [harmonics] (default 6)
 rfBlock                  rocker filter: block length of the fit (hop = half a block) [s] (default 30)
 rfMinRun                 rocker filter: shorter rocker-on periods are not corrected [s] (default 3)
 rfKnot                   rocker filter: knot distance of the baseline (slow drift) fitted together with the artifact
                          [s] (default 2)
 rfSmoothBaseline         rocker filter: smoothness penalty of the baseline (default 0.1)
 rfRidge                  rocker filter: ridge penalty of the harmonics (default 0.001)
 rfMinCover               rocker filter: a block is fitted only if this fraction of the 20 phase bins of the rocker
                          cycle has >= 5 samples between the contractions (default 0.9)
 rfMinR2                  rocker filter: minimum R2 of a block fit (default 0.2)
 rfMaxSizeRel             rocker filter: artifact size of a block at most this multiple of the reference size [x
                          reference] (default 1.6)
 rfMinRefBlock            rocker filter: reference blocks are at least this long [s] (default 10)
 rfMaxBorrow              rocker filter: a block without own fit uses the artifact of a neighbouring block of the same
                          rocker period up to this distance [s] (default 60)
 rfF0Block                rocker filter, frequency estimate: blocks of at most this length ... [s] (default 120)
 rfF0Blocks               ... at most this many per channel and rocker speed ... [blocks] (default 6)
 rfF0Clear                ... and the peak of the fit must be clear within +-this fraction (default 0.1)
 rfExtendBlock            rocker filter: blocks without full coverage of the rocker cycle are retried with this length
                          [s] (default 90)
 rfMaskRelax              rocker filter: the artifact is fitted to the samples between contractions; a contraction is
                          masked from TTP90 + rfMaskMargin before its peak to rfMaskRelax x TTR90 + rfMaskMargin after
                          it (medians of the channel) [x TTR90] (default 1.3)
 rfMaskMargin             rocker filter: margin of the contraction masks before and after a contraction [s] (default
                          0.08)
 rfMaskMax                rocker filter, paced channels (first pass): masked from 20 ms before each pulse to min(next
                          pulse - 50 ms, this time) after it [s] (default 1.2)
 PROTOCOLS
 frequencyResolution      grouping by pacing frequency (FFR): stimulus intervals within 2 % form a group, its frequency
                          (1 / median interval) is rounded to this step at >= 1 Hz; groups with the same rounded
                          frequency are one group (0.99, 1.0 and 1.001 Hz = 1 Hz). FFR results: the groups at 0.5, 1, 2
                          and 3 Hz [Hz] (default 0.1)
 frequencyResolutionLow   ... below 1 Hz the frequency is rounded to this step (0.49 and 0.5 Hz = 0.5 Hz, 0.74 and 0.75
                          Hz = 0.75 Hz) [Hz] (default 0.05)
 pauseTolerance           grouping by pause length (post-rest potentiation): pauses (stimulus interval - steady
                          interval) within this fraction of the shortest pause of a set are one pause length (same
                          group value and label, numbered #n); PRP15 / 30 / 60: mean of the pauses within this fraction
                          of 15 / 30 / 60 s (default 0.1)
 steadyStateBeats         FFR protocols: each pacing frequency is summarized from its steady state: the last this many
                          contractions of the longest run of consecutive stimuli at this frequency (other runs, e.g.
                          the basic pacing before and after the protocol, are not used), of its longest sequence of
                          captured stimuli whose previous and next stimuli are captured, too (partial capture, e.g.
                          2:1, gives no steady state). 0 = all contractions of the frequency (versions <=
                          1.0.0-beta.3) [contractions] (default 10)
 prpReferenceBeats        PRP reference 'last beats before each pause': number of contractions before the pause
                          (median) [contractions] (default 6)
 irregularCV              a group (e.g. FFR step) is flagged irregular (summary column irregular) if the coefficient of
                          variation of the amplitudes of its included contractions (population SD / mean, column
                          amplitude_CV) exceeds this value: conduction block, alternans or extra beats (default 0.15)
 minGroupBeats            FFR protocols: a note lists the frequencies summarized from fewer included contractions (0 =
                          no note) [contractions] (default 5)
 EXPORT
 pulseTextMax             prePulses / postPulses: at most this many pulses (those nearest to the eliciting pulse), then
                          '&+<number of the others>' [pulses] (default 10)

TS 2026-10-06 (port of mda_options.m, TS 2026-10-05; rockerSource, pauseDiastoleWindow 2026-10-07;
rockerArtifacts, detection 2026-10-09; onset gate, extra pulses, pulse table, advanced settings, diastolic level,
FFR steady state, PRP reference 2026-10-10)
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
    rockerArtifacts=True,
    detection="sensitive",
    beats="all",
    rocker="any",
    spikeRemoval=True,
    downsampling=2,
    medianFilterMs=50,
    meanFilterMs=25,
    maxBeatWindow=3,
    rockerFilter=False,
    rockerFrequency=None,
    referenceBeat=None,
    stimAssignment="onset",
    gateMax=0.15,
    gateCore=0.06,
    gateTolerance=0.015,
    ambiguityWindow=0.01,
    prePulseWindow=1,
    minStimToPeak=0.025,
    maxStimToPeak="auto",
    stimChannel=None,
    externalTrigger="auto",
    pulseTable=True,
    diastolicLevel="preStimulusMedian",
    ffrRockerFallback=True,
    prpReference="preceding",
    zeroForce=None,
    samplingRate=None,
    nChannels=None,
    extendedSensorMode="auto",
    extendedSensorFactor=3.3,
    calibration="auto",
    rockerSource="auto",
    rockerLogDelay=0.27,
    pauseDiastoleWindow=0.5,
    # advanced settings (2026-10-10)
    risePhaseLevel=0.25,
    steepRiseMargin=0.005,
    contractionEnd=90,
    offsetSnap=0.005,
    pacedMinStimuli=3,
    pauseMinInterval=2.5,
    pauseIntervalRatio=1.5,
    diastoleWindowStart=0.06,
    diastoleWindowEnd=0.005,
    lockWindow=0.1,
    lockWindowRel=0.2,
    certainNoiseRel=2,
    certainLargeRel=0.7,
    certainLargeNoiseRel=3,
    certainUnpacedRel=0.5,
    noiseMinInterval=0.9,
    noiseWindow=0.5,
    noiseWindowRel=0.4,
    noisePercentile=90,
    noiseMinWindows=10,
    artifactMinCandidates=6,
    artifactGapRatio=1.6,
    artifactMaxRel=0.5,
    artifactMinPeaks=3,
    artifactRockerFraction=0.75,
    chanceMargin=0.2,
    chanceMax=0.6,
    rockerRuleMinFraction=0.5,
    noiseLockedMax=0.5,
    noiseAbsMax=50,
    noiseRelMax=2,
    rhythmMinPerCycle=0.7,
    rhythmMaxPerCycle=2.2,
    rhythmTolerance=0.15,
    keepNoiseRel=1.5,
    keepNoiseAbs=50,
    keepMinPeaks=3,
    keepMinFraction=0.05,
    dropRel=3,
    smallNoiseRel=1.5,
    smallTypicalRel=0.5,
    smallRhythmMinPerCycle=0.5,
    smallRhythmTypicalRel=1,
    rockerOnlyMinIntervals=10,
    rockerOnlyFraction=0.6,
    rockerOnlyTolerance=0.1,
    captureTolerance=0.05,
    spikeJumpMin=50,
    spikeJumpFactor=8,
    spikeGroupGap=0.04,
    spikeMaxDuration=0.1,
    spikeLevelWindow=0.02,
    spikeJumpFraction=0.5,
    spikeCoincidence=0.01,
    spikeCoincidenceFactor=0.5,
    rockerHzPerRpm=0.0202,
    rfBandRel=0.03,
    rfBandNoLog=(0.4, 2.2),
    rfHarmonics=6,
    rfBlock=30,
    rfMinRun=3,
    rfKnot=2,
    rfSmoothBaseline=0.1,
    rfRidge=0.001,
    rfMinCover=0.9,
    rfMinR2=0.2,
    rfMaxSizeRel=1.6,
    rfMinRefBlock=10,
    rfMaxBorrow=60,
    rfF0Block=120,
    rfF0Blocks=6,
    rfF0Clear=0.1,
    rfExtendBlock=90,
    rfMaskRelax=1.3,
    rfMaskMargin=0.08,
    rfMaskMax=1.2,
    frequencyResolution=0.1,
    frequencyResolutionLow=0.05,
    pauseTolerance=0.1,
    steadyStateBeats=10,
    prpReferenceBeats=6,
    irregularCV=0.15,
    minGroupBeats=5,
    pulseTextMax=10,
)
NAMES = list(_DEFAULTS)


def _is_empty(v):
    if v is None:
        return True
    try:
        return len(v) == 0 and not isinstance(v, str)
    except TypeError:
        return False


def _number(v):
    """option value as float (NaN if not a single real number)"""
    if isinstance(v, (bool, str)) or v is None:
        return float("nan")
    try:
        a = np.asarray(v, dtype=float).ravel()
    except (TypeError, ValueError):
        return float("nan")
    return float(a[0]) if a.size == 1 else float("nan")


def options(base=None, **changes):
    """Options struct (Struct with the MATLAB option names); see the module help."""
    opts = Struct(_DEFAULTS)
    if base is not None:
        for k, v in dict(base).items():
            opts[k] = v
    lower = {n.lower(): n for n in NAMES}
    for key in [k for k in changes if k.lower() == "settings"]:  # settings file (settings.py): first, the other
        val = changes.pop(key)                                        # keywords override it
        if val:
            from .settings import load_settings
            for k, v in load_settings(val).items():
                if k != "referenceBeat":
                    opts[k] = v
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
    opts.detection = str(opts.detection).lower()
    if opts.detection not in ("sensitive", "specific"):
        raise ValueError("options: 'detection' must be 'sensitive' or 'specific'.")
    opts.beats = str(opts.beats).lower()
    if opts.beats not in ("all", "stimulated"):
        raise ValueError("options: 'beats' must be 'all' or 'stimulated'.")
    opts.rocker = str(opts.rocker).lower()
    if opts.rocker not in ("any", "stopped", "moving"):
        raise ValueError("options: 'rocker' must be 'any', 'stopped' or 'moving'.")
    if isinstance(opts.maxStimToPeak, str):
        opts.maxStimToPeak = "auto"
    opts.downsampling = max(1, mround(float(opts.downsampling)))
    opts.externalTrigger = str(opts.externalTrigger).lower()
    if opts.externalTrigger not in ("auto", "on", "off"):
        raise ValueError("options: 'externalTrigger' must be 'auto', 'on' or 'off'.")
    opts.rockerSource = str(opts.rockerSource).lower()
    if opts.rockerSource not in ("auto", "status", "log"):
        raise ValueError("options: 'rockerSource' must be 'auto', 'status' or 'log'.")
    ag = opts.rockerArtifacts
    opts.rockerArtifacts = (ag is True) or (not isinstance(ag, str) and ag is not None and not _is_empty(ag)
                                        and bool(ag == 1)) or (isinstance(ag, str) and ag.lower() in ("on", "true"))
    rf = opts.rockerFilter
    opts.rockerFilter = (rf is True) or (not isinstance(rf, str) and rf is not None and not _is_empty(rf)
                                          and bool(rf == 1)) or (isinstance(rf, str) and rf.lower() in ("on", "true"))
    sr = opts.spikeRemoval
    opts.spikeRemoval = (sr is True) or (not isinstance(sr, str) and sr is not None and not _is_empty(sr)
                                          and bool(sr == 1)) or (isinstance(sr, str) and sr.lower() in ("on", "true"))
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
    opts.stimAssignment = str(opts.stimAssignment).lower()
    if opts.stimAssignment not in ("onset", "peak"):
        raise ValueError("options: 'stimAssignment' must be 'onset' or 'peak'.")
    for k in ("gateMax", "gateCore", "gateTolerance", "ambiguityWindow", "prePulseWindow"):
        v = opts[k]
        if isinstance(v, (bool, str)) or not isinstance(v, numbers.Real) or not v >= 0:
            raise ValueError(f"options: '{k}' must be a number of seconds >= 0.")
        opts[k] = float(v)
    if opts.gateCore > opts.gateMax:
        opts.gateCore = opts.gateMax
    # advanced settings (2026-10-10)
    for k in ("risePhaseLevel", "artifactRockerFraction", "chanceMargin", "chanceMax",
              "rockerRuleMinFraction", "noiseLockedMax", "rhythmTolerance", "keepMinFraction", "rockerOnlyFraction",
              "rockerOnlyTolerance", "captureTolerance", "spikeJumpFraction", "rfBandRel", "rfMinCover", "rfMinR2",
              "rfF0Clear", "pauseTolerance"):
        v = _number(opts[k])
        if not (0 <= v <= 1):
            raise ValueError(f"options: '{k}' must be a number from 0 to 1.")
        opts[k] = v
    for k in ("steepRiseMargin", "offsetSnap", "pauseMinInterval", "pauseIntervalRatio",
              "diastoleWindowEnd", "certainNoiseRel", "certainLargeRel", "certainLargeNoiseRel", "certainUnpacedRel",
              "noiseMinInterval", "artifactMaxRel", "noiseAbsMax", "noiseRelMax", "rhythmMinPerCycle", "keepNoiseRel",
              "keepNoiseAbs", "dropRel", "smallNoiseRel", "smallTypicalRel", "smallRhythmMinPerCycle",
              "smallRhythmTypicalRel", "spikeJumpFactor", "spikeGroupGap", "spikeCoincidence", "rfMinRun",
              "rfSmoothBaseline", "rfRidge", "rfMinRefBlock", "rfMaxBorrow", "rfMaskMargin", "irregularCV"):
        v = _number(opts[k])
        if not (v >= 0):
            raise ValueError(f"options: '{k}' must be a number >= 0.")
        opts[k] = v
    for k in ("contractionEnd", "noisePercentile"):
        v = _number(opts[k])
        if not (0 <= v <= 100):
            raise ValueError(f"options: '{k}' must be a number from 0 to 100.")
        opts[k] = v
    for k in ("pacedMinStimuli", "noiseMinWindows", "artifactMinCandidates", "artifactMinPeaks",
              "rockerOnlyMinIntervals", "rfHarmonics", "rfF0Blocks", "prpReferenceBeats", "pulseTextMax"):
        v = _number(opts[k])
        if not (v >= 1 and v == round(v)):
            raise ValueError(f"options: '{k}' must be an integer >= 1.")
        opts[k] = v
    for k in ("diastoleWindowStart", "lockWindow", "lockWindowRel", "noiseWindow", "noiseWindowRel",
              "artifactGapRatio", "rhythmMaxPerCycle", "spikeJumpMin", "spikeMaxDuration", "spikeLevelWindow",
              "spikeCoincidenceFactor", "rockerHzPerRpm", "rfBlock", "rfKnot", "rfMaxSizeRel", "rfF0Block",
              "rfExtendBlock", "rfMaskRelax", "rfMaskMax", "frequencyResolution", "frequencyResolutionLow"):
        v = _number(opts[k])
        if not (v > 0):
            raise ValueError(f"options: '{k}' must be a number > 0.")
        opts[k] = v
    for k in ("keepMinPeaks", "steadyStateBeats", "minGroupBeats"):
        v = _number(opts[k])
        if not (v >= 0 and v == round(v)):
            raise ValueError(f"options: '{k}' must be an integer >= 0.")
        opts[k] = v
    v = np.asarray(opts.rfBandNoLog, dtype=float).ravel()
    if not (v.size == 2 and np.all(v > 0) and v[1] > v[0]):
        raise ValueError("options: 'rfBandNoLog' must be two increasing numbers > 0.")
    opts.rfBandNoLog = (float(v[0]), float(v[1]))
    pt = opts.pulseTable
    opts.pulseTable = (pt is True) or (not isinstance(pt, str) and pt is not None and not _is_empty(pt)
                                        and bool(pt == 1)) or (isinstance(pt, str) and pt.lower() in ("on", "true"))
    for k in ("rockerFrequency", "stimChannel", "zeroForce", "samplingRate", "nChannels"):
        if _is_empty(opts[k]):
            opts[k] = None
    # 2026-10-10: diastolic level, FFR steps without rocker stop, PRP reference
    vals = {"prestimulusmedian": "preStimulusMedian", "minimum": "minimum"}
    if str(opts.diastolicLevel).lower() not in vals:
        raise ValueError("options: 'diastolicLevel' must be 'preStimulusMedian' or 'minimum'.")
    opts.diastolicLevel = vals[str(opts.diastolicLevel).lower()]
    if opts.diastoleWindowEnd >= opts.diastoleWindowStart:
        raise ValueError("options: 'diastoleWindowEnd' must be smaller than 'diastoleWindowStart'.")
    fb = opts.ffrRockerFallback
    opts.ffrRockerFallback = (fb is True) or (not isinstance(fb, str) and fb is not None and not _is_empty(fb)
                                              and bool(fb == 1)) or (isinstance(fb, str) and fb.lower() in ("on", "true"))
    vals = {"preceding": "preceding", "firsttrain": "firstTrain", "steady": "steady"}
    if str(opts.prpReference).lower() not in vals:
        raise ValueError("options: 'prpReference' must be 'preceding', 'firstTrain' or 'steady'.")
    opts.prpReference = vals[str(opts.prpReference).lower()]
    return opts


def is_numeric_threshold(v):
    return not isinstance(v, str)
