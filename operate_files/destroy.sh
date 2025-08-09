#!/bin/bash

# Usage: operate <openrc> <tag> <ssh_key>

# Delete one VM based on name pattern and remove its IP from ./ips file
delete_vm_by_pattern() {
    local pattern=$1
    echo "Searching for VMs with name pattern: $pattern"
    
    # Find the first VM ID that matches the pattern
    vm_id=$(openstack server list -f value -c ID -c Name | awk -v pat="$pattern" '$2 ~ pat {print $1; exit}')
    
    if [ -z "$vm_id" ]; then
        echo "No VM found matching the pattern: $pattern"
        return 1
    fi
    
    # Get VM details
    vm_name=$(openstack server show $vm_id -c name -f value)
    vm_ip=$(openstack server show $vm_id -c addresses -f value | grep -oP '\d+\.\d+\.\d+\.\d+')
    
    echo "Deleting VM: $vm_name (ID: $vm_id, IP: $vm_ip)"
    openstack server delete $vm_id --wait
    
    if [ -n "$vm_ip" ]; then
        echo "Removing IP $vm_ip from storage/ips file"
        sed -i "/$vm_ip/d" ./storage/ips
    else
        echo "No IP found for the VM"
    fi
}

# Call the function with the pattern
delete_vm_by_pattern ""^vm.*_$2$""