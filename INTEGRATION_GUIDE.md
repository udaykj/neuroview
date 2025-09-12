# NeuroView v2 Integration Guide

## Quick Start

### Files You Need:
1. **StateManagerV2.m** - The new state management class (ready to use)
2. **neuroView_v2_key_functions.m** - Updated functions to copy into your code
3. Your original **neuroView.m** file

### Step-by-Step Integration:

#### Step 1: Setup
1. Copy `StateManagerV2.m` to your MATLAB directory
2. Make a copy of your `neuroView.m` and name it `neuroView_v2.m`

#### Step 2: Add State Manager
At the very beginning of your `neuroView_v2` function (after the comments), add:
```matlab
% --- Initialize State Manager ---
stateManager = StateManagerV2();
```

#### Step 3: Replace Key Functions
Copy the following functions from `neuroView_v2_key_functions.m` to replace the ones in your v2 file:
- `modeSwitchCallback`
- `switchOperatingContextCallback` 
- `loadStateCallback`
- `showInfoCallback`
- `selectFileCallback_TIFF` (as an example for other callbacks)
- Add the new `refreshUIFromState` function
- Add the new `getCurrentModeFromDropdown` helper
- Update `captureFullState`

#### Step 4: Update Data Loading Callbacks
For each data loading callback, follow this pattern:

**OLD:**
```matlab
N = appState.Neural;
N.dataFilePath = fullfile(pathName, fileName);
% ... load data ...
appState.Neural = N;
appState.sessionCache = struct('data', [], 'fingerprint', []);
```

**NEW:**
```matlab
stateManager.updateActiveState('Neural.dataFilePath', fullfile(pathName, fileName));
% ... load data ...
stateManager.updateActiveState('Neural.psthsData', data.psths);
stateManager.clearCache();
```

#### Step 5: Update State Reads
Throughout the code, replace direct state reads:

**OLD:**
```matlab
if strcmp(appState.currentMode, 'TIFF')
    T = appState.TIFF;
```

**NEW:**
```matlab
state = stateManager.getActiveState();
if strcmp(state.currentMode, 'TIFF')
    T = state.TIFF;
```

#### Step 6: Remove Old State Variables
Delete these lines from your code:
- `isSwitchingContext = false;`
- `appState = struct();`
- All the initialization of `appState.TIFF`, `appState.Neural`, etc.
- `appState.uiStateCache = struct();`
- `appState.sessionCache = struct();`
- etc.

#### Step 7: Update the initialization
At the end of the GUI setup (before the nested functions), replace:
```matlab
cacheCurrentUIState(appState.currentMode);
updateDisplayMode();
```

With:
```matlab
updateDisplayMode();
refreshUIFromState();
```

## Testing Your Integration

### Test 1: Basic Mode Switching
1. Start the GUI
2. Switch between TIFF and Neural modes
3. Verify UI updates correctly

### Test 2: State Persistence
1. Load data in TIFF mode
2. Change parameters
3. Switch to Neural mode
4. Switch back to TIFF
5. Verify your data and parameters are preserved

### Test 3: State Loading
1. In TIFF mode, load a TIFF state file
2. Verify it switches to loaded context
3. Try to load a Neural state file (should be rejected)
4. Switch to current session
5. Switch to Neural mode
6. Load a Neural state file

### Test 4: Raw Data Reload
1. Load a state with "reload raw data" checked
2. Verify parameter fields remain enabled
3. Make changes and reprocess
4. Switch to current session
5. Verify current session is unchanged

## Common Issues and Solutions

### Issue: "Undefined variable stateManager"
**Solution:** Make sure you added `stateManager = StateManagerV2();` at the beginning

### Issue: Mode switching doesn't work
**Solution:** Check that you replaced `modeSwitchCallback` with the new version

### Issue: State not persisting
**Solution:** Ensure all data updates use `stateManager.updateActiveState()`

### Issue: UI not updating
**Solution:** Add `refreshUIFromState()` call after state changes

## Quick Reference

### State Manager Methods:
- `stateManager.getActiveState()` - Get current state
- `stateManager.updateActiveState(path, value)` - Update a value
- `stateManager.clearCache()` - Clear the cache
- `stateManager.setActiveSlot(mode, context)` - Switch active slot
- `stateManager.hasLoadedState(mode)` - Check if loaded state exists
- `stateManager.loadStateIntoSlot(state, mode)` - Load a state

### Common Replacements:
| OLD | NEW |
|-----|-----|
| `appState.X = Y` | `stateManager.updateActiveState('X', Y)` |
| `value = appState.X` | `state = stateManager.getActiveState(); value = state.X` |
| `appState.sessionCache = struct(...)` | `stateManager.clearCache()` |

That's it! Your v2 should now have the clean 4-state architecture.