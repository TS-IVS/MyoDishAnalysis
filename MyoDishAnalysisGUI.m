function figOut = MyoDishAnalysisGUI(mddFile, varargin)
%MYODISHANALYSISGUI  Interactive contraction analysis of a MyoDish recording (.mdd).
%
%   MyoDishAnalysisGUI            opens a file dialog
%   MyoDishAnalysisGUI(mddFile)
%   MyoDishAnalysisGUI(mddFile, metadata)   labels per channel (struct / table / file, see mda_labels)
%   MyoDishAnalysisGUI(resultsFile)         results of MyoDishAnalysis / watcher / GUI export (.xlsx, _info.csv):
%                                           recording, settings and analysis window restored (mda_readResults)
%   MyoDishAnalysisGUI(file, 'channel', c, 'window', [from to])   opens the recording or results file at channel c and
%                                           loads the window from ... to s (commands of the analysis report,
%                                           mda_report; results file: its settings and the analysis window of this
%                                           channel; 2026-10-11)
%
% Labels per channel (setupID, sliceID, species, sampleID, sampleGroup, sliceGroup, tissue, treatment, concentration,
% concentrationUnit, daysInCulture, cultureStart, comment, analyst): button 'Labels ...' (editable table, load / save as .csv). A file
% <name>_labels.csv next to the .mdd file is loaded automatically. The labels become columns of the exported tables.
%
% 0. 'Open ...': a recording (.mdd; its first 120 s are loaded and analysed right away) or results of an analysis
%    (see 3.); the folder is remembered (2026-10-14). 'Results ...': results browser of a results folder of the watcher
%    (mda_index.csv, mda_flags.csv): one row per recording and channel with the flags of the watcher report (list:
%    all / with flags / red flags / not analysed; search); double-click opens the channel with the settings of its
%    analysis (red flags: the window of the flags, otherwise the first 120 s); 'Compute flags' for results of older
%    watcher versions. 'Main file' (shown for a parallel recording, e.g. a schedule file): the main recording at the
%    window shown. Grey line above the table: flags of the watcher report for the analysed range (mda_report).
%    'Comments ...': searchable list of the comments of the log file (number, date and time, time in the file, text);
%    a selected row is highlighted in the force plot, double-click (or Go to) loads the data around the comment.
%    Comments are numbered purple marks in the force plot (pointer: text; click: selected in the list).
% 1. 'Overview' shows the complete recording of the selected channel (min/max envelope, green =
%    rocker at rest; the unit of the time axis left of it, e.g. (h:mm); from 2 days 'd h:mm'). Drag in the overview (or
%    type From/To and press Load) to load a time window; right click: 'Select all' loads the range shown (at most 4 h).
%    Mouse wheel over the overview or the force plot: zoom the time axis (shift + wheel: move); double-click:
%    whole file / whole loaded window. The zoomed overview is re-read in more detail.
%    Arrow keys (click into a plot first) and the buttons under the force plot change the loaded window (= the blue
%    selection in the overview and the analysed range; read again): left / right = move it by half its length, shift
%    + left / right (shift + click) = extend it by half its length on that side, up / down (middle buttons) = zoom in
%    / out (half / twice its length). Mouse pointer over the overview: the keys move its time axis instead; a zoomed
%    overview moves along when the window leaves its visible part. The mouse wheel zooms only the display.
% 2. The force plot shows the loaded window (force - zero force, if the zero force is known): detected contractions
%    (red = selected, orange = uncertain (high sensitivity), grey = excluded by the filters, black x = excluded by
%    you), stimuli (blue ticks), rocker state (thin bar at the top: green = at rest, grey = moving; 2026-10-14, before:
%    grey background). The stimulus plot below shows the current of every
%    stimulus pulse (mA; green = extra pulse, x = current not reached) and the interval to the previous pulse of the
%    channel (ms); numbers are written when 40 pulses or fewer are visible (zoom in).
%    Cursor mode 'drag = select time range': drag in the force plot to choose the analysed range; shift + drag adds
%    another range (several ranges: the table and exports pool them, exports add one summary row per range;
%    2026-10-14). Right click in the force plot: 'Zoom to the selection'; with 'only contractions with rocker at
%    rest': 'Select all rocker stops of the overview range' reads every rocker stop (+-2 s) of the range shown in the
%    overview (also days with hourly stops) and shows them side by side, separated by dashed lines (time axis: time in
%    the file; exports: time in the file). Load a window to return to the continuous view.
%    Cursor mode 'click = exclude / include contraction': click on a contraction to exclude it (or include it again).
%    Zoom / pan with the figure toolbar (switch the zoom / pan tool off again to use the mouse modes).
% 3. The table shows mean and SD of the selected contractions; the lower plot shows one parameter (list 'Lower plot') per
%    contraction over time. 'Export this channel' writes all contractions of the range (column 'included')
%    (every export also contains the table info: version, recording, all settings, window and range; 'Open ...'
%    or MyoDishAnalysisGUI(resultsFile) restores recording, settings and analysis window of a results file of
%    MyoDishAnalysis, the watcher or the GUI and compares the contractions detected again with the file)
%    and the summary to .xlsx or .csv. 'All channels -> file' analyses the range in all channels with the
%    same settings (without your manual exclusions). The detection threshold is set per channel (auto or manual).
%    'high sensitivity' (default) counts all contractions and marks the uncertain ones (orange); 'high specificity'
%    does not count them (mda_options 'detection'). 'Rocker artifact ...': extra window with the signal before / after
%    the rocker filter and the removed periodic artifact; save as figure, export the data.
%    'Advanced ...' (2026-10-10): all parameters of the method that are based on assumptions or experience
%    (mda_options), one tab per part of the analysis: stimulus assignment (onset gate: gateMax, gateCore,
%    gateTolerance, ambiguityWindow, rise phases, pre- / post-pulses; or 'peak' as in versions <= 1.0.0-beta.3) and
%    stimulus source, detection and certainty, noise and artifact rules, rocker rules, signal (filters, spike
%    removal), rocker filter, export. Guide: settings guide docs/MyoDishAnalysis_settings_guide.pdf (figures for every
%    parameter and the markers of the force plot). Defaults restores mda_options(); Apply / OK analyse the window
%    again. Save settings ... / Load settings ...: settings file (mda_settings; results of an analysis can be loaded,
%    too). Changed settings (2026-10-14): the button shows their number in red ('Advanced (3 changed)', shortened if
%    the text does not fit, e.g. 'Adv. (3 chgd)'); its tooltip lists them with their defaults. Force plot: legend of
%    the markers (menu View; right click in the force plot): extra pulses (status channel bit 16: pre-pulses, CCM
%    pulses, ...) green ticks, contractions elicited by an extra pulse green rings, ambiguous stimulus assignments
%    black diamonds.
%    'Trend ...': rolling mean / median of a parameter over long periods, also over several files in a row; one
%    channel or several channels overlaid (channel list: 'several channels ...'). Comments of the log files: numbered
%    markers above the plot and a list below it (click a marker or a line of the list, or point at a marker, to
%    highlight the comment; 2026-10-13).
%    'Overlay contractions': mean beat of the selected contractions (aligned at the stimulus or the peak) or the time
%    course of the range (t = 0 at the first stimulus); other channels of the same range by checkboxes; colour, line
%    width, line style and SD / SEM / range band per group; editable title, axis labels and legend; 'Edit figure ...'
%    = copy with the MATLAB plot tools.
%
% 4. '+ EP recording ...': an electrophysiological recording made in parallel with LabChart (.mat export, e.g. sharp
%    electrode: voltage + stimulation channel) is aligned to the stimuli of the .mdd file (mda_readEPRecording:
%    stimulus pattern, current, clock times, clock drift) and shown below the plots with the same time axis (the window
%    grows downwards). 'Remove EP recording' hides it. With an EP recording every contraction gets the parameters of
%    its action potential (mda_analyzeAP: AP_dVdtMax, AP_RMP, AP_Vmax, APD25/50/90, AP_note; table, lower plot,
%    exports); markers in the EP plot when <= 60 contractions are visible. EP plots: drag up / down = y limits,
%    double-click = automatic, right click = type the y limits / automatic (restore view); 'remove stimulus artefact'
%    replaces the pulses and the artefact after them by straight lines (grey; display only, mda_analyzeAP
%    'removeArtefacts': the AP parameters are measured on the recorded signal).
%    Mouse pointer over the force, stimulus, parameter or EP plots: a marker on the curve in every plot and the value at
%    that time small in its top left corner (force, nearest stimulus pulse, parameter of the nearest contraction, EP
%    signal and stimulation); the plot under the pointer also shows the time and the time since the last stimulus.
%    The windows always use light colors (also with a dark theme of MATLAB / the operating system); accent color blue
%    for the main buttons, the panel titles, the stimulus pulses and the loaded window (2026-10-13).
% 5. 'Protocols ...': stimulation protocols found in the log file (comments 'start ... protocol' / 'end ... protocol',
%    mda_protocols; editable, '+ selected range' adds the range of the main window): the contractions of the ticked
%    protocols and channels are grouped by pacing frequency, S2 interval, stimulus current, rest interval, pulse
%    duration, rocker speed or any numeric log entry (mda_groupBeats); summary per group, plot of a parameter against
%    the quantity (mean +- SD / SEM), export. Default: only contractions with the rocker at rest.
%
% Parameter definitions: mda_parameters / README. Command line version: MyoDishAnalysis.
% Requires MATLAB R2019b or newer, no toolboxes.
% Thomas Seidel (FAU Erlangen-Nuernberg / InVitroSys GmbH), 2026-10-05 (EP recordings 2026-10-06, protocols 2026-10-07;
% threshold per channel, arrow keys, overlay of channels / styles / bands 2026-10-07; navigation buttons, trend of several
% channels, detection mode, open results, rocker artifact window, EP y limits / artefact removal, mouse pointer values
% 2026-10-09; advanced settings, settings files, legend of the force plot 2026-10-10; report, channel / window 2026-10-11;
% colours 2026-10-13; first window loaded, results browser, parallel recordings, numbered comments, flags 2026-10-14)

% MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
% Copyright (c) 2026 Thomas Seidel
% SPDX-License-Identifier: GPL-3.0-or-later
% Additional terms (GPL-3.0 section 7): see the file NOTICE

if nargin < 1, mddFile = ''; end
metadata = []; goCh = []; goWin = [];             %name / value pairs 'channel', 'window' (2026-10-11)
args = varargin;
if mod(numel(args), 2) == 1, metadata = args{1}; args = args(2:end); end
for iArg = 1:2:numel(args)
    switch lower(char(args{iArg}))
        case 'channel',  goCh = double(args{iArg+1});
        case 'window',   goWin = double(args{iArg+1});
        case 'metadata', metadata = args{iArg+1};
        otherwise, error('MyoDishAnalysisGUI: unknown option ''%s'' (channel, window, metadata)', char(args{iArg}));
    end
end

% ------------------------------------------------------------------ state (shared by the nested functions)
H = []; S = []; O = []; B = []; C = [];
reportAll = false;                                 %analysis report with 'All channels -> file' (menu Save / Export)
ch = 1;
range = [nan nan];                 %analysed range(s): rows [from to] in s (several: shift + drag, 2026-10-14)
sbs = [];                          %side-by-side rocker stops (2026-10-14): seg [fileFrom fileTo winFrom winTo], shift,
                                   %  breaks (window times of the dashed lines); [] = continuous window
winReq = [nan nan];                %loaded window as requested from mda_readMdd (s; exports: open the results again)
resOnly = [];                      %opened results file: t_peak of its contractions not detected again (black o)
hRA = [];                          %rocker artifact window
apiFile = '';                      %scripts / tests: file name for the next save / export dialog (api.nextFile)
resInfo = '';                      %opened results file: comparison shown in the status line
manualOff = zeros(0,1);            %t_peak of the contractions excluded by the user
zeroUser = nan(1, 8);              %zero force per channel entered by the user (NaN = 'Offset' of the log file)
thrUser = nan(1, 8);               %detection threshold per channel entered by the user (NaN = auto)
Lbl = [];                          %labels per channel (table, see mda_labels)
relTime = false;                   %time axes of the loaded window: 0 = start of the window (display only)
hLblFig = [];
LE = [];                           %entries of the log file (mda_logEntries): comments, events, settings
hCom = [];                         %comment window (uifigure) and its controls
comView = []; comRow = [];         %rows of LE shown in the comment window, selected row
hiT = nan;                         %time of the comment last jumped to (highlighted)
comT = []; comK = []; comIdx = []; %comments in the force plot: time, number (1..n of the file), row of LE (2026-10-14)
comTF = [];                        %  ... their times in the file (side-by-side rocker stops: comT is condensed)
comNumH = gobjects(0);             %  ... their numbers (text objects; overlapping ones hidden)
mainRec = [];                      %main recording of an open parallel recording (main, a, b; 2026-10-14)
hBrw = [];                         %results browser (uifigure and its controls; 2026-10-14)
statusText = '';                   %last message of the status line
ovG = [];                          %overlay: one group per added selection (segments around the contractions)
hOv = [];                          %overlay window and its controls
ovNextColor = 0;                   %overlay: number of groups added (default colour of the next group)
ovLineStyles = {'-', '--', ':', '-.'}; ovLineNames = {'solid', 'dashed', 'dotted', 'dash-dot'};
ovBands = {'none', 'SD', 'SEM', 'range'};
ovBandNames = {'no band', 'band: mean +- SD', 'band: mean +- SEM', 'band: range (min - max)'};
ovLegendNames = {'top right', 'top left', 'bottom right', 'bottom left', 'off'};
ovLegendLoc = {'northeast', 'northwest', 'southeast', 'southwest', ''};
lastDir = '';                      %folder of the last saved figure / exported data
altPt = [nan nan];                 %force plot: position of the last right click (x = s, y = displayed force)
hTr = []; trFiles = []; trData = []; trCache = [];   %trend window: handles, files (concatenated), contractions, cache
hPr = []; prRes = [];              %protocol window: handles; results (contractions, summary, info)
trSampling = '';                   %trend: description of the sampling of the last calculation
trChans = []; trMulti = [];        %trend: channels shown (several = overlaid); last set of several channels
refThr = 3;                        %reference beat: a contraction deviates if its deviation > refThr SD
refWhich = 2;                      %  ... measured 1 = absolute, 2 = normalized to amplitude 1 (shape), 3 = either
refExclude = false;                %  deviating contractions excluded from the selection
refAlign = 'stimulus';             %  alignment of new references: 'stimulus' (latency counts) or 'upstroke' (shape only)
hRef = [];                         %reference beat window
EP = [];                           %EP recording (LabChart) aligned to the .mdd file (mda_readEPRecording)
axEPv = gobjects(0); axEPs = gobjects(0); hEPtxt = gobjects(0); hEPclose = gobjects(0);
epFrac = 0;                        %fraction of the figure height used by the EP traces (0 = hidden)
epBusy = false;                    %guard: redrawing the EP traces
epFig0 = [];                       %figure size before / after showing the EP traces, layout factors
epLis = [];                        %listener: redraw the EP traces when the time axis changes
epMarks = [];                      %AP markers of the analysed window (mda_analyzeAP)
epYLim = {[], []};                 %EP plots: y limits of the signal (V_m) and the stimulation ([] = automatic; 2026-10-09)
epClean = false;                   %EP: stimulus artefacts removed in the signal plot (display, mda_analyzeAP removeArtefacts)
epVc = []; epArtMask = [];         %  ... signal without the artefacts, replaced samples (EP recording shown)
hEPclean = gobjects(0);            %  ... checkbox
dragY0 = [];                       %EP plots: drag = y limits
hvF = []; hvS = [];                %mouse pointer: plotted force (t, y) and stimulus pulses (t, current, interval, ok)
hvShown = false;                   %  ... markers visible
rfCtx = [];                        %rocker filter: context data around the loaded window (+-60 s)
rfCache = {};                      %rocker filter: per channel {key, artifact, result}
rfF0 = [];                         %rocker filter: rocker frequency of the loaded window ([rpm Hz] rows)
opts = mda_options();
PI = mda_parameters();
plotList = [PI(:,1:2); {'stimToPeak', 's'; 'prominence', 'uN'}];   %parameters of the lower plot (name, unit)
relBase = PI(~startsWith(PI(:,1), 'ref'), 1);                      %2026-10-06: relative to the reference beat
relDiff = ismember(relBase, {'diastolicForce', 'diastolicSignal'});
relName = strcat(relBase, '_pctRef'); relName(relDiff) = strcat(relBase(relDiff), '_dRef');
relUnit = repmat({'% of ref'}, numel(relBase), 1); relUnit(relDiff) = {'uN, diff. to ref'};
plotList = [plotList; [relName, relUnit]];
APP = mda_analyzeAP('parameters');                                %2026-10-06: AP parameters of an EP recording
plotList = [plotList; APP(:, 1:2)];
mu = char(181);                    %micro sign
dragX0 = []; hDrag = [];
dragAdd = false;                   %drag in the force plot with shift: the range is added to the selection (2026-10-14)
Od = [];                           %detailed overview of a zoomed part of the file
ovXL = [];                         %time axis of the overview ([] = whole file)
tmr = [];                          %timer: reads the detailed overview after zooming
shiftDown = false;                 %shift key held (shift + click on the arrow buttons under the force plot)
hAdv = [];                         %advanced settings window (2026-10-10)
advD = {}; advCtl = gobjects(0); advMsg = [];   %  ... its definitions, controls, message line
advPending = struct();              %  ... settings of the main window loaded from a settings file (applied at Apply / OK)
showLegend = true;                 %legend of the markers in the force plot (menu View; 2026-10-10)
uiBlue = [29 114 185] / 255;       %accent colors of the user interface (2026-10-13; as widgets.py): main buttons,
uiBlueDark = [21 90 148] / 255;    %  panel titles, stimulus pulses and the loaded window; status texts;
uiBlueLight = [187 212 234] / 255; %  panel borders
pnlStyle = {'ForegroundColor', uiBlue, 'HighlightColor', uiBlueLight};
mainBtn = {'BackgroundColor', uiBlue, 'ForegroundColor', 'w', 'FontWeight', 'bold'};   %main action of a window

% ------------------------------------------------------------------ figure and controls
fig = figure('Name', 'MyoDishAnalysis', 'NumberTitle', 'off', 'Color', 'w', 'Units', 'pixels', ...
    'Position', [40 40 1450 880], 'MenuBar', 'none', 'ToolBar', 'figure', 'WindowButtonDownFcn', @onMouseDown, ...
    'WindowButtonMotionFcn', @onMouseMove, 'WindowScrollWheelFcn', @onScroll, 'WindowKeyPressFcn', @onKey, 'WindowKeyReleaseFcn', @onKeyRelease, ...
    'DeleteFcn', @onClose);
lightTheme(fig);
movegui(fig, 'onscreen');
dflt = {'Units', 'normalized', 'FontSize', 10, 'BackgroundColor', 'w'};

uicontrol(fig, dflt{:}, 'Style', 'pushbutton', 'String', 'Open ...', 'Position', [0.005 0.955 0.065 0.035], 'Callback', @onOpen, ...
    'TooltipString', ['a recording (.mdd) or results of an analysis (.xlsx, _info.csv, ...: recording, settings and ' ...
    'analysis window are restored, the contractions detected again and compared with the file); the folder is remembered']);
uicontrol(fig, dflt{:}, 'Style', 'pushbutton', 'String', 'Results ...', 'Position', [0.156 0.955 0.07 0.035], 'Callback', @(~,~) onBrowse(), ...
    'TooltipString', ['results browser: the recordings and channels of a results folder of the watcher with the flags of ' ...
    'the analysis report; double-click opens them']);
uicontrol(fig, dflt{:}, 'Style', 'pushbutton', 'String', '+ EP recording ...', 'Position', [0.072 0.955 0.08 0.035], 'Callback', @onOpenEP, ...
    'TooltipString', 'add an electrophysiological recording (LabChart .mat export, e.g. sharp electrode: voltage + stimulation) aligned to the stimuli of the open .mdd file');
hFile = uicontrol(fig, dflt{:}, 'Style', 'text', 'String', 'no file', 'HorizontalAlignment', 'left', 'Position', [0.229 0.952 0.131 0.03]);
hMain = uicontrol(fig, dflt{:}, 'Style', 'pushbutton', 'String', 'Main file', 'Position', [0.318 0.955 0.042 0.035], ...
    'Visible', 'off', 'Callback', @(~,~) onMainFile());   %parallel recording: opens the main file at this window
uicontrol(fig, dflt{:}, 'Style', 'text', 'String', 'Channel', 'HorizontalAlignment', 'right', 'Position', [0.36 0.952 0.04 0.03]);
hCh = uicontrol(fig, dflt{:}, 'Style', 'popupmenu', 'String', {'-'}, 'Position', [0.405 0.957 0.1 0.033], 'Callback', @onChannel);
uicontrol(fig, dflt{:}, 'Style', 'text', 'String', 'From (s)', 'HorizontalAlignment', 'right', 'Position', [0.505 0.952 0.04 0.03]);
hFrom = uicontrol(fig, dflt{:}, 'Style', 'edit', 'String', '0', 'Position', [0.548 0.957 0.055 0.033]);
uicontrol(fig, dflt{:}, 'Style', 'text', 'String', 'To (s)', 'HorizontalAlignment', 'right', 'Position', [0.603 0.952 0.03 0.03]);
hTo = uicontrol(fig, dflt{:}, 'Style', 'edit', 'String', '60', 'Position', [0.636 0.957 0.055 0.033]);
uicontrol(fig, dflt{:}, mainBtn{:}, 'Style', 'pushbutton', 'String', 'Load', 'Position', [0.695 0.955 0.045 0.035], 'Callback', @onLoad);
uicontrol(fig, dflt{:}, 'Style', 'pushbutton', 'String', 'Overview', 'Position', [0.744 0.955 0.05 0.035], 'Callback', @onOverview, ...
    'TooltipString', 'overview of the whole file (min/max envelope)');
uicontrol(fig, dflt{:}, 'Style', 'pushbutton', 'String', 'Comments ...', 'Position', [0.797 0.955 0.05 0.035], 'Callback', @onComments, ...
    'TooltipString', 'searchable list of the comments in the log file; double-click = go to');
uicontrol(fig, dflt{:}, 'Style', 'pushbutton', 'String', 'Protocols ...', 'Position', [0.85 0.955 0.05 0.035], 'Callback', @onProtocols, ...
    'TooltipString', ['stimulation protocols of the log file (FFR, refractory period, threshold, post-rest potentiation ...): ' ...
    'contractions grouped by pacing frequency, S2 interval, current, rest interval ...']);
hInfo = uicontrol(fig, dflt{:}, 'Style', 'text', 'String', '', 'HorizontalAlignment', 'left', 'Position', [0.903 0.942 0.096 0.05], ...
    'FontSize', 7);                                 %file facts (2 lines): smaller, so that they fit

axOv = axes(fig, 'Position', [0.05 0.845 0.70 0.075], 'FontSize', 9);
axMain = axes(fig, 'Position', [0.05 0.477 0.70 0.318], 'FontSize', 10, 'XTickLabel', {});
axStim = axes(fig, 'Position', [0.05 0.315 0.70 0.105], 'FontSize', 9, 'XTickLabel', {});
axPar = axes(fig, 'Position', [0.05 0.07 0.70 0.2], 'FontSize', 10);
% buttons under the force plot (as the arrow keys): loaded window (selection) left / right (shift + click: extend), zoom in / out
nb = {'Style', 'pushbutton', 'Units', 'normalized', 'FontSize', 9, 'BackgroundColor', 'w'};
hNavL = uicontrol(fig, nb{:}, 'String', char(9664), 'Position', [0.05 0.4485 0.022 0.026], 'Callback', @(~,~) onNavButton('leftarrow'), ...
    'TooltipString', 'loaded window (selection): move it to the left by half its length (shift + click: extend it to the left; key: left arrow)');
uicontrol(fig, nb{:}, 'String', char([8594 8592]), 'Position', [0.373 0.4485 0.026 0.026], 'Callback', @(~,~) onNavButton('uparrow'), ...
    'TooltipString', 'loaded window (selection): zoom in to half its length around the centre (key: up arrow)');
uicontrol(fig, nb{:}, 'String', char([8592 8594]), 'Position', [0.401 0.4485 0.026 0.026], 'Callback', @(~,~) onNavButton('downarrow'), ...
    'TooltipString', 'loaded window (selection): zoom out to twice its length (key: down arrow)');
uicontrol(fig, nb{:}, 'String', char(9654), 'Position', [0.728 0.4485 0.022 0.026], 'Callback', @(~,~) onNavButton('rightarrow'), ...
    'TooltipString', 'loaded window (selection): move it to the right by half its length (shift + click: extend it to the right; key: right arrow)');
uicontrol(fig, 'Style', 'text', 'Units', 'normalized', 'FontSize', 10, 'BackgroundColor', 'w', 'String', 'Lower plot:', ...
    'HorizontalAlignment', 'right', 'Position', [0.05 0.272 0.05 0.025]);
hPar = uicontrol(fig, 'Style', 'popupmenu', 'Units', 'normalized', 'FontSize', 10, 'BackgroundColor', 'w', ...
    'String', cellfun(@(n, u) sprintf('%s (%s)', n, strrep(u, 'u', char(181))), plotList(:,1), plotList(:,2), 'UniformOutput', false), ...
    'Position', [0.103 0.274 0.17 0.027], 'Callback', @(~,~) plotParam(), ...
    'TooltipString', 'parameter of every contraction shown in the lower plot (red = selected contractions)');
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', 'FontSize', 10, 'String', 'Trend ...', ...
    'Position', [0.278 0.273 0.05 0.029], 'Callback', @onTrend, 'TooltipString', ...
    'rolling average of a parameter over long periods, also over several .mdd files (e.g. _0, _1, _2 ...) in a row');
hStimTxt = gobjects(0);
for ax = [axOv axMain axStim axPar]
    try disableDefaultInteractivity(ax); catch, end
    box(ax, 'on');
end
% save plots (.fig / .png / .jpg / .tif) and export the plotted data (.xlsx / .csv / .txt): menu and right click
mExp = uimenu(fig, 'Text', 'Save / Export');
uimenu(mExp, 'Text', 'Save all plots (.png / .jpg / .tif / .fig) ...', 'MenuSelectedFcn', @(~,~) savePlots('all'));
uimenu(mExp, 'Text', 'Save window as shown (screenshot .png / .jpg / .tif) ...', 'MenuSelectedFcn', @(~,~) savePlots('window'));
uimenu(mExp, 'Text', 'Save overview ...', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) savePlots('overview'));
uimenu(mExp, 'Text', 'Save force plot ...', 'MenuSelectedFcn', @(~,~) savePlots('force'));
uimenu(mExp, 'Text', 'Save stimulus plot ...', 'MenuSelectedFcn', @(~,~) savePlots('stimuli'));
uimenu(mExp, 'Text', 'Save parameter plot ...', 'MenuSelectedFcn', @(~,~) savePlots('parameter'));
uimenu(mExp, 'Text', 'Export data of the force plot (.xlsx / .csv / .txt) ...', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) exportPlotData('force'));
uimenu(mExp, 'Text', 'Export data of the stimulus plot ...', 'MenuSelectedFcn', @(~,~) exportPlotData('stimuli'));
uimenu(mExp, 'Text', 'Export data of the parameter plot ...', 'MenuSelectedFcn', @(~,~) exportPlotData('parameter'));
uimenu(mExp, 'Text', 'Rocker artifact (removed signal) ...', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) onRockerWindow());
hRepMenu = uimenu(mExp, 'Text', 'Analysis report (PDF) with ''All channels -> file''', 'Separator', 'on', ...
    'Checked', 'off', 'MenuSelectedFcn', @(~,~) toggleReport());
mView = uimenu(fig, 'Text', 'View');
hLegMenu = uimenu(mView, 'Text', 'Legend of the force plot', 'Checked', 'on', 'MenuSelectedFcn', @(~,~) toggleLegend());
axNames = {'overview', 'force', 'stimuli', 'parameter'};
axList = [axOv axMain axStim axPar];
for iAxMenu = 1:4                                    %(unique names: variables of the main function are shared with the nested functions)
    cmAxMenu = uicontextmenu(fig);
    if iAxMenu == 1                                  %overview: load the range shown (2026-10-14)
        uimenu(cmAxMenu, 'Text', 'Select all (load the range shown, at most 4 h)', 'MenuSelectedFcn', @(~,~) selectAll());
    end
    if iAxMenu == 2                                  %force plot: zero force = y value of the right click
        uimenu(cmAxMenu, 'Text', 'Zoom to the selection (analysed range)', 'MenuSelectedFcn', @(~,~) zoomToSelection());
        uimenu(cmAxMenu, 'Text', 'Select all rocker stops of the overview range (side by side)', 'Tag', 'rockerStops', ...
            'MenuSelectedFcn', @(~,~) selectRockerStops());
        uimenu(cmAxMenu, 'Text', 'Shift + drag: add a range to the selection', 'Enable', 'off');
        uimenu(cmAxMenu, 'Text', 'Set as zero force (y at the mouse pointer)', 'Tag', 'zeroHere', 'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) setZeroAtClick());
        uimenu(cmAxMenu, 'Text', 'Zero force from the log file (Offset)', 'MenuSelectedFcn', @(~,~) resetZero());
        uimenu(cmAxMenu, 'Text', 'Set mean beat shape of the selected contractions as reference', 'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) setReference());
        uimenu(cmAxMenu, 'Text', 'Show reference beat / deviating contractions ...', 'MenuSelectedFcn', @(~,~) showReference());
        uimenu(cmAxMenu, 'Text', 'Remove reference beat of this channel', 'MenuSelectedFcn', @(~,~) clearReference());
        uimenu(cmAxMenu, 'Text', 'Show rocker artifact (removed signal) ...', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) onRockerWindow());
        uimenu(cmAxMenu, 'Text', 'Show / hide legend', 'MenuSelectedFcn', @(~,~) toggleLegend());
        try cmAxMenu.ContextMenuOpeningFcn = @(src,~) zeroMenuText(src); catch, end   %R2020a+
    end
    hSaveAxMenu = uimenu(cmAxMenu, 'Text', 'Save this plot (.png / .jpg / .tif / .fig) ...', 'MenuSelectedFcn', @(~,~) savePlots(axNames{iAxMenu}));
    if iAxMenu == 2, hSaveAxMenu.Separator = 'on'; end
    if iAxMenu > 1, uimenu(cmAxMenu, 'Text', 'Export data of this plot (.xlsx / .csv / .txt) ...', 'MenuSelectedFcn', @(~,~) exportPlotData(axNames{iAxMenu})); end
    uimenu(cmAxMenu, 'Text', 'Save all plots ...', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) savePlots('all'));
    axList(iAxMenu).UIContextMenu = cmAxMenu;
end

pnl = uipanel(fig, 'Position', [0.765 0.01 0.232 0.925], 'Title', 'Analysis', 'BackgroundColor', 'w', 'FontSize', 10, pnlStyle{:});
bg = uibuttongroup(pnl, 'Position', [0.03 0.885 0.94 0.105], 'Title', 'Cursor in the force plot', 'BackgroundColor', 'w', 'FontSize', 9, pnlStyle{:});
rbRange = uicontrol(bg, dflt{:}, 'Style', 'radiobutton', 'String', 'drag = select time range', 'Position', [0.03 0.52 0.94 0.42]);
uicontrol(bg, dflt{:}, 'Style', 'radiobutton', 'String', 'click = exclude / include contraction', 'Position', [0.03 0.06 0.94 0.42]);
uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'Labels ...', 'Position', [0.03 0.835 0.46 0.04], 'Callback', @onLabels, ...
    'TooltipString', 'labels per channel: setupID, sliceID, species, sampleID, groups, treatment, days in culture, analyst ...');
uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'Range = loaded window', 'Position', [0.51 0.835 0.46 0.04], 'Callback', @onWholeWindow);
thrTip = ['minimum prominence of a contraction peak, per channel: auto or a manual value for the selected channel ' ...
    '(kept when you switch channels; also used for All channels, Protocols and Trend)'];
uicontrol(pnl, dflt{:}, 'Style', 'text', 'String', ['Threshold, this ch. (' mu 'N)'], 'HorizontalAlignment', 'left', 'Position', [0.03 0.79 0.5 0.03], ...
    'TooltipString', thrTip);
hThrMode = uicontrol(pnl, dflt{:}, 'Style', 'popupmenu', 'String', {'auto','manual'}, 'Position', [0.52 0.795 0.22 0.035], 'Callback', @onThreshold, ...
    'TooltipString', thrTip);
hThr = uicontrol(pnl, dflt{:}, 'Style', 'edit', 'String', '', 'Position', [0.76 0.795 0.21 0.035], 'Callback', @onThresholdValue, ...
    'TooltipString', thrTip);
uicontrol(pnl, dflt{:}, 'Style', 'text', 'String', ['Zero force (' mu 'N)'], 'HorizontalAlignment', 'left', 'Position', [0.03 0.75 0.5 0.03], ...
    'TooltipString', 'sensor signal without load; diastolic force = diastolic signal - zero force. Empty = Offset entry of the log file');
hZero = uicontrol(pnl, dflt{:}, 'Style', 'edit', 'String', '', 'Position', [0.52 0.755 0.22 0.035], 'Callback', @onZero, ...
    'TooltipString', 'empty = Offset entry of the log file');
hZeroSrc = uicontrol(pnl, dflt{:}, 'Style', 'text', 'String', '', 'HorizontalAlignment', 'left', 'Position', [0.76 0.75 0.23 0.03], 'FontSize', 8);
hRocker = uicontrol(pnl, dflt{:}, 'Style', 'checkbox', 'String', 'only contractions with rocker at rest', 'Position', [0.03 0.715 0.94 0.035], 'Callback', @onFilter);
hStim = uicontrol(pnl, dflt{:}, 'Style', 'checkbox', 'String', 'only stimulated contractions', 'Position', [0.03 0.68 0.585 0.035], 'Callback', @onFilter);
advTip0 = ['advanced settings: stimulus assignment (onset gate), stimulus source (MyoDish / external trigger), ' ...
    'detection and filter parameters, pulse table (for users who know the method; see mda_options)'];
hAdvBtn = uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'Advanced ...', 'Position', [0.615 0.68 0.355 0.037], ...
    'Callback', @onAdvanced, 'TooltipString', advTip0);   %number of changed settings in red (advIndicator, 2026-10-14)
hRF = uicontrol(pnl, dflt{:}, 'Style', 'checkbox', 'String', 'remove rocker artifact', 'Position', [0.03 0.645 0.585 0.033], ...
    'Callback', @onRockerFilter, 'TooltipString', ['subtracts the periodic signal of the rocker movement (estimated per channel ' ...
    'between the contractions, +-60 s around the window); light grey in the force plot = signal before. See mda_rockerFilter']);
hDet = uicontrol(pnl, dflt{:}, 'Style', 'popupmenu', 'String', {'high sensitivity', 'high specificity'}, ...
    'Position', [0.615 0.647 0.355 0.035], 'Callback', @onDetection, 'TooltipString', ['auto threshold: high sensitivity counts ' ...
    'all contractions and marks the uncertain ones (orange: neither locked to the stimuli nor large compared with the ' ...
    'typical contraction and the noise before the stimuli); high specificity does not count them (option detection)']);
hRel = uicontrol(pnl, dflt{:}, 'Style', 'checkbox', 'String', 'time 0 = window start', 'Position', [0.03 0.61 0.585 0.033], ...
    'Callback', @onRelTime, 'TooltipString', 'time axis: 0 = start of the loaded window (display only; From/To, tables and exports keep the time in the file, s)');
uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'Rocker artifact ...', 'Position', [0.615 0.609 0.355 0.035], ...
    'Callback', @(~,~) onRockerWindow(), 'TooltipString', ['periodic signal of the rocker movement that the rocker filter ' ...
    'removes (estimated for this channel and window, also if the filter is off): extra window, save as figure, export data']);
hCounts = uicontrol(pnl, dflt{:}, 'Style', 'text', 'String', '', 'HorizontalAlignment', 'left', 'Position', [0.03 0.49 0.94 0.118], 'FontSize', 9);
hFlags = uicontrol(pnl, dflt{:}, 'Style', 'text', 'String', '', 'HorizontalAlignment', 'left', 'Position', [0.03 0.462 0.94 0.026], ...
    'FontSize', 9, 'ForegroundColor', [0.45 0.45 0.45]);   %flags of the analysis report for this range (2026-10-14)
hTable = uitable(pnl, 'Units', 'normalized', 'Position', [0.03 0.215 0.94 0.245], 'RowName', [], ...
    'ColumnName', {'parameter','mean','median','SD','n','unit'}, 'ColumnWidth', {96, 58, 58, 52, 32, 40}, 'FontSize', 9);
uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'Overlay contractions', 'Position', [0.03 0.165 0.46 0.04], 'Callback', @onOverlay, ...
    'TooltipString', ['overlay of the selected contractions (mean beat or time course); press again (or Add in the overlay window) to add ' ...
    'another selection as a new group; other channels of the same range: Channels ... in the overlay window']);
uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'Show table', 'Position', [0.51 0.165 0.46 0.04], 'Callback', @onShowTable);
uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'Export this channel ...', 'Position', [0.03 0.12 0.46 0.04], 'Callback', @onExport);
uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'All channels -> file ...', 'Position', [0.51 0.12 0.46 0.04], 'Callback', @onAllChannels);
uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'Copy summary', 'Position', [0.03 0.075 0.46 0.04], 'Callback', @onCopy);
uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'Help', 'Position', [0.51 0.075 0.46 0.04], 'Callback', @(~,~) lightTheme(helpdlg(helpText(), 'MyoDishAnalysis')));
hStatus = uicontrol(pnl, dflt{:}, 'Style', 'text', 'String', 'Open an .mdd file.', 'HorizontalAlignment', 'left', 'Position', [0.03 0.003 0.94 0.068], 'FontSize', 9, 'ForegroundColor', uiBlueDark);

% functions for scripts / tests: api = fig.UserData; api.setRange([t1 t2]); api.toggleAt(t);
% [contractions, summary] = api.results();  api.epRecording(matFile) (show; '' = remove);  EP = api.epRecordingData();
% api.overlayChannels([1 2 3]) (overlay of the analysed range in these channels); [groups, h] = api.overlay();
% api.key('rightarrow', {'shift'}) (arrow key as typed in the force plot); api.navButton('rightarrow', true) (button under
% the force plot, true = shift + click); R = api.trend([1 3]) (trend window: these channels calculated and overlaid)
% api.openResults(file, k) (results file, analysis window k); h = api.rockerWindow() (rocker artifact window);
% api.nextFile(file) (file name of the next save / export dialog), then e.g. api.exportChannel() or a menu of a window
% api.epYLim(k, [lo hi]) (y limits of the EP plot k = 1 signal / 2 stimulation; [] = automatic);
% api.epRemoveArtefacts(true / false); Hv = api.hover(t, 'force' | 'stimuli' | 'parameter' | 'signal' | 'stimulation')
% (mouse pointer at time t over that plot: markers and values; Hv: one element per plot with x, y, text)
% [o, h] = api.advanced(struct('gateMax', 0.2, ...)) (advanced settings as typed in the window and Apply; no input:
% current options; h = the window); api.nextFile(file), then api.advanced('save') / api.advanced('load'): Save
% settings ... / Load settings ... of the window; api.legend(tf) (legend of the force plot on / off)
% Bw = api.browse(resultsFolder, k) (results browser of this folder, not remembered; k: open row k of the table as a
% double-click; Bw: handles and rows of the browser); st = api.state() (file, channel, loaded window, analysed range,
% comment numbers in the force plot, highlighted comment, flags line, status line, main recording); api.commentClick(k)
% (comment mark k clicked); api.mainFile() (button Main file); api.setRange(r, true) (r added to the selection, as
% shift + drag; r: one or several rows [from to]); api.rockerStops() / api.zoomToSelection() / api.selectAll() (context
% menus of the force plot and the overview; 2026-10-14)
fig.UserData = struct('setRange', @apiSetRange, 'toggleAt', @toggleContraction, 'results', @apiResults, ...
    'setLabels', @apiSetLabels, 'labels', @apiLabels, 'zeroAt', @apiZeroAt, ...
    'epRecording', @openEP, 'epRecordingData', @apiEP, 'epYLim', @epSetYLim, 'epRemoveArtefacts', @epSetClean, ...
    'hover', @apiHover, ...
    'overlayChannels', @setOverlayChannels, 'overlay', @apiOverlay, 'key', @apiKey, 'navButton', @navButton, ...
    'trend', @apiTrend, 'openResults', @openResults, 'rockerWindow', @onRockerWindow, 'nextFile', @apiNextFile, ...
    'exportChannel', @onExport, 'exportPlotData', @exportPlotData, 'advanced', @apiAdvanced, 'legend', @apiLegend, ...
    'browse', @apiBrowse, 'state', @apiState, 'commentClick', @comMarkerClick, 'mainFile', @onMainFile, ...
    'rockerStops', @selectRockerStops, 'zoomToSelection', @zoomToSelection, 'selectAll', @selectAll);

emptyPlots();
advIndicator();
fig.SizeChangedFcn = @(~,~) onSizeChanged();     %shortened text of the 'Advanced' button, margins of the plots
if ~isempty(mddFile) && ~endsWith(lower(char(mddFile)), '.mdd')   %results file (2026-10-09)
    openResults(char(mddFile));
elseif ~isempty(mddFile)
    openFile(char(mddFile), false);
    if ~isempty(metadata) && ~isempty(H)
        try
            Lbl = mda_labels(metadata, H.dataChannels);
        catch ME
            status(['Labels: ' ME.message]);
        end
    end
    if isempty(goWin) && ~isempty(H), goTo(goCh, []); firstWindow(); else, goTo(goCh, goWin); end   %first window
end
addlistener(axStim, 'XLim', 'PostSet', @(~,~) stimLabels());
addlistener(axOv, 'XLim', 'PostSet', @(~,~) ovTicks());   %time labels h:mm:ss of the overview (also toolbar zoom)
addlistener(axMain, 'XLim', 'PostSet', @(~,~) mainTicks()); %time labels of force / stimulus / parameter plot
if nargout > 0, figOut = fig; end          %(clearing 'fig' would clear it for the nested callbacks)


% =====================================================================================================
% callbacks
% =====================================================================================================
    function onOpen(~, ~)
        % a recording (.mdd) or results of an analysis (.xlsx, _info.csv, ...); the folder is remembered (2026-10-14)
        res = '*.xlsx;*_info.csv;*_summary.csv;*_contractions.csv;*_contractions.csv.gz';
        [fn, pn] = uigetfile({['*.mdd;' res], 'recordings and results (*.mdd, *.xlsx, *_info.csv, ...)'; ...
            '*.mdd', 'recordings (*.mdd)'; res, 'results of MyoDishAnalysis (*.xlsx, *_info.csv, ...)'}, 'Open', ...
            prefGet('lastOpenDir'));
        if isequal(fn, 0), return; end
        prefSet('lastOpenDir', pn);
        if endsWith(lower(fn), '.mdd'), openFile(fullfile(pn, fn)); else, openResults(fullfile(pn, fn)); end
    end

    function ok = openResults(file, pick, maxLen)
        % results file of MyoDishAnalysis / Watch / GUI export (2026-10-09): recording, settings and analysis window
        % of the results; the contractions are detected again and compared with the file (black o = only in the file).
        % maxLen (s, optional; results browser): only the beginning of the analysis window is loaded
        ok = false;
        if nargin < 3, maxLen = []; end
        try
            R = mda_readResults(file);
        catch ME
            status(['Results: ' ME.message]); return;
        end
        if isempty(R.windows) || height(R.windows) == 0, status('Results: no analysis window in the file.'); return; end
        mdd = R.mddFile;
        if isempty(mdd) || ~exist(mdd, 'file')          %moved: same name next to the results, or ask
            [~, n, e] = fileparts(strrep(mdd, '\', '/'));
            cand = fullfile(fileparts(file), [n e]);
            if ~isempty(n) && exist(cand, 'file') == 2
                mdd = cand;
            else
                [fn, pn] = uigetfile('*.mdd', sprintf('Recording of the results: %s', [n e]));
                if isequal(fn, 0), return; end
                mdd = fullfile(pn, fn);
            end
        end
        W = R.windows;
        win = goWin; goWin = [];                        %channel / window of the call (analysis report), once
        if nargin < 2, pick = []; end
        if isempty(pick) && ~isempty(goCh)
            r = find(W.channel == goCh);
            if ~isempty(win)
                r2 = r(W.from(r) <= win(1) + 1e-9 & W.to(r) >= win(1) - 1e-9);
                if ~isempty(r2), r = r2; end
            end
            if ~isempty(r), pick = r(1); else, status(sprintf('Results: no analysis window of channel %d.', goCh)); end
        elseif isempty(pick) && ~isempty(win)            %window without channel (results browser): first channel
            r = find(W.channel == W.channel(1));
            r2 = r(W.from(r) <= win(1) + 1e-9 & W.to(r) >= win(1) - 1e-9);
            if ~isempty(r2), r = r2; end
            pick = r(1);
        end
        goCh = [];
        guiMulti = strcmp(R.createdBy, 'MyoDishAnalysisGUI') && isscalar(unique(W.channel)) && height(W) > 1;
        if isempty(pick) && guiMulti, pick = 1; end      %export of the GUI with several ranges: all of them (2026-10-14)
        if isempty(pick)                                %analysis window: channel, range, chunk
            pick = 1;
            if height(W) > 1
                txt = arrayfun(@(r) sprintf('ch %d   %s   %.1f - %.1f s   (threshold %.0f %sN)', W.channel(r), W.range{r}, ...
                    W.from(r), W.to(r), W.threshold_uN(r), mu), (1:height(W))', 'UniformOutput', false);
                [pick, okP] = listdlg('ListString', txt, 'SelectionMode', 'single', 'ListSize', [460 320], ...
                    'Name', 'Open results', 'PromptString', 'Analysis window (channel, range, time):');
                if ~okP, return; end
            end
        end
        w = W(pick, :);
        openFile(mdd, false);
        if isempty(H), return; end
        if ~ismember(w.channel, H.dataChannels), status(sprintf('Results: channel %d is not in %s.', w.channel, H.file)); return; end
        % settings of the results
        opts = R.options; opts.referenceBeat = [];
        hRF.Value = opts.rockerFilter;
        hDet.Value = 1 + strcmp(opts.detection, 'specific');
        hRocker.Value = strcmp(opts.rocker, 'stopped');
        hStim.Value = strcmp(opts.beats, 'stimulated');
        if ~isempty(hAdv) && isvalid(hAdv), close(hAdv); end   %advanced settings of the results
        ch = w.channel;
        hCh.Value = find(H.dataChannels == ch, 1);
        thrUser(:) = nan; zeroUser(:) = nan;
        thrUser(ch) = valueOfChannel(opts.threshold, R.channels, ch);
        zeroUser(ch) = valueOfChannel(opts.zeroForce, R.channels, ch);
        opts.threshold = 'auto'; opts.zeroForce = [];   %the GUI keeps them per channel
        showThreshold();
        advIndicator();
        if ~isempty(R.labels)
            try
                Lbl = mda_labels(R.labels, H.dataChannels);
            catch
                status('Results: labels not read.');
            end
        end
        % data window of the analysis, analysed range, contractions excluded by the user (GUI exports)
        resInfo = '';
        segF = [];                                      %rocker stops side by side (GUI export, 2026-10-14)
        if isfield(R.extra, 'segments_s'), segF = parseRows(R.extra.segments_s); end
        rgF = [w.from w.to];                            %analysed range(s), time in the file
        if guiMulti, rgF = [W.from W.to]; end
        if isempty(win) && size(segF, 1) > 1 && isempty(maxLen)
            if ~loadSegments(segF), return; end
        elseif isempty(win)
            wl = [w.windowFrom w.windowTo];
            if ~isempty(maxLen), wl(2) = min(wl(2), max(w.from, wl(1)) + maxLen); end
            onLoad([], [], wl);
        else
            onLoad([], [], win(1:2)); rgF = win(1:2);
        end
        if isempty(S), return; end
        if opts.rockerFilter && ~strcmp(R.createdBy, 'MyoDishAnalysisGUI')
            rfCtx = S; rfCache = {};                    %as MyoDishAnalysis: estimated from the data window itself
        end
        rg = f2w(rgF);                                  %time in the loaded window
        rg = [max(rg(:,1), S.fromSeconds), min(rg(:,2), S.toSeconds)];
        rg = rg(all(isfinite(rg), 2) & rg(:,2) > rg(:,1), :);
        if isempty(rg), rg = [S.fromSeconds S.toSeconds]; end
        range = mergeRanges(rg);
        Tc = [];
        if ~isempty(R.contractions) && all(ismember({'channel', 't_peak'}, R.contractions.Properties.VariableNames))
            Tc = R.contractions(R.contractions.channel == ch, :);
            Tc.t_peak = f2w(Tc.t_peak);                 %(rocker stops side by side: window time)
            Tc = Tc(inRng(Tc.t_peak, [range(:,1) - 1e-9, range(:,2) + 1e-9]), :);
            if ismember('manuallyExcluded', Tc.Properties.VariableNames)
                manualOff = Tc.t_peak(Tc.manuallyExcluded == 1);
            end
        end
        ep = '';
        if isfield(R.extra, 'epRecording'), ep = R.extra.epRecording; end
        analyze(false);
        resInfo = compareResults(R, Tc);
        if ~isempty(ep) && exist(ep, 'file'), openEP(ep); end
        analyze(false);
        ok = true;
    end

    function v = valueOfChannel(x, chans, c)
        % threshold / zero force of channel c from the option value: 'auto' / [] = NaN, one value, one per channel
        v = nan;
        if ischar(x) || isempty(x), return; end
        if isscalar(x), v = x; return; end
        j = find(chans == c, 1);
        if ~isempty(j) && j <= numel(x), v = x(j); end
    end

    function txt = compareResults(R, Tc)
        % contractions of the results file vs. detected here (same channel and range)
        src = sprintf('Results (%s %s%s%s):', R.implementation, R.version, ...
            repmat([', ' R.createdBy], 1, ~isempty(R.createdBy)), repmat([', ' R.analysisDate], 1, ~isempty(R.analysisDate)));
        if ~strcmp(R.version, mda_version()), src = sprintf('%s version differs from this one (%s)!', src, mda_version()); end
        resOnly = [];
        if isempty(Tc)
            txt = sprintf('%s settings and window applied (no contractions in the file to compare).', src); return;
        end
        if ismember('sampleMode', Tc.Properties.VariableNames) && any(strcmp(Tc.sampleMode, 'median'))
            txt = sprintf('%s settings and window applied (contractions thinned to block medians: not compared).', src);
            return;
        end
        if isempty(B), inR = false(0, 1); else, inR = inRng(B.t_peak); end
        tH = []; if ~isempty(B), tH = B.t_peak(inR); end
        tol = S.dt / 2;
        if isempty(tH)
            d = inf(1, height(Tc)); j = ones(1, height(Tc));
        else
            [d, j] = min(abs(Tc.t_peak(:)' - tH(:)), [], 1);   %nearest contraction here for each one of the file
        end
        found = d <= tol;
        resOnly = Tc.t_peak(~found);
        thinned = ismember('sampledEvery', Tc.Properties.VariableNames) && any(Tc.sampledEvery > 1);
        nHereOnly = 0;
        if ~thinned, nHereOnly = numel(tH) - numel(unique(j(found))); end
        diffU = 0; diffI = 0;
        if any(found)
            Bh = B(inR, :); sel = selected(); sel = sel(inR);
            if ismember('uncertain', Tc.Properties.VariableNames)
                diffU = nnz(logical(Tc.uncertain(found)) ~= Bh.uncertain(j(found)));
            end
            if ismember('included', Tc.Properties.VariableNames) && ~thinned
                diffI = nnz(logical(Tc.included(found)) ~= sel(j(found)));
            end
        end
        if ~any(~found) && nHereOnly == 0 && diffU == 0 && diffI == 0
            txt = sprintf('%s %d contractions, the same as here.', src, height(Tc));
            if thinned, txt = sprintf('%s %d contractions (thinned), all found again.', src, height(Tc)); end
        else
            txt = sprintf(['%s DIFFERENCES: %d contraction(s) only in the file (black o), %d only here, flag uncertain ' ...
                '%d, included %d.'], src, nnz(~found), nHereOnly, diffU, diffI);
        end
    end

    function openFile(file, autoLoad)
        % autoLoad (default true): the first window (From / To: 0 - 120 s) is loaded and analysed right away (2026-10-14)
        if nargin < 2, autoLoad = true; end
        try
            H = mda_readMdd(file, [], [], opts);
        catch ME
            status(['Error: ' ME.message]);
            if ~isempty(getenv('MDA_DEBUG')), disp(getReport(ME, 'extended')); end
            return;
        end
        S = []; O = []; B = []; C = []; manualOff = zeros(0,1); zeroUser = nan(1, 8); thrUser = nan(1, 8); Od = []; ovXL = [];
        sbs = []; range = [nan nan];
        resOnly = []; resInfo = ''; winReq = [nan nan];
        hThrMode.Value = 1; hThr.String = '';
        rfCtx = []; rfCache = {}; rfF0 = [];
        if ~isempty(EP), EP = []; showEP(false); end     %the EP recording belongs to the previous file
        epVc = []; epArtMask = []; epYLim = {[], []};
        [~, n, e] = fileparts(H.file);
        nm = [n e];
        if numel(nm) > 30, nm = [nm(1:13) '...' nm(end-13:end)]; end
        hFile.String = nm;
        hFile.TooltipString = H.file;
        hCh.String = arrayfun(@(c) sprintf('Ch %d', c), H.dataChannels, 'UniformOutput', false);
        hCh.Value = 1; ch = H.dataChannels(1);
        info = sprintf('%.0f Hz, %d channel(s), %s', H.samplingRate, numel(H.dataChannels), fmtDuration(H.totalSeconds));
        if ~isnan(H.recordingStart), info = sprintf('%s\nstart %s', info, datestr(H.recordingStart, 'yyyy-mm-dd HH:MM')); end
        hInfo.String = info;
        hFrom.String = '0';
        hTo.String = sprintf('%.0f', min(120, floor(H.totalSeconds)));
        emptyPlots();
        msg = 'File opened. Press Load (time window From/To) or Overview.';
        LE = []; hiT = nan;
        try
            LE = mda_logEntries(H.logFile);
            if any(LE.isComment), msg = sprintf('%s %d comments in the log file (button Comments ...).', msg, nnz(LE.isComment)); end
        catch ME
            msg = [msg ' Log entries not read: ' ME.message];
        end
        if ~isempty(hCom) && isvalid(hCom.fig), hCom.fig.Name = ['Comments - ' nm]; filterComments(); end
        if ~isempty(H.notes), msg = [msg ' Note: ' strjoin(H.notes, ' ')]; end
        Lbl = mda_labels([], H.dataChannels);
        if ~isempty(hLblFig) && isvalid(hLblFig), delete(hLblFig); end
        [p, n] = fileparts(H.file);
        lf = fullfile(p, [n '_labels.csv']);
        if exist(lf, 'file')
            try
                Lbl = mda_labels(lf, H.dataChannels);
                msg = [msg ' Labels loaded from ' n '_labels.csv.'];
            catch ME
                msg = [msg ' Labels file not read: ' ME.message];
            end
        end
        % parallel recording (e.g. schedule file) of a main recording in the same folder: button Main file (2026-10-14)
        mainRec = [];
        try
            mainRec = MyoDishAnalysisWatch('mainRecording', H.file);
        catch
        end
        if isempty(mainRec)
            hMain.Visible = 'off'; hFile.Position(3) = 0.131;
        else
            hMain.TooltipString = [parallelText() ': opens the main file at the window shown here'];
            hMain.Visible = 'on'; hFile.Position(3) = 0.088;
            msg = sprintf('%s This is a %s (button Main file).', msg, parallelText());
        end
        status(msg);
        if H.bytes < 150e6, onOverview(); end      %small files: overview right away
        if autoLoad, firstWindow(); end
    end

    function firstWindow()
        % first window of a newly opened file (From / To: 0 - 120 s) loaded and analysed (2026-10-14); the notes of the
        % file stay visible after the message of the analysis
        onLoad();
        if isempty(S), return; end
        note = strjoin(H.notes, ' ');
        if ~isempty(mainRec), note = strtrim(sprintf('%s This is a %s (button Main file).', note, parallelText())); end
        if ~isempty(note), status(sprintf('%s Note: %s', statusText, note)); end
    end

    function txt = parallelText()
        % open parallel recording: 'parallel recording of <main file> (a-b s of the main file)'
        txt = '';
        if isempty(mainRec), return; end
        [~, mn, me] = fileparts(mainRec.main);
        if isfinite(mainRec.b), w = sprintf('%.1f-%.1f s', mainRec.a, mainRec.b); else, w = sprintf('from %.1f s', mainRec.a); end
        txt = sprintf('parallel recording of %s (%s of the main file)', [mn me], w);
    end

    function onMainFile()
        % parallel recording: the main file at the window shown here (time in the main file = a + time here), same
        % channel
        if isempty(mainRec), return; end
        if isempty(S), w = [0 min(120, mainRec.b - mainRec.a)]; else, w = [S.fromSeconds S.toSeconds]; end
        c = ch; f = mainRec.main; a = mainRec.a;
        openFile(f, false);
        if isempty(H), return; end
        goTo(c, a + w);
    end

    % ---------------------------------------------------------------- results browser (2026-10-14)
    function onBrowse(res, remember)
        % recordings and channels of a results folder of the watcher (mda_index.csv) with the flags of the analysis
        % report (mda_flags.csv). Double-click a row (or Open): the channel with the settings of its analysis (red
        % flags: the window of the flags, otherwise the first 120 s of its analysis); a parallel recording that was not
        % analysed: its main file at its window. The last folder is opened again directly (Folder ... = another one).
        % remember (default true): the folder is remembered (MATLAB preferences; false: tests)
        if nargin < 1, res = ''; end
        if nargin < 2, remember = true; end
        isOpen = ~isempty(hBrw) && isvalid(hBrw.fig);
        if isempty(res) && isOpen, figure(hBrw.fig); return; end
        if isempty(res)
            res = prefGet('lastResultsDir');
            if isempty(res) || ~isfile(fullfile(res, 'mda_index.csv'))
                res = uigetdir(res, 'Results folder of the watcher (with mda_index.csv)');
                if isequal(res, 0), return; end
            end
        end
        if ~isOpen, browserWindow(); end
        hBrw.res = resultsRoot(char(res));
        hBrw.remember = remember;
        browserLoad();
        figure(hBrw.fig);
    end

    function browserWindow()
        f2 = uifigure('Name', 'Results', 'Position', [90 90 1180 600]);
        lightTheme(f2);
        g = uigridlayout(f2, [4 6]);
        g.RowHeight = {26, 26, '1x', 50};
        g.ColumnWidth = {80, '1x', 220, 170, 150, 80};
        b = uibutton(g, 'Text', 'Folder ...', 'ButtonPushedFcn', @(~,~) browserFolder());
        setTip(b, 'results folder of the watcher (with mda_index.csv)');
        lf = uilabel(g, 'Text', '', 'FontColor', uiBlueDark);
        lf.Layout.Column = [2 5];
        b = uibutton(g, 'Text', 'Reload', 'ButtonPushedFcn', @(~,~) browserLoad());
        setTip(b, 'read the index and the flags again (e.g. after a pass of the watcher)');
        uilabel(g, 'Text', 'Search:');
        ef = uieditfield(g, 'text', 'ValueChangedFcn', @(~,~) browserFilter());
        try ef.Placeholder = 'recording, label, status, flag text ... (several words: all must occur)'; catch, end
        dd = uidropdown(g, 'Items', {'all recordings', 'with flags', 'red flags (check the analysis)', 'not analysed'}, ...
            'ValueChangedFcn', @(~,~) browserFilter());
        lc = uilabel(g, 'Text', '', 'HorizontalAlignment', 'right');
        bc = uibutton(g, 'Text', 'Compute flags', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) browserCompute());
        setTip(bc, ['recordings analysed without flags (older watcher versions): flags computed from their result ' ...
            'files and saved in mda_flags.csv']);
        bo = uibutton(g, 'Text', 'Open', 'ButtonPushedFcn', @(~,~) browserOpen(), 'BackgroundColor', uiBlue, ...
            'FontColor', [1 1 1], 'FontWeight', 'bold');
        ut = uitable(g, 'RowName', {}, 'ColumnName', {'recording', 'ch', 'label', 'flags', 'capture %', ...
            'contractions', 'status', 'note'}, 'ColumnWidth', {300, 32, 140, 50, 85, 100, 95, 'auto'}, ...
            'CellSelectionCallback', @(~,evt) browserSelect(evt));
        ut.Layout.Row = 3; ut.Layout.Column = [1 6];
        try ut.SelectionType = 'row'; catch, end           %R2021b+
        if isprop(ut, 'DoubleClickedFcn'), ut.DoubleClickedFcn = @(~,evt) browserDouble(evt); end   %R2021a+
        lm = uilabel(g, 'Text', '', 'FontColor', [0.3 0.3 0.3], 'VerticalAlignment', 'top');
        try lm.WordWrap = 'on'; catch, end
        lm.Layout.Row = 4; lm.Layout.Column = [1 6];
        hBrw = struct('fig', f2, 'res', '', 'remember', true, 'lf', lf, 'ef', ef, 'dd', dd, 'lc', lc, 'bc', bc, ...
            'bo', bo, 'ut', ut, 'lm', lm, 'D', [], 'view', [], 'row', [], 'missing', {{}});
    end

    function browserFolder()
        p = uigetdir(hBrw.res, 'Results folder of the watcher (with mda_index.csv)');
        figure(hBrw.fig);
        if isequal(p, 0), return; end
        hBrw.res = resultsRoot(p);
        browserLoad();
    end

    function browserLoad()
        % index and flags of the folder (flags only of the current analyses; missing ones: Compute flags)
        if isempty(hBrw) || ~isvalid(hBrw.fig), return; end
        res = hBrw.res;
        hBrw.lf.Text = res;
        hBrw.D = []; hBrw.missing = {}; hBrw.row = [];
        hBrw.bc.Enable = 'off'; hBrw.bc.Text = 'Compute flags';
        if ~isfile(fullfile(res, 'mda_index.csv'))
            browserFilter();
            hBrw.lm.Text = ['No mda_index.csv in this folder: choose the results folder of the watcher ' ...
                '(MyoDishAnalysisWatch, mda-watch) with Folder ...'];
            return;
        end
        if hBrw.remember, prefSet('lastResultsDir', res); end
        hBrw.lm.Text = 'Reading the index and the flags ...'; drawnow;
        try
            X = MyoDishAnalysisWatch('index', res);
            [T, missing] = MyoDishAnalysisWatch('flags', res, false);
        catch ME
            hBrw.lm.Text = ['Error: ' ME.message]; return;
        end
        hBrw.D = browserRows(X, T);
        hBrw.missing = missing;
        if ~isempty(missing), hBrw.bc.Enable = 'on'; hBrw.bc.Text = sprintf('Compute flags (%d)', numel(missing)); end
        browserFilter();
        hBrw.lm.Text = ['Double-click a row (or Open): the channel with the settings of its analysis (red flags: the ' ...
            'window of the flags, otherwise the first 120 s of its analysis); a parallel recording that was not ' ...
            'analysed: its main file at that time. Flags (as in the watcher report): red = check the analysis (I ' ...
            'inverted signal, N noise, S large extra beats, D delay, F stimulus frequency), yellow = slice quality (C ' ...
            'capture, X extra beats, A amplitude, T amplitude change, V amplitude CV); ? = not computed yet.'];
    end

    function browserCompute()
        % flags of the recordings without current flags (from their result files; saved in mda_flags.csv)
        n = numel(hBrw.missing);
        if n == 0, return; end
        wb = waitbar(0, sprintf('Flags of %d recording(s) ...', n), 'Name', 'Results');
        try
            MyoDishAnalysisWatch('flags', hBrw.res, true, @(k, m) waitbar(k / max(m, 1), wb));
        catch ME
            hBrw.lm.Text = ['Error: ' ME.message];
        end
        if ishandle(wb), close(wb); end
        browserLoad();
        figure(hBrw.fig);
    end

    function browserFilter()
        % rows shown: list (all / with flags / red flags / not analysed) and search text (all words, case-insensitive)
        if isempty(hBrw) || ~isvalid(hBrw.fig), return; end
        D = hBrw.D;
        if isempty(D)
            hBrw.view = []; hBrw.ut.Data = cell(0, 8); hBrw.lc.Text = ''; return;
        end
        switch find(strcmp(hBrw.dd.Items, hBrw.dd.Value))
            case 2, m = ismember(D.level, {'check', 'quality'});
            case 3, m = strcmp(D.level, 'check');
            case 4, m = ~strcmp(D.indexStatus, 'ok');
            otherwise, m = true(height(D), 1);
        end
        words = strsplit(lower(strtrim(char(hBrw.ef.Value))));
        words = words(~cellfun(@isempty, words));
        for k = 1:numel(words), m = m & contains(D.hay, words{k}); end
        hBrw.view = find(m);
        hBrw.row = [];
        V = D(hBrw.view, :);
        hBrw.ut.Data = [V.file, numText(V.channel, '%d'), V.label, V.flags, numText(V.capture, '%.0f'), ...
            numText(V.nDetected, '%d'), V.status, V.note];
        try                                                %colours of the watcher report (R2019b+)
            removeStyle(hBrw.ut);
            r = find(strcmp(V.level, 'check'));
            if ~isempty(r), addStyle(hBrw.ut, uistyle('BackgroundColor', [0.973 0.788 0.769]), 'row', r); end
            r = find(strcmp(V.level, 'quality'));
            if ~isempty(r), addStyle(hBrw.ut, uistyle('BackgroundColor', [0.984 0.910 0.651]), 'row', r); end
            r = find(~strcmp(V.indexStatus, 'ok'));
            if ~isempty(r), addStyle(hBrw.ut, uistyle('FontColor', [0.45 0.45 0.45]), 'row', r); end
        catch
        end
        hBrw.lc.Text = sprintf('%d row(s), %d recording(s)', height(V), numel(unique(V.file)));
    end

    function browserSelect(evt)
        if isempty(evt.Indices), hBrw.row = []; else, hBrw.row = evt.Indices(1,1); end
    end

    function browserDouble(evt)
        try r = evt.InteractionInformation.Row; catch, r = []; end
        if ~isempty(r), browserOpen(r(1)); end
    end

    function browserOpen(r)
        % a row of the browser in the main window (results file <name>_info.csv of the recording)
        if nargin < 1
            r = hBrw.row;
            try
                if isempty(r) && isprop(hBrw.ut, 'Selection') && ~isempty(hBrw.ut.Selection), r = hBrw.ut.Selection(1,1); end
            catch
            end
        end
        if isempty(r) || isempty(hBrw.view) || r > numel(hBrw.view)
            hBrw.lm.Text = 'Select a row first.'; return;
        end
        d = hBrw.D(hBrw.view(r), :);
        file = d.file{1}; c = d.channel(1); win = []; pick = []; maxLen = 120;
        if strcmp(d.indexStatus{1}, 'parallel') && ~isempty(d.main{1})   %not analysed: the main file at its window
            file = d.main{1}; c = nan;
            win = d.a(1) + [0 120];
            if isfinite(d.b(1)), win(2) = min(win(2), d.b(1)); end
        elseif ~strcmp(d.indexStatus{1}, 'ok')
            hBrw.lm.Text = sprintf('%s was not analysed (%s): %s', d.file{1}, d.indexStatus{1}, d.note{1}); return;
        elseif isfinite(d.from(1)) && isfinite(d.to(1))
            win = [d.from(1) d.to(1)];
        end
        [~, n] = fileparts(strrep(file, '\', '/'));
        dd = MyoDishAnalysisWatch('resultFolder', hBrw.res, file);   %folder of the series or flat (2026-10-15)
        info = '';                                  %results: <name>.xlsx (2026-10-14) or <name>_info.csv; protocols only
        for cand = {[n '.xlsx'], [n '_info.csv'], [n '_protocols.xlsx'], [n '_protocols_info.csv']}
            x = fullfile(dd, cand{1});
            if ~isfile(x), continue; end
            if endsWith(x, '.xlsx')
                try
                    ok = ismember('info', sheetnames(x));
                catch
                    ok = false;
                end
                if ~ok, continue; end
            end
            info = x; break;
        end
        if isempty(info)
            hBrw.lm.Text = sprintf('No results of %s in this folder (%s.xlsx, %s_info.csv).', file, n, n); return;
        end
        if isnan(c), goCh = []; if isempty(win), pick = 1; end, else, goCh = c; end
        goWin = win;
        figure(fig);
        openResults(info, pick, maxLen);
    end

    function st = apiState()
        % state of the main window for scripts / tests (2026-10-14)
        st = struct('file', '', 'channel', ch, 'window', [nan nan], 'range', range, 'comments', comK(:)', ...
            'hiT', hiT, 'flags', strtrim(char(hFlags.String)), 'status', statusText, 'mainRecording', mainRec, ...
            'mainButton', char(hMain.Visible));
        if ~isempty(H), st.file = H.file; end
        if ~isempty(S), st.window = [S.fromSeconds S.toSeconds]; end
        st.rangeFile = w2f(range);                      %analysed range(s), time in the file (2026-10-14)
        st.segments = zeros(0, 2);                      %rocker stops side by side: the windows read (file time)
        if ~isempty(sbs), st.segments = sbs.seg(:, 1:2); end
        st.xlim = xlim(axMain);
        st.margin = axMain.Position(1);
    end

    function Bw = apiBrowse(res, k)
        % results browser for scripts / tests (the folder is not remembered); k: row k of the table opened
        if nargin >= 1 && ~isempty(res), onBrowse(res, false); end
        if nargin >= 2 && ~isempty(k), browserOpen(k); end
        Bw = hBrw;
    end

    function onLoad(~, ~, w)
        % w (optional): window [from to] in s (results files: exactly the data window of the analysis)
        if isempty(H), status('Open a file first.'); return; end
        if nargin >= 3, from = w(1); to = w(2);
        else, from = str2double(hFrom.String); to = str2double(hTo.String); end
        if isnan(from) || isnan(to), status('From / To must be numbers (s).'); return; end
        if from < 0, from = H.totalSeconds + from; end
        if to < 0, to = H.totalSeconds + to; end
        from = max(0, from); to = min(H.totalSeconds, to);
        if to - from < 1, status('Time window too short (< 1 s).'); return; end
        if to - from > 4 * 3600
            status('Window longer than 4 h: use the command line version (MyoDishAnalysis) for long ranges.'); return;
        end
        status('Loading ...'); drawnow;
        try
            S = mda_readMdd(H.file, from, to, opts);
        catch ME
            status(['Error: ' ME.message]);
            if ~isempty(getenv('MDA_DEBUG')), disp(getReport(ME, 'extended')); end
            return;
        end
        rfCtx = []; rfCache = {}; rfF0 = []; resOnly = [];
        sbs = [];                                       %continuous window (not side-by-side rocker stops)
        winReq = [from to];
        hFrom.String = sprintf('%.1f', S.fromSeconds); hTo.String = sprintf('%.1f', S.toSeconds);
        channelLabels();
        range = [S.fromSeconds S.toSeconds];
        manualOff = zeros(0,1);
        analyze(true);
        plotOverview();
    end

    function onOverview(~, ~)
        if isempty(H), status('Open a file first.'); return; end
        wb = waitbar(0, 'Reading the whole file ...', 'Name', 'Overview');
        try
            O = mda_readMdd(H.file, 'overview', [], opts, @(p) waitbar(p, wb));
        catch ME
            O = []; status(['Error: ' ME.message]);
        end
        if ishandle(wb), close(wb); end
        plotOverview();
        if ~isempty(O), status('Overview: drag = load a time window, wheel = zoom, shift + wheel = move, double-click = whole file, right click = select all.'); end
    end

    function goTo(c, w)
        % show channel c and load the window w = [from to] s (commands of the analysis report, 2026-10-11)
        if isempty(H), return; end
        if ~isempty(c)
            k = find(H.dataChannels == c, 1);
            if isempty(k)
                status(sprintf('Channel %d is not in %s.', c, H.file));
            else
                hCh.Value = k; ch = c; showThreshold();
            end
        end
        if ~isempty(w), onLoad([], [], w(1:2)); end
    end

    function onChannel(~, ~)
        if isempty(H), return; end
        ch = H.dataChannels(hCh.Value);
        manualOff = zeros(0,1); resOnly = []; resInfo = '';
        showThreshold();
        plotOverview();
        if ~isempty(S), analyze(false); end
    end

    % detection threshold per channel (2026-10-07): auto or a manual value for each channel
    function onThreshold(~, ~)
        if hThrMode.Value == 1
            thrUser(ch) = nan;
            if ~isempty(S), analyze(false); end
        else
            onThresholdValue();
        end
    end

    function onThresholdValue(~, ~)
        v = str2double(hThr.String);
        if isnan(v) || v <= 0
            if isnan(thrUser(ch)), hThrMode.Value = 1; end  %display = the threshold actually used
            status('Threshold: enter a positive number (uN).'); return;
        end
        hThrMode.Value = 2;
        thrUser(ch) = v;
        if ~isempty(S), analyze(false); end
    end

    function showThreshold()
        % threshold controls of the selected channel (auto: value shown after the detection)
        if isnan(thrUser(ch))
            hThrMode.Value = 1; hThr.String = '';
        else
            hThrMode.Value = 2; hThr.String = sprintf('%g', thrUser(ch));
        end
    end

    function th = thrOf(chs)
        % thresholds of channels chs for the analysis functions: 'auto' or one value per channel (NaN = auto)
        th = thrUser(chs);
        if all(isnan(th)), th = 'auto'; end
    end

    function onRockerFilter(~, ~)
        opts.rockerFilter = logical(hRF.Value);
        if ~isempty(S), analyze(false); end
    end

    function onDetection(~, ~)
        dm = {'sensitive', 'specific'};
        opts.detection = dm{hDet.Value};
        if ~isempty(S), analyze(false); end
    end

    function onFilter(~, ~)
        if hRocker.Value, opts.rocker = 'stopped'; else, opts.rocker = 'any'; end
        if hStim.Value, opts.beats = 'stimulated'; else, opts.beats = 'all'; end
        if ~isempty(S), analyze(false); end
    end

    function onAdvanced(~, ~)
        % advanced settings (2026-10-10): all parameters of the method that are based on assumptions or experience
        % (mda_options), one tab per part of the analysis; meaning: tooltips and the settings guide (button Guide).
        % Apply / OK analyse the window again (options marked 'read again': the window is read again). Save settings
        % ... / Load settings ...: settings file (mda_settings; results of an analysis can be loaded as well)
        if ~isempty(hAdv) && isvalid(hAdv), figure(hAdv); return; end
        advD = advancedDefs();
        advPending = struct();
        tabs = unique(advD(:, 8), 'stable');
        nMax = max(cellfun(@(t) nnz(strcmp(advD(:, 8), t)), tabs));
        rowH = 24; wid = 780;
        tabH = rowH * nMax + 44;
        hgt = tabH + 100;
        hAdv = figure('Name', 'MyoDishAnalysis - advanced settings', 'NumberTitle', 'off', 'MenuBar', 'none', ...
            'ToolBar', 'none', 'Color', 'w', 'Units', 'pixels', 'Position', [100 40 wid hgt], 'Resize', 'off', ...
            'HandleVisibility', 'callback');
        lightTheme(hAdv);
        movegui(hAdv, 'onscreen');
        tg = uitabgroup(hAdv, 'Units', 'pixels', 'Position', [6 96 wid-12 tabH]);
        tx = {'Style', 'text', 'Units', 'pixels', 'BackgroundColor', 'w', 'HorizontalAlignment', 'left'};
        advCtl = gobjects(size(advD, 1), 1);
        d0 = mda_options();
        for k = 1:numel(tabs)
            tb = uitab(tg, 'Title', tabs{k}, 'BackgroundColor', 'w');
            y = tabH - 30 - rowH - 4;
            for r = find(strcmp(advD(:, 8), tabs{k}))'
                d = advD(r, :);
                tip = d{5};
                if d{9}, tip = [tip ' (the window is read again)']; end
                uicontrol(tb, tx{:}, 'Position', [10 y 300 19], 'String', d{2}, 'FontSize', 9, 'TooltipString', tip);
                switch d{3}
                    case 'popup'
                        advCtl(r) = uicontrol(tb, 'Style', 'popupmenu', 'Units', 'pixels', 'Position', [314 y+2 170 22], ...
                            'String', d{4}(:,1)', 'BackgroundColor', 'w', 'FontSize', 9, 'TooltipString', tip);
                    case 'check'
                        advCtl(r) = uicontrol(tb, 'Style', 'checkbox', 'Units', 'pixels', 'Position', [314 y+2 170 22], ...
                            'String', '', 'BackgroundColor', 'w', 'TooltipString', tip);
                    otherwise                               %num / int (value x scale), numauto ('auto' or s), vec
                        w = 90; if strcmp(d{3}, 'vec'), w = 120; end
                        advCtl(r) = uicontrol(tb, 'Style', 'edit', 'Units', 'pixels', 'Position', [314 y+2 w 22], ...
                            'BackgroundColor', 'w', 'FontSize', 9, 'TooltipString', tip);
                end
                uicontrol(tb, tx{:}, 'Position', [492 y 270 19], 'String', advDefaultText(d, d0), 'FontSize', 8, ...
                    'ForegroundColor', [0.4 0.4 0.4], 'TooltipString', tip);
                y = y - rowH;
            end
        end
        advMsg = uicontrol(hAdv, tx{:}, 'Position', [12 46 wid-24 46], 'String', ['Hover over a name for its meaning; ' ...
            'Guide: settings guide with figures. Apply or OK analyses the loaded window again (* = the window is read ' ...
            'again). Settings are saved with every export and can be loaded from a settings file or from results.'], ...
            'FontSize', 8, 'ForegroundColor', uiBlueDark);
        bt = {'Style', 'pushbutton', 'Units', 'pixels', 'FontSize', 9};
        uicontrol(hAdv, bt{:}, 'Position', [12 10 80 28], 'String', 'Defaults', 'Callback', @(~,~) advShow(mda_options()), ...
            'TooltipString', 'show the default values (mda_options); Apply or OK uses them');
        uicontrol(hAdv, bt{:}, 'Position', [98 10 120 28], 'String', 'Load settings ...', 'Callback', @(~,~) advLoad(), ...
            'TooltipString', ['settings file (Save settings ...) or results of an analysis (.xlsx, _info.csv): all ' ...
            'settings except the threshold and zero force of the channels; Apply or OK uses them']);
        uicontrol(hAdv, bt{:}, 'Position', [224 10 120 28], 'String', 'Save settings ...', 'Callback', @(~,~) advSave(), ...
            'TooltipString', ['all settings as shown (with the rocker filter, detection and filters of the main ' ...
            'window) as a settings file (.csv): mda_options(''settings'', file), MyoDishAnalysis(..., ''settings'', file)']);
        uicontrol(hAdv, bt{:}, 'Position', [350 10 90 28], 'String', 'Guide', 'Callback', @(~,~) advGuide(), ...
            'TooltipString', 'settings guide (PDF): the parameters and the markers of the force plot with figures');
        uicontrol(hAdv, bt{:}, 'Position', [wid-298 10 90 28], 'String', 'Cancel', 'Callback', @(~,~) close(hAdv));
        uicontrol(hAdv, bt{:}, 'Position', [wid-202 10 90 28], 'String', 'Apply', 'Callback', @(~,~) advApply(false));
        uicontrol(hAdv, bt{:}, mainBtn{:}, 'Position', [wid-106 10 90 28], 'String', 'OK', 'Callback', @(~,~) advApply(true));
        advShow(opts);
    end

    function advShow(o)
        % values of the options o in the controls of the advanced settings window
        for r = 1:size(advD, 1)
            d = advD(r, :);
            if ~isgraphics(advCtl(r)), continue; end
            v = o.(d{1});
            switch d{3}
                case 'popup'
                    k = find(strcmp(d{4}(:,2), char(v)), 1);
                    if isempty(k), k = 1; end
                    advCtl(r).Value = k;
                case 'check'
                    advCtl(r).Value = logical(v);
                case 'numauto'
                    if ischar(v) || isstring(v), advCtl(r).String = 'auto'; else, advCtl(r).String = sprintf('%g', v); end
                case 'vec'
                    advCtl(r).String = strtrim(sprintf('%g ', v * d{6}));
                otherwise
                    advCtl(r).String = sprintf('%g', v * d{6});
            end
        end
    end

    function [o, err] = advRead()
        % options from the controls of the advanced settings window (and settings loaded for the main window), checked
        o = opts; err = '';
        for f2 = fieldnames(advPending)', o.(f2{1}) = advPending.(f2{1}); end
        for r = 1:size(advD, 1)
            d = advD(r, :);
            switch d{3}
                case 'popup'
                    o.(d{1}) = d{4}{advCtl(r).Value, 2};
                case 'check'
                    o.(d{1}) = logical(advCtl(r).Value);
                case 'numauto'
                    str = strtrim(advCtl(r).String);
                    if isempty(str) || strcmpi(str, 'auto')
                        o.(d{1}) = 'auto';
                    else
                        v = str2double(str);
                        if isnan(v), err = sprintf('%s: a number or auto.', d{2}); return; end
                        o.(d{1}) = v;
                    end
                case 'vec'
                    str = strtrim(strrep(advCtl(r).String, ',', ' '));
                    if isempty(str), o.(d{1}) = []; continue; end    %e.g. no arrhythmically paced channels
                    v = str2double(strsplit(str));
                    if any(isnan(v)), err = sprintf('%s: numbers separated by spaces.', d{2}); return; end
                    o.(d{1}) = v / d{6};
                otherwise
                    v = str2double(strtrim(advCtl(r).String));
                    if isnan(v), err = sprintf('%s: enter a number.', d{2}); return; end
                    o.(d{1}) = v / d{6};
            end
        end
        try
            o = mda_options(o);
        catch ME
            err = ME.message;
        end
    end

    function ok = advApply(closeIt)
        % options from the advanced settings window: checked (mda_options), then the window is analysed again
        [o, err] = advRead();
        ok = isempty(err);
        if ~ok, advMsg.String = err; return; end
        rr = advD([advD{:, 9}], 1);                     %options applied when the data are read
        reread = ~all(cellfun(@(n) isequaln(o.(n), opts.(n)), rr));
        header = ~isequaln(o.rockerSource, opts.rockerSource) || ~isequaln(o.rockerLogDelay, opts.rockerLogDelay);
        changed = ~isequaln(rmfield(o, 'referenceBeat'), rmfield(opts, 'referenceBeat'));
        opts = o;
        advPending = struct();
        hRF.Value = opts.rockerFilter;                  %settings of the main window (loaded settings)
        hDet.Value = 1 + strcmp(opts.detection, 'specific');
        hRocker.Value = strcmp(opts.rocker, 'stopped');
        hStim.Value = strcmp(opts.beats, 'stimulated');
        if closeIt, close(hAdv); else, advShow(opts); end
        advIndicator();
        msg = sprintf('Advanced settings: %s.', advChangedText());
        if isgraphics(advMsg), advMsg.String = msg; end
        if ~changed || isempty(H), status(msg); return; end
        if header                                       %rocker state of the file
            try H = mda_readMdd(H.file, [], [], opts); catch, end
        end
        if isempty(S), status(msg); return; end
        if reread && ~isempty(sbs)                      %rocker stops side by side: the same stops read again
            rf = w2f(range);
            if loadSegments(sbs.seg(:, 1:2)), range = mergeRanges(f2w(rf)); analyze(false); end
        elseif reread
            r0 = range;
            onLoad([], [], winReq);
            if ~isempty(S) && min(r0(:,1)) >= S.fromSeconds - 1e-9 && max(r0(:,2)) <= S.toSeconds + 1e-9, range = r0; analyze(false); end
        else
            analyze(false);
        end
        status([msg ' ' hStatus.String]);
    end

    function advSave()
        % all settings as shown in the window -> settings file (mda_settings)
        [o, err] = advRead();
        if ~isempty(err), advMsg.String = err; return; end
        if ~isempty(apiFile)
            file = apiFile; apiFile = '';
        else
            d0 = lastDir; if isempty(d0) && ~isempty(H), d0 = fileparts(H.file); end
            [fn, pn] = uiputfile({'*.csv', 'settings (*.csv)'}, 'Save settings', fullfile(d0, 'MyoDishAnalysis_settings.csv'));
            if isequal(fn, 0), return; end
            file = fullfile(pn, fn);
        end
        try
            file = mda_settings('save', file, o);
            advMsg.String = sprintf('Settings saved: %s (all options as shown; Apply or OK uses them here).', file);
        catch ME
            advMsg.String = ['Settings not saved: ' ME.message];
        end
    end

    function advLoad()
        % settings file or results -> controls of the window (and the settings of the main window at Apply / OK)
        if ~isempty(apiFile)
            file = apiFile; apiFile = '';
        else
            d0 = lastDir; if isempty(d0) && ~isempty(H), d0 = fileparts(H.file); end
            [fn, pn] = uigetfile({'*.csv;*.xlsx', 'settings or results (*.csv, *.xlsx)'}, 'Load settings', d0);
            if isequal(fn, 0), return; end
            file = fullfile(pn, fn);
        end
        try
            [o, notes] = mda_settings('load', file);
        catch ME
            advMsg.String = ['Settings not loaded: ' ME.message]; return;
        end
        main = setdiff(fieldnames(o), [advD(:, 1); {'threshold'; 'zeroForce'; 'referenceBeat'}]);
        advPending = struct();
        for f2 = main', advPending.(f2{1}) = o.(f2{1}); end
        advShow(o);
        [~, n, e] = fileparts(file);
        msg = sprintf('Loaded %s: Apply or OK uses these settings (with rocker filter %s, %s, rocker %s, beats %s).', ...
            [n e], mat2str(logical(o.rockerFilter)), o.detection, o.rocker, o.beats);
        if ~isempty(notes), msg = [msg ' ' strjoin(notes, ' ')]; end
        advMsg.String = msg;
    end

    function advGuide()
        % settings guide (PDF next to the code: docs/MyoDishAnalysis_settings_guide.pdf)
        pdf = fullfile(fileparts(mfilename('fullpath')), 'docs', 'MyoDishAnalysis_settings_guide.pdf');
        if ~exist(pdf, 'file'), advMsg.String = ['Settings guide not found: ' pdf]; return; end
        if ispc, winopen(pdf);
        elseif ismac, system(['open "' pdf '" &']);
        else, system(['xdg-open "' pdf '" &']);
        end
    end

    function txt = advChangedText()
        % options of the advanced settings window that differ from the defaults
        d0 = mda_options();
        nm = {};
        for r = 1:size(advD, 1)
            d = advD(r, :);
            if sameOpt(opts.(d{1}), d0.(d{1})), continue; end
            v = opts.(d{1});
            if ischar(v), vs = v; elseif islogical(v), vs = mat2str(v); else, vs = strtrim(sprintf('%g ', v)); end
            nm{end+1} = sprintf('%s = %s', d{1}, vs); %#ok<AGROW>
        end
        if isempty(nm), txt = 'defaults'; else, txt = ['changed: ' strjoin(nm, ', ')]; end
    end

    function onSizeChanged()
        advIndicator();
        fitMargins();
    end

    function advIndicator()
        % 'Advanced ...' button (2026-10-14): number of advanced settings that differ from the defaults, in red; the
        % longest text that fits the button ('Advanced (3 changed)', ... 'Adv. (3)'); tooltip: the changed settings
        if isempty(hAdvBtn) || ~isgraphics(hAdvBtn), return; end
        nm = advChanges(opts);
        n = numel(nm);
        if n == 0
            if ~strcmp(hAdvBtn.String, 'Advanced ...'), hAdvBtn.String = 'Advanced ...'; end
            hAdvBtn.ForegroundColor = [0 0 0];
            hAdvBtn.TooltipString = [advTip0 '. All advanced settings have their default values.'];
            return;
        end
        cand = {sprintf('Advanced (%d changed)', n), sprintf('Advanced (%d chgd)', n), sprintf('Adv. (%d chgd)', n), ...
            sprintf('Adv. (%d)', n)};
        room = hAdvBtn.Position(3) * 0.9;              %(normalized units: Extent as Position; 10 % for the bevel)
        for k = 1:numel(cand)
            if ~strcmp(hAdvBtn.String, cand{k}), hAdvBtn.String = cand{k}; end
            if hAdvBtn.Extent(3) <= room, break; end
        end
        hAdvBtn.ForegroundColor = [0.75 0 0];
        hAdvBtn.TooltipString = sprintf(['%d advanced setting(s) differ from the defaults (values as in settings ' ...
            'files):\n%s\n\n%s'], n, strjoin(nm, newline), advTip0);
    end

    function [o, h] = apiAdvanced(chg)
        % tests / scripts: the advanced settings chg (struct) as typed in the window, then Apply; chg = 'save' / 'load'
        % with api.nextFile(file) before: Save settings ... / Load settings ...
        if nargin < 1 || isempty(chg), o = opts; h = hAdv; return; end
        onAdvanced();
        if ischar(chg)
            if strcmp(chg, 'save'), advSave(); else, advLoad(); end
            o = opts; h = hAdv; return;
        end
        o2 = opts;
        for f2 = fieldnames(chg)', o2.(f2{1}) = chg.(f2{1}); end
        advShow(o2);
        advApply(false);
        o = opts; h = hAdv;
    end

    function apiZeroAt(xy)
        altPt = xy; setZeroAtClick();                      %as a right click at [x y] of the force plot (tests)
    end

    function setZeroAtClick()
        % right click in the force plot: the y value of the mouse pointer becomes the zero force of the channel
        if isempty(S) || isempty(C) || any(isnan(altPt)), status('Right-click into the force plot.'); return; end
        z0 = mda_zeroForce(S, ch, zeroUser(ch), altPt(1));   %zero currently subtracted in the plot
        if isnan(z0), z0 = 0; end                            %plot shows the sensor signal
        zeroUser(ch) = altPt(2) + z0;
        hZero.String = sprintf('%.0f', zeroUser(ch));
        plotOverview();
        analyze(false);
        status(sprintf('Zero force of channel %d set to %.0f %sN (sensor signal at the mouse pointer).', ch, zeroUser(ch), mu));
    end

    function resetZero()
        zeroUser(ch) = nan; hZero.String = '';
        plotOverview();
        if ~isempty(S), analyze(false); end
    end

    function zeroMenuText(cm)
        hs = findobj(cm, 'Tag', 'rockerStops');         %only with 'only contractions with rocker at rest' (2026-10-14)
        if ~isempty(hs)
            if hRocker.Value, hs.Enable = 'on'; else, hs.Enable = 'off'; end
        end
        h = findobj(cm, 'Tag', 'zeroHere');
        if isempty(h), return; end
        if any(isnan(altPt))
            h.Text = 'Set as zero force (y at the mouse pointer)';
        else
            h.Text = sprintf('Set as zero force here (y = %.0f %sN in the plot)', altPt(2), mu);
        end
    end

    function onZero(~, ~)
        str = strtrim(hZero.String);
        if isempty(str)
            zeroUser(ch) = nan;                    %back to the Offset entry of the log file
        else
            v = str2double(str);
            if isnan(v), status('Zero force: enter a number (uN) or leave empty (= log file).'); return; end
            zeroUser(ch) = v;
        end
        plotOverview();
        if ~isempty(S), analyze(false); end
    end

    function onWholeWindow(~, ~)
        if isempty(S), return; end
        range = [S.fromSeconds S.toSeconds];
        refresh(false);
    end

    % ---------------------------------------------------------------- overlay of contractions (several selections / channels)
    % 2026-10-07: other channels of the same range (checkboxes), time course of the range (t = 0 at the first stimulus),
    % colour, line width, line style and band (SD / SEM / range) per group, editable title, axis labels and legend,
    % editable copy of the figure
    function onOverlay(~, ~)
        % opens the overlay window with the current selection, or adds the current selection as a new group
        if ~isempty(hOv) && isvalid(hOv.fig)
            if addOverlayGroup(), drawOverlay(); end
            figure(hOv.fig); return;
        end
        ovG = []; ovNextColor = 0;
        if ~addOverlayGroup(), return; end
        openOverlayWindow();
    end

    function openOverlayWindow()
        f2 = figure('Name', 'MyoDishAnalysis: overlay', 'NumberTitle', 'off', 'Color', 'w', 'Units', 'pixels', ...
            'Position', [140 90 1200 720], 'DeleteFcn', @(~,~) clearOverlayState());
        lightTheme(f2);
        movegui(f2, 'onscreen');
        d = {'Units', 'normalized', 'FontSize', 10, 'BackgroundColor', 'w'};
        axO = axes(f2, 'Position', [0.07 0.2 0.6 0.74]); box(axO, 'on');
        uicontrol(f2, d{:}, 'Style', 'text', 'String', 'Groups (one per added selection or channel):', 'HorizontalAlignment', 'left', ...
            'Position', [0.7 0.945 0.29 0.035]);
        lb = uicontrol(f2, d{:}, 'Style', 'listbox', 'String', {}, 'Position', [0.7 0.7 0.29 0.245], 'FontSize', 9, ...
            'Callback', @(~,~) showGroupStyle());
        uicontrol(f2, d{:}, 'Style', 'pushbutton', 'String', 'Add current selection', 'Position', [0.7 0.645 0.14 0.045], ...
            'Callback', @(~,~) addAndDraw(), 'TooltipString', 'contractions selected in the main window (channel, range, filters, exclusions)');
        uicontrol(f2, d{:}, 'Style', 'pushbutton', 'String', 'Channels (same range) ...', 'Position', [0.85 0.645 0.14 0.045], ...
            'Callback', @(~,~) chooseChannels(), 'TooltipString', ['channels for the analysed range of the main window (checkboxes): ' ...
            'same settings and filters, threshold and zero force of each channel; manual exclusions only in the channel of the main window']);
        uicontrol(f2, d{:}, 'Style', 'pushbutton', 'String', 'Remove group', 'Position', [0.7 0.595 0.14 0.045], 'Callback', @(~,~) removeGroup());
        uicontrol(f2, d{:}, 'Style', 'pushbutton', 'String', 'Clear all', 'Position', [0.85 0.595 0.14 0.045], 'Callback', @(~,~) clearGroups());
        al = uicontrol(f2, d{:}, 'Style', 'popupmenu', 'String', {'mean beat: align at the stimulus (t = 0)', ...
            'mean beat: align at the peak (t = 0)', 'time course of the range: t = 0 at the first stimulus'}, ...
            'Position', [0.7 0.545 0.29 0.04], 'Callback', @(~,~) drawOverlay(), 'TooltipString', ...
            'time course: force of the whole range of each group, t = 0 at its first stimulus (the channels are not stimulated at the same time)');
        c1 = uicontrol(f2, d{:}, 'Style', 'checkbox', 'String', 'single contractions', 'Value', 1, 'Position', [0.7 0.505 0.29 0.035], ...
            'Callback', @(~,~) drawOverlay());
        c2 = uicontrol(f2, d{:}, 'Style', 'checkbox', 'String', 'subtract diastolic force (developed force)', 'Value', 1, ...
            'Position', [0.7 0.47 0.29 0.035], 'Callback', @(~,~) drawOverlay());
        c3 = uicontrol(f2, d{:}, 'Style', 'checkbox', 'String', 'normalize (amplitude = 1)', 'Value', 0, 'Position', [0.7 0.435 0.29 0.035], ...
            'Callback', @(~,~) drawOverlay());
        pG = uipanel(f2, 'Position', [0.7 0.215 0.29 0.21], 'Title', 'Selected group: legend, line, band', 'BackgroundColor', 'w', 'FontSize', 9, pnlStyle{:});
        uicontrol(pG, d{:}, 'Style', 'text', 'String', 'legend', 'HorizontalAlignment', 'left', 'Position', [0.03 0.72 0.18 0.17]);
        gName = uicontrol(pG, d{:}, 'Style', 'edit', 'String', '', 'HorizontalAlignment', 'left', 'Position', [0.21 0.74 0.76 0.18], ...
            'Callback', @(s,~) setGroupStyle('name', s.String), 'TooltipString', 'legend text of the group (empty = automatic)');
        uicontrol(pG, d{:}, 'Style', 'pushbutton', 'String', 'colour ...', 'Position', [0.03 0.51 0.26 0.18], 'Callback', @(~,~) pickGroupColor());
        uicontrol(pG, d{:}, 'Style', 'text', 'String', 'width', 'HorizontalAlignment', 'right', 'Position', [0.3 0.49 0.13 0.17]);
        gWidth = uicontrol(pG, d{:}, 'Style', 'edit', 'String', '2', 'Position', [0.44 0.51 0.13 0.18], ...
            'Callback', @(s,~) setGroupStyle('width', str2double(s.String)), 'TooltipString', 'line width of the mean (points)');
        gLine = uicontrol(pG, d{:}, 'Style', 'popupmenu', 'String', ovLineNames, 'Position', [0.6 0.51 0.37 0.18], ...
            'Callback', @(s,~) setGroupStyle('style', ovLineStyles{s.Value}));
        gBand = uicontrol(pG, d{:}, 'Style', 'popupmenu', 'String', ovBandNames, 'Position', [0.03 0.28 0.94 0.18], ...
            'Callback', @(s,~) setGroupStyle('band', ovBands{s.Value}), 'TooltipString', 'transparent band around the mean (mean beat)');
        uicontrol(pG, d{:}, 'Style', 'pushbutton', 'String', 'line and band for all groups', 'Position', [0.03 0.05 0.94 0.18], ...
            'Callback', @(~,~) styleToAll(), 'TooltipString', 'width, line style and band of the selected group for all groups (colours and legends stay)');
        uicontrol(f2, d{:}, 'Style', 'pushbutton', 'String', 'Save figure ...', 'Position', [0.7 0.155 0.093 0.045], ...
            'Callback', @(~,~) saveOverlayFigure(), 'TooltipString', '.png / .jpg / .tif / .fig');
        uicontrol(f2, d{:}, 'Style', 'pushbutton', 'String', 'Export data ...', 'Position', [0.798 0.155 0.093 0.045], ...
            'Callback', @(~,~) exportOverlay(), 'TooltipString', ...
            'mean, SD, SEM, min, max, n and all single traces of every group (time course: the traces): .xlsx / .csv / .txt');
        uicontrol(f2, d{:}, 'Style', 'pushbutton', 'String', 'Edit figure ...', 'Position', [0.896 0.155 0.094 0.045], ...
            'Callback', @(~,~) editOverlayFigure(), 'TooltipString', ...
            'copy of the plot as a normal MATLAB figure: edit everything (texts, lines, axes, legend) with the plot tools, save from its menu');
        % texts of the figure (empty = automatic)
        uicontrol(f2, d{:}, 'Style', 'text', 'String', 'title', 'HorizontalAlignment', 'right', 'Position', [0.005 0.083 0.04 0.03]);
        eT = uicontrol(f2, d{:}, 'Style', 'edit', 'String', '', 'HorizontalAlignment', 'left', 'Position', [0.05 0.085 0.4 0.038], ...
            'Callback', @(~,~) drawOverlay(), 'TooltipString', 'title of the plot (empty = automatic)');
        uicontrol(f2, d{:}, 'Style', 'text', 'String', 'legend', 'HorizontalAlignment', 'right', 'Position', [0.455 0.083 0.05 0.03]);
        eL = uicontrol(f2, d{:}, 'Style', 'popupmenu', 'String', ovLegendNames, 'Position', [0.51 0.087 0.16 0.038], ...
            'Callback', @(~,~) drawOverlay(), 'TooltipString', 'position of the legend');
        uicontrol(f2, d{:}, 'Style', 'text', 'String', 'x axis', 'HorizontalAlignment', 'right', 'Position', [0.005 0.033 0.04 0.03]);
        eX = uicontrol(f2, d{:}, 'Style', 'edit', 'String', '', 'HorizontalAlignment', 'left', 'Position', [0.05 0.035 0.29 0.038], ...
            'Callback', @(~,~) drawOverlay(), 'TooltipString', 'label of the x axis (empty = automatic)');
        uicontrol(f2, d{:}, 'Style', 'text', 'String', 'y axis', 'HorizontalAlignment', 'right', 'Position', [0.345 0.033 0.04 0.03]);
        eY = uicontrol(f2, d{:}, 'Style', 'edit', 'String', '', 'HorizontalAlignment', 'left', 'Position', [0.39 0.035 0.28 0.038], ...
            'Callback', @(~,~) drawOverlay(), 'TooltipString', 'label of the y axis (empty = automatic)');
        mo = uimenu(f2, 'Text', 'Save / Export');
        uimenu(mo, 'Text', 'Save overlay figure (.png / .jpg / .tif / .fig) ...', 'MenuSelectedFcn', @(~,~) saveOverlayFigure());
        uimenu(mo, 'Text', 'Export overlay data (.xlsx / .csv / .txt) ...', 'MenuSelectedFcn', @(~,~) exportOverlay());
        uimenu(mo, 'Text', 'Edit figure (copy with the MATLAB plot tools) ...', 'MenuSelectedFcn', @(~,~) editOverlayFigure());
        tx = uicontrol(f2, d{:}, 'Style', 'text', 'String', '', 'HorizontalAlignment', 'left', 'Position', [0.7 0.01 0.29 0.135], 'FontSize', 9);
        hOv = struct('fig', f2, 'axO', axO, 'lb', lb, 'al', al, 'single', c1, 'base', c2, 'norm', c3, 'tx', tx, ...
            'gName', gName, 'gWidth', gWidth, 'gLine', gLine, 'gBand', gBand, 'title', eT, 'xlab', eX, 'ylab', eY, 'legend', eL);
        drawOverlay();
    end

    function ok = addOverlayGroup()
        % current selection of the main window --> new overlay group
        ok = false;
        if isempty(B) || isempty(C), status('Load a time window first.'); return; end
        sel = find(selected());
        if isempty(sel), status('No contraction selected.'); return; end
        ok = addGroupOf(B, C, ch, sel);
    end

    function ok = addGroupOf(Bx, Cx, chX, sel)
        % new overlay group of channel chX: segments of the filtered signal around the selected contractions
        % (peak - 1 s ... peak + 1.6 s) and the force of the analysed range (time course, t = 0 at its first stimulus)
        ok = true;
        key = sprintf('%d|%s|%d|%.6f', chX, mat2str(range, 8), numel(sel), sum(Bx.t_peak(sel)));
        if ~isempty(ovG) && any(strcmp({ovG.key}, key))
            status('This selection is already in the overlay.'); return;
        end
        pre = round(1.0 / S.dt); post = round(1.6 / S.dt);
        [~, loc] = ismember(Bx.t_peak(sel), Cx.peakTimes);
        idx = Cx.iPeaks(loc); idx = idx(:);
        n = numel(sel); N = numel(Cx.f);
        seg = nan(n, pre + post + 1);
        for k = 1:n
            a = idx(k) - pre; b = idx(k) + post;
            ia = max(1, a); ib = min(N, b);
            seg(k, (ia - a + 1):(ib - a + 1)) = Cx.f(ia:ib);
        end
        G.key = key;
        G.seg = seg; G.dt = S.dt; G.pre = pre;
        G.stimRel = reshape(Bx.t_stim(sel), [], 1) - reshape(Cx.peakTimes(loc), [], 1);   %stimulus relative to the peak (NaN: none)
        G.dia = reshape(Bx.diastolicSignal(sel), [], 1);
        G.amp = reshape(Bx.amplitude(sel), [], 1);
        G.zero = Cx.zeroForce;
        G.pp = median(Bx.peakToPeakInterval(sel), 'omitnan');
        G.ch = chX; G.range = range;
        sp = rngSpan(); G.span = w2f(sp);                 %first start / last end (time in the file)
        st = Cx.stimTimes(inRng(Cx.stimTimes));
        G.noStim = isempty(st);
        if G.noStim, G.t0 = sp(1); else, G.t0 = st(1); end
        inS = Cx.t >= sp(1) & Cx.t <= sp(2);              %time course: outside the range(s) NaN
        y = reshape(Cx.f(inS), 1, []); y(~inRng(reshape(Cx.t(inS), 1, []))) = nan;
        G.trT = reshape(Cx.t(inS), 1, []) - G.t0; G.trY = y;
        lab = sprintf('Ch %d, %s - %s, n = %d', chX, fmtClock(G.span(1), H.totalSeconds >= 3600, true), ...
            fmtClock(G.span(2), H.totalSeconds >= 3600, true), n);
        if size(range, 1) > 1, lab = sprintf('%s (%d ranges)', lab, size(range, 1)); end
        r = find(Lbl.channel == chX, 1);
        if ~isempty(r)
            for nm = {'treatment','sliceID'}
                if ismember(nm{1}, Lbl.Properties.VariableNames) && ~isempty(Lbl.(nm{1}){r}), lab = [lab ', ' Lbl.(nm{1}){r}]; end %#ok<AGROW>
            end
        end
        G.label = lab;
        ovNextColor = ovNextColor + 1;                     %default colours in the order of adding (stay when groups are removed)
        cols = lines(7);
        G.color = cols(mod(ovNextColor - 1, 7) + 1, :);
        G.width = 2; G.style = '-'; G.band = 'none'; G.name = '';
        if isempty(ovG), ovG = G; else, ovG(end+1) = G; end
        status(sprintf('Overlay: group %d added (%s).', numel(ovG), lab));
    end

    function chooseChannels()
        % checkboxes: channels with a group for the analysed range of the main window (ticked = added, unticked = removed)
        if isempty(S) || isempty(H), status('Load a time window first.'); return; end
        chs = reshape(S.dataChannels, 1, []);
        nC = numel(chs);
        have = false(1, nC);
        for k = 1:nC, have(k) = ~isempty(groupsOf(chs(k))); end
        hrs = H.totalSeconds >= 3600;
        dlg = dialog('Name', 'Overlay: channels', 'Units', 'pixels', 'Position', [300 300 360 112 + 24 * nC]);
        uicontrol(dlg, 'Style', 'text', 'Units', 'pixels', 'Position', [10 62 + 24 * nC 340 42], 'HorizontalAlignment', 'left', ...
            'String', sprintf('Channels for the analysed range %s - %s (same settings; manual exclusions only in channel %d):', ...
            fmtClock(w2f(min(range(:,1))), hrs, true), fmtClock(w2f(max(range(:,2))), hrs, true), ch));
        cb = gobjects(1, nC);
        for k = 1:nC
            cb(k) = uicontrol(dlg, 'Style', 'checkbox', 'Units', 'pixels', 'Position', [20 52 + 24 * (nC - k) 320 22], ...
                'String', sprintf('Channel %d', chs(k)), 'Value', have(k));
        end
        uicontrol(dlg, 'Style', 'pushbutton', 'Units', 'pixels', 'Position', [170 12 80 28], 'String', 'OK', 'Callback', @(s,~) closeDialog(s, true));
        uicontrol(dlg, 'Style', 'pushbutton', 'Units', 'pixels', 'Position', [260 12 80 28], 'String', 'Cancel', 'Callback', @(s,~) closeDialog(s, false));
        uiwait(dlg);
        if ~isvalid(dlg), return; end                       %closed with the window button
        okD = isequal(dlg.UserData, true);
        want = chs([cb.Value] == 1);
        delete(dlg);
        if okD, setOverlayChannels(want); end
    end

    function setOverlayChannels(want)
        % groups of the analysed range of the main window: exactly the channels want (groups of other channels of this
        % range removed); the channel of the main window with its selection, the others analysed with the same settings
        if isempty(S) || isempty(B), status('Load a time window first.'); return; end
        if isempty(hOv) || ~isvalid(hOv.fig), ovG = []; ovNextColor = 0; end
        chs = reshape(S.dataChannels, 1, []);
        want = chs(ismember(chs, want));
        for c = chs(~ismember(chs, want))
            k = groupsOf(c);
            if ~isempty(k), ovG(k) = []; end
        end
        notes = {};
        for c = want
            if ~isempty(groupsOf(c)), continue; end
            if c == ch
                sel = find(selected());
                Bx = B; Cx = C;
            else
                status(sprintf('Overlay: analysing channel %d ...', c)); drawnow;
                try
                    [Bx, Cx] = analyzeOther(c);
                catch ME
                    notes{end+1} = sprintf('channel %d: %s', c, ME.message); continue; %#ok<AGROW>
                end
                s = Bx.included & inRng(Bx.t_peak);
                if refExclude, s = s & ~deviatingOf(Bx, Cx); end
                sel = find(s);
            end
            if isempty(sel), notes{end+1} = sprintf('channel %d: no contraction selected', c); continue; end %#ok<AGROW>
            addGroupOf(Bx, Cx, c, sel);
        end
        if isempty(hOv) || ~isvalid(hOv.fig)
            if isempty(ovG), status(strjoin([{'Overlay: no group.'}, notes], ' ')); return; end
            openOverlayWindow();
        else
            drawOverlay();
        end
        if ~isempty(notes), status(['Overlay: ' strjoin(notes, '; ')]); end
    end

    function [Bx, Cx] = analyzeOther(c)
        % channel c of the loaded window with the settings of the main window (threshold and zero force of channel c)
        optsC = opts;
        optsC.zeroForce = zeroUser(c);
        optsC.threshold = thrOf(c);
        Sa = S;
        if opts.rockerFilter && isempty(sbs), Sa = rockerFiltered(optsC, c); end
        [Bx, Cx] = mda_analyzeChannel(Sa, c, [], optsC);
        [Bx, Cx] = cutJunctions(Bx, Cx);
    end

    function k = groupsOf(c)
        % overlay groups of channel c for the analysed range of the main window
        k = [];
        if isempty(ovG), return; end
        k = find([ovG.ch] == c & arrayfun(@(G) isequal(size(G.range), size(range)) && all(abs(G.range(:) - range(:)) < 1e-6), ovG));
    end

    function addAndDraw()
        if addOverlayGroup(), drawOverlay(); end
    end

    function removeGroup()
        if isempty(ovG) || isempty(hOv) || ~isvalid(hOv.fig), return; end
        k = hOv.lb.Value;
        if k >= 1 && k <= numel(ovG), ovG(k) = []; end
        hOv.lb.Value = max(1, min(k, numel(ovG)));
        drawOverlay();
    end

    function clearGroups()
        ovG = []; ovNextColor = 0;
        if ~isempty(hOv) && isvalid(hOv.fig), hOv.lb.Value = 1; drawOverlay(); end
    end

    function clearOverlayState()
        ovG = []; hOv = [];
    end

    function g = selectedGroup()
        g = min(max(1, hOv.lb.Value), numel(ovG));
    end

    function showGroupStyle()
        % controls of the selected group (legend text, line width, line style, band)
        if isempty(hOv) || ~isvalid(hOv.fig), return; end
        h = [hOv.gName hOv.gWidth hOv.gLine hOv.gBand];
        if isempty(ovG), set(h, 'Enable', 'off'); hOv.gName.String = ''; return; end
        set(h, 'Enable', 'on');
        g = selectedGroup();
        hOv.gName.String = legendName(g);
        hOv.gWidth.String = sprintf('%g', ovG(g).width);
        hOv.gLine.Value = find(strcmp(ovLineStyles, ovG(g).style), 1);
        hOv.gBand.Value = find(strcmp(ovBands, ovG(g).band), 1);
    end

    function setGroupStyle(field, value)
        if isempty(ovG) || isempty(hOv) || ~isvalid(hOv.fig), return; end
        g = selectedGroup();
        switch field
            case 'width'
                if ~isscalar(value) || ~isfinite(value) || value <= 0
                    showGroupStyle(); status('Line width: enter a positive number.'); return;
                end
            case 'name'
                value = strtrim(char(value));
                if strcmp(value, sprintf('%d: %s', g, ovG(g).label)), value = ''; end   %automatic text
        end
        ovG(g).(field) = value;
        drawOverlay();
    end

    function pickGroupColor()
        if isempty(ovG) || isempty(hOv) || ~isvalid(hOv.fig), return; end
        c = uisetcolor(ovG(selectedGroup()).color, 'Colour of the group');
        if numel(c) == 3, setGroupStyle('color', c); end
    end

    function styleToAll()
        if isempty(ovG) || isempty(hOv) || ~isvalid(hOv.fig), return; end
        G = ovG(selectedGroup());
        for g = 1:numel(ovG)
            ovG(g).width = G.width; ovG(g).style = G.style; ovG(g).band = G.band;
        end
        drawOverlay();
    end

    function s = legendName(g)
        s = ovG(g).name;
        if isempty(s), s = sprintf('%d: %s', g, ovG(g).label); end
    end

    function [xg, M, SD, nn, Yall] = overlayCurves(G)
        % traces of one group on a common time grid (alignment, baseline, normalization as chosen in the window)
        alignStim = hOv.al.Value ~= 2;
        x0 = ((1:size(G.seg, 2)) - G.pre - 1) * G.dt;          %time relative to the peak
        Y = G.seg;
        if hOv.base.Value
            Y = Y - G.dia;                                      %developed force
        elseif ~isnan(G.zero)
            Y = Y - G.zero;                                     %force - zero force
        end
        if hOv.norm.Value, Y = Y ./ G.amp; end
        if alignStim
            sh = -G.stimRel;                                    %peak relative to the stimulus
        else
            sh = zeros(size(G.stimRel));
        end
        v = find(~isnan(sh));
        xg = (round((x0(1) + min([sh(v); 0])) / G.dt) : round((x0(end) + max([sh(v); 0])) / G.dt)) * G.dt;
        Yall = nan(numel(v), numel(xg));
        for k = 1:numel(v)
            Yall(k,:) = interp1(x0 + sh(v(k)), Y(v(k),:), xg, 'linear', nan);
        end
        nn = sum(~isnan(Yall), 1);
        M = mean(Yall, 1, 'omitnan'); SD = std(Yall, 0, 1, 'omitnan');
        M(nn < 0.5 * numel(v)) = nan; SD(nn < 0.5 * numel(v)) = nan;
    end

    function [x, y] = overlayTrace(G)
        % time course of the range of one group (t = 0 at its first stimulus; baseline and normalization as chosen:
        % median diastolic force / amplitude of its contractions)
        x = G.trT; y = G.trY;
        if isempty(x), return; end
        if hOv.base.Value
            y = y - median(G.dia, 'omitnan');
        elseif ~isnan(G.zero)
            y = y - G.zero;
        end
        if hOv.norm.Value, y = y / median(G.amp, 'omitnan'); end
    end

    function [xl, yl, tt] = overlayTexts(mode)
        % axis labels and title: the texts typed in the window, otherwise automatic
        xs = {'time from the stimulus (s)', 'time from the peak (s)', 'time from the first stimulus of the range (s)'};
        xl = xs{mode};
        if hOv.norm.Value
            yl = 'force / amplitude';
        elseif hOv.base.Value
            yl = ['force - diastolic force (' mu 'N)'];
        else
            yl = ['force - zero force (' mu 'N)'];
        end
        if mode == 3
            tt = 'force of the analysed range of each group';
        elseif hOv.single.Value
            tt = 'thick: mean of each group; thin: single contractions';
        else
            tt = 'mean of each group';
        end
        if ~isempty(strtrim(hOv.xlab.String)), xl = hOv.xlab.String; end
        if ~isempty(strtrim(hOv.ylab.String)), yl = hOv.ylab.String; end
        if ~isempty(strtrim(hOv.title.String)), tt = hOv.title.String; end
    end

    function drawOverlay()
        if isempty(hOv) || ~isvalid(hOv.fig), return; end
        axO = hOv.axO;
        delete(findall(axO, 'Type', 'patch')); delete(findall(axO, 'Type', 'constantline'));   %hidden handles: not deleted by cla
        cla(axO); hold(axO, 'on'); legend(axO, 'off');
        hOv.lb.String = {};
        if isempty(ovG)
            title(axO, 'no group: select contractions in the main window and press "Add current selection"', 'FontWeight', 'normal');
            hOv.tx.String = ''; showGroupStyle(); return;
        end
        mode = hOv.al.Value;                               %1 = stimulus, 2 = peak, 3 = time course of the range
        hm = gobjects(0); names = {}; info = {};
        xr = [inf -inf];
        for g = 1:numel(ovG)
            G = ovG(g);
            col = G.color;
            if mode == 3
                [x, y] = overlayTrace(G);
                if isempty(x), continue; end
                hm(end+1) = plot(axO, x, y, 'Color', col, 'LineWidth', G.width, 'LineStyle', G.style); %#ok<AGROW>
                names{end+1} = legendName(g); %#ok<AGROW>
                xr = [min(xr(1), x(1)), max(xr(2), x(end))];
                if G.noStim, info{end+1} = sprintf('group %d: no stimulus in the range, t = 0 at its start', g); end %#ok<AGROW>
                continue;
            end
            [xg, M, SD, nn, Yall] = overlayCurves(G);
            if hOv.single.Value && ~isempty(Yall)
                plot(axO, xg, Yall', 'Color', 0.35 * col + 0.65, 'LineWidth', 0.5, 'HitTest', 'off');
            end
            if ~isempty(Yall)
                [lo, hi] = overlayBand(G.band, M, SD, nn, Yall);
                if ~isempty(lo), bandPatch(axO, xg, lo, hi, col); end
                hm(end+1) = plot(axO, xg, M, 'Color', col, 'LineWidth', G.width, 'LineStyle', G.style); %#ok<AGROW>
                names{end+1} = legendName(g); %#ok<AGROW>
            end
            nNo = size(G.seg, 1) - size(Yall, 1);
            if nNo > 0, info{end+1} = sprintf('group %d: %d contraction(s) without stimulus not shown', g, nNo); end %#ok<AGROW>
        end
        hOv.lb.String = arrayfun(@(g) sprintf('%d: %s', g, ovG(g).label), 1:numel(ovG), 'UniformOutput', false);
        hOv.lb.Value = selectedGroup();
        if mode == 3
            if all(isfinite(xr)) && xr(2) > xr(1), xlim(axO, xr); end
            xline(axO, 0, '--', 'Color', uiBlue, 'HandleVisibility', 'off');
            info = [{'time course: one trace per group (bands and single contractions: mean beat only)'}, info];
        else
            L = median([ovG.pp], 'omitnan'); if isnan(L), L = 1; end
            if mode == 1
                xlim(axO, [-0.1, min(1.5, max(0.3, 0.95 * L))]);
                xline(axO, 0, '--', 'Color', uiBlue, 'HandleVisibility', 'off');
            else
                xlim(axO, [-min(0.4, 0.45 * L), min(1.5, 0.9 * L)]);
            end
        end
        [xs, ys, ts] = overlayTexts(mode);
        xlabel(axO, xs); ylabel(axO, ys);
        loc = ovLegendLoc{hOv.legend.Value};
        if ~isempty(hm) && ~isempty(loc), legend(axO, hm, names, 'Location', loc, 'Interpreter', 'none', 'FontSize', 8); end
        grid(axO, 'on');
        % y limits from the data in the visible time range (lines and bands; also after normalizing or zooming)
        xl = xlim(axO); lo = inf; hi = -inf;
        for hL = reshape([findobj(axO, 'Type', 'line'); findall(axO, 'Type', 'patch')], 1, [])
            xd = hL.XData(:); yd = hL.YData(:);
            in = xd >= xl(1) & xd <= xl(2);
            lo = min([lo; yd(in)]); hi = max([hi; yd(in)]);
        end
        if isfinite(lo) && isfinite(hi) && hi > lo
            ylim(axO, [lo hi] + [-0.05 0.08] * (hi - lo));
        else
            ylim(axO, 'auto');
        end
        if isempty(strtrim(hOv.title.String))
            title(axO, ts, 'FontWeight', 'normal', 'FontSize', 9, 'Interpreter', 'none');
        else
            title(axO, ts, 'FontWeight', 'bold', 'FontSize', 12, 'Interpreter', 'none');
        end
        if isempty(info), info = {'all contractions shown'}; end
        hOv.tx.String = info;
        showGroupStyle();
    end

    function exportOverlay()
        % mean beat: mean, SD, SEM, min, max, n of every group on a common time grid + all single traces (one table per
        % group); time course: the traces of all groups on a common grid; sheet 'groups' with labels and settings
        if isempty(ovG) || isempty(hOv) || ~isvalid(hOv.fig), return; end
        file = askFile('data', 'overlay');
        if isempty(file), return; end
        mode = hOv.al.Value;
        dt = min([ovG.dt]);
        nG = numel(ovG);
        names = {'means'}; tabs = {[]};
        nTr = zeros(nG, 1);
        if mode == 3
            cur = cell(1, nG); xmin = inf; xmax = -inf;
            for g = 1:nG
                [x, y] = overlayTrace(ovG(g)); cur{g} = {x, y};
                if ~isempty(x), xmin = min(xmin, x(1)); xmax = max(xmax, x(end)); end
            end
            if ~isfinite(xmin), xmin = 0; xmax = 0; end
            tt = (round(xmin / dt) : round(xmax / dt))' * dt;
            Tm = table(tt, 'VariableNames', {'t_from_first_stimulus_s'});
            for g = 1:nG
                if numel(cur{g}{1}) < 2, y = nan(size(tt)); else, y = interp1(cur{g}{1}, cur{g}{2}, tt); end
                Tm.(sprintf('g%d', g)) = y(:);
                nTr(g) = double(~isempty(cur{g}{1}));
            end
            names{1} = 'traces';
        else
            cur = cell(1, nG); xmin = inf; xmax = -inf;
            for g = 1:nG
                [xg, M, SD, nn, Yall] = overlayCurves(ovG(g));
                cur{g} = {xg, M, SD, nn, Yall};
                if ~isempty(xg), xmin = min(xmin, xg(1)); xmax = max(xmax, xg(end)); end
            end
            tt = (round(xmin / dt) : round(xmax / dt))' * dt;
            if mode == 1, tn = 't_from_stimulus_s'; else, tn = 't_from_peak_s'; end
            Tm = table(tt, 'VariableNames', {tn});
            for g = 1:nG
                xg = cur{g}{1};
                if isempty(xg)
                    m = nan(size(tt)); sd = m; nk = m; se = m; mn = m; mx = m;
                else
                    Yall = cur{g}{5};
                    [mn0, mx0] = overlayBand('range', cur{g}{2}, cur{g}{3}, cur{g}{4}, Yall);
                    if isempty(mn0), mn0 = nan(size(xg)); mx0 = mn0; end
                    m = interp1(xg, cur{g}{2}, tt); sd = interp1(xg, cur{g}{3}, tt); nk = interp1(xg, cur{g}{4}, tt, 'nearest');
                    se = sd ./ sqrt(max(nk, 1)); mn = interp1(xg, mn0, tt); mx = interp1(xg, mx0, tt);
                    Tg = array2table([xg(:) Yall'], 'VariableNames', [{tn}, arrayfun(@(k) sprintf('c%d', k), 1:size(Yall, 1), 'UniformOutput', false)]);
                    names{end+1} = sprintf('g%d_traces', g); tabs{end+1} = Tg; %#ok<AGROW>
                end
                Tm.(sprintf('g%d_mean', g)) = m(:); Tm.(sprintf('g%d_SD', g)) = sd(:); Tm.(sprintf('g%d_n', g)) = nk(:);
                Tm.(sprintf('g%d_SEM', g)) = se(:); Tm.(sprintf('g%d_min', g)) = mn(:); Tm.(sprintf('g%d_max', g)) = mx(:);
                nTr(g) = size(cur{g}{5}, 1);
            end
        end
        tabs{1} = Tm;
        als = {'aligned at the stimulus (t = 0)', 'aligned at the peak (t = 0)', 'time course of the range, t = 0 at the first stimulus'};
        if hOv.base.Value, b = 'diastolic force subtracted'; else, b = 'zero force subtracted (if known)'; end
        if hOv.norm.Value, u = 'normalized to the amplitude'; else, u = 'uN'; end
        rg = vertcat(ovG.span);
        Tgrp = table((1:nG)', {ovG.label}', arrayfun(@legendName, (1:nG)', 'UniformOutput', false), [ovG.ch]', rg(:,1), rg(:,2), ...
            [ovG.t0]', nTr, repmat(als(mode), nG, 1), repmat({b}, nG, 1), repmat({u}, nG, 1), {ovG.band}', ...
            'VariableNames', {'group', 'label', 'legend', 'channel', 'from_s', 'to_s', 'firstStimulus_s', 'nTraces', 'alignment', ...
            'baseline', 'unit', 'band'});
        names{end+1} = 'groups'; tabs{end+1} = Tgrp;
        writeTables(file, names, tabs);
    end

    function a = copyOverlayAxes(f2)
        % the overlay plot (with legend) in figure f2
        lg = hOv.axO.Legend;
        if ~isempty(lg) && isvalid(lg)
            c = copyobj([lg hOv.axO], f2); a = c(2);
        else
            a = copyobj(hOv.axO, f2);
        end
        a.Units = 'normalized'; a.Position = [0.1 0.11 0.86 0.82];
    end

    function editOverlayFigure()
        % copy of the overlay plot as a normal MATLAB figure: titles, axes, lines and legend editable with the plot tools
        if isempty(hOv) || ~isvalid(hOv.fig) || isempty(ovG), return; end
        f2 = figure('Name', 'MyoDishAnalysis: overlay (editable copy)', 'NumberTitle', 'off', 'Color', 'w', 'Units', 'pixels', ...
            'Position', [180 120 900 620], 'MenuBar', 'figure', 'ToolBar', 'figure');
        lightTheme(f2);
        copyOverlayAxes(f2);
        try plotedit(f2, 'on'); catch, end
        status('Editable copy of the overlay: double-click a text, line, axis or the legend to edit it; File > Save As saves it.');
    end

    % ---------------------------------------------------------------- trend: rolling average over long periods / several files
    function onTrend(~, ~)
        if isempty(H), status('Open a file first.'); return; end
        if ~isempty(hTr) && isvalid(hTr.fig), figure(hTr.fig); return; end
        if isempty(trCache), trCache = containers.Map('KeyType', 'char', 'ValueType', 'any'); end
        trData = [];
        trFiles = trFileInfo({H.file});
        f2 = figure('Name', 'MyoDishAnalysis: trend', 'NumberTitle', 'off', 'Color', 'w', 'Units', 'pixels', ...
            'Position', [110 90 1300 660], 'DeleteFcn', @(~,~) clearTrend());
        lightTheme(f2);
        d = {'Units', 'normalized', 'FontSize', 10, 'BackgroundColor', 'w'};
        axT = axes(f2, 'Position', [0.06 0.33 0.6 0.58]); box(axT, 'on');
        % comments (2026-10-13): numbered markers in a strip above the plot (independent of the y zoom) and a list
        % below it; click a marker or a line of the list (or point at a marker) to highlight the comment
        axC = axes(f2, 'Position', [0.06 0.915 0.6 0.03], 'XTick', [], 'YTick', [], 'YLim', [0 1], 'Box', 'on', ...
            'Color', [0.97 0.96 0.99], 'XColor', [0.7 0.7 0.7], 'YColor', [0.7 0.7 0.7], 'ButtonDownFcn', @(~,~) trCommentClick());
        axC.Toolbar = []; disableDefaultInteractivity(axC);
        uicontrol(f2, d{:}, 'Style', 'text', 'String', ['Comments of the log files (number = marker above the plot; ' ...
            'click a marker or a line to highlight it)'], 'HorizontalAlignment', 'left', 'Position', [0.06 0.218 0.6 0.025], 'FontSize', 8);
        lbC = uicontrol(f2, d{:}, 'Style', 'listbox', 'String', {}, 'Position', [0.06 0.015 0.6 0.2], 'FontSize', 9, ...
            'FontName', 'FixedWidth', 'Callback', @(~,~) trCommentSelect());
        x0 = 0.69; w = 0.3;
        uicontrol(f2, d{:}, 'Style', 'text', 'String', 'Files in a row (time 0 = start of the first file; order: start time in the log):', ...
            'HorizontalAlignment', 'left', 'Position', [x0 0.92 w 0.05], 'FontSize', 9);
        lbF = uicontrol(f2, d{:}, 'Style', 'listbox', 'String', {}, 'Position', [x0 0.71 w 0.21], 'FontSize', 9);
        uicontrol(f2, d{:}, 'Style', 'pushbutton', 'String', 'Add files ...', 'Position', [x0 0.655 0.085 0.045], 'Callback', @(~,~) trAddFiles());
        uicontrol(f2, d{:}, 'Style', 'pushbutton', 'String', 'Add series (_0, _1, ...)', 'Position', [x0+0.09 0.655 0.135 0.045], ...
            'Callback', @(~,~) trAddSeries(), 'TooltipString', 'all files <name>_<number>.mdd in the folder of the open file');
        uicontrol(f2, d{:}, 'Style', 'pushbutton', 'String', 'Remove', 'Position', [x0+0.23 0.655 0.07 0.045], 'Callback', @(~,~) trRemove());
        uicontrol(f2, d{:}, 'Style', 'text', 'String', 'Channel', 'HorizontalAlignment', 'left', 'Position', [x0 0.6 0.07 0.035]);
        if isempty(trChans) || ~all(ismember(trChans, H.dataChannels)), trChans = ch; end
        trMulti = trMulti(ismember(trMulti, H.dataChannels));
        [itC, vC] = trChannelItems();
        pC = uicontrol(f2, d{:}, 'Style', 'popupmenu', 'String', itC, 'Value', vC, 'Position', [x0+0.07 0.605 0.08 0.035], ...
            'Callback', @(~,~) trChannel(), 'TooltipString', ['channel of the trend; ''several channels ...'' = several channels ' ...
            'overlaid (one colour per channel)']);
        pR = uicontrol(f2, d{:}, 'Style', 'popupmenu', 'String', {'whole files', 'selected range (open file only)'}, 'Position', [x0+0.16 0.605 0.14 0.035]);
        uicontrol(f2, d{:}, 'Style', 'text', 'String', 'Sampling', 'HorizontalAlignment', 'left', 'Position', [x0 0.55 0.07 0.035]);
        pM = uicontrol(f2, d{:}, 'Style', 'popupmenu', 'String', {'all contractions', 'short windows (W s every T min)', ...
            'rocker stops only (log file)'}, 'Value', 2, 'Position', [x0+0.07 0.555 0.23 0.035], 'Callback', @(~,~) trSamplingControls(), ...
            'TooltipString', ['short windows: only W s every T min are read and analysed (much faster for 24-h files, the reading ' ...
            'dominates); rocker stops: only the rocker stops of the log files (contractions with the rocker at rest)']);
        tW1 = uicontrol(f2, d{:}, 'Style', 'text', 'String', 'window W (s)', 'HorizontalAlignment', 'left', 'Position', [x0 0.5 0.09 0.035]);
        eWs = uicontrol(f2, d{:}, 'Style', 'edit', 'String', '30', 'Position', [x0+0.09 0.505 0.05 0.035], ...
            'TooltipString', 'length of each analysed window (s)');
        tW2 = uicontrol(f2, d{:}, 'Style', 'text', 'String', 'every T (min)', 'HorizontalAlignment', 'left', 'Position', [x0+0.16 0.5 0.09 0.035]);
        eTm = uicontrol(f2, d{:}, 'Style', 'edit', 'String', '10', 'Position', [x0+0.25 0.505 0.05 0.035], ...
            'TooltipString', ['interval between the windows (min). Every window costs a separate read: from a network drive via VPN ' ...
            '(~0.25 s per window) windows pay off from ~10 min on; in the lab network already at a few minutes']);
        uicontrol(f2, d{:}, 'Style', 'text', 'String', 'Parameter', 'HorizontalAlignment', 'left', 'Position', [x0 0.45 0.07 0.035]);
        pP = uicontrol(f2, d{:}, 'Style', 'popupmenu', 'String', hPar.String, 'Value', hPar.Value, 'Position', [x0+0.07 0.455 0.23 0.035], ...
            'Callback', @(~,~) drawTrend());
        uicontrol(f2, d{:}, 'Style', 'text', 'String', 'Rolling window (min)', 'HorizontalAlignment', 'left', 'Position', [x0 0.4 0.13 0.035]);
        eW = uicontrol(f2, d{:}, 'Style', 'edit', 'String', '60', 'Position', [x0+0.13 0.405 0.06 0.035], 'Callback', @(~,~) drawTrend());
        pS = uicontrol(f2, d{:}, 'Style', 'popupmenu', 'String', {'mean', 'median'}, 'Position', [x0+0.2 0.405 0.1 0.035], 'Callback', @(~,~) drawTrend());
        cS = uicontrol(f2, d{:}, 'Style', 'checkbox', 'String', 'single contractions', 'Value', 1, 'Position', [x0 0.36 w 0.032], 'Callback', @(~,~) drawTrend());
        cI = uicontrol(f2, d{:}, 'Style', 'checkbox', 'String', 'only included contractions (filters of the main window)', 'Value', 1, ...
            'Position', [x0 0.328 w 0.032], 'Callback', @(~,~) drawTrend());
        cK = uicontrol(f2, d{:}, 'Style', 'checkbox', 'String', 'comments of the log files', 'Value', 1, 'Position', [x0 0.296 w 0.032], 'Callback', @(~,~) drawTrend());
        cT = uicontrol(f2, d{:}, 'Style', 'checkbox', 'String', 'clock time (date) instead of time since start', 'Value', 0, ...
            'Position', [x0 0.264 w 0.032], 'Callback', @(~,~) trTicks());
        cA = uicontrol(f2, d{:}, 'Style', 'checkbox', 'String', 'all channels in one pass (switch channel without recalculation)', 'Value', 0, ...
            'Position', [x0 0.232 w 0.032], 'TooltipString', ['the file is read once for all channels (reading dominates the time); ' ...
            'about 1.5 x the time of one channel, afterwards every channel is shown at once']);
        uicontrol(f2, d{:}, mainBtn{:}, 'Style', 'pushbutton', 'String', 'Calculate', 'Position', [x0 0.175 w 0.05], ...
            'Callback', @(~,~) calcTrend(), 'TooltipString', ['detects the contractions in the files (threshold, filters, zero force and rocker ' ...
            'filter as in the main window); results are kept, so changing parameter / window only redraws']);
        uicontrol(f2, d{:}, 'Style', 'pushbutton', 'String', 'Save figure ...', 'Position', [x0 0.125 0.145 0.042], 'Callback', @(~,~) saveTrendFigure());
        uicontrol(f2, d{:}, 'Style', 'pushbutton', 'String', 'Export data ...', 'Position', [x0+0.155 0.125 0.145 0.042], 'Callback', @(~,~) exportTrend());
        tx = uicontrol(f2, d{:}, 'Style', 'text', 'String', '', 'HorizontalAlignment', 'left', 'Position', [x0 0.005 w 0.115], 'FontSize', 8);
        hTr = struct('fig', f2, 'ax', axT, 'lbF', lbF, 'pC', pC, 'pR', pR, 'pP', pP, 'eW', eW, 'pS', pS, 'cS', cS, 'cI', cI, ...
            'cK', cK, 'cT', cT, 'tx', tx, 'pM', pM, 'eWs', eWs, 'eTm', eTm, 'tW', [tW1 tW2], 'cA', cA, 'axC', axC, 'lbC', lbC, ...
            'cmtT', zeros(0, 1), 'cmtLab', {{}}, 'cmtLine', gobjects(0), 'cmtMk', gobjects(0), 'cmtNum', gobjects(0), 'cmtSel', 0);
        try                                                %the strip is not zoomed / panned (x follows the plot)
            setAllowAxesZoom(zoom(f2), axC, false); setAllowAxesPan(pan(f2), axC, false);
        catch
        end
        set(f2, 'WindowButtonMotionFcn', @(~,~) trCommentHover());
        trSamplingControls();
        addlistener(axT, 'XLim', 'PostSet', @(~,~) trTicks());
        trListFiles(); drawTrend();
    end

    function clearTrend()
        hTr = []; trData = [];
    end

    function [items, val] = trChannelItems()
        % channel list of the trend window: single channels, the last set of several channels (overlay), 'several ...'
        items = arrayfun(@(c) sprintf('Ch %d', c), reshape(H.dataChannels, 1, []), 'UniformOutput', false);
        if numel(trMulti) > 1
            items{end+1} = ['Ch ' strjoin(arrayfun(@num2str, trMulti, 'UniformOutput', false), '+')];
        end
        if numel(trChans) > 1, val = numel(items); else, val = max(1, find(H.dataChannels == trChans, 1)); end
        items{end+1} = 'several channels ...';
    end

    function trChannel()
        % channel list changed: one channel, the set of several channels, or 'several channels ...' (checkboxes)
        nC = numel(H.dataChannels); v = hTr.pC.Value;
        if v == numel(hTr.pC.String)
            sel = trChooseChannels();
            if numel(sel) > 1, trMulti = sel; trChans = sel; elseif isscalar(sel), trChans = sel; end
        elseif v <= nC
            trChans = H.dataChannels(v);
        else
            trChans = trMulti;
        end
        [itC, vC] = trChannelItems();
        hTr.pC.String = itC; hTr.pC.Value = vC;
        calcTrend(true);
    end

    function sel = trChooseChannels()
        % checkboxes: channels of the trend (several = overlaid); [] = cancelled
        sel = [];
        chs = reshape(H.dataChannels, 1, []);
        nC = numel(chs);
        dlg = dialog('Name', 'Trend: channels', 'Units', 'pixels', 'Position', [300 300 300 100 + 24 * nC]);
        uicontrol(dlg, 'Style', 'text', 'Units', 'pixels', 'Position', [10 58 + 24 * nC 280 34], 'HorizontalAlignment', 'left', ...
            'String', 'Channels of the trend (several: overlaid, one colour per channel):');
        cb = gobjects(1, nC);
        for k = 1:nC
            cb(k) = uicontrol(dlg, 'Style', 'checkbox', 'Units', 'pixels', 'Position', [20 50 + 24 * (nC - k) 260 22], ...
                'String', sprintf('Channel %d', chs(k)), 'Value', ismember(chs(k), trChans));
        end
        uicontrol(dlg, 'Style', 'pushbutton', 'Units', 'pixels', 'Position', [110 12 80 28], 'String', 'OK', 'Callback', @(s,~) closeDialog(s, true));
        uicontrol(dlg, 'Style', 'pushbutton', 'Units', 'pixels', 'Position', [200 12 80 28], 'String', 'Cancel', 'Callback', @(s,~) closeDialog(s, false));
        uiwait(dlg);
        if ~isvalid(dlg), return; end                       %closed with the window button
        if isequal(dlg.UserData, true), sel = chs([cb.Value] == 1); end
        delete(dlg);
    end

    function R = apiTrend(chans)
        % scripts / tests: trend window with these channels (several = overlaid), calculated; R.data, R.roll, R.title
        if isempty(hTr) || ~isvalid(hTr.fig), onTrend(); end
        trChans = reshape(chans, 1, []);
        if numel(trChans) > 1, trMulti = trChans; end
        [itC, vC] = trChannelItems();
        hTr.pC.String = itC; hTr.pC.Value = vC;
        calcTrend(false);
        R = struct('data', trData, 'roll', hTr.roll, 'title', hTr.axC.Title.String, 'legend', {{}}, 'fig', hTr.fig, ...
            'comments', {hTr.lbC.String});
        lg = hTr.ax.Legend;
        if ~isempty(lg) && isvalid(lg), R.legend = lg.String; end
    end

    function trSamplingControls()
        if isempty(hTr) || ~isvalid(hTr.fig), return; end
        if hTr.pM.Value == 2, en = 'on'; else, en = 'off'; end
        set([hTr.eWs hTr.eTm], 'Enable', en);
    end

    function W = trWindows(Fk, a, b, sMode, Ws, Tm)
        % analysis windows [from to] (s in the file) of the range a ... b: whole range, short windows (Ws s every Tm
        % min, starting at a) or the rocker stops of the log file ('rockerSpeed' 0 ... next speed > 0, >= 3 s)
        switch sMode
            case 2
                s0 = (a:Tm*60:b)';
                W = [s0, min(s0 + Ws, b)];
            case 3
                L = Fk.rockerLog;
                W = zeros(0, 2);
                if ~isempty(L)
                    L(isinf(L(:,1)), 1) = 0;                 %entries before the recording start
                    for q = find(L(:,2) == 0)'
                        nx = find(L(:,1) > L(q,1) & L(:,2) > 0, 1);
                        if isempty(nx), e = Fk.dur; else, e = L(nx,1); end
                        W(end+1, :) = [L(q,1), e]; %#ok<AGROW>
                    end
                end
                W = [max(W(:,1), a), min(W(:,2), b)];
                W = W(W(:,2) - W(:,1) >= 3, :);
            otherwise
                W = [a b];
        end
        if sMode ~= 3, W = W(W(:,2) - W(:,1) >= 1, :); end
    end

    function F = trFileInfo(files)
        % files sorted by the recording start in their log files; offset = start relative to the first file (s)
        F = struct('file', {}, 'name', {}, 'start', {}, 'dur', {}, 'offset', {}, 'gap', {}, 'startKnown', {}, 'channels', {}, 'comments', {}, ...
            'rockerLog', {});
        for k = 1:numel(files)
            try
                Hk = mda_readMdd(files{k}, [], [], opts);
            catch ME
                status(['Trend: ' ME.message]); continue;
            end
            [~, n, e] = fileparts(Hk.file);
            cmt = table(zeros(0,1), cell(0,1), 'VariableNames', {'t_file', 'text'});
            try
                E = mda_logEntries(Hk.logFile);
                cmt = table(E.t_file(E.isComment), E.text(E.isComment), 'VariableNames', {'t_file', 'text'});
            catch
            end
            F(end+1) = struct('file', Hk.file, 'name', [n e], 'start', Hk.recordingStart, 'dur', Hk.totalSeconds, 'offset', 0, ...
                'gap', 0, 'startKnown', ~isnan(Hk.recordingStart), 'channels', Hk.dataChannels, 'comments', cmt, ...
                'rockerLog', Hk.rockerSpeedLog); %#ok<AGROW>
        end
        if isempty(F), return; end
        st = [F.start]; st(isnan(st)) = inf;
        [~, o] = sortrows([st(:), (1:numel(F))']);
        F = F(o);
        for k = 1:numel(F)
            if k == 1
                F(k).offset = 0; F(k).gap = 0;
            elseif F(k).startKnown && F(1).startKnown
                F(k).offset = (F(k).start - F(1).start) * 86400;
                F(k).gap = F(k).offset - (F(k-1).offset + F(k-1).dur);
            else
                F(k).offset = F(k-1).offset + F(k-1).dur;        %start unknown: directly after the previous file
                F(k).gap = nan;
            end
        end
    end

    function trListFiles()
        if isempty(hTr) || ~isvalid(hTr.fig), return; end
        L = cell(1, numel(trFiles));
        for k = 1:numel(trFiles)
            Fk = trFiles(k);
            if Fk.startKnown, st = datestr(Fk.start, 'dd.mm.yy HH:MM'); else, st = 'start unknown'; end
            if k == 1, g = 'time 0';
            elseif isnan(Fk.gap), g = 'appended (no start time)';
            elseif Fk.gap < -1, g = sprintf('OVERLAP %s', fmtClock(-Fk.gap, true, true));
            elseif Fk.gap > 60, g = sprintf('gap %s', fmtClock(Fk.gap, true, true));
            else, g = 'no gap';
            end
            L{k} = sprintf('%s | %s | %s | %s', Fk.name, st, fmtClock(Fk.dur, true, true), g);
        end
        if isempty(L), L = {'(no file)'}; end
        hTr.lbF.String = L;
        hTr.lbF.Value = max(1, min(hTr.lbF.Value, numel(L)));
    end

    function trAddFiles()
        p = fileparts(H.file);
        [fn, pn] = uigetfile('*.mdd', 'Add .mdd files', [p filesep], 'MultiSelect', 'on');
        if isequal(fn, 0), return; end
        fn = cellstr(fn);
        trSetFiles([{trFiles.file}, fullfile(pn, fn)]);
    end

    function trAddSeries()
        [p, n] = fileparts(H.file);
        tok = regexp(n, '^(.*)_(\d+)$', 'tokens', 'once');
        if isempty(tok), status('The file name does not end with _<number> (e.g. Setup3_sample01_1.mdd).'); return; end
        dd = dir(fullfile(p, [tok{1} '_*.mdd']));
        nm = {dd.name};
        nm = nm(~cellfun(@isempty, regexp(nm, ['^' regexptranslate('escape', tok{1}) '_\d+\.mdd$'], 'once')));
        trSetFiles([{trFiles.file}, fullfile(p, nm)]);
        status(sprintf('Trend: %d files of the series %s_*.', numel(nm), tok{1}));
    end

    function trRemove()
        if isempty(trFiles), return; end
        k = hTr.lbF.Value;
        f = {trFiles.file}; f(k) = [];
        trSetFiles(f);
    end

    function trSetFiles(f)
        [~, iu] = unique(f, 'stable');
        f = f(sort(iu));
        wb = waitbar(0.5, 'Reading the log files ...');
        trFiles = trFileInfo(f);
        if ishandle(wb), close(wb); end
        trData = [];
        trListFiles(); drawTrend();
    end

    function key = trKey(file, chT, from, to, o)
        key = sprintf('%s|%d|%.3f|%.3f|%s', file, chT, from, to, jsonencode(o));
    end

    function oT = trOpts(Fk, chans, sMode)
        % options of the main window; zero force: open file = value of the main window, other files = log file
        oT = opts;
        if strcmp(Fk.file, H.file), oT.zeroForce = zeroUser(chans); else, oT.zeroForce = nan; end
        oT.threshold = thrOf(chans);                   %threshold per channel: also for the other files of the series
        if sMode == 3, oT.rocker = 'stopped'; end      %rocker stops: only contractions with the rocker at rest
    end

    function key = trChKey(Fk, chX, from, to, sMode)
        % cache key of one channel (file, channel, range, options, sampling)
        key = [trKey(Fk.file, chX, from, to, trOpts(Fk, chX, sMode)) '|' trSampling];
    end

    function calcTrend(onlyCached)
        % onlyCached (channel changed): show the trend only if all files of this channel are in the cache
        if nargin < 1, onlyCached = false; end
        if isempty(trFiles), return; end
        chTs = reshape(trChans, 1, []);                     %several channels: overlaid
        onlyRange = hTr.pR.Value == 2;
        jobs = {};                                          %{file index, from, to}
        for k = 1:numel(trFiles)
            if onlyRange
                spF = w2f(rngSpan());                       %(time in the file; several ranges: first start to last end)
                if strcmp(trFiles(k).file, H.file) && all(isfinite(spF)), jobs(end+1,:) = {k, spF(1), spF(2)}; end %#ok<AGROW>
            else
                jobs(end+1,:) = {k, 0, trFiles(k).dur}; %#ok<AGROW>
            end
        end
        if isempty(jobs), status('Trend: no data (selected range: load a window of the open file first).'); return; end
        % sampling: all contractions, short windows (Ws s every Tm min) or rocker stops (log file)
        sMode = hTr.pM.Value;
        Ws = str2double(hTr.eWs.String); Tm = str2double(hTr.eTm.String);
        if sMode == 2
            if isnan(Ws) || Ws < 5, Ws = 30; hTr.eWs.String = '30'; end
            if isnan(Tm) || Tm <= 0, Tm = 10; hTr.eTm.String = '10'; end
            if Ws >= Tm * 60, sMode = 1; end                %windows cover everything
        end
        switch sMode
            case 2, trSampling = sprintf('%g s every %g min', Ws, Tm);
            case 3, trSampling = 'rocker stops only';
            otherwise, trSampling = 'all contractions';
        end
        total = sum(cellfun(@(a, b) b - a, jobs(:,2), jobs(:,3)));
        if onlyCached
            for j = 1:size(jobs, 1)
                Fk = trFiles(jobs{j,1});
                for chT = chTs(ismember(chTs, Fk.channels))
                    if ~isKey(trCache, trChKey(Fk, chT, jobs{j,2}, jobs{j,3}, sMode))
                        trData = []; drawTrend(); status(sprintf('Trend: channel %d not calculated yet - press Calculate.', chT)); return;
                    end
                end
            end
        end
        wb = waitbar(0, 'Detecting contractions ...', 'Name', 'Trend', 'CreateCancelBtn', 'setappdata(gcbf, ''cancel'', true)');
        setappdata(wb, 'cancel', false);
        done = 0; parts = {};
        block = 7200;                                       %s per call (MyoDishAnalysis chunks internally)
        try
            for j = 1:size(jobs, 1)
                k = jobs{j,1}; Fk = trFiles(k);
                need = chTs(ismember(chTs, Fk.channels));
                if isempty(need)
                    status(sprintf('Trend: channel %s not in %s.', strjoin(arrayfun(@num2str, chTs, 'UniformOutput', false), ', '), Fk.name));
                    done = done + jobs{j,3} - jobs{j,2}; continue;
                end
                chans = need;                               %several channels: the file is read once for all of them
                if hTr.cA.Value && ~onlyCached, chans = Fk.channels(:)'; end   %all channels: the file is read once
                missing = false;
                for ch2 = chans, missing = missing || ~isKey(trCache, trChKey(Fk, ch2, jobs{j,2}, jobs{j,3}, sMode)); end
                if ~missing
                    done = done + jobs{j,3} - jobs{j,2};
                else
                    oT = trOpts(Fk, chans, sMode);
                    Tk = [];
                    Wj = trWindows(Fk, jobs{j,2}, jobs{j,3}, sMode, Ws, Tm);
                    if isempty(Wj), status(sprintf('Trend: no %s in %s.', trSampling, Fk.name)); end
                    for a = jobs{j,2}:block:jobs{j,3}
                        b = min(a + block, jobs{j,3});
                        if getappdata(wb, 'cancel'), error('mda:cancel', 'cancelled'); end
                        waitbar(done / total, wb, sprintf('%s: %s - %s', strrep(Fk.name, '_', '\_'), fmtClock(a, true, true), fmtClock(b, true, true)));
                        % windows starting in this block (one call per block: the header / log file is read once)
                        if sMode == 1
                            Wb = [a b];
                            if b - a < 1, Wb = zeros(0, 2); end
                        else
                            Wb = Wj(Wj(:,1) >= a & (Wj(:,1) < b | (b == jobs{j,3} & Wj(:,1) <= b)), :);
                        end
                        if ~isempty(Wb)
                            c = MyoDishAnalysis(Fk.file, chans, Wb(:,1), Wb(:,2), oT, 'quiet', true);
                            if ~isempty(c), Tk = [Tk; c]; end %#ok<AGROW>
                        end
                        done = done + (b - a);
                    end
                    for ch2 = chans                         %one cache entry per channel
                        if isempty(Tk), T2 = Tk; else, T2 = Tk(Tk.channel == ch2, :); end
                        if ~isempty(T2)
                            [~, iu] = unique(round(T2.t_peak * 1e4)); T2 = T2(iu, :);   %peaks exactly at a block border
                        end
                        trCache(trChKey(Fk, ch2, jobs{j,2}, jobs{j,3}, sMode)) = T2;
                    end
                end
                for chT = need
                    Tk = trCache(trChKey(Fk, chT, jobs{j,2}, jobs{j,3}, sMode));
                    if isempty(Tk), continue; end
                    keep = intersect({'t_peak', 'channel', 'beatType', 'included', 'rockerMoving'}, Tk.Properties.VariableNames, 'stable');
                    pn = intersect(plotList(:,1)', Tk.Properties.VariableNames, 'stable');
                    Tk = Tk(:, [keep, pn]);
                    Tk.t_since_start = Tk.t_peak + Fk.offset;
                    Tk.fileIndex = repmat(k, height(Tk), 1);
                    parts{end+1} = Tk; %#ok<AGROW>
                end
            end
        catch ME
            if ishandle(wb), delete(wb); end
            if strcmp(ME.identifier, 'mda:cancel'), status('Trend: cancelled.'); else, status(['Trend: ' ME.message]); end
            return;
        end
        if ishandle(wb), delete(wb); end
        if isempty(parts), trData = []; else, trData = sortrows(vertcat(parts{:}), 't_since_start'); end
        drawTrend();
        if isempty(trData), status('Trend: no contractions.'); return; end
        status(sprintf('Trend: %d contractions in %d file(s).', height(trData), numel(unique(trData.fileIndex))));
    end

    function [tt, rr] = trRolling(t, v, wMin, useMedian)
        % rolling mean / median (time window wMin minutes, centred) per file; NaN between the files
        tt = []; rr = [];
        if isempty(t), return; end
        [t, o] = sort(t); v = v(o);
        if useMedian
            r = movmedian(v, wMin * 60, 'omitnan', 'SamplePoints', t);
        else
            r = movmean(v, wMin * 60, 'omitnan', 'SamplePoints', t);
        end
        tt = t(:); rr = r(:);
    end

    function drawTrend()
        if isempty(hTr) || ~isvalid(hTr.fig), return; end
        axT = hTr.ax; cla(axT); hold(axT, 'on'); legend(axT, 'off');
        cla(hTr.axC); hold(hTr.axC, 'on'); hTr.lbC.String = {}; hTr.lbC.Value = 1; hTr.cmtSel = 0;
        hTr.cmtT = zeros(0, 1); hTr.cmtLab = {}; hTr.cmtLine = gobjects(0); hTr.cmtMk = gobjects(0); hTr.cmtNum = gobjects(0);
        if isempty(trFiles), title(hTr.axC, 'no file'); return; end
        k = hTr.pP.Value; pn = plotList{k,1}; unit = strrep(plotList{k,2}, 'u', mu);
        % files (light background) and gaps (grey)
        yl0 = [0 1];
        have = ~isempty(trData) && height(trData) > 0 && ismember(pn, trData.Properties.VariableNames);
        if have
            I = ~isnan(trData.(pn));
            if hTr.cI.Value, I = I & trData.included; end
            v = trData.(pn); t = trData.t_since_start;
            if any(I)
                q = sort(v(I)); lo = q(max(1, round(0.002 * numel(q)))); hi = q(max(1, round(0.998 * numel(q))));
                if hi <= lo, hi = lo + 1; end
                yl0 = [lo hi] + [-0.08 0.12] * (hi - lo);
            end
        end
        for f = 1:numel(trFiles)
            Fk = trFiles(f);
            patch(axT, Fk.offset + [0 Fk.dur Fk.dur 0], yl0([1 1 2 2]), [0.93 0.95 1] - 0.03 * mod(f, 2), 'EdgeColor', 'none', 'HitTest', 'off');
            [~, nm] = fileparts(Fk.name); suf = regexp(nm, '_\d+$', 'match', 'once');
            if isempty(suf), suf = nm(max(1, end-24):end); end
            text(axT, Fk.offset, yl0(2), [' ' suf], 'VerticalAlignment', 'top', 'FontSize', 8, 'Color', [0.3 0.3 0.6], 'Interpreter', 'none', 'Clipping', 'on');
            if f > 1 && Fk.gap > 60
                g0 = trFiles(f-1).offset + trFiles(f-1).dur;
                patch(axT, [g0 Fk.offset Fk.offset g0], yl0([1 1 2 2]), [0.82 0.82 0.82], 'EdgeColor', 'none', 'HitTest', 'off');
                text(axT, (g0 + Fk.offset) / 2, mean(yl0), sprintf('no data\n%s', fmtClock(Fk.gap, true, false)), 'HorizontalAlignment', 'center', ...
                    'FontSize', 8, 'Color', [0.35 0.35 0.35], 'Clipping', 'on');
            end
        end
        hp = gobjects(0); nmL = {};
        hTr.roll = zeros(0, 3);                              %channel, time since start, rolling mean / median
        multi = numel(trChans) > 1;                          %several channels: overlaid, one colour per channel
        wMin = str2double(hTr.eW.String); if isnan(wMin) || wMin <= 0, wMin = 10; hTr.eW.String = '10'; end
        rollName = sprintf('rolling %s (%g min)', hTr.pS.String{hTr.pS.Value}, wMin);
        if have && any(I)
            chs = trChans(ismember(trChans, trData.channel));
            pal = trendColors();
            for pass = 1:2                                   %single contractions first, rolling lines on top
                for q = 1:numel(chs)
                    Iq = I & trData.channel == chs(q);
                    if ~any(Iq), continue; end
                    if multi, col = pal(mod(q - 1, size(pal, 1)) + 1, :); colS = 1 - 0.45 * (1 - col);
                    else, col = [0.75 0 0]; colS = [0.95 0.6 0.6]; end
                    if pass == 1
                        if hTr.cS.Value
                            hs = plot(axT, t(Iq), v(Iq), '.', 'Color', colS, 'MarkerSize', 5);
                            if ~multi, hp(end+1) = hs; nmL{end+1} = 'single contractions'; end %#ok<AGROW>
                        end
                        continue;
                    end
                    T2 = []; R2 = [];
                    for f = unique(trData.fileIndex(Iq))'
                        J = Iq & trData.fileIndex == f;
                        [tt, rr] = trRolling(t(J), v(J), wMin, hTr.pS.Value == 2);
                        T2 = [T2; tt; nan]; R2 = [R2; rr; nan]; %#ok<AGROW>
                    end
                    hp(end+1) = plot(axT, T2, R2, '-', 'Color', col, 'LineWidth', 2); %#ok<AGROW>
                    if multi, nmL{end+1} = sprintf('Ch %d', chs(q)); else, nmL{end+1} = rollName; end %#ok<AGROW>
                    hTr.roll = [hTr.roll; repmat(chs(q), numel(T2), 1), T2, R2];
                end
            end
        end
        if hTr.cK.Value                                     %comments: numbered markers above the plot, list below (2026-10-13)
            tc = zeros(0, 1); lab = {};
            for f = 1:numel(trFiles)
                cm = trFiles(f).comments;
                if isempty(cm) || height(cm) == 0, continue; end
                in = cm.t_file >= 0 & cm.t_file <= trFiles(f).dur;
                tc = [tc; cm.t_file(in) + trFiles(f).offset]; lab = [lab; cellstr(cm.text(in))]; %#ok<AGROW>
            end
            [tc, o] = sort(tc); lab = lab(o);
            n = numel(tc);
            hTr.cmtT = tc; hTr.cmtLab = lab;
            hTr.cmtLine = gobjects(n, 1); hTr.cmtMk = gobjects(n, 1); hTr.cmtNum = gobjects(n, 1);
            yb = yl0 + [-100 100] * diff(yl0);               %vertical lines through any y zoom
            for k = 1:n
                hTr.cmtLine(k) = plot(axT, [tc(k) tc(k)], yb, ':', 'Color', [0.55 0 0.75], 'HitTest', 'off');
                hTr.cmtMk(k) = plot(hTr.axC, tc(k), 0.18, 'v', 'MarkerSize', 4, 'Color', [0.55 0 0.75], ...
                    'MarkerFaceColor', [0.55 0 0.75], 'HitTest', 'off');
                hTr.cmtNum(k) = text(hTr.axC, tc(k), 0.62, sprintf('%d', k), 'HorizontalAlignment', 'center', ...
                    'FontSize', 8, 'Color', [0.55 0 0.75], 'Clipping', 'on', 'HitTest', 'off');
            end
            hTr.lbC.String = arrayfun(@(k) sprintf('%3d  %s  %s', k, trCommentTime(tc(k)), lab{k}), (1:n)', ...
                'UniformOutput', false);
            if n == 0, hTr.lbC.String = {'(no comments)'}; end
        end
        hTr.axC.YLim = [0 1];
        last = trFiles(end);
        xlim(axT, [0, max(1, last.offset + last.dur)]); ylim(axT, yl0);
        ylabel(axT, sprintf('%s (%s)', pn, unit), 'Interpreter', 'none');
        if ~isempty(hp), legend(axT, hp, nmL, 'Location', 'northeast', 'FontSize', 8); end
        if have && multi
            title(hTr.axC, sprintf('Channels %s (%s), %d contractions (%d shown), %d file(s), sampling: %s', ...
                strjoin(arrayfun(@num2str, trChans, 'UniformOutput', false), ', '), rollName, height(trData), nnz(I), ...
                numel(trFiles), trSampling), 'FontWeight', 'normal', 'FontSize', 9);
        elseif have
            title(hTr.axC, sprintf('Channel %d, %d contractions (%d shown), %d file(s), sampling: %s', trChans(1), height(trData), ...
                nnz(I), numel(trFiles), trSampling), 'FontWeight', 'normal', 'FontSize', 9);
        else
            title(hTr.axC, 'press Calculate (detects the contractions in the listed files)', 'FontWeight', 'normal', 'FontSize', 9);
        end
        grid(axT, 'on');
        trTicks();
        info = {sprintf('%d file(s), total %s', numel(trFiles), fmtClock(last.offset + last.dur, true, true))};
        g = [trFiles(2:end).gap]; g = g(~isnan(g) & g > 60);
        if ~isempty(g), info{end+1} = sprintf('%d gap(s) between the files: %s', numel(g), strjoin(arrayfun(@(x) fmtClock(x, true, false), g, 'UniformOutput', false), ', ')); end
        if any(~[trFiles.startKnown]), info{end+1} = 'start time unknown for some files: appended directly'; end
        if have && hTr.pM.Value == 2
            Tm = str2double(hTr.eTm.String);
            if ~isnan(Tm) && str2double(hTr.eW.String) < 2 * Tm
                info{end+1} = sprintf('short windows every %g min: use a rolling window >= %g min', Tm, 2 * Tm);
            end
        end
        info{end+1} = 'zero force: open file = value of the main window, other files = Offset of their log';
        info{end+1} = 'manual exclusions of the main window are not applied';
        hTr.tx.String = info;
    end

    function trTicks()
        if isempty(hTr) || ~isvalid(hTr.fig) || isempty(trFiles), return; end
        axT = hTr.ax;
        xl = xlim(axT);
        [tk, tl, unit] = timeTicks(xl, max(3600, xl(2)));
        if hTr.cT.Value && trFiles(1).startKnown
            tl = arrayfun(@(x) datestr(trFiles(1).start + x / 86400, 'dd.mm. HH:MM'), tk, 'UniformOutput', false);
            xlabel(axT, 'clock time (dd.mm. HH:MM)');
        else
            xlabel(axT, sprintf('time since the start of the first file (%s)', unit));
        end
        set(axT, 'XTick', tk, 'XTickLabel', tl);
        hTr.axC.XLim = xl;                                  %comment strip follows the x axis of the plot
        h = hTr.cmtNum;
        if ~isempty(h) && all(isgraphics(h))                 %numbers of the markers: no overlapping numbers
            p = hTr.cmtT;
            u = axT.Units; axT.Units = 'pixels'; wPx = axT.Position(3); axT.Units = u;
            show = false(size(p)); last = -inf;
            for q = 1:numel(p)
                minDx = (6 * numel(sprintf('%d', q)) + 4) * diff(xl) / max(wPx, 1);
                if p(q) >= xl(1) && p(q) <= xl(2) && p(q) - last >= minDx, show(q) = true; last = p(q); end
            end
            if hTr.cmtSel > 0, show(hTr.cmtSel) = true; end
            set(h(show), 'Visible', 'on'); set(h(~show), 'Visible', 'off');
        end
        if ~isempty(hTr.cmtT)                                %list: times in the current time format (clock / since start)
            L = arrayfun(@(k) sprintf('%3d  %s  %s', k, trCommentTime(hTr.cmtT(k)), hTr.cmtLab{k}), ...
                (1:numel(hTr.cmtT))', 'UniformOutput', false);
            if ~isequal(L, hTr.lbC.String(:)), hTr.lbC.String = L; end
        end
    end

    function s = trCommentTime(t)
        % time of a comment as on the x axis: clock time or time since the start of the first file
        if hTr.cT.Value && trFiles(1).startKnown
            s = datestr(trFiles(1).start + t / 86400, 'dd.mm. HH:MM:SS');
        else
            s = fmtClock(t, true, true);
        end
    end

    function trCommentMark(k, center)
        % highlight comment k (0 = none): marker, number and line in the plot, line of the list
        if isempty(hTr) || ~isvalid(hTr.fig) || isempty(hTr.cmtT), return; end
        pu = [0.55 0 0.75];
        if hTr.cmtSel > 0 && hTr.cmtSel <= numel(hTr.cmtT) && isgraphics(hTr.cmtLine(hTr.cmtSel))
            j = hTr.cmtSel;
            set(hTr.cmtLine(j), 'Color', pu, 'LineWidth', 0.5, 'LineStyle', ':');
            set(hTr.cmtMk(j), 'Color', pu, 'MarkerFaceColor', pu, 'MarkerSize', 4);
            set(hTr.cmtNum(j), 'Color', pu, 'FontWeight', 'normal');
        end
        hTr.cmtSel = k;
        if k < 1 || k > numel(hTr.cmtT), trTicks(); return; end
        set(hTr.cmtLine(k), 'Color', [0.85 0 0], 'LineWidth', 1.5, 'LineStyle', '-');
        set(hTr.cmtMk(k), 'Color', [0.85 0 0], 'MarkerFaceColor', [0.85 0 0], 'MarkerSize', 7);
        set(hTr.cmtNum(k), 'Color', [0.85 0 0], 'FontWeight', 'bold', 'Visible', 'on');
        uistack(hTr.cmtNum(k), 'top');
        hTr.lbC.Value = k;
        xl = xlim(hTr.ax);
        if center && (hTr.cmtT(k) < xl(1) || hTr.cmtT(k) > xl(2))    %outside the view: move the view to it
            xlim(hTr.ax, hTr.cmtT(k) + [-0.5 0.5] * diff(xl));
        end
        trTicks();
    end

    function trCommentSelect()
        % line of the comment list selected: highlight the comment in the plot
        if isempty(hTr) || isempty(hTr.cmtT), return; end
        trCommentMark(hTr.lbC.Value, true);
    end

    function k = trCommentAt(maxPx)
        % comment marker nearest to the pointer in the comment strip (within maxPx pixels; 0 = none)
        k = 0;
        if isempty(hTr) || ~isvalid(hTr.fig) || isempty(hTr.cmtT), return; end
        a = hTr.axC; cp = a.CurrentPoint; x = cp(1, 1); y = cp(1, 2);
        xl = a.XLim;
        if x < xl(1) || x > xl(2) || y < 0 || y > 1, return; end
        u = a.Units; a.Units = 'pixels'; wPx = a.Position(3); a.Units = u;
        [d, j] = min(abs(hTr.cmtT - x));
        if d * wPx / diff(xl) <= maxPx, k = j; end
    end

    function trCommentClick()
        k = trCommentAt(8);
        if k > 0, trCommentMark(k, false); end
    end

    function trCommentHover()
        % pointer on a comment marker: highlight it and its line in the list
        k = trCommentAt(5);
        if k > 0 && k ~= hTr.cmtSel, trCommentMark(k, false); end
    end

    function saveTrendFigure()
        if isempty(hTr) || ~isvalid(hTr.fig), return; end
        file = askFile('image', 'trend');
        if isempty(file), return; end
        f2 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [50 50 1200 600]);
        lightTheme(f2);
        try
            lg = hTr.ax.Legend;
            if ~isempty(lg) && isvalid(lg), c = copyobj([lg hTr.ax], f2); a = c(2); else, a = copyobj(hTr.ax, f2); end
            xl = xlim(hTr.ax);
            k = find(hTr.cmtT >= xl(1) & hTr.cmtT <= xl(2));    %comments in the view: numbered markers and a list
            wA = 0.88; if ~isempty(k), wA = 0.6; end
            a.Units = 'normalized'; a.Position = [0.08 0.11 wA 0.76];
            b = copyobj(hTr.axC, f2); b.Units = 'normalized'; b.Position = [0.08 0.875 wA 0.035];
            set(b.Children, 'Visible', 'on');
            for j = 1:numel(b.Children)                  %numbers: as in the window (no overlapping numbers)
                if isa(b.Children(j), 'matlab.graphics.primitive.Text')
                    q = str2double(b.Children(j).String);
                    if ~isnan(q) && q <= numel(hTr.cmtNum), b.Children(j).Visible = hTr.cmtNum(q).Visible; end
                end
            end
            if ~isempty(k)
                L = arrayfun(@(q) sprintf('%d  %s  %s', q, trCommentTime(hTr.cmtT(q)), hTr.cmtLab{q}), k(:), 'UniformOutput', false);
                if numel(L) > 45, L = [L(1:44); {sprintf('... and %d more', numel(L) - 44)}]; end
                annotation(f2, 'textbox', [0.7 0.11 0.29 0.8], 'String', L, 'FontSize', 7, 'EdgeColor', 'none', ...
                    'Interpreter', 'none', 'VerticalAlignment', 'top', 'FitBoxToText', 'off');
            end
            saveFigureFile(f2, file);
            status(['Saved: ' file]);
        catch ME
            status(['Save: ' ME.message]);
        end
        delete(f2);
    end

    function exportTrend()
        if isempty(trData) || height(trData) == 0, status('Trend: press Calculate first.'); return; end
        file = askFile('data', 'trend');
        if isempty(file), return; end
        D = trData;
        D.file = reshape({trFiles(D.fileIndex).name}, [], 1);
        st = [trFiles(D.fileIndex).start]';
        D.clockTime = datetime(st + D.t_peak / 86400, 'ConvertFrom', 'datenum', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
        D = movevars(D, {'file', 'channel', 't_since_start', 'clockTime'}, 'Before', 1);
        vn = D.Properties.VariableNames;
        vn(strcmp(vn, 't_peak')) = {'t_file_s'}; vn(strcmp(vn, 't_since_start')) = {'t_since_start_s'};
        D.Properties.VariableNames = vn;
        D.fileIndex = [];
        k = hTr.pP.Value;
        R = array2table(hTr.roll(~isnan(hTr.roll(:,2)), :), 'VariableNames', {'channel', 't_since_start_s', ...
            matlab.lang.makeValidName(['rolling_' plotList{k,1}])});
        stTxt = cell(numel(trFiles), 1);
        for f = 1:numel(trFiles)
            if trFiles(f).startKnown, stTxt{f} = datestr(trFiles(f).start, 'yyyy-mm-dd HH:MM:SS'); else, stTxt{f} = 'unknown'; end
        end
        Fi = table({trFiles.name}', stTxt, [trFiles.dur]', [trFiles.offset]', [trFiles.gap]', repmat({trSampling}, numel(trFiles), 1), ...
            'VariableNames', {'file', 'recordingStart', 'duration_s', 'offset_s', 'gapBefore_s', 'sampling'});
        writeTables(file, {'contractions', 'rolling', 'files'}, {D, R, Fi});
    end

    % ---------------------------------------------------------------- save plots / export plotted data
    function file = askFile(kind, what)
        % file name dialog; kind 'image' (.png .jpg .tif .fig), 'screenshot' (.png .jpg .tif) or 'data' (.xlsx .csv .txt)
        file = '';
        if ~isempty(apiFile), file = apiFile; apiFile = ''; return; end
        [p, n] = fileparts(H.file);
        if isempty(lastDir), lastDir = p; end
        switch kind
            case 'image'
                flt = {'*.png', 'PNG image (*.png)'; '*.jpg', 'JPEG image (*.jpg)'; '*.tif', 'TIFF image (*.tif)'; '*.fig', 'MATLAB figure (*.fig)'};
            case 'screenshot'
                flt = {'*.png', 'PNG image (*.png)'; '*.jpg', 'JPEG image (*.jpg)'; '*.tif', 'TIFF image (*.tif)'};
            otherwise
                flt = {'*.xlsx', 'Excel (*.xlsx)'; '*.csv', 'comma separated (*.csv)'; '*.txt', 'tab separated text (*.txt)'};
        end
        if strcmp(what, 'overlay'), base = [n '_overlay']; else, base = sprintf('%s_ch%d_%s', n, ch, what); end
        [fn, pn, fi] = uiputfile(flt, ['Save ' what], fullfile(lastDir, [base flt{1,1}(2:end)]));
        if isequal(fn, 0), return; end
        [~, ~, e] = fileparts(fn);
        if isempty(e), fn = [fn flt{max(1, fi), 1}(2:end)]; end
        file = fullfile(pn, fn);
        lastDir = pn;
    end

    function saveFigureFile(f2, file)
        [~, ~, e] = fileparts(file);
        switch lower(e)
            case '.fig'
                set(f2, 'CreateFcn', 'set(gcbf, ''Visible'', ''on'')');   %saved invisible, opens visible
                savefig(f2, file);
            case {'.png', '.jpg', '.jpeg', '.tif', '.tiff'}
                if exist('exportgraphics', 'file')
                    exportgraphics(f2, file, 'Resolution', 300, 'BackgroundColor', 'white');
                else
                    fmt = struct('png', '-dpng', 'jpg', '-djpeg', 'jpeg', '-djpeg', 'tif', '-dtiff', 'tiff', '-dtiff');
                    print(f2, file, fmt.(lower(e(2:end))), '-r300');
                end
            otherwise
                error('unknown file type %s', e);
        end
    end

    function f2 = makePlainFigure(list)
        % copy of the plots in a new figure without controls (stimulus plot redrawn: yyaxis axes cannot be copied)
        relHeight = struct('overview', 1, 'force', 2.4, 'stimuli', 1, 'parameter', 1.5);
        w = cellfun(@(nm) relHeight.(nm), list);
        f2 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [50 50 1300 120 + 190 * sum(w)]);
        lightTheme(f2);
        gap = 0.055; bot = 0.07; top = 0.035;
        hAll = 1 - bot - top - gap * (numel(list) - 1);
        y = 1 - top;
        for k = 1:numel(list)
            hk = hAll * w(k) / sum(w);
            switch list{k}
                case 'overview'
                    a = copyobj(axOv, f2);
                case 'force'
                    lg = findobj(fig, 'Type', 'Legend', 'Tag', 'mdaForceLegend');
                    if ~isempty(lg) && isvalid(lg(1)) && strcmp(lg(1).Visible, 'on')
                        c2 = copyobj([lg(1), axMain], f2); a = c2(2);   %with the legend of the markers
                    else
                        a = copyobj(axMain, f2);
                    end
                case 'parameter'
                    a = copyobj(axPar, f2);
                case 'stimuli'
                    a = axes(f2); box(a, 'on');
                    drawStim(a);
                    xlim(a, xlim(axMain)); set(a, 'XTick', axPar.XTick);
                    stimText(a);
            end
            a.UIContextMenu = [];
            delete(findall(a, 'Tag', 'mdaHover'));         %mouse pointer markers
            a.Units = 'normalized'; a.Position = [0.07 y - hk 0.86 hk];
            if any(strcmp(list{k}, {'force', 'stimuli'})) && (numel(list) == 1 || k == numel(list))
                set(a, 'XTickLabel', axPar.XTickLabel); xlabel(a, axPar.XLabel.String);
            elseif any(strcmp(list{k}, {'force', 'stimuli'}))
                set(a, 'XTickLabel', {});
            end
            y = y - hk - gap;
        end
    end

    function savePlots(which)
        if isempty(H), status('Open a file first.'); return; end
        if strcmp(which, 'window')
            file = askFile('screenshot', 'window');
            if isempty(file), return; end
            fr = getframe(fig);
            if endsWith(lower(file), {'.jpg', '.jpeg'}), imwrite(fr.cdata, file, 'Quality', 95); else, imwrite(fr.cdata, file); end
            status(['Saved: ' file]); return;
        end
        if strcmp(which, 'all')
            list = {'overview', 'force', 'stimuli', 'parameter'};
        else
            list = {which};
        end
        if isempty(O), list(strcmp(list, 'overview')) = []; end
        if isempty(S) || isempty(C), list(~strcmp(list, 'overview')) = []; end
        if isempty(list), status('Nothing to save (press Overview or load a time window first).'); return; end
        file = askFile('image', which);
        if isempty(file), return; end
        f2 = [];
        try
            f2 = makePlainFigure(list);
            saveFigureFile(f2, file);
            status(['Saved: ' file]);
        catch ME
            status(['Save: ' ME.message]);
        end
        if ~isempty(f2) && isvalid(f2), delete(f2); end
    end

    function saveOverlayFigure()
        if isempty(hOv) || ~isvalid(hOv.fig), return; end
        file = askFile('image', 'overlay');
        if isempty(file), return; end
        f2 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [50 50 900 620]);
        lightTheme(f2);
        try
            copyOverlayAxes(f2);
            saveFigureFile(f2, file);
            status(['Saved: ' file]);
        catch ME
            status(['Save: ' ME.message]);
        end
        delete(f2);
    end

    function exportPlotData(which)
        % data of the visible part (time axis) of the force, stimulus or parameter plot; the overview: picture only
        if strcmp(which, 'overview'), status('The overview can only be saved as a picture.'); return; end
        if isempty(S) || isempty(C), status('Load a time window first.'); return; end
        xl = xlim(axMain);
        file = askFile('data', which);
        if isempty(file), return; end
        clk = @(t) datetime(H.recordingStart + t(:) / 86400, 'ConvertFrom', 'datenum', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
        names = {}; tabs = {};                         %(times in the file; rocker stops side by side: mapped, w2f)
        switch which
            case 'force'
                I = C.t >= xl(1) & C.t <= xl(2);
                if ~isempty(sbs) && isfield(S, 'gapMask') && numel(S.gapMask) == numel(I), I = I & ~S.gapMask; end
                t = C.t(I); t = t(:); f = C.f(I); f = f(:);
                z = mda_zeroForce(S, ch, zeroUser(ch), t);
                T = table(w2f(t), 'VariableNames', {'t_file_s'});
                if relTime, T.t_window_s = t - S.fromSeconds; end
                if ~any(isnan(z)), T.force_minus_zero_uN = f - z; else, T.force_signal_uN = f; end
                if ~isempty(C.rockerArtifact), a = C.rockerArtifact(I); T.rockerArtifactSubtracted_uN = a(:); end
                if height(T) > 1048000 && endsWith(lower(file), '.xlsx')
                    status(sprintf('%d rows: too many for Excel. Zoom in or export as .csv / .txt.', height(T))); return;
                end
                names{end+1} = 'signal'; tabs{end+1} = T;
                if ~isempty(B)
                    J = find(B.t_peak >= xl(1) & B.t_peak <= xl(2));
                    [~, loc] = ismember(B.t_peak(J), C.peakTimes);
                    y = C.f(C.iPeaks(loc)); y = y(:);
                    zz = mda_zeroForce(S, ch, zeroUser(ch), B.t_peak(J));
                    if ~any(isnan(zz)), y = y - zz(:); end
                    inR = inRng(B.t_peak); man = isManual(); sel = selected();
                    st = repmat({'outside the analysed range'}, numel(J), 1);
                    st(inR(J) & ~B.included(J)) = {'excluded by filter'};
                    st(inR(J) & man(J)) = {'excluded by user'};
                    st(sel(J)) = {'selected'};
                    Tc = table(w2f(B.t_peak(J)), y, B.beatType(J), st, 'VariableNames', {'t_peak_s', 'peak_force_uN', 'beatType', 'status'});
                    if ~isnan(H.recordingStart), Tc.clockTime = clk(Tc.t_peak_s); end
                    names{end+1} = 'contractions'; tabs{end+1} = Tc;
                end
                ts = C.stimTimes(C.stimTimes >= xl(1) & C.stimTimes <= xl(2));
                names{end+1} = 'stimuli'; tabs{end+1} = table(w2f(ts(:)), 'VariableNames', {'t_stim_s'});
                if ~isempty(LE) && height(LE) > 0
                    tw = f2w(LE.t_file);
                    cm = LE.isComment & tw >= xl(1) & tw <= xl(2);
                    if any(cm)
                        names{end+1} = 'comments';
                        tabs{end+1} = table(LE.t_file(cm), LE.clockTime(cm), LE.text(cm), 'VariableNames', {'t_file_s', 'clockTime', 'comment'});
                    end
                end
            case 'stimuli'
                [tS, cur, ok, ex, iv] = stimData();
                I = tS >= xl(1) & tS <= xl(2);
                if C.stimChannel == 0, cur(:) = nan; end    %external trigger pulses: no current
                T = table(w2f(tS(I)), cur(I), ok(I), ex(I), iv(I), 'VariableNames', ...
                    {'t_file_s', 'current_mA', 'currentReached', 'extraPulse', 'intervalToPreviousPulse_ms'});
                if relTime, T.t_window_s = T.t_file_s - S.fromSeconds; end
                if ~isnan(H.recordingStart), T.clockTime = clk(T.t_file_s); end
                if C.stimChannel == 0, nm = 'stimuli_extTrigger'; else, nm = sprintf('stimuli_ch%d', C.stimChannel); end
                names{end+1} = nm; tabs{end+1} = T;
            case 'parameter'
                if isempty(B), status('No contractions.'); return; end
                k = hPar.Value;
                if ~ismember(plotList{k,1}, B.Properties.VariableNames), status('No reference beat for this parameter.'); return; end
                v = B.(plotList{k,1}); sel = selected();
                J = B.t_peak >= xl(1) & B.t_peak <= xl(2);
                vn = matlab.lang.makeValidName([plotList{k,1} '_' strrep(strrep(plotList{k,2}, '/', '_per_'), '*', 'x')]);
                T = table(w2f(B.t_peak(J)), v(J), sel(J), 'VariableNames', {'t_peak_s', vn, 'selected'});
                if relTime, T.t_window_s = T.t_peak_s - S.fromSeconds; end
                if ~isnan(H.recordingStart), T.clockTime = clk(T.t_peak_s); end
                names{end+1} = plotList{k,1}; tabs{end+1} = T;
        end
        writeTables(file, names, tabs);
    end

    function writeTables(file, names, tabs)
        % .xlsx: one sheet per table; .csv / .txt: one file per table (<name>_<table>.csv if several). Always with
        % the table 'info' (version, file, all settings: mda_writeResults(info); 2026-10-09)
        [p, n, e] = fileparts(file);
        nData = numel(tabs);
        names{end+1} = 'info'; tabs{end+1} = mda_writeResults(guiInfo());
        try
            switch lower(e)
                case '.xlsx'
                    if exist(file, 'file'), delete(file); end
                    for k = 1:numel(tabs), writetable(tabs{k}, file, 'Sheet', names{k}); end
                    files = {file};
                case {'.csv', '.txt'}
                    if strcmpi(e, '.csv'), dl = ','; else, dl = '\t'; end
                    files = cellfun(@(nm) fullfile(p, [n '_' nm e]), names, 'UniformOutput', false);
                    if nData == 1, files{1} = file; end  %one data table: the file name chosen
                    for k = 1:numel(tabs), writetable(tabs{k}, files{k}, 'FileType', 'text', 'Delimiter', dl); end
                otherwise
                    error('unknown file type %s', e);
            end
            [~, fn, fe] = cellfun(@fileparts, files, 'UniformOutput', false);
            status(sprintf('Written to %s: %s', p, strjoin(strcat(fn, fe), ', ')));
        catch ME
            status(['Export: ' ME.message]);
        end
    end

    function f2 = onRockerWindow()
        % rocker artifact (2026-10-09): signal of the loaded window before and after the rocker filter and the subtracted
        % periodic artifact (estimated as for 'remove rocker artifact', also if that is off); save as figure (menu) and
        % export the data of the visible time range with the result of the filter and the settings
        f2 = [];
        if isempty(S) || isempty(C), status('Load a time window first.'); return; end
        if ~isempty(sbs), status('Rocker artifact: not available for the rocker stops side by side (rocker at rest).'); return; end
        if ~any(S.rockerOn), status('Rocker artifact: the rocker does not move in this window.'); return; end
        optsC = opts; optsC.zeroForce = zeroUser(ch); optsC.threshold = thrOf(ch);
        try
            [~, msg] = rockerFiltered(optsC);
        catch ME
            status(['Rocker artifact: ' ME.message]); return;
        end
        E = rfCache{ch};
        row = find(S.dataChannels == ch, 1);
        t = S.t(:); before = S.force(row, :)'; art = E.art(:); after = before - art;
        z = mda_zeroForce(S, ch, zeroUser(ch), t);
        hasZ = ~any(isnan(z));
        if hasZ, before = before - z(:); after = after - z(:); end
        if ~isempty(hRA) && isvalid(hRA)
            f2 = hRA; clf(f2); figure(f2);
        else
            f2 = figure('Name', '', 'Color', 'w', 'NumberTitle', 'off', 'Position', [80 120 1100 560]);
            lightTheme(f2);
            hRA = f2;
        end
        f2.Name = sprintf('Rocker artifact - channel %d', ch);
        if relTime, tx = t - S.fromSeconds; xlab = 'time in the window (s)'; else, tx = t; xlab = 'time in file (s)'; end
        a1 = subplot(2, 1, 1, 'Parent', f2); hold(a1, 'on');
        a2 = subplot(2, 1, 2, 'Parent', f2); hold(a2, 'on');
        for a = [a1 a2]
            yl0 = [];
            if a == a1, yl0 = [min([before; after]) max([before; after])]; else, yl0 = [min(art) max(art)]; end
            if diff(yl0) <= 0, yl0 = yl0 + [-1 1]; end
            yl0 = yl0 + [-0.05 0.05] * diff(yl0);
            on = diff([false S.rockerOn(:)' false]); s1 = find(on == 1); s2 = find(on == -1) - 1;
            if ~isempty(s1)
                patch(a, [tx(s1)'; tx(s2)'; tx(s2)'; tx(s1)'], repmat(yl0([1 1 2 2])', 1, numel(s1)), [0.55 0.55 0.55], ...
                    'FaceAlpha', 0.2, 'EdgeColor', 'none');
            end
            ylim(a, yl0);
        end
        plot(a1, tx, before, 'Color', [0.7 0.7 0.7], 'LineWidth', 0.5);
        plot(a1, tx, after, 'k', 'LineWidth', 0.5);
        plot(a2, tx, art, 'Color', uiBlue, 'LineWidth', 0.8);
        if hasZ, yu = ['force - zero force (' mu 'N)']; else, yu = ['force (' mu 'N, sensor signal)']; end
        ylabel(a1, yu); ylabel(a2, ['rocker artifact (' mu 'N)']); xlabel(a2, xlab);
        legend(a1, {'rocker moving', 'before the rocker filter', 'after (analysed)'}, 'Location', 'northeast', 'Box', 'off');
        [~, fn, fe] = fileparts(H.file);
        title(a1, sprintf('%s%s, channel %d (200 Hz signal before the median / mean filters)', fn, fe, ch), ...
            'Interpreter', 'none', 'FontWeight', 'normal', 'FontSize', 9);
        title(a2, msg, 'Interpreter', 'none', 'FontWeight', 'normal', 'FontSize', 9);
        linkaxes([a1 a2], 'x'); xlim(a1, [tx(1) tx(end)]);
        m = uimenu(f2, 'Text', 'Save / Export');
        uimenu(m, 'Text', 'Save figure (.png / .jpg / .tif / .fig) ...', 'MenuSelectedFcn', @(~,~) saveRA());
        uimenu(m, 'Text', 'Export data of the visible time range (.xlsx / .csv / .txt) ...', 'MenuSelectedFcn', @(~,~) exportRA());
        R = E.R;
        function saveRA()
            file = askFile('image', 'rockerArtifact');
            if isempty(file), return; end
            f3 = [];
            try
                f3 = figure('Visible', 'off', 'Color', 'w', 'Position', f2.Position, 'Name', f2.Name);  %without menus
                lightTheme(f3);
                copyobj(findobj(f2, '-depth', 1, {'Type', 'legend', '-or', 'Type', 'axes'}), f3);
                saveFigureFile(f3, file); status(['Saved: ' file]);
            catch ME2
                status(['Save: ' ME2.message]);
            end
            if ~isempty(f3) && isvalid(f3), delete(f3); end
        end
        function exportRA()
            file = askFile('data', 'rockerArtifact');
            if isempty(file), return; end
            xl = xlim(a2);
            I = tx >= xl(1) & tx <= xl(2);
            T = table(t(I), 'VariableNames', {'t_file_s'});
            if relTime, T.t_window_s = tx(I); end
            if ~isnan(H.recordingStart)
                T.clockTime = datetime(H.recordingStart + t(I) / 86400, 'ConvertFrom', 'datenum', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
            end
            if hasZ, nm = 'force_minus_zero'; else, nm = 'force_signal'; end
            T.([nm '_before_uN']) = before(I); T.rockerArtifact_uN = art(I); T.([nm '_after_uN']) = after(I);
            T.rockerMoving = S.rockerOn(I)';
            if height(T) > 1048000 && endsWith(lower(file), '.xlsx')
                status(sprintf('%d rows: too many for Excel. Zoom in or export as .csv / .txt.', height(T))); return;
            end
            Tr = table(ch, {R.status}, R.f0, R.artifactPP, R.r2, 100 * R.correctedFraction, {R.message}, 'VariableNames', ...
                {'channel', 'status', 'rockerFrequency_Hz', 'artifact_uN_peakToPeak', 'artifactR2', ...
                'corrected_percentOfRockerOnTime', 'message'});
            writeTables(file, {'rockerArtifact', 'rockerFilter'}, {T, Tr});
        end
    end

    function I = guiInfo()
        % file facts and all settings of the current channel and window (info table of every export, 2026-10-09)
        I = H;
        I.options = opts;
        if ~isempty(H)
            I.options.zeroForce = zeroUser(ch);                 %NaN = Offset of the log file
            I.options.threshold = thrOf(ch);
        end
        I.labels = Lbl;
        ep = ''; if ~isempty(EP), ep = EP.file; end
        Rf = w2f(range);                                   %times in the file (side-by-side rocker stops)
        I.extra = {'createdBy', 'MyoDishAnalysisGUI'; 'channels', sprintf('%d', ch); ...
            'loadedWindow_s', sprintf('%.15g %.15g', winReq); 'analysedRange_s', rowsText(Rf); ...
            'epRecording', ep};
        if ~isempty(sbs)                                   %rocker stops side by side: the windows read (2026-10-14)
            I.extra(end+1, :) = {'segments_s', rowsText(sbs.seg(:, 1:2))};
        end
        if isempty(I.notes), I.notes = {}; end
    end

    function onShowTable(~, ~)
        if isempty(B), return; end
        T = rangeTable();
        c = table2cell(T);
        for k = 1:numel(c)
            if isdatetime(c{k}), c{k} = char(c{k}); end
        end
        f2 = figure('Name', sprintf('Channel %d: contractions, %s', ch, rangeText()), 'Color', 'w', 'MenuBar', 'none');
        lightTheme(f2);
        uitable(f2, 'Units', 'normalized', 'Position', [0 0 1 1], 'Data', c, 'ColumnName', T.Properties.VariableNames, 'RowName', []);
    end

    function onExport(~, ~)
        if isempty(B), status('Nothing to export.'); return; end
        [~, n] = fileparts(H.file);
        sp = w2f(rngSpan());
        def = sprintf('%s_ch%d_%.0f-%.0fs.xlsx', n, ch, sp(1), sp(2));
        if size(range, 1) > 1, def = sprintf('%s_ch%d_%dranges_%.0f-%.0fs.xlsx', n, ch, size(range, 1), sp(1), sp(2)); end
        if ~isempty(apiFile)
            [pn, fn, fe] = fileparts(apiFile); fn = [fn fe]; apiFile = '';
        else
            [fn, pn] = uiputfile({'*.xlsx', 'Excel (*.xlsx)'; '*.csv', 'text (*.csv)'}, 'Export contractions', def);
            if isequal(fn, 0), return; end
        end
        Tw = rangeTable();                              %(window time: pulses below)
        T = rangeTable(true);                           %times in the file; several ranges: column range
        Sm = summaryAll();
        info = guiInfo();
        % analysis window (open the results again: same data window, range(s) and threshold)
        Rf = w2f(range); nRg = size(range, 1);
        info.thresholds = table((1:nRg)', repmat(ch, nRg, 1), Rf(:,1), Rf(:,2), repmat(C.threshold, nRg, 1), ...
            repmat(C.maxStimToPeak, nRg, 1), repmat(winReq(1), nRg, 1), repmat(winReq(2), nRg, 1), ...
            'VariableNames', {'range','channel','from','to','threshold_uN','maxStimToPeak_s','windowFrom','windowTo'});
        if opts.pulseTable && isfield(C, 'pulses') && istable(C.pulses) && height(C.pulses) > 0   %pulses of the range(s)
            Pr = C.pulses(inRng(C.pulses.t), :);
            [isP, locP] = ismember(Pr.t_peak, Tw.t_peak);
            Pr.contraction(:) = nan; Pr.contraction(isP) = Tw.contraction(locP(isP));
            lb = arrayfun(@(k) sprintf('range%d', k), max(1, rangeOf(Pr.t)), 'UniformOutput', false);
            info.pulses = [table(lb(:), 'VariableNames', {'range'}), fileTimes(Pr)];
        end
        if ~isempty(C.rockerFilter)                     %result of the rocker filter (as MyoDishAnalysis)
            RF = C.rockerFilter;
            info.rockerFilter = cell2table({'range1', ch, winReq(1), winReq(2), RF.status, RF.f0, RF.artifactPP, ...
                RF.r2, 100 * RF.correctedFraction, RF.message}, 'VariableNames', {'range','channel','from_s','to_s', ...
                'status','rockerFrequency_Hz','artifact_uN_peakToPeak','artifactR2','corrected_percentOfRockerOnTime','message'});
        end
        try
            files = mda_writeResults(fullfile(pn, fn), T, Sm, info);
            status(sprintf('Written: %s', strjoin(files, ', ')));
        catch ME
            status(['Error: ' ME.message]);
        end
    end

    function onAllChannels(~, ~)
        if isempty(S), status('Load a time window first.'); return; end
        [~, n] = fileparts(H.file);
        Rf = w2f(range);
        def = sprintf('%s_allChannels_%.0f-%.0fs.xlsx', n, Rf(1,1), Rf(end,2));
        [fn, pn] = uiputfile({'*.xlsx', 'Excel (*.xlsx)'; '*.csv', 'text (*.csv)'}, 'All channels', def);
        if isequal(fn, 0), return; end
        status('Analysing all channels ...'); drawnow;
        try
            optsAll = opts;
            optsAll.zeroForce = zeroUser(H.dataChannels);    %NaN = Offset of the log file
            optsAll.threshold = thrOf(H.dataChannels);       %NaN = auto
            rep = reportAll;                           %analysis report (2026-10-11)
            MyoDishAnalysis(H.file, [], Rf(:,1), Rf(:,2), optsAll, 'output', fullfile(pn, fn), 'quiet', true, ...
                'metadata', Lbl, 'report', rep, 'pooled', size(Rf, 1) > 1);
            more = '';
            if size(Rf, 1) > 1, more = sprintf(', %d ranges each in its own data window + ''all ranges''', size(Rf, 1)); end
            status(sprintf('All channels written to %s%s (same settings, manual exclusions not applied%s).', fn, ...
                repmat(' and the report (_report.pdf)', 1, rep), more));
        catch ME
            status(['Error: ' ME.message]);
        end
    end

    function onCopy(~, ~)
        if isempty(B), return; end
        Sm = summaryRow();
        [~, n, e] = fileparts(H.file);
        Rf = w2f(range);
        if size(Rf, 1) == 1
            rl = sprintf('range (s)\t%.2f\t%.2f', Rf(1), Rf(2));
        else
            rl = sprintf('ranges (s)\t%d\t%s', size(Rf, 1), strjoin(arrayfun(@(r) sprintf('%.2f-%.2f', Rf(r,1), Rf(r,2)), ...
                (1:size(Rf, 1))', 'UniformOutput', false), '; '));
        end
        lines = {sprintf('file\t%s', [n e]), sprintf('channel\t%d', ch), rl, ...
            sprintf('n contractions\t%d', Sm.nContractions), ...
            sprintf('extra beats\t%d\tof %d contractions\t%.3g %%', Sm.nExtraBeats, Sm.nDetected, Sm.extraBeats_percent), ...
            sprintf('missed beats\t%d\tof %d stimuli\t%.3g %%', Sm.nMissedBeats, Sm.nStimuli, Sm.missedBeats_percent), ...
            sprintf('uncertain\t%d\tstimulated %d\textra %d\tmissed %d', Sm.nUncertain, Sm.nStimulatedUncertain, ...
            Sm.nExtraBeatsUncertain, Sm.nMissedBeatsUncertain)};
        ln = setdiff(Lbl.Properties.VariableNames, {'channel'}, 'stable');
        for k = 1:numel(ln)
            v = Sm.(ln{k});
            if iscell(v), v = v{1}; end
            if isnumeric(v), if isnan(v), v = ''; else, v = sprintf('%.3f', v); end, end
            if ~isempty(v), lines{end+1} = sprintf('%s\t%s', ln{k}, v); end %#ok<AGROW>
        end
        hasRef = isfield(C, 'referenceBeat') && ~isempty(C.referenceBeat);
        sel = selected();
        lines{end+1} = sprintf('parameter\tmean\tmedian\tSD\tn\tunit%s', repmat(sprintf('\trelative to reference'), 1, hasRef));
        for k = 1:size(PI, 1)
            lines{end+1} = sprintf('%s\t%.6g\t%.6g\t%.6g\t%d\t%s', PI{k,1}, Sm.([PI{k,1} '_mean']), selMedian(PI{k,1}, sel), ...
                Sm.([PI{k,1} '_SD']), Sm.([PI{k,1} '_n']), PI{k,2}); %#ok<AGROW>
            if hasRef                                   %2026-10-06: % of the reference (diastolic: difference in uN)
                c = relCell(Sm, PI{k,1});
                if startsWith(c, char(916)), c = [c(2:end) ' uN']; elseif ~isempty(c), c = [c ' %']; end
                lines{end} = sprintf('%s\t%s', lines{end}, c);
            end
        end
        clipboard('copy', strjoin(lines, newline));
        status('Summary copied to the clipboard (tab separated).');
    end


% =====================================================================================================
% mouse
% =====================================================================================================
    function onMouseDown(~, ~)
        if isempty(H), return; end
        if strcmp(fig.SelectionType, 'alt')                  %right click: context menu (zero force, save / export)
            if inAxes(axMain), cp = get(axMain, 'CurrentPoint'); altPt = cp(1, 1:2); else, altPt = [nan nan]; end
            return;
        end
        if strcmp(fig.SelectionType, 'open')               %double-click: whole file / whole loaded window
            if inAxes(axOv) && ~isempty(O)
                ovXL = []; plotOverview();
            elseif epFrac > 0 && isvalid(axEPv) && inAxes(axEPv)   %EP plots: y limits automatic (2026-10-09)
                epSetYLim(1, []);
            elseif epFrac > 0 && isvalid(axEPs) && inAxes(axEPs)
                epSetYLim(2, []);
            elseif ~isempty(S) && (inAxes(axMain) || inAxes(axStim) || inAxes(axPar))
                xlim(axMain, [S.fromSeconds S.toSeconds]);
            end
            return;
        end
        if epFrac > 0 && ~isempty(EP) && isvalid(axEPv) && (inAxes(axEPv) || inAxes(axEPs))
            if inAxes(axEPv), axY = axEPv; else, axY = axEPs; end   %drag up / down: y limits of this EP plot
            startDragY(axY);
            return;
        end
        if inAxes(axMain) && ~isempty(comT)                %click on a comment mark at the top of the force plot (2026-10-14)
            cp = get(axMain, 'CurrentPoint'); yl = ylim(axMain);
            [d, q] = min(abs(comT - cp(1,1)));
            if cp(1,2) >= yl(2) - 0.12 * diff(yl) && d <= 0.006 * diff(xlim(axMain))
                comMarkerClick(comK(q)); return;
            end
        end
        if inAxes(axMain) && ~isempty(S)
            x = clampX(axMain);
            if rbRange.Value
                dragAdd = shiftDown || any(strcmp(fig.CurrentModifier, 'shift'));   %shift + drag: add a range (2026-10-14)
                startDrag(axMain, x);
            else
                toggleContraction(x);
            end
        elseif inAxes(axOv) && ~isempty(O)
            startDrag(axOv, clampX(axOv));
        end
    end

    function onScroll(~, evt)
        % mouse wheel: zoom the time axis around the mouse position; shift + wheel: move
        if isempty(H), return; end
        if inAxes(axOv) && ~isempty(O)
            axZ = axOv; lim = [0 O.totalSeconds]; minSpan = 5;
        elseif ~isempty(S) && (inAxes(axMain) || inAxes(axStim) || inAxes(axPar) || (epFrac > 0 && (inAxes(axEPv) || inAxes(axEPs))))
            axZ = axMain; lim = [S.fromSeconds S.toSeconds]; minSpan = 0.3;
        else
            return;
        end
        n = evt.VerticalScrollCount;
        xl = xlim(axZ);
        cp = get(axZ, 'CurrentPoint'); x0 = cp(1,1);
        if any(strcmp(fig.CurrentModifier, 'shift'))
            xl = xl + n * 0.15 * diff(xl);
        else
            xl = x0 + (xl - x0) * 1.25 ^ n;                 %wheel up (n < 0): zoom in
        end
        span = min(max(diff(xl), minSpan), diff(lim));
        xl(1) = min(max(xl(1), lim(1)), lim(2) - span);
        xl = [xl(1) xl(1) + span];
        if axZ == axOv
            if span >= 0.999 * diff(lim), ovXL = []; else, ovXL = xl; end
            plotOverview();
            scheduleDetail();
        else
            xlim(axMain, xl);
        end
    end

    % ---------------------------------------------------------------- keyboard: navigation on the time axis (2026-10-07)
    function onKey(~, evt)
        % left / right arrow: move the loaded window by half its length; shift: extend it by half its length on that
        % side; up / down arrow: zoom in / out (half / twice its length). Mouse over the overview: the time axis of the
        % overview; otherwise the loaded window (= selection in the overview, analysed range), read again
        shiftDown = strcmp(evt.Key, 'shift') || any(strcmp(evt.Modifier, 'shift'));
        if isempty(H) || ~any(strcmp(evt.Key, {'leftarrow', 'rightarrow', 'uparrow', 'downarrow'})), return; end
        co = fig.CurrentObject;                            %arrow keys of edit fields and lists stay theirs
        if ~isempty(co) && isprop(co, 'Style') && any(strcmp(co.Style, {'edit', 'popupmenu', 'listbox', 'slider'})), return; end
        ext = any(strcmp(evt.Modifier, 'shift'));
        if ~isempty(O) && inAxes(axOv)
            lim = [0 O.totalSeconds];
            xl = navStep(xlim(axOv), evt.Key, ext, lim, 5);
            if diff(xl) >= 0.999 * diff(lim), ovXL = []; else, ovXL = xl; end
            plotOverview();
            scheduleDetail();
            return;
        end
        if isempty(S), return; end
        navButton(evt.Key, ext);                           %force plot: the loaded window (selection in the overview)
    end

    function onKeyRelease(~, evt)
        if strcmp(evt.Key, 'shift'), shiftDown = false; end
    end

    function onNavButton(key)
        % buttons under the force plot: as the arrow keys in the force plot; shift + click on the left / right button
        % extends the loaded window instead of moving it
        ext = any(strcmp(key, {'leftarrow', 'rightarrow'})) && (shiftDown || any(strcmp(fig.CurrentModifier, 'shift')));
        navButton(key, ext);
    end

    function navButton(key, ext)
        % arrow keys in the force plot and the buttons under it: change the loaded window (= selection in the overview
        % and analysed range): left / right = move it by half its length (ext / shift: extend it on that side), up /
        % down = zoom in / out (half / twice its length around the centre, at least 1 s); the window is read again
        if isempty(H) || isempty(S), status('Load a time window first.'); return; end
        if ~isempty(sbs)
            status(['Rocker stops side by side: load a window (From / To and Load, or drag in the overview) to return ' ...
                'to the continuous view.']); return;
        end
        loadWindow(navStep([S.fromSeconds S.toSeconds], key, ext, [0 H.totalSeconds], 1));
    end

    function loadWindow(w)
        % read the window w (s): From / To, a zoomed overview moves along; analysed range = the whole window
        w = [max(0, w(1)), min(H.totalSeconds, w(2))];
        if diff(w) > 4 * 3600, status('Window longer than 4 h: use the command line version (MyoDishAnalysis) for long ranges.'); return; end
        if abs(w(1) - S.fromSeconds) < 1e-6 && abs(w(2) - S.toSeconds) < 1e-6, return; end   %start / end of the file
        followOverview(w);
        hFrom.String = sprintf('%.3f', w(1)); hTo.String = sprintf('%.3f', w(2));
        onLoad();
    end

    function followOverview(w)
        % zoomed overview: move it along when the loaded window w leaves the visible part
        if isempty(O) || isempty(ovXL) || (w(1) >= ovXL(1) && w(2) <= ovXL(2)), return; end
        span = max(diff(ovXL), 1.25 * diff(w));
        if w(2) > ovXL(1) + span, a = w(2) + 0.1 * span - span; else, a = min(ovXL(1), w(1) - 0.1 * span); end
        a = min(max(a, 0), O.totalSeconds - span);
        if span >= 0.999 * O.totalSeconds, ovXL = []; else, ovXL = [a, a + span]; end
        scheduleDetail();
    end

    function scheduleDetail()
        % read the detailed overview 0.4 s after the last wheel event
        try
            if isempty(tmr) || ~isvalid(tmr)
                tmr = timer('StartDelay', 0.4, 'ExecutionMode', 'singleShot', 'TimerFcn', @(~,~) loadDetail());
            end
            stop(tmr); start(tmr);
        catch
            loadDetail();
        end
    end

    function loadDetail()
        if isempty(O) || isempty(H) || ~isvalid(fig), return; end
        if isempty(ovXL), Od = []; return; end
        span = diff(ovXL);
        if span / O.binSeconds > 1500, return; end          %the overview of the whole file is detailed enough
        if ~isempty(Od) && Od.range(1) <= ovXL(1) && Od.range(2) >= ovXL(2) && Od.binSeconds <= span / 1500
            return;                                         %already read
        end
        r = [max(0, ovXL(1) - 0.25 * span), min(H.totalSeconds, ovXL(2) + 0.25 * span)];
        bin = max(2 / H.samplingRate, span / 3000);
        old = hStatus.String; status('Reading the zoomed part of the overview ...'); drawnow;
        try
            Od = mda_readMdd(H.file, 'overview', [bin r], opts);
            Od.range = r;
        catch ME
            Od = []; status(['Overview: ' ME.message]); return;
        end
        status(old);
        plotOverview();
    end

    function onClose(~, ~)
        try
            if ~isempty(tmr) && isvalid(tmr), stop(tmr); delete(tmr); end
        catch
        end
        try
            if ~isempty(hCom) && isvalid(hCom.fig), delete(hCom.fig); end
            if ~isempty(hOv) && isvalid(hOv.fig), delete(hOv.fig); end
            if ~isempty(hPr) && isvalid(hPr.fig), delete(hPr.fig); end
            if ~isempty(hAdv) && isvalid(hAdv), delete(hAdv); end   %advanced settings (2026-10-10)
            if ~isempty(hBrw) && isvalid(hBrw.fig), delete(hBrw.fig); end   %results browser (2026-10-14)
        catch
        end
    end

    % ---------------------------------------------------------------- stimulation protocols (2026-10-07)
    function onProtocols(~, ~)
        % protocols of the log file (mda_protocols), contractions grouped by the protocol quantity (MyoDishAnalysis
        % options 'protocol' / 'groupBy', mda_groupBeats), plot of a parameter against the quantity, export
        if isempty(H), status('Open a file first.'); return; end
        if ~isempty(hPr) && isvalid(hPr.fig)
            if strcmp(hPr.file, H.file), figure(hPr.fig); return; end
            delete(hPr.fig);
        end
        [~, prN, prE] = fileparts(H.file);
        f4 = figure('Name', ['MyoDishAnalysis: protocols - ' prN prE], 'NumberTitle', 'off', 'Color', 'w', 'Units', 'pixels', ...
            'Position', [90 70 1400 760], 'DeleteFcn', @(~,~) clearProtocols());
        lightTheme(f4);
        dd = {'Units', 'normalized', 'FontSize', 10, 'BackgroundColor', 'w'};
        axP = axes(f4, 'Position', [0.06 0.47 0.55 0.49]); box(axP, 'on'); grid(axP, 'on');
        tRes = uitable(f4, 'Units', 'normalized', 'Position', [0.01 0.01 0.62 0.37], 'RowName', [], 'FontSize', 9);
        x0 = 0.645; w0 = 0.345;
        uicontrol(f4, dd{:}, 'Style', 'text', 'String', ['Protocols (comments ''start ... protocol'' / ''end ... protocol'' or schedule files in the log file). ' ...
            'Tick the protocols to analyse; From / To and the grouping can be changed.'], 'HorizontalAlignment', 'left', ...
            'Position', [x0 0.92 w0 0.06], 'FontSize', 9);
        tProt = uitable(f4, 'Units', 'normalized', 'Position', [x0 0.6 w0 0.32], 'RowName', [], 'FontSize', 9, ...
            'ColumnName', {'use', 'type', 'name', 'from (s)', 'to (s)', 'group by', 'note'}, ...
            'ColumnFormat', {'logical', 'char', 'char', 'numeric', 'numeric', 'char', 'char'}, ...
            'ColumnEditable', [true true true true true true false], 'ColumnWidth', {32, 60, 140, 62, 62, 105, 90}, ...
            'CellSelectionCallback', @(~, ev) setappdata(f4, 'prRow', ev.Indices), ...
            'TooltipString', ['group by: pacingFrequency, S2interval, stimCurrent, pauseLength, rockerSpeed, pulseDuration, ' ...
            'log:<code> (any numeric entry of the log file, e.g. log:pauseDuration), none']);
        uicontrol(f4, dd{:}, 'Style', 'pushbutton', 'String', 'Find in log file', 'Position', [x0 0.55 0.11 0.04], 'Callback', @(~,~) prFind());
        uicontrol(f4, dd{:}, 'Style', 'pushbutton', 'String', '+ selected range', 'Position', [x0+0.117 0.55 0.11 0.04], 'Callback', @(~,~) prAddRange(), ...
            'TooltipString', 'add the range selected in the main window as a protocol (choose the grouping)');
        uicontrol(f4, dd{:}, 'Style', 'pushbutton', 'String', 'Remove', 'Position', [x0+0.234 0.55 0.111 0.04], 'Callback', @(~,~) prRemove());
        uicontrol(f4, dd{:}, 'Style', 'text', 'String', 'Channels', 'HorizontalAlignment', 'left', 'Position', [x0 0.49 0.08 0.03]);
        lbC = uicontrol(f4, dd{:}, 'Style', 'listbox', 'String', arrayfun(@(c) sprintf('Ch %d', c), H.dataChannels, 'UniformOutput', false), ...
            'Max', 2, 'Min', 0, 'Value', max(1, find(H.dataChannels == ch, 1)), 'Position', [x0+0.08 0.39 0.12 0.13], ...
            'TooltipString', 'ctrl / cmd + click: several channels');
        uicontrol(f4, dd{:}, 'Style', 'text', 'String', 'Contractions', 'HorizontalAlignment', 'left', 'Position', [x0 0.335 0.08 0.03]);
        pRk = uicontrol(f4, dd{:}, 'Style', 'popupmenu', 'String', {'rocker at rest only', 'all contractions', 'rocker moving only'}, ...
            'Position', [x0+0.08 0.34 0.265 0.03], 'TooltipString', ['default: only contractions with the rocker at rest. Sharp-electrode ' ...
            'recordings (no rocker) or protocols without rocker stops: all contractions']);
        cSt = uicontrol(f4, dd{:}, 'Style', 'checkbox', 'String', 'only stimulated contractions', 'Value', 1, ...
            'Position', [x0+0.08 0.3 0.265 0.03]);
        prPar = [PI(~startsWith(PI(:,1), 'ref'), 1:2); {'amplitude_pctOfRef', '% of S1 / steady'; 'capture_percent', '%'; 'nContractions', ''}];
        uicontrol(f4, dd{:}, 'Style', 'text', 'String', 'Parameter', 'HorizontalAlignment', 'left', 'Position', [x0 0.25 0.08 0.03]);
        pPa = uicontrol(f4, dd{:}, 'Style', 'popupmenu', 'String', strcat(prPar(:,1), {' ('}, strrep(prPar(:,2), 'u', mu), {')'}), ...
            'Position', [x0+0.08 0.255 0.265 0.03], 'Callback', @(~,~) prDraw());
        uicontrol(f4, dd{:}, 'Style', 'text', 'String', 'Show', 'HorizontalAlignment', 'left', 'Position', [x0 0.205 0.08 0.03]);
        pSh = uicontrol(f4, dd{:}, 'Style', 'popupmenu', 'String', {'-'}, 'Position', [x0+0.08 0.21 0.265 0.03], 'Callback', @(~,~) prDraw(), ...
            'TooltipString', 'protocols grouped by the same quantity are shown together');
        pSD = uicontrol(f4, dd{:}, 'Style', 'popupmenu', 'String', {[char(177) ' SD'], [char(177) ' SEM'], 'mean only'}, ...
            'Position', [x0+0.08 0.17 0.13 0.03], 'Callback', @(~,~) prDraw());
        pTb = uicontrol(f4, dd{:}, 'Style', 'popupmenu', 'String', {'table: groups', 'table: protocol results'}, ...
            'Position', [x0+0.215 0.17 0.13 0.03], 'Callback', @(~,~) prTable(), 'TooltipString', ['protocol results: ' ...
            'max. captured frequency, FFR ratios, current thresholds, refractory periods (no peak / no response), ' ...
            'PRP at 15 / 30 / 60 s, per protocol and channel']);
        uicontrol(f4, dd{:}, mainBtn{:}, 'Style', 'pushbutton', 'String', 'Analyse', 'Position', [x0 0.11 w0 0.045], ...
            'Callback', @(~,~) prAnalyse(), 'TooltipString', ['contractions of the ticked protocols and channels, grouped (threshold, ' ...
            'filters, zero force, rocker filter and labels as in the main window)']);
        uicontrol(f4, dd{:}, 'Style', 'pushbutton', 'String', 'Save figure ...', 'Position', [x0 0.06 0.17 0.04], 'Callback', @(~,~) prSaveFigure());
        uicontrol(f4, dd{:}, 'Style', 'pushbutton', 'String', 'Export ...', 'Position', [x0+0.175 0.06 0.17 0.04], 'Callback', @(~,~) prExport());
        tx = uicontrol(f4, dd{:}, 'Style', 'text', 'String', '', 'HorizontalAlignment', 'left', 'Position', [x0 0.0 w0 0.055], 'FontSize', 8);
        hPr = struct('fig', f4, 'file', H.file, 'ax', axP, 'tRes', tRes, 'tProt', tProt, 'lbC', lbC, 'pRk', pRk, 'cSt', cSt, ...
            'pPa', pPa, 'par', {prPar}, 'pSh', pSh, 'pSD', pSD, 'pTb', pTb, 'tx', tx);
        prRes = [];
        prFind();
    end

    function clearProtocols()
        hPr = []; prRes = [];
    end

    function prFind()
        if isempty(hPr) || ~isvalid(hPr.fig), return; end
        try
            prP = mda_protocols(H);
        catch ME
            hPr.tx.String = ['Protocols: ' ME.message]; prP = table();
        end
        if height(prP) == 0
            hPr.tProt.Data = cell(0, 7);
            hPr.tx.String = 'No protocol found (comments ''start ... protocol'' / ''end ... protocol''). Add a range with ''+ selected range''.';
            return;
        end
        hPr.tProt.Data = [num2cell(~strcmp(prP.groupBy, 'none')), prP.type, prP.name, num2cell(round(prP.from, 2)), ...
            num2cell(round(prP.to, 2)), prP.groupBy, prP.note];
        hPr.tx.String = sprintf('%d protocol(s) found in the log file.', height(prP));
    end

    function prAddRange()
        if any(isnan(range(:))), hPr.tx.String = 'Select a range in the main window first.'; return; end
        spF = w2f(rngSpan());                              %several ranges: first start to last end (time in the file)
        hPr.tProt.Data = [hPr.tProt.Data; {true, 'manual', 'selected range', round(spF(1), 2), round(spF(2), 2), 'pacingFrequency', ''}];
    end

    function prRemove()
        prIdx = getappdata(hPr.fig, 'prRow');
        if isempty(prIdx) || isempty(hPr.tProt.Data), return; end
        prD = hPr.tProt.Data;
        prD(unique(prIdx(:,1)), :) = [];
        hPr.tProt.Data = prD;
        setappdata(hPr.fig, 'prRow', []);
    end

    function prAnalyse()
        prD = hPr.tProt.Data;
        if isempty(prD), hPr.tx.String = 'No protocol.'; return; end
        prUse = cellfun(@(x) isequal(x, true), prD(:,1));
        prD = prD(prUse, :);
        prChs = H.dataChannels(hPr.lbC.Value);
        if isempty(prD) || isempty(prChs), hPr.tx.String = 'Tick at least one protocol and select a channel.'; return; end
        prFrom = cellfun(@double, prD(:,4)); prTo = cellfun(@double, prD(:,5));
        if any(isnan(prFrom) | isnan(prTo) | prTo <= prFrom), hPr.tx.String = 'From / To: numbers (s), To > From.'; return; end
        prTyp = prD(:,2); prTyp(cellfun(@isempty, prTyp)) = {'manual'};
        prNum = zeros(numel(prTyp), 1);
        for q = 1:numel(prTyp), prNum(q) = sum(strcmp(prTyp(1:q), prTyp{q})); end
        prBy = strtrim(prD(:,6)); prBy(cellfun(@isempty, prBy)) = {'none'};
        prP = table(prTyp, prD(:,3), prNum, prFrom, prTo, prBy, repmat({''}, numel(prTyp), 1), repmat({''}, numel(prTyp), 1), ...
            repmat({''}, numel(prTyp), 1), 'VariableNames', {'type','name','number','from','to','groupBy','startComment','endComment','note'});
        prRk = {'stopped', 'any', 'moving'};
        prBt = {'all', 'stimulated'};
        prO = opts;
        prO.zeroForce = zeroUser(prChs);                %NaN = Offset of the log file
        prO.threshold = thrOf(prChs);                   %NaN = auto
        hPr.tx.String = 'Analysing ...'; drawnow;
        try
            [prT, prS, prI] = MyoDishAnalysis(H.file, prChs, [], [], prO, 'protocol', prP, 'rocker', prRk{hPr.pRk.Value}, ...
                'beats', prBt{hPr.cSt.Value + 1}, 'quiet', true, 'metadata', Lbl);
        catch ME
            hPr.tx.String = ['Error: ' ME.message]; return;
        end
        prRes = struct('T', prT, 'S', prS, 'info', prI);
        prQ = unique(prS.groupBy(~strcmp(prS.groupBy, 'none')), 'stable');
        prItems = cell(numel(prQ), 1);
        for q = 1:numel(prQ)
            prItems{q} = sprintf('%s: %s', prQ{q}, strjoin(unique(prS.range(strcmp(prS.groupBy, prQ{q})), 'stable'), ', '));
        end
        if isempty(prItems), prItems = {'-'}; end
        hPr.pSh.String = prItems; hPr.pSh.Value = 1;
        hPr.pSh.UserData = prQ;
        prNotes = strjoin(prI.notes(1:min(2, end)), ' ');
        hPr.tx.String = sprintf('%d contractions, %d groups (%s; channels %s). %s', height(prT), height(prS), ...
            strjoin(strcat(prP.type, {' '}, arrayfun(@num2str, prP.number, 'UniformOutput', false)), ', '), ...
            strjoin(arrayfun(@num2str, prChs, 'UniformOutput', false), ', '), prNotes);
        prDraw();
    end

    function prDraw()
        if isempty(hPr) || ~isvalid(hPr.fig), return; end
        axP = hPr.ax;
        cla(axP); legend(axP, 'off'); hold(axP, 'on');
        if isempty(prRes) || isempty(hPr.pSh.UserData), prTable(); return; end
        prQ = hPr.pSh.UserData{hPr.pSh.Value};
        prNm = hPr.par{hPr.pPa.Value, 1}; prUnit = strrep(hPr.par{hPr.pPa.Value, 2}, 'u', mu);
        prS = prRes.S;
        if ismember(prNm, {'amplitude_pctOfRef', 'capture_percent', 'nContractions'})
            prM = prNm; prSDc = '';
        else
            prM = [prNm '_mean']; prSDc = [prNm '_SD'];
        end
        prS = prS(strcmp(prS.groupBy, prQ), :);
        switch prQ
            case 'pacingFrequency', prXl = 'pacing frequency (Hz)'; prXf = 1;
            case 'S2interval',      prXl = 'S2 interval (ms)';      prXf = 1000;
            case 'stimCurrent',     prXl = 'stimulus current (mA)'; prXf = 1;
            case 'pauseLength',     prXl = 'rest interval (s)';     prXf = 1;
            case 'rockerSpeed',     prXl = 'rocker speed (rpm)';    prXf = 1;
            case 'pulseDuration',   prXl = 'pulse duration (ms)';   prXf = 1;
            otherwise,              prXl = strrep(prQ, 'log:', ''); prXf = 1;
        end
        prCol = [0 114 189; 217 83 25; 237 177 32; 126 47 142; 119 172 48; 77 190 238; 162 20 47; 0 0 0] / 255;
        prKeys = unique(strcat(prS.range, {'|'}, arrayfun(@num2str, prS.channel, 'UniformOutput', false)), 'stable');
        prH = gobjects(0); prL = {};
        for q = 1:numel(prKeys)
            prK = strsplit(prKeys{q}, '|');
            prG = prS(strcmp(prS.range, prK{1}) & prS.channel == str2double(prK{2}), :);
            prC = prCol(mod(q-1, size(prCol,1)) + 1, :);
            for prRo = unique(prG.groupRole, 'stable')'
                if any(strcmp(prRo{1}, {'other', 'preS2', 'afterRest'})), continue; end   %no value: table only
                prR = prG(strcmp(prG.groupRole, prRo{1}), :);
                prY = prR.(prM);
                if any(strcmp(prRo{1}, {'S1', 'steady'}))           %reference: horizontal line
                    if ~isempty(prY) && ~isnan(prY(1))
                        prH(end+1) = yline(axP, prY(1), '--', 'Color', prC, 'LineWidth', 1.2); %#ok<AGROW>
                        prL{end+1} = sprintf('Ch %s %s %s', prK{2}, prK{1}, prRo{1}); %#ok<AGROW>
                    end
                    continue;
                end
                prX = prR.groupValue * prXf;
                prOk = ~isnan(prX);
                [prX, prO2] = sort(prX(prOk)); prY = prY(prOk); prY = prY(prO2);
                if strcmp(prRo{1}, 'postS2'), prSty = 's:'; else, prSty = 'o-'; end
                if ~isempty(prSDc) && hPr.pSD.Value < 3
                    prE = prR.(prSDc)(prOk); prE = prE(prO2);
                    if hPr.pSD.Value == 2
                        prNn = prR.([prNm '_n'])(prOk); prE = prE ./ sqrt(prNn(prO2));
                    end
                    prE(isnan(prE)) = 0;
                    prH(end+1) = errorbar(axP, prX, prY, prE, prSty, 'Color', prC, 'MarkerFaceColor', prC, 'LineWidth', 1.2, 'CapSize', 0); %#ok<AGROW>
                else
                    prH(end+1) = plot(axP, prX, prY, prSty, 'Color', prC, 'MarkerFaceColor', prC, 'LineWidth', 1.2); %#ok<AGROW>
                end
                prRl = prRo{1}; if strcmp(prRl, 'postS2'), prRl = 'post-S2'; end
                prL{end+1} = strtrim(sprintf('Ch %s %s %s', prK{2}, prK{1}, prRl)); %#ok<AGROW>
            end
        end
        hold(axP, 'off');
        xlabel(axP, prXl);
        if isempty(prUnit), ylabel(axP, prNm, 'Interpreter', 'none'); else, ylabel(axP, sprintf('%s (%s)', prNm, prUnit), 'Interpreter', 'none'); end
        if ~isempty(prH), legend(axP, prH, prL, 'Location', 'best', 'Interpreter', 'none', 'FontSize', 8, 'Box', 'off'); end
        prTable();
    end

    function prTable()
        if isempty(hPr) || ~isvalid(hPr.fig), return; end
        if isempty(prRes), hPr.tRes.Data = {}; return; end
        prNm = hPr.par{hPr.pPa.Value, 1};
        if hPr.pTb.Value == 2                           %protocol results: the columns with values
            if ~isfield(prRes.info, 'protocolResults'), hPr.tRes.Data = {}; hPr.tRes.ColumnName = {}; return; end
            prS = prRes.info.protocolResults;
            prV = prS.Properties.VariableNames(find(strcmp(prS.Properties.VariableNames, 'groupBy')) + 1:end);
            prV = prV(~strcmp(prV, 'resultNote'));
            prV = prV(cellfun(@(c) any(~isnan(prS.(c))), prV));
            prCols = [{'range', 'channel'}, prV, {'resultNote'}];
        else
            prS = prRes.S;
            prCols = {'range', 'channel', 'group', 'nStimuli', 'nContractions', 'capture_percent'};
            if ismember([prNm '_mean'], prS.Properties.VariableNames)
                prCols = [prCols, {[prNm '_mean'], [prNm '_SD'], [prNm '_n']}];
            elseif ismember(prNm, prS.Properties.VariableNames) && ~ismember(prNm, prCols)
                prCols{end+1} = prNm;
            end
            if ~ismember('amplitude_pctOfRef', prCols), prCols{end+1} = 'amplitude_pctOfRef'; end
        end
        prD = cell(height(prS), numel(prCols));
        for j = 1:numel(prCols)
            v = prS.(prCols{j});
            if iscell(v)
                prD(:, j) = v;
            else
                for i = 1:height(prS)
                    if isnan(v(i)), prD{i, j} = ''; elseif startsWith(prCols{j}, 'n'), prD{i, j} = sprintf('%.0f', v(i)); else, prD{i, j} = sprintf('%.4g', v(i)); end
                end
            end
        end
        hPr.tRes.ColumnName = prCols;
        hPr.tRes.Data = prD;
    end

    function prSaveFigure()
        if isempty(prRes), hPr.tx.String = 'Press Analyse first.'; return; end
        file = askFile('image', 'protocols');
        if isempty(file), return; end
        f2 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [50 50 900 600]);
        lightTheme(f2);
        try
            lg = hPr.ax.Legend;
            if ~isempty(lg) && isvalid(lg), c = copyobj([lg hPr.ax], f2); a = c(2); else, a = copyobj(hPr.ax, f2); end
            a.Units = 'normalized'; a.Position = [0.11 0.12 0.85 0.82];
            saveFigureFile(f2, file);
            hPr.tx.String = ['Saved: ' file];
        catch ME
            hPr.tx.String = ['Save: ' ME.message];
        end
        delete(f2);
    end

    function prExport()
        if isempty(prRes), hPr.tx.String = 'Press Analyse first.'; return; end
        file = askFile('data', 'protocols');
        if isempty(file), return; end
        [pp, nn, ee] = fileparts(file);
        if strcmpi(ee, '.txt'), file = fullfile(pp, [nn '.csv']); end
        try
            files = mda_writeResults(file, prRes.T, prRes.S, prRes.info);
            hPr.tx.String = ['Written: ' strjoin(files, ', ')];
        catch ME
            hPr.tx.String = ['Export: ' ME.message];
        end
    end

    % ---------------------------------------------------------------- comments of the log file
    function onComments(~, ~)
        if isempty(H), status('Open a file first.'); return; end
        if ~isempty(hCom) && isvalid(hCom.fig), figure(hCom.fig); return; end
        [~, n, e] = fileparts(H.file);
        f2 = uifigure('Name', ['Comments - ' n e], 'Position', [120 120 950 520]);
        lightTheme(f2);
        g = uigridlayout(f2, [3 5]);
        g.RowHeight = {28, '1x', 22}; g.ColumnWidth = {55, '1x', 230, 110, 80};
        uilabel(g, 'Text', 'Search:');
        ef = uieditfield(g, 'text', 'ValueChangedFcn', @(~,~) filterComments());
        try ef.ValueChangingFcn = @(~,evt) filterComments(evt.Value); catch, end   %live search (R2018b+)
        try ef.Placeholder = 'text (several words: all must occur)'; catch, end
        cb = uicheckbox(g, 'Text', 'all log entries (events, settings)', 'ValueChangedFcn', @(~,~) filterComments());
        lbl = uilabel(g, 'Text', '');
        uibutton(g, 'Text', 'Go to', 'ButtonPushedFcn', @(~,~) gotoRow());
        ut = uitable(g, 'RowName', {}, 'ColumnName', {'#', 'date / time', 'time in file', 't (s)', 'ch', 'code', 'text'}, ...
            'ColumnWidth', {34, 140, 80, 80, 35, 110, 'auto'}, 'CellSelectionCallback', @(~,evt) selectRow(evt));
        try ut.SelectionType = 'row'; catch, end           %R2021b+
        ut.Layout.Row = 2; ut.Layout.Column = [1 5];
        if isprop(ut, 'DoubleClickedFcn'), ut.DoubleClickedFcn = @(~,evt) dblClickRow(evt); end   %R2021a+
        hint = uilabel(g, 'Text', ['# = number in the force plot. Select a row: marked in the force plot; double-click ' ...
            '(or Go to): loads the data around it (window length = loaded window, at least 30 s).'], 'FontColor', [0.3 0.3 0.3]);
        hint.Layout.Row = 3; hint.Layout.Column = [1 5];
        hCom = struct('fig', f2, 'ef', ef, 'cb', cb, 'lbl', lbl, 'ut', ut);
        filterComments();
        if isempty(LE) || height(LE) == 0, lbl.Text = 'no log file'; end
    end

    function filterComments(q)
        % rows of LE matching the search text (all words, case-insensitive; text and code)
        if isempty(hCom) || ~isvalid(hCom.fig), return; end
        if nargin < 1, q = hCom.ef.Value; end
        comRow = [];
        if isempty(LE) || height(LE) == 0
            comView = []; hCom.ut.Data = cell(0, 7); return;
        end
        m = LE.isComment;
        if hCom.cb.Value, m = true(height(LE), 1); end
        words = strsplit(lower(strtrim(char(q))));
        words = words(~cellfun(@isempty, words));
        if ~isempty(words)
            hay = lower(strcat(LE.text, {' '}, LE.code));
            for k = 1:numel(words), m = m & contains(hay, words{k}); end
        end
        comView = find(m);
        hrs = H.totalSeconds >= 3600;
        num = cumsum(LE.isComment);                    %number of the comment (force plot)
        D = cell(numel(comView), 7);
        for k = 1:numel(comView)
            j = comView(k);
            nk = ''; if LE.isComment(j), nk = sprintf('%d', num(j)); end
            D(k,:) = {nk, char(LE.clockTime(j)), fmtClock(LE.t_file(j), hrs, true), round(LE.t_file(j) * 10) / 10, ...
                LE.channel(j), LE.code{j}, LE.text{j}};
        end
        hCom.ut.Data = D;
        if hCom.cb.Value, what = 'entries'; else, what = 'comments'; end
        hCom.lbl.Text = sprintf('%d of %d %s', numel(comView), nnz(LE.isComment | hCom.cb.Value), what);
    end

    function selectRow(evt)
        % a row of the comment window: its line in the force plot is marked (if it is in the loaded window)
        if isempty(evt.Indices), comRow = []; return; end
        comRow = evt.Indices(1,1);
        if isempty(comView) || comRow > numel(comView) || isempty(S), return; end
        t = LE.t_file(comView(comRow));
        tw = f2w(t);
        if tw >= S.fromSeconds && tw <= S.toSeconds, hiT = t; plotMain(false); end
    end

    function dblClickRow(evt)
        try r = evt.InteractionInformation.Row; catch, r = []; end
        if isempty(r), return; end
        gotoRow(r(1));
    end

    function gotoRow(r)
        if nargin < 1                                      %Go to button: current selection of the table
            r = comRow;
            try
                if isempty(r) && isprop(hCom.ut, 'Selection') && ~isempty(hCom.ut.Selection), r = hCom.ut.Selection(1,1); end
            catch
            end
        end
        if isempty(r) || isempty(comView) || r > numel(comView)
            if ~isempty(hCom) && isvalid(hCom.fig), hCom.lbl.Text = 'select a row first'; end
            return;
        end
        j = comView(r);
        t = LE.t_file(j);
        if isnan(t) || t < 0 || t > H.totalSeconds
            status(sprintf('"%s" (%.1f s) is outside the recording (0 - %.0f s).', LE.text{j}, t, H.totalSeconds)); return;
        end
        len = 60;
        if ~isempty(S), len = S.toSeconds - S.fromSeconds; end
        len = min(max(len, 30), 3600);
        from = max(0, t - 0.2 * len); to = min(H.totalSeconds, from + len);
        hiT = t;
        hFrom.String = sprintf('%.1f', from); hTo.String = sprintf('%.1f', to);
        onLoad();
        figure(fig);
        status(sprintf('Comment %s (%.1f s in the file): %s', char(LE.clockTime(j)), t, LE.text{j}));
    end

    function startDrag(ax, x)
        dragX0 = x;
        yl = ylim(ax);
        hoverHide();
        if ishandle(hDrag), delete(hDrag); end
        hDrag = patch(ax, [x x x x], yl([1 1 2 2]), uiBlue, 'FaceAlpha', 0.22, 'EdgeColor', uiBlue, 'HitTest', 'off');
        set(fig, 'WindowButtonMotionFcn', @(~,~) dragMove(ax), 'WindowButtonUpFcn', @(~,~) dragEnd(ax));
    end

    function dragMove(ax)
        x = clampX(ax);
        if ishandle(hDrag), hDrag.XData = [dragX0 x x dragX0]; end
    end

    function startDragY(ax)
        % EP plots: drag up / down = band of the new y limits (2026-10-09)
        dragY0 = clampY(ax);
        xl = xlim(ax);
        hoverHide();
        if ishandle(hDrag), delete(hDrag); end
        hDrag = patch(ax, xl([1 2 2 1]), dragY0 * [1 1 1 1], uiBlue, 'FaceAlpha', 0.22, 'EdgeColor', uiBlue, ...
            'HitTest', 'off', 'YLimInclude', 'off');
        set(fig, 'WindowButtonMotionFcn', @(~,~) dragMoveY(ax), 'WindowButtonUpFcn', @(~,~) dragEndY(ax));
    end

    function dragMoveY(ax)
        y = clampY(ax);
        if ishandle(hDrag), hDrag.YData = [dragY0 dragY0 y y]; end
    end

    function dragEndY(ax)
        set(fig, 'WindowButtonMotionFcn', @onMouseMove, 'WindowButtonUpFcn', '');
        y = clampY(ax);
        if ishandle(hDrag), delete(hDrag); end
        yl = ylim(ax);
        if abs(y - dragY0) < 0.01 * diff(yl), return; end       %a click, not a drag
        epSetYLim(1 + (ax == axEPs), sort([dragY0 y]));
    end

    function y = clampY(ax)
        cp = get(ax, 'CurrentPoint');
        yl = ylim(ax);
        y = min(max(cp(1,2), yl(1)), yl(2));
    end

    function dragEnd(ax)
        set(fig, 'WindowButtonMotionFcn', @onMouseMove, 'WindowButtonUpFcn', '');
        x = clampX(ax);
        if ishandle(hDrag), delete(hDrag); end
        xl = xlim(ax);
        if abs(x - dragX0) < 0.003 * diff(xl), return; end      %a click, not a drag
        r = sort([dragX0 x]);
        if ax == axMain
            if dragAdd && all(isfinite(range(:))), range = mergeRanges([range; r]); else, range = r; end
            dragAdd = false;
            refresh(false);
        else
            hFrom.String = sprintf('%.1f', r(1)); hTo.String = sprintf('%.1f', r(2));
            onLoad();
        end
    end

    function toggleContraction(x)
        if isempty(B), return; end
        xl = xlim(axMain);
        [d, k] = min(abs(B.t_peak - x));
        if isempty(d) || d > max(0.15, 0.01 * diff(xl)), return; end
        tk = B.t_peak(k);
        hit = abs(manualOff - tk) < 1e-6;
        if any(hit), manualOff(hit) = []; else, manualOff(end+1,1) = tk; end
        refresh(false);
    end

    function tf = inAxes(ax)
        cp = get(ax, 'CurrentPoint');
        xl = xlim(ax); yl = ylim(ax);
        tf = cp(1,1) >= xl(1) && cp(1,1) <= xl(2) && cp(1,2) >= yl(1) && cp(1,2) <= yl(2);
    end

    function x = clampX(ax)
        cp = get(ax, 'CurrentPoint');
        xl = xlim(ax);
        x = min(max(cp(1,1), xl(1)), xl(2));
    end

    % ---------------------------------------------------------------- mouse pointer: values of all plots at its time (2026-10-09)
    function onMouseMove(~, ~)
        % pointer over the force, stimulus, parameter or EP plots (not the overview): vertical line, marker on the curve
        % and value in every plot at the time of the pointer; time (and time since the last stimulus) in the plot under it
        if isempty(S) || isempty(C) || ~isvalid(fig), return; end
        axH = [];
        for a = hoverList()
            if inAxes(a), axH = a; break; end
        end
        if isempty(axH), hoverHide(); return; end
        cp = get(axH, 'CurrentPoint');
        hoverAt(cp(1, 1), axH);
    end

    function L = hoverList()
        % plots with a marker of the mouse pointer: force, stimuli, parameter (, EP signal, EP stimulation)
        L = [axMain axStim axPar];
        if epFrac > 0 && ~isempty(EP) && ~isempty(axEPv) && isvalid(axEPv), L = [L axEPv axEPs]; end
    end

    function Hv = hoverAt(x, axH)
        % markers and values at time x (s); axH = plot under the pointer (its text starts with the time)
        Hv = hoverValues(x, axH);
        L = hoverList();
        hvShown = true;
        for q = 1:numel(L)
            a = L(q);
            h = hoverObj(a);
            xl = xlim(a); yl = ylim(a);
            set(h.line, 'XData', [x x], 'YData', yl, 'Visible', 'on');
            in = ~isnan(Hv(q).y) && Hv(q).x >= xl(1) && Hv(q).x <= xl(2);
            if in
                set(h.dot, 'XData', Hv(q).x, 'YData', Hv(q).y, 'Visible', 'on');
            else
                set(h.dot, 'Visible', 'off');
            end
            str = Hv(q).text;                               %value: small, top left in the plot
            if a == axH, str = strtrim([Hv(1).time '     ' str]); end   %plot under the pointer: time first
            if isempty(str), set(h.text, 'Visible', 'off'); continue; end
            set(h.text, 'String', str, 'Visible', 'on');
        end
    end

    function Hv = hoverValues(x, axH)
        % values at time x: force and EP traces at x (sample nearest to x), stimulus pulse and contraction (parameter of
        % the lower plot) nearest to x. Hv: force, stimuli, parameter, signal, stimulation (x, y of the marker; NaN =
        % none; text); Hv(1).time: time of the pointer (time axis as shown) and time since the last stimulus
        Hv = struct('name', {'force', 'stimuli', 'parameter', 'signal', 'stimulation'}, 'x', nan, 'y', nan, ...
            'text', '', 'time', '');
        if ~isempty(hvF) && ~isempty(hvF.t)
            k = nearestSample(hvF.t, x);
            Hv(1).x = hvF.t(k); Hv(1).y = hvF.y(k);
            Hv(1).text = sprintf('%s %sN', fmtNum(Hv(1).y, 4), mu);
        end
        if ~isempty(comT)                                   %comment line under the pointer (2026-10-14)
            [d, q] = min(abs(comT - x));
            if d <= 0.006 * diff(xlim(axMain))
                Hv(1).text = sprintf('%s     comment %d: %s', Hv(1).text, comK(q), LE.text{comIdx(q)});
            end
        end
        if ~isempty(hvS) && ~isempty(hvS.t)
            [~, j] = min(abs(hvS.t - x));
            Hv(2).x = hvS.t(j); Hv(2).y = hvS.cur(j);
            if C.stimChannel == 0, tx = 'ext. trigger'; else, tx = sprintf('%g mA', hvS.cur(j)); end
            if ~isnan(hvS.iv(j)), tx = sprintf('%s, interval %.0f ms', tx, hvS.iv(j)); end
            if hvS.ok(j) == 0, tx = [tx ', current not reached']; end
            Hv(2).text = tx;
        end
        if ~isempty(B) && height(B) > 0
            kp = hPar.Value;
            if ismember(plotList{kp,1}, B.Properties.VariableNames)
                [~, j] = min(abs(B.t_peak - x));
                vp = B.(plotList{kp,1});
                Hv(3).x = B.t_peak(j); Hv(3).y = double(vp(j));
                Hv(3).text = sprintf('%s %s %s', plotList{kp,1}, fmtNum(Hv(3).y, 4), strrep(plotList{kp,2}, 'u', mu));
            end
        end
        if epFrac > 0 && ~isempty(EP)
            k = round((x - EP.t0) / EP.dt) + 1;
            if k >= 1 && k <= numel(EP.V)
                rep = false;
                if epClean && ~isempty(epVc), yv = epVc(k); rep = epArtMask(k); else, yv = EP.V(k); end
                Hv(4).x = EP.t0 + (k - 1) * EP.dt; Hv(4).y = double(yv);
                Hv(4).text = sprintf('%s %s', fmtNum(Hv(4).y, 4), EP.unitV);
                if rep, Hv(4).text = [Hv(4).text ' (artefact removed)']; end
                Hv(5).x = Hv(4).x; Hv(5).y = double(EP.stim(k));
                Hv(5).text = sprintf('%s %s', fmtNum(Hv(5).y, 4), EP.unitStim);
            end
        end
        tz = 0; tMax = H.totalSeconds;
        if relTime, tz = S.fromSeconds; tMax = S.toSeconds - tz; end
        dec = 3; if diff(xlim(axMain)) < 1, dec = 4; end
        xf = w2f(x);                                     %side-by-side rocker stops: time in the file
        if isnan(xf), Hv(1).time = 't = (gap between rocker stops)';
        else, Hv(1).time = sprintf('t = %s (%.*f s)', fmtClock(xf - tz, tMax >= 3600, true, dec), dec, xf - tz); end
        st = C.stimTimes(:);                                 %EP plots: stimuli of the EP recording (its time base)
        if (isequal(axH, axEPv) || isequal(axH, axEPs)) && ~isempty(EP) && ~isempty(EP.stimTimes), st = EP.stimTimes(:); end
        j = find(st <= x, 1, 'last');
        if ~isempty(j) && x - st(j) < 10, Hv(1).time = sprintf('%s, stimulus %+.1f ms', Hv(1).time, 1000 * (x - st(j))); end
        [Hv.time] = deal(Hv(1).time);
    end

    function h = hoverObj(a)
        % line, marker and text of the mouse pointer in the axes a (cla deletes them: created again)
        h = getappdata(a, 'mdaHover');
        if ~isempty(h)
            hh = [h.line h.dot h.text];
            if all(isgraphics(hh)), return; end
            delete(hh(isgraphics(hh)));
        end
        if a == axStim, yyaxis(axStim, 'left'); end         %current (left axis)
        nh = {'HitTest', 'off', 'PickableParts', 'none', 'Tag', 'mdaHover'};
        h = struct();
        h.line = line(a, [nan nan], [nan nan], 'Color', [0.3 0.3 0.3], 'LineStyle', '--', 'LineWidth', 0.5, ...
            'XLimInclude', 'off', 'YLimInclude', 'off', nh{:});
        h.dot = line(a, nan, nan, 'LineStyle', 'none', 'Marker', 'o', 'MarkerSize', 7, 'MarkerEdgeColor', [0 0 0], ...
            'MarkerFaceColor', [1 0.8 0], 'XLimInclude', 'off', 'YLimInclude', 'off', nh{:});
        h.text = text(a, 0.004, 0.985, '', 'Units', 'normalized', 'FontSize', 8, 'Color', [0.1 0.1 0.1], ...
            'Margin', 1, 'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
            'Interpreter', 'none', 'Visible', 'off', nh{:});     %fixed position: top left corner of the plot, no box
        setappdata(a, 'mdaHover', h);
    end

    function hoverHide()
        if ~hvShown, return; end
        hvShown = false;
        for a = [axMain axStim axPar axEPv axEPs]
            if ~isvalid(a), continue; end
            h = getappdata(a, 'mdaHover');
            if isempty(h), continue; end
            hh = [h.line h.dot h.text];
            set(hh(isgraphics(hh)), 'Visible', 'off');
        end
    end

    function Hv = apiHover(t, where)
        % scripts / tests: mouse pointer at time t over the plot 'force', 'stimuli', 'parameter', 'signal' or
        % 'stimulation' (EP); '' = pointer outside the plots (markers hidden)
        if isempty(where), hoverHide(); Hv = []; return; end
        L = hoverList();
        q = find(strcmpi({'force', 'stimuli', 'parameter', 'signal', 'stimulation'}, where), 1);
        if isempty(q) || q > numel(L) || isempty(S), error('MyoDishAnalysisGUI: no plot ''%s'' for the mouse pointer.', where); end
        Hv = hoverAt(t, L(q));
    end


% =====================================================================================================
% analysis and display
% =====================================================================================================
    function analyze(resetX)
        status('Detecting contractions ...'); drawnow;
        rfMsg = '';
        try
            optsC = opts;
            optsC.zeroForce = zeroUser(ch);                 %NaN = Offset of the log file
            optsC.threshold = thrOf(ch);
            Sa = S;
            if opts.rockerFilter && isempty(sbs)
                [Sa, rfMsg] = rockerFiltered(optsC);
            elseif opts.rockerFilter
                rfMsg = 'Rocker filter: not used for the rocker stops side by side (rocker at rest).';
            end
            [B, C] = mda_analyzeChannel(Sa, ch, [], optsC);
            [B, C] = cutJunctions(B, C);
            epMarks = [];
            if ~isempty(EP) && height(B) > 0                %AP parameters of every contraction (EP recording)
                try
                    [Aap, epMarks] = mda_analyzeAP(EP, B);
                    B = [B, Aap];
                catch MEap
                    rfMsg = strtrim([rfMsg ' AP analysis: ' MEap.message]);
                end
            end
        catch ME
            B = []; C = []; cla(axMain); cla(axPar); plotStim(); updateSummary();
            status(['Error: ' ME.message]);
            if ~isempty(getenv('MDA_DEBUG')), disp(getReport(ME, 'extended')); end   %setenv('MDA_DEBUG', '1')
            return;
        end
        if strcmp(C.thresholdMode, 'auto'), hThr.String = sprintf('%.0f', C.threshold); end
        if isnan(C.zeroForce), hZero.String = ''; else, hZero.String = sprintf('%.0f', C.zeroForce); end
        hZeroSrc.String = C.zeroSource;
        refresh(resetX);
        if ~isempty(hRef) && isvalid(hRef.fig), drawReference(); end
        msg = sprintf('Channel %d: %d contractions detected (threshold %.0f %sN, %s).', ch, height(B), C.threshold, mu, C.thresholdMode);
        if any(B.uncertain), msg = sprintf('%s %d uncertain (orange).', msg, nnz(B.uncertain)); end
        if isfield(C, 'noContractions') && C.noContractions
            lvl = '';
            if ~isnan(C.noiseLevel), lvl = sprintf(' (level before the stimuli %.0f %sN)', C.noiseLevel, mu); end
            msg = sprintf(['Channel %d: no contractions - only peaks of the rocker movement / noise%s, not locked to ' ...
                'the stimuli (slice not beating?).'], ch, lvl);
        elseif isfield(C, 'thresholdArtifacts') && C.thresholdArtifacts > 0
            msg = sprintf('%s %d peaks of the rocker movement not counted (not locked to the stimuli).', msg, C.thresholdArtifacts);
        end
        if ~isempty(rfMsg), msg = [msg ' ' rfMsg]; end
        if ~isempty(resInfo), msg = [resInfo ' ' msg]; end
        status(msg);
    end

    function [Sa, msg] = rockerFiltered(optsC, chX)
        % S with the rocker artifact of channel chX (default: the current channel) subtracted; estimated with +-60 s
        % context (windows < 10 min), cached per channel and detection options
        if nargin < 2, chX = ch; end
        Sa = S; msg = '';
        if ~any(S.rockerOn)
            msg = 'Rocker filter: the rocker does not move in this window.'; return;
        end
        row = find(S.dataChannels == chX, 1);
        key = [sprintf('%d|', chX) jsonencode(rmfield(optsC, {'zeroForce', 'rocker', 'beats', 'referenceBeat', 'detection'}))];
        hit = numel(rfCache) >= chX && ~isempty(rfCache{chX}) && strcmp(rfCache{chX}.key, key);
        if ~hit
            status('Rocker filter: estimating the rocker artifact ...'); drawnow;
            if isempty(rfCtx)
                if S.toSeconds - S.fromSeconds < 600
                    rfCtx = mda_readMdd(H.file, max(0, S.fromSeconds - 60), min(H.totalSeconds, S.toSeconds + 60), opts);
                else
                    rfCtx = S;
                end
            end
            S1 = struct('t', S.t, 'force', S.force(row, :), 'dataChannels', chX, 'rockerOn', S.rockerOn, 'dt', S.dt);
            if isempty(optsC.rockerFrequency) && ~isempty(rfF0), optsC.rockerFrequency = rfF0; end   %same for all channels
            [S1, R] = mda_rockerFilter(S1, chX, optsC, rfCtx);
            if isempty(rfF0) && ~isempty(R.f0table), rfF0 = R.f0table; end
            rfCache{chX} = struct('key', key, 'art', S1.rockerArtifact, 'R', R);
        end
        E = rfCache{chX};
        Sa.rockerArtifact = zeros(size(S.force));
        Sa.rockerFiltered = false(1, numel(S.dataChannels));
        Sa.rockerFilterInfo = cell(1, numel(S.dataChannels));
        Sa.force(row, :) = S.force(row, :) - E.art;
        Sa.rockerArtifact(row, :) = E.art;
        Sa.rockerFiltered(row) = true;
        Sa.rockerFilterInfo{row} = E.R;
        msg = regexprep(E.R.message, '^Rocker filter, channel \d+: ', 'Rocker filter: ');
    end

    function sel = selected()
        inR = inRng(B.t_peak);
        sel = B.included & inR & ~isManual();
        if refExclude, sel = sel & ~deviating(); end
    end

    function d = deviating()
        d = deviatingOf(B, C);
    end

    function d = deviatingOf(Bx, Cx)
        % contractions that deviate from the reference beat by more than refThr SD (false without reference)
        d = false(height(Bx), 1);
        if isempty(Cx) || ~isfield(Cx, 'referenceBeat') || isempty(Cx.referenceBeat), return; end
        a = Bx.refMaxDeviation_SD > refThr; nrm = Bx.refMaxDeviationNorm_SD > refThr;   %NaN --> false
        switch refWhich
            case 1, d = a;
            case 2, d = nrm;
            otherwise, d = a | nrm;
        end
    end

    function m = isManual()
        m = false(height(B), 1);
        for k = 1:numel(manualOff), m = m | abs(B.t_peak - manualOff(k)) < 1e-6; end
    end

    function T = rangeTable(forExport)
        % contractions of the analysed range(s); forExport: times in the file (side-by-side rocker stops) and with
        % several ranges the column 'range' (number of the range, 2026-10-14)
        if nargin < 1, forExport = false; end
        inR = inRng(B.t_peak);
        man = isManual();
        T = B(inR, :);
        T.included = T.included & ~man(inR);
        T.manuallyExcluded = man(inR);
        T.contraction = (1:height(T))';
        if forExport
            T = fileTimes(T);
            if size(range, 1) > 1
                T = addvars(T, rangeOf(B.t_peak(inR)), 'After', 'channel', 'NewVariableNames', 'range');
            end
        end
        if ~isnan(H.recordingStart) && height(T) > 0
            clockTime = datetime(H.recordingStart + T.t_peak / 86400, 'ConvertFrom', 'datenum', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
            T = addvars(T, clockTime, 'After', 't_peak');
        end
        [~, n, e] = fileparts(H.file);
        T = addvars(T, repmat({[n e]}, height(T), 1), 'Before', 1, 'NewVariableNames', 'file');
        if ismember('clockTime', T.Properties.VariableNames)
            T = mda_addLabels(T, Lbl, T.clockTime);
        else
            T = mda_addLabels(T, Lbl);
        end
    end

    function Sm = summaryAll()
        % summary for exports: one row; several ranges: 'all ranges' and one row per range (column range); times in the
        % file (2026-10-14)
        Sm = summaryRow();
        if size(range, 1) > 1
            P = cell(size(range, 1), 1);
            for r = 1:size(range, 1), P{r} = summaryRow(range(r, :)); end
            Sm = [Sm; vertcat(P{:})];
            lb = [{'all ranges'}; arrayfun(@(r) sprintf('range%d', r), (1:size(range, 1))', 'UniformOutput', false)];
            Sm = addvars(Sm, lb, 'After', 'file', 'NewVariableNames', 'range');
        end
        Sm = fileTimes(Sm);
    end

    function Sm = summaryRow(R)
        % summary of the selected contractions over the analysed range(s) (all together), or over the ranges R
        if nargin < 1, R = range; end
        Bs = B;
        Bs.included = selected();
        Sm = mda_summarize(Bs, C, R, opts);
        ap = ismember(C.channel, opts.arrhythmicChannels) || (opts.arrhythmicDetection && Sm.pacedSeconds > 0 && ...
            Sm.arrhythmicFraction > opts.arrhythmicMinFraction);   %as MyoDishAnalysis (2026-10-13)
        Sm = addvars(Sm, ap, 'After', 'pacedSeconds', 'NewVariableNames', 'arrhythmicPacing');
        [~, n, e] = fileparts(H.file);
        Sm = addvars(Sm, {[n e]}, 'Before', 1, 'NewVariableNames', 'file');
        if ~isnan(H.recordingStart)
            Sm = mda_addLabels(Sm, Lbl, datetime(H.recordingStart + mean(w2f([Sm.from Sm.to]), 'omitnan') / 86400, 'ConvertFrom', 'datenum'));
        else
            Sm = mda_addLabels(Sm, Lbl);
        end
    end

    % ---------------------------------------------------------------- several analysed ranges, rocker stops side by side (2026-10-14)
    function tf = inRng(t, R)
        % t within one of the analysed ranges (rows [from to] of range, or of R)
        if nargin < 2, R = range; end
        tf = false(size(t));
        for r = 1:size(R, 1), tf = tf | (t >= R(r,1) & t <= R(r,2)); end
    end

    function k = rangeOf(t)
        % number of the analysed range of each time t (0 = none)
        k = zeros(size(t));
        for r = size(range, 1):-1:1, k(t >= range(r,1) & t <= range(r,2)) = r; end
    end

    function sp = rngSpan()
        % first start and last end of the analysed range(s)
        sp = [min(range(:,1)) max(range(:,2))];
    end

    function txt = rangeText()
        % analysed range(s) as text (times in the file)
        hrs = ~isempty(H) && H.totalSeconds >= 3600;
        tot = sum(diff(range, 1, 2));
        if size(range, 1) == 1 && isempty(sbs)
            txt = sprintf('Range %.2f - %.2f s (%.1f s)', range(1), range(2), diff(range));
        else
            f = w2f(range);
            txt = sprintf('%d ranges, %.1f s in total (%s - %s)', size(range, 1), tot, fmtClock(f(1,1), hrs, true), ...
                fmtClock(f(end,2), hrs, true));
            if ~isempty(sbs), txt = sprintf('%s; %d rocker stops side by side', txt, size(sbs.seg, 1)); end
        end
    end

    function t = w2f(t)
        % time in the loaded window --> time in the file (side-by-side rocker stops: NaN in the gaps between them)
        if isempty(sbs), return; end
        t2 = nan(size(t));
        for k = 1:size(sbs.seg, 1)
            in = t >= sbs.seg(k,3) - 1e-9 & t <= sbs.seg(k,4) + 1e-9;
            t2(in) = t(in) - sbs.shift(k);
        end
        t = t2;
    end

    function t = f2w(t)
        % time in the file --> time in the loaded window (side-by-side rocker stops: NaN outside the loaded stops)
        if isempty(sbs), return; end
        t2 = nan(size(t));
        for k = 1:size(sbs.seg, 1)
            in = t >= sbs.seg(k,1) - 1e-9 & t <= sbs.seg(k,2) + 1e-9;
            t2(in) = t(in) + sbs.shift(k);
        end
        t = t2;
    end

    function k = segOf(t)
        % rocker stop (segment) of window times t (NaN in the gaps)
        k = nan(size(t));
        if isempty(sbs), k(:) = 1; return; end
        for j = 1:size(sbs.seg, 1), k(t >= sbs.seg(j,3) - 1e-9 & t <= sbs.seg(j,4) + 1e-9) = j; end
    end

    function T = fileTimes(T)
        % side-by-side rocker stops: time columns of a contraction or pulse table --> time in the file
        if isempty(sbs) || isempty(T) || height(T) == 0, return; end
        for nm = {'t_peak', 't_stim', 't_onset', 't_rise50', 't', 'from', 'to'}
            if ismember(nm{1}, T.Properties.VariableNames) && isnumeric(T.(nm{1})), T.(nm{1}) = w2f(T.(nm{1})); end
        end
        if ismember('pulse', T.Properties.VariableNames) && ismember('t', T.Properties.VariableNames)
            T.pulse = round(T.t * H.samplingRate);            %sample number in the file
        end
    end

    function [Bx, Cx] = cutJunctions(Bx, Cx)
        % side-by-side rocker stops: intervals to the previous contraction / stimulus across a gap are not intervals
        if isempty(sbs) || isempty(Bx), return; end
        sp = segOf(Bx.t_peak);
        if ismember('peakToPeakInterval', Bx.Properties.VariableNames)
            bad = segOf(Bx.t_peak - Bx.peakToPeakInterval) ~= sp;
            Bx.peakToPeakInterval(bad) = nan; Bx.peakToPeakFrequency(bad) = nan;
        end
        if ismember('stimInterval', Bx.Properties.VariableNames)
            bad = segOf(Bx.t_stim - Bx.stimInterval) ~= segOf(Bx.t_stim);
            Bx.stimInterval(bad) = nan;
            if ismember('stimFrequency', Bx.Properties.VariableNames), Bx.stimFrequency(bad) = nan; end
        end
        if isfield(Cx, 'stimInterval') && numel(Cx.stimInterval) == numel(Cx.stimTimes)
            st = Cx.stimTimes(:); iv = Cx.stimInterval(:);
            bad = segOf(st - iv) ~= segOf(st);
            iv(bad) = nan; Cx.stimInterval = reshape(iv, size(Cx.stimInterval));
        end
        if isfield(Cx, 'pulses') && istable(Cx.pulses) && height(Cx.pulses) > 0
            P = Cx.pulses;
            for nm = {'couplingInterval_s', 'sinceOnset_s'}
                if ismember(nm{1}, P.Properties.VariableNames)
                    bad = segOf(P.t - P.(nm{1})) ~= segOf(P.t);
                    P.(nm{1})(bad) = nan;
                end
            end
            Cx.pulses = P;
        end
    end

    function zoomToSelection()
        % context menu of the force plot: time axis = the analysed range(s)
        if isempty(S) || any(~isfinite(range(:))), status('Select a range first.'); return; end
        sp = rngSpan(); m = max(0.02 * diff(sp), 0.2);
        xlim(axMain, [max(S.fromSeconds, sp(1) - m), min(S.toSeconds, sp(2) + m)]);
    end

    function selectAll()
        % context menu of the overview: load the range shown (whole file or the zoomed part), at most 4 h
        if isempty(H), return; end
        if isempty(O) || isempty(ovXL), w = [0 H.totalSeconds]; else, w = ovXL; end
        if diff(w) > 4 * 3600
            status(sprintf(['The range shown is %s long: at most 4 h can be loaded. Zoom the overview (mouse wheel) or ' ...
                'use Trend ... / the command line version for long ranges.'], fmtDuration(diff(w))));
            return;
        end
        hFrom.String = sprintf('%.3f', w(1)); hTo.String = sprintf('%.3f', w(2));
        onLoad();
    end

    function selectRockerStops()
        % context menu of the force plot ('only contractions with rocker at rest'): all rocker stops of the range shown in
        % the overview are read (each +-2 s) and shown side by side, separated by dashed lines; analysed ranges = the
        % stops (2026-10-14)
        if isempty(H), return; end
        if ~hRocker.Value, status('Tick ''only contractions with rocker at rest'' first.'); return; end
        if isempty(O), onOverview(); if isempty(O), return; end, end
        if ~isfield(O, 'rockerRest')
            status('Overview without rocker intervals: press Overview again.'); return;
        end
        if isempty(ovXL), xr = [0 H.totalSeconds]; else, xr = ovXL; end
        I = O.rockerRest;
        I = I(I(:,2) > xr(1) & I(:,1) < xr(2), :);
        I = [max(I(:,1), xr(1)), min(I(:,2), xr(2))];
        I = I(I(:,2) - I(:,1) >= 1, :);                   %stops of at least 1 s
        if isempty(I), status('No rocker stop (>= 1 s) in the range shown in the overview.'); return; end
        if size(I, 1) == 1 && I(1,2) - I(1,1) > 0.98 * diff(xr)
            status('The rocker does not move in the range shown in the overview: load it as a window instead.'); return;
        end
        pad = 2;
        segs = [max(0, I(:,1) - pad), min(H.totalSeconds, I(:,2) + pad)];
        segs = mergeRanges(segs);
        if sum(diff(segs, 1, 2)) > 4 * 3600
            status('The rocker stops of this range take more than 4 h: zoom the overview.'); return;
        end
        if size(segs, 1) > 2000, status(sprintf('%d rocker stops: zoom the overview (at most 2000).', size(segs, 1))); return; end
        if loadSegments(segs), range = mergeRanges(f2w(I)); range = range(all(isfinite(range), 2), :); analyze(true); plotOverview(); end
    end

    function ok = loadSegments(segs)
        % read the windows segs (rows [from to] s in the file) and show them side by side (sbs)
        ok = false;
        if ~isempty(EP), EP = []; epMarks = []; showEP(false); status('EP recording removed (not shown with rocker stops side by side).'); end
        wb = [];
        if size(segs, 1) > 20, wb = waitbar(0, sprintf('Reading %d rocker stops ...', size(segs, 1)), 'Name', 'Rocker stops'); end
        Ss = cell(size(segs, 1), 1);
        try
            for k = 1:size(segs, 1)
                Ss{k} = mda_readMdd(H, segs(k,1), segs(k,2), opts);
                if ~isempty(wb) && mod(k, 10) == 0 && ishandle(wb), waitbar(k / size(segs, 1), wb); end
            end
        catch ME
            if ishandle(wb), close(wb); end
            status(['Error: ' ME.message]); return;
        end
        if ishandle(wb), close(wb); end
        [S, sbs] = sideBySide(Ss, 1);
        rfCtx = []; rfCache = {}; rfF0 = []; resOnly = []; manualOff = zeros(0,1);
        winReq = [segs(1,1) segs(end,2)];
        hFrom.String = sprintf('%.1f', winReq(1)); hTo.String = sprintf('%.1f', winReq(2));
        channelLabels();
        ok = true;
    end

    function channelLabels()
        % channel list with the signal range of the loaded window (helps to find the channels with a slice)
        lbl = cell(1, numel(S.dataChannels));
        for k = 1:numel(S.dataChannels)
            x = S.force(k, :);
            if isfield(S, 'gapMask') && numel(S.gapMask) == numel(x), x = x(~S.gapMask); end
            x = sort(x);
            r = x(max(1, round(0.995 * numel(x)))) - x(max(1, round(0.005 * numel(x))));
            lbl{k} = sprintf('Ch %d  (%.0f %sN)', S.dataChannels(k), r, mu);
        end
        hCh.String = lbl;
    end

    function refresh(resetX)
        plotMain(resetX);
        plotStim();
        plotParam();
        updateSummary();
        drawEP();
        fitMargins();
    end

    function plotMain(resetX)
        xlOld = xlim(axMain);
        cla(axMain); hold(axMain, 'on');
        legend(axMain, 'off');
        hvF = [];
        if isempty(C), return; end
        % force - zero force (easier to read); sensor signal if the zero force is unknown
        z0 = mda_zeroForce(S, ch, zeroUser(ch), C.t);
        hasZero = ~any(isnan(z0));
        if hasZero, fy = C.f - z0; else, fy = C.f; end
        if ~isempty(sbs) && isfield(S, 'gapMask') && numel(S.gapMask) == numel(fy), fy(S.gapMask) = nan; end   %between rocker stops
        hvF = struct('t', C.t(:), 'y', double(fy(:)));      %values at the mouse pointer
        showRaw = ~isempty(C.rockerArtifact) && any(C.rockerArtifact ~= 0);   %rocker filter: signal before
        if showRaw, fRaw = fy + C.rockerArtifact; else, fRaw = fy; end
        yl = [min([fy fRaw]) max([fy fRaw])];
        if any(~isfinite(yl)), yl = [0 1]; end
        yl = yl + [-0.08 0.08] * max(1, diff(yl));
        [tCm, ~] = commentsInWindow();
        if ~isempty(tCm)
            yl(2) = yl(2) + 0.08 * diff(yl);               %room for the numbered comment marks above the data (2026-10-14)
        end
        yl(2) = yl(2) + 0.035 * diff(yl);                  %room for the rocker bar at the top (2026-10-14)
        barH = 0.025 * diff(yl);
        % analysed range(s) (one face per range)
        R = range(all(isfinite(range), 2), :);
        if ~isempty(R)
            patch(axMain, R(:, [1 2 2 1])', repmat(yl([1 1 2 2])', 1, size(R, 1)), [1 0.96 0.75], 'EdgeColor', [0.85 0.7 0.2], 'HitTest', 'off');
        end
        % rocker state: thin bar at the top, green = at rest, grey = moving (2026-10-14; before: grey background)
        rockerBar(axMain, S.t, S.rockerOn, yl(2) - barH, yl(2));
        if showRaw, plot(axMain, C.t, fRaw, 'Color', [0.72 0.72 0.72], 'LineWidth', 0.5, 'HitTest', 'off'); end
        plot(axMain, C.t, fy, 'k', 'LineWidth', 0.5, 'HitTest', 'off');
        breakLines(axMain, yl);                            %side-by-side rocker stops: dashed lines between them
        % stimuli
        st = C.stimTimes(C.stimTimes >= S.fromSeconds & C.stimTimes <= S.toSeconds);
        if ~isempty(st)
            xs = [st st nan(size(st))]'; ys = repmat([yl(1); yl(1) + 0.04 * diff(yl); nan], 1, numel(st));
            plot(axMain, xs(:), ys(:), 'Color', uiBlue, 'HitTest', 'off');
        end
        hasX = false;                                   %extra pulses (status channel bit 16; 2026-10-10): green
        if isfield(C, 'extraTimes') && ~isempty(C.extraTimes)
            xt = C.extraTimes(C.extraTimes >= S.fromSeconds & C.extraTimes <= S.toSeconds); xt = xt(:);
            hasX = ~isempty(xt);
            if hasX
                xs = [xt xt nan(size(xt))]'; ys = repmat([yl(1); yl(1) + 0.06 * diff(yl); nan], 1, numel(xt));
                plot(axMain, xs(:), ys(:), 'Color', [0 0.6 0], 'LineWidth', 1.2, 'HitTest', 'off');
            end
        end
        hasAmb = false; hasDv = false; hasEx = false; hasRes = false; hasCom = false;
        % contractions
        if ~isempty(B)
            [~, loc] = ismember(B.t_peak, C.peakTimes);
            y = fy(C.iPeaks(loc)); y = y(:);
            inR = inRng(B.t_peak);
            man = isManual();
            unc = B.included & inR & ~man & B.uncertain;    %uncertain (high sensitivity): orange
            sel = B.included & inR & ~man & ~B.uncertain;
            filt = inR & ~B.included & ~man;
            plot(axMain, B.t_peak(~inR), y(~inR), '.', 'Color', [0.6 0.6 0.6], 'HitTest', 'off');
            plot(axMain, B.t_peak(filt), y(filt), 'v', 'Color', [0.5 0.5 0.5], 'MarkerSize', 6, 'HitTest', 'off');
            plot(axMain, B.t_peak(man & inR), y(man & inR), 'kx', 'MarkerSize', 10, 'LineWidth', 1.5, 'HitTest', 'off');
            plot(axMain, B.t_peak(sel), y(sel), 'v', 'Color', [0.85 0 0], 'MarkerFaceColor', [0.85 0 0], 'MarkerSize', 6, 'HitTest', 'off');
            plot(axMain, B.t_peak(unc), y(unc), 'v', 'Color', [1 0.55 0], 'MarkerFaceColor', [1 0.55 0], 'MarkerSize', 6, 'HitTest', 'off');
            dv = deviating() & inR;                     %deviating from the reference beat: magenta circles
            hasDv = any(dv);
            if hasDv
                plot(axMain, B.t_peak(dv), y(dv), 'o', 'Color', [0.9 0 0.9], 'MarkerSize', 11, 'LineWidth', 1.5, 'HitTest', 'off');
            end
            if ismember('elicitedByExtraPulse', B.Properties.VariableNames)   %2026-10-10
                ex = inR & B.elicitedByExtraPulse;      %elicited by an extra pulse: green rings
                hasEx = any(ex);
                if hasEx
                    plot(axMain, B.t_peak(ex), y(ex), 'o', 'Color', [0 0.6 0], 'MarkerSize', 13, 'LineWidth', 1.5, 'HitTest', 'off');
                end
                am = inR & B.stimAmbiguous;             %ambiguous stimulus assignment: black diamonds
                hasAmb = any(am);
                if hasAmb
                    plot(axMain, B.t_peak(am), y(am), 'd', 'Color', [0 0 0], 'MarkerSize', 12, 'LineWidth', 0.8, 'HitTest', 'off');
                end
            end
        end
        if ~isempty(resOnly)                            %opened results: contractions not detected again (black o)
            ro = resOnly(resOnly >= S.fromSeconds & resOnly <= S.toSeconds);
            hasRes = ~isempty(ro);
            plot(axMain, ro, interp1(C.t, fy, ro), 'ko', 'MarkerSize', 10, 'LineWidth', 1.2, 'HitTest', 'off');
        end
        % comments of the log file (purple dotted lines, the one selected / jumped to: solid): numbered markers at the
        % top, numbers as in the comment window; point at a line: its text (top left); click a marker: the comment
        % window shows it (2026-10-14)
        comT = []; comTF = []; comK = []; comIdx = []; comNumH = gobjects(0);
        if ~isempty(LE) && height(LE) > 0
            [tc, comK, cm] = commentsInWindow();         %window time (side by side: condensed), number, row of LE
            hasCom = ~isempty(cm);
            if ~isempty(cm)
                pu = [0.55 0 0.75];
                comT = tc; comTF = LE.t_file(cm); comIdx = cm;
                yT = yl(2) - barH;                          %below the rocker bar
                xs = [tc tc nan(size(tc))]'; ys = repmat([yl(1); yT; nan], 1, numel(tc));
                plot(axMain, xs(:), ys(:), ':', 'Color', pu, 'LineWidth', 1, 'HitTest', 'off');
                hi = abs(comTF - hiT) < 1e-6;
                if any(hi), plot(axMain, [tc(hi) tc(hi)]', repmat([yl(1); yT], 1, nnz(hi)), '-', 'Color', pu, 'LineWidth', 2, 'HitTest', 'off'); end
                yM = yT - 0.012 * diff(yl);
                plot(axMain, tc(~hi), yM * ones(nnz(~hi), 1), 'v', 'Color', pu, 'MarkerFaceColor', pu, 'MarkerSize', 7, ...
                    'LineStyle', 'none', 'HitTest', 'off', 'Tag', 'mdaComment');   %click: onMouseDown
                if any(hi)
                    plot(axMain, tc(hi), yM * ones(nnz(hi), 1), 'v', 'Color', [0.85 0 0], 'MarkerFaceColor', [0.85 0 0], ...
                        'MarkerSize', 7, 'LineStyle', 'none', 'HitTest', 'off', 'Tag', 'mdaComment');
                end
                comNumH = text(axMain, tc, repmat(yT - 0.035 * diff(yl), size(tc)), ...
                    arrayfun(@(k) sprintf('%d', k), comK, 'UniformOutput', false), 'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'top', 'FontSize', 8, 'Color', pu, 'Clipping', 'on', 'HitTest', 'off');
            end
        end
        ylim(axMain, yl);
        if resetX || any(xlOld < S.fromSeconds - 1) || any(xlOld > S.toSeconds + 1)
            xlim(axMain, [S.fromSeconds S.toSeconds]);
        else
            xlim(axMain, xlOld);
        end
        if hasZero
            ylabel(axMain, ['force - zero force (' mu 'N)']);
        else
            ylabel(axMain, {['force (' mu 'N, sensor signal)'], 'zero force unknown'});
        end
        if showLegend                                   %legend of the markers (2026-10-10)
            forceLegend(struct('dev', hasDv, 'ex', hasEx, 'amb', hasAmb, 'res', hasRes, 'x', hasX, 'com', hasCom, ...
                'raw', showRaw));
            ttl = sprintf('Channel %d', ch);
        else
            ttl = sprintf('Channel %d   (red = selected, orange = uncertain, grey = excluded by filter, x = excluded by you, blue = stimuli, bar at the top: green = rocker at rest, grey = moving, purple = comments)', ch);
            if showRaw, ttl = strrep(ttl, 'purple = comments)', 'purple = comments, light grey = before rocker filter)'); end
            if hasX, ttl = strrep(ttl, ')', ', green = extra pulses / elicited by one)'); end
            if hasAmb, ttl = strrep(ttl, ')', ', diamond = ambiguous stimulus)'); end
        end
        if ~isempty(sbs)
            ttl = sprintf('%s   -   %d rocker stops side by side (dashed lines: time gaps)', ttl, size(sbs.seg, 1));
        end
        title(axMain, ttl, 'FontWeight', 'normal', 'FontSize', 9);
    end

    function [tw, num, rows] = commentsInWindow()
        % comments of the log file in the loaded window: window time (side by side: condensed), number (1..n of the
        % file), row of LE
        tw = []; num = []; rows = [];
        if isempty(LE) || height(LE) == 0 || isempty(S), return; end
        cAll = find(LE.isComment);
        t = f2w(LE.t_file(cAll));
        inW = t >= S.fromSeconds & t <= S.toSeconds;     %(NaN: outside the rocker stops)
        tw = t(inW); num = find(inW); rows = cAll(inW);
    end

    function rockerBar(ax, t, on, y0, y1)
        % rocker state as a thin bar from y0 to y1: green = at rest, grey = moving; gaps between side-by-side rocker
        % stops left empty (2026-10-14)
        if isempty(t), return; end
        st = double(on(:)'); 
        if ~isempty(sbs) && isfield(S, 'gapMask') && numel(S.gapMask) == numel(st), st(S.gapMask) = nan; end
        cols = {[0.35 0.72 0.35], [0.62 0.62 0.62]};    %at rest, moving
        dt2 = 0; if numel(t) > 1, dt2 = (t(2) - t(1)) / 2; end
        for v = 0:1
            m = st == v;
            d = diff([false m false]);
            a = find(d == 1); b = find(d == -1) - 1;
            if isempty(a), continue; end
            xa = t(a) - dt2; xb = t(b) + dt2;
            patch(ax, [xa; xb; xb; xa], repmat([y0; y0; y1; y1], 1, numel(a)), cols{v + 1}, 'EdgeColor', 'none', ...
                'HitTest', 'off', 'Tag', 'mdaRockerBar');
        end
    end

    function breakLines(ax, yl)
        % side-by-side rocker stops: dashed vertical lines between them (x-axis breaks)
        if isempty(sbs) || isempty(sbs.breaks), return; end
        if nargin < 2, yl = ylim(ax); end
        x = sbs.breaks(:);
        xs = [x x nan(size(x))]'; ys = repmat([yl(1); yl(2); nan], 1, numel(x));
        plot(ax, xs(:), ys(:), '--', 'Color', [0.3 0.3 0.3], 'LineWidth', 0.9, 'HitTest', 'off', 'Tag', 'mdaBreak');
    end

    function forceLegend(has)
        % legend of the markers of the force plot: objects without data (NaN), the order of the settings guide
        E = {
            'line', {'Marker', 'v', 'Color', [0.85 0 0], 'MarkerFaceColor', [0.85 0 0], 'MarkerSize', 6}, 'selected contraction', true;
            'line', {'Marker', 'v', 'Color', [1 0.55 0], 'MarkerFaceColor', [1 0.55 0], 'MarkerSize', 6}, 'uncertain (high sensitivity)', true;
            'line', {'Marker', 'v', 'Color', [0.5 0.5 0.5], 'MarkerSize', 6}, 'excluded by filter', true;
            'line', {'Marker', 'x', 'Color', [0 0 0], 'MarkerSize', 10, 'LineWidth', 1.5}, 'excluded by you', true;
            'line', {'Marker', '.', 'Color', [0.6 0.6 0.6]}, 'outside the analysed range', true;
            'line', {'Marker', 'o', 'Color', [0.9 0 0.9], 'MarkerSize', 11, 'LineWidth', 1.5}, 'deviating from the reference beat', has.dev;
            'line', {'Marker', 'o', 'Color', [0 0.6 0], 'MarkerSize', 13, 'LineWidth', 1.5}, 'elicited by an extra pulse', has.ex;
            'line', {'Marker', 'd', 'Color', [0 0 0], 'MarkerSize', 12, 'LineWidth', 0.8}, 'ambiguous stimulus assignment', has.amb;
            'line', {'Marker', 'o', 'Color', [0 0 0], 'MarkerSize', 10, 'LineWidth', 1.2}, 'only in the results file', has.res;
            'line', {'LineStyle', '-', 'Color', uiBlue}, 'stimulus pulse', true;
            'line', {'LineStyle', '-', 'Color', [0 0.6 0], 'LineWidth', 1.2}, 'extra pulse (status bit 16)', has.x;
            'patch', {[0.35 0.72 0.35], 'EdgeColor', 'none'}, 'rocker at rest (bar at the top)', true;
            'patch', {[0.62 0.62 0.62], 'EdgeColor', 'none'}, 'rocker moving (bar at the top)', true;
            'patch', {[1 0.96 0.75], 'EdgeColor', [0.85 0.7 0.2]}, 'analysed range', true;
            'line', {'LineStyle', ':', 'Color', [0.55 0 0.75]}, 'comment of the log file', has.com;
            'line', {'LineStyle', '-', 'Color', [0.72 0.72 0.72]}, 'before the rocker filter', has.raw};
        E = E([E{:, 4}], :);
        hl = gobjects(size(E, 1), 1);
        for k = 1:size(E, 1)
            if strcmp(E{k, 1}, 'patch')
                hl(k) = patch(axMain, nan(1, 3), nan(1, 3), E{k, 2}{:}, 'HitTest', 'off', 'Tag', 'mdaLegendItem');
            else
                hl(k) = line(axMain, nan, nan, 'LineStyle', 'none', E{k, 2}{:}, 'HitTest', 'off', 'Tag', 'mdaLegendItem');
            end
        end
        try
            lg = legend(axMain, hl, E(:, 3), 'Location', 'northeast', 'FontSize', 7, 'AutoUpdate', 'off', ...
                'Interpreter', 'none', 'Tag', 'mdaForceLegend');
            try lg.NumColumns = 2; catch, end            %R2018a+
            lg.ItemHitFcn = [];
        catch
        end
    end

    function lg = apiLegend(tf)
        % tests / scripts: legend of the force plot on / off (no input: the legend object, [] if none)
        if nargin > 0 && logical(tf) ~= showLegend, toggleLegend(); end
        lg = findobj(fig, 'Type', 'Legend', 'Tag', 'mdaForceLegend');
    end

    function toggleReport()
        % menu Save / Export: analysis report (PDF) with 'All channels -> file' (2026-10-11)
        reportAll = ~reportAll;
        if reportAll, hRepMenu.Checked = 'on'; else, hRepMenu.Checked = 'off'; end
    end

    function toggleLegend()
        showLegend = ~showLegend;
        if showLegend, hLegMenu.Checked = 'on'; else, hLegMenu.Checked = 'off'; legend(axMain, 'off'); end
        if ~isempty(C), plotMain(false); end
    end

    function plotParam()
        cla(axPar); hold(axPar, 'on');
        if isempty(B), return; end
        k = hPar.Value;
        if ~ismember(plotList{k,1}, B.Properties.VariableNames)     %relative parameter without reference beat / AP without EP
            why = 'no reference beat (right click in the force plot)';
            if ismember(plotList{k,1}, APP(:,1)), why = 'no EP recording (+ EP recording ...)'; end
            title(axPar, sprintf('%s: %s', plotList{k,1}, why), 'Interpreter', 'none', ...
                'FontWeight', 'normal', 'FontSize', 9);
            mainTicks(); xlim(axPar, xlim(axMain)); return;
        end
        title(axPar, '');
        v = B.(plotList{k,1});
        sel = selected();
        plot(axPar, B.t_peak(~sel), v(~sel), '.', 'Color', [0.7 0.7 0.7], 'MarkerSize', 8);
        plot(axPar, B.t_peak(sel & ~B.uncertain), v(sel & ~B.uncertain), '.', 'Color', [0.85 0 0], 'MarkerSize', 12);
        plot(axPar, B.t_peak(sel & B.uncertain), v(sel & B.uncertain), '.', 'Color', [1 0.55 0], 'MarkerSize', 12);
        if any(sel)                                        %mean of the selected contractions over the analysed range
            xm = [range(:, 1:2) nan(size(range, 1), 1)]'; %(one line per range)
            plot(axPar, xm(:), mean(v(sel), 'omitnan') * ones(numel(xm), 1), '--', 'Color', [0.85 0 0], 'LineWidth', 1, 'HitTest', 'off');
        end
        if endsWith(plotList{k,1}, '_pctRef'), yline(axPar, 100, ':', 'HitTest', 'off'); end   %reference = 100 %
        if endsWith(plotList{k,1}, '_dRef'), yline(axPar, 0, ':', 'HitTest', 'off'); end
        breakLines(axPar);
        unit = strrep(plotList{k,2}, 'u', mu);
        ylabel(axPar, sprintf('%s (%s)', plotList{k,1}, unit), 'Interpreter', 'none');
        mainTicks();
        xlim(axPar, xlim(axMain));
        grid(axPar, 'on');
        linkaxes([axMain axStim axPar], 'x');
    end

    function updateSummary()
        if isempty(B)
            hTable.Data = {}; hCounts.String = ''; hFlags.String = ''; return;
        end
        Sm = summaryRow();
        sel = selected();                                  %median of the selected contractions (2026-10-21)
        d = cell(size(PI, 1), 6);
        for k = 1:size(PI, 1)
            d(k,:) = {PI{k,1}, fmtNum(Sm.([PI{k,1} '_mean']), 4), fmtNum(selMedian(PI{k,1}, sel), 4), ...
                fmtNum(Sm.([PI{k,1} '_SD']), 3), Sm.([PI{k,1} '_n']), strrep(PI{k,2}, 'u', mu)};
        end
        if ismember('APD90', B.Properties.VariableNames)  %AP parameters (EP recording)
            for k = 1:size(APP, 1)
                d(end+1,:) = {APP{k,1}, fmtNum(Sm.([APP{k,1} '_mean']), 4), fmtNum(selMedian(APP{k,1}, sel), 4), ...
                    fmtNum(Sm.([APP{k,1} '_SD']), 3), Sm.([APP{k,1} '_n']), APP{k,2}}; %#ok<AGROW>
            end
        end
        % whole range, independent of the rocker / stimulated filters: n = detected contractions / stimuli
        d(end+1,:) = {'extra beats', sprintf('%d', Sm.nExtraBeats), '', '', Sm.nDetected, 'count'};
        d(end+1,:) = {'extra beats', fmtNum(Sm.extraBeats_percent, 3), '', '', Sm.nDetected, '%'};
        d(end+1,:) = {'missed beats', sprintf('%d', Sm.nMissedBeats), '', '', Sm.nStimuli, 'count'};
        d(end+1,:) = {'missed beats', fmtNum(Sm.missedBeats_percent, 3), '', '', Sm.nStimuli, '%'};
        if ismember('nMissedDuringContraction', Sm.Properties.VariableNames)   %2026-10-10
            d(end+1,:) = {'missed in a contraction', sprintf('%d', Sm.nMissedDuringContraction), '', '', Sm.nStimuli, 'count'};
            if Sm.nExtraPulses > 0
                d(end+1,:) = {'extra pulses', sprintf('%d', Sm.nExtraPulses), '', '', [], 'count'};
                d(end+1,:) = {'elicited by extra pulse', sprintf('%d', Sm.nElicitedByExtraPulse), '', '', Sm.nStimulated, 'count'};
            end
            d(end+1,:) = {'ambiguous stimulus', sprintf('%d', Sm.nAmbiguous), '', '', Sm.nStimulated, 'count'};
        end
        d(end+1,:) = {'uncertain (all)', sprintf('%d', Sm.nUncertain), '', '', Sm.nDetected, 'count'};
        d(end+1,:) = {'uncertain stimulated', sprintf('%d', Sm.nStimulatedUncertain), '', '', Sm.nStimulated, 'count'};
        d(end+1,:) = {'uncertain extra', sprintf('%d', Sm.nExtraBeatsUncertain), '', '', Sm.nExtraBeats, 'count'};
        d(end+1,:) = {'uncertain missed', sprintf('%d', Sm.nMissedBeatsUncertain), '', '', Sm.nStimuli, 'count'};
        if isfield(C, 'referenceBeat') && ~isempty(C.referenceBeat)    %deviating from the reference beat (whole range)
            inR = inRng(B.t_peak);
            nCmp = sum(inR & ~isnan(B.refMaxDeviation_SD)); nDev = sum(inR & deviating());
            pDev = nan; if nCmp > 0, pDev = 100 * nDev / nCmp; end
            d(end+1,:) = {sprintf('deviating (> %g SD)', refThr), sprintf('%d', nDev), '', '', nCmp, 'count'};
            d(end+1,:) = {sprintf('deviating (> %g SD)', refThr), fmtNum(pDev, 3), '', '', nCmp, '%'};
        end
        % 2026-10-06: column '% ref' (mean relative to the reference contractions; diastolic: difference) if the channel has
        % a reference beat
        hasRef = isfield(C, 'referenceBeat') && ~isempty(C.referenceBeat);
        if hasRef
            rc = repmat({''}, size(d, 1), 1);
            for k = 1:size(PI, 1), rc{k} = relCell(Sm, PI{k,1}); end
            d = [d(:,1:2), rc, d(:,3:end)];
            cn = {'parameter', 'mean', '%ref', 'median', 'SD', 'n', 'unit'}; cw = {84, 48, 42, 48, 46, 26, 40};
        else
            cn = {'parameter', 'mean', 'median', 'SD', 'n', 'unit'}; cw = {96, 58, 58, 52, 32, 40};
        end
        if numel(hTable.ColumnName) ~= numel(cn)        %column count changes: new table (the header is not redrawn reliably)
            pT = hTable.Position; delete(hTable);
            hTable = uitable(pnl, 'Units', 'normalized', 'Position', pT, 'RowName', [], 'ColumnName', cn, 'ColumnWidth', cw, 'FontSize', 9);
        end
        hTable.ColumnWidth = cw;
        hTable.Data = d;
        if C.stimChannel == 0, sSrc = ' (ext. trigger)'; else, sSrc = ''; end
        txt = sprintf(['%s\n%d of %d contractions selected (%d stimulated, %d extra)\n' ...
            '%d stimuli%s (%.2f Hz), %d without contraction\n%s'], rangeText(), Sm.nContractions, Sm.nDetected, ...
            Sm.nStimulated, Sm.nExtraBeats, Sm.nStimuli, sSrc, Sm.stimFrequency, Sm.nMissedBeats, labelLine(Sm));
        %(the String of a text control reads back as a padded char matrix: append before assigning, not to hCounts.String)
        if ismember('nExtraPulses', Sm.Properties.VariableNames) && (Sm.nExtraPulses > 0 || Sm.nAmbiguous > 0)
            xp = '';
            if Sm.nExtraPulses > 0, xp = sprintf('%d extra pulses (%d elicited a contraction), ', Sm.nExtraPulses, Sm.nElicitedByExtraPulse); end
            txt = sprintf('%s\n%s%d ambiguous stimulus assignments, missed in a contraction: %d', txt, xp, ...
                Sm.nAmbiguous, Sm.nMissedDuringContraction);
        end
        if ~isempty(C.rockerFilter), txt = sprintf('%s\n%s', txt, rockerLine(C.rockerFilter)); end
        if isfield(C, 'referenceBeat') && ~isempty(C.referenceBeat)
            w = {'abs.', 'norm.', 'abs. or norm.'};
            txt = sprintf('%s\nreference (%d, %s): deviating > %g SD (%s)%s', txt, C.referenceBeat.n, ...
                C.referenceBeat.align, refThr, w{refWhich}, repmat(', excl.', 1, refExclude));
        end
        hCounts.String = txt;
        showFlags(Sm);
    end

    function showFlags(Sm)
        % flags of the analysis report for the analysed range of this channel (as in the watcher report; 2026-10-14):
        % red = check the analysis, orange = slice quality, grey = none / too few contractions; descriptions as tooltip
        hFlags.String = ''; hFlags.TooltipString = '';
        try
            fl = mda_report('defaults');
            Tc = rangeTable();
            if ~ismember('channel', Tc.Properties.VariableNames), Tc.channel = repmat(ch, height(Tc), 1); end
            if ~ismember('channel', Sm.Properties.VariableNames), Sm.channel = ch; end
            R = mda_report('flags', Sm, Tc, [], fl, LE);
            R = R(R.channel == ch, :);
            if isempty(R), return; end
            switch R.level{1}
                case 'check', col = [0.75 0 0];
                case 'quality', col = [0.75 0.42 0];
                otherwise, col = [0.45 0.45 0.45];
            end
            if isempty(R.flags{1})
                if R.nDetected(1) < fl.minBeats, txt = sprintf('Flags: - (fewer than %d contractions)', fl.minBeats);
                else, txt = 'Flags: none'; end
            else
                txt = sprintf('Flags %s: %s', R.flags{1}, strjoin([R.red(~cellfun(@isempty, R.red)) ...
                    R.yellow(~cellfun(@isempty, R.yellow))], '; '));
            end
            hFlags.String = txt; hFlags.ForegroundColor = col;
            hFlags.TooltipString = sprintf(['flags of the analysis report for this range (watcher report, mda_report):\n' ...
                'red: check the analysis (I inverted signal, N noise, S large extra beats, D delay, F stimulus frequency, R controller restart suspected)\n' ...
                'orange: slice quality (C capture, X extra beats, A amplitude, T amplitude change, V amplitude CV)\n%s'], txt);
        catch
        end
    end

    function m = selMedian(p, sel)
        % median of parameter p over the selected contractions (column 'median' of the summary table, 2026-10-21; the
        % mean, SD and n come from mda_summarize)
        m = nan;
        if ismember(p, B.Properties.VariableNames), m = median(B.(p)(sel), 'omitnan'); end
    end

    function c = relCell(Sm, p)
        % mean of the selection relative to the reference: % of the reference, diastolic: difference (uN)
        c = '';
        if ismember([p '_pctRef_mean'], Sm.Properties.VariableNames)
            v = Sm.([p '_pctRef_mean']);
            if ~isnan(v), c = sprintf('%.1f', v); end
        elseif ismember([p '_dRef_mean'], Sm.Properties.VariableNames)
            v = Sm.([p '_dRef_mean']);
            if ~isnan(v), c = sprintf('%s%+.0f', char(916), v); end
        end
    end

    % ---------------------------------------------------------------- reference beat
    function setReference()
        if isempty(B), status('Load a time window first.'); return; end
        rows = find(B.included & inRng(B.t_peak) & ~isManual());   %selection (without the deviation filter)
        try
            R = mda_referenceBeat('create', C, B, rows, refAlign);   %(no stimulated contractions: upstroke)
        catch ME
            status(['Reference: ' ME.message]); return;
        end
        [~, n, e] = fileparts(H.file);
        R.source = sprintf('%s%s, channel %d, %s', n, e, ch, R.source);
        refs = opts.referenceBeat;
        if ~isempty(refs), refs = refs([refs.channel] ~= ch); end
        if isempty(refs), opts.referenceBeat = R; else, opts.referenceBeat = [refs(:); R]; end
        analyze(false);
        status(sprintf('Reference beat of channel %d: mean of %d contractions, aligned at the %s. Deviations: table, lower plot (ref...Deviation...), magenta circles.', ...
            ch, R.n, alignText(R.align)));
        showReference();
    end

    function clearReference()
        refs = opts.referenceBeat;
        if ~isempty(refs), refs = refs([refs.channel] ~= ch); end
        if isempty(refs), opts.referenceBeat = []; else, opts.referenceBeat = refs; end
        if ~isempty(S), analyze(false); end
        if ~isempty(hRef) && isvalid(hRef.fig), drawReference(); end
        status(sprintf('Reference beat of channel %d removed.', ch));
    end

    function R = currentReference()
        R = [];
        refs = opts.referenceBeat;
        if ~isempty(refs), R = refs([refs.channel] == ch); end
        if numel(R) > 1, R = R(1); end
    end

    function showReference()
        if ~isempty(hRef) && isvalid(hRef.fig), figure(hRef.fig); drawReference(); return; end
        f3 = figure('Name', 'MyoDishAnalysis: reference beat', 'NumberTitle', 'off', 'Color', 'w', 'Units', 'pixels', ...
            'Position', [160 120 1150 560], 'DeleteFcn', @(~,~) clearRefHandle());
        lightTheme(f3);
        d = {'Units', 'normalized', 'FontSize', 10, 'BackgroundColor', 'w'};
        a1 = axes(f3, 'Position', [0.06 0.12 0.33 0.78]); a2 = axes(f3, 'Position', [0.45 0.12 0.33 0.78]);
        x0 = 0.81; w = 0.18;
        uicontrol(f3, d{:}, 'Style', 'text', 'String', 'deviating if more than', 'HorizontalAlignment', 'left', 'Position', [x0 0.88 w 0.04]);
        eX = uicontrol(f3, d{:}, 'Style', 'edit', 'String', num2str(refThr), 'Position', [x0 0.83 0.06 0.045], 'Callback', @(~,~) refSettings());
        uicontrol(f3, d{:}, 'Style', 'text', 'String', 'SD of the reference', 'HorizontalAlignment', 'left', 'Position', [x0+0.065 0.825 0.12 0.045]);
        pW = uicontrol(f3, d{:}, 'Style', 'popupmenu', 'String', {'absolute (incl. amplitude)', 'normalized (shape)', 'absolute or normalized'}, ...
            'Value', refWhich, 'Position', [x0 0.77 w 0.045], 'Callback', @(~,~) refSettings());
        cX = uicontrol(f3, d{:}, 'Style', 'checkbox', 'String', 'exclude from the selection', 'Value', refExclude, ...
            'Position', [x0 0.71 w 0.045], 'Callback', @(~,~) refSettings());
        cD = uicontrol(f3, d{:}, 'Style', 'checkbox', 'String', 'show deviating contractions', 'Value', 1, ...
            'Position', [x0 0.66 w 0.045], 'Callback', @(~,~) drawReference());
        uicontrol(f3, d{:}, 'Style', 'text', 'String', 'aligned at', 'HorizontalAlignment', 'left', 'Position', [x0 0.6 0.06 0.04]);
        pA = uicontrol(f3, d{:}, 'Style', 'popupmenu', 'String', {'stimulus', '50 % upstroke'}, ...
            'Value', 1 + strcmp(refAlign, 'upstroke'), 'Position', [x0+0.055 0.605 w-0.055 0.045], 'Callback', @(~,~) refSettings(), ...
            'TooltipString', ['stimulus: a changed stimulus-to-contraction latency counts as deviation (contractions without stimulus: ' ...
            'aligned at the 50 % upstroke). 50 % upstroke: shape only.']);
        uicontrol(f3, d{:}, 'Style', 'pushbutton', 'String', 'Save reference ...', 'Position', [x0 0.525 w 0.06], 'Callback', @(~,~) saveReference());
        uicontrol(f3, d{:}, 'Style', 'pushbutton', 'String', 'Load reference ...', 'Position', [x0 0.455 w 0.06], 'Callback', @(~,~) loadReference(), ...
            'TooltipString', 'reference saved before (e.g. baseline of the same slice); used for the current channel');
        uicontrol(f3, d{:}, 'Style', 'pushbutton', 'String', 'Remove reference', 'Position', [x0 0.385 w 0.06], 'Callback', @(~,~) clearReference());
        tx = uicontrol(f3, d{:}, 'Style', 'text', 'String', '', 'HorizontalAlignment', 'left', 'Position', [x0 0.01 w 0.36], 'FontSize', 8);
        hRef = struct('fig', f3, 'a1', a1, 'a2', a2, 'eX', eX, 'pW', pW, 'cX', cX, 'cD', cD, 'pA', pA, 'tx', tx);
        drawReference();
    end

    function clearRefHandle()
        hRef = [];
    end

    function refSettings()
        v = str2double(hRef.eX.String);
        if isnan(v) || v <= 0, hRef.eX.String = num2str(refThr); else, refThr = v; end
        refWhich = hRef.pW.Value; refExclude = logical(hRef.cX.Value);
        al = {'stimulus', 'upstroke'}; al = al{hRef.pA.Value};
        R = currentReference();
        if ~isempty(R) && ~strcmp(R.align, al)        %switch the alignment of the reference of this channel
            try
                R = mda_referenceBeat('align', R, al);
            catch ME
                status(ME.message); hRef.pA.Value = 1 + strcmp(R.align, 'upstroke'); return;
            end
            refAlign = al;
            refs = opts.referenceBeat;
            refs([refs.channel] == ch) = R;
            opts.referenceBeat = refs;
            if ~isempty(S), analyze(false); end
            status(sprintf('Reference beat of channel %d: aligned at the %s.', ch, alignText(al)));
        else
            refAlign = al;
            if ~isempty(B), refresh(false); end
        end
        drawReference();
    end

    function s = alignText(al)
        if strcmp(al, 'stimulus'), s = 'stimulus'; else, s = '50 % upstroke'; end
    end

    function drawReference()
        if isempty(hRef) || ~isvalid(hRef.fig), return; end
        R = currentReference();
        axs = [hRef.a1 hRef.a2];
        for q = 1:2, cla(axs(q)); hold(axs(q), 'on'); legend(axs(q), 'off'); end
        if isempty(R)
            title(hRef.a1, sprintf('channel %d: no reference beat (select contractions, right click in the force plot)', ch), 'FontWeight', 'normal', 'FontSize', 9);
            hRef.tx.String = ''; return;
        end
        hRef.pA.Value = 1 + strcmp(R.align, 'upstroke');
        tg = R.tGrid * 1000;
        M = {R.mean, R.meanNorm}; SD = {R.sd, R.sdNorm};
        ttl = {sprintf('reference, channel %d: mean %s SD (%sN)', ch, char(177), mu), 'normalized to amplitude 1 (shape)'};
        hp = gobjects(2, 2);
        for q = 1:2
            fill(axs(q), [tg; flipud(tg)], [M{q} - refThr * SD{q}; flipud(M{q} + refThr * SD{q})], [0.85 0.85 1], 'EdgeColor', 'none');
            hp(q,1) = fill(axs(q), [tg; flipud(tg)], [M{q} - SD{q}; flipud(M{q} + SD{q})], [0.6 0.6 0.95], 'EdgeColor', 'none');
            hp(q,2) = plot(axs(q), tg, M{q}, 'b', 'LineWidth', 2);
            title(axs(q), ttl{q}, 'FontWeight', 'normal', 'FontSize', 9);
            xlabel(axs(q), sprintf('time from the %s (ms)', alignText(R.align))); grid(axs(q), 'on');
        end
        ylabel(hRef.a1, ['developed force (' mu 'N)']); ylabel(hRef.a2, 'force / amplitude');
        nDev = 0; nCmp = 0;
        if ~isempty(B) && isfield(C, 'referenceBeat') && ~isempty(C.referenceBeat)
            inR = inRng(B.t_peak);
            dv = find(deviating() & inR);
            nDev = numel(dv); nCmp = sum(inR & ~isnan(B.refMaxDeviation_SD));
            if hRef.cD.Value && ~isempty(dv)
                dv = dv(1:min(end, 40));
                Y = mda_referenceBeat('traces', C, B, R, dv);
                for k = 1:numel(dv)
                    plot(hRef.a1, tg, Y(:,k), '-', 'Color', [0.9 0 0.9 0.6], 'LineWidth', 0.8);
                    plot(hRef.a2, tg, Y(:,k) / B.amplitude(dv(k)), '-', 'Color', [0.9 0 0.9 0.6], 'LineWidth', 0.8);
                end
            end
        end
        legend(hRef.a1, hp(1,:), {sprintf('%s 1 SD (light: %s %g SD)', char(177), char(177), refThr), 'mean'}, 'Location', 'northeast', 'FontSize', 8);
        w = {'absolute', 'normalized', 'absolute or normalized'};
        hRef.tx.String = {R.source, sprintf('created %s; aligned at the %s (%d contractions)', R.created, alignText(R.align), R.n), ...
            sprintf('amplitude of the mean %.0f %sN', R.amp, mu), ...
            sprintf('loaded range: %d of %d compared contractions deviate by > %g SD (%s, maximum); magenta = deviating (at most 40 shown)', ...
            nDev, nCmp, refThr, w{refWhich}), ...
            ['Parameters (tables, lower plot, trend): refCorrelation (1 = same shape), refRMSDeviation_SD (overall), ' ...
            'refMaxDeviation_SD (largest local deviation), ...Norm: amplitude 1.']};
    end

    function saveReference()
        R = currentReference();
        if isempty(R), status('No reference beat for this channel.'); return; end
        [p, n] = fileparts(H.file);
        if isempty(lastDir), lastDir = p; end
        [fn, pn] = uiputfile('*.mat', 'Save reference beat', fullfile(lastDir, sprintf('%s_ch%d_referenceBeat.mat', n, ch)));
        if isequal(fn, 0), return; end
        lastDir = pn;
        referenceBeat = R;
        save(fullfile(pn, fn), 'referenceBeat');
        status(['Reference beat saved: ' fullfile(pn, fn)]);
    end

    function loadReference()
        p = lastDir; if isempty(p), p = fileparts(H.file); end
        [fn, pn] = uigetfile('*.mat', 'Load reference beat', [p filesep]);
        if isequal(fn, 0), return; end
        try
            L = load(fullfile(pn, fn), 'referenceBeat'); R = L.referenceBeat;
            if ~isfield(R, 'tGrid') || ~isfield(R, 'sdNorm'), error('no reference beat in this file'); end
            R = mda_referenceBeat('align', R(1), '');    %standard fields (also references of an older version)
        catch ME
            status(['Load reference: ' ME.message]); return;
        end
        lastDir = pn;
        R.channel = ch;                                %used for the current channel
        refs = opts.referenceBeat;
        if ~isempty(refs), refs = refs([refs.channel] ~= ch); end
        if isempty(refs), opts.referenceBeat = R; else, opts.referenceBeat = [refs(:); R]; end
        if ~isempty(S), analyze(false); end
        drawReference();
        msg = sprintf('Reference beat loaded for channel %d (%s).', ch, R.source);
        if isempty(R.params), msg = [msg ' Saved before 2026-10-06: no parameter values, columns ..._pctRef are NaN - create it again.']; end
        status(msg);
    end

    function s = rockerLine(R)
        % one line about the rocker filter for the info text
        switch R.status
            case 'corrected'
                s = sprintf('rocker filter: %.0f %sN p-p removed (%.3f Hz)', R.artifactPP, mu, R.f0);
            case 'partly corrected'
                s = sprintf('rocker filter: %.0f %sN p-p removed in %.0f %% of rocker time', R.artifactPP, mu, 100 * R.correctedFraction);
            otherwise
                s = ['rocker filter: ' R.status];
        end
    end

    function plotStim()
        % stimulus pulses of the stimulus channel of the current channel: current (left, mA) and interval to the
        % previous pulse (right, ms), as drawStimPulses ('displayCurrents', 'displayIntervals')
        delete(hStimTxt(isgraphics(hStimTxt))); hStimTxt = gobjects(0);
        drawStim(axStim);
        hvS = [];
        if isempty(C) || isempty(S), return; end
        [tS, cur, ok, ~, iv] = stimData();
        hvS = struct('t', tS, 'cur', cur, 'iv', iv, 'ok', ok);   %values at the mouse pointer
        xlim(axStim, xlim(axMain));
        hStimTxt = stimText(axStim);
    end

    function drawStim(axT)
        yyaxis(axT, 'right'); cla(axT); ylabel(axT, '');
        yyaxis(axT, 'left'); cla(axT); hold(axT, 'on'); ylabel(axT, '');
        axT.YAxis(1).Color = [0.85 0 0]; axT.YAxis(2).Color = uiBlue;
        title(axT, '');
        if isempty(C) || isempty(S), return; end
        [tS, cur, ok, ex, iv] = stimData();
        isExt = C.stimChannel == 0;                         %external trigger pulses: bars of height 1, no current
        if isempty(tS)
            if isExt, msg = 'no external trigger pulses'; else, msg = sprintf('no stimulus pulses on channel %d', C.stimChannel); end
            title(axT, msg, 'FontWeight', 'normal', 'FontSize', 8);
            return;
        end
        for k = 1:2
            if k == 1, m = ~ex; col = [0.85 0 0]; else, m = ex; col = [0 0.6 0]; end
            if ~any(m), continue; end
            xs = [tS(m) tS(m) nan(nnz(m),1)]'; ys = [zeros(nnz(m),1) cur(m) nan(nnz(m),1)]';
            plot(axT, xs(:), ys(:), '-', 'Color', col, 'HitTest', 'off');
        end
        nr = ok == 0;                                      %current not reached (NaN: unknown)
        if any(nr), plot(axT, tS(nr), cur(nr), 'x', 'Color', [0.8 0 0.8], 'MarkerSize', 5, 'HitTest', 'off'); end
        ylim(axT, [0 max(1, max(cur)) * 1.35]);
        breakLines(axT, [0 max(1, max(cur)) * 1.35]);
        if isExt, ylabel(axT, 'ext.'); set(axT, 'YTick', []); else, ylabel(axT, 'mA'); set(axT, 'YTickMode', 'auto'); end
        axT.YAxis(1).Exponent = 0;
        yyaxis(axT, 'right');
        plot(axT, tS, iv, '.', 'Color', uiBlue, 'MarkerSize', 9, 'HitTest', 'off');
        r = [min(iv) max(iv)];
        if all(isfinite(r)), ylim(axT, r + [-0.25 0.35] * max(diff(r), 0.2 * r(2) + 1)); end
        ylabel(axT, 'ms');
        axT.YAxis(2).Exponent = 0;
        yyaxis(axT, 'left');
        if isExt
            title(axT, 'external trigger pulses (external stimulator; red bars), interval to the previous pulse (blue, ms)', ...
                'FontWeight', 'normal', 'FontSize', 8);
        else
            title(axT, sprintf(['stimuli channel %d: current (red bars, mA; green = extra pulse, x = current not reached), ' ...
                'interval to the previous pulse (blue, ms)'], C.stimChannel), 'FontWeight', 'normal', 'FontSize', 8);
        end
    end

    function [tS, cur, ok, ex, iv] = stimData()
        % pulses of the stimulus channel of the current channel in the loaded window (sorted)
        J = find(S.stim.channel == C.stimChannel);
        [tS, o] = sort(S.stim.time(J)); J = J(o); tS = tS(:);
        cur = double(S.stim.current(J)); cur = cur(:);
        if C.stimChannel == 0, cur = ones(size(cur)); end   %external trigger pulses: no current
        ok = double(S.stim.currentReached(J)); ok = ok(:);   %1 / 0 / NaN = unknown (2026-10-20)
        ex = S.stim.isExtraPulse(J); ex = ex(:);
        iv = [nan; diff(tS)] * 1000;
        if ~isempty(sbs) && numel(tS) > 1                  %no interval across a gap between rocker stops
            sg = segOf(tS); iv([false; diff(sg) ~= 0 | isnan(sg(2:end))]) = nan;
        end
    end

    function stimLabels()
        delete(hStimTxt(isgraphics(hStimTxt))); hStimTxt = gobjects(0);
        if isempty(C) || isempty(S) || ~isvalid(axStim), return; end
        hStimTxt = stimText(axStim);
    end

    function h = stimText(axT)
        % numbers (current, interval) when 40 pulses or fewer are visible
        h = gobjects(0);
        [tS, cur, ok, ~, iv] = stimData();
        if isempty(tS), return; end
        xl = xlim(axT);
        v = find(tS >= xl(1) & tS <= xl(2));
        if isempty(v) || numel(v) > 40, return; end
        yyaxis(axT, 'left'); ylL = ylim(axT);
        lab = arrayfun(@(k) sprintf('%g', cur(k)), v, 'UniformOutput', false);
        if C.stimChannel == 0, lab(:) = {'ext'}; end
        lab(ok(v) == 0) = strcat(lab(ok(v) == 0), ' ?!');
        h = text(axT, tS(v), min(cur(v) + 0.04 * diff(ylL), ylL(2)), lab, 'Color', [0.85 0 0], ...
            'FontSize', 7, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'HitTest', 'off');
        w = v(~isnan(iv(v)));
        if ~isempty(w)
            yyaxis(axT, 'right');
            h2 = text(axT, tS(w), iv(w), arrayfun(@(k) sprintf('  %.0f', iv(k)), w, 'UniformOutput', false), ...
                'Color', uiBlue, 'FontSize', 7, 'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'HitTest', 'off');
            h = [h(:); h2(:)];
            yyaxis(axT, 'left');
        end
    end

    function plotOverview()
        cla(axOv); hold(axOv, 'on');
        if isempty(O)
            text(axOv, 0.5, 0.5, 'Overview: press ''Overview''', 'Units', 'normalized', 'HorizontalAlignment', 'center', 'Color', [0.5 0.5 0.5]);
            set(axOv, 'XTick', [], 'YTick', []);
            return;
        end
        if isempty(ovXL), xlv = [0 O.totalSeconds]; else, xlv = ovXL; end
        P = O;                                             %data of the plot: whole file or detail of the zoomed part
        if ~isempty(Od) && Od.range(1) <= xlv(1) + 1e-6 && Od.range(2) >= xlv(2) - 1e-6 && Od.binSeconds < O.binSeconds
            P = Od;
        end
        row = find(P.dataChannels == ch, 1);
        x = P.tBin; lo = P.minForce(row,:); hi = P.maxForce(row,:);
        zOv = mda_zeroForce(H, ch, zeroUser(ch), x);    %force - zero force, if known
        if ~any(isnan(zOv)), lo = lo - zOv; hi = hi - zOv; end
        ok = ~isnan(lo) & ~isnan(hi);
        x = x(ok); lo = lo(ok); hi = hi(ok); rf = P.rockerFraction(ok);
        vis = x >= xlv(1) - P.binSeconds & x <= xlv(2) + P.binSeconds;
        if ~any(vis), vis = true(size(x)); end
        if isempty(x), return; end
        yl = [min(lo(vis)) max(hi(vis))]; yl = yl + [-0.05 0.05] * max(1, diff(yl));
        rest = rf < 0.5;                                   %rocker at rest
        on = diff([false rest false]); s1 = find(on == 1); s2 = find(on == -1) - 1;
        if ~isempty(s1)
            hb = P.binSeconds / 2;
            patch(axOv, [x(s1)-hb; x(s2)+hb; x(s2)+hb; x(s1)-hb], repmat(yl([1 1 2 2])', 1, numel(s1)), [0.75 0.95 0.75], 'EdgeColor', 'none', 'HitTest', 'off');
        end
        patch(axOv, [x fliplr(x)], [hi fliplr(lo)], [0.2 0.2 0.2], 'EdgeColor', [0.2 0.2 0.2], 'HitTest', 'off');
        if ~isempty(S) && ~isempty(sbs)                     %side-by-side rocker stops: each loaded stop
            q = sbs.seg(:, 1:2);
            patch(axOv, q(:, [1 2 2 1])', repmat(yl([1 1 2 2])', 1, size(q, 1)), uiBlue, 'FaceAlpha', 0.35, 'EdgeColor', uiBlue, 'HitTest', 'off');
        elseif ~isempty(S)
            patch(axOv, [S.fromSeconds S.toSeconds S.toSeconds S.fromSeconds], yl([1 1 2 2]), uiBlue, 'FaceAlpha', 0.27, 'EdgeColor', uiBlue, 'HitTest', 'off');
        end
        if ~isempty(LE) && height(LE) > 0                  %comments: purple ticks at the top
            tc = LE.t_file(LE.isComment & LE.t_file >= 0 & LE.t_file <= O.totalSeconds);
            if ~isempty(tc)
                xs = [tc tc nan(size(tc))]'; ys = repmat([yl(2) - 0.3 * diff(yl); yl(2); nan], 1, numel(tc));
                plot(axOv, xs(:), ys(:), '-', 'Color', [0.55 0 0.75], 'LineWidth', 1, 'HitTest', 'off');
            end
        end
        xlim(axOv, xlv); ylim(axOv, yl);
        set(axOv, 'YTickMode', 'auto');
        unit = ovTicks();
        text(axOv, -0.03, -0.04, ['(' unit ')'], 'Units', 'normalized', 'HorizontalAlignment', 'right', ...
            'VerticalAlignment', 'top', 'FontSize', 9, 'Color', [0.35 0.35 0.35], 'HitTest', 'off', 'Tag', 'mdaOvUnit');
        if ~any(isnan(zOv)), zs = 'force - zero force'; else, zs = 'sensor signal'; end
        hrs = O.totalSeconds >= 3600;
        if isempty(ovXL)
            ws = sprintf('whole file (%s)', fmtClock(O.totalSeconds, hrs, true));
        else
            ws = sprintf('%s - %s of %s', fmtClock(xlv(1), hrs, true), fmtClock(xlv(2), hrs, true), fmtClock(O.totalSeconds, hrs, true));
        end
        title(axOv, sprintf('Channel %d, %s, time in %s, %s   (green = rocker at rest, blue = loaded window, purple = comments)', ...
            ch, ws, unit, zs), 'FontWeight', 'normal', 'FontSize', 9);
        fitMargins();
    end

    function onRelTime(~, ~)
        relTime = logical(hRel.Value);
        mainTicks();
    end

    function mainTicks()
        % time axis of the loaded window (force, stimulus and parameter plot): h:mm:ss / m:ss, step adapted to the zoom
        % level; with 'time axis: 0 = start of the loaded window' relative to S.fromSeconds (labels only)
        if isempty(S) || ~isvalid(axPar), return; end
        t0 = 0;
        if relTime, t0 = S.fromSeconds; end
        if relTime, tMax = S.toSeconds - t0; else, tMax = H.totalSeconds; end   %same format as the overview
        [tk, tl, unit] = timeTicks(xlim(axMain) - t0, tMax);
        tk = tk + t0;
        if ~isempty(sbs)                                   %side-by-side rocker stops: labels = time in the file
            tF = w2f(tk);
            [~, tl] = timeTicks([0 1], max(tMax, max(tF(isfinite(tF)) - t0)), tF - t0, diff(xlim(axMain)));
            tl(~isfinite(tF)) = {''};
        end
        set(axMain, 'XTick', tk); set(axStim, 'XTick', tk);
        set(axPar, 'XTick', tk, 'XTickLabel', tl);
        if relTime
            xl = sprintf('time from the start of the loaded window (%s; window starts at %.1f s in the file)', unit, S.fromSeconds);
        else
            xl = sprintf('time in file (%s)', unit);
        end
        xlabel(axPar, xl);
        comNumbers();
        if epFrac > 0 && isvalid(axEPs)                  %EP traces below: same ticks, labels at the bottom
            set(axEPv, 'XTick', tk, 'XTickLabel', {}); set(axEPs, 'XTick', tk, 'XTickLabel', tl);
            xlabel(axEPs, xl);
        end
    end

    function comNumbers()
        % numbers of the comments in the force plot: overlapping ones hidden (the selected one stays visible)
        if isempty(comNumH) || ~all(isgraphics(comNumH)), return; end
        set(axMain, 'Units', 'pixels'); w = axMain.Position(3); set(axMain, 'Units', 'normalized');
        xl = xlim(axMain);
        px = (comT - xl(1)) / diff(xl) * w;
        last = -inf;
        for q = 1:numel(comNumH)
            minDx = 6 * numel(sprintf('%d', comK(q))) + 4;
            sel = abs(comTF(q) - hiT) < 1e-6;
            vis = px(q) >= 0 && px(q) <= w && (px(q) - last >= minDx || sel);
            if vis, last = px(q); comNumH(q).Visible = 'on'; else, comNumH(q).Visible = 'off'; end
        end
    end

    function comMarkerClick(k)
        % comment number k (marker in the force plot): selected in the comment window (opened if needed) (2026-10-14)
        if isempty(LE), return; end
        cAll = find(LE.isComment);
        if k < 1 || k > numel(cAll), return; end
        j = cAll(k);
        hiT = LE.t_file(j);
        onComments();
        if ~isempty(hCom) && isvalid(hCom.fig)
            if ~ismember(j, comView), hCom.ef.Value = ''; filterComments(); end
            r = find(comView == j, 1);
            if ~isempty(r)
                comRow = r;
                try hCom.ut.Selection = r; catch, end
                try scroll(hCom.ut, 'row', r); catch, end
            end
        end
        plotMain(false);
        status(sprintf('Comment %d (%s, %.1f s in the file): %s', k, char(LE.clockTime(j)), LE.t_file(j), LE.text{j}));
    end

    function unit = ovTicks()
        % time axis of the overview as h:mm(:ss) or m:ss, tick step adapted to the zoom level
        unit = '';
        if isempty(O) || ~isvalid(axOv), return; end
        [tk, tl, unit] = timeTicks(xlim(axOv), O.totalSeconds);
        set(axOv, 'XTick', tk, 'XTickLabel', tl);
        hu = findobj(axOv, 'Tag', 'mdaOvUnit');            %time unit left of the time axis (2026-10-14)
        if ~isempty(hu), set(hu, 'String', ['(' unit ')']); end
    end

    function fitMargins()
        % left edge of the plots: room for the tick labels and y labels of all plots (with wide tick labels or the
        % two-line label 'zero force unknown' they were cut off at the figure edge) and for the time unit of the
        % overview; the right edge stays (2026-10-14)
        if ~isvalid(fig) || ~isvalid(axMain), return; end
        axs = [axOv axMain axStim axPar];
        if epFrac > 0 && ~isempty(axEPv) && isvalid(axEPv), axs = [axs axEPv axEPs]; end
        need = 0.05;
        try
            for a = axs
                ti = a.TightInset; need = max(need, ti(1) + 0.008);
            end
            hu = findobj(axOv, 'Tag', 'mdaOvUnit');
            if ~isempty(hu) && isgraphics(hu(1))
                e = hu(1).Extent;                           %axes-normalized: left edge negative
                need = max(need, -e(1) * axOv.Position(3) + 0.006);
            end
        catch
            return;
        end
        need = min(need, 0.15);
        if abs(axMain.Position(1) - need) < 0.002, return; end
        x1 = axMain.Position(1) + axMain.Position(3);       %right edge of the plots
        for a = axs
            p = a.Position; a.Position = [need p(2) x1 - need p(4)];
        end
        hNavL.Position(1) = need;
    end

    function emptyPlots()
        cla(axMain); legend(axMain, 'off'); cla(axPar); plotStim();
        if epFrac > 0, cla(axEPv); cla(axEPs); end
        hTable.Data = {}; hCounts.String = ''; hFlags.String = '';
        plotOverview();
        ylabel(axMain, ['force (' mu 'N)']); xlabel(axPar, 'time in file (s)');
    end

    % ---------------------------------------------------------------- EP recording (LabChart, e.g. sharp electrode; 2026-10-06)
    function onOpenEP(~, ~)
        % read an EP recording (LabChart .mat export), align it to the stimuli of the open .mdd file and show
        % voltage and stimulation below the plots (the window grows downwards)
        if isempty(H), status('Open the .mdd file first: the EP recording is aligned to its stimuli.'); return; end
        [epDir, epBase] = fileparts(H.file);           %default: LabChart export with the name of the .mdd file
        epDef = fullfile(epDir, [epBase '.mat']); if ~isfile(epDef), epDef = [epDir filesep]; end
        [fn, pn] = uigetfile({'*.mat', 'LabChart export (*.mat)'; '*.*', 'all files'}, 'EP recording (LabChart export)', epDef);
        if isequal(fn, 0), return; end
        openEP(fullfile(pn, fn));
    end

    function openEP(epFile)
        if isempty(epFile), onCloseEP(); return; end
        if isempty(H), status('Open the .mdd file first: the EP recording is aligned to its stimuli.'); return; end
        if ~isempty(sbs), status('EP recording: load a continuous window first (not with rocker stops side by side).'); return; end
        status('EP recording: reading and aligning the stimuli ...'); drawnow;
        try
            EPnew = mda_readEPRecording(epFile, H, opts, 'mddChannel', ch);
        catch ME
            status(['EP recording: ' ME.message]); return;
        end
        EP = EPnew;
        epVc = []; epArtMask = []; epYLim = {[], []};     %artefacts removed / y limits: for this recording
        showEP(true);
        tEP = [EP.t0, EP.t0 + (numel(EP.V) - 1) * EP.dt];
        if isempty(S) || S.t(end) < tEP(1) || S.t(1) > tEP(2)   %no window or no overlap: load the recording's time range
            hFrom.String = sprintf('%.0f', max(0, floor(tEP(1))));
            hTo.String = sprintf('%.0f', min(H.totalSeconds, ceil(tEP(2))));
            onLoad();
        else
            analyze(false);                             %AP parameters for the contractions of the window
        end
        msg = EP.message;
        if ~isempty(B) && ismember('AP_note', B.Properties.VariableNames)
            msg = sprintf('%s APD90: %d/%d contractions.', msg, sum(~isnan(B.APD90)), height(B));
        end
        status(msg);
    end

    function shown = drawAPMarks(xl)
        % AP markers of the contractions in the visible range (at most 60): artefact, upstroke, peak, APD points
        shown = false;
        if isempty(epMarks) || isempty(B) || ~ismember('t_AP', B.Properties.VariableNames), return; end
        tm = arrayfun(@(m) max([m.tOn, m.tAct]), epMarks);
        vis = find(tm >= xl(1) - 0.5 & tm <= xl(2));
        if isempty(vis) || numel(vis) > 60, return; end
        yl = ylim(axEPv);
        for q = vis(:)'
            m = epMarks(q);
            if ~isnan(m.tOn) && ~isnan(m.tArtEnd)
                patch(axEPv, [m.tOn m.tArtEnd m.tArtEnd m.tOn], yl([1 1 2 2]), [0.6 0.6 0.6], 'FaceAlpha', 0.25, ...
                    'EdgeColor', 'none', 'HitTest', 'off');
            end
            if ~isnan(m.rmp)
                tr = m.tOn; if isnan(tr), tr = m.tAct; end    %RMP: 10 ms before the stimulus (unstimulated: before the upstroke)
                plot(axEPv, tr + [-0.0105 -0.0005], m.rmp * [1 1], '-', 'Color', [0 0.5 0], 'LineWidth', 2, 'HitTest', 'off');
            end
            if strcmp(B.AP_reference{q}, 'upstroke') && ~isnan(m.tAct)
                k = min(numel(EP.V), max(1, round((m.tAct - EP.t0) / EP.dt) + 1));
                plot(axEPv, m.tAct, EP.V(k), '^', 'Color', [0 0.5 0], 'MarkerFaceColor', [0 0.7 0], 'MarkerSize', 6, 'HitTest', 'off');
            end
            if ~isnan(B.AP_Vmax(q))
                plot(axEPv, m.tPeak, m.vPeak, 'v', 'Color', [0.8 0 0], 'MarkerFaceColor', [0.9 0 0], 'MarkerSize', 6, 'HitTest', 'off');
            end
            plot(axEPv, m.tAPD, m.vAPD, 'o', 'Color', [0.1 0.1 0.1], 'MarkerSize', 5, 'HitTest', 'off');
        end
        ylim(axEPv, yl);
        shown = true;
    end

    function out = apiEP()
        out = EP;
    end

    function onCloseEP(~, ~)
        if isempty(EP) && epFrac == 0, return; end
        EP = []; epMarks = []; epVc = []; epArtMask = []; epYLim = {[], []};
        showEP(false);
        if ~isempty(S), analyze(false); end              %contraction table without the AP columns
        status('EP recording removed.');
    end

    function showEP(on)
        % enlarge the figure downwards (on) or restore it. The top bar keeps its size in pixels; the plots and the
        % analysis panel keep theirs if the screen allows, otherwise (small screens; macOS clamps windows to the
        % visible area without telling MATLAB) they are compressed.
        if on == (epFrac > 0), return; end
        fp = fig.Position;
        ctl = findobj(fig, '-depth', 1, '-regexp', 'Type', '^(axes|uicontrol|uipanel)$');
        ctl = ctl(strcmp(get(ctl, 'Units'), 'normalized'));
        yBar = 0.94;                                     %top bar: buttons, file, channel, From/To, info
        if on
            scr = get(groot, 'ScreenSize');
            dec = max(0, fig.OuterPosition(4) - fp(4));  %title bar and toolbar
            Hmax = max(fp(4), scr(4) - 100 - dec);      %menu bar and dock
            dH = 330;                                    %pixels for the two traces
            if fp(4) + dH > Hmax, dH = max(220, Hmax - fp(4)); end
            H1 = min(fp(4) + dH, Hmax);
            y1 = max(66, fp(2) + fp(4) - H1);
            if y1 + H1 + dec > scr(4) - 32, y1 = max(1, scr(4) - 32 - dec - H1); end
            fig.Position = [fp(1), y1, fp(3), H1];
            f = dH / H1; r = fp(4) / H1;                 %r: factor that keeps pixel sizes
            sc = (1 - (1 - yBar) * r - f) / yBar;        %plots and panel: [0 yBar] --> [f, top bar]
            pos0 = get(ctl, 'Position'); if ~iscell(pos0), pos0 = {pos0}; end
            for h = ctl'
                q = h.Position;
                if q(2) >= yBar                          %top bar: same pixels, same distance from the top
                    h.Position = [q(1), 1 - (1 - q(2)) * r, q(3), q(4) * r];
                elseif strcmp(h.Type, 'uicontrol')       %controls (lower plot list, Trend): same height, top edge moved
                    h.Position = [q(1), f + (q(2) + q(4)) * sc - q(4) * r, q(3), q(4) * r];
                else
                    h.Position = [q(1), f + q(2) * sc, q(3), q(4) * sc];
                end
            end
            epFig0 = struct('before', fp, 'after', fig.Position, 'f', f, 'r', r, 'sc', sc, 'h', ctl, 'pos', {pos0});
            epFrac = f;
            px = 1 / H1;                                 %layout of the traces in pixels
            hS = max(45, round(0.2 * dH)); yS = 42; yV = yS + hS + 8; hV = dH - yV - 24;
            axEPv = axes(fig, 'Position', [0.05, yV * px, 0.70, hV * px], 'FontSize', 10, 'XTickLabel', {});
            axEPs = axes(fig, 'Position', [0.05, yS * px, 0.70, hS * px], 'FontSize', 9);
            for a = [axEPv axEPs]
                try disableDefaultInteractivity(a); catch, end
                box(a, 'on'); hold(a, 'on'); grid(a, 'on');
            end
            hEPtxt = uicontrol(fig, dflt{:}, 'Style', 'text', 'String', '', 'HorizontalAlignment', 'left', 'FontSize', 9, ...
                'Position', [0.77, 70 * px, 0.225, (dH - 78) * px]);
            hEPclean = uicontrol(fig, dflt{:}, 'Style', 'checkbox', 'String', 'remove stimulus artefact', 'Value', epClean, ...
                'Position', [0.77, 42 * px, 0.225, 24 * px], 'Callback', @(src,~) epSetClean(src.Value), 'TooltipString', ...
                ['signal plot: the stimulus pulses (stimulation channel) and the artefact after them replaced by straight ' ...
                'lines (grey), display only: the AP parameters are measured on the recorded signal (mda_analyzeAP removeArtefacts)']);
            hEPclose = uicontrol(fig, dflt{:}, 'Style', 'pushbutton', 'String', 'Remove EP recording', ...
                'Position', [0.77, 8 * px, 0.12, 30 * px], 'Callback', @onCloseEP);
            % right click in the EP plots: y limits, artefacts (2026-10-09)
            for iEP = 1:2
                cmEP = uicontextmenu(fig);
                uimenu(cmEP, 'Text', 'Set y limits ...', 'MenuSelectedFcn', @(~,~) epAskYLim(iEP));
                uimenu(cmEP, 'Text', 'y limits: automatic (restore view)', 'MenuSelectedFcn', @(~,~) epSetYLim(iEP, []));
                uimenu(cmEP, 'Text', 'Remove stimulus artefact', 'Separator', 'on', 'Tag', 'epClean', ...
                    'MenuSelectedFcn', @(~,~) epToggleClean());
                uimenu(cmEP, 'Text', 'Drag up / down in the plot: y limits; double-click: automatic', 'Separator', 'on', 'Enable', 'off');
                try cmEP.ContextMenuOpeningFcn = @(src,~) epMenuOpening(src); catch, end   %R2020a+
                if iEP == 1, axEPv.UIContextMenu = cmEP; else, axEPs.UIContextMenu = cmEP; end
            end
            epLis = addlistener(axMain, 'XLim', 'PostSet', @(~,~) drawEP());
        else
            M = epFig0;
            delete(epLis); epLis = [];
            cmDel = [axEPv.UIContextMenu axEPs.UIContextMenu];
            delete([axEPv axEPs hEPtxt hEPclose hEPclean]); delete(cmDel(isgraphics(cmDel)));
            axEPv = gobjects(0); axEPs = gobjects(0); hEPtxt = gobjects(0); hEPclose = gobjects(0); hEPclean = gobjects(0);
            ctl = findobj(fig, '-depth', 1, '-regexp', 'Type', '^(axes|uicontrol|uipanel)$');
            ctl = ctl(strcmp(get(ctl, 'Units'), 'normalized'));
            for h = ctl'
                k = find(M.h == h, 1);
                if ~isempty(k), h.Position = M.pos{k}; continue; end      %previous position
                q = h.Position;                                            %created meanwhile
                if q(2) >= 1 - (1 - yBar) * M.r - 1e-6, h.Position = [q(1), 1 - (1 - q(2)) / M.r, q(3), q(4) / M.r];
                else,                                   h.Position = [q(1), (q(2) - M.f) / M.sc, q(3), q(4) / M.sc]; end
            end
            if max(abs(fp(3:4) - M.after(3:4))) < 2      %not resized by the user: previous size
                fig.Position = [fp(1), fp(2) + fp(4) - M.before(4), M.before(3:4)];
            else                                         %resized: keep the upper part
                H0 = fp(4) * (1 - M.f);
                fig.Position = [fp(1), fp(2) + fp(4) - H0, fp(3), H0];
            end
            epFrac = 0;
        end
    end

    function drawEP()
        % membrane potential and stimulation of the visible time range (min/max envelope for long ranges)
        if epBusy || isempty(EP) || epFrac == 0 || ~isvalid(axEPv), return; end
        epBusy = true;
        try
            cla(axEPv); cla(axEPs);
            xl = xlim(axMain);
            if isempty(S), xl = EP.t0 + [0, (numel(EP.V) - 1) * EP.dt]; end
            if epClean && isempty(epVc), epComputeClean(); end
            if epClean && ~isempty(epVc), Vs = epVc; else, Vs = EP.V; end
            [tv, v, kv] = epSegment(Vs, xl);
            [ts, sv] = epSegment(EP.stim, xl);
            plot(axEPv, tv, v, 'Color', [0 0.3 0.75], 'LineWidth', 0.5, 'HitTest', 'off');
            if epClean && ~isempty(kv) && ~isempty(epArtMask)  %replaced samples (straight lines): grey
                g = v; g(~epArtMask(kv)) = nan;
                if any(~isnan(g)), plot(axEPv, tv, g, 'Color', [0.6 0.6 0.6], 'LineWidth', 1, 'HitTest', 'off'); end
            end
            plot(axEPs, ts, sv, 'Color', [0.8 0 0], 'LineWidth', 0.5, 'HitTest', 'off');
            set([axEPv axEPs], 'XLimMode', 'manual', 'XLim', xl);
            epApplyYLim(axEPv, 1, v, 1); epApplyYLim(axEPs, 2, sv, 1e-6);
            ylabel(axEPv, sprintf('%s (%s)', EP.labelV, EP.unitV)); ylabel(axEPs, sprintf('%s (%s)', EP.labelStim, EP.unitStim));
            tt = {};
            if isempty(v), tt{end+1} = 'no EP data in this time range'; end
            if epClean, tt{end+1} = 'stimulus artefacts removed (grey = straight lines; display only)'; end
            if ~isempty(epYLim{1}) || ~isempty(epYLim{2}), tt{end+1} = 'fixed y limits (double-click in the plot: automatic)'; end
            title(axEPv, strjoin(tt, '   |   '), 'FontWeight', 'normal', 'FontSize', 9);
            info = EP.info;
            if drawAPMarks(xl), info{end+1} = 'AP: ^ upstroke, v V_max, o APD25/50/90'; end
            hEPtxt.String = info;
            mainTicks();
        catch ME
            status(['EP plot: ' ME.message]);
        end
        epBusy = false;
    end

    function [t, y, kIdx] = epSegment(x, xl)
        % samples of x (uniform, EP.t0 + (k-1) * EP.dt in file time) within xl; > 20000 samples: min/max per bin
        % (kIdx: indices of the samples, [] for min/max)
        n = numel(x); kIdx = [];
        k1 = max(1, floor((xl(1) - EP.t0) / EP.dt) + 1); k2 = min(n, ceil((xl(2) - EP.t0) / EP.dt) + 1);
        if k2 < k1, t = []; y = []; return; end
        k = (k1:k2)';
        nBin = 4000;
        if numel(k) <= 5 * nBin
            t = EP.t0 + (k - 1) * EP.dt; y = double(x(k)); y = y(:); kIdx = k;
        else
            m = floor(numel(k) / nBin) * nBin; k = k(1:m);
            X = reshape(double(x(k)), [], nBin);
            mn = min(X, [], 1); mx = max(X, [], 1);
            tb = EP.t0 + (k(1:size(X,1):end) - 1) * EP.dt;
            t = reshape([tb(:)'; tb(:)' + (size(X,1) - 1) * EP.dt], [], 1);
            y = reshape([mn; mx], [], 1);
        end
    end

    function epApplyYLim(a, k, y, dmin)
        % y limits of the EP plot k: fixed (epYLim) or from the data shown (+-5 %)
        if ~isempty(epYLim{k}), ylim(a, epYLim{k}); return; end
        y = y(isfinite(y));
        if isempty(y), ylim(a, 'auto'); return; end
        lo = min(y); hi = max(y); d = max(hi - lo, dmin);
        ylim(a, [lo - 0.05 * d, hi + 0.05 * d]);
    end

    function epSetYLim(k, lim)
        % y limits of the EP plot k (1 = signal, 2 = stimulation): [lo hi], or [] = automatic (restore view)
        if ~isempty(lim)
            lim = double(lim(:)');
            if numel(lim) ~= 2 || any(~isfinite(lim)) || lim(2) <= lim(1)
                status('y limits: two numbers, the lower one first.'); return;
            end
        end
        epYLim{k} = lim;
        drawEP();
    end

    function epAskYLim(k)
        % right click in an EP plot: y limits typed in
        if isempty(EP) || epFrac == 0, return; end
        if k == 1, a = axEPv; nm = sprintf('%s (%s)', EP.labelV, EP.unitV); else, a = axEPs; nm = sprintf('%s (%s)', EP.labelStim, EP.unitStim); end
        yl = ylim(a);
        answ = inputdlg({'lower limit', 'upper limit'}, ['y limits: ' nm], 1, {sprintf('%.6g', yl(1)), sprintf('%.6g', yl(2))});
        if isempty(answ), return; end
        epSetYLim(k, str2double(answ(:))');
    end

    function epSetClean(on)
        % 'remove stimulus artefact': EP signal plot without the stimulus artefacts (display only; mda_analyzeAP
        % 'removeArtefacts'). The AP parameters are measured on the recorded signal.
        epClean = logical(on);
        if ~isempty(hEPclean) && isgraphics(hEPclean), hEPclean.Value = epClean; end
        drawEP();
        if epClean && ~isempty(epArtMask)
            status(sprintf(['%d stimulus artefacts removed in the plot (grey = straight lines). Display only: the AP ' ...
                'parameters are measured on the recorded signal.'], nnz(diff([false; epArtMask]) == 1)));
        end
    end

    function epToggleClean()
        epSetClean(~epClean);
    end

    function epMenuOpening(cm)
        h = findobj(cm, 'Tag', 'epClean');
        if epClean, h.Checked = 'on'; else, h.Checked = 'off'; end
    end

    function epComputeClean()
        % signal without the stimulus artefacts and the replaced samples (cache of the EP recording shown)
        epVc = []; epArtMask = [];
        if isempty(EP), return; end
        [epVc, RA] = mda_analyzeAP('removeArtefacts', EP);
        epArtMask = false(numel(EP.V), 1);
        kA = round((RA(:, 1) - EP.t0) / EP.dt) + 1; kB = round((RA(:, 2) - EP.t0) / EP.dt) + 1;
        for q = 1:numel(kA), epArtMask(kA(q):kB(q)) = true; end
    end

    function status(msg)
        hStatus.String = msg;
        statusText = msg;
    end

    function s = labelLine(Sm)
        % short label summary of the current channel for the info text
        parts = {};
        for nm = {'sampleID','sliceID','species','tissue','treatment'}
            if ismember(nm{1}, Sm.Properties.VariableNames) && ~isempty(Sm.(nm{1}){1}), parts{end+1} = Sm.(nm{1}){1}; end %#ok<AGROW>
        end
        if ismember('concentration', Sm.Properties.VariableNames) && ~isnan(Sm.concentration)
            parts{end+1} = strtrim(sprintf('%g %s', Sm.concentration, Sm.concentrationUnit{1}));
        end
        if ismember('daysInCulture', Sm.Properties.VariableNames) && ~isnan(Sm.daysInCulture)
            parts{end+1} = sprintf('day %.2f', Sm.daysInCulture);
        end
        if isempty(parts), s = 'labels: none (button Labels ...)'; else, s = ['labels: ' strjoin(parts, ' | ')]; end
    end

    % ---------------------------------------------------------------- labels dialog
    function onLabels(~, ~)
        if isempty(H), status('Open a file first.'); return; end
        if ~isempty(hLblFig) && isvalid(hLblFig), figure(hLblFig); return; end
        hLblFig = figure('Name', 'Labels per channel (metadata)', 'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none', ...
            'Color', 'w', 'Units', 'pixels', 'Position', [80 120 1300 360]);
        lightTheme(hLblFig);
        ut = uitable(hLblFig, 'Units', 'normalized', 'Position', [0.01 0.2 0.98 0.78], 'RowName', [], 'FontSize', 10);
        showLabels(ut, Lbl);
        b = {'Style', 'pushbutton', 'Units', 'normalized', 'FontSize', 10};
        uicontrol(hLblFig, b{:}, mainBtn{:}, 'String', 'Apply and close', 'Position', [0.01 0.03 0.13 0.1], 'Callback', @(~,~) applyLabels(ut, true));
        uicontrol(hLblFig, b{:}, 'String', 'Apply', 'Position', [0.15 0.03 0.08 0.1], 'Callback', @(~,~) applyLabels(ut, false));
        uicontrol(hLblFig, b{:}, 'String', 'Fill empty cells from first row', 'Position', [0.24 0.03 0.18 0.1], 'Callback', @(~,~) fillDown(ut));
        uicontrol(hLblFig, b{:}, 'String', 'Load ...', 'Position', [0.43 0.03 0.08 0.1], 'Callback', @(~,~) loadLabels(ut));
        uicontrol(hLblFig, b{:}, 'String', 'Save ...', 'Position', [0.52 0.03 0.08 0.1], 'Callback', @(~,~) saveLabels(ut));
        uicontrol(hLblFig, 'Style', 'text', 'Units', 'normalized', 'Position', [0.61 0.01 0.38 0.14], 'BackgroundColor', 'w', ...
            'HorizontalAlignment', 'left', 'FontSize', 9, 'String', ['cultureStart, e.g. 1999-12-24 14:30: daysInCulture is then ' ...
            'calculated for every contraction. analyst: your initials. Saved as <name>_labels.csv next to the .mdd file, ' ...
            'the file is loaded automatically next time.']);
    end

    function showLabels(ut, L)
        names = L.Properties.VariableNames;
        isNum = cellfun(@(nm) isnumeric(L.(nm)), names);
        fmt = repmat({'char'}, 1, numel(names));
        fmt(isNum) = {'numeric'};
        ut.Data = table2cell(L);
        ut.ColumnName = names;
        ut.ColumnFormat = fmt;
        ut.ColumnEditable = ~strcmp(names, 'channel');
    end

    function L = labelsFromTable(ut)
        d = ut.Data;
        names = ut.ColumnName(:)';
        st = cell2struct(cell(numel(names), 1), names, 1);
        for k = 1:numel(names)
            st.(names{k}) = d(:, k);
        end
        st.channel = cell2mat(d(:, strcmp(names, 'channel')));
        L = mda_labels(struct2table(st), H.dataChannels);
    end

    function applyLabels(ut, closeIt)
        try
            Lbl = labelsFromTable(ut);
        catch ME
            status(['Labels: ' ME.message]); return;
        end
        if closeIt, delete(hLblFig); else, showLabels(ut, Lbl); end
        if ~isempty(B), updateSummary(); end
        status('Labels applied (columns of the exported tables).');
    end

    function fillDown(ut)
        d = ut.Data;
        for c = 2:size(d, 2)
            for r = 2:size(d, 1)
                v = d{r, c};
                if isempty(v) || (isnumeric(v) && isscalar(v) && isnan(v)), d{r, c} = d{1, c}; end
            end
        end
        ut.Data = d;
    end

    function loadLabels(ut)
        p = fileparts(H.file);
        [fn, pn] = uigetfile({'*.csv;*.xlsx', 'labels (*.csv, *.xlsx)'}, 'Load labels', [p filesep]);
        if isequal(fn, 0), return; end
        try
            showLabels(ut, mda_labels(fullfile(pn, fn), H.dataChannels));
        catch ME
            status(['Labels: ' ME.message]);
        end
    end

    function saveLabels(ut)
        try
            L = labelsFromTable(ut);
        catch ME
            status(['Labels: ' ME.message]); return;
        end
        [p, n] = fileparts(H.file);
        [fn, pn] = uiputfile({'*.csv', 'labels (*.csv)'}, 'Save labels', fullfile(p, [n '_labels.csv']));
        if isequal(fn, 0), return; end
        try
            writetable(L, fullfile(pn, fn));
            Lbl = L;
            if ~isempty(B), updateSummary(); end
            status(['Labels saved: ' fullfile(pn, fn)]);
        catch ME
            status(['Labels not saved: ' ME.message]);
        end
    end

    function apiNextFile(file)
        apiFile = file;
    end

    function apiSetRange(r, add)
        % r = [from to] or several rows (s in the loaded window); add = true: added to the selection (shift + drag)
        if nargin < 2, add = false; end
        r = reshape(double(r), [], 2); r = sort(r, 2);
        if add, range = mergeRanges([range; r]); else, range = mergeRanges(r); end
        refresh(false);
    end

    function L = apiLabels()
        L = Lbl;
    end

    function apiSetLabels(m)
        Lbl = mda_labels(m, H.dataChannels);
        if ~isempty(B), updateSummary(); end
    end

    function [G, h] = apiOverlay()
        G = ovG; h = hOv;
    end

    function apiKey(key, modifier)
        if nargin < 2, modifier = {}; end
        fig.CurrentObject = axMain;
        onKey(fig, struct('Key', key, 'Modifier', {modifier}));
    end

    function [T, Sm] = apiResults()
        T = []; Sm = [];
        if isempty(B), return; end
        T = rangeTable();
        Sm = summaryRow();
    end
end


% =====================================================================================================
function v = prefGet(name)
% folder remembered between sessions (MATLAB preferences, group MyoDishAnalysis; 2026-10-14); '' if missing or gone
v = '';
try
    if ispref('MyoDishAnalysis', name), v = getpref('MyoDishAnalysis', name); end
catch
end
if ~ischar(v) || isempty(v) || ~isfolder(v), v = ''; end
end


function prefSet(name, value)
try
    setpref('MyoDishAnalysis', name, char(value));
catch
end
end


function setTip(h, txt)
try h.Tooltip = txt; catch, end                       %UI components: R2019b+
end


function p = resultsRoot(p)
% results folder of the watcher: p or the nearest parent folder with mda_index.csv (a subfolder was chosen)
q = p;
for k = 1:4
    if isfile(fullfile(q, 'mda_index.csv')), p = q; return; end
    up = fileparts(q);
    if isempty(up) || strcmp(up, q), return; end
    q = up;
end
end


function c = numText(x, fmt)
% numbers as text for a table ('' = NaN)
c = repmat({''}, numel(x), 1);
k = ~isnan(x(:));
if any(k), c(k) = compose(fmt, x(k)); end
end


function D = browserRows(X, T)
% rows of the results browser: one per analysed recording and channel with flags (mda_flags.csv), one per recording
% without (not analysed: status and message of the index; flags not computed yet: '?'); sorted by recording and
% channel. Columns main, a, b: main file of a parallel recording (index message 'parallel recording of ...')
[inX, loc] = ismember(T.file, X.file);
T = T(inX, :); loc = loc(inX);
red = ~cellfun(@isempty, T.red); yel = ~cellfun(@isempty, T.yellow);
note = T.red;
note(red & yel) = strcat(T.red(red & yel), {'; '}, T.yellow(red & yel));
note(~red & yel) = T.yellow(~red & yel);
[pm, pa, pb, ptxt] = parallelOf(X.message);
isP = ~cellfun(@isempty, ptxt(loc));                   %analysed parallel recordings: marked in the note
note(isP) = strcat(ptxt(loc(isP)), {'; '}, note(isP));
note(isP & ~(red | yel)) = ptxt(loc(isP & ~(red | yel)));
few = strcmp(T.level, 'few beats') & cellfun(@isempty, note);
note(few) = {'too few contractions for the flags'};
A = table(T.file, T.channel, T.label, T.flags, T.capture_percent, T.nDetected, T.status, note, T.level, ...
    X.status(loc), T.from, T.to, loc, 'VariableNames', {'file', 'channel', 'label', 'flags', 'capture', ...
    'nDetected', 'status', 'note', 'level', 'indexStatus', 'from', 'to', 'row'});
k = find(~ismember((1:height(X))', loc));               %recordings without flags
n = numel(k);
st = X.status(k);
flg = repmat({''}, n, 1);
nt = X.message(k);
ok = strcmp(st, 'ok');
flg(ok) = {'?'};
nt(ok) = {'flags not computed yet (Compute flags)'};
okP = ok & ~cellfun(@isempty, ptxt(k));
nt(okP) = strcat(ptxt(k(okP)), {'; flags not computed yet (Compute flags)'});
B = table(X.file(k), nan(n, 1), repmat({''}, n, 1), flg, nan(n, 1), nan(n, 1), st, nt, repmat({''}, n, 1), st, ...
    nan(n, 1), nan(n, 1), k, 'VariableNames', A.Properties.VariableNames);
D = [A; B];
D.main = pm(D.row); D.a = pa(D.row); D.b = pb(D.row);
D = sortrows(D, {'file', 'channel'});
D.hay = repmat({''}, height(D), 1);
if height(D) > 0, D.hay = lower(strcat(D.file, {' '}, D.label, {' '}, D.flags, {' '}, D.status, {' '}, D.note)); end
end


function [m, a, b, txt] = parallelOf(msg)
% main file (relative path), window (s of the main file) and description of parallel recordings from the messages of
% the index ('parallel recording of <main> (a-b s of the main file): ...'); '' / NaN for the others
n = numel(msg);
m = repmat({''}, n, 1); a = nan(n, 1); b = nan(n, 1); txt = repmat({''}, n, 1);
for i = find(startsWith(msg, 'parallel recording of'))'
    t = regexp(msg{i}, '^parallel recording of (.+?\.mdd) \(([^)]*) of the main file\)', 'tokens', 'once', 'ignorecase');
    if numel(t) < 2, continue; end
    w = sscanf(regexprep(t{2}, '^from |\s*s$', ''), '%f-%f');   %'a-b s' or 'from a s' (no nested tokens in MATLAB)
    if isempty(w), continue; end
    m{i} = t{1}; a(i) = w(1);
    if numel(w) > 1, b(i) = w(2); end
    [~, mn, me] = fileparts(t{1});
    txt{i} = sprintf('parallel recording of %s', [mn me]);
end
end


function closeDialog(src, ok)
% OK / Cancel of a modal dialog: result in UserData, uiresume
f = ancestor(src, 'figure');
f.UserData = ok;
uiresume(f);
end


function [lo, hi] = overlayBand(band, M, SD, nn, Yall)
% band around the mean of an overlay group: 'SD', 'SEM' (SD / sqrt(n)), 'range' (min - max of the traces); empty for
% 'none' or fewer than 2 traces
lo = []; hi = [];
if size(Yall, 1) < 2, return; end
switch band
    case 'SD'
        lo = M - SD; hi = M + SD;
    case 'SEM'
        se = SD ./ sqrt(max(nn, 1));
        lo = M - se; hi = M + se;
    case 'range'
        lo = min(Yall, [], 1); hi = max(Yall, [], 1);
        lo(isnan(M)) = nan; hi(isnan(M)) = nan;
end
end


function bandPatch(ax, x, lo, hi, col)
% transparent band lo ... hi (one patch per run of finite values)
ok = isfinite(lo) & isfinite(hi);
d = diff([false ok false]);
a = find(d == 1); b = find(d == -1) - 1;
for k = 1:numel(a)
    i = a(k):b(k);
    if numel(i) < 2, continue; end
    patch(ax, [x(i) fliplr(x(i))], [lo(i) fliplr(hi(i))], col, 'FaceAlpha', 0.2, 'EdgeColor', 'none', ...
        'HitTest', 'off', 'HandleVisibility', 'off');
end
end


function c = trendColors()
% colours of the channels in the trend window when several channels are overlaid (MATLAB default line colours + grey)
c = [0 0.447 0.741; 0.85 0.325 0.098; 0.929 0.694 0.125; 0.494 0.184 0.556; 0.466 0.674 0.188; 0.301 0.745 0.933; ...
    0.635 0.078 0.184; 0.35 0.35 0.35];
end


function xn = navStep(xl, key, ext, lim, minSpan)
% time axis after an arrow key: left / right = move by half the span, with ext (shift) = extend by half the span on
% that side; up / down = zoom in / out around the centre (span / 2, x 2); limited to lim and >= minSpan
w = diff(xl);
switch key
    case 'leftarrow'
        if ext, xn = [xl(1) - 0.5 * w, xl(2)]; else, xn = xl - 0.5 * w; end
    case 'rightarrow'
        if ext, xn = [xl(1), xl(2) + 0.5 * w]; else, xn = xl + 0.5 * w; end
    case 'uparrow'
        xn = mean(xl) + [-0.25 0.25] * w;
    otherwise
        xn = mean(xl) + [-1 1] * w;
end
span = min(max(diff(xn), minSpan), diff(lim));
if ext
    xn = [max(xn(1), lim(1)), min(xn(2), lim(2))];
else
    a = min(max(mean(xn) - span / 2, lim(1)), lim(2) - span);
    xn = [a, a + span];
end
end


function lightTheme(f)
% light colors also with the dark theme of MATLAB / the operating system (R2025a+; older releases: no Theme property)
try
    f.Theme = 'light';
catch
end
end

function k = nearestSample(t, x)
% index of the sample of the uniform time vector t nearest to x
n = numel(t);
if n == 1, k = 1; return; end
k = min(n, max(1, round((x - t(1)) / (t(n) - t(1)) * (n - 1)) + 1));
end

function s = fmtNum(x, digits)
% compact number for the summary table: integers above 1000, otherwise significant digits
if isnan(x)
    s = 'NaN';
elseif abs(x) >= 1000
    s = sprintf('%.0f', x);
else
    s = sprintf(['%.' num2str(digits) 'g'], x);
end
end

function s = fmtDuration(sec)
if sec < 120
    s = sprintf('%.1f s', sec);
elseif sec < 7200
    s = sprintf('%.1f min', sec / 60);
else
    s = sprintf('%.2f h', sec / 3600);
end
end

function R = parseRows(txt)
% 'a b; c d; ...' (info table) --> rows [from to]
R = zeros(0, 2);
if isempty(txt), return; end
if isnumeric(txt), R = reshape(double(txt), [], 2); return; end
p = strsplit(char(txt), ';');
for k = 1:numel(p)
    v = sscanf(p{k}, '%f');
    if numel(v) == 2, R(end+1, :) = v(:)'; end %#ok<AGROW>
end
end

function txt = rowsText(R)
% rows [from to] as text: 'a b' or 'a b; c d; ...' (info table)
txt = strjoin(arrayfun(@(r) sprintf('%.15g %.15g', R(r,1), R(r,2)), (1:size(R, 1))', 'UniformOutput', false), '; ');
end

function R = mergeRanges(R)
% rows [from to] sorted, overlapping or touching ones merged (2026-10-14)
R = reshape(double(R), [], 2);
R = R(all(isfinite(R), 2), :);
if isempty(R), R = [nan nan]; return; end
R = sortrows(sort(R, 2));
k = 1;
for r = 2:size(R, 1)
    if R(r,1) <= R(k,2), R(k,2) = max(R(k,2), R(r,2)); else, k = k + 1; R(k,:) = R(r,:); end
end
R = R(1:k, :);
end

function [S, V] = sideBySide(Ss, gap)
% windows Ss (cell of mda_readMdd outputs, sorted, not overlapping) one after another with gap s between them: one
% window in condensed time (2026-10-14). Between two windows the force is a straight line (no peak), the rocker counts
% as moving and S.gapMask is true. V.seg = [fileFrom fileTo winFrom winTo] per window, V.shift = winTime - fileTime,
% V.breaks = window times of the dashed lines. Time-stamped log entries of the file facts (offset, calibration, pulse
% settings, ...) are moved to window time: an entry between two windows applies from the start of the next one.
S = Ss{1};
dt = S.dt;
nG = max(1, round(gap / dt));
K = numel(Ss);
V = struct('seg', zeros(K, 4), 'shift', zeros(K, 1), 'breaks', zeros(max(0, K - 1), 1));
t = cell(1, 2 * K); F = t; R = t; G = t;
stimF = fieldnames(S.stim);
st = cell(K, numel(stimF));
sp = cell(K, 1);
tEnd = -inf; q = 0;
for k = 1:K
    Sk = Ss{k};
    if k == 1, sh = 0; else, sh = tEnd + dt * (nG + 1) - Sk.t(1); end
    if k > 1
        w = (1:nG) / (nG + 1);
        f0 = F{q}(:, end); f1 = Sk.force(:, 1);
        q = q + 1;
        t{q} = tEnd + dt * (1:nG); F{q} = f0 + (f1 - f0) .* w; R{q} = true(1, nG); G{q} = true(1, nG);
        V.breaks(k - 1) = tEnd + dt * (nG + 1) / 2;
    end
    q = q + 1;
    t{q} = Sk.t + sh; F{q} = Sk.force; R{q} = logical(Sk.rockerOn); G{q} = false(size(Sk.t));
    V.seg(k, :) = [Sk.fromSeconds, Sk.toSeconds, Sk.fromSeconds + sh, Sk.toSeconds + sh];
    V.shift(k) = sh;
    tEnd = Sk.t(end) + sh;
    for j = 1:numel(stimF)
        v = Sk.stim.(stimF{j});
        if strcmp(stimF{j}, 'time'), v = v + sh; end
        st{k, j} = reshape(v, [], 1);
    end
    if isfield(Sk, 'spikes') && ~isempty(Sk.spikes)
        x = Sk.spikes; x(:, 2:3) = x(:, 2:3) + sh; sp{k} = x;
    end
end
S.t = [t{1:q}]; S.force = [F{1:q}]; S.rockerOn = [R{1:q}]; S.gapMask = [G{1:q}];
S.fromSeconds = V.seg(1, 3); S.toSeconds = V.seg(end, 4);
for j = 1:numel(stimF), S.stim.(stimF{j}) = vertcat(st{:, j}); end
if isfield(S, 'spikes'), S.spikes = vertcat(zeros(0, 4), sp{:}); end
for nm = {'offsetLog', 'calibrationLog', 'pulseSettingsLog', 'extraPulseLog', 'rockerSpeedLog'}
    if isfield(S, nm{1}) && isnumeric(S.(nm{1})) && ~isempty(S.(nm{1}))
        S.(nm{1})(:, 1) = stepTime(S.(nm{1})(:, 1), V);
    end
end
for nm = {'extendedSensorIntervals', 'rockerLogIntervals'}
    if isfield(S, nm{1}) && isnumeric(S.(nm{1})) && ~isempty(S.(nm{1})) && size(S.(nm{1}), 2) >= 2
        S.(nm{1})(:, 1:2) = stepTime(S.(nm{1})(:, 1:2), V);
    end
end
S.sideBySide = V;
end

function tw = stepTime(tf, V)
% times of log entries (file) --> window time of sideBySide: within a window shifted with it; between two windows: the
% start of the next one; before the first: unchanged; after the last: the same distance after its end
tw = tf;
for i = 1:numel(tf)
    x = tf(i);
    if ~isfinite(x), continue; end
    k = find(x >= V.seg(:,1) & x <= V.seg(:,2), 1);
    if ~isempty(k), tw(i) = x + V.shift(k); continue; end
    k = find(V.seg(:,1) > x, 1);
    if isempty(k)
        tw(i) = V.seg(end,4) + (x - V.seg(end,2));
    elseif k > 1
        tw(i) = V.seg(k,3) - 1e-6;
    end
end
end

function [ticks, labels, unit] = timeTicks(xl, tMax, given, span)
% tick positions (s) and labels for a time axis in seconds: h:mm (h:mm:ss when zoomed in) if the axis reaches 1 h or
% more, otherwise m:ss; from 2 days 'd h:mm' (steps of days: 'd'; 2026-10-14); decimals of the seconds for steps
% < 1 s; about 4-10 ticks. given (optional): labels for these times instead (side-by-side rocker stops: the times in
% the file of the ticks of the condensed axis), the step from span (s shown)
steps = [0.05 0.1 0.2 0.5 1 2 5 10 15 30 60 120 300 600 900 1800 3600 7200 10800 21600 43200 86400 172800 432000 864000];
if nargin < 4 || isempty(span), span = diff(xl); end
k = find(span ./ steps <= 10, 1);
if isempty(k), k = numel(steps); end
st = steps(k);
if nargin < 3 || isempty(given), ticks = (ceil(xl(1) / st) : floor(xl(2) / st)) * st; else, ticks = given(:)'; end
tAll = [abs(tMax), abs(xl(:))', abs(ticks(isfinite(ticks)))];
hrs = max(tAll) >= 3600;
days = max(tAll) >= 2 * 86400;
withSec = st < 60 || ~hrs;
dec = 0;
if st < 0.1, dec = 2; elseif st < 1, dec = 1; end
if days
    labels = arrayfun(@(t) fmtDays(t, st, withSec, dec), ticks, 'UniformOutput', false);
    if st >= 86400, unit = 'days'; elseif withSec, unit = 'd h:mm:ss'; else, unit = 'd h:mm'; end
    return;
end
labels = arrayfun(@(t) fmtClock(t, hrs, withSec, dec), ticks, 'UniformOutput', false);
if ~hrs
    unit = 'm:ss';
elseif withSec
    unit = 'h:mm:ss';
else
    unit = 'h:mm';
end
end

function s = fmtDays(t, st, withSec, dec)
% seconds --> 'n d' (whole days, steps of days) or 'n d h:mm(:ss)' (time axes from 2 days, 2026-10-14)
if ~isfinite(t), s = ''; return; end
neg = t < 0; t = abs(t);
d = floor(t / 86400 + 1e-9); r = max(0, t - 86400 * d);
if st >= 86400 && r < 0.5
    s = sprintf('%d d', d);
else
    s = sprintf('%d d %s', d, fmtClock(r, true, withSec, dec));
end
if neg, s = ['-' s]; end
end

function s = fmtClock(t, hrs, withSec, dec)
% seconds --> 'h:mm:ss' / 'h:mm' (hrs = true) or 'm:ss'; dec = decimals of the seconds
if nargin < 4, dec = 0; end
neg = t < 0; t = round(abs(t) * 10^dec) / 10^dec;
h = floor(t / 3600); m = floor((t - 3600 * h) / 60); sec = t - 3600 * h - 60 * m;
if dec > 0, ss = sprintf('%0*.*f', 3 + dec, dec, sec); else, ss = sprintf('%02d', round(sec)); end
if hrs
    if withSec, s = sprintf('%d:%02d:%s', h, m, ss); else, s = sprintf('%d:%02d', h, m); end
else
    s = sprintf('%d:%s', floor(t / 60), ss);
end
if neg, s = ['-' s]; end
end

function t = helpText()
P = mda_parameters();
t = [{'Open ...: a recording (.mdd) or results of an analysis (.xlsx, <name>_info.csv, ...; see below). The folder is remembered. A recording opens with its first 120 s loaded and analysed (From / To).', ...
      'Results ...: results browser of a results folder of the watcher (mda_index.csv): one row per recording and channel with the flags of the watcher report (red = check the analysis, yellow = slice quality; list: all / with flags / red flags / not analysed; search). Double-click a row (or Open): the channel with the settings of its analysis (red flags: the window of the flags, otherwise the first 120 s). Compute flags: for results of older watcher versions. The last folder opens again directly (Folder ... = another one).', ...
      'Main file (button next to the file name): the open file is a parallel recording (e.g. schedule file or snapshot started from the main recording); opens the main file at the window shown, same channel.', ...
      'Flags (grey line above the table): flags of the watcher report for the analysed range of the channel (red = check the analysis: I inverted signal, N noise, S large extra beats, D delay, F stimulus frequency; orange = slice quality: C capture, X extra beats, A amplitude, T amplitude change, V amplitude CV).', ...
      '', ...
      'Comments ...: searchable list of the comments in the log file (# = number in the force plot, date / time, time in the file, text; option: all log entries). Select a row: the comment is highlighted in the force plot; double-click (or Go to): loads the data around it. Force plot: comments as numbered purple marks at the top (pointer on a mark: its text; click: highlighted and selected in the list).', ...
      '', ...
      'Overview: min/max of the selected channel over the whole recording (green = rocker at rest). Drag in it to load a time window (or type From/To and press Load).', ...
      '', ...
      'Force plot: red = selected contractions, orange = uncertain contractions (high sensitivity: neither locked to the stimuli nor large compared with the other contractions; not counted with high specificity), grey = excluded by the filters (rocker / stimulated only), x = excluded by you, blue ticks = stimuli, green ticks = extra pulses (status channel bit 16: pre-pulses, CCM pulses, ...), green rings = contractions elicited by an extra pulse, black diamonds = ambiguous stimulus assignment, bar at the top = rocker state (green = at rest, grey = moving), yellow = analysed range(s).', ...
      'Advanced ...: all parameters of the method that are based on assumptions or experience, one tab per part (stimulus assignment / onset gate, detection, noise and artifact rules, rocker rules, signal and spike removal, rocker filter, export). Hover over a name for its meaning; Guide = settings guide (PDF) with figures; Defaults = mda_options(); Apply / OK analyse the window again (* = the window is read again). Save settings ... / Load settings ...: settings file (.csv; also results of an analysis); the settings are saved with every export (info table). Changed settings: the button shows their number in red (e.g. Advanced (3 changed), shortened if it does not fit: Adv. (3 chgd)); its tooltip lists them with their defaults.', ...
      'Legend of the force plot: menu View or right click in the force plot (it can be dragged).', ...
      'Cursor in the force plot: "drag = select time range" (shift + drag: add a range; several ranges are pooled, exports add one row per range) or "click = exclude / include contraction". Zoom/pan: mouse wheel or figure toolbar (switch the tool off afterwards). Right click: Zoom to the selection; Select all rocker stops of the overview range (with "only contractions with rocker at rest"): every rocker stop of the range shown in the overview side by side (dashed lines = time gaps). Overview, right click: Select all (load the range shown, at most 4 h).', ...
      'Mouse pointer over the force, stimulus, parameter or EP plots: a dashed line and a marker on the curve; the value at that time is shown small in the top left corner of every plot (force; stimulus pulse nearest to it: current and interval; lower plot: parameter of the nearest contraction; EP signal and stimulation). The plot under the pointer also shows the time and the time since the last stimulus.', ...
      'Arrow keys (click into a plot first) and the buttons under the force plot change the loaded window (= blue selection in the overview and analysed range; read again): left / right = move it by half its length, shift + left / right (shift + click) = extend it by half its length on that side, up / down (middle buttons) = zoom in / out (half / twice its length). Mouse pointer over the overview: the keys move its time axis instead; a zoomed overview moves along. The mouse wheel zooms only the display.', ...
      '', ...
      'Overlay contractions: selected contractions + mean, aligned at the stimulus (t = 0, default) or the peak, or the time course of the analysed range (t = 0 at the first stimulus of each group). Press again (or Add current selection in the overlay window) to add another selection as a new group; Channels (same range) ...: tick channels to add them for the analysed range (same settings, threshold and zero force of each channel). Per group (list): legend text, colour, line width, line style and a transparent band (mean +- SD, +- SEM or range). Title, axis labels and legend position are editable below the plot (empty = automatic); Edit figure ... opens a copy with the MATLAB plot tools.', ...
      '', ...
      'Trend ...: rolling mean / median of a parameter over long periods and several files in a row (_0, _1, ...); sampling: all contractions, short windows or rocker stops. Channel list: one channel, or several channels ... (checkboxes) = overlaid, one colour per channel (the file is read once for all of them).', ...
      '', ...
      'Save / Export (menu or right click on a plot): plots as .png / .jpg / .tif / .fig, plotted data (visible time range) as .xlsx / .csv / .txt; overview: picture only. Every data export contains the table info (version, recording, all settings, threshold and zero force of the channel, window and range).', ...
      '', ...
      'Open ... with a results file of MyoDishAnalysis, the watcher or an export of the GUI (.xlsx, <name>_info.csv, _summary.csv, _contractions.csv): the recording (path in the file; otherwise next to the results file or asked for), the settings and the analysis window (channel, data window, analysed range; several: list) are restored, the contractions are detected again and compared with the file (status line; black o = contraction of the file not found again, e.g. other version). Contractions excluded by you in an export are excluded again.', ...
      '', ...
      'Labels ...: labels per channel (setupID, sliceID, species, sampleID, sampleGroup, sliceGroup, tissue, treatment, concentration, concentrationUnit, daysInCulture, cultureStart, comment, analyst) - columns of the exported tables; saved as <name>_labels.csv next to the .mdd file and loaded automatically.', ...
      '', ...
      'Detection: peaks with a prominence >= threshold (auto: 0.3 x typical amplitude, >= 30 uN; per channel: auto or a manual value, kept when you switch channels and used for All channels, Protocols and Trend). A contraction within 25 ms ... min(stimulus interval, 1 s) after a stimulus of the channel is "stimulated", otherwise "extra". Stimuli (list next to "only stimulated contractions"): the MyoDish pulses of the channel, or the external trigger pulses of the status channel (external stimulator at the external controller unit, which carries one chamber: any data channel); auto = external trigger pulses if the loaded window has no MyoDish pulses.', ...
      '', ...
      'Reference beat (right click in the force plot): the mean shape (+- SD) of the selected contractions becomes the reference of the channel. Every contraction is compared with it, aligned at the stimulus (default; a changed latency counts, contractions without stimulus at the 50 % upstroke) or at the 50 % upstroke (shape only; reference window): refCorrelation (shape correlation), refRMSDeviation_SD (overall) and refMaxDeviation_SD (largest local deviation) in SD of the reference, each also normalized (...Norm: both scaled to amplitude 1 = shape only). Deviating contractions (> x SD) are circled magenta, counted in the table and can be excluded (reference window). Save/load a reference to apply it to other files. Every parameter is also given relative to the mean of the reference contractions (column %ref in the table; <parameter>_pctRef in tables, lower plot, trend and exports; diastolic force: difference in uN, _dRef).', ...
      '', ...
      '+ EP recording ...: LabChart export (.mat) of an electrophysiological recording made in parallel, e.g. sharp electrode (voltage + stimulation channel; default: same name as the .mdd file). It is aligned to the stimuli of the .mdd file (stimulus pattern; on constant pacing also stimulus current and clock times; clock drift corrected) and shown below the plots with the same time axis. The text right of the traces gives the matched stimuli and the offset - check it if marked CHECK. Remove EP recording hides it.', ...
      'EP plots: drag up / down = y limits of that plot, double-click = automatic; right click: Set y limits ... / y limits: automatic (restore view). remove stimulus artefact: the stimulus pulses and the artefact after them (saturation, decay towards the RMP) are replaced by straight lines (grey) - display only, the AP parameters are measured on the recorded signal.', ...
      '', ...
      'AP parameters (EP recording, mda_analyzeAP), per contraction: AP_dVdtMax (V/s, max. upstroke velocity), AP_RMP (mV, median over 10 ms before the stimulus artefact), AP_Vmax (mV, peak), APD25/50/90 (ms, activation = time of dV/dt max --> 25/50/90 % repolarization). Stimulus artefact = pulse in the stimulation channel (biphasic pulse incl. pause = one pulse) until V_m is no longer saturated and |dV/dt| < 20 V/s; the stimulus onset is the stimulus time. If the upstroke lies within the artefact (foot of the upstroke not near RMP), dV/dt max, V_max, APD25 and APD50 are NaN and APD90 is measured from the stimulus onset (approximate, AP_note). Each AP is evaluated up to the next stimulus (fusion: NaN, note). Markers (<= 60 contractions visible): grey = artefact, green line = RMP, ^ upstroke, v V_max, o APD25/50/90.', ...
      '', ...
      'Remove rocker artifact: while the rocker moves, each sensor shows a periodic signal (rocker frequency, 60 rpm = 1.21 Hz). It is estimated per channel between the contractions (+-60 s around the window) and subtracted; light grey = signal before. Not possible (message): rocker frequency not found, no periodic artifact, too little time between the contractions (fast pacing). The setting also applies to All channels, Trend and exports. Rocker artifact ... (button, menu Save / Export, right click in the force plot): extra window with the signal before / after the filter and the removed artifact (also if the filter is off); menu: save as figure, export the data of the visible time range.', ...
      '', 'Parameters:'}, ...
      cellfun(@(n, u, d) sprintf('%s (%s): %s', n, u, d), P(:,1)', P(:,2)', P(:,3)', 'UniformOutput', false)];
end


function nm = advChanges(o)
% advanced settings (rows of advancedDefs) that differ from the defaults: 'name = value (default x)' (2026-10-14)
D = advancedDefs();
d0 = mda_options();
nm = {};
for r = 1:size(D, 1)
    f = D{r, 1};
    if ~isfield(o, f) || ~isfield(d0, f) || sameOpt(o.(f), d0.(f)), continue; end
    nm{end+1} = sprintf('%s = %s (default %s)', f, optText(o.(f)), optText(d0.(f))); %#ok<AGROW>
end
end


function tf = sameOpt(a, b)
% option values equal; numbers with a relative tolerance of 1e-9 (values typed in the advanced settings window are
% divided by its scale, e.g. ms -> s)
if isnumeric(a) && isnumeric(b) && isequal(size(a), size(b))
    a = double(a(:)); b = double(b(:));
    tf = all(abs(a - b) <= 1e-9 * max(1, abs(b)) | (isnan(a) & isnan(b)));
else
    tf = isequaln(a, b);
end
end


function s = optText(v)
% value of an option as text (as the status line of the advanced settings)
if ischar(v) || isstring(v), s = char(v);
elseif islogical(v), s = mat2str(v);
elseif isempty(v), s = '[]';
else, s = strtrim(sprintf('%g ', v));
end
end


function D = advancedDefs()
% rows of the advanced settings window (generated from the parameter list of the settings guide): option
% name, label, kind ('popup', 'check', 'num', 'int', 'numauto', 'vec'), popup items {label, value},
% tooltip, scale (shown value = option value x scale), unit, tab, reread (the data are read again)
D = {
    'stimAssignment', 'Assignment', 'popup', {'onset gate', 'onset'; 'peak (<= 1.0.0-beta.3)', 'peak'}, ...
        ['onset gate: a pulse can only have elicited a contraction if it lies from onset - gateMax to onset + ' ...
        'gateTolerance (onset = tangent at the maximum dF/dt crossing the diastolic level). peak: last pulse ' ...
        'minStimToPeak ... maxStimToPeak before the peak (versions <= 1.0.0-beta.3; extra pulses count as ' ...
        'regular pulses)'], ...
        1, '', 'Assignment', false;
    'gateMax', 'gateMax: longest pulse -> onset delay', 'num', [], ...
        ['longest delay from the eliciting pulse to the contraction onset (Dmax) of uncertain contractions (and ' ...
        'without certainty: manual threshold, unpaced). Near threshold the onset can be delayed by ~80 ms'], ...
        1000, 'ms', 'Assignment', false;
    'gateMaxCertain', 'gateMaxCertain: ... of certain contractions', 'num', [], ...
        ['longest pulse -> onset delay of certain contractions (auto threshold, paced: locked to the stimuli or ' ...
        'large); slices with a long but constant delay (e.g. 0.3 s). At most gateMaxCertainRel x the stimulus ' ...
        'interval, at least gateMax'], ...
        1000, 'ms', 'Assignment', false;
    'gateMaxCertainRel', 'gateMaxCertainRel: ... at most', 'num', [], ...
        ['the gate of certain contractions is at most this fraction of the interval of the regular pulses ' ...
        'before the onset (a longer delay cannot be told from an early contraction before the next pulse)'], ...
        1, 'x stimulus interval', 'Assignment', false;
    'gateCore', 'gateCore: typical delay range', 'num', [], ...
        ['several candidate pulses: pulses before the onset before pulses after it, regular before extra ' ...
        'pulses; of one kind the earliest up to gateCore before the onset, otherwise the latest one'], ...
        1000, 'ms', 'Assignment', false;
    'gateTolerance', 'gateTolerance: pulses after the onset', 'num', [], ...
        ['tolerance of the onset estimate (epsilon): pulses up to this time after the onset are still ' ...
        'candidates; ambiguous if a pulse of the other kind would be chosen with the onset this time earlier ' ...
        'or later'], ...
        1000, 'ms', 'Assignment', false;
    'ambiguityWindow', 'ambiguityWindow', 'num', [], ...
        ['a pulse of the other kind (regular / extra) up to this time before or after the chosen pulse marks ' ...
        'the assignment as ambiguous (column stimAmbiguous)'], ...
        1000, 'ms', 'Assignment', false;
    'risePhaseLevel', 'risePhaseLevel: rise phases', 'num', [], ...
        ['no pulse in the gate of the onset: the onsets of the other rise phases of the upstroke are tried ' ...
        '(local maxima of dF/dt of at least this fraction of the maximum dF/dt; rocker movement, fused ' ...
        'spontaneous events)'], ...
        100, '% of max dF/dt', 'Assignment', false;
    'steepRiseMargin', 'steepRiseMargin', 'num', [], ...
        ['still no pulse: a pulse after the gate up to this time before the maximum dF/dt is taken (onset ' ...
        'estimated too early, e.g. rocker artifacts); marked ambiguous'], ...
        1000, 'ms', 'Assignment', false;
    'contractionEnd', 'contractionEnd: end of a contraction', 'num', [], ...
        ['end of a contraction for post-pulses, for regular pulses missed within a contraction and for the ' ...
        'phase of the pulse table: this relaxation (% of peak - minimum after the peak)'], ...
        1, '% relaxation', 'Assignment', false;
    'prePulseWindow', 'prePulseWindow: pre-pulses kept', 'num', [], ...
        ['pulses without own contraction are listed as pre-pulses of the next contraction if they lie at most ' ...
        'this time before its eliciting pulse (column prePulses); during a contraction (eliciting pulse ... ' ...
        'contractionEnd) as post-pulses'], ...
        1, 's', 'Assignment', false;
    'offsetSnap', 'offsetSnap: programmed offsets', 'num', [], ...
        ['time of pre- / post-pulses: the programmed offset of the log file (''Sequence'' entries) is used if ' ...
        'the measured offset (resolution 2.5 ms) lies within this time of it'], ...
        1000, 'ms', 'Assignment', false;
    'minStimToPeak', 'minStimToPeak (peak assignment)', 'num', [], ...
        ['peak assignment: a peak earlier than this after a pulse is not caused by it; onset gate: only for ' ...
        'contractions without upstroke in the data'], ...
        1000, 'ms', 'Assignment', false;
    'maxStimToPeak', 'maxStimToPeak (peak assignment)', 'numauto', [], ...
        'peak assignment: auto = min(stimulus interval, 1 s), or a number of seconds', ...
        1, 's', 'Assignment', false;
    'externalTrigger', 'Stimuli', 'popup', {'auto', 'auto'; 'MyoDish pulses', 'off'; 'external trigger pulses', 'on'}, ...
        ['stimulus times: MyoDish pulses of the channel, or the external trigger pulses of the status channel ' ...
        '(external stimulator at the external controller unit: one chamber, any data channel). auto = ' ...
        'external trigger pulses if the window has no MyoDish pulses'], ...
        1, '', 'Assignment', false;
    'relThreshold', 'relThreshold (auto threshold)', 'num', [], ...
        'auto threshold: minimum prominence = this fraction of the typical contraction amplitude', ...
        1, 'x typical', 'Detection', false;
    'minThreshold', 'minThreshold (auto threshold)', 'num', [], ...
        'auto threshold: never lower than this', ...
        1, 'uN', 'Detection', false;
    'minBeatInterval', 'minBeatInterval', 'num', [], ...
        'minimum time between two contraction peaks (the more prominent one wins)', ...
        1, 's', 'Detection', false;
    'maxBeatWindow', 'maxBeatWindow', 'num', [], ...
        'at most this time before and after a peak belongs to one contraction (diastolic minimum, relaxation)', ...
        1, 's', 'Detection', false;
    'pacedMinStimuli', 'pacedMinStimuli', 'int', [], ...
        ['a channel counts as paced with at least this many regular pulses in the data window: typical ' ...
        'amplitude = median of the largest peaks (as many as pulses), noise level before the stimuli, rocker ' ...
        'rules, certainty by locking; otherwise: largest gap between the sorted prominences'], ...
        1, 'pulses', 'Detection', false;
    'pauseMinInterval', 'pauseMinInterval', 'num', [], ...
        'stimulation pause: stimulus interval at least this long ...', ...
        1, 's', 'Detection', false;
    'pauseIntervalRatio', 'pauseIntervalRatio', 'num', [], ...
        ['... and at least this multiple of the interval before; then F_dia is searched only from ' ...
        'pauseDiastoleWindow before the stimulus'], ...
        1, 'x interval before', 'Detection', false;
    'pauseDiastoleWindow', 'pauseDiastoleWindow', 'num', [], ...
        ['after a stimulation pause, the diastolic minimum is searched only from this time before the stimulus' ...
        ' (inf = off)'], ...
        1, 's', 'Detection', false;
    'diastolicLevel', 'Diastolic level (F_dia)', 'popup', {'median before the pulse', 'preStimulusMedian'; 'minimum before the peak (<= 1.0.0-beta.3)', 'minimum'}, ...
        ['level from which amplitude, upstroke levels (10 / 50 / 90 %), AUC and diastolic force are measured. ' ...
        'median before the pulse: median of the unfiltered signal diastoleWindowStart ... diastoleWindowEnd ' ...
        'before the eliciting pulse (before the onset if it follows the pulse by more than gateMax; contractions ' ...
        'without pulse, or a median above the peak: minimum); ' ...
        'minimum: last minimum of the filtered signal before the peak (versions <= 1.0.0-beta.3). Relaxation ' ...
        'levels: minimum after the peak (both)'], ...
        1, '', 'Detection', false;
    'diastoleWindowStart', 'diastoleWindowStart: before the pulse', 'num', [], ...
        'diastolic level ''median before the pulse'': window from this time before the eliciting pulse ...', ...
        1000, 'ms', 'Detection', false;
    'diastoleWindowEnd', 'diastoleWindowEnd: before the pulse', 'num', [], ...
        '... to this time before the pulse (stimulus artifact excluded)', ...
        1000, 'ms', 'Detection', false;
    'lockWindow', 'lockWindow: stimulus locking', 'num', [], ...
        ['a peak is locked to the stimuli if its latency (time since the previous pulse) lies within ' ...
        '+-lockWindow of the typical latency (centre of the densest window of 2 x lockWindow); certainty and ' ...
        'rocker / artifact rules'], ...
        1000, 'ms', 'Detection', false;
    'lockWindowRel', 'lockWindowRel', 'num', [], ...
        ['at high rates the lock window is at most this fraction of the stimulus interval (certainty; ' ...
        'rocker-only rule)'], ...
        1, 'x stimulus interval', 'Detection', false;
    'lockedThreshold', 'lockedThreshold: small locked peaks', 'num', [], ...
        ['0 = off. Otherwise a peak below the threshold is also a contraction if it is locked to a stimulus, the ' ...
        'rocker is at rest and it is >= this fraction of the typical amplitude (and >= lockedNoiseRel x the median ' ...
        'rise before the stimuli): small responses, e.g. to a premature S2 near the refractory period (e.g. 0.1)'], ...
        1, 'x typical', 'Detection', false;
    'lockedNoiseRel', 'lockedNoiseRel', 'num', [], ...
        'small locked peaks (lockedThreshold): ... and >= this multiple of the median rise before the stimuli', ...
        1, 'x median rise', 'Detection', false;
    'certainNoiseRel', 'certainNoiseRel', 'num', [], ...
        ['certainty, paced: a locked contraction is certain if its prominence is >= this multiple of the ' ...
        'median rise of the signal before the stimuli'], ...
        1, 'x median rise', 'Detection', false;
    'certainLargeRel', 'certainLargeRel', 'num', [], ...
        ['certainty, paced: a contraction that is not locked is certain if it is >= this fraction of the ' ...
        'typical amplitude ...'], ...
        1, 'x typical', 'Detection', false;
    'certainLargeNoiseRel', 'certainLargeNoiseRel', 'num', [], ...
        '... and >= this multiple of the median rise before the stimuli', ...
        1, 'x median rise', 'Detection', false;
    'certainUnpacedRel', 'certainUnpacedRel', 'num', [], ...
        'certainty, unpaced channels: certain if >= this fraction of the typical amplitude', ...
        1, 'x typical', 'Detection', false;
    'invertedCheck', 'Inverted signal', 'check', [], ...
        ['paced channels: if the force falls after the stimuli (magnet out of position), the contractions are ' ...
        'detected in the inverted signal (rate, capture) and the force and time parameters are NaN (column ' ...
        'invertedSignal)'], ...
        1, '', 'Detection', false;
    'invertedRatio', 'invertedRatio', 'num', [], ...
        ['inverted signal: the largest fall of the stimulus-triggered median is at least this multiple of its largest ' ...
        'rise, and the signal deflects downwards (50th - 10th percentile >= this x (90th - 50th percentile))'], ...
        1, 'x rise', 'Detection', false;
    'invertedMinAmplitude', 'invertedMinAmplitude', 'num', [], ...
        'inverted signal: the fall of the stimulus-triggered median is at least this large', ...
        1, 'uN', 'Detection', false;
    'invertedMinWidth', 'invertedMinWidth', 'num', [], ...
        ['inverted signal: the stimulus-triggered median lies below half its fall for at least this time (no ' ...
        'stimulus artifact)'], ...
        1000, 'ms', 'Detection', false;
    'invertedMinCapture', 'invertedMinCapture', 'num', [], ...
        ['inverted signal confirmed: the normal detection in the negated signal finds certain stimulated ' ...
        'contractions for at least this fraction of the pulses; otherwise (e.g. rocker waves) the channel is ' ...
        'analysed as it is'], ...
        100, '% of pulses', 'Detection', false;
    'invertedSkip', 'invertedSkip', 'num', [], ...
        'inverted signal: the stimulus-triggered median starts this time after the pulse (stimulus artifact)', ...
        1000, 'ms', 'Detection', false;
    'rockerArtifacts', 'Rocker artifact rules', 'check', [], ...
        ['paced channels, auto threshold: peaks of the rocker movement that are not locked to the stimuli are ' ...
        'not counted (artifact gap and rocker rules)'], ...
        1, '', 'Noise / artifacts', false;
    'noiseMinInterval', 'noiseMinInterval', 'num', [], ...
        'noise level N: only windows before stimuli that follow an interval of at least this length', ...
        1, 's', 'Noise / artifacts', false;
    'noiseWindow', 'noiseWindow', 'num', [], ...
        ['noise level N: window before each such stimulus (at most noiseWindowRel x interval); rise = maximum ' ...
        'minus the running minimum of the signal'], ...
        1, 's', 'Noise / artifacts', false;
    'noiseWindowRel', 'noiseWindowRel', 'num', [], ...
        'noise window at most this fraction of the stimulus interval', ...
        1, 'x interval', 'Noise / artifacts', false;
    'noisePercentile', 'noisePercentile', 'num', [], ...
        'noise level N = this percentile of the rises (the median of the rises is used for the certainty)', ...
        1, '%', 'Noise / artifacts', false;
    'noiseMinWindows', 'noiseMinWindows', 'int', [], ...
        'noise level only with at least this many windows (otherwise unknown)', ...
        1, 'windows', 'Noise / artifacts', false;
    'artifactMinCandidates', 'artifactMinCandidates', 'int', [], ...
        'artifact gap rule (raises the threshold): needs at least this many peaks above the auto threshold', ...
        1, 'peaks', 'Noise / artifacts', false;
    'artifactGapRatio', 'artifactGapRatio', 'num', [], ...
        ['artifact gap rule: the largest ratio between two consecutive sorted prominences below the typical ' ...
        'amplitude must be >= this value (a clear gap between artifacts and contractions)'], ...
        1, 'x', 'Noise / artifacts', false;
    'artifactMaxRel', 'artifactMaxRel', 'num', [], ...
        'artifact gap rule: all peaks of the lower cluster are <= this fraction of the typical amplitude', ...
        1, 'x typical', 'Noise / artifacts', false;
    'artifactMinPeaks', 'artifactMinPeaks', 'int', [], ...
        'artifact gap rule: at least this many peaks of the lower cluster are not locked to the stimuli', ...
        1, 'peaks', 'Noise / artifacts', false;
    'artifactRockerFraction', 'artifactRockerFraction', 'num', [], ...
        'artifact gap rule: at least this fraction of the lower cluster occurs while the rocker moves', ...
        100, '%', 'Noise / artifacts', false;
    'chanceMargin', 'chanceMargin', 'num', [], ...
        ['locked ''more than by chance'': fraction locked > chance level (2 x lockWindow / stimulus interval) ' ...
        '+ this margin ...'], ...
        100, '%', 'Noise / artifacts', false;
    'chanceMax', 'chanceMax', 'num', [], ...
        '... the limit is at most this fraction (artifact gap rule, partial capture of the rocker rules)', ...
        100, '%', 'Noise / artifacts', false;
    'rockerRuleMinFraction', 'rockerRuleMinFraction', 'num', [], ...
        'rocker rules (b, c): only if the rocker moves during at least this fraction of the data window', ...
        100, '% of the time', 'Rocker rules', false;
    'noiseLockedMax', 'noiseLockedMax', 'num', [], ...
        ['rule b (no contractions): fewer than this fraction of the largest peaks (as many as pulses) locked ' ...
        '...'], ...
        100, '%', 'Rocker rules', false;
    'noiseAbsMax', 'noiseAbsMax', 'num', [], ...
        '... and the typical amplitude <= this value ...', ...
        1, 'uN', 'Rocker rules', false;
    'noiseRelMax', 'noiseRelMax', 'num', [], ...
        ['... or <= this multiple of the noise level N with the peaks at the rhythm of the rocker: rocker / ' ...
        'noise peaks'], ...
        1, 'x N', 'Rocker rules', false;
    'rhythmMinPerCycle', 'rhythmMinPerCycle', 'num', [], ...
        'rhythm of the rocker: at least this many peaks per rocker cycle (rule b) ...', ...
        1, 'peaks / cycle', 'Rocker rules', false;
    'rhythmMaxPerCycle', 'rhythmMaxPerCycle', 'num', [], ...
        '... and at most this many, or a median peak interval of 1 or 1/2 rocker period ...', ...
        1, 'peaks / cycle', 'Rocker rules', false;
    'rhythmTolerance', 'rhythmTolerance', 'num', [], ...
        '... within this tolerance (1/2 period: half of it)', ...
        100, '% of the period', 'Rocker rules', false;
    'keepNoiseRel', 'keepNoiseRel', 'num', [], ...
        ['rule b: locked peaks >= max(keepNoiseRel x N, N + keepNoiseAbs) stay (slices that answer only some ' ...
        'stimuli) ...'], ...
        1, 'x N', 'Rocker rules', false;
    'keepNoiseAbs', 'keepNoiseAbs', 'num', [], ...
        '... (absolute distance from the noise level) ...', ...
        1, 'uN', 'Rocker rules', false;
    'keepMinPeaks', 'keepMinPeaks', 'int', [], ...
        '... if there are at least this many of them ...', ...
        1, 'peaks', 'Rocker rules', false;
    'keepMinFraction', 'keepMinFraction', 'num', [], ...
        '... and at least this fraction of the pulses, and more of them are locked than by chance', ...
        100, '% of the pulses', 'Rocker rules', false;
    'dropRel', 'dropRel', 'num', [], ...
        ['rule b: peaks below this multiple of max(typical amplitude, N) are removed (larger peaks are no ' ...
        'rocker artifacts)'], ...
        1, 'x max(typical, N)', 'Rocker rules', false;
    'smallNoiseRel', 'smallNoiseRel', 'num', [], ...
        ['rule c: peaks not locked to the stimuli below min(smallNoiseRel x N, smallTypicalRel x typical) are ' ...
        'removed ...'], ...
        1, 'x N', 'Rocker rules', false;
    'smallTypicalRel', 'smallTypicalRel', 'num', [], ...
        '... (peaks at the rhythm of the rocker: smallRhythmTypicalRel instead) ...', ...
        1, 'x typical', 'Rocker rules', false;
    'smallRhythmMinPerCycle', 'smallRhythmMinPerCycle', 'num', [], ...
        '... rhythm of the rocker for rule c: at least this many peaks per rocker cycle ...', ...
        1, 'peaks / cycle', 'Rocker rules', false;
    'smallRhythmTypicalRel', 'smallRhythmTypicalRel', 'num', [], ...
        '... then the limit is min(smallNoiseRel x N, this fraction of the typical amplitude)', ...
        1, 'x typical', 'Rocker rules', false;
    'rockerOnlyMinIntervals', 'rockerOnlyMinIntervals', 'int', [], ...
        ['N unknown (high rates): peaks at the rhythm of the rocker need at least this many peak intervals ...' ...
        'N unknown (high rates): peaks at the rhythm of the rocker need at least this many peak intervals ...'], ...
        1, 'intervals', 'Rocker rules', false;
    'rockerOnlyFraction', 'rockerOnlyFraction', 'num', [], ...
        '... of which at least this fraction are 1 or 1/2 rocker period ...', ...
        100, '%', 'Rocker rules', false;
    'rockerOnlyTolerance', 'rockerOnlyTolerance', 'num', [], ...
        '... within this tolerance (1/2 period: half of it) ...', ...
        100, '% of the period', 'Rocker rules', false;
    'captureTolerance', 'captureTolerance', 'num', [], ...
        ['... and the median interval is no 1:1 or 2:1 multiple of the stimulus interval within this tolerance' ...
        ' (capture at the rocker period cannot be told apart)'], ...
        100, '%', 'Rocker rules', false;
    'downsampling', 'downsampling (raw samples per value)', 'int', [], ...
        'n raw samples are combined (2: mean, 400 Hz -> 200 Hz; n > 2: median); the window is read again', ...
        1, 'samples', 'Signal', true;
    'medianFilterMs', 'Moving median', 'num', [], ...
        'moving median of the force signal (0 = off)', ...
        1, 'ms', 'Signal', false;
    'meanFilterMs', 'Moving mean', 'num', [], ...
        'moving mean after the median (0 = off)', ...
        1, 'ms', 'Signal', false;
    'spikeRemoval', 'Remove spike artifacts', 'check', [], ...
        ['spike artifacts (e.g. chambers taken out / put in) are replaced by a line before the averaging of ' ...
        'the raw samples (the window is read again)'], ...
        1, '', 'Signal', true;
    'spikeJumpMin', 'spikeJumpMin', 'num', [], ...
        ['spike: a jump between two raw samples >= J = max(spikeJumpMin, spikeJumpFactor x median of the ' ...
        'non-zero differences of the channel) ...'], ...
        1, 'AU', 'Signal', true;
    'spikeJumpFactor', 'spikeJumpFactor', 'num', [], ...
        '... (noise level of the channel) ...', ...
        1, 'x noise', 'Signal', true;
    'spikeGroupGap', 'spikeGroupGap', 'num', [], ...
        'jumps closer than this form one group ...', ...
        1000, 'ms', 'Signal', true;
    'spikeMaxDuration', 'spikeMaxDuration', 'num', [], ...
        '... that lasts at most this long ...', ...
        1000, 'ms', 'Signal', true;
    'spikeLevelWindow', 'spikeLevelWindow', 'num', [], ...
        '... and goes beyond the level before and after it (median of this time) by >= J ...', ...
        1000, 'ms', 'Signal', true;
    'spikeJumpFraction', 'spikeJumpFraction', 'num', [], ...
        ['... with the largest jump >= this fraction of its largest deviation (abrupt; a contraction rises ' ...
        'over many samples)'], ...
        100, '%', 'Signal', true;
    'spikeCoincidence', 'spikeCoincidence', 'num', [], ...
        'within this time of a spike of another channel ...', ...
        1000, 'ms', 'Signal', true;
    'spikeCoincidenceFactor', 'spikeCoincidenceFactor', 'num', [], ...
        '... the jump threshold is max(spikeJumpMin, this factor x J) (spikes in several channels)', ...
        1, 'x J', 'Signal', true;
    'rockerSource', 'Rocker state from', 'popup', {'auto', 'auto'; 'status channel', 'status'; 'log file', 'log'}, ...
        ['auto: bit 15 of the status channel; the ''rockerSpeed'' entries of the log file if that bit is ' ...
        'missing or there is no status channel; the file is read again'], ...
        1, '', 'Rocker filter', true;
    'rockerLogDelay', 'rockerLogDelay', 'num', [], ...
        ['delay of the rocker movement after a ''rockerSpeed'' entry of the log file (rocker state from the ' ...
        'log file)'], ...
        1, 's', 'Rocker filter', true;
    'rockerHzPerRpm', 'rockerHzPerRpm', 'num', [], ...
        ['rocker frequency per rpm setting (two setups: 0.02020 and 0.02025 Hz/rpm); rocker rules and rocker ' ...
        'filter'], ...
        1, 'Hz / rpm', 'Rocker filter', false;
    'rfBandRel', 'rfBandRel: frequency search', 'num', [], ...
        'rocker filter: the rocker frequency is searched within +-this fraction of the expected frequency', ...
        100, '%', 'Rocker filter', false;
    'rfBandNoLog', 'rfBandNoLog', 'vec', [], ...
        'rocker filter: search band without rocker speed in the log file', ...
        1, 'Hz (from to)', 'Rocker filter', false;
    'rfHarmonics', 'rfHarmonics', 'int', [], ...
        'rocker filter: number of harmonics of the periodic artifact', ...
        1, 'harmonics', 'Rocker filter', false;
    'rfBlock', 'rfBlock', 'num', [], ...
        'rocker filter: block length of the fit (hop = half a block)', ...
        1, 's', 'Rocker filter', false;
    'rfMinRun', 'rfMinRun', 'num', [], ...
        'rocker filter: shorter rocker-on periods are not corrected', ...
        1, 's', 'Rocker filter', false;
    'rfKnot', 'rfKnot', 'num', [], ...
        'rocker filter: knot distance of the baseline (slow drift) fitted together with the artifact', ...
        1, 's', 'Rocker filter', false;
    'rfSmoothBaseline', 'rfSmoothBaseline', 'num', [], ...
        'rocker filter: smoothness penalty of the baseline', ...
        1, '', 'Rocker filter', false;
    'rfRidge', 'rfRidge', 'num', [], ...
        'rocker filter: ridge penalty of the harmonics', ...
        1, '', 'Rocker filter', false;
    'rfMinCover', 'rfMinCover', 'num', [], ...
        ['rocker filter: a block is fitted only if this fraction of the 20 phase bins of the rocker cycle has ' ...
        '>= 5 samples between the contractions'], ...
        100, '%', 'Rocker filter', false;
    'rfMinR2', 'rfMinR2', 'num', [], ...
        'rocker filter: minimum R2 of a block fit', ...
        1, '', 'Rocker filter', false;
    'rfMaxSizeRel', 'rfMaxSizeRel', 'num', [], ...
        'rocker filter: artifact size of a block at most this multiple of the reference size', ...
        1, 'x reference', 'Rocker filter', false;
    'rfMinRefBlock', 'rfMinRefBlock', 'num', [], ...
        'rocker filter: reference blocks are at least this long', ...
        1, 's', 'Rocker filter', false;
    'rfMaxBorrow', 'rfMaxBorrow', 'num', [], ...
        ['rocker filter: a block without own fit uses the artifact of a neighbouring block of the same rocker ' ...
        'period up to this distance'], ...
        1, 's', 'Rocker filter', false;
    'rfF0Block', 'rfF0Block', 'num', [], ...
        'rocker filter, frequency estimate: blocks of at most this length ...', ...
        1, 's', 'Rocker filter', false;
    'rfF0Blocks', 'rfF0Blocks', 'int', [], ...
        '... at most this many per channel and rocker speed ...', ...
        1, 'blocks', 'Rocker filter', false;
    'rfF0Clear', 'rfF0Clear', 'num', [], ...
        '... and the peak of the fit must be clear within +-this fraction', ...
        100, '%', 'Rocker filter', false;
    'rfExtendBlock', 'rfExtendBlock', 'num', [], ...
        'rocker filter: blocks without full coverage of the rocker cycle are retried with this length', ...
        1, 's', 'Rocker filter', false;
    'rfMaskRelax', 'rfMaskRelax: contraction masks', 'num', [], ...
        ['rocker filter: the artifact is fitted to the samples between contractions; a contraction is masked ' ...
        'from TTP90 + rfMaskMargin before its peak to rfMaskRelax x TTR90 + rfMaskMargin after it (medians of' ...
        ' the channel)'], ...
        1, 'x TTR90', 'Rocker filter', false;
    'rfMaskMargin', 'rfMaskMargin', 'num', [], ...
        'rocker filter: margin of the contraction masks before and after a contraction', ...
        1000, 'ms', 'Rocker filter', false;
    'rfMaskMax', 'rfMaskMax: paced masks', 'num', [], ...
        ['rocker filter, paced channels (first pass): masked from 20 ms before each pulse to min(next pulse - ' ...
        '50 ms, this time) after it'], ...
        1, 's', 'Rocker filter', false;
    'frequencyResolution', 'frequencyResolution: >= 1 Hz', 'num', [], ...
        ['grouping by pacing frequency (FFR): stimulus intervals within 2 % form a group, its frequency (1 / ' ...
        'median interval) is rounded to this step at >= 1 Hz; groups with the same rounded frequency are one ' ...
        'group (0.99, 1.0 and 1.001 Hz = 1 Hz). FFR results: the groups at 0.5, 1, 2 and 3 Hz'], ...
        1, 'Hz', 'Protocols', false;
    'frequencyResolutionLow', 'frequencyResolutionLow: < 1 Hz', 'num', [], ...
        ['... below 1 Hz the frequency is rounded to this step (0.49 and 0.5 Hz = 0.5 Hz, 0.74 and 0.75 Hz = ' ...
        '0.75 Hz)'], ...
        1, 'Hz', 'Protocols', false;
    'pauseTolerance', 'pauseTolerance: pause length', 'num', [], ...
        ['grouping by pause length (post-rest potentiation): pauses (stimulus interval - steady interval) ' ...
        'within this fraction of the shortest pause of a set are one pause length (same group value and ' ...
        'label, numbered #n); PRP15 / 30 / 60: mean of the pauses within this fraction of 15 / 30 / 60 s'], ...
        100, '%', 'Protocols', false;
    'steadyStateBeats', 'steadyStateBeats: FFR steps', 'int', [], ...
        ['FFR protocols: each pacing frequency is summarized from its steady state: the last this many ' ...
        'contractions of the longest run of consecutive stimuli at this frequency (other runs, e.g. the basic ' ...
        'pacing before and after the protocol, are not used), of its longest sequence of captured stimuli ' ...
        'whose previous and next stimuli are captured, too (partial capture, e.g. 2:1, gives no steady ' ...
        'state). 0 = all contractions of the frequency (versions <= 1.0.0-beta.3)'], ...
        1, 'contractions', 'Protocols', false;
    'ffrRockerFallback', 'FFR: steps without rocker stop', 'check', [], ...
        ['FFR protocols with rocker ''stopped'' (default of protocols): contractions with the rocker at rest ' ...
        'are used (more accurate); a step without such contractions is summarized from the contractions with ' ...
        'the rocker moving (note)'], ...
        1, '', 'Protocols', false;
    'prpReference', 'PRP reference', 'popup', {'last beats before each pause', 'preceding'; 'train before the first pause', 'firstTrain'; 'all steady contractions (<= 1.0.0-beta.3)', 'steady'}, ...
        ['post-rest potentiation: reference amplitude of each post-rest contraction. last beats before each ' ...
        'pause: median of the last prpReferenceBeats contractions of the pacing before this pause (this ' ...
        'pacing loads the SR); train before the first pause: mean of the contractions of the pacing before ' ...
        'the first pause of the protocol; all steady contractions: mean of the steady group (versions <= ' ...
        '1.0.0-beta.3). Reference contractions independent of the rocker state'], ...
        1, '', 'Protocols', false;
    'prpReferenceBeats', 'prpReferenceBeats', 'int', [], ...
        'PRP reference ''last beats before each pause'': number of contractions before the pause (median)', ...
        1, 'contractions', 'Protocols', false;
    'irregularCV', 'irregularCV: irregular groups', 'num', [], ...
        ['a group (e.g. FFR step) is flagged irregular (summary column irregular) if the coefficient of ' ...
        'variation of the amplitudes of its included contractions (population SD / mean, column amplitude_CV)' ...
        ' exceeds this value: conduction block, alternans or extra beats'], ...
        100, '%', 'Protocols', false;
    'minGroupBeats', 'minGroupBeats: few contractions', 'int', [], ...
        ['FFR protocols: a note lists the frequencies summarized from fewer included contractions (0 = no ' ...
        'note)'], ...
        1, 'contractions', 'Protocols', false;
    'arrhythmicChannels', 'Arrhythmically paced channels', 'vec', [], ...
        ['channels paced arrhythmically (e.g. 3 5; summary column arrhythmicPacing): the analysis report does not ' ...
        'flag their capture and amplitude CV and does not count their missed beats in the noise index (expected ' ...
        'with arrhythmic pacing); the capture is still analysed'], ...
        1, 'channels', 'Protocols', false;
    'arrhythmicDetection', 'Detect arrhythmic pacing', 'check', [], ...
        ['channels are also detected as arrhythmically paced if the stim-to-stim variability exceeds ' ...
        'arrhythmicMinVariability during more than arrhythmicMinFraction of the paced time (windows overlapping a ' ...
        'stimulation protocol of the log file do not count; analyses of the protocols: only the channels above)'], ...
        1, '', 'Protocols', false;
    'arrhythmicMinVariability', 'arrhythmicMinVariability', 'num', [], ...
        ['arrhythmic pacing: a window is variable if the coefficient of variation (population SD / mean) of its ' ...
        'stimulus intervals exceeds this value (regular pacing: < 1 %)'], ...
        100, '% (CV)', 'Protocols', false;
    'arrhythmicMinFraction', 'arrhythmicMinFraction', 'num', [], ...
        ['arrhythmic pacing: the variable windows make up more than this fraction of the paced time of the ' ...
        'analysed ranges'], ...
        100, '% of the paced time', 'Protocols', false;
    'arrhythmicWindow', 'arrhythmicWindow', 'num', [], ...
        ['arrhythmic pacing: length of the windows (from the start of each range; paced: at least 6 regular ' ...
        'pulses)'], ...
        1, 's', 'Protocols', false;
    'pulseTable', 'Pulse table', 'check', [], ...
        ['exports and All channels -> file: table of all stimulus pulses (sheet / file pulses: pulse ID, time,' ...
        ' extra pulse, current, durations, outcome, role, contraction, phase)'], ...
        1, '', 'Export', false;
    'pulseTextMax', 'pulseTextMax', 'int', [], ...
        ['prePulses / postPulses: at most this many pulses (those nearest to the eliciting pulse), then ' ...
        '''&+<number of the others>'''], ...
        1, 'pulses', 'Export', false};
end


function t = advDefaultText(d, d0)
% unit and default value of a row of the advanced settings window (d0: mda_options(); * = the window is read again)
v = d0.(d{1});
u = strrep(d{7}, 'uN', [char(181) 'N']);
switch d{3}
    case 'popup'
        k = find(strcmp(d{4}(:,2), char(v)), 1);
        t = sprintf('default: %s', d{4}{k,1});
    case 'check'
        if v, t = 'default: on'; else, t = 'default: off'; end
    case 'numauto'
        if ischar(v), t = 's (default: auto)'; else, t = sprintf('s (default: %g)', v); end
    case 'vec'
        dv = strtrim(sprintf('%g ', v * d{6}));
        if isempty(dv), dv = 'none'; end
        t = strtrim(sprintf('%s (default: %s)', u, dv));
    otherwise
        t = strtrim(sprintf('%s (default: %g)', u, v * d{6}));
end
if d{9}, t = [t ' *']; end
end
