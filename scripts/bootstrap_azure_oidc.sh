#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="${REPO_OWNER:-abeshukeir}"
REPO_OWNER_ID="${REPO_OWNER_ID:-232669217}"
REPO_NAME="${REPO_NAME:-Github-Models-}"
REPO_ID="${REPO_ID:-1380545946}"
GITHUB_ENVIRONMENT="${GITHUB_ENVIRONMENT:-azure-credit-only}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-github-models-azure-credit-only}"

command -v az >/dev/null 2>&1 || {
  echo "Azure CLI (az) is required."
  exit 2
}

SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
TENANT_ID="$(az account show --query tenantId -o tsv)"

SUB_JSON="$(az rest --method get   --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}?api-version=2022-12-01")"
SPENDING_LIMIT="$(jq -r '.subscriptionPolicies.spendingLimit // "Unknown"' <<<"$SUB_JSON")"

if [[ "$SPENDING_LIMIT" != "On" ]]; then
  echo "Refusing bootstrap: Azure spendingLimit=$SPENDING_LIMIT."
  echo "This setup is intentionally restricted to credit-backed subscriptions with a hard spending limit."
  exit 41
fi

APP_ID="$(az ad app list --display-name "$APP_DISPLAY_NAME"   --query '[0].appId' -o tsv)"

if [[ -z "$APP_ID" ]]; then
  APP_ID="$(az ad app create     --display-name "$APP_DISPLAY_NAME"     --query appId -o tsv)"
fi

APP_OBJECT_ID="$(az ad app show --id "$APP_ID" --query id -o tsv)"

if ! az ad sp show --id "$APP_ID" >/dev/null 2>&1; then
  az ad sp create --id "$APP_ID" >/dev/null
fi

SP_OBJECT_ID="$(az ad sp show --id "$APP_ID" --query id -o tsv)"

SUBJECT="repo:${REPO_OWNER}@${REPO_OWNER_ID}/${REPO_NAME}@${REPO_ID}:environment:${GITHUB_ENVIRONMENT}"
CRED_NAME="github-${GITHUB_ENVIRONMENT}"

if ! az ad app federated-credential list --id "$APP_OBJECT_ID"   --query "[?name=='$CRED_NAME'] | [0].name" -o tsv | grep -qx "$CRED_NAME"; then
  az ad app federated-credential create     --id "$APP_OBJECT_ID"     --parameters "{
      \"name\": \"$CRED_NAME\",
      \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"$SUBJECT\",
      \"audiences\": [\"api://AzureADTokenExchange\"]
    }" >/dev/null
fi

SUB_SCOPE="/subscriptions/$SUBSCRIPTION_ID"

az role assignment create   --assignee-object-id "$SP_OBJECT_ID"   --assignee-principal-type ServicePrincipal   --role "Reader"   --scope "$SUB_SCOPE" >/dev/null 2>&1 || true

az role assignment create   --assignee-object-id "$SP_OBJECT_ID"   --assignee-principal-type ServicePrincipal   --role "Cognitive Services Usages Reader"   --scope "$SUB_SCOPE" >/dev/null 2>&1 || true

cat <<EOF
Azure credit-only GitHub OIDC bootstrap complete.

AZURE_CLIENT_ID=$APP_ID
AZURE_TENANT_ID=$TENANT_ID
AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID
OIDC_SUBJECT=$SUBJECT

The identity currently has subscription Reader + Cognitive Services Usages Reader.
Grant Cognitive Services OpenAI Contributor only on the specific Foundry account
that will host the deployment, after the credit-only guard passes.
EOF
