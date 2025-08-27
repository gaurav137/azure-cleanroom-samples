param(
    [string]$demo = "$env:DEMO",

    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$samplesRoot = "/home/samples",
    [string]$publicDir = "$samplesRoot/demo-resources/public",
    [string]$privateDir = "$samplesRoot/demo-resources/private",
    [string]$secretDir = "$samplesRoot/demo-resources/secret",
    [string]$demosRoot = "$samplesRoot/demos",
    [string]$sa = "",
    [string]$awsProfileName = "default",
    [string]$cgsClient = "azure-cleanroom-samples-governance-client-$persona",

    [string]$environmentConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$secretstoreConfig = "$privateDir/secretstores.config",
    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$datastoreDir = "$privateDir/datastores",
    [string]$demoPath = "$demosRoot/$demo",
    [string]$datasourcePath = "$demoPath/datasource/$persona",
    [string]$datasinkPath = "$demoPath/datasink/$persona"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

if (Test-Path -Path "$demoPath/generate-data.ps1") {
    & $demoPath/generate-data.ps1
}