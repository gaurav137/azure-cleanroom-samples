param(
    [string]$persona = "$env:PERSONA",
    [string]$cgsClient = "azure-cleanroom-samples-governance-client-$persona"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

$info = az cleanroom governance client show-deployment --name $cgsClient | ConvertFrom-Json
Write-Log OperationCompleted `
    "Open $($info.uiLink) in your browser to access the governance portal for '$persona' persona."
