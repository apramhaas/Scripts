#!/bin/bash

################################################################################
# Customer:       ***
# Author:         Andreas Pramhaas, Mitel Austria GmbH
# 
# Custom settings for OSV
# Place this script in /repository/upload on both nodes and call after toolkit
# upgrade has finished to reapply the settings specific for this customer.
# Call on one node with "bash postToolkitCustomization.sh" and it will be executed on 
# the other node as well.
# 
# History
# 2025-01-08 Initial version
################################################################################

# Configurable hostnames
NODE1="osvoice1"
NODE2="osvoice2"
SCRIPT_PATH="/repository/upload/postToolkitCustomization.sh"
FLAG_FILE="/tmp/osvCustomSettings_done"

# Check if the script is executed as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

# Check if the script has already run on this node
if [ -f "$FLAG_FILE" ]; then
  echo "The script has already been executed on this node."
  exit 0
fi

# Function to run the script on another node
run_on_node() {
  local node=$1
  echo "Executing the script on node: $node"
  ssh "$node" "bash $SCRIPT_PATH"
  if [ $? -ne 0 ]; then
    echo "Error executing the script on $node."
    exit 1
  fi
}

# Execute the chage commands to disable password aging
# predefined system accounts
users=("superad" "sysad" "dbad" "secad" "sym" "root" "solid" "cdr" "webad" "srx")
for user in "${users[@]}"; do
  chage -m 0 -M 9998 -I -1 -E -1 "$user"
done
# additional accounts
chage -m 0 -M 3650 -I -1 -E 2027-12-31 -W 30 osccesync
chage -m 0 -M 3650 -I -1 -E 2027-12-31 -W 30 osfaultmgr

# Modify /etc/ssh/sshd_config
sshd_config="/etc/ssh/sshd_config"
sed -i.bak -e "s/^\(PermitRootLogin\s\+\)without-password/#\1without-password/" \
           -e "s/^\(PermitRootLogin\s\+\)no/#\1no/" "$sshd_config"

echo "The file $sshd_config has been updated. Backup created at $sshd_config.bak."

# Restart the SSH service
if systemctl restart sshd; then
  echo "The SSH service has been restarted successfully."
else
  echo "Error restarting the SSH service. Please check."
  exit 1
fi

# Remove OSV migration toolkit
echo "Remove OSV migration toolkit"
rpm -e UNSPmigration

# Mark the script as executed on this node
touch "$FLAG_FILE"
echo "The script has been executed on this node."

# Run the script on the other node
if [ "$(hostname)" == "$NODE1" ]; then
  run_on_node "$NODE2"
elif [ "$(hostname)" == "$NODE2" ]; then
  run_on_node "$NODE1"
else
  echo "Unknown hostname: $(hostname). The script only supports $NODE1 and $NODE2."
  exit 1
fi

# Remove flag file in the end
rm "$FLAG_FILE"

exit 0
