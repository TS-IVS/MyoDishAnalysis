function figOut = MyoDishAnalysisGUI(mddFile, metadata)
%MYODISHANALYSISGUI  Interactive contraction analysis of a MyoDish recording (.mdd).
%
%   MyoDishAnalysisGUI            opens a file dialog
%   MyoDishAnalysisGUI(mddFile)
%   MyoDishAnalysisGUI(mddFile, metadata)   labels per channel (struct / table / file, see mda_labels)
%   MyoDishAnalysisGUI(resultsFile)         results of MyoDishAnalysis / watcher / GUI export (.xlsx, _info.csv):
%                                           recording, settings and analysis window restored (mda_readResults)
%
% Labels per channel (setupID, sliceID, species, sampleID, sampleGroup, sliceGroup, tissue, treatment, concentration,
% concentrationUnit, daysInCulture, cultureStart, comment, analyst): button 'Labels ...' (editable table, load / save as .csv). A file
% <name>_labels.csv next to the .mdd file is loaded automatically. The labels become columns of the exported tables.
%
% 0. 'Comments ...': searchable list of the comments of the log file (date and time, time in the file, text); double-click
%    (or Go to) loads the data around the comment. Comments are marked in the plots (purple).
% 1. 'Overview' shows the complete recording of the selected channel (min/max envelope, green =
%    rocker at rest). Drag in the overview (or type From/To and press Load) to load a time window.
%    Mouse wheel over the overview or the force plot: zoom the time axis (shift + wheel: move); double-click:
%    whole file / whole loaded window. The zoomed overview is re-read in more detail.
%    Arrow keys (click into a plot first) and the buttons under the force plot change the loaded window (= the blue
%    selection in the overview and the analysed range; read again): left / right = move it by half its length, shift
%    + left / right (shift + click) = extend it by half its length on that side, up / down (middle buttons) = zoom in
%    / out (half / twice its length). Mouse pointer over the overview: the keys move its time axis instead; a zoomed
%    overview moves along when the window leaves its visible part. The mouse wheel zooms only the display.
% 2. The force plot shows the loaded window (force - zero force, if the zero force is known): detected contractions
%    (red = selected, orange = uncertain (high sensitivity), grey = excluded by the filters, black x = excluded by
%    you), stimuli (blue ticks), rocker moving (grey background). The stimulus plot below shows the current of every
%    stimulus pulse (mA; green = extra pulse, x = current not reached) and the interval to the previous pulse of the
%    channel (ms); numbers are written when 40 pulses or fewer are visible (zoom in).
%    Cursor mode 'drag = select time range': drag in the force plot to choose the analysed range.
%    Cursor mode 'click = exclude / include contraction': click on a contraction to exclude it (or include it again).
%    Zoom / pan with the figure toolbar (switch the zoom / pan tool off again to use the mouse modes).
% 3. The table shows mean and SD of the selected contractions; the lower plot shows one parameter (list 'Lower plot') per
%    contraction over time. 'Export this channel' writes all contractions of the range (column 'included')
%    (every export also contains the table info: version, recording, all settings, window and range; 'Open results ...'
%    or MyoDishAnalysisGUI(resultsFile) restores recording, settings and analysis window of a results file of
%    MyoDishAnalysis, the watcher or the GUI and compares the contractions detected again with the file)
%    and the summary to .xlsx or .csv. 'All channels -> file' analyses the range in all channels with the
%    same settings (without your manual exclusions). The detection threshold is set per channel (auto or manual).
%    'high sensitivity' (default) counts all contractions and marks the uncertain ones (orange); 'high specificity'
%    does not count them (mda_options 'detection'). 'Rocker artifact ...': extra window with the signal before / after
%    the rocker filter and the removed periodic artifact; save as figure, export the data.
%    Stimuli ('stimuli: auto / MyoDish / ext. trigger'): MyoDish pulses of the channel or the external trigger pulses
%    of the status channel (external stimulator at the external controller unit, one chamber; auto = trigger pulses
%    if the window has no MyoDish pulses).
%    'Trend ...': rolling mean / median of a parameter over long periods, also over several files in a row; one
%    channel or several channels overlaid (channel list: 'several channels ...').
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
%    exports); markers in the EP plot when <= 60 contractions are visible.
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
% channels, detection mode, open results, rocker artifact window 2026-10-09)

if nargin < 1, mddFile = ''; end
if nargin < 2, metadata = []; end

% ------------------------------------------------------------------ state (shared by the nested functions)
H = []; S = []; O = []; B = []; C = [];
ch = 1;
range = [nan nan];
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
Od = [];                           %detailed overview of a zoomed part of the file
ovXL = [];                         %time axis of the overview ([] = whole file)
tmr = [];                          %timer: reads the detailed overview after zooming
shiftDown = false;                 %shift key held (shift + click on the arrow buttons under the force plot)

% ------------------------------------------------------------------ figure and controls
fig = figure('Name', 'MyoDishAnalysis', 'NumberTitle', 'off', 'Color', 'w', 'Units', 'pixels', ...
    'Position', [40 40 1450 880], 'MenuBar', 'none', 'ToolBar', 'figure', 'WindowButtonDownFcn', @onMouseDown, ...
    'WindowScrollWheelFcn', @onScroll, 'WindowKeyPressFcn', @onKey, 'WindowKeyReleaseFcn', @onKeyRelease, ...
    'DeleteFcn', @onClose);
movegui(fig, 'onscreen');
dflt = {'Units', 'normalized', 'FontSize', 10, 'BackgroundColor', 'w'};

uicontrol(fig, dflt{:}, 'Style', 'pushbutton', 'String', 'Open .mdd ...', 'Position', [0.005 0.955 0.065 0.035], 'Callback', @onOpen);
uicontrol(fig, dflt{:}, 'Style', 'pushbutton', 'String', 'Open results ...', 'Position', [0.156 0.955 0.07 0.035], 'Callback', @onOpenResults, ...
    'TooltipString', ['results file of MyoDishAnalysis, the watcher or an export (.xlsx, _info.csv, ...): recording, settings ' ...
    'and analysis window are restored, the contractions detected again and compared with the file']);
uicontrol(fig, dflt{:}, 'Style', 'pushbutton', 'String', '+ EP recording ...', 'Position', [0.072 0.955 0.08 0.035], 'Callback', @onOpenEP, ...
    'TooltipString', 'add an electrophysiological recording (LabChart .mat export, e.g. sharp electrode: voltage + stimulation) aligned to the stimuli of the open .mdd file');
hFile = uicontrol(fig, dflt{:}, 'Style', 'text', 'String', 'no file', 'HorizontalAlignment', 'left', 'Position', [0.229 0.952 0.131 0.03]);
uicontrol(fig, dflt{:}, 'Style', 'text', 'String', 'Channel', 'HorizontalAlignment', 'right', 'Position', [0.36 0.952 0.04 0.03]);
hCh = uicontrol(fig, dflt{:}, 'Style', 'popupmenu', 'String', {'-'}, 'Position', [0.405 0.957 0.1 0.033], 'Callback', @onChannel);
uicontrol(fig, dflt{:}, 'Style', 'text', 'String', 'From (s)', 'HorizontalAlignment', 'right', 'Position', [0.505 0.952 0.04 0.03]);
hFrom = uicontrol(fig, dflt{:}, 'Style', 'edit', 'String', '0', 'Position', [0.548 0.957 0.055 0.033]);
uicontrol(fig, dflt{:}, 'Style', 'text', 'String', 'To (s)', 'HorizontalAlignment', 'right', 'Position', [0.603 0.952 0.03 0.03]);
hTo = uicontrol(fig, dflt{:}, 'Style', 'edit', 'String', '60', 'Position', [0.636 0.957 0.055 0.033]);
uicontrol(fig, dflt{:}, 'Style', 'pushbutton', 'String', 'Load', 'Position', [0.695 0.955 0.045 0.035], 'Callback', @onLoad);
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
uicontrol(fig, nb{:}, 'String', char(9664), 'Position', [0.05 0.4485 0.022 0.026], 'Callback', @(~,~) onNavButton('leftarrow'), ...
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
axNames = {'overview', 'force', 'stimuli', 'parameter'};
axList = [axOv axMain axStim axPar];
for iAxMenu = 1:4                                    %(unique names: variables of the main function are shared with the nested functions)
    cmAxMenu = uicontextmenu(fig);
    if iAxMenu == 2                                  %force plot: zero force = y value of the right click
        uimenu(cmAxMenu, 'Text', 'Set as zero force (y at the mouse pointer)', 'Tag', 'zeroHere', 'MenuSelectedFcn', @(~,~) setZeroAtClick());
        uimenu(cmAxMenu, 'Text', 'Zero force from the log file (Offset)', 'MenuSelectedFcn', @(~,~) resetZero());
        uimenu(cmAxMenu, 'Text', 'Set mean beat shape of the selected contractions as reference', 'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) setReference());
        uimenu(cmAxMenu, 'Text', 'Show reference beat / deviating contractions ...', 'MenuSelectedFcn', @(~,~) showReference());
        uimenu(cmAxMenu, 'Text', 'Remove reference beat of this channel', 'MenuSelectedFcn', @(~,~) clearReference());
        uimenu(cmAxMenu, 'Text', 'Show rocker artifact (removed signal) ...', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) onRockerWindow());
        try cmAxMenu.ContextMenuOpeningFcn = @(src,~) zeroMenuText(src); catch, end   %R2020a+
    end
    hSaveAxMenu = uimenu(cmAxMenu, 'Text', 'Save this plot (.png / .jpg / .tif / .fig) ...', 'MenuSelectedFcn', @(~,~) savePlots(axNames{iAxMenu}));
    if iAxMenu == 2, hSaveAxMenu.Separator = 'on'; end
    if iAxMenu > 1, uimenu(cmAxMenu, 'Text', 'Export data of this plot (.xlsx / .csv / .txt) ...', 'MenuSelectedFcn', @(~,~) exportPlotData(axNames{iAxMenu})); end
    uimenu(cmAxMenu, 'Text', 'Save all plots ...', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) savePlots('all'));
    axList(iAxMenu).UIContextMenu = cmAxMenu;
end

pnl = uipanel(fig, 'Position', [0.765 0.01 0.232 0.925], 'Title', 'Analysis', 'BackgroundColor', 'w', 'FontSize', 10);
bg = uibuttongroup(pnl, 'Position', [0.03 0.885 0.94 0.105], 'Title', 'Cursor in the force plot', 'BackgroundColor', 'w', 'FontSize', 9);
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
hXT = uicontrol(pnl, dflt{:}, 'Style', 'popupmenu', 'String', {'stimuli: auto', 'stimuli: MyoDish', 'stimuli: ext. trigger'}, ...
    'Position', [0.615 0.682 0.355 0.035], 'Callback', @onFilter, 'TooltipString', ['stimulus times: MyoDish pulses of the channel, or the ' ...
    'external trigger pulses of the status channel (external stimulator at the external controller unit: one chamber, any data ' ...
    'channel). auto = external trigger pulses if the window has no MyoDish pulses']);
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
hTable = uitable(pnl, 'Units', 'normalized', 'Position', [0.03 0.215 0.94 0.27], 'RowName', [], ...
    'ColumnName', {'parameter','mean','SD','n','unit'}, 'ColumnWidth', {108, 66, 60, 38, 42}, 'FontSize', 9);
uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'Overlay contractions', 'Position', [0.03 0.165 0.46 0.04], 'Callback', @onOverlay, ...
    'TooltipString', ['overlay of the selected contractions (mean beat or time course); press again (or Add in the overlay window) to add ' ...
    'another selection as a new group; other channels of the same range: Channels ... in the overlay window']);
uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'Show table', 'Position', [0.51 0.165 0.46 0.04], 'Callback', @onShowTable);
uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'Export this channel ...', 'Position', [0.03 0.12 0.46 0.04], 'Callback', @onExport);
uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'All channels -> file ...', 'Position', [0.51 0.12 0.46 0.04], 'Callback', @onAllChannels);
uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'Copy summary', 'Position', [0.03 0.075 0.46 0.04], 'Callback', @onCopy);
uicontrol(pnl, dflt{:}, 'Style', 'pushbutton', 'String', 'Help', 'Position', [0.51 0.075 0.46 0.04], 'Callback', @(~,~) helpdlg(helpText(), 'MyoDishAnalysis'));
hStatus = uicontrol(pnl, dflt{:}, 'Style', 'text', 'String', 'Open an .mdd file.', 'HorizontalAlignment', 'left', 'Position', [0.03 0.003 0.94 0.068], 'FontSize', 9, 'ForegroundColor', [0 0 0.6]);

% functions for scripts / tests: api = fig.UserData; api.setRange([t1 t2]); api.toggleAt(t);
% [contractions, summary] = api.results();  api.epRecording(matFile) (show; '' = remove);  EP = api.epRecordingData();
% api.overlayChannels([1 2 3]) (overlay of the analysed range in these channels); [groups, h] = api.overlay();
% api.key('rightarrow', {'shift'}) (arrow key as typed in the force plot); api.navButton('rightarrow', true) (button under
% the force plot, true = shift + click); R = api.trend([1 3]) (trend window: these channels calculated and overlaid)
% api.openResults(file, k) (results file, analysis window k); h = api.rockerWindow() (rocker artifact window);
% api.nextFile(file) (file name of the next save / export dialog), then e.g. api.exportChannel() or a menu of a window
fig.UserData = struct('setRange', @apiSetRange, 'toggleAt', @toggleContraction, 'results', @apiResults, ...
    'setLabels', @apiSetLabels, 'labels', @apiLabels, 'zeroAt', @apiZeroAt, ...
    'epRecording', @openEP, 'epRecordingData', @apiEP, ...
    'overlayChannels', @setOverlayChannels, 'overlay', @apiOverlay, 'key', @apiKey, 'navButton', @navButton, ...
    'trend', @apiTrend, 'openResults', @openResults, 'rockerWindow', @onRockerWindow, 'nextFile', @apiNextFile, ...
    'exportChannel', @onExport, 'exportPlotData', @exportPlotData);

emptyPlots();
if ~isempty(mddFile) && ~endsWith(lower(char(mddFile)), '.mdd')   %results file (2026-10-09)
    openResults(char(mddFile));
elseif ~isempty(mddFile)
    openFile(char(mddFile));
    if ~isempty(metadata) && ~isempty(H)
        try
            Lbl = mda_labels(metadata, H.dataChannels);
        catch ME
            status(['Labels: ' ME.message]);
        end
    end
end
addlistener(axStim, 'XLim', 'PostSet', @(~,~) stimLabels());
addlistener(axOv, 'XLim', 'PostSet', @(~,~) ovTicks());   %time labels h:mm:ss of the overview (also toolbar zoom)
addlistener(axMain, 'XLim', 'PostSet', @(~,~) mainTicks()); %time labels of force / stimulus / parameter plot
if nargout > 0, figOut = fig; end          %(clearing 'fig' would clear it for the nested callbacks)


% =====================================================================================================
% callbacks
% =====================================================================================================
    function onOpen(~, ~)
        [fn, pn] = uigetfile('*.mdd', 'MyoDish data file');
        if isequal(fn, 0), return; end
        openFile(fullfile(pn, fn));
    end

    function onOpenResults(~, ~)
        [fn, pn] = uigetfile({'*.xlsx;*_info.csv;*_summary.csv;*_contractions.csv;*_contractions.csv.gz', ...
            'results of MyoDishAnalysis (*.xlsx, *_info.csv, ...)'}, 'Open results');
        if isequal(fn, 0), return; end
        openResults(fullfile(pn, fn));
    end

    function ok = openResults(file, pick)
        % results file of MyoDishAnalysis / Watch / GUI export (2026-10-09): recording, settings and analysis window
        % of the results; the contractions are detected again and compared with the file (black o = only in the file)
        ok = false;
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
        if nargin < 2 || isempty(pick)                  %analysis window: channel, range, chunk
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
        openFile(mdd);
        if isempty(H), return; end
        if ~ismember(w.channel, H.dataChannels), status(sprintf('Results: channel %d is not in %s.', w.channel, H.file)); return; end
        % settings of the results
        opts = R.options; opts.referenceBeat = [];
        hRF.Value = opts.rockerFilter;
        hDet.Value = 1 + strcmp(opts.detection, 'specific');
        hRocker.Value = strcmp(opts.rocker, 'stopped');
        hStim.Value = strcmp(opts.beats, 'stimulated');
        hXT.Value = find(strcmp({'auto', 'off', 'on'}, opts.externalTrigger), 1);
        ch = w.channel;
        hCh.Value = find(H.dataChannels == ch, 1);
        thrUser(:) = nan; zeroUser(:) = nan;
        thrUser(ch) = valueOfChannel(opts.threshold, R.channels, ch);
        zeroUser(ch) = valueOfChannel(opts.zeroForce, R.channels, ch);
        opts.threshold = 'auto'; opts.zeroForce = [];   %the GUI keeps them per channel
        showThreshold();
        if ~isempty(R.labels)
            try
                Lbl = mda_labels(R.labels, H.dataChannels);
            catch
                status('Results: labels not read.');
            end
        end
        % data window of the analysis, analysed range, contractions excluded by the user (GUI exports)
        resInfo = '';
        onLoad([], [], [w.windowFrom w.windowTo]);
        if isempty(S), return; end
        if opts.rockerFilter && ~strcmp(R.createdBy, 'MyoDishAnalysisGUI')
            rfCtx = S; rfCache = {};                    %as MyoDishAnalysis: estimated from the data window itself
        end
        range = [max(w.from, S.fromSeconds) min(w.to, S.toSeconds)];
        Tc = [];
        if ~isempty(R.contractions) && all(ismember({'channel', 't_peak'}, R.contractions.Properties.VariableNames))
            Tc = R.contractions(R.contractions.channel == ch & R.contractions.t_peak >= w.from - 1e-9 & ...
                R.contractions.t_peak <= w.to + 1e-9, :);
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
        if isempty(B), inR = false(0, 1); else, inR = B.t_peak >= range(1) & B.t_peak <= range(2); end
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

    function openFile(file)
        try
            H = mda_readMdd(file, [], [], opts);
        catch ME
            status(['Error: ' ME.message]);
            if ~isempty(getenv('MDA_DEBUG')), disp(getReport(ME, 'extended')); end
            return;
        end
        S = []; O = []; B = []; C = []; manualOff = zeros(0,1); zeroUser = nan(1, 8); thrUser = nan(1, 8); Od = []; ovXL = [];
        resOnly = []; resInfo = ''; winReq = [nan nan];
        hThrMode.Value = 1; hThr.String = '';
        rfCtx = []; rfCache = {}; rfF0 = [];
        if ~isempty(EP), EP = []; showEP(false); end     %the EP recording belongs to the previous file
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
        status(msg);
        if H.bytes < 150e6, onOverview(); end      %small files: overview right away
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
        winReq = [from to];
        hFrom.String = sprintf('%.1f', S.fromSeconds); hTo.String = sprintf('%.1f', S.toSeconds);
        % channel list with the signal range (helps to find the channels with a slice)
        lbl = cell(1, numel(S.dataChannels));
        for k = 1:numel(S.dataChannels)
            x = sort(S.force(k, :));
            r = x(max(1, round(0.995 * numel(x)))) - x(max(1, round(0.005 * numel(x))));
            lbl{k} = sprintf('Ch %d  (%.0f %sN)', S.dataChannels(k), r, mu);
        end
        hCh.String = lbl;
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
        if ~isempty(O), status('Overview: drag = load a time window, wheel = zoom, shift + wheel = move, double-click = whole file.'); end
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
        xts = {'auto', 'off', 'on'}; opts.externalTrigger = xts{hXT.Value};
        if ~isempty(S), analyze(false); end
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
        pG = uipanel(f2, 'Position', [0.7 0.215 0.29 0.21], 'Title', 'Selected group: legend, line, band', 'BackgroundColor', 'w', 'FontSize', 9);
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
        key = sprintf('%d|%.4f|%.4f|%d|%.6f', chX, range(1), range(2), numel(sel), sum(Bx.t_peak(sel)));
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
        st = Cx.stimTimes(Cx.stimTimes >= range(1) & Cx.stimTimes <= range(2));
        G.noStim = isempty(st);
        if G.noStim, G.t0 = range(1); else, G.t0 = st(1); end
        inR = Cx.t >= range(1) & Cx.t <= range(2);
        G.trT = reshape(Cx.t(inR), 1, []) - G.t0; G.trY = reshape(Cx.f(inR), 1, []);
        lab = sprintf('Ch %d, %s - %s, n = %d', chX, fmtClock(range(1), H.totalSeconds >= 3600, true), ...
            fmtClock(range(2), H.totalSeconds >= 3600, true), n);
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
            fmtClock(range(1), hrs, true), fmtClock(range(2), hrs, true), ch));
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
                s = Bx.included & Bx.t_peak >= range(1) & Bx.t_peak <= range(2);
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
        if opts.rockerFilter, Sa = rockerFiltered(optsC, c); end
        [Bx, Cx] = mda_analyzeChannel(Sa, c, [], optsC);
    end

    function k = groupsOf(c)
        % overlay groups of channel c for the analysed range of the main window
        k = [];
        if isempty(ovG), return; end
        k = find([ovG.ch] == c & arrayfun(@(G) all(abs(G.range - range) < 1e-6), ovG));
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
            xline(axO, 0, '--', 'Color', [0 0.3 1], 'HandleVisibility', 'off');
            info = [{'time course: one trace per group (bands and single contractions: mean beat only)'}, info];
        else
            L = median([ovG.pp], 'omitnan'); if isnan(L), L = 1; end
            if mode == 1
                xlim(axO, [-0.1, min(1.5, max(0.3, 0.95 * L))]);
                xline(axO, 0, '--', 'Color', [0 0.3 1], 'HandleVisibility', 'off');
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
        rg = reshape([ovG.range], 2, [])';
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
        d = {'Units', 'normalized', 'FontSize', 10, 'BackgroundColor', 'w'};
        axT = axes(f2, 'Position', [0.06 0.1 0.6 0.82]); box(axT, 'on');
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
        uicontrol(f2, d{:}, 'Style', 'pushbutton', 'String', 'Calculate', 'FontWeight', 'bold', 'Position', [x0 0.175 w 0.05], ...
            'Callback', @(~,~) calcTrend(), 'TooltipString', ['detects the contractions in the files (threshold, filters, zero force and rocker ' ...
            'filter as in the main window); results are kept, so changing parameter / window only redraws']);
        uicontrol(f2, d{:}, 'Style', 'pushbutton', 'String', 'Save figure ...', 'Position', [x0 0.125 0.145 0.042], 'Callback', @(~,~) saveTrendFigure());
        uicontrol(f2, d{:}, 'Style', 'pushbutton', 'String', 'Export data ...', 'Position', [x0+0.155 0.125 0.145 0.042], 'Callback', @(~,~) exportTrend());
        tx = uicontrol(f2, d{:}, 'Style', 'text', 'String', '', 'HorizontalAlignment', 'left', 'Position', [x0 0.005 w 0.115], 'FontSize', 8);
        hTr = struct('fig', f2, 'ax', axT, 'lbF', lbF, 'pC', pC, 'pR', pR, 'pP', pP, 'eW', eW, 'pS', pS, 'cS', cS, 'cI', cI, ...
            'cK', cK, 'cT', cT, 'tx', tx, 'pM', pM, 'eWs', eWs, 'eTm', eTm, 'tW', [tW1 tW2], 'cA', cA);
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
        R = struct('data', trData, 'roll', hTr.roll, 'title', hTr.ax.Title.String, 'legend', {{}}, 'fig', hTr.fig);
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
                if strcmp(trFiles(k).file, H.file) && all(~isnan(range)), jobs(end+1,:) = {k, range(1), range(2)}; end %#ok<AGROW>
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
        if isempty(trFiles), title(axT, 'no file'); return; end
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
        hTr.cmtTxt = gobjects(0);
        if hTr.cK.Value                                     %comments (labels only when 30 or fewer are visible, see trTicks)
            for f = 1:numel(trFiles)
                cm = trFiles(f).comments;
                if isempty(cm) || height(cm) == 0, continue; end
                tc = cm.t_file(cm.t_file >= 0 & cm.t_file <= trFiles(f).dur) + trFiles(f).offset;
                lab = cm.text(cm.t_file >= 0 & cm.t_file <= trFiles(f).dur);
                if isempty(tc), continue; end
                xs = [tc tc nan(size(tc))]'; ys = repmat([yl0(1); yl0(2); nan], 1, numel(tc));
                plot(axT, xs(:), ys(:), ':', 'Color', [0.55 0 0.75], 'HitTest', 'off');
                lab = cellfun(@(c) [c(1:min(end, 35)) '  '], lab, 'UniformOutput', false);
                ht = text(axT, tc, repmat(yl0(2), size(tc)), lab, 'Rotation', 90, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
                    'FontSize', 7, 'Color', [0.55 0 0.75], 'Interpreter', 'none', 'Clipping', 'on', 'HitTest', 'off');
                hTr.cmtTxt = [hTr.cmtTxt; ht(:)];
            end
        end
        last = trFiles(end);
        xlim(axT, [0, max(1, last.offset + last.dur)]); ylim(axT, yl0);
        ylabel(axT, sprintf('%s (%s)', pn, unit), 'Interpreter', 'none');
        if ~isempty(hp), legend(axT, hp, nmL, 'Location', 'northeast', 'FontSize', 8); end
        if have && multi
            title(axT, sprintf('Channels %s (%s), %d contractions (%d shown), %d file(s), sampling: %s', ...
                strjoin(arrayfun(@num2str, trChans, 'UniformOutput', false), ', '), rollName, height(trData), nnz(I), ...
                numel(trFiles), trSampling), 'FontWeight', 'normal', 'FontSize', 9);
        elseif have
            title(axT, sprintf('Channel %d, %d contractions (%d shown), %d file(s), sampling: %s', trChans(1), height(trData), ...
                nnz(I), numel(trFiles), trSampling), 'FontWeight', 'normal', 'FontSize', 9);
        else
            title(axT, 'press Calculate (detects the contractions in the listed files)', 'FontWeight', 'normal', 'FontSize', 9);
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
        if isfield(hTr, 'cmtTxt') && ~isempty(hTr.cmtTxt)          %comment labels: no overlapping labels
            h = hTr.cmtTxt(isgraphics(hTr.cmtTxt));
            if ~isempty(h)
                p = arrayfun(@(x) x.Position(1), h);
                [p, o] = sort(p); h = h(o);
                u = axT.Units; axT.Units = 'pixels'; wPx = axT.Position(3); axT.Units = u;
                minDx = 11 * diff(xl) / max(wPx, 1);            %about one text line (font 7) apart
                show = false(size(p)); last = -inf;
                for q = 1:numel(p)
                    if p(q) >= xl(1) && p(q) <= xl(2) && p(q) - last >= minDx, show(q) = true; last = p(q); end
                end
                set(h(show), 'Visible', 'on'); set(h(~show), 'Visible', 'off');
            end
        end
    end

    function saveTrendFigure()
        if isempty(hTr) || ~isvalid(hTr.fig), return; end
        file = askFile('image', 'trend');
        if isempty(file), return; end
        f2 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [50 50 1200 600]);
        try
            lg = hTr.ax.Legend;
            if ~isempty(lg) && isvalid(lg), c = copyobj([lg hTr.ax], f2); a = c(2); else, a = copyobj(hTr.ax, f2); end
            a.Units = 'normalized'; a.Position = [0.08 0.11 0.88 0.82];
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
        gap = 0.055; bot = 0.07; top = 0.035;
        hAll = 1 - bot - top - gap * (numel(list) - 1);
        y = 1 - top;
        for k = 1:numel(list)
            hk = hAll * w(k) / sum(w);
            switch list{k}
                case 'overview'
                    a = copyobj(axOv, f2);
                case 'force'
                    a = copyobj(axMain, f2);
                case 'parameter'
                    a = copyobj(axPar, f2);
                case 'stimuli'
                    a = axes(f2); box(a, 'on');
                    drawStim(a);
                    xlim(a, xlim(axMain)); set(a, 'XTick', axPar.XTick);
                    stimText(a);
            end
            a.UIContextMenu = [];
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
        names = {}; tabs = {};
        switch which
            case 'force'
                I = C.t >= xl(1) & C.t <= xl(2);
                t = C.t(I); t = t(:); f = C.f(I); f = f(:);
                z = mda_zeroForce(S, ch, zeroUser(ch), t);
                T = table(t, 'VariableNames', {'t_file_s'});
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
                    inR = B.t_peak >= range(1) & B.t_peak <= range(2); man = isManual(); sel = selected();
                    st = repmat({'outside the analysed range'}, numel(J), 1);
                    st(inR(J) & ~B.included(J)) = {'excluded by filter'};
                    st(inR(J) & man(J)) = {'excluded by user'};
                    st(sel(J)) = {'selected'};
                    Tc = table(B.t_peak(J), y, B.beatType(J), st, 'VariableNames', {'t_peak_s', 'peak_force_uN', 'beatType', 'status'});
                    if ~isnan(H.recordingStart), Tc.clockTime = clk(B.t_peak(J)); end
                    names{end+1} = 'contractions'; tabs{end+1} = Tc;
                end
                ts = C.stimTimes(C.stimTimes >= xl(1) & C.stimTimes <= xl(2));
                names{end+1} = 'stimuli'; tabs{end+1} = table(ts(:), 'VariableNames', {'t_stim_s'});
                if ~isempty(LE) && height(LE) > 0
                    cm = LE.isComment & LE.t_file >= xl(1) & LE.t_file <= xl(2);
                    if any(cm)
                        names{end+1} = 'comments';
                        tabs{end+1} = table(LE.t_file(cm), LE.clockTime(cm), LE.text(cm), 'VariableNames', {'t_file_s', 'clockTime', 'comment'});
                    end
                end
            case 'stimuli'
                [tS, cur, ok, ex, iv] = stimData();
                I = tS >= xl(1) & tS <= xl(2);
                if C.stimChannel == 0, cur(:) = nan; end    %external trigger pulses: no current
                T = table(tS(I), cur(I), ok(I), ex(I), iv(I), 'VariableNames', ...
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
                T = table(B.t_peak(J), v(J), sel(J), 'VariableNames', {'t_peak_s', vn, 'selected'});
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
        plot(a2, tx, art, 'Color', [0 0.3 1], 'LineWidth', 0.8);
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
        I.extra = {'createdBy', 'MyoDishAnalysisGUI'; 'channels', sprintf('%d', ch); ...
            'loadedWindow_s', sprintf('%.15g %.15g', winReq); 'analysedRange_s', sprintf('%.15g %.15g', range); ...
            'epRecording', ep};
        if isempty(I.notes), I.notes = {}; end
    end

    function onShowTable(~, ~)
        if isempty(B), return; end
        T = rangeTable();
        c = table2cell(T);
        for k = 1:numel(c)
            if isdatetime(c{k}), c{k} = char(c{k}); end
        end
        f2 = figure('Name', sprintf('Channel %d: contractions %.1f - %.1f s', ch, range(1), range(2)), 'Color', 'w', 'MenuBar', 'none');
        uitable(f2, 'Units', 'normalized', 'Position', [0 0 1 1], 'Data', c, 'ColumnName', T.Properties.VariableNames, 'RowName', []);
    end

    function onExport(~, ~)
        if isempty(B), status('Nothing to export.'); return; end
        [~, n] = fileparts(H.file);
        def = sprintf('%s_ch%d_%.0f-%.0fs.xlsx', n, ch, range(1), range(2));
        if ~isempty(apiFile)
            [pn, fn, fe] = fileparts(apiFile); fn = [fn fe]; apiFile = '';
        else
            [fn, pn] = uiputfile({'*.xlsx', 'Excel (*.xlsx)'; '*.csv', 'text (*.csv)'}, 'Export contractions', def);
            if isequal(fn, 0), return; end
        end
        T = rangeTable();
        Sm = summaryRow();
        info = guiInfo();
        % analysis window (open the results again: same data window, range and threshold)
        info.thresholds = table(1, ch, range(1), range(2), C.threshold, C.maxStimToPeak, winReq(1), winReq(2), ...
            'VariableNames', {'range','channel','from','to','threshold_uN','maxStimToPeak_s','windowFrom','windowTo'});
        if ~isempty(C.rockerFilter)                     %result of the rocker filter (as MyoDishAnalysis)
            RF = C.rockerFilter;
            info.rockerFilter = cell2table({'range1', ch, S.fromSeconds, S.toSeconds, RF.status, RF.f0, RF.artifactPP, ...
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
        def = sprintf('%s_allChannels_%.0f-%.0fs.xlsx', n, range(1), range(2));
        [fn, pn] = uiputfile({'*.xlsx', 'Excel (*.xlsx)'; '*.csv', 'text (*.csv)'}, 'All channels', def);
        if isequal(fn, 0), return; end
        status('Analysing all channels ...'); drawnow;
        try
            optsAll = opts;
            optsAll.zeroForce = zeroUser(H.dataChannels);    %NaN = Offset of the log file
            optsAll.threshold = thrOf(H.dataChannels);       %NaN = auto
            MyoDishAnalysis(H.file, [], range(1), range(2), optsAll, 'output', fullfile(pn, fn), 'quiet', true, 'metadata', Lbl);
            status(sprintf('All channels written to %s (same settings, manual exclusions not applied).', fn));
        catch ME
            status(['Error: ' ME.message]);
        end
    end

    function onCopy(~, ~)
        if isempty(B), return; end
        Sm = summaryRow();
        [~, n, e] = fileparts(H.file);
        lines = {sprintf('file\t%s', [n e]), sprintf('channel\t%d', ch), sprintf('range (s)\t%.2f\t%.2f', range(1), range(2)), ...
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
        lines{end+1} = sprintf('parameter\tmean\tSD\tn\tunit%s', repmat(sprintf('\trelative to reference'), 1, hasRef));
        for k = 1:size(PI, 1)
            lines{end+1} = sprintf('%s\t%.6g\t%.6g\t%d\t%s', PI{k,1}, Sm.([PI{k,1} '_mean']), Sm.([PI{k,1} '_SD']), Sm.([PI{k,1} '_n']), PI{k,2}); %#ok<AGROW>
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
            elseif ~isempty(S) && (inAxes(axMain) || inAxes(axStim) || inAxes(axPar))
                xlim(axMain, [S.fromSeconds S.toSeconds]);
            end
            return;
        end
        if inAxes(axMain) && ~isempty(S)
            x = clampX(axMain);
            if rbRange.Value
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
        uicontrol(f4, dd{:}, 'Style', 'pushbutton', 'String', 'Analyse', 'FontWeight', 'bold', 'Position', [x0 0.11 w0 0.045], ...
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
        hPr.tProt.Data = [num2cell(~strcmp(prP.type, 'other')), prP.type, prP.name, num2cell(round(prP.from, 2)), ...
            num2cell(round(prP.to, 2)), prP.groupBy, prP.note];
        hPr.tx.String = sprintf('%d protocol(s) found in the log file.', height(prP));
    end

    function prAddRange()
        if any(isnan(range)), hPr.tx.String = 'Select a range in the main window first.'; return; end
        hPr.tProt.Data = [hPr.tProt.Data; {true, 'manual', 'selected range', round(range(1), 2), round(range(2), 2), 'pacingFrequency', ''}];
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
        g = uigridlayout(f2, [3 5]);
        g.RowHeight = {28, '1x', 22}; g.ColumnWidth = {55, '1x', 230, 110, 80};
        uilabel(g, 'Text', 'Search:');
        ef = uieditfield(g, 'text', 'ValueChangedFcn', @(~,~) filterComments());
        try ef.ValueChangingFcn = @(~,evt) filterComments(evt.Value); catch, end   %live search (R2018b+)
        try ef.Placeholder = 'text (several words: all must occur)'; catch, end
        cb = uicheckbox(g, 'Text', 'all log entries (events, settings)', 'ValueChangedFcn', @(~,~) filterComments());
        lbl = uilabel(g, 'Text', '');
        uibutton(g, 'Text', 'Go to', 'ButtonPushedFcn', @(~,~) gotoRow());
        ut = uitable(g, 'RowName', {}, 'ColumnName', {'date / time', 'time in file', 't (s)', 'ch', 'code', 'text'}, ...
            'ColumnWidth', {140, 80, 80, 35, 110, 'auto'}, 'CellSelectionCallback', @(~,evt) selectRow(evt));
        ut.Layout.Row = 2; ut.Layout.Column = [1 5];
        if isprop(ut, 'DoubleClickedFcn'), ut.DoubleClickedFcn = @(~,evt) dblClickRow(evt); end   %R2021a+
        hint = uilabel(g, 'Text', ['Double-click a row (or select it and press Go to): loads the data around it ' ...
            '(window length = loaded window, at least 30 s). Comments are marked purple in the plots.'], 'FontColor', [0.3 0.3 0.3]);
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
            comView = []; hCom.ut.Data = cell(0, 6); return;
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
        D = cell(numel(comView), 6);
        for k = 1:numel(comView)
            j = comView(k);
            D(k,:) = {char(LE.clockTime(j)), fmtClock(LE.t_file(j), hrs, true), round(LE.t_file(j) * 10) / 10, ...
                LE.channel(j), LE.code{j}, LE.text{j}};
        end
        hCom.ut.Data = D;
        if hCom.cb.Value, what = 'entries'; else, what = 'comments'; end
        hCom.lbl.Text = sprintf('%d of %d %s', numel(comView), nnz(LE.isComment | hCom.cb.Value), what);
    end

    function selectRow(evt)
        if isempty(evt.Indices), comRow = []; else, comRow = evt.Indices(1,1); end
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
        if ishandle(hDrag), delete(hDrag); end
        hDrag = patch(ax, [x x x x], yl([1 1 2 2]), [0.2 0.5 1], 'FaceAlpha', 0.25, 'EdgeColor', [0.2 0.5 1], 'HitTest', 'off');
        set(fig, 'WindowButtonMotionFcn', @(~,~) dragMove(ax), 'WindowButtonUpFcn', @(~,~) dragEnd(ax));
    end

    function dragMove(ax)
        x = clampX(ax);
        if ishandle(hDrag), hDrag.XData = [dragX0 x x dragX0]; end
    end

    function dragEnd(ax)
        set(fig, 'WindowButtonMotionFcn', '', 'WindowButtonUpFcn', '');
        x = clampX(ax);
        if ishandle(hDrag), delete(hDrag); end
        xl = xlim(ax);
        if abs(x - dragX0) < 0.003 * diff(xl), return; end      %a click, not a drag
        r = sort([dragX0 x]);
        if ax == axMain
            range = r;
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
            if opts.rockerFilter
                [Sa, rfMsg] = rockerFiltered(optsC);
            end
            [B, C] = mda_analyzeChannel(Sa, ch, [], optsC);
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
        inR = B.t_peak >= range(1) & B.t_peak <= range(2);
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

    function T = rangeTable()
        inR = B.t_peak >= range(1) & B.t_peak <= range(2);
        man = isManual();
        T = B(inR, :);
        T.included = T.included & ~man(inR);
        T.manuallyExcluded = man(inR);
        T.contraction = (1:height(T))';
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

    function Sm = summaryRow()
        Bs = B;
        Bs.included = selected();
        Sm = mda_summarize(Bs, C, range);
        [~, n, e] = fileparts(H.file);
        Sm = addvars(Sm, {[n e]}, 'Before', 1, 'NewVariableNames', 'file');
        if ~isnan(H.recordingStart)
            Sm = mda_addLabels(Sm, Lbl, datetime(H.recordingStart + mean(range) / 86400, 'ConvertFrom', 'datenum'));
        else
            Sm = mda_addLabels(Sm, Lbl);
        end
    end

    function refresh(resetX)
        plotMain(resetX);
        plotStim();
        plotParam();
        updateSummary();
        drawEP();
    end

    function plotMain(resetX)
        xlOld = xlim(axMain);
        cla(axMain); hold(axMain, 'on');
        if isempty(C), return; end
        % force - zero force (easier to read); sensor signal if the zero force is unknown
        z0 = mda_zeroForce(S, ch, zeroUser(ch), C.t);
        hasZero = ~any(isnan(z0));
        if hasZero, fy = C.f - z0; else, fy = C.f; end
        showRaw = ~isempty(C.rockerArtifact) && any(C.rockerArtifact ~= 0);   %rocker filter: signal before
        if showRaw, fRaw = fy + C.rockerArtifact; else, fRaw = fy; end
        yl = [min([fy fRaw]) max([fy fRaw])];
        yl = yl + [-0.08 0.08] * max(1, diff(yl));
        % analysed range
        patch(axMain, range([1 2 2 1]), yl([1 1 2 2]), [1 0.96 0.75], 'EdgeColor', [0.85 0.7 0.2], 'HitTest', 'off');
        % rocker moving (one patch object with one face per interval)
        on = diff([false S.rockerOn false]);
        s1 = find(on == 1); s2 = find(on == -1) - 1;
        if ~isempty(s1)
            patch(axMain, [S.t(s1); S.t(s2); S.t(s2); S.t(s1)], repmat(yl([1 1 2 2])', 1, numel(s1)), [0.55 0.55 0.55], ...
                'FaceAlpha', 0.25, 'EdgeColor', 'none', 'HitTest', 'off');
        end
        if showRaw, plot(axMain, C.t, fRaw, 'Color', [0.72 0.72 0.72], 'LineWidth', 0.5, 'HitTest', 'off'); end
        plot(axMain, C.t, fy, 'k', 'LineWidth', 0.5, 'HitTest', 'off');
        % stimuli
        st = C.stimTimes(C.stimTimes >= S.fromSeconds & C.stimTimes <= S.toSeconds);
        if ~isempty(st)
            xs = [st st nan(size(st))]'; ys = repmat([yl(1); yl(1) + 0.04 * diff(yl); nan], 1, numel(st));
            plot(axMain, xs(:), ys(:), 'Color', [0 0.3 1], 'HitTest', 'off');
        end
        % contractions
        if ~isempty(B)
            [~, loc] = ismember(B.t_peak, C.peakTimes);
            y = fy(C.iPeaks(loc)); y = y(:);
            inR = B.t_peak >= range(1) & B.t_peak <= range(2);
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
            if any(dv)
                plot(axMain, B.t_peak(dv), y(dv), 'o', 'Color', [0.9 0 0.9], 'MarkerSize', 11, 'LineWidth', 1.5, 'HitTest', 'off');
            end
        end
        if ~isempty(resOnly)                            %opened results: contractions not detected again (black o)
            ro = resOnly(resOnly >= S.fromSeconds & resOnly <= S.toSeconds);
            plot(axMain, ro, interp1(C.t, fy, ro), 'ko', 'MarkerSize', 10, 'LineWidth', 1.2, 'HitTest', 'off');
        end
        % comments of the log file (purple; the one jumped to: solid)
        if ~isempty(LE) && height(LE) > 0
            cm = find(LE.isComment & LE.t_file >= S.fromSeconds & LE.t_file <= S.toSeconds);
            if ~isempty(cm)
                tc = LE.t_file(cm);
                xs = [tc tc nan(size(tc))]'; ys = repmat([yl(1); yl(2); nan], 1, numel(tc));
                plot(axMain, xs(:), ys(:), ':', 'Color', [0.55 0 0.75], 'LineWidth', 1, 'HitTest', 'off');
                lab = cellfun(@(c) [c(1:min(end, 45)) repmat('...', 1, numel(c) > 45) '  '], LE.text(cm), 'UniformOutput', false);
                text(axMain, tc, repmat(yl(2), size(tc)), lab, 'Rotation', 90, 'HorizontalAlignment', 'right', ...
                    'VerticalAlignment', 'bottom', 'FontSize', 7, 'Color', [0.55 0 0.75], 'Interpreter', 'none', 'Clipping', 'on', 'HitTest', 'off');
                hi = abs(tc - hiT) < 1e-6;
                if any(hi), plot(axMain, [tc(hi) tc(hi)]', repmat(yl(:), 1, nnz(hi)), '-', 'Color', [0.55 0 0.75], 'LineWidth', 2, 'HitTest', 'off'); end
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
        ttl = sprintf('Channel %d   (red = selected, orange = uncertain, grey = excluded by filter, x = excluded by you, blue = stimuli, grey background = rocker moving, purple = comments)', ch);
        if showRaw, ttl = strrep(ttl, 'purple = comments)', 'purple = comments, light grey = before rocker filter)'); end
        title(axMain, ttl, 'FontWeight', 'normal', 'FontSize', 9);
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
            plot(axPar, range, mean(v(sel), 'omitnan') * [1 1], '--', 'Color', [0.85 0 0], 'LineWidth', 1, 'HitTest', 'off');
        end
        if endsWith(plotList{k,1}, '_pctRef'), yline(axPar, 100, ':', 'HitTest', 'off'); end   %reference = 100 %
        if endsWith(plotList{k,1}, '_dRef'), yline(axPar, 0, ':', 'HitTest', 'off'); end
        unit = strrep(plotList{k,2}, 'u', mu);
        ylabel(axPar, sprintf('%s (%s)', plotList{k,1}, unit), 'Interpreter', 'none');
        mainTicks();
        xlim(axPar, xlim(axMain));
        grid(axPar, 'on');
        linkaxes([axMain axStim axPar], 'x');
    end

    function updateSummary()
        if isempty(B)
            hTable.Data = {}; hCounts.String = ''; return;
        end
        Sm = summaryRow();
        d = cell(size(PI, 1), 5);
        for k = 1:size(PI, 1)
            d(k,:) = {PI{k,1}, fmtNum(Sm.([PI{k,1} '_mean']), 4), fmtNum(Sm.([PI{k,1} '_SD']), 3), Sm.([PI{k,1} '_n']), strrep(PI{k,2}, 'u', mu)};
        end
        if ismember('APD90', B.Properties.VariableNames)  %AP parameters (EP recording)
            for k = 1:size(APP, 1)
                d(end+1,:) = {APP{k,1}, fmtNum(Sm.([APP{k,1} '_mean']), 4), fmtNum(Sm.([APP{k,1} '_SD']), 3), Sm.([APP{k,1} '_n']), APP{k,2}}; %#ok<AGROW>
            end
        end
        % whole range, independent of the rocker / stimulated filters: n = detected contractions / stimuli
        d(end+1,:) = {'extra beats', sprintf('%d', Sm.nExtraBeats), '', Sm.nDetected, 'count'};
        d(end+1,:) = {'extra beats', fmtNum(Sm.extraBeats_percent, 3), '', Sm.nDetected, '%'};
        d(end+1,:) = {'missed beats', sprintf('%d', Sm.nMissedBeats), '', Sm.nStimuli, 'count'};
        d(end+1,:) = {'missed beats', fmtNum(Sm.missedBeats_percent, 3), '', Sm.nStimuli, '%'};
        d(end+1,:) = {'uncertain (all)', sprintf('%d', Sm.nUncertain), '', Sm.nDetected, 'count'};
        d(end+1,:) = {'uncertain stimulated', sprintf('%d', Sm.nStimulatedUncertain), '', Sm.nStimulated, 'count'};
        d(end+1,:) = {'uncertain extra', sprintf('%d', Sm.nExtraBeatsUncertain), '', Sm.nExtraBeats, 'count'};
        d(end+1,:) = {'uncertain missed', sprintf('%d', Sm.nMissedBeatsUncertain), '', Sm.nStimuli, 'count'};
        if isfield(C, 'referenceBeat') && ~isempty(C.referenceBeat)    %deviating from the reference beat (whole range)
            inR = B.t_peak >= range(1) & B.t_peak <= range(2);
            nCmp = sum(inR & ~isnan(B.refMaxDeviation_SD)); nDev = sum(inR & deviating());
            pDev = nan; if nCmp > 0, pDev = 100 * nDev / nCmp; end
            d(end+1,:) = {sprintf('deviating (> %g SD)', refThr), sprintf('%d', nDev), '', nCmp, 'count'};
            d(end+1,:) = {sprintf('deviating (> %g SD)', refThr), fmtNum(pDev, 3), '', nCmp, '%'};
        end
        % 2026-10-06: column '% ref' (mean relative to the reference contractions; diastolic: difference) if the channel has
        % a reference beat
        hasRef = isfield(C, 'referenceBeat') && ~isempty(C.referenceBeat);
        if hasRef
            rc = repmat({''}, size(d, 1), 1);
            for k = 1:size(PI, 1), rc{k} = relCell(Sm, PI{k,1}); end
            d = [d(:,1:2), rc, d(:,3:end)];
            cn = {'parameter', 'mean', '%ref', 'SD', 'n', 'unit'}; cw = {90, 52, 46, 54, 26, 44};
        else
            cn = {'parameter', 'mean', 'SD', 'n', 'unit'}; cw = {108, 66, 60, 38, 42};
        end
        if numel(hTable.ColumnName) ~= numel(cn)        %column count changes: new table (the header is not redrawn reliably)
            pT = hTable.Position; delete(hTable);
            hTable = uitable(pnl, 'Units', 'normalized', 'Position', pT, 'RowName', [], 'ColumnName', cn, 'ColumnWidth', cw, 'FontSize', 9);
        end
        hTable.ColumnWidth = cw;
        hTable.Data = d;
        if C.stimChannel == 0, sSrc = ' (ext. trigger)'; else, sSrc = ''; end
        txt = sprintf(['Range %.2f - %.2f s (%.1f s)\n%d of %d contractions selected (%d stimulated, %d extra)\n' ...
            '%d stimuli%s (%.2f Hz), %d without contraction\n%s'], range(1), range(2), diff(range), Sm.nContractions, Sm.nDetected, ...
            Sm.nStimulated, Sm.nExtraBeats, Sm.nStimuli, sSrc, Sm.stimFrequency, Sm.nMissedBeats, labelLine(Sm));
        %(the String of a text control reads back as a padded char matrix: append before assigning, not to hCounts.String)
        if ~isempty(C.rockerFilter), txt = sprintf('%s\n%s', txt, rockerLine(C.rockerFilter)); end
        if isfield(C, 'referenceBeat') && ~isempty(C.referenceBeat)
            w = {'abs.', 'norm.', 'abs. or norm.'};
            txt = sprintf('%s\nreference (%d, %s): deviating > %g SD (%s)%s', txt, C.referenceBeat.n, ...
                C.referenceBeat.align, refThr, w{refWhich}, repmat(', excl.', 1, refExclude));
        end
        hCounts.String = txt;
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
        rows = find(B.included & B.t_peak >= range(1) & B.t_peak <= range(2) & ~isManual());   %selection (without the deviation filter)
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
            inR = B.t_peak >= range(1) & B.t_peak <= range(2);
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
        if isempty(C) || isempty(S), return; end
        xlim(axStim, xlim(axMain));
        hStimTxt = stimText(axStim);
    end

    function drawStim(axT)
        yyaxis(axT, 'right'); cla(axT); ylabel(axT, '');
        yyaxis(axT, 'left'); cla(axT); hold(axT, 'on'); ylabel(axT, '');
        axT.YAxis(1).Color = [0.85 0 0]; axT.YAxis(2).Color = [0 0.3 1];
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
        if any(~ok), plot(axT, tS(~ok), cur(~ok), 'x', 'Color', [0.8 0 0.8], 'MarkerSize', 5, 'HitTest', 'off'); end
        ylim(axT, [0 max(1, max(cur)) * 1.35]);
        if isExt, ylabel(axT, 'ext.'); set(axT, 'YTick', []); else, ylabel(axT, 'mA'); set(axT, 'YTickMode', 'auto'); end
        axT.YAxis(1).Exponent = 0;
        yyaxis(axT, 'right');
        plot(axT, tS, iv, '.', 'Color', [0 0.3 1], 'MarkerSize', 9, 'HitTest', 'off');
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
        ok = S.stim.currentReached(J); ok = ok(:);
        ex = S.stim.isExtraPulse(J); ex = ex(:);
        iv = [nan; diff(tS)] * 1000;
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
        lab(~ok(v)) = strcat(lab(~ok(v)), ' ?!');
        h = text(axT, tS(v), min(cur(v) + 0.04 * diff(ylL), ylL(2)), lab, 'Color', [0.85 0 0], ...
            'FontSize', 7, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'HitTest', 'off');
        w = v(~isnan(iv(v)));
        if ~isempty(w)
            yyaxis(axT, 'right');
            h2 = text(axT, tS(w), iv(w), arrayfun(@(k) sprintf('  %.0f', iv(k)), w, 'UniformOutput', false), ...
                'Color', [0 0.3 1], 'FontSize', 7, 'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'HitTest', 'off');
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
        if ~isempty(S)
            patch(axOv, [S.fromSeconds S.toSeconds S.toSeconds S.fromSeconds], yl([1 1 2 2]), [0.2 0.5 1], 'FaceAlpha', 0.3, 'EdgeColor', [0 0.3 1], 'HitTest', 'off');
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
        if ~any(isnan(zOv)), zs = 'force - zero force'; else, zs = 'sensor signal'; end
        hrs = O.totalSeconds >= 3600;
        if isempty(ovXL)
            ws = sprintf('whole file (%s)', fmtClock(O.totalSeconds, hrs, true));
        else
            ws = sprintf('%s - %s of %s', fmtClock(xlv(1), hrs, true), fmtClock(xlv(2), hrs, true), fmtClock(O.totalSeconds, hrs, true));
        end
        title(axOv, sprintf('Channel %d, %s, time in %s, %s   (green = rocker at rest, blue = loaded window, purple = comments)', ...
            ch, ws, unit, zs), 'FontWeight', 'normal', 'FontSize', 9);
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
        set(axMain, 'XTick', tk); set(axStim, 'XTick', tk);
        set(axPar, 'XTick', tk, 'XTickLabel', tl);
        if relTime
            xl = sprintf('time from the start of the loaded window (%s; window starts at %.1f s in the file)', unit, S.fromSeconds);
        else
            xl = sprintf('time in file (%s)', unit);
        end
        xlabel(axPar, xl);
        if epFrac > 0 && isvalid(axEPs)                  %EP traces below: same ticks, labels at the bottom
            set(axEPv, 'XTick', tk, 'XTickLabel', {}); set(axEPs, 'XTick', tk, 'XTickLabel', tl);
            xlabel(axEPs, xl);
        end
    end

    function unit = ovTicks()
        % time axis of the overview as h:mm(:ss) or m:ss, tick step adapted to the zoom level
        unit = '';
        if isempty(O) || ~isvalid(axOv), return; end
        [tk, tl, unit] = timeTicks(xlim(axOv), O.totalSeconds);
        set(axOv, 'XTick', tk, 'XTickLabel', tl);
    end

    function emptyPlots()
        cla(axMain); cla(axPar); plotStim();
        if epFrac > 0, cla(axEPv); cla(axEPs); end
        hTable.Data = {}; hCounts.String = '';
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
        status('EP recording: reading and aligning the stimuli ...'); drawnow;
        try
            EPnew = mda_readEPRecording(epFile, H, opts, 'mddChannel', ch);
        catch ME
            status(['EP recording: ' ME.message]); return;
        end
        EP = EPnew;
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
        EP = []; epMarks = []; showEP(false);
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
                'Position', [0.77, 44 * px, 0.225, (dH - 52) * px]);
            hEPclose = uicontrol(fig, dflt{:}, 'Style', 'pushbutton', 'String', 'Remove EP recording', ...
                'Position', [0.77, 8 * px, 0.12, 30 * px], 'Callback', @onCloseEP);
            epLis = addlistener(axMain, 'XLim', 'PostSet', @(~,~) drawEP());
        else
            M = epFig0;
            delete(epLis); epLis = [];
            delete([axEPv axEPs hEPtxt hEPclose]);
            axEPv = gobjects(0); axEPs = gobjects(0); hEPtxt = gobjects(0); hEPclose = gobjects(0);
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
            [tv, v] = epSegment(EP.V, xl);
            [ts, sv] = epSegment(EP.stim, xl);
            plot(axEPv, tv, v, 'Color', [0 0.3 0.75], 'LineWidth', 0.5, 'HitTest', 'off');
            plot(axEPs, ts, sv, 'Color', [0.8 0 0], 'LineWidth', 0.5, 'HitTest', 'off');
            set([axEPv axEPs], 'XLimMode', 'manual', 'XLim', xl);
            ylabel(axEPv, sprintf('%s (%s)', EP.labelV, EP.unitV)); ylabel(axEPs, sprintf('%s (%s)', EP.labelStim, EP.unitStim));
            if isempty(v), title(axEPv, 'no EP data in this time range', 'FontWeight', 'normal', 'FontSize', 9);
            else, title(axEPv, ''); end
            info = EP.info;
            if drawAPMarks(xl), info{end+1} = 'AP: ^ upstroke, v V_max, o APD25/50/90'; end
            hEPtxt.String = info;
            mainTicks();
        catch ME
            status(['EP plot: ' ME.message]);
        end
        epBusy = false;
    end

    function [t, y] = epSegment(x, xl)
        % samples of x (uniform, EP.t0 + (k-1) * EP.dt in file time) within xl; > 20000 samples: min/max per bin
        n = numel(x);
        k1 = max(1, floor((xl(1) - EP.t0) / EP.dt) + 1); k2 = min(n, ceil((xl(2) - EP.t0) / EP.dt) + 1);
        if k2 < k1, t = []; y = []; return; end
        k = (k1:k2)';
        nb = 4000;
        if numel(k) <= 5 * nb
            t = EP.t0 + (k - 1) * EP.dt; y = double(x(k)); y = y(:);
        else
            m = floor(numel(k) / nb) * nb; k = k(1:m);
            X = reshape(double(x(k)), [], nb);
            mn = min(X, [], 1); mx = max(X, [], 1);
            tb = EP.t0 + (k(1:size(X,1):end) - 1) * EP.dt;
            t = reshape([tb(:)'; tb(:)' + (size(X,1) - 1) * EP.dt], [], 1);
            y = reshape([mn; mx], [], 1);
        end
    end

    function status(msg)
        hStatus.String = msg;
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
        ut = uitable(hLblFig, 'Units', 'normalized', 'Position', [0.01 0.2 0.98 0.78], 'RowName', [], 'FontSize', 10);
        showLabels(ut, Lbl);
        b = {'Style', 'pushbutton', 'Units', 'normalized', 'FontSize', 10};
        uicontrol(hLblFig, b{:}, 'String', 'Apply and close', 'Position', [0.01 0.03 0.13 0.1], 'Callback', @(~,~) applyLabels(ut, true));
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

    function apiSetRange(r)
        range = sort(r(1:2));
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

function [ticks, labels, unit] = timeTicks(xl, tMax)
% tick positions (s) and labels for a time axis in seconds: h:mm (h:mm:ss when zoomed in) if the axis reaches 1 h or
% more, otherwise m:ss; decimals of the seconds for steps < 1 s; about 4-10 ticks
steps = [0.05 0.1 0.2 0.5 1 2 5 10 15 30 60 120 300 600 900 1800 3600 7200 10800 21600 43200];
k = find(diff(xl) ./ steps <= 10, 1);
if isempty(k), k = numel(steps); end
st = steps(k);
ticks = (ceil(xl(1) / st) : floor(xl(2) / st)) * st;
hrs = max(abs(tMax), max(abs(xl))) >= 3600;
withSec = st < 60 || ~hrs;
dec = 0;
if st < 0.1, dec = 2; elseif st < 1, dec = 1; end
labels = arrayfun(@(t) fmtClock(t, hrs, withSec, dec), ticks, 'UniformOutput', false);
if ~hrs
    unit = 'm:ss';
elseif withSec
    unit = 'h:mm:ss';
else
    unit = 'h:mm';
end
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
t = [{'Comments ...: searchable list of the comments in the log file (date / time, time in the file, text; option: all log entries). Double-click a row (or Go to) to load the data around it. Comments are marked purple in the plots.', ...
      '', ...
      'Overview: min/max of the selected channel over the whole recording (green = rocker at rest). Drag in it to load a time window (or type From/To and press Load).', ...
      '', ...
      'Force plot: red = selected contractions, orange = uncertain contractions (high sensitivity: neither locked to the stimuli nor large compared with the other contractions; not counted with high specificity), grey = excluded by the filters (rocker / stimulated only), x = excluded by you, blue ticks = stimuli, grey background = rocker moving, yellow = analysed range.', ...
      'Cursor in the force plot: "drag = select time range" or "click = exclude / include contraction". Zoom/pan: mouse wheel or figure toolbar (switch the tool off afterwards).', ...
      'Arrow keys (click into a plot first) and the buttons under the force plot change the loaded window (= blue selection in the overview and analysed range; read again): left / right = move it by half its length, shift + left / right (shift + click) = extend it by half its length on that side, up / down (middle buttons) = zoom in / out (half / twice its length). Mouse pointer over the overview: the keys move its time axis instead; a zoomed overview moves along. The mouse wheel zooms only the display.', ...
      '', ...
      'Overlay contractions: selected contractions + mean, aligned at the stimulus (t = 0, default) or the peak, or the time course of the analysed range (t = 0 at the first stimulus of each group). Press again (or Add current selection in the overlay window) to add another selection as a new group; Channels (same range) ...: tick channels to add them for the analysed range (same settings, threshold and zero force of each channel). Per group (list): legend text, colour, line width, line style and a transparent band (mean +- SD, +- SEM or range). Title, axis labels and legend position are editable below the plot (empty = automatic); Edit figure ... opens a copy with the MATLAB plot tools.', ...
      '', ...
      'Trend ...: rolling mean / median of a parameter over long periods and several files in a row (_0, _1, ...); sampling: all contractions, short windows or rocker stops. Channel list: one channel, or several channels ... (checkboxes) = overlaid, one colour per channel (the file is read once for all of them).', ...
      '', ...
      'Save / Export (menu or right click on a plot): plots as .png / .jpg / .tif / .fig, plotted data (visible time range) as .xlsx / .csv / .txt; overview: picture only. Every data export contains the table info (version, recording, all settings, threshold and zero force of the channel, window and range).', ...
      '', ...
      'Open results ...: a results file of MyoDishAnalysis, the watcher or an export of the GUI (.xlsx, <name>_info.csv, _summary.csv, _contractions.csv): the recording (path in the file; otherwise next to the results file or asked for), the settings and the analysis window (channel, data window, analysed range; several: list) are restored, the contractions are detected again and compared with the file (status line; black o = contraction of the file not found again, e.g. other version). Contractions excluded by you in an export are excluded again.', ...
      '', ...
      'Labels ...: labels per channel (setupID, sliceID, species, sampleID, sampleGroup, sliceGroup, tissue, treatment, concentration, concentrationUnit, daysInCulture, cultureStart, comment, analyst) - columns of the exported tables; saved as <name>_labels.csv next to the .mdd file and loaded automatically.', ...
      '', ...
      'Detection: peaks with a prominence >= threshold (auto: 0.3 x typical amplitude, >= 30 uN; per channel: auto or a manual value, kept when you switch channels and used for All channels, Protocols and Trend). A contraction within 25 ms ... min(stimulus interval, 1 s) after a stimulus of the channel is "stimulated", otherwise "extra". Stimuli (list next to "only stimulated contractions"): the MyoDish pulses of the channel, or the external trigger pulses of the status channel (external stimulator at the external controller unit, which carries one chamber: any data channel); auto = external trigger pulses if the loaded window has no MyoDish pulses.', ...
      '', ...
      'Reference beat (right click in the force plot): the mean shape (+- SD) of the selected contractions becomes the reference of the channel. Every contraction is compared with it, aligned at the stimulus (default; a changed latency counts, contractions without stimulus at the 50 % upstroke) or at the 50 % upstroke (shape only; reference window): refCorrelation (shape correlation), refRMSDeviation_SD (overall) and refMaxDeviation_SD (largest local deviation) in SD of the reference, each also normalized (...Norm: both scaled to amplitude 1 = shape only). Deviating contractions (> x SD) are circled magenta, counted in the table and can be excluded (reference window). Save/load a reference to apply it to other files. Every parameter is also given relative to the mean of the reference contractions (column %ref in the table; <parameter>_pctRef in tables, lower plot, trend and exports; diastolic force: difference in uN, _dRef).', ...
      '', ...
      '+ EP recording ...: LabChart export (.mat) of an electrophysiological recording made in parallel, e.g. sharp electrode (voltage + stimulation channel; default: same name as the .mdd file). It is aligned to the stimuli of the .mdd file (stimulus pattern; on constant pacing also stimulus current and clock times; clock drift corrected) and shown below the plots with the same time axis. The text right of the traces gives the matched stimuli and the offset - check it if marked CHECK. Remove EP recording hides it.', ...
      '', ...
      'AP parameters (EP recording, mda_analyzeAP), per contraction: AP_dVdtMax (V/s, max. upstroke velocity), AP_RMP (mV, median over 10 ms before the stimulus artefact), AP_Vmax (mV, peak), APD25/50/90 (ms, activation = time of dV/dt max --> 25/50/90 % repolarization). Stimulus artefact = pulse in the stimulation channel (biphasic pulse incl. pause = one pulse) until V_m is no longer saturated and |dV/dt| < 20 V/s; the stimulus onset is the stimulus time. If the upstroke lies within the artefact (foot of the upstroke not near RMP), dV/dt max, V_max, APD25 and APD50 are NaN and APD90 is measured from the stimulus onset (approximate, AP_note). Each AP is evaluated up to the next stimulus (fusion: NaN, note). Markers (<= 60 contractions visible): grey = artefact, green line = RMP, ^ upstroke, v V_max, o APD25/50/90.', ...
      '', ...
      'Remove rocker artifact: while the rocker moves, each sensor shows a periodic signal (rocker frequency, 60 rpm = 1.21 Hz). It is estimated per channel between the contractions (+-60 s around the window) and subtracted; light grey = signal before. Not possible (message): rocker frequency not found, no periodic artifact, too little time between the contractions (fast pacing). The setting also applies to All channels, Trend and exports. Rocker artifact ... (button, menu Save / Export, right click in the force plot): extra window with the signal before / after the filter and the removed artifact (also if the filter is off); menu: save as figure, export the data of the visible time range.', ...
      '', 'Parameters:'}, ...
      cellfun(@(n, u, d) sprintf('%s (%s): %s', n, u, d), P(:,1)', P(:,2)', P(:,3)', 'UniformOutput', false)];
end
