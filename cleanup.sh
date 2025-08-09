#!/bin/bash

# Usage: operate <openrc> <tag> <ssh_key_path>
#                 $1      $2     $3

. $1

# Generate key name
key_name="key_$2"

# Reassign $3 to the new key name

# source venv/bin/activate
# Function to delete resources by tag
delete_by_tag() {
    local resource_type=$1
    local tag=$2
    echo "Deleting $resource_type resources with tag: $tag"
    for resource in $(openstack $resource_type list --tag $tag -f value -c ID); do
        echo "Deleting $resource_type: $resource"
        openstack $resource_type delete $resource
    done
}

# Delete VMs based on name pattern
delete_vms_by_pattern() {
    local pattern=$1
    echo "Deleting VMs with name pattern: $pattern"
    for vm in $(openstack server list -f value -c ID -c Name | awk -v pat="$pattern" '$2 ~ pat {print $1}'); do
        echo "Deleting VM: $vm"
        openstack server delete $vm --wait
    done
}

# Delete VMs
delete_vms_by_pattern "_$2$"

# Delete floating IPs associated with the tag
for ip in $(openstack floating ip list --tag $2 -f value -c "Floating IP Address"); do
    echo "Deleting floating IP: $ip"
    openstack floating ip delete $ip
done

# Delete the router if it exists
ROUTER_NAME="router_$2"
if openstack router show $ROUTER_NAME &>/dev/null; then
    echo "Removing subnet interface from router: $ROUTER_NAME"
    SUBNET_NAME="subnet_$2"
    openstack router remove subnet $ROUTER_NAME $SUBNET_NAME
    
    echo "Removing external gateway from router: $ROUTER_NAME"
    openstack router unset --external-gateway $ROUTER_NAME
    
    echo "Deleting router: $ROUTER_NAME"
    openstack router delete $ROUTER_NAME
fi

# Delete the subnet
delete_by_tag "subnet" $2

# Delete the network
delete_by_tag "network" $2

# Delete the security group
delete_by_tag "security group" $2

# Delete ports associated with the tag
delete_by_tag "port" $2

#  Delete the SSH key
openstack keypair delete $key_name

echo "Cleanup completed"
