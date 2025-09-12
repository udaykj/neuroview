% Script to assemble the complete neuroView_v2.m file

% Read the state manager class
stateManagerCode = fileread('neuroView_v2_state_manager.m');

% Read the main file
mainCode = fileread('neuroView_v2.m');

% Read the continuation
part2Code = fileread('neuroView_v2_part2.m');

% Create the complete file
fid = fopen('neuroView_v2_complete.m', 'w');

% Write header comment
fprintf(fid, '%% neuroView_v2_complete.m\n');
fprintf(fid, '%% Complete version with 4-state architecture\n');
fprintf(fid, '%% This file includes the StateManagerV2 class and all functions\n\n');

% Write state manager class
fprintf(fid, '%% --- STATE MANAGER CLASS ---\n');
fprintf(fid, '%s\n\n', stateManagerCode);

% Write main function (remove the function declaration line)
mainLines = strsplit(mainCode, '\n');
fprintf(fid, '%% --- MAIN FUNCTION ---\n');
for i = 1:length(mainLines)
    fprintf(fid, '%s\n', mainLines{i});
end

% Add the part2 code
fprintf(fid, '\n%% --- CONTINUATION ---\n');
fprintf(fid, '%s\n', part2Code);

% Add note about remaining functions
fprintf(fid, '\n%% --- REMAINING FUNCTIONS FROM V1 ---\n');
fprintf(fid, '%% Copy all the remaining helper functions from the original neuroView.m:\n');
fprintf(fid, '%% - getProcessedData\n');
fprintf(fid, '%% - updateDisplayInfo\n');
fprintf(fid, '%% - appendToStatus\n');
fprintf(fid, '%% - updateDisplayMode\n');
fprintf(fid, '%% - setProcessingPanelEnabled\n');
fprintf(fid, '%% - launchUnifiedMoviePlayer (and all its nested functions)\n');
fprintf(fid, '%% - All TIFF processing functions\n');
fprintf(fid, '%% - All Neural processing functions\n');
fprintf(fid, '%% - All UI component builders\n');
fprintf(fid, '%% - All utility functions (ifelse, ifisfield, etc.)\n');
fprintf(fid, '\nend %% End of main function\n');

fclose(fid);

fprintf('Complete neuroView_v2 assembled in neuroView_v2_complete.m\n');
fprintf('You need to:\n');
fprintf('1. Copy all remaining functions from the original neuroView.m\n');
fprintf('2. Update any direct appState references to use stateManager\n');
fprintf('3. Test the 4-state behavior\n');