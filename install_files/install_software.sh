pip3 install jinja2
python3 inventory_generator.py ../storage/$1
scp -i ../storage/$1 -o "StrictHostKeyChecking no" ../storage/$1 ubuntu@$2:./
ansible-playbook -i inventory.ini install_soft.yaml