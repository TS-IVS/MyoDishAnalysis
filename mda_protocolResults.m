function [R, G2] = mda_protocolResults(by, G, Z, trace, opts)
%MDA_PROTOCOLRESULTS  Characteristic values of a stimulation protocol (one channel, one range) from the grouped summary.
%
%   [R, G2] = mda_protocolResults(by, G, Z, trace, opts)
%
%   by     grouping of the range ('pacingFrequency', 'stimCurrent', 'S2interval', 'pauseLength'; others: note only)
%   G      group summary of the channel and range ([B, G, Z] = mda_groupBeats(...))
%   Z      stimuli of the channel (third output of mda_groupBeats); needed for S2interval
%   trace  S2interval: struct t, f (filtered force of the channel: mda_analyzeChannel C.t / C.f), tR, rockerOn (rocker
%          state of the samples: mda_readMdd S.t / S.rockerOn); [] for the other quantities
%   opts   options (rocker 'stopped': template and S2 windows only while the rocker is at rest)
%
%   R      one-row table, all columns (NaN where not applicable):
%   Captured group: at most max(1, 10 % of its stimuli) not followed by a contraction and >= 2 followed (as in
%   GetFFRdata / GetStimThreshold: at most 1 skipped stimulus per rocker stop).
%   FFR (pacingFrequency)
%     maxCapturedFrequency_Hz   highest captured pacing frequency
%     amplitude_0p5Hz_uN        mean amplitude at 0.5 Hz (captured group; groups: frequencies rounded to
%                               opts.frequencyResolution, 0.1 Hz, below 1 Hz frequencyResolutionLow, 0.05 Hz, see
%                               mda_groupBeats)
%     FFR_1Hz_pct, FFR_2Hz_pct, FFR_3Hz_pct   mean amplitude at 1 / 2 / 3 Hz in % of 0.5 Hz (captured groups)
%   ST (stimCurrent)
%     captureThreshold_mA       lowest captured current
%     stimThreshold10_mA ... 99 lowest captured current with a mean amplitude >= 10 / 50 / 95 / 99 % of the largest
%                               mean amplitude of the captured currents (thresh10 ... thresh99 of GetStimThreshold)
%     maxAmplitude_uN           largest mean amplitude of the captured currents
%   RP (S2interval): S2 response by subtraction of the scaled mean steady-state S1 contraction (GetRefractoryPeriod
%     2026-10-06). Template = mean S1 contraction (S1 interval before and after, rocker at rest), scaled per S2 on
%     S1 ... S2 + 20 ms. Response = maximum of the residual (30-ms mean) S2 + 30 ms ... min(S2 + 600 ms, S1 interval -
%     100 ms) in % of the S1 amplitude. Separate peak = local maximum of the S1+S2 trace S2 + 25 ms ... min(S2 + 600 ms,
%     next stimulus + 20 ms; not before the S1 peak of the template + 10 ms, 2026-10-23: at intervals shorter than the
%     time to peak the S1 peak itself is no separate peak) with a prominence >= max(noise level, 2 %) of S1 (and
%     response >= noise level). Noise
%     level = 99th percentile of the response at pseudo-S2 on the template beats (leave-one-out template).
%     Without steady-state S1 beats (fewer than 3; S1-S2 pairs in every period, e.g. the human standard schedule:
%     S1 at 0, S2 at 80 ... 960 ms, period 2 s; 2026-10-23): template = mean S1 contraction of the pairs with the
%     longest S2 interval (rocker at rest), cut 20 ms before their S2 and held at the mean of the 50 ms before the
%     cut, which must be <= 10 % of the peak (the S1 contraction has relaxed; otherwise no template, note). The
%     noise level then uses pseudo-S2 intervals that end >= 100 ms before the cut. Note 'template: S1 of the N pairs
%     at <interval> ms'.
%     refPeriodNoPeak_ms        S2 interval below which there is no separate contraction peak (fraction of S2 with
%                               a separate peak < 50 %)
%     refPeriodNoResponse_ms    S2 interval below which there is no response at all (median response < noise level)
%     ...Step_ms                distance of the two intervals around the transition (uncertainty ~ +-Step/2)
%     refPeriodAllCaptured_ms   (2026-10-10) from long to short S2 intervals, the interval before the first one at
%                               which not every S2 had a separate peak (definition above); every S2 with a separate
%                               peak: the shortest interval (note); already at the longest one: NaN (note). Definition
%                               as the refractory period of the MyoDish export, but more sensitive to a single S2
%                               without a separate peak: in 323 recordings of human slices refPeriodNoPeak_ms agreed
%                               better with the export (within 10 %: 95 vs 85 %; bias -1 vs +13 ms)
%     Transition: the first interval (from long to short) below the level whose next shorter interval is also
%     below it; linear interpolation with the previous (longer) interval. Not reached / already at the longest
%     interval: NaN and a note. Noise level >= 50 %: NaN (no reliable S1 contraction).
%     S2shortest_ms, S2longest_ms   shortest / longest analysed S2 interval (NaN with 'not reached': the transition
%                               is below S2shortest_ms; 'already at the longest interval': above S2longest_ms)
%     S2noiseLevel_pct, amplitudeS1_uN, nS2, nTemplateBeats
%   PRP (pauseLength)
%     PRP15_pct, PRP30_pct, PRP60_pct   amplitude in % of the reference (option prpReference, default: median of the
%                               last 6 contractions before the pause) after a pause of 15 / 30 / 60 s
%                               (pause = stimulus interval - steady interval; within +-opts.pauseTolerance, default
%                               10 %; several pauses: their mean, resultNote)
%     PRP15_pause_s, ...        the pause (mean of these pauses)
%   resultNote
%   G2 (S2interval, 2026-10-21): table groupValue_ms, S2response_pct (median S2 response of the group, % of the S1
%   amplitude), separatePeak_percent (% of its S2 with a separate peak) for the columns of the group summary;
%   otherwise empty
%
% TS 2026-10-07 (tolerances frequencyResolution / pauseTolerance 2026-10-10: FFR groups at 0.1 Hz (below 1 Hz
% 0.05 Hz), before +-5 %;
% pauses +-10 %, before the nearest pause within +-50 %; refPeriodAllCaptured 2026-10-10)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

if nargin < 5 || isempty(opts), opts = struct(); end
fRes = 0.1; if isfield(opts, 'frequencyResolution'), fRes = opts.frequencyResolution; end
fResLow = 0.05; if isfield(opts, 'frequencyResolutionLow'), fResLow = opts.frequencyResolutionLow; end
pTol = 0.1; if isfield(opts, 'pauseTolerance'), pTol = opts.pauseTolerance; end
cols = resultColumns();
R = cell2table([num2cell(nan(1, numel(cols) - 2)), {'', ''}], 'VariableNames', cols);   %variant, resultNote: text
G2 = [];                                               %S2 groups (S2interval only)
notes = {};
if isempty(G) || height(G) == 0
    R.resultNote = {'no groups'};
    return;
end
val = G.groupValue;
amp = G.amplitude_mean;
role = cellstr(G.groupRole);
cap = capturedGroups(G);
switch lower(char(by))
    case 'pacingfrequency'
        ok = cap & ~isnan(val);
        R.variant = {variantText('%g-%g Hz (%d steps)', val)};
        if any(ok), R.maxCapturedFrequency_Hz = max(val(ok)); end
        a05 = ampAt(val, amp, cap, 0.5, fResLow);
        R.amplitude_0p5Hz_uN = a05;
        R.FFR_1Hz_pct = 100 * ampAt(val, amp, cap, 1, fRes) / a05;
        R.FFR_2Hz_pct = 100 * ampAt(val, amp, cap, 2, fRes) / a05;
        R.FFR_3Hz_pct = 100 * ampAt(val, amp, cap, 3, fRes) / a05;
        if isnan(a05), notes{end+1} = 'no captured 0.5 Hz group'; end
    case 'stimcurrent'
        ok = cap & ~isnan(val);
        R.variant = {variantText('%g-%g mA (%d steps)', val)};
        if any(ok), R.captureThreshold_mA = min(val(ok)); end
        oka = ok & ~isnan(amp);
        if any(oka)
            mx = max(amp(oka));
            R.maxAmplitude_uN = mx;
            for x = [10 50 95 99]
                R.(sprintf('stimThreshold%d_mA', x)) = min(val(oka & amp >= x / 100 * mx));
            end
        else
            notes{end+1} = 'no captured current with included contractions';
        end
    case 'pauselength'
        st = find(strcmp(role, 'steady'), 1);
        cl = nan;
        if ~isempty(st), cl = 1 / G.stimFrequency(st); end
        pr = find(strcmp(role, 'postRest') & ~isnan(val));
        pause = val(pr) - cl;
        pct = G.amplitude_pctOfRef(pr);
        % pauses of the protocol in ascending order (2026-10-23): PRP1 ... PRP8 (pauses within pauseTolerance have one
        % group value, mda_groupBeats; several pauses of one length: their mean); variant = the list of pauses
        pv = unique(val(pr));
        for q = 1:min(8, numel(pv))
            k = find(val(pr) == pv(q));
            R.(sprintf('PRP%d_pct', q)) = mean(pct(k), 'omitnan');
            R.(sprintf('PRP%d_pause_s', q)) = mean(pause(k));
        end
        if ~isempty(pv) && ~isnan(cl)
            R.variant = {sprintf('pauses %s s', strjoin(arrayfun(@(x) sprintf('%.3g', x), pv' - cl, 'UniformOutput', false), '/'))};
        end
        for x = [15 30 60]
            if ~isempty(pr) && ~isnan(cl)
                k = find(abs(pause - x) <= pTol * x + 1e-9);
                if ~isempty(k)
                    R.(sprintf('PRP%d_pct', x)) = mean(pct(k), 'omitnan');
                    R.(sprintf('PRP%d_pause_s', x)) = mean(pause(k));
                    if numel(k) > 1, notes{end+1} = sprintf('PRP%d: mean of %d pauses', x, numel(k)); end %#ok<AGROW>
                end
            end
        end
        if isnan(cl), notes{end+1} = 'no steady group'; end
    case 's2interval'
        if isempty(Z) || isempty(trace)
            notes{end+1} = 'S2 response: no data';
        else
            [R, n2, G2] = s2Results(R, Z, trace, opts);
            notes = [notes, n2];
        end
end
R.resultNote = {strjoin(notes, '; ')};
end


% =====================================================================================================
function c = resultColumns()
c = {'maxCapturedFrequency_Hz', 'amplitude_0p5Hz_uN', 'FFR_1Hz_pct', 'FFR_2Hz_pct', 'FFR_3Hz_pct', ...
    'captureThreshold_mA', 'stimThreshold10_mA', 'stimThreshold50_mA', 'stimThreshold95_mA', 'stimThreshold99_mA', ...
    'maxAmplitude_uN', ...
    'refPeriodNoPeak_ms', 'refPeriodNoPeakStep_ms', 'refPeriodNoResponse_ms', 'refPeriodNoResponseStep_ms', ...
    'refPeriodAllCaptured_ms', ...
    'S2shortest_ms', 'S2longest_ms', 'S2noiseLevel_pct', 'amplitudeS1_uN', 'nS2', 'nTemplateBeats', ...
    'PRP15_pct', 'PRP15_pause_s', 'PRP30_pct', 'PRP30_pause_s', 'PRP60_pct', 'PRP60_pause_s', ...
    'PRP1_pct', 'PRP1_pause_s', 'PRP2_pct', 'PRP2_pause_s', 'PRP3_pct', 'PRP3_pause_s', ...
    'PRP4_pct', 'PRP4_pause_s', 'PRP5_pct', 'PRP5_pause_s', 'PRP6_pct', 'PRP6_pause_s', ...
    'PRP7_pct', 'PRP7_pause_s', 'PRP8_pct', 'PRP8_pause_s', ...
    'variant', 'resultNote'};
end


function s = variantText(fmt, val)
% '<min>-<max> <unit> (<n> steps)' of the group values (protocol variant, 2026-10-23)
v = unique(val(~isnan(val)));
s = '';
if ~isempty(v), s = sprintf(fmt, min(v), max(v), numel(v)); end
end


function cap = capturedGroups(G)
% at most max(1, 10 % of the stimuli) not followed by a contraction and >= 2 followed
n = G.nStimuli;
nf = round(G.capture_percent / 100 .* n);
cap = (n - nf) <= max(1, floor(0.1 * n)) & nf >= 2;
end


function a = ampAt(val, amp, cap, f, res)
% amplitude of the captured group at f (group values rounded to res, see mda_groupBeats: within +-res / 2)
a = nan;
k = find(cap & abs(val - f) <= res / 2 + 1e-9);
if isempty(k), return; end
[~, i] = min(abs(val(k) - f));
a = amp(k(i));
end


function p = mprctile(x, q)
% prctile of a vector (NaN ignored), as the Statistics Toolbox
x = sort(x(~isnan(x)));
n = numel(x);
p = nan;
if n == 0, return; end
if n == 1, p = x(1); return; end
pos = 100 * ((1:n)' - 0.5) / n;
p = interp1(pos, x(:), min(max(q, pos(1)), pos(end)));
end


function [est, step, notes] = transition(ci, v, level, name, notes)
% first interval (from long to short) at which v falls below level and stays below: at the next shorter interval, or
% (2026-10-21) in the median of this and all shorter intervals (a single value just above the level among the
% shortest intervals, e.g. 5.3 % against a noise level of 4.6 % at the last interval, does not undo a transition);
% linear interpolation with the previous interval (GetRefractoryPeriod)
est = nan; step = nan;
keep = ~isnan(v); ci = ci(keep); v = v(keep);
if isempty(v) || isnan(level), notes{end+1} = [name ': not determined']; return; end
below = v(:) < level;
rest = arrayfun(@(i) median(v(i:end)) < level, (1:numel(v))');
k = find(below & ([below(2:end); true] | rest), 1, 'first');
if isempty(k)
    notes{end+1} = sprintf('%s: not reached (< %g ms)', name, ci(end));
elseif k == 1
    notes{end+1} = sprintf('%s: already at the longest interval (> %g ms)', name, ci(1));
else
    step = ci(k-1) - ci(k);
    est = ci(k) + (level - v(k)) / (v(k-1) - v(k)) * step;
end
end


function [R, notes, G2] = s2Results(R, Z, trace, opts)
notes = {}; G2 = [];
t = double(trace.t(:)); f = double(trace.f(:));
tR = double(trace.tR(:)); rock = logical(trace.rockerOn(:));
stopped = isstruct(opts) && isfield(opts, 'rocker') && strcmp(opts.rocker, 'stopped');
st = Z.t; role = cellstr(Z.role); val = Z.value; inR = logical(Z.inRange);
prevI = Z.prevInt; ni = Z.nextInt;
p = prevI(strcmp(role, 'S1') & inR);
p = p(~isnan(p));
jS2 = find(strcmp(role, 'S2') & inR);
if isempty(p) && ~isempty(jS2)                      %S1-S2 pairs in every period, no other S1: the period (2026-10-23)
    q = jS2(jS2 > 1 & jS2 < numel(st));
    p = st(q + 1) - st(q - 1);
    p = p(~isnan(p));
end
if numel(t) < 10 || isempty(p)
    notes = {'S2 response: no S1 stimuli'}; return;
end
S1 = median(p);
dt = median(diff(t));
tol = max(0.03, 0.02 * S1);
fallback = ~(isstruct(opts) && isfield(opts, 'rockerFallback') && ~opts.rockerFallback);
sortedR = issorted(tR);
if sortedR, nRock = [0; cumsum(double(rock))]; end   %binary search + cumulative sum: O(log N) per call, 2026-10-10
inData = @(a, b) t(1) <= a && t(end) >= b;
tg = (round(-0.05 / dt):round((S1 - 0.1) / dt))' * dt;
nTg = numel(tg);
w = max(1, round(0.03 / dt));
R.nS2 = numel(jS2);
if isempty(jS2), notes = {'no S2 stimuli'}; return; end
isSS = strcmp(role, 'S1') & inR & abs(prevI - S1) < tol & abs(ni - S1) < tol;
vS2 = val(jS2);
% protocol variant (2026-10-23): S1 train + S2 pairs (steady-state S1 stimuli with the S1 interval before and after:
% the template of the S2 response) or S1-S2 pairs without such a train (e.g. a pair in every period)
if nnz(isSS) >= 3, R.variant = {'S1 train + S2 pairs'}; else, R.variant = {'S1-S2 pairs without S1 train'}; end
if ~isempty(vS2) && any(~isnan(vS2))
    R.variant = {sprintf('%s, S2 %g-%g ms (%d steps)', R.variant{1}, round(2000 * max(vS2)) / 2, ...
        round(2000 * min(vS2)) / 2, numel(unique(vS2(~isnan(vS2)))))};
end

% template: mean steady-state S1 contraction (rocker at rest with 'stopped'); fewer than 3: the S1 of the pairs with
% the longest S2 interval (2026-10-23); with 'stopped' and fewer than 3 such pairs at rest: all pairs (option
% rockerFallback, note), the S2 are then evaluated with the rocker moving, too
cutT = inf;                                          %end of the template (pairs template: 20 ms before their S2)
nT = 0; pairsNote = ''; relaxNote = '';
for pass = 1:2
    if sortedR
        atRest = @(a, b) ~stopped || restSorted(tR, nRock, a, b);
    else
        atRest = @(a, b) ~stopped || (any(tR >= a & tR <= b) && ~any(rock(tR >= a & tR <= b)));
    end
    jSS = find(isSS);
    keep = false(size(jSS));
    for k = 1:numel(jSS)
        keep(k) = inData(st(jSS(k)) - 0.05, st(jSS(k)) + S1 - 0.1) && atRest(st(jSS(k)), st(jSS(k)) + S1 - 0.1);
    end
    jSS = jSS(keep);
    Y = nan(nTg, numel(jSS));
    for k = 1:numel(jSS), Y(:,k) = getTrace(st(jSS(k)), tg); end
    Y = Y(:, all(~isnan(Y), 1));
    nT = size(Y, 2);
    cutT = inf; pairsNote = ''; relaxNote = '';
    if nT < 3
        % S1-S2 pairs in every period (no steady-state S1 beats): template from the S1 of the pairs with the
        % longest S2 interval, cut 20 ms before the S2 and held at the mean of the 50 ms before the cut
        jL = jS2(vS2 == max(vS2) & jS2 > 1);
        cL = st(jL) - st(jL - 1);
        keep = false(size(jL));
        for k = 1:numel(jL)
            keep(k) = inData(st(jL(k) - 1) - 0.05, st(jL(k)) - 0.02) && atRest(st(jL(k) - 1), st(jL(k)) - 0.02);
        end
        jL = jL(keep); cL = cL(keep);
        if numel(jL) >= 3
            cutT = min(cL) - 0.02;
            Y = nan(nTg, numel(jL));
            for k = 1:numel(jL)
                y = getTrace(st(jL(k) - 1), tg);
                y(tg > cutT) = mean(y(tg > cutT - 0.05 & tg <= cutT));
                Y(:,k) = y;
            end
            Y = Y(:, all(~isnan(Y), 1));
            nT = size(Y, 2);
            if nT >= 3
                mT = mean(Y, 2);
                tail = mean(mT(tg > cutT - 0.05 & tg <= cutT)) / max(mT);
                lab = round(2000 * max(vS2)) / 2;
                if tail > 0.1
                    relaxNote = sprintf(['template: S1 of the %d pairs at %g ms not relaxed before the S2 (%d %% of ' ...
                        'the peak), no steady-state S1 beats - no estimates'], nT, lab, round(100 * tail));
                else
                    pairsNote = sprintf('template: S1 of the %d pairs at %g ms (no steady-state S1 beats)', nT, lab);
                end
            end
        end
    end
    if nT >= 3 || ~stopped || ~fallback, break; end
    stopped = false;                                 %second pass: all pairs, S2 with the rocker moving, too
    notes{end+1} = 'no S1-S2 pairs with the rocker at rest: all pairs used'; %#ok<AGROW>
end
R.nTemplateBeats = nT;
if ~isempty(relaxNote), notes{end+1} = relaxNote; return; end
if ~isempty(pairsNote), notes{end+1} = pairsNote; end
if nT < 3, notes{end+1} = sprintf('only %d steady-state S1 beats with the rocker at rest (>= 3 needed)', nT); return; end
m = mean(Y, 2);
[A1, iPk] = max(m);
tPk = tg(iPk);                                       %peak time of the S1 template
R.amplitudeS1_uN = A1;
if A1 <= 1e-6, notes = {'no S1 contraction'}; return; end   %flat signal: A1 ~ +-1e-12 (rounding), 2026-10-08

n = numel(jS2);
CI = nan(n, 1); resp = nan(n, 1); prom = nan(n, 1);
for q = 1:n
    j = jS2(q);
    if j < 2, continue; end
    s1 = st(j-1);
    c = st(j) - s1;
    CI(q) = c;
    nx = ni(j); if isnan(nx), nx = inf; end
    winPeak = min(c + 0.6, c + nx + 0.02);
    winResp = min(winPeak, S1 - 0.1);
    if ~inData(s1 - 0.05, s1 + max(winPeak, S1 - 0.1)) || ~atRest(s1, s1 + winPeak), continue; end
    gy = (round(-0.05 / dt):round(max(winPeak, S1 - 0.1) / dt))' * dt;
    [rq, aq, pq] = s2response(getTrace(s1, gy), m, c, winResp, gy, winPeak);
    if aq < 0.2 || isnan(rq), continue; end             %no S1 contraction
    resp(q) = 100 * rq / (aq * A1);
    prom(q) = 100 * pq / (aq * A1);
end

% noise level: pseudo-S2 on the template beats (leave-one-out template) at every tested interval
uCI = unique(round(CI(~isnan(resp)) * 1000) / 1000);
nullV = nan(nT, numel(uCI));
sumY = sum(Y, 2);
for k = 1:nT
    mk = (sumY - Y(:,k)) / (nT - 1);
    for i = 1:numel(uCI)
        wr = min([uCI(i) + 0.6, S1 - 0.1, cutT]);   %pairs template: the window ends >= 100 ms before the cut
        if wr - uCI(i) < 0.1, continue; end
        [rk, ak] = s2response(Y(:,k), mk, uCI(i), wr, [], []);
        if ak >= 0.2 && ~isnan(rk), nullV(k,i) = 100 * rk / (ak * max(mk)); end
    end
end
noise = mprctile(nullV(:), 99);
R.S2noiseLevel_pct = noise;
sep = prom >= max(noise, 2) & resp >= noise;

% transitions from long to short S2 intervals (groups of mda_groupBeats)
v = ~isnan(resp);
g = val(jS2); g = g(v);
ciU = flipud(unique(g));
fracSep = nan(size(ciU)); medResp = nan(size(ciU));
sv = sep(v); rv = resp(v);
for i = 1:numel(ciU)
    fracSep(i) = mean(sv(g == ciU(i)));
    medResp(i) = median(rv(g == ciU(i)));
end
ciU = round(2000 * ciU) / 2;                              %0.5-ms steps (2.5-ms grid of the status channel), 2026-10-21
G2 = table(ciU(:), medResp(:), 100 * fracSep(:), 'VariableNames', {'groupValue_ms', 'S2response_pct', 'separatePeak_percent'});
if ~isempty(ciU), R.S2shortest_ms = ciU(end); R.S2longest_ms = ciU(1); end
[R.refPeriodNoPeak_ms, R.refPeriodNoPeakStep_ms, notes] = transition(ciU, 100 * fracSep, 50, 'no peak', notes);
[R.refPeriodNoResponse_ms, R.refPeriodNoResponseStep_ms, notes] = transition(ciU, medResp, noise, 'no response', notes);
% as GetRefractoryPeriod (MyoDish exports, 2026-10-10): the interval before the first one (from long to short) at which
% not every S2 had a separate peak
kA = find(fracSep < 1, 1);
if isempty(kA)
    if ~isempty(ciU), R.refPeriodAllCaptured_ms = ciU(end); notes{end+1} = 'all captured: every S2 with a separate peak'; end
elseif kA > 1
    R.refPeriodAllCaptured_ms = ciU(kA-1);
else
    notes{end+1} = 'all captured: not every S2 with a separate peak already at the longest interval';
end
if ~isnan(noise) && noise >= 50
    R.refPeriodNoPeak_ms = nan; R.refPeriodNoPeakStep_ms = nan;
    R.refPeriodNoResponse_ms = nan; R.refPeriodNoResponseStep_ms = nan; R.refPeriodAllCaptured_ms = nan;
    notes = {sprintf('noise level %d %%: no reliable stimulus-locked S1 contraction - no estimates', round(noise))};
end

    function y = getTrace(s, grid)
        x = s + grid;
        y = interp1(t, f, x, 'linear', nan);
        y = y - mean(y(grid < 0));
    end

    function [rmax, aq, pmax] = s2response(y, mt, c, winResp, gy, winPeak)
        % residual maximum (S2 response), scale of the S1 contraction and the largest prominence of a local maximum
        % of the S1+S2 trace y (grid gy, starting like tg) S2 + 25 ms ... winPeak
        yt = y(1:nTg);
        pre = tg >= 0 & tg <= c + 0.02;
        aq = (yt(pre)' * mt(pre)) / (mt(pre)' * mt(pre));
        r = movmean(yt - aq * mt, w);
        Kw = find(tg >= c + 0.03 & tg <= winResp);
        rmax = nan; pmax = 0;
        if ~isempty(Kw), rmax = max(r(Kw)); end
        if ~isempty(gy)
            % not before the S1 peak of the template: an S2 shortly after the S1 (interval < time to peak) would
            % show the S1 peak itself as a separate peak (2026-10-23)
            Kq = find(gy >= max(c + 0.025, tPk + 0.01) & gy <= winPeak);
            if numel(Kq) >= 3
                [isMax, P] = islocalmax(movmean(y(Kq), w));
                if any(isMax), pmax = max(P(isMax)); end
            end
        end
    end
end


function ok = restSorted(tR, nRock, a, b)
% samples of the sorted time base tR in [a, b] exist and the rocker is at rest in all of them (nRock = [0; cumsum of
% the rocker state]); binary search instead of a mask over all samples (same result as any(tR >= a & tR <= b) &&
% ~any(rock(tR >= a & tR <= b))). TS 2026-10-10
N = numel(tR);
lo = 1; hi = N + 1;                 %first index with tR >= a
while lo < hi
    mid = floor((lo + hi) / 2);
    if tR(mid) < a, lo = mid + 1; else, hi = mid; end
end
i0 = lo;
lo = 1; hi = N + 1;                 %first index with tR > b
while lo < hi
    mid = floor((lo + hi) / 2);
    if tR(mid) <= b, lo = mid + 1; else, hi = mid; end
end
i1 = lo - 1;                        %last index with tR <= b
ok = i1 >= i0 && nRock(i1 + 1) - nRock(i0) == 0;
end
