# scripts/lint.ps1 — run luacheck the way CI does.
#
# The gate exists for the undefined-GLOBAL class: a `local function` referenced
# before it is defined resolves to a nil global, and nothing fails until that
# path runs. Our own code is strict; vendored lib/ and the tests get latitude.
# See .luacheckrc.
#
#   powershell -File scripts\lint.ps1

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$lc = Get-Command luacheck -ErrorAction SilentlyContinue
if (-not $lc) {
    Write-Host "luacheck not found on PATH. Install:  luarocks install luacheck" -ForegroundColor Yellow
    exit 2
}

& luacheck src states main.lua conf.lua tests
exit $LASTEXITCODE
