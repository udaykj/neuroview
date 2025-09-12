%% --- TOP LEVEL CALLBACKS (Mode Switching, Loading, Actions) ---

    function modeSwitchCallback(src, ~)
        % 1. Cache the UI state of the outgoing mode, ONLY if not in a context switch
        if ~isSwitchingContext
            cacheCurrentUIState(appState.currentMode);
        end
        
        % 2. Determine the new mode
        newModeIndex = get(src, 'Value');
        if newModeIndex == 1
            appState.currentMode = 'TIFF';
        else
            appState.currentMode = 'Neural';
        end
        
        % 3. Update UI visibility based on the new mode
        isTiffMode = strcmp(appState.currentMode, 'TIFF');
        set(hTiffLoadPanel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hNeuralLoadPanel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        
        % --- Show/hide mode-specific processing controls ---
        % TIFF-specific
        set(hPlaneLabel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hPlaneDropdown, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hChannelLabel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hChannelDropdown, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hSmoothingLabel, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        set(hSmoothingWindowInput, 'Visible', ifelse(isTiffMode, 'on', 'off'));
        
        % Neural-specific
        set(hNeuropilCoeffLabel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hNeuropilCoeffInput, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hDetrendCheckbox, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hDetrendWindowLabel, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hDetrendWindowInput, 'Visible', ifelse(~isTiffMode, 'on', 'off'));
        set(hForcePositiveCheckbox, 'Visible', ifelse(~isTiffMode, 'on', 'off'));

        % 4. Restore the cached UI state for the new mode
        restoreUIStateForCurrentMode();
        
        % 5. Invalidate Session Cache and Update Display
        appState.sessionCache = struct('data', [], 'fingerprint', []);
        updateDisplayInfo();
    end

    function loadStateCallback(~,~)
        [fileName, pathName] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, 'Select a saved state file');
        if isequal(fileName, 0), return; end
        
        loadPath = fullfile(pathName, fileName);
        try
            set(hText, 'String', 'Loading state...'); drawnow;
            loadedData = load(loadPath);
            if ~isfield(loadedData, 'state'), error('Invalid state file.'); end
            
            % --- Take snapshot of current session BEFORE overwriting ---
            appState.sessionMode = appState.currentMode; % Remember the session's mode
            cacheCurrentUIState(appState.currentMode); % Save UI settings for current session
            
            state = loadedData.state;
            
            % --- Get checkbox value ---
            isTiffMode = strcmp(state.mode, 'TIFF');
            if isTiffMode, reloadRaw = get(hReloadDataCheckbox_Tiff, 'Value');
            else, reloadRaw = get(hReloadDataCheckbox_Neural, 'Value'); end
            
            state.reloadRaw = reloadRaw; % Tag the state with reload status
            appState.loadedStateSnapshot = state; % Store the entire loaded state
            
            % Activate the Loaded State context
            set(hContextLoaded, 'Enable', 'on', 'Value', 1);
            set(hContextSession, 'Value', 0);
            switchOperatingContextCallback(); % Manually trigger update

        catch ME
            set(hText, 'String', sprintf('Error loading state file:\n%s', ME.message));
        end
    end

    function showInfoCallback(~, ~)
        % This now shows info based on the current context
        isInLoadedContext = get(hContextLoaded, 'Value') == 1;
        
        if isInLoadedContext && ~isempty(appState.loadedStateSnapshot)
            stateToShow = appState.loadedStateSnapshot;
        else
            stateToShow = appState; % Use current session state
        end

        mode = getStateMode(stateToShow);

        if strcmp(mode, 'TIFF')
            if isfield(stateToShow.TIFF, 'metadataString') && ~isempty(stateToShow.TIFF.metadataString)
                set(hText, 'String', stateToShow.TIFF.metadataString);
            end
        else
            if isfield(stateToShow.Neural, 'metadataString') && ~isempty(stateToShow.Neural.metadataString)
                set(hText, 'String', stateToShow.Neural.metadataString);
            end
        end
    end

    function plotAvgCallback(~, ~)
        avgData = []; localState = []; playerStateToApply = [];
        
        isInLoadedContext = get(hContextLoaded, 'Value') == 1;

        if isInLoadedContext && ~isempty(appState.loadedStateSnapshot)
            set(hText, 'String', 'Averaging pre-loaded movie data...'); drawnow;
            
            localState = appState.loadedStateSnapshot;
            playerStateToApply = ifisfield(localState, 'playerState');
            isTiffMode = strcmp(localState.mode, 'TIFF');
            timeDim = ifelse(isTiffMode, 3, 2);
            avgData = mean(localState.movieData, timeDim);
        else
            [processedData, localState, success, errMsg] = getOrProcessData();
            if ~success, set(hText, 'String', errMsg); return; end

            appendToStatus('Averaging data...');
            if strcmp(localState.mode, 'TIFF')
                avgData = mean(processedData, 3);
            else
                avgData = mean(processedData, 2);
            end
        end

        try
            localState.avgData = avgData;
            
            figName = ifelse(strcmp(localState.mode, 'TIFF'), 'Average Stitched Image', 'Average Neuronal Activity');
            hPlotFig = figure('Name', figName, 'NumberTitle', 'off', 'Position', [600 100 600 900]);
            
            hAxes = axes('Parent', hPlotFig, 'Units', 'normalized', 'Position', [0.1 0.35 0.8 0.56]);

            vareaHandles = [];
            if ~isempty(localState.Neural.vareaData)
                vareaHandles = createVareaControls(hPlotFig, hAxes, [0.1 0.95 0.8 0.04], localState);
            end
            
            uicontrol('Parent', hPlotFig, 'Style', 'edit', 'String', figName, ...
                'Units', 'normalized', 'Position', [0.1 0.91 0.8 0.03], 'FontSize', 12, ...
                'FontWeight', 'bold', 'BackgroundColor', get(hPlotFig, 'Color'), 'HorizontalAlignment', 'center');
            
            displayHandles = createDisplayModeControls(hPlotFig, [0.1 0.16 0.8 0.05]);
            markerHandles = createMarkerControls(hPlotFig, [0.1 0.1 0.8 0.05]);
            
            modeContrasts = struct();
            p_base = prctile(localState.avgData(:), [2 98]);
            if any(isnan(p_base)) || p_base(1) >= p_base(2), p_base = [0 1]; end
            if strcmp(localState.mode, 'TIFF'), modeContrasts.Image = p_base; else, modeContrasts.Cells = p_base; end
            
            if ~isempty(localState.Neural.vareaData)
                [areaImg, ~] = createAreaAverageImage(localState.avgData, localState, true);
                p_area = prctile(areaImg(:), [2 98]); 
                if any(isnan(p_area)) || p_area(1) >= p_area(2), p_area = [0 1]; end
                modeContrasts.Areas = p_area;
            end
            
            gridSize = 30;
            if strcmp(localState.mode, 'TIFF'), [gridData, ~, ~] = binData_TIFF(localState.avgData, localState.TIFF, gridSize);
            else, [gridData, ~, ~] = binData_Neural(localState.Neural, localState.avgData, gridSize, localState.physicalCoords, false); end
            p_grid = prctile(gridData(:), [2 98]); 
            if any(isnan(p_grid)) || p_grid(1) >= p_grid(2), p_grid = [0 1]; end
            modeContrasts.Grid = p_grid;

            contrastHandles = createContrastControls(hPlotFig, hAxes, [0.1 0.01 0.8 0.09], modeContrasts, displayHandles);
            hPlotObject = []; 
            
            tiffModes = {'Image', 'Grid'}; neuralModes = {'Cells', 'Grid'};
            if ~isempty(localState.Neural.vareaData), tiffModes{end+1} = 'Areas'; neuralModes{end+1} = 'Areas'; end
            if strcmp(localState.mode, 'TIFF'), set(displayHandles.modeDropdown, 'String', tiffModes);
            else, set(displayHandles.modeDropdown, 'String', neuralModes); end
            
            if ~isempty(playerStateToApply)
                set(displayHandles.modeDropdown, 'Callback', []); % Disable callback to prevent premature trigger
                set(displayHandles.modeDropdown, 'Value', playerStateToApply.displayMode);
                set(displayHandles.gridSizeEdit, 'String', playerStateToApply.gridSize);
                set(displayHandles.interpolateCheckbox, 'Value', playerStateToApply.interpolate);
                set(markerHandles.sizeSlider, 'Value', playerStateToApply.markerSize);
                set(markerHandles.shapeDropdown, 'Value', playerStateToApply.markerShapeIndex);
            end

            set(displayHandles.modeDropdown, 'Callback', @(s,e) displayModeChanged_static());
            set(displayHandles.gridSizeEdit, 'Callback', @(s,e) displayModeChanged_static());
            set(displayHandles.interpolateCheckbox, 'Callback', @(s,e) displayModeChanged_static());
            
            displayModeChanged_static(); % This calls resetSliders
            if ~isempty(vareaHandles), vareaHandles.updateAll(); end
            
            if ~isempty(playerStateToApply)
                contrastHandles.setPlayerState(playerStateToApply);
            end

            appendToStatus('Successfully plotted average activity.');
        catch ME
            appendToStatus(sprintf('Error plotting average:\n%s\nLine: %d', ME.message, ME.stack(1).line));
        end

        function displayModeChanged_static()
            modeIdx = get(displayHandles.modeDropdown, 'Value');
            modeOptions = get(displayHandles.modeDropdown, 'String');
            selectedMode = modeOptions{modeIdx};
            isTiffMode = strcmp(localState.mode, 'TIFF');
            
            set(markerHandles.panel, 'Visible', ifelse(strcmp(selectedMode, 'Cells'), 'on', 'off'));
            set(displayHandles.gridSizeEdit, 'Visible', ifelse(strcmp(selectedMode, 'Grid'), 'on', 'off'));
            set(displayHandles.gridSizeLabel, 'Visible', ifelse(strcmp(selectedMode, 'Grid'), 'on', 'off'));
            set(displayHandles.interpolateCheckbox, 'Visible', ifelse(strcmp(selectedMode, 'Grid'), 'on', 'off'));
            
            if isgraphics(hPlotObject), delete(hPlotObject); end

            if isTiffMode
                T = localState.TIFF;
                physW = T.pixelWidth / T.x_pixels_per_unit;
                physH = T.pixelHeight / T.y_pixels_per_unit;
                if strcmp(selectedMode, 'Image')
                    hPlotObject = imagesc(hAxes, [0 physW], [0 physH], localState.avgData);
                elseif strcmp(selectedMode, 'Grid')
                    gridSize = str2double(get(displayHandles.gridSizeEdit, 'String'));
                    if isnan(gridSize) || gridSize < 1, gridSize = 30; end
                    if get(displayHandles.interpolateCheckbox, 'Value') == 1, gridData = imresize(localState.avgData, [gridSize gridSize], 'bicubic');
                    else, [gridData, ~, ~] = binData_TIFF(localState.avgData, localState.TIFF, gridSize); end
                    grid_x = linspace(0, physW, gridSize); grid_y = linspace(0, physH, gridSize);
                    hPlotObject = imagesc(hAxes, 'XData', grid_x, 'YData', grid_y, 'CData', gridData);
                elseif strcmp(selectedMode, 'Areas')
                    if isempty(vareaHandles), error('Load visual areas first.'); end
                    [areaImg, ~] = createAreaAverageImage(localState.avgData, localState, get(vareaHandles.flipYCheckbox, 'Value'));
                    hPlotObject = imagesc(hAxes, [0 physW], [0 physH], areaImg);
                end
            else % Neural Mode
                if strcmp(selectedMode, 'Cells')
                    hPlotObject = scatter(hAxes, localState.physicalCoords(:,1), localState.physicalCoords(:,2), get(markerHandles.sizeSlider, 'Value'), localState.avgData, 'filled', 'Marker', markerHandles.shapeValues{get(markerHandles.shapeDropdown, 'Value')});
                    set(markerHandles.panel, 'UserData', hPlotObject);
                elseif strcmp(selectedMode, 'Grid')
                    gridSize = str2double(get(displayHandles.gridSizeEdit, 'String'));
                    if isnan(gridSize) || gridSize < 1, gridSize = 30; end
                    [binnedFrame, x_centers, y_centers] = binData_Neural(localState.Neural, localState.avgData, gridSize, localState.physicalCoords, get(displayHandles.interpolateCheckbox, 'Value'));
                    hPlotObject = imagesc(hAxes, 'XData', x_centers, 'YData', y_centers, 'CData', binnedFrame);
                elseif strcmp(selectedMode, 'Areas')
                    if isempty(vareaHandles), error('Load visual areas first.'); end
                    [areaImg, ~] = createAreaAverageImage(localState.avgData, localState, get(vareaHandles.flipYCheckbox, 'Value'));
                    N = localState.Neural;
                    hPlotObject = imagesc(hAxes, 'XData', N.plotXLim, 'YData', N.plotYLim, 'CData', areaImg);
                end
            end
            
            setupPlotAxes(hAxes, localState.mode, localState.TIFF, localState.Neural);
            if isempty(playerStateToApply)
                contrastHandles.resetSliders(selectedMode);
            end
            if isTiffMode, set(hAxes, 'YDir', 'normal'); end
            if ~isempty(vareaHandles), vareaHandles.updateAll(); end
            contrastHandles.reapplyColormap();
        end
    end

    function playMovieCallback(~, ~)
        precomputedMovie = [];
        playerStateToApply = [];
        generationState = [];
        
        isInLoadedContext = get(hContextLoaded, 'Value') == 1;

        if isInLoadedContext && ~isempty(appState.loadedStateSnapshot)
            generationState = appState.loadedStateSnapshot;
            precomputedMovie = generationState.movieData;
            playerStateToApply = ifisfield(generationState, 'playerState');
            set(hText, 'String', 'Playing pre-computed movie from loaded state...'); drawnow;
        else
            [processedData, generationState, success, errMsg] = getOrProcessData();
            if ~success, set(hText, 'String', errMsg); return; end
            
            rollingAvg = round(str2double(get(hRollingAvgInput, 'String')));
            if isnan(rollingAvg) || rollingAvg < 1, set(hText, 'String', 'Invalid Rolling Average.'); return; end
            
            appendToStatus(sprintf('Applying rolling average of %d...', rollingAvg));
            
            if strcmp(generationState.mode, 'TIFF')
                precomputedMovie = movmean(processedData, rollingAvg, 3, 'Endpoints', 'shrink');
            else % Neural
                precomputedMovie = movmean(processedData, rollingAvg, 2, 'Endpoints', 'shrink');
            end
        end

        launchUnifiedMoviePlayer(precomputedMovie, playerStateToApply, generationState);
    end