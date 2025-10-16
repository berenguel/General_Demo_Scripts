#!/bin/bash

# --- Configuration: Customize these values ---

# Azure Details
LOCATION="uksouth"                    # Azure region (e.g., westus3, eastus, uksouth)
RESOURCE_GROUP="demo_flex1"        # Name of the resource group


SUBSCRIPTION_ID="<insert_here_subscription_id>"

# PostgreSQL Server Details
SERVER_NAME="<insert_server_name>"         # Must be globally unique, 3-63 chars, lowercase, letters, numbers, and hyphens
ADMIN_USER="demo_flex1"                               # Admin username (not 'azure_superuser')
# IMPORTANT: Replace 'YourStrongPassword123' with a complex password
# Password must be 8-128 chars and contain characters from three of the following:
# English uppercase, English lowercase, numbers, and non-alphanumeric characters.
ADMIN_PASSWORD="<YourStrongPassword123>"

# SKU (Tier and Size)
# Tier options: Burstable, GeneralPurpose, MemoryOptimized
# SKU name examples: Standard_B1ms, Standard_D2s_v3 (GeneralPurpose, 2 vCores)
TIER="GeneralPurpose"
SKU_NAME="Standard_D2s_v3"
VERSION="17"                                    # PostgreSQL version (e.g., 11, 12, 13, 14, 15, 16)

# Networking and Firewall
# To find your current public IP, visit a site like 'whatismyip.com'
CLIENT_IP="<your_ip_address>"                         # YOUR LOCAL PUBLIC IP ADDRESS
FIREWALL_RULE_NAME="AllowMyIP"                        

# Database to create after server deployment
DATABASE_NAME="demo_flex1"                           # Name of the initial database to create

# ---------------------------------------------
# --- Pre-Deployment Check and Login ---
# ---------------------------------------------

echo "Starting Azure Database for PostgreSQL deployment..."

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
# ---------------------------------------------
# --- Pre-Deployment Check and Login ---
# ---------------------------------------------

echo "Starting Azure Database for PostgreSQL deployment..."

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
    # --- UPDATED IP RETRIEVAL ---
    CLIENT_IP=$(curl -s https://api.ipify.org)
    # -----------------------------
    
    # Simple check to see if the curl command was successful and returned a non-empty string
    if [ $? -ne 0 ] || [ -z "$CLIENT_IP" ]; then
        echo "ERROR: Could not retrieve public IP. Please update the CLIENT_IP variable manually in the script."
        exit 1
    fi
    echo "Your detected public IP is: $CLIENT_IP"
fi

# ---------------------------------------------
# --- Deployment Commands ---
# ---------------------------------------------

# ---------------------------------------------
# --- Deployment Commands ---
# ---------------------------------------------

# 4. Create the Resource Group
echo "Creating resource group: $RESOURCE_GROUP in $LOCATION..."
az group create --name $RESOURCE_GROUP --location $LOCATION --output none

# 5. Deploy the Azure Database for PostgreSQL Flexible Server
echo "Deploying PostgreSQL Flexible Server: $SERVER_NAME. This will take several minutes..."
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
    --high-availability Disabled \
    --zone 1 \
    --output jsonc

if [ $? -ne 0 ]; then
    echo "Server deployment failed. Exiting."
    exit 1
fi
echo "PostgreSQL Flexible Server deployed successfully."

# 6. Create an additional database
echo "Creating database: $DATABASE_NAME..."
az postgres flexible-server db create \
    --resource-group $RESOURCE_GROUP \
    --server-name $SERVER_NAME \
    --database-name $DATABASE_NAME \
    --output none

# 7. Add a firewall rule for public IP connectivity (Allowing ONLY your IP)
echo "Configuring firewall rule to allow ONLY your IP ($CLIENT_IP)..."

# Allow your local machine's public IP
az postgres flexible-server firewall-rule create \
    --resource-group $RESOURCE_GROUP \
    --server-name $SERVER_NAME \
    --name $FIREWALL_RULE_NAME \
    --start-ip-address $CLIENT_IP \
    --end-ip-address $CLIENT_IP \
    --output none

echo "Firewall rules configured successfully."

# ---------------------------------------------
# --- Output Connection Details ---
# ---------------------------------------------

echo -e "\n--- Connection Details ---"
echo "Server Name:     $SERVER_NAME.postgres.database.azure.com"
echo "Resource Group:  $RESOURCE_GROUP"
echo "Admin User:      $ADMIN_USER"
echo "Admin Password:  $ADMIN_PASSWORD (use with caution, consider Azure Key Vault)"
echo "Default Database: postgres"
echo "New Database:    $DATABASE_NAME"
echo "Allowed IP:      $CLIENT_IP"
echo -e "Port:            5432\n"

echo "You can connect using psql with the following command (you will be prompted for the password):"
echo "psql \"host=$SERVER_NAME.postgres.database.azure.com port=5432 dbname=postgres user=$ADMIN_USER\""

# ---------------------------------------------
# --- Cleanup Command ---
# ---------------------------------------------
echo -e "\n--- Cleanup Command (Optional) ---"
echo "To delete all resources created by this script, run:"
echo "az group delete --name $RESOURCE_GROUP --yes --no-wait"
