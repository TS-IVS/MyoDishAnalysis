function ok = mda_testWatch()
%MDA_TESTWATCH  Test of the watcher (MyoDishAnalysisWatch) with example recordings in a temporary folder.
%
%   ok = mda_testWatch()   prints the single checks, returns true if all pass
%
% Pendant of py/tests/test_watch.py: first and second pass, time bins with clock-time labels, protocols, one bin =
% direct analysis with MyoDishAnalysis, reanalysis after a change of the options / of the log file, 'reanalyze','new',
% recordings still running (log file without 'Recording stopped'), without log file, in hidden folders, dry run,
% filter, lock file.
%
% TS 2026-10-08

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
S = readtable(fullfile(res, 'A', 'example9_ratVentricle_summary.csv'), 'TextType', 'char');
pass = isequal(X.file', {'A/example9_ratVentricle.mdd', 'B/example7_pigVentricle.mdd'}) && all(strcmp(X.status, 'ok')) && ...
    all(strcmp(X.implementation, 'MATLAB')) && all(strcmp(X.version, mda_version())) && contains(report, 'A/example9') && ...
    height(S) == 3 && isequal(S.range', {'2000-01-01 15:48:46', '2000-01-01 15:53:46', '2000-01-01 15:58:46'}) && ...
    sum(S.nContractions) == X.nContractions(1) && ...
    isfile(fullfile(res, 'B', 'example7_pigVentricle_protocols_protocolResults.csv')) && ...
    ~isfile(fullfile(res, 'A', 'example9_ratVentricle_protocols_summary.csv')) && ~isfile(fullfile(res, 'mda_watch.lock'));
ok = check(ok, pass, 'first pass: index, 3 bins with clock time, protocol results, no lock file left');
[X2, report2] = MyoDishAnalysisWatch(raw, res, q{:}, 'binMinutes', 5);
ok = check(ok, isempty(report2) && isequal(X2.analyzed, X.analyzed), 'second pass: nothing to do');

% one bin = direct analysis
res = fullfile(root, 'res2');
MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false);
f = fullfile(raw, 'A', 'example9_ratVentricle.mdd');
C = MyoDishAnalysis(f, [], [], [], 'quiet', true, 'metadata', strrep(f, '.mdd', '_labels.csv'));
Cw = readtable(fullfile(res, 'A', 'example9_ratVentricle_contractions.csv'), 'TextType', 'char');
pass = height(Cw) == height(C) && max(abs(Cw.t_peak - C.t_peak)) < 1e-6 && ...
    max(abs(Cw.amplitude - C.amplitude) ./ C.amplitude, [], 'omitnan') < 1e-9;
ok = check(ok, pass, 'one bin (60 min): contractions identical to MyoDishAnalysis(file)');

% reanalysis: other options ('new': ignored), changed log file, 'all' with maxFiles
X = MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'reanalyze', 'new', 'rocker', 'stopped');
ok = check(ok, all(strcmp(X.options, 'binminutes=60; protocols=0')), '''reanalyze'',''new'': other options ignored');
[X, report] = MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'rocker', 'stopped');
ok = check(ok, all(strcmp(X.options, 'binminutes=60; protocols=0; rocker=stopped')) && contains(report, 'B/example7'), ...
    'other options: both recordings analysed again');
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
