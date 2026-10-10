function ok = mda_test()
%MDA_TEST  Self test of the parameter calculation with synthetic contractions of known shape.
%
%   ok = mda_test()   prints expected and calculated values, returns true if all agree (rel. error < 1e-9)
%
% Synthetic signal (no filtering): diastolic signal 100 uN (zero force 40 uN --> diastolic force 60 uN), linear rise by 1000 uN within 200 ms, linear
% relaxation within 400 ms, one contraction per second, stimulus 100 ms before the onset. For this shape all
% parameters can be calculated by hand (linear interpolation of the level crossings is exact):
%   riseTime10_90 = 0.8*0.2, TTP90 = 0.9*0.2, TTR50 = 0.5*0.4, TTR90 = 0.9*0.4, CD50 = 0.1+0.2,
%   CD90 = 0.18+0.36, dF/dt = 1000/0.2 and -1000/0.4, AUC = 0.5*0.6*1000 - 0.5*0.02*100 - 0.5*0.04*100 = 297
% Rocker filter: the same contractions every 2 s with a periodic rocker artifact (30 % of the amplitude); with the
% option 'rockerFilter' amplitude, TTP90, TTR90 and diastolic force must be recovered (0.5 %, 2 ms, 2 uN).
% Reference beat: shoulder, partial response, slow relaxation and (aligned at the stimulus) a 40 ms longer latency must
% deviate by > 5 SD, normal beats < 3 SD (normalized); the partial response (half amplitude, same shape) only in the
% absolute deviation, the longer latency not when aligned at the 50 % upstroke.
% Stimulation pause: after a 9 s pause with rocker movement until 1.2 s before the stimulus, F_dia (amplitude 1000 uN)
% and the rocker state of the first contraction come from the 0.5 s before its stimulus (option pauseDiastoleWindow).
% External trigger pulses: a temporary 9-channel .mdd file with external trigger pulses only (status bit 14 without
% channel / current): read as channel 0, one entry per pulse, stimuli with option externalTrigger 'auto' / 'on'.
% Rocker peaks (option rockerArtifacts): rocker movement only, every 4th stimulus answered, every stimulus answered.
% Uncertain contractions (option detection): small peaks between the contractions, not locked to the stimuli.
%
% Diastolic level (option diastolicLevel): median before the pulse vs minimum before the peak. FFR steady state and PRP
% reference per pause (protocolSelectionTest).
%
% TS 2026-10-05 (stimulation pause 2026-10-07, external trigger 2026-10-08, rocker peaks, uncertain 2026-10-09;
% diastolic level, FFR steady state, PRP reference 2026-10-10)

dt = 0.005;
t = 0:dt:20;
F = 100 * ones(size(t));
onset = 1:1:18;
for k = 1:numel(onset)
    I = t >= onset(k) & t < onset(k) + 0.2;
    F(I) = 100 + 1000 * (t(I) - onset(k)) / 0.2;
    I = t >= onset(k) + 0.2 & t < onset(k) + 0.6;
    F(I) = 1100 - 1000 * (t(I) - onset(k) - 0.2) / 0.4;
end
S = struct('dataChannels', 1, 'dt', dt, 't', t, 'force', F, 'rockerOn', false(size(t)), 'fromSeconds', 0, 'toSeconds', 20);
S.stim = struct('time', (onset - 0.1)', 'channel', ones(numel(onset), 1));
B = mda_analyzeChannel(S, 1, [2 17], mda_options('noFiltering', 'zeroForce', 40));

expected = {'amplitude', 1000; 'diastolicSignal', 100; 'diastolicForce', 60; 'dFdtMax', 5000; 'dFdtMin', -2500; ...
    'riseTime10_90', 0.16; 'TTP90', 0.18; 'TTR50', 0.2; 'TTR90', 0.36; 'CD50', 0.3; 'CD90', 0.54; ...
    'AUC', 297; 'peakToPeakInterval', 1; 'peakToPeakFrequency', 1; 'stimToPeak', 0.3; 'stimInterval', 1; 'stimFrequency', 1};
ok = height(B) == 15 && all(strcmp(B.beatType, 'stimulated'));
fprintf('%d contractions detected (expected 15), all stimulated: %d\n', height(B), all(strcmp(B.beatType, 'stimulated')));
for k = 1:size(expected, 1)
    v = B.(expected{k,1});
    err = max(abs(v - expected{k,2})) / abs(expected{k,2});
    pass = err < 1e-9;
    ok = ok && pass;
    fprintf('%-20s expected %9.4f   calculated %9.4f   max. rel. error %.1e   %s\n', expected{k,1}, expected{k,2}, mean(v), err, passStr(pass));
end

% diastolic level (2026-10-10): a dip to 50 uN 0.3 ... 0.25 s before every pulse (outside the window 60 ... 5 ms
% before it): median before the pulse (default) 100 uN, amplitude 1000 uN; 'minimum' 50 uN, amplitude 1050 uN
F2 = F;
for k = 1:numel(onset), F2(t >= onset(k) - 0.4 & t < onset(k) - 0.35) = 50; end
S2 = S; S2.force = F2;
Bm = mda_analyzeChannel(S2, 1, [2 17], mda_options('noFiltering', 'zeroForce', 40));
Bn = mda_analyzeChannel(S2, 1, [2 17], mda_options('noFiltering', 'zeroForce', 40, 'diastolicLevel', 'minimum'));
okD = all(abs(Bm.amplitude - 1000) < 1e-9) && all(abs(Bm.diastolicSignal - 100) < 1e-9) && ...
    all(abs(Bm.TTP90 - 0.18) < 1e-9) && all(abs(Bn.amplitude - 1050) < 1e-9) && all(abs(Bn.diastolicSignal - 50) < 1e-9);
fprintf(['diastolic level: median before the pulse %.1f uN (amplitude %.1f), minimum %.1f uN (amplitude %.1f); ' ...
    'expected 100 / 1000, 50 / 1050   %s\n'], mean(Bm.diastolicSignal), mean(Bm.amplitude), mean(Bn.diastolicSignal), ...
    mean(Bn.amplitude), passStr(okD));
ok = ok && okD;

% rocker filter: the same contractions every 2 s plus a periodic artifact (60 rpm = 1.2117 Hz, 3 harmonics, 300 uN
% peak-to-peak = 30 % of the amplitude) while the rocker moves (0-90 s and 100-200 s, another phase after the stop)
t = 0:dt:200;
F = 100 * ones(size(t));
onset = 1:2:197;
for k = 1:numel(onset)
    I = t >= onset(k) & t < onset(k) + 0.2;
    F(I) = 100 + 1000 * (t(I) - onset(k)) / 0.2;
    I = t >= onset(k) + 0.2 & t < onset(k) + 0.6;
    F(I) = 1100 - 1000 * (t(I) - onset(k) - 0.2) / 0.4;
end
on = t < 90 | t >= 100;
art = zeros(size(t));
for q = 1:2
    I = on & ((t < 90) == (q == 1));
    a = cos(2*pi*1.2117*t(I) + 0.3 + q) + 0.5 * cos(4*pi*1.2117*t(I) + 2.1 + 2*q) + 0.25 * cos(6*pi*1.2117*t(I) + 4 + q);
    art(I) = 300 * a / (max(a) - min(a));
end
S = struct('dataChannels', 1, 'dt', dt, 't', t, 'force', F + art, 'rockerOn', on, 'fromSeconds', 0, 'toSeconds', 200, ...
    'rockerSpeedLog', [-inf 60]);
S.stim = struct('time', (onset - 0.1)', 'channel', ones(numel(onset), 1));
o = mda_options('noFiltering', 'zeroForce', 40);
B0 = mda_analyzeChannel(S, 1, [5 195], o);
[B1, C1] = mda_analyzeChannel(S, 1, [5 195], mda_options(o, 'rockerFilter', true));
chk = {'amplitude', 1000, 0.005; 'TTP90', 0.18, 0.002; 'TTR90', 0.36, 0.002; 'diastolicForce', 60, 2};  %name, value, tolerance
fprintf('rocker filter (%s, f0 %.4f Hz): %d contractions (expected 95)\n', C1.rockerFilter.status, C1.rockerFilter.f0, height(B1));
okR = height(B1) == 95 && strcmp(C1.rockerFilter.status, 'corrected');
for k = 1:size(chk, 1)
    tol = chk{k,3}; if strcmp(chk{k,1}, 'amplitude'), tol = tol * chk{k,2}; end
    e0 = max(abs(B0.(chk{k,1}) - chk{k,2}));
    e1 = max(abs(B1.(chk{k,1}) - chk{k,2}));
    pass = e1 <= tol;
    okR = okR && pass;
    fprintf('%-20s expected %9.4f   max. abs. error without filter %8.4f, with filter %8.4f   %s\n', chk{k,1}, chk{k,2}, e0, e1, passStr(pass));
end
ok = ok && okR;

% reference beat: 1 Hz, noise 10 uN, amplitude 1000 uN +- 3 %; 2 beats each with a shoulder (250 uN during relaxation),
% half amplitude (partial response), slower relaxation (0.6 instead of 0.4 s) and 40 ms longer latency after the
% stimulus (same shape); reference = beats 2-15, aligned at the stimulus (default) and at the 50 % upstroke
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
S = struct('dataChannels', 1, 'dt', dt, 't', t, 'force', F, 'rockerOn', false(size(t)), 'fromSeconds', 0, 'toSeconds', 60);
S.stim = struct('time', (onset - 0.1)', 'channel', ones(numel(onset), 1));
o = mda_options('zeroForce', 40);
[B, C] = mda_analyzeChannel(S, 1, [0.5 59], o);
R = mda_referenceBeat('create', C, B, find(B.t_peak > 2 & B.t_peak < 16));
B = mda_analyzeChannel(S, 1, [0.5 59], mda_options(o, 'referenceBeat', R));
BU = mda_analyzeChannel(S, 1, [0.5 59], mda_options(o, 'referenceBeat', mda_referenceBeat('align', R, 'upstroke')));
tp = interp1(onset + 0.2, typ, B.t_peak, 'nearest');
dn = B.refMaxDeviationNorm_SD; da = B.refMaxDeviation_SD; dnU = BU.refMaxDeviationNorm_SD;
rn = B.refRMSDeviationNorm_SD;
okB = height(B) == 58 && strcmp(R.align, 'stimulus') && all(dn(tp == 0) < 3) && all(dn(tp == 1 | tp == 3) > 5) && ...
    all(da(tp == 1 | tp == 3) > 5) && all(da(tp == 2) > 5) && all(dn(tp == 2) < 3) && all(B.refCorrelation(tp == 2) > 0.999) && ...
    all(dn(tp == 4) > 5) && all(dnU(tp == 4) < 3) && all(dnU(tp == 0) < 3) && max(rn(tp == 0)) < min(rn(tp == 1 | tp == 3 | tp == 4));
fprintf(['reference beat (stimulus-aligned; max. deviation absolute / normalized, SD): normal max %.1f (normalized) | ' ...
    'shoulder %.1f / %.1f | partial %.1f / %.1f (corr %.4f) | slow relaxation %.1f / %.1f | latency +40 ms %.1f / %.1f, ' ...
    'upstroke-aligned %.1f | RMS normalized: normal max %.2f, deviating min %.2f   %s\n'], max(dn(tp == 0)), min(da(tp == 1)), ...
    min(dn(tp == 1)), min(da(tp == 2)), max(dn(tp == 2)), min(B.refCorrelation(tp == 2)), min(da(tp == 3)), min(dn(tp == 3)), ...
    min(da(tp == 4)), min(dn(tp == 4)), max(dnU(tp == 4)), max(rn(tp == 0)), min(rn(tp == 1 | tp == 3 | tp == 4)), passStr(okB));
ok = ok && okB;
% parameters relative to the reference (2026-10-06): normal ~100 %, partial response ~50 % amplitude, slow relaxation
% TTR90 0.54 / 0.36 s = 150 %
pa = B.amplitude_pctRef; pr = B.TTR90_pctRef;
okP = all(abs(pa(tp == 0) - 100) < 10) && all(abs(pa(tp == 2) - 50) < 5) && all(abs(pr(tp == 3) - 150) < 10) && ...
    all(abs(pr(tp == 0) - 100) < 5) && all(abs(B.diastolicForce_dRef(tp == 0)) < 40);
fprintf(['relative to the reference: amplitude normal %.0f-%.0f %%, partial %.0f-%.0f %% (expected 50) | TTR90 slow ' ...
    'relaxation %.0f-%.0f %% (expected 150) | diastolic force difference normal max %.0f uN   %s\n'], min(pa(tp == 0)), ...
    max(pa(tp == 0)), min(pa(tp == 2)), max(pa(tp == 2)), min(pr(tp == 3)), max(pr(tp == 3)), ...
    max(abs(B.diastolicForce_dRef(tp == 0))), passStr(okP));
ok = ok && okP;

% stimulation pause (2026-10-07): 1 Hz, pause of 9 s, rocker moving (artifact +-120 uN) until 1.2 s before the next
% stimulus. F_dia of the first contraction after the pause: only from pauseDiastoleWindow (0.5 s) before its stimulus
% (amplitude 1000 uN, rocker stopped); with the whole window (Inf) the artifact gives F_dia and the rocker state.
% Diastolic level 'minimum' (the median before the pulse is not affected by the pause: amplitude 1000 uN in both).
t = 0:dt:30;
F = 100 * ones(size(t));
onset = [1:10, 19:28];
for k = 1:numel(onset)
    I = t >= onset(k) & t < onset(k) + 0.2;
    F(I) = 100 + 1000 * (t(I) - onset(k)) / 0.2;
    I = t >= onset(k) + 0.2 & t < onset(k) + 0.6;
    F(I) = 1100 - 1000 * (t(I) - onset(k) - 0.2) / 0.4;
end
on = t >= 13.5 & t < 17.7;
F(on) = F(on) + 120 * sin(2*pi*1.2*t(on));
S = struct('dataChannels', 1, 'dt', dt, 't', t, 'force', F, 'rockerOn', on, 'fromSeconds', 0, 'toSeconds', 30);
S.stim = struct('time', (onset - 0.1)', 'channel', ones(numel(onset), 1));
o = mda_options('noFiltering', 'zeroForce', 40, 'diastolicLevel', 'minimum');
B = mda_analyzeChannel(S, 1, [0.5 29.5], o);
B0 = mda_analyzeChannel(S, 1, [0.5 29.5], mda_options(o, 'pauseDiastoleWindow', inf));
Bmed = mda_analyzeChannel(S, 1, [0.5 29.5], mda_options(o, 'pauseDiastoleWindow', inf, 'diastolicLevel', 'preStimulusMedian'));
p = abs(B.t_stim - 18.9) < 1e-9;
okS = height(B) == 20 && height(B0) == 20 && sum(p) == 1 && abs(B.amplitude(p) - 1000) < 1e-6 && ...
    abs(B.diastolicSignal(p) - 100) < 1e-6 && ~B.rockerMoving(p) && B0.amplitude(p) > 1050 && B0.rockerMoving(p) && ...
    max(abs(B.amplitude(~p) - B0.amplitude(~p))) < 1e-9 && ~any(B.rockerMoving) && abs(Bmed.amplitude(p) - 1000) < 1e-6;
fprintf(['stimulation pause 9 s, rocker moving until 1.2 s before the stimulus: amplitude %.1f uN (expected 1000; ' ...
    'whole window %.1f), rocker moving %d (whole window %d), other contractions unchanged   %s\n'], B.amplitude(p), ...
    B0.amplitude(p), B.rockerMoving(p), B0.rockerMoving(p), passStr(okS));
ok = ok && okS;

% peaks of the rocker movement (option rockerArtifacts, 2026-10-09): 200 s, stimuli every 2 s, rocker 60 rpm moving
% throughout (artifact 80 uN peak-to-peak, 2 harmonics). No contractions: none counted, C.noContractions; every 4th
% stimulus answered (200 uN): only these 24 contractions; every stimulus answered (150 uN): 95 contractions, no extra
% beats. Without the option the rocker peaks count (> 200 peaks each).
t = 0:dt:200;
onset = 1:2:197;
a = cos(2*pi*1.212*t + 0.4) + 0.3 * cos(4*pi*1.212*t + 1.3);
art = 80 * a / (max(a) - min(a));
o = mda_options('zeroForce', 40);
nR = zeros(3, 4); noC = false(1, 3);
amps = [0 200 150];
for q = 1:3
    ons = onset;
    if q == 2, ons = onset(1:4:end); end
    F = 100 * ones(size(t));
    for k = 1:numel(ons) * (amps(q) > 0)
        I = t >= ons(k) & t < ons(k) + 0.2;
        F(I) = 100 + amps(q) * (t(I) - ons(k)) / 0.2;
        I = t >= ons(k) + 0.2 & t < ons(k) + 0.6;
        F(I) = 100 + amps(q) - amps(q) * (t(I) - ons(k) - 0.2) / 0.4;
    end
    S = struct('dataChannels', 1, 'dt', dt, 't', t, 'force', F + art, 'rockerOn', true(size(t)), 'fromSeconds', 0, ...
        'toSeconds', 200, 'rockerSpeedLog', [-inf 60]);
    S.stim = struct('time', (onset - 0.1)', 'channel', ones(numel(onset), 1));
    B0 = mda_analyzeChannel(S, 1, [5 195], mda_options(o, 'rockerArtifacts', false));
    [B1, C1] = mda_analyzeChannel(S, 1, [5 195], o);
    nR(q, :) = [height(B0), height(B1), nnz(strcmp(B1.beatType, 'stimulated')), nnz(strcmp(B1.beatType, 'extra'))];
    noC(q) = C1.noContractions;
end
okA = isequal(nR(:, 2:4), [0 0 0; 24 24 0; 95 95 0]) && all(nR(:, 1) > 200) && isequal(noC, [true false false]);
fprintf(['rocker peaks (option rockerArtifacts): no contractions %d (without the option %d, no contractions flag %d) | ' ...
    'every 4th stimulus %d (expected 24; without %d) | every stimulus %d stimulated, %d extra (expected 95, 0; ' ...
    'without %d)   %s\n'], nR(1,2), nR(1,1), noC(1), nR(2,2), nR(2,1), nR(3,3), nR(3,4), nR(3,1), passStr(okA));
ok = ok && okA;

% uncertain contractions (option detection, 2026-10-09): 0.5 Hz, 300 uN, plus 32 small peaks (120 uN) between the
% contractions, not locked to the stimuli: 'sensitive' counts them as uncertain extra beats, 'specific' does not
t = 0:dt:200;
onset = 1:2:197;
F = 100 * ones(size(t));
for k = 1:numel(onset)
    I = t >= onset(k) & t < onset(k) + 0.2; F(I) = 100 + 300 * (t(I) - onset(k)) / 0.2;
    I = t >= onset(k) + 0.2 & t < onset(k) + 0.6; F(I) = 400 - 300 * (t(I) - onset(k) - 0.2) / 0.4;
end
bump = onset(1:3:end) + 1.1 + 0.3 * mod(1:numel(onset(1:3:end)), 3) / 2;
for k = 1:numel(bump), I = abs(t - bump(k)) < 0.1; F(I) = F(I) + 120 * (1 - abs(t(I) - bump(k)) / 0.1); end
S = struct('dataChannels', 1, 'dt', dt, 't', t, 'force', F, 'rockerOn', false(size(t)), 'fromSeconds', 0, 'toSeconds', 200);
S.stim = struct('time', (onset - 0.1)', 'channel', ones(numel(onset), 1));
o = mda_options('zeroForce', 40);
[B1, C1] = mda_analyzeChannel(S, 1, [5 195], o);
B2 = mda_analyzeChannel(S, 1, [5 195], mda_options(o, 'detection', 'specific'));
T1 = mda_summarize(B1, C1, [5 195]);
okU = height(B1) == 127 && nnz(B1.uncertain) == 32 && all(strcmp(B1.beatType(B1.uncertain), 'extra')) && ...
    height(B2) == 95 && T1.nUncertain == 32 && T1.nExtraBeatsUncertain == 32 && T1.nStimulatedUncertain == 0;
fprintf(['uncertain contractions (option detection): sensitive %d (expected 127), uncertain %d extra beats (expected 32), ' ...
    'specific %d (expected 95), summary nUncertain %d   %s\n'], height(B1), nnz(B1.uncertain), height(B2), T1.nUncertain, passStr(okU));
ok = ok && okU;

% external trigger pulses (2026-10-08): status bit 14 without channel / current (external stimulator at the external
% controller unit). Temporary .mdd (9 channels, 400 Hz, 30 s; contractions in channel 1 150 ms after each pulse, one
% pulse 2 samples long, rocker bit set throughout as at the external controller unit): stim.channel 0, one entry per
% pulse; stimuli of the analysed channel with 'auto' / 'on', not with 'off'; with a MyoDish pulse in the window 'auto'
% keeps the MyoDish pulses
okX = externalTriggerTest();
ok = ok && okX;
% tolerances of the grouping (2026-10-10): pacing frequency rounded to 0.1 Hz (0.99, 1.0 and 1.031 Hz = '1 Hz'),
% pauses within 10 % = one pause length (PRP results: mean of these pauses)
okG = groupingTest();
ok = ok && okG;
% FFR steady state and PRP reference per pause (2026-10-10)
okP = protocolSelectionTest();
ok = ok && okP;
if ok, disp('mda_test: all tests passed.'); else, warning('mda_test: TEST FAILED.'); end
end

function okG = groupingTest()
% temporary .mdd (9 channels, 400 Hz): pulses of channel 1 at intervals of 2.0, 2.04 (8 each: 0.5 / 0.49 Hz), 1.3325,
% 1.35 (6 each: 0.75 / 0.74 Hz), 1.0, 1.01, 0.97, 0.5 and 0.51 s (12 each),
% then 1 s pacing with pauses (intervals 16, 15.5, 31 and 32.5 s, 10 stimuli between them); a contraction 30 ms after
% every pulse (rise 100 ms, relaxation 200 ms)
fs = 400;
iv = [2 * ones(1, 8), 2.04 * ones(1, 8), 1.3325 * ones(1, 6), 1.35 * ones(1, 6), ones(1, 12), 1.01 * ones(1, 12), ...
    0.97 * ones(1, 12), 0.5 * ones(1, 12), 0.51 * ones(1, 12)];
ffrEnd = 1 + sum(iv) + 0.5;
pz = [16 15.5 31 32.5];
for q = 1:numel(pz), iv = [iv, ones(1, 10), pz(q)]; end %#ok<AGROW>
iv = [iv, ones(1, 10)];
ts = 1 + [0 cumsum(iv)];
ts = round(ts * fs) / fs;
T = ceil(ts(end)) + 2; n = T * fs; tt = (0:n-1) / fs;
F = 2000 * ones(1, n);
for k = 1:numel(ts)
    a = ts(k) + 0.03;
    I = tt >= a & tt < a + 0.1; F(I) = 2000 + 1000 * (tt(I) - a) / 0.1;
    I = tt >= a + 0.1 & tt < a + 0.3; F(I) = 3000 - 1000 * (tt(I) - a - 0.1) / 0.2;
end
X = zeros(9, n, 'int16');
X(1,:) = int16(round(F));
code = zeros(1, n, 'uint16');
code(round(ts * fs) + 1) = uint16(512 + 50);       %channel 1, 50 mA
X(9,:) = typecast(code, 'int16');
base = [tempname '_grouping'];
mdd = [base '.mdd']; lg = [base '_log.log'];
fid = fopen(mdd, 'w'); fwrite(fid, X, 'int16'); fclose(fid);
L = {'systemTime;dataLogTime;channel;code;value', '2026 01 01 06:00:00:000;0;0;nChannels;9', ...
    '2026 01 01 06:00:00:000;0;0;Recording;started: x.mdd', '2026 01 01 06:00:00:000;0;0;samplingRate Recording;400'};
for c = 1:8
    L{end+1} = sprintf('2026 01 01 06:00:00:000;0;%d;Calibration;1000', c); %#ok<AGROW>
    L{end+1} = sprintf('2026 01 01 06:00:00:000;0;%d;Offset;0', c); %#ok<AGROW>
end
L{end+1} = sprintf('2026 01 01 06:%02d:%02d:000;%d;0;Recording;stopped: x.mdd', floor(T / 60), mod(T, 60), T * 1000);
fid = fopen(lg, 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
okG = false;
try
    o = {'quiet', true, 'noFiltering', 'spikeRemoval', false};
    [~, Sf, If] = MyoDishAnalysis(mdd, 1, 0.5, ffrEnd, 'groupBy', 'pacingFrequency', o{:});
    [~, Sp, Ip] = MyoDishAnalysis(mdd, 1, ffrEnd, T, 'groupBy', 'pauseLength', o{:});
    Sf = Sf(~strcmp(Sf.group, 'unknown'), :);
    R = Ip.protocolResults;
    rest = Sp(strcmp(Sp.groupRole, 'postRest'), :);
    [~, Sf2] = MyoDishAnalysis(mdd, 1, 0.5, ffrEnd, 'groupBy', 'pacingFrequency', 'frequencyResolution', 0.01, o{:});
    okG = isequal(sort(Sf.group)', {'0.5 Hz', '0.75 Hz', '1 Hz', '2 Hz'}) && ...
        isequal(sort(Sf.groupValue)', [0.5 0.75 1 2]) && ...
        Sf.nStimuli(strcmp(Sf.group, '1 Hz')) == 36 && If.protocolResults.maxCapturedFrequency_Hz == 2 && ...
        abs(If.protocolResults.FFR_1Hz_pct - 100) < 2 && abs(If.protocolResults.FFR_2Hz_pct - 100) < 2 && ...
        height(rest) == 4 && ...
        isequal(rest.group', {'rest 15.8 s #1', 'rest 15.8 s #2', 'rest 31.8 s #3', 'rest 31.8 s #4'}) && ...
        abs(R.PRP15_pause_s - 14.75) < 1e-6 && abs(R.PRP30_pause_s - 30.75) < 1e-6 && isnan(R.PRP60_pct) && ...
        contains(R.resultNote{1}, 'PRP15: mean of 2 pauses') && any(strcmp(Sf2.group, '1.03 Hz'));
    fprintf(['grouping tolerances: frequency groups %s (expected 0.5, 0.75, 1, 2 Hz), pauses %s, PRP15 / 30 pause %.2f / %.2f s ' ...
        '(expected 14.75 / 30.75)   %s\n'], strjoin(Sf.group', ', '), strjoin(rest.group', ', '), R.PRP15_pause_s, ...
        R.PRP30_pause_s, passStr(okG));
catch ME
    fprintf('grouping tolerances: %s   FAILED\n', ME.message);
end
delete(mdd); delete(lg);
end

function okP = protocolSelectionTest()
% temporary .mdd (9 channels, 400 Hz): FFR protocol (log comments) with pulses at 0.5 Hz (16), 1 Hz (20), 2 Hz (20)
% and again 0.5 Hz (3), amplitude 1000 + 10 x number of the pulse; PRP protocol: 1 Hz train of 12 pulses (amplitudes
% 920 ... 1140), pause 10 s, post-rest contraction 2000 uN, 11 pulses (940 ... 1140), pause 20 s, post-rest 2500 uN,
% 12 pulses. 2 Hz with 2:1 capture (no contraction after every second pulse). Expected: FFR 0.5 Hz from the longest
% run (15 pulses with the interval of 0.5 Hz), its last 10 contractions (mean 1115 uN), groupStep 1; steadyStateBeats
% 0: all 18 contractions; 2 Hz: no steady state (no included contraction, note). PRP: 'preceding' reference median of
% the last 6 (1090 uN): 183.49 / 229.36 %; 'firstTrain' mean of the train at 1 Hz (1040 uN): 192.31 / 240.38 %
fs = 400;
ivF = [2 * ones(1, 15), ones(1, 20), 0.5 * ones(1, 20), 2 * ones(1, 3)];
tsF = 2 + [0 cumsum(ivF)];
ampF = 1000 + 10 * (1:numel(tsF));
t0 = tsF(end) + 2;                                 %(2 s: no pause before the train)
ivP = [ones(1, 11), 10, ones(1, 11), 20, ones(1, 12)];
tsP = t0 + [0 cumsum(ivP)];
ampP = [920:20:1140, 2000, 940:20:1140, 2500, 1000 * ones(1, 12)];
ts = round([tsF tsP] * fs) / fs; amp = [ampF ampP];
hasC = true(size(ts)); hasC(38:2:56) = false;     %2 Hz (pulses 37 ... 56): 2:1 capture
T = ceil(ts(end)) + 3; n = T * fs; tt = (0:n-1) / fs;
F = 2000 * ones(1, n);
for k = find(hasC)
    a = ts(k) + 0.03;
    I = tt >= a & tt < a + 0.1; F(I) = 2000 + amp(k) * (tt(I) - a) / 0.1;
    I = tt >= a + 0.1 & tt < a + 0.3; F(I) = 2000 + amp(k) - amp(k) * (tt(I) - a - 0.1) / 0.2;
end
X = zeros(9, n, 'int16');
X(1,:) = int16(round(F));
code = zeros(1, n, 'uint16');
code(round(ts * fs) + 1) = uint16(512 + 50);       %channel 1, 50 mA
X(9,:) = typecast(code, 'int16');
base = [tempname '_protsel'];
mdd = [base '.mdd']; lg = [base '_log.log'];
fid = fopen(mdd, 'w'); fwrite(fid, X, 'int16'); fclose(fid);
clk = @(x) sprintf('2026 01 01 06:%02d:%02d:%03d', floor(x / 60), floor(mod(x, 60)), round(1000 * mod(x, 1)));
L = {'systemTime;dataLogTime;channel;code;value', '2026 01 01 06:00:00:000;0;0;nChannels;9', ...
    '2026 01 01 06:00:00:000;0;0;Recording;started: x.mdd', '2026 01 01 06:00:00:000;0;0;samplingRate Recording;400'};
for c = 1:8
    L{end+1} = sprintf('2026 01 01 06:00:00:000;0;%d;Calibration;1000', c); %#ok<AGROW>
    L{end+1} = sprintf('2026 01 01 06:00:00:000;0;%d;Offset;0', c); %#ok<AGROW>
end
ev = {1.5, 'FFR protocol started'; tsF(end) + 1, 'FFR protocol ended'; t0 - 0.5, 'PRP protocol started'; ...
    tsP(end) + 1, 'PRP protocol ended'};
for q = 1:size(ev, 1)
    L{end+1} = sprintf('%s;%d;0;comment;%s', clk(ev{q,1}), round(1000 * ev{q,1}), ev{q,2}); %#ok<AGROW>
end
L{end+1} = sprintf('%s;%d;0;Recording;stopped: x.mdd', clk(T), T * 1000);
fid = fopen(lg, 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
okP = false;
try
    o = {'quiet', true, 'noFiltering', 'spikeRemoval', false, 'downsampling', 1};
    [~, S1, I1] = MyoDishAnalysis(mdd, 1, [], [], 'protocol', 'all', o{:});
    [~, S0] = MyoDishAnalysis(mdd, 1, [], [], 'protocol', 'FFR', 'steadyStateBeats', 0, o{:});
    [~, S2] = MyoDishAnalysis(mdd, 1, [], [], 'protocol', 'PRP', 'prpReference', 'firstTrain', o{:});
    g = @(S, r, nm) S(strcmp(S.range, r) & strcmp(S.group, nm), :);
    a = g(S1, 'FFR 1', '0.5 Hz'); a0 = g(S0, 'FFR 1', '0.5 Hz');
    p1 = g(S1, 'PRP 1', 'rest 10 s'); p2 = g(S1, 'PRP 1', 'rest 20 s');
    q1 = g(S2, 'PRP 1', 'rest 10 s'); q2 = g(S2, 'PRP 1', 'rest 20 s');
    a2 = g(S1, 'FFR 1', '2 Hz');
    n2 = 0; if ~isempty(a2), n2 = a2.nContractions; end
    note2 = any(contains(I1.notes, 'no run of captured stimuli at 2 Hz'));
    okP = a.nContractions == 10 && abs(a.amplitude_mean - 1115) < 1e-6 && a.groupStep == 1 && ...
        g(S1, 'FFR 1', '1 Hz').nContractions == 10 && n2 == 0 && note2 && ...
        a0.nContractions == 18 && isnan(a0.groupStep) && ...
        abs(p1.amplitude_pctOfRef - 100 * 2000 / 1090) < 1e-6 && abs(p2.amplitude_pctOfRef - 100 * 2500 / 1090) < 1e-6 && ...
        abs(q1.amplitude_pctOfRef - 100 * 2000 / 1040) < 1e-6 && abs(q2.amplitude_pctOfRef - 100 * 2500 / 1040) < 1e-6 && ...
        a.irregular == 0;
    fprintf(['FFR steady state: 0.5 Hz %d contractions (expected 10), mean %.1f uN (1115), step %g (1), all: %d (18), ' ...
        '2 Hz with 2:1 capture %d (0, note %d); PRP %.2f / %.2f %% (183.49 / 229.36), firstTrain %.2f / %.2f %% ' ...
        '(192.31 / 240.38)   %s\n'], a.nContractions, a.amplitude_mean, a.groupStep, a0.nContractions, n2, note2, ...
        p1.amplitude_pctOfRef, p2.amplitude_pctOfRef, q1.amplitude_pctOfRef, q2.amplitude_pctOfRef, passStr(okP));
catch ME
    fprintf('FFR steady state / PRP reference: %s   FAILED\n', ME.message);
end
delete(mdd); delete(lg);
end

function okX = externalTriggerTest()
fs = 400; n = 30 * fs; tt = (0:n-1) / fs;
trig = 1:28;                                       %trigger times (s)
X = zeros(9, n, 'int16');
F = 2000 * ones(1, n);
for k = 1:numel(trig)
    a = trig(k) + 0.05;
    I = tt >= a & tt < a + 0.1; F(I) = 2000 + 1000 * (tt(I) - a) / 0.1;
    I = tt >= a + 0.1 & tt < a + 0.4; F(I) = 3000 - 1000 * (tt(I) - a - 0.1) / 0.3;
end
X(1,:) = int16(round(F));
code = repmat(uint16(16384), 1, n);                %rocker bit
iT = round(trig * fs) + 1;
code(iT) = uint16(24576);                          %bit 14 + 15
code(iT(5) + 1) = uint16(24576);                   %one pulse 2 samples long
X(9,:) = typecast(code, 'int16');
base = [tempname '_xtrig'];
mdd = [base '.mdd']; lg = [base '_log.log'];
fid = fopen(mdd, 'w'); fwrite(fid, X, 'int16'); fclose(fid);
L = {'systemTime;dataLogTime;channel;code;value', '2026 01 01 06:00:00:000;0;0;nChannels;9', ...
    '2026 01 01 06:00:00:000;0;0;Recording;started: x.mdd', '2026 01 01 06:00:00:000;0;0;samplingRate Recording;400'};
for c = 1:8
    L{end+1} = sprintf('2026 01 01 06:00:00:000;0;%d;Calibration;1000', c); %#ok<AGROW>
    L{end+1} = sprintf('2026 01 01 06:00:00:000;0;%d;Offset;0', c); %#ok<AGROW>
end
L{end+1} = '2026 01 01 06:00:30:000;30000;0;Recording;stopped: x.mdd';
fid = fopen(lg, 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
try
    S = mda_readMdd(mdd, 0, 30);
    o = mda_options('externalTrigger', 'auto');
    nSt = @(B) nnz(strcmp(B.beatType, 'stimulated'));
    [Ba, Ca] = mda_analyzeChannel(S, 1, [0.5 29.5], o);
    Bf = mda_analyzeChannel(S, 1, [0.5 29.5], mda_options(o, 'externalTrigger', 'off'));
    Sm = S; Sm.stim.time(end+1, 1) = 0.2; Sm.stim.channel(end+1, 1) = 3;   %one MyoDish pulse (channel 3)
    Bm = mda_analyzeChannel(Sm, 1, [0.5 29.5], o);
    Bo = mda_analyzeChannel(Sm, 1, [0.5 29.5], mda_options(o, 'externalTrigger', 'on'));
    okX = numel(S.stim.time) == 28 && all(S.stim.channel == 0) && all(S.stim.external) && ...
        max(abs(S.stim.time(:) - trig(:))) < 1e-9 && Ca.stimChannel == 0 && height(Ba) == 28 && nSt(Ba) == 28 && ...
        abs(median(Ba.stimToPeak) - 0.15) < 0.02 && nSt(Bf) == 0 && nSt(Bm) == 0 && nSt(Bo) == 28;
    fprintf(['external trigger pulses (bit 14 without channel): %d pulses read (expected 28, channel 0), stimulated ' ...
        'contractions: auto %d, off %d, auto with a MyoDish pulse %d, on %d (expected 28 / 0 / 0 / 28), stimToPeak %.3f s   %s\n'], ...
        numel(S.stim.time), nSt(Ba), nSt(Bf), nSt(Bm), nSt(Bo), median(Ba.stimToPeak), passStr(okX));
catch ME
    okX = false;
    fprintf('external trigger pulses: %s   FAILED\n', ME.message);
end
delete(mdd); delete(lg);
end

function s = passStr(pass)
if pass, s = 'ok'; else, s = 'FAILED'; end
end
