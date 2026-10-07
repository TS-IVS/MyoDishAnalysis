function outFiles = mda_writeResults(outputFile, contractions, summary, info)
%MDA_WRITERESULTS  Write contraction table, summary and analysis info to Excel (.xlsx) or text (.csv).
%
%   mda_writeResults('results.xlsx', contractions, summary, info)
%       sheets: contractions, summary, parameters (definitions), info (file facts and options), labels,
%       rockerFilter (option 'rockerFilter': result per channel and time range), protocols (option 'protocol'),
%       protocolResults (characteristic values per protocol and channel, mda_protocolResults)
%   mda_writeResults('results.csv', ...)
%       results_contractions.csv, results_summary.csv, results_parameters.csv, results_info.csv
%
% Existing sheets of the same name are overwritten (MATLAB R2020a or newer; older releases: the sheet is
% written over, rows of a longer old table may remain).
%
% TS 2026-10-05

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
    elseif isscalar(v)
        vals{k} = num2str(v);
    else
        vals{k} = mat2str(v);
    end
end
keys = [{'file'; 'samplingRate_Hz'; 'samplingRateSource'; 'nChannelsInFile'; 'fileLength_s'; ...
    'recordingStart'; 'analysisDate'; 'software'; 'notes'}; strcat('option_', f)];   %logOffset/logCalibration: AU
startStr = '';
if isfield(info, 'recordingStart') && ~isnan(info.recordingStart)
    startStr = datestr(info.recordingStart, 'yyyy-mm-dd HH:MM:SS');
end
analysisDate = datestr(now, 'yyyy-mm-dd HH:MM:SS');
if isfield(info, 'analysisDate'), analysisDate = info.analysisDate; end
infoVals = [{info.file; num2str(info.samplingRate); info.samplingRateSource; num2str(info.nChannelsInFile); ...
    sprintf('%.3f', info.totalSeconds); startStr; analysisDate; ...
    'MyoDishAnalysis 1.0.0-beta.1 (MATLAB, T. Seidel, FAU Erlangen-Nuernberg)'; strjoin(info.notes, ' | ')}; vals];
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

if strcmpi(e, '.csv')
    outFiles = {fullfile(p, [n '_contractions.csv']), fullfile(p, [n '_summary.csv']), ...
        fullfile(p, [n '_parameters.csv']), fullfile(p, [n '_info.csv'])};
    writetable(contractions, outFiles{1});
    writetable(summary, outFiles{2});
    writetable(paramTable, outFiles{3});
    writetable(infoTable, outFiles{4});
    if isfield(info, 'labels') && istable(info.labels)
        outFiles{end+1} = fullfile(p, [n '_labels.csv']);
        writetable(info.labels, outFiles{end});
    end
    if isfield(info, 'rockerFilter') && istable(info.rockerFilter) && height(info.rockerFilter) > 0
        outFiles{end+1} = fullfile(p, [n '_rockerFilter.csv']);
        writetable(info.rockerFilter, outFiles{end});
    end
    if isfield(info, 'protocols') && istable(info.protocols) && height(info.protocols) > 0
        outFiles{end+1} = fullfile(p, [n '_protocols.csv']);
        writetable(info.protocols, outFiles{end});
    end
    if isfield(info, 'protocolResults') && istable(info.protocolResults) && height(info.protocolResults) > 0
        outFiles{end+1} = fullfile(p, [n '_protocolResults.csv']);
        writetable(info.protocolResults, outFiles{end});
    end
else
    outFiles = {outputFile};
    writeSheet(contractions, outputFile, 'contractions');
    writeSheet(summary, outputFile, 'summary');
    writeSheet(paramTable, outputFile, 'parameters');
    writeSheet(infoTable, outputFile, 'info');
    if isfield(info, 'labels') && istable(info.labels)
        writeSheet(info.labels, outputFile, 'labels');
    end
    if isfield(info, 'rockerFilter') && istable(info.rockerFilter) && height(info.rockerFilter) > 0
        writeSheet(info.rockerFilter, outputFile, 'rockerFilter');
    end
    if isfield(info, 'protocols') && istable(info.protocols) && height(info.protocols) > 0
        writeSheet(info.protocols, outputFile, 'protocols');
    end
    if isfield(info, 'protocolResults') && istable(info.protocolResults) && height(info.protocolResults) > 0
        writeSheet(info.protocolResults, outputFile, 'protocolResults');
    end
end
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
