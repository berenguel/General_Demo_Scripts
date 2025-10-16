#!/bin/bash

# --- Configuration: Customize these values ---

# Azure Details
RESOURCE_GROUP="<insert_resource_group>"       # Primary Resource Group Name (Will contain Primary and all Replica servers)
SUBSCRIPTION_ID="<insert_here_subscription_id>"

# PostgreSQL Server Details
LOCATION="<insert_region>"           			# Primary Server region (e.g., westus3, eastus)
SERVER_NAME="<insert_server_name>"             	# Must be globally unique, Primary Server Name
ADMIN_USER="<insert_admin_user>"               	# Admin username (not 'azure_superuser')
ADMIN_PASSWORD="<YourStrongPassword123>"		# IMPORTANT: Replace 'YourStrongPassword123' with a complex password

# SKU (Tier and Size)
TIER="GeneralPurpose"
SKU_NAME="Standard_D2s_v3"
VERSION="17"                                   # PostgreSQL version

# High Availability (HA)
# Options: ZoneRedundant (Recommended for HA), SameZone, Disabled
HA_MODE="SameZone" # High Availability configured within a single Availability Zone

# Read Replica Configuration (Up to 5 Replicas)
# Specify the region for each replica, separated by spaces. 
# The number of regions listed determines the number of replicas deployed (max 5).
# Example for 1 in-region and 1 cross-region: "westus3 eastus"
REPLICA_LOCATIONS="<insert_replica_locations_separated_by_space>" 

# Virtual Endpoint Configuration
# A virtual endpoint will be created and associated with the FIRST replica deployed.
VIRTUAL_ENDPOINT_NAME="<insert_endpoint_name>"
ENDPOINT_REPLICA_NAME="" # This will be set dynamically in the script

# Networking and Firewall
# NOTE: Using '0.0.0.0' below will trigger IP detection using api.ipify.org
CLIENT_IP="0.0.0.0"                            # YOUR LOCAL PUBLIC IP ADDRESS (0.0.0.0 = auto-detect)
FIREWALL_RULE_NAME="AllowMyIP"                 # Base name for the firewall rule

# Database to create after server deployment
DATABASE_NAME="pgbench"

# ---------------------------------------------
# --- Pre-Deployment Check and Login ---
# ---------------------------------------------

echo "Starting Azure Database for PostgreSQL HA and Read Replica deployment..."

# 1. Log in to Azure
az account show > /dev/null
if [ $? -ne 0 ]; then
    echo "Logging into Azure CLI..."
    az login
    if [ $? -ne 0 ]; then
        echo "Azure login failed. Exiting."
        exit 1
    fi
fi

# 2. SET THE TARGET SUBSCRIPTION
echo "Setting target subscription to: $SUBSCRIPTION_ID"
az account set --subscription "$SUBSCRIPTION_ID"

# 3. Get current IP for firewall rule
if [ "$CLIENT_IP" == "0.0.0.0" ] || [ "$CLIENT_IP" == "<your_ip_address>" ]; then
    echo "Attempting to retrieve your current public IP address using api.ipify.org..."
    CLIENT_IP=$(curl -s https://api.ipify.org)
    
    if [ $? -ne 0 ] || [ -z "$CLIENT_IP" ]; then
        echo "ERROR: Could not retrieve public IP. Please update the CLIENT_IP variable manually in the script."
        exit 1
    fi
    echo "Your detected public IP is: $CLIENT_IP"
fi

# ---------------------------------------------
# --- Deployment Commands (Primary Server) ---
# ---------------------------------------------

# 4. Create the Primary Resource Group
echo "Creating resource group: $RESOURCE_GROUP in $LOCATION..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

# 5. Deploy the Azure Database for PostgreSQL Flexible Server (Primary with HA)
echo "Deploying PRIMARY PostgreSQL Flexible Server with HA: $SERVER_NAME in $LOCATION. This will take several minutes..."
az postgres flexible-server create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$SERVER_NAME" \
    --location "$LOCATION" \
    --tier "$TIER" \
    --sku-name "$SKU_NAME" \
    --version "$VERSION" \
    --admin-user "$ADMIN_USER" \
    --admin-password "$ADMIN_PASSWORD" \
    --public-access "$CLIENT_IP" \
    --storage-size 32 \
    --backup-retention 7 \
    --high-availability "$HA_MODE" \
    --output jsonc

if [ $? -ne 0 ]; then
    echo "Primary Server deployment failed. Exiting."
    exit 1
fi
echo "Primary PostgreSQL Flexible Server deployed successfully with HA ($HA_MODE)."

# 6. Create an additional database on Primary
echo "Creating database: $DATABASE_NAME on primary server..."
az postgres flexible-server db create \
    --resource-group "$RESOURCE_GROUP" \
    --server-name "$SERVER_NAME" \
    --database-name "$DATABASE_NAME" \
    --output none

# 7. Add a firewall rule for public IP connectivity (Allowing ONLY your IP on Primary)
echo "Configuring firewall rule to allow ONLY your IP ($CLIENT_IP) on primary server..."
az postgres flexible-server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --server-name "$SERVER_NAME" \
    --name "$FIREWALL_RULE_NAME" \
    --start-ip-address "$CLIENT_IP" \
    --end-ip-address "$CLIENT_IP" \
    --output none

echo "Firewall rules configured successfully on primary server."

# ---------------------------------------------
# --- Deployment Commands (Read Replicas) ---
# ---------------------------------------------

# 8. Create the Read Replicas (Looping through REPLICA_LOCATIONS)
echo "Creating read replica(s) based on regions in REPLICA_LOCATIONS..."
i=0
LAST_REPLICA_NAME=""

for REPLICA_REGION in $REPLICA_LOCATIONS;
do
    i=$((i+1))
    REPLICA_NAME="${SERVER_NAME}-replica-${i}"
    REPLICA_RULE_NAME="${FIREWALL_RULE_NAME}-replica-${i}"
    LAST_REPLICA_NAME="$REPLICA_NAME" # Update variable for output summary

    if [ "$i" -eq 1 ]; then
        # Capture the name of the first replica to be used for the virtual endpoint
        ENDPOINT_REPLICA_NAME="$REPLICA_NAME"
    fi

    echo "Creating replica $i ($REPLICA_NAME) in $REPLICA_REGION..."

    az postgres flexible-server replica create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$REPLICA_NAME" \
        --source-server "$SERVER_NAME" \
        --location "$REPLICA_REGION" \
        --output none

    if [ $? -ne 0 ]; then
        echo "Read Replica $REPLICA_NAME deployment failed. Stopping further replicas."
        exit 1
    fi
    
    # Apply the firewall rule to the new replica
    echo "Configuring firewall rule ($REPLICA_RULE_NAME) for replica $REPLICA_NAME..."
    az postgres flexible-server firewall-rule create \
        --resource-group "$RESOURCE_GROUP" \
        --server-name "$REPLICA_NAME" \
        --name "$REPLICA_RULE_NAME" \
        --start-ip-address "$CLIENT_IP" \
        --end-ip-address "$CLIENT_IP" \
        --output none

    echo "Successfully created and secured replica: $REPLICA_NAME"
done

REPLICA_COUNT=$i
if [ -z "$LAST_REPLICA_NAME" ]; then
    echo "No replicas were created, check REPLICA_LOCATIONS configuration."
else
    echo "Total $REPLICA_COUNT read replicas deployed successfully."
fi

# ---------------------------------------------
# --- Deployment Commands (Virtual Endpoint) ---
# ---------------------------------------------

if [ "$ENDPOINT_REPLICA_NAME" != "" ]; then
    # 9. Create the Read Virtual Endpoint, linked to the first replica
    echo "Creating Virtual Endpoint '$VIRTUAL_ENDPOINT_NAME' and associating it with the first replica ($ENDPOINT_REPLICA_NAME)..."
    az postgres flexible-server virtual-endpoint create \
        --resource-group "$RESOURCE_GROUP" \
        --server-name "$SERVER_NAME" \
        --endpoint-type Read \
        --endpoint-name "$VIRTUAL_ENDPOINT_NAME" \
        --member-server "$ENDPOINT_REPLICA_NAME" \
        --output jsonc

    if [ $? -ne 0 ]; then
        echo "Virtual Endpoint deployment failed."
        # Do not exit, continue to output connection details
    fi
    echo "Virtual Endpoint created successfully."
fi

# ---------------------------------------------
# --- Output Connection Details ---
# ---------------------------------------------

echo -e "\n--- Connection Details ---"
echo "Primary Server (HA):    $SERVER_NAME.postgres.database.azure.com"
echo "Virtual Endpoint (Read): $VIRTUAL_ENDPOINT_NAME.postgres.database.azure.com"
echo "Primary Resource Group: $RESOURCE_GROUP ($LOCATION)"
echo "HA Mode:                $HA_MODE (Same-Zone High Availability)"
echo "Total Replicas Deployed: $REPLICA_COUNT"
echo "Admin User:             $ADMIN_USER"
echo "Allowed IP:             $CLIENT_IP"
echo "Port:                   5432\n"

echo "You can connect to the PRIMARY server using psql:"
echo "psql \"host=$SERVER_NAME.postgres.database.azure.com port=5432 dbname=postgres user=$ADMIN_USER\""

if [ "$ENDPOINT_REPLICA_NAME" != "" ]; then
    echo "You can connect to the VIRTUAL READ ENDPOINT using psql (This points to $ENDPOINT_REPLICA_NAME):"
    echo "psql \"host=$VIRTUAL_ENDPOINT_NAME.postgres.database.azure.com port=5432 dbname=postgres user=$ADMIN_USER\""
fi

# ---------------------------------------------
# --- Cleanup Commands (Optional) ---
# ---------------------------------------------
echo -e "\n--- Cleanup Commands (Optional) ---"
echo "To delete all resources (Primary Server, $REPLICA_COUNT Read Replica(s), and Virtual Endpoint) created by this script, run:"
echo "az group delete --name $RESOURCE_GROUP --yes --no-wait"