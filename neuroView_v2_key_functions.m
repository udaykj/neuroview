%% Key Updated Functions for neuroView v2
% Copy these functions to replace the corresponding ones in your v1 code
% Don't forget to add "stateManager = StateManagerV2();" at the beginning

%% 1. Updated modeSwitchCallback
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

%% 2. Updated switchOperatingContextCallback
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

%% 3. Updated loadStateCallback
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

%% 4. Updated showInfoCallback
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

%% 5. Example of updated data loading callback (selectFileCallback_TIFF)
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

%% 6. New refreshUIFromState function
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

%% 7. Updated captureFullState function
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

%% 8. Helper function
function mode = getCurrentModeFromDropdown()
    modeIndex = get(hModeSelector, 'Value');
    mode = ifelse(modeIndex == 1, 'TIFF', 'Neural');
end

%% Example patterns for updating other functions:
% 
% PATTERN 1: Reading state
% OLD: if strcmp(appState.currentMode, 'TIFF')
% NEW: state = stateManager.getActiveState();
%      if strcmp(state.currentMode, 'TIFF')
%
% PATTERN 2: Writing to state
% OLD: appState.TIFF.fullFilePath = filePath;
% NEW: stateManager.updateActiveState('TIFF.fullFilePath', filePath);
%
% PATTERN 3: Clearing cache
% OLD: appState.sessionCache = struct('data', [], 'fingerprint', []);
% NEW: stateManager.clearCache();
%
% PATTERN 4: Getting/setting deep nested values
% OLD: appState.Neural.psthsData = data.psths;
% NEW: stateManager.updateActiveState('Neural.psthsData', data.psths);