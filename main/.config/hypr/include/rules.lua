-- Window and layer rules.
local TRANSPARENT_APPS = false

------------------------------------------------------------------------
-- Global
------------------------------------------------------------------------

-- Apps cannot maximize themselves behind the compositor's back.
hl.window_rule({
    name           = "suppress-maximize",
    match          = { class = ".*" },
    suppress_event = "maximize",
})

-- Fix some dragging issues with XWayland (empty class/title floating ghost windows).
hl.window_rule({
    name     = "xwayland-drag-fix",
    match    = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

------------------------------------------------------------------------
-- Tags: browsers, terminals, floating dialogs, PiP
------------------------------------------------------------------------

hl.window_rule({
    name   = "pkg-hub",
    match  = { class = "^org\\.pkg\\.hub$" },
    float  = true,
    center = true,
    size   = { 1100, 650 },
})

hl.window_rule({
    name  = "tag-chromium-browser",
    match = { class = "((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)" },
    tag   = "+chromium-based-browser",
})
hl.window_rule({
    name  = "tag-firefox-browser",
    match = { class = "([fF]irefox|zen|librewolf)" },
    tag   = "+firefox-based-browser",
})
hl.window_rule({
    name  = "browser-always-tile",
    match = { tag = "chromium-based-browser" },
    tile  = true,
})

-- Video web apps: drop the browser tag so they can float.
hl.window_rule({
    name  = "video-apps-untag-browser",
    match = { class = "(^.+-youtube\\.com__.*$|^.+-app\\.zoom\\.us__wc_home.*$)" },
    tag   = "-chromium-based-browser",
})

-- Hide screen sharing notification windows.
hl.window_rule({
    name      = "hide-sharing-notification",
    match     = { title = ".*is sharing.*" },
    workspace = "special silent",
})

-- Terminal tag, so rules and binds can single terminals out.
hl.window_rule({
    name  = "tag-terminal",
    match = { class = "(Alacritty|kitty|com\\.mitchellh\\.ghostty|foot|org\\.codeberg\\.dnkl\\.foot|wezterm|org\\.wezfurlong\\.wezterm|org\\.gnome\\.Ptyxis|com\\.raggesilver\\.BlackBox|org\\.kde\\.konsole|org\\.gnome\\.Terminal|org\\.pkg\\.hub)" },
    tag   = "+terminal",
})

-- Apps that always float like dialogs.
hl.window_rule({
    name  = "tag-floating-apps",
    match = { class = "(org\\.gnome\\.NautilusPreviewer|org\\.gnome\\.Papers|imv|mpv)" },
    tag   = "+floating-window",
})

-- The portal only ever shows dialogs (file pickers, screen shares, permission prompts),
-- so all of its windows get the floating treatment whatever they are titled.
hl.window_rule({
    name  = "tag-portal-gtk",
    match = { class = "xdg-desktop-portal-gtk" },
    tag   = "+floating-window",
})

-- Open/save dialogs drawn by the apps themselves.
hl.window_rule({
    name  = "tag-app-file-dialogs",
    match = {
        class = "(sublime_text|DesktopEditors|org\\.gnome\\.Nautilus)",
        title =
        "^(Open.*Files?|Open [Ff]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to (open|save).*|[Cc]hoose.*)",
    },
    tag   = "+floating-window",
})

-- Picture-in-picture overlays.
hl.window_rule({
    name  = "tag-pip",
    match = { title = "(Picture.?in.?[Pp]icture)" },
    tag   = "+pip",
})

------------------------------------------------------------------------
-- Tag consumers
------------------------------------------------------------------------

hl.window_rule({
    name   = "floating-window",
    match  = { tag = "floating-window" },
    float  = true,
    center = true,
    size   = { 875, 600 },
})

hl.window_rule({
    name              = "pip",
    match             = { tag = "pip" },
    float             = true,
    pin               = true,
    size              = { 600, 338 },
    keep_aspect_ratio = true,
    border_size       = 0,
    move              = { "(monitor_w-window_w-40)", "(monitor_h*0.04)" },
})

-- Google Meet PiP uses the meeting title instead of "Picture-in-Picture".
hl.window_rule({
    name              = "meet-pip",
    match             = { tag = "chromium-based-browser", title = "^Meet - .+" },
    float             = true,
    pin               = true,
    size              = { 600, 338 },
    keep_aspect_ratio = true,
    border_size       = 0,
    move              = { "(monitor_w-window_w-40)", "(monitor_h-window_h-40)" },
})

-- Add the `noidle` tag to any window (hyprctl dispatch tagwindow noidle) to block idle while it is open.
hl.window_rule({
    name         = "noidle",
    match        = { tag = "noidle" },
    idle_inhibit = "always",
})

------------------------------------------------------------------------
-- Apps
------------------------------------------------------------------------

-- PeaZip: always floating, not tiled.
hl.window_rule({
    name   = "peazip",
    match  = { class = "^[pP]ea[zZ]ip$" },
    float  = true,
    center = true,
    size   = { 1000, 650 },
})

-- Telegram: do not steal focus on new messages.
hl.window_rule({
    name              = "telegram-no-focus-stealing",
    match             = { class = "org.telegram.desktop" },
    focus_on_activate = false,
})

-- 1Password 8.12 renamed its app id to reverse-DNS, so match both.
hl.window_rule({
    name            = "1password",
    match           = { class = "^(1[pP]assword|com\\.onepassword\\.OnePassword)$" },
    no_screen_share = true,
    tag             = "+floating-window",
})

-- Bitwarden desktop app.
hl.window_rule({
    name            = "bitwarden",
    match           = { class = "^([bB]itwarden)$" },
    no_screen_share = true,
    tag             = "+floating-window",
})

-- Bitwarden browser extension popout: it asks for its own width/height, so no shared 875x600.
-- The class varies by browser, profile and popup path.
hl.window_rule({
    name            = "bitwarden-extension-popout",
    match           = { class = ".*nngceckbapebfimnlniiiahkandclblb.*" },
    no_screen_share = true,
    float           = true,
    center          = true,
})

-- Steam.
hl.window_rule({
    name         = "steam",
    match        = { class = "steam" },
    float        = true,
    idle_inhibit = "fullscreen",
})
hl.window_rule({
    name   = "steam-main",
    match  = { class = "steam", title = "Steam" },
    center = true,
    size   = { 1100, 700 },
})
hl.window_rule({
    name  = "steam-friends",
    match = { class = "steam", title = "Friends List" },
    size  = { 460, 800 },
})

-- Battle.net runs under Proton; all its windows share the class steam_app_battlenet.
hl.window_rule({
    name   = "battlenet-launcher",
    match  = { class = "^steam_app_battlenet$", title = "^Battle\\.net$" },
    float  = true,
    center = true,
    size   = { 1280, 800 },
})
-- Installer: no decorations, blur or shadow around the Blizzard chrome.
hl.window_rule({
    name      = "battlenet-setup",
    match     = { class = "^steam_app_battlenet$", title = "^Battle\\.net Setup$" },
    decorate  = false,
    no_blur   = true,
    no_shadow = true,
})

-- DaVinci Resolve window focus handling.
hl.window_rule({
    name            = "davinci-resolve",
    match           = { class = ".*[Rr]esolve.*" },
    float           = true,
    stay_focused    = true,
    -- Prevent modal dialog pointer warps when focus follows the mouse.
    no_follow_mouse = true,
})
hl.window_rule({
    name       = "davinci-resolve-main",
    match      = { class = ".*[Rr]esolve.*", title = "^DaVinci Resolve( Studio)? - .+$" },
    fullscreen = true,
})
-- Resolve exposes the Voiceover panel under the generic "Dialog" title.
hl.window_rule({
    name         = "davinci-resolve-dialogs",
    match        = {
        class = ".*[Rr]esolve.*",
        title = "^(DaVinci Resolve( Studio)? - .+|Project Manager|Preferences|Find Directory|Dialog)$",
    },
    stay_focused = false,
})

-- Inkscape draws its file choosers itself, so the portal rule never sees them.
hl.window_rule({
    name  = "inkscape-file-dialogs",
    match = {
        class = "^org\\.inkscape\\.Inkscape$",
        title = "^Select file to (import|open|save to|save a copy to)$",
    },
    tag   = "+floating-window",
})

-- JetBrains IDEs: no focus on mouse hover.
hl.window_rule({
    name            = "jetbrains-no-follow-mouse",
    match           = { class = "^(jetbrains-.*)$" },
    no_follow_mouse = true,
})

-- LocalSend and its share window.
hl.window_rule({
    name   = "share-window",
    match  = { class = "Share" },
    float  = true,
    center = true,
})
hl.window_rule({
    name   = "localsend",
    match  = { class = "(org\\.localsend\\.)?localsend(_app)?" },
    float  = true,
    center = true,
    size   = { 1100, 700 },
})

-- Satty (screenshot editor): floating, centered.
hl.window_rule({
    name   = "satty",
    match  = { class = "^com\\.gabm\\.satty$" },
    float  = true,
    center = true,
    size   = { 1100, 700 },
})

-- Game streaming / emulation: fullscreen and keep the screen awake.
hl.window_rule({
    name         = "geforce-now",
    match        = { class = "GeForceNOW" },
    idle_inhibit = "fullscreen",
})
hl.window_rule({
    name         = "moonlight",
    match        = { class = "com.moonlight_stream.Moonlight" },
    fullscreen   = true,
    idle_inhibit = "fullscreen",
})
hl.window_rule({
    name         = "retroarch",
    match        = { class = "com.libretro.RetroArch" },
    fullscreen   = true,
    idle_inhibit = "fullscreen",
})

------------------------------------------------------------------------
-- Transparency (opt-in, see TRANSPARENT_APPS at the top)
------------------------------------------------------------------------
if TRANSPARENT_APPS then
    local opacity = "0.985 0.96"
    local function transparent(name, match)
        hl.window_rule({ name = name, match = match, opacity = opacity })
    end
    transparent("transparent-terminals", { tag = "terminal" })
    transparent("transparent-apps", { class = "(1[pP]assword|com\\.onepassword\\.OnePassword|org\\.gnome\\.Nautilus)" })
    transparent("transparent-localsend", { class = "(org\\.localsend\\.)?localsend(_app)?" })
    -- Add the `transparent` tag to any window to opt it in.
    transparent("transparent-tagged", { tag = "transparent" })
end

-- Show and hide the launcher layer immediately.
hl.layer_rule({
    name = "glass-launcher-no-animation",
    match = { namespace = "glass-launcher" },
    no_anim = true,
})


-- Blur and disable animations for Vicinae windows.
hl.layer_rule({
    name         = "vicinae-blur",
    match        = { namespace = "vicinae" },
    blur         = true,
    ignore_alpha = 0,
})

hl.layer_rule({
    name    = "vicinae-no-animation",
    match   = { namespace = "vicinae" },
    no_anim = true,
})
