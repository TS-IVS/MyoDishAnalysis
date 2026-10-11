function opts = mda_options(varargin)
%MDA_OPTIONS  Analysis options of the MyoDishAnalysis (defaults + name/value changes).
%
%   opts = mda_options()                         default options
%   opts = mda_options('threshold',150,...)      defaults, changed by name/value pairs
%   opts = mda_options(opts,'rocker','stopped')  update an existing options struct
%
% Names are not case sensitive. Unknown names raise an error (typos are not silently ignored).
%
% DETECTION OF CONTRACTIONS
%   'threshold'        'auto' (default) or a number [uN]: minimum prominence of a contraction peak; MyoDishAnalysis
%                      also takes one value per channel (NaN = auto for that channel)
%   'relThreshold'     auto threshold: at most this fraction of the typical contraction amplitude (default 0.3)
%   'minThreshold'     auto threshold: never lower than this [uN] (default 30)
%   'minBeatInterval'  minimum time between two contraction peaks [s] (default 0.15, i.e. up to ~6.7 Hz)
%   'rockerArtifacts'  true (default) | false: paced channels, auto threshold: peaks of the rocker movement are not
%                      counted as contractions (see mda_analyzeChannel): a clear gap above small peaks not locked to
%                      the stimuli raises the threshold; with the rocker moving, peaks at the rocker / noise level
%                      before the stimuli that are not locked to the stimuli are dropped (no contractions at all if
%                      the largest peaks are not locked and their typical amplitude is <= 50 uN, or <= 2 x that
%                      level at the rhythm of the rocker)
%   'detection'        'sensitive' (default, high sensitivity) | 'specific' (high specificity): auto threshold; a
%                      contraction is uncertain if it is neither locked to the stimuli (and >= 2 x the median rise
%                      of the signal before the stimuli) nor large (>= 0.7 x typical amplitude and >= 3 x that rise;
%                      unpaced: >= 0.5 x typical amplitude). 'sensitive': uncertain contractions are counted and
%                      flagged (column uncertain); 'specific': they are not counted
%
% SELECTION OF CONTRACTIONS (the excluded ones stay in the table with included = false)
%   'beats'            'all' (default) | 'stimulated' (only contractions that follow a stimulus of the channel)
%   'rocker'           'any' (default) | 'stopped' (rocker at rest from F_dia to 90 % relaxation) | 'moving'
%
% SIGNAL PROCESSING (defaults = GetContractionParameters / analyzeMyoDish of the Seidel lab)
%   'spikeRemoval'     true (default) | false: spike artifacts of the force channels (e.g. when chambers are taken out
%                      or put in, often in several channels) are replaced by a line before the averaging of the raw
%                      samples; level changes (steps) stay (see mda_removeSpikes)
%   'downsampling'     n raw samples are combined (default 2: mean, 400 Hz --> 200 Hz; n > 2: median)
%   'medianFilterMs'   moving median [ms] (default 50; 0 = off)
%   'meanFilterMs'     moving mean [ms] (default 25; 0 = off)
%   'noFiltering'      flag, same as 'medianFilterMs',0,'meanFilterMs',0
%   'maxBeatWindow'    at most this time before and after a peak belongs to one contraction [s] (default 3)
%
% ROCKER ARTIFACT (see mda_rockerFilter)
%   'rockerFilter'     false (default) | true: remove the periodic rocker artifact from the force signal while the
%                      rocker moves (estimated per channel from the signal between the contractions)
%   'rockerFrequency'  [] (default: rocker speed in the log file x 0.0202 Hz/rpm, refined with the data) or the
%                      rocker frequency in Hz (or rows [rpm Hz])
%
% REFERENCE BEAT (see mda_referenceBeat)
%   'referenceBeat'    [] (default) or reference(s) from mda_referenceBeat('create', ...) (struct array, one per
%                      channel; a reference is applied to the channel in its field 'channel'; alignment at the
%                      stimulus or the 50 % upstroke: field 'align', mda_referenceBeat('align', R, ...)): parameters
%                      refCorrelation, refRMSDeviation_SD, refRMSDeviationNorm_SD, refMaxDeviation_SD,
%                      refMaxDeviationNorm_SD (NaN without reference)
%
% STIMULUS ASSIGNMENT (which pulse elicited a contraction; see mda_analyzeChannel)
%   'stimAssignment'   'onset' (default): a pulse can only have elicited a contraction if it lies in the gate of the
%                      contraction onset, from onset - gateMax to onset + gateTolerance (onset = tangent at the
%                      maximum dF/dt crossing the diastolic level). Regular pulses and extra pulses (status channel
%                      bit 16, e.g. pre-pulses or CCM pulses) are both candidates. 'peak': as in versions <= 1.0.0-beta.3
%                      (last pulse minStimToPeak ... maxStimToPeak before the peak; extra pulses count as regular
%                      pulses)
%   'gateMax'          longest delay from the eliciting pulse to the onset [s] (default 0.15; near threshold the
%                      onset can be delayed by ~80 ms)
%   'gateCore'         typical delay range [s] (default 0.06): several candidates: pulses before the onset before
%                      pulses after it, regular before extra pulses; of one kind the earliest up to gateCore before the
%                      onset, otherwise the latest one
%   'gateTolerance'    tolerance of the onset estimate [s] (default 0.015): pulses up to this time after the onset
%                      are still candidates
%   'ambiguityWindow'  a pulse of the other kind (regular / extra) up to this time before or after the chosen pulse:
%                      column stimAmbiguous = true [s] (default 0.01; also: a pulse of the other kind would be chosen
%                      with the onset gateTolerance earlier or later; fused rise phases; pulse after the gate)
%   'prePulseWindow'   pulses that elicit no contraction: before a contraction they are kept as pre-pulses if they
%                      lie at most this time before its eliciting pulse [s] (default 1); during a contraction (from
%                      the eliciting pulse to 90 % relaxation) as post-pulses
%   'minStimToPeak'    'peak' assignment: a peak earlier than this after a stimulus is not caused by it [s] (default
%                      0.025)
%   'maxStimToPeak'    'peak' assignment: 'auto' (default: min(stimulus interval, 1 s); 0.9 s if unknown) or a
%                      number [s]
%   'stimChannel'      stimulus channel of the analysed data channel ([] = same number; single channel files:
%                      the channel that was stimulated)
%   'externalTrigger'  external trigger pulses of the status channel (bit 14 without channel / current, e.g. an
%                      external stimulator at the external controller unit, which carries one chamber) as stimuli:
%                      'auto' (default: if the window has external trigger pulses but no MyoDish stimulus pulses),
%                      'on' (always; for every analysed channel, MyoDish pulses ignored), 'off' (never)
%   'pulseTable'       true (default) | false: table of all stimulus pulses of the analysed channels and ranges
%                      (info.pulses, sheet / file 'pulses'; see MyoDishAnalysis)
%
% DIASTOLIC FORCE
%   'zeroForce'        sensor signal without load [uN] for diastolicForce = F_dia - zeroForce ([] = 'Offset' entry of
%                      the channel in the log file; NaN = from the log file). MyoDishAnalysis: one value per
%                      channel or one for all channels
%   'diastolicLevel'   'preStimulusMedian' (default, 2026-10-10): F_dia = median of the unfiltered signal
%                      diastoleWindowStart ... diastoleWindowEnd (60 ... 5 ms) before the eliciting pulse; contractions
%                      without pulse (extra, unpaced) or with a median at or above the peak: 'minimum'.
%                      'minimum' (versions <= 1.0.0-beta.3): last minimum of the filtered signal before the peak.
%                      Amplitude, upstroke levels, AUC and diastolicForce refer to F_dia; relaxation levels to the
%                      minimum after the peak (both)
%   'pauseDiastoleWindow' after a stimulation pause (stimulus interval >= 2.5 s and >= 1.5 x the interval before),
%                      the diastolic minimum is searched only from this time before the stimulus to the peak [s]
%                      (default 0.5; Inf = from the previous peak or maxBeatWindow, as for all other contractions).
%                      The minimum and the rocker state then do not depend on drift or rocker movement during the pause
%
% PROTOCOLS (see MyoDishAnalysis 'protocol' and mda_groupBeats)
%   'ffrRockerFallback' true (default) | false: FFR protocols with rocker 'stopped': a pacing frequency (step) without
%                      contractions with the rocker at rest is summarized from its contractions with the rocker moving
%   'prpReference'     post-rest potentiation, reference amplitude of each post-rest contraction: 'preceding'
%                      (default): median of the last prpReferenceBeats (6) contractions of the pacing before the pause;
%                      'firstTrain': mean of the contractions of the pacing before the first pause of the protocol;
%                      'steady': mean of the steady group (versions <= 1.0.0-beta.3)
%
% FILE FORMAT (normally taken from the log file <name>_log.log next to the .mdd file; these options override it)
%   'samplingRate'     [Hz] ([] = from the log file; without log file 400 Hz)
%   'nChannels'        number of int16 channels per sample in the file ([] = from file size and log file, or
%                      from the content of the status channel)
%   'calibration'      'auto' (default): the data (arbitrary units, AU) are converted to uN with the 'Calibration'
%                      entry of each channel in the log file (AU per mN; 1000 = AU are uN, 3000 = divide by 3);
%                      'none': no conversion (values as stored in the file, AU; also no extended sensor mode factor)
%   'extendedSensorMode' 'auto' (default: from the log file, events 'extended sensor mode on/off'), true (on during
%                      the whole file, e.g. old log files without the event) or false. While on, the calibration value
%                      is divided by 'extendedSensorFactor' (default 3.3; 1000 --> 1000/3.3, i.e. AU x 3.3)
%   'rockerSource'     'auto' (default): rocker state from bit 15 of the status channel; from the 'rockerSpeed'
%                      entries of the log file if that bit is missing (some setups) or there is no status channel.
%                      'status' or 'log' forces one source
%   'rockerLogDelay'   delay of the rocker movement after a 'rockerSpeed' entry of the log file [s] (default 0.27)
%
% ADVANCED SETTINGS (2026-10-10; before: constants in the code, based on assumptions or experience; GUI
% 'Advanced ...'; saved with every analysis (info table) and as a settings file, see mda_settings)
%  ASSIGNMENT
%  'risePhaseLevel'         no pulse in the gate of the onset: the onsets of the other rise phases of the upstroke are
%                           tried (local maxima of dF/dt of at least this fraction of the maximum dF/dt; rocker
%                           movement, fused spontaneous events) (default 0.25)
%  'steepRiseMargin'        still no pulse: a pulse after the gate up to this time before the maximum dF/dt is taken
%                           (onset estimated too early, e.g. rocker artifacts); marked ambiguous [s] (default 0.005)
%  'contractionEnd'         end of a contraction for post-pulses, for regular pulses missed within a contraction and for
%                           the phase of the pulse table: this relaxation (% of peak - minimum after the peak) [%
%                           relaxation] (default 90)
%  'offsetSnap'             time of pre- / post-pulses: the programmed offset of the log file ('Sequence' entries) is
%                           used if the measured offset (resolution 2.5 ms) lies within this time of it [s] (default
%                           0.005)
%  DETECTION
%  'pacedMinStimuli'        a channel counts as paced with at least this many regular pulses in the data window: typical
%                           amplitude = median of the largest peaks (as many as pulses), noise level before the stimuli,
%                           rocker rules, certainty by locking; otherwise: largest gap between the sorted prominences
%                           [pulses] (default 3)
%  'pauseMinInterval'       stimulation pause: stimulus interval at least this long ... [s] (default 2.5)
%  'pauseIntervalRatio'     ... and at least this multiple of the interval before; then F_dia is searched only from
%                           pauseDiastoleWindow before the stimulus [x interval before] (default 1.5)
%  'diastoleWindowStart'    diastolic level 'median before the pulse': window from this time before the eliciting pulse
%                           ... [s] (default 0.06)
%  'diastoleWindowEnd'      ... to this time before the pulse (stimulus artifact excluded) [s] (default 0.005)
%  'lockWindow'             a peak is locked to the stimuli if its latency (time since the previous pulse) lies within
%                           +-lockWindow of the typical latency (centre of the densest window of 2 x lockWindow);
%                           certainty and rocker / artifact rules [s] (default 0.1)
%  'lockWindowRel'          at high rates the lock window is at most this fraction of the stimulus interval (certainty;
%                           rocker-only rule) [x stimulus interval] (default 0.2)
%  'certainNoiseRel'        certainty, paced: a locked contraction is certain if its prominence is >= this multiple of
%                           the median rise of the signal before the stimuli [x median rise] (default 2)
%  'certainLargeRel'        certainty, paced: a contraction that is not locked is certain if it is >= this fraction of
%                           the typical amplitude ... [x typical] (default 0.7)
%  'certainLargeNoiseRel'   ... and >= this multiple of the median rise before the stimuli [x median rise] (default 3)
%  'certainUnpacedRel'      certainty, unpaced channels: certain if >= this fraction of the typical amplitude [x
%                           typical] (default 0.5)
%  NOISE / ARTIFACTS
%  'noiseMinInterval'       noise level N: only windows before stimuli that follow an interval of at least this length
%                           [s] (default 0.9)
%  'noiseWindow'            noise level N: window before each such stimulus (at most noiseWindowRel x interval); rise =
%                           maximum minus the running minimum of the signal [s] (default 0.5)
%  'noiseWindowRel'         noise window at most this fraction of the stimulus interval [x interval] (default 0.4)
%  'noisePercentile'        noise level N = this percentile of the rises (the median of the rises is used for the
%                           certainty) [%] (default 90)
%  'noiseMinWindows'        noise level only with at least this many windows (otherwise unknown) [windows] (default 10)
%  'artifactMinCandidates'  artifact gap rule (raises the threshold): needs at least this many peaks above the auto
%                           threshold [peaks] (default 6)
%  'artifactGapRatio'       artifact gap rule: the largest ratio between two consecutive sorted prominences below the
%                           typical amplitude must be >= this value (a clear gap between artifacts and contractions) [x]
%                           (default 1.6)
%  'artifactMaxRel'         artifact gap rule: all peaks of the lower cluster are <= this fraction of the typical
%                           amplitude [x typical] (default 0.5)
%  'artifactMinPeaks'       artifact gap rule: at least this many peaks of the lower cluster are not locked to the
%                           stimuli [peaks] (default 3)
%  'artifactRockerFraction' artifact gap rule: at least this fraction of the lower cluster occurs while the rocker moves
%                           (default 0.75)
%  'chanceMargin'           locked 'more than by chance': fraction locked > chance level (2 x lockWindow / stimulus
%                           interval) + this margin ... (default 0.2)
%  'chanceMax'              ... the limit is at most this fraction (artifact gap rule, partial capture of the rocker
%                           rules) (default 0.6)
%  ROCKER RULES
%  'rockerRuleMinFraction'  rocker rules (b, c): only if the rocker moves during at least this fraction of the data
%                           window (default 0.5)
%  'noiseLockedMax'         rule b (no contractions): fewer than this fraction of the largest peaks (as many as pulses)
%                           locked ... (default 0.5)
%  'noiseAbsMax'            ... and the typical amplitude <= this value ... [uN] (default 50)
%  'noiseRelMax'            ... or <= this multiple of the noise level N with the peaks at the rhythm of the rocker:
%                           rocker / noise peaks [x N] (default 2)
%  'rhythmMinPerCycle'      rhythm of the rocker: at least this many peaks per rocker cycle (rule b) ... [peaks / cycle]
%                           (default 0.7)
%  'rhythmMaxPerCycle'      ... and at most this many, or a median peak interval of 1 or 1/2 rocker period ... [peaks /
%                           cycle] (default 2.2)
%  'rhythmTolerance'        ... within this tolerance (1/2 period: half of it) (default 0.15)
%  'keepNoiseRel'           rule b: locked peaks >= max(keepNoiseRel x N, N + keepNoiseAbs) stay (slices that answer
%                           only some stimuli) ... [x N] (default 1.5)
%  'keepNoiseAbs'           ... (absolute distance from the noise level) ... [uN] (default 50)
%  'keepMinPeaks'           ... if there are at least this many of them ... [peaks] (default 3)
%  'keepMinFraction'        ... and at least this fraction of the pulses, and more of them are locked than by chance
%                           (default 0.05)
%  'dropRel'                rule b: peaks below this multiple of max(typical amplitude, N) are removed (larger peaks are
%                           no rocker artifacts) [x max(typical, N)] (default 3)
%  'smallNoiseRel'          rule c: peaks not locked to the stimuli below min(smallNoiseRel x N, smallTypicalRel x
%                           typical) are removed ... [x N] (default 1.5)
%  'smallTypicalRel'        ... (peaks at the rhythm of the rocker: smallRhythmTypicalRel instead) ... [x typical]
%                           (default 0.5)
%  'smallRhythmMinPerCycle' ... rhythm of the rocker for rule c: at least this many peaks per rocker cycle ... [peaks /
%                           cycle] (default 0.5)
%  'smallRhythmTypicalRel'  ... then the limit is min(smallNoiseRel x N, this fraction of the typical amplitude) [x
%                           typical] (default 1)
%  'rockerOnlyMinIntervals' N unknown (high rates): peaks at the rhythm of the rocker need at least this many peak
%                           intervals ... [intervals] (default 10)
%  'rockerOnlyFraction'     ... of which at least this fraction are 1 or 1/2 rocker period ... (default 0.6)
%  'rockerOnlyTolerance'    ... within this tolerance (1/2 period: half of it) ... (default 0.1)
%  'captureTolerance'       ... and the median interval is no 1:1 or 2:1 multiple of the stimulus interval within this
%                           tolerance (capture at the rocker period cannot be told apart) (default 0.05)
%  SIGNAL
%  'spikeJumpMin'           spike: a jump between two raw samples >= J = max(spikeJumpMin, spikeJumpFactor x median of
%                           the non-zero differences of the channel) ... [AU] (default 50)
%  'spikeJumpFactor'        ... (noise level of the channel) ... [x noise] (default 8)
%  'spikeGroupGap'          jumps closer than this form one group ... [s] (default 0.04)
%  'spikeMaxDuration'       ... that lasts at most this long ... [s] (default 0.1)
%  'spikeLevelWindow'       ... and goes beyond the level before and after it (median of this time) by >= J ... [s]
%                           (default 0.02)
%  'spikeJumpFraction'      ... with the largest jump >= this fraction of its largest deviation (abrupt; a contraction
%                           rises over many samples) (default 0.5)
%  'spikeCoincidence'       within this time of a spike of another channel ... [s] (default 0.01)
%  'spikeCoincidenceFactor' ... the jump threshold is max(spikeJumpMin, this factor x J) (spikes in several channels) [x
%                           J] (default 0.5)
%  ROCKER FILTER
%  'rockerHzPerRpm'         rocker frequency per rpm setting (two setups: 0.02020 and 0.02025 Hz/rpm); rocker rules and
%                           rocker filter [Hz / rpm] (default 0.0202)
%  'rfBandRel'              rocker filter: the rocker frequency is searched within +-this fraction of the expected
%                           frequency (default 0.03)
%  'rfBandNoLog'            rocker filter: search band without rocker speed in the log file [Hz (from to)] (default 0.4
%                           2.2)
%  'rfHarmonics'            rocker filter: number of harmonics of the periodic artifact [harmonics] (default 6)
%  'rfBlock'                rocker filter: block length of the fit (hop = half a block) [s] (default 30)
%  'rfMinRun'               rocker filter: shorter rocker-on periods are not corrected [s] (default 3)
%  'rfKnot'                 rocker filter: knot distance of the baseline (slow drift) fitted together with the artifact
%                           [s] (default 2)
%  'rfSmoothBaseline'       rocker filter: smoothness penalty of the baseline (default 0.1)
%  'rfRidge'                rocker filter: ridge penalty of the harmonics (default 0.001)
%  'rfMinCover'             rocker filter: a block is fitted only if this fraction of the 20 phase bins of the rocker
%                           cycle has >= 5 samples between the contractions (default 0.9)
%  'rfMinR2'                rocker filter: minimum R2 of a block fit (default 0.2)
%  'rfMaxSizeRel'           rocker filter: artifact size of a block at most this multiple of the reference size [x
%                           reference] (default 1.6)
%  'rfMinRefBlock'          rocker filter: reference blocks are at least this long [s] (default 10)
%  'rfMaxBorrow'            rocker filter: a block without own fit uses the artifact of a neighbouring block of the same
%                           rocker period up to this distance [s] (default 60)
%  'rfF0Block'              rocker filter, frequency estimate: blocks of at most this length ... [s] (default 120)
%  'rfF0Blocks'             ... at most this many per channel and rocker speed ... [blocks] (default 6)
%  'rfF0Clear'              ... and the peak of the fit must be clear within +-this fraction (default 0.1)
%  'rfExtendBlock'          rocker filter: blocks without full coverage of the rocker cycle are retried with this length
%                           [s] (default 90)
%  'rfMaskRelax'            rocker filter: the artifact is fitted to the samples between contractions; a contraction is
%                           masked from TTP90 + rfMaskMargin before its peak to rfMaskRelax x TTR90 + rfMaskMargin after
%                           it (medians of the channel) [x TTR90] (default 1.3)
%  'rfMaskMargin'           rocker filter: margin of the contraction masks before and after a contraction [s] (default
%                           0.08)
%  'rfMaskMax'              rocker filter, paced channels (first pass): masked from 20 ms before each pulse to min(next
%                           pulse - 50 ms, this time) after it [s] (default 1.2)
%  PROTOCOLS
%  'frequencyResolution'    grouping by pacing frequency (FFR): stimulus intervals within 2 % form a group, its
%                           frequency (1 / median interval) is rounded to this step at >= 1 Hz; groups with the same
%                           rounded frequency are one group (0.99, 1.0 and 1.001 Hz = 1 Hz). FFR results: the groups at
%                           0.5, 1, 2 and 3 Hz [Hz] (default 0.1)
%  'frequencyResolutionLow' ... below 1 Hz the frequency is rounded to this step (0.49 and 0.5 Hz = 0.5 Hz, 0.74 and
%                           0.75 Hz = 0.75 Hz) [Hz] (default 0.05)
%  'pauseTolerance'         grouping by pause length (post-rest potentiation): pauses (stimulus interval - steady
%                           interval) within this fraction of the shortest pause of a set are one pause length (same
%                           group value and label, numbered #n); PRP15 / 30 / 60: mean of the pauses within this
%                           fraction of 15 / 30 / 60 s (default 0.1)
%  'steadyStateBeats'       FFR protocols: each pacing frequency is summarized from its steady state: the last this many
%                           contractions of the longest run of consecutive stimuli at this frequency (other runs, e.g.
%                           the basic pacing before and after the protocol, are not used), of its longest sequence of
%                           captured stimuli whose previous and next stimuli are captured, too (partial capture, e.g.
%                           2:1, gives no steady state). 0 = all contractions of the frequency (versions <=
%                           1.0.0-beta.3) [contractions] (default 10)
%  'prpReferenceBeats'      PRP reference 'last beats before each pause': number of contractions before the pause
%                           (median) [contractions] (default 6)
%  'irregularCV'            a group (e.g. FFR step) is flagged irregular (summary column irregular) if the coefficient
%                           of variation of the amplitudes of its included contractions (population SD / mean, column
%                           amplitude_CV) exceeds this value: conduction block, alternans or extra beats (default 0.15)
%  'minGroupBeats'          FFR protocols: a note lists the frequencies summarized from fewer included contractions (0 =
%                           no note) [contractions] (default 5)
%  EXPORT
%  'pulseTextMax'           prePulses / postPulses: at most this many pulses (those nearest to the eliciting pulse),
%                           then '&+<number of the others>' [pulses] (default 10)
%
% TS 2026-10-05 (rockerSource, pauseDiastoleWindow 2026-10-07; rockerArtifacts, detection 2026-10-09; onset gate,
% extra pulses, pulse table, advanced settings 2026-10-10; diastolic level, FFR steady state, PRP reference 2026-10-10)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

opts = struct( ...
    'threshold', 'auto', ...
    'relThreshold', 0.3, ...
    'minThreshold', 30, ...
    'minBeatInterval', 0.15, ...
    'rockerArtifacts', true, ...
    'detection', 'sensitive', ...
    'beats', 'all', ...
    'rocker', 'any', ...
    'spikeRemoval', true, ...
    'downsampling', 2, ...
    'medianFilterMs', 50, ...
    'meanFilterMs', 25, ...
    'maxBeatWindow', 3, ...
    'rockerFilter', false, ...
    'rockerFrequency', [], ...
    'referenceBeat', [], ...
    'stimAssignment', 'onset', ...
    'gateMax', 0.15, ...
    'gateCore', 0.06, ...
    'gateTolerance', 0.015, ...
    'ambiguityWindow', 0.01, ...
    'prePulseWindow', 1, ...
    'minStimToPeak', 0.025, ...
    'maxStimToPeak', 'auto', ...
    'stimChannel', [], ...
    'externalTrigger', 'auto', ...
    'pulseTable', true, ...
    'diastolicLevel', 'preStimulusMedian', ...
    'ffrRockerFallback', true, ...
    'prpReference', 'preceding', ...
    'zeroForce', [], ...
    'samplingRate', [], ...
    'nChannels', [], ...
    'extendedSensorMode', 'auto', ...
    'extendedSensorFactor', 3.3, ...
    'calibration', 'auto', ...
    'rockerSource', 'auto', ...
    'rockerLogDelay', 0.27, ...
    'pauseDiastoleWindow', 0.5, ...
    'risePhaseLevel', 0.25, ...
    'steepRiseMargin', 0.005, ...
    'contractionEnd', 90, ...
    'offsetSnap', 0.005, ...
    'pacedMinStimuli', 3, ...
    'pauseMinInterval', 2.5, ...
    'pauseIntervalRatio', 1.5, ...
    'diastoleWindowStart', 0.06, ...
    'diastoleWindowEnd', 0.005, ...
    'lockWindow', 0.1, ...
    'lockWindowRel', 0.2, ...
    'certainNoiseRel', 2, ...
    'certainLargeRel', 0.7, ...
    'certainLargeNoiseRel', 3, ...
    'certainUnpacedRel', 0.5, ...
    'noiseMinInterval', 0.9, ...
    'noiseWindow', 0.5, ...
    'noiseWindowRel', 0.4, ...
    'noisePercentile', 90, ...
    'noiseMinWindows', 10, ...
    'artifactMinCandidates', 6, ...
    'artifactGapRatio', 1.6, ...
    'artifactMaxRel', 0.5, ...
    'artifactMinPeaks', 3, ...
    'artifactRockerFraction', 0.75, ...
    'chanceMargin', 0.2, ...
    'chanceMax', 0.6, ...
    'rockerRuleMinFraction', 0.5, ...
    'noiseLockedMax', 0.5, ...
    'noiseAbsMax', 50, ...
    'noiseRelMax', 2, ...
    'rhythmMinPerCycle', 0.7, ...
    'rhythmMaxPerCycle', 2.2, ...
    'rhythmTolerance', 0.15, ...
    'keepNoiseRel', 1.5, ...
    'keepNoiseAbs', 50, ...
    'keepMinPeaks', 3, ...
    'keepMinFraction', 0.05, ...
    'dropRel', 3, ...
    'smallNoiseRel', 1.5, ...
    'smallTypicalRel', 0.5, ...
    'smallRhythmMinPerCycle', 0.5, ...
    'smallRhythmTypicalRel', 1, ...
    'rockerOnlyMinIntervals', 10, ...
    'rockerOnlyFraction', 0.6, ...
    'rockerOnlyTolerance', 0.1, ...
    'captureTolerance', 0.05, ...
    'spikeJumpMin', 50, ...
    'spikeJumpFactor', 8, ...
    'spikeGroupGap', 0.04, ...
    'spikeMaxDuration', 0.1, ...
    'spikeLevelWindow', 0.02, ...
    'spikeJumpFraction', 0.5, ...
    'spikeCoincidence', 0.01, ...
    'spikeCoincidenceFactor', 0.5, ...
    'rockerHzPerRpm', 0.0202, ...
    'rfBandRel', 0.03, ...
    'rfBandNoLog', {[0.4 2.2]}, ...
    'rfHarmonics', 6, ...
    'rfBlock', 30, ...
    'rfMinRun', 3, ...
    'rfKnot', 2, ...
    'rfSmoothBaseline', 0.1, ...
    'rfRidge', 0.001, ...
    'rfMinCover', 0.9, ...
    'rfMinR2', 0.2, ...
    'rfMaxSizeRel', 1.6, ...
    'rfMinRefBlock', 10, ...
    'rfMaxBorrow', 60, ...
    'rfF0Block', 120, ...
    'rfF0Blocks', 6, ...
    'rfF0Clear', 0.1, ...
    'rfExtendBlock', 90, ...
    'rfMaskRelax', 1.3, ...
    'rfMaskMargin', 0.08, ...
    'rfMaskMax', 1.2, ...
    'frequencyResolution', 0.1, ...
    'frequencyResolutionLow', 0.05, ...
    'pauseTolerance', 0.1, ...
    'steadyStateBeats', 10, ...
    'prpReferenceBeats', 6, ...
    'irregularCV', 0.15, ...
    'minGroupBeats', 5, ...
    'pulseTextMax', 10);

args = varargin;
if ~isempty(args) && isstruct(args{1})
    given = args{1};
    f = fieldnames(given);
    for k = 1:numel(f)
        opts.(f{k}) = given.(f{k});
    end
    args = args(2:end);
end

names = fieldnames(opts);
i = 1;
while i <= numel(args)
    key = args{i};
    if ~(ischar(key) || isstring(key))
        error('mda_options: option name expected at position %d.', i);
    end
    key = char(key);
    if strcmpi(key,'noFiltering')
        opts.medianFilterMs = 0;
        opts.meanFilterMs = 0;
        i = i + 1;
        continue;
    end
    if strcmpi(key, 'settings')                     %settings file (mda_settings), later names override it
        if i == numel(args), error('mda_options: no file given for ''settings''.'); end
        St = mda_settings('load', args{i+1});
        for f2 = fieldnames(St)'
            if ~strcmp(f2{1}, 'referenceBeat'), opts.(f2{1}) = St.(f2{1}); end
        end
        i = i + 2;
        continue;
    end
    k = find(strcmpi(key,names),1);
    if isempty(k)
        error('mda_options: unknown option ''%s''. Valid options: %s, noFiltering.', key, strjoin(names',', '));
    end
    if i == numel(args)
        error('mda_options: no value given for option ''%s''.', key);
    end
    opts.(names{k}) = args{i+1};
    i = i + 2;
end

% checks
thr0 = opts.threshold;
if isempty(thr0) || ((ischar(thr0) || isstring(thr0)) && strlength(strtrim(string(thr0))) == 0)
    opts.threshold = 'auto';
elseif ischar(thr0) || isstring(thr0)
    if ~strcmpi(thr0,'auto'), error('mda_options: ''threshold'' must be ''auto'' or a number.'); end
    opts.threshold = 'auto';
elseif ~isnumeric(opts.threshold) || any(opts.threshold(:) <= 0)
    error('mda_options: ''threshold'' must be ''auto'', a positive number or one number per channel (NaN = auto).');
end
opts.detection = lower(char(opts.detection));
if ~ismember(opts.detection, {'sensitive', 'specific'})
    error('mda_options: ''detection'' must be ''sensitive'' or ''specific''.');
end
opts.beats = lower(char(opts.beats));
if ~ismember(opts.beats,{'all','stimulated'}), error('mda_options: ''beats'' must be ''all'' or ''stimulated''.'); end
opts.rocker = lower(char(opts.rocker));
if ~ismember(opts.rocker,{'any','stopped','moving'}), error('mda_options: ''rocker'' must be ''any'', ''stopped'' or ''moving''.'); end
if ischar(opts.maxStimToPeak) || isstring(opts.maxStimToPeak)
    opts.maxStimToPeak = 'auto';
end
opts.downsampling = max(1,round(opts.downsampling));
opts.externalTrigger = lower(char(opts.externalTrigger));
if ~ismember(opts.externalTrigger, {'auto', 'on', 'off'}), error('mda_options: ''externalTrigger'' must be ''auto'', ''on'' or ''off''.'); end
opts.rockerSource = lower(char(opts.rockerSource));
if ~ismember(opts.rockerSource,{'auto','status','log'}), error('mda_options: ''rockerSource'' must be ''auto'', ''status'' or ''log''.'); end
opts.rockerArtifacts = isequal(opts.rockerArtifacts, true) || isequal(opts.rockerArtifacts, 1) || ...
    ((ischar(opts.rockerArtifacts) || isstring(opts.rockerArtifacts)) && any(strcmpi(opts.rockerArtifacts, {'on','true'})));
opts.rockerFilter = isequal(opts.rockerFilter, true) || isequal(opts.rockerFilter, 1) || ...
    ((ischar(opts.rockerFilter) || isstring(opts.rockerFilter)) && any(strcmpi(opts.rockerFilter, {'on','true'})));
opts.spikeRemoval = isequal(opts.spikeRemoval, true) || isequal(opts.spikeRemoval, 1) || ...
    ((ischar(opts.spikeRemoval) || isstring(opts.spikeRemoval)) && any(strcmpi(opts.spikeRemoval, {'on','true'})));
if ~isempty(opts.referenceBeat) && ~isstruct(opts.referenceBeat)
    error('mda_options: ''referenceBeat'' must be [] or a reference from mda_referenceBeat.');
end
if ~(isnumeric(opts.pauseDiastoleWindow) && isscalar(opts.pauseDiastoleWindow) && opts.pauseDiastoleWindow > 0)
    error('mda_options: ''pauseDiastoleWindow'' must be a positive number of seconds (Inf = off).');
end
opts.calibration = lower(char(opts.calibration));
if ~ismember(opts.calibration,{'auto','none'}), error('mda_options: ''calibration'' must be ''auto'' or ''none''.'); end
opts.stimAssignment = lower(char(opts.stimAssignment));
if ~ismember(opts.stimAssignment, {'onset', 'peak'})
    error('mda_options: ''stimAssignment'' must be ''onset'' or ''peak''.');
end
for nm = {'gateMax', 'gateCore', 'gateTolerance', 'ambiguityWindow', 'prePulseWindow'}
    v = opts.(nm{1});
    if ~(isnumeric(v) && isscalar(v) && v >= 0 && ~isnan(v))
        error('mda_options: ''%s'' must be a number of seconds >= 0.', nm{1});
    end
    opts.(nm{1}) = double(v);
end
if opts.gateCore > opts.gateMax, opts.gateCore = opts.gateMax; end
% advanced settings (2026-10-10)
for nm = {'risePhaseLevel', 'artifactRockerFraction', 'chanceMargin', 'chanceMax', ...
        'rockerRuleMinFraction', 'noiseLockedMax', 'rhythmTolerance', 'keepMinFraction', 'rockerOnlyFraction', ...
        'rockerOnlyTolerance', 'captureTolerance', 'spikeJumpFraction', 'rfBandRel', 'rfMinCover', 'rfMinR2', ...
        'rfF0Clear', 'pauseTolerance'}
    v = opts.(nm{1});
    if ~(isnumeric(v) && isscalar(v) && ~isnan(v)), v = nan; end
    if ~(v >= 0 && v <= 1), error('mda_options: ''%s'' must be a number from 0 to 1.', nm{1}); end
    opts.(nm{1}) = double(v);
end
for nm = {'steepRiseMargin', 'offsetSnap', 'pauseMinInterval', 'pauseIntervalRatio', 'diastoleWindowEnd', ...
        'certainNoiseRel', 'certainLargeRel', 'certainLargeNoiseRel', 'certainUnpacedRel', 'noiseMinInterval', ...
        'artifactMaxRel', 'noiseAbsMax', 'noiseRelMax', 'rhythmMinPerCycle', 'keepNoiseRel', 'keepNoiseAbs', ...
        'dropRel', 'smallNoiseRel', 'smallTypicalRel', 'smallRhythmMinPerCycle', 'smallRhythmTypicalRel', ...
        'spikeJumpFactor', 'spikeGroupGap', 'spikeCoincidence', 'rfMinRun', 'rfSmoothBaseline', 'rfRidge', ...
        'rfMinRefBlock', 'rfMaxBorrow', 'rfMaskMargin', 'irregularCV'}
    v = opts.(nm{1});
    if ~(isnumeric(v) && isscalar(v) && ~isnan(v)), v = nan; end
    if ~(v >= 0), error('mda_options: ''%s'' must be a number >= 0.', nm{1}); end
    opts.(nm{1}) = double(v);
end
for nm = {'contractionEnd', 'noisePercentile'}
    v = opts.(nm{1});
    if ~(isnumeric(v) && isscalar(v) && ~isnan(v)), v = nan; end
    if ~(v >= 0 && v <= 100), error('mda_options: ''%s'' must be a number from 0 to 100.', nm{1}); end
    opts.(nm{1}) = double(v);
end
for nm = {'pacedMinStimuli', 'noiseMinWindows', 'artifactMinCandidates', 'artifactMinPeaks', ...
        'rockerOnlyMinIntervals', 'rfHarmonics', 'rfF0Blocks', 'prpReferenceBeats', 'pulseTextMax'}
    v = opts.(nm{1});
    if ~(isnumeric(v) && isscalar(v) && ~isnan(v)), v = nan; end
    if ~(v >= 1 && v == round(v)), error('mda_options: ''%s'' must be an integer >= 1.', nm{1}); end
    opts.(nm{1}) = double(v);
end
for nm = {'diastoleWindowStart', 'lockWindow', 'lockWindowRel', 'noiseWindow', 'noiseWindowRel', ...
        'artifactGapRatio', 'rhythmMaxPerCycle', 'spikeJumpMin', 'spikeMaxDuration', 'spikeLevelWindow', ...
        'spikeCoincidenceFactor', 'rockerHzPerRpm', 'rfBlock', 'rfKnot', 'rfMaxSizeRel', 'rfF0Block', ...
        'rfExtendBlock', 'rfMaskRelax', 'rfMaskMax', 'frequencyResolution', 'frequencyResolutionLow'}
    v = opts.(nm{1});
    if ~(isnumeric(v) && isscalar(v) && ~isnan(v)), v = nan; end
    if ~(v > 0), error('mda_options: ''%s'' must be a number > 0.', nm{1}); end
    opts.(nm{1}) = double(v);
end
for nm = {'keepMinPeaks', 'steadyStateBeats', 'minGroupBeats'}
    v = opts.(nm{1});
    if ~(isnumeric(v) && isscalar(v) && ~isnan(v)), v = nan; end
    if ~(v >= 0 && v == round(v)), error('mda_options: ''%s'' must be an integer >= 0.', nm{1}); end
    opts.(nm{1}) = double(v);
end
v = double(opts.rfBandNoLog(:)');
if ~(isnumeric(v) && numel(v) == 2 && all(v > 0) && v(2) > v(1))
    error('mda_options: ''rfBandNoLog'' must be two increasing numbers > 0.');
end
opts.rfBandNoLog = v;
opts.pulseTable = isequal(opts.pulseTable, true) || isequal(opts.pulseTable, 1) || ...
    ((ischar(opts.pulseTable) || isstring(opts.pulseTable)) && any(strcmpi(opts.pulseTable, {'on','true'})));
% 2026-10-10: diastolic level, FFR steps without rocker stop, PRP reference
vals = {'preStimulusMedian', 'minimum'};
k = find(strcmpi(char(opts.diastolicLevel), vals), 1);
if isempty(k), error('mda_options: ''diastolicLevel'' must be ''preStimulusMedian'' or ''minimum''.'); end
opts.diastolicLevel = vals{k};
if opts.diastoleWindowEnd >= opts.diastoleWindowStart
    error('mda_options: ''diastoleWindowEnd'' must be smaller than ''diastoleWindowStart''.');
end
opts.ffrRockerFallback = isequal(opts.ffrRockerFallback, true) || isequal(opts.ffrRockerFallback, 1) || ...
    ((ischar(opts.ffrRockerFallback) || isstring(opts.ffrRockerFallback)) && any(strcmpi(opts.ffrRockerFallback, {'on','true'})));
vals = {'preceding', 'firstTrain', 'steady'};
k = find(strcmpi(char(opts.prpReference), vals), 1);
if isempty(k), error('mda_options: ''prpReference'' must be ''preceding'', ''firstTrain'' or ''steady''.'); end
opts.prpReference = vals{k};
end
