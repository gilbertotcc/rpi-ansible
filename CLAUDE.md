# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What this is

Ansible repository that configures personal Raspberry Pi boards on
Debian stable: a Raspberry Pi 4 (RPI4), plus a Raspberry Pi 3 (RPI3) as
a second, lighter-weight board. RPI4 also runs a single-node Kubernetes
cluster powered by [k3s](https://k3s.io/). Forked from
[iamleot/rpi-ansible](https://github.com/iamleot/rpi-ansible).
`hosts.ini` defines two groups — `rpi4` and `rpi3` — both connected to
as `root` (see `ansible.cfg`). `playbook.yml` targets `hosts: all`; most
roles apply identically to both hosts, but `roles/zram` and `roles/k3s`
are gated to the `rpi4` group only, via
`when: inventory_hostname in groups['rpi4']` on those two role entries
in `playbook.yml`'s `roles:` list — RPI3's more limited hardware runs
neither zram-backed swap nor a k3s node. Per-host values (hostname,
WiFi static IP) live in `group_vars/rpi4/` and `group_vars/rpi3/`; WiFi
SSID/PSK are the same real network for both boards, so they live in
`group_vars/all/` instead. _Last updated: 2026-08-19._

## Commands

All common tasks are wired through `make` (`Makefile`):

```sh
make check          # runs yamllint + syntax-check + ansible-lint (the full CI gate)
make yamllint       # yamllint . 
make syntax-check   # ansible-playbook --syntax-check against playbook.yml
make ansible-lint   # ansible-lint
make run            # ansible-playbook --verbose playbook.yml (applies config to the real RPIs)
```

Run `make check` before considering any change to `playbook.yml`, `roles/*/tasks/*.yml`,
or lint configs complete — this is exactly what the `ansible.yaml` CI workflow runs.

`group_vars/all/wireless.yml`, `group_vars/rpi4/wireless.yml`, and
`group_vars/rpi3/wireless.yml` hold vault-encrypted WiFi credentials
(see `roles/wireless` below), so `make run` needs a vault password to
decrypt them. With
`.envrc`/`scripts/ansible-vault-password.sh` set up (direnv + gopass —
see the "Ansible Vault password" section of `README.md`), plain
`make run` works out of the box.

There is no test suite; correctness is validated via syntax-check + ansible-lint
(structural/style) and via `conftest` in CI (policy checks against
`.github` using an external policy bundle, see `.github/workflows/conftest.yaml`).

## Architecture

- `playbook.yml` is the single entrypoint. It targets `hosts: all` and applies
  roles from `roles/` **in a fixed order** via a `roles:` list, each
  responsible for one concern:
  1. `roles/packages` — apt upgrade everything (gated by `packages_update`)
     and install the package list (`packages_needed_packages`)
  2. `roles/journald` — cap journald's on-disk footprint via
     `roles/journald/templates/journald.conf.j2`, so logs don't grow
     unbounded on the microSD
  3. `roles/zram` — configure zram-backed swap via
     systemd-zram-generator, giving this low-RAM board memory headroom
     without writing swap to the microSD (RPI4 only — gated via `when:`
     in `playbook.yml`)
  4. `roles/network` — set hostname from the `network_hostname` var
     (`group_vars/rpi4/network.yml`, `group_vars/rpi3/network.yml`)
  5. `roles/wireless` — configure `wlan0` via ifupdown + `wpasupplicant`
     (`wireless_enabled`, defaults to `false` as a safe fallback; both
     `group_vars/rpi4/wireless.yml` and `group_vars/rpi3/wireless.yml`
     set it `true` and supply that host's static
     `wireless_address`/`wireless_gateway`, since WiFi is each board's
     primary network connection; the shared `wireless_ssid`/`wireless_psk`
     live in `group_vars/all/wireless.yml` instead). Also installs
     `ifupdown` itself (some base images run
     `systemd-networkd` instead and lack it — installing it only adds a
     `wlan0` stanza, `eth0` stays under `systemd-networkd`),
     `firmware-brcm80211`, and `wireless-regdb` — the latter two aren't
     guaranteed present on every base image, and their absence can
     silently prevent `wpa_supplicant` from bringing the interface up.
  6. `roles/dns_resolver` — install/enable the DNS resolver
     (`dns_resolver_package`/`dns_resolver_service`, default `unbound`),
     point `/etc/resolv.conf` at it
  7. `roles/wireguard` — install WireGuard, generate keys idempotently (uses
     `creates:` guards)
  8. `roles/k3s` — install/upgrade k3s to the version pinned by
     `k3s_version` in `playbook.yml`, using
     `roles/k3s/templates/k3s-config.yaml.j2` (RPI4 only — gated via
     `when:` in `playbook.yml`)
- Order matters: later roles assume earlier ones already ran (packages
  installed, hostname set, etc.). When adding a new concern, add a new
  `roles/<name>/` directory (with `tasks/main.yml` and, as needed,
  `defaults/main.yml`, `files/`, `meta/main.yml`) and reference it from
  `playbook.yml`'s `roles:` list in the appropriate position, rather than
  growing an existing role's tasks with unrelated work.
- A role that needs to behave differently per host (not just per group)
  gates itself with `when: inventory_hostname in groups['<group>']` on
  its `roles:` list entry (see `zram`/`k3s` above) rather than an
  in-role conditional, keeping the host/group logic visible in one place.
- A role that requires a value to be explicitly set per host (rather than
  falling back to a shared default) defines it as an empty string in
  `defaults/main.yml` and asserts it's non-empty as its first task
  (`delegate_to: localhost`, see `roles/network` and `roles/wireless`) —
  this fails fast with a clear message instead of silently applying an
  empty/wrong value.
- Each role's `files/` holds static files pushed verbatim to the Pi via
  `ansible.builtin.copy` (currently just `resolv.conf`); `templates/`
  holds Jinja2 files rendered via `ansible.builtin.template` for values
  that vary (journald limits, zram config, wlan0, k3s config).
- `wireless_ssid`/`wireless_psk` (used by `roles/wireless`) live in
  committed `group_vars/all/wireless.yml`, shared by both boards since
  they're on the same real WiFi network, encrypted per-variable via
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
