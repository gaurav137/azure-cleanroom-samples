param(
    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",
    [string]$resourceGroupLocation = "$env:RESOURCE_GROUP_LOCATION",

    [string]$samplesRoot = "/home/samples",
    [string]$secretDir = "$samplesRoot/demo-resources/secret",
    [string]$privateDir = "$samplesRoot/demo-resources/private",
    [string]$publicDir = "$samplesRoot/demo-resources/public",

    [string]$environmentConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$ccfProviderClient = "azure-cleanroom-samples-ccf-provider",
    [string]$cgsClient = "azure-cleanroom-samples-governance-client-$persona",
    [string]$ccfEndpoint = "$publicDir/ccfEndpoint.json",

    [string]$repo = "cleanroomemuprregistry.azurecr.io",
    [string]$tag = "16749412789"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

Test-AzureAccessToken

$initResult = Get-Content $environmentConfig | ConvertFrom-Json
$sa = $initResult.ccfsa.id

$ccfName = $persona + "-ccf"

#
# Generate operator member identity.
#
pwsh $PSScriptRoot/initialize-member.ps1

#
# Create a CCF instance.
#
$subscriptionId = az account show --query id --output tsv

@"
{
    "location": "$resourceGroupLocation",
    "subscriptionId": "$subscriptionId",
    "resourceGroupName": "$resourceGroup",
    "azureFiles": {
        "storageAccountId": "$sa"
    }
}
"@  | Out-File $privateDir/ccfProviderConfig.json

# Register the ACI RP so that confidential container usage is enabled in the subscription.
$aciRpName = "Microsoft.ContainerInstance"
$aciRpRegistration = (az provider show -n $aciRpName --query registrationState --output tsv)
if ($aciRpRegistration -ne "Registered") {
    Write-Log Verbose `
        "$aciRpName provider is not registered on the subscription. Registering provider (this can take a while)..."
    az provider register --namespace $aciRpName --wait
    Write-Log OperationCompleted `
        "$aciRpName provider is registered."
}

$ccf = & {
    # Disable $PSNativeCommandUseErrorActionPreference for this scriptblock
    $PSNativeCommandUseErrorActionPreference = $false
    return (az cleanroom ccf network show `
            --name $ccfName `
            --provider-config $privateDir/ccfProviderConfig.json `
            --provider-client $ccfProviderClient | ConvertFrom-Json)
}

$ccfOperator = "ccfoperator"

if ($null -eq $ccf) {
    Write-Log OperationStarted `
        "Creating consortium '$ccfName' in resource group '$resourceGroup'..."

    # Generate ccf-operator identity and encryption public-private key pair.
    $ccfOperatorMemberCert = $secretDir + "/" + $ccfOperator + "_cert.pem"
    $ccfOperatorEncryptionCert = $secretDir + "/" + $ccfOperator + "_enc_pubk.pem"

    if ((Test-Path -Path $ccfOperatorMemberCert) -or
        (Test-Path -Path $ccfOperatorEncryptionCert)) {
        Write-Log Warning `
            "Identity and/or encryption key pairs for '$ccfOperator' already exist."
    }
    else {
        Write-Log Verbose `
            "Generating identity and encryption key pairs for '$ccfOperator' in '$secretDir'..."
        az cleanroom governance member keygenerator-sh | bash -s -- --gen-enc-key --name $ccfOperator --out $secretDir
    }

    $memberCert = $secretDir + "/" + $persona + "_cert.pem"

    @"
[{
    "certificate": "$ccfOperatorMemberCert",
    "encryptionPublicKey": "$ccfOperatorEncryptionCert",
    "memberData": {
        "identifier": "$ccfOperator",
        "isOperator": true
    }
},
{
    "certificate": "$memberCert",
    "memberData": {
        "identifier": "$persona"
    }
}]
"@ | Out-File $privateDir/ccfMembers.json

    $option = "cached-debug"
    Write-Log Verbose `
        "Creating CCF network '$ccfName' in '$resourceGroup'..."
    $ccf = (az cleanroom ccf network create `
            --name $ccfName `
            --node-count 1 `
            --node-log-level "Info" `
            --security-policy-creation-option $option `
            --infra-type 'caci' `
            --members $privateDir/ccfMembers.json `
            --provider-config $privateDir/ccfProviderConfig.json `
            --provider-client $ccfProviderClient | ConvertFrom-Json)
    $ccfUri = $ccf.endpoint

    Write-Log OperationCompleted `
        "Created CCF network '$ccfName' ('$ccfUri')."
}
else {
    $ccfUri = $ccf.endpoint
    Write-Log Warning `
        "Connected to existing CCF network '$ccfName' ('$ccfUri')."
}

$response = (curl "$ccfUri/node/network" -k --silent | ConvertFrom-Json)
# Trimming an extra new-line character added to the cert.
$serviceCertStr = $response.service_certificate.TrimEnd("`n")
$serviceCert = "${ccfName}_service_cert.pem"
$serviceCertStr | Out-File "$publicDir/$serviceCert"

#
# Use AZCLI_ overrides till latest images are available in mcr.microsoft.com.
#
$envVarsClientDeploy = @{
    "AZCLI_CGS_CLIENT_IMAGE" = "$repo/cgs-client:$tag"
    "AZCLI_CGS_UI_IMAGE"     = "$repo/cgs-ui:$tag"
}

& {
    # Deploy client-side containers to interact with the governance service as ccf-operator
    # and accept the invitation.
    $ccfOperatorClient = "azure-cleanroom-samples-governance-client-$ccfOperator"
    Write-Log Verbose `
        "Deploying governance client '$ccfOperatorClient'..."
    Start-Process az `
        -ArgumentList "cleanroom governance client deploy --ccf-endpoint $ccfUri --signing-cert $secretDir/$($ccfOperator)_cert.pem --signing-key $secretDir/$($ccfOperator)_privk.pem --service-cert $publicDir/$serviceCert --name $ccfOperatorClient" `
        -Environment $envVarsClientDeploy  `
        -Wait
    az cleanroom governance member activate --governance-client $ccfOperatorClient

    # Setting up Microsoft IDPs as trusted JWT token issuers for user identity.
    Write-Log Verbose "Submitting set_ca_cert_bundle proposal for trusted root CAs"
    az cleanroom governance proposal create `
        --content "$PSScriptRoot/proposals/set_ca_cert_bundle/trusted_root_cas.json" `
        --governance-client $ccfOperatorClient
    
    Write-Log Verbose "Submitting set_jwt_issuer proposal for sts.windows.net"
    az cleanroom governance proposal create `
        --content "$PSScriptRoot/proposals/set_jwt_issuer/sts.windows.net.json" `
        --governance-client $ccfOperatorClient

    Write-Log Verbose "Submitting set_jwt_issuer proposal for login.microsoftonline.com"
    az cleanroom governance proposal create `
        --content "$PSScriptRoot/proposals/set_jwt_issuer/login.microsoftonline.com.json" `
        --governance-client $ccfOperatorClient


    # Configure the ccf provider client for the operator and open the network.
    Write-Log Verbose `
        "Opening CCF network '$ccfName'..."
    az cleanroom ccf provider configure `
        --name $ccfProviderClient `
        --signing-cert "$secretDir/$($ccfOperator)_cert.pem" `
        --signing-key "$secretDir/$($ccfOperator)_privk.pem"
    az cleanroom ccf network transition-to-open `
        --name $ccfName `
        --provider-config $privateDir/ccfProviderConfig.json `
        --provider-client $ccfProviderClient

    # TODO: Uncomment this block and remove initial member from member.json after picking
    # up next release.
    # az cleanroom governance member add `
    #     --certificate "$publicDir/$($persona)_cert.pem" `
    #     --identifier $persona `
    #     --tenant-id (Get-Content "$publicDir/$persona.tenantid") `
    #     --query "proposalId" `
    #     --output tsv `
    #     --governance-client $ccfOperatorClient
    Write-Log OperationCompleted `
        "Opened CCF network '$ccfName' ('$ccfUri') with default constitution" `
        "and initial member '$persona'."
}

$agentEndpoint = az cleanroom ccf network recovery-agent show `
    --name $ccfName `
    --provider-config $privateDir/ccfProviderConfig.json `
    --provider-client $ccfProviderClient `
    --query endpoint `
    --output tsv
$snpHostData = az cleanroom ccf network show-report `
    --name $ccfName `
    --provider-config $privateDir/ccfProviderConfig.json `
    --provider-client $ccfProviderClient `
    --query reports[0].hostData `
    --output tsv
@"
{
  "endpoint": "$agentEndpoint",
  "snpHostData": "$snpHostData"
}
"@ | Out-File $publicDir/ccf.recovery-agent.json

& {
    # Deploy client-side containers to interact with the governance service as the first member
    # and accept the invitation.
    Write-Log Verbose `
        "Deploying governance client '$cgsClient'..."
    Start-Process az `
        -ArgumentList "cleanroom governance client deploy --ccf-endpoint $ccfUri --signing-cert $secretDir/$($persona)_cert.pem --signing-key $secretDir/$($persona)_privk.pem --service-cert $publicDir/$serviceCert --name $cgsClient" `
        -Environment $envVarsClientDeploy `
        -Wait
    az cleanroom governance member activate --governance-client $cgsClient

    Write-Log OperationCompleted `
        "Joined consortium '$ccfUri' and deployed CGS client '$cgsClient'."
}

#
# Use AZCLI_ overrides till latest images are available in mcr.microsoft.com.
#
$envVarsServiceDeploy = @{
    "AZCLI_CGS_JSAPP_IMAGE"        = "$repo/cgs-js-app:$tag"
    "AZCLI_CGS_CONSTITUTION_IMAGE" = "$repo/cgs-constitution:$tag"
}

# Deploy governance service on the CCF instance.
Write-Log Verbose `
    "Deploying Clean Room Governance Service to '$ccfName'..."
Start-Process az `
    -ArgumentList "cleanroom governance service deploy --governance-client $cgsClient" `
    -Environment $envVarsServiceDeploy `
    -Wait

# Share the CCF endpoint details.
$result = @{
    name        = $ccfName
    url         = $ccfUri
    serviceCert = $serviceCert
}
$result | ConvertTo-Json -Depth 100 | Out-File "$ccfEndpoint"
Write-Log OperationCompleted `
    "CCF configured. Configuration written to '$ccfEndpoint'."
