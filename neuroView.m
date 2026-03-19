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
statusStepTic = []; % For appendToStatusTimed: elapsed since last reset or last timed message
appState = struct(); % Master state holder
appState.currentMode = 'TIFF'; % 'TIFF' or 'Neural'

% Mode-specific data
appState.TIFF = struct('fullFilePath','','selectedFolderPath','','fileBaseName','',...
    'isFolderMode',false,'roiData',[],'metadataString','','dataAspectRatio',[1 1 1],...
    'x_pixels_per_unit',1,'y_pixels_per_unit',1,'parsedNumPlanes',0,...
    'parsedNumChannels',0, 'nativeFrameRate', 30, 'pixelWidth', 512, 'pixelHeight', 512, ...
    'folderFileCount', 0);
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
% Four-slot architecture additions
appState.loadedState = struct('TIFF', [], 'Neural', []); % Dedicated loaded slots
appState.activeLoadedMode = ''; % 'TIFF' or 'Neural' when Loaded context is active
appState.loadedCache = struct('TIFF', struct('data', [], 'fingerprint', []), ...
                              'Neural', struct('data', [], 'fingerprint', []));
appState.sessionUiCache = struct('TIFF', [], 'Neural', []); % Explicit session UI snapshots
appState.sessionMode = 'TIFF'; % Remembers the mode of the current session when viewing a loaded state
% Export settings (session-scoped)
appState.exportGamma = struct('mp4', 1.0, 'avi', 1.0); % 1.0 = no correction (avoids export flicker)

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
% Info label to disambiguate which slot/mode is active
hContextInfoLabel = uicontrol('Parent', hContextPanel, 'Style', 'text', 'String', 'Session: TIFF', ...
    'Position', [20 25 390 15], 'HorizontalAlignment', 'left', 'BackgroundColor', [0.94 0.94 0.94]);
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
hMotionCorrectCheckbox = uicontrol('Parent', hTiffLoadPanel, 'Style', 'checkbox', 'String', 'Motion correct', ...
    'Position', [10 10 120 20], 'Value', 0, 'BackgroundColor', [0.94 0.94 0.94], ...
    'TooltipString', 'Register frames to first frame (phase correlation) before averaging/playback');
hReloadDataCheckbox_Tiff = uicontrol('Parent', hTiffLoadPanel, 'Style', 'checkbox', 'String', 'Reload raw data', ...
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

% --- Unified Processing Panel ---
hProcessingPanel = uipanel('Parent', hFig, 'Title', 'Processing Options', ...
    'Units', 'pixels', 'Position', [10 80 430 200], 'FontSize', 10);
% Line 1
hPlaneLabel = uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', 'Plane:', 'Position', [10 150 50 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94]);
hPlaneDropdown = uicontrol('Parent', hProcessingPanel, 'Style', 'popupmenu', 'String', {'-'}, 'Position', [70 150 50 20]);
hChannelLabel = uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', 'Channel:', 'Position', [130 150 60 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94]);
hChannelDropdown = uicontrol('Parent', hProcessingPanel, 'Style', 'popupmenu', 'String', {'-'}, 'Position', [200 150 50 20]);
hNeuropilCoeffLabel = uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', 'Neuropil (c):', 'Position', [10 150 80 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94], 'Visible', 'off');
hNeuropilCoeffInput = uicontrol('Parent', hProcessingPanel, 'Style', 'edit', 'String', '0.7', 'Position', [100 150 50 20], 'Visible', 'off');
uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', 'Rolling Avg (t):', 'Position', [280 150 80 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94]);
hRollingAvgInput = uicontrol('Parent', hProcessingPanel, 'Style', 'edit', 'String', '1', 'Position', [370 150 40 20]);
% Line 2
hDetrendCheckbox = uicontrol('Parent', hProcessingPanel, 'Style', 'checkbox', 'String', 'Detrend', 'Position', [15 120 70 20], 'Value', 0, 'BackgroundColor', [0.94 0.94 0.94], 'Visible', 'off');
hDetrendWindowLabel = uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', 'Win (min):', 'Position', [80 116 60 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94], 'Visible', 'off');
hDetrendWindowInput = uicontrol('Parent', hProcessingPanel, 'Style', 'edit', 'String', '1', 'Position', [145 120 30 20], 'Visible', 'off');
hForcePositiveCheckbox = uicontrol('Parent', hProcessingPanel, 'Style', 'checkbox', 'String', 'Force Positive F', 'Position', [190 120 150 20], 'Value', 1, 'BackgroundColor', [0.94 0.94 0.94], 'Visible', 'off');
hSmoothingLabel = uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', ['Smoothing (' char(956) 'm):'], 'FontSize',8, 'Position', [280 120 80 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94]);
hSmoothingWindowInput = uicontrol('Parent', hProcessingPanel, 'Style', 'edit', 'String', '0', 'Position', [370 120 40 20]);
% Line 3
uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', 'Trials:', 'Position', [20 90 50 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94]);
hTrialInput = uicontrol('Parent', hProcessingPanel, 'Style', 'edit', 'String', ':', 'Position', [80 90 205 20]);
uicontrol('Parent', hProcessingPanel, 'Style', 'pushbutton', 'String', '+', 'Position', [290 90 20 20], 'FontSize', 8, 'Callback', @(~,~) openMultiLineEditor(hTrialInput, 'Trial Selection'));
% TIFF: optional frame cap for faster iteration
hMaxFramesLabel = uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', 'Max Frames:', 'FontSize',7, 'Position', [320 90 60 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94]);
hMaxFramesInput = uicontrol('Parent', hProcessingPanel, 'Style', 'edit', 'String', '', 'Position', [385 90 40 20]);
% Line 4
uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', 'Display Mode:', 'Position', [0 60 70 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94]);
hDisplayMode = uicontrol('Parent', hProcessingPanel, 'Style', 'popupmenu', 'String', {'Raw/Corrected', 'dF/F (Initial Frames)', 'dF/F (Median)', 'dF/F (Reference Trials)'}, ...
    'Position', [80 60 150 20], 'Callback', @updateDisplayMode);
hDivideByF0Checkbox = uicontrol('Parent', hProcessingPanel, 'Style', 'checkbox', 'String', 'Divide by F0', 'Position', [240 60 100 20], 'Value', 1, 'BackgroundColor', [0.94 0.94 0.94], 'Visible', 'off');
% Line 5
hInitialFramesLabel = uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', 'Frames:', 'Position', [20 30 50 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94], 'Visible', 'off');
hInitialFramesInput = uicontrol('Parent', hProcessingPanel, 'Style', 'edit', 'String', '10', 'Position', [80 30 40 20], 'Visible', 'off');
hRefTrialsLabel = uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', 'Ref Trials:', 'Position', [5 30 70 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94], 'Visible', 'off');
hRefTrialsInput = uicontrol('Parent', hProcessingPanel, 'Style', 'edit', 'String', '[]', 'Position', [80 30 305 20], 'Visible', 'off');
hRefTrialsExpandBtn = uicontrol('Parent', hProcessingPanel, 'Style', 'pushbutton', 'String', '+', 'Position', [390 30 20 20], 'FontSize', 8, 'Callback', @(~,~) openMultiLineEditor(hRefTrialsInput, 'Reference Trials'), 'Visible', 'off');
hFrameByFrameCheckbox = uicontrol('Parent', hProcessingPanel, 'Style', 'checkbox', 'String', 'Frame-wise Subtraction', 'Position', [80 5 180 20], 'Value', 0, 'BackgroundColor', [0.94 0.94 0.94], 'Visible', 'off');


% --- Action Buttons ---
uicontrol('Style', 'pushbutton', 'String', 'Show Info', 'Position', [40 40 120 30], 'FontSize', 10, 'Callback', @showInfoCallback);
uicontrol('Style', 'pushbutton', 'String', 'Plot Average', 'Position', [165 40 120 30], 'FontSize', 10, 'Callback', @plotAvgCallback);
uicontrol('Style', 'pushbutton', 'String', 'Play Movie', 'Position', [290 40 120 30], 'FontSize', 10, 'Callback', @playMovieCallback);

% --- Initialize UI State ---
cacheCurrentUIState(appState.currentMode);
updateDisplayMode();

%% --- TOP LEVEL CALLBACKS (Mode Switching, Loading, Actions) ---

    function modeSwitchCallback(src, ~)
        % 1. Cache the UI state of the outgoing mode, ONLY if not in a context switch
        if ~isSwitchingContext
            cacheCurrentUIState(appState.currentMode);
            appState.sessionUiCache.(appState.currentMode) = harvestUIStateForMode(appState.currentMode);
        end
        
        % 2. Determine the new mode
        newModeIndex = get(src, 'Value');
        if newModeIndex == 1
            appState.currentMode = 'TIFF';
        else
            appState.currentMode = 'Neural';
        end
        
        % 3. Update UI visibility based on the new mode
        isTiffMode = strcmp(appState.currentMode, 'TIFF');
        set(hTiffLoadPanel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hNeuralLoadPanel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        
        % --- Show/hide mode-specific processing controls ---
        % TIFF-specific
        set(hPlaneLabel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hPlaneDropdown, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hChannelLabel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hChannelDropdown, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hSmoothingLabel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hSmoothingWindowInput, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        
        % Neural-specific
        set(hNeuropilCoeffLabel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hNeuropilCoeffInput, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hDetrendCheckbox, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hDetrendWindowLabel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hDetrendWindowInput, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hForcePositiveCheckbox, 'Visible', ifelse(~isTiffMode, 'on', 'off'));

        % 4. Restore the cached UI state for the new mode
        restoreUIStateForCurrentMode();
        
        % 5. Invalidate Session Cache and Update Display
        appState.sessionCache = struct('data', [], 'fingerprint', []);
        updateDisplayInfo();
    end

    function loadStateCallback(~,~)
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select a saved state file');
        if isequal(fileName, 0), return; end
        
        loadPath = fullfile(pathName, fileName);
        try
            set(hText, 'String', 'Loading state...'); drawnow;
            loadedData = load(loadPath);
            if ~isfield(loadedData, 'state'), error('Invalid state file.'); end
            
            % --- Take snapshot of current session BEFORE overwriting ---
            appState.sessionMode = appState.currentMode; % Remember the session's mode
            cacheCurrentUIState(appState.currentMode); % Save UI settings for current session
            % Also store an explicit session UI snapshot for robust restoration
            appState.sessionUiCache.(appState.currentMode) = harvestUIStateForMode(appState.currentMode);
            
            state = loadedData.state;
            
            % --- Mode-aware validation and routing ---
            fileMode = getStateMode(state);
            currentMode = appState.currentMode;
            if ~strcmp(fileMode, currentMode)
                error('Loaded state is %s but current mode is %s. Switch modes and try again.', fileMode, currentMode);
            end
            
            % --- Get checkbox value ---
            isTiffMode = strcmp(fileMode, 'TIFF');
            if isTiffMode, reloadRaw = get(hReloadDataCheckbox_Tiff, 'Value');
            else, reloadRaw = get(hReloadDataCheckbox_Neural, 'Value'); end
            
            state.reloadRaw = reloadRaw; % Tag the state with reload status
            % Store into dedicated loaded slot and make it active
            appState.loadedState.(fileMode) = state;
            appState.activeLoadedMode = fileMode;
            appState.loadedStateSnapshot = state; % Maintain compatibility for existing code paths
            
            % Activate the Loaded State context
            set(hContextLoaded, 'Enable', 'on', 'Value', 1);
            set(hContextSession, 'Value', 0);
            try
                switchOperatingContextCallback(); % Manually trigger update
            catch
                % Non-fatal context refresh errors should not block using the loaded state
            end

        catch ME
            set(hText, 'String', sprintf('Error loading state file:\n%s', ME.message));
        end
    end

    function showInfoCallback(~, ~)
        % This now shows info based on the current context
        isInLoadedContext = get(hContextLoaded, 'Value') == 1;
        
        if isInLoadedContext && ~isempty(appState.loadedStateSnapshot)
            stateToShow = appState.loadedStateSnapshot;
        else
            stateToShow = appState; % Use current session state
        end

        function openGammaDialog(~,~)
            try
                prompt = {'MP4 gamma (e.g., 1.12):','AVI gamma (e.g., 0.92):'};
                defaults = {num2str(appState.exportGamma.mp4), num2str(appState.exportGamma.avi)};
                answ = inputdlg(prompt, 'Export gamma settings', [1 35; 1 35], defaults);
                if isempty(answ), return; end
                gMp4 = str2double(answ{1}); gAvi = str2double(answ{2});
                if isfinite(gMp4) && gMp4 > 0, appState.exportGamma.mp4 = gMp4; end
                if isfinite(gAvi) && gAvi > 0, appState.exportGamma.avi = gAvi; end
                appendToStatus(sprintf('Export gamma updated: MP4=%.3f, AVI=%.3f', appState.exportGamma.mp4, appState.exportGamma.avi));
            catch ME
                warndlg(sprintf('Error updating gamma settings:\n%s', ME.message), 'Gamma');
            end
        end

        mode = getStateMode(stateToShow);

        if strcmp(mode, 'TIFF')
            if isfield(stateToShow.TIFF, 'metadataString') && ~isempty(stateToShow.TIFF.metadataString)
                set(hText, 'String', stateToShow.TIFF.metadataString);
            end
        else
            if isfield(stateToShow.Neural, 'metadataString') && ~isempty(stateToShow.Neural.metadataString)
                set(hText, 'String', stateToShow.Neural.metadataString);
            end
        end
    end

    function plotAvgCallback(~, ~)
        avgData = []; localState = []; playerStateToApply = [];
        
        isInLoadedContext = get(hContextLoaded, 'Value') == 1;

        if isInLoadedContext && ~isempty(appState.loadedStateSnapshot)
            localState = appState.loadedStateSnapshot;
            playerStateToApply = ifisfield(localState, 'playerState');
            if isfield(localState, 'reloadRaw') && localState.reloadRaw == 1
                [processedData, localState, success, errMsg] = getOrProcessData_LOADED();
                if ~success, set(hText, 'String', errMsg); return; end
                if strcmp(localState.mode, 'TIFF')
                    timeDim = ifelse(ndims(processedData) == 4, 4, 3);
                    avgData = mean(processedData, timeDim);
                else
                    avgData = mean(processedData, 2);
                end
                appendToStatusTimed('Averaged data (Loaded State, raw reload).');
            else
                set(hText, 'String', 'Averaging pre-loaded movie data...'); drawnow;
                resetStatusStepTimer();
                isTiffMode = strcmp(localState.mode, 'TIFF');
                if isTiffMode
                    timeDim = ifelse(ndims(localState.movieData) == 4, 4, 3);
                else
                    timeDim = 2;
                end
                avgData = mean(localState.movieData, timeDim);
                appendToStatusTimed('Averaged pre-loaded movie data.');
            end
        else
            [processedData, localState, success, errMsg] = getOrProcessData();
            if ~success, set(hText, 'String', errMsg); return; end

            if strcmp(localState.mode, 'TIFF')
                timeDim = ifelse(ndims(processedData) == 4, 4, 3);
                avgData = mean(processedData, timeDim);
            else
                avgData = mean(processedData, 2);
            end
            appendToStatusTimed('Averaged data over time/trials.');
        end

        try
            localState.avgData = avgData;
            
            figName = ifelse(strcmp(localState.mode, 'TIFF'), 'Average Stitched Image', 'Average Neuronal Activity');
            hPlotFig = figure('Name', figName, 'NumberTitle', 'off', 'Position', [600 100 600 900]);
            
            hAxes = axes('Parent', hPlotFig, 'Units', 'normalized', 'Position', [0.1 0.35 0.8 0.56]);

            vareaHandles = [];
            if ~isempty(localState.Neural.vareaData)
                vareaHandles = createVareaControls(hPlotFig, hAxes, [0.1 0.95 0.8 0.04], localState);
            end
            
            uicontrol('Parent', hPlotFig, 'Style', 'edit', 'String', figName, ...
                'Units', 'normalized', 'Position', [0.1 0.91 0.8 0.03], 'FontSize', 12, ...
                'FontWeight', 'bold', 'BackgroundColor', get(hPlotFig, 'Color'), 'HorizontalAlignment', 'center');
            
            displayHandles = createDisplayModeControls(hPlotFig, [0.1 0.16 0.8 0.05]);
            markerHandles = createMarkerControls(hPlotFig, [0.1 0.1 0.8 0.05]);
            hUndockedFig_avg = []; hUndockedAxes_avg = []; hUndockedPlot_avg = [];
            isSyncingLimits_avg = false;
            axisUiPanel = uipanel('Parent', hPlotFig, 'Title', 'View Limits', 'Units', 'normalized', 'Position', [0.1 0.31 0.8 0.035]);
            uicontrol('Parent', axisUiPanel, 'Style', 'text', 'String', 'X:', 'Units', 'normalized', 'Position', [0.02 0.12 0.04 0.76], 'HorizontalAlignment', 'left');
            hXMinEdit_avg = uicontrol('Parent', axisUiPanel, 'Style', 'edit', 'String', '', 'Units', 'normalized', 'Position', [0.06 0.15 0.15 0.70], 'Callback', @(s,e) applyAxisLimits_avg());
            hXMaxEdit_avg = uicontrol('Parent', axisUiPanel, 'Style', 'edit', 'String', '', 'Units', 'normalized', 'Position', [0.22 0.15 0.15 0.70], 'Callback', @(s,e) applyAxisLimits_avg());
            uicontrol('Parent', axisUiPanel, 'Style', 'text', 'String', 'Y:', 'Units', 'normalized', 'Position', [0.42 0.12 0.04 0.76], 'HorizontalAlignment', 'left');
            hYMinEdit_avg = uicontrol('Parent', axisUiPanel, 'Style', 'edit', 'String', '', 'Units', 'normalized', 'Position', [0.46 0.15 0.15 0.70], 'Callback', @(s,e) applyAxisLimits_avg());
            hYMaxEdit_avg = uicontrol('Parent', axisUiPanel, 'Style', 'edit', 'String', '', 'Units', 'normalized', 'Position', [0.62 0.15 0.15 0.70], 'Callback', @(s,e) applyAxisLimits_avg());
            hAxisApplyBtn_avg = uicontrol('Parent', axisUiPanel, 'Style', 'pushbutton', 'String', 'Apply', 'Units', 'normalized', 'Position', [0.78 0.15 0.10 0.70], 'Callback', @(s,e) applyAxisLimits_avg());
            hPopoutBtn_avg = uicontrol('Parent', axisUiPanel, 'Style', 'pushbutton', 'String', 'Popout', 'Units', 'normalized', 'Position', [0.89 0.15 0.10 0.70], 'Callback', @(s,e) togglePopout_avg());
            
            modeContrasts = struct();
            p_base = prctile(localState.avgData(:), [2 98]);
            if any(isnan(p_base)) || p_base(1) >= p_base(2), p_base = [0 1]; end
            if strcmp(localState.mode, 'TIFF'), modeContrasts.Image = p_base; else, modeContrasts.Cells = p_base; end
            
            avgDataFor2D = localState.avgData;
            isPlaneAllAvg = (strcmp(localState.mode, 'TIFF') && ndims(localState.avgData) == 3 && isfield(localState, 'ui') && localState.ui.plane > localState.TIFF.parsedNumPlanes);
            if strcmp(localState.mode, 'TIFF') && ndims(localState.avgData) == 3
                if isPlaneAllAvg
                    avgDataFor2D = sum(localState.avgData, 3);
                elseif isfield(localState,'ui') && localState.ui.channel == localState.TIFF.parsedNumChannels + 1 && size(localState.avgData, 3) == 3
                    avgDataFor2D = mean(localState.avgData, 3);
                end
            end
            if ~isempty(localState.Neural.vareaData)
                [areaImg, ~] = createAreaAverageImage(avgDataFor2D, localState, true);
                p_area = prctile(areaImg(:), [2 98]); 
                if any(isnan(p_area)) || p_area(1) >= p_area(2), p_area = [0 1]; end
                modeContrasts.Areas = p_area;
            end
            
            gridSize = 30;
            if strcmp(localState.mode, 'TIFF'), [gridData, ~, ~] = binData_TIFF(avgDataFor2D, localState.TIFF, gridSize);
            else, [gridData, ~, ~] = binData_Neural(localState.Neural, localState.avgData, gridSize, localState.physicalCoords, false); end
            p_grid = prctile(gridData(:), [2 98]); 
            if any(isnan(p_grid)) || p_grid(1) >= p_grid(2), p_grid = [0 1]; end
            modeContrasts.Grid = p_grid;

            isMergeAvg = (strcmp(localState.mode, 'TIFF') && ndims(localState.avgData) == 3 && size(localState.avgData, 3) == 3 && isfield(localState,'ui') && localState.ui.channel == localState.TIFF.parsedNumChannels + 1);
            if isMergeAvg
                contrastHandles = createMergeContrastControls(hPlotFig, hAxes, [0.1 0.01 0.8 0.09], localState.avgData, displayHandles);
            else
                contrastHandles = createContrastControls(hPlotFig, hAxes, [0.1 0.01 0.8 0.09], modeContrasts, displayHandles);
            end
            hPlaneFalseColorCheckbox_avg = [];
            planeContrastPopupFig_avg = [];
            planeContrastLimits_avg = [];
            planePalette_avg = [];
            numPlanesAvg = ifelse(isPlaneAllAvg, size(localState.avgData, 3), 1);
            if isPlaneAllAvg
                planePalette_avg = lines(numPlanesAvg);
                planeContrastLimits_avg = zeros(numPlanesAvg, 2);
                for p = 1:numPlanesAvg
                    planeP = localState.avgData(:,:,p);
                    pr = prctile(planeP(:), [2 98]);
                    if pr(1) >= pr(2), pr = [0 1]; end
                    planeContrastLimits_avg(p,:) = pr(:)';
                end
                hPlaneFalseColorCheckbox_avg = uicontrol('Parent', contrastHandles.panel, 'Style', 'checkbox', 'String', 'Multicolor', ...
                    'Value', 0, 'Units', 'normalized', 'Position', [0.80 0.10 0.19 0.30], 'Callback', @(s,e) planeFalseColorToggled_avg(), 'BackgroundColor', get(contrastHandles.panel, 'BackgroundColor'));
            end
            hPlotObject = []; 
            
            tiffModes = {'Image', 'Grid'}; neuralModes = {'Cells', 'Grid'};
            if ~isempty(localState.Neural.vareaData), tiffModes{end+1} = 'Areas'; neuralModes{end+1} = 'Areas'; end
            if strcmp(localState.mode, 'TIFF'), set(displayHandles.modeDropdown, 'String', tiffModes);
            else, set(displayHandles.modeDropdown, 'String', neuralModes); end
            
            if ~isempty(playerStateToApply)
                set(displayHandles.modeDropdown, 'Callback', []); % Disable callback to prevent premature trigger
                set(displayHandles.modeDropdown, 'Value', playerStateToApply.displayMode);
                set(displayHandles.gridSizeEdit, 'String', playerStateToApply.gridSize);
                set(displayHandles.interpolateCheckbox, 'Value', playerStateToApply.interpolate);
                set(markerHandles.sizeSlider, 'Value', playerStateToApply.markerSize);
                set(markerHandles.shapeDropdown, 'Value', playerStateToApply.markerShapeIndex);
            end

            set(displayHandles.modeDropdown, 'Callback', @(s,e) displayModeChanged_static());
            set(displayHandles.gridSizeEdit, 'Callback', @(s,e) displayModeChanged_static());
            set(displayHandles.interpolateCheckbox, 'Callback', @(s,e) displayModeChanged_static());
            
            displayModeChanged_static(); % This calls resetSliders
            syncAxisLimitEditors_avg();
            try
                addlistener(hAxes, 'XLim', 'PostSet', @(s,e) syncAxisLimitEditors_avg());
                addlistener(hAxes, 'YLim', 'PostSet', @(s,e) syncAxisLimitEditors_avg());
                addlistener(hAxes, 'CLim', 'PostSet', @(s,e) syncMainToUndocked_avg());
            catch
            end
            try
                zObj = zoom(hPlotFig); set(zObj, 'ActionPostCallback', @(s,e) syncAxisLimitEditors_avg());
                pObj = pan(hPlotFig);  set(pObj, 'ActionPostCallback', @(s,e) syncAxisLimitEditors_avg());
            catch
            end
            if isMergeAvg && isfield(contrastHandles, 'applyMergeImage')
                contrastHandles.applyMergeImage();
            end
            if ~isempty(vareaHandles), vareaHandles.updateAll(); end
            
            if ~isempty(playerStateToApply) && ~isMergeAvg
                contrastHandles.setPlayerState(playerStateToApply);
            end

            appendToStatusTimed('Successfully plotted average activity.');
        catch ME
            appendToStatusTimed(sprintf('Error plotting average:\n%s\nLine: %d', ME.message, ME.stack(1).line));
        end

        function displayModeChanged_static()
            modeIdx = get(displayHandles.modeDropdown, 'Value');
            modeOptions = get(displayHandles.modeDropdown, 'String');
            selectedMode = modeOptions{modeIdx};
            isTiffMode = strcmp(localState.mode, 'TIFF');
            
            set(markerHandles.panel, 'Visible', ifelse(strcmp(selectedMode, 'Cells'), 'on', 'off'));
            set(displayHandles.gridSizeEdit, 'Visible', ifelse(strcmp(selectedMode, 'Grid'), 'on', 'off'));
            set(displayHandles.gridSizeLabel, 'Visible', ifelse(strcmp(selectedMode, 'Grid'), 'on', 'off'));
            set(displayHandles.interpolateCheckbox, 'Visible', ifelse(strcmp(selectedMode, 'Grid'), 'on', 'off'));
            
            if isgraphics(hPlotObject), delete(hPlotObject); end

            if isTiffMode
                T = localState.TIFF;
                physW = T.pixelWidth / T.x_pixels_per_unit;
                physH = T.pixelHeight / T.y_pixels_per_unit;
                avgDataFor2D = localState.avgData;
                if ndims(localState.avgData) == 3
                    if isPlaneAllAvg
                        avgDataFor2D = sum(localState.avgData, 3);
                    elseif isMergeAvg && size(localState.avgData, 3) == 3
                        avgDataFor2D = mean(localState.avgData, 3);
                    end
                end
                if strcmp(selectedMode, 'Image')
                    if isPlaneAllAvg && isgraphics(hPlaneFalseColorCheckbox_avg) && get(hPlaneFalseColorCheckbox_avg, 'Value')
                        cdata = buildPlaneFalseColorFrame_avg(localState.avgData, planeContrastLimits_avg, planePalette_avg);
                        hPlotObject = imagesc(hAxes, [0 physW], [0 physH], cdata);
                    elseif ndims(localState.avgData) == 3 && size(localState.avgData, 3) == 3 && isMergeAvg
                        cdata = double(min(1, max(0, localState.avgData)));
                        hPlotObject = imagesc(hAxes, [0 physW], [0 physH], cdata);
                    else
                        hPlotObject = imagesc(hAxes, [0 physW], [0 physH], avgDataFor2D);
                    end
                elseif strcmp(selectedMode, 'Grid')
                    gridSize = str2double(get(displayHandles.gridSizeEdit, 'String'));
                    if isnan(gridSize) || gridSize < 1, gridSize = 30; end
                    if get(displayHandles.interpolateCheckbox, 'Value') == 1, gridData = imresize(avgDataFor2D, [gridSize gridSize], 'bicubic');
                    else, [gridData, ~, ~] = binData_TIFF(avgDataFor2D, localState.TIFF, gridSize); end
                    grid_x = linspace(0, physW, gridSize); grid_y = linspace(0, physH, gridSize);
                    hPlotObject = imagesc(hAxes, 'XData', grid_x, 'YData', grid_y, 'CData', gridData);
                elseif strcmp(selectedMode, 'Areas')
                    if isempty(vareaHandles), error('Load visual areas first.'); end
                    [areaImg, ~] = createAreaAverageImage(avgDataFor2D, localState, get(vareaHandles.flipYCheckbox, 'Value'));
                    hPlotObject = imagesc(hAxes, [0 physW], [0 physH], areaImg);
                end
            else % Neural Mode
                if strcmp(selectedMode, 'Cells')
                    hPlotObject = scatter(hAxes, localState.physicalCoords(:,1), localState.physicalCoords(:,2), get(markerHandles.sizeSlider, 'Value'), localState.avgData, 'filled', 'Marker', markerHandles.shapeValues{get(markerHandles.shapeDropdown, 'Value')});
                    set(markerHandles.panel, 'UserData', hPlotObject);
                elseif strcmp(selectedMode, 'Grid')
                    gridSize = str2double(get(displayHandles.gridSizeEdit, 'String'));
                    if isnan(gridSize) || gridSize < 1, gridSize = 30; end
                    [binnedFrame, x_centers, y_centers] = binData_Neural(localState.Neural, localState.avgData, gridSize, localState.physicalCoords, get(displayHandles.interpolateCheckbox, 'Value'));
                    hPlotObject = imagesc(hAxes, 'XData', x_centers, 'YData', y_centers, 'CData', binnedFrame);
                elseif strcmp(selectedMode, 'Areas')
                    if isempty(vareaHandles), error('Load visual areas first.'); end
                    [areaImg, ~] = createAreaAverageImage(localState.avgData, localState, get(vareaHandles.flipYCheckbox, 'Value'));
                    N = localState.Neural;
                    hPlotObject = imagesc(hAxes, 'XData', N.plotXLim, 'YData', N.plotYLim, 'CData', areaImg);
                end
            end
            
            setupPlotAxes(hAxes, localState.mode, localState.TIFF, localState.Neural);
            if isempty(playerStateToApply)
                contrastHandles.resetSliders(selectedMode);
            end
            if isTiffMode, set(hAxes, 'YDir', 'normal'); end
            if ~isempty(vareaHandles), vareaHandles.updateAll(); end
            contrastHandles.reapplyColormap();
            syncAxisLimitEditors_avg();
            refreshUndocked_avg();
        end

        function syncAxisLimitEditors_avg()
            if ~isgraphics(hAxes), return; end
            xl = get(hAxes, 'XLim'); yl = get(hAxes, 'YLim');
            set(hXMinEdit_avg, 'String', sprintf('%.3f', xl(1)));
            set(hXMaxEdit_avg, 'String', sprintf('%.3f', xl(2)));
            set(hYMinEdit_avg, 'String', sprintf('%.3f', yl(1)));
            set(hYMaxEdit_avg, 'String', sprintf('%.3f', yl(2)));
            syncMainToUndocked_avg();
        end

        function applyAxisLimits_avg()
            if ~isgraphics(hAxes), return; end
            x1 = str2double(get(hXMinEdit_avg, 'String'));
            x2 = str2double(get(hXMaxEdit_avg, 'String'));
            y1 = str2double(get(hYMinEdit_avg, 'String'));
            y2 = str2double(get(hYMaxEdit_avg, 'String'));
            if any(isnan([x1 x2 y1 y2])) || x2 <= x1 || y2 <= y1
                syncAxisLimitEditors_avg();
                return;
            end
            xlim(hAxes, [x1 x2]); ylim(hAxes, [y1 y2]);
            syncAxisLimitEditors_avg();
        end

        function togglePopout_avg()
            if isscalar(hUndockedFig_avg) && isgraphics(hUndockedFig_avg)
                closeUndocked_avg();
                return;
            end
            p = get(hPlotFig, 'Position');
            popW = max(700, p(3));
            popH = p(4);
            popX = p(1) + 40;
            popY = p(2) + 20;
            hUndockedFig_avg = figure('Name', [figName ' - Popout'], 'NumberTitle', 'off', ...
                'Position', [popX popY popW popH], 'Color', 'k', 'CloseRequestFcn', @closeUndocked_avg);
            hUndockedAxes_avg = axes('Parent', hUndockedFig_avg, 'Units', 'normalized', 'Position', [0.02 0.02 0.96 0.96]);
            set(hPopoutBtn_avg, 'String', 'Dock');
            refreshUndocked_avg();
            try
                addlistener(hUndockedAxes_avg, 'XLim', 'PostSet', @(s,e) syncUndockedToMain_avg());
                addlistener(hUndockedAxes_avg, 'YLim', 'PostSet', @(s,e) syncUndockedToMain_avg());
            catch
            end
        end

        function closeUndocked_avg(varargin)
            if isscalar(hUndockedFig_avg) && isgraphics(hUndockedFig_avg), delete(hUndockedFig_avg); end
            hUndockedFig_avg = []; hUndockedAxes_avg = []; hUndockedPlot_avg = [];
            if isscalar(hPopoutBtn_avg) && isgraphics(hPopoutBtn_avg), set(hPopoutBtn_avg, 'String', 'Popout'); end
        end

        function refreshUndocked_avg()
            if ~(isscalar(hUndockedFig_avg) && isgraphics(hUndockedFig_avg)) || ...
               ~(isscalar(hUndockedAxes_avg) && isgraphics(hUndockedAxes_avg)) || ...
               ~(isscalar(hPlotObject) && isgraphics(hPlotObject))
                return;
            end
            pType = get(hPlotObject, 'Type');
            cla(hUndockedAxes_avg);
            if strcmp(pType, 'image')
                hUndockedPlot_avg = imagesc(hUndockedAxes_avg, 'XData', get(hPlotObject, 'XData'), 'YData', get(hPlotObject, 'YData'), 'CData', get(hPlotObject, 'CData'));
            elseif strcmp(pType, 'scatter')
                hUndockedPlot_avg = scatter(hUndockedAxes_avg, get(hPlotObject, 'XData'), get(hPlotObject, 'YData'), get(hPlotObject, 'SizeData'), get(hPlotObject, 'CData'), 'filled');
                try, set(hUndockedPlot_avg, 'Marker', get(hPlotObject, 'Marker')); end
            else
                return;
            end
            colormap(hUndockedAxes_avg, colormap(hAxes));
            axis(hUndockedAxes_avg, 'equal');
            set(hUndockedAxes_avg, 'YDir', get(hAxes, 'YDir'), 'XDir', get(hAxes, 'XDir'));
            syncMainToUndocked_avg();
        end

        function syncMainToUndocked_avg()
            if ~(isscalar(hUndockedAxes_avg) && isgraphics(hUndockedAxes_avg)), return; end
            if isSyncingLimits_avg, return; end
            isSyncingLimits_avg = true;
            try
                set(hUndockedAxes_avg, 'XLim', get(hAxes, 'XLim'), 'YLim', get(hAxes, 'YLim'));
                set(hUndockedAxes_avg, 'CLim', get(hAxes, 'CLim'));
                colormap(hUndockedAxes_avg, colormap(hAxes));
            catch
            end
            isSyncingLimits_avg = false;
        end

        function syncUndockedToMain_avg()
            if ~(isscalar(hUndockedAxes_avg) && isgraphics(hUndockedAxes_avg)) || ...
               ~(isscalar(hAxes) && isgraphics(hAxes))
                return;
            end
            if isSyncingLimits_avg, return; end
            isSyncingLimits_avg = true;
            try
                set(hAxes, 'XLim', get(hUndockedAxes_avg, 'XLim'), 'YLim', get(hUndockedAxes_avg, 'YLim'));
            catch
            end
            isSyncingLimits_avg = false;
            syncAxisLimitEditors_avg();
        end

        function rgb = buildPlaneFalseColorFrame_avg(avgP, limits, palette)
            H = size(avgP,1); W = size(avgP,2); P = size(avgP,3);
            rgb = zeros(H, W, 3);
            for p = 1:P
                span = limits(p,2) - limits(p,1) + eps;
                s = min(1, max(0, (double(avgP(:,:,p)) - limits(p,1)) / span));
                for c = 1:3
                    rgb(:,:,c) = rgb(:,:,c) + palette(p,c) * s;
                end
            end
            mx = max(rgb(:)); if mx > 0, rgb = rgb / mx; end
            rgb = min(1, max(0, rgb));
        end

        function planeFalseColorToggled_avg()
            checked = get(hPlaneFalseColorCheckbox_avg, 'Value');
            if checked
                set(contrastHandles.cmapDropdown, 'Visible', 'off');
                set(contrastHandles.invertCmap, 'Visible', 'off');
                openPlaneContrastPopup_avg();
            else
                set(contrastHandles.cmapDropdown, 'Visible', 'on');
                set(contrastHandles.invertCmap, 'Visible', 'on');
                if isgraphics(planeContrastPopupFig_avg), close(planeContrastPopupFig_avg); planeContrastPopupFig_avg = []; end
            end
            displayModeChanged_static();
        end

        function openPlaneContrastPopup_avg()
            if isgraphics(planeContrastPopupFig_avg), figure(planeContrastPopupFig_avg); return; end
            P = numPlanesAvg;
            planeContrastPopupFig_avg = figure('Name', 'Plane contrast (Average)', 'NumberTitle', 'off', 'Position', [700 200 400 min(500, 80+ P*70)]);
            hMins = zeros(P,1); hMaxs = zeros(P,1); hMinRanges = zeros(P,1); hMaxRanges = zeros(P,1);
            rangeOptions = {'0.5x', '1x', '2x', '4x', '8x'};
            rangeVals = [0.5, 1, 2, 4, 8];
            for p = 1:P
                idx = p;
                y = 1 - (p-0.5)/max(P,1);
                uicontrol(planeContrastPopupFig_avg, 'Style', 'text', 'String', sprintf('Plane %d', p), 'Units', 'normalized', 'Position', [0.02 y-0.03 0.15 0.06]);
                lo = planeContrastLimits_avg(p,1); hi = planeContrastLimits_avg(p,2);
                hMins(p) = uicontrol(planeContrastPopupFig_avg, 'Style', 'slider', 'Units', 'normalized', 'Position', [0.18 y 0.24 0.04], 'Min', lo-1, 'Max', lo+1, 'Value', lo, 'UserData', lo);
                hMinRanges(p) = uicontrol(planeContrastPopupFig_avg, 'Style', 'popupmenu', 'String', rangeOptions, 'Value', 2, 'Units', 'normalized', 'Position', [0.43 y 0.08 0.04]);
                hMaxs(p) = uicontrol(planeContrastPopupFig_avg, 'Style', 'slider', 'Units', 'normalized', 'Position', [0.55 y 0.24 0.04], 'Min', hi-1, 'Max', hi+1, 'Value', hi, 'UserData', hi);
                hMaxRanges(p) = uicontrol(planeContrastPopupFig_avg, 'Style', 'popupmenu', 'String', rangeOptions, 'Value', 2, 'Units', 'normalized', 'Position', [0.80 y 0.08 0.04]);
                set(hMinRanges(p), 'Callback', @(s,e) updatePlaneSliderRanges_avg(idx));
                set(hMaxRanges(p), 'Callback', @(s,e) updatePlaneSliderRanges_avg(idx));
                addlistener(hMins(p), 'Value', 'PostSet', @(s,e) syncPlaneLimitsFromPopup_avg());
                addlistener(hMaxs(p), 'Value', 'PostSet', @(s,e) syncPlaneLimitsFromPopup_avg());
            end
            for pp = 1:P
                updatePlaneSliderRanges_avg(pp);
            end
            uicontrol(planeContrastPopupFig_avg, 'Style', 'text', 'String', 'Black', 'Units', 'normalized', 'Position', [0.18 0.96 0.1 0.03]);
            uicontrol(planeContrastPopupFig_avg, 'Style', 'text', 'String', 'White', 'Units', 'normalized', 'Position', [0.55 0.96 0.1 0.03]);
            function updatePlaneSliderRanges_avg(pp)
                lo = get(hMins(pp), 'UserData');
                hi = get(hMaxs(pp), 'UserData');
                baseRange = abs(hi - lo); if baseRange <= 0, baseRange = 1; end
                multMin = rangeVals(get(hMinRanges(pp), 'Value'));
                multMax = rangeVals(get(hMaxRanges(pp), 'Value'));
                halfMin = baseRange * multMin;
                halfMax = baseRange * multMax;
                newMinLo = lo - halfMin; newMinHi = lo + halfMin;
                newMaxLo = hi - halfMax; newMaxHi = hi + halfMax;
                set(hMins(pp), 'Min', newMinLo, 'Max', newMinHi);
                set(hMaxs(pp), 'Min', newMaxLo, 'Max', newMaxHi);
                cv = get(hMins(pp), 'Value'); set(hMins(pp), 'Value', max(newMinLo, min(newMinHi, cv)));
                cv = get(hMaxs(pp), 'Value'); set(hMaxs(pp), 'Value', max(newMaxLo, min(newMaxHi, cv)));
                syncPlaneLimitsFromPopup_avg();
            end
            function syncPlaneLimitsFromPopup_avg()
                if ~isgraphics(planeContrastPopupFig_avg), return; end
                for pp = 1:numel(hMins)
                    if hMins(pp) == 0 || ~isgraphics(hMins(pp)), continue; end
                    planeContrastLimits_avg(pp,1) = get(hMins(pp), 'Value');
                    planeContrastLimits_avg(pp,2) = get(hMaxs(pp), 'Value');
                end
                displayModeChanged_static();
            end
        end
    end

    function playMovieCallback(~, ~)
        precomputedMovie = [];
        playerStateToApply = [];
        generationState = [];
        
        isInLoadedContext = get(hContextLoaded, 'Value') == 1;

        if isInLoadedContext && ~isempty(appState.loadedStateSnapshot)
            if isfield(appState.loadedStateSnapshot, 'reloadRaw') && appState.loadedStateSnapshot.reloadRaw == 1
                [processedData, generationState, success, errMsg] = getOrProcessData_LOADED();
                if ~success, set(hText, 'String', errMsg); return; end
                if strcmp(generationState.mode, 'TIFF') && ndims(processedData) == 4 && size(processedData, 3) == 3
                    processedData = squeeze(processedData(:,:,1,:));
                end
                rollingAvg = round(str2double(get(hRollingAvgInput, 'String')));
                if isnan(rollingAvg) || rollingAvg < 1, set(hText, 'String', 'Invalid Rolling Average.'); return; end
                if strcmp(generationState.mode, 'TIFF')
                    timeDim = ifelse(ndims(processedData) == 4, 4, 3);
                    precomputedMovie = movmean(processedData, rollingAvg, timeDim, 'Endpoints', 'shrink');
                else
                    precomputedMovie = movmean(processedData, rollingAvg, 2, 'Endpoints', 'shrink');
                end
                appendToStatusTimed(sprintf('Applied rolling average of %d (Loaded State).', rollingAvg));
                playerStateToApply = ifisfield(generationState, 'playerState');
            else
                generationState = appState.loadedStateSnapshot;
                precomputedMovie = generationState.movieData;
                if ndims(precomputedMovie) == 4 && size(precomputedMovie, 3) == 3
                    precomputedMovie = squeeze(precomputedMovie(:,:,1,:));
                end
                playerStateToApply = ifisfield(generationState, 'playerState');
                set(hText, 'String', 'Playing pre-computed movie from loaded state (channel 1)...'); drawnow;
            end
        else
            channelForMovie = [];
            if strcmp(appState.currentMode, 'TIFF') && isfield(appState, 'TIFF') && ~isempty(appState.TIFF) && appState.TIFF.parsedNumChannels >= 2
                cv = get(hChannelDropdown, 'Value');
                if cv == appState.TIFF.parsedNumChannels + 1
                    channelForMovie = 1;
                end
            end
            [processedData, generationState, success, errMsg] = getOrProcessData(channelForMovie);
            if ~success, set(hText, 'String', errMsg); return; end
            
            rollingAvg = round(str2double(get(hRollingAvgInput, 'String')));
            if isnan(rollingAvg) || rollingAvg < 1, set(hText, 'String', 'Invalid Rolling Average.'); return; end
            
            if strcmp(generationState.mode, 'TIFF')
                timeDim = ifelse(ndims(processedData) == 4, 4, 3);
                precomputedMovie = movmean(processedData, rollingAvg, timeDim, 'Endpoints', 'shrink');
            else % Neural
                precomputedMovie = movmean(processedData, rollingAvg, 2, 'Endpoints', 'shrink');
            end
            appendToStatusTimed(sprintf('Applied rolling average of %d.', rollingAvg));
        end

        resetStatusStepTimer();
        launchUnifiedMoviePlayer(precomputedMovie, playerStateToApply, generationState);
        appendToStatusTimed('Movie player opened.');
    end

%% --- DATA CACHING & PROCESSING ---
    function [processedData, generationState, success, errMsg] = getOrProcessData(channelOverride)
        processedData = []; 
        generationState = [];
        success = false; 
        errMsg = '';
        if nargin < 1, channelOverride = []; end

        % 1. Get current settings fingerprint
        generationState = captureFullState();

        % 2. When channel override (e.g. for movie when channel is All), skip cache and do not update cache
        useOverride = strcmp(appState.currentMode, 'TIFF') && ~isempty(channelOverride);
        if useOverride
            if (isempty(appState.TIFF.fullFilePath) && isempty(appState.TIFF.selectedFolderPath))
                errMsg = 'Please load TIFF data first.';
                success = false;
                return;
            end
            set(hText, 'String', 'Processing data (channel for movie)...'); drawnow;
            resetStatusStepTimer();
            [newData, procSuccess, procErrMsg] = getProcessedData(channelOverride);
            if procSuccess
                processedData = newData;
                success = true;
            else
                errMsg = procErrMsg;
                success = false;
            end
            return;
        end

        % 3. Check against cache
        if isfield(appState, 'sessionCache') && ...
           ~isempty(appState.sessionCache) && ...
           isfield(appState.sessionCache, 'fingerprint') && ...
           ~isempty(appState.sessionCache.fingerprint) && ...
           isequaln(generationState, appState.sessionCache.fingerprint)
            
            % Cache Hit
            resetStatusStepTimer();
            appendToStatusTimed('Using cached data...');
            processedData = appState.sessionCache.data;
            success = true;
            
        else
            % Cache Miss
            if (strcmp(appState.currentMode, 'TIFF') && isempty(appState.TIFF.fullFilePath) && isempty(appState.TIFF.selectedFolderPath)) || ...
               (strcmp(appState.currentMode, 'Neural') && (isempty(appState.Neural.psthsData) || isempty(appState.Neural.cellCoords) || isempty(appState.Neural.tiffFolderPath)))
                errMsg = 'Please load all required data for the current mode first.';
                if strcmp(appState.currentMode, 'Neural')
                    errMsg = [errMsg sprintf('\n(Data, Coords, AND original TIFF folder are required.)')];
                end
                success = false;
                return;
            end

            set(hText, 'String', 'Processing new data...'); drawnow;
            resetStatusStepTimer();
            [newData, procSuccess, procErrMsg] = getProcessedData();
            
            if procSuccess
                appState.sessionCache.data = newData;
                appState.sessionCache.fingerprint = generationState;
                processedData = newData;
                success = true;
            else
                errMsg = procErrMsg;
                success = false;
            end
        end
    end

    function [processedData, generationState, success, errMsg] = getOrProcessData_LOADED()
        % Processing path for Loaded State when reloadRaw is enabled. Uses isolated cache per loaded slot.
        processedData = [];
        generationState = [];
        success = false;
        errMsg = '';
        
        if isempty(appState.loadedStateSnapshot)
            errMsg = 'No loaded state active.'; return; 
        end
        sourceState = appState.loadedStateSnapshot;
        mode = getStateMode(sourceState);
        if ~isfield(sourceState, 'reloadRaw') || sourceState.reloadRaw ~= 1
            errMsg = 'Reload raw data is disabled for the loaded state.'; return;
        end
        
        % Backup session state
        sessionBackup.currentMode = appState.currentMode;
        sessionBackup.TIFF = appState.TIFF;
        sessionBackup.Neural = appState.Neural;
        sessionBackupSessionCache = appState.sessionCache; % keep intact
        
        try
            % Enter sandbox using loaded state's data and current UI
            appState.currentMode = mode;
            appState.TIFF = sourceState.TIFF;
            appState.Neural = sourceState.Neural;

            % Ensure required raw data are present for processing when in Neural mode
            if strcmp(mode, 'Neural')
                N = appState.Neural;
                % Load psths/psthsnp if absent
                if (isempty(N.psthsData) || isempty(N.psthsnpData)) && ~isempty(N.dataFilePath)
                    try
                        data = load(N.dataFilePath, 'psths', 'psthsnp');
                        if isfield(data,'psths'), N.psthsData = data.psths; end
                        if isfield(data,'psthsnp'), N.psthsnpData = data.psthsnp; end
                    catch ME
                        error('Failed to load neural data from %s: %s', N.dataFilePath, ME.message);
                    end
                end
                % Load coords if absent
                if isempty(N.cellCoords) && ~isempty(N.coordsFilePath)
                    try
                        cdata = load(N.coordsFilePath);
                        f = fields(cdata); if ~isempty(f), N.cellCoords = cdata.(f{1}); end
                    catch ME
                        error('Failed to load coordinates from %s: %s', N.coordsFilePath, ME.message);
                    end
                end
                % Update basic dims if possible
                if ~isempty(N.psthsData)
                    [N.numNeurons, N.numTimepoints, N.numTrials] = size(N.psthsData);
                end
                % Populate FOV/pixel info if TIFF folder available
                if ~isempty(N.tiffFolderPath)
                    tff = dir(fullfile(N.tiffFolderPath, '*.tif*'));
                    if ~isempty(tff)
                        processTiffMetadataForInfo_Neural(fullfile(N.tiffFolderPath, tff(1).name));
                        N = appState.Neural; % processTiffMetadataForInfo_Neural writes back
                    end
                end
                appState.Neural = N;
            end
            
            % Build fingerprint from current UI + loaded data
            generationState = captureFullState();
            
            % Select correct loaded cache slot
            if strcmp(mode, 'TIFF')
                cacheSlot = appState.loadedCache.TIFF;
            else
                cacheSlot = appState.loadedCache.Neural;
            end
            
            % Cache check
            if isfield(cacheSlot, 'fingerprint') && ~isempty(cacheSlot.fingerprint) && isequaln(generationState, cacheSlot.fingerprint)
                resetStatusStepTimer();
                appendToStatusTimed('Using loaded-state cache...');
                processedData = cacheSlot.data;
                success = true;
            else
                % Compute new processed data using existing pipeline functions
                set(hText, 'String', 'Processing new data (Loaded State)...'); drawnow;
                resetStatusStepTimer();
                [newData, procSuccess, procErrMsg] = getProcessedData();
                if ~procSuccess
                    errMsg = procErrMsg; success = false;
                else
                    processedData = newData; success = true;
                    % Save back to appropriate loaded cache slot
                    if strcmp(mode, 'TIFF')
                        appState.loadedCache.TIFF.data = newData;
                        appState.loadedCache.TIFF.fingerprint = generationState;
                    else
                        appState.loadedCache.Neural.data = newData;
                        appState.loadedCache.Neural.fingerprint = generationState;
                    end
                end
            end
        catch ME
            errMsg = sprintf('Loaded-state processing error:\n%s', ME.message);
            success = false;
        end
        
        % Restore session state regardless of success
        appState.currentMode = sessionBackup.currentMode;
        appState.TIFF = sessionBackup.TIFF;
        appState.Neural = sessionBackup.Neural;
        appState.sessionCache = sessionBackupSessionCache;
    end

%% --- TIFF MODE SPECIFIC CALLBACKS ---
    function selectFileCallback_TIFF(~, ~)
        [fileName, pathName] = uigetfile({'*.tif;*.tiff', 'TIFF Files (*.tif, *.tiff)'}, 'Select a TIFF file');
        if isequal(fileName, 0), return; end
        
        T = appState.TIFF;
        T.isFolderMode = false;
        T.fullFilePath = fullfile(pathName, fileName);
        T.selectedFolderPath = '';
        T.folderFileCount = 0;
        appState.loadedMovieData = []; appState.loadedPlayerState = [];
        appState.sessionCache = struct('data', [], 'fingerprint', []); % Invalidate cache
        appState.TIFF = T;
        
        set(hText, 'String', sprintf('Analyzing file:\n%s...', fileName)); drawnow;
        try
            processMetadata_TIFF(T.fullFilePath, fileName);
            appendToStatus(sprintf('TIFF file loaded: %s', T.fullFilePath));
        catch ME
            set(hText, 'String', sprintf('Error reading file:\n%s\n\nDetails:\n%s', T.fullFilePath, ME.message));
        end
    end

    function selectFolderCallback_TIFF(~, ~)
        folderName = uigetdir();
        if isequal(folderName, 0), return; end
        
        T = appState.TIFF;
        T.isFolderMode = true;
        T.selectedFolderPath = folderName;
        T.fullFilePath = '';
        T.folderFileCount = 0;
        appState.loadedMovieData = []; appState.loadedPlayerState = [];
        appState.sessionCache = struct('data', [], 'fingerprint', []); % Invalidate cache
        
        set(hText, 'String', sprintf('Analyzing folder:\n%s...', folderName)); drawnow;
        try
            tiffFiles = dir(fullfile(T.selectedFolderPath, '*.tif*'));
            if isempty(tiffFiles), error('No TIFF files found in the selected folder.'); end
            
            firstFilePath = fullfile(T.selectedFolderPath, tiffFiles(1).name);
            [~, name, ~] = fileparts(tiffFiles(1).name);
            T.fileBaseName = regexprep(name, '_\d{5}$', '');
            T.folderFileCount = numel(tiffFiles);
            appState.TIFF = T;
            
            processMetadata_TIFF(firstFilePath, folderName);
            appendToStatus(sprintf('TIFF folder loaded: %s', folderName));
        catch ME
            set(hText, 'String', sprintf('Error reading folder:\n%s\n\nDetails:\n%s', T.selectedFolderPath, ME.message));
        end
    end

%% --- NEURAL DATA MODE SPECIFIC CALLBACKS ---
    function loadDataCallback_Neural(~, ~)
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select Data File');
        if isequal(fileName, 0), return; end
        
        N = appState.Neural;
        N.dataFilePath = fullfile(pathName, fileName);
        try
            set(hText, 'String', sprintf('Loading data from:\n%s...', fileName)); drawnow;
            data = load(N.dataFilePath, 'psths', 'psthsnp');
            if ~isfield(data, 'psths') || ~isfield(data, 'psthsnp')
                error('The selected .mat file must contain "psths" and "psthsnp" variables.');
            end
            N.psthsData = data.psths;
            N.psthsnpData = data.psthsnp;
            if ndims(N.psthsData) ~= 3 || ~isequal(size(N.psthsData), size(N.psthsnpData))
                error('Data must be 3D (N x t x R) and psths/psthsnp must be the same size.');
            end
            appState.Neural = N;
            appState.sessionCache = struct('data', [], 'fingerprint', []); % Invalidate cache
            set(hText, 'String', sprintf('Data loaded successfully from:\n%s', fileName)); drawnow;
            updateDisplayInfo();
            appendToStatus(sprintf('Neural data loaded: %s', N.dataFilePath));
        catch ME
            set(hText, 'String', sprintf('Error loading data file:\n%s', ME.message));
            N.dataFilePath = ''; N.psthsData = []; N.psthsnpData = []; appState.Neural = N;
        end
    end

    function loadCoordsCallback_Neural(~, ~)
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select Coordinates File');
        if isequal(fileName, 0), return; end
        
        N = appState.Neural;
        N.coordsFilePath = fullfile(pathName, fileName);
        try
            set(hText, 'String', sprintf('Loading coordinates from:\n%s...', fileName)); drawnow;
            data = load(N.coordsFilePath);
            f = fields(data);
            if numel(f) < 1, error('The selected .mat file is empty.'); end
            coords = data.(f{1});
            if ~ismatrix(coords) || size(coords, 2) ~= 2, error('Coordinates must be an N x 2 matrix.'); end
            N.cellCoords = coords;
            appState.Neural = N;
            appState.sessionCache = struct('data', [], 'fingerprint', []); % Invalidate cache
            set(hText, 'String', sprintf('Coordinates loaded successfully from:\n%s', fileName)); drawnow;
            updateDisplayInfo();
            appendToStatus(sprintf('Neural coords loaded: %s', N.coordsFilePath));
        catch ME
            set(hText, 'String', sprintf('Error loading coordinates file:\n%s', ME.message));
            N.coordsFilePath = ''; N.cellCoords = []; appState.Neural = N;
        end
    end
    
    function loadTiffCallback_Neural(~, ~)
        folderName = uigetdir('', 'Select the original TIFF folder');
        if isequal(folderName, 0), return; end
        
        appState.Neural.tiffFolderPath = folderName;
        try
            set(hText, 'String', sprintf('Analyzing TIFF folder:\n%s...', folderName)); drawnow;
            tiffFiles = dir(fullfile(appState.Neural.tiffFolderPath, '*.tif*'));
            if isempty(tiffFiles), error('No TIFF files found in the selected folder.'); end
            
            firstTiffPath = fullfile(appState.Neural.tiffFolderPath, tiffFiles(1).name);
            processTiffMetadataForInfo_Neural(firstTiffPath); % This populates the rest of appState.Neural
            
            appState.sessionCache = struct('data', [], 'fingerprint', []); % Invalidate cache
            set(hText, 'String', sprintf('TIFF folder loaded successfully:\n%s', folderName)); drawnow;
            updateDisplayInfo();
            appendToStatus(sprintf('Neural TIFF folder loaded: %s', folderName));
        catch ME
            set(hText, 'String', sprintf('Error reading TIFF folder:\n%s', ME.message));
            appState.Neural.tiffFolderPath = '';
        end
    end

    function loadVareaCallback(~, ~)
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select Visual Area File');
        if isequal(fileName, 0), return; end
        
        filePath = fullfile(pathName, fileName);
        try
            set(hText, 'String', sprintf('Loading visual areas from:\n%s...', fileName)); drawnow;
            data = load(filePath);
            f = fields(data);
            if numel(f) < 1, error('MAT file is empty.'); end
            vareaData = data.(f{1});
            if ~isstruct(vareaData), error('Visual area file must contain a structure of masks.'); end
            
            % Store in both since it can be used by both, and also store path in both
            appState.TIFF.vareaData = vareaData;
            appState.Neural.vareaData = vareaData;
            appState.TIFF.vareaFilePath = filePath;
            appState.Neural.vareaFilePath = filePath;

            appState.sessionCache = struct('data', [], 'fingerprint', []); % Invalidate cache
            set(hText, 'String', sprintf('Visual areas loaded from:\n%s', fileName)); drawnow;
            updateDisplayInfo();
            appendToStatus(sprintf('Visual areas loaded: %s', filePath));
        catch ME
            set(hText, 'String', sprintf('Error loading visual area file:\n%s', ME.message));
            appState.TIFF.vareaFilePath = ''; appState.TIFF.vareaData = [];
            appState.Neural.vareaFilePath = ''; appState.Neural.vareaData = [];
        end
    end

%% --- UNIFIED DATA PROCESSING ---

    function [processedData, success, errMsg] = getProcessedData(channelOverride)
        processedData = []; success = false; errMsg = '';
        
        % Step 1: Get raw trial-averaged data for the current mode
        if strcmp(appState.currentMode, 'TIFF')
            if nargin >= 1 && ~isempty(channelOverride)
                [trialAvgData, success_main, errMsg_main] = computeTrialAverageMovie_TIFF(get(hTrialInput, 'String'), channelOverride);
            else
                [trialAvgData, success_main, errMsg_main] = computeTrialAverageMovie_TIFF(get(hTrialInput, 'String'));
            end
        else % Neural
            [F_session_processed, success_pre, errMsg_pre] = preprocessFullSession_Neural();
            if ~success_pre, errMsg = errMsg_pre; success=false; return; end
            [trialAvgData, success_main, errMsg_main] = computeTrialAverageData_Neural(get(hTrialInput, 'String'), F_session_processed);
        end
        
        if ~success_main, errMsg = errMsg_main; success = false; return; end
        
        % Step 2: Apply dF/F calculations if requested
        displayMode = get(hDisplayMode, 'Value');
        if displayMode == 1 % Raw/Corrected
            processedData = trialAvgData;
        else
            try
                F0 = [];
                if displayMode == 2 % dF/F (Initial Frames)
                    numFrames = str2double(get(hInitialFramesInput, 'String'));
                    if isnan(numFrames) || numFrames < 1, error('Invalid frames for F0.'); end
                    timeDim = ndims(trialAvgData);
                    if numFrames > size(trialAvgData, timeDim), error('Not enough frames for F0.'); end
                    idx = repmat({':'}, 1, timeDim);
                    idx{timeDim} = 1:numFrames;
                    F0 = mean(trialAvgData(idx{:}), timeDim);
                    dF = trialAvgData - F0;
                elseif displayMode == 3 % dF/F (Median)
                    F0 = median(trialAvgData, ndims(trialAvgData));
                    dF = trialAvgData - F0;
                elseif displayMode == 4 % dF/F (Reference Trials)
                    refTrialStr = get(hRefTrialsInput, 'String');
                    if strcmp(appState.currentMode, 'TIFF')
                        if nargin >= 1 && ~isempty(channelOverride)
                            [refData, s, e] = computeTrialAverageMovie_TIFF(refTrialStr, channelOverride);
                        else
                            [refData, s, e] = computeTrialAverageMovie_TIFF(refTrialStr);
                        end
                    else
                        [refData, s, e] = computeTrialAverageData_Neural(refTrialStr, F_session_processed);
                    end
                    if ~s, error(['Ref trials error: ' e]); end
                    
                    if get(hFrameByFrameCheckbox, 'Value') == 1
                        timeDim = ndims(trialAvgData);
                        len1 = size(trialAvgData, timeDim);
                        len2 = size(refData, timeDim);
                        minLen = min(len1, len2);
                        if len1 ~= len2, warning('Movies are not same length. Truncating to %d frames.', minLen); end
                        idx1 = repmat({':'}, 1, timeDim); idx1{timeDim} = 1:minLen;
                        idx2 = repmat({':'}, 1, timeDim); idx2{timeDim} = 1:minLen;
                        
                        dF = trialAvgData(idx1{:}) - refData(idx2{:});
                        F0 = mean(refData, timeDim);
                    else
                        F0 = mean(refData, ndims(refData));
                        dF = trialAvgData - F0;
                    end
                end
                
                if get(hDivideByF0Checkbox, 'Value') == 1
                    processedData = dF ./ (F0 + eps);
                else
                    processedData = dF;
                end
            catch ME
                errMsg = sprintf('dF/F Error:\n%s', ME.message); return;
            end
        end
        
        % Step 3: Apply spatial smoothing (for TIFF mode)
        % Reset the step timer so smoothing time is comparable with/without motion correction.
        resetStatusStepTimer();
        if strcmp(appState.currentMode, 'TIFF')
            sigma_microns = str2double(get(hSmoothingWindowInput, 'String'));
            if ~isnan(sigma_microns) && sigma_microns > 0
                td = ndims(processedData);
                nT = size(processedData, td);
                if td == 4
                    nC = size(processedData, 3);
                    for i = 1:nT
                        for c = 1:nC
                            processedData(:,:,c,i) = applySpatialSmoothing_TIFF(processedData(:,:,c,i), sigma_microns);
                        end
                    end
                else
                    for i = 1:nT
                        processedData(:,:,i) = applySpatialSmoothing_TIFF(processedData(:,:,i), sigma_microns);
                    end
                end
                appendToStatusTimed(sprintf('Applied spatial smoothing (%.1f um).', sigma_microns));
            end
        end
        
        success = true;
    end
    
%% --- UNIFIED MOVIE PLAYER ---
    function launchUnifiedMoviePlayer(precomputedMovie, playerStateToApply, generationState)
        hPlotObject = []; % This will hold handle to scatter or image
        movieTimer = []; % Handle for the timer object
        currentFrameIdx = 1; % Canonical frame index (avoids relying on slider when popup has focus)
        hUndockedFig = []; hUndockedAxes = []; hUndockedPlot = [];
        isSyncingLimits = false;
        hNotesFig = []; % Handle for the notes window
        annotationText = ''; % Variable to hold the notes text
        
        % --- Traces UI/State ---
        hTracesFig = [];
        traceAxes = [];
        traceCursorLine = [];
        tracePerCellLines = [];
        traceAvgLine = [];
        selectedCellIndices = [];
        cellFilterExpr = '';
        traceShowAverageOnly = 1; % Default to average-only for performance
        traceSelectionMode = 'All'; % {'All','Lasso','Filter'}
        traceYLimAuto = 1; % 1=auto scale; 0=fixed (persisted in playerState)
        traceYLim = [];    % [ymin ymax] when fixed
        
        isMultiPlaneMovie = (ndims(precomputedMovie) == 4 && size(precomputedMovie, 3) >= 2);
        numPlanesInMovie = ifelse(isMultiPlaneMovie, size(precomputedMovie, 3), 1);
        isImageData = (ndims(precomputedMovie) == 3) || (ndims(precomputedMovie) == 4 && size(precomputedMovie, 3) >= 2);
        isRgbMovie = (ndims(precomputedMovie) == 4 && size(precomputedMovie, 3) == 3 && ~isMultiPlaneMovie);
        frameRate = generationState.frameRate;
        
        % Check for existing annotation text in the loaded state
        if ~isempty(playerStateToApply) && isfield(playerStateToApply, 'annotationText')
            annotationText = playerStateToApply.annotationText;
        end
        
        try
            numMovieFrames = size(precomputedMovie, ifelse(ndims(precomputedMovie) == 4, 4, ifelse(isImageData, 3, 2)));
            
            hMovieFig = figure('Name', 'Unified Activity Movie Player', 'NumberTitle', 'off', ...
                'Position', [600 100 600, 900], 'Resize', 'on', 'CloseRequestFcn', @stopMovie);
            
            % Store the state that generated this movie
            set(hMovieFig, 'UserData', generationState);

            % --- Define Axes FIRST ---
            hAxes = axes('Parent', hMovieFig, 'Units', 'normalized', 'Position', [0.1 0.35 0.8 0.56]);

            % --- Create Controls AFTER Axes ---
            vareaHandles = [];
            if ~isempty(generationState.Neural.vareaData)
                vareaHandles = createVareaControls(hMovieFig, hAxes, [0.1 0.95 0.8 0.04], generationState);
            end
            
            hTitleEdit = uicontrol('Parent', hMovieFig, 'Style', 'edit', 'String', 'Activity Movie', ...
                'Units', 'normalized', 'Position', [0.1 0.91 0.8 0.03], 'FontSize', 12, ...
                'FontWeight', 'bold', 'BackgroundColor', get(hMovieFig, 'Color'), 'HorizontalAlignment', 'center');

            hPlaybackPanel = uipanel('Parent', hMovieFig, 'Title', 'Playback', 'Units', 'normalized', 'Position', [0.1 0.21 0.8 0.1]);
            displayHandles = createDisplayModeControls(hMovieFig, [0.1 0.16 0.8 0.05]);
            axisUiPanel = uipanel('Parent', hMovieFig, 'Title', 'View Limits', 'Units', 'normalized', 'Position', [0.1 0.31 0.8 0.035]);
            uicontrol('Parent', axisUiPanel, 'Style', 'text', 'String', 'X:', 'Units', 'normalized', 'Position', [0.02 0.12 0.04 0.76], 'HorizontalAlignment', 'left');
            hXMinEdit = uicontrol('Parent', axisUiPanel, 'Style', 'edit', 'String', '', 'Units', 'normalized', 'Position', [0.06 0.15 0.15 0.70], 'Callback', @(s,e) applyAxisLimits_movie());
            hXMaxEdit = uicontrol('Parent', axisUiPanel, 'Style', 'edit', 'String', '', 'Units', 'normalized', 'Position', [0.22 0.15 0.15 0.70], 'Callback', @(s,e) applyAxisLimits_movie());
            uicontrol('Parent', axisUiPanel, 'Style', 'text', 'String', 'Y:', 'Units', 'normalized', 'Position', [0.42 0.12 0.04 0.76], 'HorizontalAlignment', 'left');
            hYMinEdit = uicontrol('Parent', axisUiPanel, 'Style', 'edit', 'String', '', 'Units', 'normalized', 'Position', [0.46 0.15 0.15 0.70], 'Callback', @(s,e) applyAxisLimits_movie());
            hYMaxEdit = uicontrol('Parent', axisUiPanel, 'Style', 'edit', 'String', '', 'Units', 'normalized', 'Position', [0.62 0.15 0.15 0.70], 'Callback', @(s,e) applyAxisLimits_movie());
            hAxisApplyBtn = uicontrol('Parent', axisUiPanel, 'Style', 'pushbutton', 'String', 'Apply', 'Units', 'normalized', 'Position', [0.78 0.15 0.10 0.70], 'Callback', @(s,e) applyAxisLimits_movie());
            hPopoutBtn = uicontrol('Parent', axisUiPanel, 'Style', 'pushbutton', 'String', 'Popout', 'Units', 'normalized', 'Position', [0.89 0.15 0.10 0.70], 'Callback', @(s,e) togglePopout_movie());
            
            hSeekSlider = uicontrol(hPlaybackPanel, 'Style', 'slider', 'Min', 1, 'Max', numMovieFrames, 'Value', 1, 'Units', 'normalized', 'Position', [0.04 0.56 0.92 0.34]);
            seekListener = addlistener(hSeekSlider, 'Value', 'PostSet', @(s,e) seekMovie(hSeekSlider));
            
            hPlayPauseBtn = uicontrol(hPlaybackPanel, 'Style', 'pushbutton', 'String', 'Pause', 'Units', 'normalized', 'Position', [0.02 0.08 0.10 0.34], 'Callback', @togglePlay, 'FontSize', 9);
            uicontrol(hPlaybackPanel, 'Style', 'pushbutton', 'String', 'Stop', 'Units', 'normalized', 'Position', [0.13 0.08 0.10 0.34], 'Callback', @(s,e) stopMovie(), 'FontSize', 9);
            hFrameCounter = uicontrol(hPlaybackPanel, 'Style', 'text', 'String', 'Frame 1/X', 'Units', 'normalized', 'Position', [0.24 0.08 0.2 0.34], 'FontSize', 9);
            uicontrol(hPlaybackPanel, 'Style', 'text', 'String', 'Speed:', 'Units', 'normalized', 'Position', [0.46 0.06 0.08 0.34], 'HorizontalAlignment', 'right', 'FontSize', 9);
            hMovieSpeedDropdown = uicontrol('Parent', hPlaybackPanel, 'Style', 'popupmenu', 'String', {'0.5x', '1x', '2x', '4x', '8x', '16x'}, 'Value', 2, 'Units', 'normalized', 'Position', [0.55 0.08 0.1 0.34], 'Callback', @updateSpeed, 'FontSize', 9);
            uicontrol(hPlaybackPanel, 'Style', 'pushbutton', 'String', 'Notes', 'Units', 'normalized', 'Position', [0.665 0.08 0.11 0.34], 'Callback', @openNotesWindow, 'FontSize', 9);
            uicontrol(hPlaybackPanel, 'Style', 'pushbutton', 'String', 'Save..', 'Units', 'normalized', 'Position', [0.78 0.08 0.11 0.34], 'Callback', @saveMovie, 'FontSize', 9);
            uicontrol(hPlaybackPanel, 'Style', 'pushbutton', 'String', 'Traces', 'Units', 'normalized', 'Position', [0.895 0.08 0.10 0.34], 'Callback', @openTracesWindow, 'FontSize', 8.5);

            % Setup display mode options based on available data
            tiffModes = {'Image', 'Grid'};
            neuralModes = {'Cells', 'Grid'};
            if ~isempty(generationState.Neural.vareaData)
                tiffModes{end+1} = 'Areas';
                neuralModes{end+1} = 'Areas';
            end

            if isImageData % TIFF mode
                set(displayHandles.modeDropdown, 'String', tiffModes);
            else % Neural mode
                set(displayHandles.modeDropdown, 'String', neuralModes);
            end

            hPlaneFalseColorCheckbox = [];
            effectiveMovie = [];
            if isMultiPlaneMovie
                effectiveMovie = sum(precomputedMovie, 3);
            end

            % --- Pre-calculate contrast limits for each display mode BEFORE creating controls ---
            modeContrasts = struct();
            midFrameIdx = round(numMovieFrames / 2);
            if midFrameIdx == 0, midFrameIdx = 1; end

            p = prctile(ifelse(isMultiPlaneMovie, effectiveMovie(:), precomputedMovie(:)), [2 98]);
            if any(isnan(p)) || p(1) >= p(2), p = [0 1]; end
            if isImageData, modeContrasts.Image = p; else, modeContrasts.Cells = p; end
            
            if any(strcmp(get(displayHandles.modeDropdown, 'String'), 'Grid'))
                gridFrame = getModeDataForFrame(midFrameIdx, 'Grid');
                p_grid = prctile(gridFrame(:), [2 98]);
                if any(isnan(p_grid)) || p_grid(1) >= p_grid(2), p_grid = [0 1]; end
                modeContrasts.Grid = p_grid;
            end
            if any(strcmp(get(displayHandles.modeDropdown, 'String'), 'Areas'))
                areaFrame = getModeDataForFrame(midFrameIdx, 'Areas');
                p_area = prctile(areaFrame(:), [2 98]);
                if any(isnan(p_area)) || p_area(1) >= p_area(2), p_area = [0 1]; end
                modeContrasts.Areas = p_area;
            end

            planeContrastPopupFig = [];
            planeContrastLimits = [];
            planePalette = [];
            if isMultiPlaneMovie
                planePalette = lines(numPlanesInMovie);
                planeContrastLimits = zeros(numPlanesInMovie, 2);
                for p = 1:numPlanesInMovie
                    planeData = precomputedMovie(:,:,p,:);
                    pr = prctile(planeData(:), [2 98]);
                    if pr(1) >= pr(2), pr = [0 1]; end
                    planeContrastLimits(p,:) = pr;
                end
            end

            contrastHandles = createContrastControls(hMovieFig, hAxes, [0.1 0.01 0.8 0.09], modeContrasts, displayHandles);
            hPlaneFalseColorCheckbox = uicontrol('Parent', contrastHandles.panel, 'Style', 'checkbox', 'String', 'Multicolor', ...
                'Value', 0, 'Units', 'normalized', 'Position', [0.80 0.10 0.19 0.30], 'Visible', ifelse(isMultiPlaneMovie, 'on', 'off'), ...
                'Callback', @(s,e) planeFalseColorToggled(), 'BackgroundColor', get(contrastHandles.panel, 'BackgroundColor'));
            markerHandles = createMarkerControls(hMovieFig, [0.1 0.10 0.8 0.05]);
            
            set(displayHandles.modeDropdown, 'Callback', @(s,e) displayModeChanged());
            set(displayHandles.gridSizeEdit, 'Callback', @(s,e) displayModeChanged());
            set(displayHandles.interpolateCheckbox, 'Callback', @(s,e) displayModeChanged());
            
            % --- Initialize and start the timer ---
            delay_ms = round((1 / frameRate) * 1000); % Convert to ms and round
            frameDelay = max(1, delay_ms) / 1000; % Enforce 1ms min and convert back to seconds
            
            movieTimer = timer('ExecutionMode', 'fixedRate', 'Period', frameDelay, 'TimerFcn', @advanceFrame);
            
            % --- Apply loaded state BEFORE initial draw, if it exists ---
            if ~isempty(playerStateToApply)
                if isfield(playerStateToApply, 'titleText'), set(hTitleEdit, 'String', playerStateToApply.titleText); end
                set(hMovieSpeedDropdown, 'Value', playerStateToApply.speedValue);
                set(markerHandles.sizeSlider, 'Value', playerStateToApply.markerSize);
                set(markerHandles.shapeDropdown, 'Value', playerStateToApply.markerShapeIndex);
                if isfield(playerStateToApply, 'displayMode'), set(displayHandles.modeDropdown, 'Value', playerStateToApply.displayMode); end
                if isfield(playerStateToApply, 'gridSize'), set(displayHandles.gridSizeEdit, 'String', playerStateToApply.gridSize); end
                if isfield(playerStateToApply, 'interpolate'), set(displayHandles.interpolateCheckbox, 'Value', playerStateToApply.interpolate); end
                if ~isempty(vareaHandles) && isfield(playerStateToApply, 'vareaToggleAllState')
                   set(vareaHandles.toggleAllCheckbox, 'Value', playerStateToApply.vareaToggleAllState);
                   if isfield(playerStateToApply, 'vareaFlipYState')
                         set(vareaHandles.flipYCheckbox, 'Value', playerStateToApply.vareaFlipYState);
                   end
                end
                % Restore traces config if present
                if isfield(playerStateToApply, 'traceSelectionMode'), traceSelectionMode = playerStateToApply.traceSelectionMode; end
                if isfield(playerStateToApply, 'traceSelectionIndices'), selectedCellIndices = playerStateToApply.traceSelectionIndices; end
                if isfield(playerStateToApply, 'traceFilterExpr'), cellFilterExpr = playerStateToApply.traceFilterExpr; end
                if isfield(playerStateToApply, 'traceAverageOnly'), traceShowAverageOnly = playerStateToApply.traceAverageOnly; end
                if isfield(playerStateToApply, 'traceYLimAuto'), traceYLimAuto = playerStateToApply.traceYLimAuto; end
                if isfield(playerStateToApply, 'traceYLim'), traceYLim = playerStateToApply.traceYLim; end
                contrastHandles.setPlayerState(playerStateToApply); % Set contrast state BEFORE display change
            end
            
            displayModeChanged(); % Initial draw, will use loaded state settings if available
            syncAxisLimitEditors_movie();
            try
                addlistener(hAxes, 'XLim', 'PostSet', @(s,e) syncAxisLimitEditors_movie());
                addlistener(hAxes, 'YLim', 'PostSet', @(s,e) syncAxisLimitEditors_movie());
                addlistener(hAxes, 'CLim', 'PostSet', @(s,e) syncMainToUndocked_movie());
            catch
            end
            try
                zObj = zoom(hMovieFig); set(zObj, 'ActionPostCallback', @(s,e) syncAxisLimitEditors_movie());
                pObj = pan(hMovieFig);  set(pObj, 'ActionPostCallback', @(s,e) syncAxisLimitEditors_movie());
            catch
            end
            updateSpeed(); % Sets timer period

            if ~isempty(vareaHandles), vareaHandles.updateAll(); end
            
        catch ME
            set(hText, 'String', sprintf('Error playing movie:\n%s\nLine: %d', ME.message, ME.stack(1).line));
            if isgraphics(hMovieFig), close(hMovieFig); end
            if isobject(movieTimer) && isvalid(movieTimer), delete(movieTimer); end
        end

        % --- Player Nested Functions ---
        function advanceFrame(~,~)
            if ~isgraphics(hMovieFig), stop(movieTimer); return; end
            if currentFrameIdx >= numMovieFrames
                stop(movieTimer);
                set(hPlayPauseBtn, 'String', 'Play');
                return;
            end
            nextFrame = currentFrameIdx + 1;
            seekListener.Enabled = false;
            set(hSeekSlider, 'Value', nextFrame);
            seekListener.Enabled = true;
            currentFrameIdx = nextFrame;
            updateFrame(nextFrame);
        end

        function updateFrame(idx)
            if ~isgraphics(hMovieFig), return; end
            if ~isgraphics(hPlotObject), return; end
            modeOptions = get(displayHandles.modeDropdown, 'String');
            selectedMode = modeOptions{get(displayHandles.modeDropdown, 'Value')};
            
            if isPlaneFalseColorEnabled() && strcmp(selectedMode, 'Image')
                frameP = precomputedMovie(:,:,:,idx);
                rgb = buildPlaneFalseColorFrame(frameP, planeContrastLimits, planePalette);
                currentFrameData = rgb;
            elseif isMultiPlaneMovie
                currentFrameData = effectiveMovie(:,:,idx);
            elseif isRgbMovie
                currentFrameData = precomputedMovie(:,:,:,idx);
            elseif isImageData
                currentFrameData = precomputedMovie(:,:,idx);
            else
                currentFrameData = precomputedMovie(:,idx);
            end

            if strcmp(selectedMode, 'Areas')
                if isempty(vareaHandles), return; end
                isFlipped = get(vareaHandles.flipYCheckbox, 'Value');
                if isRgbMovie, areaInput = mean(currentFrameData, 3); else, areaInput = currentFrameData; end
                [areaImg, ~] = createAreaAverageImage(areaInput, generationState, isFlipped);
                set(hPlotObject, 'CData', areaImg);
            elseif isImageData || isRgbMovie % TIFF Image/Grid (or RGB merge)
                T = generationState.TIFF;
                physW = T.pixelWidth / T.x_pixels_per_unit;
                physH = T.pixelHeight / T.y_pixels_per_unit;
                if strcmp(selectedMode, 'Image')
                    if isPlaneFalseColorEnabled() || isRgbMovie
                        cdata = double(currentFrameData);
                        if size(cdata, 3) ~= 3
                            cdata = mean(cdata, 3); cdata = repmat(cdata, [1 1 3]);
                        end
                        cdata = min(1, max(0, cdata));
                    else
                        cdata = currentFrameData;
                    end
                    set(hPlotObject, 'CData', cdata, 'XData', [0 physW], 'YData', [0 physH]);
                else % Grid (downsampled image)
                    gridSize = str2double(get(displayHandles.gridSizeEdit, 'String'));
                    if isnan(gridSize) || gridSize < 1, gridSize = 30; end
                    if isRgbMovie, grayFrame = mean(currentFrameData, 3); else, grayFrame = currentFrameData; end
                    if get(displayHandles.interpolateCheckbox, 'Value') == 1
                        frameData = imresize(grayFrame, [gridSize gridSize], 'bicubic');
                    else
                        [frameData, ~, ~] = binData_TIFF(grayFrame, generationState.TIFF, gridSize);
                    end
                    grid_x = linspace(0, physW, gridSize);
                    grid_y = linspace(0, physH, gridSize);
                    set(hPlotObject, 'CData', frameData, 'XData', grid_x, 'YData', grid_y);
                end
            else % Neural Data
                if strcmp(selectedMode, 'Cells')
                    set(hPlotObject, 'CData', currentFrameData);
                else % Grid
                    gridSize = str2double(get(displayHandles.gridSizeEdit, 'String'));
                    if isnan(gridSize) || gridSize < 1, gridSize = 30; end
                    [binnedFrame, x_centers, y_centers] = binData_Neural(generationState.Neural, currentFrameData, gridSize, generationState.physicalCoords, ...
                        get(displayHandles.interpolateCheckbox, 'Value'));
                    set(hPlotObject, 'XData', x_centers, 'YData', y_centers, 'CData', binnedFrame);
                end
            end
            set(hFrameCounter, 'String', sprintf('Frame %d/%d', idx, numMovieFrames));
            updateTraceCursor(idx);
            refreshUndocked_movie();
            drawnow('update');
            syncAxisLimitEditors_movie();
        end

        function displayModeChanged()
            stop(movieTimer);
            modeIdx = get(displayHandles.modeDropdown, 'Value');
            modeOptions = get(displayHandles.modeDropdown, 'String');
            selectedMode = modeOptions{modeIdx};
            
            set(markerHandles.panel, 'Visible', ifelse(strcmp(selectedMode, 'Cells'), 'on', 'off'));
            set(displayHandles.gridSizeEdit, 'Visible', ifelse(strcmp(selectedMode, 'Grid'), 'on', 'off'));
            set(displayHandles.gridSizeLabel, 'Visible', ifelse(strcmp(selectedMode, 'Grid'), 'on', 'off'));
            set(displayHandles.interpolateCheckbox, 'Visible', ifelse(strcmp(selectedMode, 'Grid'), 'on', 'off'));

            currentFrameIdx = round(get(hSeekSlider, 'Value'));
            if isgraphics(hPlotObject), delete(hPlotObject); end
            
            if strcmp(selectedMode, 'Cells')
                hPlotObject = scatter(hAxes, generationState.physicalCoords(:,1), generationState.physicalCoords(:,2), ...
                    get(markerHandles.sizeSlider, 'Value'), precomputedMovie(:, currentFrameIdx), ...
                    'filled', 'Marker', markerHandles.shapeValues{get(markerHandles.shapeDropdown, 'Value')});
                set(markerHandles.panel, 'UserData', hPlotObject);
            else % Grid, Image, or Area mode - all use imagesc
                if isImageData % TIFF
                    T = generationState.TIFF;
                    physW = T.pixelWidth / T.x_pixels_per_unit;
                    physH = T.pixelHeight / T.y_pixels_per_unit;
                end
                if (isRgbMovie || isPlaneFalseColorEnabled()) && strcmp(selectedMode, 'Image')
                    if isRgbMovie
                        firstCData = precomputedMovie(:,:,:,currentFrameIdx);
                        firstCData = double(squeeze(firstCData));
                        firstCData = min(1, max(0, firstCData));
                    else
                        firstCData = buildPlaneFalseColorFrame(precomputedMovie(:,:,:,currentFrameIdx), planeContrastLimits, planePalette);
                    end
                    if size(firstCData, 3) == 3
                        hPlotObject = imagesc(hAxes, [0 physW], [0 physH], firstCData);
                    else
                        hPlotObject = imagesc(hAxes, 'CData', []);
                        set(hPlotObject, 'XData', [0 physW], 'YData', [0 physH]);
                    end
                else
                    hPlotObject = imagesc(hAxes, 'CData', []);
                    if isImageData % TIFF
                        set(hPlotObject, 'XData', [0 physW], 'YData', [0 physH]);
                    else % Neural (Area or Grid Mode)
                        N = generationState.Neural;
                        set(hPlotObject, 'XData', N.plotXLim, 'YData', N.plotYLim);
                    end
                end
                updateFrame(currentFrameIdx); % Draw the frame (sync counter; redundant CData when we already set firstCData)
            end
            
            setupPlotAxes(hAxes, generationState.mode, generationState.TIFF, generationState.Neural);
            set(hAxes, 'YDir', 'normal');
            
            contrastHandles.resetSliders(selectedMode);
            
            if ~isempty(vareaHandles), vareaHandles.updateAll(); end
            contrastHandles.reapplyColormap();
            
            if strcmp(get(hPlayPauseBtn, 'String'), 'Pause')
                start(movieTimer);
            end
            refreshUndocked_movie();
            syncAxisLimitEditors_movie();
        end
        
        function data = getModeDataForFrame(idx, modeOverride)
             if nargin < 2 || isempty(modeOverride)
                 modeOptions = get(displayHandles.modeDropdown, 'String');
                 selectedMode = modeOptions{get(displayHandles.modeDropdown, 'Value')};
             else
                 selectedMode = modeOverride;
             end
             
             if isPlaneFalseColorEnabled()
                 frameData = buildPlaneFalseColorFrame(precomputedMovie(:,:,:,idx), planeContrastLimits, planePalette);
             elseif isMultiPlaneMovie
                 frameData = effectiveMovie(:,:,idx);
             elseif isRgbMovie
                 frameData = precomputedMovie(:,:,:,idx);
             elseif isImageData
                 frameData = precomputedMovie(:,:,idx);
             else
                 frameData = precomputedMovie(:,idx);
             end

             if strcmp(selectedMode, 'Grid')
                 gridSize = str2double(get(displayHandles.gridSizeEdit, 'String'));
                 if isnan(gridSize) || gridSize < 1, gridSize = 30; end
                 if isImageData || isRgbMovie
                     if ndims(frameData) == 3, grayForBin = mean(frameData, 3); else, grayForBin = frameData; end
                     data = binData_TIFF(grayForBin, generationState.TIFF, gridSize);
                 else
                     [data, ~, ~] = binData_Neural(generationState.Neural, frameData, gridSize, generationState.physicalCoords, get(displayHandles.interpolateCheckbox, 'Value'));
                 end
             elseif strcmp(selectedMode, 'Areas')
                 isFlipped = get(vareaHandles.flipYCheckbox, 'Value');
                 if ndims(frameData) == 3
                     [data, ~] = createAreaAverageImage(mean(frameData, 3), generationState, isFlipped);
                 else
                     [data, ~] = createAreaAverageImage(frameData, generationState, isFlipped);
                 end
             else
                 data = frameData;
             end
        end

        function rgb = buildPlaneFalseColorFrame(frameP, limits, palette)
            H = size(frameP,1); W = size(frameP,2); P = size(frameP,3);
            rgb = zeros(H, W, 3);
            for p = 1:P
                span = limits(p,2) - limits(p,1) + eps;
                s = min(1, max(0, (double(frameP(:,:,p)) - limits(p,1)) / span));
                for c = 1:3
                    rgb(:,:,c) = rgb(:,:,c) + palette(p,c) * s;
                end
            end
            mx = max(rgb(:)); if mx > 0, rgb = rgb / mx; end
            rgb = min(1, max(0, rgb));
        end

        function tf = isPlaneFalseColorEnabled()
            tf = false;
            if ~isMultiPlaneMovie, return; end
            if isempty(hPlaneFalseColorCheckbox) || ~isgraphics(hPlaneFalseColorCheckbox), return; end
            v = get(hPlaneFalseColorCheckbox, 'Value');
            tf = isscalar(v) && logical(v);
        end

        function planeFalseColorToggled()
            checked = get(hPlaneFalseColorCheckbox, 'Value');
            if checked
                set(contrastHandles.cmapDropdown, 'Visible', 'off');
                set(contrastHandles.invertCmap, 'Visible', 'off');
                openPlaneContrastPopup();
            else
                set(contrastHandles.cmapDropdown, 'Visible', 'on');
                set(contrastHandles.invertCmap, 'Visible', 'on');
                if isgraphics(planeContrastPopupFig), close(planeContrastPopupFig); planeContrastPopupFig = []; end
            end
            currentFrameIdx = round(get(hSeekSlider, 'Value'));
            updateFrame(currentFrameIdx);
        end

        function openPlaneContrastPopup()
            if isgraphics(planeContrastPopupFig), figure(planeContrastPopupFig); return; end
            P = numPlanesInMovie;
            planeContrastPopupFig = figure('Name', 'Plane contrast', 'NumberTitle', 'off', 'Position', [700 200 400 min(500, 80+ P*70)]);
            uicontrol(planeContrastPopupFig, 'Style', 'pushbutton', 'String', 'Pause playback', 'Units', 'normalized', ...
                'Position', [0.02 0.92 0.35 0.06], 'Callback', @pausePlaybackFromPopup, 'FontSize', 9);
            hMins = zeros(P,1); hMaxs = zeros(P,1); hMinRanges = zeros(P,1); hMaxRanges = zeros(P,1);
            rangeOptions = {'0.5x', '1x', '2x', '4x', '8x'};
            rangeVals = [0.5, 1, 2, 4, 8];
            for p = 1:P
                idx = p;
                y = 1 - (p-0.5)/max(P,1);
                uicontrol(planeContrastPopupFig, 'Style', 'text', 'String', sprintf('Plane %d', p), 'Units', 'normalized', 'Position', [0.02 y-0.03 0.15 0.06]);
                lo = planeContrastLimits(p,1); hi = planeContrastLimits(p,2);
                hMins(p) = uicontrol(planeContrastPopupFig, 'Style', 'slider', 'Units', 'normalized', 'Position', [0.18 y 0.24 0.04], 'Min', lo-1, 'Max', lo+1, 'Value', lo, 'UserData', lo);
                hMinRanges(p) = uicontrol(planeContrastPopupFig, 'Style', 'popupmenu', 'String', rangeOptions, 'Value', 2, 'Units', 'normalized', 'Position', [0.43 y 0.08 0.04]);
                hMaxs(p) = uicontrol(planeContrastPopupFig, 'Style', 'slider', 'Units', 'normalized', 'Position', [0.55 y 0.24 0.04], 'Min', hi-1, 'Max', hi+1, 'Value', hi, 'UserData', hi);
                hMaxRanges(p) = uicontrol(planeContrastPopupFig, 'Style', 'popupmenu', 'String', rangeOptions, 'Value', 2, 'Units', 'normalized', 'Position', [0.80 y 0.08 0.04]);
                set(hMinRanges(p), 'Callback', @(s,e) updatePlaneSliderRanges(idx));
                set(hMaxRanges(p), 'Callback', @(s,e) updatePlaneSliderRanges(idx));
                addlistener(hMins(p), 'Value', 'PostSet', @(s,e) syncPlaneLimitsFromPopup());
                addlistener(hMaxs(p), 'Value', 'PostSet', @(s,e) syncPlaneLimitsFromPopup());
            end
            for pp = 1:P
                updatePlaneSliderRanges(pp);
            end
            uicontrol(planeContrastPopupFig, 'Style', 'text', 'String', 'Black', 'Units', 'normalized', 'Position', [0.18 0.96 0.1 0.03]);
            uicontrol(planeContrastPopupFig, 'Style', 'text', 'String', 'White', 'Units', 'normalized', 'Position', [0.55 0.96 0.1 0.03]);
            function updatePlaneSliderRanges(pp)
                lo = get(hMins(pp), 'UserData');
                hi = get(hMaxs(pp), 'UserData');
                baseRange = abs(hi - lo); if baseRange <= 0, baseRange = 1; end
                multMin = rangeVals(get(hMinRanges(pp), 'Value'));
                multMax = rangeVals(get(hMaxRanges(pp), 'Value'));
                halfMin = baseRange * multMin;
                halfMax = baseRange * multMax;
                newMinLo = lo - halfMin; newMinHi = lo + halfMin;
                newMaxLo = hi - halfMax; newMaxHi = hi + halfMax;
                set(hMins(pp), 'Min', newMinLo, 'Max', newMinHi);
                set(hMaxs(pp), 'Min', newMaxLo, 'Max', newMaxHi);
                cv = get(hMins(pp), 'Value'); set(hMins(pp), 'Value', max(newMinLo, min(newMinHi, cv)));
                cv = get(hMaxs(pp), 'Value'); set(hMaxs(pp), 'Value', max(newMaxLo, min(newMaxHi, cv)));
                syncPlaneLimitsFromPopup();
            end

            function syncPlaneLimitsFromPopup()
                if ~isgraphics(planeContrastPopupFig), return; end
                if ~isgraphics(hMovieFig) || ~isgraphics(hSeekSlider)
                    try, if isgraphics(planeContrastPopupFig), close(planeContrastPopupFig); end, catch, end
                    planeContrastPopupFig = [];
                    return;
                end
                for pp = 1:numel(hMins)
                    if hMins(pp) == 0 || ~isgraphics(hMins(pp)), continue; end
                    planeContrastLimits(pp,1) = get(hMins(pp), 'Value');
                    planeContrastLimits(pp,2) = get(hMaxs(pp), 'Value');
                end
                currentFrameIdx = max(1, min(numMovieFrames, round(get(hSeekSlider, 'Value'))));
                updateFrame(currentFrameIdx);
            end

            function pausePlaybackFromPopup(~,~)
                if ~isgraphics(hMovieFig), return; end
                if isobject(movieTimer) && isvalid(movieTimer) && strcmp(get(movieTimer, 'Running'), 'on')
                    stop(movieTimer);
                    set(hPlayPauseBtn, 'String', 'Play');
                end
            end
        end

        function togglePlay(~,~)
            if strcmp(get(movieTimer, 'Running'), 'on')
                stop(movieTimer);
                set(hPlayPauseBtn, 'String', 'Play');
            else
                if currentFrameIdx >= numMovieFrames
                    currentFrameIdx = 1;
                    set(hSeekSlider, 'Value', 1);
                    updateFrame(1);
                end
                start(movieTimer);
                set(hPlayPauseBtn, 'String', 'Pause');
            end
        end

        function stopMovie(~,~)
            if isobject(movieTimer) && isvalid(movieTimer)
                stop(movieTimer);
                delete(movieTimer);
            end
            if isgraphics(hNotesFig), delete(hNotesFig); end
            if isgraphics(hTracesFig), delete(hTracesFig); end
            if isgraphics(planeContrastPopupFig), close(planeContrastPopupFig); planeContrastPopupFig = []; end
            if isscalar(hUndockedFig) && isgraphics(hUndockedFig), close(hUndockedFig); hUndockedFig = []; end
            if isgraphics(hMovieFig), delete(hMovieFig); end
        end

        function seekMovie(source)
            stop(movieTimer);
            set(hPlayPauseBtn, 'String', 'Play');
            currentFrameIdx = round(get(source, 'Value'));
            currentFrameIdx = max(1, min(numMovieFrames, currentFrameIdx));
            updateFrame(currentFrameIdx);
        end

        function updateSpeed(~,~)
            speedOptions = {0.5, 1, 2, 4, 8, 16};
            speedMultiplier = speedOptions{get(hMovieSpeedDropdown, 'Value')};
            
            % --- Use integer millisecond math to avoid floating point precision issues ---
            delay_ms = round((1 / (frameRate * speedMultiplier)) * 1000);
            newFrameDelay = max(1, delay_ms) / 1000; % Enforce 1ms minimum
            
            wasRunning = strcmp(get(movieTimer, 'Running'), 'on');
            if wasRunning, stop(movieTimer); end
            
            set(movieTimer, 'Period', newFrameDelay);
            
            if wasRunning, start(movieTimer); end
        end

        function syncAxisLimitEditors_movie()
            if ~isgraphics(hAxes), return; end
            xl = get(hAxes, 'XLim'); yl = get(hAxes, 'YLim');
            set(hXMinEdit, 'String', sprintf('%.3f', xl(1)));
            set(hXMaxEdit, 'String', sprintf('%.3f', xl(2)));
            set(hYMinEdit, 'String', sprintf('%.3f', yl(1)));
            set(hYMaxEdit, 'String', sprintf('%.3f', yl(2)));
            syncMainToUndocked_movie();
        end

        function applyAxisLimits_movie()
            if ~isgraphics(hAxes), return; end
            x1 = str2double(get(hXMinEdit, 'String'));
            x2 = str2double(get(hXMaxEdit, 'String'));
            y1 = str2double(get(hYMinEdit, 'String'));
            y2 = str2double(get(hYMaxEdit, 'String'));
            if any(isnan([x1 x2 y1 y2])) || x2 <= x1 || y2 <= y1
                syncAxisLimitEditors_movie();
                return;
            end
            xlim(hAxes, [x1 x2]); ylim(hAxes, [y1 y2]);
            syncAxisLimitEditors_movie();
        end

        function togglePopout_movie()
            if isscalar(hUndockedFig) && isgraphics(hUndockedFig)
                closeUndocked_movie();
                return;
            end
            p = get(hMovieFig, 'Position');
            popW = max(700, p(3));
            popH = p(4);
            popX = p(1) + 40;
            popY = p(2) + 20;
            hUndockedFig = figure('Name', 'Movie - Popout', 'NumberTitle', 'off', 'Position', [popX popY popW popH], ...
                'Color', 'k', 'CloseRequestFcn', @closeUndocked_movie);
            hUndockedAxes = axes('Parent', hUndockedFig, 'Units', 'normalized', 'Position', [0.02 0.02 0.96 0.96]);
            set(hPopoutBtn, 'String', 'Dock');
            refreshUndocked_movie();
            try
                addlistener(hUndockedAxes, 'XLim', 'PostSet', @(s,e) syncUndockedToMain_movie());
                addlistener(hUndockedAxes, 'YLim', 'PostSet', @(s,e) syncUndockedToMain_movie());
            catch
            end
        end

        function closeUndocked_movie(varargin)
            if isscalar(hUndockedFig) && isgraphics(hUndockedFig), delete(hUndockedFig); end
            hUndockedFig = []; hUndockedAxes = []; hUndockedPlot = [];
            if isscalar(hPopoutBtn) && isgraphics(hPopoutBtn), set(hPopoutBtn, 'String', 'Popout'); end
        end

        function refreshUndocked_movie()
            if ~(isscalar(hUndockedFig) && isgraphics(hUndockedFig)) || ...
               ~(isscalar(hUndockedAxes) && isgraphics(hUndockedAxes)) || ...
               ~(isscalar(hPlotObject) && isgraphics(hPlotObject))
                return;
            end
            pType = get(hPlotObject, 'Type');
            if strcmp(pType, 'image')
                if ~(isscalar(hUndockedPlot) && isgraphics(hUndockedPlot) && strcmp(get(hUndockedPlot, 'Type'), 'image'))
                    cla(hUndockedAxes);
                    hUndockedPlot = imagesc(hUndockedAxes, 'XData', get(hPlotObject, 'XData'), 'YData', get(hPlotObject, 'YData'), 'CData', get(hPlotObject, 'CData'));
                else
                    set(hUndockedPlot, 'XData', get(hPlotObject, 'XData'), 'YData', get(hPlotObject, 'YData'), 'CData', get(hPlotObject, 'CData'));
                end
            elseif strcmp(pType, 'scatter')
                if ~(isscalar(hUndockedPlot) && isgraphics(hUndockedPlot) && strcmp(get(hUndockedPlot, 'Type'), 'scatter'))
                    cla(hUndockedAxes);
                    hUndockedPlot = scatter(hUndockedAxes, get(hPlotObject, 'XData'), get(hPlotObject, 'YData'), get(hPlotObject, 'SizeData'), get(hPlotObject, 'CData'), 'filled');
                else
                    set(hUndockedPlot, 'XData', get(hPlotObject, 'XData'), 'YData', get(hPlotObject, 'YData'), 'SizeData', get(hPlotObject, 'SizeData'), 'CData', get(hPlotObject, 'CData'));
                end
                try, set(hUndockedPlot, 'Marker', get(hPlotObject, 'Marker')); end
            else
                return;
            end
            colormap(hUndockedAxes, colormap(hAxes));
            axis(hUndockedAxes, 'equal');
            set(hUndockedAxes, 'YDir', get(hAxes, 'YDir'), 'XDir', get(hAxes, 'XDir'));
            syncMainToUndocked_movie();
        end

        function syncMainToUndocked_movie()
            if ~(isscalar(hUndockedAxes) && isgraphics(hUndockedAxes)), return; end
            if isSyncingLimits, return; end
            isSyncingLimits = true;
            try
                set(hUndockedAxes, 'XLim', get(hAxes, 'XLim'), 'YLim', get(hAxes, 'YLim'));
                set(hUndockedAxes, 'CLim', get(hAxes, 'CLim'));
                colormap(hUndockedAxes, colormap(hAxes));
            catch
            end
            isSyncingLimits = false;
        end

        function syncUndockedToMain_movie()
            if ~(isscalar(hUndockedAxes) && isgraphics(hUndockedAxes)) || ...
               ~(isscalar(hAxes) && isgraphics(hAxes))
                return;
            end
            if isSyncingLimits, return; end
            isSyncingLimits = true;
            try
                set(hAxes, 'XLim', get(hUndockedAxes, 'XLim'), 'YLim', get(hUndockedAxes, 'YLim'));
            catch
            end
            isSyncingLimits = false;
            syncAxisLimitEditors_movie();
        end
        
        function saveMovie(~,~)
            stop(movieTimer); % Pause movie for saving
            wasPlaying = strcmp(get(hPlayPauseBtn, 'String'), 'Pause');

            [fileName, pathName, filterIndex] = uiputfile(...
                {'*.mat', 'State & Movie (*.mat)'; '*.avi', 'Video (*.avi)'; '*.mp4', 'MP4 H.264 (*.mp4)'}, 'Save As');
            if isequal(fileName, 0)
                if wasPlaying, start(movieTimer); end % Resume if cancelled
                return; 
            end
            savePath = fullfile(pathName, fileName);
            
            if filterIndex == 1 % Save .mat state
                set(hText, 'String', 'Saving state...'); drawnow;
                
                % Retrieve the state that generated the movie
                stateToSave = get(hMovieFig, 'UserData'); 
                
                % --- Lean State Save: Clear raw data before saving ---
                if strcmp(stateToSave.mode, 'Neural')
                    stateToSave.Neural.psthsData = [];
                    stateToSave.Neural.psthsnpData = [];
                end

                % Add the movie data itself
                stateToSave.movieData = precomputedMovie;
                
                % Add the current state of the player's UI controls
                panelUserData = get(contrastHandles.panel, 'UserData');
                pState.titleText = get(hTitleEdit, 'String');
                pState.speedValue = get(hMovieSpeedDropdown, 'Value');
                pState.contrastMin = get(contrastHandles.minSlider, 'Value');
                pState.contrastMax = get(contrastHandles.maxSlider, 'Value');
                pState.customContrasts = panelUserData.customModeContrasts; % Save custom limits
                pState.contrastMinRange = get(contrastHandles.minRange, 'Value');
                pState.contrastMaxRange = get(contrastHandles.maxRange, 'Value');
                pState.colormapName = panelUserData.lastAppliedCmapName;
                pState.colormapInverted = get(contrastHandles.invertCmap, 'Value');
                pState.colormapList = get(contrastHandles.cmapDropdown, 'String');
                pState.markerSize = get(markerHandles.sizeSlider, 'Value');
                pState.markerShapeIndex = get(markerHandles.shapeDropdown, 'Value');
                pState.displayMode = get(displayHandles.modeDropdown, 'Value');
                pState.gridSize = get(displayHandles.gridSizeEdit, 'String');
                pState.interpolate = get(displayHandles.interpolateCheckbox, 'Value');
                pState.annotationText = annotationText; % Save the annotation text
                if ~isempty(vareaHandles)
                    pState.vareaToggleAllState = get(vareaHandles.toggleAllCheckbox, 'Value');
                    pState.vareaFlipYState = get(vareaHandles.flipYCheckbox, 'Value');
                end
                % Persist trace configuration
                pState.traceSelectionMode = traceSelectionMode;
                pState.traceSelectionIndices = selectedCellIndices;
                pState.traceFilterExpr = cellFilterExpr;
                pState.traceAverageOnly = traceShowAverageOnly;
                pState.traceYLimAuto = traceYLimAuto;
                pState.traceYLim = traceYLim;
                stateToSave.playerState = pState;

                try
                    state = stateToSave; % Rename for saving consistency
                    save(savePath, 'state', '-v7.3');
                    set(hText, 'String', sprintf('State saved to:\n%s', savePath));
                catch ME, set(hText, 'String', sprintf('Error saving .mat:\n%s', ME.message)); end
                
            elseif filterIndex == 2 || filterIndex == 3 % Save video (AVI or MP4) with offscreen rendering
                set(hText, 'String', 'Saving video...'); drawnow;
                try
                    % Combined export settings dialog
                    resOptions = {'Native','1080p','1440p','2160p'};
                    resStr = strjoin(resOptions, '|');
                    kDefaultStart = round(get(hSeekSlider,'Value')); if kDefaultStart < 1, kDefaultStart = 1; end
                    kDefaultEnd = numMovieFrames;
                    defaults = {resOptions{2}, num2str(kDefaultStart), num2str(kDefaultEnd), num2str(appState.exportGamma.mp4), num2str(appState.exportGamma.avi)};
                    prompt = {'Resolution (choose: Native|1080p|1440p|2160p):','Start frame (1-based):','End frame:','MP4 gamma:','AVI gamma:'};
                    answ = inputdlg(prompt, 'Export settings', [1 50; 1 20; 1 20; 1 20; 1 20], defaults);
                    if isempty(answ), if wasPlaying, start(movieTimer); end, return; end
                    % Parse resolution
                    resChoice = answ{1};
                    if ~any(strcmp(resOptions, resChoice)), resChoice = '1080p'; end
                    % Parse frames
                    kStart = round(str2double(answ{2})); kEnd = round(str2double(answ{3}));
                    if isnan(kStart), kStart = kDefaultStart; end
                    if isnan(kEnd), kEnd = kDefaultEnd; end
                    if kStart < 1, kStart = 1; end
                    if kEnd > numMovieFrames, kEnd = numMovieFrames; end
                    if kStart > kEnd, kStart = 1; kEnd = numMovieFrames; end
                    % Parse gamma and update session settings
                    gMp4 = str2double(answ{4}); gAvi = str2double(answ{5});
                    if isfinite(gMp4) && gMp4 > 0, appState.exportGamma.mp4 = gMp4; end
                    if isfinite(gAvi) && gAvi > 0, appState.exportGamma.avi = gAvi; end

                    % Determine codec from extension
                    [~,~,ext] = fileparts(savePath);
                    if strcmpi(ext,'.mp4')
                        v = VideoWriter(savePath, 'MPEG-4');
                    else
                        v = VideoWriter(savePath, 'Motion JPEG AVI');
                    end
                    speedMultiplier = [0.5, 1, 2, 4, 8, 16];
                    speedVal = speedMultiplier(get(hMovieSpeedDropdown,'Value'));
                    v.FrameRate = frameRate * speedVal;
                    if isprop(v,'Quality'), v.Quality = 95; end
                    open(v);

                    % Determine aspect and target size (use current zoom/pan from movie player)
                    modeOptions = get(displayHandles.modeDropdown, 'String');
                    selectedMode = modeOptions{get(displayHandles.modeDropdown, 'Value')};
                    isTiffMode = strcmp(generationState.mode, 'TIFF');
                    nativeW = []; nativeH = [];
                    axXLim = get(hAxes, 'XLim'); axYLim = get(hAxes, 'YLim');
                    axYDir = get(hAxes, 'YDir'); axXDir = get(hAxes, 'XDir');
                    if isTiffMode
                        Tloc = generationState.TIFF;
                        dataXExtent = [0, Tloc.pixelWidth/Tloc.x_pixels_per_unit];
                        dataYExtent = [0, Tloc.pixelHeight/Tloc.y_pixels_per_unit];
                    else
                        Nloc = generationState.Neural;
                        dataXExtent = Nloc.plotXLim;
                        dataYExtent = Nloc.plotYLim;
                    end
                    % Aspect from current view (zoomed/panned) so export matches what is played
                    aspect = diff(axXLim) / diff(axYLim);
                    if ~isfinite(aspect) || aspect <= 0, aspect = 1; end
                    % Native dims = cropped view size in pixels (for Native resolution choice)
                    firstDataForSizing = getModeDataForFrame(kStart);
                    if ~strcmp(selectedMode,'Cells') && ~isempty(firstDataForSizing)
                        nR = size(firstDataForSizing,1); nC = size(firstDataForSizing,2);
                        dx = dataXExtent(2)-dataXExtent(1); dy = dataYExtent(2)-dataYExtent(1);
                        if dx<=0, dx=1; end; if dy<=0, dy=1; end
                        c1 = 1 + (nC-1)*(axXLim(1)-dataXExtent(1))/dx; c2 = 1 + (nC-1)*(axXLim(2)-dataXExtent(1))/dx;
                        r1 = 1 + (nR-1)*(axYLim(1)-dataYExtent(1))/dy; r2 = 1 + (nR-1)*(axYLim(2)-dataYExtent(1))/dy;
                        c1 = max(1,min(nC,round(c1))); c2 = max(1,min(nC,round(c2))); r1 = max(1,min(nR,round(r1))); r2 = max(1,min(nR,round(r2)));
                        if c1>c2, [c1,c2]=deal(c2,c1); end; if r1>r2, [r1,r2]=deal(r2,r1); end
                        nativeW = c2 - c1 + 1; nativeH = r2 - r1 + 1;
                    end

                    % Compute target size inline (avoid nested function nesting rules)
                    switch resChoice
                        case 'Native'
                            if ~isempty(nativeW) && ~isempty(nativeH)
                                targetW = nativeW; targetH = nativeH;
                            else
                                targetH = 1080; targetW = max(1, round(targetH * aspect));
                            end
                        case '1080p'
                            targetH = 1080; targetW = max(1, round(targetH * aspect));
                        case '1440p'
                            targetH = 1440; targetW = max(1, round(targetH * aspect));
                        case '2160p'
                            targetH = 2160; targetW = max(1, round(targetH * aspect));
                        otherwise
                            targetH = 1080; targetW = max(1, round(targetH * aspect));
                    end
                    if targetW < 1, targetW = 1; end
                    if targetH < 1, targetH = 1; end
                    % Ensure even dimensions only for MP4 encoder
                    if strcmpi(ext,'.mp4')
                        if mod(targetW,2)~=0, targetW = targetW+1; end
                        if mod(targetH,2)~=0, targetH = targetH+1; end
                    end

                    % Setup offscreen figure/axes (stable export: no figure background in capture)
                    hOffFig = figure('Visible','off','Units','pixels','Position',[100 100 targetW targetH], 'Color','k', ...
                        'InvertHardcopy','off', 'Renderer','painters');
                    hOffAx = axes('Parent',hOffFig, 'Units','normalized','Position',[0 0 1 1], 'Color','k');
                    axis(hOffAx,'off');
                    set(hOffAx,'YDir',axYDir,'XDir',axXDir);
                    colormap(hOffAx, colormap(hAxes));
                    % Lock contrast to current slider values for fidelity
                    try
                        cmin = get(contrastHandles.minSlider,'Value'); cmax = get(contrastHandles.maxSlider,'Value');
                        if isfinite(cmin) && isfinite(cmax) && cmin < cmax
                            % Slightly widen export dynamic range to reduce clipping by encoders
                            span = cmax - cmin; pad = 0.01 * span;
                            caxis(hOffAx, [cmin - pad, cmax + pad]);
                        end
                    catch
                        caxis(hOffAx, get(hAxes,'CLim'));
                    end
                    exportCLim = get(hOffAx,'CLim');
                    exportCMap = colormap(hOffAx);

                    % Plotted object handles
                    offPlot = [];
                    hTextTime = []; hTextSpeed = [];

                    % Initialize offscreen plot and overlays
                    firstData = getModeDataForFrame(1);
                    if strcmp(selectedMode,'Cells')
                        offPlot = scatter(hOffAx, generationState.physicalCoords(:,1), generationState.physicalCoords(:,2), ...
                            get(markerHandles.sizeSlider,'Value'), firstData, 'filled', 'Marker', markerHandles.shapeValues{get(markerHandles.shapeDropdown,'Value')});
                    else
                        offPlot = imagesc(hOffAx, 'CData', firstData);
                        % Match spatial scaling
                        if isTiffMode
                            T = generationState.TIFF;
                            physW = T.pixelWidth / T.x_pixels_per_unit; physH = T.pixelHeight / T.y_pixels_per_unit;
                            set(offPlot,'XData',[0 physW],'YData',[0 physH]);
                        else
                            N = generationState.Neural; set(offPlot,'XData',N.plotXLim,'YData',N.plotYLim);
                        end
                    end
                    setupPlotAxes(hOffAx, generationState.mode, generationState.TIFF, generationState.Neural);
                    axis(hOffAx,'off');
                    % Use current zoom/pan so export matches movie player view
                    xlim(hOffAx, axXLim); ylim(hOffAx, axYLim);
                    % Draw varea overlays once if enabled
                    if ~isempty(generationState.Neural) && ~isempty(generationState.Neural.vareaData)
                        if exist('vareaHandles','var') && ~isempty(vareaHandles) && get(vareaHandles.toggleAllCheckbox,'Value') == 1
                            areaNames = fields(generationState.Neural.vareaData);
                            colorsLocal = lines(numel(areaNames));
                            if isTiffMode
                                Tloc = generationState.TIFF;
                                xLimLoc = [0, Tloc.pixelWidth / Tloc.x_pixels_per_unit];
                                yLimLoc = [0, Tloc.pixelHeight / Tloc.y_pixels_per_unit];
                            else
                                Nloc = generationState.Neural; xLimLoc = Nloc.plotXLim; yLimLoc = Nloc.plotYLim;
                            end
                            doFlipY = get(vareaHandles.flipYCheckbox,'Value');
                            hold(hOffAx,'on');
                            for ai = 1:numel(areaNames)
                                mask = generationState.Neural.vareaData.(areaNames{ai});
                                boundaries = bwboundaries(mask);
                                for kk = 1:length(boundaries)
                                    boundary = boundaries{kk};
                                    scaled_y = (boundary(:,1) ./ size(mask,1)) .* yLimLoc(2);
                                    if doFlipY == 1, scaled_y = yLimLoc(2) - scaled_y; end
                                    scaled_x = (boundary(:,2) ./ size(mask,2)) .* xLimLoc(2);
                                    plot(hOffAx, scaled_x, scaled_y, 'Color', colorsLocal(ai,:), 'LineWidth', 2);
                                end
                            end
                            hold(hOffAx,'off');
                        end
                    end
                    % Overlays
                    overlayFontPx = 36; % fixed pixel size for consistent on-screen size across outputs
                    hTextTime = text(hOffAx, 0.99, 0.97, '', 'Units','normalized','Color','w','FontWeight','bold','BackgroundColor','k','HorizontalAlignment','right','VerticalAlignment','top');
                    set(hTextTime,'FontUnits','pixels','FontSize',overlayFontPx);
                    hTextSpeed = text(hOffAx, 0.99, 0.03, '', 'Units','normalized','Color','w','FontWeight','bold','BackgroundColor','k','HorizontalAlignment','right');
                    set(hTextSpeed,'FontUnits','pixels','FontSize',overlayFontPx);

                    % Render loop
                    nOutFrames = kEnd - kStart + 1;
                    hWait = waitbar(0, sprintf('Saving video... 0/%d', nOutFrames));
                    originalSliderValue = get(hSeekSlider, 'Value');
                    for k = kStart:kEnd
                        frameData = getModeDataForFrame(k);
                        tSec = (k - kStart) / frameRate; tStr = sprintf('t = %.1fs', round(tSec*10)/10);
                        spStr = sprintf('%gx', speedVal);
                        if strcmp(selectedMode,'Cells')
                            set(offPlot,'CData', frameData);
                            set(hTextTime,'String', tStr); set(hTextSpeed,'String', spStr);
                            drawnow;
                            fr = getframe(hOffAx);
                            frameRGB = fr.cdata;
                        else
                            % Image mode: crop to current zoom/pan, then build frame (grayscale + colormap or RGB)
                            set(hTextTime,'String', tStr); set(hTextSpeed,'String', spStr);
                            nR = size(frameData,1); nC = size(frameData,2);
                            dx = dataXExtent(2)-dataXExtent(1); dy = dataYExtent(2)-dataYExtent(1);
                            if dx<=0, dx=1; end; if dy<=0, dy=1; end
                            c1 = 1 + (nC-1)*(axXLim(1)-dataXExtent(1))/dx; c2 = 1 + (nC-1)*(axXLim(2)-dataXExtent(1))/dx;
                            r1 = 1 + (nR-1)*(axYLim(1)-dataYExtent(1))/dy; r2 = 1 + (nR-1)*(axYLim(2)-dataYExtent(1))/dy;
                            c1 = max(1,min(nC,round(c1))); c2 = max(1,min(nC,round(c2))); r1 = max(1,min(nR,round(r1))); r2 = max(1,min(nR,round(r2)));
                            if c1>c2, [c1,c2]=deal(c2,c1); end; if r1>r2, [r1,r2]=deal(r2,r1); end
                            isRgbFrame = (ndims(frameData) == 3 && size(frameData,3) == 3);
                            if isRgbFrame
                                frameDataCropped = frameData(r1:r2, c1:c2, :);
                                if strcmp(axYDir,'normal'), frameDataCropped = flipud(frameDataCropped); end
                                if strcmp(axXDir,'reverse'), frameDataCropped = fliplr(frameDataCropped); end
                                f = double(frameDataCropped);
                                f = min(1, max(0, f));
                                frameRGB = uint8(round(f * 255));
                                frameRGB = imresize(frameRGB, [targetH targetW]);
                            else
                                frameDataCropped = frameData(r1:r2, c1:c2);
                                if strcmp(axYDir,'normal'), frameDataCropped = flipud(frameDataCropped); end
                                if strcmp(axXDir,'reverse'), frameDataCropped = fliplr(frameDataCropped); end
                                n = size(exportCMap, 1);
                                climSpan = exportCLim(2) - exportCLim(1);
                                if climSpan <= 0, climSpan = 1; end
                                norm = (double(frameDataCropped) - exportCLim(1)) / climSpan;
                                norm = min(1, max(0, norm));
                                idx = round(norm * (n - 1)) + 1;
                                idx = min(n, max(1, idx));
                                frameRGB = ind2rgb(idx, exportCMap);
                                frameRGB = uint8(round(frameRGB * 255));
                                frameRGB = imresize(frameRGB, [targetH targetW]);
                            end
                            % Overlay time and speed (insertText if available, else getframe from axes). R2016b+ compatible.
                            overlaysAdded = false;
                            if exist('insertText','file')
                                try
                                    % Use TextColor/BoxColor for R2016b; newer releases also accept FontColor/TextBoxColor
                                    frameRGB = insertText(frameRGB, [targetW - 220, 20], tStr, 'FontSize', 36, 'TextColor', 'white', 'BoxColor', 'black');
                                    frameRGB = insertText(frameRGB, [targetW - 100, targetH - 50], spStr, 'FontSize', 36, 'TextColor', 'white', 'BoxColor', 'black');
                                    overlaysAdded = true;
                                catch
                                end
                            end
                            if ~overlaysAdded
                                set(offPlot,'CData', frameData);
                                drawnow;
                                fr = getframe(hOffAx);
                                frameRGB = fr.cdata;
                            end
                        end
                        writeVideo(v, frameRGB);
                        if ishandle(hWait), waitbar((k - kStart + 1)/nOutFrames, hWait, sprintf('Saving video... %d/%d', (k - kStart + 1), nOutFrames)); end
                    end
                    
                    close(v); if ishandle(hWait), close(hWait); end
                    if isgraphics(hOffFig), close(hOffFig); end
                    updateFrame(round(originalSliderValue)); 
                    set(hText, 'String', sprintf('Video saved to:\n%s\nOutput size: %dx%d\nFrames: %d', savePath, targetW, targetH, nOutFrames));
                catch ME
                    if exist('hWait','var')&&ishandle(hWait), close(hWait); end
                    try, if isgraphics(hOffFig), close(hOffFig); end, end
                    set(hText, 'String', sprintf('Error saving video:\n%s', ME.message));
                end
            end
            
            if wasPlaying, start(movieTimer); end % Resume if it was playing before
        end
        
        function openNotesWindow(~, ~)
            if isempty(hNotesFig) || ~isgraphics(hNotesFig)
                % Create a new figure for notes
                figPos = get(hMovieFig, 'Position');
                hNotesFig = figure('Name', 'Movie Annotations', 'NumberTitle', 'off', ...
                    'Position', [figPos(1)+figPos(3) figPos(2)+figPos(4)-400 300 400], ...
                    'MenuBar', 'none', 'ToolBar', 'none', 'CloseRequestFcn', @closeNotesWindow);
                uicontrol('Parent', hNotesFig, 'Style', 'edit', ...
                    'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.9], ...
                    'Max', 2, 'Min', 0, 'HorizontalAlignment', 'left', ...
                    'FontSize', 10, 'String', annotationText, ...
                    'Callback', @updateAnnotationText);
            else
                % If window exists, just bring it to the front
                figure(hNotesFig);
            end
        end

        % --- Traces UI & Logic ---
        function openTracesWindow(~,~)
            if ndims(precomputedMovie) ~= 2
                warndlg('Traces are available only for Neural movies (cell data).', 'Traces');
                return;
            end
            try
                % Robustly determine if we already have a valid traces figure
                hasTracesFig = false;
                if isscalar(hTracesFig) && isgraphics(hTracesFig)
                    try
                        hasTracesFig = strcmp(get(hTracesFig,'Type'), 'figure');
                    catch
                        hasTracesFig = false;
                    end
                end
                if ~hasTracesFig
                    hTracesFig = figure('Name','Cell Time Traces','NumberTitle','off','Position',[1220 100 600 450], 'CloseRequestFcn', @closeTracesWindow);
                    traceAxes = axes('Parent', hTracesFig, 'Units','normalized','Position',[0.10 0.36 0.85 0.59]);
                    xlabel(traceAxes,'Time (s)'); ylabel(traceAxes,'Activity');
                    
                    % Controls
                    uicontrol('Parent', hTracesFig, 'Style','text','String','Selection:','Units','normalized','Position',[0.10 0.21 0.15 0.06],'HorizontalAlignment','left');
                    hSelPopup = uicontrol('Parent', hTracesFig, 'Style','popupmenu','String',{'All','Lasso','Filter'},'Units','normalized','Position',[0.25 0.21 0.20 0.07], 'Callback', @selectionModeChanged);
                    uicontrol('Parent', hTracesFig, 'Style','pushbutton','String','Lasso...','Units','normalized','Position',[0.47 0.21 0.15 0.07],'Callback', @startLassoSelection);
                    uicontrol('Parent', hTracesFig, 'Style','text','String','Filter expr:','Units','normalized','Position',[0.10 0.12 0.15 0.06],'HorizontalAlignment','left');
                    hFilterEdit = uicontrol('Parent', hTracesFig, 'Style','edit','String',cellFilterExpr,'Units','normalized','Position',[0.25 0.12 0.34 0.07]);
                    uicontrol('Parent', hTracesFig, 'Style','pushbutton','String','+','Units','normalized','Position',[0.60 0.12 0.03 0.07],'FontSize',8,'Callback', @(~,~) openMultiLineEditor(hFilterEdit, 'Cell Filter Expression'));
                    uicontrol('Parent', hTracesFig, 'Style','pushbutton','String','Apply','Units','normalized','Position',[0.64 0.12 0.10 0.07],'Callback', @(s,e) applyFilterExpr(get(hFilterEdit,'String')));
                    hAvgOnly = uicontrol('Parent', hTracesFig, 'Style','checkbox','String','Average only','Value',traceShowAverageOnly,'Units','normalized','Position',[0.76 0.12 0.18 0.07],'Callback', @(src,evt) setAvgOnly(get(src,'Value')));
                    
                    % Y-Limits controls
                    uicontrol('Parent', hTracesFig, 'Style','text','String','Y-limits:','Units','normalized','Position',[0.10 0.03 0.15 0.06],'HorizontalAlignment','left');
                    hYAuto = uicontrol('Parent', hTracesFig, 'Style','checkbox','String','Auto','Value',traceYLimAuto,'Units','normalized','Position',[0.25 0.03 0.12 0.06],'Callback', @toggleYAuto);
                    hYMinEdit = uicontrol('Parent', hTracesFig, 'Style','edit','String','', 'Units','normalized','Position',[0.39 0.03 0.15 0.06]);
                    hYMaxEdit = uicontrol('Parent', hTracesFig, 'Style','edit','String','', 'Units','normalized','Position',[0.56 0.03 0.15 0.06]);
                    uicontrol('Parent', hTracesFig, 'Style','pushbutton','String','Set','Units','normalized','Position',[0.74 0.03 0.09 0.06],'Callback', @applyYLimFromUI);
                    uicontrol('Parent', hTracesFig, 'Style','pushbutton','String','Auto Now','Units','normalized','Position',[0.84 0.03 0.11 0.06],'Callback', @autoScaleOnce);
                    
                    % Initialize Y-lim UI
                    updateYLimUIFromAxes();
                    setYLimUIEnabled();

                    % Share handles for use by other callbacks
                    tracesUI.hFilterEdit = hFilterEdit;
                    tracesUI.hSelPopup = hSelPopup;
                    tracesUI.hYAuto = hYAuto;
                    tracesUI.hYMinEdit = hYMinEdit;
                    tracesUI.hYMaxEdit = hYMaxEdit;
                    setappdata(hTracesFig, 'tracesUI', tracesUI);
                    
                    % Initialize selection UI state
                    switch traceSelectionMode
                        case 'All', set(hSelPopup,'Value',1);
                        case 'Lasso', set(hSelPopup,'Value',2);
                        case 'Filter', set(hSelPopup,'Value',3);
                    end
                else
                    figure(hTracesFig);
                end
                renderTraces();
            catch ME
                warndlg(sprintf('Error opening traces window:\n%s', ME.message), 'Traces');
            end
            
            function selectionModeChanged(src, ~)
                modes = get(src,'String');
                traceSelectionMode = modes{get(src,'Value')};
                if strcmp(traceSelectionMode,'Lasso')
                    startLassoSelection();
                elseif strcmp(traceSelectionMode,'Filter')
                    % Wait for Apply
                else
                    % All
                    selectedCellIndices = [];
                    renderTraces();
                end
            end
            function setAvgOnly(val)
                traceShowAverageOnly = val;
                renderTraces();
            end
            function toggleYAuto(src, ~)
                traceYLimAuto = get(src,'Value');
                setYLimUIEnabled();
                if traceYLimAuto
                    traceYLim = [];
                    autoScaleOnce();
                else
                    applyYLimFromUI();
                end
            end
            function setYLimUIEnabled()
                if traceYLimAuto
                    set(hYMinEdit,'Enable','off'); set(hYMaxEdit,'Enable','off');
                else
                    set(hYMinEdit,'Enable','on'); set(hYMaxEdit,'Enable','on');
                end
            end
            function updateYLimUIFromAxes()
                if ~(isscalar(traceAxes) && isgraphics(traceAxes)), return; end
                yl = get(traceAxes,'YLim');
                set(hYMinEdit,'String',num2str(yl(1)));
                set(hYMaxEdit,'String',num2str(yl(2)));
            end
            function applyYLimFromUI(~,~)
                if traceYLimAuto, return; end
                ymin = str2double(get(hYMinEdit,'String'));
                ymax = str2double(get(hYMaxEdit,'String'));
                if isnan(ymin) || isnan(ymax) || ymin >= ymax
                    warndlg('Invalid Y-limits. Provide numeric min<max.','Traces');
                    return;
                end
                traceYLim = [ymin ymax];
                if isgraphics(traceAxes), ylim(traceAxes, traceYLim); end
                updateTraceCursor(round(get(hSeekSlider,'Value')));
            end
            function autoScaleOnce(~,~)
                % Let MATLAB auto-scale based on current plot data
                if isgraphics(traceAxes)
                    axis(traceAxes, 'tight');
                    updateYLimUIFromAxes();
                    updateTraceCursor(round(get(hSeekSlider,'Value')));
                end
            end
        end

        function closeTracesWindow(src, ~)
            if isgraphics(src), delete(src); end
            hTracesFig = [];
            traceAxes = [];
            traceCursorLine = [];
            tracePerCellLines = [];
            traceAvgLine = [];
        end

        function applyFilterExpr(expr)
            if nargin<1, expr = cellFilterExpr; end
            try
                idx = evalin('base', expr);
                Ncells = size(precomputedMovie,1);
                if islogical(idx), idx = find(idx);
                elseif ~isnumeric(idx), error('Filter must return numeric or logical indices.'); end
                idx = idx(:)';
                idx = idx(idx>=1 & idx<=Ncells);
                if isempty(idx), error('Filter selected zero valid cells.'); end
                selectedCellIndices = unique(idx);
                cellFilterExpr = expr;
                traceSelectionMode = 'Filter';
                renderTraces();
            catch ME
                warndlg(sprintf('Invalid filter expression:\n%s', ME.message), 'Traces');
            end
        end

        function startLassoSelection(~,~)
            try
                figure(hMovieFig);
                % R2016b-compatible polygon selection using impoly (Image Processing Toolbox)
                hPoly = [];
                useImp = exist('impoly','file') == 2;
                if useImp
                    hPoly = impoly(hAxes);
                    pos = wait(hPoly); % Nx2
                else
                    % Fallback: instruct user and use ginput to collect vertices
                    uiwait(warndlg('Click vertices for polygon, press Enter when done.', 'Lasso Selection','modal'));
                    [xv, yv] = getpoly_manual(hAxes);
                    pos = [xv(:) yv(:)];
                end
                if isempty(pos) || size(pos,2) ~= 2
                    warndlg('No polygon defined.', 'Traces');
                    return;
                end
                coords = generationState.physicalCoords;
                in = inpolygon(coords(:,1), coords(:,2), pos(:,1), pos(:,2));
                selectedCellIndices = find(in);
                if isempty(selectedCellIndices)
                    warndlg('No cells inside selection.', 'Traces');
                    return;
                end
                % Save selection to base workspace and update filter field
                varName = 'nvSelectedIdx';
                try, assignin('base', varName, selectedCellIndices); catch, end
                cellFilterExpr = varName;
                % Try to apply filter expression to set indices via the normal path
                try, applyFilterExpr(varName); catch, end
                traceSelectionMode = 'Filter';
                % Update Traces UI filter field and selection dropdown, if available
                try
                    ui = getappdata(hTracesFig, 'tracesUI');
                    if isstruct(ui)
                        if isfield(ui, 'hFilterEdit') && isgraphics(ui.hFilterEdit), set(ui.hFilterEdit, 'String', varName); end
                        if isfield(ui, 'hSelPopup') && isgraphics(ui.hSelPopup)
                            % Options order is {'All','Lasso','Filter'} => set to 3
                            set(ui.hSelPopup, 'Value', 3);
                        end
                    end
                catch
                end
                renderTraces();
                if useImp && ~isempty(hPoly) && isvalid(hPoly), delete(hPoly); end
            catch ME
                warndlg(sprintf('Lasso selection failed:\n%s', ME.message), 'Traces');
            end
        end

        function [xv, yv] = getpoly_manual(ax)
            if nargin < 1 || isempty(ax), ax = gca; end
            axes(ax);
            [xv, yv] = ginput_n();
            if numel(xv) >= 3
                xv(end+1) = xv(1); yv(end+1) = yv(1); % close
            else
                xv = []; yv = [];
            end
        end

        function [x, y] = ginput_n()
            x = []; y = [];
            % Collect clicks until Enter/Return
            but = 1;
            while ~isempty(but)
                [xi, yi, but] = ginput(1);
                if isempty(but) || any(but == [13 3]) % Enter or Return
                    break;
                end
                x(end+1,1) = xi; %#ok<AGROW>
                y(end+1,1) = yi; %#ok<AGROW>
            end
        end

        function renderTraces()
            % Ensure traces UI exists before attempting to render (use scalar-safe checks)
            if (~(isscalar(hTracesFig) && isgraphics(hTracesFig))) || (~(isscalar(traceAxes) && isgraphics(traceAxes)))
                return;
            end
            % Determine active indices
            Ncells = size(precomputedMovie,1);
            switch traceSelectionMode
                case 'All', activeIdx = 1:Ncells;
                otherwise
                    if isempty(selectedCellIndices), activeIdx = 1:Ncells; else, activeIdx = selectedCellIndices; end
            end
            tSec = (0:size(precomputedMovie,2)-1) ./ frameRate;
            % Clear previous
            if isscalar(traceAvgLine) && isgraphics(traceAvgLine), delete(traceAvgLine); end
            if ~isempty(tracePerCellLines)
                for ii=1:numel(tracePerCellLines)
                    if isscalar(tracePerCellLines(ii)) && isgraphics(tracePerCellLines(ii)), delete(tracePerCellLines(ii)); end
                end
            end
            tracePerCellLines = [];
            % Plot
            axes(traceAxes);
            hold(traceAxes,'off');
            if ~traceShowAverageOnly
                tracePerCellLines = plot(traceAxes, tSec, precomputedMovie(activeIdx, :)');
                hold(traceAxes,'on');
            end
            avgTrace = mean(precomputedMovie(activeIdx, :), 1, 'omitnan');
            traceAvgLine = plot(traceAxes, tSec, avgTrace, 'k', 'LineWidth', 2);
            hold(traceAxes,'on');
            % (Re)create cursor line (R2016b compatible)
            if ~(isscalar(traceCursorLine) && isgraphics(traceCursorLine))
                yl = get(traceAxes, 'YLim');
                traceCursorLine = line(traceAxes, [0 0], yl, 'Color', 'r', 'LineWidth', 1);
            else
                % Ensure the cursor spans current Y-limits
                set(traceCursorLine, 'YData', get(traceAxes, 'YLim'));
            end
            xlim(traceAxes, [tSec(1) tSec(end)]);
            % Apply y-limits per current mode
            if exist('traceYLimAuto','var') && ~traceYLimAuto && exist('traceYLim','var') && ~isempty(traceYLim)
                ylim(traceAxes, traceYLim);
            else
                axis(traceAxes,'tight');
            end
            % Sync UI if it exists
            try
                updateYLimUIFromAxes();
            catch
            end
        end

        function updateTraceCursor(frameIdx)
            if (~(isscalar(hTracesFig) && isgraphics(hTracesFig))) || (~(isscalar(traceAxes) && isgraphics(traceAxes)))
                return;
            end
            t = (frameIdx-1) / frameRate;
            if isscalar(traceCursorLine) && isgraphics(traceCursorLine)
                yl = get(traceAxes, 'YLim');
                set(traceCursorLine, 'XData', [t t], 'YData', yl);
            else
                yl = get(traceAxes, 'YLim');
                traceCursorLine = line(traceAxes, [t t], yl, 'Color', 'r', 'LineWidth', 1);
            end
        end

        function updateAnnotationText(src, ~)
            annotationText = get(src, 'String');
        end

        function closeNotesWindow(src, ~)
            % This function is called when the notes window is closed.
            % We just delete the figure; the text is already saved in annotationText.
            delete(src);
        end
    end
    
%% --- CONTEXT & GENERAL HELPER FUNCTIONS ---
    function switchOperatingContextCallback(~,~)
        isSwitchingContext = true; % Set guard flag to prevent premature caching
        isLoadedContext = get(hContextLoaded, 'Value') == 1;

        if isLoadedContext
            % --- Switch TO Loaded State Context ---
            % Snapshot current session UI so we can faithfully restore later
            cacheCurrentUIState(appState.currentMode);

            % Prefer the loaded slot matching the current session mode
            desiredMode = appState.currentMode;
            picked = false;
            if isfield(appState.loadedState, desiredMode) && ~isempty(appState.loadedState.(desiredMode))
                appState.loadedStateSnapshot = appState.loadedState.(desiredMode);
                appState.activeLoadedMode = desiredMode;
                picked = true;
            end
            
            % If not available for the current mode, do not auto-fallback to other mode
            % Instead, revert to session and inform the user for clarity
            if ~picked
                set(hContextSession, 'Value', 1);
                set(hContextLoaded, 'Value', 0);
                isSwitchingContext = false;
                appendToStatus(sprintf('No loaded state available for %s mode. Load a state in this mode or switch modes.', desiredMode));
                return;
            end

            if ~isempty(appState.loadedStateSnapshot)
                loadedMode = getStateMode(appState.loadedStateSnapshot);
                
                % Update the dropdown, which will trigger the modeSwitchCallback
                set(hModeSelector, 'Value', ifelse(strcmp(loadedMode, 'TIFF'), 1, 2));
                modeSwitchCallback(hModeSelector); % This handles all control visibility updates
                
                % Now that UI is configured for the right mode, populate it with loaded state data
                updateGUIFromState(appState.loadedStateSnapshot);
                % Restore maxFrames if present
                if strcmp(loadedMode,'TIFF') && isfield(appState.loadedStateSnapshot,'ui') && isfield(appState.loadedStateSnapshot.ui,'maxFrames')
                    set(hMaxFramesInput,'String', appState.loadedStateSnapshot.ui.maxFrames);
                end
                showInfoCallback(); 
                set(hModeSelector, 'Enable', 'off');
                set(hContextInfoLabel, 'String', sprintf('Loaded: %s', loadedMode));

                if ~appState.loadedStateSnapshot.reloadRaw
                    setProcessingPanelEnabled(false);
                    appendToStatus('Switched to Loaded State (read-only).');
                else
                    setProcessingPanelEnabled(true);
                    appendToStatus('Switched to Loaded State (raw data available).');
                end

                % Disable load buttons while in Loaded State context
                if strcmp(loadedMode,'TIFF')
                    set(findobj(hTiffLoadPanel,'Type','uicontrol'),'Enable','off');
                else
                    set(findobj(hNeuralLoadPanel,'Type','uicontrol'),'Enable','off');
                end
            end
        else
            % --- Switch BACK TO Session Context ---
            % Persist any UI edits done while in Loaded context back into the loaded slot
            persistLoadedUIToSlot();
            % Choose session mode to restore based on the loaded mode shown
            desiredSessionMode = appState.currentMode;
            if ~isempty(appState.loadedStateSnapshot)
                desiredSessionMode = getStateMode(appState.loadedStateSnapshot);
            elseif ~isempty(appState.activeLoadedMode)
                desiredSessionMode = appState.activeLoadedMode;
            end
            appState.currentMode = desiredSessionMode;
            
            % Update the dropdown and call the mode switcher to restore the entire session UI
            set(hModeSelector, 'Value', ifelse(strcmp(appState.currentMode, 'TIFF'), 1, 2));
            modeSwitchCallback(hModeSelector); % This will call restoreUIStateForCurrentMode
            
            % Finalize UI state
            % Force-restore the explicit session UI snapshot if present to avoid sticky loaded UI
            if isfield(appState.sessionUiCache, appState.currentMode) && ~isempty(appState.sessionUiCache.(appState.currentMode))
                Ssnap = appState.sessionUiCache.(appState.currentMode);
                if strcmp(appState.currentMode,'TIFF')
                    set(hPlaneDropdown,'Value',Ssnap.plane); set(hChannelDropdown,'Value',Ssnap.channel); set(hSmoothingWindowInput,'String',Ssnap.smoothingSigma);
                else
                    set(hNeuropilCoeffInput,'String',Ssnap.neuropilCoeff);
                end
                set(hRollingAvgInput,'String',Ssnap.rollingAvg);
                set(hTrialInput,'String',Ssnap.trials);
                set(hDisplayMode,'Value',Ssnap.displayMode);
                set(hInitialFramesInput,'String',Ssnap.initialFrames);
                set(hRefTrialsInput,'String',Ssnap.refTrials);
                set(hDivideByF0Checkbox,'Value',Ssnap.divideByF0);
                set(hFrameByFrameCheckbox,'Value',Ssnap.frameByFrame);
                set(hDetrendCheckbox,'Value',Ssnap.detrend);
                set(hDetrendWindowInput,'String',Ssnap.detrendWindow);
                set(hForcePositiveCheckbox,'Value',Ssnap.forcePositive);
                updateDisplayMode();
                % Invalidate sessionCache so session recomputation uses restored UI
                appState.sessionCache = struct('data', [], 'fingerprint', []);
            end
            showInfoCallback();
            set(hModeSelector, 'Enable', 'on');
            set(hContextInfoLabel, 'String', sprintf('Session: %s', appState.currentMode));
            % Re-enable load buttons for the active session mode
            if strcmp(appState.currentMode,'TIFF')
                set(findobj(hTiffLoadPanel,'Type','uicontrol'),'Enable','on');
            else
                set(findobj(hNeuralLoadPanel,'Type','uicontrol'),'Enable','on');
            end
            setProcessingPanelEnabled(true);
            appendToStatus('Switched back to Current Session.');
        end
        isSwitchingContext = false; % Unset guard flag
    end

    function setProcessingPanelEnabled(isEnabled)
        % Find all uicontrols within the processing panel and enable/disable them
        controls = findobj(hProcessingPanel, 'Type', 'uicontrol');
        if isEnabled
            set(controls, 'Enable', 'on');
        else
            set(controls, 'Enable', 'off');
        end
    end

    function mode = getStateMode(stateObj)
        if isfield(stateObj, 'mode') && ~isempty(stateObj.mode)
            mode = stateObj.mode;
        elseif isfield(stateObj, 'currentMode') && ~isempty(stateObj.currentMode)
            mode = stateObj.currentMode;
        else
            mode = 'TIFF'; % Fallback
        end
    end

    function state = captureFullState()
        state.mode = appState.currentMode;
        state.TIFF = appState.TIFF;
        state.Neural = appState.Neural;
        state.frameRate = ifelse(strcmp(state.mode, 'TIFF'), state.TIFF.nativeFrameRate, state.Neural.nativeFrameRate);

        % Capture UI settings
        ui.rollingAvg = get(hRollingAvgInput, 'String');
        ui.trials = get(hTrialInput, 'String');
        ui.displayMode = get(hDisplayMode, 'Value');
        ui.initialFrames = get(hInitialFramesInput, 'String');
        ui.refTrials = get(hRefTrialsInput, 'String');
        ui.divideByF0 = get(hDivideByF0Checkbox, 'Value');
        ui.frameByFrame = get(hFrameByFrameCheckbox, 'Value');
        
        if strcmp(state.mode, 'TIFF')
            ui.plane = get(hPlaneDropdown, 'Value');
            ui.channel = get(hChannelDropdown, 'Value');
            ui.smoothingSigma = get(hSmoothingWindowInput, 'String');
            ui.maxFrames = get(hMaxFramesInput, 'String');
            ui.motionCorrect = get(hMotionCorrectCheckbox, 'Value');
            % Bump this token whenever motion-correction internals change to avoid stale cache reuse.
            ui.motionCorrectAlgoVersion = 'mc_robust_refine_v1';
        else
            ui.neuropilCoeff = get(hNeuropilCoeffInput, 'String');
            ui.detrend = get(hDetrendCheckbox, 'Value');
            ui.detrendWindow = get(hDetrendWindowInput, 'String');
            ui.forcePositive = get(hForcePositiveCheckbox, 'Value');
        end
        state.ui = ui;

        % Add physical coordinates if in neural mode
        if strcmp(state.mode, 'Neural') && ~isempty(state.Neural.cellCoords)
            N = state.Neural;
            state.physicalCoords = [N.cellCoords(:,1) ./ N.x_pixels_per_um, N.cellCoords(:,2) ./ N.y_pixels_per_um];
        else
            state.physicalCoords = [];
        end
    end

    function cacheCurrentUIState(modeToCache)
        mode = modeToCache; % Use passed-in mode to ensure correct cache slot is used
        S.rollingAvg = get(hRollingAvgInput, 'String');
        S.trials = get(hTrialInput, 'String');
        S.displayMode = get(hDisplayMode, 'Value');
        S.initialFrames = get(hInitialFramesInput, 'String');
        S.refTrials = get(hRefTrialsInput, 'String');
        S.divideByF0 = get(hDivideByF0Checkbox, 'Value');
        S.frameByFrame = get(hFrameByFrameCheckbox, 'Value');
        S.detrend = get(hDetrendCheckbox, 'Value');
        S.detrendWindow = get(hDetrendWindowInput, 'String');
        S.forcePositive = get(hForcePositiveCheckbox, 'Value');

        if strcmp(mode, 'TIFF')
            S.plane = get(hPlaneDropdown, 'Value');
            S.channel = get(hChannelDropdown, 'Value');
            S.smoothingSigma = get(hSmoothingWindowInput, 'String');
            S.motionCorrect = get(hMotionCorrectCheckbox, 'Value');
            appState.uiStateCache.TIFF = S;
        else
            S.neuropilCoeff = get(hNeuropilCoeffInput, 'String');
            appState.uiStateCache.Neural = S;
        end
    end

    function S = harvestUIStateForMode(mode)
        % Collect current UI control values into a struct without mutating app state caches
        S.rollingAvg = get(hRollingAvgInput, 'String');
        S.trials = get(hTrialInput, 'String');
        S.displayMode = get(hDisplayMode, 'Value');
        S.initialFrames = get(hInitialFramesInput, 'String');
        S.refTrials = get(hRefTrialsInput, 'String');
        S.divideByF0 = get(hDivideByF0Checkbox, 'Value');
        S.frameByFrame = get(hFrameByFrameCheckbox, 'Value');
        S.detrend = get(hDetrendCheckbox, 'Value');
        S.detrendWindow = get(hDetrendWindowInput, 'String');
        S.forcePositive = get(hForcePositiveCheckbox, 'Value');
        if strcmp(mode, 'TIFF')
            S.plane = get(hPlaneDropdown, 'Value');
            S.channel = get(hChannelDropdown, 'Value');
            S.smoothingSigma = get(hSmoothingWindowInput, 'String');
            S.maxFrames = get(hMaxFramesInput, 'String');
            S.motionCorrect = get(hMotionCorrectCheckbox, 'Value');
        else
            S.neuropilCoeff = get(hNeuropilCoeffInput, 'String');
        end
    end

    function persistLoadedUIToSlot()
        % Save current UI control values back into the active loaded state slot, if any
        if isempty(appState.loadedStateSnapshot), return; end
        mode = getStateMode(appState.loadedStateSnapshot);
        S = harvestUIStateForMode(mode);
        L = appState.loadedStateSnapshot;
        L.ui = S;
        appState.loadedStateSnapshot = L;
        if isfield(appState.loadedState, mode)
            appState.loadedState.(mode) = L;
        end
    end

    function restoreUIStateForCurrentMode()
        mode = appState.currentMode;
        if isfield(appState.uiStateCache, mode) && ~isempty(appState.uiStateCache.(mode))
            S = appState.uiStateCache.(mode);
            set(hRollingAvgInput, 'String', S.rollingAvg);
            set(hTrialInput, 'String', S.trials);
            set(hDisplayMode, 'Value', S.displayMode);
            set(hInitialFramesInput, 'String', S.initialFrames);
            set(hRefTrialsInput, 'String', S.refTrials);
            set(hDivideByF0Checkbox, 'Value', S.divideByF0);
            set(hFrameByFrameCheckbox, 'Value', S.frameByFrame);
            set(hDetrendCheckbox, 'Value', S.detrend);
            set(hDetrendWindowInput, 'String', S.detrendWindow);
            set(hForcePositiveCheckbox, 'Value', S.forcePositive);
            
            if strcmp(mode, 'TIFF')
                set(hPlaneDropdown, 'Value', S.plane);
                set(hChannelDropdown, 'Value', S.channel);
                set(hSmoothingWindowInput, 'String', S.smoothingSigma);
                if isfield(S,'maxFrames'), set(hMaxFramesInput,'String', S.maxFrames); end
                if isfield(S,'motionCorrect'), set(hMotionCorrectCheckbox, 'Value', S.motionCorrect); else set(hMotionCorrectCheckbox, 'Value', 0); end
            else
                set(hNeuropilCoeffInput, 'String', S.neuropilCoeff);
            end
            updateDisplayMode(); % Ensure dependent controls visibility is correct
        end
    end

    function updateGUIFromState(state)
        % This function updates the main GUI controls to reflect a state object
        mode = getStateMode(state);

        if strcmp(mode, 'TIFF')
            [planeStrs, chanStrs] = buildTiffDropdownStringsFromState(state);
            set(hPlaneDropdown, 'String', planeStrs);
            set(hChannelDropdown, 'String', chanStrs);
            pVal = clampPopupValue(state.ui.plane, numel(planeStrs));
            cVal = clampPopupValue(state.ui.channel, numel(chanStrs));
            set(hPlaneDropdown, 'Value', pVal);
            set(hChannelDropdown, 'Value', cVal);
            set(hSmoothingWindowInput, 'String', state.ui.smoothingSigma);
            if isfield(state.ui,'maxFrames'), set(hMaxFramesInput,'String', state.ui.maxFrames); end
            if isfield(state.ui,'motionCorrect'), set(hMotionCorrectCheckbox, 'Value', state.ui.motionCorrect); else set(hMotionCorrectCheckbox, 'Value', 0); end
        else % Neural
            set(hNeuropilCoeffInput, 'String', state.ui.neuropilCoeff);
            set(hDetrendCheckbox, 'Value', state.ui.detrend);
            set(hDetrendWindowInput, 'String', state.ui.detrendWindow);
            set(hForcePositiveCheckbox, 'Value', state.ui.forcePositive);
        end
        
        set(hRollingAvgInput, 'String', state.ui.rollingAvg);
        set(hTrialInput, 'String', state.ui.trials);
        set(hDisplayMode, 'Value', state.ui.displayMode);
        set(hInitialFramesInput, 'String', state.ui.initialFrames);
        set(hRefTrialsInput, 'String', state.ui.refTrials);
        set(hDivideByF0Checkbox, 'Value', state.ui.divideByF0);
        set(hFrameByFrameCheckbox, 'Value', state.ui.frameByFrame);
        
        updateDisplayMode();
    end

    function [planeStrs, chanStrs] = buildTiffDropdownStringsFromState(state)
        % Rebuild TIFF dropdown options when loading saved states.
        nPlanes = 1;
        nCh = 1;
        if isfield(state, 'TIFF') && ~isempty(state.TIFF)
            if isfield(state.TIFF, 'parsedNumPlanes') && isfinite(state.TIFF.parsedNumPlanes) && state.TIFF.parsedNumPlanes >= 1
                nPlanes = round(state.TIFF.parsedNumPlanes);
            end
            if isfield(state.TIFF, 'parsedNumChannels') && isfinite(state.TIFF.parsedNumChannels) && state.TIFF.parsedNumChannels >= 1
                nCh = round(state.TIFF.parsedNumChannels);
            end
        end
        % Backward compatibility: if old states missed parsed counts, infer from saved UI values.
        if nPlanes < 2 && isfield(state, 'ui') && isfield(state.ui, 'plane') && isfinite(state.ui.plane) && state.ui.plane > 1
            nPlanes = max(1, round(state.ui.plane) - 1);
        end
        if nCh < 2 && isfield(state, 'ui') && isfield(state.ui, 'channel') && isfinite(state.ui.channel) && state.ui.channel > 1
            nCh = max(1, round(state.ui.channel) - 1);
        end

        planeStrs = arrayfun(@num2str, 1:nPlanes, 'UniformOutput', false);
        chanStrs = arrayfun(@num2str, 1:nCh, 'UniformOutput', false);
        if nPlanes >= 2, planeStrs{end+1} = 'All'; end
        if nCh >= 2, chanStrs{end+1} = 'All'; end
    end

    function v = clampPopupValue(vIn, nOptions)
        if isempty(vIn) || ~isfinite(vIn)
            v = 1; return;
        end
        v = round(vIn);
        if v < 1, v = 1; end
        if v > nOptions, v = nOptions; end
    end

    function updateDisplayInfo()
        if strcmp(appState.currentMode, 'TIFF')
            T = appState.TIFF;
            if ~isempty(T.metadataString)
                set(hText, 'String', T.metadataString);
            else
                set(hText, 'String', 'Welcome to TIFF Viewer Mode! Please select a file or folder.');
            end
        else % Neural
            N = appState.Neural;
            if isempty(N.psthsData) || isempty(N.cellCoords)
                set(hText, 'String', 'Welcome to Neural Data Mode! Please load Data and Coords.');
                return;
            end
            if size(N.psthsData, 1) ~= size(N.cellCoords, 1)
                set(hText, 'String', 'Error: Neuron count mismatch between data and coordinates!');
                return;
            end
            
            [N.numNeurons, N.numTimepoints, N.numTrials] = size(N.psthsData);
            
            vareaFileStr = N.vareaFilePath;
            if isempty(vareaFileStr), vareaFileStr = 'Not loaded'; end

            N.metadataString = sprintf([...
                'Data File: %s\n' ...
                'Coords File: %s\n' ...
                'TIFF Folder: %s\n' ...
                'V. Areas File: %s\n' ...
                '------------------------------------------\n\n' ...
                'Number of Neurons (N): %d\n' ...
                'Number of Timepoints (t): %d\n' ...
                'Number of Trials (R): %d\n' ...
                'Native Frame Rate: %.2f Hz\n' ...
                'FOV Dimensions: %.2f x %.2f (um)\n' ...
                'Pixel Dimensions: %d x %d (px)'], ...
                N.dataFilePath, N.coordsFilePath, N.tiffFolderPath, vareaFileStr, ...
                N.numNeurons, N.numTimepoints, N.numTrials, N.nativeFrameRate, N.plotXLim(2), N.plotYLim(2), N.pixelWidth, N.pixelHeight);
            
            appState.Neural = N;
            set(hText, 'String', N.metadataString);
        end
    end
    
    function appendToStatus(newText)
        oldText = get(hText, 'String');
        % Normalize GUI text across MATLAB versions:
        % - char row vector
        % - char matrix (multi-line)
        % - string scalar/array
        % - cell array of char
        if isstring(oldText)
            oldText = cellstr(oldText);
        elseif ischar(oldText)
            oldText = cellstr(oldText);
        elseif ~iscell(oldText)
            oldText = {char(string(oldText))};
        end
        if isempty(oldText)
            oldText = {};
        end
        firstLine = '';
        if ~isempty(oldText) && ~isempty(oldText{1})
            firstLine = oldText{1};
            if ~ischar(firstLine), firstLine = char(string(firstLine)); end
        end
        if ~isempty(strfind(firstLine, 'Welcome!')) %#ok<STREMP>
            oldText = {};
        end
        % Prepend latest status to the top; metadata appenders will still set full text when needed
        set(hText, 'String', [{newText}; oldText]);
        drawnow;
    end
    
    function resetStatusStepTimer()
        statusStepTic = tic;
    end
    
    function appendToStatusTimed(newText)
        % Append status with seconds elapsed since last resetStatusStepTimer or appendToStatusTimed
        if isempty(statusStepTic)
            tsec = 0;
        else
            tsec = toc(statusStepTic);
        end
        appendToStatus(sprintf('%s [%.2fs]', newText, tsec));
        statusStepTic = tic;
    end
    
    function updateDisplayMode(~,~)
        mode = get(hDisplayMode, 'Value');
        isInitialFrames = (mode == 2);
        isRefTrials = (mode == 4);
        isAnyDf = (mode > 1);
        
        set(hInitialFramesLabel, 'Visible', ifelse(isInitialFrames, 'on', 'off'));
        set(hInitialFramesInput, 'Visible', ifelse(isInitialFrames, 'on', 'off'));
        set(hRefTrialsLabel, 'Visible', ifelse(isRefTrials, 'on', 'off'));
        set(hRefTrialsInput, 'Visible', ifelse(isRefTrials, 'on', 'off'));
        set(hRefTrialsExpandBtn, 'Visible', ifelse(isRefTrials, 'on', 'off'));
        set(hFrameByFrameCheckbox, 'Visible', ifelse(isRefTrials, 'on', 'off'));
        set(hDivideByF0Checkbox, 'Visible', ifelse(isAnyDf, 'on', 'off'));
    end

    function setupPlotAxes(hAxes, mode, T_state, N_state)
        % This function now only sets up the axes geometry, labels, and ticks.
        % Colormap, colorbar, and CLim are handled by createContrastControls.
        axis(hAxes, 'equal');
        
        if strcmp(mode, 'TIFF')
              physW_um = T_state.pixelWidth / T_state.x_pixels_per_unit;
              physH_um = T_state.pixelHeight / T_state.y_pixels_per_unit;
              xlim(hAxes, [0 physW_um]); 
              ylim(hAxes, [0 physH_um]);
        else % Neural
            xlim(hAxes, N_state.plotXLim); 
            ylim(hAxes, N_state.plotYLim);
            set(hAxes, 'YDir', 'normal');
        end
        % Let MATLAB repopulate sensible ticks at any zoom level.
        set(hAxes, 'XTickMode', 'auto', 'YTickMode', 'auto');
        xlabel(hAxes, 'X Position (\mum)'); 
        ylabel(hAxes, 'Y Position (\mum)');
    end
    
    function value = parseSoftwareStr(softwareString, key)
        value = '';
        try
            % Only attempt parsing for text-like inputs; otherwise, gracefully bail out.
            if ~(ischar(softwareString) || isstring(softwareString) || iscellstr(softwareString))
                return;
            end
            softwareString = char(softwareString); % Normalize to char for R2016b+ / R2019a compatibility
            lines = splitlines(softwareString);
            if isstring(lines)
                lines = cellstr(lines);
            end
            for i = 1:numel(lines)
                thisLine = lines{i};
                if ~ischar(thisLine), thisLine = char(thisLine); end
                parts = regexp(thisLine, ' = ', 'split');
                if numel(parts) == 2 && strcmp(strtrim(parts{1}), key)
                    value = strtrim(parts{2});
                    return;
                end
            end
        catch
            % On any parsing failure, just return empty and let callers fall back to defaults
        end
    end
    
    function out = ifelse(condition, true_val, false_val)
        if condition, out = true_val; else, out = false_val; end
    end
    
    function val = ifisfield(s, f)
        if isfield(s,f), val = s.(f); else, val = []; end
    end
    
% --- From here down are mode-specific helpers, prefixed with _TIFF or _Neural ---
%% --- TIFF MODE HELPERS ---
    function processMetadata_TIFF(filePath, displayName)
        T = appState.TIFF;
        frameRateStr = 'N/A'; numPlanes = '1'; numRois = '1'; isMesoscan = 'No'; numChannels = '1';
        physicalDimStr = 'N/A'; trueDimStr = 'N/A'; zoomFactor = 1;
        try
            info = imfinfo(filePath);
            
            if isfield(info(1), 'Software') && ~isempty(info(1).Software)
                softwareStr = info(1).Software;
                frameRateStr = parseSoftwareStr(softwareStr, 'SI.hRoiManager.scanVolumeRate');
                if ~isempty(frameRateStr), T.nativeFrameRate = str2double(frameRateStr); end
                zoomFactorStr = parseSoftwareStr(softwareStr, 'SI.hScan2D.zoomFactor');
                if ~isempty(zoomFactorStr), zoomFactor = str2double(zoomFactorStr); end
                userZsVal = parseSoftwareStr(softwareStr, 'SI.hFastZ.userZs');
                if ~isempty(userZsVal), numPlanes = num2str(numel(str2num(userZsVal))); end %#ok<ST2NM>
                channelsVal = parseSoftwareStr(softwareStr, 'SI.hChannels.channelSave');
                if ~isempty(channelsVal), numChannels = num2str(numel(str2num(channelsVal))); end %#ok<ST2NM>
            end
            if isfield(info(1), 'Artist') && ~isempty(info(1).Artist)
                try
                    artist_info = info(1).Artist;
                    artist_info = char(artist_info); % Normalize to char / string scalar
                    lastBrace = find(artist_info == '}', 1, 'last');
                    if ~isempty(lastBrace)
                        artist_info = artist_info(1:lastBrace);
                    end
                    artist = jsondecode(artist_info);
                    if isfield(artist, 'RoiGroups') && isfield(artist.RoiGroups, 'imagingRoiGroup')
                        si_rois = artist.RoiGroups.imagingRoiGroup.rois;
                        nrois_val = numel(si_rois);
                        numRois = num2str(nrois_val);
                        isMesoscan = ifelse(nrois_val > 1, 'Yes', 'No');
                        T.roiData = si_rois;
                        
                        [pxW, pxH, physW, physH] = getStitchDimensions_TIFF(T.roiData, zoomFactor);
                        T.pixelWidth = pxW; T.pixelHeight = pxH;
                        T.x_pixels_per_unit = pxW / (physW+eps); T.y_pixels_per_unit = pxH / (physH+eps);
                        physicalDimStr = sprintf('%.2f x %.2f mm', physW/1000, physH/1000);
                        trueDimStr = sprintf('%d x %d px', pxW, pxH);
                    end
                catch
                    % If Artist/jsondecode parsing fails (e.g. older/newer TIFF variants), fall back gracefully
                end
            end
            
            % If we didn't get stitched dimensions from Artist, fall back to raw image size
            if strcmp(physicalDimStr, 'N/A') || strcmp(trueDimStr, 'N/A')
                info = imfinfo(filePath);
                pxW = info(1).Width; pxH = info(1).Height;
                T.pixelWidth = pxW; T.pixelHeight = pxH;
                T.x_pixels_per_unit = 1; T.y_pixels_per_unit = 1;
                physicalDimStr = sprintf('%.2f x %.2f mm', pxW, pxH);
                trueDimStr = sprintf('%d x %d px', pxW, pxH);
            end
            
            T.parsedNumPlanes = str2double(numPlanes);
            T.parsedNumChannels = str2double(numChannels);
            nTotalFrames = numel(info);
            nPlanesSafe = max(1, T.parsedNumPlanes);
            nChannelsSafe = max(1, T.parsedNumChannels);
            nVolumes = nTotalFrames / (nPlanesSafe * nChannelsSafe);
            nFramesPerChannel = nTotalFrames / nChannelsSafe;
            planeStrs = arrayfun(@num2str, 1:T.parsedNumPlanes, 'UniformOutput', false);
            if T.parsedNumPlanes >= 2
                planeStrs{end+1} = 'All';
            end
            set(hPlaneDropdown, 'String', planeStrs, 'Value', 1);
            chanStrs = arrayfun(@num2str, 1:T.parsedNumChannels, 'UniformOutput', false);
            if T.parsedNumChannels >= 2
                chanStrs{end+1} = 'All';
            end
            set(hChannelDropdown, 'String', chanStrs, 'Value', 1);
            
            header_text = ifelse(T.isFolderMode, ' Folder: ', ' File: ');
            folderCountLine = '';
            if T.isFolderMode && isfield(T, 'folderFileCount') && T.folderFileCount > 0
                folderCountLine = sprintf('  Number of Files in Folder: %d\n', T.folderFileCount);
            end
            
            T.metadataString = sprintf([...
                '%s%s\n' ...
                '------------------------------------------\n\n' ...
                'GENERAL INFO (from first file)\n' ...
                '%s' ...
                '  Dimensions (WxH): %d x %d\n' ...
                '  Stitched Dimensions (WxH): %s\n' ...
                '  Physical Size: %s\n' ...
                '  Number of Frames (Total): %.0f\n' ...
                '  Number of Frames per Plane (Volumes): %.0f\n' ...
                '  Number of Frames per Channel: %.0f\n\n' ...
                'SCANIMAGE INFO\n' ...
                '  Volume Rate (Hz): %s\n' ...
                '  Number of Planes: %s\n' ...
                '  Number of Channels: %s\n' ...
                '  Number of ROIs: %s\n'], ...
                header_text, displayName, folderCountLine, info(1).Width, info(1).Height, trueDimStr, ...
                physicalDimStr, nTotalFrames, nVolumes, nFramesPerChannel, frameRateStr, numPlanes, numChannels, numRois);
            
            appState.TIFF = T;
            set(hText, 'String', T.metadataString);
        catch
            % On any unexpected error in TIFF metadata parsing, fall back to minimal metadata
            try
                info = imfinfo(filePath);
                pxW = info(1).Width; pxH = info(1).Height;
                T.pixelWidth = pxW; T.pixelHeight = pxH;
                T.x_pixels_per_unit = 1; T.y_pixels_per_unit = 1;
                T.parsedNumPlanes = 1;
                T.parsedNumChannels = 1;
                nTotalFrames = numel(info);
                nVolumes = nTotalFrames;
                nFramesPerChannel = nTotalFrames;
                planeStrs = {'1'};
                chanStrs = {'1'};
                set(hPlaneDropdown, 'String', planeStrs, 'Value', 1);
                set(hChannelDropdown, 'String', chanStrs, 'Value', 1);
                header_text = ifelse(T.isFolderMode, ' Folder: ', ' File: ');
                folderCountLine = '';
                if T.isFolderMode && isfield(T, 'folderFileCount') && T.folderFileCount > 0
                    folderCountLine = sprintf('  Number of Files in Folder: %d\n', T.folderFileCount);
                end
                T.metadataString = sprintf([...
                    '%s%s\n' ...
                    '------------------------------------------\n\n' ...
                    'GENERAL INFO (from first file)\n' ...
                    '%s' ...
                    '  Dimensions (WxH): %d x %d\n' ...
                    '  Stitched Dimensions (WxH): %d x %d px\n' ...
                    '  Physical Size: %.2f x %.2f mm\n' ...
                    '  Number of Frames (Total): %.0f\n' ...
                    '  Number of Frames per Plane (Volumes): %.0f\n' ...
                    '  Number of Frames per Channel: %.0f\n\n' ...
                    'SCANIMAGE INFO\n' ...
                    '  Volume Rate (Hz): %s\n' ...
                    '  Number of Planes: %d\n' ...
                    '  Number of Channels: %d\n' ...
                    '  Number of ROIs: %s\n'], ...
                    header_text, displayName, folderCountLine, info(1).Width, info(1).Height, pxW, pxH, ...
                    pxW, pxH, nTotalFrames, nVolumes, nFramesPerChannel, 'N/A', T.parsedNumPlanes, T.parsedNumChannels, 'N/A');
                appState.TIFF = T;
                set(hText, 'String', T.metadataString);
            catch
                % If even imfinfo fails, leave T as-is and let caller report a generic error
            end
        end
    end

    function [avgMovie, success, errMsg] = computeTrialAverageMovie_TIFF(trialSelectionStr, channelOverride)
        avgMovie = []; success = false; errMsg = '';
        T = appState.TIFF;
        planeVal = get(hPlaneDropdown, 'Value');
        channelVal = get(hChannelDropdown, 'Value');
        if nargin >= 2 && ~isempty(channelOverride)
            isMerge = false;
            channelNum = channelOverride;
        else
            isMerge = (T.parsedNumChannels >= 2 && channelVal == T.parsedNumChannels + 1);
            channelNum = ifelse(isMerge, 1, channelVal);
        end
        % Plane: value 1..N = single plane; value N+1 (when "All" present) = all planes
        if planeVal <= T.parsedNumPlanes
            planeList = planeVal;
        else
            planeList = 1:T.parsedNumPlanes;
        end
        
        try
            % When motionCorrect: each raw stitched frame is registered to the reference BEFORE
            % it is added into the trial average (folder) or movie stack (single file).
            motionCorrect = (get(hMotionCorrectCheckbox, 'Value') == 1);
            ref = [];
            if T.isFolderMode
                evaluatedTrials = evalin('base', trialSelectionStr);
                selectedTrials = ifelse(islogical(evaluatedTrials), find(evaluatedTrials), evaluatedTrials);
                
                trialFilePaths = {}; trialLengths = []; infoFirstPerTrial = {};
                framesPerTrialCh1 = {}; framesPerTrialCh2 = {};
                framesPerTrialPerPlane = {};
                for trialNum = selectedTrials(:)'
                    trialFileName = sprintf('%s_%05d.tif', T.fileBaseName, trialNum);
                    trialFilePath = fullfile(T.selectedFolderPath, trialFileName);
                    if exist(trialFilePath, 'file')
                        trialFilePaths{end+1} = trialFilePath;
                        info = imfinfo(trialFilePath);
                        nF = numel(info);
                        if isMerge
                            framesPerTrialCh1{end+1} = getFramesForPlaneChannel_TIFF(planeList(1), 1, nF);
                            framesPerTrialCh2{end+1} = getFramesForPlaneChannel_TIFF(planeList(1), 2, nF);
                            trialLengths(end+1) = min(numel(framesPerTrialCh1{end}), numel(framesPerTrialCh2{end}));
                        else
                            fp = cell(1, numel(planeList));
                            for p = 1:numel(planeList)
                                fp{p} = getFramesForPlaneChannel_TIFF(planeList(p), channelNum, nF);
                            end
                            framesPerTrialPerPlane{end+1} = fp;
                            trialLengths(end+1) = min(cellfun(@numel, fp));
                        end
                        infoFirstPerTrial{end+1} = info(1);
                    end
                end
                if isempty(trialFilePaths), error('No valid trial files found.'); end
                
                minTrialLength = min(trialLengths);
                maxFramesStr = get(hMaxFramesInput,'String');
                maxFramesVal = str2double(maxFramesStr);
                if ~isnan(maxFramesVal) && maxFramesVal > 0
                    minTrialLength = min(minTrialLength, round(maxFramesVal));
                end
                
                firstFrame = stitchFrame_TIFF(imread(trialFilePaths{1}, 1), infoFirstPerTrial{1}, T.roiData);
                [H, W] = size(firstFrame);
                if motionCorrect
                    nRefFrames = min(50, minTrialLength);
                    refOrdinals = getUniformSampleIdx_TIFF(minTrialLength, nRefFrames);
                    nPl = numel(planeList);
                    if isMerge
                        if nPl == 1
                            fetchRef = @(ord) double(stitchFrame_TIFF(imread(trialFilePaths{1}, framesPerTrialCh1{1}(ord)), infoFirstPerTrial{1}, T.roiData));
                            ref = buildRobustReference_TIFF(fetchRef, refOrdinals);
                        else
                            ref = zeros(H, W, nPl, 'double');
                            for p = 1:nPl
                                nF1 = numel(imfinfo(trialFilePaths{1}));
                                fp1 = getFramesForPlaneChannel_TIFF(planeList(p), 1, nF1);
                                fetchRef = @(ord) double(stitchFrame_TIFF(imread(trialFilePaths{1}, fp1(ord)), infoFirstPerTrial{1}, T.roiData));
                                ref(:, :, p) = buildRobustReference_TIFF(fetchRef, refOrdinals);
                            end
                        end
                    else
                        if nPl == 1
                            fp = framesPerTrialPerPlane{1};
                            fetchRef = @(ord) double(stitchFrame_TIFF(imread(trialFilePaths{1}, fp{1}(ord)), infoFirstPerTrial{1}, T.roiData));
                            ref = buildRobustReference_TIFF(fetchRef, refOrdinals);
                        else
                            ref = zeros(H, W, nPl, 'double');
                            for p = 1:nPl
                                fp = framesPerTrialPerPlane{1};
                                fetchRef = @(ord) double(stitchFrame_TIFF(imread(trialFilePaths{1}, fp{p}(ord)), infoFirstPerTrial{1}, T.roiData));
                                ref(:, :, p) = buildRobustReference_TIFF(fetchRef, refOrdinals);
                            end
                        end
                    end
                    if nPl > 1
                        appendToStatusTimed(sprintf('Built motion-correction references (mean of first %d frames per plane, trial 1).', nRefFrames));
                    else
                        appendToStatusTimed(sprintf('Built motion-correction reference (mean of first %d frames, trial 1).', nRefFrames));
                    end
                end
                if isMerge
                    avgMovie = zeros(H, W, 3, minTrialLength, 'double');
                    nPlM = numel(planeList);
                    if motionCorrect
                        stepStart = tic; % includes read+stitch+sum+normalization
                        mcTime = 0;      % counts time spent inside applyMotionCorrect_TIFF only
                    end
                    for i = 1:minTrialLength
                        sumR = zeros(H, W, 'double'); sumG = zeros(H, W, 'double');
                        for k = 1:numel(trialFilePaths)
                            nFk = numel(imfinfo(trialFilePaths{k}));
                            if nPlM == 1
                                f1 = double(stitchFrame_TIFF(imread(trialFilePaths{k}, framesPerTrialCh1{k}(i)), infoFirstPerTrial{k}, T.roiData));
                                f2 = double(stitchFrame_TIFF(imread(trialFilePaths{k}, framesPerTrialCh2{k}(i)), infoFirstPerTrial{k}, T.roiData));
                                if motionCorrect, mcTic = tic; end
                                f1 = applyMotionCorrect_TIFF(ref, f1, motionCorrect);
                                f2 = applyMotionCorrect_TIFF(ref, f2, motionCorrect);
                                if motionCorrect, mcTime = mcTime + toc(mcTic); end
                            else
                                f1 = 0; f2 = 0;
                                if motionCorrect, mcTic = tic; end
                                for p = 1:nPlM
                                    fp1 = getFramesForPlaneChannel_TIFF(planeList(p), 1, nFk);
                                    fp2 = getFramesForPlaneChannel_TIFF(planeList(p), 2, nFk);
                                    f1 = f1 + applyMotionCorrect_TIFF(ref, double(stitchFrame_TIFF(imread(trialFilePaths{k}, fp1(i)), infoFirstPerTrial{k}, T.roiData)), motionCorrect, [], p);
                                    f2 = f2 + applyMotionCorrect_TIFF(ref, double(stitchFrame_TIFF(imread(trialFilePaths{k}, fp2(i)), infoFirstPerTrial{k}, T.roiData)), motionCorrect, [], p);
                                end
                                if motionCorrect, mcTime = mcTime + toc(mcTic); end
                            end
                            sumR = sumR + f1; sumG = sumG + f2;
                        end
                        sumR = sumR / numel(trialFilePaths); sumG = sumG / numel(trialFilePaths);
                        pr = prctile(sumR(:), [1 99]); pg = prctile(sumG(:), [1 99]);
                        r = (sumR - pr(1)) / (diff(pr) + eps); g = (sumG - pg(1)) / (diff(pg) + eps);
                        avgMovie(:,:,1,i) = min(1, max(0, r));
                        avgMovie(:,:,2,i) = min(1, max(0, g));
                        avgMovie(:,:,3,i) = 0;
                    end
                    if motionCorrect
                        totalTime = toc(stepStart);
                        frameAvgTime = max(0, totalTime - mcTime);
                        appendToStatus(sprintf('Frame averaging [%.2fs]', frameAvgTime));
                        appendToStatus(sprintf('Motion correction registration [%.2fs]', mcTime));
                    end
                else
                    if numel(planeList) > 1
                        avgMovie = zeros(H, W, numel(planeList), minTrialLength, 'double');
                        if motionCorrect
                            stepStart = tic;
                            mcTime = 0;
                        end
                        for i = 1:minTrialLength
                            for p = 1:numel(planeList)
                                sumFrame = zeros(H, W, 'double');
                                for k = 1:numel(trialFilePaths)
                                    fp = framesPerTrialPerPlane{k};
                                    if motionCorrect, mcTic = tic; end
                                    mcFrame = applyMotionCorrect_TIFF(ref, double(stitchFrame_TIFF(imread(trialFilePaths{k}, fp{p}(i)), infoFirstPerTrial{k}, T.roiData)), motionCorrect, [], p);
                                    if motionCorrect, mcTime = mcTime + toc(mcTic); end
                                    sumFrame = sumFrame + mcFrame;
                                end
                                avgMovie(:,:,p,i) = sumFrame / numel(trialFilePaths);
                            end
                        end
                        if motionCorrect
                            totalTime = toc(stepStart);
                            frameAvgTime = max(0, totalTime - mcTime);
                            appendToStatus(sprintf('Frame averaging [%.2fs]', frameAvgTime));
                            appendToStatus(sprintf('Motion correction registration [%.2fs]', mcTime));
                        end
                    else
                        avgMovie = zeros(H, W, minTrialLength, 'double');
                        if motionCorrect
                            stepStart = tic;
                            mcTime = 0;
                        end
                        for i = 1:minTrialLength
                            sumFrame = zeros(H, W, 'double');
                            for k = 1:numel(trialFilePaths)
                                fp = framesPerTrialPerPlane{k};
                                if motionCorrect, mcTic = tic; end
                                mcFrame = applyMotionCorrect_TIFF(ref, double(stitchFrame_TIFF(imread(trialFilePaths{k}, fp{1}(i)), infoFirstPerTrial{k}, T.roiData)), motionCorrect);
                                if motionCorrect, mcTime = mcTime + toc(mcTic); end
                                sumFrame = sumFrame + mcFrame;
                            end
                            avgMovie(:,:,i) = sumFrame / numel(trialFilePaths);
                        end
                        if motionCorrect
                            totalTime = toc(stepStart);
                            frameAvgTime = max(0, totalTime - mcTime);
                            appendToStatus(sprintf('Frame averaging [%.2fs]', frameAvgTime));
                            appendToStatus(sprintf('Motion correction registration [%.2fs]', mcTime));
                        end
                    end
                end
                if ~motionCorrect
                    appendToStatusTimed(sprintf('Folder TIFF complete (%d trials, %d timepoints per trial).', numel(trialFilePaths), minTrialLength));
                end
            else
                info = imfinfo(T.fullFilePath);
                nF = numel(info);
                if isMerge
                    allF1 = getFramesForPlaneChannel_TIFF(planeList(1), 1, nF);
                    allF2 = getFramesForPlaneChannel_TIFF(planeList(1), 2, nF);
                    nT = min(numel(allF1), numel(allF2));
                else
                    allFrames = getFramesForPlaneChannel_TIFF(planeList(1), channelNum, nF);
                    nT = numel(allFrames);
                end
                maxFramesStr = get(hMaxFramesInput,'String');
                maxFramesVal = str2double(maxFramesStr);
                if ~isnan(maxFramesVal) && maxFramesVal > 0
                    nT = min(nT, round(maxFramesVal));
                end
                firstFrame = stitchFrame_TIFF(imread(T.fullFilePath, 1), info(1), T.roiData);
                [H, W] = size(firstFrame);
                if motionCorrect
                    nPlF = numel(planeList);
                    if isMerge
                        nRefFrames = min(50, nT);
                        refOrdinals = getUniformSampleIdx_TIFF(nT, nRefFrames);
                        if nPlF == 1
                            fetchRef = @(ord) double(stitchFrame_TIFF(imread(T.fullFilePath, allF1(ord)), info(1), T.roiData));
                            ref = buildRobustReference_TIFF(fetchRef, refOrdinals);
                        else
                            ref = zeros(H, W, nPlF, 'double');
                            for p = 1:nPlF
                                fp1 = getFramesForPlaneChannel_TIFF(planeList(p), 1, nF);
                                fetchRef = @(ord) double(stitchFrame_TIFF(imread(T.fullFilePath, fp1(ord)), info(1), T.roiData));
                                ref(:, :, p) = buildRobustReference_TIFF(fetchRef, refOrdinals);
                            end
                        end
                    else
                        if nPlF == 1
                            allFramesRef = getFramesForPlaneChannel_TIFF(planeList(1), channelNum, nF);
                            nRefFrames = min(50, numel(allFramesRef));
                            refOrdinals = getUniformSampleIdx_TIFF(numel(allFramesRef), nRefFrames);
                            fetchRef = @(ord) double(stitchFrame_TIFF(imread(T.fullFilePath, allFramesRef(ord)), info(1), T.roiData));
                            ref = buildRobustReference_TIFF(fetchRef, refOrdinals);
                        else
                            ref = zeros(H, W, nPlF, 'double');
                            for p = 1:nPlF
                                fpRef = getFramesForPlaneChannel_TIFF(planeList(p), channelNum, nF);
                                nRefFrames = min(50, numel(fpRef));
                                refOrdinals = getUniformSampleIdx_TIFF(numel(fpRef), nRefFrames);
                                fetchRef = @(ord) double(stitchFrame_TIFF(imread(T.fullFilePath, fpRef(ord)), info(1), T.roiData));
                                ref(:, :, p) = buildRobustReference_TIFF(fetchRef, refOrdinals);
                            end
                        end
                    end
                    if nPlF > 1
                        appendToStatusTimed('Built motion-correction references (mean of first frames per plane).');
                    else
                        appendToStatusTimed(sprintf('Built motion-correction reference (mean of first %d frames).', nRefFrames));
                    end
                end
                % Time split (motion registration vs stack build) for MC-on case.
                if motionCorrect
                    singleStackStartTic = tic; % excludes reference-building time
                    singleMcTime = 0;         % accumulates time inside applyMotionCorrect_TIFF calls
                end
                if isMerge
                    avgMovie = zeros(H, W, 3, nT, 'double');
                    nPlFM = numel(planeList);
                    for i = 1:nT
                        if nPlFM == 1
                            if motionCorrect, mcTic = tic; end
                            f1 = applyMotionCorrect_TIFF(ref, double(stitchFrame_TIFF(imread(T.fullFilePath, allF1(i)), info(1), T.roiData)), motionCorrect);
                            if motionCorrect, singleMcTime = singleMcTime + toc(mcTic); end
                            if motionCorrect, mcTic = tic; end
                            f2 = applyMotionCorrect_TIFF(ref, double(stitchFrame_TIFF(imread(T.fullFilePath, allF2(i)), info(1), T.roiData)), motionCorrect);
                            if motionCorrect, singleMcTime = singleMcTime + toc(mcTic); end
                        else
                            f1 = 0; f2 = 0;
                            for p = 1:nPlFM
                                fp1 = getFramesForPlaneChannel_TIFF(planeList(p), 1, nF);
                                fp2 = getFramesForPlaneChannel_TIFF(planeList(p), 2, nF);
                                if motionCorrect, mcTic = tic; end
                                tmp1 = applyMotionCorrect_TIFF(ref, double(stitchFrame_TIFF(imread(T.fullFilePath, fp1(i)), info(1), T.roiData)), motionCorrect, [], p);
                                if motionCorrect, singleMcTime = singleMcTime + toc(mcTic); end
                                f1 = f1 + tmp1;
                                if motionCorrect, mcTic = tic; end
                                tmp2 = applyMotionCorrect_TIFF(ref, double(stitchFrame_TIFF(imread(T.fullFilePath, fp2(i)), info(1), T.roiData)), motionCorrect, [], p);
                                if motionCorrect, singleMcTime = singleMcTime + toc(mcTic); end
                                f2 = f2 + tmp2;
                            end
                        end
                        pr = prctile(f1(:), [1 99]); pg = prctile(f2(:), [1 99]);
                        avgMovie(:,:,1,i) = min(1, max(0, (f1 - pr(1)) / (diff(pr) + eps)));
                        avgMovie(:,:,2,i) = min(1, max(0, (f2 - pg(1)) / (diff(pg) + eps)));
                        avgMovie(:,:,3,i) = 0;
                    end
                else
                    allFrames = getFramesForPlaneChannel_TIFF(planeList(1), channelNum, nF);
                    if ~isnan(maxFramesVal) && maxFramesVal > 0
                        allFrames = allFrames(1:min(numel(allFrames), round(maxFramesVal)));
                    end
                    if numel(planeList) > 1
                        avgMovie = zeros(H, W, numel(planeList), numel(allFrames), 'double');
                        for i = 1:numel(allFrames)
                            for p = 1:numel(planeList)
                                fp = getFramesForPlaneChannel_TIFF(planeList(p), channelNum, nF);
                                if motionCorrect, mcTic = tic; end
                                tmp = applyMotionCorrect_TIFF(ref, double(stitchFrame_TIFF(imread(T.fullFilePath, fp(i)), info(1), T.roiData)), motionCorrect, [], p);
                                if motionCorrect, singleMcTime = singleMcTime + toc(mcTic); end
                                avgMovie(:,:,p,i) = tmp;
                            end
                        end
                    else
                        avgMovie = zeros(H, W, numel(allFrames), 'double');
                        for i = 1:numel(allFrames)
                            fp = getFramesForPlaneChannel_TIFF(planeList(1), channelNum, nF);
                            if motionCorrect, mcTic = tic; end
                            sumFrame = applyMotionCorrect_TIFF(ref, double(stitchFrame_TIFF(imread(T.fullFilePath, fp(i)), info(1), T.roiData)), motionCorrect);
                            if motionCorrect, singleMcTime = singleMcTime + toc(mcTic); end
                            avgMovie(:,:,i) = sumFrame;
                        end
                    end
                end
                nFramesOut = size(avgMovie, ndims(avgMovie));
                if motionCorrect
                    totalStackTime = toc(singleStackStartTic);
                    frameAvgTime = max(0, totalStackTime - singleMcTime);
                    appendToStatus(sprintf('Single-file TIFF stack complete [%.2fs] (%d frames).', frameAvgTime, nFramesOut));
                    appendToStatus(sprintf('Motion correction registration [%.2fs] (%d frames).', singleMcTime, nFramesOut));
                else
                    appendToStatusTimed(sprintf('Single-file TIFF stack complete (%d frames).', nFramesOut));
                end
            end
            success = true;
        catch ME, errMsg = sprintf('Error processing trials:\n%s', ME.message); end
    end

    function frames = getFramesForPlaneChannel_TIFF(plane, channel, totalFrames)
        T = appState.TIFF;
        startFrame = (plane - 1) * T.parsedNumChannels + channel;
        frameStep = T.parsedNumPlanes * T.parsedNumChannels;
        frames = startFrame:frameStep:totalFrames;
    end

    function ord = getUniformSampleIdx_TIFF(nTotal, nSamples)
        if nTotal < 1 || nSamples < 1
            ord = 1;
            return;
        end
        nSamples = min(nSamples, nTotal);
        ord = unique(max(1, min(nTotal, round(linspace(1, nTotal, nSamples)))));
        if isempty(ord), ord = 1; end
    end

    function ref = buildRobustReference_TIFF(fetchFrameFcn, sampleOrdinals)
        % Build a robust reference in two passes:
        % 1) Mean of sampled frames.
        % 2) Re-register those frames to pass-1 mean and re-average.
        nRefFrames = numel(sampleOrdinals);
        if nRefFrames < 1
            ref = [];
            return;
        end
        f1 = fetchFrameFcn(sampleOrdinals(1));
        [H, W] = size(f1);
        stack = zeros(H, W, nRefFrames, 'double');
        stack(:,:,1) = double(f1);
        for ii = 2:nRefFrames
            stack(:,:,ii) = double(fetchFrameFcn(sampleOrdinals(ii)));
        end
        ref0 = mean(stack, 3);
        alignedSum = zeros(H, W, 'double');
        for ii = 1:nRefFrames
            alignedSum = alignedSum + applyMotionCorrect_TIFF(ref0, stack(:,:,ii), true);
        end
        ref = alignedSum / nRefFrames;
    end

    function [dy, dx] = getPhaseCorrShift_TIFF(ref, img, maxShiftPx)
        % Phase correlation for 2D translation. Returns subpixel [dy, dx]. Optionally clamp to maxShiftPx.
        ref = double(ref); img = double(img);
        % Clip to percentile range to reduce hot pixels / outliers
        pr = prctile(ref(:), [1 99]); ref = min(max(ref, pr(1)), pr(2));
        pr = prctile(img(:), [1 99]); img = min(max(img, pr(1)), pr(2));
        ref = ref - mean(ref(:)); img = img - mean(img(:));
        % Apodize edges to suppress wrap-around peaks in FFT phase correlation.
        persistent wy wx lastH lastW
        [H, W] = size(ref);
        if isempty(lastH) || isempty(lastW) || lastH ~= H || lastW ~= W
            wy = hann(H);
            wx = hann(W);
            lastH = H; lastW = W;
        end
        win2d = wy * wx';
        ref = ref .* win2d;
        img = img .* win2d;
        sigRef = std(ref(:)); sigImg = std(img(:));
        if (sigRef > 1e-10), ref = ref / sigRef; end
        if (sigImg > 1e-10), img = img / sigImg; end
        F_ref = fft2(ref); F_img = fft2(img);
        C = F_ref .* conj(F_img);
        C = C ./ (abs(C) + 1e-10);
        r = real(ifft2(C));
        [~, idx] = max(r(:));
        [iy, ix] = ind2sub(size(r), idx);
        Ly = size(r, 1); Lx = size(r, 2);
        % Subpixel refinement: parabolic fit in 3x3 neighborhood (reduces residual jitter)
        ix_sub = double(ix); iy_sub = double(iy);
        if ix > 1 && ix < Lx
            v = r(iy, ix-1); c = r(iy, ix); w = r(iy, ix+1);
            denom = 2 * (v - 2*c + w + 1e-12);
            if abs(denom) > 1e-12
                delta = (v - w) / denom;
                delta = max(-0.5, min(0.5, delta));
                ix_sub = ix + delta;
            end
        end
        if iy > 1 && iy < Ly
            v = r(iy-1, ix); c = r(iy, ix); w = r(iy+1, ix);
            denom = 2 * (v - 2*c + w + 1e-12);
            if abs(denom) > 1e-12
                delta = (v - w) / denom;
                delta = max(-0.5, min(0.5, delta));
                iy_sub = iy + delta;
            end
        end
        dy = iy_sub - 1; dx = ix_sub - 1;
        if dy > Ly/2, dy = dy - Ly; end
        if dx > Lx/2, dx = dx - Lx; end
        if nargin >= 3 && ~isempty(maxShiftPx) && maxShiftPx > 0
            dy = max(-maxShiftPx, min(maxShiftPx, dy));
            dx = max(-maxShiftPx, min(maxShiftPx, dx));
        end
    end

    function frameOut = applyMotionCorrect_TIFF(ref, frame, doMC, maxShiftPx, planeIdx)
        if ~doMC, frameOut = frame; return; end
        if nargin < 4, maxShiftPx = 25; end  % allow slightly larger corrections; subpixel keeps it smooth
        if nargin < 5, planeIdx = []; end
        % Multi-plane (Plane=All): ref is H x W x P; each plane registers to its own mean reference.
        if ndims(ref) >= 3 && size(ref, 3) > 1
            if isempty(planeIdx), planeIdx = 1; end
            refUse = ref(:, :, planeIdx);
        else
            refUse = ref;
        end
        [dy, dx] = getPhaseCorrShift_TIFF(refUse, frame, maxShiftPx);
        % Apply shift: both signs for MATLAB imtranslate/FFT convention.
        frameOut = imtranslate(frame, [dx, dy], 'OutputView', 'same');
    end

    function [pixelWidth, pixelHeight, physicalWidth, physicalHeight] = getStitchDimensions_TIFF(si_rois, zoom)
        nrois=numel(si_rois); Ly=[]; Lx=[]; cXY=[]; szXY=[];
        for k=1:nrois
            Ly(k,1)=si_rois(k).scanfields(1).pixelResolutionXY(2);
            Lx(k,1)=si_rois(k).scanfields(1).pixelResolutionXY(1);
            cXY(k,[2 1])=si_rois(k).scanfields(1).centerXY;
            szXY(k,[2 1])=si_rois(k).scanfields(1).sizeXY;
        end
        szXY_phys = szXY / zoom;
        cXY_phys = (cXY - szXY/2) - min(cXY - szXY/2, [], 1);
        mu = median([Ly, Lx]./szXY_phys, 1);
        imin_pix = round(cXY_phys .* mu);
        pixelHeight = max(imin_pix(:,1) + Ly);
        pixelWidth = max(imin_pix(:,2) + Lx);
        physicalHeight = max(cXY_phys(:,1) + szXY_phys(:,1));
        physicalWidth = max(cXY_phys(:,2) + szXY_phys(:,2));
        if isfield(si_rois(1).scanfields(1), 'pixelToRefTransform')
            Tscale = 1/si_rois(1).scanfields(1).pixelToRefTransform(1);
            Tscale = 150;
            physicalHeight = physicalHeight*Tscale;
            physicalWidth = physicalWidth*Tscale;
        end
    end
    
    function stitched = stitchFrame_TIFF(rawFrame, header, si_rois)
        [canvas, stitchData] = prepareStitch_TIFF(header, si_rois, class(rawFrame));
        stitched = canvas;
        for i = 1:numel(si_rois)
            roi_strip = rawFrame(stitchData.lines(1,i)+1 : stitchData.lines(2,i), :);
            y_start = round(double(stitchData.dy(i))) + 1;
            y_end = y_start + size(roi_strip,1) - 1;
            x_start = round(double(stitchData.dx(i))) + 1;
            x_end = x_start + size(roi_strip,2) - 1;
            stitched(y_start:y_end, x_start:x_end) = roi_strip;
        end
    end
    
    function [canvas, stitchData] = prepareStitch_TIFF(header, si_rois, frameClass)
        nrois = numel(si_rois); Ly = []; Lx = []; cXY = []; szXY = [];
        for k = 1:nrois
            Ly(k,1) = si_rois(k).scanfields(1).pixelResolutionXY(2);
            Lx(k,1) = si_rois(k).scanfields(1).pixelResolutionXY(1);
            cXY(k, [2 1]) = si_rois(k).scanfields(1).centerXY;
            szXY(k, [2 1]) = si_rois(k).scanfields(1).sizeXY;
        end
        cXY = cXY - szXY/2; cXY = cXY - min(cXY, [], 1);
        mu = median([Ly, Lx]./szXY, 1);
        imin = round(cXY .* mu);
        n_rows_sum = sum(Ly);
        n_flyback = (header.Height - n_rows_sum) / max(1, (nrois - 1));
        irow = [0 cumsum(Ly'+n_flyback)]; irow(end) = []; irow(2,:) = irow(1,:) + Ly';
        stitchData.dx = imin(:,2); stitchData.dy = imin(:,1); stitchData.lines = irow;
        canvasHeight = max(stitchData.dy + Ly); canvasWidth = max(stitchData.dx + Lx);
        canvas = zeros(canvasHeight, canvasWidth, frameClass);
    end

    function smoothedImg = applySpatialSmoothing_TIFF(img, sigma_microns)
        T = appState.TIFF;
        if sigma_microns > 0
            sigma_y_pixels = sigma_microns * T.y_pixels_per_unit;
            sigma_x_pixels = sigma_microns * T.x_pixels_per_unit;
            smoothedImg = imgaussfilt(img, [sigma_y_pixels, sigma_x_pixels]);
        else
            smoothedImg = img;
        end
    end

    function [binnedData, x_centers, y_centers] = binData_TIFF(frameData, T_state, gridSize)
        [origH, origW] = size(frameData);
        physW = origW / T_state.x_pixels_per_unit;
        physH = origH / T_state.y_pixels_per_unit;

        x_binedges = linspace(0, physW, gridSize + 1);
        y_binedges = linspace(0, physH, gridSize + 1);
        
        px_x_phys = linspace(0, physW, origW);
        px_y_phys = linspace(0, physH, origH);
        
        [~, ~, xbin] = histcounts(px_x_phys, x_binedges);
        [~, ~, ybin] = histcounts(px_y_phys, y_binedges);
        
        [X_bin_idx, Y_bin_idx] = meshgrid(xbin, ybin);
        valid_pixels = X_bin_idx > 0 & Y_bin_idx > 0;
        
        sumGrid = accumarray([Y_bin_idx(valid_pixels), X_bin_idx(valid_pixels)], frameData(valid_pixels), [gridSize, gridSize]);
        countGrid = accumarray([Y_bin_idx(valid_pixels), X_bin_idx(valid_pixels)], 1, [gridSize, gridSize]);
        
        binnedData = sumGrid ./ (countGrid + eps);
        x_centers = (x_binedges(1:end-1) + x_binedges(2:end)) / 2;
        y_centers = (y_binedges(1:end-1) + y_binedges(2:end)) / 2;
    end

%% --- NEURAL DATA MODE HELPERS ---
    function processTiffMetadataForInfo_Neural(filePath)
        N = appState.Neural;
        info = imfinfo(filePath);
        zoomFactor = 1;
        
        if isfield(info(1), 'Software') && ~isempty(info(1).Software)
            softwareStr = info(1).Software;
            frameRateStr = parseSoftwareStr(softwareStr, 'SI.hRoiManager.scanVolumeRate');
            if ~isempty(frameRateStr), N.nativeFrameRate = str2double(frameRateStr); end
            zoomFactorStr = parseSoftwareStr(softwareStr, 'SI.hScan2D.zoomFactor');
            if ~isempty(zoomFactorStr), zoomFactor = str2double(zoomFactorStr); end
        end
        if isfield(info(1), 'Artist') && ~isempty(info(1).Artist)
            try
                artist_info = info(1).Artist;
                artist_info = char(artist_info);
                lastBrace = find(artist_info == '}', 1, 'last');
                if ~isempty(lastBrace)
                    artist_info = artist_info(1:lastBrace);
                end
                artist = jsondecode(artist_info);
                if isfield(artist, 'RoiGroups') && isfield(artist.RoiGroups, 'imagingRoiGroup')
                    si_rois = artist.RoiGroups.imagingRoiGroup.rois;
                    [pxW, pxH, physW, physH] = getStitchDimensions_TIFF(si_rois, zoomFactor);
                    N.plotXLim = [0 physW]; N.plotYLim = [0 physH];
                    N.pixelWidth = pxW; N.pixelHeight = pxH;
                    N.y_pixels_per_um = N.pixelHeight / (N.plotYLim(2) + eps);
                    N.x_pixels_per_um = N.pixelWidth / (N.plotXLim(2) + eps);
                end
            catch
                % Gracefully ignore malformed Artist/json in newer MATLAB versions
            end
        end
        appState.Neural = N; % Write back to main state
    end

    function [F_processed, success, errMsg] = preprocessFullSession_Neural()
        F_processed = []; success = false; errMsg = '';
        N = appState.Neural;
        try
            c = str2double(get(hNeuropilCoeffInput, 'String'));
            if isnan(c), error('Neuropil coefficient must be a number.'); end
            F_processed = N.psthsData - c * N.psthsnpData;
            
            if get(hDetrendCheckbox, 'Value')
                win_min = str2double(get(hDetrendWindowInput, 'String'));
                if isnan(win_min) || win_min <=0, error('Invalid detrend window.'); end
                
                % Use a safe native frame rate; older states may not carry it
                nativeFR = 1;
                if isfield(N,'nativeFrameRate') && ~isempty(N.nativeFrameRate) && isfinite(N.nativeFrameRate) && N.nativeFrameRate > 0
                    nativeFR = N.nativeFrameRate;
                else
                    appendToStatusTimed('Native frame rate missing; assuming 1 Hz for detrend window.');
                end
                win_frames = max(1, round(win_min * 60 * nativeFR));
                
                % Derive dimensions from current data to avoid reshape mismatch
                [nNeurons, nTimepoints, nTrials] = size(F_processed);
                F_reshaped = reshape(F_processed, nNeurons, []);
                F_movmedian = movmedian(F_reshaped, win_frames, 2);
                F_detrended_reshaped = F_reshaped - F_movmedian;
                F_processed = reshape(F_detrended_reshaped, nNeurons, nTimepoints, nTrials);
                appendToStatusTimed('Detrended full session (movmedian).');
            end
            
            if get(hForcePositiveCheckbox, 'Value')
                session_min = min(F_processed(:));
                if session_min <= 0
                    offset = -session_min + eps;
                    F_processed = F_processed + offset;
                    appendToStatusTimed(sprintf('Shifted data by %.2f to ensure positive baseline.', offset));
                end
            end
            success = true;
        catch ME, errMsg = sprintf('Preprocessing Error:\n%s', ME.message); end
    end
    
    function [avgData, success, errMsg] = computeTrialAverageData_Neural(trialSelectionStr, F_session_processed)
        avgData = []; success = false; errMsg = '';
        try
            nTrials = size(F_session_processed, 3);
            % Parse selection string with robust fallbacks
            selectedTrials = [];
            str = strtrim(trialSelectionStr);
            if isempty(str) || strcmp(str, ':') || strcmpi(str, 'all')
                selectedTrials = 1:nTrials;
            else
                % Try base workspace first (back-compat for users who define variables there)
                try
                    evalin('base', str);
                    selectedTrials = evalin('base','ans');
                catch
                    selectedTrials = [];
                end
                % If that failed, try evaluating locally after substituting 'end'
                if isempty(selectedTrials)
                    try
                        str_local = regexprep(str, '(?i)\bend\b', num2str(nTrials));
                        selectedTrials = eval(str_local); %#ok<EVLDIR>
                    catch
                        selectedTrials = [];
                    end
                end
                % As a last resort, numeric parse
                if isempty(selectedTrials)
                    try
                        selectedTrials = str2num(str); %#ok<ST2NM>
                    catch
                        selectedTrials = [];
                    end
                end
            end
            if islogical(selectedTrials)
                % Logical mask -> indices
                if numel(selectedTrials) ~= nTrials
                    % Pad/trim to nTrials if shape mismatch
                    selectedTrials = selectedTrials(:)';
                    selectedTrials = selectedTrials(1:min(end,nTrials));
                    if numel(selectedTrials) < nTrials
                        selectedTrials(end+1:nTrials) = false;
                    end
                end
                selectedTrials = find(selectedTrials);
            end
            if ~isnumeric(selectedTrials)
                appendToStatusTimed('Invalid trial selection string; defaulting to all trials.');
                selectedTrials = 1:nTrials;
            end
            selectedTrials = unique(round(selectedTrials(:)'));
            selectedTrials = selectedTrials(selectedTrials >= 1 & selectedTrials <= nTrials);
            if isempty(selectedTrials)
                appendToStatusTimed('Empty/invalid trial selection; defaulting to all trials.');
                selectedTrials = 1:nTrials;
            end
            avgData = mean(F_session_processed(:, :, selectedTrials), 3);
            appendToStatusTimed(sprintf('Averaged %d neural trials.', numel(selectedTrials)));
            success = true;
        catch ME, errMsg = sprintf('Trial Averaging Error:\n%s', ME.message); end
    end
    
    function [binnedData, x_centers, y_centers] = binData_Neural(N_state, dataVector, gridSize, physicalCoords, doInterpolate)
        if isscalar(gridSize), gridSize = [gridSize, gridSize]; end
        x_bins = linspace(N_state.plotXLim(1), N_state.plotXLim(2), gridSize(2) + 1);
        y_bins = linspace(N_state.plotYLim(1), N_state.plotYLim(2), gridSize(1) + 1);
        
        [~, ~, x_bin_indices] = histcounts(physicalCoords(:,1), x_bins);
        [~, ~, y_bin_indices] = histcounts(physicalCoords(:,2), y_bins);
        
        valid_indices = x_bin_indices > 0 & y_bin_indices > 0 & x_bin_indices <= gridSize(2) & y_bin_indices <= gridSize(1);
        
        linear_indices = sub2ind(gridSize, y_bin_indices(valid_indices), x_bin_indices(valid_indices));
        
        sum_grid_vec = accumarray(linear_indices, dataVector(valid_indices), [prod(gridSize) 1]);
        count_grid_vec = accumarray(linear_indices, 1, [prod(gridSize) 1]);
        
        sum_grid = reshape(sum_grid_vec, gridSize);
        count_grid = reshape(count_grid_vec, gridSize);
        
        binnedData = sum_grid ./ (count_grid + eps);
        
        x_centers = (x_bins(1:end-1) + x_bins(2:end)) / 2;
        y_centers = (y_bins(1:end-1) + y_bins(2:end)) / 2;
        
        if nargin > 4 && doInterpolate
            [row, col] = find(count_grid > 0);
            vals = binnedData(count_grid > 0);
            if numel(vals) < 3, return; end % Not enough data to interpolate
            
            [Xq, Yq] = meshgrid(x_centers, y_centers);
            
            F = scatteredInterpolant(x_centers(col)', y_centers(row)', vals, 'linear', 'none');
            interp_grid = F(Xq, Yq);
            
            k = convhull(physicalCoords(:,1), physicalCoords(:,2));
            in_mask = inpolygon(Xq, Yq, physicalCoords(k,1), physicalCoords(k,2));
            
            interp_grid(~in_mask) = NaN; % Set outside points to NaN
            binnedData = interp_grid;
        end
    end

    function [areaImage, areaAverages] = createAreaAverageImage(frameData, state, isFlipped)
        areaAverages = struct();
        vareaData = state.Neural.vareaData;
        if isempty(vareaData), areaImage = frameData; return; end
        
        bin_size_um = 50;
        
        stateMode = getStateMode(state);

        if strcmp(stateMode, 'TIFF')
            T = state.TIFF;
            physW = T.pixelWidth / T.x_pixels_per_unit;
            physH = T.pixelHeight / T.y_pixels_per_unit;
            gridSizeX = max(1, round(physW / bin_size_um));
            gridSizeY = max(1, round(physH / bin_size_um));
            grid_x = linspace(0, physW, gridSizeX);
            grid_y = linspace(0, physH, gridSizeY);
            griddedFrameData = imresize(frameData, [gridSizeY gridSizeX], 'bilinear');
        else % Neural
            N = state.Neural;
            physW = N.plotXLim(2);
            physH = N.plotYLim(2);
            gridSizeX = max(1, round(physW / bin_size_um));
            gridSizeY = max(1, round(physH / bin_size_um));
            [griddedFrameData, grid_x, grid_y] = binData_Neural(N, frameData, [gridSizeY, gridSizeX], state.physicalCoords, false);
        end
        
        [X_grid, Y_grid] = meshgrid(grid_x, grid_y);
        areaImage = NaN(gridSizeY, gridSizeX, 'like', frameData); 
        
        areaNames = fields(vareaData);
        for i = 1:numel(areaNames)
            areaName = areaNames{i};
            originalMask = vareaData.(areaName);
            [maskH, maskW] = size(originalMask);

            boundaries = bwboundaries(originalMask, 'noholes');
            if isempty(boundaries), continue; end
            boundary = boundaries{1};
            
            scaled_y = (boundary(:,1) / maskH) * physH;
            if isFlipped, scaled_y = physH - scaled_y; end
            scaled_x = (boundary(:,2) / maskW) * physW;
            
            if strcmp(stateMode, 'TIFF')
                in_polygon_mask = inpolygon(X_grid, Y_grid, scaled_x, scaled_y);
                currentAreaAvg = mean(griddedFrameData(in_polygon_mask), 'omitnan');
            else % Neural Mode - True average from neuron data
                neurons_in_area_idx = inpolygon(state.physicalCoords(:,1), state.physicalCoords(:,2), scaled_x, scaled_y);
                currentAreaAvg = mean(frameData(neurons_in_area_idx), 'omitnan');
            end

            if isnan(currentAreaAvg), currentAreaAvg = 0; end 
            
            areaAverages.(areaName) = currentAreaAvg;
            
            % Paint the visualization grid
            grid_in_polygon_mask = inpolygon(X_grid, Y_grid, scaled_x, scaled_y);
            areaImage(grid_in_polygon_mask) = currentAreaAvg;
        end
    end

% --- From here down are reusable UI component builders ---
%% --- UI COMPONENT BUILDERS ---
    function handles = createDisplayModeControls(hParent, panelPosition)
        hPanel = uipanel('Parent', hParent, 'Title', 'Display Mode', 'Units', 'normalized', 'Position', panelPosition);
        uicontrol('Parent', hPanel, 'Style', 'text', 'String', 'Mode:', 'Units', 'normalized', 'Position', [0.03 0.12 0.10 0.76]);
        hModeDropdown = uicontrol('Parent', hPanel, 'Style', 'popupmenu', 'String', {'-'}, 'Units', 'normalized', 'Position', [0.14 0.12 0.28 0.76]);
        hGridLabel = uicontrol('Parent', hPanel, 'Style', 'text', 'String', 'Grid Size:', 'Units', 'normalized', 'Position', [0.44 0.12 0.16 0.76], 'Visible', 'off');
        hGridEdit = uicontrol('Parent', hPanel, 'Style', 'edit', 'String', '30', 'Units', 'normalized', 'Position', [0.61 0.12 0.10 0.76], 'Visible', 'off');
        hInterpolateCheckbox = uicontrol('Parent', hPanel, 'Style', 'checkbox', 'String', 'Interpolate', 'Value', 1, 'Units', 'normalized', 'Position', [0.73 0.12 0.24 0.76], 'Visible', 'off');
        handles.panel = hPanel;
        handles.modeDropdown = hModeDropdown;
        handles.gridSizeLabel = hGridLabel;
        handles.gridSizeEdit = hGridEdit;
        handles.interpolateCheckbox = hInterpolateCheckbox;
    end

    function handles = createMarkerControls(hParent, panelPosition, hScatter)
        hPanel = uipanel('Parent', hParent, 'Title', 'Marker Style', 'Units', 'normalized', 'Position', panelPosition);
        if nargin > 2, set(hPanel, 'UserData', hScatter); end

        uicontrol('Parent', hPanel, 'Style', 'text', 'String', 'Size:', 'Units', 'normalized', 'Position', [0.05 0.1 0.1 0.8]);
        hSizeSlider = uicontrol('Parent', hPanel, 'Style', 'slider', 'Min', 1, 'Max', 100, 'Value', 25, 'Units', 'normalized', 'Position', [0.15 0.1 0.3 0.8]);
        uicontrol('Parent', hPanel, 'Style', 'text', 'String', 'Shape:', 'Units', 'normalized', 'Position', [0.5 0.1 0.1 0.8]);
        shapeStrings = {'o : Circle', 's : Square', 'd : Diamond', '^ : Up', 'v : Down', '. : Dot'};
        shapeValues = {'o', 's', 'd', '^', 'v', '.'};
        hShapeDropdown = uicontrol('Parent', hPanel, 'Style', 'popupmenu', 'String', shapeStrings, 'Units', 'normalized', 'Position', [0.6 0.1 0.35 0.8]);
        
        set(hSizeSlider, 'Callback', @(s,e) updateMarker(s));
        set(hShapeDropdown, 'Callback', @(s,e) updateMarker(s));

        handles.panel = hPanel; handles.sizeSlider = hSizeSlider;
        handles.shapeDropdown = hShapeDropdown; handles.shapeValues = shapeValues;
        
        function updateMarker(src)
            hPanel_local = ancestor(src, 'uipanel');
            hPlot_local = get(hPanel_local, 'UserData');
            if ~isempty(hPlot_local) && isgraphics(hPlot_local) && strcmp(get(hPlot_local,'Type'),'scatter')
                set(hPlot_local, 'SizeData', get(hSizeSlider, 'Value'));
                set(hPlot_local, 'Marker', shapeValues{get(hShapeDropdown, 'Value')});
            end
        end
    end
    
    function handles = createVareaControls(hParent, hAxes, panelPosition, localState)
        handles.hAxes = hAxes;
        hPanel = uipanel('Parent', hParent, 'Title', 'Visual Area Overlays', 'Units', 'normalized', 'Position', panelPosition);
        areaNames = fields(localState.Neural.vareaData);
        numAreas = numel(areaNames);
        plotHandles = struct();
        
        colors = lines(numAreas); % Get a set of distinct colors
        
        hToggleAll = uicontrol('Parent', hPanel, 'Style', 'checkbox', 'String', 'Areas', 'Value', 0, 'Units', 'normalized', 'Position', [0.02 0.1 0.15 0.8], 'Callback', @toggleAllOverlays);
        hFlipY = uicontrol('Parent', hPanel, 'Style', 'checkbox', 'String', 'Flip Y', 'Value', 1, 'Units', 'normalized', 'Position', [0.18 0.1 0.15 0.8], 'Callback', @toggleAllOverlays);
        
        startPos = 0.34;
        for i = 1:numAreas
            uicontrol('Parent', hPanel, 'Style', 'text', 'String', areaNames{i}, 'ForegroundColor', colors(i,:), 'Units', 'normalized', 'Position', [startPos 0.1 0.05 0.8], 'FontWeight', 'bold');
            startPos = startPos + 0.05;
        end
        
        handles.toggleAllCheckbox = hToggleAll;
        handles.flipYCheckbox = hFlipY;
        handles.updateAll = @updateAllOverlays;

        function toggleAllOverlays(~,~)
            f_existing = fields(plotHandles);
            for i=1:numel(f_existing)
                if isfield(plotHandles, f_existing{i}) && all(isgraphics(plotHandles.(f_existing{i})))
                    delete(plotHandles.(f_existing{i}));
                end
            end
            plotHandles = struct();

            if get(hToggleAll, 'Value') == 1
                if strcmp(localState.mode, 'TIFF')
                    T = localState.TIFF;
                    physW_um = T.pixelWidth / T.x_pixels_per_unit;
                    physH_um = T.pixelHeight / T.y_pixels_per_unit;
                    xLim = [0, physW_um];
                    yLim = [0, physH_um];
                else
                    N = localState.Neural;
                    xLim = N.plotXLim;
                    yLim = N.plotYLim;
                end
                
                hold(handles.hAxes, 'on');
                for i = 1:numAreas
                    areaName = areaNames{i};
                    mask = localState.Neural.vareaData.(areaName);
                    boundaries = bwboundaries(mask);
                    h = [];
                    for k = 1:length(boundaries)
                        boundary = boundaries{k};
                        scaled_y = (boundary(:,1) ./ size(mask,1)) .* yLim(2);
                        if get(hFlipY, 'Value') == 1
                            scaled_y = yLim(2) - scaled_y; % Invert Y-axis
                        end
                        scaled_x = (boundary(:,2) ./ size(mask,2)) .* xLim(2);
                        h(k) = plot(handles.hAxes, scaled_x, scaled_y, 'Color', colors(i,:), 'LineWidth', 2);
                    end
                    plotHandles.(areaName) = h;
                end
                hold(handles.hAxes, 'off');
            end
        end
        function updateAllOverlays(), toggleAllOverlays(); end
    end

    function handles = createContrastControls(hParent, hAxes, panelPosition, modeContrasts, displayHandles)
        hCtrlPanel = uipanel('Parent', hParent, 'Title', 'Contrast & Colormap', 'Units', 'normalized', 'Position', panelPosition);
        panelUserData.lastAppliedCmapName = 'gray';
        panelUserData.modeContrasts = modeContrasts;
        panelUserData.customModeContrasts = struct(); % To store user-set limits
        if nargin > 4, panelUserData.displayHandles = displayHandles; end % Store display handles
        set(hCtrlPanel, 'UserData', panelUserData);
        
        rangeOptions = {'0.5x', '1x', '2x', '4x', '8x'};
        uicontrol(hCtrlPanel,'Style','text','String','Black:','Units','normalized','Position',[0.02 0.5 0.08 0.4]);
        hMinSlider = uicontrol(hCtrlPanel,'Style','slider','Units','normalized','Position',[0.10 0.55 0.25 0.3]);
        hMinRangeDropdown = uicontrol(hCtrlPanel,'Style','popupmenu','String',rangeOptions,'Value',2,'Units','normalized','Position',[0.36 0.55 0.1 0.3]);
        uicontrol(hCtrlPanel,'Style','text','String','White:','Units','normalized','Position',[0.52 0.5 0.08 0.4]);
        hMaxSlider = uicontrol(hCtrlPanel,'Style','slider','Units','normalized','Position',[0.60 0.55 0.25 0.3]);
        hMaxRangeDropdown = uicontrol(hCtrlPanel,'Style','popupmenu','String',rangeOptions,'Value',2,'Units','normalized','Position',[0.86 0.55 0.1 0.3]);
        uicontrol(hCtrlPanel,'Style','text','String','Colormap:','Units','normalized','Position',[0.02 0.05 0.18 0.3]);
        cmapStrings = {'gray','hot','parula','jet','cool','winter','summer','spring','autumn','Other...'};
        hColormapDropdown = uicontrol(hCtrlPanel,'Style','popupmenu','String',cmapStrings,'Value',1,'Units','normalized','Position',[0.20 0.1 0.28 0.3]);
        hInvertCmapCheckbox = uicontrol(hCtrlPanel,'Style','checkbox','String','Invert','Units','normalized','Position',[0.50 0.1 0.14 0.3]);
        
        set(hMinRangeDropdown, 'Callback', @(s,e) updateSliderRange(s, hMinSlider));
        set(hMaxRangeDropdown, 'Callback', @(s,e) updateSliderRange(s, hMaxSlider));
        addlistener(hMinSlider, 'Value', 'PostSet', @(s,e) updateContrast_local('min'));
        addlistener(hMaxSlider, 'Value', 'PostSet', @(s,e) updateContrast_local('max'));
        set(hColormapDropdown, 'Callback', @(s,e) applyColormapWrapper(s));
        set(hInvertCmapCheckbox, 'Callback', @(s,e) applyColormapWrapper(s, true));
        
        handles.panel=hCtrlPanel; handles.minSlider=hMinSlider; handles.maxSlider=hMaxSlider;
        handles.minRange=hMinRangeDropdown; handles.maxRange=hMaxRangeDropdown;
        handles.cmapDropdown=hColormapDropdown; handles.invertCmap=hInvertCmapCheckbox;
        handles.setPlayerState=@setPlayerStateWrapper;
        handles.reapplyColormap=@applyColormapWrapper;
        handles.resetSliders=@resetSlidersForMode;

        function resetSlidersForMode(modeName)
            % This is the master function to set slider ranges and values.
            % It prioritizes custom (user-set) limits for the given mode if they exist,
            % otherwise it uses the default percentile-based limits.
            % The 'UserData' is ALWAYS set to the default limits to act as a stable
            % anchor for the range multipliers.

            panelUD = get(hCtrlPanel, 'UserData');
            
            % Determine the default (percentile) and current (custom or default) limits
            defaultLims = [0 1];
            if isfield(panelUD.modeContrasts, modeName), defaultLims = panelUD.modeContrasts.(modeName); end

            limsToUse = defaultLims;
            if isfield(panelUD.customModeContrasts, modeName), limsToUse = panelUD.customModeContrasts.(modeName); end
            
            % Set UserData to the stable default limits
            set(hMinSlider, 'UserData', defaultLims(1));
            set(hMaxSlider, 'UserData', defaultLims(2));
            
            % Update the slider Min/Max based on the range dropdowns and UserData
            updateSliderRange(hMinRangeDropdown, hMinSlider);
            updateSliderRange(hMaxRangeDropdown, hMaxSlider);
            
            % Safely set the slider value, clamping it within the new range
            minVal = limsToUse(1);
            maxVal = limsToUse(2);
            set(hMinSlider, 'Value', max(get(hMinSlider,'Min'), min(get(hMinSlider,'Max'), minVal)) );
            set(hMaxSlider, 'Value', max(get(hMaxSlider,'Min'), min(get(hMaxSlider,'Max'), maxVal)) );
            
            % Apply the final CLim to the axes
            updateContrast_local();
        end
        
        function setPlayerStateWrapper(pState)
            panelUD = get(hCtrlPanel, 'UserData');
            % Store the custom contrasts from the loaded state
            if isfield(pState, 'customContrasts'), panelUD.customModeContrasts = pState.customContrasts; end
            set(hCtrlPanel, 'UserData', panelUD);

            % Restore colormap
            if isfield(pState,'colormapList'),set(hColormapDropdown,'String',pState.colormapList);end
            cmapIndex = find(strcmp(get(hColormapDropdown, 'String'), pState.colormapName));
            if ~isempty(cmapIndex), set(hColormapDropdown, 'Value', cmapIndex); end
            set(hInvertCmapCheckbox, 'Value', pState.colormapInverted);
            applyColormapWrapper(hColormapDropdown); % This updates the colormap and internal state
            
            % Restore range selection
            set(hMinRangeDropdown, 'Value', pState.contrastMinRange);
            set(hMaxRangeDropdown, 'Value', pState.contrastMaxRange);

            % Now that everything is set, call the master reset function.
            % It will use the custom limits we just loaded into customModeContrasts.
            modeOptions = get(displayHandles.modeDropdown, 'String');
            currentMode = modeOptions{get(displayHandles.modeDropdown, 'Value')};
            resetSlidersForMode(currentMode);
        end

        function applyColormapWrapper(src, inversionChanged)
            if nargin < 1, src = hColormapDropdown; inversionChanged = false;
            elseif nargin < 2, inversionChanged = false; end
            hPanel = ancestor(src, 'uipanel');
            panelUserData=get(hPanel, 'UserData');
            cmapStrings=get(hColormapDropdown, 'String');
            selectedCmapName=cmapStrings{get(hColormapDropdown, 'Value')};
            currentCmapToApply=panelUserData.lastAppliedCmapName;
            if strcmp(selectedCmapName, 'Other...') && ~inversionChanged
                userInput=inputdlg('Enter colormap name:','Custom Colormap',[1 50]);
                if ~isempty(userInput) && ~isempty(userInput{1})
                    newCmapName = userInput{1};
                    if ~any(strcmp(cmapStrings, newCmapName))
                        otherIdx = find(strcmp(cmapStrings, 'Other...'));
                        newList = [cmapStrings(1:otherIdx-1); {newCmapName}; cmapStrings(otherIdx:end)];
                        set(hColormapDropdown, 'String', newList, 'Value', otherIdx);
                    end
                    currentCmapToApply = newCmapName;
                else
                    revertIdx = find(strcmp(cmapStrings, panelUserData.lastAppliedCmapName), 1);
                    if ~isempty(revertIdx), set(hColormapDropdown, 'Value', revertIdx); end
                    return;
                end
            elseif ~inversionChanged, currentCmapToApply = selectedCmapName; end
            try
                cmapMatrix = feval(currentCmapToApply);
                if get(hInvertCmapCheckbox,'Value')==1, cmapMatrix=flipud(cmapMatrix); end
                colormap(hAxes, cmapMatrix);
                colorbar(hAxes); % Recreate colorbar whenever colormap changes
                panelUserData.lastAppliedCmapName = currentCmapToApply;
            catch, warndlg(['Colormap "' currentCmapToApply '" not found.'], 'Error');
                revertIdx = find(strcmp(get(hColormapDropdown,'String'),'gray'),1);
                if ~isempty(revertIdx), set(hColormapDropdown, 'Value', revertIdx); end
                panelUserData.lastAppliedCmapName = 'gray'; 
                colormap(hAxes, 'gray');
                colorbar(hAxes);
            end
            set(hPanel, 'UserData', panelUserData);
        end

        function updateSliderRange(dropdown, slider)
            defaultVal = get(slider, 'UserData');
            if isempty(defaultVal), return; end
            rangeVals=[0.5,1,2,4,8]; multiplier=rangeVals(get(dropdown, 'Value'));
            
            if slider == hMinSlider, otherDefault = get(hMaxSlider, 'UserData');
            else, otherDefault = get(hMinSlider, 'UserData'); end
            if isempty(otherDefault), return; end

            baseRange = abs(otherDefault - defaultVal);
            if baseRange == 0, baseRange = 1; end

            newHalfRange = baseRange * multiplier;
            newMin = defaultVal - newHalfRange; newMax = defaultVal + newHalfRange;
            
            currentVal = get(slider, 'Value');
            set(slider, 'Min', newMin, 'Max', newMax);
            
            if currentVal < newMin, set(slider, 'Value', newMin);
            elseif currentVal > newMax, set(slider, 'Value', newMax); end
        end

        function updateContrast_local(sourceSlider)
            if nargin < 1, sourceSlider = ''; end
            minVal = get(hMinSlider, 'Value'); 
            maxVal = get(hMaxSlider, 'Value');
            
            if minVal >= maxVal
                if strcmp(sourceSlider, 'min')
                    minVal = maxVal - 1e-9;
                    set(hMinSlider, 'Value', minVal);
                elseif strcmp(sourceSlider, 'max')
                    maxVal = minVal + 1e-9;
                    set(hMaxSlider, 'Value', maxVal);
                end
            end
            
            set(hAxes, 'CLim', [minVal, maxVal]);
            
            % If this was a manual change, store it as a custom limit
            panelUD = get(hCtrlPanel, 'UserData');
            if isfield(panelUD, 'displayHandles')
                modeOptions = get(panelUD.displayHandles.modeDropdown, 'String');
                currentMode = modeOptions{get(panelUD.displayHandles.modeDropdown, 'Value')};
                panelUD.customModeContrasts.(currentMode) = [minVal, maxVal];
                set(hCtrlPanel, 'UserData', panelUD);
            end
        end
    end

    function handles = createMergeContrastControls(hParent, hAxes, panelPosition, avgDataRGB, displayHandles)
        % avgDataRGB is (H,W,3): (:,:,1)=Ch1, (:,:,2)=Ch2, (:,:,3)=0. Independent contrast for Ch1 and Ch2 + color assignment.
        if nargin < 5, displayHandles = []; end
        hCtrlPanel = uipanel('Parent', hParent, 'Title', 'Merge contrast (Ch1 & Ch2)', 'Units', 'normalized', 'Position', panelPosition);
        ch1 = double(avgDataRGB(:,:,1));
        ch2 = double(avgDataRGB(:,:,2));
        p1 = prctile(ch1(:), [2 98]); if p1(1) >= p1(2), p1 = [0 1]; end
        p2 = prctile(ch2(:), [2 98]); if p2(1) >= p2(2), p2 = [0 1]; end
        rangeOptions = {'0.5x', '1x', '2x', '4x', '8x'};
        % Ch1 row
        uicontrol(hCtrlPanel,'Style','text','String','Ch1 Black:','Units','normalized','Position',[0.01 0.72 0.10 0.22]);
        hCh1Min = uicontrol(hCtrlPanel,'Style','slider','Units','normalized','Position',[0.12 0.75 0.22 0.2], 'UserData', p1(1), 'Min', p1(1)-0.1, 'Max', p1(2)+0.1, 'Value', p1(1));
        hCh1MinRange = uicontrol(hCtrlPanel,'Style','popupmenu','String',rangeOptions,'Value',2,'Units','normalized','Position',[0.35 0.75 0.08 0.2]);
        uicontrol(hCtrlPanel,'Style','text','String','Ch1 White:','Units','normalized','Position',[0.44 0.72 0.10 0.22]);
        hCh1Max = uicontrol(hCtrlPanel,'Style','slider','Units','normalized','Position',[0.55 0.75 0.22 0.2], 'UserData', p1(2), 'Min', p1(1)-0.1, 'Max', p1(2)+0.1, 'Value', p1(2));
        hCh1MaxRange = uicontrol(hCtrlPanel,'Style','popupmenu','String',rangeOptions,'Value',2,'Units','normalized','Position',[0.78 0.75 0.08 0.2]);
        % Ch2 row
        uicontrol(hCtrlPanel,'Style','text','String','Ch2 Black:','Units','normalized','Position',[0.01 0.42 0.10 0.22]);
        hCh2Min = uicontrol(hCtrlPanel,'Style','slider','Units','normalized','Position',[0.12 0.45 0.22 0.2], 'UserData', p2(1), 'Min', p2(1)-0.1, 'Max', p2(2)+0.1, 'Value', p2(1));
        hCh2MinRange = uicontrol(hCtrlPanel,'Style','popupmenu','String',rangeOptions,'Value',2,'Units','normalized','Position',[0.35 0.45 0.08 0.2]);
        uicontrol(hCtrlPanel,'Style','text','String','Ch2 White:','Units','normalized','Position',[0.44 0.42 0.10 0.22]);
        hCh2Max = uicontrol(hCtrlPanel,'Style','slider','Units','normalized','Position',[0.55 0.45 0.22 0.2], 'UserData', p2(2), 'Min', p2(1)-0.1, 'Max', p2(2)+0.1, 'Value', p2(2));
        hCh2MaxRange = uicontrol(hCtrlPanel,'Style','popupmenu','String',rangeOptions,'Value',2,'Units','normalized','Position',[0.78 0.45 0.08 0.2]);
        % Color assignment: Ch1?R Ch2?G, Ch1?G Ch2?R, Ch1?R Ch2?B, Ch1?B Ch2?R, Ch1?G Ch2?B, Ch1?B Ch2?G
        colorAssignStr = {'Ch1?R Ch2?G','Ch1?G Ch2?R','Ch1?R Ch2?B','Ch1?B Ch2?R','Ch1?G Ch2?B','Ch1?B Ch2?G'};
        uicontrol(hCtrlPanel,'Style','text','String','Color:','Units','normalized','Position',[0.01 0.08 0.12 0.22]);
        hColorAssign = uicontrol(hCtrlPanel,'Style','popupmenu','String',colorAssignStr,'Value',1,'Units','normalized','Position',[0.14 0.12 0.35 0.2]);
        panelUD = struct('ch1', ch1, 'ch2', ch2, 'hAxes', hAxes, 'displayHandles', displayHandles);
        set(hCtrlPanel, 'UserData', panelUD);
        rangeVals = [0.5, 1, 2, 4, 8];
        function updateCh1Range(~,~)
            lo = get(hCh1Min,'UserData'); hi = get(hCh1Max,'UserData');
            baseRange = abs(hi - lo); if baseRange <= 0, baseRange = 1; end
            multMin = rangeVals(get(hCh1MinRange,'Value'));
            multMax = rangeVals(get(hCh1MaxRange,'Value'));
            halfMin = baseRange * multMin; halfMax = baseRange * multMax;
            newMinLo = lo - halfMin; newMinHi = lo + halfMin;
            newMaxLo = hi - halfMax; newMaxHi = hi + halfMax;
            set(hCh1Min,'Min',newMinLo,'Max',newMinHi);
            set(hCh1Max,'Min',newMaxLo,'Max',newMaxHi);
            cv = get(hCh1Min,'Value'); set(hCh1Min,'Value',max(newMinLo,min(newMinHi,cv)));
            cv = get(hCh1Max,'Value'); set(hCh1Max,'Value',max(newMaxLo,min(newMaxHi,cv)));
            applyMergeImage();
        end
        function updateCh2Range(~,~)
            lo = get(hCh2Min,'UserData'); hi = get(hCh2Max,'UserData');
            baseRange = abs(hi - lo); if baseRange <= 0, baseRange = 1; end
            multMin = rangeVals(get(hCh2MinRange,'Value'));
            multMax = rangeVals(get(hCh2MaxRange,'Value'));
            halfMin = baseRange * multMin; halfMax = baseRange * multMax;
            newMinLo = lo - halfMin; newMinHi = lo + halfMin;
            newMaxLo = hi - halfMax; newMaxHi = hi + halfMax;
            set(hCh2Min,'Min',newMinLo,'Max',newMinHi);
            set(hCh2Max,'Min',newMaxLo,'Max',newMaxHi);
            cv = get(hCh2Min,'Value'); set(hCh2Min,'Value',max(newMinLo,min(newMinHi,cv)));
            cv = get(hCh2Max,'Value'); set(hCh2Max,'Value',max(newMaxLo,min(newMaxHi,cv)));
            applyMergeImage();
        end
        set(hCh1MinRange,'Callback',@(s,e)updateCh1Range()); set(hCh1MaxRange,'Callback',@(s,e)updateCh1Range());
        set(hCh2MinRange,'Callback',@(s,e)updateCh2Range()); set(hCh2MaxRange,'Callback',@(s,e)updateCh2Range());
        function applyMergeImage(~,~)
            ud = get(hCtrlPanel,'UserData');
            if ~isempty(ud.displayHandles)
                modeOpts = get(ud.displayHandles.modeDropdown,'String');
                curMode = modeOpts{get(ud.displayHandles.modeDropdown,'Value')};
                if ~strcmp(curMode, 'Image'), return; end
            end
            m1 = get(hCh1Min,'Value'); M1 = get(hCh1Max,'Value'); span1 = M1 - m1 + eps;
            m2 = get(hCh2Min,'Value'); M2 = get(hCh2Max,'Value'); span2 = M2 - m2 + eps;
            s1 = min(1, max(0, (ud.ch1 - m1) / span1));
            s2 = min(1, max(0, (ud.ch2 - m2) / span2));
            idx = get(hColorAssign,'Value');
            rgb = zeros(size(ud.ch1,1), size(ud.ch1,2), 3);
            switch idx
                case 1, rgb(:,:,1)=s1; rgb(:,:,2)=s2; rgb(:,:,3)=0;
                case 2, rgb(:,:,1)=s2; rgb(:,:,2)=s1; rgb(:,:,3)=0;
                case 3, rgb(:,:,1)=s1; rgb(:,:,2)=0; rgb(:,:,3)=s2;
                case 4, rgb(:,:,1)=s2; rgb(:,:,2)=0; rgb(:,:,3)=s1;
                case 5, rgb(:,:,1)=0; rgb(:,:,2)=s1; rgb(:,:,3)=s2;
                case 6, rgb(:,:,1)=0; rgb(:,:,2)=s2; rgb(:,:,3)=s1;
                otherwise, rgb(:,:,1)=s1; rgb(:,:,2)=s2; rgb(:,:,3)=0;
            end
            himg = findobj(ud.hAxes, 'Type', 'image');
            if ~isempty(himg), set(himg(1), 'CData', rgb); end
        end
        addlistener(hCh1Min, 'Value', 'PostSet', @(s,e)applyMergeImage());
        addlistener(hCh1Max, 'Value', 'PostSet', @(s,e)applyMergeImage());
        addlistener(hCh2Min, 'Value', 'PostSet', @(s,e)applyMergeImage());
        addlistener(hCh2Max, 'Value', 'PostSet', @(s,e)applyMergeImage());
        set(hColorAssign, 'Callback', @(s,e)applyMergeImage());
        updateCh1Range(); updateCh2Range();
        handles.panel = hCtrlPanel;
        handles.applyMergeImage = @applyMergeImage;
        handles.resetSliders = @(modeName) applyMergeImage();
        handles.reapplyColormap = @() [];
        handles.setPlayerState = @(pState) [];
    end
    
    % Helper function: Multi-line editor for text fields
    function openMultiLineEditor(hTextField, fieldLabel)
        currentStr = get(hTextField, 'String');
        
        % Create dialog
        dlg = dialog('Name', ['Edit ' fieldLabel], 'Position', [300 300 500 400]);
        
        % Add instruction text
        uicontrol('Parent', dlg, 'Style', 'text', ...
            'String', ['Enter MATLAB expression(s) for ' fieldLabel ':'], ...
            'Position', [10 370 480 20], 'HorizontalAlignment', 'left');
        
        % Add multi-line text area
        hTextArea = uicontrol('Parent', dlg, 'Style', 'edit', ...
            'String', currentStr, ...
            'Position', [10 50 480 310], ...
            'Max', 2, 'HorizontalAlignment', 'left');  % Max=2 enables multi-line
        
        % Add OK button
        uicontrol('Parent', dlg, 'Style', 'pushbutton', ...
            'String', 'OK', 'Position', [310 10 80 30], ...
            'Callback', @(~,~) okCallback());
        
        % Add Cancel button
        uicontrol('Parent', dlg, 'Style', 'pushbutton', ...
            'String', 'Cancel', 'Position', [400 10 80 30], ...
            'Callback', @(~,~) delete(dlg));
        
        function okCallback()
            % Get text from text area and update original field
            newStr = get(hTextArea, 'String');
            % Convert cell array to single string with newlines if needed
            if iscell(newStr)
                newStr = strjoin(newStr, newline);
            end
            set(hTextField, 'String', newStr);
            delete(dlg);
        end
    end
end

