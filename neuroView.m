function neuroView()
% NEUROVIEW Creates a unified GUI to visualize raw TIFF movies or pre-processed neural data.
%
%   This GUI merges the functionality of two separate tools into one. It can
%   operate in two distinct modes, selectable via a dropdown menu:
%
%   1. TIFF Viewer Mode:
%      - Loads single or multi-file TIFFs (trials).
%      - Stitches multi-ROI (mesoscope) data on the fly.
%      - Allows for dF/F calculation, temporal averaging, and spatial smoothing.
%      - ENHANCED: Now includes detrending and grid-based visualization.
%
%   2. Neural Data Viewer Mode:
%      - Loads extracted fluorescence traces ('psths') and cell coordinates.
%      - Visualizes activity as a scatter plot of cells, an interpolated grid, or as area averages.
%      - Includes processing options like neuropil correction and detrending.
%
%   Usage:
%   1. Run this function in MATLAB.
%   2. Select the desired mode ('TIFF Viewer' or 'Neural Data Viewer').
%   3. Use the appropriate 'Load' buttons for the selected mode.
%   4. Set processing parameters and click "Play Movie" or "Plot Average".
%   5. The movie player is unified with all features, including saving the
%      movie or the full application state.
%
%   This function is compatible with MATLAB R2016b and later.

% --- Main State Variables ---
% ... existing code ...

end