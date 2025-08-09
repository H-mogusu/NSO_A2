#!/bin/bash

# === Argument Validation ===
# Ensure three positional arguments are provided: openrc file, tag, and ssh key path.
: ${1:?" Please specify the openrc, tag, and ssh_key"}
: ${2:?" Please specify the openrc, tag, and ssh_key"}
: ${3:?" Please specify the openrc, tag, and ssh_key"}

# Capture the current timestamp
cd_time=$(date)

# === Variable Assignments ===
openrc_sr=${1}     # OpenStack credentials file (OpenRC)
tag_sr=${2}        # Project-specific tag for resource identification
ssh_key_path=${3}  # SSH public key path

# Remove the `.pub` extension to get the private key path
ssh_key_sr=${ssh_key_path::-4}

# Define names for OpenStack resources based on the tag
natverk_namn="${2}_network"
sr_subnet="${2}_subnet"
sr_keypair="${2}_key"
sr_router="${2}_router"
sr_security_group="${2}_security_group"
sr_haproxy_server="${2}_proxy"
sr_bastion_server="${2}_bastion"
sr_server="${2}_server"

# Define file names for generated config and inventory
sshconfig="config"
knownhosts="known_hosts"
hostsfile="hosts"
nodes_yaml="nodes.yaml"

# Ansible run status flag (0 = no change, 1 = changes detected)
run_status=0

# Log startup message with timestamp
echo "$(date) Running operate mode for tag: $tag_sr using $openrc_sr for credentials"

# Source OpenStack credentials
source $openrc_sr

# === Function: generate_config ===
# Generates SSH configuration, Ansible inventory, and nodes list based on current server state.
generate_config(){
    # Retrieve the floating IPs for bastion and HAProxy servers
    bastionfip=$(openstack server list --name $sr_bastion_server -c Networks -f value | grep -Po '\d+\.\d+\.\d+\.\d+' | awk 'NR==2')
    haproxyfip=$(openstack server list --name $sr_haproxy_server -c Networks -f value | grep -Po '\d+\.\d+\.\d+\.\d+' | awk 'NR==2')
       
    echo "$(date) Generating config file"

    # Generate SSH config for Bastion host
    echo "Host $sr_bastion_server" >> $sshconfig
    echo "   User ubuntu" >> $sshconfig
    echo "   HostName $bastionfip" >> $sshconfig
    echo "   IdentityFile $ssh_key_sr" >> $sshconfig
    echo "   UserKnownHostsFile /dev/null" >> $sshconfig
    echo "   StrictHostKeyChecking no" >> $sshconfig
    echo "   PasswordAuthentication no" >> $sshconfig
    echo " " >> $sshconfig

    # Generate SSH config for HAProxy server via Bastion
    echo "Host $sr_haproxy_server" >> $sshconfig
    echo "   User ubuntu" >> $sshconfig
    echo "   HostName $haproxyfip" >> $sshconfig
    echo "   IdentityFile $ssh_key_sr" >> $sshconfig
    echo "   StrictHostKeyChecking no" >> $sshconfig
    echo "   PasswordAuthentication no" >> $sshconfig
    echo "   ProxyJump $sr_bastion_server" >> $sshconfig

    # Generate Ansible inventory groups
    echo "[bastion]" >> $hostsfile
    echo "$sr_bastion_server" >> $hostsfile
    echo " " >> $hostsfile
    echo "[proxyserver]" >> $hostsfile
    echo "$sr_haproxy_server" >> $hostsfile   
    echo " " >> $hostsfile
    echo "[webservers]" >> $hostsfile

    # List all active application servers with IPs and generate their SSH config
    active_servers=$(openstack server list --status ACTIVE -f value -c Name | grep -oP "${tag_sr}"'_server([0-9]+)')

    for server in $active_servers; do
        ip_address=$(openstack server list --name $server -c Networks -f value | grep -Po  '\d+\.\d+\.\d+\.\d+')
        
        # Add SSH config entry
        echo " " >> $sshconfig
        echo "Host $server" >> $sshconfig
        echo "   User ubuntu" >> $sshconfig
        echo "   HostName $ip_address" >> $sshconfig
        echo "   IdentityFile $ssh_key_sr" >> $sshconfig
        echo "   UserKnownHostsFile=~/dev/null" >> $sshconfig
        echo "   StrictHostKeyChecking no" >> $sshconfig
        echo "   PasswordAuthentication no" >> $sshconfig
        echo "   ProxyJump $sr_bastion_server" >> $sshconfig 

        # Append to Ansible hosts inventory
        echo "$server" >> $hostsfile

        # Record IP addresses in YAML-like list
        echo "$ip_address" >> $nodes_yaml
    done

    echo " " >> $hostsfile
    echo "[all:vars]" >> $hostsfile
    echo "ansible_user=ubuntu" >> $hostsfile
    echo "ansible_ssh_private_key_file=$ssh_key_sr" >> $hostsfile
    echo "ansible_ssh_common_args=' -F $sshconfig '" >> $hostsfile
}

# === Function: delete_config ===
# Removes previously generated configuration files
delete_config(){
    [[ -f "$hostsfile" ]] && rm "$hostsfile"
    [[ -f "$sshconfig" ]] && rm "$sshconfig"
    [[ -f "$knownhosts" ]] && rm "$knownhosts"
    [[ -f "$nodes_yaml" ]] && rm "$nodes_yaml"
}

# === Main Monitoring Loop ===
# Periodically ensures required number of servers are active, reconciles the state, and runs Ansible playbooks

while true
do
    a=true

    # Get desired number of servers from servers.conf
    no_of_servers=$(grep -E '[0-9]' servers.conf)

    while [ "$a" = true ]
    do
        echo "$(date) We require $no_of_servers nodes as specified in servers.conf"

        # Count current active servers
        existing_servers=$(openstack server list --status ACTIVE --column Name -f value)
        devservers_count=$(grep -c $sr_server <<< $existing_servers)
        echo "$(date) $devservers_count nodes available."

        # Count all servers with the project-specific prefix
        total_servers=$(openstack server list --column Name -f value)
        total_count=$(grep -c $sr_server <<< $total_servers)

        if (($no_of_servers > $devservers_count)); then
            # If fewer servers than required, provision additional servers
            devservers_to_add=$(($no_of_servers - $devservers_count))
            echo "$(date) Creating $devservers_to_add more nodes ..."
            v=$[ $RANDOM % 100 + 10 ]
            devserver_name=${sr_server}${v}
            servernames=$(openstack server list --status ACTIVE -f value -c Name)

            # Ensure server names are unique
            check_name=0
            until [[ check_name -eq 1 ]]
            do  
                if echo "${servernames}" | grep -qFx ${devserver_name}; then
                    v=$[ $RANDOM % 100 + 10 ]
                    devserver_name=${sr_server}${v}
                else
                    check_name=1
                fi
            done

            run_status=1

            while [ $devservers_to_add -gt 0 ]
            do
                # Provision the server
                server_create=$(openstack server create --image "Ubuntu 20.04 Focal Fossa x86_64"  $devserver_name --key-name "$sr_keypair" --flavor "1C-1GB-20GB" --network "$natverk_namn" --security-group "$sr_security_group")
                echo "$(date) Created $devserver_name node"
                ((devservers_to_add--))

                # Wait until server becomes ACTIVE
                active=false
                while [ "$active" = false ]; do
                    server_status=$(openstack server show "$devserver_name" -f value -c status)
                    [[ "$server_status" == "ACTIVE" ]] && active=true
                done

                # Prepare next unique name
                servernames=$(openstack server list --status ACTIVE -f value -c Name)
                v=$[ $RANDOM % 100 + 10 ]
                devserver_name=${sr_server}${v}

                check_name=0
                until [[ check_name -eq 1 ]]
                do  
                    if echo "${servernames}" | grep -qFx ${devserver_name}; then
                        v=$[ $RANDOM % 100 + 10 ]
                        devserver_name=${sr_server}${v}
                    else
                        check_name=1
                    fi
                done

            done

        elif (( $no_of_servers < $devservers_count )); then
            # If more servers than required, remove extras
            devservers_to_remove=$(($devservers_count - $no_of_servers))
            sequence1=0
            echo "$(date) Removing $devservers_to_remove nodes."
            run_status=1
            while [[ $sequence1 -lt $devservers_to_remove ]]; do
                server_to_delete=$(openstack server list --status ACTIVE -f value -c Name | grep -m1 -oP "${tag_sr}"'_server([0-9]+)')
                deleted_server=$(openstack server delete "$server_to_delete" --wait)
                echo "$(date) Removed $server_to_delete node"
                ((sequence1++))
            done
        else
            echo "$(date) Required number of nodes are present."
        fi

        # Validate node count
        current_servers=$(openstack server list --status ACTIVE --column Name -f value)
        new_count=$(grep -c $sr_server <<< $current_servers)

        if [[ "$no_of_servers" == "$new_count" && "$run_status" -eq 0 ]]; then
            echo "$(date) Sleeping 30 seconds. Press CTRL-C if you wish to exit."
        else
            # If changes occurred, regenerate configs and run Ansible
            delete_config
            generate_config
            echo "$(date) Running ansible-playbook"
            ansible-playbook -i "$hostsfile" site.yaml
            sleep 5
            run_status=0
            echo "$(date) Checking node availability through the ${sr_bastion_server}."
            curl http://$bastionfip:5000
            echo "$(date) Done, the solution has been deployed."
            echo "$(date) Sleeping 30 seconds. Press CTRL-C if you wish to exit."
        fi

        a=false
    done

    # Wait before next reconciliation loop
    sleep 30
done

