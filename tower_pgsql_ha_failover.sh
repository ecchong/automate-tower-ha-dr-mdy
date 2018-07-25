#!/usr/bin/env bash

# This script runs setup for Ansible Tower.
# It determines how Tower is to be installed, gives the proper command,
# and then executes the command if asked.

# -------------
# Initial Setup
# -------------

# Cause exit codes to trickle through piping.
set -o pipefail

# When using an interactive shell, force colorized output from Ansible.
if [ -t "0" ]; then
    ANSIBLE_FORCE_COLOR=True
fi

# Set variables.
TIMESTAMP=$(date +"%F-%T")
LOG_DIR="/var/log/tower"
LOG_FILE="${LOG_DIR}/failover-${TIMESTAMP}.log"
TEMP_LOG_FILE='failover.log'

OPTIONS=""

# What playbook should be run?
# By default, this is setup.log, unless we are doing a backup
# (specified in the options).
PLAYBOOK="install.yml"

# -e bundle_install=false to override and disable bundle installer
OVERRIDE_BUNDLE_INSTALL=false

# --------------
# Usage
# --------------

function usage() {
    cat << EOF
Usage: $0 [Options]

Options:
  -c CURRENT_INVENTORY_FILE     Path to ansible inventory file
  -a HA_INVENTORY_FILE          Path to HA inventory file
  -b                    failback to original configuration
  -h                    Show this help message and exit

Ansible Options:
EOF
    exit 64
}


# --------------
# Option Parsing
# --------------
FAILBACK=0
SETUP_SHORTCUT=0
REPL_INSTALL_SKIP=0
# Process options to setup.sh
while getopts 'a:c:bxy' opt; do
    case ${opt} in
        c)
            echo $OPTARG
            CURRENT_INVENTORY_FILE=$(realpath $OPTARG)
            ;;
        a)
            HA_INVENTORY_FILE=$(realpath $OPTARG)
            ;;
        b)
            FAILBACK=1
            ;;
        x)
            SETUP_SHORTCUT=1
            ;;
        y)
            REPL_INSTALL_SKIP=1
            ;;
        *)
            usage
            ;;
    esac
done

if [ "${FAILBACK}" -eq "1" ]; then
    TMP=$CURRENT_INVENTORY_FILE
    CURRENT_INVENTORY_FILE=$HA_INVENTORY_FILE
    HA_INVENTORY_FILE=$TMP
fi

echo "CURRENT_INVENTORY_FILE ${CURRENT_INVENTORY_FILE}"
echo "HA_INVENTORY_FILE ${HA_INVENTORY_FILE}"
# Change to the running directory for tower conf file and inventory file
# defaults.
cd "$( dirname "${BASH_SOURCE[0]}" )"

# Sanity check: Test to ensure that an inventory file exists.
if [ ! -f "${CURRENT_INVENTORY_FILE}" ]; then
    cat << EOF
    No current inventory file could be found at ${CURRENT_INVENTORY_FILE}.
		echo "specify one manually with -c.
EOF
    usage
    exit 64
fi

# Sanity check: Test to ensure that an inventory file exists.
if [ ! -f "${HA_INVENTORY_FILE}" ]; then
    cat << EOF
    No current inventory file could be found at ${HA_INVENTORY_FILE}.
		echo "specify one manually with -a.
EOF
    usage
    exit 64
fi

export PYTHONUNBUFFERED=x
export ANSIBLE_FORCE_COLOR=$ANSIBLE_FORCE_COLOR
export ANSIBLE_ERROR_ON_UNDEFINED_VARS=True

echo "STOP TOWER SERVICES"
ansible-playbook -i "${CURRENT_INVENTORY_FILE}" -v \
                 tower_stop_services.yml 2>&1 | tee $TEMP_LOG_FILE

echo "PROMOTE THE HA/LOCAL DATABASE"
ansible-playbook -i "${CURRENT_INVENTORY_FILE}" -v \
    tower_pgsql_promote.yml -e promotion_type=local 2>&1 | tee $TEMP_LOG_FILE

if [ "${SETUP_SHORTCUT}" -eq "0" ]; then
  echo "RERUN THE INSTALLER TO POINT TO THE NEW DATABASE"
  ANSIBLE_SUDO=True ./setup.sh -i "${HA_INVENTORY_FILE}"
else
  echo "NO INSTALLER RUN.  ONLY UPDATE DATABASE SETTINGS"
  ansible-playbook -i "${HA_INVENTORY_FILE}" -v \
     tower_dbhost_update.yml 2>&1 | tee $TEMP_LOG_FILE
fi

echo "START TOWER SERVICE"
ansible-playbook -i "${HA_INVENTORY_FILE}" -v \
                tower_start_services.yml 2>&1 | tee $TEMP_LOG_FILE

echo "SETUP REPLICATION"
ansible-playbook -i "${HA_INVENTORY_FILE}" -v \
                tower_setup_replication.yml -e pgsqlrep_install_skip=${pgsqlrep_install_skip}  2>&1 | tee $TEMP_LOG_FILE

echo "CHECK REPLICATION"
ansible-playbook -i "${HA_INVENTORY_FILE}" -v \
                tower_check_replication.yml 2>&1 | tee $TEMP_LOG_FILE