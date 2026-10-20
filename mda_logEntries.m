function E = mda_logEntries(logFile, mode)
%MDA_LOGENTRIES  All entries of a MyoDish log file (comments, events, settings) as a table, in log order.
%
%   E = mda_logEntries(logFile)          logFile = <name>_log.log next to the .mdd file
%   V = mda_logEntries(logFile, 'events')   or  V = mda_logEntries(E, 'events')   structured events (below)
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
% STRUCTURED EVENTS (2026-10-18): lines of the control software (builds from 2026-10, release 2.2) whose value is one
% JSON object, code system, slice, protocolRun, scheduleRun, doc, chamber, rigor or backup (the old text lines stay as
% they are):
%   V   table, one row per structured line, in log order: row (row of E), clockTime, t_file, t_logged, channel, code,
%       event, actionId, by ('' if null), waiting, data (struct of all fields of the JSON object, jsondecode: read
%       fields by name, absent fields are absent, null = [])
%   t_logged: the dataLogTime of the line (s). t_file: the same, except for a waiting line.
%   waiting (2026-10-20): the event happened while no main recording ran; the control software keeps such lines in
%   memory and writes them into the next main log right before its 'LogFile created/opened'. Their dataLogTime is the
%   frozen counter of the last main recording of that program run (another file, or 0), not a time in this file, so
%   their t_file is the dataLogTime of that 'LogFile created/opened' (where this file was when the recording began).
%   Rule: waiting are the lines after the last 'LogFile closed' of this log (or after the start of the log, or from a
%   line 'MyodishControlSoftware opened' = a new run of the program, e.g. after a crash) up to the next 'LogFile
%   created/opened' of this log; LogFile2 (second recording) and LogFile3 (rocker stop recording) count as well, and
%   only lines about this log (the file name after the colon = the name in its first 'LogFile created/opened' line;
%   a main log also holds lines about the other logs). Logs of a second or rocker stop recording have no waiting
%   lines. Known limit: when the software lost the 'LogFile2/3 closed' line of the previous session (it does when all
%   files are closed at once), the waiting lines before the next opening are not recognized.
%   A line is structured if its code is one of these and its value starts with '{' (old lines never do; comments are
%   checked by the code). Lines that cannot be read (e.g. cut off by a crash) are counted in
%   V.Properties.UserData.nUnreadable (rows of E: .unreadable) and left out; unknown events and fields are kept.
%
% Python: myodish_analysis.log_entries.log_entries, log_events.
%
% TS 2026-10-05 (12-hour time stamps 2026-10-08; structured events 2026-10-18; waiting lines, codes chamber, rigor and
% backup 2026-10-20)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

if nargin >= 2 && strcmpi(mode, 'events')
    if istable(logFile), E = structuredEvents(logFile); else, E = structuredEvents(mda_logEntries(logFile)); end
    return;
end
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


function V = structuredEvents(E)
% structured events of the log entries E (see the help)
V = table(zeros(0,1), NaT(0,1), zeros(0,1), zeros(0,1), zeros(0,1), cell(0,1), cell(0,1), cell(0,1), cell(0,1), ...
    false(0,1), cell(0,1), 'VariableNames', ...
    {'row','clockTime','t_file','t_logged','channel','code','event','actionId','by','waiting','data'});
V.Properties.UserData = struct('nUnreadable', 0, 'unreadable', zeros(0,1));
if ~istable(E) || height(E) == 0, return; end
code = strtrim(cellstr(string(E.code)));
txt = strtrim(cellstr(string(E.text)));
low = lower(code);
isS = ismember(low, {'system', 'slice', 'protocolrun', 'schedulerun', 'doc', 'chamber', 'rigor', 'backup'}) & ...
    startsWith(txt, '{');
[wait, tOpen] = waitingLines(low, txt, E.t_file);
idx = find(isS);
bad = zeros(0, 1);
R = cell(numel(idx), 11);
n = 0;
for k = idx(:)'
    try
        d = jsondecode(txt{k});
    catch
        d = [];
    end
    if ~isstruct(d) || ~isscalar(d), bad(end+1, 1) = k; continue; end %#ok<AGROW>
    t = E.t_file(k);
    if wait(k), t = tOpen(k); end
    n = n + 1;
    R(n, :) = {k, E.clockTime(k), t, E.t_file(k), E.channel(k), code{k}, fieldText(d, 'event'), ...
        fieldText(d, 'actionId'), fieldText(d, 'by'), wait(k), d};
end
R = R(1:n, :);
if n > 0
    V = table(vertcat(R{:, 1}), vertcat(R{:, 2}), vertcat(R{:, 3}), vertcat(R{:, 4}), vertcat(R{:, 5}), R(:, 6), ...
        R(:, 7), R(:, 8), R(:, 9), vertcat(R{:, 10}), R(:, 11), 'VariableNames', ...
        {'row','clockTime','t_file','t_logged','channel','code','event','actionId','by','waiting','data'});
end
V.Properties.UserData = struct('nUnreadable', numel(bad), 'unreadable', bad);
end


function [w, tNext] = waitingLines(low, txt, t)
% waiting lines of a log (2026-10-20, see the help): w true for a waiting line, tNext = dataLogTime (s) of the
% 'LogFile created/opened' of this log that follows it
n = numel(low);
w = false(n, 1);
tNext = nan(n, 1);
isEv = strcmp(low, 'event');
tok = cell(n, 1);
tok(isEv) = regexpi(txt(isEv), '^logfile[23]?\s+(opened|created|closed)\s*:\s*(.*)$', 'tokens', 'once');
kind = repmat({''}, n, 1);
name = repmat({''}, n, 1);
for i = find(~cellfun(@isempty, tok))'
    kind{i} = lower(tok{i}{1});
    p = regexp(strtrim(tok{i}{2}), '[\\/]', 'split');
    name{i} = lower(strtrim(p{end}));
end
first = find(ismember(kind, {'opened', 'created'}), 1);
if isempty(first), return; end
own = strcmp(name, name{first});
isOpen = own & ismember(kind, {'opened', 'created'});
isClose = own & strcmp(kind, 'closed');
isRun = isEv & ~cellfun(@isempty, regexpi(txt, '^myodishcontrolsoftware opened', 'once'));
in = false;
for i = 1:n
    if isOpen(i)
        in = true;
    elseif isClose(i)
        in = false;                               %the closing line still belongs to its session
    elseif isRun(i)
        in = false; w(i) = true;                  %a new run of the program (e.g. after a crash)
    else
        w(i) = ~in;
    end
end
nxt = nan;                                        %only lines followed by an opening of this log are waiting
for i = n:-1:1
    if isOpen(i), nxt = t(i); end
    if w(i)
        if isnan(nxt), w(i) = false; else, tNext(i) = nxt; end
    end
end
end


function s = fieldText(d, f)
% text of field f of a decoded event ('' if absent or null)
s = '';
if isfield(d, f) && (ischar(d.(f)) || isstring(d.(f))), s = char(d.(f)); end
end
