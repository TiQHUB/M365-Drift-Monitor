# Deployment Guide

## Prerequisites

Before deploying, ensure you have:

1. **Azure CLI** installed and logged in (`az login`)
2. **Azure subscription** with permissions to create resources
3. **PowerShell** (for automated deployment script)
4. **Azure Key Vault** (recommended) or be ready to create one

## Quick Deployment (Recommended)

Use the secure PowerShell script that handles secrets properly:

```powershell
./deployment/deploy-secure.ps1 `
    -ResourceGroupName "your-resource-group" `
    -KeyVaultName "your-keyvault" `
    -TenantId "your-tenant-id" `
    -ClientId "your-app-client-id" `
    -EmailRecipient "your-email@example.com" `
    -Location "westeurope"
```

**What it does:**
1. Prompts for client secret (hidden input - never written to disk)
2. Stores secret securely in Azure Key Vault
3. Creates Office 365 connection
4. Deploys Logic App with Key Vault reference
5. Provides portal link for authorization

## Manual Deployment

### Step 1: Create App Registration

```bash
# Create app
az ad app create --display-name "UTCM-Drift-Monitor"

# Grant permissions
az ad app permission add --id <app-id> \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Role

# Admin consent
az ad app permission admin-consent --id <app-id>
```

### Step 2: Store Secret in Key Vault

```bash
az keyvault secret set \
  --vault-name <your-keyvault> \
  --name "GraphAPIClientSecret" \
  --value "<your-client-secret>"
```

### Step 3: Deploy Resources

```bash
# Create Office 365 connection
az deployment group create \
  --resource-group <rg> \
  --template-file deployment/office365-connection.json

# Edit parameters file
cp deployment/azuredeploy.parameters.example.json deployment/azuredeploy.parameters.json
# (Update with your values)

# Deploy Logic App
az deployment group create \
  --resource-group <rg> \
  --template-file deployment/azuredeploy-simple.json \
  --parameters deployment/azuredeploy.parameters.json
```

### Step 4: Authorize Office 365

1. Go to Azure Portal
2. Navigate to your resource group
3. Open the `office365` connection
4. Click "Edit API connection" → "Authorize"
5. Sign in with your Microsoft 365 account

### Step 5: Test

```bash
az rest --method POST \
  --uri "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Logic/workflows/utcm-drift-monitor/triggers/Recurrence/run?api-version=2016-06-01"
```

## Security Notes

- ✅ Client secret stored in Key Vault
- ✅ Logic App references Key Vault (no secret in code)
- ✅ Easy secret rotation without redeployment
- ✅ Parameters file excluded from git

## Troubleshooting

**"Client secret expired"**
- Rotate in Azure AD
- Update in Key Vault
- No redeployment needed

**"Office 365 unauthorized"**
- Reauthorize in Azure Portal

**"Graph API denied"**
- Verify admin consent granted
- Check app permissions
