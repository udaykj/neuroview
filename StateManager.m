classdef StateManager < handle
    %STATEMANAGER Centralized state management for NeuroView GUI
    %   This class provides a clean interface for managing application state,
    %   including mode switching, context management, and data caching.
    
    properties (Access = private)
        currentMode = 'TIFF';
        tiffState = struct();
        neuralState = struct();
        uiStateCache = struct();
        sessionCache = struct('data', [], 'fingerprint', []);
        loadedStateSnapshot = [];
        sessionMode = 'TIFF';
        isSwitchingContext = false;
    end
    
    properties (Dependent)
        CurrentMode
        IsLoadedStateActive
        HasValidData
    end
    
    events
        StateChanged
        ModeChanged
        ContextChanged
        DataLoaded
        CacheInvalidated
    end
    
    methods
        function obj = StateManager()
            %STATEMANAGER Constructor
            obj.initializeDefaultStates();
        end
        
        function mode = get.CurrentMode(obj)
            mode = obj.currentMode;
        end
        
        function isActive = get.IsLoadedStateActive(obj)
            isActive = ~isempty(obj.loadedStateSnapshot);
        end
        
        function hasData = get.HasValidData(obj)
            hasData = obj.validateCurrentState();
        end
        
        function switchMode(obj, newMode)
            %SWITCHMODE Switch between TIFF and Neural modes
            if strcmp(obj.currentMode, newMode)
                return;
            end
            
            % Cache current UI state
            obj.cacheCurrentUIState();
            
            % Switch mode
            oldMode = obj.currentMode;
            obj.currentMode = newMode;
            
            % Notify listeners
            notify(obj, 'ModeChanged', ModeChangedEventData(oldMode, newMode));
            notify(obj, 'StateChanged', StateChangedEventData('mode', oldMode, newMode));
        end
        
        function switchContext(obj, context)
            %SWITCHCONTEXT Switch between Current Session and Loaded State
            obj.isSwitchingContext = true;
            
            try
                if strcmp(context, 'loaded') && ~isempty(obj.loadedStateSnapshot)
                    % Switch to loaded state
                    obj.currentMode = obj.getStateMode(obj.loadedStateSnapshot);
                    obj.updateGUIFromState(obj.loadedStateSnapshot);
                    notify(obj, 'ContextChanged', ContextChangedEventData('current', 'loaded'));
                elseif strcmp(context, 'current')
                    % Switch back to current session
                    obj.currentMode = obj.sessionMode;
                    obj.restoreUIStateForCurrentMode();
                    notify(obj, 'ContextChanged', ContextChangedEventData('loaded', 'current'));
                end
            catch ME
                warning('Context switch failed: %s', ME.message);
            end
            
            obj.isSwitchingContext = false;
        end
        
        function loadState(obj, filepath)
            %LOADSTATE Load state from file
            try
                loadedData = load(filepath);
                if ~isfield(loadedData, 'state')
                    error('Invalid state file: missing state field');
                end
                
                % Cache current session before loading
                obj.sessionMode = obj.currentMode;
                obj.cacheCurrentUIState();
                
                % Load new state
                obj.loadedStateSnapshot = loadedData.state;
                
                % Switch to loaded context
                obj.switchContext('loaded');
                
                notify(obj, 'DataLoaded', DataLoadedEventData(filepath));
                
            catch ME
                error('Failed to load state: %s', ME.message);
            end
        end
        
        function saveState(obj, filepath, includeRawData)
            %SAVESTATE Save current state to file
            if nargin < 3
                includeRawData = false;
            end
            
            try
                state = obj.captureFullState();
                
                % Optionally exclude raw data to reduce file size
                if ~includeRawData
                    state = obj.removeRawData(state);
                end
                
                save(filepath, 'state', '-v7.3');
                
            catch ME
                error('Failed to save state: %s', ME.message);
            end
        end
        
        function clearCache(obj)
            %CLEARCACHE Clear all cached data
            obj.sessionCache = struct('data', [], 'fingerprint', []);
            obj.uiStateCache = struct();
            notify(obj, 'CacheInvalidated', CacheInvalidatedEventData());
        end
        
        function isValid = validateCurrentState(obj)
            %VALIDATECURRENTSTATE Validate current state integrity
            isValid = true;
            
            try
                % Check mode consistency
                if ~ismember(obj.currentMode, {'TIFF', 'Neural'})
                    isValid = false;
                    return;
                end
                
                % Check data consistency based on mode
                if strcmp(obj.currentMode, 'TIFF')
                    isValid = obj.validateTiffState();
                else
                    isValid = obj.validateNeuralState();
                end
                
            catch
                isValid = false;
            end
        end
        
        function state = getCurrentState(obj)
            %GETCURRENTSTATE Get current state snapshot
            state = obj.captureFullState();
        end
        
        function setTiffState(obj, field, value)
            %SETTIFFSTATE Set TIFF state field
            obj.tiffState.(field) = value;
            notify(obj, 'StateChanged', StateChangedEventData('tiff', field, value));
        end
        
        function value = getTiffState(obj, field)
            %GETTIFFSTATE Get TIFF state field
            if isfield(obj.tiffState, field)
                value = obj.tiffState.(field);
            else
                value = [];
            end
        end
        
        function setNeuralState(obj, field, value)
            %SETNEURALSTATE Set Neural state field
            obj.neuralState.(field) = value;
            notify(obj, 'StateChanged', StateChangedEventData('neural', field, value));
        end
        
        function value = getNeuralState(obj, field)
            %GETNEURALSTATE Get Neural state field
            if isfield(obj.neuralState, field)
                value = obj.neuralState.(field);
            else
                value = [];
            end
        end
        
        function setUIState(obj, mode, field, value)
            %SETUISTATE Set UI state for specific mode
            if ~isfield(obj.uiStateCache, mode)
                obj.uiStateCache.(mode) = struct();
            end
            obj.uiStateCache.(mode).(field) = value;
        end
        
        function value = getUIState(obj, mode, field)
            %GETUISTATE Get UI state for specific mode
            if isfield(obj.uiStateCache, mode) && isfield(obj.uiStateCache.(mode), field)
                value = obj.uiStateCache.(mode).(field);
            else
                value = [];
            end
        end
        
        function setSessionCache(obj, data, fingerprint)
            %SETSESSIONCACHE Set session cache data
            obj.sessionCache.data = data;
            obj.sessionCache.fingerprint = fingerprint;
        end
        
        function [data, fingerprint] = getSessionCache(obj)
            %GETSESSIONCACHE Get session cache data
            data = obj.sessionCache.data;
            fingerprint = obj.sessionCache.fingerprint;
        end
        
        function clearLoadedState(obj)
            %CLEARLOADEDSTATE Clear loaded state snapshot
            obj.loadedStateSnapshot = [];
        end
    end
    
    methods (Access = private)
        function initializeDefaultStates(obj)
            %INITIALIZEDEFAULTSTATES Initialize default state structures
            obj.tiffState = struct('fullFilePath','','selectedFolderPath','','fileBaseName','',...
                'isFolderMode',false,'roiData',[],'metadataString','','dataAspectRatio',[1 1 1],...
                'x_pixels_per_unit',1,'y_pixels_per_unit',1,'parsedNumPlanes',0,...
                'parsedNumChannels',0, 'nativeFrameRate', 30, 'pixelWidth', 512, 'pixelHeight', 512,...
                'vareaData',[],'vareaFilePath','');
            
            obj.neuralState = struct('dataFilePath','','coordsFilePath','','tiffFolderPath','',...
                'vareaFilePath','','psthsData',[],'psthsnpData',[],'cellCoords',[],'vareaData',[],...
                'numNeurons',0,'numTimepoints',0,'numTrials',0,'metadataString','',...
                'nativeFrameRate',30,'plotXLim',[0 1],'plotYLim',[0 1],'pixelWidth',512,...
                'pixelHeight',512,'x_pixels_per_um',1,'y_pixels_per_um',1);
        end
        
        function cacheCurrentUIState(obj)
            %CACHECURRENTUISTATE Cache current UI state
            % This would be implemented to capture UI control values
            % Implementation depends on specific UI controls
        end
        
        function restoreUIStateForCurrentMode(obj)
            %RESTOREUISTATEFORCURRENTMODE Restore UI state for current mode
            % This would be implemented to restore UI control values
            % Implementation depends on specific UI controls
        end
        
        function updateGUIFromState(obj, state)
            %UPDATEGUIFROMSTATE Update GUI from state object
            % This would be implemented to update UI controls
            % Implementation depends on specific UI controls
        end
        
        function state = captureFullState(obj)
            %CAPTUREFULLSTATE Capture complete state snapshot
            state = struct();
            state.mode = obj.currentMode;
            state.TIFF = obj.tiffState;
            state.Neural = obj.neuralState;
            state.ui = obj.uiStateCache;
            state.timestamp = datetime('now');
        end
        
        function state = removeRawData(obj, state)
            %REMOVERAWDATA Remove raw data from state to reduce file size
            if isfield(state, 'Neural')
                state.Neural.psthsData = [];
                state.Neural.psthsnpData = [];
            end
        end
        
        function mode = getStateMode(obj, state)
            %GETSTATEMODE Get mode from state object
            if isfield(state, 'mode') && ~isempty(state.mode)
                mode = state.mode;
            elseif isfield(state, 'currentMode') && ~isempty(state.currentMode)
                mode = state.currentMode;
            else
                mode = 'TIFF'; % Fallback
            end
        end
        
        function isValid = validateTiffState(obj)
            %VALIDATETIFFSTATE Validate TIFF state integrity
            isValid = true;
            % Add specific validation logic for TIFF state
        end
        
        function isValid = validateNeuralState(obj)
            %VALIDATENEURALSTATE Validate Neural state integrity
            isValid = true;
            % Add specific validation logic for Neural state
        end
    end
end

% Event Data Classes
classdef StateChangedEventData < event.EventData
    properties
        Component
        Field
        OldValue
        NewValue
    end
    
    methods
        function obj = StateChangedEventData(component, field, newValue)
            obj.Component = component;
            obj.Field = field;
            obj.NewValue = newValue;
        end
    end
end

classdef ModeChangedEventData < event.EventData
    properties
        OldMode
        NewMode
    end
    
    methods
        function obj = ModeChangedEventData(oldMode, newMode)
            obj.OldMode = oldMode;
            obj.NewMode = newMode;
        end
    end
end

classdef ContextChangedEventData < event.EventData
    properties
        OldContext
        NewContext
    end
    
    methods
        function obj = ContextChangedEventData(oldContext, newContext)
            obj.OldContext = oldContext;
            obj.NewContext = newContext;
        end
    end
end

classdef DataLoadedEventData < event.EventData
    properties
        Filepath
    end
    
    methods
        function obj = DataLoadedEventData(filepath)
            obj.Filepath = filepath;
        end
    end
end

classdef CacheInvalidatedEventData < event.EventData
    properties
        Timestamp
    end
    
    methods
        function obj = CacheInvalidatedEventData()
            obj.Timestamp = datetime('now');
        end
    end
end