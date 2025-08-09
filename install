#!/bin/bash

# Track the time taken for deployment
SECONDS=0 

# Ensure the required arguments are provided
: ${1:?" Please specify the openrc file, tag, and ssh_key"}
: ${2:?" Please specify the openrc file, tag, and ssh_key"}
: ${3:?" Please specify the openrc file, tag, and ssh_key"}

# Assign arguments to variables
cd_time=$(date)                # Current date and time
openrc_sr=${1}                # OpenRC file for OpenStack credentials
tag_sr=${2}                   # Tag for identifying resources
ssh_key_path=${3}             # Path to the SSH key
no_of_servers=$(grep -E '[0-9]' servers.conf) # Number of servers required from servers.conf

# Source the OpenRC file to set environment variables
echo "${cd_time} Beginning deployment of $tag_sr using ${openrc_sr} for credentials."
source ${openrc_sr}
openstack token issue

# Define resource names with tag

natverk_namn="${tag_sr}_network"         # Network name
sr_subnet="${tag_sr}_subnet"             # Subnet name
sr_keypair="${tag_sr}_key"               # SSH keypair name
sr_router="${tag_sr}_router"             # Router name
sr_security_group="${tag_sr}_security_group" # Security group name
sr_haproxy_server="${tag_sr}_proxy"      # HAProxy server name
sr_bastion_server="${tag_sr}_bastion"    # Bastion server name
sr_server="${tag_sr}_server"             # Development server name

# Define configuration filenames

sshconfig="config"         # SSH config file
knownhosts="known_hosts"  # Known hosts file
hostsfile="hosts"         # Ansible inventory file
nodes_yaml="nodes.yaml"   # File for storing node IPs

# Check if the SSH keypair already exists

echo "$(date) Checking if ${sr_keypair} exists."
current_keypairs=$(openstack keypair list -f value --column Name)
if echo "${current_keypairs}" | grep -qFx "${sr_keypair}"; then
    echo "$(date) ${sr_keypair} already exists"
else 
    echo "$(date) ${sr_keypair} not found. Adding it now."
    openstack keypair create --public-key "${ssh_key_path}" "${sr_keypair}"
fi

#workflow is:

#1 Create a network
#2 Create a subnet inside that network
#3 Create a router
# Attach the subnet to the router (as an interface)
#4 Create a security group
#5 Set the router’s external gateway if it’s connecting to an external/public network

#1 Create a network
# Check if the network already exists
# create in the background

current_networks=$(openstack network list --tag "${tag_sr}" --column Name -f value 2>/dev/null)
if echo "${current_networks}" | grep -qFx "${natverk_namn}"; then
    echo "$(date) ${natverk_namn} already exists"
else
    echo "$(date) ${natverk_namn} not found. Creating it now."
    openstack network create --tag "${tag_sr}" "${natverk_namn}" -f json >/dev/null 2>&1
    echo "$(date) ${natverk_namn} created."
fi

#2 Create a subnet inside that network
# Check if the subnet already exists

current_subnets=$(openstack subnet list --tag "${tag_sr}" --column Name -f value 2>/dev/null)
if echo "${current_subnets}" | grep -qFx "${sr_subnet}"; then
    echo "$(date) ${sr_subnet} already exists"
else
    echo "$(date) ${sr_subnet} not found. Creating it now."
    openstack subnet create --subnet-range 10.10.0.0/27 \
        --allocation-pool start=10.10.0.10,end=10.10.0.30 \
        --tag "${tag_sr}" \
        --network "${natverk_namn}" \
        "${sr_subnet}" -f json >/dev/null 2>&1
    echo "$(date) ${sr_subnet} created."
fi

#3 Create a router
# Check if the router already exists

current_routers=$(openstack router list --tag "${tag_sr}" --column Name -f value 2>/dev/null)
if echo "${current_routers}" | grep -qFx "${sr_router}"; then
    echo "$(date) ${sr_router} already exists"
else
    echo "$(date) ${sr_router} not found. Creating it now."
    openstack router create --tag "${tag_sr}" "${sr_router}" >/dev/null 2>&1
    echo "$(date) ${sr_router} created. Configuring router."
    openstack router add subnet "${sr_router}" "${sr_subnet}" >/dev/null 2>&1
    openstack router set --external-gateway ext-net "${sr_router}" >/dev/null 2>&1
    echo "$(date) Router configuration complete."
fi

#4 Create a security group
# Check if the security group already exists

current_security_groups=$(openstack security group list --tag "${tag_sr}" -f value 2>/dev/null)
if [[ -z "${current_security_groups}" || ! "${current_security_groups}" == *"${sr_security_group}"* ]]; then
    echo "$(date) Adding security group and rules."
    openstack security group create --tag "${tag_sr}" "${sr_security_group}" -f json >/dev/null 2>&1
    openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 22 --protocol tcp --ingress "${sr_security_group}" >/dev/null 2>&1
    openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 5000 --protocol tcp --ingress "${sr_security_group}" >/dev/null 2>&1
    openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 6000 --protocol udp --ingress "${sr_security_group}" >/dev/null 2>&1
    openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 161 --protocol udp --ingress "${sr_security_group}" >/dev/null 2>&1
    openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 80 --protocol icmp --ingress "${sr_security_group}" >/dev/null 2>&1
    echo "$(date) Security group and rules added."
else
    echo "$(date) ${sr_security_group} already exists"
fi

# Clean up old configuration files
rm -f "$sshconfig" "$knownhosts" "$hostsfile" "$nodes_yaml"

# Retrieve list of unassigned floating IPs
unassigned_ips=$(openstack floating ip list --status DOWN -f value -c "Floating IP Address" 2>/dev/null)

# Check and display appropriate message
if [[ -n "$unassigned_ips" ]]; then
    echo "$(date) Here is the list of unassigned floating IPs:"
    echo "$unassigned_ips"
else
    echo "$(date) No unassigned floating IPs found."
fi

# Function to create and assign a server with a floating IP

create_server() {
    local server_name=$1
    local fip_var=$2
    local server_type=$3
    local fip

    if [[ "${existing_servers}" == *"${server_name}"* ]]; then
        echo "$(date) ${server_name} already exists"
    else
        if [[ -n "${unassigned_ips}" ]]; then
            fip=$(echo "${unassigned_ips}" | awk "NR==${fip_var}")
            if [[ -n "${fip}" ]]; then
                echo "$(date) Floating IP ${fip} available for the ${server_type} server."
            else
                echo "$(date) No pre-existing floating IP at position ${fip_var}. Creating new one."
                fip=$(openstack floating ip create ext-net -f json | jq -r '.floating_ip_address' 2>/dev/null)
            fi
        else
            echo "$(date) No unassigned floating IPs. Creating new one."
            fip=$(openstack floating ip create ext-net -f json | jq -r '.floating_ip_address' 2>/dev/null)
        fi

        echo "$(date) Launching ${server_name}."
        openstack server create --image "Ubuntu 20.04 Focal Fossa x86_64" \
            --key-name "${sr_keypair}" \
            --flavor "1C-1GB" \
            --network "${natverk_namn}" \
            --security-group "${sr_security_group}" \
            "${server_name}" >/dev/null 2>&1
       	echo "$(date) ${server_name} now launched."
       	
        # Wait a bit before adding floating IP to avoid API errors
        sleep 2

        openstack server add floating ip "${server_name}" "${fip}" >/dev/null 2>&1

        echo "$(date) Floating IP ${fip} assigned to ${server_name}."
    fi
}


# Create bastion and HAProxy servers
# call create function twice using IP above

# Create Bastion and HAProxy servers
create_server "${sr_bastion_server}" 1 "Bastion"
create_server "${sr_haproxy_server}" 2 "Proxy"

# Get list of active servers
existing_servers=$(openstack server list --status ACTIVE -f value -c Name)

# Count development servers (matching prefix)
devservers_count=$(echo "${existing_servers}" | grep -o "^${sr_server}" | wc -l)

# Scale up development servers
if (( no_of_servers > devservers_count )); then
    devservers_to_add=$(( no_of_servers - devservers_count ))
    echo "$(date) Creating ${devservers_to_add} additional development servers."

    while (( devservers_to_add > 0 )); do
        devserver_name="${sr_server}$(( RANDOM % 1000 + 100 ))"

        # Check for duplicate names
	if echo "${existing_servers}" | grep -q "^${devserver_name}$"; then
	    echo "$(date) Duplicate name found: ${devserver_name}. Skipping."
	    continue
	else
	    echo "$(date) No duplicate for ${devserver_name}. Proceeding to create."
	fi

        openstack server create --image "Ubuntu 20.04 Focal Fossa x86_64" \
            --key-name "${sr_keypair}" \
            --flavor "1C-1GB" \
            --network "${natverk_namn}" \
            --security-group "${sr_security_group}" \
            "${devserver_name}" >/dev/null 2>&1

        echo "$(date) ${devserver_name} created."
        existing_servers+=$'\n'"${devserver_name}"
        devservers_to_add=$(( devservers_to_add - 1 ))
    done

# Scale down development servers
elif (( no_of_servers < devservers_count )); then
    servers_to_delete=$(( devservers_count - no_of_servers ))
    echo "$(date) Deleting ${servers_to_delete} excess development servers."

    dev_servers_list=$(echo "${existing_servers}" | grep "^${sr_server}")

    for server_to_delete in $(echo "${dev_servers_list}" | head -n "${servers_to_delete}"); do
        openstack server delete "${server_to_delete}" >/dev/null 2>&1
        echo "$(date) Node ${server_to_delete} deleted."
    done
else
    echo "$(date) No changes needed. Desired number of development servers already active."
fi

# Generate SSH configuration file
bastionfip=$(openstack server list --name "${sr_bastion_server}" -c Networks -f value | grep -Po '\d+\.\d+\.\d+\.\d+' | awk 'NR==2')
haproxyfip=$(openstack server list --name "${sr_haproxy_server}" -c Networks -f value | grep -Po '\d+\.\d+\.\d+\.\d+' | awk 'NR==2')
ssh_key_sr=${ssh_key_path%.pub}  # Remove .pub from the SSH key path

echo "$(date) Generating SSH config file"
cat << EOF > $sshconfig
Host $sr_bastion_server
   User ubuntu
   HostName $bastionfip
   IdentityFile $ssh_key_sr
   UserKnownHostsFile /dev/null
   StrictHostKeyChecking no
   PasswordAuthentication no

Host $sr_haproxy_server
   User ubuntu
   HostName $haproxyfip
   IdentityFile $ssh_key_sr
   StrictHostKeyChecking no
   PasswordAuthentication no
   ProxyJump $sr_bastion_server
EOF

# Generate Ansible hosts file
echo "$(date) Generating Ansible hosts file"
cat << EOF > $hostsfile
[bastion]
$sr_bastion_server

[proxyserver]
$sr_haproxy_server

[webservers]
EOF

# List active servers and add them to the SSH config and hosts file

active_servers=$(openstack server list --status ACTIVE -f value -c Name | grep -oP "${tag_sr}_server([0-9]+)")
for server in $active_servers; do
    ip_address=$(openstack server list --name "$server" -c Networks -f value | grep -Po '\d+\.\d+\.\d+\.\d+')
    cat << EOF >> $sshconfig

Host $server
   User ubuntu
   HostName $ip_address
   IdentityFile $ssh_key_sr
   UserKnownHostsFile /dev/null
   StrictHostKeyChecking no
   PasswordAuthentication no
   ProxyJump $sr_bastion_server
EOF
    echo "$server" >> $hostsfile
    echo "$ip_address" >> $nodes_yaml
done

# Add Ansible variables to the hosts file
cat << EOF >> $hostsfile
[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=$ssh_key_sr
ansible_ssh_common_args=' -F $sshconfig '
EOF

# Run Ansible playbook
echo "$(date) Running ansible-playbook"
ansible-playbook -i "$hostsfile" site.yaml

# Wait for deployment to complete
sleep 5

# Check availability of the application on bastion
echo "$(date) Checking node availability at $bastionfip..."
http_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$bastionfip:5000")
echo "Node $bastionfip returned HTTP status: $http_status"


if [ "$http_status" -eq 200 ]; then
  echo "$(date) Bastion server is available and responding."
else
  echo "$(date) Bastion server is not available or returned status $http_status."
fi

# Report completion and duration
echo "$(date) Deployment done."
echo "Bastion IP address: $bastionfip"
echo "Proxy IP address: $haproxyfip"
duration=$SECONDS
echo "$((duration / 60)) minutes and $((duration % 60)) seconds used."

