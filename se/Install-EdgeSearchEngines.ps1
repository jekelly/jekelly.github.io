#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$baseUrl = 'https://www.jkly.me/se'
$directory = Join-Path $env:LOCALAPPDATA ('EdgeSearchEngines\' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $directory | Out-Null
Write-Host "Saved to $directory"

foreach ($file in 'Manage-EdgeSearchEngines.ps1', 'managed-search-engines.json') {
    Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/$file" -OutFile (Join-Path $directory $file)
}

& (Join-Path $directory 'Manage-EdgeSearchEngines.ps1') -Confirm
