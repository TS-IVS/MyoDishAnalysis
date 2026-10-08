function EP = mda_readEPRecording(epFile, H, opts, varargin)
%MDA_READEPRECORDING  Read an EP recording (LabChart .mat export) and align it to a MyoDish .mdd file.
%
%   EP = mda_readEPRecording(epFile, H)              H = mda_readMdd(mddFile) (file facts) or the .mdd file name
%   EP = mda_readEPRecording(epFile, H, opts)        opts from mda_options (used to read the .mdd stimuli)
%   EP = mda_readEPRecording(epFile, H, opts, 'name', value, ...)
%
% EP recording: any LabChart recording with a signal channel (e.g. membrane potential of a sharp electrode, field
% potential, current) and a channel that records the stimulus pulses, made in parallel with the MyoDish recording.
% The recording is placed on the time axis of the .mdd file (file time, s) by matching the stimulus pulses of the
% LabChart stimulation channel with the stimulus pulses in the status channel of the .mdd file:
%   t_mdd = t0 + slope * t_LabChart   (t_LabChart = 0 at the first sample of the block)
% (importSharpElectrodeData does this with alignStimTimes_new, constant offset; with near-constant pacing that can
% pick a shift by several stimulus intervals, see the project notes of 2026-10-06.)
%
% ALIGNMENT
%   1. LabChart stimuli: |signal - median| > threshold (onset of each pulse; pulses closer than 10 ms are one pulse).
%   2. All time differences mdd stimulus - LabChart stimulus are counted in bins of 'tolerance'; the most frequent
%      differences are the candidate offsets. Each candidate is refined (median of the matched differences) and scored
%      by the number of matched stimuli (|difference| <= tolerance).
%   3. With (nearly) constant pacing, shifts by one or more stimulus intervals match almost as many stimuli. Among the
%      candidates that match at most max(2, 5 %) fewer stimuli than the best one, the choice is made by
%        a) the stimulus current: the LabChart pulse amplitude must be the same for the same current (R^2 of
%           amplitude ~ current level; used when the current changes, e.g. stimulus threshold protocols),
%        b) the clock times (LabChart block time vs. recording start in the .mdd log file), if they point clearly
%           to one candidate,
%        c) else the most matches (flagged: CHECK the alignment).
%   The alignment is also flagged if < 80 % of the LabChart stimuli within the .mdd recording match or if the clock
%   times differ by more than 60 s (wrong file?).
%   4. Clock drift: slope from a straight line through the matched stimuli (if >= 10 stimuli over >= 30 s and
%      |slope - 1| < 0.002).
%   Without matching stimuli the clock times are used (message), without clock times offset 0.
%
% OPTIONS (name/value, not case sensitive)
%   'signalChannel'  LabChart channel of the signal: number or part of the title (default: title with 'potential',
%                    'membran', 'Vm' or 'voltage', else channel 1). 'vmChannel' is the same.
%   'stimChannel'    LabChart stimulation channel: number or part of the title (default: title with 'stim', else the
%                    last channel)
%   'block'          LabChart block (default: the block that overlaps the .mdd recording by the clock times, else 1)
%   'mddChannel'     MyoDish channel whose stimuli are matched. Default: every channel with stimuli is tried and the
%                    one with the most matches is used; this channel is preferred on ties. 0 = the external trigger
%                    pulses of the .mdd file (external stimulator; tried like a channel)
%   'stimThreshold'  'auto' (default: max(20 x noise SD, 5 % of the largest pulse), after subtraction of the median)
%                    or a number (units of the stimulation channel)
%   'timeOffset'     t0 or [t0 slope]: no matching, t_mdd = t0 + slope * t_LabChart (slope default 1; the clocks of
%                    LabChart and MyoDish differ by ~ -90 ppm in the 2026-09 recordings: slope 0.99991)
%   'tolerance'      maximum time difference of matched stimuli (s; default 0.01)
%   'fitDrift'       true (default) | false
%
% OUTPUT (EP)
%   file, titles, signalChannel, stimChannel, block, nBlocks, fs (LabChart sampling rate, Hz), duration (s)
%   t0       .mdd file time of the first LabChart sample (s);   dt   .mdd time per LabChart sample (s, = slope / fs)
%   V        signal (single, unitV; V and uV are converted to mV), labelV (axis label: channel title, 'V_m' for
%            membrane potential);   stim   stimulation channel (single, unitStim), labelStim
%   stimTimes, stimEnds, stimAmplitude   LabChart stimuli: onset and end (.mdd time, s; biphasic pulse = one
%            pulse), pulse amplitude (unitStim)
%   comments table(time, text) of the LabChart comments of the block (.mdd time)
%   align    struct: offset, slope, method, nMatched, nSE, nMdd, mddChannel, rms (s), clockOffset (s, NaN if unknown),
%            ambiguous, check (cell: reasons to check the alignment - ambiguous, few matches, clock times > 60 s apart),
%            pairs ([LabChart time, .mdd time] of the matched stimuli),
%            candidates ([offset (s), matched stimuli, R2 amplitude ~ current, drift (ppm)], best first)
%   info     cell of text lines (GUI),   message   one line
%
% TS 2026-10-06 (after importSharpElectrodeData and alignStimTimes_new)

if nargin < 3 || isempty(opts), opts = mda_options(); end
P = struct('signalChannel', [], 'stimChannel', [], 'block', [], 'mddChannel', [], 'stimThreshold', 'auto', ...
    'timeOffset', [], 'tolerance', 0.01, 'fitDrift', true);
fn = fieldnames(P);
for k = 1:2:numel(varargin)
    if strcmpi(varargin{k}, 'vmChannel'), varargin{k} = 'signalChannel'; end
    j = find(strcmpi(fn, varargin{k}), 1);
    if isempty(j), error('mda_readEPRecording: unknown option ''%s''.', varargin{k}); end
    P.(fn{j}) = varargin{k+1};
end
if ischar(H) || isstring(H), H = mda_readMdd(char(H), [], [], opts); end
epFile = char(epFile);
[~, nm, ext] = fileparts(epFile);

% ---------------------------------------------------------------- LabChart file
if ~strcmpi(ext, '.mat'), error('%s: a LabChart export (.mat) is expected.', [nm ext]); end
L = load(epFile);
need = {'data', 'datastart', 'dataend', 'titles', 'samplerate'};
if ~all(isfield(L, need))
    error('%s is not a LabChart .mat export (variables data, datastart, dataend, titles, samplerate).', [nm ext]);
end
titles = strtrim(cellstr(L.titles));
nCh = size(L.datastart, 1); nBl = size(L.datastart, 2);
vm = pickChannel(P.signalChannel, titles, {'potential', 'membran', 'vm', 'voltage'}, 1);
sc = pickChannel(P.stimChannel, titles, {'stim'}, nCh);
if sc == vm && nCh > 1, error('Signal and stimulation are the same LabChart channel (%d).', vm); end
blockTimes = NaN(1, nBl);
if isfield(L, 'blocktimes'), blockTimes(1:numel(L.blocktimes)) = L.blocktimes(:)'; end
has = L.datastart(vm, :) > 0 & L.dataend(vm, :) >= L.datastart(vm, :);
if ~any(has), error('%s: no data in channel %d (%s).', [nm ext], vm, titles{vm}); end

clockStart = (blockTimes - H.recordingStart) * 86400;        %s, .mdd time of the block start by the clocks
dur = (L.dataend(vm, :) - L.datastart(vm, :) + 1) ./ L.samplerate(vm, :);
if isempty(P.block)
    ov = min(clockStart + dur, H.totalSeconds) - max(clockStart, 0);
    ov(~has | isnan(ov)) = -Inf;
    [mx, b] = max(ov);
    if ~(mx > 0), b = find(has, 1); end
else
    b = P.block;
    if b < 1 || b > nBl || ~has(b), error('%s: block %d has no data.', [nm ext], b); end
end
fs = L.samplerate(vm, b);
V = L.data(L.datastart(vm, b):L.dataend(vm, b));
[V, unitV] = toMilli(V, unitOf(L, vm, b));
if L.datastart(sc, b) > 0 && L.samplerate(sc, b) == fs
    X = L.data(L.datastart(sc, b):L.dataend(sc, b));
    unitStim = unitOf(L, sc, b);
else
    X = zeros(0, 1, 'single'); unitStim = '';
end
V = single(V(:)); X = single(X(:));
prior = clockStart(b);
if isfield(L, 'firstsampleoffset') && isfield(L, 'tickrate') && L.tickrate(b) > 0
    prior = prior + L.firstsampleoffset(vm, b) / L.tickrate(b);
end

% ---------------------------------------------------------------- stimuli
[tA, ampA, tEndA] = detectStim(X, fs, P.stimThreshold);
A = struct('offset', 0, 'slope', 1, 'method', '', 'nMatched', 0, 'nSE', numel(tA), 'nMdd', 0, 'mddChannel', NaN, ...
    'rms', NaN, 'clockOffset', NaN, 'ambiguous', false, 'pairs', zeros(0, 2), 'candidates', zeros(0, 4));
if ~isempty(P.timeOffset)
    A.offset = P.timeOffset(1); A.method = 'fixed offset (option timeOffset)';
    if numel(P.timeOffset) > 1, A.slope = P.timeOffset(2); end
    st = mddStimuli(H, opts, [max(0, A.offset - 10), min(H.totalSeconds, A.offset + dur(b) + 10)]);
    k = true(size(st.time));
    if ~isempty(P.mddChannel) && any(st.channel == P.mddChannel), k = st.channel == P.mddChannel; A.mddChannel = P.mddChannel; end
    tB = unique(st.time(k));
    A.nMdd = numel(tB);
    if ~isempty(tB) && ~isempty(tA)                              %stimuli that match at this offset (information)
        [ia, ~, d] = matchAt(tA(:), tB(:), [-Inf; (tB(1:end-1) + tB(2:end)) / 2; Inf], A.offset, A.slope, P.tolerance);
        A.nMatched = numel(ia); A.rms = sqrt(mean(d .^ 2));
    end
else
    rg = [0 H.totalSeconds];                                     %.mdd time range searched for stimuli
    if isfinite(prior), rg = [max(0, prior - 1800), min(H.totalSeconds, prior + dur(b) + 1800)]; end
    st = mddStimuli(H, opts, rg);
    A = matchChannels(A, tA, ampA, st, prior, P);
    if A.nMatched < minMatches(numel(tA), A.nMdd) && isfinite(prior) && any(rg ~= [0 H.totalSeconds])
        st = mddStimuli(H, opts, [0 H.totalSeconds]);                  %clock times wrong? whole file
        A = matchChannels(A, tA, ampA, st, prior, P);
    end
    if A.nMatched < minMatches(numel(tA), A.nMdd)
        A.ambiguous = true;
        if isfinite(prior)
            A.offset = prior; A.slope = 1;
            A.method = sprintf('clock times (only %d of %d stimuli matched)', A.nMatched, numel(tA));
        else
            A.offset = 0; A.slope = 1;
            A.method = sprintf('NOT ALIGNED: offset 0 (%d of %d stimuli matched, no clock times)', A.nMatched, numel(tA));
        end
    end
end
if isfinite(prior), A.clockOffset = prior - A.offset; end
A.check = {};                                                    %reasons to check the alignment
if isempty(P.timeOffset) && A.ambiguous && A.nMatched >= minMatches(numel(tA), A.nMdd)
    A.check{end+1} = 'shifts by a stimulus interval match as well';
end
tm = A.offset + A.slope * tA;
nIn = nnz(tm >= 0 & tm <= H.totalSeconds);                       %LabChart stimuli within the .mdd recording
if A.nMdd > 0 && nIn > 0 && A.nMatched < 0.8 * nIn
    A.check{end+1} = sprintf('only %d of %d LabChart stimuli within the .mdd recording matched', A.nMatched, nIn);
end
if isempty(P.timeOffset) && abs(A.clockOffset) > 60
    A.check{end+1} = sprintf('clock times differ by %.0f s (wrong file?)', A.clockOffset);
end

% ---------------------------------------------------------------- output
EP = struct();
EP.file = epFile; EP.titles = titles; EP.signalChannel = vm; EP.stimChannel = sc;
EP.block = b; EP.nBlocks = nBl; EP.fs = fs; EP.duration = numel(V) / fs;
EP.t0 = A.offset; EP.dt = A.slope / fs;
EP.V = V; EP.unitV = unitV; EP.labelV = axisLabel(titles{vm}); EP.stim = X; EP.unitStim = unitStim;
EP.labelStim = axisLabel(titles{sc});
EP.stimTimes = A.offset + A.slope * tA; EP.stimAmplitude = ampA;
EP.stimEnds = A.offset + A.slope * tEndA;
EP.comments = readComments(L, b, A);
EP.align = A;
tEnd = EP.t0 + (numel(V) - 1) * EP.dt;
info = {[nm ext]; ...
    sprintf('%s (%s) | %s (%s)', titles{vm}, unitV, titles{sc}, unitStim); ...
    sprintf('%g kHz, %.1f s, block %d of %d', fs / 1000, EP.duration, b, nBl); ...
    sprintf('.mdd time %.2f - %.2f s', EP.t0, tEnd); ''; ...
    'Alignment to the .mdd stimuli:'};
if A.nMdd == 0
    info{end+1} = sprintf('%d LabChart stimuli, no .mdd stimuli', numel(tA));
elseif isnan(A.mddChannel)
    info{end+1} = sprintf('%d of %d stimuli matched (.mdd: %d)', A.nMatched, numel(tA), A.nMdd);
elseif A.mddChannel == 0                                        %external trigger pulses of the .mdd file
    info{end+1} = sprintf('%d of %d stimuli matched (ext. trigger: %d)', A.nMatched, numel(tA), A.nMdd);
else
    info{end+1} = sprintf('%d of %d stimuli matched (ch %d: %d)', A.nMatched, numel(tA), A.mddChannel, A.nMdd);
end
info{end+1} = sprintf('offset %.4f s, drift %+.0f ppm, rms %.1f ms', A.offset, (A.slope - 1) * 1e6, A.rms * 1000);
info{end+1} = A.method;
if isfinite(A.clockOffset), info{end+1} = sprintf('clock times differ by %+.2f s', A.clockOffset); end
for k = 1:numel(A.check), info{end+1} = ['CHECK: ' A.check{k}]; end
if ~isempty(EP.comments), info{end+1} = sprintf('%d LabChart comments', height(EP.comments)); end
if nBl > 1, info{end+1} = sprintf('(%d blocks in the file)', nBl); end
EP.info = info;
EP.message = sprintf('EP recording %s: %d/%d stimuli matched, offset %.3f s (%s).', [nm ext], A.nMatched, ...
    numel(tA), A.offset, A.method);
if ~isempty(A.check)
    EP.message = ['CHECK (' strjoin(A.check, '; ') ') ' EP.message];
    fprintf('%s\n', EP.message);
    if ~isempty(A.candidates)
        fprintf('Candidate offsets [offset (s), matched stimuli, R2 amplitude~current, drift (ppm)]:\n');
        disp(A.candidates(1:min(end, 10), :));
    end
end
end


% =====================================================================================================
function c = pickChannel(v, titles, keys, dflt)
if isnumeric(v) && ~isempty(v), c = v; return; end
if ischar(v) || isstring(v), keys = {char(v)}; end
c = dflt;
for k = 1:numel(keys)
    j = find(contains(lower(titles), lower(keys{k})), 1);
    if ~isempty(j), c = j; return; end
end
if ischar(v) || isstring(v), error('No LabChart channel title contains ''%s''.', char(v)); end
end

function s = axisLabel(t)
% short axis label from a LabChart channel title
if contains(lower(t), 'membran') || strcmpi(t, 'vm'), s = 'V_m';
elseif contains(lower(t), 'stim'), s = 'stim.';
elseif numel(t) > 14, s = [t(1:13) '.'];
else, s = t;
end
end

function u = unitOf(L, ch, b)
u = '';
if isfield(L, 'unittext') && isfield(L, 'unittextmap')
    k = L.unittextmap(ch, b);
    if k > 0, u = strtrim(L.unittext(k, :)); end
end
end

function [x, u] = toMilli(x, u)
switch u
    case 'V',          x = x * 1000; u = 'mV';
    case {'µV', 'uV'}, x = x / 1000; u = 'mV';
end
end

function [t, amp, tEnd] = detectStim(x, fs, thr)
% onsets and ends (s) and amplitudes of the pulses of the stimulation channel (biphasic pulse = one pulse)
t = zeros(0, 1); amp = zeros(0, 1); tEnd = zeros(0, 1);
if isempty(x), return; end
x = abs(x - median(x));
if ischar(thr) || isstring(thr)
    thr = max(20 * 1.4826 * median(x), 0.05 * max(x));
    if thr == 0, return; end
end
a = x > thr;
if fs >= 4000, a = a & ([a(2:end); false] | [false; a(1:end-1)]); end    %>= 2 samples: no single-sample spikes
idx = find(a);
if isempty(idx), return; end
first = [true; diff(idx) > round(0.01 * fs)];                    %pulses closer than 10 ms are one pulse
g = cumsum(first);
t = (idx(first) - 1) / fs;
tEnd = (idx([first(2:end); true]) - 1) / fs;
amp = accumarray(g, double(x(idx)), [], @max);
end

function st = mddStimuli(H, opts, rg)
% stimulus pulses of the .mdd file in the time range rg (s), read in parts of one hour
st = struct('time', zeros(0, 1), 'channel', zeros(0, 1), 'current', zeros(0, 1));
if ~H.hasStimChannel, return; end
for a = rg(1):3600:rg(2)
    S = mda_readMdd(H, a, min(rg(2), a + 3600), opts);
    st.time = [st.time; S.stim.time(:)];
    st.channel = [st.channel; S.stim.channel(:)];
    st.current = [st.current; S.stim.current(:)];
end
[st.time, k] = unique(st.time + 1e-6 * st.channel);              %parts may overlap by one sample
st.time = st.time - 1e-6 * st.channel(k); st.channel = st.channel(k); st.current = st.current(k);
end

function n = minMatches(nA, nB)
n = max(3, ceil(0.3 * min(nA, nB)));
end

function A = matchChannels(A, tA, ampA, st, prior, P)
% best alignment over the MyoDish channels with stimuli (P.mddChannel first: preferred on ties)
chs = unique(st.channel(:))';
if ~isempty(P.mddChannel) && ismember(P.mddChannel, chs), chs = [P.mddChannel, setdiff(chs, P.mddChannel)]; end
best = [];
for c = chs
    k = st.channel == c;
    tB = st.time(k); cB = st.current(k);
    keep = [true; diff(tB) > 0.005];                             %one pulse = one stimulus
    R = alignStim(tA, ampA, tB(keep), cB(keep), prior, P.tolerance, P.fitDrift);
    R.mddChannel = c;
    if isempty(best) || R.nMatched > best.nMatched, best = R; end
end
if isempty(best), A.nMdd = 0; return; end
f = fieldnames(best);
for k = 1:numel(f), A.(f{k}) = best.(f{k}); end
end

function R = alignStim(tA, ampA, tB, cB, prior, tol, fitDrift)
tA = tA(:); tB = tB(:); ampA = ampA(:); cB = cB(:);
nA = numel(tA); nB = numel(tB);
R = struct('offset', NaN, 'slope', 1, 'method', '', 'nMatched', 0, 'nMdd', nB, 'rms', NaN, 'ambiguous', false, ...
    'pairs', zeros(0, 2), 'candidates', zeros(0, 3));
if nA == 0 || nB == 0, return; end

% histogram of all differences tB - tA (bins of width tol), in parts of <= 2e6 differences
dmin = min(tB) - max(tA) - tol; dmax = max(tB) - min(tA) + tol;
nb = ceil((dmax - dmin) / tol) + 1;
h = zeros(nb, 1);
step = max(1, floor(2e6 / nB));
for i = 1:step:nA
    D = tB - tA(i:min(nA, i + step - 1))';
    h = h + accumarray(floor((D(:) - dmin) / tol) + 1, 1, [nb 1]);
end
h2 = h + [h(2:end); 0];                                          %a matching difference may fall on either side of a bin edge
isMax = h2 >= [0; h2(1:end-1)] & h2 >= [h2(2:end); 0] & h2 >= max(2, 0.5 * max(h2));
cand = find(isMax);
if isempty(cand), return; end
[~, o] = sort(h2(cand), 'descend');
cand = cand(o(1:min(end, 300)));
off0 = dmin + cand * tol;                                        %centre of the two bins

nc = numel(off0);
C = zeros(nc, 4); keepR = cell(nc, 1);
for i = 1:nc
    [n, off, sl, rms, pr, ia, ib] = evalOffset(tA, tB, off0(i), tol, fitDrift);
    C(i, :) = [off, n, r2Current(ampA(ia), cB(ib)), (sl - 1) * 1e6];
    keepR{i} = {sl, rms, pr};
end
[~, o] = sortrows([-C(:, 2), abs(C(:, 1) - prior)]); C = C(o, :); keepR = keepR(o);
[~, u] = unique(round(C(:, 1) / tol), 'stable'); C = C(u, :); keepR = keepR(u);   %refined candidates may coincide
R.candidates = C;
nBest = C(1, 2);
comp = find(C(:, 2) >= nBest - max(2, ceil(0.05 * nBest)));
how = 'stimulus pattern';
if numel(comp) > 1
    r2 = C(comp, 3);
    if any(~isnan(r2))
        good = comp(r2 >= max(r2) - 0.01);
        if numel(good) < numel(comp), how = 'stimulus pattern + current'; end
        comp = good;
    end
end
if numel(comp) > 1 && isfinite(prior)
    d = abs(C(comp, 1) - prior);
    [ds, o] = sort(d);
    if ds(1) < 0.5 * ds(2)
        comp = comp(o(1)); how = [how ' + clock times'];
    end
end
if numel(comp) > 1
    R.ambiguous = true;
end
pick = comp(1);
R.offset = C(pick, 1); R.nMatched = C(pick, 2); [R.slope, R.rms, R.pairs] = keepR{pick}{:}; R.method = how;
end

function [n, off, sl, rms, pairs, ia, ib] = evalOffset(tA, tB, off, tol, fitDrift)
% matched stimuli, starting at offset off: the matched region grows with every refinement (median of the
% differences, with fitDrift a straight line through the matched stimuli, so that clock drift is followed)
sl = 1; nPrev = -1;
edges = [-Inf; (tB(1:end-1) + tB(2:end)) / 2; Inf];
for it = 1:15
    [ia, ib, d] = matchAt(tA, tB, edges, off, sl, tol);
    n = numel(ia);
    if n == 0 || (n == nPrev && it > 2), break; end
    nPrev = n;
    if fitDrift && n >= 10 && max(tA(ia)) - min(tA(ia)) >= 30
        p = polyfit(tA(ia), tB(ib), 1);
        if abs(p(1) - 1) < 0.002, sl = p(1); off = p(2); continue; end
    end
    off = off + median(d);
end
[ia, ib, d] = matchAt(tA, tB, edges, off, sl, tol);
n = numel(ia);
rms = sqrt(mean(d .^ 2));
pairs = [tA(ia), tB(ib)];
end

function [ia, ib, d] = matchAt(tA, tB, edges, off, sl, tol)
% nearest .mdd stimulus of every LabChart stimulus (one .mdd stimulus per LabChart stimulus), |difference| <= tol
x = off + sl * tA;
[~, ~, ib] = histcounts(x, edges);
d = tB(ib) - x;
ia = find(abs(d) <= tol); ib = ib(ia); d = d(ia);
[~, o] = sort(abs(d)); [~, u] = unique(ib(o), 'stable'); k = sort(o(u));
ia = ia(k); ib = ib(k); d = d(k);
end

function r2 = r2Current(amp, cur)
% fraction of the variance of the LabChart pulse amplitude explained by the stimulus current level
r2 = NaN;
if numel(amp) < 6 || numel(unique(cur)) < 2, return; end
[~, ~, g] = unique(cur);
mu = accumarray(g, amp, [], @mean);
sst = sum((amp - mean(amp)) .^ 2);
if sst > 0, r2 = 1 - sum((amp - mu(g)) .^ 2) / sst; end
end

function T = readComments(L, b, A)
T = table(zeros(0, 1), cell(0, 1), 'VariableNames', {'time', 'text'});
if ~isfield(L, 'com') || isempty(L.com) || ~isfield(L, 'comtext') || ~isfield(L, 'tickrate'), return; end
try
    c = L.com(L.com(:, 2) == b, :);
    if isempty(c), return; end
    t = A.offset + A.slope * c(:, 3) / L.tickrate(b);
    txt = strtrim(cellstr(L.comtext(c(:, 5), :)));
    T = table(t, txt, 'VariableNames', {'time', 'text'});
catch
end
end
