%% MyoDishAnalysis - examples
% Add this folder to the MATLAB path once (or run the examples from within the folder):
%   addpath('/path/to/MyoDishAnalysis')
% The log file <name>_log.log written by the MyoDish software must be in the same folder as the .mdd file
% (sampling rate, number of channels, extended sensor mode, recording start).
% The recordings used here are the anonymized examples in the folder 'examples' (see examples/README.md).

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

ex = fullfile(fileparts(mfilename('fullpath')), 'examples');
mdd = fullfile(ex, 'example3_humanVentricle.mdd');    % human ventricle, force-frequency protocol 0.2-4 Hz, 8 channels
mddIso = fullfile(ex, 'example4_humanAtrium.mdd');    % human atrium, isoprenaline (channels 3, 4, 6, 8)

%% 1) Interactive: overview of the file, choose time window / range / single contractions, export
MyoDishAnalysisGUI(mdd)

%% 2) One channel, one time range (seconds in the file)
[contractions, summary] = MyoDishAnalysis(mdd, 6, 0, 120);
disp(contractions(1:5, :))
disp(summary(:, {'channel','nContractions','amplitude_mean','dFdtMax_mean','TTP90_mean','TTR90_mean','CD90_mean'}))

%% 3) Several channels, two ranges (baseline and drug), Excel output and control figures
[contractions, summary] = MyoDishAnalysis(mddIso, [2 3 6 8], [0 780], [60 870], ...
    'labels', {'baseline','iso'}, 'output', fullfile(tempdir, 'results.xlsx'), 'showFigures', true);
disp(summary(:, {'range','channel','nContractions','amplitude_mean','amplitude_SD'}))

%% 3b) Labels per channel (become columns of the tables): one value for all channels or one per channel
m = struct();
m.species = 'human';
m.sampleID = 'H01';
m.sliceID = {'S2','S3','S6','S8'};
m.sliceGroup = {'control','iso','iso','iso'};
m.tissue = 'RA';
m.treatment = {'none','isoprenaline','isoprenaline','isoprenaline'};
m.concentration = [0 100 100 100];       % number, for dose-response analyses
m.concentrationUnit = 'nM';
m.daysInCulture = 8;                     % or m.cultureStart = '1999-12-24 16:00' --> daysInCulture of every contraction
m.analyst = 'TS';
[contractions, summary] = MyoDishAnalysis(mddIso, [2 3 6 8], 780, 870, 'metadata', m);
disp(summary(:, {'channel','sliceID','sliceGroup','treatment','amplitude_mean'}))

%% 4) Manual detection threshold (uN) and only stimulated contractions
[contractions, summary] = MyoDishAnalysis(mdd, 6, 0, 120, 'threshold', 300, 'beats', 'stimulated');
disp(contractions(contractions.included, {'t_peak','amplitude','TTP90','TTR90'}))

%% 4b) Remove the periodic rocker artifact (contractions while the rocker moves); compare with rocker stops
%      (rabbit ventricle, rocker speed test 0-90 rpm, 1 Hz)
mddRocker = fullfile(ex, 'example1_rabbitVentricle.mdd');
[c0, s0] = MyoDishAnalysis(mddRocker, 5, 0, inf, 'rocker', 'stopped');
[c1, s1, info] = MyoDishAnalysis(mddRocker, 5, 0, inf, 'rockerFilter', true, 'rocker', 'moving');
disp(info.rockerFilter(:, {'channel','status','rockerFrequency_Hz','artifact_uN_peakToPeak','corrected_percentOfRockerOnTime'}))
disp([s0(:, {'nContractions','TTP90_mean','TTP90_SD','TTR90_mean','TTR90_SD'}); s1(:, {'nContractions','TTP90_mean','TTP90_SD','TTR90_mean','TTR90_SD'})])

%% 4c) Reference beat: mean shape +- SD of the contractions 0-120 s (e.g. baseline); compare the contractions of a
%      later range with it (refCorrelation, refRMSDeviation..., refMaxDeviation...; max. > 3 SD = deviating).
%      Aligned at the stimulus (latency counts); mda_referenceBeat('align', R, 'upstroke'): shape only.
S = mda_readMdd(mdd, 0, 125);
[B, C] = mda_analyzeChannel(S, 6, [0 120], mda_options());
R = mda_referenceBeat('create', C, B, find(B.included));
c = MyoDishAnalysis(mdd, 6, 400, 460, 'referenceBeat', R);
disp(c(:, {'t_peak','amplitude','refCorrelation','refRMSDeviationNorm_SD','refMaxDeviation_SD','refMaxDeviationNorm_SD'}))
disp(c(:, {'t_peak','amplitude_pctRef','CD90_pctRef','AUC_pctRef','diastolicForce_dRef'}))   %relative to the reference (% / uN)

%% 4d) Parallel sharp-electrode recording (LabChart .mat): alignment with the MyoDish stimuli, AP parameters
%      per contraction (rabbit ventricle, refractory period protocol). In the GUI: button '+ EP recording ...'.
mddEP = fullfile(ex, 'example8_rabbitVentricle_EP.mdd');
H = mda_readMdd(mddEP);
EP = mda_readEPRecording(strrep(mddEP, '.mdd', '.mat'), H);
disp(EP.align.method)
B = MyoDishAnalysis(mddEP, 1, 0, inf);
AP = mda_analyzeAP(EP, B);
fprintf('median APD90 %.1f ms (n = %d)\n', median(AP.APD90, 'omitnan'), sum(~isnan(AP.APD90)))

%% 5) Self test of the parameter calculation, the rocker filter and the reference beat (synthetic contractions)
mda_test
