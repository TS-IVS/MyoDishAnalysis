function mda_py_reference_files(dataDir, outDir, which)
%MDA_PY_REFERENCE_FILES  MATLAB results of the MyoDishAnalysis for the example recordings (reference for the Python port).
%
%   mda_py_reference_files(dataDir, outDir, which)
%
%   dataDir  folder with the example recordings (examples/ of the repository: .mdd + _log.log, LabChart .mat)
%   outDir   folder for the results (<case>.mat), py/tests/reference
%   which    case name(s): 'ex1' ... 'ex9', 'ex3ref', 'protocols' (cell or char)
%
% Every case saves the contraction and summary tables (table2struct, 'ToScalar'), the thresholds, rocker filter
% results, raw data of a short window (reader check), the overview and the log entries; the EP case also the alignment
% and the AP parameters (and the stimulus artefacts removed for the display). Compared by tests/test_matlab_reference.py.
%
% TS 2026-10-07 (cases: anonymized example recordings; before: lab recordings, 2026-10-06; ex3 'spec', ex8 epClean 2026-10-09)

if ischar(which), which = {which}; end
for w = which(:)'
    c = w{1};
    tic;
    R = struct();
    switch c
        case 'ex1'     % rabbit ventricle, rocker speed test 0-90 rpm, 1 Hz, 2022 log format (all channels in one line)
            mdd = fullfile(dataDir, 'example1_rabbitVentricle.mdd');
            R = runCLI(R, 'all', mdd, [], 0, inf, {});
            R = runCLI(R, 'rocker', mdd, [1 2 8], 0, inf, {'rockerFilter', true});
            R = readerCheck(R, mdd, 300, 330);
        case 'ex2'     % rabbit ventricle, pulse duration and stimulation threshold protocols (stimulus currents)
            mdd = fullfile(dataDir, 'example2_rabbitVentricle.mdd');
            R = runCLI(R, 'all', mdd, [], 0, inf, {});
            R = readerCheck(R, mdd, 500, 560);
        case 'ex3'     % human ventricle, force-frequency protocol, 8 channels, 15 min
            mdd = fullfile(dataDir, 'example3_humanVentricle.mdd');
            R = runCLI(R, 'all', mdd, [], 0, inf, {});
            R = runCLI(R, 'ranges', mdd, [3 6], [60 400], [120 460], {'labels', {'a', 'b'}, 'rocker', 'stopped', 'beats', 'stimulated'});
            R = runCLI(R, 'rocker', mdd, [], 0, inf, {'rockerFilter', true});
            R = runCLI(R, 'thr', mdd, 6, 100, 300, {'threshold', 300, 'downsampling', 1, 'medianFilterMs', 20, 'meanFilterMs', 10});
            R = runCLI(R, 'thrCh', mdd, [1 3 6], 100, 300, {'threshold', [NaN 300 NaN]});   %threshold per channel (NaN = auto)
            R = runCLI(R, 'spec', mdd, [], 0, inf, {'detection', 'specific'});   %uncertain contractions not counted
            R = readerCheck(R, mdd, 100, 160);
        case 'ex3ref'  % reference beat (channel 6, 0-120 s, 0.5 Hz) applied to the whole force-frequency protocol
            mdd = fullfile(dataDir, 'example3_humanVentricle.mdd');
            S = mda_readMdd(mdd, 0, 125);
            [B, C] = mda_analyzeChannel(S, 6, [0 120], mda_options());
            Rf = mda_referenceBeat('create', C, B, find(B.included));
            Rf.created = '';
            R.ref = Rf;
            R = runCLI(R, 'refStim', mdd, [3 6], 0, 900, {'referenceBeat', Rf});
            R = runCLI(R, 'refUp', mdd, 6, 0, 900, {'referenceBeat', mda_referenceBeat('align', Rf, 'upstroke')});
        case 'ex4'     % human atrium, isoprenaline, frequency protocol 30-300 bpm; two time ranges with labels
            mdd = fullfile(dataDir, 'example4_humanAtrium.mdd');
            R = runCLI(R, 'all', mdd, [], 0, inf, {});
            R = runCLI(R, 'ranges', mdd, [2 3 5 6], [0 780], [60 870], {'labels', {'baseline', 'iso'}});
            R = readerCheck(R, mdd, 50, 110);
        case 'ex5'     % pig ventricle, force-frequency protocol, 2022 log format
            mdd = fullfile(dataDir, 'example5_pigVentricle.mdd');
            R = runCLI(R, 'all', mdd, [], 0, inf, {});
            R = readerCheck(R, mdd, 200, 260);
        case 'ex6'     % rat ventricle, rocker speed test (30 / 60 bpm) and force-frequency protocol, 2022 log format
            mdd = fullfile(dataDir, 'example6_ratVentricle.mdd');
            R = runCLI(R, 'all', mdd, [], 0, inf, {});
            R = runCLI(R, 'rocker', mdd, [1 4 6], 0, 745, {'rockerFilter', true});
            R = runCLI(R, 'rockerThr', mdd, [1 4 6], 0, 745, {'rockerFilter', true, 'threshold', [NaN 200 NaN]});
            R = readerCheck(R, mdd, 1030, 1090);
        case 'ex7'     % pig ventricle, post-rest potentiation
            mdd = fullfile(dataDir, 'example7_pigVentricle.mdd');
            R = runCLI(R, 'all', mdd, [], 0, inf, {});
        case 'ex9'     % rat ventricle, single-channel file (2 channels incl. status), calibration 3000
            mdd = fullfile(dataDir, 'example9_ratVentricle.mdd');
            R = runCLI(R, 'all', mdd, [], 0, inf, {});
            R = readerCheck(R, mdd, 10, 70);
        case 'ex8'     % rabbit ventricle, sharp electrode (LabChart .mat): EP alignment and AP parameters
            mdd = fullfile(dataDir, 'example8_rabbitVentricle_EP.mdd');
            H = mda_readMdd(mdd);
            EP = mda_readEPRecording(strrep(mdd, '.mdd', '.mat'), H);
            A = EP.align;
            R.ep = struct('t0', EP.t0, 'dt', EP.dt, 'fs', EP.fs, 'block', EP.block, 'signalChannel', EP.signalChannel, ...
                'stimChannel', EP.stimChannel, 'nV', numel(EP.V), 'Vsum', sum(double(EP.V)), 'stimTimes', EP.stimTimes, ...
                'stimEnds', EP.stimEnds, 'stimAmplitude', EP.stimAmplitude, 'offset', A.offset, 'slope', A.slope, ...
                'method', A.method, 'nMatched', A.nMatched, 'nSE', A.nSE, 'nMdd', A.nMdd, 'mddChannel', A.mddChannel, ...
                'rms', A.rms, 'clockOffset', A.clockOffset, 'ambiguous', A.ambiguous, 'pairs', A.pairs, ...
                'candidates', A.candidates, 'check', {A.check}, 'info', {EP.info}, 'message', EP.message);
            ch = H.dataChannels(1);
            if numel(H.dataChannels) >= 8 && ~isnan(A.mddChannel), ch = A.mddChannel; end
            [B, ~] = MyoDishAnalysis(mdd, ch, 0, inf, 'quiet', true);
            [AP, ~] = mda_analyzeAP(EP, B);
            R.ap = table2struct([B(:, {'t_peak', 't_stim', 'beatType'}), AP], 'ToScalar', true);
            R.apChannel = ch;
            [Vc, RA] = mda_analyzeAP('removeArtefacts', EP);    %stimulus artefacts removed (display; 2026-10-09)
            kA = round((RA(:, 1) - EP.t0) / EP.dt) + 1; kB = round((RA(:, 2) - EP.t0) / EP.dt) + 1;
            seg = arrayfun(@(q) double(Vc(kA(q):kB(q))), 1:min(5, numel(kA)), 'UniformOutput', false);
            R.epClean = struct('R', RA, 'Vsum', sum(double(Vc)), 'nChanged', nnz(Vc ~= EP.V), 'segments', {seg});
            R = runCLI(R, 'all', mdd, [], 0, inf, {});
        case 'protocols'   % protocols found in the log files; analyses per protocol and group (mda_groupBeats)
            mdd = fullfile(dataDir, 'example3_humanVentricle.mdd');
            for k = 1:9
                d = dir(fullfile(dataDir, sprintf('example%d_*.mdd', k)));
                P = mda_protocols(fullfile(dataDir, d(1).name));
                R.(sprintf('list%d', k)) = table2struct(P, 'ToScalar', true);
            end
            ex = @(k) fullfile(dataDir, getfield(dir(fullfile(dataDir, sprintf('example%d_*.mdd', k))), 'name')); %#ok<GFLD>
            R = runCLI(R, 'ffr3', ex(3), [3 6], [], [], {'protocol', 'FFR'});
            R = runCLI(R, 'ffr4', ex(4), [3 6], [], [], {'protocol', 'FFR', 'rocker', 'any'});
            R = runCLI(R, 'rp8', ex(8), 1, [], [], {'protocol', 'RP', 'rocker', 'any'});
            R = runCLI(R, 'st2', ex(2), [3 5 7], [], [], {'protocol', 'ST', 'rocker', 'any'});
            R = runCLI(R, 'pd2', ex(2), 5, [], [], {'protocol', 'PD', 'rocker', 'any'});
            R = runCLI(R, 'prp7', ex(7), [1 3], [], [], {'protocol', 'PRP'});
            R = runCLI(R, 'prp7any', ex(7), 3, [], [], {'protocol', 'PRP', 'rocker', 'any'});
            R = runCLI(R, 'rocker1', ex(1), 5, [], [], {'protocol', 'rockerSpeed'});
            R = runCLI(R, 'all6', ex(6), [1 6], [], [], {'protocol', 'all'});
            R = runCLI(R, 'log2', ex(2), 5, 60, 330, {'groupBy', 'log:dechargeDuration', 'rocker', 'any'});
        otherwise
            error('mda_py_reference_files: unknown case ''%s''.', c);
    end
    [~, n, e] = fileparts(mdd);
    R.case = c; R.mdd = [n e]; R.seconds = toc;
    save(fullfile(outDir, [c '.mat']), 'R', '-v7');
    fprintf('%s: %.1f s\n', c, R.seconds);
end
end


function R = runCLI(R, key, mdd, ch, a, b, args)
[T, S, info] = MyoDishAnalysis(mdd, ch, a, b, 'quiet', true, args{:});
if ismember('clockTime', T.Properties.VariableNames)
    T.clockTime = datenum(T.clockTime);    %exact in .mat
end
X = struct('contractions', table2struct(T, 'ToScalar', true), 'summary', table2struct(S, 'ToScalar', true), ...
    'thresholds', table2struct(info.thresholds, 'ToScalar', true), 'notes', {info.notes}, ...
    'recordingStart', info.recordingStart, 'samplingRate', info.samplingRate, 'nChannelsInFile', info.nChannelsInFile, ...
    'dataChannels', info.dataChannels, 'totalSeconds', info.totalSeconds, 'offsetLog', info.offsetLog, ...
    'calibrationLog', info.calibrationLog, 'rockerSpeedLog', info.rockerSpeedLog, ...
    'extendedSensorIntervals', info.extendedSensorIntervals, 'args', {args(1:2:end)});
if isfield(info, 'rockerFilter') && height(info.rockerFilter) > 0
    X.rockerFilter = table2struct(info.rockerFilter, 'ToScalar', true);
end
if isfield(info, 'protocolResults') && height(info.protocolResults) > 0
    X.protocolResults = table2struct(info.protocolResults, 'ToScalar', true);
end
R.(key) = X;
end


function R = readerCheck(R, mdd, a, b)
S = mda_readMdd(mdd, a, b);
R.reader = struct('t', S.t, 'force', S.force, 'rockerOn', double(S.rockerOn), 'stimTime', S.stim.time, ...
    'stimChannel', S.stim.channel, 'stimCurrent', S.stim.current, 'currentReached', double(S.stim.currentReached), ...
    'fromSeconds', S.fromSeconds, 'toSeconds', S.toSeconds, 'notes', {S.notes});
O = mda_readMdd(mdd, 'overview', 2);
R.overview = struct('tBin', O.tBin, 'minForce', O.minForce, 'maxForce', O.maxForce, 'rockerFraction', O.rockerFraction);
E = mda_logEntries(S.logFile);
E.clockTime = datenum(E.clockTime);
R.log = table2struct(E, 'ToScalar', true);
end
