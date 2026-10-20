function P = mda_protocols(src, regularMinutes)
%MDA_PROTOCOLS  Stimulation protocols in a MyoDish recording, found from the comments of the log file.
%
%   P = mda_protocols(mddFile)     or  P = mda_protocols(H)   (H from mda_readMdd)  or  P = mda_protocols(logFile)
%   P = mda_protocols(..., regularMinutes)    end estimation (below), default 5 min; 0 = only next protocol / end
%
% Protocols are marked by pairs of comments such as 'start FFR protocol' ... 'end FFR protocol', 'start of
% refractory period protocol' ... 'end of refractory period protocol' or 'FFR protocol started' ... 'FFR protocol
% ended'. A start is paired with the next end of the same name (otherwise of the same type). The end of a start
% without end comment is estimated (2026-10-10): the start of regular pacing after the protocol start (per
% stimulated channel the first run of stimuli that lasts > regularMinutes + one interval with the same interval
% +-max(5 ms, 2 %), current and pulse duration (log 'chargeDuration'); lower median over the channels; pulses < 50 ms
% after the previous one are ignored), otherwise the start of the next protocol (any type) or the end of the file;
% note 'no end comment: end estimated at ... s (start of regular pacing: 0.5 Hz, 50 mA, > 5 min)' (or '(start of the
% next protocol ...)', '(end of the file)'). Regular pacing needs the stimulus pulses (mddFile or H); with a log file
% only: next protocol or end of the file. Protocols
% within a protocol of the same type (e.g. 'PRP protocol started' within 'start post rest potentiation protocol')
% are not listed separately; a start comment repeated within 10 s counts once. A gap of > 10 min between the log
% entries within a protocol is noted ('gap of 23.5 h in the log': schedule stalled). Comments about the recording itself ('Started parallel recording ...') and about schedule
% files ('start scheduleFile_humanVentricle', 'end of schedule file ...') are ignored.
% Schedule files loaded by a schedule (log events 'Loaded schedule file <path>' ... 'Jumped back from loaded schedule
% file <path>') are protocols, too, if their file name contains a protocol keyword (e.g. PD_Test_12Steps.txt,
% ST_50-8mA_stepSize2mA.txt) and not 'schedule'; name = file name without extension. If such a protocol is also marked
% by comments, the longer of the two is listed.
%
% P  table, one row per protocol (in the order of the start): type, name, number (k-th protocol of this type),
%    from, to (s, time in the file), groupBy (default quantity for mda_groupBeats), startComment, endComment, note
%
% Types (keywords in the name, not case sensitive; FFR, RP, ST, PRP, PD also as separate words or parts of a
% CamelCase / underscore name such as 'PD_Test') and default grouping:
%   FFR          FFR, force-frequency, frequency          pacingFrequency
%   RP           refractory, RP, S1S2, S2                 S2interval
%   ST           threshold, thresh, stimCurrent, ST       stimCurrent
%   PRP          post rest, PRP, rest potentiation        pauseLength
%   PD           pulse duration, PD                       pulseDuration
%   rockerSpeed  rocker speed                             rockerSpeed
%   unknown      no type keyword, but protocol, Protokoll, programme, program or Test (comments only)    none
% A comment without any of these keywords is no protocol (e.g. 'Software new started', 'start Iso Wash In'). A
% protocol of type 'unknown' without end comment needs regular pacing within 2 h after its start (end estimate),
% otherwise it is dropped. A protocol without end comment ends at the latest when the software was restarted ('LogFile
% opened', programInfo 'Version', 'Recording started:') or the connection was lost (without 'Connection
% re-established' within 60 s) (2026-10-11).
%
% PROTOCOLRUN EVENTS (control software from 2026-10, release 2.2; 2026-10-18): if the log file has structured
% protocolRun events (mda_logEntries(..., 'events')), these protocols are taken from them: start paired with end or
% abort by run, from / to = their times in the file, type and name of the start (types of the software: FFR, RP, ST,
% PRP, PD, rockerSpeed, doseResponse, substance, stretch, other; groupBy none for the last four), startComment
% 'protocolRun start: <name> (<source> <schedule file> line <n>)', endComment 'protocolRun end|abort: <reason>', note
% 'aborted: <reason>', 'started before this recording (<clock time>)' (start written before the log was opened),
% 'started before this file' (end without start: from 0) or 'no end in the log: end of the file' / '...: software
% restarted'. A protocol whose start and end were both written before the log was opened ran between two recordings
% and is not listed. The automatic comments 'start <TYPE> protocol' / 'end <TYPE> protocol' next to these events are
% not read again (each paired with the next protocolRun line of its kind and type, 2026-10-20); comment protocols of
% the same type that overlap a protocolRun protocol are dropped; other comments are read as before (older recordings:
% unchanged). Waiting events (started while no recording ran, see mda_logEntries): from = where the file was when the
% recording began (2026-10-20).
% Names with 'dose response' (any spelling) or the word DRC: type doseResponse (tested first, as the control software;
% 2026-10-18); without end comment it is treated like type unknown.
%
% Python: myodish_analysis.protocols.find_protocols, protocol_runs.
%
% TS 2026-10-07 (schedule files 2026-10-07; protocolRun events 2026-10-18)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

if nargin < 2 || isempty(regularMinutes), regularMinutes = 5; end
H = [];
if isstruct(src)
    H = src; logFile = src.logFile; T = src.totalSeconds;
else
    src = char(src);
    if endsWith(lower(src), '.mdd')
        H = mda_readMdd(src); logFile = H.logFile; T = H.totalSeconds;
    else
        logFile = src; T = inf;
    end
end
E = mda_logEntries(logFile);
tAll = sort(E.t_file(isfinite(E.t_file)));       %all log entries (gaps within a protocol)
tStop = interruptions(E);                         %software restarted / connection lost: a protocol without end comment ends there
V = mda_logEntries(E, 'events');                  %protocolRun events of the control software (2026-10-18)
runs = protocolRuns(V, T, tStop);
auto = autoComments(E, V);                        %their automatic start / end comments: not read again
E = E((E.isComment | strcmpi(E.code, 'schedule')) & isfinite(E.t_file) & ~auto, :);
E = sortrows(E, 't_file');                        %stable

st = struct('type', {}, 'name', {}, 'key', {}, 'from', {}, 'to', {}, 'startComment', {}, 'endComment', {}, 'note', {});
open = zeros(0, 1);                               %indices of open (unpaired) starts
sched = {};                                       %names of the loaded schedule files (nested)
for k = 1:height(E)
    txt = strtrim(E.text{k});
    if E.isComment(k)
        [kind, name] = parseComment(txt);
        if isempty(kind), continue; end
    else
        [kind, name] = parseScheduleEvent(txt);
        if isempty(kind), continue; end
        if strcmp(kind, 'start')
            sched{end+1} = name; %#ok<AGROW>
        else                                      %'Jumped back from loaded schedule file.' (older logs): the last one
            j = find(strcmp(sched, name), 1, 'last');
            if isempty(name) || isempty(j), j = numel(sched); end
            if j == 0, continue; end
            name = sched{j}; sched(j) = [];
        end
        if strcmp(kind, 'start'), txt = ['Loaded schedule file ' name]; else, txt = ['Jumped back from loaded schedule file ' name]; end
    end
    if contains(lower(name), 'schedule'), continue; end           %the schedule file itself
    key = normName(name);
    typ = protocolType(name);
    if strcmp(typ, 'other')
        % schedule files without protocol keyword: no protocol. Comments (2026-10-11): only with a general protocol
        % keyword (type 'unknown'); others such as 'Software new started' or 'start Iso Wash In' are no protocol
        if ~E.isComment(k) || ~genericProtocol(name), continue; end
        typ = 'unknown';
    end
    if strcmp(kind, 'start')
        st(end+1) = struct('type', typ, 'name', name, 'key', key, 'from', E.t_file(k), 'to', nan, ...
            'startComment', txt, 'endComment', '', 'note', ''); %#ok<AGROW>
        open(end+1) = numel(st); %#ok<AGROW>
    else
        j = find(strcmp({st(open).key}, key), 1, 'last');
        if isempty(j), j = find(strcmp({st(open).type}, typ) & ~any(strcmp(typ, {'other', 'unknown'})), 1, 'last'); end
        if isempty(j), continue; end               %end without start: ignored
        st(open(j)).to = E.t_file(k);
        st(open(j)).endComment = txt;
        open(j) = [];
    end
end
% starts without end within a protocol of the same type (e.g. 'PRP protocol started' after 'start post rest
% potentiation protocol'): not listed separately
drop = false(1, numel(st));
for i = 1:numel(st)
    if isnan(st(i).to)
        drop(i) = any(arrayfun(@(x) strcmp(x.type, st(i).type) && ~isnan(x.to) && x.from <= st(i).from && ...
            st(i).from < x.to, st));
    end
end
st = st(~drop);
% a start followed by another start of the same type within 10 s is a repeated comment and dropped
drop = false(1, numel(st));
for i = 1:numel(st)
    if isnan(st(i).to)
        nxt = [st(i+1:end).from];
        nxt = nxt(strcmp({st(i+1:end).type}, st(i).type));
        drop(i) = ~isempty(nxt) && nxt(1) - st(i).from < 10;
    end
end
st = st(~drop);
% other starts without end: end estimated (2026-10-10) = start of regular pacing, otherwise the start of the next
% protocol (any type) or the end of the file
logE = [];
unknownMaxSeconds = 7200;                          %unknown type without end comment (2026-10-11)
dropU = false(1, numel(st));
for i = 1:numel(st)
    if isnan(st(i).to)
        %(a protocolRun protocol of the same type: no limit; it marks the same protocol, which is dropped below)
        cand = [st, runs(~strcmp({runs.type}, st(i).type))];
        later = find([cand.from] > st(i).from);
        if ~isempty(later)
            [tLimit, j] = min([cand(later).from]);
            why = sprintf('start of the next protocol ''%s''', cand(later(j)).name);
        else
            tLimit = T; why = 'end of the file';
        end
        k = find(tStop(:,1) > st(i).from & tStop(:,1) < tLimit, 1);
        if ~isempty(k)                            %2026-10-11
            tLimit = tStop(k,1);
            if tStop(k,2) == 1, why = 'software restarted'; else, why = 'connection lost'; end
        end
        tEnd = tLimit;
        r = nan;
        if ~isempty(H) && regularMinutes > 0
            if isempty(logE), logE = mda_logEntries(logFile); end
            [r, w] = regularPacingStart(H, logE, st(i).from, tLimit, 60 * regularMinutes);
            if ~isnan(r), tEnd = r; why = w; end
        end
        if any(strcmp(st(i).type, {'unknown', 'doseResponse'})) && (isnan(r) || tEnd - st(i).from > unknownMaxSeconds)
            dropU(i) = true;    %unknown type without end comment: a protocol only if regular pacing starts again
            continue;           %within 2 h (otherwise e.g. 'not sure if stim protocol started' without a change)
        end
        st(i).to = tEnd;
        st(i).note = sprintf('no end comment: end estimated at %g s (%s)', tEnd, why);
    end
end
st = st(~dropU);
% protocols within a protocol of the same type are not listed separately
keep = true(1, numel(st));
for i = 1:numel(st)
    for j = 1:numel(st)
        if i ~= j && keep(j) && strcmp(st(i).type, st(j).type) && st(i).from >= st(j).from && st(i).to <= st(j).to && ...
                (st(i).from > st(j).from || st(i).to < st(j).to || i > j)
            keep(i) = false;
        end
    end
end
st = st(keep);
if ~isempty(runs)    %protocolRun protocols (2026-10-18); comment protocols of the same type overlapping one: dropped
    keep = true(1, numel(st));
    for i = 1:numel(st)
        keep(i) = ~any(strcmp({runs.type}, st(i).type) & [runs.from] < st(i).to & st(i).from < [runs.to]);
    end
    st = [st(keep), runs];
    [~, o] = sort([st.from]); st = st(o);
end
% a gap of > 10 min between the log entries within a protocol (e.g. the schedule stalled and the remaining commands
% were sent later at once): note
for i = 1:numel(st)
    if ~isfinite(st(i).to), continue; end
    g = max(diff([st(i).from; tAll(tAll > st(i).from & tAll < st(i).to); st(i).to]));
    if g > 600
        if g >= 3600, gs = sprintf('%.1f h', floor(g / 360) / 10); else, gs = sprintf('%d min', floor(g / 60)); end
        if isempty(st(i).note), st(i).note = ['gap of ' gs ' in the log'];
        else, st(i).note = [st(i).note '; gap of ' gs ' in the log']; end
    end
end
n = numel(st);
number = zeros(n, 1); groupBy = cell(n, 1);
for i = 1:n
    number(i) = sum(strcmp({st(1:i).type}, st(i).type));
    groupBy{i} = defaultGroupBy(st(i).type);
end
P = table(reshape({st.type}, [], 1), reshape({st.name}, [], 1), number, reshape([st.from], [], 1), reshape([st.to], [], 1), ...
    groupBy, reshape({st.startComment}, [], 1), reshape({st.endComment}, [], 1), reshape({st.note}, [], 1), ...
    'VariableNames', {'type','name','number','from','to','groupBy','startComment','endComment','note'});
end


% =====================================================================================================
function [r, why] = regularPacingStart(H, E, t0, tLimit, minDur)
% start of regular pacing after t0 (end of a protocol without end comment, see the help): per stimulated channel the
% first run of stimuli that starts after t0 and before tLimit and lasts > minDur + one interval with the same
% interval, current and pulse duration; lower median over the channels with such a run. NaN if none. TS 2026-10-10
r = nan; why = '';
T = H.totalSeconds;
b = min(T, tLimit + minDur + 60);
if ~isfield(H, 'hasStimChannel') || ~H.hasStimChannel || b <= t0, return; end
opts = mda_options('spikeRemoval', false);   %stimuli only
tt = zeros(0, 1); ch = zeros(0, 1); cur = zeros(0, 1);
a = max(0, t0 - 120);                     %from before the start: pacing that continues into the protocol is no new run
while a < b
    e = min(b, a + 3600);
    S = mda_readMdd(H, a, e, opts);
    k = S.stim.time >= a & S.stim.time < e;   %chunk boundaries: no pulse twice
    if isfield(S.stim, 'isExtraPulse'), k = k & ~S.stim.isExtraPulse; end   %extra pulses: no pacing (2026-10-10)
    tt = [tt; S.stim.time(k)]; ch = [ch; S.stim.channel(k)]; cur = [cur; S.stim.current(k)]; %#ok<AGROW>
    a = e;
end
starts = zeros(0, 3);
for c = unique(ch)'
    k = find(ch == c);
    t = tt(k); I = cur(k);
    keep = [true; diff(t) >= 0.05];          %a pulse < 50 ms after the previous one: no pacing (status channel errors)
    t = t(keep); I = I(keep);
    chg = pulseDurationChanges(E, c);
    ep = zeros(size(t));                      %pulse duration epoch of every pulse
    for q = 1:numel(chg), ep = ep + (t >= chg(q)); end
    n = numel(t); i = 1;
    while i < n
        isi0 = t(i+1) - t(i);
        tol = max(0.005, 0.02 * isi0);
        j = i + 1;
        while j + 1 <= n && abs(t(j+1) - t(j) - isi0) <= tol && I(j+1) == I(i) && I(j) == I(i) && ...
                ep(j+1) == ep(i) && ep(j) == ep(i)
            j = j + 1;
        end
        if t(i) > t0 && t(i) < tLimit && I(j) == I(i) && ep(j) == ep(i) && t(j) - t(i) > minDur + isi0
            starts(end+1, :) = [t(i), isi0, I(i)]; %#ok<AGROW>
            break;
        end
        if t(i) >= tLimit, break; end
        i = j;
    end
end
if isempty(starts), return; end
starts = sortrows(starts);
m = starts(floor((size(starts, 1) + 1) / 2), :);   %lower median over the channels
r = m(1);
why = sprintf('start of regular pacing: %.3g Hz, %g mA, > %g min', 1 / m(2), m(3), minDur / 60);
end


function chg = pulseDurationChanges(E, c)
% times at which the pulse duration of channel c changes (log 'chargeDuration' of channel c or 0 with another value
% than the entry before)
chg = zeros(0, 1);
if ~istable(E) || height(E) == 0, return; end
k = find(strcmpi(E.code, 'chargeDuration') & (E.channel == c | E.channel == 0) & isfinite(E.t_file));
if numel(k) < 2, return; end
[~, o] = sort(E.t_file(k)); k = k(o);
v = str2double(E.text(k));
i = find(v(2:end) ~= v(1:end-1)) + 1;
chg = sort(E.t_file(k(i)));
end


function [kind, name] = parseComment(txt)
kind = ''; name = '';
if contains(lower(txt), 'recording'), return; end   %'Started parallel recording: ...'
tok = regexp(txt, '^(?:start(?:ing)?|begin(?:ning)?)\s+(?:of\s+)?(?:the\s+)?(.+?)\s*$', 'tokens', 'once', 'ignorecase');
if ~isempty(tok), kind = 'start'; name = tok{1}; return; end
tok = regexp(txt, '^(.+?)\s+(?:started|starts|begins)\s*$', 'tokens', 'once', 'ignorecase');
if ~isempty(tok), kind = 'start'; name = tok{1}; return; end
tok = regexp(txt, '^(?:end(?:ed)?|stop(?:ped)?|finish(?:ed)?)\s+(?:of\s+)?(?:the\s+)?(.+?)\s*$', 'tokens', 'once', 'ignorecase');
if ~isempty(tok), kind = 'end'; name = tok{1}; return; end
tok = regexp(txt, '^(.+?)\s+(?:ended|ends|end|stopped|finished|done)\s*$', 'tokens', 'once', 'ignorecase');
if ~isempty(tok), kind = 'end'; name = tok{1}; return; end
end


function [kind, name] = parseScheduleEvent(txt)
% 'Loaded schedule file C:\...\PD_Test_12Steps.txt' / 'Jumped back from loaded schedule file C:\...\PD_Test.txt.'
kind = ''; name = '';
tok = regexp(txt, '^Loaded schedule file\s+(.+?)\s*$', 'tokens', 'once', 'ignorecase');
if ~isempty(tok)
    kind = 'start';
else
    tok = regexp(txt, '^Jumped back from loaded schedule file\s*(.*?)\s*$', 'tokens', 'once', 'ignorecase');
    if isempty(tok), return; end
    kind = 'end';
end
p = regexprep(strrep(tok{1}, '\', '/'), '\.+$', '');
k = find(p == '/', 1, 'last');
if ~isempty(k), p = p(k+1:end); end
name = regexprep(p, '\.[A-Za-z0-9]{1,4}$', '');
end


function key = normName(name)
% lower case, without 'protocol' and non-alphanumeric characters ('PulseDurationProtocol' = 'pulse duration')
key = lower(name);
key = regexprep(key, 'protocol', '');
key = regexprep(key, '[^a-z0-9]', '');
end


function typ = protocolType(name)
key = normName(name);
tok = lower(regexp(char(name), '[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+', 'match'));   %words: 'PD_Test' -> pd, test
if contains(key, 'doseresponse') || ismember('drc', tok)   %first, as the control software (2026-10-18)
    typ = 'doseResponse';
elseif ~isempty(regexp(key, 'postrest|prp|restpotentiation', 'once'))
    typ = 'PRP';
elseif ~isempty(regexp(key, 'refractory|^rp|s1s2|^s2', 'once')) || ismember('rp', tok)
    typ = 'RP';
elseif ~isempty(regexp(key, 'thresh|tresh|stimcurrent|^st$|^st[^a-z]', 'once')) || ismember('st', tok)   %'StimThresh' (2026-10-11)
    typ = 'ST';
elseif ~isempty(regexp(key, 'pulseduration|^pd$|^pd[^a-z]', 'once')) || ismember('pd', tok)
    typ = 'PD';
elseif ~isempty(regexp(key, 'rockerspeed', 'once'))
    typ = 'rockerSpeed';
elseif ~isempty(regexp(key, 'ffr|forcefrequency|frequency', 'once')) || ismember('ffr', tok)
    typ = 'FFR';
else
    typ = 'other';
end
end


function X = interruptions(E)
%[file time, kind] of every interruption in the log entries (kind 1: software restarted = 'LogFile opened', programInfo
%'Version ...' or 'Recording started: ...'; 2: 'Connection lost' without 'Connection re-established' within 60 s),
%sorted (2026-10-11)
X = zeros(0, 2);
if ~istable(E) || height(E) == 0, return; end
txt = strtrim(cellstr(string(E.text)));
code = lower(cellstr(string(E.code)));
t = E.t_file;
restart = ~cellfun(@isempty, regexpi(txt, '^logfile opened', 'once')) | ...
    (strcmp(code, 'programinfo') & ~cellfun(@isempty, regexpi(txt, '^version', 'once'))) | ...
    (strcmp(code, 'recording') & ~cellfun(@isempty, regexpi(txt, '^started\s*:', 'once')));
lost = ~cellfun(@isempty, regexpi(txt, '^connection lost', 'once'));
back = t(~cellfun(@isempty, regexpi(txt, '^connection re-?established', 'once')));
for k = find(lost)'
    if any(back >= t(k) & back <= t(k) + 60), lost(k) = false; end
end
X = [t(restart), ones(nnz(restart), 1); t(lost), 2 * ones(nnz(lost), 1)];
X = X(isfinite(X(:,1)), :);
[~, o] = sort(X(:,1)); X = X(o, :);
end

function tf = genericProtocol(name)
%name without type keyword but with a general protocol keyword (protocol, Protokoll, programme, program, Test as a word
%or part of a CamelCase / underscore name): type 'unknown' (2026-10-11)
tok = lower(regexp(char(name), '[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+', 'match'));
tf = ~isempty(regexpi(char(name), 'protocol|protokoll|program', 'once')) || ismember('test', tok);
end

function g = defaultGroupBy(typ)
switch typ
    case 'FFR',         g = 'pacingFrequency';
    case 'RP',          g = 'S2interval';
    case 'ST',          g = 'stimCurrent';
    case 'PRP',         g = 'pauseLength';
    case 'PD',          g = 'pulseDuration';
    case 'rockerSpeed', g = 'rockerSpeed';
    otherwise,          g = 'none';
end
end


function st = protocolRuns(V, T, tStop)
% protocols from the protocolRun events of the control software (2026-10-18): start paired with end or abort by run;
% from / to = t_file of the events; type and name of the start; see the help. Same fields as the comment protocols.
st = struct('type', {}, 'name', {}, 'key', {}, 'from', {}, 'to', {}, 'startComment', {}, 'endComment', {}, 'note', {});
if ~istable(V) || height(V) == 0, return; end
R = V(strcmpi(V.code, 'protocolRun'), :);
if height(R) == 0, return; end
runOf = cellfun(@(d) fieldOr(d, 'run', ''), R.data, 'UniformOutput', false);
isEnd = ismember(R.event, {'end', 'abort'}) & ~cellfun(@isempty, runOf);
seen = {};
for k = find(strcmp(R.event, 'start'))'
    d = R.data{k};
    run = runOf{k};
    if isempty(run), run = R.actionId{k}; end
    if ismember(run, seen), continue; end
    seen{end+1} = run; %#ok<AGROW>
    e = find(isEnd & strcmp(runOf, run), 1);
    if R.waiting(k) && ~isempty(e) && R.waiting(e), continue; end   %ran between two recordings
    typ = softwareType(fieldOr(d, 'type', ''));
    name = strtrim(fieldOr(d, 'name', ''));
    if isempty(name), name = typ; end
    frm = R.t_file(k);
    note = {};
    if R.waiting(k)
        note{end+1} = sprintf('started before this recording (%s)', clockText(R.clockTime(k))); %#ok<AGROW>
    end
    src = fieldOr(d, 'source', '');
    sf = fieldOr(d, 'scheduleFile', '');
    if strcmp(src, 'schedule') && ~isempty(sf)
        src = [src ' ' sf]; %#ok<AGROW>
        ln = fieldOr(d, 'line', []);
        if isnumeric(ln) && isscalar(ln), src = sprintf('%s line %d', src, ln); end
    end
    if isempty(e)
        tEnd = T; why = 'end of the file';
        q = find(tStop(:,1) > frm & tStop(:,2) == 1 & tStop(:,1) < T, 1);
        if ~isempty(q), tEnd = tStop(q,1); why = 'software restarted'; end
        note{end+1} = ['no end in the log: ' why]; %#ok<AGROW>
        endc = '';
    else
        tEnd = R.t_file(e);
        reason = fieldOr(R.data{e}, 'reason', '');
        endc = sprintf('protocolRun %s: %s', R.event{e}, reason);
        if strcmp(R.event{e}, 'abort'), note{end+1} = ['aborted: ' reason]; end %#ok<AGROW>
    end
    if isempty(src), sc = ['protocolRun start: ' name]; else, sc = sprintf('protocolRun start: %s (%s)', name, src); end
    st(end+1) = struct('type', typ, 'name', name, 'key', normName(name), 'from', frm, 'to', min(tEnd, T), ...
        'startComment', sc, 'endComment', endc, 'note', strjoin(note, '; ')); %#ok<AGROW>
end
for e = find(isEnd)'                            %ends without start in this log (first end of a run)
    run = runOf{e};
    if ismember(run, seen) || R.waiting(e) || find(isEnd & strcmp(runOf, run), 1) ~= e, continue; end
    seen{end+1} = run; %#ok<AGROW>
    typ = softwareType(fieldOr(R.data{e}, 'type', ''));
    reason = fieldOr(R.data{e}, 'reason', '');
    note = 'started before this file';
    if strcmp(R.event{e}, 'abort'), note = [note '; aborted: ' reason]; end %#ok<AGROW>
    st(end+1) = struct('type', typ, 'name', typ, 'key', normName(typ), 'from', 0, 'to', R.t_file(e), ...
        'startComment', '', 'endComment', sprintf('protocolRun %s: %s', R.event{e}, reason), 'note', note); %#ok<AGROW>
end
if ~isempty(st), [~, o] = sort([st.from]); st = st(o); end
end


function skip = autoComments(E, V)
% rows of E with the automatic comments 'start <TYPE> protocol' / 'end <TYPE> protocol' that the control software
% writes right before each protocolRun start / end / abort: each comment is paired with the next protocolRun line of
% the same kind (start / end or abort) and type after it in the log, unless another such comment comes first
% (2026-10-20; before: same type within 1 s, which a delay between the two writes can exceed)
skip = false(height(E), 1);
if ~istable(V) || height(V) == 0, return; end
R = V(strcmpi(V.code, 'protocolRun'), :);
if height(R) == 0, return; end
typ = lower(cellfun(@(d) fieldOr(d, 'type', ''), R.data, 'UniformOutput', false));
isStart = strcmp(R.event, 'start');
isEnd = ismember(R.event, {'end', 'abort'});
used = false(height(R), 1);
ci = zeros(0, 1); ck = zeros(0, 1); ct = cell(0, 1);   %the automatic comments: row, kind (1 start, 2 end), type
for i = find(E.isComment)'
    tok = regexp(strtrim(E.text{i}), '^(start|end)\s+(\S+)\s+protocol$', 'tokens', 'once', 'ignorecase');
    if isempty(tok), continue; end
    ci(end+1, 1) = i; ck(end+1, 1) = 1 + strcmpi(tok{1}, 'end'); ct{end+1, 1} = lower(tok{2}); %#ok<AGROW>
end
for j = 1:numel(ci)
    if ck(j) == 1, want = isStart; else, want = isEnd; end
    c = find(~used & want & R.row > ci(j) & strcmp(typ, ct{j}), 1);
    if isempty(c), continue; end
    if any(ci > ci(j) & ci < R.row(c) & ck == ck(j) & strcmp(ct, ct{j})), continue; end   %that one is its comment
    used(c) = true;
    skip(ci(j)) = true;
end
end


function typ = softwareType(t)
% type of a protocolRun event as protocol type (unknown types: other)
switch lower(strtrim(char(t)))
    case 'ffr',          typ = 'FFR';
    case 'rp',           typ = 'RP';
    case 'st',           typ = 'ST';
    case 'prp',          typ = 'PRP';
    case 'pd',           typ = 'PD';
    case 'rockerspeed',  typ = 'rockerSpeed';
    case 'doseresponse', typ = 'doseResponse';
    case 'substance',    typ = 'substance';
    case 'stretch',      typ = 'stretch';
    otherwise,           typ = 'other';
end
end


function v = fieldOr(d, f, default)
% field f of a decoded event (default if absent or null)
v = default;
if isstruct(d) && isfield(d, f) && ~isempty(d.(f))
    v = d.(f);
    if isstring(v), v = char(v); end
end
end


function s = clockText(t)
if isnat(t), s = '?'; else, s = char(datetime(t, 'Format', 'yyyy-MM-dd HH:mm:ss')); end
end
