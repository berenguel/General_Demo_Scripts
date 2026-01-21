#!/bin/bash

# --- Configuration ---
SUBSCRIPTIONS=("sub-id-1" "sub-id-2" "sub-id-3")
SERVER_NAMES=("server-prod-01" "server-stage-01" "server-dev-01")

# Common Config
LOCATION="eastus"
RESOURCE_GROUP="rg-postgresql-multisub"
ADMIN_USER="pgadmin"
ADMIN_PASSWORD="YourStrongPassword123!" 
DATABASE_NAME="pgbench"

# --- Pre-Deployment ---
az account show > /dev/null || az login
CLIENT_IP=$(curl -s https://api.ipify.org)

for i in "${!SUBSCRIPTIONS[@]}"; do
    SUB_ID=${SUBSCRIPTIONS[$i]}
    SVR_NAME=${SERVER_NAMES[$i]}
    FQDN="$SVR_NAME.postgres.database.azure.com"

    echo "--------------------------------------------------------"
    echo "Processing Subscription: $SUB_ID"
    az account set --subscription "$SUB_ID"

    # 1. Create Resource Group
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

    # 2. Deploy Server with HA DISABLED and Enhanced Metrics ENABLED
    echo "Deploying $SVR_NAME with HA Disabled..."
    az postgres flexible-server create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SVR_NAME" \
        --location "$LOCATION" \
        --admin-user "$ADMIN_USER" \
        --admin-password "$ADMIN_PASSWORD" \
        --public-access "$CLIENT_IP" \
        --tier "GeneralPurpose" \
        --sku-name "Standard_D2s_v3" \
        --version "17" \
        --zonal-resiliency "Disabled" \
        --output none

    # Enable Enhanced Metrics (Required for Troubleshooting Guides)
    echo "Enabling Enhanced Metrics for $SVR_NAME..."
    az postgres flexible-server parameter set \
        --resource-group "$RESOURCE_GROUP" \
        --server-name "$SVR_NAME" \
        --name "metrics.collector_database_activity" \
        --value "on"

    # 3. Create the empty database
    echo "Creating empty database $DATABASE_NAME..."
    az postgres flexible-server db create \
        --resource-group "$RESOURCE_GROUP" \
        --server-name "$SVR_NAME" \
        --database-name "$DATABASE_NAME" --output none

    # 4. INITIALIZE PGBENCH
    echo "Initializing pgbench tables on $FQDN..."
    export PGPASSWORD="$ADMIN_PASSWORD"
    
    pgbench -i -s 1 -h "$FQDN" -U "$ADMIN_USER" -d "$DATABASE_NAME"
    
    unset PGPASSWORD
    echo "pgbench initialization for $SVR_NAME complete."
done

echo "All deployments finished. You now have 3 servers ready for monitoring demos!"
