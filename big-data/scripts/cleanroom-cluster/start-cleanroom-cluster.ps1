param(
    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",
    [string]$resourceGroupLocation = "$env:RESOURCE_GROUP_LOCATION",

    [string]$samplesRoot = "/home/samples",
    [string]$secretDir = "$samplesRoot/demo-resources/secret",
    [string]$privateDir = "$samplesRoot/demo-resources/private",
    [string]$publicDir = "$samplesRoot/demo-resources/public",

    [string]$cgsClient = "azure-cleanroom-samples-governance-client-$persona",
    [string]$clusterProviderClient = "azure-cleanroom-samples-cluster-provider",
    [string]$ccfEndpoint = "$publicDir/ccfEndpoint.json",
    [string]$contractId = "",

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
$response | Out-File $privateDir/cl-cluster.json

$kubeConfig = "${privateDir}/k8s-credentials.yaml"
az cleanroom cluster get-kubeconfig `
    --name $clusterName `
    --provider-config $privateDir/providerConfig.json `
    -f $kubeConfig `
    --provider-client $clusterProviderClient

Write-Log OperationCompleted `
    "Cleanroom cluster configured."

# Propose the analytics contract for the cleanroom cluster.
$ccfEndpointUrl = (Get-Content $ccfEndpoint | ConvertFrom-Json).url
$agent = Get-Content $publicDir/ccf.recovery-agent.json | ConvertFrom-Json
$agentEndpoint = $agent.endpoint
$agentNetworkReport = curl -k -s -S $agentEndpoint/network/report | ConvertFrom-Json
$reportDataContent = $agentNetworkReport.reportDataPayload | base64 -d | ConvertFrom-Json

# Propose a contract for the cleanroom cluster analytics deployment.
if ($contractId -eq "") {
    $contractId = "analytics-$((New-Guid).ToString().Substring(0, 8))"
}

$recoveryMembers = az cleanroom governance member show --governance-client $cgsClient | jq '[.value[] | select(.publicEncryptionKey != null) | .memberId]' -c 
@"
{
  "ccrgovEndpoint": "$ccfEndpointUrl",
  "ccrgovApiPathPrefix": "/app/contracts/$contractId",
  "ccrgovServiceCertDiscovery" : {
    "endpoint": "$agentEndpoint/network/report",
    "snpHostData": "$($agent.snpHostData)",
    "constitutionDigest": "$($reportDataContent.constitutionDigest)",
    "jsappBundleDigest": "$($reportDataContent.jsappBundleDigest)"
  },
  "ccfNetworkRecoveryMembers": $recoveryMembers
}
"@ > $privateDir/contract.json

$data = Get-Content -Raw $privateDir/contract.json
Write-Output "Creating contract '$contractId'..."
az cleanroom governance contract create `
    --data "$data" `
    --id $contractId `
    --governance-client $cgsClient

$contractId | Out-File $publicDir/analytics.contract-id

# Submitting a contract proposal.
$version = (az cleanroom governance contract show `
        --id $contractId `
        --query "version" `
        --output tsv `
        --governance-client $cgsClient)

az cleanroom governance contract propose `
    --version $version `
    --id $contractId `
    --governance-client $cgsClient

$contract = (az cleanroom governance contract show `
        --id $contractId `
        --governance-client $cgsClient | ConvertFrom-Json)

# Accept it.
az cleanroom governance contract vote `
    --id $contractId `
    --proposal-id $contract.proposalId `
    --action accept `
    --governance-client $cgsClient

Write-Output "Enabling CA..."
az cleanroom governance ca propose-enable `
    --contract-id $contractId `
    --governance-client $cgsClient

# Vote on the proposed CA enable.
$proposalId = az cleanroom governance ca show `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --query "proposalIds[0]" `
    --output tsv

az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $cgsClient

az cleanroom governance ca generate-key `
    --contract-id $contractId `
    --governance-client $cgsClient

az cleanroom governance ca show `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --query "caCert" `
    --output tsv > $publicDir/cleanroomca.crt

$option = "cached-debug"
Write-Output "Generating deployment template/policy with $option creation option for analytics workload..."
mkdir -p $privateDir/deployments
az cleanroom cluster analytics-workload deployment generate `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --output-dir $privateDir/deployments `
    --security-policy-creation-option $option `
    --provider-client $clusterProviderClient `
    --provider-config $privateDir/providerConfig.json

Write-Output "Setting deployment template..."
az cleanroom governance deployment template propose `
    --contract-id $contractId `
    --template-file $privateDir/deployments/analytics-workload.deployment-template.json `
    --governance-client $cgsClient

# Vote on the proposed deployment template.
$proposalId = az cleanroom governance deployment template show `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --query "proposalIds[0]" `
    --output tsv

az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $cgsClient

Write-Output "Setting clean room policy..."
az cleanroom governance deployment policy propose `
    --policy-file $privateDir/deployments/analytics-workload.governance-policy.json `
    --contract-id $contractId `
    --governance-client $cgsClient

# Vote on the proposed cce policy.
$proposalId = az cleanroom governance deployment policy show `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --query "proposalIds[0]" `
    --output tsv

az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $cgsClient

# Deploy the analytics agent using the CGS /deploymentspec endpoint as the analytics config endpoint.
$ccfName = $persona + "-ccf"
$serviceCertFileName = "${ccfName}_service_cert.pem"
$serviceCert = "$publicDir/$serviceCertFileName"
@"
{
    "url": "${ccfEndpointUrl}/app/contracts/$contractId/deploymentspec",
    "caCert": "$((Get-Content $serviceCert -Raw).ReplaceLineEndings("\n"))"
}
"@ > $privateDir/analytics-workload-config-endpoint.json

pwsh $PSScriptRoot/enable-analytics-workload.ps1 `
    -privateDir $privateDir `
    -securityPolicyCreationOption $option `
    -configEndpointFile $privateDir/analytics-workload-config-endpoint.json
