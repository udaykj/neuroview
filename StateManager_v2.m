classdef StateManager_v2 < handle
    %STATEMANAGER_V2 Four-slot state management for NeuroView GUI
    %   Maintains four isolated state slots:
    %   - Current Session (TIFF)
    %   - Current Session (Neural) 
    %   - Loaded State (TIFF)
    %   - Loaded State (Neural)
    
    properties (Access = private)
        % Four isolated state slots
        currentSessionTIFF = struct();
        currentSessionNeural = struct();
        loadedStateTIFF = [];
        loadedStateNeural = [];
        
        % Current operating context and mode
        currentContext = 'current'; % 'current' or 'loaded'
        currentMode = 'TIFF'; % 'TIFF' or 'Neural'
        
        % UI state caches for each slot
        uiStateCache = struct('currentTIFF', struct(), 'currentNeural', struct(), ...
                             'loadedTIFF', struct(), 'loadedNeural', struct());
        
        % Session caches for processed data
        sessionCaches = struct('currentTIFF', struct('data', [], 'fingerprint', []), ...
                              'currentNeural', struct('data', [], 'fingerprint', []), ...
                              'loadedTIFF', struct('data', [], 'fingerprint', []), ...
                              'loadedNeural', struct('data', [], 'fingerprint', []));
        
        % Guard flags
        isSwitchingContext = false;
        isSwitchingMode = false;
    end
    
    properties (Dependent)
        CurrentMode
        CurrentContext
        ActiveState
        IsLoadedStateActive
        HasValidCurrentSession
        HasValidLoadedState
    end
    
    events
        StateChanged
        ModeChanged
        ContextChanged
        DataLoaded
        CacheInvalidated
        UIRestored
    end
    
    methods
        function obj = StateManager_v2()
            %STATEMANAGER_V2 Constructor
            obj.initializeDefaultStates();
        end
        
        function mode = get.CurrentMode(obj)
            mode = obj.currentMode;
        end
        
        function context = get.CurrentContext(obj)
            context = obj.currentContext;
        end
        
        function state = get.ActiveState(obj)
            % Get the currently active state based on context and mode
            if strcmp(obj.currentContext, 'current')
                if strcmp(obj.currentMode, 'TIFF')
                    state = obj.currentSessionTIFF;
                else
                    state = obj.currentSessionNeural;
                end
            else
                if strcmp(obj.currentMode, 'TIFF')
                    state = obj.loadedStateTIFF;
                else
                    state = obj.loadedStateNeural;
                end
            end
        end
        
        function isActive = get.IsLoadedStateActive(obj)
            isActive = strcmp(obj.currentContext, 'loaded');
        end
        
        function hasData = get.HasValidCurrentSession(obj)
            if strcmp(obj.currentMode, 'TIFF')
                hasData = obj.validateState(obj.currentSessionTIFF, 'TIFF');
            else
                hasData = obj.validateState(obj.currentSessionNeural, 'Neural');
            end
        end
        
        function hasData = get.HasValidLoadedState(obj)
            if strcmp(obj.currentMode, 'TIFF')
                hasData = ~isempty(obj.loadedStateTIFF) && obj.validateState(obj.loadedStateTIFF, 'TIFF');
            else
                hasData = ~isempty(obj.loadedStateNeural) && obj.validateState(obj.loadedStateNeural, 'Neural');
            end
        end
        
        function switchMode(obj, newMode)
            %SWITCHMODE Switch between TIFF and Neural modes
            if strcmp(obj.currentMode, newMode) || obj.isSwitchingMode
                return;
            end
            
            obj.isSwitchingMode = true;
            
            try
                % Cache current UI state before switching
                obj.cacheCurrentUIState();
                
                % Switch mode
                oldMode = obj.currentMode;
                obj.currentMode = newMode;
                
                % Restore UI state for new mode
                obj.restoreUIStateForCurrentMode();
                
                % Notify listeners
                notify(obj, 'ModeChanged', ModeChangedEventData(oldMode, newMode));
                notify(obj, 'StateChanged', StateChangedEventData('mode', oldMode, newMode));
                
            catch ME
                warning('Mode switch failed: %s', ME.message);
                % Revert mode on error
                obj.currentMode = oldMode;
            end
            
            obj.isSwitchingMode = false;
        end
        
        function switchContext(obj, newContext)
            %SWITCHCONTEXT Switch between Current Session and Loaded State
            if strcmp(obj.currentContext, newContext) || obj.isSwitchingContext
                return;
            end
            
            obj.isSwitchingContext = true;
            
            try
                % Cache current UI state before switching
                obj.cacheCurrentUIState();
                
                % Switch context
                oldContext = obj.currentContext;
                obj.currentContext = newContext;
                
                % Restore UI state for new context
                obj.restoreUIStateForCurrentContext();
                
                % Notify listeners
                notify(obj, 'ContextChanged', ContextChangedEventData(oldContext, newContext));
                notify(obj, 'UIRestored', UIRestoredEventData(obj.currentMode, obj.currentContext));
                
            catch ME
                warning('Context switch failed: %s', ME.message);
                % Revert context on error
                obj.currentContext = oldContext;
            end
            
            obj.isSwitchingContext = false;
        end
        
        function success = loadState(obj, filepath, enableRawData)
            %LOADSTATE Load state into appropriate slot based on current mode
            if nargin < 3
                enableRawData = false;
            end
            
            success = false;
            
            try
                loadedData = load(filepath);
                if ~isfield(loadedData, 'state')
                    error('Invalid state file: missing state field');
                end
                
                state = loadedData.state;
                stateMode = obj.getStateMode(state);
                
                % Validate mode compatibility
                if ~strcmp(stateMode, obj.currentMode)
                    error('State mode (%s) does not match current mode (%s)', stateMode, obj.currentMode);
                end
                
                % Load into appropriate slot
                if strcmp(obj.currentMode, 'TIFF')
                    obj.loadedStateTIFF = state;
                    obj.loadedStateTIFF.enableRawData = enableRawData;
                else
                    obj.loadedStateNeural = state;
                    obj.loadedStateNeural.enableRawData = enableRawData;
                end
                
                % Switch to loaded context
                obj.switchContext('loaded');
                
                success = true;
                notify(obj, 'DataLoaded', DataLoadedEventData(filepath, stateMode));
                
            catch ME
                error('Failed to load state: %s', ME.message);
            end
        end
        
        function saveState(obj, filepath, includeRawData)
            %SAVESTATE Save current active state to file
            if nargin < 3
                includeRawData = false;
            end
            
            try
                state = obj.ActiveState;
                if isempty(state)
                    error('No active state to save');
                end
                
                % Add metadata
                state.mode = obj.currentMode;
                state.context = obj.currentContext;
                state.timestamp = datetime('now');
                
                % Optionally exclude raw data
                if ~includeRawData
                    state = obj.removeRawData(state);
                end
                
                save(filepath, 'state', '-v7.3');
                
            catch ME
                error('Failed to save state: %s', ME.message);
            end
        end
        
        function clearCache(obj, slot)
            %CLEARCACHE Clear cache for specific slot or all slots
            if nargin < 2
                % Clear all caches
                obj.sessionCaches = struct('currentTIFF', struct('data', [], 'fingerprint', []), ...
                                          'currentNeural', struct('data', [], 'fingerprint', []), ...
                                          'loadedTIFF', struct('data', [], 'fingerprint', []), ...
                                          'loadedNeural', struct('data', [], 'fingerprint', []));
            else
                % Clear specific slot cache
                if isfield(obj.sessionCaches, slot)
                    obj.sessionCaches.(slot) = struct('data', [], 'fingerprint', []);
                end
            end
            
            notify(obj, 'CacheInvalidated', CacheInvalidatedEventData(slot));
        end
        
        function setStateField(obj, field, value)
            %SETSTATEFIELD Set field in currently active state
            if strcmp(obj.currentContext, 'current')
                if strcmp(obj.currentMode, 'TIFF')
                    obj.currentSessionTIFF.(field) = value;
                else
                    obj.currentSessionNeural.(field) = value;
                end
            else
                if strcmp(obj.currentMode, 'TIFF')
                    if ~isempty(obj.loadedStateTIFF)
                        obj.loadedStateTIFF.(field) = value;
                    end
                else
                    if ~isempty(obj.loadedStateNeural)
                        obj.loadedStateNeural.(field) = value;
                    end
                end
            end
            
            notify(obj, 'StateChanged', StateChangedEventData('field', field, value));
        end
        
        function value = getStateField(obj, field)
            %GETSTATEFIELD Get field from currently active state
            state = obj.ActiveState;
            if isempty(state) || ~isfield(state, field)
                value = [];
            else
                value = state.(field);
            end
        end
        
        function setUIState(obj, field, value)
            %SETUISTATE Set UI state for current context and mode
            slotName = obj.getCurrentSlotName();
            if ~isfield(obj.uiStateCache, slotName)
                obj.uiStateCache.(slotName) = struct();
            end
            obj.uiStateCache.(slotName).(field) = value;
        end
        
        function value = getUIState(obj, field)
            %GETUISTATE Get UI state for current context and mode
            slotName = obj.getCurrentSlotName();
            if isfield(obj.uiStateCache, slotName) && isfield(obj.uiStateCache.(slotName), field)
                value = obj.uiStateCache.(slotName).(field);
            else
                value = [];
            end
        end
        
        function setSessionCache(obj, data, fingerprint)
            %SETSESSIONCACHE Set session cache for current slot
            slotName = obj.getCurrentSlotName();
            obj.sessionCaches.(slotName).data = data;
            obj.sessionCaches.(slotName).fingerprint = fingerprint;
        end
        
        function [data, fingerprint] = getSessionCache(obj)
            %GETSESSIONCACHE Get session cache for current slot
            slotName = obj.getCurrentSlotName();
            data = obj.sessionCaches.(slotName).data;
            fingerprint = obj.sessionCaches.(slotName).fingerprint;
        end
        
        function isValid = validateState(obj, state, mode)
            %VALIDATESTATE Validate state integrity
            isValid = true;
            
            if isempty(state)
                isValid = false;
                return;
            end
            
            try
                % Basic validation
                if ~isstruct(state)
                    isValid = false;
                    return;
                end
                
                % Mode-specific validation
                if strcmp(mode, 'TIFF')
                    isValid = obj.validateTiffState(state);
                elseif strcmp(mode, 'Neural')
                    isValid = obj.validateNeuralState(state);
                else
                    isValid = false;
                end
                
            catch
                isValid = false;
            end
        end
        
        function clearLoadedStates(obj)
            %CLEARLOADEDSTATES Clear both loaded state slots
            obj.loadedStateTIFF = [];
            obj.loadedStateNeural = [];
        end
        
        function state = getStateSnapshot(obj, context, mode)
            %GETSTATESNAPSHOT Get state snapshot for specific context and mode
            if strcmp(context, 'current')
                if strcmp(mode, 'TIFF')
                    state = obj.currentSessionTIFF;
                else
                    state = obj.currentSessionNeural;
                end
            else
                if strcmp(mode, 'TIFF')
                    state = obj.loadedStateTIFF;
                else
                    state = obj.loadedStateNeural;
                end
            end
        end
    end
    
    methods (Access = private)
        function initializeDefaultStates(obj)
            %INITIALIZEDEFAULTSTATES Initialize default state structures
            obj.currentSessionTIFF = struct('fullFilePath','','selectedFolderPath','','fileBaseName','',...
                'isFolderMode',false,'roiData',[],'metadataString','','dataAspectRatio',[1 1 1],...
                'x_pixels_per_unit',1,'y_pixels_per_unit',1,'parsedNumPlanes',0,...
                'parsedNumChannels',0, 'nativeFrameRate', 30, 'pixelWidth', 512, 'pixelHeight', 512,...
                'vareaData',[],'vareaFilePath','');
            
            obj.currentSessionNeural = struct('dataFilePath','','coordsFilePath','','tiffFolderPath','',...
                'vareaFilePath','','psthsData',[],'psthsnpData',[],'cellCoords',[],'vareaData',[],...
                'numNeurons',0,'numTimepoints',0,'numTrials',0,'metadataString','',...
                'nativeFrameRate',30,'plotXLim',[0 1],'plotYLim',[0 1],'pixelWidth',512,...
                'pixelHeight',512,'x_pixels_per_um',1,'y_pixels_per_um',1);
        end
        
        function cacheCurrentUIState(obj)
            %CACHECURRENTUISTATE Cache current UI state
            % This will be implemented to capture UI control values
            % Implementation depends on specific UI controls
        end
        
        function restoreUIStateForCurrentMode(obj)
            %RESTOREUISTATEFORCURRENTMODE Restore UI state for current mode
            % This will be implemented to restore UI control values
            % Implementation depends on specific UI controls
        end
        
        function restoreUIStateForCurrentContext(obj)
            %RESTOREUISTATEFORCURRENTCONTEXT Restore UI state for current context
            % This will be implemented to restore UI control values
            % Implementation depends on specific UI controls
        end
        
        function slotName = getCurrentSlotName(obj)
            %GETCURRENTSLOTNAME Get current slot name for UI state caching
            if strcmp(obj.currentContext, 'current')
                slotName = sprintf('current%s', obj.currentMode);
            else
                slotName = sprintf('loaded%s', obj.currentMode);
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
        
        function state = removeRawData(obj, state)
            %REMOVERAWDATA Remove raw data from state to reduce file size
            if isfield(state, 'psthsData')
                state.psthsData = [];
            end
            if isfield(state, 'psthsnpData')
                state.psthsnpData = [];
            end
        end
        
        function isValid = validateTiffState(obj, state)
            %VALIDATETIFFSTATE Validate TIFF state integrity
            isValid = true;
            % Add specific validation logic for TIFF state
        end
        
        function isValid = validateNeuralState(obj, state)
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
        Mode
    end
    
    methods
        function obj = DataLoadedEventData(filepath, mode)
            obj.Filepath = filepath;
            obj.Mode = mode;
        end
    end
end

classdef CacheInvalidatedEventData < event.EventData
    properties
        Slot
        Timestamp
    end
    
    methods
        function obj = CacheInvalidatedEventData(slot)
            obj.Slot = slot;
            obj.Timestamp = datetime('now');
        end
    end
end

classdef UIRestoredEventData < event.EventData
    properties
        Mode
        Context
    end
    
    methods
        function obj = UIRestoredEventData(mode, context)
            obj.Mode = mode;
            obj.Context = context;
        end
    end
end