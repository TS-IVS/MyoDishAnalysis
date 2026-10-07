function [contractions, summary, info] = MyoDishAnalysis(mddFile, channels, fromSeconds, toSeconds, varargin)
%MYODISHANALYSIS  Contraction parameters of every single contraction in a MyoDish recording (.mdd).
%
%   [contractions, summary, info] = MyoDishAnalysis(mddFile, channels, fromSeconds, toSeconds, ...)
%
%   mddFile      .mdd file ('' or [] opens a file dialog). The log file <name>_log.log must be in the same folder.
%   channels     data channels, e.g. 3 or [1 2 5] ([] = all channels in the file)
%   fromSeconds  start of the analysed time range in s (time in the file; negative = seconds before the end).
%   toSeconds    end of the time range. Vectors define several ranges, e.g. baseline and drug:
%                fromSeconds = [600 3000], toSeconds = [660 3060]
%
%   contractions table, one row per detected contraction (also the excluded ones, see column 'included')
%   summary      table, one row per channel and range: numbers of contractions/stimuli, mean and SD of all
%                parameters of the included contractions
%   info         struct: file facts, options, detection threshold per channel and range, notes; with grouped
%                protocols (FFR, ST, RP, PRP) info.protocolResults: characteristic values per protocol and channel
%                (max. captured frequency, FFR ratios, current thresholds, refractory periods, PRP at 15 / 30 /
%                60 s; see mda_protocolResults), also sheet 'protocolResults' of the results file
%
% PARAMETERS (per contraction; force in uN, times in s; see mda_analyzeChannel for the exact definitions)
%   amplitude, diastolicForce (F_dia - zero force), diastolicSignal (F_dia, sensor signal), dFdtMax, dFdtMin,
%   riseTime10_90, TTP90 (rise time 90 %: 10 % --> peak), TTR50, TTR90
%   (peak --> 50 / 90 % relaxation), CD50, CD90 (contraction duration at 50 / 90 %), AUC (area above the
%   diastolic force from 10 % upstroke to 90 % relaxation), peakToPeakInterval, peakToPeakFrequency;
%   in addition: t_peak, clockTime, beatType (stimulated / extra / unpaced), t_stim, stimToPeak,
%   rockerMoving, prominence (detection criterion)
%
% OPTIONS (name/value pairs)
%   'output', file      write the results: .xlsx (sheets contractions, summary, parameters, info) or .csv
%   'labels', {..}      names of the time ranges (e.g. {'baseline','drug'})
%   'metadata', m       labels per channel (columns of both tables): struct, table or file (.csv/.xlsx) with
%                       setupID, sliceID, species, sampleID, sampleGroup, sliceGroup, tissue, treatment,
%                       concentration, concentrationUnit, daysInCulture, cultureStart, comment, analyst (+ own
%                       fields); see mda_labels. Example:
%                       m.species = 'human'; m.sliceID = {'S1','S2','S3'}; m.analyst = 'TS';
%   'showFigures', tf   plot the signal with the detected contractions (default false; ranges <= 30 min,
%                       at most 16 figures)
%   'quiet', tf         no messages (default false)
%   'rocker', 'stopped' only contractions while the rocker is at rest are included ('any' (default), 'moving')
%   'beats', 'stimulated'  only stimulated contractions are included (default 'all')
%   'threshold', x      minimum peak prominence in uN (default 'auto')
%   'zeroForce', z      sensor signal without load (uN) for diastolicForce = F_dia - zeroForce, one value per
%                       channel or one for all (default: 'Offset' entry of each channel in the log file)
%   'rockerFilter', tf  remove the periodic rocker artifact while the rocker moves (default false; see
%                       mda_rockerFilter). Result per channel and range: info.rockerFilter
%   'protocol', p       analyse stimulation protocols found in the log file (mda_protocols: comments 'start ...
%                       protocol' / 'end ... protocol') instead of fromSeconds / toSeconds: a type ('FFR', 'RP',
%                       'ST', 'PRP', 'PD', 'rockerSpeed'), 'all', row numbers of mda_protocols(file), or a table like
%                       its output (e.g. with corrected from / to). Range labels: 'FFR 1', 'FFR 2', ... With a
%                       protocol, only stimulated contractions with the rocker at rest are included unless 'rocker'
%                       / 'beats' is given (grouping by rocker speed: all contractions).
%   'groupBy', q        group the contractions by a stimulation quantity and summarize per group (see
%                       mda_groupBeats): 'pacingFrequency', 'S2interval', 'stimCurrent', 'pauseLength',
%                       'rockerSpeed', 'pulseDuration', 'log:<code>', 'none'. Default with 'protocol': the quantity
%                       of the protocol type (FFR: pacingFrequency, RP: S2interval, ST: stimCurrent, PRP:
%                       pauseLength, PD: pulseDuration). The summary then has one row per range, channel and group
%                       (columns group, groupValue, groupRole, groupStep, groupBy, capture_percent,
%                       amplitude_pctOfRef, ...).
%   further options: see mda_options (filters, stimulus assignment, file format)
%
% EXAMPLES
%   T = MyoDishAnalysis('examples/example3_humanVentricle.mdd', 6, 0, 120);
%   [T, S] = MyoDishAnalysis(file, [1 2 3], [600 3000], [660 3060], 'labels', {'baseline','drug'}, ...
%                                'rocker','stopped', 'output','results.xlsx', 'showFigures',true);
%   [T, S] = MyoDishAnalysis(file, [], [], [], 'protocol', 'FFR');       %force-frequency protocol(s), per rate
%   [T, S] = MyoDishAnalysis(file, 1, [], [], 'protocol', 'RP', 'rocker', 'any');   %S2 intervals, all beats
%   MyoDishAnalysisGUI(file)     interactive selection of the time range / single contractions
%
% Requires MATLAB R2019b or newer, no toolboxes.
% Thomas Seidel (FAU Erlangen-Nuernberg / InVitroSys GmbH), 2026-10-05

if nargin < 1 || isempty(mddFile)
    [fn, pn] = uigetfile('*.mdd', 'MyoDish data file');
    if isequal(fn, 0), contractions = []; summary = []; info = []; return; end
    mddFile = fullfile(pn, fn);
end
if nargin < 2, channels = []; end
if nargin < 3 || isempty(fromSeconds), fromSeconds = 0; end
if nargin < 4 || isempty(toSeconds), toSeconds = inf; end

% ------------------------------------------------------------------ options
outputFile = ''; labels = {}; showFigures = false; quiet = false; chunkSeconds = 1800; metadata = [];
protocolSel = []; groupBy = '';
rest = {};
i = 1;
while i <= numel(varargin)
    key = varargin{i};
    if (ischar(key) || isstring(key)) && i < numel(varargin)
        switch lower(char(key))
            case 'output',       outputFile = char(varargin{i+1}); i = i + 2; continue;
            case 'labels',       labels = cellstr(varargin{i+1}); i = i + 2; continue;
            case 'showfigures',  showFigures = logical(varargin{i+1}); i = i + 2; continue;
            case 'quiet',        quiet = logical(varargin{i+1}); i = i + 2; continue;
            case 'chunkseconds', chunkSeconds = varargin{i+1}; i = i + 2; continue;
            case 'metadata',     metadata = varargin{i+1}; i = i + 2; continue;
            case 'protocol',     protocolSel = varargin{i+1}; i = i + 2; continue;
            case 'groupby',      groupBy = char(varargin{i+1}); i = i + 2; continue;
        end
    end
    rest{end+1} = varargin{i}; %#ok<AGROW>
    i = i + 1;
end
rk = rest;
if ~isempty(rk) && isstruct(rk{1}), rk = rk(2:end); end   %options struct first (GUI)
rockerGiven = any(cellfun(@(x) (ischar(x) || isstring(x)) && strcmpi(x, 'rocker'), rk(1:2:end)));
beatsGiven = any(cellfun(@(x) (ischar(x) || isstring(x)) && strcmpi(x, 'beats'), rk(1:2:end)));
opts = mda_options(rest{:});

% ------------------------------------------------------------------ file and ranges
H = mda_readMdd(mddFile, [], [], opts);
protocols = [];
if ~isempty(protocolSel)                           %ranges = stimulation protocols of the log file
    if istable(protocolSel)
        protocols = protocolSel;
    else
        P = mda_protocols(H);
        if isnumeric(protocolSel)
            protocols = P(protocolSel, :);
        elseif strcmpi(protocolSel, 'all')
            protocols = P;
        else
            protocols = P(strcmpi(P.type, protocolSel) | strcmpi(P.name, protocolSel), :);
        end
        if isempty(protocols)
            error('No protocol ''%s'' in the log file of %s. Protocols found: %s', char(string(protocolSel)), ...
                H.file, strjoin(strcat(P.type, {' ('}, P.name, {')'}), ', '));
        end
    end
    fromSeconds = protocols.from;
    toSeconds = protocols.to;
    if isempty(labels)
        labels = strcat(protocols.type, {' '}, arrayfun(@num2str, protocols.number, 'UniformOutput', false));
    end
end
nRanges = numel(fromSeconds);
if isempty(groupBy) && ~isempty(protocols)
    groupByR = cellstr(protocols.groupBy);
elseif isempty(groupBy)
    groupByR = repmat({'none'}, nRanges, 1);
else
    groupByR = repmat({groupBy}, nRanges, 1);
end
grouping = any(~strcmpi(groupByR, 'none'));
if ~isempty(protocols) && ~any(strcmpi(groupByR, 'rockerSpeed'))
    if ~rockerGiven, opts.rocker = 'stopped'; end   %protocols: contractions with the rocker at rest ...
    if ~beatsGiven, opts.beats = 'stimulated'; end  %... that follow a stimulus
end
if isempty(channels), channels = H.dataChannels; end
channels = channels(:)';
bad = channels(~ismember(channels, H.dataChannels));
if ~isempty(bad)
    error('Channel(s) %s not in the file. Data channels in %s: %s', mat2str(bad), H.file, mat2str(H.dataChannels));
end
if numel(fromSeconds) ~= numel(toSeconds)
    error('fromSeconds and toSeconds must have the same number of elements.');
end
ranges = [fromSeconds(:) toSeconds(:)];
ranges(ranges < 0) = H.totalSeconds + ranges(ranges < 0);
ranges = min(max(ranges, 0), H.totalSeconds);
if any(ranges(:,2) <= ranges(:,1))
    error('Empty time range (file length %.1f s).', H.totalSeconds);
end
nR = size(ranges, 1);
% zero force per channel ([] or NaN = 'Offset' entry of the log file)
zf = opts.zeroForce;
if isempty(zf)
    zeroOfChannel = @(c) [];
elseif isscalar(zf)
    zeroOfChannel = @(c) zf;
elseif numel(zf) == numel(channels)
    zeroOfChannel = @(c) zf(c);
else
    error('zeroForce: one value for all channels or one value per channel (%d) expected.', numel(channels));
end
if isempty(labels), labels = arrayfun(@(r) sprintf('range%d', r), 1:nR, 'UniformOutput', false); end
if numel(labels) ~= nR, error('Number of labels (%d) ~= number of ranges (%d).', numel(labels), nR); end
if ~quiet
    fprintf('%s\n  %.0f Hz (%s), %d channel(s) in file, %.1f s\n', H.file, H.samplingRate, H.samplingRateSource, ...
        numel(H.dataChannels), H.totalSeconds);
    for k = 1:numel(H.notes), fprintf('  note: %s\n', H.notes{k}); end
end

% ------------------------------------------------------------------ analysis (chunks of <= chunkSeconds)
pad = opts.maxBeatWindow + 2;
if opts.rockerFilter, pad = max(pad, 60); end      %context for the estimate of the rocker artifact
parts = {}; sumParts = {}; thrInfo = zeros(0, 6);
rfRows = {}; resParts = {};
nFig = 0;
f0cache = [];                                       %rocker frequency per rocker speed, estimated once (all channels)
for r = 1:nR
    edges = unique([ranges(r,1):chunkSeconds:ranges(r,2), ranges(r,2)]);
    nQ = numel(edges) - 1;
    Bc = cell(numel(channels), nQ); Cs = cell(numel(channels), nQ);
    lastB = cell(1, numel(channels)); lastC = cell(1, numel(channels));
    Sres = [];                                      %S2interval results: data of the whole range (traces)
    for q = 1:nQ
        % each chunk is read once for all channels; the file header (log file) is not read again
        S = mda_readMdd(H, max(0, edges(q) - pad), edges(q+1) + pad, opts);
        sub = [edges(q), edges(q+1)];
        if q < nQ, sub(2) = sub(2) - 1e-9; end      %half-open chunks: no contraction twice
        if opts.rockerFilter                        %rocker artifact of all channels of this chunk at once
            oR = opts;
            if isempty(oR.rockerFrequency) && ~isempty(f0cache), oR.rockerFrequency = f0cache; end
            [S, RFq] = mda_rockerFilter(S, channels, oR);
            if ~isempty(RFq) && ~isempty(RFq(1).f0table)  %frequencies found are kept (speeds not yet known: next chunk)
                ft = RFq(1).f0table(~isnan(RFq(1).f0table(:,2)), :);
                for jf = 1:size(ft, 1)
                    if isempty(f0cache) || ~any(f0cache(:,1) == ft(jf,1) | (isnan(f0cache(:,1)) & isnan(ft(jf,1))))
                        f0cache(end+1, :) = ft(jf, :); %#ok<AGROW>
                    end
                end
            end
        end
        for c = 1:numel(channels)
            optsC = opts;
            optsC.zeroForce = zeroOfChannel(c);
            [Bq, Cq] = mda_analyzeChannel(S, channels(c), sub, optsC);
            Bc{c,q} = Bq;
            lastB{c} = Bq; lastC{c} = Cq;           %control figure (single chunk)
            Cq.t = []; Cq.f = []; Cq.rockerArtifact = [];   %keep only the small fields of the earlier chunks
            Cs{c,q} = Cq;
            thrInfo(end+1,:) = [r, channels(c), edges(q), edges(q+1), Cq.threshold, Cq.maxStimToPeak]; %#ok<AGROW>
            if opts.rockerFilter && ~isempty(Cq.rockerFilter)
                RF = Cq.rockerFilter;
                rfRows(end+1,:) = {labels{r}, channels(c), edges(q), edges(q+1), RF.status, RF.f0, RF.artifactPP, ...
                    RF.r2, 100 * RF.correctedFraction, RF.message}; %#ok<AGROW>
            end
        end
    end
    for c = 1:numel(channels)
        B = vertcat(Bc{c,:});
        B.contraction = (1:height(B))';
        CsC = Cs(c,:);
        Cm = CsC{1};
        Cm.stimTimes = cell2mat(cellfun(@(x) x.stimTimes(x.stimTimes >= x.range(1) & x.stimTimes <= x.range(2)), CsC(:), 'UniformOutput', false));
        Cm.stimCaptured = cell2mat(cellfun(@(x) x.stimCaptured(x.stimTimes >= x.range(1) & x.stimTimes <= x.range(2)), CsC(:), 'UniformOutput', false));
        Cm.threshold = median(cellfun(@(x) x.threshold, CsC));
        if grouping && ~strcmpi(groupByR{r}, 'none')
            [B, T, Z] = mda_groupBeats(H, B, Cm, ranges(r,:), groupByR{r}, opts);
            gb = lower(groupByR{r});
            if ismember(gb, {'pacingfrequency', 'stimcurrent', 's2interval', 'pauselength'})
                trace = [];
                if strcmp(gb, 's2interval')            %S2 response: traces of the whole range
                    if isempty(Sres), Sres = mda_readMdd(H, max(0, ranges(r,1) - 2), ranges(r,2) + 2, opts); end
                    [~, Cx] = mda_analyzeChannel(Sres, channels(c), ranges(r,:), opts);
                    trace = struct('t', Cx.t, 'f', Cx.f, 'tR', Sres.t, 'rockerOn', Sres.rockerOn);
                end
                Rr = mda_protocolResults(groupByR{r}, T, Z, trace, opts);
                resParts{end+1} = [table(labels(r), channels(c), ranges(r,1), ranges(r,2), groupByR(r), ...
                    'VariableNames', {'range','channel','from','to','groupBy'}), Rr]; %#ok<AGROW>
            end
        else
            T = mda_summarize(B, Cm, ranges(r,:));
            if grouping                            %same columns as the grouped ranges
                B.group = repmat({'all'}, height(B), 1); B.groupValue = nan(height(B), 1); B.groupRole = repmat({''}, height(B), 1);
                B.groupStep = nan(height(B), 1);
                T = addvars(T, nan, nan, 'After', 'missedBeats_percent', 'NewVariableNames', {'capture_percent', 'currentReached_percent'});
                T = addvars(T, nan(height(T), 1), 'After', 'amplitude_SD', 'NewVariableNames', 'amplitude_pctOfRef');
                T = [table({'all'}, nan, {''}, nan, {'none'}, 'VariableNames', {'group','groupValue','groupRole','groupStep','groupBy'}), T]; %#ok<AGROW>
            end
        end
        T = [table(repmat(labels(r), height(T), 1), 'VariableNames', {'range'}), T]; %#ok<AGROW>
        sumParts{end+1} = T; %#ok<AGROW>
        B = [table(repmat(labels(r), height(B), 1), 'VariableNames', {'range'}), B]; %#ok<AGROW>
        parts{end+1} = B; %#ok<AGROW>
        if ~quiet
            fprintf('  %s, channel %d: %d contractions detected, %d included (threshold %.0f uN, %s)\n', ...
                labels{r}, channels(c), height(B), sum(B.included), Cm.threshold, Cm.thresholdMode);
            if strcmp(opts.rocker, 'stopped') && height(B) > 0 && ~any(B.included) && all(B.rockerMoving)
                fprintf('    the rocker moved during every contraction: ''rocker'',''any'' includes them\n');
            end
            if opts.rockerFilter && ~isempty(rfRows)
                k = strcmp(rfRows(:,1), labels{r}) & cell2mat(rfRows(:,2)) == channels(c);
                msgs = unique(regexprep(rfRows(k,10), '^Rocker filter, channel \d+: ', ''), 'stable');
                fprintf('    rocker filter: %s\n', strjoin(msgs(1:min(3, end)), ' | '));
            end
        end
        if showFigures && nFig < 16 && nQ == 1
            nFig = nFig + 1;
            plotChannel(lastC{c}, lastB{c}, S, ranges(r,:), sprintf('%s - channel %d - %s', shortName(H.file), channels(c), labels{r}));
        end
    end
end
thrInfo = sortrows(thrInfo, [1 2 3]);                %order: range, channel, time
contractions = vertcat(parts{:});
summary = vertcat(sumParts{:});

% absolute time of every contraction (if the log file contains the recording start)
if ~isnan(H.recordingStart) && height(contractions) > 0
    clockTime = datetime(H.recordingStart + contractions.t_peak / 86400, 'ConvertFrom', 'datenum', ...
        'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
    contractions = addvars(contractions, clockTime, 'After', 't_peak');
end
summary = addvars(summary, repmat({shortName(H.file)}, height(summary), 1), 'Before', 1, 'NewVariableNames', 'file');

% per-channel labels (metadata) as columns after 'channel'
Lbl = mda_labels(metadata, channels);
if ismember('clockTime', contractions.Properties.VariableNames)
    contractions = mda_addLabels(contractions, Lbl, contractions.clockTime);
else
    contractions = mda_addLabels(contractions, Lbl);
end
if ~isnan(H.recordingStart)
    mid = datetime(H.recordingStart + (summary.from + summary.to) / 2 / 86400, 'ConvertFrom', 'datenum');
    summary = mda_addLabels(summary, Lbl, mid);
else
    summary = mda_addLabels(summary, Lbl);
end

if ~isempty(resParts)                              %characteristic values per protocol and channel
    PR = vertcat(resParts{:});
    PR = addvars(PR, repmat({shortName(H.file)}, height(PR), 1), 'Before', 1, 'NewVariableNames', 'file');
    if ~isnan(H.recordingStart)
        PR = mda_addLabels(PR, Lbl, datetime(H.recordingStart + (PR.from + PR.to) / 2 / 86400, 'ConvertFrom', 'datenum'));
    else
        PR = mda_addLabels(PR, Lbl);
    end
end

info = rmfield(H, {'totalSamples','stimRow'});
info.channels = channels;
info.ranges = ranges;
info.rangeLabels = labels;
info.protocols = protocols;
info.groupBy = groupByR;
if ~isempty(resParts), info.protocolResults = PR; end
info.labels = Lbl;
info.options = opts;
info.thresholds = array2table(thrInfo, 'VariableNames', {'range','channel','from','to','threshold_uN','maxStimToPeak_s'});
if opts.rockerFilter
    if isempty(rfRows), rfRows = cell(0, 10); end
    info.rockerFilter = cell2table(rfRows, 'VariableNames', {'range','channel','from_s','to_s','status','rockerFrequency_Hz', ...
        'artifact_uN_peakToPeak','artifactR2','corrected_percentOfRockerOnTime','message'});
    [~, gr] = ismember(info.rockerFilter.range, labels);
    [~, o] = sortrows([gr info.rockerFilter.channel info.rockerFilter.from_s]);   %order: range, channel, time
    info.rockerFilter = info.rockerFilter(o, :);
end
info.analysisDate = datestr(now, 'yyyy-mm-dd HH:MM:SS');

if ~isempty(outputFile)
    mda_writeResults(outputFile, contractions, summary, info);
    if ~quiet, fprintf('  results written to %s\n', outputFile); end
end
end


% =====================================================================================================
function s = shortName(file)
[~, n, e] = fileparts(file);
s = [n e];
end

function plotChannel(C, B, S, range, ttl)
figure('Name', ttl, 'Color', 'w');
ax = axes; hold(ax, 'on');
I = C.t >= range(1) - 2 & C.t <= range(2) + 2;
yl = [min(C.f(I)) max(C.f(I))]; yl = yl + [-0.05 0.1] * max(1, diff(yl));
rk = S.rockerOn(I); tt = C.t(I);
if any(rk)
    on = diff([0 rk 0]); s1 = find(on == 1); s2 = find(on == -1) - 1;
    for k = 1:numel(s1)
        patch(ax, tt([s1(k) s2(k) s2(k) s1(k)]), yl([1 1 2 2]), [0.9 0.9 0.9], 'EdgeColor', 'none');
    end
end
plot(ax, C.t(I), C.f(I), 'k');
st = C.stimTimes(C.stimTimes >= range(1) - 2 & C.stimTimes <= range(2) + 2);
plot(ax, [st st]', repmat(yl(1) + [0; 0.04] * diff(yl), 1, numel(st)), 'b');
inc = B.included;
[~, loc] = ismember(B.t_peak, C.peakTimes);
plot(ax, B.t_peak(inc), C.f(C.iPeaks(loc(inc))), 'rv', 'MarkerFaceColor', 'r');
plot(ax, B.t_peak(~inc), C.f(C.iPeaks(loc(~inc))), 'v', 'Color', [0.5 0.5 0.5]);
xline(ax, range(1), 'g--'); xline(ax, range(2), 'g--');
ylim(ax, yl); xlabel(ax, 'time in file (s)'); ylabel(ax, 'force (\muN)');
title(ax, {ttl, sprintf('%d contractions included (red), grey = excluded, blue = stimuli, shaded = rocker moving', sum(inc))}, 'Interpreter', 'none');
end
