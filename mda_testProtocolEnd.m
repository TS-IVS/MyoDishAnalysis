function ok = mda_testProtocolEnd()
%MDA_TESTPROTOCOLEND  Test of the end of protocols without end comment (mda_protocols) with a synthetic recording
%(9 channels, 400 Hz, 2400 s; stimuli of channels 1 and 2 in the status channel).
%
%   ok = mda_testProtocolEnd()   prints the single checks, returns true if all pass
%
%      0- 300 s  0.5 Hz, 60 mA (regular)
%    300 s       'start stimCurrent threshold protocol': current steps 20, 30, 40, 50, 70, 80 mA every 40 s
%    540-1000    0.5 Hz, 60 mA                    --> ST ends at 540 s (regular pacing)
%   1000 s       'start post rest potentiation protocol': 3 trains of 10 stimuli (0.5 Hz), 30 s pauses
%   1150 s       'start FFR protocol': 1 Hz, 2 Hz (100 s each)   --> PRP ends at 1150 s (next protocol)
%   1350-2400    0.5 Hz, 60 mA                    --> FFR ends at 1350 s (regular pacing)
%   1800 s       'start pulse duration protocol': pulse duration (log chargeDuration) 1000, 500, 250, 2000 us
%                every 30 s, interval and current unchanged   --> PD ends at 1890 s (pulse duration unchanged)
% Second recording (2026-10-11): protocol keywords of comments (unknown type, StimThresh) and interruptions (software
% restart, connection lost). Pendant of py/tests/test_protocol_end.py (same recordings and checks).
%
% TS 2026-10-10

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

ok = true;
T = 2400; fs = 400;
folder = tempname; mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's')); %#ok<NASGU>
f = fullfile(folder, 'pend_rigA_0.mdd');
writeRecording(f, T, fs);
P = mda_protocols(f);
ok = check(ok, 'types and starts', isequal(P.type', {'ST', 'PRP', 'FFR', 'PD'}) && ...
    isequal(P.from', [300 1000 1150 1800]));
ok = check(ok, 'estimated ends: regular pacing, next protocol, regular pacing, pulse duration unchanged', ...
    max(abs(P.to' - [540 1150 1350 1890])) < 1e-9);
ok = check(ok, 'notes', ...
    strcmp(P.note{1}, 'no end comment: end estimated at 540 s (start of regular pacing: 0.5 Hz, 60 mA, > 5 min)') && ...
    strcmp(P.note{2}, 'no end comment: end estimated at 1150 s (start of the next protocol ''FFR protocol'')') && ...
    strcmp(P.note{3}, ['no end comment: end estimated at 1350 s (start of regular pacing: 0.5 Hz, 60 mA, ' ...
    '> 5 min)']) && ...
    strcmp(P.note{4}, ['no end comment: end estimated at 1890 s (start of regular pacing: 0.5 Hz, 60 mA, ' ...
    '> 5 min)']));
L = mda_protocols(strrep(f, '.mdd', '_log.log'));
ok = check(ok, 'log file only: next protocol or end of the file', ...
    max(abs(L.to(1:3)' - [1000 1150 1800])) < 1e-9 && ...
    isinf(L.to(4)) && strcmp(L.note{4}, 'no end comment: end estimated at Inf s (end of the file)'));
P0 = mda_protocols(f, 0);
ok = check(ok, 'without the end estimation from the stimuli', max(abs(P0.to' - [1000 1150 1800 T])) < 1e-9 && ...
    strcmp(P0.note{4}, sprintf('no end comment: end estimated at %d s (end of the file)', T)));
% 2026-10-11: comments without protocol keyword are no protocol; 'StimThresh' = ST; a protocol of unknown type needs
% an end comment or regular pacing; a software restart ends a protocol without end comment, a connection lost for 1 s
% does not
f2 = fullfile(folder, 'pkw_rigA_0.mdd');
writeRecording(f2, T, fs, {100, 0, 'comment', 'Software new started'; 300, 0, 'comment', 'Start StimThresh'; ...
    600, 0, 'comment', 'not sure if stim protocol started'; ...
    1000, 0, 'comment', 'start post rest potentiation protocol'; 1150, 0, 'comment', 'start FFR protocol'; ...
    1200, 0, 'event', 'Connection lost'; 1201, 0, 'event', 'Connection re-established'; ...
    1250, 0, 'Event', 'LogFile opened: C:/x/pkw_rigA_0_log.log'; 1250, 0, 'programInfo', 'Version 2.0.1'; ...
    1800, 0, 'comment', 'start training programme'; 1830, 0, 'comment', 'end of training programme'; ...
    2100, 0, 'event', 'Connection lost'});
P2 = mda_protocols(f2);
ok = check(ok, 'keywords: no protocol without keyword, StimThresh = ST, unknown type', ...
    isequal(P2.type', {'ST', 'PRP', 'FFR', 'unknown'}) && isequal(P2.from', [300 1000 1150 1800]) && ...
    strcmp(P2.groupBy{4}, 'none') && strcmp(P2.name{4}, 'training programme'));
ok = check(ok, 'interruptions: software restart ends the FFR, a connection lost for 1 s does not', ...
    max(abs(P2.to' - [540 1150 1250 1830])) < 1e-9 && ...
    strcmp(P2.note{3}, 'no end comment: end estimated at 1250 s (software restarted)'));
% 2026-10-11: a protocol outside the recorded data is not analysed (note), the others are
P3 = [P; P(3,:)];
P3.number(5) = 2; P3.from(5) = 2500; P3.to(5) = 2600;
[~, ~, info] = MyoDishAnalysis(f, 1, [], [], 'protocol', P3, 'quiet', true);
ok = check(ok, 'protocol outside the recorded data: not analysed, the others are', ...
    any(strcmp(info.notes, 'protocol FFR 2: not analysed: outside the recorded data (2500 ... 2600 s, file length 2400.0 s)')) && ...
    isequal(info.rangeLabels(:)', {'ST 1', 'PRP 1', 'FFR 1', 'PD 1'}) && height(info.protocols) == 5 && ...
    contains(info.protocols.note{5}, 'not analysed: outside the recorded data'));
end


function [t, cur] = stimuli(T)
t = []; cur = [];
steps = [20 30 40 50 70 80];
for x = 0:2:998                                    %0.5 Hz, ST current steps
    t(end+1) = x; %#ok<AGROW>
    if x >= 300 && x < 540, cur(end+1) = steps(floor((x - 300) / 40) + 1); else, cur(end+1) = 60; end %#ok<AGROW>
end
for a = [1000 1050 1100]                           %PRP trains
    for i = 0:9, t(end+1) = a + 2 * i; cur(end+1) = 60; end %#ok<AGROW>
end
for x = 1150:1:1249, t(end+1) = x; cur(end+1) = 60; end %#ok<AGROW>
for x = 1250:0.5:1349.5, t(end+1) = x; cur(end+1) = 60; end %#ok<AGROW>
for x = 1350:2:T-2, t(end+1) = x; cur(end+1) = 60; end %#ok<AGROW>
end


function writeRecording(f, T, fs, rows)
n = T * fs;
x = zeros(9, n, 'int16');
x(1:8, :) = -383;
[t, cur] = stimuli(T);
for c = 1:2                                        %pulse of channel c one sample after the one of channel c-1
    idx = round(t * fs) + (c - 1) + 1;
    x(9, idx) = int16(bitor(uint16(cur), uint16(bitshift(c, 9))));
end
fid = fopen(f, 'w'); fwrite(fid, x, 'int16'); fclose(fid);
[~, name, ext] = fileparts(f); name = [name ext];
head = {0, 0, 'samplingRate Recording', '400'; 0, 0, 'Recording', ['started: ' name]; 0, 0, 'chargeDuration', '2000'};
if nargin >= 4
    rows = [head; rows; {T, 0, 'Recording', ['stopped: ' name]}];
else
    rows = [head; {300, 0, 'comment', 'start stimCurrent threshold protocol'; ...
        1000, 0, 'comment', 'start post rest potentiation protocol'; ...
        1150, 0, 'comment', 'start FFR protocol'; 1800, 0, 'comment', 'start pulse duration protocol'; ...
        1800, 0, 'chargeDuration', '1000'; 1830, 0, 'chargeDuration', '500'; 1860, 0, 'chargeDuration', '250'; ...
        1890, 0, 'chargeDuration', '2000'; T, 0, 'Recording', ['stopped: ' name]}];
end
fid = fopen(strrep(f, '.mdd', '_log.log'), 'w');
fprintf(fid, 'systemTime;dataLogTime;channel;code;value\n');
for i = 1:size(rows, 1)
    s = rows{i, 1};
    fprintf(fid, '2000 01 01 %02d:%02d:%02d:000;%d;%d;%s;%s\n', 10 + floor(s / 3600), floor(mod(s, 3600) / 60), ...
        mod(s, 60), s * 1000, rows{i, 2}, rows{i, 3}, rows{i, 4});
end
fclose(fid);
end


function ok = check(ok, name, pass)
fprintf('%-72s %s\n', name, passStr(pass));
ok = ok && pass;
end


function s = passStr(pass)
if pass, s = 'ok'; else, s = 'FAILED'; end
end
