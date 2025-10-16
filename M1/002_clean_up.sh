#!/bin/bash

# --- Configuration: Match your deployment script's values ---
RESOURCE_GROUP="demo1_flex1"        # Name of the resource group
SUBSCRIPTION_ID="<insert_here_subscription_id>" 
# ---------------------------------------------

echo "Starting Azure resource cleanup..."

# 1. Log in to Azure (if not already logged in)
az account show > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Logging into Azure CLI..."
    az login --scope https://management.core.windows.net/
    if [ $? -ne 0 ]; then
        echo "Azure login failed. Exiting."
        exit 1
    fi
fi

# 2. Set the target subscription
echo "Setting target subscription to: $SUBSCRIPTION_ID"
az account set --subscription "$SUBSCRIPTION_ID"

# 3. Check if the resource group exists
az group show --name $RESOURCE_GROUP > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Resource Group '$RESOURCE_GROUP' does not exist. Cleanup complete."
    exit 0
fi

# 4. Delete the Resource Group
echo "Deleting Resource Group '$RESOURCE_GROUP'..."
echo "This operation will delete ALL resources inside it, including the PostgreSQL server."
echo "It runs in the background (--no-wait) to let you continue."

# The --yes flag bypasses the confirmation prompt.
# The --no-wait flag immediately returns control to the shell while Azure handles the deletion.
az group delete \
    --name $RESOURCE_GROUP \
    --yes \
    --no-wait

if [ $? -eq 0 ]; then
    echo "Resource Group deletion successfully initiated for '$RESOURCE_GROUP'."
    echo "It is now deleting in the background. Please check the Azure Portal for final status."
else
    echo "Failed to initiate Resource Group deletion. Check the error above."
fi

# ---------------------------------------------
# --- Final Instruction ---
# ---------------------------------------------
echo -e "\n--- To check the deletion status in the Azure Cloud Shell, run: ---"

echo "az group show --name $RESOURCE_GROUP --output table"
