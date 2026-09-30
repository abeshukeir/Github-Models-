#!/usr/bin/env bash
set -euo pipefail

LOCATION="${1:-eastus}"
MODEL_NAME="${2:-}"

echo "== Cognitive Services / Foundry quota in $LOCATION =="
az cognitiveservices usage list --location "$LOCATION" --output table

echo
echo "== Models and SKUs available in $LOCATION =="
if [[ -n "$MODEL_NAME" ]]; then
  az cognitiveservices model list     --location "$LOCATION"     --query "[?model.name=='$MODEL_NAME'].{model:model.name,version:model.version,format:model.format,skus:join(',',model.skus[].name)}"     --output table
else
  az cognitiveservices model list     --location "$LOCATION"     --query "[].{model:model.name,version:model.version,format:model.format,skus:join(',',model.skus[].name)}"     --output table
fi

echo
echo "Inventory only. No Azure resources were created or modified."
