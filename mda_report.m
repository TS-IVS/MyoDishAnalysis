function varargout = mda_report(varargin)
%MDA_REPORT  Analysis report (PDF): which analyses should be checked, with traces and the commands to open them in the
%GUI. Same flags and pages as the Python version (report.py).
%
%   R = mda_report(recs, pdfFile, 'title', t, 'subtitle', {...}, 'flags', fl, 'maxPages', 8, 'windowSeconds', 20,
%                  'notice', {...}, 'image', png)   notice: lines in red at the top of the first page (watcher:
%                                       recordings analysed with another version or other options); image: PNG on the
%                                       first page (overview image of an experiment)
%   R = mda_report('analysis', pdfFile, mddFile, C, S, info, resultsFile, fl)   report of one analysis (MyoDishAnalysis,
%                                       GUI); the GUI commands open resultsFile (or the recording if it is empty)
%   R = mda_report('flags', S, C, status, fl)   flags per channel (table), no PDF
%   f = mda_report('path', outputFile, report)  file of the report of an analysis: report [] / true / 'on' ->
%                                       <outputFile without extension>_report.pdf ('' without outputFile), false /
%                                       'off' -> '', a file name -> this file
%   fl = mda_report('defaults')         default flags (struct)
%   [from, to] = mda_report('window', C, channel, codes, width)
%   [m, p] = mda_report('commands', file, channel, from, to)   MATLAB and Python commands that open the GUI there
%   f = mda_report('trend', pngFile, D)  trend image of one channel (watcher, slice register; 2026-10-14): one panel
%                                       per parameter, see trendImage below; '' if there is nothing to show
%   [T, C] = mda_report('trendData', D)  its data: one row per window (t_from, nBeats, parameters, bin_from of the
%                                       line) and the comments shown (number, t, text)
%   f = mda_report('course', pngFile, D)  course image of one channel of a series (slice register, 2026-10-15): per
%                                       parameter the whole time course (left) and the last 24 h (right), see
%                                       courseImage below
%   [Tc, Tl, Tm] = mda_report('courseData', D)  its data: bins of the whole course (per slice), windows of the last
%                                       24 h, comments shown
%   f = mda_report('experiment', pngFile, D)  overview image of an experiment (2026-10-15): series x channels with
%                                       the amplitude over the whole time course, status, red flags
%
% Written by MyoDishAnalysisWatch per experiment after every pass with analysed recordings of the experiment
% (<experiment>/<experiment>_report.pdf: all its recordings, the new ones (recs(i).new) in bold with detail pages, first
% page 'image' = overview image; 2026-10-15; option 'report'), by MyoDishAnalysis with an output file (<output>_report.pdf, option
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
%     F  stimulus frequency > stimFrequency (10 Hz) in a range (median stimulus interval; 2026-10-13): pulse pairs or
%        groups (e.g. CCM pulses without the extra-pulse bit), bursts, pulses over consecutive samples or a misread
%        status channel; the contractions are analysed as usual (check the stimulation)
%   slice quality (yellow: possibly poor biological quality, e.g. also an effect of a treatment; the user decides):
%     C  capture < capture (90) % of the stimuli
%     X  extra beats > extra (10) % of the detected contractions (spontaneous activity; not shown with N)
%     A  median amplitude of the included contractions < amplitude (75 uN)
%     T  amplitude change > amplitudeChange (30) % from the first to the last range with >= 10 included contractions
%        (shown with the time between the start of the first and the end of the last of these ranges, e.g. 'amplitude
%        change +660 % over 24 h')
%     V  median amplitude CV of the ranges > amplitudeCV (30) %
% Arrhythmic pacing (summary column arrhythmicPacing: option arrhythmicChannels or detected, see mda_options;
% 2026-10-13): capture and amplitude CV are not flagged (C, V) and the missed beats do not count in the noise index (N:
% extra beats only); missed beats, uncertain contractions and a variable amplitude are expected. The capture is still
% shown (overview: '~' after it).
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
% TS 2026-10-11 (noise index N, large extra beats S, extra beats as slice quality 2026-10-12; arrhythmic pacing, F
% 2026-10-13; trend images 2026-10-14; course and experiment images, reports per experiment 2026-10-15)

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
        case 'trend'
            varargout{1} = trendImage(char(varargin{2}), varargin{3});
        case 'trenddata'
            [varargout{1}, varargout{2}] = trendData(varargin{2});
        case 'course'
            varargout{1} = courseImage(char(varargin{2}), varargin{3});
        case 'coursedata'
            [varargout{1}, varargout{2}, varargout{3}] = courseData(varargin{2});
        case 'experiment'
            varargout{1} = experimentImage(char(varargin{2}), varargin{3});
        otherwise
            error('mda_report: unknown mode ''%s''', char(varargin{1}));
    end
    return;
end
recs = varargin{1}; out = char(varargin{2});
p = struct('title', 'MyoDishAnalysis report', 'subtitle', {{}}, 'flags', [], 'maxpages', 8, 'windowseconds', 20, ...
    'notice', {{}}, 'image', '');
for i = 3:2:numel(varargin)
    k = lower(char(varargin{i}));
    if ~isfield(p, k), error('mda_report: unknown option ''%s''', varargin{i}); end
    p.(k) = varargin{i+1};
end
varargout{1} = writeReport(recs, out, p.title, cellstr(p.subtitle), flagsOf(p.flags), p.maxpages, p.windowseconds, ...
    cellstr(p.notice), char(p.image));
end


% =====================================================================================================
function fl = defaults()
fl = struct('uncertain', 25, 'irregular', 15, 'artifactShare', 5, 'artifactRatio', 3, 'extra', 10, 'capture', 90, ...
    'amplitudeChange', 30, 'amplitude', 75, 'amplitudeCV', 30, 'delay', 0.15, 'minBeats', 50, 'stimFrequency', 10);
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
    false(n, 1), nan(n, 1), repmat({''}, n, 1), repmat({''}, n, 1), repmat({''}, n, 1), repmat({''}, n, 1), ...
    'VariableNames', {'channel', 'label', 'status', 'nDetected', 'capture_percent', 'extra_percent', ...
    'uncertain_percent', 'extraMissed_percent', 'noiseIndex', 'largeExtra_percent', 'largeExtra_ratio', ...
    'amplitude_uN', 'amplitudeChange_percent', 'amplitudeChange_hours', 'amplitudeCV_percent', 'delay_ms', ...
    'invertedSignal', 'arrhythmicPacing', 'stimFrequency_Hz', 'flags', 'level', 'red', 'yellow'});
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
    if ~isempty(s) && height(s) > 0 && ismember('arrhythmicPacing', s.Properties.VariableNames)
        R.arrhythmicPacing(k) = any(truthy(s.arrhythmicPacing));
    end
    if ~isempty(s) && ismember('stimFrequency', s.Properties.VariableNames) && any(~isnan(double(s.stimFrequency)))
        R.stimFrequency_Hz(k) = max(double(s.stimFrequency), [], 'omitnan');
    end
    arr = R.arrhythmicPacing(k);
    if nDet > 0                 %noise index: uncertain contractions in a channel that does not follow the pacing
        if nStim > 0            %arrhythmic pacing: missed beats expected, not counted (2026-10-13)
            R.extraMissed_percent(k) = R.extra_percent(k) + (~arr) * (100 - R.capture_percent(k));
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
            share = 100 * nInv / nDet;
            if nInv >= nDet, red{end+1} = 'inverted signal'; %#ok<AGROW>
            elseif share < 1, red{end+1} = 'inverted signal (< 1 % of the contractions)'; %#ok<AGROW>
            else, red{end+1} = sprintf('inverted signal (%.0f %% of the contractions)', share); %#ok<AGROW>
            end
            codes(end+1) = 'I'; %#ok<AGROW>
        end
        noise = R.uncertain_percent(k) >= fl.uncertain && (nStim <= 0 || R.extraMissed_percent(k) >= fl.irregular);
        if noise
            if nStim > 0 && arr
                red{end+1} = sprintf('noise index %.0f (uncertain %.0f %%, extra %.0f %%, arrhythmic pacing)', ...
                    R.noiseIndex(k), R.uncertain_percent(k), R.extra_percent(k)); %#ok<AGROW>
            elseif nStim > 0
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
        if R.stimFrequency_Hz(k) > fl.stimFrequency
            red{end+1} = sprintf('stimulus frequency %.0f Hz', R.stimFrequency_Hz(k)); codes(end+1) = 'F'; %#ok<AGROW>
        end
        if R.capture_percent(k) < fl.capture && ~arr
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
        if R.amplitudeCV_percent(k) > fl.amplitudeCV && ~arr
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
R = writeReport(rec, out, 'MyoDishAnalysis report', sub, flagsOf(fl), 8, 20, {}, '');
end


% ===================================================================================================== PDF
function Rall = writeReport(recs, out, title, subtitle, fl, maxPages, winS, notice, png)
% recs(i).new (optional, 2026-10-15; experiment reports of the watcher): recordings of the last pass, marked '(new)';
% detail pages only for them (the others: flags R and windows of mda_flags.csv, no contractions). png: image shown on
% the first page (experiment overview)
nR = numel(recs);
Rs = cell(nR, 1);
hasNew = isfield(recs, 'new');
for i = 1:nR
    rec = recs(i);
    st = []; if isfield(rec, 'status'), st = rec.status; end
    C = []; if isfield(rec, 'C'), C = rec.C; end
    if isfield(rec, 'R') && ~isempty(rec.R), R = rec.R;   %flags computed by the caller (watcher)
    else, R = reportFlags(rec.S, C, st, fl); end
    if ~ismember('noiseIndex', R.Properties.VariableNames), R.noiseIndex = nan(height(R), 1); end
    if ~ismember('arrhythmicPacing', R.Properties.VariableNames), R.arrhythmicPacing = false(height(R), 1); end
    R = addvars(R, repmat({rec.name}, height(R), 1), 'Before', 1, 'NewVariableNames', 'recording');
    if ~ismember('window_from', R.Properties.VariableNames)
        R.window_from = nan(height(R), 1); R.window_to = nan(height(R), 1);
    end
    R.matlab = repmat({''}, height(R), 1); R.python = repmat({''}, height(R), 1);
    opn = '';
    if isfield(rec, 'open'), opn = rec.open; end
    if isempty(opn), opn = rec.file; end
    for j = find(strcmp(R.level, 'check'))'
        if ~isfinite(R.window_from(j)) || ~isempty(C)  %windows of mda_flags.csv kept (no contractions)
            [R.window_from(j), R.window_to(j)] = reportWindow(C, R.channel(j), R.flags{j}, winS);
        end
        [R.matlab{j}, R.python{j}] = guiCommands(opn, R.channel(j), R.window_from(j), R.window_to(j));
    end
    recs(i).open = opn;
    if ~isfield(rec, 'notes') || isempty(rec.notes), recs(i).notes = {}; else, recs(i).notes = cellstr(rec.notes); end
    Rs{i} = R;
end
if nR, Rall = vertcat(Rs{:}); else, Rall = reportFlags([], [], [], fl); end
isCheck = cellfun(@(R) any(strcmp(R.level, 'check')), Rs);
nRed = cellfun(@(R) sum(cellfun(@(x) sum(ismember(x, 'INSDF')), R.flags(strcmp(R.level, 'check')))), Rs);
maxNI = cellfun(@(R) max([0; R.noiseIndex(strcmp(R.level, 'check') & ~isnan(R.noiseIndex))]), Rs);
check = find(isCheck | arrayfun(@(r) ~isempty(r.notes), recs(:)));
det = find(isCheck);
if hasNew, det = det(arrayfun(@(r) isequal(r.new, true), recs(det))); end
[~, o] = sortrows([-nRed(det(:)), -maxNI(det(:))]);
det = det(o);                                       %stable: the most red flags, the highest noise index first
det = det(1:min(maxPages, numel(det)));
d = fileparts(out);
if ~isempty(d) && ~exist(d, 'dir'), mkdir(d); end
if exist(out, 'file'), delete(out); end
pg = 0;
if ~isempty(png) && isfile(png), pg = imagePage(out, png, title, subtitle, notice); end
pg = overviewPages(out, recs, Rs, title, subtitle, fl, numel(det), notice, pg);
listPages(out, recs, Rs, check, det, pg);
for k = 1:numel(det)
    detailPage(out, recs(det(k)), Rs{det(k)});
end
end


function [fig, ax] = newPage(P)
% A4 page (P = [width height] in cm, default portrait)
if nargin < 1, P = [21 29.7]; end
fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [1 1 P], 'Color', 'w', ...
    'PaperUnits', 'centimeters', 'PaperSize', P, 'PaperPosition', [0 0 P]);
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


function pg = imagePage(out, png, title, subtitle, notice)
% first page of an experiment report (2026-10-15): title, subtitle, notice and the overview image of the experiment
RED = [0.776 0.157 0.157]; GREY = [0.33 0.33 0.33];
I = imread(png);
P = [21 29.7];                                         %page (cm): landscape for a wide image
if size(I, 2) > 1.2 * size(I, 1), P = [29.7 21]; end
[fig, ax] = newPage(P);
dy = 29.7 / P(2);                                      %line spacing as on a portrait page
txt(ax, 0.05, 1 - 0.035 * dy, title, 14, 'FontWeight', 'bold');
y = 1 - 0.052 * dy;
for i = 1:numel(subtitle)
    w = wrapText(subtitle{i}, 150 * P(1) / 21);
    for j = 1:min(2, numel(w)), txt(ax, 0.05, y, w{j}, 6.5, 'Color', GREY); y = y - 0.011 * dy; end
end
for i = 1:numel(notice)
    w = wrapText(notice{i}, 135 * P(1) / 21);
    if i == 1, fw = 'bold'; else, fw = 'normal'; end
    for j = 1:min(3, numel(w)), txt(ax, 0.05, y, w{j}, 7, 'Color', RED, 'FontWeight', fw); y = y - 0.012 * dy; end
end
r = size(I, 1) / size(I, 2) * P(1) / P(2);              %height per width (page units)
h = 0.9 * r;                                           %at 90 % of the width
top = y - 0.01;
if h > top - 0.04, h = top - 0.04; end
wd = h / r;
axI = axes(fig, 'Position', [(1 - wd) / 2, top - h, wd, h]);
image(axI, I);
axis(axI, 'off');
savePage(fig, out);
pg = 1;
end


function pg = overviewPages(out, recs, Rs, title, subtitle, fl, nDetail, notice, pg)
RED = [0.776 0.157 0.157]; GREY = [0.33 0.33 0.33];
pg0 = pg;
isNew = false(1, numel(recs));
if isfield(recs, 'new'), isNew = arrayfun(@(r) isequal(r.new, true), recs); end
nRed = sum(cellfun(@(R) sum(strcmp(R.level, 'check')), Rs));
nYel = sum(cellfun(@(R) sum(strcmp(R.level, 'quality')), Rs));
nSl = sum(cellfun(@(R) sum(~strcmp(R.status, 'no slice')), Rs));
chans = unique(cell2mat(cellfun(@(R) double(R.channel(:)), Rs(:), 'UniformOutput', false)))';
if isempty(chans), chans = 1:8; end
perPage = 48;
nP = max(1, ceil(numel(recs) / perPage));
for p = 1:nP
    [fig, ax] = newPage();
    t = title; if nP > 1, t = sprintf('%s (overview %d/%d)', title, p, nP); end
    txt(ax, 0.05, 0.965, t, 14, 'FontWeight', 'bold');
    y = 0.948;
    for i = 1:numel(subtitle)
        w = wrapText(subtitle{i}, 150);
        for j = 1:min(2, numel(w)), txt(ax, 0.05, y, w{j}, 6.5, 'Color', GREY); y = y - 0.011; end
    end
    if p == 1 && pg0 == 0 && ~isempty(notice)         %e.g. recordings analysed with another version (watcher)
        y = y - 0.003;
        for i = 1:numel(notice)
            w = wrapText(notice{i}, 135);
            if i == 1, fw = 'bold'; else, fw = 'normal'; end
            for j = 1:min(3, numel(w)), txt(ax, 0.05, y, w{j}, 7, 'Color', RED, 'FontWeight', fw); y = y - 0.012; end
        end
    end
    s = sprintf('%d recording(s), %d channel(s) with a slice: %d to check (red', numel(recs), nSl, nRed);
    if any(isNew), s = sprintf('%d recording(s) (%d new = bold), %d channel(s) with a slice: %d to check (red', ...
            numel(recs), sum(isNew), nSl, nRed); end
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
        if isNew(idx(k)), fwt = 'bold'; else, fwt = 'normal'; end
        text(ax, X(0), Y(yk - rh * 0.2), shortName(rec.name, 62), 'FontSize', 6, 'Interpreter', 'none', ...
            'VerticalAlignment', 'top', 'FontWeight', fwt);
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
                    tl = ''; if R.arrhythmicPacing(r), tl = '~'; end
                    if ~isnan(R.capture_percent(r)), s = strtrim(sprintf('%.0f%s %s', R.capture_percent(r), tl, s)); end
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
L = {'', ['Each cell: capture (% of the stimuli followed by a contraction; ~ arrhythmic pacing, C and V not ' ...
        'flagged) and the letters of the flags. White: no flag; empty: no slice.']
    '#f8c9c4', sprintf(['Red = check the analysis:  I inverted signal,  N noise (uncertain %s %g %%, ' ...
        'extra+missed %s %g %%),  S large extra beats (> %g x paced),  D delay > %g ms,  F pacing > %g Hz'], ...
        char(8805), fl.uncertain, char(8805), fl.irregular, fl.artifactRatio, 1000 * fl.delay, fl.stimFrequency)
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
    nm = shortName(recs(i).name, 110);
    if isfield(recs, 'new') && isequal(recs(i).new, true), nm = [nm '  (new)']; end
    L(end+1, :) = {nm, 'b', i}; %#ok<AGROW>
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


% ===================================================================================================== trend images
function out = trendImage(out, D)
% trend image (PNG, 150 dpi; 2026-10-14) of one channel: one panel per parameter with the values per window of the
% overview (dots: included contractions; several rows of a window, e.g. beat types or rocker states, weighted by their
% number of contractions) and their median per bin (line: 5 min up to 3 h shown, 10 min up to 30 h, 30 min up to 7
% days, 2 h beyond), stimulation protocols (light blue, name), periods without signal (grey), comments (purple,
% numbered, list below; during a protocol only those at its start or end).
% D: title, subtitle (char or cellstr: lines), t (window start, s after t0), w (window length, s), nb (contractions), inc (included),
% V (values, one column per parameter), names, units (cellstr), t0 (datenum of t = 0; NaN: time in hours), xlim ([from
% to] s; optional), bands (rows from, to (s), kind: 1 = protocol, 2 = no signal), bandLabels (cellstr), com (struct
% with t (s), text, category; comments of this channel and of all channels)
K = trendColors(); PURPLE = K.purple; INK = K.ink;
p = numel(D.names);
R = trendPrep(D);
if isempty(R), out = ''; return; end
Y = R.Y; th = R.th; xl = R.xl; span = R.span; bm = R.bm; clock = R.clock; B = R.B; bl = R.bl; cm = R.cm;
nCm = numel(cm); nList = min(nCm, 60); listRows = ceil(nList / 3) + (nCm > nList);
% layout (inches)
fw = 11; hT = 0.78; hS = 0.26; hP = 1.3; hG = 0.1; hX = 0.5; hL = (listRows > 0) * (0.12 + 0.15 * listRows);
fh = hT + hS + p * hP + (p - 1) * hG + hX + hL;
fig = figure('Visible', 'off', 'Units', 'inches', 'Position', [0 0 fw fh], 'Color', 'w', 'PaperPositionMode', 'auto');
cleanup = onCleanup(@() close(fig));
L = 0.085; Wd = 0.885;
annotation(fig, 'textbox', [0.01 1 - 0.36 / fh 0.98 0.3 / fh], 'String', D.title, 'Interpreter', 'none', ...
    'FontSize', 11, 'FontWeight', 'bold', 'EdgeColor', 'none', 'Color', INK, 'VerticalAlignment', 'middle', ...
    'Margin', 0);
annotation(fig, 'textbox', [0.01 1 - 0.72 / fh 0.98 0.4 / fh], 'String', cellstr(D.subtitle), 'Interpreter', ...
    'none', 'FontSize', 7.5, 'EdgeColor', 'none', 'Color', [0.35 0.35 0.35], 'VerticalAlignment', 'middle', ...
    'Margin', 0);
[tk, tkl] = trendTicks(xl, clock, D);
yTop = fh - hT - hS;
axS = axes(fig, 'Position', [L yTop / fh Wd hS / fh], 'XLim', xl, 'YLim', [0 1], 'Visible', 'off');
hold(axS, 'on');
ax = gobjects(p, 1);
for i = 1:p
    b = yTop - i * hP - (i - 1) * hG;
    ax(i) = axes(fig, 'Position', [L b / fh Wd hP / fh], 'FontSize', 8, 'Box', 'on', 'TickDir', 'in', ...
        'TickLength', [0.005 0.005], ...
        'XLim', xl, 'XTick', tk, 'XTickLabel', {}, 'Layer', 'top', 'XGrid', 'on', 'YGrid', 'on', ...
        'GridAlpha', 0.12, 'Color', 'w', 'XColor', [0.3 0.3 0.3], 'YColor', [0.3 0.3 0.3]);
    hold(ax(i), 'on');
    [y, nm, un] = trendUnits(Y(:, i), D.names{i}, D.units{i});
    [xb, yb] = binLine(th, y, bm, []);                 %line: median per bin of bm minutes
    yl = trendPanel(ax(i), th, y, xb, yb, B, bl, [cm.t], xl, span, 0.0048 * (i == 1), 7);
    ylabel(ax(i), {nm, ['(' un ')']}, 'FontSize', 8, 'Interpreter', 'none');
    text(ax(i), xl(2) - 0.004 * span, yl(2) - 0.02 * diff(yl), trendNote(th, y, un), 'FontSize', 7, 'Color', ...
        [0.3 0.3 0.3], 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', 'Interpreter', 'none', ...
        'BackgroundColor', [1 1 1], 'Margin', 1);
end
set(ax(end), 'XTickLabel', tkl);
if clock
    xlabel(ax(end), 'clock time', 'FontSize', 8);
else
    xlabel(ax(end), 'time in the recording (h)', 'FontSize', 8);
end
% comment numbers above the panels (two rows; moved to the right where they would overlap)
last = -inf(1, 2);
for k = 1:nCm
    x = cm(k).t / 3600;
    dmin = 0.006 * span * (numel(sprintf('%d', k)) + 1);
    r = find(x - last >= dmin, 1);
    if isempty(r), [~, r] = min(last); end
    x = max(x, last(r) + dmin);
    last(r) = x;
    text(axS, x, 0.28 + 0.42 * (r - 1), sprintf('%d', k), 'FontSize', 7, 'Color', PURPLE, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'baseline', 'Clipping', 'off');
end
% list of the comments
if listRows > 0
    axL = axes(fig, 'Position', [0.02 0 0.96 hL / fh], 'XLim', [0 3], 'YLim', [0 1], 'Visible', 'off');
    nr = ceil(nList / 3);
    for k = 1:nList
        col = floor((k - 1) / nr); row = mod(k - 1, nr);
        y = 1 - (0.08 + row * 0.15) / hL;
        s = cm(k).text; if numel(s) > 52, s = [s(1:51) char(8230)]; end
        text(axL, col + 0.005, y, sprintf('%d', k), 'FontSize', 7, 'Color', PURPLE, 'FontWeight', 'bold', ...
            'VerticalAlignment', 'top', 'Interpreter', 'none');
        text(axL, col + 0.06, y, [trendTime(cm(k).t, clock, D, span) '  ' s], 'FontSize', 7, 'Color', INK, ...
            'VerticalAlignment', 'top', 'Interpreter', 'none');
    end
    if nCm > nList
        text(axL, 0.005, 1 - (0.08 + nr * 0.15) / hL, sprintf('%s and %d more comments (events of the recording)', ...
            char(8230), nCm - nList), 'FontSize', 7, 'Color', [0.35 0.35 0.35], 'VerticalAlignment', 'top');
    end
end
savePng(fig, out);
end


function K = trendColors()
% colours of the trend, course and experiment images
K = struct('blue', [0.114 0.447 0.725], 'dot', [0.64 0.72 0.84], 'purple', [0.55 0.24 0.66], 'ink', ...
    [0.13 0.13 0.13], 'prot', [0.87 0.93 1], 'gap', [0.89 0.89 0.89], 'last24', [1 0.96 0.78], 'red', ...
    [0.776 0.157 0.157], 'slice', [0.3 0.3 0.3], 'grey', [0.35 0.35 0.35]);
end


function [xb, yb] = binLine(th, y, bm, grp)
% line of a trend panel: median of y per bin of bm minutes (th: hours), x = centre of the bin (h); NaN between bins
% that are not adjacent and between the groups grp (e.g. slices; [] = one group)
xb = zeros(0, 1); yb = zeros(0, 1);
th = th(:); y = y(:);
if isempty(grp), grp = ones(size(th)); end
grp = grp(:);
ok = ~isnan(y);
for g = unique(grp(ok))'
    s = ok & grp == g;
    [ub, ~, gb] = unique(floor(th(s) * 60 / bm));
    med = accumarray(gb, y(s), [], @median);
    idx = (1:numel(ub))' + [0; cumsum(diff(ub(:)) > 1)];      %NaN between bins that are not adjacent
    x = nan(idx(end), 1); v = x;
    x(idx) = (ub + 0.5) * bm / 60; v(idx) = med;
    if ~isempty(xb), xb(end+1, 1) = NaN; yb(end+1, 1) = NaN; end %#ok<AGROW>
    xb = [xb; x]; yb = [yb; v]; %#ok<AGROW>
end
end


function yl = trendPanel(ax, th, y, xb, yb, B, bl, tc, xl, span, nameWidth, ms)
% one panel of a trend / course image: bands (B rows from, to (s), kind 1 = protocol (light blue; with its name bl if
% nameWidth > 0 = width of a character as part of the span), 2 = no signal (grey)), comment lines at tc (s), dots
% (median per window, size ms), line (xb, yb; a point for bins without neighbours); y limits from the 1st and 99th
% percentile of the values; returns the y limits
K = trendColors();
v = [y(:); yb(:)]; v = sort(v(~isnan(v)));
if isempty(v)
    yl = [0 1];
else
    lo = v(max(1, round(0.01 * numel(v)))); hi = v(max(1, round(0.99 * numel(v))));
    if hi <= lo, hi = lo + max(1, abs(lo)) * 0.1; lo = lo - max(1, abs(lo)) * 0.1; end
    yl = [lo hi] + [-0.08 0.12] * (hi - lo);
end
for k = 1:size(B, 1)
    if B(k, 3) == 1, col = K.prot; else, col = K.gap; end
    patch(ax, B(k, [1 2 2 1]) / 3600, yl([1 1 2 2]), col, 'EdgeColor', 'none', 'HitTest', 'off');
    if nameWidth > 0 && B(k, 3) == 1 && k <= numel(bl)   %name, shortened to the width of the band
        nch = floor((min(B(k, 2) / 3600, xl(2)) - max(B(k, 1) / 3600, xl(1))) / span / nameWidth);
        lb = bl{k}; if numel(lb) > nch, lb = [lb(1:max(0, nch - 1)) char(8230)]; end
        if nch >= 4
            text(ax, max(B(k, 1) / 3600, xl(1)), yl(2), [' ' lb], 'FontSize', 6.5, 'Color', ...
                [0.2 0.38 0.62], 'VerticalAlignment', 'top', 'Clipping', 'on', 'Interpreter', 'none');
        end
    end
end
for k = 1:numel(tc)
    plot(ax, tc(k) / 3600 * [1 1], yl, ':', 'Color', K.purple, 'LineWidth', 0.7);
end
plot(ax, th, y, '.', 'Color', K.dot, 'MarkerSize', ms);
plot(ax, xb, yb, '-', 'Color', K.blue, 'LineWidth', 1.3);
if ~isempty(yb)                                        %bins without neighbours: a point
    pad = [nan; yb(:); nan];
    iso = ~isnan(yb(:)) & isnan(pad(1:end-2)) & isnan(pad(3:end));
    plot(ax, xb(iso), yb(iso), 'o', 'Color', K.blue, 'MarkerFaceColor', K.blue, 'MarkerSize', 2.5);
end
set(ax, 'YLim', yl);
end


function [R, R24] = coursePrep(D)
% values of a course image (courseImage, courseData): R = the whole time course (trendPrep of all windows, D.xlim),
% R24 = the last 24 h (trendPrep of the windows in D.last24, [] if none); both with the slice of every window
% (D.slices: rows from, to (s), number)
R = trendPrep(D);
R24 = [];
if isempty(R), return; end
R.slice = sliceOfWindows(R.wins, D.slices);
a = D.last24(1); b = D.last24(2);
c = D.t(:) + D.w(1) / 2;                               %windows with their centre in the last 24 h
k = c >= a & c <= b;
if ~any(k), return; end
D24 = D;
D24.t = D.t(k); D24.nb = D.nb(k); D24.inc = D.inc(k); D24.V = D.V(k, :); D24.xlim = [a b];
R24 = trendPrep(D24);
if ~isempty(R24), R24.slice = sliceOfWindows(R24.wins, D.slices); end
end


function k = sliceOfWindows(t, S)
% number of the slice (rows from, to, number of S, in the order of time) of the windows starting at t
k = ones(numel(t), 1);
if isempty(S), return; end
i = sum(t(:) >= S(:, 1)' - 1e-6, 2);
i(i < 1) = 1;
k = reshape(S(i, 3), [], 1);
end


function [Tc, Tl, Tm] = courseData(D)
% the data of a course image (2026-10-15): Tc one row per slice and bin of the whole course (slice, bin_from (s after
% t0), nBeats = included contractions, the parameters = median of the windows of the bin, binMinutes), Tl the windows
% of the last 24 h (slice, t_from, nBeats, the parameters: median per window), Tm the comments numbered in the image
% (number, t, text). Units of D.units (as the sheet parameters).
names = cellstr(D.names(:)');
p = numel(names);
cc = matlab.lang.makeUniqueStrings([{'slice', 'bin_from', 'nBeats'}, names, {'binMinutes'}]);
cl = matlab.lang.makeUniqueStrings([{'slice', 't_from', 'nBeats'}, names]);
Tc = cell2table(cell(0, numel(cc)), 'VariableNames', cc);
Tl = cell2table(cell(0, numel(cl)), 'VariableNames', cl);
Tm = table(zeros(0, 1), zeros(0, 1), cell(0, 1), 'VariableNames', {'number', 't', 'text'});
[R, R24] = coursePrep(D);
if isempty(R), return; end
[G, ks, bs] = findgroups(R.slice, floor(R.th * 60 / R.bm));
n = numel(ks);
M = nan(n, p);
G = G(:);
for j = 1:p
    ok = ~isnan(R.Y(:, j));
    M(:, j) = accumarray(reshape(G(ok), [], 1), reshape(R.Y(ok, j), [], 1), [n 1], @median, NaN);
end
Tc = array2table([ks, bs * R.bm * 60, accumarray(G, R.nb, [n 1]), M, repmat(R.bm, n, 1)], 'VariableNames', cc);
if isempty(R24), return; end
Tl = array2table([R24.slice, R24.wins, R24.nb, R24.Y], 'VariableNames', cl);
Tm = table((1:numel(R24.cm))', reshape([R24.cm.t], [], 1), reshape({R24.cm.text}, [], 1), ...
    'VariableNames', {'number', 't', 'text'});
end


function [tk, lbl] = courseTicks(xl, D)
% ticks of the whole time course: clock time / dates; at midnight with the day in culture (D.dayBase) below
[tk, lbl] = trendTicks(xl, true, D);
if ~isfield(D, 'dayBase') || isempty(D.dayBase) || ~isfinite(D.dayBase), return; end
for k = 1:numel(tk)
    d = D.t0 + tk(k) / 24;
    if abs(d - round(d)) < 1e-6
        lbl{k} = sprintf('%s\\newline day %d', datestr(round(d), 'dd mmm'), round(d) - floor(D.dayBase));   %two lines (tex)
    end
end
end


function out = courseImage(out, D)
% course image (PNG, 150 dpi; 2026-10-15) of one channel of a series of recordings (slice register): one row per
% parameter, left the whole time course of the series (dots = values per window of the overview, line = median per bin
% of each slice: 30 min up to 7 days, 2 h beyond; slice changes dashed with 'slice k'; the last 24 h shaded yellow;
% recordings with red flags as red bars at the bottom), right the last 24 h (as the trend image of a recording: 10-min
% bins, protocols, periods without signal, numbered comments with a list below).
% D: as for trendImage (title, subtitle, t, w, nb, inc, V, names, units, t0, xlim = [0 end of the series] (s), bands,
% bandLabels, com) and slices (rows from, to (s), number), last24 ([from to] s), dayBase (datenum of day 0 of the
% culture; NaN: no day numbers), red (rows from, to (s): recordings with red flags)
K = trendColors();
[R, R24] = coursePrep(D);
if isempty(R), out = ''; return; end
p = numel(D.names);
cm = struct('t', {}, 'text', {});
if ~isempty(R24), cm = R24.cm; end
nCm = numel(cm); nList = min(nCm, 60); listRows = ceil(nList / 3) + (nCm > nList);
fw = 11; hT = 0.78; hS = 0.42; hP = 1.3; hG = 0.1; hX = 0.62; hL = (listRows > 0) * (0.12 + 0.15 * listRows);
fh = hT + hS + p * hP + (p - 1) * hG + hX + hL;
fig = figure('Visible', 'off', 'Units', 'inches', 'Position', [0 0 fw fh], 'Color', 'w', 'PaperPositionMode', 'auto');
cleanup = onCleanup(@() close(fig));
L1 = 0.075; W1 = 0.565; L2 = 0.70; W2 = 0.285;
annotation(fig, 'textbox', [0.01 1 - 0.36 / fh 0.98 0.3 / fh], 'String', D.title, 'Interpreter', 'none', ...
    'FontSize', 11, 'FontWeight', 'bold', 'EdgeColor', 'none', 'Color', K.ink, 'VerticalAlignment', 'middle', ...
    'Margin', 0);
annotation(fig, 'textbox', [0.01 1 - 0.72 / fh 0.98 0.4 / fh], 'String', cellstr(D.subtitle), 'Interpreter', ...
    'none', 'FontSize', 7.5, 'EdgeColor', 'none', 'Color', K.grey, 'VerticalAlignment', 'middle', 'Margin', 0);
xl = R.xl; span = R.span;
xl24 = D.last24(:)' / 3600;
r = @(d) round(d * 86400) / 86400;
yTop = fh - hT - hS;
axH = axes(fig, 'Position', [L1 yTop / fh W1 hS / fh], 'XLim', [0 1], 'YLim', [0 1], 'Visible', 'off');
text(axH, 0, 0.82, sprintf('whole time course: %s to %s (%.1f days)', datestr(r(D.t0 + xl(1) / 24), ...
    'dd mmm HH:MM'), datestr(r(D.t0 + xl(2) / 24), 'dd mmm HH:MM'), span / 24), 'FontSize', 8, 'FontWeight', ...
    'bold', 'Color', K.ink, 'Interpreter', 'none', 'VerticalAlignment', 'middle');
axS = axes(fig, 'Position', [L2 yTop / fh W2 hS / fh], 'XLim', xl24, 'YLim', [0 1], 'Visible', 'off');
hold(axS, 'on');
text(axS, 0, 0.82, sprintf('last 24 h (to %s)', datestr(r(D.t0 + xl24(2) / 24), 'dd mmm HH:MM')), 'Units', ...
    'normalized', 'FontSize', 8, 'FontWeight', 'bold', 'Color', K.ink, 'Interpreter', 'none', ...
    'VerticalAlignment', 'middle');
[tk, tkl] = courseTicks(xl, D);
[tk2, tkl2] = trendTicks(xl24, true, D, 5);
S = zeros(0, 3); if isfield(D, 'slices') && ~isempty(D.slices), S = D.slices; end
Rd = zeros(0, 2); if isfield(D, 'red') && ~isempty(D.red), Rd = D.red; end
props = {'FontSize', 8, 'Box', 'on', 'TickDir', 'in', 'TickLength', [0.005 0.005], 'Layer', 'top', 'XGrid', 'on', ...
    'YGrid', 'on', 'GridAlpha', 0.12, 'Color', 'w', 'XColor', [0.3 0.3 0.3], 'YColor', [0.3 0.3 0.3]};
a1 = gobjects(p, 1); a2 = gobjects(p, 1);
for i = 1:p
    b = yTop - i * hP - (i - 1) * hG;
    [y, nm, un] = trendUnits(R.Y(:, i), D.names{i}, D.units{i});
    a1(i) = axes(fig, 'Position', [L1 b / fh W1 hP / fh], props{:}, 'XLim', xl, 'XTick', tk, 'XTickLabel', {});
    hold(a1(i), 'on');
    [xb, yb] = binLine(R.th, y, R.bm, R.slice);
    yl = trendPanel(a1(i), R.th, y, xb, yb, R.B, R.bl, [], xl, span, 0, 4);
    h = patch(a1(i), xl24([1 2 2 1]), yl([1 1 2 2]), K.last24, 'EdgeColor', 'none', 'HitTest', 'off');
    uistack(h, 'bottom');
    courseMarks(a1(i), S, Rd, yl, i == 1, xl);
    ylabel(a1(i), {nm, ['(' un ')']}, 'FontSize', 8, 'Interpreter', 'none');
    text(a1(i), xl(2) - 0.004 * span, yl(2) - 0.02 * diff(yl), trendNote(R.th, y, un), 'FontSize', 7, 'Color', ...
        [0.3 0.3 0.3], 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', 'Interpreter', 'none', ...
        'BackgroundColor', [1 1 1], 'Margin', 1);
    a2(i) = axes(fig, 'Position', [L2 b / fh W2 hP / fh], props{:}, 'XLim', xl24, 'XTick', tk2, 'XTickLabel', {});
    hold(a2(i), 'on');
    if isempty(R24)
        set(a2(i), 'YTick', []);
        text(a2(i), 0.5, 0.5, 'no contractions in the last 24 h', 'Units', 'normalized', 'FontSize', 7.5, 'Color', ...
            K.grey, 'HorizontalAlignment', 'center');
        continue;
    end
    y2 = trendUnits(R24.Y(:, i), D.names{i}, D.units{i});
    [xb2, yb2] = binLine(R24.th, y2, R24.bm, R24.slice);
    yl2 = trendPanel(a2(i), R24.th, y2, xb2, yb2, R24.B, R24.bl, [cm.t], xl24, diff(xl24), ...
        0.0048 * W1 / W2 * (i == 1), 6);
    courseMarks(a2(i), S, Rd, yl2, false, xl24);
    text(a2(i), xl24(2) - 0.006 * diff(xl24), yl2(2) - 0.02 * diff(yl2), trendNote(R24.th, y2, un), 'FontSize', 6.5, ...
        'Color', [0.3 0.3 0.3], 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', 'Interpreter', 'none', ...
        'BackgroundColor', [1 1 1], 'Margin', 1);
end
set(a1(end), 'XTickLabel', tkl, 'FontSize', 7.5);
set(a2(end), 'XTickLabel', tkl2, 'XTickLabelRotation', 0);
set(a1(end), 'XTickLabelRotation', 0, 'TickLabelInterpreter', 'tex');
if isfield(D, 'dayBase') && ~isempty(D.dayBase) && isfinite(D.dayBase)
    xlabel(a1(end), 'date (day in culture)', 'FontSize', 8);
else
    xlabel(a1(end), 'date', 'FontSize', 8);
end
xlabel(a2(end), 'clock time', 'FontSize', 8);
% comment numbers above the panels of the last 24 h (three rows; moved to the right where they would overlap)
last = -inf(1, 3);
s24 = diff(xl24);
for k = 1:nCm
    x = cm(k).t / 3600;
    dmin = 0.006 * W1 / W2 * s24 * (numel(sprintf('%d', k)) + 1);
    q = find(x - last >= dmin, 1);
    if isempty(q), [~, q] = min(last); end
    x = max(x, last(q) + dmin);
    last(q) = x;
    text(axS, x, 0.04 + 0.22 * (q - 1), sprintf('%d', k), 'FontSize', 7, 'Color', K.purple, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'baseline', 'Clipping', 'off');
end
if listRows > 0                                        %list of the comments of the last 24 h
    axL = axes(fig, 'Position', [0.02 0 0.96 hL / fh], 'XLim', [0 3], 'YLim', [0 1], 'Visible', 'off');
    nr = ceil(nList / 3);
    for k = 1:nList
        col = floor((k - 1) / nr); row = mod(k - 1, nr);
        y = 1 - (0.08 + row * 0.15) / hL;
        s = cm(k).text; if numel(s) > 52, s = [s(1:51) char(8230)]; end
        text(axL, col + 0.005, y, sprintf('%d', k), 'FontSize', 7, 'Color', K.purple, 'FontWeight', 'bold', ...
            'VerticalAlignment', 'top', 'Interpreter', 'none');
        text(axL, col + 0.06, y, [trendTime(cm(k).t, true, D, 25) '  ' s], 'FontSize', 7, 'Color', K.ink, ...
            'VerticalAlignment', 'top', 'Interpreter', 'none');
    end
    if nCm > nList
        text(axL, 0.005, 1 - (0.08 + nr * 0.15) / hL, sprintf('%s and %d more comments in the last 24 h', ...
            char(8230), nCm - nList), 'FontSize', 7, 'Color', K.grey, 'VerticalAlignment', 'top');
    end
end
savePng(fig, out);
end


function courseMarks(ax, S, Rd, yl, labels, xl)
% slice changes (dashed line, 'slice k' if labels) and recordings with red flags (red bar at the bottom)
K = trendColors();
for k = 2:size(S, 1)
    x = S(k, 1) / 3600;
    if x < xl(1) || x > xl(2), continue; end
    plot(ax, [x x], yl, '--', 'Color', K.slice, 'LineWidth', 1);
    if labels
        text(ax, x, yl(1) + 0.08 * diff(yl), sprintf(' slice %d', S(k, 3)), 'FontSize', 7, 'Color', K.slice, ...
            'FontWeight', 'bold', 'VerticalAlignment', 'bottom', 'Clipping', 'on');
    end
end
for k = 1:size(Rd, 1)
    a = max(Rd(k, 1) / 3600, xl(1)); b = min(Rd(k, 2) / 3600, xl(2));
    if b <= a, continue; end
    patch(ax, [a b b a], yl(1) + [0 0 0.05 0.05] * diff(yl), K.red, 'EdgeColor', 'none', 'HitTest', 'off');
end
end


function savePng(fig, out)
d = fileparts(out);
if ~isempty(d) && ~isfolder(d), mkdir(d); end
try                                                    %the whole figure (no cropping to the content)
    exportgraphics(fig, out, 'Resolution', 150, 'BackgroundColor', 'white', 'Padding', 'figure');
catch
    print(fig, out, '-dpng', '-r150');
end
end


function out = experimentImage(out, D)
% overview image of an experiment (PNG, 150 dpi; 2026-10-15): one row per series (setup), one column per channel; per
% cell the amplitude (median per bin of the included contractions) over the whole time course of the experiment, slice
% changes (dashed), the last 24 h (yellow), background = status of the last slice at the end of its data (green
% beating, red not beating, grey removed / replaced, orange signal lost, white no slice), texts: last amplitude, change
% in the last 24 h, % of the maximum of the slice, number of the slice, recordings with red flags (red frame, number).
% D: title, subtitle (cellstr), rows (labels of the series), cols (channels), t0 (datenum of x = 0), xl ([0 end] h),
% last24 ([from to] h), report (name of the PDF report, legend), cells (struct array r, c, t (h), y (uN), sb (slice
% changes, h), status, k (number of the last slice), amp (last amplitude, uN), pct (% of the maximum), d24 (change in the
% last 24 h, %), nRed (recordings with red flags))
K = trendColors();
nr = numel(D.rows); nc = numel(D.cols);
if nr == 0 || nc == 0, out = ''; return; end
cwI = 1.3; chI = 0.88; lwI = 1.45; hT = 0.78; hH = 0.25; hB = 0.8;
fw = max(9, lwI + nc * cwI + 0.15); fh = hT + hH + nr * chI + hB;
fig = figure('Visible', 'off', 'Units', 'inches', 'Position', [0 0 fw fh], 'Color', 'w', 'PaperPositionMode', 'auto');
cleanup = onCleanup(@() close(fig));
annotation(fig, 'textbox', [0.01 1 - 0.36 / fh 0.98 0.3 / fh], 'String', D.title, 'Interpreter', 'none', ...
    'FontSize', 11, 'FontWeight', 'bold', 'EdgeColor', 'none', 'Color', K.ink, 'VerticalAlignment', 'middle', ...
    'Margin', 0);
annotation(fig, 'textbox', [0.01 1 - 0.72 / fh 0.98 0.4 / fh], 'String', cellstr(D.subtitle), 'Interpreter', ...
    'none', 'FontSize', 7.5, 'EdgeColor', 'none', 'Color', K.grey, 'VerticalAlignment', 'middle', 'Margin', 0);
axT = axes(fig, 'Position', [0 0 1 1], 'XLim', [0 fw], 'YLim', [0 fh], 'Visible', 'off');
for j = 1:nc
    text(axT, lwI + (j - 0.5) * cwI, fh - hT - hH / 2, sprintf('ch %d', D.cols(j)), 'FontSize', 8, 'FontWeight', ...
        'bold', 'HorizontalAlignment', 'center', 'Color', K.ink);
end
for i = 1:nr
    text(axT, 0.12, fh - hT - hH - (i - 0.5) * chI, D.rows{i}, 'FontSize', 8, 'FontWeight', 'bold', 'Color', ...
        K.ink, 'Interpreter', 'none');
end
mid = (ceil(D.t0 + D.xl(1) / 24):floor(D.t0 + D.xl(2) / 24))';    %midnights
xm = (mid - D.t0) * 24;
st = {'beating at end of data', 'not beating at end of data', 'removed', 'replaced (other sliceID)', 'signal lost'};
cols = {[0.89 0.96 0.9], [0.99 0.88 0.86], [0.92 0.92 0.92], [0.92 0.92 0.92], [1 0.94 0.84]};
short = {'beating', 'not beating', 'removed', 'replaced', 'signal lost'};
for i = 1:nr
    for j = 1:nc
        pos = [(lwI + (j - 1) * cwI + 0.04) / fw, (fh - hT - hH - i * chI + 0.08) / fh, (cwI - 0.08) / fw, ...
            (chI - 0.16) / fh];
        ax = axes(fig, 'Position', pos, 'XLim', D.xl, 'YLim', [0 1], 'XTick', [], 'YTick', [], 'Box', 'on', ...
            'XColor', [0.75 0.75 0.75], 'YColor', [0.75 0.75 0.75]);
        hold(ax, 'on');
        q = find([D.cells.r] == i & [D.cells.c] == j, 1);
        if isempty(q)
            text(ax, 0.5, 0.5, 'no slice', 'Units', 'normalized', 'FontSize', 6.5, 'Color', [0.6 0.6 0.6], ...
                'HorizontalAlignment', 'center');
            continue;
        end
        Cc = D.cells(q);
        m = find(strcmp(st, Cc.status), 1);
        if ~isempty(m), set(ax, 'Color', cols{m}); sl = short{m}; else, sl = Cc.status; end
        y = Cc.y(:); v = sort(y(~isnan(y)));
        top = 1;
        if ~isempty(v), top = v(max(1, round(0.99 * numel(v)))); end
        if ~(top > 0), top = 1; end
        yl = [-0.4 1.6] * top;                         %line between the texts at the top and at the bottom
        set(ax, 'YLim', yl);
        patch(ax, D.last24([1 2 2 1]), yl([1 1 2 2]), K.last24, 'EdgeColor', 'none', 'FaceAlpha', 0.8);
        for x = xm', plot(ax, [x x], yl, '-', 'Color', [0.82 0.82 0.82], 'LineWidth', 0.4); end
        for x = Cc.sb(:)', plot(ax, [x x], yl, '--', 'Color', K.slice, 'LineWidth', 0.8); end
        plot(ax, Cc.t, Cc.y, '-', 'Color', K.blue, 'LineWidth', 1);
        pad = [nan; Cc.y(:); nan];                     %bins without neighbours: a point
        iso = ~isnan(Cc.y(:)) & isnan(pad(1:end-2)) & isnan(pad(3:end));
        plot(ax, Cc.t(iso), Cc.y(iso), '.', 'Color', K.blue, 'MarkerSize', 6);
        if isfinite(Cc.amp)
            text(ax, 0.03, 0.95, [fmtSig(Cc.amp) ' ' char(181) 'N'], 'Units', 'normalized', 'FontSize', 6.5, ...
                'VerticalAlignment', 'top', 'Color', K.ink);
        end
        if isfinite(Cc.d24)
            text(ax, 0.97, 0.95, sprintf('24 h %+.0f %%', Cc.d24), 'Units', 'normalized', 'FontSize', 6.5, ...
                'VerticalAlignment', 'top', 'HorizontalAlignment', 'right', 'Color', K.ink);
        end
        text(ax, 0.03, 0.05, sl, 'Units', 'normalized', 'FontSize', 6.5, 'VerticalAlignment', 'bottom', ...
            'Color', K.ink, 'Interpreter', 'none');
        s = ''; if Cc.k > 1, s = sprintf('slice %d', Cc.k); end
        if isfinite(Cc.pct), s = strtrim(sprintf('%s  %.0f %%', s, Cc.pct)); end
        text(ax, 0.97, 0.05, s, 'Units', 'normalized', 'FontSize', 6, 'VerticalAlignment', 'bottom', ...
            'HorizontalAlignment', 'right', 'Color', K.grey);
        if Cc.nRed > 0                                 %red frame, number above it
            set(ax, 'XColor', K.red, 'YColor', K.red, 'LineWidth', 1.6);
            text(ax, 0.5, 1.03, sprintf('%d red', Cc.nRed), 'Units', 'normalized', 'FontSize', 6.5, 'FontWeight', ...
                'bold', 'Color', K.red, 'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'w', 'EdgeColor', K.red, 'Margin', 1, 'Clipping', 'off');
        end
    end
end
% legend: colours, lines, texts
y0 = hB - 0.2;
x = 0.12;
for m = [1 2 3 5]
    rectangle(axT, 'Position', [x, y0 - 0.06, 0.16, 0.12], 'FaceColor', cols{m}, 'EdgeColor', [0.7 0.7 0.7]);
    text(axT, x + 0.21, y0, short{m}, 'FontSize', 7, 'Color', K.ink);
    x = x + 0.32 + 0.065 * numel(short{m});
end
rectangle(axT, 'Position', [x, y0 - 0.06, 0.16, 0.12], 'FaceColor', K.last24, 'EdgeColor', 'none');
text(axT, x + 0.21, y0, 'last 24 h', 'FontSize', 7, 'Color', K.ink);
text(axT, 0.12, y0 - 0.2, ['blue: amplitude (median per bin);  dashed: new slice;  red frame: recordings with red ' ...
    'flags (check the analysis' repmat([', ' D.report], 1, ~isempty(D.report)) ')'], 'FontSize', 7, 'Color', K.ink, ...
    'Interpreter', 'none');
text(axT, 0.12, y0 - 0.4, ['status = end of the data of the last slice; texts: last amplitude, change in the last ' ...
    '24 h (first vs. last 2 h), number of the slice, last amplitude in % of the maximum of the slice'], 'FontSize', 7, ...
    'Color', K.grey);
savePng(fig, out);
end


function R = trendPrep(D)
% values of a trend image (trendImage, trendData): per window of the overview the included contractions (rows of a
% window weighted by their number of contractions), time axis, bin of the line, bands and the comments shown
p = numel(D.names);
R = [];
use = logical(D.inc(:)) & D.nb(:) > 0;
if ~any(use) || p == 0, return; end
[wins, ~, g] = unique(D.t(use));
X = D.V(use, :); nb = D.nb(use); nb = nb(:);
Y = nan(numel(wins), p);
g = g(:);
for j = 1:p
    x = X(:, j); ok = ~isnan(x);
    gk = reshape(g(ok), [], 1);                        %column also for one window (g(false) of a scalar is 0x0)
    Y(:, j) = accumarray(gk, reshape(x(ok) .* nb(ok), [], 1), [numel(wins) 1]) ./ ...
        accumarray(gk, reshape(nb(ok), [], 1), [numel(wins) 1]);
end
w = D.w; if isempty(w) || isnan(w(1)), w = 60; end
th = (wins(:) + w(1) / 2) / 3600;                      %hours after t0
if isfield(D, 'xlim') && numel(D.xlim) == 2 && all(isfinite(D.xlim))
    xl = sort(D.xlim(:))' / 3600;
else
    xl = [min(th) max(th)];
end
if diff(xl) <= 0, xl = xl + [-0.5 0.5]; end
span = diff(xl);
if span <= 3, bm = 5; elseif span <= 30, bm = 10; elseif span <= 24 * 7, bm = 30; else, bm = 120; end
clock = isfield(D, 't0') && ~isempty(D.t0) && isfinite(D.t0);
% bands, comments (during a protocol only the one nearest to its start and to its end, within 5 s)
B = zeros(0, 3); bl = {};
if isfield(D, 'bands') && ~isempty(D.bands), B = D.bands; bl = cellstr(D.bandLabels); end
cm = struct('t', {}, 'text', {});
if isfield(D, 'com') && ~isempty(D.com)
    P = B(B(:, 3) == 1, 1:2);
    C0 = D.com([D.com.t] >= xl(1) * 3600 - 1 & [D.com.t] <= xl(2) * 3600 + 1);
    tcs = [C0.t];
    keep = false(1, numel(C0));
    for k = 1:numel(C0)                                %outside the protocols: the comments
        keep(k) = strcmp(C0(k).category, 'comment') && ~any(P(:, 1) <= tcs(k) + 5 & P(:, 2) >= tcs(k) - 5);
    end
    for k = 1:size(P, 1)                               %a protocol: only the comment nearest to its start and its end
        for edge = P(k, :)
            [dm, j] = min(abs(tcs - edge));
            if ~isempty(dm) && dm <= 5, keep(j) = true; end
        end
    end
    for k = find(keep)
        cm(end+1) = struct('t', tcs(k), 'text', strtrim(regexprep(char(C0(k).text), '\s+', ' '))); %#ok<AGROW>
    end
    if ~isempty(cm), [~, o] = sort([cm.t]); cm = cm(o); end
end
nbw = accumarray(g, nb, [numel(wins) 1]);              %included contractions per window
R = struct('wins', wins(:), 'nb', nbw, 'Y', Y, 'th', th, 'xl', xl, 'span', span, 'bm', bm, 'clock', clock, ...
    'B', B, 'bl', {bl}, 'cm', cm);
end


function [T, C] = trendData(D)
% the data of a trend image (2026-10-14): T one row per window with included contractions: t_from (s after t0, as
% D.t), nBeats (included contractions), the parameters (units of D.units), bin_from (start of the bin of the line, s;
% line = median of the rows of a bin); C the comments shown (number, t (s), text). Empty tables if nothing is shown.
R = trendPrep(D);
names = matlab.lang.makeUniqueStrings([{'t_from', 'nBeats'}, cellstr(D.names(:)'), {'bin_from'}]);
if isempty(R)
    T = cell2table(cell(0, numel(names)), 'VariableNames', names);
    C = table(zeros(0, 1), zeros(0, 1), cell(0, 1), 'VariableNames', {'number', 't', 'text'});
    return;
end
binFrom = floor(R.th * 60 / R.bm) * R.bm * 60;          %s after t0
T = array2table([R.wins, R.nb, R.Y, binFrom], 'VariableNames', names);
C = table((1:numel(R.cm))', reshape([R.cm.t], [], 1), reshape({R.cm.text}, [], 1), ...
    'VariableNames', {'number', 't', 'text'});
end


function [y, nm, un] = trendUnits(y, nm, un)
% display units: uN -> µN, s -> ms
switch char(un)
    case 's', y = 1000 * y; un = 'ms';
    case 'uN', un = [char(181) 'N'];
    case 'uN/s', un = [char(181) 'N/s'];
    case 'uN*s', un = [char(181) 'N' char(183) 's'];
    case '', un = '-';
end
nm = char(nm);
end


function s = trendNote(th, y, un)
% median of all values; first -> last 2 h (spans of at least 4 h)
ok = ~isnan(y);
s = '';
if ~any(ok), return; end
s = sprintf('median %s %s', fmtSig(median(y(ok))), un);
t = th(ok); v = y(ok);
if max(t) - min(t) >= 4
    a = median(v(t <= min(t) + 2)); b = median(v(t >= max(t) - 2));
    s = sprintf('%s   first / last 2 h: %s %s %s', s, fmtSig(a), char(8594), fmtSig(b));
    if a ~= 0 && isfinite(a) && isfinite(b), s = sprintf('%s (%+.0f %%)', s, 100 * (b - a) / abs(a)); end
end
end


function s = fmtSig(v)
if ~isfinite(v), s = 'NaN'; return; end
if abs(v) >= 100, s = sprintf('%.0f', v); elseif abs(v) >= 10, s = sprintf('%.1f', v); else, s = sprintf('%.3g', v); end
end


function [tk, lbl] = trendTicks(xl, clock, D, nMax)
% ticks (hours after t0) and labels: clock time 'HH:MM', midnight / steps of days 'dd mmm'; otherwise hours; at most
% about nMax intervals (default 9)
if nargin < 4, nMax = 9; end
steps = [1/60 2/60 5/60 10/60 0.25 0.5 1 2 3 6 12 24 48 96 168 336];
span = diff(xl);
st = steps(end);
for k = 1:numel(steps)
    if span / steps(k) <= nMax, st = steps(k); break; end
end
if clock
    a = D.t0 + xl(1) / 24; b = D.t0 + xl(2) / 24;
    d = (ceil(a * 24 / st - 1e-9) * st / 24 : st / 24 : b + 1e-9)';
    tk = (d - D.t0) * 24;
    d = round(d * 86400) / 86400;                      %labels of whole seconds
    lbl = cell(numel(d), 1);
    for k = 1:numel(d)
        if st >= 24 || abs(d(k) - round(d(k))) < 1e-6
            lbl{k} = datestr(d(k), 'dd mmm');
        else
            lbl{k} = datestr(d(k), 'HH:MM');
        end
    end
else
    tk = (ceil(xl(1) / st - 1e-9) * st : st : xl(2) + 1e-9)';
    lbl = arrayfun(@(h) sprintf('%g', h), tk, 'UniformOutput', false);
end
end


function s = trendTime(t, clock, D, span)
if clock
    d = round((D.t0 + t / 86400) * 86400) / 86400;   %whole seconds
    if span > 24, s = datestr(d, 'dd mmm HH:MM'); else, s = datestr(d, 'HH:MM'); end
else
    s = sprintf('%d:%02d h', floor(t / 3600), floor(mod(t, 3600) / 60));
end
end
