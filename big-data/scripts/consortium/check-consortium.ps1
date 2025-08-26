param(
    [string]$persona = "$env:PERSONA",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources/private",

    [string]$ccfProviderClient = "azure-cleanroom-samples-ccf-provider"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

Test-AzureAccessToken 1>$null

$ccfName = $persona + "-ccf"

$ccf = & {
    # Disable $PSNativeCommandUseErrorActionPreference for this scriptblock
    $PSNativeCommandUseErrorActionPreference = $false
    return (az cleanroom ccf network show `
            --name $ccfName `
            --provider-config $privateDir/ccfProviderConfig.json `
            --provider-client $ccfProviderClient | ConvertFrom-Json)
}

if ($null -eq $ccf) {
    Write-Log Warning `
        "No consortium '$ccfName' exists."
}
else {
    Write-Log Verbose `
        "Found existing CCF network '$ccfName'."
    $health = (az cleanroom ccf network show-health `
            --name $ccfName `
            --provider-config $privateDir/ccfProviderConfig.json `
            --provider-client $ccfProviderClient | ConvertFrom-Json)
    if ($health.nodeHealth[0].status -eq "Ok") {
        Write-Log OperationCompleted "CCF network is up."
    }
    elseif ($health.nodeHealth[0].status -eq "NeedsReplacement") {
        $health | ConvertTo-Json -Depth 100 | jq
        Write-Log Error "CCF network needs to be recovered. Run start-consortium.ps1 to recover the network."
    }
}
