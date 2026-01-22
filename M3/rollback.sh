#!/bin/bash

# --- Configuration (Must match your provisioning script) ---
SUBSCRIPTIONS=("subs1" "subs2" "subs3")
SERVER_NAMES=("server-prod-01" "server-stage-01" "server-dev-01")
RESOURCE_GROUP="rg_group_name"

echo "Starting selective cleanup of PostgreSQL servers..."

for i in "${!SUBSCRIPTIONS[@]}"; do
    SUB_ID=${SUBSCRIPTIONS[$i]}
    SVR_NAME=${SERVER_NAMES[$i]}

    echo "--------------------------------------------------------"
    echo "Switching to Subscription: $SUB_ID"
    az account set --subscription "$SUB_ID"

    # Check if the server exists before trying to delete
    SERVER_EXISTS=$(az postgres flexible-server list --resource-group "$RESOURCE_GROUP" --query "[?name=='$SVR_NAME'].name" -o tsv)

    if [ -n "$SERVER_EXISTS" ]; then
        echo "Deleting PostgreSQL Server: $SVR_NAME from Resource Group: $RESOURCE_GROUP..."
        # --yes confirms deletion, --no-wait runs it in the background to speed up the script
        az postgres flexible-server delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$SVR_NAME" \
            --yes
    else
        echo "Server $SVR_NAME not found in $SUB_ID. Skipping."
    fi
done

echo "--------------------------------------------------------"
echo "Cleanup commands triggered. The servers are being deleted in the background."
echo "Note: The Resource Group '$RESOURCE_GROUP' has been preserved."
