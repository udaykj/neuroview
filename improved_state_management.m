% Proposed improved state management architecture for NeuroView

classdef StateManager < handle
    % StateManager - Centralized state management for NeuroView
    %
    % This class implements a Redux-like pattern for managing application state
    % with immutable updates, action dispatching, and subscriber notifications.
    
    properties (Access = private)
        state           % Current application state
        subscribers     % List of subscriber callbacks
        history         % State history for undo/redo
        historyIndex    % Current position in history
        maxHistory      % Maximum history entries
    end
    
    properties (Constant)
        % Action types
        SET_MODE = 'SET_MODE'
        LOAD_TIFF_DATA = 'LOAD_TIFF_DATA'
        LOAD_NEURAL_DATA = 'LOAD_NEURAL_DATA'
        UPDATE_UI_SETTING = 'UPDATE_UI_SETTING'
        CACHE_DATA = 'CACHE_DATA'
        CLEAR_CACHE = 'CLEAR_CACHE'
        SAVE_UI_STATE = 'SAVE_UI_STATE'
        RESTORE_UI_STATE = 'RESTORE_UI_STATE'
        SET_CONTEXT = 'SET_CONTEXT'
        LOAD_STATE_FROM_FILE = 'LOAD_STATE_FROM_FILE'
    end
    
    methods
        function obj = StateManager(initialState)
            % Initialize state manager with initial state
            if nargin < 1
                initialState = obj.createInitialState();
            end
            obj.state = initialState;
            obj.subscribers = {};
            obj.history = {initialState};
            obj.historyIndex = 1;
            obj.maxHistory = 50;
        end
        
        function currentState = getState(obj)
            % Get current state (returns a deep copy to prevent mutations)
            currentState = obj.deepCopy(obj.state);
        end
        
        function dispatch(obj, action)
            % Dispatch an action to update state
            oldState = obj.state;
            
            try
                % Apply reducer to get new state
                newState = obj.reducer(oldState, action);
                
                % Only update if state actually changed
                if ~isequal(oldState, newState)
                    obj.state = newState;
                    
                    % Add to history
                    obj.addToHistory(newState);
                    
                    % Notify subscribers
                    obj.notifySubscribers(action);
                end
            catch ME
                warning('StateManager:DispatchError', ...
                    'Error dispatching action %s: %s', action.type, ME.message);
            end
        end
        
        function unsubscribe = subscribe(obj, callback)
            % Subscribe to state changes
            % Returns a function that can be called to unsubscribe
            
            subscriberId = length(obj.subscribers) + 1;
            obj.subscribers{subscriberId} = callback;
            
            % Return unsubscribe function
            unsubscribe = @() obj.removeSubscriber(subscriberId);
        end
        
        function undo(obj)
            % Undo last state change
            if obj.historyIndex > 1
                obj.historyIndex = obj.historyIndex - 1;
                obj.state = obj.deepCopy(obj.history{obj.historyIndex});
                obj.notifySubscribers(struct('type', 'UNDO'));
            end
        end
        
        function redo(obj)
            % Redo previously undone state change
            if obj.historyIndex < length(obj.history)
                obj.historyIndex = obj.historyIndex + 1;
                obj.state = obj.deepCopy(obj.history{obj.historyIndex});
                obj.notifySubscribers(struct('type', 'REDO'));
            end
        end
        
    end
    
    methods (Access = private)
        function newState = reducer(obj, state, action)
            % Main reducer function - handles all state updates
            newState = obj.deepCopy(state);
            
            switch action.type
                case obj.SET_MODE
                    newState.currentMode = action.payload;
                    newState.sessionCache = struct('data', [], 'fingerprint', []);
                    
                case obj.LOAD_TIFF_DATA
                    newState.TIFF = obj.mergeTIFFData(newState.TIFF, action.payload);
                    newState.sessionCache = struct('data', [], 'fingerprint', []);
                    
                case obj.LOAD_NEURAL_DATA
                    newState.Neural = obj.mergeNeuralData(newState.Neural, action.payload);
                    newState.sessionCache = struct('data', [], 'fingerprint', []);
                    
                case obj.UPDATE_UI_SETTING
                    newState.ui.(action.payload.setting) = action.payload.value;
                    
                case obj.CACHE_DATA
                    newState.sessionCache.data = action.payload.data;
                    newState.sessionCache.fingerprint = action.payload.fingerprint;
                    
                case obj.CLEAR_CACHE
                    newState.sessionCache = struct('data', [], 'fingerprint', []);
                    
                case obj.SAVE_UI_STATE
                    mode = action.payload.mode;
                    newState.uiStateCache.(mode) = action.payload.uiState;
                    
                case obj.RESTORE_UI_STATE
                    mode = action.payload.mode;
                    if isfield(newState.uiStateCache, mode)
                        newState.ui = newState.uiStateCache.(mode);
                    end
                    
                case obj.SET_CONTEXT
                    newState.currentContext = action.payload;
                    
                case obj.LOAD_STATE_FROM_FILE
                    newState.loadedStateSnapshot = action.payload;
                    newState.sessionState = obj.deepCopy(state);
                    
                otherwise
                    warning('Unknown action type: %s', action.type);
            end
        end
        
        function mergedData = mergeTIFFData(~, currentData, newData)
            % Merge new TIFF data with existing, preserving unchanged fields
            mergedData = currentData;
            fields = fieldnames(newData);
            for i = 1:length(fields)
                mergedData.(fields{i}) = newData.(fields{i});
            end
        end
        
        function mergedData = mergeNeuralData(~, currentData, newData)
            % Merge new Neural data with existing, preserving unchanged fields
            mergedData = currentData;
            fields = fieldnames(newData);
            for i = 1:length(fields)
                mergedData.(fields{i}) = newData.(fields{i});
            end
        end
        
        function notifySubscribers(obj, action)
            % Notify all subscribers of state change
            for i = 1:length(obj.subscribers)
                if ~isempty(obj.subscribers{i})
                    try
                        obj.subscribers{i}(obj.getState(), action);
                    catch ME
                        warning('Error in subscriber callback: %s', ME.message);
                    end
                end
            end
        end
        
        function removeSubscriber(obj, subscriberId)
            % Remove a subscriber
            if subscriberId <= length(obj.subscribers)
                obj.subscribers{subscriberId} = [];
            end
        end
        
        function addToHistory(obj, state)
            % Add state to history for undo/redo
            
            % Remove any states after current index (for new branch)
            if obj.historyIndex < length(obj.history)
                obj.history = obj.history(1:obj.historyIndex);
            end
            
            % Add new state
            obj.history{end+1} = obj.deepCopy(state);
            obj.historyIndex = length(obj.history);
            
            % Limit history size
            if length(obj.history) > obj.maxHistory
                obj.history = obj.history(end-obj.maxHistory+1:end);
                obj.historyIndex = length(obj.history);
            end
        end
        
        function copy = deepCopy(~, original)
            % Create a deep copy of a structure
            % This prevents accidental mutations
            copy = evalc('disp(original)');
            copy = eval(copy);
        end
        
        function state = createInitialState(~)
            % Create the initial application state
            state = struct();
            state.currentMode = 'TIFF';
            state.currentContext = 'session';
            
            % TIFF mode data
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
            
            % Neural mode data
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
            
            % UI state
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
            state.uiStateCache = struct();
            state.sessionCache = struct('data', [], 'fingerprint', []);
            state.sessionState = [];
            state.loadedStateSnapshot = [];
            state.sessionMode = 'TIFF';
        end
    end
end

% Example usage function showing how to integrate with existing GUI
function integrateStateManager()
    % Create global state manager instance
    global stateManager;
    stateManager = StateManager();
    
    % Subscribe UI components to state changes
    stateManager.subscribe(@(state, action) updateUIFromState(state, action));
    
    % Example: Mode switch
    stateManager.dispatch(struct(...
        'type', StateManager.SET_MODE, ...
        'payload', 'Neural'));
    
    % Example: Load TIFF data
    stateManager.dispatch(struct(...
        'type', StateManager.LOAD_TIFF_DATA, ...
        'payload', struct('fullFilePath', '/path/to/file.tif')));
    
    % Example: Update UI setting
    stateManager.dispatch(struct(...
        'type', StateManager.UPDATE_UI_SETTING, ...
        'payload', struct('setting', 'rollingAvg', 'value', '5')));
end

function updateUIFromState(state, action)
    % Update UI components based on state changes
    fprintf('State updated by action: %s\n', action.type);
    % Update UI controls here based on new state
end