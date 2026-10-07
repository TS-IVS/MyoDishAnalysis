function P = mda_protocols(src)
%MDA_PROTOCOLS  Stimulation protocols in a MyoDish recording, found from the comments of the log file.
%
%   P = mda_protocols(mddFile)     or  P = mda_protocols(H)   (H from mda_readMdd)  or  P = mda_protocols(logFile)
%
% Protocols are marked by pairs of comments such as 'start FFR protocol' ... 'end FFR protocol', 'start of
% refractory period protocol' ... 'end of refractory period protocol' or 'FFR protocol started' ... 'FFR protocol
% ended'. A start is paired with the next end of the same name (otherwise of the same type). A start without an
% end lasts until the next protocol of the same type or the end of the file (note 'no end comment'). Protocols
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
%   ST           threshold, stimCurrent, ST               stimCurrent
%   PRP          post rest, PRP, rest potentiation        pauseLength
%   PD           pulse duration, PD                       pulseDuration
%   rockerSpeed  rocker speed                             rockerSpeed
%   other        all other names                          none
%
% TS 2026-10-07 (schedule files 2026-10-07)

if isstruct(src)
    logFile = src.logFile; T = src.totalSeconds;
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
E = E((E.isComment | strcmpi(E.code, 'schedule')) & isfinite(E.t_file), :);
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
    if ~E.isComment(k) && strcmp(typ, 'other'), continue; end   %schedule files without protocol keyword
    if strcmp(kind, 'start')
        st(end+1) = struct('type', typ, 'name', name, 'key', key, 'from', E.t_file(k), 'to', nan, ...
            'startComment', txt, 'endComment', '', 'note', ''); %#ok<AGROW>
        open(end+1) = numel(st); %#ok<AGROW>
    else
        j = find(strcmp({st(open).key}, key), 1, 'last');
        if isempty(j), j = find(strcmp({st(open).type}, typ) & ~strcmp(typ, 'other'), 1, 'last'); end
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
% other starts without end: until the next start of the same type or the end of the file; a start followed by
% another start of the same type within 10 s is a repeated comment and dropped
drop = false(1, numel(st));
for i = 1:numel(st)
    if isnan(st(i).to)
        nxt = [st(i+1:end).from];
        nxt = nxt(strcmp({st(i+1:end).type}, st(i).type));
        if ~isempty(nxt), st(i).to = nxt(1); else, st(i).to = T; end
        st(i).note = 'no end comment';
        drop(i) = ~isempty(nxt) && nxt(1) - st(i).from < 10;
    end
end
st = st(~drop);
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
if ~isempty(regexp(key, 'postrest|prp|restpotentiation', 'once'))
    typ = 'PRP';
elseif ~isempty(regexp(key, 'refractory|^rp|s1s2|^s2', 'once')) || ismember('rp', tok)
    typ = 'RP';
elseif ~isempty(regexp(key, 'threshold|stimcurrent|^st$|^st[^a-z]', 'once')) || ismember('st', tok)
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
