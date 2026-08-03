-- Luacheck configuration for Bones.
--
-- The gate that earns its keep is the undefined-GLOBAL check: a `local function`
-- referenced before it is defined resolves to a nil global, and nothing fails
-- until that path runs. Our own code (src/, states/, main.lua, conf.lua) is
-- strict; vendored libraries and the tests get latitude.

std = "max"          -- Lua 5.1–5.4 + LuaJIT built-ins (the tests target all)

globals = { "love" } -- injected by the framework; a LÖVE app sets its callbacks

ignore = {
    "211", "212", "213", "231", "241",   -- unused / write-only locals & args
    "311",                               -- value assigned never used
    "411", "412", "421", "431",          -- redefinitions & shadowing
    "512", "542", "581",                 -- loop-once / empty-if / boolean spelling
    "611", "612", "614", "621", "631",   -- whitespace / indent / line length
}

max_line_length = false

-- Vendored third-party libraries are not ours to lint.
exclude_files = {
    "lib/",
    "docs/",
}

files["tests/"] = {
    ignore = { "111", "121", "122", "331", "411", "412", "413" },
}
