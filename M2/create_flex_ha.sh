
#!/bin/bash

# --- Configuration: Customize these values ---

# Azure Details
LOCATION="<insert_location>"           # Primary Azure region (e.g., westus3, eastus, uksouth)
RESOURCE_GROUP="<insert_resource_group>"       # Primary Resource Group Name (Will contain Primary and all Replica servers)
SUBSCRIPTION_ID="<insert_here_subscription_id>"

# PostgreSQL Server Details
SERVER_NAME="<insert_server_name>"             # Must be globally unique, Primary Server Name
ADMIN_USER="<insert_admin_user>"               # Admin username (not 'azure_superuser')
# IMPORTANT: Replace 'YourStrongPassword123' with a complex password
ADMIN_PASSWORD="<YourStrongPassword123>"

# SKU (Tier and Size)
TIER="GeneralPurpose"
SKU_NAME="Standard_D2s_v3"
VERSION="17"                                   # PostgreSQL version

# High Availability (HA)
# Options: ZoneRedundant (Recommended for HA), SameZone, Disabled
HA_MODE="ZoneRedundant"

# Read Replica Configuration
# MUST be a different region than LOCATION if using ZoneRedundant HA on Primary
REPLICA_LOCATION="<insert_location>"           # Region for the read replicas (e.g., eastus, westeurope)
REPLICA_COUNT="<insert_number_here>"           # Number of read replicas to deploy (e.g., 2)

# Networking and Firewall
# NOTE: Using '0.0.0.0' below will trigger IP detection using api.ipify.org
CLIENT_IP="0.0.0.0"                            # YOUR LOCAL PUBLIC IP ADDRESS (0.0.0.0 = auto-detect)
FIREWALL_RULE_NAME="AllowMyIP"                 # Base name for the firewall rule

# Database to create after server deployment
DATABASE_NAME="pgbench"

# ---------------------------------------------
# --- Pre-Deployment Check and Login ---
# ---------------------------------------------

echo "Starting Azure Database for PostgreSQL Primary & HA..."

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
az group create --name $RESOURCE_GROUP --location $LOCATION --output none

# 5. Deploy the Azure Database for PostgreSQL Flexible Server (Primary with HA)
echo "Deploying PRIMARY PostgreSQL Flexible Server with HA: $SERVER_NAME in $LOCATION. This will take several minutes..."
az postgres flexible-server create \
    --resource-group $RESOURCE_GROUP \
    --name $SERVER_NAME \
    --location $LOCATION \
    --tier $TIER \
    --sku-name $SKU_NAME \
    --version $VERSION \
    --admin-user $ADMIN_USER \
    --admin-password $ADMIN_PASSWORD \
    --public-access $CLIENT_IP \
    --storage-size 32 \
    --backup-retention 7 \
    --high-availability $HA_MODE \
    --output jsonc

if [ $? -ne 0 ]; then
    echo "Primary Server deployment failed. Exiting."
    exit 1
fi
echo "Primary PostgreSQL Flexible Server deployed successfully with HA ($HA_MODE)."

# 6. Create an additional database on Primary
echo "Creating database: $DATABASE_NAME on primary server..."
az postgres flexible-server db create \
    --resource-group $RESOURCE_GROUP \
    --server-name $SERVER_NAME \
    --database-name $DATABASE_NAME \
    --output none

# 7. Add a firewall rule for public IP connectivity (Allowing ONLY your IP on Primary)
echo "Configuring firewall rule to allow ONLY your IP ($CLIENT_IP) on primary server..."
az postgres flexible-server firewall-rule create \
    --resource-group $RESOURCE_GROUP \
    --server-name $SERVER_NAME \
    --name $FIREWALL_RULE_NAME \
    --start-ip-address $CLIENT_IP \
    --end-ip-address $CLIENT_IP \
    --output none

echo "Firewall rules configured successfully on primary server."

# ---------------------------------------------
# --- Deployment Commands (Read Replica) ---
# ---------------------------------------------

# Note: All replicas will be placed into the existing $RESOURCE_GROUP.

# 8. Create the Read Replicas (up to $REPLICA_COUNT)
echo "Creating $REPLICA_COUNT read replica(s)..."
LAST_REPLICA_NAME="" # Initialize a variable to hold the name of the last replica created for output

for i in $(seq 1 $REPLICA_COUNT); 
do
    REPLICA_NAME="${SERVER_NAME}-replica-${i}"
    REPLICA_RULE_NAME="${FIREWALL_RULE_NAME}-replica-${i}"
    LAST_REPLICA_NAME="$REPLICA_NAME" # Update variable for output summary

    echo "Creating replica $REPLICA_NAME in $REPLICA_LOCATION..."
    # Corrected parameter: using --name instead of --replica-name
    az postgres flexible-server replica create \
        --resource-group $RESOURCE_GROUP \
        --name $REPLICA_NAME \
        --source-server $SERVER_NAME \
        --location $REPLICA_LOCATION \
        --output none

    if [ $? -ne 0 ]; then
        echo "Read Replica $REPLICA_NAME deployment failed. Stopping further replicas."
        # If the script fails here, the primary server and any previously created replicas still exist.
        exit 1
    fi
    
    # Apply the firewall rule to the new replica
    echo "Configuring firewall rule ($REPLICA_RULE_NAME) for replica $REPLICA_NAME..."
    # Corrected command: explicitly using --server-name and --end-ip-address
    az postgres flexible-server firewall-rule create \
        --resource-group $RESOURCE_GROUP \
        --server-name $REPLICA_NAME \
        --name $REPLICA_RULE_NAME \
        --start-ip-address $CLIENT_IP \
        --end-ip-address $CLIENT_IP \
        --output none

    echo "Successfully created and secured replica: $REPLICA_NAME"
done

if [ -z "$LAST_REPLICA_NAME" ]; then
    echo "No replicas were created, check REPLICA_COUNT configuration."
else
    echo "All $REPLICA_COUNT read replicas deployed successfully."
fi


# ---------------------------------------------
# --- Output Connection Details ---
# ---------------------------------------------

echo -e "\n--- Connection Details ---"
echo "Primary Server (HA):    $SERVER_NAME.postgres.database.azure.com"
echo "Example Replica:        $LAST_REPLICA_NAME.postgres.database.azure.com"
echo "Total Replicas Deployed: $REPLICA_COUNT"
echo "Primary Resource Group: $RESOURCE_GROUP ($LOCATION)"
echo "Replica Location:       $REPLICA_LOCATION"
echo "Admin User:             $ADMIN_USER"
echo "Allowed IP:             $CLIENT_IP"
echo -e "Port:                   5432\n"

echo "You can connect to the PRIMARY server using psql with the following command (you will be prompted for the password):"
echo "psql \"host=$SERVER_NAME.postgres.database.azure.com port=5432 dbname=postgres user=$ADMIN_USER\""
echo "Remember to use the replica servers for read-only queries."
echo "Example psql command for the last created replica:"
echo "psql \"host=$LAST_REPLICA_NAME.postgres.database.azure.com port=5432 dbname=postgres user=$ADMIN_USER\""

# ---------------------------------------------
# --- Cleanup Commands (Optional) ---
# ---------------------------------------------
echo -e "\n--- Cleanup Commands (Optional) ---"
echo "To delete all resources (Primary Server and $REPLICA_COUNT Read Replica(s)) created by this script, run:"
echo "az group delete --name $RESOURCE_GROUP --yes --no-wait"
