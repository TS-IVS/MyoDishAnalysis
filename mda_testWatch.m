function ok = mda_testWatch()
%MDA_TESTWATCH  Test of the watcher (MyoDishAnalysisWatch) with example recordings in a temporary folder.
%
%   ok = mda_testWatch()   prints the single checks, returns true if all pass
%
% Pendant of py/tests/test_watch.py: first and second pass, time bins with clock-time labels, protocols, one bin =
% direct analysis with MyoDishAnalysis, reanalysis after a change of the options / of the log file, 'reanalyze','new'
% (default: notice) and 'outdated', schedule (parsing, next pass, timer, status, stop),
% recordings still running (log file without 'Recording stopped'), without log file, in hidden folders, dry run,
% filter, include / exclude patterns, lock file (heartbeat: ignored when not refreshed for 1 h); protocol periods
% excluded / included, thinned contractions (every n-th, block medians), compression, events and comments, overview
% (1-min medians), slice register; incomplete copies, parallel recordings; results as .xlsx, csv <-> xlsx, trend
% images (2026-10-14); folders of the series, course and overview images, PDF report per experiment, reorganize
% (2026-10-15).
%
% TS 2026-10-08 (info table, mda_readResults 2026-10-09; schedule, reanalyze 'new' 2026-10-12; include / exclude,
% incomplete copies, parallel recordings 2026-10-13; lock heartbeat 2026-10-14)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

ex = fullfile(fileparts(which('MyoDishAnalysis')), 'examples');
root = tempname;
raw = fullfile(root, 'raw');
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
copyRec(ex, 'example9_ratVentricle', fullfile(raw, 'A'), true);
copyRec(ex, 'example7_pigVentricle', fullfile(raw, 'B'), true);
qx = {'quiet', true, 'minFileAgeMinutes', 0};                   %results as .xlsx, trend images (defaults)
q = [qx, {'resultFormat', 'csv', 'trends', false, 'folders', 'flat'}];   %one csv file per table in the folder of the
                                                                %experiment: tests of the analysis
ok = true;

% first pass: 2 recordings, 5-min bins, protocols of example 7; default results (2026-10-14/15): a folder per recording
% (names without a number: <experiment>/<name>/), <name>.xlsx with the tables as sheets, the large tables as .csv.gz,
% trend images, PDF report per experiment
res = fullfile(root, 'res1');
[X, report] = MyoDishAnalysisWatch(raw, res, qx{:}, 'binMinutes', 5);
n9 = 'example9_ratVentricle'; n7 = 'example7_pigVentricle';
eA = fullfile(res, 'A'); eB = fullfile(res, 'B');
A9 = fullfile(eA, n9); B7 = fullfile(eB, n7);
xA = fullfile(A9, [n9 '.xlsx']);
S = readSheet(xA, 'summary');
pass = isequal(X.file', {'A/example9_ratVentricle.mdd', 'B/example7_pigVentricle.mdd'}) && all(strcmp(X.status, 'ok')) && ...
    all(strcmp(X.implementation, 'MATLAB')) && all(strcmp(X.version, mda_version())) && contains(report, 'A/example9') && ...
    height(S) == 3 && isequal(S.range', {'2000-01-01 15:48:46', '2000-01-01 15:53:46', '2000-01-01 15:58:46'}) && ...
    sum(S.nContractions) == X.nContractions(1) && all(ismember({'bin', 'nComments', 'comments'}, S.Properties.VariableNames)) && ...
    X.nContractions(2) == 0 && contains(X.message{2}, 'no time outside the stimulation protocols') && ...
    ~isfile(fullfile(res, 'mda_watch.lock'));
ok = check(ok, pass, 'first pass: index, 3 bins with clock time, no lock file left');
D = dir(eA); D = sort({D(~startsWith({D.name}, '.')).name});
D9 = dir(A9); D9 = sort({D9(~startsWith({D9.name}, '.')).name});
B7f = dir(fullfile(B7, '*.png'));
pass = isequal(D, {'A_report.pdf', 'A_slices.csv', n9}) && isequal(D9, {[n9 '.xlsx'], [n9 '_ch1.png'], ...
    [n9 '_contractions.csv.gz'], [n9 '_overview.csv.gz'], [n9 '_pulses.csv.gz']}) && ...
    isequal(cellstr(sheetnames(xA))', {'summary', 'trends', 'trendComments', ...
    'channels', 'gaps', 'events', 'parameters', 'info', 'thresholds', 'labels'}) && isequal(cellstr(sheetnames(fullfile(B7, [n7 '.xlsx'])))', ...
    {'channels', 'gaps', 'events'}) && ismember('protocolResults', sheetnames(fullfile(B7, [n7 '_protocols.xlsx']))) ...
    && isfile(fullfile(B7, [n7 '_protocols_contractions.csv.gz'])) && isempty(B7f) && ...
    strcmp(X.outputs{1}, sprintf('%s.xlsx; %s_contractions.csv.gz; %s_pulses.csv.gz; %s_overview.csv.gz; %s_ch*.png (1)', ...
    n9, n9, n9, n9, n9)) && strcmp(MyoDishAnalysisWatch('resultFolder', res, ['A/' n9 '.mdd']), A9);
ok = check(ok, pass, 'results in A/<name>/: <name>.xlsx (sheets), contractions / pulses / overview as .csv.gz, protocols');
T = dir(fullfile(A9, '*.png'));
ok = check(ok, numel(T) == 1 && strcmp(T(1).name, [n9 '_ch1.png']) && T(1).bytes > 20000, ...
    sprintf('trend image per channel: %s', strjoin({T.name}, ', ')));
pdfs = dir(fullfile(res, 'reports', 'mda_report_*.pdf'));
pa = dir(fullfile(eA, 'A_report.pdf'));
ok = check(ok, isempty(pdfs) && isscalar(pa) && pa(1).bytes > 1000 && isfile(fullfile(eB, 'B_report.pdf')) && ...
    contains(report, ['PDF report: ' fullfile(eA, 'A_report.pdf')]), 'PDF report per experiment (mda_report), none per pass');
O = readCsvGz(fullfile(A9, [n9 '_overview.csv']));   % amplitude(1) 755.87 with diastolicLevel minimum (<= 1.0.0-beta.3)
C1 = readCsvGz(fullfile(A9, [n9 '_contractions.csv']));
Tt = readSheet(xA, 'trends');                                  %data of the trend image
inc = O(O.included == 1, :);
[u, ~, g] = unique(inc.t_from);
one = u(accumarray(g, 1) == 1);
[~, ia] = ismember(one, Tt.t_from); [~, ib] = ismember(one, inc.t_from);
pass = isequal(Tt.Properties.VariableNames, {'channel', 'window', 't_from', 'nBeats', 'amplitude', 'diastolicForce', ...
    'TTP90', 'TTR90', 'bin_from'}) && height(Tt) == numel(u) && sum(Tt.nBeats) == sum(inc.nBeats) && ...
    max(abs(Tt.amplitude(ia) - inc.amplitude(ib)) ./ inc.amplitude(ib)) < 1e-12 && strcmp(Tt.window{1}, O.window{1}) && ...
    all(ismember(Tt.bin_from, [0 300 600]));
ok = check(ok, pass, 'sheet trends: values of the trend image per window (overview of the included contractions)');
Rr = mda_readResults(xA);
ok = check(ok, strcmp(Rr.createdBy, 'MyoDishAnalysisWatch') && height(Rr.contractions) == 333 && height(Rr.windows) >= 1, ...
    'results opened again (mda_readResults of the .xlsx: contractions from the .csv.gz)');
R = readCsv(fullfile(res, 'mda_slices.csv'));
a = R(strcmp(R.experiment, 'A'), :);
pass = height(O) == 12 && sum(O.nBeats) == height(C1) && height(C1) == 333 && isequal(O.t_from(1:2)', [0 60]) && ...
    strcmp(O.window{1}, '2000-01-01 15:48:46') && abs(O.amplitude(1) - 748.916666666667) < 1e-6 && ...
    height(R) == 9 && strcmp(a.endStatus{1}, 'beating at end of data') && a.nBeats == 333 && ...
    strcmp(a.species{1}, 'rat') && all(strcmp(R.endStatus(strcmp(R.experiment, 'B')), 'protocols only')) && ...
    contains(report, 'slice register: 9 slices') && isfile(fullfile(eA, 'A_slices.csv')) && ...
    isfile(fullfile(eB, 'B_slices.csv'));
ok = check(ok, pass, 'overview (1-min medians, all contractions) and slice register (protocols only)');
[X2, report2] = MyoDishAnalysisWatch(raw, res, qx{:}, 'binMinutes', 5);
ok = check(ok, isempty(report2) && isequal(X2.analyzed, X.analyzed), 'second pass: nothing to do');

% result formats (2026-10-14) and folders (2026-10-15): csv <-> xlsx, flat <-> series (the files of the other format /
% layout are removed), slice register of mixed folders, trend images again from the results ('trends')
res = fullfile(root, 'resF');
MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'trends', true);
eA = fullfile(res, 'A'); A = fullfile(eA, n9);
pass = isfile(fullfile(eA, [n9 '_summary.csv'])) && ~isfile(fullfile(eA, [n9 '.xlsx'])) && ...
    isfile(fullfile(eA, [n9 '_trends.csv'])) && isfile(fullfile(eA, [n9 '_trendComments.csv'])) && ...
    isfile(fullfile(eA, 'trends', [n9 '_ch1.png']));
MyoDishAnalysisWatch(raw, res, qx{:}, 'protocols', false, 'reanalyze', 'all', 'include', 'A');
D = dir(fullfile(A, [n9 '*'])); D = sort({D.name});
F = dir(fullfile(eA, [n9 '*'])); F = F(~[F.isdir]);
pass = pass && isequal(D, {[n9 '.xlsx'], [n9 '_ch1.png'], [n9 '_contractions.csv.gz'], [n9 '_overview.csv.gz'], ...
    [n9 '_pulses.csv.gz']}) && isempty(F) && ~isfolder(fullfile(eA, 'trends')) && isfile(fullfile(res, 'B', [n7 '_channels.csv']));
R = mda_sliceRegister(res);
pass = pass && height(R) == 9 && R.nBeats(find(strcmp(R.experiment, 'A'), 1)) == 333;
ok = check(ok, pass, 'csv in A/ -> xlsx in A/<name>/: files of the other format and layout removed; register of both');
[files, rt] = MyoDishAnalysisWatch('trends', res, 'include', 'A', 'trendParameters', {'amplitude', 'beatsPerMinute'}, ...
    'quiet', true);
Tt = readSheet(fullfile(A, [n9 '.xlsx']), 'trends');            %sheet replaced: the new parameters
pass = isscalar(files) && strcmp(files{1}, fullfile(A, [n9 '_ch1.png'])) && startsWith(rt, '1 trend image(s) of 1') && ...
    isequal(Tt.Properties.VariableNames(5:end), {'amplitude', 'beatsPerMinute', 'bin_from'}) && height(Tt) > 5;
try
    MyoDishAnalysisWatch('trends', res, 'trendParameters', {'noSuchParameter'}, 'quiet', true); pass = false;
catch
end
MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'reanalyze', 'all', 'include', 'A');
pass = pass && isfile(fullfile(eA, [n9 '_channels.csv'])) && ~isfile(fullfile(eA, [n9 '.xlsx'])) && ~isfolder(A) && ...
    ~isfolder(fullfile(eA, 'trends'));
ok = check(ok, pass, 'trend images again from the results (''trends''); back to csv in A/: A/<name>/ removed');

% folders 'series' (2026-10-15): numbered recordings of a setup in <experiment>/<series>/<nn>/, course image per
% channel and workbook in <experiment>/<series>/, overview image and PDF report per experiment; flags of earlier passes
% kept; reorganize into the flat layout and back
rawS = fullfile(root, 'rawSeries'); res = fullfile(root, 'resSeries');
hrs = [30 6];
for k = 0:1
    f = copyRec(ex, 'example9_ratVentricle', fullfile(rawS, 'E'), true);
    nk = sprintf('rigX_sampleA_%d', k);
    for x = {'.mdd', '_labels.csv', '_log.log'}
        movefile([f(1:end-4) x{1}], fullfile(rawS, 'E', [nk x{1}]));
    end
    lf = fullfile(rawS, 'E', [nk '_log.log']);
    L = regexp(readUtf16(lf), '\r?\n', 'split');                %as UTF-8 text, then the clock shifted
    fid = fopen(lf, 'w'); fprintf(fid, '%s\n', L{~cellfun(@isempty, L)}); fclose(fid);
    shiftLog(lf, hrs(k + 1));
    ageFiles({fullfile(rawS, 'E', [nk '.mdd']), fullfile(rawS, 'E', [nk '_log.log'])}, 3600);
end
[X, report] = MyoDishAnalysisWatch(rawS, res, qx{:}, 'protocols', false);
e = fullfile(res, 'E'); sr = fullfile(e, 'rigX_sampleA');
n0 = 'rigX_sampleA_0'; n1 = 'rigX_sampleA_1';
D = dir(e); D = sort({D(~startsWith({D.name}, '.')).name});
Ds = dir(sr); Ds = sort({Ds(~startsWith({Ds.name}, '.')).name});
D1 = dir(fullfile(sr, '01')); D1 = sort({D1(~startsWith({D1.name}, '.')).name});
pass = all(strcmp(X.status, 'ok')) && isequal(D, {'E_overview.png', 'E_report.pdf', 'E_slices.csv', 'rigX_sampleA'}) && ...
    isequal(Ds, {'00', '01', 'rigX_sampleA_ch1.png', 'rigX_sampleA_trends.xlsx'}) && isequal(D1, {[n1 '.xlsx'], ...
    [n1 '_ch1.png'], [n1 '_contractions.csv.gz'], [n1 '_overview.csv.gz'], [n1 '_pulses.csv.gz']}) && ...
    contains(report, ['PDF report: ' fullfile(e, 'E_report.pdf')]) && ...
    strcmp(MyoDishAnalysisWatch('resultFolder', res, ['E/' n1 '.mdd']), fullfile(sr, '01'));
ok = check(ok, pass, 'folders ''series'': E/rigX_sampleA/00/, 01/, course image, workbook, overview, report');
wb = fullfile(sr, 'rigX_sampleA_trends.xlsx');
Tc = readSheet(wb, 'course'); Tl = readSheet(wb, 'last24h');
O1 = readCsvGz(fullfile(sr, '01', [n1 '_overview.csv']));
bins = char(Tc.bin);
pass = isequal(cellstr(sheetnames(wb))', {'course', 'last24h', 'comments', 'slices'}) && ...
    isequal(Tc.Properties.VariableNames, {'channel', 'slice', 'bin', 'dayInCulture', 'nBeats', 'amplitude', ...
    'diastolicForce', 'TTP90', 'TTR90', 'binMinutes'}) && all(Tc.slice == 1) && all(Tc.binMinutes == 10) && ...
    all(mod(str2double(cellstr(bins(:, 15:16))), 10) == 0) && all(strcmp(cellstr(bins(:, 18:19)), '00')) && ...
    height(Tl) == numel(unique(O1.t_from(O1.included == 1))) && height(readSheet(wb, 'slices')) == 1;
ok = check(ok, pass, 'workbook of the series: course (10-min bins of the clock), last 24 h (recording 1), slices');
Fl = readFlagsCsv(fullfile(res, 'mda_flags.csv'));
i0 = strcmp(Fl.file, ['E/' n0 '.mdd']);
Fl.level(i0) = {'check'}; Fl.red(i0) = {'test flag of yesterday'}; Fl.flags(i0) = {'N'};
writetable(Fl, fullfile(res, 'mda_flags.csv'));
[~, report2] = MyoDishAnalysisWatch(rawS, res, qx{:}, 'protocols', false, 'reanalyze', 'all', 'include', '*_1.mdd');
Fl2 = readFlagsCsv(fullfile(res, 'mda_flags.csv'));
pass = contains(report2, [n1 '.mdd']) && ~contains(report2, [n0 '.mdd']) && ...
    any(strcmp(Fl2.red, 'test flag of yesterday')) && isfile(fullfile(e, 'E_report.pdf'));
ok = check(ok, pass, 'second pass with recording 1: red flag of recording 0 kept (mda_flags.csv, experiment report)');
% mda_timepoints (2026-10-15) on these results: means of the contractions of the windows, no recording between the
% recordings, pending after the data; the watcher keeps <experiment>/timepoints/ (reorganize below)
C1 = readCsvGz(fullfile(sr, '01', [n1 '_contractions.csv']));
tc = C1.clockTime;
if ~isdatetime(tc), tc = datetime(tc, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS'); end
t0 = dateshift(min(tc), 'start', 'minute') + minutes(5);
TP = mda_timepoints(res, 'Tst', 'rigX_sampleA', [], t0, [-600 -2 2 300], 60);
S = TP.summary;
pass = isequal(TP.rows.channel, 1) && strcmp(S.note{1}, 'no recording') && strcmp(S.note{4}, 'pending: no data yet');
for k = 2:3
    a = t0 + minutes(S.offset_min(k));
    m = tc >= a & tc < a + seconds(60) & C1.channel == 1 & C1.included == 1;
    pass = pass && S.nIncluded(k) == sum(m) && abs(S.amplitude(k) - mean(C1.amplitude(m))) < 1e-9 * S.amplitude(k) ...
        && abs(S.amplitude_median(k) - median(C1.amplitude(m))) < 1e-9 * S.amplitude(k) ...
        && abs(S.dFdtMax(k) - mean(C1.dFdtMax(m)) / 1000) < 1e-9 * abs(S.dFdtMax(k));        %mN/s
end
for k = 2:3                                            %average beats: amplitude as the contractions
    pass = pass && S.nAvgBeats(k) > 0 && abs(S.avgBeat_amplitude(k) / S.amplitude(k) - 1) < 0.05;
end
AB = TP.averageBeats; b = AB(AB.offset_min == -2 & strcmp(AB.trace, 'all'), :);
pass = pass && abs(max(b.norm_baselineAmplitude) - 1) < 1e-9 && abs(mean(b.norm_ownAmplitude(b.t_s < 0))) < 1e-9 ...
    && all(b.force_SE_uN > 0);
b2 = AB(AB.offset_min == 2 & strcmp(AB.trace, 'all'), :);           %own amplitude = 1: SE in the same scale
a2 = max(b2.force_uN) - mean(b2.force_uN(b2.t_s < 0));
pass = pass && max(abs(b2.norm_ownAmplitude_SE - b2.force_SE_uN / a2)) < 1e-9 * max(b2.norm_ownAmplitude_SE);
TP2 = mda_timepoints(res, 'Tst2', 'rigX_sampleA', 2, t0, [-2 2], 60, 'averageBeats', false, 'write', false);
S2 = TP2.summary;                                  %channel 2 without contractions: force 0, times NaN, diastole signal
pass = pass && all(all(S2{:, {'amplitude', 'dFdtMax', 'dFdtMin', 'AUC', 'beatsPerMinute'}} == 0)) && ...
    all(all(isnan(S2{:, {'TTP90', 'TTR90', 'CD50', 'CD90'}}))) && all(isfinite(S2.diastolicForce)) && ...
    all(strcmp(S2.note, 'no contractions; diastolic force from the signal')) && ...
    abs(S2.diastolicForce_delta(2) - (S2.diastolicForce(2) - S2.diastolicForce(1))) < 1e-9;
tpd = TP.folder;
Dtp = dir(tpd); Dtp = sort({Dtp(~startsWith({Dtp.name}, '.')).name});
Dab = dir(fullfile(tpd, 'averageBeats')); Dab = sort({Dab(~startsWith({Dab.name}, '.')).name});
pass = pass && startsWith(tpd, fullfile(e, 'timepoints', 'Tst_')) && numel(Dtp) == 18 && ...
    isequal(Dab, {'rigX_sampleA_ch1.fig', 'rigX_sampleA_ch1.png'});
ok = check(ok, pass, ['mda_timepoints on the results: means, medians, no recording, pending, average beats, ' ...
    'channel without contractions, folder']);
[n, rt] = MyoDishAnalysisWatch('reorganize', res, 'folders', 'flat', 'quiet', true);
D = dir(e); D = sort({D(~startsWith({D.name}, '.')).name});
Dt = dir(fullfile(e, 'trends')); Dt = sort({Dt(~startsWith({Dt.name}, '.')).name});
want = sort([{'E_overview.png', 'E_report.pdf', 'E_slices.csv', 'timepoints', 'trends'}, strcat(n0, {'.xlsx', ...
    '_contractions.csv.gz', '_overview.csv.gz', '_pulses.csv.gz'}), strcat(n1, {'.xlsx', '_contractions.csv.gz', ...
    '_overview.csv.gz', '_pulses.csv.gz'})]);
pass = n == 2 && startsWith(rt, 'results of 2 recording(s) moved to the layout ''flat''') && isequal(D, want) && ...
    isequal(Dt, {[n0 '_ch1.png'], [n1 '_ch1.png'], 'rigX_sampleA_ch1.png', 'rigX_sampleA_trends.xlsx'});
MyoDishAnalysisWatch('reorganize', res, 'quiet', true);
D = dir(e); D = sort({D(~startsWith({D.name}, '.')).name});
D0 = dir(fullfile(sr, '00')); D0 = sort({D0(~startsWith({D0.name}, '.')).name});
Dtp2 = dir(tpd); Dtp2 = sort({Dtp2(~startsWith({Dtp2.name}, '.')).name});
pass = pass && isequal(D, {'E_overview.png', 'E_report.pdf', 'E_slices.csv', 'rigX_sampleA', 'timepoints'}) && ...
    isequal(D0, {[n0 '.xlsx'], [n0 '_ch1.png'], [n0 '_contractions.csv.gz'], [n0 '_overview.csv.gz'], ...
    [n0 '_pulses.csv.gz']}) && height(mda_sliceRegister(res)) == 1 && isequal(Dtp2, Dtp);
ok = check(ok, pass, ['''reorganize'': into the flat layout (images in trends/) and back into the folders of the ' ...
    'series; timepoints/ kept']);

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
base = ['binminutes=60; compress=0; contractions=all; events=1; gaps=1; includeprotocols=0; overviewseconds=60; ' ...
    'protocolmarginseconds=0; ' ...
    'protocols=0'];
[X, report] = MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'rocker', 'stopped');
ok = check(ok, all(strcmp(X.options, base)) && contains(report, '2 recording(s) were analysed with other options') ...
    && contains(report, '''reanalyze'', ''outdated'''), ...
    'other options, ''reanalyze'',''new'' (default): results kept, notice (2026-10-12)');
[X, report] = MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'rocker', 'stopped', 'reanalyze', 'outdated');
ok = check(ok, all(strcmp(X.options, [base '; rocker=stopped'])) && contains(report, 'B/example7') && ...
    ~contains(report, 'NOTE'), '''reanalyze'',''outdated'': both recordings analysed again (options text as in Python)');
fid = fopen(fullfile(raw, 'A', 'example9_ratVentricle_log.log'), 'a'); fwrite(fid, uint8(0)); fclose(fid);
[X3, report] = MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'rocker', 'stopped');
ok = check(ok, contains(report, 'A/example9') && ~contains(report, 'B/example7') && X3.logBytes(1) == X.logBytes(1) + 1, ...
    'changed log file: only this recording analysed again');
[~, report] = MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'rocker', 'stopped', 'reanalyze', 'all', 'maxFiles', 1);
ok = check(ok, contains(report, 'A/example9') && ~contains(report, 'B/example7'), ...
    '''reanalyze'',''all'' with ''maxFiles'', 1: first recording analysed again');
X = readIndex(res);
X.code{1} = '00000000'; X.version{2} = '0.9';
writetable(X, fullfile(res, 'mda_index.csv'), 'FileType', 'text');
[X1, report] = MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'rocker', 'stopped');
pass = startsWith(report, 'MyoDishAnalysis has been updated') && contains(report, '(0.9: 1, ') && ...
    contains(report, 'with other core code: 1)') && isequal(X1.version, X.version);
ok = check(ok, pass, 'other version / core code, default: results kept, notice with the versions');
X = readIndex(res);
X.code{1} = '00000000'; X.version{2} = '0.9';
writetable(X, fullfile(res, 'mda_index.csv'), 'FileType', 'text');
[~, report] = MyoDishAnalysisWatch(raw, res, q{:}, 'protocols', false, 'rocker', 'stopped', 'reanalyze', 'outdated');
ok = check(ok, contains(report, 'A/example9') && contains(report, 'B/example7'), ...
    '''reanalyze'',''outdated'': other version and changed core code analysed again');
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
shiftLog(strrep(run, '.mdd', '_log.log'), 1);   %2026-10-13: running while the end of the data is < 30 h ago
H = mda_readMdd(run);
ok = check(ok, H.recordingStopped == 0, 'log file without ''Recording stopped'': recordingStopped = 0');
res = fullfile(root, 'res3');
X = MyoDishAnalysisWatch(raw2, res, q{:}, 'dryRun', true);
ok = check(ok, height(X) == 0 && ~isfile(fullfile(res, 'mda_index.csv')), 'dry run: nothing written');
[X, report] = MyoDishAnalysisWatch(raw2, res, q{:});
pass = isequal(X.file', {'nolog/example9_ratVentricle.mdd', 'running/example9_ratVentricle.mdd'}) && ...
    isequal(X.status', {'noLog', 'running'}) && isempty(report);
ok = check(ok, pass, 'no log file --> noLog, still running --> running, hidden folder skipped');
a0 = X.analyzed{1};
pause(1.1);
X = MyoDishAnalysisWatch(raw2, res, q{:}, 'incompleteAfterHours', 0);
ok = check(ok, isequal(X.status', {'noLog', 'ok'}), '''incompleteAfterHours'', 0: running recording analysed');
ok = check(ok, strcmp(X.analyzed{1}, a0), 'noLog not checked again in every pass (2026-10-13)');
copyfile(fullfile(ex, 'example9_ratVentricle_log.log'), fullfile(raw2, 'nolog'));
X = MyoDishAnalysisWatch(raw2, res, q{:}, 'protocols', false);
ok = check(ok, strcmp(X.status{1}, 'ok'), 'noLog: analysed when the log file appears');
X = MyoDishAnalysisWatch(raw, fullfile(root, 'res4'), q{:}, 'filter', 'example7', 'protocols', false);
ok = check(ok, isequal(X.file', {'B/example7_pigVentricle.mdd'}), 'filter');
% wildcard patterns (2026-10-13; as test_watch.py): folder or file name, case ignored unless caseSensitive; exclude
C = {{'include', 'b'}, {'B/example7'}; {'include', 'b', 'caseSensitive', true}, {}; ...
    {'include', '*VENTRICLE*', 'exclude', 'B/*'}, {'A/example9'}; {'include', 'example?_*', 'exclude', {'*pig*'}}, ...
    {'A/example9'}; {'filter', 'EXAMPLE9', 'caseSensitive', true}, {}};
pass = true;
for k = 1:size(C, 1)
    out = evalc('MyoDishAnalysisWatch(raw, fullfile(root, ''dry''), q{:}, ''dryRun'', true, C{k,1}{:});');
    sel = {'A/example9', 'B/example7'}; sel = sel(cellfun(@(x) contains(out, [x '_']), sel));
    pass = pass && isequal(sel(:)', C{k,2}(:)');
end
ok = check(ok, pass, 'include / exclude wildcard patterns, caseSensitive (dry runs)');
fid = fopen(fullfile(root, 'res4', 'mda_watch.lock'), 'w'); fprintf(fid, '1\n'); fclose(fid);
[X, msg] = MyoDishAnalysisWatch(raw, fullfile(root, 'res4'), q{:}, 'protocols', false);
ok = check(ok, contains(msg, 'another watcher') && height(X) == 1, 'lock file of another watcher: pass skipped');
% heartbeat (2026-10-14): a lock file not refreshed for 1 h is ignored (watcher crashed) and removed after the pass
ageFiles({fullfile(root, 'res4', 'mda_watch.lock')}, 2 * 3600);
[X, msg] = MyoDishAnalysisWatch(raw, fullfile(root, 'res4'), q{:}, 'protocols', false, 'report', false);
ok = check(ok, ~contains(msg, 'another watcher') && height(X) == 2 && ~isfile(fullfile(root, 'res4', 'mda_watch.lock')), ...
    'lock file not refreshed for 1 h: ignored and removed after the pass');

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
    'note: MX1.6-1.8 Dexa100nM'};
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
MyoDishAnalysisWatch(raw3, resM, q{:}, 'binMinutes', 5, 'contractions', 'thinned', 'thinMode', 'median', 'filter', 'example9', 'compress', true, 'reanalyze', 'outdated');
pass = isfile([cf '.gz']) && ~isfile(cf);
MyoDishAnalysisWatch(raw3, resM, q{:}, 'binMinutes', 5, 'contractions', 'none', 'filter', 'example9', 'reanalyze', 'outdated');
pass = pass && ~isfile([cf '.gz']) && ~isfile(cf) && isfile(fullfile(resM, 'example9_ratVentricle_summary.csv'));
ok = check(ok, pass, '''compress'' (.csv.gz), ''contractions'',''none'', no files of earlier options left');
% 2026-10-11: protocol contractions and pulses compressed as well
MyoDishAnalysisWatch(raw, fullfile(root, 'res5'), q{:}, 'filter', 'example7', 'compress', true);
pb = fullfile(root, 'res5', 'B', 'example7_pigVentricle_protocols_');
pass = isfile([pb 'contractions.csv.gz']) && ~isfile([pb 'contractions.csv']) && isfile([pb 'pulses.csv.gz']) && ...
    ~isfile([pb 'pulses.csv']);
ok = check(ok, pass, '''compress'': protocol contractions and pulses as .csv.gz');

% schedule (2026-10-12): parsing and next pass as in Python, timer in the background, status, stop
N = @(s, prev, t) MyoDishAnalysisWatch('nextPass', s, prev, t);
t0 = datenum(2026, 10, 12, 8, 30, 0);                  %Monday
same = @(a, b) abs(a - b) < 1e-6;
pass = same(N('daily 10:00', [], t0), datenum(2026, 10, 12, 10, 0, 0)) && ...
    same(N('every day at 07:00', [], t0), datenum(2026, 10, 13, 7, 0, 0)) && ...
    same(N('weekly Sun 05:00', [], t0), datenum(2026, 10, 18, 5, 0, 0)) && ...
    same(N('Sunday 5:00', [], t0), datenum(2026, 10, 18, 5, 0, 0)) && ...
    same(N('Mon,Thu 06:30', [], t0), datenum(2026, 10, 15, 6, 30, 0)) && ...
    same(N('Mon,Thu 06:30', datenum(2026, 10, 15, 6, 30, 0), datenum(2026, 10, 15, 6, 30, 0)), datenum(2026, 10, 19, 6, 30, 0)) && ...
    same(N('weekdays 07:00', [], datenum(2026, 10, 16, 8, 0, 0)), datenum(2026, 10, 19, 7, 0, 0)) && ...
    same(N('every 120 min', [], t0), t0) && same(N('every 120 min', t0, t0), datenum(2026, 10, 12, 10, 30, 0)) && ...
    same(N('every 2 h', t0, t0 + 5 / 24), datenum(2026, 10, 12, 14, 30, 0)) && ...
    same(N('every 2 days 07:00', datenum(2026, 10, 13, 7, 0, 0), datenum(2026, 10, 13, 7, 5, 0)), datenum(2026, 10, 15, 7, 0, 0));
bad = {'daily 25:00', 'sometimes', 'every 0 min', 'every 30 s', 'T 10:00'};
for k = 1:numel(bad)
    try
        N(bad{k}, [], t0); pass = false;
    catch
    end
end
ok = check(ok, pass, 'schedule: daily, weekly, weekdays, every n days, every n min / h, errors (as in Python)');
MyoDishAnalysisWatch('stop');
res9 = fullfile(root, 'res9');
MyoDishAnalysisWatch(raw, res9, q{:}, 'protocols', false, 'filter', 'example9', 'schedule', 'every 60 min');
[T1, txt1] = MyoDishAnalysisWatch('status');
t1 = tic;
while ~isfile(fullfile(res9, 'mda_index.csv')) && toc(t1) < 120, pause(1); end
pause(2);
[T2, txt2] = MyoDishAnalysisWatch('status');
MyoDishAnalysisWatch(raw, res9, q{:}, 'schedule', 'daily 23:59');   %replaces the first one
T3 = MyoDishAnalysisWatch('status');
n = MyoDishAnalysisWatch('stop', res9);
T4 = MyoDishAnalysisWatch('status');
X9 = readIndex(res9);
pass = height(T1) == 1 && strcmp(T1.schedule{1}, 'every 60 min') && contains(txt1, 'next pass') && ...
    height(T2) == 1 && strcmp(T2.lastResult{1}, '1 recording(s) analysed') && contains(txt2, 'last pass') && ...
    isequal(X9.file', {'A/example9_ratVentricle.mdd'}) && height(T3) == 1 && strcmp(T3.schedule{1}, 'daily 23:59') && ...
    n == 1 && height(T4) == 0 && isempty(timerfindall('Tag', 'MyoDishAnalysisWatch'));
ok = check(ok, pass, 'schedule: timer in the background, first pass now, status, replaced, stop');
try
    MyoDishAnalysisWatch(raw, res9, q{:}, 'schedule', 'every 1 h', 'interval', 2); pass = false;
catch
    pass = true;
end
ok = check(ok, pass && isempty(timerfindall('Tag', 'MyoDishAnalysisWatch')), '''schedule'' with ''interval'': error');

% completeness (2026-10-13; as test_watch.py): file shorter than the recording in the log file (> max(10 s, 1 %)),
% robocopy file time 1980; analysed after 'incompleteAfterHours' without change; complete copy analysed again
rawI = fullfile(root, 'rawIncomplete'); res = fullfile(root, 'resIncomplete');
namedCopy(ex, fullfile(rawI, 'I'), 'half', 333);
namedCopy(ex, fullfile(rawI, 'T'), 'short5s', 666.68 - 5);
r = namedCopy(ex, fullfile(rawI, 'R'), 'robo', []);
java.io.File(r).setLastModified(int64(315532800000));                       %1980-01-01
namedCopy(ex, fullfile(rawI, 'E'), 'empty', 0);                             %empty file (0 bytes) with log file
e = namedCopy(ex, fullfile(rawI, 'L'), 'emptylog', []);                     %empty log file
fid = fopen([e(1:end-4) '_log.log'], 'w'); fclose(fid); ageFiles({[e(1:end-4) '_log.log']}, 3600);
q5 = {'quiet', true, 'minFileAgeMinutes', 0, 'protocols', false, 'register', false, 'resultFormat', 'csv', 'trends', false};
X = MyoDishAnalysisWatch(rawI, res, q5{:});
pass = isequal(X.file', {'E/empty.mdd', 'I/half.mdd', 'L/emptylog.mdd', 'R/robo.mdd', 'T/short5s.mdd'}) && ...
    isequal(X.status', {'incomplete', 'incomplete', 'noLog', 'incomplete', 'ok'}) && ...
    startsWith(X.message{1}, 'empty file (0 bytes)') && ...
    startsWith(X.message{2}, 'file 333 s, recording in the log file 667 s (50.1 % missing)') && ...
    contains(X.message{3}, 'empty') && contains(X.message{4}, 'before 1990');
ok = check(ok, pass, 'file shorter than the log / empty / dated 1980 --> incomplete, empty log --> noLog, 5 s missing: ok');
X = MyoDishAnalysisWatch(rawI, res, q5{:}, 'incompleteAfterHours', 0.5);
pass = isequal(X.status', {'incomplete', 'ok', 'noLog', 'incomplete', 'ok'}) && ...
    contains(X.message{2}, 'analysed after 0.5 h without change');
ok = check(ok, pass, 'incomplete file unchanged for ''incompleteAfterHours'': analysed with a note; empty, 1980: until copied');
namedCopy(ex, fullfile(rawI, 'I'), 'half', [], 60);                         %copy completed
X = MyoDishAnalysisWatch(rawI, res, q5{:});
ok = check(ok, strcmp(X.status{2}, 'ok') && ~contains(X.message{2}, 'incomplete'), 'completed copy analysed again');

% parallel recordings (2026-10-13; as test_watch.py): schedule file with its main file --> 'parallel' (default),
% 'parallel','analyse'; without main file, software 2020 (own 'parallel recording' entries) and a main file listing a
% parallel recording of the same name with another duration --> analysed; slice register without parallel files
rawP = fullfile(root, 'rawParallel'); res = fullfile(root, 'resParallel');
par = 'C:\data\S1_X_1_scheduleFile.mdd';
m = namedCopy(ex, fullfile(rawP, 'P'), 'S1_X_1', []);
editLog(m, {0, 'started: S1_X_1.mdd'; 100000, ['started parallel recording: ' par]; ...
    400000, ['stopped parallel recording: ' par]; 666680, 'stopped: S1_X_1.mdd'});
for d = {'P', 'Q'}
    p = namedCopy(ex, fullfile(rawP, d{1}), 'S1_X_1_scheduleFile', 300);
    editLog(p, {5, ['started parallel recording: ' par]; 300005, ['stopped parallel recording: ' par]});
end
o = namedCopy(ex, fullfile(rawP, 'O'), 'S2_X_0', []);
editLog(o, {0, 'started parallel recording: C:\x\S2_X_0.mdd'; 666680, 'stopped parallel recording: C:\x\S2_X_0.mdd'});
w = namedCopy(ex, fullfile(rawP, 'W'), 'S3_X_1', []);
editLog(w, {0, 'started: S3_X_1.mdd'; 100000, 'started parallel recording: C:\x\S3_X_1_ffr.mdd'; ...
    300000, 'stopped parallel recording: C:\x\S3_X_1_ffr.mdd'; 666680, 'stopped: S3_X_1.mdd'});
w2 = namedCopy(ex, fullfile(rawP, 'W'), 'S3_X_1_ffr', 300);
editLog(w2, {5, 'started parallel recording: C:\x\S3_X_1_ffr.mdd'; 300005, 'stopped parallel recording: C:\x\S3_X_1_ffr.mdd'});
q6 = {'quiet', true, 'minFileAgeMinutes', 0, 'protocols', false, 'resultFormat', 'csv', 'trends', false};
X = MyoDishAnalysisWatch(rawP, res, q6{:});
pass = isequal(X.file', {'O/S2_X_0.mdd', 'P/S1_X_1.mdd', 'P/S1_X_1_scheduleFile.mdd', 'Q/S1_X_1_scheduleFile.mdd', ...
    'W/S3_X_1.mdd', 'W/S3_X_1_ffr.mdd'}) && isequal(X.status', {'ok', 'ok', 'parallel', 'ok', 'ok', 'ok'}) && ...
    startsWith(X.message{3}, 'parallel recording of P/S1_X_1.mdd (100.0-400.0 s of the main file)') && ...
    ~isfile(fullfile(res, 'P', 'S1_X_1_scheduleFile_summary.csv'));
ok = check(ok, pass, 'parallel recording with main file --> parallel; without main file, 2020 log, other duration --> ok');
[~, report] = MyoDishAnalysisWatch(rawP, res, q6{:});
ok = check(ok, isempty(report), 'parallel recordings: second pass nothing to do');
X = MyoDishAnalysisWatch(rawP, res, q6{:}, 'parallel', 'analyse');
regP = @(r) strjoin(cellfun(@char, table2cell(r(strcmp(r.experiment, 'P'), {'firstRecording', 'lastRecording'})), ...
    'UniformOutput', false), ' ');
R = readCsv(fullfile(res, 'mda_slices.csv'));
pass = strcmp(X.status{3}, 'ok') && startsWith(X.message{3}, ['parallel recording of P/S1_X_1.mdd (100.0-400.0 s ' ...
    'of the main file): analysed (parallel=''analyse'')']) && ~contains(regP(R), 'scheduleFile') && ~isempty(regP(R));
ok = check(ok, pass, '''parallel'', ''analyse'': analysed and marked, not counted in the slice register (2026-10-14)');
X = MyoDishAnalysisWatch(rawP, res, q6{:}, 'reanalyze', 'all', 'filter', '^P/');
R = readCsv(fullfile(res, 'mda_slices.csv'));
ok = check(ok, strcmp(X.status{3}, 'parallel') && ~contains(regP(R), 'scheduleFile') && ~isempty(regP(R)), ...
    'parallel again: its earlier results ignored by the slice register');
r2 = fullfile(root, 'resParallel2');
[X, report] = MyoDishAnalysisWatch(rawP, r2, q6{:}, 'include', '*schedule*');
R = readCsv(fullfile(r2, 'mda_slices.csv'));
pass = isequal(X.status', {'ok', 'ok'}) && startsWith(X.message{1}, ['parallel recording of P/S1_X_1.mdd ' ...
    '(100.0-400.0 s of the main file): analysed (main file not selected)']) && ...
    ~contains(report, 'not analysed although') && contains(regP(R), 'scheduleFile');
ok = check(ok, pass, 'only the parallel files (main file not selected): analysed, marked, counted without main results');
X = MyoDishAnalysisWatch(rawP, r2, q6{:});
R = readCsv(fullfile(r2, 'mda_slices.csv'));
ok = check(ok, strcmp(X.status{strcmp(X.file, 'P/S1_X_1.mdd')}, 'ok') && ~contains(regP(R), 'scheduleFile') && ...
    contains(regP(R), 'S1_X_1'), 'main file analysed later: the parallel file no longer counted in the slice register');
% flags table of the report (mda_flags.csv, 2026-10-14): written by the watcher, computed again = same flags
[T, missing] = MyoDishAnalysisWatch('flags', r2);
delete(fullfile(r2, 'mda_flags.csv'));
[T0, missing0] = MyoDishAnalysisWatch('flags', r2);
[T2, missing2] = MyoDishAnalysisWatch('flags', r2, true);
T = sortrows(T, {'file', 'channel'}); T2 = sortrows(T2, {'file', 'channel'});
pass = isempty(missing) && height(T) > 0 && height(T0) == 0 && numel(missing0) == 6 && isempty(missing2) && ...
    isfile(fullfile(r2, 'mda_flags.csv')) && isequal(T.file, T2.file) && isequal(T.channel, T2.channel) && ...
    isequal(T.flags, T2.flags) && isequal(T.level, T2.level);
ok = check(ok, pass, 'flags table mda_flags.csv: written by the watcher, computed again from the results');
M = MyoDishAnalysisWatch('mainRecording', fullfile(rawP, 'P', 'S1_X_1_scheduleFile.mdd'));
M2 = MyoDishAnalysisWatch('mainRecording', fullfile(rawP, 'Q', 'S1_X_1_scheduleFile.mdd'));
ok = check(ok, ~isempty(M) && endsWith(M.main, 'S1_X_1.mdd') && M.a == 100 && M.b == 400 && isempty(M2), ...
    '''mainRecording'': main file and window of a parallel recording (GUI)');
try
    MyoDishAnalysisWatch(rawP, fullfile(root, 'resParallel3'), q6{:}, 'parallel', 'sometimes'); pass = false;
catch
    pass = true;
end
ok = check(ok, pass, '''parallel'', ''sometimes'': error');

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

function T = readSheet(f, sheet)
% sheet of a results .xlsx with the text columns as text
o = detectImportOptions(f, 'Sheet', sheet, 'TextType', 'char');
o.VariableNamesRange = 'A1'; o.DataRange = 'A2';
txt = intersect(o.VariableNames, {'range', 'bin', 'comments', 'beatType', 'category', 'text', 'code', 'status', ...
    'window', 'clockTime'});
o = setvartype(o, txt, 'char');
T = readtable(f, o);
end

function T = readCsvGz(f)
% <f>.gz (readtable does not read .gz)
tmp = tempname; mkdir(tmp);
c = onCleanup(@() rmdir(tmp, 's'));
gunzip([f '.gz'], tmp);
[~, n, e] = fileparts(f);
T = readCsv(fullfile(tmp, [n e]));
end

function T = readCsv(f)
% csv result file with the text columns as text (readtable would turn clock-time labels into datetime)
o = detectImportOptions(f, 'TextType', 'char');
txt = intersect(o.VariableNames, {'range', 'bin', 'comments', 'beatType', 'sampleMode', 'category', 'text', 'code', ...
    'window', 'experiment', 'series', 'startTime', 'endTime', 'startReason', 'endStatus', 'species', 'sliceID', 'setupID', ...
    'sampleID', 'idDate', 'lastBeat', 'daySource', 'firstRecording', 'lastRecording', 'endComments'});
o = setvartype(o, txt, 'char');
T = readtable(f, o);
end

function T = readFlagsCsv(f)
% mda_flags.csv with the text columns as text
o = detectImportOptions(f, 'FileType', 'text', 'Delimiter', ',');
o = setvartype(o, intersect(o.VariableNames, {'file', 'analyzed', 'label', 'status', 'flags', 'level', 'red', ...
    'yellow'}), 'char');
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

function f = namedCopy(ex, dest, name, seconds, ageSeconds)
% example 9 (400 Hz, 2 channels, 666.68 s) as <dest>/<name>.mdd with log file, truncated to seconds ([] = whole);
% files ageSeconds old (default 3600)
if nargin < 5, ageSeconds = 3600; end
if ~isfolder(dest), mkdir(dest); end
f = fullfile(dest, [name '.mdd']);
fid = fopen(fullfile(ex, 'example9_ratVentricle.mdd'), 'r'); b = fread(fid, inf, 'uint8=>uint8'); fclose(fid);
if ~isempty(seconds), b = b(1:round(seconds * 400) * 4); end
fid = fopen(f, 'w'); fwrite(fid, b, 'uint8'); fclose(fid);
copyfile(fullfile(ex, 'example9_ratVentricle_log.log'), [f(1:end-4) '_log.log']);
ageFiles({f, [f(1:end-4) '_log.log']}, ageSeconds);
end

function ageFiles(files, s)
ms = int64((posixtime(datetime('now', 'TimeZone', 'local')) - s) * 1000);
for k = 1:numel(files), java.io.File(files{k}).setLastModified(ms); end
end

function editLog(f, rec)
% 'Recording' entries of the log file of f replaced by rec = {dataLogTime ms, text; ...}: 'started' entries at the place
% of the first, 'stopped' entries at the place of the last Recording entry (as _edit_log in test_watch.py)
lf = [f(1:end-4) '_log.log'];
L = regexp(readUtf16(lf), '\r?\n', 'split');
k = find(contains(L, ';Recording;'));
clk = strtok(L{k(1)}, ';');
new = cell(size(L)); new(k) = {{}};
for i = 1:size(rec, 1)
    j = k(1); if contains(rec{i,2}, 'stopped'), j = k(end); end
    new{j}{end+1} = sprintf('%s;%d;0;Recording;%s', clk, rec{i,1}, rec{i,2});
end
out = {};
for i = 1:numel(L)
    if ismember(i, k), out = [out new{i}]; else, out{end+1} = L{i}; end %#ok<AGROW>
end
out = out(~cellfun(@isempty, out));
fid = fopen(lf, 'w'); fprintf(fid, '%s\n', out{:}); fclose(fid);
ageFiles({lf}, 3600);
end

function shiftLog(lf, hoursAgo)
% clock times of the log file shifted: the recording started hoursAgo h ago (as _edit_log in test_watch.py)
L = regexp(fileread(lf), '\r?\n', 'split');
L = L(~cellfun(@isempty, L));
k = find(contains(L, ';Recording;started'), 1);
t0 = datenum(L{k}(1:19), 'yyyy mm dd HH:MM:SS');
d = now - hoursAgo / 24 - t0;
for i = 2:numel(L)
    L{i} = [datestr(datenum(L{i}(1:19), 'yyyy mm dd HH:MM:SS') + d, 'yyyy mm dd HH:MM:SS') L{i}(20:end)];
end
fid = fopen(lf, 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
end
