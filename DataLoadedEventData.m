classdef DataLoadedEventData < event.EventData
    properties
        Filepath
        Mode
    end
    
    methods
        function obj = DataLoadedEventData(filepath, mode)
            obj.Filepath = filepath;
            obj.Mode = mode;
        end
    end
end