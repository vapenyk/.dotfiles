-- Environment, autostart, monitor, appearance, input.

-- Cursor
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm app -t service -u mshell.service -p Restart=on-failure -- qs -dn -c mshell")
    hl.exec_cmd("uwsm app -t service -u vicinae-uwsm.service -p Restart=on-failure -- vicinae server")
end)

-- Monitor
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1.5,
})

hl.config({ render = { cm_auto_hdr = 0 } })

-- Window layout and appearance
hl.config({
    general = {
        gaps_in = 2,
        gaps_out = 8,
        border_size = 2,
        ["col.active_border"] = "rgb(b8cacd)",   -- primary
        ["col.inactive_border"] = "rgb(464747)", -- outlineVariant
        resize_on_border = true,
        layout = "dwindle",
    },
    dwindle = {
        preserve_split = true,
        smart_split = false,
        force_split = 2,
    },
    decoration = {
        rounding = 14,
        blur = {
            enabled = true,
            size = 10,
            passes = 3,
        },
        shadow = { enabled = true },
    },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = "rgb(1f2020)", -- surface
        focus_on_activate = true,
    },
})

-- Behavior and session
hl.config({
    misc = {
        key_press_enables_dpms = true,
        mouse_move_enables_dpms = true,
        disable_watchdog_warning = true,
        disable_hyprland_guiutils_check = true,
    },
    xwayland = { force_zero_scaling = true },
    ecosystem = { no_update_news = true, no_donation_nag = true },
})

-- Animations
hl.config({
    animations = { enabled = false },
})

-- Keyboard, touchpad and mouse
hl.config({
    input = {
        touchpad = {
            natural_scroll = false,
            tap_to_click = true,
        },
        kb_layout = "us,ru,ua",
        kb_options = "grp:caps_toggle",
        repeat_delay = 250,
        repeat_rate = 40,
        numlock_by_default = false,
    },
})

hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})
