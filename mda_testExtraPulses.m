function ok = mda_testExtraPulses()
%MDA_TESTEXTRAPULSES  Self test of the stimulus assignment with extra pulses (onset gate, pre- / post-pulses, pulse table).
%
%   ok = mda_testExtraPulses()   prints the results of every case, returns true if all agree
%
% A temporary 9-channel .mdd file (400 Hz) with log file: one contraction per second in channel 1 (linear rise 100 ms,
% relaxation 300 ms, onset at k + 0.5 s), regular pulses (50 mA) and extra pulses (status channel bit 16) of
% channel 1. Log: pulse durations of channel 1 (1000 / 100 / 1000 us) and of extra pulse #1 (log channel 11: 3000 /
% 1000 / 3000 us), 'Sequence' entries with the programmed extra pulse 30 ms after the regular pulse.
%   k = 1-4, 12-14  regular pulse 30 ms before the onset
%   k = 5   CCM: regular pulse 70 ms, extra pulse (60 mA) 40 ms before the onset -> regular pulse, post-pulse t30
%   k = 6   sub-threshold pre-pulse (15 mA) 100 ms before the regular pulse -> regular pulse, pre-pulse t-100
%   k = 7   eliciting pre-pulse (20 mA) 30 ms before the onset, regular pulse 70 ms after the onset -> extra pulse,
%           elicitedByExtraPulse, the regular pulse is missed within the contraction (post-pulse t100)
%   k = 8   no pulse: extra beat
%   k = 9   regular pulse without contraction: missed beat (diastolic)
%   k = 10  extra pulse 5 ms before the regular pulse -> regular pulse, stimAmbiguous, pre-pulses t-1000 (the missed
%           pulse of k = 9, prePulseWindow 1 s) & t-5
%   k = 11  extra pulse only -> elicitedByExtraPulse
% Option stimAssignment 'peak' (versions <= 1.0.0-beta.3): extra pulses count as regular pulses.
%
% TS 2026-10-10

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

fs = 400; T = 16; n = T * fs; tt = (0:n-1) / fs;
X = zeros(9, n, 'int16');
F = 2000 * ones(1, n);
beats = setdiff(1:14, 9);
for k = beats
    a = k + 0.5;
    I = tt >= a & tt < a + 0.1; F(I) = 2000 + 1000 * (tt(I) - a) / 0.1;
    I = tt >= a + 0.1 & tt < a + 0.4; F(I) = 3000 - 1000 * (tt(I) - a - 0.1) / 0.3;
end
X(1,:) = int16(round(F));
P = zeros(0, 3);                                    %pulses: time, current, extra
for k = [1:4 12:14], P(end+1,:) = [k + 0.47, 50, 0]; end %#ok<AGROW>
P = [P; 5.43 50 0; 5.46 60 1; 6.37 15 1; 6.47 50 0; 7.47 20 1; 7.57 50 0; 9.47 50 0; 10.465 25 1; 10.47 50 0; ...
    11.47 30 1];
code = zeros(1, n, 'uint16');
for q = 1:size(P, 1)
    c = uint16(512) + uint16(P(q,2));               %channel 1 (bits 10-13), current (bits 1-8)
    if P(q,3), c = c + uint16(32768); end           %bit 16: extra pulse
    code(round(P(q,1) * fs) + 1) = c;
end
X(9,:) = typecast(code, 'int16');
base = [tempname '_xpulse'];
mdd = [base '.mdd']; lg = [base '_log.log'];
fid = fopen(mdd, 'w'); fwrite(fid, X, 'int16'); fclose(fid);
L = {'systemTime;dataLogTime;channel;code;value', '2026 01 01 06:00:00:000;0;0;nChannels;9', ...
    '2026 01 01 06:00:00:000;0;1;chargeDuration;1000', '2026 01 01 06:00:00:000;0;1;pauseDuration;100', ...
    '2026 01 01 06:00:00:000;0;1;dechargeDuration;1000', '2026 01 01 06:00:00:000;0;11;chargeDuration;3000', ...
    '2026 01 01 06:00:00:000;0;11;pauseDuration;1000', '2026 01 01 06:00:00:000;0;11;dechargeDuration;3000', ...
    '2026 01 01 06:00:00:000;0;0;Sequence;Sent stimPeriod 1000', ...
    '2026 01 01 06:00:00:000;0;1;Sequence;Added stimTime(s) 470 500#1', ...
    '2026 01 01 06:00:00:000;0;0;Recording;started: x.mdd', '2026 01 01 06:00:00:000;0;0;samplingRate Recording;400'};
for c = 1:8
    L{end+1} = sprintf('2026 01 01 06:00:00:000;0;%d;Calibration;1000', c); %#ok<AGROW>
    L{end+1} = sprintf('2026 01 01 06:00:00:000;0;%d;Offset;0', c); %#ok<AGROW>
end
L{end+1} = sprintf('2026 01 01 06:00:%02d:000;%d;0;Recording;stopped: x.mdd', T, T * 1000);
fid = fopen(lg, 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
ok = true;
try
    S = mda_readMdd(mdd, 0, T);
    o = mda_options('noFiltering', 'spikeRemoval', false);
    [B, C] = mda_analyzeChannel(S, 1, [0.8 15], o);
    Sm = mda_summarize(B, C, [0.8 15]);
    row = @(k) find(abs(B.t_onset - (k + 0.5)) < 0.003, 1);
    chk = {};
    % reader and log
    X1 = S.extraPulseLog;
    chk(end+1,:) = {'reader: 17 pulses, 5 extra pulses (bit 16)', numel(S.stim.time) == 17 && nnz(S.stim.isExtraPulse) == 5};
    chk(end+1,:) = {'log: programmed extra pulse +30 ms (Sequence)', any(X1(:,2) == 1 & X1(:,3) == 1 & abs(X1(:,4) - 30) < 1e-9)};
    chk(end+1,:) = {'log: pulse durations of channel 1 and 11', size(S.pulseSettingsLog, 1) == 6};
    % contractions
    chk(end+1,:) = {'13 contractions, 12 stimulated, 1 extra beat', height(B) == 13 && Sm.nStimulated == 12 && Sm.nExtraBeats == 1};
    chk(end+1,:) = {'onsets exact (+-3 ms)', all(arrayfun(@(k) ~isempty(row(k)), beats))};
    r = row(1);
    chk(end+1,:) = {'k=1: regular pulse, stimToOnset 30 ms, pulse ID, current, durations', ~B.elicitedByExtraPulse(r) && ...
        abs(B.stimToOnset(r) - 0.03) < 0.003 && B.stimPulse(r) == round(1.47 * fs) && B.stimCurrent(r) == 50 && ...
        isequal([B.stimChargeDuration(r) B.stimPauseDuration(r) B.stimDechargeDuration(r)], [1000 100 1000])};
    r = row(5);
    chk(end+1,:) = {'k=5 CCM: regular pulse, post-pulse t30|60|3000|1000|3000', abs(B.t_stim(r) - 5.43) < 1e-9 && ...
        ~B.elicitedByExtraPulse(r) && ~B.stimAmbiguous(r) && strcmp(B.postPulses{r}, 't30|60|3000|1000|3000') && isempty(B.prePulses{r})};
    r = row(6);
    chk(end+1,:) = {'k=6 sub-threshold pre-pulse: regular pulse, pre-pulse t-100|15|...', abs(B.t_stim(r) - 6.47) < 1e-9 && ...
        strcmp(B.prePulses{r}, 't-100|15|3000|1000|3000') && ~B.stimAmbiguous(r)};
    r = row(7);
    chk(end+1,:) = {'k=7 eliciting pre-pulse: elicitedByExtraPulse, post-pulse t100|50|...', B.elicitedByExtraPulse(r) && ...
        abs(B.t_stim(r) - 7.47) < 1e-9 && B.stimCurrent(r) == 20 && B.stimChargeDuration(r) == 3000 && ...
        strcmp(B.postPulses{r}, 't100|50|1000|100|1000')};
    r = row(8);
    chk(end+1,:) = {'k=8: extra beat', strcmp(B.beatType{r}, 'extra') && isnan(B.t_stim(r))};
    r = row(10);
    chk(end+1,:) = {'k=10: regular pulse, ambiguous, pre-pulses t-1000 (missed at k=9) & t-5', abs(B.t_stim(r) - 10.47) < 1e-9 && B.stimAmbiguous(r) && ...
        strcmp(B.prePulses{r}, 't-1000|50|1000|100|1000&t-5|25|3000|1000|3000')};
    r = row(11);
    chk(end+1,:) = {'k=11: extra pulse only -> elicitedByExtraPulse', B.elicitedByExtraPulse(r) && ~B.stimAmbiguous(r)};
    % summary
    chk(end+1,:) = {'summary: 12 stimuli, 2 missed (1 in a contraction), 5 extra pulses, 2 elicited by them, 1 ambiguous', ...
        Sm.nStimuli == 12 && Sm.nMissedBeats == 2 && Sm.nMissedDuringContraction == 1 && Sm.nExtraPulses == 5 && ...
        Sm.nElicitedByExtraPulse == 2 && Sm.nAmbiguous == 1};
    % pulse table
    Pt = C.pulses;
    q9 = find(abs(Pt.t - 9.47) < 1e-9, 1); q7 = find(abs(Pt.t - 7.57) < 1e-9, 1); q5 = find(abs(Pt.t - 5.46) < 1e-9, 1);
    chk(end+1,:) = {'pulse table: 17 rows, outcomes and roles', height(Pt) == 17 && nnz(strcmp(Pt.outcome, 'elicited')) == 12 && ...
        strcmp(Pt.outcome{q9}, 'noResponse') && strcmp(Pt.outcome{q7}, 'duringContraction') && strcmp(Pt.role{q7}, 'post') && ...
        Pt.tRel_ms(q7) == 100 && abs(Pt.phase(q7) - 0.07 / 0.37) < 0.02 && strcmp(Pt.role{q5}, 'post') && Pt.extra(q5) && ...
        Pt.pulse(q5) == round(5.46 * fs) && Pt.tRel_ms(q5) == 30};
    % option stimAssignment 'peak': extra pulses count as regular pulses
    Bp = mda_analyzeChannel(S, 1, [0.8 15], mda_options(o, 'stimAssignment', 'peak'));
    [~, Cp] = mda_analyzeChannel(S, 1, [0.8 15], mda_options(o, 'stimAssignment', 'peak'));
    chk(end+1,:) = {'peak assignment: 17 stimuli, no extra pulses', numel(Cp.stimTimes) == 17 && isempty(Cp.extraTimes) && ...
        ~any(Bp.elicitedByExtraPulse) && strcmp(Cp.stimAssignment, 'peak')};
    for q = 1:size(chk, 1)
        fprintf('%-100s %s\n', chk{q,1}, passStr(chk{q,2}));
        ok = ok && chk{q,2};
    end
catch ME
    ok = false;
    fprintf('extra pulses: %s   FAILED\n', ME.message);
end
delete(mdd); delete(lg);
if ok, disp('mda_testExtraPulses: all tests passed.'); else, warning('mda_testExtraPulses: TEST FAILED.'); end
end


function s = passStr(pass)
if pass, s = 'ok'; else, s = 'FAILED'; end
end
