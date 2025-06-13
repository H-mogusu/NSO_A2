#!/bin/bash

# -----------------------------------------
# OpenStack Environment Cleanup Script
# Purpose: Remove all resources associated with a given deployment tag.
# Usage: ./cleanup.sh <openrc> <tag> <ssh_key>
# -----------------------------------------

# Validate required arguments
: ${1:?"Usage: $0 <openrc_file> <tag> <ssh_key>"}
: ${2:?"Usage: $0 <openrc_file> <tag> <ssh_key>"}
: ${3:?"Usage: $0 <openrc_file> <tag> <ssh_key>"}

# Source the OpenStack credentials
openrc_file=$1
tag=$2
ssh_key=$3
source "$openrc_file"

echo "$(date) Starting cleanup for tag: $tag"

# Define naming conventions
network_name="${tag}_network"
subnet_name="${tag}_subnet"
router_name="${tag}_router"
keypair_name="${tag}_key"
security_group_name="${tag}_security_group"

# Cleanup Servers
echo "$(date) Removing servers..."
servers=$(openstack server list --name "$tag" -c ID -f value)
if [ -n "$servers" ]; then
  for server in $servers; do
    openstack server delete "$server"
  done
  echo "$(date) Servers removed."
else
  echo "$(date) No servers found."
fi

# Cleanup Floating IPs (regardless of status)
echo "$(date) Removing floating IPs..."
floating_ips=$(openstack floating ip list -f value -c ID)
if [ -n "$floating_ips" ]; then
  for fip in $floating_ips; do
    openstack floating ip delete "$fip"
  done
  echo "$(date) Floating IPs removed."
else
  echo "$(date) No floating IPs found."
fi

# Cleanup Keypairs
echo "$(date) Removing keypairs..."
keypairs=$(openstack keypair list -f value -c Name | grep "^${tag}")
if [ -n "$keypairs" ]; then
  for key in $keypairs; do
    openstack keypair delete "$key"
  done
  echo "$(date) Keypairs removed."
else
  echo "$(date) No keypairs found."
fi

# Cleanup Router Interfaces and Subnets
echo "$(date) Removing subnets and router interfaces..."
subnet_ids=$(openstack subnet list --tag "$tag" -c ID -f value)
if [ -n "$subnet_ids" ]; then
  for subnet_id in $subnet_ids; do
    openstack router remove subnet "$router_name" "$subnet_id" 2>/dev/null
    openstack subnet delete "$subnet_id"
  done
  echo "$(date) Subnets and interfaces removed."
else
  echo "$(date) No subnets found."
fi

# Cleanup Router Ports (in case any leftover ports exist)
echo "$(date) Removing router ports..."
router_ports=$(openstack port list --router "$router_name" -c ID -f value)
if [ -n "$router_ports" ]; then
  for port in $router_ports; do
    openstack port delete "$port"
  done
  echo "$(date) Router ports removed."
else
  echo "$(date) No router ports found."
fi

# Cleanup Routers
echo "$(date) Removing routers..."
routers=$(openstack router list --tag "$tag" -c ID -f value)
if [ -n "$routers" ]; then
  for rtr in $routers; do
    openstack router delete "$rtr"
  done
  echo "$(date) Routers removed."
else
  echo "$(date) No routers found."
fi

# Cleanup Networks
echo "$(date) Removing networks..."
networks=$(openstack network list --tag "$tag" -c Name -f value)
if [ -n "$networks" ]; then
  for net in $networks; do
    openstack network delete "$net"
  done
  echo "$(date) Networks removed."
else
  echo "$(date) No networks found."
fi

# Cleanup Security Groups
echo "$(date) Removing security groups..."
security_groups=$(openstack security group list -f value -c Name | grep "^${tag}")
if [ -n "$security_groups" ]; then
  for sg in $security_groups; do
    openstack security group delete "$sg"
  done
  echo "$(date) Security groups removed."
else
  echo "$(date) No security groups found."
fi

# Cleanup Available Volumes (if any were created)
echo "$(date) Removing volumes..."
volumes=$(openstack volume list --status available -f value -c ID)
if [ -n "$volumes" ]; then
  for vol in $volumes; do
    openstack volume delete "$vol"
  done
  echo "$(date) Volumes removed."
else
  echo "$(date) No available volumes found."
fi

# Remove local SSH and config files
echo "$(date) Cleaning up local files..."
rm -f config known_hosts floating_ip1 floating_ip2 hostsfile
find . -name '*floating_ip*' -delete
echo "$(date) Local config files removed."

echo "$(date) Cleanup completed for tag: $tag"

# Report cleanup completion and duration
echo "$(date) cleanup done."
duration=$SECONDS
echo "$(date) $((duration / 60)) minutes and $((duration % 60)) seconds used to cleanup tag: $tag"


echo "======================================"
echo "$(date) Post-cleanup resource check starting…"
echo "======================================"

# Check active servers
echo "Active servers:"
servers=$(openstack server list --status ACTIVE --long -f value -c ID)
if [ -z "$servers" ]; then
    echo "Zero (none exist)"
else
    openstack server list --status ACTIVE --long -f table
fi
echo

# Check floating IPs
echo "Floating IPs still allocated:"
fips=$(openstack floating ip list -f value -c ID)
if [ -z "$fips" ]; then
    echo "Zero (none exist)"
else
    openstack floating ip list -f table
fi
echo

# Check networks
echo "Networks still existing:"
networks=$(openstack network list -f value -c ID)
if [ -z "$networks" ]; then
    echo "Zero (none exist)"
else
    while read -r net_id; do
        is_ext=$(openstack network show "$net_id" -f value -c router:external)
        net_name=$(openstack network show "$net_id" -f value -c name)
        if [ "$is_ext" == "True" ]; then
            echo "$net_name ($net_id) → External network"
        else
            echo "$net_name ($net_id)"
        fi
    done <<< "$networks"
fi
echo

# Check routers
echo "Routers still existing:"
routers=$(openstack router list -f value -c ID)
if [ -z "$routers" ]; then
    echo "Zero (none exist)"
else
    openstack router list -f table
fi
echo

# Check subnets
echo "Subnets still existing:"
subnets=$(openstack subnet list -f value -c ID)
if [ -z "$subnets" ]; then
    echo "Zero (none exist)"
else
    openstack subnet list -f table
fi
echo

# Check security groups
echo "Security groups still existing:"
secgroups=$(openstack security group list -f value -c Name)
if [ -z "$secgroups" ]; then
    echo "Zero (none exist)"
else
    if [ "$secgroups" == "default" ]; then
        echo "Only 'default' security group present."
    else
        openstack security group list -f table
    fi
fi
echo

# Check keypairs
echo "Keypairs still existing:"
keypairs=$(openstack keypair list -f value -c Name)
if [ -z "$keypairs" ]; then
    echo "Zero (none exist)"
else
    openstack keypair list -f table
fi
echo

echo "============================================"
echo "$(date) Post-cleanup resource check completed"
duration=$SECONDS
echo "$(date) $((duration / 60)) minutes and $((duration % 60)) seconds used to for complete cleanup"
echo "============================================"

