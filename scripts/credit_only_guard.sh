#!/usr/bin/env bash
set -euo pipefail

: "${AZURE_SUBSCRIPTION_ID:?AZURE_SUBSCRIPTION_ID is required}"

SUB_JSON="$(az rest   --method get   --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}?api-version=2022-12-01")"

STATE="$(jq -r '.state // "Unknown"' <<<"$SUB_JSON")"
SPENDING_LIMIT="$(jq -r '.subscriptionPolicies.spendingLimit // "Unknown"' <<<"$SUB_JSON")"
QUOTA_ID="$(jq -r '.subscriptionPolicies.quotaId // "Unknown"' <<<"$SUB_JSON")"

echo "Azure subscription state: $STATE"
echo "Azure spending limit: $SPENDING_LIMIT"
echo "Azure quota ID: $QUOTA_ID"

if [[ "$STATE" != "Enabled" ]]; then
  echo "::error::Azure subscription is not Enabled. Refusing to deploy."
  exit 40
fi

# Credit-only safety invariant:
# Azure must enforce the subscription spending limit. Budgets/alerts alone do not
# create a hard stop, so we intentionally refuse deployment when the limit is Off
# or CurrentPeriodOff.
if [[ "$SPENDING_LIMIT" != "On" ]]; then
  echo "::error::Hard credit-only guard failed: Azure spendingLimit=$SPENDING_LIMIT."
  echo "::error::This workflow will not deploy anything that could continue billing after credits."
  exit 41
fi

# Optional informational credit balance lookup for MCA billing profiles.
# This is NOT used as a substitute for a hard spending limit.
if [[ -n "${AZURE_BILLING_ACCOUNT_ID:-}" && -n "${AZURE_BILLING_PROFILE_ID:-}" ]]; then
  CREDIT_URL="https://management.azure.com/providers/Microsoft.Billing/billingAccounts/${AZURE_BILLING_ACCOUNT_ID}/billingProfiles/${AZURE_BILLING_PROFILE_ID}/providers/Microsoft.Consumption/credits/balanceSummary?api-version=2026-06-01"
  if CREDIT_JSON="$(az rest --method get --url "$CREDIT_URL" 2>/dev/null)"; then
    CURRENT="$(jq -r '.properties.balanceSummary.currentBalance.value // empty' <<<"$CREDIT_JSON")"
    ESTIMATED="$(jq -r '.properties.balanceSummary.estimatedBalance.value // empty' <<<"$CREDIT_JSON")"
    CURRENCY="$(jq -r '.properties.creditCurrency // .properties.billingCurrency // empty' <<<"$CREDIT_JSON")"
    [[ -n "$CURRENT" ]] && echo "Reported current credit balance: $CURRENT $CURRENCY"
    [[ -n "$ESTIMATED" ]] && echo "Reported estimated credit balance: $ESTIMATED $CURRENCY"
  else
    echo "Credit balance API was unavailable for this billing scope; continuing only because Azure reports spendingLimit=On."
  fi
fi

echo "Credit-only guard PASSED."
