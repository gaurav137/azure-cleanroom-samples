function Create-Storage-Resources {
    param(
        [string]$resourceGroup,

        [string[]]$storageAccountNames,

        [string]$objectId
    )

    foreach ($storageAccountName in $storageAccountNames) {
        Write-Host "Creating storage account $storageAccountName in resource group $resourceGroup"
        $storageAccountResult = (az storage account create --name $storageAccountName --resource-group $resourceGroup --min-tls-version TLS1_2 --allow-shared-key-access $false) | ConvertFrom-Json

        if ($null -eq $storageAccountResult) {
            $storageAccountResult = (az storage account show --name $storageAccountName --resource-group $resourceGroup) | ConvertFrom-Json
        }

        $role = "Storage Blob Data Contributor"
        $roleAssignment = (az role assignment list `
                --assignee-object-id $objectId `
                --scope $storageAccountResult.id `
                --role $role `
                --fill-principal-name false `
                --fill-role-definition-name false) | ConvertFrom-Json

        if ($roleAssignment.Length -eq 1) {
            Write-Host "$role permission on the storage account already exists, skipping assignment"
        }
        else {
            Write-Host "Assigning '$role' permissions to logged in user"
            az role assignment create --role $role --scope $storageAccountResult.id --assignee-object-id $objectId --assignee-principal-type $(Get-Assignee-Principal-Type)
        }
        $storageAccountResult

        if ($env:GITHUB_ACTIONS -eq "true") {
            $sleepTime = 90
            Write-Host "Waiting for $sleepTime seconds for permissions to get applied"
            Start-Sleep -Seconds $sleepTime
        }
    
    }
}

function Get-Assignee-Principal-Type {
    if ($env:GITHUB_ACTIONS -eq "true") {
        return "ServicePrincipal"
    }
    else {
        return "User"
    }
}
