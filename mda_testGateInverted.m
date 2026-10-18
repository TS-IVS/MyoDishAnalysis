function ok = mda_testGateInverted()
%MDA_TESTGATEINVERTED  Test of the longer onset gate of certain contractions and of inverted signals with a synthetic
%recording (9 channels, 400 Hz, 320 s; pacing 0.5 Hz, 50 mA in channels 1-3).
%
%   ok = mda_testGateInverted()   prints the single checks, returns true if all pass
%
%   ch1  twitch 30 ms after every pulse                 stimulated, amplitude 1000 (filtered ~930)
%   ch2  twitch 300 ms after every pulse (long delay)   stimulated (gateMaxCertain 0.5 s); all extra with 0.15 s
%   ch3  inverted twitch 30 ms after every pulse        invertedSignal, force parameters NaN, rate and capture
%   ch4  noise only; analysis report (mda_report): ch2 delay and ch3 inverted to check
%   ch5  rocker waves downwards (400 uN, 3 per stimulus interval) partly in phase with the pulses (phase at the pulse
%        0 +- 2.5 rad): the median falls after the pulses (suspicion), but the detection in the negated signal finds
%        no certain stimulated contraction: not inverted (invertedMinCapture; 2026-10-12)
% Twitch: raised cosine rise in 0.1 s, exponential relaxation (0.12 s). Pendant of py/tests/test_gate_inverted.py
% (same recording and checks).
% Arrhythmic pacing (2026-10-13; second recording, 3 channels, 600 s, noise only): ch1 paced arrhythmically (mean 4 Hz,
% interval CV ~29 %), ch2 1 Hz with variable pacing during an FFR protocol of the log file (100-500 s), ch3 1 Hz.
%
% TS 2026-10-11 (arrhythmic pacing 2026-10-13)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

ok = true;
T = 320; fs = 400;
pulses = 10:2:308;
folder = tempname; mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's')); %#ok<NASGU>
f = fullfile(folder, 'gate_rigA_0.mdd');
writeRecording(f, T, fs, pulses);
[C, S] = MyoDishAnalysis(f, 1:3, 0, T, 'quiet', true);
nP = numel(pulses);
pass = true;
for ch = 1:3
    b = C.beatType(C.channel == ch);
    pass = pass && sum(strcmp(b, 'stimulated')) >= nP - 1 && ~any(strcmp(b, 'extra'));
end
ok = check(ok, 'channels 1-3: every twitch stimulated, no extra beats', pass);
c1 = C(C.channel == 1, :); c2 = C(C.channel == 2, :); c3 = C(C.channel == 3, :);
a1 = median(c1.amplitude, 'omitnan'); a2 = median(c2.amplitude, 'omitnan');
ok = check(ok, 'delayed twitch: same amplitude (diastolic level before the onset), not inverted', ...
    a1 > 900 && abs(a2 / a1 - 1) < 0.01 && ~any(c1.invertedSignal) && ~any(c2.invertedSignal));
ok = check(ok, 'delay 300 ms: stimToOnset +270 ms, stimToRise50 350 / 80 ms', ...
    abs(median(c2.stimToOnset, 'omitnan') - median(c1.stimToOnset, 'omitnan') - 0.27) < 0.01 && ...
    abs(median(c2.stimToRise50, 'omitnan') - 0.35) < 0.01 && abs(median(c1.stimToRise50, 'omitnan') - 0.08) < 0.01);
ok = check(ok, 'inverted: flagged, force parameters NaN, rate 0.5 Hz', ...
    all(c3.invertedSignal) && all(isnan(c3.amplitude)) && all(isnan(c3.TTP90)) && all(isnan(c3.stimToRise50)) && ...
    abs(median(c3.peakToPeakFrequency, 'omitnan') - 0.5) < 0.01);
s3 = S(S.channel == 3, :);
ok = check(ok, 'summary: invertedSignal only in channel 3, no missed beats, amplitude NaN', ...
    all(s3.invertedSignal) && sum(s3.nMissedBeats) <= 1 && isnan(s3.amplitude_mean(1)) && ...
    ~any(S.invertedSignal(S.channel ~= 3)));
C15 = MyoDishAnalysis(f, 2, 0, T, 'quiet', true, 'gateMaxCertain', 0.15);
ok = check(ok, 'gateMaxCertain 0.15 s: the delayed twitches are extra beats', ~any(strcmp(C15.beatType, 'stimulated')));
C0 = MyoDishAnalysis(f, 3, 0, T, 'quiet', true, 'invertedCheck', false);
ok = check(ok, 'invertedCheck false: channel 3 not flagged', isempty(C0) || ~any(C0.invertedSignal));
% rocker waves partly in phase with the pulses (ch5): suspected, but no certain stimulated contraction in the negated
% signal: analysed as it is; option invertedMinCapture (2026-10-12; as test_gate_inverted.py)
[C, S] = MyoDishAnalysis(f, [3 5], 0, T, 'quiet', true);
C0 = MyoDishAnalysis(f, 5, 0, T, 'quiet', true, 'invertedCheck', false);
[~, S1] = MyoDishAnalysis(f, 5, 0, T, 'quiet', true, 'invertedMinCapture', 0);
[~, S2] = MyoDishAnalysis(f, 3, 0, T, 'quiet', true, 'invertedMinCapture', 1.01);
c5 = C(C.channel == 5, :);
ok = check(ok, 'rocker waves partly in phase: not inverted (confirmation by the detection in the negated signal)', ...
    all(S.invertedSignal(S.channel == 3)) && ~any(S.invertedSignal(S.channel == 5)) && height(c5) == height(C0) && ...
    isequaln(c5.amplitude, C0.amplitude) && all(S1.invertedSignal) && ~any(S2.invertedSignal));
% analysis report (mda_report, 2026-10-11): ch2 delay (red D), ch3 inverted (red I), ch4 without contractions
out = fullfile(folder, 'res.csv');
[C, S, info] = MyoDishAnalysis(f, 1:4, 0, T, 'quiet', true, 'output', out);
R = mda_report('flags', S, C);
ok = check(ok, 'report: written with output, flags D (delay) and I (inverted)', ...
    isfile(fullfile(folder, 'res_report.pdf')) && isequal(R.flags', {'', 'D', 'I', ''}) && ...
    isequal(R.level', {'', 'check', 'check', 'few beats'}) && strcmp(R.red{2}, 'delay 315 ms') && ...
    strcmp(R.red{3}, 'inverted signal'));
R2 = mda_report('analysis', fullfile(folder, 'x.pdf'), f, C, S, info, out);
ok = check(ok, 'report: commands that open the GUI at the channel and window', ...
    strcmp(R2.matlab{2}, sprintf('MyoDishAnalysisGUI(''%s'', ''channel'', 2, ''window'', [149 169])', out)) && ...
    strcmp(R2.python{3}, sprintf('mda-gui "%s" --channel 3 --window 149 169', out)));
Ra = mda_report('flags', S, C, [], struct('amplitude', 1000));
ok = check(ok, 'report: flags as options, report file names', isequal(Ra.flags(1:2)', {'A', 'DA'}) && ...
    strcmp(mda_report('path', fullfile('a', 'res.xlsx')), fullfile('a', 'res_report.pdf')) && ...
    isempty(mda_report('path', 'res.csv', false)) && isempty(mda_report('path', '')) && ...
    strcmp(mda_report('path', '', 'r.pdf'), 'r.pdf') && strcmp(mda_report('path', 'r.txt', 'on'), 'r.txt_report.pdf'));
MyoDishAnalysis(f, 1, 0, 60, 'quiet', true, 'output', fullfile(folder, 'n.csv'), 'report', false);
ok = check(ok, 'report false: no report', ~isfile(fullfile(folder, 'n_report.pdf')));
% channel label and amplitude change with its time span (2026-10-12; as test_gate_inverted.py)
k = (0:23)';
mk = @(c, a1, da, x, tr, conc, grp) table(repmat(c, 24, 1), 3600 * k, 3600 * (k + 1), repmat(100, 24, 1), ...
    repmat(100, 24, 1), zeros(24, 1), repmat(x, 24, 1), zeros(24, 1), repmat(100, 24, 1), a1 + da * k / 23, ...
    repmat(0.1, 24, 1), repmat({tr}, 24, 1), repmat(conc, 24, 1), repmat({'nM'}, 24, 1), repmat({grp}, 24, 1), ...
    repmat({''}, 24, 1), 'VariableNames', {'channel', 'from', 'to', 'nDetected', 'nStimuli', 'nMissedBeats', ...
    'nExtraBeats', 'nUncertain', 'nContractions', 'amplitude_mean', 'amplitude_CV', 'treatment', 'concentration', ...
    'concentrationUnit', 'sliceGroup', 'sampleGroup'});
SL = [mk(1, 100, 660, 0, 'PMA', 100, ''); mk(2, 300, 0, 30, '', NaN, 'control'); mk(3, 300, 0, 0, '', NaN, '')];
RL = mda_report('flags', SL);
ok = check(ok, 'report: channel labels, amplitude change +660 % over 24 h', ...
    isequal(RL.label', {'PMA 100 nM', 'control', ''}) && strcmp(RL.yellow{1}, 'amplitude change +660 % over 24 h') && ...
    abs(RL.amplitudeChange_hours(1) - 24) < 1e-9 && strcmp(RL.yellow{2}, 'extra beats 30 %') && ...
    isequal(RL.flags', {'T', 'X', ''}));
SI = table([1; 1], [0; 3600], [3600; 7200], [60; 9940], [60; 9940], [0; 0], [0; 0], [0; 0], [60; 9940], [NaN; 300], ...
    [0.1; 0.1], [true; false], 'VariableNames', {'channel', 'from', 'to', 'nDetected', 'nStimuli', 'nMissedBeats', ...
    'nExtraBeats', 'nUncertain', 'nContractions', 'amplitude_mean', 'amplitude_CV', 'invertedSignal'});
RI = mda_report('flags', SI);
ok = check(ok, 'report: inverted signal in < 1 % of the contractions', ...
    strcmp(RI.red{1}, 'inverted signal (< 1 % of the contractions)'));
% noise index N, large extra beats S, extra beats as slice quality (2026-10-12; as test_gate_inverted.py)
sr = @(ch, stimuli, miss, extra, unc) table(ch, 0, 3600, 1000, stimuli, miss, extra, unc, 1000, 300, 0.1, ...
    'VariableNames', {'channel', 'from', 'to', 'nDetected', 'nStimuli', 'nMissedBeats', 'nExtraBeats', 'nUncertain', ...
    'nContractions', 'amplitude_mean', 'amplitude_CV'});
SN = [sr(1, 1000, 450, 0, 980); sr(2, 1000, 10, 20, 900); sr(3, 0, 0, 0, 400); sr(4, 1000, 500, 300, 50); ...
    sr(5, 1000, 0, 100, 0); sr(6, 1000, 50, 150, 240)];
kk = (0:999)'; bt = repmat({'stimulated'}, 1000, 1); bt(mod(kk, 10) == 0) = {'extra'};
am = repmat(400, 1000, 1); am(mod(kk, 10) == 0) = 5000;
CN = table(repmat(5, 1000, 1), kk, bt, false(1000, 1), true(1000, 1), repmat(0.03, 1000, 1), am, 'VariableNames', ...
    {'channel', 't_peak', 'beatType', 'uncertain', 'included', 'stimToOnset', 'amplitude'});
RN = mda_report('flags', SN, CN);
RN10 = mda_report('flags', SN, CN, [], struct('uncertain', 10));
[wa, wb] = mda_report('window', CN, 5, 'S', 20);
ok = check(ok, 'report: noise index N, large extra beats S, extra beats yellow (as in Python)', ...
    isequal(RN.flags', {'NC', '', 'N', 'CX', 'S', 'X'}) && ...
    strcmp(RN.red{1}, 'noise index 44 (uncertain 98 %, extra 0 %, missed 45 %)') && ...
    strcmp(RN.red{3}, 'noise index 40 (uncertain 40 %, unpaced)') && strcmp(RN.yellow{4}, 'capture 50 %, extra beats 30 %') && ...
    strcmp(RN.red{5}, 'large extra beats 10 % (12.5 x the paced amplitude)') && abs(RN.noiseIndex(2) - 2.7) < 1e-9 && ...
    isequal(RN.level', {'check', '', 'check', 'quality', 'check', 'quality'}) && wa == 0 && wb == 20 && ...
    strcmp(RN10.flags{6}, 'N'));
% arrhythmic pacing (2026-10-13; as test_gate_inverted.py): detected from the stim-to-stim variability outside the
% stimulation protocols, or set by arrhythmicChannels
T2 = 600;
f = fullfile(folder, 'arr_rigA_0.mdd');
writeArrhythmic(f, T2, fs, true);
[~, S] = MyoDishAnalysis(f, 1:3, 0, T2, 'quiet', true);
v = S.Properties.VariableNames; k = find(strcmp(v, 'stimFrequency'));
ok = check(ok, 'arrhythmic pacing: ch1 detected, ch2 not (FFR protocol excluded), summary columns', ...
    isequal(v(k:k+5), {'stimFrequency', 'stimVariability_percent', 'arrhythmicFraction', 'pacedSeconds', ...
    'arrhythmicPacing', 'detectionThreshold'}) && isequal(S.arrhythmicPacing', [true false false]) && ...
    isequal(S.pacedSeconds', [120 120 120]) && isequal(S.arrhythmicFraction', [1 0 0]) && ...
    S.stimVariability_percent(1) > 25 && S.stimVariability_percent(1) < 33 && S.stimVariability_percent(2) < 1);
[~, Sa] = MyoDishAnalysis(f, 1:3, 0, T2, 'quiet', true, 'arrhythmicDetection', false, 'arrhythmicChannels', '3');
[~, Sb] = MyoDishAnalysis(f, 1:3, 0, T2, 'quiet', true, 'arrhythmicMinFraction', 1);
[~, Sp] = MyoDishAnalysis(f, 2, [], [], 'quiet', true, 'protocol', 'FFR', 'arrhythmicChannels', 2);
f2 = fullfile(folder, 'arr_rigB_0.mdd');
writeArrhythmic(f2, T2, fs, false);                %without the protocol in the log: ch2 variable during 400 of 600 s
[~, Sc] = MyoDishAnalysis(f2, 1:3, 0, T2, 'quiet', true);
ok = check(ok, 'arrhythmic pacing: options, without protocol ch2 arrhythmic, protocol analysis', ...
    isequal(Sa.arrhythmicPacing', [false false true]) && ~any(Sb.arrhythmicPacing) && ...
    isequal(Sc.arrhythmicPacing', [true true false]) && isequal(Sc.pacedSeconds', [T2 T2 T2]) && ...
    all(Sp.arrhythmicPacing));
% report: arrhythmic pacing without C, V and missed beats in the noise index; red F above stimFrequency
ra = @(ch, arr, fr) table(ch, 0, 3600, 1000, 2000, 1200, 20, 300, 1000, 300, 0.5, fr, {arr}, 'VariableNames', ...
    {'channel', 'from', 'to', 'nDetected', 'nStimuli', 'nMissedBeats', 'nExtraBeats', 'nUncertain', ...
    'nContractions', 'amplitude_mean', 'amplitude_CV', 'stimFrequency', 'arrhythmicPacing'});
SA = [ra(1, 'false', 5); ra(2, 'true', 5); ra(3, 'false', 50); ra(4, 'True', 50)];
RA = mda_report('flags', SA);
RA2 = mda_report('flags', SA, [], [], struct('uncertain', 20, 'irregular', 1));
RA3 = mda_report('flags', SA, [], [], struct('stimFrequency', 60));
ok = check(ok, 'report: arrhythmic pacing (no C, V), F above 10 Hz (as in Python)', ...
    isequal(RA.flags', {'NCV', '', 'NFCV', 'F'}) && isequal(RA.level', {'check', '', 'check', 'check'}) && ...
    RA.extraMissed_percent(2) == 2 && RA.capture_percent(2) == 40 && RA.arrhythmicPacing(2) && ...
    strcmp(RA.red{4}, 'stimulus frequency 50 Hz') && RA.stimFrequency_Hz(1) == 5 && ...
    strcmp(RA2.red{2}, 'noise index 1 (uncertain 30 %, extra 2 %, arrhythmic pacing)') && ...
    isequal(RA3.flags', {'NCV', '', 'NCV', ''}));

% stimulation > 10 Hz (2026-10-18): status channel misread, technical error, no contraction included (as in Python)
f3 = fullfile(folder, 'fast_rigA_0.mdd');
writeFastStimulation(f3, fs);
[C3, S3, I3] = MyoDishAnalysis(f3, [1 2], 0, 60, 'quiet', true);
nt = I3.notes; if ~iscell(nt), nt = cellstr(nt); end
ok = check(ok, 'stimulation > 10 Hz: no contraction included, parameters NaN, note; 1 Hz unchanged', ...
    S3.nContractions(1) == 56 && abs(S3.stimFrequency(1) - 1) < 1e-9 && S3.amplitude_mean(1) > 800 && ...
    S3.nContractions(2) == 0 && abs(S3.stimFrequency(2) - 20) < 1e-6 && isnan(S3.amplitude_mean(2)) && ...
    ~any(C3.included(C3.channel == 2)) && sum(C3.channel == 2) >= 50 && ...
    any(contains(nt, ['channel 2: stimulation > 10 Hz (status channel misread): technical error, contractions ' ...
    'not included'])));
end


function [p1, p2, p3] = arrhythmicPulses(T2, fs)
% pulse times of ch1 (arrhythmic: intervals 0.25 s x (1 + 0.5 u_i), u_i in [-1, 1] plastic number sequence), ch2 (1 Hz;
% 100-500 s steps of 20 s at 1, 2, 3 Hz), ch3 (1 Hz); samples 4k, 4k + 1, 4k + 2 (one pulse per sample of the status
% channel)
i = 1:2399;
iv = 0.25 * (1 + 0.5 * (2 * mod(i * 0.7548776662466927, 1) - 1));
p1 = 5 + cumsum(iv);
p1 = 4 * round(p1(p1 < T2 - 5) * fs / 4) / fs;
p2 = 5:99;
for j = 0:19
    r = 1 + mod(j, 3);
    p2 = [p2, 100 + 20 * j + (0:20*r-1) / r]; %#ok<AGROW>
end
p2 = [p2, 500:T2-6];
p2 = 4 * round(p2 * fs / 4) / fs + 1 / fs;
p3 = (5:T2-6) + 2 / fs;
end


function writeArrhythmic(f, T2, fs, protocol)
n = T2 * fs;
t = (0:n-1) / fs;
x = zeros(4, n);
x(1:3,:) = repmat(-383 + round(3 * sin(2 * pi * 37.3 * t) + 2 * sin(2 * pi * 91.7 * t)), 3, 1);
[p1, p2, p3] = arrhythmicPulses(T2, fs);
P = {p1, p2, p3};
for c = 1:3, x(4, round(P{c} * fs) + 1) = bitor(50, bitshift(c, 9)); end
fid = fopen(f, 'w'); fwrite(fid, int16(round(x)), 'int16'); fclose(fid);
[~, name, ext] = fileparts(f); name = [name ext];
fid = fopen(strrep(f, '.mdd', '_log.log'), 'w');
fprintf(fid, 'systemTime;dataLogTime;channel;code;value\n');
fprintf(fid, '2000 01 01 10:00:00:000;0;0;samplingRate Recording;400\n');
fprintf(fid, '2000 01 01 10:00:00:000;0;0;Recording;started: %s\n', name);
if protocol
    fprintf(fid, '2000 01 01 10:01:40:000;100000;0;comment;FFR protocol started\n');
    fprintf(fid, '2000 01 01 10:08:20:000;500000;0;comment;FFR protocol ended\n');
end
fprintf(fid, '2000 01 01 10:10:00:000;%d;0;Recording;stopped: %s\n', T2 * 1000, name);
fclose(fid);
end


function writeFastStimulation(f, fs)
% 2 channels, 60 s: twitches (1000 uN, 30 ms after the pulse) at 1 Hz in both channels; ch1 pulses at 1 Hz, ch2 pulses
% at 20 Hz (status channel misread)
Tf = 60; n = Tf * fs;
t = (0:n-1) / fs;
x = zeros(3, n);
x(1:2,:) = repmat(-383 + round(3 * sin(2 * pi * 37.3 * t) + 2 * sin(2 * pi * 91.7 * t)), 2, 1);
beats = 2:Tf - 3;
for c = 1:2
    for p = beats, x(c,:) = x(c,:) + 1000 * twitch(t - p - 0.03); end
end
p1 = 4 * round(beats * fs / 4) / fs;
p2 = (2:0.05:Tf - 2 - 1e-9) + 1 / fs;
x(3, round(p1 * fs) + 1) = bitor(50, bitshift(1, 9));
x(3, round(p2 * fs) + 1) = bitor(50, bitshift(2, 9));
fid = fopen(f, 'w'); fwrite(fid, int16(round(x)), 'int16'); fclose(fid);
[~, name, ext] = fileparts(f); name = [name ext];
fid = fopen(strrep(f, '.mdd', '_log.log'), 'w');
fprintf(fid, 'systemTime;dataLogTime;channel;code;value\n');
fprintf(fid, '2000 01 01 10:00:00:000;0;0;samplingRate Recording;400\n');
fprintf(fid, '2000 01 01 10:00:00:000;0;0;Recording;started: %s\n', name);
fprintf(fid, '2000 01 01 10:01:00:000;%d;0;Recording;stopped: %s\n', Tf * 1000, name);
fclose(fid);
end


function writeRecording(f, T, fs, pulses)
n = T * fs;
t = (0:n-1) / fs;
x = zeros(9, n);
noise = round(3 * sin(2 * pi * 37.3 * t) + 2 * sin(2 * pi * 91.7 * t));
cfg = [0.03 1; 0.30 1; 0.03 -1];                    %delay, sign of channels 1-3
for c = 1:3
    y = zeros(1, n);
    for p = pulses
        k0 = round((p + cfg(c,1)) * fs) + 1;
        k1 = min(n, k0 + round(1.2 * fs) - 1);
        y(k0:k1) = y(k0:k1) + twitch((0:k1-k0) / fs);
    end
    x(c,:) = -383 + cfg(c,2) * 1000 * y + noise;
end
x(4:8,:) = repmat(-383 + noise, 5, 1);
i = 0:numel(pulses) - 1;                           %ch5: rocker waves partly in phase with the pulses
u = 2 * mod((i + 1) * 0.7548776662466927, 1) - 1;  %phase at pulse i: 2 pi 3 i + 2.5 u_i, linear in between
th = 2 * pi * 3 * i + 2.5 * u;
w = 2 * pi * 3 / 2;
th = interp1([0 pulses T], [th(1) - w * pulses(1), th, th(end) + w * (T - pulses(end))], t);
x(5,:) = -383 - 400 * max(0, sin(th)) .^ 3 + noise;
st = zeros(1, n);
for c = [1 2 3 5]                                  %pulse of channel c one sample after the one of channel c-1
    st(round(pulses * fs) + (c - 1) + 1) = bitor(50, bitshift(c, 9));
end
x(9,:) = st;
fid = fopen(f, 'w'); fwrite(fid, int16(round(x)), 'int16'); fclose(fid);
[~, name, ext] = fileparts(f); name = [name ext];
fid = fopen(strrep(f, '.mdd', '_log.log'), 'w');
fprintf(fid, 'systemTime;dataLogTime;channel;code;value\n');
fprintf(fid, '2000 01 01 10:00:00:000;0;0;samplingRate Recording;400\n');
fprintf(fid, '2000 01 01 10:00:00:000;0;0;Recording;started: %s\n', name);
fprintf(fid, '2000 01 01 10:05:20:000;%d;0;Recording;stopped: %s\n', T * 1000, name);
fclose(fid);
end


function y = twitch(tau)
%twitch of amplitude 1: raised cosine rise in 0.1 s, exponential relaxation (0.12 s)
y = zeros(size(tau));
r = tau >= 0 & tau < 0.1;
y(r) = (1 - cos(pi * tau(r) / 0.1)) / 2;
d = tau >= 0.1;
y(d) = exp(-(tau(d) - 0.1) / 0.12);
end


function ok = check(ok, name, pass)
fprintf('%-72s %s\n', name, passStr(pass));
ok = ok && pass;
end


function s = passStr(pass)
if pass, s = 'ok'; else, s = 'FAILED'; end
end
