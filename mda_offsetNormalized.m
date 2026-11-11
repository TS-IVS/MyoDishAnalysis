function tf = mda_offsetNormalized(version)
%MDA_OFFSETNORMALIZED  Is the 'Offset' line of the log a normalized value (raw x factor of the output mode)?
%
%   tf = mda_offsetNormalized(version)   version = the 'programInfo' text of the log ('Version 2.2.9811.14999'),
%                                        its version number alone, or '' / [] if it is not known
%
%   The control software keeps the offset, the calibration and the force in normalized counts, raw x factor of the
%   output mode (Tom, 2026-11-11). That makes all three independent of the mode: the same force gives the same
%   normalized value in mode 0 and in the extended sensor mode, the calibration value (AU per mN) does not have to
%   change with the mode, and 'Detect offsets' works in any mode. What stays in the raw counts of the mode is the
%   sensor itself, i.e. the limits of its characteristic (mda_report, flags M and L) and the word limit.
%
%   From lab version 10e (2.2.9811) on, the 'Offset' line of the log holds that normalized value, so converting it
%   to uN takes the calibration alone (mda_calibrationFactor(..., false)). Up to 10d the line held the raw value of
%   the mode that was active when the offset was detected, so there the factor of that moment belongs to it. Without
%   a version (very old files) the answer is false, which is how MDA always read those files.
%
% TS 2026-11-11

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

tf = false;
if nargin < 1 || isempty(version), return; end
t = regexp(char(string(version)), '\d+(\.\d+)+', 'match', 'once');       %first dotted number of the text
if isempty(t), return; end
v = str2double(strsplit(t, '.'));
v = v(~isnan(v)); v(end+1:3) = 0;
tf = v(1) * 1e10 + v(2) * 1e6 + v(3) >= 2 * 1e10 + 2 * 1e6 + 9811;      %>= 2.2.9811 (lab round 10e)
end
