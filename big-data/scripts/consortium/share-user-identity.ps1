param(
    [string]$persona = "$env:PERSONA",
    [Parameter(Mandatory = $true)]
    [string]$email,

    [string]$samplesRoot = "/home/samples",
    [string]$publicDir = "$samplesRoot/demo-resources/public"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

# Share the email address to invite.
$email | Out-File "$publicDir/$persona.email"
Write-Log OperationCompleted `
    "Shared email ID '$email' for '$persona' at '$publicDir/$persona.email'."
