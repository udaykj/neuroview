% MATLAB script to create a state management flow diagram

figure('Name', 'NeuroView State Management Flow', 'Position', [100 100 1200 800]);

% Create main components
annotation('textbox', [0.4 0.9 0.2 0.05], 'String', 'NeuroView State Management', ...
    'FontSize', 16, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
    'EdgeColor', 'none');

% Main state container
annotation('rectangle', [0.4 0.7 0.2 0.15], 'LineWidth', 2, 'Color', 'blue');
annotation('textbox', [0.4 0.78 0.2 0.05], 'String', 'appState', ...
    'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
    'EdgeColor', 'none');

% Mode branches
annotation('rectangle', [0.1 0.5 0.15 0.12], 'LineWidth', 1.5, 'Color', 'green');
annotation('textbox', [0.1 0.56 0.15 0.04], 'String', 'TIFF Mode', ...
    'FontSize', 11, 'HorizontalAlignment', 'center', 'EdgeColor', 'none');

annotation('rectangle', [0.75 0.5 0.15 0.12], 'LineWidth', 1.5, 'Color', 'green');
annotation('textbox', [0.75 0.56 0.15 0.04], 'String', 'Neural Mode', ...
    'FontSize', 11, 'HorizontalAlignment', 'center', 'EdgeColor', 'none');

% Context switcher
annotation('rectangle', [0.4 0.45 0.2 0.1], 'LineWidth', 1.5, 'Color', 'red');
annotation('textbox', [0.4 0.48 0.2 0.04], 'String', 'Context Switcher', ...
    'FontSize', 11, 'HorizontalAlignment', 'center', 'EdgeColor', 'none');

% UI State Caches
annotation('rectangle', [0.05 0.3 0.12 0.08], 'LineWidth', 1, 'Color', [0.5 0.5 0.5]);
annotation('textbox', [0.05 0.32 0.12 0.04], 'String', 'TIFF UI Cache', ...
    'FontSize', 10, 'HorizontalAlignment', 'center', 'EdgeColor', 'none');

annotation('rectangle', [0.83 0.3 0.12 0.08], 'LineWidth', 1, 'Color', [0.5 0.5 0.5]);
annotation('textbox', [0.83 0.32 0.12 0.04], 'String', 'Neural UI Cache', ...
    'FontSize', 10, 'HorizontalAlignment', 'center', 'EdgeColor', 'none');

% Session Cache
annotation('rectangle', [0.4 0.25 0.2 0.08], 'LineWidth', 1.5, 'Color', 'magenta');
annotation('textbox', [0.4 0.27 0.2 0.04], 'String', 'Session Cache', ...
    'FontSize', 11, 'HorizontalAlignment', 'center', 'EdgeColor', 'none');

% State Operations
annotation('rectangle', [0.15 0.1 0.15 0.08], 'LineWidth', 1, 'Color', [0.8 0.4 0]);
annotation('textbox', [0.15 0.12 0.15 0.04], 'String', 'Save State', ...
    'FontSize', 10, 'HorizontalAlignment', 'center', 'EdgeColor', 'none');

annotation('rectangle', [0.35 0.1 0.15 0.08], 'LineWidth', 1, 'Color', [0.8 0.4 0]);
annotation('textbox', [0.35 0.12 0.15 0.04], 'String', 'Load State', ...
    'FontSize', 10, 'HorizontalAlignment', 'center', 'EdgeColor', 'none');

annotation('rectangle', [0.55 0.1 0.15 0.08], 'LineWidth', 1, 'Color', [0.8 0.4 0]);
annotation('textbox', [0.55 0.12 0.15 0.04], 'String', 'Process Data', ...
    'FontSize', 10, 'HorizontalAlignment', 'center', 'EdgeColor', 'none');

% Add arrows to show flow
annotation('arrow', [0.5 0.5], [0.7 0.62], 'LineWidth', 2);
annotation('arrow', [0.5 0.25], [0.7 0.62], 'LineWidth', 2);
annotation('arrow', [0.5 0.75], [0.7 0.62], 'LineWidth', 2);

annotation('arrow', [0.5 0.5], [0.45 0.33], 'LineWidth', 1.5, 'Color', 'red');

% Add labels
annotation('textbox', [0.3 0.65 0.1 0.04], 'String', 'Mode Switch', ...
    'FontSize', 9, 'EdgeColor', 'none', 'Color', 'blue');
annotation('textbox', [0.6 0.65 0.15 0.04], 'String', 'Context Switch', ...
    'FontSize', 9, 'EdgeColor', 'none', 'Color', 'red');

% Problem areas
annotation('textbox', [0.02 0.02 0.4 0.05], 'String', '⚠️ Problem Areas: Complex state nesting, Manual cache management', ...
    'FontSize', 10, 'EdgeColor', 'red', 'LineWidth', 2, 'Color', 'red', ...
    'BackgroundColor', [1 0.9 0.9]);

title('State Management Challenges in NeuroView');

saveas(gcf, 'neuroView_state_diagram.png');
disp('State management diagram saved as neuroView_state_diagram.png');