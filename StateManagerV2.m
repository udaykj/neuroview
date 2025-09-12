classdef StateManagerV2 < handle
    % StateManagerV2 - Manages four independent state slots for NeuroView
    % 
    % This class maintains complete isolation between:
    % 1. Current Session (TIFF)
    % 2. Current Session (Neural) 
    % 3. Loaded State (TIFF)
    % 4. Loaded State (Neural)
    
    properties (Access = private)
        states      % Container for all 4 state slots
        activeSlot  % Currently active state slot identifier
    end
    
    properties (Constant)
        % State slot identifiers
        CURRENT_TIFF = 'current_tiff'
        CURRENT_NEURAL = 'current_neural'
        LOADED_TIFF = 'loaded_tiff'
        LOADED_NEURAL = 'loaded_neural'
    end
    
    methods
        function obj = StateManagerV2()
            % Initialize all four state slots
            obj.states = struct();
            obj.states.(obj.CURRENT_TIFF) = obj.createEmptyState('TIFF');
            obj.states.(obj.CURRENT_NEURAL) = obj.createEmptyState('Neural');
            obj.states.(obj.LOADED_TIFF) = [];  % Empty until loaded
            obj.states.(obj.LOADED_NEURAL) = [];  % Empty until loaded
            obj.activeSlot = obj.CURRENT_TIFF;  % Start with TIFF mode
        end
        
        function state = getActiveState(obj)
            % Get the currently active state (deep copy)
            state = obj.states.(obj.activeSlot);
        end
        
        function setActiveSlot(obj, mode, context)
            % Determine which slot should be active based on mode and context
            if strcmp(context, 'current')
                if strcmp(mode, 'TIFF')
                    obj.activeSlot = obj.CURRENT_TIFF;
                else
                    obj.activeSlot = obj.CURRENT_NEURAL;
                end
            else % 'loaded' context
                if strcmp(mode, 'TIFF')
                    obj.activeSlot = obj.LOADED_TIFF;
                else
                    obj.activeSlot = obj.LOADED_NEURAL;
                end
            end
        end
        
        function success = loadStateIntoSlot(obj, stateData, currentMode)
            % Load a state into the appropriate loaded slot based on current mode
            success = false;
            
            % Determine state mode from loaded data
            loadedMode = obj.getStateMode(stateData);
            
            % Mode must match current mode
            if ~strcmp(loadedMode, currentMode)
                errordlg(sprintf('Cannot load %s state while in %s mode', loadedMode, currentMode), 'Mode Mismatch');
                return;
            end
            
            % Load into appropriate slot
            if strcmp(loadedMode, 'TIFF')
                obj.states.(obj.LOADED_TIFF) = stateData;
            else
                obj.states.(obj.LOADED_NEURAL) = stateData;
            end
            
            success = true;
        end
        
        function hasLoaded = hasLoadedState(obj, mode)
            % Check if a loaded state exists for the given mode
            if strcmp(mode, 'TIFF')
                hasLoaded = ~isempty(obj.states.(obj.LOADED_TIFF));
            else
                hasLoaded = ~isempty(obj.states.(obj.LOADED_NEURAL));
            end
        end
        
        function updateActiveState(obj, fieldPath, value)
            % Update a field in the active state
            % fieldPath can be like 'TIFF.fullFilePath' or 'ui.rollingAvg'
            
            % Get the active state
            state = obj.states.(obj.activeSlot);
            
            % Parse the field path and update
            parts = strsplit(fieldPath, '.');
            
            % Navigate to the parent of the field to update
            eval_str = 'state';
            for i = 1:length(parts)-1
                eval_str = [eval_str '.' parts{i}];
                % Create struct if it doesn't exist
                if ~isfield(eval(eval_str), parts{i+1})
                    eval([eval_str '.' parts{i+1} ' = [];']);
                end
            end
            
            % Set the value
            eval([eval_str '.' parts{end} ' = value;']);
            
            % Update cache invalidation if needed
            if contains(fieldPath, {'TIFF.', 'Neural.', 'ui.'})
                state.sessionCache = struct('data', [], 'fingerprint', []);
            end
            
            % Store back
            obj.states.(obj.activeSlot) = state;
        end
        
        function clearCache(obj)
            % Clear cache for active state
            state = obj.states.(obj.activeSlot);
            state.sessionCache = struct('data', [], 'fingerprint', []);
            obj.states.(obj.activeSlot) = state;
        end
        
        function mode = getCurrentMode(obj)
            % Get the mode of the currently active state
            state = obj.states.(obj.activeSlot);
            if isempty(state)
                mode = 'TIFF'; % Default
            else
                mode = state.currentMode;
            end
        end
        
        function isReadOnly = isLoadedStateReadOnly(obj)
            % Check if the current loaded state is read-only
            state = obj.states.(obj.activeSlot);
            if isfield(state, 'reloadRaw')
                isReadOnly = ~state.reloadRaw;
            else
                isReadOnly = true;
            end
        end
        
    end
    
    methods (Access = private)
        function state = createEmptyState(obj, mode)
            % Create a fresh state structure for the given mode
            state = struct();
            state.currentMode = mode;
            
            % Initialize TIFF data
            state.TIFF = struct(...
                'fullFilePath', '', ...
                'selectedFolderPath', '', ...
                'fileBaseName', '', ...
                'isFolderMode', false, ...
                'roiData', [], ...
                'metadataString', '', ...
                'dataAspectRatio', [1 1 1], ...
                'x_pixels_per_unit', 1, ...
                'y_pixels_per_unit', 1, ...
                'parsedNumPlanes', 0, ...
                'parsedNumChannels', 0, ...
                'nativeFrameRate', 30, ...
                'pixelWidth', 512, ...
                'pixelHeight', 512, ...
                'vareaData', [], ...
                'vareaFilePath', '');
            
            % Initialize Neural data
            state.Neural = struct(...
                'dataFilePath', '', ...
                'coordsFilePath', '', ...
                'tiffFolderPath', '', ...
                'vareaFilePath', '', ...
                'psthsData', [], ...
                'psthsnpData', [], ...
                'cellCoords', [], ...
                'vareaData', [], ...
                'numNeurons', 0, ...
                'numTimepoints', 0, ...
                'numTrials', 0, ...
                'metadataString', '', ...
                'nativeFrameRate', 30, ...
                'plotXLim', [0 1], ...
                'plotYLim', [0 1], ...
                'pixelWidth', 512, ...
                'pixelHeight', 512, ...
                'x_pixels_per_um', 1, ...
                'y_pixels_per_um', 1);
            
            % Initialize UI state
            state.ui = struct(...
                'rollingAvg', '1', ...
                'trials', ':', ...
                'displayMode', 1, ...
                'initialFrames', '10', ...
                'refTrials', '[]', ...
                'divideByF0', 1, ...
                'frameByFrame', 0, ...
                'plane', 1, ...
                'channel', 1, ...
                'smoothingSigma', '0', ...
                'neuropilCoeff', '0.7', ...
                'detrend', 0, ...
                'detrendWindow', '1', ...
                'forcePositive', 1);
            
            % Cache structures
            state.sessionCache = struct('data', [], 'fingerprint', []);
            state.frameRate = 30;
            
            return;
        end
        
        function mode = getStateMode(obj, stateData)
            % Determine the mode of a state
            if isfield(stateData, 'mode')
                mode = stateData.mode;
            elseif isfield(stateData, 'currentMode')
                mode = stateData.currentMode;
            else
                % Try to infer from data presence
                if isfield(stateData, 'TIFF') && ...
                   (isfield(stateData.TIFF, 'fullFilePath') && ~isempty(stateData.TIFF.fullFilePath) || ...
                    isfield(stateData.TIFF, 'selectedFolderPath') && ~isempty(stateData.TIFF.selectedFolderPath))
                    mode = 'TIFF';
                elseif isfield(stateData, 'Neural') && ...
                       isfield(stateData.Neural, 'dataFilePath') && ~isempty(stateData.Neural.dataFilePath)
                    mode = 'Neural';
                else
                    mode = 'TIFF'; % Default
                end
            end
        end
    end
end