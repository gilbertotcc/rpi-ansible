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
status=$?

case "${status}" in
  0) ;;
  10)
    echo "error: gopass secret '${GOPASS_SECRET}' not found." >&2
    echo "Create it with: gopass insert ${GOPASS_SECRET}" >&2
    ;;
  11)
    # gopass has been observed returning 11 both for "not found" and for
    # actual decrypt failures (e.g. locked GPG key) - don't guess which.
    echo "error: gopass could not retrieve '${GOPASS_SECRET}'." >&2
    echo "Either it doesn't exist yet (gopass insert ${GOPASS_SECRET})" >&2
    echo "or your GPG key needs to be unlocked. Run" >&2
    echo "'gopass show ${GOPASS_SECRET}' directly to see which." >&2
    ;;
  *)
    echo "error: gopass exited ${status} retrieving '${GOPASS_SECRET}'." >&2
    echo "Run 'gopass show ${GOPASS_SECRET}' directly to see why." >&2
    ;;
esac

exit "${status}"
