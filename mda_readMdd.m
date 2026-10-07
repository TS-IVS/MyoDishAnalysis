function S = mda_readMdd(mddFile, fromSeconds, toSeconds, opts, progressFcn)
%MDA_READMDD  Read a MyoDish .mdd file (force data, stimulus pulses, rocker state).
%
%   H = mda_readMdd(mddFile)                         file facts only (no data)
%   S = mda_readMdd(H, fromSeconds, toSeconds, opts) data, with the file facts H of an earlier call (faster: the
%                                                     log file is not read again; same opts as for H)
%   S = mda_readMdd(mddFile, fromSeconds, toSeconds) data between fromSeconds and toSeconds (time in the file)
%   S = mda_readMdd(mddFile, fromSeconds, toSeconds, opts)   opts from mda_options
%   O = mda_readMdd(mddFile, 'overview', binSeconds, opts, progressFcn)
%                                                     min/max of every channel per bin of the whole file
%   O = mda_readMdd(mddFile, 'overview', [binSeconds fromSeconds toSeconds], ...)   only this part of the file
%
% FILE FORMAT (MyoDish software; facts from the Seidel lab's importMyoDishData)
%   - int16, little endian, channels interleaved. Standard: 8 force channels + 1 stimulus/status channel
%     at 400 Hz (7200 bytes per second). Since MyoDish software 2.0.9708 (07/2026) a file may contain only
%     the recorded channel(s) + the status channel (single channel mode: 2 x int16 per sample).
%     Old files (2020/21, software 1.0.x): 8 force channels at 500 Hz, no status channel.
%   - sampling rate, recording duration (--> number of channels) and extended sensor mode are read from the
%     log file <name>_log.log (UTF-16) next to the .mdd file.
%   - the values in the file are arbitrary units (AU). They are converted to uN with the 'Calibration' entry of each
%     channel in the log file (AU per mN, a kind of spring constant; 1000: AU = uN, 3000: AU / 3 = uN). While the
%     extended sensor mode is on (log event 'extended sensor mode on', also before the recording, until '... off'),
%     the calibration value is divided by 3.3 (1000 --> AU x 3.3). See mda_calibrationFactor. Option
%     'calibration','none' keeps the values as stored in the file (AU, no extended sensor mode factor).
%   - status channel, bits (1-based): 1-8 stimulus current [mA], 9 current not reached, 10-13 stimulated
%     channel, 14 external trigger, 15 rocker moving (set in every sample while the rocker moves),
%     16 extra pulse. A stimulus pulse is a sample with any bit other than bit 15 set.
%
% OUTPUT (S)
%   file facts: file, logFile, samplingRate, nChannelsInFile, dataChannels, hasStimChannel, totalSeconds,
%               recordingStart (datenum of file time 0, NaN if unknown), extendedSensorIntervals, notes,
%               offsetLog / calibrationLog ([time channel value] of the 'Offset' / 'Calibration' entries of the log;
%               time -Inf = logged before the recording start), calibrationApplied, extendedSensorFactor
%   data:       t (1 x n, s; centre of the averaged raw samples, first raw sample = 0 s), dt,
%               force (numel(dataChannels) x n, uN), rockerOn (1 x n logical),
%               stim (struct with fields time, channel, current, currentReached, external, isExtraPulse,
%               rockerOn; one entry per stimulus pulse of any channel)
%   Single channel files: force has one row = channel 1, stim.channel keeps the physical channel number.
%
% TS 2026-10-05 (condensed from importMyoDishData, readRecordingInfoFromMyoDishLogFile,
% readSamplingRateFromMyoDishLogFile; identical data and stimulus times)

if nargin < 3, toSeconds = []; end
if nargin < 4 || isempty(opts), opts = mda_options(); end
if nargin < 5, progressFcn = []; end

if isstruct(mddFile)            %file facts of an earlier call (same options): the log file is not read again
    S = mddFile;
else
    S = readHeader(char(mddFile), opts);
end

if nargin < 2 || isempty(fromSeconds)
    return; %header only
end
if ischar(fromSeconds) && strcmpi(fromSeconds,'overview')
    binSeconds = toSeconds; tRange = [];
    if numel(binSeconds) == 3, tRange = binSeconds(2:3); binSeconds = binSeconds(1); end
    if isempty(binSeconds), binSeconds = max(1, S.totalSeconds / 20000); end
    S = readOverview(S, binSeconds, progressFcn, tRange);
    return;
end
S = readData(S, fromSeconds, toSeconds, opts.downsampling);
end


% =====================================================================================================
function H = readHeader(mddFile, opts)
if ~exist(mddFile,'file')
    error('mda_readMdd: file not found: %s', mddFile);
end
d = dir(mddFile);
H.file = fullfile(d.folder, d.name);
H.bytes = d.bytes;
[p, n] = fileparts(H.file);
H.logFile = fullfile(p, [n '_log.log']);
H.notes = {};

L = readLog(H.logFile);
H.recordingStart = L.startDatenum;
H.programVersion = L.programVersion;
H.offsetLog = L.offsetEvents;          %[time channel value]: sensor signal without load ('Offset' entries)
H.calibrationLog = L.calibrationEvents; %[time channel value]: 'Calibration' entries (AU per mN)
H.rockerSpeedLog = L.rockerSpeedEvents; %[time rpm]: 'rockerSpeed' entries (0 = stop)

% sampling rate: option > log file > 500 Hz for old 8-channel files (software 1.0.x) > 400 Hz
if ~isempty(opts.samplingRate)
    fs = opts.samplingRate;  src = 'option';
elseif ~isnan(L.samplingRate)
    fs = L.samplingRate;     src = 'log file';
elseif (~isempty(opts.nChannels) && opts.nChannels == 8) || L.nChannelsController == 8
    fs = 500;                src = 'assumed (old 8-channel file)';
else
    fs = 400;                src = 'assumed';
end
H.samplingRate = fs;
H.samplingRateSource = src;
if ~strcmp(src,'log file') && ~strcmp(src,'option')
    H.notes{end+1} = sprintf('No sampling rate in the log file: %g Hz assumed.', fs);
end

% number of int16 channels in the file: option > file size / recording duration > single channel mode > 9
if ~isempty(opts.nChannels)
    nCh = opts.nChannels;
else
    nCh = [];
    if ~isnan(L.recordingDuration) && L.recordingDuration > 5
        nEst = H.bytes / (2 * fs * L.recordingDuration);
        if abs(nEst - round(nEst)) < 0.1 && round(nEst) >= 2 && round(nEst) <= 9
            nCh = round(nEst);
        else
            H.notes{end+1} = sprintf('File size does not fit the recording duration in the log file (%.2f channels).', nEst);
        end
    elseif isequal(L.singleChannelMode, true)
        nCh = 2;
    end
    if isempty(nCh) && isnan(L.samplingRate) && L.nChannelsController == 8
        nCh = 8;   %old 8-channel file (500 Hz, no status channel)
    end
    if isempty(nCh)
        % no usable log information: the status channel (last channel) contains almost only 0 or the rocker
        % bit (16384); test 9 channels first, then single channel mode (2), then the others
        nCh = 9;
        for cand = [9 2 3 4 5 6 7 8]
            if statusFraction(H.file, cand) > 0.95
                nCh = cand;
                break;
            end
        end
        H.notes{end+1} = sprintf('%d channels in the file (from the content of the status channel).', nCh);
    end
end
H.nChannelsInFile = nCh;

% status (stimulus) channel = last channel, except in legacy 8-channel files (500 Hz / nChannels;8 in the log)
isLegacy = isnan(L.samplingRate) || L.samplingRate == 500 || L.nChannelsController == 8;
if nCh == 8 && isLegacy
    H.hasStimChannel = false;
    H.dataChannels = 1:8;
elseif nCh >= 9
    H.hasStimChannel = true;
    H.dataChannels = 1:8;
else
    H.hasStimChannel = true;
    H.dataChannels = 1:(nCh-1);
end
H.stimRow = nCh;
H.totalSamples = floor(H.bytes / (2 * nCh));
H.totalSeconds = H.totalSamples / fs;

% extended sensor mode: intervals [from to] (s) in which the calibration value is divided by 3.3
ext = zeros(0,2);
if ischar(opts.extendedSensorMode) || isstring(opts.extendedSensorMode)
    ev = L.extendedSensorModeEvents;
    for k = 1:size(ev,1)
        if ev(k,2) == 1 && (isempty(ext) || ~isinf(ext(end,2)))
            ext(end+1,:) = [ev(k,1) inf]; %#ok<AGROW>
        elseif ev(k,2) == 0 && ~isempty(ext) && isinf(ext(end,2))
            ext(end,2) = ev(k,1);
        end
    end
elseif opts.extendedSensorMode
    ext = [-inf inf];
end
H.extendedSensorIntervals = ext(ext(:,2) > ext(:,1), :);
H.extendedSensorFactor = opts.extendedSensorFactor;

% calibration (AU per mN) --> factor 1000 / calibration per data channel (step function of time, mda_calibrationFactor)
H.calibrationApplied = strcmp(opts.calibration, 'auto');
if H.calibrationApplied
    C = H.calibrationLog;
    C = C(ismember(C(:,2), H.dataChannels) & C(:,3) > 0, :);
    odd = unique(C(C(:,3) ~= 1000, 2))';
    if ~isempty(odd)
        H.notes{end+1} = sprintf('Calibration %s AU/mN in channel(s) %s: data converted to uN (AU x 1000 / calibration).', ...
            mat2str(unique(C(C(:,3) ~= 1000, 3))'), mat2str(odd));
    end
    if ~isempty(H.extendedSensorIntervals)
        H.notes{end+1} = sprintf('Extended sensor mode on (%s s): calibration / %g.', ...
            mat2str(H.extendedSensorIntervals, 6), H.extendedSensorFactor);
    end
else
    H.notes{end+1} = 'Calibration not applied: force values in arbitrary units (AU) as stored in the file.';
end
end


% =====================================================================================================
function S = readData(S, fromSeconds, toSeconds, nDS)
fs = S.samplingRate;
nCh = S.nChannelsInFile;
if fromSeconds < 0, fromSeconds = S.totalSeconds + fromSeconds; end
if toSeconds < 0,   toSeconds = S.totalSeconds + toSeconds;     end
i0 = max(0, floor(fromSeconds * fs / nDS) * nDS);          %first raw sample (0-based), on the nDS grid
i1 = min(S.totalSamples, ceil(toSeconds * fs));             %raw sample after the last one
nRaw = floor(max(0, i1 - i0) / nDS) * nDS;

fid = fopen(S.file, 'r', 'ieee-le');
if fid < 0, error('mda_readMdd: cannot open %s', S.file); end
cleaner = onCleanup(@() fclose(fid));
fseek(fid, i0 * nCh * 2, 'bof');
raw = fread(fid, [nCh nRaw], 'int16=>int16');
nRaw = size(raw,2);
nRaw = floor(nRaw / nDS) * nDS;
raw = raw(:,1:nRaw);

n = nRaw / nDS;
S.fromSeconds = i0 / fs;
S.toSeconds = (i0 + nRaw) / fs;
S.dt = nDS / fs;
S.downsampling = nDS;
S.t = ((i0 + (0:n-1) * nDS) + (nDS - 1) / 2) / fs;          %centre of the averaged raw samples

% force channels: mean of nDS samples (nDS = 2: identical to the median used by importMyoDishData)
nData = numel(S.dataChannels);
S.force = zeros(nData, n);
for c = 1:nData
    x = double(raw(c,:));
    if nDS == 2
        x = (x(1:2:end) + x(2:2:end)) / 2;
    elseif nDS > 2
        x = median(reshape(x, nDS, n), 1);
    end
    S.force(c,:) = x;
end
for c = 1:nData                                    %AU --> uN (calibration, extended sensor mode)
    S.force(c,:) = S.force(c,:) .* mda_calibrationFactor(S, S.dataChannels(c), S.t);
end

% status channel: stimulus pulses and rocker state
S.stim = struct('time',zeros(0,1),'channel',zeros(0,1),'current',zeros(0,1),'currentReached',false(0,1), ...
    'external',false(0,1),'isExtraPulse',false(0,1),'rockerOn',false(0,1));
S.rockerOn = false(1,n);
if S.hasStimChannel && nRaw > 0
    code = typecast(raw(S.stimRow,:), 'uint16');
    rockerBit = bitand(code, uint16(16384)) ~= 0;                 %bit 15
    idx = find(bitand(code, uint16(49151)) ~= 0);                 %any bit except bit 15 = stimulus pulse
    pc = code(idx);
    ch = double(bitand(bitshift(pc, -9), uint16(15)));            %bits 10-13
    ch(ch > 8) = ch(ch > 8) - 8;
    ch(ch == 0) = 8;
    S.stim.time = ((i0 + idx(:) - 1) / fs);
    S.stim.channel = ch(:);
    S.stim.current = double(bitand(pc(:), uint16(255)));          %bits 1-8 [mA]
    S.stim.currentReached = bitand(pc(:), uint16(256)) == 0;      %bit 9
    S.stim.external = bitand(pc(:), uint16(8192)) ~= 0;           %bit 14
    S.stim.isExtraPulse = bitand(pc(:), uint16(32768)) ~= 0;      %bit 16
    S.stim.rockerOn = reshape(rockerBit(idx), [], 1);

    % rocker state of every (downsampled) sample. In older firmware the rocker bit may only be set in the
    % stimulus pulses: then the state of the last pulse (any channel) is held until the next pulse.
    if nnz(rockerBit) > 2 * nnz(S.stim.rockerOn)
        S.rockerOn = any(reshape(rockerBit, nDS, n), 1);
    elseif any(S.stim.rockerOn)
        isPulse = false(1, nRaw);
        isPulse(idx) = true;
        lastPulse = cumsum(isPulse);                              %number of the last pulse at/before a sample
        pulseState = [false; S.stim.rockerOn(:)];
        state = reshape(pulseState(lastPulse + 1), 1, []);
        S.rockerOn = any(reshape(state, nDS, n), 1);
        S.notes{end+1} = 'Rocker state taken from the stimulus pulses (rocker bit not set continuously).';
    end
end
end


% =====================================================================================================
function O = readOverview(S, binSeconds, progressFcn, tRange)
% min/max of every data channel per bin over the whole file or the part tRange = [from to] (s) (chunk-wise)
fs = S.samplingRate;
nCh = S.nChannelsInFile;
binSamples = max(1, round(binSeconds * fs));
chunkBins = max(1, floor(600 * fs / binSamples));             %about 10 min per read
chunkSamples = chunkBins * binSamples;
if nargin < 4 || isempty(tRange)
    s0 = 0; s1 = S.totalSamples;
else
    s0 = min(S.totalSamples, max(0, floor(tRange(1) * fs))); s1 = min(S.totalSamples, ceil(tRange(2) * fs));
end
nSamples = max(0, s1 - s0);
nBins = ceil(nSamples / binSamples);
nData = numel(S.dataChannels);
O = S;
O.binSeconds = binSamples / fs;
O.tBin = (s0 + ((0:nBins-1) + 0.5) * binSamples) / fs;
O.minForce = nan(nData, nBins);
O.maxForce = nan(nData, nBins);
O.rockerFraction = zeros(1, nBins);

fid = fopen(S.file, 'r', 'ieee-le');
if fid < 0, error('mda_readMdd: cannot open %s', S.file); end
cleaner = onCleanup(@() fclose(fid));
fseek(fid, s0 * nCh * 2, 'bof');
b0 = 0;
while b0 < nBins
    raw = fread(fid, [nCh min(chunkSamples, nSamples - b0 * binSamples)], 'int16=>int16'); %complete samples only
    m = size(raw,2);
    if m == 0, break; end
    nb = ceil(m / binSamples);
    pad = nb * binSamples - m;
    for c = 1:nData
        x = double(raw(c,:));
        x(end+1:end+pad) = nan;
        X = reshape(x, binSamples, nb);
        O.minForce(c, b0+(1:nb)) = min(X, [], 1);
        O.maxForce(c, b0+(1:nb)) = max(X, [], 1);
    end
    if S.hasStimChannel
        r = double(bitand(typecast(raw(S.stimRow,:),'uint16'), uint16(16384)) ~= 0);
        r(end+1:end+pad) = nan;
        O.rockerFraction(b0+(1:nb)) = mean(reshape(r, binSamples, nb), 1, 'omitnan');
    end
    b0 = b0 + nb;
    if ~isempty(progressFcn), progressFcn(min(1, b0 / nBins)); end
end
for c = 1:nData                                    %AU --> uN (calibration, extended sensor mode)
    kc = mda_calibrationFactor(S, S.dataChannels(c), O.tBin);
    O.minForce(c,:) = O.minForce(c,:) .* kc;
    O.maxForce(c,:) = O.maxForce(c,:) .* kc;
end
end


% =====================================================================================================
function q = statusFraction(file, nCh)
% fraction of the values of the last channel (status channel if nCh is correct) that are 0 or 16384
fid = fopen(file, 'r', 'ieee-le');
raw = fread(fid, [nCh 20000], 'int16=>int16');
fclose(fid);
if size(raw,2) < 100, q = 0; return; end
v = raw(nCh,:);
q = mean(v == 0 | v == 16384);
if all(raw(:) == 0), q = 0; end
end


% =====================================================================================================
function L = readLog(logFile)
% the facts needed from the MyoDish log file (lines: systemTime;dataLogTime_ms;channel;code;value)
L = struct('samplingRate',nan,'recordingDuration',nan,'nChannelsController',nan,'singleChannelMode',[], ...
    'extendedSensorModeEvents',zeros(0,2),'startDatenum',nan,'programVersion','', ...
    'offsetEvents',zeros(0,3),'calibrationEvents',zeros(0,3),'rockerSpeedEvents',zeros(0,2));
if ~exist(logFile,'file'), return; end
% MyoDish logs are UTF-16 little endian (with byte order mark); converted copies may be UTF-8
fid = fopen(logFile, 'r');
if fid < 0, return; end
b = fread(fid, inf, 'uint8=>uint8')';
fclose(fid);
if numel(b) >= 4 && ((b(1) == 255 && b(2) == 254) || (b(2) == 0 && b(4) == 0))
    if b(1) == 255, b = b(3:end); end
    b = b(1:2*floor(numel(b)/2));
    txt = char(double(b(1:2:end)) + 256 * double(b(2:2:end)));
else
    txt = native2unicode(b, 'UTF-8');
end
lines = regexp(txt, '\r?\n', 'split');
nValid = 0;
tStart = nan; tStop = nan; tStartPar = nan; tStopPar = nan;
sysStart = ''; sysStartPar = ''; sysFirst = ''; tFirst = nan;
ext = zeros(0,3); offs = zeros(0,4); cal = zeros(0,4); rck = zeros(0,3);  %last column: line number
lineStart = nan; lineStartPar = nan;
for i = 1:numel(lines)
    f = strsplit(lines{i}, ';');
    if numel(f) < 5, continue; end
    tsec = str2double(f{2}) / 1000;
    if isnan(tsec), continue; end
    nValid = nValid + 1;
    if isempty(sysFirst), sysFirst = strtrim(f{1}); tFirst = tsec; end
    code = strtrim(f{4});
    value = strtrim(strjoin(f(5:end), ';'));
    if strcmpi(code,'samplingRate Recording')
        v = str2double(value); if ~isnan(v), L.samplingRate = v; end
    elseif strcmpi(code,'Recording')
        par = contains(value,'parallel','IgnoreCase',true);
        if contains(value,'started','IgnoreCase',true)
            if par
                tStartPar = tsec; sysStartPar = strtrim(f{1}); lineStartPar = i;
            else
                tStart = tsec; sysStart = strtrim(f{1}); lineStart = i;
            end
        elseif contains(value,'stopped','IgnoreCase',true)
            if par, tStopPar = tsec; else, tStop = tsec; end
        end
    elseif strcmpi(code,'Event') && contains(value,'extended sensor mode','IgnoreCase',true)
        ext(end+1,:) = [tsec, double(~contains(value,'off','IgnoreCase',true)), i]; %#ok<AGROW>
    elseif strcmpi(code,'Offset') || strcmpi(code,'Calibration')
        % one entry per channel ('<ch>;Calibration;1000'), or (software 2.0.80xx, 2022) all channels in one line
        % with channel 0 ('0;Calibration; 1000 1000 ... 1000')
        ch = str2double(f{3}); v = sscanf(value, '%f')';
        if ~isnan(ch) && ~isempty(v)
            if ch == 0 && numel(v) > 1
                E = [repmat(tsec, numel(v), 1), (1:numel(v))', v(:), repmat(i, numel(v), 1)];
            else
                E = [tsec ch v(1) i];
            end
            if strcmpi(code,'Offset'), offs = [offs; E]; else, cal = [cal; E]; end %#ok<AGROW>
        end
    elseif strcmpi(code,'rockerSpeed')
        v = str2double(value); if ~isnan(v), rck(end+1,:) = [tsec v i]; end %#ok<AGROW>
    elseif strcmpi(code,'nChannels')
        v = str2double(value); if ~isnan(v), L.nChannelsController = v; end
    elseif strcmpi(code,'programInfo') && contains(value,'Version','IgnoreCase',true)
        L.programVersion = value;
    elseif contains(code,'singleChannelMode','IgnoreCase',true) || ...
            (strcmpi(code,'Event') && contains(value,'singleChannelMode','IgnoreCase',true))
        v = lower(value);
        L.singleChannelMode = ~(contains(v,'off') || contains(v,'false') || strcmp(v,'0'));
    end
end
if nValid == 0, return; end
% entries of the main recording have priority over 'parallel recording' entries (schedule files)
if isnan(tStart) && isnan(tStop)
    tStart = tStartPar; tStop = tStopPar; sysStart = sysStartPar;
end
if ~isnan(tStart) && ~isnan(tStop) && tStop > tStart
    L.recordingDuration = tStop - tStart;
elseif ~isnan(tStop)
    L.recordingDuration = tStop;
end
% entries logged before the 'Recording started' line hold from the start of the file (time -Inf; such lines may
% carry the dataLogTime of a previous recording)
if isnan(lineStart), lineStart = lineStartPar; end
if ~isnan(lineStart)
    ext(ext(:,3) < lineStart, 1) = -inf;
    offs(offs(:,4) < lineStart, 1) = -inf;
    cal(cal(:,4) < lineStart, 1) = -inf;
    rck(rck(:,3) < lineStart, 1) = -inf;
end
L.rockerSpeedEvents = rck(:,1:2);
L.extendedSensorModeEvents = ext(:,1:2);
L.offsetEvents = offs(:,1:3);
L.calibrationEvents = cal(:,1:3);
tSys = tStart;
if isempty(sysStart), sysStart = sysFirst; tSys = tFirst; end
v = sscanf(sysStart, '%d %d %d %d:%d:%d:%d');      %e.g. 2026 08 04 05:59:00:983
if numel(v) >= 6
    if numel(v) < 7, v(7) = 0; end
    if isnan(tSys), tSys = 0; end
    L.startDatenum = datenum(v(1),v(2),v(3),v(4),v(5),v(6)+v(7)/1000) - tSys/86400;
end
end
