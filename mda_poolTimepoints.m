function PT = mda_poolTimepoints(source, varargin)
%MDA_POOLTIMEPOINTS  Analyses of mda_timepoints (several experiments, samples, days) pooled by treatment: one table with
%all slices and time points (for statistics, e.g. BarsWithErrorsFromList), tables per sample and per treatment, and the
%images of mda_timepoints per treatment with all its slices.
%
%   PT = mda_poolTimepoints(resultsFolder)
%   PT = mda_poolTimepoints(source, 'labels', {'OME3uM', 'MAVA1uM'}, 'name', 'myosinModulators')
%
%   PT = mda_poolTimepoints('/data/results')
%        all analyses <experiment>/timepoints/<label>_<time>/ below the results folder of the watcher, pooled by the
%        label (treatment); files in /data/results/timepoints_pooled/pooled/
%   PT = mda_poolTimepoints(R(:, 2), 'name', 'myosinModulators')
%        the TP structs of mda_timepoints calls (e.g. collected in a script); nothing is read from the files
%
% INPUTS
%   source          results folder of the watcher (all analyses below it), the folder of one analysis
%                   (<label>_<time>/), a cell or string array of such folders, or TP structs of mda_timepoints (struct
%                   array or cell array)
% OPTIONS
%   'labels'        treatments to pool (default: all)
%   'order'         order of the treatments in the images (default: controls first, then by substance and
%                   concentration)
%   'control'       treatments that are controls (default: the labels starting with CTRL, control, vehicle or DMSO)
%   'name'          name of the pooled analysis (default 'pooled'): name of the folder and of the workbook
%   'outputFolder'  folder of the files (default <results folder of the watcher>/timepoints_pooled/<name>)
%   'write'         write the files (default true); 'figures' the images (default true, with 'write')
%
% POOLING: treatment = label of mda_timepoints, with substance, concentration and unit taken from it (OME0.5uM --> OME,
% 0.5, uM; CTRL --> CTRL, NaN, ''); sample = sampleID of mda_timepoints (option 'sampleID', slice register, or the
% series name after the setup); group = group of mda_timepoints (option 'group'); slice = series and channel of an
% analysis (sliceID <series>_ch<c>, another slice of the slice register: _s<n>). Time points = offsets of the windows
% (all offsets of the analyses of a treatment). The values of a slice and window are those of mda_timepoints: mean of
% the included beats (column <parameter>), SD, SEM, median, quartiles, normalized to the baseline window of the same
% slice (<parameter>_pctBaseline; diastolicForce_delta: change in uN). Against the controls of the same time point (the
% control slices of the same sample, otherwise all control slices; columns controlReference, nControlSlices):
% <parameter>_pctBaseline_vsControl = 100 * pctBaseline / mean pctBaseline of the controls (corrects the drift of the
% controls), diastolicForce_delta_vsControl = delta - mean delta of the controls (uN). Slices of one sample are not
% independent: the sheet
% samples has the means per sample; with slices as data points use the sample as random effect (BarsWithErrorsFromList
% option 'IDs'). Analyses of older versions of mda_timepoints (without sampleID and SEM) are skipped (sheet analyses):
% call mda_timepoints again.
%
% OUTPUT FILES (outputFolder; files of the same name are replaced):
%   <name>.xlsx   sheets slices (one row per slice and time point: treatment, substance, concentration,
%                 concentrationUnit, group, sampleID, sliceID, timePoint, offset_min, isBaseline, the columns of the
%                 summary of mda_timepoints, analysis, controlReference, nControlSlices, <...>_vsControl), samples (per
%                 treatment, sample and time point: number of slices
%                 and their mean of every parameter), treatments (per treatment and time point: number of slices and
%                 samples; per parameter and normalized value the mean, SD and SEM of the slices and the mean and SEM
%                 of the samples: <parameter>_samples, <parameter>_samplesSEM), course (per treatment and minute after
%                 the treatment: mean and SEM of the 1-min values of the slices), averageBeatsMean (per treatment and
%                 time point: mean, SD and SE of the average beats of the slices), analyses (the analyses pooled or
%                 skipped) and info
%   <treatment>/<treatment>_timepoints_abs / _norm, _course_abs / _norm, _averageBeatsMean_abs / _norm (.png, .fig)
%                 the images of mda_timepoints with all slices of the treatment: one line per slice, black = mean +-
%                 SEM of the slices
%   treatments_abs / _norm / _vsControl (.png, .fig)   per parameter and time point: the slices (dots) and their
%                 mean +- SEM for every treatment (norm, vsControl: the windows after the baseline)
%
% PT  struct with the same data: name, parameters, units, slices, samples, treatments, course, averageBeatsMean,
%     analyses, notes, controls, info, folder, files
%
% EXAMPLE (statistics of the amplitude 2 h after the treatment, sample as random effect):
%   S = PT.slices; s = S.offset_min == 120;
%   BarsWithErrorsFromList(S.amplitude_pctBaseline(s), S.treatment(s), 'lme', 'IDs', S.sampleID(s))
%
% Python: myodish_analysis.timepoints.pool_timepoints (same arguments, files and values; images as .png and .svg).
%
% TS 2026-10-16

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

P = struct('labels', {{}}, 'order', {{}}, 'control', {{}}, 'name', 'pooled', 'outputFolder', '', 'write', true, ...
    'figures', true);
if mod(numel(varargin), 2) ~= 0, error('mda_poolTimepoints: options as name, value pairs expected.'); end
for i = 1:2:numel(varargin)
    P.(validatestring(varargin{i}, fieldnames(P))) = varargin{i+1};
end
name = char(P.name);
if isempty(regexp(name, '^[A-Za-z0-9._-]+$', 'once'))
    error('mda_poolTimepoints: name: letters, digits, ''.'', ''-'' and ''_'' expected.');
end

% ---------------------------------------------------------------------------------------------------- analyses
[A, notes, resFolder] = collectAnalyses(source);
labels = cellstr(P.labels);
if ~isempty(labels) && ~isempty(A), A = A(ismember({A.label}, labels)); end
use = true(1, numel(A));
for i = 1:numel(A)
    if ~isempty(A(i).skip), use(i) = false; notes{end+1} = sprintf('%s: %s', A(i).name, A(i).skip); end %#ok<AGROW>
end
An = analysesTable(A, use);
A = A(use);
if isempty(A), error('mda_poolTimepoints: no analysis of mda_timepoints found (or none of the labels).'); end
pars = A(1).parameters;
for i = 2:numel(A), pars = pars(ismember(pars, A(i).parameters)); end
if numel(pars) < numel(A(1).parameters)
    notes{end+1} = 'parameters: only those of all analyses';
end
units = A(1).units(ismember(A(1).parameters, pars));
treat = unique({A.label}, 'stable');
treat = treatmentOrder(treat, cellstr(P.order));

% ---------------------------------------------------------------------------------------------------- slices
Sl = sliceTable(A, pars);
ctrl = cellstr(P.control);
if isempty(ctrl), ctrl = treat(~cellfun(@isempty, regexpi(treat, '^(ctrl|control|vehicle|dmso)', 'once'))); end
[Sl, nt] = controlColumns(Sl, pars, ctrl);
notes = [notes, nt];
Sm = sampleTable(Sl, pars);
Tr = treatmentTable(Sl, Sm, pars, treat);
[Co, Ab, TPs] = treatmentData(A, Sl, pars, units, treat);

PT = struct();
PT.name = name;
PT.parameters = pars;
PT.units = units;
PT.slices = Sl;
PT.samples = Sm;
PT.treatments = Tr;
PT.course = Co;
PT.averageBeatsMean = Ab;
PT.analyses = An;
PT.notes = notes;
PT.controls = ctrl;
PT.info = infoTable(PT, treat);
PT.folder = ''; PT.files = {};
if ~logical(P.write), return; end

% ---------------------------------------------------------------------------------------------------- files
d = char(P.outputFolder);
if isempty(d)
    if isempty(resFolder)
        error('mda_poolTimepoints: outputFolder: needed (no results folder of the watcher known).');
    end
    d = fullfile(resFolder, 'timepoints_pooled', name);
end
if ~isfolder(d), mkdir(d); end
x = fullfile(d, [name '.xlsx']);
if isfile(x), delete(x); end
writetable(Sl, x, 'Sheet', 'slices');
writetable(Sm, x, 'Sheet', 'samples');
writetable(Tr, x, 'Sheet', 'treatments');
writetable(Co, x, 'Sheet', 'course');
writetable(Ab, x, 'Sheet', 'averageBeatsMean');
writetable(An, x, 'Sheet', 'analyses');
writetable(PT.info, x, 'Sheet', 'info');
files = {x};
if logical(P.figures)
    for t = 1:numel(treat)
        dt = fullfile(d, treat{t});
        if ~isfolder(dt), mkdir(dt); end
        files = [files, mda_timepoints('figures', TPs{t}, dt, treat{t}, {'timepoints', 'course', ...
            'averageBeatsMean'})]; %#ok<AGROW>
    end
    modes = {'abs', 'norm', 'vsControl'};
    if isempty(ctrl), modes = {'abs', 'norm'}; end
    for m = modes
        f = fullfile(d, ['treatments_' m{1}]);
        saveFigure(treatmentsFigure(Sl, pars, units, treat, TPs, m{1}, name), f);
        files = [files, {[f '.png'], [f '.fig']}]; %#ok<AGROW>
    end
end
PT.folder = d;
PT.files = files;
end


% =====================================================================================================================
function [A, notes, resFolder] = collectAnalyses(source)
% analyses of mda_timepoints: TP structs or the workbooks <label>_<time>.xlsx of the folders
A = struct('name', {}, 'folder', {}, 'label', {}, 'summary', {}, 'course', {}, 'averageBeats', {}, ...
    'parameters', {}, 'units', {}, 'offsets', {}, 'baseline', {}, 'seconds', {}, 'version', {}, 'skip', {});
notes = {}; resFolder = '';
if isstruct(source), source = num2cell(source); end
if iscell(source) && ~isempty(source) && all(cellfun(@isstruct, source))
    for i = 1:numel(source)
        TP = source{i};
        f = TP.folder; if iscell(f), f = strjoin(f, '; '); end
        a = struct('name', sprintf('%s_%s', TP.label, char(datetime(TP.time, 'InputFormat', ...
            'yyyy-MM-dd HH:mm:ss', 'Format', 'yyyy-MM-dd-HH-mm'))), 'folder', f, 'label', TP.label, ...
            'summary', TP.summary, 'course', TP.course, 'averageBeats', TP.averageBeats, 'parameters', ...
            {TP.parameters}, 'units', {TP.units}, 'offsets', TP.offsets, 'baseline', TP.baseline, 'seconds', ...
            TP.seconds, 'version', infoValue(TP.info, 'version'), 'skip', '');
        a.skip = checkSummary(a);
        A(end+1) = a; %#ok<AGROW>
        if isempty(resFolder), resFolder = infoValue(TP.info, 'resultsFolder'); end
    end
    return;
end
F = cellstr(source);
D = {};
for i = 1:numel(F)
    f = char(F{i});
    if ~isfolder(f), error('mda_poolTimepoints: %s: no folder.', f); end
    f = char(java.io.File(f).getCanonicalPath());
    n = folderName(f);
    if isfile(fullfile(f, [n '.xlsx']))
        D{end+1} = f; %#ok<AGROW>
    else
        X = dir(fullfile(f, '**', 'timepoints', '*', '*.xlsx'));
        found = {};
        for j = 1:numel(X)
            if strcmp(X(j).name, [folderName(X(j).folder) '.xlsx']), found{end+1} = X(j).folder; end %#ok<AGROW>
        end
        D = [D, sort(found)]; %#ok<AGROW>
        if isempty(resFolder) && isfile(fullfile(f, 'mda_index.csv')), resFolder = f; end
    end
end
D = unique(D, 'stable');
for i = 1:numel(D)
    a = readAnalysis(D{i});
    if isempty(resFolder) && ~isempty(a.resultsFolder), resFolder = a.resultsFolder; end
    A(end+1) = rmfield(a, 'resultsFolder'); %#ok<AGROW>
end
end


function n = folderName(d)
% last part of a folder path (fileparts would cut a label such as OME0.5uM at the '.')
n = regexp(d, '[^/\\]+$', 'match', 'once');
end


function a = readAnalysis(d)
% one analysis from its workbook <d>/<name>.xlsx (sheets summary, course, averageBeats, info)
n = folderName(d);
x = fullfile(d, [n '.xlsx']);
a = struct('name', n, 'folder', d, 'label', '', 'summary', table(), 'course', table(), 'averageBeats', table(), ...
    'parameters', {{}}, 'units', {{}}, 'offsets', [], 'baseline', nan, 'seconds', nan, 'version', '', 'skip', '', ...
    'resultsFolder', '');
try
    I = sheet(x, 'info', {'key', 'value'});
catch
    a.skip = 'no sheet info'; return;
end
a.label = infoValue(I, 'label');
a.version = infoValue(I, 'version');
a.resultsFolder = infoValue(I, 'resultsFolder');
a.parameters = strsplit(strtrim(infoValue(I, 'parameters')));
u = strsplit(strtrim(infoValue(I, 'units')));
a.units = repmat({''}, size(a.parameters));
for k = 1:numel(u)
    q = strsplit(u{k}, '=');
    j = find(strcmp(a.parameters, q{1}), 1);
    if ~isempty(j) && numel(q) > 1, a.units{j} = q{2}; end
end
a.offsets = str2double(strsplit(strtrim(infoValue(I, 'offsets_min'))));
a.baseline = str2double(infoValue(I, 'baseline_min'));
a.seconds = str2double(infoValue(I, 'seconds'));
a.summary = sheet(x, 'summary', {'series', 'sampleID', 'group', 'time', 'from', 'to', 'recording', 'note'});
a.skip = checkSummary(a);
if ~isempty(a.skip), return; end
a.course = sheet(x, 'course', {'series', 'time', 'window'});
AB = sheet(x, 'averageBeats', {'series', 'trace', 'note'});
if ismember('note', AB.Properties.VariableNames) && ~ismember('t_s', AB.Properties.VariableNames)
    f = fullfile(d, [n '_averageBeats.csv']);                   %more than 1 million rows
    if isfile(f), AB = readtable(f, 'TextType', 'char', 'Delimiter', ','); else, AB = table(); end
end
a.averageBeats = AB;
end


function T = sheet(x, s, textCols)
% sheet s of the workbook x; textCols as text, all other columns as numbers
o = detectImportOptions(x, 'Sheet', s, 'VariableNamingRule', 'preserve', 'TextType', 'char');
v = o.VariableNames;
if any(ismember(v, textCols)), o = setvartype(o, v(ismember(v, textCols)), 'char'); end
if any(~ismember(v, textCols)), o = setvartype(o, v(~ismember(v, textCols)), 'double'); end
T = readtable(x, o);
for c = v(ismember(v, textCols))
    T.(c{1})(strcmp(T.(c{1}), '<missing>')) = {''};
end
end


function v = infoValue(I, key)
v = '';
if isempty(I) || ~all(ismember({'key', 'value'}, I.Properties.VariableNames)), return; end
k = find(strcmp(cellstr(string(I.key)), key), 1);
if ~isempty(k), v = char(string(I.value(k))); end
if strcmp(v, '<missing>'), v = ''; end
end


function s = checkSummary(a)
% '' or why the analysis cannot be pooled
s = '';
S = a.summary;
if isempty(S) || height(S) == 0, s = 'empty summary'; return; end
if ~all(ismember({'sampleID', 'group'}, S.Properties.VariableNames)) || isempty(a.parameters) || ...
        ~ismember([a.parameters{1} '_SEM'], S.Properties.VariableNames)
    s = 'older version of mda_timepoints (no sampleID, SEM): call mda_timepoints again';
end
end


function T = analysesTable(A, use)
n = numel(A);
T = table(cell(n, 1), cell(n, 1), cell(n, 1), zeros(n, 1), cell(n, 1), cell(n, 1), 'VariableNames', ...
    {'analysis', 'treatment', 'sampleID', 'nSlices', 'status', 'folder'});
for i = 1:n
    S = A(i).summary; ns = 0; sid = '';
    if ~isempty(S) && height(S) > 0 && all(ismember({'series', 'channel'}, S.Properties.VariableNames))
        ns = height(unique(S(:, {'series', 'channel'})));
        if ismember('sampleID', S.Properties.VariableNames), sid = strjoin(unique(S.sampleID, 'stable'), ' '); end
    end
    st = 'pooled'; if ~use(i), st = ['skipped: ' A(i).skip]; end
    T(i, :) = {A(i).name, A(i).label, sid, ns, st, A(i).folder};
end
end


function t = treatmentOrder(t, order)
% controls first, then by substance and concentration (molar); 'order' first
[sub, c, u] = cellfun(@splitLabel, t, 'UniformOutput', false);
molar = cellfun(@(x, y) x * unitFactor(y), c, u);
isC = ~cellfun(@isempty, regexpi(t, '^(ctrl|control|vehicle|dmso)', 'once'));
key = table(~isC(:), lower(sub(:)), molar(:), 'VariableNames', {'c', 's', 'm'});
[~, o] = sortrows(key, {'c', 's', 'm'});
t = t(o);
if ~isempty(order)
    order = order(:)';
    first = order(ismember(order, t));
    t = [first, t(~ismember(t, first))];
end
end


function [s, c, u] = splitLabel(label)
% substance, concentration and unit of a treatment label (OME0.5uM --> OME, 0.5, uM; OME0p5uM as well)
q = regexp(label, ['^(.*?)[_-]?(\d+(?:[.,p]\d+)?)\s*(pM|nM|uM|' char(181) 'M|mM|M)$'], 'tokens', 'once');
if isempty(q) || isempty(q{1}), s = label; c = nan; u = ''; return; end
s = q{1}; c = str2double(regexprep(q{2}, '[,p]', '.')); u = q{3};
end


function f = unitFactor(u)
switch u
    case 'pM', f = 1e-12;
    case 'nM', f = 1e-9;
    case {'uM', [char(181) 'M']}, f = 1e-6;
    case 'mM', f = 1e-3;
    case 'M', f = 1;
    otherwise, f = 1;
end
end


function n = normName(p)
% column of the normalized value (as mda_timepoints)
if strcmp(p, 'diastolicForce'), n = 'diastolicForce_delta'; else, n = [p '_pctBaseline']; end
end


function c = poolCols(pars)
% value, normalized value and normalized value against the controls of every parameter
q = cellfun(@normName, pars, 'UniformOutput', false);
c = [reshape([pars; q], 1, []), strcat(q, '_vsControl')];
end


function [Sl, notes] = controlColumns(Sl, pars, ctrl)
% normalized values against the controls of the same time point: the control slices of the same sample, otherwise all
% control slices; <parameter>_pctBaseline_vsControl = 100 * value / control mean, diastolicForce_delta_vsControl =
% value - control mean (uN)
notes = {};
n = height(Sl);
isC = ismember(Sl.treatment, ctrl);
ref = repmat({''}, n, 1); nRef = zeros(n, 1);
R = false(n, n);
for i = 1:n
    s = isC & Sl.offset_min == Sl.offset_min(i);
    same = s & strcmp(Sl.sampleID, Sl.sampleID{i});
    if any(same), R(:, i) = same; ref{i} = 'sample';
    elseif any(s), R(:, i) = s; ref{i} = 'all controls'; end
    nRef(i) = sum(R(:, i));
end
Sl.controlReference = ref;
Sl.nControlSlices = nRef;
for k = 1:numel(pars)
    q = normName(pars{k}); x = Sl.(q); v = nan(n, 1);
    for i = 1:n
        if nRef(i) == 0, continue; end
        m = mean(x(R(:, i)), 'omitnan');
        if strcmp(pars{k}, 'diastolicForce'), v(i) = x(i) - m; else, v(i) = 100 * x(i) / m; end
    end
    Sl.([q '_vsControl']) = v;
end
if isempty(ctrl), notes{end+1} = 'no control treatment: no values against the controls'; end
end


function Sl = sliceTable(A, pars)
% one row per slice and window: treatment, sample, slice, time point and the summary columns of mda_timepoints
parts = {};
for i = 1:numel(A)
    S = A(i).summary;
    [s, c, u] = splitLabel(A(i).label);
    n = height(S);
    sid = cell(n, 1);
    [g, gs, gc] = findgroups(S.series, S.channel);
    for k = 1:max(g)
        r = find(g == k);
        sl = S.slice(r(S.offset_min(r) == A(i).baseline));
        if isempty(sl) || isnan(sl(1)), sl = S.slice(r(~isnan(S.slice(r)))); end
        id = sprintf('%s_ch%d', gs{k}, gc(k));
        if ~isempty(sl) && sl(1) > 1, id = sprintf('%s_s%d', id, sl(1)); end
        sid(r) = {id};
    end
    tp = offsetLabels(S.offset_min');
    T = table(repmat({A(i).label}, n, 1), repmat({s}, n, 1), repmat(c, n, 1), repmat({u}, n, 1), S.group, ...
        S.sampleID, sid, tp(:), S.offset_min, double(S.offset_min == A(i).baseline), 'VariableNames', {'treatment', ...
        'substance', 'concentration', 'concentrationUnit', 'group', 'sampleID', 'sliceID', 'timePoint', ...
        'offset_min', 'isBaseline'});
    rest = S(:, setdiff(S.Properties.VariableNames, {'sampleID', 'group', 'offset_min'}, 'stable'));
    rest = renamevars(rest, 'time', 'treatmentTime');
    extra = setdiff(A(i).parameters, pars);
    keep = true(1, width(rest));
    if ~isempty(extra)
        keep = ~startsWith(rest.Properties.VariableNames, strcat(extra, '_')) & ...
            ~ismember(rest.Properties.VariableNames, extra);
    end
    T = [T, rest(:, keep)]; %#ok<AGROW>
    T.analysis = repmat({A(i).name}, n, 1);
    if ~isempty(parts), T = alignTable(T, parts{1}); end
    parts{end+1} = T; %#ok<AGROW>
end
Sl = vertcat(parts{:});
end


function T = alignTable(T, R)
% columns of T in the order of R (missing: NaN or '')
for c = R.Properties.VariableNames
    if ismember(c{1}, T.Properties.VariableNames), continue; end
    if iscell(R.(c{1})), T.(c{1}) = repmat({''}, height(T), 1); else, T.(c{1}) = nan(height(T), 1); end
end
T = T(:, R.Properties.VariableNames);
end


function Sm = sampleTable(Sl, pars)
% per treatment, sample and window: number of slices and the mean of the slices of every parameter
cols = poolCols(pars);
[g, tr, smp, off] = findgroups(Sl.treatment, Sl.sampleID, Sl.offset_min);
n = max(g);
Sm = table(tr, cell(n, 1), smp, off, offsetLabels(off')', splitapply(@numel, Sl.offset_min, g), 'VariableNames', ...
    {'treatment', 'group', 'sampleID', 'offset_min', 'timePoint', 'nSlices'});
for k = 1:n, Sm.group{k} = Sl.group{find(g == k, 1)}; end
for c = cols
    Sm.(c{1}) = splitapply(@(x) mean(x, 'omitnan'), Sl.(c{1}), g);
end
end


function Tr = treatmentTable(Sl, Sm, pars, treat)
% per treatment and window: n slices, n samples; per parameter mean, SD, SEM of the slices, mean and SEM of the samples
cols = poolCols(pars);
[g, tr, off] = findgroups(Sl.treatment, Sl.offset_min);
[~, o] = sortrows(table(cellfun(@(x) find(strcmp(treat, x), 1), tr), off));
n = max(g);
Tr = table(tr, off, offsetLabels(off')', splitapply(@numel, Sl.offset_min, g), ...
    splitapply(@(x) numel(unique(x)), Sl.sampleID, g), 'VariableNames', {'treatment', 'offset_min', 'timePoint', ...
    'nSlices', 'nSamples'});
gm = zeros(height(Sm), 1);
for k = 1:n, gm(strcmp(Sm.treatment, tr{k}) & Sm.offset_min == off(k)) = k; end
for c = cols
    x = Sl.(c{1});
    Tr.(c{1}) = splitapply(@(v) mean(v, 'omitnan'), x, g);
    Tr.([c{1} '_SD']) = splitapply(@sdOf, x, g);
    Tr.([c{1} '_SEM']) = splitapply(@semOf, x, g);
    y = Sm.(c{1}); ms = nan(n, 1); es = ms;
    for k = 1:n, ms(k) = mean(y(gm == k), 'omitnan'); es(k) = semOf(y(gm == k)); end
    Tr.([c{1} '_samples']) = ms;
    Tr.([c{1} '_samplesSEM']) = es;
end
Tr = Tr(o, :);
end


function s = sdOf(x)
x = x(~isnan(x));
if numel(x) < 2, s = nan; else, s = std(x); end
end


function s = semOf(x)
x = x(~isnan(x));
if numel(x) < 2, s = nan; else, s = std(x) / sqrt(numel(x)); end
end


function [Co, Ab, TPs] = treatmentData(A, Sl, pars, units, treat)
% per treatment: course (mean and SEM of the slices per minute), mean of the average beats, TP struct for the images
cols = reshape([pars; cellfun(@normName, pars, 'UniformOutput', false)], 1, []);
Cparts = {}; Aparts = {}; TPs = cell(1, numel(treat));
for t = 1:numel(treat)
    ia = find(strcmp({A.label}, treat{t}));
    S = Sl(strcmp(Sl.treatment, treat{t}), :);
    off = unique([A(ia).offsets]);
    bl = unique([A(ia).baseline]);
    if numel(bl) ~= 1, bl = nan; end
    sec = A(ia(1)).seconds;
    % slices of the treatment: key = analysis|series (series names may repeat in other analyses)
    key = strcat(S.analysis, '|', S.series);
    [u, iu] = unique(strcat(key, '|', arrayfun(@num2str, S.channel, 'UniformOutput', false)), 'stable');
    nP = numel(u); nK = numel(off);
    R = table(key(iu), S.channel(iu), cell(nP, 1), S.sampleID(iu), S.treatmentTime(iu), 'VariableNames', ...
        {'series', 'channel', 'label', 'sampleID', 'time'});
    for p = 1:nP
        st = regexp(S.series{iu(p)}, '^[^_]+', 'match', 'once');
        R.label{p} = sprintf('%s %s ch%d', S.sampleID{iu(p)}, st, S.channel(iu(p)));
    end
    Su = table(repelem(R.series, nK, 1), repelem(R.channel, nK, 1), repmat(off(:), nP, 1), 'VariableNames', ...
        {'series', 'channel', 'offset_min'});
    TP = struct('label', treat{t}, 'offsets', off, 'seconds', sec, 'baseline', bl, 'parameters', {pars}, ...
        'units', {units}, 'rows', R);
    for i = 1:numel(pars)
        M = nan(nP, nK); Q = M; E = M;
        for p = 1:nP
            s = strcmp(key, R.series{p}) & S.channel == R.channel(p);
            [~, k] = ismember(S.offset_min(s), off);
            M(p, k) = S.(pars{i})(s); Q(p, k) = S.(normName(pars{i}))(s); E(p, k) = S.([pars{i} '_SEM'])(s);
        end
        TP.matrix.(pars{i}) = M; TP.pctBaseline.(pars{i}) = Q;
        Su.([pars{i} '_SEM']) = reshape(E', [], 1);
    end
    TP.summary = Su;
    % course: 1-min values of the slices
    cp = {};
    for j = ia
        C = A(j).course;
        if isempty(C) || height(C) == 0 || ~all(ismember([{'series', 'channel', 'minutes'}, cols], ...
                C.Properties.VariableNames)), continue; end
        C = C(:, [{'series', 'channel', 'minutes'}, cols]);
        C.series = strcat(A(j).name, '|', C.series);
        cp{end+1} = C; %#ok<AGROW>
    end
    if isempty(cp)
        C = cell2table(cell(0, 3 + numel(cols)), 'VariableNames', [{'series', 'channel', 'minutes'}, cols]);
    else
        C = vertcat(cp{:});
    end
    C = C(ismember(strcat(C.series, '|', arrayfun(@num2str, C.channel, 'UniformOutput', false)), u), :);
    TP.course = C;
    if height(C) > 0
        m = round(C.minutes);
        [g, mm] = findgroups(m);
        T = table(repmat(treat(t), numel(mm), 1), mm, splitapply(@(x) numel(unique(x)), ...
            strcat(C.series, '|', arrayfun(@num2str, C.channel, 'UniformOutput', false)), g), 'VariableNames', ...
            {'treatment', 'minutes', 'nSlices'});
        for c = cols
            T.(c{1}) = splitapply(@(x) mean(x, 'omitnan'), C.(c{1}), g);
            T.([c{1} '_SEM']) = splitapply(@semOf, C.(c{1}), g);
        end
        Cparts{end+1} = T; %#ok<AGROW>
    end
    % average beats of the slices (trace all)
    ap = {};
    for j = ia
        B = A(j).averageBeats;
        if isempty(B) || height(B) == 0 || ~ismember('t_s', B.Properties.VariableNames), continue; end
        B = B(strcmp(B.trace, 'all'), :);
        B.series = strcat(A(j).name, '|', B.series);
        ap{end+1} = B; %#ok<AGROW>
    end
    if isempty(ap), AB = table(); else, AB = vertcat(ap{:}); end
    if height(AB) > 0
        AB = AB(ismember(strcat(AB.series, '|', arrayfun(@num2str, AB.channel, 'UniformOutput', false)), u), :);
    end
    TP.averageBeats = AB;
    TP.averageBeatsMean = averageBeatsMean(AB, off);
    if height(TP.averageBeatsMean) > 0
        M = TP.averageBeatsMean;
        Aparts{end+1} = [table(repmat(treat(t), height(M), 1), 'VariableNames', {'treatment'}), M]; %#ok<AGROW>
    end
    L = offsetLabels(bl);
    if isnan(bl), b = ''; else, b = sprintf(', baseline %s', L{1}); end
    TP.unitName = 'slices';
    TP.title = sprintf('%s (pooled): %d slice(s) of %d sample(s), windows of %g s%s', treat{t}, nP, ...
        numel(unique(R.sampleID)), sec, b);
    TPs{t} = TP;
end
if isempty(Cparts)
    Co = cell2table(cell(0, 3), 'VariableNames', {'treatment', 'minutes', 'nSlices'});
else
    Co = vertcat(Cparts{:});
end
if isempty(Aparts)
    M = averageBeatsMean(table(), 0);
    Ab = [table(cell(0, 1), 'VariableNames', {'treatment'}), M];
else
    Ab = vertcat(Aparts{:});
end
end


function M = averageBeatsMean(AB, offsets)
% mean, SD and SE over the slices of the average beats (trace all) per window, common time axis (shortest beat), as
% mda_timepoints
v = {'force_uN', 'norm_baselineAmplitude', 'norm_ownAmplitude'};
names = [{'offset_min', 't_s', 'n'}, reshape([strcat(v, '_mean'); strcat(v, '_sd'); strcat(v, '_se')], 1, [])];
M = array2table(zeros(0, numel(names)), 'VariableNames', names);
if isempty(AB) || height(AB) == 0, return; end
keys = strcat(AB.series, '|', arrayfun(@num2str, AB.channel, 'UniformOutput', false));
parts = {};
for k = 1:numel(offsets)
    Ak = AB(AB.offset_min == offsets(k), :); kk = keys(AB.offset_min == offsets(k));
    u = unique(kk, 'stable');
    if isempty(u), continue; end
    tmax = inf;
    for i = 1:numel(u), tmax = min(tmax, max(Ak.t_s(strcmp(kk, u{i})))); end
    t = Ak.t_s(strcmp(kk, u{1}) & Ak.t_s <= tmax + 1e-9);
    n = numel(u);
    T = table(repmat(offsets(k), numel(t), 1), t, repmat(n, numel(t), 1), 'VariableNames', names(1:3));
    for c = 1:numel(v)
        Y = nan(numel(t), n);
        for i = 1:n
            s = strcmp(kk, u{i}) & Ak.t_s <= tmax + 1e-9;
            y = Ak.(v{c})(s);
            Y(1:min(numel(y), numel(t)), i) = y(1:min(numel(y), numel(t)));
        end
        sd = nan(numel(t), 1);
        if n > 1, sd = std(Y, 0, 2, 'omitnan'); end
        T.([v{c} '_mean']) = mean(Y, 2, 'omitnan'); T.([v{c} '_sd']) = sd; T.([v{c} '_se']) = sd / sqrt(n);
    end
    parts{end+1} = T; %#ok<AGROW>
end
if ~isempty(parts), M = vertcat(parts{:}); end
end


function T = infoTable(PT, treat)
k = {'function'; 'version'; 'implementation'; 'analysisDate'; 'name'; 'treatments'; 'controls'; 'parameters'; ...
    'units'; 'values'; 'vsControl'; 'samples'; 'treatmentsSheet'; 'course'; 'notes'};
v = {'mda_poolTimepoints'; mda_version(); 'MATLAB'; char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')); ...
    PT.name; strjoin(treat, ' '); strjoin(PT.controls, ' '); strjoin(PT.parameters, ' '); ...
    strjoin(strcat(PT.parameters, '=', PT.units), ' '); ...
    ['per slice and window as mda_timepoints: mean (column <parameter>), SD, SEM, median, q25, q75 of the ' ...
    'included beats; <parameter>_pctBaseline = 100 * mean / mean of the baseline window of the slice; ' ...
    'diastolicForce_delta = mean - baseline mean (uN)']; ...
    ['against the controls of the same time point (the control slices of the same sample, otherwise all control ' ...
    'slices: controlReference, nControlSlices): <parameter>_pctBaseline_vsControl = 100 * pctBaseline / mean ' ...
    'pctBaseline of the controls; diastolicForce_delta_vsControl = delta - mean delta of the controls (uN)']; ...
    'mean of the slices of a sample per treatment and window (slices of a sample are not independent)'; ...
    ['per treatment and window: mean, SD and SEM of the slices; <parameter>_samples, <parameter>_samplesSEM: ' ...
    'mean and SEM of the sample means']; ...
    'mean and SEM of the 1-min values of the slices per minute after the treatment (rounded)'; ...
    strjoin(PT.notes, '; ')};
T = table(k, v, 'VariableNames', {'key', 'value'});
end


% ---------------------------------------------------------------------------------------------------- figures
function h = treatmentsFigure(Sl, pars, units, treat, TPs, mode, name)
% per parameter: x = treatments; per window the slices (dots) and their mean +- SEM; norm and vsControl (against the
% controls): windows after the baseline
isNorm = ~strcmp(mode, 'abs'); isCtrl = strcmp(mode, 'vsControl');
offs = unique(Sl.offset_min)';
if isNorm, offs = offs(~ismember(offs, Sl.offset_min(Sl.isBaseline == 1))); end
nT = numel(treat); nK = numel(offs);
nc = min(3, numel(pars)); nr = ceil(numel(pars) / nc);
h = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', 'Position', [1 1 max(4.2, 0.55 * nT + 1.5) * nc, ...
    3.4 * nr + 0.6]);
col = lines(max(nK + 1, 2)); col = col(2:end, :);
bl = unique(Sl.offset_min(Sl.isBaseline == 1));
for k = 1:nK, if ismember(offs(k), bl), col(k, :) = [0 0 0]; end, end
L = offsetLabels(offs);
w = 0.7 / max(nK, 1);
for i = 1:numel(pars)
    ax = subplot(nr, nc, i); hold(ax, 'on'); box(ax, 'on');
    if isCtrl, v = [normName(pars{i}) '_vsControl']; elseif isNorm, v = normName(pars{i}); else, v = pars{i}; end
    for k = 1:nK
        x0 = (1:nT) + (k - (nK + 1) / 2) * w;
        mu = nan(1, nT); se = mu;
        for t = 1:nT
            y = Sl.(v)(strcmp(Sl.treatment, treat{t}) & Sl.offset_min == offs(k));
            y = y(~isnan(y));
            if isempty(y), continue; end
            jx = x0(t) + (mod((1:numel(y))' * 0.618, 1) - 0.5) * w * 0.6;
            plot(ax, jx, y, '.', 'Color', 0.55 * col(k, :) + 0.45, 'MarkerSize', 7, 'HandleVisibility', 'off');
            mu(t) = mean(y); se(t) = semOf(y);
        end
        errorbar(ax, x0, mu, se, 'o', 'Color', col(k, :), 'MarkerFaceColor', col(k, :), 'MarkerSize', 5, ...
            'LineWidth', 1.2, 'CapSize', 4, 'DisplayName', L{k});
    end
    if isNorm
        r = 100; if strcmp(pars{i}, 'diastolicForce'), r = 0; end
        yline(ax, r, ':', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');
        if strcmp(pars{i}, 'diastolicForce') && isCtrl, yl = 'change against the baseline - controls (uN)';
        elseif strcmp(pars{i}, 'diastolicForce'), yl = 'change against the baseline (uN)';
        elseif isCtrl, yl = '% of baseline, % of the controls';
        else, yl = '% of baseline'; end
    else
        yl = units{i};
    end
    set(ax, 'XTick', 1:nT, 'XTickLabel', treat, 'XLim', [0.4, nT + 0.6], 'FontSize', 7, 'TickLabelInterpreter', ...
        'none');
    xtickangle(ax, 45);
    ylabel(ax, yl, 'Interpreter', 'none');
    if isempty(units{i}), tt = pars{i}; else, tt = sprintf('%s (%s)', pars{i}, units{i}); end
    title(ax, tt, 'FontWeight', 'normal', 'FontSize', 9, 'Interpreter', 'none');
    if i == 1, legend(ax, 'Location', 'best', 'FontSize', 6, 'Box', 'off', 'Interpreter', 'none'); end
end
n = cellfun(@(T) height(T.rows), TPs);
if isCtrl, m = 'normalized to the baseline window and to the controls';
elseif isNorm, m = 'normalized to the baseline window of the slice';
else, m = 'absolute'; end
sgtitle(h, sprintf('%s: %d treatment(s), %d slice(s) - slices (dots) and mean +- SEM, %s', name, nT, sum(n), m), ...
    'FontSize', 10, 'Interpreter', 'none');
end


function L = offsetLabels(off)
% '-60 min' --> '-1 h' (as mda_timepoints)
L = cell(1, numel(off));
for i = 1:numel(off)
    o = off(i);
    if isnan(o), L{i} = ''; continue; end
    if o ~= 0 && mod(o, 60) == 0, L{i} = sprintf('%+g h', o / 60); else, L{i} = sprintf('%+g min', o); end
    if o == 0, L{i} = '0 min'; end
end
end


function saveFigure(h, f)
% <f>.png (150 dpi) and <f>.fig (visible when opened)
set(h, 'PaperPositionMode', 'auto');
print(h, [f '.png'], '-dpng', '-r150');
set(h, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')');
savefig(h, [f '.fig']);
close(h);
end
