# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What this is

Ansible repository that configures a personal single-node Kubernetes cluster
(powered by [k3s](https://k3s.io/)) on a Raspberry Pi 4 running Debian stable.
Forked from [iamleot/rpi-ansible](https://github.com/iamleot/rpi-ansible).
There is exactly one target host, defined in `hosts.ini`, connected to as
`root` (see `ansible.cfg`).

## Commands

All common tasks are wired through `make` (`Makefile`):

```sh
make check          # runs yamllint + syntax-check + ansible-lint (the full CI gate)
make yamllint       # yamllint . 
make syntax-check   # ansible-playbook --syntax-check against playbook.yml
make ansible-lint   # ansible-lint
make run            # ansible-playbook --verbose playbook.yml (applies config to the real RPI)
```

Run `make check` before considering any change to `playbook.yml`, `roles/*/tasks/*.yml`,
or lint configs complete — this is exactly what the `ansible.yaml` CI workflow runs.

Once `group_vars/rpi/wireless.yml` exists (see `roles/wireless` below),
`make run` needs a vault password to decrypt it:
`make run ANSIBLE_PLAYBOOK="ansible-playbook --ask-vault-pass"`. With
`.envrc`/`scripts/ansible-vault-password.sh` set up (direnv + gopass —
see the "Ansible Vault password" section of `README.md`).

There is no test suite; correctness is validated via syntax-check + ansible-lint
(structural/style) and via `conftest` in CI (policy checks against
`.github` using an external policy bundle, see `.github/workflows/conftest.yaml`).

## Architecture

- `playbook.yml` is the single entrypoint. It targets `hosts: all` and applies
  roles from `roles/` **in a fixed order** via a `roles:` list, each
  responsible for one concern:
  1. `roles/packages` — apt upgrade everything (gated by `packages_update`)
     and install the package list (`packages_needed_packages`)
  2. `roles/network` — set hostname from `roles/network/files/hostname`
  3. `roles/wireless` — configure `wlan0` via ifupdown + `wpasupplicant`
     (`wireless_enabled`, defaults to `false` as a safe fallback; the
     committed `group_vars/rpi/wireless.yml` sets it `true` since WiFi is
     this board's primary network connection)
  4. `roles/dns_resolver` — install/enable the DNS resolver
     (`dns_resolver_package`/`dns_resolver_service`, default `unbound`),
     point `/etc/resolv.conf` at it
  5. `roles/wireguard` — install WireGuard, generate keys idempotently (uses
     `creates:` guards)
  6. `roles/k3s` — install/upgrade k3s to the version pinned by
     `k3s_version` in `playbook.yml`, using
     `roles/k3s/files/k3s-config.yaml`
- Order matters: later roles assume earlier ones already ran (packages
  installed, hostname set, etc.). When adding a new concern, add a new
  `roles/<name>/` directory (with `tasks/main.yml` and, as needed,
  `defaults/main.yml`, `files/`, `meta/main.yml`) and reference it from
  `playbook.yml`'s `roles:` list in the appropriate position, rather than
  growing an existing role's tasks with unrelated work.
- Each role's `files/` holds static files pushed verbatim to the Pi via
  `ansible.builtin.copy` (hostname, k3s config, resolv.conf).
- `wireless_ssid`/`wireless_psk` (used by `roles/wireless`) live in a
  committed `group_vars/rpi/wireless.yml`, encrypted per-variable via
  `ansible-vault encrypt_string` rather than whole-file vault encryption,
  so `make check`/CI can parse the file with no vault password available.
  See the "WiFi network" section of `README.md` for the exact commands.
- `.envrc` and `scripts/ansible-vault-password.sh` give non-interactive vault
  password delivery (`ANSIBLE_VAULT_PASSWORD_FILE`) via direnv + gopass.
- Values a role's tasks may need to vary (package lists, the DNS resolver
  package/service name, etc.) live in that role's `defaults/main.yml`
  rather than being hardcoded in `tasks/main.yml`.
- `k3s_version` (in `playbook.yml`) is validated by an `assert` in
  `roles/k3s/tasks/main.yml` against `v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+`;
  the task compares the installed version to it and only reinstalls on
  mismatch. Bump this var to upgrade k3s; valid channel/version values are
  listed at <https://update.k3s.io/v1-release/channels>.
- Nearly every task uses `become: true` and guards apt cache updates with
  `cache_valid_time: 3600`, following the existing pattern for any new apt-based
  task.
- Every role has a `meta/main.yml` with `dependencies: []` — roles are
  self-contained and don't depend on each other via Ansible role
  dependencies; ordering between them is expressed solely by their position
  in `playbook.yml`'s `roles:` list.

## CI (GitHub Actions, all under `.github/workflows/`)

- `ansible.yaml` — runs `make check` on push to `main` and on PRs.
- `conftest.yaml` — runs `conftest` against `.github` using an external,
  personal policy bundle (`iamleot/conftest-policies`), on push to `main` and PRs.
- `check-markdown-files.yml` — `markdownlint-cli2` + `lychee` link checking,
  scoped to `**.md` changes.
- Dependency updates are handled by both Dependabot (`.github/dependabot.yml`,
  GitHub Actions only) and Renovate (`renovate.json`, which also has a custom
  regex manager to track the `CONFTEST_VERSION` pin inside the workflow YAML
  files).

## Conventions worth preserving

- Every task in `roles/*/tasks/main.yml` has a trailing-period, capitalized
  `name:` (e.g. `Install unbound if needed.`) — match this style for new
  tasks. Every `tasks/main.yml` starts with a `---` and a short
  `#`-comment block describing the role's purpose.
  Idempotency-sensitive shell steps use `creates:` / `changed_when:` rather than
  free-running shell commands.
- Markdown must pass `markdownlint-cli2` (`.markdownlint-cli2.yaml`: ATX
  headers, 80-char line length except in tables/code blocks) and `lychee`
  link checking (add unreachable/intentional URLs to `.lycheeignore` rather
  than disabling the check).
