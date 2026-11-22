-- Entry point. Configs in include/, scripts in scripts/.
-- bindings.lua next to this file is personal and optional: no file, no problem.

require("include.autostart")
require("include.settings")
require("include.binds")
require("include.rules")

-- Loaded last, so its binds override the rest.
-- searchpath, not pcall: real errors inside the file are not swallowed.
if package.searchpath("bindings", package.path) then
    require("bindings")
end
