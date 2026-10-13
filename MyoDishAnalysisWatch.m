function [index, report] = MyoDishAnalysisWatch(rawFolder, resultsFolder, varargin)
%MYODISHANALYSISWATCH  Automatic analysis of new MyoDish recordings in a folder (watcher).
%
%   [index, report] = MyoDishAnalysisWatch(rawFolder, resultsFolder, ...)                  one pass
%   MyoDishAnalysisWatch(rawFolder, resultsFolder, 'schedule', 'daily 10:00', ...)         passes on a schedule
%   MyoDishAnalysisWatch('status')       scheduled watchers: schedule, next and last pass (table as first output)
%   MyoDishAnalysisWatch('stop')         stops all scheduled watchers ('stop', resultsFolder: only this one)
%
%   Every pass searches rawFolder (with subfolders) for .mdd files and analyses those that are new or have changed.
%   The watcher only calls the functions of MyoDishAnalysis (MyoDishAnalysis, mda_readMdd, mda_protocols). Recordings
%   analysed earlier with another version of MyoDishAnalysis, other options or (same implementation) other core code
%   are not analysed again by default ('reanalyze','new', 2026-10-12); every pass then shows a notice (command window,
%   top of the txt and PDF reports) with their number and the command that analyses them again ('reanalyze',
%   'outdated'). Earlier results are kept until then. Python: mda-watch (myodish_analysis.watch), same index and
%   results.
%
%   'reanalyze': 'new' (default)   new and changed recordings; recordings with an analysis error are retried when the
%                                  version, the options or the core code change
%                'outdated'        in addition the recordings analysed with another version, other options or other
%                                  core code (e.g. after an update: all of them, can take hours)
%                'all'             every recording again
%
% SCHEDULE ('schedule', 2026-10-12): the watcher runs in the background of this MATLAB session (timer) and checks for
%   new recordings at the given times; MATLAB stays free in between (during a pass it is busy). It stops when MATLAB is
%   closed or with MyoDishAnalysisWatch('stop'). A second schedule for the same results folder replaces the first.
%     'daily 10:00'           every day at 10:00 (first pass at the next 10:00)
%     'weekly Sun 05:00'      every Sunday at 05:00; several days: 'Mon,Thu 06:30'; 'weekdays 07:00' (Mon-Fri)
%     'every 2 days 10:00'    every 2nd day at 10:00 (first pass at the next 10:00)
%     'every 120 min'         first pass now, then every 120 min (also 'every 6 h')
%   Passes that are missed (computer asleep, MATLAB busy, a pass longer than the interval) are not repeated: the next
%   one follows at the next scheduled time.
%
% RESULTS per recording (resultsFolder/<subfolder of rawFolder>/)
%   <name>_summary.csv, _contractions.csv(.gz), _pulses.csv(.gz) (all stimulus pulses, option pulseTable; like the
%   contractions: not written with 'contractions','none', compressed with 'compress',true), _parameters.csv, _info.csv
%   (version, all options, watcher settings),
%   _thresholds.csv (analysis windows), _labels.csv (_rockerFilter.csv); MyoDishAnalysisGUI(<name>_info.csv) opens them
%       summary = one row per channel and time range: time bins of 'binMinutes' (default 60 min) without the periods of
%       the stimulation protocols ('includeProtocols', false, default; a bin with a protocol gives several ranges).
%       range = clock time of the start of the range, bin = clock time of the start of the bin, nComments / comments =
%       comments of the log file in the range (this channel or all channels). Contractions ('contractions'): 'all'
%       (every contraction), 'thinned' (every 'thinFactor'-th contraction per channel, 'thinMode','nth', or the median
%       of blocks of 'thinFactor' contractions, 'thinMode','median'; extra beats and, with 'includeProtocols', the
%       contractions in the protocols are always kept) or 'none'; columns bin, sampledEvery (number of contractions per
%       row) and sampleMode ('singleBeat' / 'median'). 'compress', true: <name>_contractions.csv.gz (gzip level 6).
%   <name>_overview.csv ('overviewSeconds', 60, default; 0 = none): medians of all contractions per window of 1 min
%       (file time, split at the ranges), channel, beat type, rocker state and inclusion: window (clock time of its
%       start), t_from, t_to, nBeats, beatsPerMinute and the median of every parameter. About 1/30 (0.5 Hz) to 1/60
%       (1 Hz) of the rows of all contractions; opens in Excel.
%   <name>_protocols_*.csv (if the log file contains stimulation protocols, 'protocols', true)
%       MyoDishAnalysis(file, [], [], [], 'protocol', 'all', ...): every contraction in the protocols, summary per
%       protocol, channel and group, protocolResults (FFR, ST thresholds, refractory periods, PRP). 'compress', true:
%       _protocols_contractions and _protocols_pulses as .csv.gz.
%   <name>_events.csv ('events', true): all entries of the log file (comments, stimulation and rocker settings,
%       recording, calibration, schedule, warnings) with category, clock time and time in the file
%   <name>_gaps.csv ('gaps', true): periods without force signal (mda_signalGaps): chamber taken out ('chamber out'),
%       sensor board group or controller failures (>= 2 channels within 1 s), saturation, channels without a chamber
%       ('no signal'); with clock times and the comments of the log file within 5 min of the start or end. The summary
%       gets the columns noSignal_s (s without signal in the range) and nChamberOut (chambers taken out in the range).
%   <name>_channels.csv ('gaps', true): one row per channel: recording, recordingStart, fileLength_s, calibration
%       ('Calibration' entries of the log file, AU per mN; several values separated by ';'), status at the
%       end of the recording ('beating', 'not beating' = no contraction in the last 30 min with signal outside the
%       stimulation protocols, 'protocols only' = no time outside the protocols (not analysed), 'removed' = chamber
%       taken out and not put back, 'signal lost' = technical, 'no slice'), beatingAtEnd, s with and without signal,
%       chambers taken out, technical failures, contractions, last contraction (time, clock time, median amplitude of the last 10 included
%       contractions, in % of the 95th percentile of the recording), date of the experiment ID in the file name
%       (6 digits yymmdd, e.g. ABC000101) and days since this date at the last contraction (or the end of the signal),
%       daysInCulture, labels setupID, sliceID, species, sampleID, cultureStart, comments about the slice's end
%       (discarded, removed, not beating, fixed, frozen, ...).
%   Labels per channel (metadata): <name>_labels.csv next to the .mdd file (saved by the GUI), if present.
% SLICE REGISTER ('register', true, 'gaps', true; after each pass with analysed recordings, see mda_sliceRegister)
%   resultsFolder/<experiment>/<experiment>_slices.csv and resultsFolder/mda_slices.csv (all experiments): one row per
%   slice (channel of a setup from putting the slice in until it was taken out, the signal was lost or the data end)
%   with start, end, reason of the start, end status, last contraction and amplitude, days in culture, chamber-out
%   periods. A chamber-out period >= 'newSliceHours' (default 2 h), a recording without signal, a comment such as
%   'new slice' or another sliceID label start a new slice.
% resultsFolder/mda_index.csv
%   one row per recording: file (path relative to rawFolder), bytes, modified (time of the .mdd file, UTC), logBytes, status (ok / error /
%   running / noLog), version, implementation (MATLAB / Python), code (fingerprint of the core functions), options,
%   analyzed, seconds, nContractions, outputs, message. The same file is used by the MATLAB and the Python watcher.
% resultsFolder/reports/mda_report_<date>_<time>.txt
%   report of a pass with analysed recordings: per channel contractions, capture (% of the stimuli followed by a
%   contraction), extra beats (% of the detected contractions), mean amplitude in the first and last range (>= 10
%   included contractions) and flags (no contractions, capture < flagCapture % (not with arrhythmic pacing, summary
%   column arrhythmicPacing: 'arrhythmic pacing'), extra beats > flagExtraBeats %, amplitude change >
%   flagAmplitudeChange %).
% resultsFolder/reports/mda_report_<date>_<time>.pdf ('report', true; 2026-10-11)
%   analysis report of the same pass (mda_report): overview of the recordings x channels with flags, the channels whose
%   analysis should be checked (red: inverted signal; noise suspected = uncertain >= flagUncertain % and extra +
%   missed beats >= flagIrregular %; large extra beats; delay pulse -> onset > flagDelay s; stimulus frequency >
%   flagStimFrequency Hz) and those with slice-quality flags (yellow: capture < flagCapture %, extra beats >
%   flagExtraBeats %, amplitude < flagAmplitude uN, amplitude change > flagAmplitudeChange %, amplitude CV >
%   flagAmplitudeCV %; arrhythmic pacing: no capture and amplitude CV flags); channels with fewer than
%   flagMinBeats detected contractions are not flagged. Pages with traces of the red
%   channels and the commands that open them in the GUI (MyoDishAnalysisGUI(<name>_info.csv, 'channel', c, 'window',
%   [a b]); without 'quiet' also as links in the command window).
%
% SKIPPED while written: files modified less than 'minFileAgeMinutes' ago (default 10), names starting with '.'
%   (rsync temporary files, hidden folders), and recordings whose log file has no 'Recording stopped' entry yet (status
%   'running') unless unchanged for 'incompleteAfterHours' (default 30 h, e.g. aborted recordings). Recordings without
%   log file get the status 'noLog'; they are checked again in every pass. Errors are retried when the file, the
%   version, the options or the code change, or with 'retryErrors'.
%
% OPTIONS (name/value pairs)
%   'schedule', s            passes on a schedule in the background (see SCHEDULE; default '' = one pass)
%   'interval', h            hours between passes (default 0 = one pass; > 0: runs until Ctrl+C, MATLAB stays busy)
%   'reanalyze', m           'new' (default) | 'outdated' | 'all' (see above)
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
%   'overviewSeconds', s     <name>_overview.csv: medians per window of s seconds (default 60, 0 = none)
%   'events', tf             <name>_events.csv and comments in the summary (default true)
%   'gaps', tf               <name>_gaps.csv, <name>_channels.csv, summary columns noSignal_s, nChamberOut (default true)
%   'register', tf           slice register (default true)
%   'newSliceHours', h       slice register: new slice after >= h without signal (default 2)
%   'flagCapture', 'flagExtraBeats', 'flagAmplitudeChange'   report flags (default 90, 10, 30 %)
%   'report', tf             PDF report (default true)
%   'flagUncertain', 'flagIrregular', 'flagAmplitude', 'flagAmplitudeCV', 'flagDelay', 'flagMinBeats',
%   'flagStimFrequency'      flags of the PDF report (default 25 %, 15 %, 75 uN, 30 %, 0.15 s, 50 contractions,
%                            10 Hz; see mda_report)
%   'quiet', tf              no messages
%   all other name/value pairs: analysis options of MyoDishAnalysis for all recordings, e.g. 'rockerFilter', true,
%   'rocker', 'stopped', 'threshold', 300 (not 'output', 'labels', 'metadata', 'protocol', 'groupBy')
%   'settings', file         analysis options from a settings file (mda_settings) or earlier results; the index
%                            records its values (after a change of the file the earlier recordings count as
%                            analysed with other options)
%
% EXAMPLES
%   MyoDishAnalysisWatch('/data/myodish/raw', '/data/myodish/results', 'rockerFilter', true)
%   MyoDishAnalysisWatch(raw, results, 'fromDate', '2026-10-01', 'dryRun', true)
%   MyoDishAnalysisWatch(raw, results, 'schedule', 'daily 10:00')        %every day at 10:00, MATLAB stays free
%   MyoDishAnalysisWatch(raw, results, 'schedule', 'weekly Sun 05:00')   %every Sunday at 05:00
%   MyoDishAnalysisWatch(raw, results, 'schedule', 'every 120 min')      %now and then every 120 min
%   MyoDishAnalysisWatch('status'), MyoDishAnalysisWatch('stop')
%   MyoDishAnalysisWatch(raw, results, 'reanalyze', 'outdated')   %after an update: recordings of another version
%   MyoDishAnalysisWatch(raw, results, 'contractions', 'thinned', 'thinMode', 'median', 'compress', true)
%   Daily without an open MATLAB: the scheduler of the operating system with
%   matlab -batch "MyoDishAnalysisWatch('raw', 'results', 'quiet', true)"   or the Python version (mda-watch).
%
% TS 2026-10-08 (watcher settings in the info table 2026-10-09; pulse table 2026-10-10; PDF report 2026-10-11;
% schedule and 'reanalyze','new' 2026-10-12; arrhythmic pacing, flagStimFrequency 2026-10-13)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

if nargin >= 1 && (ischar(rawFolder) || isstring(rawFolder)) && ...
        any(strcmpi(rawFolder, {'stop', 'status', 'nextPass'})) && ~isfolder(rawFolder)
    switch lower(char(rawFolder))                  %no output: nothing shown as ans
        case 'stop'
            if nargin < 2, resultsFolder = ''; end
            n = stopWatch(resultsFolder, true);
            if nargout > 0, index = n; report = ''; end
        case 'status'
            [T, txt] = watchStatus(nargout == 0);
            if nargout > 0, index = T; report = txt; end
        case 'nextpass'                                %MyoDishAnalysisWatch('nextPass', schedule, prev, now) (tests)
            a = [varargin, cell(1, 2)];
            if isempty(a{2}), a{2} = now; end
            index = nextPass(parseSchedule(resultsFolder), a{1}, a{2});
            report = '';
    end
    return;
end

W = struct('interval', 0, 'schedule', '', 'reanalyze', 'new', 'retryErrors', false, 'fromDate', '', 'filter', '', ...
    'maxFiles', inf, 'dryRun', false, 'minFileAgeMinutes', 10, 'incompleteAfterHours', 30, 'binMinutes', 60, ...
    'includeProtocols', false, 'protocolMarginSeconds', 0, 'protocols', true, 'contractions', 'all', ...
    'thinFactor', 10, 'thinMode', 'nth', 'compress', false, 'overviewSeconds', 60, 'events', true, 'gaps', true, ...
    'register', true, 'newSliceHours', 2, ...
    'flagCapture', 90, 'flagExtraBeats', 10, 'flagAmplitudeChange', 30, 'report', true, 'flagUncertain', 25, ...
    'flagIrregular', 15, 'flagAmplitude', 75, 'flagAmplitudeCV', 30, 'flagDelay', 0.15, 'flagMinBeats', 50, ...
    'flagStimFrequency', 10, 'quiet', false);
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
    error('MyoDishAnalysisWatch: ''reanalyze'': ''new'', ''outdated'' or ''all'' expected.');
end
W.contractions = lower(char(W.contractions)); W.thinMode = lower(char(W.thinMode));
if ~ismember(W.contractions, {'all', 'thinned', 'none'})
    error('MyoDishAnalysisWatch: ''contractions'': ''all'', ''thinned'' or ''none'' expected.');
end
if ~ismember(W.thinMode, {'nth', 'median'}), error('MyoDishAnalysisWatch: ''thinMode'': ''nth'' or ''median'' expected.'); end
if ~isscalar(W.thinFactor) || W.thinFactor < 1 || W.thinFactor ~= round(W.thinFactor)
    error('MyoDishAnalysisWatch: ''thinFactor'': integer >= 1 expected.');
end
if ~isscalar(W.overviewSeconds) || ~(W.overviewSeconds >= 0)
    error('MyoDishAnalysisWatch: ''overviewSeconds'': number >= 0 expected (0 = no overview).');
end
args = expandSettings(args);                       %settings file: its values (2026-10-10)
raw = absPath(rawFolder);
res = absPath(resultsFolder);
if ~isfolder(raw), error('MyoDishAnalysisWatch: folder not found: %s', raw); end
oa = optionArgs(args);
mda_options(oa{:});                                    %unknown analysis options: error now
if ~isempty(W.schedule)                                %passes on a schedule in the background (timer, 2026-10-12)
    if W.interval > 0
        error(['MyoDishAnalysisWatch: ''schedule'' and ''interval'' cannot be combined (''interval'', h is ' ...
            '''schedule'', ''every <h> h'').']);
    end
    spec = parseSchedule(W.schedule);
    stopWatch(res, false);                             %a scheduled watcher of the same results folder is replaced
    st = struct('raw', raw, 'res', res, 'W', W, 'args', {args}, 'spec', spec, 'next', nextPass(spec, [], now), ...
        'last', NaN, 'lastText', '');
    tm = timer('Name', 'MyoDishAnalysisWatch', 'Tag', 'MyoDishAnalysisWatch', 'ExecutionMode', 'fixedSpacing', ...
        'Period', 30, 'BusyMode', 'drop', 'StartDelay', 1, 'TimerFcn', @scheduledPass, 'UserData', st);
    start(tm);
    if nargout > 0, index = readIndex(res); end
    report = sprintf(['watcher scheduled (''%s''): next pass %s. MyoDishAnalysisWatch(''status'') shows the ' ...
        'scheduled watchers, MyoDishAnalysisWatch(''stop'') stops them (they run while this MATLAB session is open).'], ...
        W.schedule, datestr(st.next, 'yyyy-mm-dd HH:MM'));
    if ~W.quiet, fprintf('%s\n', report); end
    return;
end
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
function [X, report, nDone] = onePass(raw, res, W, args)
if ~isfolder(res), mkdir(res); end
lock = fullfile(res, 'mda_watch.lock');
nDone = 0;
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
[X, report, nDone] = scanAndAnalyse(raw, res, W, args);
end


function [X, report, nDone] = scanAndAnalyse(raw, res, W, args)
report = ''; nDone = 0;
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
stale = cell(0, 2);                                    %kept results of another version / other options ('new')
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
    elseif ~isempty(r) && strcmp(r.status{1}, 'ok')
        od = outdatedOf(r, version, code, otext);
        if ~isempty(od), stale(end+1, :) = {od, r.version{1}}; end %#ok<AGROW>
    end
end
todo = todo(1:min(size(todo,1), W.maxFiles), :);
notice = updateNotice(stale, version, raw, res);
if ~W.quiet
    fprintf('%s  %s: %d recording(s) to analyse\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), raw, size(todo,1));
    for k = 1:numel(notice), fprintf('NOTE: %s\n', notice{k}); end
end
if W.dryRun
    for k = 1:size(todo,1), fprintf('  %s  (%s)\n', todo{k,1}, todo{k,8}); end
    report = strjoin(notice, newline);
    return;
end
blocks = {};
done = {};                                             %rows of the analysed recordings (PDF report)
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
        done{end+1} = row; %#ok<AGROW>
    end
    if ~W.quiet && ~strcmp(row.status, 'ok'), fprintf('  %s: %s: %s\n', rel, row.status, row.message); end
    X = setRow(X, row);
    writeIndex(res, X);
end
if size(todo, 1) > 0                                   %index in the order of the files
    X = sortrows(X, 'file');
    writeIndex(res, X);
end
reg = '';
if size(todo, 1) > 0 && W.register && W.gaps          %slice register of the experiments with analysed recordings
    exps = cell(size(todo, 1), 1);
    for k = 1:size(todo, 1)
        j = find(todo{k,1} == '/', 1, 'last');
        if isempty(j), exps{k} = ''; else, exps{k} = todo{k,1}(1:j-1); end
    end
    exps = unique(exps);
    try
        R = mda_sliceRegister(res, exps, 'newSliceHours', W.newSliceHours);
        reg = sprintf('slice register: %d slices in %d experiment(s), mda_slices.csv\n', height(R), numel(exps));
    catch ME
        reg = [clean(sprintf('slice register: %s: %s', ME.identifier, ME.message)) newline];
    end
end
if ~isempty(blocks)
    blocks = sort(blocks);
    now_ = now;
    nt = '';
    if ~isempty(notice), nt = [sprintf('NOTE: %s\n', notice{:}) newline]; end
    report = sprintf('MyoDishAnalysis %s (MATLAB) watcher report %s\nraw folder: %s\nresults:    %s\noptions:    %s\n\n%s%s', ...
        version, datestr(now_, 'yyyy-mm-dd HH:MM:SS'), raw, res, otext, nt, strjoin(blocks, newline));
    if ~isempty(reg), report = [report newline reg]; end
    dr = fullfile(res, 'reports');
    if ~isfolder(dr), mkdir(dr); end
    R = [];
    if W.report                                        %analysis report (PDF, 2026-10-11)
        pdf = fullfile(dr, ['mda_report_' datestr(now_, 'yyyy-mm-dd_HHMMSS') '.pdf']);
        [~, o] = sort(cellfun(@(r) r.file, done, 'UniformOutput', false));
        try
            R = pdfReport(pdf, raw, res, done(o), W, version, otext, now_, notice);
            n = sum(strcmp(R.level, 'check'));
            ln = sprintf('PDF report: %s%s', pdf, repmat(sprintf(' (%d channel(s) to check)', n), 1, n > 0));
        catch ME
            ln = clean(sprintf('PDF report: %s: %s', ME.identifier, ME.message));
        end
        report = [report newline ln newline];
    end
    fid = fopen(fullfile(dr, ['mda_report_' datestr(now_, 'yyyy-mm-dd_HHMMSS') '.txt']), 'w', 'n', 'UTF-8');
    fwrite(fid, unicode2native(report, 'UTF-8'));
    fclose(fid);
    if ~W.quiet
        fprintf('\n%s\n', report);
        if ~isempty(R)                                 %channels to check: links that open them in the GUI
            for j = find(strcmp(R.level, 'check'))'
                if feature('hotlinks')
                    fprintf('  <a href="matlab:%s">%s ch %d</a>: %s\n', R.matlab{j}, R.recording{j}, R.channel(j), R.red{j});
                else
                    fprintf('  %s\n', R.matlab{j});
                end
            end
        end
    end
elseif ~isempty(notice)
    report = strjoin(notice, newline);
end
nDone = numel(done);
end


function R = pdfReport(out, raw, res, rows, W, version, otext, now_, notice)
% analysis report (mda_report) of the recordings of this pass, from their result files
ccols = {'channel', 't_peak', 'beatType', 'uncertain', 'included', 'amplitude', 'stimToOnset'};
fl = struct('uncertain', W.flagUncertain, 'irregular', W.flagIrregular, 'extra', W.flagExtraBeats, 'capture', ...
    W.flagCapture, 'amplitudeChange', W.flagAmplitudeChange, 'amplitude', W.flagAmplitude, 'amplitudeCV', ...
    W.flagAmplitudeCV, 'delay', W.flagDelay, 'minBeats', W.flagMinBeats, 'stimFrequency', W.flagStimFrequency);
recs = struct('name', {}, 'file', {}, 'open', {}, 'S', {}, 'C', {}, 'P', {}, 'P_file', {}, 'R', {}, 'status', {}, ...
    'notes', {});
for i = 1:numel(rows)
    row = rows{i};
    rel = row.file;
    [d, n] = fileparts(strrep(rel, '\', '/'));
    d = fullfile(res, d);
    rec = struct('name', rel, 'file', fullfile(raw, rel), 'open', fullfile(d, [n '_info.csv']), 'S', [], 'C', [], ...
        'P', [], 'P_file', '', 'R', [], 'status', [], 'notes', {{}});
    if ~strcmp(row.status, 'ok')
        rec.notes = {clean(['error: ' row.message])};
        recs(end+1) = rec; %#ok<AGROW>
        continue;
    end
    rec.S = readResult(fullfile(d, [n '_summary.csv']), {});
    C = readResult(fullfile(d, [n '_contractions.csv']), ccols);
    rec.status = readResult(fullfile(d, [n '_channels.csv']), {'channel', 'status'});
    m = strtrim(strsplit(row.message, ' | '));
    rec.notes = m(startsWith(m, 'protocols:'));
    % flags now; contractions kept and pulses read (detail pages) only for recordings with channels to check: memory
    % of passes with thousands of recordings
    rec.R = mda_report('flags', rec.S, C, rec.status, fl);
    if any(strcmp(rec.R.level, 'check')), rec.C = C; end
    rec.P_file = fullfile(d, [n '_pulses.csv']);
    recs(end+1) = rec; %#ok<AGROW>
end
sub = {['raw folder: ' raw], ['results: ' res], sprintf(['MyoDishAnalysis %s (MATLAB) watcher, %s: %d recording(s) ' ...
    'analysed in this pass; options: %s'], version, datestr(now_, 'yyyy-mm-dd HH:MM:SS'), numel(rows), otext)};
R = mda_report(recs, out, 'title', 'MyoDishAnalysis watcher report', 'subtitle', sub, 'flags', fl, 'notice', notice);
end


function T = readResult(f, cols)
% result table f or f.gz ([] if neither exists); cols: only these columns ({} = all); text columns as char
T = [];
src = f; tmp = '';
if ~isfile(f)
    if ~isfile([f '.gz']), return; end
    tmp = tempname; mkdir(tmp);                        %readtable does not read .gz
    gunzip([f '.gz'], tmp);
    [~, n, e] = fileparts(f);
    src = fullfile(tmp, [n e]);
end
try
    o = detectImportOptions(src, 'FileType', 'text', 'Delimiter', ',', 'VariableNamingRule', 'preserve');
    o.VariableNamesLine = 1; o.DataLines = [2 Inf];
    if ~isempty(cols), o.SelectedVariableNames = intersect(cols, o.VariableNames, 'stable'); end
    for k = 1:numel(o.SelectedVariableNames)
        j = strcmp(o.VariableNames, o.SelectedVariableNames{k});
        if any(strcmp(o.VariableTypes{j}, {'string', 'datetime', 'categorical'}))
            o = setvartype(o, o.SelectedVariableNames{k}, 'char');
        end
    end
    T = readtable(src, o);
catch
    T = [];
end
if ~isempty(tmp), rmdir(tmp, 's'); end
end


function od = outdatedOf(r, version, code, otext)
% 'other version' / 'other options' / 'core code changed' (same implementation) / ''
od = '';
if ~strcmp(r.version{1}, version)
    od = 'other version';
elseif ~strcmp(r.options{1}, otext)
    od = 'other options';
elseif strcmp(r.implementation{1}, 'MATLAB') && ~strcmp(r.code{1}, code)
    od = 'core code changed';
end
end


function lines = updateNotice(stale, version, raw, res)
% lines of the notice about recordings that were analysed with another version, other options or other core code
% and kept ('reanalyze','new'); stale = {reason, version of the index} per recording
lines = {};
if isempty(stale), return; end
isOpt = strcmp(stale(:, 1), 'other options');
v = stale(~isOpt, 2);
code = strcmp(stale(~isOpt, 1), 'core code changed');
v(code) = strcat(v(code), {' with other core code'});
if ~isempty(v)
    [u, ~, j] = unique(v);
    parts = arrayfun(@(k) sprintf('%s: %d', u{k}, sum(j == k)), 1:numel(u), 'UniformOutput', false);
    lines{end+1} = sprintf(['MyoDishAnalysis has been updated (now %s): %d recording(s) were analysed with another ' ...
        'version (%s). This may change the results or lead to inconsistencies with new data (see the release notes, ' ...
        'CHANGELOG.md).'], version, numel(v), strjoin(parts, ', '));
end
if any(isOpt)
    lines{end+1} = sprintf(['The analysis options have changed: %d recording(s) were analysed with other options ' ...
        '(index column ''options''); their results may not be comparable with those of new recordings.'], sum(isOpt));
end
q = @(x) strrep(x, '''', '''''');
lines{end+1} = sprintf(['The earlier results were kept. To analyse these recordings again: MyoDishAnalysisWatch(''%s'', ' ...
    '''%s'', ''reanalyze'', ''outdated'') (with your other options)'], q(raw), q(res));
end


% ===================================================================================================== schedule
function spec = parseSchedule(text)
% schedule text -> struct: kind 'interval' (seconds; first pass now), 'days' (every n days at hour:minute) or 'weekly'
% (days 0 = Monday ... 6 = Sunday at hour:minute). Same rules as watch.py (parse_schedule).
s = lower(strtrim(char(text)));
s = regexprep(regexprep(s, '\s*,\s*', ', '), '\s+', ' ');
msg = sprintf(['MyoDishAnalysisWatch: ''schedule'': ''daily 10:00'', ''weekly Sun 05:00'', ''Mon,Thu 06:30'', ' ...
    '''weekdays 07:00'', ''every 2 days 10:00'', ''every 120 min'' or ''every 6 h'' expected, not ''%s''.'], char(text));
spec = struct('kind', '', 'seconds', NaN, 'every', 1, 'hour', 0, 'minute', 0, 'days', []);
t = regexp(s, '^every (\d+(?:\.\d+)?) ?(min|mins|minute|minutes|m|h|hr|hrs|hour|hours)$', 'tokens', 'once');
if ~isempty(t)
    spec.kind = 'interval';
    spec.seconds = str2double(t{1}) * 3600;
    if t{2}(1) == 'm', spec.seconds = str2double(t{1}) * 60; end
    if spec.seconds < 60, error('MyoDishAnalysisWatch: ''schedule'': interval of at least 1 min expected.'); end
    return;
end
t = regexp(s, '^(daily|every day|every \d+ days?)(?: at)? (\d{1,2}):(\d{2})$', 'tokens', 'once');
if ~isempty(t)
    n = str2double(regexp(t{1}, '\d+', 'match', 'once'));
    if isnan(n), n = 1; end
    h = str2double(t{2}); mi = str2double(t{3});
    if n < 1 || h > 23 || mi > 59, error(msg); end
    spec.kind = 'days'; spec.every = n; spec.hour = h; spec.minute = mi;
    return;
end
t = regexp(s, '^(?:weekly |every )?([a-z][a-z, ]*?)(?: at)? (\d{1,2}):(\d{2})$', 'tokens', 'once');
if isempty(t), error(msg); end
names = {'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'};
days = [];
for tok = strsplit(strtrim(t{1}), {' ', ','}, 'CollapseDelimiters', true)
    switch tok{1}
        case {'weekdays', 'workdays'}, days = [days 0:4]; %#ok<AGROW>
        case {'weekend', 'weekends'}, days = [days 5 6]; %#ok<AGROW>
        otherwise
            k = find(startsWith(names, tok{1}));
            if numel(tok{1}) < 2 || numel(k) ~= 1, error(msg); end
            days(end+1) = k - 1; %#ok<AGROW>
    end
end
h = str2double(t{2}); mi = str2double(t{3});
if isempty(days) || h > 23 || mi > 59, error(msg); end
spec.kind = 'weekly'; spec.days = unique(days); spec.hour = h; spec.minute = mi;
end


function t = nextPass(spec, prev, nowT)
% time of the next pass (datenum, local time) after the pass planned for prev ([] = first pass)
switch spec.kind
    case 'interval'
        if isempty(prev), t = nowT; return; end
        step = spec.seconds / 86400;
        t = prev + step;
        while t <= nowT, t = t + step; end              %missed passes are not repeated
    case 'days'
        at = floor(nowT) + (spec.hour * 60 + spec.minute) / 1440;
        if isempty(prev)
            t = at; if t <= nowT, t = t + 1; end
            return;
        end
        t = prev + spec.every;
        while t <= nowT, t = t + spec.every; end
    otherwise
        at = floor(nowT) + (spec.hour * 60 + spec.minute) / 1440;
        for k = 0:7
            t = at + k;
            if t > nowT && ismember(mod(weekday(t) + 5, 7), spec.days), return; end   %0 = Monday
        end
end
end


function scheduledPass(tm, ~)
% timer callback (every 30 s): a pass when its time has come
st = tm.UserData;
if now < st.next, return; end
try
    [~, rep, n] = onePass(st.raw, st.res, st.W, st.args);
    if startsWith(rep, 'another watcher'), st.lastText = rep; else, st.lastText = sprintf('%d recording(s) analysed', n); end
catch ME
    st.lastText = clean(['error: ' ME.message]);
    if ~st.W.quiet, fprintf(2, 'MyoDishAnalysisWatch: %s\n', st.lastText); end
end
st.last = now;
st.next = nextPass(st.spec, st.next, now);
if isvalid(tm), tm.UserData = st; end
if ~st.W.quiet
    fprintf('next pass %s (schedule ''%s''; MyoDishAnalysisWatch(''stop'') stops the watcher)\n', ...
        datestr(st.next, 'yyyy-mm-dd HH:MM'), st.W.schedule);
end
end


function [T, txt] = watchStatus(show)
% scheduled watchers (table) and their description
tms = timerfindall('Tag', 'MyoDishAnalysisWatch');
n = numel(tms);
[res, raw, sch, nxt, lst, lastResult, lines] = deal(cell(n, 1));
for i = 1:n
    st = tms(i).UserData;
    res{i} = st.res; raw{i} = st.raw; sch{i} = st.W.schedule; nxt{i} = datestr(st.next, 'yyyy-mm-dd HH:MM');
    if isnan(st.last), lst{i} = ''; else, lst{i} = datestr(st.last, 'yyyy-mm-dd HH:MM'); end
    lastResult{i} = st.lastText;
    lines{i} = sprintf('%s (raw %s): ''%s'', next pass %s', res{i}, raw{i}, sch{i}, nxt{i});
    if ~isempty(lst{i}), lines{i} = sprintf('%s, last pass %s (%s)', lines{i}, lst{i}, lastResult{i}); end
end
T = table(res, raw, sch, nxt, lst, lastResult, 'VariableNames', ...
    {'resultsFolder', 'rawFolder', 'schedule', 'nextPass', 'lastPass', 'lastResult'});
if n == 0, txt = 'no scheduled watcher'; else, txt = strjoin(lines, newline); end
if show, fprintf('%s\n', txt); end
end


function n = stopWatch(res, show)
% stops the scheduled watchers (of the results folder res; '' = all)
tms = timerfindall('Tag', 'MyoDishAnalysisWatch');
n = 0;
if ~isempty(res), res = absPath(res); end
for i = 1:numel(tms)
    st = tms(i).UserData;
    if isempty(res) || (isstruct(st) && strcmp(st.res, res))
        stop(tms(i)); delete(tms(i)); n = n + 1;
    end
end
if show, fprintf('%d scheduled watcher(s) stopped\n', n); end
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
outdated = outdatedOf(r, version, code, otext);
mode = lower(W.reanalyze);
if strcmp(status, 'error')        %no results to keep: retried when the version, the options or the core code change
    if W.retryErrors, why = 'retry error';
    elseif ~isempty(outdated), why = ['retry error, ' outdated];
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
deleteFile(fullfile(outDir, [n '_pulses.csv']));
deleteFile(fullfile(outDir, [n '_pulses.csv.gz']));
deleteFile(fullfile(outDir, [n '_overview.csv']));
for sfx = {'_protocols_contractions.csv', '_protocols_pulses.csv'}
    deleteFile(fullfile(outDir, [n sfx{1}]));
    deleteFile(fullfile(outDir, [n sfx{1} '.gz']));
end
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
    if W.overviewSeconds > 0 && nC > 0
        writetable(overview(C, labels, fr, to, H, W.overviewSeconds), fullfile(outDir, [n '_overview.csv']));
        outputs{end+1} = [n '_overview.csv'];
    end
    if W.includeProtocols, Wkeep = Wp; else, Wkeep = []; end
    C = sampleContractions(C, labels, Wkeep, W);
    mda_writeResults(fullfile(outDir, [n '.csv']), C, S, info);
    for cf = {fullfile(outDir, [n '_contractions.csv']), fullfile(outDir, [n '_pulses.csv'])}
        if ~isfile(cf{1}), continue; end            %pulses: option pulseTable
        if strcmp(W.contractions, 'none')
            delete(cf{1});
        elseif W.compress
            gzip(cf{1});
            delete(cf{1});
        end
    end
    outputs = [{[n '.csv']}, outputs];
    msgs = [info.notes(:)', msgs];
else
    msgs{end+1} = 'no time outside the stimulation protocols';
    Call = [];
end
CH = [];
if W.gaps && istable(G)
    if isempty(to), tEnd = nan; else, tEnd = max(to); end
    CH = channelStatus(H, Call, G, E, n, mda_labels(meta, H.dataChannels), tEnd);
    writetable(CH, fullfile(outDir, [n '_channels.csv']));
    outputs{end+1} = [n '_channels.csv'];
end
if W.protocols && istable(P) && height(P) > 0
    try
        [~, ~, pinfo] = MyoDishAnalysis(f, [], [], [], 'protocol', 'all', 'metadata', meta, 'quiet', true, ...
            'output', fullfile(outDir, [n '_protocols.csv']), 'report', false, args{:});
        outputs{end+1} = [n '_protocols.csv'];
        nt = pinfo.notes(contains(pinfo.notes, 'not analysed'));      %single protocols (2026-10-11)
        if ~isempty(nt), msgs = [msgs, strcat('protocols: ', nt(:)')]; end
        if W.compress                               %protocol contractions and pulses as well (2026-10-11)
            for cf = {fullfile(outDir, [n '_protocols_contractions.csv']), fullfile(outDir, [n '_protocols_pulses.csv'])}
                if isfile(cf{1}), gzip(cf{1}); delete(cf{1}); end
            end
        end
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


function T = channelStatus(H, C, G, E, name, L, tEnd)
% one row per channel: recording, its start and length, status at the end of the recording, signal, gaps, last
% contraction, labels (setupID, sliceID, species, sampleID, cultureStart), comments about the end. tEnd = end of the
% analysed ranges (stimulation protocols at the end are not analysed; NaN: protocols only)
if nargin < 7, tEnd = inf; end
chs = H.dataChannels(:);
nCh = numel(chs);
TT = H.totalSeconds;
start = '';
if ~isnan(H.recordingStart), start = timeLabel(H, 0, 0); end
labNames = {'setupID', 'sliceID', 'species', 'sampleID', 'cultureStart'};
lab = repmat({''}, nCh, numel(labNames));
for i = 1:nCh
    for j = 1:numel(labNames)
        if nargin >= 6 && istable(L) && ismember(labNames{j}, L.Properties.VariableNames)
            k = find(L.channel == chs(i), 1);
            if isempty(k), continue; end
            v = L.(labNames{j})(k);
            if iscell(v), v = v{1}; end
            if isnumeric(v) && (isempty(v) || isnan(v)), v = ''; end
            if isnumeric(v), v = sprintf('%.15g', v); end
            lab{i,j} = char(v);
        end
    end
end
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
    if height(cc) > 0, tLast(i) = max(cc.t_peak); end  %also without signal (artifacts, e.g. chambers put back)
    if any(strcmp(g.type, 'no signal'))
        status{i} = 'no slice';
    else
        firstS(i) = 0; lastS(i) = TT;
        k = find(g.fromStart & ~g.untilEnd, 1); if ~isempty(k), firstS(i) = g.to(k); end
        k = find(g.untilEnd & ~g.fromStart, 1); if ~isempty(k), lastS(i) = g.from(k); end
        lastEff = min(lastS(i), tEnd);                 %end of the analysed signal
        beatEnd(i) = ~isnan(tLast(i)) && ~isnan(lastEff) && lastEff - tLast(i) <= 1800;
        if ~isempty(k) && strcmp(g.type{k}, 'chamber out')
            status{i} = 'removed';
        elseif ~isempty(k)
            status{i} = 'signal lost';
        elseif isnan(tEnd)
            status{i} = 'protocols only';
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
% 'Calibration' entries of the log file per channel (AU per mN; channel 0 = all channels), in the order of time,
% several values separated by ';' (2026-10-10: changes are flagged in the slice register)
cal = repmat({''}, nCh, 1);
if isfield(H, 'calibrationLog') && ~isempty(H.calibrationLog)
    CL = sortrows(H.calibrationLog, 1);
    for i = 1:nCh
        v = CL(CL(:,2) == chs(i) | CL(:,2) == 0, 3);
        if isempty(v), continue; end
        v = v([true; diff(v) ~= 0]);
        cal{i} = strjoin(arrayfun(@(x) sprintf('%.15g', x), v', 'UniformOutput', false), ';');
    end
end
T = table(repmat({name}, nCh, 1), repmat({start}, nCh, 1), repmat(TT, nCh, 1), chs, cal, status, beatEnd, sig, ...
    noSig, nOut, nTech, firstS, lastS, nCon, tLast, clk, aLast, aMax, aPct, repmat({idTxt}, nCh, 1), dId, dCul, ...
    lab(:,1), lab(:,2), lab(:,3), lab(:,4), lab(:,5), endTxt, 'VariableNames', {'recording', 'recordingStart', ...
    'fileLength_s', 'channel', 'calibration', 'status', 'beatingAtEnd', 'signal_s', 'noSignal_s', 'nChamberOut', ...
    'nTechnical', 'firstSignal_s', 'lastSignal_s', 'nContractions', 'lastContraction_s', 'lastContractionClock', ...
    'lastAmplitude', 'maxAmplitude', 'lastAmplitude_pctMax', 'idDate', 'daysSinceIdDate', 'daysInCulture', 'setupID', ...
    'sliceID', 'species', 'sampleID', 'cultureStart', 'endComments'});
end


function O = overview(C, labels, fr, to, H, w)
% medians of all contractions per window of w s (file time; split at the ranges), channel, beat type, rocker state
% and inclusion: one row per group with window (clock time of its start), t_from, t_to, nBeats, beatsPerMinute (per s
% of the window in the range) and the median of every numeric parameter
fr = fr(:); to = to(:);
[~, rI] = ismember(C.range, labels);
win = floor(C.t_peak / w);
[btU, ~, btI] = unique(C.beatType);
rock = logical(C.rockerMoving); inc = logical(C.included);
K = [C.channel, rI, win, btI, double(rock), double(~inc)];
[K, o] = sortrows(K);
newG = [true; any(diff(K, 1, 1) ~= 0, 2)];
g = cumsum(newG);
first = o(newG);
nG = numel(first);
keys = {'contraction', 'channel', 't_peak', 't_stim', 'clockTime', 'sampledEvery', 'beatType', 'rockerMoving', ...
    'included', 'range', 'bin', 'sampleMode'};
labNames = {'setupID', 'sliceID', 'species', 'sampleID', 'sampleGroup', 'sliceGroup', 'tissue', 'treatment', ...
    'concentration', 'concentrationUnit', 'daysInCulture', 'cultureStart', 'comment', 'analyst'};
v = C.Properties.VariableNames;
lab = v(ismember(v, labNames));
lab = labNames(ismember(labNames, lab));
num = v(~ismember(v, [keys, lab]) & cellfun(@(x) isnumeric(C.(x)) && ~islogical(C.(x)), v));
A = C{o, num};
O = C(first, [{'range', 'bin', 'channel'}, lab]);
a = max(win(first) * w, fr(rI(first)));
b = min((win(first) + 1) * w, round(to(rI(first)) * 1e6) / 1e6);
O.window = arrayfun(@(x) timeLabel(H, x, x), a, 'UniformOutput', false);
O.t_from = a;
O.t_to = b;
O.beatType = btU(btI(first));
O.rockerMoving = double(rock(first));
O.included = double(inc(first));
nB = accumarray(g, 1);
O.nBeats = nB;
bpm = nan(nG, 1); k = b > a; bpm(k) = 60 * nB(k) ./ (b(k) - a(k));
O.beatsPerMinute = bpm;
M = nan(nG, numel(num));
st = [find(newG); numel(newG) + 1];
for i = 1:nG
    M(i, :) = median(A(st(i):st(i+1)-1, :), 1, 'omitnan');
end
for j = 1:numel(num)
    O.(num{j}) = M(:, j);
end
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
    arr = false;
    if ismember('arrhythmicPacing', s.Properties.VariableNames)
        x = s.arrhythmicPacing;
        if iscell(x) || isstring(x), arr = any(strcmpi(string(x), "true") | string(x) == "1");
        else, arr = any(double(x) ~= 0 & ~isnan(double(x))); end
    end
    flags = {};
    if nDet == 0
        flags{end+1} = 'no contractions'; %#ok<AGROW>
    elseif arr                                      %capture < 100 % expected (2026-10-13)
        flags{end+1} = 'arrhythmic pacing'; %#ok<AGROW>
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
% adler32 (hex) of the core functions (MyoDishAnalysis.m, mda_*.m except the tests and the slice register)
p = fileparts(which('MyoDishAnalysis'));
D = dir(fullfile(p, 'mda_*.m'));
names = sort([{'MyoDishAnalysis.m'}, {D.name}]);
names = names(~startsWith(names, 'mda_test') & ~strcmp(names, 'mda_sliceRegister.m'));
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
keys = {'binminutes', 'protocols', 'contractions', 'compress', 'events', 'includeprotocols', 'gaps', ...
    'overviewseconds'};
vals = {valueText(W.binMinutes), valueText(logical(W.protocols)), valueText(char(W.contractions)), ...
    valueText(logical(W.compress)), valueText(logical(W.events)), valueText(logical(W.includeProtocols)), ...
    valueText(logical(W.gaps)), valueText(W.overviewSeconds)};
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

function a = expandSettings(args)
% option 'settings' (settings file, mda_settings): the options of the file that differ from the defaults as name /
% value pairs, the other options given override them. The index records the values, not the file name: a changed
% settings file analyses the recordings again (reanalyze 'outdated').
j = find(strcmpi(args(1:2:end), 'settings'));
if isempty(j), a = args; return; end
f = args{2 * j(end)};
keep = true(size(args)); keep([2*j-1, 2*j]) = false;
rest = args(keep);
a = {};
if isempty(f), a = rest; return; end
St = mda_settings('load', f);
D = mda_options();
given = lower(rest(1:2:end));
for k = fieldnames(St)'
    if strcmp(k{1}, 'referenceBeat') || ismember(lower(k{1}), given), continue; end
    if ~strcmp(valueText(St.(k{1})), valueText(D.(k{1}))), a(end+1:end+2) = {k{1}, St.(k{1})}; end %#ok<AGROW>
end
a = [a, rest];
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
