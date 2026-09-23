$ErrorActionPreference = 'Stop'
$zip = Join-Path $env:TEMP 'opies-plugin-hut.zip'
$dest = Join-Path $env:TEMP 'opies-plugin-hut'
$uri = 'https://github.com/opesoid/opies-plugin-hut/archive/refs/heads/dev.zip'
Invoke-WebRequest -Uri $uri -OutFile $zip -UseBasicParsing
if (Test-Path -LiteralPath $dest) {
    Remove-Item -LiteralPath $dest -Recurse -Force
}
Expand-Archive -Path $zip -DestinationPath $dest -Force
$root = Get-ChildItem -LiteralPath $dest -Directory | Select-Object -First 1
if ($null -eq $root) {
    throw 'Could not unpack the plugin hut.'
}
$setup = Join-Path $root.FullName 'installer\OpiesPluginLibrary-Setup.vbs'
if (-not (Test-Path -LiteralPath $setup)) {
    throw "Missing setup file: $setup"
}
Start-Process -FilePath 'wscript.exe' -ArgumentList @('//nologo', $setup)
