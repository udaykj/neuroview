classdef ModeChangedEventData < event.EventData
    properties
        OldMode
        NewMode
    end
    
    methods
        function obj = ModeChangedEventData(oldMode, newMode)
            obj.OldMode = oldMode;
            obj.NewMode = newMode;
        end
    end
end