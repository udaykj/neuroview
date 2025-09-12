classdef CacheInvalidatedEventData < event.EventData
    properties
        Slot
        Timestamp
    end
    
    methods
        function obj = CacheInvalidatedEventData(slot)
            obj.Slot = slot;
            obj.Timestamp = datetime('now');
        end
    end
end