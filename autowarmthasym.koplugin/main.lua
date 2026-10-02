--[[--
Companion plugin for AutoWarmth: separate warmth / night mode values for every
sun event (sunrise vs. sunset, civil dawn vs. civil dusk, ...).

The stock AutoWarmth plugin already stores eleven independent warmth values and
its scheduler interpolates between them; only its settings menu forces the
evening value to mirror the morning one. This plugin replaces that one menu
function on the live AutoWarmth instance and changes nothing else, so it can be
installed next to the stock plugin and survives KOReader updates.

@module koplugin.autowarmthasym
--]]--

local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local Powerd = Device.powerd
local T = FFIUtil.template

local device_max_warmth = Device:hasNaturalLight() and Powerd.fl_warmth_max or 100

-- Same helper as in the stock plugin: drop entries whose `mode` does not match
-- the current easy/expert mode.
local function tidy_menu(menu, request)
    for i = #menu, 1, -1 do
        if menu[i].mode ~= nil then
            if menu[i].mode ~= request then
                table.remove(menu, i)
            else
                menu[i].mode = nil
            end
        end
    end
    return menu
end

-- Replacement for AutoWarmth:getWarmthMenu(). Copied from the stock plugin with
-- two changes: one menu entry per sun event, and no mirroring of the value onto
-- the opposite half of the day. `self` is the AutoWarmth instance.
local function getWarmthMenu(self)
    -- mode == nil ... show always
    --      == true ... easy mode
    --      == false ... expert mode
    local function getWarmthMenuEntry(text, num, mode)
        return {
            mode = mode,
            text_func = function()
                if Device:hasNaturalLight() and self.control_warmth then
                    if self.control_nightmode then
                        if self.warmth[num] <= 100 then
                            return T(_("%1: %2 %"), text, self.warmth[num])
                        else
                            return T(_("%1: %2 % + ☾"), text, math.max(self.warmth[num] - 1000, 0))
                        end
                    else
                        if self.warmth[num] <= 100 then
                            return T(_("%1: %2 %"), text, self.warmth[num])
                        else
                            return T(_("%1: %2 %"), text, math.max(self.warmth[num] - 1000, 0))
                        end
                    end
                else
                    if self.warmth[num] <= 100 then
                        return T(_("%1: ☼"), text)
                    else
                        return T(_("%1: ☾"), text)
                    end
                end
            end,
            callback = function(touchmenu_instance)
                if Device:hasNaturalLight() and self.control_warmth then
                    local warmth_spinner = SpinWidget:new{
                        title_text = text,
                        info_text = _("Enter percentage of warmth."),
                        value = self.warmth[num] <= 100 and self.warmth[num] or math.max(self.warmth[num] - 1000, 0), -- mask nightmode
                        value_min = 0,
                        value_max = 100,
                        wrap = false,
                        value_step = math.floor(100 / device_max_warmth),
                        value_hold_step = 10,
                        unit = "%",
                        ok_text = _("Set"),
                        ok_always_enabled = true,
                        callback = function(spin)
                            self.warmth[num] = spin.value
                            if self.control_nightmode and self.night_mode_check_box.checked then
                                if self.warmth[num] <= 100 then
                                    self.warmth[num] = self.warmth[num] + 1000 -- add night mode
                                end
                            else
                                if self.warmth[num] > 100 then
                                    self.warmth[num] = math.max(self.warmth[num] - 1000, 0) -- delete night mode
                                end
                            end
                            G_reader_settings:saveSetting("autowarmth_warmth", self.warmth)
                            self:scheduleMidnightUpdate()
                            if touchmenu_instance then self:updateItems(touchmenu_instance) end
                        end,
                    }

                    if self.control_nightmode then
                        self.night_mode_check_box = CheckButton:new{
                            text = _("Night mode"),
                            checked = self.warmth[num] > 100,
                            parent = warmth_spinner,
                        }
                        warmth_spinner:addWidget(self.night_mode_check_box)
                    end
                    UIManager:show(warmth_spinner)
                else
                    UIManager:show(ConfirmBox:new{
                        text = _("Night mode"),
                        ok_text = _("Turn on"),
                        ok_callback = function()
                            if self.warmth[num] <= 100 then
                                self.warmth[num] = self.warmth[num] + 1000
                                G_reader_settings:saveSetting("autowarmth_warmth", self.warmth)
                                self:scheduleMidnightUpdate()
                                if touchmenu_instance then self:updateItems(touchmenu_instance) end
                            end
                        end,
                        cancel_text = _("Turn off"),
                        cancel_callback = function()
                            if self.warmth[num] > 100 then
                                self.warmth[num] = math.max(self.warmth[num] - 1000, 0) -- delete night mode
                                G_reader_settings:saveSetting("autowarmth_warmth", self.warmth)
                                self:scheduleMidnightUpdate()
                                if touchmenu_instance then self:updateItems(touchmenu_instance) end
                            end
                        end,
                        other_buttons = {{
                            {
                                text = _("Cancel"),
                            }
                        }},
                    })
                end
            end,
            keep_menu_open = true,
        }
    end

    local retval = {
        {
            text_func = function()
                if Device:hasNaturalLight() then
                    return T(_("Control: %1%2%3"), self.control_warmth and _("warmth") or "",
                            self.control_warmth and self.control_nightmode and T(" %1 ", _("and")) or "",
                            self.control_nightmode and _("night mode") or "")
                else
                    return _("Control: night mode")
                end
            end,
            checked_func = function()
                if Device:hasNaturalLight() then
                    return self.control_nightmode or self.control_warmth
                else
                    return self.control_nightmode
                end
            end,
            hold_callback = function()
                if Device:hasNaturalLight() then
                    UIManager:show(InfoMessage:new{
                        text = _("Tapping here chooses between the different AutoWarmth modes: 'warmth only', 'warmth and night mode', 'night mode only'."),
                    })
                else
                    UIManager:show(InfoMessage:new{
                        text = _("Your device supports 'night mode' control only."),
                    })
                end
            end,
            check_callback_updates_menu = true,
            callback = function(touchmenu_instance)
                if Device:hasNaturalLight() then
                    if self.control_warmth and self.control_nightmode then
                        self.control_warmth = true
                        self.control_nightmode = false
                        G_reader_settings:makeTrue("autowarmth_control_warmth")
                        G_reader_settings:makeFalse("autowarmth_control_nightmode")
                    elseif self.control_warmth and not self.control_nightmode then
                        self.control_warmth = false
                        self.control_nightmode = true
                        G_reader_settings:makeFalse("autowarmth_control_warmth")
                        G_reader_settings:makeTrue("autowarmth_control_nightmode")
                    else
                        self.control_warmth = true
                        self.control_nightmode = true
                        G_reader_settings:makeTrue("autowarmth_control_warmth")
                        G_reader_settings:makeTrue("autowarmth_control_nightmode")
                    end
                else
                    self.control_nightmode = not self.control_nightmode
                    G_reader_settings:toggle("autowarmth_control_nightmode")
                end
                self:scheduleMidnightUpdate()
                if touchmenu_instance then self:updateItems(touchmenu_instance) end
            end,
            keep_menu_open = true,
            separator = true,
        },
        {
            text = Device:hasNaturalLight() and _("Set warmth and night mode for:") or _("Set night mode for:"),
            enabled = false,
        },
        getWarmthMenuEntry(_("Solar midnight (previous day)"), 1, false),
        getWarmthMenuEntry(_("Astronomical dawn"), 2, false),
        getWarmthMenuEntry(_("Nautical dawn"), 3, false),
        getWarmthMenuEntry(_("Civil dawn"), 4),
        getWarmthMenuEntry(_("Sunrise"), 5),
        getWarmthMenuEntry(_("Solar noon"), 6),
        getWarmthMenuEntry(_("Sunset"), 7),
        getWarmthMenuEntry(_("Civil dusk"), 8),
        getWarmthMenuEntry(_("Nautical dusk"), 9, false),
        getWarmthMenuEntry(_("Astronomical dusk"), 10, false),
        getWarmthMenuEntry(_("Solar midnight"), 11, false),
    }

    return tidy_menu(retval, self.easy_mode)
end

local AutoWarmthAsym = WidgetContainer:extend{
    name = "autowarmthasym",
    is_doc_only = false,
}

function AutoWarmthAsym:init()
    -- Plugins are instantiated one after another; wait until all of them exist
    -- before looking for AutoWarmth.
    self.ui:registerPostInitCallback(function()
        self:patchAutoWarmth()
    end)
end

function AutoWarmthAsym:patchAutoWarmth()
    local autowarmth = self.ui.autowarmth
    if not autowarmth then
        logger.dbg("AutoWarmthAsym: AutoWarmth plugin not loaded, nothing to patch")
        return
    end
    if type(autowarmth.getWarmthMenu) ~= "function" then
        logger.warn("AutoWarmthAsym: AutoWarmth has no getWarmthMenu(), not patching")
        return
    end
    -- Override on the instance only (not on the class), so a disabled or
    -- removed companion plugin leaves the stock plugin untouched.
    autowarmth.getWarmthMenu = getWarmthMenu
    logger.dbg("AutoWarmthAsym: AutoWarmth warmth menu patched")
end

return AutoWarmthAsym
