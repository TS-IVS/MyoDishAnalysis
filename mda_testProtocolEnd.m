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
% Pendant of py/tests/test_protocol_end.py (same recording and checks).
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


function writeRecording(f, T, fs)
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
rows = {0, 0, 'samplingRate Recording', '400'; 0, 0, 'Recording', ['started: ' name]; ...
    0, 0, 'chargeDuration', '2000'; 300, 0, 'comment', 'start stimCurrent threshold protocol'; ...
    1000, 0, 'comment', 'start post rest potentiation protocol'; ...
    1150, 0, 'comment', 'start FFR protocol'; 1800, 0, 'comment', 'start pulse duration protocol'; ...
    1800, 0, 'chargeDuration', '1000'; 1830, 0, 'chargeDuration', '500'; 1860, 0, 'chargeDuration', '250'; ...
    1890, 0, 'chargeDuration', '2000'; T, 0, 'Recording', ['stopped: ' name]};
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
