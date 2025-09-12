# NeuroView v2 - Four-Slot State Management Implementation Guide

## Overview

This implementation provides a complete four-slot state management system for the NeuroView GUI, ensuring perfect state isolation and seamless context switching while maintaining minimal changes to the existing working code.

## Architecture

### Four Isolated State Slots

1. **Current Session (TIFF)** - Active work with TIFF data
2. **Current Session (Neural)** - Active work with Neural data  
3. **Loaded State (TIFF)** - Dedicated slot for loaded TIFF states
4. **Loaded State (Neural)** - Dedicated slot for loaded Neural states

### Key Components

- **StateManager_v2.m** - Core state management class
- **neuroView_v2.m** - Enhanced GUI with four-slot integration
- **test_four_slot_isolation.m** - Comprehensive test suite

## Implementation Details

### StateManager_v2 Class

The `StateManager_v2` class provides:

#### Properties
```matlab
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
```

#### Key Methods

**Mode Switching**
```matlab
stateManager.switchMode('Neural'); % Switch between TIFF and Neural modes
```

**Context Switching**
```matlab
stateManager.switchContext('loaded'); % Switch to loaded state context
stateManager.switchContext('current'); % Switch back to current session
```

**State Loading (Mode-Aware)**
```matlab
stateManager.loadState('path/to/state.mat', enableRawData); % Loads into appropriate slot
```

**State Operations**
```matlab
stateManager.setStateField('metadataString', 'New metadata');
value = stateManager.getStateField('metadataString');
```

**Cache Management**
```matlab
stateManager.setSessionCache(data, fingerprint);
[data, fingerprint] = stateManager.getSessionCache();
stateManager.clearCache(); % Clear all caches
```

### neuroView_v2 Integration

The enhanced GUI maintains compatibility with the original code while adding four-slot state management:

#### Key Features

1. **Minimal Changes** - Existing GUI code remains largely unchanged
2. **Compatibility Layer** - Original `appState` structure maintained for compatibility
3. **Event-Driven Updates** - UI updates through event listeners
4. **Perfect State Restoration** - Complete UI state preservation across context switches

#### Enhanced Callbacks

**Mode Switching**
```matlab
function modeSwitchCallback(src, ~)
    newModeIndex = get(src, 'Value');
    newMode = ifelse(newModeIndex == 1, 'TIFF', 'Neural');
    stateManager.switchMode(newMode);
    appState.currentMode = newMode; % Update compatibility layer
end
```

**Context Switching**
```matlab
function switchOperatingContextCallback(~, ~)
    if get(hContextLoaded, 'Value') == 1
        stateManager.switchContext('loaded');
    else
        stateManager.switchContext('current');
    end
end
```

**State Loading (Mode-Aware)**
```matlab
function loadStateCallback(~, ~)
    [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select a saved state file');
    if isequal(fileName, 0), return; end
    
    loadPath = fullfile(pathName, fileName);
    
    % Get raw data reload setting
    isTiffMode = strcmp(stateManager.CurrentMode, 'TIFF');
    if isTiffMode
        reloadRaw = get(hReloadDataCheckbox_Tiff, 'Value');
    else
        reloadRaw = get(hReloadDataCheckbox_Neural, 'Value');
    end
    
    % Load with mode validation
    stateManager.loadState(loadPath, reloadRaw);
    
    % Enable loaded state context
    set(hContextLoaded, 'Enable', 'on', 'Value', 1);
    set(hContextSession, 'Value', 0);
end
```

## Usage Scenarios

### Scenario 1: Basic Workflow

1. **Open GUI** - Starts in TIFF mode, Current Session context
2. **Load TIFF Data** - Populates Current Session (TIFF) slot
3. **Adjust Parameters** - Changes stored in Current Session (TIFF)
4. **Switch to Neural Mode** - Switches to Current Session (Neural) slot
5. **Load Neural Data** - Populates Current Session (Neural) slot
6. **Switch Back to TIFF** - Restores Current Session (TIFF) with all previous settings

### Scenario 2: State Loading

1. **In TIFF Mode** - Click "Load State" loads into Loaded State (TIFF) slot
2. **Mode Validation** - Rejects Neural states with error message
3. **Context Switch** - Automatically switches to Loaded State context
4. **UI Updates** - Disables mode selector and parameter fields (if raw data disabled)
5. **State Restoration** - All UI elements restored to loaded state values

### Scenario 3: Context Switching

1. **Current Session** - Full editing capabilities, affects Current Session states
2. **Switch to Loaded State** - Perfect restoration of loaded state UI
3. **Parameter Changes** - Only affect Loaded State slot (if raw data enabled)
4. **Switch Back** - Perfect restoration of Current Session state

### Scenario 4: Four-Slot Isolation

1. **Current Session (TIFF)** - Independent state with its own parameters and data
2. **Current Session (Neural)** - Independent state with its own parameters and data
3. **Loaded State (TIFF)** - Independent loaded state, doesn't affect Current Session
4. **Loaded State (Neural)** - Independent loaded state, doesn't affect Current Session

## Event System

The implementation uses MATLAB's event system for decoupled UI updates:

```matlab
% Set up event listeners
addlistener(stateManager, 'ModeChanged', @onModeChanged);
addlistener(stateManager, 'ContextChanged', @onContextChanged);
addlistener(stateManager, 'DataLoaded', @onDataLoaded);
addlistener(stateManager, 'UIRestored', @onUIRestored);
```

### Event Handlers

**Mode Changed**
```matlab
function onModeChanged(~, eventData)
    isTiffMode = strcmp(eventData.NewMode, 'TIFF');
    set(hTiffLoadPanel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
    set(hNeuralLoadPanel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
    % Update mode-specific controls
    updateDisplayInfo();
end
```

**Context Changed**
```matlab
function onContextChanged(~, eventData)
    if strcmp(eventData.NewContext, 'loaded')
        set(hModeSelector, 'Enable', 'off');
        setProcessingPanelEnabled(false);
    else
        set(hModeSelector, 'Enable', 'on');
        setProcessingPanelEnabled(true);
    end
end
```

## Testing

The `test_four_slot_isolation.m` script provides comprehensive testing:

1. **Initial State Validation** - Verifies proper initialization
2. **Mode Switching** - Tests mode transitions
3. **State Field Operations** - Tests get/set operations
4. **Context Switching** - Tests context transitions
5. **Four-Slot Isolation** - Verifies complete state isolation
6. **State Snapshots** - Tests snapshot functionality
7. **Cache Isolation** - Verifies cache separation
8. **State Validation** - Tests validation logic
9. **Event Handling** - Tests event system
10. **Error Handling** - Tests error conditions

## Benefits

### 1. Perfect State Isolation
- Four completely independent state slots
- No interference between different contexts
- Clean separation of concerns

### 2. Seamless Context Switching
- Perfect UI state restoration
- Automatic mode-aware state loading
- Complete parameter preservation

### 3. Minimal Code Changes
- Existing GUI code largely unchanged
- Compatibility layer maintains original structure
- Gradual migration path

### 4. Robust Error Handling
- Mode validation for state loading
- State integrity validation
- Graceful error recovery

### 5. Event-Driven Architecture
- Decoupled UI updates
- Clean separation of state and UI logic
- Easy to extend and maintain

## Migration Path

1. **Phase 1** - Deploy `StateManager_v2.m` alongside existing code
2. **Phase 2** - Update GUI to use `neuroView_v2.m`
3. **Phase 3** - Gradually migrate existing callbacks to use state manager
4. **Phase 4** - Remove compatibility layer once migration is complete

## Conclusion

This implementation provides a robust, scalable solution for four-slot state management while maintaining compatibility with existing code. The architecture ensures perfect state isolation and seamless context switching, making the GUI much more reliable and user-friendly.

The four-slot system effectively provides four independent "virtual users" each with their own complete GUI state, with seamless switching between them while maintaining perfect isolation and state preservation.