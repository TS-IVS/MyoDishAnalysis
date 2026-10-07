function E = mda_logEntries(logFile)
%MDA_LOGENTRIES  All entries of a MyoDish log file (comments, events, settings) as a table, in log order.
%
%   E = mda_logEntries(logFile)          logFile = <name>_log.log next to the .mdd file
%
%   E.clockTime   datetime: system time of the entry (real-world date and time)
%   E.t_file      s: dataLogTime of the entry = time in the .mdd file (as used by all MyoDish analysis scripts)
%   E.channel     channel number of the entry (0 = not channel-specific)
%   E.code        e.g. 'comment', 'Event', 'rockerSpeed', 'Calibration'
%   E.text        value / comment text
%   E.isComment   true for comments (code 'comment')
%
% Lines (UTF-16 or UTF-8): systemTime;dataLogTime_ms;channel;code;value, e.g.
%   2022 03 07 09:44:35:717;1025;0;comment;start rockerSpeedTest
%
% TS 2026-10-05

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

% system time 'yyyy mm dd HH:MM:SS:fff'
clk = NaT(n, 1);
num = regexp(strtrim(tok(:,1)), '^(\d+) (\d+) (\d+) (\d+):(\d+):(\d+):?(\d*)', 'tokens', 'once');
ok = ~cellfun(@isempty, num);
if any(ok)
    N = str2double(vertcat(num{ok}));
    ms = N(:,7); ms(isnan(ms)) = 0;
    clk(ok) = datetime(N(:,1), N(:,2), N(:,3), N(:,4), N(:,5), N(:,6) + ms / 1000);
end
clk.Format = 'yyyy-MM-dd HH:mm:ss';

ch = str2double(tok(:,3)); ch(isnan(ch)) = 0;
code = strtrim(tok(:,4));
E = table(clk, t, ch, code, strtrim(tok(:,5)), strcmpi(code, 'comment'), ...
    'VariableNames', {'clockTime','t_file','channel','code','text','isComment'});
end
