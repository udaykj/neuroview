# NeuroView GUI - State Management Analysis

## Overview
This is a MATLAB GUI application for visualizing neural data with two main modes:
1. **TIFF Viewer Mode**: Loads and processes raw TIFF movies with stitching capabilities
2. **Neural Data Viewer Mode**: Visualizes pre-processed neural activity data

## Key State Management Components

### Main State Structure (`appState`)
- `currentMode`: 'TIFF' or 'Neural' 
- `TIFF`: TIFF-specific data (file paths, ROI data, metadata)
- `Neural`: Neural data (psths, coordinates, visual areas)
- `uiStateCache`: Caches UI settings when switching modes
- `sessionCache`: Caches processed data to avoid recomputation
- `loadedStateSnapshot`: Stores loaded state from file
- `sessionMode`: Remembers original mode when viewing loaded state

### Context Switching
- **Current Session**: Working with live data
- **Loaded State**: Viewing pre-saved state (read-only or with raw data)

### Key Features
- Unified movie player with multiple display modes
- Visual area overlays
- Contrast and colormap controls
- State saving/loading functionality
- Data caching for performance

## State Management Challenges
The code shows complex state management with multiple contexts and caching layers that could benefit from refactoring.