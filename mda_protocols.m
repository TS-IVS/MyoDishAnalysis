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
% are not listed separately. Comments about the recording itself ('Started parallel recording ...') are ignored.
%
% P  table, one row per protocol (in the order of the start): type, name, number (k-th protocol of this type),
%    from, to (s, time in the file), groupBy (default quantity for mda_groupBeats), startComment, endComment, note
%
% Types (keywords in the name, not case sensitive) and default grouping:
%   FFR          FFR, force-frequency, frequency          pacingFrequency
%   RP           refractory, RP, S1S2, S2                 S2interval
%   ST           threshold, stimCurrent, ST               stimCurrent
%   PRP          post rest, PRP, rest potentiation        pauseLength
%   PD           pulse duration, PD                       pulseDuration
%   rockerSpeed  rocker speed                             rockerSpeed
%   other        all other names                          none
%
% TS 2026-10-07

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
E = E(E.isComment & isfinite(E.t_file), :);
E = sortrows(E, 't_file');                        %stable

st = struct('type', {}, 'name', {}, 'key', {}, 'from', {}, 'to', {}, 'startComment', {}, 'endComment', {}, 'note', {});
open = zeros(0, 1);                               %indices of open (unpaired) starts
for k = 1:height(E)
    txt = strtrim(E.text{k});
    [kind, name] = parseComment(txt);
    if isempty(kind), continue; end
    key = normName(name);
    typ = protocolType(key);
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
% other starts without end: until the next start of the same type or the end of the file
for i = 1:numel(st)
    if isnan(st(i).to)
        nxt = [st(i+1:end).from];
        nxt = nxt(strcmp({st(i+1:end).type}, st(i).type));
        if ~isempty(nxt), st(i).to = nxt(1); else, st(i).to = T; end
        st(i).note = 'no end comment';
    end
end
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


function key = normName(name)
% lower case, without 'protocol' and non-alphanumeric characters ('PulseDurationProtocol' = 'pulse duration')
key = lower(name);
key = regexprep(key, 'protocol', '');
key = regexprep(key, '[^a-z0-9]', '');
end


function typ = protocolType(key)
if ~isempty(regexp(key, 'postrest|prp|restpotentiation', 'once'))
    typ = 'PRP';
elseif ~isempty(regexp(key, 'refractory|^rp|s1s2|^s2', 'once'))
    typ = 'RP';
elseif ~isempty(regexp(key, 'threshold|stimcurrent|^st$|^st[^a-z]', 'once'))
    typ = 'ST';
elseif ~isempty(regexp(key, 'pulseduration|^pd$|^pd[^a-z]', 'once'))
    typ = 'PD';
elseif ~isempty(regexp(key, 'rockerspeed', 'once'))
    typ = 'rockerSpeed';
elseif ~isempty(regexp(key, 'ffr|forcefrequency|frequency', 'once'))
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
