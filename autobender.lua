class "Autobender"

require "AutobenderWindow"
require "utils"

    ----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

function Autobender:__init()

    self.in_ui_update = false -- is the value change originated by the program (instead of the user)?
    self.in_automation_update = false

    self.window = AutobenderWindow(self)
    self.window:show_dialog()

    renoise.song().selected_pattern_track_observable:add_notifier(
        function()
            self:handle_pattern_track_change()
        end
    )
    self:handle_pattern_track_change()

    self.need_update = false
    renoise.tool().app_idle_observable:add_notifier(
        function()
            if self.need_update then
                self:update_automation()
                self.need_update = false
            end
        end
    )

end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

function Autobender:handle_pattern_track_change()
    if self.window.dialog.visible then
        renoise.song().selected_automation_parameter_observable:add_notifier(
            function()
                self:handle_parameter_change()
            end
        )
        renoise.song().selected_pattern_track.automation_observable:add_notifier(
            function()
                self:handle_parameter_change()
            end
        )
    end
    self:handle_parameter_change()
end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

function Autobender:handle_parameter_change()
    local pattern_track = renoise.song().selected_pattern_track
    local parameter = renoise.song().selected_automation_parameter
    self.automation = pattern_track:find_automation(parameter)
    if self.automation then
        self.automation.selection_range_observable:add_notifier(
            function()
                self:handle_selection_range_change()
            end
        )
        self.automation.points_observable:add_notifier(
            function()
                if not self.in_automation_update then
                    self:handle_selection_range_change()
                end
            end
        )
    end
    self:handle_selection_range_change()
end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

function Autobender:handle_selection_range_change()
    if self.window.dialog.visible then
        local pattern_track = renoise.song().selected_pattern_track
        local parameter = renoise.song().selected_automation_parameter
        self.automation = pattern_track:find_automation(parameter)
        if
            self.automation
            and self.automation.selection_start < self.automation.selection_end
            and self.automation.selection_end < self.automation.length + 1
        then
            local selection_start = self.automation.selection_start
            local selection_end = self.automation.selection_end

            -- Compute automation values at start and end of selection
            local start_prec, start_next, end_prec, end_next = nil, nil, nil, nil
            local points = self.automation.points
            for _,point in pairs(points) do
                if point.time < selection_start then
                    start_prec = point
                elseif not start_next then
                    start_next = point
                end
                if point.time < selection_end then
                    end_prec = point
                elseif not end_next then
                    end_next = point
                end
            end
            local start_value = 0
            if start_prec and start_next then
                start_value = self:point_on_line(
                    selection_start,
                    start_prec.time,
                    start_prec.value,
                    start_next.time,
                    start_next.value
                )
            elseif start_prec then
                start_value = start_prec.value
            elseif start_next then
                start_value = start_next.value
            end
            local end_value = 0
            if end_prec and end_next then
            end_value = self:point_on_line(
                selection_end,
                end_prec.time,
                end_prec.value,
                end_next.time,
                end_next.value
            )
            elseif end_next then
                end_value = end_next.value
            elseif end_prec then
                end_value = end_prec.value
            end
            if end_value > 1.0 then end_value = 1.0 end

            self.in_ui_update = true
            local views = self.window.vb.views
            views["status"].text = "Selection: " .. selection_start - 1 .. " - " .. selection_end - 1
            views["start"].value = start_value
            views["start"].active = true
            views["end"].value = end_value
            views["end"].active = true
            self.in_ui_update = false
        else
            self.in_ui_update = true
            local views = self.window.vb.views
            views["status"].text = "(No selection)"
            views["start"].value = 0.0
            views["start"].active = false
            views["end"].value = 0.0
            views["end"].active = false
            self.in_ui_update = false
        end
    end
end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

function Autobender:point_on_line(x, x1, y1, x2, y2)
    local a = (y1 - y2) / (x1 - x2)
    local b = y1 - a * x1
    return a * x + b
end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

function Autobender:update_automation()
    local automation = self.automation
    if
        automation
        and automation.selection_start < automation.selection_end
        and automation.selection_end < automation.length + 1
    then
        local views = self.window.vb.views

        local start_value = views["start"].value
        local end_value = views["end"].value

        local curvature = views["curvature"].value
        local shape = views["shape"].value

        local step = views["step"].value
        if step == 0 then
            step = 1.0 / 8.0
        elseif step == 1 then
            step = 1.0 / 4.0
        elseif step == 2 then
            step = 1.0 / 2.0
        else
            step = step - 2
        end

        self.in_automation_update = true
        automation:clear_range(automation.selection_start, automation.selection_end)
        automation:add_point_at(automation.selection_start, start_value)
        automation:add_point_at(automation.selection_end, end_value)
        for p = automation.selection_start + step, automation.selection_end, step do
            local v = self:point_on_curve(
                p,
                automation.selection_start,
                start_value,
                automation.selection_end,
                end_value,
                curvature,
                shape
            )
            if v < 0.0 then v = 0.0 end
            if v > 1.0 then v = 1.0 end
            automation:add_point_at(p, v)
        end
        self.in_automation_update = false
    end
end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

function Autobender:point_on_curve(x, x1, y1, x2, y2, curvature, shape)
    local x_normalised = (x - x1) / (x2 - x1)
    local value = self:curve(x_normalised, curvature, shape)
    return y1 + value * (y2 - y1)
end


function Autobender:curve(x, curvature, shape)

    local result

    shape = 4.0 * shape
    if shape < 1.0 then
        result = mix(
            self:curve_exponential(x, curvature),
            self:curve_logarithmic(x, curvature),
            shape
        )
    elseif shape < 2.0 then
        result = mix(
            self:curve_logarithmic(x, curvature),
            self:curve_circular(x, curvature),
            shape - 1.0
        )
    elseif shape < 3.0 then
        shape = shape
        result = mix(
            self:curve_circular(x, curvature),
            self:curve_half_sinusoidal(x, curvature),
            shape - 2.0
        )
    else
        shape = shape
        result = mix(
            self:curve_half_sinusoidal(x, curvature),
            self:curve_sinusoidal(x, curvature),
            shape - 3.0
        )
    end

    return result

end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

function Autobender:curve_exponential(x, curvature)
    local b = -16.0 * curvature * (math.exp(1.0 * math.abs(curvature)) - 1.0) / (math.exp(1.0) - 1.0)
    if math.abs(curvature) > 0.01 then
        return (math.exp(b * x) - 1.0) / (math.exp(b) - 1.0)
    else
        return x
    end
end


function Autobender:curve_logarithmic(x, curvature)
    local b = 16.0 * curvature * (math.exp(1.0 * math.abs(curvature)) - 1.0) / (math.exp(1.0) - 1.0)
    if math.abs(curvature) > 0.01 then
        return math.log(x * (math.exp(b) - 1.0) + 1.0) / b
    else
        return x
    end
end

function Autobender:curve_circular(x, curvature)
    --local b = curvature * (math.exp(4.0 * math.abs(curvature)) - 1.0) / (math.exp(4.0) - 1.0)
    local b = curvature
    if math.abs(curvature) > 0.01 then
        local new_position = (b * x + (1.0 - b) * 0.5)
        local angle = math.acos(1.0 - new_position)
        local result = math.sin(angle)
        return (result - math.sin(math.acos(1.0 - ((1.0 - b) * 0.5))))
            / (math.sin(math.acos(1.0 - (b + (1.0 - b) * 0.5))) - math.sin(math.acos(1.0 - ((1.0 - b) * 0.5))))
    else
        return x
    end
end

function Autobender:curve_half_sinusoidal(x, curvature)
    local b = math.abs(curvature)
    if curvature > 0.01 then
        return (1.0 - b) * x + b * math.sin(x * math.pi/2.0)
    elseif curvature < -0.01 then
        return (1.0 - b) * x + b * (math.sin(3.0*math.pi/2.0 + x * math.pi/2.0) + 1.0)
    else
        return x
    end
end

function Autobender:curve_sinusoidal(x, curvature)
    local b = math.abs(curvature)
    if curvature > 0.01 then
        return (1.0 - b) * x + b * (math.sin((x - 0.5) * math.pi) / 2.0 + 0.5)
    elseif curvature < -0.01 then
        return (1.0 - b) * x + b * (math.asin(2.0 * x - 1.0) / math.pi + 0.5)
    else
        return x
    end
end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
