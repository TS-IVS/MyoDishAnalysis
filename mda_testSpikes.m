function ok = mda_testSpikes()
%MDA_TESTSPIKES  Test of the spike removal (mda_removeSpikes, option 'spikeRemoval' of mda_readMdd) with synthetic
%signals (20 s, 400 Hz).
%
%   ok = mda_testSpikes()   prints the single checks, returns true if all pass
%
%   ch1  rabbit-like contractions every 1 s (rise 60 ms), noise +-8 AU (raw sample pairs as in MyoDish files)
%        spikes: 2.3 s one sample +2000; 4.6 s five samples -3000; 16.0 s five samples +3000
%   ch2  fast rat-like contractions every 0.5 s (rise 20 ms), noise +-50 AU
%        spikes: 1 sample -1500 in the upstroke of the contraction at 3.3 s; 16.0025 s five samples +120 (smaller
%        than the jump threshold of ch2: found because of the spike of ch1 at the same time)
%   ch3  chamber put in at 10 s: -5000 --> 30 ms at +20000, 10 ms at -15000 --> new level -2000 (spike + step);
%        chamber taken out at 14 s: step to -8000 (no spike: stays)
% Pendant of py/tests/test_spikes.py (same signals and checks; sample indices here 1-based).
%
% TS 2026-10-10

ok = true;
fs = 400; N = 20 * 400;
[X0, X] = signals(fs, N);
[~, none] = mda_removeSpikes(X0, fs);
ok = check(ok, 'no spikes: contractions (also fast ones), noise, steps', isempty(none));
[Y, sp] = mda_removeSpikes(X, fs);
ok = check(ok, '6 spikes at the right samples', size(sp, 1) == 6 && isequal(sp(:,1)', [1 2 1 3 1 2]) && ...
    isequal(sp(:,2)', [921 1325 1841 4001 6401 6402]) && isequal(sp(:,3)', [921 1325 1845 4016 6405 6406]));
rep = false(size(X));
for i = 1:size(sp, 1), rep(sp(i,1), sp(i,2):sp(i,3)) = true; end
ok = check(ok, 'nothing else changed', isequal(Y(~rep), X(~rep)));
ok = check(ok, 'replaced values close to the signal without spikes', ...
    max(abs(Y(1, [921 1841 1843 1845 6403]) - X0(1, [921 1841 1843 1845 6403]))) <= 20 && ...
    abs(Y(2, 1325) - X0(2, 1325)) <= 0.1 * 800 && max(abs(Y(2, 6402:6406) - X0(2, 6402:6406))) <= 120);
seg = Y(3, 3996:4025);
ok = check(ok, 'chamber put in: ramp from the old to the new level', max(seg) <= -1900 && min(seg) >= -5100);
ok = check(ok, 'chamber taken out: step kept', isequal(Y(3, 5591:5700), X0(3, 5591:5700)));

% mda_readMdd (option 'spikeRemoval') and MyoDishAnalysis (notes)
folder = tempname; mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's')); %#ok<NASGU>
f = fullfile(folder, 'spikes_rigA_0.mdd');
raw = zeros(9, N); raw(1:3, :) = X; raw(4:8, :) = -383;
fid = fopen(f, 'w'); fwrite(fid, int16(raw), 'int16'); fclose(fid);
L = {'systemTime;dataLogTime;channel;code;value', ...
    '2000 01 01 10:00:00:000;0;0;samplingRate Recording;400', ...
    '2000 01 01 10:00:00:000;0;0;Recording;started: spikes_rigA_0.mdd', ...
    '2000 01 01 10:00:20:000;20000;0;Recording;stopped: spikes_rigA_0.mdd'};
fid = fopen(strrep(f, '.mdd', '_log.log'), 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
H = mda_readMdd(f);
S = mda_readMdd(H, 0, 20);
S0 = mda_readMdd(H, 0, 20, mda_options('spikeRemoval', false));
ok = check(ok, 'mda_readMdd: S.spikes (channel, time); spikeRemoval false: raw data', size(S.spikes, 1) == 6 && ...
    isequal(S.spikes(:,1)', [1 2 1 3 1 2]) && ...
    max(abs(S.spikes(:,2)' - [920 1324 1840 4000 6400 6401] / fs)) < 1e-12 && ...
    isempty(S0.spikes) && isequal(S0.force(1,:), (X(1,1:2:end) + X(1,2:2:end)) / 2));
[C, ~, info] = MyoDishAnalysis(f, [1 2 3], 0, 20, 'quiet', true);
C0 = MyoDishAnalysis(f, [1 2 3], 0, 20, 'quiet', true, 'spikeRemoval', false);
ok = check(ok, 'MyoDishAnalysis: note, spike of the chamber put in is no contraction', ...
    any(strcmp(info.notes, ['Spike artifacts removed (option spikeRemoval): 6 (channel 1: 3, channel 2: 2, ' ...
    'channel 3: 1), largest 24997 AU.'])) && max(C0.amplitude(C0.channel == 3)) > 20000 && ...
    max(C.amplitude(C.channel == 3)) < 5000 && sum(C.channel == 1) == 20 && sum(C0.channel == 1) == 20);
end


function [X0, X] = signals(fs, N)
k = 0:N-1;
t = k / fs;
X0 = zeros(3, N);
X0(1,:) = floor(-8000 + beats(t, 0.5, 1.0, 1000, 0.06, 0.12) + 0.5) + noise(k, 5, 3);
X0(2,:) = floor(-5000 + beats(t, 0.3, 0.5, 800, 0.02, 0.04) + 0.5) + noise(k, 30, 20);
lvl = -8000 * ones(1, N); lvl(k < 5600) = -2000; lvl(k < 4000) = -5000;
X0(3,:) = lvl + noise(k, 5, 3);
X = X0;
X(1, 921) = X(1, 921) + 2000;
X(1, 1841:1845) = X(1, 1841:1845) - 3000;
X(1, 6401:6405) = X(1, 6401:6405) + 3000;
X(2, 1325) = X(2, 1325) - 1500;
X(2, 6402:6406) = X(2, 6402:6406) + 120;
X(3, 4001:4012) = 20000;
X(3, 4013:4016) = -15000;
end


function v = noise(k, a, b)
kk = 2 * floor(k / 2);                             %pairs of identical raw samples
v = floor(a * sin(0.7 * kk) + b * sin(1.9 * kk + 0.3) + 0.5);
end


function y = beats(t, first, period, amp, rise, tau)
y = zeros(size(t));
for t0 = first:period:t(end)
    u = t - t0;
    r = u >= 0 & u < rise;
    y(r) = y(r) + amp * (1 - cos(pi * u(r) / rise)) / 2;
    d = u >= rise & u < rise + 8 * tau;
    y(d) = y(d) + amp * exp(-(u(d) - rise) / tau);
end
end


function ok = check(ok, name, pass)
fprintf('%-72s %s\n', name, passStr(pass));
ok = ok && pass;
end


function s = passStr(pass)
if pass, s = 'ok'; else, s = 'FAILED'; end
end
