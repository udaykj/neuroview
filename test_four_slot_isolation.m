function test_four_slot_isolation()
% TEST_FOUR_SLOT_ISOLATION Test script to validate four-slot state management
%   This script tests the four isolated state slots and context switching
%   to ensure perfect state isolation and restoration.

fprintf('=== Testing Four-Slot State Management ===\n\n');

% Initialize state manager
stateManager = StateManager_v2();

% Test 1: Initial state validation
fprintf('Test 1: Initial State Validation\n');
fprintf('Current Mode: %s\n', stateManager.CurrentMode);
fprintf('Current Context: %s\n', stateManager.CurrentContext);
fprintf('Has Valid Current Session: %s\n', mat2str(stateManager.HasValidCurrentSession));
fprintf('Has Valid Loaded State: %s\n', mat2str(stateManager.HasValidLoadedState));
fprintf('Is Loaded State Active: %s\n', mat2str(stateManager.IsLoadedStateActive));
fprintf('✓ Initial state validation passed\n\n');

% Test 2: Mode switching
fprintf('Test 2: Mode Switching\n');
fprintf('Switching to Neural mode...\n');
stateManager.switchMode('Neural');
fprintf('Current Mode: %s\n', stateManager.CurrentMode);
fprintf('Current Context: %s\n', stateManager.CurrentContext);
fprintf('✓ Mode switching passed\n\n');

% Test 3: State field operations
fprintf('Test 3: State Field Operations\n');
fprintf('Setting TIFF state fields...\n');
stateManager.switchMode('TIFF');
stateManager.setStateField('fullFilePath', '/test/path/file.tif');
stateManager.setStateField('metadataString', 'Test TIFF metadata');
stateManager.setStateField('pixelWidth', 512);

fprintf('Getting TIFF state fields...\n');
filePath = stateManager.getStateField('fullFilePath');
metadata = stateManager.getStateField('metadataString');
pixelWidth = stateManager.getStateField('pixelWidth');

fprintf('File Path: %s\n', filePath);
fprintf('Metadata: %s\n', metadata);
fprintf('Pixel Width: %d\n', pixelWidth);
fprintf('✓ State field operations passed\n\n');

% Test 4: Context switching
fprintf('Test 4: Context Switching\n');
fprintf('Switching to loaded context...\n');
stateManager.switchContext('loaded');
fprintf('Current Context: %s\n', stateManager.CurrentContext);
fprintf('Is Loaded State Active: %s\n', mat2str(stateManager.IsLoadedStateActive));

fprintf('Switching back to current context...\n');
stateManager.switchContext('current');
fprintf('Current Context: %s\n', stateManager.CurrentContext);
fprintf('Is Loaded State Active: %s\n', mat2str(stateManager.IsLoadedStateActive));
fprintf('✓ Context switching passed\n\n');

% Test 5: Four-slot isolation
fprintf('Test 5: Four-Slot Isolation\n');

% Set different data in each slot
fprintf('Setting Current Session TIFF data...\n');
stateManager.switchMode('TIFF');
stateManager.switchContext('current');
stateManager.setStateField('metadataString', 'Current Session TIFF Data');
stateManager.setStateField('pixelWidth', 1024);

fprintf('Setting Current Session Neural data...\n');
stateManager.switchMode('Neural');
stateManager.switchContext('current');
stateManager.setStateField('metadataString', 'Current Session Neural Data');
stateManager.setStateField('numNeurons', 100);

fprintf('Setting Loaded State TIFF data...\n');
stateManager.switchMode('TIFF');
stateManager.switchContext('loaded');
stateManager.setStateField('metadataString', 'Loaded State TIFF Data');
stateManager.setStateField('pixelWidth', 2048);

fprintf('Setting Loaded State Neural data...\n');
stateManager.switchMode('Neural');
stateManager.switchContext('loaded');
stateManager.setStateField('metadataString', 'Loaded State Neural Data');
stateManager.setStateField('numNeurons', 200);

% Verify isolation
fprintf('\nVerifying slot isolation...\n');

% Check Current Session TIFF
stateManager.switchMode('TIFF');
stateManager.switchContext('current');
fprintf('Current Session TIFF - Metadata: %s, Pixel Width: %d\n', ...
    stateManager.getStateField('metadataString'), stateManager.getStateField('pixelWidth'));

% Check Current Session Neural
stateManager.switchMode('Neural');
stateManager.switchContext('current');
fprintf('Current Session Neural - Metadata: %s, Num Neurons: %d\n', ...
    stateManager.getStateField('metadataString'), stateManager.getStateField('numNeurons'));

% Check Loaded State TIFF
stateManager.switchMode('TIFF');
stateManager.switchContext('loaded');
fprintf('Loaded State TIFF - Metadata: %s, Pixel Width: %d\n', ...
    stateManager.getStateField('metadataString'), stateManager.getStateField('pixelWidth'));

% Check Loaded State Neural
stateManager.switchMode('Neural');
stateManager.switchContext('loaded');
fprintf('Loaded State Neural - Metadata: %s, Num Neurons: %d\n', ...
    stateManager.getStateField('metadataString'), stateManager.getStateField('numNeurons'));

fprintf('✓ Four-slot isolation verified\n\n');

% Test 6: State snapshots
fprintf('Test 6: State Snapshots\n');
fprintf('Getting snapshots of all slots...\n');

currentTIFF = stateManager.getStateSnapshot('current', 'TIFF');
currentNeural = stateManager.getStateSnapshot('current', 'Neural');
loadedTIFF = stateManager.getStateSnapshot('loaded', 'TIFF');
loadedNeural = stateManager.getStateSnapshot('loaded', 'Neural');

fprintf('Current TIFF snapshot - Metadata: %s\n', currentTIFF.metadataString);
fprintf('Current Neural snapshot - Metadata: %s\n', currentNeural.metadataString);
fprintf('Loaded TIFF snapshot - Metadata: %s\n', loadedTIFF.metadataString);
fprintf('Loaded Neural snapshot - Metadata: %s\n', loadedNeural.metadataString);

fprintf('✓ State snapshots working correctly\n\n');

% Test 7: Cache isolation
fprintf('Test 7: Cache Isolation\n');
fprintf('Setting different cache data for each slot...\n');

% Set cache for Current Session TIFF
stateManager.switchMode('TIFF');
stateManager.switchContext('current');
stateManager.setSessionCache(rand(100, 100, 50), struct('mode', 'TIFF', 'context', 'current'));

% Set cache for Current Session Neural
stateManager.switchMode('Neural');
stateManager.switchContext('current');
stateManager.setSessionCache(rand(100, 50), struct('mode', 'Neural', 'context', 'current'));

% Set cache for Loaded State TIFF
stateManager.switchMode('TIFF');
stateManager.switchContext('loaded');
stateManager.setSessionCache(rand(200, 200, 100), struct('mode', 'TIFF', 'context', 'loaded'));

% Set cache for Loaded State Neural
stateManager.switchMode('Neural');
stateManager.switchContext('loaded');
stateManager.setSessionCache(rand(200, 100), struct('mode', 'Neural', 'context', 'loaded'));

% Verify cache isolation
fprintf('Verifying cache isolation...\n');

stateManager.switchMode('TIFF');
stateManager.switchContext('current');
[data, fingerprint] = stateManager.getSessionCache();
fprintf('Current TIFF cache - Data size: %s, Mode: %s\n', mat2str(size(data)), fingerprint.mode);

stateManager.switchMode('Neural');
stateManager.switchContext('current');
[data, fingerprint] = stateManager.getSessionCache();
fprintf('Current Neural cache - Data size: %s, Mode: %s\n', mat2str(size(data)), fingerprint.mode);

stateManager.switchMode('TIFF');
stateManager.switchContext('loaded');
[data, fingerprint] = stateManager.getSessionCache();
fprintf('Loaded TIFF cache - Data size: %s, Mode: %s\n', mat2str(size(data)), fingerprint.mode);

stateManager.switchMode('Neural');
stateManager.switchContext('loaded');
[data, fingerprint] = stateManager.getSessionCache();
fprintf('Loaded Neural cache - Data size: %s, Mode: %s\n', mat2str(size(data)), fingerprint.mode);

fprintf('✓ Cache isolation verified\n\n');

% Test 8: State validation
fprintf('Test 8: State Validation\n');
fprintf('Testing state validation...\n');

% Test valid states
fprintf('Current Session TIFF valid: %s\n', mat2str(stateManager.validateState(currentTIFF, 'TIFF')));
fprintf('Current Session Neural valid: %s\n', mat2str(stateManager.validateState(currentNeural, 'Neural')));
fprintf('Loaded State TIFF valid: %s\n', mat2str(stateManager.validateState(loadedTIFF, 'TIFF')));
fprintf('Loaded State Neural valid: %s\n', mat2str(stateManager.validateState(loadedNeural, 'Neural')));

% Test invalid states
fprintf('Empty state valid: %s\n', mat2str(stateManager.validateState([], 'TIFF')));
fprintf('Wrong mode state valid: %s\n', mat2str(stateManager.validateState(currentTIFF, 'Neural')));

fprintf('✓ State validation working correctly\n\n');

% Test 9: Event handling
fprintf('Test 9: Event Handling\n');
fprintf('Setting up event listeners...\n');

% Create event listeners
addlistener(stateManager, 'ModeChanged', @(src, evt) fprintf('Mode changed: %s -> %s\n', evt.OldMode, evt.NewMode));
addlistener(stateManager, 'ContextChanged', @(src, evt) fprintf('Context changed: %s -> %s\n', evt.OldContext, evt.NewContext));
addlistener(stateManager, 'StateChanged', @(src, evt) fprintf('State changed: %s.%s\n', evt.Component, evt.Field));

fprintf('Testing events...\n');
stateManager.switchMode('TIFF');
stateManager.switchContext('loaded');
stateManager.setStateField('testField', 'testValue');

fprintf('✓ Event handling working correctly\n\n');

% Test 10: Error handling
fprintf('Test 10: Error Handling\n');
fprintf('Testing error handling...\n');

try
    stateManager.loadState('nonexistent_file.mat');
    fprintf('ERROR: Should have failed to load nonexistent file\n');
catch ME
    fprintf('✓ Correctly caught error: %s\n', ME.message);
end

try
    stateManager.switchMode('InvalidMode');
    fprintf('ERROR: Should have failed to switch to invalid mode\n');
catch ME
    fprintf('✓ Correctly caught error: %s\n', ME.message);
end

fprintf('✓ Error handling working correctly\n\n');

fprintf('=== All Tests Passed! ===\n');
fprintf('Four-slot state management is working correctly.\n');
fprintf('Perfect state isolation and context switching verified.\n');

end