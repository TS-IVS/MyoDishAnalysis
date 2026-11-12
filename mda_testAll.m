function ok = mda_testAll(varargin)
% All tests of MyoDishAnalysis in one call (2026-11-12): the test suites mda_test*.m of this folder and a smoke test
% of the GUI. To be run before every commit, together with the tests of the Python version (py: python -m pytest).
%
%   ok = mda_testAll                     all suites and the GUI smoke test
%   ok = mda_testAll('gui', false)       without the GUI smoke test (e.g. on a computer without a display)
%   ok = mda_testAll('only', 'Watch')    only the suites whose name contains the text (e.g. mda_testWatch)
%   ok = mda_testAll('log', file)        full output of the suites in this file (default <tempdir>/mda_testAll.log)
%
% The folder of this file is put on the MATLAB path for the run (the suites call the functions by name; one of them
% fails a check otherwise). A suite passes if it returns true and prints no line with FAILED.
% GUI smoke test: every example recording (examples/*.mdd) is opened in MyoDishAnalysisGUI; every channel is selected,
% every checkbox switched on and off and the side windows are opened (Overview, Comments, Protocols, Labels, Advanced,
% Trend, Overlay, Show table, Rocker artifact). It passes if no error occurs, nothing new is written to the error log
% of the GUI (<tempdir>/MyoDishAnalysisGUI_errors.log), the flag line shows flags and every one of these buttons was
% found in at least one recording (a renamed button must be renamed here too). Only the windows the test opened are
% closed.
%
% TS 2026-11-12

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE
p = struct('gui', true, 'only', '', 'log', fullfile(tempdir, 'mda_testAll.log'));
for i = 1:2:numel(varargin)
    if ~isfield(p, lower(char(varargin{i}))), error('mda_testAll: unknown option ''%s''.', char(varargin{i})); end
    p.(lower(char(varargin{i}))) = varargin{i+1};
end
here = fileparts(mfilename('fullpath'));
oldPath = path; addpath(here); restorePath = onCleanup(@() path(oldPath)); %#ok<NASGU>
d = dir(fullfile(here, 'mda_test*.m'));
names = setdiff(erase({d.name}, '.m'), {'mda_testAll'}, 'stable');
if ~isempty(p.only), names = names(contains(lower(names), lower(char(p.only)))); end
fid = fopen(p.log, 'w');
closeLog = onCleanup(@() fclose(fid)); %#ok<NASGU>
ok = true; t0 = tic;
for i = 1:numel(names)
    t = tic; pass = false;
    try
        [txt, r] = evalc(names{i});
        pass = isequal(r, true) && ~contains(txt, 'FAILED');
    catch ME
        txt = getReport(ME, 'extended', 'hyperlinks', 'off');
    end
    fprintf(fid, '===== %s: %s\n%s\n', names{i}, passText(pass), txt);
    fprintf('%-24s %-7s (%.0f s)\n', names{i}, passText(pass), toc(t));
    if ~pass, showFailed(txt); end
    ok = ok && pass;
end
if p.gui && isempty(p.only)
    t = tic;
    [pass, txt] = guiSmoke(here);
    fprintf(fid, '===== GUI smoke test: %s\n%s\n', passText(pass), txt);
    fprintf('%-24s %-7s (%.0f s)\n', 'GUI smoke test', passText(pass), toc(t));
    if ~pass, disp(txt); end
    ok = ok && pass;
end
if ok, fprintf('mda_testAll: all tests passed (%.0f s). Log: %s\n', toc(t0), p.log);
else, fprintf(2, 'mda_testAll: TESTS FAILED (%.0f s). Log: %s\n', toc(t0), p.log);
end
end


function s = passText(pass)
if pass, s = 'ok'; else, s = 'FAILED'; end
end


function showFailed(txt)
% the lines of a suite that say what failed (all of it if none does: an error report)
L = regexp(txt, '\r?\n', 'split');
k = contains(L, 'FAILED') | contains(L, 'Error') | startsWith(strtrim(L), 'case ');
if ~any(k), k = true(size(L)); end
L = L(k);
for i = 1:min(numel(L), 40), fprintf('      %s\n', L{i}); end
end


function [pass, txt] = guiSmoke(here)
buttons = {'Overview', 'Comments', 'Protocols', 'Labels', 'Advanced', 'Trend', 'Overlay', 'Show table', ...
    'Rocker artifact'};
found = false(size(buttons));
lf = fullfile(tempdir, 'MyoDishAnalysisGUI_errors.log');
n0 = 0; if isfile(lf), n0 = numel(fileread(lf)); end
d = dir(fullfile(here, 'examples', '*.mdd'));
lines = {}; pass = true;
if isempty(d), lines{end+1} = 'no example recordings (examples/*.mdd): nothing tested'; pass = false; end
for i = 1:numel(d)
    before = findall(groot, 'Type', 'figure');
    t = tic;
    try
        gf = MyoDishAnalysisGUI(fullfile(d(i).folder, d(i).name)); drawnow;
        pop = findall(gf, 'Style', 'popupmenu');
        isCh = false(size(pop));
        for q = 1:numel(pop), isCh(q) = any(startsWith(cellstr(pop(q).String), 'Ch ')); end
        chPop = pop(find(isCh, 1));
        nCh = numel(cellstr(chPop.String));
        for c = [1:nCh, 1]
            chPop.Value = c; feval(chPop.Callback, chPop, []); drawnow;
        end
        cb = findall(gf, 'Style', 'checkbox');
        for k = 1:numel(cb)
            for v = [~cb(k).Value, cb(k).Value]             %switched and back to its setting
                cb(k).Value = v;
                if ~isempty(cb(k).Callback), feval(cb(k).Callback, cb(k), []); end
                drawnow;
            end
        end
        btn = findall(gf, 'Style', 'pushbutton');
        s = arrayfun(@(b) strjoin(cellstr(b.String), ' '), btn, 'UniformOutput', false);
        for j = 1:numel(buttons)
            k = find(startsWith(s, buttons{j}) & strcmp(get(btn, {'Enable'}), 'on'), 1);
            if isempty(k), continue; end
            found(j) = true;
            feval(btn(k).Callback, btn(k), []); drawnow;
        end
        st = findall(gf, 'Style', 'text');
        tx = strtrim(arrayfun(@(b) strjoin(cellstr(b.String), ' '), st, 'UniformOutput', false));
        fl = tx(startsWith(tx, 'Flags'));
        good = ~isempty(fl) && ~any(contains(fl, 'could not be computed'));
        if ~good, pass = false; end
        lines{end+1} = sprintf('%-32s %d channel(s), %.0f s, flag line %s | %s', d(i).name, nCh, toc(t), ...
            passText(good), strjoin(fl, ' / ')); %#ok<AGROW>
    catch ME
        pass = false;
        lines{end+1} = sprintf('%-32s ERROR %s', d(i).name, ME.message); %#ok<AGROW>
    end
    new = findall(groot, 'Type', 'figure');
    if ~isempty(before), new = new(~ismember(new, before)); end
    for k = 1:numel(new), try, delete(new(k)); catch, end, end %#ok<TRYNC>
    drawnow;
end
if ~isempty(d) && ~all(found)
    pass = false;
    lines{end+1} = ['buttons not found in any recording (renamed? then rename them in mda_testAll): ' ...
        strjoin(buttons(~found), ', ')];
end
if isfile(lf)
    e = fileread(lf);
    if numel(e) > n0
        pass = false;
        lines{end+1} = sprintf('new entries in the error log of the GUI (%s):\n%s', lf, e(n0+1:end));
    end
end
txt = strjoin(lines, newline);
end
