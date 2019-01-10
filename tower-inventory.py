#!/usr/bin/env python

import json
import subprocess
import os
import argparse
import logging
import yaml


# run ansible-inventory on the correct inventory file
def _get_inventory(inv_file):

    ANS_INV_CMD = "ansible-inventory"
    ANS_INV_ARGS = ["--list", "--export"]

    if not os.path.exists(inv_file):
        raise Exception("Inventory file does not exist")

    inv_cmd = [ANS_INV_CMD] + ["-i", inv_file] + ANS_INV_ARGS
    inv = json.loads(subprocess.check_output(inv_cmd))

    # cleanup using ansible-inventory twice
    try:
        del inv['ungrouped']
        del inv['_meta']['ungrouped']
    except KeyError:
        pass

    return json.dumps(inv)


if __name__ == '__main__':

    parser = argparse.ArgumentParser()

    parser.add_argument('--list', action="store_true",
                    help="basic ansible inventory")

    parser.add_argument('--host', action="store",
                    help="basic ansible inventory")

    args = parser.parse_args()

    # assume inventory and vars files are at same path
    inv_path = os.path.dirname(os.path.abspath(__file__))

    # load tower vars file with info about failover configurations
    vars_tower_file = os.path.join(inv_path,"tower-vars.yml")
    if os.path.exists(vars_tower_file):
        with open(vars_tower_file) as tv:
            tower_inventory = yaml.load(tv.read())
    else:
        raise Exception(vars_tower_file + " must be present and well-formed YAML")

    # ensure tower vars file has a primary inventory file
    inv_pm_file = os.path.join(inv_path, tower_inventory.get("tower_inventory_pm"))
    if not os.path.exists(inv_pm_file):
        raise Exception(vars_tower_file + " must contain a tower_inventory_pm file")

    # ensure tower vars file has a ha and/or dr inventory file
    inv_ha_file = os.path.join(inv_path, tower_inventory.get("tower_inventory_ha"))
    inv_dr_file = os.path.join(inv_path, tower_inventory.get("tower_inventory_dr"))
    if not os.path.exists(inv_ha_file) and not os.path.exists(inv_dr_file):
        raise Exception(vars_tower_file + " must contain a tower_inventory_dr or tower_inventory_ha file")

    # ini file contents are used to determine which inventory file to load
    inv_ini_path = os.path.join(inv_path, '.tower_inventory.ini')

    # default to primary
    if not os.path.exists(inv_ini_path):
        if tower_inventory:
            inventory_file = inv_pm_file
    else:
        with open(inv_ini_path) as fh:
            inventory_file = fh.read()
            inventory_file = inventory_file.strip()
            inventory_file = os.path.join(inv_path, inventory_file)

    print _get_inventory(inventory_file)