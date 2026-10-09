function [B, C] = mda_analyzeChannel(S, channel, range, opts)
%MDA_ANALYZECHANNEL  Detect the contractions of one channel and calculate their parameters.
%
%   [B, C] = mda_analyzeChannel(S, channel, range, opts)
%
%   S        data from mda_readMdd (should start/end a few seconds before/after the range, so that the
%            first and last contraction of the range are complete)
%   channel  data channel (1-8; single channel files: 1)
%   range    [from to] in s (time in the file); contractions whose peak lies in the range are returned.
%            [] = all contractions in S
%   opts     options from mda_options
%
%   B  table, one row per contraction (see below)
%   C  struct: filtered signal (t, f), detection threshold, stimulus times of the channel (stimTimes) and
%      whether each stimulus was followed by a contraction (stimCaptured), the stimulus channel used (stimChannel;
%      0 = external trigger pulses, option 'externalTrigger'), all peaks in S (iPeaks); with the option
%      'rockerFilter': result of mda_rockerFilter (rockerFilter) and the subtracted artifact (rockerArtifact);
%      referenceBeat: the reference used for the columns refCorrelation, refRMSDeviation..., refMaxDeviation... ([] = none)
%   With the option referenceBeat, B also contains every parameter relative to the reference: <parameter>_pctRef
%   (% of the mean of the reference contractions), diastolicForce_dRef / diastolicSignal_dRef (difference, uN)
%
% PROCESSING
%   0. option 'rockerFilter': the periodic rocker artifact is subtracted first (mda_rockerFilter); column
%      rockerCorrected = contraction while the rocker moved and the artifact was subtracted
%   1. filter: moving median (50 ms) + moving mean (25 ms) on the 200 Hz signal (as GetContractionParameters)
%   2. contractions = local maxima with a prominence >= threshold that are >= minBeatInterval apart.
%      Automatic threshold (default): relThreshold (0.3) x the typical contraction amplitude, at least
%      minThreshold (30 uN). Typical amplitude: paced channels: median of the n largest prominences
%      (n = number of stimuli in the data); unpaced: the prominences above the largest gap between the
%      sorted prominences (see autoThreshold). Paced channels, auto threshold (option rockerArtifacts):
%      a) small peaks between the contractions (<= 0.5 x typical, not locked to the stimuli) that form a cluster
%         separated from the contractions by a clear gap: the threshold is raised into the gap
%         (artifactGapThreshold);
%      b) rocker moving (>= 50 % of the data); rocker / noise level N = 90th percentile of the rise of the signal
%         in the windows before the stimuli after intervals >= 0.9 s (preStimulusNoise). The largest peaks (as
%         many as stimuli) not locked to the stimuli (< 50 % within the densest 0.2-s window of their latencies)
%         and either typical amplitude <= 50 uN or typical <= 2 x N with the peaks at the rhythm of the rocker
%         (0.7 ... 2.2 peaks per rocker cycle or median interval 1 or 1/2 rocker period; rocker speed of the log
%         file x 0.0202 Hz/rpm); without N (high rates, no intervals >= 0.9 s): >= 60 % of the peak intervals
%         1 or 1/2 rocker period, no 1:1 / 2:1 capture at the rocker period, not locked (+-0.2 x interval): rocker /
%         noise peaks - all peaks < 3 x max(typical, N) are removed, except peaks locked to the stimuli
%         >= max(1.5 x N, N + 50 uN) if there are >= max(3, 5 % of the stimuli) of them and more than by chance
%         (only some stimuli answered); C.noContractions if no peak is left (slice not beating);
%      c) rocker moving, otherwise: peaks not locked to the stimuli with a prominence < min(1.5 x N,
%         0.5 x typical) are removed, < min(1.5 x N, typical) if they are at the rhythm of the rocker
%         (rockerNoiseRule).
%      Small peaks locked to a stimulus (alternans, partial capture) stay. C.thresholdArtifacts = number of
%      removed peaks, C.noiseLevel = N.
%   2b. certainty (auto threshold, option 'detection'): paced channels: a contraction is certain if it is locked
%      to the stimuli (latency within +-min(0.1 s, 0.2 x stimulus interval) of the typical latency) and >= 2 x the
%      median rise before the stimuli (C.noiseMedian), or large (>= 0.7 x typical and >= 3 x that median);
%      unpaced: >= 0.5 x typical. Otherwise column uncertain = true ('sensitive', default) or the contraction is
%      not counted ('specific'). C.stimCapturedCertain: stimulus followed by a certain contraction.
%   3. stimulus assignment: a contraction is 'stimulated' if its peak follows a stimulus of the channel
%      by minStimToPeak ... maxStimToPeak (and is the most prominent peak after this stimulus), otherwise
%      'extra'. Channels without stimulus pulses: 'unpaced'.
%   4. parameters, per contraction, between the previous and the next peak (at most maxBeatWindow s):
%      diastolic minimum before the peak (F_dia) and minimum after the peak (F_min,post). After a stimulation
%      pause (stimulus interval >= 2.5 s and >= 1.5 x the interval before) F_dia is searched only from
%      pauseDiastoleWindow (0.5 s) before the stimulus (mda_options).
%        amplitude       F_peak - F_dia                                                [uN]
%        diastolicForce  F_dia - zero force (zero = 'Offset' of the channel in the log file or 'zeroForce') [uN]
%        diastolicSignal F_dia (sensor signal at the minimum before the peak)            [uN]
%        dFdtMax         maximum of dF/dt between F_dia and the peak                     [uN/s]
%        dFdtMin         minimum of dF/dt between the peak and F_min,post               [uN/s]
%        riseTime10_90   10 % --> 90 % of the amplitude (upstroke)                       [s]
%        TTP90           rise time 90 %: 10 % of the amplitude (upstroke) --> peak       [s]
%        TTR50, TTR90    peak --> 50 % / 90 % relaxation                                 [s]
%        CD50            50 % (upstroke) --> 50 % relaxation (full width at half maximum) [s]
%        CD90            10 % (upstroke) --> 90 % relaxation                             [s]
%        AUC             integral of (F - F_dia) from 10 % (upstroke) to 90 % relaxation  [uN*s]
%        peakToPeakInterval / peakToPeakFrequency   to the previous contraction          [s] / [Hz]
%      Upstroke levels: F_dia + x % of the amplitude, last crossing before the peak. Relaxation levels:
%      F_min,post + (100-x) % of (F_peak - F_min,post), first crossing after the peak (x % relaxation).
%      Crossing times are interpolated linearly between samples.
%
% TS 2026-10-05 (rocker artifacts, certainty of contractions 2026-10-09)

if nargin < 3, range = []; end
if nargin < 4 || isempty(opts), opts = mda_options(); end
if ~isfield(opts, 'rockerFilter') || ~isfield(opts, 'referenceBeat') || ~isfield(opts, 'pauseDiastoleWindow')
    opts = mda_options(opts);       %options struct of an older version
end

row = find(S.dataChannels == channel, 1);
if isempty(row)
    error('mda_analyzeChannel: channel %d is not in the file (data channels: %s).', channel, mat2str(S.dataChannels));
end
if isempty(range), range = [S.fromSeconds S.toSeconds]; end

% rocker artifact (option 'rockerFilter'): subtracted here, unless S was filtered before (mda_rockerFilter with
% more context, e.g. by the GUI)
RF = [];
if opts.rockerFilter
    if isfield(S, 'rockerFiltered') && numel(S.rockerFiltered) >= row && S.rockerFiltered(row)
        RF = S.rockerFilterInfo{row};
    else
        [S, RF] = mda_rockerFilter(S, channel, opts);
    end
end

dt = S.dt;
[f, t] = filterSignal(S.force(row,:), S.t, dt, opts);
N = numel(f);
g = gradient(f) / dt;

% ------------------------------------------------------------------ stimuli
stimCh = opts.stimChannel;
isMD = S.stim.channel > 0;                          %MyoDish stimulus pulses (0 = external trigger pulse)
if isempty(stimCh)
    stimCh = channel;
    % files with fewer than 8 data channels (single channel mode): the data rows are numbered 1..n, the stimulus
    % pulses keep the physical channel number. If there are no pulses for this number: the stimulated channel.
    if numel(S.dataChannels) < 8 && any(isMD) && ~any(S.stim.channel == channel)
        stimCh = mode(S.stim.channel(isMD));
    end
end
% external trigger pulses (external stimulator at the external controller unit: one chamber, no channel number) as
% stimuli: 'on', or 'auto' if the window has trigger pulses but no MyoDish pulses (2026-10-08)
xt = 'auto';
if isfield(opts, 'externalTrigger'), xt = opts.externalTrigger; end
if strcmp(xt, 'on') || (strcmp(xt, 'auto') && ~any(isMD) && any(S.stim.channel == 0))
    stimCh = 0;
end
ST = sort(S.stim.time(S.stim.channel == stimCh));
CL = nan;
if numel(ST) > 1, CL = median(diff(ST)); end
if isnumeric(opts.maxStimToPeak)
    maxLat = opts.maxStimToPeak;
elseif isnan(CL)
    maxLat = 0.9;
else
    maxLat = min(CL, 1.0);
end

% ------------------------------------------------------------------ detection
[isMax, P] = islocalmax(f);
cand = find(isMax);
prom = P(cand);
if isnumeric(opts.threshold) && numel(opts.threshold) > 1
    error('mda_analyzeChannel: one threshold per channel (several channels: MyoDishAnalysis).');
end
nArt = 0;                                           %peaks removed as rocker artifacts
keepLow = false(size(prom));                        %small peaks below a raised threshold that are kept (locked)
drop = false(size(prom));                           %peaks removed by the rocker / noise level
noBeats = false;                                    %no contractions (peaks at the rocker / noise level)
noiseLvl = nan;                                     %rocker / noise level before the stimuli (uN, 90th percentile)
noiseMed = nan;                                     %median rise before the stimuli (uN; certainty of contractions)
if isnumeric(opts.threshold) && ~isnan(opts.threshold)  %NaN = auto (per-channel thresholds of MyoDishAnalysis)
    thr = opts.threshold;
    thrMode = 'manual';
    typAmp = nan;
else
    [thr, typAmp] = autoThreshold(prom, numel(ST), opts);
    thrMode = 'auto';
    if numel(ST) >= 3                               %paced: rocker / noise level before the stimuli
        [noiseLvl, nNoise, noiseMed] = preStimulusNoise(t, f, ST);
        if nNoise < 10, noiseLvl = nan; noiseMed = nan; end
    end
    if (~isfield(opts, 'rockerArtifacts') || opts.rockerArtifacts) && numel(ST) >= 3   %paced: rocker artifacts
        [thr, keepLow, nArt] = artifactGapThreshold(t(cand), prom, thr, typAmp, ST, S.rockerOn(cand), CL);
        if mean(S.rockerOn) >= 0.5
            fR = rockerFrequency(S, opts);
            [drop, noBeats] = rockerNoiseRule(t(cand), prom, thr, keepLow, typAmp, ST, noiseLvl, ...
                S.rockerOn(cand), nnz(S.rockerOn) * dt, fR);
            nArt = nArt + nnz(drop);
        end
    end
end
keep = (prom >= thr | keepLow) & ~drop;
cand = cand(keep);
prom = prom(keep);
% minimum interval: the more prominent of two close maxima wins
[~, order] = sort(prom, 'descend');
w = max(1, round(opts.minBeatInterval / dt));
blocked = false(1, N);
accepted = false(size(cand));
for q = order(:)'
    i = cand(q);
    if ~blocked(i)
        accepted(q) = true;
        blocked(max(1,i-w+1):min(N,i+w-1)) = true;
    end
end
iPk = cand(accepted);
promPk = prom(accepted);
% certainty (option 'detection', 2026-10-09). Paced: certain = locked to the stimuli (latency within +-hw of the
% typical latency, hw = min(0.1 s, 0.2 x stimulus interval before the largest contractions)) and >= 2 x Nm, or large
% (>= 0.7 x typical and >= 3 x Nm); Nm = median rise before the stimuli (robust against contractions in these
% windows; unknown: locked suffices), typical = median of the largest contractions (as many as stimuli). Unpaced:
% certain = >= 0.5 x typical (auto threshold). 'sensitive': uncertain contractions are counted and flagged (column
% uncertain); 'specific': they are removed. Manual threshold: not assessed.
certain = true(size(iPk));
if strcmp(thrMode, 'auto') && ~isempty(iPk)
    if numel(ST) >= 3
        [~, o] = sort(promPk, 'descend');
        top = o(1:min(numel(o), numel(ST)));
        typC = median(promPk(top));
        lat = stimLatency(t(iPk), ST);
        ci = nan(size(top));                               %stimulus interval before the largest contractions
        for q = 1:numel(top)
            j = find(ST <= t(iPk(top(q))), 1, 'last');
            if ~isempty(j) && j >= 2, ci(q) = ST(j) - ST(j-1); end
        end
        hw = min(0.1, 0.2 * median(ci, 'omitnan'));
        if isnan(hw), hw = 0.1; end
        lk = latencyLock(lat, top, hw);
        certain = (lk & ~(promPk < 2 * noiseMed)) | ~(promPk < max(0.7 * typC, 3 * noiseMed));  %NaN: no limit
    elseif ~isnan(typAmp)
        certain = promPk >= 0.5 * typAmp;
    end
end
if isfield(opts, 'detection') && strcmp(opts.detection, 'specific')
    iPk = iPk(certain);
    promPk = promPk(certain);
    certain = certain(certain);
end
nPk = numel(iPk);
tPk = t(iPk);

% ------------------------------------------------------------------ stimulus assignment
beatType = repmat({'unpaced'}, nPk, 1);
tStimOfBeat = nan(nPk, 1);
jStimOfBeat = zeros(nPk, 1);
stimCaptured = false(numel(ST), 1);
stimCapturedCertain = false(numel(ST), 1);          %stimulus followed by a certain contraction
if ~isempty(ST)
    beatType(:) = {'extra'};
    j = zeros(nPk, 1);
    for k = 1:nPk
        jj = find(ST <= tPk(k) - opts.minStimToPeak, 1, 'last');
        if ~isempty(jj) && tPk(k) - ST(jj) <= maxLat
            j(k) = jj;
        end
    end
    for jj = unique(j(j > 0))'
        ks = find(j == jj);
        [~, best] = max(promPk(ks));      %several peaks after one stimulus: the most prominent one
        k = ks(best);
        beatType{k} = 'stimulated';
        tStimOfBeat(k) = ST(jj);
        jStimOfBeat(k) = jj;
        stimCaptured(jj) = true;
        stimCapturedCertain(jj) = any(certain(ks));     %captured in the 'specific' mode, too
    end
end
% contractions after a stimulation pause (stimulus interval >= 2.5 s and >= 1.5 x the interval before; without a
% previous stimulus in the data: time since the start of the data; without the interval before: median interval):
% F_dia is searched only from opts.pauseDiastoleWindow before the stimulus, not during the pause (drift, rocker
% movement until shortly before the stimulus, e.g. post-rest potentiation protocols)
afterPause = false(nPk, 1);
for k = find(jStimOfBeat > 0)'
    jj = jStimOfBeat(k);
    if jj >= 2, prevInt = ST(jj) - ST(jj-1); else, prevInt = ST(jj) - t(1); end
    if jj >= 3, before = ST(jj-1) - ST(jj-2); else, before = CL; end
    afterPause(k) = prevInt >= max(2.5, 1.5 * before);
end

% ------------------------------------------------------------------ zero force (sensor signal without load)
% 'Offset' entries of the log file (one per channel, written at the start of a recording; 0 = not calibrated) or
% opts.zeroForce. Scaled like the data in extended sensor mode.
[~, zeroSource, zeroT, zeroV] = mda_zeroForce(S, channel, opts.zeroForce);

% ------------------------------------------------------------------ parameters
sel = find(tPk >= range(1) & tPk <= range(2));
n = numel(sel);
PI = mda_parameters();
names = PI(:,1)';            %columns of V
ix = struct();
for k = 1:numel(names), ix.(names{k}) = k; end
V = nan(n, numel(names));
rockerMoving = false(n, 1);
maxW = round(opts.maxBeatWindow / dt);
for q = 1:n
    k = sel(q);
    i = iPk(k);
    if k > 1, a = iPk(k-1); else, a = 1; end
    if k < nPk, b = iPk(k+1); else, b = N; end
    a = max([a, i - maxW, 1]);
    b = min([b, i + maxW, N]);
    if afterPause(k), a = max(a, find(t >= tStimOfBeat(k) - opts.pauseDiastoleWindow, 1)); end
    [Fdia, ia] = min(f(i:-1:a)); ia = i - ia + 1;   %last minimum before the peak (flat diastole: the one next to the upstroke)
    [Fpost, ib] = min(f(i:b));  ib = i + ib - 1;
    Fpk = f(i);
    A = Fpk - Fdia;
    if k > 1, V(q,ix.peakToPeakInterval) = tPk(k) - tPk(k-1); end
    rockerMoving(q) = any(S.rockerOn(ia:ib));   %replaced below by F_dia ... 90 % relaxation, if available
    if A <= 0 || ia == 1         %no upstroke within the data (contraction starts before the loaded data)
        continue;
    end
    up10 = crossUp(f, t, dt, ia, i, Fdia + 0.1*A);
    up50 = crossUp(f, t, dt, ia, i, Fdia + 0.5*A);
    up90 = crossUp(f, t, dt, ia, i, Fdia + 0.9*A);
    V(q,ix.amplitude) = A;
    V(q,ix.diastolicSignal) = Fdia;
    V(q,ix.diastolicForce) = Fdia - zeroAt(zeroT, zeroV, t(ia));
    V(q,ix.dFdtMax) = max(g(ia:i));
    V(q,ix.riseTime10_90) = up90 - up10;
    V(q,ix.TTP90) = t(i) - up10;
    if ib < N && Fpk > Fpost     %relaxation within the data
        R = Fpk - Fpost;
        rel50 = crossDown(f, t, dt, i, ib, Fpost + 0.5*R);
        [rel90, j90] = crossDown(f, t, dt, i, ib, Fpost + 0.1*R);
        V(q,ix.dFdtMin) = min(g(i:ib));
        rockerMoving(q) = any(S.rockerOn(ia:j90));   %rocker state from F_dia to 90 % relaxation
        V(q,ix.TTR50) = rel50 - t(i);
        V(q,ix.TTR90) = rel90 - t(i);
        V(q,ix.CD50) = rel50 - up50;
        V(q,ix.CD90) = rel90 - up10;
        % AUC: trapezoid of (F - F_dia) from the 10 % crossing (upstroke) to the 90 % relaxation crossing
        i10 = find(f(ia:i-1) < Fdia + 0.1*A, 1, 'last') + ia;     %first sample above the 10 % level
        tt = [up10, t(i10:j90-1), rel90];
        yy = [0.1*A, f(i10:j90-1) - Fdia, Fpost + 0.1*R - Fdia];
        V(q,ix.AUC) = trapz(tt, yy);
    end
end
V(:,ix.peakToPeakFrequency) = 1 ./ V(:,ix.peakToPeakInterval);
% set stimulation interval (2026-10-05): stimulus of the contraction (extra contraction: last stimulus before the peak)
% minus the previous stimulus pulse of the channel
for q = 1:n
    tRef = tStimOfBeat(sel(q));
    if isnan(tRef), tRef = tPk(sel(q)); end
    j = find(ST <= tRef + 1e-9, 1, 'last');
    if ~isempty(j) && j >= 2, V(q,ix.stimInterval) = ST(j) - ST(j-1); end
end
V(:,ix.stimFrequency) = 1 ./ V(:,ix.stimInterval);

% ------------------------------------------------------------------ table
col = @(x) reshape(x, [], 1);   %column vectors also for n = 0 / 1
beatType = col(beatType(sel));
tStim = col(tStimOfBeat(sel));
tPeakSel = col(tPk(sel));
promSel = col(promPk(sel));
uncertain = col(~certain(sel));
included = ~isnan(V(:,1));
if strcmp(opts.beats, 'stimulated'), included = included & strcmp(beatType, 'stimulated'); end
if strcmp(opts.rocker, 'stopped'),   included = included & ~rockerMoving; end
if strcmp(opts.rocker, 'moving'),    included = included & rockerMoving; end

B = table(repmat(channel, n, 1), (1:n)', tPeakSel, beatType, tStim, tPeakSel - tStim, rockerMoving, included, ...
    uncertain, 'VariableNames', {'channel','contraction','t_peak','beatType','t_stim','stimToPeak','rockerMoving', ...
    'included','uncertain'});
B = [B, array2table(V, 'VariableNames', names), table(promSel, 'VariableNames', {'prominence'})];
B.Properties.VariableUnits = [{'','','s','','s','s','','',''}, PI(:,2)', {'uN'}];
if opts.rockerFilter        %contraction during a rocker movement whose artifact was subtracted
    art = S.rockerArtifact(row, :);
    B.rockerCorrected = rockerMoving & col(art(iPk(sel)) ~= 0);
end

C.channel = channel;
C.stimChannel = stimCh;
C.t = t;
C.f = f;
C.iPeaks = iPk;
C.peakTimes = tPk;
C.threshold = thr;
C.thresholdMode = thrMode;
C.typicalAmplitude = typAmp;
C.thresholdArtifacts = nArt;
C.noContractions = noBeats;
C.noiseLevel = noiseLvl;
C.noiseMedian = noiseMed;
C.stimCapturedCertain = stimCapturedCertain;
C.stimTimes = ST(:);
C.stimCaptured = stimCaptured;
C.stimInterval = CL;
C.maxStimToPeak = maxLat;
C.range = range;
C.zeroForce = zeroAt(zeroT, zeroV, mean(range));
C.zeroSource = zeroSource;
C.rockerFilter = RF;                 %[] = not applied; otherwise result of mda_rockerFilter
C.rockerArtifact = [];
if opts.rockerFilter, C.rockerArtifact = S.rockerArtifact(row, :); end   %subtracted artifact (uN, at C.t)
% comparison with a reference beat of this channel (option referenceBeat; otherwise the columns stay NaN)
C.referenceBeat = [];
refs = opts.referenceBeat;
if ~isempty(refs) && isfield(refs, 'channel') && n > 0
    refs = refs([refs.channel] == channel);       %a reference applies to its own channel (field channel)
    if ~isempty(refs)
        Vr = mda_referenceBeat('compare', C, B, refs(1));
        for nm = Vr.Properties.VariableNames, B.(nm{1}) = Vr.(nm{1}); end
        C.referenceBeat = mda_referenceBeat('align', refs(1), '');   %standard fields (also older references)
    end
end
% 2026-10-06: every parameter relative to the reference (<parameter>_pctRef, diastolic: _dRef). Added whenever the
% option referenceBeat is set (NaN for channels without own reference), so that tables of all channels match
if ~isempty(opts.referenceBeat)
    B = [B, mda_referenceBeat('relative', B, C.referenceBeat)];
end
end


function z = zeroAt(zeroT, zeroV, t)
% value of the step function at time t (before the first entry: the first entry)
k = find(zeroT <= t, 1, 'last');
if isempty(k), k = 1; end
z = zeroV(k);
end


% =====================================================================================================
function [f, t] = filterSignal(x, t, dt, opts)
% moving median + moving mean (windows in ms). An even window is centred half a sample before the current
% sample, i.e. delays the signal by dt/2: the time axis is corrected accordingly.
f = x;
nMed = round(opts.medianFilterMs / 1000 / dt);
nMean = round(opts.meanFilterMs / 1000 / dt);
delay = 0;
if nMed > 1
    f = movmedian(f, nMed, 'omitnan', 'Endpoints', 'shrink');
    if mod(nMed, 2) == 0, delay = delay + dt/2; end
end
if nMean > 1
    f = movmean(f, nMean, 'omitnan', 'Endpoints', 'shrink');
    if mod(nMean, 2) == 0, delay = delay + dt/2; end
end
t = t - delay;
end


function [thr, keepLow, nLow] = artifactGapThreshold(tc, prom, thr, typical, ST, rocker, CL)
% Paced channels: small peaks between the contractions (rocker artifacts while the rocker moves) can pass the auto
% threshold (relThreshold x typical). The prominences >= thr are sorted; if the largest ratio between two consecutive
% values below the typical amplitude is >= 1.6, the lower cluster (all <= 0.5 x typical) has >= 3 peaks that are not
% locked to the stimuli (latency to the previous stimulus not within +-0.1 s of the median latency of the upper
% cluster), at most chance level + 0.2 of the lower cluster is locked and >= 75 % of it occurs while the rocker moves,
% the threshold is raised to the geometric mean of the two prominences at the gap. Peaks of the lower cluster that are
% locked to a stimulus stay (keepLow; small stimulated contractions: alternans, partial capture). nLow: number of
% removed peaks. TS 2026-10-09
keepLow = false(size(prom));
nLow = 0;
k = find(prom >= thr);
if numel(k) < 6 || isnan(typical) || isempty(ST), return; end
[p, o] = sort(prom(k), 'descend');
k = k(o);
r = p(1:end-1) ./ p(2:end);
r(p(1:end-1) > typical | p(2:end) > 0.5 * typical) = 0;    %gap below the bulk, lower cluster <= 0.5 x typical
[rMax, g] = max(r);
if rMax < 1.6, return; end
hi = k(1:g); lo = k(g+1:end);
latHi = median(stimLatency(tc(hi), ST), 'omitnan');
if isnan(latHi), return; end
locked = abs(stimLatency(tc(lo), ST) - latHi) <= 0.1;
chance = 0.2 / max(CL, 0.2);                                %fraction locked by chance (window 0.2 s per cycle)
if nnz(~locked) < 3 || mean(locked) > min(0.6, chance + 0.2) || mean(rocker(lo)) < 0.75, return; end
thr = sqrt(p(g) * p(g+1));
keepLow(lo(locked)) = true;
nLow = nnz(~locked);
end


function [N, n, Nm] = preStimulusNoise(t, f, ST)
% rocker / noise level: rise (maximum minus the running minimum) of the filtered signal in the window before every
% stimulus that follows an interval >= 0.9 s (window min(0.5 s, 0.4 x interval), where no contraction is expected; a
% relaxation that is not finished only falls and does not count). N = 90th percentile, n = number of windows,
% Nm = median (robust against contractions that reach into some of the windows).
% Approach of GetBeatByBeatParameters (noise before the stimuli). TS 2026-10-09
r = nan(numel(ST), 1);
for j = 2:numel(ST)
    ci = ST(j) - ST(j-1);
    if ci < 0.9, continue; end
    i1 = firstAtLeast(t, ST(j) - min(0.5, 0.4 * ci));
    i2 = firstAtLeast(t, ST(j)) - 1;                       %last sample before the stimulus
    if i2 - i1 < 2, continue; end
    s = f(i1:i2);
    r(j) = max(s - cummin(s));
end
N = mprctile(r, 90);
n = nnz(~isnan(r));
Nm = mprctile(r, 50);
end


function i = firstAtLeast(t, x)
% first index with t(i) >= x (t increasing, uniform); numel(t) + 1 if none
n = numel(t);
i = min(max(1, floor((x - t(1)) / (t(2) - t(1)))), n);
while i > 1 && t(i-1) >= x, i = i - 1; end
while i <= n && t(i) < x, i = i + 1; end
end


function [drop, none] = rockerNoiseRule(tc, prom, thr, keepLow, typical, ST, N, rocker, tOn, fR)
% Latency of the contractions: centre of the 0.2-s window that contains the most latencies (time since the previous
% stimulus) of the largest peaks (as many as stimuli); peaks within +-0.1 s of it are locked to the stimuli.
% Peaks at the rhythm of the rocker (fR = rocker frequency, tOn = time with the rocker moving): see rockerRhythm.
% (< 50 % of the largest peaks locked and (typical amplitude <= 50 uN or (typical <= 2 x N and the peaks at the rhythm
% of the rocker))) or else rockerOnly (N unknown, high rates: >= 60 % of the peak intervals 1 or 1/2 rocker period
% +-10 %, the median no 1:1 or 2:1 multiple of the stimulus interval +-5 %, < max(50 %, chance + 20 %) locked within
% +-min(0.1 s, 0.2 x stimulus interval)): rocker / noise peaks - all peaks < 3 x max(typical, N) (rockerOnly: median
% of the largest peaks, only while the rocker moves) are dropped, except locked peaks
% >= max(1.5 x N, N + 50 uN) (N = typical if unknown) if there are >= max(3, 5 % of the stimuli) of them and more of
% these large peaks are locked than by chance (> min(0.6, chance + 0.2), as artifactGapThreshold) (contractions of
% only some stimuli); larger peaks are no rocker artifacts and stay; none = no peak left (slice not beating).
% Otherwise peaks not locked with a prominence < min(1.5 x N, 0.5 x typical) are dropped, < min(1.5 x N, typical) if
% the peaks not locked are at the rhythm of the rocker (N = rocker / noise level before the stimuli; NaN = unknown).
% TS 2026-10-09
above = prom >= thr | keepLow;
drop = false(size(prom));
none = false;
k = find(above);
if numel(k) < 3, return; end
[~, o] = sort(prom(k), 'descend');
top = k(o(1:min(numel(k), numel(ST))));
lat = stimLatency(tc, ST);
l = sort(lat(top));
l = l(~isnan(l));
if isempty(l), return; end
locked = latencyLock(lat, top, 0.1);
chance = 0.2 / max(median(diff(ST)), 0.2);                 %fraction of the time within +-0.1 s of the latency
% N unknown (high rates, no intervals >= 0.9 s): peaks at the rhythm of the rocker, not of the stimuli. +-0.1 s covers
% most of a short stimulus interval: locking here within +-hw, hw = min(0.1 s, 0.2 x median interval)
noise = mean(locked(top)) < 0.5 && ...
    (typical <= 50 || (typical <= 2 * N && rockerRhythm(tc, above & rocker, tOn, fR, 0.7)));
rockerOnly = false;
if ~noise && isnan(N) && ~isnan(fR)
    d = diff(tc(above & rocker)) * fR;                     %peak intervals in rocker periods
    atR = abs(d - 1) <= 0.1 | abs(d - 0.5) <= 0.05;
    CLm = median(diff(ST));
    ipi = median(d) / fR;
    k = round(ipi / CLm);                                  %1:1 or 2:1 capture at the rocker period: undecidable
    if numel(d) >= 10 && mean(atR) >= 0.6 && ~(k >= 1 && k <= 2 && abs(ipi - k * CLm) <= 0.05 * ipi)
        hw = min(0.1, 0.2 * CLm);
        lockedR = latencyLock(lat, top, hw);
        chanceR = 2 * hw / max(CLm, 2 * hw);
        if mean(lockedR(top)) < max(0.5, chanceR + 0.2)
            rockerOnly = true;
            locked = lockedR;
            chance = chanceR;
        end
    end
end
if noise || rockerOnly
    Nn = N;
    if isnan(Nn), Nn = typical; end
    big = above & prom >= max(1.5 * Nn, Nn + 50);          %>= 50 uN above the rocker / noise level
    lk = big & locked;                                     %contractions of some stimuli (partial capture)
    if nnz(lk) < max(3, 0.05 * numel(ST)) || nnz(lk) <= min(0.6, chance + 0.2) * nnz(big)
        lk(:) = false;                                     %not more than by chance
    end
    L = max(typical, N);                                   %max ignores NaN
    if rockerOnly, L = median(prom(top)); end              %size of the rocker peaks (typical: of more peaks than exist)
    drop = above & prom < 3 * L & ~lk;
    if rockerOnly, drop = drop & rocker; end               %peaks while the rocker is at rest are no rocker peaks
    none = ~any(above & ~drop);
    return;
end
if ~isnan(N)
    lim = min(1.5 * N, 0.5 * typical);
    if rockerRhythm(tc, above & ~locked & rocker, tOn, fR, 0.5), lim = min(1.5 * N, typical); end
    drop = above & ~locked & prom < lim;
end
end


function r = rockerRhythm(tc, sel, tOn, fR, minPerCycle)
% peaks sel at the rhythm of the rocker: minPerCycle ... 2.2 peaks per rocker cycle (tOn = time with the rocker
% moving) or a median interval of 1 or 1/2 rocker period (+-15 %); false if the rocker frequency fR is unknown
perCycle = nnz(sel) / max(tOn, eps) / fR;
ipi = median(diff(tc(sel))) * fR;
r = (perCycle >= minPerCycle && perCycle <= 2.2) || abs(ipi - 1) <= 0.15 || abs(ipi - 0.5) <= 0.075;
end


function fR = rockerFrequency(S, opts)
% rocker frequency (Hz) of the data: opts.rockerFrequency (one value in Hz, or [rpm f0] rows of mda_rockerFilter:
% the row of the logged speed, a single row otherwise) or the last logged rocker speed > 0 before the middle of the
% data (otherwise the first one) x 0.0202 Hz/rpm (as mda_rockerFilter); NaN if unknown
fR = nan;
g = opts.rockerFrequency;
if isnumeric(g) && isscalar(g) && g > 0
    fR = g;
    return;
end
rpm = nan;
if isfield(S, 'rockerSpeedLog') && ~isempty(S.rockerSpeedLog)
    L = S.rockerSpeedLog;
    j = find(L(:,1) <= (S.fromSeconds + S.toSeconds) / 2 & L(:,2) > 0, 1, 'last');
    if isempty(j), j = find(L(:,2) > 0, 1); end
    if ~isempty(j), rpm = L(j,2); end
end
if isnumeric(g) && size(g, 2) == 2 && ~isempty(g)
    j = find(g(:,1) == rpm, 1);
    if isempty(j) && size(g, 1) == 1, j = 1; end
    if ~isempty(j) && g(j,2) > 0, fR = g(j,2); return; end
end
if ~isnan(rpm), fR = 0.0202 * rpm; end
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


function locked = latencyLock(lat, top, hw)
% peaks locked to the stimuli: latency (time since the previous stimulus) within +-hw of the centre of the window of
% 2 x hw that contains the most latencies of the reference peaks top (indices, e.g. the largest peaks)
locked = false(size(lat));
l = sort(lat(top));
l = l(~isnan(l));
if isempty(l), return; end
best = 0; latRef = nan;
for i = 1:numel(l)
    c = nnz(l >= l(i) & l <= l(i) + 2 * hw);
    if c > best, best = c; latRef = l(i) + hw; end
end
locked = abs(lat - latRef) <= hw;
end


function lat = stimLatency(tt, ST)
% time since the previous stimulus (NaN before the first one)
lat = nan(size(tt));
for q = 1:numel(tt)
    j = find(ST <= tt(q), 1, 'last');
    if ~isempty(j), lat(q) = tt(q) - ST(j); end
end
end


function [thr, typical] = autoThreshold(prom, nStim, opts)
% threshold = relThreshold x typical contraction amplitude, at least minThreshold.
% Typical amplitude (median prominence of the contractions):
%   paced (>= 3 stimuli in the data): median of the nStim largest prominences, i.e. of the responses to the
%       stimuli as long as more than half of the stimuli are followed by a contraction. Robust against many
%       intermediate maxima (e.g. rocker artifacts while the rocker moves), which may outnumber the contractions.
%   unpaced: the largest ratio between two consecutive prominences (sorted, >= minThreshold) separates the
%       contractions (above) from noise / artifacts (below); median of the prominences above the gap.
typical = nan;
p = sort(prom(prom > 0), 'descend');
if nStim >= 3
    typical = median(p(1:min(numel(p), nStim)));
else
    p = p(p >= opts.minThreshold);
    if numel(p) >= 3
        ratio = p(1:end-1) ./ p(2:end);
        ratio(1) = 0;                   %at least 2 contractions above the gap (a single artifact is no cluster)
        [~, k] = max(ratio);
        typical = median(p(1:k));
    elseif ~isempty(p)
        typical = median(p);
    end
end
thr = max(opts.minThreshold, opts.relThreshold * typical);   %max ignores NaN
end


function tc = crossUp(f, t, dt, ia, i, level)
% last crossing of level from below between the minimum (ia) and the peak (i), linear interpolation
j = find(f(ia:i-1) < level, 1, 'last') + ia - 1;
if isempty(j) || f(j+1) == f(j)
    tc = nan;
    return;
end
tc = t(j) + (level - f(j)) / (f(j+1) - f(j)) * dt;
end


function [tc, j] = crossDown(f, t, dt, i, ib, level)
% first crossing of level from above between the peak (i) and the minimum after the peak (ib)
j = find(f(i+1:ib) < level, 1, 'first') + i;
if isempty(j)
    tc = nan;
    j = ib;
    return;
end
tc = t(j-1) + (f(j-1) - level) / (f(j-1) - f(j)) * dt;
end
