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
%   'exclude'       slices or windows left out, with the reason (2026-10-18): a cell array with one row per entry
%                   {id, channel, from_min, reason} (id = sampleID, series or sliceID; channel [] or NaN = all
%                   channels of id; from_min [] or NaN = all windows, otherwise the windows from this offset on), a
%                   cell array of ids (whole slices), or a table with the variables id (or sampleID, sliceID, series),
%                   channel, from_min, reason; e.g. {'ABC000101', 6, 720, 'arrhythmic from +12 h'}. Left out of all
%                   tables, the course and the images; listed in the sheet excluded
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
%                 of the samples: <parameter>_samples, <parameter>_samplesSEM), statistics (2026-10-18: per
%                 treatment, time point after the baseline and normalized parameter against the controls of the same
%                 time point: n, means and SEM of the slices, difference, paired difference of the sample means
%                 (samples with both), linear mixed model value ~ 1 + treatment + (1 | sampleID) (REML, t test with
%                 n - 2 degrees of freedom) if both groups have >= 3 samples, otherwise descriptive only), qc (windows
%                 with notes; column qc of the slices: arrhythmic, capture, noContractions, alternans, irregular,
%                 protocol, signal, otherSlice, comment, pending), excluded (option 'exclude'), course (per treatment
%                 and minute after
%                 the treatment: mean and SEM of the 1-min values of the slices), averageBeatsMean (per treatment and
%                 time point: mean, SD and SE of the average beats of the slices), analyses (the analyses pooled or
%                 skipped) and info
%   <treatment>/<treatment>_timepoints_abs / _norm, _course_abs / _norm, _averageBeatsMean_abs / _norm (.png, .fig)
%                 the images of mda_timepoints with all slices of the treatment: one line per slice, black = mean +-
%                 SEM of the slices
%   treatments_abs / _norm / _vsControl (.png, .fig)   per parameter and time point: the slices (dots) and their
%                 mean +- SEM for every treatment (norm, vsControl: the windows after the baseline)
%   <name>_figure_norm (.pdf, .svg, .png; 2026-10-18)   figure for a manuscript (mda_plotTimepoints: amplitude,
%                 diastolic force, TTP90, TTR90 over time, mean +- SEM and single slices per treatment)
%   <name>_prism.xlsx   the normalized values for GraphPad Prism (one sheet per parameter, one row per time point,
%                 one column per slice: treatment|sample slice)
%
% PT  struct with the same data: name, parameters, units, slices, samples, treatments, statistics, qc, excluded,
%     course, averageBeatsMean, analyses, notes, controls, info, folder, files
%
% EXAMPLE (statistics of the amplitude 2 h after the treatment, sample as random effect):
%   S = PT.slices; s = S.offset_min == 120;
%   BarsWithErrorsFromList(S.amplitude_pctBaseline(s), S.treatment(s), 'lme', 'IDs', S.sampleID(s))
%
% Mixed model of the sheet statistics alone: M = mda_poolTimepoints('lme', y, x, g) (fields estimate, SE, df, p,
% varianceRatio; y values, x 0 = control / 1 = treatment, g sample IDs).
%
% Python: myodish_analysis.timepoints.pool_timepoints (same arguments, files and values; images as .png and .svg).
%
% TS 2026-10-16 (exclude, qc, statistics: 2026-10-18)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

if (ischar(source) || isstring(source)) && strcmp(source, 'lme')   %mixed model of the sheet statistics (tests)
    [e, se, df, pv, th] = lmeRI(varargin{:});
    PT = struct('estimate', e, 'SE', se, 'df', df, 'p', pv, 'varianceRatio', th);
    return;
end
P = struct('labels', {{}}, 'order', {{}}, 'control', {{}}, 'name', 'pooled', 'outputFolder', '', 'write', true, ...
    'figures', true, 'exclude', {{}});
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
Sl = addvars(Sl, cellfun(@qcCodes, Sl.note, 'UniformOutput', false), 'After', 'note', 'NewVariableNames', 'qc');
[Sl, Ex, cut, nt, xtxt] = applyExclude(Sl, P.exclude);
notes = [notes, nt];
left = treat(~ismember(treat, unique(Sl.treatment)));
if ~isempty(left)
    notes{end+1} = ['no slices left (exclude): ' strjoin(left, ' ')];
    treat = treat(~ismember(treat, left));
    A = A(ismember({A.label}, treat));
end
if isempty(treat), error('mda_poolTimepoints: exclude: no slices left.'); end
ctrl = cellstr(P.control);
if isempty(ctrl), ctrl = treat(~cellfun(@isempty, regexpi(treat, '^(ctrl|control|vehicle|dmso)', 'once'))); end
[Sl, nt] = controlColumns(Sl, pars, ctrl);
notes = [notes, nt];
Sm = sampleTable(Sl, pars);
Tr = treatmentTable(Sl, Sm, pars, treat);
St = statisticsTable(Sl, pars, treat, ctrl);
Q = Sl(~cellfun(@isempty, Sl.qc), {'treatment', 'sampleID', 'sliceID', 'series', 'channel', 'timePoint', ...
    'offset_min', 'qc', 'note'});
[Co, Ab, TPs] = treatmentData(A, Sl, pars, units, treat, cut);

PT = struct();
PT.name = name;
PT.parameters = pars;
PT.units = units;
PT.slices = Sl;
PT.samples = Sm;
PT.treatments = Tr;
PT.statistics = St;
PT.qc = Q;
PT.excluded = Ex;
PT.excludeText = xtxt;
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
writeSheet(St, x, 'statistics');
writeSheet(Q, x, 'qc');
writeSheet(Ex, x, 'excluded');
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
    [hf, fl] = mda_plotTimepoints(PT, 'output', fullfile(d, [name '_figure_norm']));   %for a manuscript (2026-10-18)
    close(hf);
    files = [files, fl];
end
xp = fullfile(d, [name '_prism.xlsx']);            %tables for GraphPad Prism (2026-10-18)
if isfile(xp), delete(xp); end
T = mda_plotTimepoints('prism', PT);
for fn = fieldnames(T)'
    writetable(T.(fn{1}), xp, 'Sheet', fn{1}(1:min(31, end)));
end
files{end+1} = xp;
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
    f = canonicalPath(f);
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


function [Co, Ab, TPs] = treatmentData(A, Sl, pars, units, treat, cut)
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
    kc = strcat(C.series, '|', arrayfun(@num2str, C.channel, 'UniformOutput', false));
    keep = ismember(kc, u);
    if ~isempty(cut) && cut.Count > 0              %exclude from an offset on: 1-min values from this minute on
        for r = find(keep)'
            if isKey(cut, kc{r}) && C.minutes(r) >= cut(kc{r}), keep(r) = false; end
        end
    end
    C = C(keep, :);
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
        ka = strcat(AB.series, '|', arrayfun(@num2str, AB.channel, 'UniformOutput', false));
        keep = ismember(ka, u);
        if ~isempty(cut) && cut.Count > 0
            for r = find(keep)'
                if isKey(cut, ka{r}) && AB.offset_min(r) >= cut(ka{r}), keep(r) = false; end
            end
        end
        AB = AB(keep, :);
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


function c = qcCodes(note)
% codes of the notes of a window (column qc, 2026-10-18): arrhythmic, capture, noContractions, alternans, irregular,
% protocol, signal, otherSlice, comment, pending
codes = {'arrhythmic', {'arrhythmic:'}; 'capture', {'expected contractions included'}; ...
    'noContractions', {'no contractions'}; 'alternans', {'alternans:'}; 'irregular', {'irregular amplitudes:'}; ...
    'protocol', {'protocol '}; 'signal', {'chamber out', 'no signal', 'technical', ...
    'window partly without recording', 'no recording'}; 'otherSlice', {'other slice than in the baseline window'}; ...
    'comment', {'comment '}; 'pending', {'pending:'}};
if ~(ischar(note) || isstring(note)), note = ''; end
note = char(note);
c = {};
for i = 1:size(codes, 1)
    if any(cellfun(@(k) contains(note, k), codes{i, 2})), c{end+1} = codes{i, 1}; end %#ok<AGROW>
end
c = strjoin(c, ' ');
end


function E = excludeEntries(X)
% option 'exclude' as a cell array {id, channel, from_min, reason} per row
E = cell(0, 4);
if isempty(X), return; end
if istable(X)
    v = lower(X.Properties.VariableNames);
    col = @(names) find(ismember(v, names), 1);
    ki = col({'id', 'sampleid', 'sliceid', 'series'}); kc = col({'channel'}); kf = col({'from_min', 'from'});
    kr = col({'reason'});
    for r = 1:height(X)
        e = {char(string(X{r, ki})), [], [], ''};
        if ~isempty(kc), e{2} = X{r, kc}; end
        if ~isempty(kf), e{3} = X{r, kf}; end
        if ~isempty(kr), e{4} = char(string(X{r, kr})); end
        E(end+1, :) = e; %#ok<AGROW>
    end
elseif isstruct(X)
    for r = 1:numel(X)
        f = fieldnames(X(r)); lf = lower(f);
        get = @(names) X(r).(f{find(ismember(lf, names), 1)});
        e = {'', [], [], ''};
        if any(ismember(lf, {'id', 'sampleid', 'sliceid', 'series'}))
            e{1} = char(string(get({'id', 'sampleid', 'sliceid', 'series'})));
        end
        if any(ismember(lf, {'channel'})), e{2} = get({'channel'}); end
        if any(ismember(lf, {'from_min', 'from'})), e{3} = get({'from_min', 'from'}); end
        if any(ismember(lf, {'reason'})), e{4} = char(string(get({'reason'}))); end
        E(end+1, :) = e; %#ok<AGROW>
    end
elseif ischar(X) || isstring(X) || (iscell(X) && isvector(X) && all(cellfun(@(z) ischar(z) || isstring(z), X)))
    ids = cellstr(X);
    E = [ids(:), cell(numel(ids), 2), repmat({''}, numel(ids), 1)];
elseif iscell(X)
    if size(X, 2) > 4, X = X'; end
    for r = 1:size(X, 1)
        e = [X(r, :), cell(1, 4 - size(X, 2))];
        e{1} = char(string(e{1}));
        if isempty(e{4}), e{4} = ''; end
        E(end+1, :) = e; %#ok<AGROW>
    end
else
    error('mda_poolTimepoints: exclude: cell array, table or struct expected.');
end
for r = 1:size(E, 1)
    if isempty(E{r, 2}) || (isnumeric(E{r, 2}) && isnan(E{r, 2})), E{r, 2} = nan; else, E{r, 2} = double(E{r, 2}); end
    if isempty(E{r, 3}) || (isnumeric(E{r, 3}) && isnan(E{r, 3})), E{r, 3} = -inf; else, E{r, 3} = double(E{r, 3}); end
    E{r, 4} = char(string(E{r, 4}));
end
end


function [Sl, Ex, cut, notes, txt] = applyExclude(Sl, X)
% rows of the slices left out (option 'exclude'): kept rows, excluded rows (with excludeReason), minute from which the
% course and the average beats of a slice are left out (key analysis|series|channel), notes, text
E = excludeEntries(X);
drop = false(height(Sl), 1); why = repmat({''}, height(Sl), 1);
cut = containers.Map('KeyType', 'char', 'ValueType', 'double');
notes = {}; t = {};
for r = 1:size(E, 1)
    [id, ch, fr, rs] = E{r, :};
    m = strcmp(Sl.sampleID, id) | strcmp(Sl.series, id) | strcmp(Sl.sliceID, id);
    if ~isnan(ch), m = m & Sl.channel == ch; end
    w = id;
    if ~isnan(ch), w = sprintf('%s ch%d', w, ch); end
    if fr > -inf, w = sprintf('%s from %g min', w, fr); end
    if isempty(rs), t{end+1} = w; else, t{end+1} = [w ': ' rs]; end %#ok<AGROW>
    if ~any(m), notes{end+1} = ['exclude ' w ': no slice found']; continue; end %#ok<AGROW>
    m = m & Sl.offset_min >= fr;
    for k = find(m)'
        if isempty(why{k}), why{k} = rs;
        elseif ~any(strcmp(strsplit(why{k}, '; '), rs)), why{k} = [why{k} '; ' rs];
        end
        key = sprintf('%s|%s|%d', Sl.analysis{k}, Sl.series{k}, Sl.channel(k));
        if isKey(cut, key), cut(key) = min(cut(key), fr); else, cut(key) = fr; end
    end
    drop = drop | m;
end
Ex = [table(why(drop), 'VariableNames', {'excludeReason'}), Sl(drop, :)];
Sl = Sl(~drop, :);
txt = strjoin(t, '; ');
end


function [est, se, df, pv, th] = lmeRI(y, x, g)
% linear mixed model y ~ 1 + x + (1 | g) (random intercept per sample), REML: estimate of x, its SE, the degrees of
% freedom (n - 2, as fitlme 'Residual'), the p-value (t test) and the variance ratio sample / residual. The REML
% criterion is minimized over the variance ratio (grid and golden section, the same in MATLAB and Python).
y = double(y(:)); x = double(x(:)); n = numel(y);
X = [ones(n, 1), x]; p = 2;
[est, se, df, pv, th] = deal(nan);
if n - p < 1 || all(x == x(1)), return; end
[~, ~, gi] = unique(cellstr(string(g(:))));
G = max(gi);
m = accumarray(gi, 1, [G 1]);
Sx = [accumarray(gi, X(:, 1), [G 1]), accumarray(gi, X(:, 2), [G 1])];
Sy = accumarray(gi, y, [G 1]);
XtX = X' * X; Xty = X' * y; yty = y' * y;
    function [A, b, q, ld] = parts(t)
        c = t ./ (1 + t * m);
        A = XtX - (Sx .* c)' * Sx;
        b = Xty - (Sx .* c)' * Sy;
        q = yty - sum(c .* Sy .* Sy);
        ld = sum(log1p(t * m));
    end
    function v = crit(t)
        [A, b, q, ld] = parts(t);
        dA = A(1, 1) * A(2, 2) - A(1, 2) * A(2, 1);
        if ~(dA > 0), v = inf; return; end
        beta = [A(2, 2) * b(1) - A(1, 2) * b(2); A(1, 1) * b(2) - A(2, 1) * b(1)] / dA;
        s2 = (q - b' * beta) / (n - p);
        if ~(s2 > 0), v = inf; else, v = (n - p) * log(s2) + ld + log(dA); end
    end
us = linspace(-12, 8, 201);
cv = arrayfun(@(u) crit(exp(u)), us);
[~, k] = min(cv);
a = us(max(k - 1, 1)); bb = us(min(k + 1, numel(us)));
r = (sqrt(5) - 1) / 2;
c1 = bb - r * (bb - a); c2 = a + r * (bb - a);
f1 = crit(exp(c1)); f2 = crit(exp(c2));
for it = 1:80
    if f1 <= f2
        bb = c2; c2 = c1; f2 = f1; c1 = bb - r * (bb - a); f1 = crit(exp(c1));
    else
        a = c1; c1 = c2; f1 = f2; c2 = a + r * (bb - a); f2 = crit(exp(c2));
    end
end
th = exp((a + bb) / 2);
if crit(0) <= crit(th), th = 0; end
[A, b, q] = parts(th);
dA = A(1, 1) * A(2, 2) - A(1, 2) * A(2, 1);
beta = [A(2, 2) * b(1) - A(1, 2) * b(2); A(1, 1) * b(2) - A(2, 1) * b(1)] / dA;
s2 = (q - b' * beta) / (n - p);
se = sqrt(s2 * A(1, 1) / dA);
df = n - p;
tt = beta(2) / se;
pv = betainc(df / (df + tt^2), df / 2, 0.5);
est = beta(2);
end


function St = statisticsTable(Sl, pars, treat, ctrl)
% per treatment (not a control), time point after the baseline and normalized parameter, against the controls of the
% same time point: slices and samples, means and SEM, difference of the means, paired difference of the sample means
% (samples with both), linear mixed model (sample as random intercept; only with >= 3 samples in both groups)
names = {'treatment', 'control', 'offset_min', 'timePoint', 'parameter', 'nSlices', 'nSamples', 'mean', 'SEM', ...
    'nControlSlices', 'nControlSamples', 'controlMean', 'controlSEM', 'difference', 'nPairedSamples', ...
    'pairedDifference', 'pairedDifference_SEM', 'lme_estimate', 'lme_SE', 'lme_df', 'lme_p', 'lme_note'};
rows = cell(0, numel(names));
isC = ismember(Sl.treatment, ctrl);
if any(isC)
    for t = 1:numel(treat)
        if ismember(treat{t}, ctrl), continue; end
        for off = unique(Sl.offset_min(strcmp(Sl.treatment, treat{t})))'
            st = strcmp(Sl.treatment, treat{t}) & Sl.offset_min == off;
            if all(Sl.isBaseline(st) == 1), continue; end   %baseline window: normalized values 100 / 0
            sc = isC & Sl.offset_min == off;
            L = offsetLabels(off);
            for i = 1:numel(pars)
                c = normName(pars{i});
                v = Sl.(c);
                a_ = st & isfinite(v); b_ = sc & isfinite(v);
                yt = v(a_); yc = v(b_); gt = Sl.sampleID(a_); gc = Sl.sampleID(b_);
                ut = unique(gt); uc = unique(gc);
                if isempty(yt), mt = nan; else, mt = mean(yt); end
                if isempty(yc), mc = nan; else, mc = mean(yc); end
                both = intersect(ut, uc);
                d = nan(numel(both), 1);
                for k = 1:numel(both)
                    d(k) = mean(yt(strcmp(gt, both{k}))) - mean(yc(strcmp(gc, both{k})));
                end
                if isempty(d), md = nan; else, md = mean(d); end
                if numel(ut) >= 3 && numel(uc) >= 3
                    [e, se, df, pv] = lmeRI([yc; yt], [zeros(numel(yc), 1); ones(numel(yt), 1)], [gc; gt]);
                    nt = '';
                else
                    [e, se, df, pv] = deal(nan); nt = 'fewer than 3 samples in a group: descriptive only';
                end
                rows(end+1, :) = {treat{t}, strjoin(ctrl, ' '), off, L{1}, c, numel(yt), numel(ut), mt, ...
                    semOf(yt), numel(yc), numel(uc), mc, semOf(yc), mt - mc, numel(d), md, semOf(d), e, se, df, ...
                    pv, nt}; %#ok<AGROW>
            end
        end
    end
end
St = cell2table(rows, 'VariableNames', names);
if isempty(rows)
    St = cell2table(cell(0, numel(names)), 'VariableNames', names);
end
end


function writeSheet(T, x, sheet)
% table as a sheet; an empty table: only the header
if height(T) > 0
    writetable(T, x, 'Sheet', sheet);
else
    writecell(T.Properties.VariableNames, x, 'Sheet', sheet);
end
end


function T = infoTable(PT, treat)
k = {'function'; 'version'; 'implementation'; 'analysisDate'; 'name'; 'treatments'; 'controls'; 'parameters'; ...
    'units'; 'values'; 'vsControl'; 'samples'; 'treatmentsSheet'; 'course'; 'statistics'; 'qc'; 'exclude'; 'notes'};
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
    sprintf(['mean and SEM of the 1-min values of the slices per minute after the treatment (rounded); images: ' ...
    'solid = mean +- SEM where all slices have values, dashed = gaps of single slices up to %g min interpolated'], ...
    180); ...
    ['per treatment, time point after the baseline and normalized parameter against the controls of the same time ' ...
    'point: n, mean and SEM of the slices and samples, difference of the means, pairedDifference = mean of ' ...
    '(treatment - control) of the sample means of samples with both; lme_*: linear mixed model value ~ 1 + ' ...
    'treatment + (1 | sampleID), REML, t test with n - 2 degrees of freedom, only if both groups have >= 3 ' ...
    'samples (otherwise descriptive only); exploratory, not corrected for multiple comparisons']; ...
    ['codes of the notes of a window (column qc): arrhythmic (>= 5 % extra beats), capture (< 80 % of the ' ...
    'expected contractions included), noContractions, alternans, irregular (amplitudes), protocol, signal ' ...
    '(chamber out, no signal, window partly without recording), otherSlice, comment, pending']; ...
    excludeTextOrNone(PT); ...
    strjoin(PT.notes, '; ')};
T = table(k, v, 'VariableNames', {'key', 'value'});
end


function s = excludeTextOrNone(PT)
s = 'none';
if isfield(PT, 'excludeText') && ~isempty(PT.excludeText), s = PT.excludeText; end
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


function p = canonicalPath(p)
% absolute path without . and .. (java.io.File resolves relative paths against the folder MATLAB was started in,
% not against pwd)
p = char(p);
if isempty(regexp(p, '^([/\\]|[A-Za-z]:[/\\])', 'once')), p = fullfile(pwd, p); end
p = char(java.io.File(p).getCanonicalPath());
end
