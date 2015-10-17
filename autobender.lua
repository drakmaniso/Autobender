class "Autobender"

require "AutobenderWindow"


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


local function point_on_line(x, x1, y1, x2, y2)
    local a = (y1 - y2) / (x1 - x2)
    local b = y1 - a * x1
    return a * x + b
end


----------------------------------------------------------------------------------------------------


local function curve(position, curvature, shape)

    local exp_curvature = (100000.0 ^ (1.0 + math.abs(curvature))) / 100000.0
    local circ_curvature = 1.0 - ((1000.0 ^ (1.0 - math.abs(curvature))) - 1.0) / (1000.0 - 1.0)
    local sin_curvature = math.abs(curvature)
    local exp_result, circ_result, sin_result, result
    local pi = math.pi

    if curvature > 0.01 then

        exp_result = 1.0 - ((exp_curvature ^ (1.0 - position)) - 1.0) / (exp_curvature - 1.0)

        local new_position = (circ_curvature * position + (1.0 - circ_curvature) * 0.5)
        local angle = math.acos(1.0 - new_position)
        circ_result = math.sin(angle)
        circ_result = (circ_result - math.sin(math.acos(1.0 - ((1.0 - circ_curvature) * 0.5))))
            / (math.sin(math.acos(1.0 - (circ_curvature + (1.0 - circ_curvature) * 0.5))) - math.sin(math.acos(1.0 - ((1.0 - circ_curvature) * 0.5))))

        sin_result = (1.0 - sin_curvature) * position + sin_curvature * math.sin(position * pi/2.0)

        if shape < 0.0 then
            shape = shape + 1.0
            result = shape * circ_result + (1.0 - shape) * exp_result
        else
            result = shape * sin_result + (1.0 - shape) * circ_result
        end

    elseif curvature < -0.01 then

        exp_result = ((exp_curvature ^ position) - 1.0) / (exp_curvature - 1.0)

        local new_position = (circ_curvature * position + (1.0 - circ_curvature) * 0.5)
        local angle = math.acos(new_position)
        circ_result = 1.0 - math.sin(angle)
        circ_result = (circ_result - (1.0 - math.sin(math.acos((1.0 - circ_curvature) * 0.5))))
            / (1.0 - math.sin(math.acos(circ_curvature + (1.0 - circ_curvature) * 0.5)) - 1.0 + math.sin(math.acos((1.0 - circ_curvature) * 0.5)))

        sin_result = (1.0 - sin_curvature) * position + sin_curvature * (math.sin(3.0*math.pi/2.0 + position * math.pi/2.0) + 1.0)

        if shape < 0.0 then
            shape = shape + 1.0
            result = shape * circ_result + (1.0 - shape) * sin_result
        else
            result = shape * exp_result + (1.0 - shape) * circ_result
        end

    else

        result = position

    end

    return result

end


local function point_on_curve(x, x1, y1, x2, y2, curvature, shape)
    local position = (x - x1) / (x2 - x1)
    local value = curve(position, curvature, shape)
    return y1 + value * (y2 - y1)
end


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
                start_value = point_on_line(selection_start, start_prec.time, start_prec.value, start_next.time, start_next.value)
            elseif start_prec then
                start_value = start_prec.value
            elseif start_next then
                start_value = start_next.value
            end
            local end_value = 0
            if end_prec and end_next then
                end_value = point_on_line(selection_end, end_prec.time, end_prec.value, end_next.time, end_next.value)
            elseif end_next then
                end_value = end_next.value
            elseif end_prec then
                end_value = end_prec.value
            end
            if end_value > 1.0 then end_value = 1.0 end

            self.in_ui_update = true
            local views = self.window.vb.views
            views["status"].text = "Selection: " .. selection_start - 1 .. " -  " .. selection_end - 1
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
        local curvature = views["curve"].value.y
        local shape = views["curve"].value.x
        if start_value > end_value then
            curvature = - curvature
        end
        self.in_automation_update = true
        automation:clear_range(automation.selection_start, automation.selection_end)
        automation:add_point_at(automation.selection_start, start_value)
        automation:add_point_at(automation.selection_end, end_value)
        for p = automation.selection_start + 1, automation.selection_end do
            local v = point_on_curve(p, automation.selection_start, start_value, automation.selection_end, end_value, curvature, shape)
            if v < 0.0 then v = 0.0 end
            if v > 1.0 then v = 1.0 end
            automation:add_point_at(p, v)
        end
        self.in_automation_update = false
    end
end


----------------------------------------------------------------------------------------------------
