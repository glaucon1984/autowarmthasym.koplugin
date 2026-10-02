-- Harness: luajit tests/test_asym.lua <companion plugin dir> <stock autowarmth.koplugin dir>
-- Loads the pristine upstream autowarmth plugin and the companion
-- plugin with stubbed KOReader modules, then exercise the warmth menu.
local plugin_dir = arg[1] or "autowarmthasym.koplugin"
local upstream_dir = arg[2] or "autowarmth.koplugin"
local checks, failed = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then failed = failed + 1; print("FAIL: " .. msg) end
end

-- Auto-vivifying stub for any module we do not model explicitly.
local function autostub()
    local t = {}
    return setmetatable(t, {
        __index = function(self, k) local v = autostub(); rawset(self, k, v); return v end,
        __call = function() return autostub() end,
    })
end
local shown = {}
local function widgetClass()
    local C = {}
    C.__index = C
    function C:new(o) o = o or {}; setmetatable(o, self); self.__index = self; if o.init then o:init() end; return o end
    function C:extend(o) o = o or {}; setmetatable(o, self); self.__index = self; return o end
    function C:addWidget() end
    return C
end
local stubs = {
    ["device"] = { hasNaturalLight = function() return true end, powerd = { fl_warmth_max = 100 }, screen = {},
                   isKobo = function() return true end },
    ["gettext"] = setmetatable({ pgettext = function(c, s) return s end }, { __call = function(_, s) return s end }),
    ["ffi/util"] = { template = function(s, ...)
        local a = { ... }
        return (s:gsub("%%(%d)", function(i) return tostring(a[tonumber(i)]) end))
    end },
    ["ui/uimanager"] = { show = function(_, w) shown[#shown + 1] = w end, unschedule = function() end,
                         scheduleIn = function() end, broadcastEvent = function() end, close = function() end,
                         event_hook = { registerWidget = function() end } },
    ["ui/widget/spinwidget"] = widgetClass(),
    ["ui/widget/checkbutton"] = widgetClass(),
    ["ui/widget/confirmbox"] = widgetClass(),
    ["ui/widget/infomessage"] = widgetClass(),
    ["ui/widget/container/widgetcontainer"] = widgetClass(),
    ["logger"] = { dbg = function() end, warn = function() end, info = function() end, err = function() end },
    ["dispatcher"] = { registerAction = function() end },
}
table.insert(package.loaders, function(name)
    return function() return stubs[name] or autostub() end
end)

-- Fake settings store
local store = {}
G_reader_settings = {
    readSetting = function(_, k, default) if store[k] == nil then return default end return store[k] end,
    saveSetting = function(_, k, v) store[k] = v end,
    nilOrTrue = function(_, k) return store[k] ~= false end,
    nilOrFalse = function(_, k) return store[k] == true end,
    isTrue = function(_, k) return store[k] == true end,
    makeTrue = function(_, k) store[k] = true end,
    makeFalse = function(_, k) store[k] = false end,
    toggle = function(_, k) store[k] = not store[k] end,
}

local AutoWarmth = dofile(upstream_dir .. "/main.lua")
local Asym = dofile(plugin_dir .. "/main.lua")
local orig_getWarmthMenu = AutoWarmth.getWarmthMenu
local sched_calls = 0
AutoWarmth.scheduleMidnightUpdate = function() sched_calls = sched_calls + 1 end
local update_calls = 0
AutoWarmth.updateItems = function() update_calls = update_calls + 1 end

local function newUI()
    local ui = { postInitCallback = {}, menu = { registerToMainMenu = function() end } }
    function ui:registerPostInitCallback(cb) table.insert(self.postInitCallback, cb) end
    function ui:runPostInit() for _, cb in ipairs(self.postInitCallback) do cb() end end
    return ui
end
local function build(with_autowarmth)
    store = {}
    shown = {}
    local ui = newUI()
    if with_autowarmth then ui.autowarmth = AutoWarmth:new{ ui = ui } end
    ui.autowarmthasym = Asym:new{ ui = ui }
    ui:runPostInit()
    return ui
end
local function entry(menu, prefix)
    for _, item in ipairs(menu) do
        local t = item.text_func and item.text_func() or item.text
        if t and t:sub(1, #prefix) == prefix then return item end
    end
end
local function setValue(aw, label, value, nightmode)
    local item = entry(aw:getWarmthMenu(), label)
    check(item, "menu entry " .. label .. " exists")
    local before = #shown
    item.callback({})
    local spinner = shown[#shown]
    check(#shown == before + 1 and spinner.value_max == 100, label .. ": spinner shown")
    if nightmode ~= nil then aw.night_mode_check_box.checked = nightmode end
    spinner.callback({ value = value })
end

-- 1. Upstream behaviour: mirror (so the harness detects the difference).
do
    store = {}; shown = {}
    local ui = newUI()
    local aw = AutoWarmth:new{ ui = ui }
    local item = entry(orig_getWarmthMenu(aw), "Sunset and sunrise")
    check(item, "upstream: combined entry exists")
    item.callback({})
    shown[#shown].callback({ value = 33 })
    check(aw.warmth[5] == 33 and aw.warmth[7] == 33, "upstream mirrors sunrise onto sunset")
end

-- 2. Patched, easy mode.
local ui = build(true)
local aw = ui.autowarmth
check(aw.getWarmthMenu ~= orig_getWarmthMenu, "instance method replaced")
check(AutoWarmth.getWarmthMenu == orig_getWarmthMenu, "class method untouched")
local menu = aw:getWarmthMenu()
check(#menu == 7, "easy mode: 7 items, got " .. #menu)
check(entry(menu, "Sunrise") and entry(menu, "Sunset") and entry(menu, "Civil dawn") and entry(menu, "Civil dusk")
      and entry(menu, "Solar noon"), "easy mode: separate sunrise/sunset/civil entries")
check(not entry(menu, "Nautical") and not entry(menu, "Solar midnight"), "easy mode hides expert entries")
check(not entry(menu, "Sunset and sunrise"), "combined entry gone")
for _, item in ipairs(menu) do check(item.mode == nil, "mode field tidied") end

-- 3. Independent values.
sched_calls, update_calls = 0, 0
setValue(aw, "Sunrise", 10)
check(aw.warmth[5] == 10 and aw.warmth[7] == 20, "sunrise set, sunset untouched")
setValue(aw, "Sunset", 80)
check(aw.warmth[7] == 80 and aw.warmth[5] == 10, "sunset set, sunrise untouched")
setValue(aw, "Civil dawn", 30)
setValue(aw, "Civil dusk", 90)
check(aw.warmth[4] == 30 and aw.warmth[8] == 90, "civil dawn/dusk independent")
check(store.autowarmth_warmth == aw.warmth, "settings saved")
check(sched_calls == 4 and update_calls == 4, "reschedule and menu refresh per change")
check(entry(aw:getWarmthMenu(), "Sunrise").text_func() == "Sunrise: 10 %", "text shows value")

-- 4. Night mode checkbox, no mirror.
setValue(aw, "Sunset", 50, true)
check(aw.warmth[7] == 1050 and aw.warmth[5] == 10, "night mode flag added to sunset only")
check(entry(aw:getWarmthMenu(), "Sunset").text_func() == "Sunset: 50 % + \226\152\190", "night mode text")
setValue(aw, "Sunset", 50, false)
check(aw.warmth[7] == 50, "night mode flag removed")

-- 5. Expert mode.
aw.easy_mode = false
menu = aw:getWarmthMenu()
check(#menu == 13, "expert mode: 13 items, got " .. #menu)
check(entry(menu, "Nautical dawn") and entry(menu, "Nautical dusk") and entry(menu, "Astronomical dawn")
      and entry(menu, "Astronomical dusk") and entry(menu, "Solar midnight (previous day)")
      and entry(menu, "Solar midnight:"), "expert entries present")
setValue(aw, "Nautical dusk", 70)
check(aw.warmth[9] == 70 and aw.warmth[3] == 80, "nautical dusk independent of nautical dawn")

-- 6. Night-mode-only control: ConfirmBox path.
aw.control_warmth = false
menu = aw:getWarmthMenu()
local item = entry(menu, "Sunrise")
check(item.text_func() == "Sunrise: \226\152\188", "night-mode-only text")
item.callback({})
local box = shown[#shown]
check(box.ok_callback and box.cancel_callback, "confirm box shown")
box.ok_callback()
check(aw.warmth[5] == 1010 and aw.warmth[7] == 50, "night mode on for sunrise only")
box.cancel_callback()
check(aw.warmth[5] == 10, "night mode off again")

-- 7. AutoWarmth disabled: nothing to patch, no error.
local ok, err = pcall(build, false)
check(ok, "no autowarmth: patch is a no-op (" .. tostring(err) .. ")")

print(string.format("%d checks, %d failed", checks, failed))
os.exit(failed == 0 and 0 or 1)
