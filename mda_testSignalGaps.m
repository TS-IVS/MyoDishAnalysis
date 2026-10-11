function ok = mda_testSignalGaps()
%MDA_TESTSIGNALGAPS  Test of the periods without signal (mda_signalGaps) and of the watcher outputs _gaps.csv and
%_channels.csv with a synthetic recording (9 channels, 400 Hz, 600 s).
%
%   ok = mda_testSignalGaps()   prints the single checks, returns true if all pass
%
% Periods (value held = no noise): ch1 100-160 s with a spike before and another level after (chamber out), ch1 200 s
% and ch3 200.05 s (2 channels of group 1-4 within 0.1 s: board group), ch5-8 from 300.0/300.1/300.25/300.4 s (board
% group of 4 within 1 s), ch4 0-50 s (from the start) and 400-410 s at 32767 (saturated), ch7 450 s and ch1 450.05 s
% (both groups: controller), ch3 from 500 s to the end, ch6 520-540 s with one different sample at 530 s (one
% period), ch8 570 s and ch4 570.4 s (two chambers taken out with both hands: chamber out), ch2 the whole file (no
% signal). Pendant of py/tests/test_signal_gaps.py (same recording and checks).
%
% TS 2026-10-08

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

ok = true;
folder = tempname; mkdir(fullfile(folder, 'raw'));
cleanup = onCleanup(@() rmdir(folder, 's')); %#ok<NASGU>
f = fullfile(folder, 'raw', 'gaps_ABC000101.mdd');
writeRecording(f);

G = mda_signalGaps(f);
row = @(c, a) G(G.channel == c & abs(G.from - a) < 1e-9, :);
r = row(1, 100);
ok = check(ok, 'chamber out: ch1 100-160 s', height(r) == 1 && strcmp(r.type{1}, 'chamber out') && ...
    abs(r.to - 160) < 1e-9 && r.value == -10000 && r.nSimultaneous == 1 && ~r.fromStart && ~r.untilEnd);
ok = check(ok, 'level change +300 uN after putting the chamber back, spike before', ...
    abs(r.levelChange - 300) < 5 && r.spikeBefore > 1900 && abs(r.spikeAfter) < 100);
ok = check(ok, 'board group of 2 (ch1 200 s, ch3 200.05 s)', strcmp(row(1, 200).type{1}, 'board group') && ...
    strcmp(row(3, 200.05).type{1}, 'board group') && row(3, 200.05).nSimultaneous == 2 && ...
    abs(row(3, 200.05).spread - 0.05) < 1e-9);
g4 = G(G.channel >= 5 & G.from >= 299 & G.from <= 301, :);
ok = check(ok, 'board group of 4 (ch5-8 within 0.4 s)', height(g4) == 4 && all(strcmp(g4.type, 'board group')) && ...
    all(g4.nSimultaneous == 4) && all(abs(g4.to - 360) < 1e-9) && all(abs(g4.spread - 0.4) < 1e-9));
r = row(4, 0);
ok = check(ok, 'from the start: ch4 0-50 s', height(r) == 1 && r.fromStart && abs(r.to - 50) < 1e-9 && ...
    strcmp(r.type{1}, 'chamber out') && isnan(r.levelBefore) && ~isnan(r.levelAfter));
ok = check(ok, 'saturated: ch4 400-410 s at 32767', strcmp(row(4, 400).type{1}, 'saturated') && row(4, 400).valueAU == 32767);
ok = check(ok, 'controller (ch7 450 s, ch1 450.05 s)', strcmp(row(7, 450).type{1}, 'controller') && ...
    strcmp(row(1, 450.05).type{1}, 'controller'));
ok = check(ok, 'two hands: ch8 570 s, ch4 570.4 s (2 channels, 0.4 s apart) are chamber out', ...
    strcmp(row(8, 570).type{1}, 'chamber out') && strcmp(row(4, 570.4).type{1}, 'chamber out') && ...
    row(8, 570).nSimultaneous == 1 && row(4, 570.4).spread == 0);
r = row(3, 500);
ok = check(ok, 'until the end: ch3 from 500 s', height(r) == 1 && r.untilEnd && strcmp(r.type{1}, 'chamber out') && isnan(r.levelAfter));
r = row(6, 520);
ok = check(ok, 'one different sample at 530 s: one period 520-540 s', height(r) == 1 && abs(r.to - 540) < 1e-9 && ...
    sum(G.channel == 6 & G.from > 521 & G.from < 541) == 0);
r = G(G.channel == 2, :);
ok = check(ok, 'no signal: ch2 whole file', height(r) == 1 && strcmp(r.type{1}, 'no signal') && r.fromStart && r.untilEnd);
ok = check(ok, 'number of periods (16)', height(G) == 16);

% watcher: _gaps.csv, _channels.csv, summary columns
res = fullfile(folder, 'res');
[X, report] = MyoDishAnalysisWatch(fullfile(folder, 'raw'), res, 'quiet', true, 'minFileAgeMinutes', 0, 'protocols', false);
Gw = readCsv(fullfile(res, 'gaps_ABC000101_gaps.csv'));
CH = readCsv(fullfile(res, 'gaps_ABC000101_channels.csv'));
S = readCsv(fullfile(res, 'gaps_ABC000101_summary.csv'));
ok = check(ok, 'watcher: _gaps.csv with clock times and comments', strcmp(X.status{1}, 'ok') && height(Gw) == 16 && ...
    all(ismember({'clockFrom', 'clockTo', 'comments'}, Gw.Properties.VariableNames)) && ...
    any(contains(Gw.comments, 'chamber 1 out')));
st = @(c) CH.status{CH.channel == c};
ok = check(ok, 'watcher: _channels.csv status (no slice, removed, beating if contractions)', strcmp(st(2), 'no slice') && ...
    strcmp(st(3), 'removed') && strcmp(st(1), 'beating') == (CH.nContractions(CH.channel == 1) > 0) && ...
    abs(CH.lastSignal_s(CH.channel == 3) - 500) < 1e-6 && ...
    strcmp(CH.idDate{1}, '2000-01-01') && contains(CH.endComments{CH.channel == 3}, 'discarded'));
s1 = S(S.channel == 1, :);
ok = check(ok, 'watcher: summary noSignal_s and nChamberOut', abs(sum(s1.noSignal_s) - 79.95) < 1e-6 && ...
    sum(s1.nChamberOut) == 1 && contains(report, 'signal gaps: 6 chamber out, 6 board group, 2 controller, 1 saturated'));
% slice register: one slice per channel with signal; short chamber-out periods and technical periods belong to it
R = readCsv(fullfile(res, 'mda_slices.csv'));
r1 = R(R.channel == 1, :); r3 = R(R.channel == 3, :); r4 = R(R.channel == 4, :);
ok = check(ok, 'slice register: 7 slices, chamber out / removed / from the start', height(R) == 7 && ...
    ~any(R.channel == 2) && contains(report, 'slice register: 7 slices in 1 experiment(s)') && ...
    r1.nChamberOut == 1 && abs(r1.outHours - 60 / 3600) < 1e-9 && strcmp(r1.startReason{1}, 'first signal') && ...
    abs(r1.dayStart - 10 / 24) < 1e-9 && strcmp(r1.daySource{1}, 'idDate') && strcmp(r3.endStatus{1}, 'removed') && ...
    strcmp(r3.endTime{1}, '2000-01-01 10:08:20') && contains(r3.endComments{1}, 'discarded') && ...
    strcmp(r4.startTime{1}, '2000-01-01 10:00:50') && r4.nChamberOut == 1);
end


function T = readCsv(f)
% table of a results file; text columns as text (not datetime)
o = detectImportOptions(f, 'TextType', 'char', 'Delimiter', ',');
txt = intersect({'idDate', 'clockFrom', 'clockTo', 'lastContractionClock', 'status', 'type', 'comments', ...
    'endComments', 'range', 'bin', 'experiment', 'series', 'startTime', 'endTime', 'startReason', 'endStatus', 'daySource', ...
    'lastBeat', 'species', 'sliceID', 'setupID', 'sampleID', 'firstRecording', 'lastRecording', 'recording', ...
    'recordingStart', 'cultureStart'}, o.VariableNames);
o = setvartype(o, txt, 'char');
T = readtable(f, o);
end


function writeRecording(f)
fs = 400; T = 600; n = T * fs; nCh = 9;
k = (0:n-1);
x = zeros(nCh, n);
for c = 1:8
    x(c, :) = round(-10000 + 500 * c + 20 * sin(0.7 * k + c) + 13 * sin(1.3 * k + 0.5 * c));
end
x(1, 39921:39960) = x(1, 39921:39960) + 2000;          %spike 99.8-99.9 s
x(1, 64001:end) = x(1, 64001:end) + 300;               %other level after putting the chamber back
hold = @(x, c, a, b, v) setRange(x, c, round(a * fs) + 1, round(b * fs), v);
x = hold(x, 1, 100, 160, -10000);
x = hold(x, 1, 200, 210, -10001);
x = hold(x, 3, 200.05, 210, -10002);
x = hold(x, 5, 300, 360, -383); x = hold(x, 6, 300.1, 360, -383); x = hold(x, 7, 300.25, 360, -383); x = hold(x, 8, 300.4, 360, -383);
x = hold(x, 4, 0, 50, -9000);
x = hold(x, 4, 400, 410, 32767);
x = hold(x, 7, 450, 460, -5000); x = hold(x, 1, 450.05, 460, -5001);
x = hold(x, 3, 500, 600, -8000);
x = hold(x, 6, 520, 540, -7000); x(6, 530 * fs + 1) = -6999;
x = hold(x, 8, 570, 580, -6000); x = hold(x, 4, 570.4, 585, -6001);
x(2, :) = -383;
x(9, :) = 0;                                           %status channel: no stimuli, rocker at rest
fid = fopen(f, 'w'); fwrite(fid, int16(x), 'int16'); fclose(fid);
lf = strrep(f, '.mdd', '_log.log');
L = {'systemTime;dataLogTime;channel;code;value', ...
    '2000 01 01 10:00:00:000;0;0;samplingRate Recording;400', ...
    '2000 01 01 10:00:00:000;0;0;Recording;started: gaps_ABC000101.mdd', ...
    '2000 01 01 10:01:41:000;101000;1;comment;chamber 1 out', ...
    '2000 01 01 10:08:20:000;500000;3;comment;discarded', ...
    '2000 01 01 10:10:00:000;600000;0;Recording;stopped: gaps_ABC000101.mdd'};
fid = fopen(lf, 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
end


function x = setRange(x, c, i0, i1, v)
x(c, i0:i1) = v;
end


function ok = check(ok, name, pass)
fprintf('%-72s %s\n', name, passStr(pass));
ok = ok && pass;
end


function s = passStr(pass)
if pass, s = 'ok'; else, s = 'FAILED'; end
end
