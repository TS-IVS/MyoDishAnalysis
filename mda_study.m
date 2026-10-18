function R = mda_study(design, varargin)
%MDA_STUDY  Time points of a study from a design table: mda_timepoints per treatment and mda_poolTimepoints with the
%exclusions, all in one study folder, with a copy of the design, a figure, tables for Prism and a methods text.
%
%   R = mda_study('design.xlsx')
%   R = mda_study('design.xlsx', 'resultsFolder', '/data/results', 'name', 'PKC_rabbit')
%   mda_study('template', 'design.xlsx')            design table to fill in (one example row, settings)
%
% DESIGN TABLE (sheet slices of an .xlsx file, or a .csv file; one row per slice; or a table):
%   series         recordings of one setup: the file name up to its number (Setup1_ABC000101 for
%                  Setup1_ABC000101_3.mdd)
%   channel        channel of the slice
%   treatment      name of the treatment (label of mda_timepoints: letters, digits, '.', '-', '_'), e.g. PMA50nM
%   time           clock time of the treatment ('yyyy-mm-dd HH:MM[:SS]'; with t0 = chamberIn the documented time)
%   sampleID       sample (heart, tissue) of the slice (default: slice register or series name)
%   group          group of the sample (optional)
%   exclude        empty, 'all' (whole slice) or the offset (min) from which the windows are left out
%   excludeReason  reason of the exclusion (sheet excluded, methods text)
% SETTINGS (sheet settings of the .xlsx file: key, value; or name, value pairs, which have priority):
%   resultsFolder (results folder of the watcher; required), name (default 'study'), outputFolder (default
%   <resultsFolder>/studies/<name>), offsets (minutes, e.g. '-30 10 60 180 360 720 1380'; required), seconds (default
%   120), baseline (default: the last negative offset), t0 ('given' or 'chamberIn', default 'given'), t0Window
%   (default 90), control and order (treatments, separated by spaces), parameters (default those of mda_timepoints),
%   rawFolder, averageBeats (default true), figures (default true)
%
% OUTPUT (study folder): analyses/<experiment>/<label>_<time>/ (mda_timepoints per treatment, all its slices), the
% files of mda_poolTimepoints (<name>.xlsx with slices, samples, treatments, statistics, qc, excluded, course,
% averageBeatsMean, analyses, info; images; <name>_figure_norm .pdf/.svg/.png; <name>_prism.xlsx), the design
% (design_<name>.xlsx or .csv) and <name>_methods.txt (methods text for a manuscript, generated from the settings, the
% groups and the exclusions; check it before use).
%
% R  struct: name, folder, design (table), settings, analyses (folders), pool (struct of mda_poolTimepoints), methods
%    (text), files
%
% Python: myodish_analysis.study.study, study_template; command line mda-study (same arguments, files and values).
%
% TS 2026-10-18

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

S0 = settingsList();
if (ischar(design) || isstring(design)) && strcmp(design, 'template')
    R = writeTemplate(char(varargin{1}), S0);
    return;
end
[D, settings] = readDesign(design);
P = struct();
for i = 1:size(S0, 1), P.(S0{i, 1}) = S0{i, 2}; end
f = fieldnames(settings);
for i = 1:numel(f), if isfield(P, f{i}), P.(f{i}) = settings.(f{i}); end, end
if mod(numel(varargin), 2) ~= 0, error('mda_study: settings as name, value pairs expected.'); end
for i = 1:2:numel(varargin)
    k = char(varargin{i});
    if ~isfield(P, k), error('mda_study: unknown setting %s.', k); end
    P.(k) = textOf(varargin{i+1});
end
if isempty(P.resultsFolder), error('mda_study: resultsFolder: the results folder of the watcher expected.'); end
off = str2double(listOf(P.offsets));
if isempty(off) || any(isnan(off))
    error('mda_study: offsets: minutes after the treatment expected, e.g. -30 10 60.');
end
name = P.name; if isempty(name), name = 'study'; end
if isempty(regexp(name, '^[A-Za-z0-9._-]+$', 'once'))
    error('mda_study: name: letters, digits, ''.'', ''-'' and ''_'' expected.');
end
folder = P.outputFolder;
if isempty(folder), folder = fullfile(P.resultsFolder, 'studies', name); end
if ~isfolder(folder), mkdir(folder); end
b = lower(strtrim(P.baseline));
if isempty(b), baseline = []; elseif strcmp(b, 'none'), baseline = 'none'; else, baseline = str2double(b); end
figs = isTrue(P.figures); avg = isTrue(P.averageBeats);
pars = listOf(P.parameters);
kw = {'baseline', baseline, 'write', true, 'figures', figs, 'averageBeats', avg, 'rawFolder', P.rawFolder, ...
    't0', P.t0, 't0Window', str2double(P.t0Window), 'outputFolder', fullfile(folder, 'analyses')};
if ~isempty(pars), kw = [kw, {'parameters', pars}]; end
folders = {};
tr = unique(D.treatment, 'stable');
for t = 1:numel(tr)                                 %one call of mda_timepoints per treatment, all its slices
    Dt = D(strcmp(D.treatment, tr{t}), :);
    S = unique(Dt.series, 'stable')';
    ch = cell(1, numel(S)); tm = {}; smp = cell(1, numel(S)); grp = smp;
    for s = 1:numel(S)
        r = strcmp(Dt.series, S{s});
        ch{s} = Dt.channel(r)';
        tm = [tm; Dt.time(r)]; %#ok<AGROW>
        u = unique(Dt.sampleID(r), 'stable'); g = unique(Dt.group(r), 'stable');
        if numel(u) > 1, error('mda_study: design: treatment %s, series %s: one sampleID expected.', tr{t}, S{s}); end
        if numel(g) > 1, error('mda_study: design: treatment %s, series %s: one group expected.', tr{t}, S{s}); end
        smp{s} = u{1}; grp{s} = g{1};
    end
    if all(cellfun(@isempty, smp)), smp = ''; end
    if all(cellfun(@isempty, grp)), grp = ''; end
    TP = mda_timepoints(P.resultsFolder, tr{t}, S, ch, tm, off, str2double(P.seconds), 'sampleID', smp, ...
        'group', grp, kw{:});
    if iscell(TP.folder), folders = [folders, TP.folder(:)']; else, folders{end+1} = TP.folder; end %#ok<AGROW>
end
ex = cell(0, 4);
for r = 1:height(D)
    e = D.exclude{r};
    if isempty(e), continue; end
    if strcmpi(e, 'all'), fr = []; else, fr = str2double(e); end
    ex(end+1, :) = {D.series{r}, D.channel(r), fr, D.excludeReason{r}}; %#ok<AGROW>
end
PT = mda_poolTimepoints(folders, 'order', listOf(P.order), 'name', name, 'outputFolder', folder, 'figures', ...
    figs, 'control', listOf(P.control), 'exclude', ex);
if istable(design)
    dc = fullfile(folder, ['design_' name '.xlsx']);
    if isfile(dc), delete(dc); end
    writetable(D, dc, 'Sheet', 'slices');
    writetable(table(S0(:, 1), cellfun(@(k) P.(k), S0(:, 1), 'UniformOutput', false), 'VariableNames', ...
        {'key', 'value'}), dc, 'Sheet', 'settings');
else
    [~, ~, ext] = fileparts(char(design));
    dc = fullfile(folder, ['design_' name lower(ext)]);
    if ~strcmp(canonicalPath(design), canonicalPath(dc)), copyfile(char(design), dc); end
end
M = methodsText(PT, P, off);
mf = fullfile(folder, [name '_methods.txt']);
fid = fopen(mf, 'w', 'n', 'UTF-8'); fprintf(fid, '%s\n', M); fclose(fid);
R = struct('name', name, 'folder', folder, 'design', D, 'settings', P, 'analyses', {folders}, 'pool', PT, ...
    'methods', M, 'files', {[PT.files, {dc, mf}]});
end


% =====================================================================================================================
function S = settingsList()
S = {'resultsFolder', '', 'results folder of the watcher (folder with mda_index.csv); required'; ...
    'name', 'study', 'name of the study: folder and workbook'; ...
    'outputFolder', '', 'folder of the study (default <resultsFolder>/studies/<name>)'; ...
    'offsets', '', 'start of the windows in minutes after the treatment, e.g. -30 10 60 180; required'; ...
    'seconds', '120', 'duration of every window (s)'; ...
    'baseline', '', 'offset of the reference window (default: the last negative offset; none: no baseline)'; ...
    't0', 'given', ['time 0: given (the time of the design) or chamberIn (end of the chamber-out period of the ' ...
    'channel nearest to it)']; ...
    't0Window', '90', 'chamberIn: periods ending within +- this many minutes of the given time'; ...
    'control', '', ['treatments that are controls, separated by spaces (default: labels starting with CTRL, ' ...
    'control, vehicle or DMSO)']; ...
    'order', '', 'order of the treatments in the images, separated by spaces'; ...
    'parameters', '', 'parameters, separated by spaces (default those of timepoints)'; ...
    'rawFolder', '', 'raw folder of the watcher (average beats; default: the path of the analysis)'; ...
    'averageBeats', 'true', 'average beats from the raw data (true / false)'; ...
    'figures', 'true', 'images (true / false)'};
end


function f = writeTemplate(f, S0)
% design table to fill in: sheet slices (example rows) and sheet settings (keys, defaults, descriptions)
D = table({'Setup1_ABC000101'; 'Setup1_ABC000101'}, [1; 2], {'CTRL'; 'PMA50nM'}, {'2000-01-01 12:00'; ...
    '2000-01-01 12:00'}, {'ABC000101'; 'ABC000101'}, {''; ''}, {''; '720'}, {''; 'arrhythmic from +12 h'}, ...
    'VariableNames', designColumns());
v = S0(:, 2); v{strcmp(S0(:, 1), 'offsets')} = '-30 10 60 180 360 720 1380';
if isfile(f), delete(f); end
writetable(D, f, 'Sheet', 'slices');
writetable(table(S0(:, 1), v, S0(:, 3), 'VariableNames', {'key', 'value', 'description'}), f, 'Sheet', 'settings');
end


function c = designColumns()
c = {'series', 'channel', 'treatment', 'time', 'sampleID', 'group', 'exclude', 'excludeReason'};
end


function [D, settings] = readDesign(design)
% design table (cellstr columns, channel numeric) and the settings of the file
settings = struct();
if istable(design)
    T = design;
else
    f = char(design);
    [~, ~, ext] = fileparts(f);
    if any(strcmpi(ext, {'.xlsx', '.xls'}))
        sh = sheetnames(f);
        s = 'slices'; if ~any(strcmp(sh, s)), s = sh(1); end
        o = detectImportOptions(f, 'Sheet', s, 'VariableNamingRule', 'preserve');
        o = setvartype(o, o.VariableNames, 'char');
        T = readtable(f, o, 'Sheet', s);
        if any(strcmp(sh, 'settings'))
            o = detectImportOptions(f, 'Sheet', 'settings');
            o = setvartype(o, o.VariableNames, 'char');
            St = readtable(f, o, 'Sheet', 'settings');
            for r = 1:height(St)
                k = textOf(St{r, 1}); if ~isempty(k), settings.(k) = textOf(St{r, 2}); end
            end
        end
    else
        o = detectImportOptions(f, 'Delimiter', ',', 'VariableNamingRule', 'preserve');
        o = setvartype(o, o.VariableNames, 'char');
        T = readtable(f, o);
    end
end
T.Properties.VariableNames = strtrim(T.Properties.VariableNames);
miss = setdiff({'series', 'channel', 'treatment', 'time'}, T.Properties.VariableNames, 'stable');
if ~isempty(miss), error('mda_study: design: columns missing: %s', strjoin(miss, ', ')); end
n = height(T);
D = table();
for c = designColumns()
    if ismember(c{1}, T.Properties.VariableNames)
        x = T.(c{1});
        if isnumeric(x) || islogical(x), x = arrayfun(@textOf, x, 'UniformOutput', false);
        elseif isdatetime(x), x = cellstr(string(x, 'yyyy-MM-dd HH:mm:ss'));
        else, x = cellfun(@textOf, cellstr(string(x)), 'UniformOutput', false);
        end
        x(strcmp(x, 'NaN') | strcmp(x, '<missing>')) = {''};
    else
        x = repmat({''}, n, 1);
    end
    D.(c{1}) = x(:);
end
D = D(~cellfun(@isempty, D.series), :);
if height(D) == 0, error('mda_study: design: no slices.'); end
D.channel = str2double(D.channel);
for t = D.treatment'
    if isempty(regexp(t{1}, '^[A-Za-z0-9._-]+$', 'once'))
        error('mda_study: design: treatment ''%s'': letters, digits, ''.'', ''-'' and ''_'' expected.', t{1});
    end
end
end


function s = textOf(v)
if isempty(v), s = ''; return; end
if iscell(v), v = v{1}; end
if isdatetime(v), s = char(string(v, 'yyyy-MM-dd HH:mm:ss')); return; end
if islogical(v), if v, s = 'true'; else, s = 'false'; end, return; end
if isnumeric(v)
    if isempty(v) || all(isnan(v)), s = ''; return; end
    s = strjoin(arrayfun(@(x) num2str(x, 15), v(:)', 'UniformOutput', false), ' ');
    return;
end
s = strtrim(char(string(v)));
end


function c = listOf(v)
if iscell(v), c = cellfun(@textOf, v(:)', 'UniformOutput', false); return; end
v = textOf(v);
if isempty(v), c = {}; else, c = regexp(v, '[\s,;]+', 'split'); c = c(~cellfun(@isempty, c)); end
end


function tf = isTrue(v)
v = lower(textOf(v));
tf = ~ismember(v, {'false', '0', 'no', ''});
end


function s = minutesText(off)
x = cell(1, numel(off));
for i = 1:numel(off)
    o = off(i);
    if o == 0, x{i} = '0 min';
    elseif mod(o, 60) == 0, x{i} = sprintf('%+g h', o / 60);
    else, x{i} = sprintf('%+g min', o);
    end
end
s = strjoin(x, ', ');
end


function s = methodsText(PT, P, off)
% methods paragraph for a manuscript (English; check before use)
Sl = PT.slices; Ex = PT.excluded;
b = lower(strtrim(P.baseline));
if strcmp(b, 'none'), bo = [];
elseif ~isempty(b), bo = str2double(b);
else, bo = max(off(off < 0));
end
if any(strcmpi(P.t0, {'', 'given'}))
    t0 = 'the documented time of the addition';
else
    t0 = sprintf(['the reinsertion of the chamber after the addition (end of the chamber-out period of the channel ' ...
        'nearest to the documented time, within %s%s min)'], char(177), P.t0Window);
end
s = sprintf(['Contraction parameters were analysed with MyoDishAnalysis %s from the results of its automatic batch ' ...
    'analysis (watcher). For every slice, the parameters of the contractions were averaged in windows of %s s ' ...
    'starting %s relative to the treatment (time 0 = %s). In paced slices, only stimulated contractions were ' ...
    'averaged; windows with %s 5 %% extra beats were marked as arrhythmic.'], mda_version(), P.seconds, ...
    minutesText(off), t0, char(8805));
if ~isempty(bo)
    s = [s sprintf([' Values were normalized to the window %g min before the treatment of the same slice ' ...
        '(%% of baseline); the diastolic force is given as change from this window (%sN).'], abs(bo), char(181))];
end
tr = unique(PT.treatments.treatment, 'stable');
g = cell(1, numel(tr));
for t = 1:numel(tr)
    St = Sl(strcmp(Sl.treatment, tr{t}), :);
    nS = numel(unique(strcat(St.sampleID, '|', St.sliceID))); nP = numel(unique(St.sampleID));
    g{t} = sprintf('%s %d slice%s from %d sample%s', tr{t}, nS, repmat('s', 1, nS ~= 1), nP, repmat('s', 1, nP ~= 1));
end
s = [s ' Groups: ' strjoin(g, '; ') '.'];
if height(Ex) > 0
    key = strcat(Ex.sampleID, '|', Ex.sliceID, '|', Ex.excludeReason);
    [u, iu] = unique(key, 'stable');
    x = cell(1, numel(u));
    for i = 1:numel(u)
        o = Ex.offset_min(strcmp(key, u{i}));
        if min(o) <= min(off), w = 'all windows'; else, w = ['windows from ' minutesText(min(o))]; end
        why = Ex.excludeReason{iu(i)};
        if isempty(why), x{i} = sprintf('%s %s (%s)', Ex.sampleID{iu(i)}, Ex.sliceID{iu(i)}, w);
        else, x{i} = sprintf('%s %s (%s; %s)', Ex.sampleID{iu(i)}, Ex.sliceID{iu(i)}, w, why);
        end
    end
    s = [s ' Excluded: ' strjoin(x, '; ') '.'];
end
St = PT.statistics;
if height(St) > 0 && any(~isnan(St.lme_p))
    s = [s sprintf([' Treatments were compared with the controls of the same time point by a linear mixed model ' ...
        'with the sample as random intercept (REML; t test with n %s 2 degrees of freedom); data are mean %s SEM ' ...
        'of the slices.'], char(8722), char(177))];
else
    s = [s sprintf([' Data are mean %s SEM of the slices; with fewer than 3 samples per group the data are shown ' ...
        'descriptively.'], char(177))];
end
end


function p = canonicalPath(p)
% absolute path without . and .. (java.io.File resolves relative paths against the folder MATLAB was started in,
% not against pwd)
p = char(p);
if isempty(regexp(p, '^([/\\]|[A-Za-z]:[/\\])', 'once')), p = fullfile(pwd, p); end
p = char(java.io.File(p).getCanonicalPath());
end
