param(
    [string]$demo = "$env:DEMO",
    [string]$samplesRoot = "/home/samples",
    [string]$demosRoot = "$samplesRoot/demos",
    [string]$demoPath = "$demosRoot/$demo"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

if (Test-Path -Path "$demoPath/generate-data.ps1") {
    & $demoPath/generate-data.ps1
}