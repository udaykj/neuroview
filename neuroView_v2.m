function neuroView_v2()
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
    end