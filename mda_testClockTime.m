function ok = mda_testClockTime()
%MDA_TESTCLOCKTIME  Test of the clock time of log entries (mda_clockTime): 12-hour time stamps of MyoDish software
%2.0.7717-2.0.7769 corrected, 24-hour logs unchanged.
%
%   ok = mda_testClockTime()   prints the single checks, returns true if all pass
%
% Synthetic logs (true clock times, dataLogTime, written with 'hh' or 'HH'), and one log file + .mdd file through
% mda_logEntries and mda_readMdd. Pendant of py/tests/test_clock_time.py (same cases).
%
% TS 2026-10-08

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

ok = true;
d0 = datetime(2021, 3, 1);
at = @(hrs) d0 + seconds(round(hrs * 3600));       %clock times in whole seconds
V12 = 'Version 2.0.7769.26061'; V24 = 'Version 2.0.9756.15922';

% 1: 24-hour log across noon and midnight: unchanged
T = at([6 6.5 11.9 12.2 17.1 23.5 24.2 29.9])';
[clk, I] = run(T, T, false, V24);
ok = check(ok, '24-hour log unchanged', isequal(clk, T) && strcmp(I.format, '24h') && I.nCorrected == 0);

% 2: 12-hour log (affected version), 06:00 to 05:59 next day: 17:04 written as 05:04, 00:30 as 12:30, 12:15 as 12:15
T = at([6 7 12.25 17 + 4/60 23.9 24.5 29.98])';
[clk, I] = run(T, T, true, V12);
ok = check(ok, '12-hour log corrected (version 2.0.7769)', isequal(clk, T) && strcmp(I.format, '12h') && ...
    I.nCorrected == 3 && ~I.ambiguous && strcmp(I.source, 'log'));

% 3: the same without version entry: correction from the data alone
[clk, I] = run(T, T, true, '');
ok = check(ok, '12-hour log corrected (no version entry)', isequal(clk, T) && strcmp(I.format, '12h') && I.nCorrected == 3);

% 4: 12-hour log, all entries in one afternoon: ambiguous without further information ...
T = at([13 13.5 14 16 17])';
[clk, I] = run(T, T, true, V12);
ok = check(ok, 'afternoon only: ambiguous, as written', isequal(clk, T - hours(12)) && I.ambiguous && I.nCorrected == 0 && ...
    contains(I.note, 'AM/PM of the recording unknown'));
% ... decided by 'Started parallel recording: 01.Mar.2021 13:00:00' in the text of an entry
txt = repmat({'x'}, numel(T), 1); txt{1} = 'Started parallel recording: 01.Mrz.2021 13:00:00';
[clk, I] = run(T, T, true, V12, [], txt);
ok = check(ok, 'afternoon only: AM/PM from the text of an entry', isequal(clk, T) && ~I.ambiguous && I.nCorrected == 5);
% ... or by the time of the .mdd file (end of the recording, within 15 min)
[clk, I] = run(T, T, true, V12, datenum(T(end) + minutes(2)));
ok = check(ok, 'afternoon only: AM/PM from the file time', isequal(clk, T) && ~I.ambiguous && strcmp(I.source, 'file time'));
[clk, I] = run(T, T, true, V12, datenum(T(end) - hours(12) + minutes(1)));
ok = check(ok, 'morning (file time agrees with the times as written)', isequal(clk, T - hours(12)) && ~I.ambiguous && I.nCorrected == 0);

% 5: 24-hour log with entries carrying the stale dataLogTime of a recording that started 12 h earlier: unchanged
Told = at(10 + (0:4)' / 3600);                     %10:00, dataLogTime of a recording started at 06:00 (4 h)
Tnew = at([18 18.5 19 22 25 29])';           %new recording from 18:00
T = [Told; Tnew];
tt = [repmat(4 * 3600, numel(Told), 1); seconds(Tnew - Tnew(1))];
[clk, I] = run(T, tt, false, V24, [], {}, true);
ok = check(ok, '24-hour log with stale dataLogTime unchanged', isequal(clk, T) && strcmp(I.format, '24h'));

% 6: 12-hour log with entries before the start (stale dataLogTime) and with frozen dataLogTime after the stop
T = at([13.9 13.95 14 15 18 22 26 30 30.5 31 36])';
tt = seconds(T - T(3)); tt(1:2) = 5000; tt(end-2:end) = tt(end-3);
[clk, I] = run(T, tt, true, V12, [], {}, true);
ok = check(ok, '12-hour log: stale and frozen dataLogTime in chronological order', isequal(clk, T) && strcmp(I.format, '12h'));

% 7: log of two versions: 24-hour entries of 2.0.7712, then 12-hour entries of 2.0.7769 after a restart
T1 = at([15 15.1 15.2])'; T2 = at([15.5 16 20 26])';
N = [nums(T1, false); nums(T2, true)];
tt = [seconds(T1 - T1(1)); seconds(T2 - T2(1))];
[clk, I] = mda_clockTime(N, tt, {'Version 2.0.7712.19726', V12});
ok = check(ok, 'log of two software versions', isequal(clk, [T1; T2]) && strcmp(I.format, '12h'));

% 8: log file + .mdd file: mda_logEntries and mda_readMdd (recording start 14:20, written 02:20)
folder = tempname; mkdir(folder); cleanup = onCleanup(@() rmdir(folder, 's')); %#ok<NASGU>
mdd = fullfile(folder, 'clock_test_0.mdd');
fid = fopen(mdd, 'w'); fwrite(fid, zeros(9, 400 * 60, 'int16'), 'int16'); fclose(fid);
T = at([14 + 1/3, 14 + 1/3, 15, 20, 25])';
tt = [0; seconds(T(2:end) - T(1))];
txt = {'Recording;started: clock_test_0.mdd', 'samplingRate Recording;400', 'comment;Mx 1600', 'comment;observation', ...
    'Recording;stopped: clock_test_0.mdd'};
lf = fullfile(folder, 'clock_test_0_log.log');
fid = fopen(lf, 'w');
Nw = nums(T, true);
fprintf(fid, 'systemTime;dataLogTime;channel;code;value\n%04d %02d %02d %02d:%02d:%02d:%03d;0;0;programInfo;%s\n', Nw(1,:), V12);
for k = 1:numel(T)
    c = strsplit(txt{k}, ';');
    fprintf(fid, '%04d %02d %02d %02d:%02d:%02d:%03d;%d;0;%s;%s\n', Nw(k,:), round(tt(k) * 1000), c{1}, c{2});
end
fclose(fid);
E = mda_logEntries(lf);
H = mda_readMdd(mdd);
ok = check(ok, 'mda_logEntries: corrected clock times', isequal(E.clockTime, [T(1); T]) && E.Properties.UserData.nCorrected == 5);
ok = check(ok, 'mda_readMdd: recording start corrected + note', abs(H.recordingStart - datenum(T(1))) < 1e-8 && ...
    any(contains(H.notes, '12-hour time stamps')));
end


function [clk, I] = run(T, tt, fmt12, ver, fileTime, txt, ttGiven)
% clock times T written with a 12- or 24-hour clock; dataLogTime tt (s) = T - T(1), or given (ttGiven)
if nargin < 5, fileTime = []; end
if nargin < 6, txt = {}; end
if nargin < 7 || ~ttGiven
    if isdatetime(tt), tt = seconds(tt - tt(1)); end
end
[clk, I] = mda_clockTime(nums(T, fmt12), tt, ver, fileTime, txt);
clk.Format = T.Format;
end


function N = nums(T, fmt12)
% numbers of the time stamps as the software writes them ('hh': hours 1-12, 'HH': 0-23)
[y, mo, d] = ymd(T); [h, mi, s] = hms(T);
ms = round(1000 * (s - floor(s))); s = floor(s);
if fmt12, h = mod(h - 1, 12) + 1; end
N = [y mo d h mi s ms];
end


function ok = check(ok, name, pass)
fprintf('%-62s %s\n', name, passStr(pass));
ok = ok && pass;
end


function s = passStr(pass)
if pass, s = 'ok'; else, s = 'FAILED'; end
end
