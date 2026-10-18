function [h, files] = mda_plotTimepoints(PT, varargin)
%MDA_PLOTTIMEPOINTS  Figure for a manuscript from a pool of mda_poolTimepoints: per parameter one panel, x = time after
%the treatment, per treatment the mean +- SEM of the slices (markers, error bars, line) and the single slices (thin
%lines). Also the tables for GraphPad Prism.
%
%   [h, files] = mda_plotTimepoints(PT)
%   [h, files] = mda_plotTimepoints(PT, 'parameters', {'amplitude', 'diastolicForce'}, 'output', 'fig2')
%   T = mda_plotTimepoints('prism', PT)
%
%   PT     struct of mda_poolTimepoints or its workbook <name>.xlsx
% OPTIONS
%   'parameters'  parameters (default amplitude, diastolicForce, TTP90, TTR90 if pooled)
%   'treatments'  treatments and their order (default: the order of the pool)
%   'mode'        'norm' (default: % of baseline, diastolic force: change in uN), 'abs' or 'vsControl'
%   'slices'      thin lines of the single slices (default true)
%   'output'      file name without extension: files <output>.pdf / .svg / .png (300 dpi); default none
%   'formats'     default {'pdf', 'svg', 'png'}
%   'panelSize'   [width height] of a panel in mm (default [60 45]); 'ncols' panels per row (default 2)
%   'fontSize'    pt (default 7; Arial); 'timeUnit' 'h' (default) or 'min'; 'colors' colours of the treatments that
%                 are not controls (default Okabe-Ito, colour-blind safe; controls black)
%
% Legend: treatment (n = slices / samples). Prism tables (T.<value column>): one row per time point (time_h or
% time_min), per treatment one column per slice (header 'treatment|sample slice'); the pool writes them to
% <name>_prism.xlsx and the figure (normalized) to <name>_figure_norm.pdf / .svg / .png.
%
% Python: myodish_analysis.timepoints.plot_timepoints, prism_tables (same options and tables).
%
% TS 2026-10-18

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

if (ischar(PT) || isstring(PT)) && strcmp(PT, 'prism')
    h = prismTables(varargin{1}, varargin{2:end});
    files = {};
    return;
end
P = struct('parameters', {{}}, 'treatments', {{}}, 'mode', 'norm', 'slices', true, 'output', '', ...
    'formats', {{'pdf', 'svg', 'png'}}, 'panelSize', [60 45], 'ncols', [], 'fontSize', 7, 'timeUnit', 'h', ...
    'colors', []);
if mod(numel(varargin), 2) ~= 0, error('mda_plotTimepoints: options as name, value pairs expected.'); end
for i = 1:2:numel(varargin)
    P.(validatestring(varargin{i}, fieldnames(P))) = varargin{i+1};
end
[Sl, tr, ctrl, pars0, units0] = poolSlices(PT);
pars = cellstr(P.parameters);
if isempty(pars), pars = defaultParameters(Sl); end
if ~isempty(P.treatments), tr = cellstr(P.treatments); end
tr = tr(ismember(tr, unique(Sl.treatment)));
if strcmp(P.timeUnit, 'h'), f = 60; else, f = 1; end
nc = P.ncols; if isempty(nc), nc = min(2, numel(pars)); end
nr = ceil(numel(pars) / nc);
oi = [0.902 0.624 0; 0.337 0.706 0.914; 0 0.620 0.451; 0 0.447 0.698; 0.835 0.369 0; 0.800 0.475 0.655; ...
    0.6 0.6 0.6];                                   %Okabe-Ito
if ~isempty(P.colors), oi = P.colors; end
col = zeros(numel(tr), 3); k = 0;
for t = 1:numel(tr)
    if ismember(tr{t}, ctrl), col(t, :) = [0 0 0];
    else, k = k + 1; if k <= size(oi, 1), col(t, :) = oi(k, :); else, col(t, :) = [0.5 0.5 0.5]; end
    end
end
mm = 1 / 25.4;
h = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', 'Position', [1 1 nc * P.panelSize(1) * mm ...
    nr * P.panelSize(2) * mm]);
t0 = tiledlayout(h, nr, nc, 'TileSpacing', 'compact', 'Padding', 'compact');
lh = gobjects(0); ll = {};
for i = 1:numel(pars)
    ax = nexttile(t0); hold(ax, 'on');
    v = valueColumn(pars{i}, P.mode);
    for t = 1:numel(tr)
        St = Sl(strcmp(Sl.treatment, tr{t}), :);
        key = strcat(St.sampleID, '|', St.sliceID);
        [ku, ~] = unique(key, 'stable');
        if P.slices
            for s = 1:numel(ku)
                g = St(strcmp(key, ku{s}), :); g = sortrows(g, 'offset_min');
                plot(ax, g.offset_min / f, g.(v), '-', 'Color', [col(t, :) 0.35], 'LineWidth', 0.4, ...
                    'HandleVisibility', 'off');
            end
        end
        [g, x] = findgroups(St.offset_min);
        m = splitapply(@(z) mean(z, 'omitnan'), St.(v), g);
        e = splitapply(@semOf, St.(v), g); e(isnan(e)) = 0;
        hb = errorbar(ax, x / f, m, e, '-o', 'Color', col(t, :), 'LineWidth', 1.0, 'MarkerSize', 2.5, ...
            'MarkerFaceColor', col(t, :), 'CapSize', 2);
        if i == 1
            lh(end+1) = hb; %#ok<AGROW>
            ll{end+1} = sprintf('%s (n = %d/%d)', tr{t}, numel(ku), numel(unique(St.sampleID))); %#ok<AGROW>
        end
    end
    if ~strcmp(P.mode, 'abs')
        if strcmp(pars{i}, 'diastolicForce') && strcmp(P.mode, 'norm'), y0 = 0; else, y0 = 100; end
        yline(ax, y0, '--', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.5, 'HandleVisibility', 'off');
    end
    xline(ax, 0, ':', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.5, 'HandleVisibility', 'off');
    u = '';
    ip = find(strcmp(pars0, pars{i}), 1);
    if ~isempty(ip) && ~isempty(units0), u = units0{ip}; end
    switch P.mode
        case 'abs', if isempty(u), yl = pars{i}; else, yl = sprintf('%s (%s)', pars{i}, u); end
        case 'norm'
            if strcmp(pars{i}, 'diastolicForce'), yl = 'diastolic force, change (uN)';
            else, yl = sprintf('%s (%% of baseline)', pars{i}); end
        otherwise
            if strcmp(pars{i}, 'diastolicForce'), yl = 'diastolic force - control (uN)';
            else, yl = sprintf('%s (%% of control)', pars{i}); end
    end
    ylabel(ax, yl, 'Interpreter', 'none');
    xlabel(ax, ['time after the treatment (' P.timeUnit ')']);
    set(ax, 'FontName', 'Arial', 'FontSize', P.fontSize, 'LineWidth', 0.6, 'TickDir', 'out', 'Box', 'off');
end
lg = legend(lh, ll, 'Interpreter', 'none', 'Box', 'off', 'Orientation', 'horizontal', 'FontName', 'Arial', ...
    'FontSize', P.fontSize);
lg.Layout.Tile = 'north';
files = {};
if ~isempty(P.output)
    for k = 1:numel(P.formats)
        fn = sprintf('%s.%s', char(P.output), P.formats{k});
        switch P.formats{k}
            case 'pdf', exportgraphics(h, fn, 'ContentType', 'vector');
            case 'png', exportgraphics(h, fn, 'Resolution', 300);
            case 'svg', print(h, fn, '-dsvg', '-vector');
            otherwise, saveas(h, fn);
        end
        files{end+1} = fn; %#ok<AGROW>
    end
end
end


function T = prismTables(PT, varargin)
% tables for GraphPad Prism per parameter: one row per time point, per treatment one column per slice
P = struct('parameters', {{}}, 'mode', 'norm', 'timeUnit', 'h');
for i = 1:2:numel(varargin), P.(validatestring(varargin{i}, fieldnames(P))) = varargin{i+1}; end
[Sl, tr] = poolSlices(PT);
pars = cellstr(P.parameters);
if isempty(pars), pars = defaultParameters(Sl); end
if strcmp(P.timeUnit, 'h'), f = 60; else, f = 1; end
off = unique(Sl.offset_min);
T = struct();
for i = 1:numel(pars)
    v = valueColumn(pars{i}, P.mode);
    X = table(off / f, 'VariableNames', {['time_' P.timeUnit]});
    for t = 1:numel(tr)
        St = Sl(strcmp(Sl.treatment, tr{t}), :);
        key = strcat(St.sampleID, '|', St.sliceID);
        ku = unique(key, 'stable');
        for s = 1:numel(ku)
            g = St(strcmp(key, ku{s}), :);
            c = nan(numel(off), 1);
            [~, k] = ismember(g.offset_min, off);
            c(k) = g.(v);
            parts = strsplit(ku{s}, '|');
            X.(sprintf('%s|%s %s', tr{t}, parts{1}, parts{2})) = c;
        end
    end
    T.(v) = X;
end
end


function [Sl, tr, ctrl, pars, units] = poolSlices(PT)
% slices table, treatments, controls, parameters and units of a pool (struct or workbook)
if isstruct(PT)
    Sl = PT.slices; tr = unique(PT.treatments.treatment, 'stable')'; ctrl = cellstr(PT.controls);
    pars = PT.parameters; units = PT.units;
else
    x = char(PT);
    o = detectImportOptions(x, 'Sheet', 'slices', 'VariableNamingRule', 'preserve');
    txt = intersect({'treatment', 'substance', 'concentrationUnit', 'group', 'sampleID', 'sliceID', 'timePoint', ...
        'series', 'treatmentTime', 'from', 'to', 'recording', 'note', 'qc', 'analysis', 'controlReference'}, ...
        o.VariableNames);
    o = setvartype(o, txt, 'char');
    o = setvartype(o, setdiff(o.VariableNames, txt), 'double');
    Sl = readtable(x, o, 'Sheet', 'slices');
    Tr = readtable(x, 'Sheet', 'treatments', 'VariableNamingRule', 'preserve', 'TextType', 'char');
    tr = unique(Tr.treatment, 'stable')';
    I = readtable(x, 'Sheet', 'info', 'TextType', 'char');
    c = I.value(strcmp(I.key, 'controls'));
    if isempty(c) || isempty(c{1}), ctrl = {}; else, ctrl = strsplit(c{1}); end
    p = I.value(strcmp(I.key, 'parameters')); pars = strsplit(p{1});
    u = I.value(strcmp(I.key, 'units')); u = strsplit(u{1});
    units = cell(size(pars));
    for i = 1:numel(u)
        q = strsplit(u{i}, '='); j = find(strcmp(pars, q{1}), 1);
        if ~isempty(j) && numel(q) > 1, units{j} = q{2}; end
    end
end
for c = {'treatment', 'sampleID', 'sliceID'}
    Sl.(c{1}) = cellstr(string(Sl.(c{1})));
end
end


function pars = defaultParameters(Sl)
pars = {'amplitude', 'diastolicForce', 'TTP90', 'TTR90'};
pars = pars(ismember(pars, Sl.Properties.VariableNames));
end


function v = valueColumn(p, mode)
switch mode
    case 'abs', v = p;
    case 'norm', if strcmp(p, 'diastolicForce'), v = 'diastolicForce_delta'; else, v = [p '_pctBaseline']; end
    case 'vsControl'
        if strcmp(p, 'diastolicForce'), v = 'diastolicForce_delta_vsControl';
        else, v = [p '_pctBaseline_vsControl']; end
    otherwise, error('mda_plotTimepoints: mode: ''norm'', ''abs'' or ''vsControl'' expected.');
end
end


function s = semOf(x)
x = x(~isnan(x));
if numel(x) < 2, s = nan; else, s = std(x) / sqrt(numel(x)); end
end
