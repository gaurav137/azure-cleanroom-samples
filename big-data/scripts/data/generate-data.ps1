param(
    [string]$demo = "$env:DEMO",
    [string]$samplesRoot = "/home/samples",
    [string]$demosRoot = "$samplesRoot/demos",
    [string]$demoPath = "$demosRoot/$demo",
    [datetime]$dataStartDate = [datetime]"2025-09-01"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

if (Test-Path -Path "$demoPath/generate-data.ps1") {
    & $demoPath/generate-data.ps1 -dataStartDate $dataStartDate
}
else {
    Write-Log Error `
        "No generate-data.ps1 script found for demo '$demo'."
    throw "No generate-data.ps1 script found for demo '$demo'."
}