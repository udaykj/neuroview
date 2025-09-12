classdef StateManagerV2 < handle
    % StateManagerV2 - Manages four independent state slots for NeuroView
    % 
    % This class maintains complete isolation between:
    % 1. Current Session (TIFF)
    % 2. Current Session (Neural) 
    % 3. Loaded State (TIFF)
    % 4. Loaded State (Neural)
    
    properties (Access = private)
        states      % Container for all 4 state slots
        activeSlot  % Currently active state slot identifier
    end
    
    properties (Constant)
        % State slot identifiers
        CURRENT_TIFF = 'current_tiff'
        CURRENT_NEURAL = 'current_neural'
        LOADED_TIFF = 'loaded_tiff'
        LOADED_NEURAL = 'loaded_neural'
    end
    
    methods
        function obj = StateManagerV2()
            % Initialize all four state slots
            obj.states = struct();
            obj.states.(obj.CURRENT_TIFF) = obj.createEmptyState('TIFF');
            obj.states.(obj.CURRENT_NEURAL) = obj.createEmptyState('Neural');
            obj.states.(obj.LOADED_TIFF) = [];  % Empty until loaded
            obj.states.(obj.LOADED_NEURAL) = [];  % Empty until loaded
            obj.activeSlot = obj.CURRENT_TIFF;  % Start with TIFF mode
        end
        
        function state = getActiveState(obj)
            % Get the currently active state (deep copy)
            state = obj.deepCopy(obj.states.(obj.activeSlot));
        end
        
        function setActiveSlot(obj, mode, context)
            % Determine which slot should be active based on mode and context
            if strcmp(context, 'current')
                if strcmp(mode, 'TIFF')
                    obj.activeSlot = obj.CURRENT_TIFF;
                else
                    obj.activeSlot = obj.CURRENT_NEURAL;
                end
            else % 'loaded' context
                if strcmp(mode, 'TIFF')
                    obj.activeSlot = obj.LOADED_TIFF;
                else
                    obj.activeSlot = obj.LOADED_NEURAL;
                end
            end
        end
        
        function success = loadStateIntoSlot(obj, stateData, currentMode)
            % Load a state into the appropriate loaded slot based on current mode
            success = false;
            
            % Determine state mode from loaded data
            loadedMode = obj.getStateMode(stateData);
            
            % Mode must match current mode
            if ~strcmp(loadedMode, currentMode)
                errordlg(sprintf('Cannot load %s state while in %s mode', loadedMode, currentMode), 'Mode Mismatch');
                return;
            end
            
            % Load into appropriate slot
            if strcmp(loadedMode, 'TIFF')
                obj.states.(obj.LOADED_TIFF) = stateData;
            else
                obj.states.(obj.LOADED_NEURAL) = stateData;
            end
            
            success = true;
        end
        
        function hasLoaded = hasLoadedState(obj, mode)
            % Check if a loaded state exists for the given mode
            if strcmp(mode, 'TIFF')
                hasLoaded = ~isempty(obj.states.(obj.LOADED_TIFF));
            else
                hasLoaded = ~isempty(obj.states.(obj.LOADED_NEURAL));
            end
        end
        
        function updateActiveState(obj, fieldPath, value)
            % Update a field in the active state
            % fieldPath can be like 'TIFF.fullFilePath' or 'ui.rollingAvg'
            
            % Get the active state
            state = obj.states.(obj.activeSlot);
            
            % Parse the field path and update
            parts = strsplit(fieldPath, '.');
            
            % Navigate to the parent of the field to update
            parent = state;
            for i = 1:length(parts)-1
                if ~isfield(parent, parts{i})
                    parent.(parts{i}) = struct();
                end
                parent = parent.(parts{i});
            end
            
            % Set the value
            parent.(parts{end}) = value;
            
            % Update cache invalidation if needed
            if contains(fieldPath, {'TIFF.', 'Neural.', 'ui.'})
                state.sessionCache = struct('data', [], 'fingerprint', []);
            end
            
            % Store back
            obj.states.(obj.activeSlot) = state;
        end
        
        function clearCache(obj)
            % Clear cache for active state
            state = obj.states.(obj.activeSlot);
            state.sessionCache = struct('data', [], 'fingerprint', []);
            obj.states.(obj.activeSlot) = state;
        end
        
        function mode = getCurrentMode(obj)
            % Get the mode of the currently active state
            state = obj.states.(obj.activeSlot);
            mode = state.currentMode;
        end
        
        function isReadOnly = isLoadedStateReadOnly(obj)
            % Check if the current loaded state is read-only
            state = obj.states.(obj.activeSlot);
            if isfield(state, 'reloadRaw')
                isReadOnly = ~state.reloadRaw;
            else
                isReadOnly = true;
            end
        end
        
    end
    
    methods (Access = private)
        function state = createEmptyState(obj, mode)
            % Create a fresh state structure for the given mode
            state = struct();
            state.currentMode = mode;
            
            % Initialize TIFF data
            state.TIFF = struct(...
                'fullFilePath', '', ...
                'selectedFolderPath', '', ...
                'fileBaseName', '', ...
                'isFolderMode', false, ...
                'roiData', [], ...
                'metadataString', '', ...
                'dataAspectRatio', [1 1 1], ...
                'x_pixels_per_unit', 1, ...
                'y_pixels_per_unit', 1, ...
                'parsedNumPlanes', 0, ...
                'parsedNumChannels', 0, ...
                'nativeFrameRate', 30, ...
                'pixelWidth', 512, ...
                'pixelHeight', 512, ...
                'vareaData', [], ...
                'vareaFilePath', '');
            
            % Initialize Neural data
            state.Neural = struct(...
                'dataFilePath', '', ...
                'coordsFilePath', '', ...
                'tiffFolderPath', '', ...
                'vareaFilePath', '', ...
                'psthsData', [], ...
                'psthsnpData', [], ...
                'cellCoords', [], ...
                'vareaData', [], ...
                'numNeurons', 0, ...
                'numTimepoints', 0, ...
                'numTrials', 0, ...
                'metadataString', '', ...
                'nativeFrameRate', 30, ...
                'plotXLim', [0 1], ...
                'plotYLim', [0 1], ...
                'pixelWidth', 512, ...
                'pixelHeight', 512, ...
                'x_pixels_per_um', 1, ...
                'y_pixels_per_um', 1);
            
            % Initialize UI state
            state.ui = struct(...
                'rollingAvg', '1', ...
                'trials', ':', ...
                'displayMode', 1, ...
                'initialFrames', '10', ...
                'refTrials', '[]', ...
                'divideByF0', 1, ...
                'frameByFrame', 0, ...
                'plane', 1, ...
                'channel', 1, ...
                'smoothingSigma', '0', ...
                'neuropilCoeff', '0.7', ...
                'detrend', 0, ...
                'detrendWindow', '1', ...
                'forcePositive', 1);
            
            % Cache structures
            state.sessionCache = struct('data', [], 'fingerprint', []);
            state.frameRate = 30;
            
            return;
        end
        
        function mode = getStateMode(obj, stateData)
            % Determine the mode of a state
            if isfield(stateData, 'mode')
                mode = stateData.mode;
            elseif isfield(stateData, 'currentMode')
                mode = stateData.currentMode;
            else
                % Try to infer from data presence
                if isfield(stateData, 'TIFF') && ~isempty(stateData.TIFF.fullFilePath)
                    mode = 'TIFF';
                elseif isfield(stateData, 'Neural') && ~isempty(stateData.Neural.dataFilePath)
                    mode = 'Neural';
                else
                    mode = 'TIFF'; % Default
                end
            end
        end
        
        function copy = deepCopy(obj, original)
            % Create a deep copy of a structure
            if isempty(original)
                copy = [];
                return;
            end
            
            % Use struct2cell and cell2struct for deep copy
            try
                copy = eval(sprintf('%s', mat2str(original)));
            catch
                % Fallback for complex structures
                copy = original; % This is shallow, but preserves functionality
            end
        end
    end
endfunction neuroView_v2()
% NEUROVIEW_V2 Creates a unified GUI with improved 4-state architecture
%
% Version 2 implements a clean 4-state system:
% - Current Session (TIFF)
% - Current Session (Neural)
% - Loaded State (TIFF)
% - Loaded State (Neural)

% --- Initialize State Manager ---
stateManager = StateManagerV2();

% --- GUI Setup ---
hFig = figure('Name', 'NeuroView v2 - Unified Viewer', ...
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
    'Position', [315 10 110 20], 'Value', 0, 'BackgroundColor', [0.94 0.94 0.94']);


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
hSmoothingLabel = uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', 'Smoothing (µm):', 'Position', [280 120 80 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94]);
hSmoothingWindowInput = uicontrol('Parent', hProcessingPanel, 'Style', 'edit', 'String', '0', 'Position', [370 120 40 20]);
% Line 3
uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', 'Trials:', 'Position', [20 90 50 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94]);
hTrialInput = uicontrol('Parent', hProcessingPanel, 'Style', 'edit', 'String', ':', 'Position', [80 90 330 20]);
% Line 4
uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', 'Display Mode:', 'Position', [0 60 70 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94]);
hDisplayMode = uicontrol('Parent', hProcessingPanel, 'Style', 'popupmenu', 'String', {'Raw/Corrected', 'dF/F (Initial Frames)', 'dF/F (Median)', 'dF/F (Reference Trials)'}, ...
    'Position', [80 60 150 20], 'Callback', @updateDisplayMode);
hDivideByF0Checkbox = uicontrol('Parent', hProcessingPanel, 'Style', 'checkbox', 'String', 'Divide by F0', 'Position', [240 60 100 20], 'Value', 1, 'BackgroundColor', [0.94 0.94 0.94], 'Visible', 'off');
% Line 5
hInitialFramesLabel = uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', 'Frames:', 'Position', [20 30 50 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94], 'Visible', 'off');
hInitialFramesInput = uicontrol('Parent', hProcessingPanel, 'Style', 'edit', 'String', '10', 'Position', [80 30 40 20], 'Visible', 'off');
hRefTrialsLabel = uicontrol('Parent', hProcessingPanel, 'Style', 'text', 'String', 'Ref Trials:', 'Position', [5 30 70 20], 'HorizontalAlignment', 'right', 'BackgroundColor', [0.94 0.94 0.94], 'Visible', 'off');
hRefTrialsInput = uicontrol('Parent', hProcessingPanel, 'Style', 'edit', 'String', '[]', 'Position', [80 30 330 20], 'Visible', 'off');
hFrameByFrameCheckbox = uicontrol('Parent', hProcessingPanel, 'Style', 'checkbox', 'String', 'Frame-wise Subtraction', 'Position', [80 5 180 20], 'Value', 0, 'BackgroundColor', [0.94 0.94 0.94], 'Visible', 'off');


% --- Action Buttons ---
uicontrol('Style', 'pushbutton', 'String', 'Show Info', 'Position', [40 40 120 30], 'FontSize', 10, 'Callback', @showInfoCallback);
uicontrol('Style', 'pushbutton', 'String', 'Plot Average', 'Position', [165 40 120 30], 'FontSize', 10, 'Callback', @plotAvgCallback);
uicontrol('Style', 'pushbutton', 'String', 'Play Movie', 'Position', [290 40 120 30], 'FontSize', 10, 'Callback', @playMovieCallback);

% --- Initialize display ---
updateDisplayMode();
refreshUIFromState();

%% --- TOP LEVEL CALLBACKS WITH NEW STATE MANAGEMENT ---

    function modeSwitchCallback(src, ~)
        % Get current context and mode
        isCurrentContext = get(hContextSession, 'Value') == 1;
        currentMode = stateManager.getCurrentMode();
        
        % Get new mode from dropdown
        newModeIndex = get(src, 'Value');
        newMode = ifelse(newModeIndex == 1, 'TIFF', 'Neural');
        
        % If in current context, we can switch modes freely
        if isCurrentContext
            % Update state manager to point to new current session slot
            stateManager.setActiveSlot(newMode, 'current');
            
            % Update mode in the state
            stateManager.updateActiveState('currentMode', newMode);
            
            % Refresh UI from the newly active state
            refreshUIFromState();
        else
            % In loaded context, mode switching is not allowed
            % Revert dropdown to match loaded state mode
            set(src, 'Value', ifelse(strcmp(currentMode, 'TIFF'), 1, 2));
            return;
        end
    end

    function switchOperatingContextCallback(~,~)
        isLoadedContext = get(hContextLoaded, 'Value') == 1;
        currentMode = getCurrentModeFromDropdown();
        
        if isLoadedContext
            % Switching TO loaded context
            if ~stateManager.hasLoadedState(currentMode)
                % No loaded state for this mode
                set(hContextSession, 'Value', 1);
                set(hContextLoaded, 'Value', 0);
                errordlg(sprintf('No loaded %s state available', currentMode), 'No Loaded State');
                return;
            end
            
            % Switch to loaded state slot
            stateManager.setActiveSlot(currentMode, 'loaded');
            
            % Update UI controls based on loaded state
            set(hModeSelector, 'Enable', 'off');
            
            % Check if read-only
            if stateManager.isLoadedStateReadOnly()
                setProcessingPanelEnabled(false);
                appendToStatus('Switched to Loaded State (read-only).');
            else
                setProcessingPanelEnabled(true);
                appendToStatus('Switched to Loaded State (raw data available).');
            end
        else
            % Switching BACK to current session
            stateManager.setActiveSlot(currentMode, 'current');
            
            % Re-enable controls
            set(hModeSelector, 'Enable', 'on');
            setProcessingPanelEnabled(true);
            appendToStatus('Switched back to Current Session.');
        end
        
        % Refresh UI from newly active state
        refreshUIFromState();
    end

    function loadStateCallback(~,~)
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select a saved state file');
        if isequal(fileName, 0), return; end
        
        loadPath = fullfile(pathName, fileName);
        currentMode = getCurrentModeFromDropdown();
        
        try
            set(hText, 'String', 'Loading state...'); drawnow;
            loadedData = load(loadPath);
            if ~isfield(loadedData, 'state'), error('Invalid state file.'); end
            
            state = loadedData.state;
            
            % Get reload raw checkbox value
            isTiffMode = strcmp(currentMode, 'TIFF');
            if isTiffMode
                reloadRaw = get(hReloadDataCheckbox_Tiff, 'Value');
            else
                reloadRaw = get(hReloadDataCheckbox_Neural, 'Value');
            end
            
            state.reloadRaw = reloadRaw;
            
            % Load state into appropriate slot
            if stateManager.loadStateIntoSlot(state, currentMode)
                % Enable loaded context radio button
                set(hContextLoaded, 'Enable', 'on', 'Value', 1);
                set(hContextSession, 'Value', 0);
                
                % Trigger context switch
                switchOperatingContextCallback();
            end
            
        catch ME
            set(hText, 'String', sprintf('Error loading state file:\n%s', ME.message));
        end
    end

    function showInfoCallback(~, ~)
        state = stateManager.getActiveState();
        
        if strcmp(state.currentMode, 'TIFF')
            if ~isempty(state.TIFF.metadataString)
                set(hText, 'String', state.TIFF.metadataString);
            end
        else
            if ~isempty(state.Neural.metadataString)
                set(hText, 'String', state.Neural.metadataString);
            end
        end
    end

    function plotAvgCallback(~, ~)
        avgData = []; localState = []; playerStateToApply = [];
        
        isInLoadedContext = get(hContextLoaded, 'Value') == 1;
        state = stateManager.getActiveState();

        if isInLoadedContext && isfield(state, 'movieData') && ~isempty(state.movieData)
            set(hText, 'String', 'Averaging pre-loaded movie data...'); drawnow;
            
            localState = state;
            playerStateToApply = ifisfield(localState, 'playerState');
            isTiffMode = strcmp(localState.currentMode, 'TIFF');
            timeDim = ifelse(isTiffMode, 3, 2);
            avgData = mean(localState.movieData, timeDim);
        else
            [processedData, localState, success, errMsg] = getOrProcessData();
            if ~success, set(hText, 'String', errMsg); return; end

            appendToStatus('Averaging data...');
            if strcmp(localState.currentMode, 'TIFF')
                avgData = mean(processedData, 3);
            else
                avgData = mean(processedData, 2);
            end
        end

        try
            localState.avgData = avgData;
            
            figName = ifelse(strcmp(localState.currentMode, 'TIFF'), 'Average Stitched Image', 'Average Neuronal Activity');
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
            
            modeContrasts = struct();
            p_base = prctile(localState.avgData(:), [2 98]);
            if any(isnan(p_base)) || p_base(1) >= p_base(2), p_base = [0 1]; end
            if strcmp(localState.currentMode, 'TIFF'), modeContrasts.Image = p_base; else, modeContrasts.Cells = p_base; end
            
            if ~isempty(localState.Neural.vareaData)
                [areaImg, ~] = createAreaAverageImage(localState.avgData, localState, true);
                p_area = prctile(areaImg(:), [2 98]); 
                if any(isnan(p_area)) || p_area(1) >= p_area(2), p_area = [0 1]; end
                modeContrasts.Areas = p_area;
            end
            
            gridSize = 30;
            if strcmp(localState.currentMode, 'TIFF')
                [gridData, ~, ~] = binData_TIFF(localState.avgData, localState.TIFF, gridSize);
            else
                [gridData, ~, ~] = binData_Neural(localState.Neural, localState.avgData, gridSize, localState.physicalCoords, false);
            end
            p_grid = prctile(gridData(:), [2 98]); 
            if any(isnan(p_grid)) || p_grid(1) >= p_grid(2), p_grid = [0 1]; end
            modeContrasts.Grid = p_grid;

            contrastHandles = createContrastControls(hPlotFig, hAxes, [0.1 0.01 0.8 0.09], modeContrasts, displayHandles);
            hPlotObject = []; 
            
            tiffModes = {'Image', 'Grid'}; neuralModes = {'Cells', 'Grid'};
            if ~isempty(localState.Neural.vareaData), tiffModes{end+1} = 'Areas'; neuralModes{end+1} = 'Areas'; end
            if strcmp(localState.currentMode, 'TIFF'), set(displayHandles.modeDropdown, 'String', tiffModes);
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
            if ~isempty(vareaHandles), vareaHandles.updateAll(); end
            
            if ~isempty(playerStateToApply)
                contrastHandles.setPlayerState(playerStateToApply);
            end

            appendToStatus('Successfully plotted average activity.');
        catch ME
            appendToStatus(sprintf('Error plotting average:\n%s\nLine: %d', ME.message, ME.stack(1).line));
        end

        function displayModeChanged_static()
            modeIdx = get(displayHandles.modeDropdown, 'Value');
            modeOptions = get(displayHandles.modeDropdown, 'String');
            selectedMode = modeOptions{modeIdx};
            isTiffMode = strcmp(localState.currentMode, 'TIFF');
            
            set(markerHandles.panel, 'Visible', ifelse(strcmp(selectedMode, 'Cells'), 'on', 'off'));
            set(displayHandles.gridSizeEdit, 'Visible', ifelse(strcmp(selectedMode, 'Grid'), 'on', 'off'));
            set(displayHandles.gridSizeLabel, 'Visible', ifelse(strcmp(selectedMode, 'Grid'), 'on', 'off'));
            set(displayHandles.interpolateCheckbox, 'Visible', ifelse(strcmp(selectedMode, 'Grid'), 'on', 'off'));
            
            if isgraphics(hPlotObject), delete(hPlotObject); end

            if isTiffMode
                T = localState.TIFF;
                physW = T.pixelWidth / T.x_pixels_per_unit;
                physH = T.pixelHeight / T.y_pixels_per_unit;
                if strcmp(selectedMode, 'Image')
                    hPlotObject = imagesc(hAxes, [0 physW], [0 physH], localState.avgData);
                elseif strcmp(selectedMode, 'Grid')
                    gridSize = str2double(get(displayHandles.gridSizeEdit, 'String'));
                    if isnan(gridSize) || gridSize < 1, gridSize = 30; end
                    if get(displayHandles.interpolateCheckbox, 'Value') == 1
                        gridData = imresize(localState.avgData, [gridSize gridSize], 'bicubic');
                    else
                        [gridData, ~, ~] = binData_TIFF(localState.avgData, localState.TIFF, gridSize);
                    end
                    grid_x = linspace(0, physW, gridSize); grid_y = linspace(0, physH, gridSize);
                    hPlotObject = imagesc(hAxes, 'XData', grid_x, 'YData', grid_y, 'CData', gridData);
                elseif strcmp(selectedMode, 'Areas')
                    if isempty(vareaHandles), error('Load visual areas first.'); end
                    [areaImg, ~] = createAreaAverageImage(localState.avgData, localState, get(vareaHandles.flipYCheckbox, 'Value'));
                    hPlotObject = imagesc(hAxes, [0 physW], [0 physH], areaImg);
                end
            else % Neural Mode
                if strcmp(selectedMode, 'Cells')
                    hPlotObject = scatter(hAxes, localState.physicalCoords(:,1), localState.physicalCoords(:,2), ...
                        get(markerHandles.sizeSlider, 'Value'), localState.avgData, 'filled', ...
                        'Marker', markerHandles.shapeValues{get(markerHandles.shapeDropdown, 'Value')});
                    set(markerHandles.panel, 'UserData', hPlotObject);
                elseif strcmp(selectedMode, 'Grid')
                    gridSize = str2double(get(displayHandles.gridSizeEdit, 'String'));
                    if isnan(gridSize) || gridSize < 1, gridSize = 30; end
                    [binnedFrame, x_centers, y_centers] = binData_Neural(localState.Neural, localState.avgData, ...
                        gridSize, localState.physicalCoords, get(displayHandles.interpolateCheckbox, 'Value'));
                    hPlotObject = imagesc(hAxes, 'XData', x_centers, 'YData', y_centers, 'CData', binnedFrame);
                elseif strcmp(selectedMode, 'Areas')
                    if isempty(vareaHandles), error('Load visual areas first.'); end
                    [areaImg, ~] = createAreaAverageImage(localState.avgData, localState, get(vareaHandles.flipYCheckbox, 'Value'));
                    N = localState.Neural;
                    hPlotObject = imagesc(hAxes, 'XData', N.plotXLim, 'YData', N.plotYLim, 'CData', areaImg);
                end
            end
            
            setupPlotAxes(hAxes, localState.currentMode, localState.TIFF, localState.Neural);
            if isempty(playerStateToApply)
                contrastHandles.resetSliders(selectedMode);
            end
            if isTiffMode, set(hAxes, 'YDir', 'normal'); end
            if ~isempty(vareaHandles), vareaHandles.updateAll(); end
            contrastHandles.reapplyColormap();
        end
    end

    function playMovieCallback(~, ~)
        precomputedMovie = [];
        playerStateToApply = [];
        generationState = [];
        
        isInLoadedContext = get(hContextLoaded, 'Value') == 1;
        state = stateManager.getActiveState();

        if isInLoadedContext && isfield(state, 'movieData') && ~isempty(state.movieData)
            generationState = state;
            precomputedMovie = generationState.movieData;
            playerStateToApply = ifisfield(generationState, 'playerState');
            set(hText, 'String', 'Playing pre-computed movie from loaded state...'); drawnow;
        else
            [processedData, generationState, success, errMsg] = getOrProcessData();
            if ~success, set(hText, 'String', errMsg); return; end
            
            rollingAvg = round(str2double(get(hRollingAvgInput, 'String')));
            if isnan(rollingAvg) || rollingAvg < 1, set(hText, 'String', 'Invalid Rolling Average.'); return; end
            
            appendToStatus(sprintf('Applying rolling average of %d...', rollingAvg));
            
            if strcmp(generationState.currentMode, 'TIFF')
                precomputedMovie = movmean(processedData, rollingAvg, 3, 'Endpoints', 'shrink');
            else % Neural
                precomputedMovie = movmean(processedData, rollingAvg, 2, 'Endpoints', 'shrink');
            end
        end

        launchUnifiedMoviePlayer(precomputedMovie, playerStateToApply, generationState);
    end%% --- DATA CACHING & PROCESSING (with new state management) ---
    function [processedData, generationState, success, errMsg] = getOrProcessData()
        processedData = []; 
        generationState = [];
        success = false; 
        errMsg = '';

        % Get current state from state manager
        generationState = captureFullState();

        % Check against cache
        state = stateManager.getActiveState();
        if ~isempty(state.sessionCache.fingerprint) && ...
           isequaln(generationState, state.sessionCache.fingerprint)
            
            % Cache Hit
            appendToStatus('Using cached data...');
            processedData = state.sessionCache.data;
            success = true;
            
        else
            % Cache Miss
            currentMode = state.currentMode;
            if (strcmp(currentMode, 'TIFF') && isempty(state.TIFF.fullFilePath) && isempty(state.TIFF.selectedFolderPath)) || ...
               (strcmp(currentMode, 'Neural') && (isempty(state.Neural.psthsData) || isempty(state.Neural.cellCoords) || isempty(state.Neural.tiffFolderPath)))
                errMsg = 'Please load all required data for the current mode first.';
                if strcmp(currentMode, 'Neural')
                    errMsg = [errMsg sprintf('\n(Data, Coords, AND original TIFF folder are required.)')];
                end
                success = false;
                return;
            end

            set(hText, 'String', 'Processing new data...'); drawnow;
            [newData, procSuccess, procErrMsg] = getProcessedData();
            
            if procSuccess
                % Update cache in state manager
                stateManager.updateActiveState('sessionCache.data', newData);
                stateManager.updateActiveState('sessionCache.fingerprint', generationState);
                processedData = newData;
                success = true;
            else
                errMsg = procErrMsg;
                success = false;
            end
        end
    end

%% --- TIFF MODE SPECIFIC CALLBACKS (with state manager updates) ---
    function selectFileCallback_TIFF(~, ~)
        [fileName, pathName] = uigetfile({'*.tif;*.tiff', 'TIFF Files (*.tif, *.tiff)'}, 'Select a TIFF file');
        if isequal(fileName, 0), return; end
        
        fullFilePath = fullfile(pathName, fileName);
        
        % Update state through state manager
        stateManager.updateActiveState('TIFF.isFolderMode', false);
        stateManager.updateActiveState('TIFF.fullFilePath', fullFilePath);
        stateManager.updateActiveState('TIFF.selectedFolderPath', '');
        stateManager.clearCache();
        
        set(hText, 'String', sprintf('Analyzing file:\n%s...', fileName)); drawnow;
        try
            processMetadata_TIFF(fullFilePath, fileName);
        catch ME
            set(hText, 'String', sprintf('Error reading file:\n%s\n\nDetails:\n%s', fullFilePath, ME.message));
        end
    end

    function selectFolderCallback_TIFF(~, ~)
        folderName = uigetdir();
        if isequal(folderName, 0), return; end
        
        % Update state through state manager
        stateManager.updateActiveState('TIFF.isFolderMode', true);
        stateManager.updateActiveState('TIFF.selectedFolderPath', folderName);
        stateManager.updateActiveState('TIFF.fullFilePath', '');
        stateManager.clearCache();
        
        set(hText, 'String', sprintf('Analyzing folder:\n%s...', folderName)); drawnow;
        try
            tiffFiles = dir(fullfile(folderName, '*.tif*'));
            if isempty(tiffFiles), error('No TIFF files found in the selected folder.'); end
            
            firstFilePath = fullfile(folderName, tiffFiles(1).name);
            [~, name, ~] = fileparts(tiffFiles(1).name);
            fileBaseName = regexprep(name, '_\d{5}$', '');
            stateManager.updateActiveState('TIFF.fileBaseName', fileBaseName);
            
            processMetadata_TIFF(firstFilePath, folderName);
        catch ME
            set(hText, 'String', sprintf('Error reading folder:\n%s\n\nDetails:\n%s', folderName, ME.message));
        end
    end

%% --- NEURAL DATA MODE SPECIFIC CALLBACKS (with state manager updates) ---
    function loadDataCallback_Neural(~, ~)
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select Data File');
        if isequal(fileName, 0), return; end
        
        dataFilePath = fullfile(pathName, fileName);
        stateManager.updateActiveState('Neural.dataFilePath', dataFilePath);
        
        try
            set(hText, 'String', sprintf('Loading data from:\n%s...', fileName)); drawnow;
            data = load(dataFilePath, 'psths', 'psthsnp');
            if ~isfield(data, 'psths') || ~isfield(data, 'psthsnp')
                error('The selected .mat file must contain "psths" and "psthsnp" variables.');
            end
            
            if ndims(data.psths) ~= 3 || ~isequal(size(data.psths), size(data.psthsnp))
                error('Data must be 3D (N x t x R) and psths/psthsnp must be the same size.');
            end
            
            stateManager.updateActiveState('Neural.psthsData', data.psths);
            stateManager.updateActiveState('Neural.psthsnpData', data.psthsnp);
            stateManager.clearCache();
            
            set(hText, 'String', sprintf('Data loaded successfully from:\n%s', fileName)); drawnow;
            updateDisplayInfo();
        catch ME
            set(hText, 'String', sprintf('Error loading data file:\n%s', ME.message));
            stateManager.updateActiveState('Neural.dataFilePath', '');
            stateManager.updateActiveState('Neural.psthsData', []);
            stateManager.updateActiveState('Neural.psthsnpData', []);
        end
    end

    function loadCoordsCallback_Neural(~, ~)
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select Coordinates File');
        if isequal(fileName, 0), return; end
        
        coordsFilePath = fullfile(pathName, fileName);
        stateManager.updateActiveState('Neural.coordsFilePath', coordsFilePath);
        
        try
            set(hText, 'String', sprintf('Loading coordinates from:\n%s...', fileName)); drawnow;
            data = load(coordsFilePath);
            f = fields(data);
            if numel(f) < 1, error('The selected .mat file is empty.'); end
            coords = data.(f{1});
            if ~ismatrix(coords) || size(coords, 2) ~= 2, error('Coordinates must be an N x 2 matrix.'); end
            
            stateManager.updateActiveState('Neural.cellCoords', coords);
            stateManager.clearCache();
            
            set(hText, 'String', sprintf('Coordinates loaded successfully from:\n%s', fileName)); drawnow;
            updateDisplayInfo();
        catch ME
            set(hText, 'String', sprintf('Error loading coordinates file:\n%s', ME.message));
            stateManager.updateActiveState('Neural.coordsFilePath', '');
            stateManager.updateActiveState('Neural.cellCoords', []);
        end
    end
    
    function loadTiffCallback_Neural(~, ~)
        folderName = uigetdir('', 'Select the original TIFF folder');
        if isequal(folderName, 0), return; end
        
        stateManager.updateActiveState('Neural.tiffFolderPath', folderName);
        
        try
            set(hText, 'String', sprintf('Analyzing TIFF folder:\n%s...', folderName)); drawnow;
            tiffFiles = dir(fullfile(folderName, '*.tif*'));
            if isempty(tiffFiles), error('No TIFF files found in the selected folder.'); end
            
            firstTiffPath = fullfile(folderName, tiffFiles(1).name);
            processTiffMetadataForInfo_Neural(firstTiffPath);
            
            stateManager.clearCache();
            set(hText, 'String', sprintf('TIFF folder loaded successfully:\n%s', folderName)); drawnow;
            updateDisplayInfo();
        catch ME
            set(hText, 'String', sprintf('Error reading TIFF folder:\n%s', ME.message));
            stateManager.updateActiveState('Neural.tiffFolderPath', '');
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
            
            % Update both modes since vareas can be used by both
            stateManager.updateActiveState('TIFF.vareaData', vareaData);
            stateManager.updateActiveState('TIFF.vareaFilePath', filePath);
            stateManager.updateActiveState('Neural.vareaData', vareaData);
            stateManager.updateActiveState('Neural.vareaFilePath', filePath);
            stateManager.clearCache();
            
            set(hText, 'String', sprintf('Visual areas loaded from:\n%s', fileName)); drawnow;
            updateDisplayInfo();
        catch ME
            set(hText, 'String', sprintf('Error loading visual area file:\n%s', ME.message));
            stateManager.updateActiveState('TIFF.vareaFilePath', '');
            stateManager.updateActiveState('TIFF.vareaData', []);
            stateManager.updateActiveState('Neural.vareaFilePath', '');
            stateManager.updateActiveState('Neural.vareaData', []);
        end
    end

%% --- HELPER FUNCTIONS ---
    function refreshUIFromState()
        % Get active state and update all UI elements
        state = stateManager.getActiveState();
        
        % Update mode dropdown (without triggering callback)
        set(hModeSelector, 'Value', ifelse(strcmp(state.currentMode, 'TIFF'), 1, 2));
        
        % Update visibility of panels
        isTiffMode = strcmp(state.currentMode, 'TIFF');
        set(hTiffLoadPanel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hNeuralLoadPanel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        
        % Update mode-specific control visibility
        set(hPlaneLabel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hPlaneDropdown, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hChannelLabel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hChannelDropdown, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hSmoothingLabel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hSmoothingWindowInput, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        
        set(hNeuropilCoeffLabel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hNeuropilCoeffInput, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hDetrendCheckbox, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hDetrendWindowLabel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hDetrendWindowInput, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hForcePositiveCheckbox, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        
        % Update all parameter values from state
        if isfield(state, 'ui')
            set(hRollingAvgInput, 'String', state.ui.rollingAvg);
            set(hTrialInput, 'String', state.ui.trials);
            set(hDisplayMode, 'Value', state.ui.displayMode);
            set(hInitialFramesInput, 'String', state.ui.initialFrames);
            set(hRefTrialsInput, 'String', state.ui.refTrials);
            set(hDivideByF0Checkbox, 'Value', state.ui.divideByF0);
            set(hFrameByFrameCheckbox, 'Value', state.ui.frameByFrame);
            
            if isTiffMode
                set(hPlaneDropdown, 'Value', state.ui.plane);
                set(hChannelDropdown, 'Value', state.ui.channel);
                set(hSmoothingWindowInput, 'String', state.ui.smoothingSigma);
                
                % Update plane/channel dropdowns if metadata exists
                if state.TIFF.parsedNumPlanes > 0
                    set(hPlaneDropdown, 'String', 1:state.TIFF.parsedNumPlanes);
                end
                if state.TIFF.parsedNumChannels > 0
                    set(hChannelDropdown, 'String', 1:state.TIFF.parsedNumChannels);
                end
            else
                set(hNeuropilCoeffInput, 'String', state.ui.neuropilCoeff);
                set(hDetrendCheckbox, 'Value', state.ui.detrend);
                set(hDetrendWindowInput, 'String', state.ui.detrendWindow);
                set(hForcePositiveCheckbox, 'Value', state.ui.forcePositive);
            end
        end
        
        % Update display mode visibility
        updateDisplayMode();
        
        % Update info display
        updateDisplayInfo();
    end

    function saveUIStateToActiveSlot()
        % Save current UI values to active state slot
        state = stateManager.getActiveState();
        
        stateManager.updateActiveState('ui.rollingAvg', get(hRollingAvgInput, 'String'));
        stateManager.updateActiveState('ui.trials', get(hTrialInput, 'String'));
        stateManager.updateActiveState('ui.displayMode', get(hDisplayMode, 'Value'));
        stateManager.updateActiveState('ui.initialFrames', get(hInitialFramesInput, 'String'));
        stateManager.updateActiveState('ui.refTrials', get(hRefTrialsInput, 'String'));
        stateManager.updateActiveState('ui.divideByF0', get(hDivideByF0Checkbox, 'Value'));
        stateManager.updateActiveState('ui.frameByFrame', get(hFrameByFrameCheckbox, 'Value'));
        
        if strcmp(state.currentMode, 'TIFF')
            stateManager.updateActiveState('ui.plane', get(hPlaneDropdown, 'Value'));
            stateManager.updateActiveState('ui.channel', get(hChannelDropdown, 'Value'));
            stateManager.updateActiveState('ui.smoothingSigma', get(hSmoothingWindowInput, 'String'));
        else
            stateManager.updateActiveState('ui.neuropilCoeff', get(hNeuropilCoeffInput, 'String'));
            stateManager.updateActiveState('ui.detrend', get(hDetrendCheckbox, 'Value'));
            stateManager.updateActiveState('ui.detrendWindow', get(hDetrendWindowInput, 'String'));
            stateManager.updateActiveState('ui.forcePositive', get(hForcePositiveCheckbox, 'Value'));
        end
    end

    function mode = getCurrentModeFromDropdown()
        modeIndex = get(hModeSelector, 'Value');
        mode = ifelse(modeIndex == 1, 'TIFF', 'Neural');
    end

    function state = captureFullState()
        % Get current state from state manager
        state = stateManager.getActiveState();
        
        % Add physical coordinates if in neural mode
        if strcmp(state.currentMode, 'Neural') && ~isempty(state.Neural.cellCoords)
            N = state.Neural;
            state.physicalCoords = [N.cellCoords(:,1) ./ N.x_pixels_per_um, ...
                                   N.cellCoords(:,2) ./ N.y_pixels_per_um];
        else
            state.physicalCoords = [];
        end
        
        % Ensure frameRate is set
        if strcmp(state.currentMode, 'TIFF')
            state.frameRate = state.TIFF.nativeFrameRate;
        else
            state.frameRate = state.Neural.nativeFrameRate;
        end
    end

    function processMetadata_TIFF(filePath, displayName)
        % Process TIFF metadata and update state
        info = imfinfo(filePath);
        frameRateStr = 'N/A'; numPlanes = '1'; numRois = '1'; isMesoscan = 'No'; numChannels = '1';
        physicalDimStr = 'N/A'; trueDimStr = 'N/A'; zoomFactor = 1;
        
        % [Rest of the metadata processing code remains the same]
        % ... (copy the rest of the processMetadata_TIFF function from v1)
        
        % Update state through state manager
        stateManager.updateActiveState('TIFF.metadataString', metadataString);
        set(hText, 'String', metadataString);
    end