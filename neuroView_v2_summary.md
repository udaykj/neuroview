# NeuroView v2 - 4-State Architecture Implementation

## Overview
Version 2 implements a clean 4-state architecture with complete isolation between:
1. **Current Session (TIFF)** - Active TIFF mode workspace
2. **Current Session (Neural)** - Active Neural mode workspace  
3. **Loaded State (TIFF)** - Dedicated slot for loaded TIFF states
4. **Loaded State (Neural)** - Dedicated slot for loaded Neural states

## Key Architecture Changes

### 1. StateManagerV2 Class
- Centralized state management with 4 independent state slots
- Mode-aware state loading (only accepts matching state types)
- Clean API for state updates and retrieval
- Automatic cache invalidation

### 2. Updated Callbacks

#### Mode Switching (`modeSwitchCallback`)
- In current context: Switches between Current Session (TIFF) and Current Session (Neural)
- In loaded context: Mode switching is disabled
- State manager automatically points to correct slot

#### Context Switching (`switchOperatingContextCallback`)
- Checks if loaded state exists for current mode
- Updates UI controls based on context
- Handles read-only vs editable loaded states
- Complete UI refresh from active state

#### Load State (`loadStateCallback`)
- Mode-aware loading (rejects mismatched states)
- Populates correct loaded slot based on current mode
- Automatically switches to loaded context
- Respects "reload raw data" checkbox

### 3. Data Flow

#### State Updates
All state modifications go through the state manager:
```matlab
stateManager.updateActiveState('TIFF.fullFilePath', filePath);
stateManager.updateActiveState('Neural.psthsData', data);
stateManager.clearCache();
```

#### State Retrieval
Always get current state from state manager:
```matlab
state = stateManager.getActiveState();
```

### 4. UI Synchronization

#### `refreshUIFromState()`
- Updates all UI elements from active state
- Handles mode-specific control visibility
- Restores parameter values
- Updates metadata display

#### `saveUIStateToActiveSlot()`
- Captures current UI values
- Saves to active state slot
- Preserves user changes

## Key Benefits

1. **Complete Isolation**: Each of the 4 states is completely independent
2. **Clean Context Switching**: No cross-contamination between states
3. **Mode Safety**: Can't load TIFF state while in Neural mode (and vice versa)
4. **Predictable Behavior**: Always know which state is active
5. **Easier Maintenance**: Centralized state management

## Usage Scenarios

### Scenario 1: Basic Workflow
1. Start in TIFF mode → Working in Current Session (TIFF)
2. Load data, adjust parameters → State saved to Current Session (TIFF)
3. Switch to Neural mode → Now in Current Session (Neural)
4. Load data, adjust parameters → State saved to Current Session (Neural)
5. Switch back to TIFF → Current Session (TIFF) perfectly restored

### Scenario 2: Loading States
1. In TIFF mode, load a TIFF state → Goes to Loaded State (TIFF) slot
2. View/analyze the loaded state
3. Switch to Current Session → Back to Current Session (TIFF)
4. Switch to Neural mode → Now in Current Session (Neural)
5. Load a Neural state → Goes to Loaded State (Neural) slot
6. Both loaded states remain available

### Scenario 3: Editable Loaded States
1. Load state with "reload raw data" checked
2. Parameter fields remain enabled
3. Make changes and reprocess
4. Changes affect ONLY the loaded state slot
5. Current session remains untouched

## Integration Notes

To complete the v2 implementation:

1. **Copy remaining functions from v1**:
   - All helper functions
   - Processing functions
   - UI builders
   - Movie player

2. **Update direct state references**:
   Replace `appState.X = Y` with `stateManager.updateActiveState('X', Y)`

3. **Add callbacks for parameter changes**:
   When in loaded context with raw data, save changes to loaded slot

4. **Test all workflows**:
   - Mode switching in both contexts
   - Loading states of both types
   - Parameter persistence
   - Cache behavior

## Files Created

1. `neuroView_v2_state_manager.m` - The StateManagerV2 class
2. `neuroView_v2.m` - Main GUI file with updated callbacks
3. `neuroView_v2_part2.m` - Additional functions
4. `neuroView_v2_combined.m` - All parts combined

The architecture is designed to be minimally disruptive to the working parts of the code while providing clean state management for the complex 4-state system.