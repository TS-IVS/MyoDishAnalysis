function E = mda_logEntries(logFile)
%MDA_LOGENTRIES  All entries of a MyoDish log file (comments, events, settings) as a table, in log order.
%
%   E = mda_logEntries(logFile)          logFile = <name>_log.log next to the .mdd file
%
%   E.clockTime   datetime: system time of the entry (real-world date and time; 12-hour time stamps of MyoDish
%                 software 2.0.7717-2.0.7769 corrected, see mda_clockTime)
%   E.t_file      s: dataLogTime of the entry = time in the .mdd file (as used by all MyoDish analysis scripts)
%   E.channel     channel number of the entry (0 = not channel-specific)
%   E.code        e.g. 'comment', 'Event', 'rockerSpeed', 'Calibration'
%   E.text        value / comment text
%   E.isComment   true for comments (code 'comment')
%   E.Properties.UserData   info of mda_clockTime (format '24h' / '12h', nCorrected, ambiguous, source, note)
%
% Lines (UTF-16 or UTF-8): systemTime;dataLogTime_ms;channel;code;value, e.g.
%   2000 01 01 09:44:35:717;1025;0;comment;start rockerSpeedTest
%
% TS 2026-10-05 (12-hour time stamps 2026-10-08)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

E = table(NaT(0,1), zeros(0,1), zeros(0,1), cell(0,1), cell(0,1), false(0,1), ...
    'VariableNames', {'clockTime','t_file','channel','code','text','isComment'});
if isempty(logFile) || ~exist(logFile, 'file'), return; end
fid = fopen(logFile, 'r');
if fid < 0, return; end
b = fread(fid, inf, 'uint8=>uint8')';
fclose(fid);
if numel(b) >= 4 && ((b(1) == 255 && b(2) == 254) || (b(2) == 0 && b(4) == 0))   %UTF-16 little endian
    if b(1) == 255, b = b(3:end); end
    b = b(1:2*floor(numel(b)/2));
    txt = char(double(b(1:2:end)) + 256 * double(b(2:2:end)));
else
    txt = native2unicode(b, 'UTF-8');
end
lines = regexp(txt, '\r?\n', 'split')';
tok = regexp(lines, '^([^;]*);([^;]*);([^;]*);([^;]*);(.*)$', 'tokens', 'once');
tok = tok(~cellfun(@isempty, tok));
if isempty(tok), return; end
tok = vertcat(tok{:});                                    %n x 5
t = str2double(tok(:,2)) / 1000;
tok = tok(~isnan(t), :); t = t(~isnan(t));               %header line, broken lines
n = numel(t);
if n == 0, return; end

% system time 'yyyy mm dd HH:MM:SS:fff'; 12-hour time stamps (software 2.0.7717-2.0.7769) corrected, see
% mda_clockTime (2026-10-08)
N = nan(n, 7);
num = regexp(strtrim(tok(:,1)), '^(\d+) (\d+) (\d+) (\d+):(\d+):(\d+):?(\d*)', 'tokens', 'once');
ok = ~cellfun(@isempty, num);
if any(ok)
    N(ok,:) = str2double(vertcat(num{ok}));
end
ch = str2double(tok(:,3)); ch(isnan(ch)) = 0;
code = strtrim(tok(:,4));
txt = strtrim(tok(:,5));
ver = txt((strcmpi(code, 'programInfo') & contains(txt, 'Version', 'IgnoreCase', true)) | strcmpi(code, 'programVersion'));
fileTime = [];
mdd = regexprep(logFile, '_log\.log$', '.mdd', 'ignorecase');
if ~strcmp(mdd, logFile)
    d = dir(mdd);
    if numel(d) == 1, fileTime = d.datenum; end
end
[clk, info] = mda_clockTime(N, t, ver, fileTime, txt);

E = table(clk, t, ch, code, txt, strcmpi(code, 'comment'), ...
    'VariableNames', {'clockTime','t_file','channel','code','text','isComment'});
E.Properties.UserData = info;   %clock time: format ('24h' / '12h'), nCorrected, ambiguous, source, note
end
