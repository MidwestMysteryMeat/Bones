-- Static analysis config for Bones.
--
--   luacheck .          -- must exit with 0 errors; run before every commit
--
-- A meaningful gate, not a wall of noise: anything that can crash or silently
-- misbehave fails. Cosmetic codes are muted below with stated reasons.

std = "lua51+love"
cache = true
codes = true

exclude_files = {
    "assets/**",
    -- Vendored third-party libraries: hump (Matthias Richter), sock.lua
    -- (camchenry), anim8, flux, bitser. Not ours to restyle, and their
    -- deliberate global registration (class_commons, bitser) is not a defect.
    "lib/**",
}

ignore = {
    "211",  -- unused local
    "212",  -- unused argument (interface-conformance stubs)
    "213",  -- unused loop variable, idiomatic in `for _, v in ipairs(...)`
    "542",  -- empty if branch, used as explicit "do nothing" markers
    "421",  -- shadowing a local
}

-- Predates any line-length rule; reflowing wide data tables risks breaking
-- string literals for no functional gain.
max_line_length = false

files["main.lua"] = { allow_defined_top = true }
files["conf.lua"] = { globals = { "love" } }
files["tests/**"] = { allow_defined_top = true, globals = { "love" } }
