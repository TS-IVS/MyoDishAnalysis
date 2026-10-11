function R = mda_readResults(resultsFile)
%MDA_READRESULTS  Read a results file of MyoDishAnalysis (settings, analysis windows, contractions) to show it again.
%
%   R = mda_readResults('results.xlsx')
%   R = mda_readResults('results_info.csv')      (or _summary.csv, _contractions.csv(.gz), _thresholds.csv: the
%                                                  other files of the set are found by their names)
%   R = mda_readResults('settings.csv')          a single table key, value (settings file of mda_settings): options
%
% Results of MyoDishAnalysis ('output'), MyoDishAnalysisWatch, MyoDishAnalysisGUI (Export this channel ..., All
% channels -> file ..., protocols) and of the Python version. Used by MyoDishAnalysisGUI to open results:
% MyoDishAnalysisGUI('results.xlsx').
%
%   R.mddFile         recording (path at the time of the analysis, 'file' of the info table)
%   R.version, R.implementation, R.createdBy, R.analysisDate
%   R.options         options (mda_options) from the rows option_<name> of the info table; options of another
%                     version that are unknown here and a reference beat are left out (R.notes)
%   R.channels        analysed channels (one threshold / zero force per channel: same order); [] if not recorded
%   R.windows         table, one row per analysis window: channel, range (label), from, to (contractions reported),
%                     windowFrom, windowTo (data read and analysed), threshold_uN. Older results without the
%                     thresholds sheet: from the summary (window = range +- maxBeatWindow + 2 s, R.notes)
%   R.summary, R.contractions, R.labels, R.rockerFilter   tables of the results ([] if not present)
%   R.extra           struct of the other rows of the info table (e.g. loadedWindow_s, epRecording, watcherOptions)
%   R.info            the info table (key, value)
%   R.notes           cell of messages
%
% TS 2026-10-09 (settings files 2026-10-10)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

R = struct('resultsFile', char(resultsFile), 'mddFile', '', 'version', '', 'implementation', '', 'createdBy', '', ...
    'analysisDate', '', 'options', mda_options(), 'channels', [], 'windows', [], 'summary', [], 'contractions', [], ...
    'labels', [], 'rockerFilter', [], 'extra', struct(), 'info', [], 'notes', {{}});
[p, n, e] = fileparts(char(resultsFile));
if strcmpi(e, '.gz')                                %<name>_contractions.csv.gz
    [~, n] = fileparts(n);
    e = '.csv';
end
if strcmpi(e, '.xlsx') || strcmpi(e, '.xls')
    sheets = sheetnames(resultsFile);
    get = @(nm) readSheet(resultsFile, sheets, nm);
else
    base = regexprep(n, '_(info|summary|contractions|thresholds|parameters|labels|rockerFilter|protocols|protocolResults|pulses)$', '');
    get = @(nm) readCsv(fullfile(p, [base '_' nm '.csv']));
end
I = get('info');
if isempty(I) && strcmpi(e, '.csv') && exist(resultsFile, 'file')   %a single table key, value (settings file)
    I = readCsv(char(resultsFile), true);
end
if isempty(I) || ~all(ismember({'key', 'value'}, I.Properties.VariableNames))
    error('mda_readResults: no info table (key, value) found for %s.', resultsFile);
end
I.key = cellstr(string(I.key)); I.value = cellstr(string(I.value));
I.value(strcmp(I.value, '<missing>')) = {''};
R.info = I;
val = @(k) firstValue(I, k);
R.mddFile = val('file');
R.version = val('version');
R.implementation = val('implementation');
if isempty(R.version)                               %results written before 2026-10-09: version in 'software'
    sw = val('software');
    tok = regexp(sw, '(\d+\.\d+\.\d+(-?[a-z]+\.?\d*)?)', 'tokens', 'once');
    if ~isempty(tok), R.version = tok{1}; end
    if contains(sw, 'Python'), R.implementation = 'Python'; elseif contains(sw, 'MATLAB'), R.implementation = 'MATLAB'; end
end
R.createdBy = val('createdBy');
R.analysisDate = val('analysisDate');
% options
defaults = mda_options();
given = struct();
known = fieldnames(defaults);
for k = find(startsWith(I.key, 'option_'))'
    name = I.key{k}(8:end);
    v = I.value{k};
    if ~ismember(name, known)
        R.notes{end+1} = sprintf('option %s of the results is unknown in this version (ignored)', name);
        continue;
    end
    if strcmp(name, 'referenceBeat')
        if ~isempty(v), R.notes{end+1} = sprintf('%s: not restored (create it again in the GUI)', v); end
        continue;
    end
    given.(name) = parseValue(v, defaults.(name), name);
end
if any(startsWith(I.key, 'option_')) && ~ismember('option_stimAssignment', I.key)
    given.stimAssignment = 'peak';                 %results of versions <= 1.0.0-beta.3 (2026-10-10)
    R.notes{end+1} = 'results without option stimAssignment (older version): stimulus assignment ''peak''';
end
R.options = mda_options(given);
ch = val('channels');
if ~isempty(ch), R.channels = parseNumbers(ch); end
% tables
R.summary = get('summary');
R.labels = get('labels');
R.rockerFilter = get('rockerFilter');
cf = fullfile(p, [regexprep(n, '_(info|summary|contractions|thresholds|parameters|labels|rockerFilter|protocols|protocolResults|pulses)$', '') '_contractions.csv.gz']);
if ~(strcmpi(e, '.xlsx') || strcmpi(e, '.xls')) && ~exist(regexprep(cf, '\.gz$', ''), 'file') && exist(cf, 'file')
    tmp = tempname; mkdir(tmp);                     %readtable does not read .gz
    gunzip(cf, tmp);
    [~, cn] = fileparts(cf);
    R.contractions = readCsv(fullfile(tmp, cn));
    rmdir(tmp, 's');
else
    R.contractions = get('contractions');
end
% analysis windows
W = get('thresholds');
if ~isempty(W) && all(ismember({'channel', 'from', 'to', 'windowFrom', 'windowTo'}, W.Properties.VariableNames))
    lbl = repmat({''}, height(W), 1);
    if ~isempty(R.summary) && all(ismember({'range', 'channel', 'from', 'to'}, R.summary.Properties.VariableNames))
        Sm = R.summary;
        for r = 1:height(W)
            j = find(Sm.channel == W.channel(r) & Sm.from <= W.from(r) + 1e-6 & Sm.to >= W.to(r) - 1e-6, 1);
            if ~isempty(j), lbl{r} = char(string(Sm.range(j))); end
        end
    end
    thr = nan(height(W), 1);
    if ismember('threshold_uN', W.Properties.VariableNames), thr = W.threshold_uN; end
    R.windows = table(W.channel, lbl, W.from, W.to, W.windowFrom, W.windowTo, thr, 'VariableNames', ...
        {'channel', 'range', 'from', 'to', 'windowFrom', 'windowTo', 'threshold_uN'});
elseif ~isempty(R.summary) && all(ismember({'channel', 'from', 'to'}, R.summary.Properties.VariableNames))
    Sm = R.summary;
    pad = R.options.maxBeatWindow + 2;
    if R.options.rockerFilter, pad = max(pad, 60); end
    lbl = repmat({''}, height(Sm), 1);
    if ismember('range', Sm.Properties.VariableNames), lbl = cellstr(string(Sm.range)); end
    thr = nan(height(Sm), 1);
    if ismember('detectionThreshold', Sm.Properties.VariableNames), thr = Sm.detectionThreshold; end
    R.windows = table(Sm.channel, lbl, Sm.from, Sm.to, max(0, Sm.from - pad), Sm.to + pad, thr, 'VariableNames', ...
        {'channel', 'range', 'from', 'to', 'windowFrom', 'windowTo', 'threshold_uN'});
    R.notes{end+1} = 'no analysis windows in the results (older version): data window = range +- maxBeatWindow + 2 s';
else
    R.windows = table(zeros(0,1), cell(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        'VariableNames', {'channel', 'range', 'from', 'to', 'windowFrom', 'windowTo', 'threshold_uN'});
end
% other rows of the info table
skip = [{'file', 'version', 'implementation', 'createdBy', 'analysisDate', 'channels', 'notes', 'software'}, ...
    {'samplingRate_Hz', 'samplingRateSource', 'nChannelsInFile', 'fileLength_s', 'recordingStart'}];
for k = 1:height(I)
    key = I.key{k};
    if startsWith(key, {'option_', 'logOffset_ch', 'logCalibration_ch'}) || ismember(key, skip), continue; end
    R.extra.(matlab.lang.makeValidName(key)) = I.value{k};
end
nt = val('notes');
if ~isempty(nt), R.notes = [{['notes of the analysis: ' nt]}, R.notes]; end
end


function v = firstValue(I, key)
j = find(strcmp(I.key, key), 1);
if isempty(j), v = ''; else, v = I.value{j}; end
end


function v = parseValue(s, default, name)
% option value from its text in the info table (as written by mda_writeResults / write_results)
s = strtrim(s);
if isempty(s)
    v = [];
    if ischar(default), v = default; end
    return;
end
x = parseNumbers(s);
if ~isempty(x)
    v = x;
elseif any(strcmpi(s, {'true', 'false'}))
    v = strcmpi(s, 'true');
else
    v = s;
end
if (islogical(default) || strcmp(name, 'extendedSensorMode')) && isnumeric(v) && isscalar(v), v = v ~= 0; end
end


function x = parseNumbers(s)
% numbers of a scalar or of mat2str text ('[1 2;3 4]', 'NaN', 'Inf'); [] if s is not numeric. No eval.
s = strtrim(s);
x = [];
if isempty(s), return; end
t = regexprep(s, '^\[|\]$', '');
rows = strsplit(t, ';');
M = [];
for r = 1:numel(rows)
    parts = strsplit(strtrim(rows{r}));
    parts = parts(~cellfun(@isempty, parts));
    v = str2double(parts);
    bad = isnan(v) & ~strcmpi(parts, 'NaN');
    if isempty(v) || any(bad), x = []; return; end
    if r > 1 && numel(v) ~= size(M, 2), x = []; return; end
    M = [M; v]; %#ok<AGROW>
end
x = M;
end


function T = readSheet(file, sheets, nm)
T = [];
if ~ismember(nm, sheets), return; end
o = detectImportOptions(file, 'Sheet', nm);
o.VariableNamesRange = 'A1'; o.DataRange = 'A2';  %header in row 1 (detection can take the first row for a header)
if strcmp(nm, 'info'), o = setvartype(o, intersect(o.VariableNames, {'key', 'value'}), 'char'); end
o = textDates(o);
T = readtable(file, o);
end


function T = readCsv(file, isInfo)
T = [];
if ~exist(file, 'file'), return; end
o = detectImportOptions(file, 'FileType', 'text', 'Delimiter', ',');
o.VariableNamesLine = 1; o.DataLines = [2 Inf];     %header in line 1 (detection can skip the first data line)
[~, n] = fileparts(file);
if endsWith(n, '_info') || (nargin > 1 && isInfo), o = setvartype(o, intersect(o.VariableNames, {'key', 'value'}), 'char'); end
o = textDates(o);
T = readtable(file, o);
end


function o = textDates(o)
% text columns (range labels, beat types, dates) as char
for k = 1:numel(o.VariableNames)
    if any(strcmp(o.VariableTypes{k}, {'string', 'datetime', 'categorical'})), o = setvartype(o, o.VariableNames{k}, 'char'); end
end
end
