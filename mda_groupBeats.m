function [B, G, Z, notes] = mda_groupBeats(H, B, C, range, by, opts, steadyN)
%MDA_GROUPBEATS  Group the contractions of one channel and time range by a stimulation quantity; summary per group.
%
%   [B, G, Z, notes] = mda_groupBeats(H, B, C, range, by, opts, steadyN)
%
%   H      file facts (mda_readMdd(mddFile))
%   B      contraction table of one channel and range (mda_analyzeChannel / MyoDishAnalysis)
%   C      channel info of mda_analyzeChannel (stimTimes and stimCaptured of the range, stimChannel)
%   range  [from to] (s)
%   by     quantity:
%          'pacingFrequency'  1 / interval from the previous stimulus of the channel (Hz); intervals within 2 % are
%                             one cluster (e.g. 0.2850 and 0.2875 s = 3.5 Hz); groupValue = 1 / median interval of
%                             the cluster rounded to opts.frequencyResolution (default 0.1 Hz) at >= 1 Hz and to
%                             opts.frequencyResolutionLow (0.05 Hz) below 1 Hz: clusters with the same rounded
%                             frequency are one group (0.99, 1.0, 1.001 Hz = '1 Hz'; 0.74, 0.75 Hz = '0.75 Hz').
%                             stimFrequency of the group summary: 1 / median interval (measured)
%          'S2interval'       S1-S2 protocols: S2 = premature stimulus (interval < 95 % of the previous one, next
%                             interval longer, previous stimulus not premature); groups 'S1', 'S2 <interval>' and
%                             'post-S2 <interval>' (the stimulus after an S2); S2 intervals within 7.5 ms = one group.
%                             'S1' = the other stimuli at the basic interval (median, +-5 %) that are not followed by an
%                             S2 ('pre-S2': relaxation cut off by the S2); stimuli at other intervals (e.g. trains at a
%                             higher rate between the S1-S2 steps): group 'other'
%          'stimCurrent'      stimulus current of the pulse (mA, status channel)
%          'pauseLength'      post-rest potentiation: first stimulus after a pause (interval >= 1.5 s, >= 1.5 x the
%                             median interval and >= 1.5 x the interval before; the median interval returns within the
%                             next 3 stimuli) = 'rest <interval>', one group per pause
%                             (groupStep = number of the pause in the range); pauses (interval - steady interval)
%                             within opts.pauseTolerance (default 10 %) of the shortest pause of a set have the same
%                             pause length (groupValue = median interval of the set; equal labels are numbered #n);
%                             the stimuli within 10 s after it 'after rest' (potentiation decays); the other stimuli at
%                             the median interval (+-5 %) 'steady' (reference), all others 'other'
%          'rockerSpeed'      rocker speed (rpm) at the contraction peak / stimulus ('rockerSpeed' entries of the log
%                             file, + rockerLogDelay); before the first entry: unknown
%          'pulseDuration'    'chargeDuration' entry of the log file for the stimulated channel (ms)
%          'log:<code>'       any numeric entry of the log file for the stimulated channel (or channel 0), e.g.
%                             'log:pauseDuration', 'log:stimCurrent'
%   opts   options (mda_options; minStimToPeak, rockerLogDelay, frequencyResolution(Low), pauseTolerance, rocker,
%          ffrRockerFallback, prpReference, prpReferenceBeats, irregularCV, minGroupBeats)
%   steadyN  pacingFrequency (FFR protocols, MyoDishAnalysis: opts.steadyStateBeats; default 0 = all contractions):
%          steady state per frequency (2026-10-10). Runs = consecutive stimuli at the same frequency (groupStep = number
%          of the run of this frequency). In the longest run (the protocol step; not the basic pacing before or after
%          the protocol), the longest sequence of consecutive captured stimuli whose previous and next stimuli are
%          captured, too (partial capture, e.g. 2:1, gives no candidates and a note); its contractions are candidates;
%          with rocker 'stopped' those with the rocker at rest (none: with opts.ffrRockerFallback all candidates,
%          note); of these the last steadyN are included, all other
%          contractions of the group are not. Groups with fewer than opts.minGroupBeats included contractions: note.
%
%   B      with the columns group (text), groupValue (number; NaN for 'S1', 'steady', unknown), groupRole
%          ('S1' / 'preS2' / 'S2' / 'postS2' / 'other', 'steady' / 'afterRest' / 'postRest' / 'other', otherwise '')
%          and groupStep (pauseLength: number of the pause in the range, otherwise NaN). A stimulated contraction
%          belongs to the group of its stimulus (elicited by an extra pulse: of the last regular pulse at or before
%          it), an extra / unpaced contraction to the group of the last stimulus before its onset (without onset:
%          its peak; rockerSpeed: rocker speed at the peak). Extra pulses (status channel bit 16) are no stimuli of
%          the protocol; an extra pulse belongs to the group of the nearest regular pulse.
%   G      one row per group (order: role, value): group, groupValue, groupRole, groupStep, groupBy, then the columns of
%          mda_summarize for the contractions and stimuli of the group, capture_percent (stimuli followed by a
%          contraction), currentReached_percent (stimuli with the set current reached) and amplitude_pctOfRef
%          (mean amplitude in % of the group 'S1' / 'steady'; NaN for the other quantities). stimFrequency of a group =
%          1 / median interval from the previous stimulus.
%          amplitude_CV (population SD / mean of the included amplitudes, from mda_summarize) and irregular
%          (amplitude_CV > opts.irregularCV, 0.15; NaN with < 2 contractions). pauseLength, post-rest groups
%          (2026-10-10): amplitude_pctOfRef = mean of the amplitudes in % of the reference of each pause (option
%          prpReference): 'preceding' (default) median of the last prpReferenceBeats (6) stimulated contractions of the
%          pacing at the steady interval before the pause; 'firstTrain' mean of the stimulated contractions of the
%          pacing before the first pause of the range; 'steady' the steady group. Reference contractions: independent
%          of the rocker state. The other groups: % of the steady group.
%   Z      the stimuli of the channel (with the 300 s before the range): t, prevInt, nextInt, role, value, step,
%          group, captured (followed by a contraction), inRange (input of mda_protocolResults)
%   notes  text notes (FFR: steps summarized with the rocker moving, steps with few contractions)
%
% TS 2026-10-07 (S2interval: groups 'other', 'pre-S2'; pauseLength: one group per pause, 'after rest', 'other';
% uncertain contractions 2026-10-09; extra pulses, tolerances frequencyResolution / pauseTolerance, FFR steady state,
% PRP reference per pause, irregular groups 2026-10-10)

if nargin < 6 || isempty(opts), opts = mda_options(); end
if nargin < 7 || isempty(steadyN), steadyN = 0; end
notes = {};
dflt = struct('ffrRockerFallback', true, 'prpReference', 'steady', 'prpReferenceBeats', 6, 'irregularCV', 0.15, ...
    'minGroupBeats', 5, 'rocker', 'any', 'beats', 'all');   %options structs of older versions
fn = fieldnames(dflt);
for i = 1:numel(fn), if ~isfield(opts, fn{i}), opts.(fn{i}) = dflt.(fn{i}); end, end
if ~isfield(opts, 'frequencyResolution'), opts.frequencyResolution = 0.1; end
if ~isfield(opts, 'frequencyResolutionLow'), opts.frequencyResolutionLow = 0.05; end
if ~isfield(opts, 'pauseTolerance'), opts.pauseTolerance = 0.1; end
by = char(by);

% ------------------------------------------------------------------ stimuli of the channel (with the 300 s before)
S = mda_readMdd(H, max(0, range(1) - 300), min(H.totalSeconds, range(2) + 1), opts);
stimCh = C.stimChannel;
isX = false(size(S.stim.channel));                 %extra pulses (status channel bit 16) are no stimuli of the
if isfield(S.stim, 'isExtraPulse') && stimCh > 0 && ~(isfield(opts, 'stimAssignment') && ...
        strcmp(opts.stimAssignment, 'peak'))       %protocol (option stimAssignment 'peak': as before)
    isX = S.stim.isExtraPulse;
end
idx = find(S.stim.channel == stimCh & ~isX(:));
[tt, o] = sort(S.stim.time(idx));
idx = idx(o);
cur = S.stim.current(idx);
reached = S.stim.currentReached(idx);
nS = numel(tt);
prevInt = [nan; diff(tt)]; prevInt = prevInt(1:nS, 1);   %no stimuli (channel not paced): empty
nextInt = [diff(tt); nan]; nextInt = nextInt(1:nS, 1);

% ------------------------------------------------------------------ value and role of every stimulus
val = nan(nS, 1);                                  %group value
step = nan(nS, 1);                                 %pauseLength: number of the pause
role = repmat({''}, nS, 1);
refRole = '';
switch lower(by)
    case 'pacingfrequency'
        gid = clusterValues(prevInt, 0, 0.02);
        val = groupMedian(prevInt, gid);
        % one group per rounded frequency (2026-10-10)
        val = roundFrequency(1 ./ val, opts.frequencyResolution, opts.frequencyResolutionLow);
        % runs of consecutive stimuli at the same frequency; step = number of the run of this frequency (steady state)
        runId = cumsum([true; ~(val(2:end) == val(1:end-1))]);
        runId = runId(1:nS, 1);
        if steadyN > 0
            for v = unique(val(~isnan(val)))'
                r = unique(runId(val == v), 'stable');
                for q = 1:numel(r), step(runId == r(q)) = q; end
            end
        end
    case 's2interval'
        premature = prevInt < 0.95 * [nan; prevInt(1:end-1)] & (isnan(nextInt) | nextInt > 1.05 * prevInt);
        isS2 = premature & ~[false; premature(1:end-1)];
        role(:) = {'S1'};
        role(isS2) = {'S2'};
        post = [false; isS2(1:end-1)];
        role(post) = {'postS2'};
        cand = ~isS2 & ~post;                      %S1 = basic interval; other intervals: 'other'
        inR = tt >= range(1) & tt <= range(2);
        base = median(prevInt(cand & inR), 'omitnan');
        role(cand & abs(prevInt - base) > 0.05 * base) = {'other'};
        role(strcmp(role, 'S1') & [isS2(2:end); false]) = {'preS2'};   %relaxation cut off by the S2
        s2 = nan(nS, 1); s2(isS2) = prevInt(isS2);
        gid = clusterValues(s2, 0.0075, 0);
        v2 = groupMedian(s2, gid);
        val(isS2) = v2(isS2);
        ip = find(post);
        val(ip) = v2(ip - 1);
        refRole = 'S1';
    case 'stimcurrent'
        val = cur;
    case 'pauselength'
        inR = tt >= range(1) & tt <= range(2);
        steadyCL = median(prevInt(inR), 'omitnan');
        % pause: the interval before is known and >= 1.5 x shorter (not the 2nd interval after a pause), and the
        % steady interval returns within the next 3 stimuli (not a change to a lower rate, e.g. at the end)
        before = [nan; prevInt(1:end-1)];
        isSteady = abs(prevInt - steadyCL) <= 0.05 * steadyCL;
        rest = prevInt >= max(1.5, 1.5 * steadyCL) & prevInt >= 1.5 * before;
        for r = find(rest)'
            nx = isSteady(r+1:min(r+3, nS));
            rest(r) = isempty(nx) || any(nx);
        end
        after = false(nS, 1);                      %potentiation decays: not part of the steady reference
        for r = find(rest)'
            after = after | (tt > tt(r) & tt <= tt(r) + 10);
        end
        role(:) = {'other'};
        role(isSteady) = {'steady'};
        role(after) = {'afterRest'};
        role(rest) = {'postRest'};
        val(rest) = prevInt(rest);
        pz = nan(nS, 1); pz(rest) = prevInt(rest) - steadyCL;   %pauses within pauseTolerance: one length (2026-10-10)
        if isnan(steadyCL), pz(rest) = prevInt(rest); end
        gid = clusterAnchored(pz, opts.pauseTolerance);
        v2 = round(groupMedian(prevInt, gid) * 1000) / 1000;   %(ms: labels without rounding noise)
        val(rest) = v2(rest);
        step(rest & inR) = 1:nnz(rest & inR);
        refRole = 'steady';
    case 'rockerspeed'
        val = rockerSpeedAt(H, tt, opts.rockerLogDelay);
    case 'pulseduration'
        val = logValueAt(H, 'chargeDuration', stimCh, tt) / 1000;
    otherwise
        if strncmpi(by, 'log:', 4)
            val = logValueAt(H, strtrim(by(5:end)), stimCh, tt);
        else
            error('mda_groupBeats: unknown quantity ''%s''.', by);
        end
end
lbl = groupLabels(lower(by), val, role, by);
if strcmpi(by, 'pauseLength')                      %one group per pause: equal labels get the pause number
    ir = find(~isnan(step));
    if ~isempty(ir)
        [~, ~, iu] = unique(lbl(ir));
        dup = ir(ismember(iu, find(accumarray(iu, 1) > 1)));
        for i = dup', lbl{i} = sprintf('%s #%d', lbl{i}, step(i)); end
    end
end

% ------------------------------------------------------------------ group of every contraction
% stimulus of every contraction: first stimulus with t == t_stim, without t_stim the last stimulus <= t_peak -
% minStimToPeak (ismember / binary search instead of a search over all stimuli per contraction: long protocols,
% 2026-10-10)
% (2026-10-10: contraction elicited by an extra pulse: the last regular pulse at or before it; extra beat: the last
% regular pulse at or before the onset, if known)
k = nan(height(B), 1);
hasS = ~isnan(B.t_stim);
[isS, locS] = ismember(B.t_stim(hasS), tt);         %lowest index = find(tt == t_stim, 1)
kS = nan(nnz(hasS), 1); kS(isS) = locS(isS);
k(hasS) = kS;
sortedT = issorted(tt);
hasOn = ismember('t_onset', B.Properties.VariableNames) && ~(isfield(opts, 'stimAssignment') && ...
    strcmp(opts.stimAssignment, 'peak'));
for i = find(~hasS | isnan(k))'
    if hasS(i)
        x = B.t_stim(i);
    elseif hasOn && ~isnan(B.t_onset(i))
        x = B.t_onset(i);
    else
        x = B.t_peak(i) - opts.minStimToPeak;
    end
    if sortedT
        j = lastAtMost(tt, x);
    else
        j = find(tt <= x, 1, 'last');
    end
    if ~isempty(j), k(i) = j; end
end
bVal = nan(height(B), 1); bRole = repmat({''}, height(B), 1); bLbl = repmat({'unknown'}, height(B), 1);
bStep = nan(height(B), 1);
has = ~isnan(k);
bVal(has) = val(k(has)); bRole(has) = role(k(has)); bLbl(has) = lbl(k(has)); bStep(has) = step(k(has));
if strcmpi(by, 'rockerSpeed')                     %rocker speed at the peak
    bVal = rockerSpeedAt(H, B.t_peak, opts.rockerLogDelay);
    bLbl = groupLabels('rockerspeed', bVal, repmat({''}, height(B), 1), by);
end
B.group = bLbl;
B.groupValue = bVal;
B.groupRole = bRole;
B.groupStep = bStep;

% ------------------------------------------------------------------ FFR: steady state per frequency (2026-10-10)
selStep = containers.Map('KeyType', 'char', 'ValueType', 'double');
if strcmpi(by, 'pacingFrequency') && steadyN > 0 && height(B) > 0 && nS > 0
    eligible = ~isnan(B.amplitude);
    if strcmp(opts.beats, 'stimulated'), eligible = eligible & strcmp(B.beatType, 'stimulated'); end
    inRs = tt >= range(1) & tt <= range(2);
    % captured stimuli: followed by their stimulated contraction (any rocker state). Within the longest run, only
    % captured stimuli whose previous and next stimulus are captured, too, count (preceding and following interval of
    % the contraction = stimulus intervals), and of these the longest sequence of consecutive stimuli: partial capture
    % (e.g. 2:1) is no steady state at this frequency (2026-10-10)
    capt = false(nS, 1);
    okC = has & strcmp(B.beatType, 'stimulated') & ~isnan(B.amplitude);
    capt(k(okC)) = true;
    okS = capt & [false; capt(1:end-1)] & [capt(2:end); true];
    fb = {}; nc = {};
    for key = unique(B.group(has), 'stable')'
        rowsG = strcmp(B.group, key{1});
        js = find(inRs & strcmp(lbl, key{1}));
        if isempty(js) || isnan(val(js(1))), continue; end
        ru = runId(js);
        u = unique(ru);
        cnt = arrayfun(@(x) sum(ru == x), u);
        rSel = u(find(cnt == max(cnt), 1, 'last'));     %longest run (equal length: the later one)
        jRun = find(runId == rSel);
        jOk = jRun(okS(jRun));
        if isempty(jOk)
            nc{end+1} = key{1}; %#ok<AGROW>
        else
            sub = cumsum([1; diff(jOk) ~= 1]);
            cs = accumarray(sub, 1);
            jOk = jOk(sub == find(cs == max(cs), 1, 'last'));
        end
        cand = rowsG & has & eligible & ismember(k, jOk);
        switch opts.rocker
            case 'stopped'
                use = cand & ~B.rockerMoving;
                if ~any(use) && any(cand) && opts.ffrRockerFallback
                    use = cand;
                    fb{end+1} = key{1}; %#ok<AGROW>
                end
            case 'moving'
                use = cand & B.rockerMoving;
            otherwise
                use = cand;
        end
        iu = find(use);
        [~, o] = sort(B.t_peak(iu));
        iu = iu(o);
        iu = iu(max(1, end - steadyN + 1):end);
        B.included(rowsG) = false;
        B.included(iu) = true;
        selStep(key{1}) = step(find(runId == rSel, 1));
    end
    if ~isempty(fb)
        notes{end+1} = sprintf('no contraction with the rocker at rest at %s: contractions with the rocker moving used', ...
            strjoin(fb, ', '));
    end
    if ~isempty(nc)
        notes{end+1} = sprintf('no run of captured stimuli at %s (missed beats): no steady-state contractions', ...
            strjoin(nc, ', '));
    end
end

% ------------------------------------------------------------------ summary per group
inR = tt >= range(1) & tt <= range(2);
[isC, locC] = ismember(tt, C.stimTimes);
captured = false(nS, 1);
captured(isC) = C.stimCaptured(locC(isC));
capturedCertain = captured;                           %followed by a certain contraction (option 'detection')
if isfield(C, 'stimCapturedCertain'), capturedCertain(isC) = C.stimCapturedCertain(locC(isC)); end
duringC = false(nS, 1);                               %within a contraction elicited by another pulse
if isfield(C, 'stimDuringContraction') && numel(C.stimDuringContraction) == numel(C.stimTimes)
    duringC(isC) = C.stimDuringContraction(locC(isC));
end
% extra pulses of the range: group of the nearest regular pulse (pre-pulse: the next one, CCM pulse: the previous one)
xT = zeros(0, 1); xE = false(0, 1); xLbl = cell(0, 1);
if isfield(C, 'extraTimes') && ~isempty(C.extraTimes) && nS > 0
    xT = C.extraTimes(:); xE = false(size(xT));
    if isfield(C, 'extraElicited') && numel(C.extraElicited) == numel(xT), xE = C.extraElicited(:); end
    keepX = xT >= range(1) & xT <= range(2); xT = xT(keepX); xE = xE(keepX);
    xLbl = cell(numel(xT), 1);
    for i = 1:numel(xT)
        [~, j] = min(abs(tt - xT(i)));
        xLbl{i} = lbl{j};
    end
end
keys = unique([lbl(inR); B.group(B.t_peak >= range(1) & B.t_peak <= range(2))], 'stable');
% order: role (as listed below), then value
roleOrder = {'', 'S1', 'preS2', 'S2', 'postS2', 'steady', 'afterRest', 'postRest', 'other'};
kr = zeros(numel(keys), 1); kv = nan(numel(keys), 1); ks = nan(numel(keys), 1);
for q = 1:numel(keys)
    j = find(strcmp(lbl, keys{q}), 1);
    if ~isempty(j)
        kr(q) = find(strcmp(roleOrder, role{j})); kv(q) = val(j); ks(q) = step(j);
    else
        j = find(strcmp(B.group, keys{q}), 1);
        kr(q) = find(strcmp(roleOrder, B.groupRole{j})); kv(q) = B.groupValue(j); ks(q) = B.groupStep(j);
    end
end
kv2 = kv; kv2(isnan(kv2)) = inf;                   %unknown last
ks2 = ks; ks2(isnan(ks2)) = inf;
[~, o] = sortrows([kr kv2 ks2]);
keys = keys(o); kr = kr(o); kv = kv(o); ks = ks(o);
parts = cell(numel(keys), 1);
for q = 1:numel(keys)
    js = inR & strcmp(lbl, keys{q});
    Cg = C;
    Cg.stimTimes = tt(js);
    Cg.stimCaptured = captured(js);
    Cg.stimCapturedCertain = capturedCertain(js);
    Cg.stimDuringContraction = duringC(js);
    Cg.extraTimes = xT(strcmp(xLbl, keys{q}));
    Cg.extraElicited = xE(strcmp(xLbl, keys{q}));
    Bg = B(strcmp(B.group, keys{q}), :);
    T = mda_summarize(Bg, Cg, range);
    T.stimFrequency = 1 / median(prevInt(js), 'omitnan');
    if ~any(js), T.stimFrequency = nan; end
    capt = nan; reach = nan;
    if any(js), capt = 100 * mean(captured(js)); reach = 100 * mean(reached(js)); end
    T = addvars(T, capt, reach, 'After', 'missedBeats_percent', 'NewVariableNames', {'capture_percent', 'currentReached_percent'});
    T = [table(keys(q), kv(q), roleOrder(kr(q)), ks(q), {by}, 'VariableNames', {'group','groupValue','groupRole','groupStep','groupBy'}), T]; %#ok<AGROW>
    parts{q} = T;
end
Z = table(tt, prevInt, nextInt, role, val, step, lbl, captured, inR, 'VariableNames', ...
    {'t','prevInt','nextInt','role','value','step','group','captured','inRange'});
if isempty(parts)
    G = table();
    return;
end
G = vertcat(parts{:});
ref = nan;
if ~isempty(refRole)
    r = find(strcmp(G.groupRole, refRole), 1);
    if ~isempty(r), ref = G.amplitude_mean(r); end
end
G = addvars(G, 100 * G.amplitude_mean / ref, 'After', 'amplitude_SD', 'NewVariableNames', 'amplitude_pctOfRef');
irregular = double(G.amplitude_CV > opts.irregularCV);
irregular(isnan(G.amplitude_CV)) = nan;
G = addvars(G, irregular, 'After', 'amplitude_CV', 'NewVariableNames', 'irregular');
if selStep.Count > 0                               %FFR: number of the run summarized
    for q = 1:height(G)
        if isKey(selStep, G.group{q}), G.groupStep(q) = selStep(G.group{q}); end
    end
end
if strcmpi(by, 'pacingFrequency') && steadyN > 0 && opts.minGroupBeats > 0
    few = find(G.nContractions > 0 & G.nContractions < opts.minGroupBeats & ~isnan(G.groupValue));
    if ~isempty(few)
        notes{end+1} = sprintf('fewer than %d included contractions at %s', opts.minGroupBeats, strjoin( ...
            arrayfun(@(q) sprintf('%s (%d)', G.group{q}, G.nContractions(q)), few', 'UniformOutput', false), ', '));
    end
end
% post-rest potentiation: reference of each pause (2026-10-10)
if strcmpi(by, 'pauseLength') && ~strcmp(opts.prpReference, 'steady') && height(B) > 0 && ~isnan(steadyCL)
    regular = abs(prevInt - steadyCL) <= 0.05 * steadyCL;   %stimuli at the steady interval
    cOf = zeros(nS, 1);                            %stimulated contraction of every stimulus
    ok = has & strcmp(B.beatType, 'stimulated') & ~isnan(B.amplitude);
    cOf(k(ok)) = find(ok);
    post = find(strcmp(B.groupRole, 'postRest') & has & B.included);
    refOf = nan(height(B), 1);
    if strcmp(opts.prpReference, 'preceding')
        for i = post'
            lst = zeros(0, 1);
            j = k(i) - 1;
            while j >= 1 && regular(j)
                if cOf(j) > 0
                    lst(end+1, 1) = cOf(j); %#ok<AGROW>
                    if numel(lst) == opts.prpReferenceBeats, break; end
                end
                j = j - 1;
            end
            if ~isempty(lst), refOf(i) = median(B.amplitude(lst)); end
        end
    else                                           %'firstTrain'
        kp = find(strcmp(role, 'postRest') & tt >= range(1) & tt <= range(2), 1);
        lst = zeros(0, 1);
        if ~isempty(kp)
            j = kp - 1;
            while j >= 1 && regular(j)
                if cOf(j) > 0, lst(end+1, 1) = cOf(j); end %#ok<AGROW>
                j = j - 1;
            end
        end
        if ~isempty(lst), refOf(post) = mean(B.amplitude(lst)); end
    end
    for q = find(strcmp(G.groupRole, 'postRest'))'
        rq = post(strcmp(B.group(post), G.group{q}));
        G.amplitude_pctOfRef(q) = 100 * mean(B.amplitude(rq) ./ refOf(rq), 'omitnan');
    end
end
end


% =====================================================================================================
function gid = clusterValues(v, absTol, relTol)
% groups of similar values: sorted distinct values, a new group where the gap > absTol + relTol * lower value
gid = nan(size(v));
u = unique(v(~isnan(v)));
if isempty(u), return; end
br = [true; diff(u) > absTol + relTol * u(1:end-1)];
starts = u(br);
ok = ~isnan(v);
gid(ok) = discretize(v(ok), [starts; inf]);
end


function gid = clusterAnchored(v, relTol)
% groups of similar values: sorted distinct values, a new group where the value > (1 + relTol) x the first value of
% the group (no chaining)
gid = nan(size(v));
u = unique(v(~isnan(v)));
if isempty(u), return; end
starts = u(1);
for k = 2:numel(u)
    if u(k) > (1 + relTol) * starts(end) + 1e-12, starts(end+1, 1) = u(k); end %#ok<AGROW>
end
ok = ~isnan(v);
gid(ok) = discretize(v(ok), [starts; inf]);
end


function f = roundFrequency(f, res, resLow)
% frequency rounded to res (Hz) at >= 1 Hz, to resLow below 1 Hz (division by the integer 1 / res where possible:
% exact decimals, e.g. 1.5 instead of 1.5000000000000002)
lo = f < 1;
f(~lo) = roundTo(f(~lo), res);
f(lo) = roundTo(f(lo), resLow);
end


function x = roundTo(x, res)
q = 1 / res; if abs(q - round(q)) < 1e-9, q = round(q); end
x = round(x * q) / q;
end


function m = groupMedian(v, gid)
% median of the values of each group, for every element
m = nan(size(v));
for g = unique(gid(~isnan(gid)))'
    k = gid == g;
    m(k) = median(v(k));
end
end


function lbl = groupLabels(by, val, role, byName)
n = numel(val);
lbl = cell(n, 1);
for i = 1:n
    v = val(i);
    switch by
        case 'pacingfrequency'                    %label: the rounded frequency (roundFrequency)
            s = sprintf('%g Hz', v);
        case 's2interval'
            switch role{i}
                case 'S1', s = 'S1';
                case 'preS2', s = 'pre-S2';
                case 'other', s = 'other';
                case 'S2', s = sprintf('S2 %d ms', round(1000 * v));
                otherwise, s = sprintf('post-S2 %d ms', round(1000 * v));
            end
        case 'stimcurrent', s = sprintf('%g mA', v);
        case 'pauselength'
            switch role{i}
                case 'postRest', s = sprintf('rest %.3g s', v);
                case 'afterRest', s = 'after rest';
                otherwise, s = role{i};            %'steady', 'other'
            end
        case 'rockerspeed', s = sprintf('%g rpm', v);
        case 'pulseduration', s = sprintf('%g ms', v);
        otherwise, s = sprintf('%s %g', strtrim(byName(5:end)), v);
    end
    if isnan(v) && ~any(strcmp(role{i}, {'S1', 'preS2', 'other', 'steady', 'afterRest'})), s = 'unknown'; end
    lbl{i} = s;
end
end


function v = rockerSpeedAt(H, t, delay)
% rocker speed (rpm) at the times t from the 'rockerSpeed' entries (effective 'delay' s later); NaN before the first
R = H.rockerSpeedLog;
v = nan(size(t));
if isempty(R), return; end
[~, o] = sort(R(:,1));
R = R(o,:);
te = max(R(:,1) + delay, 0);
[te, last] = unique(te, 'last');                   %several entries at the same time: the last one
k = discretize(t, [te; inf]);
ok = ~isnan(k);
rv = R(last, 2);
v(ok) = rv(k(ok));
end


function rec = recordingStartRow(E)
% row of the 'Recording started' entry that starts the data of the .mdd file: the first one (main recording before
% 'parallel recording'); a later one only if the dataLogTime starts again (new recording in the same log file; a
% recording that was stopped and started again is appended to the .mdd file, its dataLogTime continues)
isRec = strcmpi(E.code, 'Recording') & contains(lower(E.text), 'started');
par = contains(lower(E.text), 'parallel');
c = find(isRec & ~par);
if isempty(c), c = find(isRec); end
rec = [];
if isempty(c), return; end
rec = c(1);
for j = reshape(c(2:end), 1, [])
    if E.t_file(j) < max(E.t_file(rec:j-1)) - 1, rec = j; end
end
end


function v = logValueAt(H, code, ch, t)
% value of the last log entry 'code' for channel ch (or 0) at or before the times t; entries before the start of the
% recording count from -Inf
E = mda_logEntries(H.logFile);
v = nan(size(t));
if isempty(E), return; end
rec = recordingStartRow(E);
tf = E.t_file;
if ~isempty(rec), tf(1:rec-1) = -inf; end
k = find(strcmpi(E.code, code) & (E.channel == ch | E.channel == 0));
if isempty(k), return; end
x = nan(numel(k), 1);
for i = 1:numel(k)
    num = sscanf(E.text{k(i)}, '%f', 1);
    if ~isempty(num), x(i) = num; end
end
te = tf(k);
[te, o] = sort(te);                                %stable
x = x(o);
[te, last] = unique(te, 'last');
x = x(last);
kk = discretize(t, [te; inf]);
ok = ~isnan(kk);
v(ok) = x(kk(ok));
end


function j = lastAtMost(x, v)
% index of the last element of the sorted vector x that is <= v ([] if none); binary search (same result as
% find(x <= v, 1, 'last')). TS 2026-10-10
lo = 1; hi = numel(x) + 1;          %first index with x > v
while lo < hi
    mid = floor((lo + hi) / 2);
    if x(mid) <= v, lo = mid + 1; else, hi = mid; end
end
j = lo - 1;
if j < 1, j = []; end
end
