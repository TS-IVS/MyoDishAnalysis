function [A, M] = mda_analyzeAP(EP, B, varargin)
%MDA_ANALYZEAP  Action potential parameters of an EP recording (membrane potential) for every contraction.
%
%   [A, M] = mda_analyzeAP(EP, B)                 EP from mda_readEPRecording, B from mda_analyzeChannel (same .mdd)
%   [A, M] = mda_analyzeAP(EP, B, 'name', value, ...)
%   P = mda_analyzeAP('parameters')               {name, unit, definition} of the numeric AP columns
%   [Vc, R] = mda_analyzeAP('removeArtefacts', EP)   EP.V with the stimulus artefacts replaced by straight lines
%   [Vc, R] = mda_analyzeAP('removeArtefacts', EP, 'name', value, ...)   (display only, see REMOVING THE ARTEFACTS)
%
% A  table with one row per row of B (append with [B, A]):
%      AP_dVdtMax  (V/s)  maximum upstroke velocity (central difference of the raw signal); NaN if the upstroke is not
%                         evaluable (within the stimulus artefact, sampling rate < 5 kHz)
%      AP_RMP      (mV)   resting (diastolic) membrane potential: median over 10 ms before the stimulus artefact
%                         (unstimulated beats: before the foot of the upstroke)
%      AP_Vmax     (mV)   maximum voltage of the AP (peak); NaN if the peak may lie within the stimulus artefact
%      APD25/50/90 (ms)   activation --> 25 / 50 / 90 % repolarization: first time after the peak at which the signal
%                         (0.5 ms moving mean) falls below V_max - x % of (V_max - RMP). Upstroke in the artefact (peak
%                         unknown): APD25 and APD50 NaN; APD90 from the stimulus onset with V_ref = highest value within
%                         50 ms after the artefact instead of V_max (approximate: the level is RMP + 10 % of
%                         (V_ref - RMP); a slow final repolarization makes it sensitive to V_ref)
%      t_AP        (s)    activation time in the .mdd file: time of the maximum upstroke velocity, or the stimulus
%                         onset if the upstroke lies within the stimulus artefact (column AP_reference)
%      AP_reference       'upstroke' | 'stimulus' | ''
%      AP_note            reasons for missing values, e.g. 'upstroke in artefact', 'no AP', 'next stimulus before APD90'
% M  struct array (one element per row of B) for plots: tOn, tArtEnd, tAct, tPeak, vPeak, tAPD (1x3), vAPD (1x3), rmp
%
% STIMULUS ARTEFACT
%   The pulse (onset and end in the stimulation channel; biphasic pulse incl. pause = one pulse, EP.stimTimes /
%   EP.stimEnds) is followed in V_m by saturation (amplifier limit) and a capacitive decay. The artefact ends at the
%   first sample after the pulse end that is not saturated and where |dV/dt| (0.5 ms moving mean) < 'artefactSlope'.
%   The stimulus onset (beginning of the artefact) is the stimulus time. The upstroke is evaluated only if it lies
%   completely after the artefact: maximum dV/dt >= 'upstrokeMin' after the artefact end and not at its first samples,
%   foot of the upstroke (minimum between artefact end and dV/dt max) <= RMP + 30 % of the amplitude, amplitude >=
%   'minAmplitude', peak not saturated. Otherwise the upstroke (dV/dt max) and the peak (V_max) are NaN and the APDs
%   are measured from the stimulus onset (AP_reference = 'stimulus'; error <= latency of the activation, a few ms).
%   No AP: the signal 20 ms after the artefact is < RMP + minAmplitude / 2 or never >= RMP + minAmplitude.
% FUSION / NEXT STIMULUS
%   Each AP is evaluated up to the next stimulus (any pulse in the stimulation channel). If the repolarization level is
%   not reached before it, the APD is NaN (note 'next stimulus before APD90'). RMP more than 10 mV above the median
%   RMP of the table: note 'RMP not diastolic' (stimulated before repolarization).
%
% OPTIONS
%   'artefactSlope'  V/s, default 20      'upstrokeMin'  V/s, default 20      'minAmplitude'  mV, default 40
%   'maxFoot'        default 0.3: the foot of an evaluable upstroke is <= RMP + maxFoot x amplitude (stricter: 0.2)
%   'maxLatency'     s, default 0.1 (stimulus onset --> upstroke)              'maxAPD'  s, default 2
%   'apdFrom'        'auto' (default: upstroke, else stimulus onset) | 'stimulus' | 'upstroke' (NaN without upstroke)
%   'tolerance'      s, default 0.015: stimulus of a contraction (t_stim) <--> stimulus in the EP recording
%
% REMOVING THE ARTEFACTS (display, MyoDishAnalysisGUI 'remove stimulus artefact'; the AP parameters above do not use it)
%   For every pulse of the stimulation channel (EP.stimTimes / EP.stimEnds) the samples from the pulse onset to the
%   end of the artefact are replaced by a straight line from the last sample before the pulse to the first sample
%   after the artefact. End of the artefact: as above (first sample after the pulse end that is not saturated and
%   where |dV/dt| (0.5 ms moving mean) < 'artefactSlope'; within 30 ms and before the next pulse), then the decay of
%   the artefact is followed towards the RMP (median over 10 ms before the pulse) for at most 'maxTail': it ends
%   when the RMP is reached, when the decay is slower than 'tailSlope' or when the signal turns back by > 3 mV (an
%   upstroke). An upstroke within the artefact cannot be recovered: the line runs to the first sample after it.
%   Vc   EP.V (same class and size) with the replaced samples;   R   [tFrom tTo] (s, .mdd time) of every replaced
%        segment (the samples at tFrom and tTo are kept)
%   Options: 'artefactSlope' V/s, default 20;  'tailSlope' V/s, default 2;  'maxTail' s, default 0.01
%
% TS 2026-10-06 (removeArtefacts 2026-10-09)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

if ischar(EP) && strcmpi(EP, 'parameters')
    A = {
        'AP_dVdtMax', 'V/s', 'AP: maximum upstroke velocity; NaN if the upstroke lies within the stimulus artefact'
        'AP_RMP',     'mV',  'AP: resting (diastolic) membrane potential, median over 10 ms before the stimulus artefact'
        'AP_Vmax',    'mV',  'AP: maximum voltage (peak); NaN if the peak may lie within the stimulus artefact'
        'APD25',      'ms',  'AP duration: activation (upstroke dV/dt max) --> 25 % repolarization; NaN if the upstroke lies within the stimulus artefact'
        'APD50',      'ms',  'AP duration: activation --> 50 % repolarization; NaN if the upstroke lies within the stimulus artefact'
        'APD90',      'ms',  'AP duration: activation --> 90 % repolarization; upstroke within the artefact: from the stimulus onset, approximate (AP_note)'
        };
    return;
end
if ischar(EP) && strcmpi(EP, 'removeArtefacts')
    [A, M] = removeArtefacts(B, varargin{:});
    return;
end

P = struct('artefactSlope', 20, 'upstrokeMin', 20, 'minAmplitude', 40, 'maxFoot', 0.3, 'maxLatency', 0.1, 'maxAPD', 2, ...
    'apdFrom', 'auto', 'tolerance', 0.015);
f = fieldnames(P);
for k = 1:2:numel(varargin)
    j = find(strcmpi(f, varargin{k}), 1);
    if isempty(j), error('mda_analyzeAP: unknown option ''%s''.', varargin{k}); end
    P.(f{j}) = varargin{k+1};
end

n = height(B);
nan1 = nan(n, 1);
A = table(nan1, nan1, nan1, nan1, nan1, nan1, nan1, repmat({''}, n, 1), repmat({''}, n, 1), 'VariableNames', ...
    {'AP_dVdtMax', 'AP_RMP', 'AP_Vmax', 'APD25', 'APD50', 'APD90', 't_AP', 'AP_reference', 'AP_note'});
M = repmat(struct('tOn', nan, 'tArtEnd', nan, 'tAct', nan, 'tPeak', nan, 'vPeak', nan, 'tAPD', nan(1, 3), ...
    'vAPD', nan(1, 3), 'rmp', nan), n, 1);
if n == 0 || isempty(EP) || isempty(EP.V), return; end

V = EP.V; nV = numel(V); dt = EP.dt; t0 = EP.t0;
tEP = [t0, t0 + (nV - 1) * dt];
idx = @(t) min(nV, max(1, round((t - t0) / dt) + 1));
tOf = @(k) t0 + (k - 1) * dt;
sAP = [];
if isfield(EP, 'stimTimes'), sAP = EP.stimTimes(:); end
sEnd = sAP;
if isfield(EP, 'stimEnds') && numel(EP.stimEnds) == numel(sAP), sEnd = EP.stimEnds(:); end
fsHz = 1 / dt;
w05 = max(1, round(0.0005 / dt));                                 %0.5 ms
mx = max(V); mn = min(V);                                         %amplifier limits: many samples at exactly the extreme
satHi = Inf; satLo = -Inf;
if nnz(V == mx) >= 10, satHi = double(mx) - 0.5; end
if nnz(V == mn) >= 10, satLo = double(mn) + 0.5; end
lev = [0.25 0.5 0.9];
artEndPrev = -Inf;

for r = 1:n
    note = {};
    tPk = B.t_peak(r);
    if tPk < tEP(1) || tPk > tEP(2) + 0.5
        A.AP_note{r} = 'outside the EP recording'; continue;
    end
    ts = nan;
    if ismember('t_stim', B.Properties.VariableNames), ts = B.t_stim(r); end
    j = [];
    if ~isnan(ts) && ~isempty(sAP)
        [dmin, j] = min(abs(sAP - ts));
        if dmin > P.tolerance, j = []; end
    end
    if isempty(j) && ~isempty(sAP)                                %unassigned contraction: EP stimulus before the peak?
        c = find(sAP < tPk - 0.03 & sAP > tPk - 0.6, 1, 'last');
        if ~isempty(c) && (r == 1 || sAP(c) > B.t_peak(max(1, r - 1))), j = c; end
    end

    if ~isempty(j)                                                %---------------- stimulated AP
        tOn = sAP(j); tPe = max(sEnd(j), tOn);
        kOn = idx(tOn);
        tNext = tEP(2) + dt; if j < numel(sAP), tNext = sAP(j + 1); end
        kEnd = min([nV, idx(tNext) - 1, kOn + round(P.maxAPD / dt)]);
        kr = max(kOn - round(0.0105 / dt), 1):(kOn - w05);
        kr = kr(tOf(kr) > artEndPrev);
        rmp = nan; if ~isempty(kr), rmp = median(double(V(kr))); end
        seg = double(V(kOn:kEnd)); ns = numel(seg);
        if ns < 3 || isnan(rmp)
            A.AP_note{r} = 'too little EP data'; continue;
        end
        sm = movmean(seg, w05);
        dsm = gradient(sm) / dt / 1000;                           %V/s (mV/ms)
        sat = seg >= satHi | seg <= satLo;
        iPe = max(1, min(ns, idx(tPe) - kOn + 1));
        iAe = find((1:ns)' > iPe & ~sat & abs(dsm) < P.artefactSlope, 1);
        if isempty(iAe), iAe = min(ns, iPe + round(0.03 / dt)); note{end+1} = 'artefact not settled'; end %#ok<AGROW>
        tAe = tOf(kOn + iAe - 1);
        artEndPrev = tAe;
        M(r).tOn = tOn; M(r).tArtEnd = tAe; M(r).rmp = rmp;
        % upstroke after the artefact
        dV = gradient(seg) / dt / 1000;
        iw = iAe:min(ns, round(P.maxLatency / dt) + 1);
        clean = false; iAct = NaN; iPk = NaN;
        if numel(iw) > 2
            [dmax, im] = max(dV(iw)); im = iw(im);
            ip = im - 1 + find(seg(im:min(ns, im + round(0.02 / dt))) == max(seg(im:min(ns, im + round(0.02 / dt)))), 1);
            amp = seg(ip) - rmp;
            foot = min(seg(iAe:im));
            clean = dmax >= P.upstrokeMin && im > iAe + 1 && amp >= P.minAmplitude && foot <= rmp + P.maxFoot * amp && ~sat(ip);
            if clean, iAct = im; iPk = ip; end
        end
        if clean
            A.AP_dVdtMax(r) = dmax; A.AP_Vmax(r) = seg(iPk);
            if fsHz < 5000, A.AP_dVdtMax(r) = NaN; note{end+1} = 'dV/dt max needs >= 5 kHz'; end %#ok<AGROW>
            tAct = tOf(kOn + iAct - 1); ref = 'upstroke'; vRef = seg(iPk); iFrom = iPk; pkKnown = true;
            if strcmpi(P.apdFrom, 'stimulus'), tAct = tOn; ref = 'stimulus'; end
        else
            note{end+1} = 'upstroke in artefact: APD90 from stimulus, approx.'; %#ok<AGROW>
            i50 = iAe:min(ns, iAe + round(0.05 / dt));
            i50 = i50(~sat(i50));
            noAP = isempty(i50);
            if ~noAP
                [vRef, k] = max(seg(i50)); iFrom = i50(k);
                v20 = sm(min(ns, iAe + round(0.02 / dt)));
                noAP = vRef - rmp < P.minAmplitude || v20 - rmp < P.minAmplitude / 2;
            end
            if noAP
                A.AP_RMP(r) = rmp; A.AP_note{r} = 'no AP'; continue;
            end
            tAct = tOn; ref = 'stimulus'; pkKnown = false;
            if strcmpi(P.apdFrom, 'upstroke'), tAct = NaN; ref = ''; end
        end
        repolarization();
    else                                                          %---------------- unstimulated AP (no EP stimulus)
        k1 = idx(max(tPk - 0.6, tEP(1))); k2 = idx(tPk - 0.02);
        if r > 1, k1 = max(k1, idx(B.t_peak(r - 1) + 0.05)); end
        if k2 - k1 < 10, A.AP_note{r} = 'no AP found'; continue; end
        seg0 = double(V(k1:k2));
        dV0 = gradient(seg0) / dt / 1000;
        inArt = false(size(seg0));                                %exclude stimulus artefacts (+30 ms)
        for q = find(sAP >= tOf(k1) - 0.04 & sAP <= tOf(k2))'
            inArt(max(1, idx(sAP(q)) - k1 + 1):min(numel(seg0), idx(sEnd(q) + 0.03) - k1 + 1)) = true;
        end
        dV0(inArt) = -Inf;
        [dmax, im] = max(dV0);
        if dmax < P.upstrokeMin, A.AP_note{r} = 'no AP found'; continue; end
        kAct = k1 + im - 1;
        iF = find(dV0(1:im) < 0.1 * dmax, 1, 'last'); if isempty(iF), iF = 1; end
        kF = k1 + iF - 1;
        kr = max(1, kF - round(0.0105 / dt)):(kF - w05);
        if isempty(kr), A.AP_note{r} = 'no AP found'; continue; end
        rmp = median(double(V(kr)));
        kEnd = min(nV, kAct + round(P.maxAPD / dt));
        nx = find(sAP > tOf(kAct), 1); if ~isempty(nx), kEnd = min(kEnd, idx(sAP(nx)) - 1); end
        seg = double(V(kF:kEnd)); ns = numel(seg); sm = movmean(seg, w05);
        sat = seg >= satHi | seg <= satLo;
        iAct = kAct - kF + 1;
        iPk = iAct - 1 + find(seg(iAct:min(ns, iAct + round(0.02 / dt))) == max(seg(iAct:min(ns, iAct + round(0.02 / dt)))), 1);
        if seg(iPk) - rmp < P.minAmplitude || sat(iPk), A.AP_RMP(r) = rmp; A.AP_note{r} = 'no AP found'; continue; end
        kOn = kF;
        A.AP_dVdtMax(r) = dmax; A.AP_Vmax(r) = seg(iPk);
        if fsHz < 5000, A.AP_dVdtMax(r) = NaN; note{end+1} = 'dV/dt max needs >= 5 kHz'; end %#ok<AGROW>
        tAct = tOf(kAct); ref = 'upstroke'; vRef = seg(iPk); iFrom = iPk; pkKnown = true;
        M(r).rmp = rmp;
        repolarization();
    end
end

% RMP not diastolic (stimulated before repolarization of the previous AP)
med = median(A.AP_RMP, 'omitnan');
for r = find(A.AP_RMP > med + 10)'
    A.AP_note{r} = strjoin([{'RMP not diastolic'}, A.AP_note(r)], '; ');
    A.AP_note{r} = regexprep(A.AP_note{r}, '; $', '');
end

    function repolarization()
        % APD25/50/90 from the activation time; fills A(r, :) and M(r)
        A.AP_RMP(r) = rmp; A.t_AP(r) = tAct; A.AP_reference{r} = ref;
        M(r).tAct = tAct; M(r).tPeak = tOf(kOn + iFrom - 1); M(r).vPeak = vRef;
        if ~isnan(A.AP_Vmax(r)), M(r).vPeak = A.AP_Vmax(r); end
        L = vRef - lev * (vRef - rmp);
        qq = 1:3;
        if ~pkKnown, qq = 3; end                                  %peak unknown: APD25 / APD50 not evaluable
        for qn = qq
            i = iFrom - 1 + find(sm(iFrom:ns) <= L(qn), 1);
            if isempty(i) || i <= 1
                if kOn + ns - 1 < nV && kOn + ns - 1 < kOn + round(P.maxAPD / dt)
                    note{end+1} = sprintf('next stimulus before APD%d', round(100 * lev(qn))); %#ok<AGROW>
                else
                    note{end+1} = sprintf('no APD%d', round(100 * lev(qn))); %#ok<AGROW>
                end
                continue;
            end
            fr = (sm(i - 1) - L(qn)) / (sm(i - 1) - sm(i));       %linear interpolation
            tx = tOf(kOn + i - 2) + fr * dt;
            M(r).tAPD(qn) = tx; M(r).vAPD(qn) = L(qn);
            A.(sprintf('APD%d', round(100 * lev(qn))))(r) = 1000 * (tx - tAct);
        end
        note = unique(note, 'stable');
        if any(startsWith(note, 'next stimulus before APD'))      %one note: the first level not reached
            kn = find(startsWith(note, 'next stimulus before APD'), 1);
            note = [note(~startsWith(note, 'next stimulus before APD')), note(kn)];
        end
        A.AP_note{r} = strjoin(note, '; ');
    end
end


function [Vc, R] = removeArtefacts(EP, varargin)
% stimulus artefacts of EP.V replaced by straight lines (display; see REMOVING THE ARTEFACTS in the help)
P = struct('artefactSlope', 20, 'tailSlope', 2, 'maxTail', 0.01);
f = fieldnames(P);
for k = 1:2:numel(varargin)
    j = find(strcmpi(f, varargin{k}), 1);
    if isempty(j), error('mda_analyzeAP: unknown option ''%s'' of removeArtefacts.', varargin{k}); end
    P.(f{j}) = varargin{k+1};
end
R = zeros(0, 2);
if isempty(EP) || ~isfield(EP, 'V') || isempty(EP.V), Vc = []; return; end
Vc = EP.V;
sAP = [];
if isfield(EP, 'stimTimes'), sAP = EP.stimTimes(:); end
if isempty(sAP), return; end
sEnd = sAP;
if isfield(EP, 'stimEnds') && numel(EP.stimEnds) == numel(sAP), sEnd = EP.stimEnds(:); end
V = double(EP.V(:)); nV = numel(V); dt = EP.dt; t0 = EP.t0;
idx = @(t) min(nV, max(1, round((t - t0) / dt) + 1));
w05 = max(1, round(0.0005 / dt));                                 %0.5 ms
mx = max(V); mn = min(V);                                         %amplifier limits (as the analysis)
satHi = Inf; satLo = -Inf;
if nnz(V == mx) >= 10, satHi = mx - 0.5; end
if nnz(V == mn) >= 10, satLo = mn + 0.5; end
n30 = round(0.03 / dt); nTail = round(P.maxTail / dt);
out = V;
R = nan(numel(sAP), 2);
kBprev = 0;
for j = 1:numel(sAP)
    kOn = idx(sAP(j)); kPe = idx(max(sEnd(j), sAP(j)));
    kLim = nV;
    if j < numel(sAP), kLim = min(nV, idx(sAP(j + 1)) - 1); end   %before the next pulse
    k3 = min(kLim, kPe + n30 + w05);
    if k3 <= kOn + 1, continue; end
    seg = V(kOn:k3); ns = numel(seg);
    sm = movmean(seg, w05);
    dsm = gradient(sm) / dt / 1000;                               %V/s (mV/ms)
    sat = seg >= satHi | seg <= satLo;
    iPe = kPe - kOn + 1;
    iLim = min(ns, iPe + n30);
    ii = (1:ns)';
    iAe = find(ii > iPe & ii <= iLim & ~sat & abs(dsm) < P.artefactSlope, 1);
    if isempty(iAe), iAe = iLim; end
    % decay of the artefact towards the RMP: until the RMP, slower than tailSlope, or turning back by > 3 mV (upstroke)
    kr = max(1, kOn - round(0.0105 / dt)):(kOn - w05);
    kr = kr(kr > kBprev);
    if ~isempty(kr) && ~sat(iAe)
        rmp = median(V(kr));
        d = sign(rmp - sm(iAe)); best = iAe;
        for i = iAe:min(iLim, iAe + nTail)
            if d * (sm(i) - rmp) >= 0, best = i; break; end
            if d * (sm(i) - sm(best)) > 0, best = i; end
            if d * (sm(best) - sm(i)) > 3 || (i > iAe && abs(dsm(i)) < P.tailSlope), break; end
        end
        iAe = best;
    end
    kA = max(1, kOn - 1); kB = kOn + iAe - 1;
    if kB > kA + 1
        k = (kA + 1:kB - 1)';
        out(k) = V(kA) + (V(kB) - V(kA)) * (k - kA) / (kB - kA);
    end
    R(j, :) = t0 + ([kA kB] - 1) * dt;
    kBprev = kB;
end
R = R(~isnan(R(:, 1)), :);
Vc = reshape(cast(out, 'like', EP.V), size(EP.V));
end
