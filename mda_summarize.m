function T = mda_summarize(B, C, range)
%MDA_SUMMARIZE  One summary row (mean and SD of the included contractions) for one channel and time range.
%
%   T = mda_summarize(B, C, range)
%
%   B      contraction table of one channel (mda_analyzeChannel); only rows with included = true and a peak
%          within range are averaged
%   C      channel info from mda_analyzeChannel (stimulus times, threshold)
%   range  [from to] in s
%
% Columns: channel, from, to, nContractions (included), nDetected, nStimulated, nExtraBeats, nStimuli, nMissedBeats,
% extraBeats_percent, missedBeats_percent, nUncertain, nStimulatedUncertain, nExtraBeatsUncertain,
% nMissedBeatsUncertain (uncertain contractions, see mda_analyzeChannel, option 'detection'; missed: stimuli followed
% only by an uncertain contraction), stimFrequency (Hz, from the median stimulus interval in the range),
% detectionThreshold (uN), zeroForce (uN, zero of diastolicForce), then <parameter>_mean, <parameter>_SD and
% <parameter>_n (number of included contractions with a value of this parameter, 2026-10-05) for every parameter.
% With a reference beat (option referenceBeat): <parameter>_pctRef_mean / _SD (% of the reference) and
% diastolicForce_dRef / diastolicSignal_dRef _mean / _SD (difference to the reference, uN), 2026-10-06.
% With AP columns (EP recording, mda_analyzeAP): AP_dVdtMax, AP_RMP, AP_Vmax, APD25, APD50, APD90 _mean / _SD / _n.
%
% TS 2026-10-04 (uncertain contractions 2026-10-09)

PI = mda_parameters();
params = PI(:,1)';

inRange = B.t_peak >= range(1) & B.t_peak <= range(2);
I = inRange & B.included;

ST = C.stimTimes;
J = ST >= range(1) & ST <= range(2);
fStim = nan;
if sum(J) > 1, fStim = 1 / median(diff(ST(J))); end
zeroF = nan;
if isfield(C, 'zeroForce'), zeroF = C.zeroForce; end

T = table(C.channel, range(1), range(2), sum(I), sum(inRange), sum(inRange & strcmp(B.beatType,'stimulated')), ...
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
for k = 1:numel(params)
    v = B.(params{k})(I);
    T.([params{k} '_mean']) = mean(v, 'omitnan');
    T.([params{k} '_SD']) = std(v, 'omitnan');
    T.([params{k} '_n']) = sum(~isnan(v));                %contractions with a value of this parameter
end
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
