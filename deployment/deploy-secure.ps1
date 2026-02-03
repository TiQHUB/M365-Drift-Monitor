# Secure Deployment Script for UTCM Configuration Drift Monitor
# This script uses Azure Key Vault to securely manage secrets

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$true)]
    [string]$ClientId,
    
    [Parameter(Mandatory=$true)]
    [string]$EmailRecipient,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "westeurope",
    
    [Parameter(Mandatory=$false)]
    [string]$LogicAppName = "utcm-drift-monitor"
)

Write-Host "🔐 Secure Deployment for UTCM Configuration Drift Monitor" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Check if logged in to Azure
Write-Host "Checking Azure login status..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "❌ Not logged in to Azure. Please run 'az login' first." -ForegroundColor Red
    exit 1
}
Write-Host "✅ Logged in as: $($account.user.name)" -ForegroundColor Green
Write-Host ""

# Check if Key Vault exists
Write-Host "🔍 Checking Key Vault..." -ForegroundColor Yellow
$kvExists = az keyvault show --name $KeyVaultName 2>$null

if (-not $kvExists) {
    # Check if Key Vault exists in soft-deleted state
    Write-Host "   Checking for soft-deleted Key Vault..." -ForegroundColor Gray
    $kvDeleted = az keyvault list-deleted --query "[?name=='$KeyVaultName']" 2>$null | ConvertFrom-Json
    
    if ($kvDeleted -and $kvDeleted.Count -gt 0) {
        Write-Host "⚠️  Key Vault '$KeyVaultName' exists in soft-deleted state." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Cyan
        Write-Host "  1. Recover the soft-deleted Key Vault" -ForegroundColor White
        Write-Host "  2. Purge and recreate the Key Vault (permanent deletion)" -ForegroundColor White
        Write-Host "  3. Use a different existing Key Vault" -ForegroundColor White
        Write-Host "  4. Cancel deployment" -ForegroundColor White
        Write-Host ""
        $choice = Read-Host "Select option (1-4)"
        
        switch ($choice) {
            "1" {
                Write-Host ""
                Write-Host "♻️  Recovering Key Vault: $KeyVaultName..." -ForegroundColor Yellow
                az keyvault recover --name $KeyVaultName --output none
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ Key Vault recovered successfully" -ForegroundColor Green
                } else {
                    Write-Host "❌ Failed to recover Key Vault. Exiting." -ForegroundColor Red
                    exit 1
                }
            }
            "2" {
                Write-Host ""
                Write-Host "🗑️  Purging Key Vault: $KeyVaultName..." -ForegroundColor Yellow
                Write-Host "⚠️  WARNING: This is a permanent deletion. Waiting 5 seconds..." -ForegroundColor Red
                Start-Sleep -Seconds 5
                
                az keyvault purge --name $KeyVaultName --output none
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ Key Vault purged" -ForegroundColor Green
                    Write-Host "   Waiting 10 seconds for purge to complete..." -ForegroundColor Gray
                    Start-Sleep -Seconds 10
                    
                    Write-Host "🔨 Creating new Key Vault: $KeyVaultName..." -ForegroundColor Yellow
                    az keyvault create `
                        --name $KeyVaultName `
                        --resource-group $ResourceGroupName `
                        --location $Location `
                        --output none
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✅ Key Vault created successfully" -ForegroundColor Green
                    } else {
                        Write-Host "❌ Failed to create Key Vault. Exiting." -ForegroundColor Red
                        exit 1
                    }
                } else {
                    Write-Host "❌ Failed to purge Key Vault. Exiting." -ForegroundColor Red
                    exit 1
                }
            }
            "3" {
                Write-Host ""
                Write-Host "Available Key Vaults in subscription:" -ForegroundColor Cyan
                az keyvault list --query "[].{Name:name, ResourceGroup:resourceGroup, Location:location}" --output table
                Write-Host ""
                $KeyVaultName = Read-Host "Enter existing Key Vault name"
                $kvExists = az keyvault show --name $KeyVaultName 2>$null
                if (-not $kvExists) {
                    Write-Host "❌ Key Vault '$KeyVaultName' not found. Exiting." -ForegroundColor Red
                    exit 1
                }
                Write-Host "✅ Using Key Vault: $KeyVaultName" -ForegroundColor Green
            }
            default {
                Write-Host "❌ Deployment cancelled." -ForegroundColor Red
                exit 0
            }
        }
    } else {
        # Key Vault doesn't exist at all
        Write-Host "⚠️  Key Vault '$KeyVaultName' not found." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Cyan
        Write-Host "  1. Create new Key Vault: $KeyVaultName" -ForegroundColor White
        Write-Host "  2. Use a different existing Key Vault" -ForegroundColor White
        Write-Host "  3. Cancel deployment" -ForegroundColor White
        Write-Host ""
        $choice = Read-Host "Select option (1-3)"
        
        switch ($choice) {
            "1" {
                Write-Host ""
                Write-Host "🔨 Creating Key Vault: $KeyVaultName..." -ForegroundColor Yellow
                az keyvault create `
                    --name $KeyVaultName `
                    --resource-group $ResourceGroupName `
                    --location $Location `
                    --output none
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ Key Vault created successfully" -ForegroundColor Green
                } else {
                    Write-Host "❌ Failed to create Key Vault. Exiting." -ForegroundColor Red
                    exit 1
                }
            }
            "2" {
                Write-Host ""
                Write-Host "Available Key Vaults in subscription:" -ForegroundColor Cyan
                az keyvault list --query "[].{Name:name, ResourceGroup:resourceGroup, Location:location}" --output table
                Write-Host ""
                $KeyVaultName = Read-Host "Enter existing Key Vault name"
                $kvExists = az keyvault show --name $KeyVaultName 2>$null
                if (-not $kvExists) {
                    Write-Host "❌ Key Vault '$KeyVaultName' not found. Exiting." -ForegroundColor Red
                    exit 1
                }
                Write-Host "✅ Using Key Vault: $KeyVaultName" -ForegroundColor Green
            }
            default {
                Write-Host "❌ Deployment cancelled." -ForegroundColor Red
                exit 0
            }
        }
    }
} else {
    Write-Host "✅ Key Vault found: $KeyVaultName" -ForegroundColor Green
}

# Grant current user permissions to Key Vault
Write-Host ""
Write-Host "🔐 Configuring Key Vault permissions..." -ForegroundColor Yellow
$userId = az ad signed-in-user show --query id -o tsv
$kvProperties = az keyvault show --name $KeyVaultName --query "properties.enableRbacAuthorization" -o tsv

if ($kvProperties -eq "true") {
    # Key Vault uses RBAC - assign role
    Write-Host "   Using RBAC authorization..." -ForegroundColor Gray
    $kvResourceId = az keyvault show --name $KeyVaultName --query id -o tsv
    az role assignment create `
        --role "Key Vault Secrets Officer" `
        --assignee $userId `
        --scope $kvResourceId `
        --output none 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Key Vault RBAC permissions configured" -ForegroundColor Green
        Write-Host "   ⏳ Waiting 10 seconds for permissions to propagate..." -ForegroundColor Gray
        Start-Sleep -Seconds 10
    } else {
        Write-Host "⚠️  Warning: Could not assign RBAC role. Attempting to continue..." -ForegroundColor Yellow
    }
    
    # Enable Key Vault for ARM template deployment
    Write-Host "   Enabling Key Vault for template deployment..." -ForegroundColor Gray
    az keyvault update `
        --name $KeyVaultName `
        --enabled-for-template-deployment true `
        --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Key Vault enabled for ARM template deployment" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Warning: Could not enable template deployment. Deployment may fail." -ForegroundColor Yellow
    }
} else {
    # Key Vault uses access policies
    Write-Host "   Using access policy..." -ForegroundColor Gray
    az keyvault set-policy `
        --name $KeyVaultName `
        --object-id $userId `
        --secret-permissions get set delete list `
        --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Key Vault access policy configured" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Warning: Could not set access policy. Attempting to continue..." -ForegroundColor Yellow
    }
}

# Prompt for client secret
Write-Host ""
Write-Host "📝 Enter Client Secret (input will be hidden):" -ForegroundColor Yellow
$secureSecret = Read-Host -AsSecureString
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSecret)
$clientSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

if ([string]::IsNullOrWhiteSpace($clientSecret)) {
    Write-Host "❌ Client secret cannot be empty." -ForegroundColor Red
    exit 1
}

# Store secret in Key Vault
Write-Host ""
Write-Host "🔐 Storing client secret in Azure Key Vault..." -ForegroundColor Yellow
try {
    az keyvault secret set `
        --vault-name $KeyVaultName `
        --name "GraphAPIClientSecret" `
        --value $clientSecret `
        --output none
    Write-Host "✅ Secret stored in Key Vault: $KeyVaultName" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to store secret in Key Vault. Make sure you have access." -ForegroundColor Red
    exit 1
}

# Clear the secret from memory
$clientSecret = $null
[System.GC]::Collect()

# Get Key Vault resource ID
Write-Host ""
Write-Host "🔍 Getting Key Vault details..." -ForegroundColor Yellow
$kvId = az keyvault show --name $KeyVaultName --query "id" -o tsv

# Get subscription ID
$subscriptionId = az account show --query "id" -o tsv

# Deploy Office 365 connection first
Write-Host ""
Write-Host "📧 Creating Office 365 connection..." -ForegroundColor Yellow
az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file deployment/office365-connection.json `
    --parameters location=$Location `
    --output none

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Office 365 connection created" -ForegroundColor Green
} else {
    Write-Host "⚠️  Office 365 connection may already exist or failed to create" -ForegroundColor Yellow
}

# Get Office 365 connection ID
$office365ConnectionId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/connections/office365"

# Create parameters JSON with Key Vault reference
Write-Host ""
Write-Host "📝 Creating deployment parameters..." -ForegroundColor Yellow
$parameters = @{
    "`$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
    "contentVersion" = "1.0.0.0"
    "parameters" = @{
        "logicAppName" = @{ "value" = $LogicAppName }
        "location" = @{ "value" = $Location }
        "tenantId" = @{ "value" = $TenantId }
        "clientId" = @{ "value" = $ClientId }
        "clientSecret" = @{
            "reference" = @{
                "keyVault" = @{
                    "id" = $kvId
                }
                "secretName" = "GraphAPIClientSecret"
            }
        }
        "emailRecipient" = @{ "value" = $EmailRecipient }
        "office365ConnectionId" = @{ "value" = $office365ConnectionId }
    }
}

# Save parameters to temporary file
$tempParamFile = [System.IO.Path]::GetTempFileName()
$parameters | ConvertTo-Json -Depth 10 | Out-File -FilePath $tempParamFile -Encoding UTF8 -Force

# Deploy Logic App
Write-Host ""
Write-Host "🚀 Deploying Logic App..." -ForegroundColor Yellow
$deploymentResult = az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file deployment/azuredeploy-simple.json `
    --parameters $tempParamFile `
    --only-show-errors `
    --output json 2>&1 | ConvertFrom-Json

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ Deployment completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "📊 Logic App Details:" -ForegroundColor Cyan
    Write-Host "  Name: $LogicAppName" -ForegroundColor White
    Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor White
    Write-Host "  Location: $Location" -ForegroundColor White
    Write-Host ""
    Write-Host "🔗 View in Azure Portal:" -ForegroundColor Cyan
    Write-Host "  https://portal.azure.com/#resource/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Logic/workflows/$LogicAppName" -ForegroundColor White
    Write-Host ""
    Write-Host "⚠️  Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Authorize the Office 365 connection in Azure Portal" -ForegroundColor White
    Write-Host "  2. Test the Logic App by triggering a manual run" -ForegroundColor White
    Write-Host "  3. Check your email: $EmailRecipient" -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "❌ Deployment failed. Error details:" -ForegroundColor Red
    if ($deploymentResult) {
        Write-Host ($deploymentResult | ConvertTo-Json -Depth 5) -ForegroundColor Red
    }
}

# Clean up temporary file
Remove-Item -Path $tempParamFile -Force

Write-Host ""
Write-Host "🔐 Security Note: Your client secret is stored securely in Key Vault and was never written to disk." -ForegroundColor Green
