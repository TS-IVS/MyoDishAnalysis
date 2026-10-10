function [X, spikes] = mda_removeSpikes(X, fs, opts)
%MDA_REMOVESPIKES  Spike artifacts of the force channels: detection and removal.
%
%   [X, spikes] = mda_removeSpikes(X, fs)        X: channels x samples (raw samples of the force channels, AU)
%   [X, spikes] = mda_removeSpikes(X, fs, opts)  options (mda_options) spikeJumpMin, spikeJumpFactor, spikeGroupGap,
%                                                spikeMaxDuration, spikeLevelWindow, spikeJumpFraction,
%                                                spikeCoincidence, spikeCoincidenceFactor (advanced settings; the
%                                                numbers below are their defaults)
%
% Spikes appear e.g. when a chamber is taken out or put in, often in several channels at once: the value jumps within
% 1-2 samples and comes back within a few ms (or goes on to a new level). A spike is a group of jumps (|difference
% between two samples| >= J; jumps < 40 ms apart form one group) that lasts <= 100 ms, goes beyond the level before
% and the level after it (median of the 20 ms before / after) by >= J, and whose largest jump is >= 50 % of its
% largest deviation from the level before (abrupt; a contraction rises over many samples: at most ~30 % of its
% amplitude per sample at 400 Hz). J = max(50 AU, 8 x median of the non-zero |differences| of the channel) (noise
% level: independent of contractions and spikes). Where a spike of another channel lies within +-10 ms, J = max(50
% AU, J / 2) (spikes in several channels). A level change (step when a chamber is put in or taken out: one jump or a
% monotonic transition) is no spike and stays. Replaced: the samples between the first and the last jump of the
% group, by a line from the sample before to the sample after (a step with a spike becomes a short ramp).
%
% spikes   one row per spike: channel index, first and last replaced sample, size (largest deviation from the
%          sample before the spike, AU)
%
% Used by mda_readMdd (option 'spikeRemoval', default true) before the averaging of the raw samples.
%
% TS 2026-10-10 (advanced settings 2026-10-10)

if nargin < 3, opts = struct(); end
D = struct('spikeJumpMin', 50, 'spikeJumpFactor', 8, 'spikeGroupGap', 0.04, 'spikeMaxDuration', 0.1, ...
    'spikeLevelWindow', 0.02, 'spikeJumpFraction', 0.5, 'spikeCoincidence', 0.01, 'spikeCoincidenceFactor', 0.5);
for f = fieldnames(D)'
    if isfield(opts, f{1}), D.(f{1}) = double(opts.(f{1})); end
end
JUMP_MIN = D.spikeJumpMin; JUMP_FACTOR = D.spikeJumpFactor; GROUP_GAP_MS = 1000 * D.spikeGroupGap;
MAX_MS = 1000 * D.spikeMaxDuration; LEVEL_MS = 1000 * D.spikeLevelWindow; COINCIDENCE_MS = 1000 * D.spikeCoincidence;
X = double(X);
[nCh, n] = size(X);
G = max(1, round(GROUP_GAP_MS * fs / 1000));
Lmax = max(1, round(MAX_MS * fs / 1000));
W = max(2, round(LEVEL_MS * fs / 1000));
Cw = max(1, round(COINCIDENCE_MS * fs / 1000));
found = zeros(0, 4);
J1 = zeros(nCh, 1);                                %jump threshold of every channel (pass 1)
replaced = false(nCh, n);
if n < 2 * W + 2, spikes = found; return; end
for pas = 1:2
    if pas == 2 && isempty(found), break; end
    for c = 1:nCh
        x = X(c, :);
        ad = abs(diff(x));
        if pas == 1
            nz = ad(ad > 0);
            if isempty(nz), m = 0; else, m = median(nz); end
            J1(c) = max(JUMP_MIN, JUMP_FACTOR * m);
            J = J1(c);
            big = find(ad >= J);
        else                                           %within +-10 ms of a spike of another channel
            near = false(1, n);
            for f = find(found(:, 1) ~= c)'
                near(max(1, found(f, 2) - Cw):min(n, found(f, 3) + Cw)) = true;
            end
            J = max(JUMP_MIN, D.spikeCoincidenceFactor * J1(c));
            big = find(ad >= J & near(1:end-1) & ~replaced(c, 1:end-1) & ~replaced(c, 2:end));
        end
        if isempty(big), continue; end
        br = find(diff(big) > G);
        g1 = big([1, br + 1]); g2 = big([br, numel(big)]);
        for q = 1:numel(g1)
            k1 = g1(q); k2 = g2(q);                    %jump k: x(k) -> x(k+1)
            if any(replaced(c, k1+1:k2)) || ~isSpike(x, k1, k2, J, W, Lmax, D.spikeJumpFraction), continue; end
            sz = max(abs(x(k1+1:k2) - x(k1)));
            idx = k1+1:k2;
            x(idx) = x(k1) + (x(k2+1) - x(k1)) * (idx - k1) / (k2 + 1 - k1);
            replaced(c, idx) = true;
            found(end+1, :) = [c, k1 + 1, k2, sz]; %#ok<AGROW>
        end
        X(c, :) = x;
    end
end
spikes = sortrows(found, [2 1]);
end


function tf = isSpike(x, k1, k2, J, W, Lmax, frac)
% jumps k1..k2: x(k1+1..k2) is a spike
tf = false;
if k2 <= k1 || k2 - k1 > Lmax || k1 - W + 1 < 1 || k2 + W > numel(x), return; end
seg = x(k1+1:k2);
before = median(x(k1-W+1:k1));
after = median(x(k2+1:k2+W));
beyond = max(max(seg) - max(before, after), min(before, after) - min(seg));
if beyond < J, return; end                         %a step / monotonic transition
largestJump = max(abs(diff(x(k1:k2+1))));
tf = largestJump >= frac * max(abs(seg - before));
end
