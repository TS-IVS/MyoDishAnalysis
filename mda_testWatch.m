function ok = mda_testWatch()
%MDA_TESTWATCH  Test of the watcher (MyoDishAnalysisWatch) with example recordings in a temporary folder.
%
%   ok = mda_testWatch()   prints the single checks, returns true if all pass
%
% Pendant of py/tests/test_watch.py: first and second pass, time bins with clock-time labels, protocols, one bin =
% direct analysis with MyoDishAnalysis, reanalysis after a change of the options / of the log file, 'reanalyze','new',
% recordings still running (log file without 'Recording stopped'), without log file, in hidden folders, dry run,
% filter, lock file; protocol periods excluded / included, thinned contractions (every n-th, block medians),
% compression, events and comments.
%
% TS 2026-10-08 (info table, mda_readResults 2026-10-09)

ex = fullfile(fileparts(which('MyoDishAnalysis')), 'examples');
root = tempname;
raw = fullfile(root, 'raw');
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
copyRec(ex, 'example9_ratVentricle', fullfile(raw, 'A'), true);
copyRec(ex, 'example7_pigVentricle', fullfile(raw, 'B'), true);
q = {'quiet', true, 'minFileAgeMinutes', 0};
ok = true;

% first pass: 2 recordings, 5-min bins, protocols of example 7
res = fullfile(root, 'res1');
[X, report] = MyoDishAnalysisWatch(raw, res, q{:}, 'binMinutes', 5);
S = readCsv(fullfile(res, 'A', 'example9_ratVentricle_summary.csv'));
pass = isequal(X.file', {'A/example9_ratVentricle.mdd', 'B/example7_pigVentricle.mdd'}) && all(strcmp(X.status, 'ok')) && ...
    all(strcmp(X.implementation, 'MATLAB')) && all(strcmp(X.version, mda_version())) && contains(report, 'A/example9') && ...
    height(S) == 3 && isequal(S.range', {'2000-01-01 15:48:46', '2000-01-01 15:53:46', '2000-01-01 15:58:46'}) && ...
    sum(S.nContractions) == X.nContractions(1) && all(ismember({'bin', 'nComments', 'comments'}, S.Properties.VariableNames)) && ...
    isfile(fullfile(res, 'B', 'example7_pigVentricle_protocols_protocolResults.csv')) && ...
    X.nContractions(2) == 0 && contains(X.message{2}, 'no time outside the stimulation protocols') && ...
    ~isfile(fullfile(res, 'B', 'example7_pigVentricle_summary.csv')) && isfile(fullfile(res, 'A', 'example9_ratVentricle_events.csv')) && ...
    ~isfile(fullfile(res, 'A', 'example9_ratVentricle_protocols_summary.csv')) && ~isfile(fullfile(res, 'mda_watch.lock'));
ok = check(ok, pass, 'first pass: index, 3 bins with clock time, protocol results, no lock file left');
[X2, report2] = MyoDishAnalysisWatch(raw, res, q{:}, 'binMinutes', 5);
ok = check(ok, isempty(report2) && isequal(X2.analyzed, X.analyzed), 'second pass: nothing to do');

% one bin = direct analysis
res = fullfile(root, 'res2');
MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false);
f = fullfile(raw, 'A', 'example9_ratVentricle.mdd');
C = MyoDishAnalysis(f, [], [], [], 'quiet', true, 'metadata', strrep(f, '.mdd', '_labels.csv'));
Cw = readCsv(fullfile(res, 'A', 'example9_ratVentricle_contractions.csv'));
pass = height(Cw) == height(C) && max(abs(Cw.t_peak - C.t_peak)) < 1e-6 && ...
    max(abs(Cw.amplitude - C.amplitude) ./ C.amplitude, [], 'omitnan') < 1e-9;
ok = check(ok, pass, 'one bin (60 min): contractions identical to MyoDishAnalysis(file)');
R = mda_readResults(fullfile(res, 'A', 'example9_ratVentricle_info.csv'));   %2026-10-09: version, settings, windows
pass = strcmp(R.version, mda_version()) && strcmp(R.implementation, 'MATLAB') && strcmp(R.createdBy, 'MyoDishAnalysisWatch') ...
    && isfield(R.extra, 'watcherOptions') && contains(R.extra.watcherOptions, 'binminutes=60') && height(R.windows) >= 1 ...
    && all(R.windows.windowFrom <= R.windows.from) && strcmp(R.options.detection, 'sensitive') && height(R.contractions) == height(Cw);
ok = check(ok, pass, 'info table: version, watcher settings, analysis windows (mda_readResults)');

% reanalysis: other options ('new': ignored), changed log file, 'all' with maxFiles
base = ['binminutes=60; compress=0; contractions=all; events=1; gaps=1; includeprotocols=0; protocolmarginseconds=0; ' ...
    'protocols=0'];
X = MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'reanalyze', 'new', 'rocker', 'stopped');
ok = check(ok, all(strcmp(X.options, base)), '''reanalyze'',''new'': other options ignored');
[X, report] = MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'rocker', 'stopped');
ok = check(ok, all(strcmp(X.options, [base '; rocker=stopped'])) && contains(report, 'B/example7'), ...
    'other options: both recordings analysed again (options text as in Python)');
fid = fopen(fullfile(raw, 'A', 'example9_ratVentricle_log.log'), 'a'); fwrite(fid, uint8(0)); fclose(fid);
[X3, report] = MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'rocker', 'stopped');
ok = check(ok, contains(report, 'A/example9') && ~contains(report, 'B/example7') && X3.logBytes(1) == X.logBytes(1) + 1, ...
    'changed log file: only this recording analysed again');
[~, report] = MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'rocker', 'stopped', 'reanalyze', 'all', 'maxFiles', 1);
ok = check(ok, contains(report, 'A/example9') && ~contains(report, 'B/example7'), ...
    '''reanalyze'',''all'' with ''maxFiles'', 1: first recording analysed again');
X = readIndex(res);
X.code{1} = '00000000';
writetable(X, fullfile(res, 'mda_index.csv'), 'FileType', 'text');
[~, report] = MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'rocker', 'stopped');
ok = check(ok, contains(report, 'A/example9') && ~contains(report, 'B/example7'), 'changed core code: analysed again');
X = readIndex(res);
X.code(:) = {'00000000'}; X.implementation(:) = {'Python'};
writetable(X, fullfile(res, 'mda_index.csv'), 'FileType', 'text');
[~, report] = MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'rocker', 'stopped');
ok = check(ok, isempty(report), 'code of the other implementation: not analysed again');

% skipped recordings: running, no log file, hidden folder; dry run, filter, lock
raw2 = fullfile(root, 'raw2');
copyRec(ex, 'example9_ratVentricle', fullfile(raw2, 'nolog'), false);
copyRec(ex, 'example9_ratVentricle', fullfile(raw2, '.hidden'), true);
run = copyRec(ex, 'example9_ratVentricle', fullfile(raw2, 'running'), true);
txt = readUtf16(strrep(run, '.mdd', '_log.log'));
L = regexp(txt, '\r?\n', 'split');
L = L(~contains(L, 'stopped:'));
fid = fopen(strrep(run, '.mdd', '_log.log'), 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
H = mda_readMdd(run);
ok = check(ok, H.recordingStopped == 0, 'log file without ''Recording stopped'': recordingStopped = 0');
res = fullfile(root, 'res3');
X = MyoDishAnalysisWatch(raw2, res, q{:}, 'dryRun', true);
ok = check(ok, height(X) == 0 && ~isfile(fullfile(res, 'mda_index.csv')), 'dry run: nothing written');
[X, report] = MyoDishAnalysisWatch(raw2, res, q{:});
pass = isequal(X.file', {'nolog/example9_ratVentricle.mdd', 'running/example9_ratVentricle.mdd'}) && ...
    isequal(X.status', {'noLog', 'running'}) && isempty(report);
ok = check(ok, pass, 'no log file --> noLog, still running --> running, hidden folder skipped');
X = MyoDishAnalysisWatch(raw2, res, q{:}, 'incompleteAfterHours', 0);
ok = check(ok, isequal(X.status', {'noLog', 'ok'}), '''incompleteAfterHours'', 0: running recording analysed');
X = MyoDishAnalysisWatch(raw, fullfile(root, 'res4'), q{:}, 'filter', 'example7', 'protocols', false);
ok = check(ok, isequal(X.file', {'B/example7_pigVentricle.mdd'}), 'filter');
fid = fopen(fullfile(root, 'res4', 'mda_watch.lock'), 'w'); fprintf(fid, '1\n'); fclose(fid);
[X, msg] = MyoDishAnalysisWatch(raw, fullfile(root, 'res4'), q{:}, 'protocols', false);
ok = check(ok, contains(msg, 'another watcher') && height(X) == 1, 'lock file of another watcher: pass skipped');

% protocol periods excluded (default) or included (example 2: PD 67-327 s, ST 512-658 s)
raw3 = fullfile(root, 'raw3');
f2 = copyRec(ex, 'example2_rabbitVentricle', raw3, true);
copyRec(ex, 'example4_humanAtrium', raw3, true);
copyRec(ex, 'example9_ratVentricle', raw3, true);
P = mda_protocols(f2);
res = fullfile(root, 'res5');
MyoDishAnalysisWatch(raw3, res, q{:}, 'binMinutes', 5);
S = readCsv(fullfile(res, 'example2_rabbitVentricle_summary.csv'));
C = readCsv(fullfile(res, 'example2_rabbitVentricle_contractions.csv'));
pass = numel(unique(S.range)) == 3;
for k = 1:height(P)
    pass = pass && ~any(C.t_peak > P.from(k) & C.t_peak < P.to(k)) && ~any(S.from < P.to(k) & S.to > P.from(k));
end
ok = check(ok, pass, 'stimulation protocols excluded from summary and contractions (3 ranges)');
res6 = fullfile(root, 'res6');
MyoDishAnalysisWatch(raw3, res6, q{:}, 'binMinutes', 5, 'includeProtocols', true, 'filter', 'example2');
C6 = readCsv(fullfile(res6, 'example2_rabbitVentricle_contractions.csv'));
ok = check(ok, height(C6) > height(C) && any(C6.t_peak > P.from(1) & C6.t_peak < P.to(1)), '''includeProtocols'', true');
res7 = fullfile(root, 'res7');
MyoDishAnalysisWatch(raw3, res7, q{:}, 'binMinutes', 5, 'protocolMarginSeconds', 30, 'filter', 'example2');
S7 = readCsv(fullfile(res7, 'example2_rabbitVentricle_summary.csv'));
u = unique(S7.from);
ok = check(ok, abs(u(2) - (P.to(1) + 30)) < 1e-6, '''protocolMarginSeconds'', 30');

% events and comments (example 4: 'addition of 100nM Iso' in channels 3, 4, 6, 8)
E = readCsv(fullfile(res, 'example4_humanAtrium_events.csv'));
S4 = readCsv(fullfile(res, 'example4_humanAtrium_summary.csv'));
r1 = S4(strcmp(S4.range, S4.range{1}), :);
pass = all(ismember({'clockTime', 't_file', 'channel', 'code', 'category', 'text'}, E.Properties.VariableNames)) && ...
    all(strcmp(E.category(strcmp(E.text, 'addition of 100nM Iso')), 'comment')) && ...
    strcmp(r1.comments{r1.channel == 3}, 'addition of 100nM Iso') && r1.nComments(r1.channel == 1) == 0;
ok = check(ok, pass, 'events file with categories, comments per channel in the summary');
raw5 = fullfile(root, 'raw5');
f5 = copyRec(ex, 'example9_ratVentricle', raw5, true);
L5 = readUtf16(strrep(f5, '.mdd', '_log.log'));
add = {'jump to 60 bpm', 'S2 beat 300 ms', '50 mA', 'Pause 180seconds', 'Approaching 2 GB limit. Changing datafile2.', ...
    'ZI: MX1.6-1.8 Dexa100nM'};
fid = fopen(strrep(f5, '.mdd', '_log.log'), 'w');
fprintf(fid, '%s', L5);
for k = 1:numel(add), fprintf(fid, '2000 01 01 15:50:%02d:000;%d;0;comment;%s\n', k, 100000 + k, add{k}); end
fclose(fid);
res8 = fullfile(root, 'res8');
MyoDishAnalysisWatch(raw5, res8, q{:}, 'protocols', false);
E8 = readCsv(fullfile(res8, 'example9_ratVentricle_events.csv'));
[~, iE] = ismember(add, E8.text);
ok = check(ok, all(iE > 0) && isequal(E8.category(iE)', {'protocol', 'protocol', 'protocol', 'protocol', 'recording', 'comment'}), ...
    'schedule steps written as comments: category protocol');

% thinned contractions: every 10th / block medians; extra beats complete
resN = fullfile(root, 'resN'); resM = fullfile(root, 'resM');
MyoDishAnalysisWatch(raw3, resN, q{:}, 'binMinutes', 5, 'contractions', 'thinned', 'filter', 'example[49]');
MyoDishAnalysisWatch(raw3, resM, q{:}, 'binMinutes', 5, 'contractions', 'thinned', 'thinMode', 'median', 'filter', 'example[49]');
pass = true;
for nm = {'example4_humanAtrium', 'example9_ratVentricle'}
    A = readCsv(fullfile(res, [nm{1} '_contractions.csv']));
    Nn = readCsv(fullfile(resN, [nm{1} '_contractions.csv']));
    M = readCsv(fullfile(resM, [nm{1} '_contractions.csv']));
    nx = sum(strcmp(A.beatType, 'extra'));
    pass = pass && all(A.sampledEvery == 1) && sum(strcmp(Nn.beatType, 'extra')) == nx && sum(strcmp(M.beatType, 'extra')) == nx && ...
        all(Nn.sampledEvery(~strcmp(Nn.beatType, 'extra')) == 10) && ...
        sum(M.sampledEvery(strcmp(M.sampleMode, 'median'))) == sum(~strcmp(A.beatType, 'extra'));
    for c = unique(A.channel)'
        a = sort(A.t_peak(A.channel == c & ~strcmp(A.beatType, 'extra')));
        b = sort(Nn.t_peak(Nn.channel == c & ~strcmp(Nn.beatType, 'extra')));
        pass = pass && isequal(numel(b), numel(a(1:10:end))) && max(abs(b - a(1:10:end)), [], 'all') < 1e-9;
    end
end
A = sortrows(readCsv(fullfile(res, 'example9_ratVentricle_contractions.csv')), 't_peak');
M = sortrows(readCsv(fullfile(resM, 'example9_ratVentricle_contractions.csv')), 't_peak');
k = M.sampledEvery(1);
pass = pass && abs(M.amplitude(1) - median(A.amplitude(1:k))) < 1e-6 && abs(M.t_peak(1) - median(A.t_peak(1:k))) < 1e-9;
ok = check(ok, pass, 'thinned contractions: every 10th, block medians, extra beats complete');

% compression, 'none', no stale files
cf = fullfile(resM, 'example9_ratVentricle_contractions.csv');
MyoDishAnalysisWatch(raw3, resM, q{:}, 'binMinutes', 5, 'contractions', 'thinned', 'thinMode', 'median', 'filter', 'example9', 'compress', true);
pass = isfile([cf '.gz']) && ~isfile(cf);
MyoDishAnalysisWatch(raw3, resM, q{:}, 'binMinutes', 5, 'contractions', 'none', 'filter', 'example9');
pass = pass && ~isfile([cf '.gz']) && ~isfile(cf) && isfile(fullfile(resM, 'example9_ratVentricle_summary.csv'));
ok = check(ok, pass, '''compress'' (.csv.gz), ''contractions'',''none'', no files of earlier options left');

if ok, disp('mda_testWatch: all tests passed.'); else, warning('mda_testWatch: TEST FAILED.'); end
end


function ok = check(ok, pass, txt)
if pass, s = 'ok'; else, s = 'FAILED'; end
fprintf('%-100s %s\n', txt, s);
ok = ok && pass;
end

function f = copyRec(ex, name, dest, withLog)
if ~isfolder(dest), mkdir(dest); end
ext = {'.mdd', '_labels.csv'};
if withLog, ext{end+1} = '_log.log'; end
for k = 1:numel(ext)
    src = fullfile(ex, [name ext{k}]);
    if isfile(src), copyfile(src, dest); end
end
f = fullfile(dest, [name '.mdd']);
end

function T = readCsv(f)
% csv result file with the text columns as text (readtable would turn clock-time labels into datetime)
o = detectImportOptions(f, 'TextType', 'char');
txt = intersect(o.VariableNames, {'range', 'bin', 'comments', 'beatType', 'sampleMode', 'category', 'text', 'code'});
o = setvartype(o, txt, 'char');
T = readtable(f, o);
end

function X = readIndex(res)
f = fullfile(res, 'mda_index.csv');
o = detectImportOptions(f, 'FileType', 'text', 'Delimiter', ',');
num = {'bytes', 'logBytes', 'seconds', 'nContractions'};
o = setvartype(o, num, 'double');
o = setvartype(o, setdiff(o.VariableNames, num), 'char');
X = readtable(f, o);
end

function txt = readUtf16(f)
fid = fopen(f, 'r'); b = fread(fid, inf, 'uint8=>double')'; fclose(fid);
if numel(b) >= 2 && b(1) == 255 && b(2) == 254, b = b(3:end); end
b = b(1:2*floor(numel(b)/2));
txt = char(b(1:2:end) + 256 * b(2:2:end));
end
