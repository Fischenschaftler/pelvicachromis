param([Parameter(Mandatory=$true)][string]$Godot, [switch]$PrepareOnly)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$target = Join-Path $projectRoot 'dist/PelvicachromisStudio'
foreach ($name in @('projects','data','config','logs')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $target $name) | Out-Null
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/PORTABLE_README.txt') -Destination (Join-Path $target 'README.txt')
if (-not $PrepareOnly) {
    & $Godot --headless --path $projectRoot --export-release 'Windows Portable' (Join-Path $target 'PelvicachromisStudio.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Export fehlgeschlagen. Passende Godot-Exportvorlagen prüfen.' }
}
Write-Output $target
