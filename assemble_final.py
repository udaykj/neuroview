#!/usr/bin/env python3
"""
Assemble the complete neuroView_v2.m file from the original v1 code
"""

# Read the original v1 code
print("Reading original neuroView.m...")
with open('neuroView.m', 'r') as f:
    v1_lines = f.readlines()

# Find where the callbacks start in v1
callback_start = -1
for i, line in enumerate(v1_lines):
    if 'function loadStateCallback' in line:
        callback_start = i
        break

if callback_start == -1:
    print("ERROR: Could not find loadStateCallback in original file")
    exit(1)

print(f"Found callbacks starting at line {callback_start}")

# Read the StateManager class
with open('StateManagerV2.m', 'r') as f:
    state_manager_code = f.read()

# Read the v2 setup code
with open('neuroView_v2_part1.txt', 'r') as f:
    v2_setup = f.read()

# Create the complete file
print("Creating neuroView_v2_complete.m...")
with open('neuroView_v2_complete.m', 'w') as f:
    # Write header
    f.write("% neuroView_v2_complete.m\n")
    f.write("% Complete version with 4-state architecture\n")
    f.write("% Auto-generated from v1 code\n\n")
    
    # Write StateManager class (embedded)
    f.write("%% --- EMBEDDED STATE MANAGER CLASS ---\n")
    f.write(state_manager_code)
    f.write("\n\n")
    
    # Write main function and GUI setup
    f.write("%% --- MAIN NEUROVIEW FUNCTION ---\n")
    f.write(v2_setup)
    f.write("\n\n")
    
    # Write updated callbacks
    f.write("%% --- UPDATED CALLBACKS FOR V2 ---\n\n")
    
    # Add the key updated callbacks
    updated_callbacks = """
    function modeSwitchCallback(src, ~)
        % Get current context and mode
        isCurrentContext = get(hContextSession, 'Value') == 1;
        currentMode = stateManager.getCurrentMode();
        
        % Get new mode from dropdown
        newModeIndex = get(src, 'Value');
        newMode = ifelse(newModeIndex == 1, 'TIFF', 'Neural');
        
        % If in current context, we can switch modes freely
        if isCurrentContext
            % Update state manager to point to new current session slot
            stateManager.setActiveSlot(newMode, 'current');
            
            % Update mode in the state
            stateManager.updateActiveState('currentMode', newMode);
            
            % Refresh UI from the newly active state
            refreshUIFromState();
        else
            % In loaded context, mode switching is not allowed
            % Revert dropdown to match loaded state mode
            set(src, 'Value', ifelse(strcmp(currentMode, 'TIFF'), 1, 2));
            return;
        end
    end

    function switchOperatingContextCallback(~,~)
        isLoadedContext = get(hContextLoaded, 'Value') == 1;
        currentMode = getCurrentModeFromDropdown();
        
        if isLoadedContext
            % Switching TO loaded context
            if ~stateManager.hasLoadedState(currentMode)
                % No loaded state for this mode
                set(hContextSession, 'Value', 1);
                set(hContextLoaded, 'Value', 0);
                errordlg(sprintf('No loaded %s state available', currentMode), 'No Loaded State');
                return;
            end
            
            % Switch to loaded state slot
            stateManager.setActiveSlot(currentMode, 'loaded');
            
            % Update UI controls based on loaded state
            set(hModeSelector, 'Enable', 'off');
            
            % Check if read-only
            if stateManager.isLoadedStateReadOnly()
                setProcessingPanelEnabled(false);
                appendToStatus('Switched to Loaded State (read-only).');
            else
                setProcessingPanelEnabled(true);
                appendToStatus('Switched to Loaded State (raw data available).');
            end
        else
            % Switching BACK to current session
            stateManager.setActiveSlot(currentMode, 'current');
            
            % Re-enable controls
            set(hModeSelector, 'Enable', 'on');
            setProcessingPanelEnabled(true);
            appendToStatus('Switched back to Current Session.');
        end
        
        % Refresh UI from newly active state
        refreshUIFromState();
    end

    function refreshUIFromState()
        % Get active state and update all UI elements
        state = stateManager.getActiveState();
        
        % Update mode dropdown (without triggering callback)
        set(hModeSelector, 'Value', ifelse(strcmp(state.currentMode, 'TIFF'), 1, 2));
        
        % Update visibility of panels
        isTiffMode = strcmp(state.currentMode, 'TIFF');
        set(hTiffLoadPanel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hNeuralLoadPanel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        
        % Update mode-specific control visibility
        set(hPlaneLabel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hPlaneDropdown, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hChannelLabel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hChannelDropdown, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hSmoothingLabel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hSmoothingWindowInput, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        
        set(hNeuropilCoeffLabel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hNeuropilCoeffInput, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hDetrendCheckbox, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hDetrendWindowLabel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hDetrendWindowInput, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hForcePositiveCheckbox, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        
        % Update display mode visibility
        updateDisplayMode();
        
        % Update info display
        updateDisplayInfo();
    end

    function mode = getCurrentModeFromDropdown()
        modeIndex = get(hModeSelector, 'Value');
        mode = ifelse(modeIndex == 1, 'TIFF', 'Neural');
    end
"""
    f.write(updated_callbacks)
    f.write("\n\n")
    
    # Now copy the rest from v1 (from loadStateCallback onwards)
    f.write("%% --- FUNCTIONS FROM ORIGINAL V1 (NEEDS MANUAL STATE UPDATES) ---\n")
    f.write("%% NOTE: You need to update these functions:\n")
    f.write("%% - Replace 'appState' with 'state = stateManager.getActiveState()'\n")
    f.write("%% - Replace 'appState.X = Y' with 'stateManager.updateActiveState(\"X\", Y)'\n")
    f.write("%% - Replace 'appState.sessionCache = struct(...)' with 'stateManager.clearCache()'\n\n")
    
    # Copy all functions from v1 starting from loadStateCallback
    for i in range(callback_start, len(v1_lines)):
        f.write(v1_lines[i])

print("\nSUCCESS! Created neuroView_v2_complete.m")
print("\nIMPORTANT: The file contains all the v1 functions but they need updates:")
print("1. Search for 'appState' and replace with state management calls")
print("2. Test thoroughly with your data")
print("\nThe main architecture is ready - just needs the state reference updates!")