-- All binds: launch, windows, workspaces, media, clipboard, gestures.

local mainMod     = "SUPER"

local terminal    = "uwsm app -- xdg-terminal-exec"
local fileManager = "nautilus"
local menu        = "vicinae toggle"

-- Launchers
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + SHIFT + code:201", hl.dsp.exec_cmd(menu))

hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("qs -c mshell ipc call lock lock"))

-- System menus
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("vicinae vicinae://launch/clipboard/history"))
hl.bind("ALT + SPACE", hl.dsp.exec_cmd('"$HOME/.config/hypr/scripts/pkg-vicinae.sh"'))

-- Screenshots
hl.bind("Print", hl.dsp.exec_cmd('bash "$HOME/.config/hypr/scripts/screenshot.sh" region'))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd('bash "$HOME/.config/hypr/scripts/screenshot.sh" full'))

-- Window controls
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- Workspaces
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Mouse drag and resize
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind(mainMod .. " + equal", hl.dsp.window.resize({ x = 40, y = 0, relative = true }),
    { repeating = true, description = "Grow window width by 40" })
hl.bind(mainMod .. " + minus", hl.dsp.window.resize({ x = -40, y = 0, relative = true }),
    { repeating = true, description = "Shrink window width by 40" })
hl.bind(mainMod .. " + SHIFT + equal", hl.dsp.window.resize({ x = 0, y = 40, relative = true }),
    { repeating = true, description = "Grow window height by 40" })
hl.bind(mainMod .. " + SHIFT + minus", hl.dsp.window.resize({ x = 0, y = -40, relative = true }),
    { repeating = true, description = "Shrink window height by 40" })

-- Volume and brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("qs -c mshell ipc call osd volumeUp"),
    { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("qs -c mshell ipc call osd volumeDown"),
    { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("qs -c mshell ipc call osd toggleMute"),
    { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
    { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("qs -c mshell ipc call osd brightnessUp"),
    { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("qs -c mshell ipc call osd brightnessDown"),
    { locked = true, repeating = true })

-- Media playback
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

------------------------------------------------------------------------
-- Unified clipboard (like Omarchy)
-- Super+A/C/X/V; in terminals (the "terminal" tag from rules.lua) copy/paste
-- = Ctrl+Shift+C/V. Keys are sent by keycode (code:N) instead of a letter name:
-- a name is looked up in the ACTIVE layout, so with ru/ua active "C" is "key not found".
-- Key down, then up after 50 ms: works around stuck synthetic keys.
------------------------------------------------------------------------
local KEY = { A = "code:38", X = "code:53", C = "code:54", V = "code:55" }

local function send_once(mods, key)
    key = KEY[key] or key
    return function()
        hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
        hl.timer(function()
            hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
        end, { timeout = 50, type = "oneshot" })
    end
end

local function active_is_terminal()
    local w = hl.get_active_window()
    if not w then return false end
    for _, tag in ipairs(w.tags or {}) do
        if tag:gsub("%*$", "") == "terminal" then return true end
    end
    return false
end

local function universal(def_mods, def_key, term_mods, term_key)
    return function()
        if active_is_terminal() then
            send_once(term_mods, term_key)()
        else
            send_once(def_mods, def_key)()
        end
    end
end

hl.bind(mainMod .. " + A", send_once("CTRL", "A"))                    -- select all
hl.bind(mainMod .. " + C", universal("CTRL", "C", "CTRL SHIFT", "C")) -- copy
hl.bind(mainMod .. " + X", send_once("CTRL", "X"))                    -- cut
hl.bind(mainMod .. " + V", universal("CTRL", "V", "CTRL SHIFT", "V")) -- paste

------------------------------------------------------------------------
-- Gestures
------------------------------------------------------------------------

-- 3-finger + Super + swipe up -> fullscreen
hl.gesture({
    fingers   = 3,
    direction = "up",
    mods      = mainMod,
    action    = "fullscreen",
})

-- 3-finger swipe left/right -> next / previous track
hl.gesture({
    fingers   = 3,
    direction = "left",
    action    = function() hl.exec_cmd("playerctl next") end,
})

hl.gesture({
    fingers   = 3,
    direction = "right",
    action    = function() hl.exec_cmd("playerctl previous") end,
})

-- Touchpad names as Hyprland sees them (lowercase, spaces -> dashes),
-- read from the kernel, so nothing is hardcoded per machine.
local function touchpads()
    local list = {}
    local f = io.open("/proc/bus/input/devices", "r")
    if not f then return list end
    for line in f:lines() do
        local name = line:match('^N: Name="(.-)"')
        if name and name:lower():find("touchpad", 1, true) then
            list[#list + 1] = (name:lower():gsub("%s", "-"))
        end
    end
    f:close()
    return list
end

-- 3-finger tap -> play/pause (touchpad only, ignores mouse wheel).
local pads = touchpads()
if #pads > 0 then
    hl.bind("mouse:274", hl.dsp.exec_cmd("playerctl play-pause"), {
        device = {
            inclusive = true,
            list = pads,
        },
    })
end

-- 3-finger vertical swipe -> system volume (live)
local function volume_gesture(change)
    if change ~= 0 then
        local points = string.format("%.6f", change):gsub(",", ".")
        hl.exec_cmd("qs -c mshell ipc call osd adjustVolume -- " .. points)
    end
end

hl.gesture({
    fingers   = 3,
    direction = "vertical",
    action    = {
        start  = function(e) volume_gesture(-0.50 * e.delta.y) end,
        update = function(e) volume_gesture(-0.50 * e.delta.y) end,
    },
})
