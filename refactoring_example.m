% Example: Refactoring the mode switch callback with better state management

% BEFORE: Complex nested logic with manual state management
function modeSwitchCallback_OLD(src, ~)
    % 1. Cache the UI state of the outgoing mode, ONLY if not in a context switch
    if ~isSwitchingContext
        cacheCurrentUIState(appState.currentMode);
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
    
    % ... many more UI updates ...
    
    % 4. Restore the cached UI state for the new mode
    restoreUIStateForCurrentMode();
    
    % 5. Invalidate Session Cache and Update Display
    appState.sessionCache = struct('data', [], 'fingerprint', []);
    updateDisplayInfo();
end

% AFTER: Clean action-based approach
function modeSwitchCallback_NEW(src, ~)
    global stateManager;
    
    % Get the new mode
    newModeIndex = get(src, 'Value');
    newMode = ifelse(newModeIndex == 1, 'TIFF', 'Neural');
    
    % Dispatch a single action - everything else is handled automatically
    stateManager.dispatch(struct(...
        'type', 'SWITCH_MODE', ...
        'payload', struct(...
            'newMode', newMode, ...
            'preserveUIState', ~isSwitchingContext ...
        )));
end

% The state manager reducer handles all the complex logic
function newState = handleModeSwitch(state, action)
    newState = state;
    
    % Save current UI state if requested
    if action.payload.preserveUIState
        newState.uiStateCache.(state.currentMode) = state.ui;
    end
    
    % Switch mode
    newState.currentMode = action.payload.newMode;
    
    % Restore UI state for new mode
    if isfield(newState.uiStateCache, action.payload.newMode)
        newState.ui = newState.uiStateCache.(action.payload.newMode);
    end
    
    % Clear cache
    newState.sessionCache = struct('data', [], 'fingerprint', []);
end

% UI updates are handled by subscribers
function updateUIForModeSwitch(state)
    isTiffMode = strcmp(state.currentMode, 'TIFF');
    
    % Update panel visibility
    set(hTiffLoadPanel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
    set(hNeuralLoadPanel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
    
    % Update mode-specific controls
    updateModeSpecificControls(state);
    
    % Update display
    updateDisplayInfo(state);
end

%% Example: Simplifying data loading with state management

% BEFORE: Manual state updates scattered throughout
function loadDataCallback_Neural_OLD(~, ~)
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
    catch ME
        set(hText, 'String', sprintf('Error loading data file:\n%s', ME.message));
        N.dataFilePath = ''; N.psthsData = []; N.psthsnpData = []; appState.Neural = N;
    end
end

% AFTER: Clean separation of concerns
function loadDataCallback_Neural_NEW(~, ~)
    global stateManager;
    
    [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select Data File');
    if isequal(fileName, 0), return; end
    
    % Dispatch loading action
    stateManager.dispatch(struct(...
        'type', 'LOAD_NEURAL_DATA_REQUEST', ...
        'payload', struct(...
            'filePath', fullfile(pathName, fileName), ...
            'fileName', fileName ...
        )));
end

% Separate data loading logic (can be tested independently)
function loadNeuralDataMiddleware(state, action)
    if strcmp(action.type, 'LOAD_NEURAL_DATA_REQUEST')
        try
            % Update UI to show loading
            updateStatus('Loading data...');
            
            % Load the data
            data = load(action.payload.filePath, 'psths', 'psthsnp');
            
            % Validate data
            validateNeuralData(data);
            
            % Dispatch success action
            stateManager.dispatch(struct(...
                'type', 'LOAD_NEURAL_DATA_SUCCESS', ...
                'payload', struct(...
                    'dataFilePath', action.payload.filePath, ...
                    'psthsData', data.psths, ...
                    'psthsnpData', data.psthsnp ...
                )));
            
        catch ME
            % Dispatch error action
            stateManager.dispatch(struct(...
                'type', 'LOAD_NEURAL_DATA_ERROR', ...
                'payload', ME.message ...
            ));
        end
    end
end

function validateNeuralData(data)
    if ~isfield(data, 'psths') || ~isfield(data, 'psthsnp')
        error('The selected .mat file must contain "psths" and "psthsnp" variables.');
    end
    if ndims(data.psths) ~= 3 || ~isequal(size(data.psths), size(data.psthsnp))
        error('Data must be 3D (N x t x R) and psths/psthsnp must be the same size.');
    end
end

%% Benefits of this approach:

% 1. Separation of Concerns
%    - UI logic separated from business logic
%    - Data loading separated from state management
%    - Validation logic is testable

% 2. Predictable State Updates
%    - All state changes go through reducer
%    - State is immutable (new copies created)
%    - Easy to track what changed and why

% 3. Better Error Handling
%    - Centralized error handling
%    - UI automatically updated on errors
%    - Can implement retry logic easily

% 4. Easier Testing
%    - Pure functions for reducers
%    - Can test state transitions independently
%    - Mock actions for testing

% 5. Better Developer Experience
%    - Clear flow of data
%    - Easier to debug (can log all actions)
%    - Can implement time-travel debugging