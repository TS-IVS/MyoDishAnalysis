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
% RESULT FOLDERS ('folders', 2026-10-15): a quick overview instead of hundreds of files in one folder
%   'series' (default)   resultsFolder/<experiment>/<series>/<nn>/ for recordings with a number in the name
%                        (ABC000101/Setup1_ABC000101_3.mdd -> ABC000101/Setup1_ABC000101/03/; also its parallel recordings,
%                        e.g. Setup1_ABC000101_3_scheduleFile_..._daily6am.mdd), resultsFolder/<experiment>/<name>/ for
%                        recordings without a number (experiment = folder of the recording in rawFolder, series =
%                        name up to its number, see mda_sliceRegister)
%   'flat'               resultsFolder/<experiment>/ (all files of an experiment in one folder, as before)
%   Per experiment (with 'trends', 'register', 'report'; see SLICE REGISTER, TREND IMAGES, REPORTS):
%     <experiment>/<experiment>_overview.png   all setups x channels at a glance (amplitude since the start, status,
%                                              last 24 h, red flags)
%     <experiment>/<experiment>_report.pdf     analysis report of all recordings of the experiment
%     <experiment>/<experiment>_slices.csv     slice register
%     <experiment>/<series>/<series>_ch<c>.png course of each channel: since the start and the last 24 h
%     <experiment>/<series>/<series>_trends.xlsx   the data of these images
%     <experiment>/<series>/<nn>/              the results of each recording (below) and its trend images
%   The readers (GUI, results browser, flags, slice register, 'trends') take both layouts. Results of earlier passes in
%   the other layout are moved when a recording is analysed again; MyoDishAnalysisWatch('reorganize', resultsFolder)
%   moves all of them at once (and 'reorganize', resultsFolder, 'folders', 'flat' back).
% RESULTS per recording ('resultFormat', 'xlsx', default since 2026-10-14)
%   <name>.xlsx               sheets summary, trends, trendComments, channels, gaps, events, parameters, info (version,
%                             all options, watcher settings), thresholds (analysis windows), labels (rockerFilter): the
%                             tables described below; MyoDishAnalysisGUI(<name>.xlsx) opens the analysis
%   <name>_contractions.csv.gz, <name>_pulses.csv.gz (all stimulus pulses, option pulseTable), <name>_overview.csv.gz:
%                             the large tables (gzip; much faster to write and read than sheets, no row limit)
%   <name>_protocols.xlsx, <name>_protocols_contractions.csv.gz, _protocols_pulses.csv.gz   stimulation protocols
%   <name>_ch<c>.png          trend image per channel ('trends', true; see TREND IMAGES; flat layout: in trends/)
%   'resultFormat', 'csv': one file per table as before: <name>_summary.csv, _contractions.csv(.gz), _pulses.csv(.gz),
%   _parameters.csv, _info.csv, _thresholds.csv, _labels.csv (_rockerFilter.csv), _overview.csv, _events.csv,
%   _gaps.csv, _channels.csv, _trends.csv, _trendComments.csv, _protocols_*.csv ('compress', true: contractions and
%   pulses as .csv.gz). The readers
%   (GUI, results browser, flags, slice register) take both formats; recordings are not analysed again because of
%   the format ('reanalyze', 'all' converts the results). Tables (sheets or files):
%       contractions: not written with 'contractions','none'
%       summary = one row per channel and time range: time bins of 'binMinutes' (default 60 min) without the periods of
%       the stimulation protocols ('includeProtocols', false, default; a bin with a protocol gives several ranges).
%       range = clock time of the start of the range, bin = clock time of the start of the bin, nComments / comments =
%       comments of the log file in the range (this channel or all channels). Contractions ('contractions'): 'all'
%       (every contraction), 'thinned' (every 'thinFactor'-th contraction per channel, 'thinMode','nth', or the median
%       of blocks of 'thinFactor' contractions, 'thinMode','median'; extra beats and, with 'includeProtocols', the
%       contractions in the protocols are always kept) or 'none'; columns bin, sampledEvery (number of contractions per
%       row) and sampleMode ('singleBeat' / 'median'). 'compress', true: <name>_contractions.csv.gz (gzip level 6).
%   overview ('overviewSeconds', 60, default; 0 = none): medians of all contractions per window of 1 min
%       (file time, split at the ranges), channel, beat type, rocker state and inclusion: window (clock time of its
%       start), t_from, t_to, nBeats, beatsPerMinute and the median of every parameter. About 1/30 (0.5 Hz) to 1/60
%       (1 Hz) of the rows of all contractions.
%   protocols (if the log file contains stimulation protocols, 'protocols', true)
%       MyoDishAnalysis(file, [], [], [], 'protocol', 'all', ...): every contraction in the protocols, summary per
%       protocol, channel and group, protocolResults (FFR, ST thresholds, refractory periods, PRP).
%   events ('events', true): all entries of the log file (comments, stimulation and rocker settings,
%       recording, calibration, schedule, warnings) with category, clock time and time in the file
%   gaps ('gaps', true): periods without force signal (mda_signalGaps): chamber taken out ('chamber out'),
%       sensor board group or controller failures (>= 2 channels within 1 s), saturation, channels without a chamber
%       ('no signal'); with clock times and the comments of the log file within 5 min of the start or end. The summary
%       gets the columns noSignal_s (s without signal in the range) and nChamberOut (chambers taken out in the range).
%   channels ('gaps', true): one row per channel: recording, recordingStart, fileLength_s, calibration
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
%   <experiment>/<experiment>_slices.csv and resultsFolder/mda_slices.csv (all experiments): one row per
%   slice (channel of a setup from putting the slice in until it was taken out, the signal was lost or the data end)
%   with start, end, reason of the start, end status, last contraction and amplitude, days in culture, chamber-out
%   periods. A chamber-out period >= 'newSliceHours' (default 2 h), a recording without signal, a comment such as
%   'new slice' or another sliceID label start a new slice.
% TREND IMAGES ('trends', true, default; needs the overview; 2026-10-14) for a quick look every morning
%   <experiment>/<experiment>_overview.png   (2026-10-15) one row per setup (numbered series), one column per channel:
%       amplitude over the whole time course, background = status at the end of the data of the last slice (green
%       beating, red not beating, grey removed, orange signal lost), last 24 h yellow, new slices dashed, texts: last
%       amplitude, change in the last 24 h, % of the maximum of the slice; red frame = recordings with red flags of the
%       analysis report (number; also flags of earlier passes: mda_flags.csv)
%   <series>/<series>_ch<c>.png   (2026-10-15; flat layout: trends/) per setup and channel: left the whole time course
%       since the start of the series (all slices, slice changes dashed, the last 24 h yellow, recordings with red flags
%       as red bars), right the last 24 h (10-min line, protocols, comments numbered with a list); data in
%       <series>/<series>_trends.xlsx (sheets course, last24h, comments, slices; see mda_sliceRegister)
%   <nn>/<name>_ch<c>.png    per recording and channel (with at least 20 included contractions): one panel per
%       parameter of 'trendParameters' (default {'amplitude', 'diastolicForce', 'TTP90', 'TTR90'}; any parameter of
%       mda_parameters or 'beatsPerMinute'), dots = values of the overview (median per minute of the included
%       contractions), line = their median per 10 min (5 min up to 3 h, 30 min beyond 30 h), clock time; stimulation
%       protocols as light blue bands with their name, periods without signal grey, comments of the log file as
%       numbered purple lines with a list below (comments during a protocol only at its start or end); title with the
%       labels of the channel (setupID, sliceID, species, tissue, sampleID, treatment); first / last 2 h and change in %.
%   PNG, 150 dpi, 11 inch wide. The data of the images per recording: sheet trends (channel, window = clock time of
%   its start, t_from (s), nBeats = included contractions, the trend parameters (median per window; units as in the
%   sheet parameters), bin_from (s): line = median of the rows with the same bin_from; up to 8 x 1440 rows per day)
%   and sheet trendComments (channel, number as in the image, t_file, clockTime, text).
%   MyoDishAnalysisWatch('trends', resultsFolder, 'include', p, 'trendParameters', {...}) makes the images and these
%   sheets again from the result files (e.g. other parameters, or results of earlier versions), and the images of the
%   series and experiments of these recordings.
% resultsFolder/mda_flags.csv ('report', true; 2026-10-14)
%   flags of the analysis report per recording and channel (file, analyzed, channel, label, status, nDetected,
%   capture_percent, flags, level, red, yellow, from, to = window to open for the channels to check) of all analysed
%   recordings (also of earlier passes); read by the results browser of the GUI (MyoDishAnalysisWatch('flags',
%   resultsFolder)), the experiment reports and the overview images.
% resultsFolder/mda_index.csv
%   one row per recording: file (path relative to rawFolder), bytes, modified (time of the .mdd file, UTC), logBytes, status (ok / error /
%   running / incomplete / parallel / noLog), version, implementation (MATLAB / Python), code (fingerprint of the core functions), options,
%   analyzed, seconds, nContractions, outputs, message. The same file is used by the MATLAB and the Python watcher.
% resultsFolder/reports/mda_report_<date>_<time>.txt
%   report of a pass with analysed recordings: per channel contractions, capture (% of the stimuli followed by a
%   contraction), extra beats (% of the detected contractions), mean amplitude in the first and last range (>= 10
%   included contractions) and flags (no contractions, capture < flagCapture % (not with arrhythmic pacing, summary
%   column arrhythmicPacing: 'arrhythmic pacing'), extra beats > flagExtraBeats %, amplitude change >
%   flagAmplitudeChange %).
%   It lists the PDF reports of the experiments with analysed recordings.
% resultsFolder/<experiment>/<experiment>_report.pdf ('report', true; 2026-10-11; one report per experiment instead of
%   one per pass since 2026-10-15; mda_report_root.pdf for recordings directly in rawFolder)
%   analysis report of all analysed recordings of the experiment (mda_report), made again after every pass with
%   analysed recordings of the experiment: first page the overview image of the experiment, then the recordings x
%   channels with flags (recordings of the last pass bold, earlier ones with the flags of mda_flags.csv: flags of
%   earlier days stay visible), the list of the channels to check and those with slice-quality flags, and pages with
%   traces of the red channels of the last pass. Flags: the channels whose
%   analysis should be checked (red: inverted signal; noise suspected = uncertain >= flagUncertain % and extra +
%   missed beats >= flagIrregular %; large extra beats; delay pulse -> onset > flagDelay s; stimulus frequency >
%   flagStimFrequency Hz) and those with slice-quality flags (yellow: capture < flagCapture %, extra beats >
%   flagExtraBeats %, amplitude < flagAmplitude uN, amplitude change > flagAmplitudeChange %, amplitude CV >
%   flagAmplitudeCV %; arrhythmic pacing: no capture and amplitude CV flags); channels with fewer than
%   flagMinBeats detected contractions are not flagged. The commands that open the red channels in the GUI
%   (MyoDishAnalysisGUI(<name>.xlsx, 'channel', c, 'window', [a b]); without 'quiet' also as links in the command
%   window).
%
% SKIPPED while written or copied (2026-10-13): files modified less than 'minFileAgeMinutes' ago (default 10), names
%   starting with '.' (rsync temporary files, hidden folders),
%   - status 'running': no 'Recording stopped' entry in the log file yet; analysed when the end of the data (start of
%     the recording in the log file + duration of the file from its size) is 'incompleteAfterHours' (default 30 h)
%     ago, e.g. aborted recordings (without clock time in the log file, or with the clock of the recording computer
%     more than 1 h ahead: 'incompleteAfterHours' after the last change of the files),
%   - status 'incomplete': the file is shorter than the recording in the log file ('Recording started' -> 'stopped')
%     by more than 10 s and more than 'incompleteTolerance' % (default 2 %; relative because the sample clock of the
%     controllers deviates from the clock of the computer by up to about 0.6 %, in one setup by 2 %; 24-h
%     recordings: 99 % within 90 s; the 10 s protect short recordings, whose start and stop entries can be 1-2 s
%     off). Checked again in every pass; analysed (with a note in the message) when unchanged for
%     'incompleteAfterHours' (copies that are never completed). Also 'incomplete', until the file changes: empty files (no data) and files dated before 1990
%     (robocopy dates files to 1980 until their copy is finished),
%   - status 'parallel' ('parallel', 'skip', default): parallel recordings (e.g. schedule files, snapshots) whose main
%     recording is in the same folder of rawFolder (its log file lists the file as 'started parallel recording', with
%     the same duration) and selected in the same pass ('include' / 'exclude' / 'fromDate'): the data are
%     in the main file and its stimulation protocols in the main file's _protocols_* results. The message names the
%     main file and the time window in it. Parallel recordings whose main file is not selected (e.g. 'include',
%     '*schedule*': the schedule files only) or missing, and all of them with 'parallel', 'analyse', are analysed;
%     the message starts with 'parallel recording of <main file> (...)'. The slice register ignores parallel
%     recordings whose main file has results: no contraction or stimulus is counted twice (2026-10-14),
%   - status 'noLog': no log file, or an empty one; analysed when the log file appears or changes.
%   Errors are retried when the file, the version, the options or the code change, or with 'retryErrors'. The index is
%   written after every analysed recording and once at the end of the pass.
%
% LOCK FILE (2026-10-14): resultsFolder/mda_watch.lock exists while a pass runs; a second watcher on the same results
%   folder (MATLAB timer, Python, another computer) skips its pass. It is refreshed after every recording and during
%   long steps; a lock file that was not refreshed for 1 h (watcher crashed) is ignored.
%
% OPTIONS (name/value pairs)
%   'schedule', s            passes on a schedule in the background (see SCHEDULE; default '' = one pass)
%   'reanalyze', m           'new' (default) | 'outdated' | 'all' (see above)
%   'retryErrors', tf        analyse recordings with errors again (default false)
%   'fromDate', d            only files modified on/after this date ('yyyy-mm-dd', 'dd.mm.yyyy', 'yymmdd')
%   'include', p / 'exclude', p   wildcard patterns (char, several separated by ',' or ';', or a cell array; * any
%                            characters, ? one character): only the recordings matching one of the 'include' patterns
%                            and none of the 'exclude' patterns. A pattern without '/' is matched against every
%                            folder name and the file name of the path relative to rawFolder, with '/' against the
%                            whole path: 'ABC00*' = all folders starting with ABC00, '*schedule*' = schedule files
%                            (2026-10-13)
%   'caseSensitive', tf      'include' and 'exclude' (and 'filter') distinguish upper and lower case (default false)
%   'parallel', m            'skip' (default) | 'analyse': parallel recordings whose main file is selected, too
%                            (see SKIPPED)
%   'maxFiles', n            at most n recordings per pass
%   'dryRun', tf             only list what would be analysed
%   'minFileAgeMinutes', m   (default 10)       'incompleteAfterHours', h   (default 30)
%   'incompleteTolerance', p missing part of the recording (% of the log file) that is tolerated (default 2)
%   'binMinutes', m          time bin of the summary (default 60)
%   'includeProtocols', tf   summary and contractions also during the stimulation protocols (default false)
%   'protocolMarginSeconds', s   excluded after the end of a protocol as well (default 0)
%   'protocols', tf          analyse the stimulation protocols of the log file (default true)
%   'contractions', c        'all' (default) | 'thinned' | 'none'
%   'thinFactor', n          (default 10)       'thinMode', m   'nth' (default) | 'median'
%   'resultFormat', f        'xlsx' (default: <name>.xlsx with the tables as sheets, large tables as .csv.gz) | 'csv'
%                            (one file per table; see RESULTS)
%   'folders', f             'series' (default: a folder per setup and recording) | 'flat' (see RESULT FOLDERS)
%   'compress', tf           'csv': <name>_contractions.csv.gz, _pulses.csv.gz (default false)
%   'overviewSeconds', s     overview: medians per window of s seconds (default 60, 0 = none)
%   'trends', tf             trend images per recording and channel, course images per setup and channel, overview
%                            image per experiment (default true; see TREND IMAGES)
%   'trendParameters', c     parameters of the trend images (default {'amplitude', 'diastolicForce', 'TTP90', 'TTR90'})
%   'events', tf             events table and comments in the summary (default true)
%   'gaps', tf               gaps and channels tables, summary columns noSignal_s, nChamberOut (default true)
%   'register', tf           slice register (default true)
%   'newSliceHours', h       slice register: new slice after >= h without signal (default 2)
%   'flagCapture', 'flagExtraBeats', 'flagAmplitudeChange'   report flags (default 90, 10, 30 %)
%   'report', tf             PDF report per experiment and mda_flags.csv (default true)
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
% ADVANCED OPTIONS
%   'filter', rx             regular expression on the path relative to rawFolder (as Python re.search; 'include' /
%                            'exclude' are simpler)
%
% EXAMPLES
%   MyoDishAnalysisWatch('/data/myodish/raw', '/data/myodish/results', 'rockerFilter', true)
%   MyoDishAnalysisWatch(raw, results, 'fromDate', '2026-10-01', 'dryRun', true)
%   MyoDishAnalysisWatch(raw, results, 'schedule', 'daily 10:00')        %every day at 10:00, MATLAB stays free
%   MyoDishAnalysisWatch(raw, results, 'schedule', 'weekly Sun 05:00')   %every Sunday at 05:00
%   MyoDishAnalysisWatch(raw, results, 'schedule', 'every 120 min')      %now and then every 120 min
%   MyoDishAnalysisWatch('status'), MyoDishAnalysisWatch('stop')
%   [T, missing] = MyoDishAnalysisWatch('flags', results, true)   %flags of all recordings (mda_flags.csv; missing:
%                                       computed from the result files), X = MyoDishAnalysisWatch('index', results)
%   M = MyoDishAnalysisWatch('mainRecording', mddFile)   %main recording of a parallel recording (main, a, b) or []
%   MyoDishAnalysisWatch('trends', results, 'include', 'ABC00*', 'trendParameters', {'amplitude', 'beatsPerMinute'})
%                                       %trend images again from the result files (recordings, series, experiments)
%   MyoDishAnalysisWatch('reorganize', results)   %results of earlier versions into the folders of the series
%   d = MyoDishAnalysisWatch('resultFolder', results, 'ABC000101/Setup1_ABC000101_3.mdd')   %folder of its results
%   MyoDishAnalysisWatch(raw, results, 'reanalyze', 'outdated')   %after an update: recordings of another version
%   MyoDishAnalysisWatch(raw, results, 'contractions', 'thinned', 'thinMode', 'median', 'compress', true)
%   MyoDishAnalysisWatch(raw, results, 'include', '*schedule*')   %only the schedule files
%   Daily without an open MATLAB: the scheduler of the operating system with
%   matlab -batch "MyoDishAnalysisWatch('raw', 'results', 'quiet', true)"   or the Python version (mda-watch).
%
% TS 2026-10-08 (watcher settings in the info table 2026-10-09; pulse table 2026-10-10; PDF report 2026-10-11;
% schedule and 'reanalyze','new' 2026-10-12; arrhythmic pacing, flagStimFrequency, include / exclude, completeness
% check, parallel recordings 2026-10-13; results as .xlsx, trend images 2026-10-14; result folders per series, course
% and overview images, PDF report per experiment 2026-10-15)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

if nargin >= 1 && (ischar(rawFolder) || isstring(rawFolder)) && ...
        any(strcmpi(rawFolder, {'stop', 'status', 'nextPass', 'flags', 'index', 'mainRecording', 'trends', ...
        'resultFolder', 'reorganize'})) && ...
        ~isfolder(rawFolder)
    switch lower(char(rawFolder))                  %no output: nothing shown as ans
        case 'flags'                                   %[T, missing] = MyoDishAnalysisWatch('flags', res, compute, fcn)
            a = [varargin, cell(1, 2)];
            [index, report] = flagsTable(char(resultsFolder), ~isempty(a{1}) && logical(a{1}), a{2});
        case 'index'                                   %X = MyoDishAnalysisWatch('index', res)
            index = readIndex(char(resultsFolder)); report = '';
        case 'mainrecording'                           %M = MyoDishAnalysisWatch('mainRecording', mddFile)
            f = char(resultsFolder);
            index = []; report = '';
            D = logRecordings([f(1:end-4) '_log.log'], f);
            if D.parallel, index = mainRecording(f, D, containers.Map(), true); end
        case 'trends'                                  %files = MyoDishAnalysisWatch('trends', res, 'include', p, ...)
            [index, report] = trendsAgain(char(resultsFolder), varargin);
        case 'resultfolder'                            %d = MyoDishAnalysisWatch('resultFolder', res, rel)
            [index, report] = resultsOf(absPath(resultsFolder), strrep(char(varargin{1}), '\', '/'));
        case 'reorganize'                              %n = MyoDishAnalysisWatch('reorganize', res, 'folders', f, ...)
            [index, report] = reorganize(absPath(resultsFolder), varargin);
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
    'include', '', 'exclude', '', 'caseSensitive', false, 'parallel', 'skip', 'incompleteTolerance', 2, ...
    'maxFiles', inf, 'dryRun', false, 'minFileAgeMinutes', 10, 'incompleteAfterHours', 30, 'binMinutes', 60, ...
    'includeProtocols', false, 'protocolMarginSeconds', 0, 'protocols', true, 'contractions', 'all', ...
    'thinFactor', 10, 'thinMode', 'nth', 'compress', false, 'overviewSeconds', 60, 'events', true, 'gaps', true, ...
    'register', true, 'newSliceHours', 2, 'resultFormat', 'xlsx', 'folders', 'series', 'trends', true, ...
    'trendParameters', {{'amplitude', 'diastolicForce', 'TTP90', 'TTR90'}}, ...
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
W.parallel = strrep(lower(char(W.parallel)), 'analyze', 'analyse');
if ~ismember(W.parallel, {'skip', 'analyse'})
    error('MyoDishAnalysisWatch: ''parallel'': ''skip'' or ''analyse'' expected.');
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
W = checkResultOptions(W);
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
if ~isempty(d) && (now - d.datenum) * 24 < lockStaleHours()
    report = sprintf('another watcher is running (lock file %s, refreshed within the last hour): pass skipped', lock);
    if ~W.quiet, fprintf('%s\n', report); end
    X = readIndex(res);
    return;
end
W.lockFile = '';
if ~W.dryRun
    W.lockFile = lock;
    touchLock(lock, true);
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
incP = patternList(W.include); excP = patternList(W.exclude);
sel = false(numel(F), 1);          %recordings selected in this pass (filter, include / exclude, fromDate)
for k = 1:numel(F)
    sel(k) = isSelected(F(k).rel, W, incP, excP) && (isnan(fromDate) || F(k).datenum >= fromDate);
end
chosen = {F(sel).rel};
todo = {};
stale = cell(0, 2);                                    %kept results of another version / other options ('new')
for k = 1:numel(F)
    rel = F(k).rel; f = F(k).file;
    if ~sel(k), continue; end
    touchLock(W.lockFile);                             %heartbeat (at most once a minute)
    logf = [f(1:end-4) '_log.log'];
    dl = dir(logf);
    logBytes = -1; lastChange = F(k).datenum;
    if ~isempty(dl), logBytes = dl.bytes; lastChange = max(lastChange, dl.datenum); end
    if (t - lastChange) * 1440 < W.minFileAgeMinutes, continue; end     %still written / copied
    modified = utcText(F(k).datenum);
    i = find(strcmp(X.file, rel), 1);
    if isempty(i), r = []; else, r = X(i,:); end
    why = reason(r, F(k).bytes, modified, logBytes, version, code, otext, W, chosen);
    if ~isempty(why)
        todo(end+1,:) = {rel, f, logf, F(k).bytes, modified, logBytes, lastChange, why, F(k).datenum, []}; %#ok<AGROW>
    elseif ~isempty(r) && strcmp(r.status{1}, 'ok')
        od = outdatedOf(r, version, code, otext);
        if ~isempty(od), stale(end+1, :) = {od, r.version{1}}; end %#ok<AGROW>
    end
end
% parallel recordings (2026-10-14): skipped ('parallel', 'skip') if their main file is selected in this pass, too (its
% results contain the data); otherwise analysed and marked in the message (slice register: not counted twice)
par = cell(0, 4);
parRows = cell(0, 10);
if ~isempty(todo)
    cache = containers.Map();
    keep = true(size(todo, 1), 1);
    for k = 1:size(todo, 1)
        touchLock(W.lockFile);
        if todo{k,6} <= 0 || todo{k,4} <= 0, continue; end
        try
            D = logRecordings(todo{k,3}, todo{k,2});
            if ~D.parallel, continue; end
            M = mainRecording(todo{k,2}, D, cache);
        catch
            M = [];                                    %analysed as usual
        end
        if isempty(M), continue; end
        m = strrep(M.main(numel(raw)+2:end), filesep, '/');
        todo{k,10} = struct('main', m, 'a', M.a, 'b', M.b); %#ok<AGROW> todo exists (cell of the job)
        if strcmp(W.parallel, 'skip') && ismember(m, chosen)
            keep(k) = false;
            par(end+1, :) = {k, m, M.a, M.b}; %#ok<AGROW>
        end
    end
    parRows = todo(~keep, :);
    todo = todo(keep, :);
end
todo = todo(1:min(size(todo,1), W.maxFiles), :);
notice = updateNotice(stale, version, raw, res);
if ~W.quiet
    nChk = 0;
    if ~isempty(todo), nChk = sum(startsWith(todo(:, 8), 'check')); end
    ps = '';
    if nChk > 0, ps = sprintf(', %d to check again (running / incomplete)', nChk); end
    if ~isempty(par), ps = sprintf('%s, %d parallel recording(s) skipped (main file selected)', ps, size(par, 1)); end
    fprintf('%s  %s: %d recording(s) to analyse%s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), raw, size(todo,1) - nChk, ps);
    for k = 1:numel(notice), fprintf('NOTE: %s\n', notice{k}); end
end
if W.dryRun
    for k = 1:size(todo,1), fprintf('  %s  (%s)\n', todo{k,1}, todo{k,8}); end
    for k = 1:size(par,1), fprintf('  %s  (parallel recording of %s: skipped)\n', parRows{k,1}, par{k,2}); end
    report = strjoin(notice, newline);
    return;
end
for k = 1:size(par, 1)                                 %index rows without analysis
    [rel, ~, ~, nBytes, modified, logBytes] = parRows{k, 1:6};
    row = newRow(rel, nBytes, modified, logBytes, version, code, otext);
    row.status = 'parallel'; row.seconds = 0;
    row.message = sprintf(['parallel recording of %s (%s of the main file): not analysed (parallel=''skip''), ' ...
        'its data and stimulation protocols are in the results of the main file'], par{k,2}, windowText(par{k,3}, par{k,4}));
    if ~W.quiet, fprintf('  %s: parallel: %s\n', rel, row.message); end
    X = setRow(X, row);                                %index written at the end of the pass
end
blocks = {};
done = {};                                             %rows of the analysed recordings (PDF report)
for k = 1:size(todo,1)
    [rel, f, ~, nBytes, modified, logBytes, lastChange, why, mtime, mainOf] = todo{k,:};
    row = newRow(rel, nBytes, modified, logBytes, version, code, otext);
    tic0 = tic;
    block = '';
    [status, note] = precheck(nBytes, mtime, logBytes);
    if ~isempty(status)
        row.status = status; row.message = note;
    else
        try
            H = mda_readMdd(f, [], [], hopts);
            [status, note] = completeness(f, lastChange, H, W, t);
            if ~isempty(status)
                row.status = status; row.message = note;
            else
                if ~W.quiet, fprintf('  %s (%s) ...\n', rel, why); end
                [row, block] = analyse(f, rel, H, res, row, W, args);
                if ~isempty(note)
                    if isempty(row.message), row.message = note; else, row.message = [note ' | ' row.message]; end
                end
            end
        catch ME
            row.status = 'error';
            row.message = clean(sprintf('%s: %s', ME.identifier, ME.message));
        end
    end
    if ~isempty(mainOf) && any(strcmp(row.status, {'ok', 'error'}))   %analysed parallel recording: marked (2026-10-14)
        if strcmp(W.parallel, 'skip'), whyP = 'main file not selected'; else, whyP = 'parallel=''analyse'''; end
        mark = sprintf('parallel recording of %s (%s of the main file): analysed (%s)', mainOf.main, ...
            windowText(mainOf.a, mainOf.b), whyP);
        if isempty(row.message), row.message = mark; else, row.message = [mark ' | ' row.message]; end
    end
    row.seconds = round(toc(tic0) * 10) / 10;
    if any(strcmp(row.status, {'ok', 'error'}))
        if isempty(block), block = sprintf('%s\n  %s: %s\n', rel, row.status, row.message); end
        blocks{end+1} = block; %#ok<AGROW>
        done{end+1} = row; %#ok<AGROW>
    end
    if ~W.quiet && ~strcmp(row.status, 'ok'), fprintf('  %s: %s: %s\n', rel, row.status, row.message); end
    X = setRow(X, row);
    if any(strcmp(row.status, {'ok', 'error'})), writeIndex(res, X); end   %other states: at the end of the pass
    touchLock(W.lockFile);                             %heartbeat after every recording (2026-10-14)
end
if size(todo, 1) > 0 || ~isempty(par)                 %index in the order of the files
    X = sortrows(X, 'file');
    writeIndex(res, X);
end
fl = struct('uncertain', W.flagUncertain, 'irregular', W.flagIrregular, 'extra', W.flagExtraBeats, 'capture', ...
    W.flagCapture, 'amplitudeChange', W.flagAmplitudeChange, 'amplitude', W.flagAmplitude, 'amplitudeCV', ...
    W.flagAmplitudeCV, 'delay', W.flagDelay, 'minBeats', W.flagMinBeats, 'stimFrequency', W.flagStimFrequency);
recs = []; flagMsg = '';
if ~isempty(done) && W.report                        %flags of the analysis report -> mda_flags.csv (2026-10-14), before
    touchLock(W.lockFile);                             %the register (red flags in its images; 2026-10-15)
    [~, o] = sort(cellfun(@(r) r.file, done, 'UniformOutput', false));
    try
        recs = reportRecords(raw, res, done(o), fl);
        updateFlags(res, recordFlags(recs), done);
    catch ME
        recs = [];
        flagMsg = clean(sprintf('flags: %s: %s', ME.identifier, ME.message));
    end
end
reg = '';
exps = {};
if size(todo, 1) > 0                                   %experiments (folders in the raw folder) with analysed recordings
    exps = cell(size(todo, 1), 1);
    for k = 1:size(todo, 1)
        j = find(todo{k,1} == '/', 1, 'last');
        if isempty(j), exps{k} = ''; else, exps{k} = todo{k,1}(1:j-1); end
    end
    exps = unique(exps);
end
if ~isempty(exps) && W.register && W.gaps              %slice register and images of the series of these experiments
    touchLock(W.lockFile);
    try
        R = mda_sliceRegister(res, exps, 'newSliceHours', W.newSliceHours, 'trends', W.trends && ...
            W.overviewSeconds > 0, 'trendParameters', W.trendParameters);
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
    if ~isempty(flagMsg), report = [report newline flagMsg newline]; end
    dr = fullfile(res, 'reports');
    if ~isfolder(dr), mkdir(dr); end
    links = {};
    if W.report && ~isempty(recs)                      %PDF report per experiment (2026-10-15)
        ln = {};
        for k = 1:numel(exps)
            touchLock(W.lockFile);
            in = arrayfun(@(r) strcmp(folderOf(r.name), exps{k}), recs);
            if ~any(in), continue; end
            try
                [pdf, n, lk] = experimentReport(raw, res, exps{k}, recs(in), fl, version, otext, now_, notice);
                if isempty(pdf), continue; end
                ln{end+1} = sprintf('PDF report: %s%s', pdf, repmat(sprintf(' (%d channel(s) to check)', n), 1, ...
                    n > 0)); %#ok<AGROW>
                links = [links; lk]; %#ok<AGROW>
            catch ME
                ln{end+1} = clean(sprintf('PDF report %s: %s: %s', exps{k}, ME.identifier, ME.message)); %#ok<AGROW>
            end
        end
        if ~isempty(ln), report = [report newline strjoin(ln, newline) newline]; end
    end
    fid = fopen(fullfile(dr, ['mda_report_' datestr(now_, 'yyyy-mm-dd_HHMMSS') '.txt']), 'w', 'n', 'UTF-8');
    fwrite(fid, unicode2native(report, 'UTF-8'));
    fclose(fid);
    if ~W.quiet
        fprintf('\n%s\n', report);
        for j = 1:size(links, 1)                       %channels to check: links that open them in the GUI
            if feature('hotlinks')
                fprintf('  <a href="matlab:%s">%s</a>: %s\n', links{j, 1}, links{j, 2}, links{j, 3});
            else
                fprintf('  %s\n', links{j, 1});
            end
        end
    end
elseif ~isempty(notice)
    report = strjoin(notice, newline);
end
nDone = numel(done);
end


function recs = reportRecords(raw, res, rows, fl)
% recordings of this pass for the reports (2026-10-15): flags R per channel (mda_report 'flags', with the window of
% the channels to check), contractions C only for recordings with channels to check (detail pages; memory of passes
% with thousands of recordings), pulses read later (P_file)
ccols = {'channel', 't_peak', 'beatType', 'uncertain', 'included', 'amplitude', 'stimToOnset'};
recs = repmat(reportRecord(), 0, 1);
for i = 1:numel(rows)
    row = rows{i};
    rel = strrep(row.file, '\', '/');
    [~, n] = fileparts(rel);
    d = resultsOf(res, rel);
    rec = reportRecord();
    rec.name = rel; rec.file = fullfile(raw, rel); rec.open = fullfile(d, [n '_info.csv']); rec.new = true;
    rec.analyzed = row.analyzed;
    if ~strcmp(row.status, 'ok')
        rec.notes = {clean(['error: ' row.message])};
        recs(end+1) = rec; %#ok<AGROW>
        continue;
    end
    rec.S = resultTable(d, n, 'summary', {});
    C = readResult(fullfile(d, [n '_contractions.csv']), ccols);
    rec.status = resultTable(d, n, 'channels', {'channel', 'status'});
    if isfile(fullfile(d, [n '.xlsx'])), rec.open = fullfile(d, [n '.xlsx']); end   %results as .xlsx (2026-10-14)
    m = strtrim(strsplit(row.message, ' | '));
    rec.notes = m(startsWith(m, 'protocols:'));
    E = resultTable(d, n, 'events', {'code', 'text', 't_file'});   %red flag R: controller restart suspected (2026-10-21)
    R = mda_report('flags', rec.S, C, rec.status, fl, E);
    R.window_from = nan(height(R), 1); R.window_to = nan(height(R), 1);
    for j = find(strcmp(R.level, 'check'))'
        [R.window_from(j), R.window_to(j)] = mda_report('window', C, R.channel(j), R.flags{j}, 20);
    end
    rec.R = R;
    if any(strcmp(R.level, 'check')), rec.C = C; end
    rec.P_file = fullfile(d, [n '_pulses.csv']);
    recs(end+1) = rec; %#ok<AGROW>
end
end


function rec = reportRecord()
rec = struct('name', '', 'file', '', 'open', '', 'S', [], 'C', [], 'P', [], 'P_file', '', 'R', [], 'status', [], ...
    'notes', {{}}, 'new', false, 'analyzed', '');
end


function R = recordFlags(recs)
% flags of the recordings (column recording) for mda_flags.csv
parts = {};
for i = 1:numel(recs)
    if isempty(recs(i).R) || height(recs(i).R) == 0, continue; end
    parts{end+1} = addvars(recs(i).R, repmat({recs(i).name}, height(recs(i).R), 1), 'Before', 1, ...
        'NewVariableNames', 'recording'); %#ok<AGROW>
end
if isempty(parts), R = []; else, R = vertcat(parts{:}); end
end


function e = folderOf(rel)
j = find(rel == '/', 1, 'last');
if isempty(j), e = ''; else, e = rel(1:j-1); end
end


function [pdf, nCheck, links] = experimentReport(raw, res, e, recsNew, fl, version, otext, now_, notice)
% PDF report of an experiment (2026-10-15): <experiment>/<name>_report.pdf (mda_report_root.pdf for recordings directly
% in the raw folder) with all analysed recordings of the experiment (index), the recordings of this pass (recsNew)
% marked new (bold) with detail pages; the others with the flags of mda_flags.csv (computed from their result files
% where missing); first page: the overview image of the experiment (slice register). nCheck: channels to check in the
% recordings of this pass; links: {MATLAB command, recording ch c, red flags} of these channels
nCheck = 0; links = cell(0, 3);
if isempty(e)
    pdf = fullfile(res, 'mda_report_root.pdf'); png = fullfile(res, 'mda_overview_root.png'); en = 'recordings in the raw folder';
else
    p = strsplit(e, '/');
    pdf = fullfile(res, p{:}, [p{end} '_report.pdf']); png = fullfile(res, p{:}, [p{end} '_overview.png']); en = e;
end
X = readIndex(res);
X = X(ismember(X.status, {'ok', 'error'}) & strcmp(cellfun(@folderOf, strrep(X.file, '\', '/'), ...
    'UniformOutput', false), e), :);
F = readFlags(res);
newNames = {recsNew.name};
recs = repmat(reportRecord(), 0, 1);
add = emptyFlags();
for i = 1:height(X)
    rel = strrep(X.file{i}, '\', '/');
    j = find(strcmp(newNames, rel), 1);
    if ~isempty(j), recs(end+1) = recsNew(j); continue; end %#ok<AGROW>
    rec = reportRecord();
    rec.name = rel; rec.file = fullfile(raw, rel); rec.analyzed = X.analyzed{i};
    if ~strcmp(X.status{i}, 'ok')
        rec.notes = {clean(['error: ' X.message{i}])};
        recs(end+1) = rec; %#ok<AGROW>
        continue;
    end
    [d, ~] = resultsOf(res, rel);
    [~, n] = fileparts(rel);
    rec.open = fullfile(d, [n '_info.csv']);
    if isfile(fullfile(d, [n '.xlsx'])), rec.open = fullfile(d, [n '.xlsx']); end
    Fr = F(strcmp(F.file, X.file{i}) & strcmp(F.analyzed, X.analyzed{i}), :);
    if height(Fr) == 0                                 %flags missing (older watcher versions): from the result files
        try
            Fr = flagsOf(res, X.file{i}, X.analyzed{i});
            add = [add; Fr]; %#ok<AGROW>
        catch
        end
    end
    rec.R = table(Fr.channel, Fr.label, Fr.status, Fr.nDetected, Fr.capture_percent, Fr.flags, Fr.level, Fr.red, ...
        Fr.yellow, Fr.from, Fr.to, 'VariableNames', {'channel', 'label', 'status', 'nDetected', 'capture_percent', ...
        'flags', 'level', 'red', 'yellow', 'window_from', 'window_to'});
    m = strtrim(strsplit(X.message{i}, ' | '));
    rec.notes = m(startsWith(m, 'protocols:'));
    recs(end+1) = rec; %#ok<AGROW>
end
if height(add) > 0, writeFlags(res, [F(~ismember(F.file, add.file), :); add]); end
if isempty(recs), pdf = ''; return; end
% order: series, number, name
key = cell(numel(recs), 3);
for i = 1:numel(recs)
    [~, n] = fileparts(recs(i).name);
    [sr, nr] = mda_sliceRegister('series', n);
    if isnan(nr), nr = inf; end
    key(i, :) = {sr, nr, n};
end
[~, o] = sortrows(cell2table(key, 'VariableNames', {'s', 'n', 'name'}), {'s', 'n', 'name'});
recs = recs(o);
nNew = sum([recs.new]);
sub = {['raw folder: ' raw], ['results: ' res], sprintf(['MyoDishAnalysis %s (MATLAB) watcher, %s: %d recording(s) ' ...
    'of %s, %d analysed in this pass (bold); options: %s'], version, datestr(now_, 'yyyy-mm-dd HH:MM:SS'), ...
    numel(recs), en, nNew, otext)};
img = ''; if isfile(png), img = png; end
R = mda_report(rmfield(recs, 'analyzed'), pdf, 'title', ['MyoDishAnalysis report: ' en], 'subtitle', sub, ...
    'flags', fl, 'notice', notice, 'image', img);
isNewRow = ismember(R.recording, newNames);
for j = find(strcmp(R.level, 'check') & isNewRow)'
    nCheck = nCheck + 1;
    links(end+1, :) = {R.matlab{j}, sprintf('%s ch %d', R.recording{j}, R.channel(j)), R.red{j}}; %#ok<AGROW>
end
end


function T = resultTable(d, n, tab, cols)
% table tab of the results of recording n in folder d: sheet of <n>.xlsx (resultFormat 'xlsx', 2026-10-14) or
% <n>_<tab>.csv(.gz) ([] if neither exists); cols: only these columns ({} = all); text columns as char
x = fullfile(d, [n '.xlsx']);
if isfile(x)
    try
        if ismember(tab, sheetnames(x))
            o = detectImportOptions(x, 'Sheet', tab, 'VariableNamingRule', 'preserve');
            o.VariableNamesRange = 'A1'; o.DataRange = 'A2';
            if ~isempty(cols), o.SelectedVariableNames = intersect(cols, o.VariableNames, 'stable'); end
            for k = 1:numel(o.SelectedVariableNames)
                j = strcmp(o.VariableNames, o.SelectedVariableNames{k});
                if any(strcmp(o.VariableTypes{j}, {'string', 'datetime', 'categorical'}))
                    o = setvartype(o, o.SelectedVariableNames{k}, 'char');
                end
            end
            T = readtable(x, o);
            return;
        end
    catch
    end
end
T = readResult(fullfile(d, [n '_' tab '.csv']), cols);
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


function why = reason(r, nBytes, modified, logBytes, version, code, otext, W, present)
% reason to analyse the recording ('' = nothing to do)
why = '';
if isempty(r), why = 'new'; return; end
old = parseTime(r.modified{1});
if r.bytes ~= nBytes || r.logBytes ~= logBytes || isnan(old) || abs(old - parseTime(modified)) * 86400 > 2
    why = 'changed'; return;
end
status = r.status{1};
if any(strcmp(status, {'running', 'incomplete'})), why = ['check ' status]; return; end   %'noLog': when the log appears
if strcmp(status, 'parallel')                          %main file named in the message (2026-10-13)
    if ~strcmp(W.parallel, 'skip'), why = 'parallel=''analyse'''; return; end
    m = regexpi(r.message{1}, '^parallel recording of (.+?\.mdd) \(', 'tokens', 'once');
    if isempty(m) || ~any(strcmp(present, m{1})), why = 'check parallel (main file not selected)'; end
    return;
end
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
outDir = absFolder(res, mda_sliceRegister('resultFolder', rel, W.folders));   %series layout (2026-10-15) or flat
other = 'series'; if strcmp(W.folders, 'series'), other = 'flat'; end
oldDir = absFolder(res, mda_sliceRegister('resultFolder', rel, other));
if ~strcmp(oldDir, outDir) && isfolder(oldDir)       %results of the other layout (earlier passes)
    deleteResults(oldDir, n, strcmp(oldDir, fileparts(f)));
    removeEmptyFolders(oldDir, res);
end
if ~isfolder(outDir), mkdir(outDir); end
meta = [f(1:end-4) '_labels.csv'];
if ~isfile(meta), meta = []; end
xls = strcmp(W.resultFormat, 'xlsx');
msgs = {}; outputs = {};
P = [];
if W.protocols || ~W.includeProtocols || W.trends
    try
        P = mda_protocols(H);
    catch ME
        msgs{end+1} = sprintf('protocols: %s: %s', ME.identifier, ME.message);
    end
end
Wp = protocolWindows(P, W.protocolMarginSeconds);
if W.includeProtocols, Wcut = []; else, Wcut = Wp; end
[fr, to, labels, binLabels] = ranges(H, W.binMinutes * 60, Wcut);
deleteResults(outDir, n, strcmp(outDir, fileparts(f)));           %results of earlier options or the other format
E = [];                                             %entries of the log file (also for the trend images)
if W.events || W.trends
    E = mda_logEntries(H.logFile);
    E = addvars(E, cellfun(@eventCategory, E.code, E.text, 'UniformOutput', false), 'After', 'code', ...
        'NewVariableNames', 'category');
    E.clockTime.Format = 'yyyy-MM-dd HH:mm:ss.SSS';
end
Ev = []; if W.events, Ev = E; end                  %events table and comments in the results ('events')
G = []; Gw = [];
if W.gaps
    try
        G = mda_signalGaps(H);
        Gw = gapsOut(G, H, Ev);
    catch ME
        G = [];
        msgs{end+1} = sprintf('gaps: %s: %s', ME.identifier, ME.message);
    end
end
S = []; C = []; info = []; Ov = [];
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
    S = addComments(S, Ev);
    if W.gaps, S = addGaps(S, G); end
    Call = C;
    if W.overviewSeconds > 0 && nC > 0, Ov = overview(C, labels, fr, to, H, W.overviewSeconds); end
    if W.includeProtocols, Wkeep = Wp; else, Wkeep = []; end
    C = sampleContractions(C, labels, Wkeep, W);
    msgs = [info.notes(:)', msgs];
else
    msgs{end+1} = 'no time outside the stimulation protocols';
    Call = [];
end
CH = [];
if W.gaps && istable(G)
    if isempty(to), tEnd = nan; else, tEnd = max(to); end
    CH = channelStatus(H, Call, G, Ev, n, mda_labels(meta, H.dataChannels), tEnd);
end
TR = []; Ttr = []; Tcm = [];                       %trend data per channel (2026-10-14)
if W.trends && istable(Ov)
    try
        TR = recordingTrends(n, H, Ov, E, P, G, mda_labels(meta, H.dataChannels), W);
        [Ttr, Tcm] = trendTables(TR, H.recordingStart);
    catch ME
        TR = []; Ttr = []; Tcm = [];
        msgs{end+1} = sprintf('trends: %s: %s', ME.identifier, ME.message);
    end
end
% result files: 'xlsx' (2026-10-14): <name>.xlsx (summary, trends, channels, gaps, events, parameters, info, ...;
% sheets of Excel) and the large tables as <name>_contractions.csv.gz, _pulses.csv.gz, _overview.csv.gz; 'csv': one
% file per table
if xls
    sheets = {'trends', Ttr; 'trendComments', Tcm; 'channels', CH; 'gaps', Gw; 'events', Ev};
    sheets = sheets(cellfun(@istable, sheets(:, 2)), :);
    if ~isempty(S)
        if strcmp(W.contractions, 'none'), Cw = []; info.pulses = []; else, Cw = C; end
        out = mda_writeResults(fullfile(outDir, [n '.xlsx']), Cw, S, info, 'csvTables', {'contractions', 'pulses'}, ...
            'compress', true, 'sheets', sheets);
        outputs = [outputs, fileNames(out)];
    elseif ~isempty(sheets)
        for k = 1:size(sheets, 1), writetable(sheets{k, 2}, fullfile(outDir, [n '.xlsx']), 'Sheet', sheets{k, 1}); end
        outputs{end+1} = [n '.xlsx'];
    end
    if istable(Ov)
        writeGz(Ov, fullfile(outDir, [n '_overview.csv']));
        outputs{end+1} = [n '_overview.csv.gz'];
    end
else
    if istable(Ev), writetable(Ev, fullfile(outDir, [n '_events.csv'])); outputs{end+1} = [n '_events.csv']; end
    if istable(Gw), writetable(Gw, fullfile(outDir, [n '_gaps.csv'])); outputs{end+1} = [n '_gaps.csv']; end
    if ~isempty(S)
        if strcmp(W.contractions, 'none'), Cw = []; info.pulses = []; else, Cw = C; end
        mda_writeResults(fullfile(outDir, [n '.csv']), Cw, S, info, 'csvTables', {'contractions', 'pulses'}, ...
            'compress', W.compress);
        outputs = [{[n '.csv']}, outputs];
    end
    if istable(Ov)
        writetable(Ov, fullfile(outDir, [n '_overview.csv']));
        outputs{end+1} = [n '_overview.csv'];
    end
    if istable(CH), writetable(CH, fullfile(outDir, [n '_channels.csv'])); outputs{end+1} = [n '_channels.csv']; end
    if istable(Ttr)
        writetable(Ttr, fullfile(outDir, [n '_trends.csv'])); writetable(Tcm, fullfile(outDir, [n '_trendComments.csv']));
        outputs = [outputs, {[n '_trends.csv'], [n '_trendComments.csv']}];
    end
end
if W.protocols && istable(P) && height(P) > 0
    try
        if xls                                      %<name>_protocols.xlsx, contractions and pulses as .csv.gz
            [Cp, Sp, pinfo] = MyoDishAnalysis(f, [], [], [], 'protocol', 'all', 'metadata', meta, 'quiet', true, ...
                'report', false, args{:});
            out = mda_writeResults(fullfile(outDir, [n '_protocols.xlsx']), Cp, Sp, pinfo, 'csvTables', ...
                {'contractions', 'pulses'}, 'compress', true);
            outputs = [outputs, fileNames(out)];
        else
            [~, ~, pinfo] = MyoDishAnalysis(f, [], [], [], 'protocol', 'all', 'metadata', meta, 'quiet', true, ...
                'output', fullfile(outDir, [n '_protocols.csv']), 'report', false, args{:});
            outputs{end+1} = [n '_protocols.csv'];
            if W.compress                           %protocol contractions and pulses as well (2026-10-11)
                for cf = {fullfile(outDir, [n '_protocols_contractions.csv']), fullfile(outDir, [n '_protocols_pulses.csv'])}
                    if isfile(cf{1}), gzip(cf{1}); delete(cf{1}); end
                end
            end
        end
        nt = pinfo.notes(contains(pinfo.notes, 'not analysed'));      %single protocols (2026-10-11)
        if ~isempty(nt), msgs = [msgs, strcat('protocols: ', nt(:)')]; end
    catch ME
        msgs{end+1} = sprintf('protocols: %s: %s', ME.identifier, ME.message);
    end
end
if ~isempty(TR)                                     %trend images per channel (2026-10-14)
    try
        tf = trendImages(imageFolder(outDir, W.folders), n, TR);
        if ~isempty(tf)
            if strcmp(W.folders, 'flat'), outputs{end+1} = sprintf('trends/%s_ch*.png (%d)', n, numel(tf));
            else, outputs{end+1} = sprintf('%s_ch*.png (%d)', n, numel(tf)); end
        end
    catch ME
        msgs{end+1} = sprintf('trends: %s: %s', ME.identifier, ME.message);
    end
end
row.status = 'ok';
row.nContractions = nC;
row.outputs = strjoin(outputs, '; ');
row.message = clean(strjoin(msgs, ' | '));
block = reportBlock(rel, H, S, W, CH, G);
end


function [files, report] = trendsAgain(res, a)
% trend images of analysed recordings again from their result files (overview, events, protocols, gaps, labels,
% channels) and of the slices of their experiments ('include' / 'exclude' / 'caseSensitive' select the recordings of
% the index; 'trendParameters'; 'quiet')
W = struct('include', '', 'exclude', '', 'caseSensitive', false, 'trendParameters', ...
    {{'amplitude', 'diastolicForce', 'TTP90', 'TTR90'}}, 'quiet', false, 'newSliceHours', 2, 'resultFormat', 'xlsx', ...
    'trends', true, 'overviewSeconds', 60);
wn = fieldnames(W);
for i = 1:2:numel(a)
    k = find(strcmpi(wn, char(a{i})), 1);
    if isempty(k) || i == numel(a), error('MyoDishAnalysisWatch(''trends''): unknown option %s.', char(a{i})); end
    W.(wn{k}) = a{i+1};
end
W = checkResultOptions(W);
X = readIndex(res);
X = X(strcmp(X.status, 'ok'), :);
inc = patternList(W.include); exc = patternList(W.exclude);
files = {};
exps = {};
nRec = 0;
for i = 1:height(X)
    rel = strrep(X.file{i}, '\', '/');
    if (~isempty(inc) && ~wildcardMatch(rel, inc, W.caseSensitive)) || (~isempty(exc) && wildcardMatch(rel, exc, W.caseSensitive))
        continue;
    end
    nRec = nRec + 1;
    [dr, n] = fileparts(rel);
    [d, layout] = resultsOf(res, rel);
    exps{end+1} = dr; %#ok<AGROW>
    Ov = readResult(fullfile(d, [n '_overview.csv']), {});
    if ~istable(Ov) || height(Ov) == 0, continue; end
    E = resultTable(d, n, 'events', {});
    P = resultTable(d, [n '_protocols'], 'protocols', {});
    G = resultTable(d, n, 'gaps', {});
    L = resultTable(d, n, 'labels', {});
    CH = resultTable(d, n, 'channels', {'recordingStart', 'fileLength_s'});
    H = struct('recordingStart', NaN, 'totalSeconds', max(Ov.t_to));
    if istable(CH) && height(CH) > 0
        st = strtrim(char(string(CH.recordingStart(1))));
        try
            if ~isempty(st) && ~strcmp(st, '<missing>'), H.recordingStart = datenum(st, 'yyyy-mm-dd HH:MM:SS'); end
        catch
        end
        if isfinite(CH.fileLength_s(1)), H.totalSeconds = CH.fileLength_s(1); end
    end
    deleteResultsTrends(d, n);
    f = {};
    try
        TR = recordingTrends(n, H, Ov, E, P, G, L, W);
        [Ttr, Tcm] = trendTables(TR, H.recordingStart);
        writeTrendTables(d, n, Ttr, Tcm);
        f = trendImages(imageFolder(d, layout), n, TR);
        files = [files, f]; %#ok<AGROW>
    catch ME
        if ~W.quiet, fprintf('  %s: trends: %s\n', rel, ME.message); end
    end
    if ~W.quiet, fprintf('  %s: %d trend image(s)\n', rel, numel(f)); end
end
exps = unique(exps);
report = sprintf('%d trend image(s) of %d recording(s)', numel(files), nRec);
if ~isempty(exps)
    R = mda_sliceRegister(res, exps, 'newSliceHours', W.newSliceHours, 'trends', true, 'trendParameters', ...
        W.trendParameters);
    report = sprintf('%s; slice register: %d slices in %d experiment(s), images of the series and experiments', ...
        report, height(R), numel(exps));
end
if ~W.quiet, fprintf('%s\n', report); end
end


function [nMoved, report] = reorganize(res, a)
% result files of the analysed recordings (mda_index.csv) moved into the layout 'folders' ('series', default, or
% 'flat'; 2026-10-15), then the slice register, the images of the series and experiments and the experiment reports
% (PDF, flags of mda_flags.csv) made again for the experiments with moved results
W = struct('folders', 'series', 'quiet', false, 'newSliceHours', 2, 'resultFormat', 'xlsx', 'trends', true, ...
    'trendParameters', {{'amplitude', 'diastolicForce', 'TTP90', 'TTR90'}}, 'report', true, 'register', true);
wn = fieldnames(W);
for i = 1:2:numel(a)
    k = find(strcmpi(wn, char(a{i})), 1);
    if isempty(k) || i == numel(a), error('MyoDishAnalysisWatch(''reorganize''): unknown option %s.', char(a{i})); end
    W.(wn{k}) = a{i+1};
end
W = checkResultOptions(W);
other = 'series'; if strcmp(W.folders, 'series'), other = 'flat'; end
lock = fullfile(res, 'mda_watch.lock');
d = dir(lock);
if ~isempty(d) && (now - d.datenum) * 24 < lockStaleHours()
    error('MyoDishAnalysisWatch(''reorganize''): a watcher is running on %s (lock file).', res);
end
X = readIndex(res);
nMoved = 0; exps = {};
for i = 1:height(X)
    rel = strrep(X.file{i}, '\', '/');
    [~, n] = fileparts(rel);
    to = absFolder(res, mda_sliceRegister('resultFolder', rel, W.folders));
    from = absFolder(res, mda_sliceRegister('resultFolder', rel, other));
    if strcmp(from, to) || ~isfolder(from), continue; end
    [src, dst] = resultFiles(from, n, strcmp(other, 'flat'), strcmp(W.folders, 'flat'));
    if isempty(src), continue; end
    for k = 1:numel(src)
        t = fullfile(to, dst{k});
        if ~isfolder(fileparts(t)), mkdir(fileparts(t)); end
        movefile(fullfile(from, src{k}), t, 'f');
    end
    removeEmptyFolders(fullfile(from, 'trends'), res);
    removeEmptyFolders(from, res);
    nMoved = nMoved + 1;
    exps{end+1} = folderOf(rel); %#ok<AGROW>
    if ~W.quiet, fprintf('  %s: %d file(s) -> %s\n', rel, numel(src), to); end
end
exps = unique(exps);
report = sprintf('results of %d recording(s) moved to the layout ''%s''', nMoved, W.folders);
if ~isempty(exps) && W.register
    R = mda_sliceRegister(res, exps, 'newSliceHours', W.newSliceHours, 'trends', true, 'trendParameters', ...
        W.trendParameters);
    report = sprintf('%s; slice register: %d slices in %d experiment(s), images of the series and experiments', ...
        report, height(R), numel(exps));
end
if ~isempty(exps) && W.report
    for k = 1:numel(exps)
        try
            experimentReport('', res, exps{k}, repmat(reportRecord(), 0, 1), mda_report('defaults'), mda_version(), ...
                '', now, {});
        catch ME
            report = sprintf('%s; PDF report %s: %s', report, exps{k}, ME.message);
        end
    end
    report = sprintf('%s; PDF reports of %d experiment(s)', report, numel(exps));
end
if ~W.quiet, fprintf('%s\n', report); end
end


function [src, dst] = resultFiles(d, n, fromFlat, toFlat)
% result files of recording n in folder d (names relative to d) and their names in the other layout (trend images:
% trends/<n>_ch<c>.png in the flat layout, <n>_ch<c>.png in the series layout); not <n>_labels.csv next to the
% recording (results folder = raw folder)
names = {[n '.xlsx'], [n '_protocols.xlsx']};
t = {'summary', 'contractions', 'pulses', 'parameters', 'info', 'thresholds', 'labels', 'rockerFilter', 'overview', ...
    'events', 'gaps', 'channels', 'protocols', 'protocolResults', 'trends', 'trendComments'};
beside = isfile(fullfile(d, [n '.mdd']));
for k = 1:numel(t)
    for pre = {'', 'protocols_'}
        if strcmp(t{k}, 'labels') && isempty(pre{1}) && beside, continue; end
        names = [names, {[n '_' pre{1} t{k} '.csv'], [n '_' pre{1} t{k} '.csv.gz']}]; %#ok<AGROW>
    end
end
src = names(cellfun(@(x) isfile(fullfile(d, x)), names));
dst = src;
if fromFlat, img = fullfile(d, 'trends'); else, img = d; end
D = dir(fullfile(img, [n '_ch*.png']));
for k = 1:numel(D)
    if isempty(regexp(D(k).name, ['^' regexptranslate('escape', n) '_ch\d+\.png$'], 'once')), continue; end
    if fromFlat, src{end+1} = ['trends/' D(k).name]; else, src{end+1} = D(k).name; end %#ok<AGROW>
    if toFlat, dst{end+1} = ['trends/' D(k).name]; else, dst{end+1} = D(k).name; end %#ok<AGROW>
end
end


function writeTrendTables(d, n, Ttr, Tcm)
% sheets trends / trendComments of <n>.xlsx (or <n>_trends.csv, _trendComments.csv for csv results) replaced
x = fullfile(d, [n '.xlsx']);
if isfile(x)
    sh = sheetnames(x);
    if ~istable(Ttr), return; end
    for t = {'trends', Ttr; 'trendComments', Tcm}'
        if ismember(t{1}, sh)
            writetable(t{2}, x, 'Sheet', t{1}, 'WriteMode', 'overwritesheet');
        else
            writetable(t{2}, x, 'Sheet', t{1});
        end
    end
elseif istable(Ttr)
    writetable(Ttr, fullfile(d, [n '_trends.csv']));
    writetable(Tcm, fullfile(d, [n '_trendComments.csv']));
end
end


function deleteResultsTrends(d, n)
% trend images of recording n (<d>/<n>_ch<c>.png in the series layout, <d>/trends/<n>_ch<c>.png in the flat layout)
for td = {d, fullfile(d, 'trends')}
    if ~isfolder(td{1}), continue; end
    D = dir(fullfile(td{1}, [n '_ch*.png']));
    for k = 1:numel(D)
        if ~isempty(regexp(D(k).name, ['^' regexptranslate('escape', n) '_ch\d+\.png$'], 'once'))
            delete(fullfile(td{1}, D(k).name));
        end
    end
end
td = fullfile(d, 'trends');
if isfolder(td)
    D = dir(td);
    if all(ismember({D.name}, {'.', '..'})), rmdir(td); end
end
end


function d = imageFolder(outDir, folders)
% folder of the trend images of a recording: its results folder (series layout) or <folder>/trends (flat)
if strcmp(folders, 'flat'), d = fullfile(outDir, 'trends'); else, d = outDir; end
end


function d = absFolder(res, rel)
% absolute folder of a folder relative to the results folder ('/' separated, '' = res)
if isempty(rel), d = res; else, p = strsplit(rel, '/'); d = fullfile(res, p{:}); end
end


function removeEmptyFolders(d, res)
% d and its parents up to res (exclusive) deleted while they are empty (results moved to the other layout)
while numel(d) > numel(res) && isfolder(d)
    D = dir(d);
    if ~all(ismember({D.name}, {'.', '..'})), return; end
    rmdir(d);
    d = fileparts(d);
end
end


function [d, layout] = resultsOf(res, rel)
% folder with the results of the recording rel (path relative to the raw folder): series layout (2026-10-15) or flat
% layout (earlier results); the series layout if neither has results
n = regexprep(rel, '^.*/', ''); n = regexprep(n, '\.mdd$', '', 'ignorecase');
layout = 'series';
d = absFolder(res, mda_sliceRegister('resultFolder', rel, 'series'));
if hasResults(d, n), return; end
f = absFolder(res, mda_sliceRegister('resultFolder', rel, 'flat'));
if hasResults(f, n), d = f; layout = 'flat'; end
end


function tf = hasResults(d, n)
tf = false;
if ~isfolder(d), return; end
for x = {'.xlsx', '_info.csv', '_summary.csv', '_channels.csv', '_overview.csv', '_overview.csv.gz', ...
        '_protocols.xlsx', '_protocols_info.csv'}
    if isfile(fullfile(d, [n x{1}])), tf = true; return; end
end
end


function W = checkResultOptions(W)
% 'resultFormat', 'trends', 'trendParameters' (2026-10-14), 'folders' (2026-10-15)
W.resultFormat = lower(char(W.resultFormat));
if ~ismember(W.resultFormat, {'xlsx', 'csv'})
    error('MyoDishAnalysisWatch: ''resultFormat'': ''xlsx'' or ''csv'' expected.');
end
if isfield(W, 'folders')
    W.folders = lower(char(W.folders));
    if ~ismember(W.folders, {'series', 'flat'})
        error('MyoDishAnalysisWatch: ''folders'': ''series'' or ''flat'' expected.');
    end
end
W.trends = logical(W.trends);
W.trendParameters = cellstr(W.trendParameters);
PI = mda_parameters();
bad = setdiff(W.trendParameters, [PI(:, 1); {'beatsPerMinute'}]);
if ~isempty(bad) || isempty(W.trendParameters)
    error('MyoDishAnalysisWatch: ''trendParameters'': parameters of mda_parameters or beatsPerMinute expected (%s).', ...
        strjoin(bad, ', '));
end
end


function names = fileNames(files)
names = cell(1, numel(files));
for k = 1:numel(files), [~, a, b] = fileparts(files{k}); names{k} = [a b]; end
end


function writeGz(T, f)
% table as <f>.gz
writetable(T, f);
gzip(f);
delete(f);
end


function deleteResults(outDir, n, besideRecording)
% result files of a recording written by earlier passes (other options, the other format); not the labels file
% <name>_labels.csv if the results are written next to the recording
deleteFile(fullfile(outDir, [n '.xlsx']));
deleteFile(fullfile(outDir, [n '_protocols.xlsx']));
t = {'summary', 'contractions', 'pulses', 'parameters', 'info', 'thresholds', 'labels', 'rockerFilter', 'overview', ...
    'events', 'gaps', 'channels', 'protocols', 'protocolResults', 'trends', 'trendComments'};
for k = 1:numel(t)
    for pre = {'', 'protocols_'}
        if strcmp(t{k}, 'labels') && isempty(pre{1}) && besideRecording, continue; end
        deleteFile(fullfile(outDir, [n '_' pre{1} t{k} '.csv']));
        deleteFile(fullfile(outDir, [n '_' pre{1} t{k} '.csv.gz']));
    end
end
deleteResultsTrends(outDir, n);
end


% ===================================================================================================== trend images
function TR = recordingTrends(n, H, Ov, E, P, G, L, W)
% trend data of the channels of one recording (struct array channel, D for mda_report 'trend' / 'trendData'): every
% channel with at least 20 included contractions; values of the overview (W.overviewSeconds)
TR = struct('channel', {}, 'D', {});
if ~istable(Ov) || height(Ov) == 0, return; end
pn = cellstr(W.trendParameters);
[V, un] = trendValues(Ov, pn);
com = trendComments(E);
for c = unique(Ov.channel(:))'
    r = Ov.channel == c;
    inc = logical(Ov.included(r));
    if sum(Ov.nBeats(r & logical(Ov.included))) < 20, continue; end
    B = zeros(0, 3); bl = {};
    if istable(P) && height(P) > 0
        B = [P.from(:), P.to(:), ones(height(P), 1)];
        bl = cellstr(string(P.name));
    end
    if istable(G) && height(G) > 0
        g = G.channel == c;
        B = [B; G.from(g), G.to(g), 2 * ones(nnz(g), 1)]; %#ok<AGROW>
    end
    cc = com([com.channel] == 0 | [com.channel] == c);
    nIn = sum(Ov.nBeats(r & logical(Ov.included)));
    D = struct('title', sprintf('%s  %s  channel %d%s', n, char(183), c, labelText(L, c)), ...
        'subtitle', {trendSubtitle(H.recordingStart, 0, H.totalSeconds, nIn, W.overviewSeconds)}, ...
        't', Ov.t_from(r), 'w', W.overviewSeconds, 'nb', Ov.nBeats(r), 'inc', inc, 'V', V(r, :), ...
        'names', {pn}, 'units', {un}, 't0', H.recordingStart, 'xlim', [0 H.totalSeconds], 'bands', B, ...
        'bandLabels', {bl}, 'com', cc);
    TR(end+1) = struct('channel', c, 'D', D); %#ok<AGROW>
end
end


function files = trendImages(d, n, TR)
% trend images <d>/<name>_ch<c>.png of the channels of TR (recordingTrends); d = imageFolder(...)
files = {};
for k = 1:numel(TR)
    f = mda_report('trend', fullfile(d, sprintf('%s_ch%d.png', n, TR(k).channel)), TR(k).D);
    if ~isempty(f), files{end+1} = f; end %#ok<AGROW>
end
end


function [T, C] = trendTables(TR, t0)
% sheets trends and trendComments (2026-10-14): the data of the trend images of all channels. trends: channel,
% window (clock time of its start), t_from (s in the file), nBeats (included contractions), the trend parameters
% (median per window; units as in the sheet parameters), bin_from (s; line of the image = median of the rows with the
% same bin_from); trendComments: channel, number (as in the image), t_file, clockTime, text. [] without channels.
T = []; C = [];
for k = 1:numel(TR)
    [Tk, Ck] = mda_report('trendData', TR(k).D);
    Tk = addvars(Tk, repmat(TR(k).channel, height(Tk), 1), clockLabels(t0, Tk.t_from), 'Before', 1, ...
        'NewVariableNames', {'channel', 'window'});
    Ck.Properties.VariableNames{'t'} = 't_file';
    Ck = addvars(Ck, repmat(TR(k).channel, height(Ck), 1), 'Before', 1, 'NewVariableNames', 'channel');
    Ck = addvars(Ck, clockLabels(t0, Ck.t_file), 'After', 't_file', 'NewVariableNames', 'clockTime');
    T = [T; Tk]; C = [C; Ck]; %#ok<AGROW>
end
end


function c = clockLabels(t0, t)
% clock times 'yyyy-mm-dd HH:MM:SS' of the times t (s in the file); '' if the clock time is unknown
c = repmat({''}, numel(t), 1);
if isempty(t) || ~isfinite(t0), return; end
c = cellstr(datestr(round((t0 + t(:) / 86400) * 86400) / 86400, 'yyyy-mm-dd HH:MM:SS'));
end


function [V, un] = trendValues(Ov, pn)
% columns pn of the overview (missing: NaN) and their units (mda_parameters; beatsPerMinute: 1/min)
PI = mda_parameters();
V = nan(height(Ov), numel(pn)); un = repmat({''}, 1, numel(pn));
for k = 1:numel(pn)
    if ismember(pn{k}, Ov.Properties.VariableNames), V(:, k) = double(Ov.(pn{k})); end
    j = find(strcmp(PI(:, 1), pn{k}), 1);
    if ~isempty(j), un{k} = PI{j, 2}; elseif strcmp(pn{k}, 'beatsPerMinute'), un{k} = '1/min'; end
end
end


function com = trendComments(E)
% comments of the log file (categories comment and protocol) for the trend images
com = struct('t', {}, 'text', {}, 'category', {}, 'channel', {});
if ~istable(E) || height(E) == 0 || ~ismember('category', E.Properties.VariableNames), return; end
k = find(ismember(E.category, {'comment', 'protocol'}))';
for j = k
    com(end+1) = struct('t', E.t_file(j), 'text', char(string(E.text(j))), 'category', E.category{j}, ...
        'channel', E.channel(j)); %#ok<AGROW>
end
end


function s = labelText(L, c)
% labels of channel c for the title: setupID, sliceID, species, tissue, sampleID, treatment (concentration unit)
s = '';
if ~istable(L) || height(L) == 0 || ~ismember('channel', L.Properties.VariableNames), return; end
r = find(L.channel == c, 1);
if isempty(r), return; end
v = {};
for nm = {'setupID', 'sliceID', 'species', 'tissue', 'sampleID', 'treatment'}
    if ~ismember(nm{1}, L.Properties.VariableNames), continue; end
    x = strtrim(char(string(L.(nm{1})(r))));
    if isempty(x) || strcmpi(x, 'NaN') || strcmp(x, '<missing>'), continue; end
    if strcmp(nm{1}, 'treatment') && all(ismember({'concentration', 'concentrationUnit'}, L.Properties.VariableNames))
        cc = strtrim(char(string(L.concentration(r)))); cu = strtrim(char(string(L.concentrationUnit(r))));
        if ~isempty(cc) && ~strcmpi(cc, 'NaN') && ~strcmp(cc, '<missing>'), x = strtrim([x ' ' cc ' ' cu]); end
    end
    v{end+1} = x; %#ok<AGROW>
end
if ~isempty(v), s = ['  ' char(183) '  ' strjoin(v, ['  ' char(183) '  '])]; end
end


function s = trendSubtitle(t0, a, b, nIn, w)
% start, duration, contractions and the legend of the trend image
if isfinite(t0)
    r = @(d) round(d * 86400) / 86400;                 %whole seconds (no 05:58 for 05:59:00)
    st = sprintf('%s to %s', datestr(r(t0 + a / 86400), 'yyyy-mm-dd HH:MM'), datestr(r(t0 + b / 86400), 'yyyy-mm-dd HH:MM'));
else
    st = 'clock time unknown';
end
s = {sprintf('%s (%.1f h), %d included contractions', st, (b - a) / 3600, round(nIn)), ...
    sprintf(['Dots: median per %g s; line: median of the dots per bin; light blue: stimulation protocol; grey: no ' ...
    'signal; purple: comments (in protocols only at start / end)'], w)};
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


% ===================================================================================================== flags table
function c = flagColumns()
c = {'file', 'analyzed', 'channel', 'label', 'status', 'nDetected', 'capture_percent', 'flags', 'level', 'red', ...
    'yellow', 'from', 'to'};
end

function T = emptyFlags()
T = table(cell(0,1), cell(0,1), zeros(0,1), cell(0,1), cell(0,1), zeros(0,1), zeros(0,1), cell(0,1), cell(0,1), ...
    cell(0,1), cell(0,1), zeros(0,1), zeros(0,1), 'VariableNames', flagColumns());
end

function T = readFlags(res)
% resultsFolder/mda_flags.csv (flags of the analysis report per recording and channel; 2026-10-14)
T = emptyFlags();
f = fullfile(res, 'mda_flags.csv');
if ~isfile(f), return; end
if numel(regexp(fileread(f), '\n', 'match')) < 2, return; end   %header only
o = detectImportOptions(f, 'FileType', 'text', 'Delimiter', ',');
cols = flagColumns();
txt = {'file', 'analyzed', 'label', 'status', 'flags', 'level', 'red', 'yellow'};
present = intersect(o.VariableNames, cols, 'stable');
o.SelectedVariableNames = present;
o = setvartype(o, intersect(present, txt), 'char');
o = setvartype(o, setdiff(present, txt), 'double');
R = readtable(f, o);
for k = 1:numel(cols)
    if ~ismember(cols{k}, R.Properties.VariableNames)
        if ismember(cols{k}, txt), R.(cols{k}) = repmat({''}, height(R), 1); else, R.(cols{k}) = nan(height(R), 1); end
    end
end
T = R(:, cols);
end

function writeFlags(res, T)
f = fullfile(res, 'mda_flags.csv');
tmp = [f '.tmp'];
if height(T) > 0, T = sortrows(T, {'file', 'channel'}); end
writetable(T, tmp, 'FileType', 'text', 'Delimiter', ',');
movefile(tmp, f, 'f');
end

function T = flagRows(R, files, analyzed)
% rows of mda_flags.csv from the flags of mda_report (column recording = file); files / analyzed: cellstr
T = emptyFlags();
if isempty(R) || height(R) == 0, return; end
n = height(R);
ana = repmat({''}, n, 1);
for i = 1:n
    j = find(strcmp(files, R.recording{i}), 1);
    if ~isempty(j), ana{i} = analyzed{j}; end
end
wf = nan(n, 1); wt = nan(n, 1);
if ismember('window_from', R.Properties.VariableNames), wf = R.window_from; wt = R.window_to; end
T = table(R.recording, ana, double(R.channel), R.label, R.status, double(R.nDetected), ...
    round(double(R.capture_percent) * 10) / 10, R.flags, R.level, R.red, R.yellow, wf, wt, 'VariableNames', flagColumns());
end

function updateFlags(res, R, done)
% mda_flags.csv: rows of the recordings of this pass replaced (also removed: error now)
files = cellfun(@(r) r.file, done, 'UniformOutput', false);
ana = cellfun(@(r) r.analyzed, done, 'UniformOutput', false);
T = readFlags(res);
T = T(~ismember(T.file, files), :);
if ~isempty(R) && height(R) > 0
    T = [T; flagRows(R(ismember(R.recording, files), :), files, ana)];
end
writeFlags(res, T);
end

function T = flagsOf(res, rel, analyzed)
% flags of one analysed recording from its result files (summary, contractions, channels); window for the channels
% to check (mda_report 'window', 20 s)
[~, n] = fileparts(strrep(rel, '\', '/'));
d = resultsOf(res, strrep(rel, '\', '/'));
T = emptyFlags();
S = resultTable(d, n, 'summary', {});
if isempty(S), return; end
C = readResult(fullfile(d, [n '_contractions.csv']), {'channel', 't_peak', 'beatType', 'uncertain', 'included', ...
    'amplitude', 'stimToOnset'});
st = resultTable(d, n, 'channels', {'channel', 'status'});
E = resultTable(d, n, 'events', {'code', 'text', 't_file'});
R = mda_report('flags', S, C, st, mda_report('defaults'), E);
R = addvars(R, repmat({rel}, height(R), 1), 'Before', 1, 'NewVariableNames', 'recording');
R.window_from = nan(height(R), 1); R.window_to = nan(height(R), 1);
for j = find(strcmp(R.level, 'check'))'
    [R.window_from(j), R.window_to(j)] = mda_report('window', C, R.channel(j), R.flags{j}, 20);
end
T = flagRows(R, {rel}, {analyzed});
end

function [T, missing] = flagsTable(res, compute, progressFcn)
% flags of the analysis report per recording and channel for the results browser of the GUI (2026-10-14):
% mda_flags.csv (written by the watcher); recordings with the status ok whose flags are missing or older than their
% analysis (index column analyzed) are computed from their result files if compute is true (and written to
% mda_flags.csv unless a watcher is running). missing: files still without current flags.
X = readIndex(res);
T = readFlags(res);
ok = X(strcmp(X.status, 'ok'), :);
key = strcat(T.file, '|', T.analyzed);
isMissing = ~ismember(strcat(ok.file, '|', ok.analyzed), key);
missing = ok.file(isMissing);
if ~compute || isempty(missing)
    T = T(ismember(key, strcat(ok.file, '|', ok.analyzed)), :);   %only the flags of the current analyses
    return;
end
T = T(~ismember(T.file, missing), :);
ana = ok.analyzed(isMissing);
for k = 1:numel(missing)
    if ~isempty(progressFcn), progressFcn(k - 1, numel(missing)); end
    try
        T = [T; flagsOf(res, missing{k}, ana{k})]; %#ok<AGROW>
    catch
    end
end
lock = dir(fullfile(res, 'mda_watch.lock'));
if isempty(lock) || (now - lock.datenum) * 24 >= lockStaleHours()
    try
        writeFlags(res, T);
    catch
    end
end
missing = ok.file(~ismember(strcat(ok.file, '|', ok.analyzed), strcat(T.file, '|', T.analyzed)));
T = T(ismember(strcat(T.file, '|', T.analyzed), strcat(ok.file, '|', ok.analyzed)), :);
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
    warning('MyoDishAnalysisWatch: lock file %s could not be deleted (%s); delete it, otherwise the next passes are skipped for 1 h.', f, ME.message);
end
end


function touchLock(lock, force)
% heartbeat of the lock file of a pass (2026-10-14): rewritten (time) at most once a minute (force: now) during the
% scan, after every recording and before long steps; a lock file not refreshed for lockStaleHours() is ignored by the
% next watcher (crashed). '' = no lock (dry run)
persistent last
if isempty(lock), return; end
if nargin < 2, force = false; end
if ~force && ~isempty(last) && (now - last) * 86400 < 60, return; end
last = now;
fid = fopen(lock, 'w');
if fid < 0, return; end
fprintf(fid, '%d %s\n', feature('getpid'), datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fclose(fid);
end


function h = lockStaleHours()
% a lock file not refreshed for this time (h) is ignored: watcher crashed (before 2026-10-14: 12 h after its creation)
h = 1;
end


function row = newRow(rel, nBytes, modified, logBytes, version, code, otext)
row = struct('file', rel, 'bytes', nBytes, 'modified', modified, 'logBytes', logBytes, 'status', '', ...
    'version', version, 'implementation', 'MATLAB', 'code', code, 'options', otext, ...
    'analyzed', datestr(now, 'yyyy-mm-dd HH:MM:SS'), 'seconds', nan, 'nContractions', nan, 'outputs', '', 'message', '');
end


function tf = isSelected(rel, W, incP, excP)
% the recording rel passes 'filter', 'include' and 'exclude'
tf = false;
if ~isempty(W.filter)                                  %as Python re.search
    if W.caseSensitive, m = regexp(rel, W.filter, 'once', 'emptymatch');
    else, m = regexpi(rel, W.filter, 'once', 'emptymatch'); end
    if isempty(m), return; end
end
tf = ~((~isempty(incP) && ~wildcardMatch(rel, incP, W.caseSensitive)) || ...
    (~isempty(excP) && wildcardMatch(rel, excP, W.caseSensitive)));
end


function [status, note] = precheck(nBytes, mtime, logBytes)
% checks without reading the file (2026-10-13; as precheck in watch.py): 'incomplete' for an empty file or a file dated
% before 1990 (robocopy marks unfinished copies with 1980), 'noLog' without log file or with an empty one. These
% states end when the file or the log file changes (no time limit).
status = ''; note = '';
if nBytes == 0
    status = 'incomplete'; note = 'empty file (0 bytes): copy not finished';
elseif mtime < datenum(1990, 1, 1)      %until the copy is finished (robocopy then sets the time of the source file)
    status = 'incomplete'; note = 'file time before 1990: copy not finished (robocopy dates unfinished copies to 1980)';
elseif logBytes < 0
    status = 'noLog'; note = 'no log file <name>_log.log';
elseif logBytes == 0
    status = 'noLog'; note = 'log file <name>_log.log empty: copy not finished';
end
end


function [status, note] = completeness(f, lastChange, H, W, t)
% ('running' | 'incomplete', message) while a recording is written or copied; ('', note) if it is analysed (note:
% analysed although incomplete). lastChange, t: datenum (2026-10-13; as completeness in watch.py)
%   no data (< 1 s):            'incomplete' until the file changes
%   no 'Recording stopped':     'running' until the end of the data (start in the log file + duration of the file) is
%                               'incompleteAfterHours' ago (clock time unknown or > 1 h in the future: the last change
%                               of the files instead)
%   file shorter than the log:  'incomplete' if more than max(10 s, 'incompleteTolerance' %) is missing; analysed (with
%                               a note) when unchanged for 'incompleteAfterHours'
status = ''; note = '';
if H.totalSeconds < 1
    status = 'incomplete'; note = 'no data in the file (< 1 s): copy not finished';
    return;
end
if H.recordingStopped == 0
    e = H.recordingStart + H.totalSeconds / 86400;
    if isfinite(e) && e <= t + 1 / 24
        age = (t - e) * 24;
        msg = sprintf('no ''Recording stopped'' in the log file yet (data until %s)', datestr(e, 'yyyy-mm-dd HH:MM'));
    else                                %no clock time, or the clock of the recording computer is ahead
        age = (t - lastChange) * 24;
        msg = 'no ''Recording stopped'' in the log file yet';
    end
    if age < W.incompleteAfterHours, status = 'running'; note = msg; end
    return;
end
if H.recordingStopped == 1
    d = logRecordings([f(1:end-4) '_log.log'], f).seconds;
    if isfinite(d) && d > 0
        miss = d - H.totalSeconds;
        if miss > max(10, W.incompleteTolerance / 100 * d)
            msg = sprintf('file %.0f s, recording in the log file %.0f s (%.1f %% missing): copy incomplete', ...
                H.totalSeconds, d, 100 * miss / d);
            if (t - lastChange) * 24 >= W.incompleteAfterHours
                note = sprintf('%s; analysed after %g h without change', msg, W.incompleteAfterHours);
            else
                status = 'incomplete'; note = msg;
            end
        end
    end
end
end


function D = logRecordings(logFile, mddFile)
% 'Recording' entries of the log file of mddFile (completeness check and parallel recordings, 2026-10-13):
%   seconds   recorded time of the file: sum of its intervals started -> stopped, at most last stop - first start (s,
%             dataLogTime; NaN without complete interval)
%   stopped   1 if its last entry is 'stopped', 0 if 'started', NaN without entries
%   parallel  the file was recorded as a parallel recording (its entries are 'parallel recording' entries; the
%             software of 2020 wrote them for main recordings as well)
%   started   struct array name (lower case), a, b: the parallel recordings started from this log (s of this file;
%             b NaN if missing)
% Entries of the recording of the file: 'started: <file>' / 'stopped: <file>' (any file name: renamed files), else
% 'started / stopped parallel recording: <this file>'. As log_recordings in watch.py.
D = struct('seconds', nan, 'stopped', nan, 'parallel', false, 'started', struct('name', {}, 'a', {}, 'b', {}));
txt = readLogText(logFile);
if isempty(txt), return; end
[~, n, e] = fileparts(mddFile);
own = lower([n e]);
lines = regexp(txt, '\r?\n', 'split');
ev = zeros(0, 3); nm = {};                             %time, 1 started / 0 stopped, parallel; file name or ''
for i = 1:numel(lines)
    if ~contains(lines{i}, 'ecording', 'IgnoreCase', true), continue; end
    f = strsplit(lines{i}, ';');
    if numel(f) < 5 || ~strcmpi(strtrim(f{4}), 'recording'), continue; end
    tt = str2double(f{2}) / 1000;
    v = strtrim(strjoin(f(5:end), ';')); lv = lower(v);
    if contains(lv, 'started'), k = 1; elseif contains(lv, 'stopped'), k = 0; else, continue; end
    if isnan(tt), continue; end
    j = find(v == ':', 1);
    name = '';
    if ~isempty(j)
        p = regexp(strtrim(v(j+1:end)), '[\\/]', 'split');
        name = lower(strtrim(p{end}));
    end
    ev(end+1, :) = [tt, k, contains(lv, 'parallel')]; %#ok<AGROW>
    nm{end+1} = name; %#ok<AGROW>
end
mine = find(ev(:, 3) == 0);
if isempty(mine)
    mine = find(ev(:, 3) == 1 & (cellfun(@isempty, nm(:)) | strcmp(nm(:), own)));
    D.parallel = ~isempty(mine);
end
for i = 1:size(ev, 1)
    if ev(i, 3) == 1 && ~isempty(nm{i}) && ~strcmp(nm{i}, own)
        j = find(strcmp({D.started.name}, nm{i}), 1, 'last');
        if ev(i, 2) == 1
            D.started(end+1) = struct('name', nm{i}, 'a', ev(i, 1), 'b', nan);
        elseif ~isempty(j) && isnan(D.started(j).b)
            D.started(j).b = ev(i, 1);
        end
    end
end
if isempty(mine), return; end
E = ev(mine, :);
D.stopped = double(E(end, 2) == 0);
tot = 0; t0 = nan; n = 0;
for i = 1:size(E, 1)
    if E(i, 2) == 1 && isnan(t0)
        t0 = E(i, 1);
    elseif E(i, 2) == 0 && ~isnan(t0)
        tot = tot + E(i, 1) - t0; t0 = nan; n = n + 1;
    end
end
if n > 0
    s0 = E(find(E(:, 2) == 1, 1), 1); s1 = E(find(E(:, 2) == 0, 1, 'last'), 1);
    if s1 > s0, D.seconds = min(tot, s1 - s0); else, D.seconds = tot; end
end
end


function M = mainRecording(f, D, cache, prefixOnly)
% main recording of the parallel recording f (D = logRecordings of f): a recording of the same folder whose log lists
% f as parallel recording ('started parallel recording: <name of f>') with the same duration (+-max(5 s, 1 %), if
% both are known). Returns struct main (path), a, b (s of the main file) or []. cache (containers.Map): logs of the
% folder read once per pass. prefixOnly (GUI): only the recordings whose name is the beginning of the name of f (fast;
% about 90 % of the parallel recordings). As main_recording in watch.py.
M = [];
if nargin < 4, prefixOnly = false; end
[folder, own] = fileparts(f);
if ~isKey(cache, folder)
    R = struct('name', {}, 'main', {}, 'a', {}, 'b', {});
    L = dir(folder);
    L = L(~[L.isdir] & ~startsWith({L.name}, '.'));
    names = sort({L.name});
    isMdd = endsWith(lower(names), '.mdd');
    mdd = names(isMdd);
    stems = regexprep(mdd, '\.mdd$', '', 'ignorecase');
    for k = find(endsWith(lower(names), '_log.log'))
        j = find(strcmpi(stems, names{k}(1:end-8)), 1);
        if isempty(j), continue; end
        if prefixOnly && ~(numel(stems{j}) < numel(own) && strncmpi(own, stems{j}, numel(stems{j}))), continue; end
        m = fullfile(folder, mdd{j});
        S = logRecordings(fullfile(folder, names{k}), m);
        for i = 1:numel(S.started)
            R(end+1) = struct('name', S.started(i).name, 'main', m, 'a', S.started(i).a, 'b', S.started(i).b); %#ok<AGROW>
        end
    end
    cache(folder) = R;                                 %containers.Map: handle
end
R = cache(folder);
if isempty(R), return; end
[~, n, e] = fileparts(f);
d = D.seconds;
for i = find(strcmpi({R.name}, [n e]))
    if strcmpi(R(i).main, f), continue; end
    if isfinite(R(i).b) && isfinite(d) && abs((R(i).b - R(i).a) - d) > max(5, 0.01 * d)
        continue;                                      %another recording of the same name
    end
    M = R(i);
    return;
end
end


function s = windowText(a, b)
if isfinite(b), s = sprintf('%.1f-%.1f s', a, b); else, s = sprintf('from %.1f s', a); end
end


function txt = readLogText(f)
% text of a MyoDish log file (UTF-16 little endian with or without byte order mark, or UTF-8); '' if missing
txt = '';
fid = fopen(f, 'r');
if fid < 0, return; end
b = fread(fid, inf, 'uint8=>uint8')';
fclose(fid);
if numel(b) >= 4 && ((b(1) == 255 && b(2) == 254) || (b(2) == 0 && b(4) == 0))
    if b(1) == 255, b = b(3:end); end
    b = b(1:2*floor(numel(b)/2));
    txt = char(double(b(1:2:end)) + 256 * double(b(2:2:end)));
else
    txt = native2unicode(b, 'UTF-8');
end
end


function P = patternList(x)
% wildcard patterns of the options 'include' / 'exclude': '' / {} = none, char (several separated by ',' or ';'),
% string array or cell array
if isempty(x), P = {}; return; end
if ischar(x) || (isstring(x) && isscalar(x)), x = regexp(char(x), '[,;]', 'split'); end
P = strrep(strtrim(cellstr(x)), '\', '/');
P = P(~cellfun(@isempty, P));
end


function tf = wildcardMatch(rel, P, caseSensitive)
% true if the relative path rel ('folder/name.mdd') matches one of the wildcard patterns P (* any characters, ? one
% character): a pattern without '/' is matched against the whole path, every folder name and the file name, a pattern
% with '/' against the whole path (2026-10-13; as watch.wildcard_match in Python)
rel = strrep(rel, '\', '/');
tf = false;
for k = 1:numel(P)
    rx = ['^' strrep(strrep(regexptranslate('escape', P{k}), '\*', '.*'), '\?', '.') '$'];
    if contains(P{k}, '/'), parts = {rel}; else, parts = [{rel}, strsplit(rel, '/')]; end
    if caseSensitive, m = regexp(parts, rx, 'once'); else, m = regexpi(parts, rx, 'once'); end
    if any(~cellfun(@isempty, m)), tf = true; return; end
end
end
