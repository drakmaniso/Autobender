class "AutobenderWindow"

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

function AutobenderWindow:__init(autobender)
    self.vb = renoise.ViewBuilder()
    self.autobender = autobender
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

        vb:text
        {
            id = "status",
            text = "(No selection)",
            width = "100%",
            font = "big",
            align = "center",
        },


        vb:horizontal_aligner
        {
            width = "100%",
            mode = "justify",

            vb:minislider
            {
                id = "start",
                height = 200,
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


            vb:xypad
            {
                id = "curve",
                height = 200,
                width = 200,
                min = {x = 0.0, y = 0.0},
                max = {x = 1.0, y = 1.0},
                value = {x = 0.5, y = 0.5},
                notifier = function(value)
                    local automation = self.autobender.automation
                    if automation and not self.autobender.in_ui_update then
                        vb.views["status"].text = "X: " .. math.floor(value.x * 100.0 + 0.5) .. "   Y: " .. math.floor(value.y * 100.0 + 0.5)
                        self.autobender.need_update = true
                    end
                end,
            },
            vb:column { width = 8 },
            vb:minislider
            {
                id = "end",
                height = 200,
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


        vb:horizontal_aligner
        {
            mode = "center",
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


    }

    return result

end

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
