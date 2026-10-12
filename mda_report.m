function varargout = mda_report(varargin)
%MDA_REPORT  Analysis report (PDF): which analyses should be checked, with traces and the commands to open them in the
%GUI. Same flags and pages as the Python version (report.py).
%
%   R = mda_report(recs, pdfFile, 'title', t, 'subtitle', {...}, 'flags', fl, 'maxPages', 8, 'windowSeconds', 20,
%                  'notice', {...})     notice: lines in red at the top of the first page (watcher: recordings analysed
%                                       with another version or other options)
%   R = mda_report('analysis', pdfFile, mddFile, C, S, info, resultsFile, fl)   report of one analysis (MyoDishAnalysis,
%                                       GUI); the GUI commands open resultsFile (or the recording if it is empty)
%   R = mda_report('flags', S, C, status, fl)   flags per channel (table), no PDF
%   f = mda_report('path', outputFile, report)  file of the report of an analysis: report [] / true / 'on' ->
%                                       <outputFile without extension>_report.pdf ('' without outputFile), false /
%                                       'off' -> '', a file name -> this file
%   fl = mda_report('defaults')         default flags (struct)
%   [from, to] = mda_report('window', C, channel, codes, width)
%   [m, p] = mda_report('commands', file, channel, from, to)   MATLAB and Python commands that open the GUI there
%
% Written by MyoDishAnalysisWatch after every pass with analysed recordings (resultsFolder/reports/
% mda_report_<date>_<time>.pdf, option 'report'), by MyoDishAnalysis with an output file (<output>_report.pdf, option
% 'report') and by the GUI on request (menu Save / Export).
%
% recs: struct array, one element per recording: name (shown), file (.mdd), open (file for the GUI commands: results
% file of the analysis, otherwise the .mdd file), S (summary), C (contractions, optional: amplitude, delay and markers
% of the traces), P (pulse table, optional: pulses in the traces; or P_file: read only for the detail pages), R
% (optional: flags of mda_report('flags', ...), computed by the caller), status (table channel, status of the watcher
% channel table, e.g. 'no slice'; optional), notes (cellstr, e.g. protocols not analysed; 'error: ...' = analysis
% error).
%
% Flags per channel (channels with a slice and at least minBeats (50) detected contractions):
%   check the analysis (red: the analysis may not work, or technical faults put wrong values into the data; detail
%   page with traces):
%     I  inverted signal (column invertedSignal) in ranges with at least minBeats detected contractions (sensor not
%        working properly; only beating, capture and rate are analysed)
%     N  noise suspected: uncertain contractions >= uncertain (25) % of the detected ones and, in a paced channel,
%        extra beats + missed beats (% of the detected contractions + % of the stimuli) >= irregular (15) %:
%        contractions near the detection threshold that do not follow the pacing are mostly noise or artifacts (e.g.
%        rocker waves). Uncertain contractions with regular capture (few extra and missed beats) are real contractions
%        near the threshold and not flagged. Noise index = uncertain % x min(100, extra % + missed %) / 100 (unpaced
%        channel: uncertain %); it orders the detail pages.
%     S  large extra beats: certain extra beats >= artifactShare (5) % of the contractions with a median amplitude >
%        artifactRatio (3) times that of the certain stimulated contractions (spikes, saturation; needs C)
%     D  median delay pulse -> onset of the stimulated contractions > delay (0.15 s)
%   slice quality (yellow: possibly poor biological quality, e.g. also an effect of a treatment; the user decides):
%     C  capture < capture (90) % of the stimuli
%     X  extra beats > extra (10) % of the detected contractions (spontaneous activity; not shown with N)
%     A  median amplitude of the included contractions < amplitude (75 uN)
%     T  amplitude change > amplitudeChange (30) % from the first to the last range with >= 10 included contractions
%        (shown with the time between the start of the first and the end of the last of these ranges, e.g. 'amplitude
%        change +660 % over 24 h')
%     V  median amplitude CV of the ranges > amplitudeCV (30) %
% Channel label (lists and trace pages, e.g. 'ch 7 (PMA)'): the values of the label treatment (with concentration and
% unit), otherwise sliceGroup, otherwise sampleGroup of the summary, if given.
% Pages: overview (recordings x channels: capture % and codes), list of the channels to check (red) and of those with
% slice-quality flags (yellow), one page per recording with red flags (at most maxPages, the recordings with the
% most red flags and the highest noise index first; up to 4 channels with a window of windowSeconds at the most
% uncertain / extra beats (N) or large extra beats (S)) with the commands to open them:
%     MATLAB  MyoDishAnalysisGUI(file, 'channel', c, 'window', [from to])
%     Python  mda-gui file --channel c --window from to
% Needs MATLAB R2021b or newer (exportgraphics with 'Append').
%
% TS 2026-10-11 (noise index N, large extra beats S, extra beats as slice quality 2026-10-12)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

if ischar(varargin{1}) || isstring(varargin{1})
    switch lower(char(varargin{1}))
        case 'defaults'
            varargout{1} = defaults();
        case 'flags'
            a = [varargin(2:end), cell(1, 4)];
            varargout{1} = reportFlags(a{1}, a{2}, a{3}, flagsOf(a{4}));
        case 'window'
            [varargout{1}, varargout{2}] = reportWindow(varargin{2:5});
        case 'commands'
            [varargout{1}, varargout{2}] = guiCommands(varargin{2:5});
        case 'path'
            a = [varargin(2:end), cell(1, 2)];
            varargout{1} = reportPath(a{1}, a{2});
        case 'analysis'
            a = [varargin(2:end), cell(1, 7)];
            varargout{1} = analysisReport(a{1:7});
        otherwise
            error('mda_report: unknown mode ''%s''', char(varargin{1}));
    end
    return;
end
recs = varargin{1}; out = char(varargin{2});
p = struct('title', 'MyoDishAnalysis report', 'subtitle', {{}}, 'flags', [], 'maxpages', 8, 'windowseconds', 20, ...
    'notice', {{}});
for i = 3:2:numel(varargin)
    k = lower(char(varargin{i}));
    if ~isfield(p, k), error('mda_report: unknown option ''%s''', varargin{i}); end
    p.(k) = varargin{i+1};
end
varargout{1} = writeReport(recs, out, p.title, cellstr(p.subtitle), flagsOf(p.flags), p.maxpages, p.windowseconds, ...
    cellstr(p.notice));
end


% =====================================================================================================
function fl = defaults()
fl = struct('uncertain', 25, 'irregular', 15, 'artifactShare', 5, 'artifactRatio', 3, 'extra', 10, 'capture', 90, ...
    'amplitudeChange', 30, 'amplitude', 75, 'amplitudeCV', 30, 'delay', 0.15, 'minBeats', 50);
end


function fl = flagsOf(x)
fl = defaults();
if isempty(x), return; end
for f = fieldnames(x)'
    if ~isfield(fl, f{1})
        error('mda_report: unknown flag ''%s'' (%s)', f{1}, strjoin(fieldnames(fl)', ', '));
    end
    fl.(f{1}) = x.(f{1});
end
end


function v = colSum(s, name)
v = 0;
if ~isempty(s) && ismember(name, s.Properties.VariableNames), v = sum(double(s.(name)), 'omitnan'); end
end


function b = truthy(x)
% logical column of a table (logical, numeric or text 'true' / 'false' of a csv file)
if iscell(x) || isstring(x), b = any(strcmpi(string(x), ["true" "1"]), 2);
else, b = double(x) ~= 0 & ~isnan(double(x)); end
b = b(:);
end


function v = texts(x)
% non-empty texts of a table column, unique in order (csv: an empty column is read as NaN)
v = {};
if isempty(x) || isnumeric(x) || islogical(x), return; end
x = strtrim(cellstr(string(x)));
x = x(~cellfun(@isempty, x) & ~strcmpi(x, 'nan') & ~strcmp(x, '<missing>'));
if ~isempty(x), v = unique(x, 'stable'); v = v(:)'; end
end


function txt = channelLabel(s)
% short label of a channel from the label columns of its summary rows: treatment (with concentration and unit),
% otherwise sliceGroup, otherwise sampleGroup; several values joined by ' / '; '' if none
txt = '';
if isempty(s) || height(s) == 0, return; end
vn = s.Properties.VariableNames;
vals = {};
if ismember('treatment', vn)
    for i = 1:height(s)
        t = texts(s.treatment(i));
        if isempty(t), continue; end
        v = t{1};
        c = NaN;
        if ismember('concentration', vn)
            c = s.concentration(i);
            if iscell(c) || isstring(c), c = str2double(string(c)); end
            c = double(c);
        end
        if ~isnan(c)
            v = sprintf('%s %g', v, c);
            if ismember('concentrationUnit', vn)
                u = texts(s.concentrationUnit(i));
                if ~isempty(u), v = [v ' ' u{1}]; end
            end
        end
        if ~ismember(v, vals), vals{end+1} = v; end %#ok<AGROW>
    end
end
for col = {'sliceGroup', 'sampleGroup'}
    if isempty(vals) && ismember(col{1}, vn), vals = texts(s.(col{1})); end
end
if isempty(vals), return; end
txt = strjoin(vals(1:min(3, numel(vals))), ' / ');
if numel(vals) > 3, txt = [txt ' / ' char(8230)]; end
if numel(txt) > 40, txt = [txt(1:39) char(8230)]; end
end


function s = durationText(h)
% '45 min', '5.5 h', '24 h', '3.5 d'
if isnan(h), s = '';
elseif h < 1.5, s = sprintf('%.0f min', 60 * h);
elseif h < 10, s = sprintf('%.1f h', h);
elseif h < 72, s = sprintf('%.0f h', h);
else, s = sprintf('%.1f d', h / 24);
end
end


function s = labelOf(R, r)
s = '';
if ismember('label', R.Properties.VariableNames) && ~isempty(R.label{r}), s = [' (' R.label{r} ')']; end
end


function R = reportFlags(S, C, status, fl)
% one row per channel: counts, values and flags (flags = codes, red / yellow = descriptions)
chans = [];
if ~isempty(S) && height(S) > 0, chans = double(S.channel(:)); end
st = containers.Map('KeyType', 'double', 'ValueType', 'any');
if ~isempty(status) && height(status) > 0
    for i = 1:height(status), st(double(status.channel(i))) = char(string(status.status(i))); end
    chans = [chans; double(status.channel(:))];
end
chans = unique(chans);
n = numel(chans);
R = table(chans, repmat({''}, n, 1), repmat({''}, n, 1), zeros(n, 1), nan(n, 1), nan(n, 1), nan(n, 1), nan(n, 1), ...
    nan(n, 1), nan(n, 1), nan(n, 1), nan(n, 1), nan(n, 1), nan(n, 1), nan(n, 1), nan(n, 1), false(n, 1), ...
    repmat({''}, n, 1), repmat({''}, n, 1), repmat({''}, n, 1), repmat({''}, n, 1), ...
    'VariableNames', {'channel', 'label', 'status', 'nDetected', 'capture_percent', 'extra_percent', ...
    'uncertain_percent', 'extraMissed_percent', 'noiseIndex', 'largeExtra_percent', 'largeExtra_ratio', ...
    'amplitude_uN', 'amplitudeChange_percent', 'amplitudeChange_hours', 'amplitudeCV_percent', 'delay_ms', ...
    'invertedSignal', 'flags', 'level', 'red', 'yellow'});
for k = 1:n
    c = chans(k);
    if isKey(st, c), R.status{k} = st(c); end
    s = [];
    if ~isempty(S) && height(S) > 0, s = S(double(S.channel) == c, :); end
    R.label{k} = channelLabel(s);
    nDet = colSum(s, 'nDetected'); nStim = colSum(s, 'nStimuli'); nMiss = colSum(s, 'nMissedBeats');
    nX = colSum(s, 'nExtraBeats'); nU = colSum(s, 'nUncertain');
    R.nDetected(k) = nDet;
    if nStim > 0, R.capture_percent(k) = 100 * (1 - nMiss / nStim); end
    if nDet > 0, R.extra_percent(k) = 100 * nX / nDet; R.uncertain_percent(k) = 100 * nU / nDet; end
    if nDet > 0                 %noise index: uncertain contractions in a channel that does not follow the pacing
        if nStim > 0
            R.extraMissed_percent(k) = R.extra_percent(k) + 100 - R.capture_percent(k);
            R.noiseIndex(k) = R.uncertain_percent(k) * min(100, R.extraMissed_percent(k)) / 100;
        else
            R.noiseIndex(k) = R.uncertain_percent(k);
        end
    end
    if ~isempty(s) && all(ismember({'nContractions', 'amplitude_mean'}, s.Properties.VariableNames))
        good = s(s.nContractions >= 10, :);
        if height(good) > 1 && good.amplitude_mean(1) > 0
            R.amplitudeChange_percent(k) = 100 * (good.amplitude_mean(end) - good.amplitude_mean(1)) / good.amplitude_mean(1);
            if all(ismember({'from', 'to'}, good.Properties.VariableNames))
                R.amplitudeChange_hours(k) = (double(good.to(end)) - double(good.from(1))) / 3600;
            end
        end
    end
    if ~isempty(s) && ismember('amplitude_CV', s.Properties.VariableNames)
        cv = double(s.amplitude_CV); cv = cv(~isnan(cv));
        if ~isempty(cv), R.amplitudeCV_percent(k) = 100 * median(cv); end
    end
    nInv = 0;
    if ~isempty(s) && ismember('invertedSignal', s.Properties.VariableNames)
        iv = truthy(s.invertedSignal);
        R.invertedSignal(k) = any(iv);
        nInv = colSum(s(iv, :), 'nDetected');
    end
    cc = [];
    if ~isempty(C) && height(C) > 0, cc = C(double(C.channel) == c, :); end
    if ~isempty(cc) && height(cc) > 0
        inc = cc;
        if ismember('included', cc.Properties.VariableNames), inc = cc(truthy(cc.included), :); end
        if ismember('amplitude', inc.Properties.VariableNames)
            a = double(inc.amplitude); a = a(~isnan(a));
            if ~isempty(a), R.amplitude_uN(k) = median(a); end
        end
        if all(ismember({'beatType', 'stimToOnset'}, cc.Properties.VariableNames))
            d = double(cc.stimToOnset(strcmp(cellstr(cc.beatType), 'stimulated'))); d = d(~isnan(d));
            if ~isempty(d), R.delay_ms(k) = 1000 * median(d); end
        end
        if all(ismember({'beatType', 'uncertain', 'amplitude'}, cc.Properties.VariableNames))   %large certain extra beats
            cert = ~truthy(cc.uncertain); bt = cellstr(string(cc.beatType)); am = double(cc.amplitude);
            ae = am(cert & strcmp(bt, 'extra')); ap = am(cert & strcmp(bt, 'stimulated'));
            ae = ae(~isnan(ae)); ap = ap(~isnan(ap));
            R.largeExtra_percent(k) = 100 * numel(ae) / height(cc);
            if ~isempty(ae) && ~isempty(ap) && median(ap) > 0, R.largeExtra_ratio(k) = median(ae) / median(ap); end
        end
    elseif ~isempty(s) && ismember('amplitude_mean', s.Properties.VariableNames) && any(~isnan(s.amplitude_mean))
        R.amplitude_uN(k) = median(s.amplitude_mean, 'omitnan');
    end
    red = {}; codes = '';
    yel = {}; ycodes = '';
    if ~strcmp(R.status{k}, 'no slice') && nDet >= fl.minBeats
        if nInv >= fl.minBeats                     %ranges with an inverted signal and enough contractions
            if nInv < nDet, red{end+1} = sprintf('inverted signal (%.0f %% of the contractions)', 100 * nInv / nDet); %#ok<AGROW>
            else, red{end+1} = 'inverted signal'; end %#ok<AGROW>
            codes(end+1) = 'I'; %#ok<AGROW>
        end
        noise = R.uncertain_percent(k) >= fl.uncertain && (nStim <= 0 || R.extraMissed_percent(k) >= fl.irregular);
        if noise
            if nStim > 0
                red{end+1} = sprintf('noise index %.0f (uncertain %.0f %%, extra %.0f %%, missed %.0f %%)', ...
                    R.noiseIndex(k), R.uncertain_percent(k), R.extra_percent(k), 100 - R.capture_percent(k)); %#ok<AGROW>
            else
                red{end+1} = sprintf('noise index %.0f (uncertain %.0f %%, unpaced)', R.noiseIndex(k), ...
                    R.uncertain_percent(k)); %#ok<AGROW>
            end
            codes(end+1) = 'N'; %#ok<AGROW>
        end
        if R.largeExtra_percent(k) >= fl.artifactShare && R.largeExtra_ratio(k) > fl.artifactRatio
            red{end+1} = sprintf('large extra beats %.0f %% (%.1f x the paced amplitude)', R.largeExtra_percent(k), ...
                R.largeExtra_ratio(k)); codes(end+1) = 'S'; %#ok<AGROW>
        end
        if R.delay_ms(k) > 1000 * fl.delay
            red{end+1} = sprintf('delay %.0f ms', R.delay_ms(k)); codes(end+1) = 'D'; %#ok<AGROW>
        end
        if R.capture_percent(k) < fl.capture
            yel{end+1} = sprintf('capture %.0f %%', R.capture_percent(k)); ycodes(end+1) = 'C'; %#ok<AGROW>
        end
        if ~noise && R.extra_percent(k) > fl.extra
            yel{end+1} = sprintf('extra beats %.0f %%', R.extra_percent(k)); ycodes(end+1) = 'X'; %#ok<AGROW>
        end
        if ~R.invertedSignal(k) && R.amplitude_uN(k) < fl.amplitude
            yel{end+1} = sprintf('amplitude %.0f uN', R.amplitude_uN(k)); ycodes(end+1) = 'A'; %#ok<AGROW>
        end
        if abs(R.amplitudeChange_percent(k)) > fl.amplitudeChange
            d = durationText(R.amplitudeChange_hours(k));
            if isempty(d), d = '(first vs. last range)'; else, d = ['over ' d]; end
            yel{end+1} = sprintf('amplitude change %+.0f %% %s', R.amplitudeChange_percent(k), d); %#ok<AGROW>
            ycodes(end+1) = 'T'; %#ok<AGROW>
        end
        if R.amplitudeCV_percent(k) > fl.amplitudeCV
            yel{end+1} = sprintf('amplitude CV %.0f %%', R.amplitudeCV_percent(k)); ycodes(end+1) = 'V'; %#ok<AGROW>
        end
    end
    R.flags{k} = [codes ycodes];
    R.red{k} = strjoin(red, '; ');
    R.yellow{k} = strjoin(yel, ', ');
    if ~isempty(red), R.level{k} = 'check';
    elseif ~isempty(yel), R.level{k} = 'quality';
    elseif strcmp(R.status{k}, 'no slice'), R.level{k} = 'no slice';
    elseif nDet < fl.minBeats, R.level{k} = 'few beats';
    end
end
end


function [a, b] = reportWindow(C, channel, codes, width)
% window [a, a + width] at the most uncertain / extra contractions (code N; X, U as well), at the most certain
% extra beats (S), otherwise around the median contraction
if nargin < 4 || isempty(width), width = 20; end
a = 0; b = width;
if isempty(C) || height(C) == 0 || ~ismember('t_peak', C.Properties.VariableNames), return; end
c = C(double(C.channel) == channel, :);
if height(c) == 0, return; end
t = double(c.t_peak);
bad = false(height(c), 1);
ex = false(height(c), 1); un = false(height(c), 1);
if ismember('beatType', c.Properties.VariableNames), ex = strcmp(cellstr(string(c.beatType)), 'extra'); end
if ismember('uncertain', c.Properties.VariableNames), un = truthy(c.uncertain); end
if contains(codes, 'X') || contains(codes, 'N'), bad = bad | ex; end
if contains(codes, 'U') || contains(codes, 'N'), bad = bad | un; end
if contains(codes, 'S') && ~any(bad), bad = ex & ~un; end
if any(bad)
    e0 = floor(min(t)); stop = max(t) + width;
    e = e0 + width * (0:ceil((stop - e0) / width) - 1);       %as numpy arange(e0, stop, width)
    h = histcounts(t(bad), e);
    [~, j] = max(h);
    a = e(j);
else
    a = floor(median(t, 'omitnan') - width / 2);
end
a = max(0, a); b = a + width;
end


function [m, p] = guiCommands(file, channel, a, b)
m = sprintf('MyoDishAnalysisGUI(''%s'', ''channel'', %d, ''window'', [%g %g])', strrep(char(file), '''', ''''''), ...
    channel, a, b);
p = sprintf('mda-gui "%s" --channel %d --window %g %g', char(file), channel, a, b);
end


function f = reportPath(output, report)
f = '';
if isequal(report, false) || (isempty(report) && isempty(output)), return; end
if ischar(report) || isstring(report)
    r = char(report);
    if any(strcmpi(r, {'off', 'false', 'none', ''})), return; end
    if ~any(strcmpi(r, {'on', 'true', 'auto'})), f = r; return; end
end
if isempty(output), return; end
o = char(output);
[pth, n, e] = fileparts(o);
if any(strcmpi(e, {'.xlsx', '.xls', '.csv'})), f = fullfile(pth, [n '_report.pdf']); else, f = [o '_report.pdf']; end
end


function txt = optionsChanged(opts)
% 'name=value; ...' of the options that differ from the defaults (subtitle of the report)
d0 = mda_options();
ch = {};
for f = fieldnames(opts)'
    if strcmp(f{1}, 'referenceBeat') || ~isfield(d0, f{1}), continue; end
    if ~isequaln(opts.(f{1}), d0.(f{1})), ch{end+1} = sprintf('%s=%s', f{1}, valueText(opts.(f{1}))); end %#ok<AGROW>
end
if isempty(ch), txt = 'defaults'; else, txt = strjoin(ch, '; '); end
end


function s = valueText(v)
if ischar(v) || isstring(v), s = char(v);
elseif islogical(v) && isscalar(v), s = mat2str(v);
elseif isnumeric(v) || islogical(v), s = mat2str(v, 6);
else, s = class(v); end
end


function R = analysisReport(out, file, C, S, info, results, fl)
notes = {};
if isfield(info, 'notes') && ~isempty(info.notes)
    nt = cellstr(info.notes);
    notes = nt(contains(nt, 'not analysed'));
end
P = [];
if isfield(info, 'pulses'), P = info.pulses; end
[~, n, e] = fileparts(char(file));
if isempty(results), opn = char(file); else, opn = char(results); end
rec = struct('name', [n e], 'file', char(file), 'open', opn, 'S', S, 'C', C, 'P', P, 'status', [], 'notes', {notes});
if isfield(info, 'options'), o = optionsChanged(info.options); else, o = 'defaults'; end
if isempty(results), rs = 'results: not written'; else, rs = ['results: ' char(results)]; end
ad = '';
if isfield(info, 'analysisDate'), ad = info.analysisDate; end
sub = {['recording: ' char(file)], rs, sprintf('MyoDishAnalysis %s (MATLAB), analysed %s; settings: %s', ...
    mda_version(), ad, o)};
R = writeReport(rec, out, 'MyoDishAnalysis report', sub, flagsOf(fl), 8, 20, {});
end


% ===================================================================================================== PDF
function Rall = writeReport(recs, out, title, subtitle, fl, maxPages, winS, notice)
nR = numel(recs);
Rs = cell(nR, 1);
for i = 1:nR
    rec = recs(i);
    st = []; if isfield(rec, 'status'), st = rec.status; end
    C = []; if isfield(rec, 'C'), C = rec.C; end
    if isfield(rec, 'R') && ~isempty(rec.R), R = rec.R;   %flags computed by the caller (watcher)
    else, R = reportFlags(rec.S, C, st, fl); end
    R = addvars(R, repmat({rec.name}, height(R), 1), 'Before', 1, 'NewVariableNames', 'recording');
    R.window_from = nan(height(R), 1); R.window_to = nan(height(R), 1);
    R.matlab = repmat({''}, height(R), 1); R.python = repmat({''}, height(R), 1);
    opn = '';
    if isfield(rec, 'open'), opn = rec.open; end
    if isempty(opn), opn = rec.file; end
    for j = find(strcmp(R.level, 'check'))'
        [a, b] = reportWindow(C, R.channel(j), R.flags{j}, winS);
        R.window_from(j) = a; R.window_to(j) = b;
        [R.matlab{j}, R.python{j}] = guiCommands(opn, R.channel(j), a, b);
    end
    recs(i).open = opn;
    if ~isfield(rec, 'notes') || isempty(rec.notes), recs(i).notes = {}; else, recs(i).notes = cellstr(rec.notes); end
    Rs{i} = R;
end
if nR, Rall = vertcat(Rs{:}); else, Rall = reportFlags([], [], [], fl); end
isCheck = cellfun(@(R) any(strcmp(R.level, 'check')), Rs);
nRed = cellfun(@(R) sum(cellfun(@(x) sum(ismember(x, 'INSD')), R.flags(strcmp(R.level, 'check')))), Rs);
maxNI = cellfun(@(R) max([0; R.noiseIndex(strcmp(R.level, 'check') & ~isnan(R.noiseIndex))]), Rs);
check = find(isCheck | arrayfun(@(r) ~isempty(r.notes), recs(:)));
det = find(isCheck);
[~, o] = sortrows([-nRed(det(:)), -maxNI(det(:))]);
det = det(o);                                       %stable: the most red flags, the highest noise index first
det = det(1:min(maxPages, numel(det)));
d = fileparts(out);
if ~isempty(d) && ~exist(d, 'dir'), mkdir(d); end
if exist(out, 'file'), delete(out); end
pg = overviewPages(out, recs, Rs, title, subtitle, fl, numel(det), notice);
listPages(out, recs, Rs, check, det, pg);
for k = 1:numel(det)
    detailPage(out, recs(det(k)), Rs{det(k)});
end
end


function [fig, ax] = newPage()
fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [1 1 21 29.7], 'Color', 'w', ...
    'PaperUnits', 'centimeters', 'PaperSize', [21 29.7], 'PaperPosition', [0 0 21 29.7]);
ax = axes(fig, 'Position', [0 0 1 1], 'XLim', [0 1], 'YLim', [0 1], 'Visible', 'off');
hold(ax, 'on');
end


function savePage(fig, out)
app = exist(out, 'file') == 2;
try
    exportgraphics(fig, out, 'ContentType', 'vector', 'Append', app, 'Padding', 'figure');
catch
    exportgraphics(fig, out, 'ContentType', 'vector', 'Append', app);
end
close(fig);
end


function txt(ax, x, y, s, sz, varargin)
text(ax, x, y, s, 'FontSize', sz, 'Interpreter', 'none', 'VerticalAlignment', 'baseline', varargin{:});
end


function s = shortName(name, n)
s = strrep(strrep(strrep(char(name), '.mdd', ''), '_scheduleFile_', ' sched '), '_withParallelRecording', '');
if numel(s) > n, s = [s(1:n-1) char(8230)]; end
end


function pg = overviewPages(out, recs, Rs, title, subtitle, fl, nDetail, notice)
RED = [0.776 0.157 0.157]; GREY = [0.33 0.33 0.33];
nRed = sum(cellfun(@(R) sum(strcmp(R.level, 'check')), Rs));
nYel = sum(cellfun(@(R) sum(strcmp(R.level, 'quality')), Rs));
nSl = sum(cellfun(@(R) sum(~strcmp(R.status, 'no slice')), Rs));
chans = unique(cell2mat(cellfun(@(R) double(R.channel(:)), Rs(:), 'UniformOutput', false)))';
if isempty(chans), chans = 1:8; end
perPage = 48;
nP = max(1, ceil(numel(recs) / perPage));
pg = 0;
for p = 1:nP
    [fig, ax] = newPage();
    t = title; if nP > 1, t = sprintf('%s (overview %d/%d)', title, p, nP); end
    txt(ax, 0.05, 0.965, t, 14, 'FontWeight', 'bold');
    y = 0.948;
    for i = 1:numel(subtitle)
        w = wrapText(subtitle{i}, 150);
        for j = 1:min(2, numel(w)), txt(ax, 0.05, y, w{j}, 6.5, 'Color', GREY); y = y - 0.011; end
    end
    if p == 1 && ~isempty(notice)                      %e.g. recordings analysed with another version (watcher)
        y = y - 0.003;
        for i = 1:numel(notice)
            w = wrapText(notice{i}, 135);
            if i == 1, fw = 'bold'; else, fw = 'normal'; end
            for j = 1:min(3, numel(w)), txt(ax, 0.05, y, w{j}, 7, 'Color', RED, 'FontWeight', fw); y = y - 0.012; end
        end
    end
    s = sprintf('%d recording(s), %d channel(s) with a slice: %d to check (red', numel(recs), nSl, nRed);
    if nDetail, s = sprintf('%s, traces on %d page(s)', s, nDetail); end
    txt(ax, 0.05, y - 0.004, sprintf('%s), %d with slice-quality flags (yellow)', s, nYel), 8);
    top = y - 0.02;
    % matrix: axes coordinates 0..1 in [0.05 0.10 0.92 top-0.10] of the page
    X = @(x) 0.05 + 0.92 * x; Y = @(v) 0.10 + (top - 0.10) * v;
    rh = 1 / (perPage + 1); x0 = 0.46; cw = min(0.068, (1 - x0) / numel(chans));
    txt(ax, X(0), Y(1) - 0.006, 'recording', 7, 'FontWeight', 'bold');
    for j = 1:numel(chans)
        txt(ax, X(x0 + (j - 0.5) * cw), Y(1) - 0.006, sprintf('ch %d', chans(j)), 7, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center');
    end
    idx = (p - 1) * perPage + 1:min(numel(recs), p * perPage);
    for k = 1:numel(idx)
        rec = recs(idx(k)); R = Rs{idx(k)};
        yk = 1 - k * rh;
        text(ax, X(0), Y(yk - rh * 0.2), shortName(rec.name, 62), 'FontSize', 6, 'Interpreter', 'none', ...
            'VerticalAlignment', 'top');
        if ~isempty(rec.notes)
            mk = 'P'; if any(startsWith(rec.notes, 'error')), mk = 'E'; end
            text(ax, X(x0 - 0.008), Y(yk - rh * 0.2), mk, 'FontSize', 6, 'VerticalAlignment', 'top', ...
                'HorizontalAlignment', 'right', 'Color', RED, 'FontWeight', 'bold');
        end
        for j = 1:numel(chans)
            r = find(R.channel == chans(j), 1);
            if isempty(r), continue; end
            switch R.level{r}
                case 'no slice', col = [1 1 1]; s = '';
                case 'few beats'
                    col = hex('#eeeeee');
                    m = containers.Map({'beating', 'not beating', 'removed', 'signal lost', 'protocols only'}, ...
                        {'b', 'nb', 'rm', 'lost', 'prot'});
                    if isKey(m, R.status{r}), s = m(R.status{r}); else, s = sprintf('%d', R.nDetected(r)); end
                otherwise
                    if strcmp(R.level{r}, 'check'), col = hex('#f8c9c4');
                    elseif strcmp(R.level{r}, 'quality'), col = hex('#fbe8a6');
                    else, col = [1 1 1]; end
                    s = R.flags{r};
                    if ~isnan(R.capture_percent(r)), s = strtrim(sprintf('%.0f %s', R.capture_percent(r), s)); end
            end
            x1 = X(x0 + (j - 1) * cw + 0.002); y1 = Y(yk - rh + 0.001);
            rectangle(ax, 'Position', [x1, y1, 0.92 * (cw - 0.004), (top - 0.10) * (rh - 0.002)], ...
                'FaceColor', col, 'EdgeColor', 'none');
            text(ax, X(x0 + (j - 0.5) * cw), Y(yk - rh / 2), s, 'FontSize', 5.5, 'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', 'Interpreter', 'none');
        end
    end
    legendLines(ax, fl);
    savePage(fig, out);
    pg = pg + 1;
end
end


function L = legendText(fl)
% {cell colour ('' = none), text} of the legend below the overview table
mu = char(181);
L = {'', ['Each cell: capture (% of the stimuli followed by a contraction) and the letters of the flags. White: ' ...
        'no flag; empty: no slice.']
    '#f8c9c4', sprintf(['Red = check the analysis:  I inverted signal,  N noise (uncertain %s %g %% with extra + ' ...
        'missed %s %g %%),  S large extra beats (> %g x paced),  D delay to onset > %g ms'], char(8805), ...
        fl.uncertain, char(8805), fl.irregular, fl.artifactRatio, 1000 * fl.delay)
    '#fbe8a6', sprintf(['Yellow = slice quality:  C capture < %g %%,  X extra beats > %g %%,  A amplitude < %g %sN,  ' ...
        'T amplitude changes by > %g %% during the recording,  V amplitude CV > %g %%'], fl.capture, fl.extra, ...
        fl.amplitude, mu, fl.amplitudeChange, fl.amplitudeCV)
    '#eeeeee', sprintf(['Grey = fewer than %g contractions:  b beating, nb not beating, rm removed, otherwise the ' ...
        'number of contractions'], fl.minBeats)
    '', ['Red letter left of the cells:  P a stimulation protocol was not analysed,  E analysis error  (details in ' ...
        'the list on the next page)']};
end


function legendLines(ax, fl)
L = legendText(fl);
y = 0.085;
for i = 1:size(L, 1)
    x = 0.05;
    if ~isempty(L{i, 1})
        rectangle(ax, 'Position', [0.05, y - 0.0015, 0.012, 0.0085], 'FaceColor', hex(L{i, 1}), 'EdgeColor', 'none');
        x = 0.066;
    end
    txt(ax, x, y, L{i, 2}, 6.5);
    y = y - 0.0125;
end
end


function pg = listPages(out, recs, Rs, check, det, pg)
ORANGE = hex('#e65100'); GREY = [0.33 0.33 0.33];
L = {'Check the analysis (red)', 'h', 0};
if isempty(check), L(end+1, :) = {'no channel to check', 'n', 0}; end
for i = check(:)'
    L(end+1, :) = {shortName(recs(i).name, 110), 'b', i}; %#ok<AGROW>
    R = Rs{i};
    for r = find(strcmp(R.level, 'check'))'
        s = sprintf('ch %d%s: %s', R.channel(r), labelOf(R, r), R.red{r});
        if ~isempty(R.yellow{r}), s = sprintf('%s   (%s)', s, R.yellow{r}); end
        L(end+1, :) = {s, 'n', 0}; %#ok<AGROW>
    end
    for m = 1:numel(recs(i).notes)
        w = wrapText(recs(i).notes{m}, 140);
        for j = 1:min(3, numel(w)), L(end+1, :) = {w{j}, 'o', 0}; end %#ok<AGROW>
    end
end
L(end+1, :) = {'', 'n', 0};
L(end+1, :) = {'Slice quality (yellow)', 'h', 0};
nQ = 0;
for i = 1:numel(recs)
    R = Rs{i};
    q = find(strcmp(R.level, 'quality'));
    if isempty(q), continue; end
    nQ = nQ + numel(q);
    parts = arrayfun(@(r) sprintf('ch %d%s: %s', R.channel(r), labelOf(R, r), R.yellow{r}), q, 'UniformOutput', false);
    w = wrapText([shortName(recs(i).name, 80) ' - ' strjoin(parts', '; ')], 150);
    for j = 1:numel(w), L(end+1, :) = {w{j}, 's', 0}; end %#ok<AGROW>
end
if ~nQ, L(end+1, :) = {'none', 'n', 0}; end
perPage = 78;
nP = ceil(size(L, 1) / perPage);
first = pg + nP + 1;
for p = 1:nP
    [fig, ax] = newPage();
    y = 0.965;
    for i = (p - 1) * perPage + 1:min(size(L, 1), p * perPage)
        [s, sty, ri] = L{i, :};
        switch sty
            case 'h', txt(ax, 0.05, y, s, 11, 'FontWeight', 'bold'); y = y - 0.016; continue;
            case 'b', txt(ax, 0.05, y, s, 7.5, 'FontWeight', 'bold');
            case 'n', txt(ax, 0.07, y, s, 6.8);
            case 'o', txt(ax, 0.07, y, s, 6.5, 'Color', ORANGE);
            case 's', txt(ax, 0.05, y, s, 6.3);
        end
        k = find(det == ri, 1);
        if ri > 0 && ~isempty(k)
            txt(ax, 0.95, y, sprintf('page %d', first + k - 1), 6.5, 'Color', GREY, 'HorizontalAlignment', 'right');
        end
        y = y - 0.0118;
    end
    savePage(fig, out);
    pg = pg + 1;
end
end


function detailPage(out, rec, R)
GREEN = hex('#2e7d32'); ORANGE = hex('#e65100'); BLUE = hex('#1565c0'); RED = hex('#c62828'); GREY = [0.33 0.33 0.33];
rows = find(strcmp(R.level, 'check'));
rows = rows(1:min(4, numel(rows)));
[fig, ax] = newPage();
txt(ax, 0.05, 0.965, shortName(rec.name, 100), 10, 'FontWeight', 'bold');
txt(ax, 0.05, 0.951, ['o stimulated (green) / extra beat (orange), x uncertain; dashed: pulse (blue) / pulse ' ...
    'without contraction (red); dotted: extra pulse'], 6.5, 'Color', GREY);
top = 0.935; bottom = 0.22; h = (top - bottom) / 4;
H = [];
try
    H = mda_readMdd(rec.file);
catch ME
    txt(ax, 0.05, 0.9, ['recording not read: ' ME.message], 8, 'Color', RED);
end
C = []; if isfield(rec, 'C'), C = rec.C; end
P = []; if isfield(rec, 'P'), P = rec.P; end
if isempty(P) && isfield(rec, 'P_file') && ~isempty(rec.P_file), P = readPulses(rec.P_file); end
opts = mda_options();
for k = 1:numel(rows)
    r = rows(k); a = R.window_from(r); b = R.window_to(r); c = R.channel(r);
    tt = sprintf('channel %d%s: %s', c, labelOf(R, r), ...
        strjoin(R{r, {'red', 'yellow'}}(~cellfun(@isempty, R{r, {'red', 'yellow'}})), '; '));
    axk = axes(fig, 'Position', [0.09, top - k * h + 0.045, 0.86, h - 0.075], 'FontSize', 6, 'Box', 'on');
    hold(axk, 'on');
    title(axk, tt, 'FontSize', 8, 'FontWeight', 'normal', 'HorizontalAlignment', 'left', 'Units', 'normalized', ...
        'Position', [0 1.02 0], 'Interpreter', 'none');
    xlabel(axk, 'time in the recording (s)', 'FontSize', 6); ylabel(axk, ['force (' char(181) 'N)'], 'FontSize', 6);
    xlim(axk, [a b]);
    if isempty(H), continue; end
    try
        D = mda_readMdd(H, a, b, opts);
        i = find(D.dataChannels == c, 1);
        t = D.t(:); y = double(D.force(i, :))';
    catch ME
        text(axk, 0.5, 0.5, ['not read: ' ME.message], 'Units', 'normalized', 'HorizontalAlignment', 'center', ...
            'FontSize', 7, 'Color', RED, 'Interpreter', 'none');
        continue;
    end
    plot(axk, t, y, 'Color', hex('#37474f'), 'LineWidth', 0.5);
    yl = [min(y) max(y)]; if diff(yl) <= 0, yl = yl + [-1 1]; end
    yl = yl + [-0.05 0.08] * diff(yl);
    if ~isempty(P) && height(P) > 0 && all(ismember({'channel', 't'}, P.Properties.VariableNames))
        q = P(double(P.channel) == c & P.t >= a & P.t <= b, :);
        for j = 1:height(q)
            col = BLUE; ls = '--';
            if ismember('outcome', q.Properties.VariableNames) && strcmp(char(string(q.outcome(j))), 'noResponse'), col = RED; end
            if ismember('extra', q.Properties.VariableNames) && truthy(q.extra(j)), ls = ':'; end
            plot(axk, [q.t(j) q.t(j)], yl, ls, 'Color', col, 'LineWidth', 0.6);
        end
    end
    if ~isempty(C) && height(C) > 0 && ismember('t_peak', C.Properties.VariableNames)
        q = C(double(C.channel) == c & C.t_peak >= a & C.t_peak <= b, :);
        for j = 1:height(q)
            tp = q.t_peak(j);
            col = ORANGE;
            if ismember('beatType', q.Properties.VariableNames) && strcmp(char(string(q.beatType(j))), 'stimulated'), col = GREEN; end
            mk = 'o';
            if ismember('uncertain', q.Properties.VariableNames) && truthy(q.uncertain(j)), mk = 'x'; end
            plot(axk, tp, interp1(t, y, tp, 'linear', 'extrap'), mk, 'Color', col, 'MarkerSize', 4);
        end
    end
    ylim(axk, yl);
end
yy = 0.19;
txt(ax, 0.05, yy, 'Open in the GUI (MATLAB; Python: mda-gui "<file>" --channel <c> --window <from> <to>):', 7, ...
    'FontWeight', 'bold');
yy = yy - 0.014;
w = wrapText(sprintf('f = ''%s'';', strrep(rec.open, '''', '''''')), 130);
for j = 1:numel(w), txt(ax, 0.05, yy, w{j}, 6, 'FontName', 'FixedWidth'); yy = yy - 0.012; end
for k = 1:numel(rows)
    r = rows(k);
    txt(ax, 0.05, yy, sprintf('MyoDishAnalysisGUI(f, ''channel'', %d, ''window'', [%g %g])', R.channel(r), ...
        R.window_from(r), R.window_to(r)), 6, 'FontName', 'FixedWidth');
    yy = yy - 0.012;
end
for m = 1:numel(rec.notes)
    yy = yy - 0.004;
    s = rec.notes{m}; if numel(s) > 150, s = [s(1:149) char(8230)]; end
    txt(ax, 0.05, yy, s, 6.5, 'Color', ORANGE);
    yy = yy - 0.012;
end
uistack(ax, 'bottom');
savePage(fig, out);
end


function P = readPulses(f)
% pulse table f or f.gz (columns channel, t, extra, outcome; [] if missing), read only for the detail pages
P = []; src = f; tmp = '';
if ~isfile(f)
    if ~isfile([f '.gz']), return; end
    tmp = tempname; mkdir(tmp);                        %readtable does not read .gz
    gunzip([f '.gz'], tmp);
    [~, n, e] = fileparts(f);
    src = fullfile(tmp, [n e]);
end
try
    o = detectImportOptions(src, 'FileType', 'text', 'Delimiter', ',');
    o.SelectedVariableNames = intersect({'channel', 't', 'extra', 'outcome'}, o.VariableNames, 'stable');
    if ismember('outcome', o.SelectedVariableNames), o = setvartype(o, 'outcome', 'char'); end
    P = readtable(src, o);
catch
    P = [];
end
if ~isempty(tmp), rmdir(tmp, 's'); end
end


function c = hex(s)
c = sscanf(s(2:end), '%2x%2x%2x', [1 3]) / 255;
end


function w = wrapText(s, n)
% lines of at most n characters, broken at spaces (as Python textwrap.wrap)
s = strtrim(regexprep(char(s), '\s+', ' '));
w = {};
while numel(s) > n
    k = find(s(1:n+1) == ' ', 1, 'last');
    if isempty(k) || k == 1, k = n + 1; w{end+1} = s(1:n); else, w{end+1} = s(1:k-1); end %#ok<AGROW>
    s = strtrim(s(k:end));
end
if ~isempty(s), w{end+1} = s; end
end
