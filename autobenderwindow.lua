class "AutobenderWindow"

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

function AutobenderWindow:__init(autobender)
    self.vb = renoise.ViewBuilder()
    self.autobender = autobender
    renoise.tool().app_release_document_observable:add_notifier(
        function()
            if self.dialog and self.dialog.visible then
                self.dialog:close()
            end
        end
    )
end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

function AutobenderWindow:show_dialog ()

    if self.dialog and self.dialog.visible then
        self.dialog:show ()
        return
    end

    if not self.dialog_content then
        self.dialog_content = self:gui ()
    end

    local kh = function (d, k) return self:key_handler (d, k) end
    self.dialog = renoise.app():show_custom_dialog ("Autobender", self.dialog_content, kh)

end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

function AutobenderWindow:key_handler (dialog, key)
    if key.modifiers == "" and key.name == "esc" then
        dialog:close()
    else
        return key
    end
end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

AutobenderWindow.mode_names = {
    "exponential",
    "logarithmic",
    "sinusoidal",
    "half-sinusoidal",
    "arc-sinusoidal",
    "circular",
}

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

function AutobenderWindow:gui ()

    local vb = self.vb

    local dialog_margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN
    local dialog_spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING
    local control_margin = renoise.ViewBuilder.DEFAULT_CONTROL_MARGIN
    local control_spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING
    local control_height = renoise.ViewBuilder.DEFAULT_CONTROL_HEIGHT

    local result = vb:column
    {
        style = "body",
        -- width = 300,
        height = 400,
        margin = dialog_margin,
        spacing = dialog_spacing,
        uniform = true,

        vb:horizontal_aligner
        {
            width = "100%",
            mode = "justify",

            vb:minislider
            {
                id = "start",
                height = "100%",
                width = 24,
                notifier = function(value)
                    local automation = self.autobender.automation
                    if automation and not self.autobender.in_ui_update then
                        vb.views["status"].text = "Start: " .. (math.floor(value * 100.0 + 0.5) / 1.0)
                        self.autobender.need_update = true
                    end
                end,
            },

            vb:column { width = 8 },

            vb:column
            {

                vb:column
                {
                    width = "100%",
                    -- mode = "center",
                    style = "group",
                    vb:text
                    {
                        id = "status",
                        text = "(No selection)",
                        width = "100%",
                        height = 42,
                        font = "big",
                        align = "center",
                    },
                },

                vb:row { height = 8, },

                vb:xypad
                {
                    id = "curve",
                    height = 200,
                    width = 200,
                    min = {x = 0.0, y = 0.0},
                    max = {x = 2.0, y = 1.0},
                    value = {x = 0.0, y = 0.0},
                    notifier = function(value)
                        local automation = self.autobender.automation
                        if automation and not self.autobender.in_ui_update then
                            vb.views["status"].text = "Torsion: " .. math.floor(value.x * 50.0 + 0.5) .. "   Curvature: " .. math.floor(value.y * 100.0 + 0.5)
                            self:update_curvature_and_shape_rotaries()
                            self.autobender.need_update = true
                        end
                    end,
                },

                vb:row { height = 8, },

                vb:minislider
                {
                    id = "shape",
                    width = 200,
                    height = 16,
                    min = -1.0,
                    max = 1.0,
                    value = 0.0,
                    notifier = function(value)
                        local shape_string
                        local percent = math.floor(value * 100.0 + 0.5)
                        if percent == -100 then
                            shape_string = "logarithmic"
                        elseif percent < 0 then
                            shape_string = "" .. -percent .. "% log  " .. 100+percent .. "% exp"
                        elseif percent == 0 then
                            shape_string = "exponential"
                        elseif percent < 100 then
                            shape_string = "" .. 100-percent .. "% exp  " .. percent .. "% sin"
                        else
                            shape_string = "sinusoidal"
                        end
                        vb.views["status"].text = "Shape: " .. shape_string
                        self.autobender.need_update = true
                    end,
                },

                vb:row { height = 8, },

                vb:valuebox
                {
                    id = "step",
                    width = 200,
                    min = 0,
                    max = 16 + 2,
                    value = 3,
                    tostring = function(n)
                        if n == 0 then
                            return "8 points per line"
                        elseif n == 1 then
                            return "4 points per line"
                        elseif n == 2 then
                            return "2 points per line"
                        elseif n == 3 then
                            return "1 point per line"
                        else
                            return "1 point every " .. n - 2 .. " lines"
                        end
                    end,
                    tonumber = function(s)
                        return 3
                    end,
                    notifier = function()
                        self.autobender.need_update = true
                    end,
                },

            },

            vb:column { width = 8 },

            vb:minislider
            {
                id = "end",
                height = "100%",
                width = 24,
                notifier = function(value)
                    local automation = self.autobender.automation
                    if automation and not self.autobender.in_ui_update then
                        vb.views["status"].text = "End: " .. (math.floor(value * 100.0 + 0.5) / 1.0)
                        self.autobender.need_update = true
                    end
                end,
            },

        },


    }

    return result

end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

function AutobenderWindow:update_curvature_and_shape_rotaries()

    -- if not self.autobender.in_ui_update then
    --
    --     local start_value = self.vb.views["start"].value
    --     local end_value = self.vb.views["end"].value
    --
    --     local curve_x = self.vb.views["curve"].value.x
    --     local curve_y = self.vb.views["curve"].value.y
    --
    --     self.autobender.in_ui_update = true
    --     self.vb.views["curvature"].value = math.floor(1000.0 * curve_y + 0.5)
    --     self.vb.views["shape"].value = math.floor(1000.0 * curve_x + 0.5)
    --     self.autobender.in_ui_update = false
    --
    -- end

end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
