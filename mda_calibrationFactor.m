function k = mda_calibrationFactor(H, channel, t)
%MDA_CALIBRATIONFACTOR  Factor AU --> uN of a data channel at the times t (step function of time).
%
%   k = mda_calibrationFactor(H, channel, t)     H = file facts from mda_readMdd, t = times in the file (s)
%
%   The values in an .mdd file are arbitrary units (AU):  uN = AU * k,  k = 1000 / calibrationEff(t).
%   calibrationEff = 'Calibration' entry of the channel in the log file (AU per mN, a kind of spring constant;
%   1000 if there is none), divided by H.extendedSensorFactor (3.3) while the extended sensor mode is on.
%   Examples: 1000 --> k = 1; 3000 --> k = 1/3; 1000 in extended sensor mode --> k = 3.3.
%   k = 1 everywhere if the calibration is not applied (option 'calibration','none': values as stored in the file).
%
% TS 2026-10-04

k = ones(size(t));
if ~H.calibrationApplied, return; end
cal = 1000 * ones(size(t));
E = zeros(0,3);
if ~isempty(H.calibrationLog)
    E = H.calibrationLog(H.calibrationLog(:,2) == channel & H.calibrationLog(:,3) > 0, :);
end
if ~isempty(E)
    [~, o] = sort(E(:,1)); E = E(o,:);            %stable: entries before the recording start (-Inf) keep the log order
    cal(:) = E(1,3);                              %the first entry also holds before its time
    for j = 2:size(E,1)
        cal(t >= E(j,1)) = E(j,3);
    end
end
for q = 1:size(H.extendedSensorIntervals,1)
    I = t >= H.extendedSensorIntervals(q,1) & t < H.extendedSensorIntervals(q,2);
    cal(I) = cal(I) / H.extendedSensorFactor;
end
k = 1000 ./ cal;
end
