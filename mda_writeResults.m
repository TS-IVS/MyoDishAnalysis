function outFiles = mda_writeResults(outputFile, contractions, summary, info, varargin)
%MDA_WRITERESULTS  Write contraction table, summary and analysis info to Excel (.xlsx) or text (.csv).
%
%   mda_writeResults('results.xlsx', contractions, summary, info)
%       sheets: contractions, summary, parameters (definitions), info (file facts, version and all options),
%       thresholds (analysis windows: data window read, analysed range and detection threshold per channel and chunk;
%       used to open the results in MyoDishAnalysisGUI), labels, rockerFilter (option 'rockerFilter': result per
%       channel and time range), protocols (option 'protocol'), protocolResults (characteristic values per protocol
%       and channel, mda_protocolResults), pulses (all stimulus pulses of the analysed channels and ranges, option
%       pulseTable; > 1048575 rows: <name>_pulses.csv)
%   mda_writeResults('results.csv', ...)
%       results_contractions.csv, results_summary.csv, results_parameters.csv, results_info.csv, ...
%   mda_writeResults(..., 'csvTables', {'contractions', 'pulses'}, 'compress', true, 'sheets', {name, T; ...})
%       (2026-10-14; results of the watcher) 'csvTables': these tables of an .xlsx file as <name>_<table>.csv next to
%       it (large tables: much faster to write and read, no row limit); 'compress', true: as .csv.gz (gzip);
%       'sheets': further tables, after the summary (.csv: <name>_<sheet>.csv). A table with more rows than Excel
%       allows (1048575) is always written as <name>_<table>.csv. contractions = []: no contraction table.
%   T = mda_writeResults(info)
%       only the info table (key, value): file, ..., software, version, implementation, notes, info.extra (rows
%       {key, value}, e.g. createdBy, channels, loadedWindow_s), option_<name> for every option, log file entries
%
% Existing sheets of the same name are overwritten (MATLAB R2020a or newer; older releases: the sheet is
% written over, rows of a longer old table may remain).
%
% TS 2026-10-05 (version, implementation, extra rows, thresholds sheet, info table only 2026-10-09)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

if nargin == 1 && isstruct(outputFile)              %info table only (GUI exports of plotted data)
    outFiles = infoTableOf(outputFile);
    return;
end
P = struct('csvTables', {{}}, 'compress', false, 'sheets', {cell(0, 2)});
pn = fieldnames(P);
for i = 1:2:numel(varargin)
    k = find(strcmpi(pn, char(varargin{i})), 1);
    if isempty(k) || i == numel(varargin), error('mda_writeResults: unknown option or missing value: %s.', char(varargin{i})); end
    P.(pn{k}) = varargin{i+1};
end
P.csvTables = cellstr(P.csvTables);
P.sheets = reshape(P.sheets, [], 2);
[p, n, e] = fileparts(outputFile);
if isempty(e), e = '.xlsx'; outputFile = fullfile(p, [n e]); end

PI = mda_parameters();
paramTable = cell2table(PI, 'VariableNames', {'parameter','unit','definition'});
% 2026-10-06: parameters relative to the reference beat (if present in the contraction table)
if istable(contractions)
    rel = contractions.Properties.VariableNames(endsWith(contractions.Properties.VariableNames, {'_pctRef', '_dRef'}));
    for k = 1:numel(rel)
        if endsWith(rel{k}, '_dRef')
            d = {rel{k}, 'uN', sprintf('%s - mean of the reference contractions (reference beat of the channel)', erase(rel{k}, '_dRef'))};
        else
            d = {rel{k}, '%', sprintf('100 * %s / mean of the reference contractions (reference beat of the channel)', erase(rel{k}, '_pctRef'))};
        end
        paramTable = [paramTable; cell2table(d, 'VariableNames', {'parameter','unit','definition'})]; %#ok<AGROW>
    end
    % 2026-10-06: AP parameters of an EP recording (mda_analyzeAP)
    AP = mda_analyzeAP('parameters');
    AP = AP(ismember(AP(:,1), contractions.Properties.VariableNames), :);
    if ~isempty(AP)
        paramTable = [paramTable; cell2table(AP, 'VariableNames', {'parameter','unit','definition'})];
    end
end

infoTable = infoTableOf(info);
thr = [];                                           %analysis windows (MyoDishAnalysis, GUI export)
if isfield(info, 'thresholds') && istable(info.thresholds) && height(info.thresholds) > 0, thr = info.thresholds; end

% tables in the order of the sheets / files; tables that are not given (e.g. contractions = []) are left out
tabs = [{'contractions', contractions; 'summary', summary}; P.sheets; {'parameters', paramTable; 'info', infoTable}];
if ~isempty(thr), tabs(end+1, :) = {'thresholds', thr}; end
if isfield(info, 'labels') && istable(info.labels), tabs(end+1, :) = {'labels', info.labels}; end
for nm = {'rockerFilter', 'protocols', 'protocolResults', 'pulses'}
    if isfield(info, nm{1}) && istable(info.(nm{1})) && height(info.(nm{1})) > 0, tabs(end+1, :) = {nm{1}, info.(nm{1})}; end %#ok<AGROW>
end
tabs = tabs(cellfun(@istable, tabs(:, 2)), :);
xls = ~strcmpi(e, '.csv');
if xls, outFiles = {outputFile}; else, outFiles = {}; end
for k = 1:size(tabs, 1)
    nm = tabs{k, 1};
    if xls && ~ismember(nm, P.csvTables) && height(tabs{k, 2}) < 1048576     %Excel row limit
        writeSheet(tabs{k, 2}, outputFile, nm);
        continue;
    end
    f = fullfile(p, [n '_' nm '.csv']);
    writetable(tabs{k, 2}, f);
    if P.compress && ismember(nm, P.csvTables)
        gzip(f);
        delete(f);
        f = [f '.gz'];
    end
    outFiles{end+1} = f; %#ok<AGROW>
end
end


function infoTable = infoTableOf(info)
% key / value table: file facts, software, version, implementation, notes, extra rows, options, log file entries
o = info.options;
f = fieldnames(o);
vals = cell(numel(f), 1);
for k = 1:numel(f)
    v = o.(f{k});
    if ischar(v)
        vals{k} = v;
    elseif isempty(v)
        vals{k} = '';
    elseif isstruct(v)                                    %reference beat(s)
        vals{k} = sprintf('reference beat: %s', strjoin(arrayfun(@(r) sprintf('channel %d (%s; aligned at the %s)', r.channel, r.source, alignOf(r)), v, 'UniformOutput', false), '; '));
    elseif islogical(v) && isscalar(v)
        vals{k} = num2str(v);
    elseif isscalar(v)
        vals{k} = sprintf('%.15g', v);              %full precision: options are read back (mda_readResults)
    else
        vals{k} = mat2str(v);
    end
end
% 2026-10-09: version and implementation as own rows; info.extra (rows {key, value}) after the notes
extra = cell(0, 2);
if isfield(info, 'extra') && ~isempty(info.extra), extra = info.extra; end
keys = [{'file'; 'samplingRate_Hz'; 'samplingRateSource'; 'nChannelsInFile'; 'fileLength_s'; ...
    'recordingStart'; 'analysisDate'; 'software'; 'version'; 'implementation'; 'notes'}; extra(:, 1); ...
    strcat('option_', f)];                          %logOffset/logCalibration: AU
startStr = '';
if isfield(info, 'recordingStart') && ~isempty(info.recordingStart) && ~isnan(info.recordingStart)
    startStr = datestr(info.recordingStart, 'yyyy-mm-dd HH:MM:SS');
end
analysisDate = datestr(now, 'yyyy-mm-dd HH:MM:SS');
if isfield(info, 'analysisDate'), analysisDate = info.analysisDate; end
infoVals = [{info.file; num2str(info.samplingRate); info.samplingRateSource; num2str(info.nChannelsInFile); ...
    sprintf('%.3f', info.totalSeconds); startStr; analysisDate; ...
    ['MyoDishAnalysis ' mda_version() ' (MATLAB, T. Seidel, FAU Erlangen-Nuernberg)']; mda_version(); 'MATLAB'; ...
    strjoin(info.notes, ' | ')}; extra(:, 2); vals];
% zero force (Offset) and Calibration entries of the log file, per channel (first and last value)
logKeys = {}; logVals = {};
if isfield(info, 'offsetLog')
    lists = {'offsetLog', 'logOffset_ch'; 'calibrationLog', 'logCalibration_ch'};
    for L = 1:2
        E = info.(lists{L,1});
        for ch = unique(E(:,2))'
            v = E(E(:,2) == ch, 3);
            logKeys{end+1,1} = sprintf('%s%d', lists{L,2}, ch); %#ok<AGROW>
            logVals{end+1,1} = strjoin(arrayfun(@num2str, unique(v,'stable')', 'UniformOutput', false), ', '); %#ok<AGROW>
        end
    end
end
infoTable = table([keys; logKeys], [infoVals; logVals], 'VariableNames', {'key','value'});
end


function a = alignOf(r)
% alignment of a reference beat (references of the first version: 50 % upstroke)
a = '50 % upstroke';
if isfield(r, 'align') && strcmp(r.align, 'stimulus'), a = 'stimulus'; end
end


function writeSheet(T, file, sheet)
try
    writetable(T, file, 'Sheet', sheet, 'WriteMode', 'overwritesheet');
catch ME
    if contains(ME.message, 'WriteMode')
        writetable(T, file, 'Sheet', sheet);
    else
        rethrow(ME);
    end
end
end
