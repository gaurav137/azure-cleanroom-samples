param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("analytics", "analytics-s3")]
    [string]$demo,

    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$samplesRoot = "/home/samples",
    [string]$publicDir = "$samplesRoot/demo-resources/public",
    [string]$privateDir = "$samplesRoot/demo-resources/private",
    [string]$demosRoot = "$samplesRoot/demos",

    [string]$contractFragment = "$privateDir/$persona-$demo.config",
    [string]$datasourcePath = "$demosRoot/$demo/datasource/$persona",
    [string]$datasinkPath = "$demosRoot/$demo/datasink/$persona",
    [string]$cgsClient = "azure-cleanroom-samples-governance-client-$persona"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

Write-Log OperationStarted `
    "Creating dataset documents in CCF for the datasources and datasinks for '$persona' in the '$demo' demo..."

$instanceId = (New-Guid).ToString().Substring(0, 8)
if (Test-Path -Path $datasourcePath) {
    $dirs = Get-ChildItem -Path $datasourcePath -Directory -Name
    foreach ($dir in $dirs) {
        $datasourceName = "$persona-$dir".ToLower()
        $datasetName = "$datasourceName-$instanceId"
        $datasetDocument = [ordered]@{
            "name"        = "$datasetName"
            "format"      = "csv"
            "schema"      = $(Get-Content "$datasourcePath/$dir/schema.json" | ConvertFrom-Json)
            "accessPoint" = $(Get-Content $contractFragment | ConvertFrom-Yaml)["datasources"] | Where-Object { $_.name -eq $datasourceName }
        }
        $documentId = $datasetName
        $documentApprovers = , @(
            @{
                "id"   = "$(az cleanroom governance client show --name $cgsClient --query userTokenClaims.oid -o tsv)"
                "type" = "user"
            }
        ) | ConvertTo-Json -Depth 100
        $contractId = Get-Content $publicDir/analytics.contract-id
        Write-Log Verbose `
            "Adding '$datasetName' dataset document with approvers as $documentApprovers..."
        az cleanroom governance user-document create `
            --data $($datasetDocument | ConvertTo-Json -Depth 100)`
            --id $documentId `
            --approvers $documentApprovers `
            --contract-id $contractId `
            --governance-client $cgsClient
        $version = (az cleanroom governance user-document show `
                --id $documentId `
                --governance-client $cgsClient `
                --query "version" `
                --output tsv)
        $proposalId = (az cleanroom governance user-document propose `
                --version $version `
                --id $documentId `
                --governance-client $cgsClient `
                --query "proposalId" `
                --output tsv)
        az cleanroom governance user-document vote `
            --id $documentId `
            --proposal-id $proposalId `
            --action accept `
            --governance-client $cgsClient 1>$null

        $documentId | Out-File $publicDir/$datasourceName.dataset-id

        Write-Log OperationCompleted `
            "Published '$datasourceName' datasource as '$datasetName' dataset document in CCF."
    }
}
else {
    Write-Log Warning `
        "No input datasets required for persona '$persona' in demo '$demo'."
}

if (Test-Path -Path $datasinkPath) {
    $dirs = Get-ChildItem -Path $datasinkPath -Directory -Name
    foreach ($dir in $dirs) {
        $datasinkName = "$persona-$dir".ToLower()
        $datasetName = "$datasinkName-$instanceId"
        $datasetDocument = [ordered]@{
            "name"        = "$datasetName"
            "format"      = "csv"
            "schema"      = $(Get-Content "$datasinkPath/$dir/schema.json" | ConvertFrom-Json)
            "accessPoint" = $(Get-Content $contractFragment | ConvertFrom-Yaml)["datasinks"] | Where-Object { $_.name -eq $datasinkName }
        }
        $documentId = $datasetName
        $documentApprovers = , @(
            @{
                "id"   = "$(az cleanroom governance client show --name $cgsClient --query userTokenClaims.oid -o tsv)"
                "type" = "user"
            }
        ) | ConvertTo-Json -Depth 100
        $contractId = Get-Content $publicDir/analytics.contract-id
        Write-Log Verbose `
            "Adding '$datasetName' dataset document with approvers as $documentApprovers..."
        az cleanroom governance user-document create `
            --data $($datasetDocument | ConvertTo-Json -Depth 100)`
            --id $documentId `
            --approvers $documentApprovers `
            --contract-id $contractId `
            --governance-client $cgsClient
        $version = (az cleanroom governance user-document show `
                --id $documentId `
                --governance-client $cgsClient `
                --query "version" `
                --output tsv)
        $proposalId = (az cleanroom governance user-document propose `
                --version $version `
                --id $documentId `
                --governance-client $cgsClient `
                --query "proposalId" `
                --output tsv)
        az cleanroom governance user-document vote `
            --id $documentId `
            --proposal-id $proposalId `
            --action accept `
            --governance-client $cgsClient 1>$null

        $documentId | Out-File $publicDir/$datasinkName.dataset-id

        Write-Log OperationCompleted `
            "Published '$datasinkName' datasink as '$datasetName' dataset document in CCF."
    }
}
else {
    Write-Log Warning `
        "No output datasets required for persona '$persona' in demo '$demo'."
}
