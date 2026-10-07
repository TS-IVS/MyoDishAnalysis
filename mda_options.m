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
%
% SELECTION OF CONTRACTIONS (the excluded ones stay in the table with included = false)
%   'beats'            'all' (default) | 'stimulated' (only contractions that follow a stimulus of the channel)
%   'rocker'           'any' (default) | 'stopped' (rocker at rest from F_dia to 90 % relaxation) | 'moving'
%
% SIGNAL PROCESSING (defaults = GetContractionParameters / analyzeMyoDish of the Seidel lab)
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
% STIMULUS ASSIGNMENT
%   'minStimToPeak'    a peak earlier than this after a stimulus is not caused by it [s] (default 0.025)
%   'maxStimToPeak'    'auto' (default: min(stimulus interval, 1 s); 0.9 s if unknown) or a number [s]
%   'stimChannel'      stimulus channel of the analysed data channel ([] = same number; single channel files:
%                      the channel that was stimulated)
%
% DIASTOLIC FORCE
%   'zeroForce'        sensor signal without load [uN] for diastolicForce = F_dia - zeroForce ([] = 'Offset' entry of
%                      the channel in the log file; NaN = from the log file). MyoDishAnalysis: one value per
%                      channel or one for all channels
%   'pauseDiastoleWindow' after a stimulation pause (stimulus interval >= 2.5 s and >= 1.5 x the interval before),
%                      F_dia is searched only from this time before the stimulus to the peak [s] (default 0.5;
%                      Inf = from the previous peak or maxBeatWindow, as for all other contractions). F_dia and the
%                      rocker state then do not depend on drift or rocker movement during the pause
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
% TS 2026-10-05 (rockerSource, pauseDiastoleWindow 2026-10-07)

opts = struct( ...
    'threshold', 'auto', ...
    'relThreshold', 0.3, ...
    'minThreshold', 30, ...
    'minBeatInterval', 0.15, ...
    'beats', 'all', ...
    'rocker', 'any', ...
    'downsampling', 2, ...
    'medianFilterMs', 50, ...
    'meanFilterMs', 25, ...
    'maxBeatWindow', 3, ...
    'rockerFilter', false, ...
    'rockerFrequency', [], ...
    'referenceBeat', [], ...
    'minStimToPeak', 0.025, ...
    'maxStimToPeak', 'auto', ...
    'stimChannel', [], ...
    'zeroForce', [], ...
    'samplingRate', [], ...
    'nChannels', [], ...
    'extendedSensorMode', 'auto', ...
    'extendedSensorFactor', 3.3, ...
    'calibration', 'auto', ...
    'rockerSource', 'auto', ...
    'rockerLogDelay', 0.27, ...
    'pauseDiastoleWindow', 0.5);

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
opts.beats = lower(char(opts.beats));
if ~ismember(opts.beats,{'all','stimulated'}), error('mda_options: ''beats'' must be ''all'' or ''stimulated''.'); end
opts.rocker = lower(char(opts.rocker));
if ~ismember(opts.rocker,{'any','stopped','moving'}), error('mda_options: ''rocker'' must be ''any'', ''stopped'' or ''moving''.'); end
if ischar(opts.maxStimToPeak) || isstring(opts.maxStimToPeak)
    opts.maxStimToPeak = 'auto';
end
opts.downsampling = max(1,round(opts.downsampling));
opts.rockerSource = lower(char(opts.rockerSource));
if ~ismember(opts.rockerSource,{'auto','status','log'}), error('mda_options: ''rockerSource'' must be ''auto'', ''status'' or ''log''.'); end
opts.rockerFilter = isequal(opts.rockerFilter, true) || isequal(opts.rockerFilter, 1) || ...
    ((ischar(opts.rockerFilter) || isstring(opts.rockerFilter)) && any(strcmpi(opts.rockerFilter, {'on','true'})));
if ~isempty(opts.referenceBeat) && ~isstruct(opts.referenceBeat)
    error('mda_options: ''referenceBeat'' must be [] or a reference from mda_referenceBeat.');
end
if ~(isnumeric(opts.pauseDiastoleWindow) && isscalar(opts.pauseDiastoleWindow) && opts.pauseDiastoleWindow > 0)
    error('mda_options: ''pauseDiastoleWindow'' must be a positive number of seconds (Inf = off).');
end
opts.calibration = lower(char(opts.calibration));
if ~ismember(opts.calibration,{'auto','none'}), error('mda_options: ''calibration'' must be ''auto'' or ''none''.'); end
end
