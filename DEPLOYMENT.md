# End-to-End Deployment Guide (UTCM Configuration Drift Monitor)

This guide walks you through deploying the solution from scratch to production-ready validation.

---

## 1) What You Are Deploying

This repository deploys:

- An **Azure Logic App (Consumption)** that runs on a schedule.
- An **Office 365 Outlook API connection** used to send email reports.
- A workflow that queries Microsoft Graph UTCM beta endpoints and generates AI-assisted summaries.

Core deployment files:

- `deployment/deploy-secure.ps1` (recommended secure deployment automation)
- `deployment/azuredeploy-simple.json` (Logic App ARM template)
- `deployment/office365-connection.json` (Office 365 connection ARM template)
- `deployment/azuredeploy.parameters.example.json` (example parameter values)

---

## 2) Prerequisites

Before you start, ensure all of the following are in place:

### Azure + Identity

- Active Azure subscription with permissions to:
  - Create resource groups, Logic Apps, and API connections
  - Create/access Key Vault and deploy ARM templates
- Microsoft Entra tenant with rights to:
  - Create App Registrations
  - Grant admin consent for Microsoft Graph application permissions

### Local tooling

- Azure CLI (`az`) installed and authenticated
- PowerShell 7+ (or Windows PowerShell compatible with the script)

### Graph permissions required by this solution

Grant these **Application** permissions to your App Registration:

- `ConfigurationSnapshot.Read.All`
- `ConfigurationMonitor.Read.All`
- `ConfigurationDrift.Read.All`

Optional but useful:

- `Directory.Read.All`
- `Policy.Read.All`

> UTCM endpoints are Microsoft Graph **beta** endpoints and may change.

---

## 3) High-Level Deployment Flow

1. Create/select a resource group.
2. Create an App Registration and client secret.
3. Grant required Graph application permissions and admin consent.
4. Create/select Key Vault and store the client secret.
5. Deploy Office 365 connection.
6. Deploy Logic App template with parameters.
7. Authorize Office 365 connection in portal.
8. Trigger a run and validate output email + run history.

---

## 4) Recommended Path: Secure Script (Fastest and Safest)

Use the secure script for end-to-end deployment with Key Vault integration.

## 4.1 Create resource group (if needed)

```bash
az group create --name <resource-group-name> --location <azure-region>
```

Example:

```bash
az group create --name rg-utcm-drift --location westeurope
```

## 4.2 Create App Registration (if not already created)

```bash
az ad app create --display-name "UTCM-Drift-Monitor"
```

Capture the returned app ID as `clientId`.

Get your tenant ID:

```bash
az account show --query tenantId -o tsv
```

## 4.3 Add Graph permissions + grant consent

Add required application permissions in Entra ID (portal recommended for accuracy/visibility):

1. Entra ID → App registrations → your app
2. API permissions → Add a permission → Microsoft Graph → **Application permissions**
3. Add:
   - `ConfigurationSnapshot.Read.All`
   - `ConfigurationMonitor.Read.All`
   - `ConfigurationDrift.Read.All`
4. Click **Grant admin consent**

> If your tenant policies allow CLI-based permission assignment, you can use CLI, but many teams prefer portal for verification.

## 4.4 Create a client secret

In Entra ID:

1. App registrations → your app → Certificates & secrets
2. New client secret
3. Copy the secret value immediately (you will enter it once in the script prompt)

## 4.5 Run secure deployment script

From repository root:

```powershell
./deployment/deploy-secure.ps1 `
  -ResourceGroupName "<resource-group-name>" `
  -KeyVaultName "<globally-unique-keyvault-name>" `
  -TenantId "<tenant-id-guid>" `
  -ClientId "<app-client-id-guid>" `
  -EmailRecipient "<recipient@domain.com>" `
  -Location "westeurope" `
  -LogicAppName "utcm-drift-monitor"
```

What the script does for you:

- Verifies Azure login
- Validates/creates/recover/purges Key Vault with guided prompts
- Configures Key Vault access (RBAC or access policy path)
- Prompts for secret securely and stores it as `GraphAPIClientSecret`
- Deploys `deployment/office365-connection.json`
- Builds temporary ARM parameters with a Key Vault secret reference
- Deploys `deployment/azuredeploy-simple.json`

## 4.6 Authorize Office 365 connection

After deployment:

1. Azure Portal → Resource Group
2. Open connection resource named `office365`
3. Click **Edit API connection** / **Authorize**
4. Sign in with mailbox account used for sending reports

## 4.7 Validate by manual trigger

Run the recurrence trigger manually:

```bash
az rest --method POST \
  --uri "https://management.azure.com/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.Logic/workflows/<logic-app-name>/triggers/Recurrence/run?api-version=2016-06-01"
```

Then verify:

- Logic App run status = Succeeded
- Email delivered to configured recipient
- Body contains monitor/snapshot/drift analysis sections

---

## 5) Manual Path (Template-Driven)

Use this when you want explicit control over every step.

## 5.1 Create Office 365 connection

```bash
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file deployment/office365-connection.json \
  --parameters location=<azure-region>
```

The connection name is fixed to `office365`, so expected resource ID format is:

```text
/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.Web/connections/office365
```

## 5.2 Prepare deployment parameters

```bash
cp deployment/azuredeploy.parameters.example.json deployment/azuredeploy.parameters.json
```

Edit `deployment/azuredeploy.parameters.json` and set:

- `logicAppName`
- `location`
- `tenantId`
- `clientId`
- `clientSecret` (or use Key Vault reference approach)
- `emailRecipient`
- `office365ConnectionId`

> Never commit a real `azuredeploy.parameters.json` containing secrets.

## 5.3 Deploy Logic App template

```bash
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file deployment/azuredeploy-simple.json \
  --parameters deployment/azuredeploy.parameters.json
```

## 5.4 Authorize connection and test

Perform the same authorization and test steps from sections 4.6 and 4.7.

---

## 6) Post-Deployment Configuration Checklist

After first successful run, review:

- **Schedule**: default recurrence is daily (`frequency=Day`, `interval=1`) in the template.
- **Time zone**: currently set to `Romance Standard Time` in template.
- **Email recipient(s)**: update parameter and redeploy if needed.
- **Permissions health**: confirm Graph calls do not return 401/403.
- **Model usage**: verify Agent actions complete successfully in run history.

---

## 7) Operations and Maintenance

## 7.1 Secret rotation

If using Key Vault reference (recommended):

1. Create new client secret in App Registration.
2. Update Key Vault secret `GraphAPIClientSecret`:

```bash
az keyvault secret set \
  --vault-name <keyvault-name> \
  --name GraphAPIClientSecret \
  --value "<new-client-secret>"
```

3. Trigger/test Logic App. No template changes are required.

## 7.2 Redeployment

Safe to redeploy templates to apply updates:

```bash
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file deployment/azuredeploy-simple.json \
  --parameters deployment/azuredeploy.parameters.json
```

## 7.3 Monitoring

Track:

- Logic App run failures
- HTTP action status codes to Graph endpoints
- Office 365 connector auth status
- Email delivery consistency

---

## 8) Troubleshooting (Start-to-Fix)

### Problem: Office 365 action fails with authorization errors

**Symptoms**
- Send email action fails
- Connection status shows unauthorized

**Fix**
1. Open `office365` connection in portal
2. Re-authenticate
3. Re-run Logic App

### Problem: Graph API actions return 401/403

**Symptoms**
- `Query_Snapshots`, `Query_Monitors`, or `Query_Drifts` fails

**Fix**
1. Confirm app has all required **Application permissions**
2. Confirm **Admin consent** granted
3. Confirm tenant ID / client ID / client secret are correct
4. If secret expired, rotate and update Key Vault

### Problem: No drift data appears

**Symptoms**
- Workflow succeeds but drift array empty

**Fix**
1. Confirm UTCM monitors exist and have executed
2. Remember monitor cadence can be 6-hour based
3. Validate data directly via Graph Explorer/CLI for tenant

### Problem: Key Vault permission errors during script run

**Symptoms**
- Secret set/read fails during deployment

**Fix**
1. Ensure your account has rights to assign RBAC or set policy
2. Wait for RBAC propagation and retry
3. Ensure Key Vault allows template deployment if using references

### Problem: ARM deployment fails with parameter/connection ID errors

**Fix**
1. Verify `office365ConnectionId` format exactly
2. Ensure `office365` connection exists in same resource group
3. Validate JSON in parameter file

---

## 9) Production Hardening Recommendations

- Use dedicated deployment service principal with least privilege.
- Restrict Key Vault access to specific identities only.
- Add alerting for failed Logic App runs (Azure Monitor).
- Add deployment pipeline (Bicep/ARM in CI/CD) for repeatability.
- Keep an eye on Microsoft Graph beta API changes.

---

## 10) Quick Verification Commands

Use these after deployment:

```bash
# Current account and subscription
az account show --output table

# Logic App state
az resource show \
  --resource-group <resource-group-name> \
  --name <logic-app-name> \
  --resource-type Microsoft.Logic/workflows \
  --query properties.state -o tsv

# Office 365 connection status
az resource show \
  --resource-group <resource-group-name> \
  --name office365 \
  --resource-type Microsoft.Web/connections \
  --query properties.statuses -o json
```

---

## 11) Security Reminders

- Do **not** commit real secrets.
- Prefer Key Vault references over plain-text parameter values.
- Rotate app secrets periodically.
- Review permissions regularly and remove unnecessary scopes.

