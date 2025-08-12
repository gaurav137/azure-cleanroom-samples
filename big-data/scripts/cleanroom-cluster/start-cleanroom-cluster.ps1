param(
    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",
    [string]$resourceGroupLocation = "$env:RESOURCE_GROUP_LOCATION",

    [string]$samplesRoot = "/home/samples",
    [string]$secretDir = "$samplesRoot/demo-resources/secret",
    [string]$privateDir = "$samplesRoot/demo-resources/private",
    [string]$publicDir = "$samplesRoot/demo-resources/public",

    [string]$clusterProviderClient = "azure-cleanroom-samples-cluster-provider",
    [string]$ccfEndpoint = "$publicDir/ccfEndpoint.json",

    [string]$repo = "cleanroomemuprregistry.azurecr.io",
    [string]$tag = "16749412789"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

Test-AzureAccessToken

$clusterName = $persona + "-cluster"

#
# Create a cleanroom cluster instance.
#
$subscriptionId = az account show --query id --output tsv
$tenantId = az account show --query tenantId --output tsv
@"
{
    "location": "$resourceGroupLocation",
    "subscriptionId": "$subscriptionId",
    "resourceGroupName": "$resourceGroup",
    "tenantId": "$tenantId"
}
"@  | Out-File $privateDir/providerConfig.json

# Register the ACI and AKS RP so that confidential container/AKS usage is enabled in the subscription.
$aciRpName = "Microsoft.ContainerInstance"
$aciRpRegistration = (az provider show -n $aciRpName --query registrationState --output tsv)
if ($aciRpRegistration -ne "Registered") {
    Write-Log Verbose `
        "$aciRpName provider is not registered on the subscription. Registering provider (this can take a while)..."
    az provider register --namespace $aciRpName --wait
    Write-Log OperationCompleted `
        "$aciRpName provider is registered."
}

$aksRpName = "Microsoft.ContainerService"
$aksRpRegistration = (az provider show -n $aksRpName --query registrationState --output tsv)
if ($aksRpRegistration -ne "Registered") {
    Write-Log Verbose `
        "$aksRpName provider is not registered on the subscription. Registering provider (this can take a while)..."
    az provider register --namespace $aksRpName --wait
    Write-Log OperationCompleted `
        "$aksRpName provider is registered."
}

$cluster = & {
    # Disable $PSNativeCommandUseErrorActionPreference for this scriptblock
    $PSNativeCommandUseErrorActionPreference = $false
    return (az cleanroom cluster show `
            --name $clusterName `
            --provider-config $privateDir/providerConfig.json `
            --provider-client $clusterProviderClient | ConvertFrom-Json)
}

if ($null -eq $cluster) {
    Write-Log OperationStarted `
        "Creating cleanroom cluster '$clusterName' in resource group '$resourceGroup'..."

    az cleanroom cluster create `
        --name $clusterName `
        --provider-config $privateDir/providerConfig.json `
        --provider-client $clusterProviderClient
    Write-Log OperationCompleted `
        "Created cleanroom cluster '$clusterName'."
}
else {
    Write-Log Warning `
        "Connected to existing cleanroom cluster '$clusterName'."
}

$response = az cleanroom cluster show `
    --name $clusterName `
    --provider-config $privateDir/providerConfig.json `
    --provider-client $clusterProviderClient
$response | Out-File $publicDir/cl-cluster.json

$kubeConfig = "${privateDir}/k8s-credentials.yaml"
az cleanroom cluster get-kubeconfig `
    --name $clusterName `
    --provider-config $privateDir/providerConfig.json `
    -f $kubeConfig `
    --provider-client $clusterProviderClient

Write-Log OperationCompleted `
    "Cleanroom cluster configured."
