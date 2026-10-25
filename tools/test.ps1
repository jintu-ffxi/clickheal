# Runs every ClickHeal test. From the repository root:  .\tools\test.ps1
# Needs a Lua interpreter on PATH (Lua 5.1-5.4 or LuaJIT). On Windows:  scoop install lua   or   choco install lua
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$lua = (Get-Command lua, luajit, lua5.4, lua54 -ErrorAction SilentlyContinue | Select-Object -First 1)
if (-not $lua) {
    Write-Host 'No Lua interpreter found on PATH. Install one (scoop install lua) and try again.' -ForegroundColor Red
    exit 2
}

Write-Host "Using $($lua.Source)`n"
$failed = 0
foreach ($t in 'tests/run.lua', 'tests/smoke_ashita.lua') {
    Write-Host "== $t" -ForegroundColor Cyan
    & $lua.Source $t
    if ($LASTEXITCODE -ne 0) { $failed++ }
}
if ($failed -gt 0) { Write-Host "`n$failed test file(s) failed." -ForegroundColor Red; exit 1 }
Write-Host "`nAll tests passed." -ForegroundColor Green
