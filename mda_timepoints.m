function TP = mda_timepoints(resultsFolder, label, series, channels, time, offsets, varargin)
%MDA_TIMEPOINTS  Contraction parameters in time windows before and after a treatment (e.g. a substance added at a
%known clock time), from the results of MyoDishAnalysisWatch.
%
%   TP = mda_timepoints(resultsFolder, label, series, channels, time, offsets)
%   TP = mda_timepoints(resultsFolder, label, series, channels, time, offsets, seconds)
%   TP = mda_timepoints(..., 'parameters', {...}, 'baseline', -60, 'write', true, 'figures', true)
%
%   TP = mda_timepoints('/data/results', 'Mava100', 'Setup1_ABC000101', [1 3 5], '2000-01-01 15:20', ...
%                       [-10 10 60 240 1440])
%        channels 1, 3 and 5 of the setup 1 (recordings Setup1_ABC000101_<n>.mdd), substance added at 15:20:
%        windows of 120 s starting 10 min before and 10 min, 1 h, 4 h and 24 h after
%   TP = mda_timepoints(res, 'Ome2uM', {'Setup1_ABC000101', 'Setup2_ABC000101'}, [1 2 0; 4 5 6], ...
%                       {'2000-01-01 13:20:00', '2000-01-01 13:30:00'}, [-60 120], 300)
%        two setups (channels 1 and 2 of setup 1, 4 to 6 of setup 2), one time per setup, windows of 300 s
%
% INPUTS
%   resultsFolder  results folder of the watcher (MyoDishAnalysisWatch(rawFolder, resultsFolder): the folder with
%                  mda_index.csv) or a folder in it (e.g. the folder of the experiment)
%   label          name of the treatment, e.g. 'Mava100' (letters, digits, '.', '-', '_'): name of the output folder
%   series         recordings of one setup: the file name up to its number ('Setup1_ABC000101' for
%                  Setup1_ABC000101_3.mdd); several series as a cell or string array
%   channels       [] = all channels with contractions in the windows; a vector (the same channels in every series);
%                  a matrix with one row per series (0 or NaN = no channel), or a cell array with one vector per series
%   time           clock time of the treatment: datetime or text ('yyyy-mm-dd HH:MM[:SS]' or 'dd.mm.yyyy HH:MM[:SS]');
%                  one time for all channels, one per series (vector, cell or string array), or one per channel (an
%                  array of the size of the channel matrix, or one per channel in the order of the channels, series by
%                  series)
%   offsets        start of the windows in minutes after the treatment (required, negative = before), e.g. [-60 120]
%   seconds        duration of every window in s (default 120)
% OPTIONS
%   'parameters'   columns of the contraction table (default {'amplitude', 'diastolicForce', 'TTP90', 'TTR90',
%                  'CD50', 'CD90', 'dFdtMax', 'dFdtMin', 'AUC', 'beatsPerMinute'}, see mda_parameters; CD90 = 10 %
%                  upstroke to 90 % relaxation = TTP90 + TTR90 of the beat); dFdtMax and dFdtMin in mN/s (the analysis:
%                  uN/s), also in the sheets beats and course; beatsPerMinute = all contractions of the window per
%                  minute
%   'baseline'     offset (min) of the reference window of pctBaseline (default: the last negative offset; none: no
%                  pctBaseline)
%   'write'        write the files (default true); 'figures' the images (default true, with 'write')
%   'averageBeats' average beats per window from the raw data (default true; needs the recordings, read only)
%   'rawFolder'    raw folder of the watcher: recordings at <rawFolder>/<path in mda_index.csv> (default: the path of
%                  the analysis, info sheet 'file')
%   'sampleID'     sample (tissue, heart) of the slices: one text or one per series (default: the slice register, else
%                  the series name after the setup: Setup1_ABC000101 --> ABC000101); for mda_poolTimepoints
%   'group'        group of the sample, e.g. 'HTX' or 'LVAD': one text or one per series (default '')
%
% WINDOWS start exactly at time + offset and last 'seconds' ([start, start + seconds), clock time of the peak of the
% contraction); they are never shifted. Values per window of the included contractions (column included of the
% contraction table, all beat types): mean (column <parameter>), SD, SEM (SD / sqrt(n)), median, quartiles (q25, q75);
% nBeats (all contractions), nIncluded, nExtra (extra beats); normalized to the baseline window of the same channel:
% <parameter>_pctBaseline = 100 * mean / mean of the baseline window, for the diastolic force the absolute change
% diastolicForce_delta = mean - mean of the baseline window (uN; a diastolic force near 0 or negative has no
% meaningful % of baseline). Windows without contractions although recorded (no gap of the signal): the slice does not
% contract: amplitude, AUC, dFdtMax, dFdtMin and beatsPerMinute 0, TTP90, TTR90, CD50, CD90 NaN, the diastolic force
% from the signal (median of the force filtered as in the analysis - zero force; needs the recording; note 'diastolic
% force from the signal'). Notes (column
% note) say what may make a window unusual: stimulation protocols, periods without signal (chamber out, no signal,
% technical; from the gaps of the watcher), user comments in the window, fewer than 80 % of the expected contractions
% included (expected = seconds x median stimulation or beat frequency of the window), another slice than in the
% baseline window (slice register; then no pctBaseline), a window that ends after the treatment (baseline), windows
% without recording, and 'pending: no data yet' for windows after the end of the analysed recordings (call
% mda_timepoints again after the next pass of the watcher), and two amplitude groups of the included beats (1-D
% 2-means: each group >= 20 % of the beats, means >= 20 % and >= 3 SD apart): 'alternans: 2 amplitude groups 1693 /
% 3727 uN (42 % small beats, 83 % of successive beats switch)' if >= 80 % of successive beats switch the group,
% otherwise 'irregular amplitudes: 2 groups ...'; mean and median then describe neither group, see the average
% beats. Parallel recordings of a main file are not used twice.
%
% AVERAGE BEATS (2026-10-15): the included beats of a window without extra beats and without another contraction in
% the segment, aligned at the stimulus (unpaced: at the onset), from 0.1 s before to the next beat - 0.05 s (shortest
% beat interval of the windows, at most 4 s), raw force of the recording (mda_readMdd) - zero force of the channel
% (summary), filtered as in the analysis (moving median and mean, options of the analysis), on a 2-ms grid,
% averaged; with alternans also the small and the large beats separately. Columns force_uN
% (absolute: the diastolic force is kept), norm_baselineAmplitude ((F - diastole of the baseline average beat) / its
% amplitude: the baseline beat goes from 0 to 1, the other windows show the change of amplitude and diastole on this
% scale; comparable between slices) and norm_ownAmplitude ((F - own diastole) / own amplitude + (own diastole -
% baseline diastole) / baseline amplitude: every beat has the amplitude 1 and keeps its diastolic change against the
% baseline, e.g. omecamtiv mecarbil; without baseline window: own diastole = 0); diastole = mean of the 0.1 s before the
% stimulus. Every column with its standard error (..._SE: SD of the beats / sqrt(n)). Summary: nAvgBeats,
% avgBeat_diastolic, avgBeat_amplitude (uN).
%
% OUTPUT FILES (folder of the experiment in the results folder: <experiment>/timepoints/<label>_<yyyy-mm-dd-HH-MM>/,
% time = the earliest treatment time; several experiments: one folder each; existing files of the same name are
% replaced, the watcher never changes these folders):
%   <label>_<time>.xlsx            sheets summary (one row per series, channel and window: counts, note, per
%                                  parameter mean and pctBaseline (diastole: delta), then per parameter SD and SEM,
%                                  median, q25, q75, then the average beat: nAvgBeats, avgBeat_diastolic,
%                                  avgBeat_amplitude), matrix (per parameter the means and pctBaseline: one row per
%                                  series and channel, one column per offset), course (1-min values of the overview of
%                                  the watcher from 30 min before the first to 30 min after the last window: median
%                                  per minute of the included contractions, extra beats excluded; normalized with the
%                                  medians of the baseline window), beats (all contractions of the windows; more
%                                  than 1 million rows: <label>_<time>_beats.csv), averageBeats (series, channel,
%                                  offset_min, trace =
%                                  all / small beats / large beats, nBeats, t_s, force_uN, norm_baselineAmplitude,
%                                  norm_ownAmplitude, each with ..._SE), averageBeatsMean (mean, SD and SE of the
%                                  channels per window: force, baseline amplitude = 1, own amplitude = 1) and info
%                                  (call, version, recordings used, notes)
%   images, each absolute (_abs) and normalized to the baseline window (_norm; not without baseline window):
%   <label>_<time>_timepoints_abs / _norm.png / .fig   per parameter over the windows: mean +- SEM of the beats (abs)
%                                  or pctBaseline (norm), one line per channel, black = mean +- SEM of the channels
%   <label>_<time>_course_abs / _norm.png / .fig       per parameter the 1-min course relative to the treatment
%                                  (values or pctBaseline), one line per channel, black = mean +- SEM of the
%                                  channels, windows grey, treatment = dashed line
%   <label>_<time>_averageBeats_abs / _norm.png / .fig one panel per channel: force (uN; abs), or one row per channel:
%                                  baseline amplitude = 1, own amplitude = 1 (norm; without baseline: own amplitude);
%                                  +- SE shaded, one color per window (baseline black), alternans groups dashed
%   <label>_<time>_averageBeatsMean_abs / _norm.png / .fig  mean +- SE of the channels (force; baseline amplitude = 1,
%                                  own amplitude = 1)
%   averageBeats/<series>_ch<c>.png / .fig      one 16:9 slide per channel (for presentations): average beats +- SE in
%                                  uN and with the own amplitude = 1, table of the values per window (n, amplitude,
%                                  diastolic force, TTP90, TTR90 and their change against the baseline, note)
%
% TP  struct with the same data: label, time (earliest treatment time), offsets, seconds, baseline (offset, NaN =
%     none), parameters, units, rows (table series, channel, sampleID, group, time, experiment: one row per channel =
%     rows of the matrices), summary, matrix.<parameter> (means) and pctBaseline.<parameter> (normalized;
%     diastolicForce: delta in uN) (channels x offsets), course, beats, averageBeats, averageBeatsMean, notes, info,
%     folder (char; cell for several experiments), files
%
% Several analyses (experiments, samples) by treatment: mda_poolTimepoints.
% Python: myodish_analysis.timepoints.timepoints (same arguments, files and values; images as .png and .svg).
%
% TS 2026-10-15 (average beats, alternans, standard errors, slides per channel 2026-10-15; means, SD, SEM, CD90, dF/dt,
% AUC, diastolic force as change in uN, windows without contractions, images absolute and normalized 2026-10-16)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

% images of a TP struct (mda_poolTimepoints): files = mda_timepoints('figures', TP, folder, base[, kinds])
if (ischar(resultsFolder) || isstring(resultsFolder)) && strcmp(resultsFolder, 'figures') && isstruct(label)
    kinds = {'timepoints', 'course', 'averageBeats', 'averageBeatsMean', 'slides'};
    if nargin >= 5, kinds = cellstr(time); end
    TP = writeFigures(char(series), char(channels), label, kinds);
    return;
end

% ---------------------------------------------------------------------------------------------------- inputs
sec = 120;
a = varargin;
if ~isempty(a) && isnumeric(a{1}), sec = a{1}; a = a(2:end); end
P = struct('parameters', {{'amplitude', 'diastolicForce', 'TTP90', 'TTR90', 'CD50', 'CD90', 'dFdtMax', 'dFdtMin', ...
    'AUC', 'beatsPerMinute'}}, ...
    'baseline', [], 'write', true, 'figures', true, 'seconds', [], 'averageBeats', true, 'rawFolder', '', ...
    'sampleID', '', 'group', '');
if mod(numel(a), 2) ~= 0, error('mda_timepoints: options as name, value pairs expected.'); end
for i = 1:2:numel(a)
    name = validatestring(a{i}, fieldnames(P));
    P.(name) = a{i+1};
end
if ~isempty(P.seconds), sec = P.seconds; end
if ~(isnumeric(sec) && isscalar(sec) && isfinite(sec) && sec > 0)
    error('mda_timepoints: seconds: a positive number expected.');
end
sec = double(sec);
label = char(label);
if isempty(regexp(label, '^[A-Za-z0-9._-]+$', 'once'))
    error('mda_timepoints: label: letters, digits, ''.'', ''-'' and ''_'' expected (name of the output folder).');
end
if ~(isnumeric(offsets) && ~isempty(offsets) && all(isfinite(offsets(:))))
    error('mda_timepoints: offsets: minutes after the treatment expected, e.g. [-60 120].');
end
offsets = double(offsets(:)');
if numel(unique(offsets)) < numel(offsets), error('mda_timepoints: offsets: each offset only once.'); end
pars = cellstr(P.parameters);
pars = pars(:)';
if isempty(pars), error('mda_timepoints: parameters: at least one parameter expected.'); end
baseOff = baselineOffset(P.baseline, offsets);
S = cellstr(series); S = strtrim(S(:)');
if isempty(S) || any(cellfun(@isempty, S)), error('mda_timepoints: series: name(s) of the series expected.'); end
[pS, pC, pT, allCh] = expandPairs(S, channels, time);
smpS = labelPerSeries(P.sampleID, S, 'sampleID');
grpS = labelPerSeries(P.group, S, 'group');

res = indexFolder(char(resultsFolder));
X = MyoDishAnalysisWatch('index', res);
recs = seriesRecordings(res, X, S);
for i = 1:numel(S), recs.(fieldName(S{i})).raw = char(P.rawFolder); end

% channels [] = all channels with contractions in the windows of the series
cache = struct('key', {{}}, 'D', {{}});
rawCache = struct('file', {{}}, 'H', {{}});
abNotes = {};
if any(allCh)
    [pS, pC, pT, cache] = allChannels(pS, pC, pT, allCh, recs, offsets, sec, pars, cache);
end
nP = numel(pS); nK = numel(offsets);
if nP == 0, error('mda_timepoints: no channel with contractions in the windows.'); end
iS = cellfun(@(s) find(strcmp(S, s), 1), pS);
pSmp = smpS(iS); pGrp = grpS(iS);                  %sample ID and group of the channels ('' = from the data)
units = parameterUnits(pars);

% ---------------------------------------------------------------------------------------------------- windows
cols = summaryColumns(pars);
col = containers.Map(cols, 1:numel(cols));
Srows = cell(nP * nK, numel(cols));
Bparts = cell(nP, nK);
ABparts = cell(nP, 1);
used = {};
kb = [];
if ~isempty(baseOff), kb = find(offsets == baseOff, 1); end
Mval = nan(nP, nK, numel(pars));                   %means (main values)
Med = Mval;                                        %medians (normalization of the course)
regCache = containers.Map();
for p = 1:nP
    R = recs.(fieldName(pS{p}));
    sliceRow = nan(1, nK);
    Wb = cell(1, nK);                                  %included beats of the windows (average beats)
    for k = 1:nK
        a0 = pT(p) + minutes(offsets(k)); b0 = a0 + seconds(sec);
        notes = {};
        inR = find(R.start < b0 & R.stop > a0);
        C = []; recNames = {};
        for j = inR(:)'
            [D, cache] = recordingData(cache, R, j, pars);
            recNames{end+1} = R.name{j}; %#ok<AGROW>
            used{end+1} = R.rel{j}; %#ok<AGROW>
            c = D.C(D.C.channel == pC(p) & D.C.clock >= a0 & D.C.clock < b0, :);
            c.rec_ = repmat(j, height(c), 1);
            if isempty(C), C = c; else, C = [C; c]; end %#ok<AGROW>
            notes = [notes, windowNotes(D, pC(p), a0, b0)]; %#ok<AGROW>
            if contains(R.options{j}, 'contractions=thinned'), notes{end+1} = 'thinned contractions'; end %#ok<AGROW>
        end
        if isempty(inR)
            if isempty(R.stop) || a0 >= max(R.stop), notes{end+1} = 'pending: no data yet';
            else, notes{end+1} = 'no recording'; end
        elseif a0 < min(R.start(inR)) || b0 > max(R.stop(inR)) || coverageGap(R, inR, a0, b0)
            notes{end+1} = 'window partly without recording';
        end
        if isempty(C), C = emptyContractions(pars); C.rec_ = zeros(0, 1); end
        C = sortrows(C, 'clock');
        nB = height(C);
        inc = C.included == 1;
        nI = sum(inc);
        nE = sum(strcmp(C.beatType, 'extra'));
        f = median(C.stimFrequency, 'omitnan');
        if isnan(f), f = median(C.peakToPeakFrequency, 'omitnan'); end
        if ~isnan(f) && f > 0 && nI < 0.8 * sec * f
            notes{end+1} = sprintf('%d of ~%d expected contractions included', nI, round(sec * f)); %#ok<AGROW>
        end
        if nB == 0 && ~isempty(inR), notes{end+1} = 'no contractions'; end %#ok<AGROW>
        if ~isempty(kb) && k == kb && b0 > pT(p)
            notes{end+1} = 'baseline window ends after the treatment'; %#ok<AGROW>
        end
        ib = inc & ~strcmp(C.beatType, 'extra');       %alternans: two amplitude groups of the included beats
        [grp, atxt] = alternansGroups(C.amplitude(ib));
        if ~isempty(atxt), notes{end+1} = atxt; end %#ok<AGROW>
        al = C.t_stim(ib); u = isnan(al); tOn = C.t_onset(ib); al(u) = tOn(u);   %unpaced: onset
        Wb{k} = table(C.rec_(ib), al, C.t_peak(ib), grp(:), 'VariableNames', {'j', 'align', 'tpeak', 'grp'});
        [sliceRow(k), regCache, sid] = sliceAt(res, R, pS{p}, pC(p), a0, regCache);
        if isempty(pSmp{p}) && ~isempty(sid), pSmp{p} = sid; end    %sample ID of the slice register
        [vals, sdv, sem, med, q25, q75] = deal(nan(1, numel(pars)));
        for i = 1:numel(pars)
            if strcmp(pars{i}, 'beatsPerMinute')
                if ~isempty(inR), vals(i) = nB / sec * 60; med(i) = vals(i); end
            else
                x = C.(pars{i})(inc); x = x(~isnan(x));
                if ~isempty(x)
                    vals(i) = mean(x); med(i) = median(x); q25(i) = mprctile(x, 25); q75(i) = mprctile(x, 75);
                    if numel(x) > 1, sdv(i) = std(x); sem(i) = sdv(i) / sqrt(numel(x)); end
                end
            end
        end
        % no contractions although recorded (no gap of the signal in the window): the slice does not contract:
        % amplitude, AUC, dF/dt and beatsPerMinute 0, times NaN, diastolic force from the signal (median of the
        % filtered force - zero force; needs the recording)
        if nB == 0 && ~isempty(inR) && ~any(strcmp(notes, 'window partly without recording'))
            [gap, cache] = signalGap(R, inR, cache, pC(p), a0, b0, pars);
            if ~gap
                z = ismember(pars, {'amplitude', 'AUC', 'dFdtMax', 'dFdtMin'});
                [vals(z), med(z), q25(z), q75(z)] = deal(0);
                id = find(strcmp(pars, 'diastolicForce'), 1);
                if ~isempty(id)
                    [v, cache, rawCache, nt] = signalForce(R, inR, cache, rawCache, pC(p), a0, b0, pars);
                    abNotes = [abNotes, nt]; %#ok<AGROW>
                    if ~isnan(v)
                        [vals(id), med(id)] = deal(v); notes{end+1} = 'diastolic force from the signal'; %#ok<AGROW>
                    end
                end
            end
        end
        Mval(p, k, :) = vals; Med(p, k, :) = med;
        r = (p - 1) * nK + k;
        Srows(r, cellfun(@(x) col(x), {'series', 'channel', 'time', 'offset_min', 'from', 'to', 'recording', ...
            'slice', 'nBeats', 'nIncluded', 'nExtra', 'note'})) = {pS{p}, pC(p), clockText(pT(p)), offsets(k), ...
            clockText(a0), clockText(b0), strjoin(unique(recNames, 'stable'), ';'), sliceRow(k), nB, nI, nE, ''};
        for i = 1:numel(pars)
            Srows(r, [col(pars{i}), col(normName(pars{i})), col([pars{i} '_SD']), col([pars{i} '_SEM']), ...
                col([pars{i} '_median']), col([pars{i} '_q25']), col([pars{i} '_q75'])]) = ...
                {vals(i), nan, sdv(i), sem(i), med(i), q25(i), q75(i)};
        end
        Srows(r, [col('nAvgBeats'), col('avgBeat_diastolic'), col('avgBeat_amplitude')]) = {0, nan, nan};
        Srows{r, col('note')} = strjoin(unique(notes, 'stable'), '; ');
        if nB > 0
            B = C(:, setdiff(C.Properties.VariableNames, {'clock', 'rec_'}, 'stable'));
            B = addvars(B, repmat(pS(p), nB, 1), repmat(pC(p), nB, 1), repmat(offsets(k), nB, 1), ...
                repmat({clockText(a0)}, nB, 1), 'Before', 1, ...
                'NewVariableNames', {'series', 'channel_', 'offset_min', 'window_from'});
            B.channel = []; B = renamevars(B, 'channel_', 'channel');
            Bparts{p, k} = B;
        end
    end
    % sample ID: option, slice register, or the series name after the setup (Setup1_ABC000101 --> ABC000101)
    if isempty(pSmp{p}), pSmp{p} = seriesSample(pS{p}); end
    % pctBaseline: 100 * mean / mean of the baseline window (same slice); diastolicForce: change against the baseline
    % window in uN (diastolicForce_delta)
    for k = 1:nK
        r = (p - 1) * nK + k;
        Srows(r, [col('sampleID'), col('group')]) = {pSmp{p}, pGrp{p}};
        other = ~isempty(kb) && ~isnan(sliceRow(k)) && ~isnan(sliceRow(kb)) && sliceRow(k) ~= sliceRow(kb);
        if other
            Srows{r, col('note')} = joinNote(Srows{r, col('note')}, 'other slice than in the baseline window');
        end
        if isempty(kb) || other, continue; end
        for i = 1:numel(pars)
            if strcmp(pars{i}, 'diastolicForce')
                Srows{r, col(normName(pars{i}))} = Mval(p, k, i) - Mval(p, kb, i);
            else
                Srows{r, col(normName(pars{i}))} = 100 * Mval(p, k, i) / Mval(p, kb, i);
            end
        end
    end
    % average beats (raw data of the recordings)
    if logical(P.averageBeats)
        [ABparts{p}, st, nt, cache, rawCache] = pairAverageBeats(pS{p}, pC(p), Wb, offsets, kb, R, pars, cache, ...
            rawCache);
        abNotes = [abNotes, nt]; %#ok<AGROW>
        for k = 1:nK
            r = (p - 1) * nK + k;
            Srows(r, [col('nAvgBeats'), col('avgBeat_diastolic'), col('avgBeat_amplitude')]) = ...
                {st.n(k), st.dia(k), st.amp(k)};
        end
    end
end
Summary = cell2table(Srows, 'VariableNames', cols);
Pct = nan(nP, nK, numel(pars));
for i = 1:numel(pars)
    Pct(:, :, i) = reshape(Summary.(normName(pars{i})), nK, nP)';
end
Bparts = Bparts(~cellfun(@isempty, Bparts));
if isempty(Bparts), Beats = table(); else, Beats = vertcat(Bparts{:}); end
ABparts = ABparts(~cellfun(@(x) isempty(x) || height(x) == 0, ABparts));
if isempty(ABparts), AB = abTemplate(); else, AB = vertcat(ABparts{:}); end

% ---------------------------------------------------------------------------------------------------- course
rangeA = minutes(min(offsets) - 30); rangeB = minutes(max(offsets) + 30) + seconds(sec);
Cparts = cell(nP, 1);
for p = 1:nP
    R = recs.(fieldName(pS{p}));
    a0 = pT(p) + rangeA; b0 = pT(p) + rangeB;
    parts = {};
    for j = find(R.start < b0 & R.stop > a0)'
        [D, cache] = recordingData(cache, R, j, pars);
        O = D.Ov(D.Ov.channel == pC(p) & D.Ov.clock >= a0 & D.Ov.clock < b0, :);
        if ~isempty(O), parts{end+1} = O; end %#ok<AGROW>
    end
    if isempty(parts), continue; end
    O = vertcat(parts{:});
    O = sortrows(O, 'clock');
    n = height(O);
    T = table(repmat(pS(p), n, 1), repmat(pC(p), n, 1), repmat({clockText(pT(p))}, n, 1), ...
        cellstr(string(O.clock, 'yyyy-MM-dd HH:mm:ss')), round(minutes(O.clock - pT(p)) * 1e6) / 1e6, O.nBeats, ...
        'VariableNames', {'series', 'channel', 'time', 'window', 'minutes', 'nBeats'});
    for i = 1:numel(pars)                              %normalized with the medians of the baseline window
        T.(pars{i}) = O.(pars{i});
        nm = normName(pars{i});
        if isempty(kb), T.(nm) = nan(n, 1);
        elseif strcmp(pars{i}, 'diastolicForce'), T.(nm) = O.(pars{i}) - Med(p, kb, i);
        else, T.(nm) = 100 * O.(pars{i}) / Med(p, kb, i); end
    end
    Cparts{p} = T;
end
Cparts = Cparts(~cellfun(@isempty, Cparts));
if isempty(Cparts), Course = courseTemplate(pars); else, Course = vertcat(Cparts{:}); end

% ---------------------------------------------------------------------------------------------------- struct
exps = cellfun(@(s) recs.(fieldName(s)).experiment, pS, 'UniformOutput', false);
TP = struct();
TP.label = label;
TP.time = clockText(min(pT));
TP.offsets = offsets;
TP.seconds = sec;
if isempty(kb), TP.baseline = nan; else, TP.baseline = offsets(kb); end
TP.parameters = pars;
TP.units = units;
TP.rows = table(pS(:), pC(:), pSmp(:), pGrp(:), cellstr(arrayfun(@clockText, pT(:), 'UniformOutput', false)), ...
    exps(:), 'VariableNames', {'series', 'channel', 'sampleID', 'group', 'time', 'experiment'});
TP.summary = Summary;
TP.matrix = struct(); TP.pctBaseline = struct();
for i = 1:numel(pars)
    TP.matrix.(pars{i}) = Mval(:, :, i);
    TP.pctBaseline.(pars{i}) = Pct(:, :, i);
end
TP.course = Course;
TP.beats = Beats;
TP.averageBeats = AB;
TP.averageBeatsMean = averageBeatsMean(AB, offsets);
TP.notes = unique(abNotes, 'stable');
used = unique(used, 'stable');
TP.info = infoTable(TP, res, used);
TP.folder = ''; TP.files = {};
if ~logical(P.write), return; end

% ---------------------------------------------------------------------------------------------------- files
ue = unique(exps, 'stable');
folders = cell(1, numel(ue));
for e = 1:numel(ue)
    sel = strcmp(exps, ue{e});
    t0 = min(pT(sel));
    base = sprintf('%s_%s', label, char(datetime(t0, 'Format', 'yyyy-MM-dd-HH-mm')));
    if isempty(ue{e}), d = fullfile(res, 'timepoints', base);
    else, q = strsplit(ue{e}, '/'); d = fullfile(res, q{:}, 'timepoints', base); end
    if ~isfolder(d), mkdir(d); end
    folders{e} = d;
    Te = subsetTP(TP, sel, nK);
    Te.info = infoTable(Te, res, usedOf(used, Te.rows.series));
    TP.files = [TP.files, writeFiles(d, base, Te, logical(P.figures))];
end
if numel(folders) == 1, TP.folder = folders{1}; else, TP.folder = folders; end
end


% =====================================================================================================================
function off = baselineOffset(b, offsets)
% offset of the baseline window: given, or the last negative offset ([] = none)
if isempty(b)
    neg = offsets(offsets < 0);
    if isempty(neg), off = []; else, off = max(neg); end
elseif isnumeric(b) && isscalar(b) && any(offsets == b)
    off = double(b);
elseif isnumeric(b) && isscalar(b) && isnan(b)
    off = [];
else
    error('mda_timepoints: baseline: one of the offsets expected.');
end
end


function [pS, pC, pT, allCh] = expandPairs(S, channels, time)
% one element per channel: series, channel (NaN = all channels of the series, filled later), time of the treatment
nS = numel(S);
T = toTime(time);
if iscell(channels)
    if numel(channels) ~= nS, error('mda_timepoints: channels: one vector per series expected.'); end
    rows = cellfun(@(c) double(c(:)'), channels, 'UniformOutput', false);
    M = [];
elseif isempty(channels)
    rows = repmat({nan}, 1, nS); M = [];
elseif isnumeric(channels) && nS > 1 && size(channels, 1) == nS
    M = double(channels);
    rows = arrayfun(@(i) M(i, :), 1:nS, 'UniformOutput', false);
elseif isnumeric(channels) && isvector(channels)
    rows = repmat({double(channels(:)')}, 1, nS); M = [];
    if nS == 1, M = double(channels(:)'); end
else
    error('mda_timepoints: channels: [], a vector, a matrix with one row per series or a cell array expected.');
end
pS = {}; pC = []; idx = []; allCh = [];
for i = 1:nS
    r = rows{i};
    if isscalar(r) && isnan(r) && isempty(channels)
        pS{end+1} = S{i}; pC(end+1) = nan; allCh(end+1) = true; idx(end+1) = nan; %#ok<AGROW>
        continue;
    end
    for j = 1:numel(r)
        if isnan(r(j)) || r(j) == 0, continue; end
        if r(j) < 1 || r(j) ~= round(r(j)), error('mda_timepoints: channels: channel numbers 1, 2, ... expected.'); end
        if any(strcmp(pS, S{i}) & pC == r(j))
            error(['mda_timepoints: channels: channel %d of %s given twice (one channel per series: a cell array ' ...
                'such as {1, 1} or a matrix with one row per series).'], r(j), S{i});
        end
        pS{end+1} = S{i}; pC(end+1) = r(j); allCh(end+1) = false; %#ok<AGROW>
        if ~isempty(M), idx(end+1) = sub2ind(size(M), min(i, size(M, 1)), j); else, idx(end+1) = nan; end %#ok<AGROW>
    end
end
if isempty(pS), error('mda_timepoints: channels: no channel given.'); end
seriesIdx = cellfun(@(s) find(strcmp(S, s), 1), pS);
nT = numel(T);
if nT == 1
    pT = repmat(T, 1, numel(pS));
elseif ~isempty(M) && ~any(allCh) && isequal(size(T), size(M))
    pT = T(idx);
elseif ~any(allCh) && nT == numel(pS)
    pT = T(:)';
elseif nT == nS
    pT = T(seriesIdx);
else
    error(['mda_timepoints: time: one time, one per series or one per channel (the size of the channel matrix) ' ...
        'expected.']);
end
pT = pT(:)';
if any(isnat(pT)), error('mda_timepoints: time: a clock time is missing (NaT or empty).'); end
allCh = logical(allCh);
end


function T = toTime(x)
% datetime array (shape kept) from datetime, text, cell or string array
if isdatetime(x), T = x; T.Format = 'yyyy-MM-dd HH:mm:ss'; return; end
if ischar(x), x = {x}; end
if isstring(x), x = cellstr(x); end
if ~iscell(x), error('mda_timepoints: time: datetime or text expected.'); end
T = NaT(size(x));
for i = 1:numel(x)
    v = x{i};
    if isdatetime(v), T(i) = v; continue; end
    if isempty(v) || (isnumeric(v) && isscalar(v) && isnan(v)), continue; end   %no channel at this position
    s = strtrim(char(v));
    s = regexprep(s, '^(\d{4}-\d{2}-\d{2})T', '$1 ');
    if isempty(regexp(s, ['^(\d{4}-\d{1,2}-\d{1,2}|\d{1,2}\.\d{1,2}\.\d{4}) \d{1,2}:\d{2}(:\d{2}(\.\d+)?)?$'], 'once'))
        error('mda_timepoints: time ''%s'': ''yyyy-mm-dd HH:MM[:SS]'' or ''dd.mm.yyyy HH:MM[:SS]'' expected.', s);
    end
    fm = {'yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd HH:mm', 'dd.MM.yyyy HH:mm:ss', 'dd.MM.yyyy HH:mm', ...
        'yyyy-MM-dd HH:mm:ss.SSS'};
    for k = 1:numel(fm)
        try
            t = datetime(s, 'InputFormat', fm{k});
            if ~isnat(t), T(i) = t; break; end
        catch
        end
    end
    if isnat(T(i))
        error('mda_timepoints: time ''%s'': ''yyyy-mm-dd HH:MM[:SS]'' or ''dd.mm.yyyy HH:MM[:SS]'' expected.', s);
    end
end
T.Format = 'yyyy-MM-dd HH:mm:ss';
end


function res = indexFolder(f)
% the results folder of the watcher: f or the first parent folder with mda_index.csv
f = char(java.io.File(f).getCanonicalPath());
d = f;
while true
    if isfile(fullfile(d, 'mda_index.csv')), res = d; return; end
    up = fileparts(d);
    if isempty(up) || strcmp(up, d)
        error('mda_timepoints: no mda_index.csv in %s or its parent folders (results folder of the watcher).', f);
    end
    d = up;
end
end


function recs = seriesRecordings(res, X, S)
% analysed recordings of each series in the order of their start: rel, name, folder of the results, start, stop
recs = struct();
for i = 1:numel(S)
    R = struct('rel', {{}}, 'name', {{}}, 'dir', {{}}, 'num', [], 'main', [], 'options', {{}}, ...
        'start', NaT(0, 1), 'stop', NaT(0, 1), 'experiment', '');
    for r = 1:height(X)
        if ~startsWith(X.status{r}, 'ok'), continue; end
        rel = strrep(X.file{r}, '\', '/');
        [~, n] = fileparts(rel);
        [s, num, isMain] = seriesInfo(n);
        if ~strcmp(s, S{i}), continue; end
        d = MyoDishAnalysisWatch('resultFolder', res, rel);
        [t1, t2] = recordingSpan(d, n);
        if isnat(t1), continue; end
        R.rel{end+1, 1} = rel; R.name{end+1, 1} = n; R.dir{end+1, 1} = d; R.num(end+1, 1) = num;
        R.main(end+1, 1) = isMain; R.options{end+1, 1} = X.options{r}; R.start(end+1, 1) = t1; R.stop(end+1, 1) = t2;
        j = find(rel == '/', 1, 'last');
        if isempty(j), R.experiment = ''; else, R.experiment = rel(1:j-1); end
    end
    if isempty(R.rel), error('mda_timepoints: no analysed recording of the series %s in %s.', S{i}, res); end
    keep = true(numel(R.rel), 1);                       %parallel recordings: not with their main file
    for r = 1:numel(R.rel)
        if ~R.main(r) && any(R.main & R.num == R.num(r)), keep(r) = false; end
    end
    [~, o] = sort(R.start(keep));
    k = find(keep); k = k(o);
    for f = {'rel', 'name', 'dir', 'num', 'main', 'options', 'start', 'stop'}
        R.(f{1}) = R.(f{1})(k);
    end
    recs.(fieldName(S{i})) = R;
end
end


function [s, num, isMain] = seriesInfo(name)
% series, number and main recording (nothing after the number) of a file name
p = strsplit(name, '_');
s = name; num = nan; isMain = true;
for i = 2:numel(p)
    if ~isempty(regexp(p{i}, '^\d+$', 'once'))
        s = strjoin(p(1:i-1), '_'); num = str2double(p{i}); isMain = (i == numel(p));
        return;
    end
end
end


function f = fieldName(s)
f = ['s_' regexprep(s, '[^A-Za-z0-9]', '_')];
f = f(1:min(end, namelengthmax));
end


function [t1, t2] = recordingSpan(d, n)
% clock time of the start and end of a recording (info: recordingStart, fileLength_s)
t1 = NaT; t2 = NaT;
I = resultTable(d, n, 'info', {'key', 'value'}, {'key', 'value'});
if isempty(I) || ~all(ismember({'key', 'value'}, I.Properties.VariableNames)), return; end
k = cellstr(string(I.key)); v = cellstr(string(I.value));
s = v(strcmp(k, 'recordingStart')); L = str2double(v(strcmp(k, 'fileLength_s')));
if isempty(s) || isempty(L) || isnan(L(1)), return; end
t1 = parseClock(s(1));
t2 = t1 + seconds(L(1));
end


function [D, cache] = recordingData(cache, R, j, pars)
% contractions, protocols, gaps, comments and overview of recording j (read once)
key = R.rel{j};
i = find(strcmp(cache.key, key), 1);
if ~isempty(i), D = cache.D{i}; return; end
d = R.dir{j}; n = R.name{j};
pc = pars(~strcmp(pars, 'beatsPerMinute'));
cc = unique([{'channel', 'clockTime', 'beatType', 'included', 'stimFrequency', 'peakToPeakFrequency', 't_stim', ...
    't_onset', 't_peak', 'amplitude'}, pc], 'stable');
C = resultTable(d, n, 'contractions', cc, {'clockTime', 'beatType'});
C = standardContractions(C, pars);
I = resultTable(d, n, 'info', {'key', 'value'}, {'key', 'value'});
rs = R.start(j);
if ~isempty(I)
    v = cellstr(string(I.value)); s = v(strcmp(cellstr(string(I.key)), 'recordingStart'));
    if ~isempty(s), rs = parseClock(s(1)); end
end
Pr = resultTable(d, [n '_protocols'], 'protocols', {'name', 'from', 'to'}, {'name'});
if isempty(Pr) || ~all(ismember({'name', 'from', 'to'}, Pr.Properties.VariableNames))
    Pr = table(cell(0, 1), NaT(0, 1), NaT(0, 1), 'VariableNames', {'name', 'a', 'b'});
else
    Pr = table(cellstr(string(Pr.name)), rs + seconds(double(Pr.from)), rs + seconds(double(Pr.to)), ...
        'VariableNames', {'name', 'a', 'b'});
end
G = resultTable(d, n, 'gaps', {'channel', 'clockFrom', 'clockTo', 'type'}, {'clockFrom', 'clockTo', 'type'});
if isempty(G) || ~all(ismember({'channel', 'clockFrom', 'clockTo', 'type'}, G.Properties.VariableNames))
    G = table(zeros(0, 1), NaT(0, 1), NaT(0, 1), cell(0, 1), 'VariableNames', {'channel', 'a', 'b', 'type'});
else
    G = table(double(G.channel), parseClock(G.clockFrom), parseClock(G.clockTo), cellstr(string(G.type)), ...
        'VariableNames', {'channel', 'a', 'b', 'type'});
end
E = resultTable(d, n, 'events', {'clockTime', 'channel', 'category', 'text'}, ...
    {'clockTime', 'category', 'text'});
if isempty(E) || ~all(ismember({'clockTime', 'channel', 'category', 'text'}, E.Properties.VariableNames))
    E = table(NaT(0, 1), zeros(0, 1), cell(0, 1), 'VariableNames', {'t', 'channel', 'text'});
else
    E = E(strcmp(cellstr(string(E.category)), 'comment'), :);
    E = table(parseClock(E.clockTime), double(E.channel), cellstr(string(E.text)), ...
        'VariableNames', {'t', 'channel', 'text'});
end
oc = unique([{'window', 'channel', 'beatType', 'included', 'nBeats'}, pars], 'stable');
Ov = resultTable(d, n, 'overview', oc, {'window', 'beatType'});
Ov = standardOverview(Ov, pars);
% zero force per channel (summary) and the recording (average beats): <rawFolder>/<relative path> or the path of
% the analysis (info: file)
Z = resultTable(d, n, 'summary', {'channel', 'zeroForce'});
zero = nan(1, 64);
if ~isempty(Z) && all(ismember({'channel', 'zeroForce'}, Z.Properties.VariableNames))
    zc = double(Z.channel); zf = double(Z.zeroForce);
    for c = unique(zc(~isnan(zc) & zc >= 1 & zc <= 64 & ~isnan(zf)))'
        zero(c) = zf(find(zc == c & ~isnan(zf), 1));
    end
end
mdd = '';
cand = {};
if isfield(R, 'raw') && ~isempty(R.raw), q = strsplit(R.rel{j}, '/'); cand{end+1} = fullfile(R.raw, q{:}); end
if ~isempty(I)
    v = cellstr(string(I.value)); f = v(strcmp(cellstr(string(I.key)), 'file'));
    if ~isempty(f), cand{end+1} = f{1}; end
end
for c = 1:numel(cand)
    if isfile(cand{c}), mdd = cand{c}; break; end
end
o = mda_options();                                     %filter of the analysis (average beats)
filt = [o.medianFilterMs, o.meanFilterMs];
if ~isempty(I)
    kk = cellstr(string(I.key)); v = cellstr(string(I.value));
    x = str2double(v(strcmp(kk, 'option_medianFilterMs'))); if ~isempty(x) && ~isnan(x(1)), filt(1) = x(1); end
    x = str2double(v(strcmp(kk, 'option_meanFilterMs'))); if ~isempty(x) && ~isnan(x(1)), filt(2) = x(1); end
    x = v(strcmp(kk, 'option_noFiltering')); if ~isempty(x) && any(strcmpi(x{1}, {'1', 'true'})), filt = [0 0]; end
end
D = struct('C', C, 'Pr', Pr, 'G', G, 'E', E, 'Ov', Ov, 'zero', zero, 'mdd', mdd, 'filt', filt, 'start', rs);
cache.key{end+1} = key; cache.D{end+1} = D;
end


function C = standardContractions(C, pars)
% columns channel, clock, beatType, included, stimFrequency, peakToPeakFrequency and the parameters (NaN if missing)
if isempty(C) || ~all(ismember({'channel', 'clockTime'}, C.Properties.VariableNames))
    C = emptyContractions(pars); return;
end
T = table(double(C.channel), parseClock(C.clockTime), 'VariableNames', {'channel', 'clock'});
T.clockTime = cellstr(string(C.clockTime));
if ismember('beatType', C.Properties.VariableNames), T.beatType = cellstr(string(C.beatType));
else, T.beatType = repmat({''}, height(C), 1); end
T.beatType(strcmp(T.beatType, '<missing>')) = {''};
for f = unique([{'included', 'stimFrequency', 'peakToPeakFrequency', 't_stim', 't_onset', 't_peak', 'amplitude'}, ...
        pars(~strcmp(pars, 'beatsPerMinute'))], 'stable')
    if ismember(f{1}, C.Properties.VariableNames), T.(f{1}) = double(C.(f{1})) * parameterScale(f{1});
    else, T.(f{1}) = nan(height(C), 1); end
end
C = T;
end


function C = emptyContractions(pars)
C = table(zeros(0, 1), NaT(0, 1), cell(0, 1), cell(0, 1), 'VariableNames', {'channel', 'clock', 'clockTime', ...
    'beatType'});
for f = unique([{'included', 'stimFrequency', 'peakToPeakFrequency', 't_stim', 't_onset', 't_peak', 'amplitude'}, ...
        pars(~strcmp(pars, 'beatsPerMinute'))], 'stable')
    C.(f{1}) = zeros(0, 1);
end
end


function O = standardOverview(Ov, pars)
% 1-min values of the included contractions (extra beats excluded; several beat types: the one with most beats)
O = table(zeros(0, 1), NaT(0, 1), zeros(0, 1), 'VariableNames', {'channel', 'clock', 'nBeats'});
for i = 1:numel(pars), O.(pars{i}) = zeros(0, 1); end
if isempty(Ov) || ~all(ismember({'window', 'channel', 'included', 'nBeats'}, Ov.Properties.VariableNames)), return; end
inc = double(Ov.included) == 1;
if ismember('beatType', Ov.Properties.VariableNames)
    inc = inc & ~strcmp(cellstr(string(Ov.beatType)), 'extra');
end
Ov = Ov(inc, :);
if isempty(Ov), return; end
t = parseClock(Ov.window);
ch = double(Ov.channel); nb = double(Ov.nBeats);
[~, o] = sortrows([ch, datenum(t), -nb]); %#ok<DATNM>
ch = ch(o); t = t(o); nb = nb(o); Ov = Ov(o, :);
first = [true; ch(2:end) ~= ch(1:end-1) | t(2:end) ~= t(1:end-1)];
O = table(ch(first), t(first), nb(first), 'VariableNames', {'channel', 'clock', 'nBeats'});
for i = 1:numel(pars)
    if ismember(pars{i}, Ov.Properties.VariableNames)
        v = double(Ov.(pars{i})) * parameterScale(pars{i}); O.(pars{i}) = v(first);
    else
        O.(pars{i}) = nan(height(O), 1);
    end
end
end


function notes = windowNotes(D, c, a0, b0)
% protocols, periods without signal and user comments in the window [a0, b0)
notes = {};
for i = find(D.Pr.a < b0 & D.Pr.b > a0)'
    notes{end+1} = sprintf('protocol %s %s-%s', D.Pr.name{i}, hms(D.Pr.a(i)), hms(D.Pr.b(i))); %#ok<AGROW>
end
for i = find((D.G.channel == c | D.G.channel == 0) & D.G.a < b0 & D.G.b > a0)'
    notes{end+1} = sprintf('%s %s-%s', D.G.type{i}, hms(D.G.a(i)), hms(D.G.b(i))); %#ok<AGROW>
end
for i = find((D.E.channel == c | D.E.channel == 0) & D.E.t >= a0 & D.E.t < b0)'
    notes{end+1} = sprintf('comment %s %s', hms(D.E.t(i)), D.E.text{i}); %#ok<AGROW>
end
end


function tf = coverageGap(R, inR, a0, b0)
% a period of the window [a0, b0) between the recordings inR
tf = false;
s = sort(R.start(inR)); e = sort(R.stop(inR));
for i = 1:numel(s) - 1
    if s(i+1) > e(i) && s(i+1) > a0 && e(i) < b0, tf = true; return; end
end
end


function [s, regCache, sid] = sliceAt(res, R, series, c, t, regCache)
% number of the slice of the channel at time t and its sample ID (slice register of the experiment; NaN / '' if
% unknown)
s = nan; sid = '';
e = R.experiment;
if isempty(e), f = fullfile(res, 'mda_slices_root.csv');
else, q = strsplit(e, '/'); f = fullfile(res, q{:}, [q{end} '_slices.csv']); end
if ~isKey(regCache, f)
    T = [];
    if isfile(f)
        try
            o = detectImportOptions(f, 'Delimiter', ',', 'TextType', 'char', 'VariableNamingRule', 'preserve');
            o = setvartype(o, 'char');
            T = readtable(f, o);
        catch
            T = [];
        end
    end
    regCache(f) = T;
end
T = regCache(f);
if isempty(T) || ~all(ismember({'series', 'channel', 'slice', 'startTime', 'endTime'}, T.Properties.VariableNames))
    return;
end
k = find(strcmp(T.series, series) & str2double(T.channel) == c);
for i = k(:)'
    a = parseClock(T.startTime(i)); b = parseClock(T.endTime(i));
    if ~isnat(a) && ~isnat(b) && t >= a - seconds(60) && t <= b + seconds(60)
        s = str2double(T.slice{i});
        if ismember('sampleID', T.Properties.VariableNames)
            sid = strtrim(T.sampleID{i});
            if any(strcmpi(sid, {'NaN', '<missing>'})), sid = ''; end
        end
        return;
    end
end
end


function [pS, pC, pT, cache] = allChannels(pS, pC, pT, allCh, recs, offsets, sec, pars, cache)
% channels [] of a series: all channels with contractions in its windows
nS = {}; nC = []; nT = NaT(1, 0);
for p = 1:numel(pS)
    if ~allCh(p), nS{end+1} = pS{p}; nC(end+1) = pC(p); nT(end+1) = pT(p); continue; end %#ok<AGROW>
    R = recs.(fieldName(pS{p}));
    chs = [];
    for k = 1:numel(offsets)
        a0 = pT(p) + minutes(offsets(k)); b0 = a0 + seconds(sec);
        for j = find(R.start < b0 & R.stop > a0)'
            [D, cache] = recordingData(cache, R, j, pars);
            chs = union(chs, D.C.channel(D.C.clock >= a0 & D.C.clock < b0));
        end
    end
    for c = chs(:)'
        nS{end+1} = pS{p}; nC(end+1) = c; nT(end+1) = pT(p); %#ok<AGROW>
    end
end
pS = nS; pC = nC; pT = nT;
end


function u = parameterUnits(pars)
% units of the parameters (mda_parameters; beatsPerMinute 1/min)
D = mda_parameters();
u = cell(size(pars));
for i = 1:numel(pars)
    k = find(strcmp(D(:, 1), pars{i}), 1);
    if strcmp(pars{i}, 'beatsPerMinute'), u{i} = '1/min';
    elseif any(strcmp(pars{i}, {'dFdtMax', 'dFdtMin'})), u{i} = 'mN/s';     %uN/s of the analysis / 1000
    elseif isempty(k), u{i} = '';
    else, u{i} = D{k, 2}; end
end
end


function c = summaryColumns(pars)
% counts, note, per parameter mean and normalized value; then SD and SEM, median and quartiles, average beat
c = {'series', 'channel', 'sampleID', 'group', 'time', 'offset_min', 'from', 'to', 'recording', 'slice', 'nBeats', ...
    'nIncluded', 'nExtra', 'note'};
for i = 1:numel(pars), c = [c, {pars{i}, normName(pars{i})}]; end %#ok<AGROW>
for i = 1:numel(pars), c = [c, {[pars{i} '_SD'], [pars{i} '_SEM']}]; end %#ok<AGROW>
for i = 1:numel(pars), c = [c, {[pars{i} '_median'], [pars{i} '_q25'], [pars{i} '_q75']}]; end %#ok<AGROW>
c = [c, {'nAvgBeats', 'avgBeat_diastolic', 'avgBeat_amplitude'}];
end


function v = labelPerSeries(x, S, name)
% sample ID / group: one text for all series or one per series ('' = from the data)
nS = numel(S);
if isempty(x), v = repmat({''}, 1, nS); return; end
if ischar(x) || (isstring(x) && isscalar(x)), v = repmat({strtrim(char(x))}, 1, nS); return; end
if (iscell(x) || isstring(x)) && numel(x) == nS
    v = cellfun(@(y) strtrim(char(y)), cellstr(x(:)'), 'UniformOutput', false); return;
end
error('mda_timepoints: %s: one text or one per series expected.', name);
end


function s = seriesSample(series)
% sample ID from the name of the series: the part after the setup (Setup1_ABC000101 --> ABC000101)
t = regexp(series, '^[^_]+_(.+)$', 'tokens', 'once');
if isempty(t), s = series; else, s = t{1}; end
end


function [tf, cache] = signalGap(R, inR, cache, c, a0, b0, pars)
% a period without signal of channel c (chamber out, no signal, technical; gaps of the watcher) in [a0, b0)
tf = false;
for j = inR(:)'
    [D, cache] = recordingData(cache, R, j, pars);
    if any((D.G.channel == c | D.G.channel == 0) & D.G.a < b0 & D.G.b > a0), tf = true; return; end
end
end


function [v, cache, rawCache, notes] = signalForce(R, inR, cache, rawCache, ch, a0, b0, pars)
% median of the force of channel ch in [a0, b0) (raw signal of the recordings, filtered as in the analysis, minus the
% zero force of the channel: of the analysis, else of the log file); NaN without recording or zero force
v = nan; notes = {}; F = [];
for j = inR(:)'
    [D, cache] = recordingData(cache, R, j, pars);
    if isempty(D.mdd)
        notes{end+1} = sprintf('diastolic force without contractions: %s.mdd not found (option rawFolder)', ...
            R.name{j}); %#ok<AGROW>
        continue;
    end
    [H, rawCache] = rawHeader(rawCache, D.mdd);
    s0 = seconds(a0 - D.start); s1 = seconds(b0 - D.start);
    z = nan; if ch <= numel(D.zero), z = D.zero(ch); end            %zero force of the analysis (summary)
    if isnan(z), z = mda_zeroForce(H, ch, [], (s0 + s1) / 2); end   %channel without contractions: log file
    if isnan(z)
        notes{end+1} = sprintf('diastolic force without contractions: zero force of %s ch%d unknown', ...
            R.name{j}, ch); %#ok<AGROW>
        continue;
    end
    S = mda_readMdd(H, max(0, s0 - 1), s1 + 1);
    row = find(S.dataChannels == ch, 1);
    if isempty(row) && numel(S.dataChannels) == 1, row = 1; end
    if isempty(row) || numel(S.t) < 2, continue; end
    t = double(S.t(:)');
    [f, t] = filterSignal(double(S.force(row, :)), t, t(2) - t(1), D.filt);
    F = [F, f(t >= s0 & t < s1) - z]; %#ok<AGROW>
end
if ~isempty(F), v = median(F, 'omitnan'); end
end


function n = normName(p)
% column of the normalized value: <p>_pctBaseline; diastolicForce: change against the baseline (uN)
if strcmp(p, 'diastolicForce'), n = 'diastolicForce_delta'; else, n = [p '_pctBaseline']; end
end


function f = parameterScale(p)
% factor from the unit of the analysis to the unit of mda_timepoints (dF/dt: uN/s --> mN/s)
if any(strcmp(p, {'dFdtMax', 'dFdtMin'})), f = 1e-3; else, f = 1; end
end


function T = courseTemplate(pars)
T = table(cell(0, 1), zeros(0, 1), cell(0, 1), cell(0, 1), zeros(0, 1), zeros(0, 1), ...
    'VariableNames', {'series', 'channel', 'time', 'window', 'minutes', 'nBeats'});
for i = 1:numel(pars), T.(pars{i}) = zeros(0, 1); T.(normName(pars{i})) = zeros(0, 1); end
end


function s = joinNote(s, x)
if isempty(s), s = x; else, s = [s '; ' x]; end
end


function T = infoTable(TP, res, used)
% key, value: call, version and the recordings used
k = {'function'; 'version'; 'implementation'; 'analysisDate'; 'resultsFolder'; 'label'; 'sampleID'; 'group'; ...
    'time'; 'offsets_min'; ...
    'seconds'; 'baseline_min'; 'parameters'; 'units'; 'windows'; 'values'; 'pctBaseline'; 'averageBeats'; ...
    'alternans'; 'notes'; 'recordings'};
if isnan(TP.baseline), b = 'none'; else, b = num2str(TP.baseline); end
v = {'mda_timepoints'; mda_version(); 'MATLAB'; char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')); res; ...
    TP.label; strjoin(unique(TP.rows.sampleID, 'stable'), ' '); strjoin(unique(TP.rows.group, 'stable'), ' '); ...
    TP.time; strjoin(arrayfun(@num2str, TP.offsets, 'UniformOutput', false), ' '); num2str(TP.seconds); b; ...
    strjoin(TP.parameters, ' '); strjoin(strcat(TP.parameters, '=', TP.units), ' '); ...
    '[time + offset, time + offset + seconds), clock time of the peak'; ...
    ['mean (column <parameter>), SD, SEM (SD / sqrt(n)), median, q25, q75 of the included contractions; ' ...
    'beatsPerMinute = all contractions per minute; dFdtMax, dFdtMin in mN/s']; ...
    ['<parameter>_pctBaseline = 100 * mean / mean of the baseline window of the channel (same slice); ' ...
    'diastolicForce_delta = mean - mean of the baseline window (uN); course: the same with the 1-min medians and ' ...
    'the medians of the baseline window; no contractions (recorded, no gap): amplitude, AUC, dFdtMax, dFdtMin 0, ' ...
    'times NaN, diastolic force = median of the filtered signal - zero force']; ...
    ['mean of the included beats (no extra beats, no other contraction in the segment), aligned at the stimulus ' ...
    '(unpaced: onset), 0.1 s before to the next beat - 0.05 s, raw force of the recording - zero force (uN), ' ...
    'filtered as in the analysis; ' ...
    'norm_baselineAmplitude = (F - diastole of the baseline average beat) / its amplitude; norm_ownAmplitude = ' ...
    '(F - own diastole) / own amplitude + (own diastole - baseline diastole) / baseline amplitude; diastole = ' ...
    'mean of the 0.1 s before the stimulus; ..._SE = SD of the beats / sqrt(n)']; ...
    ['two amplitude groups of the included beats (1-D 2-means: each >= 20 %, means >= 20 % and >= 3 SD apart; ' ...
    'alternans if >= 80 % of successive beats switch, otherwise irregular amplitudes): note, average beats of the ' ...
    'small and the large beats']; strjoin(TP.notes, '; '); strjoin(used, '; ')};
T = table(k, v, 'VariableNames', {'key', 'value'});
end


function u = usedOf(used, series)
% recordings of these series
u = {};
for i = 1:numel(used)
    [~, n] = fileparts(used{i});
    if ismember(seriesInfo(n), series), u{end+1} = used{i}; end %#ok<AGROW>
end
end


function Te = subsetTP(TP, sel, nK)
% the rows sel (channels) of TP
Te = TP;
Te.rows = TP.rows(sel, :);
Te.time = clockText(min(parseClock(Te.rows.time)));
rs = repelem(sel(:), nK);
Te.summary = TP.summary(rs, :);
for i = 1:numel(TP.parameters)
    Te.matrix.(TP.parameters{i}) = TP.matrix.(TP.parameters{i})(sel, :);
    Te.pctBaseline.(TP.parameters{i}) = TP.pctBaseline.(TP.parameters{i})(sel, :);
end
key = @(T) strcat(T.series, '|', arrayfun(@num2str, T.channel, 'UniformOutput', false));
ks = key(Te.rows);
if ~isempty(TP.course), Te.course = TP.course(ismember(key(TP.course), ks), :); end
if ~isempty(TP.beats), Te.beats = TP.beats(ismember(key(TP.beats), ks), :); end
if ~isempty(TP.averageBeats), Te.averageBeats = TP.averageBeats(ismember(key(TP.averageBeats), ks), :); end
Te.averageBeatsMean = averageBeatsMean(Te.averageBeats, TP.offsets);
end


function files = writeFiles(d, base, TP, figs)
% <base>.xlsx (summary, matrix, course, beats, info) and the images
files = {};
x = fullfile(d, [base '.xlsx']);
deleteIfExists(x); deleteIfExists(fullfile(d, [base '_beats.csv']));
deleteIfExists(fullfile(d, [base '_averageBeats.csv']));
writetable(TP.summary, x, 'Sheet', 'summary');
writetable(matrixSheet(TP), x, 'Sheet', 'matrix');
writetable(TP.course, x, 'Sheet', 'course');
if height(TP.beats) > 1e6
    f = fullfile(d, [base '_beats.csv']);
    writetable(TP.beats, f);
    writetable(table({sprintf('%d rows: %s_beats.csv', height(TP.beats), base)}, 'VariableNames', {'note'}), x, ...
        'Sheet', 'beats');
    files{end+1} = f;
elseif isempty(TP.beats)
    writetable(table(cell(0, 1), 'VariableNames', {'series'}), x, 'Sheet', 'beats');
else
    writetable(TP.beats, x, 'Sheet', 'beats');
end
if height(TP.averageBeats) > 1e6
    f = fullfile(d, [base '_averageBeats.csv']);
    writetable(TP.averageBeats, f);
    writetable(table({sprintf('%d rows: %s_averageBeats.csv', height(TP.averageBeats), base)}, ...
        'VariableNames', {'note'}), x, 'Sheet', 'averageBeats');
    files{end+1} = f;
else
    writetable(TP.averageBeats, x, 'Sheet', 'averageBeats');
end
writetable(TP.averageBeatsMean, x, 'Sheet', 'averageBeatsMean');
writetable(TP.info, x, 'Sheet', 'info');
files = [{x}, files];
if ~figs, return; end
files = [files, writeFigures(d, base, TP, {'timepoints', 'course', 'averageBeats', 'averageBeatsMean', 'slides'})];
end


function files = writeFigures(d, base, TP, kinds)
% images (kinds: timepoints, course, averageBeats, averageBeatsMean, slides), each absolute (_abs) and normalized to
% the baseline window (_norm; not without baseline); files of the names of earlier versions (<base>_timepoints,
% _course, _averageBeats, _averageBeatsMean) are removed
files = {};
for g = {'timepoints', 'course', 'averageBeats', 'averageBeatsMean'}
    for e = {'.png', '.fig'}
        deleteIfExists(fullfile(d, [base '_' g{1} e{1}]));
        if isnan(TP.baseline), deleteIfExists(fullfile(d, [base '_' g{1} '_norm' e{1}])); end
    end
end
modes = {'abs', 'norm'};
if isnan(TP.baseline), modes = {'abs'}; end
for m = modes
    if ismember('timepoints', kinds)
        f1 = fullfile(d, [base '_timepoints_' m{1}]);
        saveFigure(timepointsFigure(TP, m{1}), f1);
        files = [files, {[f1 '.png'], [f1 '.fig']}]; %#ok<AGROW>
    end
    if ismember('course', kinds)
        f2 = fullfile(d, [base '_course_' m{1}]);
        saveFigure(courseFigure(TP, m{1}), f2);
        files = [files, {[f2 '.png'], [f2 '.fig']}]; %#ok<AGROW>
    end
end
if isempty(TP.averageBeats) || height(TP.averageBeats) == 0, return; end
for m = {'abs', 'norm'}                                %norm without baseline: own amplitude = 1 only
    if ismember('averageBeats', kinds)
        f3 = fullfile(d, [base '_averageBeats_' m{1}]);
        saveFigure(averageBeatsFigure(TP, m{1}), f3);
        files = [files, {[f3 '.png'], [f3 '.fig']}]; %#ok<AGROW>
    end
    if ismember('averageBeatsMean', kinds)
        f4 = fullfile(d, [base '_averageBeatsMean_' m{1}]);
        saveFigure(averageBeatsMeanFigure(TP, m{1}), f4);
        files = [files, {[f4 '.png'], [f4 '.fig']}]; %#ok<AGROW>
    end
end
if ~ismember('slides', kinds), return; end
% one 16:9 slide per channel (average beats +- SE and the values): averageBeats/<series>_ch<c>
ds = fullfile(d, 'averageBeats');
if ~isfolder(ds), mkdir(ds); end
AB = TP.averageBeats;
for i = 1:height(TP.rows)
    if ~any(strcmp(AB.series, TP.rows.series{i}) & AB.channel == TP.rows.channel(i)), continue; end
    f5 = fullfile(ds, sprintf('%s_ch%d', TP.rows.series{i}, TP.rows.channel(i)));
    saveFigure(channelSlide(TP, i), f5);
    files = [files, {[f5 '.png'], [f5 '.fig']}]; %#ok<AGROW>
end
end


function T = matrixSheet(TP)
% per parameter and measure (mean, pctBaseline; diastolicForce: delta) one row per channel, one column per
% offset
oc = arrayfun(@(o) sprintf('%+g min', o), TP.offsets, 'UniformOutput', false);
parts = {};
n = height(TP.rows);
for i = 1:numel(TP.parameters)
    nm = normName(TP.parameters{i});
    for m = {'mean', nm(numel(TP.parameters{i}) + 2:end)}
        if strcmp(m{1}, 'mean'), V = TP.matrix.(TP.parameters{i}); else, V = TP.pctBaseline.(TP.parameters{i}); end
        T = table(repmat(TP.parameters(i), n, 1), repmat(m, n, 1), TP.rows.series, TP.rows.channel, TP.rows.time, ...
            'VariableNames', {'parameter', 'measure', 'series', 'channel', 'time'});
        T = [T, array2table(V, 'VariableNames', oc)]; %#ok<AGROW>
        parts{end+1} = T; %#ok<AGROW>
    end
end
T = vertcat(parts{:});
end


% ---------------------------------------------------------------------------------------------------- figures
function h = timepointsFigure(TP, mode)
% per parameter over the windows, one line per channel (abs: mean +- SEM of the beats, units of the parameters;
% norm: pctBaseline, diastolicForce: change in uN), black = mean +- SEM of the channels
pars = TP.parameters; nP = height(TP.rows); nK = numel(TP.offsets);
[nr, nc] = grid(numel(pars));
h = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', 'Position', [1 1 4.2 * nc, 3.1 * nr + 0.6]);
col = lines(max(nP, 1));
lab = pairLabels(TP.rows);
isNorm = strcmp(mode, 'norm');
for i = 1:numel(pars)
    ax = subplot(nr, nc, i); hold(ax, 'on'); box(ax, 'on');
    if isNorm
        V = TP.pctBaseline.(pars{i}); E = nan(size(V));
    else
        V = TP.matrix.(pars{i}); E = reshape(TP.summary.([pars{i} '_SEM']), nK, nP)';
    end
    for p = 1:nP
        errorbar(ax, 1:nK, V(p, :), E(p, :), '-o', 'Color', col(p, :), 'MarkerFaceColor', col(p, :), ...
            'MarkerSize', 4, 'LineWidth', 0.8, 'CapSize', 3, 'DisplayName', lab{p});
    end
    if nP > 1                                          %mean +- SEM of the channels
        nv = sum(~isnan(V), 1); sv = std(V, 0, 1, 'omitnan') ./ sqrt(nv); sv(nv < 2) = nan;
        errorbar(ax, 1:nK, mean(V, 1, 'omitnan'), sv, 'LineStyle', 'none', 'Color', 'k', 'LineWidth', 1, ...
            'CapSize', 7, 'HandleVisibility', 'off');
        plot(ax, 1:nK, mean(V, 1, 'omitnan'), '-', 'Color', 'k', 'LineWidth', 2.2, 'DisplayName', 'mean +- SEM');
    end
    if isNorm, yline(ax, normRef(pars{i}), ':', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off'); end
    set(ax, 'XTick', 1:nK, 'XTickLabel', offsetLabels(TP.offsets), 'XLim', [0.6, nK + 0.4], 'FontSize', 8);
    ylabel(ax, axisLabel(pars{i}, TP.units{i}, isNorm), 'Interpreter', 'none');
    title(ax, unitTitle(pars{i}, TP.units{i}), 'FontWeight', 'normal', 'FontSize', 9, 'Interpreter', 'none');
    if i == 1 && nP <= 16, legend(ax, 'Location', 'best', 'FontSize', 6, 'Box', 'off', 'Interpreter', 'none'); end
end
if isNorm, w = ' - normalized to the baseline window'; else, w = ' - mean +- SEM of the beats'; end
sgtitle(h, [figureTitle(TP) w], 'FontSize', 10, 'Interpreter', 'none');
end


function h = courseFigure(TP, mode)
% per parameter the 1-min values relative to the treatment: 'abs' (units) or 'norm' (pctBaseline; diastolicForce:
% change in uN), one line per channel, black = mean +- SEM of the channels (shaded); windows
% grey, treatment dashed
pars = TP.parameters; nP = height(TP.rows);
[nr, nc] = grid(numel(pars));
h = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', 'Position', [1 1 4.2 * nc, 3.1 * nr + 0.6]);
col = lines(max(nP, 1));
lab = pairLabels(TP.rows);
isNorm = strcmp(mode, 'norm');
span = max(TP.offsets) + 30 + TP.seconds / 60 - (min(TP.offsets) - 30);
f = 1; xl = 'minutes after the treatment';
if span > 360, f = 60; xl = 'hours after the treatment'; end
C = TP.course;
for i = 1:numel(pars)
    ax = subplot(nr, nc, i); hold(ax, 'on'); box(ax, 'on');
    if isNorm, v = normName(pars{i}); else, v = pars{i}; end
    yy = [];
    for p = 1:nP
        s = strcmp(C.series, TP.rows.series{p}) & C.channel == TP.rows.channel(p);
        y = C.(v)(s);
        plot(ax, C.minutes(s) / f, y, '-', 'Color', col(p, :), 'LineWidth', 0.8, 'DisplayName', lab{p});
        yy = [yy; y(isfinite(y))]; %#ok<AGROW>
    end
    if nP > 1                                          %mean +- SEM of the channels (minutes rounded)
        [mx, my, ms] = courseMean(C, TP.rows, v);
        shade(ax, mx / f, my, ms, [0 0 0]);
        plot(ax, mx / f, my, '-', 'Color', 'k', 'LineWidth', 1.6, 'DisplayName', 'mean +- SEM');
    end
    if isempty(yy)
        yl = ylim(ax);
    else
        dy = max(yy) - min(yy);
        if dy == 0, dy = max(0.1 * abs(max(yy)), 1); end
        yl = [min(yy) - 0.05 * dy, max(yy) + 0.05 * dy];
    end
    for k = 1:numel(TP.offsets)
        x0 = TP.offsets(k) / f; x1 = (TP.offsets(k) + TP.seconds / 60) / f;
        w = max(x1 - x0, span / f / 300);
        hp = patch(ax, [x0 x0 + w x0 + w x0], yl([1 1 2 2]), [0.85 0.85 0.85], 'EdgeColor', 'none', ...
            'HandleVisibility', 'off');
        uistack(hp, 'bottom');
    end
    ylim(ax, yl);
    xline(ax, 0, '--', 'Color', [0.3 0.3 0.3], 'HandleVisibility', 'off');
    xlim(ax, [min(TP.offsets) - 30, max(TP.offsets) + 30 + TP.seconds / 60] / f);
    set(ax, 'FontSize', 8, 'Layer', 'top');
    xlabel(ax, xl);
    ylabel(ax, axisLabel(pars{i}, TP.units{i}, isNorm), 'Interpreter', 'none');
    title(ax, unitTitle(pars{i}, TP.units{i}), 'FontWeight', 'normal', 'FontSize', 9, 'Interpreter', 'none');
    if i == 1 && nP <= 16, legend(ax, 'Location', 'best', 'FontSize', 6, 'Box', 'off', 'Interpreter', 'none'); end
end
if isNorm, w = ', normalized to the baseline window'; else, w = ''; end
sgtitle(h, [figureTitle(TP) ' - 1-min values' w ', windows grey'], 'FontSize', 10, 'Interpreter', 'none');
end


function [x, y, e] = courseMean(C, rows, v)
% mean and SEM of the channels rows of the course column v per minute (minutes after the treatment rounded)
x = zeros(0, 1); y = x; e = x;
s = false(height(C), 1);
for p = 1:height(rows), s = s | (strcmp(C.series, rows.series{p}) & C.channel == rows.channel(p)); end
m = round(C.minutes(s)); val = C.(v)(s);
ok = isfinite(val);
if ~any(ok), return; end
[g, x] = findgroups(m(ok));
y = splitapply(@mean, val(ok), g);
n = splitapply(@numel, val(ok), g);
sd = splitapply(@(z) std(z), val(ok), g);
e = sd ./ sqrt(n); e(n < 2) = nan;
end


function y = normRef(p)
% value of 'no change' of the normalized parameter
if strcmp(p, 'diastolicForce'), y = 0; else, y = 100; end
end


function s = axisLabel(p, u, isNorm)
if ~isNorm, s = u;
elseif strcmp(p, 'diastolicForce'), s = 'change against the baseline (uN)';
else, s = '% of baseline'; end
end


function [nr, nc] = grid(n)
nc = min(3, n); nr = ceil(n / nc);
end


function lab = pairLabels(rows)
if ismember('label', rows.Properties.VariableNames), lab = rows.label; return; end   %mda_poolTimepoints
if numel(unique(rows.series)) == 1
    lab = arrayfun(@(c) sprintf('ch%d', c), rows.channel, 'UniformOutput', false);
else
    lab = arrayfun(@(i) sprintf('%s ch%d', rows.series{i}, rows.channel(i)), (1:height(rows))', 'UniformOutput', false);
end
end


function s = unitTitle(p, u)
if isempty(u), s = p; else, s = sprintf('%s (%s)', p, u); end
end


function s = figureTitle(TP)
if isfield(TP, 'title') && ~isempty(TP.title), s = TP.title; return; end            %mda_poolTimepoints
t = parseClock(TP.rows.time);
if min(t) == max(t), tt = clockText(min(t)); else, tt = sprintf('%s to %s', clockText(min(t)), hms(max(t))); end
s = sprintf('%s: treatment %s, %d channel(s), windows of %g s', TP.label, tt, height(TP.rows), TP.seconds);
if ~isnan(TP.baseline), L = offsetLabels(TP.baseline); s = sprintf('%s, baseline %s', s, L{1}); end
end


function L = offsetLabels(off)
% '-60 min', '+2 h', '+24 h'
L = cell(1, numel(off));
for i = 1:numel(off)
    o = off(i);
    if o ~= 0 && mod(o, 60) == 0, L{i} = sprintf('%+g h', o / 60); else, L{i} = sprintf('%+g min', o); end
    if o == 0, L{i} = '0 min'; end
end
end


function saveFigure(h, f)
% <f>.png (150 dpi) and <f>.fig (visible when opened)
set(h, 'PaperPositionMode', 'auto');
print(h, [f '.png'], '-dpng', '-r150');
set(h, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')');
savefig(h, [f '.fig']);
close(h);
end


% ---------------------------------------------------------------------------------------------------- average beats
function [grp, txt] = alternansGroups(x)
% two amplitude groups of the beats x (in time order; alternans or irregular): grp 1 = small, 2 = large, 0 = none
% (1-D 2-means of the amplitudes: each group >= 20 % of the beats, means >= 20 % of the larger and >= 3 SD apart);
% 'alternans' if >= 80 % of successive beats switch the group, otherwise 'irregular amplitudes'
x = x(:); grp = zeros(size(x)); txt = '';
ok = ~isnan(x); n = sum(ok);
if n < 10, return; end
v = sort(x(ok));
best = inf; kb = 0;
for k = 1:n - 1
    a = v(1:k); b = v(k+1:end);
    ss = sum((a - mean(a)) .^ 2) + sum((b - mean(b)) .^ 2);
    if ss < best, best = ss; kb = k; end
end
lo = ok & x <= v(kb); hi = ok & x > v(kb);
if ~any(hi), return; end
mlo = mean(x(lo)); mhi = mean(x(hi));
sd = sqrt(best / max(n - 2, 1));
fl = sum(lo) / n;
if min(fl, 1 - fl) < 0.2 || mhi - mlo < 0.2 * mhi || mhi - mlo < 3 * sd, return; end
grp(lo) = 1; grp(hi) = 2;
g = grp(ok);
sw = mean(g(2:end) ~= g(1:end-1));
if sw >= 0.8, kind = 'alternans: 2 amplitude groups'; else, kind = 'irregular amplitudes: 2 groups'; end
txt = sprintf('%s %.0f / %.0f uN (%d %% small beats, %d %% of successive beats switch)', kind, mlo, mhi, ...
    round(100 * fl), round(100 * sw));
end


function [T, st, notes, cache, rawCache] = pairAverageBeats(series, ch, Wb, offsets, kb, R, pars, cache, rawCache)
% average beats of one channel per window (Wb{k}: table j (recording), align (s in the file), tpeak, grp of the
% included beats): traces 'all', 'small beats', 'large beats' (alternans), force - zero force (uN) and normalized,
% each with its standard error (SD of the beats / sqrt(n))
nK = numel(offsets);
st = struct('n', zeros(1, nK), 'dia', nan(1, nK), 'amp', nan(1, nK));
notes = {}; T = abTemplate();
pre = 0.1; step = 0.002;
cyc = nan(1, nK);
for k = 1:nK
    W = Wb{k};
    if isempty(W) || height(W) < 2, continue; end
    dd = [];
    for j = unique(W.j)'
        a = sort(W.align(W.j == j & ~isnan(W.align)));
        dd = [dd; diff(a)]; %#ok<AGROW>
    end
    if ~isempty(dd), cyc(k) = median(dd); end
end
L = min(min(cyc, [], 'omitnan') - pre - 0.05, 4);
if isempty(L) || isnan(L) || L < 0.1, return; end
nPts = floor((L + pre) / step + 1e-9) + 1;
tg = -pre + (0:nPts - 1)' * step;
avg = cell(nK, 3); se = cell(nK, 3); nb = zeros(nK, 3);
for k = 1:nK
    W = Wb{k};
    if isempty(W), continue; end
    segs = zeros(nPts, 0); g = zeros(1, 0);
    for j = unique(W.j)'
        [D, cache] = recordingData(cache, R, j, pars);
        if isempty(D.mdd)
            notes{end+1} = sprintf('average beats: %s.mdd not found (option rawFolder)', R.name{j}); %#ok<AGROW>
            continue;
        end
        w = W(W.j == j & ~isnan(W.align), :);
        if isempty(w), continue; end
        z = nan; if ch <= numel(D.zero), z = D.zero(ch); end
        if isnan(z)
            z = 0;
            notes{end+1} = sprintf('average beats: zero force of %s ch%d unknown (force = sensor signal)', ...
                R.name{j}, ch); %#ok<AGROW>
        end
        [H, rawCache] = rawHeader(rawCache, D.mdd);
        S = mda_readMdd(H, max(0, min(w.align) - pre - 1), max(w.align) + L + 1);
        row = find(S.dataChannels == ch, 1);
        if isempty(row) && numel(S.dataChannels) == 1, row = 1; end
        if isempty(row) || isempty(S.t), continue; end
        t = double(S.t(:)');
        [F, t] = filterSignal(double(S.force(row, :)), t, t(2) - t(1), D.filt);   %as in the analysis
        pk = D.C.t_peak(D.C.channel == ch);
        for b = 1:height(w)
            a = w.align(b);
            if a - pre < t(1) || a + L > t(end), continue; end
            if any(abs(pk - w.tpeak(b)) > 1e-6 & pk > a - pre & pk < a + L), continue; end
            segs(:, end+1) = interp1(t, F, a + tg) - z; %#ok<AGROW>
            g(end+1) = w.grp(b); %#ok<AGROW>
        end
    end
    sets = {true(size(g)), g == 1, g == 2};
    for m = 1:3
        if any(sets{m}) && (m == 1 || any(g > 0))
            avg{k, m} = mean(segs(:, sets{m}), 2); nb(k, m) = sum(sets{m});
            if nb(k, m) > 1, se{k, m} = std(segs(:, sets{m}), 0, 2) / sqrt(nb(k, m));
            else, se{k, m} = nan(nPts, 1); end
        end
    end
end
ref = [];
if ~isempty(kb) && ~isempty(avg{kb, 1})
    y = avg{kb, 1}; d0 = mean(y(tg < 0)); ref = [d0, max(y) - d0];
end
labs = {'all', 'small beats', 'large beats'};
parts = {};
for k = 1:nK
    for m = 1:3
        y = avg{k, m};
        if isempty(y), continue; end
        d0 = mean(y(tg < 0)); a0 = max(y) - d0;
        if m == 1, st.n(k) = nb(k, 1); st.dia(k) = d0; st.amp(k) = a0; end
        e = se{k, m};
        %own amplitude = 1; the diastole keeps its change against the baseline (in baseline amplitudes)
        if isempty(ref)
            y2 = nan(nPts, 1); e2 = y2; y1 = (y - d0) / a0;
        else
            y2 = (y - ref(1)) / ref(2); e2 = e / ref(2); y1 = (y - d0) / a0 + (d0 - ref(1)) / ref(2);
        end
        parts{end+1} = table(repmat({series}, nPts, 1), repmat(ch, nPts, 1), repmat(offsets(k), nPts, 1), ...
            repmat(labs(m), nPts, 1), repmat(nb(k, m), nPts, 1), round(tg * 1e6) / 1e6, y, e, y2, e2, y1, e / a0, ...
            'VariableNames', abColumns()); %#ok<AGROW>
    end
end
if ~isempty(parts), T = vertcat(parts{:}); end
end


function [f, t] = filterSignal(x, t, dt, filt)
% moving median + moving mean (filt = [medianFilterMs meanFilterMs]) as mda_analyzeChannel; an even window delays the
% signal by dt/2: the time axis is corrected accordingly
f = x;
nMed = round(filt(1) / 1000 / dt);
nMean = round(filt(2) / 1000 / dt);
delay = 0;
if nMed > 1
    f = movmedian(f, nMed, 'omitnan', 'Endpoints', 'shrink');
    if mod(nMed, 2) == 0, delay = delay + dt / 2; end
end
if nMean > 1
    f = movmean(f, nMean, 'omitnan', 'Endpoints', 'shrink');
    if mod(nMean, 2) == 0, delay = delay + dt / 2; end
end
t = t - delay;
end


function [H, rawCache] = rawHeader(rawCache, f)
% file facts of a recording (read once)
i = find(strcmp(rawCache.file, f), 1);
if ~isempty(i), H = rawCache.H{i}; return; end
H = mda_readMdd(f);
rawCache.file{end+1} = f; rawCache.H{end+1} = H;
end


function c = abColumns()
c = {'series', 'channel', 'offset_min', 'trace', 'nBeats', 't_s', 'force_uN', 'force_SE_uN', ...
    'norm_baselineAmplitude', 'norm_baselineAmplitude_SE', 'norm_ownAmplitude', 'norm_ownAmplitude_SE'};
end


function T = abTemplate()
T = table(cell(0, 1), zeros(0, 1), zeros(0, 1), cell(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), 'VariableNames', abColumns());
end


function M = averageBeatsMean(AB, offsets)
% mean, SD and SE over the channels of the average beats (trace all) per window, common time axis (shortest beat):
% force (uN), baseline amplitude = 1, own amplitude = 1
v = {'force_uN', 'norm_baselineAmplitude', 'norm_ownAmplitude'};
names = [{'offset_min', 't_s', 'n'}, reshape([strcat(v, '_mean'); strcat(v, '_sd'); strcat(v, '_se')], 1, [])];
M = array2table(zeros(0, numel(names)), 'VariableNames', names);
if isempty(AB) || height(AB) == 0, return; end
A = AB(strcmp(AB.trace, 'all'), :);
keys = strcat(A.series, '|', arrayfun(@num2str, A.channel, 'UniformOutput', false));
parts = {};
for k = 1:numel(offsets)
    Ak = A(A.offset_min == offsets(k), :); kk = keys(A.offset_min == offsets(k));
    u = unique(kk, 'stable');
    if isempty(u), continue; end
    tmax = inf;
    for i = 1:numel(u), tmax = min(tmax, max(Ak.t_s(strcmp(kk, u{i})))); end
    t = Ak.t_s(strcmp(kk, u{1}) & Ak.t_s <= tmax + 1e-9);
    n = numel(u);
    T = table(repmat(offsets(k), numel(t), 1), t, repmat(n, numel(t), 1), 'VariableNames', names(1:3));
    for c = 1:numel(v)
        Y = nan(numel(t), n);
        for i = 1:n
            s = strcmp(kk, u{i}) & Ak.t_s <= tmax + 1e-9;
            Y(:, i) = Ak.(v{c})(s);
        end
        sd = nan(numel(t), 1);
        if n > 1, sd = std(Y, 0, 2, 'omitnan'); end
        T.([v{c} '_mean']) = mean(Y, 2, 'omitnan'); T.([v{c} '_sd']) = sd; T.([v{c} '_se']) = sd / sqrt(n);
    end
    parts{end+1} = T; %#ok<AGROW>
end
if ~isempty(parts), M = vertcat(parts{:}); end
end


function col = offsetColors(TP)
% colors of the windows: baseline black, the others in the order of the offsets
nK = numel(TP.offsets);
col = lines(max(nK, 2));
col = [col(2:end, :); col(1, :)];
if ~isnan(TP.baseline), col(TP.offsets == TP.baseline, :) = [0 0 0]; end
end


function t = abTitles()
t = {'force (uN)', 'baseline amplitude = 1, baseline diastole = 0', ...
    'own amplitude = 1, diastole: change in baseline amplitudes'};
end


function shade(ax, t, y, e, color)
% standard error as a band around y
if all(isnan(e)), return; end
e(isnan(e)) = 0;
patch(ax, [t; flipud(t)], [y - e; flipud(y + e)], color, 'FaceAlpha', 0.2, 'EdgeColor', 'none', ...
    'HandleVisibility', 'off');
end


function h = averageBeatsFigure(TP, mode)
% average beats +- SE per channel, one color per window, alternans: small and large beats dashed; mode 'abs': force
% (uN), one panel per channel; 'norm': one row per channel, baseline amplitude = 1 and own amplitude = 1 (diastole:
% change against the baseline; without baseline window: own amplitude only)
AB = TP.averageBeats;
keys = strcat(AB.series, '|', arrayfun(@num2str, AB.channel, 'UniformOutput', false));
rk = strcat(TP.rows.series, '|', arrayfun(@num2str, TP.rows.channel, 'UniformOutput', false));
rows = find(ismember(rk, keys));
nRow = numel(rows);
col = offsetColors(TP);
lab = pairLabels(TP.rows);
ttl = abTitles();
if strcmp(mode, 'abs')
    [nr, nc] = grid(nRow);
    h = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', 'Position', [1 1 4.2 * nc, 2.9 * nr + 0.7]);
    for r = 1:nRow
        ax = subplot(nr, nc, r);
        beatPanel(ax, TP, AB, strcmp(keys, rk{rows(r)}), 'force_uN', 'force_SE_uN', col, r == 1, 7);
        title(ax, sprintf('%s: %s', lab{rows(r)}, ttl{1}), 'FontWeight', 'normal', 'FontSize', 8, ...
            'Interpreter', 'none');
        if r > nRow - nc, xlabel(ax, 's after stimulus'); end
    end
else
    cs = [2 3];
    if isnan(TP.baseline), cs = 3; end
    nc = numel(cs);
    h = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', 'Position', [1 1 4.2 * nc + 0.8, 2.4 * nRow + 0.7]);
    ycol = {'force_uN', 'norm_baselineAmplitude', 'norm_ownAmplitude'};
    ecol = {'force_SE_uN', 'norm_baselineAmplitude_SE', 'norm_ownAmplitude_SE'};
    for r = 1:nRow
        for c = 1:nc
            ax = subplot(nRow, nc, (r - 1) * nc + c);
            beatPanel(ax, TP, AB, strcmp(keys, rk{rows(r)}), ycol{cs(c)}, ecol{cs(c)}, col, c == 1, 7);
            if c == 1, tt = sprintf('%s: %s', lab{rows(r)}, ttl{cs(c)}); else, tt = ttl{cs(c)}; end
            title(ax, tt, 'FontWeight', 'normal', 'FontSize', 8, 'Interpreter', 'none');
            if r == nRow, xlabel(ax, 's after stimulus'); end
        end
    end
end
sgtitle(h, [figureTitle(TP) ' - average beats +- SE (dashed: small / large beats of alternans)'], 'FontSize', 9, ...
    'Interpreter', 'none');
end


function beatPanel(ax, TP, AB, sel, ycol, ecol, col, withLegend, fs)
% average beats of the rows sel of AB per window: trace all +- SE (shaded), alternans groups dashed
hold(ax, 'on'); box(ax, 'on');
L = offsetLabels(TP.offsets);
for k = 1:numel(TP.offsets)
    for m = {'all', 'small beats', 'large beats'}
        s = sel & AB.offset_min == TP.offsets(k) & strcmp(AB.trace, m{1});
        if ~any(s), continue; end
        if strcmp(m{1}, 'all')
            shade(ax, AB.t_s(s), AB.(ycol)(s), AB.(ecol)(s), col(k, :));
            plot(ax, AB.t_s(s), AB.(ycol)(s), '-', 'Color', col(k, :), 'LineWidth', 1.2, ...
                'DisplayName', sprintf('%s (n=%d)', L{k}, AB.nBeats(find(s, 1))));
        else
            plot(ax, AB.t_s(s), AB.(ycol)(s), '--', 'Color', col(k, :), 'LineWidth', 0.7, 'HandleVisibility', 'off');
        end
    end
end
set(ax, 'FontSize', fs);
if withLegend, legend(ax, 'Location', 'best', 'FontSize', 6, 'Box', 'off', 'Interpreter', 'none'); end
end


function h = averageBeatsMeanFigure(TP, mode)
% mean +- SE over the channels: 'abs' force (uN); 'norm' baseline amplitude = 1 and own amplitude = 1 (without
% baseline window: own amplitude only)
M = TP.averageBeatsMean;
col = offsetColors(TP);
L = offsetLabels(TP.offsets);
ttl = abTitles();
ycol = {'force_uN', 'norm_baselineAmplitude', 'norm_ownAmplitude'};
if strcmp(mode, 'abs'), cs = 1; elseif isnan(TP.baseline), cs = 3; else, cs = [2 3]; end
h = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', 'Position', [1 1 4.75 * numel(cs), 3.8]);
for c = 1:numel(cs)
    ax = subplot(1, numel(cs), c); hold(ax, 'on'); box(ax, 'on');
    for k = 1:numel(TP.offsets)
        s = M.offset_min == TP.offsets(k);
        if ~any(s), continue; end
        t = M.t_s(s); y = M.([ycol{cs(c)} '_mean'])(s);
        shade(ax, t, y, M.([ycol{cs(c)} '_se'])(s), col(k, :));
        plot(ax, t, y, '-', 'Color', col(k, :), 'LineWidth', 1.3, 'DisplayName', ...
            sprintf('%s (n=%d)', L{k}, M.n(find(s, 1))));
    end
    set(ax, 'FontSize', 8);
    xlabel(ax, 's after stimulus');
    title(ax, ttl{cs(c)}, 'FontWeight', 'normal', 'FontSize', 9, 'Interpreter', 'none');
    if c == 1, legend(ax, 'Location', 'best', 'FontSize', 7, 'Box', 'off', 'Interpreter', 'none'); end
end
u = 'channels'; if isfield(TP, 'unitName'), u = TP.unitName; end      %mda_poolTimepoints: slices
sgtitle(h, [figureTitle(TP) ' - mean +- SE of the ' u], 'FontSize', 9, 'Interpreter', 'none');
end


function [head, rows] = slideTable(TP, i)
% rows of the value table of a channel slide: window, n, mean amplitude (% of baseline), diastolic force (change),
% TTP90 / TTR90 (% of baseline), note
S = TP.summary;
s = S(strcmp(S.series, TP.rows.series{i}) & S.channel == TP.rows.channel(i), :);
L = offsetLabels(TP.offsets);
names = {'amplitude', 'diastolicForce', 'TTP90', 'TTR90'};
heads = {'amplitude (uN)', 'diastolic force (uN)', 'TTP90 (ms)', 'TTR90 (ms)'};
use = ismember(names, TP.parameters);
names = names(use);
head = [{'window', 'n (avg. beat)'}, heads(use), {'note'}];
kb = [];
if ~isnan(TP.baseline), kb = find(TP.offsets == TP.baseline, 1); end
rows = cell(height(s), numel(head));
for k = 1:height(s)
    rows(k, 1:2) = {L{k}, sprintf('%d (%d)', s.nIncluded(k), s.nAvgBeats(k))};
    for q = 1:numel(names)
        v = s.(names{q})(k);
        f = 1; if any(strcmp(names{q}, {'TTP90', 'TTR90'})), f = 1000; end
        if isnan(v), txt = '-'; else, txt = sprintf('%.0f', v * f); end
        if ~isnan(v) && ~isempty(kb) && k ~= kb
            if strcmp(names{q}, 'diastolicForce')
                b = s.(names{q})(kb);
                if ~isnan(b), txt = sprintf('%s (%+.0f)', txt, v - b); end
            else
                pc = s.([names{q} '_pctBaseline'])(k);
                if ~isnan(pc), txt = sprintf('%s (%.0f %%)', txt, pc); end
            end
        end
        rows{k, 2 + q} = txt;
    end
    nt = s.note{k};
    if numel(nt) > 70, nt = [nt(1:67) '...']; end
    rows{k, end} = nt;
end
end


function x1 = beatEnd(AB, sel)
% end of the slide time axis: last time with > 5 % of the amplitude in any window + 30 %
x1 = -inf; tmax = -inf;
for o = unique(AB.offset_min(sel))'
    s = sel & AB.offset_min == o & strcmp(AB.trace, 'all');
    if ~any(s), continue; end
    t = AB.t_s(s); y = AB.force_uN(s);
    tmax = max(tmax, max(t));
    d0 = mean(y(t < 0)); a = max(y) - d0;
    j = find((y - d0) / a > 0.05, 1, 'last');
    if ~isempty(j), x1 = max(x1, t(j)); end
end
if isinf(x1), x1 = tmax; else, x1 = min(tmax, 1.3 * x1 + 0.05); end
end


function h = channelSlide(TP, i)
% 16:9 slide of one channel: average beats +- SE absolute (uN) and with the own amplitude = 1 (diastole: change against
% the baseline in baseline amplitudes), table of the values
AB = TP.averageBeats;
sel = strcmp(AB.series, TP.rows.series{i}) & AB.channel == TP.rows.channel(i);
h = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', 'Position', [0.5 0.5 13.333 7.5]);
col = offsetColors(TP);
L = offsetLabels(TP.offsets);
ttl = abTitles();
spec = {{'force_uN', 'force_SE_uN', ttl{1}, 'uN'}, {'norm_ownAmplitude', 'norm_ownAmplitude_SE', ttl{3}, ...
    'amplitude = 1'}};
x1 = 1000 * beatEnd(AB, sel);
for c = 1:2
    ax = axes(h, 'Position', [0.06 + (c - 1) * 0.49, 0.42, 0.42, 0.46]); hold(ax, 'on');
    for k = 1:numel(TP.offsets)
        for m = {'all', 'small beats', 'large beats'}
            s = sel & AB.offset_min == TP.offsets(k) & strcmp(AB.trace, m{1});
            if ~any(s), continue; end
            t = 1000 * AB.t_s(s); y = AB.(spec{c}{1})(s);
            if strcmp(m{1}, 'all')
                shade(ax, t, y, AB.(spec{c}{2})(s), col(k, :));
                plot(ax, t, y, '-', 'Color', col(k, :), 'LineWidth', 1.8, 'DisplayName', ...
                    sprintf('%s (n = %d)', L{k}, AB.nBeats(find(s, 1))));
            else
                plot(ax, t, y, '--', 'Color', col(k, :), 'LineWidth', 0.9, 'HandleVisibility', 'off');
            end
        end
    end
    if isfinite(x1), xlim(ax, [-100, x1]); end
    set(ax, 'FontSize', 10, 'Box', 'off', 'TickDir', 'out');
    xlabel(ax, 'ms after stimulus', 'FontSize', 11);
    ylabel(ax, spec{c}{4}, 'FontSize', 11);
    title(ax, spec{c}{3}, 'FontWeight', 'normal', 'FontSize', 12, 'Interpreter', 'none');
    if c == 1, legend(ax, 'Location', 'best', 'FontSize', 10, 'Box', 'off', 'Interpreter', 'none'); end
end
[head, rows] = slideTable(TP, i);
ax = axes(h, 'Position', [0.06 0.02 0.91 0.3], 'Visible', 'off'); hold(ax, 'on');
nc = numel(head); nr = size(rows, 1) + 1;
w = [1 1.2 ones(1, nc - 3) * 1.25 2.6]; xe = [0 cumsum(w)] / sum(w);
for r = 1:nr
    y = 1 - (r - 0.5) / max(nr, 6);
    if r == 1, patch(ax, [0 1 1 0], [1 1 1 - 1 / max(nr, 6) * [1 1]], [0.92 0.92 0.92], 'EdgeColor', 'none'); end
    for c = 1:nc
        if r == 1, txt = head{c}; else, txt = rows{r - 1, c}; end
        fw = 'normal'; cl = [0 0 0]; fs = 10;
        if r == 1 || c == 1, fw = 'bold'; end
        if r > 1 && c == 1, cl = col(r - 1, :); end
        if c == nc && r > 1, fs = 8; end
        text(ax, (xe(c) + xe(c + 1)) / 2, y, txt, 'HorizontalAlignment', 'center', 'FontSize', fs, ...
            'FontWeight', fw, 'Color', cl, 'Interpreter', 'none');
    end
    plot(ax, [0 1], (1 - r / max(nr, 6)) * [1 1], '-', 'Color', [0.75 0.75 0.75], 'LineWidth', 0.5);
end
xlim(ax, [0 1]); ylim(ax, [0 1]);
sgtitle(h, sprintf('%s ch%d - %s, treatment %s - average beats +- SE (windows of %g s; dashed: alternans groups)', ...
    TP.rows.series{i}, TP.rows.channel(i), TP.label, TP.rows.time{i}, TP.seconds), 'FontSize', 14, ...
    'Interpreter', 'none');
end


% ---------------------------------------------------------------------------------------------------- helpers
function T = resultTable(d, n, tab, cols, textCols)
% table tab of the results of recording n in folder d: sheet of <n>.xlsx or <n>_<tab>.csv(.gz) ([] if neither); the
% columns textCols (and all text, date and categorical columns) as text
if nargin < 5, textCols = {}; end
T = [];
x = fullfile(d, [n '.xlsx']);
if isfile(x)
    try
        if ismember(tab, sheetnames(x))
            o = detectImportOptions(x, 'Sheet', tab, 'VariableNamingRule', 'preserve');
            o.VariableNamesRange = 'A1'; o.DataRange = 'A2';
            o.SelectedVariableNames = intersect(cols, o.VariableNames, 'stable');
            for k = 1:numel(o.SelectedVariableNames)
                j = strcmp(o.VariableNames, o.SelectedVariableNames{k});
                if any(strcmp(o.VariableTypes{j}, {'string', 'datetime', 'categorical'})) || ...
                        ismember(o.SelectedVariableNames{k}, textCols)
                    o = setvartype(o, o.SelectedVariableNames{k}, 'char');
                end
            end
            T = readtable(x, o);
            return;
        end
    catch
    end
end
f = fullfile(d, [n '_' tab '.csv']);
src = f; tmp = '';
if ~isfile(f)
    if ~isfile([f '.gz']), return; end
    tmp = tempname; mkdir(tmp);
    gunzip([f '.gz'], tmp);
    [~, nn, e] = fileparts(f);
    src = fullfile(tmp, [nn e]);
end
try
    o = detectImportOptions(src, 'FileType', 'text', 'Delimiter', ',', 'VariableNamingRule', 'preserve');
    o.VariableNamesLine = 1; o.DataLines = [2 Inf];
    o.SelectedVariableNames = intersect(cols, o.VariableNames, 'stable');
    for k = 1:numel(o.SelectedVariableNames)
        j = strcmp(o.VariableNames, o.SelectedVariableNames{k});
        if any(strcmp(o.VariableTypes{j}, {'string', 'datetime', 'categorical'})) || ...
                ismember(o.SelectedVariableNames{k}, textCols)
            o = setvartype(o, o.SelectedVariableNames{k}, 'char');
        end
    end
    T = readtable(src, o);
catch
    T = [];
end
if ~isempty(tmp), rmdir(tmp, 's'); end
end


function t = parseClock(x)
% clock texts ('yyyy-mm-dd HH:MM:SS[.fff]', 'yyyy-mm-dd HH:MM', 'yyyy-mm-dd') or datetimes --> datetime column (NaT if
% not readable)
if isdatetime(x), t = x(:); return; end
if isnumeric(x), t = NaT(numel(x), 1); return; end
s = string(x); s = s(:);
s(ismissing(s)) = "";
s = strtrim(replace(s, "T", " "));
t = NaT(numel(s), 1);
t.Format = 'yyyy-MM-dd HH:mm:ss.SSS';
if isempty(s), return; end
c = cellstr(s);
k = ~cellfun(@isempty, regexp(c, '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(\.\d*)?$', 'once'));
if any(k)
    f = str2double(extractAfter(s(k), 19)); f(isnan(f)) = 0;
    t(k) = datetime(extractBefore(s(k), 20), 'InputFormat', 'yyyy-MM-dd HH:mm:ss') + seconds(f);
end
k = ~cellfun(@isempty, regexp(c, '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$', 'once'));
if any(k), t(k) = datetime(s(k), 'InputFormat', 'yyyy-MM-dd HH:mm'); end
k = ~cellfun(@isempty, regexp(c, '^\d{4}-\d{2}-\d{2}$', 'once'));
if any(k), t(k) = datetime(s(k), 'InputFormat', 'yyyy-MM-dd'); end
end


function s = clockText(t)
% 'yyyy-mm-dd HH:MM:SS' (milliseconds when not zero)
if isnat(t), s = ''; return; end
ms = round(mod(second(t), 1) * 1000);
if ms == 0 || ms == 1000
    s = char(datetime(dateshift(t, 'start', 'second', 'nearest'), 'Format', 'yyyy-MM-dd HH:mm:ss'));
else
    s = [char(datetime(dateshift(t, 'start', 'second'), 'Format', 'yyyy-MM-dd HH:mm:ss')) sprintf('.%03d', ms)];
end
end


function s = hms(t)
s = char(datetime(dateshift(t, 'start', 'second', 'nearest'), 'Format', 'HH:mm:ss'));
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


function deleteIfExists(f)
if isfile(f), delete(f); end
end
