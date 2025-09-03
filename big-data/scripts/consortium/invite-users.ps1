param(
    [string]$persona = "$env:PERSONA",
    [string[]]$collaborators = ('northwind', 'woodgrove'),

    [string]$samplesRoot = "/home/samples",
    [string]$publicDir = "$samplesRoot/demo-resources/public",

    [string]$cgsClient = "azure-cleanroom-samples-governance-client-$persona"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

Write-Log OperationStarted `
    "Inviting '$collaborators' to the collaboration..." 

# Create invitations for each user.
foreach ($collaboratorName in $collaborators) {
    # Makes a proposal for adding the new user.
    $invitationId = [Guid]::NewGuid().ToString("N")
    $proposalId = (az cleanroom governance user-identity invitation create `
            --invitation-id $invitationId `
            --username (Get-Content "$publicDir/$collaboratorName.email") `
            --identity-type user `
            --account-type microsoft `
            --query "proposalId" `
            --output tsv `
            --governance-client $cgsClient)
    $invitationId | Out-File "$publicDir/$collaboratorName.invitation-id"

    # Vote on the above proposal to activate the invite.
    az cleanroom governance proposal vote `
        --proposal-id $proposalId `
        --action accept `
        --governance-client $cgsClient

    Write-Log OperationCompleted `
        "Invited '$collaboratorName' to the collaboration."
}
