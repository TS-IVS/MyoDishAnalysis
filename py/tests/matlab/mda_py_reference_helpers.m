function mda_py_reference_helpers(outFile)
%MDA_PY_REFERENCE_HELPERS  Reference values of MATLAB functions for the Python port (islocalmax, movmedian, movmean,
%gradient, round, median of single, colon).
%
%   mda_py_reference_helpers('helpers_reference.mat')
%
% Test signals with plateaus, equal peaks, NaN and short signals. Compared by tests/test_matlab_reference.py.
%
% TS 2026-10-06

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

rs = rng; rng(11);
X = {};
X{end+1} = cumsum(round(randn(1, 3000)));                         %integer random walk: many plateaus and equal peaks
X{end+1} = round(5 * sin((1:2000) / 7)) + round(randn(1, 2000));  %periodic, equal maxima, plateaus
x = randn(1, 2000); x(100:104) = 3; x(300) = x(299); x([500 520]) = 4; x(700:701) = 5; x(702) = 4.9; X{end+1} = x;
X{end+1} = [1 2 2 2 1 3 3 1 0 0 5 5 5 5 2 2 3];                   %short, hand-made
X{end+1} = [3 3 1 2 1 4 4];                                       %plateaus at the ends
X{end+1} = [1 3 1 3 1 3 1];                                       %equal peaks
X{end+1} = [0 5 1 5 2 5 0];
X{end+1} = 100 * sin((0:999) * 0.05) + 3 * randn(1, 1000);
TF = cell(size(X)); P = TF;
for k = 1:numel(X)
    [tf, p] = islocalmax(X{k});
    TF{k} = double(tf); P{k} = p;
end
% moving windows
y = 100 * randn(1, 1500); y(200) = NaN; y(400:410) = NaN; y(1) = NaN;
z = round(50 * randn(1, 1500));
win = [1 2 3 4 5 6 9 10 11];
MM = zeros(numel(win), numel(y)); MA = MM; MZ = MM; MZa = MM;
for k = 1:numel(win)
    MM(k,:) = movmedian(y, win(k), 'omitnan', 'Endpoints', 'shrink');
    MA(k,:) = movmean(y, win(k), 'omitnan', 'Endpoints', 'shrink');
    MZ(k,:) = movmedian(z, win(k), 'omitnan', 'Endpoints', 'shrink');
    MZa(k,:) = movmean(movmedian(z, win(k), 'omitnan', 'Endpoints', 'shrink'), 5, 'omitnan', 'Endpoints', 'shrink');
end
G = gradient(y);
R = round([-2.5 -1.5 -0.5 0.5 1.5 2.5 0.49999999999999994]);
s = single([1 5 2 8 3 9 4]); medS = median(s); medS2 = median(single([1 5 2 8 3 9]));
C1 = 0:0.005:20; C2 = 1.0954:0.002:1.3388; C3 = -0.002:0.0001:0.002;
rng(rs);
save(outFile, 'X', 'TF', 'P', 'y', 'z', 'win', 'MM', 'MA', 'MZ', 'MZa', 'G', 'R', 'medS', 'medS2', 'C1', 'C2', 'C3', '-v7');
fprintf('mda_py_reference_helpers: %s written\n', outFile);
end
