# Azure Foundry credit-only migration

This repository is prepared to move GitHub-model workloads to Microsoft Foundry while preserving one strict invariant:

> **No Azure deployment is allowed unless Azure itself reports that the subscription spending limit is ON.**

That is intentionally stricter than an Azure budget. A budget can alert on spend, but it is not treated here as a hard stop.

## What the workflow does

The workflow at `.github/workflows/azure-foundry-credit-only.yml` has two modes:

- **inventory** — signs in to Azure, verifies the hard spending limit, lists Cognitive Services/Foundry quota, and lists model/SKU availability. It creates no Azure resources.
- **deploy** — performs the same checks and can create/update a **GlobalStandard** model deployment using an explicitly supplied quota capacity.

The workflow intentionally blocks:

- Provisioned throughput / PTU purchases
- GPU managed-compute deployments
- Any run where the Azure subscription reports `spendingLimit=Off`
- Any run where the subscription reports `spendingLimit=CurrentPeriodOff`

## GitHub → Azure authentication

Use GitHub OIDC instead of storing an Azure client secret.

Create a GitHub Environment named:

`azure-credit-only`

Configure these environment or repository variables:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

Optional, for informational credit-balance reporting on supported Microsoft Customer Agreement billing scopes:

- `AZURE_BILLING_ACCOUNT_ID`
- `AZURE_BILLING_PROFILE_ID`

The Azure identity used by GitHub should have only the minimum roles required for the Foundry resource/resource group.

## Maximize throughput without buying fixed capacity

Run the workflow first in **inventory** mode.

The inventory step executes:

```bash
az cognitiveservices usage list --location <region>
az cognitiveservices model list --location <region>
```

These reveal the quota Azure has actually assigned to the subscription and which model/SKU combinations are available.

For deployment, this repository only uses **GlobalStandard**. Raising `sku_capacity` allocates more of your existing quota to the deployment; it does not switch the deployment to provisioned throughput.

If Azure rejects the requested capacity because the assigned quota is lower, request a quota increase in Microsoft Foundry/Azure before increasing the workflow value. A quota increase raises the allowed throughput ceiling; it does not itself consume tokens.

## Why the hard spending-limit requirement matters

Some Azure credit offers automatically stop the subscription when included credit is exhausted. Other billing arrangements can continue into paid usage after credits are exhausted. Because this repository is configured for **credits only**, it refuses to deploy when Azure reports that its spending limit is not active.

Do not remove this guard if the goal remains "use credits only; no paid overage."
