%% --- DATA CACHING & PROCESSING (with new state management) ---
    function [processedData, generationState, success, errMsg] = getOrProcessData()
        processedData = []; 
        generationState = [];
        success = false; 
        errMsg = '';

        % Get current state from state manager
        generationState = captureFullState();

        % Check against cache
        state = stateManager.getActiveState();
        if ~isempty(state.sessionCache.fingerprint) && ...
           isequaln(generationState, state.sessionCache.fingerprint)
            
            % Cache Hit
            appendToStatus('Using cached data...');
            processedData = state.sessionCache.data;
            success = true;
            
        else
            % Cache Miss
            currentMode = state.currentMode;
            if (strcmp(currentMode, 'TIFF') && isempty(state.TIFF.fullFilePath) && isempty(state.TIFF.selectedFolderPath)) || ...
               (strcmp(currentMode, 'Neural') && (isempty(state.Neural.psthsData) || isempty(state.Neural.cellCoords) || isempty(state.Neural.tiffFolderPath)))
                errMsg = 'Please load all required data for the current mode first.';
                if strcmp(currentMode, 'Neural')
                    errMsg = [errMsg sprintf('\n(Data, Coords, AND original TIFF folder are required.)')];
                end
                success = false;
                return;
            end

            set(hText, 'String', 'Processing new data...'); drawnow;
            [newData, procSuccess, procErrMsg] = getProcessedData();
            
            if procSuccess
                % Update cache in state manager
                stateManager.updateActiveState('sessionCache.data', newData);
                stateManager.updateActiveState('sessionCache.fingerprint', generationState);
                processedData = newData;
                success = true;
            else
                errMsg = procErrMsg;
                success = false;
            end
        end
    end

%% --- TIFF MODE SPECIFIC CALLBACKS (with state manager updates) ---
    function selectFileCallback_TIFF(~, ~)
        [fileName, pathName] = uigetfile({'*.tif;*.tiff', 'TIFF Files (*.tif, *.tiff)'}, 'Select a TIFF file');
        if isequal(fileName, 0), return; end
        
        fullFilePath = fullfile(pathName, fileName);
        
        % Update state through state manager
        stateManager.updateActiveState('TIFF.isFolderMode', false);
        stateManager.updateActiveState('TIFF.fullFilePath', fullFilePath);
        stateManager.updateActiveState('TIFF.selectedFolderPath', '');
        stateManager.clearCache();
        
        set(hText, 'String', sprintf('Analyzing file:\n%s...', fileName)); drawnow;
        try
            processMetadata_TIFF(fullFilePath, fileName);
        catch ME
            set(hText, 'String', sprintf('Error reading file:\n%s\n\nDetails:\n%s', fullFilePath, ME.message));
        end
    end

    function selectFolderCallback_TIFF(~, ~)
        folderName = uigetdir();
        if isequal(folderName, 0), return; end
        
        % Update state through state manager
        stateManager.updateActiveState('TIFF.isFolderMode', true);
        stateManager.updateActiveState('TIFF.selectedFolderPath', folderName);
        stateManager.updateActiveState('TIFF.fullFilePath', '');
        stateManager.clearCache();
        
        set(hText, 'String', sprintf('Analyzing folder:\n%s...', folderName)); drawnow;
        try
            tiffFiles = dir(fullfile(folderName, '*.tif*'));
            if isempty(tiffFiles), error('No TIFF files found in the selected folder.'); end
            
            firstFilePath = fullfile(folderName, tiffFiles(1).name);
            [~, name, ~] = fileparts(tiffFiles(1).name);
            fileBaseName = regexprep(name, '_\d{5}$', '');
            stateManager.updateActiveState('TIFF.fileBaseName', fileBaseName);
            
            processMetadata_TIFF(firstFilePath, folderName);
        catch ME
            set(hText, 'String', sprintf('Error reading folder:\n%s\n\nDetails:\n%s', folderName, ME.message));
        end
    end

%% --- NEURAL DATA MODE SPECIFIC CALLBACKS (with state manager updates) ---
    function loadDataCallback_Neural(~, ~)
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select Data File');
        if isequal(fileName, 0), return; end
        
        dataFilePath = fullfile(pathName, fileName);
        stateManager.updateActiveState('Neural.dataFilePath', dataFilePath);
        
        try
            set(hText, 'String', sprintf('Loading data from:\n%s...', fileName)); drawnow;
            data = load(dataFilePath, 'psths', 'psthsnp');
            if ~isfield(data, 'psths') || ~isfield(data, 'psthsnp')
                error('The selected .mat file must contain "psths" and "psthsnp" variables.');
            end
            
            if ndims(data.psths) ~= 3 || ~isequal(size(data.psths), size(data.psthsnp))
                error('Data must be 3D (N x t x R) and psths/psthsnp must be the same size.');
            end
            
            stateManager.updateActiveState('Neural.psthsData', data.psths);
            stateManager.updateActiveState('Neural.psthsnpData', data.psthsnp);
            stateManager.clearCache();
            
            set(hText, 'String', sprintf('Data loaded successfully from:\n%s', fileName)); drawnow;
            updateDisplayInfo();
        catch ME
            set(hText, 'String', sprintf('Error loading data file:\n%s', ME.message));
            stateManager.updateActiveState('Neural.dataFilePath', '');
            stateManager.updateActiveState('Neural.psthsData', []);
            stateManager.updateActiveState('Neural.psthsnpData', []);
        end
    end

    function loadCoordsCallback_Neural(~, ~)
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select Coordinates File');
        if isequal(fileName, 0), return; end
        
        coordsFilePath = fullfile(pathName, fileName);
        stateManager.updateActiveState('Neural.coordsFilePath', coordsFilePath);
        
        try
            set(hText, 'String', sprintf('Loading coordinates from:\n%s...', fileName)); drawnow;
            data = load(coordsFilePath);
            f = fields(data);
            if numel(f) < 1, error('The selected .mat file is empty.'); end
            coords = data.(f{1});
            if ~ismatrix(coords) || size(coords, 2) ~= 2, error('Coordinates must be an N x 2 matrix.'); end
            
            stateManager.updateActiveState('Neural.cellCoords', coords);
            stateManager.clearCache();
            
            set(hText, 'String', sprintf('Coordinates loaded successfully from:\n%s', fileName)); drawnow;
            updateDisplayInfo();
        catch ME
            set(hText, 'String', sprintf('Error loading coordinates file:\n%s', ME.message));
            stateManager.updateActiveState('Neural.coordsFilePath', '');
            stateManager.updateActiveState('Neural.cellCoords', []);
        end
    end
    
    function loadTiffCallback_Neural(~, ~)
        folderName = uigetdir('', 'Select the original TIFF folder');
        if isequal(folderName, 0), return; end
        
        stateManager.updateActiveState('Neural.tiffFolderPath', folderName);
        
        try
            set(hText, 'String', sprintf('Analyzing TIFF folder:\n%s...', folderName)); drawnow;
            tiffFiles = dir(fullfile(folderName, '*.tif*'));
            if isempty(tiffFiles), error('No TIFF files found in the selected folder.'); end
            
            firstTiffPath = fullfile(folderName, tiffFiles(1).name);
            processTiffMetadataForInfo_Neural(firstTiffPath);
            
            stateManager.clearCache();
            set(hText, 'String', sprintf('TIFF folder loaded successfully:\n%s', folderName)); drawnow;
            updateDisplayInfo();
        catch ME
            set(hText, 'String', sprintf('Error reading TIFF folder:\n%s', ME.message));
            stateManager.updateActiveState('Neural.tiffFolderPath', '');
        end
    end

    function loadVareaCallback(~, ~)
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select Visual Area File');
        if isequal(fileName, 0), return; end
        
        filePath = fullfile(pathName, fileName);
        try
            set(hText, 'String', sprintf('Loading visual areas from:\n%s...', fileName)); drawnow;
            data = load(filePath);
            f = fields(data);
            if numel(f) < 1, error('MAT file is empty.'); end
            vareaData = data.(f{1});
            if ~isstruct(vareaData), error('Visual area file must contain a structure of masks.'); end
            
            % Update both modes since vareas can be used by both
            stateManager.updateActiveState('TIFF.vareaData', vareaData);
            stateManager.updateActiveState('TIFF.vareaFilePath', filePath);
            stateManager.updateActiveState('Neural.vareaData', vareaData);
            stateManager.updateActiveState('Neural.vareaFilePath', filePath);
            stateManager.clearCache();
            
            set(hText, 'String', sprintf('Visual areas loaded from:\n%s', fileName)); drawnow;
            updateDisplayInfo();
        catch ME
            set(hText, 'String', sprintf('Error loading visual area file:\n%s', ME.message));
            stateManager.updateActiveState('TIFF.vareaFilePath', '');
            stateManager.updateActiveState('TIFF.vareaData', []);
            stateManager.updateActiveState('Neural.vareaFilePath', '');
            stateManager.updateActiveState('Neural.vareaData', []);
        end
    end

%% --- HELPER FUNCTIONS ---
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
        
        % Update all parameter values from state
        if isfield(state, 'ui')
            set(hRollingAvgInput, 'String', state.ui.rollingAvg);
            set(hTrialInput, 'String', state.ui.trials);
            set(hDisplayMode, 'Value', state.ui.displayMode);
            set(hInitialFramesInput, 'String', state.ui.initialFrames);
            set(hRefTrialsInput, 'String', state.ui.refTrials);
            set(hDivideByF0Checkbox, 'Value', state.ui.divideByF0);
            set(hFrameByFrameCheckbox, 'Value', state.ui.frameByFrame);
            
            if isTiffMode
                set(hPlaneDropdown, 'Value', state.ui.plane);
                set(hChannelDropdown, 'Value', state.ui.channel);
                set(hSmoothingWindowInput, 'String', state.ui.smoothingSigma);
                
                % Update plane/channel dropdowns if metadata exists
                if state.TIFF.parsedNumPlanes > 0
                    set(hPlaneDropdown, 'String', 1:state.TIFF.parsedNumPlanes);
                end
                if state.TIFF.parsedNumChannels > 0
                    set(hChannelDropdown, 'String', 1:state.TIFF.parsedNumChannels);
                end
            else
                set(hNeuropilCoeffInput, 'String', state.ui.neuropilCoeff);
                set(hDetrendCheckbox, 'Value', state.ui.detrend);
                set(hDetrendWindowInput, 'String', state.ui.detrendWindow);
                set(hForcePositiveCheckbox, 'Value', state.ui.forcePositive);
            end
        end
        
        % Update display mode visibility
        updateDisplayMode();
        
        % Update info display
        updateDisplayInfo();
    end

    function saveUIStateToActiveSlot()
        % Save current UI values to active state slot
        state = stateManager.getActiveState();
        
        stateManager.updateActiveState('ui.rollingAvg', get(hRollingAvgInput, 'String'));
        stateManager.updateActiveState('ui.trials', get(hTrialInput, 'String'));
        stateManager.updateActiveState('ui.displayMode', get(hDisplayMode, 'Value'));
        stateManager.updateActiveState('ui.initialFrames', get(hInitialFramesInput, 'String'));
        stateManager.updateActiveState('ui.refTrials', get(hRefTrialsInput, 'String'));
        stateManager.updateActiveState('ui.divideByF0', get(hDivideByF0Checkbox, 'Value'));
        stateManager.updateActiveState('ui.frameByFrame', get(hFrameByFrameCheckbox, 'Value'));
        
        if strcmp(state.currentMode, 'TIFF')
            stateManager.updateActiveState('ui.plane', get(hPlaneDropdown, 'Value'));
            stateManager.updateActiveState('ui.channel', get(hChannelDropdown, 'Value'));
            stateManager.updateActiveState('ui.smoothingSigma', get(hSmoothingWindowInput, 'String'));
        else
            stateManager.updateActiveState('ui.neuropilCoeff', get(hNeuropilCoeffInput, 'String'));
            stateManager.updateActiveState('ui.detrend', get(hDetrendCheckbox, 'Value'));
            stateManager.updateActiveState('ui.detrendWindow', get(hDetrendWindowInput, 'String'));
            stateManager.updateActiveState('ui.forcePositive', get(hForcePositiveCheckbox, 'Value'));
        end
    end

    function mode = getCurrentModeFromDropdown()
        modeIndex = get(hModeSelector, 'Value');
        mode = ifelse(modeIndex == 1, 'TIFF', 'Neural');
    end

    function state = captureFullState()
        % Get current state from state manager
        state = stateManager.getActiveState();
        
        % Add physical coordinates if in neural mode
        if strcmp(state.currentMode, 'Neural') && ~isempty(state.Neural.cellCoords)
            N = state.Neural;
            state.physicalCoords = [N.cellCoords(:,1) ./ N.x_pixels_per_um, ...
                                   N.cellCoords(:,2) ./ N.y_pixels_per_um];
        else
            state.physicalCoords = [];
        end
        
        % Ensure frameRate is set
        if strcmp(state.currentMode, 'TIFF')
            state.frameRate = state.TIFF.nativeFrameRate;
        else
            state.frameRate = state.Neural.nativeFrameRate;
        end
    end

    function processMetadata_TIFF(filePath, displayName)
        % Process TIFF metadata and update state
        info = imfinfo(filePath);
        frameRateStr = 'N/A'; numPlanes = '1'; numRois = '1'; isMesoscan = 'No'; numChannels = '1';
        physicalDimStr = 'N/A'; trueDimStr = 'N/A'; zoomFactor = 1;
        
        % [Rest of the metadata processing code remains the same]
        % ... (copy the rest of the processMetadata_TIFF function from v1)
        
        % Update state through state manager
        stateManager.updateActiveState('TIFF.metadataString', metadataString);
        set(hText, 'String', metadataString);
    end