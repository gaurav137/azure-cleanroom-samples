function Get-JwtOid {
    param (
        [Parameter(Mandatory = $true)]
        [string]$token
    )

    # Split token into header.payload.signature
    $parts = $token -split '\.'

    if ($parts.Length -lt 2) {
        throw "Invalid JWT token format."
    }

    # Base64URL decode payload
    $payloadBase64 = $parts[1].Replace('-', '+').Replace('_', '/')
    switch ($payloadBase64.Length % 4) {
        2 { $payloadBase64 += '==' }
        3 { $payloadBase64 += '=' }
    }

    $payloadJson = [System.Text.Encoding]::UTF8.GetString(
        [System.Convert]::FromBase64String($payloadBase64)
    )

    try {
        $payloadObj = $payloadJson | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse JWT payload as JSON."
    }

    if (-not $payloadObj.PSObject.Properties.Match("oid")) {
        throw "JWT does not contain an 'oid' claim."
    }

    return $payloadObj.oid
}

function GetLoggedInEntityObjectId {
    if ($env:GITHUB_ACTIONS -eq "true") {
        Write-Host "Running inside GitHub Actions. Fetching Azure credentials"

        if ($env:TEST_ENVIRONMENT -eq "PR") {
            $clientId = $($env:AZURE_CREDENTIALS | ConvertFrom-Json).clientId
        }
        elseif ($env:TEST_ENVIRONMENT -eq "BVT") {
            $clientId = $env:RELEASE_CLIENT_ID
        }
        else {
            throw "Required environment variables are unavailable"
            $clientId = ""
        }

        $spDetails = (az ad sp show --id $clientId) | ConvertFrom-Json
        $objectId = $spDetails.id

        Write-Host "Fetched object ID $objectId for client ID $clientID"
        return $objectId
    }
    else {
        Write-Host "Fetching object ID of currently logged in user"
        # Since some tenant (including Microsoft tenant) has Conditional Access policies that block
        # accessing Microsoft Graph with device code (#22629), querying Microsoft Graph API is no
        # longer possible with device code.
        # Using manual workaround per https://github.com/Azure/azure-cli/issues/22776
        $token = (az account get-access-token --query accessToken --output tsv)
        $objectId = Get-JwtOid -token $token
        return $objectId
    }
}