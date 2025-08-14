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

Write-Log OperationStarted `
    "Creating query documents in CCF for '$persona' in the '$demo' demo..."

$instanceId = (New-Guid).ToString().Substring(0, 8)
if (Test-Path -Path $queryPath) {
    $dirs = Get-ChildItem -Path $queryPath -Directory -Name
    foreach ($dir in $dirs) {
        $queryName = "$("$persona-$dir".ToLower())-$instanceId"
        $query = Get-Content "$queryPath/$dir/query.txt"
        $queryDocument = [ordered]@{
            "query"    = "$query"
            "datasets" = [ordered]@{
                "publisher_data" = $(Get-Content "$publicDir/northwind-input.dataset-id")
                "consumer_data"  = $(Get-Content "$publicDir/woodgrove-input.dataset-id")
            }
            "datasink" = $(Get-Content "$publicDir/woodgrove-output.dataset-id")
        }
        $queryDocumentId = $queryName
        $documentApprovers = , @(
            @{
                "id"   = "$(az cleanroom governance client show --name "azure-cleanroom-samples-governance-client-northwind" --query userTokenClaims.oid -o tsv)"
                "type" = "user"
            },
            @{
                "id"   = "$(az cleanroom governance client show --name "azure-cleanroom-samples-governance-client-woodgrove" --query userTokenClaims.oid -o tsv)"
                "type" = "user"
            }
        ) | ConvertTo-Json -Depth 100
        $contractId = Get-Content $publicDir/analytics.contract-id
        Write-Log Verbose `
            "Proposing '$queryName' query document with approvers as $documentApprovers..."
        az cleanroom governance user-document create `
            --data $($queryDocument | ConvertTo-Json -Depth 100)`
            --id $queryDocumentId `
            --approvers $documentApprovers `
            --contract-id $contractId `
            --governance-client $cgsClient
        $version = (az cleanroom governance user-document show `
                --id $queryDocumentId `
                --governance-client $cgsClient `
                --query "version" `
                --output tsv)
        $proposalId = (az cleanroom governance user-document propose `
                --version $version `
                --id $queryDocumentId `
                --governance-client $cgsClient `
                --query "proposalId" `
                --output tsv)
        $queryDocumentId | Out-File $publicDir/analytics.query-id

        Write-Log OperationCompleted `
            "Query document '$queryName' is proposed in CCF. ProposalId: $proposalId."
    }
}
else {
    Write-Log Warning `
        "No query specified for persona '$persona' in demo '$demo'."
}

