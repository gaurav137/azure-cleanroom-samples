param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("analytics")]
    [string]$demo,

    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",
    [string]$kekName = $($($(New-Guid).Guid) -replace '-').ToLower(),

    [string]$samplesRoot = "/home/samples",
    [string]$publicDir = "$samplesRoot/demo-resources/public",
    [string]$privateDir = "$samplesRoot/demo-resources/private",
    [string]$demosRoot = "$samplesRoot/demos",

    [string]$contractConfig = "$privateDir/$resourceGroup-$demo.generated.json",
    [string]$contractFragment = "$publicDir/$persona-$demo.config",
    [string]$environmentConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$secretstoreConfig = "$privateDir/secretstores.config",
    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$queryPath = "$demosRoot/$demo/query/$persona",
    [string]$cgsClient = "azure-cleanroom-samples-governance-client-$persona"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

$queryDocumentId = Get-Content $publicDir/analytics.query-id
Write-Log OperationStarted `
    "Approving query '$queryDocumentId' for '$persona' in the '$demo' demo..."
$proposalId = (az cleanroom governance user-document show `
        --id $queryDocumentId `
        --governance-client $cgsClient `
        --query "proposalId" `
        --output tsv)
az cleanroom governance user-document vote `
    --id $queryDocumentId `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $cgsClient

Write-Log OperationCompleted `
    "Query approved by '$persona'."