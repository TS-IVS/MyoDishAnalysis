function [index, report] = MyoDishAnalysisWatch(rawFolder, resultsFolder, varargin)
%MYODISHANALYSISWATCH  Automatic analysis of new MyoDish recordings in a folder (watcher).
%
%   [index, report] = MyoDishAnalysisWatch(rawFolder, resultsFolder, ...)
%
%   Every pass searches rawFolder (with subfolders) for .mdd files and analyses those that are new, have changed, or
%   were analysed with another version, other options or (same implementation) other core code. The watcher only
%   calls the functions of MyoDishAnalysis (MyoDishAnalysis, mda_readMdd, mda_protocols): improvements of the analysis
%   apply to the watcher results as well; with 'reanalyze','outdated' (default) the affected recordings are analysed
%   again. Python: mda-watch (myodish_analysis.watch), same index and results.
%
% RESULTS per recording (resultsFolder/<subfolder of rawFolder>/)
%   <name>_contractions.csv, _summary.csv, _parameters.csv, _info.csv, _labels.csv (_rockerFilter.csv)
%       every single contraction of the whole recording; summary = one row per channel and time bin ('binMinutes',
%       default 60 min; range label = clock time of the bin start). Same as
%       MyoDishAnalysis(file, [], binsFrom, binsTo, 'labels', .., 'output', '<name>.csv', analysisOptions{:})
%   <name>_protocols_*.csv (if the log file contains stimulation protocols, 'protocols', true)
%       MyoDishAnalysis(file, [], [], [], 'protocol', 'all', 'output', '<name>_protocols.csv', ...): summary per
%       protocol, channel and group, protocolResults (FFR, ST thresholds, refractory periods, PRP)
%   Labels per channel (metadata): <name>_labels.csv next to the .mdd file (saved by the GUI), if present.
% resultsFolder/mda_index.csv
%   one row per recording: file (path relative to rawFolder), bytes, modified (time of the .mdd file, UTC), logBytes, status (ok / error /
%   running / noLog), version, implementation (MATLAB / Python), code (fingerprint of the core functions), options,
%   analyzed, seconds, nContractions, outputs, message. The same file is used by the MATLAB and the Python watcher.
% resultsFolder/reports/mda_report_<date>_<time>.txt
%   report of a pass with analysed recordings: per channel contractions, capture (% of the stimuli followed by a
%   contraction), extra beats (% of the detected contractions), mean amplitude in the first and last bin (bins with
%   >= 10 included contractions) and flags (no contractions, capture < flagCapture %, extra beats > flagExtraBeats %,
%   amplitude change > flagAmplitudeChange %).
%
% SKIPPED while written: files modified less than 'minFileAgeMinutes' ago (default 10), names starting with '.'
%   (rsync temporary files, hidden folders), and recordings whose log file has no 'Recording stopped' entry yet (status
%   'running') unless unchanged for 'incompleteAfterHours' (default 30 h, e.g. aborted recordings). Recordings without
%   log file get the status 'noLog'; they are checked again in every pass. Errors are retried when the file, the
%   version, the options or the code change, or with 'retryErrors'.
%
% OPTIONS (name/value pairs)
%   'interval', h            hours between passes (default 0 = one pass; > 0: runs until Ctrl+C)
%   'reanalyze', m           'outdated' (default) | 'new' (only new and changed files) | 'all'
%   'retryErrors', tf        analyse recordings with errors again (default false)
%   'fromDate', d            only files modified on/after this date ('yyyy-mm-dd', 'dd.mm.yyyy', 'yymmdd')
%   'filter', rx             regular expression on the path relative to rawFolder (case-insensitive)
%   'maxFiles', n            at most n recordings per pass
%   'dryRun', tf             only list what would be analysed
%   'minFileAgeMinutes', m   (default 10)       'incompleteAfterHours', h   (default 30)
%   'binMinutes', m          time bin of the summary (default 60)
%   'protocols', tf          analyse the stimulation protocols of the log file (default true)
%   'flagCapture', 'flagExtraBeats', 'flagAmplitudeChange'   report flags (default 90, 10, 30 %)
%   'quiet', tf              no messages
%   all other name/value pairs: analysis options of MyoDishAnalysis for all recordings, e.g. 'rockerFilter', true,
%   'rocker', 'stopped', 'threshold', 300 (not 'output', 'labels', 'metadata', 'protocol', 'groupBy')
%
% EXAMPLES
%   MyoDishAnalysisWatch('/data/myodish/raw', '/data/myodish/results', 'rockerFilter', true)
%   MyoDishAnalysisWatch(raw, results, 'fromDate', '2026-10-01', 'dryRun', true)
%   MyoDishAnalysisWatch(raw, results, 'interval', 24)        %one pass every 24 h (MATLAB stays busy)
%   Daily without an open MATLAB: the scheduler of the operating system with
%   matlab -batch "MyoDishAnalysisWatch('raw', 'results', 'quiet', true)"   or the Python version (mda-watch).
%
% TS 2026-10-08

W = struct('interval', 0, 'reanalyze', 'outdated', 'retryErrors', false, 'fromDate', '', 'filter', '', ...
    'maxFiles', inf, 'dryRun', false, 'minFileAgeMinutes', 10, 'incompleteAfterHours', 30, 'binMinutes', 60, ...
    'protocols', true, 'flagCapture', 90, 'flagExtraBeats', 10, 'flagAmplitudeChange', 30, 'quiet', false);
wNames = fieldnames(W);
args = {};
for i = 1:2:numel(varargin)
    if i == numel(varargin), error('MyoDishAnalysisWatch: options as name/value pairs.'); end
    k = find(strcmpi(wNames, char(varargin{i})), 1);
    if ~isempty(k)
        W.(wNames{k}) = varargin{i+1};
    elseif ismember(lower(char(varargin{i})), {'output', 'labels', 'metadata', 'protocol', 'groupby'})
        error('MyoDishAnalysisWatch: ''%s'' is set by the watcher (labels per channel: <name>_labels.csv).', varargin{i});
    else
        args(end+1:end+2) = {char(varargin{i}), varargin{i+1}}; %#ok<AGROW>
    end
end
if ~ismember(lower(W.reanalyze), {'outdated', 'new', 'all'})
    error('MyoDishAnalysisWatch: ''reanalyze'': ''outdated'', ''new'' or ''all'' expected.');
end
raw = absPath(rawFolder);
res = absPath(resultsFolder);
if ~isfolder(raw), error('MyoDishAnalysisWatch: folder not found: %s', raw); end
oa = optionArgs(args);
mda_options(oa{:});                                    %unknown analysis options: error now
while true
    [index, report] = onePass(raw, res, W, args);
    if W.interval <= 0, return; end
    if ~W.quiet
        fprintf('next pass %s (Ctrl+C stops)\n', datestr(now + W.interval / 24, 'yyyy-mm-dd HH:MM'));
    end
    pause(W.interval * 3600);
end
end


% =====================================================================================================
function [X, report] = onePass(raw, res, W, args)
if ~isfolder(res), mkdir(res); end
lock = fullfile(res, 'mda_watch.lock');
report = '';
d = dir(lock);
if ~isempty(d) && (now - d.datenum) * 24 < 12
    report = sprintf('another watcher is running (lock file %s, younger than 12 h): pass skipped', lock);
    if ~W.quiet, fprintf('%s\n', report); end
    X = readIndex(res);
    return;
end
if ~W.dryRun
    fid = fopen(lock, 'w'); fprintf(fid, '%d %s\n', feature('getpid'), datestr(now, 'yyyy-mm-dd HH:MM:SS')); fclose(fid);
    cleanup = onCleanup(@() deleteIfExists(lock)); %#ok<NASGU>
end
[X, report] = scanAndAnalyse(raw, res, W, args);
end


function [X, report] = scanAndAnalyse(raw, res, W, args)
report = '';
X = readIndex(res);
version = mda_version();
code = codeFingerprint();
otext = optionsText(args, W.binMinutes, W.protocols);
fromDate = parseDate(W.fromDate);
oa = optionArgs(args);
hopts = mda_options(oa{:});
t = now;
F = findRecordings(raw);
todo = {};
for k = 1:numel(F)
    rel = F(k).rel; f = F(k).file;
    if ~isempty(W.filter) && isempty(regexpi(rel, W.filter, 'once')), continue; end
    logf = [f(1:end-4) '_log.log'];
    dl = dir(logf);
    logBytes = -1; lastChange = F(k).datenum;
    if ~isempty(dl), logBytes = dl.bytes; lastChange = max(lastChange, dl.datenum); end
    if ~isnan(fromDate) && F(k).datenum < fromDate, continue; end
    if (t - lastChange) * 1440 < W.minFileAgeMinutes, continue; end     %still written / copied
    modified = utcText(F(k).datenum);
    i = find(strcmp(X.file, rel), 1);
    if isempty(i), r = []; else, r = X(i,:); end
    why = reason(r, F(k).bytes, modified, logBytes, version, code, otext, W);
    if ~isempty(why)
        todo(end+1,:) = {rel, f, logf, F(k).bytes, modified, logBytes, lastChange, why}; %#ok<AGROW>
    end
end
todo = todo(1:min(size(todo,1), W.maxFiles), :);
if ~W.quiet
    fprintf('%s  %s: %d recording(s) to analyse\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), raw, size(todo,1));
end
if W.dryRun
    for k = 1:size(todo,1), fprintf('  %s  (%s)\n', todo{k,1}, todo{k,8}); end
    return;
end
blocks = {};
for k = 1:size(todo,1)
    [rel, f, ~, nBytes, modified, logBytes, lastChange, why] = todo{k,:};
    row = struct('file', rel, 'bytes', nBytes, 'modified', modified, 'logBytes', logBytes, 'status', '', ...
        'version', version, 'implementation', 'MATLAB', 'code', code, 'options', otext, ...
        'analyzed', datestr(now, 'yyyy-mm-dd HH:MM:SS'), 'seconds', nan, 'nContractions', nan, 'outputs', '', 'message', '');
    tic0 = tic;
    block = '';
    if logBytes < 0
        row.status = 'noLog'; row.message = 'no log file <name>_log.log';
    else
        try
            H = mda_readMdd(f, [], [], hopts);
            if H.recordingStopped == 0 && (t - lastChange) * 24 < W.incompleteAfterHours
                row.status = 'running'; row.message = 'no ''Recording stopped'' in the log file yet';
            else
                if ~W.quiet, fprintf('  %s (%s) ...\n', rel, why); end
                [row, block] = analyse(f, rel, H, res, row, W, args);
            end
        catch ME
            row.status = 'error';
            row.message = clean(sprintf('%s: %s', ME.identifier, ME.message));
        end
    end
    row.seconds = round(toc(tic0) * 10) / 10;
    if any(strcmp(row.status, {'ok', 'error'}))
        if isempty(block), block = sprintf('%s\n  %s: %s\n', rel, row.status, row.message); end
        blocks{end+1} = block; %#ok<AGROW>
    end
    if ~W.quiet && ~strcmp(row.status, 'ok'), fprintf('  %s: %s: %s\n', rel, row.status, row.message); end
    X = setRow(X, row);
    writeIndex(res, X);
end
if ~isempty(blocks)
    report = sprintf('MyoDishAnalysis %s (MATLAB) watcher report %s\nraw folder: %s\nresults:    %s\noptions:    %s\n\n%s', ...
        version, datestr(now, 'yyyy-mm-dd HH:MM:SS'), raw, res, otext, strjoin(blocks, newline));
    dr = fullfile(res, 'reports');
    if ~isfolder(dr), mkdir(dr); end
    fid = fopen(fullfile(dr, ['mda_report_' datestr(now, 'yyyy-mm-dd_HHMMSS') '.txt']), 'w', 'n', 'UTF-8');
    fwrite(fid, unicode2native(report, 'UTF-8'));
    fclose(fid);
    if ~W.quiet, fprintf('\n%s\n', report); end
end
end


function why = reason(r, nBytes, modified, logBytes, version, code, otext, W)
% reason to analyse the recording ('' = nothing to do)
why = '';
if isempty(r), why = 'new'; return; end
old = parseTime(r.modified{1});
if r.bytes ~= nBytes || r.logBytes ~= logBytes || isnan(old) || abs(old - parseTime(modified)) * 86400 > 2
    why = 'changed'; return;
end
status = r.status{1};
if any(strcmp(status, {'running', 'noLog'})), why = ['check ' status]; return; end
outdated = '';
if ~strcmp(r.version{1}, version)
    outdated = 'other version';
elseif ~strcmp(r.options{1}, otext)
    outdated = 'other options';
elseif strcmp(r.implementation{1}, 'MATLAB') && ~strcmp(r.code{1}, code)
    outdated = 'core code changed';
end
mode = lower(W.reanalyze);
if strcmp(status, 'error')
    if W.retryErrors, why = 'retry error';
    elseif ~isempty(outdated) && ~strcmp(mode, 'new'), why = ['retry error, ' outdated];
    end
    return;
end
if strcmp(mode, 'all')
    why = 'reanalyze all';
elseif strcmp(mode, 'outdated') && ~isempty(outdated)
    why = outdated;
end
end


function [row, block] = analyse(f, rel, H, res, row, W, args)
% the analyses of one recording (only calls of the MyoDishAnalysis functions)
[~, n] = fileparts(f);
outDir = fullfile(res, fileparts(rel));
if ~isfolder(outDir), mkdir(outDir); end
meta = [f(1:end-4) '_labels.csv'];
if ~isfile(meta), meta = []; end
[fr, to, labels] = bins(H, W.binMinutes * 60);
[C, S, info] = MyoDishAnalysis(f, [], fr, to, 'labels', labels, 'metadata', meta, 'quiet', true, ...
    'output', fullfile(outDir, [n '.csv']), args{:});
outputs = {[n '.csv']};
msgs = info.notes(:)';
if W.protocols
    try
        P = mda_protocols(H);
        if height(P) > 0
            MyoDishAnalysis(f, [], [], [], 'protocol', 'all', 'metadata', meta, 'quiet', true, ...
                'output', fullfile(outDir, [n '_protocols.csv']), args{:});
            outputs{end+1} = [n '_protocols.csv'];
        end
    catch ME
        msgs{end+1} = sprintf('protocols: %s: %s', ME.identifier, ME.message);
    end
end
row.status = 'ok';
row.nContractions = height(C);
row.outputs = strjoin(outputs, '; ');
row.message = clean(strjoin(msgs, ' | '));
block = reportBlock(rel, H, S, W);
end


function [fr, to, labels] = bins(H, binS)
T = H.totalSeconds;
if binS > 0, edges = 0:binS:T; else, edges = 0; end
if edges(end) >= T && numel(edges) > 1, edges(end) = []; end   %as numpy.arange: T itself is no bin start
if numel(edges) > 1 && T - edges(end) <= 1, edges(end) = []; end  %no bin shorter than 1 s at the end
fr = edges(:);
to = [fr(2:end) - 1e-9; T];                         %half-open bins: no contraction twice
labels = cell(numel(fr), 1);
for k = 1:numel(fr)
    if ~isnan(H.recordingStart)
        sec = round((H.recordingStart - 719529) * 86400 + fr(k));
        labels{k} = char(datetime(sec, 'ConvertFrom', 'posixtime', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    else
        labels{k} = sprintf('%g-%g min', fr(k) / 60, round(to(k)) / 60);
    end
end
end


function block = reportBlock(rel, H, S, W)
start = '';
if ~isnan(H.recordingStart)
    sec = round((H.recordingStart - 719529) * 86400);
    start = [', start ' char(datetime(sec, 'ConvertFrom', 'posixtime', 'Format', 'yyyy-MM-dd HH:mm:ss'))];
end
lines = {sprintf('%s  (%.2f h, %d channels%s)', rel, H.totalSeconds / 3600, numel(H.dataChannels), start), ...
    '  channel  contractions  capture%  extra%  amplitude first/last bin (uN)  change%  flags'};
for ch = unique(S.channel)'
    s = S(S.channel == ch, :);
    nDet = sum(s.nDetected); nInc = sum(s.nContractions);
    nStim = sum(s.nStimuli); nMiss = sum(s.nMissedBeats); nExtra = sum(s.nExtraBeats);
    cap = nan; extra = nan; a1 = nan; a2 = nan; chg = nan;
    if nStim > 0, cap = 100 * (1 - nMiss / nStim); end
    if nDet > 0, extra = 100 * nExtra / nDet; end
    good = s(s.nContractions >= 10, :);
    if height(good) > 0, a1 = good.amplitude_mean(1); a2 = good.amplitude_mean(end); end
    if height(good) > 1 && a1 > 0, chg = 100 * (a2 - a1) / a1; end
    flags = {};
    if nDet == 0
        flags{end+1} = 'no contractions'; %#ok<AGROW>
    elseif cap < W.flagCapture
        flags{end+1} = sprintf('capture < %g %%', W.flagCapture); %#ok<AGROW>
    end
    if extra > W.flagExtraBeats, flags{end+1} = sprintf('extra beats > %g %%', W.flagExtraBeats); end %#ok<AGROW>
    if abs(chg) > W.flagAmplitudeChange, flags{end+1} = sprintf('amplitude change > %g %%', W.flagAmplitudeChange); end %#ok<AGROW>
    lines{end+1} = sprintf('  %7d  %12d  %8s  %6s  %14s / %-14s  %7s  %s', ch, nInc, f1(cap), f1(extra), f1(a1), ...
        f1(a2), f1(chg), strjoin(flags, ', ')); %#ok<AGROW>
end
block = sprintf('%s\n', lines{:});
end


% ===================================================================================================== index
function X = emptyIndex()
X = table(cell(0,1), zeros(0,1), cell(0,1), zeros(0,1), cell(0,1), cell(0,1), cell(0,1), cell(0,1), cell(0,1), ...
    cell(0,1), zeros(0,1), zeros(0,1), cell(0,1), cell(0,1), 'VariableNames', indexColumns());
end

function c = indexColumns()
c = {'file','bytes','modified','logBytes','status','version','implementation','code','options','analyzed', ...
    'seconds','nContractions','outputs','message'};
end

function X = readIndex(res)
f = fullfile(res, 'mda_index.csv');
X = emptyIndex();
if ~isfile(f), return; end
txt = fileread(f);
if numel(regexp(txt, '\n', 'match')) < 2, return; end   %header only
o = detectImportOptions(f, 'FileType', 'text', 'Delimiter', ',');
cols = indexColumns();
num = {'bytes', 'logBytes', 'seconds', 'nContractions'};
present = intersect(o.VariableNames, cols, 'stable');
o.SelectedVariableNames = present;
o = setvartype(o, intersect(present, num), 'double');
o = setvartype(o, setdiff(present, num), 'char');
R = readtable(f, o);
for k = 1:numel(cols)
    if ~ismember(cols{k}, R.Properties.VariableNames)
        if ismember(cols{k}, num), R.(cols{k}) = nan(height(R), 1); else, R.(cols{k}) = repmat({''}, height(R), 1); end
    end
end
X = R(:, cols);
end

function X = setRow(X, row)
cols = indexColumns();
i = find(strcmp(X.file, row.file), 1);
if isempty(i)
    i = height(X) + 1;
    X = [X; emptyRow()];
end
for k = 1:numel(cols)
    v = row.(cols{k});
    if ischar(v), X.(cols{k}){i} = v; else, X.(cols{k})(i) = v; end
end
end

function R = emptyRow()
R = table({''}, nan, {''}, nan, {''}, {''}, {''}, {''}, {''}, {''}, nan, nan, {''}, {''}, 'VariableNames', indexColumns());
end

function writeIndex(res, X)
f = fullfile(res, 'mda_index.csv');
tmp = [f '.tmp'];
writetable(X, tmp, 'FileType', 'text', 'Delimiter', ',');
movefile(tmp, f, 'f');
end


% ===================================================================================================== helpers
function F = findRecordings(raw)
D = dir(fullfile(raw, '**', '*'));
D = D(~[D.isdir]);
keep = ~cellfun(@isempty, regexpi({D.name}, '\.mdd$', 'once')) & ~startsWith({D.name}, '.');
D = D(keep);
F = struct('rel', {}, 'file', {}, 'bytes', {}, 'datenum', {});
for k = 1:numel(D)
    f = fullfile(D(k).folder, D(k).name);
    rel = strrep(f(numel(raw)+2:end), filesep, '/');
    if any(startsWith(strsplit(rel, '/'), '.')), continue; end   %hidden folders
    F(end+1) = struct('rel', rel, 'file', f, 'bytes', D(k).bytes, 'datenum', D(k).datenum); %#ok<AGROW>
end
[~, o] = sort({F.rel});
F = F(o);
end

function c = codeFingerprint()
% adler32 (hex) of the core functions (MyoDishAnalysis.m, mda_*.m except the tests)
p = fileparts(which('MyoDishAnalysis'));
D = dir(fullfile(p, 'mda_*.m'));
names = sort([{'MyoDishAnalysis.m'}, {D.name}]);
names = names(~startsWith(names, 'mda_test'));
A = 1; B = 0;
for k = 1:numel(names)
    fid = fopen(fullfile(p, names{k}), 'r');
    b = [double(uint8(names{k})), double(fread(fid, inf, 'uint8=>uint8'))'];
    fclose(fid);
    n = numel(b);
    B = mod(B + n * A + sum((n:-1:1) .* b), 65521);
    A = mod(A + sum(b), 65521);
end
c = sprintf('%08x', B * 65536 + A);
end

function s = optionsText(args, binMinutes, protocols)
% canonical text of the options that change the results (index column 'options'; same text as in Python)
keys = {'binminutes', 'protocols'}; vals = {valueText(binMinutes), valueText(logical(protocols))};
for i = 1:2:numel(args)
    k = lower(args{i});
    j = find(strcmp(keys, k), 1);
    if isempty(j), keys{end+1} = k; vals{end+1} = valueText(args{i+1}); %#ok<AGROW>
    else, vals{j} = valueText(args{i+1}); end
end
[keys, o] = sort(keys);
vals = vals(o);
s = strjoin(strcat(keys, '=', vals), '; ');
end

function s = valueText(v)
if isempty(v) && ~ischar(v)
    s = '';
elseif ischar(v) || isstring(v)
    s = char(v);
elseif islogical(v) && isscalar(v)
    s = char('0' + v);
elseif isnumeric(v) && isscalar(v)
    s = sprintf('%.10g', v);
elseif isnumeric(v) || islogical(v)
    s = ['[' strjoin(arrayfun(@(x) sprintf('%.10g', x), double(v(:)'), 'UniformOutput', false), ' ') ']'];
elseif iscell(v)
    s = ['{' strjoin(cellfun(@(x) valueText(x), v(:)', 'UniformOutput', false), ' ') '}'];
else
    s = ['<' class(v) '>'];
end
end

function a = optionArgs(args)
% analysis options without the keywords of MyoDishAnalysis that are no mda_options
keep = true(size(args));
for i = 1:2:numel(args)
    if ismember(lower(args{i}), {'showfigures', 'quiet', 'chunkseconds'}), keep(i:i+1) = false; end
end
a = args(keep);
end

function d = parseDate(s)
d = nan;
if isempty(s), return; end
if isnumeric(s), d = floor(s); return; end
if isdatetime(s), d = floor(datenum(s)); return; end
s = strtrim(char(s));
if ~isempty(regexp(s, '^\d{4}-\d{2}-\d{2}$', 'once')), d = datenum(s, 'yyyy-mm-dd');
elseif ~isempty(regexp(s, '^\d{2}\.\d{2}\.\d{4}$', 'once')), d = datenum(s, 'dd.mm.yyyy');
elseif ~isempty(regexp(s, '^\d{6}$', 'once')), d = datenum(s, 'yymmdd');
else, error('MyoDishAnalysisWatch: fromDate ''yyyy-mm-dd'', ''dd.mm.yyyy'' or ''yymmdd'' expected, not ''%s''.', s);
end
end

function d = parseTime(s)
% 'yyyy-mm-dd HH:MM:SS UTC' (index column 'modified') --> datenum (UTC); NaN if not readable
d = nan;
if ~isempty(regexp(s, '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC$', 'once')), d = datenum(s(1:19), 'yyyy-mm-dd HH:MM:SS'); end
end

function s = utcText(dn)
% local datenum (dir) --> 'yyyy-mm-dd HH:MM:SS UTC': the index is valid on computers in other time zones
t = datetime(dn, 'ConvertFrom', 'datenum', 'TimeZone', 'local');
t.TimeZone = 'UTC';
t.Format = 'yyyy-MM-dd HH:mm:ss';
s = [char(t) ' UTC'];
end

function p = absPath(p)
p = char(p);
if isempty(regexp(p, '^([/\\]|[A-Za-z]:)', 'once')), p = fullfile(pwd, p); end
while numel(p) > 1 && any(p(end) == '/\'), p(end) = []; end
end

function s = f1(x)
if isnan(x), s = ''; else, s = sprintf('%.1f', x); end
end

function s = clean(s)
s = strtrim(regexprep(char(s), '[\r\n,]+', ' '));
end

function deleteIfExists(f)
if ~isfile(f), return; end
try
    delete(f);
catch ME
    warning('MyoDishAnalysisWatch: lock file %s could not be deleted (%s); delete it, otherwise the next passes are skipped for 12 h.', f, ME.message);
end
end
