function neuroView_v2_demo()
% NEUROVIEW_V2_DEMO - Simplified demo of the 4-state architecture
% This is a working example that demonstrates the key v2 features
% You can run this directly to see how the 4-state system works

% --- Initialize State Manager ---
stateManager = StateManagerV2();

% --- GUI Setup ---
hFig = figure('Name', 'NeuroView v2 Demo - 4-State Architecture', ...
    'NumberTitle', 'off', 'Position', [400 200 450, 600], 'MenuBar', 'none', ...
    'Resize', 'off', 'Color', [0.94 0.94 0.94]);

% --- Mode Selector ---
uicontrol('Style', 'text', 'String', 'Operating Mode:', 'Position', [60 560 120 20], ...
    'FontSize', 11, 'FontWeight', 'bold', 'HorizontalAlignment','right',...
    'BackgroundColor', [0.94 0.94 0.94]);
hModeSelector = uicontrol('Style', 'popupmenu', 'String', {'TIFF Viewer', 'Neural Data Viewer'}, ...
    'Position', [190 565 150 20], 'FontSize', 10, 'Callback', @modeSwitchCallback);

% --- OPERATING CONTEXT SWITCH ---
hContextPanel = uibuttongroup('Parent', hFig, 'Title', 'Operating Context', ...
    'Units', 'pixels', 'Position', [10 510 430 45], 'FontSize', 9);
hContextSession = uicontrol('Parent', hContextPanel, 'Style', 'radiobutton', 'String', 'Current Session', ...
    'Position', [20 5 150 20], 'Value', 1, 'BackgroundColor', [0.94 0.94 0.94]);
hContextLoaded = uicontrol('Parent', hContextPanel, 'Style', 'radiobutton', 'String', 'Loaded State', ...
    'Position', [250 5 150 20], 'Value', 0, 'Enable', 'off', 'BackgroundColor', [0.94 0.94 0.94]);
set(hContextPanel, 'SelectionChangedFcn', @switchOperatingContextCallback);

% --- State Display ---
hStateDisplay = uicontrol('Style', 'edit', 'String', 'State Info Will Appear Here', ...
    'Position', [10 200 430 300], 'FontSize', 10, 'HorizontalAlignment', 'left', ...
    'Enable', 'on', 'Max', 2, 'Min', 0);

% --- Demo Controls ---
hDemoPanel = uipanel('Parent', hFig, 'Title', 'Demo Controls', ...
    'Units', 'pixels', 'Position', [10 50 430 140], 'FontSize', 10);

uicontrol('Parent', hDemoPanel, 'Style', 'text', 'String', 'Parameter 1:', ...
    'Position', [10 90 80 20], 'HorizontalAlignment', 'right');
hParam1 = uicontrol('Parent', hDemoPanel, 'Style', 'edit', 'String', 'Default', ...
    'Position', [100 90 100 20], 'Callback', @(s,e) updateParam('param1', get(s,'String')));

uicontrol('Parent', hDemoPanel, 'Style', 'text', 'String', 'Parameter 2:', ...
    'Position', [210 90 80 20], 'HorizontalAlignment', 'right');
hParam2 = uicontrol('Parent', hDemoPanel, 'Style', 'edit', 'String', '1', ...
    'Position', [300 90 100 20], 'Callback', @(s,e) updateParam('param2', get(s,'String')));

uicontrol('Parent', hDemoPanel, 'Style', 'pushbutton', 'String', 'Simulate Load Data', ...
    'Position', [10 50 150 30], 'Callback', @simulateLoadData);

uicontrol('Parent', hDemoPanel, 'Style', 'pushbutton', 'String', 'Load Demo State', ...
    'Position', [170 50 150 30], 'Callback', @loadDemoState);

hReloadCheckbox = uicontrol('Parent', hDemoPanel, 'Style', 'checkbox', ...
    'String', 'Enable editing in loaded state', 'Position', [10 20 200 20], ...
    'Value', 0, 'BackgroundColor', [0.94 0.94 0.94]);

% --- Action Buttons ---
uicontrol('Style', 'pushbutton', 'String', 'Show Current State', ...
    'Position', [40 10 180 30], 'FontSize', 10, 'Callback', @showStateInfo);

uicontrol('Style', 'pushbutton', 'String', 'Test State Isolation', ...
    'Position', [230 10 180 30], 'FontSize', 10, 'Callback', @testIsolation);

% Initialize display
refreshUI();

%% --- CALLBACKS ---

    function modeSwitchCallback(src, ~)
        isCurrentContext = get(hContextSession, 'Value') == 1;
        currentMode = stateManager.getCurrentMode();
        newModeIndex = get(src, 'Value');
        newMode = ifelse(newModeIndex == 1, 'TIFF', 'Neural');
        
        if isCurrentContext
            stateManager.setActiveSlot(newMode, 'current');
            stateManager.updateActiveState('currentMode', newMode);
            refreshUI();
            addMessage(sprintf('Switched to %s mode', newMode));
        else
            set(src, 'Value', ifelse(strcmp(currentMode, 'TIFF'), 1, 2));
            addMessage('Cannot switch modes in loaded context!');
        end
    end

    function switchOperatingContextCallback(~,~)
        isLoadedContext = get(hContextLoaded, 'Value') == 1;
        currentMode = getCurrentModeFromDropdown();
        
        if isLoadedContext
            if ~stateManager.hasLoadedState(currentMode)
                set(hContextSession, 'Value', 1);
                set(hContextLoaded, 'Value', 0);
                addMessage(sprintf('No loaded %s state available!', currentMode));
                return;
            end
            
            stateManager.setActiveSlot(currentMode, 'loaded');
            set(hModeSelector, 'Enable', 'off');
            
            if stateManager.isLoadedStateReadOnly()
                setControlsEnabled(false);
                addMessage('Switched to Loaded State (read-only)');
            else
                setControlsEnabled(true);
                addMessage('Switched to Loaded State (editable)');
            end
        else
            stateManager.setActiveSlot(currentMode, 'current');
            set(hModeSelector, 'Enable', 'on');
            setControlsEnabled(true);
            addMessage('Switched back to Current Session');
        end
        
        refreshUI();
    end

    function simulateLoadData(~,~)
        state = stateManager.getActiveState();
        timestamp = datestr(now, 'HH:MM:SS');
        
        if strcmp(state.currentMode, 'TIFF')
            stateManager.updateActiveState('TIFF.fullFilePath', sprintf('demo_tiff_%s.tif', timestamp));
            stateManager.updateActiveState('TIFF.metadataString', sprintf('TIFF loaded at %s', timestamp));
        else
            stateManager.updateActiveState('Neural.dataFilePath', sprintf('demo_neural_%s.mat', timestamp));
            stateManager.updateActiveState('Neural.metadataString', sprintf('Neural data loaded at %s', timestamp));
        end
        
        addMessage(sprintf('Simulated data load for %s mode', state.currentMode));
        showStateInfo();
    end

    function loadDemoState(~,~)
        currentMode = getCurrentModeFromDropdown();
        
        % Create a demo state
        demoState = struct();
        demoState.currentMode = currentMode;
        demoState.mode = currentMode; % For compatibility
        demoState.reloadRaw = get(hReloadCheckbox, 'Value');
        
        if strcmp(currentMode, 'TIFF')
            demoState.TIFF = struct('fullFilePath', 'loaded_demo.tif', ...
                'metadataString', 'This is a loaded TIFF state');
            demoState.Neural = struct('dataFilePath', '', 'metadataString', '');
        else
            demoState.Neural = struct('dataFilePath', 'loaded_demo.mat', ...
                'metadataString', 'This is a loaded Neural state');
            demoState.TIFF = struct('fullFilePath', '', 'metadataString', '');
        end
        
        demoState.ui = struct('param1', 'LoadedValue', 'param2', '999');
        
        % Load it
        if stateManager.loadStateIntoSlot(demoState, currentMode)
            set(hContextLoaded, 'Enable', 'on', 'Value', 1);
            set(hContextSession, 'Value', 0);
            switchOperatingContextCallback();
        end
    end

    function testIsolation(~,~)
        msg = sprintf('=== STATE ISOLATION TEST ===\n\n');
        
        % Show all 4 states
        states = {'Current TIFF', 'Current Neural', 'Loaded TIFF', 'Loaded Neural'};
        slots = {stateManager.CURRENT_TIFF, stateManager.CURRENT_NEURAL, ...
                 stateManager.LOADED_TIFF, stateManager.LOADED_NEURAL};
        
        for i = 1:4
            stateData = stateManager.states.(slots{i});
            if isempty(stateData)
                msg = sprintf('%s%s: [EMPTY]\n', msg, states{i});
            else
                param1 = '';
                param2 = '';
                if isfield(stateData, 'ui')
                    if isfield(stateData.ui, 'param1'), param1 = stateData.ui.param1; end
                    if isfield(stateData.ui, 'param2'), param2 = stateData.ui.param2; end
                end
                msg = sprintf('%s%s: param1="%s", param2="%s"\n', ...
                    msg, states{i}, param1, param2);
            end
        end
        
        msg = sprintf('%s\nEach state is completely independent!', msg);
        set(hStateDisplay, 'String', msg);
    end

    function updateParam(param, value)
        stateManager.updateActiveState(['ui.' param], value);
        addMessage(sprintf('Updated %s to "%s" in active state', param, value));
    end

    function showStateInfo(~,~)
        state = stateManager.getActiveState();
        activeSlot = stateManager.activeSlot;
        
        msg = sprintf('=== ACTIVE STATE INFO ===\n');
        msg = sprintf('%sActive Slot: %s\n', msg, strrep(activeSlot, '_', ' '));
        msg = sprintf('%sMode: %s\n', msg, state.currentMode);
        
        if strcmp(state.currentMode, 'TIFF')
            msg = sprintf('%s\nTIFF Data:\n', msg);
            msg = sprintf('%sFile: %s\n', msg, state.TIFF.fullFilePath);
            if ~isempty(state.TIFF.metadataString)
                msg = sprintf('%sMetadata: %s\n', msg, state.TIFF.metadataString);
            end
        else
            msg = sprintf('%s\nNeural Data:\n', msg);
            msg = sprintf('%sFile: %s\n', msg, state.Neural.dataFilePath);
            if ~isempty(state.Neural.metadataString)
                msg = sprintf('%sMetadata: %s\n', msg, state.Neural.metadataString);
            end
        end
        
        msg = sprintf('%s\nUI Parameters:\n', msg);
        if isfield(state, 'ui')
            msg = sprintf('%sParam1: %s\n', msg, state.ui.param1);
            msg = sprintf('%sParam2: %s\n', msg, state.ui.param2);
        end
        
        set(hStateDisplay, 'String', msg);
    end

    function refreshUI()
        state = stateManager.getActiveState();
        
        % Update mode dropdown
        set(hModeSelector, 'Value', ifelse(strcmp(state.currentMode, 'TIFF'), 1, 2));
        
        % Update parameters
        if isfield(state, 'ui')
            if isfield(state.ui, 'param1'), set(hParam1, 'String', state.ui.param1); end
            if isfield(state.ui, 'param2'), set(hParam2, 'String', state.ui.param2); end
        end
        
        showStateInfo();
    end

    function setControlsEnabled(enabled)
        if enabled
            set(hParam1, 'Enable', 'on');
            set(hParam2, 'Enable', 'on');
        else
            set(hParam1, 'Enable', 'off');
            set(hParam2, 'Enable', 'off');
        end
    end

    function addMessage(msg)
        current = get(hStateDisplay, 'String');
        if ~iscell(current), current = {current}; end
        current{end+1} = sprintf('\n>>> %s', msg);
        set(hStateDisplay, 'String', current);
    end

    function mode = getCurrentModeFromDropdown()
        modeIndex = get(hModeSelector, 'Value');
        mode = ifelse(modeIndex == 1, 'TIFF', 'Neural');
    end

    function out = ifelse(condition, true_val, false_val)
        if condition, out = true_val; else, out = false_val; end
    end

end

%% --- EMBEDDED STATE MANAGER CLASS ---
% This is included here for the demo to be self-contained
% In production, use the separate StateManagerV2.m file