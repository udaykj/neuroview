classdef UIRestoredEventData < event.EventData
    properties
        Mode
        Context
    end
    
    methods
        function obj = UIRestoredEventData(mode, context)
            obj.Mode = mode;
            obj.Context = context;
        end
    end
end