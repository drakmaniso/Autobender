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

        local curvature = views["curvature"].value / 1000.0
        if start_value > end_value then
            --curvature = - curvature
        end
        local shape = views["shape"].value / 1000.0

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


function Autobender:curve(x, curvature, esser)

    local result

    local mode = self.window.vb.views["mode"].value
    local shape = self.window.vb.views["esser"].value
    local total_length = 1.0 + esser

    if mode == 1 then

        local orig_exponential = curve_exponential(esser, curvature)
        local height_exponential = 1.0 + orig_exponential
        local orig_logarithmic = curve_logarithmic(esser, curvature)
        local height_logarithmic = 1.0 + orig_logarithmic
        if x > esser / total_length then
            result = mix(
                orig_exponential/height_exponential + curve_exponential((x - esser / total_length) * total_length, curvature) / height_exponential,
                orig_logarithmic/height_logarithmic + curve_logarithmic((x - esser / total_length) * total_length, curvature) / height_logarithmic,
                shape
            )
        else
            result = mix(
                orig_exponential/height_exponential - curve_exponential(esser - x * total_length, curvature) / height_exponential,
                orig_logarithmic/height_logarithmic - curve_logarithmic(esser - x * total_length, curvature) / height_logarithmic,
                shape
            )
        end

    else

        if curvature > 0.0 then
            local orig_half_sinusoidal = curve_half_sinusoidal(esser, curvature)
            local height_half_sinusoidal = 1.0 + orig_half_sinusoidal
            local orig_circular = curve_circular(esser, curvature)
            local height_circular = 1.0 + orig_circular
            if x > esser / total_length then
                result = mix(
                    orig_half_sinusoidal/height_half_sinusoidal + curve_half_sinusoidal((x - esser / total_length) * total_length, curvature) / height_half_sinusoidal,
                    orig_circular/height_circular + curve_circular((x - esser / total_length) * total_length, curvature) / height_circular,
                    shape
                )
            else
                result = mix(
                    orig_half_sinusoidal/height_half_sinusoidal - curve_half_sinusoidal(esser - x * total_length, curvature) / height_half_sinusoidal,
                    orig_circular/height_circular - curve_circular(esser - x * total_length, curvature) / height_circular,
                    shape
                )
            end
        else
            local extra_half_sinusoidal = 1.0 - curve_half_sinusoidal(1.0 - esser, curvature)
            local height_half_sinusoidal = (1.0 + extra_half_sinusoidal)
            local extra_circular = 1.0 - curve_circular(1.0 - esser, curvature)
            local height_circular = (1.0 + extra_half_sinusoidal)
            if x < 1.0 - esser / total_length then
                result = mix(
                    curve_half_sinusoidal(x * total_length, curvature) / height_half_sinusoidal,
                    curve_circular(x * total_length, curvature) / height_circular,
                    shape
                )
            else
                result = mix(
                    (2.0 - curve_half_sinusoidal(1.0 - (x * total_length - 1.0), curvature)) / height_half_sinusoidal,
                    (2.0 - curve_circular(1.0 - (x * total_length - 1.0), curvature)) / height_circular,
                    shape
                )
            end
        end

    end

    return result

end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
