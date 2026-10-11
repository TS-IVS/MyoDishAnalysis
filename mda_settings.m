function [out, notes] = mda_settings(action, file, opts)
%MDA_SETTINGS  Save and load the settings of an analysis (all options, including the advanced settings).
%
%   mda_settings('save', 'mySettings.csv', opts)    write a settings file: table key, value (as the info table of the
%                                                   results): createdBy (MyoDishAnalysisSettings), version,
%                                                   implementation, savedDate, option_<name> for every option except
%                                                   the reference beat
%   [opts, notes] = mda_settings('load', file)      complete options (mda_options) from a settings file or from results
%                                                   of MyoDishAnalysis, MyoDishAnalysisWatch or MyoDishAnalysisGUI
%                                                   (.xlsx, <name>_info.csv: the options of that analysis); options
%                                                   missing in the file have their default, options unknown in this
%                                                   version are ignored (notes)
%
% The same file format is read and written by the Python version (settings.py). Every analysis stores its options
% in the info table of the results, so the results of an analysis can be loaded as settings, too.
% Use: mda_options('settings', file, ...), MyoDishAnalysis(..., 'settings', file), MyoDishAnalysisWatch(...,
% 'settings', file), MyoDishAnalysisGUI: Advanced ... -> Save settings ... / Load settings ...
%
% TS 2026-10-10

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

switch lower(action)
    case 'save'
        if nargin < 3 || isempty(opts), opts = mda_options(); end
        [p, n, e] = fileparts(char(file));
        if isempty(e), file = fullfile(p, [n '.csv']); end
        f = setdiff(fieldnames(opts), {'referenceBeat'}, 'stable');
        keys = [{'createdBy'; 'version'; 'implementation'; 'savedDate'}; strcat('option_', f)];
        vals = [{'MyoDishAnalysisSettings'; mda_version(); 'MATLAB'; datestr(now, 'yyyy-mm-dd HH:MM:SS')}; ...
            cellfun(@(k) valueText(opts.(k)), f, 'UniformOutput', false)];
        writetable(table(keys, vals, 'VariableNames', {'key', 'value'}), file);
        out = file;
        notes = {};
    case 'load'
        R = mda_readResults(file);
        out = R.options;
        if isfield(out, 'referenceBeat'), out.referenceBeat = []; end
        notes = R.notes;
    otherwise
        error('mda_settings: action ''save'' or ''load'' expected.');
end
end


function s = valueText(v)
% option value as text (as in the info table of mda_writeResults; read back by mda_readResults)
if ischar(v)
    s = v;
elseif isempty(v)
    s = '';
elseif islogical(v) && isscalar(v)
    s = num2str(v);
elseif isnumeric(v) && isscalar(v)
    s = sprintf('%.15g', v);
elseif isnumeric(v) || islogical(v)
    s = mat2str(v);
else
    s = '';
end
end
