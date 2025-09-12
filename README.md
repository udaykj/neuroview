# NeuroView State Management Refactoring

## Overview
This repository contains an analysis and refactoring proposal for the NeuroView MATLAB GUI application's state management system. The original code has grown complex with multiple overlapping state structures and tight coupling between UI and data state.

## Files in this Repository

### Original Code
- `neuroView.m` - Main GUI function (partial implementation)
- `neuroView_callbacks.m` - Callback functions (partial implementation)

### Analysis Documents
- `state_management_analysis.md` - Detailed analysis of current state management issues
- `state_management_diagram.txt` - Text-based diagram of current state structure
- `neuroView_summary.md` - High-level overview of the application

### Refactored Solution
- `StateManager.m` - New centralized state management class
- `neuroView_refactored_example.m` - Example implementation using the new StateManager

## Key Problems Identified

### 1. Complex State Structure
The original code has multiple overlapping state containers:
- `appState` - Master state container
- `appState.TIFF` - TIFF-specific data
- `appState.Neural` - Neural-specific data
- `appState.uiStateCache` - UI settings cache
- `appState.sessionCache` - Processed data cache
- `appState.loadedStateSnapshot` - Loaded state from file

### 2. State Synchronization Issues
- UI state and data state can become desynchronized
- Multiple sources of truth for the same information
- Complex state validation logic scattered throughout

### 3. Context Switching Complexity
- Two operating contexts: Current Session and Loaded State
- Complex interdependencies between mode switching and context switching
- Error-prone state transitions

### 4. Memory Management
- Large data structures cached in memory without clear cleanup strategy
- Potential memory leaks with large datasets
- No clear cache invalidation strategy

## Proposed Solution

### StateManager Class
The new `StateManager` class provides:

1. **Centralized State Management**
   - Single source of truth for all application state
   - Clean interface for state operations
   - Automatic state validation

2. **Event-Driven Architecture**
   - Observer pattern for state changes
   - Decoupled UI updates
   - Better error handling

3. **Improved Context Management**
   - Clean separation between Current Session and Loaded State
   - Automatic state caching and restoration
   - Error recovery mechanisms

4. **Memory Management**
   - Clear cache invalidation
   - Optional raw data exclusion for file saves
   - Automatic cleanup of invalid states

### Key Features

#### State Operations
```matlab
% Switch modes
stateManager.switchMode('Neural');

% Load/save states
stateManager.loadState('path/to/state.mat');
stateManager.saveState('path/to/state.mat', false); % Exclude raw data

% Clear cache
stateManager.clearCache();
```

#### Event Handling
```matlab
% Listen for state changes
addlistener(stateManager, 'ModeChanged', @onModeChanged);
addlistener(stateManager, 'DataLoaded', @onDataLoaded);
```

#### State Validation
```matlab
% Check state validity
if stateManager.HasValidData
    % Proceed with data processing
end
```

## Benefits of Refactoring

### 1. Maintainability
- Centralized state logic
- Clear separation of concerns
- Easier to debug and test

### 2. Reliability
- Automatic state validation
- Better error handling
- Consistent state transitions

### 3. Performance
- Efficient caching strategy
- Memory management
- Reduced state synchronization overhead

### 4. Extensibility
- Easy to add new state fields
- Simple to implement new features
- Clean event system for UI updates

## Implementation Strategy

### Phase 1: Core StateManager
1. Implement basic StateManager class
2. Add state validation
3. Implement event system

### Phase 2: UI Integration
1. Refactor existing callbacks to use StateManager
2. Implement event handlers
3. Update UI state management

### Phase 3: Advanced Features
1. Add state persistence
2. Implement cache management
3. Add error recovery

### Phase 4: Testing and Optimization
1. Comprehensive testing
2. Performance optimization
3. Memory usage analysis

## Usage Example

```matlab
% Initialize state manager
stateManager = StateManager();

% Switch modes
stateManager.switchMode('Neural');

% Set state data
stateManager.setNeuralState('psthsData', data);
stateManager.setNeuralState('cellCoords', coords);

% Load state from file
stateManager.loadState('saved_state.mat');

% Save current state
stateManager.saveState('current_state.mat', false);

% Check state validity
if stateManager.HasValidData
    % Process data
end
```

## Conclusion

The refactored state management system provides a clean, maintainable, and reliable foundation for the NeuroView GUI. By centralizing state operations and implementing proper validation and event handling, the application becomes more robust and easier to extend.

The new architecture addresses all major issues identified in the original code while providing a clear path for future development and maintenance.