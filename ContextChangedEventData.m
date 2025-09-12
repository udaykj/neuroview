classdef ContextChangedEventData < event.EventData
    properties
        OldContext
        NewContext
    end
    
    methods
        function obj = ContextChangedEventData(oldContext, newContext)
            obj.OldContext = oldContext;
            obj.NewContext = newContext;
        end
    end
end