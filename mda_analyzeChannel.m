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
%   B  table, one row per contraction (see below); stimulus columns: t_stim, stimToPeak, t_onset, stimToOnset,
%      stimPulse (ID = raw sample number of the eliciting pulse), stimCurrent (mA), stimChargeDuration,
%      stimPauseDuration, stimDechargeDuration (us, log file), elicitedByExtraPulse, stimAmbiguous, prePulses,
%      postPulses (see 3.)
%   C  struct: filtered signal (t, f), detection threshold, regular stimulus pulses of the channel (stimTimes),
%      whether each was followed by a contraction (stimCaptured) or fell into a contraction elicited by another pulse
%      (stimDuringContraction), extra pulses (extraTimes, extraElicited), onsets of all peaks (onsetTimes), table of
%      the pulses of the range (pulses; option pulseTable, see pulseTable below), the stimulus channel used (stimChannel;
%      0 = external trigger pulses, option 'externalTrigger'), all peaks in S (iPeaks); with the option
%      'rockerFilter': result of mda_rockerFilter (rockerFilter) and the subtracted artifact (rockerArtifact);
%      referenceBeat: the reference used for the columns refCorrelation, refRMSDeviation..., refMaxDeviation... ([] = none)
%   With the option referenceBeat, B also contains every parameter relative to the reference: <parameter>_pctRef
%   (% of the mean of the reference contractions), diastolicForce_dRef / diastolicSignal_dRef (difference, uN)
%
% PROCESSING (the numbers are the defaults of the advanced settings, see mda_options; 2026-10-10)
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
%   3. stimulus assignment (option stimAssignment, default 'onset', 2026-10-10): every pulse of the channel, regular
%      or extra pulse (status channel bit 16: pre-pulses, CCM pulses, ...), is a candidate. Contraction onset =
%      the tangent at the maximum dF/dt between the diastolic minimum and the peak, crossing the diastolic level.
%      A pulse can only have elicited a contraction if it lies in the gate onset - gateMax ... onset +
%      gateTolerance (0.15 s / 0.015 s): the delay from the pulse to the onset is short and stable across species
%      and pacing rates (~5-80 ms; peak: ~50-280 ms). Contractions in the order of their prominence, every pulse
%      elicits at most one contraction; several candidates: pulses before the onset before pulses after it, regular
%      pulses before extra pulses, of one kind the earliest within gateCore (0.06 s) before the onset, otherwise the
%      latest. No pulse in the gate: the onsets of the other rise phases of the upstroke (local maxima of dF/dt >= 25 %
%      of the maximum: rocker movement, a spontaneous event fused with the contraction) are tried, the earliest first,
%      then a pulse up to 5 ms before the maximum dF/dt. Column stimAmbiguous: a pulse of the other kind within
%      ambiguityWindow (0.01 s) of the chosen one or chosen with the onset gateTolerance earlier or later, a later
%      rise phase (the upstroke started before) or the pulse after the gate. 'stimulated' = a pulse in the gate
%      (elicitedByExtraPulse: an extra pulse), 'extra' = none, 'unpaced' = channel without pulses. Missed beats =
%      regular pulses that elicited no contraction (C.stimDuringContraction: they fell into a contraction elicited
%      by another pulse). Pulses that elicited no contraction are kept with a contraction: post-pulses from its
%      eliciting pulse to 90 % relaxation, pre-pulses up to prePulseWindow (1 s) before its eliciting pulse (columns
%      prePulses / postPulses: 't<ms>|<mA>|<charge us>|<pause us>|<decharge us>', several joined by '&'; time
%      relative to the eliciting pulse, the programmed offset of the log file if within 5 ms). 'peak' (versions
%      <= 1.0.0-beta.3): a contraction is 'stimulated' if its peak follows a pulse of the channel by
%      minStimToPeak ... maxStimToPeak (and is the most prominent peak after this pulse); extra pulses count as
%      regular pulses.
%   4. parameters, per contraction, between the previous and the next peak (at most maxBeatWindow s):
%      diastolic level F_dia (option diastolicLevel, 2026-10-10): median of the unfiltered signal 60 ... 5 ms
%      (diastoleWindowStart ... diastoleWindowEnd) before the eliciting pulse; contractions without pulse, or a median
%      at or above the peak: the last minimum of the filtered signal before the peak ('minimum', versions <=
%      1.0.0-beta.3). Minimum after the peak: F_min,post. After a stimulation pause (stimulus interval >= 2.5 s and >=
%      1.5 x the interval before) the minimum before the peak is searched only from pauseDiastoleWindow (0.5 s) before
%      the stimulus (mda_options).
%        amplitude       F_peak - F_dia                                                [uN]
%        diastolicForce  F_dia - zero force (zero = 'Offset' of the channel in the log file or 'zeroForce') [uN]
%        diastolicSignal F_dia (sensor signal)                                           [uN]
%        dFdtMax         maximum of dF/dt between the minimum before the peak and the peak [uN/s]
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
% TS 2026-10-05 (rocker artifacts, certainty of contractions 2026-10-09; onset gate, extra pulses, pulse table,
% diastolic level before the pulse 2026-10-10)

if nargin < 3, range = []; end
if nargin < 4 || isempty(opts), opts = mda_options(); end
if ~isfield(opts, 'rockerFilter') || ~isfield(opts, 'referenceBeat') || ~isfield(opts, 'pauseDiastoleWindow') || ...
        ~isfield(opts, 'lockWindow') || ~isfield(opts, 'diastolicLevel')
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
% pulses of the channel: regular pulses (ST) and extra pulses (status channel bit 16: pre-pulses, CCM pulses, ...;
% 2026-10-10). Option stimAssignment 'peak' (versions <= 1.0.0-beta.3): extra pulses count as regular pulses.
legacy = isfield(opts, 'stimAssignment') && strcmp(opts.stimAssignment, 'peak');
selP = S.stim.channel(:) == stimCh;
PT = S.stim.time(selP); PT = PT(:);
PX = false(size(PT));
if stimCh > 0 && isfield(S.stim, 'isExtraPulse') && ~legacy
    x = S.stim.isExtraPulse(:); PX = x(selP);
end
PC = nan(size(PT)); PR = true(size(PT));           %current (mA) and current reached (status channel)
if isfield(S.stim, 'current'), x = S.stim.current(:); PC = x(selP); end
if isfield(S.stim, 'currentReached'), x = S.stim.currentReached(:); PR = x(selP); end
[PT, o] = sort(PT); PX = PX(o); PC = PC(o); PR = PR(o);
STall = PT;                                         %all pulses (latency of the peaks: locked to any pulse)
ST = PT(~PX);                                       %regular pulses (counts, intervals, missed beats)
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
    if numel(ST) >= opts.pacedMinStimuli            %paced: rocker / noise level before the stimuli
        [noiseLvl, nNoise, noiseMed] = preStimulusNoise(t, f, ST, opts);
        if nNoise < opts.noiseMinWindows, noiseLvl = nan; noiseMed = nan; end
    end
    if (~isfield(opts, 'rockerArtifacts') || opts.rockerArtifacts) && numel(ST) >= opts.pacedMinStimuli   %rocker artifacts
        [thr, keepLow, nArt] = artifactGapThreshold(t(cand), prom, thr, typAmp, STall, S.rockerOn(cand), CL, opts);
        if mean(S.rockerOn) >= opts.rockerRuleMinFraction
            fR = rockerFrequency(S, opts);
            [drop, noBeats] = rockerNoiseRule(t(cand), prom, thr, keepLow, typAmp, ST, noiseLvl, ...
                S.rockerOn(cand), nnz(S.rockerOn) * dt, fR, STall, opts);
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
    if numel(ST) >= opts.pacedMinStimuli
        [~, o] = sort(promPk, 'descend');
        top = o(1:min(numel(o), numel(ST)));
        typC = median(promPk(top));
        lat = stimLatency(t(iPk), STall);
        ci = nan(size(top));                               %stimulus interval before the largest contractions
        for q = 1:numel(top)
            j = find(ST <= t(iPk(top(q))), 1, 'last');
            if ~isempty(j) && j >= 2, ci(q) = ST(j) - ST(j-1); end
        end
        hw = min(opts.lockWindow, opts.lockWindowRel * median(ci, 'omitnan'));
        if isnan(hw), hw = opts.lockWindow; end
        lk = latencyLock(lat, top, hw);
        certain = (lk & ~(promPk < opts.certainNoiseRel * noiseMed)) | ...
            ~(promPk < max(opts.certainLargeRel * typC, opts.certainLargeNoiseRel * noiseMed));  %NaN: no limit
    elseif ~isnan(typAmp)
        certain = promPk >= opts.certainUnpacedRel * typAmp;
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
% onset of every contraction: tangent at the maximum dF/dt between the diastolic minimum and the peak, crossing the
% diastolic level (NaN without upstroke in the data); end of the contraction: 90 % relaxation (2026-10-10)
maxW = round(opts.maxBeatWindow / dt);
[tOn, tEnd, tMs, tSeg] = onsetAndEnd(f, t, g, dt, iPk, maxW, opts);
beatType = repmat({'unpaced'}, nPk, 1);
pOfBeat = zeros(nPk, 1);                             %eliciting pulse (index into PT; 0 = none)
jAll = zeros(nPk, 1);                                %'peak': pulse of every peak (also the less prominent ones)
amb = false(nPk, 1);                                 %assignment ambiguous (option ambiguityWindow)
if ~isempty(PT)
    beatType(:) = {'extra'};
    if legacy                                        %peak: last pulse minStimToPeak ... maxLat before the peak
        j = zeros(nPk, 1);
        for k = 1:nPk
            jj = find(PT <= tPk(k) - opts.minStimToPeak, 1, 'last');
            if ~isempty(jj) && tPk(k) - PT(jj) <= maxLat
                j(k) = jj;
            end
        end
        for jj = unique(j(j > 0))'
            ks = find(j == jj);
            [~, best] = max(promPk(ks));      %several peaks after one stimulus: the most prominent one
            pOfBeat(ks(best)) = jj;
        end
        jAll = j;
    else
        [pOfBeat, amb, tOn] = gateAssign(tOn, tMs, tPk, promPk, PT, PX, opts, maxLat, tSeg);
        jAll = pOfBeat;
    end
    beatType(pOfBeat > 0) = {'stimulated'};
end
tStimOfBeat = nan(nPk, 1);
tStimOfBeat(pOfBeat > 0) = PT(pOfBeat(pOfBeat > 0));
elicitedX = false(nPk, 1);
elicitedX(pOfBeat > 0) = PX(pOfBeat(pOfBeat > 0));
% regular pulses: followed by a contraction (captured), by a certain one, or within a contraction elicited by
% another pulse (from its eliciting pulse to 90 % relaxation: refractory, not captured)
regIdx = cumsum(~PX); regIdx(PX) = 0;                %index into ST of every regular pulse
pUsed = false(size(PT)); pUsedCertain = false(size(PT));
pUsed(pOfBeat(pOfBeat > 0)) = true;
for jj = unique(pOfBeat(pOfBeat > 0))'              %several peaks after one pulse ('peak'): any certain one
    pUsedCertain(jj) = any(certain(jAll == jj));    %captured in the 'specific' mode, too
end
stimCaptured = pUsed(~PX);
stimCapturedCertain = pUsedCertain(~PX);
wStart = tStimOfBeat; wStart(isnan(wStart)) = tOn(isnan(wStart));
[owner, during] = pulseOwners(PT, pOfBeat, wStart, tEnd, tStimOfBeat, tOn, opts);
stimDuring = during(~PX);
jStimOfBeat = zeros(nPk, 1);                         %regular pulse of the contraction (index into ST)
jStimOfBeat(pOfBeat > 0) = regIdx(pOfBeat(pOfBeat > 0));
% contractions after a stimulation pause (stimulus interval >= 2.5 s and >= 1.5 x the interval before; without a
% previous stimulus in the data: time since the start of the data; without the interval before: median interval):
% F_dia is searched only from opts.pauseDiastoleWindow before the stimulus, not during the pause (drift, rocker
% movement until shortly before the stimulus, e.g. post-rest potentiation protocols)
afterPause = false(nPk, 1);
for k = find(jStimOfBeat > 0)'
    jj = jStimOfBeat(k);
    if jj >= 2, prevInt = ST(jj) - ST(jj-1); else, prevInt = ST(jj) - t(1); end
    if jj >= 3, before = ST(jj-1) - ST(jj-2); else, before = CL; end
    afterPause(k) = prevInt >= max(opts.pauseMinInterval, opts.pauseIntervalRatio * before);
end

% ------------------------------------------------------------------ zero force (sensor signal without load)
% 'Offset' entries of the log file (one per channel, written at the start of a recording; 0 = not calibrated) or
% opts.zeroForce. Scaled like the data in extended sensor mode.
[~, zeroSource, zeroT, zeroV] = mda_zeroForce(S, channel, opts.zeroForce);

% ------------------------------------------------------------------ parameters
sel = find(tPk >= range(1) & tPk <= range(2));
n = numel(sel);
useMedian = ~strcmp(opts.diastolicLevel, 'minimum');   %diastolic level: median before the pulse (2026-10-10)
xRaw = S.force(row,:); tRaw = S.t(:)';                %unfiltered signal (after spike removal / rocker filter)
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
    iu = ia;                                       %start of the search for the upstroke crossings
    % diastolic level (2026-10-10): median of the unfiltered signal diastoleWindowStart ... diastoleWindowEnd before the
    % eliciting pulse (default); without pulse, or a median at or above the peak: the minimum before the peak
    if useMedian && ~isnan(tStimOfBeat(k))
        w0 = lowerBound(tRaw, tStimOfBeat(k) - opts.diastoleWindowStart - 1e-9);
        w1 = lowerBound(tRaw, tStimOfBeat(k) - opts.diastoleWindowEnd + 1e-9) - 1;
        if w0 >= 1 && w1 >= w0 && w1 <= numel(xRaw)
            Fm = median(xRaw(w0:w1), 'omitnan');
            if Fm < Fpk
                Fdia = Fm;
                %upstroke crossings: from the window before the pulse on (a median below the filtered minimum)
                iu = min(ia, max(a, lowerBound(t, tStimOfBeat(k) - opts.diastoleWindowStart)));
            end
        end
    end
    A = Fpk - Fdia;
    if k > 1, V(q,ix.peakToPeakInterval) = tPk(k) - tPk(k-1); end
    rockerMoving(q) = any(S.rockerOn(ia:ib));   %replaced below by F_dia ... 90 % relaxation, if available
    % no upstroke within the data (contraction starts before the loaded data), or a rounding bump of a held value
    % (e.g. chamber out: plateau above the diastolic level, A ~ 1e-13 uN)
    if ~(A > 1e-9 * max(1, abs(Fdia))) || ia == 1
        continue;
    end
    up10 = crossUp(f, t, dt, iu, i, Fdia + 0.1*A);
    up50 = crossUp(f, t, dt, iu, i, Fdia + 0.5*A);
    up90 = crossUp(f, t, dt, iu, i, Fdia + 0.9*A);
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
        i10 = find(f(iu:i-1) < Fdia + 0.1*A, 1, 'last') + iu;     %first sample above the 10 % level
        if ~isempty(i10)
            tt = [up10, t(i10:j90-1), rel90];
            yy = [0.1*A, f(i10:j90-1) - Fdia, Fpost + 0.1*R - Fdia];
            V(q,ix.AUC) = trapz(tt, yy);
        end
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
% eliciting pulse and the pulses that did not elicit a contraction (2026-10-10, see pulseProperties / pulseText)
if isfield(S, 'samplingRate'), fs = S.samplingRate; else, fs = 2 / dt; end   %pulse ID = raw sample number
snapMs = opts.offsetSnap * 1000;                    %programmed offsets (log file) used within this time (ms)
[pDur, ~, pNom] = pulseProperties(S, stimCh, PT, PX, snapMs);
pSel = col(pOfBeat(sel));
hasP = pSel > 0;
sv = nan(n, 5);                                     %pulse ID, current, charge, pause, decharge
sv(hasP, :) = [round(PT(pSel(hasP)) * fs), PC(pSel(hasP)), pDur(pSel(hasP), :)];
[preTxt, postTxt] = pulseText(sel, owner, PT, PX, PC, pDur, pNom, pOfBeat, tOn, n, snapMs, opts.pulseTextMax);
B = [B, table(col(tOn(sel)), col(tOn(sel)) - tStim, sv(:,1), sv(:,2), sv(:,3), sv(:,4), sv(:,5), ...
    col(elicitedX(sel)), col(amb(sel)), preTxt, postTxt, 'VariableNames', {'t_onset', 'stimToOnset', 'stimPulse', ...
    'stimCurrent', 'stimChargeDuration', 'stimPauseDuration', 'stimDechargeDuration', 'elicitedByExtraPulse', ...
    'stimAmbiguous', 'prePulses', 'postPulses'})];
B = [B, array2table(V, 'VariableNames', names), table(promSel, 'VariableNames', {'prominence'})];
B.Properties.VariableUnits = [{'','','s','','s','s','','',''}, {'s','s','','mA','us','us','us','','','',''}, ...
    PI(:,2)', {'uN'}];
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
C.stimDuringContraction = stimDuring;   %regular pulse within a contraction elicited by another pulse (refractory)
C.extraTimes = PT(PX);                  %extra pulses (status channel bit 16)
C.extraElicited = pUsed(PX);            %extra pulse elicited a contraction
C.onsetTimes = tOn;                     %contraction onset of every peak (iPeaks)
C.stimAssignment = 'onset';
if legacy, C.stimAssignment = 'peak'; end
C.pulses = [];                          %pulse table of the range (option pulseTable; MyoDishAnalysis: info.pulses)
if ~isfield(opts, 'pulseTable') || opts.pulseTable
    C.pulses = pulseTable(channel, PT, PX, PC, PR, pDur, fs, range, pOfBeat, owner, during, tStimOfBeat, tOn, ...
        tEnd, tPk, sel, pNom, snapMs);
end
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


% =====================================================================================================
% stimulus assignment, pulses (2026-10-10)
function [tOn, tEnd, tMs, tSeg] = onsetAndEnd(f, t, g, dt, iPk, maxW, opts)
% onset of every contraction: the tangent at the maximum dF/dt between the diastolic minimum (last minimum before the
% peak, as for the parameters) and the peak crosses the diastolic level (limited to [t(minimum), t(max. dF/dt)]); NaN
% without upstroke in the data. tMs: time of the maximum dF/dt. End: opts.contractionEnd (90 %) relaxation (first
% crossing after the peak, as TTR90); without relaxation in the window: time of the minimum after the peak. tSeg: onsets of the other rise
% phases of the upstroke (cell, see phaseOnsets): the upstroke can rise in phases (rocker movement, an undetected event
% fused with the contraction, e.g. a spontaneous beat just before the stimulus)
N = numel(f); nPk = numel(iPk);
tOn = nan(nPk, 1); tEnd = nan(nPk, 1); tMs = nan(nPk, 1);
tSeg = repmat({zeros(0, 1)}, nPk, 1);
for k = 1:nPk
    i = iPk(k);
    if k > 1, a = iPk(k-1); else, a = 1; end
    if k < nPk, b = iPk(k+1); else, b = N; end
    a = max([a, i - maxW, 1]);
    b = min([b, i + maxW, N]);
    [Fdia, ia] = min(f(i:-1:a)); ia = i - ia + 1;
    if ia > 1 && ia < i
        [gm, im] = max(g(ia:i)); im = ia + im - 1;
        if gm > 0
            tOn(k) = min(max(t(im) - (f(im) - Fdia) / gm, t(ia)), t(im));
            tMs(k) = t(im);
            tSeg{k} = phaseOnsets(f, t, g, ia, i, im, opts.risePhaseLevel);
        end
    end
    [Fpost, ib] = min(f(i:b)); ib = i + ib - 1;
    if ib > i && f(i) > Fpost
        lvl = Fpost + (100 - opts.contractionEnd) / 100 * (f(i) - Fpost);
        j = find(f(i+1:ib) < lvl, 1, 'first') + i;
        if isempty(j)
            tEnd(k) = t(ib);
        else
            tEnd(k) = t(j-1) + (f(j-1) - lvl) / (f(j-1) - f(j)) * dt;
        end
    else
        tEnd(k) = t(i);
    end
end
end


function on = phaseOnsets(f, t, g, ia, i, im, level)
% onsets of the other rise phases of the upstroke between the diastolic minimum ia and the peak i (im = maximum dF/dt),
% in time order: every local maximum of dF/dt >= level (opts.risePhaseLevel, 25 %) x the maximum; foot of a phase = the bottom of the dip of F
% before it (dF/dt <= 0 in between) or the shoulder (minimum of dF/dt) after the previous phase, the diastolic minimum
% for the first phase; onset = the tangent at the local maximum of dF/dt crossing the level of the foot (limited to
% [t(foot), t(maximum)]). Indices relative to ia (1 = ia).
on = zeros(0, 1);
y = g(ia:i); x = f(ia:i);
y = y(:); x = x(:);
if numel(y) < 3, return; end
pk = find(y(2:end-1) > y(1:end-2) & y(2:end-1) >= y(3:end) & y(2:end-1) >= level * g(im)) + 1;
allPk = union(pk, im - ia + 1);
for p = reshape(pk, 1, [])
    if p == im - ia + 1, continue; end
    prev = allPk(allPk < p);
    if isempty(prev)
        foot = 1;
    else
        seg = y(prev(end):p);
        if min(seg) <= 0
            foot = prev(end) - 1 + find(seg <= 0, 1, 'last');   %bottom of the dip of F
        else
            [~, q] = min(seg); foot = prev(end) - 1 + q;        %shoulder
        end
    end
    on(end+1, 1) = min(max(t(ia + p - 1) - (x(p) - x(foot)) / y(p), t(ia + foot - 1)), t(ia + p - 1)); %#ok<AGROW>
end
end


function [p, amb, tOn] = gateAssign(tOn, tMs, tPk, promPk, PT, PX, opts, maxLat, tSeg)
% Onset gate: a pulse (regular or extra) can only have elicited a contraction if it lies from onset - gateMax to
% onset + gateTolerance. Contractions in the order of their prominence (the most prominent one first), each pulse
% elicits at most one contraction. Several candidates: see choosePulse (before the onset before after it, regular
% before extra pulses, the earliest within gateCore before the onset, otherwise the latest). Ambiguous: a pulse of the
% other kind (regular / extra) within ambiguityWindow of the chosen one, or one of the other kind would be chosen if
% the onset were gateTolerance earlier or later.
% No pulse in the gate: 1. the gates of the other rise phases of the upstroke (tSeg, earliest first), the first one
% with a pulse; its onset becomes the onset of the contraction (ambiguous if the upstroke started more than
% gateTolerance before it); 2. the eliciting pulse must precede the steepest upstroke - a pulse after the gate up to
% steepRiseMargin (5 ms) before the maximum dF/dt (onset estimated too early, e.g. rocker artifacts) is taken (regular first, the
% earliest), marked ambiguous. Contractions without onset (no upstroke in the data): the last unused pulse
% minStimToPeak ... maxLat before the peak.
if nargin < 9, tSeg = cell(numel(tOn), 1); end
nPk = numel(tOn);
p = zeros(nPk, 1); amb = false(nPk, 1);
used = false(numel(PT), 1);
[~, order] = sort(promPk, 'descend');
for k = reshape(order, 1, [])
    if isnan(tOn(k))
        j = find(PT <= tPk(k) - opts.minStimToPeak & ~used, 1, 'last');
        if ~isempty(j) && tPk(k) - PT(j) <= maxLat, p(k) = j; used(j) = true; end
        continue;
    end
    [cand, b] = gate(tOn(k));
    forced = false;
    if isempty(cand) && ~isempty(tSeg{k})
        first = min(tOn(k), min(tSeg{k}));               %start of the upstroke
        for ts = reshape(tSeg{k}, 1, [])
            c2 = gate(ts);
            if ~isempty(c2)
                cand = c2; tOn(k) = ts;
                forced = ts > first + opts.gateTolerance + 1e-9;   %the upstroke started before (fused event): ambiguous
                break;
            end
        end
    end
    if isempty(cand)
        c2 = lowerBound(PT, tMs(k) - opts.steepRiseMargin + 1e-9) - 1;
        cand = (b + 1:c2)';
        cand = cand(~used(cand));
        if isempty(cand), continue; end
        r = cand(~PX(cand));
        if ~isempty(r), j = r(1); else, j = cand(1); end
        p(k) = j; used(j) = true; amb(k) = true;
        continue;
    end
    j = choosePulse(cand, PT, PX, tOn(k), opts.gateCore);
    o = cand(cand ~= j);
    oth = o(PX(o) ~= PX(j));                             %candidates of the other kind (regular / extra)
    % ambiguous: a pulse of the other kind (regular / extra) within ambiguityWindow, or chosen if the onset were
    % gateTolerance earlier or later (tolerance of the onset estimate: gate and choice)
    amb(k) = forced || any(abs(PT(oth) - PT(j)) <= opts.ambiguityWindow + 1e-9);
    for t1 = tOn(k) + [-1 1] * opts.gateTolerance
        c1 = gate(t1);
        if ~amb(k) && ~isempty(c1) && PX(choosePulse(c1, PT, PX, t1, opts.gateCore)) ~= PX(j), amb(k) = true; end
    end
    p(k) = j;
    used(j) = true;
end
    function [c, b] = gate(t0)
        a = lowerBound(PT, t0 - opts.gateMax - 1e-9);
        b = lowerBound(PT, t0 + opts.gateTolerance + 1e-9) - 1;
        c = (a:b)';
        c = c(~used(c));
    end
end


function j = choosePulse(cand, PT, PX, t0, gCore)
% eliciting pulse among the candidates of a gate (onset t0): pulses before the onset before pulses after it (onset
% tolerance); among them regular pulses before extra pulses (an extra pulse after a regular one falls into its
% refractory period, e.g. CCM; a sub-threshold pre-pulse lies further before the onset than the regular pulse); of one
% kind the earliest within gateCore before the onset, otherwise the latest one. After the onset: the earliest (regular
% first).
B = cand(PT(cand) <= t0 + 1e-9);
if ~isempty(B)
    for q = {B(~PX(B)), B(PX(B))}
        if ~isempty(q{1})
            c = q{1}(PT(q{1}) >= t0 - gCore - 1e-9);
            if ~isempty(c), j = c(1); else, j = q{1}(end); end
            return;
        end
    end
end
r = cand(~PX(cand));
if ~isempty(r), j = r(1); else, j = cand(1); end
end


function i = lowerBound(x, v)
% first index of the sorted vector x with x(i) >= v (numel(x) + 1 if none); binary search
lo = 1; hi = numel(x) + 1;
while lo < hi
    mid = floor((lo + hi) / 2);
    if x(mid) < v, lo = mid + 1; else, hi = mid; end
end
i = lo;
end


function [owner, during] = pulseOwners(PT, pOfBeat, wStart, tEnd, tStim, tOn, opts)
% contraction of every pulse: owner(i,:) = [contraction index, role], role 3 = eliciting pulse, 2 = post-pulse (within
% a contraction, from its eliciting pulse (extra beat: onset) to 90 % relaxation; the one that started last), 1 =
% pre-pulse (before the eliciting pulse (onset) of the next contraction, at most prePulseWindow), 0 = none.
% during: within a contraction elicited by another pulse (not the eliciting pulse)
nP = numel(PT);
owner = zeros(nP, 2); during = false(nP, 1);
ok = find(~isnan(wStart));
[ws, o] = sort(wStart(ok)); kk = ok(o);
we = tEnd(kk); we(isnan(we)) = ws(isnan(we));
isEl = false(nP, 1);
for k = find(pOfBeat(:)' > 0)
    owner(pOfBeat(k), :) = [k, 3];
    isEl(pOfBeat(k)) = true;
end
for i = find(~isEl)'
    tp = PT(i);
    j = lowerBound(ws, tp + 1e-12) - 1;              %last window that starts at or before the pulse
    post = 0;
    for jj = [j, j - 1]
        if jj >= 1 && tp <= we(jj) + 1e-9, post = kk(jj); break; end
    end
    if post > 0
        owner(i, :) = [post, 2];
        during(i) = true;
        continue;
    end
    if j + 1 <= numel(kk)
        k = kk(j + 1);
        ref = tStim(k);
        if isnan(ref), ref = tOn(k); end
        if ref > tp && ref - tp <= opts.prePulseWindow + 1e-9, owner(i, :) = [k, 1]; end
    end
end
end


function [dur, kOf, dNom] = pulseProperties(S, c, PT, PX, snapMs)
% pulse durations (us; charge, pause, decharge: last 'chargeDuration' / 'pauseDuration' / 'dechargeDuration' entry of
% the log file at or before the pulse; regular pulses: log channel c (and 0); extra pulse #k: log channel 10k + c if
% such entries exist (software 2022), otherwise the values of channel c (software 2026)), number k of every extra
% pulse and its programmed offset to the regular pulse (dNom, ms: the offset of the 'Sequence' entries nearest to the
% measured one, if within snapMs (opts.offsetSnap, 5 ms); NaN otherwise). Measured offset: to the nearest regular pulse of the channel.
n = numel(PT);
dur = nan(n, 3); kOf = zeros(n, 1); dNom = nan(n, 1);
if n == 0, return; end
iX = find(PX(:));
kOf(iX) = 1;
X = zeros(0, 5);
if isfield(S, 'extraPulseLog') && ~isempty(S.extraPulseLog), X = S.extraPulseLog; end
TR = PT(~PX);
if ~isempty(iX) && ~isempty(X) && ~isempty(TR)
    Xc = X(X(:,2) == c, :);
    if ~isempty(Xc)
        [~, o] = sortrows(Xc(:, [1 5])); Xc = Xc(o, :);
        for i = iX'
            jr = lowerBound(TR, PT(i));
            cand = [jr - 1, jr]; cand = cand(cand >= 1 & cand <= numel(TR));
            [~, q] = min(abs(TR(cand) - PT(i)));
            dm = (PT(i) - TR(cand(q))) * 1000;
            L = lowerBound(Xc(:,1), PT(i) + 1e-9) - 1;  %latest entry at or before the pulse: its line = the set
            if L < 1, continue; end
            R = Xc(Xc(:,5) == Xc(L,5) & Xc(:,3) > 0, :);
            if isempty(R), continue; end
            [e, q] = min(abs(R(:,4) - dm));
            kOf(i) = R(q,3);
            if e <= snapMs, dNom(i) = R(q,4); end
        end
    end
end
P = zeros(0, 4);
if isfield(S, 'pulseSettingsLog') && ~isempty(S.pulseSettingsLog), P = S.pulseSettingsLog; end
if isempty(P), return; end
for code = 1:3
    dur(:, code) = logValue(P(ismember(P(:,2), [0 c]) & P(:,3) == code, :), PT);
    for k = reshape(unique(kOf(kOf > 0)), 1, [])
        Pk = P(P(:,2) == 10 * k + c & P(:,3) == code, :);
        if isempty(Pk), continue; end
        ii = find(kOf == k);
        v = logValue(Pk, PT(ii));
        keep = ~isnan(v);
        dur(ii(keep), code) = v(keep);
    end
end
end


function v = logValue(P, t)
% value of the last entry (rows [time ch code value], log order) at or before the times t (NaN before the first)
v = nan(size(t));
if isempty(P), return; end
[te, o] = sort(P(:,1));                            %stable: entries at the same time in log order
x = P(o, 4);
for i = 1:numel(t)
    j = lowerBound(te, t(i) + 1e-9) - 1;
    if j >= 1, v(i) = x(j); end
end
end


function tms = relPulseTime(i, k, PT, PX, pNom, pOfBeat, tOn, snapMs)
% time of pulse i relative to the eliciting pulse of contraction k (extra beat: its onset), ms; the programmed offset
% (log file) if the measured one is within snapMs of it (extra pulse relative to the regular pulse, or vice versa)
e = pOfBeat(k);
if e > 0, ref = PT(e); else, ref = tOn(k); end
tms = round((PT(i) - ref) * 10000) / 10;
if e > 0 && ~PX(e) && PX(i) && ~isnan(pNom(i)) && abs(tms - pNom(i)) <= snapMs
    tms = pNom(i);
elseif e > 0 && PX(e) && ~PX(i) && ~isnan(pNom(e)) && abs(tms + pNom(e)) <= snapMs
    tms = -pNom(e);
end
end


function [preTxt, postTxt] = pulseText(sel, owner, PT, PX, PC, pDur, pNom, pOfBeat, tOn, n, snapMs, nMax)
% pre- and post-pulses of the selected contractions: 't<ms>|<mA>|<charge us>|<pause us>|<decharge us>', several joined
% by '&' (sorted by time; at most nMax (opts.pulseTextMax, 10), the ones nearest to the eliciting pulse, then
% '&+<number of the others>'). The
% text starts with 't' (a cell starting with '-' or '+' would be read as a formula by spreadsheet programs)
preTxt = repmat({''}, n, 1); postTxt = repmat({''}, n, 1);
if n == 0 || isempty(PT), return; end
qOf = zeros(max([numel(tOn); sel(:)]), 1);
qOf(sel) = 1:n;
for role = 1:2
    ii = find(owner(:,2) == role & owner(:,1) > 0);
    if isempty(ii), continue; end
    qq = qOf(owner(ii, 1));
    keep = qq > 0; ii = ii(keep); qq = qq(keep);
    for q = reshape(unique(qq), 1, [])
        list = sort(ii(qq == q));
        k = sel(q);
        nMore = max(0, numel(list) - nMax);
        if role == 1, list = list(end - min(nMax, numel(list)) + 1:end); else, list = list(1:min(nMax, numel(list))); end
        tok = cell(1, numel(list));
        for m = 1:numel(list)
            i = list(m);
            tok{m} = ['t' numText(relPulseTime(i, k, PT, PX, pNom, pOfBeat, tOn, snapMs)) '|' numText(PC(i)) '|' ...
                numText(pDur(i,1)) '|' numText(pDur(i,2)) '|' numText(pDur(i,3))];
        end
        txt = strjoin(tok, '&');
        if nMore > 0, txt = sprintf('%s&+%d', txt, nMore); end   %never at the start (spreadsheet formulas)
        if role == 1, preTxt{q} = txt; else, postTxt{q} = txt; end
    end
end
end


function s = numText(x)
if isnan(x), s = 'NaN'; else, s = sprintf('%.10g', x + 0); end   %+ 0: no '-0'
end


function P = pulseTable(channel, PT, PX, PC, PR, pDur, fs, range, pOfBeat, owner, during, tStim, tOn, tEnd, tPk, ...
    sel, pNom, snapMs)
% one row per pulse of the range: pulse (ID = raw sample number in the file, from 0), channel, t (s), extra (status
% channel bit 16), current_mA, currentReached, chargeDuration_us, pauseDuration_us, dechargeDuration_us, outcome
% ('elicited' / 'duringContraction' / 'noResponse'), role ('eliciting' / 'pre' / 'post' / ''), contraction (number
% of the contraction it belongs to, NaN if outside the range), t_peak of that contraction, tRel_ms (pre / post: time
% relative to its eliciting pulse, as in prePulses / postPulses), couplingInterval_s (to the previous eliciting pulse),
% sinceOnset_s (to the onset of the latest contraction), phase (sinceOnset / onset ... contractionEnd (90 %)
% relaxation of that contraction)
i = find(PT >= range(1) & PT <= range(2));
n = numel(i);
nPk = numel(tOn);
qOf = zeros(max(nPk, 1), 1); qOf(sel) = 1:numel(sel);
roles = {'', 'pre', 'post', 'eliciting'};
outcome = repmat({'noResponse'}, n, 1);
role = cell(n, 1); contraction = nan(n, 1); tPeakOf = nan(n, 1); tRel = nan(n, 1);
elT = sort(tStim(~isnan(tStim)));
onV = find(~isnan(tOn)); [onT, o] = sort(tOn(onV)); onK = onV(o);
coupling = nan(n, 1); since = nan(n, 1); phase = nan(n, 1);
for m = 1:n
    ip = i(m);
    k = owner(ip, 1); r = owner(ip, 2);
    role{m} = roles{r + 1};
    if r == 3, outcome{m} = 'elicited'; elseif during(ip), outcome{m} = 'duringContraction'; end
    if k > 0
        tPeakOf(m) = tPk(k);
        if qOf(k) > 0, contraction(m) = qOf(k); end
        if r == 3, tRel(m) = 0; else, tRel(m) = relPulseTime(ip, k, PT, PX, pNom, pOfBeat, tOn, snapMs); end
    end
    j = lowerBound(elT, PT(ip) - 1e-9) - 1;          %previous eliciting pulse (strictly before)
    if j >= 1, coupling(m) = PT(ip) - elT(j); end
    j = lowerBound(onT, PT(ip) + 1e-9) - 1;          %latest onset at or before the pulse
    if j >= 1
        since(m) = PT(ip) - onT(j);
        kk = onK(j);
        dur = tEnd(kk) - tOn(kk);
        if dur > 0, phase(m) = since(m) / dur; end
    end
end
P = table(round(PT(i) * fs), repmat(channel, n, 1), PT(i), PX(i), PC(i), PR(i), pDur(i,1), pDur(i,2), pDur(i,3), ...
    outcome, role, contraction, tPeakOf, tRel, coupling, since, phase, 'VariableNames', {'pulse', 'channel', 't', ...
    'extra', 'current_mA', 'currentReached', 'chargeDuration_us', 'pauseDuration_us', 'dechargeDuration_us', 'outcome', ...
    'role', 'contraction', 't_peak', 'tRel_ms', 'couplingInterval_s', 'sinceOnset_s', 'phase'});
P.Properties.VariableUnits = {'', '', 's', '', 'mA', '', 'us', 'us', 'us', '', '', '', 's', 'ms', 's', 's', ''};
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


function [thr, keepLow, nLow] = artifactGapThreshold(tc, prom, thr, typical, ST, rocker, CL, opts)
% Paced channels: small peaks between the contractions (rocker artifacts while the rocker moves) can pass the auto
% threshold (relThreshold x typical). The prominences >= thr are sorted (>= artifactMinCandidates, 6); if the largest
% ratio between two consecutive values below the typical amplitude is >= artifactGapRatio (1.6), the lower cluster
% (all <= artifactMaxRel (0.5) x typical) has >= artifactMinPeaks (3) peaks that are not locked to the stimuli
% (latency to the previous stimulus not within +-lockWindow (0.1 s) of the median latency of the upper cluster), at
% most min(chanceMax, chance level + chanceMargin) (0.6, 0.2) of the lower cluster is locked and >=
% artifactRockerFraction (75 %) of it occurs while the rocker moves, the threshold is raised to the geometric mean of
% the two prominences at the gap. Peaks of the lower cluster that are
% locked to a stimulus stay (keepLow; small stimulated contractions: alternans, partial capture). nLow: number of
% removed peaks. TS 2026-10-09
keepLow = false(size(prom));
nLow = 0;
k = find(prom >= thr);
if numel(k) < opts.artifactMinCandidates || isnan(typical) || isempty(ST), return; end
[p, o] = sort(prom(k), 'descend');
k = k(o);
r = p(1:end-1) ./ p(2:end);
r(p(1:end-1) > typical | p(2:end) > opts.artifactMaxRel * typical) = 0;    %gap below the bulk, small lower cluster
[rMax, g] = max(r);
if rMax < opts.artifactGapRatio, return; end
hi = k(1:g); lo = k(g+1:end);
latHi = median(stimLatency(tc(hi), ST), 'omitnan');
if isnan(latHi), return; end
locked = abs(stimLatency(tc(lo), ST) - latHi) <= opts.lockWindow;
w2 = 2 * opts.lockWindow;
chance = w2 / max(CL, w2);                                  %fraction locked by chance (window 2 x lockWindow per cycle)
if nnz(~locked) < opts.artifactMinPeaks || mean(locked) > min(opts.chanceMax, chance + opts.chanceMargin) || ...
        mean(rocker(lo)) < opts.artifactRockerFraction
    return;
end
thr = sqrt(p(g) * p(g+1));
keepLow(lo(locked)) = true;
nLow = nnz(~locked);
end


function [N, n, Nm] = preStimulusNoise(t, f, ST, opts)
% rocker / noise level: rise (maximum minus the running minimum) of the filtered signal in the window before every
% stimulus that follows an interval >= noiseMinInterval (0.9 s) (window min(noiseWindow, noiseWindowRel x interval),
% 0.5 s, 0.4, where no contraction is expected; a relaxation that is not finished only falls and does not count).
% N = noisePercentile (90th) percentile, n = number of windows, Nm = median (robust against contractions that reach
% into some of the windows).
% Approach of GetBeatByBeatParameters (noise before the stimuli). TS 2026-10-09
r = nan(numel(ST), 1);
for j = 2:numel(ST)
    ci = ST(j) - ST(j-1);
    if ci < opts.noiseMinInterval, continue; end
    i1 = firstAtLeast(t, ST(j) - min(opts.noiseWindow, opts.noiseWindowRel * ci));
    i2 = firstAtLeast(t, ST(j)) - 1;                       %last sample before the stimulus
    if i2 - i1 < 2, continue; end
    s = f(i1:i2);
    r(j) = max(s - cummin(s));
end
N = mprctile(r, opts.noisePercentile);
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


function [drop, none] = rockerNoiseRule(tc, prom, thr, keepLow, typical, ST, N, rocker, tOn, fR, STall, opts)
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
% Constants: options of mda_options (advanced settings, 2026-10-10): lockWindow (0.1 s), noiseLockedMax (50 %),
% noiseAbsMax (50 uN), noiseRelMax (2 x N), rhythm*, keepNoiseRel / keepNoiseAbs (1.5 x N, N + 50 uN), keepMinPeaks /
% keepMinFraction (3, 5 %), chanceMax / chanceMargin (0.6, 0.2), dropRel (3), smallNoiseRel / smallTypicalRel /
% smallRhythmTypicalRel (1.5 x N, 0.5 / 1 x typical), rockerOnly* and captureTolerance (10, 60 %, 10 %, 5 %).
% TS 2026-10-09 (STall: all pulses incl. extra pulses for the latency, 2026-10-10)
if nargin < 11 || isempty(STall), STall = ST; end
if nargin < 12, opts = mda_options(); end
above = prom >= thr | keepLow;
drop = false(size(prom));
none = false;
k = find(above);
if numel(k) < 3, return; end
[~, o] = sort(prom(k), 'descend');
top = k(o(1:min(numel(k), numel(ST))));
lat = stimLatency(tc, STall);
l = sort(lat(top));
l = l(~isnan(l));
if isempty(l), return; end
locked = latencyLock(lat, top, opts.lockWindow);
w2 = 2 * opts.lockWindow;
chance = w2 / max(median(diff(ST)), w2);                   %fraction of the time within +-lockWindow of the latency
% N unknown (high rates, no intervals >= 0.9 s): peaks at the rhythm of the rocker, not of the stimuli. +-0.1 s covers
% most of a short stimulus interval: locking here within +-hw, hw = min(0.1 s, 0.2 x median interval)
noise = mean(locked(top)) < opts.noiseLockedMax && (typical <= opts.noiseAbsMax || ...
    (typical <= opts.noiseRelMax * N && rockerRhythm(tc, above & rocker, tOn, fR, opts.rhythmMinPerCycle, opts)));
rockerOnly = false;
if ~noise && isnan(N) && ~isnan(fR)
    d = diff(tc(above & rocker)) * fR;                     %peak intervals in rocker periods
    atR = abs(d - 1) <= opts.rockerOnlyTolerance | abs(d - 0.5) <= opts.rockerOnlyTolerance / 2;
    CLm = median(diff(ST));
    ipi = median(d) / fR;
    k = round(ipi / CLm);                                  %1:1 or 2:1 capture at the rocker period: undecidable
    if numel(d) >= opts.rockerOnlyMinIntervals && mean(atR) >= opts.rockerOnlyFraction && ...
            ~(k >= 1 && k <= 2 && abs(ipi - k * CLm) <= opts.captureTolerance * ipi)
        hw = min(opts.lockWindow, opts.lockWindowRel * CLm);
        lockedR = latencyLock(lat, top, hw);
        chanceR = 2 * hw / max(CLm, 2 * hw);
        if mean(lockedR(top)) < max(opts.noiseLockedMax, chanceR + opts.chanceMargin)
            rockerOnly = true;
            locked = lockedR;
            chance = chanceR;
        end
    end
end
if noise || rockerOnly
    Nn = N;
    if isnan(Nn), Nn = typical; end
    big = above & prom >= max(opts.keepNoiseRel * Nn, Nn + opts.keepNoiseAbs);   %clearly above the rocker / noise level
    lk = big & locked;                                     %contractions of some stimuli (partial capture)
    if nnz(lk) < max(opts.keepMinPeaks, opts.keepMinFraction * numel(ST)) || ...
            nnz(lk) <= min(opts.chanceMax, chance + opts.chanceMargin) * nnz(big)
        lk(:) = false;                                     %not more than by chance
    end
    L = max(typical, N);                                   %max ignores NaN
    if rockerOnly, L = median(prom(top)); end              %size of the rocker peaks (typical: of more peaks than exist)
    drop = above & prom < opts.dropRel * L & ~lk;
    if rockerOnly, drop = drop & rocker; end               %peaks while the rocker is at rest are no rocker peaks
    none = ~any(above & ~drop);
    return;
end
if ~isnan(N)
    lim = min(opts.smallNoiseRel * N, opts.smallTypicalRel * typical);
    if rockerRhythm(tc, above & ~locked & rocker, tOn, fR, opts.smallRhythmMinPerCycle, opts)
        lim = min(opts.smallNoiseRel * N, opts.smallRhythmTypicalRel * typical);
    end
    drop = above & ~locked & prom < lim;
end
end


function r = rockerRhythm(tc, sel, tOn, fR, minPerCycle, opts)
% peaks sel at the rhythm of the rocker: minPerCycle ... rhythmMaxPerCycle (2.2) peaks per rocker cycle (tOn = time
% with the rocker moving) or a median interval of 1 or 1/2 rocker period (+-rhythmTolerance, 15 %, or half of it);
% false if the rocker frequency fR is unknown
perCycle = nnz(sel) / max(tOn, eps) / fR;
ipi = median(diff(tc(sel))) * fR;
tol = opts.rhythmTolerance;
r = (perCycle >= minPerCycle && perCycle <= opts.rhythmMaxPerCycle) || abs(ipi - 1) <= tol || abs(ipi - 0.5) <= tol / 2;
end


function fR = rockerFrequency(S, opts)
% rocker frequency (Hz) of the data: opts.rockerFrequency (one value in Hz, or [rpm f0] rows of mda_rockerFilter:
% the row of the logged speed, a single row otherwise) or the last logged rocker speed > 0 before the middle of the
% data (otherwise the first one) x opts.rockerHzPerRpm (0.0202 Hz/rpm, as mda_rockerFilter); NaN if unknown
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
if ~isnan(rpm), fR = opts.rockerHzPerRpm * rpm; end
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
if nStim >= opts.pacedMinStimuli
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
