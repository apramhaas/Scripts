#!/bin/bash

################################################################################
# Customer/System: ***
# Author:          Andreas Pramhaas
#                  https://github.com/apramhaas/Scripts
# 
# Custom settings for OSV
# Place this script in /repository/upload on both nodes and call after toolkit
# upgrade has finished to reapply the settings specific for this customer.
# Call on one node with "bash postToolkitCustomization.sh" and it will be 
# executed on the other node as well.
# Variable NODE1 and NODE2 can be set to the hostnames of the OSV nodes.
# If the system is a Simplex system, NODE2 should be empty.
# 
# History
# 2025-01-08 Initial version
# 2025-03-20 Optimize password aging handling
#            Better an more status messages
#            added SSH key import example
# 2025-06-05 Add support for Simplex systems
################################################################################

# Configurable hostnames
NODE1="osvoice1"
NODE2="osvoice2"
SCRIPT_PATH="/repository/upload/postToolkitCustomization.sh"
FLAG_FILE="/tmp/osvCustomSettings_done"

# Check if the script is executed as root
if [ "$EUID" -ne 0 ]; then
  echo "$(hostname): This script must be run as root."
  exit 1
fi

# Check if the script has already run on this node
if [ -f "$FLAG_FILE" ]; then
  echo "$(hostname): The script has already been executed on this node."
  exit 0
fi

# Function to run the script on another node
run_on_node() {
  local node=$1
  echo "$(hostname): Executing the script on node: $node"
  ssh "$node" "bash $SCRIPT_PATH"
  if [ $? -ne 0 ]; then
    echo "$(hostname): Error executing the script on $node."
    exit 1
  fi
}

# Execute the chage commands to disable password aging
# predefined system accounts
systemusers=("superad" "sysad" "dbad" "secad" "sym" "root" "solid" "cdr" "webad" "srx")
for user in "${systemusers[@]}"; do
  chage -m 0 -M 9998 -I -1 -E -1 "$user"
  echo "Password policy for $user set: min=0, max=9998, inactive=-1, expire=-1"
done
# additional accounts
# do not set password aging to 'never' as this triggers a OSV password
# expiration alarm for non predefined system accounts
future_date=$(date -d "+3 years" +%Y-%m-%d)
if id "osccesync" &>/dev/null; then  
  chage -m 0 -M 3650 -I -1 -E "$future_date" -W 30 osccesync
  echo "Password policy for osccesync set: min=0, max=3650, inactive=-1, expire=$future_date, warn=30"
fi
if id "osfaultmgr" &>/dev/null; then  
  chage -m 0 -M 3650 -I -1 -E "$future_date" -W 30 osfaultmgr
  echo "Password policy for osfaultmgr set: min=0, max=3650, inactive=-1, expire=$future_date, warn=30"
fi

# Uncomment to add SSH keys for authentication.
# Example given for the sysad account
###
#ssh_key="ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAgEAyzRPOK9/hCWXoJS2GsEBPM8EvyhBCJ8SMys8wthcNrG/AZXhMHcqOIzxRz4R7ku6eTjyDSy6p7WXK5+1KvAv5o3AVtmOJBctWxO9CIc8g/g7iq505aFXnP/NbxynR/PM50RmkSUb1u7Kq5jd6e5kExKgJjw9VkSz/31gXPaCkiHZGcJSHdV8B4bR2C2gTFgkOF7KRXbzMh9WK39w0/NcL0n5n/kYXBOyOU6EPH5wKTSailkd6MrwnNjN1eFtka20wO8QFEWRmcUnnZahO+jM5OwvOGssCiZ3rGL3jbYcW7mP14VJYP7Uh6K7SFGDKz6W6Ihil/ZLcWwWvOMJrIv1a+63AcIKWdRFlRHj/RWH0cCKSbZ4NKKAQ4RKnv2QSpMBlmIe0q1KObOudW9KyHUFF2zgqVSkA/VYXAGK+hq55UMnuWDKHAguew/3wuJG2cIdNOgUVmoWgHfGqWnhRRPJtFqjBR8M+u3mi0Aa1Lcb7EAy4WH4bY+Kszd12ine5XE33f6ME6jPVfy4Z142+SzYb3jMD4hcSWrA0l9WJkZRTu+AEtFgn3dIC8zIBNxzuAwfcIRYOtbaqfxT4FNa/tD0MHeLbHeW+F3CAMQ5vzbqKM+OUmfRoK7SzxIeEs4LAUlI9utvkcWpU9CKsOgBKIMaaBlF2sDCfc58AM4QGkEHnW8= root@admin.lab.local"
#auth_file="/home/sysad/.ssh/authorized_keys"
#ssh_dir=$(dirname "$auth_file")
#
#mkdir -p "$ssh_dir"
#touch "$auth_file"
#
#if ! grep -q "$ssh_key" "$auth_file"; then
#  echo "$ssh_key" >> "$auth_file"
#  echo "SSH key has been added to $auth_file."
#else
#  echo "SSH key is already present in $auth_file."
#fi
#
#chmod 700 "$ssh_dir"
#chown sysad:rtpgrp "$ssh_dir"
#chmod 600 "$auth_file"
#chown sysad:rtpgrp "$auth_file"
###

# Modify /etc/ssh/sshd_config
sshd_config="/etc/ssh/sshd_config"
sed -i.bak -e "s/^\(PermitRootLogin\s\+\)without-password/#\1without-password/" \
           -e "s/^\(PermitRootLogin\s\+\)no/#\1no/" "$sshd_config"

echo "$(hostname): The file $sshd_config has been updated. Backup created at $sshd_config.bak."

# Restart the SSH service
if systemctl restart sshd; then
  echo "$(hostname): The SSH service has been restarted successfully."
else
  echo "$(hostname): Error restarting the SSH service. Please check."
  exit 1
fi

# Remove OSV migration toolkit
echo "$(hostname): Remove OSV migration toolkit"
rpm -e UNSPmigration

# Mark the script as executed on this node
touch "$FLAG_FILE"
echo "$(hostname): The script has been executed on this node."

# Run the script on the other node
if [ "$(hostname)" == "$NODE1" ]; then
  if [ -n "$NODE2" ]; then
    run_on_node "$NODE2"
  else
    echo "$(hostname): NODE2 variable is empty - probably a Simplex system. Not running on other node."
  fi
elif [ "$(hostname)" == "$NODE2" ]; then
  run_on_node "$NODE1"
else
  echo "$(hostname): Unknown hostname: $(hostname). The script only supports $NODE1 and $NODE2."
  exit 1
fi

# Remove flag file in the end
rm "$FLAG_FILE"
echo "$(hostname): ########   postToolkitCustomization.sh done   ########"
exit 0
