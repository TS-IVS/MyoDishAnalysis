function L = mda_labels(meta, channels)
%MDA_LABELS  Per-channel labels (metadata) as a table with one row per channel.
%
%   L = mda_labels([], channels)          empty labels for the channels
%   L = mda_labels(s, channels)           s = struct, e.g.
%         s.species = 'human';                          same value for all channels
%         s.sampleID = 'H01';
%         s.sliceID = {'S1','S2','S3'};                 one value per channel (in the order of 'channels')
%         s.treatment = {'control','iso','iso'};
%         s.daysInCulture = [3 3 3];
%         s.analyst = 'TS';
%       or a struct array with one element per channel.
%         s.channel = [1 6 8]: the per-channel values refer to these channels (other channels: empty labels)
%   L = mda_labels(T, channels)           T = table (with a column 'channel', or one row per channel in order)
%   L = mda_labels('labels.csv', channels)   file written by the GUI (csv) or an Excel file (sheet 'labels' of a
%                                             result file of MyoDishAnalysis, otherwise the first sheet)
%
% Standard labels (always present, in this order):
%   setupID, sliceID, species, sampleID, sampleGroup, sliceGroup, tissue, treatment   text
%   concentration   number (concentration of the treatment, e.g. 100)
%   concentrationUnit  text (e.g. 'nM')
%   daysInCulture   number (days)
%   cultureStart    text, date/time of the start of the culture, e.g. '1999-12-24 14:30' (or '24.12.1999 14:30').
%                   If given, daysInCulture of every contraction = time since cultureStart (from the clock time of
%                   the recording), otherwise the value of daysInCulture is used.
%   comment         text
%   analyst         text (initials of the person who does the analysis)
% Further fields are kept (appended after the standard labels).
%
% TS 2026-10-04

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

channels = channels(:);
nCh = numel(channels);
L = table(channels, 'VariableNames', {'channel'});
[~, stdNames] = mda_parameters();
for k = 1:numel(stdNames)
    if ismember(stdNames{k}, numericLabels())
        L.(stdNames{k}) = nan(nCh, 1);
    else
        L.(stdNames{k}) = repmat({''}, nCh, 1);
    end
end
if nargin < 1 || isempty(meta)
    return;
end

% file --> table
if ischar(meta) || (isstring(meta) && isscalar(meta))
    meta = readLabelFile(char(meta));
end

% struct with a field 'channel': the values refer to these channels (e.g. in the GUI, which shows all channels)
if isstruct(meta) && isscalar(meta) && isfield(meta, 'channel') && ~isempty(meta.channel)
    meta = mda_labels(rmfield(meta, 'channel'), meta.channel);
end

% table --> struct array (one element per channel)
if istable(meta)
    if ismember('channel', meta.Properties.VariableNames)
        [found, loc] = ismember(channels, meta.channel);
        S = repmat(struct(), nCh, 1);
        names = setdiff(meta.Properties.VariableNames, {'channel'}, 'stable');
        for i = 1:nCh
            for k = 1:numel(names)
                if found(i)
                    v = meta.(names{k})(loc(i));
                    if iscell(v), v = v{1}; end
                    if isstring(v), v = char(v); end
                    if iscategorical(v), v = char(v); end
                else
                    v = [];
                end
                S(i).(names{k}) = v;
            end
        end
        meta = S;
    elseif height(meta) == nCh
        meta = table2struct(meta);
    else
        error('mda_labels: the table needs a column ''channel'' or one row per channel (%d).', nCh);
    end
end

if ~isstruct(meta)
    error('mda_labels: labels must be a struct, a table or a file name.');
end

names = fieldnames(meta);
for k = 1:numel(names)
    nm = names{k};
    if strcmp(nm, 'channel'), continue; end
    vals = cell(nCh, 1);
    if numel(meta) == nCh && nCh > 1
        for i = 1:nCh, vals{i} = meta(i).(nm); end
    elseif numel(meta) == 1
        v = meta.(nm);
        if isstring(v), v = cellstr(v); end
        if ischar(v) || (isnumeric(v) && isscalar(v)) || islogical(v) && isscalar(v) || isempty(v) || isdatetime(v) && isscalar(v)
            vals(:) = {v};                                 %same value for all channels
        elseif (iscell(v) || isnumeric(v) || isdatetime(v)) && numel(v) == nCh
            for i = 1:nCh
                if iscell(v), vals{i} = v{i}; else, vals{i} = v(i); end
            end
        elseif iscell(v) && isscalar(v)
            vals(:) = v;
        else
            error('mda_labels: label ''%s'' needs one value for all channels or one value per channel (%d).', nm, nCh);
        end
    else
        error('mda_labels: struct array with %d elements, but %d channels.', numel(meta), nCh);
    end
    if ismember(nm, numericLabels()) || (~ismember(nm, stdNames) && all(cellfun(@(x) isnumeric(x) || islogical(x), vals)))
        num = nan(nCh, 1);
        for i = 1:nCh
            x = vals{i};
            if ischar(x), x = str2double(strrep(x, ',', '.')); end
            if ~isempty(x) && isscalar(x), num(i) = double(x); end
        end
        L.(nm) = num;
    else
        txt = cell(nCh, 1);
        for i = 1:nCh, txt{i} = toText(vals{i}); end
        L.(nm) = txt;
    end
end
end


function n = numericLabels()
% standard labels that are numbers
n = {'concentration','daysInCulture'};
end


function s = toText(x)
if isempty(x)
    s = '';
elseif ischar(x)
    s = x;
elseif isstring(x) || iscategorical(x)
    s = char(x);
elseif isdatetime(x)
    s = char(x, 'yyyy-MM-dd HH:mm');
elseif isnumeric(x) || islogical(x)
    s = num2str(x);
else
    s = '';
end
if any(ismissing(string(s))), s = ''; end
end


function T = readLabelFile(file)
if ~exist(file, 'file'), error('mda_labels: file not found: %s', file); end
[~, ~, e] = fileparts(file);
if any(strcmpi(e, {'.xlsx','.xls'})) && ismember('labels', sheetnames(file))
    opts = detectImportOptions(file, 'Sheet', 'labels');   %result file of MyoDishAnalysis: sheet 'labels'
else
    opts = detectImportOptions(file);
end
v = opts.VariableNames;
types = repmat({'char'}, 1, numel(v));                 %text, so that IDs like '01' stay text
types(ismember(v, [{'channel'}, numericLabels()])) = {'double'};
opts = setvartype(opts, v, types);
T = readtable(file, opts);
end
