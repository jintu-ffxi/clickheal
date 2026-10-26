# Builds the release zip: dist\clickheal-<version>.zip, laid out so it unzips straight into Ashita's folder
# (addons\clickheal\...), with the README, LICENSE and CHANGELOG beside it. From the repository root:  .\tools\release.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$ver = (Select-String -Path 'addons\clickheal\clickheal.lua' -Pattern "addon\.version\s*=\s*'([^']+)'").Matches[0].Groups[1].Value
$stage = Join-Path $env:TEMP "clickheal-release-$ver"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Path "$stage\addons" | Out-Null
Copy-Item -Recurse 'addons\clickheal' "$stage\addons\clickheal"
Copy-Item 'README.md', 'LICENSE', 'CHANGELOG.md' $stage
Copy-Item -Recurse 'media' "$stage\media"

New-Item -ItemType Directory -Force 'dist' | Out-Null
$zip = "dist\clickheal-$ver.zip"
if (Test-Path $zip) { Remove-Item $zip }
# Built by hand so entry names use forward slashes (Compress-Archive in Windows PowerShell 5.1 writes backslashes).
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$full = Join-Path (Get-Location) $zip
$arc = [System.IO.Compression.ZipFile]::Open($full, 'Create')
foreach ($f in Get-ChildItem -Recurse -File $stage) {
    $name = $f.FullName.Substring($stage.Length + 1).Replace([char]92, [char]47)
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($arc, $f.FullName, $name)
}
$arc.Dispose()
Remove-Item -Recurse -Force $stage
Write-Host "wrote $zip"
