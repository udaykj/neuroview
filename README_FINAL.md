# NeuroView v2 - Complete Package

## What You Get:

### 1. Core Files (Ready to Use)
- **`StateManagerV2.m`** - The state management class (100% complete)
- **`neuroView_v2_demo.m`** - Working demo showing the 4-state system

### 2. Integration Files
- **`neuroView_v2_key_functions.m`** - Updated callback functions to copy into your v1 code

## Option 1: Quick Test (Recommended First)

1. Download both files:
   - `StateManagerV2.m`
   - `neuroView_v2_demo.m`

2. Put them in your MATLAB directory

3. Run:
   ```matlab
   neuroView_v2_demo()
   ```

4. Try these actions to see the 4-state system:
   - Switch between TIFF and Neural modes
   - Change parameters in each mode
   - Click "Simulate Load Data" 
   - Click "Load Demo State"
   - Switch between Current Session and Loaded State
   - Click "Test State Isolation" to see all 4 states

## Option 2: Full Integration

Since I need your complete v1 code for a fully automated solution, here's the manual process:

1. Copy your `neuroView.m` to `neuroView_v2.m`

2. Add at the beginning (after the function declaration):
   ```matlab
   % --- Initialize State Manager ---
   stateManager = StateManagerV2();
   ```

3. Replace these specific callbacks with the versions from `neuroView_v2_key_functions.m`:
   - `modeSwitchCallback`
   - `switchOperatingContextCallback`
   - `loadStateCallback`
   - `showInfoCallback`

4. Add the new `refreshUIFromState()` function from the key functions file

5. Throughout your code, replace:
   - `appState` → `state = stateManager.getActiveState(); state`
   - `appState.X = Y` → `stateManager.updateActiveState('X', Y)`
   - `appState.sessionCache = struct(...)` → `stateManager.clearCache()`

## Option 3: Send Me Your Complete v1 Code

If you send me your complete `neuroView.m` file, I can create a fully integrated `neuroView_v2.m` that's ready to run with no manual work required.

## Key Features of v2:

✅ Four completely independent state slots
✅ Mode-aware state loading (rejects wrong types)
✅ Clean context switching with full UI restoration  
✅ Editable loaded states (with checkbox option)
✅ No cross-contamination between states

## Files Summary:

| File | Status | Purpose |
|------|--------|---------|
| `StateManagerV2.m` | ✅ Complete | Core state management |
| `neuroView_v2_demo.m` | ✅ Complete | Working demo |
| `neuroView_v2_key_functions.m` | ✅ Complete | Functions to integrate |
| `neuroView_v2.m` | ⏳ Needs v1 code | Full integrated version |

The demo file shows exactly how the 4-state system works. Try it first to see if this is what you want!