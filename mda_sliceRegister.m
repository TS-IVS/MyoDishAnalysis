function [R, out2] = mda_sliceRegister(resultsFolder, experiments, varargin)
%MDA_SLICEREGISTER  Slice register: one row per slice (channel of a setup from putting the slice in until it was taken
%out, the signal was lost or the data end), built from the results of MyoDishAnalysisWatch.
%
%   R = mda_sliceRegister(resultsFolder)                   all experiments; writes the register files
%   R = mda_sliceRegister(resultsFolder, {'expA'})         only these experiments (folders of the recordings in the raw
%                                                          folder, relative to it)
%   R = mda_sliceRegister(..., 'newSliceHours', 2, 'write', true)
%   R = mda_sliceRegister(..., 'trends', true, 'trendParameters', {'amplitude', 'diastolicForce', 'TTP90', 'TTR90'})
%       images of the series and the experiment (2026-10-15; the watcher with 'trends', true), see below
%   [series, number] = mda_sliceRegister('series', name)   series and number of a recording (name of the file)
%   d = mda_sliceRegister('resultFolder', rel, folders)    folder of the results of the recording rel (path relative to
%                                                          the raw folder) relative to the results folder of the
%                                                          watcher: folders 'series' (default) or 'flat'
%
% RESULT FOLDERS of the watcher ('folders', 2026-10-15):
%   'series' (default)  <experiment>/<series>/<nn>/ for recordings with a number (Setup1_ABC000101_3.mdd ->
%                       ABC000101/Setup1_ABC000101/03/; also its parallel recordings, e.g. ..._3_scheduleFile_...),
%                       <experiment>/<name>/ for recordings without a number
%   'flat'              <experiment>/ (all result files of the experiment in one folder, as before)
%   Both layouts are read (also mixed; a recording with results in both: the series layout).
%
% IMAGES ('trends', true; results with overview), per experiment:
%   <series>/<series>_ch<c>.png  (flat layout: trends/<series>_ch<c>.png) per numbered series and channel with at least
%       20 included contractions: per parameter of 'trendParameters' the whole time course of the series (left; all
%       slices of the channel, slice changes dashed, the last 24 h yellow, recordings with red flags of the analysis
%       report (mda_flags.csv) as red bars) and the last 24 h of the data (right; numbered comments with a list below);
%       mda_report 'course'
%   <series>/<series>_trends.xlsx  (flat: trends/) the data of these images: sheets course (channel, slice, bin = clock
%       time of the start of the bin, dayInCulture, nBeats = included contractions, the parameters = median of the
%       1-min values of the bin, binMinutes), last24h (channel, slice, window, nBeats, parameters per minute),
%       comments (channel, number as in the image, clockTime, text) and slices (rows of the register of the series)
%   <experiment>_overview.png  (mda_overview_root.png for recordings directly in the raw folder) all numbered series x
%       channels: amplitude over the whole time course, status at the end of the data of the last slice, last
%       amplitude, change in the last 24 h, % of the maximum, red frame = recordings with red flags (number); mda_report
%       'experiment'
%
% Experiment = folder of the recordings in the raw folder (relative to it). Series = recordings of one setup: the file
% name up to its number (rigA_X_0, rigA_X_1, ... --> series rigA_X); channels are followed through the recordings of a
% series in the order of their start.
% Inputs per recording (watcher, 'gaps', true): channels (required) and gaps (sheets of <name>.xlsx or <name>_channels.csv,
% <name>_gaps.csv), <name>_overview.csv(.gz); with 'trends' also events (sheet / <name>_events.csv) and the protocols
% (<name>_protocols.xlsx, sheet protocols, or <name>_protocols_protocols.csv).
% Parallel recordings of a main file are ignored (mda_index.csv: status 'parallel', or analysed while their main file
% has results; 2026-10-13/14): no contraction or stimulus is counted twice.
%
% A new slice begins in a channel
%   - with its first signal ('first signal'),
%   - after a chamber-out period with a comment such as 'new slice', 'replaced', 'exchanged', 'getauscht' within 5 min
%     of its start or end ('comment: <the comment>'), if the comment names the slice (slice, Schnitt, tissue, S<n>C<n>)
%     or nothing else that can be exchanged (not: medium exchange, setup / sensor board / electrode exchanged,
%     chamber replaced = the same slice in a new chamber; 2026-10-11),
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
%      calibration     'Calibration' values (AU per mN) of the channel in the recordings of the slice (';' separated)
%      calibrationChanged  1 if the calibration changed during the slice or differs from another row with the same
%                      sliceID (slice moved to another setup): force values / fold changes over time are only
%                      comparable after conversion to uN (2026-10-10)
%      endComments     comments of the log file about the end (removed, discarded, fixed, frozen, imaging, ...)
%    Without <name>_overview.csv ('overviewSeconds', 0) lastBeat, lastAmplitude, maxAmplitude and nBeats come from
%    <name>_channels.csv (whole recording: for a slice replaced within a recording only the later slice gets them).
%
% Python: myodish_analysis.slice_register (same files and results).
%
% TS 2026-10-08 (calibration 2026-10-10; parallel recordings ignored 2026-10-13; result folders of the series, course
% and overview images 2026-10-15)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

out2 = [];
if (ischar(resultsFolder) || isstring(resultsFolder)) && any(strcmp(resultsFolder, {'series', 'resultFolder'})) && ...
        ~isfolder(resultsFolder)
    switch char(resultsFolder)
        case 'series'                                  %[series, number] = mda_sliceRegister('series', name)
            [R, out2] = seriesOf(char(experiments));
        case 'resultFolder'                            %d = mda_sliceRegister('resultFolder', rel, folders)
            f = 'series'; if ~isempty(varargin), f = char(varargin{1}); end
            R = resultFolder(char(experiments), f);
    end
    return;
end
P = struct('newSliceHours', 2, 'write', true, 'trends', false, ...
    'trendParameters', {{'amplitude', 'diastolicForce', 'TTP90', 'TTR90'}});
for i = 1:2:numel(varargin)
    name = validatestring(varargin{i}, fieldnames(P));
    P.(name) = varargin{i+1};
end
res = char(resultsFolder);
[found, items] = findExperiments(res);
if nargin < 2 || (isnumeric(experiments) && isempty(experiments))
    todo = found;
else
    todo = found(ismember(found, cellstr(experiments)));
end
red = cell(0, 2);
if P.trends, red = redFlags(res); end
parts = cell(numel(todo), 1);
for k = 1:numel(todo)
    parts{k} = experiment(res, todo{k}, items{strcmp(found, todo{k})}, P, red);
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
    'nTechnical', 'calibration', 'calibrationChanged', 'endComments'};
end


function R = emptyRegister()
R = cell2table(cell(0, numel(columns())), 'VariableNames', columns());
end


function [found, items] = findExperiments(res)
% experiments ('/' separated folders of the recordings in the raw folder, '' = recordings directly in it) and their
% recordings (items{k}: struct array folder = folder of the results relative to res, name), from the result files
% (<name>_channels.csv or <name>.xlsx) in both layouts of the watcher (2026-10-15), without the parallel recordings of
% mda_index.csv (2026-10-13); a recording with results in both layouts: the series layout
L = walk(res, '', struct('folder', {}, 'name', {}));
found = {}; items = {};
if isempty(L), return; end
[skip, files] = indexFiles(res);
known = containers.Map();                              %folder|name -> experiment, from the files of the index
for k = 1:numel(files)
    rel = regexprep(files{k}, '\.mdd$', '', 'ignorecase');
    j = find(rel == '/', 1, 'last');
    if isempty(j), e = ''; n = rel; else, e = rel(1:j-1); n = rel(j+1:end); end
    for f = {e, resultFolder(rel, 'series')}
        key = [f{1} '|' n];
        if ~isKey(known, key), known(key) = e; end
    end
end
es = cell(numel(L), 1);
keep = true(numel(L), 1);
for k = 1:numel(L)
    key = [L(k).folder '|' L(k).name];
    if isKey(known, key), es{k} = known(key); else, es{k} = experimentOf(L(k).folder, L(k).name); end
    if isempty(es{k}), rel = L(k).name; else, rel = [es{k} '/' L(k).name]; end
    keep(k) = ~ismember([rel '.mdd'], skip);
end
L = L(keep); es = es(keep);
% the same recording in both layouts: the series layout
id = strcat(es, '|', {L.name}');
isSer = arrayfun(@(k) strcmp(L(k).folder, resultFolder(fullName(es{k}, L(k).name), 'series')), (1:numel(L))');
[~, o] = sortrows(table(id, ~isSer));
L = L(o); es = es(o); id = id(o);
[~, first] = unique(id, 'stable');
L = L(first); es = es(first);
found = unique(es);
items = cell(size(found));
for k = 1:numel(found)
    I = L(strcmp(es, found{k}));
    [~, o] = sort({I.name});
    items{k} = I(o);
end
end


function r = fullName(e, n)
if isempty(e), r = n; else, r = [e '/' n]; end
end


function e = experimentOf(rel, name)
% experiment of the results of recording name in the folder rel (relative to the results folder) without an index:
% <e>/<series>/<nn> or <e>/<name> (series layout), otherwise rel (flat layout)
p = strsplit(rel, '/');
if isempty(rel), p = {}; end
[s, num] = seriesOf(name);
e = rel;
if ~isnan(num) && numel(p) >= 2 && ~isempty(regexp(p{end}, '^\d+$', 'once')) && str2double(p{end}) == num && ...
        strcmp(p{end-1}, s)
    e = strjoin(p(1:end-2), '/');
elseif isnan(num) && ~isempty(p) && strcmp(p{end}, name)
    e = strjoin(p(1:end-1), '/');
end
end


function d = resultFolder(rel, folders)
% folder of the results of the recording rel (path relative to the raw folder, with or without .mdd) relative to the
% results folder ('/' separated, '' = the results folder): 'series' <folder>/<series>/<nn> (number with at least 2
% digits) or <folder>/<name> (no number); 'flat' <folder>
rel = strrep(char(rel), '\', '/');
j = find(rel == '/', 1, 'last');
if isempty(j), dr = ''; n = rel; else, dr = rel(1:j-1); n = rel(j+1:end); end
n = regexprep(n, '\.mdd$', '', 'ignorecase');
if strcmpi(folders, 'flat'), d = dr; return; end
[s, num] = seriesOf(n);
if isnan(num), sub = n; else, sub = sprintf('%s/%02d', s, num); end
if isempty(dr), d = sub; else, d = [dr '/' sub]; end
end


function [s, files] = indexFiles(res)
% files of mda_index.csv (relative paths) and those of parallel recordings ('.mdd' lower case): status 'parallel', or
% analysed ('parallel recording of <main> (...' in the message) while their main file has results (status ok): their
% data are in the results of the main file (2026-10-14)
s = {}; files = {};
f = fullfile(res, 'mda_index.csv');
if ~isfile(f), return; end
try
    o = detectImportOptions(f, 'FileType', 'text', 'Delimiter', ',');
    if ~all(ismember({'file', 'status', 'message'}, o.VariableNames)), return; end
    o.SelectedVariableNames = {'file', 'status', 'message'};
    o = setvartype(o, {'file', 'status', 'message'}, 'char');
    X = readtable(f, o);
catch
    return;
end
files = strrep(X.file, '\', '/');
ok = X.file(strcmp(X.status, 'ok'));
keep = strcmp(X.status, 'parallel');
for i = 1:height(X)
    m = regexpi(X.message{i}, '^parallel recording of (.+?\.mdd) \(', 'tokens', 'once');
    if ~isempty(m) && any(strcmp(ok, m{1})), keep(i) = true; end
end
s = regexprep(files(keep), '\.mdd$', '.mdd', 'ignorecase');
end


function T = redFlags(res)
% recordings (path relative to the raw folder without .mdd) and channels with red flags of the analysis report
% (mda_flags.csv, level 'check'), cell array {file, channel}
T = cell(0, 2);
f = fullfile(res, 'mda_flags.csv');
if ~isfile(f), return; end
try
    o = detectImportOptions(f, 'FileType', 'text', 'Delimiter', ',');
    if ~all(ismember({'file', 'channel', 'level'}, o.VariableNames)), return; end
    o.SelectedVariableNames = {'file', 'channel', 'level'};
    o = setvartype(o, {'file', 'level'}, 'char');
    o = setvartype(o, 'channel', 'double');
    X = readtable(f, o);
catch
    return;
end
X = X(strcmp(X.level, 'check'), :);
T = [regexprep(strrep(X.file, '\', '/'), '\.mdd$', '', 'ignorecase'), num2cell(X.channel)];
end


function L = walk(res, rel, L)
% folders with result files: (folder relative to res, name of the recording); not reports/, trends/ and the workbook
% <series>_trends.xlsx of a series folder
if isempty(rel), D = dir(res); else, p = strsplit(rel, '/'); D = dir(fullfile(res, p{:})); end
[~, here] = fileparts(rel);
names = {};
for k = 1:numel(D)
    if startsWith(D(k).name, '.') || D(k).isdir, continue; end
    if endsWith(D(k).name, '_channels.csv')
        names{end+1} = D(k).name(1:end-numel('_channels.csv')); %#ok<AGROW>
    elseif endsWith(D(k).name, '.xlsx') && ~endsWith(D(k).name, '_protocols.xlsx') && ...
            ~startsWith(D(k).name, '~$') && ~strcmp(D(k).name, [here '_trends.xlsx'])
        names{end+1} = D(k).name(1:end-5); %#ok<AGROW>  results as .xlsx (2026-10-14): channels sheet read later
    end
end
names = unique(names);
for k = 1:numel(names), L(end+1) = struct('folder', rel, 'name', names{k}); end %#ok<AGROW>
sub = sort({D([D.isdir] & ~startsWith({D.name}, '.') & ~ismember({D.name}, {'reports', 'trends'})).name});
for k = 1:numel(sub)
    if isempty(rel), r = sub{k}; else, r = [rel '/' sub{k}]; end
    L = walk(res, r, L);
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


function R = experiment(res, e, items, P, red)
hours = P.newSliceHours;
if isempty(e), folder = res; else, p = strsplit(e, '/'); folder = fullfile(res, p{:}); end
recs = struct('name', {}, 'series', {}, 'num', {}, 'start', {}, 'L', {}, 'CH', {}, 'G', {}, 'O', {}, 'E', {}, ...
    'PR', {}, 'folder', {});
oc = {'channel', 't_from', 't_to', 'nBeats', 'amplitude', 'included'};
if P.trends, oc = unique([oc, cellstr(P.trendParameters)], 'stable'); end
for k = 1:numel(items)
    n = items(k).name;
    if isempty(items(k).folder), d = res; else, p = strsplit(items(k).folder, '/'); d = fullfile(res, p{:}); end
    CH = readTab(d, n, 'channels');
    if isempty(CH) || height(CH) == 0, continue; end
    G = readTab(d, n, 'gaps');
    O = readTab(d, n, 'overview', oc);
    E = []; PR = [];
    if P.trends
        E = readTab(d, n, 'events', {'t_file', 'channel', 'category', 'text'});
        PR = readTab(d, [n '_protocols'], 'protocols', {'name', 'from', 'to'});
    end
    name = txt(CH, 'recording'); name = name{1};
    if isempty(name), name = n; end
    [series, nn] = seriesOf(name);
    st = txt(CH, 'recordingStart');
    L = num(CH, 'fileLength_s');
    recs(end+1) = struct('name', name, 'series', series, 'num', nn, 'start', seconds1970(st{1}), 'L', L(1), ...
        'CH', CH, 'G', G, 'O', O, 'E', E, 'PR', PR, 'folder', items(k).folder); %#ok<AGROW>
end
rows = {};
slices = {};                                           %slices (images)
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
        I = find(strcmp({recs.series}, ser{s}));
        S = recs(I);
        prevEnd = nan;
        for r = 1:numel(S)                             %unknown start: end of the previous recording of the series
            if isnan(S(r).start)
                if ~isnan(prevEnd), S(r).start = prevEnd; else, S(r).start = 0; end
            end
            Lr = S(r).L; if isnan(Lr), Lr = 0; end
            prevEnd = S(r).start + Lr;
        end
        recs(I) = S;
        chans = [];
        for r = 1:numel(S), chans = [chans; num(S(r).CH, 'channel')]; end %#ok<AGROW>
        chans = unique(chans(~isnan(chans)));
        for c = chans'
            [rr, cc] = channelRows(e, ser{s}, c, S, hours, P);
            rows = [rows; rr]; %#ok<AGROW>
            slices = [slices, cc]; %#ok<AGROW>
        end
    end
end
if isempty(rows)
    R = emptyRegister();
else
    R = cell2table(rows, 'VariableNames', columns());
    % calibration (2026-10-10): rows of the same sliceID (slice moved to another setup) with other calibration values
    sid = R.sliceID;
    for i = 1:height(R)
        if isempty(sid{i}) || isempty(R.calibration{i}), continue; end
        j = find(strcmp(sid, sid{i}) & ~cellfun(@isempty, R.calibration));
        if numel(unique(R.calibration(j))) > 1, R.calibrationChanged(i) = 1; end
    end
end
if P.trends && P.write
    seriesImages(folder, e, recs, slices, R, P, red);
end
end


function cur = newSlice(e, series, c, k, t, reason, row, seriesStart, hours)
cur = struct('e', e, 'series', series, 'c', c, 'k', k, 'start', t, 'reason', reason, ...
    'inserted', ~strcmp(reason, 'first signal') || t - seriesStart > hours * 3600, 'lab', row, 'last', t, ...
    'recs', {{}}, 'nOut', 0, 'outSec', 0, 'longest', 0, 'nTech', 0, 'nPutBack', 0, 'W', zeros(0, 5), ...
    'fb', zeros(0, 4), ...
    'endCand', '', 'endComments', '', 'closed', '', 'cal', {{}}, ...
    'TV', [], 'com', struct('t', {}, 'text', {}, 'category', {}), 'bands', zeros(0, 3), 'bandLabels', {{}});
end


function [rows, slices] = channelRows(e, series, c, S, hours, P)
rx = 'new slice|neues slice|replac|exchang|getauscht|ausgetauscht|ersetzt|swap';
% 2026-10-11: a comment with rx counts only if it names the slice (rxSlice) or names nothing else that can be exchanged
% (rxNot: medium exchange, setup / sensor board / electrode exchanged, chamber replaced = same slice in a new chamber)
rxSlice = 'slice|schnitt|tissue|gewebe|\<LMS\>|\<S\d+C\d+\>';
rxNot = ['medi(um|a|en)|buffer|solution|l(oe|.)sung|setup|sensor|board|platine|electrode|elektrode|magnet|offset|', ...
    'calibr|kalibr|chamber|kammer|software|controller|cable|kabel|lid\>|deckel|computer|\<pc\>|pump|lamp|rocker'];
rxBack = 'moved back|put back|placed back|reinsert|re-insert|wieder eingesetzt|zur.{1,2}ckgesetzt';
rows = {};
slices = {};
cur = [];
k = 0;
outSince = [];
outText = '';
emptyBetween = false;
seriesStart = S(1).start;
fields = {'status', 'setupID', 'sampleID', 'species', 'sliceID', 'idDate', 'cultureStart', 'endComments', 'calibration'};
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
                nc = newSliceComment({outText, cmOn}, rx, rxSlice, rxNot);
                isLong = emptyBetween || dur >= hours * 3600;
                if ~isempty(nc)
                    reason = ['comment: ' nc];
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
                slices{end+1} = cur; %#ok<AGROW>
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
        if ~isempty(row.calibration), cur.cal = [cur.cal, strsplit(row.calibration, ';')]; end
        O = S(r).O;
        if istable(O) && height(O) > 0
            tf = num(O, 't_from'); tt = num(O, 't_to');
            sel = find(num(O, 'channel') == c & tf >= a - 1e-6 & tf < b);
            sel = sel(:);
            amp = num(O, 'amplitude'); nb = num(O, 'nBeats'); inc = bool(O, 'included');
            cur.W = [cur.W; St + tf(sel), St + min(tt(sel), b), amp(sel), nb(sel), double(inc(sel))];
            if P.trends                                %values of the trend parameters (2026-10-14)
                V = zeros(numel(sel), numel(P.trendParameters));
                for j = 1:numel(P.trendParameters), x = num(O, P.trendParameters{j}); V(:, j) = x(sel); end
                cur.TV = [cur.TV; St + tf(sel), nb(sel), double(inc(sel)), V];
            end
        end
        if P.trends, cur = trendEvents(cur, S(r), c, St, a, b); end
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
    slices{end+1} = cur;
end
end


function cur = trendEvents(cur, rec, c, St, a, b)
% comments, protocols and periods without signal of channel c in the segment [a b] (file time) of a recording
E = rec.E;
if istable(E) && height(E) > 0
    t = num(E, 't_file'); ch = num(E, 'channel'); cat = txt(E, 'category'); tx = txt(E, 'text');
    for j = find(t >= a & t <= b & (ch == 0 | ch == c) & ismember(cat, {'comment', 'protocol'}))'
        cur.com(end+1) = struct('t', St + t(j), 'text', tx{j}, 'category', cat{j});
    end
end
PR = rec.PR;
if istable(PR) && height(PR) > 0
    pa = num(PR, 'from'); pb = num(PR, 'to'); pnm = txt(PR, 'name');
    for j = find(pb > a & pa < b)'
        cur.bands(end+1, :) = [St + max(pa(j), a), St + min(pb(j), b), 1];
        cur.bandLabels{end+1} = pnm{j};
    end
end
G = rec.G;
if istable(G) && height(G) > 0
    ga = num(G, 'from'); gb = num(G, 'to');
    for j = find(num(G, 'channel') == c & gb > a - 1 & ga < b + 1)'
        cur.bands(end+1, :) = [St + ga(j), St + gb(j), 2];
        cur.bandLabels{end+1} = '';
    end
end
end


function seriesImages(folder, e, recs, slices, R, P, red)
% images of the numbered series (2026-10-15): course image per channel and <series>_trends.xlsx in <experiment>/<series>/
% (results in the series layout) or <experiment>/trends/ (flat layout), overview image of the experiment
td = fullfile(folder, 'trends');
deleteMatching(td, '_ch\d+_slice\d+\.png$');          %slice images of 2026-10-14 (replaced by the course images)
[~, en] = fileparts(folder);
if isempty(e), ov = fullfile(folder, 'mda_overview_root.png'); en = '(results folder)';
else, ov = fullfile(folder, [en '_overview.png']); end
if isfile(ov), delete(ov); end
if isempty(recs) || isempty(slices), removeEmpty(td); return; end
pn = cellstr(P.trendParameters);
PI = mda_parameters();
un = repmat({''}, 1, numel(pn));
for j = 1:numel(pn)
    i = find(strcmp(PI(:, 1), pn{j}), 1);
    if ~isempty(i), un{j} = PI{i, 2}; elseif strcmp(pn{j}, 'beatsPerMinute'), un{j} = '1/min'; end
end
rk = cellfun(@(x) x.series, slices, 'UniformOutput', false);
redCh = zeros(0, 1); if ~isempty(red), redCh = cell2mat(red(:, 2)); end
ser = unique({recs(~isnan([recs.num])).series});
OV = struct('series', {}, 'c', {}, 'J', {}, 'red', {});    %cells of the overview image
for s = 1:numel(ser)
    S = recs(strcmp({recs.series}, ser{s}));
    isSer = any(~strcmp({S.folder}, e));               %results in <experiment>/<series>/<nn>/
    if isSer, out = fullfile(folder, ser{s}); old = td; else, out = td; old = fullfile(folder, ser{s}); end
    deleteSeriesOutputs(old, ser{s}); deleteSeriesOutputs(out, ser{s});
    if ~isSer, removeEmpty(old); end                   %series folder of the other layout without results
    J = find(strcmp(rk, ser{s}));
    if isempty(J), continue; end
    t0s = min(cellfun(@(x) x.start, slices(J))); t1s = max(cellfun(@(x) x.last, slices(J)));
    a0 = floor(t0s / 86400) * 86400;                   %time 0 of the images: midnight (bins of the clock)
    base = nan;                                        %day 0 of the series: first slice with cultureStart / idDate
    [~, o] = sort(cellfun(@(x) x.start, slices(J)));
    for j = reshape(J(o), 1, [])
        base = sliceBase(slices{j});
        if ~isnan(base), break; end
    end
    chans = unique(cellfun(@(x) x.c, slices(J)));
    Tc = {}; Tl = {}; Tm = {};
    for c = chans(:)'
        Jc = J(cellfun(@(x) x.c, slices(J)) == c);
        Rd = zeros(0, 2);                              %recordings with red flags in this channel
        for r = 1:numel(S)
            if any(strcmp(red(:, 1), fullName(e, S(r).name)) & redCh == c)
                Rd(end+1, :) = [S(r).start, S(r).start + max(S(r).L, 0)] - a0; %#ok<AGROW>
            end
        end
        OV(end+1) = struct('series', ser{s}, 'c', c, 'J', Jc, 'red', size(Rd, 1)); %#ok<AGROW>
        D = courseOf(slices(Jc), a0, t0s, t1s, base, pn, un, Rd);
        if isempty(D), continue; end
        cur = slices{Jc(end)};
        rowL = R(Jc(end), :);
        lt = labelLine(cur.lab);
        D.title = sprintf('%s  %s  %s  %s  channel %d%s', en, char(183), ser{s}, char(183), c, lt);
        D.subtitle = {statusLine(rowL, cur, numel(Jc), base), ['Left: dots = median per minute, line = median per ' ...
            'bin; yellow = last 24 h; dashed = new slice; red bar = red flags; light blue = protocol; grey = no ' ...
            'signal. Right: the last 24 h, purple = comments']};
        mda_report('course', fullfile(out, sprintf('%s_ch%d.png', ser{s}, c)), D);
        [a1, a2, a3] = mda_report('courseData', D);
        Tc{end+1} = courseRows(a1, c, 'bin_from', 'bin', D.t0, base); %#ok<AGROW>
        Tl{end+1} = courseRows(a2, c, 't_from', 'window', D.t0, nan); %#ok<AGROW>
        a3.clockTime = clockOf(D.t0, a3.t);
        a3 = addvars(removevars(a3, 't'), repmat(c, height(a3), 1), 'Before', 1, 'NewVariableNames', 'channel');
        Tm{end+1} = a3(:, {'channel', 'number', 'clockTime', 'text'}); %#ok<AGROW>
    end
    if ~isempty(Tc)
        x = fullfile(out, [ser{s} '_trends.xlsx']);
        if ~isfolder(out), mkdir(out); end
        writetable(vertcat(Tc{:}), x, 'Sheet', 'course');
        writetable(vertcat(Tl{:}), x, 'Sheet', 'last24h');
        writetable(vertcat(Tm{:}), x, 'Sheet', 'comments');
        writetable(R(strcmp(R.series, ser{s}), :), x, 'Sheet', 'slices');
    end
end
removeEmpty(td);
if ~isempty(OV), experimentImage(ov, en, OV, slices, R); end
end


function D = courseOf(sl, a0, t0s, t1s, base, pn, un, Rd)
% data of the course image of one channel (slices sl of the channel; times in s since 1970: a0 time 0 of the image,
% t0s, t1s start and end of the series)
D = [];
TV = []; com = struct('t', {}, 'text', {}, 'category', {}); B = zeros(0, 3); bl = {}; S = zeros(0, 3);
for k = 1:numel(sl)
    cur = sl{k};
    if ~isempty(cur.TV), TV = [TV; cur.TV]; end %#ok<AGROW>
    com = [com, cur.com]; %#ok<AGROW>
    if ~isempty(cur.bands), B = [B; cur.bands]; bl = [bl, cur.bandLabels]; end %#ok<AGROW>
    S(end+1, :) = [cur.start - a0, cur.last - a0, cur.k]; %#ok<AGROW>
end
if isempty(TV) || sum(TV(TV(:, 3) > 0, 2), 'omitnan') < 20, return; end
for j = 1:numel(com), com(j).t = com(j).t - a0; end
if ~isempty(B), B(:, 1:2) = B(:, 1:2) - a0; end
db = nan; if ~isnan(base), db = 719529 + base / 86400; end
D = struct('title', '', 'subtitle', {{}}, 't', TV(:, 1) - a0, 'w', 60, 'nb', TV(:, 2), 'inc', TV(:, 3) > 0, ...
    'V', TV(:, 4:end), 'names', {pn}, 'units', {un}, 't0', 719529 + a0 / 86400, 'xlim', [t0s t1s] - a0, ...
    'bands', B, 'bandLabels', {bl}, 'com', com, 'slices', S, 'last24', [max(t0s, t1s - 86400), t1s] - a0, ...
    'dayBase', db, 'red', Rd);
end


function T = courseRows(T, c, tcol, name, t0, base)
% rows of a sheet of <series>_trends.xlsx: channel, slice, clock time of tcol (s after t0) as name, dayInCulture
% (base: s since 1970; NaN: column not added), the other columns
t = T.(tcol);
T = removevars(T, tcol);
T = addvars(T, repmat(c, height(T), 1), 'Before', 1, 'NewVariableNames', 'channel');
T = addvars(T, clockOf(t0, t), 'After', 'slice', 'NewVariableNames', name);
if ~isnan(base) || strcmp(name, 'bin')
    d = (t0 - 719529) * 86400 + t;
    T = addvars(T, round((d - base) / 86400 * 1000) / 1000, 'After', name, 'NewVariableNames', 'dayInCulture');
end
end


function c = clockOf(t0, t)
c = repmat({''}, numel(t), 1);
if isempty(t), return; end
c = cellstr(datestr(round((t0 + t(:) / 86400) * 86400) / 86400, 'yyyy-mm-dd HH:MM:SS'));
end


function s = labelLine(lab)
v = {};
for nm = {'setupID', 'sliceID', 'species', 'sampleID'}
    if isfield(lab, nm{1}) && ~isempty(strtrim(lab.(nm{1}))), v{end+1} = strtrim(lab.(nm{1})); end %#ok<AGROW>
end
s = ''; if ~isempty(v), s = ['  ' char(183) '  ' strjoin(v, ['  ' char(183) '  '])]; end
end


function s = statusLine(r, cur, nSl, base)
% status of the last slice of a channel (first line of the subtitle of the course image)
dn = @(t) datestr(round(719529 * 86400 + t) / 86400, 'dd mmm HH:MM');
s = sprintf('slice %d since %s', cur.k, dn(cur.start));
if ~isnan(base), s = sprintf('%s (day %d)', s, floor(cur.start / 86400) - floor(base / 86400)); end
s = sprintf('%s: %s', s, r.endStatus{1});
if ~isempty(r.lastBeat{1})
    s = sprintf('%s; last contraction %s', s, datestr(datenum(r.lastBeat{1}, 'yyyy-mm-dd HH:MM:SS'), 'dd mmm HH:MM'));
end
if isfinite(r.lastAmplitude)
    s = sprintf('%s, amplitude %.0f %sN', s, r.lastAmplitude, char(181));
    if isfinite(r.lastAmplitude_pctMax), s = sprintf('%s (%.0f %% of the maximum of the slice)', s, r.lastAmplitude_pctMax); end
end
s = sprintf('%s; %d slice(s), %d recording(s) of the last slice', s, nSl, numel(cur.recs));
end


function experimentImage(ov, en, OV, slices, R)
% overview image of the experiment: series x channels (cells OV: series, c, J = slices, red = recordings with red flags)
ser = unique({OV.series});
chans = unique([OV.c]);
J = [OV.J];
t0 = min(cellfun(@(x) x.start, slices(J))); t1 = max(cellfun(@(x) x.last, slices(J)));
span = (t1 - t0) / 3600;
if span <= 30, bm = 30; elseif span <= 24 * 7, bm = 60; else, bm = 120; end
cells = struct('r', {}, 'c', {}, 't', {}, 'y', {}, 'sb', {}, 'status', {}, 'k', {}, 'amp', {}, 'pct', {}, ...
    'd24', {}, 'nRed', {});
nBeat = 0; nSl = 0;
for q = 1:numel(OV)
    Jq = OV(q).J;
    t = zeros(0, 1); y = zeros(0, 1); sb = zeros(0, 1);
    tw = zeros(0, 1); aw = zeros(0, 1);
    for k = 1:numel(Jq)
        cur = slices{Jq(k)};
        if k > 1, sb(end+1, 1) = (cur.start - t0) / 3600; end %#ok<AGROW>
        [w, a] = windowAmplitudes(cur.W);
        tw = [tw; w]; aw = [aw; a]; %#ok<AGROW>
        if isempty(w), continue; end
        [ub, ~, g] = unique(floor((w - t0) / 60 / bm));
        m = accumarray(g, a, [], @median);
        if ~isempty(t), t(end+1, 1) = NaN; y(end+1, 1) = NaN; end %#ok<AGROW>
        t = [t; (ub + 0.5) * bm / 60]; y = [y; m]; %#ok<AGROW>
    end
    last = slices{Jq(end)};
    r = R(Jq(end), :);
    d24 = nan;
    u = tw >= t1 - 86400;
    if any(u)
        ta = tw(u); va = aw(u);
        if max(ta) - min(ta) >= 4 * 3600
            a = median(va(ta <= min(ta) + 7200)); b = median(va(ta >= max(ta) - 7200));
            if a > 0, d24 = 100 * (b - a) / a; end
        end
    end
    cells(end+1) = struct('r', find(strcmp(ser, OV(q).series)), 'c', find(chans == OV(q).c), 't', t, 'y', y, ...
        'sb', sb, 'status', r.endStatus{1}, 'k', last.k, 'amp', r.lastAmplitude, 'pct', r.lastAmplitude_pctMax, ...
        'd24', d24, 'nRed', OV(q).red); %#ok<AGROW>
    nSl = nSl + 1;
    nBeat = nBeat + strcmp(r.endStatus{1}, 'beating at end of data');
end
dn = @(t) datestr(round(719529 * 86400 + t) / 86400, 'yyyy-mm-dd HH:MM');
[~, rep] = fileparts(ov); rep = strrep([rep '.pdf'], '_overview.pdf', '_report.pdf');
rep = strrep(rep, 'mda_overview_root.pdf', 'mda_report_root.pdf');
D = struct('title', sprintf('%s  %s  %d setup(s), %d channel(s) with a slice: %d beating at the end of their data', ...
    en, char(183), numel(ser), nSl, nBeat), 'subtitle', {{sprintf(['%s to %s (%.1f days); status of the last slice ' ...
    'of each channel at the end of its data; made %s (MyoDishAnalysis %s)'], dn(t0), dn(t1), span / 24, ...
    datestr(now, 'yyyy-mm-dd HH:MM'), mda_version())}}, 'rows', {ser}, 'cols', chans, 't0', 719529 + t0 / 86400, ...
    'xl', [0 max(span, 1)], 'last24', [max(0, span - 24), span], 'report', rep, 'cells', cells);
mda_report('experiment', ov, D);
end


function [w, a] = windowAmplitudes(W)
% amplitude per 1-min window (rows of W: t_from, t_to, amplitude, nBeats, included; several rows of a window weighted by
% their number of contractions; included contractions, otherwise all)
w = zeros(0, 1); a = zeros(0, 1);
if isempty(W), return; end
tf = W(:, 1); amp = W(:, 3); nb = W(:, 4); inc = W(:, 5) > 0;
use = inc & nb > 0 & ~isnan(amp);
if ~any(use), use = nb > 0 & ~isnan(amp); end
if ~any(use), return; end
[w, ~, g] = unique(tf(use));
a = accumarray(g, amp(use) .* nb(use)) ./ accumarray(g, nb(use));
end


function deleteSeriesOutputs(d, series)
% images and workbook of a series in folder d (before they are written again, or in the other layout)
if ~isfolder(d), return; end
deleteMatching(d, ['^' regexptranslate('escape', series) '_ch\d+\.png$']);
f = fullfile(d, [series '_trends.xlsx']);
if isfile(f), delete(f); end
end


function deleteMatching(d, rx)
if ~isfolder(d), return; end
D = dir(fullfile(d, '*.png'));
for k = 1:numel(D)
    if ~isempty(regexp(D(k).name, rx, 'once')), delete(fullfile(d, D(k).name)); end
end
end


function removeEmpty(d)
% folder d deleted if it is empty
if ~isfolder(d), return; end
D = dir(d);
if all(ismember({D.name}, {'.', '..'})), rmdir(d); end
end


function base = sliceBase(cur)
% day 0 of the culture of a slice (s since 1970): cultureStart (label), otherwise 00:00 of idDate (not for slices
% inserted later); NaN if unknown
lab = cur.lab;
base = nan;
if ~isempty(lab.cultureStart) && ~isnan(seconds1970(lab.cultureStart))
    base = seconds1970(lab.cultureStart);
elseif ~isempty(lab.idDate) && ~cur.inserted && ~isnan(seconds1970(lab.idDate))
    base = seconds1970(lab.idDate);
end
end


function T = readTab(folder, n, tab, cols)
% table tab of recording n as text: sheet of <n>.xlsx (2026-10-14) or <n>_<tab>.csv(.gz); [] if missing
T = [];
if nargin < 4, cols = {}; end
x = fullfile(folder, [n '.xlsx']);
if isfile(x)
    try
        sh = sheetnames(x);
    catch
        sh = {};
    end
    if ismember(tab, sh), T = readSheetText(x, tab, cols); return; end
end
f = fullfile(folder, [n '_' tab '.csv']);
tmp = '';
if ~isfile(f)
    if ~isfile([f '.gz']), return; end
    tmp = tempname; mkdir(tmp);                        %readtable does not read .gz
    gunzip([f '.gz'], tmp);
    f = fullfile(tmp, [n '_' tab '.csv']);
end
if isempty(cols), T = readText(f); else, T = readText(f, cols); end
if ~isempty(tmp), rmdir(tmp, 's'); end
end


function T = readSheetText(x, tab, cols)
% sheet as text table (as readText): numbers with 15 significant digits, '' for empty cells
o = detectImportOptions(x, 'Sheet', tab, 'VariableNamingRule', 'preserve');
o.VariableNamesRange = 'A1'; o.DataRange = 'A2';
if ~isempty(cols), o.SelectedVariableNames = intersect(cols, o.VariableNames, 'stable'); end
R = readtable(x, o);
T = table();
for v = R.Properties.VariableNames
    c = R.(v{1});
    if isnumeric(c) || islogical(c)
        c = double(c);
        s = arrayfun(@(z) sprintf('%.15g', z), c, 'UniformOutput', false);
        s(isnan(c)) = {''};
    elseif isdatetime(c)
        s = cellstr(string(c, 'yyyy-MM-dd HH:mm:ss'));
        s(isnat(c)) = {''};
    else
        s = cellstr(string(c));
        s(ismissing(string(c))) = {''};
    end
    T.(v{1}) = reshape(s, [], 1);
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
cal = '';                                          %calibration values of the slice in the order of time (2026-10-10)
if ~isempty(cur.cal)
    v = cur.cal([true, ~strcmp(cur.cal(2:end), cur.cal(1:end-1))]);
    cal = strjoin(v, ';');
end
calChanged = double(numel(unique(cur.cal)) > 1);
row = {cur.e, cur.series, cur.c, cur.k, lab.setupID, lab.sampleID, lab.species, lab.sliceID, lab.idDate, ...
    clockText(cur.start), clockText(cur.last), (cur.last - cur.start) / 86400, cur.reason, double(cur.inserted), ...
    status, double(beating), clockText(lastBeat), lastAmp, maxAmp, pct, nBeats, dS, dE, src, numel(cur.recs), r1, ...
    r2, cur.nOut, cur.outSec / 3600, cur.longest / 60, cur.nPutBack, cur.nTech, cal, calChanged, cur.endComments};
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

function c = newSliceComment(texts, rx, rxSlice, rxNot)
%the first comment (gap comments, separated by ' | ') that says a new slice was mounted (rx, and the slice named or
%nothing else that can be exchanged); '' if none. Each comment once (2026-10-11).
c = '';
parts = {};
for k = 1:numel(texts)
    parts = [parts, strtrim(regexp(char(texts{k}), '\s*\|\s*', 'split'))]; %#ok<AGROW>
end
parts = unique(parts(~cellfun(@isempty, parts)), 'stable');
for k = 1:numel(parts)
    x = parts{k};
    if ~isempty(regexpi(x, rx, 'once')) && (~isempty(regexpi(x, rxSlice, 'once')) || isempty(regexpi(x, rxNot, 'once')))
        c = x(1:min(end, 100));
        return;
    end
end
end
