function neuroViewRefactored()
% NEUROVIEWREFACTORED Example of refactored NeuroView using StateManager
%   This demonstrates how the new StateManager class can be used to
%   simplify state management in the NeuroView GUI.

% --- Initialize State Manager ---
stateManager = StateManager();

% --- GUI Setup ---
hFig = figure('Name', 'NeuroView - Refactored', ...
    'NumberTitle', 'off', 'Position', [400 200 450, 750], 'MenuBar', 'none', ...
    'Resize', 'off', 'Color', [0.94 0.94 0.94]);

% --- Mode Selector ---
uicontrol('Style', 'text', 'String', 'Operating Mode:', 'Position', [60 710 120 20], ...
    'FontSize', 11, 'FontWeight', 'bold', 'HorizontalAlignment','right',...
    'BackgroundColor', [0.94 0.94 0.94]);
hModeSelector = uicontrol('Style', 'popupmenu', 'String', {'TIFF Viewer', 'Neural Data Viewer'}, ...
    'Position', [190 715 150 20], 'FontSize', 10, 'Callback', @modeSwitchCallback);

% --- Context Switch ---
hContextPanel = uibuttongroup('Parent', hFig, 'Title', 'Operating Context', ...
    'Units', 'pixels', 'Position', [10 660 430 45], 'FontSize', 9);
hContextSession = uicontrol('Parent', hContextPanel, 'Style', 'radiobutton', 'String', 'Current Session', ...
    'Position', [20 5 150 20], 'Value', 1, 'BackgroundColor', [0.94 0.94 0.94]);
hContextLoaded = uicontrol('Parent', hContextPanel, 'Style', 'radiobutton', 'String', 'Loaded State', ...
    'Position', [250 5 150 20], 'Value', 0, 'Enable', 'off', 'BackgroundColor', [0.94 0.94 0.94]);
set(hContextPanel, 'SelectionChangedFcn', @contextSwitchCallback);

% --- File Loading Panels ---
hTiffLoadPanel = uipanel('Parent', hFig, 'Title', 'TIFF Data Loading', ...
    'Units', 'pixels', 'Position', [10 540 430 110], 'FontSize', 10);
uicontrol('Parent', hTiffLoadPanel, 'Style', 'pushbutton', 'String', 'Select File', ...
    'Position', [10 40 90 30], 'FontSize', 10, 'Callback', @selectFileCallback_TIFF);
uicontrol('Parent', hTiffLoadPanel, 'Style', 'pushbutton', 'String', 'Load State', ...
    'Position', [295 40 125 30], 'FontSize', 10, 'Callback', @loadStateCallback);

hNeuralLoadPanel = uipanel('Parent', hFig, 'Title', 'Processed Neural Data Loading', ...
    'Units', 'pixels', 'Position', [10 540 430 110], 'Visible', 'off', 'FontSize', 10);
uicontrol('Parent', hNeuralLoadPanel, 'Style', 'pushbutton', 'String', 'Load Data', ...
    'Position', [5 40 80 30], 'FontSize', 10, 'Callback', @loadDataCallback_Neural);
uicontrol('Parent', hNeuralLoadPanel, 'Style', 'pushbutton', 'String', 'Load State', ...
    'Position', [345 40 80 30], 'FontSize', 10, 'Callback', @loadStateCallback);

% --- Main Text Display ---
hText = uicontrol('Style', 'edit', 'String', 'Welcome! Select a mode and load data to begin.', ...
    'Position', [40 290 370 240], 'FontSize', 10, 'HorizontalAlignment', 'left', ...
    'Enable', 'on', 'Max', 2, 'Min', 0);

% --- Action Buttons ---
uicontrol('Style', 'pushbutton', 'String', 'Show Info', 'Position', [40 40 120 30], 'FontSize', 10, 'Callback', @showInfoCallback);
uicontrol('Style', 'pushbutton', 'String', 'Save State', 'Position', [165 40 120 30], 'FontSize', 10, 'Callback', @saveStateCallback);
uicontrol('Style', 'pushbutton', 'String', 'Clear Cache', 'Position', [290 40 120 30], 'FontSize', 10, 'Callback', @clearCacheCallback);

% --- Set up event listeners ---
addlistener(stateManager, 'ModeChanged', @onModeChanged);
addlistener(stateManager, 'ContextChanged', @onContextChanged);
addlistener(stateManager, 'DataLoaded', @onDataLoaded);
addlistener(stateManager, 'CacheInvalidated', @onCacheInvalidated);

% --- Store state manager in figure ---
set(hFig, 'UserData', stateManager);

%% --- Callback Functions ---

    function modeSwitchCallback(src, ~)
        newModeIndex = get(src, 'Value');
        newMode = ifelse(newModeIndex == 1, 'TIFF', 'Neural');
        stateManager.switchMode(newMode);
    end

    function contextSwitchCallback(~, ~)
        if get(hContextLoaded, 'Value') == 1
            stateManager.switchContext('loaded');
        else
            stateManager.switchContext('current');
        end
    end

    function selectFileCallback_TIFF(~, ~)
        [fileName, pathName] = uigetfile({'*.tif;*.tiff', 'TIFF Files (*.tif, *.tiff)'}, 'Select a TIFF file');
        if isequal(fileName, 0), return; end
        
        stateManager.setTiffState('fullFilePath', fullfile(pathName, fileName));
        stateManager.setTiffState('isFolderMode', false);
        stateManager.setTiffState('selectedFolderPath', '');
        
        % Process metadata
        processMetadata_TIFF(fullfile(pathName, fileName), fileName);
    end

    function loadDataCallback_Neural(~, ~)
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select Data File');
        if isequal(fileName, 0), return; end
        
        try
            data = load(fullfile(pathName, fileName), 'psths', 'psthsnp');
            if ~isfield(data, 'psths') || ~isfield(data, 'psthsnp')
                error('The selected .mat file must contain "psths" and "psthsnp" variables.');
            end
            
            stateManager.setNeuralState('dataFilePath', fullfile(pathName, fileName));
            stateManager.setNeuralState('psthsData', data.psths);
            stateManager.setNeuralState('psthsnpData', data.psthsnp);
            
            set(hText, 'String', sprintf('Data loaded successfully from:\n%s', fileName));
            
        catch ME
            set(hText, 'String', sprintf('Error loading data file:\n%s', ME.message));
        end
    end

    function loadStateCallback(~, ~)
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select a saved state file');
        if isequal(fileName, 0), return; end
        
        try
            stateManager.loadState(fullfile(pathName, fileName));
            set(hContextLoaded, 'Enable', 'on', 'Value', 1);
            set(hContextSession, 'Value', 0);
        catch ME
            set(hText, 'String', sprintf('Error loading state file:\n%s', ME.message));
        end
    end

    function saveStateCallback(~, ~)
        [fileName, pathName] = uiputfile({'*.mat', 'MAT-files (*.mat)'}, 'Save state as');
        if isequal(fileName, 0), return; end
        
        try
            stateManager.saveState(fullfile(pathName, fileName), false); % Don't include raw data
            set(hText, 'String', sprintf('State saved to:\n%s', fullfile(pathName, fileName)));
        catch ME
            set(hText, 'String', sprintf('Error saving state:\n%s', ME.message));
        end
    end

    function clearCacheCallback(~, ~)
        stateManager.clearCache();
        set(hText, 'String', 'Cache cleared successfully.');
    end

    function showInfoCallback(~, ~)
        if stateManager.IsLoadedStateActive
            state = stateManager.loadedStateSnapshot;
        else
            state = stateManager.getCurrentState();
        end
        
        mode = state.mode;
        if strcmp(mode, 'TIFF')
            metadata = stateManager.getTiffState('metadataString');
            if ~isempty(metadata)
                set(hText, 'String', metadata);
            end
        else
            metadata = stateManager.getNeuralState('metadataString');
            if ~isempty(metadata)
                set(hText, 'String', metadata);
            end
        end
    end

%% --- Event Handlers ---

    function onModeChanged(~, eventData)
        % Update UI visibility based on new mode
        isTiffMode = strcmp(eventData.NewMode, 'TIFF');
        set(hTiffLoadPanel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hNeuralLoadPanel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        
        % Update display
        updateDisplayInfo();
    end

    function onContextChanged(~, eventData)
        if strcmp(eventData.NewContext, 'loaded')
            set(hModeSelector, 'Enable', 'off');
            set(hText, 'String', 'Viewing loaded state (read-only)');
        else
            set(hModeSelector, 'Enable', 'on');
            set(hText, 'String', 'Current session mode');
        end
    end

    function onDataLoaded(~, eventData)
        set(hText, 'String', sprintf('State loaded from:\n%s', eventData.Filepath));
    end

    function onCacheInvalidated(~, ~)
        set(hText, 'String', 'Cache invalidated - data will be reprocessed');
    end

%% --- Helper Functions ---

    function processMetadata_TIFF(filePath, displayName)
        % Simplified metadata processing
        try
            info = imfinfo(filePath);
            metadata = sprintf('File: %s\nDimensions: %d x %d\nFrames: %d', ...
                displayName, info(1).Width, info(1).Height, numel(info));
            
            stateManager.setTiffState('metadataString', metadata);
            set(hText, 'String', metadata);
        catch ME
            set(hText, 'String', sprintf('Error reading file:\n%s', ME.message));
        end
    end

    function updateDisplayInfo()
        % Update display based on current state
        if stateManager.IsLoadedStateActive
            set(hText, 'String', 'Viewing loaded state');
        else
            mode = stateManager.CurrentMode;
            if strcmp(mode, 'TIFF')
                metadata = stateManager.getTiffState('metadataString');
                if ~isempty(metadata)
                    set(hText, 'String', metadata);
                else
                    set(hText, 'String', 'TIFF mode - please load a file');
                end
            else
                metadata = stateManager.getNeuralState('metadataString');
                if ~isempty(metadata)
                    set(hText, 'String', metadata);
                else
                    set(hText, 'String', 'Neural mode - please load data');
                end
            end
        end
    end

    function out = ifelse(condition, true_val, false_val)
        if condition, out = true_val; else, out = false_val; end
    end
end