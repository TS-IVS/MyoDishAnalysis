function R = mda_sliceRegister(resultsFolder, experiments, varargin)
%MDA_SLICEREGISTER  Slice register: one row per slice (channel of a setup from putting the slice in until it was taken
%out, the signal was lost or the data end), built from the results of MyoDishAnalysisWatch.
%
%   R = mda_sliceRegister(resultsFolder)                   all experiments; writes the register files
%   R = mda_sliceRegister(resultsFolder, {'expA'})         only these experiments (subfolders of resultsFolder)
%   R = mda_sliceRegister(..., 'newSliceHours', 2, 'write', true)
%
% Experiment = subfolder of the results folder (= subfolder of the raw folder). Series = recordings of one setup: the
% file name up to its number (rigA_X_0, rigA_X_1, ... --> series rigA_X); channels are followed through the
% recordings of a series in the order of their start.
% Inputs per recording (watcher, 'gaps', true): <name>_channels.csv (required), <name>_gaps.csv, <name>_overview.csv.
%
% A new slice begins in a channel
%   - with its first signal ('first signal'),
%   - after a chamber-out period with a comment such as 'new slice', 'replaced', 'exchanged', 'getauscht' within 5 min
%     of its start or end ('comment: ...'),
%   - when the label sliceID (<name>_labels.csv next to the recording) changes ('other sliceID'),
%   - with the signal after a recording without signal in this channel ('after a recording without signal') or after
%     >= 'newSliceHours' (default 2 h) without signal ('after # h without signal'), unless a comment within 5 min of
%     the start or end of the period says the slice was put back ('moved back', 'put back', 'reinserted', 'wieder
%     eingesetzt': same slice, nPutBack).
% Shorter chamber-out periods (medium change, looking at the slice) belong to the slice (nChamberOut, outHours). Which
% slice was put back is not in the signal: a slice exchanged within 'newSliceHours' without a comment or label stays
% one row. Technical periods (board group, controller, saturated) do not end a slice.
%
% R  table (and files <experiment>/<name of the experiment folder>_slices.csv, mda_slices_root.csv for recordings
%    directly in the results folder, mda_slices.csv with all experiments), one row per slice:
%      experiment, series, channel, slice (1, 2, ... per series and channel), setupID, sampleID, species, sliceID,
%      idDate (labels of the first recording of the slice; idDate = yymmdd of the file name, see the watcher)
%      startTime, endTime  clock time of the first and the last signal of the slice
%      daysInSetup     (endTime - startTime) in days
%      startReason     see above; insertedLater = not with the first signal of the series (or > newSliceHours later)
%      endStatus       'removed' (chamber out and not put back, or another slice afterwards), 'beating at end of data',
%                      'not beating at end of data' (no contraction in the last 30 min with signal), 'signal lost'
%                      (technical, until the end of the data), 'replaced (other sliceID)'
%      beatingAtEnd    a contraction within the last 30 min with signal
%      lastBeat        clock time of the end of the last 1-min window with contractions (overview)
%      lastAmplitude   amplitude (median, included contractions) of the last 1-min window with contractions
%      maxAmplitude    95th percentile of the 1-min amplitudes of the slice; lastAmplitude_pctMax = 100 * last / max
%      nBeats          contractions of the slice (all, from the overview)
%      dayStart, dayEnd  days since cultureStart (label) or since 00:00 of idDate (daySource); NaN for slices inserted
%                      later without cultureStart (they may come from another preparation)
%      nRecordings, firstRecording, lastRecording, nChamberOut, outHours, longestOut_min, nPutBack (long periods
%      without signal bridged by a put-back comment), nTechnical (periods),
%      endComments     comments of the log file about the end (removed, discarded, fixed, frozen, imaging, ...)
%    Without <name>_overview.csv ('overviewSeconds', 0) lastBeat, lastAmplitude, maxAmplitude and nBeats come from
%    <name>_channels.csv (whole recording: for a slice replaced within a recording only the later slice gets them).
%
% Python: myodish_analysis.slice_register (same files and results).
%
% TS 2026-10-08

P = struct('newSliceHours', 2, 'write', true);
for i = 1:2:numel(varargin)
    name = validatestring(varargin{i}, fieldnames(P));
    P.(name) = varargin{i+1};
end
res = char(resultsFolder);
[found, fnames] = findExperiments(res);
if nargin < 2 || (isnumeric(experiments) && isempty(experiments))
    todo = found;
else
    todo = found(ismember(found, cellstr(experiments)));
end
parts = cell(numel(todo), 1);
for k = 1:numel(todo)
    parts{k} = experiment(res, todo{k}, fnames{strcmp(found, todo{k})}, P.newSliceHours);
    if P.write, writetable(parts{k}, registerFile(res, todo{k})); end
end
if P.write                                             %all experiments: text of the experiment files
    fid = fopen(fullfile(res, 'mda_slices.csv'), 'w', 'n', 'UTF-8');
    fprintf(fid, '%s\n', strjoin(columns(), ','));
    for k = 1:numel(found)
        f = registerFile(res, found{k});
        if ~isfile(f), continue; end
        L = splitlines(fileread(f));
        L = L(2:end);
        L = L(~cellfun(@isempty, L));
        if ~isempty(L), fprintf(fid, '%s\n', L{:}); end
    end
    fclose(fid);
end
parts = parts(cellfun(@height, parts) > 0);
if isempty(parts)
    R = emptyRegister();
else
    R = vertcat(parts{:});
end
end


% =====================================================================================================
function c = columns()
c = {'experiment', 'series', 'channel', 'slice', 'setupID', 'sampleID', 'species', 'sliceID', 'idDate', 'startTime', ...
    'endTime', 'daysInSetup', 'startReason', 'insertedLater', 'endStatus', 'beatingAtEnd', 'lastBeat', ...
    'lastAmplitude', 'maxAmplitude', 'lastAmplitude_pctMax', 'nBeats', 'dayStart', 'dayEnd', 'daySource', ...
    'nRecordings', 'firstRecording', 'lastRecording', 'nChamberOut', 'outHours', 'longestOut_min', 'nPutBack', ...
    'nTechnical', 'endComments'};
end


function R = emptyRegister()
R = cell2table(cell(0, numel(columns())), 'VariableNames', columns());
end


function [found, fnames] = findExperiments(res)
% experiments (subfolders, '/' separated, '' = results folder) and the names of their <name>_channels.csv files
found = {}; fnames = {};
[found, fnames] = walk(res, '', found, fnames);
[found, o] = sort(found);
fnames = fnames(o);
for k = 1:numel(fnames), fnames{k} = sort(fnames{k}); end
end


function [found, fnames] = walk(res, rel, found, fnames)
if isempty(rel), D = dir(res); else, p = strsplit(rel, '/'); D = dir(fullfile(res, p{:})); end
names = {};
for k = 1:numel(D)
    if startsWith(D(k).name, '.'), continue; end
    if ~D(k).isdir && endsWith(D(k).name, '_channels.csv')
        names{end+1} = D(k).name(1:end-numel('_channels.csv')); %#ok<AGROW>
    end
end
if ~isempty(names), found{end+1} = rel; fnames{end+1} = names; end
sub = sort({D([D.isdir] & ~startsWith({D.name}, '.') & ~strcmp({D.name}, 'reports')).name});
for k = 1:numel(sub)
    if isempty(rel), r = sub{k}; else, r = [rel '/' sub{k}]; end
    [found, fnames] = walk(res, r, found, fnames);
end
end


function f = registerFile(res, e)
if isempty(e)
    f = fullfile(res, 'mda_slices_root.csv');
else
    p = strsplit(e, '/');
    f = fullfile(res, p{:}, [p{end} '_slices.csv']);
end
end


function T = readText(f, cols)
% all columns (or the columns cols) as text ('' for empty); numbers converted by the callers
L = splitlines(fileread(f));
L = L(~cellfun(@isempty, L));
if numel(L) <= 1                                       %header only (or empty file)
    if isempty(L), names = {}; else, names = strtrim(strsplit(L{1}, ',')); end
    T = cell2table(cell(0, numel(names)), 'VariableNames', names);
    return;
end
o = detectImportOptions(f, 'Delimiter', ',', 'TextType', 'char', 'VariableNamingRule', 'preserve');
o = setvartype(o, 'char');
if nargin > 1, o.SelectedVariableNames = intersect(cols, o.VariableNames, 'stable'); end
T = readtable(f, o);
end


function x = num(T, c)
if ~ismember(c, T.Properties.VariableNames), x = nan(height(T), 1); return; end
x = str2double(T.(c));
if isempty(x), x = zeros(0, 1); end
x = x(:);
end


function t = txt(T, c)
if ~ismember(c, T.Properties.VariableNames), t = repmat({''}, height(T), 1); return; end
t = T.(c);
end


function b = bool(T, c)
b = ismember(lower(strtrim(txt(T, c))), {'1', 'true'});
end


function [series, n] = seriesOf(name)
% file name up to its number (first part of digits only after the first part), number
p = strsplit(name, '_');
series = name; n = nan;
for i = 2:numel(p)
    if ~isempty(regexp(p{i}, '^\d+$', 'once'))
        series = strjoin(p(1:i-1), '_'); n = str2double(p{i});
        return;
    end
end
end


function t = seconds1970(s)
% clock text --> s since 1970 (NaN if empty / not readable): 'yyyy-mm-dd[ HH:MM[:SS]]' or 'dd.mm.yyyy[ HH:MM[:SS]]'
t = nan;
p = strsplit(strtrim(char(s)), ' ');
if isempty(p{1}) || numel(p) > 2, return; end
v = regexp(p{1}, '^(\d{4})-(\d{1,2})-(\d{1,2})$', 'tokens', 'once');
if isempty(v)
    v = regexp(p{1}, '^(\d{1,2})\.(\d{1,2})\.(\d{4})$', 'tokens', 'once');
    if isempty(v), return; end
    v = v([3 2 1]);
end
x = [str2double(v), 0, 0, 0];
if numel(p) == 2
    h = strsplit(p{2}, ':');
    if numel(h) < 2 || numel(h) > 3 || any(cellfun(@isempty, regexp(h, '^\d{1,2}$', 'once'))), return; end
    x(4:3+numel(h)) = str2double(h);
end
if x(2) < 1 || x(2) > 12 || x(3) < 1 || x(3) > eomday(x(1), x(2)) || x(4) > 23 || x(5) > 59 || x(6) > 59, return; end
t = (datenum(x(1), x(2), x(3)) - 719529) * 86400 + x(4) * 3600 + x(5) * 60 + x(6);
end


function s = clockText(t)
if isnan(t), s = ''; return; end
t = floor(t + 0.5);
d = floor(t / 86400); r = t - d * 86400;
v = datevec(d + 719529);
s = sprintf('%04d-%02d-%02d %02d:%02d:%02d', v(1), v(2), v(3), floor(r / 3600), floor(mod(r, 3600) / 60), ...
    mod(r, 60));
end


function R = experiment(res, e, names, hours)
if isempty(e), folder = res; else, p = strsplit(e, '/'); folder = fullfile(res, p{:}); end
recs = struct('name', {}, 'series', {}, 'num', {}, 'start', {}, 'L', {}, 'CH', {}, 'G', {}, 'O', {});
for k = 1:numel(names)
    n = names{k};
    CH = readText(fullfile(folder, [n '_channels.csv']));
    if height(CH) == 0, continue; end
    G = []; O = [];
    if isfile(fullfile(folder, [n '_gaps.csv'])), G = readText(fullfile(folder, [n '_gaps.csv'])); end
    if isfile(fullfile(folder, [n '_overview.csv']))
        O = readText(fullfile(folder, [n '_overview.csv']), ...
            {'channel', 't_from', 't_to', 'nBeats', 'amplitude', 'included'});
    end
    name = txt(CH, 'recording'); name = name{1};
    if isempty(name), name = n; end
    [series, nn] = seriesOf(name);
    st = txt(CH, 'recordingStart');
    L = num(CH, 'fileLength_s');
    recs(end+1) = struct('name', name, 'series', series, 'num', nn, 'start', seconds1970(st{1}), 'L', L(1), ...
        'CH', CH, 'G', G, 'O', O); %#ok<AGROW>
end
rows = {};
if ~isempty(recs)
    % order: series, start (unknown start: after the known ones), number, name
    K = table({recs.series}', isnan([recs.start]'), [recs.start]', [recs.num]', {recs.name}', ...
        'VariableNames', {'series', 'noStart', 'start', 'num', 'name'});
    K.start(K.noStart) = 0;
    K.num(isnan(K.num)) = inf;
    [~, o] = sortrows(K, {'series', 'noStart', 'start', 'num', 'name'});
    recs = recs(o);
    ser = unique({recs.series});
    for s = 1:numel(ser)
        S = recs(strcmp({recs.series}, ser{s}));
        prevEnd = nan;
        for r = 1:numel(S)                             %unknown start: end of the previous recording of the series
            if isnan(S(r).start)
                if ~isnan(prevEnd), S(r).start = prevEnd; else, S(r).start = 0; end
            end
            Lr = S(r).L; if isnan(Lr), Lr = 0; end
            prevEnd = S(r).start + Lr;
        end
        chans = [];
        for r = 1:numel(S), chans = [chans; num(S(r).CH, 'channel')]; end %#ok<AGROW>
        chans = unique(chans(~isnan(chans)));
        for c = chans'
            rows = [rows; channelRows(e, ser{s}, c, S, hours)]; %#ok<AGROW>
        end
    end
end
if isempty(rows)
    R = emptyRegister();
else
    R = cell2table(rows, 'VariableNames', columns());
end
end


function cur = newSlice(e, series, c, k, t, reason, row, seriesStart, hours)
cur = struct('e', e, 'series', series, 'c', c, 'k', k, 'start', t, 'reason', reason, ...
    'inserted', ~strcmp(reason, 'first signal') || t - seriesStart > hours * 3600, 'lab', row, 'last', t, ...
    'recs', {{}}, 'nOut', 0, 'outSec', 0, 'longest', 0, 'nTech', 0, 'nPutBack', 0, 'W', zeros(0, 5), ...
    'fb', zeros(0, 4), ...
    'endCand', '', 'endComments', '', 'closed', '');
end


function rows = channelRows(e, series, c, S, hours)
rx = 'new slice|neues slice|replac|exchang|getauscht|ausgetauscht|ersetzt|swap';
rxBack = 'moved back|put back|placed back|reinsert|re-insert|wieder eingesetzt|zur.{1,2}ckgesetzt';
rows = {};
cur = [];
k = 0;
outSince = [];
outText = '';
emptyBetween = false;
seriesStart = S(1).start;
fields = {'status', 'setupID', 'sampleID', 'species', 'sliceID', 'idDate', 'cultureStart', 'endComments'};
for r = 1:numel(S)
    CH = S(r).CH;
    i = find(num(CH, 'channel') == c, 1);
    if isempty(i), continue; end
    row = struct();
    for f = 1:numel(fields)
        v = txt(CH, fields{f});
        row.(fields{f}) = v{i};
    end
    St = S(r).start; L = S(r).L;
    if strcmp(row.status, 'no slice')
        if ~isempty(cur)
            if isempty(outSince), outSince = cur.last; end
            emptyBetween = true;
        end
        continue;
    end
    outs = zeros(0, 2); outC = {};                     %chamber-out periods of this channel (file time)
    G = S(r).G;
    if istable(G) && height(G) > 0
        j = find(num(G, 'channel') == c & strcmp(txt(G, 'type'), 'chamber out'));
        j = j(:);                                      %find of a scalar gives 1x0
        ga = num(G, 'from'); gb = num(G, 'to'); gt = txt(G, 'comments');
        outs = [ga(j), gb(j)]; outC = reshape(gt(j), [], 1);
        [outs, o] = sortrows(outs); outC = outC(o);
    end
    segs = zeros(0, 2); t = 0;
    for j = 1:size(outs, 1)
        if outs(j,1) > t, segs(end+1, :) = [t, outs(j,1)]; end %#ok<AGROW>
        t = max(t, outs(j,2));
    end
    if t < L, segs(end+1, :) = [t, L]; end %#ok<AGROW>
    for q = 1:size(segs, 1)
        a = segs(q,1); b = segs(q,2);
        tOn = St + a;
        cmOn = strjoin(outC(abs(outs(:,2) - a) < 1e-6)', ' ');
        sid = row.sliceID;
        if isempty(cur)
            k = k + 1;
            if k == 1, why = 'first signal'; else, why = 'signal after no slice'; end
            cur = newSlice(e, series, c, k, tOn, why, row, seriesStart, hours);
        else
            reason = '';
            if isempty(outSince)
                if a == 0 && ~isempty(sid) && ~isempty(cur.lab.sliceID) && ~strcmp(sid, cur.lab.sliceID)
                    reason = 'other sliceID';
                end
            else
                dur = tOn - outSince;
                t2 = [outText ' ' cmOn];
                [m1, m2] = regexpi(t2, rx, 'once');
                isLong = emptyBetween || dur >= hours * 3600;
                if ~isempty(m1)
                    reason = ['comment: ' strtrim(t2(max(1, m1 - 40):min(numel(t2), m2 + 40)))];
                elseif ~isempty(sid) && ~isempty(cur.lab.sliceID) && ~strcmp(sid, cur.lab.sliceID)
                    reason = 'other sliceID';
                elseif isLong && ~isempty(regexpi(t2, rxBack, 'once'))
                    cur.nPutBack = cur.nPutBack + 1;   %same slice put back (comment), however long it was out
                elseif emptyBetween
                    reason = 'after a recording without signal';
                elseif dur >= hours * 3600
                    reason = sprintf('after %.1f h without signal', dur / 3600);
                end
            end
            if ~isempty(reason)
                if ~isempty(outSince), cur.closed = 'removed'; else, cur.closed = 'replaced (other sliceID)'; end
                rows(end+1, :) = sliceRow(cur); %#ok<AGROW>
                k = k + 1;
                cur = newSlice(e, series, c, k, tOn, reason, row, seriesStart, hours);
            elseif ~isempty(outSince)
                cur.nOut = cur.nOut + 1;
                cur.outSec = cur.outSec + (tOn - outSince);
                cur.longest = max(cur.longest, tOn - outSince);
            end
        end
        outSince = []; outText = ''; emptyBetween = false;
        cur.last = St + b;
        if ~any(strcmp(cur.recs, S(r).name)), cur.recs{end+1} = S(r).name; end
        O = S(r).O;
        if istable(O) && height(O) > 0
            tf = num(O, 't_from'); tt = num(O, 't_to');
            sel = find(num(O, 'channel') == c & tf >= a - 1e-6 & tf < b);
            sel = sel(:);
            amp = num(O, 'amplitude'); nb = num(O, 'nBeats'); inc = bool(O, 'included');
            cur.W = [cur.W; St + tf(sel), St + min(tt(sel), b), amp(sel), nb(sel), double(inc(sel))];
        end
        if b < L - 1e-6
            outSince = St + b;
            outText = strjoin(outC(abs(outs(:,1) - b) < 1e-6)', ' ');
        end
    end
    if ~isempty(cur) && ~isempty(segs) && any(strcmp(cur.recs, S(r).name))
        nt = num(CH, 'nTechnical');
        if ~isnan(nt(i)), cur.nTech = cur.nTech + nt(i); end
        if segs(end, 2) >= L - 1e-6, cur.endCand = row.status; end
        cur.endComments = row.endComments;
        if ~istable(S(r).O)                            %no overview: values of the whole recording
            lc = num(CH, 'lastContraction_s'); la = num(CH, 'lastAmplitude'); ma = num(CH, 'maxAmplitude');
            nc = num(CH, 'nContractions');
            cur.fb(end+1, :) = [St + lc(i), la(i), ma(i), nc(i)];
        end
    end
end
if ~isempty(cur)
    if ~isempty(outSince), cur.closed = 'removed'; end
    rows(end+1, :) = sliceRow(cur);
end
end


function row = sliceRow(cur)
W = cur.W;
lastBeat = nan; lastAmp = nan; maxAmp = nan; nBeats = 0;
if ~isempty(W)
    tf = W(:,1); tt = W(:,2); amp = W(:,3); nb = W(:,4); inc = W(:,5) > 0;
    nBeats = sum(nb, 'omitnan');
    has = nb > 0;
    if any(has), lastBeat = max(tt(has)); end
    use = inc & has & ~isnan(amp);
    if ~any(use), use = has & ~isnan(amp); end
    if any(use)
        wins = unique(tf(use));                        %amplitude per window: mean of the rows weighted by nBeats
        aw = zeros(numel(wins), 1);
        for j = 1:numel(wins)
            u = use & tf == wins(j);
            aw(j) = sum(amp(u) .* nb(u)) / sum(nb(u));
        end
        lastAmp = aw(end);
        maxAmp = mprctile(aw, 95);
    end
elseif ~isempty(cur.fb)
    F = cur.fb;
    if any(~isnan(F(:,1)))
        [~, j] = max(F(:,1));
        lastBeat = F(j,1); lastAmp = F(j,2);
    end
    if any(~isnan(F(:,3))), maxAmp = max(F(:,3)); end
    nBeats = sum(F(:,4), 'omitnan');
end
beating = ~isnan(lastBeat) && cur.last - lastBeat <= 1800;
if ~isempty(cur.closed)
    status = cur.closed;
else
    switch cur.endCand
        case 'beating', status = 'beating at end of data';
        case 'not beating', status = 'not beating at end of data';
        otherwise, status = cur.endCand;
    end
end
lab = cur.lab;
base = nan; src = '';
if ~isempty(lab.cultureStart) && ~isnan(seconds1970(lab.cultureStart))
    base = seconds1970(lab.cultureStart); src = 'cultureStart';
elseif ~isempty(lab.idDate) && ~cur.inserted && ~isnan(seconds1970(lab.idDate))
    base = seconds1970(lab.idDate); src = 'idDate';
elseif ~isempty(lab.idDate)
    src = 'unknown (inserted later)';
end
pct = nan; if maxAmp > 0, pct = 100 * lastAmp / maxAmp; end
dS = nan; dE = nan;
if ~isnan(base), dS = (cur.start - base) / 86400; dE = (cur.last - base) / 86400; end
if isempty(cur.recs), r1 = ''; r2 = ''; else, r1 = cur.recs{1}; r2 = cur.recs{end}; end
row = {cur.e, cur.series, cur.c, cur.k, lab.setupID, lab.sampleID, lab.species, lab.sliceID, lab.idDate, ...
    clockText(cur.start), clockText(cur.last), (cur.last - cur.start) / 86400, cur.reason, double(cur.inserted), ...
    status, double(beating), clockText(lastBeat), lastAmp, maxAmp, pct, nBeats, dS, dE, src, numel(cur.recs), r1, ...
    r2, cur.nOut, cur.outSec / 3600, cur.longest / 60, cur.nPutBack, cur.nTech, cur.endComments};
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
