function [S, R] = mda_rockerFilter(S, channels, opts, Sctx)
%MDA_ROCKERFILTER  Remove the periodic rocker artifact from the force signal while the rocker moves.
%
%   [S, R] = mda_rockerFilter(S, channels, opts)          estimate the artifact in S and subtract it
%   [S, R] = mda_rockerFilter(S, channels, opts, Sctx)    estimate it in Sctx (same file, a larger time window that
%                                                          contains S: more data for short windows) and subtract it in S
%
%   S         data from mda_readMdd. Returned with the artifact subtracted from the force rows of the channels;
%             S.rockerArtifact (size of S.force, uN; 0 where nothing was subtracted), S.rockerFiltered (logical per
%             force row) and S.rockerFilterInfo (cell per force row: R of the channel)
%   channels  data channels to filter
%   opts      options from mda_options ('rockerFrequency': [] = automatic, a number (Hz) or [rpm f0] rows)
%   R         struct per channel: status, message, f0 (Hz), rpm, artifactPP (uN, peak-to-peak), r2 (fraction of the
%             diastolic signal variance explained by the artifact), correctedFraction (of the rocker-on time in S),
%             f0table ([rpm f0] rows, can be passed as 'rockerFrequency' for further channels of the same data)
%
% METHOD
%   While the rocker moves, the dish tilts periodically and the medium moves. Each sensor shows an additive periodic
%   signal with the rocker frequency f0 (the shape and size differ between channels, they are stable over time).
%   (the numbers are the defaults of the advanced settings rockerHzPerRpm and rf..., mda_options)
%   1. f0: rocker speed in the log file ('rockerSpeed', rpm) x 0.0202 Hz/rpm (measured: 60 rpm = 1.212-1.215 Hz),
%      refined +-3 % with the data of all channels (harmonic-sum periodogram of the samples between contractions;
%      a clear peak is required). Without a rocker speed in the log file: search 0.4-2.2 Hz.
%   2. Per rocker-on period (rocker bit of the status channel) in blocks of 30 s (overlap 15 s): least-squares fit of
%      6 harmonics of f0 + baseline to the samples between contractions. The baseline is fitted separately for each
%      stretch between two contractions (constant, or linear spline with knots every 2 s for stretches >= 4 s), so
%      that it cannot mimic the artifact sampled at the pacing rate.
%      Contractions are masked. Paced channels: stimulus ... stimulus + stimToPeak + 1.3 x TTR90 (+ large extra
%      contractions), or stimulus ... next stimulus - 50 ms (<= 1.2 s; robust if the artifact is larger than the
%      contractions), whichever gives the better fit; unpaced: TTP90 before ... 1.3 x TTR90 after each peak.
%      Second pass: masks from the contractions detected in the cleaned signal (used if the fit is not worse).
%   3. A block is used only if the samples between contractions cover the whole rocker cycle and the fitted artifact
%      is consistent with the channel at this rocker speed (R2 >= 0.2 and >= half the median R2, size <= 1.6 x the
%      median size of the blocks >= 10 s). Rejected blocks take the artifact of the nearest accepted block of the same rocker period
%      (<= 60 s; the phase is continuous within a rocker period). Blocks are cross-faded.
%   4. Only the periodic part (harmonics) is subtracted from the raw signal; the baseline is not changed.
%   Not possible (status, nothing subtracted): no rocker movement; rocker frequency not found; no periodic artifact
%   detectable; too little time between contractions (fast pacing of slow tissue). Changes of the contraction itself
%   by the rocker movement (e.g. a modulation of the amplitude) cannot be removed by a subtraction.
%
% TS 2026-10-05 (contraction masks independent of the option detection 2026-10-09; advanced settings 2026-10-10)

if nargin < 4 || isempty(Sctx), Sctx = S; end
channels = channels(:)';
nRow = numel(S.dataChannels);
if ~isfield(S, 'rockerArtifact') || ~isequal(size(S.rockerArtifact), size(S.force))
    S.rockerArtifact = zeros(size(S.force));
    S.rockerFiltered = false(1, nRow);
    S.rockerFilterInfo = cell(1, nRow);
end
o0 = opts; o0.rockerFilter = false; o0.rocker = 'any'; o0.beats = 'all'; o0.zeroForce = nan;
o0.detection = 'sensitive';                         %contraction masks: all contractions (independent of the mode)
thrV = [];                                          %one threshold per channel (MyoDishAnalysis; NaN = auto)
if isnumeric(opts.threshold) && numel(opts.threshold) > 1
    if numel(opts.threshold) ~= numel(channels), error('mda_rockerFilter: one threshold per channel expected.'); end
    thrV = opts.threshold(:)'; o0.threshold = 'auto';
end
oOf = @(chX) setThreshold(o0, thrV, channels, chX);  %options of the contraction masks of channel chX
P = constants(opts);
R = repmat(emptyR(), 1, numel(channels));
for c = 1:numel(channels), R(c).channel = channels(c); end

% ------------------------------------------------------------------ rocker periods and their speed
[r0, r1] = runs(Sctx.rockerOn, Sctx.dt, P.minRun);
if isempty(r0) || ~any(S.rockerOn)
    for c = 1:numel(channels)
        R(c).status = 'rocker not moving';
        R(c).message = sprintf('Rocker filter, channel %d: the rocker does not move in this time window.', channels(c));
    end
    S = store(S, R);
    return;
end
runT = [reshape(Sctx.t(r0), [], 1), reshape(Sctx.t(r1), [], 1)];   %[start end] of the rocker-on periods (s)
rpm = nan(numel(r0), 1);
if isfield(Sctx, 'rockerSpeedLog') && ~isempty(Sctx.rockerSpeedLog)
    L = Sctx.rockerSpeedLog;
    for q = 1:numel(r0)
        tq = runT(q,1) + min(5, 0.5 * (runT(q,2) - runT(q,1)));   %the speed command may follow the start shortly
        j = find(L(:,1) <= tq & L(:,2) > 0, 1, 'last');
        if ~isempty(j), rpm(q) = L(j,2); end
    end
    % periods before the first logged speed: speed of the nearest period with a logged speed
    known = find(~isnan(rpm));
    for q = find(isnan(rpm))'
        if isempty(known), break; end
        [~, k] = min(abs(runT(known,1) - runT(q,1)));
        rpm(q) = rpm(known(k));
    end
    if isempty(known)          %only stop commands before: first speed logged after the periods
        j = find(L(:,2) > 0, 1);
        if ~isempty(j), rpm(:) = L(j,2); end
    end
end
% ------------------------------------------------------------------ rocker frequency per speed
key = rpm; key(isnan(key)) = -1;             %periods without logged speed: one group
[grp, ~, gi] = unique(key);
f0run = nan(numel(r0), 1);
given = opts.rockerFrequency;
if size(given, 2) == 2, given(isnan(given(:,1)), 1) = -1; end
needEstimate = false(numel(grp), 1);
for g = 1:numel(grp)
    if isscalar(given) && given > 0
        f0run(gi == g) = given;
    elseif size(given, 2) == 2 && any(given(:,1) == grp(g))
        f0run(gi == g) = given(find(given(:,1) == grp(g), 1), 2);
    else
        needEstimate(g) = true;
    end
end
% masks of the contractions in the original signal (A: stimulus windows of paced channels; B: from the detected
% contractions); all channels for the frequency estimate, otherwise only the filtered channels
nX = numel(Sctx.dataChannels);
need = ismember(Sctx.dataChannels, channels);
if any(needEstimate), need(:) = true; end
MA = cell(1, nX); MB = cell(1, nX);
for k = find(need(:))'
    try
        [B0, C0] = mda_analyzeChannel(Sctx, Sctx.dataChannels(k), [], oOf(Sctx.dataChannels(k)));
        if numel(C0.stimTimes) >= 3, MA{k} = firstMask(B0, C0, P); end
        MB{k} = secondMask(B0, C0, P);
    catch
        MB{k} = zeros(0, 2);
    end
end
if any(needEstimate)
    MF = MB;                                  %frequency estimate: stimulus windows if they leave >= 25 % of the time
    for k = 1:nX
        if ~isempty(MA{k}) && mean(maskOf(Sctx.t(:), MA{k})) >= 0.25, MF{k} = MA{k}; end
    end
    for g = find(needEstimate)'
        if grp(g) < 0
            band = P.bandNoLog;
        else
            band = grp(g) * P.hzPerRpm * [1 - P.bandRel, 1 + P.bandRel];
        end
        f0run(gi == g) = estimateF0(Sctx, MF, runT(gi == g, :), band, grp(g) >= 0, P);
    end
end
f0table = zeros(numel(grp), 2);
for g = 1:numel(grp)
    f0table(g, :) = [grp(g) f0run(find(gi == g, 1))];
end
f0table(f0table(:,1) < 0, 1) = nan;

% ------------------------------------------------------------------ artifact per channel
onS = S.rockerOn(:);
t = Sctx.t(:);
for c = 1:numel(channels)
    ch = channels(c);
    row = find(S.dataChannels == ch, 1);
    rowX = find(Sctx.dataChannels == ch, 1);
    R(c).f0table = f0table;
    R(c).f0 = median(f0run, 'omitnan');
    R(c).rpm = median(rpm, 'omitnan');
    if isempty(row) || isempty(rowX), continue; end
    if all(isnan(f0run))
        R(c).status = 'rocker frequency not found';
        R(c).message = sprintf('Rocker filter, channel %d: rocker frequency not found (expected %s Hz) - no correction.', ...
            ch, fmtList(rpm * P.hzPerRpm));
        continue;
    end
    x = Sctx.force(rowX, :)';
    % pass 1: both masks, the better fit (accepted time x R2) is used
    I = fitArtifact(t, x, runT, gi, f0run, MB{rowX}, P);
    if ~isempty(MA{rowX})
        IA = fitArtifact(t, x, runT, gi, f0run, MA{rowX}, P);
        if IA.score > I.score, I = IA; end
    end
    R(c).pass = 1;
    % pass 2: mask from the contractions detected in the cleaned signal; fit again on the original signal
    if I.score > 0
        Sx = Sctx;
        Sx.force(rowX, :) = (x - evalArtifact(I, t, runT, f0run, P))';
        [B1, C1] = mda_analyzeChannel(Sx, ch, [], oOf(ch));
        I2 = fitArtifact(t, x, runT, gi, f0run, secondMask(B1, C1, P), P);
        if I2.score >= I.score, I = I2; R(c).pass = 2; end
    end
    a = evalArtifact(I, S.t(:), runT, f0run, P);
    S.force(row, :) = S.force(row, :) - a(:)';
    S.rockerArtifact(row, :) = a(:)';
    % result
    R(c).artifactPP = I.refPP;
    R(c).r2 = I.refR2;
    R(c).blocks = I.blk;
    R(c).correctedFraction = sum(onS & a(:) ~= 0) / max(1, sum(onS));
    pct = 100 * R(c).correctedFraction;
    fTxt = fmtList(f0run(unique(I.blk(~isnan(I.blk(:,8)), 7))));
    if isnan(I.refPP) || pct == 0
        if I.nCovered == 0
            R(c).status = 'too little time between contractions';
            R(c).message = sprintf(['Rocker filter, channel %d: too little time between the contractions to estimate the ' ...
                'rocker artifact (pacing too fast for the duration of the contractions) - no correction.'], ch);
        else
            R(c).status = 'no periodic artifact detectable';
            R(c).message = sprintf('Rocker filter, channel %d: no periodic rocker artifact detectable - no correction.', ch);
        end
    elseif pct >= 99.5
        R(c).status = 'corrected';
        R(c).message = sprintf('Rocker filter, channel %d: artifact %.0f %sN peak-to-peak (f0 %s Hz) removed.', ...
            ch, I.refPP, char(181), fTxt);
    else
        R(c).status = 'partly corrected';
        R(c).message = sprintf(['Rocker filter, channel %d: artifact %.0f %sN peak-to-peak (f0 %s Hz) removed in %.0f %% ' ...
            'of the rocker-on time (rest: not estimable).'], ch, I.refPP, char(181), fTxt, pct);
    end
end
S = store(S, R);
end


% =====================================================================================================
function P = constants(opts)
% advanced settings of the rocker filter (mda_options; before 2026-10-10: constants)
M = {'hzPerRpm', 'rockerHzPerRpm', 0.0202;    %rocker frequency per rpm setting (two setups: 0.02020 and 0.02025 Hz/rpm)
    'bandRel', 'rfBandRel', 0.03;              %search band around the expected frequency
    'bandNoLog', 'rfBandNoLog', [0.4 2.2];     %search band without rocker speed in the log file
    'K', 'rfHarmonics', 6;                     %harmonics
    'block', 'rfBlock', 30;                    %block length (s), hop = block / 2
    'minRun', 'rfMinRun', 3;                   %shorter rocker-on periods are not corrected (s)
    'knot', 'rfKnot', 2;                       %baseline knots (s)
    'lamB', 'rfSmoothBaseline', 0.1;           %smoothness penalty baseline
    'lamH', 'rfRidge', 1e-3;                   %ridge penalty harmonics
    'minCover', 'rfMinCover', 0.9;             %fraction of the 20 phase bins of the rocker cycle with >= 5 samples
    'minR2', 'rfMinR2', 0.2;
    'maxPPrel', 'rfMaxSizeRel', 1.6;           %block size <= 1.6 x reference size
    'minRefBlock', 'rfMinRefBlock', 10;        %reference blocks >= 10 s
    'maxBorrow', 'rfMaxBorrow', 60;            %artifact of a neighbouring block of the same rocker period (s)
    'f0Block', 'rfF0Block', 120;               %frequency estimate: blocks of <= 120 s (resolution), at most 6 per channel and speed
    'f0Blocks', 'rfF0Blocks', 6;
    'wideRel', 'rfF0Clear', 0.10;              %frequency estimate: the peak must be clear within +-10 %
    'extendBlock', 'rfExtendBlock', 90;        %blocks without full coverage of the rocker cycle: retried with 90 s
    'maskRelax', 'rfMaskRelax', 1.3;           %contraction masks: peak ... + 1.3 x TTR90 + margin
    'maskMargin', 'rfMaskMargin', 0.08;        %contraction masks: margin before (TTP90) and after (s)
    'maskMax', 'rfMaskMax', 1.2};              %paced: stimulus ... min(next stimulus - 50 ms, 1.2 s)
P = struct();
for k = 1:size(M, 1)
    if isfield(opts, M{k,2}), P.(M{k,1}) = double(opts.(M{k,2})); else, P.(M{k,1}) = M{k,3}; end
end
end

function R = emptyR()
R = struct('channel', nan, 'status', '', 'message', '', 'f0', nan, 'rpm', nan, 'artifactPP', nan, 'r2', nan, ...
    'correctedFraction', 0, 'pass', 0, 'f0table', zeros(0,2), 'blocks', zeros(0,8));
end

function S = store(S, R)
for c = 1:numel(R)
    row = find(S.dataChannels == R(c).channel, 1);
    if isempty(row), continue; end
    S.rockerFiltered(row) = true;
    S.rockerFilterInfo{row} = R(c);
end
end

function s = fmtList(v)
v = unique(round(v(~isnan(v)), 3));
if isempty(v), s = '?'; else, s = strjoin(arrayfun(@(x) sprintf('%.3f', x), v(:)', 'UniformOutput', false), ', '); end
end

function [s0, s1] = runs(on, dt, minLen)
d = diff([0; on(:); 0]);
s0 = find(d == 1); s1 = find(d == -1) - 1;
keep = (s1 - s0) * dt >= minLen;
s0 = s0(keep); s1 = s1(keep);
end

% ------------------------------------------------------------------ masks (time intervals with contractions)
function iv = firstMask(B, C, P)
ST = C.stimTimes(:);
if numel(ST) >= 3
    CL = [diff(ST); median(diff(ST))];
    iv = [ST - 0.02, ST + min(CL - 0.05, P.maskMax)];
else
    [ttp, ttr] = durations(B);
    iv = [C.peakTimes(:) - ttp - P.maskMargin, C.peakTimes(:) + P.maskRelax * ttr + P.maskMargin];
end
end

function iv = secondMask(B, C, P)
ST = C.stimTimes(:);
if numel(ST) >= 3
    st = strcmp(B.beatType, 'stimulated');
    [ttp, ttr] = durations(B(st, :));
    lat = median(B.stimToPeak(st), 'omitnan');
    if isnan(lat), lat = 0.3; end
    CL = [diff(ST); median(diff(ST))];
    iv = [ST - 0.02, ST + min(CL - 0.05, max(0.3, lat + P.maskRelax * ttr + P.maskMargin))];
    ampS = median(B.amplitude(st), 'omitnan');
    ex = strcmp(B.beatType, 'extra') & B.prominence >= 0.5 * ampS;
    iv = [iv; B.t_peak(ex) - ttp - P.maskMargin, B.t_peak(ex) + P.maskRelax * ttr + P.maskMargin];
else
    [ttp, ttr] = durations(B);
    iv = [C.peakTimes(:) - ttp - P.maskMargin, C.peakTimes(:) + P.maskRelax * ttr + P.maskMargin];
end
end

function [ttp, ttr] = durations(B)
ttp = median(B.TTP90, 'omitnan'); ttr = median(B.TTR90, 'omitnan');
if isnan(ttp), ttp = 0.3; end
if isnan(ttr), ttr = 0.6; end
end

function m = maskOf(t, iv)
% true = sample between contractions
n = numel(t);
m = true(n, 1);
if isempty(iv) || n < 2, return; end
dt = (t(end) - t(1)) / (n - 1);
i0 = floor((iv(:,1) - t(1)) / dt) + 1;
i1 = ceil((iv(:,2) - t(1)) / dt) + 1;
i0 = max(1, i0); i1 = min(n, i1);
ok = i1 >= i0;
if ~any(ok), return; end
d = accumarray(i0(ok), 1, [n + 1, 1]) - accumarray(i1(ok) + 1, 1, [n + 1, 1]);
m = cumsum(d(1:n)) == 0;
end

% ------------------------------------------------------------------ rocker frequency (all channels)
function f0 = estimateF0(Sctx, M, runT, band, fromLog, P)
% harmonic-sum periodogram (3 harmonics, baseline per block removed), mean over the channels; maximum within band,
% which must be a clear peak (>= 0.05 and >= 3 x the median within +-10 % around the expected frequency)
t = Sctx.t(:);
dec = max(1, round(0.02 / Sctx.dt));                %about 50 Hz is enough for the frequency
blocks = blocksOf(runT, P.f0Block);
if size(blocks, 1) > P.f0Blocks
    blocks = blocks(round(linspace(1, size(blocks, 1), P.f0Blocks)), :);
end
D = {};                                             %per channel and block: t, residual e0, basis Q
for k = 1:numel(M)
    m = maskOf(t, M{k});
    for j = 1:size(blocks, 1)
        u = find(t >= blocks(j,1) & t <= blocks(j,2) & m);
        u = u(1:dec:end);
        if numel(u) < 30, continue; end
        [Hb, ~, keep] = baseBasis(t(u), 1.5 * dec * Sctx.dt, 3, P);
        u = u(keep);
        if numel(u) < 30, continue; end
        y = Sctx.force(k, u)';
        [Q, ~] = qr(Hb, 0);
        e0 = y - Q * (Q' * y);
        D(end+1, :) = {k, t(u), e0, Q}; %#ok<AGROW>
    end
end
f0 = nan;
if isempty(D), return; end
step = 0.002;
wide = band;
if fromLog, wide = mean(band) * [1 - P.wideRel, 1 + P.wideRel]; end
fr = wide(1):step:wide(2);
r2 = meanR2(fr);
inB = fr >= band(1) & fr <= band(2);
[r2max, j] = max(r2 .* inB);
if ~(r2max >= 0.05 && r2max >= 3 * median(r2))      %no clear peak: not found
    return;
end
ff = fr(j) + (-step:step/20:step);
r2f = meanR2(ff);
[~, j] = max(r2f);
f0 = ff(j);
if f0 <= band(1) + step || f0 >= band(2) - step       %at the band edge: not found
    f0 = nan;
end
    function r = meanR2(fx)
        nCh = numel(M);
        res = zeros(nCh, numel(fx)); tot = zeros(nCh, 1);
        for i = 1:size(D, 1)
            [k_, tt, e0_, Q_] = D{i, :};
            tot(k_) = tot(k_) + sum(e0_.^2);
            for jj = 1:numel(fx)
                e1 = exp(2i * pi * fx(jj) * tt); e2 = e1 .* e1; e3 = e2 .* e1;
                X = [real(e1) imag(e1) real(e2) imag(e2) real(e3) imag(e3)];
                X = X - Q_ * (Q_' * X);
                res(k_, jj) = res(k_, jj) + sum((e0_ - X * (X \ e0_)).^2);
            end
        end
        okC = tot > 0;
        r = mean(1 - res(okC, :) ./ tot(okC), 1);
    end
end

function [u, cov] = blockSamples(t, m, a, b, f0)
% samples between contractions in [a b] and the covered fraction of the rocker cycle (20 phase bins, >= 5 samples)
u = find(t >= a & t <= b & m);
pb = floor(mod(t(u) * f0, 1) * 20);
cov = mean(accumarray(pb + 1, 1, [20 1]) >= 5);
end

function blocks = blocksOf(runT, L)
blocks = zeros(0, 3);                  %[from to run]
for q = 1:size(runT, 1)
    ts = runT(q,1); te = runT(q,2);
    if te - ts <= L
        blocks(end+1, :) = [ts te q]; %#ok<AGROW>
    else
        nb = ceil((te - ts - L) / (L/2)) + 1;
        a = linspace(ts, te - L, nb)';
        blocks = [blocks; a, a + L, repmat(q, nb, 1)]; %#ok<AGROW>
    end
end
end

% ------------------------------------------------------------------ artifact of one channel
function I = fitArtifact(t, x, runT, grpRun, f0run, iv, P)
% t, x: signal (raw force), iv: contractions [from to]; I: blocks, harmonic coefficients, consistency
m = maskOf(t, iv);
I.dt = median(diff(t));
blocks = blocksOf(runT, P.block);
nB = size(blocks, 1);
I.blk = nan(nB, 8);                  %[from to coverage r2 pp ok run source]
coef = cell(nB, 1);
for j = 1:nB
    a = blocks(j,1); b = blocks(j,2); q = blocks(j,3);
    f0 = f0run(q);
    I.blk(j, [1 2 7]) = [a b q];
    I.blk(j, 6) = 0;
    if isnan(f0), continue; end
    [u, cov] = blockSamples(t, m, a, b, f0);
    if cov < P.minCover && b - a < P.extendBlock    %e.g. pacing close to the rocker frequency: longer block
        mid = (a + b) / 2;
        a2 = max(runT(q,1), mid - P.extendBlock/2); b2 = min(runT(q,2), mid + P.extendBlock/2);
        if b2 - a2 > b - a
            [u2, cov2] = blockSamples(t, m, a2, b2, f0);
            if cov2 > cov, u = u2; cov = cov2; a = a2; b = b2; end
        end
    end
    I.blk(j, 3) = cov;
    if numel(u) < 100 || cov < P.minCover, continue; end
    [Hb, DtD, keep] = baseBasis(t(u), 1.5 * I.dt, 10, P);
    u = u(keep);
    if numel(u) < 100, continue; end
    X = [Hb, harm(t(u), f0, P.K)];
    nb = size(Hb, 2); n = numel(u);
    Pen = blkdiag(P.lamB * n / nb * DtD, P.lamH * n * eye(2 * P.K));
    cf = (X' * X + Pen) \ (X' * x(u));
    e = x(u) - X * cf;
    base = x(u) - Hb * cf(1:nb);
    r2 = 1 - sum(e.^2) / sum((base - mean(base)).^2);
    w = harm((0:0.005:1)' / f0, f0, P.K) * cf(nb+1:end);
    pp = max(w) - min(w);
    sb = sort(base);
    rng = sb(max(1, round(0.99 * n))) - sb(max(1, round(0.01 * n)));
    I.blk(j, 4:6) = [r2 pp pp <= 1.5 * rng];
    coef{j} = cf(nb+1:end);
end
I.nCovered = sum(I.blk(:,3) >= P.minCover);
% consistency of the blocks, per rocker speed (the size of the artifact depends on the speed)
good = I.blk(:,6) == 1 & I.blk(:,4) >= P.minR2 & I.blk(:,2) - I.blk(:,1) >= P.minRefBlock;
acc = false(nB, 1);
gB = reshape(grpRun(I.blk(:,7)), [], 1);
for g = unique(gB)'
    in = gB == g;
    if ~any(good & in), continue; end
    refPP = median(I.blk(good & in, 5));
    refR2 = median(I.blk(good & in, 4));
    acc = acc | (in & I.blk(:,6) == 1 & I.blk(:,4) >= max(P.minR2, 0.5 * refR2) & I.blk(:,5) <= P.maxPPrel * refPP);
end
I.blk(:,6) = acc;
I.refPP = nan; I.refR2 = nan;
if any(acc)
    I.refPP = median(I.blk(acc, 5));
    I.refR2 = median(I.blk(acc, 4));
end
I.acceptedTime = sum(I.blk(acc, 2) - I.blk(acc, 1));
I.score = I.acceptedTime * max(0, I.refR2);       %for the choice between masks
if isnan(I.score), I.score = 0; end
% coefficients per block: accepted blocks their own; others those of the nearest accepted block of the same rocker
% period (<= maxBorrow s)
ctr = mean(I.blk(:, 1:2), 2);
for j = 1:nB
    if acc(j)
        I.blk(j, 8) = j;
    else
        cand = find(acc & I.blk(:,7) == I.blk(j,7) & abs(ctr - ctr(j)) <= P.maxBorrow);
        if isempty(cand), continue; end
        [~, k] = min(abs(ctr(cand) - ctr(j)));
        I.blk(j, 8) = cand(k);
    end
end
I.coef = coef;
end

function art = evalArtifact(I, tEval, runT, f0run, P)
% artifact at the times tEval (blocks cross-faded with triangular weights, flat towards the ends of a rocker period)
art = zeros(size(tEval)); W = zeros(size(tEval));
dt = I.dt;
for j = find(~isnan(I.blk(:, 8)))'
    a = I.blk(j,1); b = I.blk(j,2); q = I.blk(j,7);
    ie = find(tEval >= a - dt/2 & tEval <= b + dt/2);
    if isempty(ie), continue; end
    te_ = tEval(ie); mid = (a + b) / 2;
    w = ones(numel(ie), 1);
    if a > runT(q,1) + dt, w = min(w, (te_ - a) / (mid - a)); end
    if b < runT(q,2) - dt, w = min(w, (b - te_) / (b - mid)); end
    w = max(w, 1e-6);
    art(ie) = art(ie) + w .* (harm(te_, f0run(q), P.K) * I.coef{I.blk(j, 8)});
    W(ie) = W(ie) + w;
end
art(W > 0) = art(W > 0) ./ W(W > 0);
end

function [Hb, DtD, keep] = baseBasis(tu, gapThr, minN, P)
% baseline of the samples between contractions, separately per gap-free stretch: a constant for stretches < 2 knot
% distances, a linear spline (smoothness penalty DtD) for longer ones. No baseline across the gaps, which could
% otherwise mimic a harmonic of the rocker sampled at the pacing rate (aliasing).
n = numel(tu);
brk = [0; find(diff(tu(:)) > gapThr); n];
keep = false(n, 1);
Hs = {}; Ds = {};
for w = 1:numel(brk) - 1
    iw = (brk(w) + 1:brk(w + 1))';
    if numel(iw) < minN, continue; end
    keep(iw) = true;
    tw = tu(iw);
    if tw(end) - tw(1) < 2 * P.knot
        Hs{end+1} = ones(numel(iw), 1); Ds{end+1} = 0; %#ok<AGROW>
    else
        H = hats(tw, P.knot);
        Dm = diff(eye(size(H, 2)), 2);
        Hs{end+1} = H; Ds{end+1} = Dm' * Dm; %#ok<AGROW>
    end
end
Hb = blkdiag(Hs{:});
DtD = blkdiag(Ds{:});
end

function X = harm(t, f0, K)
X = zeros(numel(t), 2*K);
for k = 1:K
    X(:, 2*k-1) = cos(2*pi*k*f0*t);
    X(:, 2*k) = sin(2*pi*k*f0*t);
end
end

function H = hats(t, step)
% linear spline basis (hat functions), knots evenly over [t(1) t(end)] with a spacing <= step
n = max(2, ceil((t(end) - t(1)) / step) + 1);
kn = linspace(t(1), t(end), n);
h = kn(2) - kn(1);
H = max(0, 1 - abs(t(:) - kn) / h);
end


function o = setThreshold(o, thrV, channels, chX)
% options with the threshold of channel chX (per-channel thresholds thrV of MyoDishAnalysis; others: as in o)
if ~isempty(thrV) && any(channels == chX), o.threshold = thrV(find(channels == chX, 1)); end
end
