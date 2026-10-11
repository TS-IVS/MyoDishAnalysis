function ok = mda_testSliceRegister()
%MDA_TESTSLICEREGISTER  Test of the slice register (mda_sliceRegister) with synthetic watcher results: experiment
%expA, series rigA_sampleX (4 recordings, channels 1-8) and rigB_sampleY (1 recording).
%
%   ok = mda_testSliceRegister()   prints the single checks, returns true if all pass
%
%   ch1  medium changes (2 x 5 min)                               1 slice, beating at end of data
%   ch2  taken out on day 2 (comment 'discarded'), then empty      1 slice, removed, last amplitude 50 of 200
%   ch3  taken out on day 1, one recording empty, new slice day 3  2 slices (after a recording without signal)
%   ch4  5 min out with the comment 'new slice'                    2 slices (comment)
%   ch5  4 h out                                                   2 slices (after 4.0 h without signal)
%   ch6  no slice                                                  no row
%   ch7  label sliceID S7a --> S7b                                 2 slices (other sliceID)
%   ch8  no contractions after day 2                               1 slice, not beating at end of data
%   rigB ch1 with label cultureStart                               days since cultureStart
%   rigB ch2 3 h out with the comment 'slice moved back'            1 slice (put back), nPutBack 1
% Pendant of py/tests/test_slice_register.py (same results and checks).
%
% TS 2026-10-08

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

ok = true;
res = tempname; mkdir(fullfile(res, 'expA'));
cleanup = onCleanup(@() rmdir(res, 's')); %#ok<NASGU>
writeScenario(fullfile(res, 'expA'));
R = mda_sliceRegister(res);
A = readCsv(fullfile(res, 'mda_slices.csv'));
E = readCsv(fullfile(res, 'expA', 'expA_slices.csv'));
ok = check(ok, '13 slices (register, mda_slices.csv, expA_slices.csv)', height(R) == 13 && height(A) == 13 && ...
    height(E) == 13);
get = @(s, c) R(strcmp(R.series, s) & R.channel == c, :);
H = 3600;
r = get('rigA_sampleX', 1);
ok = check(ok, 'ch1: medium changes, beating at end of data, days since idDate', height(r) == 1 && ...
    strcmp(r.endStatus{1}, 'beating at end of data') && r.beatingAtEnd == 1 && r.nChamberOut == 2 && ...
    abs(r.outHours - 600 / H) < 1e-9 && r.nRecordings == 4 && strcmp(r.startTime{1}, '2000-01-01 16:00:00') && ...
    strcmp(r.endTime{1}, '2000-01-05 06:00:00') && abs(r.dayStart - 16 / 24) < 1e-9 && ...
    abs(r.dayEnd - 4.25) < 1e-9 && ...
    strcmp(r.daySource{1}, 'idDate'));
r = get('rigA_sampleX', 2);
ok = check(ok, 'ch2: removed, last amplitude 50 of 200, end comment', height(r) == 1 && ...
    strcmp(r.endStatus{1}, 'removed') && strcmp(r.endTime{1}, '2000-01-03 12:00:00') && r.lastAmplitude == 50 && ...
    r.maxAmplitude == 200 && abs(r.lastAmplitude_pctMax - 25) < 1e-9 && contains(r.endComments{1}, 'discarded'));
r = get('rigA_sampleX', 3);
ok = check(ok, 'ch3: new slice after a recording without signal (inserted later)', height(r) == 2 && ...
    strcmp(r.endStatus{1}, 'removed') && strcmp(r.endTime{1}, '2000-01-02 12:00:00') && ...
    strcmp(r.startReason{2}, 'after a recording without signal') && strcmp(r.startTime{2}, '2000-01-04 08:00:00') && ...
    r.insertedLater(2) == 1 && isnan(r.dayStart(2)) && strcmp(r.daySource{2}, 'unknown (inserted later)'));
r = get('rigA_sampleX', 4);
ok = check(ok, 'ch4: new slice after the comment ''new slice''', height(r) == 2 && ...
    startsWith(r.startReason{2}, 'comment:') && contains(r.startReason{2}, 'new slice') && ...
    strcmp(r.endStatus{1}, 'removed') && strcmp(r.startTime{2}, '2000-01-03 10:05:00'));
r = get('rigA_sampleX', 5);
ok = check(ok, 'ch5: new slice after 4 h without signal', height(r) == 2 && ...
    strcmp(r.startReason{2}, 'after 4.0 h without signal'));
ok = check(ok, 'ch6: no slice, no row', height(get('rigA_sampleX', 6)) == 0);
r = get('rigA_sampleX', 7);
ok = check(ok, 'ch7: other sliceID', height(r) == 2 && strcmp(r.endStatus{1}, 'replaced (other sliceID)') && ...
    strcmp(r.startReason{2}, 'other sliceID') && strcmp(r.sliceID{2}, 'S7b') && ...
    strcmp(r.startTime{2}, '2000-01-03 06:00:00'));
r = get('rigA_sampleX', 8);
ok = check(ok, 'ch8: not beating at end of data', height(r) == 1 && ...
    strcmp(r.endStatus{1}, 'not beating at end of data') && r.beatingAtEnd == 0 && ...
    strcmp(r.lastBeat{1}, '2000-01-03 05:41:00'));
r = get('rigB_sampleY', 2);
ok = check(ok, 'rigB ch2: 3 h out, comment ''moved back'': same slice', height(r) == 1 && r.nPutBack == 1 && ...
    r.nChamberOut == 1 && abs(r.outHours - 3) < 1e-9 && strcmp(r.endStatus{1}, 'beating at end of data'));
r = get('rigB_sampleY', 1);
ok = check(ok, 'rigB ch1: days since cultureStart', height(r) == 1 && strcmp(r.daySource{1}, 'cultureStart') && ...
    abs(r.dayStart - 28 / 24) < 1e-9);
ok = check(ok, 'mda_slices.csv in the order of the register', isequal(A.slice, R.slice));
end


function writeScenario(folder)
DAY = 86400; H = 3600;
rec = {'rigA_sampleX_0', 16 * H, 14 * H; 'rigA_sampleX_1', DAY + 6 * H, DAY; 'rigA_sampleX_2', 2 * DAY + 6 * H, DAY; ...
    'rigA_sampleX_3', 3 * DAY + 6 * H, DAY; 'rigB_sampleY_0', 16 * H, 14 * H};
nR = size(rec, 1);
% channels: rows {recording index, channel, status, sliceID, cultureStart, endComments}
ch = {};
for k = 1:4
    for c = 1:8
        sid = '';
        if c == 7, if k <= 2, sid = 'S7a'; else, sid = 'S7b'; end, end
        st = 'beating'; if c == 6, st = 'no slice'; end
        ch(end+1, :) = {k, c, st, sid, '', ''}; %#ok<AGROW>
    end
end
ch(end+1, :) = {5, 1, 'beating', '', '1999-12-31 12:00', ''};
ch(end+1, :) = {5, 2, 'beating', '', '', ''};
setStatus = @(ch, k, c, st, txt) setRow(ch, k, c, st, txt);
% gaps: {recording index, channel, from, to, comments}
gp = {};
for k = 1:4, gp(end+1, :) = {k, 6, 0, rec{k,3}, ''}; end %#ok<AGROW>
gp(end+1, :) = {2, 1, 4 * H, 4 * H + 300, ''};
gp(end+1, :) = {3, 1, 4 * H, 4 * H + 300, ''};
gp(end+1, :) = {3, 2, 6 * H, DAY, 'discarded'};
ch = setStatus(ch, 3, 2, 'removed', 'discarded');
ch = setStatus(ch, 4, 2, 'no slice', '');
gp(end+1, :) = {4, 2, 0, DAY, ''};
gp(end+1, :) = {2, 3, 6 * H, DAY, ''};
ch = setStatus(ch, 2, 3, 'removed', '');
ch = setStatus(ch, 3, 3, 'no slice', '');
gp(end+1, :) = {3, 3, 0, DAY, ''};
gp(end+1, :) = {4, 3, 0, 2 * H, ''};
gp(end+1, :) = {3, 4, 4 * H, 4 * H + 300, 'new slice'};
gp(end+1, :) = {2, 5, 3 * H, 7 * H, ''};
gp(end+1, :) = {5, 2, 2 * H, 5 * H, 'slice moved back'};
ch = setStatus(ch, 3, 8, 'not beating', '');
ch = setStatus(ch, 4, 8, 'not beating', '');
for k = 1:nR
    name = rec{k,1}; L = rec{k,3};
    t0 = rec{k,2};
    clk = sprintf('%s %02d:%02d:%02d', datestr(datenum(2000, 1, 1) + floor(t0 / 86400), 'yyyy-mm-dd'), ...
        floor(mod(t0, 86400) / 3600), floor(mod(t0, 3600) / 60), mod(t0, 60));
    I = find([ch{:,1}] == k);
    n = numel(I);
    T = table(repmat({name}, n, 1), repmat({clk}, n, 1), repmat(L, n, 1), [ch{I,2}]', ch(I,3), zeros(n, 1), ...
        nan(n, 1), nan(n, 1), nan(n, 1), zeros(n, 1), repmat({'2000-01-01'}, n, 1), repmat({''}, n, 1), ch(I,4), ...
        repmat({''}, n, 1), repmat({''}, n, 1), ch(I,5), ch(I,6), 'VariableNames', {'recording', 'recordingStart', ...
        'fileLength_s', 'channel', 'status', 'nTechnical', 'lastContraction_s', 'lastAmplitude', 'maxAmplitude', ...
        'nContractions', 'idDate', 'setupID', 'sliceID', 'species', 'sampleID', 'cultureStart', 'endComments'});
    writetable(T, fullfile(folder, [name '_channels.csv']));
    J = find([gp{:,1}] == k);
    a = [gp{J,3}]'; b = [gp{J,4}]';
    typ = repmat({'chamber out'}, numel(J), 1);
    typ(a == 0 & b == L) = {'no signal'};
    G = table([gp{J,2}]', a, b, typ, double(a == 0), double(b == L), gp(J,5), 'VariableNames', ...
        {'channel', 'from', 'to', 'type', 'fromStart', 'untilEnd', 'comments'});
    writetable(G, fullfile(folder, [name '_gaps.csv']));
    % overview: one 60-s window every 20 min of signal, 60 beats; amplitude 100 (ch2: 200, last window before the
    % removal 50)
    ov = zeros(0, 4);
    for i = I
        c = ch{i,2};
        if strcmp(ch{i,3}, 'no slice'), continue; end
        g = gp([gp{:,1}] == k & [gp{:,2}] == c, :);
        outs = sortrows([[g{:,3}]', [g{:,4}]']);
        segs = zeros(0, 2); t = 0;
        for j = 1:size(outs, 1)
            if outs(j,1) > t, segs(end+1, :) = [t, outs(j,1)]; end %#ok<AGROW>
            t = max(t, outs(j,2));
        end
        if t < L, segs(end+1, :) = [t, L]; end %#ok<AGROW>
        for q = 1:size(segs, 1)
            for w = segs(q,1):1200:segs(q,2) - 1e-9
                if c == 8 && (k == 3 || k == 4), continue; end
                amp = 100; if c == 2, amp = 200; end
                if c == 2 && k == 3 && w + 1200 >= segs(q,2), amp = 50; end
                ov(end+1, :) = [c, w, min(w + 60, segs(q,2)), amp]; %#ok<AGROW>
            end
        end
    end
    m = size(ov, 1);
    O = table(ov(:,1), ov(:,2), ov(:,3), repmat({'stimulated'}, m, 1), ones(m, 1), repmat(60, m, 1), ov(:,4), ...
        'VariableNames', {'channel', 't_from', 't_to', 'beatType', 'included', 'nBeats', 'amplitude'});
    writetable(O, fullfile(folder, [name '_overview.csv']));
end
end


function ch = setRow(ch, k, c, st, txt)
i = find([ch{:,1}] == k & [ch{:,2}] == c, 1);
ch{i,3} = st; ch{i,6} = txt;
end


function T = readCsv(f)
o = detectImportOptions(f, 'TextType', 'char', 'Delimiter', ',');
txt = intersect({'experiment', 'series', 'setupID', 'sampleID', 'species', 'sliceID', 'idDate', 'startTime', ...
    'endTime', ...
    'startReason', 'endStatus', 'lastBeat', 'daySource', 'firstRecording', 'lastRecording', 'endComments'}, ...
    o.VariableNames);
o = setvartype(o, txt, 'char');
T = readtable(f, o);
end


function ok = check(ok, name, pass)
fprintf('%-72s %s\n', name, passStr(pass));
ok = ok && pass;
end


function s = passStr(pass)
if pass, s = 'ok'; else, s = 'FAILED'; end
end
