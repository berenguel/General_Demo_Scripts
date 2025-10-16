# **Module 2**
If you are uploading this file to Azure Cloud Shell or other locations you must run the following commands:

# Prepare and run the creation script with Primary Server & HA
```sql
dos2unix 001_create_flex_ha.sh  
chmod +x 001_create_flex_ha.sh  # Grants executable permission

# Execute the script
./001_create_flex_ha.sh

```

# Prepare and run the creation script with Primary Server, HA & DR
```sql
dos2unix 002_create_flex_ha_dr.sh  
chmod +x 002_create_flex_ha_dr.sh  # Grants executable permission

# Execute the script
./002_create_flex_ha_dr.sh

```

# Prepare and run the deletion script
```sql
dos2unix 003_clean_up.sh   # Fixes line endings
chmod +x 003_clean_up.sh   # Grants executable permission

# Execute the script
./003_clean_up.sh
```
