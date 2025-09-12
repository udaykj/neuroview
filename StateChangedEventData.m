classdef StateChangedEventData < event.EventData
    properties
        Component
        Field
        OldValue
        NewValue
    end
    
    methods
        function obj = StateChangedEventData(component, field, newValue)
            obj.Component = component;
            obj.Field = field;
            obj.NewValue = newValue;
        end
    end
end