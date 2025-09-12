# State Management Recommendations for NeuroView

## Summary of Current Issues

1. **Complex State Nesting**: The `appState` structure has deep nesting making updates cumbersome
2. **Manual Cache Management**: Cache invalidation is scattered throughout the code
3. **Context Switching Complexity**: The dual-context system (session vs loaded) uses guard flags and manual tracking
4. **UI State Synchronization**: Multiple UI components need manual synchronization
5. **No Central State Management**: State updates happen in many places without a clear pattern

## Immediate Improvements (Without Major Refactoring)

### 1. Create State Update Helper Functions
```matlab
% Instead of directly modifying appState everywhere
function updateTIFFState(field, value)
    global appState;
    appState.TIFF.(field) = value;
    invalidateCache();
    logStateChange('TIFF', field, value);
end

function updateNeuralState(field, value)
    global appState;
    appState.Neural.(field) = value;
    invalidateCache();
    logStateChange('Neural', field, value);
end

function invalidateCache()
    global appState;
    appState.sessionCache = struct('data', [], 'fingerprint', []);
end
```

### 2. Centralize Context Management
```matlab
function setOperatingContext(contextName)
    global appState isSwitchingContext;
    
    % Start context switch
    isSwitchingContext = true;
    
    % Save current context state
    if strcmp(contextName, 'loaded')
        appState.sessionMode = appState.currentMode;
        cacheCurrentUIState(appState.currentMode);
    end
    
    % Switch context
    appState.currentContext = contextName;
    
    % Update UI
    updateContextUI(contextName);
    
    % End context switch
    isSwitchingContext = false;
end
```

### 3. Implement State Validation
```matlab
function isValid = validateState(state)
    isValid = true;
    
    % Check mode consistency
    if ~ismember(state.currentMode, {'TIFF', 'Neural'})
        warning('Invalid mode: %s', state.currentMode);
        isValid = false;
    end
    
    % Check data consistency
    if strcmp(state.currentMode, 'Neural')
        if ~isempty(state.Neural.psthsData) && ~isempty(state.Neural.cellCoords)
            if size(state.Neural.psthsData, 1) ~= size(state.Neural.cellCoords, 1)
                warning('Neuron count mismatch');
                isValid = false;
            end
        end
    end
    
    return;
end
```

### 4. Add State Change Logging
```matlab
function logStateChange(category, field, value)
    persistent stateLog;
    if isempty(stateLog)
        stateLog = {};
    end
    
    timestamp = datestr(now, 'HH:MM:SS.FFF');
    stateLog{end+1} = sprintf('[%s] %s.%s changed', timestamp, category, field);
    
    % Keep last 100 entries
    if length(stateLog) > 100
        stateLog = stateLog(end-99:end);
    end
end
```

## Long-term Solution: Implement State Manager

### Phase 1: Create Basic State Manager
```matlab
classdef SimpleStateManager < handle
    properties (Access = private)
        state
        listeners
    end
    
    methods
        function obj = SimpleStateManager(initialState)
            obj.state = initialState;
            obj.listeners = {};
        end
        
        function value = get(obj, path)
            % Get nested value using dot notation
            % Example: stateManager.get('Neural.psthsData')
            value = eval(['obj.state.' path]);
        end
        
        function set(obj, path, value)
            % Set nested value and notify listeners
            eval(['obj.state.' path ' = value;']);
            obj.notify(path, value);
        end
        
        function subscribe(obj, callback)
            obj.listeners{end+1} = callback;
        end
        
        function notify(obj, path, value)
            for i = 1:length(obj.listeners)
                obj.listeners{i}(path, value);
            end
        end
    end
end
```

### Phase 2: Migrate Critical Paths
Start with the most problematic areas:

1. **Mode Switching**
2. **Data Loading** 
3. **Cache Management**
4. **Context Switching**

### Phase 3: Add Advanced Features
- Undo/Redo functionality
- State persistence
- Middleware for async operations
- Dev tools for debugging

## Specific Fixes for Your Current Code

### 1. Fix Mode Switch Caching Issue
```matlab
function modeSwitchCallback(src, ~)
    % Use a transaction pattern
    beginStateTransaction();
    
    try
        % Cache current state
        if ~isSwitchingContext
            cacheCurrentUIState(appState.currentMode);
        end
        
        % Update mode
        newMode = getSelectedMode(src);
        appState.currentMode = newMode;
        
        % Update UI
        updateUIForMode(newMode);
        
        % Restore state
        restoreUIStateForCurrentMode();
        
        commitStateTransaction();
    catch ME
        rollbackStateTransaction();
        rethrow(ME);
    end
end
```

### 2. Simplify Cache Management
```matlab
function [data, hit] = getCachedData(fingerprint)
    global appState;
    
    hit = false;
    data = [];
    
    if isfield(appState.sessionCache, 'fingerprint') && ...
       isequal(appState.sessionCache.fingerprint, fingerprint)
        data = appState.sessionCache.data;
        hit = true;
    end
end

function setCachedData(data, fingerprint)
    global appState;
    appState.sessionCache.data = data;
    appState.sessionCache.fingerprint = fingerprint;
end
```

### 3. Better Context Management
```matlab
function context = getCurrentContext()
    global appState;
    
    if get(hContextLoaded, 'Value') == 1
        context = struct(...
            'type', 'loaded', ...
            'data', appState.loadedStateSnapshot, ...
            'readOnly', ~appState.loadedStateSnapshot.reloadRaw ...
        );
    else
        context = struct(...
            'type', 'session', ...
            'data', appState, ...
            'readOnly', false ...
        );
    end
end
```

## Testing Strategy

### 1. Unit Tests for State Operations
```matlab
function testStateManager()
    % Test state updates
    sm = SimpleStateManager(struct('mode', 'TIFF'));
    sm.set('mode', 'Neural');
    assert(strcmp(sm.get('mode'), 'Neural'));
    
    % Test nested updates
    sm.set('Neural.dataFilePath', '/test/path');
    assert(strcmp(sm.get('Neural.dataFilePath'), '/test/path'));
    
    % Test listeners
    notified = false;
    sm.subscribe(@(p,v) notified = true);
    sm.set('mode', 'TIFF');
    assert(notified);
end
```

### 2. Integration Tests
- Test mode switching with data loaded
- Test context switching scenarios
- Test cache invalidation

## Migration Path

1. **Week 1**: Implement helper functions and logging
2. **Week 2**: Create SimpleStateManager and test
3. **Week 3**: Migrate mode switching to use StateManager
4. **Week 4**: Migrate data loading operations
5. **Week 5**: Migrate context management
6. **Week 6**: Add undo/redo and other advanced features

This approach allows you to improve state management incrementally without breaking existing functionality.