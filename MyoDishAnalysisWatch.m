function [index, report] = MyoDishAnalysisWatch(rawFolder, resultsFolder, varargin)
%MYODISHANALYSISWATCH  Automatic analysis of new MyoDish recordings in a folder (watcher).
%
%   [index, report] = MyoDishAnalysisWatch(rawFolder, resultsFolder, ...)
%
%   Every pass searches rawFolder (with subfolders) for .mdd files and analyses those that are new, have changed, or
%   were analysed with another version, other options or (same implementation) other core code. The watcher only
%   calls the functions of MyoDishAnalysis (MyoDishAnalysis, mda_readMdd, mda_protocols): improvements of the analysis
%   apply to the watcher results as well; with 'reanalyze','outdated' (default) the affected recordings are analysed
%   again. Python: mda-watch (myodish_analysis.watch), same index and results.
%
% RESULTS per recording (resultsFolder/<subfolder of rawFolder>/)
%   <name>_summary.csv, _contractions.csv(.gz), _parameters.csv, _info.csv (version, all options, watcher settings),
%   _thresholds.csv (analysis windows), _labels.csv (_rockerFilter.csv); MyoDishAnalysisGUI(<name>_info.csv) opens them
%       summary = one row per channel and time range: time bins of 'binMinutes' (default 60 min) without the periods of
%       the stimulation protocols ('includeProtocols', false, default; a bin with a protocol gives several ranges).
%       range = clock time of the start of the range, bin = clock time of the start of the bin, nComments / comments =
%       comments of the log file in the range (this channel or all channels). Contractions ('contractions'): 'all'
%       (every contraction), 'thinned' (every 'thinFactor'-th contraction per channel, 'thinMode','nth', or the median
%       of blocks of 'thinFactor' contractions, 'thinMode','median'; extra beats and, with 'includeProtocols', the
%       contractions in the protocols are always kept) or 'none'; columns bin, sampledEvery (number of contractions per
%       row) and sampleMode ('singleBeat' / 'median'). 'compress', true: <name>_contractions.csv.gz.
%   <name>_protocols_*.csv (if the log file contains stimulation protocols, 'protocols', true)
%       MyoDishAnalysis(file, [], [], [], 'protocol', 'all', ...): every contraction in the protocols, summary per
%       protocol, channel and group, protocolResults (FFR, ST thresholds, refractory periods, PRP)
%   <name>_events.csv ('events', true): all entries of the log file (comments, stimulation and rocker settings,
%       recording, calibration, schedule, warnings) with category, clock time and time in the file
%   <name>_gaps.csv ('gaps', true): periods without force signal (mda_signalGaps): chamber taken out ('chamber out'),
%       sensor board group or controller failures (>= 2 channels within 1 s), saturation, channels without a chamber
%       ('no signal'); with clock times and the comments of the log file within 5 min of the start or end. The summary
%       gets the columns noSignal_s (s without signal in the range) and nChamberOut (chambers taken out in the range).
%   <name>_channels.csv ('gaps', true): one row per channel: status at the end of the recording ('beating', 'not
%       beating' = no contraction in the last 30 min with signal, 'removed' = chamber taken out and not put back,
%       'signal lost' = technical, 'no slice'), beatingAtEnd, s with and without signal, chambers taken out, technical
%       failures, contractions, last contraction (time, clock time, median amplitude of the last 10 included
%       contractions, in % of the 95th percentile of the recording), date of the experiment ID in the file name
%       (6 digits yymmdd, e.g. ABC000101) and days since this date at the last contraction (or the end of the signal),
%       daysInCulture (labels), comments about the slice's end (discarded, removed, not beating, fixed, frozen, ...).
%   Labels per channel (metadata): <name>_labels.csv next to the .mdd file (saved by the GUI), if present.
% resultsFolder/mda_index.csv
%   one row per recording: file (path relative to rawFolder), bytes, modified (time of the .mdd file, UTC), logBytes, status (ok / error /
%   running / noLog), version, implementation (MATLAB / Python), code (fingerprint of the core functions), options,
%   analyzed, seconds, nContractions, outputs, message. The same file is used by the MATLAB and the Python watcher.
% resultsFolder/reports/mda_report_<date>_<time>.txt
%   report of a pass with analysed recordings: per channel contractions, capture (% of the stimuli followed by a
%   contraction), extra beats (% of the detected contractions), mean amplitude in the first and last range (>= 10
%   included contractions) and flags (no contractions, capture < flagCapture %, extra beats > flagExtraBeats %,
%   amplitude change > flagAmplitudeChange %).
%
% SKIPPED while written: files modified less than 'minFileAgeMinutes' ago (default 10), names starting with '.'
%   (rsync temporary files, hidden folders), and recordings whose log file has no 'Recording stopped' entry yet (status
%   'running') unless unchanged for 'incompleteAfterHours' (default 30 h, e.g. aborted recordings). Recordings without
%   log file get the status 'noLog'; they are checked again in every pass. Errors are retried when the file, the
%   version, the options or the code change, or with 'retryErrors'.
%
% OPTIONS (name/value pairs)
%   'interval', h            hours between passes (default 0 = one pass; > 0: runs until Ctrl+C)
%   'reanalyze', m           'outdated' (default) | 'new' (only new and changed files) | 'all'
%   'retryErrors', tf        analyse recordings with errors again (default false)
%   'fromDate', d            only files modified on/after this date ('yyyy-mm-dd', 'dd.mm.yyyy', 'yymmdd')
%   'filter', rx             regular expression on the path relative to rawFolder (case-insensitive)
%   'maxFiles', n            at most n recordings per pass
%   'dryRun', tf             only list what would be analysed
%   'minFileAgeMinutes', m   (default 10)       'incompleteAfterHours', h   (default 30)
%   'binMinutes', m          time bin of the summary (default 60)
%   'includeProtocols', tf   summary and contractions also during the stimulation protocols (default false)
%   'protocolMarginSeconds', s   excluded after the end of a protocol as well (default 0)
%   'protocols', tf          analyse the stimulation protocols of the log file (default true)
%   'contractions', c        'all' (default) | 'thinned' | 'none'
%   'thinFactor', n          (default 10)       'thinMode', m   'nth' (default) | 'median'
%   'compress', tf           <name>_contractions.csv.gz (default false)
%   'events', tf             <name>_events.csv and comments in the summary (default true)
%   'gaps', tf               <name>_gaps.csv, <name>_channels.csv, summary columns noSignal_s, nChamberOut (default true)
%   'flagCapture', 'flagExtraBeats', 'flagAmplitudeChange'   report flags (default 90, 10, 30 %)
%   'quiet', tf              no messages
%   all other name/value pairs: analysis options of MyoDishAnalysis for all recordings, e.g. 'rockerFilter', true,
%   'rocker', 'stopped', 'threshold', 300 (not 'output', 'labels', 'metadata', 'protocol', 'groupBy')
%
% EXAMPLES
%   MyoDishAnalysisWatch('/data/myodish/raw', '/data/myodish/results', 'rockerFilter', true)
%   MyoDishAnalysisWatch(raw, results, 'fromDate', '2026-10-01', 'dryRun', true)
%   MyoDishAnalysisWatch(raw, results, 'interval', 24)        %one pass every 24 h (MATLAB stays busy)
%   MyoDishAnalysisWatch(raw, results, 'contractions', 'thinned', 'thinMode', 'median', 'compress', true)
%   Daily without an open MATLAB: the scheduler of the operating system with
%   matlab -batch "MyoDishAnalysisWatch('raw', 'results', 'quiet', true)"   or the Python version (mda-watch).
%
% TS 2026-10-08 (watcher settings in the info table 2026-10-09)

W = struct('interval', 0, 'reanalyze', 'outdated', 'retryErrors', false, 'fromDate', '', 'filter', '', ...
    'maxFiles', inf, 'dryRun', false, 'minFileAgeMinutes', 10, 'incompleteAfterHours', 30, 'binMinutes', 60, ...
    'includeProtocols', false, 'protocolMarginSeconds', 0, 'protocols', true, 'contractions', 'all', ...
    'thinFactor', 10, 'thinMode', 'nth', 'compress', false, 'events', true, 'gaps', true, ...
    'flagCapture', 90, 'flagExtraBeats', 10, 'flagAmplitudeChange', 30, 'quiet', false);
wNames = fieldnames(W);
args = {};
for i = 1:2:numel(varargin)
    if i == numel(varargin), error('MyoDishAnalysisWatch: options as name/value pairs.'); end
    k = find(strcmpi(wNames, char(varargin{i})), 1);
    if ~isempty(k)
        W.(wNames{k}) = varargin{i+1};
    elseif ismember(lower(char(varargin{i})), {'output', 'labels', 'metadata', 'protocol', 'groupby'})
        error('MyoDishAnalysisWatch: ''%s'' is set by the watcher (labels per channel: <name>_labels.csv).', varargin{i});
    else
        args(end+1:end+2) = {char(varargin{i}), varargin{i+1}}; %#ok<AGROW>
    end
end
if ~ismember(lower(W.reanalyze), {'outdated', 'new', 'all'})
    error('MyoDishAnalysisWatch: ''reanalyze'': ''outdated'', ''new'' or ''all'' expected.');
end
W.contractions = lower(char(W.contractions)); W.thinMode = lower(char(W.thinMode));
if ~ismember(W.contractions, {'all', 'thinned', 'none'})
    error('MyoDishAnalysisWatch: ''contractions'': ''all'', ''thinned'' or ''none'' expected.');
end
if ~ismember(W.thinMode, {'nth', 'median'}), error('MyoDishAnalysisWatch: ''thinMode'': ''nth'' or ''median'' expected.'); end
if ~isscalar(W.thinFactor) || W.thinFactor < 1 || W.thinFactor ~= round(W.thinFactor)
    error('MyoDishAnalysisWatch: ''thinFactor'': integer >= 1 expected.');
end
raw = absPath(rawFolder);
res = absPath(resultsFolder);
if ~isfolder(raw), error('MyoDishAnalysisWatch: folder not found: %s', raw); end
oa = optionArgs(args);
mda_options(oa{:});                                    %unknown analysis options: error now
while true
    [index, report] = onePass(raw, res, W, args);
    if W.interval <= 0, return; end
    if ~W.quiet
        fprintf('next pass %s (Ctrl+C stops)\n', datestr(now + W.interval / 24, 'yyyy-mm-dd HH:MM'));
    end
    pause(W.interval * 3600);
end
end


% =====================================================================================================
function [X, report] = onePass(raw, res, W, args)
if ~isfolder(res), mkdir(res); end
lock = fullfile(res, 'mda_watch.lock');
report = '';
d = dir(lock);
if ~isempty(d) && (now - d.datenum) * 24 < 12
    report = sprintf('another watcher is running (lock file %s, younger than 12 h): pass skipped', lock);
    if ~W.quiet, fprintf('%s\n', report); end
    X = readIndex(res);
    return;
end
if ~W.dryRun
    fid = fopen(lock, 'w'); fprintf(fid, '%d %s\n', feature('getpid'), datestr(now, 'yyyy-mm-dd HH:MM:SS')); fclose(fid);
    cleanup = onCleanup(@() deleteIfExists(lock)); %#ok<NASGU>
end
[X, report] = scanAndAnalyse(raw, res, W, args);
end


function [X, report] = scanAndAnalyse(raw, res, W, args)
report = '';
X = readIndex(res);
version = mda_version();
code = codeFingerprint();
otext = optionsText(args, W);
fromDate = parseDate(W.fromDate);
oa = optionArgs(args);
hopts = mda_options(oa{:});
t = now;
F = findRecordings(raw);
todo = {};
for k = 1:numel(F)
    rel = F(k).rel; f = F(k).file;
    if ~isempty(W.filter) && isempty(regexpi(rel, W.filter, 'once', 'emptymatch')), continue; end   %as Python re.search
    logf = [f(1:end-4) '_log.log'];
    dl = dir(logf);
    logBytes = -1; lastChange = F(k).datenum;
    if ~isempty(dl), logBytes = dl.bytes; lastChange = max(lastChange, dl.datenum); end
    if ~isnan(fromDate) && F(k).datenum < fromDate, continue; end
    if (t - lastChange) * 1440 < W.minFileAgeMinutes, continue; end     %still written / copied
    modified = utcText(F(k).datenum);
    i = find(strcmp(X.file, rel), 1);
    if isempty(i), r = []; else, r = X(i,:); end
    why = reason(r, F(k).bytes, modified, logBytes, version, code, otext, W);
    if ~isempty(why)
        todo(end+1,:) = {rel, f, logf, F(k).bytes, modified, logBytes, lastChange, why}; %#ok<AGROW>
    end
end
todo = todo(1:min(size(todo,1), W.maxFiles), :);
if ~W.quiet
    fprintf('%s  %s: %d recording(s) to analyse\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), raw, size(todo,1));
end
if W.dryRun
    for k = 1:size(todo,1), fprintf('  %s  (%s)\n', todo{k,1}, todo{k,8}); end
    return;
end
blocks = {};
for k = 1:size(todo,1)
    [rel, f, ~, nBytes, modified, logBytes, lastChange, why] = todo{k,:};
    row = struct('file', rel, 'bytes', nBytes, 'modified', modified, 'logBytes', logBytes, 'status', '', ...
        'version', version, 'implementation', 'MATLAB', 'code', code, 'options', otext, ...
        'analyzed', datestr(now, 'yyyy-mm-dd HH:MM:SS'), 'seconds', nan, 'nContractions', nan, 'outputs', '', 'message', '');
    tic0 = tic;
    block = '';
    if logBytes < 0
        row.status = 'noLog'; row.message = 'no log file <name>_log.log';
    else
        try
            H = mda_readMdd(f, [], [], hopts);
            if H.recordingStopped == 0 && (t - lastChange) * 24 < W.incompleteAfterHours
                row.status = 'running'; row.message = 'no ''Recording stopped'' in the log file yet';
            else
                if ~W.quiet, fprintf('  %s (%s) ...\n', rel, why); end
                [row, block] = analyse(f, rel, H, res, row, W, args);
            end
        catch ME
            row.status = 'error';
            row.message = clean(sprintf('%s: %s', ME.identifier, ME.message));
        end
    end
    row.seconds = round(toc(tic0) * 10) / 10;
    if any(strcmp(row.status, {'ok', 'error'}))
        if isempty(block), block = sprintf('%s\n  %s: %s\n', rel, row.status, row.message); end
        blocks{end+1} = block; %#ok<AGROW>
    end
    if ~W.quiet && ~strcmp(row.status, 'ok'), fprintf('  %s: %s: %s\n', rel, row.status, row.message); end
    X = setRow(X, row);
    writeIndex(res, X);
end
if size(todo, 1) > 0                                   %index in the order of the files
    X = sortrows(X, 'file');
    writeIndex(res, X);
end
if ~isempty(blocks)
    blocks = sort(blocks);
    report = sprintf('MyoDishAnalysis %s (MATLAB) watcher report %s\nraw folder: %s\nresults:    %s\noptions:    %s\n\n%s', ...
        version, datestr(now, 'yyyy-mm-dd HH:MM:SS'), raw, res, otext, strjoin(blocks, newline));
    dr = fullfile(res, 'reports');
    if ~isfolder(dr), mkdir(dr); end
    fid = fopen(fullfile(dr, ['mda_report_' datestr(now, 'yyyy-mm-dd_HHMMSS') '.txt']), 'w', 'n', 'UTF-8');
    fwrite(fid, unicode2native(report, 'UTF-8'));
    fclose(fid);
    if ~W.quiet, fprintf('\n%s\n', report); end
end
end


function why = reason(r, nBytes, modified, logBytes, version, code, otext, W)
% reason to analyse the recording ('' = nothing to do)
why = '';
if isempty(r), why = 'new'; return; end
old = parseTime(r.modified{1});
if r.bytes ~= nBytes || r.logBytes ~= logBytes || isnan(old) || abs(old - parseTime(modified)) * 86400 > 2
    why = 'changed'; return;
end
status = r.status{1};
if any(strcmp(status, {'running', 'noLog'})), why = ['check ' status]; return; end
outdated = '';
if ~strcmp(r.version{1}, version)
    outdated = 'other version';
elseif ~strcmp(r.options{1}, otext)
    outdated = 'other options';
elseif strcmp(r.implementation{1}, 'MATLAB') && ~strcmp(r.code{1}, code)
    outdated = 'core code changed';
end
mode = lower(W.reanalyze);
if strcmp(status, 'error')
    if W.retryErrors, why = 'retry error';
    elseif ~isempty(outdated) && ~strcmp(mode, 'new'), why = ['retry error, ' outdated];
    end
    return;
end
if strcmp(mode, 'all')
    why = 'reanalyze all';
elseif strcmp(mode, 'outdated') && ~isempty(outdated)
    why = outdated;
end
end


function [row, block] = analyse(f, rel, H, res, row, W, args)
% the analyses of one recording (only calls of the MyoDishAnalysis functions)
[~, n] = fileparts(f);
outDir = fullfile(res, fileparts(rel));
if ~isfolder(outDir), mkdir(outDir); end
meta = [f(1:end-4) '_labels.csv'];
if ~isfile(meta), meta = []; end
msgs = {}; outputs = {};
P = [];
if W.protocols || ~W.includeProtocols
    try
        P = mda_protocols(H);
    catch ME
        msgs{end+1} = sprintf('protocols: %s: %s', ME.identifier, ME.message);
    end
end
Wp = protocolWindows(P, W.protocolMarginSeconds);
if W.includeProtocols, Wcut = []; else, Wcut = Wp; end
[fr, to, labels, binLabels] = ranges(H, W.binMinutes * 60, Wcut);
deleteFile(fullfile(outDir, [n '_contractions.csv']));            %results of earlier options
deleteFile(fullfile(outDir, [n '_contractions.csv.gz']));
E = [];
if W.events
    E = mda_logEntries(H.logFile);
    E = addvars(E, cellfun(@eventCategory, E.code, E.text, 'UniformOutput', false), 'After', 'code', ...
        'NewVariableNames', 'category');
    E.clockTime.Format = 'yyyy-MM-dd HH:mm:ss.SSS';
    writetable(E, fullfile(outDir, [n '_events.csv']));
    outputs{end+1} = [n '_events.csv'];
end
G = [];
if W.gaps
    try
        G = mda_signalGaps(H);
        Gw = gapsOut(G, H, E);
        writetable(Gw, fullfile(outDir, [n '_gaps.csv']));
        outputs{end+1} = [n '_gaps.csv'];
    catch ME
        G = [];
        msgs{end+1} = sprintf('gaps: %s: %s', ME.identifier, ME.message);
    end
end
S = [];
C = [];
nC = 0;
if ~isempty(fr)
    [C, S, info] = MyoDishAnalysis(f, [], fr, to, 'labels', labels, 'metadata', meta, 'quiet', true, args{:});
    info.extra(strcmp(info.extra(:, 1), 'createdBy'), 2) = {'MyoDishAnalysisWatch'};   %info table: watcher settings
    info.extra = [info.extra; {'watcherOptions', row.options; 'watcherCode', row.code}];
    nC = height(C);
    [~, iS] = ismember(S.range, labels);
    S = addvars(S, binLabels(iS), 'After', 'range', 'NewVariableNames', 'bin');
    [~, iC] = ismember(C.range, labels);
    C = addvars(C, binLabels(iC), 'After', 'range', 'NewVariableNames', 'bin');
    S = addComments(S, E);
    if W.gaps, S = addGaps(S, G); end
    Call = C;
    if W.includeProtocols, Wkeep = Wp; else, Wkeep = []; end
    C = sampleContractions(C, labels, Wkeep, W);
    mda_writeResults(fullfile(outDir, [n '.csv']), C, S, info);
    cf = fullfile(outDir, [n '_contractions.csv']);
    if strcmp(W.contractions, 'none')
        delete(cf);
    elseif W.compress
        gzip(cf);
        delete(cf);
    end
    outputs = [{[n '.csv']}, outputs];
    msgs = [info.notes(:)', msgs];
else
    msgs{end+1} = 'no time outside the stimulation protocols';
    Call = [];
end
CH = [];
if W.gaps && istable(G)
    CH = channelStatus(H, Call, G, E, n);
    writetable(CH, fullfile(outDir, [n '_channels.csv']));
    outputs{end+1} = [n '_channels.csv'];
end
if W.protocols && istable(P) && height(P) > 0
    try
        MyoDishAnalysis(f, [], [], [], 'protocol', 'all', 'metadata', meta, 'quiet', true, ...
            'output', fullfile(outDir, [n '_protocols.csv']), args{:});
        outputs{end+1} = [n '_protocols.csv'];
    catch ME
        msgs{end+1} = sprintf('protocols: %s: %s', ME.identifier, ME.message);
    end
end
row.status = 'ok';
row.nContractions = nC;
row.outputs = strjoin(outputs, '; ');
row.message = clean(strjoin(msgs, ' | '));
block = reportBlock(rel, H, S, W, CH, G);
end


function Gw = gapsOut(G, H, E)
% periods without signal with clock times and the comments of the log file within 5 min of their start or end (this
% channel or all channels)
Gw = G;
nG = height(G);
cf = repmat({''}, nG, 1); ct = cf; txt = cf;
cm = [];
if istable(E) && height(E) > 0, cm = E(strcmp(E.category, 'comment'), :); end
for r = 1:nG
    cf{r} = timeLabel(H, G.from(r), G.from(r));
    ct{r} = timeLabel(H, G.to(r), G.to(r));
    if ~isempty(cm)
        near = abs(cm.t_file - G.from(r)) <= 300;
        if ~G.untilEnd(r), near = near | abs(cm.t_file - G.to(r)) <= 300; end
        k = find(near & (cm.channel == G.channel(r) | cm.channel == 0));
        txt{r} = strjoin(cellfun(@clean, cm.text(k)', 'UniformOutput', false), ' | ');
    end
end
Gw = addvars(Gw, cf, ct, 'After', 'duration', 'NewVariableNames', {'clockFrom', 'clockTo'});
Gw.comments = txt;
end


function S = addGaps(S, G)
% columns noSignal_s (s without signal of the channel in the range) and nChamberOut (chambers taken out in the range)
noSig = zeros(height(S), 1); nOut = zeros(height(S), 1);
if istable(G) && height(G) > 0
    for r = 1:height(S)
        g = G(G.channel == S.channel(r), :);
        if height(g) == 0, continue; end
        noSig(r) = sum(max(0, min(g.to, S.to(r)) - max(g.from, S.from(r))));
        nOut(r) = sum(strcmp(g.type, 'chamber out') & ~g.fromStart & g.from >= S.from(r) & g.from <= S.to(r));
    end
end
S.noSignal_s = noSig;
S.nChamberOut = nOut;
end


function T = channelStatus(H, C, G, E, name)
% one row per channel: status at the end of the recording, signal, gaps, last contraction, comments about the end
chs = H.dataChannels(:);
nCh = numel(chs);
TT = H.totalSeconds;
status = repmat({''}, nCh, 1); beatEnd = false(nCh, 1);
sig = zeros(nCh, 1); noSig = zeros(nCh, 1); nOut = zeros(nCh, 1); nTech = zeros(nCh, 1);
firstS = nan(nCh, 1); lastS = nan(nCh, 1); nCon = zeros(nCh, 1); tLast = nan(nCh, 1); clk = repmat({''}, nCh, 1);
aLast = nan(nCh, 1); aMax = nan(nCh, 1); aPct = nan(nCh, 1); dId = nan(nCh, 1); dCul = nan(nCh, 1);
endTxt = repmat({''}, nCh, 1);
idTxt = idDate(name);
cm = [];
if istable(E) && height(E) > 0, cm = E(strcmp(E.category, 'comment'), :); end
rxEnd = ['discard|remov|not beating|no beat|stopped beating|dead|died|infect|contamin|fix|froz|moved|taken out|' ...
    'replac|end of exp|sharp|imaging|histo|rna|pcr'];
for i = 1:nCh
    c = chs(i);
    g = G(G.channel == c, :);
    noSig(i) = sum(g.duration);
    sig(i) = max(0, TT - noSig(i));
    nOut(i) = sum(strcmp(g.type, 'chamber out') & ~g.fromStart);
    nTech(i) = sum(ismember(g.type, {'board group', 'controller', 'saturated'}));
    if istable(C) && height(C) > 0
        cc = C(C.channel == c, :);
    else
        cc = table();
    end
    nCon(i) = height(cc);
    if any(strcmp(g.type, 'no signal'))
        status{i} = 'no slice';
    else
        firstS(i) = 0; lastS(i) = TT;
        k = find(g.fromStart & ~g.untilEnd, 1); if ~isempty(k), firstS(i) = g.to(k); end
        k = find(g.untilEnd & ~g.fromStart, 1); if ~isempty(k), lastS(i) = g.from(k); end
        if height(cc) > 0, tLast(i) = max(cc.t_peak); end
        beatEnd(i) = ~isnan(tLast(i)) && lastS(i) - tLast(i) <= 1800;
        if ~isempty(k) && strcmp(g.type{k}, 'chamber out')
            status{i} = 'removed';
        elseif ~isempty(k)
            status{i} = 'signal lost';
        elseif beatEnd(i)
            status{i} = 'beating';
        else
            status{i} = 'not beating';
        end
    end
    if height(cc) > 0
        inc = cc(cc.included, :);
        if height(inc) == 0, inc = cc; end
        inc = sortrows(inc, 't_peak');
        aLast(i) = median(inc.amplitude(max(1, end-9):end), 'omitnan');
        aMax(i) = mprctile(inc.amplitude, 95);
        if aMax(i) > 0, aPct(i) = 100 * aLast(i) / aMax(i); end
        [~, j] = max(cc.t_peak);
        clk{i} = timeLabel(H, tLast(i), tLast(i));
        if ismember('daysInCulture', cc.Properties.VariableNames), dCul(i) = cc.daysInCulture(j); end
    end
    tRef = tLast(i); if isnan(tRef), tRef = lastS(i); end
    if ~isempty(idTxt) && ~isnan(H.recordingStart) && ~isnan(tRef)
        dId(i) = H.recordingStart + tRef / 86400 - datenum(idTxt, 'yyyy-mm-dd');
    end
    if ~isempty(cm)
        k = find((cm.channel == c | cm.channel == 0) & ~cellfun(@isempty, regexpi(cm.text, rxEnd, 'once')));
        endTxt{i} = strjoin(cellfun(@clean, cm.text(k)', 'UniformOutput', false), ' | ');
    end
end
T = table(chs, status, beatEnd, sig, noSig, nOut, nTech, firstS, lastS, nCon, tLast, clk, aLast, aMax, aPct, ...
    repmat({idTxt}, nCh, 1), dId, dCul, endTxt, 'VariableNames', {'channel', 'status', 'beatingAtEnd', 'signal_s', ...
    'noSignal_s', 'nChamberOut', 'nTechnical', 'firstSignal_s', 'lastSignal_s', 'nContractions', ...
    'lastContraction_s', 'lastContractionClock', 'lastAmplitude', 'maxAmplitude', 'lastAmplitude_pctMax', ...
    'idDate', 'daysSinceIdDate', 'daysInCulture', 'endComments'});
end


function d = idDate(name)
% date of the experiment ID in the file name: first part (between '_') of letters + 6 digits yymmdd ('' if none)
d = '';
parts = strsplit(name, '_');
for k = 1:numel(parts)
    t = regexp(parts{k}, '^[A-Za-z]*(\d{6})$', 'tokens', 'once');
    if isempty(t), continue; end
    v = sscanf(t{1}, '%2d%2d%2d');
    if v(2) >= 1 && v(2) <= 12 && v(3) >= 1 && v(3) <= 31 && v(3) <= eomday(2000 + v(1), v(2))
        d = sprintf('%04d-%02d-%02d', 2000 + v(1), v(2), v(3));
        return;
    end
end
end


function p = mprctile(x, q)
% prctile of a vector (NaN ignored), as the Statistics Toolbox
x = sort(x(~isnan(x)));
n = numel(x);
p = nan;
if n == 0, return; end
if n == 1, p = x(1); return; end
pos = 100 * ((1:n)' - 0.5) / n;
p = interp1(pos, x(:), min(max(q, pos(1)), pos(end)));
end


function Wp = protocolWindows(P, margin)
% [from to] of the protocols (to + margin), merged where they overlap
Wp = zeros(0, 2);
if ~istable(P) || height(P) == 0, return; end
V = sortrows([P.from(:), P.to(:) + margin], 1);
Wp = V(1,:);
for k = 2:size(V, 1)
    if V(k,1) <= Wp(end,2)
        Wp(end,2) = max(Wp(end,2), V(k,2));
    else
        Wp(end+1,:) = V(k,:); %#ok<AGROW>
    end
end
end


function [fr, to, labels, binLabels] = ranges(H, binS, Wcut)
% time bins of binS s (half-open) without the windows Wcut ([]: bins only); range label = clock time of the start of
% the range, bin label = clock time of the start of the bin
T = H.totalSeconds;
if binS > 0, edges = 0:binS:T; else, edges = 0; end
if edges(end) >= T && numel(edges) > 1, edges(end) = []; end   %as numpy.arange: T itself is no bin start
if numel(edges) > 1 && T - edges(end) <= 1, edges(end) = []; end  %no bin shorter than 1 s at the end
bto = [edges(2:end), T];
fr = zeros(0, 1); to = zeros(0, 1); labels = cell(0, 1); binLabels = cell(0, 1);
for k = 1:numel(edges)
    a = edges(k); b = bto(k);
    pieces = [a b];
    for w = 1:size(Wcut, 1)
        nxt = zeros(0, 2);
        for p = 1:size(pieces, 1)
            pa = pieces(p,1); pb = pieces(p,2);
            if Wcut(w,2) <= pa || Wcut(w,1) >= pb, nxt(end+1,:) = [pa pb]; continue; end %#ok<AGROW>
            if Wcut(w,1) > pa, nxt(end+1,:) = [pa Wcut(w,1)]; end %#ok<AGROW>
            if Wcut(w,2) < pb, nxt(end+1,:) = [Wcut(w,2) pb]; end %#ok<AGROW>
        end
        pieces = nxt;
    end
    for p = 1:size(pieces, 1)
        pa = pieces(p,1); pb = pieces(p,2);
        if pb - pa < 1, continue; end                  %no range shorter than 1 s
        fr(end+1,1) = pa; %#ok<AGROW>
        if k == numel(edges) && pb == T, to(end+1,1) = pb; else, to(end+1,1) = pb - 1e-9; end %#ok<AGROW>
        labels{end+1,1} = timeLabel(H, pa, pb); %#ok<AGROW>
        binLabels{end+1,1} = timeLabel(H, a, b); %#ok<AGROW>
    end
end
end


function s = timeLabel(H, a, b)
if ~isnan(H.recordingStart)
    sec = round((H.recordingStart - 719529) * 86400 + a);
    s = char(datetime(sec, 'ConvertFrom', 'posixtime', 'Format', 'yyyy-MM-dd HH:mm:ss'));
else
    s = sprintf('%g-%g min', a / 60, round(b) / 60);
end
end


function S = addComments(S, E)
% columns nComments and comments: comments of the log file in the range (channel of the row or channel 0)
nC = zeros(height(S), 1); txt = repmat({''}, height(S), 1);
if istable(E) && height(E) > 0
    cm = E(strcmp(E.category, 'comment'), :);
    for r = 1:height(S)
        k = find(cm.t_file >= S.from(r) & cm.t_file <= S.to(r) & (cm.channel == S.channel(r) | cm.channel == 0));
        nC(r) = numel(k);
        txt{r} = strjoin(cellfun(@clean, cm.text(k)', 'UniformOutput', false), ' | ');
    end
end
S.nComments = nC;
S.comments = txt;
end


function C = sampleContractions(C, labels, Wkeep, W)
% contractions to save: all, every thinFactor-th, or medians of blocks of thinFactor (extra beats and the contractions
% in the windows Wkeep always complete); columns sampledEvery and sampleMode
if ~strcmp(W.contractions, 'thinned') || height(C) == 0
    C = addvars(C, ones(height(C), 1), repmat({'singleBeat'}, height(C), 1), 'After', 'bin', ...
        'NewVariableNames', {'sampledEvery', 'sampleMode'});
    return;
end
N = W.thinFactor;
tp = C.t_peak;
keep = strcmp(C.beatType, 'extra');
for w = 1:size(Wkeep, 1), keep = keep | (tp >= Wkeep(w,1) & tp <= Wkeep(w,2)); end
[~, rIdx] = ismember(C.range, labels);
ch = C.channel;
[~, order] = sortrows([ch tp]);                     %per channel in time order
singles = zeros(0, 2); blocks = {};
if strcmp(W.thinMode, 'nth')
    cnt = containers.Map('KeyType', 'double', 'ValueType', 'double');
    for i = order'
        if keep(i), singles(end+1,:) = [i 1]; continue; end %#ok<AGROW>
        if isKey(cnt, ch(i)), cnt(ch(i)) = cnt(ch(i)) + 1; else, cnt(ch(i)) = 0; end
        if mod(cnt(ch(i)), N) == 0, singles(end+1,:) = [i N]; end %#ok<AGROW>
    end
else
    bt = C.beatType; inc = C.included; rock = C.rockerMoving;
    cur = []; prev = [];
    for i = order'
        if keep(i), singles(end+1,:) = [i 1]; continue; end %#ok<AGROW>   %does not interrupt the blocks
        key = [ch(i), rIdx(i), double(inc(i)), double(rock(i)), double(strcmp(bt{i}, 'stimulated'))];
        if ~isempty(cur) && (~isequal(key, prev) || ~isequal(bt{i}, bt{cur(1)}) || numel(cur) == N)
            blocks{end+1} = cur; cur = []; %#ok<AGROW>
        end
        cur(end+1) = i; %#ok<AGROW>
        prev = key;
    end
    if ~isempty(cur), blocks{end+1} = cur; end
end
out = C(singles(:,1), :);
every = singles(:,2);
mode = repmat({'singleBeat'}, size(singles, 1), 1);
if ~isempty(blocks)
    first = cellfun(@(b) b(1), blocks)';
    M = C(first, :);
    names = C.Properties.VariableNames;
    num = names(cellfun(@(v) isnumeric(C.(v)) && ~islogical(C.(v)), names) & ~ismember(names, {'contraction', 'channel'}));
    A = C{:, num};
    med = zeros(numel(blocks), numel(num));
    for b = 1:numel(blocks), med(b,:) = median(A(blocks{b}, :), 1, 'omitnan'); end
    for v = 1:numel(num), M.(num{v}) = med(:, v); end
    if ismember('clockTime', names)
        M.clockTime = C.clockTime(first) + seconds(M.t_peak - tp(first));
    end
    out = [out; M];
    every = [every; cellfun(@numel, blocks)'];
    mode = [mode; repmat({'median'}, numel(blocks), 1)];
end
out = addvars(out, every, mode, 'After', 'bin', 'NewVariableNames', {'sampledEvery', 'sampleMode'});
[~, rI] = ismember(out.range, labels);
[~, o2] = sortrows([rI, out.channel, out.t_peak]);  %range, channel, time
C = out(o2, :);
end


function c = eventCategory(code, text)
% category of a log entry: comment, protocol, recording, schedule, stimulation, rocker, calibration, warning, other
% (same rules as in Python)
c = lower(strtrim(code)); t = lower(strtrim(text));
stim = {'stimfrequency', 'stimcurrent', 'chargeduration', 'dechargeduration', 'chargecurrent', 'dechargecurrent', ...
    'stimpulse', 'stimpulses', 'stimpolarisation', 'stimpolarity', 'polarity', 'pauseduration', 'sequence', ...
    'stimsequence', 'spikethresh'};
if strcmp(c, 'comment')
    if ~isempty(regexp(t, '^(started|stopped) (parallel )?recording', 'once')) || startsWith(t, 'approaching 2 gb limit')
        c = 'recording';
    elseif ~isempty(regexp(t, ['^(jump to \d+\s*bpm|s\d+ beat|\d+([.,]\d+)?\s*(hz|ma|bpm|ms)$|pause\s*\d+\s*sec|' ...
            'restored stimulation|keeping pulse settings|stimfrequency\s*\d+|"?rocker stop time)'], 'once'))
        c = 'protocol';                                 %steps written by the schedule files
    elseif contains(t, 'schedule') || startsWith(t, 'saved settings'), c = 'schedule';
    elseif ~isempty(regexp(t, '^(start|end|stop)\>', 'once')) || ~isempty(regexp(t, '\<(started|ended)$', 'once'))
        c = 'protocol';
    end
    return;                                         %'comment' otherwise
end
if ismember(c, stim), c = 'stimulation';
elseif ismember(c, {'rockerspeed', 'rocker'}), c = 'rocker';
elseif ismember(c, {'offset', 'calibration'}) || (strcmp(c, 'event') && contains(t, 'extended sensor mode')), c = 'calibration';
elseif strcmp(c, 'schedule'), c = 'schedule';
elseif ismember(c, {'warning', 'error'}), c = 'warning';
elseif ismember(c, {'recording', 'programinfo', 'nchannels', 'channel number', 'channel order', 'event'}) || ...
        startsWith(c, 'samplingrate'), c = 'recording';
else, c = 'other';
end
end


function block = reportBlock(rel, H, S, W, CH, G)
start = '';
if ~isnan(H.recordingStart)
    sec = round((H.recordingStart - 719529) * 86400);
    start = [', start ' char(datetime(sec, 'ConvertFrom', 'posixtime', 'Format', 'yyyy-MM-dd HH:mm:ss'))];
end
lines = {sprintf('%s  (%.2f h, %d channels%s)', rel, H.totalSeconds / 3600, numel(H.dataChannels), start), ...
    '  channel  contractions  capture%  extra%  amplitude first/last range (uN)  change%  flags'};
if nargin < 5, CH = []; G = []; end
if ~istable(S) || height(S) == 0
    gl = gapLines(CH, G);
    block = sprintf('%s\n', lines{1}, '  no time outside the stimulation protocols', gl{:});
    return;
end
for ch = unique(S.channel)'
    s = S(S.channel == ch, :);
    nDet = sum(s.nDetected); nInc = sum(s.nContractions);
    nStim = sum(s.nStimuli); nMiss = sum(s.nMissedBeats); nExtra = sum(s.nExtraBeats);
    cap = nan; extra = nan; a1 = nan; a2 = nan; chg = nan;
    if nStim > 0, cap = 100 * (1 - nMiss / nStim); end
    if nDet > 0, extra = 100 * nExtra / nDet; end
    good = s(s.nContractions >= 10, :);
    if height(good) > 0, a1 = good.amplitude_mean(1); a2 = good.amplitude_mean(end); end
    if height(good) > 1 && a1 > 0, chg = 100 * (a2 - a1) / a1; end
    flags = {};
    if nDet == 0
        flags{end+1} = 'no contractions'; %#ok<AGROW>
    elseif cap < W.flagCapture
        flags{end+1} = sprintf('capture < %g %%', W.flagCapture); %#ok<AGROW>
    end
    if extra > W.flagExtraBeats, flags{end+1} = sprintf('extra beats > %g %%', W.flagExtraBeats); end %#ok<AGROW>
    if abs(chg) > W.flagAmplitudeChange, flags{end+1} = sprintf('amplitude change > %g %%', W.flagAmplitudeChange); end %#ok<AGROW>
    lines{end+1} = sprintf('  %7d  %12d  %8s  %6s  %15s / %-15s  %7s  %s', ch, nInc, f1(cap), f1(extra), f1(a1), ...
        f1(a2), f1(chg), strjoin(flags, ', ')); %#ok<AGROW>
end
lines = [lines, gapLines(CH, G)];
block = sprintf('%s\n', lines{:});
end


function lines = gapLines(CH, G)
% report: periods without signal by type, channels that do not end beating
lines = {};
if nargin < 2 || ~istable(G) || ~istable(CH), return; end
types = {'chamber out', 'board group', 'controller', 'saturated'};
parts = {};
for k = 1:numel(types)
    n = sum(strcmp(G.type, types{k}));
    if n > 0, parts{end+1} = sprintf('%d %s', n, types{k}); end %#ok<AGROW>
end
if ~isempty(parts), lines{end+1} = ['  signal gaps: ' strjoin(parts, ', ')]; end
parts = {};
for i = 1:height(CH)
    if ~strcmp(CH.status{i}, 'beating')
        parts{end+1} = sprintf('ch%d %s', CH.channel(i), CH.status{i}); %#ok<AGROW>
    end
end
if ~isempty(parts), lines{end+1} = ['  end of recording: ' strjoin(parts, ', ')]; end
end


% ===================================================================================================== index
function X = emptyIndex()
X = table(cell(0,1), zeros(0,1), cell(0,1), zeros(0,1), cell(0,1), cell(0,1), cell(0,1), cell(0,1), cell(0,1), ...
    cell(0,1), zeros(0,1), zeros(0,1), cell(0,1), cell(0,1), 'VariableNames', indexColumns());
end

function c = indexColumns()
c = {'file','bytes','modified','logBytes','status','version','implementation','code','options','analyzed', ...
    'seconds','nContractions','outputs','message'};
end

function X = readIndex(res)
f = fullfile(res, 'mda_index.csv');
X = emptyIndex();
if ~isfile(f), return; end
txt = fileread(f);
if numel(regexp(txt, '\n', 'match')) < 2, return; end   %header only
o = detectImportOptions(f, 'FileType', 'text', 'Delimiter', ',');
cols = indexColumns();
num = {'bytes', 'logBytes', 'seconds', 'nContractions'};
present = intersect(o.VariableNames, cols, 'stable');
o.SelectedVariableNames = present;
o = setvartype(o, intersect(present, num), 'double');
o = setvartype(o, setdiff(present, num), 'char');
R = readtable(f, o);
for k = 1:numel(cols)
    if ~ismember(cols{k}, R.Properties.VariableNames)
        if ismember(cols{k}, num), R.(cols{k}) = nan(height(R), 1); else, R.(cols{k}) = repmat({''}, height(R), 1); end
    end
end
X = R(:, cols);
end

function X = setRow(X, row)
cols = indexColumns();
i = find(strcmp(X.file, row.file), 1);
if isempty(i)
    i = height(X) + 1;
    X = [X; emptyRow()];
end
for k = 1:numel(cols)
    v = row.(cols{k});
    if ischar(v), X.(cols{k}){i} = v; else, X.(cols{k})(i) = v; end
end
end

function R = emptyRow()
R = table({''}, nan, {''}, nan, {''}, {''}, {''}, {''}, {''}, {''}, nan, nan, {''}, {''}, 'VariableNames', indexColumns());
end

function writeIndex(res, X)
f = fullfile(res, 'mda_index.csv');
tmp = [f '.tmp'];
writetable(X, tmp, 'FileType', 'text', 'Delimiter', ',');
movefile(tmp, f, 'f');
end


% ===================================================================================================== helpers
function F = findRecordings(raw)
D = dir(fullfile(raw, '**', '*'));
D = D(~[D.isdir]);
keep = ~cellfun(@isempty, regexpi({D.name}, '\.mdd$', 'once')) & ~startsWith({D.name}, '.');
D = D(keep);
F = struct('rel', {}, 'file', {}, 'bytes', {}, 'datenum', {});
for k = 1:numel(D)
    f = fullfile(D(k).folder, D(k).name);
    rel = strrep(f(numel(raw)+2:end), filesep, '/');
    if any(startsWith(strsplit(rel, '/'), '.')), continue; end   %hidden folders
    F(end+1) = struct('rel', rel, 'file', f, 'bytes', D(k).bytes, 'datenum', D(k).datenum); %#ok<AGROW>
end
[~, o] = sort({F.rel});
F = F(o);
end

function c = codeFingerprint()
% adler32 (hex) of the core functions (MyoDishAnalysis.m, mda_*.m except the tests)
p = fileparts(which('MyoDishAnalysis'));
D = dir(fullfile(p, 'mda_*.m'));
names = sort([{'MyoDishAnalysis.m'}, {D.name}]);
names = names(~startsWith(names, 'mda_test'));
A = 1; B = 0;
for k = 1:numel(names)
    fid = fopen(fullfile(p, names{k}), 'r');
    b = [double(uint8(names{k})), double(fread(fid, inf, 'uint8=>uint8'))'];
    fclose(fid);
    n = numel(b);
    B = mod(B + n * A + sum((n:-1:1) .* b), 65521);
    A = mod(A + sum(b), 65521);
end
c = sprintf('%08x', B * 65536 + A);
end

function s = optionsText(args, W)
% canonical text of the options that change the results (index column 'options'; same text as in Python)
keys = {'binminutes', 'protocols', 'contractions', 'compress', 'events', 'includeprotocols', 'gaps'};
vals = {valueText(W.binMinutes), valueText(logical(W.protocols)), valueText(char(W.contractions)), ...
    valueText(logical(W.compress)), valueText(logical(W.events)), valueText(logical(W.includeProtocols)), ...
    valueText(logical(W.gaps))};
if ~W.includeProtocols, keys{end+1} = 'protocolmarginseconds'; vals{end+1} = valueText(W.protocolMarginSeconds); end
if strcmp(W.contractions, 'thinned')
    keys(end+1:end+2) = {'thinfactor', 'thinmode'}; vals(end+1:end+2) = {valueText(W.thinFactor), valueText(char(W.thinMode))};
end
for i = 1:2:numel(args)
    k = lower(args{i});
    j = find(strcmp(keys, k), 1);
    if isempty(j), keys{end+1} = k; vals{end+1} = valueText(args{i+1}); %#ok<AGROW>
    else, vals{j} = valueText(args{i+1}); end
end
[keys, o] = sort(keys);
vals = vals(o);
s = strjoin(strcat(keys, '=', vals), '; ');
end

function s = valueText(v)
if isempty(v) && ~ischar(v)
    s = '';
elseif ischar(v) || isstring(v)
    s = char(v);
elseif islogical(v) && isscalar(v)
    s = char('0' + v);
elseif isnumeric(v) && isscalar(v)
    s = sprintf('%.10g', v);
elseif isnumeric(v) || islogical(v)
    s = ['[' strjoin(arrayfun(@(x) sprintf('%.10g', x), double(v(:)'), 'UniformOutput', false), ' ') ']'];
elseif iscell(v)
    s = ['{' strjoin(cellfun(@(x) valueText(x), v(:)', 'UniformOutput', false), ' ') '}'];
else
    s = ['<' class(v) '>'];
end
end

function a = optionArgs(args)
% analysis options without the keywords of MyoDishAnalysis that are no mda_options
keep = true(size(args));
for i = 1:2:numel(args)
    if ismember(lower(args{i}), {'showfigures', 'quiet', 'chunkseconds'}), keep(i:i+1) = false; end
end
a = args(keep);
end

function d = parseDate(s)
d = nan;
if isempty(s), return; end
if isnumeric(s), d = floor(s); return; end
if isdatetime(s), d = floor(datenum(s)); return; end
s = strtrim(char(s));
if ~isempty(regexp(s, '^\d{4}-\d{2}-\d{2}$', 'once')), d = datenum(s, 'yyyy-mm-dd');
elseif ~isempty(regexp(s, '^\d{2}\.\d{2}\.\d{4}$', 'once')), d = datenum(s, 'dd.mm.yyyy');
elseif ~isempty(regexp(s, '^\d{6}$', 'once')), d = datenum(s, 'yymmdd');
else, error('MyoDishAnalysisWatch: fromDate ''yyyy-mm-dd'', ''dd.mm.yyyy'' or ''yymmdd'' expected, not ''%s''.', s);
end
end

function d = parseTime(s)
% 'yyyy-mm-dd HH:MM:SS UTC' (index column 'modified') --> datenum (UTC); NaN if not readable
d = nan;
if ~isempty(regexp(s, '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC$', 'once')), d = datenum(s(1:19), 'yyyy-mm-dd HH:MM:SS'); end
end

function s = utcText(dn)
% local datenum (dir) --> 'yyyy-mm-dd HH:MM:SS UTC': the index is valid on computers in other time zones
t = datetime(dn, 'ConvertFrom', 'datenum', 'TimeZone', 'local');
t.TimeZone = 'UTC';
t.Format = 'yyyy-MM-dd HH:mm:ss';
s = [char(t) ' UTC'];
end

function p = absPath(p)
p = char(p);
if isempty(regexp(p, '^([/\\]|[A-Za-z]:)', 'once')), p = fullfile(pwd, p); end
while numel(p) > 1 && any(p(end) == '/\'), p(end) = []; end
end

function s = f1(x)
if isnan(x), s = ''; else, s = sprintf('%.1f', x); end
end

function s = clean(s)
s = strtrim(regexprep(char(s), '[\r\n,]+', ' '));
end

function deleteFile(f)
if isfile(f), delete(f); end
end

function deleteIfExists(f)
if ~isfile(f), return; end
try
    delete(f);
catch ME
    warning('MyoDishAnalysisWatch: lock file %s could not be deleted (%s); delete it, otherwise the next passes are skipped for 12 h.', f, ME.message);
end
end
