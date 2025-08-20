param(
    [string]$persona = "$env:PERSONA",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources/private",
    [string]$publicDir = "$samplesRoot/demo-resources/public",

    [string]$cgsClient = "azure-cleanroom-samples-governance-client-$persona",
    [string]$operatorCgsClient = "azure-cleanroom-samples-governance-client-operator",

    [string]$repo = "$env:CLEANROOM_REPO",
    [string]$tag = "$env:CLEANROOM_TAG"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

$ccfEndpoint = (Get-Content "$publicDir/ccfEndpoint.json" | ConvertFrom-Json)
Write-Log OperationStarted `
    "Performing login as $persona to accept invitation..."

#
# Use AZCLI_ overrides till latest images are available in mcr.microsoft.com.
#
$envVarsClientDeploy = @{
    "AZCLI_CGS_CLIENT_IMAGE" = "$repo/cgs-client:$tag"
    "AZCLI_CGS_UI_IMAGE"     = "$repo/cgs-ui:$tag"
}

#
# Connect to CCF using service cert discovery. This transparently handles CCF network restart/recovery performed by the operator.
#
$agent = Get-Content $publicDir/ccf.recovery-agent.json | ConvertFrom-Json
$agentEndpoint = $agent.endpoint
$agentNetworkReport = curl -k -s -S $agentEndpoint/network/report | ConvertFrom-Json
$reportDataContent = $agentNetworkReport.reportDataPayload | base64 -d | ConvertFrom-Json
$serviceCertDiscoveryArgs = "--service-cert-discovery-endpoint $agentEndpoint/network/report " + 
"--service-cert-discovery-snp-host-data $($agent.snpHostData) " + 
"--service-cert-discovery-constitution-digest $($reportDataContent.constitutionDigest) " +
"--service-cert-discovery-jsapp-bundle-digest $($reportDataContent.jsappBundleDigest) "

$cgsMsalTokenCacheDir = $env:HOST_PERSONA_PRIVATE_DIR + "/$cgsClient"
# Deploy client-side containers to interact with the governance service as the new user.
$proc = Start-Process az `
    -ArgumentList "cleanroom governance client deploy --ccf-endpoint $($ccfEndpoint.url) --use-microsoft-identity --msal-token-cache-root-dir $privateDir --cgs-msal-token-cache-dir $cgsMsalTokenCacheDir $serviceCertDiscoveryArgs --name $cgsClient" `
    -Environment $envVarsClientDeploy `
    -Wait `
    -PassThru
if (0 -ne $proc.ExitCode) {
    throw "Command failed."
}

# Accept the invitation and becomes an active member in the consortium.
$invitationId = Get-Content "$publicDir/$persona.invitation-id"
$status = (az cleanroom governance user-identity invitation show  `
        --invitation-id $invitationId `
        --governance-client $cgsClient `
        --query status `
        --output tsv)
if ($status -eq "Finalized") {
    Write-Log Verbose `
        "Invitation $invitationId was already accepted."
    return
}

az cleanroom governance user-identity invitation accept `
    --invitation-id $invitationId `
    --governance-client $cgsClient

Write-Log OperationStarted `
    "Finalizing the invitation for $persona via $operatorCgsClient..."
$proposalId = (az cleanroom governance user-identity add `
        --accepted-invitation-id $invitationId `
        --governance-client $operatorCgsClient `
        --query "proposalId" `
        --output tsv)
az cleanroom governance proposal vote --proposal-id $proposalId --action accept --governance-client $operatorCgsClient

Write-Log OperationCompleted `
    "Invitation accepted and deployed CGS client '$cgsClient'."
