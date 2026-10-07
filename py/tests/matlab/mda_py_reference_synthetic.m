function mda_py_reference_synthetic(outFile)
%MDA_PY_REFERENCE_SYNTHETIC  Signals and results of the three mda_test scenarios for the comparison with Python.
%
%   mda_py_reference_synthetic('synthetic_reference.mat')
%
% Saves the input signals (so that Python analyses exactly the same data; the noise of the reference beat test is
% drawn with rng(3) as in mda_test) and the contraction tables of mda_analyzeChannel (table2struct, 'ToScalar').
% Compared by tests/test_matlab_reference.py.
%
% TS 2026-10-06

dt = 0.005;
% 1) exact parameters
t = 0:dt:20; F = 100 * ones(size(t)); onset = 1:1:18;
for k = 1:numel(onset)
    I = t >= onset(k) & t < onset(k) + 0.2; F(I) = 100 + 1000 * (t(I) - onset(k)) / 0.2;
    I = t >= onset(k) + 0.2 & t < onset(k) + 0.6; F(I) = 1100 - 1000 * (t(I) - onset(k) - 0.2) / 0.4;
end
S = mkS(t, F, onset, false(size(t)));
B = mda_analyzeChannel(S, 1, [2 17], mda_options('noFiltering', 'zeroForce', 40));
T1 = struct('t', t, 'F', F, 'onset', onset, 'B', table2struct(B, 'ToScalar', true));
% default filters on the same signal
B = mda_analyzeChannel(S, 1, [2 17], mda_options('zeroForce', 40));
T1.Bfilt = table2struct(B, 'ToScalar', true);

% 2) rocker filter
t = 0:dt:200; F = 100 * ones(size(t)); onset = 1:2:197;
for k = 1:numel(onset)
    I = t >= onset(k) & t < onset(k) + 0.2; F(I) = 100 + 1000 * (t(I) - onset(k)) / 0.2;
    I = t >= onset(k) + 0.2 & t < onset(k) + 0.6; F(I) = 1100 - 1000 * (t(I) - onset(k) - 0.2) / 0.4;
end
on = t < 90 | t >= 100; art = zeros(size(t));
for q = 1:2
    I = on & ((t < 90) == (q == 1));
    a = cos(2*pi*1.2117*t(I) + 0.3 + q) + 0.5 * cos(4*pi*1.2117*t(I) + 2.1 + 2*q) + 0.25 * cos(6*pi*1.2117*t(I) + 4 + q);
    art(I) = 300 * a / (max(a) - min(a));
end
S = mkS(t, F + art, onset, on); S.rockerSpeedLog = [-inf 60];
o = mda_options('noFiltering', 'zeroForce', 40);
B0 = mda_analyzeChannel(S, 1, [5 195], o);
[B1, C1] = mda_analyzeChannel(S, 1, [5 195], mda_options(o, 'rockerFilter', true));
RF = C1.rockerFilter;
T2 = struct('t', t, 'F', F + art, 'onset', onset, 'on', double(on), 'B0', table2struct(B0, 'ToScalar', true), ...
    'B1', table2struct(B1, 'ToScalar', true), 'artifact', C1.rockerArtifact, 'f0', RF.f0, 'status', RF.status, ...
    'artifactPP', RF.artifactPP, 'r2', RF.r2, 'blocks', RF.blocks, 'pass', RF.pass);
% default filters + rocker filter
[B1f, C1f] = mda_analyzeChannel(S, 1, [5 195], mda_options('zeroForce', 40, 'rockerFilter', true));
T2.B1filt = table2struct(B1f, 'ToScalar', true); T2.artifactFilt = C1f.rockerArtifact;

% 3) reference beat (noise from rng(3), as mda_test)
rs = rng; rng(3);
t = 0:dt:60; F = 100 + 10 * randn(size(t)); onset = 1:58; typ = zeros(size(onset));
typ([20 35]) = 1; typ([25 45]) = 2; typ([30 50]) = 3; typ([40 55]) = 4;
for k = 1:numel(onset)
    A = 1000 * (1 + 0.03 * randn); rel = 0.4; t0 = onset(k);
    if typ(k) == 2, A = 500; end
    if typ(k) == 3, rel = 0.6; end
    if typ(k) == 4, t0 = t0 + 0.04; end
    I = t >= t0 & t < t0 + 0.2; F(I) = F(I) + A * (t(I) - t0) / 0.2;
    I = t >= t0 + 0.2 & t < t0 + 0.2 + rel; F(I) = F(I) + A - A * (t(I) - t0 - 0.2) / rel;
    if typ(k) == 1, I = t >= t0 + 0.35 & t < t0 + 0.5; F(I) = F(I) + 250 * sin(pi * (t(I) - t0 - 0.35) / 0.15); end
end
rng(rs);
S = mkS(t, F, onset, false(size(t)));
o = mda_options('zeroForce', 40);
[B, C] = mda_analyzeChannel(S, 1, [0.5 59], o);
rows = find(B.t_peak > 2 & B.t_peak < 16);
R = mda_referenceBeat('create', C, B, rows);
BR = mda_analyzeChannel(S, 1, [0.5 59], mda_options(o, 'referenceBeat', R));
RU = mda_referenceBeat('align', R, 'upstroke');
BU = mda_analyzeChannel(S, 1, [0.5 59], mda_options(o, 'referenceBeat', RU));
Y = mda_referenceBeat('traces', C, B, R, 1:height(B));
R.created = '';
T3 = struct('t', t, 'F', F, 'onset', onset, 'typ', typ, 'rows', rows, 'B', table2struct(B, 'ToScalar', true), ...
    'BR', table2struct(BR, 'ToScalar', true), 'BU', table2struct(BU, 'ToScalar', true), 'R', R, 'Y', Y);
save(outFile, 'T1', 'T2', 'T3', '-v7');
fprintf('mda_py_reference_synthetic: %s written\n', outFile);
end

function S = mkS(t, F, onset, on)
S = struct('dataChannels', 1, 'dt', 0.005, 't', t, 'force', F, 'rockerOn', on, 'fromSeconds', t(1), 'toSeconds', t(end));
S.stim = struct('time', (onset - 0.1)', 'channel', ones(numel(onset), 1));
end
