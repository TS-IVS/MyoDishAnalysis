function out = mda_referenceBeat(action, varargin)
%MDA_REFERENCEBEAT  Reference beat (mean shape +- SD of selected contractions) and the comparison of contractions with it.
%
%   R = mda_referenceBeat('create', C, B, rows)         reference from the contractions B(rows,:) (at least 3)
%   R = mda_referenceBeat('create', C, B, rows, align)  align: 'stimulus' (default) or 'upstroke'
%   R = mda_referenceBeat('align', R, align)            switch the alignment of a reference (both variants are stored;
%                                                        '' = keep, only standardize the fields of older references)
%   V = mda_referenceBeat('compare', C, B, R)           table, one row per contraction (rows of B): refCorrelation,
%                                                        refRMSDeviation_SD, refRMSDeviationNorm_SD, refMaxDeviation_SD,
%                                                        refMaxDeviationNorm_SD (NaN if not comparable)
%   Y = mda_referenceBeat('traces', C, B, R, rows)      developed force of the contractions B(rows,:) on R.tGrid, aligned
%                                                        as R (one column per contraction, NaN where not comparable)
%   V = mda_referenceBeat('relative', B, R)             table, one row per contraction: every parameter relative to the
%                                                        reference (see RELATIVE PARAMETERS; NaN without R)
%
%   C, B   channel info and contraction table of mda_analyzeChannel (filtered signal C.t, C.f; B.t_peak, B.t_stim,
%          B.diastolicSignal, B.amplitude)
%
% ALIGNMENT (every contraction as developed force: signal - F_dia)
%   'stimulus' (default)  t = 0 at the stimulus of the contraction: a changed stimulus-to-contraction latency counts as
%                         a deviation. The reference is built from the stimulated contractions of the selection.
%                         Contractions without a stimulus (unpaced, extra) are aligned at their 50 % upstroke, placed at
%                         the 50 % upstroke of the reference (R.t50 = median latency stimulus -> 50 % upstroke).
%   'upstroke'            t = 0 at the 50 % upstroke (last crossing of F_dia + 50 % of the amplitude before the peak):
%                         shape only, independent of the latency. Used automatically if the selection contains fewer
%                         than 3 stimulated contractions (e.g. unpaced recordings).
%   Both variants are stored in R.variants; R.align and the top-level fields are the active one. The reference covers
%   0.15 s before the 50 % upstroke (stimulus: from 0.05 s before the stimulus) until 90 % relaxation of the mean
%   + 0.15 s (at most 2.5 s after the 50 % upstroke), where at least half of the contractions are available. A
%   contraction is compared only after the peak of the previous and before the upstroke of the next contraction.
%   R: align, tGrid (s), mean, sd (uN), meanNorm, sdNorm (every contraction divided by its own amplitude), nPerPoint,
%   t50, tOnset (10 % upstroke of the mean), tPeak, amp (amplitude of the mean), n, channel, source, created, params
%   (see RELATIVE PARAMETERS), variants.
%
% COMPARISON (parameters of mda_analyzeChannel, NaN without reference)
%   z = (F - mean) / SD at every time point of the reference; SD at least the median SD of the reference and 2 % of
%   its amplitude (normalized: 0.02).
%   refCorrelation          Pearson correlation with the mean reference shape (1 = same shape). Independent of
%                           amplitude and baseline, therefore without a normalized variant.
%   refRMSDeviation_SD      root mean square of z over the compared window: overall deviation in SD
%   refMaxDeviation_SD      maximum |z| (moving mean over 30 ms): local deviations (shoulder, partial response, delay)
%   ...Norm_SD              the same with contraction and reference normalized to amplitude 1 (shape only)
%   A contraction deviates by more than x SD if refMaxDeviation_SD (or ...Norm_SD) > x (GUI: x = 3 by default). At
%   least half of the reference window (and 10 samples) must be comparable, otherwise NaN.
%
% RELATIVE PARAMETERS (2026-10-06)
%   R.params: mean, SD and n of every parameter (mda_parameters, without the ref... parameters) over the reference
%   contractions. Every contraction gets <parameter>_pctRef = 100 * value / reference mean (% of the reference), for
%   diastolicForce and diastolicSignal <parameter>_dRef = value - reference mean (uN; their zero point is arbitrary or
%   close to the values). NaN without reference or for references created before 2026-10-06 (no R.params).
%
% TS 2026-10-05 (relative parameters 2026-10-06)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

switch lower(action)
    case 'create'
        align = 'stimulus';
        if numel(varargin) >= 4 && ~isempty(varargin{4}), align = checkAlign(varargin{4}); end
        out = createRef(varargin{1}, varargin{2}, varargin{3}, align);
    case 'align'
        align = varargin{2};
        if ~isempty(align), align = checkAlign(align); end
        out = setAlign(varargin{1}, align);
    case 'compare'
        out = compareRef(varargin{1}, varargin{2}, setAlign(varargin{3}, ''));
    case 'relative'
        out = relativeTable(varargin{1}, varargin{2});
    case 'traces'
        [C, B, R, rows] = varargin{1:4};
        R = setAlign(R, '');
        info = beatInfo(C, B);
        a = anchors(B, info, R);
        out = nan(numel(R.tGrid), numel(rows));
        for q = 1:numel(rows)
            if isnan(a(rows(q))), continue; end
            [y, valid] = beatTrace(B, info, rows(q), a(rows(q)), R.tGrid);
            y(~valid) = nan;
            out(:,q) = y;
        end
    otherwise
        error('mda_referenceBeat: action ''create'', ''align'', ''compare'', ''relative'' or ''traces'' expected.');
end
end


% =====================================================================================================
function R = createRef(C, B, rows, align)
if islogical(rows), rows = find(rows); end
rows = rows(:)';
rows = rows(~isnan(B.amplitude(rows)) & B.amplitude(rows) > 0);
info = beatInfo(C, B);
rows = rows(~isnan(info.t50(rows)));
if numel(rows) < 3
    error('mda_referenceBeat: at least 3 contractions with an amplitude are needed for a reference (selected: %d).', numel(rows));
end
dt = median(diff(C.t));
V.upstroke = variant(B, info, rows, info.t50(rows), 0, -0.15, 2.5, dt, 'upstroke');
V.stimulus = [];
st = rows(~isnan(B.t_stim(rows)));
if numel(st) >= 3
    lat = median(info.t50(st) - B.t_stim(st));     %stimulus -> 50 % upstroke
    V.stimulus = variant(B, info, st, B.t_stim(st), lat, min(-0.05, lat - 0.15), lat + 2.5, dt, 'stimulus');
end
if isempty(V.stimulus), align = 'upstroke'; end
R.variants = V;
R.channel = C.channel;
R.source = sprintf('%d contractions (%d stimulated), %.1f-%.1f s', numel(rows), numel(st), min(B.t_peak(rows)), max(B.t_peak(rows)));
R.created = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'));
R.params = paramStats(B, rows);
R.align = align;
R = setAlign(R, align);
end


function P = paramStats(B, rows)
% mean, SD and n of every parameter over the reference contractions
[base, ~, ~] = relativeNames();
P = struct('names', {base}, 'mean', nan(1, numel(base)), 'sd', nan(1, numel(base)), 'n', zeros(1, numel(base)));
for k = 1:numel(base)
    if ~ismember(base{k}, B.Properties.VariableNames), continue; end
    v = B.(base{k})(rows);
    P.mean(k) = mean(v, 'omitnan'); P.sd(k) = std(v, 'omitnan'); P.n(k) = sum(~isnan(v));
end
end


function [base, rel, isDiff] = relativeNames()
% parameters (without ref...) and the names of their relative columns
PI = mda_parameters();
base = PI(~startsWith(PI(:,1), 'ref'), 1)';
isDiff = ismember(base, {'diastolicForce', 'diastolicSignal'});
rel = strcat(base, '_pctRef');
rel(isDiff) = strcat(base(isDiff), '_dRef');
end


function V = relativeTable(B, R)
% every parameter relative to the reference (NaN without reference / parameter values)
[base, rel, isDiff] = relativeNames();
M = nan(height(B), numel(base));
if ~isempty(R) && isfield(R, 'params') && ~isempty(R.params) && isfield(R.params, 'names')
    for k = 1:numel(base)
        j = find(strcmp(R.params.names, base{k}), 1);
        if isempty(j) || ~ismember(base{k}, B.Properties.VariableNames), continue; end
        r = R.params.mean(j);
        if isDiff(k)
            M(:,k) = B.(base{k}) - r;
        elseif ~isnan(r) && r ~= 0
            M(:,k) = 100 * B.(base{k}) / r;
        end
    end
end
V = array2table(M, 'VariableNames', rel);
u = repmat({'%'}, 1, numel(rel)); u(isDiff) = {'uN'};
V.Properties.VariableUnits = u;
end


function W = variant(B, info, rows, anchor, t50, g0, g1, dt, align)
% mean +- SD of the contractions rows (time 0 = anchor) on a grid g0 ... g1
tGrid = (round(g0 / dt):round(g1 / dt))' * dt;
Y = nan(numel(tGrid), numel(rows)); YN = Y;
for q = 1:numel(rows)
    [y, valid] = beatTrace(B, info, rows(q), anchor(q), tGrid);
    y(~valid) = nan;
    Y(:,q) = y; YN(:,q) = y / B.amplitude(rows(q));
end
nValid = sum(~isnan(Y), 2);
m = mean(Y, 2, 'omitnan');
mN = mean(YN, 2, 'omitnan');
% window: where at least half of the contractions are available, until 90 % relaxation of the mean + 0.15 s
ok = nValid >= max(2, 0.5 * numel(rows));
[amp, ip] = max(m .* ok);
iEnd = find((1:numel(m))' > ip & m < 0.1 * amp, 1);
if isempty(iEnd), iEnd = numel(m); end
iEnd = min(numel(m), iEnd + round(0.15 / dt));
bad = find(~ok(1:iEnd) & (1:iEnd)' > ip, 1);
if ~isempty(bad), iEnd = bad - 1; end
bad = find(~ok(1:ip), 1, 'last');
if isempty(bad), iBeg = 1; else, iBeg = bad + 1; end
J = (iBeg:iEnd)';
W.align = align;
W.tGrid = tGrid(J);
W.mean = m(J);
W.sd = std(Y(J,:), 0, 2, 'omitnan');
W.meanNorm = mN(J);
W.sdNorm = std(YN(J,:), 0, 2, 'omitnan');
W.nPerPoint = nValid(J);
W.t50 = t50;
i10 = find(m(iBeg:ip) < 0.1 * amp, 1, 'last');
if isempty(i10), W.tOnset = tGrid(iBeg); else, W.tOnset = tGrid(iBeg + i10 - 1); end
W.tPeak = tGrid(ip);
W.amp = amp;
W.n = numel(rows);
end


function R = setAlign(R, align)
% activate a variant ('' = keep R.align); also converts references of the first version (aligned at the upstroke)
F = {'align', 'tGrid', 'mean', 'sd', 'meanNorm', 'sdNorm', 'nPerPoint', 't50', 'tOnset', 'tPeak', 'amp', 'n'};
if isempty(R), return; end
if ~isfield(R, 'variants')
    W = struct();
    for f = F
        if isfield(R, f{1}), W.(f{1}) = R.(f{1}); else, W.(f{1}) = []; end
    end
    W.align = 'upstroke'; W.t50 = 0;
    if isempty(W.nPerPoint), W.nPerPoint = nan(size(W.tGrid)); end
    R.variants = struct('upstroke', W, 'stimulus', []);
    R.align = 'upstroke';
end
if isempty(align), align = R.align; end
if strcmp(align, 'stimulus') && isempty(R.variants.stimulus)
    error('mda_referenceBeat:noStimulus', ['mda_referenceBeat: this reference has no stimulus-aligned variant ' ...
        '(fewer than 3 stimulated contractions); use the alignment ''upstroke''.']);
end
W = R.variants.(align);
out = struct();
for f = F, out.(f{1}) = W.(f{1}); end
out.channel = R.channel;
out.source = R.source;
out.created = R.created;
if isfield(R, 'params'), out.params = R.params; else, out.params = []; end   %[]: reference before 2026-10-06
out.variants = struct('upstroke', R.variants.upstroke, 'stimulus', R.variants.stimulus);
R = out;                                   %fixed field order: references can be combined in a struct array
end


function a = checkAlign(a)
a = validatestring(a, {'stimulus', 'upstroke'}, 'mda_referenceBeat', 'alignment');
end


function V = compareRef(C, B, R)
names = {'refCorrelation', 'refRMSDeviation_SD', 'refRMSDeviationNorm_SD', 'refMaxDeviation_SD', 'refMaxDeviationNorm_SD'};
n = height(B);
M = nan(n, numel(names));
if ~isempty(R) && n > 0
    info = beatInfo(C, B);
    a = anchors(B, info, R);
    dt = median(diff(R.tGrid));
    w = max(1, round(0.03 / dt));                        %moving mean of the deviation over 30 ms (maximum)
    sdA = max(R.sd, max(median(R.sd, 'omitnan'), 0.02 * R.amp));
    sdN = max(R.sdNorm, max(median(R.sdNorm, 'omitnan'), 0.02));
    for k = 1:n
        A = B.amplitude(k);
        if isnan(A) || A <= 0 || isnan(a(k)), continue; end
        [y, valid] = beatTrace(B, info, k, a(k), R.tGrid);
        valid = valid & ~isnan(R.mean) & ~isnan(R.sd);
        if sum(valid) < 0.5 * numel(R.tGrid) || sum(valid) < 10, continue; end
        yv = y(valid); mv = R.mean(valid);
        if std(yv) > 0 && std(mv) > 0
            cc = corrcoef(yv, mv); M(k,1) = cc(1,2);
        end
        z = (y - R.mean) ./ sdA;  z(~valid) = nan;
        zN = (y / A - R.meanNorm) ./ sdN;  zN(~valid) = nan;
        M(k,2) = sqrt(mean(z(valid).^2));
        M(k,3) = sqrt(mean(zN(valid).^2));
        M(k,4) = max(abs(movmean(z, w, 'omitnan')), [], 'omitnan');
        M(k,5) = max(abs(movmean(zN, w, 'omitnan')), [], 'omitnan');
    end
end
V = array2table(M, 'VariableNames', names);
end


function a = anchors(B, info, R)
% time 0 of every contraction on R.tGrid (NaN: no 50 % upstroke found)
a = info.t50 - R.t50;                     %50 % upstroke at the 50 % upstroke of the reference
if strcmp(R.align, 'stimulus')
    s = ~isnan(B.t_stim) & ~isnan(info.t50);
    a(s) = B.t_stim(s);
end
end


function info = beatInfo(C, B)
% 50 % upstroke time of every contraction; peak times of the neighbouring contractions
n = height(B);
info.t50 = nan(n, 1);
[~, loc] = ismember(B.t_peak, C.peakTimes);
t = C.t(:); f = C.f(:);
for k = 1:n
    if loc(k) == 0 || isnan(B.amplitude(k)), continue; end
    i = C.iPeaks(loc(k));
    lev = B.diastolicSignal(k) + 0.5 * B.amplitude(k);
    lo = max(1, i - round(3 / median(diff(t))));
    j = find(f(lo:i-1) < lev, 1, 'last') + lo - 1;
    if isempty(j) || f(j+1) == f(j), continue; end
    info.t50(k) = t(j) + (lev - f(j)) / (f(j+1) - f(j)) * (t(j+1) - t(j));
end
% all detected peaks (also outside B) as neighbours
pk = sort(C.peakTimes(:));
info.prevPeak = nan(n, 1); info.nextPeak = nan(n, 1);
[~, pos] = ismember(B.t_peak, pk);
for k = find(pos(:)' > 0)
    if pos(k) > 1, info.prevPeak(k) = pk(pos(k) - 1); end
    if pos(k) < numel(pk), info.nextPeak(k) = pk(pos(k) + 1); end
end
% time from the 50 % upstroke to the peak (median): the next contraction starts about this much before its peak
dUp = B.t_peak - info.t50;
info.riseHalf = median(dUp(~isnan(dUp)));
if isempty(info.riseHalf) || isnan(info.riseHalf), info.riseHalf = 0.1; end
info.t = t; info.f = f;
info.t0 = t(1); info.dt = (t(end) - t(1)) / max(1, numel(t) - 1);   %uniform sampling (mda_readMdd)
end


function [y, valid] = beatTrace(B, info, k, anchor, tGrid)
% developed force of contraction k on tGrid (relative to its anchor time)
tq = anchor + tGrid;
x = (tq - info.t0) / info.dt + 1;                    %linear interpolation on the uniform time grid
i0 = floor(x); fr = x - i0;
inside = i0 >= 1 & i0 < numel(info.f);
y = nan(size(tq));
y(inside) = info.f(i0(inside)) .* (1 - fr(inside)) + info.f(i0(inside) + 1) .* fr(inside) - B.diastolicSignal(k);
valid = inside;
if ~isnan(info.nextPeak(k))           %before the upstroke of the next contraction (10 % ~ 2 x (50 % -> peak) before it)
    valid = valid & tq < info.nextPeak(k) - 2 * info.riseHalf;
end
if ~isnan(info.prevPeak(k))
    valid = valid & tq > info.prevPeak(k);
end
end
