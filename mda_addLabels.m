function T = mda_addLabels(T, L, when)
%MDA_ADDLABELS  Add the per-channel labels as columns (after 'channel') to a contraction or summary table.
%
%   T = mda_addLabels(T, L)          L = label table from mda_labels; rows are matched by T.channel
%   T = mda_addLabels(T, L, when)    when = datetime per row of T (clock time of the contraction, or of the middle
%                                     of the range for summary rows): if cultureStart is given for a channel,
%                                     daysInCulture = days since cultureStart (fractional), otherwise the label value
%
% TS 2026-10-04

h = height(T);
if nargin < 3, when = []; end
[found, loc] = ismember(T.channel, L.channel);
names = setdiff(L.Properties.VariableNames, {'channel'}, 'stable');
old = intersect(T.Properties.VariableNames, names);
if ~isempty(old), T = removevars(T, old); end             %labels added before: replace

for k = numel(names):-1:1                                     %reverse order: each one inserted after 'channel'
    col = L.(names{k});
    if iscell(col)
        v = repmat({''}, h, 1);
        v(found) = col(loc(found));
    else
        v = nan(h, 1);
        v(found) = col(loc(found));
    end
    if strcmp(names{k}, 'daysInCulture') && ~isempty(when) && ismember('cultureStart', names)
        startTxt = repmat({''}, h, 1);
        startTxt(found) = L.cultureStart(loc(found));
        d = daysSince(startTxt, when(:));
        v(~isnan(d)) = d(~isnan(d));
    end
    T = addvars(T, v, 'After', 'channel', 'NewVariableNames', names{k});
end
end


function d = daysSince(startTxt, when)
% days from cultureStart (text) to when (datetime); NaN if one of them is unknown
d = nan(numel(startTxt), 1);
[u, ~, j] = unique(startTxt);
for k = 1:numel(u)
    t0 = parseDate(u{k});
    if isnat(t0), continue; end
    I = j == k;
    d(I) = days(when(I) - t0);
end
end


function t = parseDate(s)
t = NaT;
s = strtrim(s);
if isempty(s), return; end
fmts = {'yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd HH:mm', 'yyyy-MM-dd', 'dd.MM.yyyy HH:mm:ss', 'dd.MM.yyyy HH:mm', ...
    'dd.MM.yyyy', 'yyyy/MM/dd HH:mm', 'yyyy/MM/dd'};
for k = 1:numel(fmts)
    try
        t = datetime(s, 'InputFormat', fmts{k});
        return;
    catch
    end
end
warning('mda_addLabels:cultureStart', 'cultureStart ''%s'' not understood (use e.g. 2026-09-08 14:30).', s);
end
