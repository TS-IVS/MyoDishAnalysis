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
%   - external trigger pulses (bit 14 without channel and current bits, e.g. TTL pulses of an external stimulator
%     connected to the external controller unit, which carries one chamber): stim.channel = 0 (before 2026-10-08
%     read as channel 8); consecutive samples of such a pulse are one pulse. Whether they are the stimuli of the
%     analysed channel: option 'externalTrigger' (mda_options, mda_analyzeChannel).
%   - some setups do not transmit the rocker bit (firmware error). If bit 15 is never set while the log file has
%     rocker speeds > 0 (tested in up to 5 such periods), or if there is no status channel, the rocker state is
%     taken from the 'rockerSpeed' entries of the log file (moving while rpm > 0, from 'rockerLogDelay' = 0.27 s
%     after the entry: median delay of the rocker bit in 154 transitions of 7 recordings, 0.26-0.31 s; moving
%     before the first entry, as in all 7 recordings).
%     Options 'rockerSource' ('auto' | 'status' | 'log') and 'rockerLogDelay', see mda_options.
%
% OUTPUT (S)
%   file facts: file, logFile, samplingRate, nChannelsInFile, dataChannels, hasStimChannel, totalSeconds,
%               recordingStart (datenum of file time 0, NaN if unknown; 12-hour time stamps of software 2.0.7717-
%               2.0.7769 corrected, see mda_clockTime), extendedSensorIntervals, notes,
%               offsetLog / calibrationLog ([time channel value] of the 'Offset' / 'Calibration' entries of the log;
%               time -Inf = logged before the recording start), calibrationApplied, extendedSensorFactor,
%               pulseSettingsLog ([time logChannel code value]: chargeDuration (code 1), pauseDuration (2),
%               dechargeDuration (3) entries, us; log channel 10k + c = extra pulse #k of channel c),
%               extraPulseLog ([time channel k offset_ms line]: programmed time of the extra pulses relative to the
%               regular pulse of the channel, from the 'Sequence' entries; see extraPulseOffsets),
%               rockerSpeedLog ([time rpm]), rockerSource ('status channel' or 'log'), rockerLogIntervals
%               ([from to] in s with rocker speed > 0 according to the log file), recordingStopped (1 = the log
%               file ends with 'Recording stopped' for this file, 0 = recording still running or aborted, NaN = no
%               'Recording' entries; used by MyoDishAnalysisWatch to skip recordings that are still running)
%   data:       t (1 x n, s; centre of the averaged raw samples, first raw sample = 0 s), dt,
%               force (numel(dataChannels) x n, uN), rockerOn (1 x n logical),
%               stim (struct with fields time, channel, current, currentReached, external, isExtraPulse,
%               rockerOn; one entry per stimulus pulse of any channel; channel 0 = external trigger pulse)
%   Single channel files: force has one row = channel 1, stim.channel keeps the physical channel number.
%
% TS 2026-10-05 (condensed from importMyoDishData, readRecordingInfoFromMyoDishLogFile,
% readSamplingRateFromMyoDishLogFile; identical data and stimulus times)
% 2026-10-08: recordingStart from mda_clockTime (12-hour time stamps)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

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
S = readData(S, fromSeconds, toSeconds, opts.downsampling, ~isfield(opts, 'spikeRemoval') || opts.spikeRemoval, opts);
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

L = readLog(H.logFile, d.datenum);
H.recordingStart = L.startDatenum;
if ~isempty(L.clockNote), H.notes{end+1} = L.clockNote; end   %12-hour time stamps (2026-10-08)
H.programVersion = L.programVersion;
H.recordingStopped = L.recordingStopped; %1 / 0 / NaN (2026-10-08)
H.offsetLog = L.offsetEvents;          %[time channel value]: sensor signal without load ('Offset' entries)
H.calibrationLog = L.calibrationEvents; %[time channel value]: 'Calibration' entries (AU per mN)
H.rockerSpeedLog = L.rockerSpeedEvents; %[time rpm]: 'rockerSpeed' entries (0 = stop)
H.pulseSettingsLog = L.pulseSettingsEvents; %[time logChannel code value]: pulse durations (us; code 1 charge, 2 pause,
                                           %3 decharge; log channel 10k + c = extra pulse #k of channel c)
H.extraPulseLog = L.extraPulseOffsets;     %[time channel k offset_ms line]: programmed extra pulse times (2026-10-10)

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

% rocker state: bit 15 of the status channel or, if this bit is missing although the log file has rocker speeds
% > 0 (firmware error in some setups) or there is no status channel, the 'rockerSpeed' entries of the log file
% (rocker moving while rpm > 0, from 'rockerLogDelay' s after the entry)
H.rockerLogIntervals = rockerIntervalsFromLog(H.rockerSpeedLog, opts.rockerLogDelay, H.totalSeconds);
switch lower(char(opts.rockerSource))
    case 'log'
        H.rockerSource = 'log';
    case 'status'
        H.rockerSource = 'status channel';
    otherwise
        H.rockerSource = 'status channel';
        if ~isempty(H.rockerLogIntervals)
            if ~H.hasStimChannel
                H.rockerSource = 'log';
                H.notes{end+1} = sprintf('No status channel: rocker state from the rockerSpeed entries of the log file (+%g s).', ...
                    opts.rockerLogDelay);
            elseif ~rockerBitInIntervals(H)
                H.rockerSource = 'log';
                H.notes{end+1} = sprintf(['Rocker bit missing in the status channel although the rocker speed was > 0: ' ...
                    'rocker state from the rockerSpeed entries of the log file (+%g s).'], opts.rockerLogDelay);
            end
        end
end

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
function S = readData(S, fromSeconds, toSeconds, nDS, spikeRemoval, opts)
if nargin < 5, spikeRemoval = false; end
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

% force channels: spike artifacts removed (option 'spikeRemoval', see mda_removeSpikes), mean of nDS samples (nDS = 2:
% identical to the median used by importMyoDishData)
nData = numel(S.dataChannels);
S.force = zeros(nData, n);
S.spikes = zeros(0, 4);                            %channel, from, to (s, time in the file), size (AU)
Xr = [];
if spikeRemoval && nRaw > 0
    [Xr, sp] = mda_removeSpikes(raw(1:nData, :), fs, opts);
    if ~isempty(sp)
        dc = S.dataChannels(:);
        S.spikes = [dc(sp(:,1)), (i0 + sp(:,2) - 1) / fs, (i0 + sp(:,3) - 1) / fs, sp(:,4)];
    end
end
for c = 1:nData
    if isempty(Xr), x = double(raw(c,:)); else, x = Xr(c,:); end
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
isLog = isfield(S, 'rockerSource') && strcmp(S.rockerSource, 'log');
if S.hasStimChannel && nRaw > 0
    code = typecast(raw(S.stimRow,:), 'uint16');
    rockerBit = bitand(code, uint16(16384)) ~= 0;                 %bit 15
    idx = find(bitand(code, uint16(49151)) ~= 0);                 %any bit except bit 15 = stimulus pulse
    pc = code(idx);
    ch = double(bitand(bitshift(pc, -9), uint16(15)));            %bits 10-13
    isTrig = bitand(pc, uint16(16383)) == uint16(8192);           %bit 14 without channel / current (bits 1-13)
    ch(ch > 8) = ch(ch > 8) - 8;
    ch(ch == 0) = 8;
    ch(isTrig) = 0;                                               %external trigger pulse (no MyoDish channel)
    if numel(idx) > 1                                             %next sample of the same trigger pulse: one pulse
        dup = reshape(isTrig, [], 1) & [false; reshape(isTrig(1:end-1), [], 1)] & [false; diff(idx(:)) == 1];
        idx = idx(~dup); pc = pc(~dup); ch = ch(~dup);
    end
    S.stim.time = ((i0 + idx(:) - 1) / fs);
    S.stim.channel = ch(:);
    S.stim.current = double(bitand(pc(:), uint16(255)));          %bits 1-8 [mA]
    S.stim.currentReached = bitand(pc(:), uint16(256)) == 0;      %bit 9
    S.stim.external = bitand(pc(:), uint16(8192)) ~= 0;           %bit 14
    S.stim.isExtraPulse = bitand(pc(:), uint16(32768)) ~= 0;      %bit 16
    S.stim.rockerOn = reshape(rockerBit(idx), [], 1);

    % rocker state of every (downsampled) sample. In older firmware the rocker bit may only be set in the
    % stimulus pulses: then the state of the last pulse (any channel) is held until the next pulse.
    if isLog
        % rocker state from the log file (below)
    elseif nnz(rockerBit) > 2 * nnz(S.stim.rockerOn)
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
if isLog && nRaw > 0                               %rocker state from the 'rockerSpeed' entries of the log file
    state = rockerStateFromLog(S.rockerLogIntervals, (i0 + (0:nRaw-1)) / fs);
    S.rockerOn = any(reshape(state, nDS, n), 1);
    S.stim.rockerOn = reshape(state(round(S.stim.time * fs) - i0 + 1), [], 1);
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
    if isfield(S, 'rockerSource') && strcmp(S.rockerSource, 'log')
        r = double(rockerStateFromLog(S.rockerLogIntervals, (s0 + b0 * binSamples + (0:m-1)) / fs));
        r(end+1:end+pad) = nan;
        O.rockerFraction(b0+(1:nb)) = mean(reshape(r, binSamples, nb), 1, 'omitnan');
    elseif S.hasStimChannel
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
function I = rockerIntervalsFromLog(R, delay, T)
% [from to] (s, time in the file) in which the rocker moves according to the 'rockerSpeed' entries (rpm > 0).
% An entry takes effect 'delay' s after its time; entries before the recording start (time -Inf) at time 0.
% Before the first entry the rocker moves (default state; in 7 of 7 recordings with rocker bit it moved at the
% start, also when the first entry was a speed > 0).
I = zeros(0,2);
if isempty(R), return; end
[~, o] = sort(R(:,1));                             %stable
R = R(o,:);
t = max(R(:,1) + delay, 0);
a = 0;
for k = 1:size(R,1)
    if R(k,2) > 0 && isnan(a)
        a = t(k);
    elseif R(k,2) <= 0 && ~isnan(a)
        I(end+1,:) = [a t(k)]; %#ok<AGROW>
        a = nan;
    end
end
if ~isnan(a), I(end+1,:) = [a T]; end
I(:,2) = min(I(:,2), T);
I = I(I(:,2) > I(:,1), :);
end


function on = rockerStateFromLog(I, t)
% true where t lies in one of the intervals I = [from to] (sorted, disjoint): from <= t < to
on = false(size(t));
if isempty(I) || isempty(t), return; end
k = discretize(t, [I(:,1); inf]);
v = ~isnan(k);
tv = t(v);
on(v) = tv(:) < I(k(v),2);
end


function tf = rockerBitInIntervals(H)
% true if bit 15 of the status channel is set in (one of) the first 5 intervals with rocker movement according
% to the log file (0.25 s after the start, at most 4 s each); true also if no interval can be tested
I = H.rockerLogIntervals;
I = [I(:,1) + 0.25, min(I(:,2) - 0.25, I(:,1) + 4.25)];
I = I(I(:,2) - I(:,1) >= 0.5, :);
tf = isempty(I);
if tf, return; end
fid = fopen(H.file, 'r', 'ieee-le');
if fid < 0, tf = true; return; end
cleaner = onCleanup(@() fclose(fid));
fs = H.samplingRate;
nCh = H.nChannelsInFile;
for k = 1:min(5, size(I,1))
    s0 = floor(I(k,1) * fs);
    m = min(H.totalSamples, ceil(I(k,2) * fs)) - s0;
    if m <= 0, continue; end
    fseek(fid, s0 * nCh * 2, 'bof');
    raw = fread(fid, [nCh m], 'int16=>int16');
    if any(bitand(typecast(raw(H.stimRow,:), 'uint16'), uint16(16384)) ~= 0)
        tf = true;
        return;
    end
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
function L = readLog(logFile, fileTime)
% the facts needed from the MyoDish log file (lines: systemTime;dataLogTime_ms;channel;code;value)
% fileTime: datenum of the last change of the .mdd file (decides AM/PM of 12-hour time stamps if the log cannot)
if nargin < 2, fileTime = []; end
L = struct('samplingRate',nan,'recordingDuration',nan,'nChannelsController',nan,'singleChannelMode',[], ...
    'extendedSensorModeEvents',zeros(0,2),'startDatenum',nan,'programVersion','','clockNote','', ...
    'offsetEvents',zeros(0,3),'calibrationEvents',zeros(0,3),'rockerSpeedEvents',zeros(0,2), ...
    'recordingStopped',nan,'pulseSettingsEvents',zeros(0,4),'extraPulseOffsets',zeros(0,5));
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
kStart = nan; kStartPar = nan; tFirst = nan;
sysAll = cell(numel(lines), 1); textAll = sysAll; tAll = nan(numel(lines), 1); versions = {};   %all valid entries (clock time)
ext = zeros(0,3); offs = zeros(0,4); cal = zeros(0,4); rck = zeros(0,3);  %last column: line number
pst = zeros(0,5); nPst = 0;                         %pulse durations: time, log channel, code (1-3), value (us), line
seqEv = cell(0, 1);                                 %'Sequence' entries: {time, log channel, line, text}
pstCodes = {'chargeDuration', 'pauseDuration', 'dechargeDuration'};
lineStart = nan; lineStartPar = nan;
tMax = -inf; tMaxPar = -inf;                        %latest dataLogTime since the chosen start line
% 2026-10-08: state of the last 'Recording' entry (1 started, 0 stopped) for this file (name in the entry), for the
% main recording and for parallel recordings
[~, ownName] = fileparts(logFile);
ownName = lower([regexprep(ownName, '_log$', '') '.mdd']);
lastOwn = nan; lastMain = nan; lastPar = nan;
for i = 1:numel(lines)
    f = strsplit(lines{i}, ';');
    if numel(f) < 5, continue; end
    tsec = str2double(f{2}) / 1000;
    if isnan(tsec), continue; end
    nValid = nValid + 1;
    sysAll{nValid} = strtrim(f{1}); tAll(nValid) = tsec;
    if nValid == 1, tFirst = tsec; end
    code = strtrim(f{4});
    value = strtrim(strjoin(f(5:end), ';'));
    textAll{nValid} = value;
    if strcmpi(code,'samplingRate Recording')
        v = str2double(value); if ~isnan(v), L.samplingRate = v; end
    elseif strcmpi(code,'Recording')
        par = contains(value,'parallel','IgnoreCase',true);
        if contains(value,'started','IgnoreCase',true)
            % the first start line; a later one only if the dataLogTime starts again (new recording). A recording
            % that was stopped and started again is appended to the same .mdd file (dataLogTime continues).
            if par
                if isnan(lineStartPar) || tsec < tMaxPar - 1
                    tStartPar = tsec; kStartPar = nValid; lineStartPar = i; tMaxPar = tsec;
                end
            else
                if isnan(lineStart) || tsec < tMax - 1
                    tStart = tsec; kStart = nValid; lineStart = i; tMax = tsec;
                end
            end
        elseif contains(value,'stopped','IgnoreCase',true)
            if par, tStopPar = tsec; else, tStop = tsec; end
        end
        st = nan;
        if contains(value,'started','IgnoreCase',true), st = 1; elseif contains(value,'stopped','IgnoreCase',true), st = 0; end
        if ~isnan(st)
            if contains(lower(value), ownName), lastOwn = st; end
            if par, lastPar = st; else, lastMain = st; end
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
    elseif any(strcmpi(code, pstCodes))              %pulse durations (us) of a channel; channel 10k+c = extra pulse #k
        ch = str2double(f{3}); v = str2double(value);
        if ~isnan(ch) && ~isnan(v)
            nPst = nPst + 1;
            if nPst > size(pst, 1), pst(end + max(64, nPst), :) = 0; end
            pst(nPst,:) = [tsec ch find(strcmpi(code, pstCodes), 1) v i];
        end
    elseif strcmpi(code,'Sequence')                  %stimulus times of the sequence (regular and extra pulses #k)
        seqEv{end+1, 1} = {tsec, str2double(f{3}), i, value}; %#ok<AGROW>
    elseif strcmpi(code,'nChannels')
        v = str2double(value); if ~isnan(v), L.nChannelsController = v; end
    elseif strcmpi(code,'programInfo') && contains(value,'Version','IgnoreCase',true)
        L.programVersion = value; versions{end+1} = value; %#ok<AGROW>
    elseif strcmpi(code,'programVersion')         %2021-2022: 'ProgramVersion;2.0.7769.26061'
        versions{end+1} = value; %#ok<AGROW>
    elseif contains(code,'singleChannelMode','IgnoreCase',true) || ...
            (strcmpi(code,'Event') && contains(value,'singleChannelMode','IgnoreCase',true))
        v = lower(value);
        L.singleChannelMode = ~(contains(v,'off') || contains(v,'false') || strcmp(v,'0'));
    end
    if ~isnan(lineStart), tMax = max(tMax, tsec); end
    if ~isnan(lineStartPar), tMaxPar = max(tMaxPar, tsec); end
end
if nValid == 0, return; end
if ~isnan(lastOwn)
    L.recordingStopped = double(lastOwn == 0);
elseif ~isnan(lastMain)
    L.recordingStopped = double(lastMain == 0);
elseif ~isnan(lastPar)
    L.recordingStopped = double(lastPar == 0);
end
% entries of the main recording have priority over 'parallel recording' entries (schedule files)
if isnan(tStart) && isnan(tStop)
    tStart = tStartPar; tStop = tStopPar; kStart = kStartPar;
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
pst = pst(1:nPst, :);
X = extraPulseOffsets(seqEv);
if ~isnan(lineStart)
    pst(pst(:,5) < lineStart, 1) = -inf;
    X(X(:,5) < lineStart, 1) = -inf;
end
L.pulseSettingsEvents = pst(:,1:4);
L.extraPulseOffsets = X;
L.rockerSpeedEvents = rck(:,1:2);
L.extendedSensorModeEvents = ext(:,1:2);
L.offsetEvents = offs(:,1:3);
L.calibrationEvents = cal(:,1:3);
% clock time of all entries, 12-hour time stamps (software 2.0.7717-2.0.7769) corrected (2026-10-08); file time 0
% = clock time of the 'Recording started' entry - its dataLogTime
sysAll = sysAll(1:nValid); textAll = textAll(1:nValid); tAll = tAll(1:nValid);
N = nan(nValid, 7);
num = regexp(sysAll, '^(\d+) (\d+) (\d+) (\d+):(\d+):(\d+):?(\d*)', 'tokens', 'once');
okN = ~cellfun(@isempty, num);
if any(okN), N(okN,:) = str2double(vertcat(num{okN})); end
[clk, info] = mda_clockTime(N, tAll, versions, fileTime, textAll);
L.clockNote = info.note;
tSys = tStart;
if isnan(kStart), kStart = 1; tSys = tFirst; end
if ~isnat(clk(kStart))
    if isnan(tSys), tSys = 0; end
    L.startDatenum = datenum(clk(kStart)) - tSys/86400;
end
end


function X = extraPulseOffsets(ev)
% Programmed time of the extra pulses relative to the regular pulse of the same channel, from the 'Sequence'
% entries of the log file: 'Sent stimPeriod P' starts a new sequence (all extra pulses cleared); 'Added stimTime(s)
% a b#k ...' of channel c sets its regular times (numbers) and extra pulse times (#k = extra pulse k, software
% 2022 and 2026); an entry of log channel 10k + c ('Added stimTime e') sets the times of extra pulse k of channel c.
% X: rows [time, channel c, k, offset (ms; extra time - nearest regular time of the channel, within the period),
% line]. Every entry that changes channel c gives the complete set of its extra pulses (rows with the same line);
% k = 0 / offset NaN: no extra pulses. TS 2026-10-10
X = zeros(0, 5);
if isempty(ev), return; end
R = cell(1, 8);                                     %regular times per channel (ms within the period)
E = cell(8, 9);                                     %extra pulse times per channel and k
P = nan;                                            %period (ms)
rows = cell(numel(ev), 1);
for i = 1:numel(ev)
    t = ev{i}{1}; chn = ev{i}{2}; ln = ev{i}{3}; txt = strtrim(ev{i}{4});
    if strncmpi(txt, 'Sent stimPeriod', 15)
        p = str2double(regexp(txt, '-?\d+(\.\d+)?', 'match', 'once'));
        if ~isnan(p) && p > 0, P = p; end
        R = cell(1, 8); E = cell(8, 9);
        rows{i} = [repmat(t, 8, 1), (1:8)', zeros(8, 1), nan(8, 1), repmat(ln, 8, 1)];
        continue;
    end
    tok = regexp(txt, '^Added stimTime(?:\(s\))?\s*(.*)$', 'tokens', 'once', 'ignorecase');
    if isempty(tok) || isnan(chn), continue; end
    k0 = floor(chn / 10); c = chn - 10 * k0;
    if c < 1 || c > 8 || k0 > 9, continue; end
    reg = []; ext = cell(1, 9);
    for p = regexp(strtrim(tok{1}), '\s+', 'split')
        m = regexp(p{1}, '^(-?\d+(?:\.\d+)?)(#\d)?$', 'tokens', 'once');   %(MATLAB: no tokens inside (?:...)?)
        if isempty(m), continue; end
        v = str2double(m{1});
        if numel(m) >= 2 && numel(m{2}) == 2 && str2double(m{2}(2)) >= 1
            k = str2double(m{2}(2)); ext{k}(end+1) = v;
        elseif k0 > 0
            ext{k0}(end+1) = v;
        else
            reg(end+1) = v; %#ok<AGROW>
        end
    end
    if k0 == 0                                      %an entry of channel c replaces its sequence
        R{c} = reg;
        for k = 1:9, E{c,k} = ext{k}; end
    else
        E{c,k0} = ext{k0};
    end
    r = zeros(0, 5);
    for k = 1:9
        for e = E{c,k}
            if isempty(R{c}), continue; end
            d = e - R{c};
            if ~isnan(P), d = mod(d + P/2, P) - P/2; end
            [~, j] = min(abs(d));
            r(end+1, :) = [t, c, k, d(j), ln]; %#ok<AGROW>
        end
    end
    if isempty(r), r = [t, c, 0, nan, ln]; end
    rows{i} = r;
end
X = vertcat(rows{:});
if isempty(X), X = zeros(0, 5); end
end
