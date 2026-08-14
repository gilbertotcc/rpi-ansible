#!/bin/sh
#
# Prints the ansible-vault password for this repository by retrieving it
# from gopass. Used as ANSIBLE_VAULT_PASSWORD_FILE (see .envrc) so
# ansible-playbook/ansible-vault never prompt interactively.
#
# See README.md's "Ansible Vault password" section.

GOPASS_SECRET="Devices/rpi-ansible-vault"

if ! command -v gopass >/dev/null 2>&1; then
  echo "error: gopass not found on PATH (https://www.gopass.pw/)." >&2
  echo "Install it, or point ANSIBLE_VAULT_PASSWORD_FILE (.envrc) at" >&2
  echo "your own password manager's equivalent script instead." >&2
  exit 1
fi

gopass show --password "${GOPASS_SECRET}"
