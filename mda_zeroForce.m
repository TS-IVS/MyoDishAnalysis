function [z, src, zeroT, zeroV] = mda_zeroForce(S, channel, zeroUser, t)
%MDA_ZEROFORCE  Zero force of a channel (sensor signal without load, uN) at the times t.
%
%   [z, src] = mda_zeroForce(S, channel, zeroUser, t)
%   [z, src, zeroT, zeroV] = mda_zeroForce(...)       also the step function (times zeroT, values zeroV)
%
%   S         file facts / data from mda_readMdd (offsetLog, calibration, extended sensor mode)
%   zeroUser  zero force entered by the user (uN); [] or NaN = 'Offset' entry of the channel in the log file
%             (written at the start of a recording, AU; 0 = not calibrated --> NaN). The log value is converted to
%             uN with mda_calibrationFactor, and whether the factor of the extended sensor mode belongs to it
%             depends on the version of the control software (mda_offsetNormalized): from lab version 10e on the
%             line is normalized (raw x factor) and the calibration alone converts it, up to 10d it was the raw
%             value of the mode that was active when the offset was detected, so there the factor at the time of
%             the entry belongs to it. The control software writes no new Offset line when the mode is switched
%             during a recording; the small step that the approximate factor leaves is noted in the report.
%   z         zero force at the times t (NaN = unknown), src text ('user', 'log', 'unknown', ...)
%
% TS 2026-10-04

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

if nargin < 4, t = []; end
zeroT = 0; zeroV = nan; src = 'unknown';
if ~isempty(zeroUser) && ~isnan(zeroUser(1))
    zeroV = zeroUser(1);
    src = 'user';
elseif isfield(S, 'offsetLog') && ~isempty(S.offsetLog)
    E = S.offsetLog(S.offsetLog(:,2) == channel, :);   %[time channel value]
    if ~isempty(E)
        [~, o] = sort(E(:,1)); E = E(o,:);
        v = E(:,3);
        v(v == 0) = nan;                               %0 = offset not calibrated
        if all(isnan(v))
            src = 'log: not calibrated (0)';
        else
            zeroT = E(:,1);
            withMode = true;                               %up to 10d: raw value of the mode of that moment
            if isfield(S, 'programVersion'), withMode = ~mda_offsetNormalized(S.programVersion); end
            zeroV = v .* reshape(mda_calibrationFactor(S, channel, zeroT, withMode), [], 1);
            src = 'log';
        end
    end
end
idx = ones(size(t));                                   %before the first entry: the first entry
for j = 2:numel(zeroT)
    idx(t >= zeroT(j)) = j;
end
z = reshape(zeroV(idx), size(t));
end
