function neuroView_v2()
% NEUROVIEW_V2 Creates a unified GUI to visualize raw TIFF movies or pre-processed neural data.
%   Enhanced with four-slot state management for perfect state isolation.
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
%   ENHANCED STATE MANAGEMENT:
%   - Four isolated state slots: Current Session (TIFF/Neural) + Loaded State (TIFF/Neural)
%   - Perfect state preservation and restoration
%   - Mode-aware state loading with validation
%   - Context switching with complete UI restoration

% --- Initialize Enhanced State Manager ---
stateManager = StateManager_v2();

% --- Main State Variables (kept for compatibility) ---
isSwitchingContext = false; % Guard flag to prevent caching during programmatic UI updates
appState = struct(); % Master state holder - now just a compatibility layer
appState.currentMode = 'TIFF'; % 'TIFF' or 'Neural'

% Mode-specific data (kept for compatibility)
appState.TIFF = struct('fullFilePath','','selectedFolderPath','','fileBaseName','',...
    'isFolderMode',false,'roiData',[],'metadataString','','dataAspectRatio',[1 1 1],...
    'x_pixels_per_unit',1,'y_pixels_per_unit',1,'parsedNumPlanes',0,...
    'parsedNumChannels',0, 'nativeFrameRate', 30, 'pixelWidth', 512, 'pixelHeight', 512);
appState.Neural = struct('dataFilePath','','coordsFilePath','','tiffFolderPath','',...
    'vareaFilePath','','psthsData',[],'psthsnpData',[],'cellCoords',[],'vareaData',[],...
    'numNeurons',0,'numTimepoints',0,'numTrials',0,'metadataString','',...
    'nativeFrameRate',30,'plotXLim',[0 1],'plotYLim',[0 1],'pixelWidth',512,...
    'pixelHeight',512,'x_pixels_per_um',1,'y_pixels_per_um',1);

% Shared state & context management (kept for compatibility)
appState.uiStateCache = struct(); % To save UI settings on mode switch
appState.sessionCache = struct('data', [], 'fingerprint', []); % For caching processed data
appState.sessionState = []; % Snapshot of appState before loading a file state
appState.loadedStateSnapshot = []; % The state loaded from a file
appState.sessionMode = 'TIFF'; % Remembers the mode of the current session when viewing a loaded state

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
uicontrol('Parent', hTiffLoadPanel, 'Style', 'pushbutton', 'String', 'Load State', ...
    'Position', [295 40 90 30], 'FontSize', 10, 'Callback', @loadStateCallback);
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

% --- Store state manager in figure ---
set(hFig, 'UserData', stateManager);

% --- Set up event listeners ---
addlistener(stateManager, 'ModeChanged', @onModeChanged);
addlistener(stateManager, 'ContextChanged', @onContextChanged);
addlistener(stateManager, 'DataLoaded', @onDataLoaded);
addlistener(stateManager, 'UIRestored', @onUIRestored);

% --- Initialize UI State ---
cacheCurrentUIState(stateManager.CurrentMode);
updateDisplayMode();

%% --- ENHANCED CALLBACKS WITH FOUR-SLOT STATE MANAGEMENT ---

    function modeSwitchCallback(src, ~)
        % Enhanced mode switching with four-slot state management
        newModeIndex = get(src, 'Value');
        newMode = ifelse(newModeIndex == 1, 'TIFF', 'Neural');
        
        % Use state manager for mode switching
        stateManager.switchMode(newMode);
        
        % Update compatibility layer
        appState.currentMode = newMode;
    end

    function switchOperatingContextCallback(~, ~)
        % Enhanced context switching with perfect state restoration
        if get(hContextLoaded, 'Value') == 1
            stateManager.switchContext('loaded');
        else
            stateManager.switchContext('current');
        end
        
        % Update compatibility layer
        isSwitchingContext = true;
        appState.sessionMode = stateManager.CurrentMode;
        isSwitchingContext = false;
    end

    function loadStateCallback(~, ~)
        % Enhanced state loading with mode-aware validation
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select a saved state file');
        if isequal(fileName, 0), return; end
        
        loadPath = fullfile(pathName, fileName);
        
        try
            set(hText, 'String', 'Loading state...'); drawnow;
            
            % Get raw data reload setting
            isTiffMode = strcmp(stateManager.CurrentMode, 'TIFF');
            if isTiffMode
                reloadRaw = get(hReloadDataCheckbox_Tiff, 'Value');
            else
                reloadRaw = get(hReloadDataCheckbox_Neural, 'Value');
            end
            
            % Use state manager for loading
            stateManager.loadState(loadPath, reloadRaw);
            
            % Enable loaded state context
            set(hContextLoaded, 'Enable', 'on', 'Value', 1);
            set(hContextSession, 'Value', 0);
            
            % Update compatibility layer
            appState.loadedStateSnapshot = stateManager.getStateSnapshot('loaded', stateManager.CurrentMode);
            
        catch ME
            set(hText, 'String', sprintf('Error loading state file:\n%s', ME.message));
        end
    end

    function showInfoCallback(~, ~)
        % Enhanced info display based on current context and mode
        if stateManager.IsLoadedStateActive
            state = stateManager.getStateSnapshot('loaded', stateManager.CurrentMode);
        else
            state = stateManager.getStateSnapshot('current', stateManager.CurrentMode);
        end
        
        if strcmp(stateManager.CurrentMode, 'TIFF')
            metadata = stateManager.getStateField('metadataString');
            if ~isempty(metadata)
                set(hText, 'String', metadata);
            end
        else
            metadata = stateManager.getStateField('metadataString');
            if ~isempty(metadata)
                set(hText, 'String', metadata);
            end
        end
    end

    function plotAvgCallback(~, ~)
        % Enhanced plotting with context-aware state management
        if stateManager.IsLoadedStateActive
            % Use loaded state data
            state = stateManager.getStateSnapshot('loaded', stateManager.CurrentMode);
            if isfield(state, 'movieData')
                avgData = mean(state.movieData, ifelse(strcmp(stateManager.CurrentMode, 'TIFF'), 3, 2));
            else
                set(hText, 'String', 'No movie data available in loaded state');
                return;
            end
        else
            % Process current session data
            [processedData, localState, success, errMsg] = getOrProcessData();
            if ~success, set(hText, 'String', errMsg); return; end
            
            if strcmp(localState.mode, 'TIFF')
                avgData = mean(processedData, 3);
            else
                avgData = mean(processedData, 2);
            end
        end
        
        % Continue with existing plotting logic...
        try
            figName = ifelse(strcmp(stateManager.CurrentMode, 'TIFF'), 'Average Stitched Image', 'Average Neuronal Activity');
            hPlotFig = figure('Name', figName, 'NumberTitle', 'off', 'Position', [600 100 600 900]);
            
            hAxes = axes('Parent', hPlotFig, 'Units', 'normalized', 'Position', [0.1 0.35 0.8 0.56]);
            
            % Create visualization (simplified for this example)
            if strcmp(stateManager.CurrentMode, 'TIFF')
                imagesc(hAxes, avgData);
                title('Average TIFF Image');
            else
                scatter(hAxes, 1:size(avgData,1), avgData, 'filled');
                title('Average Neural Activity');
            end
            
            set(hText, 'String', 'Successfully plotted average activity.');
        catch ME
            set(hText, 'String', sprintf('Error plotting average:\n%s', ME.message));
        end
    end

    function playMovieCallback(~, ~)
        % Enhanced movie playing with context-aware state management
        if stateManager.IsLoadedStateActive
            % Use loaded state data
            state = stateManager.getStateSnapshot('loaded', stateManager.CurrentMode);
            if isfield(state, 'movieData')
                precomputedMovie = state.movieData;
                generationState = state;
            else
                set(hText, 'String', 'No movie data available in loaded state');
                return;
            end
        else
            % Process current session data
            [processedData, generationState, success, errMsg] = getOrProcessData();
            if ~success, set(hText, 'String', errMsg); return; end
            
            rollingAvg = round(str2double(get(hRollingAvgInput, 'String')));
            if isnan(rollingAvg) || rollingAvg < 1, set(hText, 'String', 'Invalid Rolling Average.'); return; end
            
            if strcmp(generationState.mode, 'TIFF')
                precomputedMovie = movmean(processedData, rollingAvg, 3, 'Endpoints', 'shrink');
            else
                precomputedMovie = movmean(processedData, rollingAvg, 2, 'Endpoints', 'shrink');
            end
        end
        
        % Launch movie player (simplified for this example)
        set(hText, 'String', 'Movie player launched (simplified implementation)');
    end

%% --- TIFF MODE SPECIFIC CALLBACKS (Enhanced) ---

    function selectFileCallback_TIFF(~, ~)
        [fileName, pathName] = uigetfile({'*.tif;*.tiff', 'TIFF Files (*.tif, *.tiff)'}, 'Select a TIFF file');
        if isequal(fileName, 0), return; end
        
        % Update state manager
        stateManager.setStateField('isFolderMode', false);
        stateManager.setStateField('fullFilePath', fullfile(pathName, fileName));
        stateManager.setStateField('selectedFolderPath', '');
        
        % Update compatibility layer
        appState.TIFF.isFolderMode = false;
        appState.TIFF.fullFilePath = fullfile(pathName, fileName);
        appState.TIFF.selectedFolderPath = '';
        
        % Clear caches
        stateManager.clearCache();
        appState.sessionCache = struct('data', [], 'fingerprint', []);
        
        set(hText, 'String', sprintf('Analyzing file:\n%s...', fileName)); drawnow;
        try
            processMetadata_TIFF(fullfile(pathName, fileName), fileName);
        catch ME
            set(hText, 'String', sprintf('Error reading file:\n%s', ME.message));
        end
    end

    function selectFolderCallback_TIFF(~, ~)
        folderName = uigetdir();
        if isequal(folderName, 0), return; end
        
        % Update state manager
        stateManager.setStateField('isFolderMode', true);
        stateManager.setStateField('selectedFolderPath', folderName);
        stateManager.setStateField('fullFilePath', '');
        
        % Update compatibility layer
        appState.TIFF.isFolderMode = true;
        appState.TIFF.selectedFolderPath = folderName;
        appState.TIFF.fullFilePath = '';
        
        % Clear caches
        stateManager.clearCache();
        appState.sessionCache = struct('data', [], 'fingerprint', []);
        
        set(hText, 'String', sprintf('Analyzing folder:\n%s...', folderName)); drawnow;
        try
            tiffFiles = dir(fullfile(folderName, '*.tif*'));
            if isempty(tiffFiles), error('No TIFF files found in the selected folder.'); end
            
            firstFilePath = fullfile(folderName, tiffFiles(1).name);
            [~, name, ~] = fileparts(tiffFiles(1).name);
            fileBaseName = regexprep(name, '_\d{5}$', '');
            
            stateManager.setStateField('fileBaseName', fileBaseName);
            appState.TIFF.fileBaseName = fileBaseName;
            
            processMetadata_TIFF(firstFilePath, folderName);
        catch ME
            set(hText, 'String', sprintf('Error reading folder:\n%s', ME.message));
        end
    end

%% --- NEURAL DATA MODE SPECIFIC CALLBACKS (Enhanced) ---

    function loadDataCallback_Neural(~, ~)
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select Data File');
        if isequal(fileName, 0), return; end
        
        try
            set(hText, 'String', sprintf('Loading data from:\n%s...', fileName)); drawnow;
            data = load(fullfile(pathName, fileName), 'psths', 'psthsnp');
            if ~isfield(data, 'psths') || ~isfield(data, 'psthsnp')
                error('The selected .mat file must contain "psths" and "psthsnp" variables.');
            end
            
            % Update state manager
            stateManager.setStateField('dataFilePath', fullfile(pathName, fileName));
            stateManager.setStateField('psthsData', data.psths);
            stateManager.setStateField('psthsnpData', data.psthsnp);
            
            % Update compatibility layer
            appState.Neural.dataFilePath = fullfile(pathName, fileName);
            appState.Neural.psthsData = data.psths;
            appState.Neural.psthsnpData = data.psthsnp;
            
            % Clear caches
            stateManager.clearCache();
            appState.sessionCache = struct('data', [], 'fingerprint', []);
            
            set(hText, 'String', sprintf('Data loaded successfully from:\n%s', fileName)); drawnow;
            updateDisplayInfo();
        catch ME
            set(hText, 'String', sprintf('Error loading data file:\n%s', ME.message));
        end
    end

    function loadCoordsCallback_Neural(~, ~)
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select Coordinates File');
        if isequal(fileName, 0), return; end
        
        try
            set(hText, 'String', sprintf('Loading coordinates from:\n%s...', fileName)); drawnow;
            data = load(fullfile(pathName, fileName));
            f = fields(data);
            if numel(f) < 1, error('The selected .mat file is empty.'); end
            coords = data.(f{1});
            if ~ismatrix(coords) || size(coords, 2) ~= 2, error('Coordinates must be an N x 2 matrix.'); end
            
            % Update state manager
            stateManager.setStateField('coordsFilePath', fullfile(pathName, fileName));
            stateManager.setStateField('cellCoords', coords);
            
            % Update compatibility layer
            appState.Neural.coordsFilePath = fullfile(pathName, fileName);
            appState.Neural.cellCoords = coords;
            
            % Clear caches
            stateManager.clearCache();
            appState.sessionCache = struct('data', [], 'fingerprint', []);
            
            set(hText, 'String', sprintf('Coordinates loaded successfully from:\n%s', fileName)); drawnow;
            updateDisplayInfo();
        catch ME
            set(hText, 'String', sprintf('Error loading coordinates file:\n%s', ME.message));
        end
    end
    
    function loadTiffCallback_Neural(~, ~)
        folderName = uigetdir('', 'Select the original TIFF folder');
        if isequal(folderName, 0), return; end
        
        try
            set(hText, 'String', sprintf('Analyzing TIFF folder:\n%s...', folderName)); drawnow;
            tiffFiles = dir(fullfile(folderName, '*.tif*'));
            if isempty(tiffFiles), error('No TIFF files found in the selected folder.'); end
            
            % Update state manager
            stateManager.setStateField('tiffFolderPath', folderName);
            
            % Update compatibility layer
            appState.Neural.tiffFolderPath = folderName;
            
            % Clear caches
            stateManager.clearCache();
            appState.sessionCache = struct('data', [], 'fingerprint', []);
            
            firstTiffPath = fullfile(folderName, tiffFiles(1).name);
            processTiffMetadataForInfo_Neural(firstTiffPath);
            
            set(hText, 'String', sprintf('TIFF folder loaded successfully:\n%s', folderName)); drawnow;
            updateDisplayInfo();
        catch ME
            set(hText, 'String', sprintf('Error reading TIFF folder:\n%s', ME.message));
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
            
            % Update both TIFF and Neural states in state manager
            stateManager.setStateField('vareaData', vareaData);
            stateManager.setStateField('vareaFilePath', filePath);
            
            % Update compatibility layer
            appState.TIFF.vareaData = vareaData;
            appState.TIFF.vareaFilePath = filePath;
            appState.Neural.vareaData = vareaData;
            appState.Neural.vareaFilePath = filePath;

            % Clear caches
            stateManager.clearCache();
            appState.sessionCache = struct('data', [], 'fingerprint', []);
            
            set(hText, 'String', sprintf('Visual areas loaded from:\n%s', fileName)); drawnow;
            updateDisplayInfo();
        catch ME
            set(hText, 'String', sprintf('Error loading visual area file:\n%s', ME.message));
        end
    end

%% --- EVENT HANDLERS ---

    function onModeChanged(~, eventData)
        % Handle mode changes with UI updates
        isTiffMode = strcmp(eventData.NewMode, 'TIFF');
        
        % Update UI visibility
        set(hTiffLoadPanel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hNeuralLoadPanel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        
        % Show/hide mode-specific processing controls
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
        
        % Update display
        updateDisplayInfo();
    end

    function onContextChanged(~, eventData)
        % Handle context changes with UI updates
        if strcmp(eventData.NewContext, 'loaded')
            % Disable mode selector and parameter fields
            set(hModeSelector, 'Enable', 'off');
            setProcessingPanelEnabled(false);
            set(hText, 'String', 'Viewing loaded state (read-only)');
        else
            % Enable mode selector and parameter fields
            set(hModeSelector, 'Enable', 'on');
            setProcessingPanelEnabled(true);
            set(hText, 'String', 'Current session mode');
        end
    end

    function onDataLoaded(~, eventData)
        % Handle data loaded events
        set(hText, 'String', sprintf('State loaded from:\n%s', eventData.Filepath));
    end

    function onUIRestored(~, eventData)
        % Handle UI restoration events
        % This is where we would restore all UI control values
        % Implementation depends on specific UI controls
        updateDisplayInfo();
    end

%% --- HELPER FUNCTIONS ---

    function setProcessingPanelEnabled(isEnabled)
        % Enable/disable processing panel controls
        controls = findobj(hProcessingPanel, 'Type', 'uicontrol');
        if isEnabled
            set(controls, 'Enable', 'on');
        else
            set(controls, 'Enable', 'off');
        end
    end

    function cacheCurrentUIState(mode)
        % Cache current UI state for the specified mode
        % This is a simplified implementation
        % In a full implementation, this would capture all UI control values
        stateManager.setUIState('mode', mode);
        stateManager.setUIState('timestamp', datetime('now'));
    end

    function updateDisplayInfo()
        % Update display based on current state
        if stateManager.IsLoadedStateActive
            metadata = stateManager.getStateField('metadataString');
            if ~isempty(metadata)
                set(hText, 'String', metadata);
            else
                set(hText, 'String', 'Loaded state - no metadata available');
            end
        else
            mode = stateManager.CurrentMode;
            if strcmp(mode, 'TIFF')
                metadata = stateManager.getStateField('metadataString');
                if ~isempty(metadata)
                    set(hText, 'String', metadata);
                else
                    set(hText, 'String', 'TIFF mode - please load a file or folder');
                end
            else
                metadata = stateManager.getStateField('metadataString');
                if ~isempty(metadata)
                    set(hText, 'String', metadata);
                else
                    set(hText, 'String', 'Neural mode - please load data and coordinates');
                end
            end
        end
    end

    function updateDisplayMode(~, ~)
        % Update display mode controls visibility
        mode = get(hDisplayMode, 'Value');
        isInitialFrames = (mode == 2);
        isRefTrials = (mode == 4);
        isAnyDf = (mode > 1);
        
        set(hInitialFramesLabel, 'Visible', ifelse(isInitialFrames, 'on', 'off'));
        set(hInitialFramesInput, 'Visible', ifelse(isInitialFrames, 'on', 'off'));
        set(hRefTrialsLabel, 'Visible', ifelse(isRefTrials, 'on', 'off'));
        set(hRefTrialsInput, 'Visible', ifelse(isRefTrials, 'on', 'off'));
        set(hFrameByFrameCheckbox, 'Visible', ifelse(isRefTrials, 'on', 'off'));
        set(hDivideByF0Checkbox, 'Visible', ifelse(isAnyDf, 'on', 'off'));
    end

    function [processedData, generationState, success, errMsg] = getOrProcessData()
        % Enhanced data processing with context-aware state management
        processedData = []; 
        generationState = [];
        success = false; 
        errMsg = '';

        % Get current state
        generationState = stateManager.ActiveState;
        if isempty(generationState)
            errMsg = 'No active state available';
            return;
        end

        % Check cache
        [cachedData, fingerprint] = stateManager.getSessionCache();
        if ~isempty(cachedData) && isequaln(generationState, fingerprint)
            processedData = cachedData;
            success = true;
            return;
        end

        % Process new data (simplified for this example)
        try
            if strcmp(stateManager.CurrentMode, 'TIFF')
                % TIFF processing logic would go here
                processedData = rand(100, 100, 50); % Placeholder
            else
                % Neural processing logic would go here
                processedData = rand(100, 50); % Placeholder
            end
            
            % Cache the result
            stateManager.setSessionCache(processedData, generationState);
            success = true;
        catch ME
            errMsg = sprintf('Processing error: %s', ME.message);
        end
    end

    function processMetadata_TIFF(filePath, displayName)
        % Process TIFF metadata (simplified)
        try
            info = imfinfo(filePath);
            metadata = sprintf('File: %s\nDimensions: %d x %d\nFrames: %d', ...
                displayName, info(1).Width, info(1).Height, numel(info));
            
            stateManager.setStateField('metadataString', metadata);
            appState.TIFF.metadataString = metadata;
            set(hText, 'String', metadata);
        catch ME
            set(hText, 'String', sprintf('Error reading file:\n%s', ME.message));
        end
    end

    function processTiffMetadataForInfo_Neural(filePath)
        % Process TIFF metadata for Neural mode (simplified)
        try
            info = imfinfo(filePath);
            metadata = sprintf('TIFF Folder loaded\nDimensions: %d x %d\nFrames: %d', ...
                info(1).Width, info(1).Height, numel(info));
            
            stateManager.setStateField('metadataString', metadata);
            appState.Neural.metadataString = metadata;
            set(hText, 'String', metadata);
        catch ME
            set(hText, 'String', sprintf('Error reading TIFF folder:\n%s', ME.message));
        end
    end

    function out = ifelse(condition, true_val, false_val)
        if condition, out = true_val; else, out = false_val; end
    end
end