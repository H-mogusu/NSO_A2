import os
import argparse
from jinja2 import Template

def main():
    # Setup command-line argument parsing
    parser = argparse.ArgumentParser(description='Generate an inventory file from a template.')
    parser.add_argument('ssh_key', help='Path to the SSH key file')
    args = parser.parse_args()

    # Read IPs from file
    with open('../storage/ips', 'r') as f:
        ips = [line.strip() for line in f.readlines()]

    bastion_ip = ips[0]
    proxy_ip = ips[1]
    service_ips = ips[2:]
    print(service_ips)

    # Read template
    with open('inventory_template.ini', 'r') as template_file:
        template_content = template_file.read()

    # Create a Jinja2 Template object
    template = Template(template_content)

    # Render the template with the variables including ssh_key
    inventory_content = template.render(
        bastion_ip=bastion_ip,
        proxy_ip=proxy_ip,
        service_ips=service_ips,
        ssh_key=args.ssh_key
    )

    # Write the inventory file
    with open('inventory.ini', 'w') as inventory_file:
        inventory_file.write(inventory_content)

    print("Inventory file generated: inventory.ini")

if __name__ == '__main__':
    main()
