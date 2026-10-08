function [clk, info] = mda_clockTime(N, t, programVersion, fileTime, text)
%MDA_CLOCKTIME  Clock time of MyoDish log entries; corrects the 12-hour time stamps of software 2.0.7717-2.0.7769.
%
%   [clk, info] = mda_clockTime(N, t)
%   [clk, info] = mda_clockTime(N, t, programVersion, fileTime, text)
%
%   N               n x 7: system time of each log entry as numbers: year month day hour minute second millisecond
%                   (e.g. from '2021 03 01 03:11:50:000'); rows with NaN in columns 1-6: not readable (clk NaT)
%   t               n x 1: dataLogTime of the entries (s; NaN if not readable)
%   programVersion  'programInfo' entry (entries) of the log, e.g. 'Version 2.0.7769.26061' (char or cellstr; optional)
%   fileTime        time of the last change of the .mdd file (datetime or datenum, local time; optional)
%   text            n x 1 cellstr: value of the entries (optional; 'Started parallel recording: 01.Mar.2021 16:50:17'
%                   gives the 24-hour time of its entry)
%
%   clk             n x 1 datetime: real-world clock time of the entries
%   info            struct: format ('24h' or '12h'), nCorrected (entries shifted by 12 h), ambiguous (true: 12-hour
%                   time stamps whose AM/PM could not be determined; clk as written), source ('log', 'file time' or
%                   '' = nothing corrected), note (text for the notes of the file; '' if nothing to report)
%
% MyoDish software 2.0.7717 to 2.0.7769 (builds of 16.02.-09.04.2021; one setup used 2.0.7769 until 2024) wrote the
% system time with a 12-hour clock and without AM/PM ('hh' instead of 'HH': 17:04 is written as 05:04, 00:30 as
% 12:30). 2.0.7712 and earlier and 2.0.7971 and later write 24-hour time stamps. A log can contain both (program
% restarted with another version). The dataLogTime of the entries (ms since the start of the recording) is
% continuous, so AM/PM of the entries follows from it:
%   - an entry with hour 1-12 has two candidate times (as written, hour mod 12, and 12 h later); hours 0 and 13-23
%     are 24-hour time stamps and stay as written.
%   - entries 'Started / Stopped parallel recording: dd.MMM.yyyy HH:mm:ss' carry the 24-hour time in their text
%     (also in the affected versions): their candidate is known.
%   - the offset clock time - dataLogTime that most entries share (+-5 min) belongs to the recording; every entry
%     takes the candidate with this offset (or with the offset +-1 h: change of daylight saving time). Entries with the
%     same dataLogTime count once together (the software may log thousands of entries with a frozen dataLogTime).
%   - entries without this offset (logged before 'Recording started' with the dataLogTime of a previous recording,
%     or with a frozen dataLogTime after the recording) take the candidate that keeps the log in chronological order.
%   - a log counts as 12-hour if a 'programInfo' / 'ProgramVersion' entry names a version between 2.0.7713 and
%     2.0.7970 (the last unaffected and the first unaffected build seen in 16,203 logs of 2020-2026: 2.0.7712 and
%     2.0.7971), if a 'parallel recording' entry shows it, or if entries of the recording need the correction and
%     the corrected log is not less chronological than as written (rejects e.g. 24-hour logs with entries whose
%     stale dataLogTime belongs to a recording that started 12 h earlier). 24-hour logs are not changed.
%   - if all entries of the recording lie on the same side of noon / midnight, the log cannot tell AM from PM. Then
%     the time of the last change of the .mdd file decides if it agrees with one of the two possible ends of the
%     recording within 15 min (in 908 of 974 recordings checked, the file time was within 2 min of 'Recording
%     stopped'); otherwise the times stay as written and info.ambiguous is true (possibly 12 h too early).
%
% TS 2026-10-08

if nargin < 3, programVersion = ''; end
if nargin < 4, fileTime = []; end
if nargin < 5, text = {}; end
n = size(N, 1);
info = struct('format', '24h', 'nCorrected', 0, 'ambiguous', false, 'source', '', 'note', '');
clk = NaT(n, 1);
clk.Format = 'yyyy-MM-dd HH:mm:ss';
if n == 0, return; end
N = double(N);
if size(N, 2) < 7, N(:, end+1:7) = 0; end
ok = all(isfinite(N(:, 1:6)), 2);
msec = N(:, 7); msec(~isfinite(msec)) = 0;
if any(ok)
    clk(ok) = datetime(N(ok,1), N(ok,2), N(ok,3), N(ok,4), N(ok,5), N(ok,6), msec(ok));
end

% affected software version?
if ischar(programVersion) || isstring(programVersion), programVersion = cellstr(programVersion); end
ver = ''; affected = false;
for k = 1:numel(programVersion)
    v = regexp(programVersion{k}, '(\d+)\.(\d+)\.(\d+)(\.\d+)?', 'tokens', 'once');
    if isempty(v), continue; end
    b = str2double(v{3});
    if str2double(v{1}) == 2 && b >= 7713 && b <= 7970
        affected = true; ver = [v{1} '.' v{2} '.' v{3} v{4}];
    elseif isempty(ver)
        ver = [v{1} '.' v{2} '.' v{3} v{4}];
    end
end

% written time and candidates (ms; day number as datenum)
H12 = 43200000; TOL = 600000;
P = nan(n, 1);
P(ok) = datenum(N(ok,1), N(ok,2), N(ok,3)) * 86400000 + ((N(ok,4) * 60 + N(ok,5)) * 60 + N(ok,6)) * 1000 + msec(ok);
h = N(:, 4);
two = ok & h >= 1 & h <= 12;               %hour as written may be AM or PM
base = P; base(two & h == 12) = P(two & h == 12) - H12;   %candidate k = 0 (hour mod 12); k = 1: 12 h later
kWritten = double(two & h == 12);          %k of the time as written
% 24-hour time in the text of the entry ('Started parallel recording: 01.Mar.2021 16:50:17')
kText = nan(n, 1);
if numel(text) == n
    q = regexp(text(:), '(Started|Stopped) parallel recording: *\d{1,2}\.\S+\.\d{4} (\d{1,2}):(\d{2}):\d{2}', 'tokens', 'once', 'ignorecase');
    for i = find(two & ~cellfun(@isempty, q))'
        hT = str2double(q{i}{2}); mT = str2double(q{i}{3});
        if hT >= 0 && hT <= 23 && mT == N(i,5) && mod(hT, 12) == mod(h(i), 12)
            kText(i) = double(hT >= 12);
        end
    end
end
known = ~isnan(kText);                      %candidate known from the text
fixedVal = P; fixedVal(known) = base(known) + kText(known) * H12;   %time of entries with one candidate
needText = any(known & kText ~= kWritten);
two = two & ~known;
tm = round(t(:) * 1000);
v = ok & isfinite(tm);

% offset shared by most entries (60 s bins, window +-5 bins); ties: more entries as written, then the earlier offset.
% Weight of an entry: 1 / number of entries with the same dataLogTime (entries logged while the dataLogTime is frozen,
% e.g. after the end of a recording, count once together).
w = zeros(n, 1);
if any(v)
    [~, ~, jt] = unique(tm(v)); ct = accumarray(jt, 1); w(v) = 1 ./ ct(jt);
end
i2 = find(v & two); i1 = find(v & ~two);
cand = [base(i2) - tm(i2); base(i2) + H12 - tm(i2); fixedVal(i1) - tm(i1)];
wc = [w(i2); w(i2); w(i1)];
asWritten = [kWritten(i2) == 0; kWritten(i2) == 1; fixedVal(i1) == P(i1)];
rnd = @(x) floor(x * 1e6 + 0.5) / 1e6;     %sums of weights: identical in MATLAB and Python
if isempty(cand)
    Ob = nan; tie = false; altBin = nan;
else
    bin = floor(cand / 60000);
    [ub, ~, j] = unique(bin);
    cs = [0; cumsum(accumarray(j, wc))]; csW = [0; cumsum(accumarray(j, wc .* asWritten))];
    m = numel(ub); lo = zeros(m, 1); hi = zeros(m, 1);
    a = 1; z = 0;
    for k = 1:m
        while z < m && ub(z+1) <= ub(k) + 5, z = z + 1; end
        while ub(a) < ub(k) - 5, a = a + 1; end
        lo(k) = a; hi(k) = z;
    end
    sc = rnd(cs(hi+1) - cs(lo)); scW = rnd(csW(hi+1) - csW(lo));
    [~, o] = sortrows([-sc, -scW, ub]);
    Ob = ub(o(1)); best = sc(o(1));
    sPlus = scoreAt(Ob + 720); sMinus = scoreAt(Ob - 720);
    tie = max(sPlus, sMinus) >= best;
    if sPlus >= sMinus, altBin = Ob + 720; else, altBin = Ob - 720; end
end

[shift, needCorr, lastMain] = assign(Ob);
if needCorr && ~affected && ~needText
    % correction found in the data only: reject it if it makes the log less chronological (more steps back by
    % > 65 min), e.g. for entries with the stale dataLogTime of a recording that started 12 h earlier
    io = find(ok);
    if sum(diff(P(io) + shift(io)) < -3900000) > sum(diff(P(io)) < -3900000)
        needCorr = false;
    end
end
is12 = needCorr || needText || affected;
if ~is12, return; end                       %24-hour log: clock times as written
info.format = '12h';
src = 'log';
if tie
    decided = false;
    if ~isempty(fileTime) && ~isnan(lastMain)
        if isdatetime(fileTime), fileTime = datenum(fileTime); end
        F = double(fileTime) * 86400000;
        [shiftAlt, ~, lastAlt] = assign(altBin);
        if abs(F - lastMain) <= 900000 && abs(F - lastAlt) > 900000
            decided = true; src = 'file time';
        elseif abs(F - lastAlt) <= 900000 && abs(F - lastMain) > 900000
            decided = true; src = 'file time'; shift = shiftAlt;
        end
    end
    info.ambiguous = ~decided;
end
info.nCorrected = nnz(shift ~= 0);
if info.nCorrected > 0
    clk(ok) = clk(ok) + milliseconds(shift(ok));
end
if isempty(ver), vtxt = ''; else, vtxt = [', software ' ver]; end
if info.ambiguous
    info.source = '';
    info.note = sprintf(['12-hour time stamps in the log file (no AM/PM%s): AM/PM of the recording unknown, ' ...
        'clock times as written (possibly 12 h too early).'], vtxt);
elseif info.nCorrected > 0
    info.source = src;
    info.note = sprintf('12-hour time stamps in the log file (no AM/PM%s): clock time of %d entries corrected by 12 h (AM/PM from the %s).', ...
        vtxt, info.nCorrected, regexprep(src, '^log$', 'dataLogTime'));
end


    function sAt = scoreAt(b0)
        a0 = find(ub >= b0 - 5, 1); z0 = find(ub <= b0 + 5, 1, 'last');
        if isempty(a0) || isempty(z0) || a0 > z0, sAt = 0; else, sAt = rnd(cs(z0+1) - cs(a0)); end
    end

    function [sh, need, lastM] = assign(Ob0)
        % shift (ms) of every entry for the recording offset bin Ob0
        sh = zeros(n, 1); need = false; lastM = nan;
        kc = nan(n, 1);                      %chosen candidate of entries with hour 1-12 (NaN: not decided)
        anchor = false(n, 1);               %clock time known: decided by the offset, or 24-hour time stamp
        anchor(ok & ~two) = true;
        if ~isnan(Ob0)
            for kk = [0 1]
                off = floor((base + kk * H12 - tm) / 60000);
                inMain = v & two & isnan(kc) & abs(off - Ob0) <= 5;
                inDst = v & two & isnan(kc) & ~inMain & (abs(off - Ob0 - 60) <= 5 | abs(off - Ob0 + 60) <= 5);
                kc(inMain) = kk; kc(inDst) = kk;
                anchor(inMain | inDst) = true;
                need = need || any(inMain & kk ~= kWritten);
                lastM = max([lastM; base(inMain) + kk * H12]);
            end
            offS = floor((fixedVal - tm) / 60000);
            inMainS = v & ~two & abs(offS - Ob0) <= 5;
            lastM = max([lastM; fixedVal(inMainS)]);
        end
        cur = fixedVal;
        cur(two & ~isnan(kc)) = base(two & ~isnan(kc)) + kc(two & ~isnan(kc)) * H12;
        % entries not decided by the offset: chronological order of the log
        first = find(anchor, 1);
        if isempty(first)
            sh(ok) = 0; return;             %nothing to anchor: as written
        end
        last = cur(first);
        for ii = first+1:n
            if ~ok(ii), continue; end
            if two(ii) && isnan(kc(ii))
                kc(ii) = double(base(ii) < last - TOL);   %earliest candidate not before the previous entry
                cur(ii) = base(ii) + kc(ii) * H12;
            end
            last = cur(ii);
        end
        nxt = cur(first);
        for ii = first-1:-1:1
            if ~ok(ii), continue; end
            if two(ii) && isnan(kc(ii))
                kc(ii) = double(base(ii) + H12 <= nxt + TOL);  %latest candidate not after the next entry
                cur(ii) = base(ii) + kc(ii) * H12;
            end
            nxt = cur(ii);
        end
        sh(ok) = cur(ok) - P(ok);
    end
end
