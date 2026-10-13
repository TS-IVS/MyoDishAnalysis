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
%   contractions table, one row per detected contraction (also the excluded ones, see column 'included'); column
%                'uncertain': contraction found with high sensitivity only (option 'detection', see mda_options)
%   summary      table, one row per channel and range: numbers of contractions/stimuli, mean and SD of all
%                parameters of the included contractions; column arrhythmicPacing (2026-10-13): channel paced
%                arrhythmically (option arrhythmicChannels, or detected from the stim-to-stim variability outside
%                the stimulation protocols of the log file: arrhythmicDetection, see mda_options, mda_summarize)
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
%   rockerMoving, prominence (detection criterion); eliciting pulse (option stimAssignment, default 'onset': pulse in
%   the gate of the contraction onset, see mda_analyzeChannel): t_onset, stimToOnset, t_rise50, stimToRise50 (50 % of
%   the amplitude on the upstroke), stimPulse (pulse ID),
%   stimCurrent, stimChargeDuration, stimPauseDuration, stimDechargeDuration, elicitedByExtraPulse (extra pulse,
%   status channel bit 16), stimAmbiguous, prePulses / postPulses (pulses without own contraction before / during
%   the contraction: 't<ms>|<mA>|<charge us>|<pause us>|<decharge us>', several joined by '&')
%   info.pulses (option pulseTable, default true; sheet / file 'pulses'): one row per stimulus pulse of the analysed
%   channels and ranges: pulse ID, time, extra pulse, current, durations, outcome (elicited / duringContraction /
%   noResponse), role (eliciting / pre / post), contraction, coupling interval, time since the last onset, phase
%
% OPTIONS (name/value pairs)
%   'output', file      write the results: .xlsx (sheets contractions, summary, parameters, info) or .csv
%   'report', r         analysis report (PDF, mda_report: channels to check with traces and the commands to open them
%                       in the GUI): default with 'output': <output without extension>_report.pdf; false: none; a
%                       file name: this file (also without 'output') (2026-10-11)
%   'labels', {..}      names of the time ranges (e.g. {'baseline','drug'})
%   'metadata', m       labels per channel (columns of both tables): struct, table or file (.csv/.xlsx) with
%                       setupID, sliceID, species, sampleID, sampleGroup, sliceGroup, tissue, treatment,
%                       concentration, concentrationUnit, daysInCulture, cultureStart, comment, analyst (+ own
%                       fields); see mda_labels. Example:
%                       m.species = 'human'; m.sliceID = {'S1','S2','S3'}; m.analyst = 'TS';
%   'showFigures', tf   plot the signal with the detected contractions (default false; ranges <= 30 min,
%                       at most 16 figures)
%   'quiet', tf         no messages (default false)
%   'settings', file    all options from a settings file (mda_settings; GUI: Advanced ... -> Save settings ...) or
%                       from the results of an earlier analysis; options given after it override them
%   'rocker', 'stopped' only contractions while the rocker is at rest are included ('any' (default), 'moving')
%   'beats', 'stimulated'  only stimulated contractions are included (default 'all')
%   'threshold', x      minimum peak prominence in uN (default 'auto'), one value for all channels or one value per
%                       channel (NaN = auto for that channel)
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
%                       amplitude_pctOfRef, amplitude_CV, irregular, ...). FFR protocols (2026-10-10): each frequency
%                       from its steady state (the last steadyStateBeats contractions of its longest run; rocker at
%                       rest if there are such contractions, see ffrRockerFallback); post-rest potentiation: reference
%                       per pause (prpReference); see mda_groupBeats.
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

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

if nargin < 1 || isempty(mddFile)
    [fn, pn] = uigetfile('*.mdd', 'MyoDish data file');
    if isequal(fn, 0), contractions = []; summary = []; info = []; return; end
    mddFile = fullfile(pn, fn);
end
if nargin < 2, channels = []; end
if nargin < 3 || isempty(fromSeconds), fromSeconds = 0; end
if nargin < 4 || isempty(toSeconds), toSeconds = inf; end

% ------------------------------------------------------------------ options
outputFile = ''; labels = {}; showFigures = false; quiet = false; chunkSeconds = 1800; metadata = []; reportOpt = [];
protocolSel = []; groupBy = '';
rest = {};
i = 1;
while i <= numel(varargin)
    key = varargin{i};
    if (ischar(key) || isstring(key)) && i < numel(varargin)
        switch lower(char(key))
            case 'output',       outputFile = char(varargin{i+1}); i = i + 2; continue;
            case 'report',       reportOpt = varargin{i+1}; i = i + 2; continue;
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
protW = zeros(0, 2);   %stimulation protocols: not used for the detection of arrhythmic pacing (2026-10-13)
if isempty(protocols) && opts.arrhythmicDetection
    try
        P0 = mda_protocols(H);
        if ~isempty(P0) && height(P0) > 0, protW = [P0.from(:) P0.to(:)]; end
    catch                                           %no log file / protocols: all windows
    end
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
protocolsAll = [];
protRow = (1:size(ranges, 1))';                     %row of every analysed range in protocolsAll
if ~isempty(protocols)          %every protocol on its own: one outside the data (or with an error, below) is not
    protocolsAll = protocols;   %analysed (note), the others are (2026-10-11)
    if ~ismember('note', protocolsAll.Properties.VariableNames)
        protocolsAll.note = repmat({''}, height(protocolsAll), 1);
    end
    empty = ranges(:,2) <= ranges(:,1);
    for r = find(empty)'
        why = sprintf('not analysed: outside the recorded data (%g ... %g s, file length %.1f s)', ...
            fromSeconds(r), toSeconds(r), H.totalSeconds);
        H.notes{end+1} = sprintf('protocol %s: %s', labels{r}, why);
        protocolsAll = addNote(protocolsAll, r, why);
    end
    if all(empty)
        error('No protocol within the recorded data (file length %.1f s).', H.totalSeconds);
    end
    protRow = find(~empty);
    ranges = ranges(~empty, :);
    protocols = protocols(~empty, :);
    labels = labels(~empty);
    groupByR = groupByR(~empty);
end
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
% detection threshold per channel ('auto', one value, or one value per channel; NaN = auto)
th = opts.threshold;
if ischar(th) || isscalar(th)
    thrOfChannel = @(c) th;
elseif numel(th) == numel(channels)
    thrOfChannel = @(c) th(c);
else
    error('threshold: ''auto'', one value for all channels or one value per channel (%d) expected.', numel(channels));
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
parts = {}; sumParts = {}; thrInfo = zeros(0, 8);
rfRows = {}; resParts = {}; pulseParts = {};
spikes = zeros(0, 4);                              %spike artifacts removed ('spikeRemoval'): channel, from, to, size
nFig = 0;
f0cache = [];                                       %rocker frequency per rocker speed, estimated once (all channels)
for r = 1:nR
    n0 = [numel(parts), numel(sumParts), size(thrInfo, 1), size(rfRows, 1), numel(resParts), numel(pulseParts), ...
        size(spikes, 1)];
    try
        edges = unique([ranges(r,1):chunkSeconds:ranges(r,2), ranges(r,2)]);
        nQ = numel(edges) - 1;
        Bc = cell(numel(channels), nQ); Cs = cell(numel(channels), nQ);
        lastB = cell(1, numel(channels)); lastC = cell(1, numel(channels));
        Sres = [];                                      %S2interval results: data of the whole range (traces)
        for q = 1:nQ
            % each chunk is read once for all channels; the file header (log file) is not read again
            S = mda_readMdd(H, max(0, edges(q) - pad), edges(q+1) + pad, opts);
            if isfield(S, 'spikes') && ~isempty(S.spikes)  %within the chunk (the padding belongs to the neighbours)
                sp = S.spikes;
                ok = sp(:,2) >= edges(q) & (sp(:,2) < edges(q+1) | (q == nQ & sp(:,2) <= edges(q+1))) & ...
                    ismember(sp(:,1), channels);
                spikes = [spikes; sp(ok, :)]; %#ok<AGROW>
            end
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
                optsC.threshold = thrOfChannel(c);
                [Bq, Cq] = mda_analyzeChannel(S, channels(c), sub, optsC);
                Bc{c,q} = Bq;
                lastB{c} = Bq; lastC{c} = Cq;           %control figure (single chunk)
                Cq.t = []; Cq.f = []; Cq.rockerArtifact = [];   %keep only the small fields of the earlier chunks
                Cs{c,q} = Cq;
                thrInfo(end+1,:) = [r, channels(c), edges(q), edges(q+1), Cq.threshold, Cq.maxStimToPeak, ...
                    max(0, edges(q) - pad), edges(q+1) + pad]; %#ok<AGROW>  data window read (GUI: open the results)
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
            Cm.stimTimes = inRangeOf(CsC, 'stimTimes', 'stimTimes');
            Cm.stimCaptured = inRangeOf(CsC, 'stimCaptured', 'stimTimes');
            Cm.stimCapturedCertain = inRangeOf(CsC, 'stimCapturedCertain', 'stimTimes');
            Cm.stimDuringContraction = inRangeOf(CsC, 'stimDuringContraction', 'stimTimes');
            Cm.extraTimes = inRangeOf(CsC, 'extraTimes', 'extraTimes');
            Cm.extraElicited = inRangeOf(CsC, 'extraElicited', 'extraTimes');
            Cm.threshold = median(cellfun(@(x) x.threshold, CsC));
            Cm.invertedSignal = any(cellfun(@(x) isfield(x, 'invertedSignal') && x.invertedSignal, CsC));   %2026-10-11
            if opts.pulseTable                         %pulses of the range: contraction numbers of the whole range
                Pc = cellfun(@(x) x.pulses, CsC(:), 'UniformOutput', false);
                Pc = vertcat(Pc{~cellfun(@isempty, Pc)});
                if ~isempty(Pc) && height(Pc) > 0
                    [tf, loc] = ismember(Pc.t_peak, B.t_peak);
                    Pc.contraction(:) = nan;
                    Pc.contraction(tf) = B.contraction(loc(tf));
                    pulseParts{end+1} = [table(repmat(labels(r), height(Pc), 1), 'VariableNames', {'range'}), Pc]; %#ok<AGROW>
                end
            end
            if grouping && ~strcmpi(groupByR{r}, 'none')
                steadyN = 0;                           %FFR protocols: steady state per frequency (2026-10-10)
                if istable(protocols) && strcmpi(protocols.type{r}, 'FFR'), steadyN = opts.steadyStateBeats; end
                [B, T, Z, gNotes] = mda_groupBeats(H, B, Cm, ranges(r,:), groupByR{r}, opts, steadyN);
                for q = 1:numel(gNotes)
                    H.notes{end+1} = sprintf('%s, channel %d: %s', labels{r}, channels(c), gNotes{q});
                end
                gb = lower(groupByR{r});
                if ismember(gb, {'pacingfrequency', 'stimcurrent', 's2interval', 'pauselength'})
                    trace = [];
                    if strcmp(gb, 's2interval')            %S2 response: traces of the whole range
                        if isempty(Sres), Sres = mda_readMdd(H, max(0, ranges(r,1) - 2), ranges(r,2) + 2, opts); end
                        optsC = opts; optsC.zeroForce = zeroOfChannel(c); optsC.threshold = thrOfChannel(c);
                        [~, Cx] = mda_analyzeChannel(Sres, channels(c), ranges(r,:), optsC);
                        trace = struct('t', Cx.t, 'f', Cx.f, 'tR', Sres.t, 'rockerOn', Sres.rockerOn);
                    end
                    Rr = mda_protocolResults(groupByR{r}, T, Z, trace, opts);
                    pNote = {''};                      %note of the protocol (e.g. 'no end comment: end estimated ...')
                    if istable(protocols) && ismember('note', protocols.Properties.VariableNames)
                        pNote = protocols.note(r);
                    end
                    resParts{end+1} = [table(labels(r), channels(c), ranges(r,1), ranges(r,2), groupByR(r), ...
                        'VariableNames', {'range','channel','from','to','groupBy'}), Rr, ...
                        table(pNote, 'VariableNames', {'protocolNote'})]; %#ok<AGROW>
                end
            else
                T = mda_summarize(B, Cm, ranges(r,:), opts, protW);
                if grouping                            %same columns as the grouped ranges
                    B.group = repmat({'all'}, height(B), 1); B.groupValue = nan(height(B), 1); B.groupRole = repmat({''}, height(B), 1);
                    B.groupStep = nan(height(B), 1);
                    T = addvars(T, nan, nan, 'After', 'missedBeats_percent', 'NewVariableNames', {'capture_percent', 'currentReached_percent'});
                    T = addvars(T, nan(height(T), 1), 'After', 'amplitude_SD', 'NewVariableNames', 'amplitude_pctOfRef');
                    T = addvars(T, nan(height(T), 1), 'After', 'amplitude_CV', 'NewVariableNames', 'irregular');
                    T = [table({'all'}, nan, {''}, nan, {'none'}, 'VariableNames', {'group','groupValue','groupRole','groupStep','groupBy'}), T]; %#ok<AGROW>
                end
            end
            T.invertedSignal = repmat(Cm.invertedSignal, height(T), 1);   %signal inverted in (a chunk of) the range
            T = [table(repmat(labels(r), height(T), 1), 'VariableNames', {'range'}), T]; %#ok<AGROW>
            sumParts{end+1} = T; %#ok<AGROW>
            B = [table(repmat(labels(r), height(B), 1), 'VariableNames', {'range'}), B]; %#ok<AGROW>
            parts{end+1} = B; %#ok<AGROW>
            if ~quiet
                fprintf('  %s, channel %d: %d contractions detected (%d uncertain), %d included (threshold %.0f uN, %s)\n', ...
                    labels{r}, channels(c), height(B), sum(B.uncertain), sum(B.included), Cm.threshold, Cm.thresholdMode);
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
    catch ME                                        %protocols: the others are analysed (2026-10-11)
        if isempty(protocols), rethrow(ME); end
        parts = parts(1:n0(1)); sumParts = sumParts(1:n0(2)); thrInfo = thrInfo(1:n0(3), :);
        rfRows = rfRows(1:n0(4), :); resParts = resParts(1:n0(5)); pulseParts = pulseParts(1:n0(6));
        spikes = spikes(1:n0(7), :);
        why = sprintf('not analysed: %s', ME.message);
        H.notes{end+1} = sprintf('protocol %s: %s', labels{r}, why);
        protocolsAll = addNote(protocolsAll, protRow(r), why);
    end
end
if isempty(parts)
    error('No range analysed: %s', strjoin(H.notes(max(1, end-nR+1):end), ' | '));
end
thrInfo = sortrows(thrInfo, [1 2 3]);                %order: range, channel, time
contractions = vertcat(parts{:});
summary = vertcat(sumParts{:});
summary = arrhythmicPacing(summary, opts, ~isempty(protocols));   %2026-10-13

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
if ~isempty(spikes)
    spikes = unique(spikes, 'rows');                  %ranges that overlap: once
    [cs, ~, ic] = unique(spikes(:,1));
    ns = accumarray(ic, 1);
    spParts = arrayfun(@(c, k) sprintf('channel %d: %d', c, k), cs, ns, 'UniformOutput', false);
    info.notes{end+1} = sprintf('Spike artifacts removed (option spikeRemoval): %d (%s), largest %g AU.', ...
        size(spikes, 1), strjoin(spParts', ', '), max(spikes(:,4)));
end
info.spikes = spikes;
if opts.pulseTable                                 %all stimulus pulses of the analysed channels and ranges (2026-10-10)
    if isempty(pulseParts)
        info.pulses = table();
    else
        info.pulses = vertcat(pulseParts{:});
    end
end
info.channels = channels;
info.ranges = ranges;
info.rangeLabels = labels;
if ~isempty(protocolsAll), info.protocols = protocolsAll; else, info.protocols = protocols; end   %all, with notes
info.groupBy = groupByR;
if ~isempty(resParts), info.protocolResults = PR; end
info.labels = Lbl;
info.options = opts;
info.thresholds = array2table(thrInfo, 'VariableNames', {'range','channel','from','to','threshold_uN','maxStimToPeak_s', ...
    'windowFrom','windowTo'});
% 2026-10-09: rows of the info table (mda_writeResults) to reproduce the analysis (MyoDishAnalysisGUI: open results)
info.extra = {'createdBy', 'MyoDishAnalysis'; 'channels', mat2str(channels); 'chunkSeconds', sprintf('%.15g', chunkSeconds)};
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
rep = mda_report('path', outputFile, reportOpt);
if ~isempty(rep)                                   %analysis report (2026-10-11)
    R = mda_report('analysis', rep, H.file, contractions, summary, info, outputFile);
    if ~quiet
        k = find(strcmp(R.level, 'check'));
        fprintf('  report written to %s%s\n', rep, repmat(sprintf(' (%d channel(s) to check)', numel(k)), 1, ~isempty(k)));
        for j = k(:)'                              %clickable in the command window
            if feature('hotlinks')
                fprintf('    <a href="matlab:%s">open channel %d (%s)</a>\n', R.matlab{j}, R.channel(j), R.red{j});
            else
                fprintf('    %s\n', R.matlab{j});
            end
        end
    end
end
end


% =====================================================================================================
function T = arrhythmicPacing(T, opts, protocolMode)
% column arrhythmicPacing after pacedSeconds (2026-10-13): channels of arrhythmicChannels and (arrhythmicDetection,
% not in analyses of the stimulation protocols) channels whose variable windows (stimulus interval CV >
% arrhythmicMinVariability) make up more than arrhythmicMinFraction of the paced time of the analysed ranges
% (windows overlapping a stimulation protocol of the log file are not counted, see mda_summarize)
if isempty(T) || ~all(ismember({'pacedSeconds', 'channel'}, T.Properties.VariableNames)), return; end
ap = false(height(T), 1);
chan = double(T.channel);
uc = unique(chan(~isnan(chan)));
for k = 1:numel(uc)
    m = chan == uc(k);
    on = ismember(uc(k), opts.arrhythmicChannels);
    if ~on && opts.arrhythmicDetection && ~protocolMode
        w = T.pacedSeconds(m); f = T.arrhythmicFraction(m);
        ok = w > 0 & ~isnan(f);
        on = any(ok) && sum(w(ok) .* f(ok)) / sum(w(ok)) > opts.arrhythmicMinFraction;
    end
    ap(m) = on;
end
T = addvars(T, ap, 'After', 'pacedSeconds', 'NewVariableNames', 'arrhythmicPacing');
end


function v = inRangeOf(CsC, field, timeField)
% values of the field of all chunks (channel info of mda_analyzeChannel) whose times lie in the chunk's range
parts = cell(numel(CsC), 1);
for i = 1:numel(CsC)
    x = CsC{i};
    if ~isfield(x, field) || ~isfield(x, timeField), continue; end
    tt = x.(timeField);
    y = x.(field);
    parts{i} = reshape(y(tt >= x.range(1) & tt <= x.range(2)), [], 1);
end
v = vertcat(parts{:});
if isempty(v), v = zeros(0, 1); end
end


function s = shortName(file)
[~, n, e] = fileparts(file);
s = [n e];
end

function plotChannel(C, B, S, range, ttl)
fh = figure('Name', ttl, 'Color', 'w');
try fh.Theme = 'light'; catch, end                 %light colors also with a dark theme (R2025a+)
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


function P = addNote(P, r, why)
%note of protocol row r (protocols table)
old = P.note{r};
if isempty(old) || (isnumeric(old) && all(isnan(old))), P.note{r} = why; else, P.note{r} = [char(old) '; ' why]; end
end
