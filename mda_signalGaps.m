function G = mda_signalGaps(src, opts, varargin)
%MDA_SIGNALGAPS  Periods without force signal: chamber taken out, sensor board failures, channels without a chamber.
%
%   G = mda_signalGaps(mddFile)              or  G = mda_signalGaps(H)   (H from mda_readMdd)
%   G = mda_signalGaps(mddFile, opts)        opts from mda_options (calibration of the values)
%   G = mda_signalGaps(..., 'minSeconds', 2, 'simultaneous', 1, 'simultaneousPair', 0.1, 'mergeSeconds', 0.5)
%
% Without a sensor board (chamber taken out of the setup, defective board) the controller repeats the last value of the
% channel: the signal stays at exactly the same number. A connected sensor never gives identical values for seconds
% (noise of the AD converter). A period without signal = at least 'minSeconds' (default 2 s) of identical consecutive
% raw samples of a data channel. Periods of a channel less than 'mergeSeconds' (default 0.5 s) apart are one period (the
% value held may jump once, e.g. when another board of the controller is plugged in or the controller restarts).
%
% G  table, one row per period and channel, sorted by the start:
%      channel, from, to, duration (s in the file; to = first sample with signal again or the end of the file)
%      type            'chamber out'  one channel: chamber taken out (and put back at 'to' unless untilEnd). The
%                                     reason is not in the signal (log comments, documentation).
%                      'board group'  >= 3 channels of the same group (1-4 or 5-8) within 'simultaneous' s (default
%                                     1), or 2 channels within 'simultaneousPair' s (default 0.1): faster than a person
%                                     can take chambers out (two hands: two chambers at once), i.e. a technical failure
%                                     (a defective sensor board disturbs the other boards of its group)
%                      'controller'   the same with channels of both groups (controller, connection)
%                      'saturated'    the value held is the limit of the AD converter (-32768 or 32767: overload)
%                      'no signal'    the whole recording (no chamber in this channel)
%      nSimultaneous   channels in the same event (1 for 'chamber out')
%      spread          s between the first and the last channel of the event (0 for 'chamber out')
%      fromStart       the period begins with the file (chamber put in at 'to', or taken out before the file began):
%                      simultaneity is then judged from the ends (signal back within 'simultaneous' s)
%      untilEnd        the period lasts until the end of the file
%      valueAU, value  value held (raw value of the file; uN, or AU with 'calibration','none')
%      levelBefore     10th percentile of the 5 s before the period (ending 0.5 s before it): diastolic level
%      levelAfter      10th percentile of the 5 s after the period (from 2 s after it)
%      levelChange     levelAfter - levelBefore (e.g. other preload or another slice after putting the chamber back)
%      spikeBefore     largest deviation from the median of the 2 s before the period within its last 0.5 s
%      spikeAfter      largest deviation from the median of the 2 s after the period (from 0.5 s) within its first 0.5 s
%                      (levels and spikes NaN where there is no signal)
%
% Reads the raw data of the whole file in 1-h blocks.
%
% TS 2026-10-08

if nargin < 2 || isempty(opts), opts = mda_options(); end
P = struct('minSeconds', 2, 'simultaneous', 1, 'simultaneousPair', 0.1, 'mergeSeconds', 0.5);
for i = 1:2:numel(varargin)
    name = validatestring(varargin{i}, fieldnames(P));
    P.(name) = varargin{i+1};
end
if isstruct(src), H = src; else, H = mda_readMdd(char(src), [], [], opts); end
optsFull = mda_options(opts, 'downsampling', 1, 'spikeRemoval', false);   %levels and spikes at the periods: raw
fs = H.samplingRate;
ch = H.dataChannels(:)'; nCh = numel(ch);
minN = max(2, round(P.minSeconds * fs));

% runs of identical consecutive raw samples (indices of the samples, 1 = first sample of the file), read directly in
% blocks of 1 h
runs = zeros(0, 4);                                    %[channel index, first sample, last sample, raw value]
cur = nan(nCh, 2); lastVal = nan(nCh, 1); n0 = 0;
nF = H.nChannelsInFile; N = H.totalSamples; block = round(3600 * fs);
fid = fopen(H.file, 'r', 'ieee-le');
if fid < 0, error('mda_signalGaps: cannot open %s', H.file); end
cleaner = onCleanup(@() fclose(fid));
while n0 < N
    m = min(block, N - n0);
    raw = fread(fid, [nF m], 'int16=>int16');
    m = size(raw, 2);
    if m == 0, break; end
    for c = 1:nCh
        v = double(raw(c, :));
        st = find([v(1) ~= lastVal(c), diff(v) ~= 0]);  %first samples of segments with a new value
        if ~isempty(st)
            if ~isnan(cur(c,1)) && n0 + st(1) - cur(c,1) >= minN      %segment continued from the previous block
                runs(end+1, :) = [c, cur(c,1), n0 + st(1) - 1, cur(c,2)]; %#ok<AGROW>
            end
            q = find(diff(st) >= minN);                                %segments within this block
            runs = [runs; repmat(c, numel(q), 1), n0 + st(q)', n0 + st(q+1)' - 1, v(st(q))']; %#ok<AGROW>
            cur(c, :) = [n0 + st(end), v(st(end))];                    %last segment: continues in the next block
        end
        lastVal(c) = v(end);
    end
    n0 = n0 + m;
end
for c = 1:nCh
    if ~isnan(cur(c,1)) && n0 - cur(c,1) + 1 >= minN
        runs(end+1, :) = [c, cur(c,1), n0, cur(c,2)]; %#ok<AGROW>
    end
end

% merge periods of a channel that are less than mergeSeconds apart (glitch between two held values)
runs = sortrows(runs, [1 2]);
keep = true(size(runs, 1), 1);
for r = 2:size(runs, 1)
    q = find(keep(1:r-1), 1, 'last');
    if runs(r,1) == runs(q,1) && runs(r,2) - runs(q,3) - 1 < P.mergeSeconds * fs
        runs(q,3) = max(runs(q,3), runs(r,3)); keep(r) = false;
    end
end
runs = runs(keep, :);
nR = size(runs, 1);
G = table(zeros(nR,1), zeros(nR,1), zeros(nR,1), zeros(nR,1), repmat({''}, nR, 1), ones(nR,1), zeros(nR,1), ...
    false(nR,1), false(nR,1), zeros(nR,1), zeros(nR,1), nan(nR,1), nan(nR,1), nan(nR,1), nan(nR,1), nan(nR,1), ...
    'VariableNames', {'channel','from','to','duration','type','nSimultaneous','spread','fromStart','untilEnd', ...
    'valueAU','value','levelBefore','levelAfter','levelChange','spikeBefore','spikeAfter'});
if nR == 0, return; end
G.channel = ch(runs(:,1))';
G.from = (runs(:,2) - 1) / fs;
G.to = runs(:,3) / fs;                                 %end of the last identical sample
G.duration = G.to - G.from;
G.fromStart = runs(:,2) == 1;
G.untilEnd = runs(:,3) == n0;
G.valueAU = runs(:,4);
for r = 1:nR
    G.value(r) = G.valueAU(r) * mda_calibrationFactor(H, G.channel(r), G.from(r));
end

% type
sat = G.valueAU <= -32768 | G.valueAU >= 32767;
none = G.fromStart & G.untilEnd;
G.type(:) = {'chamber out'};
G.type(sat) = {'saturated'};
G.type(none & ~sat) = {'no signal'};
grp = 1 + (G.channel > 4);
% simultaneous events: signal lost (from) of periods within the file, and signal back (to) of periods from the file
% start, each kind separately. A person has two hands: >= 3 channels within 'simultaneous' s, or 2 channels within
% 'simultaneousPair' s are technical. (Sample of 88 recordings: 21 technical events, 19 within 0.01 s, max. 0.42 s;
% two chambers taken out with both hands 0.36 and 0.6 s apart, one after the other mostly >= 2.4 s apart.)
for kind = 1:2
    if kind == 1
        cand = find(~sat & ~none & ~G.fromStart); ev = G.from;
    else
        cand = find(~sat & ~none & G.fromStart); ev = G.to;
    end
    [~, o] = sort(ev(cand)); cand = cand(o);
    k = 1;
    while k <= numel(cand)
        j = k;
        while j < numel(cand) && ev(cand(j+1)) - ev(cand(k)) <= P.simultaneous
            j = j + 1;
        end
        I = cand(k:j);
        spread = ev(I(end)) - ev(I(1));
        if numel(I) >= 3 || (numel(I) == 2 && spread <= P.simultaneousPair)
            if all(grp(I) == grp(I(1))), G.type(I) = {'board group'}; else, G.type(I) = {'controller'}; end
            G.nSimultaneous(I) = numel(I);
            G.spread(I) = spread;
        end
        k = j + 1;
    end
end

% levels and spikes around the period (signal of the channel)
for r = find(~none)'
    c = G.channel(r);
    if ~G.fromStart(r)
        [G.levelBefore(r), G.spikeBefore(r)] = around(H, optsFull, c, G.from(r), -1);
    end
    if ~G.untilEnd(r)
        [G.levelAfter(r), G.spikeAfter(r)] = around(H, optsFull, c, G.to(r), 1);
    end
end
G.levelChange = G.levelAfter - G.levelBefore;
G = sortrows(G, {'from', 'channel'});
end


function [level, spike] = around(H, opts, c, t0, side)
% diastolic level (10th percentile of 5 s, 0.5 s / 2 s away from the period) and spike (largest deviation from the
% median of the 2 s next to the period within the 0.5 s next to it); side -1 = before t0, +1 = after t0
level = nan; spike = nan;
if side < 0
    w = [t0 - 5.5, t0 - 0.5]; ws = [t0 - 2, t0];
else
    w = [t0 + 2, t0 + 7]; ws = [t0, t0 + 2];
end
w = max(min(w, H.totalSeconds), 0); ws = max(min(ws, H.totalSeconds), 0);
iC = find(H.dataChannels == c, 1);
if w(2) - w(1) >= 1
    S = mda_readMdd(H, w(1), w(2), opts);
    level = mprctile(S.force(iC, :), 10);
end
if ws(2) - ws(1) >= 1
    S = mda_readMdd(H, ws(1), ws(2), opts);
    x = S.force(iC, :);
    if side < 0, near = S.t >= ws(2) - 0.5; ref = ~near; else, near = S.t < ws(1) + 0.5; ref = ~near; end
    if any(near) && any(ref)
        spike = max(abs(x(near) - median(x(ref))));
    end
end
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
