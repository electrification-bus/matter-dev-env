# Source this before running the playbooks:  source setup-env.sh
#
# Why this exists: if you already have ANSIBLE_CONFIG exported globally (common
# if you use Ansible for other projects), it WINS over the ansible.cfg sitting
# in this directory, and the playbook will not find inventory.ini. Ansible only
# auto-loads ./ansible.cfg when ANSIBLE_CONFIG is unset. Pointing it here is the
# reliable fix.
#
# If you do not have ANSIBLE_CONFIG set, you can skip this entirely and just run
# ansible-playbook from this directory.

_here="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
export ANSIBLE_CONFIG="$_here/ansible.cfg"
echo "ANSIBLE_CONFIG=$ANSIBLE_CONFIG"
unset _here
