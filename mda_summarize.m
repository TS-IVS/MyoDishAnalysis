function T = mda_summarize(B, C, range, opts, exclude)
%MDA_SUMMARIZE  One summary row (mean and SD of the included contractions) for one channel and time range.
%
%   T = mda_summarize(B, C, range)
%   T = mda_summarize(B, C, range, opts, exclude)
%
%   B        contraction table of one channel (mda_analyzeChannel); only rows with included = true and a peak
%            within range are averaged
%   C        channel info from mda_analyzeChannel (stimulus times, threshold)
%   range    [from to] in s; several ranges (n x 2, 2026-10-14): one row over all of them (union; from / to = first
%            start / last end, stimFrequency from the intervals within the ranges)
%   opts     options (arrhythmicWindow, arrhythmicMinVariability; [] = defaults)
%   exclude  [from to] rows of the stimulation protocols (stim-to-stim variability: windows overlapping them are
%            skipped)
%
% Columns: channel, from, to, nContractions (included), nDetected, nStimulated, nExtraBeats, nStimuli, nMissedBeats,
% extraBeats_percent, missedBeats_percent, nUncertain, nStimulatedUncertain, nExtraBeatsUncertain,
% nMissedBeatsUncertain (uncertain contractions, see mda_analyzeChannel, option 'detection'; missed: stimuli followed
% only by an uncertain contraction), nMissedDuringContraction (missed: the regular pulse fell into a contraction
% elicited by another pulse), nExtraPulses (status channel bit 16), nElicitedByExtraPulse, nAmbiguous (stimAmbiguous),
% stimFrequency (Hz, from the median stimulus interval in the range), stimVariability_percent (median CV of the stimulus
% intervals in windows of arrhythmicWindow, %), arrhythmicFraction (fraction of the paced time in windows whose CV
% exceeds arrhythmicMinVariability), pacedSeconds (paced time of these windows: >= 5 intervals, no overlap with
% exclude; 2026-10-13; MyoDishAnalysis adds arrhythmicPacing),
% detectionThreshold (uN), zeroForce (uN, zero of diastolicForce), sensorRate_inferred (Hz) and repeatedSamples_percent
% (sensor rate of the channel inferred from repeated raw values in the window read, see mda_readMdd; 2026-10-21),
% then <parameter>_mean, <parameter>_SD and
% <parameter>_n (number of included contractions with a value of this parameter, 2026-10-05) for every parameter;
% amplitude_CV after amplitude_n (population SD / mean of the included amplitudes, NaN with < 2; 2026-10-10).
% With a reference beat (option referenceBeat): <parameter>_pctRef_mean / _SD (% of the reference) and
% diastolicForce_dRef / diastolicSignal_dRef _mean / _SD (difference to the reference, uN), 2026-10-06.
% With AP columns (EP recording, mda_analyzeAP): AP_dVdtMax, AP_RMP, AP_Vmax, APD25, APD50, APD90 _mean / _SD / _n.
%
% TS 2026-10-04 (uncertain contractions 2026-10-09; extra pulses 2026-10-10; stimulus variability 2026-10-13; several
% ranges 2026-10-14)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

if nargin < 4 || isempty(opts), opts = mda_options(); end
if nargin < 5, exclude = []; end
PI = mda_parameters();
params = PI(:,1)';

R = reshape(double(range), [], 2);                  %one or several ranges [from to] (2026-10-14)
inRange = inRanges(B.t_peak, R);
I = inRange & B.included;

ST = C.stimTimes;
J = inRanges(ST, R);
fStim = nan;
iv = [];                                            %stimulus intervals within the ranges
for r = 1:size(R, 1)
    x = ST(ST >= R(r,1) & ST <= R(r,2));
    iv = [iv; diff(x(:))]; %#ok<AGROW>
end
if ~isempty(iv), fStim = 1 / median(iv); end
zeroF = nan;
if isfield(C, 'zeroForce'), zeroF = C.zeroForce; end

T = table(C.channel, min(R(:,1)), max(R(:,2)), sum(I), sum(inRange), sum(inRange & strcmp(B.beatType,'stimulated')), ...
    sum(inRange & strcmp(B.beatType,'extra')), sum(J), sum(J & ~C.stimCaptured), fStim, C.threshold, zeroF, ...
    'VariableNames', {'channel','from','to','nContractions','nDetected','nStimulated','nExtraBeats','nStimuli', ...
    'nMissedBeats','stimFrequency','detectionThreshold','zeroForce'});
% 2026-10-05: extra beats = detected contractions without an adequate stimulus (peak not 25 ms ... min(CL, 1 s) after a
% stimulus); missed beats = stimuli without a detected contraction (below the detection threshold). Both over the whole
% range, independent of the rocker / stimulated filters. Percent of the detected contractions / of the stimuli.
pExtra = nan; pMissed = nan;
if T.nDetected > 0, pExtra = 100 * T.nExtraBeats / T.nDetected; end
if T.nStimuli > 0, pMissed = 100 * T.nMissedBeats / T.nStimuli; end
T = addvars(T, pExtra, pMissed, 'After', 'nMissedBeats', 'NewVariableNames', {'extraBeats_percent', 'missedBeats_percent'});
% 2026-10-09: uncertain contractions (column uncertain, option 'detection'): all, stimulated, extra beats, and missed
% beats that are uncertain (stimuli followed only by an uncertain contraction: missed with 'detection','specific')
u = inRange & B.uncertain;
nMU = 0;
if isfield(C, 'stimCapturedCertain'), nMU = sum(J & C.stimCaptured & ~C.stimCapturedCertain); end
T = addvars(T, sum(u), sum(u & strcmp(B.beatType, 'stimulated')), sum(u & strcmp(B.beatType, 'extra')), nMU, ...
    'After', 'missedBeats_percent', 'NewVariableNames', {'nUncertain', 'nStimulatedUncertain', 'nExtraBeatsUncertain', ...
    'nMissedBeatsUncertain'});
% 2026-10-10: extra pulses (status channel bit 16), contractions elicited by them, ambiguous assignments, missed beats
% whose pulse fell into a contraction elicited by another pulse (refractory)
nDur = 0; nXP = 0; nEl = 0; nAmb = 0;
if isfield(C, 'stimDuringContraction') && numel(C.stimDuringContraction) == numel(ST)
    nDur = sum(J & C.stimDuringContraction(:) & ~C.stimCaptured(:));
end
if isfield(C, 'extraTimes'), nXP = sum(inRanges(C.extraTimes, R)); end
if ismember('elicitedByExtraPulse', B.Properties.VariableNames), nEl = sum(inRange & B.elicitedByExtraPulse); end
if ismember('stimAmbiguous', B.Properties.VariableNames), nAmb = sum(inRange & B.stimAmbiguous); end
T = addvars(T, nDur, nXP, nEl, nAmb, 'After', 'nMissedBeatsUncertain', 'NewVariableNames', ...
    {'nMissedDuringContraction', 'nExtraPulses', 'nElicitedByExtraPulse', 'nAmbiguous'});
% 2026-10-13: stim-to-stim variability of the regular pulses (arrhythmic pacing)
[vCV, vFrac, vDur] = stimVariability(ST(J), R, optionOr(opts, 'arrhythmicWindow', 60), ...
    optionOr(opts, 'arrhythmicMinVariability', 0.1), exclude);
T = addvars(T, vCV, vFrac, vDur, 'After', 'stimFrequency', 'NewVariableNames', ...
    {'stimVariability_percent', 'arrhythmicFraction', 'pacedSeconds'});
% 2026-10-21: sensor rate of the channel inferred from repeated raw values (mda_readMdd)
sr = nan; rp = nan;
if isfield(C, 'sensorRate'), sr = C.sensorRate; rp = C.repeatedSamples_percent; end
T = addvars(T, sr, rp, 'After', 'zeroForce', 'NewVariableNames', {'sensorRate_inferred', 'repeatedSamples_percent'});
for k = 1:numel(params)
    v = B.(params{k})(I);
    T.([params{k} '_mean']) = mean(v, 'omitnan');
    T.([params{k} '_SD']) = std(v, 'omitnan');
    T.([params{k} '_n']) = sum(~isnan(v));                %contractions with a value of this parameter
end
% 2026-10-10: coefficient of variation of the amplitude (population SD / mean; irregular groups, mda_groupBeats)
v = B.amplitude(I); v = v(~isnan(v));
cv = nan;
if numel(v) >= 2, cv = std(v, 1) / mean(v); end
T = addvars(T, cv, 'After', 'amplitude_n', 'NewVariableNames', 'amplitude_CV');
% 2026-10-06: parameters relative to the reference beat (columns of B, option referenceBeat): mean and SD
rel = B.Properties.VariableNames(endsWith(B.Properties.VariableNames, {'_pctRef', '_dRef'}));
for k = 1:numel(rel)
    v = B.(rel{k})(I);
    T.([rel{k} '_mean']) = mean(v, 'omitnan');
    T.([rel{k} '_SD']) = std(v, 'omitnan');
end
% 2026-10-06: AP parameters of an EP recording (columns of mda_analyzeAP): mean, SD, n
AP = mda_analyzeAP('parameters');
for k = 1:size(AP, 1)
    if ~ismember(AP{k,1}, B.Properties.VariableNames), continue; end
    v = B.(AP{k,1})(I);
    T.([AP{k,1} '_mean']) = mean(v, 'omitnan');
    T.([AP{k,1} '_SD']) = std(v, 'omitnan');
    T.([AP{k,1} '_n']) = sum(~isnan(v));
end
end


function [medCV, frac, dur] = stimVariability(ST, R, window, minCV, X)
% stim-to-stim variability of the regular pulses ST in the ranges R (rows [from to]; 2026-10-13): windows of window s
% from the start of each range (the last one shorter); paced windows: >= 6 pulses and no overlap with the [from to]
% rows of X (stimulation protocols); CV = population SD / mean of their intervals. Median CV (%), fraction of the paced
% time with CV > minCV, paced time (s); NaN, NaN, 0 without paced windows.
ST = sort(double(ST(:)));
if isempty(X), X = zeros(0, 2); else, X = reshape(double(X), [], 2); end
cvs = []; dur = 0; tVar = 0;
for r = 1:size(R, 1)
    a = double(R(r,1)); b = double(R(r,2));
    w = a;
    while w < b
        e = min(w + double(window), b);
        x = ST(ST >= w & ST < e);
        if numel(x) >= 6 && ~any(X(:,1) < e & X(:,2) > w)
            iv = diff(x);
            cv = std(iv, 1) / mean(iv);
            cvs(end+1) = cv; %#ok<AGROW>
            dur = dur + (e - w);
            if cv > minCV, tVar = tVar + (e - w); end
        end
        w = e;
    end
end
if isempty(cvs)
    medCV = nan; frac = nan; dur = 0;
else
    medCV = 100 * median(cvs); frac = tVar / dur;
end
end


function tf = inRanges(t, R)
% t within one of the ranges R (rows [from to], bounds included)
tf = false(size(t));
for r = 1:size(R, 1), tf = tf | (t >= R(r,1) & t <= R(r,2)); end
end


function v = optionOr(opts, name, default)
% option of opts, default if missing (options of older versions)
v = default;
if isstruct(opts) && isfield(opts, name), v = opts.(name); end
end
