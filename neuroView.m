function neuroView()
% NEUROVIEW Creates a unified GUI to visualize raw TIFF movies or pre-processed neural data.
%
%   This GUI merges the functionality of two separate tools into one. It can
%   operate in two distinct modes, selectable via a dropdown menu:
%
%   1. TIFF Viewer Mode:
%      - Loads single or multi-file TIFFs (trials).
%      - Stitches multi-ROI (mesoscope) data on the fly.
%      - Allows for dF/F calculation, temporal averaging, and spatial smoothing.
%      - ENHANCED: Now includes detrending and grid-based visualization.
%
%   2. Neural Data Viewer Mode:
%      - Loads extracted fluorescence traces ('psths') and cell coordinates.
%      - Visualizes activity as a scatter plot of cells, an interpolated grid, or as area averages.
%      - Includes processing options like neuropil correction and detrending.
%
%   Usage:
%   1. Run this function in MATLAB.
%   2. Select the desired mode ('TIFF Viewer' or 'Neural Data Viewer').
%   3. Use the appropriate 'Load' buttons for the selected mode.
%   4. Set processing parameters and click "Play Movie" or "Plot Average".
%   5. The movie player is unified with all features, including saving the
%      movie or the full application state.
%
%   This function is compatible with MATLAB R2016b and later.

% --- Main State Variables ---
isSwitchingContext = false; % Guard flag to prevent caching during programmatic UI updates
appState = struct(); % Master state holder
appState.currentMode = 'TIFF'; % 'TIFF' or 'Neural'

% Mode-specific data
appState.TIFF = struct('fullFilePath','','selectedFolderPath','','fileBaseName','',...
    'isFolderMode',false,'roiData',[],'metadataString','','dataAspectRatio',[1 1 1],...
    'x_pixels_per_unit',1,'y_pixels_per_unit',1,'parsedNumPlanes',0,...
    'parsedNumChannels',0, 'nativeFrameRate', 30, 'pixelWidth', 512, 'pixelHeight', 512);
appState.Neural = struct('dataFilePath','','coordsFilePath','','tiffFolderPath','',...
    'vareaFilePath','','psthsData',[],'psthsnpData',[],'cellCoords',[],'vareaData',[],...
    'numNeurons',0,'numTimepoints',0,'numTrials',0,'metadataString','',...
    'nativeFrameRate',30,'plotXLim',[0 1],'plotYLim',[0 1],'pixelWidth',512,...
    'pixelHeight',512,'x_pixels_per_um',1,'y_pixels_per_um',1);

% Shared state & context management
appState.uiStateCache = struct(); % To save UI settings on mode switch
appState.sessionCache = struct('data', [], 'fingerprint', []); % For caching processed data
appState.sessionState = []; % Snapshot of appState before loading a file state
appState.loadedStateSnapshot = []; % The state loaded from a file
appState.sessionMode = 'TIFF'; % Remembers the mode of the current session when viewing a loaded state

% --- GUI Setup ---
hFig = figure('Name', 'NeuroView - Unified Viewer', ...
    'NumberTitle', 'off', 'Position', [400 200 450, 750], 'MenuBar', 'none', ...
    'Resize', 'off', 'Color', [0.94 0.94 0.94]);

% --- Mode Selector ---
uicontrol('Style', 'text', 'String', 'Operating Mode:', 'Position', [60 710 120 20], ...
    'FontSize', 11, 'FontWeight', 'bold', 'HorizontalAlignment','right',...
    'BackgroundColor', [0.94 0.94 0.94]);
hModeSelector = uicontrol('Style', 'popupmenu', 'String', {'TIFF Viewer', 'Neural Data Viewer'}, ...
    'Position', [190 715 150 20], 'FontSize', 10, 'Callback', @modeSwitchCallback);

% --- OPERATING CONTEXT SWITCH ---
hContextPanel = uibuttongroup('Parent', hFig, 'Title', 'Operating Context', ...
    'Units', 'pixels', 'Position', [10 660 430 45], 'FontSize', 9);
hContextSession = uicontrol('Parent', hContextPanel, 'Style', 'radiobutton', 'String', 'Current Session', ...
    'Position', [20 5 150 20], 'Value', 1, 'BackgroundColor', [0.94 0.94 0.94]);
hContextLoaded = uicontrol('Parent', hContextPanel, 'Style', 'radiobutton', 'String', 'Loaded State', ...
    'Position', [250 5 150 20], 'Value', 0, 'Enable', 'off', 'BackgroundColor', [0.94 0.94 0.94]);
set(hContextPanel, 'SelectionChangedFcn', @switchOperatingContextCallback);


% --- File Loading Panels ---
hTiffLoadPanel = uipanel('Parent', hFig, 'Title', 'TIFF Data Loading', ...
    'Units', 'pixels', 'Position', [10 540 430 110], 'FontSize', 10);
uicontrol('Parent', hTiffLoadPanel, 'Style', 'pushbutton', 'String', 'Select File', ...
    'Position', [10 40 90 30], 'FontSize', 10, 'Callback', @selectFileCallback_TIFF);
uicontrol('Parent', hTiffLoadPanel, 'Style', 'pushbutton', 'String', 'Select Folder', ...
    'Position', [105 40 90 30], 'FontSize', 10, 'Callback', @selectFolderCallback_TIFF);
uicontrol('Parent', hTiffLoadPanel, 'Style', 'pushbutton', 'String', 'Load Areas', ...
    'Position', [200 40 90 30], 'FontSize', 10, 'Callback', @loadVareaCallback);
uicontrol('Parent', hTiffLoadPanel, 'Style', 'pushbutton', 'String', 'Load State / Movie', ...
    'Position', [295 40 125 30], 'FontSize', 10, 'Callback', @loadStateCallback);
hReloadDataCheckbox_Tiff = uicontrol('Parent', hTiffLoadPanel, 'Style', 'checkbox', 'String', 'Reload raw data from paths', ...
    'Position', [295 10 130 20], 'Value', 0, 'BackgroundColor', [0.94 0.94 0.94]);

hNeuralLoadPanel = uipanel('Parent', hFig, 'Title', 'Processed Neural Data Loading', ...
    'Units', 'pixels', 'Position', [10 540 430 110], 'Visible', 'off', 'FontSize', 10);
uicontrol('Parent', hNeuralLoadPanel, 'Style', 'pushbutton', 'String', 'Load Data', ...
    'Position', [5 40 80 30], 'FontSize', 10, 'Callback', @loadDataCallback_Neural);
uicontrol('Parent', hNeuralLoadPanel, 'Style', 'pushbutton', 'String', 'Load Coords', ...
    'Position', [90 40 80 30], 'FontSize', 10, 'Callback', @loadCoordsCallback_Neural);
uicontrol('Parent', hNeuralLoadPanel, 'Style', 'pushbutton', 'String', 'Load TIFFs', ...
    'Position', [175 40 80 30], 'FontSize', 10, 'Callback', @loadTiffCallback_Neural, ...
    'TooltipString', 'Load original TIFF folder to get frame rate and FOV');
uicontrol('Parent', hNeuralLoadPanel, 'Style', 'pushbutton', 'String', 'Load Areas', ...
    'Position', [260 40 80 30], 'FontSize', 10, 'Callback', @loadVareaCallback);
uicontrol('Parent', hNeuralLoadPanel, 'Style', 'pushbutton', 'String', 'Load State', ...
    'Position', [345 40 80 30], 'FontSize', 10, 'Callback', @loadStateCallback);
hReloadDataCheckbox_Neural = uicontrol('Parent', hNeuralLoadPanel, 'Style', 'checkbox', 'String', 'Reload raw data from paths', ...
    'Position', [315 10 110 20], 'Value', 0, 'BackgroundColor', [0.94 0.94 0.94]);


% --- Main Text Display ---
hText = uicontrol('Style', 'edit', 'String', 'Welcome! Select a mode and load data to begin.', ...
    'Position', [40 290 370 240], 'FontSize', 10, 'HorizontalAlignment', 'left', ...
    'Enable', 'on', 'Max', 2, 'Min', 0);